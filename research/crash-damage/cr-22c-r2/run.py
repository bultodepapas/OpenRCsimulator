"""Compare preserved CR-22c-R2 references with current presentation on an imported app."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--app', type=Path, default=ROOT / 'app')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--native', action='store_true')
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=False)
    evidence = ROOT / 'docs/research/crash-damage-investigations/CR-22c-R2'
    inputs = {}
    commands = []
    for kind, source in [('shadow', 'render/crash/wreck.gd'), ('scenery', 'render/landscape_upgrade/scenery_bodies.gd')]:
        original = gzip.decompress((evidence / (kind + '-reference.gd.gz')).read_bytes())
        candidate = (args.app / source).read_bytes()
        inputs[kind] = {variant: hashlib.sha256(data).hexdigest() for variant, data in [('reference', original), ('candidate', candidate)]}
        paths = []
        for variant, data in [('reference', original), ('candidate', candidate)]:
            path = args.out / (kind + '-' + variant + '.gd')
            # External copies must not hide the project's registered global class.
            text = data.decode('utf-8').replace('\r\n', '\n').replace('class_name Wreck\n', '')
            path.write_text(text, encoding='utf-8', newline='\n')
            paths.append(path)
        cmd = [str(args.godot.resolve()), '--path', str(args.app.resolve()), '--audio-driver', 'Dummy']
        if not args.native:
            cmd.append('--headless')
        cmd += ['--script', str(HERE / (kind + '_bench.gd')), '--', '--out=' + str(args.out / (kind + '.json')),
                '--reference=' + str(paths[0]), '--candidate=' + str(paths[1])]
        commands.append(cmd)
        log_path = args.out / (kind + '.log')
        with log_path.open('w', encoding='utf-8') as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        log = log_path.read_text(encoding='utf-8')
        if result.returncode or any(s in log for s in ['SCRIPT ERROR:', 'SHADER ERROR:', '\nERROR:']):
            raise SystemExit('Failed: ' + str(log_path))
        data = json.loads((args.out / (kind + '.json')).read_text())
        if not data['valid']:
            raise SystemExit('Output parity failed: ' + kind)
    (args.out / 'manifest.json').write_text(json.dumps({'inputs': inputs, 'commands': commands}, indent=2), encoding='utf-8')
    print('Both output comparisons passed. Timings are CPU samples, not frame-rate acceptance.')


if __name__ == '__main__':
    main()
