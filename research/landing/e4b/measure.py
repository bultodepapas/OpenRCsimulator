#!/usr/bin/env python3
"""Measure E4a long-circuit math sensitivity in disposable copies; never edit app/."""
import argparse
import gzip
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*'))
            if p.is_file() and p.suffix in ('.gd', '.py', '.json', '.godot', '.gz')
            and '.godot' not in p.parts and '__pycache__' not in p.parts}


def validate(report, direction):
    if (not report['ok'] or report['ticks'] != 28861 or report['checkpoints'] != 483
            or len(report['branches']) != report['ticks'] or len(report['modes']) != report['ticks']):
        raise ValueError('incomplete circuit report')
    if report['direction'] != direction or len(report['math_check']) != 6:
        raise ValueError('missing perturbation proof')
    for probe in report['math_check']:
        base = struct.unpack('<d', bytes.fromhex(probe['builtin']))[0]
        expected = math.nextafter(base, math.inf if direction > 0 else -math.inf) if direction else base
        if struct.pack('<d', expected).hex() != probe['wrapper']:
            raise ValueError('wrapper did not move exactly one adjacent float')
    components = report['policy']['components']
    if set(report['metrics']) != set(components):
        raise ValueError('missing numerical component')
    for name, metric in report['metrics'].items():
        if (not math.isfinite(metric['max_absolute']) or metric['max_absolute'] < 0
                or metric['tolerance'] != components[name]['absolute']
                or not math.isclose(metric['max_ratio'], metric['max_absolute'] / metric['tolerance'], rel_tol=1e-12)):
            raise ValueError('invalid numerical metric')


def compact(report):
    """Intern exact decision sequences; retain every selected branch at every tick."""
    table, indices, lookup = [], [], {}
    for row in report.pop('branches'):
        key = tuple(tuple(part) for part in row)
        if key not in lookup:
            lookup[key] = len(table)
            table.append(row)
        indices.append(lookup[key])
    report['branch_table'] = table
    report['branch_indices'] = indices
    return report


