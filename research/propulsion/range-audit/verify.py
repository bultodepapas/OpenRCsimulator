"""Reproduce G1b1 tests, isolated mutations and real-session query comparisons."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import audit as A

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def source_hashes():
    paths = [p for p in (ROOT/'app').rglob('*') if p.is_file() and '.godot' not in p.parts
             and p.suffix in ('.gd', '.json', '.tscn', '.godot')]
    paths += [p for p in HERE.iterdir() if p.suffix in ('.py', '.gd', '.json')]
    paths += [ROOT/'app/tests/check_trimmed_flight.py']
    return {str(p.relative_to(ROOT)): A.digest(p.read_bytes()) for p in sorted(paths)}


def run(command, log, *, env=None, expect=0):
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    log.write_text(output)
    if result.returncode != expect or 'SCRIPT ERROR:' in output or '\nERROR:' in output:
        raise RuntimeError(f'failed command: {command}; see {log}')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--godot', type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        raise ValueError('verification output directory must be empty (no stale artifacts)')
    godot = str(args.godot.resolve()) if args.godot else subprocess.check_output(
        [str(ROOT/'app/get-godot.sh')], text=True).strip()
    before = source_hashes()
    test = run([sys.executable, '-m', 'unittest', 'discover', '-s', str(HERE), '-v'], out/'unit.log')
    if 'Ran 20 tests' not in test or not test.rstrip().endswith('OK'):
        raise RuntimeError('focused suite did not execute expected tests')
    mutations = {
        'rpm-as-rps': ('((rpm/60.0)*diameter)', '(rpm*diameter)'),
        'wrong-state-timing': ('query[key] = previous[key]', 'query[key] = current[key]'),
        'inclusive-gap': ('a < advance < b', 'a <= advance <= b'),
    }
    for name, (old, new) in mutations.items():
        with tempfile.TemporaryDirectory(prefix='openrc-range-mutation-') as temp:
            root = Path(temp)
            directory = root/'research/propulsion/range-audit'
            directory.mkdir(parents=True)
            (root/'app/tests').mkdir(parents=True)
            shutil.copyfile(ROOT/'app/tests/check_trimmed_flight.py', root/'app/tests/check_trimmed_flight.py')
            shutil.copyfile(HERE/'test_audit.py', directory/'test_audit.py')
            source = (HERE/'audit.py').read_text()
            assert source.count(old) == 1
            (directory/'audit.py').write_text(source.replace(old, new))
            log = run([sys.executable, '-m', 'unittest', 'discover', '-s', str(directory), '-v'],
                      out/f'mutation-{name}.log', expect=1)
            if 'AssertionError' not in log or 'ERROR:' in log:
                raise RuntimeError(f'{name} did not fail by the intended assertions')
    with tempfile.TemporaryDirectory(prefix='openrc-range-settings-') as settings:
        env = dict(os.environ, OPENRC_RANGE_OUTPUT=str(out), XDG_DATA_HOME=settings+'/data',
                   XDG_CONFIG_HOME=settings+'/config')
        run([godot, '--headless', '--path', str(ROOT/'app'), '--script', str(HERE/'flights.gd')],
            out/'flights.log', env=env)
        for test_name in ('test_propulsion', 'test_trace_metadata'):
            run([godot, '--headless', '--path', str(ROOT/'app'), '--script', f'res://tests/{test_name}.gd'],
                out/(test_name+'.log'), env=env)
    flights = json.loads((out/'oracle.json').read_text())
    if len(flights) != 6:
        raise RuntimeError('six flight cases required')
    summaries = []
    max_error = 0.0
    comparisons = 0
    for flight in flights:
        aircraft_path = ROOT/f'app/data/aircraft/{flight["aircraft_file"]}.json'
        aircraft = aircraft_path.read_bytes()
        trace_path = out/(flight['name']+'.csv')
        coverage_path = HERE/'stik-coverage.json' if flight['name'].startswith('stik_') else None
        command = [sys.executable, str(HERE/'audit.py'), str(trace_path), '--aircraft', str(aircraft_path),
                   '--ticks', str(flight['ticks']), '--assume-still-air', '--output', str(out/(flight['name']+'.json'))]
        if coverage_path:
            command += ['--coverage', str(coverage_path)]
        run(command, out/(flight['name']+'-audit.log'))
        report = json.loads((out/(flight['name']+'.json')).read_text())
        diameter, axis, tables = A.propeller(A.decode(aircraft))
        _, samples = A.read_trace(trace_path.read_bytes(), A.digest(aircraft), flight['ticks'], 240)
        if flight['name'] in ('stik_dive_idle', 'stik_full_power'):
            expected_throttle = 0.0 if flight['name'] == 'stik_dive_idle' else 1.0
            assert all(s['cmd_throttle'] == expected_throttle for s in samples), 'fixture throttle not sampled'
            assert all(abs(s['engine_rpm'] - samples[0]['engine_rpm']) < 1e-8 for s in samples), 'fixture RPM drifts from target'
        assert len(flight['queries']) == flight['ticks']
        for previous, current, oracle in zip(samples, samples[1:], flight['queries']):
            query = dict(current)
            for key in ('u_mps', 'v_mps', 'w_mps'):
                query[key] = previous[key]
            point = A.classify(query, diameter, axis, tables, {})
            assert point['tick'] == oracle['tick']
            assert (point['advance_ratio'] is None) == oracle['stopped']
            if not oracle['stopped']:
                error = abs(point['advance_ratio'] - oracle['J'])
                assert error <= 1e-8, (flight['name'], error)
                max_error = max(max_error, error)
            comparisons += 1
        summaries.append({'name': flight['name'], 'ticks': flight['ticks'],
                          'active_j_range': report['active_j_range'], 'counts': report['counts']})
    by_name = {s['name']: s for s in summaries}
    assert by_name['stik_dive_idle']['counts']['ct_table']['above_table'] == 480
    assert by_name['stik_full_power']['counts']['ct_table']['documented_j_gap'] > 0
    assert by_name['stik_stopped']['counts']['ct_table']['stopped'] == 240
    assert source_hashes() == before, 'source changed during verification; repeat on a stable snapshot'
    summary = {'step': 'G1b1', 'source_sha256': before, 'unit_tests': 20,
               'rejected_mutations': list(mutations), 'engine_query_comparisons': comparisons,
               'max_advance_ratio_error_from_csv_rounding': max_error, 'flights': summaries,
               'evidence_sha256': {p.name: A.digest(p.read_bytes()) for p in sorted(out.iterdir()) if p.is_file()}}
    (out/'verification.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps({'tests': 20, 'mutations': 3, 'engine_query_comparisons': comparisons,
                      'max_J_error': max_error, 'flights': summaries}, indent=2))


if __name__ == '__main__':
    main()
