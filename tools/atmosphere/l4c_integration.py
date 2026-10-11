#!/usr/bin/env python3
"""Verify L4c through actual app entry, traces, time-of-day routes and an exported pack.

Use frozen imported app snapshots and a fresh output folder. Native display needed.
Pillow 12.3.0 and NumPy 2.4.6 are the measured evidence environment.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('godot','app','baseline','out'):
        p.add_argument('--'+key,type=Path,required=True)
    a = p.parse_args()
    out = a.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    engine = a.godot.resolve()
    apps = {'before':a.baseline.resolve(),'after':a.app.resolve()}
    env = dict(os.environ,APPDATA=str(out/'user'),XDG_DATA_HOME=str(out/'user'),OPENRC_SCENERY='off')
    records = {}

    def run(key,name,options):
        cmd = [str(engine),'--path',str(apps[key]),'--audio-driver','Dummy',*options]
        r = subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env,
                           timeout=180,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        (out/(name+'.log')).write_bytes(r.stdout)
        assert r.returncode==0 and b'ERROR:' not in r.stdout,(name,r.returncode,r.stdout[-2000:])
        print(name,'PASS',flush=True)

    for key in apps:
        run(key,key+'-trace',['--headless','--','--trace='+str(out/(key+'.csv')),'--t=3'])
    traces = [(out/(key+'.csv')).read_text().splitlines() for key in apps]
    assert len(traces[0])==len(traces[1])
    differences = [(i,b,c) for i,(b,c) in enumerate(zip(*traces)) if b!=c]
    assert all(b.startswith('# created_utc:') and c.startswith('# created_utc:') for _,b,c in differences),differences
    rows = [line for line in traces[0] if line and not line.startswith('#')]
    assert len(rows)==722, 'header plus 721 initial/tick rows required'
    records['trace'] = {'samples':721,'differences':differences}

    for case,opts in [('day',[]),('sunrise',['--time_of_day=sunrise']),
                      ('moon',['--time_of_day=night']),('dark',['--time_of_day=night_dark']),
                      ('precise-night',['--time-of-day=00:00'])]:
        for key in apps:
            run(key,key+'-'+case,['--','--capture','--scripted','--t=3',
                                 '--out='+str(out/(key+'-'+case+'.png')),*opts])
        b,c = (np.asarray(Image.open(out/(key+'-'+case+'.png'))).astype(np.int16) for key in apps)
        records[case]={'changed_pixels':int(np.any(b!=c,axis=2).sum()),'max_increase':int((c-b).max())}
        if case in ('dark','precise-night'):
            assert (c-b).max()<=1, (case,'unlit sky gained light')
        if case == 'precise-night':
            assert np.array_equal(b,c), 'precise midnight differs'
    pack = out/'candidate.pck'
    run('after','export',['--headless','--editor','--export-pack','Windows',str(pack)])
    assert pack.is_file() and pack.stat().st_size>0
    run('after','pack-day',['--main-pack',str(pack),'--','--capture','--scripted','--t=3','--out='+str(out/'pack-day.png')])
    assert np.array_equal(np.asarray(Image.open(out/'pack-day.png')),np.asarray(Image.open(out/'after-day.png'))),'pack differs'
    records['pack']={'sha256':hashlib.sha256(pack.read_bytes()).hexdigest(),'bytes':pack.stat().st_size,'day_pixel_parity':True}
    (out/'summary.json').write_text(json.dumps(records,indent=2)+'\n')


if __name__=='__main__':
    main()
