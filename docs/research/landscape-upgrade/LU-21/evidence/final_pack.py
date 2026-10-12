"""Export the installed app, inspect packed assets, and run a short packed flight."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
evidence = root/'docs/research/landscape-upgrade/LU-21/evidence'
engine = root/'.tools/Godot_v4.7.2-stable_win64_console.exe'
pack = out/'population-review.pck'
empty = out/'pack-empty'
empty.mkdir(exist_ok=True)
credits = hashlib.sha256((root/'app/assets/landscape/UPGRADE_CREDITS.md').read_bytes()).hexdigest()
commands = []

def run(label, args):
    cmd = [str(engine), *map(str,args)]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    log = p.stdout+p.stderr
    (evidence/(label+'.log')).write_text(log)
    commands.append(dict(label=label, command=cmd, exit=p.returncode))
    if p.returncode or any(x.startswith(('ERROR:', 'SCRIPT ERROR:', 'SHADER ERROR:')) for x in log.splitlines()):
        raise RuntimeError(label+' failed: '+log[-3000:])
    print(label, 'passed', flush=True)

run('export-pack',['--headless','--path',root/'app','--export-pack','Windows',pack])
run('pack-check',['--headless','--path',empty,'--script',root/'tools/scenery/population/check_pack.gd','--',pack,credits])
run('pack-flight',['--headless','--path',empty,'--main-pack',pack,'--','--trace='+str(out/'pack-flight.csv'),'--t=0.25'])
p = subprocess.run(['python',str(root/'app/tests/check_trimmed_flight.py'),str(out/'pack-flight.csv'),'--duration','0.25'],capture_output=True,text=True,timeout=30)
assert p.returncode == 0, p.stdout+p.stderr
(evidence/'pack-flight-check.log').write_text(p.stdout+p.stderr)
(evidence/'pack-flight.csv').write_bytes((out/'pack-flight.csv').read_bytes())
(evidence/'pack-check.json').write_text(json.dumps(dict(pack_bytes=pack.stat().st_size,pack_sha256=hashlib.sha256(pack.read_bytes()).hexdigest(),credits_sha256=credits,models_loaded=6,finite_trimmed_ticks=60,note='Manual Windows resource pack, not a release installer; loaded from an empty project.',commands=commands),indent=2)+'\n')
