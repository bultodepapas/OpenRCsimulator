#!/usr/bin/env python3
"""Disposable macOS sanitizers for the existing native-kernel translation unit.

The exact candidate build and official Godot remain untouched.  The selected
sanitizer instruments nk_kernel.cpp and code inlined into it; the prebuilt
godot-cpp archive and Godot executable are not instrumented.  A separate mutant
must trigger the detector through the real Godot late loader before any clean
oracle is credited.  Results are diagnostics, never installable evidence.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import subprocess
import sys
import uuid
from xml.parsers.expat import ExpatError

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FORMAT = "openrc-nk3-macos-sanitizer-diagnostic v1"
OFFICIAL_TEAM = "6K46PWY5DM"
SIGNATURE = re.compile(r"AddressSanitizer|UndefinedBehaviorSanitizer|LeakSanitizer|runtime error:", re.I)
CONTROL_MARKER = "OPENRC_MAC_SANITIZER_CONTROL"
SCRIPT_COMPONENTS = {
    "oracle.gd": ("openrc-nk3-oracle v1", "math_shim"),
    "stage_oracle.gd": ("openrc-nk3-stage-oracle v1", "stage_bytes"),
    "propeller_oracle.gd": ("openrc-nk3-propeller-oracle v1", "propeller_thrust_torque"),
    "electric_oracle.gd": ("openrc-nk3-electric-oracle v1", "electric_values"),
    "liquid_oracle.gd": ("openrc-nk3-liquid-oracle v1", "liquid_gas_laws"),
    "glow_oracle.gd": ("openrc-nk3-glow-oracle v1", "glow_source_values"),
}
DEFAULT_SCRIPTS = ("oracle.gd", "stage_oracle.gd", "propeller_oracle.gd")
DOMAIN_GUARD_SCRIPT = "test_macos_domain_guard.gd"
DOMAIN_GUARD_PROFILE_SCOPE = "isolated guard-call loop only; not inclusive tick or product performance"
DOMAIN_GUARD_KINDS = frozenset(("byte", "int32", "int64", "float32", "float64"))


def _arm64_text_identity(path: Path) -> dict:
    """Hash the executable's actual ARM64 __TEXT,__text, excluding its signature."""
    with path.open("rb") as stream:
        size = os.fstat(stream.fileno()).st_size
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError("Truncated diagnostic host Mach-O header")
        magic, cpu, subtype, kind, count, commands_size, _flags, _reserved = struct.unpack("<IiiIIIII", header)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 2:
            raise ValueError("Diagnostic host must be a thin ARM64 Mach-O executable")
        if not 0 < count <= 4096 or not 0 < commands_size <= 16 * 1024 * 1024 or 32 + commands_size > size:
            raise ValueError("Invalid diagnostic host Mach-O command table")
        commands = stream.read(commands_size)
        position = 0
        identity_uuid = None
        text_section = None
        for _ in range(count):
            if position + 8 > len(commands):
                raise ValueError("Truncated diagnostic host Mach-O command")
            command, command_size = struct.unpack_from("<II", commands, position)
            if command_size < 8 or position + command_size > len(commands):
                raise ValueError("Invalid diagnostic host Mach-O command size")
            if command == 0x1B:  # LC_UUID
                if command_size != 24 or identity_uuid is not None:
                    raise ValueError("Invalid or duplicate diagnostic host UUID")
                identity_uuid = str(uuid.UUID(bytes=commands[position + 8:position + 24])).upper()
            elif command == 0x19:  # LC_SEGMENT_64
                if command_size < 72:
                    raise ValueError("Truncated diagnostic host segment")
                segment = struct.unpack_from("<II16sQQQQIIII", commands, position)
                segment_name = segment[2].split(b"\0", 1)[0]
                file_offset, file_size, section_count = segment[5], segment[6], segment[9]
                if section_count > (command_size - 72) // 80 or file_offset + file_size > size:
                    raise ValueError("Invalid diagnostic host segment bounds")
                for index in range(section_count):
                    section = struct.unpack_from("<16s16sQQIIIIIIII", commands, position + 72 + index * 80)
                    section_name, owner = (part.split(b"\0", 1)[0] for part in section[:2])
                    if segment_name == b"__TEXT" and owner == b"__TEXT" and section_name == b"__text":
                        address, length, offset = section[2], section[3], section[4]
                        if (text_section is not None or not length or offset < file_offset
                                or offset + length > file_offset + file_size or offset + length > size):
                            raise ValueError("Invalid or duplicate diagnostic host text section")
                        text_section = (address, length, offset)
            position += command_size
        if position != len(commands) or identity_uuid is None or text_section is None:
            raise ValueError("Diagnostic host UUID or text section is missing")
        address, length, offset = text_section
        stream.seek(offset)
        digest = hashlib.sha256()
        remaining = length
        while remaining:
            chunk = stream.read(min(remaining, 1024 * 1024))
            if not chunk:
                raise ValueError("Truncated diagnostic host text section")
            digest.update(chunk)
            remaining -= len(chunk)
    return {"architecture": "arm64", "cpu_subtype": subtype, "uuid": identity_uuid,
            "text_address": address, "text_bytes": length, "text_sha256": digest.hexdigest()}


