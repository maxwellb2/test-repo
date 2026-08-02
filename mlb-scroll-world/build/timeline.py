"""Shared flight timeline for the closed-loop camera path.

Used by the photo continuous renderer, the Earth Studio slicer, and the
handoff docs so frame numbers stay in one place.

Layout (1-based Earth Studio keyframes / 0-based sequence indices):

  dive₀ ──────┐
              ├─ shared frame ─→ conn₀ ──────┐
  dive₁ ←─────┘                              ├─ shared ─→ …
  …
  dive₅ (Camden) ── shared ─→ conn₅ (wrap) ── shared ─→ dive₀ frame 0

With shared boundaries the unique frame count is:

  N * (DIVE_FRAMES + CONN_FRAMES - 2) + 1

and the final unique frame must equal frame 0 for the loop to close.
"""

FPS = 24
DIVE_FRAMES = 77          # ~3.2s
CONN_FRAMES = 50          # ~2.1s
HOLD_FRAMES = 36          # ~1.5s hold on the opening shot for the home section
OUT_W, OUT_H = 1920, 1080

# Ballparks in flight order. lat/lon/alt_m are Earth Studio camera targets;
# photo_focal/drift drive the synthetic photo continuous renderer.
PARKS = [
    {
        "slug": "fenway",
        "label": "Fenway",
        "lat": 42.3467, "lon": -71.0972,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.36, 0.72), "photo_drift": (+0.05, -0.03),
        "accent": "#BD3039",
    },
    {
        "slug": "wrigley",
        "label": "Wrigley",
        "lat": 41.9484, "lon": -87.6553,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.46, 0.55), "photo_drift": (-0.05, -0.03),
        "accent": "#0E3386",
    },
    {
        "slug": "oracle",
        "label": "Oracle Park",
        "lat": 37.7786, "lon": -122.3893,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.44, 0.62), "photo_drift": (+0.06, -0.02),
        "accent": "#FD5A1E",
    },
    {
        "slug": "pnc",
        "label": "PNC Park",
        "lat": 40.4469, "lon": -80.0057,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.34, 0.42), "photo_drift": (-0.06, +0.03),
        "accent": "#FDB827",
    },
    {
        "slug": "dodger",
        "label": "Dodger Stadium",
        "lat": 34.0739, "lon": -118.2400,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.55, 0.65), "photo_drift": (+0.05, +0.03),
        "accent": "#005A9C",
    },
    {
        "slug": "camden",
        "label": "Camden Yards",
        "lat": 39.2839, "lon": -76.6217,
        "alt_wide_m": 1400, "alt_tight_m": 300,
        "photo_focal": (0.42, 0.60), "photo_drift": (-0.05, +0.02),
        "accent": "#DF4601",
    },
]

N = len(PARKS)
# Unique frames in the continuous loop (last frame == first frame).
STEP = DIVE_FRAMES + CONN_FRAMES - 2   # 125
LOOP_FRAMES = N * STEP + 1            # 751  (indices 0..750, frame 750 == frame 0)


def dive_range(i):
    """Inclusive-exclusive [start, end) indices for dive i."""
    start = i * STEP
    return start, start + DIVE_FRAMES


def conn_range(i):
    """Inclusive-exclusive [start, end) for connector i (wraps after last park)."""
    # Connector opens on the last frame of dive i.
    dive_start, dive_end = dive_range(i % N)
    start = dive_end - 1
    return start, start + CONN_FRAMES


def earth_studio_keyframes():
    """1-based keyframe list for the Earth Studio handoff doc / .esp generator.

    Alternates park wide → park tight → travel apex → next park wide, and
    closes by repeating the opening camera on the final frame.
    """
    keys = []
    for i, park in enumerate(PARKS):
        dive_s, dive_e = dive_range(i)
        # Wide (dive start) — 1-based frame numbers for Earth Studio UI.
        keys.append({
            "frame": dive_s + 1,
            "kind": "wide",
            "slug": park["slug"],
            "lat": park["lat"], "lon": park["lon"],
            "alt_m": park["alt_wide_m"],
        })
        # Tight (dive end)
        keys.append({
            "frame": dive_e,          # dive_e is exclusive 0-based end → 1-based last = dive_e
            "kind": "tight",
            "slug": park["slug"],
            "lat": park["lat"], "lon": park["lon"],
            "alt_m": park["alt_tight_m"],
        })
        # Travel apex between this park and the next (or wrap to Fenway)
        nxt = PARKS[(i + 1) % N]
        conn_s, conn_e = conn_range(i)
        mid = conn_s + CONN_FRAMES // 2
        keys.append({
            "frame": mid + 1,
            "kind": "apex",
            "slug": f"{park['slug']}→{nxt['slug']}",
            "lat": (park["lat"] + nxt["lat"]) / 2,
            "lon": (park["lon"] + nxt["lon"]) / 2,
            "alt_m": max(park["alt_wide_m"], nxt["alt_wide_m"]) * 80,  # high arc
        })
    # Close the loop: last unique frame == opening camera.
    keys.append({
        "frame": LOOP_FRAMES,         # 1-based index of the duplicated opening frame
        "kind": "wide",
        "slug": PARKS[0]["slug"],
        "lat": PARKS[0]["lat"], "lon": PARKS[0]["lon"],
        "alt_m": PARKS[0]["alt_wide_m"],
        "loop_close": True,
    })
    return keys


if __name__ == "__main__":
    print(f"N={N}  DIVE={DIVE_FRAMES}  CONN={CONN_FRAMES}  STEP={STEP}")
    print(f"LOOP_FRAMES={LOOP_FRAMES}  duration={LOOP_FRAMES / FPS:.1f}s @ {FPS}fps")
    print()
    for i, p in enumerate(PARKS):
        ds, de = dive_range(i)
        cs, ce = conn_range(i)
        print(f"  dive[{p['slug']:<8}] [{ds:4d},{de:4d})  "
              f"conn[{i}] [{cs:4d},{ce:4d})")
    print()
    print("Earth Studio keyframes (1-based):")
    for k in earth_studio_keyframes():
        flag = "  ← LOOP CLOSE" if k.get("loop_close") else ""
        print(f"  f{k['frame']:<5} {k['kind']:<5} {k['slug']:<20} "
              f"{k['lat']:.4f},{k['lon']:.4f}  {k['alt_m']:.0f}m{flag}")
