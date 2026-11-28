"""Build the Turbo Lumber JR Servos tribute markings with the pinned visual venv."""

import argparse
import hashlib
import io
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

APP = Path(__file__).resolve().parents[2] / "app"
FONT = APP / "assets/fonts/NotoSansCJKjp-Regular.otf"
FONT_SHA256 = "68a3fc98800b2a27b371f2fb79991daf3633bd89309d4ffaa6946fd587f375b5"
OUTPUT = APP / "assets/vehicle-paints/turbo-lumber-evolution/jr_servos_decals.png"
INK = "#222733"
SILVER = "#f3f2eb"
RED = "#d3323f"


def label(draw, center, text, size, color, stroke=0):
    font = ImageFont.truetype(FONT, size)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font, stroke_width=stroke)
    x, y = center
    draw.text((x - (left + right) / 2, y - (top + bottom) / 2), text,
              fill=color, font=font, stroke_width=stroke)


def atlas():
    image = Image.new("RGBA", (1024, 512))
    draw = ImageDraw.Draw(image)
    label(draw, (256, 107), "JR SERVOS", 82, SILVER, 2)
    draw.rectangle((39, 162, 473, 171), fill=RED)
    label(draw, (256, 204), "S 8 9 1 1 B L    /    2 K", 31, SILVER)

    # Stylized servo output spline with a short arm, drawn from scratch.
    cx, cy = 747, 126
    draw.rounded_rectangle((749, 105, 941, 147), radius=20, fill=INK)
    draw.ellipse((912, 119, 926, 133), fill=RED)
    tooth_profile = (77, 89, 89, 77)
    teeth = []
    for index in range(64):
        angle = 2 * math.pi * index / 64
        radius = tooth_profile[index % 4]
        teeth.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    draw.polygon(teeth, fill=INK)
    for radius, color in [(58, SILVER), (46, RED), (34, INK), (16, SILVER)]:
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color)

    label(draw, (256, 373), "S8911BL", 103, INK, 3)
    label(draw, (256, 454), "2 K   B R U S H L E S S", 31, RED, 1)
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if hashlib.sha256(FONT.read_bytes()).hexdigest() != FONT_SHA256:
        raise SystemExit(f"Unexpected lettering source bytes: {FONT}")
    result = io.BytesIO()
    atlas().save(result, format="PNG", optimize=True)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != result.getvalue():
            raise SystemExit(f"Stale decal atlas: {OUTPUT}")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(result.getvalue())
    print(f"Turbo Lumber JR Servos decals: {'verified' if args.check else 'built'}")


if __name__ == "__main__":
    main()
