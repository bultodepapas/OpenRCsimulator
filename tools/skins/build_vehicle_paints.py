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


def scene_primitives(path: Path, materials, *, mesh_nodes=()):
    """Yield (material, scene positions, scene normals, uv, triangles) with every node transform applied."""
    doc, accessor = read_glb(path)
    names = [m["name"] for m in doc["materials"]]
    wanted = set(materials)
    found = []

    def walk(index: int, parent: np.ndarray) -> None:
        node = doc["nodes"][index]
        world = parent @ _node_matrix(node)
        if "mesh" in node and (not mesh_nodes or node.get("name") in mesh_nodes):
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


def bake_scene(path: Path, materials, size, symmetric: bool = False, skin_axis: int = -1, *, mesh_nodes=()):
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
    for name, pos, nrm, uv, tris in scene_primitives(path, materials, mesh_nodes=mesh_nodes):
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
ALU_TONES = np.array([(216, 220, 224), (196, 203, 211), (230, 229, 223), (180, 188, 197),
                      (206, 207, 201), (222, 225, 231), (170, 176, 183), (236, 237, 236)], dtype=np.float64) / 255.0
ALU_ROUGH = np.array([0.26, 0.34, 0.22, 0.42, 0.31, 0.27, 0.47, 0.19])
# Metallic share per panel. Compatibility flight and Home scenes disable sky reflections (atmosphere.gd), where a
# fully metallic skin keeps only sun highlights and reads near-black; a partial share keeps a diffuse silver body
# under ambient light and still reflects where the High profile enables sky reflections.
ALU_METAL = np.array([0.60, 0.52, 0.66, 0.46, 0.56, 0.60, 0.44, 0.70])
SABRE_INK = hex_rgb("#1d1f22")
SABRE_WHITE = hex_rgb("#ebe9e2")
SABRE_YELLOW = hex_rgb("#e8bb24")
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


def _sabre_text(text: str, aspect: float, lines: int = 1, font=None, stroke=None) -> np.ndarray:
    """Upright lettering mask (1 = ink), USAF block style by default; several lines for stencil placards."""
    key = ("text", text, round(aspect, 3), lines, str(font), stroke)
    if key not in _SABRE_ART:
        from PIL import ImageDraw, ImageFont
        height = 128 * lines
        width = int(round(height * aspect))
        canvas = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(canvas)
        rows = text.split("\n")
        face = str(font or FONT)
        font = ImageFont.truetype(face, int(height / len(rows) * 0.78))
        stroke = (6 if lines == 1 else 2) if stroke is None else stroke
        widest = max(draw.textbbox((0, 0), row, font=font, stroke_width=stroke)[2] for row in rows)
        if widest > width * 0.97:
            font = ImageFont.truetype(face, int(height / len(rows) * 0.78 * width * 0.97 / widest))
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


def _side_uv(p, n, z0, z1, y0, y1):
    """Box coordinates on a fuselage or fin side that read left-to-right from both sides, and the side weight."""
    z, y = p[:, 2], p[:, 1]
    u = np.where(n[:, 0] >= 0.0, (z1 - z) / (z1 - z0), (z - z0) / (z1 - z0))
    v = (y1 - y) / (y1 - y0)
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    return u, v, inside * smoothstep(0.35, 0.6, np.abs(n[:, 0]))


REVOC_RED = hex_rgb("#e30613")
REVOC_WHITE = hex_rgb("#faf9f6")
REVOC_GRAPHITE = hex_rgb("#26282c")
REVOC_SIZES = {"fuselage": (2048, 4096), "wing": (2048, 2048), "stab": (1024, 1024), "fin": (2048, 1024)}


def avanti_flank_decal(colour, p, art, z0, z1, centre_y):
    """Project premultiplied artwork across the intake bevels without fading the ink."""
    height = (z1 - z0) * art.shape[0] / art.shape[1]
    u = (p[:, 2] - z0) / (z1 - z0)
    u = np.where(p[:, 0] > 0, 1 - u, u)
    v = 0.5 + (centre_y - p[:, 1]) / height
    hit = (u >= 0) & (u <= 1) & (v >= 0) & (v <= 1)
    rgba = _bilinear(art, u[hit], v[hit])
    colour[hit] = colour[hit] * (1 - rgba[:, 3:]) + rgba[:, :3]


def revoc_body_colours(y, z):
    # The lower sweep levels out beneath the intake and climbs into the tail.
    knots = np.array([-0.94, -0.65, -0.15, 0.22, 0.88, 1.28])
    heights = np.array([0.018, -0.050, -0.052, -0.012, 0.167, 0.255])
    slopes = np.array([-0.31, -0.011, 0.0, 0.208, 0.29, 0.10])
    i = np.clip(np.searchsorted(knots, z) - 1, 0, len(knots) - 2)
    length = knots[i + 1] - knots[i]
    t = np.clip((z - knots[i]) / length, 0, 1)
    edge = (heights[i] + (heights[i + 1] - heights[i]) * t * t * (3 - 2 * t)
            + length * t * (1 - t) * (slopes[i] * (1 - t) - slopes[i + 1] * t))
    d = y - edge
    colour = mix(REVOC_RED, REVOC_WHITE, smoothstep(-0.001, 0.001, d))
    # Taper both ends of the graphite keyline into the paint instead of capping it square.
    width = 0.030 * smoothstep(-0.23, 0.48, z) * (1 - smoothstep(0.94, 1.19, z))
    stripe = smoothstep(0.004, 0.006, d) * (1 - smoothstep(0.003, 0.005, d - width))
    colour = mix(colour, REVOC_GRAPHITE, stripe)
    # Use the same upper sweep on both sides of the fuselage/fin joint.
    rise = y - 0.245 + 0.28 * (z - 1.005)
    return mix(colour, REVOC_RED, smoothstep(-0.001, 0.001, rise))


def revoc_body(atlas, p, logo):
    _, y, z = p.T
    colour = revoc_body_colours(y, z)
    if atlas == "fuselage":
        # Finish the nose with a full cap.
        colour = mix(colour, REVOC_GRAPHITE, 1 - smoothstep(-0.847, -0.845, z))
        # Follow the lower intake crease on both flanks. At 390 mm wide the midpoint
        # of the clear space between the two lines (source row 277) is 13.1 mm below centre.
        crease_y = np.interp(z, [-0.52, -0.36, -0.205], [0.0128, 0.0097, 0.0091])
        avanti_flank_decal(colour, p, logo, -0.595, -0.205, crease_y + 0.0131)
        return colour
    # Curl the cap up to the top edge before the rudder, which shares UVs with
    # the fixed fin and carries solid red across the whole hinge.
    cap = y - 0.531 - 0.20 * (z - 1.1) - 0.064 * smoothstep(1.178, 1.218, z)
    colour = mix(colour, REVOC_WHITE, smoothstep(-0.001, 0.001, cap))
    colour = mix(colour, REVOC_GRAPHITE, smoothstep(0.010, 0.012, cap))
    # The square emblem fits on the fixed fin ahead of the rudder hinge.
    avanti_flank_decal(colour, p, logo[:, :logo.shape[0]], 0.992, 1.109, 0.376)
    return colour


def bake_avanti_lifting(atlas, size, paint):
    # For the exposed skins U is linear in span and each half of V is linear in
    # chord. Use those shared paint coordinates on the fixed and moving pieces.
    # Wrapped and overlapping cove UVs then cannot overwrite the visible faces.
    if atlas == "stab":
        inner, outer, nose, aft = 0.055, 0.443, 0.986, 1.297
    else:
        inner, outer, nose, aft = 0.060, 0.998, 0.001, 0.614
    materials = JET_ATLASES[atlas][0]
    edges = chord_table(JET_GLB, materials, 0, 28 if atlas == "stab" else 48, -outer, outer)
    width, height = size
    u = (np.arange(width) + 0.5) / width
    span = inner + (outer - inner) * u
    colour = np.empty((height, width, 3), dtype=np.uint8)
    for start in range(0, height, 128):
        end = min(start + 128, height)
        v = (np.arange(start, end)[:, None] + 0.5) / height
        z = aft - (aft - nose) * (2 * v % 1)
        # Keep the leading-edge roll in upper colours. The lower field runs to
        # the hinge and trailing edge, where the UVs already separate the skins.
        position = np.stack(np.broadcast_arrays(span, 0.0, z), axis=-1)
        chord = chord_fraction(position, 0, edges, -outer, outer)
        lower_face = (v >= 0.5) * smoothstep(0.025, 0.036, chord)
        rgb = paint(atlas, span, z, lower_face)
        colour[start:end] = np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(colour)


def revoc_lifting(atlas, span, z, lower_face):
    if atlas == "stab":
        span_band = sweep = tip = span / 0.443
    else:
        span_band = span
        sweep = span + 0.85 * (z - 0.28)
        tip = span - 0.04 * (z - 0.4)
    upper = mix(REVOC_WHITE, REVOC_GRAPHITE, smoothstep(0.397, 0.403, sweep))
    upper = mix(upper, REVOC_WHITE, smoothstep(0.456, 0.462, sweep))
    upper = mix(upper, REVOC_RED, smoothstep(0.485, 0.491, sweep))
    lower = mix(REVOC_GRAPHITE, REVOC_WHITE, smoothstep(0.711, 0.717, span_band))
    lower = mix(lower, REVOC_RED, smoothstep(0.826, 0.832, span_band))
    rgb = mix(upper, lower, lower_face)
    # Finish the tips with continuous white keylines and graphite on both faces.
    rgb = mix(rgb, REVOC_WHITE, smoothstep(0.897, 0.903, tip))
    return mix(rgb, REVOC_GRAPHITE, smoothstep(0.919, 0.925, tip))


def bake_avanti_side(atlas, sample_size, paint):
    materials = JET_ATLASES[atlas][0]
    mesh_nodes = ("vertical_tail_fixed",) if atlas == "fin" else ()
    p, n, material_ids, covered = bake_scene(JET_GLB, materials, sample_size, skin_axis=0, mesh_nodes=mesh_nodes)
    del n, material_ids
    colour = np.zeros(p.shape, dtype=np.uint8)
    for rows in range(0, len(covered), 128):
        block = slice(rows, rows + 128)
        hit = covered[block]
        rgb = paint(p[block][hit])
        colour[block][hit] = np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8)
    del p
    # Include the gutter on both sides of each strip, wrapping like the GPU sampler.
    gutter = 16
    padded = np.empty_like(colour)
    for start in range(0, len(covered), 256):
        end = min(start + 256, len(covered))
        rows = np.arange(start - gutter, end + gutter) % len(covered)
        strip = dilate(colour[rows].astype(np.float32), covered[rows], passes=gutter)
        padded[start:end] = np.rint(strip[gutter:-gutter]).astype(np.uint8)
    return Image.fromarray(padded)


def build_revoc(atlas):
    size = REVOC_SIZES[atlas]
    # Filter four samples per delivered texel after projection and island padding.
    sample_size = (size[0] * 2, size[1] * 2)
    if atlas in ("wing", "stab"):
        return bake_avanti_lifting(atlas, sample_size, revoc_lifting).resize(size, Image.Resampling.LANCZOS)
    with Image.open(ROOT / "site/assets/brands/revoc/revoc-custom-logo.png") as source:
        logo = np.asarray(source.convert("RGBA"), dtype=np.float32) / 255
    logo[..., :3] *= logo[..., 3:]
    return bake_avanti_side(atlas, sample_size, lambda p: revoc_body(atlas, p, logo)).resize(size, Image.Resampling.LANCZOS)


JETI_RUBY = hex_rgb("#ae122e")
JETI_GARNET = hex_rgb("#801129")
JETI_GRAPHITE = hex_rgb("#353b44")
JETI_CARBON = hex_rgb("#262b33")
JETI_PEWTER = hex_rgb("#77838f")
JETI_SILVER = hex_rgb("#d6dee4")
JETI_PEARL = hex_rgb("#f0f4f6")
JETI_SIZES = {"fuselage": (4096, 4096), "wing": (4096, 4096), "stab": (2048, 2048), "fin": (2048, 2048)}
JETI_ROUGHNESS_SIZE = (1024, 1024)


def jeti_shell_edges(y, z):
    lower = y + 0.014 - 0.078 * smoothstep(0.30, 1.12, z)
    shoulder = y - (0.111 - 0.022 * smoothstep(-0.19, 0.36, z) + 0.156 * smoothstep(0.28, 1.10, z))
    return lower, shoulder


def jeti_shell(y, z):
    lower, shoulder = jeti_shell_edges(y, z)
    lacquer = mix(JETI_GARNET, JETI_RUBY, smoothstep(0.0, 0.043, lower))
    colour = mix(JETI_SILVER, lacquer, smoothstep(-0.0013, 0.0013, lower))
    colour = mix(colour, JETI_PEARL, smoothstep(-0.0013, 0.0013, shoulder))
    return mix(colour, JETI_GRAPHITE, smoothstep(0.005, 0.0076, shoulder))


def jeti_nose_cut(y, z):
    return z + 0.784 - 0.20 * (y - 0.054)


def jeti_exhaust_collar(z):
    # The nose pole at V=1 filters against the exhaust end at V=0.
    return smoothstep(1.219, 1.234, z)


def jeti_belly_panel(x, y, z):
    # Follow the keel between the nose-gear door and the rising tail.
    taper = smoothstep(-0.538, -0.371, z) * (1 - smoothstep(0.622, 0.875, z))
    half_width = (0.040 + 0.014 * smoothstep(-0.225, 0.24, z)) * taper
    edge = half_width - np.abs(x)
    belly = 1 - smoothstep(-0.041, -0.024, y)
    panel = smoothstep(-0.0011, 0.0011, edge) * smoothstep(0.001, 0.004, half_width)
    return edge, panel * belly


def jeti_fuselage(p, logo):
    x, y, z = p.T
    colour = jeti_shell(y, z)
    cap = jeti_nose_cut(y, z)
    colour = mix(JETI_CARBON, colour, smoothstep(0.001, 0.003, cap))
    colour = mix(colour, JETI_PEARL, smoothstep(0.002, 0.004, cap) * (1 - smoothstep(0.007, 0.009, cap)))

    edge, panel = jeti_belly_panel(x, y, z)
    colour = mix(colour, JETI_GRAPHITE, panel)
    piping = 1 - smoothstep(0.0020, 0.0052, edge)
    colour = mix(colour, JETI_PEWTER, 0.88 * panel * piping)
    # Repeat the telemetry marks within the keel, in front of its taper.
    for start, span in ((0.438, 0.021), (0.477, 0.026), (0.520, 0.031)):
        shape = np.maximum(np.abs(x) - span, np.abs(z - start + 0.31 * np.abs(x)) - 0.008)
        colour = mix(colour, JETI_RUBY, panel * (1 - smoothstep(-0.001, 0.001, shape)))

    # Corner marks sit on the fixed shell, just outside the closed nose-gear door.
    side = np.abs(x)
    for stop, direction in ((-0.763, 1), (-0.552, -1)):
        along = direction * (z - stop)
        upright = _box_distance(side, along, 0.026, 0.029, 0.0, 0.024)
        crossbar = _box_distance(side, along, 0.014, 0.029, 0.0, 0.003)
        bracket = 1 - smoothstep(-0.0006, 0.0006, np.minimum(upright, crossbar))
        colour = mix(colour, JETI_PEWTER, bracket * (1 - smoothstep(-0.052, -0.040, y)))

    # The carbon insert follows the exposed spine behind the cockpit.
    taper = smoothstep(0.31, 0.45, z) * (1 - smoothstep(0.75, 0.91, z))
    inset = (1 - smoothstep(0.048, 0.057, np.abs(x))) * taper * smoothstep(0.160, 0.186, y)
    warp = np.sin(2 * np.pi * x / 0.005)
    weft = np.sin(2 * np.pi * z / 0.006)
    twill = warp * weft * np.cos(2 * np.pi * (x - z) / 0.012)
    colour = mix(colour, JETI_CARBON + 0.016 * twill[:, None], 0.76 * inset)

    # Two brushed-silver rails end in the same diagonal as the fin's signal marks.
    rail = np.abs(x) - (0.053 - 0.029 * smoothstep(0.42, 0.87, z))
    rail = (1 - smoothstep(0.0010, 0.0027, np.abs(rail))) * taper
    colour = mix(colour, JETI_SILVER, 0.59 * rail * smoothstep(0.177, 0.192, y))
    for start, width in ((0.615, 0.012), (0.644, 0.016), (0.677, 0.021)):
        edge = z - start + 0.36 * x
        shape = np.maximum(np.abs(x) - width, np.abs(edge) - 0.007)
        mark = (1 - smoothstep(-0.0011, 0.0011, shape)) * smoothstep(0.177, 0.192, y)
        colour = mix(colour, JETI_SILVER, mark)

    # Keep the full badge on the smooth cheek ahead of the rising intake fold.
    centre = 0.033 + 0.013 * smoothstep(-0.748, -0.493, z)
    avanti_flank_decal(colour, p, logo, -0.748, -0.493, centre)
    return mix(colour, JETI_CARBON, jeti_exhaust_collar(z))


