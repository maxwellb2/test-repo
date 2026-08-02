#!/usr/bin/env python3
"""Render the scroll-world camera flight for six MLB ballparks.

This stands in for the skill's paid Seedance/Kling image-to-video chain. Instead
of generating motion with a video model, every frame is a crop out of a
high-resolution still, which makes the seam rule trivial to satisfy exactly
rather than approximately:

    connector[i] frame 0    == dive[i]   final frame
    connector[i] final frame == dive[i+1] frame 0

Both endpoints are computed from the same camera function as the dives they join,
so the engine can cross the seam without a visible cut.

Outputs (assets/vid/): dive-<slug>.mp4, conn-<n>.mp4 plus -m.mp4 mobile encodes,
and one poster still per scene (assets/<slug>.jpg).
"""
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image
import imageio_ffmpeg

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

OUT_W, OUT_H = 1920, 1080
# Scroll drives time, so frame rate only sets how finely the flight can be
# scrubbed — 24fps is plenty and costs a quarter less than 30 given the tight
# GOP below, where every keyframe on a detailed photo is expensive.
FPS = 24
DIVE_FRAMES = 77           # ~3.2s of dive per ballpark
CONN_FRAMES = 50           # ~2.1s of travel between ballparks

# Zoom is expressed as a fraction of the base image width. The dive stops short
# of 1.0 so connectors have headroom to push in from further out.
Z_WIDE = 0.92
Z_TIGHT = 0.42
Z_CONN_START = 1.00        # widest the outgoing park pulls back to
Z_CONN_APPROACH = 1.00     # how far out the incoming park starts

VID = Path("assets/vid")
VID.mkdir(parents=True, exist_ok=True)

# Ordered flight path. `focal` is the normalised point the camera dives toward —
# the heart of each park. `drift` nudges the outgoing pull-back sideways so the
# transition reads as travel rather than a rewind.
SCENES = [
    {"slug": "fenway",  "focal": (0.36, 0.72), "drift": (+0.05, -0.03)},
    {"slug": "wrigley", "focal": (0.46, 0.55), "drift": (-0.05, -0.03)},
    {"slug": "oracle",  "focal": (0.44, 0.62), "drift": (+0.06, -0.02)},
    {"slug": "pnc",     "focal": (0.34, 0.42), "drift": (-0.06, +0.03)},
    {"slug": "dodger",  "focal": (0.55, 0.65), "drift": (+0.05, +0.03)},
    {"slug": "camden",  "focal": (0.42, 0.60), "drift": (0.0, 0.0)},
]


# ---------------------------------------------------------------- easing ----
def ease_in_out(t):
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def smoother(t):
    t = min(1.0, max(0.0, t))
    return t * t * t * (t * (t * 6 - 15) + 10)


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------- camera ----
def crop_window(base_w, base_h, zoom, cx, cy):
    """Crop rect for a zoom level and normalised centre, clamped inside the base."""
    w = base_w * zoom
    h = w * OUT_H / OUT_W
    if h > base_h:                      # never sample outside the image
        h = base_h
        w = h * OUT_W / OUT_H
    x = cx * base_w - w / 2
    y = cy * base_h - h / 2
    x = min(max(x, 0), base_w - w)
    y = min(max(y, 0), base_h - h)
    return x, y, x + w, y + h


def sample(base, zoom, cx, cy):
    box = crop_window(base.width, base.height, zoom, cx, cy)
    return base.resize((OUT_W, OUT_H), Image.LANCZOS, box=box)


def dive_camera(scene, t):
    """Wide establishing shot -> pushed in on the focal point. t in [0,1]."""
    e = ease_in_out(t)
    fx, fy = scene["focal"]
    return (lerp(Z_WIDE, Z_TIGHT, e), lerp(0.5, fx, e), lerp(0.5, fy, e))


# ------------------------------------------------------------------ grade ----
VIGNETTE = None


def vignette_mask():
    """Soft corner falloff, shared by every frame so the six photos feel of a piece."""
    global VIGNETTE
    if VIGNETTE is None:
        ys, xs = np.mgrid[0:OUT_H, 0:OUT_W]
        nx = (xs / (OUT_W - 1) - 0.5) * 2
        ny = (ys / (OUT_H - 1) - 0.5) * 2
        r = np.sqrt(nx ** 2 + (ny * 0.92) ** 2)
        VIGNETTE = np.clip(1.0 - 0.30 * np.clip((r - 0.62) / 0.75, 0, 1) ** 1.6, 0, 1)
        VIGNETTE = VIGNETTE[:, :, None].astype(np.float32)
    return VIGNETTE


def grade(arr):
    """Light, uniform colour treatment: lifted contrast, cool shadows, vignette."""
    x = arr.astype(np.float32) / 255.0
    x = np.clip((x - 0.5) * 1.06 + 0.5, 0, 1)          # gentle contrast
    lum = x @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    x = np.clip(lum[:, :, None] + (x - lum[:, :, None]) * 1.08, 0, 1)   # saturation
    shadow = (1.0 - lum)[:, :, None] ** 2
    x = np.clip(x + shadow * np.array([-0.012, 0.0, 0.028], dtype=np.float32), 0, 1)
    x = x * vignette_mask()
    return (x * 255.0 + 0.5).astype(np.uint8)


