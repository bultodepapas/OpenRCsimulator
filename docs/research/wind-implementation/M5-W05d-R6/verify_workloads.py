"""Run the existing checked Godot harness sequentially, with timing disabled."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent
APP = WORK / 'candidate/app'
ENGINE = ROOT / '.tools/Godot_v4.8-beta1_win64_console.exe'
OUTPUT = WORK / 'candidate-workloads'
OUTPUT.mkdir(exist_ok=False)
source_manifest = WORK / 'source-manifest.json'
identity = [
    '--revision=' + (WORK/'base-revision.txt').read_text().strip(),
    '--manifest-sha256=' + hashlib.sha256(source_manifest.read_bytes()).hexdigest(),
]
cases = [
    ('trainer', 'jensen-das-ugly-stik-60', False, ['legacy-v4-steady', 'spatial-v5-modes-24',
        'spatial-v5-gusts-24', 'spatial-v5-thermals-24', 'spatial-v5-gusts-thermals-24']),
    ('aerobatic', 'gp-extra-300s-60', False, ['spatial-v5-gusts-thermals-24']),
    ('turbo', 'turbo-lumber-evolution', False, ['spatial-v5-gusts-thermals-24']),
    ('x8-ideal', 'skywalker-x8', False, ['spatial-v5-gusts-thermals-24']),
    ('x8-pack', 'skywalker-x8', True, ['spatial-v5-gusts-thermals-24']),
]
summary = []
for label, aircraft, battery, weather in cases:
    output = OUTPUT / (label + '.json')
    command = [sys.executable, str(ROOT/'tools/godot/run_checked.py'), '--timeout', '600',
        '--out-dir', str(WORK/'checks'), '--label', label, '--require-text', 'wrote ', '--',
        str(ENGINE), '--headless', '--path', str(APP), '--audio-driver', 'Dummy',
        '--script', 'res://tests/bench_spatial_wind.gd', '--', '--full-session', '--verify-only',
        '--aircraft='+aircraft, '--output='+str(output), *identity,
        *['--case='+value for value in weather], *(['--battery'] if battery else [])]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (OUTPUT / (label + '.cli.log')).write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        print(result.stdout, flush=True)
        raise SystemExit(result.returncode)
    report = json.loads(output.read_text())
    assert report['measurement_mode'] == 'verification-only'
    assert report['benchmark_sha256'] == hashlib.sha256((APP/'tests/bench_spatial_wind.gd').read_bytes()).hexdigest()
    for group in report['aircraft']:
        assert group['id'] == aircraft
        assert group['data_sha256'] == hashlib.sha256((APP/group['data'].removeprefix('res://')).read_bytes()).hexdigest()
        for case in group['cases']:
            assert case['accepted_workload_ticks'] == 1440 and case['accepted_warmup_ticks'] == 720
            assert case['reset_checks_passed'] == case['reset_checks_expected'] == 9
            assert case['final_states_repeatable']
            coverage = case['workload_coverage']
            assert coverage['matches_production'] and coverage['accepted_ticks'] == 480
            assert coverage['first_query_time_s'] == 0.0 and coverage['last_query_time_s'] == 2.0
            assert not any('us_per_' in k or k.startswith('ratio_') or 'budget_fraction' in k or 'timed_ticks' in k for k in case)
            if 'gusts' in case['case_id']:
                assert coverage['gust_peak_mps'] >= .01 and coverage['gust_queries_above_1e_minus_6_mps'] > 0
            if 'thermals' in case['case_id']:
                assert coverage['thermal_peak_mps'] >= .01 and coverage['thermal_queries_above_1e_minus_6_mps'] > 0
            summary.append({'aircraft': aircraft, 'power_variant': report['power_variant'],
                'case': case['case_id'], 'coverage': coverage,
                'first_tick_queries': case['queries_per_accepted_tick_untimed']})
    print(f'{label}: {len(weather)} workloads verified, no timing values', flush=True)
(OUTPUT/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
print(f'PASS: {len(summary)} workloads; {len(summary)*2640} accepted ticks including coverage replays', flush=True)
