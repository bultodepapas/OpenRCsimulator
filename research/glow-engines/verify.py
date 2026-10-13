"""Reproduce focused glow proof, disposable faults and bounded coupled bench cases."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
ENGINE_VERSION='4.7.2.stable.official.ed1daf0bf'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True,type=Path)
    parser.add_argument('--out',required=True,type=Path)
    args=parser.parse_args(); out=args.out.resolve(); out.mkdir(parents=True,exist_ok=False)
    godot=args.godot.resolve()
    version=subprocess.check_output([str(godot),'--version'],text=True).strip()
    if version!=ENGINE_VERSION:raise SystemExit('Unexpected Godot: '+version)
    results=[]

    def run(label,command,expected=0):
        result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=120)
        text=result.stdout+result.stderr
        (out/(label+'.log')).write_text(text,encoding='utf-8')
        error=bool(re.search(r'^(?:SCRIPT |SHADER )?ERROR:',text,re.M))
        passed=result.returncode==expected and (not error or expected!=0)
        results.append(dict(check=label,exit_code=result.returncode,expected=expected,passed=passed))
        print(label+': '+('PASS' if passed else 'FAIL'),flush=True)
        if not passed:raise RuntimeError(label+' failed: '+text[-1500:])
        return text

    run('generator',[sys.executable,'research/glow-engines/build_profiles.py','--check'])
    run('profile-python',[sys.executable,'research/glow-engines/test_profiles.py'])
    run('reference-python',[sys.executable,'research/glow-engines/reference/test_reference.py'])
    run('oracle-current',[sys.executable,'research/glow-engines/reference/reference.py','--check'])
    run('math-boundary',[sys.executable,'app/tests/check_transcendentals.py'])
    kernels=sorted((ROOT/'app/physics/glow').glob('*.gd'))
    tests=sorted((ROOT/'app/tests').glob('test_glow_*.gd'))
    for p in kernels+tests:
        run('parse-'+p.stem,[str(godot),'--headless','--path',str(ROOT/'app'),'--audio-driver','Dummy',
                            '--check-only','--script','res://'+p.relative_to(ROOT/'app').as_posix()])
    count=0
    for p in tests:
        text=run(p.stem,[str(godot),'--headless','--path',str(ROOT/'app'),'--audio-driver','Dummy','--script','res://tests/'+p.name])
        matches=re.findall(r'(\d+) checks, (\d+) failed',text)
        if len(matches)!=1 or int(matches[0][1])!=0:raise RuntimeError('Missing unambiguous test summary: '+p.name)
        count+=int(matches[0][0])
    run('mutations',[sys.executable,'research/glow-engines/mutations.py','--godot',str(godot),'--out',str(out/'mutations')])
    benches=[]
    for family,profile,diameter in [('2t','os_max_55ax_candidate',.3302),('4t','os_fs_64v_candidate',.3556)]:
        for hz in [240,480,960]:
            target=out/(family+'-'+str(hz)+'.json')
            run(f'bench-{family}-{hz}',[str(godot),'--headless','--path',str(ROOT/'app'),'--audio-driver','Dummy',
                '--script',str(ROOT/'research/glow-engines/bench.gd'),'--',
                '--profile=res://data/glow/'+profile+'.json','--prop-diameter-m='+str(diameter),
                '--hz='+str(hz),'--ticks='+str(int(hz*2.5)),'--out='+str(target)])
            data=json.loads(target.read_text(encoding='utf-8'))
            if not data['ok'] or data['simulation']['ticks_completed']!=int(hz*2.5) or data['profile_identity'].get('status')!='candidate':
                raise RuntimeError('Bench completion or candidate provenance missing')
            if data['metrics']['propeller_absorbed_work_j'] + .01 < data['metrics']['thrust_work_j']:
                raise RuntimeError('Propeller delivers more work than the shaft supplies')
            benches.append(dict(family=family,hz=hz,file=target.name,metrics=data['metrics']))
    target=out/'unsupported-stop.json'
    run('unsupported-stop',[str(godot),'--headless','--path',str(ROOT/'app'),'--audio-driver','Dummy',
        '--script',str(ROOT/'research/glow-engines/bench.gd'),'--',
        '--profile=res://data/glow/os_fs_64v_candidate.json','--prop-diameter-m=0.381','--carrier-mass-kg=3',
        '--ticks=600','--out='+str(target)],expected=2)
    stop=json.loads(target.read_text(encoding='utf-8'))
    if stop['ok'] or stop['simulation']['ticks_completed']>=600 or stop['metrics']['final_rpm']<0:
        raise RuntimeError('Unsupported rest crossing must refuse and retain nonnegative accepted RPM')
    sources=kernels+tests+list((ROOT/'app/data/glow').glob('*.json'))+list((ROOT/'research/glow-engines').glob('*.py'))+list((ROOT/'research/glow-engines/reference').glob('*.py'))+[ROOT/'research/glow-engines/reference/oracle.json',ROOT/'research/glow-engines/bench.gd']
    sources += [ROOT/'app'/p for p in ['sim/simulation.gd','physics/propulsion.gd','physics/rotor_coupling.gd','physics/rigid_body.gd','physics/math3d.gd']]
    manifest={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(sources))}
    report=dict(format='openrc-glow-foundation-proof v1',godot=version,gdscript_checks=count,python_checks=15,
                results=results,benches=benches,source_sha256=manifest,
                claim='Software proof of standalone candidate mean-cycle kernels; physical and catalog acceptance remain open')
    (out/'verification.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(f'PASS: {count} GDScript checks, 15 Python checks; six paired refinement benches and stop refusal',flush=True)


if __name__=='__main__': main()
