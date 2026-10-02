#!/usr/bin/env python3
"""Rasterize the Spike Prime Studio mark: fused white SP, amber circuit traces.

The locked direction is a square monogram on the app's dark ground. This script
is the source of the launcher, window, and README assets.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BG = (18, 20, 24, 255)
INK = (244, 246, 248, 255)
AMBER = (226, 177, 90, 255)
ORANGE = (224, 122, 48, 255)


def _rect(draw, box, color):
    draw.rectangle(box, fill=color)


def _pad(draw, cx, cy, size, color):
    half = size // 2
    draw.rectangle((cx - half, cy - half, cx + half, cy + half), fill=color)
    hole = max(4, size // 5)
    draw.rectangle((cx - hole, cy - hole, cx + hole, cy + hole), fill=BG)


def _trace(draw, points, width, color):
    draw.line(points, fill=color, width=width, joint="curve")


def render(size: int) -> Image.Image:
    """Draw at 4x and downscale so corners stay sharp at launcher sizes."""
    scale = 4
    canvas = size * scale
    image = Image.new("RGBA", (canvas, canvas), BG)
    draw = ImageDraw.Draw(image)
    s = canvas / 1024

    def x(value):
        return round(value * s)

    def box(x0, y0, x1, y1):
        return (x(x0), x(y0), x(x1), x(y1))

    # S on the left, P on the right, joined by the middle bar (the fuse).
    # Counters stay dark so the letters still read at 48px.
    t = 100
    _rect(draw, box(150, 230, 430, 230 + t), INK)
    _rect(draw, box(150, 230, 150 + t, 512), INK)
    _rect(draw, box(150, 512 - t, 470, 512), INK)
    _rect(draw, box(370, 512 - t, 470, 800), INK)
    _rect(draw, box(150, 800 - t, 470, 800), INK)

    _rect(draw, box(430, 470, 620, 554), INK)  # fuse into the P stem
    _rect(draw, box(520, 210, 520 + t, 800), INK)
    _rect(draw, box(620, 210, 890, 210 + t), INK)
    _rect(draw, box(890 - t, 210, 890, 530), INK)
    _rect(draw, box(620, 530 - t, 890, 530), INK)

    trace = max(8, x(26))
    pad = max(10, x(44))
    _trace(draw, [(x(200), x(230)), (x(200), x(150)), (x(310), x(150))], trace, AMBER)
    _pad(draw, x(330), x(150), pad, AMBER)
    _trace(draw, [(x(760), x(210)), (x(760), x(145)), (x(860), x(145))], trace, ORANGE)
    _pad(draw, x(860), x(145), pad, ORANGE)
    _trace(draw, [(x(200), x(800)), (x(200), x(890)), (x(320), x(890))], trace, ORANGE)
    _pad(draw, x(340), x(890), pad, ORANGE)
    _trace(draw, [(x(890), x(470)), (x(950), x(470)), (x(950), x(620))], trace, AMBER)
    _pad(draw, x(950), x(640), pad, AMBER)

    # Keep the letters inside the Android adaptive-icon safe zone.
    inset = 0.74
    framed = Image.new("RGBA", (canvas, canvas), BG)
    inner = round(canvas * inset)
    reduced = image.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (canvas - inner) // 2
    framed.paste(reduced, (offset, offset))
    return framed.resize((size, size), Image.Resampling.LANCZOS)


def main():
    master = render(1024)
    brand = ROOT / "assets" / "brand"
    brand.mkdir(parents=True, exist_ok=True)
    master.save(brand / "sp-mark-1024.png")
    master.resize((512, 512), Image.Resampling.LANCZOS).save(brand / "sp-mark.png")

    android = {
        48: "mipmap-mdpi",
        72: "mipmap-hdpi",
        96: "mipmap-xhdpi",
        144: "mipmap-xxhdpi",
        192: "mipmap-xxxhdpi",
    }
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for size, folder in android.items():
        out = res / folder
        out.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.Resampling.LANCZOS).save(out / "ic_launcher.png")

    mac = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        master.resize((size, size), Image.Resampling.LANCZOS).save(mac / f"app_icon_{size}.png")

    web_icons = ROOT / "web" / "icons"
    web_icons.mkdir(parents=True, exist_ok=True)
    for size, name in (
        (32, ROOT / "web" / "favicon.png"),
        (192, web_icons / "Icon-192.png"),
        (512, web_icons / "Icon-512.png"),
        (192, web_icons / "Icon-maskable-192.png"),
        (512, web_icons / "Icon-maskable-512.png"),
    ):
        master.resize((size, size), Image.Resampling.LANCZOS).save(name)

    linux_icon = ROOT / "linux" / "runner" / "resources"
    linux_icon.mkdir(parents=True, exist_ok=True)
    master.resize((256, 256), Image.Resampling.LANCZOS).save(linux_icon / "app_icon.png")

    windows = ROOT / "windows" / "runner" / "resources"
    windows.mkdir(parents=True, exist_ok=True)
    ico_sizes = [master.resize((size, size), Image.Resampling.LANCZOS) for size in (16, 32, 48, 64, 128, 256)]
    ico_sizes[-1].save(
        windows / "app_icon.ico",
        format="ICO",
        sizes=[(image.width, image.height) for image in ico_sizes],
        append_images=ico_sizes[:-1],
    )
    print("Wrote brand assets from the SP circuit monogram.")


if __name__ == "__main__":
    main()
