"""SC-HUM-02: merge one exported field-person glTF into a single mesh with one atlas material.

Run through Blender 5.2.2 (for its bundled numpy and PNG reader) after generate_people.py:

    blender --background --factory-startup --python tools/scenery/population/merge_people_atlas.py -- \
        SOURCE.gltf OUTPUT.gltf

Each source part keeps its geometry, normals and UVs exactly; UVs are remapped into a diffuse atlas
with edge-extended gutters (no mip bleeding between parts) and a half-resolution normal atlas. The
second UV set carries (shading class, roughness) so one runtime material reproduces the per-part
shading: 0 skin, 1 fabric, 2 plain, 3 eyes (also marks the eye height for the head rig),
4 flat (untextured parts and the rigid transmitter). PNGs are written with zlib directly, so equal pixels give equal bytes.
Then package the result with package_population.py as before.
"""

import hashlib
import json
import math
import os
import struct
import sys
import zlib
from pathlib import Path

import bpy
import numpy

GUTTER = 16
# Low-end and web GPUs guarantee 4096-texel textures; the Compatibility renderer targets them.
MAX_ATLAS_EDGE = 4096
SWATCH = 16
CLASS_SKIN, CLASS_FABRIC, CLASS_PLAIN, CLASS_EYES, CLASS_FLAT = 0, 1, 2, 3, 4
MIN_ROUGHNESS = 0.60  # population.gd clamps per-part roughness to at least this value
# Every atlas reserves this swatch (the project transmitter's dark matte), so poses with and without
# the transmitter share one atlas file by content hash.
DEFAULT_SWATCH = (0.015, 0.02, 0.03)
COMPONENTS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
FORMATS = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}


def read_accessor(document, binary, index):
    accessor = document['accessors'][index]
    view = document['bufferViews'][accessor['bufferView']]
    width = COMPONENTS[accessor['type']]
    kind = FORMATS[accessor['componentType']]
    size = struct.calcsize('<' + kind)
    stride = view.get('byteStride', width * size)
    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    values = []
    for item in range(accessor['count']):
        values.append(struct.unpack_from('<%d%s' % (width, kind), binary, start + item * stride))
    return values


def shading_class(material_name, has_texture):
    name = material_name.lower()
    # The transmitter is rigid (never in the head rig), textured screen included (SC-HUM-01).
    if not has_texture or name.startswith('rc_transmitter'):
        return CLASS_FLAT
    if name.endswith('.body'):
        return CLASS_SKIN
    # Tintable garments (the runtime shirt tint only reaches the upper body). Work overalls keep their denim.
    if 'worksuit' not in name and any(word in name for word in ('suit', 'shirt', 'pants', 'shorts', 'sweater')):
        return CLASS_FABRIC
    if 'low-poly' in name or 'eye' in name and 'brow' not in name:
        return CLASS_EYES
    return CLASS_PLAIN


def load_rgba(path):
    """Top-left-origin uint8 RGBA, exactly the stored bytes (no colour management)."""
    image = bpy.data.images.load(str(path), check_existing=False)
    image.colorspace_settings.name = 'Non-Color'
    width, height = image.size
    pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    rgba = numpy.rint(pixels.reshape(height, width, 4) * 255.0).astype(numpy.uint8)
    return rgba[::-1].copy()


def write_png(path, rgba):
    height, width, _ = rgba.shape
    raw = b''.join(b'\x00' + rgba[row].tobytes() for row in range(height))
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    Path(path).write_bytes(png)


def srgb_byte(linear):
    value = linear * 12.92 if linear <= 0.0031308 else 1.055 * math.pow(linear, 1.0 / 2.4) - 0.055
    return int(round(max(0.0, min(1.0, value)) * 255.0))