def jeti_fuselage_roughness(p):
    x, y, z = p.T
    lower, shoulder = jeti_shell_edges(y, z)
    lacquer = smoothstep(-0.002, 0.002, lower) * (1 - smoothstep(-0.002, 0.007, shoulder))
    # Lacquer, satin aluminium and satin carbon share one UV layout.
    satin = 0.49 + 0.09 * smoothstep(0.0, 0.009, shoulder)
    rough = satin + (0.27 - satin) * lacquer
    _, panel = jeti_belly_panel(x, y, z)
    rough += (0.59 - rough) * panel
    rough = 0.55 + (rough - 0.55) * smoothstep(0.001, 0.011, jeti_nose_cut(y, z))
    rough += (0.55 - rough) * jeti_exhaust_collar(z)
    return np.repeat(rough[:, None], 3, axis=1)


def jeti_fin(p):
    _, y, z = p.T
    colour = mix(jeti_shell(y, z), JETI_RUBY, smoothstep(0.243, 0.285, y))
    # A low-contrast ruby sweep rounds off the fixed fin's leading shoulder.
    ridge = z - (0.86 + 0.81 * (y - 0.23))
    tint = (1 - smoothstep(0.028, 0.093, ridge)) * smoothstep(0.255, 0.352, y)
    colour = mix(colour, JETI_GARNET, 0.48 * tint)
    # A rising group of telemetric signal bars with generous clearance from the rudder.
    along = z - 0.72 * (y - 0.30)
    across = y + 0.34 * (z - 1.03)
    for start, height, length in ((0.328, 0.016, 0.088), (0.368, 0.021, 0.104), (0.413, 0.027, 0.119)):
        shape = np.maximum(np.abs(across - start) - height / 2, np.abs(along - 0.982) - length / 2)
        colour = mix(colour, JETI_PEARL, 1 - smoothstep(-0.001, 0.001, shape))
    return colour


def jeti_wing_lower(span, z):
    # Sweep into the graphite tip ahead of the outboard door and hinge line.
    tip = smoothstep(0.688, 0.694, span)
    sweep = z - (0.131 + 0.49 * (span - 0.430))
    width = 0.081 - 0.043 * smoothstep(0.470, 0.627, span)
    entry = smoothstep(-0.002, 0.002, span - (0.433 + 0.52 * sweep))
    blade = smoothstep(-0.0015, 0.0015, sweep) * (1 - smoothstep(width - 0.0015, width + 0.0015, sweep))
    dark = np.maximum(tip, entry * blade)
    colour = mix(JETI_SILVER, JETI_GRAPHITE, dark)
    rail = smoothstep(0.004, 0.007, sweep) * (1 - smoothstep(0.020, 0.023, sweep))
    rail *= smoothstep(0.459, 0.484, span) * (1 - smoothstep(0.646, 0.681, span))
    return mix(colour, JETI_RUBY, rail)


def jeti_lifting(atlas, span, z, lower_face):
    if atlas == "stab":
        # The tailplane reuses V around the hinge. Its bands depend on span alone.
        silver = mix(JETI_GRAPHITE, JETI_SILVER, smoothstep(0.162, 0.166, span))
        silver = mix(silver, JETI_PEARL, smoothstep(0.254, 0.258, span))
        tip = mix(JETI_RUBY, JETI_GARNET, 0.72 * smoothstep(0.407, 0.432, span))
        return np.broadcast_to(mix(silver, tip, smoothstep(0.266, 0.270, span)), (*z.shape[:-1], span.size, 3))

    # One tapered blade on each wing opens toward the leading edge.
    blade = span - (0.310 + 0.45 * (z - 0.23) + 0.65 * (z - 0.24) ** 2)
    width = 0.200 - 0.082 * smoothstep(0.11, 0.53, z)
    silver = smoothstep(-0.002, 0.002, blade) * (1 - smoothstep(-0.002, 0.002, blade - width))
    upper = mix(JETI_GRAPHITE, JETI_SILVER, silver)
    border = smoothstep(-0.010, -0.007, blade) * (1 - smoothstep(-0.002, 0.001, blade))
    upper = mix(upper, JETI_PEARL, border)
    # A tapered graphite inlay beside the blade provides a secondary edge in close-up.
    inlay = smoothstep(-0.033, -0.029, blade) * (1 - smoothstep(-0.015, -0.011, blade))
    inlay *= smoothstep(0.045, 0.117, z) * (1 - smoothstep(0.33, 0.43, z))
    upper = mix(upper, JETI_CARBON, 0.64 * inlay)
    lower = jeti_wing_lower(span, z)
    colour = mix(upper, lower, lower_face)
    cap = span - (0.746 + 0.28 * (z - 0.28))
    colour = mix(colour, JETI_PEARL, smoothstep(-0.017, -0.013, cap))
    bevel = smoothstep(0.016, 0.025, cap) * (1 - smoothstep(0.041, 0.057, cap))
    ruby = mix(JETI_RUBY, JETI_GARNET, 0.50 * bevel)
    colour = mix(colour, ruby, smoothstep(-0.002, 0.002, cap))
    return mix(colour, JETI_GARNET, smoothstep(0.932, 0.953, span))


def build_jeti(atlas):
    if atlas == "fuselage_roughness":
        return bake_avanti_side("fuselage", JETI_ROUGHNESS_SIZE, jeti_fuselage_roughness).convert("L")
    size = JETI_SIZES[atlas]
    if atlas in ("wing", "stab"):
        return bake_avanti_lifting(atlas, size, jeti_lifting)
    if atlas == "fin":
        return bake_avanti_side(atlas, size, jeti_fin)
    # Premultiply before filtering so the PNG's transparent corners leave no fringe.
    with Image.open(SPONSORS / "jeti_model_logo.png") as source:
        logo = np.asarray(source.convert("RGBA"), dtype=np.float32) / 255
    logo[..., :3] *= logo[..., 3:]
    return bake_avanti_side(atlas, size, lambda p: jeti_fuselage(p, logo))


ELAN_BLUE = hex_rgb("#227bd3")
ELAN_DEEP = hex_rgb("#174785")
ELAN_CARBON = hex_rgb("#243140")
ELAN_INK = hex_rgb("#192330")
ELAN_ALLOY = hex_rgb("#b3c7d3")
ELAN_PEARL = hex_rgb("#e8f1f5")
ELAN_AMBER = hex_rgb("#e6ad63")
ELAN_SIZES = {
    "fuselage": (4096, 4096), "wing": (4096, 4096), "stab": (2048, 2048), "fin": (2048, 2048),
}


def elan_twill(a, b):
    warp = np.sin(2 * np.pi * a / 0.0064)
    weft = np.sin(2 * np.pi * b / 0.0064)
    return ELAN_CARBON + (0.015 * warp * weft * np.cos(2 * np.pi * (a - b) / 0.013))[..., None]


def elan_lettering(text, aspect):
    alpha = _sabre_text(text, aspect, stroke=3)[..., None]
    return np.concatenate((ELAN_PEARL * alpha, alpha), axis=-1)


def elan_shell_masks(y, z):
    # The alloy C follows the two-tone split behind the intake shoulder.
    split = z - (0.281 - 11.3 * (y - 0.101) ** 2)
    lower_edge = -0.030 + 0.071 * smoothstep(0.50, 1.14, z)
    belly = 1 - smoothstep(-0.002, 0.002, y - lower_edge)
    # The wrapped atlas shares a filter edge between the nose pole and exhaust.
    collars = np.maximum(1 - smoothstep(-0.892, -0.879, z), smoothstep(1.219, 1.234, z))
    return split, belly, collars


def elan_chamfer(a, b, half_a, half_b, corner):
    a = np.abs(a) - half_a
    b = np.abs(b) - half_b
    return np.maximum(np.maximum(a, b), (a + b + corner) * 0.7071)


def elan_panel_layout(side, y, z):
    service = elan_chamfer(z - 0.521 - 0.29 * (y - 0.078), y - 0.080, 0.070, 0.030, 0.011)
    flank = smoothstep(0.062, 0.087, side)
    deck = elan_chamfer(side - 0.043, z - 0.681, 0.015, 0.058, 0.010)
    crown = smoothstep(0.177, 0.207, y)
    return service, flank, deck, crown


def elan_fuselage(p, badge):
    x, y, z = p.T
    side = np.abs(x)
    split, belly, collars = elan_shell_masks(y, z)
    blue = mix(ELAN_DEEP, ELAN_BLUE, smoothstep(-0.012, 0.134, y))
    core = elan_twill(y + 0.43 * side, z)
    colour = mix(blue, core, smoothstep(-0.002, 0.002, split))
    colour = mix(colour, ELAN_PEARL, belly)

    flank = smoothstep(0.043, 0.082, side) * smoothstep(-0.030, 0.015, y)
    flank *= 1 - smoothstep(0.196, 0.259, y)
    colour = mix(colour, ELAN_INK, flank * _line(split - 0.0025, 0.014))
    colour = mix(colour, ELAN_ALLOY, flank * _line(split, 0.0070))
    colour = mix(colour, ELAN_PEARL, flank * _line(split - 0.0021, 0.0018))

    # The centerline ends cleanly at the glass and follows the rear spine.
    nose_spine = smoothstep(-0.872, -0.782, z) * (1 - smoothstep(-0.666, -0.628, z))
    tail_spine = smoothstep(0.26, 0.45, z) * (1 - smoothstep(0.99, 1.13, z))
    spine = (nose_spine + tail_spine) * smoothstep(0.078, 0.106, y)
    colour = mix(colour, ELAN_ALLOY, spine * _line(x, 0.0042))
    colour = mix(colour, ELAN_PEARL, spine * _line(x + 0.0008, 0.0014))

    # The sill follows the shell below the glass, behind the nose-frame joint.
    sill_run = smoothstep(-0.354, -0.342, z) * (1 - smoothstep(-0.222, -0.209, z))
    sill_run *= smoothstep(0.068, 0.083, side)
    colour = mix(colour, ELAN_INK, 0.56 * sill_run * _line(y - 0.110, 0.0047))
    colour = mix(colour, ELAN_ALLOY, 0.78 * sill_run * _line(y - 0.1115, 0.00165))
    for station in (-0.336, -0.305, -0.274, -0.243, -0.218):
        pin = np.hypot(z - station, y - 0.110)
        colour = mix(colour, ELAN_INK, sill_run * (1 - smoothstep(0.0016, 0.0027, pin)))
        colour = mix(colour, ELAN_ALLOY, sill_run * (1 - smoothstep(0.0009, 0.0015, pin)))

    # Small index marks sit on the smooth shoulder above the intake lip.
    intake_flank = smoothstep(0.103, 0.122, side)
    for station, ink in ((-0.106, ELAN_AMBER), (-0.091, ELAN_ALLOY), (-0.076, ELAN_ALLOY)):
        mark = elan_chamfer(z - station + 0.55 * (y - 0.095), y - 0.095, 0.004, 0.0015, 0.001)
        colour = mix(colour, ink, 0.77 * intake_flank * (1 - smoothstep(-0.0005, 0.0005, mark)))

    # Service covers and quarter-turn fasteners are kept on the fixed rear shell.
    service, panel_flank, deck, crown = elan_panel_layout(side, y, z)
    colour = mix(colour, ELAN_INK, 0.55 * panel_flank * (1 - smoothstep(-0.002, 0.001, service)))
    colour = mix(colour, ELAN_ALLOY, 0.47 * panel_flank * _line(service, 0.0018))
    brush = 0.25 + 0.038 * np.cos(2 * np.pi * z / 0.0047)
    colour = mix(colour, ELAN_ALLOY, brush * crown * (1 - smoothstep(-0.001, 0.001, deck)))
    colour = mix(colour, ELAN_ALLOY, 0.62 * crown * _line(deck, 0.0016))
    for station in (0.641, 0.721):
        fastener = np.hypot(side - 0.043, z - station)
        colour = mix(colour, ELAN_INK, crown * (1 - smoothstep(0.003, 0.0042, fastener)))
        colour = mix(colour, ELAN_ALLOY, crown * (1 - smoothstep(0.0014, 0.0022, fastener)))
    for station in (0.472, 0.570):
        rivet = np.hypot(z - station, y - 0.082)
        colour = mix(colour, ELAN_ALLOY, 0.84 * panel_flank * (1 - smoothstep(0.0017, 0.0027, rivet)))

    # Dark rails follow the sill below the wing while the silver keel stays readable.
    length = smoothstep(-0.535, -0.374, z) * (1 - smoothstep(0.754, 0.946, z))
    sill = side - (0.035 + 0.025 * smoothstep(-0.357, 0.094, z)
                   - 0.025 * smoothstep(0.53, 0.91, z))
    colour = mix(colour, core, belly * length * _line(sill, 0.027))
    colour = mix(colour, ELAN_DEEP, belly * length * _line(sill + 0.011, 0.0047))
    for station in (-0.748, -0.567):
        locator = _box_distance(side, z - station, 0.025, 0.030, -0.006, 0.006)
        colour = mix(colour, ELAN_DEEP, 0.58 * belly * (1 - smoothstep(-0.001, 0.001, locator)))
    for height, width in ((0.066, 0.042), (0.078, 0.036), (0.090, 0.028)):
        slot = _box_distance(z - 0.52 - 0.29 * (y - 0.078), y, -width / 2, width / 2, height, height + 0.003)
        colour = mix(colour, ELAN_ALLOY, 0.72 * smoothstep(0.066, 0.087, side)
                     * (1 - smoothstep(-0.0006, 0.0006, slot)))

    centre = 0.034 + 0.012 * smoothstep(-0.743, -0.492, z)
    avanti_flank_decal(colour, p, badge, -0.743, -0.492, centre)
    return mix(colour, ELAN_INK, collars)


def elan_roughness(p):
    x, y, z = p.T
    split, belly, collars = elan_shell_masks(y, z)
    rough = mix(0.27, 0.54, smoothstep(-0.002, 0.002, split))[:, 0]
    rough += (0.49 - rough) * belly
    rough += (0.32 - rough) * _line(split, 0.0085) * smoothstep(0.022, 0.061, y)
    service, flank, deck, crown = elan_panel_layout(np.abs(x), y, z)
    rough += (0.58 - rough) * flank * (1 - smoothstep(-0.002, 0.001, service))
    rough += (0.43 - rough) * crown * (1 - smoothstep(-0.001, 0.001, deck))
    rough += (0.56 - rough) * collars
    return np.repeat(rough[:, None], 3, axis=1)


def elan_fin(p, number):
    _, y, z = p.T
    core = elan_twill(y, z)
    cut = z - (1.082 + 0.63 * (y - 0.33))
    colour = mix(ELAN_BLUE, ELAN_DEEP, smoothstep(0.355, 0.52, y))
    colour = mix(colour, ELAN_INK, smoothstep(-0.002, 0.002, cut))
    colour = mix(colour, ELAN_ALLOY, _line(cut + 0.004, 0.0036))
    colour = mix(core, colour, smoothstep(0.239, 0.286, y))
    tab = elan_chamfer(z - 0.971 - 0.60 * (y - 0.283), y - 0.283, 0.020, 0.004, 0.002)
    colour = mix(colour, ELAN_ALLOY, 0.81 * (1 - smoothstep(-0.001, 0.001, tab)))
    # Shear the number with the leading edge. Its two faces have distinct UVs.
    upright = p.copy()
    upright[:, 2] -= 0.70 * (y - 0.351)
    avanti_flank_decal(colour, upright, number, 0.970, 1.047, 0.351)
    return colour


