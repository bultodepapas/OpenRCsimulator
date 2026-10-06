"""VQ-01a acceptance experiments. All deliberate breakage stays in temporary copies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--godot', type=Path, required=True)
parser.add_argument('--captures', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
args.app = args.app.resolve()
args.godot = args.godot.resolve()
args.out.mkdir(parents=True, exist_ok=True)
sys.dont_write_bytecode = True
sys.path.insert(0, str(args.app / 'tests'))
from capture_runner import run_capture

results = []
env = {**os.environ, 'LP_NUM_THREADS': '1'}
os.environ['LP_NUM_THREADS'] = '1'

def run(command, name):
    result = subprocess.run(list(map(str, command)), text=True, capture_output=True, timeout=60, env=env)
    (args.out / f'{name}.log').write_text(result.stdout + result.stderr)
    return result

def record(name, passed, **detail):
    results.append({'case': name, 'passed': bool(passed), **detail})
    assert passed, name

with tempfile.TemporaryDirectory(prefix='openrc-capture-mutations-') as temporary:
    root = Path(temporary)
    app = root / 'app'
    shutil.copytree(args.app, app, ignore=shutil.ignore_patterns('captures', '.godot', '__pycache__'))
    main = app / 'main.gd'
    original = main.read_text()
    obstruction = '''func _build_field() -> void:
	var obstacle := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(60, 60, 5)
	obstacle.mesh = box
	obstacle.position = Vector3(0, 20, -50)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	obstacle.material_override = red
	add_child(obstacle)
'''
    assert original.count('func _build_field() -> void:\n') == 1
    main.write_text(original.replace('func _build_field() -> void:\n', obstruction))
    for scene, entry, extra, baseline in [
        ('atmosphere', ['res://tests/fixtures/atmosphere_field.tscn'], [], args.captures),
        ('field', [], ['--hide_airplane'], args.captures / 'field'),
    ]:
        output = args.out / scene / 'capture-land-az0-el0.png'
        command = ['xvfb-run', '-a', '-s', '-screen 0 1280x720x24', str(args.godot),
                   '--path', str(app), '--rendering-driver', 'opengl3', '--audio-driver', 'Dummy',
                   *entry, '--', '--capture', '--t=1.5', '--look_az=0', '--look_el=0', *extra,
                   f'--out={output.resolve()}']
        run_capture(command, output, 'flight', scene)
        same = output.read_bytes() == (baseline / output.name).read_bytes()
        record(f'production-obstacle-{scene}', same if scene == 'atmosphere' else not same,
               png_identical_to_baseline=same, sha256=hashlib.sha256(output.read_bytes()).hexdigest())
    main.write_text(original)

    # Force FileAccess.open to fail without relying on permissions or running as a particular uid.
    blocked = root / 'blocked.png'
    blocked.with_suffix('.json').mkdir()
    result = run(['xvfb-run', '-a', str(args.godot), '--path', app, '--rendering-driver', 'opengl3',
                  '--audio-driver', 'Dummy', '--', '--capture', '--scripted', f'--out={blocked}'], 'manifest-write-failure')
    record('manifest-write-failure', result.returncode != 0 and 'Cannot write capture manifest' in (result.stdout + result.stderr),
           process_exit=result.returncode)

    evidence = root / 'evidence'
    shutil.copytree(args.captures, evidence)
    checker = [sys.executable, str(args.app / 'tests/check_landscape_captures.py'), str(evidence)]
    counters = evidence / 'landscape-counters.txt'
    text = counters.read_text()
    counters.write_text('\n'.join(text.splitlines()[1:]) + '\n')
    result = run(checker, 'missing-counter')
    record('missing-counter-with-png-present', result.returncode != 0 and 'counter inventory mismatch' in result.stderr)
    counters.write_text(text)

    for name, image_name, expected_error in [
        ('clouds-frozen', 'capture-land-az90-el10-t11.png', 'cloud'),
        ('sky-flat', 'capture-land-az0-el0.png', 'sky not darker'),
        ('rim-line', 'capture-land-az0-el0-100m.png', "ground's rim"),
    ]:
        png = evidence / image_name
        sidecar = png.with_suffix('.json')
        old_image, old_manifest = png.read_bytes(), sidecar.read_bytes()
        if name == 'clouds-frozen':
            shutil.copyfile(evidence / 'capture-land-az90-el10.png', png)
        else:
            image = Image.open(png).convert('RGB')
            draw = ImageDraw.Draw(image)
            if name == 'sky-flat':
                draw.rectangle((0, 0, 1279, 359), fill=(180, 180, 180))
            else:
                draw.rectangle((0, 380, 1279, 382), fill=(255, 255, 255))
            image.save(png)
        metadata = json.loads(old_manifest)
        metadata['sha256'] = hashlib.sha256(png.read_bytes()).hexdigest()
        sidecar.write_text(json.dumps(metadata))  # Deliberately valid evidence: image thresholds must reject it.
        result = run(checker, name)
        record(name, result.returncode != 0 and expected_error in result.stdout + result.stderr)
        png.write_bytes(old_image)
        sidecar.write_bytes(old_manifest)

(args.out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(results, indent=2))
