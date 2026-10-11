#!/usr/bin/env python3
"""L9e evidence reducer. Requires NumPy 2.4.6 and Pillow 12.3.0.

Input layout: day/, legacy/, night/, profile1/ through profile3/, each produced
by turf_capture.gd into a fresh directory. Optional filtered/, raw/, reference/
contain motion --filter-reference at 1x, unfiltered 1x, unfiltered 4x.
Never treats process success as proof: caller must also check engine logs.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def manifest(folder):
    value = json.loads((folder / 'manifest.json').read_text())
    assert value['format'] == 'openrc-l9e-turf-capture v1'
    assert value['renderer_method'] == 'gl_compatibility'
    assert [value['engine'][k] for k in ('major', 'minor', 'patch')] == [4, 7, 2]
    assert value['viewport_msaa_3d'] == 2 and value['shader_time_s'] == 0
    return value


def image(folder, record):
    path = folder / record['image']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == record['sha256'], path
    return np.asarray(Image.open(path).convert('RGB'), dtype=np.float64)


def verify(root):
    summary = {'visual': {}, 'profile': [], 'limitations': [
        'Static visual fixture, not whole-app frame cost or minimum hardware acceptance.',
        'Human Gate L and other GPU vendors remain unverified.',
    ]}
    day, legacy, night = [manifest(root / name) for name in ('day', 'legacy', 'night')]
    assert legacy['legacy_baseline'] and not legacy['turf_uniform_present'] and night['night']
    assert not day['legacy_baseline'] and day['turf_uniform_present']
    for actual, old, dark in zip(day['captures'], legacy['captures'], night['captures'], strict=True):
        name = actual['id']
        assert name == old['id'] == dark['id']
        off, on, repeat = [image(root / 'day', r) for r in actual['captures']]
        original = image(root / 'legacy', old['captures'][0])
        assert np.array_equal(off, original), (name, 'zero-strength fallback')
        assert np.array_equal(on, repeat), (name, 'repeatability')
        assert off.shape == (720, 1280, 3)
        for metric in ('draw_calls', 'primitives'):
            assert len({r[metric] for r in actual['captures'] + old['captures']}) == 1, (name, metric)
        delta = on - off
        mean = float(delta.mean())
        mae = float(np.abs(delta).mean())
        assert abs(mean) < 1, (name, 'mean brightness drift')
        if name == 'aerial':
            assert np.array_equal(on, off), 'far-detail leakage'
        else:
            assert mae > .3, (name, 'missing visible turf detail')
        night_images = [image(root / 'night', r) for r in dark['captures']]
        assert all(np.array_equal(night_images[0], n) for n in night_images[1:]), (name, 'unlit material changed')
        summary['visual'][name] = {
            'old_shader_equals_off': True, 'repeat_equal': True, 'night_equal': True,
            'mean_rgb_delta_255': mean, 'mean_absolute_rgb_delta_255': mae,
            'changed_pixels': int(np.any(delta != 0, axis=2).sum()),
            'draw_calls': actual['captures'][1]['draw_calls'],
            'primitives': actual['captures'][1]['primitives'],
        }
    for index in range(1, 4):
        value = manifest(root / f'profile{index}')
        assert not value['legacy_baseline'] and value['turf_uniform_present']
        assert value['manual_draw'] and not value['automatic_render_loop']
        assert value['viewport'] == [1280, 720] and value['vsync'] == 'disabled'
        runs = value['profile']['runs']
        assert [r['state'] for r in runs] == ['off', 'on', 'off', 'on']
        for run in runs:
            assert run['effective_state'] == run['state']
            assert run['turf_detail_strength'] == (1.0 if run['state'] == 'on' else 0.0)
            samples = np.array(run['samples'])
            assert samples.ndim == 2 and samples.shape[0] >= 180 and samples.shape[1] == 3
            assert np.isfinite(samples).all() and (samples > 0).all()
            assert run['warmup_frames'] >= 60
        assert len({r['draw_calls'] for r in runs}) == 1
        stats = {}
        for state in ['off', 'on']:
            samples = np.concatenate([r['samples'] for r in runs if r['state'] == state])
            stats[state] = np.quantile(samples, [.5, .95], axis=0)
        delta = stats['on'] - stats['off']
        assert delta[0, 2] <= .5 and delta[1, 2] <= 1 and delta[1, 0] <= 2, ('budget', index, delta)
        summary['profile'].append({
            'run': index, 'columns': ['wall_ms', 'viewport_cpu_ms', 'viewport_gpu_ms'],
            'rows': ['p50', 'p95'], 'off': stats['off'].tolist(), 'on': stats['on'].tolist(),
            'delta': delta.tolist(), 'budget_pass': True,
        })
    if (root / 'reference').exists():
        errors = {'filtered': [], 'raw': []}
        captures = {kind: manifest(root / kind)['captures'] for kind in ('filtered', 'raw', 'reference')}
        for frame in range(3):
            def on_image(kind):
                view = captures[kind][frame]
                assert view['id'] == f'motion_{frame:02d}'
                record = next(r for r in view['captures'] if r['state'] == 'on')
                return image(root / kind, record)
            reference = on_image('reference')
            assert reference.shape == (384, 2560, 3)
            def linear(rgb):
                v = np.asarray(rgb, dtype=float) / 255
                return np.where(v <= .04045, v / 12.92, ((v + .055) / 1.055) ** 2.4)
            target = linear(reference).reshape(96, 4, 640, 4, 3).mean(axis=(1, 3))
            for kind in errors:
                actual = linear(on_image(kind))
                errors[kind].append(float(np.sqrt(np.mean((actual - target) ** 2))) * 255)
        improvement = 1 - np.mean(errors['filtered']) / np.mean(errors['raw'])
        assert improvement > .3, ('filter does not reject aliasing', errors)
        summary['filter_reference'] = {'linear_rgb_rmse_255': errors, 'reduction_fraction': float(improvement),
            'limit': 'Three shifted grazing-angle crops; not a universal absence-of-shimmer proof.'}
    (root / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.evidence), indent=2))
