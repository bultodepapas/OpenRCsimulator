#!/usr/bin/env python3
"""L10a–d: verify production flight cues with isolated on/off captures."""
import argparse
import json
import os
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from check_surfaces import checked_run, finite_tree, reject_constant, sha256

ROOT = Path(__file__).resolve().parents[2]
CAPTURE = Path(__file__).with_name('capture_windsock.gd')
STEPS = {'windsock': 'l10a', 'pilot_station': 'l10b', 'flightline_barrier': 'l10c', 'contact_shadows': 'l10d'}
VIEWS = ('close', 'pilot_turn', 'overview')
STATION_VIEWS = ('close', 'rear', 'overview', 'pilot_left', 'pilot_right')


def check_pair(on, off, bounds, partial=False):
    delta = np.max(np.abs(on.astype(np.int16) - off.astype(np.int16)), axis=2)
    changed = delta > 1
    count = int(changed.sum())
    if count < 20:
        raise RuntimeError('cue ablation changed fewer than 20 pixels')
    x0, y0, x1, y1 = bounds
    if not partial and not (0 <= x0 < x1 < 960 and 0 <= y0 < y1 < 540):
        raise RuntimeError('cue mesh bounds are not fully on screen')
    ys, xs = np.mgrid[:540, :960]
    outside = (xs < x0 - 2) | (xs > x1 + 2) | (ys < y0 - 2) | (ys > y1 + 2)
    if np.any(changed & outside):
        raise RuntimeError('on/off changes escape the projected cue bounds')
    return {'changed_pixels': count, 'mean_changed_rgb_delta': float(delta[changed].mean()),
            'clipped_white_pixels': int(np.all(on >= 254, axis=2)[changed].sum())}


def check_clear_view(on, off):
    if not np.array_equal(on, off):
        raise RuntimeError('pilot station obstructs the runway view')
    return {'changed_pixels': 0}


def check_runway_clear(on, off, mask):
    if mask.sum() < 100 or np.any(on[mask] != off[mask]):
        raise RuntimeError('flightline barrier obstructs the runway')


