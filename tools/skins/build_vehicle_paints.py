"""Build the stock paint textures of the HX-700 helicopter and the RC cars.

Every output is derived from assets already in the repository (the HX-700 GLB and
its paint masks and the Monster Car 2 livery and emission map), so the result is
reproducible byte for byte:

    .tools/visual-venv/Scripts/python.exe tools/skins/build_vehicle_paints.py
    .tools/visual-venv/Scripts/python.exe tools/skins/build_vehicle_paints.py --check

Outputs go to app/assets/vehicle-paints/. Runtime bindings live in
app/data/vehicle_paints.json and are applied by app/render/vehicle_paint.gd.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
OUT = APP / "assets" / "vehicle-paints"
HX_GLB = APP / "assets/aircraft/hx-700/hx-700.glb"
HX_BOOM = APP / "assets/aircraft/hx-700/hx-700_hx700_botalon_mascaras.png"
MC_LIVERY = APP / "assets/vehicles/monster-car-2/monster_truck_nitro_1_carroceria_color.jpg"

CANOPY_SIZE = (2048, 1024)  # the HX-700 skin-kit canopy atlas size
BOOM_SIZE = (4096, 440)  # the HX-700 skin-kit boom atlas size


def hex_rgb(value: str) -> np.ndarray:
    value = value.lstrip("#")
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float64)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    t = np.asarray(t)[..., None]
    return a * (1.0 - t) + b * t


# ---------------------------------------------------------------------------------------------
# glTF reading
# ---------------------------------------------------------------------------------------------
CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path: Path):
    data = path.read_bytes()
    json_len = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + json_len])
    binary = data[20 + json_len + 8:]

    def accessor(index: int) -> np.ndarray:
        acc = doc["accessors"][index]
        view = doc["bufferViews"][acc["bufferView"]]
        dtype = np.dtype(CT[acc["componentType"]])
        count, comps = acc["count"], NC[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", 0) or dtype.itemsize * comps
        rows = [np.frombuffer(binary, dtype=dtype, count=comps, offset=start + i * stride) for i in range(count)] \
            if stride != dtype.itemsize * comps else None
        if rows is not None:
            return np.stack(rows)
        return np.frombuffer(binary, dtype=dtype, count=count * comps, offset=start).reshape(count, comps)

    return doc, accessor


def primitives_for(path: Path, material: str):
    doc, accessor = read_glb(path)
    names = [m["name"] for m in doc["materials"]]
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            if names[prim["material"]] != material:
                continue
            attrs = prim["attributes"]
            yield (accessor(attrs["POSITION"]).astype(np.float64), accessor(attrs["NORMAL"]).astype(np.float64),
                   accessor(attrs["TEXCOORD_0"]).astype(np.float64), accessor(prim["indices"]).reshape(-1, 3))


# ---------------------------------------------------------------------------------------------
# UV-space bake: rasterize triangles, interpolate model-space position and normal per texel
# ---------------------------------------------------------------------------------------------
def bake_attributes(path: Path, material: str, size):
    width, height = size
    pos_map = np.zeros((height, width, 3))
    nrm_map = np.zeros((height, width, 3))
    weight = np.zeros((height, width))
    for pos, nrm, uv, tris in primitives_for(path, material):
        px = uv * np.array([width, height])
        for tri in tris:
            p = px[tri]
            x0, y0 = np.floor(p.min(0)).astype(int)
            x1, y1 = np.ceil(p.max(0)).astype(int)
            x0, y0 = max(x0, 0), max(y0, 0)
            x1, y1 = min(x1, width - 1), min(y1, height - 1)
            if x1 < x0 or y1 < y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = p
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-12:
                continue
            w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / det
            w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / det
            w2 = 1.0 - w0 - w1
            inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
            if not inside.any():
                continue
            ws = np.stack([w0[inside], w1[inside], w2[inside]], axis=1)
            yi = ys[inside].astype(int)
            xi = xs[inside].astype(int)
            pos_map[yi, xi] += ws @ pos[tri]
            nrm_map[yi, xi] += ws @ nrm[tri]
            weight[yi, xi] += 1.0
    covered = weight > 0
    pos_map[covered] /= weight[covered][:, None]
    norms = np.linalg.norm(nrm_map, axis=2, keepdims=True)
    nrm_map = np.where(norms > 1e-9, nrm_map / np.maximum(norms, 1e-9), 0.0)
    return pos_map, nrm_map, covered


def dilate(image: np.ndarray, covered: np.ndarray, passes: int = 8) -> np.ndarray:
    """Bleed island colours outward so mip levels and filtering never sample the background."""
    image = image.copy()
    covered = covered.copy()
    for _ in range(passes):
        acc = np.zeros_like(image)
        count = np.zeros(covered.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            shifted = np.roll(np.roll(covered, dy, 0), dx, 1)
            acc += np.roll(np.roll(image * covered[..., None], dy, 0), dx, 1)
            count += shifted
        grow = (~covered) & (count > 0)
        image[grow] = acc[grow] / count[grow][:, None]
        covered = covered | grow
    return image


# ---------------------------------------------------------------------------------------------
# HX-700 canopy designs, evaluated in the canopy's model space (glTF axes: +X nose, +Y up, Z lateral)
# ---------------------------------------------------------------------------------------------
def canopy_frame(pos):
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    s = (x - (-0.103)) / (0.387 - (-0.103))  # 0 = rear edge, 1 = nose
    h = (y - 0.095) / (0.288 - 0.095)  # 0 = lower edge, 1 = top
    return s, h, z


def band(s, h, start_h, slope, half_width, soft=0.012):
    centre = start_h + slope * s
    return 1.0 - smoothstep(half_width - soft, half_width + soft, np.abs(h - centre))


def _screen_distance(s, h):
    return ((s - 0.80) / 0.20) ** 2 + ((h - 0.66) / 0.30) ** 2


def windscreen(s, h, nrm):
    """Smoked screen on the forward upper canopy, shaped like the factory mask."""
    upper = smoothstep(0.32, 0.40, h)
    return (1.0 - smoothstep(0.92, 1.0, _screen_distance(s, h))) * upper * (nrm[..., 1] > -0.2)


def screen_keyline(s, h, nrm, inner=1.0, outer=1.16):
    """A painted border just outside the screen, as on real moulded canopies."""
    d = _screen_distance(s, h)
    ring = smoothstep(inner - 0.02, inner + 0.02, d) * (1.0 - smoothstep(outer - 0.03, outer + 0.03, d))
    return ring * smoothstep(0.30, 0.38, h) * (nrm[..., 1] > -0.2)


def body_shading(colour, h):
    """Bake a gentle occlusion falloff toward the belly; flat paint reads as plastic, graded paint as a shell."""
    return colour * (0.86 + 0.14 * smoothstep(0.0, 0.55, h))[..., None]


FONT = APP / "assets/fonts/NotoSansCJKjp-Regular.otf"  # SIL OFL 1.1 (assets/fonts/OFL-NotoSansCJK.txt)
_LETTERING_CACHE: dict = {}


def _lettering_image(text: str, aspect: float) -> np.ndarray:
    """Italic, heavy lettering mask (1 = ink) on a canvas whose aspect matches the target box."""
    key = (text, round(aspect, 3))
    if key in _LETTERING_CACHE:
        return _LETTERING_CACHE[key]
    from PIL import ImageDraw, ImageFont
    height = 256
    width = int(round(height * aspect))
    canvas = Image.new("L", (width * 2, height), 0)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(FONT), int(height * 0.78))
    box = draw.textbbox((0, 0), text, font=font, stroke_width=10)
    x = (width * 2 - (box[2] - box[0])) // 2 - box[0]
    y = (height - (box[3] - box[1])) // 2 - box[1]
    draw.text((x, y), text, fill=255, font=font, stroke_width=10, stroke_fill=255)
    shear = 0.22  # forward-leaning racing italic
    canvas = canvas.transform(canvas.size, Image.AFFINE, (1, shear, -shear * height * 0.5, 0, 1, 0), Image.BICUBIC)
    bbox = canvas.getbbox() or (0, 0, width, height)
    ink = canvas.crop(bbox)
    scale = min(width / ink.width, height / ink.height) * 0.94
    ink = ink.resize((max(1, int(ink.width * scale)), max(1, int(ink.height * scale))), Image.LANCZOS)
    final = Image.new("L", (width, height), 0)
    final.paste(ink, ((width - ink.width) // 2, (height - ink.height) // 2))
    mask = np.asarray(final, dtype=np.float64) / 255.0
    _LETTERING_CACHE[key] = mask
    return mask


def lettering(s, h, z, nrm, text, s0, s1, h0, h1):
    """Side lettering that reads left-to-right from both sides (mirrored on the left, -Z, side)."""
    # Physical aspect of the box: canopy length 0.490 m by height 0.193 m.
    aspect = ((s1 - s0) * 0.490) / ((h1 - h0) * 0.193)
    mask = _lettering_image(text, aspect)
    rows, cols = mask.shape
    x = np.where(z >= 0.0, (s - s0) / (s1 - s0), (s1 - s) / (s1 - s0))
    y = (h1 - h) / (h1 - h0)
    inside = (x >= 0.0) & (x < 1.0) & (y >= 0.0) & (y < 1.0)
    xi = np.clip((x * cols).astype(int), 0, cols - 1)
    yi = np.clip((y * rows).astype(int), 0, rows - 1)
    side = smoothstep(0.30, 0.50, np.abs(nrm[..., 2]))
    return np.where(inside, mask[yi, xi], 0.0) * side


def design_blanco_artico(s, h, z, nrm):
    # Pearl white with a cooler underside, a cyan sweep edged by navy pinstripes, navy belly and screen keyline.
    base = mix(np.broadcast_to(hex_rgb("#e9edf2"), s.shape + (3,)), hex_rgb("#f8f9fb"), smoothstep(0.2, 0.8, h))
    width = 0.10 + 0.06 * s
    sweep = band(s, h, 0.18, 0.52, width)
    edge = band(s, h, 0.18, 0.52, width + 0.022, soft=0.006) * (1.0 - sweep)
    pin = band(s, h, 0.03, 0.52, 0.012 + 0.008 * s, soft=0.006)
    belly = 1.0 - smoothstep(0.14, 0.18, h)
    out = mix(base, hex_rgb("#0aa3e0"), sweep * (s > 0.05))
    out = mix(out, hex_rgb("#0b2a5b"), np.maximum(np.maximum(pin * (s > 0.12), edge * (s > 0.05)), belly))
    out = mix(out, hex_rgb("#0b2a5b"), lettering(s, h, z, nrm, "HX-700", 0.10, 0.40, 0.47, 0.62))
    out = body_shading(out, h)
    out = mix(out, hex_rgb("#0aa3e0"), screen_keyline(s, h, nrm))
    return mix(out, hex_rgb("#11161c"), windscreen(s, h, nrm))


def design_rojo_fuego(s, h, z, nrm):
    # Candy red graded to deep crimson, three flame spears with dark keylines, black belly with gold lettering.
    base = mix(np.broadcast_to(hex_rgb("#8e0b22"), s.shape + (3,)), hex_rgb("#d0142f"), smoothstep(0.15, 0.75, h))
    out = base
    for i, (start, colour) in enumerate(((0.62, "#ffb000"), (0.46, "#ff6a00"), (0.30, "#ffd84a"))):
        reach = 0.95 - 0.12 * i
        width = (0.055 - 0.012 * i) * np.clip((reach - s) / reach, 0.0, 1.0)
        outline = band(s, h, start, -0.12 + 0.05 * i, width + 0.012, soft=0.005) * (s < reach + 0.02)
        spear = band(s, h, start, -0.12 + 0.05 * i, width, soft=0.006) * (s < reach)
        out = mix(out, hex_rgb("#3a0610"), outline * (1.0 - spear))
        out = mix(out, hex_rgb(colour), spear)
    belly = 1.0 - smoothstep(0.17, 0.2, h)
    out = mix(out, hex_rgb("#141414"), belly)
    gold_line = band(s, h, 0.205, 0.0, 0.008, soft=0.004)
    out = mix(out, hex_rgb("#ffb000"), gold_line)
    out = mix(out, hex_rgb("#ffb000"), lettering(s, h, z, nrm, "HX-700", 0.34, 0.62, 0.035, 0.165))
    out = body_shading(out, h)
    out = mix(out, hex_rgb("#141414"), screen_keyline(s, h, nrm))
    return mix(out, hex_rgb("#101215"), windscreen(s, h, nrm))


def design_negro_lima(s, h, z, nrm):
    # Gloss black, a lime lightning band with a white keyline, lime nose cap and white lettering.
    base = mix(np.broadcast_to(hex_rgb("#0f1114"), s.shape + (3,)), hex_rgb("#1b1e23"), smoothstep(0.2, 0.9, h))
    zig = 0.48 + 0.10 * (2.0 * np.abs(((s * 3.0) % 1.0) - 0.5) - 0.5)
    dist = np.abs(h - zig)
    lime = 1.0 - smoothstep(0.045, 0.06, dist)
    key = (1.0 - smoothstep(0.072, 0.082, dist)) * (1.0 - lime)
    out = mix(base, hex_rgb("#f4f6f8"), key * (s > 0.04))
    out = mix(out, hex_rgb("#9ee21b"), lime * (s > 0.04))
    nose_cap = smoothstep(0.93, 0.95, s) * (1.0 - smoothstep(0.30, 0.34, h))
    out = mix(out, hex_rgb("#9ee21b"), nose_cap)
    out = mix(out, hex_rgb("#f4f6f8"), lettering(s, h, z, nrm, "HX-700", 0.16, 0.46, 0.18, 0.32))
    out = body_shading(out, h)
    out = mix(out, hex_rgb("#9ee21b"), screen_keyline(s, h, nrm))
    return mix(out, hex_rgb("#07090b"), windscreen(s, h, nrm))


CANOPY_DESIGNS = {
    "blanco_artico": design_blanco_artico,
    "rojo_fuego": design_rojo_fuego,
    "negro_lima": design_negro_lima,
}

# Boom: the factory mask mixes black (base), red (stripe), yellow (HX-700 lettering) and blue (keyline).
BOOM_PALETTES = {
    "blanco_artico": {"base": "#f2f4f6", "stripe": "#0aa3e0", "letters": "#0b2a5b", "keyline": "#0b2a5b"},
    "rojo_fuego": {"base": "#c4122f", "stripe": "#141414", "letters": "#ffb000", "keyline": "#ffb000"},
    "negro_lima": {"base": "#15171b", "stripe": "#9ee21b", "letters": "#15171b", "keyline": "#f4f6f8"},
}

# Monster Car 2: the green body colour is re-tinted; flames, camouflage and sponsor art keep their colours.
MONSTER_TINTS = {
    "azul_electrico": {"hue": 214.0, "saturation": 1.05, "value": 1.08},
    "naranja_lava": {"hue": 24.0, "saturation": 1.0, "value": 1.5},
}
MC_EMISSION = APP / "assets/vehicles/monster-car-2/monster_truck_nitro_1_carroceria_emision.png"


def build_canopy(design) -> Image.Image:
    pos, nrm, covered = bake_attributes(HX_GLB, "Pintura_Carenado", CANOPY_SIZE)
    s, h, z = canopy_frame(pos)
    colour = design(s, h, z, nrm)
    colour[~covered] = 0.0
    colour = dilate(colour, covered)
    return Image.fromarray(np.clip(colour * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def build_boom(palette: dict) -> Image.Image:
    source = Image.open(HX_BOOM).convert("RGB").resize(BOOM_SIZE, Image.LANCZOS)
    rgb = np.asarray(source, dtype=np.float64) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    letters = g
    stripe = np.clip(r - g, 0.0, 1.0)
    keyline = b
    base = np.clip(1.0 - stripe - letters - keyline, 0.0, 1.0)
    out = (base[..., None] * hex_rgb(palette["base"]) + stripe[..., None] * hex_rgb(palette["stripe"])
           + letters[..., None] * hex_rgb(palette["letters"]) + keyline[..., None] * hex_rgb(palette["keyline"]))
    return Image.fromarray(np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    delta = mx - mn
    hue = np.zeros_like(mx)
    nz = delta > 1e-9
    rmax = nz & (mx == r)
    gmax = nz & (mx == g) & ~rmax
    bmax = nz & ~rmax & ~gmax
    hue[rmax] = ((g - b)[rmax] / delta[rmax]) % 6.0
    hue[gmax] = (b - r)[gmax] / delta[gmax] + 2.0
    hue[bmax] = (r - g)[bmax] / delta[bmax] + 4.0
    sat = np.where(mx > 1e-9, delta / np.maximum(mx, 1e-9), 0.0)
    return hue * 60.0, sat, mx


def hsv_to_rgb(hue, sat, val):
    c = val * sat
    hp = (hue % 360.0) / 60.0
    x = c * (1.0 - np.abs(hp % 2.0 - 1.0))
    zeros = np.zeros_like(c)
    sector = np.floor(hp).astype(int) % 6
    table = [(c, x, zeros), (x, c, zeros), (zeros, c, x), (zeros, x, c), (x, zeros, c), (c, zeros, x)]
    out = np.zeros(hue.shape + (3,))
    for i, (rr, gg, bb) in enumerate(table):
        sel = sector == i
        out[sel] = np.stack([rr[sel], gg[sel], bb[sel]], axis=-1)
    return out + (val - c)[..., None]


def build_monster(tint: dict, source: Path = MC_LIVERY) -> Image.Image:
    """Re-tint the green family of the livery (or of its emission map, which carries the glowing keylines)."""
    rgb = np.asarray(Image.open(source).convert("RGB"), dtype=np.float64) / 255.0
    hue, sat, val = rgb_to_hsv(rgb)
    # Green body family (body gradient, neon keylines, "08" numerals); soft edges keep anti-aliasing.
    in_hue = smoothstep(70.0, 95.0, hue) * (1.0 - smoothstep(165.0, 185.0, hue))
    mask = in_hue * smoothstep(0.25, 0.40, sat)
    shifted = hsv_to_rgb(np.full_like(hue, tint["hue"]) + (hue - 140.0) * 0.5,
                         np.clip(sat * tint["saturation"], 0.0, 1.0), np.clip(val * tint["value"], 0.0, 1.0))
    out = mix(rgb, shifted, mask)
    return Image.fromarray(np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def encode(image: Image.Image, suffix: str) -> bytes:
    buffer = io.BytesIO()
    if suffix == ".jpg":
        image.save(buffer, "JPEG", quality=90, subsampling=0, optimize=True)
    else:
        image.save(buffer, "PNG", optimize=True)
    return buffer.getvalue()


def outputs() -> dict[str, bytes]:
    # shared/ holds unchanged CC0 maps from ambientCG (see shared/LICENSES.txt); this tool does not write them.
    files: dict[str, bytes] = {}
    for skin, design in CANOPY_DESIGNS.items():
        files[f"hx-700/{skin}_canopy.png"] = encode(build_canopy(design), ".png")
        files[f"hx-700/{skin}_boom.png"] = encode(build_boom(BOOM_PALETTES[skin]), ".png")
    for skin, tint in MONSTER_TINTS.items():
        files[f"monster-car-2/{skin}_livery.jpg"] = encode(build_monster(tint), ".jpg")
        glow = dict(tint, value=1.0)  # the emission map is already at full value; only its hue moves
        files[f"monster-car-2/{skin}_emission.png"] = encode(build_monster(glow, MC_EMISSION), ".png")
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail when a committed output differs")
    parser.add_argument("--only", default="", help="build only outputs whose path contains this text")
    args = parser.parse_args()
    built = {k: v for k, v in outputs().items() if args.only in k} if args.only else outputs()
    stale = []
    for relative, data in built.items():
        target = OUT / relative
        if args.check:
            if not target.exists() or target.read_bytes() != data:
                stale.append(relative)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        print(f"{relative}  {len(data) / 1024:.0f} KiB  sha256 {hashlib.sha256(data).hexdigest()[:16]}")
    if stale:
        print("stale outputs:", ", ".join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
