"""Build the Extra 300S T15 tribute decal atlas with the pinned visual venv."""

import argparse
import hashlib
import io
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

APP = Path(__file__).resolve().parents[2] / "app"
LOGO = APP / "assets/vehicle-paints/avanti-s-a200/sponsors/jumper_rc_logo.png"
FONT = APP / "assets/fonts/NotoSansCJKjp-Regular.otf"
OUTPUT = APP / "assets/vehicle-paints/extra-300s-60/jumper_t15_decals.png"
INK = "#202b38"
CYAN = "#008ebc"


def centered_text(image, center, text, size, color, stroke=0):
    font = ImageFont.truetype(FONT, size)
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font, stroke_width=stroke)
    x, y = center
    draw.text((x - (left + right) / 2, y - (top + bottom) / 2), text,
              fill=color, font=font, stroke_width=stroke)


def decals():
    atlas = Image.new("RGBA", (1024, 512))
    draw = ImageDraw.Draw(atlas)
    with Image.open(LOGO) as source:
        logo = source.convert("RGBA")
    logo.thumbnail((410, 158), Image.Resampling.LANCZOS)
    atlas.alpha_composite(logo, ((512 - logo.width) // 2, 22))
    centered_text(atlas, (256, 213), "R C   C O N T R O L L E R S", 24, INK, stroke=1)

    centered_text(atlas, (768, 111), "T15", 154, INK, stroke=6)
    draw.polygon([(586, 206), (940, 206), (930, 218), (576, 218)], fill=CYAN)

    # Two stick gimbals and the center display, drawn from simple shapes.
    for x, offset in [(154, (-21, -19)), (358, (21, 19))]:
        y = 384
        draw.ellipse((x - 66, y - 66, x + 66, y + 66), outline=INK, width=12)
        draw.line((x - 45, y, x + 45, y), fill=CYAN, width=5)
        draw.line((x, y - 45, x, y + 45), fill=CYAN, width=5)
        u, v = x + offset[0], y + offset[1]
        draw.line((x, y, u, v), fill=INK, width=13)
        draw.ellipse((u - 14, v - 14, u + 14, v + 14), fill=INK)
    draw.rounded_rectangle((234, 367, 278, 401), radius=7, outline=INK, width=6)
    draw.line((244, 385, 268, 385), fill=CYAN, width=5)
    return atlas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, expected in (
        (LOGO, "2a0acfe066285815e5d1a6fc722f886b61c7eec16a318e15494f89ad87a3f095"),
        (FONT, "68a3fc98800b2a27b371f2fb79991daf3633bd89309d4ffaa6946fd587f375b5"),
    ):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f"Unexpected decal source bytes: {path}")
    result = io.BytesIO()
    decals().save(result, format="PNG", optimize=True)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != result.getvalue():
            raise SystemExit(f"Stale decal atlas: {OUTPUT}")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(result.getvalue())
    print(f"Extra 300S T15 decals: {OUTPUT.name} ({'verified' if args.check else 'built'})")


if __name__ == "__main__":
    main()
