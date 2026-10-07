"""SCENERY-PLAN SC-03: labelled contact sheets from tools/scenery/capture.sh output (pinned visual venv: Pillow).
    .tools/visual-venv/bin/python -I tools/scenery/sheets.py <capture-dir> <evidence-dir> [<theme-dir>...]
Every tile is a downscaled capture; nothing is retouched.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

POSTCARDS = ["postcard_club", "postcard_pits", "postcard_pavilion", "postcard_meadow", "postcard_farm", "car_park"]
EVIDENCE = ["pilot_north", "pilot_south", "pilot_east", "pilot_west", "aerial_overview", "fleet_close", "turbines_zoom", "birds_watch"]


def sheet(paths, labels, cols, w, h, out):
    rows = (len(paths) + cols - 1) // cols
    canvas = Image.new("RGB", (cols * w, rows * h), "white")
    draw = ImageDraw.Draw(canvas)
    for i, (p, label) in enumerate(zip(paths, labels)):
        x, y = (i % cols) * w, (i // cols) * h
        canvas.paste(Image.open(p).convert("RGB").resize((w, h)), (x, y))
        draw.rectangle([x, y, x + 8 + 6 * len(label), y + 16], fill="black")
        draw.text((x + 4, y + 2), label, fill="white")
    canvas.save(out, optimize=True)


def main():
    cap, ev = Path(sys.argv[1]), Path(sys.argv[2])
    ev.mkdir(parents=True, exist_ok=True)
    sheet([cap / "on" / f"{n}.png" for n in POSTCARDS], POSTCARDS, 2, 800, 450, ev / "postcards.png")
    sheet([cap / "on" / f"{n}.png" for n in EVIDENCE], EVIDENCE, 2, 640, 360, ev / "views.png")
    sheet([cap / "off" / "pilot_south.png", cap / "on" / "pilot_south.png"], ["pilot_south scenery off", "pilot_south scenery on"],
          2, 800, 450, ev / "off-on.png")
    extra = [Path(d) for d in sys.argv[3:]]
    if extra:
        paths, labels = [], []
        for d in extra:
            for png in sorted(d.glob("*.png")):
                paths.append(png)
                labels.append(f"{d.name}/{png.stem}")
        sheet(paths, labels, 2, 640, 360, ev / "themes-birds.png")


if __name__ == "__main__":
    main()
