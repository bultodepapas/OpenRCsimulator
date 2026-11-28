"""Build Aserradero's wood, laminated propeller and burned shop mark."""

import argparse
import io
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

from build_vehicle_paints import _wood

APP = Path(__file__).resolve().parents[2] / "app"
OUTPUT = APP / "assets/vehicle-paints/turbo-lumber-evolution"
FONT = APP / "assets/fonts/NotoSansCJKjp-Regular.otf"
SPECIES = ("maple", "walnut", "cherry", "mahogany")
GRADE = {"cherry": (1.24, 1.08, 0.99), "mahogany": (1.33, 1.06, 0.96)}
CELL = 512
BORDER = 8


def veneer(name, size):
    colour, _ = _wood(name)
    pixels = np.rint(np.clip(colour * GRADE.get(name, (1.0, 1.0, 1.0)), 0.0, 1.0) * 255).astype(np.uint8)
    return Image.fromarray(pixels).resize(size, Image.Resampling.LANCZOS)


def wood_atlas():
    result = Image.new("RGB", (2 * CELL, 2 * CELL))
    interior = CELL - 2 * BORDER
    for index, name in enumerate(SPECIES):
        image = np.asarray(veneer(name, (interior, interior)))
        padded = np.pad(image, ((BORDER, BORDER), (BORDER, BORDER), (0, 0)), mode="edge")
        result.paste(Image.fromarray(padded), (index % 2 * CELL, index // 2 * CELL))
    return result


def propeller_laminate():
    maple = veneer("maple", (256, 256))
    walnut = veneer("walnut", (256, 256))
    cherry = veneer("cherry", (256, 256))
    for top, bottom, layer in ((45, 63, walnut), (88, 116, cherry), (140, 158, walnut), (187, 205, cherry)):
        maple.paste(layer.crop((0, top, 256, bottom)), (0, top))
    # Keep the cap/sliver colours light because the standard material supplies
    # the warm average albedo used by the rotor blur.
    return Image.blend(maple, Image.new("RGB", maple.size, "white"), 0.12)


def shop_stamp():
    image = Image.new("L", (512, 192))
    draw = ImageDraw.Draw(image)
    labels = ((59, "TURBO LUMBER", 48), (132, "EDICIÓN ASERRADERO", 29))
    for y, text, size in labels:
        font = ImageFont.truetype(FONT, size)
        draw.text((256, y), text, font=font, fill=255, anchor="mm", stroke_width=1)
    draw.rounded_rectangle((24, 15, 487, 176), radius=13, width=4, outline=255)
    draw.line((84, 95, 427, 95), fill=216, width=3)
    return ImageOps.colorize(image, "black", "white")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, image in (
        ("aserradero_wood.jpg", wood_atlas()),
        ("aserradero_propeller.jpg", propeller_laminate()),
        ("aserradero_stamp.png", shop_stamp()),
    ):
        path = OUTPUT / name
        with io.BytesIO() as data:
            if path.suffix == ".jpg":
                image.save(data, "JPEG", quality=93, subsampling=0, optimize=True)
            else:
                image.save(data, "PNG", optimize=True)
            content = data.getvalue()
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                raise SystemExit(f"Stale Aserradero texture: {path}")
        else:
            path.write_bytes(content)
        print(f"{name}: {'verified' if args.check else 'built'}")


if __name__ == "__main__":
    main()
