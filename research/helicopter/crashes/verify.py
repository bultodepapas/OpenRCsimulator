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
runtime_paths = [ROOT / 'app' / path for path in [
    'helicopter_main.gd', 'sim/helicopter_flight_session.gd', 'sim/simulation.gd',
    'sim/scenery_collision.gd', 'scenery/collision_world.gd', 'scenery/collision_setup.gd',
    'physics/rigid_body.gd', 'physics/math3d.gd', 'physics/ground_terrain.gd',
    'physics/ground_contact.gd', 'physics/effective_mass.gd',
    'physics/rotorcraft/flight_dynamics.gd', 'physics/rotorcraft/skid_contact.gd',
    'physics/rotorcraft/impact_detector.gd', 'render/rotor/heli_wreck.gd',
    'render/rotor/heli_crash_presentation.gd', 'render/crash/wreck.gd',
    'render/crash/effects.gd', 'render/crash/crash_audio.gd',
]]
def identities():
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in runtime_paths}
for name in args.tests:
    script = ROOT / 'app/tests' / f'test_{name}.gd'
    before = identities()
    start = time.monotonic()
    result = subprocess.run([args.godot, '--headless', '--path', str(ROOT / 'app'), '--audio-driver', 'Dummy', '--script', f'res://tests/test_{name}.gd'], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=420)
    output = result.stdout + result.stderr
    (out / f'test_{name}.log').write_text(output, encoding='utf-8')
    ok = result.returncode == 0 and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:|^FAIL\b', output, re.M)
    stable = before == identities()
    row = dict(test=name, ok=ok and stable, exit=result.returncode, seconds=round(time.monotonic()-start, 3), sha256=hashlib.sha256(script.read_bytes()).hexdigest(), source_stable=stable, runtime_sha256=before)
    results.append(row)
    print(json.dumps({k:v for k,v in row.items() if k != 'runtime_sha256'}), flush=True)
(out / 'verification.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
raise SystemExit(0 if all(r['ok'] for r in results) else 1)
