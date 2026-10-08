#!/usr/bin/env python3
"""Run H8-R1 tests against removed guards, using only temporary external scripts."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, default=Path('app'))
parser.add_argument('--godot', type=Path, required=True)
args = parser.parse_args()
project = args.project.resolve()
source = (project / 'sim/simulation.gd').read_text()
test = (project / 'tests/test_checkpoint_integrity.gd').read_text()
mutations = {
    'producer_validation': ('return snapshot if can_restore_checkpoint(snapshot) else {}', 'return snapshot'),
    'restored_clock': ('_fixed_dt = candidate.dt # a compatible fresh owner has no reset-established clock yet', 'pass # removed fixed clock restoration'),
    'clock_range': ('if not _checkpoint_clock_is_valid(candidate.tick, candidate.dt):', 'if false:'),
    'derived_inverse': ('and _array_is_finite(RB.inertia_inverse(inertia), 6)', 'and true'),
}
results = []
with tempfile.TemporaryDirectory(prefix='openrc-h8r1-mutations-') as temporary:
    folder = Path(temporary)
    for name, mutation in [('control', None), *mutations.items()]:
        candidate = source
        if mutation:
            old, new = mutation
            if source.count(old) != 1:
                raise SystemExit(f'{name}: guard is not unique; update probe')
            candidate = source.replace(old, new, 1)
        helper = folder / 'simulation.gd'
        helper.write_text(candidate)
        probe = folder / 'probe.gd'
        probe.write_text(test.replace('res://sim/simulation.gd', helper.as_posix()))
        run = subprocess.run([str(args.godot.resolve()), '--headless', '--path', str(project), '--script', str(probe)], capture_output=True, text=True, timeout=30)
        output = run.stdout + run.stderr
        expected = 0 if mutation is None else 1
        if run.returncode != expected or 'ERROR:' in output:
            raise SystemExit(f'{name}: unexpected result {run.returncode}\n{output}')
        results.append({'case': name, 'exit_code': run.returncode, 'output': output.strip()})
print(json.dumps({'all_detected': True, 'results': results}, indent=2))
