#!/usr/bin/env python3
"""Profile native Godot thread CPU time around a real audio gameplay capture.

Windows-only, standard-library profiler. Thread names come from Windows
GetThreadDescription; an unnamed/high-CPU thread is never guessed to be the
mixer. CPU-time deltas measure average thread cost, not individual mix blocks.
"""

from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
DEFAULT_APP = ROOT / "app"
DEFAULT_PROBE = ROOT / "tools" / "audio" / "gameplay_probe.gd"
DEFAULT_OUT = ROOT / ".tools" / "audio-profile" / "native-gameplay"
REPORT_PATH = ROOT / "docs" / "research" / "audio" / "AUD-04" / "native-profile.json"
CPU_TICKS_PER_SECOND = 10_000_000
TH32CS_SNAPTHREAD = 0x00000004
TH32CS_SNAPPROCESS = 0x00000002
THREAD_QUERY_INFORMATION = 0x0040
THREAD_QUERY_LIMITED_INFORMATION = 0x0800
PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
SYNCHRONIZE = 0x00100000
WAIT_OBJECT_0 = 0x00000000
WAIT_TIMEOUT = 0x00000102


class FILETIME(ctypes.Structure):
    _fields_ = [("dwLowDateTime", wintypes.DWORD), ("dwHighDateTime", wintypes.DWORD)]


class THREADENTRY32(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ThreadID", wintypes.DWORD),
        ("th32OwnerProcessID", wintypes.DWORD),
        ("tpBasePri", wintypes.LONG),
        ("tpDeltaPri", wintypes.LONG),
        ("dwFlags", wintypes.DWORD),
    ]


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("th32DefaultHeapID", ctypes.c_size_t),
        ("th32ModuleID", wintypes.DWORD),
        ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD),
        ("pcPriClassBase", wintypes.LONG),
        ("dwFlags", wintypes.DWORD),
        ("szExeFile", ctypes.c_wchar * 260),
    ]


def _filetime_ticks(value: FILETIME) -> int:
    return (int(value.dwHighDateTime) << 32) | int(value.dwLowDateTime)


def _cpu_seconds(user: int, kernel: int) -> float:
    return (user + kernel) / CPU_TICKS_PER_SECOND


def _child_processes(parent_process_id: int) -> list[dict[str, Any]]:
    """Return all descendants from a native Toolhelp process snapshot."""
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    kernel.Process32FirstW.restype = wintypes.BOOL
    kernel.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
    kernel.Process32NextW.restype = wintypes.BOOL
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    snapshot = kernel.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    invalid = ctypes.c_void_p(-1).value
    if not snapshot or ctypes.cast(snapshot, ctypes.c_void_p).value == invalid:
        raise ctypes.WinError(ctypes.get_last_error())
    entries: list[dict[str, Any]] = []
    try:
        entry = PROCESSENTRY32W()
        entry.dwSize = ctypes.sizeof(PROCESSENTRY32W)
        more = kernel.Process32FirstW(snapshot, ctypes.byref(entry))
        while more:
            entries.append(
                {
                    "process_id": int(entry.th32ProcessID),
                    "parent_process_id": int(entry.th32ParentProcessID),
                    "thread_count": int(entry.cntThreads),
                    "executable": entry.szExeFile,
                }
            )
            entry.dwSize = ctypes.sizeof(PROCESSENTRY32W)
            more = kernel.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel.CloseHandle(snapshot)
    descendants: list[dict[str, Any]] = []
    frontier = {parent_process_id}
    while frontier:
        next_frontier: set[int] = set()
        for entry in entries:
            if entry["parent_process_id"] in frontier:
                descendants.append(entry)
                next_frontier.add(entry["process_id"])
        frontier = next_frontier
    return descendants


