"""Verify a fresh source snapshot, Windows export, and packaged RC startup.

This checks the current working tree, including authorized uncommitted RC work.
It is not a claim that a clean Git checkout or other desktop platforms passed.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--isolated-rc', action='store_true', help='Export an RC-only verification entry point; does not qualify the shared application release')
    parser.add_argument('--require-native', action='store_true', help='Fail if the exported RC activity silently falls back to GDScript')
    parser.add_argument('--reference-backend', action='store_true', help='Exclude generated native artifacts to verify the exported GDScript fallback')
    args = parser.parse_args()
    if args.require_native and args.reference_backend:
        parser.error('--require-native and --reference-backend are mutually exclusive')
    destination = args.out.resolve()
    for input_root in [ROOT / 'app', ROOT / 'assets/aircraft']:
        if destination == input_root or input_root in destination.parents:
            parser.error('--out must be outside the source directories copied by this verifier')
    if destination.exists():
        parser.error('--out must be a new directory; evidence is never overwritten')
    destination.mkdir(parents=True)
    source = ROOT / 'app'
    snapshot = destination / 'app'
    def ignore_generated(folder, names):
        ignored = {'.godot'} & set(names)
        if args.reference_backend and Path(folder).resolve() == (source / 'native').resolve():
            ignored.add('ground_vehicle')
        return ignored
    shutil.copytree(source, snapshot, ignore=ignore_generated)
    # The existing aircraft export plugin verifies authoring proofs outside res://.
    # Keep those build inputs beside app; they are not RC runtime dependencies.
    shutil.copytree(ROOT / 'assets/aircraft', destination / 'assets/aircraft')
    # Official 4.7 templates disable path overrides, including --script. A compiled
    # verification entry point is required to measure the actual release runtime.
    shutil.copyfile(ROOT / 'research/rc-monster-truck/bench_runtime.gd', snapshot / 'rcv_package_bench.gd')
    base = 'Node' if args.isolated_rc else '"res://app_root.gd"'
    normal_start = '''\tvar activity = load("res://vehicles/ground/ground_scene.gd").new()
\tadd_child(activity)
\tif not activity.startup_error.is_empty():
\t\tpush_error(activity.startup_error)
\t\tget_tree().quit(1)
\tactivity.home_requested.connect(func(): get_tree().quit())''' if args.isolated_rc else '\tsuper._ready()'
    wrapper = f'''extends {base}
const Cost = preload("res://rcv_package_bench.gd")
func _ready() -> void:
\tif OS.get_cmdline_user_args().has("--rcv-package-cost"):
\t\tvar report := Cost.measure()
\t\tprint(JSON.stringify(report, "\\t", true, true))
\t\tget_tree().quit(1 if report.has("error") else 0)
\t\treturn
{normal_start}
'''
    (snapshot / 'rcv_package_entry.gd').write_text(wrapper, encoding='utf-8')
    (snapshot / 'rcv_package_entry.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://rcv_package_entry.gd" id="1"]\n[node name="RCVerification" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
    project_path = snapshot / 'project.godot'
    project = project_path.read_text(encoding='utf-8').replace('run/main_scene="res://app_root.tscn"', 'run/main_scene="res://rcv_package_entry.tscn"')
    if args.isolated_rc:
        project = re.sub(r'^enabled=PackedStringArray\([^\n]*\)$', 'enabled=PackedStringArray()', project, flags=re.M)
    project_path.write_text(project, encoding='utf-8')
    identities = {path.relative_to(snapshot).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted(snapshot.rglob('*')) if path.is_file()}
    for path in sorted((destination / 'assets/aircraft').rglob('*')):
        if path.is_file():
            identities['../' + path.relative_to(destination).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    (destination / 'source-sha256.json').write_text(json.dumps(identities, indent=2) + '\n', encoding='utf-8')
    engine = str(args.godot.resolve())
    executable = destination / 'OpenRC-RC-verification.exe'
    commands = [
        ('fresh-import', [engine, '--headless', '--path', str(snapshot), '--audio-driver', 'Dummy', '--import']),
        ('windows-export', [engine, '--headless', '--path', str(snapshot), '--audio-driver', 'Dummy',
                            '--export-release', 'Windows', str(executable)]),
        ('packaged-rc-start', [str(executable), '--headless', '--audio-driver', 'Dummy', '--quit-after', '8',
                               '--', '--vehicle=mt8-bisonte']),
        ('packaged-rc-cost', [str(executable), '--headless', '--audio-driver', 'Dummy',
                              '--', '--rcv-package-cost']),
    ]
    started = datetime.now(timezone.utc)
    report = {'format': 'openrc-rcv-package-verification', 'date': started.date().isoformat(),
              'started_utc': started.isoformat(),
              'source': 'fresh copy of current app working tree; no import cache',
              'platform': 'Windows x86_64', 'checks': [], 'physical_validation': False}
    report['isolated_rc'] = args.isolated_rc
    report['require_native'] = args.require_native
    report['reference_backend'] = args.reference_backend
    report['application_release_scope'] = not args.isolated_rc
    # This bounded Windows startup/cost check is not the full application release suite.
    report['application_release_qualification'] = False
    for name, command in commands:
        engine_log = destination / f'{name}.engine.log'
        command[1:1] = ['--log-file', str(engine_log)]
        print('Running ' + name, flush=True)
        start = time.perf_counter()
        try:
            result = subprocess.run(command, cwd=destination, capture_output=True, text=True,
                                    encoding='utf-8', errors='replace', timeout=360,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            output, code = result.stdout + result.stderr, result.returncode
            if engine_log.exists():
                output += '\n' + engine_log.read_text(encoding='utf-8', errors='replace')
        except subprocess.TimeoutExpired as exc:
            output = (exc.stdout or b'').decode('utf-8', errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or '')
            output += '\nTIMEOUT after 360 seconds\n'
            code = -1
        (destination / f'{name}.log').write_text(output, encoding='utf-8')
        ok = code == 0 and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:', output, re.M)
        if name == 'packaged-rc-cost' and ok:
            try:
                cost, _ = json.JSONDecoder().raw_decode(output[output.index('{'):])
                ok = cost.get('format') == 'openrc-rcv-cost' and cost.get('debug_build') is False
                if args.require_native:
                    ok = ok and cost.get('backend_identity', {}).get('backend') == 'native'
                if args.reference_backend:
                    ok = ok and cost.get('backend_identity', {}).get('backend') == 'gdscript_reference'
                report['cost'] = cost
                report['plan_cost_qualified'] = all(item['plan_500us_mean_gate'] for item in cost['results'])
                report['realtime_cost_qualified'] = all(item['realtime_mean_gate'] and item['realtime_p95_gate'] for item in cost['results'])
            except (ValueError, KeyError, TypeError):
                ok = False
        report['checks'].append({'name': name, 'ok': ok, 'exit_code': code,
                                 'elapsed_s': round(time.perf_counter() - start, 3), 'command': command})
        report['ok'] = all(check['ok'] for check in report['checks'])
        (destination / 'package-verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(f'{name}: {"PASS" if ok else "FAIL"}', flush=True)
        if not ok:
            return 1
    report['executable_sha256'] = hashlib.sha256(executable.read_bytes()).hexdigest()
    report['executable_bytes'] = executable.stat().st_size
    (destination / 'package-verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
