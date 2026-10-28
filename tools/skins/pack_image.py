#!/usr/bin/env python3
"""Package an existing X8 UV-atlas PNG as an OpenRC paint, without Blender.

    python pack_image.py painted-atlas.png --output paint.orskin --label "My paint"

The input must follow the Skywalker X8's *existing* x8_livery UV layout. A
photograph or illustration of an aircraft is not a UV atlas. Validation can
check PNG integrity and size, but cannot establish alignment or appearance.
The SHA-256 below pins the stock GLB from app/data/aircraft_models/skywalker-x8.json.
"""

import argparse
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import zipfile
import zlib


BASE_ASSET_SHA256 = "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac"
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


def pack_image(image_path, output_path, label=None):
    """Validate and atomically publish a one-material X8 .orskin archive."""
    source = Path(image_path).expanduser().resolve()
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
    with source.open("rb") as handle:
        png = handle.read(MAX_PNG_BYTES + 1)
    width, height = inspect_png(png)
    manifest = {
        "format": "openrc-skin", "version": 1,
        "aircraft_id": "skywalker-x8", "base_asset_sha256": BASE_ASSET_SHA256,
        "label": label,
        "materials": [{"name": "x8_livery", "base_color": [1, 1, 1, 1], "texture": "texture-01.png"}],
    }
    encoded = (json.dumps(manifest, ensure_ascii=True, indent=2) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=".openrc-skin-", suffix=".tmp", dir=str(output.parent))
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("manifest.json", encoded)
            archive.writestr("texture-01.png", png)
        if os.path.getsize(temporary) > MAX_ARCHIVE_BYTES:
            raise ValueError("The .orskin archive exceeds 32 MiB.")
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return output, width, height


def main(argv=None):
    parser = argparse.ArgumentParser(description="Package an existing Skywalker X8 UV-atlas PNG as an OpenRC .orskin.")
    parser.add_argument("image", help="Painted X8 atlas PNG, following the original UV layout")
    parser.add_argument("--output", required=True, help="Destination .orskin file")
    parser.add_argument("--label", help="Paint name, up to 48 printable characters (default: output filename)")
    args = parser.parse_args(argv)
    try:
        output, width, height = pack_image(args.image, args.output, args.label)
    except (OSError, ValueError) as error:
        print(f"Cannot package paint: {error}", file=sys.stderr)
        return 1
    print(f"Saved {output} ({width} × {height} PNG). Review the paint on the aircraft in OpenRC.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
