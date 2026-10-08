#!/usr/bin/env python3
"""Exercise the real regression suite against disposable source mutations."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
source = (HERE / 'reduce.py').read_text()
mutations = {
    'omit_tare': ('net = values["gross"][0] - values["tare"][0]', 'net = values["gross"][0]'),
    'ignore_mass_moment_covariance': ('dx = (values["x"][0] - cg[0]) / mass', 'dx = values["x"][0] / mass'),
    'shared_datum_averaged_down': ('[0.0, common["datum_x"], 0.0]', '[0.0, common["datum_x"] / math.sqrt(len(supports)), 0.0]'),
    'shared_gain_leaks_into_cg': ('[mass * common["common_scale_gain"], 0.0, 0.0]', '[mass * common["common_scale_gain"], cg[0] * common["common_scale_gain"], 0.0]'),
}
results = {}
with tempfile.TemporaryDirectory(prefix='openrc-val5a-mutation-') as tmp:
    for name, replacement in [('control', None), *mutations.items()]:
        candidate = source
        if replacement:
            old, new = replacement
            assert source.count(old) == 1, (name, 'mutation target changed')
            candidate = source.replace(old, new)
        script = Path(tmp) / (name + '.py')
        script.write_text(candidate)
        run = subprocess.run([sys.executable, str(HERE / 'test_reduce.py')],
                             env={**os.environ, 'OPENRC_WEIGHING_REDUCER': str(script)},
                             capture_output=True, text=True, timeout=30)
        failures = [line for line in run.stderr.splitlines() if line.startswith('FAIL:')]
        ok = run.returncode == 0 if name == 'control' else run.returncode != 0 and bool(failures) and 'ERROR:' not in run.stderr
        results[name] = {'accepted': ok, 'exit_code': run.returncode, 'assertion_failures': failures}
print(json.dumps(results, indent=2))
sys.exit(0 if all(item['accepted'] for item in results.values()) else 1)
