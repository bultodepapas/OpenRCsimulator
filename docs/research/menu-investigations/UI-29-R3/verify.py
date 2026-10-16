from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json, subprocess, sys

root = Path(__file__).resolve().parents[2]
output = root / 'tmp/menu-final-review/logs'
output.mkdir(exist_ok=True)
tests = sys.argv[1:] or ['test_home_presentation', 'test_field_integration', 'test_ui_home_preview_cache',
         'test_ui_preview_requests', 'test_ui_preview_resources', 'test_ui_screen_stack',
         'test_ui_settings_integration', 'test_ui_language', 'test_ui_weather',
         'test_ui_natural_random', 'test_ui_runway', 'test_workshop_ui', 'test_workshop_trial',
         'test_ui_input', 'test_ui_controller_navigation']
def run(name):
    cmd = [str(root / '.tools/Godot_v4.7.2-stable_win64_console.exe'), '--headless', '--path',
           str(root / 'app'), '--audio-driver', 'Dummy', '--script', f'res://tests/{name}.gd']
    if not (root / f'app/tests/{name}.gd').exists():
        return {'test': name, 'skip': 'file absent'}
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=240)
        log = result.stdout + result.stderr
        (output / f'{name}.log').write_text(log, encoding='utf-8')
        errors = [line for line in log.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:', 'FAIL'))]
        row = {'test': name, 'exit': result.returncode, 'errors': errors, 'checks': sum(line.startswith('ok ') for line in log.splitlines())}
    except subprocess.TimeoutExpired:
        row = {'test': name, 'exit': 'timeout'}
    print(json.dumps(row), flush=True)
    return row
with ThreadPoolExecutor(max_workers=3) as pool:
    results = list(pool.map(run, tests))
(output / 'tests.json').write_text(json.dumps(results, indent=2), encoding='utf-8')