def pack(sizes, order, width):
    """Guillotine packing into a fixed width, largest first (top-most, then left-most free rectangle)."""
    ranked = sorted(sizes, key=lambda key: (-sizes[key][1], -sizes[key][0], order[key]))
    free = [(0, 0, width, 1 << 30)]
    places, height = {}, 0
    for key in ranked:
        w, h = sizes[key][0] + 2 * GUTTER, sizes[key][1] + 2 * GUTTER
        candidates = [r for r in free if r[2] >= w and r[3] >= h]
        if not candidates:
            return None, 1 << 30
        x, y, rw, rh = min(candidates, key=lambda r: (r[1], r[0]))
        free.remove((x, y, rw, rh))
        # Split the remainder: right of the item (item height), then the full-width strip below.
        if rw - w > 0:
            free.append((x + w, y, rw - w, h))
        if rh - h > 0:
            free.append((x, y + h, rw, rh - h))
        places[key] = (x + GUTTER, y + GUTTER)
        height = max(height, y + h)
    return places, height


def layout(sizes, order, search_width=True):
    """Deterministic smallest-area width (ties: closest to square), no edge above MAX_ATLAS_EDGE.
    Without search_width the SC-HUM-02 single-pose width (two 1024 columns) is kept.
    Returns {key: (x, y)} of each content origin and the atlas size."""
    widest = max(w for w, _ in sizes.values())
    base = max(1024, widest) * 2 + 4 * GUTTER
    best = None
    for width in [base] + list(range(widest + 2 * GUTTER, 4 * 1024 + 8 * GUTTER + 1, 32)):
        places, height = pack(sizes, order, width)
        if places is None:
            continue
        w4, h4 = (width + 3) // 4 * 4, (height + 3) // 4 * 4
        if max(w4, h4) > MAX_ATLAS_EDGE and best is not None:
            continue
        score = (max(w4, h4) > MAX_ATLAS_EDGE, w4 * h4, abs(w4 - h4))
        if best is None or score < best[0]:
            best = (score, places, w4, h4)
        if not search_width:
            break
    return best[1], best[2], best[3]


