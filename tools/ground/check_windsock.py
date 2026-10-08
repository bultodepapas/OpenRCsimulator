#!/usr/bin/env python3
"""L10a: verify the production calm windsock with isolated on/off captures."""
import argparse
import json
import os
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image

from check_surfaces import checked_run, finite_tree, reject_constant, sha256

ROOT = Path(__file__).resolve().parents[2]
CAPTURE = Path(__file__).with_name('capture_windsock.gd')
VIEWS = ('close', 'pilot_turn', 'overview')


def check_pair(on, off, bounds):
    delta = np.max(np.abs(on.astype(np.int16) - off.astype(np.int16)), axis=2)
    changed = delta > 1
    count = int(changed.sum())
    if count < 20:
        raise RuntimeError('windsock ablation changed fewer than 20 pixels')
    x0, y0, x1, y1 = bounds
    if not (0 <= x0 < x1 < 960 and 0 <= y0 < y1 < 540):
        raise RuntimeError('windsock mesh bounds are not fully on screen')
    ys, xs = np.mgrid[:540, :960]
    outside = (xs < x0 - 2) | (xs > x1 + 2) | (ys < y0 - 2) | (ys > y1 + 2)
    if np.any(changed & outside):
        raise RuntimeError('on/off changes escape the projected windsock bounds')
    return {'changed_pixels': count, 'mean_changed_rgb_delta': float(delta[changed].mean()),
            'clipped_white_pixels': int(np.all(on >= 254, axis=2)[changed].sum())}


def load(folder):
    data = json.loads((folder / 'capture.json').read_text(), parse_constant=reject_constant)
    finite_tree(data)
    if data.get('format') != 'openrc-l10a-capture v1' or data.get('method') != 'gl_compatibility' or data.get('driver') != 'opengl3':
        raise RuntimeError('invalid capture format or renderer')
    if data.get('viewport') != [960, 540] or data.get('shader_time') != 0:
        raise RuntimeError('wrong viewport or shader clock')
    records = {}
    for item in data['records']:
        name = item['image']
        path = folder / name
        if path.parent != folder or name in records or sha256(path) != item['sha256']:
            raise RuntimeError('invalid, duplicate or altered capture image')
        with Image.open(path) as image:
            if image.size != (960, 540):
                raise RuntimeError('wrong PNG dimensions')
            records[name] = (item, np.asarray(image.convert('RGB')))
    if set(records) != {f'{view}-{state}.png' for view in VIEWS for state in ('on', 'off')}:
        raise RuntimeError('incomplete capture set')
    metrics = {}
    for view in VIEWS:
        on, a = records[f'{view}-on.png']
        off, b = records[f'{view}-off.png']
        for key in ('bounds', 'eye', 'target', 'fov'):
            if on[key] != off[key]:
                raise RuntimeError('camera/projection changed during ablation')
        metric = check_pair(a, b, on['bounds'])
        metric['added_draws'] = on['draws'] - off['draws']
        metric['added_primitives'] = on['primitives'] - off['primitives']
        if metric['added_draws'] != 2 or not 0 < metric['added_primitives'] < 2000:
            raise RuntimeError(f'{view}: expected two draws and fewer than 2000 added triangles')
        if metric['clipped_white_pixels']:
            raise RuntimeError(f'{view}: clipped whites on the windsock')
        try:
            check_pair(b, b, on['bounds'])
        except RuntimeError as exc:
            if 'fewer than 20 pixels' not in str(exc):
                raise
        else:
            raise RuntimeError('invisible-feature control escaped the capture check')
        metrics[view] = metric
    return data, metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'app')
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out, app, godot = args.out.resolve(), args.app.resolve(), args.godot.resolve()
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error('--out must be new or empty')
    if not (app / 'project.godot').is_file() or not godot.is_file():
        parser.error('valid app and Godot executable required')
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LP_NUM_THREADS='1', OPENRC_SCENERY_AUDIO='off', OPENRC_SCENERY_BIRDS='off')
    runs, metrics, commands = {}, {}, {}
    for name in ('first', 'repeat', 'scenery'):
        command = ['xvfb-run', '-a', '-s', '-screen 0 960x540x24', str(godot), '--path', str(app),
                   '--resolution', '960x540', '--rendering-driver', 'opengl3', '--audio-driver', 'Dummy',
                   '--script', str(CAPTURE), '--', f'--out={out / name}']
        if name == 'scenery':
            command.append('--scenery=on')
        commands[name] = command
        checked_run(command, out / f'{name}.log', env, 240)
        runs[name], metrics[name] = load(out / name)
        if runs[name]['scenery'] != (name == 'scenery'):
            raise RuntimeError('scenery mode differs from requested fixture')
    if runs['first'] != runs['repeat']:
        raise RuntimeError('independent repeat hashes/counters differ')
    sources = {"app/" + relative: sha256(app / relative) for relative in (
        'data/field_loader.gd', 'data/fields/default.json', 'render/field.gd',
        'render/windsock.gd', 'scenery/mesh_kit.gd')}
    sources.update({str(path.relative_to(ROOT)): sha256(path) for path in (CAPTURE, Path(__file__).resolve())})
    summary = {'format': 'openrc-l10a-review v1', 'complete': True, 'metrics': metrics,
               'identical_repeat': True, 'invisible_feature_control_rejected': True,
               'renderer': runs['first']['adapter'], 'sources_sha256': sources,
               'commands': commands, 'godot_version': subprocess.run([str(godot), '--version'], check=True,
                   capture_output=True, text=True).stdout.strip()}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True, allow_nan=False) + '\n')
    print(f'L10a windsock capture passed: {out}')


if __name__ == '__main__':
    main()
