#!/usr/bin/env python3
"""Estimate and cache per-park depth maps with Depth Anything V2 (ONNX).

Depth is stored as float32 .npy next to a visual .png preview. Larger values
mean nearer (Depth Anything's native convention). Re-running is a no-op when
the cache is fresh relative to the source photo.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODEL = Path(__file__).resolve().parent / "models" / "depth_anything_v2_small.onnx"
CACHE = Path(__file__).resolve().parent / "depth"
SRC = ROOT / "assets" / "src"

# Depth Anything V2 was trained at 518; keep a multiple of 14.
INFER_SIZE = 518
IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def _session():
    if not MODEL.exists():
        raise SystemExit(
            f"missing {MODEL}\n"
            "Download Depth Anything V2 Small ONNX to build/models/ first.")
    providers = ["CoreMLExecutionProvider", "CPUExecutionProvider"]
    return ort.InferenceSession(str(MODEL), providers=providers)


def estimate(rgb: Image.Image, sess=None) -> np.ndarray:
    """Return a float32 depth map matching `rgb`'s size (larger = nearer)."""
    sess = sess or _session()
    w, h = rgb.size
    resized = rgb.resize((INFER_SIZE, INFER_SIZE), Image.BICUBIC)
    arr = np.asarray(resized).astype(np.float32) / 255.0
    arr = (arr - IMAGENET_MEAN) / IMAGENET_STD
    pixel = arr.transpose(2, 0, 1)[None]
    name = sess.get_inputs()[0].name
    out = sess.run(None, {name: pixel})[0][0]  # HxW at infer size
    depth = Image.fromarray(out.astype(np.float32), mode="F").resize(
        (w, h), Image.BILINEAR)
    return np.asarray(depth, dtype=np.float32)


def cache_path(slug: str) -> Path:
    return CACHE / f"{slug}.npy"


def load_or_compute(slug: str, sess=None, force: bool = False) -> np.ndarray:
    CACHE.mkdir(parents=True, exist_ok=True)
    src = SRC / f"{slug}.jpg"
    if not src.exists():
        raise FileNotFoundError(src)
    npy = cache_path(slug)
    if npy.exists() and not force:
        if npy.stat().st_mtime >= src.stat().st_mtime:
            return np.load(npy)
    rgb = Image.open(src).convert("RGB")
    depth = estimate(rgb, sess=sess)
    np.save(npy, depth)
    # Preview for visual QA.
    vis = (depth - depth.min()) / (depth.max() - depth.min() + 1e-8)
    Image.fromarray((vis * 255).astype(np.uint8)).save(CACHE / f"{slug}.png")
    print(f"  depth {slug}: {depth.shape}  "
          f"range [{depth.min():.2f}, {depth.max():.2f}]")
    return depth


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("slugs", nargs="*", default=None)
    args = ap.parse_args()
    slugs = args.slugs or sorted(p.stem for p in SRC.glob("*.jpg"))
    sess = _session()
    print(f"estimating depth for {len(slugs)} parks → {CACHE}/")
    for slug in slugs:
        load_or_compute(slug, sess=sess, force=args.force)
    print("done")


if __name__ == "__main__":
    main()
