"""Bounded actual-lake driving proof; retain exact runtime identities and logs."""
import argparse
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def sources():
    paths = []
    for directory in ['app/physics/ground_vehicle', 'app/sim/ground_vehicle',
                      'app/vehicles/ground', 'app/native/ground_vehicle', 'app/data/ground_vehicle',
                      'app/data/fields', 'app/data/vehicles/ground', 'app/render/lake',
                      'app/assets/landscape/lake']:
        paths.extend(p for p in (ROOT / directory).rglob('*')
                     if p.is_file() and p.suffix not in ['.uid', '.import'])
    paths.extend([Path(__file__), Path(__file__).with_suffix('.gd')])
    paths.extend(ROOT / p for p in ['app/physics/lake_surface.gd', 'app/physics/ground_terrain.gd',
                 'app/physics/ground_surfaces.gd', 'app/physics/ground_contact.gd', 'app/physics/math3d.gd',
                 'app/physics/integrator.gd', 'app/data/lake_loader.gd', 'app/data/field_loader.gd'])
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    if args.out.exists():
        parser.error('--out must be a new directory')
    args.out.mkdir(parents=True)
    stem = args.out.resolve() / 'water-entry'
    before = sources()
    command = [str(args.godot.resolve()), '--path', str(ROOT / 'app'), '--audio-driver', 'Dummy']
    command += ['--rendering-method', 'gl_compatibility', '--position', '-16000,-16000',
                '--resolution', '1280x720'] if args.capture else ['--headless']
    command += ['--script', str(Path(__file__).with_suffix('.gd')), '--', '--output=' + str(stem)]
    if args.capture:
        command.append('--capture')
    log = stem.with_suffix('.log')
    with log.open('w', encoding='utf-8') as stream:
        process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        deadline = time.monotonic() + 300
        while process.poll() is None:
            time.sleep(0.2)
            tail = log.read_text(encoding='utf-8', errors='replace')[-8000:]
            if time.monotonic() > deadline or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', tail, re.M):
                process.kill()
                process.wait(timeout=10)
                break
        code = process.returncode
    output = log.read_text(encoding='utf-8', errors='replace')
    result = json.loads(stem.with_suffix('.json').read_text()) if stem.with_suffix('.json').exists() else {}
    stable = before == sources()
    ok = code == 0 and stable and result.get('ok') is True and re.search(r'^(?:SCRIPT |SHADER )?ERROR:|^FAIL', output, re.M) is None
    receipt = {'ok': ok, 'exit_code': code, 'sources_unchanged': stable, 'source_sha256': before,
               'godot_sha256': hashlib.sha256(args.godot.read_bytes()).hexdigest(),
               'command': command, 'physical_validation': False,
               'artifact_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in args.out.iterdir() if p.is_file()}}
    (args.out / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'ok': ok, 'ticks': result.get('ticks'), 'phases': list(result.get('phases', {})),
                      'tick_p95_us': result.get('tick_p95_us'), 'output': str(args.out)}))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
