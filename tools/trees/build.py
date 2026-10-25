"""Reproducible L6a offline tree assets; no writes to the runtime tree.

npm ci --prefix tools/trees
$(app/tests/visual-env.sh) tools/trees/build.py --out /tmp/trees-bake
Copy verified artifacts only after reviewing reports. --out must be empty.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
IDS = ('CommonTree_1', 'CommonTree_3', 'Pine_1')
LANDSCAPELAB_DIR = ROOT / 'assets/landscape/vegetation/source/landscapelab_tree_2026'
MAPLE_DIR = ROOT / 'assets/landscape/vegetation/derived/lolipop_maple_2026'
MAPLE_SOURCE_DIR = ROOT / 'assets/landscape/vegetation/source/lolipop_maple_2026'

REALISTIC_PINS = {
    'quercus_sha256': 'd4fb683939a0a6e28fb1ff409cbc73c306207f093bfcb40110ff1fe79fabbd1e',
    'pine_sha256': '74d3d4d0f541522163b1e4d24931e76640df6fdd758db0f963d109faf1a9bcf8',
    'landscapelab_readme_sha256': '87680a80f2fe326c387b1ed79c9a1a043fe0b0ce7e72d7f9ba2efe46c462e276',
    'landscapelab_license_sha256': 'f05b5077b3793eb19f9184cbbce49d777d8183aa862af50de9ae1833578f3922',
    'maple_manifest_sha256': 'ec1c882ee6045dbae5e7499fda2747da646db9c2fe2e0ecfc35af9cf1fe71421',
    'maple_source_sha256': 'ba5eb469c725d00eb8160b335211a2ab064f17669beccc3f93b6b63b62ead942',
    'maple_license_sha256': '56e3dda18eef50e5b1a4fd321fcb914d25c03bb0f5b3648590afe8bfe209f574',
}


def _absolute(path: Path) -> str:
    return str(path.resolve())


def _pin(path: Path, expected: str, label: str) -> dict[str, str]:
    actual = sha(path)
    if actual != expected:
        raise RuntimeError(f'{label} hash drift: expected {expected}, got {actual} ({path})')
    return {'path': _absolute(path), 'sha256': expected}


def realistic_recipe() -> dict:
    """Create the explicitly pinned realistic tree set without editing any source asset."""
    landscape_license = _pin(LANDSCAPELAB_DIR / 'LICENSE_LANDSCAPELAB.txt',
                             REALISTIC_PINS['landscapelab_license_sha256'], 'LandscapeLab license')
    landscape_readme = _pin(LANDSCAPELAB_DIR / 'README.md',
                            REALISTIC_PINS['landscapelab_readme_sha256'], 'LandscapeLab provenance')
    quercus = _pin(LANDSCAPELAB_DIR / 'quercus.glb', REALISTIC_PINS['quercus_sha256'], 'LandscapeLab Quercus')
    pine = _pin(LANDSCAPELAB_DIR / 'pine_joined.glb', REALISTIC_PINS['pine_sha256'], 'LandscapeLab Pine')

    conversion_manifest_path = MAPLE_DIR / 'conversion_manifest.json'
    conversion_manifest_pin = _pin(conversion_manifest_path,
                                   REALISTIC_PINS['maple_manifest_sha256'], 'LOLIPOP maple conversion manifest')
    conversion = json.loads(conversion_manifest_path.read_text(encoding='utf-8'))
    output_entries = {entry['path']: entry for entry in conversion['outputs']}
    model_relative = 'maple_large_3_lod1.gltf'
    model_entry = output_entries.get(model_relative)
    if model_entry is None or model_entry['sha256'] != REALISTIC_PINS['maple_source_sha256']:
        raise RuntimeError('LOLIPOP maple conversion manifest does not pin the expected glTF')
    dependencies = []
    for relative, entry in sorted(output_entries.items()):
        if relative == model_relative:
            continue
        dependency_path = MAPLE_DIR / relative
        if sha(dependency_path) != entry['sha256']:
            raise RuntimeError(f'LOLIPOP maple dependency hash drift: {dependency_path}')
        uri = Path(relative).as_posix()
        # The model and its sidecars share MAPLE_DIR, so URI spelling must match glTF exactly.
        dependencies.append({'uri': uri, 'sha256': entry['sha256']})

    maple_license = _pin(MAPLE_SOURCE_DIR / 'LICENSE_MAPLE.txt',
                         REALISTIC_PINS['maple_license_sha256'], 'LOLIPOP maple license')
    maple_model = _pin(MAPLE_DIR / model_relative, REALISTIC_PINS['maple_source_sha256'], 'LOLIPOP maple glTF')
    return {
        'format': 'openrc-tree-source-recipe v1',
        'recipe_id': 'realistic-trees-2026-10-20-v1',
        'species': [
            {
                'id': 'CommonTree_1', 'source_asset_id': 'landscapelab:quercus',
                'source_path': quercus['path'], 'source_sha256': quercus['sha256'], 'dependencies': [],
                'bark_material_name': 'branches', 'foliage_material_name': 'leaves',
                'pinned_files': [
                    {**landscape_license, 'role': 'license'},
                    {**landscape_readme, 'role': 'source-provenance'},
                ],
                'provenance': {
                    'creator': 'LandscapeLab Assets contributors', 'license': 'CC BY-SA 4.0',
                    'source_url': 'https://github.com/boku-ilen/landscapelab-assets/blob/dfdde034c3547f9876967653d98827bd5348e52e/Natural/Plants/Trees/Quercus/quercus.glb',
                    'source_revision': 'dfdde034c3547f9876967653d98827bd5348e52e',
                    'source_title': 'Quercus tree asset',
                },
            },
            {
                'id': 'CommonTree_3', 'source_asset_id': 'lolipop:acer_large_3_lod1',
                'source_path': maple_model['path'], 'source_sha256': maple_model['sha256'],
                'dependencies': dependencies,
                'bark_material_name': 'Maple_Bark_PBR', 'foliage_material_name': 'Maple_Leaves_PBR',
                'pinned_files': [
                    {**maple_license, 'role': 'license'},
                    {**conversion_manifest_pin, 'role': 'conversion-manifest'},
                ],
                'provenance': {
                    'creator': 'LOLIPOP (@lolipop_1707)', 'license': 'CC BY 4.0',
                    'source_url': conversion['source']['url'],
                    'source_revision': conversion['source']['archive']['sha256'],
                    'source_title': conversion['source']['name'],
                },
            },
            {
                'id': 'Pine_1', 'source_asset_id': 'landscapelab:pine',
                'source_path': pine['path'], 'source_sha256': pine['sha256'], 'dependencies': [],
                'bark_material_name': 'branches.001', 'foliage_material_name': 'leaves.001',
                'pinned_files': [
                    {**landscape_license, 'role': 'license'},
                    {**landscape_readme, 'role': 'source-provenance'},
                ],
                'provenance': {
                    'creator': 'LandscapeLab Assets contributors', 'license': 'CC BY-SA 4.0',
                    'source_url': 'https://github.com/boku-ilen/landscapelab-assets/blob/dfdde034c3547f9876967653d98827bd5348e52e/Natural/Plants/Trees/Pine/pine_joined.glb',
                    'source_revision': 'dfdde034c3547f9876967653d98827bd5348e52e',
                    'source_title': 'Joined pine tree asset',
                },
            },
        ],
    }


def normalize_user_recipe(path: Path) -> tuple[dict, str]:
    """Resolve user recipe file paths before staging it beside the build evidence."""
    recipe_path = path.resolve()
    raw = recipe_path.read_bytes()
    recipe = json.loads(raw)
    if recipe.get('format') != 'openrc-tree-source-recipe v1':
        raise RuntimeError('source recipe must use openrc-tree-source-recipe v1')
    if not isinstance(recipe.get('species'), list):
        raise RuntimeError('source recipe must contain a species array')
    for item in recipe['species']:
        item['source_path'] = _absolute((recipe_path.parent / item['source_path']).resolve()) \
            if not Path(item['source_path']).is_absolute() else _absolute(Path(item['source_path']))
        for pin in item.get('pinned_files', []):
            pin_path = Path(pin['path'])
            pin['path'] = _absolute((recipe_path.parent / pin_path).resolve() if not pin_path.is_absolute() else pin_path)
    return recipe, hashlib.sha256(raw).hexdigest()


def run(command, log, env=None, timeout=180):
    with Path(log).open('w') as stream:
        process_options = {'stdout': stream, 'stderr': subprocess.STDOUT, 'env': env}
        if os.name == 'nt':
            process_options['creationflags'] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            process_options['start_new_session'] = True
        child = subprocess.Popen([str(x) for x in command], **process_options)
        try:
            status = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                child.kill()
            else:
                os.killpg(child.pid, signal.SIGKILL)
            child.wait()
            raise RuntimeError(f'timed out: {command[0]}; see {log}')
    text = Path(log).read_text(errors='replace')
    if status or re.search(r'(?m)^\s*(?:(?:SCRIPT|SHADER) )?ERROR:', text):
        raise RuntimeError(f'failed: {command}; see {log}\n{text[-2000:]}')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inspect_mips(folder):
    """Check actual Godot mips, including silhouette loss at distant sizes."""
    import numpy as np
    from PIL import Image
    rows = []
    for level in range(11):
        image = Image.open(folder / f'mip-{level:02d}.png').convert('RGBA')
        if image.size != (1024 >> level, 1024 >> level):
            raise RuntimeError(f'bad mip size at level {level}')
        pixels = np.asarray(image)
        size = 512 >> level
        tiles = []
        if size:
            for x, y in ((0, 0), (size, 0), (0, size)):
                alpha = pixels[y:y+size, x:x+size, 3]
                count = int((alpha >= 128).sum())
                if level <= 4 and not count:
                    raise RuntimeError(f'empty silhouette at mip {level}')
                tiles.append(count)
            if level <= 4 and np.any(pixels[size:, size:, 3]):
                raise RuntimeError(f'alpha leaked into reserved slot at mip {level}')
        rows.append({'level': level, 'atlas_size_px': image.width,
                     'tile_opaque_pixels_at_cutoff_0_5': tiles})
    (folder / 'mip-analysis.json').write_text(json.dumps(rows, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--out', required=True, type=Path)
    recipe_group = parser.add_mutually_exclusive_group()
    recipe_group.add_argument('--recipe', choices=('legacy', 'realistic'),
                              help='Source set to bake; legacy remains the default')
    recipe_group.add_argument('--source-recipe', type=Path,
                              help='Use an explicit pinned glTF/GLB recipe JSON instead of a built-in source set')
    parser.add_argument('--match-atlas', type=Path,
                        help='Align the generated material-mask alpha to an existing runtime atlas without replacing it')
    default_godot = ROOT / ('.tools/Godot_v4.8-beta1_win64.exe' if os.name == 'nt'
                            else '.tools/Godot_v4.8-beta1_linux.x86_64')
    parser.add_argument('--godot', type=Path, default=default_godot)
    args = parser.parse_args()
    out = args.out.resolve()
    match_atlas = args.match_atlas.resolve() if args.match_atlas else None
    recipe_kind = 'user' if args.source_recipe else (args.recipe or 'legacy')
    if out.exists() and any(out.iterdir()):
        raise RuntimeError('--out must be new or empty; never reuse stale evidence')
    if match_atlas is not None and not match_atlas.is_file():
        raise RuntimeError(f'--match-atlas does not exist: {match_atlas}')
    if match_atlas is not None:
        try:
            match_atlas.relative_to(ROOT)
        except ValueError as error:
            raise RuntimeError('--match-atlas must identify an input inside this repository') from error
    out.mkdir(parents=True, exist_ok=True)
    recipe_path: Path | None = None
    original_recipe_sha256: str | None = None
    recipe_data: dict | None = None
    if recipe_kind == 'realistic':
        recipe_data = realistic_recipe()
    elif recipe_kind == 'user':
        recipe_data, original_recipe_sha256 = normalize_user_recipe(args.source_recipe)
    if recipe_data is not None:
        recipe_path = out / 'source-recipe.json'
        recipe_path.write_text(json.dumps(recipe_data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        if original_recipe_sha256 is None:
            original_recipe_sha256 = sha(recipe_path)
    godot = args.godot.resolve()
    version = subprocess.check_output([str(godot), '--version'], text=True).strip()
    if version != '4.8.beta1.official.4d10419ca':
        raise RuntimeError(f'expected pinned Godot 4.8-beta1, got {version}')
    if recipe_path is None:
        run(['node', TOOLS / 'adapt.mjs', '--out', out / 'derived'], out / 'adapt.log')
    else:
        run(['node', TOOLS / 'adapt.mjs', '--source-recipe', recipe_path, '--out', out / 'derived'],
            out / 'adapt.log', timeout=600)
    with tempfile.TemporaryDirectory(prefix='openrc-tree-bake-') as scratch:
        project = Path(scratch)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="L6a Bake"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\nenvironment/defaults/default_clear_color=Color(0,0,0,0)\n')
        (project / 'trees').mkdir()
        for name in IDS:
            for suffix in ('', '-reference'):
                shutil.copy2(out / 'derived' / (name + suffix + '.glb'), project / 'trees')
        if recipe_path is not None:
            shutil.copy2(out / 'derived' / 'bake-recipe.json', project / 'trees' / 'bake-recipe.json')
        raw = out / 'raw'
        raw.mkdir()
        env = {**os.environ, 'LP_NUM_THREADS': '1'}
        bake_command = [godot, '--path', project, '--rendering-driver', 'opengl3',
                        '--audio-driver', 'Dummy', '--script', TOOLS / 'bake.gd', '--', '--out=' + str(raw)]
        if os.name != 'nt':
            bake_command = ['xvfb-run', '-a', *bake_command]
        run(bake_command,
            out / 'bake.log', env=env)
        import sys
        process_command = [sys.executable, TOOLS / 'process_atlas.py', '--bake', raw, '--out', out / 'atlas']
        if match_atlas is not None:
            process_command.extend(['--runtime-atlas', match_atlas])
        run(process_command, out / 'process.log')
        run([godot, '--headless', '--path', project, '--script', TOOLS / 'fix_atlas.gd', '--', out / 'atlas'], out / 'mips.log')
        inspect_mips(out / 'atlas')
    # Keep input hashes with the bake, so reproducing an image never relies on a script filename alone.
    inputs = list(TOOLS.glob('*.gd')) + list(TOOLS.glob('*.py')) + list(TOOLS.glob('*.mjs')) + [TOOLS/'package-lock.json']
    inputs += list((ROOT/'assets/landscape/trees/source').glob('*'))
    inputs.append(ROOT/'.gitattributes')
    if recipe_path is not None:
        inputs.append(recipe_path)
        for item in recipe_data['species']:
            model_path = Path(item['source_path']).resolve()
            inputs.append(model_path)
            inputs.extend((model_path.parent / Path(dependency['uri'])).resolve()
                          for dependency in item.get('dependencies', []))
            inputs.extend(Path(pin['path']).resolve() for pin in item.get('pinned_files', []))
    if match_atlas is not None:
        inputs.append(match_atlas)
    if recipe_kind == 'legacy':
        # Preserve the established legacy manifest representation byte-for-byte.
        input_hashes = {str(p.relative_to(ROOT)): sha(p) for p in sorted(inputs) if p.is_file()}
    else:
        input_hashes = {}
        for input_path in sorted(set(p.resolve() for p in inputs)):
            if not input_path.is_file():
                raise RuntimeError(f'bake input disappeared before manifest: {input_path}')
            try:
                input_name = input_path.relative_to(ROOT).as_posix()
            except ValueError:
                input_name = str(input_path)
            input_hashes[input_name] = sha(input_path)
    if recipe_kind == 'legacy':
        output_hashes = {str(p.relative_to(out)): sha(p) for folder in ('derived', 'atlas')
                         for p in sorted((out / folder).glob('*')) if p.is_file()}
    else:
        output_hashes = {str(p.relative_to(out)): sha(p) for folder in ('derived', 'atlas')
                         for p in sorted((out / folder).rglob('*')) if p.is_file()}
    report = {'format':'openrc-tree-bake v1' if recipe_kind == 'legacy' else 'openrc-tree-bake v2', 'godot':version,
              'runtime_alpha_reference': str(match_atlas.relative_to(ROOT).as_posix()) if match_atlas else None,
              'inputs_sha256':input_hashes,
              'outputs_sha256': output_hashes,
              'bake':json.loads((raw/'bake.json').read_text())}
    if recipe_path is not None:
        report['recipe_id'] = recipe_data['recipe_id']
        report['source_recipe_sha256'] = sha(recipe_path)
        if args.source_recipe:
            report['source_recipe_original_path'] = str(args.source_recipe.resolve())
            report['source_recipe_original_sha256'] = original_recipe_sha256
    (out/'manifest.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    print(f'Bake complete: {out}')


if __name__ == '__main__':
    main()
