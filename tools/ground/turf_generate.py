#!/usr/bin/env python3
"""L9e deterministic periodic turf data. Python stdlib only; no external art.

Packed linear RGBA8: world x/z slopes, centered tone, reserved neutral channel.
Artistic estimates: 2 m tile, 18,000 tapered blades, lengths 25–110 mm.
Run --check to verify the committed PNG exactly. Ours, repository MIT license.
"""
import argparse
import hashlib
import math
from pathlib import Path
import random
import struct
import zlib

SIZE = 1024
SEED = 9105
OUTPUT = Path(__file__).resolve().parents[2] / 'app/assets/landscape/turf/detail.png'


def generate():
    rng = random.Random(SEED)
    height = [0.0] * (SIZE * SIZE)
    for _ in range(18000):
        x, y = rng.random() * SIZE, rng.random() * SIZE
        angle = rng.random() * math.tau
        length = rng.uniform(.025, .110) * SIZE / 2
        width = rng.uniform(.002, .005) * SIZE / 2
        strength = rng.uniform(.3, 1)
        dx, dy = math.cos(angle), math.sin(angle)
        for step in range(int(length) + 1):
            t = step / length
            radius = max(.55, width * (1 - t) * .5)
            cx, cy = x + dx * step, y + dy * step
            for j in range(math.floor(cy - radius), math.ceil(cy + radius) + 1):
                for i in range(math.floor(cx - radius), math.ceil(cx + radius) + 1):
                    distance = math.hypot(i - cx, j - cy)
                    h = strength * max(0, 1 - distance / radius) * math.sin(math.pi * min(t + .12, 1))
                    idx = (j % SIZE) * SIZE + i % SIZE
                    height[idx] = max(height[idx], h)
    mean = sum(height) / len(height)
    raw = bytearray()
    for j in range(SIZE):
        raw.append(0)  # PNG filter None: reproducible using stdlib.
        for i in range(SIZE):
            hx = height[j * SIZE + (i + 1) % SIZE] - height[j * SIZE + (i - 1) % SIZE]
            hz = height[((j + 1) % SIZE) * SIZE + i] - height[((j - 1) % SIZE) * SIZE + i]
            tone = .5 + (height[j * SIZE + i] - mean) * .65
            raw.extend(max(0, min(255, round(v * 255))) for v in (.5 - hx * .5, .5 - hz * .5, tone, .5))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--check', action='store_true')
    args = p.parse_args()
    data = generate()
    if args.check:
        assert OUTPUT.read_bytes() == data, 'regenerate turf data'
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(data)
    print('turf data', len(data), 'bytes; SHA256', hashlib.sha256(data).hexdigest())