def elan_lifting(atlas, span, z, lower_face):
    if atlas == "stab":
        # Shared UVs on the tailplane and elevator keep these bands spanwise.
        outer = mix(ELAN_CARBON, ELAN_BLUE, smoothstep(0.213, 0.219, span))
        outer = mix(outer, ELAN_ALLOY, _line(span - 0.223, 0.007))
        outer = mix(outer, ELAN_DEEP, 0.72 * _line(span - 0.239, 0.004))
        outer = mix(outer, ELAN_INK, smoothstep(0.420, 0.438, span))
        return np.broadcast_to(outer, (*z.shape[:-1], span.size, 3))

    sweep = span - (0.356 + 0.60 * (z - 0.21) + 0.5 * (z - 0.21) ** 2)
    carbon = elan_twill(span + np.zeros_like(z), z)
    blue = mix(ELAN_DEEP, ELAN_BLUE, smoothstep(0.03, 0.13, span - 0.16 * z))
    upper = mix(blue, carbon, smoothstep(-0.002, 0.002, sweep))
    foil = smoothstep(0.044, 0.090, z) * (1 - smoothstep(0.350, 0.415, z))
    upper = mix(upper, ELAN_ALLOY, _line(sweep + 0.010, 0.005) * foil)
    slot = _box_distance(sweep, z, 0.027, 0.033, 0.188, 0.308)
    upper = mix(upper, ELAN_AMBER, (1 - smoothstep(-0.001, 0.001, slot)) * 0.85)
    cap = span - (0.759 + 0.21 * (z - 0.28))
    upper = mix(upper, ELAN_BLUE, smoothstep(-0.002, 0.002, cap))
    upper = mix(upper, ELAN_ALLOY, _line(cap - 0.007, 0.0048))
    # The fixed tip panel is outboard of the aileron's entire UV range.
    tip_track = span - (0.930 + 0.17 * (z - 0.438))
    insert = elan_chamfer(tip_track, z - 0.438, 0.016, 0.054, 0.007)
    upper = mix(upper, ELAN_INK, 0.82 * (1 - smoothstep(-0.001, 0.001, insert)))
    upper = mix(upper, ELAN_ALLOY, 0.59 * _line(insert, 0.0018))
    accent = _box_distance(tip_track, z, -0.007, -0.003, 0.403, 0.469)
    upper = mix(upper, ELAN_ALLOY, 0.81 * (1 - smoothstep(-0.001, 0.001, accent)))
    amber = _box_distance(tip_track, z, 0.003, 0.007, 0.421, 0.453)
    upper = mix(upper, ELAN_AMBER, 0.86 * (1 - smoothstep(-0.001, 0.001, amber)))

    # The lower stripes clear the main and outboard gear doors and follow the span across the hinges.
    lower = mix(ELAN_CARBON, ELAN_DEEP, smoothstep(0.784, 0.901, span))
    for start, end, finish in ((0.443, 0.541, ELAN_PEARL), (0.694, 0.762, ELAN_ALLOY)):
        band = smoothstep(start - 0.002, start + 0.002, span) * (1 - smoothstep(end - 0.002, end + 0.002, span))
        lower = mix(lower, finish, band)
    # Inspection corner marks frame the main and outboard gear bays.
    for inside, outside, front, rear in ((0.218, 0.427, 0.185, 0.389), (0.594, 0.683, 0.279, 0.385)):
        s = np.minimum(np.abs(span - inside), np.abs(span - outside))
        t = np.minimum(np.abs(z - front), np.abs(z - rear))
        inset_s = smoothstep(inside - 0.001, inside + 0.001, span) * (1 - smoothstep(outside - 0.001, outside + 0.001, span))
        inset_z = smoothstep(front - 0.001, front + 0.001, z) * (1 - smoothstep(rear - 0.001, rear + 0.001, z))
        corners = np.maximum(_line(s, 0.0028) * (1 - smoothstep(0.015, 0.018, t)) * inset_z,
                             _line(t, 0.0028) * (1 - smoothstep(0.015, 0.018, s)) * inset_s)
        lower = mix(lower, ELAN_ALLOY, 0.71 * corners)
    lower = mix(lower, ELAN_BLUE, smoothstep(0.828, 0.928, span))
    colour = mix(upper, lower, lower_face)
    return mix(colour, ELAN_INK, smoothstep(0.968, 0.985, span))


def build_elan(atlas):
    if atlas == "fuselage_roughness":
        return bake_avanti_side("fuselage", (1024, 1024), elan_roughness).convert("L")
    size = ELAN_SIZES[atlas]
    if atlas in ("wing", "stab"):
        return bake_avanti_lifting(atlas, size, elan_lifting)
    if atlas == "fin":
        number = elan_lettering("35", 0.82)
        return bake_avanti_side(atlas, size, lambda p: elan_fin(p, number))
    badge = elan_lettering("ÉLAN", 3.65)
    return bake_avanti_side(atlas, size, lambda p: elan_fuselage(p, badge))


class _Skin:
    """Per-texel material channels of a natural-metal skin, built up layer by layer."""

    def __init__(self, count: int):
        self.colour = np.zeros((count, 3))
        self.rough = np.zeros(count)
        self.metal = np.ones(count)
        self.height = np.zeros(count)  # metres, + out of the surface
        self.paint = np.zeros(count)  # coverage by paint or decal (0..1)
        self.glow = np.zeros((count, 3))  # emission RGB (0..1)

    def panels(self, panel_id, grain_a, grain_b, p, seed, tones=ALU_TONES, roughs=ALU_ROUGH, metals=ALU_METAL):
        tone = np.minimum((_hash(panel_id, seed=seed) * len(tones)).astype(int), len(tones) - 1)
        self.colour = tones[tone] * (0.96 + 0.08 * _hash(panel_id, seed=seed + 3))[:, None]
        self.rough = roughs[tone].copy()
        self.metal = metals[tone].copy()
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

    def lay(self, colour, alpha, rough, metal):
        """A part or material over the skin (brass, glass, iron): colour, roughness and metallic share together."""
        alpha = np.clip(alpha, 0.0, 1.0)
        self.colour = mix(self.colour, colour, alpha)
        self.rough = self.rough + (rough - self.rough) * alpha
        self.metal = self.metal + (metal - self.metal) * alpha

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
        self.colour = mix(self.colour, ALU_TONES[0], 0.5 * mask * self.paint)
        self.metal = np.maximum(self.metal, 0.3 * mask * self.paint)
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
    # Engine-bay and tail-pipe skins are darker, harder alloys and steel than the forward fuselage.
    tail_bay = smoothstep(0.845, 0.86, zn)
    skin.colour = mix(skin.colour, skin.colour * np.array([0.86, 0.85, 0.83]), tail_bay)
    skin.rough = skin.rough + 0.05 * tail_bay
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
    band = (zn > 0.684) & (zn < 0.718)
    skin.paint_over(SABRE_YELLOW, band.astype(float), rough=0.4, chips=chips)
    for edge in (0.684, 0.718):
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

    lettering("U.S. AIR FORCE", 0.192, 0.362, 0.075, 0.105)
    insignia_rgb, insignia_alpha = side_rgba(_sabre_insignia(), 0.765, 0.845, 0.058, 0.152)
    skin.paint_over(insignia_rgb, insignia_alpha, rough=0.42, chips=chips * 0.5)
    lettering("FU-861", 0.855, 0.952, 0.030, 0.078)
    lettering("CAPT. M. ORTEGA", 0.215, 0.300, 0.114, 0.126)
    # Red RESCUE arrow pointing forward to the canopy release on both sides (drawn in scene space so the tip
    # does not flip with the reading direction), white lettering in its shaft.
    rz0, rz1, ry = 0.322 * FUS_LEN, 0.366 * FUS_LEN, 0.1195
    shaft = (zm > rz0 + 0.011) & (zm < rz1) & (np.abs(y - ry) < 0.0042)
    head = (zm >= rz0) & (zm <= rz0 + 0.012) & (np.abs(y - ry) < 0.008 * (zm - rz0) / 0.012)
    skin.paint_over(SABRE_RED, (shaft | head) * side, rough=0.42)
    lettering("RESCUE", 0.331, 0.363, 0.1162, 0.1228, colour=SABRE_WHITE)
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
    skin.grime(oil * belly * 0.4, tint=(0.44, 0.41, 0.36), rough=0.45, metal_loss=0.25)
    skin.colour = skin.colour * (1.0 - 0.07 * smoothstep(np.radians(70), np.radians(170), a))[:, None]
    sill = (zn > 0.165) & (zn < 0.42) & (y > 0.08)
    walk = (zn > 0.42) & (zn < 0.70) & (n[:, 1] > 0.5)
    density = np.where(sill, 0.22, np.where(walk, 0.18, 0.03)) * (glare < 0.5) * (radome < 0.5)
    skin.scratch(0.6 * scratches(zm, arc, 0.018, 1.0, 61) * (_hash(np.floor(zm / 0.018), np.floor(arc / 0.018), seed=63) < density))
    return skin


def sabre_lifting(p, n, frac, span_norm, span_hi, atlas, chord_len, table=None):
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
        skin.paint_over(SABRE_INK, _line(walk, 0.0018) * top * skin_face, rough=0.45, chips=chips)
        cap = np.hypot(s - 0.66, (frac - 0.36) * chord_m)
        skin.colour = mix(skin.colour, hex_rgb("#a7aaad"), (1.0 - smoothstep(0.009, 0.010, cap)) * top)
        skin.groove(np.where(top, cap - 0.0102, 1.0), width=0.0012)
        skin.paint_over(SABRE_RED, _line(cap - 0.013, 0.0028) * top, rough=0.4)
        inside_walk = (walk < 0) & top
        skin.scratch(0.6 * scratches(s, z, 0.016, 1.0, 79) * np.where(inside_walk, 0.35, 0.03))
        # Undersides: duller, with streaks from the gear bays and drains.
        streak = smoothstep(0.55, 0.85, noise3(p, (0.2, 0.006, 0.006), 83)) * (frac > 0.3)
        skin.grime(np.where(top, 0.0, 0.16 * streak), tint=(0.46, 0.44, 0.41), rough=0.45, metal_loss=0.2)
    else:
        # Stabiliser roots sit beside the exhaust: soot on the inboard aft part.
        soot = (1.0 - smoothstep(0.10, 0.22, s)) * smoothstep(0.3, 0.9, frac)
        skin.grime(soot * (0.5 + 0.5 * noise3(p, (0.2, 0.01, 0.01), 89)) * 0.6, tint=(0.25, 0.24, 0.23))
    skin.rough = skin.rough + np.where(top, 0.0, 0.06)
    # Horizontal skins face the sun and read whiter than the fuselage sides: match the overall value.
    skin.colour = skin.colour * 0.93
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

    lettering("U.S. AIR FORCE", 0.932, 1.032, 0.352, 0.364)
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
    return build_metal_skin(atlas, SABRE_ATLASES, sabre_fuselage, sabre_lifting, sabre_fin)


def build_metal_skin(atlas: str, atlases: dict, fuselage, lifting_design, fin, glow: bool = False):
    """Bake one atlas of a scene-space metal skin: albedo, roughness, metallic, normal (and emission)."""
    materials, size = atlases[atlas]
    skin_axis = {"wing": 1, "stab": 1, "doors": 1, "fin": 0}.get(atlas, -1)
    pos, nrm, _mat, covered = bake_scene(JET_GLB, materials, size, symmetric=atlas in ("wing", "stab", "doors"),
                                         skin_axis=skin_axis)
    p, n = pos[covered], nrm[covered]
    if atlas == "fuselage":
        design = fuselage
    elif atlas in ("wing", "stab", "doors"):
        span_hi = 0.443 if atlas == "stab" else 0.998
        lifting = ("paint_stab",) if atlas == "stab" else ("paint_wing",)
        table = chord_table(JET_GLB, lifting, 0, 28 if atlas == "stab" else 48, -span_hi, span_hi)
        if atlas == "doors":
            n = n.copy()
            n[:, 1] = -np.maximum(np.abs(n[:, 1]), 0.7)
        design = lambda pc, nc: lifting_design(pc, nc, chord_fraction(pc, 0, table, -span_hi, span_hi),
                                               np.abs(pc[:, 0]) / span_hi, span_hi, atlas,
                                               chord_length(pc, 0, table, -span_hi, span_hi), table)
    else:
        table = chord_table(JET_GLB, ("paint_fin",), 1, 20, 0.212, 0.577)
        design = lambda pc, nc: fin(pc, nc, chord_fraction(pc, 1, table, 0.212, 0.577),
                                    (pc[:, 1] - 0.212) / (0.577 - 0.212))
    # Every layer is per texel, so chunks give identical bytes with a bounded memory peak.
    parts = [design(p[k:k + 1_000_000], n[k:k + 1_000_000]) for k in range(0, len(p), 1_000_000)]
    skin = _Skin(0)
    skin.colour = np.concatenate([part.colour for part in parts])
    skin.rough = np.concatenate([part.rough for part in parts])
    skin.metal = np.concatenate([part.metal for part in parts])
    skin.height = np.concatenate([part.height for part in parts])
    skin.glow = np.concatenate([part.glow for part in parts])
    del parts
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
    maps = (to_image(colour), to_image(rough).convert("L"), to_image(metal).convert("L"), to_image(normal))
    return maps + (to_image(full(np.clip(skin.glow, 0, 1), 3)),) if glow else maps


_SABRE_CACHE: dict = {}


def _sabre_cached(atlas: str):
    if atlas not in _SABRE_CACHE:
        _SABRE_CACHE[atlas] = build_sabre(atlas)
    return _SABRE_CACHE[atlas]


# ---------------------------------------------------------------------------------------------
# Sebart Avanti S jet: "Steampunk Cobre". An original Victorian steam-age airframe fitted to the jet's own lines:
# riveted copper and blackened-iron plates, brass hoops at the fuselage frames, copper steam pipes with brass
# couplings, a working-looking gear train driven by a piston and connecting rod, pressure gauges, portholes, a
# glowing firebox grille, a brass clock on the fin, verdigris in the seams and heat-blued tail steel. Same maps
# as Sabre Plata plus an emission map (firebox embers, porthole and dial glow). Gear teeth share one circular
# pitch, so meshing wheels really mesh.
# ---------------------------------------------------------------------------------------------
STEAM_ATLASES = dict(SABRE_ATLASES)
STEAM_FONT = ROOT / "tools/skins/sources/steampunk/IMFeENsc28P.ttf"  # SIL OFL 1.1 (see that folder's README.md)
# Bright, rosy, aged and dark-brown copper: plates of different age and polish.
COPPER_TONES = np.array([(206, 124, 82), (178, 101, 63), (152, 86, 57), (222, 152, 112), (190, 112, 72),
                         (164, 94, 62), (146, 84, 56)], dtype=np.float64) / 255.0
COPPER_ROUGH = np.array([0.26, 0.36, 0.46, 0.22, 0.32, 0.40, 0.50])
COPPER_METAL = np.array([0.64, 0.56, 0.48, 0.68, 0.60, 0.54, 0.46])
IRON_TONES = np.array([(80, 82, 84), (67, 68, 70), (92, 89, 83), (73, 75, 79), (86, 83, 80)], dtype=np.float64) / 255.0
IRON_ROUGH = np.array([0.42, 0.50, 0.38, 0.46, 0.44])
IRON_METAL = np.array([0.56, 0.50, 0.60, 0.52, 0.55])
BRASS_BRIGHT = hex_rgb("#e3c26c")
BRASS_DARK = hex_rgb("#93722f")
VERDIGRIS = hex_rgb("#5b9c86")
CREAM = hex_rgb("#efe4c7")
STEEL = hex_rgb("#a3a8ad")
ENGRAVE = hex_rgb("#2b2117")
EMBER = np.array([1.0, 0.42, 0.08])
GEAR_PITCH = 0.0126  # circular pitch shared by every gear (metres per tooth)
STEAM_HOOPS = [0.064, 0.300, 0.470, 0.700, 0.860]


def _engraved(text: str, aspect: float) -> np.ndarray:
    return _sabre_text(text, aspect, 1, font=STEAM_FONT, stroke=1)


def _view(p, n, ca, cb):
    """Side coordinates (metres) as a viewer sees them on either side: +a towards the nose, +b up."""
    a = np.where(n[:, 0] >= 0.0, ca - p[:, 2], p[:, 2] - ca)
    return a, p[:, 1] - cb


def gear(a, b, ca, cb, teeth: int, phase: float, spokes: int = 6):
    """Spur gear relief in surface coordinates: solid metal, see-through windows, axle cap, distance, pitch radius."""
    radius = teeth * GEAR_PITCH / (2.0 * np.pi)
    da, db = a - ca, b - cb
    d = np.hypot(da, db)
    th = np.arctan2(db, da)
    tooth = smoothstep(-0.35, 0.35, np.cos(teeth * th + phase))
    outer = radius + 0.0044 * (tooth - 0.5)
    body = 1.0 - smoothstep(-0.0004, 0.0004, d - outer)
    rim = radius - 0.0022 - 0.16 * radius
    hub = 0.30 * radius
    k = 2.0 * np.pi / spokes
    spoke_gap = d * np.abs(np.sin(np.mod(th - phase / teeth + k * 0.5, k) - k * 0.5))
    window = body * (1.0 - smoothstep(rim - 0.0008, rim, d)) * smoothstep(hub, hub + 0.0008, d) \
        * smoothstep(0.09 * radius, 0.09 * radius + 0.0008, spoke_gap)
    solid = np.clip(body - window, 0.0, 1.0)
    axle = 1.0 - smoothstep(0.08 * radius, 0.08 * radius + 0.0006, d)
    return solid, window, axle, d, radius


