from pathlib import Path
import hashlib
import json
import re
import subprocess
import time
import psutil

ROOT=Path(__file__).resolve().parents[2]
A=Path(__file__).resolve().parent
ENGINE=ROOT/'.tools/Godot_v4.7.2-stable_win64.exe'
PROJECT=A/'source/app'
ERROR=re.compile(r'(?m)^(?:SCRIPT |SHADER )?ERROR:')
records=[]

def run(name, project, script, arguments=(), native=False, expected_failure=False):
    command=[str(ENGINE),'--path',str(project),'--audio-driver','Dummy']
    command+=['--windowed','--resolution','1280x720','--max-fps','60'] if native else ['--headless']
    command+=['--script',str(script)]
    if arguments: command+=['--',*arguments]
    samples=[]
    begin=time.monotonic()
    with (A/(name+'.log')).open('w',encoding='utf-8') as f:
        p=subprocess.Popen(command,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,
                           creationflags=0 if native else subprocess.CREATE_NO_WINDOW)
        proc=psutil.Process(p.pid)
        while p.poll() is None:
            if time.monotonic()-begin>180:
                p.kill();p.wait();raise RuntimeError(name+' timed out')
            if native:
                try:
                    mem=proc.memory_info();cpu=proc.cpu_times()
                    others=[]
                    for other in psutil.process_iter(['pid','name','cpu_times','cmdline']):
                        if other.pid!=p.pid and 'godot' in (other.info['name'] or '').lower():
                            ct=other.info['cpu_times']
                            others.append({'pid':other.pid,'cpu_s':ct.user+ct.system if ct else None,
                                           'headless':'--headless' in (other.info['cmdline'] or [])})
                    gpu=subprocess.run(['nvidia-smi','--query-gpu=utilization.gpu,utilization.memory,memory.used,power.draw,temperature.gpu',
                                        '--format=csv,noheader,nounits'],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW,timeout=5)
                    samples.append({'elapsed_s':time.monotonic()-begin,'cpu_s':cpu.user+cpu.system,
                                    'rss_bytes':mem.rss,'private_bytes':getattr(mem,'private',None),
                                    'gpu_adapter_csv':gpu.stdout.strip(),'other_godot':others})
                except (psutil.NoSuchProcess,psutil.AccessDenied): pass
            time.sleep(1)
    log=(A/(name+'.log')).read_text(encoding='utf-8',errors='replace')
    record={'name':name,'command':command,'exit':p.returncode,'engine_errors':bool(ERROR.search(log)),
            'wall_s':time.monotonic()-begin,'expected_failure':expected_failure}
    records.append(record)
    (A/'completion-verification-2.json').write_text(json.dumps(records,indent=2))
    if native: (A/(name+'-host.json')).write_text(json.dumps(samples,indent=2))
    print(name,record,'\n'+' / '.join(log.splitlines()[-2:]),flush=True)
    if record['engine_errors'] or (p.returncode!=0)!=expected_failure:
        raise RuntimeError('Unexpected result: '+name)
    return log

if __name__=='__main__':
    # Deliberate mutation only in the disposable agent project; always restore it.
    draft=A/'cloud-candidate/project/render/atmosphere.gd'
    original=draft.read_bytes()
    try:
        mutant=original.replace(b'\t_invalidate_cloud_derived_cache()',b'\tpass # deliberate cache-invalidation mutation')
        assert mutant!=original
        draft.write_bytes(mutant)
        run('cloud-invalidation-mutation-2',A/'cloud-candidate/project','res://tests/test_atmosphere_cloud_expected.gd',expected_failure=True)
    finally:
        draft.write_bytes(original)
    run('cloud-independent-final',A/'cloud-candidate/project','res://tests/test_atmosphere_cloud_expected.gd')
    comparison=[]
    candidate={rel:(PROJECT/rel).read_bytes() for rel in ['render/atmosphere.gd','render/weather/storm_bank.gd']}
    try:
        for variant in ['candidate','reference']:
            for rel in candidate:
                data=candidate[rel] if variant=='candidate' else (A/'reference-src'/rel).read_bytes()
                (PROJECT/rel).write_bytes(data)
            name='native-'+variant+'-unprofiled-2'
            output=A/(name+'.json')
            assert not output.exists(), 'Refuse existing output'
            run(name,PROJECT,A/'native_flight_unprofiled.gd',['--output='+str(output),'--resume-focus-loss'],native=True)
            report=json.loads(output.read_text());assert report['complete']
            comparison.append({'variant':variant,'sha256':{rel:hashlib.sha256((PROJECT/rel).read_bytes()).hexdigest() for rel in candidate},
                               'cases':[{k:c[k] for k in ['scenario','tick','numeric_sha256','focus_uninterrupted','focus_events']} for c in report['cases']]})
    finally:
        for rel,data in candidate.items(): (PROJECT/rel).write_bytes(data)
    assert [c['numeric_sha256'] for c in comparison[0]['cases']]==[c['numeric_sha256'] for c in comparison[1]['cases']]
    (A/'unprofiled-comparison-2.json').write_text(json.dumps(comparison,indent=2))
    # Native Home/Fly/Home with private settings and the affected storm appearance.
    text=(ROOT/'research/performance/loading_probe.gd').read_text()
    text=text.replace('prefs.start_choice = "airborne"','prefs.start_choice = "airborne"\n\tprefs.sky_config = load("res://environment/sky_appearance_config.gd").for_preset("distant_storm")')
    loading=A/'loading_storm.gd';loading.write_text(text)
    output=A/'loading-storm-candidate.json';assert not output.exists()
    run('loading-storm-candidate',PROJECT,loading,['--output='+str(output),'--cycles=3'],native=True)
    assert json.loads(output.read_text())['complete']
    print('All completion checks finished; production physics and timestep were never edited.',flush=True)
