"""LU-16-R2: reduce downloaded SRTM relief to a bounded four-chunk backdrop.

No dependencies. Source crop is retained for offline regeneration; --download-source
recreates it from the SHA-256-pinned public terrain tile. This is an art-directed
backdrop, not a georeferenced field or physical height sampler.
"""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import struct
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/landscape/mountains/chingaza.hgt.gz"
OUTPUT = ROOT / "app/data/fields/mountains.json"
NORMAL_OUTPUT = ROOT / "app/assets/landscape/mountains/relief.png"
URL = "https://s3.amazonaws.com/elevation-tiles-prod/skadi/N04/N04W074.hgt.gz"
TILE_SHA256 = "2471314dae35ad938cb53092ff4bc9cd2929beab4dcd5a2bad4973e65e7eccab"
CROP_SHA256 = "d639fc35d79a5117cd8a9474941278fe8b306dc1463dc1e1938092eb607d2222"
# Inclusive integer arc-second crop: 4.42–4.72 N, 73.96–73.70 W.
TOP, BOTTOM, LEFT, RIGHT = 1008, 2088, 144, 1080
WIDTH, HEIGHT = RIGHT - LEFT + 1, BOTTOM - TOP + 1
COLUMNS, ROWS = 192, 72


def download_source():
    with urllib.request.urlopen(URL, timeout=90) as response:
        archive = response.read()
    if hashlib.sha256(archive).hexdigest() != TILE_SHA256:
        raise ValueError("Upstream tile changed; review provenance before updating")
    tile = gzip.decompress(archive)
    if len(tile) != 3601 * 3601 * 2:
        raise ValueError("Unexpected SRTM dimensions")
    crop = b"".join(tile[(row * 3601 + LEFT) * 2:(row * 3601 + RIGHT + 1) * 2]
                    for row in range(TOP, BOTTOM + 1))
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    SOURCE.write_bytes(gzip.compress(crop, mtime=0))


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def source_sampler():
    source = gzip.decompress(SOURCE.read_bytes())
    if hashlib.sha256(source).hexdigest() != CROP_SHA256:
        raise ValueError("Retained source crop changed; review provenance before updating")
    if len(source) != WIDTH * HEIGHT * 2:
        raise ValueError("Unexpected source crop dimensions")
    data = struct.unpack(f">{WIDTH * HEIGHT}h", source)
    if min(data) <= -32768:
        raise ValueError("Source contains void elevations")

    def sample(x, y):
        # Small area filter before reduction: retain drainage without aliasing
        # isolated 30 m peaks onto the reduced render grid.
        cx, cy = round(x), round(y)
        return sum(data[min(HEIGHT - 1, max(0, cy + dy)) * WIDTH
                        + min(WIDTH - 1, max(0, cx + dx))]
                   for dy in range(-2, 3) for dx in range(-2, 3)) / 25

    def terrain(u, v):
        elevation = sample(v * (WIDTH - 1), (1.0 - u) * (HEIGHT - 1))
        edge = smooth(u / 0.12) * smooth((1 - u) / 0.12)
        edge *= smooth(v / 0.20) * smooth((1 - v) / 0.18)
        return max(0.0, elevation - 1850.0) * 0.70 * edge

    return terrain


def generate():
    terrain = source_sampler()
    heights = []
    for row in range(ROWS + 1):
        v = row / ROWS
        for column in range(COLUMNS + 1):
            u = column / COLUMNS
            # Rotate the north/south source ridge across the field's north horizon.
            height = terrain(u, v)
            heights.append(round(height * 100) / 100)
    # Object-space normals retain source gullies below the mesh resolution.
    # RGBA = render-world normal XYZ + gentle local cavity occlusion; one fetch.
    w, h = 513, 193
    detail = [[terrain(x / (w - 1), y / (h - 1)) for x in range(w)] for y in range(h)]
    pixels = bytearray()
    for y in range(h):
        pixels.append(0)  # PNG filter: none
        for x in range(w):
            west, east = max(0, x - 1), min(w - 1, x + 1)
            south, north = max(0, y - 1), min(h - 1, y + 1)
            de = (detail[y][east] - detail[y][west]) / ((east - west) * 13000 / (w - 1))
            dn = (detail[north][x] - detail[south][x]) / ((north - south) * 7000 / (h - 1))
            length = math.sqrt(de * de + dn * dn + 1)
            neighbours = [detail[min(h - 1, max(0, y + dy))][min(w - 1, max(0, x + dx))]
                          for dx, dy in [(-4, 0), (4, 0), (0, -4), (0, 4)]]
            cavity = max(0.72, 1 - max(0, sum(neighbours) / 4 - detail[y][x]) * 0.006)
            pixels.extend(round((v / length * 0.5 + 0.5) * 255) for v in (-de, 1.0, dn))
            pixels.append(round(cavity * 255))

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload))

    normal = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    normal += chunk(b"IDAT", zlib.compress(bytes(pixels), 9)) + chunk(b"IEND", b"")
    profile = (json.dumps({
        "format": "openrc-visual-mountains v1",
        "source": URL,
        "source_tile_sha256": TILE_SHA256,
        "source_crop_sha256": CROP_SHA256,
        "attribution": "SRTM data courtesy of the U.S. Geological Survey; Mapzen Terrain Tiles.",
        "generator": "tools/terrain/import_mountains.py",
        "physical_terrain": False,
        "columns": COLUMNS, "rows": ROWS,
        "east_min_m": -6500.0, "east_max_m": 6500.0,
        "north_min_m": 1600.0, "north_max_m": 8600.0,
        "heights_m": heights,
    }, separators=(",", ":")) + "\n").encode()
    return profile, normal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download-source", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--normal-output", type=Path, default=NORMAL_OUTPUT)
    args = parser.parse_args()
    if args.download_source:
        download_source()
    result, normal = generate()
    if args.check:
        if args.output.read_bytes() != result:
            raise SystemExit("Mountain profile is stale or edited")
        if args.normal_output.read_bytes() != normal:
            raise SystemExit("Mountain relief texture is stale or edited")
        print("Mountain profile and relief texture match retained SRTM source")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(result)
        args.normal_output.parent.mkdir(parents=True, exist_ok=True)
        args.normal_output.write_bytes(normal)
        print(f"Wrote {args.output}: {len(result)} bytes, {COLUMNS * ROWS * 2} triangles")


if __name__ == "__main__":
    main()
