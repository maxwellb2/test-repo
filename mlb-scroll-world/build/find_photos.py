#!/usr/bin/env python3
"""List Wikimedia Commons candidates per ballpark so we can pick good wide shots.

Search relevance alone is poor here (a "Dodger Stadium panorama" query happily
returns Marlins Park), so every hit must also carry a stadium keyword in its
title and sit in a croppable aspect range.
"""
import json
import subprocess
import urllib.parse

# slug -> (search queries, required title keywords)
BALLPARKS = {
    "fenway":  (["Fenway Park", "Fenway Park interior", "Fenway Park aerial"],
                ["fenway"]),
    "wrigley": (["Wrigley Field", "Wrigley Field interior", "Wrigley Field aerial"],
                ["wrigley"]),
    "oracle":  (["Oracle Park San Francisco", "AT&T Park San Francisco interior",
                 "Oracle Park aerial"],
                ["oracle park", "at&t park", "att park", "pacific bell", "sbc park"]),
    "pnc":     (["PNC Park", "PNC Park interior", "PNC Park aerial"],
                ["pnc park"]),
    "dodger":  (["Dodger Stadium", "Dodger Stadium interior", "Dodger Stadium aerial"],
                ["dodger stadium"]),
    "camden":  (["Oriole Park at Camden Yards", "Camden Yards interior",
                 "Oriole Park at Camden Yards aerial"],
                ["camden yards", "oriole park"]),
}
API = "https://commons.wikimedia.org/w/api.php"
UA = "scroll-world-mlb-demo/1.0 (local evaluation)"
SKIP_EXT = (".png", ".svg", ".tif", ".pdf", ".webm", ".ogv", ".gif")


def search(query, limit=20):
    params = urllib.parse.urlencode({
        "action": "query", "generator": "search", "gsrsearch": query,
        "gsrlimit": limit, "gsrnamespace": 6, "prop": "imageinfo",
        "iiprop": "url|size|extmetadata", "iiurlwidth": 3200, "format": "json",
    })
    out = subprocess.run(
        ["curl", "-sL", "-A", UA, f"{API}?{params}"],
        capture_output=True, text=True, check=True,
    ).stdout
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return []
    return list(data.get("query", {}).get("pages", {}).values())


for slug, (queries, keywords) in BALLPARKS.items():
    print(f"\n=== {slug}")
    seen = set()
    rows = []
    for query in queries:
        for page in search(query):
            title = page["title"]
            low = title.lower()
            if title in seen or low.endswith(SKIP_EXT):
                continue
            if not any(k in low for k in keywords):
                continue
            seen.add(title)
            info = page["imageinfo"][0]
            w, h = info.get("width", 0), info.get("height", 0)
            if not h or w < 2000:
                continue
            ar = w / h
            if not (1.25 <= ar <= 2.4):
                continue
            lic = info.get("extmetadata", {}).get(
                "LicenseShortName", {}).get("value", "?")
            rows.append((w * h, w, h, ar, lic, title,
                         info.get("thumburl") or info["url"]))
    for _, w, h, ar, lic, title, url in sorted(rows, reverse=True)[:8]:
        print(f"  {w}x{h} ar={ar:.2f} [{lic}] {title}")
        print(f"      {url}")
    if not rows:
        print("  (nothing matched)")
