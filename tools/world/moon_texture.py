#!/usr/bin/env python3
"""FW-MOON-04: moon textures from the NASA SVS CGI Moon Kit (assets/sky/moon/source/, PROVENANCE.json).

Writes app/assets/sky/moon/:
  moon_albedo_2k.jpg  the SVS 2025 LROC colour map, copied byte for byte (2048x1024 sRGB JPEG, no re-encode).
  moon_normal_1k.png  1024x512 RGB8 local-frame normal map from LOLA ldem_4_uint.tif: R = east, G = north, B = up,
                      each 0.5 + 0.5 * n, linear data (not sRGB). Decode n = 2 * rgb - 1, then renormalise.
  LICENSE.md          credit, NASA media terms and provenance.

Both textures are equirectangular: u = (lon_east_deg + 180) / 360, v = (90 - lat_deg) / 180 (v = 0 is the top row,
north). The normal map uses the spherical metric on the 1737.4 km LOLA sphere: per source texel,
dh/dx = (dh/dlon) / ((R + h) cos(lat)) and dh/dy = (dh/dlat) / (R + h) by central differences (longitude wraps;
the first and last rows use one-sided differences), n = normalise(-dh/dx, -dh/dy, 1). The two slopes are computed on
the 1440x720 source grid and then area-averaged (exact box overlaps, cos(lat) area weights) to 1024x512, so each
texel holds the mean slope over its footprint without aliasing; averaging slopes rather than unit normals keeps the
operation linear. Relief fades to straight up between 86 and 88 degrees of latitude, where the 1/cos(lat) metric
turns sub-kilometre noise into spurious slopes. Relief is physical (exaggeration 1.0).

Dependencies: an explicit exception to the stdlib-only rule of tools/world. Decoding the TIFF needs Pillow and the
filter needs numpy, taken from the repository's pinned visual environment (app/tests/requirements-visual.txt:
numpy==2.5.3, pillow==12.3.0, installed with hashes). The PNG is written here with the standard-library zlib, so the
bytes do not depend on Pillow's encoder. No network access; downloaded files are only read.
  "$(app/tests/visual-env.sh)" tools/world/moon_texture.py            write the outputs
  "$(app/tests/visual-env.sh)" tools/world/moon_texture.py --check    exit 1 unless the outputs are byte-identical
"""
from __future__ import annotations

import hashlib
import io
import json
import math
import struct
import sys
import zlib
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover - environment setup message
    raise SystemExit('numpy and Pillow are required: run with "$(app/tests/visual-env.sh)"') from exc

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "assets" / "sky" / "moon"
OUT_DIR = ROOT / "app" / "assets" / "sky" / "moon"
PIPELINE_VERSION = "fw-moon-04-v1"
PINNED = {"numpy": "2.5.3", "Pillow": "12.3.0"}

ALBEDO_SOURCE = "source/lroc_color_2k.jpg"
LDEM_SOURCE = "source/ldem_4_uint.tif"
ALBEDO_OUT = "moon_albedo_2k.jpg"
NORMAL_OUT = "moon_normal_1k.png"
LICENSE_OUT = "LICENSE.md"

MOON_RADIUS_M = 1737400.0  # LOLA reference sphere (SVS 4720 page)
LDEM_OFFSET = 20000  # uint16 TIFF = signed half-metres + 20000
LDEM_METRES_PER_UNIT = 0.5
LDEM_SIZE = (1440, 720)  # 4 pixels per degree
NORMAL_SIZE = (1024, 512)
RELIEF_EXAGGERATION = 1.0  # physical relief; any other value is an art choice and must be labelled
POLE_FADE_START_DEG = 86.0  # full relief equatorward of this latitude
POLE_FADE_END_DEG = 88.0  # straight up poleward of this latitude
PNG_FILTER = 3  # PNG "Average" on every row: the smallest of the five fixed filters for this map (707,536 vs 710,893-762,565 B)
ZLIB_LEVEL = 9


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def provenance() -> dict:
    return json.loads((SOURCE_ROOT / "PROVENANCE.json").read_text(encoding="utf-8"))


