"""LENS-00/10 (docs/plans/lens-screen-effects.md): build the lens splat atlas from its downloaded CC0 source.

Source: "~100 grunge brushstrokes and splatters set" by Dino0040, OpenGameArt, CC0
(https://opengameart.org/content/100-grunge-brushstrokes-and-splatters-set). Photographed ink splatters, so blood
and mud on the lens have real, organic shapes instead of hand-drawn ones.

The atlas is a single 8-bit coverage channel (the brushes' alpha), 4 × 2 cells of CELL px: the top row holds liquid
splats (blood), the bottom row clumpy splats (mud). Each brush is centred on its alpha's centroid and scaled to fit.

Usage:
    python tools/lens/build_splat_atlas.py --zip <grunge_brushes.zip> [--check]
    python tools/lens/build_splat_atlas.py --download <scratch dir> [--check]
Requires Pillow (the repository's .tools/visual-venv has it). --check rebuilds in memory and compares with the
committed atlas. Never hand-edit app/assets/lens/splats.png; rebuild it with this script.
"""
import argparse
import hashlib
import io
import json
import pathlib
import sys
import urllib.request
import zipfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "app" / "assets" / "lens" / "splats.png"
SOURCES = ROOT / "app" / "assets" / "lens" / "sources.json"
URL = "https://opengameart.org/sites/default/files/grunge_brushes.zip"
ARCHIVE_SHA256 = "ce17c54ed6ca8b3ecfb92e46a68a46b1c0d52f77fcdae5bfa310fc3afc092d2a"
CELL = 384
MARGIN = 12
# Top row: liquid splats with satellite droplets (blood). Bottom row: clumpy splats (mud).
LIQUID = ["brush079", "brush081", "brush086", "brush092"]
CLUMPY = ["brush053", "brush058", "brush062", "brush024"]
MEMBER = "grunge_brushes/increased_opacity/{}.png"


def load_archive(args: argparse.Namespace) -> bytes:
    if args.zip:
        data = pathlib.Path(args.zip).read_bytes()
    else:
        target = pathlib.Path(args.download) / "grunge_brushes.zip"
        target.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(URL, headers={"User-Agent": "openrc-asset-build"})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read()
        target.write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    if digest != ARCHIVE_SHA256:
        sys.exit(f"archive sha256 {digest} != recorded {ARCHIVE_SHA256}")
    return data


def cell_image(archive: zipfile.ZipFile, name: str) -> Image.Image:
    alpha = Image.open(io.BytesIO(archive.read(MEMBER.format(name)))).getchannel("A")
    box = alpha.getbbox()
    alpha = alpha.crop(box)
    size = CELL - 2 * MARGIN
    scale = size / max(alpha.size)
    alpha = alpha.resize((max(1, round(alpha.width * scale)), max(1, round(alpha.height * scale))), Image.LANCZOS)
    cell = Image.new("L", (CELL, CELL), 0)
    cell.paste(alpha, ((CELL - alpha.width) // 2, (CELL - alpha.height) // 2))
    return cell


def build(data: bytes) -> Image.Image:
    archive = zipfile.ZipFile(io.BytesIO(data))
    atlas = Image.new("L", (CELL * 4, CELL * 2), 0)
    for row, names in enumerate([LIQUID, CLUMPY]):
        for column, name in enumerate(names):
            atlas.paste(cell_image(archive, name), (column * CELL, row * CELL))
    return atlas


def encoded(atlas: Image.Image) -> bytes:
    buffer = io.BytesIO()
    atlas.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--zip", help="an already downloaded grunge_brushes.zip")
    source.add_argument("--download", help="scratch directory to download the archive into")
    parser.add_argument("--check", action="store_true", help="compare with the committed atlas instead of writing")
    args = parser.parse_args()
    png = encoded(build(load_archive(args)))
    digest = hashlib.sha256(png).hexdigest()
    if args.check:
        current = OUT.read_bytes() if OUT.exists() else b""
        ok = hashlib.sha256(current).hexdigest() == digest
        print(("ok " if ok else "MISMATCH ") + str(OUT.relative_to(ROOT)))
        return 0 if ok else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    record = {
        "author": "Dino0040",
        "license": "CC0-1.0",
        "page": "https://opengameart.org/content/100-grunge-brushstrokes-and-splatters-set",
        "download": URL,
        "retrieved": "2026-11-12",
        "archive_sha256": ARCHIVE_SHA256,
        "modifications": "Alpha channels of eight brushes cropped, scaled and packed into one 8-bit atlas by "
                         "tools/lens/build_splat_atlas.py (4 x 2 cells: liquid row, clumpy row).",
        "files": [{"path": "splats.png", "sha256": digest,
                   "source_members": [MEMBER.format(n) for n in LIQUID + CLUMPY]}],
    }
    SOURCES.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(png)} bytes, sha256 {digest})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
