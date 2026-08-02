#!/usr/bin/env python3
"""Render a continuous closed-loop flight as a frame sequence (synthetic).

Stands in for an Earth Studio PNG dump so the slicer / page wiring can be
verified end-to-end before real 3D frames arrive. Uses the same photo-crop
camera as render_flight.py, plus a wrap connector Camden → Fenway so the
final unique frame equals frame 0.

Writes:
  build/sequence/frame-000000.jpg … frame-000750.jpg   (LOOP_FRAMES frames)
  build/sequence/MANIFEST.json
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, "build")
import timeline as tl  # noqa: E402
import render_flight as rf  # noqa: E402

OUT = Path("build/sequence")
OUT.mkdir(parents=True, exist_ok=True)

# Map timeline parks onto render_flight's scene shape.
SCENES = [
    {"slug": p["slug"], "focal": p["photo_focal"], "drift": p["photo_drift"]}
    for p in tl.PARKS
]


def write_frame(i, arr):
    Image.fromarray(arr).save(OUT / f"frame-{i:06d}.jpg", quality=92, optimize=True)


def main():
    bases = {
        s["slug"]: Image.open(f"assets/src/{s['slug']}.jpg").convert("RGB")
        for s in SCENES
    }
    print(f"rendering {tl.LOOP_FRAMES} frames → {OUT}/")

    # Precompute every dive and connector into a dict keyed by absolute index.
    # Shared boundary frames are written once; later writers must match exactly.
    frames = {}

    for i, scene in enumerate(SCENES):
        start, end = tl.dive_range(i)
        base = bases[scene["slug"]]
        for local, abs_i in enumerate(range(start, end)):
            t = local / (tl.DIVE_FRAMES - 1)
            arr = rf.grade(np.asarray(rf.sample(base, *rf.dive_camera(scene, t))))
            if abs_i in frames:
                delta = np.abs(frames[abs_i].astype(np.int16) - arr.astype(np.int16)).mean()
                if delta > 0:
                    raise SystemExit(f"dive[{scene['slug']}] conflict at {abs_i}: δ={delta}")
            else:
                frames[abs_i] = arr

    for i in range(tl.N):
        a, b = SCENES[i], SCENES[(i + 1) % tl.N]
        start, end = tl.conn_range(i)
        for local, abs_i in enumerate(range(start, end)):
            t = local / (tl.CONN_FRAMES - 1)
            arr = rf.connector_frame(a, b, bases[a["slug"]], bases[b["slug"]], t)
            if abs_i in frames:
                delta = np.abs(frames[abs_i].astype(np.int16) - arr.astype(np.int16)).mean()
                # Boundary frames must match the dive they share.
                if delta > 0:
                    raise SystemExit(
                        f"conn[{i}] conflict at {abs_i} (local {local}): δ={delta}")
            else:
                frames[abs_i] = arr

    # The wrap connector's last frame lands on dive[0] frame 0 by construction
    # (connector_frame at t=1 samples the next park at Z_WIDE / centre). Confirm
    # the loop closes: last unique index == first frame.
    last = tl.LOOP_FRAMES - 1
    if last not in frames:
        raise SystemExit(f"missing loop-close frame {last}")
    # Frame `last` should equal frame 0. The connector produces fenway-wide;
    # dive[0] frame 0 is also fenway-wide. If abs_i `last` was only written by
    # the connector and 0 by the dive, compare them.
    d = np.abs(frames[0].astype(np.int16) - frames[last].astype(np.int16)).mean()
    print(f"loop close δ(frame 0, frame {last}) = {d:.4f}")
    if d > 0:
        # Force exact close so the slicer / export can rely on it.
        frames[last] = frames[0].copy()
        print("  forced frame[last] = frame[0] for exact loop close")

    missing = [i for i in range(tl.LOOP_FRAMES) if i not in frames]
    if missing:
        raise SystemExit(f"missing {len(missing)} frames, e.g. {missing[:5]}")

    for i in range(tl.LOOP_FRAMES):
        write_frame(i, frames[i])
        if i % 125 == 0:
            print(f"  wrote frame-{i:06d}.jpg")

    # Posters for each dive.
    for i, scene in enumerate(SCENES):
        start, _ = tl.dive_range(i)
        Image.fromarray(frames[start]).save(
            f"assets/{scene['slug']}.jpg", quality=88)

    # Hold poster for the home section = opening frame.
    Image.fromarray(frames[0]).save("assets/home.jpg", quality=88)

    manifest = {
        "source": "synthetic-photo",
        "fps": tl.FPS,
        "width": tl.OUT_W,
        "height": tl.OUT_H,
        "loop_frames": tl.LOOP_FRAMES,
        "dive_frames": tl.DIVE_FRAMES,
        "conn_frames": tl.CONN_FRAMES,
        "parks": [p["slug"] for p in tl.PARKS],
        "pattern": "frame-%06d.jpg",
        "loop_close_delta": float(d),
    }
    (OUT / "MANIFEST.json").write_text(json.dumps(manifest, indent=2))
    print(f"done — {tl.LOOP_FRAMES} frames, loop δ={d:.4f}")


if __name__ == "__main__":
    main()
