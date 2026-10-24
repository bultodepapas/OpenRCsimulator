"""SC-HUM-02: merge one exported field-person glTF into a single mesh with one atlas material.

Run through Blender 5.2.2 (for its bundled numpy and PNG reader) after generate_people.py:

    blender --background --factory-startup --python tools/scenery/population/merge_people_atlas.py -- \
        SOURCE.gltf OUTPUT.gltf

Each source part keeps its geometry, normals and UVs exactly; UVs are remapped into a diffuse atlas
with edge-extended gutters (no mip bleeding between parts) and a half-resolution normal atlas. The
second UV set carries (shading class, roughness) so one runtime material reproduces the per-part
shading: 0 skin, 1 fabric, 2 plain, 3 eyes (also marks the eye height for the head rig),
4 untextured transmitter. PNGs are written with zlib directly, so equal pixels give equal bytes.
Then package the result with package_population.py as before.
"""

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
    if not has_texture:
        return CLASS_FLAT
    if name.endswith('.body'):
        return CLASS_SKIN
    if 'suit' in name or 'shirt' in name or 'pants' in name:
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


def layout(sizes):
    """Guillotine packing into a fixed width, largest first, deterministic (top-most, then left-most free
    rectangle). Returns {key: (x, y)} of each content origin and the atlas size."""
    order = sorted(sizes, key=lambda key: (-sizes[key][1], -sizes[key][0], str(key)))
    width = max(1024, max(w for w, _ in sizes.values())) * 2 + 4 * GUTTER
    free = [(0, 0, width, 1 << 30)]
    places, height = {}, 0
    for key in order:
        w, h = sizes[key][0] + 2 * GUTTER, sizes[key][1] + 2 * GUTTER
        candidates = [r for r in free if r[2] >= w and r[3] >= h]
        x, y, rw, rh = min(candidates, key=lambda r: (r[1], r[0]))
        free.remove((x, y, rw, rh))
        # Split the remainder: right of the item (item height), then the full-width strip below.
        if rw - w > 0:
            free.append((x + w, y, rw - w, h))
        if rh - h > 0:
            free.append((x, y + h, rw, rh - h))
        places[key] = (x + GUTTER, y + GUTTER)
        height = max(height, y + h)
    # Even dimensions keep the half-resolution normal atlas aligned; multiples of 4 suit VRAM compression.
    return places, (width + 3) // 4 * 4, (height + 3) // 4 * 4


def blit(atlas, image, x, y):
    padded = numpy.pad(image, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode='edge')
    atlas[y - GUTTER:y + image.shape[0] + GUTTER, x - GUTTER:x + image.shape[1] + GUTTER] = padded


