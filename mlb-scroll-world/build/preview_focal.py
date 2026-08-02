#!/usr/bin/env python3
"""Render just the final dive frame for candidate focal points.

The full flight takes ~2 minutes; aiming the camera is iterative, so preview the
one frame that actually shows whether the dive lands on something worth seeing.
"""
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, "build")
from render_flight import Z_TIGHT, sample, grade  # noqa: E402
import numpy as np  # noqa: E402

CANDIDATES = {
    "fenway":  [(0.44, 0.60), (0.40, 0.70), (0.42, 0.66), (0.36, 0.72)],
    "pnc":     [(0.45, 0.36), (0.40, 0.28), (0.34, 0.42), (0.48, 0.30)],
    "dodger":  [(0.52, 0.55), (0.57, 0.60), (0.60, 0.58), (0.55, 0.65)],
}

rows = []
for slug, points in CANDIDATES.items():
    base = Image.open(f"assets/src/{slug}.jpg").convert("RGB")
    shots = []
    for fx, fy in points:
        arr = grade(np.asarray(sample(base, Z_TIGHT, fx, fy)))
        im = Image.fromarray(arr)
        im.thumbnail((440, 440))
        shots.append((f"{fx},{fy}", im))
    rows.append((slug, shots))

cw = rows[0][1][0][1].width + 6
ch = rows[0][1][0][1].height + 24
sheet = Image.new("RGB", (cw * 4, ch * len(rows)), "#000")
draw = ImageDraw.Draw(sheet)
for r, (slug, shots) in enumerate(rows):
    for c, (label, im) in enumerate(shots):
        x, y = c * cw, r * ch
        draw.text((x + 4, y + 4), f"{slug} {label}", fill="#0f0")
        sheet.paste(im, (x, y + 20))
sheet.save("build/sheet-focal.png")
print("-> build/sheet-focal.png")
