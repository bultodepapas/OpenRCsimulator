"""Read-only native equivalent of app/test.sh's all-GDScript parse pass."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--out', required=True)
parser.add_argument('--scripts', nargs='+', help='Optional script paths relative to app for a targeted recheck')
args = parser.parse_args()
godot = str(Path(args.godot).resolve())
paths = sorted(p for p in (ROOT / 'app').rglob('*.gd') if '.godot' not in p.parts)
if args.scripts:
    paths = [(ROOT / 'app' / name).resolve() for name in args.scripts]
    if any(not p.is_relative_to((ROOT / 'app').resolve()) or p.suffix != '.gd' or not p.is_file() for p in paths):
        parser.error('scripts must be existing GDScript files under app')

def check(path):
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    command = [godot, '--headless', '--path', str(ROOT / 'app'), '--check-only', '--script', 'res://' + path.relative_to(ROOT / 'app').as_posix()]
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=60)
        output = result.stdout + result.stderr
        ok = result.returncode == 0 and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:', output, re.M)
    except subprocess.TimeoutExpired:
        output, ok = 'TIMEOUT', False
    stable = before == hashlib.sha256(path.read_bytes()).hexdigest()
    return {'path': path.relative_to(ROOT).as_posix(), 'sha256': before, 'source_stable': stable, 'ok': ok and stable, **({'output': output} if not ok or not stable else {})}

with ThreadPoolExecutor(max_workers=2) as executor:
    results = list(executor.map(check, paths))
out = Path(args.out)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({'godot': subprocess.check_output([godot, '--version'], text=True).strip(), 'results': results}, indent=2), encoding='utf-8')
failures = [r for r in results if not r['ok']]
print(f'{len(results)} scripts, {len(failures)} failed')
for failure in failures:
    print(failure)
raise SystemExit(bool(failures))
