from pathlib import Path
import hashlib
import json
import subprocess
import sys
import time

source = Path(__file__).resolve().parents[2]
target = Path(sys.argv[1]).resolve()
out = source / '.tools/landscape-upgrade/final-regression'
out.mkdir(exist_ok=True)
assert target != source and str(target).startswith('/var/tmp/openrc-lu-validation-')
for command in [['fetch', '--quiet', '--depth=1', str(source), 'HEAD'],
                ['update-ref', 'HEAD', 'FETCH_HEAD'], ['read-tree', 'HEAD']]:
    subprocess.run(['git', '-C', str(target), *command], check=True)
names = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=source).decode().split('\0')
manifest, changes = {}, {}
for name in sorted(set(names)):
    if not name.startswith('app/') or not (source/name).is_file():
        continue
    original = (source/name).read_bytes()
    normalized = original.replace(b'\r\n', b'\n') if (source/name).suffix in {'.gd','.gdshader','.gdshaderinc','.json','.py','.md','.godot','.tscn','.tres','.csv','.txt','.po','.cfg','.sh','.svg','.html','.js'} else original
    manifest[name] = hashlib.sha256(original).hexdigest()
    dest = target/name
    if not dest.exists() or dest.read_bytes() != normalized:
        changes[name] = {'before_normalized': hashlib.sha256(dest.read_bytes()).hexdigest() if dest.exists() else None,
                         'after_original': manifest[name], 'after_normalized': hashlib.sha256(normalized).hexdigest()}
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(normalized)
(out/'final-source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
(out/'final-source-delta.json').write_text(json.dumps(changes,indent=2)+'\n')
print('Synced:',list(changes),flush=True)
godot = str(target/'.tools/Godot_v4.7.2-stable_linux.x86_64')
tests = ['test_field_integration','test_field_projected_shadows','test_field_surfaces','test_replay_policy',
         'test_scenery_trace','test_world_sky','test_landscape_scenery_eligibility','test_landscape_population',
         'test_scenery_build','test_landscape_collision_setup','test_landscape_runtime','test_landscape_checkpoint',
         'test_world_flow','test_world_field_lights','test_visual_checkpoint','test_time_of_day_checkpoint']
results = []
for name in tests:
    started = time.monotonic()
    proc = subprocess.run([godot,'--headless','--path',str(target/'app'),'--audio-driver','Dummy','--script',f'res://tests/{name}.gd'], capture_output=True,text=True,timeout=60)
    log = proc.stdout+proc.stderr
    (out/f'{name}.log').write_text(log)
    failed = proc.returncode != 0 or any(line.startswith(('ERROR:','SCRIPT ERROR:','SHADER ERROR:')) for line in log.splitlines())
    results.append(dict(test=name+'.gd',exit=proc.returncode,failed=failed,seconds=time.monotonic()-started))
    (out/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
    print(('FAIL ' if failed else 'PASS ')+name,flush=True)
script_source = (target/'app/test.sh').read_text()
marker = 'echo "== E5a: generated Extra taildragger contacts, P-51 review and session refinement"'
script = target/'app/landscape-regression-final-tail.sh'
script.write_text(script_source[:script_source.index('# L6a imports')]+script_source[script_source.index(marker):])
proc = subprocess.run(['bash',str(script)],cwd=target,capture_output=True,text=True)
(out/'regression-final-tail.log').write_text(proc.stdout+proc.stderr)
results.append(dict(test='app/test.sh E5a/E5b tail',exit=proc.returncode,failed=proc.returncode!=0))
(out/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
print('Final failures:',[x['test'] for x in results if x['failed']],flush=True)
sys.exit(1 if any(x['failed'] for x in results) else 0)
