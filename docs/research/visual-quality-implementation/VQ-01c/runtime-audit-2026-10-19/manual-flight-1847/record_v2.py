"""Launch the normal interactive app, monitor its owned PID, summarize on exit."""
from pathlib import Path
from datetime import datetime, timezone
import csv
import hashlib
import json
import math
import os
import platform
import re
import subprocess
import sys
import time
import psutil
import threading
from hang_dump import watchdog

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ENGINE = ROOT / '.tools/Godot_v4.7.2-stable_win64.exe'
SMOKE = '--smoke' in sys.argv
RUN = ROOT / 'tmp/manual-flight-recordings' / (datetime.now().strftime('%Y%m%d-%H%M%S') + ('-smoke-v2' if SMOKE else '-v2'))
RUN.mkdir(parents=True, exist_ok=False)
(HERE / 'latest.txt').write_text(str(RUN), encoding='utf-8')


def save(name, data):
    (RUN / name).write_text(json.dumps(data, indent=2), encoding='utf-8')


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def percentile(a, p):
    a = sorted(a)
    x = (len(a) - 1) * p
    i, j = math.floor(x), math.ceil(x)
    return a[i] + (a[j] - a[i]) * (x - i)


def summarize(exit_code):
    groups = {'all': [], 'focused_active_flight': []}
    largest = []
    with (RUN / 'frames.csv').open(newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            try:
                interval = int(row['interval_usec'])
                groups['all'].append(interval)
                if int(row['sim_tick']) >= 0 and row['focused'] == '1' and row['paused'] == '0':
                    groups['focused_active_flight'].append(interval)
                if interval >= 50000:
                    largest.append(row)
            except (ValueError, TypeError, KeyError):
                continue  # Keep partial final rows in raw file after an abnormal exit.
    result = {'exit_code': exit_code, 'scope': 'Exploratory manual session; engine callback intervals, not display-present times; GPU CSV is adapter-wide, not per-process; no reference comparison', 'groups': {}}
    for name, a in groups.items():
        if a:
            result['groups'][name] = {'frames': len(a), 'seconds': sum(a) / 1e6,
                'fps_mean': len(a) * 1e6 / sum(a),
                'p50_ms': percentile(a, .50) / 1000,
                'p95_ms': percentile(a, .95) / 1000,
                'p99_ms': percentile(a, .99) / 1000,
                'max_ms': max(a) / 1000,
                'over_33ms': sum(x > 33333 for x in a),
                'over_50ms': sum(x > 50000 for x in a),
                'over_100ms': sum(x > 100000 for x in a)}
    result['largest_intervals'] = sorted(largest, key=lambda r: int(r['interval_usec']), reverse=True)[:40]
    errors = []
    for line in (RUN / 'console.log').read_text(encoding='utf-8', errors='replace').splitlines():
        if re.search(r'\b(?:SCRIPT |SHADER )?ERROR:', line): errors.append(line)
    result['engine_error_lines'] = errors
    result['normal_observer_teardown'] = (RUN / 'observer-finish.json').exists()
    save('summary.json', result)


def main():
    command = [str(ENGINE), '--path', str(ROOT / 'app'), '--log-file', str(RUN / 'engine.log'), '--script', str(HERE / 'entry.gd')]
    if SMOKE: command[1:1] = ['--headless', '--audio-driver', 'Dummy']
    env = os.environ.copy()
    env['OPENRC_RECORD_DIR'] = str(RUN)
    env['OPENRC_PROFILE_SMOKE'] = '1' if SMOKE else '0'
    metadata = {'started_utc': datetime.now(timezone.utc).isoformat(), 'command': command,
        'git_head': git('rev-parse', 'HEAD'), 'git_status': git('status', '--short'),
        'os': platform.platform(), 'cpu_logical': psutil.cpu_count(),
        'cpu_physical': psutil.cpu_count(logical=False),
        'limits': ['GPU is whole-adapter utilization', 'Engine process/physics monitors are smoothed engine metrics',
                   'No GPU timestamp queries, screen recording or physics observer',
                   'Caches retained from previous run; cache temperature uncontrolled',
                   'Automatic stack snapshots can perturb timing; their intervals are tagged in stalls.jsonl',
                   'Normal focus safety and user preferences remain active'],
        'recorder_version': 2,
        'kernel_trace': {'available':False,'wpr_error':'0xc5585011 policy to profile system performance not enabled'},
        'stack_snapshots': {'trigger':'2.5 s without frame-file growth after ready','maximum':3,'minimum_gap_s':15,'overhead_file':'stalls.jsonl'},
        'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [ROOT/'app/main.gd', ROOT/'app/app_root.gd', ROOT/'app/project.godot',
                      ROOT/'app/sim/simulation.gd', HERE/'entry.gd', HERE/'observer.gd', HERE/'hang_dump.py', Path(__file__).resolve()]}}
    save('session.json', metadata)
    with (RUN / 'console.log').open('w', encoding='utf-8') as console:
        process = subprocess.Popen(command, cwd=ROOT, stdout=console, stderr=subprocess.STDOUT, env=env)
        metadata['pid'] = process.pid
        save('session.json', metadata)
        watcher_stop = threading.Event()
        watcher = threading.Thread(target=watchdog,args=(process,RUN,watcher_stop),daemon=True)
        watcher.start()
        gpu = None
        with (RUN / 'gpu.csv').open('w', encoding='utf-8') as gpu_file, (RUN / 'gpu-errors.log').open('w', encoding='utf-8') as gpu_errors, (RUN/'host.jsonl').open('w',encoding='utf-8',buffering=1) as host:
            try:
                gpu = subprocess.Popen(['nvidia-smi', '--query-gpu=timestamp,index,name,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu', '--format=csv', '--loop-ms=1000'], stdout=gpu_file, stderr=gpu_errors, creationflags=subprocess.CREATE_NO_WINDOW)
            except OSError as exc:
                gpu_errors.write(str(exc))
            proc = psutil.Process(process.pid)
            proc.cpu_percent(None)
            psutil.cpu_percent(None)
            sample_number = 0
            while process.poll() is None:
                begin = time.perf_counter()
                try:
                    mem = proc.memory_info()
                    cpu = proc.cpu_percent(None)
                    io = proc.io_counters()
                    sample = {'unix_s': time.time(), 'process_cpu_core_percent': cpu,
                        'process_cpu_machine_percent': cpu / psutil.cpu_count(),
                        'rss_bytes': mem.rss, 'private_bytes': getattr(mem,'private',None),
                        'threads': proc.num_threads(), 'read_bytes': io.read_bytes,
                        'write_bytes': io.write_bytes, 'system_cpu_percent': psutil.cpu_percent(None),
                        'system_available_bytes': psutil.virtual_memory().available}
                    # Avoid enumerating every process on this timing-sensitive loop.
                    sample['sampler_usec'] = (time.perf_counter() - begin) * 1e6
                    host.write(json.dumps(sample)+'\n')
                except psutil.NoSuchProcess:
                    break
                sample_number += 1
                time.sleep(max(.01, 1 - (time.perf_counter() - begin)))
            exit_code = process.wait()
            watcher_stop.set()
            watcher.join(timeout=15)
            if gpu and gpu.poll() is None:
                gpu.terminate()
                gpu.wait(timeout=10)
    save('process-exit.json', {'exit_code': exit_code, 'ended_utc': datetime.now(timezone.utc).isoformat()})
    summarize(exit_code)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        import traceback
        (RUN / 'monitor-error.txt').write_text(traceback.format_exc(), encoding='utf-8')
        raise