def _find_engine_child(
    launcher_pid: int,
    godot_executable: Path,
    timeout_s: float,
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    """Find the non-console Godot sibling process created by the console launcher."""
    expected_name = godot_executable.name.replace("_console.exe", ".exe").casefold()
    deadline = time.monotonic() + timeout_s
    descendants: list[dict[str, Any]] = []
    while True:
        descendants = _child_processes(launcher_pid)
        candidates = [
            item for item in descendants
            if str(item["executable"]).casefold() == expected_name
        ]
        if candidates:
            candidates.sort(key=lambda item: item["thread_count"], reverse=True)
            return candidates[0], descendants
        if time.monotonic() >= deadline:
            return None, descendants
        time.sleep(0.05)


def _percent(cpu_seconds: float, wall_seconds: float) -> float:
    return 100.0 * cpu_seconds / wall_seconds if wall_seconds > 0.0 else 0.0


def _quantum_cost_ms(cpu_seconds: float, wall_seconds: float) -> float:
    # Mean single-thread CPU time allocated to a 10 ms reference mix quantum.
    return 10.0 * cpu_seconds / wall_seconds if wall_seconds > 0.0 else 0.0


class WinAudioThreadSampler:
    """Samples named thread CPU counters for one child process."""

    def __init__(self, process_id: int) -> None:
        if os.name != "nt":
            raise RuntimeError("Native thread profiling requires Windows APIs")
        self.process_id = process_id
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self._bind_apis()
        self.states: dict[tuple[int, int], dict[str, Any]] = {}
        self.thread_open_failures = 0
        self.counter_failures = 0
        self.thread_description_empty = 0
        self.thread_description_failures: list[str] = []
        self._get_thread_description = getattr(self.kernel, "GetThreadDescription", None)
        if self._get_thread_description is not None:
            self._get_thread_description.argtypes = [wintypes.HANDLE, ctypes.POINTER(ctypes.c_wchar_p)]
            self._get_thread_description.restype = ctypes.c_long
        self._get_precise_system_time = getattr(self.kernel, "GetSystemTimePreciseAsFileTime", None)
        if self._get_precise_system_time is not None:
            self._get_precise_system_time.argtypes = [ctypes.POINTER(FILETIME)]
            self._get_precise_system_time.restype = None
        self.kernel.GetSystemTimeAsFileTime.argtypes = [ctypes.POINTER(FILETIME)]
        self.kernel.GetSystemTimeAsFileTime.restype = None

    def _bind_apis(self) -> None:
        kernel = self.kernel
        kernel.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
        kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        kernel.Thread32First.argtypes = [wintypes.HANDLE, ctypes.POINTER(THREADENTRY32)]
        kernel.Thread32First.restype = wintypes.BOOL
        kernel.Thread32Next.argtypes = [wintypes.HANDLE, ctypes.POINTER(THREADENTRY32)]
        kernel.Thread32Next.restype = wintypes.BOOL
        kernel.OpenThread.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenThread.restype = wintypes.HANDLE
        kernel.GetThreadTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(FILETIME)] * 4
        kernel.GetThreadTimes.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle.restype = wintypes.BOOL
        kernel.LocalFree.argtypes = [ctypes.c_void_p]
        kernel.LocalFree.restype = ctypes.c_void_p

    def system_filetime(self) -> int:
        value = FILETIME()
        if self._get_precise_system_time is not None:
            self._get_precise_system_time(ctypes.byref(value))
        else:
            self.kernel.GetSystemTimeAsFileTime(ctypes.byref(value))
        return _filetime_ticks(value)

    def _thread_times(self, handle: wintypes.HANDLE) -> tuple[int, int, int] | None:
        creation, _exit, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
        if not self.kernel.GetThreadTimes(
            handle,
            ctypes.byref(creation),
            ctypes.byref(_exit),
            ctypes.byref(kernel),
            ctypes.byref(user),
        ):
            self.counter_failures += 1
            return None
        return _filetime_ticks(creation), _filetime_ticks(user), _filetime_ticks(kernel)

    def _thread_description(self, handle: wintypes.HANDLE) -> str | None:
        if self._get_thread_description is None:
            return None
        value = ctypes.c_wchar_p()
        result = self._get_thread_description(handle, ctypes.byref(value))
        try:
            # HRESULT uses its sign bit for failure. S_OK is zero, but
            # positive success values (for example S_FALSE) are still valid.
            if result < 0:
                self.thread_description_failures.append(f"0x{result & 0xFFFFFFFF:08x}")
                return None
            if not value.value:
                self.thread_description_empty += 1
                return None
            return value.value
        finally:
            if value:
                self.kernel.LocalFree(ctypes.cast(value, ctypes.c_void_p))

    def _thread_ids(self) -> list[int]:
        snapshot = self.kernel.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
        invalid = ctypes.c_void_p(-1).value
        if not snapshot or ctypes.cast(snapshot, ctypes.c_void_p).value == invalid:
            raise ctypes.WinError(ctypes.get_last_error())
        result: list[int] = []
        try:
            entry = THREADENTRY32()
            entry.dwSize = ctypes.sizeof(THREADENTRY32)
            more = self.kernel.Thread32First(snapshot, ctypes.byref(entry))
            while more:
                if int(entry.th32OwnerProcessID) == self.process_id:
                    result.append(int(entry.th32ThreadID))
                entry.dwSize = ctypes.sizeof(THREADENTRY32)
                more = self.kernel.Thread32Next(snapshot, ctypes.byref(entry))
        finally:
            self.kernel.CloseHandle(snapshot)
        return result

    def observe(self, *, baseline: bool, window_start_filetime: int) -> int:
        """Observe every currently listed thread; retain handles for final counters."""
        seen = 0
        for thread_id in self._thread_ids():
            handle = self.kernel.OpenThread(
                THREAD_QUERY_INFORMATION | THREAD_QUERY_LIMITED_INFORMATION,
                False,
                thread_id,
            )
            if not handle:
                self.thread_open_failures += 1
                continue
            times = self._thread_times(handle)
            if times is None:
                self.kernel.CloseHandle(handle)
                continue
            creation, user, kernel = times
            key = (thread_id, creation)
            state = self.states.get(key)
            cpu = (user, kernel)
            if state is None:
                name = self._thread_description(handle)
                if baseline:
                    start_cpu = cpu
                    baseline_kind = "sampled_at_window_start"
                elif creation >= window_start_filetime:
                    # Thread counters begin at zero when Windows creates the thread.
                    start_cpu = (0, 0)
                    baseline_kind = "created_during_window"
                else:
                    # It appeared between snapshots after the boundary; avoid
                    # attributing pre-observation CPU to the measured interval.
                    start_cpu = cpu
                    baseline_kind = "first_observed_after_window_start"
                self.states[key] = {
                    "thread_id": thread_id,
                    "creation_filetime": creation,
                    "name": name,
                    "start_user_ticks": start_cpu[0],
                    "start_kernel_ticks": start_cpu[1],
                    "end_user_ticks": user,
                    "end_kernel_ticks": kernel,
                    "baseline_kind": baseline_kind,
                    "handle": handle,
                }
            else:
                self.kernel.CloseHandle(handle)
                state["end_user_ticks"] = user
                state["end_kernel_ticks"] = kernel
            seen += 1
        return seen

    def finalize(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for state in self.states.values():
            times = self._thread_times(state["handle"])
            if times is not None:
                _creation, user, kernel = times
                state["end_user_ticks"] = user
                state["end_kernel_ticks"] = kernel
            user_delta = max(0, state["end_user_ticks"] - state["start_user_ticks"])
            kernel_delta = max(0, state["end_kernel_ticks"] - state["start_kernel_ticks"])
            rows.append(
                {
                    "thread_id": state["thread_id"],
                    "name": state["name"],
                    "name_source": "Windows GetThreadDescription" if state["name"] else None,
                    "creation_filetime_utc": state["creation_filetime"],
                    "baseline_kind": state["baseline_kind"],
                    "user_cpu_ms": user_delta / 10_000.0,
                    "kernel_cpu_ms": kernel_delta / 10_000.0,
                    "total_cpu_ms": (user_delta + kernel_delta) / 10_000.0,
                    "user_ticks_start": state["start_user_ticks"],
                    "kernel_ticks_start": state["start_kernel_ticks"],
                    "user_ticks_end": state["end_user_ticks"],
                    "kernel_ticks_end": state["end_kernel_ticks"],
                    "counter_delta_100ns": user_delta + kernel_delta,
                }
            )
            self.kernel.CloseHandle(state["handle"])
        rows.sort(key=lambda item: item["total_cpu_ms"], reverse=True)
        return rows


def _bind_process_times(kernel: Any) -> tuple[Any, Any, Any]:
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(FILETIME)] * 4
    kernel.GetProcessTimes.restype = wintypes.BOOL
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    return kernel.OpenProcess, kernel.GetProcessTimes, kernel.CloseHandle


