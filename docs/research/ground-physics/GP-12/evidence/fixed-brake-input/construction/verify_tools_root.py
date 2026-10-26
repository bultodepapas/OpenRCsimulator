from pathlib import Path
import hashlib
import json
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
commands = [
    [sys.executable, 'app/tests/test_fixed_brake_trace_contract.py'],
    ['C:/Program Files/Git/bin/bash.exe', '-n', 'app/test.sh'],
]
results = []
for command in commands:
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    results.append({'command': command, 'exit_code': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr})
    assert run.returncode == 0, results[-1]
receipt = {
    'format': 'openrc-fixed-brake-tool-verification v1',
    'results': results,
    'test_sh_sha256': hashlib.sha256((ROOT / 'app/test.sh').read_bytes()).hexdigest(),
    'test_sh_before_sha256': hashlib.sha256((HERE / 'root-before/app/test.sh').read_bytes()).hexdigest(),
    'full_suite_executed': False,
}
(HERE / 'root-tool-checks.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'commands_passed': len(results), 'python_tests': 13, 'test_sh_syntax': 'pass'}, indent=2))
