"""Focused P-51 compatibility checks with complete per-process logs and failure exits."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', required=True, type=Path)
    p.add_argument('--app', required=True, type=Path)
    p.add_argument('--out', required=True, type=Path)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=False)
    imported = subprocess.run([str(a.godot.resolve()), '--headless', '--path', str(a.app.resolve()),
                               '--audio-driver', 'Dummy', '--import'], capture_output=True, text=True, timeout=180)
    import_log = imported.stdout + imported.stderr
    (a.out / 'import.log').write_text(import_log, encoding='utf-8', newline='\n')
    if imported.returncode or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', import_log, re.M):
        raise SystemExit('Resource import failed; see import.log')
    scripts = [
        'tests/test_aircraft_data.gd', 'tests/test_aircraft_contract.gd',
        'tests/test_aircraft_catalog.gd', 'tests/test_p51_handling.gd',
        'tests/test_p51_envelope.gd', 'tests/test_p51_ground.gd',
        'tests/test_runway_start.gd', 'tests/test_propulsion.gd',
        'aircraft/verify_model.gd', 'aircraft/verify_extra.gd',
        'aircraft/verify_p51.gd', 'aircraft/verify_p51_clearance.gd',
        'aircraft/verify_avanti.gd',
    ]
    results = []
    for script in scripts:
        command = [str(a.godot.resolve()), '--headless', '--path', str(a.app.resolve()),
                   '--audio-driver', 'Dummy', '--script', 'res://' + script]
        started = time.monotonic()
        done = subprocess.run(command, capture_output=True, text=True, timeout=180)
        log = done.stdout + done.stderr
        name = Path(script).stem
        (a.out / (name + '.log')).write_text(log, encoding='utf-8', newline='\n')
        results.append(dict(script=script, exit=done.returncode,
                            engine_errors=bool(re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M)),
                            assertion_failure=bool(re.search(r'^FAIL', log, re.M)),
                            seconds=round(time.monotonic()-started, 3)))
        (a.out / 'results.json').write_text(json.dumps(results, indent=2)+'\n')
        print(name, results[-1], flush=True)
    raise SystemExit(int(any(r['exit'] or r['engine_errors'] or r['assertion_failure'] for r in results)))


if __name__ == '__main__':
    main()
