from pathlib import Path
import json
import re
import subprocess
import time

AUDIT = Path(__file__).resolve().parent
ROOT = AUDIT.parents[1]
output = AUDIT / 'loading-storm-forced-candidate.json'
assert not output.exists(), 'Refuse to overwrite a result'
command = [str(ROOT / '.tools/Godot_v4.7.2-stable_win64.exe'),
           '--path', str(AUDIT / 'source/app'), '--audio-driver', 'Dummy',
           '--windowed', '--resolution', '1280x720', '--max-fps', '60',
           '--script', str(AUDIT / 'loading_storm_forced.gd'), '--',
           '--output=' + str(output), '--cycles=3']
begin = time.monotonic()
timed_out = False
with (AUDIT / 'loading-storm-forced-candidate.log').open('w', encoding='utf-8') as log:
    process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    try:
        process.wait(timeout=120)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        process.wait()
text = (AUDIT / 'loading-storm-forced-candidate.log').read_text(encoding='utf-8', errors='replace')
record = {'command': command, 'exit': process.returncode, 'timed_out': timed_out,
          'wall_s': time.monotonic() - begin,
          'engine_errors': bool(re.search(r'(?m)^(?:SCRIPT |SHADER )?ERROR:', text))}
(AUDIT / 'loading-storm-forced-verification.json').write_text(json.dumps(record, indent=2))
print(json.dumps(record), flush=True)
assert not timed_out and process.returncode == 0 and not record['engine_errors']
assert json.loads(output.read_text())['complete']
