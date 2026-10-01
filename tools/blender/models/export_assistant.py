"""Turns the assistant renders (assistant.py) into the app's WebP layers in assets/assistant/.

  <variant>_body.webp   the robot, RGBA, kept sharp (near-lossless colour, exact alpha)
  <variant>_glass.webp  visor reflections, luminance as alpha (drawn normally over the live face)
  <variant>_glow.webp   lights plus a tight two-step halo, luminance as alpha, at half size

Light layers are rendered on black. Their alpha is the brightest channel with a smoothstep fade near
zero (so render noise never tints the page), and their colour is unpremultiplied to full strength.

    python3 tools/blender/models/export_assistant.py RENDER_DIR [--variants nova,sol,iris,mint]
"""

import argparse
import os

import numpy as np
from PIL import Image, ImageFilter

ASSETS = os.path.join(os.path.dirname(__file__), "..", "..", "..", "assets", "assistant")


def light_layer(rgb):
    m = rgb.max(-1)
    t = np.clip(m / 0.025, 0, 1)
    alpha = m * t * t * (3 - 2 * t)
    colour = np.where(m[..., None] > 1e-5, rgb / np.maximum(m[..., None], 1e-5), 0)
    return np.dstack([colour, alpha])


def blur(rgb, radius):
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255


def save(arr, path, size=None, lossless=False):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8))
    if size:
        img = img.resize((size, size), Image.LANCZOS)
    if lossless:
        img.save(path, "WEBP", lossless=True, quality=100, method=6)
    else:
        img.save(path, "WEBP", quality=92, alpha_quality=100, method=6, exact=True)
    print("wrote", os.path.normpath(path), img.size, os.path.getsize(path) // 1024, "KB")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("renders")
    p.add_argument("--variants", default="nova,sol,iris,mint")
    p.add_argument("--out", default=ASSETS)
    a = p.parse_args()
    for v in a.variants.split(","):
        body = np.asarray(Image.open(os.path.join(a.renders, f"{v}_body.png")).convert("RGBA")).astype(np.float32) / 255
        size = body.shape[0]
        save(body, os.path.join(a.out, f"{v}_body.webp"))

        glass = np.asarray(Image.open(os.path.join(a.renders, f"{v}_glass.png")).convert("RGB")).astype(np.float32) / 255
        # Reflections are near-white, so one colour keeps the layer clean and small; alpha carries the
        # shape.
        layer = light_layer(glass)
        layer[..., :3] = (0.9, 0.93, 1.0)
        save(layer, os.path.join(a.out, f"{v}_glass.webp"))

        lights = np.asarray(Image.open(os.path.join(a.renders, f"{v}_glow.png")).convert("RGB")).astype(np.float32) / 255
        halo = lights + 0.8 * blur(lights, size * 0.006) + 0.45 * blur(lights, size * 0.018)
        save(light_layer(np.clip(halo, 0, 1)), os.path.join(a.out, f"{v}_glow.webp"), size=size // 2)


if __name__ == "__main__":
    main()
