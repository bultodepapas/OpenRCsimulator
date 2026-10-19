import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
AUDIT = Path(__file__).resolve().parent
ENGINE = ROOT / '.tools/Godot_v4.7.2-stable_win64.exe'
ERROR = re.compile(r'(?m)^(?:SCRIPT |SHADER )?ERROR:')
records = []

def run(name, project, script, arguments=(), native=False, timeout=180):
    command = [str(ENGINE), '--path', str(project), '--audio-driver', 'Dummy']
    if native:
        command += ['--windowed', '--resolution', '1280x720', '--max-fps', '60']
    else:
        command += ['--headless']
    command += ['--script', str(script)]
    if arguments:
        command += ['--', *arguments]
    begin = time.time()
    with (AUDIT / (name+'.log')).open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                timeout=timeout, creationflags=0 if native else subprocess.CREATE_NO_WINDOW)
    text = (AUDIT / (name+'.log')).read_text(encoding='utf-8', errors='replace')
    record = {'name': name, 'command': command, 'exit': result.returncode,
              'wall_s': time.time()-begin, 'engine_errors': bool(ERROR.search(text))}
    records.append(record)
    (AUDIT/'verification.json').write_text(json.dumps(records, indent=2))
    print(name, record['exit'], 'errors='+str(record['engine_errors']), '|', ' / '.join(text.splitlines()[-2:]), flush=True)
    if result.returncode or record['engine_errors']:
        raise RuntimeError('Verification failed: '+name)

if __name__ == '__main__':
    # These checks use current production files; no tests run alongside a native flight.
    for name in ['test_atmosphere', 'test_cloud_transport', 'test_sky_appearance_config',
                 'test_sky_checkpoint', 'test_storm_bank', 'test_storm_cell',
                 'test_storm_events', 'test_sky_render', 'test_world_sky', 'test_sky_routes']:
        run(name, ROOT/'app', 'res://tests/'+name+'.gd', timeout=90)
    run('cloud-raw-timing', AUDIT/'cloud-candidate/project',
        'res://tests/benchmark_atmosphere_cloud_candidate.gd',
        ['--cloud-candidate-iterations=12000','--cloud-candidate-warmup=500'])
    output = AUDIT/'native-candidate-2.json'
    if output.exists():
        raise RuntimeError('Refusing to overwrite '+str(output))
    run('native-candidate-2', AUDIT/'source/app', AUDIT/'native_flight.gd',
        ['--output='+str(output), '--resume-focus-loss'], native=True, timeout=180)
    data=json.loads(output.read_text())
    assert data['complete']
    print('NATIVE candidate:',[(c['scenario'],c['complete'],c['focus_uninterrupted'],c['numeric_sha256']) for c in data['cases']],flush=True)
