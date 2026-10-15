"""Compare CR-22c-R3 effects state and bounded CPU cost against its preserved reference."""
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
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--app', type=Path, default=ROOT/'app')
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--native', action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    reference = out/'reference.gd'
    reference.write_bytes(gzip.decompress((ROOT/'docs/research/crash-damage-investigations/CR-22c-R3/reference.gd.gz').read_bytes()))
    candidate = (args.app/'render/crash/effects.gd').resolve()
    cmd = [str(args.godot.resolve()), '--path', str(args.app.resolve()), '--audio-driver', 'Dummy']
    if not args.native:
        cmd.append('--headless')
    cmd += ['--script', str(HERE/'compare.gd'), '--', '--out='+str(out/'results.json'),
            '--reference='+str(reference), '--candidate='+str(candidate)]
    with (out/'run.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=240)
    log = (out/'run.log').read_text(encoding='utf-8')
    if result.returncode or any(s in log for s in ['SCRIPT ERROR:', 'SHADER ERROR:', '\nERROR:']):
        raise SystemExit('Engine failure; inspect '+str(out/'run.log'))
    data = json.loads((out/'results.json').read_text())
    if not data['valid']:
        raise SystemExit('Parity or settling assertion failed')
    manifest = {'command':cmd, 'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [reference,candidate,HERE/'compare.gd']}}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('18,000 exact state comparisons passed. Timings cover update() CPU work, not GPU frame times.')


if __name__ == '__main__':
    main()
