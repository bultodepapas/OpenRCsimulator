#!/usr/bin/env python3
"""Collect bounded, serial-free Mac inventory for a later native test session.

This does not install software, benchmark, select a renderer, qualify a GPU or
run the exported application. macOS command output is filtered before writing.
"""
from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import stat
import subprocess
import threading
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "tmp" / "macos-preflight"
MAX_ENGINE_BYTES = 512 * 1024 * 1024
MAX_OUTPUT_BYTES = 1024 * 1024
TOTAL_SECONDS = 55.0
MAX_GPUS = 16
MAX_DISPLAYS = 32
TOOLS = ("python3", "git", "shasum", "unzip", "file", "codesign", "spctl",
         "xcrun", "xcode-select", "xcodebuild", "clang", "instruments")


@dataclass
class Outcome:
    text: str | None
    reason: str | None
    exit_code: int | None


def bounded_command(command: list[str], *, timeout: float, max_bytes: int) -> Outcome:
    """Run a read-only command with bounded time/output and no retained raw logs."""
    try:
        child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, start_new_session=os.name != "nt")
    except OSError:
        return Outcome(None, "launch_failed", None)
    buffer = bytearray()
    overflow = threading.Event()
    read_failed = threading.Event()

    def read_output() -> None:
        try:
            while block := child.stdout.read1(65536):
                remaining = max_bytes - len(buffer)
                buffer.extend(block[:remaining])
                if len(block) > remaining:
                    overflow.set()
                    break
        except (OSError, ValueError):
            read_failed.set()
        finally:
            try:
                child.stdout.close()
            except OSError:
                read_failed.set()

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout
    reason = None
    while child.poll() is None or reader.is_alive():
        if overflow.is_set():
            reason = "output_limit"
            break
        if read_failed.is_set():
            reason = "read_failed"
            break
        if time.monotonic() >= deadline:
            reason = "timeout"
            break
        time.sleep(0.02)
    if reason:
        try:
            if os.name == "nt":
                child.kill()
            else:
                os.killpg(child.pid, signal.SIGKILL)
        except (OSError, ProcessLookupError):
            pass
    try:
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        reason = reason or "termination_failed"
    reader.join(timeout=1)
    if reader.is_alive():
        reason = reason or "pipe_incomplete"
    if overflow.is_set():
        reason = "output_limit"
    if read_failed.is_set():
        reason = reason or "read_failed"
    if reason:
        return Outcome(None, reason, child.poll())
    if child.returncode != 0:
        return Outcome(None, "nonzero_exit", child.returncode)
    try:
        return Outcome(buffer.decode("utf-8"), None, child.returncode)
    except UnicodeDecodeError:
        return Outcome(None, "invalid_utf8", child.returncode)


def process_translation() -> tuple[bool | None, str | None]:
    """Ask sysctl in this process: a separate sysctl executable has its own state."""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        func = libc.sysctlbyname
        func.argtypes = (ctypes.c_char_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t),
                         ctypes.c_void_p, ctypes.c_size_t)
        func.restype = ctypes.c_int
        value = ctypes.c_int()
        length = ctypes.c_size_t(ctypes.sizeof(value))
        if func(b"sysctl.proc_translated", ctypes.byref(value), ctypes.byref(length), None, 0) != 0:
            return None, "sysctl_unavailable"
        if length.value != ctypes.sizeof(value) or value.value not in (0, 1):
            return None, "invalid_translation_value"
        return bool(value.value), None
    except (AttributeError, OSError):
        return None, "sysctl_unavailable"


def clean_text(value: object, *, limit: int = 128) -> str | None:
    if not isinstance(value, str):
        return None
    value = value.strip()
    if not value or len(value) > limit or "serial" in value.lower() or any(ord(c) < 32 for c in value):
        return None
    return value


