"""Sequence the existing benchmark; keep physics/workload and engine unchanged."""
from pathlib import Path
import ctypes, hashlib, json, subprocess, sys, time

work = Path(__file__).resolve().parent
root = work.parents[1]
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.GetCurrentProcess.restype = ctypes.c_void_p
kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
handle = kernel.GetCurrentProcess()
mask = 1 << 20
if not kernel.SetProcessAffinityMask(handle, mask):
    raise ctypes.WinError(ctypes.get_last_error())
identity = json.loads((work/'comparison-manifest.json').read_text())
receipt = {'affinity_mask': mask, 'logical_processor': 20,
           'method': 'ABBA; existing benchmark; launcher affinity inherited by child engine processes; no other Godot at window boundaries; CPU frequency, thermals and non-engine host work uncontrolled',
           'runs': []}
def other_engines():
    query = "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot' } | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress"
    observed = subprocess.check_output(['powershell', '-NoProfile', '-Command', query], text=True).strip()
    return json.loads(observed) if observed else []

for label, source in [('pinned-a1', 'baseline'), ('pinned-b1', 'candidate'), ('pinned-b2', 'candidate'), ('pinned-a2', 'baseline')]:
    app = work/source/'app'
    output = work/(label+'.json')
    assert not output.exists(), output
    command = [sys.executable, str(root/'tools/godot/run_checked.py'), '--out-dir', str(work/'checks'),
               '--label', label, '--timeout', '600', '--', str(root/'.tools/Godot_v4.8-beta1_win64_console.exe'),
               '--headless', '--path', str(app), '--audio-driver', 'Dummy', '--script', 'res://tests/bench_spatial_wind.gd',
               '--', '--full-session', '--aircraft=gp-extra-300s-60', '--samples=5',
               '--case=spatial-v5-modes-24', '--case=spatial-v5-gusts-thermals-24',
               '--output='+str(output), '--revision='+identity[source]['solver_sha256'],
               '--manifest-sha256='+hashlib.sha256((work/'comparison-manifest.json').read_bytes()).hexdigest()]
    before_engines = other_engines()
    if before_engines:
        (work/'timing-blocked.json').write_text(json.dumps(before_engines, indent=2)+'\n')
        raise SystemExit('Other Godot work detected; timing stopped')
    started = time.time()
    print('Starting '+label, flush=True)
    run = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
    (work/(label+'.log')).write_text(run.stdout+run.stderr, encoding='utf-8')
    receipt['runs'].append({'label': label, 'source': source, 'started_unix_s': started,
                            'finished_unix_s': time.time(), 'exit_code': run.returncode, 'command': command,
                            'other_engines_before': before_engines, 'other_engines_after': other_engines()})
    (work/'pinned-sequence.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    if receipt['runs'][-1]['other_engines_after']:
        raise SystemExit('Other Godot work detected after window; reject timing interpretation')
    if run.returncode:
        raise SystemExit(run.stdout+run.stderr)
    print('Completed '+label, flush=True)
