"""Native focused HELI-33 regression runner; engine error text also fails a run."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', default=str(ROOT / '.tools/Godot_v4.7.2-stable_win64_console.exe'))
parser.add_argument('--out', default=str(ROOT / 'docs/research/helicopter/HELI-33/checks'))
parser.add_argument('--tests', nargs='+', default=[
    'heli_impact_detector', 'heli_crash_visual', 'heli_crash_presentation', 'heli_crash_relaunch', 'heli_session', 'heli_ground_session',
    'heli_state_audit', 'heli_render_audit', 'heli_control_actions',
    'heli_night_lights', 'heli_night_rotor', 'controller_flight_actions',
])
args = parser.parse_args()
out = Path(args.out)
out.mkdir(parents=True, exist_ok=True)
results = []
for name in args.tests:
    script = ROOT / 'app/tests' / f'test_{name}.gd'
    start = time.monotonic()
    result = subprocess.run([args.godot, '--headless', '--path', str(ROOT / 'app'), '--audio-driver', 'Dummy', '--script', f'res://tests/test_{name}.gd'], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=420)
    output = result.stdout + result.stderr
    (out / f'test_{name}.log').write_text(output, encoding='utf-8')
    ok = result.returncode == 0 and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:|^FAIL\b', output, re.M)
    row = dict(test=name, ok=ok, exit=result.returncode, seconds=round(time.monotonic()-start, 3), sha256=hashlib.sha256(script.read_bytes()).hexdigest())
    results.append(row)
    print(json.dumps(row), flush=True)
(out / 'verification.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
raise SystemExit(0 if all(r['ok'] for r in results) else 1)
