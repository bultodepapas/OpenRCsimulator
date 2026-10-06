#!/usr/bin/env python3
"""Reproduce in a fresh temporary Godot project. No writes to app/ or user settings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--godot', type=Path, required=True)
parser.add_argument('--tools', type=Path, required=True, help='Directory containing pinned npm installation')
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
if any(out.iterdir()):
    parser.error('--out must be empty: stale PNGs must not count as a successful run')
godot = args.godot.resolve()
tools = args.tools.resolve()
cli = tools / 'node_modules/.bin/gltf-transform'

def run(command, log):
    try:
        result = subprocess.run(list(map(str, command)), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=90, env={**os.environ, 'NO_COLOR': '1'})
    except subprocess.TimeoutExpired as error:
        captured = error.stdout or b''
        (out / log).write_text(captured.decode(errors='replace') if isinstance(captured, bytes) else captured)
        raise
    text = re.sub(r'\x1b\[[0-9;]*m', '', result.stdout)
    (out / log).write_text(text)
    if result.returncode or re.search(r'(?:SCRIPT ERROR:|^ERROR:|Parse Error)', text, re.M):
        raise RuntimeError(f'{log}: command failed ({result.returncode}); see log')

for entry in json.loads((HERE / 'provenance.json').read_text())['files']:
    source = HERE / 'source' / Path(entry['entry']).name
    if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
        raise RuntimeError(f'Source hash mismatch: {source.name}')
run([cli, '--version'], 'tool-version.txt')
if (out / 'tool-version.txt').read_text().strip() != '4.5.0':
    raise RuntimeError('Expected glTF Transform 4.5.0')

with tempfile.TemporaryDirectory(prefix='openrc-nature-') as temp:
    scratch = Path(temp)
    for name in ['project.godot', 'probe.gd']:
        shutil.copy(HERE / name, scratch / name)
    shutil.copytree(HERE / 'source', scratch / 'source')
    (scratch / 'optimized').mkdir()
    inputs = []
    outputs = []
    stats = []
    for source in sorted((scratch / 'source').glob('*.glb')):
        optimized = scratch / 'optimized' / source.name
        # Exact vertex weld only: no simplification, quantization, compression, or flattening.
        run([cli, 'inspect', source], source.stem + '-inspect.txt')
        run([cli, 'weld', source, optimized], source.stem + '-weld.txt')
        inputs.append(source)
        outputs.append(optimized)
        stats.append({'name': source.name, 'source_bytes': source.stat().st_size,
                      'weld_bytes': optimized.stat().st_size,
                      'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                      'weld_sha256': hashlib.sha256(optimized.read_bytes()).hexdigest()})
    run(['node', HERE / 'validate.cjs', tools, out / 'validation.json', *inputs, *outputs], 'validation.log')
    (out / 'sizes.json').write_text(json.dumps(stats, indent=2) + '\n')
    run([godot, '--headless', '--editor', '--path', scratch, '--import'], 'import.log')
    for repeat in [1, 2]:
        render_out = out / f'repeat-{repeat}'
        run(['xvfb-run', '-a', godot, '--path', scratch, '--audio-driver', 'Dummy', '--quit-after', '240',
             '--script', 'res://probe.gd', '--', f'--out={render_out}'], f'render-{repeat}.log')
    comparisons = {}
    for name in ['source', 'optimized', 'merged-colors', 'adapted-palette', 'multimesh-source', 'multimesh-merged']:
        a, b = (out / 'repeat-1' / f'{name}.png'), (out / 'repeat-2' / f'{name}.png')
        comparisons[name] = a.read_bytes() == b.read_bytes()
    (out / 'repeatability.json').write_text(json.dumps(comparisons, indent=2) + '\n')
    if not all(comparisons.values()):
        raise RuntimeError('Repeated PNGs differ; inspect repeatability.json')
    if (out / 'repeat-1/source.png').read_bytes() != (out / 'repeat-1/optimized.png').read_bytes():
        raise RuntimeError('GLB rewrite changed the reference image')
print(f'Validated and rendered. Evidence: {out}')
