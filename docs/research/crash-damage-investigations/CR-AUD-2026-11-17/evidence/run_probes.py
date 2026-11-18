#!/usr/bin/env python3
"""Re-run retained audit fixtures through OpenRC's checked Godot runner.

Several fixtures intentionally exit nonzero on the audited baseline because they
assert desired behavior that the baseline violates. Preserve those raw outcomes.
This launcher does not turn a known failure into a pass.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[5]
ENGINE_SHA512 = '428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9'
PROBES = {
    'prop-source-off': ('test_spinning_source_off_prop_strike.gd', 'PROBE spinning source-off ground strike:'),
    'staggered-crossing': ('test_staggered_hull_crossing_event.gd', 'PROBE staggered hull crossing:'),
    'wreck-adversarial': ('crash_adversarial_probe.gd', 'PROBE RESULT'),
    'lake-session': ('lake_session_probe.gd', 'LAKE_SESSION_PROBE:'),
    'heli-soft-contact': ('heli_soft_contact_probe.gd', 'HELI_SOFT_CONTACT_PROBE:'),
    'scenario-fuel': ('scenario_and_fuel_probe.gd', 'SCENARIO_FUEL_PROBE:'),
    'ground-scenery': ('ground_scenery_probe.gd', 'GROUND_SCENERY_PROBE:'),
    'engine-com': ('engine_com_probe.gd', 'ENGINE_COM_PROBE:'),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('names', nargs='*', help='Probe names; defaults to all probes, sequentially.')
    parser.add_argument('--list', action='store_true', help='Print probe names without launching the engine.')
    parser.add_argument('--engine', type=Path, default=ROOT / '.tools/Godot_v4.8-beta2_linux.x86_64')
    parser.add_argument('--timeout', type=float, default=120.0)
    parser.add_argument('--out', type=Path, default=ROOT / 'tmp/collision-audit/reproductions' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    args = parser.parse_args()
    if args.list:
        print('\n'.join(PROBES))
        return 0
    names = args.names or list(PROBES)
    unknown = sorted(set(names) - set(PROBES))
    if unknown:
        parser.error('Unknown probes: ' + ', '.join(unknown))
    if not args.engine.is_file():
        parser.error('Pinned engine not found. Run bash app/get-godot.sh, or supply its verified binary with --engine.')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    digest = hashlib.sha512()
    with args.engine.open('rb') as binary:
        for chunk in iter(lambda: binary.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != ENGINE_SHA512:
        parser.error('Engine SHA-512 differs from the audited Linux x86_64 binary. Use the pinned downloader.')
    failed = False
    for name in names:
        filename, marker = PROBES[name]
        command = [
            sys.executable, str(ROOT / 'tools/godot/run_checked.py'),
            '--timeout', str(args.timeout), '--out-dir', str(args.out / name),
            '--label', name, '--require-text', marker, '--',
            str(args.engine.resolve()), '--headless', '--path', str(ROOT / 'app'),
            '--audio-driver', 'Dummy', '--script', str(Path(__file__).parent / 'probes' / filename),
        ]
        environment = os.environ.copy()
        for variable, directory in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
            environment[variable] = str((args.out / name / 'profile' / directory).resolve())
        result = subprocess.run(command, cwd=ROOT, env=environment, check=False)
        failed = failed or result.returncode != 0
        print(f'{name}: checked runner exit {result.returncode}', flush=True)
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
