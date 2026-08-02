#!/usr/bin/env python3
"""Measure the encode trade-offs this technique actually forces on you.

Scrubbed video has one unusual requirement — a very tight GOP, because the engine
seeks rather than plays and seek cost is dominated by distance from the last
keyframe. This quantifies what that costs, what else moves the needle, and
whether temporal denoising damages the frame-locked seams.

Runs on one dive/connector pair (Fenway -> Wrigley) so it finishes in a minute.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, "build")
import render_flight as rf  # noqa: E402

TMP = Path("/tmp/scroll-world-tradeoffs")
TMP.mkdir(exist_ok=True)
DIVE, CONN = TMP / "dive.mp4", TMP / "conn.mp4"

A, B = rf.SCENES[0], rf.SCENES[1]
base_a = Image.open(f"assets/src/{A['slug']}.jpg").convert("RGB")
base_b = Image.open(f"assets/src/{B['slug']}.jpg").convert("RGB")

dive_frames = [
    rf.grade(np.asarray(rf.sample(base_a, *rf.dive_camera(A, f / (rf.DIVE_FRAMES - 1)))))
    for f in range(rf.DIVE_FRAMES)
]
conn_frames = [
    rf.connector_frame(A, B, base_a, base_b, f / (rf.CONN_FRAMES - 1))
    for f in range(rf.CONN_FRAMES)
]


def encode(path, frames, gop=8, crf=26, denoise="hqdn3d=2.2:2.2:0:0"):
    cmd = [rf.FFMPEG, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{rf.OUT_W}x{rf.OUT_H}", "-r", str(rf.FPS), "-i", "-", "-an"]
    if denoise:
        cmd += ["-vf", denoise]
    cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", str(crf),
            "-g", str(gop), "-keyint_min", str(gop), "-sc_threshold", "0",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(path)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for arr in frames:
        proc.stdin.write(arr.tobytes())
    proc.stdin.close()
    proc.wait()


def build(**kw):
    encode(DIVE, dive_frames, **kw)
    encode(CONN, conn_frames, **kw)
    return (DIVE.stat().st_size + CONN.stat().st_size) / 1e6


def decoded_frame(path, index, tag):
    out = TMP / f"{tag}.png"
    subprocess.run([rf.FFMPEG, "-y", "-loglevel", "error", "-i", str(path),
                    "-vf", f"select=eq(n\\,{index})", "-vsync", "0",
                    "-frames:v", "1", str(out)], check=True)
    return np.asarray(Image.open(out).convert("RGB")).astype(np.int16)


def seam_deltas():
    """Raw and structural difference across the dive -> connector seam."""
    a = decoded_frame(DIVE, rf.DIVE_FRAMES - 1, "a")
    b = decoded_frame(CONN, 0, "b")
    blur = [np.asarray(Image.fromarray(x.astype(np.uint8))
                       .filter(ImageFilter.GaussianBlur(3))).astype(np.int16)
            for x in (a, b)]
    return np.abs(a - b).mean(), np.abs(blur[0] - blur[1]).mean()


src_delta = np.abs(dive_frames[-1].astype(np.int16)
                   - conn_frames[0].astype(np.int16)).mean()
print(f"seam delta before encoding: {src_delta:.4f}  (0 = frame-identical)\n")

print("keyframe interval — the one requirement scrubbing imposes (crf 26)")
ref = None
for gop in (8, 12, 24, 48, 250):
    mb = build(gop=gop)
    ref = ref or mb
    print(f"  -g {gop:<4} {mb:5.2f} MB   {mb / ref:4.2f}x vs -g 8")

print("\nquality — the larger lever, and freely negotiable (-g 8)")
for crf in (20, 23, 26, 29):
    print(f"  crf {crf:<3} {build(crf=crf):5.2f} MB")

print("\ndenoise — marginal for size, and does it harm the seam? (-g 8, crf 26)")
for label, dn in (("none", None),
                  ("hqdn3d=2.2:2.2:0:0 (spatial)", "hqdn3d=2.2:2.2:0:0"),
                  ("hqdn3d=1.8:1.8:5:5 (temporal)", "hqdn3d=1.8:1.8:5:5")):
    mb = build(denoise=dn)
    raw, struct = seam_deltas()
    print(f"  {label:<30} {mb:5.2f} MB   seam raw {raw:5.2f}  structural {struct:5.2f}")
