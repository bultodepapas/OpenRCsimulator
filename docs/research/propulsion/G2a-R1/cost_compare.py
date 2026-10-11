#!/usr/bin/env python3
"""Serial, matched P-51 step-cost comparison against the pre-optimization archive."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BENCH = ROOT / 'docs/research/propulsion/G2a-RK4/cost.gd'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    engine = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
    reports = {}
    for label, root in [('baseline', args.baseline.resolve()), ('candidate', ROOT)]:
        path = out / f'cost-{label}.json'
        result = subprocess.run([engine, '--headless', '--path', str(root / 'app'),
                                 '--script', str(BENCH), '--', '--out=' + str(path)],
                                capture_output=True, text=True, timeout=180, cwd=root)
        log = result.stdout + result.stderr
        (out / f'cost-{label}.log').write_text(log)
        if result.returncode or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
            raise RuntimeError(log)
        reports[label] = json.loads(path.read_text())
    if reports['baseline']['cpu'] != reports['candidate']['cpu']:
        raise RuntimeError('Host mismatch')
    pairs = []
    for before, after in zip(reports['baseline']['cases'], reports['candidate']['cases'], strict=True):
        keys = ('weather', 'fixture', 'integrator')
        if any(before[k] != after[k] for k in keys):
            raise RuntimeError('Fixture mismatch')
        pairs.append({**{k: before[k] for k in keys},
                      'baseline_usec': before['median_batch_mean_usec'],
                      'candidate_usec': after['median_batch_mean_usec'],
                      'change_percent': 100 * (after['median_batch_mean_usec'] / before['median_batch_mean_usec'] - 1)})
    payload = {'format': 'openrc-stage-cost-comparison v1', 'baseline_commit': 'a03503655788b479547da160de024545b4b9e7bb',
               'benchmark_sha256': hashlib.sha256(BENCH.read_bytes()).hexdigest(),
               'scope': 'serial matched simulation-step batch means, not tick tails or renderer', 'pairs': pairs}
    (out / 'cost-comparison.json').write_text(json.dumps(payload, indent=2) + '\n')
    lines = ['# G2a-R1 serial step cost', '', '2026-10-09 · **Status: observational software measurement; performance acceptance open.**', '',
             'The same benchmark ran first against the clean pre-optimization archive, then against the candidate. No other Godot process ran during these measurements. Each fixture uses seven timed batches of 240 steps, each after reset and 240 warm-up steps. These are medians of batch means, not individual-tick tails. Shared-host load and sequential ordering limit causal timing conclusions.', '',
             '| Air | Fixture | Integrator | Baseline (µs) | Candidate (µs) | Change |',
             '| --- | --- | --- | ---: | ---: | ---: |']
    for pair in pairs:
        lines.append('| {weather} | {fixture} | {integrator} | {baseline_usec:.1f} | {candidate_usec:.1f} | {change_percent:+.1f}% |'.format(**pair))
    lines += ['', '[Comparison](cost-comparison.json) and [baseline](cost-baseline.json)/[candidate](cost-candidate.json) preserve all measured batch means. The [benchmark](../G2a-RK4/cost.gd) excludes trim, audio and rendering. The 500 µs target must be assessed separately from numerical parity and this shared-host measurement.', '',
              '**Reproduce:** `python3 docs/research/propulsion/G2a-R1/cost_compare.py --baseline /tmp/openrc-stage-baseline --out docs/research/propulsion/G2a-R1`.']
    (out / 'cost.md').write_text('\n'.join(lines) + '\n')
    print('Eight serial before/after pairs measured.')


if __name__ == '__main__':
    main()
