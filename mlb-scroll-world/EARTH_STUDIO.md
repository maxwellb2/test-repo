# Earth Studio handoff

This demo's scrub engine is ready for a continuous Earth Studio render. You
keyframe and render once; `build/slice_sequence.py` cuts the dump into the
clips the page needs, with frame-locked seams and a closed loop.

## 1. Get access

1. Open [earth.google.com/studio](https://earth.google.com/studio) in **desktop Chrome**.
2. Sign in and request access. Use case: *non-commercial internal evaluation /
   research prototype*. Approval is usually 24–48 hours.

## 2. Fast path — send me a tiny `.esp`

Earth Studio projects are JSON. The quickest way to get a correct 19-keyframe
loop is:

1. Create a new project, drop **two** keyframes on Fenway Park
   (`42.3467, -71.0972`), save.
2. Drop the `.esp` file into this repo (or paste it into chat).
3. Switch to Agent mode and ask me to expand it — I'll generate the full
   project with the keyframes below, exact loop closure, and the right
   frame count.

## 3. Manual keyframe path

Project settings:

| Setting | Value |
| --- | --- |
| Resolution | 1920 × 1080 |
| Frame rate | **24 fps** |
| Duration | **751 frames** (31.3 s) |
| Field of view | ~35–40°, constant |
| Date / time of day | **fixed** (don't animate — keeps lighting consistent across cities) |
| Attribution | bottom-right (copy lives on the left) |
| Layers | hide roads, borders, place labels |

Keyframes (1-based, matching `python3 build/timeline.py`):

| Frame | Kind | Target | Lat, Lon | Altitude |
| ---: | --- | --- | --- | ---: |
| 1 | wide | Fenway | 42.3467, -71.0972 | 1,400 m |
| 77 | tight | Fenway | same | 300 m |
| 102 | apex | Fenway→Wrigley | midpoint | ~112 km |
| 126 | wide | Wrigley | 41.9484, -87.6553 | 1,400 m |
| 202 | tight | Wrigley | same | 300 m |
| 227 | apex | Wrigley→Oracle | midpoint | ~112 km |
| 251 | wide | Oracle Park | 37.7786, -122.3893 | 1,400 m |
| 327 | tight | Oracle Park | same | 300 m |
| 352 | apex | Oracle→PNC | midpoint | ~112 km |
| 376 | wide | PNC Park | 40.4469, -80.0057 | 1,400 m |
| 452 | tight | PNC Park | same | 300 m |
| 477 | apex | PNC→Dodger | midpoint | ~112 km |
| 501 | wide | Dodger Stadium | 34.0739, -118.2400 | 1,400 m |
| 577 | tight | Dodger Stadium | same | 300 m |
| 602 | apex | Dodger→Camden | midpoint | ~112 km |
| 626 | wide | Camden Yards | 39.2839, -76.6217 | 1,400 m |
| 702 | tight | Camden Yards | same | 300 m |
| 727 | apex | Camden→Fenway | midpoint | ~112 km |
| **751** | **wide** | **Fenway (copy frame 1 exactly)** | **42.3467, -71.0972** | **1,400 m** |

The apex keyframes matter — without them Earth Studio interpolates a low path
between cities instead of arcing over the globe. Nudge lat/lon in the tool so
each park is centred; altitudes are starting points.

**Frame 751 must be an exact duplicate of frame 1's camera values.** Copy the
keyframe rather than eyeballing it, or the loop will hitch.

Don't descend much below ~300 m — the photogrammetry mesh over seating bowls
turns to mush.

## 4. Render

- Prefer a **PNG sequence** (avoids double compression; we re-encode anyway).
- JPEG at max quality is fine if PNG is too slow / too large.
- Expect 20–60 minutes for 751 frames at 1080p.

Dump the frames into `build/sequence/` as `frame-000000.png` …
`frame-000750.png` (0-based). Earth Studio's own numbering is often 1-based
(`00001.png`); either is fine — the slicer accepts both.

Or export one continuous `.mp4` / `.mov` and pass it with `--video`.

## 5. Slice into the scrub engine

```bash
# from a frame directory
python3 build/slice_sequence.py --seq build/sequence

# or from a single continuous video
python3 build/slice_sequence.py --video /path/to/earth-studio-export.mp4

python3 build/verify.py
```

That writes:

- `assets/vid/dive-*.mp4` + mobile variants
- `assets/vid/conn-0.mp4` … `conn-5.mp4` (conn-5 is the wrap home)
- `assets/vid/dive-home.mp4` (opening frame held for the final section)
- `assets/vid/flight-loop.mp4` (shareable seamless loop)

The page at http://127.0.0.1:8777 is already wired for the closed loop.

## 6. Attribution

Earth Studio watermarks every frame. Keep it. Reposition to bottom-right in
render settings if it collides with the copy. Do not crop it out — required
under Google's terms even for non-commercial use.