def _open_process_handle(process_id: int) -> tuple[Any, Any, Any, Any, str | None]:
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    open_process, get_times, close_handle = _bind_process_times(kernel)
    handle = open_process(
        PROCESS_QUERY_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
        False,
        process_id,
    )
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    image_path: str | None = None
    query_image = getattr(kernel, "QueryFullProcessImageNameW", None)
    if query_image is not None:
        query_image.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.c_wchar_p, ctypes.POINTER(wintypes.DWORD)]
        query_image.restype = wintypes.BOOL
        buffer = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(buffer))
        if query_image(handle, 0, buffer, ctypes.byref(size)):
            image_path = buffer.value
    return kernel, handle, get_times, close_handle, image_path


def _process_is_running(kernel: Any, handle: Any) -> bool:
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.WaitForSingleObject.restype = wintypes.DWORD
    return kernel.WaitForSingleObject(handle, 0) == WAIT_TIMEOUT


def _process_cpu_ticks(get_times: Any, handle: Any) -> tuple[int, int, int]:
    creation, exit_time, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
    if not get_times(
        handle,
        ctypes.byref(creation),
        ctypes.byref(exit_time),
        ctypes.byref(kernel),
        ctypes.byref(user),
    ):
        raise ctypes.WinError(ctypes.get_last_error())
    return _filetime_ticks(creation), _filetime_ticks(user), _filetime_ticks(kernel)


