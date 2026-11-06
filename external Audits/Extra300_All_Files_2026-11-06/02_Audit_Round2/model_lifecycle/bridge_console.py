#!/usr/bin/env python3
"""Keep a disposable debug-bridge launch and its controller in one sandbox."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
aircraft = root / 'app/data/aircraft/gp_extra_300s_60.json'
install = root / 'app/data/glow/extra_61fx_2t.json'
original = {p: p.read_bytes() for p in (aircraft, install)}
env = os.environ.copy()
env.update({
    'OPENRC_GODOT': '/workspace/scratch/bc7264df490c/audit_round3/engine/Godot_v4.8-beta2_linux.x86_64',
    'OPENRC_DEBUG_BRIDGE': '47871',
    'XDG_CONFIG_HOME': str(root / 'xdg/config'),
    'XDG_CACHE_HOME': str(root / 'xdg/cache'),
})
transcript = root / 'bridge_transcript.jsonl'

def emit(value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    print(encoded, flush=True)
    with transcript.open('a') as f:
        f.write(encoded + '\n')

def command(args):
    try:
        result = subprocess.run([sys.executable, 'tools/debug/debugctl.py', *args], cwd=root,
                                env=env, capture_output=True, text=True, timeout=58)
        emit({'command': args, 'exit': result.returncode, 'stdout': result.stdout,
              'stderr': result.stderr})
    except Exception as exc:
        emit({'command': args, 'exception': str(exc)})

emit({'ready': True, 'aircraft_sha256': hashlib.sha256(original[aircraft]).hexdigest(),
      'installation_sha256': hashlib.sha256(original[install]).hexdigest()})
try:
    for line in sys.stdin:
        try:
            req = json.loads(line)
            if 'command' in req:
                command(req['command'])
            elif 'diameter' in req:
                diameter = float(req['diameter'])
                raw_aircraft = json.loads(original[aircraft])
                raw_install = json.loads(original[install])
                raw_aircraft['propulsion']['propeller']['diameter']['value'] = diameter
                raw_install['propeller']['diameter_m']['value'] = diameter
                aircraft.write_text(json.dumps(raw_aircraft, indent=2) + '\n')
                install.write_text(json.dumps(raw_install, indent=2) + '\n')
                emit({'diameter': diameter, 'aircraft_sha256': hashlib.sha256(aircraft.read_bytes()).hexdigest(),
                      'installation_sha256': hashlib.sha256(install.read_bytes()).hexdigest()})
            elif 'aircraft_diameter' in req:
                diameter = float(req['aircraft_diameter'])
                raw_aircraft = json.loads(original[aircraft])
                raw_aircraft['propulsion']['propeller']['diameter']['value'] = diameter
                aircraft.write_text(json.dumps(raw_aircraft, indent=2) + '\n')
                install.write_bytes(original[install])
                emit({'aircraft_diameter': diameter, 'aircraft_sha256': hashlib.sha256(aircraft.read_bytes()).hexdigest(),
                      'installation_sha256': hashlib.sha256(install.read_bytes()).hexdigest()})
            elif req.get('restore'):
                for p in original: p.write_bytes(original[p])
                emit({'restored': True})
            elif req.get('quit'):
                break
            else:
                emit({'error': 'unknown request'})
        except Exception as exc:
            emit({'error': str(exc)})
finally:
    for p in original: p.write_bytes(original[p])
    command(['stop', '--force'])
