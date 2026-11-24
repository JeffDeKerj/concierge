"""
Draw the app icon: a dark squircle in the briefing page's own colours, a sun
rising over a horizon, and three lines of text under it.

Produces Resources/AppIcon.png (1024 master), Resources/AppIcon.iconset/ and
Resources/AppIcon.icns. Run with a Python that has Pillow:

  /opt/anaconda3/bin/python3 Resources/make_icon.py
"""
from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
SIZE = 1024

BG_TOP = (23, 26, 33)       # --panel
BG_BOTTOM = (15, 17, 21)    # --bg
SUN_A = (122, 162, 247)     # --accent
SUN_B = (187, 154, 247)     # the avatar's second colour
WARM = (224, 175, 104)      # --mid
LINE = (154, 161, 173)      # --ink-soft
LINE_FAINT = (107, 114, 128)


def squircle_mask(size: int, radius_factor: float = 0.225) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * radius_factor), fill=255)
    return mask


def vertical_gradient(size: int, top, bottom) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        row = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(size):
            px[x, y] = row
    return img


def diagonal_gradient_disc(size: int, bbox, a, b) -> Image.Image:
    """A disc filled with a top-left to bottom-right gradient from a to b."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0, y1 - y0
    grad = Image.new("RGBA", (w, h))
    px = grad.load()
    for y in range(h):
        for x in range(w):
            t = (x + y) / (w + h - 2)
            px[x, y] = tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3)) + (255,)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, w - 1, h - 1), fill=255)
    layer.paste(grad, (x0, y0), mask)
    return layer


def glow(size: int, center, radius: int, color, alpha: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = center
    ImageDraw.Draw(layer).ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(*color, alpha))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.5))


def make_master() -> Image.Image:
    img = vertical_gradient(SIZE, BG_TOP, BG_BOTTOM).convert("RGBA")

    horizon = int(SIZE * 0.56)
    cx = SIZE // 2
    sun_r = int(SIZE * 0.21)

    # Warm glow behind the sun, then the sun itself, cut at the horizon.
    img = Image.alpha_composite(img, glow(SIZE, (cx, horizon - sun_r * 0.2), int(sun_r * 1.9), WARM, 70))
    img = Image.alpha_composite(img, glow(SIZE, (cx, horizon - sun_r * 0.3), int(sun_r * 1.3), SUN_A, 110))
    sun = diagonal_gradient_disc(SIZE, (cx - sun_r, horizon - sun_r - int(sun_r * 0.15), cx + sun_r, horizon + sun_r - int(sun_r * 0.15)), SUN_A, SUN_B)
    cut = Image.new("L", (SIZE, SIZE), 255)
    ImageDraw.Draw(cut).rectangle((0, horizon, SIZE, SIZE), fill=0)
    sun.putalpha(Image.composite(sun.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), cut))
    img = Image.alpha_composite(img, sun)

    d = ImageDraw.Draw(img)
    # Rays: short bars fanned over the sun.
    for deg in (-60, -30, 0, 30, 60):
        a = math.radians(-90 + deg)
        r0, r1 = sun_r * 1.28, sun_r * 1.55
        x0, y0 = cx + r0 * math.cos(a), (horizon - sun_r * 0.15) + r0 * math.sin(a)
        x1, y1 = cx + r1 * math.cos(a), (horizon - sun_r * 0.15) + r1 * math.sin(a)
        d.line((x0, y0, x1, y1), fill=(*WARM, 220), width=int(SIZE * 0.022))

    # Horizon line.
    d.line((int(SIZE * 0.17), horizon, int(SIZE * 0.83), horizon), fill=(*LINE, 255), width=int(SIZE * 0.014))

    # Three lines of the briefing, left-aligned, shorter each time.
    left = int(SIZE * 0.2)
    y = horizon + int(SIZE * 0.08)
    gap = int(SIZE * 0.075)
    widths = (0.6, 0.45, 0.3)
    for i, w in enumerate(widths):
        colour = LINE if i == 0 else LINE_FAINT
        d.rounded_rectangle((left, y, left + int(SIZE * w), y + int(SIZE * 0.032)), radius=int(SIZE * 0.016), fill=(*colour, 255))
        y += gap

    img.putalpha(squircle_mask(SIZE))
    return img


def write_iconset(master: Image.Image) -> None:
    iconset = HERE / "AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}" + ("@2x" if scale == 2 else "") + ".png"
            master.resize((px, px), Image.LANCZOS).save(iconset / name)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(HERE / "AppIcon.icns")], check=True)


if __name__ == "__main__":
    master = make_master()
    master.save(HERE / "AppIcon.png")
    write_iconset(master)
    print("wrote", HERE / "AppIcon.icns")
