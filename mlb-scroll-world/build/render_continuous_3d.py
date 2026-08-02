#!/usr/bin/env python3
"""Render a continuous closed-loop flight with real camera parallax.

Two methods share the same pose path:

  --method plane   ground-plane + backdrop homography (no ML)
  --method depth   depth-aware warp (needs build/depth/*.npy)

Frames are written as they are produced (streaming) so peak RAM stays modest.
Shared boundary frames are verified against the first writer; later writers must
match within 0.5 mean abs delta.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, "build")
import timeline as tl  # noqa: E402
import camera3d as cam  # noqa: E402
import depth as depth_mod  # noqa: E402


def render_frame(method, scene, pose, bases_img, bases_rgb, depths):
    park = scene["park"]
    if method == "plane":
        return cam.grade(cam.render_plane(bases_img[park], pose))
    return cam.grade(cam.render_depth(bases_rgb[park], depths[park], pose))


def interpolate_pose(a, b, t):
    e = cam.smoother(t)
    return {k: cam.lerp(a[k], b[k], e) for k in a}


def connector_frame(method, a, b, t, bases_img, bases_rgb, depths):
    """Travel shot joining scene a to scene b.

    Same-park (approach→arrival): pose interpolation on one photo.
    Cross-park: pull-back + approach dissolve, flat at both ends for seams.
    """
    pose_a_end = cam.pose_at_end(a)
    pose_b_start = cam.pose_at_start(b)

    if tl.same_park(a, b):
        pose = interpolate_pose(pose_a_end, pose_b_start, t)
        return render_frame(method, a, pose, bases_img, bases_rgb, depths)

    e = cam.smoother(t)
    dx, dy = a["drift"]
    out = dict(pose_a_end)
    out["zoom"] = cam.lerp(pose_a_end["zoom"], 1.00, e)
    out["cx"] = cam.lerp(pose_a_end["cx"], 0.5, e) + dx * e
    out["cy"] = cam.lerp(pose_a_end["cy"], 0.5, e) + dy * e
    out["tx"] = cam.lerp(pose_a_end["tx"], 0.0, e)
    out["ty"] = cam.lerp(pose_a_end["ty"], 0.0, e)
    out["tz"] = cam.lerp(pose_a_end["tz"], 0.0, e)
    out["yaw"] = cam.lerp(pose_a_end["yaw"], 0.0, e)

    inn = dict(pose_b_start)
    inn["zoom"] = cam.lerp(1.00, pose_b_start["zoom"], e)

    alpha = cam.smoother((t - 0.16) / 0.68)
    if alpha <= 0.0:
        return render_frame(method, a, out, bases_img, bases_rgb, depths)
    if alpha >= 1.0:
        return render_frame(method, b, inn, bases_img, bases_rgb, depths)
    fa = render_frame(method, a, out, bases_img, bases_rgb, depths).astype(np.float32)
    fb = render_frame(method, b, inn, bases_img, bases_rgb, depths).astype(np.float32)
    return np.clip(fa + (fb - fa) * alpha, 0, 255).astype(np.uint8)


class FrameStore:
    """Stream frames to disk; keep only claimed indices for seam checks."""

    def __init__(self, out: Path):
        self.out = out
        self.claimed = {}  # abs_i -> path (already written)
        self.boundary = {}  # abs_i -> ndarray kept for conflict checks

    def put(self, abs_i: int, arr: np.ndarray, keep: bool = False):
        path = self.out / f"frame-{abs_i:06d}.jpg"
        if abs_i in self.claimed:
            prev = self.boundary.get(abs_i)
            if prev is None:
                prev = np.asarray(Image.open(self.claimed[abs_i]))
            delta = np.abs(prev.astype(np.int16) - arr.astype(np.int16)).mean()
            if delta > 0.5:
                raise SystemExit(f"conflict at frame {abs_i}: δ={delta:.3f}")
            return delta
        Image.fromarray(arr).save(path, quality=92, optimize=True)
        self.claimed[abs_i] = path
        if keep:
            self.boundary[abs_i] = arr
        return 0.0

    def get(self, abs_i: int) -> np.ndarray:
        if abs_i in self.boundary:
            return self.boundary[abs_i]
        return np.asarray(Image.open(self.out / f"frame-{abs_i:06d}.jpg"))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--method", choices=("plane", "depth"), required=True)
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    out = args.out or Path(f"build/sequence-{args.method}")
    out.mkdir(parents=True, exist_ok=True)
    # Clear prior frames so a partial re-run can't mix generations.
    for old in out.glob("frame-*.jpg"):
        old.unlink()

    park_slugs = sorted({s["park"] for s in tl.SCENES})
    bases_img = {
        s: Image.open(f"assets/src/{s}.jpg").convert("RGB") for s in park_slugs
    }
    bases_rgb = {s: np.asarray(im) for s, im in bases_img.items()}
    depths = {}
    if args.method == "depth":
        print("loading depth maps…")
        for s in park_slugs:
            depths[s] = depth_mod.load_or_compute(s)

    print(f"rendering {tl.LOOP_FRAMES} frames → {out}/  method={args.method}")
    t0 = time.time()
    store = FrameStore(out)

    # Boundary indices that connectors will re-touch: dive ends and dive starts.
    boundaries = set()
    for i in range(tl.N):
        ds, de = tl.dive_range(i)
        boundaries.add(ds)
        boundaries.add(de - 1)
    boundaries.add(tl.LOOP_FRAMES - 1)

    for i, scene in enumerate(tl.SCENES):
        start, end = tl.dive_range(i)
        for local, abs_i in enumerate(range(start, end)):
            t = local / (tl.DIVE_FRAMES - 1)
            pose = cam.dive_pose(scene, t)
            arr = render_frame(
                args.method, scene, pose, bases_img, bases_rgb, depths)
            store.put(abs_i, arr, keep=(abs_i in boundaries))
        print(f"  dive[{scene['slug']}] done  "
              f"({time.time() - t0:.0f}s)")

    for i in range(tl.N):
        a, b = tl.SCENES[i], tl.SCENES[(i + 1) % tl.N]
        start, end = tl.conn_range(i)
        for local, abs_i in enumerate(range(start, end)):
            t = local / (tl.CONN_FRAMES - 1)
            arr = connector_frame(
                args.method, a, b, t, bases_img, bases_rgb, depths)
            # Last connector frame is the loop-close index; also a boundary.
            store.put(abs_i, arr, keep=(abs_i in boundaries))
        print(f"  conn[{i}] {a['slug']}→{b['slug']} done  "
              f"({time.time() - t0:.0f}s)")

    last = tl.LOOP_FRAMES - 1
    d = np.abs(
        store.get(0).astype(np.int16) - store.get(last).astype(np.int16)).mean()
    print(f"loop close δ(frame 0, frame {last}) = {d:.4f}")
    if d > 0.5:
        # Force exact close.
        Image.fromarray(store.get(0)).save(
            out / f"frame-{last:06d}.jpg", quality=92, optimize=True)
        print("  forced frame[last] = frame[0] for exact loop close")
        d = 0.0

    missing = [i for i in range(tl.LOOP_FRAMES)
               if not (out / f"frame-{i:06d}.jpg").exists()]
    if missing:
        raise SystemExit(f"missing {len(missing)} frames, e.g. {missing[:5]}")

    for i, scene in enumerate(tl.SCENES):
        start, _ = tl.dive_range(i)
        store.get(start)  # ensure readable
        Image.fromarray(store.get(start)).save(
            f"assets/{scene['slug']}.jpg", quality=88)
    Image.fromarray(store.get(0)).save("assets/home.jpg", quality=88)

    manifest = {
        "source": f"synthetic-3d-{args.method}",
        "fps": tl.FPS,
        "width": tl.OUT_W,
        "height": tl.OUT_H,
        "loop_frames": tl.LOOP_FRAMES,
        "dive_frames": tl.DIVE_FRAMES,
        "conn_frames": tl.CONN_FRAMES,
        "scenes": [s["slug"] for s in tl.SCENES],
        "pattern": "frame-%06d.jpg",
        "loop_close_delta": float(d),
        "elapsed_s": round(time.time() - t0, 1),
    }
    (out / "MANIFEST.json").write_text(json.dumps(manifest, indent=2))
    print(f"done — {tl.LOOP_FRAMES} frames in {time.time() - t0:.0f}s, "
          f"loop δ={d:.4f}")


if __name__ == "__main__":
    main()
