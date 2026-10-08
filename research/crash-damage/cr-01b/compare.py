#!/usr/bin/env python3
"""Compare CR-01b isolated projects; refuse engine errors, save exact trace hashes/timings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def run(godot, project, user, args):
    result = subprocess.run([godot, '--headless', '--path', str(project/'app'), *args],
                            env=dict(os.environ, XDG_DATA_HOME=str(user)),
                            capture_output=True, text=True, timeout=180)
    output = result.stdout+result.stderr
    if result.returncode or 'ERROR:' in output:
        raise RuntimeError(output)
    return output


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', required=True)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    ids = ['jensen-das-ugly-stik-60', 'gp-extra-300s-60', 'p51d-mustang-120', 'sebart-avanti-s-a200-p100rx']
    report = {'trace_comparison': [], 'benchmarks': {}}
    with tempfile.TemporaryDirectory(prefix='openrc-cr01b-compare-') as temp:
        work = Path(temp)
        for name, project in [('baseline', args.baseline), ('candidate', args.candidate)]:
            run(args.godot, project, work/name, ['--import'])
        for aircraft in ids:
            rows = []
            for name, project in [('baseline', args.baseline), ('candidate', args.candidate)]:
                trace = work/f'{name}-{aircraft}.csv'
                run(args.godot, project, work/name, ['--', '--aircraft='+aircraft, '--trace='+str(trace), '--t=3'])
                rows.append(''.join(line+'\n' for line in trace.read_text().splitlines() if not line.startswith('#')))
            if rows[0] != rows[1] or len(rows[0].splitlines()) != 722:
                raise RuntimeError('flight trace changed or incomplete: '+aircraft)
            report['trace_comparison'].append(dict(aircraft=aircraft, match=True, samples=721,
                                                    sha256=hashlib.sha256(rows[0].encode()).hexdigest()))
        for name, project in [('baseline', args.baseline), ('candidate', args.candidate)]:
            log = run(args.godot, project, work/name, ['--script', str(Path(__file__).with_name('benchmark.gd').resolve())])
            payloads = [line.removeprefix('CR01B_JSON=') for line in log.splitlines() if line.startswith('CR01B_JSON=')]
            if len(payloads) != 1:
                raise RuntimeError('missing benchmark output: '+log)
            report['benchmarks'][name] = json.loads(payloads[0])
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print('Four complete traces identical; baseline/candidate timing samples saved to', args.output)


if __name__ == '__main__':
    main()
