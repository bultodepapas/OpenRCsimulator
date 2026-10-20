"""Bake art-directed rock, sheltered vegetation and upland masks from retained SRTM.

This is a decorative material classification, not a surveyed biome/hydrology map.
No third-party dependencies; no noise or habitat calculations in the frame loop.
"""
import argparse
import math
from pathlib import Path
import struct
import zlib

from import_mountains import ROOT, smooth, source_sampler

OUTPUT = ROOT / "app/assets/landscape/mountains/habitat.png"
WIDTH, HEIGHT = 513, 193


def generate():
    terrain = source_sampler()
    heights = [[terrain(x / (WIDTH - 1), y / (HEIGHT - 1))
                for x in range(WIDTH)] for y in range(HEIGHT)]

    def at(x, y):
        return heights[min(HEIGHT - 1, max(0, y))][min(WIDTH - 1, max(0, x))]

    pixels = bytearray()
    for y in range(HEIGHT):
        pixels.append(0)
        for x in range(WIDTH):
            h = at(x, y)
            de = (at(x + 1, y) - at(x - 1, y)) / (26000 / (WIDTH - 1))
            dn = (at(x, y + 1) - at(x, y - 1)) / (14000 / (HEIGHT - 1))
            slope = math.hypot(de, dn)
            # Broad concavity follows source gullies; positive values are sheltered.
            neighbours = [at(x + dx, y + dy)
                          for dx, dy in [(-6, 0), (6, 0), (0, -4), (0, 4)]]
            concavity = (sum(neighbours) / 4 - h) / 45
            rock = smooth((slope - 0.34) / 0.55) * smooth((h - 300) / 650)
            shelter = smooth(0.35 + concavity) * (1 - smooth((h - 1000) / 500))
            upland = smooth((h - 550) / 800)
            pixels.extend(round(v * 255) for v in (rock, shelter, upland))

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload))

    result = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    return result + chunk(b"IDAT", zlib.compress(bytes(pixels), 9)) + chunk(b"IEND", b"")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    result = generate()
    if args.check:
        if args.output.read_bytes() != result:
            raise SystemExit("Mountain habitat texture is stale or edited")
        print("Mountain habitat texture matches retained SRTM source")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(result)
        print(f"Wrote {args.output}: {len(result)} bytes")


if __name__ == "__main__":
    main()
