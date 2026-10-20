from pathlib import Path
import ctypes, hashlib, json, subprocess, statistics

root = Path.cwd()
work = root / 'tmp/perf-20261019-work'
app = work / 'profile/app'
leaf = app / 'physics/lake_surface.gd'
sources = {'baseline': work / 'base/app/physics/lake_surface.gd',
           'candidate': work / 'lake_final_candidate.gd'}
godot = root / '.tools/Godot_v4.7.2-stable_win64.exe'
probe = root / 'research/performance/session_probe.gd'
kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
set_affinity = kernel32.SetProcessAffinityMask
set_affinity.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
set_affinity.restype = ctypes.c_int
ledger = []
try:
    for repeat in range(3):
        for mode in (['baseline', 'candidate'] if repeat % 2 == 0 else ['candidate', 'baseline']):
            leaf.write_bytes(sources[mode].read_bytes())
            name = f'affinity-stik-{repeat + 1}-{mode}'
            output = work / (name + '.json')
            command = [str(godot), '--headless', '--path', str(app), '--audio-driver', 'Dummy',
                       '--script', str(probe), '--', '--aircraft=jensen-das-ugly-stik-60',
                       '--case=trim', '--observer=on', '--warmup-ticks=2400',
                       '--sample-ticks=14400', '--output=' + str(output)]
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            # Pin only our child engine to logical CPU 4, before its warmup.
            if not set_affinity(int(process._handle), 1 << 4):
                process.kill()
                raise ctypes.WinError(ctypes.get_last_error())
            try:
                log, _ = process.communicate(timeout=240)
            except subprocess.TimeoutExpired:
                process.kill()
                log, _ = process.communicate()
                (work / (name + '.log')).write_text(log)
                raise
            (work / (name + '.log')).write_text(log)
            if process.returncode or 'ERROR:' in log:
                raise RuntimeError(name + ': ' + log[-2000:])
            data = json.loads(output.read_text())
            assert data['complete'] and data['completed'] == data['requested']
            assert len(data['tick_usec']) == 14400
            entry = {'repeat': repeat + 1, 'mode': mode, 'output': output.name,
                     'affinity_mask': 1 << 4,
                     'leaf_sha256': hashlib.sha256(leaf.read_bytes()).hexdigest(),
                     'probe_sha256': hashlib.sha256(probe.read_bytes()).hexdigest(),
                     'command': command, 'fingerprint': data['fingerprint'],
                     'median_tick_usec': statistics.median(data['tick_usec']),
                     'mean_tick_usec': statistics.mean(data['tick_usec'])}
            ledger.append(entry)
            (work / 'affinity-ledger.json').write_text(json.dumps(ledger, indent=2))
            print(name, entry['median_tick_usec'], entry['mean_tick_usec'], flush=True)
    assert len({entry['fingerprint'] for entry in ledger}) == 1
finally:
    leaf.write_bytes(sources['candidate'].read_bytes())
