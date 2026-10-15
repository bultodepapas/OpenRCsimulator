"""Reproduce DT-11a bounded helicopter canopy station scans and exact-output checks."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EVIDENCE = ROOT / 'docs/research/visual-quality-implementation/VQ-01c/loading/heli-canopy/stations'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--app', type=Path, default=ROOT / 'app')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--candidate', type=Path, help='Optional parsed draft outside app')
    args = parser.parse_args()
    if args.runs < 1:
        parser.error('--runs must be positive')
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out / 'reference.gd').write_bytes(gzip.decompress((EVIDENCE / 'reference.gd.gz').read_bytes()))
    (out / 'candidate.gd').write_bytes((args.candidate or args.app / 'render/rotor/heli_night_lights.gd').read_bytes())
    sources = [out / 'reference.gd', out / 'candidate.gd', HERE / 'compare.gd']
    manifest = {'commands': [], 'sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    for index in range(1, args.runs + 1):
        cmd = [str(args.godot.resolve()), '--path', str(args.app.resolve()), '--audio-driver', 'Dummy',
               '--script', str(HERE / 'compare.gd'), '--', '--reference=' + str(out / 'reference.gd'),
               '--candidate=' + str(out / 'candidate.gd'), '--out=' + str(out / f'native-{index}.json')]
        if index % 2 == 0:
            cmd.append('--reverse')
        manifest['commands'].append(cmd)
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        log_path = out / f'native-{index}.log'
        with log_path.open('w', encoding='utf-8') as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        log = log_path.read_text(encoding='utf-8')
        if result.returncode or any(s in log for s in ['SCRIPT ERROR:', 'SHADER ERROR:', '\nERROR:', 'WARNING:']):
            raise SystemExit('Engine check failed: ' + str(log_path))
        data = json.loads((out / f'native-{index}.json').read_text())
        if not data['valid']:
            raise SystemExit('Output parity failed: ' + str(out / f'native-{index}.json'))
        print(f'Run {index}: 12 real geometry/kit and 256 synthetic pairs passed.', flush=True)
    print('Timings cover canopy contour/kit construction only, not complete loading or FPS.')


if __name__ == '__main__':
    main()
