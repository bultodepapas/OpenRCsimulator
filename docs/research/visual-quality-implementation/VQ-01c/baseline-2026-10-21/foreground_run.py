"""One-off phase-1 launch setup. Focus the owned Godot window once, before sampling.

No input injection, pause override, runtime patch or continuous focus enforcement.
The checked runner retains process/error evidence; this records the OS setup.
"""
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import subprocess
import sys
import time

import psutil

root = Path(__file__).resolve().parents[2]
base = Path(__file__).resolve().parent
label = sys.argv[1]
aircraft = sys.argv[2]
duration = sys.argv[3] if len(sys.argv) > 3 else '60'
diagnostics = len(sys.argv) > 4 and sys.argv[4] == 'diagnostics'
out = base / 'native' / (label + '.json')
setup = base / 'native' / (label + '-window.json')
if out.exists() or setup.exists():
    raise SystemExit('Refusing existing output')
command = [sys.executable, str(root/'tools/godot/run_checked.py'),
           '--out-dir', str(base/'native'), '--label', label, '--timeout', '140']
if diagnostics:
    command += ['--resources', '--resource-interval', '1']
command += ['--', str(root/'.tools/Godot_v4.7.2-stable_win64.exe'),
            '--path', str(root/'app'), '--audio-driver', 'Dummy', '--windowed',
            '--resolution', '1280x720', '--screen', '0', '--position', '80,80',
            '--max-fps', '60', '--', '--aircraft='+aircraft,
            '--frametimes='+out.as_posix(), '--warmup=10', '--t='+duration]
if diagnostics:
    command += ['--frame-diagnostics']
u = ctypes.WinDLL('user32', use_last_error=True)
callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
u.EnumWindows.argtypes = [callback, wintypes.LPARAM]
u.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
u.IsWindowVisible.argtypes = [wintypes.HWND]
u.GetForegroundWindow.restype = wintypes.HWND
u.SetForegroundWindow.argtypes = [wintypes.HWND]
u.SetForegroundWindow.restype = wintypes.BOOL
u.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
started = time.monotonic()
process = subprocess.Popen(command, cwd=root)
record = {'command': command, 'checked_runner_pid': process.pid,
          'policy': 'one OS focus request before warmup; normal pause safety unchanged',
          'found_window': False}
while time.monotonic() - started < 15 and process.poll() is None:
    try:
        children = psutil.Process(process.pid).children(recursive=True)
        pids = {p.pid for p in children if p.name().lower().startswith('godot')}
    except psutil.Error:
        pids = set()
    found = []
    @callback
    def visit(hwnd, ignored):
        pid = wintypes.DWORD()
        u.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value in pids and u.IsWindowVisible(hwnd):
            found.append((hwnd, pid.value))
        return True
    u.EnumWindows(visit, 0)
    if found:
        hwnd, pid = found[0]
        before = u.GetForegroundWindow()
        accepted = bool(u.SetForegroundWindow(hwnd))
        after = u.GetForegroundWindow()
        rect = wintypes.RECT()
        u.GetWindowRect(hwnd, ctypes.byref(rect))
        record.update(found_window=True, engine_pid=pid, window=int(hwnd),
                      request_elapsed_s=time.monotonic()-started,
                      was_foreground=before == hwnd, request_accepted=accepted,
                      is_foreground=after == hwnd,
                      outer_rect=[rect.left,rect.top,rect.right,rect.bottom])
        break
    time.sleep(0.1)
setup.write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
print('Window setup:', json.dumps(record), flush=True)
raise SystemExit(process.wait())