def mesh_phase(teeth_a: int, phase_a: float, angle: float, teeth_b: int) -> float:
    """Phase of gear b, centred at `angle` from gear a, so a's tooth phase at the contact meets a gap of b."""
    return np.pi - (teeth_a * angle + phase_a) - teeth_b * (angle + np.pi)


def steam_gear(skin, p, a, b, ca, cb, teeth, phase, weight, seed):
    solid, window, axle, d, radius = gear(a, b, ca, cb, teeth, phase)
    solid, window, axle = solid * weight, window * weight, axle * weight
    tarnish = smoothstep(0.35, 0.8, fbm(p, 0.02, seed))
    brass = mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.7)
    tips = smoothstep(radius - 0.001, radius + 0.002, d)
    skin.lay(mix(brass, BRASS_BRIGHT * 1.05, tips * 0.6), solid, rough=0.22 + 0.1 * tarnish, metal=0.66)
    skin.lay(hex_rgb("#1d1b19"), window, rough=0.8, metal=0.1)
    skin.lay(STEEL, axle, rough=0.25, metal=0.62)
    edge = solid * (1.0 - smoothstep(0.0, 0.0012, np.abs(d - (radius - 0.0022 - 0.16 * radius))))
    skin.height += 0.0009 * solid - 0.0007 * window + 0.0005 * axle - 0.0002 * edge


def steam_pipe(skin, p, d, t, t0, t1, radius, weight, colour, seed, coupling_pitch=0.09):
    """A pipe along t (metres) at signed distance d from its centre line, with brass couplings and bolts."""
    along = (t > t0) & (t < t1)
    phase = np.mod(t - t0, coupling_pitch) - coupling_pitch * 0.5
    coupling = (np.abs(phase) < 0.004) & along
    r = np.where(coupling, radius * 1.35, radius)
    section = np.sqrt(np.clip(1.0 - (d / r) ** 2, 0.0, 1.0))
    mask = (1.0 - smoothstep(r * 0.9, r, np.abs(d))) * along * weight
    polish = smoothstep(0.3, 0.9, noise3(p, (0.004, 0.004, 0.15), seed))
    body = mix(np.broadcast_to(colour, (len(p), 3)), colour * 1.18, polish * 0.5)
    body = np.where(coupling[:, None], mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, 0.25), body)
    shade = 0.55 + 0.45 * section  # contact shadow where the pipe meets the skin
    skin.lay(body * shade[:, None], mask, rough=np.where(coupling, 0.22, 0.30), metal=0.64)
    bolt = (1.0 - smoothstep(0.0007, 0.0011, np.hypot(phase, np.abs(d) - r * 0.55))) * coupling * weight
    skin.lay(STEEL * 0.8, bolt, rough=0.35, metal=0.6)
    skin.height += 0.75 * r * section * mask + 0.0003 * bolt


def steam_dial(skin, p, a, b, ca, cb, r, reading, weight, seed):
    """Pressure gauge: brass bezel with screws, cream dial, ticks, red zone, needle and glass glint."""
    da, db = a - ca, b - cb
    d = np.hypot(da, db)
    psi = np.arctan2(da, db)  # 0 = up, + towards the viewer's right
    face = (1.0 - smoothstep(r - 0.0005, r, d)) * weight
    bezel = smoothstep(r - 0.0004, r, d) * (1.0 - smoothstep(r * 1.3 - 0.0005, r * 1.3, d)) * weight
    tarnish = smoothstep(0.3, 0.8, fbm(p, 0.01, seed))
    skin.lay(mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.6), bezel, rough=0.22, metal=0.66)
    skin.height += 0.0010 * bezel - 0.0004 * face
    for k in range(6):
        ang = k * np.pi / 3.0 + 0.3
        screw = 1.0 - smoothstep(0.0005, 0.0008, np.hypot(da - np.sin(ang) * r * 1.15, db - np.cos(ang) * r * 1.15))
        skin.lay(STEEL * 0.75, screw * weight, rough=0.35, metal=0.6)
    skin.lay(CREAM, face, rough=0.35, metal=0.0)
    step = np.radians(27.0)
    nearest = np.clip(np.round(psi / step), -5, 5) * step
    tick = (np.abs(psi) < np.radians(137)) * (d > r * 0.68) * (d < r * 0.9) \
        * (1.0 - smoothstep(0.0003, 0.0005, d * np.abs(np.sin(psi - nearest))))
    red = (psi > np.radians(80)) * (psi < np.radians(135)) * (d > r * 0.78) * (d < r * 0.9)
    skin.lay(hex_rgb("#a82b22"), red * face, rough=0.4, metal=0.0)
    skin.lay(ENGRAVE, tick * face, rough=0.4, metal=0.0)
    needle_angle = np.radians(-135.0 + 270.0 * reading)
    ux, uy = np.sin(needle_angle), np.cos(needle_angle)
    along = np.clip(da * ux + db * uy, -0.15 * r, 0.85 * r)
    needle = 1.0 - smoothstep(0.00025, 0.00045, np.hypot(da - along * ux, db - along * uy))
    skin.lay(hex_rgb("#141210"), needle * face, rough=0.4, metal=0.0)
    cap = (1.0 - smoothstep(r * 0.1, r * 0.1 + 0.0004, d)) * weight
    skin.lay(BRASS_BRIGHT, cap, rough=0.2, metal=0.66)
    skin.glow = skin.glow + (EMBER * 0.12)[None, :] * (face * (1.0 - tick) * (1.0 - needle))[:, None]
    glint = face * smoothstep(0.55, 0.8, (-da + db) / max(r, 1e-6)) * (d > r * 0.55)
    skin.colour = mix(skin.colour, np.minimum(skin.colour + 0.18, 1.0), glint * 0.5)
    skin.rough = skin.rough - 0.25 * glint


def steam_plaque(skin, p, a, b, ca, cb, width, height, text, weight, seed):
    """Brass name plate with a raised border, corner screws and engraved lettering."""
    da, db = a - ca, b - cb
    box = np.maximum(np.abs(da) - width * 0.5, np.abs(db) - height * 0.5)
    plate = (1.0 - smoothstep(-0.0004, 0.0, box)) * weight
    tarnish = smoothstep(0.35, 0.8, fbm(p, 0.015, seed))
    skin.lay(mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.5), plate, rough=0.24, metal=0.66)
    border = plate * (1.0 - smoothstep(0.0004, 0.0008, np.abs(box + 0.0022)))
    skin.lay(ENGRAVE, border, rough=0.5, metal=0.1)
    u = (da + width * 0.5 - 0.004) / (width - 0.008)
    v = (height * 0.5 - 0.0035 - db) / (height - 0.007)
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    mask = _engraved(text, (width - 0.008) / (height - 0.007))
    ink = np.where(inside, _bilinear(mask, u, v), 0.0) * plate
    skin.lay(ENGRAVE, ink, rough=0.55, metal=0.1)
    for sa in (-1, 1):
        for sb in (-1, 1):
            screw = 1.0 - smoothstep(0.0006, 0.0009, np.hypot(da - sa * (width * 0.5 - 0.0025), db - sb * (height * 0.5 - 0.0022)))
            skin.lay(STEEL * 0.8, screw * plate, rough=0.35, metal=0.6)
            skin.height += 0.0002 * screw * plate
    skin.height += 0.0005 * plate - 0.0002 * ink - 0.0002 * border


def steam_porthole(skin, p, a, b, ca, cb, r, weight):
    da, db = a - ca, b - cb
    d = np.hypot(da, db)
    glass = (1.0 - smoothstep(r - 0.0005, r, d)) * weight
    ring = smoothstep(r - 0.0004, r, d) * (1.0 - smoothstep(r * 1.32 - 0.0005, r * 1.32, d)) * weight
    skin.lay(mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, 0.3), ring, rough=0.22, metal=0.66)
    th = np.arctan2(db, da)
    rivet = (1.0 - smoothstep(0.0008, 0.0012, d * np.abs(np.sin(np.mod(th, np.pi / 4) - np.pi / 8)) +
                              np.abs(d - r * 1.16))) * ring
    skin.lay(BRASS_BRIGHT * 1.05, rivet, rough=0.2, metal=0.66)
    skin.lay(hex_rgb("#101619"), glass, rough=0.05, metal=0.0)
    glint = glass * smoothstep(0.45, 0.8, (-da + db) / r) * (d > r * 0.5)
    skin.colour = mix(skin.colour, hex_rgb("#7f9aa3"), glint * 0.6)
    skin.glow = skin.glow + (EMBER * 0.35)[None, :] * (glass * (1.0 - smoothstep(0.0, r, d)) * (1.0 - glint))[:, None]
    skin.height += 0.0011 * ring + 0.0003 * rivet - 0.0006 * glass


def hammered(a, b, cell, seed):
    """Distance to the nearest hammer blow (cellular noise in surface metres), normalised by the cell size."""
    ia, ib = np.floor(a / cell), np.floor(b / cell)
    best = np.full(np.shape(a), np.inf)
    for oa in (-1, 0, 1):
        for ob in (-1, 0, 1):
            ca, cb = ia + oa, ib + ob
            pa = (ca + 0.15 + 0.7 * _hash(ca, cb, seed=seed)) * cell
            pb = (cb + 0.15 + 0.7 * _hash(ca, cb, seed=seed + 1)) * cell
            best = np.minimum(best, np.hypot(a - pa, b - pb))
    return best / cell


def steam_plates(skin, p, panel, grain_a, grain_b, copper_weight, seed):
    """Copper and blackened-iron plates: both palettes per panel, blended by zone; half the copper is planished."""
    skin.panels(panel, grain_a, grain_b, p, seed, COPPER_TONES, COPPER_ROUGH, COPPER_METAL)
    blow = hammered(grain_a, grain_b, 0.009, seed + 9)
    dent = 1.0 - np.clip(blow / 0.75, 0.0, 1.0) ** 2
    planished = copper_weight * (_hash(panel, seed=seed + 8) < 0.5)
    skin.height -= 0.00016 * dent * planished
    skin.colour = skin.colour * (1.0 - 0.05 * dent * planished)[:, None]
    iron = _Skin(len(p))
    iron.panels(panel, grain_a, grain_b, p, seed + 1, IRON_TONES, IRON_ROUGH, IRON_METAL)
    skin.lay(iron.colour, 1.0 - copper_weight, rough=iron.rough, metal=iron.metal)


def steam_patina(skin, p, crevice, copper_weight, seed):
    """Verdigris collects in copper seams and round rivet heads; soot-dark rust on iron."""
    noise = smoothstep(0.4, 0.75, fbm(p, 0.012, seed))
    green = np.clip(crevice * noise * copper_weight * 0.75, 0.0, 1.0)
    skin.lay(VERDIGRIS * (0.85 + 0.3 * fbm(p, 0.004, seed + 1))[:, None], green, rough=0.75, metal=0.08)
    rust = np.clip(crevice * noise * (1.0 - copper_weight) * 0.5, 0.0, 1.0)
    skin.lay(hex_rgb("#5a3a26"), rust, rough=0.8, metal=0.1)


def domed_rivets(skin, mask, colour_gain=1.12):
    skin.colour = np.minimum(skin.colour * (1.0 + (colour_gain - 1.0) * mask)[:, None], 1.0)
    skin.rough = skin.rough - 0.06 * mask
    skin.height += 0.00028 * mask


