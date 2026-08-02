#!/usr/bin/env python3
"""Build a side-by-side plane vs depth comparison sheet for a few parks."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, "build")
import timeline as tl  # noqa: E402
import camera3d as cam  # noqa: E402
import depth as depth_mod  # noqa: E402

PARKS = ["pnc", "oracle", "dodger", "camden"]
# Mid-approach frames show the truck parallax most clearly.
T = 0.45
CELL_W, CELL_H = 640, 360


def main():
    rows = []
    labels = []
    for park in PARKS:
        base = Image.open(f"assets/src/{park}.jpg").convert("RGB")
        rgb = np.asarray(base)
        dep = depth_mod.load_or_compute(park)
        scene = next(s for s in tl.SCENES if s["slug"] == f"{park}-approach")
        pose = cam.dive_pose(scene, T)
        plane = Image.fromarray(
            cam.grade(cam.render_plane(base, pose))).resize(
            (CELL_W, CELL_H), Image.LANCZOS)
        depth = Image.fromarray(
            cam.grade(cam.render_depth(rgb, dep, pose))).resize(
            (CELL_W, CELL_H), Image.LANCZOS)
        rows.append((plane, depth))
        labels.append(park)

    pad = 8
    header = 28
    sheet = Image.new(
        "RGB",
        (CELL_W * 2 + pad * 3, len(PARKS) * (CELL_H + pad) + header + pad),
        "#0a0e14")
    draw = ImageDraw.Draw(sheet)
    draw.text((pad, 8), "LEFT plane   ·   RIGHT depth    (approach t=0.45)",
              fill="#8c9bab")
    for i, ((plane, depth), label) in enumerate(zip(rows, labels)):
        y = header + i * (CELL_H + pad)
        sheet.paste(plane, (pad, y))
        sheet.paste(depth, (pad * 2 + CELL_W, y))
        draw.text((pad + 6, y + 6), label, fill="#f4f7fa")
    out = Path("build/compare-methods.jpg")
    sheet.save(out, quality=90)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