def parse_profile(raw: str) -> tuple[list[dict], bool]:
    """Keep GPU labels and display dimensions only; never retain profiler JSON."""
    data = json.loads(raw)
    if not isinstance(data, dict) or not isinstance(data.get("SPDisplaysDataType"), list):
        raise ValueError("missing display inventory")
    source_gpus = data["SPDisplaysDataType"]
    gpus = []
    truncated = len(source_gpus) > MAX_GPUS
    display_count = 0
    for gpu in source_gpus[:MAX_GPUS]:
        if not isinstance(gpu, dict):
            raise ValueError("invalid GPU entry")
        displays = gpu.get("spdisplays_ndrvs", [])
        if not isinstance(displays, list):
            raise ValueError("invalid display entries")
        output_displays = []
        for display in displays:
            if display_count >= MAX_DISPLAYS:
                truncated = True
                break
            if not isinstance(display, dict):
                raise ValueError("invalid display entry")
            display_count += 1
            resolution_key = ("_spdisplays_resolution" if display.get("_spdisplays_resolution")
                              else "spdisplays_resolution")
            raw_resolution = display.get(resolution_key)
            match = re.search(r"\b(\d{2,5})\s*[x×]\s*(\d{2,5})\b", raw_resolution) if isinstance(raw_resolution, str) else None
            raw_main = display.get("spdisplays_main")
            main = True if raw_main in ("spdisplays_yes", "yes", True) else False if raw_main in ("spdisplays_no", "no", False) else None
            raw_connection = display.get("spdisplays_connection_type")
            connection = raw_connection if raw_connection in ("spdisplays_internal", "spdisplays_external", "internal", "external") else None
            output_displays.append({"reported_dimensions": [int(match.group(1)), int(match.group(2))] if match else None,
                                    "resolution_source": resolution_key if match else None,
                                    "main": main, "connection": connection})
        gpus.append({"model": clean_text(gpu.get("sppci_model")) or clean_text(gpu.get("_name")),
                     "metal_reported": clean_text(gpu.get("spdisplays_metal")), "displays": output_displays})
    return gpus, truncated


def hash_file(path: Path, deadline: float) -> tuple[dict | None, str | None, tuple | None]:
    """Hash a bounded regular file; reject changes observed during the read."""
    try:
        # Opening a FIFO must not block the collector. Only regular files are
        # admitted after opening and checking the file descriptor itself.
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= MAX_ENGINE_BYTES:
                return None, "invalid_engine_file", None
            sha256, sha512 = hashlib.sha256(), hashlib.sha512()
            count = 0
            while True:
                if time.monotonic() >= deadline:
                    return None, "hash_timeout", None
                block = stream.read(1024 * 1024)
                if not block:
                    break
                count += len(block)
                if count > MAX_ENGINE_BYTES:
                    return None, "engine_size_limit", None
                sha256.update(block)
                sha512.update(block)
            after = os.fstat(stream.fileno())
            if (count != before.st_size or before.st_size != after.st_size or
                    before.st_mtime_ns != after.st_mtime_ns or before.st_ino != after.st_ino):
                return None, "engine_changed", None
            stamp = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
            return {"size_bytes": count, "sha256": sha256.hexdigest(), "sha512": sha512.hexdigest()}, None, stamp
    except OSError:
        return None, "engine_unreadable", None