def _diagnostic_signature(path: Path, env: dict[str, str]) -> dict:
    """Verify and record the clone's actual ad-hoc, non-hardened signature."""
    verify = ["codesign", "--verify", "--strict", "--arch", "arm64", str(path)]
    display = ["codesign", "--display", "--verbose=4", "--arch", "arm64", str(path)]
    entitlements = ["codesign", "--display", "--entitlements", "-", "--xml", "--arch", "arm64", str(path)]
    subprocess.run(verify, check=True, capture_output=True, env=env)
    detail = subprocess.run(display, check=True, capture_output=True, text=True, env=env).stderr
    if len(detail) > 1024 * 1024:
        raise ValueError("Oversized diagnostic host signature output")
    flags = re.findall(r"^CodeDirectory\b.*\bflags=(0x[0-9a-fA-F]+)\b", detail, re.MULTILINE)
    lines = detail.splitlines()
    teams = [line.split("=", 1)[1] for line in lines if line.startswith("TeamIdentifier=")]
    if (len(flags) != 1 or not int(flags[0], 16) & 0x2 or int(flags[0], 16) & 0x10000
            or "Signature=adhoc" not in lines or teams not in ([], ["not set"])
            or any(line.startswith("Authority=") for line in lines)):
        raise ValueError("Diagnostic host must be ad-hoc signed without hardened runtime")
    observed = subprocess.run(entitlements, check=True, capture_output=True, env=env)
    if len(observed.stdout) > 1024 * 1024 or len(observed.stderr) > 1024 * 1024:
        raise ValueError("Oversized diagnostic host entitlements")
    try:
        xml = observed.stdout.decode("utf-8")
        if xml.strip() and not isinstance(plistlib.loads(observed.stdout), dict):
            raise ValueError("Entitlements are not a dictionary")
        diagnostics = observed.stderr.decode("utf-8")
    except (UnicodeDecodeError, plistlib.InvalidFileException, ExpatError, ValueError, TypeError, OverflowError) as error:
        raise ValueError("Invalid diagnostic host entitlement output") from error
    return {"flags": flags[0], "details": detail.strip(), "entitlements_xml": xml,
            "entitlements_sha256": hashlib.sha256(observed.stdout).hexdigest(),
            "entitlement_diagnostics": diagnostics.strip(),
            "verify_command": verify, "display_command": display, "entitlements_command": entitlements}


def _diagnostic_host(original: Path, clone: Path, mac, lock: dict, env: dict[str, str],
                     tmp: Path, forbidden: tuple[Path, ...]) -> dict:
    raw = clone.expanduser()
    if raw.is_symlink() or not raw.is_file() or not stat.S_ISREG(raw.stat().st_mode):
        raise ValueError("Diagnostic host must be a regular non-symlink file")
    host = raw.resolve()
    if (not host.is_relative_to(tmp) or host == original.resolve() or os.path.samefile(host, original)
            or any(host.is_relative_to(path) for path in forbidden)):
        raise ValueError("Diagnostic host must be a separate task-owned tmp/ executable")
    source_code = _arm64_text_identity(original)
    clone_code = _arm64_text_identity(host)
    if source_code != clone_code:
        raise ValueError("Diagnostic host ARM64 UUID or text differs from official Godot")
    signing = _diagnostic_signature(host, env)
    engine = mac.godot_identity(host, lock)
    return {"scope": "resigned diagnostic clone; not official-host or installable evidence",
            "engine": engine, "official_code": source_code, "diagnostic_code": clone_code,
            "signing": signing}


