"""SUN-05: labelled comparison sheets from native glare captures (app/tests/capture_landscape_upgrade.gd).

Each sheet places matching PNGs from an "old" (HEAD before SUN) and a "new" capture set side by side, half size,
with a caption per tile. Missing images are skipped. Pixels are not retouched beyond the resize and the caption.

Run from the repository root with the pinned visual environment:
    "$(app/tests/visual-env.sh)" research/sun/sun-05/sheets.py --captures <folder> --out <folder>
<folder> holds old_day, new_day, old_golden, new_golden, old_sunset, new_sunset capture sets.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

SHEETS = {
    "sun-day.png": [("old_day", "glare_off", "Before: sky only"), ("new_day", "glare_off", "After: sky only (aureole)"),
                    ("old_day", "glare_clear", "Before: sky + LU-04 glare"), ("new_day", "glare_clear", "After: sky + eye veil")],
    "sun-disc.png": [("old_day", "glare_disc_zoom", "Before: day disc (2.5° view)"),
                     ("new_day", "glare_disc_zoom", "After: day disc"),
                     ("old_golden", "glare_disc_zoom", "Before: golden hour disc"),
                     ("new_golden", "glare_disc_zoom", "After: golden hour disc"),
                     ("old_sunset", "glare_disc_zoom", "Before: sunset disc"),
                     ("new_sunset", "glare_disc_zoom", "After: sunset disc")],
    "sun-crossing.png": [("old_day", "glare_offset_3", "Before: Stik 3° from the sun"),
                         ("new_day", "glare_offset_3", "After: Stik 3° from the sun (veil)"),
                         ("old_day", "glare_crossing", "Before: 0.67 s after crossing the sun"),
                         ("new_day", "glare_crossing", "After: 0.67 s after crossing (bleached)"),
                         ("new_day", "glare_crossing_off", "Glare off: same frame, Stik visible"),
                         ("new_day", "glare_crossing_late", "After: 5 s later, recovering")],
    "sun-low.png": [("old_golden", "glare_clear", "Before: golden hour"), ("new_golden", "glare_clear", "After: golden hour"),
                    ("old_sunset", "glare_clear", "Before: sunset"), ("new_sunset", "glare_clear", "After: sunset"),
                    ("new_golden", "glare_crossing", "After: golden hour, 0.67 s after crossing"),
                    ("new_sunset", "glare_crossing", "After: sunset, 0.67 s after crossing")],
    "sun-optics.png": [("new_day", "glare_afterimage", "Eye: afterimage 0.67 s after looking away"),
                       ("new_day", "glare_afterimage_off", "Glare off: same frame"),
                       ("new_day", "glare_lens", "Lens (chase, orbit, close-up)"),
                       ("new_golden", "glare_lens", "Lens at golden hour")],
}


def tile(path: Path, caption: str, scale: float) -> Image.Image:
    image = Image.open(path).convert("RGB")
    image = image.resize((int(image.width * scale), int(image.height * scale)), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, image.width, 22), fill=(0, 0, 0))
    draw.text((8, 5), caption, fill=(255, 255, 255))
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--captures", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--scale", type=float, default=0.5)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    manifest = {"format": "openrc-sun-sheets v1", "sheets": {}}
    for name, entries in SHEETS.items():
        tiles, sources = [], []
        for folder, case, caption in entries:
            path = args.captures / folder / f"{case}.png"
            if path.exists():
                tiles.append(tile(path, caption, args.scale))
                sources.append({"set": folder, "case": case,
                                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        if not tiles:
            continue
        columns = 2
        rows = (len(tiles) + columns - 1) // columns
        width, height = tiles[0].size
        sheet = Image.new("RGB", (width * columns, height * rows), (32, 32, 32))
        for index, image in enumerate(tiles):
            sheet.paste(image, ((index % columns) * width, (index // columns) * height))
        sheet.save(args.out / name, optimize=True)
        manifest["sheets"][name] = sources
    (args.out / "sheets.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({name: len(sources) for name, sources in manifest["sheets"].items()}))


if __name__ == "__main__":
    main()
