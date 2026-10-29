"""Render the launcher icon: Android mipmaps, adaptive foreground, iOS set.

Flat mark: a white bathroom-scale platform with a teal readout pill on a teal
gradient. Run from the repo root:

    python tools/make_icon.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

SS = 4  # supersampling factor; every target is drawn large, then downscaled
TOP = (18, 140, 118)
BOTTOM = (9, 84, 70)
PLATFORM = (255, 255, 255)
READOUT = (14, 124, 102)

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def _gradient(size: int) -> Image.Image:
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / (size - 1)
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)),
        )
    return image


def _mark(draw: ImageDraw.ImageDraw, x0: float, y0: float, side: float) -> None:
    def x(v: float) -> float:
        return x0 + v * side

    def y(v: float) -> float:
        return y0 + v * side

    draw.rounded_rectangle(
        [x(0.11), y(0.11), x(0.89), y(0.89)], radius=0.15 * side, fill=PLATFORM
    )
    draw.rounded_rectangle(
        [x(0.31), y(0.18), x(0.69), y(0.30)], radius=0.05 * side, fill=READOUT
    )


def render(pixels: int, *, bleed: float, background: bool) -> Image.Image:
    big = pixels * SS
    if background:
        canvas = _gradient(big).convert("RGBA")
    else:
        canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    inset = (1 - bleed) / 2 * big
    _mark(ImageDraw.Draw(canvas), inset, inset, big - 2 * inset)
    return canvas.resize((pixels, pixels), Image.LANCZOS)


def rounded(image: Image.Image, radius: float) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, image.size[0] - 1, image.size[1] - 1],
        radius=round(radius * image.size[0]),
        fill=255,
    )
    out = image.copy()
    out.putalpha(mask)
    return out


def write(image: Image.Image, path: Path, *, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB" if opaque else "RGBA").save(path)
    assert Image.open(path).size == image.size, path


def main() -> None:
    for density, scale in DENSITIES.items():
        legacy = round(48 * scale)
        write(
            rounded(render(legacy, bleed=1.0, background=True), 0.22),
            RES / f"mipmap-{density}" / "ic_launcher.png",
        )
        # Adaptive foreground: 108dp canvas, mark inside the 72dp safe zone.
        write(
            render(round(108 * scale), bleed=0.66, background=False),
            RES / f"mipmap-{density}" / "ic_launcher_foreground.png",
        )

    contents = json.loads((IOS / "Contents.json").read_text(encoding="utf-8"))
    for image in contents["images"]:
        width, _ = image["size"].split("x")
        side = round(float(width) * int(image["scale"].rstrip("x")))
        write(render(side, bleed=1.0, background=True), IOS / image["filename"], opaque=True)

    write(rounded(render(1024, bleed=1.0, background=True), 0.22), ROOT / "build" / "icon-preview.png")
    print("icons written")


if __name__ == "__main__":
    main()
