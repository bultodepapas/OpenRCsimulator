"""Reproduce DT-11a shadow-mask cache comparisons on an imported Godot project."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EVIDENCE = ROOT/'docs/research/visual-quality-implementation/VQ-01c/loading/shadow-mask-cache'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--app', type=Path, default=ROOT/'app')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=5)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error('--runs must be positive')
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out/'reference.gd').write_bytes(gzip.decompress((EVIDENCE/'reference.gd.gz').read_bytes()))
    (out/'candidate.gd').write_bytes((args.app/'render/shadow.gd').read_bytes())
    commands = []
    for index in range(args.runs):
        cmd = [str(args.godot.resolve()), '--path', str(args.app.resolve()), '--audio-driver', 'Dummy',
               '--script', str(HERE/'compare.gd'), '--', '--directory='+str(out), '--output='+str(out/f'native-{index}.json')]
        if index % 2:
            cmd.append('--reverse')
        commands.append(cmd)
        with (out/f'native-{index}.log').open('w', encoding='utf-8') as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=120)
        log = (out/f'native-{index}.log').read_text(encoding='utf-8')
        if result.returncode or any(s in log for s in ['SCRIPT ERROR:', 'SHADER ERROR:', '\nERROR:']):
            raise SystemExit('Engine failure: '+str(out/f'native-{index}.log'))
        if not json.loads((out/f'native-{index}.json').read_text())['complete']:
            raise SystemExit('Output parity failed')
    sources = [out/'reference.gd', out/'candidate.gd', HERE/'compare.gd']
    (out/'manifest.json').write_text(json.dumps({'commands':commands,'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}},indent=2)+'\n',encoding='utf-8')
    print(f'{20*args.runs} exact native image/carrier pairs passed; timings are construction cost, not full loading or FPS.')


if __name__ == '__main__':
    main()
