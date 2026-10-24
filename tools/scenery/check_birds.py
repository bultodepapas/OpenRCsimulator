#!/usr/bin/env python3
"""SC-BIRD-01/05: the bird layer renders where its float64 reference says, at true size, and repeats byte for byte.

Runs tools/scenery/capture_birds.gd twice (independent processes) at 1920x1080 on the Compatibility renderer. For the
birds with the smallest and the largest time offset of every flock, the birds-on minus birds-off difference isolates
the bird; the connected blob nearest the image centre must sit within CENTRE_TOLERANCE_PX of the centre (where the CPU
track predicts it) and span a plausible fraction of the requested size. The in-process repeat and the second process must produce identical images.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'ground'))
from check_surfaces import checked_run, sha256  # noqa: E402

CAPTURE = Path(__file__).with_name('capture_birds.gd')
RESOLUTION = (1920, 1080)
CENTRE_TOLERANCE_PX = 10.0
MIN_PIXELS = 12
SPAN_RANGE = (0.25, 1.6)  # blob extent / requested span (the planform is seen obliquely and banked)
DIFF_THRESHOLD = 3
MERGE_PX = 3


def blobs(mask):
    """4-connected components of a boolean mask: list of (ys, xs) arrays."""
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        stack, ys, xs = [(y0, x0)], [], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            ys.append(y)
            xs.append(x)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1] and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        out.append((np.array(ys), np.array(xs)))
    return out


def check_view(folder, name, view):
    on = np.asarray(Image.open(folder / view['shots']['on']).convert('RGB')).astype(np.int16)
    repeat = np.asarray(Image.open(folder / view['shots']['repeat']).convert('RGB')).astype(np.int16)
    off = np.asarray(Image.open(folder / view['shots']['off']).convert('RGB')).astype(np.int16)
    if on.shape[:2] != (RESOLUTION[1], RESOLUTION[0]):
        raise RuntimeError(f'{name}: capture is {on.shape[1]}x{on.shape[0]}, expected {RESOLUTION}')
    if not np.array_equal(on, repeat):
        raise RuntimeError(f'{name}: the in-process repeat differs')
    mask = np.max(np.abs(on - off), axis=2) > DIFF_THRESHOLD
    # A bird seen edge-on is a thin line that MSAA breaks into dashes: join pieces closer than MERGE_PX, then measure
    # each joined blob with its own (undilated) pixels.
    joined = mask.copy()
    for _ in range(MERGE_PX):
        grown = joined.copy()
        grown[1:] |= joined[:-1]
        grown[:-1] |= joined[1:]
        grown[:, 1:] |= joined[:, :-1]
        grown[:, :-1] |= joined[:, 1:]
        joined = grown
    found = []
    for ys, xs in blobs(joined):
        keep = mask[ys, xs]
        if keep.any():
            found.append((ys[keep], xs[keep]))
    if not found:
        raise RuntimeError(f'{name}: no bird pixels (birds on = birds off)')
    cx, cy = view['expected_px']
    def distance(b):
        return float(np.hypot(b[1].mean() - cx, b[0].mean() - cy))
    best = min(found, key=distance)
    ys, xs = best
    extent = float(max(xs.max() - xs.min(), ys.max() - ys.min()) + 1)
    result = {'pixels': int(ys.size), 'centroid_px': [float(xs.mean()), float(ys.mean())],
              'centre_error_px': distance(best), 'extent_px': extent, 'requested_span_px': view['expected_span_px'],
              'blobs_in_view': len(found), 'species': view['species'], 'distance_m': view['distance_m'],
              'fov_deg': view['fov_deg'], 'time_offset_s': view['time_offset_s'], 'mean_rgb_on_bird': [float(v) for v in on[ys, xs].mean(axis=0)],
              'mean_rgb_behind_bird': [float(v) for v in off[ys, xs].mean(axis=0)]}
    if result['pixels'] < MIN_PIXELS:
        raise RuntimeError(f'{name}: bird blob has {result["pixels"]} pixels')
    if result['centre_error_px'] > CENTRE_TOLERANCE_PX:
        raise RuntimeError(f'{name}: bird drawn {result["centre_error_px"]:.1f} px from the predicted position')
    ratio = extent / float(view['expected_span_px'])
    if not SPAN_RANGE[0] <= ratio <= SPAN_RANGE[1]:
        raise RuntimeError(f'{name}: bird extent {extent:.0f} px vs requested {view["expected_span_px"]} px')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'app')
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--t', type=float, default=20.0, help='sim_clock of the capture (s)')
    args = parser.parse_args()
    out, app, godot = args.out.resolve(), args.app.resolve(), args.godot.resolve()
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error('--out must be new or empty')
    if not (app / 'project.godot').is_file() or not godot.is_file():
        parser.error('valid app and Godot executable required')
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LP_NUM_THREADS='1', OPENRC_SCENERY='on', OPENRC_SCENERY_AUDIO='off',
               OPENRC_SCENERY_BIRDS='on')
    reports, commands, hashes = {}, {}, {}
    for run in ('first', 'second'):
        command = ['xvfb-run', '-a', '-s', f'-screen 0 {RESOLUTION[0]}x{RESOLUTION[1]}x24', str(godot), '--path', str(app),
                   '--resolution', f'{RESOLUTION[0]}x{RESOLUTION[1]}', '--rendering-driver', 'opengl3',
                   '--audio-driver', 'Dummy', '--script', str(CAPTURE), '--', f'--out={out / run}', f'--t={args.t}']
        commands[run] = command
        checked_run(command, out / f'{run}.log', env, 600)
        reports[run] = json.loads((out / run / 'birds.json').read_text())
        hashes[run] = {p.name: sha256(p) for p in sorted((out / run).glob('*.png'))}
    if hashes['first'] != hashes['second']:
        raise RuntimeError('the second process rendered different images')
    views = reports['first']['views']
    flocks = ('vulture_kettle', 'kite_quartering', 'swallow_coursing')
    if set(views) != {f'{f}_{which}' for f in flocks for which in ('early', 'late')}:
        raise RuntimeError(f'unexpected flock views {sorted(views)}')
    metrics = {name: check_view(out / 'first', name, view) for name, view in sorted(views.items())}
    sources = {str(p.relative_to(ROOT)): sha256(p) for p in (
        app / 'scenery/birds.gd', app / 'scenery/birds/bird_data.gd', app / 'scenery/birds/bird_tracks.gd',
        app / 'scenery/birds/bird_planform.gd', app / 'scenery/birds/sky_birds.gdshader',
        app / 'data/scenery/birds/birds.json', CAPTURE, Path(__file__).resolve())}
    summary = {'format': 'openrc-sc-bird-capture v1', 'complete': True, 'sim_clock': reports['first']['sim_clock'],
               'resolution': list(RESOLUTION), 'renderer': reports['first']['adapter'], 'metrics': metrics,
               'identical_repeat': True, 'identical_second_process': True, 'image_sha256': hashes['first'],
               'sources_sha256': sources, 'commands': commands,
               'godot_version': subprocess.run([str(godot), '--version'], check=True, capture_output=True,
                                               text=True).stdout.strip()}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    for name, m in sorted(metrics.items()):
        print(f'{name}: {m["pixels"]} px, centre error {m["centre_error_px"]:.1f} px, extent {m["extent_px"]:.0f}/'
              f'{m["requested_span_px"]:.0f} px, {m["blobs_in_view"]} bird(s) in view')
    print(f'bird capture passed: {out}')


if __name__ == '__main__':
    main()
