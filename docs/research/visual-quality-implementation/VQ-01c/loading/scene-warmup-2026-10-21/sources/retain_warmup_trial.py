from pathlib import Path
import hashlib, json, gzip
root = Path(__file__).resolve().parent
repo = root.parents[1]
out = repo / 'docs/research/visual-quality-implementation/VQ-01c/loading/scene-warmup-2026-10-21'
out.mkdir(parents=True, exist_ok=True)
records = []
def retain(path, relative):
    data = path.read_bytes()
    target = out / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    stored = gzip.compress(data, mtime=0) if target.suffix == '.gz' else data
    target.write_bytes(stored)
    assert (gzip.decompress(stored) if target.suffix == '.gz' else stored) == data
    records.append({'source':str(path.relative_to(repo)), 'retained':relative, 'raw_sha256':hashlib.sha256(data).hexdigest(), 'stored_sha256':hashlib.sha256(stored).hexdigest()})
for name in ('make_warmup_trial.py', 'run_warmup_trial.py', 'warmup-trial.patch', 'warmup-trial-identity.json', 'retain_warmup_trial.py', 'verify_sources.py'):
    retain(root/name, 'sources/'+name)
for variant in ('control', 'warmup'):
    for number in ('01','02'):
        label = variant+'-'+number
        retain(root/(label+'.json'), 'runs/'+label+'.json')
        matches = list((root/'native').glob(label+'-*'))
        assert len(matches) == 1
        for name in ('report.json','engine.log'):
            retain(matches[0]/name, 'runs/'+label+'/'+name)
for path in (root/'checks').glob('warmup-parse-*'):
    for name in ('report.json','engine.log'):
        retain(path/name, 'checks/'+name)
for label in ('test_simulation', 'test_ui_pause', 'test_start_choice'):
    matches = list((root/'checks').glob(label+'-*'))
    assert len(matches)==1, (label,matches)
    for name in ('report.json','engine.log'):
        retain(matches[0]/name, 'checks/'+label+'/'+name)
retain(root/'source-verification.json', 'source-verification.json')
rows=[]
for number in ('01','02'):
    pair={v:json.loads((root/f'{v}-{number}.json').read_text()) for v in ('control','warmup')}
    row={'pair':number, 'order':['control','warmup'] if number=='01' else ['warmup','control']}
    for v,p in pair.items():
        assert p['complete'] and p['shutdown']['audio_released'] and len(p['cycles'])==2
        row[v]={'home_from_load_s':p['home_first_draw_from_load_usec']/1e6,'home_engine_elapsed_s':p['home_first_draw_engine_elapsed_usec']/1e6,'first_fly_s':p['cycles'][0]['fly_first_draw_usec']/1e6,'warm_fly_s':p['cycles'][1]['fly_first_draw_usec']/1e6}
        row[v]['combined_s']=row[v]['home_from_load_s']+row[v]['first_fly_s']
    row['combined_improvement_percent']=100*(1-row['warmup']['combined_s']/row['control']['combined_s'])
    row['home_regression_percent']=100*(row['warmup']['home_from_load_s']/row['control']['home_from_load_s']-1)
    rows.append(row)
(out/'comparison.json').write_text(json.dumps({'decision':'retain-baseline','scope':'source/editor stop-go; not qualification', 'pairs':rows},indent=2)+'\n')
(out/'evidence-manifest.json').write_text(json.dumps({'files':records},indent=2)+'\n')
print(json.dumps(rows,indent=2))
