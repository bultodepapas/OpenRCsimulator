#!/usr/bin/env python3
"""Replay the saved E4a circuit and reject physics/tape mutations. Never refresh a golden implicitly."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity():
    paths = []
    for folder in (ROOT/'app', HERE, HERE.parent/'e3c2a'):
        paths.extend(p for p in folder.rglob('*') if p.suffix in ('.gd', '.py', '.json', '.godot')
                     and '.godot' not in p.parts and p.is_file())
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(set(paths))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path, help='new output directory')
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--tape', type=Path, default=HERE/'circuit.tape.gz')
    parser.add_argument('--record', action='store_true', help='deliberately record a NEW candidate into --out; tracked baseline stays intact')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    godot = args.godot or Path(subprocess.check_output([str(ROOT/'app/get-godot.sh')], text=True).strip())
    before = identity()
    summary = []
    with tempfile.TemporaryDirectory(prefix='openrc-e4a-settings-') as temporary:
        env = os.environ.copy()
        for key in ('DATA', 'CONFIG', 'CACHE'):
            env[f'XDG_{key}_HOME'] = str(Path(temporary)/key.lower())

        def invoke(script, arguments, name, expected_exit=0, parse=False):
            command = [str(godot), '--headless', '--path', str(ROOT/'app'), '--audio-driver', 'Dummy']
            if parse:
                command.append('--check-only')
            command += ['--script', str(script), '--', *arguments]
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, env=env, timeout=300)
            (out/f'{name}.log').write_text(result.stdout)
            if result.returncode != expected_exit or any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for line in result.stdout.splitlines()):
                raise RuntimeError(f'{name}: unexpected exit/engine error; see log')
            return result

        for script in HERE.glob('*.gd'):
            invoke(script, [], 'parse-'+script.stem, parse=True)
        tape = out/'circuit.tape'
        common = [f'--field={HERE / "field.reference.json"}']
        if args.record:
            invoke(HERE/'run.gd', [f'--record={tape}', f'--report={out / "record.json"}', *common], 'record')
            (out/'candidate.tape.gz').write_bytes(gzip.compress(tape.read_bytes(), mtime=0))
        else:
            tape.write_bytes(gzip.decompress(args.tape.read_bytes()))
        for mutation, expected_tick in (('none', None), ('rolling', 300), ('anchor', 60)):
            report_path = out/f'{mutation}.json'
            invoke(HERE/'run.gd', [f'--replay={tape}', f'--report={report_path}', f'--mutation={mutation}', *common],
                   mutation, 0 if mutation == 'none' else 1)
            report = json.loads(report_path.read_text())
            if mutation == 'none':
                if not report['ok'] or report['ticks'] < 24000 or report['checkpoints'] < 400:
                    raise RuntimeError('full-circuit replay incomplete')
            elif report.get('error') != 'H9 tolerance exceeded' or report.get('tick') != expected_tick:
                raise RuntimeError(f'{mutation}: wrong rejection reason/tick')
            summary.append({'case': mutation, 'report': report})
        for name in ('missing-input', 'nonfinite-input', 'missing-final', 'clock', 'position', 'auxiliary', 'initial', 'anchor-mode', 'policy', 'stamp'):
            changed = out/f'{name}.tape'
            invoke(HERE/'corrupt.gd', [str(tape), str(changed), name], 'create-'+name)
            report_path = out/f'{name}.json'
            invoke(HERE/'run.gd', [f'--replay={changed}', f'--report={report_path}', *common], name, 1)
            report = json.loads(report_path.read_text())
            expected = 'H9 tolerance exceeded' if name in ('position', 'auxiliary', 'initial') else 'invalid tape'
            if report.get('error') != expected:
                raise RuntimeError(f'{name}: wrong rejection reason')
            if expected == 'H9 tolerance exceeded' and report.get('tick') != (0 if name == 'initial' else 60):
                raise RuntimeError(f'{name}: wrong rejection tick')
            summary.append({'case': name, 'report': report})
            changed.unlink()
        # Existing H8/H9/airborne-golden consumers remain separate from the new tape format.
        for name in ('test_checkpoint', 'test_replay_policy', 'test_golden'):
            invoke(ROOT/f'app/tests/{name}.gd', [], name)
        if before != identity():
            raise RuntimeError('source changed during verification; repeat on an isolated snapshot')
        metadata = {'baseline_commit': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
                    'tape_sha256': digest(tape), 'engine_sha256': digest(godot.resolve()),
                    'source_sha256': before, 'note': 'Source hashes include uncommitted files; build dirty flag alone is insufficient.'}
        (out/'source-identity.json').write_text(json.dumps(metadata, indent=2)+'\n')
        (out/'verification.json').write_text(json.dumps({'ok': True, 'cases': summary}, indent=2)+'\n')
        print(json.dumps({'ok': True, 'cases': len(summary), 'out': str(out)}))


if __name__ == '__main__':
    main()
