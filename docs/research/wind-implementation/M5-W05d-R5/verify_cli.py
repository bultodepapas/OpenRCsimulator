"""Exercise benchmark CLI refusals through the existing checked engine runner."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent
sentinel = WORK/'existing-output.json'
sentinel.write_text('preserve this existing output\n')
cases = [
    ('compile', ['--full-session', '--verify-only', '--compile-only'], 0, 'benchmark script parsed'),
    ('typo', ['--verfy-only'], 1, 'unknown benchmark argument'),
    ('missing-mode', ['--verify-only'], 1, 'require --full-session'),
    ('bad-integer', ['--samples=not-an-integer'], 1, 'invalid benchmark integer argument'),
    ('short-workload', ['--full-session', '--verify-only', '--ticks-per-sample=1'], 1, 'at least 480 batch ticks'),
    ('unknown-case', ['--full-session', '--case=missing', '--output='+str(WORK/'unused-case.json')], 1, 'unknown --case ID'),
    ('unknown-aircraft', ['--full-session', '--aircraft=missing', '--output='+str(WORK/'unused-aircraft.json')], 1, 'unknown --aircraft ID'),
    ('existing-output', ['--full-session', '--verify-only', '--output='+str(sentinel)], 1, 'benchmark output already exists'),
]
summary=[]
for label, arguments, expected, message in cases:
    command=[sys.executable,str(ROOT/'tools/godot/run_checked.py'),'--timeout','90',
        '--out-dir',str(WORK/'cli-checks'),'--label',label,'--',str(ROOT/'.tools/Godot_v4.8-beta1_win64_console.exe'),
        '--headless','--path',str(WORK/'snapshot/app'),'--script','res://tests/bench_spatial_wind.gd','--',*arguments]
    result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    assert result.returncode==expected and message in result.stdout,(label,result.stdout)
    summary.append({'case':label,'expected_checked_exit':expected,'actual_checked_exit':result.returncode,'required_message':message,'passed':True})
assert sentinel.read_text()=='preserve this existing output\n'
(WORK/'cli-verification.json').write_text(json.dumps(summary,indent=2)+'\n')
print(f'{len(summary)} CLI contracts passed; existing output preserved')
