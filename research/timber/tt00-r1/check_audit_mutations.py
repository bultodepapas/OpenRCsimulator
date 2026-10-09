#!/usr/bin/env python3
"""Prove the R1 audit rejects a changed pivot and a reversed declared axis."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def run(package, output):
    rows = []
    with tempfile.TemporaryDirectory(prefix='timber-r1-mutation-') as folder:
        root = Path(folder); copy = root/'package'; (copy/'export').mkdir(parents=True)
        for name in ['aircraft.glb', 'aircraft_demo.glb']:
            shutil.copy2(package/'export'/name, copy/'export'/name)
        for case in ['control', 'pivot_shift', 'axis_flip']:
            metadata = json.loads((package/'metadata.json').read_text())
            joint = metadata['articulations']['rudder_hinge']
            if case == 'pivot_shift':
                joint['pivot_sim_m'][0] += .01
            if case == 'axis_flip':
                joint['axis_sim'] = [-x for x in joint['axis_sim']]
            (copy/'metadata.json').write_text(json.dumps(metadata))
            report = root/(case+'.json')
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('audit_glb.py')),
                                     str(copy), str(report)], capture_output=True, text=True, timeout=30)
            checks = json.loads(report.read_text())['checks']
            failed = [name for name, passed in checks.items() if not passed]
            expected = {'control': [], 'pivot_shift': ['pivots_within_0p01mm'],
                        'axis_flip': ['axes_within_1e_minus5']}[case]
            assert failed == expected, (case, failed)
            assert result.returncode == (0 if case == 'control' else 1)
            rows.append(dict(case=case, exit_code=result.returncode, failed_checks=failed))
    output.write_text(json.dumps(rows, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path); parser.add_argument('output', type=Path)
    args = parser.parse_args(); run(args.package, args.output)
