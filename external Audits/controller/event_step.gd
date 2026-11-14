from pathlib import Path
import os
import subprocess
import sys
import time

base = Path('/workspace/scratch/a1128d42a6f8/evidence/profiles')
repo = Path('/workspace/scratch/a1128d42a6f8/openrc-audit')
sync = base / ('race-' + str(time.time_ns()))
sync.mkdir()
engine = '/workspace/scratch/912e78c5574d/repo_current/.tools/Godot_v4.8-beta2_linux.x86_64'
runner = str(repo / 'tools/godot/run_checked.py')
project = str(base / 'repro')
store = str(sync / 'profiles.cfg')
env = os.environ.copy()
env.update({'AUDIT_SYNC': str(sync), 'AUDIT_STORE': store, 'XDG_DATA_HOME': str(base/'userdata'), 'XDG_CONFIG_HOME': str(base/'config')})
def cmd(label, script, marker):
    return [sys.executable, runner, '--label', label, '--out-dir', str(base/'checks'), '--timeout', '30', '--require-text', marker, '--', engine, '--headless', '--path', project, '--audio-driver', 'Dummy', '--script', 'res://' + script]
procs = []
try:
    for name in ['A', 'B']:
        e = env.copy()
        e['AUDIT_WRITER'] = name
        procs.append(subprocess.Popen(cmd('race-writer-'+name, 'concurrent_writer.gd', 'WRITER_DONE name='+name+' ok=true'), cwd=repo, env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
    limit = time.monotonic() + 20
    while not all((sync / (name + '.ready')).exists() for name in ['A','B']):
        if time.monotonic() > limit or any(p.poll() is not None for p in procs):
            raise RuntimeError('writer did not reach read barrier')
        time.sleep(.01)
    for index, name in enumerate(['A','B']):
        (sync / (name + '.release')).write_text('release')
        output, _ = procs[index].communicate(timeout=20)
        print(output, end='')
        if procs[index].returncode: raise RuntimeError(name + ' writer failed')
    result = subprocess.run(cmd('race-final-store', 'inspect_store.gd', 'FINAL_STORE names=["Writer B"] ok=true'), cwd=repo, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout, end='')
    if result.returncode: raise RuntimeError('final store was not exactly B')
    print('RACE_PROBE_COMPLETE sync=' + str(sync))
finally:
    for p in procs:
        if p.poll() is None:
            p.kill()
            p.wait()
