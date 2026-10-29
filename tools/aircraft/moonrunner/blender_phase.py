"""Run one MoonRunner derivative phase inside the official Blender Lab MCP bridge.

Arguments are supplied by lab.py in RUN_ARGS, never read from untrusted model data.
The immutable source delivery and existing stock GLB are read only.
"""
from pathlib import Path
import hashlib
import json
import os
import struct
import sys
import traceback

import bpy

repo = Path(RUN_ARGS['repo']).resolve()
work = Path(RUN_ARGS['work']).resolve()
deps = Path(RUN_ARGS['deps']).resolve()
phase = RUN_ARGS['phase']
delivery = repo / 'assets/source-deliveries/skywalker-x8-r4/skywalker_x8/r4/source'
scripts = delivery / 'scripts'
stock = repo / 'app/assets/aircraft/skywalker-x8/skywalker_x8.glb'
blend = delivery / 'aircraft_game.blend'
assert work != repo and not work.is_relative_to(delivery) and not work.is_relative_to(repo / 'app')
work.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(deps))

PINS = {
    blend: 'c0951a4e6f50e150bada31d1e850dea30d589f7eca99410faa9475fbafdc24f7',
    stock: '3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac',
    scripts / 'livery_bake_geom.py': '257d679037864a9fe445b5b16013af89641654c3a574d3ea1f8dd25302a20dda',
    scripts / 'livery_paint.py': 'b1441ecb5066465f1dab861fd01e9abd70dd5999bd1e8bf995e0fab28ace95ac',
    scripts / 'x8_game_spec.py': 'd0288333f410ce09a135e9e2cdc50863933d0c5d0027e6a9e49068959515d4e0',
    scripts / 'x8_skywalker_blender.py': 'a217e027d2c2fa5e3f8057f2e7d87385c0f3720bb19680ddcf3d6bd59b27cec4',
    scripts / 'export_glb.py': '03d42dfc9f93890c230ec04ec6054156d8747af976677174379a9e08739acbd6',
    Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'): '5c1247acef7f2b8522a31742c76d6adcb5569bacc0be7ceaa4dc39dd252ce895',
    Path('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'): '3a3c502eeff669a231549e80df9f7c49de109bafe303170409e905d0b31a38fe',
}
MAP_PINS = {
    'P.npy': '0d9bd4074b8e9fcce454af0e3571410e2b93ffe11e52b5747b1703b6d8ae1790',
    'N.npy': '457c95f28234427bc98a3b4626bc045aa0fb7557b6e06d53d39a5c38f9d1b664',
    'ID.npz': '9ac534e6a27979a4edc99f97b4390d12a79d1344b398f36a14530e6055fb32f3',
    'build_info.json': 'f7da21834381dbb7ecb531ac2030a4796efb250c3edfb57cf2a3a60270606eb4',
}
PAINT_PINS = {
    'baseline': '3fcbb0cc2b0968530dc186eb8a4f5a101700d7958dbd527d896c0009e8470738',
    'blank': '83f51c94e4f4c9c1413458c8c7ef59b26caeaec30dddf3d91c4071888a1a98e1',
    'candidate': '2575e5e71169bf9733b53d6b6c6959e1e239fc66cfc402b9dcd99b5a9976cff5',
}
BASE_HASH = '99eee6bf2fd358a9867e96ed0ab64b9c053aced18ab6f5d0367e514153dd9247'
ATLAS_HASH = '7d1cac4fac2b15a3da0ae97de35b0e1fd450249b30fca7167ad7b5eaaf43660c'
GLB_HASH = '54d67d9bbfe4ce4abdc4bafa523c3bf812422d6336ba1d0f151a2970e087b0f0'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def require_hash(path, expected):
    actual = digest(path)
    if actual != expected:
        raise RuntimeError(f'hash mismatch for {path}: {actual} != {expected}')


