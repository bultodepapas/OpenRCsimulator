#!/usr/bin/env python3
"""DATA-2b: paired load timings, exact parity, component profiling and isolated negative control."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GUARD = '\t\tif a0 == lo or a0 == hi:\n\t\t\tbreak # Rounded midpoint cannot change; remaining inverse evaluations would repeat.\n'
ERROR = re.compile(r'^(?:SCRIPT |SHADER )?ERROR:', re.MULTILINE)


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('instrumentation anchor changed: ' + old)
    return text.replace(old, new)


def instrument(source):
    source = replace_once(source, 'extends RefCounted', 'extends RefCounted\nstatic var envelope_us: int = 0\nstatic var induced_us: int = 0\nstatic var map_calls: int = 0')
    anchor = '\tvar envelope := _envelope(errors, aero_node.get("envelope"), aero) if errors.is_empty() else {}'
    source = replace_once(source, anchor, '\tvar envelope_begin := Time.get_ticks_usec()\n' + anchor + '\n\tenvelope_us = Time.get_ticks_usec() - envelope_begin')
    anchor = '\tif errors.is_empty() and not envelope.is_empty() and not surfaces.is_empty():\n\t\t_induced_map(envelope, surfaces, aero, area, span, chords)'
    source = replace_once(source, anchor, '\tvar induced_begin := Time.get_ticks_usec()\n\tmap_calls = 0\n' + anchor + '\n\tinduced_us = Time.get_ticks_usec() - induced_begin')
    anchor = 'static func effective_angle_map(k_map: PackedFloat64Array, a0: float, n: int) -> PackedFloat64Array:\n'
    return replace_once(source, anchor, anchor + '\tmap_calls += 1\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--loader', type=Path, default=ROOT/'app/physics/aircraft_data.gd')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if any(args.output.iterdir()):
        parser.error('output directory must be empty')
    godot = subprocess.check_output([str(ROOT/'app/get-godot.sh')], text=True).strip()
    paths = [args.loader, ROOT/'app/physics/aero.gd', ROOT/'app/physics/math3d.gd']
    paths += sorted((ROOT/'app/data/aircraft').glob('*.json')) + sorted(HERE.glob('*.gd')) + [Path(__file__)]
    def hashes():
        return {str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    original_hashes = hashes()
    source = args.loader.read_text()
    baseline = replace_once(source, GUARD, '')
    report = {'step': 'DATA-2b', 'input_sha256': original_hashes, 'paired_runs': [], 'profiles': {}}
    def run(script, label, variables, expected=0):
        result = subprocess.run([godot, '--headless', '--path', str(ROOT/'app'), '--script', str(HERE/script)],
                                env={**os.environ, **variables}, capture_output=True, text=True, timeout=120)
        output = result.stdout + result.stderr
        (args.output/(label+'.log')).write_text(output)
        if result.returncode != expected or ERROR.search(output):
            raise RuntimeError(f'{label}: exit {result.returncode}, expected {expected}\n{output}')
        return output
    def rows(output):
        parsed = [json.loads(line) for line in output.splitlines() if line.startswith('{')]
        if len(parsed) != 4:
            raise RuntimeError('incomplete fleet output')
        return parsed
    with tempfile.TemporaryDirectory(prefix='openrc-data2b-') as temp:
        directory = Path(temp)
        before = directory/'before.gd'; before.write_text(baseline)
        after = directory/'after.gd'; after.write_text(source)
        env = {'OPENRC_DATA2B_BEFORE': str(before), 'OPENRC_DATA2B_AFTER': str(after)}
        for repeat in range(2):
            pairs = rows(run('compare.gd', f'pairs-{repeat+1}', env))
            for row in pairs:
                if row['exact_pairs'] != 24 or len(row['rows']) != 24:
                    raise RuntimeError('incomplete exact load pairs')
                row['before_median_us'] = statistics.median(v['before_us'] for v in row['rows'])
                row['after_median_us'] = statistics.median(v['after_us'] for v in row['rows'])
                row['after_range_us'] = [min(v['after_us'] for v in row['rows']), max(v['after_us'] for v in row['rows'])]
            report['paired_runs'].append(pairs)
        output = run('cases.gd', 'cases', env)
        if 'DATA-2b: 152 exact checks, 0 failed' not in output:
            raise RuntimeError('case count changed')
        report['exact_map_cases'] = 128
        report['exact_refusal_cases'] = 24
        for label, text in [('before', baseline), ('after', source)]:
            profiled = directory/(label+'-profile.gd'); profiled.write_text(instrument(text))
            profile = rows(run('profile.gd', 'profile-'+label, {'OPENRC_PROFILE_LOADER': str(profiled)}))
            for case in profile:
                counts = {row['map_calls'] for row in case['rows']}
                if len(case['rows']) != 16 or (counts != {81} if label == 'before' else not all(1 < count < 81 for count in counts)):
                    raise RuntimeError('unexpected inverse count')
                case['medians_us'] = {key: statistics.median(row[key] for row in case['rows']) for key in ('load_us', 'envelope_us', 'induced_us')}
            report['profiles'][label] = profile
        mutant = directory/'premature.gd'
        mutant.write_text(replace_once(source, 'if a0 == lo or a0 == hi:', 'if hi - lo < 0.01:'))
        output = run('cases.gd', 'premature-stop', {**env, 'OPENRC_DATA2B_AFTER': str(mutant)}, 1)
        if 'FAIL ' not in output:
            raise RuntimeError('negative control did not fail assertions')
        report['premature_stop_detected'] = True
    if hashes() != original_hashes:
        raise RuntimeError('verification inputs changed during run')
    report['limits'] = 'Warm OS cache, shared-host wall-clock measurements; no cold-start, universal timing or physical calibration claim.'
    (args.output/'verification.json').write_text(json.dumps(report, indent=2)+'\n')
    print('DATA-2b: 192 exact full loads, 128 maps, 24 refusals; premature-stop mutation detected.')
    for run_rows in report['paired_runs']:
        print([(row['aircraft'], row['before_median_us'], row['after_median_us']) for row in run_rows])


if __name__ == '__main__':
    main()
