from pathlib import Path
import subprocess,sys,json
repo=Path.cwd(); root=Path('D:/OpenRCsimulator-scratch/windsock-grid-20261021-8b808672')
for number in range(1,6):
 for variant in (['collector','diagnostic'] if number%2 else ['diagnostic','collector']):
  result=subprocess.run([sys.executable,str(repo/'tmp/wind_run_package_loading.py'),variant,f'{number:02d}'],capture_output=True,text=True)
  print(result.stdout[-600:] if result.returncode else '',flush=True)
  if result.returncode: print(result.stderr,flush=True);sys.exit(result.returncode)
  r=json.loads((root/'runs'/f'{variant}-{number:02d}.json').read_text())
  print(json.dumps({'pair':number,'variant':variant,'home_ms':r['home_first_draw_from_load_usec']/1000,'first_fly_ms':r['cycles'][0]['fly_first_draw_usec']/1000,'warm_fly_ms':r['cycles'][1]['fly_first_draw_usec']/1000,'active':all(not c['paused_at_first_draw'] and c['tick_at_first_draw']>0 for c in r['cycles'])}),flush=True)
