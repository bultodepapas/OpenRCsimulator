#!/usr/bin/env python3
"""Regenerate the prepared OpenRC Simulator WebP image assets.

Requires Pillow==12.3.0. Source images remain untouched. Field and vehicle images
are reduced to at most 1600 pixels wide and encoded as WebP at quality 85. Savox
display copies are resized to 768 pixels wide and encoded losslessly;
--brands-only rebuilds just those derivatives.
"""

from __future__ import annotations

from pathlib import Path
import argparse
import sys

from PIL import Image, __version__ as pillow_version


PINNED_PILLOW_VERSION = "12.3.0"
ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = Path(__file__).resolve().parent / "assets"
MAX_FIELD_WIDTH = 1600
MAX_BRAND_WIDTH = 768

FIELD_IMAGES = (
    (
        Path("docs/research/landscape-upgrade/LU-21/evidence/final-after-day/postcard_club.png"),
        "field-club.webp",
    ),
    (
        Path("assets/source-deliveries/mt8-bisonte/MT8_Bisonte_entrega1_1/MT8_Bisonte/out/renders/01_tres_cuartos_delantero.png"),
        "bisonte.webp",
    ),
    (
        Path("docs/research/landscape-upgrade/LU-21/evidence/final-after-day/aerial_overview.png"),
        "field-day.webp",
    ),
    (
        Path("docs/research/landscape-upgrade/LU-21/evidence/final-after-night/runway_threshold.png"),
        "field-night.webp",
    ),
)


def metadata_for_webp(image: Image.Image) -> dict[str, bytes]:
    """Retain color and image metadata supported by WebP when present."""
    return {
        name: image.info[name]
        for name in ("icc_profile", "exif", "xmp")
        if name in image.info
    }


def require_supported_source_mode(image: Image.Image, path: Path) -> None:
    if image.mode not in ("RGB", "RGBA"):
        raise ValueError(
            f"Expected an RGB or RGBA source image at {path}; got {image.mode}."
        )


def report(source: Path, destination: Path, size: tuple[int, int], encoding: str) -> None:
    source_size = source.stat().st_size
    output_size = destination.stat().st_size
    print(
        f"{destination.relative_to(ROOT)}: {size[0]}x{size[1]}, {encoding}, "
        f"{source_size:,} -> {output_size:,} bytes"
    )


def convert_field_images() -> None:
    for relative_source, filename in FIELD_IMAGES:
        source = ROOT / relative_source
        destination = ASSET_DIR / filename
        with Image.open(source) as opened:
            opened.load()
            require_supported_source_mode(opened, source)
            metadata = metadata_for_webp(opened)
            if opened.width > MAX_FIELD_WIDTH:
                height = max(1, round(opened.height * MAX_FIELD_WIDTH / opened.width))
                image = opened.resize(
                    (MAX_FIELD_WIDTH, height),
                    Image.Resampling.LANCZOS,
                )
            else:
                image = opened.copy()
            size = image.size
            image.save(
                destination,
                format="WEBP",
                quality=85,
                alpha_quality=100,
                method=6,
                **metadata,
            )
        report(source, destination, size, "WebP quality 85")


def convert_brand_images() -> None:
    """Preserve official PNG originals; size the used black web copy for 3x display."""
    source = ASSET_DIR / "brands" / "savox" / "TeamSavox-Logo-Mono-Black.png"
    destination = source.with_suffix(".webp")
    with Image.open(source) as opened:
        require_supported_source_mode(opened, source)
        image = opened.copy()
        image.thumbnail((MAX_BRAND_WIDTH, MAX_BRAND_WIDTH), Image.Resampling.LANCZOS)
        image.save(destination, format="WEBP", lossless=True, exact=True, method=6, **metadata_for_webp(opened))
        size = image.size
    report(source, destination, size, "resized lossless WebP")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--brands-only", action="store_true", help="Only rebuild the Savox web derivatives.")
    args = parser.parse_args()
    if pillow_version != PINNED_PILLOW_VERSION:
        print(
            f"This asset script requires Pillow=={PINNED_PILLOW_VERSION}; "
            f"found {pillow_version}.",
            file=sys.stderr,
        )
        return 2

    if not Image.registered_extensions().get(".webp"):
        print("This Pillow installation does not support WebP.", file=sys.stderr)
        return 2

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    if not args.brands_only:
        convert_field_images()
    convert_brand_images()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