# ---------------------------------------------------------------- encoder ----
class Encoder:
    """Two x264 pipes fed identical frames: a 1080p desktop master and a lighter
    720p phone encode. Tight GOPs (-g) matter more than bitrate here — the engine
    scrubs by seeking, and seek cost is dominated by distance to the last keyframe.
    """

    # No pre-denoise: build/encode_tradeoffs.py measures it at under 2% of file
    # size on this material while slightly widening the seam delta, so it costs
    # a filter stage and buys nothing.
    def __init__(self, path):
        self.path = path
        self.desktop = self._spawn(path, None, 8, 26)
        self.mobile = self._spawn(path.with_name(path.stem + "-m" + path.suffix),
                                  "scale=1280:720", 4, 28)

    def _spawn(self, out, vf, gop, crf):
        cmd = [
            FFMPEG, "-y", "-loglevel", "error",
            "-f", "rawvideo", "-pix_fmt", "rgb24",
            "-s", f"{OUT_W}x{OUT_H}", "-r", str(FPS), "-i", "-",
            "-an",
        ]
        if vf:
            cmd += ["-vf", vf]
        cmd += [
            "-c:v", "libx264", "-preset", "medium", "-crf", str(crf),
            "-g", str(gop), "-keyint_min", str(gop), "-sc_threshold", "0",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out),
        ]
        return subprocess.Popen(cmd, stdin=subprocess.PIPE)

    def write(self, arr):
        data = arr.tobytes()
        self.desktop.stdin.write(data)
        self.mobile.stdin.write(data)

    def close(self):
        for p in (self.desktop, self.mobile):
            p.stdin.close()
            p.wait()


def connector_frame(a, b, base_a, base_b, t):
    """One frame of the travel shot joining ballpark a to ballpark b."""
    afx, afy = a["focal"]
    dx, dy = a["drift"]

    # Outgoing park lifts away: the exact reverse of its dive, plus a drift
    # that is zero at t=0 so frame 0 still matches the dive's last frame.
    e = smoother(t)
    za = lerp(Z_TIGHT, Z_CONN_START, e)
    ca = (lerp(afx, 0.5, e) + dx * e, lerp(afy, 0.5, e) + dy * e)

    # Incoming park approaches from further out, landing precisely on the next
    # dive's opening frame.
    zb = lerp(Z_CONN_APPROACH, Z_WIDE, smoother(t))

    # Dissolve held flat at both ends so the seams stay pure A / pure B, which
    # keeps the frame-lock intact regardless of encoder noise.
    alpha = smoother((t - 0.16) / 0.68)

    if alpha <= 0.0:
        return grade(np.asarray(sample(base_a, za, *ca)))
    if alpha >= 1.0:
        return grade(np.asarray(sample(base_b, zb, 0.5, 0.5)))
    fa = np.asarray(sample(base_a, za, *ca)).astype(np.float32)
    fb = np.asarray(sample(base_b, zb, 0.5, 0.5)).astype(np.float32)
    return grade((fa + (fb - fa) * alpha).astype(np.uint8))


# ------------------------------------------------------------------- build ----
def main():
    bases = {}
    for scene in SCENES:
        bases[scene["slug"]] = Image.open(
            f"assets/src/{scene['slug']}.jpg").convert("RGB")
        print(f"loaded {scene['slug']} {bases[scene['slug']].size}")

    # Frames we must reproduce exactly at the seams, kept for verification.
    seam = {}

    for scene in SCENES:
        slug = scene["slug"]
        enc = Encoder(VID / f"dive-{slug}.mp4")
        for f in range(DIVE_FRAMES):
            t = f / (DIVE_FRAMES - 1)
            arr = grade(np.asarray(sample(bases[slug], *dive_camera(scene, t))))
            enc.write(arr)
            if f == 0:
                Image.fromarray(arr).save(f"assets/{slug}.jpg", quality=88)
                seam[f"{slug}-first"] = arr
            if f == DIVE_FRAMES - 1:
                seam[f"{slug}-last"] = arr
        enc.close()
        print(f"dive-{slug}.mp4  "
              f"{(VID / f'dive-{slug}.mp4').stat().st_size / 1e6:.1f} MB")

    for i in range(len(SCENES) - 1):
        a, b = SCENES[i], SCENES[i + 1]
        enc = Encoder(VID / f"conn-{i}.mp4")
        for f in range(CONN_FRAMES):
            arr = connector_frame(a, b, bases[a["slug"]], bases[b["slug"]],
                                  f / (CONN_FRAMES - 1))
            enc.write(arr)
            if f == 0:
                seam[f"conn{i}-first"] = arr
            if f == CONN_FRAMES - 1:
                seam[f"conn{i}-last"] = arr
        enc.close()
        print(f"conn-{i}.mp4  {(VID / f'conn-{i}.mp4').stat().st_size / 1e6:.1f} MB")

    print("\nseam check (mean abs pixel diff, 0 = frame-identical):")
    ok = True
    for i in range(len(SCENES) - 1):
        d1 = np.abs(seam[f"{SCENES[i]['slug']}-last"].astype(np.int16)
                    - seam[f"conn{i}-first"].astype(np.int16)).mean()
        d2 = np.abs(seam[f"conn{i}-last"].astype(np.int16)
                    - seam[f"{SCENES[i + 1]['slug']}-first"].astype(np.int16)).mean()
        ok &= d1 == 0 and d2 == 0
        print(f"  dive[{SCENES[i]['slug']}]->conn{i}: {d1:.4f}    "
              f"conn{i}->dive[{SCENES[i + 1]['slug']}]: {d2:.4f}")
    print("all seams frame-identical" if ok else "SEAM MISMATCH")


if __name__ == "__main__":
    main()
