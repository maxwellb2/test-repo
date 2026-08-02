"""Shared flight timeline for the closed-loop camera path.

12 scenes = 6 parks × (approach + arrival). Approach trucks in with lateral
parallax; arrival orbits to a tight hold. Frame math is derived from N so the
slicer / verifier stay unchanged when the scene count moves.

Layout (0-based sequence indices):

  dive₀ ──────┐
              ├─ shared frame ─→ conn₀ ──────┐
  dive₁ ←─────┘                              ├─ shared ─→ …
  …
  dive₁₁ ── shared ─→ conn₁₁ (wrap) ── shared ─→ dive₀ frame 0

Unique frame count: N * (DIVE_FRAMES + CONN_FRAMES - 2) + 1
"""

FPS = 24
DIVE_FRAMES = 77          # ~3.2s
CONN_FRAMES = 50          # ~2.1s
HOLD_FRAMES = 36          # ~1.5s hold on the opening shot for the home section
OUT_W, OUT_H = 1920, 1080

# One entry per ballpark. `photo_focal` is the normalised dive target;
# `truck` / `orbit` steer the approach lateral move and arrival orbit sign.
PARKS = [
    {
        "slug": "fenway",
        "label": "Fenway",
        "lat": 42.3467, "lon": -71.0972,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.36, 0.72),
        "photo_drift": (+0.05, -0.03),
        "truck": (+1.0, -0.3),
        "orbit": +1.0,
        "accent": "#BD3039",
    },
    {
        "slug": "wrigley",
        "label": "Wrigley",
        "lat": 41.9484, "lon": -87.6553,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.46, 0.55),
        "photo_drift": (-0.05, -0.03),
        "truck": (-1.0, -0.2),
        "orbit": -1.0,
        "accent": "#0E3386",
    },
    {
        "slug": "oracle",
        "label": "Oracle Park",
        "lat": 37.7786, "lon": -122.3893,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.44, 0.62),
        "photo_drift": (+0.06, -0.02),
        "truck": (+1.0, +0.2),
        "orbit": +1.0,
        "accent": "#FD5A1E",
    },
    {
        "slug": "pnc",
        "label": "PNC Park",
        "lat": 40.4469, "lon": -80.0057,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.34, 0.42),
        "photo_drift": (-0.06, +0.03),
        "truck": (-1.0, +0.3),
        "orbit": -1.0,
        "accent": "#FDB827",
    },
    {
        "slug": "dodger",
        "label": "Dodger Stadium",
        "lat": 34.0739, "lon": -118.2400,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        # DTLA-skyline plate: stadium mid-frame, downtown on the right horizon.
        "photo_focal": (0.48, 0.58),
        "photo_drift": (+0.05, +0.03),
        "truck": (+1.0, -0.15),
        "orbit": +1.0,
        "accent": "#005A9C",
    },
    {
        "slug": "camden",
        "label": "Camden Yards",
        "lat": 39.2839, "lon": -76.6217,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.42, 0.60),
        "photo_drift": (-0.05, +0.02),
        "truck": (-1.0, +0.2),
        "orbit": -1.0,
        "accent": "#DF4601",
    },
]


def _scenes_from_parks():
    """Expand each park into approach + arrival beats."""
    scenes = []
    for p in PARKS:
        for beat in ("approach", "arrival"):
            scenes.append({
                "slug": f"{p['slug']}-{beat}",
                "park": p["slug"],
                "label": p["label"] if beat == "approach" else f"{p['label']} · close",
                "beat": beat,
                "focal": p["photo_focal"],
                "drift": p["photo_drift"],
                "truck": p["truck"],
                "orbit": p["orbit"],
                "accent": p["accent"],
                "lat": p["lat"], "lon": p["lon"],
                "alt_wide_m": p["alt_wide_m"],
                "alt_tight_m": p["alt_tight_m"],
            })
    return scenes


SCENES = _scenes_from_parks()
# Back-compat alias: slicer / verify historically iterated PARKS for dives.
# Point them at SCENES so dive-<slug>.mp4 names pick up the -approach/-arrival
# suffixes without further edits.
PARKS_FOR_EARTH = PARKS
PARKS = SCENES

N = len(SCENES)
STEP = DIVE_FRAMES + CONN_FRAMES - 2   # 125
LOOP_FRAMES = N * STEP + 1            # 1501


def dive_range(i):
    """Inclusive-exclusive [start, end) indices for dive i."""
    start = i * STEP
    return start, start + DIVE_FRAMES


def conn_range(i):
    """Inclusive-exclusive [start, end) for connector i (wraps after last scene)."""
    dive_start, dive_end = dive_range(i % N)
    start = dive_end - 1
    return start, start + CONN_FRAMES


def same_park(a, b):
    return a.get("park") == b.get("park")


def earth_studio_keyframes():
    """1-based keyframe list for the Earth Studio handoff (one wide→tight per park)."""
    keys = []
    for i, park in enumerate(PARKS_FOR_EARTH):
        approach_i = i * 2
        arrival_i = i * 2 + 1
        dive_s, _ = dive_range(approach_i)
        _, dive_e = dive_range(arrival_i)
        keys.append({
            "frame": dive_s + 1,
            "kind": "wide",
            "slug": park["slug"],
            "lat": park["lat"], "lon": park["lon"],
            "alt_m": park["alt_wide_m"],
        })
        keys.append({
            "frame": dive_e,
            "kind": "tight",
            "slug": park["slug"],
            "lat": park["lat"], "lon": park["lon"],
            "alt_m": park["alt_tight_m"],
        })
        nxt = PARKS_FOR_EARTH[(i + 1) % len(PARKS_FOR_EARTH)]
        conn_s, _ = conn_range(arrival_i)
        mid = conn_s + CONN_FRAMES // 2
        keys.append({
            "frame": mid + 1,
            "kind": "apex",
            "slug": f"{park['slug']}→{nxt['slug']}",
            "lat": (park["lat"] + nxt["lat"]) / 2,
            "lon": (park["lon"] + nxt["lon"]) / 2,
            "alt_m": max(park["alt_wide_m"], nxt["alt_wide_m"]) * 80,
        })
    keys.append({
        "frame": LOOP_FRAMES,
        "kind": "wide",
        "slug": PARKS_FOR_EARTH[0]["slug"],
        "lat": PARKS_FOR_EARTH[0]["lat"], "lon": PARKS_FOR_EARTH[0]["lon"],
        "alt_m": PARKS_FOR_EARTH[0]["alt_wide_m"],
        "loop_close": True,
    })
    return keys


if __name__ == "__main__":
    print(f"N={N}  DIVE={DIVE_FRAMES}  CONN={CONN_FRAMES}  STEP={STEP}")
    print(f"LOOP_FRAMES={LOOP_FRAMES}  duration={LOOP_FRAMES / FPS:.1f}s @ {FPS}fps")
    print()
    for i, s in enumerate(SCENES):
        ds, de = dive_range(i)
        cs, ce = conn_range(i)
        print(f"  dive[{s['slug']:<22}] [{ds:4d},{de:4d})  "
              f"conn[{i:2d}] [{cs:4d},{ce:4d})")
