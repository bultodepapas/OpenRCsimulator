"""Run focused RC runtime checks with bounded processes and retained evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--include-menu', action='store_true')
    args = parser.parse_args()
    if args.out.exists():
        parser.error('--out must be a new directory; evidence is never overwritten')
    args.out.mkdir(parents=True)
    binary = args.godot.resolve()
    checks = [
        ('visual-source', [sys.executable, 'research/rc-monster-truck/build_visual.py', '--check']),
        ('vehicle-source', [sys.executable, 'research/rc-monster-truck/build_vehicle_data.py', '--check']),
        ('generator-mutations', [sys.executable, 'research/rc-monster-truck/test_vehicle_data_generator.py']),
        ('float64-guard', [sys.executable, 'app/tests/check_transcendentals.py']),
    ]
    scripts = ['test_rcv_vehicle_data', 'test_rcv_course', 'test_rcv_airfield_course',
               'test_rcv_airfield_track', 'test_rcv_obstacle_contacts', 'test_rcv_input',
               'test_rcv_vehicle_dynamics', 'test_rcv_session', 'test_rcv_activity',
               'test_rcv_presentation', 'test_rcv_menu']
    if args.include_menu:
        scripts += ['test_ui_home', 'test_ui_home_layout']
    for name in scripts:
        checks.append((name, [str(binary), '--headless', '--path', 'app', '--audio-driver', 'Dummy',
                             '--script', f'res://tests/{name}.gd']))
    started = datetime.now(timezone.utc)
    report = {'format': 'openrc-rcv-runtime-verification', 'date': started.date().isoformat(),
              'started_utc': started.isoformat(),
              'godot': str(binary), 'godot_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'checks': [], 'physical_validation': False}
    def source_identity():
        source_paths = [ROOT / 'app/app_root.gd', ROOT / 'app/ui/home.gd',
                        ROOT / 'app/input/ground_vehicle_input.gd']
        for folder in ['app/physics/ground_vehicle', 'app/sim/ground_vehicle',
                       'app/vehicles/ground', 'app/data/vehicles/ground', 'app/data/ground_vehicle',
                       'app/native/ground_vehicle']:
            source_paths.extend(path for path in (ROOT / folder).rglob('*')
                                if path.is_file() and path.suffix not in ['.uid', '.import'])
        return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(source_paths)}
    report['source_sha256'] = source_identity()
    for name, command in checks:
        start = time.perf_counter()
        print(f'Running {name}', flush=True)
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                    encoding='utf-8', errors='replace', timeout=300,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            output = result.stdout + result.stderr
            code = result.returncode
        except subprocess.TimeoutExpired as exc:
            output = f'TIMEOUT after 300 seconds: {exc}'
            code = -1
        ok = code == 0 and re.search(r'^(?:SCRIPT |SHADER )?ERROR:|^FAIL(?:\s|:)', output, re.M) is None
        (args.out / f'{name}.log').write_text(output, encoding='utf-8')
        report['checks'].append({'name': name, 'ok': ok, 'exit_code': code,
                                 'elapsed_s': round(time.perf_counter() - start, 3), 'command': command})
        report['ok'] = all(item['ok'] for item in report['checks'])
        (args.out / 'verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(f'{name}: {"PASS" if ok else "FAIL"} ({code})', flush=True)
    report['sources_unchanged_during_verification'] = source_identity() == report['source_sha256']
    report['ok'] = report['ok'] and report['sources_unchanged_during_verification']
    (args.out / 'verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
