"""
Draw the app icon: a dark squircle in the briefing page's own colours with a
concierge's desk bell on it, ringing.

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

    cx = SIZE // 2
    base_y = int(SIZE * 0.70)          # where the dome meets the plate
    dome_r = int(SIZE * 0.27)

    # Soft warm glow behind the bell.
    img = Image.alpha_composite(img, glow(SIZE, (cx, base_y - dome_r * 0.5), int(dome_r * 1.5), WARM, 60))
    img = Image.alpha_composite(img, glow(SIZE, (cx, base_y - dome_r * 0.4), int(dome_r * 1.1), SUN_A, 90))

    # Dome: a gradient disc cut at the plate line.
    dome = diagonal_gradient_disc(SIZE, (cx - dome_r, base_y - dome_r, cx + dome_r, base_y + dome_r), SUN_A, SUN_B)
    cut = Image.new("L", (SIZE, SIZE), 255)
    ImageDraw.Draw(cut).rectangle((0, base_y, SIZE, SIZE), fill=0)
    dome.putalpha(Image.composite(dome.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), cut))
    img = Image.alpha_composite(img, dome)

    d = ImageDraw.Draw(img)
    # Highlight on the dome.
    hl = int(dome_r * 0.62)
    d.arc((cx - hl, base_y - hl - int(dome_r * 0.12), cx + hl, base_y + hl - int(dome_r * 0.12)),
          start=200, end=245, fill=(255, 255, 255, 150), width=int(SIZE * 0.022))

    # Stem and button on top.
    top = base_y - dome_r
    stem_w, stem_h = int(SIZE * 0.035), int(SIZE * 0.05)
    d.rectangle((cx - stem_w // 2, top - stem_h, cx + stem_w // 2, top + 4), fill=(*LINE, 255))
    btn_w, btn_h = int(SIZE * 0.11), int(SIZE * 0.035)
    d.rounded_rectangle((cx - btn_w // 2, top - stem_h - btn_h, cx + btn_w // 2, top - stem_h + 2),
                        radius=btn_h // 2, fill=(*LINE, 255))

    # Plate under the dome.
    plate_w, plate_h = int(SIZE * 0.66), int(SIZE * 0.06)
    d.rounded_rectangle((cx - plate_w // 2, base_y - 2, cx + plate_w // 2, base_y + plate_h),
                        radius=plate_h // 2, fill=(*LINE, 255))
    d.rounded_rectangle((cx - plate_w // 2 + 20, base_y + plate_h - 6, cx + plate_w // 2 - 20, base_y + plate_h + int(SIZE * 0.02)),
                        radius=8, fill=(*LINE_FAINT, 255))

    # Ring marks: three short warm strokes either side of the button.
    ring_cy = top - stem_h - btn_h // 2
    for side in (-1, 1):
        for deg in (-35, 0, 35):
            a = math.radians(deg)
            r0, r1 = SIZE * 0.10, SIZE * 0.16
            x0 = cx + side * r0 * math.cos(a); y0 = ring_cy + r0 * math.sin(a) - SIZE * 0.02
            x1 = cx + side * r1 * math.cos(a); y1 = ring_cy + r1 * math.sin(a) - SIZE * 0.02
            d.line((x0, y0, x1, y1), fill=(*WARM, 230), width=int(SIZE * 0.022))

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