def resize_rgba(image, width, height):
    """Box/nearest resample for normal maps whose size differs from their diffuse map."""
    ys = (numpy.arange(height) * image.shape[0] // height)
    xs = (numpy.arange(width) * image.shape[1] // width)
    return image[ys][:, xs]


def blit(atlas, image, x, y):
    padded = numpy.pad(image, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode='edge')
    atlas[y - GUTTER:y + image.shape[0] + GUTTER, x - GUTTER:x + image.shape[1] + GUTTER] = padded


def read_parts(source, regions, order):
    """Parts of one exported pose; images are registered in `regions` by content hash (shared across sources)."""
    document = json.loads(source.read_text())
    binary = (source.parent / document['buffers'][0]['uri']).read_bytes()
    images = [source.parent / image['uri'] for image in document['images']]
    nodes = [node for node in document['nodes'] if 'mesh' in node]
    for node in nodes:
        for key in ('matrix', 'rotation', 'scale', 'translation'):
            if key in node and node[key] not in ([0, 0, 0, 1], [1, 1, 1], [0, 0, 0]):
                raise ValueError('Expected identity part transforms: ' + node.get('name', '?'))
    def register(index, prefix=''):
        data = images[index].read_bytes()
        key = prefix + hashlib.sha256(data).hexdigest()
        if key not in regions:
            regions[key] = load_rgba(images[index])
            order[key] = len(order)
        return key
    parts = []
    for node in nodes:
        mesh = document['meshes'][node['mesh']]
        if len(mesh['primitives']) != 1:
            raise ValueError('Expected one primitive per part')
        primitive = mesh['primitives'][0]
        if 'material' not in primitive:
            raise ValueError(mesh['name'] + ' has no material; check the asset .mhclo for a material line')
        material = document['materials'][primitive['material']]
        pbr = material.get('pbrMetallicRoughness', {})
        texture = pbr.get('baseColorTexture')
        normal = material.get('normalTexture')
        image_key = register(document['textures'][texture['index']]['source']) if texture else None
        normal_key = register(document['textures'][normal['index']]['source'], 'n:') if normal and texture else None
        colour = pbr.get('baseColorFactor', [1, 1, 1, 1])
        parts.append({
            'name': mesh['name'], 'class': shading_class(material['name'], texture is not None),
            'image': image_key, 'normal': normal_key,
            'roughness': max(MIN_ROUGHNESS, float(pbr.get('roughnessFactor', 1.0))),
            'swatch': [srgb_byte(c) for c in colour[:3]] + [255],
            'position': read_accessor(document, binary, primitive['attributes']['POSITION']),
            'normal_vectors': read_accessor(document, binary, primitive['attributes']['NORMAL']),
            'uv': read_accessor(document, binary, primitive['attributes']['TEXCOORD_0']),
            'indices': [v[0] for v in read_accessor(document, binary, primitive['indices'])],
        })
    return parts


def merge_many(pairs, atlas_dir, atlas_stem, search_width=True):
    """Merge each (source, output) pose into one mesh; all poses share one diffuse and one normal atlas."""
    regions, order, posed = {}, {}, []
    for source, output in pairs:
        posed.append((source, output, read_parts(source, regions, order)))
    all_parts = [part for _, _, parts in posed for part in parts]
    sizes = {key: (img.shape[1], img.shape[0]) for key, img in regions.items() if not key.startswith('n:')}
    swatch_colours = {tuple(srgb_byte(c) for c in DEFAULT_SWATCH) + (255,)}
    swatch_colours |= {tuple(part['swatch']) for part in all_parts if part['image'] is None}
    for colour in sorted(swatch_colours):
        sizes[('s', colour)] = (SWATCH, SWATCH)
        order[('s', colour)] = len(order)
    places, width, height = layout(sizes, order, search_width)
    atlas = numpy.zeros((height, width, 4), dtype=numpy.uint8)
    for key, (x, y) in places.items():
        if isinstance(key, tuple):
            blit(atlas, numpy.full((SWATCH, SWATCH, 4), key[1], dtype=numpy.uint8), x, y)
        else:
            blit(atlas, regions[key], x, y)
    # Normal atlas: flat everywhere except regions whose part has a normal map; half resolution.
    normals = numpy.zeros((height, width, 4), dtype=numpy.uint8)
    normals[:] = (128, 128, 255, 255)
    for part in all_parts:
        if part['normal'] is not None:
            x, y = places[part['image']]
            w, h = sizes[part['image']]
            source_normal = regions[part['normal']]
            if source_normal.shape[:2] != (h, w):
                source_normal = resize_rgba(source_normal, w, h)
            blit(normals, source_normal, x, y)
    half = normals.reshape(height // 2, 2, width // 2, 2, 4).astype(numpy.float32).mean(axis=(1, 3))
    vectors = half[..., :3] / 127.5 - 1.0
    vectors /= numpy.maximum(numpy.linalg.norm(vectors, axis=2, keepdims=True), 1.0e-6)
    half[..., :3] = (vectors + 1.0) * 127.5
    half[..., 3] = 255
    normal_half = numpy.clip(numpy.rint(half), 0, 255).astype(numpy.uint8)
    atlas_dir.mkdir(parents=True, exist_ok=True)
    write_png(atlas_dir / (atlas_stem + '_atlas.png'), atlas)
    write_png(atlas_dir / (atlas_stem + '_atlas_normal.png'), normal_half)
    reports = []
    for source, output, parts in posed:
        reports.append(write_pose(source, output, parts, places, sizes, width, height,
                                  Path(os.path.relpath(atlas_dir, output.parent)), atlas_stem))
    print('MERGE_REPORT=' + json.dumps({'atlas': [width, height], 'normal_atlas': [width // 2, height // 2],
                                        'regions': len(sizes), 'poses': reports}, sort_keys=True))


def merge(source, output):
    """Single pose with its own atlas next to it (the SC-HUM-02 form)."""
    merge_many([(source, output)], output.parent, output.stem, search_width=False)


def write_pose(source, output, parts, places, sizes, width, height, atlas_rel, atlas_stem):
    positions, normals_out, uv0, uv1, indices = [], [], [], [], []
    for index, part in enumerate(parts):
        base = len(positions)
        if part['image'] is not None:
            x, y = places[part['image']]
            w, h = sizes[part['image']]
            mapped = [((x + u * w) / width, (y + v * h) / height) for u, v in part['uv']]
        else:
            x, y = places[('s', tuple(part['swatch']))]
            centre = ((x + SWATCH * 0.5) / width, (y + SWATCH * 0.5) / height)
            mapped = [centre] * len(part['uv'])
        positions += part['position']
        normals_out += part['normal_vectors']
        uv0 += mapped
        uv1 += [(float(part['class']), part['roughness'])] * len(part['uv'])
        indices += [base + i for i in part['indices']]

    output.parent.mkdir(parents=True, exist_ok=True)
    stem = output.stem
    blobs, views, accessors = [], [], []
    def add(values, kind, component, target=None, bounds=False):
        fmt = '<%d%s' % (len(values[0]) if isinstance(values[0], tuple) else 1, FORMATS[component])
        data = b''.join(struct.pack(fmt, *(v if isinstance(v, tuple) else (v,))) for v in values)
        offset = sum(len(b) for b in blobs)
        blobs.append(data + b'\x00' * (-len(data) % 4))
        view = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(data)}
        if target:
            view['target'] = target
        views.append(view)
        accessor = {'bufferView': len(views) - 1, 'componentType': component, 'count': len(values), 'type': kind}
        if bounds:
            accessor['min'] = [min(v[i] for v in values) for i in range(3)]
            accessor['max'] = [max(v[i] for v in values) for i in range(3)]
        accessors.append(accessor)
        return len(accessors) - 1
    attributes = {
        'POSITION': add([tuple(v) for v in positions], 'VEC3', 5126, 34962, True),
        'NORMAL': add([tuple(v) for v in normals_out], 'VEC3', 5126, 34962),
        'TEXCOORD_0': add(uv0, 'VEC2', 5126, 34962),
        'TEXCOORD_1': add(uv1, 'VEC2', 5126, 34962),
    }
    index_accessor = add(indices, 'SCALAR', 5125, 34963)
    binary_name = stem + '.bin'
    (output.parent / binary_name).write_bytes(b''.join(blobs))
    merged = {
        'asset': {'version': '2.0', 'generator': 'OpenRC merge_people_atlas.py (SC-HUM-02)'},
        'scene': 0, 'scenes': [{'nodes': [0]}],
        'nodes': [{'name': 'Human_atlas', 'mesh': 0}],
        'meshes': [{'name': 'Human_atlas', 'primitives': [{'attributes': attributes, 'indices': index_accessor, 'material': 0}]}],
        'materials': [{'name': 'Human.atlas', 'doubleSided': True, 'alphaMode': 'BLEND',
                       'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 1.0},
                       'normalTexture': {'index': 1}}],
        'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}],
        'samplers': [{'magFilter': 9729, 'minFilter': 9987}],
        'images': [{'uri': (atlas_rel / (atlas_stem + '_atlas.png')).as_posix()},
                   {'uri': (atlas_rel / (atlas_stem + '_atlas_normal.png')).as_posix()}],
        'buffers': [{'uri': binary_name, 'byteLength': sum(len(b) for b in blobs)}],
        'bufferViews': views, 'accessors': accessors,
    }
    output.write_text(json.dumps(merged, indent=1, sort_keys=True))
    return {'source': source.name, 'output': output.name,
            'parts': [{'name': p['name'], 'class': p['class'], 'roughness': p['roughness'], 'vertices': len(p['position']),
                       'triangles': len(p['indices']) // 3} for p in parts],
            'vertices': len(positions), 'triangles': len(indices) // 3}


if __name__ == '__main__':
    arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if len(arguments) == 2 and arguments[1].endswith('.gltf'):
        merge(Path(arguments[0]).resolve(), Path(arguments[1]).resolve())
    elif len(arguments) >= 3 and arguments[0] == '--shared':
        # --shared OUT_DIR ATLAS_STEM SOURCE.gltf...: each pose to OUT_DIR/<source stem>.gltf, one shared atlas.
        out_dir, stem = Path(arguments[1]).resolve(), arguments[2]
        # Sorted by file name, so the atlas layout does not depend on the command-line order.
        sources = sorted((Path(a).resolve() for a in arguments[3:]), key=lambda path: path.name)
        merge_many([(s, out_dir / s.name) for s in sources], out_dir, stem)
    else:
        raise SystemExit('usage: merge_people_atlas.py -- SOURCE.gltf OUTPUT.gltf | --shared OUT_DIR ATLAS_STEM SOURCE.gltf...')
