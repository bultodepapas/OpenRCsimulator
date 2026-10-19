"""Read an existing capture; retain raw timing and attribution limitations."""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import csv
import hashlib
import json
import math
import statistics
import sys

run = Path(sys.argv[1])
frames = list(csv.DictReader((run / 'frames.csv').open(newline='', encoding='utf-8')))
events = [json.loads(x) for x in (run / 'events.jsonl').read_text().splitlines()]
host = [json.loads(x) for x in (run / 'host.jsonl').read_text().splitlines()]
session = json.loads((run / 'session.json').read_text())
finish = json.loads((run / 'observer-finish.json').read_text())
anchor = next(e['detail'] for e in events if e['kind'] == 'clock_anchor')
contexts = {e['detail']['id']: e['detail']['state'] for e in events if e['kind'] == 'context'}
bogota = ZoneInfo('America/Bogota')


def unix(engine_us):
    return anchor['unix_s'] + (engine_us - anchor['engine_usec']) / 1e6


def stats(values):
    a = sorted(values)
    def q(p):
        x = (len(a)-1)*p
        i, j = math.floor(x), math.ceil(x)
        return a[i]+(a[j]-a[i])*(x-i)
    return {'count': len(a), 'min': a[0], 'p50': q(.5), 'p95': q(.95),
            'p99': q(.99), 'max': a[-1], 'first': values[0], 'last': values[-1]}


assert len(frames) == finish['frames']
assert all(int(r['interval_usec']) > 0 for r in frames)
assert all(int(frames[i]['engine_usec']) > int(frames[i-1]['engine_usec']) for i in range(1,len(frames)))
assert all(int(frames[i]['engine_usec'])-int(frames[i-1]['engine_usec']) == int(frames[i]['interval_usec']) for i in range(1,len(frames)))
active = [r for r in frames if r['focused']=='1' and r['paused']=='0' and int(r['sim_tick'])>=0]
raw_active = active
captures = []
stall_file = run/'stalls.jsonl'
if stall_file.exists():
    pending = None
    for line in stall_file.read_text().splitlines():
        item = json.loads(line)
        if item['kind'] == 'capture_begin':
            pending = item
        elif item['kind'] in ['capture_end','capture_error'] and pending is not None:
            captures.append((pending['unix_s'], item['unix_s']))
            pending = None
def contaminated(row):
    end = int(row['engine_usec']); begin = end-int(row['interval_usec'])
    return any(unix(begin)<=stop and unix(end)>=start for start,stop in captures)
active = [row for row in raw_active if not contaminated(row)]
t0, t1 = int(active[0]['engine_usec']), int(active[-1]['engine_usec'])
ah = [r for r in host if unix(t0) <= r['unix_s'] <= unix(t1)]
gpu = []
for row in csv.DictReader((run / 'gpu.csv').open(newline='',encoding='utf-8')):
    r = {k.strip(): v.strip() for k,v in row.items()}
    r['unix_s'] = datetime.strptime(r['timestamp'],'%Y/%m/%d %H:%M:%S.%f').replace(tzinfo=bogota).timestamp()
    gpu.append(r)
ag = [r for r in gpu if unix(t0) <= r['unix_s'] <= unix(t1)]
result = {
    'format': 'openrc-manual-flight-analysis v1',
    'timezone': 'America/Bogota',
    'quality': {'raw_rows_match_finish': True, 'monotonic_intervals_valid': True,
        'context_poll_msec':100, 'context_eligibility':'endpoint state; transition frames remain included',
        'frame_clock':'engine observer callbacks, not display presents',
        'gpu_scope':'whole adapter; no per-process timestamps or wait stacks',
        'host_sampling':'irregular, coarse CPU/memory samples; no wait-state attribution',
        'gpu_csv_timezone':'America/Bogota; matches launch UTC and local driver timestamp',
        'marker_count':finish['markers'], 'snapshot_intervals_unix_s':captures, 'excluded_active_capture_overlap_frames':len(raw_active)-len(active), 'observer_scope':'own callback clocks; external monitor and OS overhead not included'},
    'active_frame_interval_ms':stats([int(r['interval_usec'])/1000 for r in active]),
    'raw_active_fps_mean':len(raw_active)*1e6/sum(int(r['interval_usec']) for r in raw_active),
    'active_fps_mean':len(active)*1e6/sum(int(r['interval_usec']) for r in active),
    'active_endpoint_simulation':{'first_tick':int(active[0]['sim_tick']),
        'last_tick':int(active[-1]['sim_tick']), 'wall_s':(t1-t0)/1e6,
        'simulation_s':(int(active[-1]['sim_tick'])-int(active[0]['sim_tick']))/240,
        'simulation_to_wall_ratio':(int(active[-1]['sim_tick'])-int(active[0]['sim_tick']))/240/((t1-t0)/1e6)},
    'host_active':{k:stats([r[k] for r in ah]) for k in ['process_cpu_core_percent',
        'process_cpu_machine_percent','system_cpu_percent','rss_bytes','private_bytes','sampler_usec']},
    'gpu_active':{k:stats([float(r[k].split()[0]) for r in ag]) for k in
        ['utilization.gpu [%]','memory.used [MiB]','power.draw [W]','temperature.gpu']},
    'engine_active':{k:stats([float(r[k]) for r in active]) for k in
        ['nodes','objects','static_bytes','video_bytes','step_smoothed_usec','process_monitor_usec','physics_monitor_usec']},
    'observer':{'mean_usec':finish['observer_total_usec']/finish['frames'],
        'max_usec':finish['observer_max_usec'],'total_usec':finish['observer_total_usec']},
    'host_sample_gaps_s':stats([host[i]['unix_s']-host[i-1]['unix_s'] for i in range(1,len(host))]),
    'largest_intervals':[],
}
for r in sorted(frames,key=lambda x:int(x['interval_usec']),reverse=True)[:15]:
    end = int(r['engine_usec']); begin = end-int(r['interval_usec'])
    result['largest_intervals'].append({'begin_engine_s':begin/1e6,'end_engine_s':end/1e6,
        'begin_bogota':datetime.fromtimestamp(unix(begin),bogota).isoformat(),
        'end_bogota':datetime.fromtimestamp(unix(end),bogota).isoformat(),
        'duration_ms':int(r['interval_usec'])/1000,
        'endpoint_context':contexts[int(r['context_id'])],
        'endpoint_tick':int(r['sim_tick']), 'previous_observer_usec':int(r['previous_observer_usec'])})