def source_bytes(manifest: dict, relative: str) -> bytes:
    entries = {entry["file"]: entry for entry in manifest["files"]}
    if relative not in entries:
        sys.exit(f"{relative}: no entry in assets/sky/moon/PROVENANCE.json")
    data = (SOURCE_ROOT / relative).read_bytes()
    entry = entries[relative]
    if len(data) != int(entry["bytes"]) or sha256(data) != entry["sha256"]:
        sys.exit(f"{relative}: size or SHA-256 differs from assets/sky/moon/PROVENANCE.json")
    return data


def elevation_m(data: bytes) -> np.ndarray:
    """LOLA elevation in metres above the 1737.4 km sphere, rows north to south, columns from 180 W eastward."""
    with Image.open(io.BytesIO(data)) as image:
        if image.format != "TIFF" or image.mode not in ("I;16", "I;16B") or image.size != LDEM_SIZE:
            sys.exit(f"{LDEM_SOURCE}: expected a {LDEM_SIZE[0]}x{LDEM_SIZE[1]} 16-bit TIFF, got {image.format} {image.mode} {image.size}")
        raw = np.asarray(image).astype(np.float64)
    return (raw - LDEM_OFFSET) * LDEM_METRES_PER_UNIT


def _box_weights(n_in: int, n_out: int, edge_value=None) -> tuple[np.ndarray, np.ndarray]:
    """Exact box overlaps from n_in cells to n_out cells spanning the same interval (same first edge).

    Returns (index, weight), each (n_out, k); weights of a row sum to 1. edge_value maps a cell edge, in units of
    1 / (n_in * n_out) of the interval, to the measure used for the weights (default: length)."""
    unit_in, unit_out = n_out, n_in  # common units: the interval is n_in * n_out long
    rows: list[list[tuple[int, float]]] = []
    for j in range(n_out):
        a, b = j * unit_out, (j + 1) * unit_out
        parts = []
        for i in range(a // unit_in, min(n_in, (b - 1) // unit_in + 1)):
            lo, hi = max(a, i * unit_in), min(b, (i + 1) * unit_in)
            if hi > lo:
                weight = float(hi - lo) if edge_value is None else edge_value(lo) - edge_value(hi)
                parts.append((i, weight))
        total = sum(w for _, w in parts)
        rows.append([(i, w / total) for i, w in parts])
    k = max(len(r) for r in rows)
    index = np.zeros((n_out, k), dtype=np.int64)
    weight = np.zeros((n_out, k), dtype=np.float64)
    for j, parts in enumerate(rows):
        for m, (i, w) in enumerate(parts):
            index[j, m] = i
            weight[j, m] = w
    return index, weight


def area_average(field: np.ndarray, width: int, height: int) -> np.ndarray:
    """Area-weighted box average of an equirectangular field to width x height, in a fixed summation order."""
    rows_in, cols_in = field.shape
    span = rows_in * height
    # Weight by the area between two latitude edges: sin(lat_top) - sin(lat_bottom).
    lat_sin = lambda u: math.sin(math.radians(90.0 - 180.0 * u / span))  # noqa: E731
    r_index, r_weight = _box_weights(rows_in, height, lat_sin)
    c_index, c_weight = _box_weights(cols_in, width)
    by_rows = np.zeros((height, cols_in), dtype=np.float64)
    for m in range(r_index.shape[1]):
        by_rows += r_weight[:, m, None] * field[r_index[:, m], :]
    out = np.zeros((height, width), dtype=np.float64)
    for m in range(c_index.shape[1]):
        out += c_weight[None, :, m] * by_rows[:, c_index[:, m]]
    return out


def latitudes_deg(height: int) -> np.ndarray:
    return np.array([90.0 - (row + 0.5) * 180.0 / height for row in range(height)], dtype=np.float64)


def normals(h: np.ndarray) -> np.ndarray:
    """Unit (east, north, up) normals, float64 (NORMAL_SIZE[1], NORMAL_SIZE[0], 3)."""
    rows, cols = h.shape
    d_lon = 2.0 * math.pi / cols
    d_lat = math.pi / rows
    cos_lat = np.array([math.cos(math.radians(v)) for v in latitudes_deg(rows)], dtype=np.float64)[:, None]
    radius = MOON_RADIUS_M + h
    dh_dlon = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) / (2.0 * d_lon)
    dh_dlat = np.empty_like(h)  # latitude decreases with the row index
    dh_dlat[1:-1] = (h[:-2] - h[2:]) / (2.0 * d_lat)
    dh_dlat[0] = (h[0] - h[1]) / d_lat
    dh_dlat[-1] = (h[-2] - h[-1]) / d_lat
    slope_east = dh_dlon / (radius * cos_lat)
    slope_north = dh_dlat / radius
    width, height = NORMAL_SIZE
    slope_east = area_average(slope_east, width, height)
    slope_north = area_average(slope_north, width, height)
    t = np.clip((POLE_FADE_END_DEG - np.abs(latitudes_deg(height))) / (POLE_FADE_END_DEG - POLE_FADE_START_DEG), 0.0, 1.0)
    fade = (t * t * (3.0 - 2.0 * t))[:, None] * RELIEF_EXAGGERATION
    n = np.stack([-slope_east * fade, -slope_north * fade, np.ones_like(slope_east)], axis=-1)
    n /= np.sqrt(np.sum(n * n, axis=-1, keepdims=True))
    if not np.all(np.isfinite(n)):
        sys.exit("normal map has non-finite values")
    return n