def collect(godot: Path) -> dict:
    deadline = time.monotonic() + TOTAL_SECONDS
    issues: list[str] = []

    def query(name: str, args: list[str], *, seconds: float = 5, max_bytes: int = 4096,
              required: bool = True) -> str | None:
        remaining = deadline - time.monotonic()
        result = (bounded_command(args, timeout=min(seconds, remaining), max_bytes=max_bytes)
                  if remaining > 0 else Outcome(None, "budget_exhausted", None))
        if result.reason and required:
            issues.append(name + ":" + result.reason)
        return result.text

    host_arch = clean_text(platform.machine())
    if host_arch is None:
        issues.append("process_architecture:unavailable")
    translated, translation_issue = process_translation()
    if translation_issue:
        issues.append("process_translation:" + translation_issue)
    arm_raw = query("hardware_arm64", ["/usr/sbin/sysctl", "-n", "hw.optional.arm64"])
    hardware_arm64 = {"0": False, "1": True}.get(arm_raw.strip()) if arm_raw else None
    if hardware_arm64 is None:
        issues.append("hardware_arm64:invalid_or_unavailable")
    native_arm64 = None if translated is None or host_arch is None else (host_arch in ("arm64", "aarch64") and not translated)
    model = clean_text(query("model", ["/usr/sbin/sysctl", "-n", "hw.model"]))
    if model is None:
        issues.append("model:invalid_or_unavailable")
    memory_raw = query("memory", ["/usr/sbin/sysctl", "-n", "hw.memsize"])
    memory_bytes = int(memory_raw.strip()) if memory_raw and memory_raw.strip().isdigit() else None
    if memory_bytes is None or not 0 < memory_bytes < 2**60:
        memory_bytes = None
        issues.append("memory:invalid_value")
    os_version = clean_text(query("os_version", ["/usr/bin/sw_vers", "-productVersion"]))
    os_build = clean_text(query("os_build", ["/usr/bin/sw_vers", "-buildVersion"]))
    if os_version is None or os_build is None:
        issues.append("os:invalid_or_unavailable")
    cpu = clean_text(query("cpu", ["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"], required=False))
    profile = query("displays", ["/usr/sbin/system_profiler", "SPDisplaysDataType", "-json", "-detailLevel", "basic"],
                    seconds=15, max_bytes=MAX_OUTPUT_BYTES)
    gpus: list[dict] = []
    truncated = False
    if profile is not None:
        try:
            gpus, truncated = parse_profile(profile)
            if truncated:
                issues.append("displays:entry_limit")
        except (ValueError, RecursionError):
            issues.append("displays:invalid_json")
    if not gpus or not any(gpu["model"] for gpu in gpus):
        issues.append("displays:no_gpu_data")

    engine_path = godot.expanduser().absolute()
    engine_hash, hash_issue, file_stamp = hash_file(engine_path, deadline)
    if hash_issue:
        issues.append("engine:" + hash_issue)
    engine = {"path": str(engine_path), "identity": engine_hash, "version": None,
              "file_architectures": [], "normal_launch_native_arm64": None,
              "forced_arm64_version_succeeded": None, "identity_stable_across_version_checks": None}
    if engine_hash is not None:
        description = query("engine_file", ["/usr/bin/file", "-b", str(engine_path)])
        if description and "Mach-O" in description:
            engine["file_architectures"] = sorted(set(re.findall(r"\b(?:arm64|x86_64)\b", description)))
        if not engine["file_architectures"]:
            issues.append("engine:architecture_unknown")
        version_raw = query("engine_version", [str(engine_path), "--version"], seconds=10)
        version = clean_text(version_raw, limit=128)
        if version and re.fullmatch(r"[A-Za-z0-9._+\-]+", version):
            engine["version"] = version
        else:
            issues.append("engine:version_invalid")
        if hardware_arm64 is True and "arm64" in engine["file_architectures"]:
            forced = query("engine_forced_arm64", ["/usr/bin/arch", "-arm64", str(engine_path), "--version"],
                           seconds=10, required=False)
            if forced is not None and version is not None:
                engine["forced_arm64_version_succeeded"] = forced.strip() == version
        try:
            current = engine_path.stat()
            current_stamp = (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns)
            engine["identity_stable_across_version_checks"] = stat.S_ISREG(current.st_mode) and current_stamp == file_stamp
        except OSError:
            engine["identity_stable_across_version_checks"] = False
        if not engine["identity_stable_across_version_checks"]:
            issues.append("engine:changed_after_hash")

    selected_xcode = clean_text(query("xcode_selection", ["/usr/bin/xcode-select", "-p"], required=False), limit=512)
    report = {
        "format": "openrc-macos-preflight-v1", "captured_utc": datetime.now(timezone.utc).isoformat(),
        "collection": {"complete": not issues, "issues": issues, "time_budget_seconds": TOTAL_SECONDS,
                       "command_output_limit_bytes": MAX_OUTPUT_BYTES,
                       "display_resolution_note": "System-reported dimensions; drawable and render pixels are unverified.",
                       "qualification": "inventory only; no renderer, GPU performance, package or physical qualification"},
        "host": {"model_identifier": model, "cpu": cpu, "memory_bytes": memory_bytes,
                 "os_version": os_version, "os_build": os_build, "hardware_arm64": hardware_arm64,
                 "python_process_architecture": host_arch, "python_process_rosetta": translated,
                 "python_process_native_arm64": native_arm64},
        "gpus": gpus, "display_entries_truncated": truncated, "engine": engine,
        "tooling": {"path_found": {tool: shutil.which(tool) for tool in TOOLS},
                    "xcode_selection": selected_xcode, "python_version": platform.python_version(),
                    "note": "Paths indicate discovery, not verified tool or SDK functionality."},
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, help="native editor executable returned by app/get-godot.sh")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT, help="parent for a new uniquely named JSON receipt")
    parser.add_argument("--dry-run", action="store_true", help="show collection scope without reading host or writing files")
    args = parser.parse_args()
    if args.dry_run:
        print(json.dumps({"collection_started": False, "requires": "Darwin and --godot",
                          "collects": ["model and memory", "OS and process architecture", "filtered GPU/display data",
                                       "engine path/hash/version", "tool paths"],
                          "serial_numbers": "discarded from system output in memory; never written",
                          "output_directory": str(args.out_dir)}))
        return 0
    if platform.system() != "Darwin":
        parser.exit(2, "macOS preflight collection requires a native Darwin host; use --dry-run for scope.\n")
    if args.godot is None:
        parser.error("--godot is required for collection")
    report = collect(args.godot)
    try:
        args.out_dir.mkdir(parents=True, exist_ok=True)
        output = args.out_dir / ("macos-preflight-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex + ".json")
        with output.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=True)
            stream.write("\n")
    except OSError as error:
        parser.exit(2, "Could not write new preflight receipt: " + str(error) + "\n")
    print(output)
    return 0 if report["collection"]["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