def steam_fuselage(p, n):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    zn = (z - FUS_NOSE) / FUS_LEN
    zm = zn * FUS_LEN
    dy = y - _fuselage_centre(zn)
    r = np.hypot(x, dy)
    phi = np.arctan2(x, dy)
    a = np.abs(phi)
    arc = r * phi
    side = smoothstep(0.45, 0.65, np.abs(n[:, 0]))
    skin = _Skin(len(p))
    d_station, k_station, f_station = _nearest(zn, FUS_STATIONS)
    d_seam, k_seam, _ = _nearest(a, FUS_SEAMS)
    k_seam = np.where(k_seam == 0, 0, k_seam + 10 * (x < 0))
    panel = k_station * 64 + k_seam
    copper = 1.0 - smoothstep(0.299, 0.301, zn) * (1.0 - smoothstep(0.699, 0.701, zn))
    steam_plates(skin, p, panel, zm, arc, copper, seed=401)
    across = np.where(a < FUS_SEAMS[0], (phi + FUS_SEAMS[0]) / (2 * FUS_SEAMS[0]), _nearest(a, FUS_SEAMS)[2])
    skin.height += 0.0003 * np.sin(np.pi * f_station) * np.sin(np.pi * np.clip(across, 0, 1)) \
        * np.where(_hash(panel, seed=13) < 0.5, -1.0, 1.0)
    # Lap joints and big domed boiler rivets.
    skin.groove(d_station * FUS_LEN, width=0.0012, depth=0.0003, wash=0.08)
    skin.groove(d_seam * r, width=0.0012, depth=0.0003, wash=0.08)
    rivet = rivets(d_station * FUS_LEN, arc, (-0.0045, 0.0045), 0.010, radius=0.0012)
    rivet = np.maximum(rivet, rivets(d_seam * r, zm, (-0.0045, 0.0045), 0.010, radius=0.0012))
    domed_rivets(skin, rivet * (zn > 0.07))
    crevice = np.maximum(1.0 - smoothstep(0.0, 0.004, np.minimum(np.abs(d_station * FUS_LEN), np.abs(d_seam * r))),
                         rivets(d_station * FUS_LEN, arc, (-0.0045, 0.0045), 0.010, radius=0.0019) - rivet)
    steam_patina(skin, p, crevice, copper, seed=409)

    # Brass nose cone with engraved rings.
    cone = 1.0 - smoothstep(0.0615, 0.0625, zn)
    tarnish = smoothstep(0.3, 0.8, fbm(p, 0.02, 411))
    skin.lay(mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.5), cone, rough=0.18, metal=0.68)
    for ring in (0.016, 0.031, 0.046):
        skin.groove(np.where(cone > 0.5, (zn - ring) * FUS_LEN, 1.0), width=0.0009, depth=0.0002, wash=0.03)

    # Heat-blued tail steel behind the last hoop.
    tail = smoothstep(0.859, 0.861, zn)
    temper = np.interp(zn, [0.86, 0.92, 0.97, 1.0], [0.0, 0.35, 0.7, 1.0])
    heat = np.stack([np.interp(temper, [0, 0.35, 0.7, 1], c) for c in
                     ([0.55, 0.62, 0.40, 0.30], [0.50, 0.48, 0.34, 0.36], [0.46, 0.30, 0.30, 0.52])], axis=1)
    skin.lay(heat * (0.9 + 0.2 * fbm(p, 0.03, 413))[:, None], tail, rough=0.32, metal=0.62)

    # Brass hoops at the frames, raised, with a domed rivet row along both edges.
    for hoop in STEAM_HOOPS:
        dist = np.abs(zn - hoop) * FUS_LEN
        band = 1.0 - smoothstep(0.0095, 0.0105, dist)
        skin.lay(mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.6), band, rough=0.22, metal=0.66)
        skin.height += 0.0007 * band * smoothstep(0.0105, 0.008, dist)
        domed_rivets(skin, rivets((zn - hoop) * FUS_LEN, arc, (-0.0065, 0.0065), 0.011, radius=0.0011) * band, 1.15)
    # Dorsal brass spine strap from the wing to the tail.
    strap = (np.abs(x) < 0.012) * (n[:, 1] > 0.7) * (zn > 0.47) * (zn < 0.86)
    skin.lay(mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.6), strap, rough=0.22, metal=0.66)
    domed_rivets(skin, rivets(np.abs(x) - 0.012, zm, (-0.004,), 0.011, radius=0.0011) * strap)
    skin.height += 0.0005 * strap

    # Steam pipes along both flanks, the gear train, piston and connecting rod.
    steam_pipe(skin, p, y - 0.150, zm, 0.31 * FUS_LEN, 0.855 * FUS_LEN, 0.006, side, hex_rgb("#c27a4c"), 421)
    steam_pipe(skin, p, y - 0.180, zm, 0.48 * FUS_LEN, 0.69 * FUS_LEN, 0.0035, side, BRASS_BRIGHT * 0.95, 423, 0.07)
    big = (0.585 * FUS_LEN, 0.095)
    teeth = (20, 11, 8)
    phase_big = 0.0
    small_angle, tiny_angle = np.radians(15.0), np.radians(-35.0)
    radius = [t * GEAR_PITCH / (2 * np.pi) for t in teeth]
    small = (big[0] + (radius[0] + radius[1]) * np.cos(small_angle), big[1] + (radius[0] + radius[1]) * np.sin(small_angle))
    tiny = (big[0] + (radius[0] + radius[2]) * np.cos(tiny_angle), big[1] + (radius[0] + radius[2]) * np.sin(tiny_angle))
    steam_gear(skin, p, zm, y, big[0], big[1], teeth[0], phase_big, side, 431)
    steam_gear(skin, p, zm, y, small[0], small[1], teeth[1], mesh_phase(teeth[0], phase_big, small_angle, teeth[1]), side, 433)
    steam_gear(skin, p, zm, y, tiny[0], tiny[1], teeth[2], mesh_phase(teeth[0], phase_big, tiny_angle, teeth[2]), side, 435)
    # Piston: a finned cylinder whose rod and crosshead drive a crank pin on the big wheel.
    cyl0, cyl1, cyl_y = 0.490 * FUS_LEN, 0.535 * FUS_LEN, 0.104
    cyl = ((zm > cyl0) & (zm < cyl1) & (np.abs(y - cyl_y) < 0.0145)) * side
    fins = 0.5 + 0.5 * np.cos((zm - cyl0) / 0.004 * 2 * np.pi)
    skin.lay(IRON_TONES[1] * (0.8 + 0.4 * fins)[:, None], cyl, rough=0.45, metal=0.55)
    skin.height += (0.0010 + 0.0005 * fins) * cyl
    for flange in (cyl0, cyl1):
        ring = (np.abs(zm - flange) < 0.003) * (np.abs(y - cyl_y) < 0.0175) * side
        skin.lay(BRASS_BRIGHT, ring, rough=0.22, metal=0.66)
        skin.height += 0.0016 * ring
    crank = (big[0] - 0.026 * np.cos(np.radians(30)), big[1] + 0.026 * np.sin(np.radians(30)))
    cross = (cyl1 + 0.012, cyl_y)
    rod = ((zm > cyl1) & (zm < cross[0]) & (np.abs(y - cyl_y) < 0.003)) * side
    skin.lay(STEEL * 1.1, rod, rough=0.15, metal=0.66)
    skin.height += 0.0012 * rod
    head = ((np.abs(zm - cross[0]) < 0.0055) & (np.abs(y - cyl_y) < 0.0065)) * side
    skin.lay(BRASS_DARK, head, rough=0.3, metal=0.62)
    skin.height += 0.0018 * head
    ux, uy = crank[0] - cross[0], crank[1] - cross[1]
    length = np.hypot(ux, uy)
    t = np.clip(((zm - cross[0]) * ux + (y - cross[1]) * uy) / length, 0.0, length)
    con = (1.0 - smoothstep(0.0036, 0.0042, np.hypot(zm - cross[0] - t * ux / length, y - cross[1] - t * uy / length))) * side
    skin.lay(STEEL * 0.95, con, rough=0.22, metal=0.64)
    skin.height += 0.0022 * con
    pin = (1.0 - smoothstep(0.0028, 0.0034, np.hypot(zm - crank[0], y - crank[1]))) * side
    skin.lay(STEEL, pin, rough=0.2, metal=0.64)
    skin.height += 0.0026 * pin

    # The steam circuit: a riser from the firebox to the steam main, and a feed with a handwheel valve down to
    # the cylinder, so the drawn machine reads as one working engine.
    steam_pipe(skin, p, zm - 0.872 * FUS_LEN, y, 0.074, 0.150, 0.0045, side, hex_rgb("#c27a4c"), 425, 0.05)
    feed_z = 0.512 * FUS_LEN
    steam_pipe(skin, p, zm - feed_z, y, cyl_y + 0.016, 0.150, 0.0035, side, BRASS_BRIGHT * 0.95, 427, 0.04)
    wheel_a, wheel_b = feed_z, 0.134
    wd = np.hypot(zm - wheel_a, y - wheel_b)
    wth = np.arctan2(y - wheel_b, zm - wheel_a)
    rim = (np.abs(wd - 0.0072) < 0.0012) * side
    spokes = (wd < 0.0072) * (wd * np.abs(np.sin(np.mod(wth, np.pi / 2) - np.pi / 4 + np.pi / 4)) < 0.0007) * side
    hub = (wd < 0.0018) * side
    skin.lay(hex_rgb("#8e2a22"), np.clip(rim + spokes, 0, 1), rough=0.4, metal=0.2)
    skin.lay(BRASS_BRIGHT, hub, rough=0.2, metal=0.66)
    skin.height += 0.0014 * np.clip(rim + spokes, 0, 1) + 0.0018 * hub
    # Cockpit instruments, name plate, portholes and the firebox.
    va, vb = _view(p, n, 0.0, 0.0)
    for zc, reading in ((0.226, 0.62), (0.264, 0.84)):
        ca = np.where(n[:, 0] >= 0.0, -(FUS_NOSE + zc * FUS_LEN), FUS_NOSE + zc * FUS_LEN)
        steam_dial(skin, p, va, vb, ca, 0.112, 0.0085, reading, side, 441)
    plaque_z = FUS_NOSE + 0.225 * FUS_LEN
    pa, pb = _view(p, n, plaque_z, 0.085)
    steam_plaque(skin, p, pa, pb, 0.0, 0.0, 0.25, 0.026, "AETHER-JET  No. VII", side, 443)
    for zc in (0.752, 0.806):
        steam_porthole(skin, p, zm, y, zc * FUS_LEN, 0.122, 0.013, side)
    fz0, fz1, fy0, fy1 = 0.885 * FUS_LEN, 0.935 * FUS_LEN, 0.034, 0.076
    frame = _box_distance(zm, y, fz0, fz1, fy0, fy1)
    inside = (frame < -0.003) * side
    border = (frame < 0.0) * (frame >= -0.003) * side
    skin.lay(BRASS_DARK, border, rough=0.28, metal=0.64)
    slots = (np.abs(np.mod(zm - fz0, 0.0085) - 0.00425) < 0.0024) * inside
    skin.lay(IRON_TONES[1] * 0.5, inside * (1.0 - slots), rough=0.5, metal=0.5)
    ember = (0.55 + 0.45 * (1.0 - (y - fy0) / (fy1 - fy0))) * (0.75 + 0.5 * noise3(p, 0.004, 447))
    skin.lay(np.array([0.55, 0.16, 0.04]), slots, rough=0.6, metal=0.0)
    skin.glow = skin.glow + EMBER[None, :] * (slots * np.clip(ember, 0, 1.2))[:, None]
    skin.height += 0.0006 * border - 0.0008 * slots
    above = np.clip((y - fy1) / 0.05, 0.0, 1.0)
    soot = (y > fy1) * (zm > fz0 - 0.005) * np.exp(-above * 3.0) * (1.0 - smoothstep(fz1, fz1 + 0.08, zm)) * side
    skin.grime(soot * 0.7 * (0.6 + 0.4 * noise3(p, (0.02, 0.004, 0.02), 449)), tint=(0.25, 0.24, 0.23), rough=0.6)
    exhaust = smoothstep(0.92, 1.0, zn) * (1.0 - smoothstep(0.05, 0.17, y))
    skin.grime(exhaust * (0.5 + 0.5 * noise3(p, (0.006, 0.006, 0.12), 451)) * 0.7, tint=(0.24, 0.23, 0.22), rough=0.55)
    return skin


def steam_lifting(p, n, frac, span_norm, span_hi, atlas, chord_len, table=None):
    s, z = span_norm * span_hi, p[:, 2]
    top = n[:, 1] >= 0.0
    face = smoothstep(0.3, 0.6, np.abs(n[:, 1]))
    chord_m = chord_len
    joints = [0.14, 0.42, 0.70] if atlas != "stab" else [0.17, 0.32]
    spars = [0.14, 0.63] if atlas != "stab" else [0.16, 0.62]
    d_joint, k_joint, f_joint = _nearest(s, joints)
    d_spar, k_spar, f_spar = _nearest(frac, spars)
    panel = k_joint * 16 + k_spar * 2 + top
    skin = _Skin(len(p))
    copper = top.astype(float)
    steam_plates(skin, p, panel, s, z, copper, seed=461 if atlas != "stab" else 467)
    skin.height += 0.0003 * np.sin(np.pi * f_joint) * np.sin(np.pi * f_spar) * np.where(_hash(panel, seed=17) < 0.5, -1, 1)
    skin.groove(np.where(face > 0.5, d_joint, 1.0), width=0.0012, depth=0.0003, wash=0.08)
    skin.groove(np.where(face > 0.5, d_spar * chord_m, 1.0), width=0.0012, depth=0.0003, wash=0.08)
    rivet = rivets(d_joint, z, (-0.0045, 0.0045), 0.010, radius=0.0012)
    rivet = np.maximum(rivet, rivets(d_spar * chord_m, s, (-0.0045, 0.0045), 0.010, radius=0.0012))
    domed_rivets(skin, rivet * face)
    crevice = 1.0 - smoothstep(0.0, 0.004, np.minimum(np.abs(d_joint), np.abs(d_spar * chord_m)))
    steam_patina(skin, p, crevice, copper, seed=471)
    tarnish = smoothstep(0.3, 0.8, fbm(p, 0.02, 473))
    brass = mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.6)
    # Polished brass leading edge with its rivet row, brass tips.
    edge = 1.0 - smoothstep(0.062, 0.068, frac)
    skin.lay(brass, edge, rough=0.18, metal=0.68)
    domed_rivets(skin, rivets((frac - 0.078) * chord_m, s, (0.0,), 0.010, radius=0.0011) * face)
    tip = smoothstep(0.95, 0.955, span_norm)
    skin.lay(brass, tip, rough=0.2, metal=0.66)
    if atlas != "stab":
        b0, b1 = 0.76 * span_hi, 0.79 * span_hi
        band = ((s > b0) & (s < b1)).astype(float)
        skin.lay(brass, band, rough=0.22, metal=0.66)
        skin.height += 0.0006 * band
        for edge_s in (b0 + 0.0055, b1 - 0.0055):
            domed_rivets(skin, rivets(s - edge_s, z, (0.0,), 0.011, radius=0.0011) * band, 1.15)
    if atlas == "wing":
        steam_pipe(skin, p, (frac - 0.33) * chord_m, s, 0.14, 0.70, 0.0045, top * face, hex_rgb("#c27a4c"), 475)
        le, te = table
        centres = -span_hi + (np.arange(len(le)) + 0.5) * (2.0 * span_hi) / len(le)

        def at(s0, f0):
            l0, t0 = np.interp(s0, centres, le), np.interp(s0, centres, te)
            return s0, l0 + f0 * (t0 - l0)

        big = at(0.43, 0.50)
        teeth = (21, 12)
        r0, r1 = (t * GEAR_PITCH / (2 * np.pi) for t in teeth)
        angle = np.radians(-15.0)
        small = (big[0] + (r0 + r1) * np.cos(angle), big[1] + (r0 + r1) * np.sin(angle))
        steam_gear(skin, p, s, z, big[0], big[1], teeth[0], 0.0, top * face, 477)
        steam_gear(skin, p, s, z, small[0], small[1], teeth[1], mesh_phase(teeth[0], 0.0, angle, teeth[1]), top * face, 479)
        streak = smoothstep(0.55, 0.85, noise3(p, (0.2, 0.006, 0.006), 481)) * (frac > 0.3)
        skin.grime(np.where(top, 0.0, 0.25 * streak), tint=(0.36, 0.33, 0.29), rough=0.55, metal_loss=0.3)
    else:
        soot = (1.0 - smoothstep(0.10, 0.22, s)) * smoothstep(0.3, 0.9, frac)
        skin.grime(soot * (0.5 + 0.5 * noise3(p, (0.2, 0.01, 0.01), 483)) * 0.6, tint=(0.25, 0.24, 0.23))
    skin.colour = mix(IRON_TONES[1] * 0.8, skin.colour, face)
    return skin


def steam_fin(p, n, frac, height_norm):
    y, z = p[:, 1], p[:, 2]
    chord_m = 0.36
    skin = _Skin(len(p))
    joints = [0.212 + 0.365 * h for h in (0.30, 0.62)]
    d_joint, k_joint, f_joint = _nearest(y, joints)
    d_spar, k_spar, f_spar = _nearest(frac, [0.12, 0.62])
    panel = k_joint * 8 + k_spar
    copper = smoothstep(0.615, 0.625, frac)  # copper rudder on an iron fin
    steam_plates(skin, p, panel, y, z, copper, seed=491)
    side = smoothstep(0.35, 0.6, np.abs(n[:, 0]))
    skin.groove(np.where(side > 0.5, d_joint, 1.0), width=0.0012, depth=0.0003, wash=0.08)
    skin.groove(np.where(side > 0.5, d_spar * chord_m, 1.0), width=0.0012, depth=0.0003, wash=0.08)
    rivet = rivets(d_joint, z, (-0.0045, 0.0045), 0.010, radius=0.0012)
    rivet = np.maximum(rivet, rivets(d_spar * chord_m, y, (-0.0045, 0.0045), 0.010, radius=0.0012))
    domed_rivets(skin, rivet * side)
    crevice = 1.0 - smoothstep(0.0, 0.004, np.minimum(np.abs(d_joint), np.abs(d_spar * chord_m)))
    steam_patina(skin, p, crevice, copper, seed=493)
    tarnish = smoothstep(0.3, 0.8, fbm(p, 0.02, 495))
    brass = mix(np.broadcast_to(BRASS_BRIGHT, (len(p), 3)), BRASS_DARK, tarnish * 0.6)
    skin.lay(brass, 1.0 - smoothstep(0.075, 0.082, frac), rough=0.18, metal=0.68)
    cap = smoothstep(0.875, 0.885, height_norm)
    skin.lay(brass, cap, rough=0.2, metal=0.66)
    domed_rivets(skin, rivets((height_norm - 0.895) * 0.365, z, (0.0,), 0.010, radius=0.0011) * side, 1.15)
    # The fin clock: a gear wheel behind a brass-bezelled dial with Roman numerals, hands at ten past ten.
    zc, yc = 0.990, 0.348
    va, vb = _view(p, n, zc, yc)
    steam_gear(skin, p, va, vb, 0.0, 0.0, 19, 0.2, side, 497)
    rc = 0.031
    d = np.hypot(va, vb)
    psi = np.arctan2(va, vb)
    face = (1.0 - smoothstep(rc - 0.0005, rc, d)) * side
    bezel = smoothstep(rc - 0.0004, rc, d) * (1.0 - smoothstep(rc * 1.18 - 0.0005, rc * 1.18, d)) * side
    skin.lay(brass, bezel, rough=0.2, metal=0.66)
    skin.lay(CREAM, face, rough=0.35, metal=0.0)
    skin.height += 0.0012 * bezel + 0.0006 * face
    step = np.pi / 6.0
    tick = (d > rc * 0.86) * (d < rc * 0.95) * (1.0 - smoothstep(0.0003, 0.0005, d * np.abs(np.sin(psi - np.round(psi / step) * step))))
    skin.lay(ENGRAVE, tick * face, rough=0.4, metal=0.0)
    for numeral, ang in (("XII", 0.0), ("III", 90.0), ("VI", 180.0), ("IX", 270.0)):
        ca, cb = np.sin(np.radians(ang)) * rc * 0.66, np.cos(np.radians(ang)) * rc * 0.66
        w, h = 0.011, 0.0075
        u = (va - ca + w * 0.5) / w
        v = (cb + h * 0.5 - vb) / h
        inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
        skin.lay(ENGRAVE, np.where(inside, _bilinear(_engraved(numeral, w / h), u, v), 0.0) * face, rough=0.4, metal=0.0)
    for ang, length, width in ((-60.0, 0.55, 0.0009), (60.0, 0.8, 0.0006)):
        ux, uy = np.sin(np.radians(ang)), np.cos(np.radians(ang))
        along = np.clip(va * ux + vb * uy, -0.1 * rc, length * rc)
        hand = 1.0 - smoothstep(width * 0.6, width, np.hypot(va - along * ux, vb - along * uy))
        skin.lay(hex_rgb("#141210"), hand * face, rough=0.35, metal=0.2)
    skin.lay(BRASS_BRIGHT, (1.0 - smoothstep(0.0015, 0.002, d)) * side, rough=0.2, metal=0.66)
    skin.glow = skin.glow + (EMBER * 0.10)[None, :] * (face * (1.0 - tick))[:, None]
    pa, pb = _view(p, n, 0.990, 0.299)
    steam_plaque(skin, p, pa, pb, 0.0, 0.0, 0.066, 0.015, "No. VII", side, 499)
    soot = (1.0 - smoothstep(0.0, 0.12, height_norm)) * smoothstep(0.4, 0.9, frac)
    skin.grime(soot * 0.4, tint=(0.25, 0.24, 0.23))
    skin.colour = mix(IRON_TONES[1] * 0.8, skin.colour, side)
    return skin