def _host_details() -> dict[str, Any]:
    data: dict[str, Any] = {
        "platform": platform.platform(),
        "system": platform.system(),
        "release": platform.release(),
        "version": platform.version(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "logical_cpu_count": os.cpu_count(),
        "python": platform.python_version(),
    }
    if os.name == "nt":
        value = sys.getwindowsversion()
        data["windows_version"] = {
            "major": value.major,
            "minor": value.minor,
            "build": value.build,
            "platform": value.platform,
        }
    return data


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--probe", type=Path, default=DEFAULT_PROBE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Gameplay WAV/report prefix")
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument("--duration", type=float, default=20.0)
    parser.add_argument("--window-start", type=float, default=2.0)
    parser.add_argument("--window-end", type=float, default=18.0)
    parser.add_argument("--sample-period", type=float, default=0.25)
    parser.add_argument("--audio-driver", default="WASAPI")
    parser.add_argument("--audio-seed", type=int, default=4102026)
    parser.add_argument("--report", type=Path, default=REPORT_PATH)
    return parser.parse_args()


def _named_indices(rows: list[dict[str, Any]]) -> tuple[list[int], list[int]]:
    audio: list[int] = []
    main: list[int] = []
    for index, row in enumerate(rows):
        name = (row.get("name") or "").strip().lower()
        if re.search(r"audio|mixer|mix\s*thread", name):
            audio.append(index)
        if re.search(r"\bmain(?:\s+thread)?\b|godot\s+main", name):
            main.append(index)
    return audio, main


