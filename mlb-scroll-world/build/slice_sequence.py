#!/usr/bin/env python3
"""Slice a continuous frame sequence into dive + connector clips.

Accepts either:
  - a directory of frame-000000.jpg / .png  (Earth Studio PNG dump or synthetic)
  - a single continuous .mp4 / .mov

Writes the scrub-engine assets the page expects, plus a looping export:

  assets/vid/dive-<slug>.mp4       (+ -m.mp4)
  assets/vid/conn-<i>.mp4          (+ -m.mp4)   including wrap connector N-1
  assets/vid/dive-home.mp4         (+ -m.mp4)   hold on opening frame
  assets/vid/flight-loop.mp4       seamless loop (drops duplicate last frame)
  assets/<slug>.jpg, assets/home.jpg

Shared boundary frames are encoded into BOTH neighbouring clips, so the
engine's seam crossfade dissolves between identical images.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image
import imageio_ffmpeg

sys.path.insert(0, "build")
import timeline as tl  # noqa: E402

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
VID = Path("assets/vid")
VID.mkdir(parents=True, exist_ok=True)


class Encoder:
    def __init__(self, path, crf=26, gop=8, mobile_crf=28, mobile_gop=4):
        self.path = path
        self.desktop = self._spawn(path, None, gop, crf)
        self.mobile = self._spawn(
            path.with_name(path.stem + "-m" + path.suffix),
            "scale=1280:720", mobile_gop, mobile_crf)

    def _spawn(self, out, vf, gop, crf):
        cmd = [
            FFMPEG, "-y", "-loglevel", "error",
            "-f", "rawvideo", "-pix_fmt", "rgb24",
            "-s", f"{tl.OUT_W}x{tl.OUT_H}", "-r", str(tl.FPS), "-i", "-",
            "-an",
        ]
        if vf:
            cmd += ["-vf", vf]
        cmd += [
            "-c:v", "libx264", "-preset", "medium", "-crf", str(crf),
            "-g", str(gop), "-keyint_min", str(gop), "-sc_threshold", "0",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out),
        ]
        return subprocess.Popen(cmd, stdin=subprocess.PIPE)

    def write(self, arr):
        data = arr.tobytes()
        self.desktop.stdin.write(data)
        self.mobile.stdin.write(data)

    def close(self):
        for p in (self.desktop, self.mobile):
            p.stdin.close()
            p.wait()


def discover_frames(seq_dir: Path):
    jpgs = sorted(seq_dir.glob("frame-*.jpg"))
    pngs = sorted(seq_dir.glob("frame-*.png"))
    files = pngs if len(pngs) >= len(jpgs) else jpgs
    if not files:
        # Earth Studio sometimes dumps as 00001.png without a prefix.
        bare = sorted(seq_dir.glob("*.png")) + sorted(seq_dir.glob("*.jpg"))
        files = [f for f in bare if f.stem.replace("-", "").isdigit()
                 or f.stem.isdigit()]
        files = sorted(files, key=lambda p: int(
            "".join(c for c in p.stem if c.isdigit()) or "0"))
    return files


def load_frame(path: Path):
    im = Image.open(path).convert("RGB")
    if im.size != (tl.OUT_W, tl.OUT_H):
        im = im.resize((tl.OUT_W, tl.OUT_H), Image.LANCZOS)
    return np.asarray(im)


def frames_from_video(path: Path):
    """Decode every frame of a continuous video into a temp dir of JPEGs."""
    out = Path("build/sequence-from-video")
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("frame-*"):
        old.unlink()
    subprocess.run([
        FFMPEG, "-y", "-loglevel", "error", "-i", str(path),
        "-vf", f"scale={tl.OUT_W}:{tl.OUT_H}",
        "-q:v", "2", str(out / "frame-%06d.jpg"),
    ], check=True)
    # ffmpeg's image muxer is 1-based; rename to 0-based.
    files = sorted(out.glob("frame-*.jpg"))
    for i, f in enumerate(files):
        dest = out / f"frame-{i:06d}.jpg"
        if f != dest:
            f.rename(dest)
    return discover_frames(out)


def encode_range(files, start, end, out_path):
    enc = Encoder(out_path)
    first = last = None
    for i in range(start, end):
        arr = load_frame(files[i])
        enc.write(arr)
        if i == start:
            first = arr
        if i == end - 1:
            last = arr
    enc.close()
    mb = out_path.stat().st_size / 1e6
    print(f"  {out_path.name:<22} {mb:5.2f} MB  frames [{start},{end})")
    return first, last


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--seq", type=Path, default=Path("build/sequence"),
                    help="directory of frame-XXXXXX.jpg/png")
    ap.add_argument("--video", type=Path, default=None,
                    help="alternative: one continuous mp4/mov to decode first")
    ap.add_argument("--expect", type=int, default=tl.LOOP_FRAMES,
                    help="expected frame count (default: timeline.LOOP_FRAMES)")
    args = ap.parse_args()

    if args.video:
        files = frames_from_video(args.video)
        seq_dir = args.video.parent
    else:
        files = discover_frames(args.seq)
        seq_dir = args.seq

    if len(files) < args.expect:
        raise SystemExit(
            f"found {len(files)} frames in {seq_dir}, need ≥ {args.expect}")
    if len(files) > args.expect:
        print(f"note: {len(files)} frames found, using first {args.expect}")
        files = files[:args.expect]

    # Loop-close check on source frames.
    a = load_frame(files[0]).astype(np.int16)
    b = load_frame(files[args.expect - 1]).astype(np.int16)
    loop_delta = np.abs(a - b).mean()
    print(f"source loop close δ = {loop_delta:.4f}")
    if loop_delta > 2.0:
        print("WARNING: last frame ≠ first frame — loop will hitch. "
              "For Earth Studio, copy keyframe 1 onto the final frame exactly.")

    seams = {}

    print("\ndives")
    for i, park in enumerate(tl.PARKS):
        start, end = tl.dive_range(i)
        first, last = encode_range(
            files, start, end, VID / f"dive-{park['slug']}.mp4")
        Image.fromarray(first).save(f"assets/{park['slug']}.jpg", quality=88)
        seams[f"{park['slug']}-first"] = first
        seams[f"{park['slug']}-last"] = last

    print("\nconnectors (including wrap)")
    for i in range(tl.N):
        start, end = tl.conn_range(i)
        # Conn ranges can extend to LOOP_FRAMES; the last index is the loop-close
        # frame which equals files[0]. Cap reads at len(files).
        first, last = encode_range(files, start, end, VID / f"conn-{i}.mp4")
        seams[f"conn{i}-first"] = first
        seams[f"conn{i}-last"] = last

    print("\nhome hold")
    home = Encoder(VID / "dive-home.mp4")
    opening = load_frame(files[0])
    for _ in range(tl.HOLD_FRAMES):
        home.write(opening)
    home.close()
    Image.fromarray(opening).save("assets/home.jpg", quality=88)
    print(f"  dive-home.mp4          "
          f"{(VID / 'dive-home.mp4').stat().st_size / 1e6:5.2f} MB  "
          f"{tl.HOLD_FRAMES} held frames")

    print("\nflight-loop.mp4 (includes duplicate close frame so players loop invisibly)")
    loop = Encoder(VID / "flight-loop.mp4", crf=23, gop=24,
                   mobile_crf=26, mobile_gop=12)
    # Encode the full LOOP_FRAMES sequence. Frame[last] == frame[0], so when a
    # player wraps from the end back to the start the image doesn't change.
    for i in range(args.expect):
        loop.write(load_frame(files[i]))
    loop.close()
    print(f"  flight-loop.mp4        "
          f"{(VID / 'flight-loop.mp4').stat().st_size / 1e6:5.2f} MB")

    print("\nseam check (source arrays, pre-encode)")
    ok = True
    for i in range(tl.N):
        a_slug = tl.PARKS[i]["slug"]
        b_slug = tl.PARKS[(i + 1) % tl.N]["slug"]
        d1 = np.abs(seams[f"{a_slug}-last"].astype(np.int16)
                    - seams[f"conn{i}-first"].astype(np.int16)).mean()
        d2 = np.abs(seams[f"conn{i}-last"].astype(np.int16)
                    - seams[f"{b_slug}-first"].astype(np.int16)).mean()
        ok &= d1 == 0 and d2 == 0
        print(f"  {a_slug} → conn{i}: {d1:.4f}    "
              f"conn{i} → {b_slug}: {d2:.4f}")
    print("all seams frame-identical" if ok else "SEAM MISMATCH")

    manifest = {
        "source": str(seq_dir),
        "loop_delta": float(loop_delta),
        "seams_ok": bool(ok),
        "clips": {
            "dives": [p["slug"] for p in tl.PARKS] + ["home"],
            "connectors": list(range(tl.N)),
            "loop": "flight-loop.mp4",
        },
    }
    (VID / "MANIFEST.json").write_text(json.dumps(manifest, indent=2))
    if not ok or loop_delta > 2.0:
        sys.exit(1)


if __name__ == "__main__":
    main()