def verify_inputs():
    if tuple(bpy.app.version) != (5, 2, 2):
        raise RuntimeError(f'Expected Blender 5.2.2, got {bpy.app.version_string}')
    import numpy, PIL, scipy, matplotlib
    versions = (numpy.__version__, PIL.__version__, scipy.__version__, matplotlib.__version__)
    if versions != ('2.3.4', '12.3.0', '1.17.1', '3.10.7'):
        raise RuntimeError(f'Unexpected dependency versions: {versions}')
    for path, expected in PINS.items():
        require_hash(path, expected)
    # The original painter falls back to the pinned Bold font when Condensed is absent.
    if Path('/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf').exists():
        raise RuntimeError('Unexpected condensed font: baseline would not reproduce')
    sys.path.insert(0, str(scripts))


def fresh_scene():
    scene_path = Path(bpy.data.filepath).resolve()
    if scene_path == blend.resolve() or scene_path.is_relative_to(delivery):
        raise RuntimeError('Open a scratch copy of the immutable Blender file')
    require_hash(scene_path, PINS[blend])
    if bpy.data.is_dirty:
        raise RuntimeError('Open a fresh, unmodified scratch scene for this phase')


def verify_maps():
    maps = work / 'maps-v3'
    for name, expected in MAP_PINS.items():
        require_hash(maps / name, expected)
    return maps


def run_bake():
    fresh_scene()
    import x8_game_spec as spec
    maps = work / 'maps-v3'
    if maps.exists():
        raise RuntimeError(f'Refusing to overwrite {maps}')
    src = scripts / 'livery_bake_geom.py'
    text = src.read_text(encoding='utf-8')
    line = 'bpy.ops.wm.open_mainfile(filepath=BLEND)'
    if text.count(line) != 1 or text.count('# dibujo del UV para editar a mano') != 1:
        raise RuntimeError('Unexpected delivered bake source')
    # Scene is already the hash-verified scratch copy; omit only UV preview output.
    text = text.replace(line, '# scene already loaded').split('# dibujo del UV para editar a mano')[0]
    old_argv = sys.argv[:]
    try:
        sys.argv = ['blender', '--', str(Path(bpy.data.filepath)), str(maps), '4096']
        objects = [bpy.data.objects[name] for name in spec.LIVERY_PARTS]
        with bpy.context.temp_override(scene=bpy.context.scene, view_layer=bpy.context.view_layer,
                                       object=objects[0], active_object=objects[0],
                                       selected_objects=objects, selected_editable_objects=objects):
            exec(compile(text, str(src), 'exec'), {'__file__': str(src), '__name__': '__main__'})
    finally:
        sys.argv = old_argv
    verify_maps()


def run_paint(mode):
    maps = verify_maps()
    dest = work / f'paint-{mode}-v2'
    if dest.exists():
        raise RuntimeError(f'Refusing to overwrite {dest}')
    src = scripts / 'livery_paint.py'
    text = src.read_text(encoding='utf-8')
    replacements = {
        'text_image(["X8·08"], F_BOLD, 2.0 if SUB == 1 else 1.0, 120)': 'text_image(["MoonRunner", "X99"], F_BOLD, 2.0 if SUB == 1 else 1.0, 58, align="center")',
        'text_image(["EPO · X8 · 2120 · SN 0811-ABY"], F_MONO, PX, 4.5)': 'text_image(["EPO · MoonRunner X99 · 2120 · SN 0811-ABY"], F_MONO, PX, 3.0)',
    }
    for old, new in replacements.items():
        if text.count(old) != 1:
            raise RuntimeError(f'Expected unique source stencil: {old}')
        if mode == 'candidate':
            text = text.replace(old, new)
        elif mode == 'blank':
            text = text.replace(old, old + '\n' + ('    ' if 'EPO' in old else '') + 'img[:] = 0.0')
    old_argv = sys.argv[:]
    try:
        sys.argv = ['blender', '--', str(maps), str(dest)]
        exec(compile(text, str(src), 'exec'), {'__file__': str(src), '__name__': '__main__'})
    finally:
        sys.argv = old_argv
    require_hash(dest / 'x8_abisal_base_color.png', PAINT_PINS[mode])


