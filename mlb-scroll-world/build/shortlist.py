#!/usr/bin/env python3
"""Download candidate ballpark photos and build one labelled contact sheet per park."""
import json
import subprocess
import urllib.parse
from pathlib import Path

from PIL import Image, ImageDraw

API = "https://commons.wikimedia.org/w/api.php"
UA = "scroll-world-mlb-demo/1.0 (local evaluation)"
SKIP_EXT = (".png", ".svg", ".tif", ".pdf", ".webm", ".ogv", ".gif")
CAND = Path("build/candidates")
CAND.mkdir(parents=True, exist_ok=True)

# Wide interior/aerial views are what a dive-in needs. "Scranton" excludes
# PNC Field, a different (minor-league) park that shares the PNC name.
BALLPARKS = {
    "fenway": (["Fenway Park aerial", "Fenway Park from above", "Fenway Park green monster",
                "Fenway Park grandstand"], ["fenway"], ["locker", "room"]),
    "wrigley": (["Wrigley Field aerial", "Wrigley Field from above", "Wrigley Field ivy",
                 "Wrigley Field marquee", "Wrigley Field outfield"], ["wrigley"], ["football", "seats"]),
    "oracle": (["Oracle Park aerial", "AT&T Park aerial San Francisco",
                "Oracle Park McCovey Cove", "AT&T Park outfield"],
               ["oracle park", "at&t park", "att park"], []),
    "pnc": (["PNC Park Pittsburgh aerial", "PNC Park Pittsburgh outfield",
             "PNC Park Clemente Bridge", "PNC Park Pittsburgh skyline"],
            ["pnc park"], ["scranton"]),
    "dodger": (["Dodger Stadium aerial", "Dodger Stadium from above",
                "Dodger Stadium outfield", "Dodger Stadium field"],
               ["dodger stadium"], ["entrance", "parking"]),
    "camden": (["Camden Yards aerial", "Oriole Park Camden Yards warehouse",
                "Camden Yards outfield", "Oriole Park at Camden Yards field",
                "Camden Yards baseball"], ["camden yards", "oriole park"], []),
}


def search(query, limit=20):
    params = urllib.parse.urlencode({
        "action": "query", "generator": "search", "gsrsearch": query,
        "gsrlimit": limit, "gsrnamespace": 6, "prop": "imageinfo",
        "iiprop": "url|size|extmetadata", "iiurlwidth": 2400, "format": "json",
    })
    out = subprocess.run(["curl", "-sL", "-A", UA, f"{API}?{params}"],
                         capture_output=True, text=True, check=True).stdout
    try:
        return list(json.loads(out).get("query", {}).get("pages", {}).values())
    except json.JSONDecodeError:
        return []


for slug, (queries, keywords, blocked) in BALLPARKS.items():
    rows, seen = [], set()
    for query in queries:
        for page in search(query):
            title = page["title"]
            low = title.lower()
            if title in seen or low.endswith(SKIP_EXT):
                continue
            if not any(k in low for k in keywords) or any(b in low for b in blocked):
                continue
            info = page["imageinfo"][0]
            w, h = info.get("width", 0), info.get("height", 0)
            if not h or w < 1800 or not (1.25 <= w / h <= 2.6):
                continue
            seen.add(title)
            rows.append((info.get("thumburl") or info["url"], title,
                         info.get("extmetadata", {}).get("LicenseShortName", {}).get("value", "?")))

    rows = rows[:9]
    thumbs = []
    for i, (url, title, lic) in enumerate(rows):
        dest = CAND / f"{slug}-{i}.jpg"
        if not dest.exists():
            subprocess.run(["curl", "-sL", "-A", UA, "-o", str(dest), url], check=False)
        try:
            im = Image.open(dest).convert("RGB")
        except Exception:
            continue
        im.thumbnail((640, 640))
        thumbs.append((i, im, title, lic))
        print(f"{slug}-{i}  {title}  [{lic}]")

    if not thumbs:
        print(f"{slug}: NOTHING")
        continue

    cols = 3
    rows_n = (len(thumbs) + cols - 1) // cols
    cw, ch = 640, 460
    sheet = Image.new("RGB", (cols * cw, rows_n * ch), "#111")
    draw = ImageDraw.Draw(sheet)
    for n, (i, im, title, lic) in enumerate(thumbs):
        x, y = (n % cols) * cw, (n // cols) * ch
        sheet.paste(im, (x + 8, y + 30))
        draw.text((x + 10, y + 8), f"[{i}] {title[5:60]}", fill="#0f0")
    sheet.save(f"build/sheet-{slug}.jpg", quality=88)
    print(f"  -> build/sheet-{slug}.jpg\n")
