"""SC-01(d) evidence sheets from a run.sh output folder (pinned visual venv: Pillow, numpy):
    .tools/visual-venv/bin/python -I research/scenery/sc01/sheets.py <out-dir> <evidence-dir>
Writes three labelled PNG sheets; every tile is a downscaled probe capture, nothing is retouched.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def sheet(tiles, cols, tile_w, tile_h, path: Path) -> None:
    rows = (len(tiles) + cols - 1) // cols
    canvas = Image.new("RGB", (cols * tile_w, rows * tile_h), "white")
    draw = ImageDraw.Draw(canvas)
    for i, (img_path, label, crop) in enumerate(tiles):
        img = Image.open(img_path).convert("RGB")
        if crop:
            img = img.crop(crop)
        x, y = (i % cols) * tile_w, (i // cols) * tile_h
        canvas.paste(img.resize((tile_w, tile_h)), (x, y))
        draw.rectangle([x, y, x + 8 + 6 * len(label), y + 16], fill="black")
        draw.text((x + 4, y + 2), label, fill="white")
    canvas.save(path, optimize=True)


def main() -> None:
    out, ev = Path(sys.argv[1]), Path(sys.argv[2])
    ev.mkdir(parents=True, exist_ok=True)
    s = out / "style"
    sheet([(s / f"style-{v}-separate.png", v, None) for v in
           ("club_photo", "club_runway", "lineup_20", "lineup_60", "country_pilot", "country_zoom")],
          2, 640, 360, ev / "style-bakeoff.png")
    m = out / "merge"
    crop = (400, 260, 920, 440)
    sheet([(m / "merge-none.png", "separate meshes: 221 draws", crop),
           (m / "merge-surfacetool.png", "SurfaceTool per material: 9 draws, 0 px differ", crop),
           (m / "merge-importer.png", "ImporterMesh: 27 draws, mirrored cars relit", crop),
           (m / "merge-shared.png", "one shared material: 2 draws, 0 px differ", crop)],
          2, 520, 180, ev / "merge.png")
    g = out / "groundbug"
    sheet([(g / "bug-v26-sub0.png", "production 2-triangle ground: runway hidden (30 m up)", None),
           (g / "bug-v26-sub9.png", "same view, ground split 10 x 10: runway drawn", None)],
          2, 640, 360, ev / "ground-runway-bug.png")


if __name__ == "__main__":
    main()
