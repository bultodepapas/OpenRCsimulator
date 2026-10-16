from pathlib import Path
import hashlib, json, math, statistics, subprocess

root = Path(__file__).resolve().parents[2]
out = root / 'tmp/menu-optimization'
engine = root / '.tools/Godot_v4.7.2-stable_win64_console.exe'
rows = []
for repeat in range(5):
    for variant in (['baseline','candidate'] if repeat % 2 == 0 else ['candidate','baseline']):
        command = [str(engine),'--headless','--path',str(root/'app'),'--audio-driver','Dummy',
                   '--script',str(out/'benchmark.gd')]
        if variant == 'baseline': command += ['--','--baseline']
        result = subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
        log = result.stdout + result.stderr
        tag = f'{repeat+1:02}-{variant}'
        (out/(tag+'.log')).write_text(log,encoding='utf-8')
        assert result.returncode == 0 and 'ERROR:' not in log, (tag,result.returncode,log[-3000:])
        data = json.loads((out/(variant+'.json')).read_text())
        (out/(tag+'.json')).write_text(json.dumps(data,indent=2),encoding='utf-8')
        rows.append(data)
        print(tag, 'volume', round(statistics.median(data['volume_handler_us']),2),
              'home', round(statistics.median(data['home_layout_handler_us']),2), flush=True)

summary = {'runs_per_variant':5,'samples_per_run':60,'unit':'microseconds','variants':{}}
for variant in ['baseline','candidate']:
    selected = [r for r in rows if r['variant']==variant]
    values = {}
    for key in ['volume_handler_us','home_layout_handler_us']:
        samples = sorted(v for row in selected for v in row[key])
        values[key] = {'median':statistics.median(samples),'p95':samples[math.ceil(len(samples)*.95)-1],
                       'max':max(samples),'count':len(samples)}
    values['events_per_run'] = {key:[r[key] for r in selected] for key in
        ['volume_theme_events','home_gradient_events','home_font_events']}
    summary['variants'][variant] = values
summary['source_sha256'] = {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in
    [root/'app/app_root.gd',root/'app/ui/home.gd',out/'baseline_root.gd',out/'baseline_home.gd',out/'benchmark.gd']}
(out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary['variants']))
