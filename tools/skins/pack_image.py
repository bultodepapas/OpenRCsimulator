#!/usr/bin/env python3
"""Package the paint PNGs from an OpenRC kit without Blender.

    python pack_image.py --output paint.orskin --label "My paint"

Edit the kit's Paint-NN.png files in place, or pass a folder containing files
with those names. A single PNG may be supplied directly for one-image kits.
Validation cannot establish that a design follows the model's UV layout.
"""

import argparse
import json
import math
import os
from pathlib import Path
import struct
import sys
import tempfile
import zipfile
import zlib


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_PNG_BYTES = 16 * 1024 * 1024
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
MAX_SIDE = 4096
MAX_PIXELS = 16_777_216
MAX_CHUNKS = 65536
_DEPTHS = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
_ADAM7 = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
          (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))


def _scanlines(width, height, depth, color, interlaced):
    """Expected lengths and filter positions, including Adam7 passes."""
    bits = _CHANNELS[color] * depth
    passes = _ADAM7 if interlaced else ((0, 0, 1, 1),)
    lengths = []
    for x, y, dx, dy in passes:
        pass_width = max(0, (width - x + dx - 1) // dx)
        pass_height = max(0, (height - y + dy - 1) // dy)
        if pass_width and pass_height:
            lengths.extend([1 + (pass_width * bits + 7) // 8] * pass_height)
    return lengths


def _validate_zlib(chunks, row_lengths):
    """Validate the bounded zlib stream and each PNG scanline's filter byte."""
    decoder = zlib.decompressobj()
    expected = sum(row_lengths)
    count = 0
    row = 0
    next_filter = 0

    def consume(data):
        nonlocal count, row, next_filter
        end = count + len(data)
        if end > expected:
            raise ValueError("PNG image data expands beyond its stated dimensions.")
        while row < len(row_lengths) and next_filter < end:
            if data[next_filter - count] > 4:
                raise ValueError("PNG contains an invalid scanline filter.")
            next_filter += row_lengths[row]
            row += 1
        count = end

    try:
        for part in chunks:
            pending = part
            while pending:
                before = len(pending)
                decoded = decoder.decompress(pending, 65536)
                pending = decoder.unconsumed_tail
                if decoder.unused_data:
                    raise ValueError("PNG has extra compressed image data.")
                consume(decoded)
                if not decoded and len(pending) == before:
                    raise ValueError("PNG compressed image data did not advance.")
        while True:
            decoded = decoder.decompress(b"", 65536)
            if not decoded:
                break
            consume(decoded)
    except zlib.error as error:
        raise ValueError("PNG image data is damaged or incomplete.") from error
    if not decoder.eof or decoder.unused_data or count != expected or row != len(row_lengths):
        raise ValueError("PNG image data is damaged or incomplete.")


def inspect_png(data):
    """Check the subset of PNG accepted by the runtime and return dimensions."""
    if not data.startswith(PNG_SIGNATURE) or len(data) > MAX_PNG_BYTES:
        raise ValueError("Choose a PNG file no larger than 16 MiB.")
    offset, count = 8, 0
    width = height = depth = color = interlaced = None
    idat = []
    seen_palette = seen_data = data_closed = ended = False
    while offset + 12 <= len(data):
        count += 1
        if count > MAX_CHUNKS:
            raise ValueError("PNG contains too many chunks.")
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        end = offset + length + 12
        if end > len(data) or not all(65 <= b <= 90 or 97 <= b <= 122 for b in kind):
            raise ValueError("PNG chunk is incomplete or invalid.")
        body = memoryview(data)[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(body, zlib.crc32(kind)) & 0xFFFFFFFF != crc:
            raise ValueError("PNG chunk checksum failed.")
        if count == 1:
            if kind != b"IHDR" or length != 13:
                raise ValueError("PNG must start with an IHDR header.")
            width, height, depth, color, compression, filtering, interlaced = struct.unpack(">IIBBBBB", body)
            if not 1 <= width <= MAX_SIDE or not 1 <= height <= MAX_SIDE or width * height > MAX_PIXELS:
                raise ValueError("PNG dimensions exceed the 4096-per-side / 16,777,216-pixel limits.")
            if color not in _DEPTHS or depth not in _DEPTHS[color] or compression != 0 or filtering != 0 or interlaced not in (0, 1):
                raise ValueError("PNG has an unsupported color, depth, compression or interlace mode.")
        elif kind == b"IHDR":
            raise ValueError("PNG contains a duplicate IHDR header.")
        elif kind in (b"iCCP", b"zTXt", b"iTXt"):
            raise ValueError("PNG contains compressed metadata unsupported by OpenRC; export a standard sRGB PNG without compressed metadata.")
        elif kind == b"PLTE":
            if seen_palette or seen_data or color in (0, 4) or length == 0 or length > 768 or length % 3:
                raise ValueError("PNG palette is invalid.")
            if color == 3 and length // 3 > 2 ** depth:
                raise ValueError("PNG palette exceeds its indexed color depth.")
            seen_palette = True
        elif kind == b"IDAT":
            if data_closed or (color == 3 and not seen_palette):
                raise ValueError("PNG image chunks or palette are out of order.")
            seen_data = True
            idat.append(body)
        elif kind == b"IEND":
            if length or not seen_data or end != len(data):
                raise ValueError("PNG has an invalid end marker or trailing bytes.")
            ended = True
            break
        elif not kind[0] & 32:
            raise ValueError("PNG has an unsupported critical chunk.")
        if seen_data and kind != b"IDAT":
            data_closed = True
        offset = end
    if not ended:
        raise ValueError("PNG is incomplete.")
    _validate_zlib(idat, _scanlines(width, height, depth, color, interlaced))
    return width, height


def pack_image(image_path, output_path, label=None, kit=None):
    """Validate and atomically publish an image-only .orskin archive."""
    kit_dir = Path(__file__).resolve().parent
    if kit is None:
        kit = json.loads((kit_dir / "kit.json").read_text(encoding="utf-8"))
    paints = kit.get("paints")
    if not isinstance(paints, list) or not 1 <= len(paints) <= 9:
        raise ValueError("The kit has no valid paint image list.")
    if not isinstance(kit.get("aircraft_id"), str) or not kit["aircraft_id"]:
        raise ValueError("The kit aircraft identity is missing.")
    sha = kit.get("stock_sha256")
    if not isinstance(sha, str) or len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
        raise ValueError("The kit stock-model identity is invalid.")
    source = Path(image_path).expanduser().resolve() if image_path else kit_dir
    output = Path(output_path).expanduser().resolve()
    if output.suffix.lower() != ".orskin":
        raise ValueError("The output filename must end in .orskin.")
    if source == output:
        raise ValueError("The input image and output package must be different files.")
    if not output.parent.is_dir():
        raise ValueError("The output folder does not exist.")
    label = (label if label is not None else output.stem).strip()
    if not 1 <= len(label) <= 48 or not label.isprintable():
        raise ValueError("The paint label must contain 1–48 printable characters.")
    if source.is_file() and len(paints) != 1:
        raise ValueError("This aircraft has multiple paint images; supply a folder containing all Paint-NN.png files.")
    if not source.is_file() and not source.is_dir():
        raise ValueError("The paint image or image folder does not exist.")
    manifest = {
        "format": "openrc-skin", "version": 1,
        "aircraft_id": kit["aircraft_id"], "base_asset_sha256": sha,
        "label": label,
        "materials": [],
    }
    textures, sizes, seen_materials, seen_images = {}, [], set(), set()
    total_pixels = 0
    for index, paint in enumerate(paints, 1):
        filename = paint.get("image", "") if isinstance(paint, dict) else ""
        if not filename or Path(filename).name != filename or filename in seen_images:
            raise ValueError("The kit has an invalid or duplicate paint image name.")
        seen_images.add(filename)
        image = source if source.is_file() else source / filename
        if image.resolve() == output:
            raise ValueError("The input image and output package must be different files.")
        with image.open("rb") as handle:
            png = handle.read(MAX_PNG_BYTES + 1)
        width, height = inspect_png(png)
        total_pixels += width * height
        if total_pixels > MAX_PIXELS:
            raise ValueError("The combined paint images exceed 16,777,216 pixels.")
        sizes.append((width, height))
        texture_name = f"texture-{index:02d}.png"
        textures[texture_name] = png
        materials, colors = paint.get("materials"), paint.get("base_colors")
        if not isinstance(materials, list) or not materials or not isinstance(colors, dict):
            raise ValueError("The kit has an invalid paint material list.")
        for name in materials:
            if not isinstance(name, str) or not name or name in seen_materials:
                raise ValueError("The kit contains an invalid or duplicate material name.")
            color = colors.get(name)
            if not isinstance(color, list) or len(color) != 4 or any(
                    not isinstance(c, (int, float)) or not math.isfinite(c) or not 0 <= c <= 1 for c in color):
                raise ValueError("The kit contains an invalid material color.")
            seen_materials.add(name)
            manifest["materials"].append({"name": name, "base_color": color, "texture": texture_name})
    if len(manifest["materials"]) > 9:
        raise ValueError("The kit contains more than nine paint materials.")
    encoded = (json.dumps(manifest, ensure_ascii=True, indent=2) + "\n").encode("utf-8")
    if len(encoded) > 64 * 1024 or len(encoded) + sum(map(len, textures.values())) > MAX_ARCHIVE_BYTES:
        raise ValueError("The expanded .orskin archive exceeds its size limit.")
    fd, temporary = tempfile.mkstemp(prefix=".openrc-skin-", suffix=".tmp", dir=str(output.parent))
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("manifest.json", encoded)
            for name, png in textures.items():
                archive.writestr(name, png)
        if os.path.getsize(temporary) > MAX_ARCHIVE_BYTES:
            raise ValueError("The .orskin archive exceeds 32 MiB.")
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return output, sizes


def main(argv=None):
    parser = argparse.ArgumentParser(description="Package this kit's paint PNGs as an OpenRC .orskin.")
    parser.add_argument("image", nargs="?", help="Single PNG for a one-image kit, or folder containing Paint-NN.png files")
    parser.add_argument("--output", required=True, help="Destination .orskin file")
    parser.add_argument("--label", help="Paint name, up to 48 printable characters (default: output filename)")
    args = parser.parse_args(argv)
    try:
        output, sizes = pack_image(args.image, args.output, args.label)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Cannot package paint: {error}", file=sys.stderr)
        return 1
    print(f"Saved {output} ({len(sizes)} PNG image(s)). Review the paint on the aircraft in OpenRC.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