def build_steam(atlas: str):
    return build_metal_skin(atlas, STEAM_ATLASES, steam_fuselage, steam_lifting, steam_fin, glow=True)


_STEAM_CACHE: dict = {}


def _steam_cached(atlas: str):
    if atlas not in _STEAM_CACHE:
        _STEAM_CACHE[atlas] = build_steam(atlas)
    return _STEAM_CACHE[atlas]


# ---------------------------------------------------------------------------------------------
# Sebart Avanti S jet: "Camuflaje Selva". A fictional low-visibility combat scheme: a matte three-tone dark-green
# disruptive camouflage (dark green, black-green and olive drab patches, domain-warped and stretched along the
# airframe) over the upper surfaces and flanks, a light grey-green countershaded belly with a wavy spray line,
# low-visibility pale-grey markings (fictional roundel, serial, squadron), touched-up panels, panel-line wash,
# leading-edge chips to primer and bare alloy, a non-slip walkway, exhaust soot and belly oil streaks. Same four
# maps and scene-space bake as Sabre Plata; the paint is dielectric and only chips expose metal.
# ---------------------------------------------------------------------------------------------
CAMO_ATLASES = dict(SABRE_ATLASES)
CAMO_GREEN = hex_rgb("#34432c")
CAMO_BLACK = hex_rgb("#1e281c")
CAMO_OLIVE = hex_rgb("#565d3b")
CAMO_BELLY = hex_rgb("#8b9487")
CAMO_MARK = hex_rgb("#8f9784")  # low-visibility pale grey-green markings
CAMO_INK = hex_rgb("#17191a")
CAMO_PRIMER = hex_rgb("#8a8b6a")
CAMO_RED = hex_rgb("#8e2a26")  # subdued rescue red
CAMO_ROUGH = 0.66
_CAMO_ART: dict = {}


def _camo_roundel() -> np.ndarray:
    """Fictional low-visibility roundel: pale ring, black-green disc and a forward chevron (left-right symmetric,
    so it reads the same on both flanks and on the mirrored wings)."""
    if "roundel" not in _CAMO_ART:
        from PIL import ImageDraw
        size = 512
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        mark = tuple(int(c * 255 + 0.5) for c in CAMO_MARK) + (255,)
        disc = tuple(int(c * 255 + 0.5) for c in CAMO_BLACK) + (255,)
        d.ellipse((4, 4, size - 5, size - 5), fill=mark)
        d.ellipse((40, 40, size - 41, size - 41), fill=disc)
        c = size / 2
        d.polygon([(c, 96), (c + 150, 330), (c + 92, 330), (c, 188), (c - 92, 330), (c - 150, 330)], fill=mark)
        d.ellipse((c - 26, 360, c + 26, 412), fill=mark)
        _CAMO_ART["roundel"] = np.asarray(img, dtype=np.float64) / 255.0
    return _CAMO_ART["roundel"]


def camo_paint(skin: "_Skin", p, panel_id, seed: int, pattern=None):
    """Matte three-tone camouflage in scene space, so patches run on across parts and control surfaces.
    `pattern` replaces the scene position for the patch shapes where stock UVs share texels between faces."""
    pattern = p if pattern is None else pattern
    warp = np.stack([fbm(pattern, 0.16, seed + k) - 0.5 for k in range(3)], axis=1) * 0.09
    q = pattern + warp
    dark = fbm(q, (0.20, 0.12, 0.34), seed + 5)
    olive = fbm(q, (0.22, 0.14, 0.30), seed + 9)
    dark_w = 1.0 - smoothstep(0.437, 0.443, dark)
    olive_w = smoothstep(0.567, 0.573, olive) * (1.0 - dark_w)
    colour = mix(np.broadcast_to(CAMO_GREEN, (len(p), 3)).copy(), CAMO_OLIVE, olive_w)
    colour = mix(colour, CAMO_BLACK, dark_w)
    # Touched-up panels differ slightly in shade and sheen; the paint fades in sun-exposed blotches.
    shade = 0.95 + 0.09 * _hash(panel_id, seed=seed + 13)
    fade = fbm(p, 0.07, seed + 17)
    skin.colour = colour * (shade * (0.95 + 0.10 * fade))[:, None]
    skin.rough = CAMO_ROUGH + 0.05 * (_hash(panel_id, seed=seed + 19) - 0.5) + 0.08 * (fbm(p, 0.03, seed + 23) - 0.5)
    skin.metal = np.zeros(len(p))
    skin.paint = np.ones(len(p))


def camo_belly(skin: "_Skin", p, weight):
    weight = np.clip(weight, 0.0, 1.0)
    tone = CAMO_BELLY * (0.96 + 0.06 * fbm(p, 0.06, 601))[:, None]
    skin.colour = mix(skin.colour, tone, weight)
    skin.rough = skin.rough + (0.6 - skin.rough) * weight


def camo_chips(skin: "_Skin", amount, p, seed: int):
    """Worn paint: primer first, bare alloy at the centre of the larger chips."""
    primer = smoothstep(0.62, 0.66, fbm(p, 0.006, seed)) * amount
    metal = smoothstep(0.70, 0.74, fbm(p, 0.006, seed)) * amount
    skin.lay(CAMO_PRIMER, primer, rough=0.7, metal=0.0)
    skin.lay(ALU_TONES[1], metal, rough=0.32, metal=0.55)


def camo_fuselage(p, n):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    zn = (z - FUS_NOSE) / FUS_LEN
    zm = zn * FUS_LEN
    dy = y - _fuselage_centre(zn)
    r = np.hypot(x, dy)
    phi = np.arctan2(x, dy)
    a = np.abs(phi)
    arc = r * phi
    side = smoothstep(0.45, 0.65, np.abs(n[:, 0]))
    skin = _Skin(len(p))
    d_station, k_station, f_station = _nearest(zn, FUS_STATIONS)
    d_seam, k_seam, _ = _nearest(a, FUS_SEAMS)
    k_seam = np.where(k_seam == 0, 0, k_seam + 10 * (x < 0))
    panel = k_station * 64 + k_seam
    camo_paint(skin, p, panel, seed=611)
    across = np.where(a < FUS_SEAMS[0], (phi + FUS_SEAMS[0]) / (2 * FUS_SEAMS[0]), _nearest(a, FUS_SEAMS)[2])
    skin.height += 0.0002 * np.sin(np.pi * f_station) * np.sin(np.pi * np.clip(across, 0, 1)) \
        * np.where(_hash(panel, seed=7) < 0.5, -1.0, 1.0)
    # Countershaded belly below a wavy spray line.
    limit = np.radians(124.0 + 10.0 * (noise3(p, (0.5, 0.5, 0.18), 613) - 0.5))
    camo_belly(skin, p, smoothstep(-0.003, 0.003, (a - limit) * r))
    # Panel lines with a dark wash, rivet rows, screwed hatches.
    skin.groove(d_station * FUS_LEN, wash=0.10)
    skin.groove(d_seam * r, wash=0.10)
    skin.groove(np.abs(zn - 0.730) * FUS_LEN, width=0.0016, depth=0.00035, wash=0.12)
    rivet = rivets(d_station * FUS_LEN, arc, (-0.0035, 0.0035), 0.008)
    rivet = np.maximum(rivet, rivets(d_seam * r, zm, (0.0,), 0.008))
    skin.rivet(rivet * (zn > 0.062) * 0.7)
    for z0, z1, y0, y1 in FUS_HATCHES:
        box = _box_distance(zm, y, z0 * FUS_LEN, z1 * FUS_LEN, y0, y1)
        skin.groove(np.where(side > 0.5, box, 1.0), width=0.0013, wash=0.12)
        along = np.where(np.minimum(np.abs(y - y0), np.abs(y - y1)) < np.minimum(np.abs(zm - z0 * FUS_LEN),
                                                                                 np.abs(zm - z1 * FUS_LEN)), zm, y)
        phase = (along % 0.011) - 0.0055
        skin.screw((1.0 - smoothstep(0.0007, 0.0011, np.hypot(box + 0.004, phase))) * (box < 0) * side * 0.6)
        # Fluid stains running aft from the hatch's lower edge.
        drip = np.exp(-np.maximum(zm - z1 * FUS_LEN, 0.0) / 0.10) * (zm > z0 * FUS_LEN) * (np.abs(y - y0) < 0.012)
        skin.grime(drip * smoothstep(0.5, 0.8, noise3(p, (0.004, 0.004, 0.08), 617)) * side * 0.35,
                   tint=(0.30, 0.29, 0.25), rough=0.45, metal_loss=0.0)
    # Gun ports: dark recessed slots with soot fanning aft.
    slot_z0, slot_z1 = 0.100 * FUS_LEN, 0.136 * FUS_LEN
    soot = np.zeros(len(p))
    for yc in GUN_SLOTS:
        capsule = np.hypot(np.maximum(np.maximum(slot_z0 - zm, zm - slot_z1), 0.0), y - yc) - 0.0042
        port = (1.0 - smoothstep(-0.0004, 0.0003, capsule)) * side
        skin.lay(hex_rgb("#101111"), port, rough=0.85, metal=0.0)
        skin.height -= 0.0008 * port
        aft = np.maximum(zm - slot_z1, 0.0)
        spread = 0.0045 + aft * 0.22
        streak = 0.6 + 0.4 * noise3(p, (0.004, 0.003, 0.06), 619)
        soot = np.maximum(soot, np.exp(-aft / 0.12) * (1.0 - smoothstep(spread * 0.5, spread, np.abs(y - yc)))
                          * (zm > slot_z0) * streak * side)
    skin.grime(soot * 0.8, tint=(0.22, 0.21, 0.20), rough=0.7, metal_loss=0.0)
    # Dark grey radome and a matte black-green anti-glare panel ahead of the canopy.
    radome = 1.0 - smoothstep(0.0615, 0.0625, zn)
    skin.lay(hex_rgb("#3a3e3a"), radome, rough=0.55, metal=0.0)
    glare_limit = np.radians(np.interp(zn, [0.07, 0.12, 0.165], [30.0, 50.0, 64.0]))
    glare = (1.0 - smoothstep(-0.001, 0.001, (a - glare_limit) * r)) * (zn > 0.0625) * (1.0 - smoothstep(0.163, 0.167, zn))
    skin.lay(hex_rgb("#191d18"), glare, rough=0.85, metal=0.0)

    def side_mask(mask, z0, z1, y0, y1):
        u, v, weight = _side_uv(p, n, FUS_NOSE + z0 * FUS_LEN, FUS_NOSE + z1 * FUS_LEN, y0, y1)
        return np.where(weight > 0, _bilinear(mask, u, v), 0.0) * weight

    def lettering(text, z0, z1, y0, y1, colour=CAMO_MARK, rows=1, rough=0.6):
        aspect = (z1 - z0) * FUS_LEN / (y1 - y0)
        skin.lay(colour, side_mask(_sabre_text(text, aspect, rows), z0, z1, y0, y1), rough=rough, metal=0.0)

    u, v, weight = _side_uv(p, n, FUS_NOSE + 0.765 * FUS_LEN, FUS_NOSE + 0.845 * FUS_LEN, 0.058, 0.152)
    art = _bilinear(_camo_roundel(), u, v)
    skin.lay(art[:, :3], np.where(weight > 0, art[:, 3], 0.0) * weight, rough=0.6, metal=0.0)
    lettering("FA-742", 0.862, 0.952, 0.034, 0.074, colour=CAMO_INK)
    lettering("ESCUADRÓN 7", 0.205, 0.330, 0.082, 0.102)
    # Rescue arrow pointing forward to the canopy release (scene space, so the tip does not flip).
    rz0, rz1, ry = 0.322 * FUS_LEN, 0.366 * FUS_LEN, 0.1195
    shaft = (zm > rz0 + 0.011) & (zm < rz1) & (np.abs(y - ry) < 0.0042)
    head = (zm >= rz0) & (zm <= rz0 + 0.012) & (np.abs(y - ry) < 0.008 * (zm - rz0) / 0.012)
    skin.lay(CAMO_RED, (shaft | head) * side, rough=0.55, metal=0.0)
    lettering("RESCUE", 0.331, 0.363, 0.1162, 0.1228, colour=CAMO_MARK)
    lettering("SERIAL NO. 742\nFUEL JP-8", 0.432, 0.490, 0.068, 0.090, colour=CAMO_INK, rows=2)
    lettering("EXT. POWER\n28V DC", 0.612, 0.650, 0.074, 0.092, colour=CAMO_INK, rows=2)
    lettering("NO STEP", 0.560, 0.598, 0.196, 0.206, colour=CAMO_MARK)
    # Fuel filler cap on the spine.
    top = smoothstep(0.55, 0.7, n[:, 1])
    cap = np.hypot(x, (zn - 0.53) * FUS_LEN)
    skin.lay(hex_rgb("#4b5046"), (1.0 - smoothstep(0.010, 0.011, cap)) * top, rough=0.5, metal=0.2)
    skin.groove(np.where(top > 0, cap - 0.0112, 1.0), width=0.0012)
    # Weathering: chips on the canopy sill and spine walk, exhaust soot and heat, belly oil.
    sill = ((zn > 0.165) & (zn < 0.42) & (y > 0.08)).astype(float)
    camo_chips(skin, 0.1 * sill + 0.03, p, 621)
    skin.scratch(0.5 * scratches(zm, arc, 0.018, 1.0, 623) * (_hash(np.floor(zm / 0.018), np.floor(arc / 0.018), seed=625)
                                                          < np.where(sill > 0, 0.2, 0.03)))
    exhaust = smoothstep(0.88, 1.0, zn) * (1.0 - smoothstep(0.05, 0.17, y))
    skin.grime(exhaust * (0.5 + 0.5 * noise3(p, (0.006, 0.006, 0.12), 627)) * 0.9, tint=(0.22, 0.21, 0.20), rough=0.7,
               metal_loss=0.0)
    heat = smoothstep(0.975, 0.995, zn)
    skin.lay(hex_rgb("#3a3631"), heat, rough=0.45, metal=0.5)
    belly = smoothstep(np.radians(115), np.radians(150), a)
    oil = np.exp(-np.mod(zn - 0.20, 0.135) * FUS_LEN / 0.16) * smoothstep(0.55, 0.85, noise3(p, (0.005, 0.005, 0.2), 629))
    skin.grime(oil * belly * 0.5, tint=(0.40, 0.38, 0.33), rough=0.42, metal_loss=0.0)
    return skin


