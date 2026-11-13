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
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys

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
        summary["godot_signature"] = _official_engine(Path(engine["path"]), env)
        runtime = _asan_runtime(Path(toolchain["compiler"]), env) if args.mode == "asan" else None
        summary["asan_runtime"] = {"path": str(runtime), "sha256": helper._sha(runtime)} if runtime else None
        summary["engine_sha256"] = engine["sha256"]
        summary["candidate_binary_sha256"] = built["binary_sha256"]
        summary["project"] = str(project)
        summary["project_inventory"] = project_proof
        harness = [*HERE.glob("*.gd"), HERE / "run.py", HERE / "build_macos.py", HERE / "fpcr_control_probe.py",
                   HERE / "macos_diagnostics.py", ROOT / "tools/godot/run_checked.py"]
        harness_hashes = {str(path): helper._sha(path) for path in harness}
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
                       [source, old_obj, database, root / "build-receipt.json", *archives]}
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
        command = [str(args.godot.resolve()), "--headless", "--path", str(project), "--audio-driver", "Dummy",
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
            raise ValueError("Sanitizer detector was not demonstrated in the official Godot loader; inspect its retained log")
        descriptor, candidate_info, _ = build_variant("candidate", False)
        summary["instrumented_build"] = candidate_info
        for script in scripts:
            output = out / (Path(script).stem + "-oracle.json")
            command = [str(args.godot.resolve()), "--headless", "--path", str(project), "--audio-driver", "Dummy",
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
        if (inputs != {name: helper._sha(Path(name)) for name in inputs} or mac._identity() != identity
                or mac.godot_identity(args.godot, lock) != engine or runner.validate_project(project) != project_proof
                or harness_hashes != {name: helper._sha(Path(name)) for name in harness_hashes}
                or (runtime and helper._sha(runtime) != summary["asan_runtime"]["sha256"])):
            raise ValueError("Candidate, runtime, engine, harness or project changed during diagnostics")
        for directory, info in ((out / "positive-control", control_info), (out / "candidate", candidate_info)):
            for name, key in (("nk_kernel.cpp", "source_sha256"), ("nk_kernel.o", "object_sha256"),
                              ("libopenrc_native_kernel.dylib", "binary_sha256"),
                              ("diagnostic.gdextension", "descriptor_sha256")):
                if helper._sha(directory / name) != info[key]:
                    raise ValueError("Diagnostic build changed during oracle execution")
        summary["input_sha256"] = inputs
        summary["harness_sha256"] = harness_hashes
        summary["status"] = "passed"
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        summary["error"] = str(error)
        _json(out / "diagnostic-summary.json", summary)
        raise ValueError(f"Diagnostic not qualified: {error}; details: {out / 'diagnostic-summary.json'}") from error
    _json(out / "diagnostic-summary.json", summary)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("ubsan", "asan"), required=True)
    parser.add_argument("--tool-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--script", action="append", choices=tuple(SCRIPT_COMPONENTS),
                        help="repeat to select oracles; default is base, stage and propeller")
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
