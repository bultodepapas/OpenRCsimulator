from pathlib import Path
import datetime, gzip, json, shutil, sys

ROOT=Path.cwd()
OUT=Path(__file__).resolve().parent
RESULTS=Path(sys.argv[1]).resolve()
RESULTS.mkdir(parents=True,exist_ok=False)
sys.path.insert(0,str(ROOT/'research/performance'))
from native_summary import DEFAULT_POLICY, summarize_directory

def read_json(path):
    return json.loads(path.read_bytes() if path.exists() else gzip.decompress(Path(str(path)+'.gz').read_bytes()))

names=[f'{mode}-{n}' for n in [1,3] for mode in ['probe','planar']]
reference=None
intervals=[]
rows=[]
for name in names:
    mode=name.split('-')[0]
    identity=read_json(OUT/(name+'-identity.json'))
    assert identity['source_stable'] and identity['source_before']==identity['source_after'],name
    reference=reference or identity['source_before']
    assert reference==identity['source_before'], ('source changed between accepted runs',name)
    checked=next((OUT/'checks').glob(name+'-*/report.json'))
    receipt=json.loads(checked.read_text())
    assert receipt['ok'] and receipt['counts']['error']==0,name
    start=datetime.datetime.fromisoformat(receipt['started_utc'])
    end=start+datetime.timedelta(seconds=receipt['elapsed_seconds'])
    intervals.append((start,end,name))
    log=checked.with_name('engine.log').read_text()
    line=next(line for line in log.splitlines() if line.startswith('Keyboard flight diagnostic: '))
    selection=json.loads(line.split(': ',1)[1])
    assert selection['keyboard_selected'] and not selection['radio_connected'] and selection['focus'],name
    assert selection['input_enabled'] and selection['physics_enabled'] and not selection['initial_paused'],name
    data=read_json(OUT/(name+'.json'))
    assert not data['simulation']['paused'] and not data['simulation']['fault'],name
    state=data['render_settings']['lake_reflections']
    assert state['mode']==mode,name
    assert state['planar_active_at_report']==(mode=='planar'),name
    if mode=='planar': assert state['capture_size_at_report']==[640,360]
    directory=RESULTS/'campaign'/mode
    directory.mkdir(parents=True,exist_ok=True)
    index={1:1,3:2,4:3}[int(name.split('-')[1])]
    (directory/f'run-{index}.json').write_text(json.dumps(data)+'\n')
    shutil.copy2(checked.with_name('engine.log'),directory/f'run-{index}.log')
    rows.append(dict(name=name,mode=mode,frame_ms=data['frame_ms'],simulation=data['simulation'],
                     camera=data['camera'],max_fps=data['max_fps'],vsync_mode=data['vsync_mode'],
                     screen_refresh_hz=data['screen_refresh_hz'],warnings=receipt['counts']['warning']))
intervals.sort()
assert all(a[1]<=b[0] for a,b in zip(intervals,intervals[1:])), 'accepted processes overlap'
summaries={}
for mode in ['probe','planar']:
    summary,status=summarize_directory(RESULTS/'campaign'/mode,RESULTS/(mode+'-summary.json'),dict(DEFAULT_POLICY))
    summaries[mode]=dict(exit_code=status,performance_pass=summary['performance_pass'],
                         active_flight_qualifier_count=summary['active_flight_qualifier_count'])
(RESULTS/'comparison.json').write_text(json.dumps(dict(rows=rows,campaigns=summaries,
    accepted_processes_serial=True,source_same_for_all_accepted=True,
    order=[x[2] for x in intervals],excluded=['planar-2','probe-2','probe-4','planar-4'],
    workload='Custom bootstrap using ordinary Main and ControllerService; neutral physical keyboard; fixed pilot lake view; no input/pose override',
    limitations=['Not a pilot circuit, low jet pass, exact input-tape equivalence, 1080p or release/platform qualification',
                 'Main viewport/frame cadence only; no claim of isolated GPU cost or input-to-photon latency',
                 'Other host activity uncontrolled; shutdown warnings remain; reflection activity is end snapshot']),indent=2)+'\n')
print(json.dumps(summaries,indent=2))