def camo_lifting(p, n, frac, span_norm, span_hi, atlas, chord_len, table=None):
    z = p[:, 2]
    s = span_norm * span_hi
    top = n[:, 1] >= 0.0
    face = smoothstep(0.3, 0.6, np.abs(n[:, 1]))
    joints = [0.14, 0.42, 0.70] if atlas != "stab" else [0.17, 0.32]
    spars = [0.14, 0.63] if atlas != "stab" else [0.16, 0.62]
    skin = _Skin(len(p))
    d_joint, k_joint, f_joint = _nearest(s, joints)
    d_spar, k_spar, f_spar = _nearest(frac, spars)
    panel = k_joint * 16 + k_spar * 2 + top
    # The stock stabiliser UVs let elevator and stabiliser faces several centimetres apart share texels: its
    # patches vary along the span only, so the faces sharing a texel agree on its colour.
    pattern = None if atlas != "stab" else np.stack([s, np.full(len(p), 0.30), np.full(len(p), 1.05)], axis=1)
    camo_paint(skin, p, panel, seed=641 if atlas != "stab" else 643, pattern=pattern)
    camo_belly(skin, p, (~top).astype(float))
    skin.height += 0.0002 * np.sin(np.pi * f_joint) * np.sin(np.pi * f_spar) * np.where(_hash(panel, seed=9) < 0.5, -1, 1)
    skin.groove(np.where(face > 0.5, d_joint, 1.0), wash=0.10)
    skin.groove(np.where(face > 0.5, d_spar * chord_len, 1.0), wash=0.10)
    rivet = rivets(d_joint, z, (0.0,), 0.008)
    rivet = np.maximum(rivet, rivets(d_spar * chord_len, s, (0.0,), 0.008))
    skin.rivet(rivet * face * 0.7)
    # Leading-edge erosion: chipped to primer and bare alloy.
    edge = 1.0 - smoothstep(0.0, 0.04, frac)
    camo_chips(skin, 0.85 * edge + 0.03, p, 645 if atlas != "stab" else 647)
    if atlas != "stab":
        # Low-visibility roundels on the upper surfaces, chevron forward.
        art = _camo_roundel()
        # Square in (span, z) about the 42 % chord point at its centre span: not sheared by the sweep, clear of
        # the walkway, the fence, the flap and the leading-edge wear.
        x0, x1 = 0.34, 0.54  # inboard of the wing fence (|x| 0.575) and ahead of the flap
        size = x1 - x0
        le, te = table
        centres = -span_hi + (np.arange(len(le)) + 0.5) * (2.0 * span_hi) / len(le)
        sc = 0.5 * (x0 + x1)
        zc = np.interp(sc, centres, le) + 0.42 * (np.interp(sc, centres, te) - np.interp(sc, centres, le))
        u = (s - x0) / size
        v = (z - (zc - size * 0.5)) / size
        inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1) & top
        sample = _bilinear(art, u, v)
        skin.lay(sample[:, :3], np.where(inside, sample[:, 3], 0.0) * face, rough=0.6, metal=0.0)
        # Non-slip walkway at the root: rough black-green with a pale outline.
        walk = _box_distance(s, frac * chord_len, 0.12, 0.30, 0.26 * chord_len, 0.58 * chord_len)
        skin.lay(hex_rgb("#1b211a"), ((walk < 0) & top) * face, rough=0.92, metal=0.0)
        skin.lay(CAMO_MARK, _line(walk, 0.0018) * top * face, rough=0.6, metal=0.0)
        skin.scratch(0.5 * scratches(s, z, 0.016, 1.0, 649) * np.where((walk < 0) & top, 0.4, 0.02))
        streak = smoothstep(0.55, 0.85, noise3(p, (0.2, 0.006, 0.006), 651)) * (frac > 0.3)
        skin.grime(np.where(top, 0.0, 0.25 * streak), tint=(0.42, 0.40, 0.36), rough=0.45, metal_loss=0.0)
    else:
        soot = (1.0 - smoothstep(0.10, 0.22, s)) * smoothstep(0.3, 0.9, frac)
        skin.grime(soot * (0.5 + 0.5 * noise3(p, (0.2, 0.01, 0.01), 653)) * 0.7, tint=(0.22, 0.21, 0.20), metal_loss=0.0)
    skin.colour = mix(CAMO_BLACK * 0.8, skin.colour, face)  # gap and edge faces read dark
    return skin


def camo_fin(p, n, frac, height_norm):
    y, z = p[:, 1], p[:, 2]
    chord_m = 0.36
    skin = _Skin(len(p))
    joints = [0.212 + 0.365 * h for h in (0.30, 0.62)]
    d_joint, k_joint, f_joint = _nearest(y, joints)
    d_spar, k_spar, f_spar = _nearest(frac, [0.12, 0.62])
    panel = k_joint * 8 + k_spar
    camo_paint(skin, p, panel, seed=661)
    side = smoothstep(0.35, 0.6, np.abs(n[:, 0]))
    skin.groove(np.where(side > 0.5, d_joint, 1.0), wash=0.10)
    skin.groove(np.where(side > 0.5, d_spar * chord_m, 1.0), wash=0.10)
    skin.rivet(np.maximum(rivets(d_joint, z, (0.0,), 0.008), rivets(d_spar * chord_m, y, (0.0,), 0.008)) * side * 0.7)
    camo_chips(skin, 0.8 * (1.0 - smoothstep(0.0, 0.05, frac)) + 0.03, p, 663)

    def lettering(text, z0, z1, y0, y1):
        u, v, weight = _side_uv(p, n, z0, z1, y0, y1)
        mask = _sabre_text(text, (z1 - z0) / (y1 - y0))
        skin.lay(CAMO_MARK, np.where(weight > 0, _bilinear(mask, u, v), 0.0) * weight, rough=0.6, metal=0.0)

    lettering("742", 0.895, 1.035, 0.300, 0.344)
    lettering("ESCUADRÓN 7", 0.925, 1.035, 0.352, 0.364)
    # A black-green fin cap band with a pale keyline.
    skin.lay(CAMO_BLACK, smoothstep(0.875, 0.885, height_norm) * side, rough=0.62, metal=0.0)
    skin.lay(CAMO_MARK, _line((height_norm - 0.872) * 0.365, 0.0025) * side, rough=0.6, metal=0.0)
    soot = (1.0 - smoothstep(0.0, 0.12, height_norm)) * smoothstep(0.4, 0.9, frac)
    skin.grime(soot * 0.5, tint=(0.22, 0.21, 0.20), metal_loss=0.0)
    skin.colour = mix(CAMO_BLACK * 0.8, skin.colour, side)
    return skin


def build_camo(atlas: str):
    return build_metal_skin(atlas, CAMO_ATLASES, camo_fuselage, camo_lifting, camo_fin)


_CAMO_CACHE: dict = {}


def _camo_cached(atlas: str):
    if atlas not in _CAMO_CACHE:
        _CAMO_CACHE[atlas] = build_camo(atlas)
    return _CAMO_CACHE[atlas]


# ---------------------------------------------------------------------------------------------
# Sebart Avanti S jet: "Marquetería Real". A luxury cabinetmaker's veneer airframe: strip-planked walnut topsides
# and mahogany below a stringing belt, a maple king plank, an ebony radome and tail cone, a padauk band, book-matched
# knotty-cherry wings and a crown-cut fin with maple cross-banded leading edges and ebony tips, satinwood and padauk
# control surfaces, compass-rose medallions and inlaid maple Cinzel numerals edged in ebony, brass fittings, all under
# a gloss lacquer. Each veneer is a photographed CC0 wood (ambientCG, see sources/marquetry) laid in scene space with its
# grain following the airframe. Same four maps and bake as Sabre Plata; the metallic map marks only the brass.
# ---------------------------------------------------------------------------------------------
WOOD_ATLASES = dict(SABRE_ATLASES)
MARQUETRY_SOURCES = ROOT / "tools/skins/sources/marquetry"
MARQUETRY_CACHE = ROOT / ".tools/skin-sources/marquetry"  # ignored; filled from ambientCG and hash-verified
INLAY_FONT = MARQUETRY_SOURCES / "Cinzel-wght.ttf"  # SIL OFL 1.1 (see that folder's README.md)
WOODS = {"walnut": "Wood027", "ebony": "Wood028", "maple": "Wood022", "satinwood": "Wood023",
         "cherry": "Wood029", "mahogany": "Wood026", "padauk": "Wood069", "crown": "Wood013"}
WOOD_TILE = 0.60  # metres of real veneer per photograph (finer grain aliases at the atlas texel size)
LACQUER = np.array([1.0, 0.975, 0.94])  # amber warmth of a gloss lacquer film
# Art-directed grading per veneer (saturation, value): a lifted dark walnut and a quieter padauk keep it elegant.
WOOD_GRADE = {"walnut": (0.95, 1.08), "padauk": (0.72, 0.80), "cherry": (0.92, 0.94), "mahogany": (0.92, 0.92)}
BRASS = hex_rgb("#c49b50")
_WOOD: dict = {}
_WOOD_ART: dict = {}
_HINGES: dict = {}


def _wood(name: str):
    """(colour, relief) arrays of one veneer from the ignored cache; a missing member is fetched once and verified."""
    if name not in _WOOD:
        asset = WOODS[name]
        manifest = json.loads((MARQUETRY_SOURCES / "sources.json").read_text(encoding="utf-8"))
        entries = {entry["file"]: entry for entry in manifest["files"]}
        members = [f"{asset}_1K-JPG_{kind}.jpg" for kind in ("Color", "Displacement")]

        def valid(member):
            path = MARQUETRY_CACHE / member
            return path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == entries[member]["sha256"]

        if not all(valid(member) for member in members):
            import urllib.request
            import zipfile
            request = urllib.request.Request(entries[members[0]]["archive"], headers={"User-Agent": "openrc-skin-builder"})
            with urllib.request.urlopen(request, timeout=120) as response:
                archive = zipfile.ZipFile(io.BytesIO(response.read()))
            MARQUETRY_CACHE.mkdir(parents=True, exist_ok=True)
            for member in members:
                data = archive.read(member)
                if hashlib.sha256(data).hexdigest() != entries[member]["sha256"]:
                    raise SystemExit(f"{member}: SHA-256 differs from sources/marquetry/sources.json")
                (MARQUETRY_CACHE / member).write_bytes(data)
        colour = np.asarray(Image.open(MARQUETRY_CACHE / members[0]).convert("RGB"), dtype=np.float64) / 255.0
        saturation, value = WOOD_GRADE.get(name, (1.0, 1.0))
        grey = colour @ np.array([0.2126, 0.7152, 0.0722])
        colour = (grey[..., None] + (colour - grey[..., None]) * saturation) * value
        relief = np.asarray(Image.open(MARQUETRY_CACHE / members[1]).convert("L"), dtype=np.float64) / 255.0
        _WOOD[name] = (colour, relief)
    return _WOOD[name]


def wood_lay(skin: "_Skin", name, along, t, mask, leaf=0, width=1e3, seed=0, tone=0.08, tile=WOOD_TILE,
             seam=False):
    """Lay veneer over `mask`: `along` runs with the grain (metres), `t` across it from the leaf's seam (0..width).
    Leaves 2k and 2k+1 are consecutive slices of one flitch, so the second mirrors the first across their shared
    seam (book-matching); each flitch has its own offset into the photograph and a slightly different tone."""
    mask = np.clip(mask, 0.0, 1.0)
    colour, relief = _wood(name)
    leaf = np.broadcast_to(np.asarray(leaf), np.shape(along)).astype(np.int64)
    width = np.broadcast_to(np.asarray(width, dtype=np.float64), np.shape(along))
    pair = np.floor_divide(leaf, 2)
    local = np.where(leaf % 2 == 1, width - t, t)
    u = (along / tile + _hash(pair, seed=seed)) % 1.0
    v = (local / tile + _hash(pair, seed=seed + 1)) % 1.0
    shade = 1.0 - tone * 0.5 + tone * _hash(pair, seed=seed + 2)
    wood = np.clip(_bilinear(colour, u, v) * shade[:, None] * LACQUER, 0.0, 1.0)
    pores = _bilinear(relief, u, v)
    skin.colour = mix(skin.colour, wood, mask)
    skin.rough = skin.rough + (0.085 + 0.10 * (1.0 - pores) ** 2 - skin.rough) * mask  # open pores hold less lacquer
    skin.metal = skin.metal * (1.0 - mask)
    skin.height = skin.height * (1.0 - mask) + 0.00003 * (pores - 0.5) * mask
    if seam:  # a hairline glue joint between leaves
        line = _line(np.minimum(t, width - t), 0.0005) * mask
        skin.colour = skin.colour * (1.0 - 0.28 * line)[:, None]
        skin.height -= 0.00002 * line


def leaves(coord, width):
    """Leaf index and the position across it for leaves `width` wide along `coord`."""
    k = np.floor(coord / width)
    return k.astype(np.int64), coord - k * width


def stringing(skin: "_Skin", d, along, mask=1.0, pattern=(("ebony", 0.0024), ("maple", 0.0011)), seed=0):
    """Inlaid stringing centred on d = 0: nested bands, outermost first (ebony-maple-ebony by default)."""
    for n, (name, half) in enumerate(pattern):
        band = (1.0 - smoothstep(half - 0.00015, half + 0.00015, np.abs(d))) * mask
        if np.any(band > 0):
            wood_lay(skin, name, along, d + half, band, seed=seed + 17 * n, tone=0.0, tile=0.25)
            skin.height -= 0.00002 * _line(np.abs(d) - half, 0.0004) * np.clip(mask, 0, 1)


def brass_fitting(skin: "_Skin", mask, p, seed):
    mask = np.clip(mask, 0.0, 1.0)
    tarnish = smoothstep(0.3, 0.8, fbm(p, 0.01, seed))
    skin.lay(BRASS * (1.0 - 0.18 * tarnish)[:, None], mask, rough=0.22 + 0.10 * tarnish, metal=0.68)
    skin.height = skin.height * (1.0 - mask) + 0.00006 * mask


def _inlay_masks(text: str, aspect: float):
    """(letter, letter plus ebony border) masks of Cinzel Bold numerals."""
    key = (text, round(aspect, 3))
    if key not in _WOOD_ART:
        from PIL import ImageDraw, ImageFont
        height = 256
        width = int(round(height * aspect))
        font = ImageFont.truetype(str(INLAY_FONT), int(height * 0.80))
        font.set_variation_by_name("Bold")
        masks = []
        for stroke in (0, 9):
            canvas = Image.new("L", (width, height), 0)
            ImageDraw.Draw(canvas).text((width * 0.5, height * 0.52), text, fill=255, font=font, anchor="mm",
                                        stroke_width=stroke, stroke_fill=255)
            masks.append(np.asarray(canvas, dtype=np.float64) / 255.0)
        _WOOD_ART[key] = tuple(masks)
    return _WOOD_ART[key]


def _compass_labels() -> np.ndarray:
    """Label image of an eight-point compass rose: 1 disc, 2 ebony ring, 3 maple ring, 4 centre, 10 + 2i (+1) for
    the left (right) half of point i, clockwise from the top (forward)."""
    if "compass" not in _WOOD_ART:
        from PIL import ImageDraw
        size = 1024
        c = size / 2
        img = Image.new("L", (size, size), 0)
        d = ImageDraw.Draw(img)
        for radius, label in ((0.49, 2), (0.465, 3), (0.452, 2), (0.437, 1)):
            d.ellipse((c - radius * size, c - radius * size, c + radius * size, c + radius * size), fill=label)

        def at(angle, radius):
            return (c + radius * size * np.sin(angle), c - radius * size * np.cos(angle))

        for i in list(range(1, 8, 2)) + list(range(0, 8, 2)):  # minor points under the cardinal points
            phi = np.radians(45.0 * i)
            tip = 0.425 if i % 2 == 0 else 0.30
            side = 0.085 if i % 2 == 0 else 0.065
            left, right = at(phi - np.radians(22.5), side), at(phi + np.radians(22.5), side)
            d.polygon([(c, c), at(phi, tip), left], fill=10 + 2 * i)
            d.polygon([(c, c), at(phi, tip), right], fill=11 + 2 * i)
        d.ellipse((c - 0.03 * size, c - 0.03 * size, c + 0.03 * size, c + 0.03 * size), fill=4)
        _WOOD_ART["compass"] = np.asarray(img)
    return _WOOD_ART["compass"]


def compass_inlay(skin: "_Skin", u, v, size_m, weight, seed):
    """A compass-rose medallion over the unit square (u right, v down = aft); each point is split into a light and a
    dark wood with the grain along the point, as a marquetry rose is cut."""
    labels = _compass_labels()
    n = labels.shape[0]
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1) & (np.asarray(weight) > 0)
    lab = np.where(inside, labels[np.clip((v * n).astype(int), 0, n - 1), np.clip((u * n).astype(int), 0, n - 1)], 0)
    x, y = (u - 0.5) * size_m, (0.5 - v) * size_m
    w = np.clip(weight, 0.0, 1.0)
    wood_lay(skin, "satinwood", x, y, (lab == 1) * w, seed=seed, tone=0.0)
    wood_lay(skin, "ebony", np.arctan2(x, y) * size_m * 0.5, np.hypot(x, y), np.isin(lab, (2, 4)) * w, seed=seed + 1, tone=0.0)
    wood_lay(skin, "maple", np.arctan2(x, y) * size_m * 0.5, np.hypot(x, y), (lab == 3) * w, seed=seed + 2, tone=0.0)
    for i in range(8):
        phi = np.radians(45.0 * i)
        along = x * np.sin(phi) + y * np.cos(phi)
        across = x * np.cos(phi) - y * np.sin(phi)
        light, dark = ("maple", "walnut") if i % 2 == 0 else ("padauk", "mahogany")
        wood_lay(skin, light, along, across, (lab == 10 + 2 * i) * w, seed=seed + 5 + i, tone=0.0)
        wood_lay(skin, dark, along, across, (lab == 11 + 2 * i) * w, seed=seed + 15 + i, tone=0.0)
    edge = np.zeros(len(u))
    for dy, dx in ((1, 0), (0, 1)):  # hairline knife joints between the cut pieces
        nb = labels[np.clip((v * n).astype(int) + dy, 0, n - 1), np.clip((u * n).astype(int) + dx, 0, n - 1)]
        edge = np.maximum(edge, ((nb != lab) & inside).astype(float))
    skin.colour = skin.colour * (1.0 - 0.3 * edge * w)[:, None]
    skin.height -= 0.00002 * edge * w


