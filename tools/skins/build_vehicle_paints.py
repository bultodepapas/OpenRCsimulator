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
    "doors": (("paint_doors_ala",), (1024, 1024)),
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
                if name not in wanted:
                    continue
                attrs = prim["attributes"]
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


def carbon(pos, nrm, tile: float = 0.025):
    """Clear-coated 2x2 twill sampled triplanar in scene space (the CC0 ambientCG weave in shared/)."""
    global _TWILL
    if _TWILL is None:
        _TWILL = np.asarray(Image.open(CARBON_TWILL).convert("RGB"), dtype=np.float64) / 255.0
    size = _TWILL.shape[0]
    axis = np.argmax(np.abs(nrm), axis=-1)
    a = np.where(axis == 0, pos[..., 1], pos[..., 0])
    b = np.where(axis == 2, pos[..., 1], pos[..., 2])
    u = ((a / tile) % 1.0 * size).astype(int) % size
    v = ((b / tile) % 1.0 * size).astype(int) % size
    return _TWILL[v, u] * 1.05


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
    pin = (1.0 - smoothstep(0.0022, 0.0034, np.abs(d - 0.007))) + (1.0 - smoothstep(0.0010, 0.0020, np.abs(d - 0.0155)))
    colour = mix(colour, JET_WHITE, np.clip(pin, 0, 1) * (zn > 0.07))
    # Speed slashes on the flanks behind the intakes.
    side = smoothstep(0.45, 0.7, np.abs(nrm[..., 0]))
    diag = zn * 3.4 + y * 7.0
    slash = (1.0 - smoothstep(0.08, 0.1, (diag % 1.0))) * smoothstep(0.38, 0.40, zn) * (1.0 - smoothstep(0.58, 0.60, zn))
    colour = mix(colour, JET_WHITE, slash * side * (y < split - 0.03))
    # White belly with forward-pointing green chevrons.
    belly = smoothstep(-0.45, -0.65, ny)
    chevron = (1.0 - smoothstep(0.16, 0.19, ((zn * 7.0 + np.abs(x) * 9.0) % 1.0))) * (zn > 0.12) * (zn < 0.92)
    belly_colour = mix(np.broadcast_to(JET_WHITE, pos.shape).copy(), NEON, chevron)
    colour = mix(colour, belly_colour, belly)
    # Lettering: "NEO" on the rear flanks, "07" behind the radome.
    colour = mix(colour, JET_WHITE, side_text(pos, nrm, "NEO", 0.52, 0.86, 0.005, 0.085) * (1.0 - belly))
    colour = mix(colour, INK, side_text(pos, nrm, "07", -0.72, -0.56, -0.02, 0.045) * (1.0 - belly) * (1.0 - above))
    glow = np.clip((1.0 - above) * (1.0 - belly) * (1.0 - np.clip(pin, 0, 1)) * (zn > 0.06), 0, 1)
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
    upper = mix(carbon(pos, nrm), NEON, np.maximum(blade, tip))
    upper = mix(upper, JET_WHITE, np.clip(rim + tip_stripe, 0, 1) * (1.0 - tip * (1.0 - tip_stripe)))
    chevron = np.abs(frac - (0.18 + 0.75 * span_norm)) < 0.13
    lower = mix(np.broadcast_to(JET_WHITE, pos.shape).copy(), NEON, chevron.astype(float))
    lower = mix(lower, carbon(pos, nrm), tip)
    colour = np.where(top[..., None], upper, lower)
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
    colour = mix(colour, JET_WHITE, side_text(pos, nrm, "07", 0.97, 1.19, 0.262, 0.352))
    glow = np.maximum(blade, tip) * (1.0 - np.clip(rim, 0, 1))
    return colour, glow, 1.0 - np.maximum(np.maximum(blade, tip), np.clip(rim, 0, 1))


# --- Detail pass: engraved panel lines, hatches, stencils and decals, vinyl edges, soot, gloss map ---------------
DECAL_RED = (214, 32, 38, 255)
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
        d.text((360, 56), "NEO-07  SPORT JET", fill=(242, 245, 247, 255), font=font, anchor="mm",
               stroke_width=1, stroke_fill=(242, 245, 247, 255))
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
        for joint in (0.30, 0.47, 0.70, 0.86):
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
                  ("hot", 0.925, 0.958, 0.080, 0.112), ("serial", 0.690, 0.905, 0.087, 0.109)]
        for kind, a0, a1, b0, b1 in decals:
            art, alpha = side_decal(pos, nrm, kind, -0.938 + a0 * 2.221, -0.938 + a1 * 2.221, b0, b1)
            colour = mix(colour, art, alpha)
            rough = rough + (0.32 - rough) * alpha
            glow *= 1.0 - alpha
        # Exhaust soot: a faint grey film on the tail cone.
        soot = smoothstep(0.90, 1.0, zn) * (1.0 - smoothstep(0.05, 0.16, y))
        colour = colour * (1.0 - 0.28 * soot)[..., None]
        rough = np.maximum(rough, 0.4 * soot)
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
            walk = _box_distance(span_norm * 0.998, frac * chord_m, 0.27, 0.40, 0.18 * chord_m, 0.55 * chord_m)
            dash = ((((span_norm * 0.998 + frac * chord_m) / 0.012) % 1.0) < 0.6).astype(float)
            colour = mix(colour, JET_WHITE, _line(walk, 0.0016) * top * dash)
    elif atlas == "fin":
        colour, rough, g = engrave(colour, rough, (frac - 0.62) * 0.4)
        glow *= 1.0 - g
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
