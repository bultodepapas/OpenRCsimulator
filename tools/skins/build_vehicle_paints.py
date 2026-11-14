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


# ---------------------------------------------------------------------------------------------
# Sebart Avanti S jet: "Verde Neón Carbono". Designed in the jet's scene space (glTF: +X right wing, +Y up,
# -Z nose) and baked through each paint material's own UV atlas, so stripes run on across control surfaces.
# ---------------------------------------------------------------------------------------------
JET_GLB = APP / "assets/aircraft/avanti-s-a200/avanti_s.glb"
CARBON_TWILL = APP / "assets/vehicle-paints/shared/carbon_twill_albedo.jpg"
NEON = hex_rgb("#4cf02a")
NEON_DEEP = hex_rgb("#1e9e2a")
JET_WHITE = hex_rgb("#f2f5f7")
INK = hex_rgb("#0d0f12")
# Atlas sizes (width, height) of the stock paint textures. The stock wing doors reuse the wing image with UVs that
# overlap the wing's leading edge, so the skin gives them their own texture.
JET_ATLASES = {
    "wing": (("paint_wing",), (2048, 2048)),
    "doors": (("paint_doors_ala",), (2048, 2048)),
    "fuselage": (("paint_fuselage",), (2048, 4096)),  # double the stock atlas: crisp stencils and lettering
    "stab": (("paint_stab",), (2048, 2048)),
    "fin": (("paint_fin",), (2048, 1024)),
}


