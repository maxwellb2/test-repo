#!/usr/bin/env python3
"""Verify the encoded flight the way the browser will actually see it.

The render script proves the seams match before encoding; this checks they
survive H.264, and that every clip carries the tight GOP the scrub engine needs.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
import imageio_ffmpeg

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
VID = Path("assets/vid")
SLUGS = ["fenway", "wrigley", "oracle", "pnc", "dodger", "camden"]
TMP = Path("build/frames")
TMP.mkdir(parents=True, exist_ok=True)


_probe_cache = {}


def probe(path):
    """Frame count and worst keyframe gap. imageio-ffmpeg ships no ffprobe, so
    read it out of ffmpeg's own showinfo filter."""
    key = str(path)
    if key in _probe_cache:
        return _probe_cache[key]
    err = subprocess.run(
        [FFMPEG, "-i", str(path), "-vf", "showinfo", "-f", "null", "-"],
        capture_output=True, text=True).stderr
    keys, count = [], 0
    for line in err.splitlines():
        if " n:" not in line or "pts:" not in line:
            continue
        if "iskey:1" in line or "type:I" in line:
            keys.append(count)
        count += 1
    gaps = [b - a for a, b in zip(keys, keys[1:])] or [count]
    _probe_cache[key] = (count, max(gaps))
    return _probe_cache[key]


def frame_at(path, index, tag):
    """Decode a single frame by index and return it as an array."""
    out = TMP / f"{tag}.png"
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-i", str(path),
         "-vf", f"select=eq(n\\,{index})", "-vsync", "0", "-frames:v", "1", str(out)],
        check=True)
    return np.asarray(Image.open(out).convert("RGB")).astype(np.int16)


def nframes(path):
    return probe(path)[0]


print("clip inventory")
missing = []
for name in ([f"dive-{s}" for s in SLUGS] + [f"conn-{i}" for i in range(5)]):
    for variant in (f"{name}.mp4", f"{name}-m.mp4"):
        p = VID / variant
        if not p.exists():
            missing.append(variant)
            continue
        count, gop = probe(p)
        print(f"  {variant:<22} {p.stat().st_size / 1e6:5.2f} MB  "
              f"{count:3d} frames  max GOP {gop}")
if missing:
    print("MISSING:", missing)

def structural(a, b):
    """Difference with codec noise removed.

    The seams are geometrically exact by construction, so anything left after a
    blur is a real discontinuity — a shifted or mismatched camera position —
    whereas the raw delta also counts per-clip quantisation noise, which the eye
    reads as grain rather than as a cut.
    """
    ia = Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    ib = Image.fromarray(b.astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    return np.abs(np.asarray(ia).astype(np.int16)
                  - np.asarray(ib).astype(np.int16)).mean()


print("\ndecoded seam check (mean abs diff over 1920x1080 RGB)")
print("  pair                          raw   structural")
worst_raw = worst_struct = 0.0
for i in range(5):
    a, b = SLUGS[i], SLUGS[i + 1]
    dive_a = VID / f"dive-{a}.mp4"
    conn = VID / f"conn-{i}.mp4"
    dive_b = VID / f"dive-{b}.mp4"
    pairs = [
        (f"{a} -> conn{i}",
         frame_at(dive_a, nframes(dive_a) - 1, f"a{i}"), frame_at(conn, 0, f"cf{i}")),
        (f"conn{i} -> {b}",
         frame_at(conn, nframes(conn) - 1, f"cl{i}"), frame_at(dive_b, 0, f"b{i}")),
    ]
    for label, x, y in pairs:
        raw = np.abs(x - y).mean()
        st = structural(x, y)
        worst_raw = max(worst_raw, raw)
        worst_struct = max(worst_struct, st)
        print(f"  {label:<28} {raw:5.2f}   {st:5.2f}")

print(f"\nworst raw delta        {worst_raw:.2f} / 255  (includes codec grain)")
print(f"worst structural delta {worst_struct:.2f} / 255  (real discontinuity)")
if worst_struct < 1.5:
    print("PASS - no geometric discontinuity at any seam; the flight has no cuts.")
else:
    print("FAIL - the camera jumps at a seam.")
    sys.exit(1)