def load(folder, cue_type='windsock'):
    data = json.loads((folder / 'capture.json').read_text(), parse_constant=reject_constant)
    finite_tree(data)
    station = cue_type == 'pilot_station'
    barrier = cue_type == 'flightline_barrier'
    shadows = cue_type == 'contact_shadows'
    views = STATION_VIEWS if station or barrier else ('close', 'station', 'barrier') if shadows else VIEWS
    if data.get('cue', {}).get('type') != cue_type:
        raise RuntimeError('wrong cue type')
    if data.get('format') != f'openrc-{STEPS[cue_type]}-capture v1' or data.get('method') != 'gl_compatibility' or data.get('driver') != 'opengl3':
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
    if set(records) != {f'{view}-{state}.png' for view in views for state in ('on', 'off')}:
        raise RuntimeError('incomplete capture set')
    metrics = {}
    for view in views:
        on, a = records[f'{view}-on.png']
        off, b = records[f'{view}-off.png']
        for key in ('bounds', 'eye', 'target', 'fov', 'runway_polygon'):
            if on[key] != off[key]:
                raise RuntimeError('camera/projection changed during ablation')
        if station and view.startswith('pilot_'):
            metric = check_clear_view(a, b)
            mutated = b.copy()
            mutated[270, 480] ^= np.uint8(255)
            try:
                check_clear_view(mutated, b)
            except RuntimeError:
                pass
            else:
                raise RuntimeError('occlusion control escaped the pilot-view check')
            metrics[view] = metric
            continue
        if barrier and view.startswith('pilot_'):
            mask_image = Image.new('L', (960, 540))
            ImageDraw.Draw(mask_image).polygon([tuple(p) for p in on['runway_polygon']], fill=255)
            mask = np.asarray(mask_image.filter(ImageFilter.MaxFilter(5))) > 0
            check_runway_clear(a, b, mask)
            mutated = b.copy()
            row, column = np.argwhere(mask)[0]
            mutated[row, column] ^= np.uint8(255)
            try:
                check_runway_clear(mutated, b, mask)
            except RuntimeError:
                pass
            else:
                raise RuntimeError('runway pixel-difference control escaped the check')
            metric = check_pair(a, b, on['bounds'], partial=True)
            metric['protected_runway_pixels'] = int(mask.sum())
            x0, y0, x1, y1 = on['bounds']
            yy, xx = np.mgrid[:540, :960]
            outside = (xx < x0 - 2) | (xx > x1 + 2) | (yy < y0 - 2) | (yy > y1 + 2)
            if not np.any(outside):
                raise RuntimeError('pilot cue bounds leave no outside pixel for the control')
            row, column = np.argwhere(outside)[0]
            mutated = a.copy()
            mutated[row, column] = b[row, column] ^ np.uint8(255)
            try:
                check_pair(mutated, b, on['bounds'], partial=True)
            except RuntimeError as exc:
                if 'escape the projected cue bounds' not in str(exc):
                    raise
            else:
                raise RuntimeError('outside-cue pixel control escaped the check')
            metric['outside_cue_control_rejected'] = True
        else:
            metric = check_pair(a, b, on['bounds'], partial=shadows)
        if shadows:
            brightened = np.max(a.astype(np.int16) - b.astype(np.int16), axis=2) > 1
            if np.any(brightened):
                raise RuntimeError('contact shadows brighten the ground')
        metric['added_draws'] = on['draws'] - off['draws']
        metric['added_primitives'] = on['primitives'] - off['primitives']
        if metric['added_draws'] != (2 if cue_type == 'windsock' else 1) or not 0 < metric['added_primitives'] < (400 if station else 2000 if cue_type == 'windsock' else 1500):
            raise RuntimeError(f'{view}: cue exceeds its draw or triangle budget')
        if metric['clipped_white_pixels']:
            raise RuntimeError(f'{view}: clipped whites on the cue')
        try:
            check_pair(b, b, on['bounds'], partial=shadows)
        except RuntimeError as exc:
            if 'fewer than 20 pixels' not in str(exc):
                raise
        else:
            raise RuntimeError('invisible-feature control escaped the capture check')
        metrics[view] = metric
    return data, metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cue', choices=tuple(STEPS), default='windsock')
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
                   '--script', str(CAPTURE), '--', f'--out={out / name}', f'--cue={args.cue}']
        if name == 'scenery':
            command.append('--scenery=on')
        commands[name] = command
        checked_run(command, out / f'{name}.log', env, 240)
        runs[name], metrics[name] = load(out / name, args.cue)
        if runs[name]['scenery'] != (name == 'scenery'):
            raise RuntimeError('scenery mode differs from requested fixture')
    if runs['first'] != runs['repeat']:
        raise RuntimeError('independent repeat hashes/counters differ')
    sources = {"app/" + relative: sha256(app / relative) for relative in (
        'data/field_loader.gd', 'data/fields/default.json', 'render/field.gd',
        'render/windsock.gd', 'render/pilot_station.gd', 'render/flightline_barrier.gd',
        'render/flight_cue_shadows.gd', 'render/near_grass.gd', 'scenery/mesh_kit.gd')}
    sources.update({str(path.relative_to(ROOT)): sha256(path) for path in (CAPTURE, Path(__file__).resolve())})
    summary = {'format': f'openrc-{STEPS[args.cue]}-review v1', 'complete': True, 'metrics': metrics,
               'cue': args.cue, 'identical_repeat': True, 'invisible_feature_control_rejected': True,
               'renderer': runs['first']['adapter'], 'sources_sha256': sources,
               'commands': commands, 'godot_version': subprocess.run([str(godot), '--version'], check=True,
                   capture_output=True, text=True).stdout.strip()}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True, allow_nan=False) + '\n')
    print(f'{args.cue} capture passed: {out}')


if __name__ == '__main__':
    main()