def glb(path):
    data = path.read_bytes()
    if data[:4] != b'glTF' or struct.unpack_from('<I', data, 4)[0] != 2:
        raise RuntimeError(f'Not a glTF 2 GLB: {path}')
    size, kind = struct.unpack_from('<II', data, 12)
    if kind != 0x4E4F534A:
        raise RuntimeError('Missing JSON chunk')
    doc = json.loads(data[20:20 + size])
    start = 20 + size
    length, kind = struct.unpack_from('<II', data, start)
    if kind != 0x004E4942:
        raise RuntimeError('Missing binary chunk')
    return doc, data[start + 8:start + 8 + length]


def image_bytes(doc, binary, image):
    view = doc['bufferViews'][image['bufferView']]
    start = view.get('byteOffset', 0)
    return binary[start:start + view['byteLength']]


def run_compose():
    import io
    import numpy as np
    from PIL import Image
    original_doc, original_bin = glb(stock)
    original_image = next(i for i in original_doc['images'] if i.get('name') == 'x8_abisal_base_color')
    raw = image_bytes(original_doc, original_bin, original_image)
    if hashlib.sha256(raw).hexdigest() != BASE_HASH:
        raise RuntimeError('Shipped packed base image mismatch')
    original = np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'), dtype=np.int16)
    arrays = {}
    for mode, expected in PAINT_PINS.items():
        path = work / f'paint-{mode}-v2/x8_abisal_base_color.png'
        require_hash(path, expected)
        image = Image.open(path).convert('RGB')
        if image.size != (4096, 4096):
            raise RuntimeError(f'Unexpected paint dimensions: {mode}')
        arrays[mode] = np.asarray(image.resize((2048, 2048), Image.Resampling.LANCZOS), dtype=np.int16)
    old_mask = np.any(arrays['baseline'] != arrays['blank'], axis=2)
    new_mask = np.any(arrays['candidate'] != arrays['blank'], axis=2)
    mask = old_mask | new_mask
    delta = arrays['candidate'] - arrays['baseline']
    if np.any(delta[~mask]):
        raise RuntimeError('Candidate differs outside the old/new marking mask')
    result = original.copy()
    unclipped = original + delta
    result[mask] = np.clip(unclipped[mask], 0, 255)
    if np.any(result[~mask] != original[~mask]):
        raise RuntimeError('Composite changed pixels outside marking mask')
    out = work / 'moonrunner-base-scratch.png'
    if out.exists():
        raise RuntimeError(f'Refusing to overwrite {out}')
    Image.fromarray(result.astype(np.uint8), 'RGB').save(out)
    require_hash(out, ATLAS_HASH)
    if not np.array_equal(np.asarray(Image.open(out).convert('RGB'), dtype=np.int16), result):
        raise RuntimeError('PNG is not lossless')
    error = np.abs(original - arrays['baseline'])
    encoded = io.BytesIO()
    Image.fromarray(arrays['baseline'].astype(np.uint8), 'RGB').save(encoded, format='JPEG', quality=92, subsampling=0)
    rebuilt_jpeg = np.asarray(Image.open(io.BytesIO(encoded.getvalue())).convert('RGB'), dtype=np.int16)
    jpeg_error = np.abs(original - rebuilt_jpeg)
    pixel_error = jpeg_error.max(axis=2)
    evidence = {'baseline_jpeg_sha256': hashlib.sha256(encoded.getvalue()).hexdigest(),
                'baseline_jpeg_mean_channel_error': float(jpeg_error.mean()),
                'baseline_jpeg_fraction_pixels_different': float((pixel_error > 0).mean()),
                'baseline_jpeg_fraction_pixels_error_over_5': float((pixel_error > 5).mean()),
                'old_mask_pixels': int(old_mask.sum()), 'new_mask_pixels': int(new_mask.sum()),
                'union_mask_pixels': int(mask.sum()), 'outside_mask_changed_pixels': 0,
                'changed_pixels': int(np.any(result != original, axis=2).sum()),
                'clipped_channels': int(np.count_nonzero((unclipped < 0) | (unclipped > 255))),
                'baseline_error_in_mask_mean': float(error[mask].mean()),
                'baseline_error_in_mask_p99': float(np.percentile(error[mask], 99)),
                'atlas_sha256': digest(out)}
    (work / 'mask-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')


