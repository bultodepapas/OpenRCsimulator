import json
import subprocess
import time
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
ENGINE = ROOT / '.tools/Godot_v4.7.2-stable_win64_console.exe'
records = []
if '--after-only' in sys.argv or '--timing-pair' in sys.argv:
    records = json.loads((OUT / 'native-runs.json').read_text())

def run(label, build, cases, frames=600, extra=()):
    if '--timing-pair' in sys.argv and label not in ['final-before-day','final-after-day','final-before-night','final-after-night']:
        return
    if '--scenery-only' in sys.argv and label not in ['final-after-day','final-after-night','final-blue-hour','final-details']:
        return
    if '--after-only' in sys.argv and build == 'lu16-baseline':
        return
    dest = OUT / label
    dest.mkdir(exist_ok=True)
    cmd = [str(ENGINE), '--path', str(ROOT / '.tools' / build / 'app'),
           '--script', 'res://tests/capture_landscape_upgrade.gd', '--',
           '--out=' + dest.as_posix(), '--width=1920', '--height=1080',
           '--frames=' + str(frames), '--engine_shadows=on', '--scenery=on',
           '--scenery_audio=off', '--soundscape=off', '--cases=' + cases, *extra]
    start = time.time()
    with (OUT / (label + '.log')).open('w') as log:
        result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=180)
    error = 'ERROR:' in (OUT / (label + '.log')).read_text()
    records[:] = [r for r in records if r['label'] != label]
    records.append(dict(label=label, command=cmd, seconds=time.time()-start,
                        exit=result.returncode, engine_error=error))
    (OUT / 'native-runs.json').write_text(json.dumps(records, indent=2))
    print(label, result.returncode, 'error=' + str(error), flush=True)
    if result.returncode or error:
        raise RuntimeError(label)

common = 'pilot_north,postcard_club,car_park,postcard_pavilion,postcard_pits,aerial_overview,people_5m,cars_5m,seated_5m,pilot_5m'
# Paired sequential runs: no simultaneous engines launched by this task.
run('final-before-day', 'lu16-baseline', common)
run('final-after-day', 'lu16-stage', common)
run('final-before-night', 'lu16-baseline', 'runway_threshold,runway_inside,runway_east_far,postcard_pavilion,postcard_club', extra=('--time_of_day=night',))
run('final-after-night', 'lu16-stage', 'runway_threshold,runway_inside,runway_east_far,postcard_pavilion,postcard_club', extra=('--time_of_day=night',))
run('final-blue-hour', 'lu16-stage', 'pilot_north,horizon_raised120,twilight_aircraft,twilight_background,postcard_pavilion', extra=('--time_of_day=blue_hour',))
run('final-details', 'lu16-stage', 'entry_path,flower_border,people_15m,people_40m,parked_stik,parked_extra,parked_p51,parked_avanti')
glare = 'clear,off,blocked,blocked_off,partial,partial_off,aircraft,aircraft_off,side,side_off,night,night_off,cloud,cloud_off,low_exposure,low_exposure_off,aircraft_left,aircraft_left_off,aircraft_right,aircraft_right_off,half'
run('final-glare', 'lu16-stage', ','.join('glare_'+x for x in glare.split(',')), frames=30)
run('final-markers', 'lu16-stage', 'marker_clear,marker_half,marker_off,marker_occluded,runway_threshold,runway_inside,runway_east_far', frames=30, extra=('--time_of_day=night',))
run('final-sun-transit', 'lu16-stage', 'glare_aircraft', frames=121, extra=('--motion=aircraft',))