def sanitizer_flags(mode: str) -> tuple[str, ...]:
    if mode not in ("ubsan", "asan"):
        raise ValueError("Unsupported sanitizer mode")
    kind = "undefined" if mode == "ubsan" else "address"
    return (f"-fsanitize={kind}", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer")


def sanitizer_compile_flags(mode: str, *, control: bool = False) -> tuple[str, ...]:
    """Declare exactly the sanitizer instrumentation active in this translation unit."""
    flags = [*sanitizer_flags(mode), "-DUBSAN_ENABLED" if mode == "ubsan" else "-DASAN_ENABLED"]
    if control:
        flags.append("-DOPENRC_MAC_SANITIZER_CONTROL=1")
        if mode == "asan":
            flags.append("-DOPENRC_MAC_SANITIZER_ASAN=1")
    return tuple(flags)


def control_source(source: str, mode: str) -> str:
    """Place the positive fault only in a private copy of the existing TU."""
    sanitizer_flags(mode)
    header = "#include <cstdint>\n"
    anchor = '\t\t__asm__ __volatile__("mrs %0, fpcr" : "=r"(fpcr) : : "memory");\n'
    if source.count(header) != 1 or source.count(anchor) != 1:
        raise ValueError("Expected unique header and FPCR observation anchors")
    fault = r'''#if defined(OPENRC_MAC_SANITIZER_CONTROL)
		std::fputs("OPENRC_MAC_SANITIZER_CONTROL mode=''' + mode + r'''\n", stderr);
		std::fflush(stderr);
#if defined(OPENRC_MAC_SANITIZER_ASAN)
		volatile int index = 1;
		volatile int *values = new int[1];
		values[index] = 42;
		delete[] values;
#else
		volatile int value = INT_MAX;
		volatile int result = value + 1;
		(void)result;
#endif
#endif
'''
    return source.replace(header, header + "#include <climits>\n#include <cstdio>\n", 1).replace(anchor, anchor + fault, 1)


def detected_control(mode: str, report: dict, log: str, source: Path, library: Path) -> bool:
    marker = f"{CONTROL_MARKER} mode={mode}"
    before, found, after = log.partition(marker)
    del before
    expected = "signed integer overflow" if mode == "ubsan" else "heap-buffer-overflow"
    signature = "runtime error:" if mode == "ubsan" else "AddressSanitizer"
    origin = str(source) in after or source.name in after or library.name in after
    return bool(found and expected in after and signature in after and origin
                and report.get("complete") is True and report.get("reason") == "process_exit"
                and type(report.get("process_exit")) is int and report["process_exit"] != 0)


def oracle_error(script: str, data: dict, report: dict, log: str, seed: int, states: int) -> str:
    expected_format, component = SCRIPT_COMPONENTS[script]
    if (report.get("ok") is not True or report.get("complete") is not True
            or report.get("reason") != "passed" or report.get("process_exit") != 0
            or report.get("counts", {}).get("error") != 0 or report.get("missing_required_text") != []
            or SIGNATURE.search(log)):
        return "checked execution failed or emitted a sanitizer diagnostic"
    if (data.get("format") != expected_format or data.get("verdict") != "pass"
            or data.get("failures") != [] or data.get("seed") != seed or data.get("states") != states
            or data.get("self_test", {}).get("passed") is not True
            or data.get("identity", {}).get("backend") != "native"):
        return "oracle identity, arguments or verdict differ"
    components = data.get("components")
    if not isinstance(components, dict) or component not in components:
        return "the intended native component was not exercised"
    total = 0
    for row in components.values():
        if (not isinstance(row, dict) or type(row.get("count")) is not int or row["count"] <= 0
                or type(row.get("identical")) is not int or row["identical"] != row["count"]):
            return "oracle comparison counts are missing or unequal"
        total += row["count"]
    if data.get("total") != {"compared": total, "identical": total, "mismatched": 0}:
        return "oracle total does not match its components"
    if script == "oracle.gd":
        if (data.get("macos_boundary", {}).get("control_unchanged") is not True
                or data.get("coverage", {}).get("macos_fpcr", {}).get("observations") != 14
                or components["math_shim"]["count"] < 14 * (27 * 27 + 20000)
                or components.get("literals", {}).get("count", 0) < 100):
            return "base-oracle Mac boundary checks did not complete"
    if script == "stage_oracle.gd":
        coverage = data.get("coverage", {})
        rows = [coverage.get(name, {}) for name in ("stage_air", "stage_ground", "stage_hull")]
        counts = [row.get("states", 0) for row in rows]
        if any(type(count) is not int or count < 0 for count in counts) or sum(counts) != states:
            return "stage oracle did not exercise the requested state count"
    return ""


def domain_guard_result(report: dict, log: str) -> dict:
    """Validate the real guard harness, including its controls and stock-world profile."""
    if (report.get("ok") is not True or report.get("complete") is not True
            or report.get("reason") != "passed" or report.get("process_exit") != 0
            or report.get("counts", {}).get("error") != 0 or report.get("missing_required_text") != []
            or SIGNATURE.search(log)):
        raise ValueError("checked domain-guard execution failed or emitted a sanitizer diagnostic")
    lines = log.splitlines()
    verdicts = [line for line in lines if line.startswith("MACOS_DOMAIN_GUARD ")]
    if len(verdicts) != 1 or any(line.startswith("FAIL ") for line in lines):
        raise ValueError("domain-guard verdict is missing, duplicated or contains failures")
    match = re.fullmatch(r"MACOS_DOMAIN_GUARD verdict=pass checks=(\d+)", verdicts[0])
    if match is None or int(match.group(1)) < 72:
        raise ValueError("domain-guard harness did not pass at least 72 checks")

    def object_for(line: str, prefix: str) -> dict:
        def unique(pairs: list[tuple[str, object]]) -> dict:
            value = {}
            for key, item in pairs:
                if key in value:
                    raise ValueError("domain-guard control has duplicate JSON keys")
                value[key] = item
            return value

        def invalid_constant(_value: str) -> None:
            raise ValueError("domain-guard control has non-finite JSON")

        value = json.loads(line[len(prefix):], object_pairs_hook=unique, parse_constant=invalid_constant)
        if not isinstance(value, dict):
            raise ValueError("domain-guard control is not an object")
        return value

    resize_prefix = "MACOS_DOMAIN_RESIZE "
    resize_lines = [line for line in lines if line.startswith(resize_prefix)]
    resize = [object_for(line, resize_prefix) for line in resize_lines]
    if (len(resize) != len(DOMAIN_GUARD_KINDS)
            or any(type(row.get("kind")) is not str or row.get("alias_resized") is not True
                   or row.get("live_changed") is not True for row in resize)
            or {row["kind"] for row in resize} != DOMAIN_GUARD_KINDS):
        raise ValueError("domain-guard packed resize controls are missing, duplicated or did not mutate the live leaf")
    direct_prefix = "MACOS_DOMAIN_DIRECT_RESIZE "
    direct_lines = [line for line in lines if line.startswith(direct_prefix)]
    if len(direct_lines) != 1:
        raise ValueError("domain-guard direct resize control is missing or duplicated")
    direct = object_for(direct_lines[0], direct_prefix)
    if direct.get("live_changed") is not True or type(direct.get("size")) is not int or direct["size"] != 1024:
        raise ValueError("domain-guard direct resize control did not resize the live leaf")

    profile_prefix = "MACOS_DOMAIN_STOCK_GUARD_DIAGNOSTIC "
    profiles = [line for line in lines if line.startswith(profile_prefix)]
    if len(profiles) != 1:
        raise ValueError("domain-guard stock profile is missing or duplicated")
    profile = object_for(profiles[0], profile_prefix)
    if (profile.get("scope") != DOMAIN_GUARD_PROFILE_SCOPE or profile.get("all_match") is not True
            or type(profile.get("warmup_calls")) is not int or profile["warmup_calls"] != 16
            or type(profile.get("calls")) is not int or profile["calls"] != 2400
            or type(profile.get("proxies")) is not int or profile["proxies"] != 6092
            or any(type(profile.get(key)) is not int or profile[key] <= 0
                   for key in ("nodes", "packed_leaves", "packed_bytes"))
            or type(profile.get("elapsed_usec")) is not int or not 0 <= profile["elapsed_usec"] <= 2**53
            or type(profile.get("mean_usec")) not in (int, float)
            or (type(profile["mean_usec"]) is int and abs(profile["mean_usec"]) > 2**53)
            or not math.isfinite(profile["mean_usec"]) or profile["mean_usec"] < 0
            or not math.isclose(profile["mean_usec"], profile["elapsed_usec"] / 2400.0, rel_tol=1e-5, abs_tol=1e-6)
            or not isinstance(profile.get("world_identity"), str)
            or re.fullmatch(r"[0-9a-f]{64}", profile["world_identity"]) is None
            or not all(isinstance(profile.get(key), str) and profile[key] for key in ("cpu", "model"))):
        raise ValueError("domain-guard stock profile is incomplete or inconsistent")
    return {"checks": int(match.group(1)), "resize_controls": resize, "direct_resize": direct,
            "stock_profile": profile,
            "scope": "Sanitizer diagnostics only; stock guard timings are not a performance result."}


@contextmanager
def sanitizer_environment(mode: str, runtime: Path | None):
    """Only the checked child inherits sanitizer settings, never the user's shell."""
    if mode == "asan" and runtime is None:
        raise ValueError("Matching ASan runtime is unavailable")
    names = {key for key in os.environ if key.startswith("DYLD_")} | {"ASAN_OPTIONS", "UBSAN_OPTIONS"}
    saved = {key: os.environ[key] for key in names if key in os.environ}
    for key in names:
        os.environ.pop(key, None)
    os.environ["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    if mode == "asan":
        os.environ["DYLD_INSERT_LIBRARIES"] = str(runtime)
        os.environ["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1:abort_on_error=1"
    try:
        yield
    finally:
        for key in list(os.environ):
            if key.startswith("DYLD_") or key in {"ASAN_OPTIONS", "UBSAN_OPTIONS"}:
                os.environ.pop(key, None)
        os.environ.update(saved)


def _write(path: Path, data: str) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as output:
        output.write(data)


def _json(path: Path, data: dict) -> None:
    _write(path, json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + "\n")


def _asan_runtime(compiler: Path, env: dict[str, str]) -> Path:
    resource = subprocess.run([str(compiler), "-print-resource-dir"], check=True, capture_output=True,
                              text=True, env=env).stdout.strip()
    runtime = (Path(resource) / "lib/darwin/libclang_rt.asan_osx_dynamic.dylib").resolve()
    if not runtime.is_file():
        raise ValueError(f"Matching Apple Clang ASan runtime not found: {runtime}")
    return runtime


def _sign(path: Path, env: dict[str, str]) -> str:
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(path)],
                   check=True, capture_output=True, env=env)
    subprocess.run(["codesign", "--verify", "--strict", str(path)], check=True, capture_output=True, env=env)
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(path)], check=True,
                             text=True, capture_output=True, env=env).stderr
    if "adhoc" not in details.lower():
        raise ValueError("Diagnostic dylib signature is not ad-hoc")
    return details.strip()


