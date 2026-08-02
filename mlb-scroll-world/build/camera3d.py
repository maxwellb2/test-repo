#!/usr/bin/env python3
"""Two camera renderers that produce real perspective change from a still + depth.

`render_plane`  — ground-plane + backdrop homography (no ML). Nearer ground
                  sweeps faster than the distant backdrop under lateral truck.
`render_depth`  — single-pass depth-aware warp. Near pixels displace more than
                  far ones, giving continuous parallax and a dolly-zoom feel.

Both take the same camera pose so the continuous renderer / A-B comparison
share identical motion paths. Pose fields:

    zoom   fraction of base width visible (1 = full width)
    cx,cy  normalised crop centre
    tx,ty  lateral camera translation in normalised image units
    tz     forward push (0 = no dolly, ~0.5 = strong)
    yaw    horizontal orbit angle in radians (plane uses it; depth approximates)
"""
from __future__ import annotations

import numpy as np
from PIL import Image

OUT_W, OUT_H = 1920, 1080

# Max parallax displacement at full depth, in base-image pixels, for |tx|=1.
PARALLAX_PX = 140.0
# Extra near-field scale contribution from a unit of tz.
DOLLY_SCALE = 0.22


def ease_in_out(t: float) -> float:
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def smoother(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return t * t * t * (t * (t * 6 - 15) + 10)


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------- sampling ----
def bilinear(img: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Sample HxWxC at floating coords with edge clamp."""
    H, W = img.shape[:2]
    x = np.clip(x, 0, W - 1.001)
    y = np.clip(y, 0, H - 1.001)
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    x1 = np.minimum(x0 + 1, W - 1)
    y1 = np.minimum(y0 + 1, H - 1)
    fx = (x - x0).astype(np.float32)
    fy = (y - y0).astype(np.float32)
    wa = (1 - fx) * (1 - fy)
    wb = fx * (1 - fy)
    wc = (1 - fx) * fy
    wd = fx * fy
    # Broadcast weights over channels.
    out = (wa[..., None] * img[y0, x0]
           + wb[..., None] * img[y0, x1]
           + wc[..., None] * img[y1, x0]
           + wd[..., None] * img[y1, x1])
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def crop_window(base_w, base_h, zoom, cx, cy, margin=0.0):
    """Axis-aligned crop rect, optionally expanded by `margin` (fraction of size)."""
    w = base_w * zoom * (1 + margin)
    h = w * OUT_H / OUT_W
    if h > base_h * (1 + margin):
        h = base_h * (1 + margin)
        w = h * OUT_W / OUT_H
    x = cx * base_w - w / 2
    y = cy * base_h - h / 2
    x = min(max(x, -base_w * margin), base_w - w + base_w * margin)
    y = min(max(y, -base_h * margin), base_h - h + base_h * margin)
    return x, y, x + w, y + h


# ----------------------------------------------------------- camera poses ----
def approach_pose(scene, t):
    """Wide establishing → mid push with a lateral truck. t in [0,1]."""
    e = ease_in_out(t)
    fx, fy = scene["focal"]
    truck = scene.get("truck", (+1.0, 0.0))
    # Start offset opposite the truck so the camera drives *into* the focal.
    cx = lerp(fx - 0.07 * truck[0], fx, e)
    cy = lerp(fy - 0.03 * truck[1], fy, e)
    zoom = lerp(0.96, 0.58, e)
    tx = lerp(0.045 * truck[0], 0.0, e)
    ty = lerp(0.020 * truck[1], 0.0, e)
    tz = lerp(0.0, 0.32, e)
    yaw = lerp(-0.04 * truck[0], 0.0, e)
    return dict(zoom=zoom, cx=cx, cy=cy, tx=tx, ty=ty, tz=tz, yaw=yaw)


def arrival_pose(scene, t):
    """Mid push → tight orbit around the focal. Continues from approach end."""
    e = ease_in_out(t)
    fx, fy = scene["focal"]
    orbit = scene.get("orbit", +1.0)
    # Match approach end at t=0: zoom 0.58, cx/cy=focal, tx/ty/yaw=0, tz=0.32
    zoom = lerp(0.58, 0.42, e)
    ang = lerp(0.0, 0.55 * orbit, e)          # radians of orbit travel
    radius = 0.035
    cx = fx + radius * np.sin(ang)
    cy = fy - 0.012 * (1 - np.cos(ang))
    tx = lerp(0.0, 0.055 * orbit, e)
    ty = lerp(0.0, -0.012, e)
    tz = lerp(0.32, 0.55, e)
    yaw = lerp(0.0, 0.07 * orbit, e)
    return dict(zoom=zoom, cx=cx, cy=cy, tx=tx, ty=ty, tz=tz, yaw=yaw)


def dive_pose(scene, t):
    beat = scene.get("beat", "approach")
    return arrival_pose(scene, t) if beat == "arrival" else approach_pose(scene, t)


def pose_at_end(scene):
    return dive_pose(scene, 1.0)


def pose_at_start(scene):
    return dive_pose(scene, 0.0)


# --------------------------------------------------------------- plane ----
def render_plane(base: Image.Image, pose: dict) -> np.ndarray:
    """Homography warp: ground (bottom) parallaxes more than sky (top)."""
    W, H = base.size
    z, cx, cy = pose["zoom"], pose["cx"], pose["cy"]
    tx, ty, tz, yaw = pose["tx"], pose["ty"], pose["tz"], pose["yaw"]

    # Generous crop so the perspective warp has room to pull from.
    x0, y0, x1, y1 = crop_window(W, H, z, cx, cy, margin=0.12)
    # Clamp to image for the PIL crop, then pad if we went outside.
    sx0, sy0 = max(0, int(np.floor(x0))), max(0, int(np.floor(y0)))
    sx1, sy1 = min(W, int(np.ceil(x1))), min(H, int(np.ceil(y1)))
    crop = base.crop((sx0, sy0, sx1, sy1))
    # Local coords of the ideal crop rect inside `crop`.
    lx0, ly0 = x0 - sx0, y0 - sy0
    lx1, ly1 = x1 - sx0, y1 - sy0
    cw, ch = crop.size

    # Destination is OUT_W x OUT_H. Source quad is the ideal crop rectangle,
    # pushed by a ground-plane slant: bottom corners shift with (tx,ty,yaw)
    # more than the top (sky stays put). Forward tz pulls all corners in
    # toward the focal, bottom more than top.
    # Source points for the four dest corners (TL, TR, BR, BL), in crop-local px.
    mid_x = (lx0 + lx1) / 2
    # Ground weight: 0 at top edge of crop, 1 at bottom.
    # Lateral shift grows toward the ground and with |tx|+|yaw|.
    shift_bot = (tx * 0.55 + yaw * 0.8) * (lx1 - lx0)
    shift_top = (tx * 0.12 + yaw * 0.15) * (lx1 - lx0)
    # Vertical: ty pushes ground more; tz foreshortens (bottom rises).
    v_bot = ty * 0.35 * (ly1 - ly0) - tz * 0.18 * (ly1 - ly0)
    v_top = ty * 0.08 * (ly1 - ly0) - tz * 0.04 * (ly1 - ly0)
    # Dolly: pull sides inward more at the bottom.
    inset_bot = tz * 0.10 * (lx1 - lx0)
    inset_top = tz * 0.03 * (lx1 - lx0)

    src = [
        lx0 + shift_top + inset_top, ly0 + v_top,           # TL
        lx1 + shift_top - inset_top, ly0 + v_top,           # TR
        lx1 + shift_bot - inset_bot, ly1 + v_bot,           # BR
        lx0 + shift_bot + inset_bot, ly1 + v_bot,           # BL
    ]
    # Clamp source points into the padded crop.
    for i in range(0, 8, 2):
        src[i] = min(max(src[i], 0), cw - 1)
        src[i + 1] = min(max(src[i + 1], 0), ch - 1)

    # find_coefficients: dest corners → source points.
    dest = [0, 0, OUT_W, 0, OUT_W, OUT_H, 0, OUT_H]
    coeffs = _perspective_coeffs(dest, src)
    out = crop.transform(
        (OUT_W, OUT_H), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    return np.asarray(out)


def _perspective_coeffs(dest, src):
    """8 perspective coeffs mapping dest quad → src quad (PIL convention)."""
    # Solve for coeffs c0..c7 where
    #   x = (c0*u + c1*v + c2) / (c6*u + c7*v + 1)
    #   y = (c3*u + c4*v + c5) / (c6*u + c7*v + 1)
    matrix = []
    for i in range(4):
        u, v = dest[2 * i], dest[2 * i + 1]
        x, y = src[2 * i], src[2 * i + 1]
        matrix.append([u, v, 1, 0, 0, 0, -u * x, -v * x])
        matrix.append([0, 0, 0, u, v, 1, -u * y, -v * y])
    A = np.array(matrix, dtype=np.float64)
    b = np.array(src, dtype=np.float64)
    return np.linalg.solve(A, b).tolist()


# --------------------------------------------------------------- depth ----
def render_depth(base_rgb: np.ndarray, depth: np.ndarray, pose: dict) -> np.ndarray:
    """Single-pass depth-aware warp. `depth` larger = nearer."""
    H, W = depth.shape
    z, cx, cy = pose["zoom"], pose["cx"], pose["cy"]
    tx, ty, tz = pose["tx"], pose["ty"], pose["tz"]
    yaw = pose.get("yaw", 0.0)

    # Normalise depth once per call; callers may pass cached 0..1 maps too.
    dmin, dmax = float(depth.min()), float(depth.max())
    d_norm = (depth - dmin) / (dmax - dmin + 1e-8)

    x0, y0, x1, y1 = crop_window(W, H, z, cx, cy, margin=0.0)
    # Output grid → unrefracted base coords.
    ys, xs = np.mgrid[0:OUT_H, 0:OUT_W].astype(np.float32)
    bx = x0 + xs * ((x1 - x0) / OUT_W)
    by = y0 + ys * ((y1 - y0) / OUT_H)

    # Depth at the unrefracted sample (one-iteration approximation).
    bx_i = np.clip(bx, 0, W - 1.001)
    by_i = np.clip(by, 0, H - 1.001)
    # Bilinear depth sample.
    x0i = np.floor(bx_i).astype(np.int32)
    y0i = np.floor(by_i).astype(np.int32)
    x1i = np.minimum(x0i + 1, W - 1)
    y1i = np.minimum(y0i + 1, H - 1)
    fx = bx_i - x0i
    fy = by_i - y0i
    d = ((1 - fx) * (1 - fy) * d_norm[y0i, x0i]
         + fx * (1 - fy) * d_norm[y0i, x1i]
         + (1 - fx) * fy * d_norm[y1i, x0i]
         + fx * fy * d_norm[y1i, x1i])

    # Lateral parallax: camera right → near content shifts left in frame.
    # yaw adds a pure horizontal orbit component.
    strength = PARALLAX_PX * (1.0 + 0.6 * tz)
    bx = bx - (tx + yaw * 0.6) * d * strength
    by = by - ty * d * strength

    # Dolly: near content scales up around the focal more than far content.
    fbx, fby = cx * W, cy * H
    scale = 1.0 + tz * d * DOLLY_SCALE
    bx = fbx + (bx - fbx) * scale
    by = fby + (by - fby) * scale

    return bilinear(base_rgb, bx, by)


# --------------------------------------------------------------- grade ----
_VIGNETTE = None


def vignette_mask():
    global _VIGNETTE
    if _VIGNETTE is None:
        ys, xs = np.mgrid[0:OUT_H, 0:OUT_W]
        nx = (xs / (OUT_W - 1) - 0.5) * 2
        ny = (ys / (OUT_H - 1) - 0.5) * 2
        r = np.sqrt(nx ** 2 + (ny * 0.92) ** 2)
        v = np.clip(1.0 - 0.30 * np.clip((r - 0.62) / 0.75, 0, 1) ** 1.6, 0, 1)
        _VIGNETTE = v[:, :, None].astype(np.float32)
    return _VIGNETTE


def grade(arr: np.ndarray) -> np.ndarray:
    x = arr.astype(np.float32) / 255.0
    x = np.clip((x - 0.5) * 1.06 + 0.5, 0, 1)
    lum = x @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    x = np.clip(lum[:, :, None] + (x - lum[:, :, None]) * 1.08, 0, 1)
    shadow = (1.0 - lum)[:, :, None] ** 2
    x = np.clip(x + shadow * np.array([-0.012, 0.0, 0.028], dtype=np.float32), 0, 1)
    x = x * vignette_mask()
    return (x * 255.0 + 0.5).astype(np.uint8)
