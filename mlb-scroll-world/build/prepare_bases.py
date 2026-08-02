#!/usr/bin/env python3
"""Fetch the six chosen ballpark photos and normalise them to one working canvas.

The picks are pinned by explicit Commons filename rather than by position in a
search result, because search ranking drifts — `find_photos.py` and
`shortlist.py` are how these six were found, not how they're reproduced.

Every camera move downstream is a crop out of these bases, so they all need the
same aspect and enough resolution that the tightest crop still exceeds 1920px.
"""
import subprocess
import urllib.parse
from pathlib import Path

from PIL import Image, ImageDraw

# slug -> Commons filename. Credits are listed in the README.
CHOSEN = {
    "fenway":  "Boston - View from Prudential-Tower - Fenway Park - "
               "Baseball-Team Boston Red Sox - panoramio.jpg",
    "wrigley": "Wrigley Field in line with home plate.jpg",
    "oracle":  "ATT Sunset Panorama.jpg",
    "pnc":     "PNC Park with Roberto Clemente Bridge May 2018.jpg",
    "dodger":  "Flickr - Official U.S. Navy Imagery - Sailor on Navy Parachute Team "
               "displays an American flag above Dodger Stadium during a baseball game.jpg",
    "camden":  "Oriole Park at Camden Yards with Baltimore skyline in the "
               "background in 2023.jpg",
}
BASE_W, BASE_H = 3200, 1800
UA = "scroll-world-mlb-demo/1.0 (local evaluation)"
OUT = Path("assets/src")
RAW = Path("build/originals")
OUT.mkdir(parents=True, exist_ok=True)
RAW.mkdir(parents=True, exist_ok=True)


def fetch(slug, filename):
    """Special:FilePath redirects to the current file and can resize server-side."""
    dest = RAW / f"{slug}.jpg"
    if dest.exists():
        return dest
    url = ("https://commons.wikimedia.org/wiki/Special:FilePath/"
           f"{urllib.parse.quote(filename.replace(' ', '_'))}?width=3600")
    subprocess.run(["curl", "-sL", "-A", UA, "-o", str(dest), url], check=True)
    return dest


def cover(im, w, h):
    src_ar, dst_ar = im.width / im.height, w / h
    if src_ar > dst_ar:                      # source too wide -> trim sides
        new_w = int(round(im.height * dst_ar))
        left = (im.width - new_w) // 2
        im = im.crop((left, 0, left + new_w, im.height))
    else:                                    # source too tall -> trim top/bottom
        new_h = int(round(im.width / dst_ar))
        top = (im.height - new_h) // 2
        im = im.crop((0, top, im.width, top + new_h))
    return im.resize((w, h), Image.LANCZOS)


sheets = []
for slug, filename in CHOSEN.items():
    src = fetch(slug, filename)
    original = Image.open(src).convert("RGB")
    if original.width < 2400:
        raise SystemExit(f"{slug}: only got {original.size} — too small to dive into")
    base = cover(original, BASE_W, BASE_H)
    base.save(OUT / f"{slug}.jpg", quality=95, subsampling=0)
    print(f"{slug}: {original.size} -> {OUT / f'{slug}.jpg'}")

    # Grid overlay in normalised coords so focal points can be read off directly.
    grid = base.copy()
    grid.thumbnail((900, 900))
    draw = ImageDraw.Draw(grid)
    for i in range(1, 10):
        x, y = grid.width * i / 10, grid.height * i / 10
        draw.line([(x, 0), (x, grid.height)], fill="#00ff88", width=1)
        draw.line([(0, y), (grid.width, y)], fill="#00ff88", width=1)
        draw.text((x + 2, 2), f".{i}", fill="#00ff88")
        draw.text((2, y + 2), f".{i}", fill="#ff4488")
    draw.text((4, grid.height - 14), slug, fill="#ffff00")
    sheets.append(grid)

pad = 20
sheet = Image.new("RGB", (sheets[0].width, sum(s.height + pad for s in sheets)), "#000")
y = 0
for s in sheets:
    sheet.paste(s, (0, y))
    y += s.height + pad
sheet.save("build/sheet-grid.png")
print("-> build/sheet-grid.png (normalised grid for picking focal points)")
