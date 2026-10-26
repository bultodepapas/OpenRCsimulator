"""Use the existing ORFL CLI to compare the isolated R4 solver on unchanged input tapes."""
from pathlib import Path
import csv
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent
GODOT = ROOT / '.tools/Godot_v4.8-beta1_win64_console.exe'
OUT = WORK / 'replays'


def run(tree, *args):
    command = [sys.executable, str(WORK / tree / 'tools/flight_log/flight_log.py'), *map(str, args)]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)


def rows(path):
    with path.open(newline='', encoding='utf-8') as stream:
        return list(csv.reader(stream))


summary = []
for log in sorted((WORK / 'baseline-logs').glob('*.orfl')):
    name = log.stem
    data = {'jensen_spatial': 'jensen_ugly_stik_60', 'extra_spatial': 'gp_extra_300s_60'}.get(name, name)
    if name.startswith('skywalker_x8'):
        data = 'battery/skywalker_x8_6s_pack' if '6s_pack' in name else 'skywalker_x8'
    aircraft = WORK / 'candidate/app/data/aircraft' / (data + '.json')
    assert aircraft.is_file(), aircraft
    case = OUT / name
    run('baseline', 'export', log, '--out', case / 'export', '--godot', GODOT)
    run('baseline', 'replay', log, '--out', case / 'exact', '--godot', GODOT)
    run('candidate', 'replay', log, '--candidate', aircraft, '--out', case / 'candidate', '--godot', GODOT)
    run('candidate', 'compare', case / 'export/flight.csv', case / 'candidate/flight.csv', '--out', case / 'comparison.json')
    exported, exact, candidate = [rows(case / branch / 'flight.csv') for branch in ['export', 'exact', 'candidate']]
    assert exported == exact == candidate, name
    reports = {branch: json.loads((case / branch / ('export.json' if branch == 'export' else 'replay.json')).read_text()) for branch in ['export', 'exact', 'candidate']}
    assert all(r.get('complete') and r.get('status') == 'ok' for r in reports.values())
    assert reports['exact']['solver_changed'] is False and reports['candidate']['solver_changed'] is True
    summary.append({'log': log.name, 'rows': len(exact)-1, 'columns': len(exact[0]), 'all_csv_cells_equal': True,
                    'exact_solver_changed': False, 'candidate_solver_changed': True})
    print('VERIFIED', log.name, len(exact)-1, 'rows', flush=True)
assert len(summary) == 12
(OUT / 'parity.json').write_text(json.dumps(summary, indent=2) + '\n')