def verify_export(path):
    require_hash(path, GLB_HASH)
    a, ab = glb(stock)
    b, bb = glb(path)
    for key in ('scene', 'scenes', 'nodes', 'meshes', 'accessors', 'materials', 'textures', 'samplers'):
        if a.get(key) != b.get(key):
            raise RuntimeError(f'Export changed glTF {key}')
    for i, (old, new) in enumerate(zip(a['accessors'], b['accessors'])):
        va, vb = a['bufferViews'][old['bufferView']], b['bufferViews'][new['bufferView']]
        xa = ab[va.get('byteOffset', 0):va.get('byteOffset', 0) + va['byteLength']]
        xb = bb[vb.get('byteOffset', 0):vb.get('byteOffset', 0) + vb['byteLength']]
        if xa != xb:
            raise RuntimeError(f'Geometry buffer differs at accessor {i}')
    old_images = {i['name']: hashlib.sha256(image_bytes(a, ab, i)).hexdigest() for i in a['images']}
    new_images = {i['name']: hashlib.sha256(image_bytes(b, bb, i)).hexdigest() for i in b['images']}
    for name in ('x8_abisal_emission', 'x8_abisal_normal', 'x8_abisal_orm'):
        if old_images[name] != new_images[name]:
            raise RuntimeError(f'Non-base texture changed: {name}')
    if old_images['x8_abisal_base_color'] != BASE_HASH or new_images['moonrunner-base-scratch'] != ATLAS_HASH:
        raise RuntimeError('Unexpected base texture')
    evidence = {'source_glb_sha256': digest(stock), 'derived_glb_sha256': digest(path),
                'nodes': len(a['nodes']), 'meshes': len(a['meshes']),
                'identical_geometry_accessor_views': len(a['accessors']),
                'identical_materials': len(a['materials']), 'original_images': old_images,
                'derived_images': new_images}
    (work / 'export-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')


def run_export():
    fresh_scene()
    atlas = work / 'moonrunner-base-scratch.png'
    require_hash(atlas, ATLAS_HASH)
    out = work / 'moonrunner-experiment.glb'
    if out.exists():
        raise RuntimeError(f'Refusing to overwrite {out}')
    mat = bpy.data.materials['x8_livery']
    nodes = [n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image and n.image.name == 'x8_abisal_base_color.jpg']
    if len(nodes) != 1 or nodes[0].image.colorspace_settings.name != 'sRGB':
        raise RuntimeError('Unexpected material base image')
    image = bpy.data.images.load(str(atlas), check_existing=False)
    image.colorspace_settings.name = 'sRGB'
    image.pack()
    nodes[0].image = image
    source = scripts / 'export_glb.py'
    ns = {'__file__': str(source), '__name__': 'moonrunner_export'}
    exec(compile(source.read_text(encoding='utf-8'), str(source), 'exec'), ns)
    bpy.context.scene.frame_set(1)
    obj = bpy.data.objects['fuselage_core']
    window = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=window, screen=window.screen, scene=bpy.context.scene,
                                   view_layer=bpy.context.view_layer, object=obj, active_object=obj,
                                   selected_objects=[obj], selected_editable_objects=[obj]):
        ns['export'](str(out))
    verify_export(out)


marker = work / f'{phase}.complete'
failed = work / f'{phase}.failed'
if marker.exists() or failed.exists():
    raise RuntimeError(f'Phase already attempted: {phase}')
try:
    verify_inputs()
    if phase == 'bake':
        run_bake()
    elif phase in ('baseline', 'blank', 'candidate'):
        run_paint(phase)
    elif phase == 'compose':
        run_compose()
    elif phase == 'export':
        run_export()
    else:
        raise ValueError(f'Unknown phase {phase}')
    marker.write_text('ok\n', encoding='utf-8')
    print('MOONRUNNER_PHASE_COMPLETE', phase)
except BaseException:
    failed.write_text(traceback.format_exc(), encoding='utf-8')
    raise