def encode_rgb8(n: np.ndarray) -> np.ndarray:
    return np.clip(np.floor((0.5 + 0.5 * n) * 255.0 + 0.5), 0, 255).astype(np.uint8)


def _filter_rows(pixels: np.ndarray, kind: int) -> bytes:
    """PNG scanlines with one fixed filter type (RFC 2083 section 6), bytes per pixel = 3."""
    x = pixels.reshape(pixels.shape[0], -1).astype(np.int16)
    left = np.zeros_like(x)
    left[:, 3:] = x[:, :-3]
    up = np.zeros_like(x)
    up[1:] = x[:-1]
    if kind == 0:
        f = x
    elif kind == 1:
        f = x - left
    elif kind == 2:
        f = x - up
    elif kind == 3:
        f = x - (left + up) // 2
    elif kind == 4:
        up_left = np.zeros_like(x)
        up_left[1:, 3:] = x[:-1, :-3]
        p = left + up - up_left
        pa, pb, pc = np.abs(p - left), np.abs(p - up), np.abs(p - up_left)
        f = x - np.where((pa <= pb) & (pa <= pc), left, np.where(pb <= pc, up, up_left))
    else:
        raise ValueError(kind)
    body = (f & 0xFF).astype(np.uint8)
    lines = np.concatenate([np.full((x.shape[0], 1), kind, dtype=np.uint8), body], axis=1)
    return lines.tobytes()


def png_rgb8(pixels: np.ndarray, text: dict[str, str], kind: int = PNG_FILTER) -> bytes:
    height, width, channels = pixels.shape
    if channels != 3 or pixels.dtype != np.uint8:
        raise ValueError("expected RGB8")

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    out = [b"\x89PNG\r\n\x1a\n", chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))]
    for key in sorted(text):
        out.append(chunk(b"tEXt", key.encode("latin-1") + b"\0" + text[key].encode("latin-1")))
    out.append(chunk(b"IDAT", zlib.compress(_filter_rows(pixels, kind), ZLIB_LEVEL)))
    out.append(chunk(b"IEND", b""))
    return b"".join(out)


