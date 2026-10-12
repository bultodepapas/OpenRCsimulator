"""LU-21: externalize exact glTF/GLB image bytes once per SHA-256, without re-encoding.

Usage: python package_population.py SOURCE.glb|SOURCE.gltf OUTPUT.glb
Writes shared textures next to OUTPUT, a compact GLB, and an input/output hash record.
Only glTF 2.0 single-BIN Blender exports with local PNG/JPEG images are supported.
Data URIs and compressed mesh extensions are unsupported. No downloaded code is executed.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def package(source, destination):
    raw = source.read_bytes()
    magic, version = 0x46546C67, 2
    inputs = []
    if source.suffix == '.gltf':
        document = json.loads(raw)
        binary_path = source.parent / document['buffers'][0]['uri']
        binary = binary_path.read_bytes()
        inputs.append({'file': binary_path.name, 'sha256': digest(binary), 'bytes': len(binary)})
    else:
        read_magic, read_version, total = struct.unpack_from('<III', raw)
        if read_magic != magic or read_version != version or total != len(raw):
            raise ValueError('Expected valid GLB 2.0')
        chunks = {}
        offset = 12
        while offset < len(raw):
            length, kind = struct.unpack_from('<II', raw, offset)
            chunks[kind] = raw[offset + 8:offset + 8 + length]
            offset += 8 + length
        document = json.loads(chunks[0x4E4F534A])
        binary = chunks[0x004E4942]
    if len(document['buffers']) != 1:
        raise ValueError('Expected one binary buffer')
    destination.parent.mkdir(parents=True, exist_ok=True)
    textures = destination.parent / 'textures'
    textures.mkdir(exist_ok=True)
    image_views = set()
    image_records = []
    for image in document.get('images', []):
        if 'bufferView' in image:
            index = image.pop('bufferView')
            view = document['bufferViews'][index]
            data = binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']]
            mime = image.pop('mimeType')
            extension = {'image/png': '.png', 'image/jpeg': '.jpg'}[mime]
            image_views.add(index)
        else:
            image_path = source.parent / image.pop('uri')
            data = image_path.read_bytes()
            extension = image_path.suffix
            if extension not in ['.png', '.jpg', '.jpeg']:
                raise ValueError('Unexpected image format')
            inputs.append({'file': image_path.name, 'sha256': digest(data), 'bytes': len(data)})
        filename = digest(data) + extension
        path = textures / filename
        if path.exists() and path.read_bytes() != data:
            raise ValueError('Texture hash collision')
        path.write_bytes(data)
        image['uri'] = 'textures/' + filename
        image_records.append({'name': image.get('name', ''), 'path': image['uri'], 'sha256': digest(data), 'bytes': len(data)})
    output = bytearray()
    views = []
    mapping = {}
    for index, view in enumerate(document['bufferViews']):
        if index in image_views:
            continue
        if view.get('buffer', 0) != 0:
            raise ValueError('Unexpected external buffer')
        output.extend(b'\0' * (-len(output) % 4))
        start = view.get('byteOffset', 0)
        replacement = dict(view, byteOffset=len(output))
        output.extend(binary[start:start + view['byteLength']])
        mapping[index] = len(views)
        views.append(replacement)
    for accessor in document.get('accessors', []):
        if 'bufferView' in accessor:
            accessor['bufferView'] = mapping[accessor['bufferView']]
        if 'sparse' in accessor:
            for key in ['indices', 'values']:
                item = accessor['sparse'][key]
                item['bufferView'] = mapping[item['bufferView']]
    # These exports intentionally contain no compressed mesh bufferView extension.
    for mesh in document.get('meshes', []):
        for primitive in mesh['primitives']:
            if 'KHR_draco_mesh_compression' in primitive.get('extensions', {}):
                raise ValueError('Compressed glTF is not accepted by this recipe')
    document['bufferViews'] = views
    document['buffers'] = [{'byteLength': len(output)}]
    encoded = json.dumps(document, separators=(',', ':'), ensure_ascii=False).encode('utf8')
    encoded += b' ' * (-len(encoded) % 4)
    output.extend(b'\0' * (-len(output) % 4))
    packed = struct.pack('<III', magic, version, 28 + len(encoded) + len(output))
    packed += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
    packed += struct.pack('<II', len(output), 0x004E4942) + output
    destination.write_bytes(packed)
    result = {'source': source.name, 'source_sha256': digest(raw), 'output': destination.name,
              'output_sha256': digest(packed), 'geometry_bytes': len(packed), 'images': image_records, 'source_dependencies': inputs}
    destination.with_suffix('.source.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf8')
    print(json.dumps({k: v for k, v in result.items() if k not in ['images', 'source_dependencies']}))


if __name__ == '__main__':
    package(Path(sys.argv[1]), Path(sys.argv[2]))
