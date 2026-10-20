"""Bounded, process-scoped stack snapshots; no elevation or system trace changes.

API contract: https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/nf-minidumpapiset-minidumpwritedump
Snapshot intervals can perturb timing and must be excluded from causal FPS comparisons.
"""
from pathlib import Path
import ctypes
from ctypes import wintypes
import json
import msvcrt
import subprocess
import sys
import threading
import time

kernel = ctypes.WinDLL('kernel32', use_last_error=True)
dbghelp = ctypes.WinDLL('dbghelp', use_last_error=True)
kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel.OpenProcess.restype = wintypes.HANDLE
kernel.CloseHandle.argtypes = [wintypes.HANDLE]
kernel.CloseHandle.restype = wintypes.BOOL
dbghelp.MiniDumpWriteDump.argtypes = [wintypes.HANDLE,wintypes.DWORD,wintypes.HANDLE,wintypes.DWORD,
                                    ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p]
dbghelp.MiniDumpWriteDump.restype = wintypes.BOOL


def dump(pid, path):
    begin = time.perf_counter()
    handle = kernel.OpenProcess(0x0400 | 0x0010, False, pid)  # query information + VM read
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        with Path(path).open('xb') as output:
            ok = dbghelp.MiniDumpWriteDump(handle, pid, msvcrt.get_osfhandle(output.fileno()),
                                          0x1000 | 0x20, None, None, None)
            if not ok:
                raise ctypes.WinError(ctypes.get_last_error())
        with Path(path).open('rb') as check:
            assert check.read(4) == b'MDMP', 'Invalid minidump header'
        return {'path':str(path),'bytes':Path(path).stat().st_size,
                'capture_usec':(time.perf_counter()-begin)*1e6}
    finally:
        kernel.CloseHandle(handle)


def watchdog(process, folder, stop):
    """The frame writer flushes once/second. Capture after 2.5 seconds without growth.

    At most three snapshots, at least 15 seconds apart, after observer readiness.
    Never inject code, modify simulation state, auto-resume or terminate the game.
    """
    folder = Path(folder)
    size = -1
    changed = time.monotonic()
    last_capture = -1e6
    captures = 0
    with (folder/'stalls.jsonl').open('w',encoding='utf-8',buffering=1) as log:
        while not stop.wait(.1) and process.poll() is None:
            if not (folder/'ready.json').exists():
                changed = time.monotonic()
                continue
            try:
                current = (folder/'frames.csv').stat().st_size
            except OSError:
                continue
            now = time.monotonic()
            if current != size:
                size = current
                changed = now
            if now-changed < 2.5 or now-last_capture < 15 or captures >= 3:
                continue
            captures += 1
            last_capture = now
            log.write(json.dumps({'kind':'capture_begin','unix_s':time.time(),
                                  'no_frame_file_growth_s':now-changed,'pid':process.pid})+'\n')
            try:
                result = dump(process.pid,folder/f'stall-{captures}.dmp')
                log.write(json.dumps({'kind':'capture_end','unix_s':time.time(),**result})+'\n')
            except Exception as exc:
                log.write(json.dumps({'kind':'capture_error','unix_s':time.time(),'error':str(exc)})+'\n')


if __name__ == '__main__':
    # Verify normal-user dump rights and file validity using an owned disposable child.
    target = Path(sys.argv[1])
    child = subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)'],
                             creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        time.sleep(.4)
        result = dump(child.pid,target)
        print(json.dumps(result))
    finally:
        child.terminate()
        child.wait()