def license_text(manifest: dict, albedo: bytes, ldem: bytes, normal_png: bytes) -> str:
    c = manifest["collection"]
    return f"""# Moon textures: credit and licence

Credit: **{c["credit"]}**. CGI Moon Kit, SVS ID 4720, <{c["page_url"]}>.
Visualizer Ernie Wright (USRA); scientist Noah Petro (NASA/GSFC). Data: LRO LROC WAC colour mosaic (Arizona State
University) and LRO LOLA elevation.

NASA media terms (<{c["license_url"]}>): NASA material is generally not subject to copyright in the United States;
NASA must be acknowledged as the source; use must not state or imply NASA endorsement. No NASA insignia or logotype
is used. SVS notes that the maps are "optimized for aesthetics, not science".

These files are reference-derived generated outputs. Do not edit them; rebuild them with
`"$(app/tests/visual-env.sh)" tools/world/moon_texture.py` (`--check` verifies them). Sources and hashes:
`assets/sky/moon/PROVENANCE.json`.

| File | Made from | SHA-256 |
| --- | --- | --- |
| `{ALBEDO_OUT}` | `{ALBEDO_SOURCE}` (sha256 `{sha256(albedo)}`), copied byte for byte | `{sha256(albedo)}` |
| `{NORMAL_OUT}` | `{LDEM_SOURCE}` (sha256 `{sha256(ldem)}`), local east/north/up normals | `{sha256(normal_png)}` |

Mapping (both textures): equirectangular, u = (east longitude + 180°) / 360°, v = (90° − latitude) / 180°; the left
edge is 180° W, the centre 0°, north at the top. The normal map is linear data: n = 2·rgb − 1 in the local (east, north,
up) frame on the 1737.4 km sphere; relief ×{RELIEF_EXAGGERATION:g}, faded to up poleward of {POLE_FADE_START_DEG:g}–{POLE_FADE_END_DEG:g}°.
Pipeline `{PIPELINE_VERSION}`.
"""


def build() -> dict[str, bytes]:
    manifest = provenance()
    albedo = source_bytes(manifest, ALBEDO_SOURCE)
    with Image.open(io.BytesIO(albedo)) as image:
        if image.format != "JPEG" or image.mode != "RGB" or image.size != (2048, 1024):
            sys.exit(f"{ALBEDO_SOURCE}: expected a 2048x1024 RGB JPEG")
    ldem = source_bytes(manifest, LDEM_SOURCE)
    pixels = encode_rgb8(normals(elevation_m(ldem)))
    normal_png = png_rgb8(pixels, {
        "Description": "Moon local-frame normal map: R=east G=north B=up, n = 2*rgb - 1, linear; equirectangular, left edge 180 W, north up.",
        "Source": f"NASA's Scientific Visualization Studio, CGI Moon Kit (SVS 4720) {LDEM_SOURCE} sha256 {sha256(ldem)}",
        "Software": f"tools/world/moon_texture.py {PIPELINE_VERSION}",
    })
    return {
        ALBEDO_OUT: albedo,
        NORMAL_OUT: normal_png,
        LICENSE_OUT: license_text(manifest, albedo, ldem, normal_png).encode("utf-8"),
    }


def _decoded_equal(a: bytes, b: bytes) -> bool:
    try:
        with Image.open(io.BytesIO(a)) as ia, Image.open(io.BytesIO(b)) as ib:
            return ia.size == ib.size and np.array_equal(np.asarray(ia), np.asarray(ib))
    except Exception:  # noqa: BLE001 - diagnostic only
        return False


def main() -> int:
    import numpy
    import PIL

    versions = {"numpy": numpy.__version__, "Pillow": PIL.__version__}
    if versions != PINNED:
        print(f"warning: pinned {PINNED}, running {versions}; use \"$(app/tests/visual-env.sh)\"", file=sys.stderr)
    outputs = build()
    if "--check" in sys.argv[1:]:
        stale = []
        for name, data in outputs.items():
            path = OUT_DIR / name
            current = path.read_bytes() if path.exists() else None
            if current != data:
                note = ""
                if current is not None and name.endswith(".png") and _decoded_equal(current, data):
                    note = " (pixels identical; only the compressed stream differs: zlib build)"
                stale.append(f"{name}{note}")
        if stale:
            print(f"moon textures are stale: {', '.join(stale)}; run tools/world/moon_texture.py", file=sys.stderr)
            return 1
        print(f"moon textures current ({len(outputs)} files)")
        return 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, data in outputs.items():
        (OUT_DIR / name).write_bytes(data)
        print(f"{name}: {len(data)} bytes sha256 {sha256(data)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
