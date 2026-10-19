# FW-MOON-08c: evidence sheet from moon_glare_capture.gd runs. For each capture folder: the pilot's 60° view of the
# moon without and with glare (centre crop), and the aircraft 1° and 5° from the moon without and with glare.
# Usage: python3 -I research/field-world/fw-moon-08/glare_sheet.py <out.jpg> <label>=<capture-dir> [...]
import sys

from PIL import Image, ImageDraw

TILE = (320, 180)


def crop(path, size):
    image = Image.open(path).convert("RGB")
    w, h = image.size
    cw, ch = size
    return image.crop(((w - cw) // 2, (h - ch) // 2, (w + cw) // 2, (h + ch) // 2)).resize(TILE)


def main():
    out = sys.argv[1]
    runs = [arg.split("=", 1) for arg in sys.argv[2:]]
    columns = [("moon-view-off.png", (640, 360), "60° view, no glare"), ("moon-view-on.png", (640, 360), "60° view, glare"),
               ("glare_offset_1_off.png", (640, 360), "model 1° away, no glare"), ("glare_offset_1.png", (640, 360), "model 1°, glare"),
               ("glare_offset_5_off.png", (640, 360), "model 5° away, no glare"), ("glare_offset_5.png", (640, 360), "model 5°, glare")]
    sheet = Image.new("RGB", (len(columns) * (TILE[0] + 4) + 4, len(runs) * (TILE[1] + 22) + 22), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for c, (_, _, title) in enumerate(columns):
        draw.text((4 + c * (TILE[0] + 4), 4), title, fill=(0, 0, 0))
    for r, (label, folder) in enumerate(runs):
        y = 22 + r * (TILE[1] + 22)
        draw.text((4, y), label, fill=(0, 0, 0))
        for c, (name, size, _) in enumerate(columns):
            sheet.paste(crop(f"{folder}/{name}", size), (4 + c * (TILE[0] + 4), y + 16))
    sheet.save(out, quality=88)
    print("sheet written to", out)


if __name__ == "__main__":
    main()
