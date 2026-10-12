import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(sys.argv[1])
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
godot = root / '.tools/Godot_v4.7.2-stable_linux.x86_64'
results = []
for test in sorted((root / 'app/tests').glob('test_*.gd')):
    if test.name <= 'test_atmosphere_flight.gd':
        continue  # these ran in the unmodified full script; keep their original failure log
    started = time.monotonic()
    try:
        proc = subprocess.run([str(godot), '--headless', '--path', str(root/'app'), '--audio-driver', 'Dummy', '--script', 'res://tests/'+test.name], capture_output=True, text=True, timeout=60)
        log = proc.stdout + proc.stderr
        failed = proc.returncode != 0 or any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for line in log.splitlines())
        code = proc.returncode
    except subprocess.TimeoutExpired as exc:
        log = str(exc)
        failed = True
        code = 124
    (output/(test.stem+'.log')).write_text(log)
    results.append(dict(test=test.name, exit=code, failed=failed, seconds=time.monotonic()-started))
    (output/'remaining-summary.json').write_text(json.dumps(results,indent=2)+'\n')
    print(('FAIL ' if failed else 'PASS ')+test.name,flush=True)

source = (root/'app/test.sh').read_text()
marker = 'echo "== H7: exact one-ulp math sensitivity and golden branch signatures"'
prefix = source[:source.index('# L6a imports')]
tail = prefix + '\nLOG="$(mktemp)"; trap \'rm -f "$LOG"\' EXIT\n' + source[source.index(marker):]
script = root/'app/landscape-regression-tail.sh'
script.write_text(tail)
proc = subprocess.run(['bash',str(script)],cwd=root,capture_output=True,text=True)
(output/'regression-tail.log').write_text(proc.stdout+proc.stderr)
results.append(dict(test='app/test.sh post-GDScript tail',exit=proc.returncode,failed=proc.returncode!=0))
(output/'remaining-summary.json').write_text(json.dumps(results,indent=2)+'\n')
print('Failures:',[x['test'] for x in results if x['failed']],flush=True)
sys.exit(1 if any(x['failed'] for x in results) else 0)
