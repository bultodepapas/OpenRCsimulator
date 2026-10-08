#!/usr/bin/env python3
"""E3b2-R1: inject bounded defects only into disposable app copies."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]


def main():
    engine = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
        [str(ROOT / 'app/get-godot.sh')], text=True).strip()
    source = (ROOT / 'app/physics/ground_start.gd').read_text()
    mutations = [
        ('norm-hides-earlier-nan',
         '\t\tif not is_finite(value):\n\t\t\treturn INF\n', '',
         'FAIL norm nonfinite component 0'),
        ('nonfinite-initial-iterate-accepted',
         '\tif n == 0 or not _finite_size(x, n):\n\t\treturn { ok = false, x = x, residual = INF, iterations = iterations }\n', '',
         'FAIL initial iterate refused before callback'),
        ('linear-division-overflow-exposed',
         '\t\tif not is_finite(x[row]):\n\t\t\treturn PackedFloat64Array()\n', '',
         'FAIL overflow in final division'),
        ('negative-operating-inputs-accepted',
         '\tif rpm < 0.0 or rho < 0.0 or g <= 0.0:\n\t\treturn _fail("runway start needs nonnegative rpm/density and positive gravity")\n', '',
         'FAIL negative physical input'),
    ]
    results = []
    with tempfile.TemporaryDirectory(prefix='openrc-e3b2r1-mutations-') as folder:
        app = Path(folder) / 'app'
        shutil.copytree(ROOT / 'app', app, ignore=shutil.ignore_patterns('.godot', 'captures'))
        for name, old, new, expected in mutations:
            assert source.count(old) == 1, name
            (app / 'physics/ground_start.gd').write_text(source.replace(old, new, 1))
            run = subprocess.run([engine, '--headless', '--path', str(app), '--script',
                                  'res://tests/test_ground_start_integrity.gd'],
                                 capture_output=True, text=True, timeout=60)
            output = run.stdout + run.stderr
            assert run.returncode == 1 and expected in output, (name, output)
            assert 'ERROR:' not in output, (name, output)
            results.append({'mutation': name, 'exit_code': run.returncode,
                            'failed_checks': [x for x in output.splitlines() if x.startswith('FAIL ')]})
    print(json.dumps({'format': 'openrc-ground-start-mutations v1', 'results': results}, indent=2))


if __name__ == '__main__':
    main()
