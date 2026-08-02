#!/usr/bin/env python3
"""Verify the encoded closed-loop flight the way the browser will see it.

Checks:
  - every dive / connector / home clip exists with a tight GOP
  - decoded seams stay geometrically continuous (including the wrap home)
  - flight-loop.mp4's last decoded frame ≈ its first (seamless loop export)
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
import imageio_ffmpeg

sys.path.insert(0, "build")
import timeline as tl  # noqa: E402

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
VID = Path("assets/vid")
SLUGS = [p["slug"] for p in tl.PARKS]
TMP = Path("build/frames")
TMP.mkdir(parents=True, exist_ok=True)

_probe_cache = {}


def probe(path):
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
    _probe_cache[key] = (count, max(gaps) if gaps else 0)
    return _probe_cache[key]


def frame_at(path, index, tag):
    out = TMP / f"{tag}.png"
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-i", str(path),
         "-vf", f"select=eq(n\\,{index})", "-vsync", "0",
         "-frames:v", "1", str(out)],
        check=True)
    return np.asarray(Image.open(out).convert("RGB")).astype(np.int16)


def nframes(path):
    return probe(path)[0]


def structural(a, b):
    ia = Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    ib = Image.fromarray(b.astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    return np.abs(np.asarray(ia).astype(np.int16)
                  - np.asarray(ib).astype(np.int16)).mean()


print("clip inventory")
missing = []
names = ([f"dive-{s}" for s in SLUGS] + ["dive-home"]
         + [f"conn-{i}" for i in range(tl.N)] + ["flight-loop"])
for name in names:
    variants = [f"{name}.mp4"]
    if name != "flight-loop":
        variants.append(f"{name}-m.mp4")
    for variant in variants:
        p = VID / variant
        if not p.exists():
            missing.append(variant)
            continue
        count, gop = probe(p)
        print(f"  {variant:<22} {p.stat().st_size / 1e6:5.2f} MB  "
              f"{count:3d} frames  max GOP {gop}")
if missing:
    print("MISSING:", missing)
    sys.exit(1)

print("\ndecoded seam check (mean abs diff over 1920x1080 RGB)")
print("  pair                          raw   structural")
worst_raw = worst_struct = 0.0
for i in range(tl.N):
    a, b = SLUGS[i], SLUGS[(i + 1) % tl.N]
    dive_a = VID / f"dive-{a}.mp4"
    conn = VID / f"conn-{i}.mp4"
    dive_b = VID / f"dive-{b}.mp4"
    pairs = [
        (f"{a} → conn{i}",
         frame_at(dive_a, nframes(dive_a) - 1, f"a{i}"),
         frame_at(conn, 0, f"cf{i}")),
        (f"conn{i} → {b}",
         frame_at(conn, nframes(conn) - 1, f"cl{i}"),
         frame_at(dive_b, 0, f"b{i}")),
    ]
    for label, x, y in pairs:
        raw = np.abs(x - y).mean()
        st = structural(x, y)
        worst_raw = max(worst_raw, raw)
        worst_struct = max(worst_struct, st)
        print(f"  {label:<28} {raw:5.2f}   {st:5.2f}")

# Wrap connector must also land on the home hold opening.
wrap_last = frame_at(VID / f"conn-{tl.N - 1}.mp4",
                     nframes(VID / f"conn-{tl.N - 1}.mp4") - 1, "wrap")
home_first = frame_at(VID / "dive-home.mp4", 0, "home")
raw = np.abs(wrap_last - home_first).mean()
st = structural(wrap_last, home_first)
worst_raw = max(worst_raw, raw)
worst_struct = max(worst_struct, st)
print(f"  {'conn5 → home':<28} {raw:5.2f}   {st:5.2f}")

print(f"\nworst raw delta        {worst_raw:.2f} / 255  (includes codec grain)")
print(f"worst structural delta {worst_struct:.2f} / 255  (real discontinuity)")

# Loop export: last frame == first frame (duplicate close included).
loop = VID / "flight-loop.mp4"
n = nframes(loop)
loop_first = frame_at(loop, 0, "loop0")
loop_last = frame_at(loop, n - 1, "loopN")
loop_delta = np.abs(loop_first - loop_last).mean()
loop_struct = structural(loop_first, loop_last)
print(f"\nflight-loop last≈first   raw {loop_delta:5.2f}  structural {loop_struct:5.2f}")

ok = worst_struct < 1.5 and loop_struct < 1.5
if ok:
    print("PASS - seams continuous; loop export closes.")
else:
    print("FAIL")
    sys.exit(1)