def differences(base, other):
    result = {}
    for key in ('branches', 'modes'):
        if key == 'branches':
            a = [base['branch_table'][i] for i in base['branch_indices']]
            b = [other['branch_table'][i] for i in other['branch_indices']]
        else:
            a, b = base[key], other[key]
        if len(a) != len(b) or len(a) != base['ticks']:
            raise ValueError('different timeline lengths')
        ticks = [i + 1 for i, (x, y) in enumerate(zip(a, b)) if x != y]
        result[key] = {'different_ticks': len(ticks), 'first_tick': ticks[0] if ticks else None}
        if ticks:
            result[key]['first_baseline'] = a[ticks[0] - 1]
            result[key]['first_candidate'] = b[ticks[0] - 1]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT, help='repository snapshot supplying app/')
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--out', type=Path, required=True, help='new evidence directory')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = args.source.resolve()
    godot = (args.godot or Path(subprocess.check_output([str(ROOT/'app/get-godot.sh')], text=True).strip())).resolve()
    original = hashes(source/'app')
    research_identity = {**{'e4a/'+p: h for p, h in hashes(HERE.parent/'e4a').items()},
                         **{'e4b/'+p: h for p, h in hashes(HERE).items()}}
    reports = {}
    with tempfile.TemporaryDirectory(prefix='openrc-e4b-') as temporary:
        work = Path(temporary)
        frozen = work/'source'
        shutil.copytree(source/'app', frozen/'app', ignore=shutil.ignore_patterns('.godot', 'captures'))
        for folder in ('e4a', 'e4b'):
            shutil.copytree(HERE.parent/folder, frozen/'research/landing'/folder,
                            ignore=shutil.ignore_patterns('__pycache__'))
        if hashes(frozen/'app') != original or hashes(source/'app') != original:
            raise RuntimeError('app changed while freezing; retry on an isolated snapshot')
        spec = importlib.util.spec_from_file_location('h7', frozen/'app/tests/check_math_sensitivity.py')
        h7 = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(h7)
        tape = work/'circuit.tape'
        tape.write_bytes(gzip.decompress((frozen/'research/landing/e4a/circuit.tape.gz').read_bytes()))
        for name, direction in (('raw', 0), ('baseline', 0), ('up', 1), ('down', -1), ('branch-control', 0)):
            case = work/name
            shutil.copytree(frozen, case, ignore=shutil.ignore_patterns('__pycache__'))
            project = case/'app'
            if name == 'raw':
                for filename in ('aero', 'ground_contact', 'propulsion'):
                    path = project/f'physics/{filename}.gd'
                    path.write_text(h7.replace_once(path.read_text(), 'extends RefCounted\n',
                                    'extends RefCounted\nstatic var h7_branch_tape: Array[int] = []\n', filename))
            else:
                h7.instrument_branches(project)
            if name == 'branch-control':
                h7.mutate_branch(project)
            if direction:
                path = project/'physics/math3d.gd'
                text = path.read_text()
                helper = json.dumps(str(case/'research/landing/e4b/math_probe.gd'))
                text = h7.replace_once(text, 'extends RefCounted\n', f'extends RefCounted\nconst E4bMath = preload({helper})\n', 'math helper')
                for expression in ('sin(a)', 'atan2(y, x)'):
                    text = h7.replace_once(text, f'\treturn {expression}\n', f'\treturn E4bMath.apply({expression})\n', expression)
                path.write_text(text)
            report_path = case/'report.json'
            env = os.environ.copy()
            for kind in ('DATA', 'CONFIG', 'CACHE'):
                env[f'XDG_{kind}_HOME'] = str(case/kind.lower())
            command = [str(godot), '--headless', '--path', str(project), '--audio-driver', 'Dummy',
                       '--script', str(case/'research/landing/e4b/probe.gd'), '--', str(tape),
                       str(case/'research/landing/e4a/field.reference.json'), str(report_path), str(direction)]
            proc = subprocess.run(command, capture_output=True, text=True, timeout=300, env=env)
            log = proc.stdout + proc.stderr
            (out/f'{name}.log').write_text(log)
            if proc.returncode or any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for line in log.splitlines()):
                raise RuntimeError(f'{name}: engine failure; see log')
            report = json.loads(report_path.read_text())
            validate(report, direction)
            reports[name] = compact(report)
            (out/f'{name}.json.gz').write_bytes(gzip.compress(json.dumps(report, separators=(',', ':')).encode(), mtime=0))
            print(f'{name}: {report["ticks"]} ticks, max H9 ratio {max(m["max_ratio"] for m in report["metrics"].values()):.8g}', flush=True)
        base, raw = reports['baseline'], reports['raw']
        if base['exact_samples'] != 483 or raw['exact_samples'] != 483 or base['trajectory_sha256'] != raw['trajectory_sha256']:
            raise RuntimeError('instrumentation changed trajectory or baseline differs from frozen E4a tape')
        comparison = {name: differences(base, reports[name]) for name in ('up', 'down', 'branch-control')}
        if comparison['branch-control']['branches']['different_ticks'] == 0:
            raise RuntimeError('branch negative control was not detected')
        summary = {'ok': True, 'ticks': base['ticks'], 'checkpoints': base['checkpoints'],
                   'instrumentation_bit_exact_every_tick': True, 'comparison': comparison,
                   'cases': {name: {k: v for k, v in report.items() if k not in ('branch_table', 'branch_indices', 'modes')}
                             for name, report in reports.items()}}
        (out/'verification.json').write_text(json.dumps(summary, indent=2)+'\n')
        identity = {'source_commit': subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
                    'app_sha256': original, 'research_sha256': research_identity,
                    'engine_sha256': digest(godot), 'tape_sha256': digest(tape)}
        (out/'source-identity.json').write_text(json.dumps(identity, indent=2)+'\n')
    print(json.dumps({'ok': True, 'out': str(out)}))


if __name__ == '__main__':
    main()