def _node_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = np.eye(4)
    t[:3, 3] = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    r = np.eye(4)
    r[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                 [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                 [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    s = np.diag(list(node.get("scale", [1.0, 1.0, 1.0])) + [1.0])
    return t @ r @ s


def scene_primitives(path: Path, materials):
    """Yield (material, scene positions, scene normals, uv, triangles) with every node transform applied."""
    doc, accessor = read_glb(path)
    names = [m["name"] for m in doc["materials"]]
    wanted = set(materials)
    found = []

    def walk(index: int, parent: np.ndarray) -> None:
        node = doc["nodes"][index]
        world = parent @ _node_matrix(node)
        if "mesh" in node:
            normal_matrix = np.linalg.inv(world[:3, :3]).T
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                name = names[prim["material"]]
                attrs = prim["attributes"]
                if name not in wanted or "TEXCOORD_0" not in attrs:  # untextured parts cannot carry a bake
                    continue
                pos = accessor(attrs["POSITION"]).astype(np.float64)
                nrm = accessor(attrs["NORMAL"]).astype(np.float64)
                pos = pos @ world[:3, :3].T + world[:3, 3]
                nrm = nrm @ normal_matrix.T
                nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
                found.append((name, pos, nrm, accessor(attrs["TEXCOORD_0"]).astype(np.float64),
                              accessor(prim["indices"]).reshape(-1, 3)))
        for child in node.get("children", []):
            walk(child, world)

    for root_index in doc["scenes"][doc.get("scene", 0)]["nodes"]:
        walk(root_index, np.eye(4))
    return found


def bake_scene(path: Path, materials, size, symmetric: bool = False, skin_axis: int = -1):
    """UV-space rasterisation of several materials sharing one atlas: scene position, normal, material id.
    `symmetric` folds the scene about the X = 0 plane first: left and right parts that share mirrored UVs (the
    jet's wings and stabiliser) then accumulate the same |x| instead of averaging to the centre line.
    `skin_axis`: where the stock UVs let a skin face share texels with hidden edge or cove faces (the wing's flap
    coves), the face with the largest |normal[axis]| owns the texel, so the visible skin decides the colour."""
    width, height = size
    pos_map = np.zeros((height, width, 3))
    nrm_map = np.zeros((height, width, 3))
    mat_map = np.full((height, width), -1, dtype=np.int32)
    weight = np.zeros((height, width))
    best = np.full((height, width), -1.0)
    for name, pos, nrm, uv, tris in scene_primitives(path, materials):
        mat_id = list(materials).index(name)
        if symmetric and pos[:, 0].mean() < 0.0:
            mirror = np.array([-1.0, 1.0, 1.0])
            pos = pos * mirror
            nrm = nrm * mirror
        px = uv * np.array([width, height])
        for tri in tris:
            # The paint textures repeat: UVs outside [0, 1] (the jet's wing spans ~2.5 tiles) wrap like the GPU's
            # sampler does. Shift each triangle into the base tile and wrap the texel indices.
            p = px[tri] - np.floor(uv[tri].mean(0)) * np.array([width, height])
            x0, y0 = np.floor(p.min(0)).astype(int)
            x1, y1 = np.ceil(p.max(0)).astype(int)
            if x1 - x0 > width or y1 - y0 > height:
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
            yi = np.floor(ys[inside]).astype(int) % height
            xi = np.floor(xs[inside]).astype(int) % width
            if skin_axis >= 0:
                # Winner takes all: the face that best faces the skin direction owns the texel (no blending).
                importance = abs(float(nrm[tri, skin_axis].mean()))
                wins = importance > best[yi, xi]
                if not wins.any():
                    continue
                yi, xi, ws = yi[wins], xi[wins], ws[wins]
                best[yi, xi] = importance
                pos_map[yi, xi] = ws @ pos[tri]
                nrm_map[yi, xi] = ws @ nrm[tri]
                weight[yi, xi] = 1.0
            else:
                np.add.at(pos_map, (yi, xi), ws @ pos[tri])
                np.add.at(nrm_map, (yi, xi), ws @ nrm[tri])
                np.add.at(weight, (yi, xi), 1.0)
            mat_map[yi, xi] = mat_id
    covered = weight > 0
    pos_map[covered] /= weight[covered][:, None]
    norms = np.linalg.norm(nrm_map, axis=2, keepdims=True)
    nrm_map = np.where(norms > 1e-9, nrm_map / np.maximum(norms, 1e-9), 0.0)
    return pos_map, nrm_map, mat_map, covered


def chord_table(path: Path, materials, span_axis: int, bins: int, lo: float, hi: float):
    """Leading and trailing edge (min/max z) per span bin, over every part of a lifting surface."""
    le = np.full(bins, np.inf)
    te = np.full(bins, -np.inf)
    for _name, pos, _nrm, _uv, _tris in scene_primitives(path, materials):
        k = np.clip(((pos[:, span_axis] - lo) / (hi - lo) * bins).astype(int), 0, bins - 1)
        np.minimum.at(le, k, pos[:, 2])
        np.maximum.at(te, k, pos[:, 2])
    # Fill empty bins from their neighbours so the fraction stays defined everywhere, then smooth: sparse meshes
    # leave single bins without their true edge vertex, which would otherwise stripe the design.
    good = np.isfinite(le)
    idx = np.arange(bins)
    le = np.interp(idx, idx[good], le[good])
    te = np.interp(idx, idx[good], te[good])
    pad = 2
    le_padded = np.pad(le, pad, mode="edge")
    te_padded = np.pad(te, pad, mode="edge")
    windows = np.lib.stride_tricks.sliding_window_view
    le = windows(le_padded, 2 * pad + 1).min(axis=1)
    te = windows(te_padded, 2 * pad + 1).max(axis=1)
    kernel = np.ones(3) / 3.0
    le = np.convolve(np.pad(le, 1, mode="edge"), kernel, mode="valid")
    te = np.convolve(np.pad(te, 1, mode="edge"), kernel, mode="valid")
    return le, te


def chord_fraction(pos, span_axis: int, table, lo: float, hi: float):
    """Chord position 0 (leading edge) .. 1 (trailing edge), interpolated linearly between span bins."""
    le, te = table
    centres = lo + (np.arange(len(le)) + 0.5) * (hi - lo) / len(le)
    s = pos[..., span_axis]
    le_s = np.interp(s, centres, le)
    te_s = np.interp(s, centres, te)
    return np.clip((pos[..., 2] - le_s) / np.maximum(te_s - le_s, 1e-6), 0.0, 1.0)


_TWILL = None
_TWILL_MEAN = None


def carbon(pos, nrm, tile: float = 0.025):
    """Clear-coated 2x2 twill sampled triplanar in scene space (the CC0 ambientCG weave in shared/)."""
    global _TWILL
    if _TWILL is None:
        _TWILL = np.asarray(Image.open(CARBON_TWILL).convert("RGB"), dtype=np.float64) / 255.0
        globals()["_TWILL_MEAN"] = _TWILL.reshape(-1, 3).mean(axis=0)
    size = _TWILL.shape[0]
    axis = np.argmax(np.abs(nrm), axis=-1)
    a = np.where(axis == 0, pos[..., 1], pos[..., 0])
    b = np.where(axis == 2, pos[..., 1], pos[..., 2])
    u = ((a / tile) % 1.0 * size).astype(int) % size
    v = ((b / tile) % 1.0 * size).astype(int) % size
    weave = _TWILL[v, u]
    return (_TWILL_MEAN + (weave - _TWILL_MEAN) * 0.7) * 1.05


def _bilinear(art, u, v):
    """Sample a 2-D (or 2-D x channels) array at normalised u, v with bilinear filtering; edges clamp."""
    rows, cols = art.shape[:2]
    fx = np.clip(u * cols - 0.5, 0.0, cols - 1.0)
    fy = np.clip(v * rows - 0.5, 0.0, rows - 1.0)
    x0 = np.floor(fx).astype(int)
    y0 = np.floor(fy).astype(int)
    x1 = np.minimum(x0 + 1, cols - 1)
    y1 = np.minimum(y0 + 1, rows - 1)
    tx = fx - x0
    ty = fy - y0
    if art.ndim == 3:
        tx = tx[..., None]
        ty = ty[..., None]
    top = art[y0, x0] * (1 - tx) + art[y0, x1] * tx
    bottom = art[y1, x0] * (1 - tx) + art[y1, x1] * tx
    return top * (1 - ty) + bottom * ty


def side_text(pos, nrm, text, z0, z1, y0, y1):
    """Lettering on a side surface that reads left-to-right from both sides (+X sees the nose to its right)."""
    aspect = (z1 - z0) / (y1 - y0)
    mask = _lettering_image(text, aspect)
    rows, cols = mask.shape
    z, y = pos[..., 2], pos[..., 1]
    # The facing side comes from the normal: thin parts (the fin) sit within millimetres of X = 0.
    u = np.where(nrm[..., 0] >= 0.0, (z1 - z) / (z1 - z0), (z - z0) / (z1 - z0))
    v = (y1 - y) / (y1 - y0)
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    return np.where(inside, _bilinear(mask, u, v), 0.0) * smoothstep(0.35, 0.6, np.abs(nrm[..., 0]))


def _piecewise(x, xs, ys):
    return np.interp(x, xs, ys)


def jet_fuselage(pos, nrm):
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    zn = (z + 0.938) / 2.221  # 0 = nose, 1 = tail
    ny = nrm[..., 1]
    split = _piecewise(zn, [0.0, 0.10, 0.34, 0.62, 1.0], [0.0, 0.045, 0.150, 0.150, 0.105])
    above = smoothstep(-0.002, 0.002, y - split)
    colour = mix(np.broadcast_to(NEON, pos.shape).copy(), carbon(pos, nrm), above)
    # Carbon radome with a thin white ring.
    colour = mix(colour, carbon(pos, nrm), 1.0 - smoothstep(0.055, 0.06, zn))
    colour = mix(colour, JET_WHITE, band(zn, np.zeros_like(zn), 0.068, 0.0, 0.0035, soft=0.0012))
    # White double pinstripe under the split line.
    d = split - y
    pin = (1.0 - smoothstep(0.0042, 0.0056, np.abs(d - 0.009))) + (1.0 - smoothstep(0.0010, 0.0020, np.abs(d - 0.0195)))
    colour = mix(colour, JET_WHITE, np.clip(pin, 0, 1) * (zn > 0.07))
    # Speed slashes on the flanks behind the intakes.
    side = smoothstep(0.45, 0.7, np.abs(nrm[..., 0]))
    diag = zn * 3.4 + y * 7.0
    slash = (1.0 - smoothstep(0.08, 0.1, (diag % 1.0))) * smoothstep(0.38, 0.40, zn) * (1.0 - smoothstep(0.58, 0.60, zn))
    colour = mix(colour, JET_WHITE, slash * side * (y < split - 0.03))
    # White belly with forward-pointing green chevrons.
    belly = smoothstep(-0.45, -0.65, ny)
    chevron = (1.0 - smoothstep(0.28, 0.31, ((zn * 7.0 + np.abs(x) * 9.0) % 1.0))) * (zn > 0.12) * (zn < 0.92)
    belly_colour = mix(np.broadcast_to(JET_WHITE, pos.shape).copy(), NEON, chevron)
    colour = mix(colour, belly_colour, belly)
    # Lettering: "NEO" on the rear flanks, "07" behind the radome.
    colour = mix(colour, JET_WHITE, side_text(pos, nrm, "NEO", 0.52, 0.86, 0.005, 0.085) * (1.0 - belly))
    nose_number = side_text(pos, nrm, "07", -0.72, -0.56, -0.02, 0.045) * (1.0 - belly) * (1.0 - above)
    colour = mix(colour, JET_WHITE, nose_number)
    # Twin white pinstripes along the spine: orientation from above.
    spine = (nrm[..., 1] > 0.7) & (zn > 0.60) & (zn < 0.97)
    spine_lines = (1.0 - smoothstep(0.0009, 0.0016, np.abs(np.abs(x) - 0.012))) * spine
    colour = mix(colour, JET_WHITE, spine_lines)
    glow = np.clip((1.0 - above) * (1.0 - belly) * (1.0 - np.clip(pin, 0, 1)) * (1.0 - nose_number) * (zn > 0.06)
                   + belly * chevron, 0, 1)
    carbon_weight = np.maximum(above, 1.0 - smoothstep(0.055, 0.06, zn)) * (1.0 - belly)
    return colour, glow, carbon_weight


def jet_lifting(pos, nrm, frac, span_norm, tip_from: float):
    """Wings and stabiliser: carbon top with a neon leading-edge blade, white underside with a green chevron."""
    top = nrm[..., 1] >= 0.0
    blade_edge = 0.36 - 0.12 * span_norm
    blade = 1.0 - smoothstep(blade_edge - 0.004, blade_edge + 0.004, frac)
    rim = (1.0 - smoothstep(0.010, 0.016, np.abs(frac - blade_edge - 0.022)))
    tip = smoothstep(tip_from - 0.005, tip_from + 0.005, span_norm)
    tip_stripe = 1.0 - smoothstep(0.010, 0.016, np.abs(span_norm - tip_from + 0.035))
    skin = smoothstep(0.3, 0.6, np.abs(nrm[..., 1]))
    rim = rim * skin
    tip_stripe = tip_stripe * skin
    upper = mix(carbon(pos, nrm), NEON, np.maximum(blade, tip))
    upper = mix(upper, JET_WHITE, np.clip(rim + tip_stripe, 0, 1) * (1.0 - tip * (1.0 - tip_stripe)))
    chevron = np.abs(frac - (0.18 + 0.75 * span_norm)) < 0.13
    lower = mix(np.broadcast_to(JET_WHITE, pos.shape).copy(), NEON, chevron.astype(float))
    lower = mix(lower, carbon(pos, nrm), tip)
    colour = np.where(top[..., None], upper, lower)
    colour = mix(carbon(pos, nrm), colour, skin)  # gap and edge faces read as dark carbon
    glow = np.where(top, np.maximum(blade, tip) * (1.0 - np.clip(rim, 0, 1)), chevron.astype(float) * (1.0 - tip))
    carbon_weight = np.where(top, 1.0 - np.maximum(np.maximum(blade, tip), np.clip(rim, 0, 1)), tip)
    return colour, glow, carbon_weight


def jet_fin(pos, nrm, frac, height_norm):
    blade_edge = 0.40
    blade = 1.0 - smoothstep(blade_edge - 0.005, blade_edge + 0.005, frac)
    rim = 1.0 - smoothstep(0.010, 0.016, np.abs(frac - blade_edge - 0.025))
    tip = smoothstep(0.86, 0.87, height_norm)
    colour = mix(carbon(pos, nrm), NEON, np.maximum(blade, tip))
    colour = mix(colour, JET_WHITE, np.clip(rim, 0, 1) * (1.0 - tip))
    colour = mix(colour, JET_WHITE, side_text(pos, nrm, "07", 0.895, 1.04, 0.298, 0.356))
    glow = np.maximum(blade, tip) * (1.0 - np.clip(rim, 0, 1))
    return colour, glow, 1.0 - np.maximum(np.maximum(blade, tip), np.clip(rim, 0, 1))


# --- Detail pass: engraved panel lines, hatches, stencils and decals, vinyl edges, soot, gloss map ---------------
DECAL_RED = (214, 32, 38, 255)
SPONSORS = APP / "assets/vehicle-paints/avanti-s-a200/sponsors"  # trademarks used with sponsor support (SOURCE.txt)
DECAL_YELLOW = (255, 200, 30, 255)
_DECALS: dict = {}


def _decal(kind: str) -> np.ndarray:
    """RGBA (0..1) artwork for a stencil or warning decal, drawn once with PIL."""
    if kind in _DECALS:
        return _DECALS[kind]
    from PIL import ImageDraw, ImageFont
    font_path = str(FONT)
    if kind in ("eject", "hot"):
        size = 256
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.polygon([(size * 0.5, size * 0.06), (size * 0.95, size * 0.9), (size * 0.05, size * 0.9)], fill=(255, 255, 255, 255))
        d.polygon([(size * 0.5, size * 0.2), (size * 0.83, size * 0.83), (size * 0.17, size * 0.83)],
                  fill=DECAL_RED if kind == "eject" else DECAL_YELLOW)
        ink = (255, 255, 255, 255) if kind == "eject" else (20, 20, 20, 255)
        font = ImageFont.truetype(font_path, int(size * 0.42))
        d.text((size * 0.5, size * 0.62), "!", fill=ink, font=font, anchor="mm", stroke_width=4, stroke_fill=ink)
    elif kind == "danger":
        img = Image.new("RGBA", (640, 128), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rectangle((0, 0, 639, 127), fill=DECAL_RED)
        d.rectangle((6, 6, 633, 121), outline=(255, 255, 255, 255), width=5)
        font = ImageFont.truetype(font_path, 74)
        d.text((320, 64), "DANGER  INTAKE", fill=(255, 255, 255, 255), font=font, anchor="mm",
               stroke_width=2, stroke_fill=(255, 255, 255, 255))
    elif kind == "serial":
        img = Image.new("RGBA", (720, 112), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        font = ImageFont.truetype(font_path, 84)
        d.text((360, 56), "SPORT JET", fill=(242, 245, 247, 255), font=font, anchor="mm",
               stroke_width=1, stroke_fill=(242, 245, 247, 255))
    elif kind == "pilot":
        img = Image.new("RGBA", (640, 112), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        font = ImageFont.truetype(font_path, 80)
        d.text((320, 56), "CAPT. NEO", fill=(242, 245, 247, 255), font=font, anchor="mm",
               stroke_width=1, stroke_fill=(242, 245, 247, 255))
    elif kind == "blast":
        img = Image.new("RGBA", (560, 112), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rectangle((0, 0, 559, 111), fill=DECAL_RED)
        font = ImageFont.truetype(font_path, 70)
        d.text((280, 56), "JET BLAST", fill=(255, 255, 255, 255), font=font, anchor="mm",
               stroke_width=2, stroke_fill=(255, 255, 255, 255))
    elif kind == "jumper":
        # Sponsor sticker: the official red Jumper logo on a white die-cut sticker with a thin black edge,
        # matching the JETI model badge style.
        logo = Image.open(SPONSORS / "jumper_rc_logo.png").convert("RGBA")
        logo = logo.crop(logo.getbbox())
        width, height = 900, 330
        img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((2, 2, width - 3, height - 3), radius=42, fill=(20, 20, 22, 255))
        d.rounded_rectangle((12, 12, width - 13, height - 13), radius=34, fill=(250, 250, 250, 255))
        scale = min((width - 110) / logo.width, (height - 90) / logo.height)
        logo = logo.resize((int(logo.width * scale), int(logo.height * scale)), Image.LANCZOS)
        img.alpha_composite(logo, ((width - logo.width) // 2, (height - logo.height) // 2))
    elif kind == "jeti":
        # The official JETI model badge is already a white sticker with a black rounded edge.
        img = Image.open(SPONSORS / "jeti_model_logo.png").convert("RGBA")
        img = img.resize((img.width * 2, img.height * 2), Image.LANCZOS)
    else:
        raise ValueError(kind)
    _DECALS[kind] = np.asarray(img, dtype=np.float64) / 255.0
    return _DECALS[kind]


def side_decal(pos, nrm, kind, z0, z1, y0, y1):
    """Sample a decal on a side surface; it reads left-to-right from both sides like side_text."""
    art = _decal(kind)
    rows, cols = art.shape[:2]
    z, y = pos[..., 2], pos[..., 1]
    u = np.where(nrm[..., 0] >= 0.0, (z1 - z) / (z1 - z0), (z - z0) / (z1 - z0))
    v = (y1 - y) / (y1 - y0)
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    sample = _bilinear(art, u, v)
    alpha = np.where(inside, sample[..., 3], 0.0) * smoothstep(0.35, 0.6, np.abs(nrm[..., 0]))
    return sample[..., :3], alpha


def _line(distance, width):
    return 1.0 - smoothstep(width * 0.5, width, np.abs(distance))


def engrave(colour, rough, distance, width=0.0011):
    """A panel line: a dark groove with a faint lit lip beside it, rougher so it breaks the clear-coat reflection."""
    groove = _line(distance, width)
    lip = _line(distance - width * 1.5, width * 0.6) * (1.0 - groove)
    colour = colour * (1.0 - 0.5 * groove)[..., None]
    colour = np.clip(colour * (1.0 + 0.12 * lip)[..., None], 0.0, 1.0)
    return colour, np.maximum(rough, 0.48 * groove), groove


def _box_distance(a, b, a0, a1, b0, b1):
    """Distance to a rectangle's outline in two surface coordinates (metres): 0 on the outline."""
    return np.maximum(np.maximum(a0 - a, a - a1), np.maximum(b0 - b, b - b1))


def vinyl_edges(colour, covered, rough):
    """Thin dark edge around white vinyl where it meets neon paint, as cut decals look on a gloss finish."""
    white = (colour.min(-1) > 0.85) & covered
    grown = white.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)):
        grown |= np.roll(np.roll(white, dy, 0), dx, 1)
    neon = (colour[..., 1] > 0.75) & (colour[..., 0] < 0.5)
    edge = grown & ~white & neon
    colour = colour.copy()
    colour[edge] *= 0.62
    return colour, np.where(edge, np.maximum(rough, 0.3), rough)


def jet_details(atlas, pos, nrm, colour, glow, carbon_weight, frac=None, span_norm=None, height_norm=None):
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    # Gloss map: clear-coated carbon is the glossiest; neon and white paint are satin-gloss.
    rough = 0.21 + (0.11 - 0.21) * carbon_weight
    glow = glow.copy()
    if atlas == "fuselage":
        zn = (z + 0.938) / 2.221
        for joint in (0.30, 0.47, 0.70, 0.83):  # the 0.83 joint stays ahead of the access hatch
            colour, rough, g = engrave(colour, rough, (zn - joint) * 2.221)
            glow *= 1.0 - g
        side = (np.abs(nrm[..., 0]) > 0.5).astype(float)
        hatch = _box_distance(zn * 2.221, y, 0.845 * 2.221, 0.895 * 2.221, 0.030, 0.064)
        colour, rough, g = engrave(colour, rough, np.where(side > 0, hatch, 1.0))
        glow *= 1.0 - g
        for cz in (0.849, 0.891):
            for cy in (0.034, 0.060):
                screw = np.hypot((zn - cz) * 2.221, y - cy)
                colour = mix(colour, hex_rgb("#8c9299"), (1.0 - smoothstep(0.0012, 0.0018, screw)) * side)
        # Flush fuel cap on the spine with a blue centre.
        top = (nrm[..., 1] > 0.6).astype(float)
        cap = np.hypot(x, (zn - 0.53) * 2.221)
        colour = mix(colour, hex_rgb("#9aa0a6"), (1.0 - smoothstep(0.011, 0.0118, cap)) * top)
        colour, rough, g = engrave(colour, rough, np.where(top > 0, cap - 0.0122, 1.0))
        colour = mix(colour, hex_rgb("#2c66d8"), (1.0 - smoothstep(0.0035, 0.0042, cap)) * top)
        # Stencils and warning decals (fuselage sides have their own UVs, so text reads on both sides).
        decals = [("eject", 0.200, 0.232, 0.094, 0.124), ("danger", 0.300, 0.372, 0.014, 0.034),
                  ("serial", 0.760, 0.895, 0.087, 0.108),
                  ("pilot", 0.245, 0.335, 0.097, 0.113), ("blast", 0.905, 0.975, 0.083, 0.101),
                  ("jumper", 0.192, 0.242, 0.003, 0.041)]
        for kind, a0, a1, b0, b1 in decals:
            art, alpha = side_decal(pos, nrm, kind, -0.938 + a0 * 2.221, -0.938 + a1 * 2.221, b0, b1)
            colour = mix(colour, art, alpha)
            rough = rough + (0.32 - rough) * alpha
            glow *= 1.0 - alpha
        # Exhaust soot: a faint grey film on the tail cone.
        soot = smoothstep(0.86, 1.0, zn) * (1.0 - smoothstep(0.06, 0.18, y))
        colour = colour * (1.0 - 0.45 * soot)[..., None]
        rough = np.maximum(rough, 0.42 * soot)
        heat = smoothstep(0.978, 0.986, zn)
        heat_tint = mix(np.broadcast_to(hex_rgb("#c9a35a"), pos.shape), hex_rgb("#4b5c9e"), smoothstep(0.986, 0.998, zn))
        colour = mix(colour, heat_tint, heat * 0.65)
        glow *= 1.0 - heat
    elif atlas in ("wing", "stab", "doors"):
        # Wings and stabiliser share mirrored UVs: only symmetric details (no lettering).
        chord_m = 0.25 if atlas == "stab" else 0.45
        spars = (0.6,) if atlas == "stab" else (0.12, 0.62)
        inner = (span_norm > 0.18) & (span_norm < 0.86)
        for spar in spars:
            colour, rough, g = engrave(colour, rough, np.where(inner, (frac - spar) * chord_m, 1.0))
            glow *= 1.0 - g
        if atlas == "wing":
            between = (frac > 0.12) & (frac < 0.62)
            for rib in (0.40, 0.58, 0.76):
                colour, rough, g = engrave(colour, rough, np.where(between, (span_norm - rib) * 0.998, 1.0))
                glow *= 1.0 - g
            # Walkway outline at the root, dashed white on the carbon.
            top = (nrm[..., 1] > 0.3).astype(float)
            walk = _box_distance(span_norm * 0.998, frac * chord_m, 0.27, 0.40, 0.45 * chord_m, 0.62 * chord_m)
            dash = ((((span_norm * 0.998 + frac * chord_m) / 0.012) % 1.0) < 0.6).astype(float)
            colour = mix(colour, JET_WHITE, _line(walk, 0.0016) * top * dash)
    elif atlas == "fin":
        colour, rough, g = engrave(colour, rough, (frac - 0.62) * 0.4)
        glow *= 1.0 - g
        # JETI model sponsor badge under the fin number, on the carbon of the fixed fin (ahead of the rudder line).
        art, alpha = side_decal(pos, nrm, "jeti", 0.82, 0.955, 0.245, 0.283)
        colour = mix(colour, art, alpha)
        rough = rough + (0.3 - rough) * alpha
        glow *= 1.0 - alpha
        # Chequered racing band under the neon tip.
        band_mask = (height_norm > 0.79) & (height_norm < 0.85)
        checks = ((np.floor(z / 0.011) + np.floor(y / 0.011)) % 2.0) < 1.0
        colour = np.where((band_mask & checks)[..., None], INK, np.where(band_mask[..., None], JET_WHITE, colour))
        glow = np.where(band_mask, 0.0, glow)
        rough = np.where(band_mask, 0.2, rough)
    return colour, glow, rough


def build_jet(atlas: str):
    materials, size = JET_ATLASES[atlas]
    skin_axis = {"wing": 1, "stab": 1, "doors": 1, "fin": 0}.get(atlas, -1)
    pos, nrm, mat_map, covered = bake_scene(JET_GLB, materials, size, symmetric=atlas in ("wing", "stab", "doors"),
                                            skin_axis=skin_axis)
    extra = {}
    if atlas == "fuselage":
        colour, glow, carb = jet_fuselage(pos, nrm)
    elif atlas in ("wing", "stab", "doors"):
        span_hi = 0.443 if atlas == "stab" else 0.998
        lifting = ("paint_stab",) if atlas == "stab" else ("paint_wing",)
        table = chord_table(JET_GLB, lifting, 0, 28 if atlas == "stab" else 48, -span_hi, span_hi)
        frac = chord_fraction(pos, 0, table, -span_hi, span_hi)
        span_norm = np.abs(pos[..., 0]) / span_hi
        if atlas == "doors":
            nrm = nrm.copy()
            nrm[..., 1] = -np.maximum(np.abs(nrm[..., 1]), 0.7)
        colour, glow, carb = jet_lifting(pos, nrm, frac, span_norm, 0.86 if atlas == "stab" else 0.88)
        extra = {"frac": frac, "span_norm": span_norm}
    else:
        table = chord_table(JET_GLB, ("paint_fin",), 1, 20, 0.212, 0.577)
        frac = chord_fraction(pos, 1, table, 0.212, 0.577)
        height_norm = (pos[..., 1] - 0.212) / (0.577 - 0.212)
        colour, glow, carb = jet_fin(pos, nrm, frac, height_norm)
        extra = {"frac": frac, "height_norm": height_norm}
    colour, glow, rough = jet_details(atlas, pos, nrm, colour, glow, carb, **extra)
    colour, rough = vinyl_edges(colour, covered, rough)
    colour[~covered] = 0.0
    glow = np.where(covered, glow, 0.0)
    colour = dilate(colour, covered)
    glow_rgb = dilate(glow[..., None] * NEON, covered)
    rough_rgb = dilate(np.repeat(rough[..., None], 3, axis=-1), covered)
    to_image = lambda a: Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    return to_image(colour), to_image(glow_rgb), to_image(rough_rgb).convert("L")


# ---------------------------------------------------------------------------------------------
# Sebart Avanti S jet: "Sabre Plata". A natural-metal tribute to early-1950s USAF day fighters with fictional
# FU-861 / 20861 markings: aluminium panels of varying temper and polish, flush-rivet rows, screwed hatches, a
# gun-blast panel, a heat-stained tail, Korea-style yellow ID bands and a chequered nose ring. Four maps per atlas:
# albedo, roughness, metallic (bare metal vs paint) and a tangent-space normal map baked from a height field
# (panel grooves, rivet dimples, oil-canned skins). Same scene-space bake as Verde Neón Carbono above.
# ---------------------------------------------------------------------------------------------
SABRE_ATLASES = {
    "wing": (("paint_wing",), (2048, 2048)),
    "doors": (("paint_doors_ala",), (1024, 1024)),
    "fuselage": (("paint_fuselage",), (2048, 4096)),
    "stab": (("paint_stab",), (1024, 1024)),
    "fin": (("paint_fin",), (2048, 1024)),
}
SILVER_ACE_SOURCES = ROOT / "tools/skins/sources/silver-ace"  # public-domain USAF insignia (see its README.md)
# Art-directed aluminium reflectance (sRGB) and roughness per panel: temper, polish and age differ panel to panel.
ALU_TONES = np.array([(214, 218, 222), (199, 206, 213), (226, 226, 221), (189, 196, 204),
                      (207, 209, 205), (220, 223, 228), (182, 188, 194), (232, 233, 233)], dtype=np.float64) / 255.0
ALU_ROUGH = np.array([0.26, 0.34, 0.22, 0.42, 0.31, 0.27, 0.47, 0.19])
# Metallic share per panel. Compatibility flight and Home scenes disable sky reflections (atmosphere.gd), where a
# fully metallic skin keeps only sun highlights and reads near-black; a partial share keeps a diffuse silver body
# under ambient light and still reflects where the High profile enables sky reflections.
ALU_METAL = np.array([0.60, 0.52, 0.66, 0.46, 0.56, 0.60, 0.44, 0.70])
SABRE_INK = hex_rgb("#1d1f22")
SABRE_WHITE = hex_rgb("#ebe9e2")
SABRE_YELLOW = hex_rgb("#e3b21f")
SABRE_OLIVE = hex_rgb("#2f3229")
SABRE_RED = hex_rgb("#b3262a")
FUS_NOSE, FUS_LEN = -0.938, 2.221
_SABRE_ART: dict = {}


def _hash(*ints, seed: int = 0) -> np.ndarray:
    """Deterministic 0..1 hash of integer arrays (panel, rivet and noise lattice ids)."""
    with np.errstate(over="ignore"):
        v = np.full(np.shape(ints[0]), np.uint64(seed) * np.uint64(0x9E3779B97F4A7C15) + np.uint64(0x632BE5AB),
                    dtype=np.uint64)
        for value in ints:
            v = (v ^ np.asarray(value).astype(np.int64).astype(np.uint64)) * np.uint64(0x100000001B3)
            v ^= v >> np.uint64(29)
            v *= np.uint64(0xBF58476D1CE4E5B9)
            v ^= v >> np.uint64(32)
    return (v >> np.uint64(40)).astype(np.float64) / float(1 << 24)


def noise3(p, scale, seed: int):
    """Smooth value noise in scene space (continuous across UV seams); `scale` may be per axis."""
    q = p / np.asarray(scale, dtype=np.float64)
    i = np.floor(q)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    i = i.astype(np.int64)
    out = np.zeros(len(p))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out += w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed=seed)
    return out


def fbm(p, scale, seed: int, octaves: int = 3):
    total, norm, amp = np.zeros(len(p)), 0.0, 1.0
    for octave in range(octaves):
        total += amp * noise3(p, np.asarray(scale, dtype=np.float64) / (2.0 ** octave), seed + octave * 31)
        norm += amp
        amp *= 0.5
    return total / norm


def _nearest(v, lines):
    """Signed distance from v to the nearest line value, the interval index and the fraction across it."""
    lines = np.asarray(lines, dtype=np.float64)
    k = np.searchsorted(lines, v)
    lo = lines[np.clip(k - 1, 0, len(lines) - 1)]
    hi = lines[np.clip(k, 0, len(lines) - 1)]
    d = np.where(np.abs(v - lo) < np.abs(v - hi), v - lo, v - hi)
    frac = np.where(hi > lo, (v - lo) / np.maximum(hi - lo, 1e-9), 0.5)
    return d, k, np.clip(frac, 0.0, 1.0)


def rivets(d, t, offsets, pitch, radius=0.0007):
    """Mask of flush rivets in rows parallel to a seam: d = signed distance from the seam, t = position along it."""
    best = np.full(np.shape(d), np.inf)
    for n, offset in enumerate(offsets):
        phase = (t + n * pitch * 0.5) % pitch - pitch * 0.5  # neighbouring rows stagger
        best = np.minimum(best, np.hypot(d - offset, phase))
    return 1.0 - smoothstep(radius * 0.55, radius, best)


def scratches(a, b, cell, density, seed, width=0.0006):
    """Short random hairline scratches in surface coordinates (metres): one candidate stroke per cell."""
    out = np.zeros(np.shape(a))
    for layer in range(2):
        shift = layer * cell * 0.5
        ia, ib = np.floor((a + shift) / cell), np.floor((b + shift) / cell)
        present = _hash(ia, ib, seed=seed + layer * 7) < density
        angle = _hash(ia, ib, seed=seed + layer * 7 + 1) * np.pi
        strength = _hash(ia, ib, seed=seed + layer * 7 + 2)
        da, db = a + shift - (ia + 0.5) * cell, b + shift - (ib + 0.5) * cell
        along = da * np.cos(angle) + db * np.sin(angle)
        across = -da * np.sin(angle) + db * np.cos(angle)
        dist = np.hypot(across, np.maximum(np.abs(along) - (0.2 + 0.25 * strength) * cell, 0.0))
        out = np.maximum(out, present * (1.0 - smoothstep(width * 0.5, width, dist)) * (0.45 + 0.55 * strength))
    return out


def _sabre_text(text: str, aspect: float, lines: int = 1) -> np.ndarray:
    """Upright block lettering mask (1 = ink), USAF style; several lines for stencil placards."""
    key = ("text", text, round(aspect, 3), lines)
    if key not in _SABRE_ART:
        from PIL import ImageDraw, ImageFont
        height = 128 * lines
        width = int(round(height * aspect))
        canvas = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(canvas)
        rows = text.split("\n")
        font = ImageFont.truetype(str(FONT), int(height / len(rows) * 0.78))
        stroke = 6 if lines == 1 else 2
        widest = max(draw.textbbox((0, 0), row, font=font, stroke_width=stroke)[2] for row in rows)
        if widest > width * 0.97:
            font = ImageFont.truetype(str(FONT), int(height / len(rows) * 0.78 * width * 0.97 / widest))
        for n, row in enumerate(rows):
            draw.text((width * 0.5, height * (n + 0.5) / len(rows)), row, fill=255, font=font, anchor="mm",
                      stroke_width=stroke, stroke_fill=255)
        _SABRE_ART[key] = np.asarray(canvas, dtype=np.float64) / 255.0
    return _SABRE_ART[key]


def _sabre_insignia() -> np.ndarray:
    if "insignia" not in _SABRE_ART:
        art = Image.open(SILVER_ACE_SOURCES / "usaf-roundel.png").convert("RGBA")
        _SABRE_ART["insignia"] = np.asarray(art, dtype=np.float64) / 255.0
    return _SABRE_ART["insignia"]


def _rescue_arrow() -> np.ndarray:
    if "rescue" not in _SABRE_ART:
        from PIL import ImageDraw, ImageFont
        img = Image.new("RGBA", (560, 160), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        red = tuple(int(c * 255) for c in SABRE_RED) + (255,)
        d.polygon([(8, 52), (420, 52), (420, 14), (552, 80), (420, 146), (420, 108), (8, 108)], fill=red)
        font = ImageFont.truetype(str(FONT), 46)
        d.text((214, 80), "RESCUE", fill=(240, 238, 230, 255), font=font, anchor="mm", stroke_width=2,
               stroke_fill=(240, 238, 230, 255))
        _SABRE_ART["rescue"] = np.asarray(img, dtype=np.float64) / 255.0
    return _SABRE_ART["rescue"]


def _side_uv(p, n, z0, z1, y0, y1):
    """Box coordinates on a fuselage or fin side that read left-to-right from both sides, and the side weight."""
    z, y = p[:, 2], p[:, 1]
    u = np.where(n[:, 0] >= 0.0, (z1 - z) / (z1 - z0), (z - z0) / (z1 - z0))
    v = (y1 - y) / (y1 - y0)
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    return u, v, inside * smoothstep(0.35, 0.6, np.abs(n[:, 0]))


class _Skin:
    """Per-texel material channels of a natural-metal skin, built up layer by layer."""

    def __init__(self, count: int):
        self.colour = np.zeros((count, 3))
        self.rough = np.zeros(count)
        self.metal = np.ones(count)
        self.height = np.zeros(count)  # metres, + out of the surface
        self.paint = np.zeros(count)  # coverage by paint or decal (0..1)

    def panels(self, panel_id, grain_a, grain_b, p, seed):
        tone = np.minimum((_hash(panel_id, seed=seed) * len(ALU_TONES)).astype(int), len(ALU_TONES) - 1)
        self.colour = ALU_TONES[tone].copy()
        self.rough = ALU_ROUGH[tone].copy()
        self.metal = ALU_METAL[tone].copy()
        # Directional polishing grain (ambientCG Metal009) along the panel, each panel offset; some turned 90 deg.
        grain = _brushed()
        turned = _hash(panel_id, seed=seed + 5) < 0.3
        ga = np.where(turned, grain_b, grain_a) + _hash(panel_id, seed=seed + 6)
        gb = np.where(turned, grain_a, grain_b) * 4.0 + _hash(panel_id, seed=seed + 7)
        g = _bilinear(grain, (ga / 0.22) % 1.0, (gb / 0.22) % 1.0) - _BRUSHED_MEAN
        self.rough = self.rough + 0.30 * g
        self.colour = self.colour * (1.0 + 0.05 * g)[:, None]
        # Oxidation and handling blotches.
        blotch = fbm(p, 0.09, seed + 11)
        self.colour = self.colour * (0.95 + 0.07 * blotch)[:, None]
        self.rough = self.rough + 0.10 * (fbm(p, 0.05, seed + 13) - 0.5)
        return tone

    def groove(self, distance, width=0.0010, depth=0.00025, wash=0.06):
        line = _line(distance, width)
        near = 1.0 - smoothstep(0.0, 0.004, np.abs(distance))
        self.colour = self.colour * (1.0 - 0.24 * line - wash * near)[:, None]
        self.rough = np.maximum(self.rough, 0.5 * line) + 0.05 * near
        self.height -= depth * line
        return line

    def rivet(self, mask, depth=0.00006):
        self.colour = self.colour * (1.0 - 0.16 * mask)[:, None]
        self.rough = self.rough + 0.16 * mask
        self.height -= depth * mask

    def screw(self, mask):
        self.colour = mix(self.colour, hex_rgb("#8b8e92"), mask)
        self.rough = self.rough + (0.40 - self.rough) * mask
        self.height += 0.00005 * mask

    def paint_over(self, colour, alpha, rough=0.42, chips=None):
        """Lacquer or decal over the metal; `chips` (0..1) wears it back to the bare skin."""
        alpha = np.clip(alpha, 0.0, 1.0)
        if chips is not None:
            alpha = alpha * (1.0 - chips)
        self.colour = mix(self.colour, colour, alpha)
        self.rough = self.rough + (rough - self.rough) * alpha
        self.metal = self.metal * (1.0 - alpha)
        self.paint = np.maximum(self.paint, alpha)

    def grime(self, amount, tint=(0.36, 0.33, 0.29), rough=0.55, metal_loss=0.5):
        amount = np.clip(amount, 0.0, 1.0)
        self.colour = mix(self.colour, self.colour * np.asarray(tint) * 1.6, amount)
        self.rough = self.rough + (rough - self.rough) * amount
        self.metal = self.metal * (1.0 - metal_loss * amount)

    def scratch(self, mask):
        # Bare skin shows through paint; on metal a scratch catches the light as a duller, brighter hairline.
        self.colour = mix(self.colour, np.minimum(self.colour * 1.08 + 0.04, 1.0), mask * (1.0 - self.paint))
        self.colour = mix(self.colour, ALU_TONES[0], mask * self.paint)
        self.metal = np.maximum(self.metal, 0.6 * mask * self.paint)
        self.rough = self.rough + 0.08 * mask


_BRUSHED = None
_BRUSHED_MEAN = 0.0


def _brushed():
    global _BRUSHED, _BRUSHED_MEAN
    if _BRUSHED is None:
        _BRUSHED = np.asarray(Image.open(APP / "assets/vehicle-paints/shared/brushed_metal_roughness.jpg").convert("L"),
                              dtype=np.float64) / 255.0
        _BRUSHED_MEAN = float(_BRUSHED.mean())
    return _BRUSHED


_SECTION = None


def _fuselage_centre(zn):
    """Height of the fuselage cross-section centre along its length (smoothed over the canopy deck step)."""
    global _SECTION
    if _SECTION is None:
        bins = 64
        pts = np.concatenate([prim[1] for prim in scene_primitives(JET_GLB, ("paint_fuselage",))])
        k = np.clip(((pts[:, 2] - FUS_NOSE) / FUS_LEN * bins).astype(int), 0, bins - 1)
        lo, hi = np.full(bins, np.inf), np.full(bins, -np.inf)
        np.minimum.at(lo, k, pts[:, 1])
        np.maximum.at(hi, k, pts[:, 1])
        good = np.isfinite(lo)
        idx = np.arange(bins)
        centre = (np.interp(idx, idx[good], lo[good]) + np.interp(idx, idx[good], hi[good])) * 0.5
        centre = np.convolve(np.pad(centre, 4, mode="edge"), np.ones(9) / 9.0, mode="valid")
        _SECTION = ((idx + 0.5) / bins, centre)
    return np.interp(zn, *_SECTION)


FUS_STATIONS = [0.062, 0.130, 0.200, 0.270, 0.335, 0.400, 0.470, 0.535, 0.600, 0.665, 0.730, 0.790, 0.850,
                0.905, 0.955]
FUS_SEAMS = np.radians([40.0, 84.0, 130.0, 180.0])
FUS_STRINGERS = np.radians([20.0, 62.0, 107.0, 155.0])
FUS_HATCHES = [(0.470, 0.545, 0.175, 0.225), (0.620, 0.680, 0.150, 0.200), (0.860, 0.905, 0.125, 0.165)]
GUN_PANEL = (0.092, 0.178, -0.004, 0.100)
GUN_SLOTS = (0.022, 0.046, 0.070)


def sabre_fuselage(p, n):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    zn = (z - FUS_NOSE) / FUS_LEN
    zm = zn * FUS_LEN
    dy = y - _fuselage_centre(zn)
    r = np.hypot(x, dy)
    phi = np.arctan2(x, dy)  # 0 on top, +-pi under the belly
    a = np.abs(phi)
    arc = r * phi
    side = smoothstep(0.45, 0.65, np.abs(n[:, 0]))
    skin = _Skin(len(p))

    d_station, k_station, f_station = _nearest(zn, FUS_STATIONS)
    d_seam, k_seam, _ = _nearest(a, FUS_SEAMS)
    k_seam = np.where(k_seam == 0, 0, k_seam + 10 * (x < 0))  # the top panel spans the spine
    panel = k_station * 64 + k_seam
    skin.panels(panel, zm, arc, p, seed=101)
    # Oil-canned skins: each panel bows in or out a fraction of a millimetre between frames.
    across = np.where(a < FUS_SEAMS[0], (phi + FUS_SEAMS[0]) / (2 * FUS_SEAMS[0]), _nearest(a, FUS_SEAMS)[2])
    bow = np.sin(np.pi * f_station) * np.sin(np.pi * np.clip(across, 0, 1))
    skin.height += 0.00028 * bow * np.where(_hash(panel, seed=7) < 0.5, -1.0, 1.0)

    # Seams, frame joints and their rivet rows; single rows along the stringers and mid-frames.
    skin.groove(d_station * FUS_LEN)
    skin.groove(d_seam * r)
    major = np.abs(zn - 0.730) * FUS_LEN  # the aft-fuselage break: a heavier joint with a triple rivet row
    skin.groove(major, width=0.0016, depth=0.00035)
    rivet = rivets(d_station * FUS_LEN, arc, (-0.0035, 0.0035), 0.007)
    rivet = np.maximum(rivet, rivets((zn - 0.730) * FUS_LEN, arc, (-0.0065, 0.0065), 0.007))
    rivet = np.maximum(rivet, rivets(d_seam * r, zm, (-0.0035, 0.0035), 0.007))
    rivet = np.maximum(rivet, rivets(_nearest(a, FUS_STRINGERS)[0] * r, zm, (0.0,), 0.009))
    mids = (np.asarray(FUS_STATIONS[:-1]) + np.asarray(FUS_STATIONS[1:])) * 0.5
    rivet = np.maximum(rivet, rivets(_nearest(zn, mids)[0] * FUS_LEN, arc, (0.0,), 0.009))
    skin.rivet(rivet * (zn > 0.062))

    # Screwed access hatches on both sides.
    for z0, z1, y0, y1 in FUS_HATCHES:
        box = _box_distance(zm, y, z0 * FUS_LEN, z1 * FUS_LEN, y0, y1)
        skin.groove(np.where(side > 0.5, box, 1.0), width=0.0013)
        along = np.where(np.minimum(np.abs(y - y0), np.abs(y - y1)) < np.minimum(np.abs(zm - z0 * FUS_LEN),
                                                                                 np.abs(zm - z1 * FUS_LEN)), zm, y)
        phase = (along % 0.011) - 0.0055
        skin.screw((1.0 - smoothstep(0.0007, 0.0011, np.hypot(box + 0.004, phase))) * (box < 0) * side)

    # Gun-blast panel: darker stainless with three ports and their soot.
    gz0, gz1, gy0, gy1 = GUN_PANEL
    gun_box = _box_distance(zm, y, gz0 * FUS_LEN, gz1 * FUS_LEN, gy0, gy1)
    gun = (gun_box < 0) * side
    skin.colour = mix(skin.colour, hex_rgb("#b2ada3") * (0.97 + 0.06 * fbm(p, 0.02, 41))[:, None], gun)
    skin.rough = skin.rough + (0.30 - skin.rough) * gun
    skin.groove(np.where(side > 0.5, gun_box, 1.0), width=0.0013)
    phase = (np.where(np.abs(y - gy0) < 0.004, zm, np.where(np.abs(y - gy1) < 0.004, zm, y)) % 0.010) - 0.005
    skin.screw((1.0 - smoothstep(0.0007, 0.0011, np.hypot(gun_box + 0.0035, phase))) * (gun_box < 0) * side)
    slot_z0, slot_z1 = 0.100 * FUS_LEN, 0.136 * FUS_LEN
    soot = np.zeros(len(p))
    for yc in GUN_SLOTS:
        capsule = np.hypot(np.maximum(np.maximum(slot_z0 - zm, zm - slot_z1), 0.0), y - yc) - 0.0042
        port = (1.0 - smoothstep(-0.0004, 0.0003, capsule)) * side
        rim = _line(capsule - 0.0009, 0.0012) * side
        skin.colour = mix(skin.colour, hex_rgb("#d9dbdc"), rim * 0.6)
        skin.rough = skin.rough + (0.12 - skin.rough) * rim * 0.6
        skin.paint_over(hex_rgb("#131415"), port, rough=0.85)
        skin.height -= 0.0008 * port
        aft = np.maximum(zm - slot_z1, 0.0)
        spread = 0.0045 + aft * 0.22
        streak = 0.6 + 0.4 * noise3(p, (0.004, 0.003, 0.06), 43)
        soot = np.maximum(soot, np.exp(-aft / 0.12) * (1.0 - smoothstep(spread * 0.5, spread, np.abs(y - yc)))
                          * (zm > slot_z0) * streak * side)
    skin.grime(soot * 0.85, tint=(0.25, 0.24, 0.23), rough=0.6, metal_loss=0.6)

    # Dielectric radome, chequered ring and the olive-drab anti-glare panel.
    radome = 1.0 - smoothstep(0.0615, 0.0625, zn)
    skin.paint_over(hex_rgb("#2b2d29"), radome, rough=0.45)
    ring = (zn > 0.064) & (zn < 0.088)
    checks = ((np.floor((phi + np.pi) / (2 * np.pi / 24)) + np.floor((zn - 0.064) / 0.008)) % 2) < 1
    chips = smoothstep(0.70, 0.80, fbm(p, 0.010, 47)) * 0.7
    skin.paint_over(np.where(checks[:, None], SABRE_INK, SABRE_WHITE), ring.astype(float), rough=0.38, chips=chips * 0.4)
    for edge in (0.064, 0.088):
        skin.paint_over(SABRE_INK, _line((zn - edge) * FUS_LEN, 0.003), rough=0.4)
    glare_limit = np.radians(np.interp(zn, [0.088, 0.12, 0.165], [28.0, 50.0, 64.0]))
    glare = (1.0 - smoothstep(-0.001, 0.001, (a - glare_limit) * r)) * (zn > 0.088) * (1.0 - smoothstep(0.163, 0.167, zn))
    skin.paint_over(SABRE_OLIVE, glare, rough=0.72, chips=chips)

    # Korea-style yellow ID band with black borders.
    band = (zn > 0.705) & (zn < 0.738)
    skin.paint_over(SABRE_YELLOW, band.astype(float), rough=0.4, chips=chips)
    for edge in (0.705, 0.738):
        skin.paint_over(SABRE_INK, _line((zn - edge) * FUS_LEN, 0.006), rough=0.4, chips=chips)

    # Markings: U.S. AIR FORCE, the national insignia, the buzz number, pilot, rescue arrow and stencils.
    def side_mask(mask, z0, z1, y0, y1):
        u, v, weight = _side_uv(p, n, FUS_NOSE + z0 * FUS_LEN, FUS_NOSE + z1 * FUS_LEN, y0, y1)
        return np.where(weight > 0, _bilinear(mask, u, v), 0.0) * weight

    def side_rgba(art, z0, z1, y0, y1):
        u, v, weight = _side_uv(p, n, FUS_NOSE + z0 * FUS_LEN, FUS_NOSE + z1 * FUS_LEN, y0, y1)
        sample = _bilinear(art, u, v)
        return sample[:, :3], np.where(weight > 0, sample[:, 3], 0.0) * weight

    def lettering(text, z0, z1, y0, y1, colour=SABRE_INK, rows=1):
        aspect = (z1 - z0) * FUS_LEN / (y1 - y0)
        skin.paint_over(colour, side_mask(_sabre_text(text, aspect, rows), z0, z1, y0, y1), rough=0.45, chips=chips * 0.5)

    lettering("U.S. AIR FORCE", 0.190, 0.385, 0.072, 0.106)
    insignia_rgb, insignia_alpha = side_rgba(_sabre_insignia(), 0.765, 0.845, 0.058, 0.152)
    skin.paint_over(insignia_rgb, insignia_alpha, rough=0.42, chips=chips * 0.5)
    lettering("FU-861", 0.855, 0.952, 0.030, 0.078)
    lettering("CAPT. M. ORTEGA", 0.215, 0.300, 0.114, 0.126)
    rescue_rgb, rescue_alpha = side_rgba(_rescue_arrow(), 0.322, 0.366, 0.112, 0.127)
    skin.paint_over(rescue_rgb, rescue_alpha, rough=0.42)
    lettering("USAF F-86 SPORT\nSERIAL NO. 52-0861\nFUEL JP-4", 0.432, 0.500, 0.064, 0.094, rows=3)
    lettering("EXT. POWER\n28V DC", 0.612, 0.650, 0.074, 0.092, rows=2)
    lettering("NO STEP", 0.560, 0.598, 0.196, 0.206)

    # Fuel filler cap on the spine.
    top = smoothstep(0.55, 0.7, n[:, 1])
    cap = np.hypot(x, (zn - 0.53) * FUS_LEN)
    skin.colour = mix(skin.colour, hex_rgb("#a7aaad"), (1.0 - smoothstep(0.010, 0.011, cap)) * top)
    skin.groove(np.where(top > 0, cap - 0.0112, 1.0), width=0.0012)
    skin.paint_over(SABRE_RED, _line(cap - 0.0145, 0.003) * top, rough=0.4)

    # Weathering: heat-stained tail, exhaust soot, belly oil streaks, handling scratches.
    heat = smoothstep(0.935, 0.99, zn)
    temper = np.interp(zn, [0.935, 0.96, 0.98, 1.0], [0.0, 0.33, 0.66, 1.0])
    heat_tint = np.stack([np.interp(temper, [0, 0.33, 0.66, 1], c) for c in
                          ([0.80, 0.74, 0.55, 0.42], [0.78, 0.66, 0.45, 0.46], [0.76, 0.50, 0.38, 0.60])], axis=1)
    skin.colour = mix(skin.colour, heat_tint, heat * (1.0 - skin.paint))
    skin.rough = skin.rough + (0.34 - skin.rough) * heat
    exhaust = smoothstep(0.90, 1.0, zn) * (1.0 - smoothstep(0.05, 0.17, y))
    streaks = 0.5 + 0.5 * noise3(p, (0.006, 0.006, 0.12), 53)
    skin.grime(exhaust * streaks * 0.8, tint=(0.24, 0.23, 0.22), rough=0.55)
    belly = smoothstep(np.radians(115), np.radians(150), a)
    oil = np.exp(-np.mod(zn - 0.20, 0.135) * FUS_LEN / 0.16) * smoothstep(0.55, 0.85, noise3(p, (0.005, 0.005, 0.2), 59))
    skin.grime(oil * belly * 0.7, tint=(0.40, 0.34, 0.26), rough=0.5, metal_loss=0.35)
    skin.colour = skin.colour * (1.0 - 0.07 * smoothstep(np.radians(70), np.radians(170), a))[:, None]
    sill = (zn > 0.13) & (zn < 0.42) & (y > 0.08)
    walk = (zn > 0.42) & (zn < 0.70) & (n[:, 1] > 0.5)
    density = np.where(sill, 0.22, np.where(walk, 0.18, 0.03))
    skin.scratch(0.6 * scratches(zm, arc, 0.018, 1.0, 61) * (_hash(np.floor(zm / 0.018), np.floor(arc / 0.018), seed=63) < density))
    return skin


def sabre_lifting(p, n, frac, span_norm, span_hi, atlas, chord_len):
    """Wings, gear doors and stabiliser: panels between span joints and spars, rivets on ribs, ID band, insignia."""
    x, z = np.abs(p[:, 0]), p[:, 2]
    s = span_norm * span_hi  # metres from the centre line
    top = n[:, 1] >= 0.0
    skin_face = smoothstep(0.3, 0.6, np.abs(n[:, 1]))
    chord_m = chord_len
    joints = [0.14, 0.42, 0.70] if atlas != "stab" else [0.17, 0.32]
    spars = [0.14, 0.63] if atlas != "stab" else [0.16, 0.62]
    ribs = np.arange(0.10, span_hi, 0.075 if atlas != "stab" else 0.055)
    skin = _Skin(len(p))
    d_joint, k_joint, f_joint = _nearest(s, joints)
    d_spar, k_spar, f_spar = _nearest(frac, spars)
    panel = k_joint * 16 + k_spar * 2 + top
    skin.panels(panel, s, z, p, seed=211 if atlas != "stab" else 223)
    skin.height += 0.00025 * np.sin(np.pi * f_joint) * np.sin(np.pi * f_spar) * np.where(_hash(panel, seed=9) < 0.5, -1, 1)
    # Slats and leading edges: polished, eroded aluminium.
    slat = 1.0 - smoothstep(0.135, 0.145, frac)
    skin.colour = mix(skin.colour, ALU_TONES[7], slat * 0.6)
    skin.rough = skin.rough + (0.12 - skin.rough) * slat * 0.7
    erosion = (1.0 - smoothstep(0.0, 0.035, frac)) * smoothstep(0.55, 0.85, fbm(p, 0.004, 71))
    skin.rough = skin.rough + 0.2 * erosion
    skin.groove(np.where(skin_face > 0.5, d_joint, 1.0))
    skin.groove(np.where(skin_face > 0.5, d_spar * chord_m, 1.0))
    rivet = rivets(d_joint, z, (-0.0035, 0.0035), 0.007)
    rivet = np.maximum(rivet, rivets(d_spar * chord_m, s, (-0.0035, 0.0035), 0.007))
    rivet = np.maximum(rivet, rivets(_nearest(s, ribs)[0], z, (0.0,), 0.008))
    stringers = [0.28, 0.40, 0.52] if atlas != "stab" else [0.40]
    rivet = np.maximum(rivet, rivets(_nearest(frac, stringers)[0] * chord_m, s, (0.0,), 0.010) * (frac > 0.15) * (frac < 0.62))
    skin.rivet(rivet * skin_face)
    chips = smoothstep(0.70, 0.80, fbm(p, 0.010, 73)) * 0.7 + 0.6 * (1.0 - smoothstep(0.0, 0.02, frac))
    if atlas != "stab":
        # Yellow ID band, wrapped round the wing, with black borders.
        b0, b1 = 0.74 * span_hi, 0.82 * span_hi
        skin.paint_over(SABRE_YELLOW, ((s > b0) & (s < b1)).astype(float), rough=0.4, chips=chips)
        for edge in (b0, b1):
            skin.paint_over(SABRE_INK, _line(s - edge, 0.006), rough=0.4, chips=chips)
        # National insignia on the upper surfaces, star point forward.
        art = _sabre_insignia()
        x0, x1 = 0.36, 0.60
        width = x1 - x0
        height = width * art.shape[0] / art.shape[1]
        zc = z - (frac - 0.40) * chord_m  # centre the insignia on the 40 % chord line, following the sweep
        u = (s - x0) / width
        v = (z - (zc - height * 0.5)) / height
        inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1) & top
        sample = _bilinear(art, u, v)
        skin.paint_over(sample[:, :3], np.where(inside, sample[:, 3], 0.0) * skin_face, rough=0.42, chips=chips * 0.4)
        # Black walkway outline at the root and a filler cap outboard.
        walk = _box_distance(s, frac * chord_m, 0.12, 0.30, 0.26 * chord_m, 0.58 * chord_m)
        skin.paint_over(SABRE_INK, _line(walk, 0.003) * top * skin_face, rough=0.45, chips=chips)
        cap = np.hypot(s - 0.66, (frac - 0.36) * chord_m)
        skin.colour = mix(skin.colour, hex_rgb("#a7aaad"), (1.0 - smoothstep(0.009, 0.010, cap)) * top)
        skin.groove(np.where(top, cap - 0.0102, 1.0), width=0.0012)
        skin.paint_over(SABRE_RED, _line(cap - 0.013, 0.0028) * top, rough=0.4)
        inside_walk = (walk < 0) & top
        skin.scratch(0.6 * scratches(s, z, 0.016, 1.0, 79) * np.where(inside_walk, 0.35, 0.03))
        # Undersides: duller, with streaks from the gear bays and drains.
        streak = smoothstep(0.55, 0.85, noise3(p, (0.2, 0.006, 0.006), 83)) * (frac > 0.3)
        skin.grime(np.where(top, 0.0, 0.35 * streak), tint=(0.40, 0.35, 0.28), rough=0.5, metal_loss=0.3)
    else:
        # Stabiliser roots sit beside the exhaust: soot on the inboard aft part.
        soot = (1.0 - smoothstep(0.10, 0.22, s)) * smoothstep(0.3, 0.9, frac)
        skin.grime(soot * (0.5 + 0.5 * noise3(p, (0.2, 0.01, 0.01), 89)) * 0.6, tint=(0.25, 0.24, 0.23))
    skin.rough = skin.rough + np.where(top, 0.0, 0.06)
    # Gap and edge faces read as plain dull metal.
    skin.colour = mix(ALU_TONES[6] * 0.8, skin.colour, skin_face)
    return skin


def sabre_fin(p, n, frac, height_norm):
    y, z = p[:, 1], p[:, 2]
    chord_m = 0.36
    skin = _Skin(len(p))
    joints = [0.212 + 0.365 * h for h in (0.30, 0.62)]
    d_joint, k_joint, f_joint = _nearest(y, joints)
    d_spar, k_spar, f_spar = _nearest(frac, [0.12, 0.62])
    panel = k_joint * 8 + k_spar
    skin.panels(panel, y, z, p, seed=307)
    skin.height += 0.00025 * np.sin(np.pi * f_joint) * np.sin(np.pi * f_spar) * np.where(_hash(panel, seed=11) < 0.5, -1, 1)
    side = smoothstep(0.35, 0.6, np.abs(n[:, 0]))
    skin.groove(np.where(side > 0.5, d_joint, 1.0))
    skin.groove(np.where(side > 0.5, d_spar * chord_m, 1.0))
    rivet = rivets(d_joint, z, (-0.0035, 0.0035), 0.007)
    rivet = np.maximum(rivet, rivets(d_spar * chord_m, y, (-0.0035, 0.0035), 0.007))
    rivet = np.maximum(rivet, rivets(_nearest(y, np.arange(0.24, 0.58, 0.045))[0], z, (0.0,), 0.008))
    rivet = np.maximum(rivet, rivets(_nearest(frac, [0.30, 0.45])[0] * chord_m, y, (0.0,), 0.010))
    skin.rivet(rivet * side)
    chips = smoothstep(0.70, 0.80, fbm(p, 0.010, 97)) * 0.7
    # Chequered fin cap with a black keyline under it.
    cap = height_norm > 0.83
    checks = ((np.floor(z / 0.016) + np.floor(y / 0.016)) % 2) < 1
    skin.paint_over(np.where(checks[:, None], SABRE_INK, SABRE_WHITE), cap.astype(float) * side, rough=0.38, chips=chips * 0.5)
    skin.paint_over(SABRE_INK, _line((height_norm - 0.83) * 0.365, 0.004) * side, rough=0.4)

    def lettering(text, z0, z1, y0, y1, rows=1):
        u, v, weight = _side_uv(p, n, z0, z1, y0, y1)
        mask = _sabre_text(text, (z1 - z0) / (y1 - y0), rows)
        skin.paint_over(SABRE_INK, np.where(weight > 0, _bilinear(mask, u, v), 0.0) * weight, rough=0.45, chips=chips * 0.5)

    lettering("U.S. AIR FORCE", 0.905, 1.035, 0.352, 0.366)
    lettering("20861", 0.885, 1.045, 0.300, 0.342)
    # Exhaust haze at the fin root's trailing edge.
    soot = (1.0 - smoothstep(0.0, 0.12, height_norm)) * smoothstep(0.4, 0.9, frac)
    skin.grime(soot * 0.4, tint=(0.25, 0.24, 0.23))
    skin.colour = mix(ALU_TONES[6] * 0.8, skin.colour, side)
    return skin


def chord_length(pos, span_axis: int, table, lo: float, hi: float):
    """Local chord (metres) of a lifting surface, interpolated like chord_fraction."""
    le, te = table
    centres = lo + (np.arange(len(le)) + 0.5) * (hi - lo) / len(le)
    s = pos[..., span_axis]
    return np.maximum(np.interp(s, centres, te) - np.interp(s, centres, le), 1e-3)


def height_to_normal(height, pos, covered, strength=1.0):
    """Tangent-space normal map (OpenGL / Godot convention, green = up the image) from a height field in metres.
    Slopes use the true texel size from the scene positions; neighbours more than 1 cm apart are UV-island seams."""
    h = dilate(height[..., None], covered)[..., 0]
    pp = dilate(pos, covered)
    slopes = []
    for axis in (1, 0):
        dp = (np.roll(pp, -1, axis) - np.roll(pp, 1, axis)) * 0.5
        length = np.linalg.norm(dp, axis=2)
        dh = (np.roll(h, -1, axis) - np.roll(h, 1, axis)) * 0.5
        valid = (length > 1e-6) & (length < 0.005)
        slopes.append(np.where(valid, dh / np.maximum(length, 1e-6), 0.0) * strength)
    normal = np.stack([-slopes[0], slopes[1], np.ones_like(h)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return normal * 0.5 + 0.5


def build_sabre(atlas: str):
    materials, size = SABRE_ATLASES[atlas]
    skin_axis = {"wing": 1, "stab": 1, "doors": 1, "fin": 0}.get(atlas, -1)
    pos, nrm, _mat, covered = bake_scene(JET_GLB, materials, size, symmetric=atlas in ("wing", "stab", "doors"),
                                         skin_axis=skin_axis)
    p, n = pos[covered], nrm[covered]
    if atlas == "fuselage":
        skin = sabre_fuselage(p, n)
    elif atlas in ("wing", "stab", "doors"):
        span_hi = 0.443 if atlas == "stab" else 0.998
        lifting = ("paint_stab",) if atlas == "stab" else ("paint_wing",)
        table = chord_table(JET_GLB, lifting, 0, 28 if atlas == "stab" else 48, -span_hi, span_hi)
        frac = chord_fraction(p, 0, table, -span_hi, span_hi)
        if atlas == "doors":
            n = n.copy()
            n[:, 1] = -np.maximum(np.abs(n[:, 1]), 0.7)
        skin = sabre_lifting(p, n, frac, np.abs(p[:, 0]) / span_hi, span_hi, atlas,
                             chord_length(p, 0, table, -span_hi, span_hi))
    else:
        table = chord_table(JET_GLB, ("paint_fin",), 1, 20, 0.212, 0.577)
        frac = chord_fraction(p, 1, table, 0.212, 0.577)
        skin = sabre_fin(p, n, frac, (p[:, 1] - 0.212) / (0.577 - 0.212))
    height, width = covered.shape

    def full(values, channels):
        out = np.zeros((height, width, channels))
        out[covered] = values.reshape(len(values), channels)
        return dilate(out, covered)

    to_image = lambda a: Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    colour = full(np.clip(skin.colour, 0, 1), 3)
    rough = full(np.repeat(np.clip(skin.rough, 0.06, 1.0)[:, None], 3, axis=1), 3)
    metal = full(np.repeat(np.clip(skin.metal, 0, 1)[:, None], 3, axis=1), 3)
    height_map = np.zeros((height, width))
    height_map[covered] = skin.height
    normal = height_to_normal(height_map, pos, covered)
    return (to_image(colour), to_image(rough).convert("L"), to_image(metal).convert("L"), to_image(normal))


_SABRE_CACHE: dict = {}


def _sabre_cached(atlas: str):
    if atlas not in _SABRE_CACHE:
        _SABRE_CACHE[atlas] = build_sabre(atlas)
    return _SABRE_CACHE[atlas]


def outputs() -> dict:
    """Output path -> zero-argument builder returning encoded bytes (built only when selected)."""
    # shared/ holds unchanged CC0 maps from ambientCG (see shared/LICENSES.txt); this tool does not write them.
    files: dict = {}
    for skin, design in CANOPY_DESIGNS.items():
        files[f"hx-700/{skin}_canopy.png"] = lambda d=design: encode(build_canopy(d), ".png")
        files[f"hx-700/{skin}_boom.png"] = lambda s=skin: encode(build_boom(BOOM_PALETTES[s]), ".png")
    for skin, tint in MONSTER_TINTS.items():
        files[f"monster-car-2/{skin}_livery.jpg"] = lambda t=tint: encode(build_monster(t), ".jpg")
        glow = dict(tint, value=1.0)  # the emission map is already at full value; only its hue moves
        files[f"monster-car-2/{skin}_emission.png"] = lambda g=glow: encode(build_monster(g, MC_EMISSION), ".png")
    for atlas in JET_ATLASES:
        files[f"avanti-s-a200/verde_neon_carbono_{atlas}.jpg"] = lambda a=atlas: encode(_jet_cached(a)[0], ".jpg")
        files[f"avanti-s-a200/verde_neon_carbono_{atlas}_emission.png"] = lambda a=atlas: encode(_jet_cached(a)[1], ".png")
        files[f"avanti-s-a200/verde_neon_carbono_{atlas}_roughness.png"] = lambda a=atlas: encode(_jet_cached(a)[2], ".png")
    for atlas in SABRE_ATLASES:
        stem = f"avanti-s-a200/sabre_plata_{atlas}"
        files[stem + ".jpg"] = lambda a=atlas: encode(_sabre_cached(a)[0], ".jpg")
        files[stem + "_roughness.jpg"] = lambda a=atlas: encode(_sabre_cached(a)[1], ".jpg")
        files[stem + "_metallic.png"] = lambda a=atlas: encode(_sabre_cached(a)[2], ".png")
        files[stem + "_normal.png"] = lambda a=atlas: encode(_sabre_cached(a)[3], ".png")
    return files


_JET_CACHE: dict = {}


def _jet_cached(atlas: str):
    if atlas not in _JET_CACHE:
        _JET_CACHE[atlas] = build_jet(atlas)
    return _JET_CACHE[atlas]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail when a committed output differs")
    parser.add_argument("--only", default="", help="build only outputs whose path contains this text")
    args = parser.parse_args()
    selected = {k: v for k, v in outputs().items() if args.only in k}
    stale = []
    for relative, make in selected.items():
        data = make()
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
