"""Reconstruct a pre-audit kernel from Git and run a bounded paired input experiment."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
KERNEL = 'app/physics/ground_vehicle/vehicle_dynamics.gd'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--reference-ref', required=True)
    parser.add_argument('--csv', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error('--out must be new')
    args.out.mkdir(parents=True)
    commit = subprocess.check_output(['git','rev-parse',args.reference_ref], cwd=ROOT, text=True).strip()
    source = subprocess.check_output(['git','show',f'{commit}:{KERNEL}'], cwd=ROOT)
    if b'const SOLVER_VERSION := "openrc-ground-vehicle-dynamics-rk4-v4"' not in source:
        parser.error('this experiment requires the pre-audit v4 reference, not a moving HEAD')
    identity = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    before = identity(ROOT / KERNEL)
    with tempfile.TemporaryDirectory(prefix='rc-kernel-') as directory:
        reference = Path(directory) / 'reference.gd'
        reference.write_bytes(source)
        command = [str(args.godot.resolve()), '--headless','--path',str(ROOT/'app'),'--audio-driver','Dummy',
                   '--script',str(Path(__file__).with_suffix('.gd')),'--',reference.as_posix(),
                   args.csv.resolve().as_posix(),(args.out.resolve()/'comparison.json').as_posix()]
        result = subprocess.run(command,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',
                                timeout=300,creationflags=0x08000000 if os.name=='nt' else 0)
    log = result.stdout + result.stderr
    (args.out/'run.log').write_text(log, encoding='utf-8')
    comparison_path = args.out/'comparison.json'
    comparison = json.loads(comparison_path.read_text()) if comparison_path.exists() else {}
    report = {'ok':result.returncode==0 and comparison.get('complete') is True and comparison.get('ticks')==5392
                   and before==identity(ROOT/KERNEL) and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:',log,re.M),
              'reference_commit':commit,'reference_kernel_sha256':hashlib.sha256(source).hexdigest(),
              'candidate_kernel_sha256':before,'input_csv_sha256':identity(args.csv),
              'godot_sha256':identity(args.godot),'exit_code':result.returncode,'physical_validation':False}
    (args.out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(log)
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
