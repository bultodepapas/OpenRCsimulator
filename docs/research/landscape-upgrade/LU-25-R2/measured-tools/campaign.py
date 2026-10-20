from pathlib import Path
import ctypes, hashlib, json, statistics, subprocess, time
r = Path.cwd()
w = r / 'tmp/perf-pass3-20261019'
app = w / 'base/app'
engine = r / '.tools/Godot_v4.7.2-stable_win64.exe'
probe = w / 'paired_session.gd'
candidate = w / 'candidate/sim/flight_session.gd'
kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
affinity = kernel32.SetProcessAffinityMask
affinity.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
affinity.restype = ctypes.c_int
ledger = []
cases = [('jensen-das-ugly-stik-60','runway',1), ('jensen-das-ugly-stik-60','trim',1), ('jensen-das-ugly-stik-60','runway',2), ('p51d-mustang-120','trim',1), ('jensen-das-ugly-stik-60','runway',3)]
for aid, case, repeat in cases:
    name = f'paired-{aid}-{case}-r{repeat}'
    output = w / (name + '.json')
    command = [str(engine), '--headless', '--path', str(app), '--audio-driver', 'Dummy',
        '--script', str(probe), '--', '--reference=res://sim/flight_session.gd',
        '--candidate=' + str(candidate), '--aircraft=' + aid, '--case=' + case,
        '--warmup=2400', '--samples=14400', '--output=' + str(output)]
    start = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if not affinity(int(process._handle), 1 << 4):
        process.kill()
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        log, _ = process.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        process.kill()
        log, _ = process.communicate()
        (w / (name + '.log')).write_text(log)
        raise
    (w / (name + '.log')).write_text(log)
    if process.returncode or 'ERROR:' in log:
        raise RuntimeError(name + ': ' + log[-2000:])
    data = json.loads(output.read_text())
    assert data['complete'] and not data['failure'] and data['completed_batches'] == 120
    assert len(data['baseline_tick_usec']) == len(data['candidate_tick_usec']) == 14400
    assert data['fingerprints'][0] == data['fingerprints'][1]
    gains = [100 * (1 - b / a) for a, b in zip(data['baseline_batch_usec'], data['candidate_batch_usec'])]
    row = {'name': name, 'command': command, 'seconds': time.monotonic()-start, 'affinity_mask': 16,
        'baseline_session_sha256': data['reference_session_sha256'],
        'candidate_session_sha256': data['candidate_session_sha256'],
        'probe_sha256': hashlib.sha256(probe.read_bytes()).hexdigest(),
        'baseline_median_tick_usec': statistics.median(data['baseline_tick_usec']),
        'candidate_median_tick_usec': statistics.median(data['candidate_tick_usec']),
        'median_paired_reduction_percent': statistics.median(gains),
        'winning_pairs': sum(g > 0 for g in gains), 'paired_batches': len(gains)}
    ledger.append(row)
    (w / 'campaign.json').write_text(json.dumps(ledger, indent=2))
    print(name, 'PASS', round(row['median_paired_reduction_percent'], 2), '%', row['winning_pairs'], '/120 wins', flush=True)
