#!/usr/bin/env python3
"""L6b real-render regression: shader identity, draws, all-sector bounds and byte-repeat captures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

VIEWS = [f'az{az:03d}-el{el:02d}' for az in (0, 90, 180, 270) for el in (0, 10)] + ['gap030', 'gap210', 'overhead', 'engine-shadow-audit']


def checked_run(command, log, env):
    with log.open('w') as output:
        result = subprocess.run(['timeout', '--kill-after=5', '120', *command], stdout=output, stderr=subprocess.STDOUT, env=env)
    text = re.sub(r'\x1b\[[0-9;]*m', '', log.read_text())
    if result.returncode or re.search(r'^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:', text, re.M):
        raise RuntimeError(f'L6b engine check failed: {log}')


def verify(folder):
    report = json.loads((folder / 'review.json').read_text())
    assert report['complete'] is True
    assert [v['id'] for v in report['views']] == VIEWS
    for view in report['views']:
        assert 0 < view['vegetation_visible_draws'] <= 24
        assert view['vegetation_shadow_draws'] == 0
        assert hashlib.sha256((folder / (view['id'] + '.png')).read_bytes()).hexdigest() == view['sha256']
    assert report['views'][10]['vegetation_visible_draws'] == 8
    assert len(report['hash_samples']) == 480
    for sample in report['hash_samples']:
        assert sample['species_matches'] and sample['height_error_m'] <= 1 / 1024 and sample['yaw_error_rad'] <= 1 / 4096
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LP_NUM_THREADS='1')
    command = ['xvfb-run', '-a', str(godot), '--path', str(app), '--rendering-driver', 'opengl3', '--audio-driver', 'Dummy']
    # This standalone command must also work before opening the editor.
    checked_run([str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy", "--import"], out / "import.log", env)
    reports = []
    for repeat in (1, 2):
        folder = out / f'repeat-{repeat}'
        folder.mkdir(exist_ok=True)
        for filename in ['review.json', 'hash-probe.png', *(f'{v}.png' for v in VIEWS)]:
            (folder / filename).unlink(missing_ok=True)
        checked_run([*command, '--script', str(Path(__file__).with_name('review.gd')), '--', str(folder)], out / f'repeat-{repeat}.log', env)
        reports.append(verify(folder))
    assert reports[0] == reports[1], 'GPU review reports differ'
    for filename in ['hash-probe.png', *(f'{v}.png' for v in VIEWS)]:
        assert (out / 'repeat-1' / filename).read_bytes() == (out / 'repeat-2' / filename).read_bytes(), filename
    checked_run([*command, '--script', 'res://tests/test_treeline.gd'], out / 'runtime-gpu.log', env)
    max_draws = max(view['vegetation_visible_draws'] for view in reports[0]['views'])
    print(f'L6b: 13 PNGs and reports repeat byte-for-byte; 480 shader identities, maximum {max_draws} vegetation draws, no shadow draws; GPU instance/bounds checks passed')


if __name__ == '__main__':
    main()