def numeral_inlay(skin: "_Skin", u, v, inside_weight, text, aspect, seed, along, across):
    """Maple numerals with an ebony border, grain set across the surrounding veneer."""
    letter, border = _inlay_masks(text, aspect)
    w = np.clip(inside_weight, 0.0, 1.0)
    edge = np.where(w > 0, _bilinear(border, np.clip(u, 0, 1), np.clip(v, 0, 1)), 0.0) * w
    core = np.where(w > 0, _bilinear(letter, np.clip(u, 0, 1), np.clip(v, 0, 1)), 0.0) * w
    wood_lay(skin, "ebony", along, across, edge, seed=seed, tone=0.0)
    wood_lay(skin, "maple", across, along, core, seed=seed + 1, tone=0.0)
    skin.height -= 0.00002 * (_line(edge - 0.5, 0.25) + _line(core - 0.5, 0.25))


def _hinge(kind: str):
    """Control-surface leading edge z along its span, from that surface's own primitives in the stock model."""
    if kind not in _HINGES:
        material, axis, lo, hi, z_floor = {"aileron": ("paint_wing", 0, 0.579, 0.894, 0.40),
                                           "flap": ("paint_wing", 0, 0.174, 0.566, 0.30),
                                           "elevator": ("paint_stab", 0, 0.087, 0.44, 1.10),
                                           "rudder": ("paint_fin", 1, 0.224, 0.576, 1.00)}[kind]
        pts = []
        for _name, pos, _nrm, _uv, _tris in scene_primitives(JET_GLB, (material,)):
            span = np.abs(pos[:, axis]) if axis == 0 else pos[:, axis]
            if abs(span.min() - lo) < 0.01 and abs(span.max() - hi) < 0.01 and pos[:, 2].min() > z_floor:
                pts.append(np.stack([span, pos[:, 2]], axis=1))
        pts = np.concatenate(pts)
        bins = 24
        k = np.clip(((pts[:, 0] - lo) / (hi - lo) * bins).astype(int), 0, bins - 1)
        zmin = np.full(bins, np.inf)
        np.minimum.at(zmin, k, pts[:, 1])
        centres = lo + (np.arange(bins) + 0.5) * (hi - lo) / bins
        good = np.isfinite(zmin)
        # Hinge lines are straight; a line through the per-bin leading edges removes the bins' stair steps.
        _HINGES[kind] = (lo, hi, np.polyfit(centres[good], zmin[good], 1))
    return _HINGES[kind]


def hinge_mask(kind: str, span, z):
    """(mask of the control surface, signed distance aft of its hinge line)."""
    lo, hi, line = _hinge(kind)
    d = z - np.polyval(line, span)
    inside = (span > lo - 0.002) & (span < hi + 0.002)
    return (inside & (d > -0.001)).astype(float), np.where(inside, d, 1.0)


def wood_fuselage(p, n):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    zn = (z - FUS_NOSE) / FUS_LEN
    zm = zn * FUS_LEN
    dy = y - _fuselage_centre(zn)
    r = np.hypot(x, dy)
    phi = np.arctan2(x, dy)
    a = np.abs(phi)
    arc = r * phi
    side = smoothstep(0.45, 0.65, np.abs(n[:, 0]))
    skin = _Skin(len(p))
    skin.metal = np.zeros(len(p))
    # Strip planking: tapering strakes (constant angle, so they narrow toward the nose and tail like real strips).
    strake = 2.0 * np.pi / 44.0
    k, t = leaves(phi, strake)
    width = strake * np.maximum(r, 1e-3)
    belt = np.radians(117.0)
    lower = smoothstep(-0.0004, 0.0004, (a - belt) * r)
    wood_lay(skin, "walnut", zm, t * r, np.ones(len(p)), leaf=k, width=width, seed=701, seam=True)
    wood_lay(skin, "mahogany", zm, t * r, lower, leaf=k, width=width, seed=703, seam=True)
    body = (zn > 0.07) & (zn < 0.905)
    stringing(skin, (a - belt) * r, zm, body, seed=705)
    # Maple king plank down the spine, edged in ebony.
    king = 0.0105
    wood_lay(skin, "maple", zm, arc + king, (np.abs(arc) < king) * body, seed=707, tone=0.0)
    stringing(skin, np.abs(arc) - king, zm, body, pattern=(("ebony", 0.0014),), seed=709)
    # Padauk band at the aft break, cross-grained, with stringing on both edges.
    band = (zn > 0.700) & (zn < 0.724)
    wood_lay(skin, "padauk", arc, zm, band.astype(float), seed=711, tone=0.0)
    for edge in (0.700, 0.724):
        stringing(skin, (zn - edge) * FUS_LEN, arc, 1.0, seed=713)
    # Ebony radome and tail cone, grain along the length, with a maple-and-ebony ring at each joint.
    wood_lay(skin, "ebony", zm, arc, (zn < 0.066).astype(float), seed=715, tone=0.0)
    wood_lay(skin, "ebony", zm, arc, (zn > 0.905).astype(float), seed=717, tone=0.0)
    for edge in (0.066, 0.905):
        stringing(skin, (zn - edge) * FUS_LEN, arc, 1.0, pattern=(("ebony", 0.0030), ("maple", 0.0016)), seed=719)
    # Hatches: a maple stringing outline and four brass screws.
    for z0, z1, y0, y1 in FUS_HATCHES:
        box = _box_distance(zm, y, z0 * FUS_LEN, z1 * FUS_LEN, y0, y1)
        along = np.where(np.abs(np.abs(y - 0.5 * (y0 + y1)) - 0.5 * (y1 - y0)) < 0.003, zm, y)
        stringing(skin, box, along, side, pattern=(("maple", 0.0009),), seed=721)
        for cz in (z0 * FUS_LEN + 0.006, z1 * FUS_LEN - 0.006):
            for cy in (y0 + 0.006, y1 - 0.006):
                brass_fitting(skin, (1.0 - smoothstep(0.0011, 0.0016, np.hypot(zm - cz, y - cy))) * side, p, 723)
    # Brass fuel filler on the spine.
    top = smoothstep(0.55, 0.7, n[:, 1])
    cap = np.hypot(x, (zn - 0.53) * FUS_LEN)
    stringing(skin, cap - 0.0125, arc, top, pattern=(("ebony", 0.0016),), seed=725)
    brass_fitting(skin, (1.0 - smoothstep(0.010, 0.0108, cap)) * top, p, 727)
    # Inlaid numerals behind the radome and compass-rose medallions on the aft flanks.
    z0, z1, y0, y1 = FUS_NOSE + 0.098 * FUS_LEN, FUS_NOSE + 0.170 * FUS_LEN, -0.018, 0.046
    u, v, weight = _side_uv(p, n, z0, z1, y0, y1)
    numeral_inlay(skin, u, v, weight, "07", (z1 - z0) / (y1 - y0), 731, zm, y)
    z0, z1, y0, y1 = FUS_NOSE + 0.784 * FUS_LEN, FUS_NOSE + 0.826 * FUS_LEN, 0.058, 0.152
    u, v, weight = _side_uv(p, n, z0, z1, y0, y1)
    compass_inlay(skin, u, v, y1 - y0, weight, 733)
    # A faint heat patina inside the jet pipe lip; the lacquer is otherwise immaculate.
    heat = smoothstep(0.975, 1.0, zn)
    skin.colour = skin.colour * (1.0 - 0.25 * heat)[:, None]
    return skin


def wood_lifting(p, n, frac, span_norm, span_hi, atlas, chord_len, table=None):
    z = p[:, 2]
    s = span_norm * span_hi
    top = n[:, 1] >= 0.0
    face = smoothstep(0.3, 0.6, np.abs(n[:, 1]))
    skin = _Skin(len(p))
    skin.metal = np.zeros(len(p))
    b = frac * chord_len  # metres aft of the leading edge
    ones = np.ones(len(p))
    if atlas == "stab":
        # Grain runs chordwise: the stock stabiliser UVs let faces centimetres apart in z share texels, and a
        # veneer varies far less along its grain than across it.
        k, t = leaves(s, 0.075)
        wood_lay(skin, "walnut", z, t, ones, leaf=k, width=0.075, seed=741, seam=True)
        cs, d_hinge = hinge_mask("elevator", s, z)
        wood_lay(skin, "padauk", z, s, cs, seed=743, tone=0.0)
        stringing(skin, d_hinge - 0.0012, s, (d_hinge > -0.004).astype(float), pattern=(("ebony", 0.0012),), seed=745)
        le_band, tip_from = 0.014, span_hi - 0.030
    else:
        k, t = leaves(b, 0.078)
        wood_lay(skin, "cherry", s, t, top.astype(float), leaf=k, width=0.078, seed=751, seam=True)
        wood_lay(skin, "mahogany", s, t, (~top).astype(float), leaf=k, width=0.078, seed=753, seam=True)
        for kind, name in (("flap", "satinwood"), ("aileron", "padauk")):
            cs, d_hinge = hinge_mask(kind, s, z)
            wood_lay(skin, name, s, d_hinge, cs, seed=755 if kind == "flap" else 757, tone=0.0)
            stringing(skin, d_hinge - 0.0012, s, (d_hinge > -0.004).astype(float), pattern=(("ebony", 0.0012),), seed=759)
        le_band, tip_from = 0.022, span_hi - 0.045
    # Maple cross-banded leading edge (grain chordwise) behind an ebony line; ebony tips edged in maple.
    wood_lay(skin, "maple", b, s, (b < le_band).astype(float), seed=761, tone=0.0)
    stringing(skin, b - le_band, s, 1.0, pattern=(("ebony", 0.0012),), seed=763)
    wood_lay(skin, "ebony", b, s, (s > tip_from).astype(float), seed=765, tone=0.0)
    stringing(skin, s - tip_from, b, 1.0, pattern=(("maple", 0.0011),), seed=767)
    if atlas == "wing":
        # Compass-rose medallions on the upper surfaces, inboard of the fences and ahead of the flaps.
        x0, x1 = 0.36, 0.52
        size = x1 - x0
        le, te = table
        centres = -span_hi + (np.arange(len(le)) + 0.5) * (2.0 * span_hi) / len(le)
        sc = 0.5 * (x0 + x1)
        zc = np.interp(sc, centres, le) + 0.40 * (np.interp(sc, centres, te) - np.interp(sc, centres, le))
        compass_inlay(skin, (s - x0) / size, (z - (zc - size * 0.5)) / size, size, top * face, 771)
    # Gap and edge faces read as dark end grain.
    skin.colour = mix(np.broadcast_to(hex_rgb("#231912"), (len(p), 3)), skin.colour, face)
    return skin


def wood_fin(p, n, frac, height_norm):
    y, z = p[:, 1], p[:, 2]
    side = smoothstep(0.35, 0.6, np.abs(n[:, 0]))
    skin = _Skin(len(p))
    skin.metal = np.zeros(len(p))
    k, t = leaves(y, 0.07)
    wood_lay(skin, "crown", z, t, np.ones(len(p)), leaf=k, width=0.07, seed=781, seam=True)
    cs, d_hinge = hinge_mask("rudder", y, z)
    wood_lay(skin, "satinwood", y, z, cs, seed=783, tone=0.0)  # vertical grain on the rudder
    stringing(skin, d_hinge - 0.0012, y, (d_hinge > -0.004).astype(float), pattern=(("ebony", 0.0012),), seed=785)
    wood_lay(skin, "maple", y, z, (frac < 0.045).astype(float), seed=787, tone=0.0)
    stringing(skin, (frac - 0.045) * 0.36, y, 1.0, pattern=(("ebony", 0.0012),), seed=789)
    cap = 0.885
    wood_lay(skin, "ebony", z, y, (height_norm > cap).astype(float), seed=791, tone=0.0)
    stringing(skin, (height_norm - cap) * 0.365, z, 1.0, pattern=(("ebony", 0.0024), ("maple", 0.0011)), seed=793)
    z0, z1, y0, y1 = 0.905, 1.030, 0.284, 0.364
    u, v, weight = _side_uv(p, n, z0, z1, y0, y1)
    numeral_inlay(skin, u, v, weight, "07", (z1 - z0) / (y1 - y0), 795, z, y)
    skin.colour = mix(np.broadcast_to(hex_rgb("#231912"), (len(p), 3)), skin.colour, side)
    return skin


def build_wood(atlas: str):
    return build_metal_skin(atlas, WOOD_ATLASES, wood_fuselage, wood_lifting, wood_fin)


_WOOD_CACHE: dict = {}


def _wood_cached(atlas: str):
    if atlas not in _WOOD_CACHE:
        _WOOD_CACHE[atlas] = build_wood(atlas)
    return _WOOD_CACHE[atlas]


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
    for atlas in REVOC_SIZES:
        files[f"avanti-s-a200/revoc_custom_{atlas}.png"] = lambda a=atlas: encode(build_revoc(a), ".png")
    for atlas in JETI_SIZES:
        files[f"avanti-s-a200/jeti_ruby_{atlas}.png"] = lambda a=atlas: encode(build_jeti(a), ".png")
    files["avanti-s-a200/jeti_ruby_fuselage_roughness.png"] = lambda: encode(build_jeti("fuselage_roughness"), ".png")
    for atlas in ELAN_SIZES:
        files[f"avanti-s-a200/elan_35_{atlas}.png"] = lambda a=atlas: encode(build_elan(a), ".png")
    files["avanti-s-a200/elan_35_fuselage_roughness.png"] = lambda: encode(build_elan("fuselage_roughness"), ".png")
    for atlas in SABRE_ATLASES:
        stem = f"avanti-s-a200/sabre_plata_{atlas}"
        files[stem + ".jpg"] = lambda a=atlas: encode(_sabre_cached(a)[0], ".jpg")
        files[stem + "_roughness.jpg"] = lambda a=atlas: encode(_sabre_cached(a)[1], ".jpg")
        files[stem + "_metallic.png"] = lambda a=atlas: encode(_sabre_cached(a)[2], ".png")
        files[stem + "_normal.png"] = lambda a=atlas: encode(_sabre_cached(a)[3], ".png")
    for atlas in STEAM_ATLASES:
        stem = f"avanti-s-a200/steampunk_cobre_{atlas}"
        files[stem + ".jpg"] = lambda a=atlas: encode(_steam_cached(a)[0], ".jpg")
        files[stem + "_roughness.jpg"] = lambda a=atlas: encode(_steam_cached(a)[1], ".jpg")
        files[stem + "_metallic.png"] = lambda a=atlas: encode(_steam_cached(a)[2], ".png")
        files[stem + "_normal.png"] = lambda a=atlas: encode(_steam_cached(a)[3], ".png")
        files[stem + "_emission.png"] = lambda a=atlas: encode(_steam_cached(a)[4], ".png")
    for atlas in CAMO_ATLASES:
        stem = f"avanti-s-a200/camuflaje_selva_{atlas}"
        files[stem + ".jpg"] = lambda a=atlas: encode(_camo_cached(a)[0], ".jpg")
        files[stem + "_roughness.jpg"] = lambda a=atlas: encode(_camo_cached(a)[1], ".jpg")
        files[stem + "_metallic.png"] = lambda a=atlas: encode(_camo_cached(a)[2], ".png")
        files[stem + "_normal.png"] = lambda a=atlas: encode(_camo_cached(a)[3], ".png")
    for atlas in WOOD_ATLASES:
        stem = f"avanti-s-a200/marqueteria_real_{atlas}"
        files[stem + ".jpg"] = lambda a=atlas: encode(_wood_cached(a)[0], ".jpg")
        files[stem + "_roughness.jpg"] = lambda a=atlas: encode(_wood_cached(a)[1], ".jpg")
        files[stem + "_metallic.png"] = lambda a=atlas: encode(_wood_cached(a)[2], ".png")
        files[stem + "_normal.png"] = lambda a=atlas: encode(_wood_cached(a)[3], ".png")
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
