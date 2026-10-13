"""AV-20 paired native evidence on two frozen app copies; no physical calibration.

Run with --baseline <repo> --candidate <repo> --godot <binary> --out <fresh-dir>.
Both app copies must already have imported resources. Deliberate mutations use
separate scripts in the evidence directory and never modify either app copy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys


def execute(binary: Path, app: Path, script: Path, log: Path, *arguments: str,
            expected_success: bool = True) -> str:
    result = subprocess.run([str(binary), '--headless', '--path', str(app), '--audio-driver', 'Dummy',
                             '--script', str(script), '--', *arguments],
                            capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    log.write_text(output, encoding='utf8')
    if 'SCRIPT ERROR:' in output or '\nERROR:' in output:
        raise RuntimeError(f'{log.name}: runtime error, not a completed assertion run')
    if expected_success and result.returncode:
        raise RuntimeError(f'{log.name}: native process returned {result.returncode}')
    if not expected_success and (result.returncode == 0 or 'FAIL ' not in output or '41 checks,' not in output):
        raise RuntimeError(f'{log.name}: mutation did not reach and fail the completed test suite')
    return output


def load_probe(path: Path) -> dict:
    report = json.loads(path.read_text(encoding='utf8'))
    if report['schema'] != 'openrc.av20.native-probe/v1' or len(report['cases']) != 5:
        raise ValueError('wrong or incomplete native probe')
    for case in report['cases']:
        if not case['ok'] or case['ticks'] != 720 or case['duration_s'] != 3.0:
            raise ValueError('incomplete flight case')
        if len(case['final_state']) != 13 or not all(math.isfinite(x) for x in case['final_state']):
            raise ValueError('non-finite body state')
        if len(case['interval_sha256']) != 6:
            raise ValueError('missing interval snapshots')
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['baseline', 'candidate', 'godot', 'out']:
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    if args.out.exists():
        raise SystemExit('--out must be fresh')
    args.out.mkdir(parents=True)
    root = Path(__file__).resolve().parents[3]
    probe = Path(__file__).with_name('probe.gd')
    reports = {}
    for name, repo in [('baseline', args.baseline), ('candidate', args.candidate)]:
        dest = args.out / (name + '.json')
        execute(args.godot, repo / 'app', probe, args.out / (name + '.log'), '--out=' + str(dest))
        reports[name] = load_probe(dest)
        response = args.out / (name + '-response.json')
        response.write_text(json.dumps(reports[name]['response']), encoding='utf8')
        reduced = subprocess.run([sys.executable, str(root / 'research/avanti-s/av18/response_metrics.py'), str(response)],
                                 capture_output=True, text=True, timeout=20)
        if reduced.returncode:
            raise RuntimeError(reduced.stderr)
        metrics = json.loads(reduced.stdout)
        (args.out / (name + '-response-metrics.json')).write_text(json.dumps(metrics, indent=2), encoding='utf8')
    pairs = []
    for before, after in zip(reports['baseline']['cases'], reports['candidate']['cases']):
        if before['id'] != after['id']:
            raise ValueError('pair identities changed')
        turbine = before['id'] == 'sebart-avanti-s-a200-p100rx'
        identical = before['state_sha256'] == after['state_sha256'] and before['interval_sha256'] == after['interval_sha256']
        if not turbine and not identical:
            raise ValueError('inactive aircraft changed: ' + before['id'])
        if turbine and identical:
            raise ValueError('turbine candidate did not change integration')
        pairs.append({'id': before['id'], 'complete_state_identical': identical,
                      'endpoint_rpm_delta': after['final_rpm'] - before['final_rpm'],
                      'endpoint_body_max_abs_delta': max(abs(a-b) for a, b in zip(after['final_state'], before['final_state']))})
    candidate = args.candidate / 'app'
    native_test = candidate / 'tests/test_turbine_continuous.gd'
    control = execute(args.godot, candidate, native_test, args.out / 'positive-control.log')
    if '41 checks, 0 failed' not in control:
        raise RuntimeError('positive control incomplete')
    flight_source = (candidate / 'sim/flight_session.gd').read_text(encoding='utf8')
    test_source = native_test.read_text(encoding='utf8')
    mutations = {
        'endpoint-rpm-in-stage': ('func _turbine_evaluate(s: PackedFloat64Array, values: PackedFloat64Array, stage_time: float) -> Dictionary:\n\tvar rpm: float = _turbine_rpm(values)',
                                  'func _turbine_evaluate(s: PackedFloat64Array, values: PackedFloat64Array, stage_time: float) -> Dictionary:\n\tvar rpm: float = sim.aux[AUX_RPM]'),
        'stale-endpoint-mirror': ('\tout[AUX_RPM] = rpm\n\treturn out\n\n\n## Pure RK stage response',
                                  '\tout[AUX_RPM] = sampled[AUX_RPM]\n\treturn out\n\n\n## Pure RK stage response'),
    }
    rejected = []
    for name, (old, new) in mutations.items():
        if flight_source.count(old) != 1:
            raise RuntimeError('mutation source is ambiguous: ' + name)
        mutant = args.out / (name + '-flight.gd')
        mutant.write_text(flight_source.replace(old, new), encoding='utf8')
        test = args.out / (name + '-test.gd')
        test.write_text(test_source.replace('preload("res://sim/flight_session.gd")',
                                           'preload(' + json.dumps(str(mutant)) + ')'), encoding='utf8')
        output = execute(args.godot, candidate, test, args.out / (name + '.log'), expected_success=False)
        rejected.append({'id': name, 'failed_assertions': [line for line in output.splitlines() if line.startswith('FAIL ')]})
    hashes = {}
    for file in ['physics/turbine.gd', 'sim/flight_session.gd', 'data/aircraft/sebart_avanti_s_a200.json']:
        hashes[file] = {name: hashlib.sha256((repo / 'app' / file).read_bytes()).hexdigest()
                        for name, repo in [('baseline', args.baseline), ('candidate', args.candidate)]}
    summary = {'schema': 'openrc.av20.verification/v1', 'physical_validation': False,
               'paired_flights': pairs, 'mutations_rejected': rejected, 'source_sha256': hashes,
               'timing_scope': 'observational probe timing only; not the idle-host Gate P measurement'}
    (args.out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf8')
    print(json.dumps({'paired_flights': len(pairs), 'inactive_exact': sum(x['complete_state_identical'] for x in pairs),
                      'rejected_mutations': len(rejected)}))


if __name__ == '__main__':
    main()
