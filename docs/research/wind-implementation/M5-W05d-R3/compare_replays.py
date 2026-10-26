"""R3 replay receipts; uses the existing flight-log CLI without altering tapes."""
import csv
import json
import subprocess
import sys
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'tmp/wind-tailless-r3'
GODOT = ROOT / '.tools/Godot_v4.8-beta1_win64_console.exe'
OUT = WORK / 'replays-final'


def run(tree, *args):
    command = [sys.executable, str(WORK / tree / 'tools/flight_log/flight_log.py'), *map(str, args)]
    result = subprocess.run(command, capture_output=True, text=True)
    print(result.stdout, end='', flush=True)
    if result.returncode:
        raise RuntimeError(result.stderr + result.stdout)


def rows(path):
    with path.open(newline='', encoding='utf-8') as stream:
        return list(csv.reader(stream))


summary = []
logs = sorted((WORK / 'baseline-logs').glob('*.orfl')) + sorted((WORK / 'x8-legacy-baseline').glob('*.orfl'))
for log in logs:
    # The six named accepted recordings from test_flight_log, plus the v5 trace.
    if not log.stem.startswith('skywalker_x8') and log.stem not in ['jensen_ugly_stik_60', 'gp_extra_300s_60', 'p51d_mustang_120',
                        'sebart_avanti_s_a200', 'turbo_lumber_evolution', 'stik_glow_61fx_2t', 'jensen_spatial']:
        continue
    case = OUT / log.stem
    for operation, tree, destination in [('export', 'baseline', 'export'), ('replay', 'baseline', 'exact')]:
        existing = WORK / 'replays' / log.stem / destination
        if existing.is_dir():
            # Baseline source/tape are unchanged. Preserve their completed receipts verbatim.
            shutil.copytree(existing, case / destination)
        else:
            run(tree, operation, log, '--out', case / destination, '--godot', GODOT)
    data = 'jensen_ugly_stik_60' if log.stem == 'jensen_spatial' else log.stem
    aircraft = WORK / 'candidate/app/data/aircraft' / (data + '.json')
    if data.startswith('skywalker_x8'):
        aircraft = WORK / 'candidate/app/data/aircraft' / ('battery/skywalker_x8_6s_pack.json' if '6s_pack' in data else 'skywalker_x8.json')
    run('candidate', 'replay', log, '--out', case / 'candidate', '--godot', GODOT, '--candidate', aircraft)
    run('candidate', 'compare', case / 'export/flight.csv', case / 'candidate/flight.csv', '--out', case / 'comparison.json')
    exported, exact, candidate = [rows(case / name / 'flight.csv') for name in ['export', 'exact', 'candidate']]
    assert exported == exact == candidate, log.name
    reports = {name: json.loads((case / name / ('export.json' if name == 'export' else 'replay.json')).read_text(encoding='utf-8')) for name in ['export', 'exact', 'candidate']}
    assert all(report.get('complete') and report.get('status') == 'ok' for report in reports.values()), reports
    assert reports['exact'].get('solver_changed') is False, reports['exact']
    assert reports['candidate'].get('solver_changed') is True, reports['candidate']
    summary.append({'log': log.name, 'rows': len(exported)-1, 'columns': len(exported[0]),
                    'all_csv_cells_equal': True, 'exact_solver_changed': False, 'candidate_solver_changed': True})
    print('VERIFIED', log.name, flush=True)
OUT.mkdir(exist_ok=True)
(OUT / 'parity.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
spatial = []
for log in sorted((WORK / 'x8-spatial-accepted').glob('*.orfl')):
    case = OUT / log.stem
    run('candidate', 'export', log, '--out', case / 'export', '--godot', GODOT)
    run('candidate', 'replay', log, '--out', case / 'exact', '--godot', GODOT)
    exported, exact = [rows(case / name / 'flight.csv') for name in ['export', 'exact']]
    report = json.loads((case / 'exact/replay.json').read_text(encoding='utf-8'))
    assert report['complete'] and report['status'] == 'ok' and not report['solver_changed'], report
    assert exported == exact, log.name
    spatial.append({'log': log.name, 'rows': len(exact)-1, 'columns': len(exact[0]), 'all_csv_cells_equal': True, 'solver_changed': False})
(OUT / 'spatial-exact.json').write_text(json.dumps(spatial, indent=2) + '\n', encoding='utf-8')