(run/'analysis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
plt.rcParams.update({'font.size':9,'axes.spines.top':False,'axes.spines.right':False})
fig, axes = plt.subplots(4,1,figsize=(12,10),sharex=True,layout='constrained')
x = [(int(r['engine_usec'])-t0)/1e6 for r in frames]
axes[0].plot(x,[int(r['interval_usec'])/1000 if int(r['interval_usec'])<=100000 else None for r in frames],lw=.6,color='#236a9a')
spikes=[(xx,int(r['interval_usec'])/1000) for xx,r in zip(x,frames) if int(r['interval_usec'])>100000]
axes[0].scatter([a for a,b in spikes],[b for a,b in spikes],s=14,color='#ae3836',zorder=3)
axes[0].set_yscale('log'); axes[0].set_ylabel('Frame interval (ms)')
axes[0].axhline(16.667,color='#777777',ls='--',lw=.8,label='60 FPS interval')
axes[0].legend(loc='upper left')
hx=[(r['unix_s']-unix(t0)) for r in host]
axes[1].plot(hx,[r['process_cpu_core_percent'] for r in host],label='Simulator CPU (100% = one logical core)',color='#236a9a')
axes[1].plot(hx,[r['system_cpu_percent'] for r in host],label='Whole-system CPU (100% = all cores)',color='#a56220',alpha=.8)
axes[1].set_ylabel('CPU (%)'); axes[1].legend(loc='upper right',fontsize=8)
gx=[r['unix_s']-unix(t0) for r in gpu]
axes[2].plot(gx,[float(r['utilization.gpu [%]'].split()[0]) for r in gpu],color='#23836b')
axes[2].set_ylabel('Whole-adapter GPU (%)');axes[2].set_ylim(-2,105)
axes[3].plot(hx,[r['rss_bytes']/2**20 for r in host],label='Simulator RSS',color='#236a9a')
axes[3].plot(hx,[r['private_bytes']/2**20 for r in host],label='Simulator private bytes',color='#6c55a0')
axes[3].set_ylabel('Process memory (MiB)');axes[3].legend(loc='upper right',fontsize=8)
freeze=result['largest_intervals'][0]
axes[0].annotate(f"{freeze['duration_ms']/1000:.2f} s launch interval (snapshot overlap)",xy=(freeze['end_engine_s']-t0/1e6,freeze['duration_ms']),
    xytext=(freeze['end_engine_s']-t0/1e6+7,1200),arrowprops={'arrowstyle':'->','color':'#ae3836'},color='#ae3836')
for ax in axes:
    ax.grid(alpha=.18)
    ax.axvspan(freeze['begin_engine_s']-t0/1e6,freeze['end_engine_s']-t0/1e6,color='#c84b45',alpha=.13)
    ax.set_xlim(min(x),max(x))
axes[-1].set_xlabel('Seconds relative to first active-flight sample; negative time is Home / launch')
fig.suptitle('Manual Stik flight — 2026-10-19 18:47 America/Bogota\n4K / VSync / Compatibility; shaded launch interval includes stack-snapshot overhead; shared host',fontsize=12)
fig.savefig(run/'timeline.png',dpi=150)
plt.close(fig)
print(json.dumps({'frames':len(frames),'active_frames':len(active),'fps':result['active_fps_mean'],
    'freeze':freeze,'host_gaps':result['host_sample_gaps_s'],'plot':str(run/'timeline.png')},indent=2))
