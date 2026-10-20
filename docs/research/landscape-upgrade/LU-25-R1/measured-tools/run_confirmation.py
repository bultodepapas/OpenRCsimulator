from pathlib import Path
import hashlib, json, subprocess, statistics

root = Path.cwd()
work = root / 'tmp/perf-20261019-work'
app = work / 'profile/app'
leaf = app / 'physics/lake_surface.gd'
sources = {'baseline': work / 'base/app/physics/lake_surface.gd',
           'candidate': work / 'lake_final_candidate.gd'}
godot = root / '.tools/Godot_v4.7.2-stable_win64_console.exe'
probe = root / 'research/performance/session_probe.gd'
ledger = []
try:
    for repeat in range(3):
        for mode in (['baseline', 'candidate'] if repeat % 2 == 0 else ['candidate', 'baseline']):
            leaf.write_bytes(sources[mode].read_bytes())
            name = f'confirmation-stik-{repeat + 1}-{mode}'
            output = work / (name + '.json')
            command = [str(godot), '--headless', '--path', str(app), '--audio-driver', 'Dummy',
                       '--script', str(probe), '--', '--aircraft=jensen-das-ugly-stik-60',
                       '--case=trim', '--observer=on', '--warmup-ticks=2400',
                       '--sample-ticks=14400', '--output=' + str(output)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=240)
            log = result.stdout + result.stderr
            (work / (name + '.log')).write_text(log)
            if result.returncode or 'ERROR:' in log:
                raise RuntimeError(name + ': ' + log[-2000:])
            data = json.loads(output.read_text())
            assert data['complete'] and data['completed'] == data['requested']
            assert len(data['tick_usec']) == 14400
            entry = {'repeat': repeat + 1, 'mode': mode, 'output': output.name,
                     'leaf_sha256': hashlib.sha256(leaf.read_bytes()).hexdigest(),
                     'probe_sha256': hashlib.sha256(probe.read_bytes()).hexdigest(),
                     'command': command, 'fingerprint': data['fingerprint'],
                     'median_tick_usec': statistics.median(data['tick_usec']),
                     'mean_tick_usec': statistics.mean(data['tick_usec'])}
            ledger.append(entry)
            (work / 'confirmation-ledger.json').write_text(json.dumps(ledger, indent=2))
            print(name, entry['median_tick_usec'], entry['mean_tick_usec'], flush=True)
    assert len({entry['fingerprint'] for entry in ledger}) == 1
finally:
    leaf.write_bytes(sources['candidate'].read_bytes())
