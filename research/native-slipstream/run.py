#!/usr/bin/env python3
"""Gate P: build-independent, isolated oracle/native comparison on fresh local clones."""
from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ERROR = re.compile(r"^(?:SCRIPT |SHADER )?ERROR:|^FAIL", re.M)


def execute(command, log: Path, *, env=None, timeout=600):
    result = subprocess.run([str(x) for x in command], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=env, timeout=timeout)
    log.write_text(result.stdout)
    if result.returncode or ERROR.search(result.stdout):
        raise RuntimeError(f"command failed ({result.returncode}); see {log}\n{result.stdout[-5000:]}")
    return result.stdout


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f"expected one patch anchor in {path}: {old!r}")
    path.write_text(text.replace(old, new, 1))


def install_probe(project: Path, library: Path):
    folder = project / "tests/gate_p"
    folder.mkdir()
    for name in ["adapter.gd", "verify.gd"]:
        shutil.copyfile(HERE / name, folder / name)
    target = folder / library.name
    shutil.copyfile(library, target)
    # One local artifact per experiment. Other platforms run this script with their own build.
    platform_key = {".so": "linux", ".dll": "windows", ".dylib": "macos"}[library.suffix]
    (folder / "slipstream.gdextension").write_text(
        '[configuration]\nentry_symbol = "openrc_slipstream_library_init"\n'
        'compatibility_minimum = "4.7"\nreloadable = false\n\n[libraries]\n'
        f'{platform_key} = "res://tests/gate_p/{library.name}"\n')


def instrument_bench(project: Path):
    bench = project / "tests/bench_regimes.gd"
    # Add a complete body/aux/mode/clock sample, solely in the measurement copy.
    replace_once(bench, 'var _output_path: String = ""',
                 'var _output_path: String = ""\nvar gate_p_samples := PackedFloat64Array()\nvar gate_p_serial: int = 0')
    replace_once(bench, 'func _fingerprint(session: Node, fixture: Dictionary) -> Dictionary:\n',
                 'func _fingerprint(session: Node, fixture: Dictionary) -> Dictionary:\n\tgate_p_samples.clear()\n')
    text = bench.read_text()
    anchor = 'digest.update(session.sim.state.to_byte_array())'
    assert text.count(anchor) == 2
    for indent in ['\t', '\t\t']:
        old = '\n' + indent + anchor
        new = old + ''.join('\n' + indent + line for line in [
            'gate_p_samples.append_array(session.sim.state)',
            'gate_p_samples.append_array(session.sim.aux)',
            'gate_p_samples.append(float(session.sim.modes[0]))',
            'gate_p_samples.append(float(session.sim.tick))'])
        text = text.replace(old, new)
    bench.write_text(text)
    replace_once(bench, '\tvar final_state: PackedFloat64Array = session.sim.state',
                 '\tvar sample_path: String = OS.get_environment("OPENRC_GATE_P_SAMPLES").path_join("%02d.bin" % gate_p_serial)\n'
                 '\tvar sample_file: FileAccess = FileAccess.open(sample_path, FileAccess.WRITE)\n'
                 '\tsample_file.store_buffer(gate_p_samples.to_byte_array())\n'
                 '\tsample_file.close()\n\tgate_p_serial += 1\n'
                 '\tvar final_state: PackedFloat64Array = session.sim.state')


