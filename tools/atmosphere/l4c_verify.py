#!/usr/bin/env python3
"""L4c native-render comparison. Requires Pillow 12.3.0 and NumPy 2.4.6.

Fresh output; isolated app snapshots; fail on engine errors or missing evidence.
Runs the renderer, not --headless. See the L4c report for interpretation and budget.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import numpy as np
from PIL import Image


def fingerprint(app):
    return {str(p.relative_to(app)).replace('\\', '/'): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(app.rglob('*')) if p.is_file()
            and '.godot' not in p.parts and 'captures' not in p.parts}


def pixels(path):
    return np.asarray(Image.open(path).convert('RGB')).astype(np.int16)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--profile', action='store_true', help='3 alternating 10s warmup/60s pairs at 720p (budget) and 1080p (scaling observation)')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    engine = args.godot.resolve()
    producer = Path(__file__).with_name('l4c_capture.gd').resolve()
    sources = {}
    apps = {}
    for key, app in [('before', args.baseline.resolve()), ('after', args.app.resolve())]:
        sources[key] = fingerprint(app)
        apps[key] = out / (key + '-app')
        shutil.copytree(app, apps[key], ignore=shutil.ignore_patterns('.godot', 'captures'))
    reports = {}

    def run(key, name, extra=(), native=True):
        target = out / name
        target.mkdir()
        cmd = [str(engine), '--path', str(apps[key]), '--audio-driver', 'Dummy']
        if native:
            cmd += ['--script', str(producer), '--', '--out=' + str(target), *extra]
        else:
            cmd += list(extra)
        env = dict(os.environ, OPENRC_SCENERY='off', APPDATA=str(out/'user-data'),
                   XDG_DATA_HOME=str(out/'user-data'))
        with (target/'engine.log').open('w', encoding='utf-8') as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT,
                                    env=env, timeout=240,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        log = (target/'engine.log').read_text(encoding='utf-8')
        assert result.returncode == 0 and 'ERROR:' not in log, (name, result.returncode, log[-2000:])
        if native:
            report = json.loads((target/'report.json').read_text())
            assert report['renderer'] == 'gl_compatibility' and report['cases']
            reports[name] = report
        print(name, 'PASS', flush=True)
        return target

    for key in apps:
        run(key, key+'-import', ['--headless', '--import'], False)
    if args.profile:
        for width in (1280, 1920):
            for pair in range(3):
                for key in (('before','after') if pair % 2 == 0 else ('after','before')):
                    run(key, f'{width}-{pair}-{key}', ['--profile=on', '--warmup=10', '--seconds=60', f'--width={width}'])
        summary = {}
        for name, report in reports.items():
            rows = np.asarray(report['cases'][0]['samples_wall_cpu_gpu_ms'])
            assert rows.shape[0] > 1000 and np.isfinite(rows).all() and (rows[:,2] > 0).all()
            summary[name] = {metric: {p:float(np.percentile(rows[:,i], q)) for p,q in [('p50',50),('p95',95),('p99',99)]}
                             for i,metric in enumerate(('wall','cpu','gpu'))}
        for pair in range(3):
            b,a = (summary[f'1280-{pair}-{key}']['gpu'] for key in ('before','after'))
            assert a['p50']-b['p50'] <= 0.5 and a['p95']-b['p95'] <= 1.0, (b,a)
        (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    else:
        for name, options in [('day',[]),('clear',['--coverage=0']),('sunrise',['--hour=6']),('night',['--hour=0']),('no-plane',['--airplane=off'])]:
            for key in apps:
                run(key,key+'-'+name,options)
        run('after','after-repeat')
        run('after','after-zero',['--strength=0'])
        metrics = {}
        for file in sorted((out/'before-day').glob('*.png')):
            name = file.name
            before = pixels(file)
            after = pixels(out/'after-day'/name)
            assert np.array_equal(before,pixels(out/'after-zero'/name)), 'zero parity '+name
            assert np.array_equal(after,pixels(out/'after-repeat'/name)), 'repeat '+name
            assert np.array_equal(pixels(out/'before-clear'/name),pixels(out/'after-clear'/name)), 'clear '+name
            night_delta = pixels(out/'after-night'/name) - pixels(out/'before-night'/name)
            assert night_delta.max() <= 1, 'night gained light '+name
            bg = pixels(out/'before-no-plane'/name)
            # Require equality for fully covered model pixels; mixed edge pixels
            # correctly include the changed sky background under MSAA.
            model = np.max(np.abs(before-bg),axis=2)>20
            # White sky can coincide with white airplane: count only this observed mask.
            interior = model.copy()
            for axis in (0,1):
                interior &= np.roll(model,1,axis) & np.roll(model,-1,axis)
            model_error = int(np.max(np.abs(before-after)[interior])) if interior.any() else 0
            assert model_error <= 1, ('aircraft',name,model_error)
            delta = np.max(np.abs(before-after),axis=2)
            if name.startswith('ground'):
                assert not delta.any(), 'ground parity '+name
            metrics[name] = {'changed_pixels_gt3':int((delta>3).sum()),'max_channel_delta':int(delta.max()),
                             'aircraft_interior_pixels':int(interior.sum()),'aircraft_max_delta':model_error,
                             'night_max_increase':int(night_delta.max())}
        # Direct same-camera count comparison across all render cases.
        for b,a in zip(reports['before-day']['cases'],reports['after-day']['cases']):
            assert b['id']==a['id'] and b['draws']==a['draws'] and b['primitives']==a['primitives']
        assert metrics['sun-000.png']['changed_pixels_gt3']>5000, 'missing visible upgrade'
        assert not np.array_equal(pixels(out/'after-day/sun-000.png'),pixels(out/'after-day/sun-120.png')), 'no drift'
        (out/'summary.json').write_text(json.dumps(metrics,indent=2)+'\n')
    for key, app in apps.items():
        assert fingerprint(app)==sources[key], 'source changed during evidence: '+key
    (out/'sources.json').write_text(json.dumps({'apps':sources,'producer_sha256':hashlib.sha256(producer.read_bytes()).hexdigest(),
                                              'engine_sha256':hashlib.sha256(engine.read_bytes()).hexdigest()},indent=2)+'\n')
    print('L4c verification complete',out)


if __name__ == '__main__':
    main()