def merge(source, output):
    document = json.loads(source.read_text())
    binary = (source.parent / document['buffers'][0]['uri']).read_bytes()
    images = [source.parent / image['uri'] for image in document['images']]
    nodes = [node for node in document['nodes'] if 'mesh' in node]
    for node in nodes:
        for key in ('matrix', 'rotation', 'scale', 'translation'):
            if key in node and node[key] not in ([0, 0, 0, 1], [1, 1, 1], [0, 0, 0]):
                raise ValueError('Expected identity part transforms: ' + node.get('name', '?'))
    parts = []
    regions = {}
    for node in nodes:
        mesh = document['meshes'][node['mesh']]
        if len(mesh['primitives']) != 1:
            raise ValueError('Expected one primitive per part')
        primitive = mesh['primitives'][0]
        material = document['materials'][primitive['material']]
        pbr = material.get('pbrMetallicRoughness', {})
        texture = pbr.get('baseColorTexture')
        image_index = document['textures'][texture['index']]['source'] if texture else None
        normal = material.get('normalTexture')
        normal_index = document['textures'][normal['index']]['source'] if normal else None
        kind = shading_class(material['name'], texture is not None)
        if image_index is not None and image_index not in regions:
            regions[image_index] = load_rgba(images[image_index])
        if normal_index is not None and ('n', normal_index) not in regions:
            regions[('n', normal_index)] = load_rgba(images[normal_index])
        colour = pbr.get('baseColorFactor', [1, 1, 1, 1])
        parts.append({
            'name': mesh['name'], 'class': kind, 'image': image_index, 'normal': normal_index,
            'roughness': max(MIN_ROUGHNESS, float(pbr.get('roughnessFactor', 1.0))),
            'swatch': [srgb_byte(c) for c in colour[:3]] + [255],
            'position': read_accessor(document, binary, primitive['attributes']['POSITION']),
            'normal_vectors': read_accessor(document, binary, primitive['attributes']['NORMAL']),
            'uv': read_accessor(document, binary, primitive['attributes']['TEXCOORD_0']),
            'indices': [v[0] for v in read_accessor(document, binary, primitive['indices'])],
        })
    sizes = {key: (img.shape[1], img.shape[0]) for key, img in regions.items() if not isinstance(key, tuple)}
    swatch_colours = {tuple(srgb_byte(c) for c in DEFAULT_SWATCH) + (255,)}
    swatch_colours |= {tuple(part['swatch']) for part in parts if part['image'] is None}
    for colour in swatch_colours:
        sizes[('s', colour)] = (SWATCH, SWATCH)
    places, width, height = layout(sizes)
    atlas = numpy.zeros((height, width, 4), dtype=numpy.uint8)
    for key, (x, y) in places.items():
        if isinstance(key, tuple) and key[0] == 's':
            blit(atlas, numpy.full((SWATCH, SWATCH, 4), key[1], dtype=numpy.uint8), x, y)
        elif not isinstance(key, tuple):
            blit(atlas, regions[key], x, y)
    # Normal atlas: flat everywhere except regions whose part has a normal map; half resolution.
    normals = numpy.zeros((height, width, 4), dtype=numpy.uint8)
    normals[:] = (128, 128, 255, 255)
    for part in parts:
        if part['normal'] is not None and part['image'] is not None:
            x, y = places[part['image']]
            source_normal = regions[('n', part['normal'])]
            w, h = sizes[part['image']]
            if source_normal.shape[:2] != (h, w):
                raise ValueError('Normal map must match its diffuse size')
            blit(normals, source_normal, x, y)
    half = normals.reshape(height // 2, 2, width // 2, 2, 4).astype(numpy.float32).mean(axis=(1, 3))
    vectors = half[..., :3] / 127.5 - 1.0
    vectors /= numpy.maximum(numpy.linalg.norm(vectors, axis=2, keepdims=True), 1.0e-6)
    half[..., :3] = (vectors + 1.0) * 127.5
    half[..., 3] = 255
    normal_half = numpy.clip(numpy.rint(half), 0, 255).astype(numpy.uint8)

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
    write_png(output.parent / (stem + '_atlas.png'), atlas)
    write_png(output.parent / (stem + '_atlas_normal.png'), normal_half)
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
        'images': [{'uri': stem + '_atlas.png'}, {'uri': stem + '_atlas_normal.png'}],
        'buffers': [{'uri': binary_name, 'byteLength': sum(len(b) for b in blobs)}],
        'bufferViews': views, 'accessors': accessors,
    }
    output.write_text(json.dumps(merged, indent=1, sort_keys=True))
    report = {'source': source.name, 'output': output.name, 'atlas': [width, height], 'normal_atlas': [width // 2, height // 2],
              'parts': [{'name': p['name'], 'class': p['class'], 'roughness': p['roughness'], 'vertices': len(p['position']),
                         'triangles': len(p['indices']) // 3} for p in parts],
              'vertices': len(positions), 'triangles': len(indices) // 3}
    print('MERGE_REPORT=' + json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if len(arguments) != 2:
        raise SystemExit('usage: blender --background --factory-startup --python merge_people_atlas.py -- SOURCE.gltf OUTPUT.gltf')
    merge(Path(arguments[0]).resolve(), Path(arguments[1]).resolve())
