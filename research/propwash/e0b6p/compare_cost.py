#!/usr/bin/env python3
"""Measure frozen E0b6 vs current correction in a disposable project; compare every 240-tick boundary."""
import argparse
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def compare(before: dict, after: dict) -> dict:
    assert len(before['rows']) == len(after['rows']) == 12
    rows = []
    for old, new in zip(before['rows'], after['rows']):
        assert (old['regime'], old['swirl_factor']) == (new['regime'], new['swirl_factor'])
        assert len(old['boundaries']) == len(new['boundaries']) == 240
        worst = {key: 0.0 for key in ('state', 'aux', 'continuous')}
        exact = True
        for a, b in zip(old['boundaries'], new['boundaries']):
            for key in worst:
                assert len(a[key]) == len(b[key])
                for x, y in zip(a[key], b[key]):
                    assert isinstance(x, (int, float)) and isinstance(y, (int, float))
                    assert math.isfinite(x) and math.isfinite(y)
                    worst[key] = max(worst[key], abs(x-y))
                    exact = exact and x == y
                    assert abs(x-y) <= 1e-9 * max(1.0, abs(x)), (new['regime'], key, x, y)
        if new['swirl_factor'] == 0.0:
            assert exact, ('zero-swirl baseline changed', new['regime'])
        rows.append({key: new[key] for key in ('regime', 'swirl_factor')} | {
            'before_median_us': old['median_us'], 'after_median_us': new['median_us'],
            'before_batches_us': old['batches_us'], 'after_batches_us': new['batches_us'],
            'speedup': old['median_us']/new['median_us'], 'exact_boundaries': exact,
            'max_absolute_boundary_difference': worst})
    return {'format': 'openrc-e0b6p-comparison v1', 'cpu': after['cpu'], 'godot': after['godot'],
            'ticks_per_timed_batch': after['ticks_per_batch'], 'trajectory_ticks': 240,
            'trajectory_tolerance': '1e-9 * max(1, abs(reference)) per component; zero swirl exact',
            'rows': rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--project', type=Path, default=ROOT/'app')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='openrc-e0b6p-cost-') as tmp:
        project = Path(tmp)/'app'
        shutil.copytree(args.project, project, ignore=shutil.ignore_patterns('.godot', 'captures'))
        runtime = project/'physics/swirl_loads.gd'
        optimized = runtime.read_bytes()
        measurements = []
        for label, code in [('before', (project/'tests/swirl_e0b6_reference.gd').read_bytes()), ('after', optimized)]:
            runtime.write_bytes(code)
            output = Path(tmp)/(label+'.json')
            result = subprocess.run([args.godot, '--headless', '--path', str(project), '--script',
                                     str(ROOT/'research/propwash/e0b6p/bench_swirl.gd'), '--', str(output)],
                                    text=True, capture_output=True, timeout=300)
            assert result.returncode == 0 and 'ERROR:' not in result.stdout+result.stderr, result.stdout+result.stderr
            measurements.append(json.loads(output.read_text()))
            print(label, 'benchmark completed')
        report = compare(*measurements)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2)+'\n')
        print('12 trajectories verified, all 240 boundaries; saved', args.output)


if __name__ == '__main__':
    main()