def _enrich_thread_metrics(rows: list[dict[str, Any]], wall_seconds: float) -> dict[str, Any]:
    for row in rows:
        row["mean_one_core_percent"] = _percent(row["total_cpu_ms"] / 1000.0, wall_seconds)
        row["mean_cpu_ms_per_10ms_reference_quantum"] = _quantum_cost_ms(
            row["total_cpu_ms"] / 1000.0, wall_seconds
        )
    audio_indices, main_indices = _named_indices(rows)
    identified_audio = [rows[i] for i in audio_indices]
    identified_main = [rows[i] for i in main_indices]
    audio_total = sum(row["total_cpu_ms"] for row in identified_audio)
    mix_cost = _quantum_cost_ms(audio_total / 1000.0, wall_seconds) if identified_audio else None
    main_total = sum(row["total_cpu_ms"] for row in identified_main)
    return {
        "thread_rows": rows,
        "mixer_thread_identification": {
            "status": "identified_by_thread_description" if identified_audio else "not_identified",
            "basis": "Only Windows thread descriptions containing audio, mixer, or mix thread are classified; CPU activity alone is never used to guess the mixer.",
            "identified_threads": [
                {"thread_id": row["thread_id"], "name": row["name"]} for row in identified_audio
            ],
            "combined_mean_cpu_ms_per_10ms_reference_quantum": mix_cost,
            "target_ms_per_10ms_reference_quantum": 1.0,
            "within_target_by_mean": mix_cost < 1.0 if mix_cost is not None else None,
            "sample_block_p95_ms": None,
            "sample_block_p95_status": "Not measurable here: GetThreadTimes deltas provide window-average CPU time, not per-mix-block timing samples.",
        },
        "main_thread_if_named": {
            "status": "identified_by_thread_description" if identified_main else "not_identified",
            "threads": [
                {
                    "thread_id": row["thread_id"],
                    "name": row["name"],
                    "total_cpu_ms": row["total_cpu_ms"],
                    "mean_one_core_percent": row["mean_one_core_percent"],
                }
                for row in identified_main
            ],
            "combined_total_cpu_ms": main_total if identified_main else None,
        },
    }


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def run_profile(args: argparse.Namespace) -> dict[str, Any]:
    if os.name != "nt":
        raise RuntimeError("This profiler requires Windows Toolhelp and GetThreadTimes APIs")
    if not (0.0 <= args.window_start < args.window_end < args.duration):
        raise ValueError("Require 0 <= window-start < window-end < duration")
    if args.fps <= 0 or args.sample_period <= 0.0:
        raise ValueError("fps and sample-period must be positive")

    godot = args.godot.resolve()
    app = args.app.resolve()
    probe = args.probe.resolve()
    out_prefix = args.out.resolve()
    report_path = args.report.resolve()
    for required, label in ((godot, "Godot executable"), (app / "project.godot", "app project"), (probe, "gameplay probe")):
        if not required.exists():
            raise FileNotFoundError(f"{label} not found: {required}")
    out_prefix.parent.mkdir(parents=True, exist_ok=True)
    stdout_path = Path(str(out_prefix) + ".stdout.log")
    stderr_path = Path(str(out_prefix) + ".stderr.log")
    capture_json_path = Path(str(out_prefix) + ".json")
    command = [
        str(godot),
        "--headless",
        "--audio-driver",
        args.audio_driver,
        "--path",
        str(app),
        "--script",
        str(probe),
        "--",
        f"--fps={args.fps}",
        f"--duration={args.duration:g}",
        "--soundscape=on",
        f"--audio-seed={args.audio_seed}",
        f"--out={out_prefix}",
    ]
    report: dict[str, Any] = {
        "format": "openrc-audio-native-profile-v1",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "host": _host_details(),
        "tool": {
            "python_stdlib_only": True,
            "cpu_counter_api": "Windows GetThreadTimes (100 ns user/kernel counters)",
            "thread_enumeration_api": "Windows Toolhelp32Snapshot/Thread32First/Thread32Next",
            "thread_name_api": "Windows GetThreadDescription when available",
        },
        "run": {
            "godot": str(godot),
            "app": str(app),
            "probe": str(probe),
            "audio_driver_requested": args.audio_driver,
            "fps_requested": args.fps,
            "audio_seed": args.audio_seed,
            "duration_requested_s": args.duration,
            "measurement_window_requested_s": [args.window_start, args.window_end],
            "sampling_period_requested_s": args.sample_period,
            "command": command,
            "stdout_log": str(stdout_path),
            "stderr_log": str(stderr_path),
            "gameplay_probe_json": str(capture_json_path),
        },
        "valid": False,
        "validity_notes": [],
    }
    process_kernel = None
    process_handle = None
    sampler: WinAudioThreadSampler | None = None
    rows: list[dict[str, Any]] = []
    start_process_cpu: tuple[int, int, int] | None = None
    end_process_cpu: tuple[int, int, int] | None = None
    wall_seconds = 0.0
    child: subprocess.Popen[bytes] | None = None
    launch_mono = time.monotonic()
    sample_offsets: list[float] = []
    with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
        child = subprocess.Popen(command, cwd=ROOT, stdout=stdout_file, stderr=stderr_file)
        report["run"]["launcher_process_id"] = child.pid
        try:
            launcher_kernel, launcher_handle, _launcher_times, close_launcher, launcher_image = _open_process_handle(child.pid)
            report["run"]["launcher_process_image_path"] = launcher_image
            close_launcher(launcher_handle)
            expected_engine_name = godot.name.replace("_console.exe", ".exe").casefold()
            engine_child, descendants = _find_engine_child(
                child.pid,
                godot,
                min(args.window_start, 3.0),
            )
            target_process_id = int(engine_child["process_id"]) if engine_child else child.pid
            target_selection = "sibling_engine_child" if engine_child else "launcher_fallback_no_matching_sibling"
            report["run"]["engine_child_executable_expected"] = expected_engine_name
            report["run"]["process_descendants_at_selection"] = descendants
            report["run"]["target_selection"] = target_selection
            report["run"]["process_id"] = target_process_id
            process_kernel, process_handle, get_process_times, close_process, process_image = _open_process_handle(target_process_id)
            report["run"]["process_image_path"] = process_image
            sampler = WinAudioThreadSampler(target_process_id)
            report["run"]["get_thread_description_available"] = sampler._get_thread_description is not None

            # Keep the requested profile window tied to launcher start even though
            # we first wait for the GUI/engine sibling to appear.
            until_window_start = launch_mono + args.window_start - time.monotonic()
            if until_window_start > 0.0:
                time.sleep(until_window_start)
            if not _process_is_running(process_kernel, process_handle):
                raise RuntimeError(f"Godot engine process {target_process_id} exited before measurement began")

            start_mono = time.monotonic()
            start_filetime = sampler.system_filetime()
            start_process_cpu = _process_cpu_ticks(get_process_times, process_handle)
            initial_threads = sampler.observe(baseline=True, window_start_filetime=start_filetime)
            samples = 1
            sample_offsets.append(time.monotonic() - launch_mono)
            profile_span = args.window_end - args.window_start
            next_sample = start_mono + min(args.sample_period, profile_span)
            while True:
                remaining = next_sample - time.monotonic()
                if remaining > 0.0:
                    time.sleep(remaining)
                now = time.monotonic()
                if now >= start_mono + profile_span:
                    break
                if not _process_is_running(process_kernel, process_handle):
                    raise RuntimeError(f"Godot engine process {target_process_id} exited during measurement")
                sampler.observe(baseline=False, window_start_filetime=start_filetime)
                samples += 1
                sample_offsets.append(time.monotonic() - launch_mono)
                next_sample += args.sample_period
                # Avoid a burst of catch-up snapshots if the host is briefly busy.
                if next_sample <= now:
                    next_sample = now + args.sample_period

            sampler.observe(baseline=False, window_start_filetime=start_filetime)
            sample_offsets.append(time.monotonic() - launch_mono)
            rows = sampler.finalize()
            end_process_cpu = _process_cpu_ticks(get_process_times, process_handle)
            end_mono = time.monotonic()
            wall_seconds = end_mono - start_mono
            if child.poll() is None:
                try:
                    exit_code = child.wait(timeout=max(5.0, args.duration - args.window_end + 30.0))
                except subprocess.TimeoutExpired:
                    child.terminate()
                    try:
                        exit_code = child.wait(timeout=5.0)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        exit_code = child.wait(timeout=5.0)
                    report["validity_notes"].append("Godot exceeded the post-window wait and was terminated.")
            else:
                exit_code = child.returncode
            report["run"]["engine_process_exited_after_capture"] = not _process_is_running(process_kernel, process_handle)
            report["run"]["exit_code"] = exit_code
        finally:
            if sampler is not None and not rows:
                rows = sampler.finalize()
            if process_handle:
                close_process(process_handle)
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5.0)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5.0)

    report["run"]["thread_samples"] = samples if "samples" in locals() else 0
    report["run"]["sample_offsets_from_launch_s"] = sample_offsets
    if len(sample_offsets) > 1:
        intervals = [sample_offsets[i] - sample_offsets[i - 1] for i in range(1, len(sample_offsets))]
        report["run"]["observed_sample_interval_s"] = {
            "mean": sum(intervals) / len(intervals),
            "min": min(intervals),
            "max": max(intervals),
        }
    report["run"]["thread_open_failures"] = sampler.thread_open_failures if sampler else None
    report["run"]["counter_failures"] = sampler.counter_failures if sampler else None
    report["run"]["thread_descriptions_empty"] = sampler.thread_description_empty if sampler else None
    report["run"]["thread_description_hresult_failures"] = sampler.thread_description_failures if sampler else None
    capture_report: dict[str, Any] | None = None
    if capture_json_path.is_file():
        try:
            capture_report = json.loads(capture_json_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as error:
            report["validity_notes"].append(f"Gameplay probe report could not be parsed: {error}")
    else:
        report["validity_notes"].append("Gameplay probe did not produce its JSON report.")
    report["gameplay_probe"] = capture_report

    process_delta: dict[str, float] | None = None
    if start_process_cpu is not None and end_process_cpu is not None and wall_seconds > 0.0:
        user_ms = max(0, end_process_cpu[1] - start_process_cpu[1]) / 10_000.0
        kernel_ms = max(0, end_process_cpu[2] - start_process_cpu[2]) / 10_000.0
        process_delta = {
            "creation_filetime_utc": start_process_cpu[0],
            "user_ticks_start": start_process_cpu[1],
            "kernel_ticks_start": start_process_cpu[2],
            "user_ticks_end": end_process_cpu[1],
            "kernel_ticks_end": end_process_cpu[2],
            "user_cpu_ms": user_ms,
            "kernel_cpu_ms": kernel_ms,
            "total_cpu_ms": user_ms + kernel_ms,
            "mean_one_core_percent": _percent((user_ms + kernel_ms) / 1000.0, wall_seconds),
            "mean_cpu_ms_per_10ms_reference_quantum": _quantum_cost_ms(
                (user_ms + kernel_ms) / 1000.0, wall_seconds
            ),
        }
    enriched = _enrich_thread_metrics(rows, wall_seconds) if wall_seconds > 0.0 else {
        "thread_rows": rows,
        "mixer_thread_identification": {
            "status": "not_identified",
            "basis": "No valid CPU measurement window was captured.",
            "identified_threads": [],
            "combined_mean_cpu_ms_per_10ms_reference_quantum": None,
            "target_ms_per_10ms_reference_quantum": 1.0,
            "within_target_by_mean": None,
            "sample_block_p95_ms": None,
            "sample_block_p95_status": "Not measurable from thread counter snapshots.",
        },
        "main_thread_if_named": {"status": "not_identified", "threads": [], "combined_total_cpu_ms": None},
    }
    report["measurement"] = {
        "window_requested_s_from_process_launch": [args.window_start, args.window_end],
        "first_and_last_snapshot_offsets_from_launch_s": [sample_offsets[0], sample_offsets[-1]] if sample_offsets else None,
        "wall_interval_s": wall_seconds if wall_seconds > 0.0 else None,
        "window_method": "Baseline at launch+window-start; periodic GetThreadTimes snapshots through launch+window-end; final counters captured at the end boundary.",
        "sampling_period_requested_s": args.sample_period,
            "shared_host_contention_note": "Other non-audio full-suite tasks were present on the shared host. GetThreadTimes measures this child process CPU only, but host contention can change scheduling; no deadline or per-block inference is made.",
        "process_cpu": process_delta,
        "threads": enriched["thread_rows"],
        "mixer_thread_identification": enriched["mixer_thread_identification"],
        "main_thread_if_named": enriched["main_thread_if_named"],
        "mean_only_limitation": "CPU deltas are averaged over the measured wall interval. They do not measure per-audio-block execution time, deadline misses, or p95 block cost.",
    }

    capture_valid = bool(
        capture_report
        and report.get("run", {}).get("exit_code") == 0
        and str(capture_report.get("driver", "")).casefold() == args.audio_driver.casefold()
        and capture_report.get("display") == "headless"
        and capture_report.get("requested_fps") == args.fps
        and capture_report.get("wav_saved") is True
        and capture_report.get("discarded_frames") == 0
        and float(capture_report.get("captured_seconds", 0.0)) >= args.duration - 0.25
        and wall_seconds >= (args.window_end - args.window_start) * 0.98
    )
    engine_target_valid = report.get("run", {}).get("target_selection") == "sibling_engine_child"
    cpu_counters_nonzero = bool(
        (process_delta is not None and process_delta["total_cpu_ms"] > 0.0)
        or any(row["total_cpu_ms"] > 0.0 for row in enriched["thread_rows"])
    )
    report["capture_valid"] = capture_valid
    report["engine_target_valid"] = engine_target_valid
    report["cpu_counters_nonzero"] = cpu_counters_nonzero
    report["valid"] = capture_valid and engine_target_valid and cpu_counters_nonzero
    if not capture_valid:
        report["validity_notes"].append(
            "Capture acceptance requires successful exit, the requested audio driver, headless display, requested FPS, a saved WAV, zero discarded frames, the requested capture duration, and a complete CPU window."
        )
    if not cpu_counters_nonzero:
        report["validity_notes"].append(
            "All sampled process/thread CPU deltas were zero; this capture is not accepted as a native CPU profile."
        )
    if not engine_target_valid:
        report["validity_notes"].append(
            "The profiler did not find the expected non-console Godot sibling process and therefore only sampled the launcher; no engine CPU conclusion is accepted."
        )
    if report["measurement"]["mixer_thread_identification"]["status"] == "not_identified":
        report["validity_notes"].append(
            "Mixer thread was not positively identified by its Windows thread description; no mixer CPU-budget conclusion is made."
        )
    return report


def main() -> int:
    args = _parse_args()
    try:
        result = run_profile(args)
    except Exception as error:  # A failure report preserves the reason and invocation.
        result = {
            "format": "openrc-audio-native-profile-v1",
            "generated_utc": datetime.now(timezone.utc).isoformat(),
            "host": _host_details(),
            "valid": False,
            "error": f"{type(error).__name__}: {error}",
            "validity_notes": ["Native profiling did not complete."],
        }
        print(result["error"], file=sys.stderr)
    report_path = args.report.resolve()
    _write_json(report_path, result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("valid") else 1


if __name__ == "__main__":
    raise SystemExit(main())
