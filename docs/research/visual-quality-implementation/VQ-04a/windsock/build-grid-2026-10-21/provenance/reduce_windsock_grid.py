import json,statistics
from pathlib import Path
root=Path('D:/OpenRCsimulator-scratch/windsock-grid-20261021-8b808672/runs')
rows=[]
for n in range(1,8):
 b=json.loads((root/f'collector-{n:02d}.json').read_text());c=json.loads((root/f'diagnostic-{n:02d}.json').read_text())
 active=all(not r['paused_at_first_draw'] and r['tick_at_first_draw']>0 for d in [b,c] for r in d['cycles'])
 def metrics(d):return {'home':d['home_first_draw_from_load_usec']/1000,'home_engine':d['home_first_draw_engine_elapsed_usec']/1000,'first_fly':d['cycles'][0]['fly_first_draw_usec']/1000,'warm_fly':d['cycles'][1]['fly_first_draw_usec']/1000,'return_home':d['cycles'][0]['return_first_draw_usec']/1000,'cold_combined':(d['home_first_draw_from_load_usec']+d['cycles'][0]['fly_first_draw_usec'])/1000,'warm_combined':(d['cycles'][0]['return_first_draw_usec']+d['cycles'][1]['fly_first_draw_usec'])/1000}
 rows.append({'pair':n,'eligible':active,'baseline':metrics(b),'candidate':metrics(c)})
valid=[r for r in rows if r['eligible']]
summary={k:{'baseline_median_ms':statistics.median(r['baseline'][k] for r in valid),'candidate_median_ms':statistics.median(r['candidate'][k] for r in valid),'median_paired_reduction_pct':statistics.median(100*(r['baseline'][k]-r['candidate'][k])/r['baseline'][k] for r in valid),'paired_delta_ms':[r['candidate'][k]-r['baseline'][k] for r in valid]} for k in valid[0]['baseline']}
result={'method':'five active paired processes, each with one warm repeat; pairs1/6 retained but excluded for pause','pairs':rows,'summary':summary};(root/'loading-summary.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(summary,indent=2))