def compare_flights(oracle: dict, native: dict, reference_samples: Path, native_samples: Path, policy: dict):
    results = []
    index = 0
    for left_aircraft, right_aircraft in zip(oracle['aircraft'], native['aircraft'], strict=True):
        assert left_aircraft['id'] == right_aircraft['id']
        for regime in ['trim', 'stall', 'spin', 'ground']:
            left = left_aircraft['regimes'][regime]
            right = right_aircraft['regimes'][regime]
            for record in [left, right]:
                assert record['fingerprint']['ticks'] == oracle['fingerprint_ticks']
                assert not record['fingerprint']['fault'] and not record['timing']['fault']
            values = []
            for folder in [reference_samples, native_samples]:
                sample = array.array('d')
                sample.frombytes((folder / f'{index:02d}.bin').read_bytes())
                values.append(sample)
            assert len(values[0]) == len(values[1]) == (oracle['fingerprint_ticks'] + 1) * 19
            worst = {key: 0.0 for key in policy['components']}
            exact_discrete = True
            mapping = ['position']*3 + ['velocity']*3 + ['attitude']*4 + ['rate']*3 + ['rpm'] + ['servo']*3
            for row in range(0, len(values[0]), 19):
                for column, component in enumerate(mapping):
                    error = abs(values[0][row+column] - values[1][row+column])
                    if not math.isfinite(error):
                        error = math.inf
                    worst[component] = max(worst[component], error)
                exact_discrete &= values[0][row+17:row+19] == values[1][row+17:row+19]
            passed = exact_discrete and all(worst[k] <= policy['components'][k]['absolute'] for k in worst)
            results.append({'aircraft': left_aircraft['id'], 'regime': regime, 'ok': passed,
                            'fingerprint_exact': left['fingerprint']['sha256'] == right['fingerprint']['sha256'],
                            'discrete_clock_exact': exact_discrete, 'worst_absolute_error': worst})
            index += 1
    assert len(results) == 16
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--quick', action='store_true', help='diagnostic timing only: 3 batches, 240-tick replay')
    parser.add_argument('--skip-suite', action='store_true', help='omit the native-copy full suite (recorded in report)')
    args = parser.parse_args()
    library = args.library.resolve(strict=True)
    godot = (args.godot or Path(subprocess.check_output([str(ROOT/'app/get-godot.sh')], text=True).strip())).resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    execute([sys.executable, HERE/'test_runner.py'], output/'comparison-tests.log')
    if subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain', '--', 'app'], text=True).strip():
        raise RuntimeError('app/ must be clean: comparison uses the committed application in fresh clones')
    base_commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    environment = os.environ.copy()
    evidence = {'format': 'openrc-gate-p-native-spike v1', 'base_commit': base_commit,
                'library_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
                'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts},
                'godot': subprocess.check_output([str(godot), '--version'], text=True).strip(),
                'quick_diagnostic': args.quick, 'native_full_suite': not args.skip_suite}
    with tempfile.TemporaryDirectory(prefix='gate-p-', dir=ROOT/'.tools') as temp:
        work = Path(temp)
        projects = {}
        for mode in ['oracle', 'native']:
            checkout = work/mode
            execute(['git', 'clone', '--quiet', '--shared', '--no-hardlinks', ROOT, checkout], output/f'{mode}-clone.log')
            # Download cache is explicit. Every tracked resource comes from a fresh checkout.
            (checkout/'.tools').symlink_to(ROOT/'.tools', target_is_directory=True)
            project = checkout/'app'
            projects[mode] = project
            if mode == 'native':
                install_probe(project, library)
                replacement = 'const Slipstream := preload("res://tests/gate_p/adapter.gd")'
                original = 'const Slipstream := preload("res://physics/slipstream.gd")'
                replace_once(project/'physics/dynamics.gd', original, replacement)
                replace_once(project/'tests/bench_regimes.gd', original, replacement)
            execute([godot, '--headless', '--path', project, '--audio-driver', 'Dummy', '--import'], output/f'{mode}-import.log', timeout=180)
            instrument_bench(project)
        environment['OPENRC_GATE_P_REPORT'] = str(output/'kernel.json')
        execute([godot, '--headless', '--path', projects['native'], '--script', 'res://tests/gate_p/verify.gd'],
                output/'kernel.log', env=environment)
        evidence['kernel'] = json.loads((output/'kernel.json').read_text())
        if not args.skip_suite:
            print('Running full app/test.sh against the isolated native route', flush=True)
            execute([projects['native']/'test.sh'], output/'native-full-suite.log', env=environment, timeout=1200)
        # Measurement runs are sequential and start only after compilation/tests finish.
        runs = {}
        trajectories = None
        for repetition in [1, 2]:
            # Counterbalance ordering to reduce monotonic host drift.
            for mode in (['oracle', 'native'] if repetition == 1 else ['native', 'oracle']):
                sample_folder = work/f'{mode}-samples'
                sample_folder.mkdir(exist_ok=True)
                environment['OPENRC_GATE_P_SAMPLES'] = str(sample_folder)
                filename = f'{mode}-{repetition}.json'
                command = [godot, '--headless', '--path', projects[mode], '--script', 'res://tests/bench_regimes.gd', '--', f'--output={output/filename}']
                if args.quick:
                    command += ['--samples=3', '--ticks-per-sample=30', '--fingerprint-ticks=240']
                print(f'Measuring {mode}, run {repetition}', flush=True)
                execute(command, output/f'{mode}-{repetition}.log', env=environment)
                runs[f'{mode}-{repetition}'] = json.loads((output/filename).read_text())
            trajectories = compare_flights(runs[f'oracle-{repetition}'], runs[f'native-{repetition}'],
                                           work/'oracle-samples', work/'native-samples', evidence['kernel']['policy'])
            evidence[f'trajectories_{repetition}'] = trajectories
            if not all(row['ok'] for row in trajectories):
                (output/'verification.json').write_text(json.dumps(evidence, indent=2)+'\n')
                raise RuntimeError('native trajectories exceed unchanged H9 budgets')
        evidence['all_trajectories_pass'] = all(row['ok'] for row in trajectories)
        evidence['all_native_medians_within_budget'] = all(row['timing']['median_us_per_tick'] <= 500
            for key, run in runs.items() if key.startswith('native') for plane in run['aircraft'] for row in plane['regimes'].values())
        evidence['all_native_batch_p95_within_budget'] = all(row['timing']['p95_us_per_tick'] <= 500
            for key, run in runs.items() if key.startswith('native') for plane in run['aircraft'] for row in plane['regimes'].values())
        (output/'verification.json').write_text(json.dumps(evidence, indent=2)+'\n')
    print('Native experiment completed; inspect verification.json and all four timing distributions.')


if __name__ == '__main__':
    main()