def _official_engine(godot: Path, env: dict[str, str]) -> str:
    subprocess.run(["codesign", "--verify", "--strict", str(godot)], check=True, capture_output=True, env=env)
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(godot)], check=True,
                             capture_output=True, text=True, env=env).stderr
    if f"TeamIdentifier={OFFICIAL_TEAM}" not in {line.strip() for line in details.splitlines()}:
        raise ValueError("Godot executable is not signed by the expected official team")
    return details.strip()


def _checked(runner, command: list[str], destination: Path, label: str, timeout: float,
             required: list[str], mode: str, runtime: Path | None) -> tuple[dict, str]:
    with sanitizer_environment(mode, runtime):
        report = runner.run_checked(command, destination, label=label, timeout=timeout, required=required)
    log = Path(report["log"]).read_text(encoding="utf-8", errors="replace")
    return report, log


def run(args: argparse.Namespace) -> dict:
    if (not math.isfinite(args.timeout) or not 0 < args.timeout <= 1800
            or not 1 <= args.states <= 12000 or not 1 <= args.variant_states <= 1500):
        raise ValueError("Invalid timeout or state limits")
    scripts = args.script or list(DEFAULT_SCRIPTS)
    if len(scripts) != len(set(scripts)) or any(script not in SCRIPT_COMPONENTS for script in scripts):
        raise ValueError("Unknown or repeated oracle script")
    domain_guard = getattr(args, "domain_guard", False)
    if type(domain_guard) is not bool or (domain_guard and not set(DEFAULT_SCRIPTS).issubset(scripts)):
        raise ValueError("Domain-guard diagnostics require the base, stage and propeller oracles")
    spec = importlib.util.spec_from_file_location("openrc_macos_diagnostic_helpers", HERE / "fpcr_control_probe.py")
    if spec is None or spec.loader is None:
        raise ValueError("Cannot load the shared diagnostic helpers")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    mac = helper._module("openrc_macos_diagnostic_builder", HERE / "build_macos.py")
    runner = helper._module("openrc_macos_diagnostic_oracle", HERE / "run.py")
    checked_runner = helper._module("openrc_macos_diagnostic_checked", ROOT / "tools/godot/run_checked.py")
    root, project = args.tool_root.resolve(), args.project.resolve()
    tmp, raw_out = (ROOT / "tmp").resolve(), args.out.expanduser()
    if raw_out.exists() or raw_out.is_symlink():
        raise ValueError("--out must be new")
    out = raw_out.resolve()
    if (root == tmp or not root.is_relative_to(tmp) or out == tmp or not out.is_relative_to(tmp)
            or not out.parent.is_dir() or out.is_relative_to(root) or root.is_relative_to(out)
            or out.is_relative_to(project) or project.is_relative_to(out)):
        raise ValueError("Output must be a new tmp/ directory separate from the candidate and project")
    out.mkdir(exist_ok=False)
    summary = {"format": FORMAT, "installable": False, "performance_qualification": False,
               "mode": args.mode, "status": "failed", "scripts": scripts, "runs": {},
               "scope": "Only nk_kernel.cpp and inline code compiled into that translation unit are instrumented; "
                        "the Godot executable and prebuilt godot-cpp archive are uninstrumented.",
               "archive_scope": "Retained archives are hashed before/after; their bytes are not bound by the candidate receipt."}
    if domain_guard:
        summary["domain_guard"] = {"requested": True, "covered": False}
    diagnostic_before = None
    original_signature = None
    diagnostic_path = getattr(args, "diagnostic_godot", None)
    try:
        lock = mac.locked.load_lock()
        toolchain = mac.host_toolchain()
        engine = mac.godot_identity(args.godot, lock)
        identity = mac._identity()
        built = mac.validate_build(root, False, identity, toolchain, engine, lock)
        project_proof = runner.validate_project(project)
        if not project_proof:
            raise ValueError("Use a verified isolated research project")
        work, source = root / "work/candidate", (HERE / "src/nk_kernel.cpp").resolve()
        database = work / "compile_commands.json"
        rows = json.loads(database.read_text(encoding="utf-8"))
        selected = [row for row in rows if isinstance(row, dict) and
                    (Path(row.get("directory", "")) / row.get("file", "")).resolve() == source]
        if len(selected) != 1:
            raise ValueError("Compilation database must contain exactly one kernel TU")
        env = mac.clean_build_environment(Path(toolchain["compiler"]), Path(toolchain["sdk_path"]))
        env["CC"] = toolchain["c_compiler"]
        original_signature = _official_engine(Path(engine["path"]), env)
        summary["godot_signature"] = original_signature
        selected_godot = Path(engine["path"])
        if diagnostic_path is not None:
            diagnostic_before = _diagnostic_host(selected_godot, diagnostic_path, mac, lock, env, tmp,
                                                  (root, project, out))
            selected_godot = Path(diagnostic_before["engine"]["path"])
            summary["diagnostic_host"] = diagnostic_before
            summary["official_engine_parity"] = False
        runtime = _asan_runtime(Path(toolchain["compiler"]), env) if args.mode == "asan" else None
        summary["asan_runtime"] = {"path": str(runtime), "sha256": helper._sha(runtime)} if runtime else None
        summary["engine_sha256"] = engine["sha256"]
        summary["candidate_binary_sha256"] = built["binary_sha256"]
        summary["project"] = str(project)
        summary["project_inventory"] = project_proof
        harness = [*HERE.glob("*.gd"), HERE / "run.py", HERE / "build_macos.py", HERE / "fpcr_control_probe.py",
                   HERE / "macos_diagnostics.py", ROOT / "tools/godot/run_checked.py"]
        guard_script = HERE / DOMAIN_GUARD_SCRIPT
        if domain_guard and (guard_script.is_symlink() or not guard_script.is_file() or guard_script not in harness):
            raise ValueError("Domain-guard diagnostic harness is missing or redirected")
        harness_hashes = {str(path): helper._sha(path) for path in harness}
        if domain_guard:
            summary["domain_guard"]["harness_sha256"] = harness_hashes[str(guard_script)]
        inputs = None

        def build_variant(kind: str, control: bool) -> tuple[Path, dict, dict]:
            nonlocal inputs
            directory = out / kind
            directory.mkdir()
            copied, obj = directory / "nk_kernel.cpp", directory / "nk_kernel.o"
            library, descriptor = directory / "libopenrc_native_kernel.dylib", directory / "diagnostic.gdextension"
            text = source.read_text(encoding="utf-8")
            if control:
                _write(copied, control_source(text, args.mode))
            else:
                with copied.open("xb") as output:
                    output.write(source.read_bytes())
            extra = sanitizer_compile_flags(args.mode, control=control)
            compile_args, old_obj = helper.compile_command(selected[0], Path(toolchain["compiler"]), work,
                                                            source, copied, obj, HERE / "src", extra)
            link_args, archives = helper.link_command(built["link_command"], Path(toolchain["compiler"]), work,
                                                       old_obj, obj, library)
            link_args.extend(sanitizer_flags(args.mode))
            current = {str(path): helper._sha(path) for path in
                       [source, old_obj, database, root / "build-receipt.json", *archives,
                        *([guard_script] if domain_guard else [])]}
            if inputs is None: inputs = current
            if inputs != current:
                raise ValueError("Candidate inputs changed before diagnostic compilation")
            helper._run_to_log(compile_args, work, env, directory / "compile.log", args.timeout)
            helper._run_to_log(link_args, work, env, directory / "link.log", args.timeout)
            if not obj.is_file() or not library.is_file() or mac.architectures(library) != ["arm64"]:
                raise ValueError("Diagnostic object or ARM64 dylib was not produced")
            signature = _sign(library, env)
            helper._run_to_log(["xcrun", "otool", "-L", str(library)], work, env,
                               directory / "dependencies.log", args.timeout)
            helper._run_to_log(["xcrun", "nm", "-u", str(library)], work, env,
                               directory / "imports.log", args.timeout)
            if args.mode not in (directory / "imports.log").read_text(encoding="utf-8", errors="replace").lower():
                raise ValueError("Diagnostic library lacks imports for the requested sanitizer")
            _write(descriptor, '[configuration]\nentry_symbol = "openrc_native_kernel_library_init"\n'
                               'compatibility_minimum = "4.7"\nreloadable = false\n\n[libraries]\n'
                               'macos.arm64 = "libopenrc_native_kernel.dylib"\n')
            info = {"source_sha256": helper._sha(copied), "object_sha256": helper._sha(obj),
                    "binary_sha256": helper._sha(library), "descriptor_sha256": helper._sha(descriptor),
                    "compile_command": compile_args, "link_command": link_args,
                    "compile_log_sha256": helper._sha(directory / "compile.log"),
                    "link_log_sha256": helper._sha(directory / "link.log"),
                    "dependencies_log_sha256": helper._sha(directory / "dependencies.log"),
                    "imports_log_sha256": helper._sha(directory / "imports.log"), "signing": signature}
            return descriptor, info, current

        control_descriptor, control_info, _ = build_variant("positive-control", True)
        summary["positive_control_build"] = control_info
        control_result = out / "positive-control/oracle.json"
        command = [str(selected_godot), "--headless", "--path", str(project), "--audio-driver", "Dummy",
                   "--script", str(HERE / "oracle.gd"), "--", f"--extension={control_descriptor}",
                   f"--output={control_result}", f"--seed={args.seed}", "--states=1", "--variant-states=1",
                   "--timing-rounds=1", "--experimental-native-macos=false"]
        checked, log = _checked(checked_runner, command, out / "checks", "sanitizer-control", args.timeout,
                                [], args.mode, runtime)
        control = {"checked": checked, "command": command, "detected": detected_control(
            args.mode, checked, log, out / "positive-control/nk_kernel.cpp",
            out / "positive-control/libopenrc_native_kernel.dylib")}
        summary["positive_control"] = control
        if not control["detected"]:
            loader = "diagnostic" if diagnostic_before is not None else "official"
            raise ValueError(f"Sanitizer detector was not demonstrated in the {loader} Godot loader; inspect its retained log")
        descriptor, candidate_info, _ = build_variant("candidate", False)
        summary["instrumented_build"] = candidate_info
        for script in scripts:
            output = out / (Path(script).stem + "-oracle.json")
            command = [str(selected_godot), "--headless", "--path", str(project), "--audio-driver", "Dummy",
                       "--script", str(HERE / script), "--", f"--extension={descriptor}", f"--output={output}",
                       f"--seed={args.seed}", f"--states={args.states}", f"--variant-states={args.variant_states}",
                       "--timing-rounds=1", "--experimental-native-macos=false"]
            checked, log = _checked(checked_runner, command, out / "checks", Path(script).stem,
                                    args.timeout, ["NK3_ORACLE verdict=pass"], args.mode, runtime)
            try:
                data = json.loads(output.read_text(encoding="utf-8"))
                error = oracle_error(script, data, checked, log, args.seed, args.states)
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as exception:
                data, error = {}, f"Missing or invalid oracle output: {exception}"
            summary["runs"][script] = {"checked": checked, "error": error, "command": command,
                                       "oracle_sha256": helper._sha(output) if output.is_file() else None,
                                       "total": data.get("total"), "coverage": data.get("coverage")}
            if error:
                raise ValueError(f"{script}: {error}")
        if domain_guard:
            command = [str(selected_godot), "--headless", "--path", str(project), "--audio-driver", "Dummy",
                       "--script", str(guard_script), "--", f"--extension={descriptor}"]
            checked, log = _checked(checked_runner, command, out / "checks", "domain-guard",
                                    args.timeout, ["MACOS_DOMAIN_GUARD verdict=pass"], args.mode, runtime)
            summary["domain_guard"].update(checked=checked, command=command)
            try:
                guard_result = domain_guard_result(checked, log)
            except (ValueError, TypeError, KeyError) as error:
                summary["domain_guard"]["error"] = str(error)
                raise ValueError(f"{DOMAIN_GUARD_SCRIPT}: {error}") from error
            summary["domain_guard"].update(**guard_result)
        if (inputs != {name: helper._sha(Path(name)) for name in inputs} or mac._identity() != identity
                or mac.godot_identity(args.godot, lock) != engine or runner.validate_project(project) != project_proof
                or harness_hashes != {name: helper._sha(Path(name)) for name in harness_hashes}
                or (runtime and helper._sha(runtime) != summary["asan_runtime"]["sha256"])):
            raise ValueError("Candidate, runtime, engine, harness or project changed during diagnostics")
        if diagnostic_before is not None:
            after = _diagnostic_host(Path(engine["path"]), diagnostic_path, mac, lock, env, tmp,
                                     (root, project, out))
            if after != diagnostic_before or _official_engine(Path(engine["path"]), env) != original_signature:
                raise ValueError("Official or diagnostic host changed during diagnostics")
            summary["diagnostic_host_unchanged"] = True
            summary["official_host_unchanged"] = True
        for directory, info in ((out / "positive-control", control_info), (out / "candidate", candidate_info)):
            for name, key in (("nk_kernel.cpp", "source_sha256"), ("nk_kernel.o", "object_sha256"),
                              ("libopenrc_native_kernel.dylib", "binary_sha256"),
                              ("diagnostic.gdextension", "descriptor_sha256")):
                if helper._sha(directory / name) != info[key]:
                    raise ValueError("Diagnostic build changed during oracle execution")
        summary["input_sha256"] = inputs
        summary["harness_sha256"] = harness_hashes
        if domain_guard:
            summary["domain_guard"]["covered"] = True
        summary["status"] = "passed"
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        detail = str(error)
        if diagnostic_path is not None and original_signature is not None:
            try:
                summary["official_host_unchanged"] = (mac.godot_identity(args.godot, lock) == engine
                    and _official_engine(Path(engine["path"]), env) == original_signature)
            except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as host_error:
                summary["official_host_unchanged"] = False
                summary["official_host_recheck_error"] = str(host_error)
            if not summary["official_host_unchanged"]:
                detail += "; official host changed or recheck failed"
        if diagnostic_before is not None:
            try:
                summary["diagnostic_host_unchanged"] = (_diagnostic_host(
                    Path(engine["path"]), diagnostic_path, mac, lock, env, tmp, (root, project, out)) == diagnostic_before)
            except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as host_error:
                summary["diagnostic_host_unchanged"] = False
                summary["diagnostic_host_recheck_error"] = str(host_error)
            if not summary["diagnostic_host_unchanged"]:
                detail += "; diagnostic host changed or recheck failed"
        summary["error"] = detail
        _json(out / "diagnostic-summary.json", summary)
        raise ValueError(f"Diagnostic not qualified: {detail}; details: {out / 'diagnostic-summary.json'}") from error
    _json(out / "diagnostic-summary.json", summary)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("ubsan", "asan"), required=True)
    parser.add_argument("--tool-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--diagnostic-godot", type=Path,
                        help="separate ad-hoc, non-hardened clone used only for disposable diagnostics")
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--script", action="append", choices=tuple(SCRIPT_COMPONENTS),
                        help="repeat to select oracles; default is base, stage and propeller")
    parser.add_argument("--domain-guard", action="store_true",
                        help="also exercise the real Mac domain guard after the three default oracles")
    parser.add_argument("--states", type=int, default=64)
    parser.add_argument("--variant-states", type=int, default=16)
    parser.add_argument("--seed", type=int, default=20261027)
    parser.add_argument("--timeout", type=float, default=600)
    try:
        result = run(parser.parse_args())
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        print(f"macOS sanitizer diagnostic failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": result["status"], "mode": result["mode"], "installable": False}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
