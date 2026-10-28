#!/usr/bin/env python3
"""NK-3 Linux development builds: SCons compile database, symbols and ASan/UBSan.

Uses the pinned builder and existing oracles. Diagnostic artifacts cannot be installed.
See README.md; every invocation requires a new output directory under tmp/.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
def sanitizer_flags(mode: str) -> list[str]:
    if mode == "profile":
        return []
    return [f"-fsanitize={'address,undefined' if mode == 'asan' else 'undefined'}",
            "-fno-sanitize-recover=undefined"]


FP_FLAGS = ["-fno-fast-math", "-ffp-contract=off"]
SIGNATURE = re.compile(r"AddressSanitizer|UndefinedBehaviorSanitizer|LeakSanitizer|runtime error:|RTLD_DEEPBIND")
FORMAT = "openrc-nk3-development-build v1"


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")


def fresh(path: Path) -> Path:
    path = path.resolve()
    if not path.is_relative_to(ROOT / "tmp") or path == ROOT / "tmp":
        raise ValueError("output must be a new directory inside this repository's tmp/")
    path.mkdir(parents=True, exist_ok=False)
    return path


def source_hashes() -> dict:
    paths = [*HERE.glob("src/*.cpp"), *HERE.glob("src/*.hpp"), HERE / "toolchain-lock.json",
             HERE / "devtools.py", ROOT / "research/native-slipstream/build.py"]
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


def validate_compdb(path: Path, mode: str) -> list[dict]:
    entries = json.loads(path.read_text())
    expected = {p.resolve() for p in (HERE / "src").glob("*.cpp")}
    selected = []
    for entry in entries:
        file = (Path(entry["directory"]) / entry["file"]).resolve()
        if file not in expected:
            continue
        args = entry.get("arguments") or shlex.split(entry["command"])
        required = [*FP_FLAGS, "-std=c++17", "-fexceptions", "-fno-omit-frame-pointer"]
        required += sanitizer_flags(mode)
        if not all(flag in args for flag in required):
            raise ValueError(f"compilation database lacks required flags for {file}")
        if any(flag in args for flag in ("-ffast-math", "-Ofast", "-ffp-contract=fast")):
            raise ValueError(f"compilation database has unsafe floating-point flags for {file}")
        includes = []
        for i, arg in enumerate(args):
            if arg == "-I" and i + 1 < len(args):
                includes.append(Path(entry["directory"]) / args[i + 1])
            elif arg.startswith("-I"):
                includes.append(Path(entry["directory"]) / arg[2:])
        for header in ("nk_math.hpp", "godot_cpp/core/defs.hpp", "godot_cpp/classes/ref_counted.hpp"):
            if not any((include / header).is_file() for include in includes):
                raise ValueError(f"compilation database cannot resolve {header}")
        selected.append(entry)
        expected.remove(file)
    if expected or not selected:
        raise ValueError(f"compilation database misses NK-3 translation units: {sorted(expected)}")
    return selected


def build(args) -> int:
    owner = module("nk3_build", HERE / "build.py")
    locked = owner.locked
    if locked.host_platform_name() != "linux" or locked.host_arch_name() != "x86_64":
        raise ValueError("development builds currently require Linux x86_64")
    lock = locked.load_lock()
    compiler = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
    if compiler != lock["linux"]["compiler_version"]:
        raise ValueError(f"expected GCC {lock['linux']['compiler_version']}, got {compiler}")
    if shutil.disk_usage(ROOT).free < 2 * 1024**3:
        raise ValueError("at least 2 GiB free is required for a development build")
    out = fresh(args.out)
    before = source_hashes()
    # godot-cpp writes objects into its checkout: never share it with the production builder.
    locked.TOOL_ROOT = out / "dependencies"
    scons = locked.ensure_scons(lock)
    cpp = locked.ensure_godot_cpp(lock)
    profile = json.dumps(lock["godot_cpp"]["build_profile"]["content"], sort_keys=True,
                         separators=(",", ":")) + "\n"
    if hashlib.sha256(profile.encode()).hexdigest() != lock["godot_cpp"]["build_profile"]["sha256"]:
        raise ValueError("pinned build profile hash differs")
    (out / "build_profile.json").write_text(profile)
    flags = [*FP_FLAGS, "-fexceptions", "-fno-omit-frame-pointer"]
    flags += sanitizer_flags(args.mode)
    script = locked.sconstruct_text(cpp, HERE / "src", out / "lib", out / "build_profile.json",
                                    lock["godot"]["extension_api"])
    anchor = 'env["build_profile"] = profile_path'
    if script.count(anchor) != 1 or script.count("openrc_slipstream") != 1:
        raise ValueError("shared SConstruct changed; update the development adapter")
    # Before SConscript, so generated bindings as well as NK-3 code are instrumented.
    script = script.replace(anchor, anchor + f"\nenv.Append(CCFLAGS={flags!r})\n" +
                            f"env.Append(LINKFLAGS={sanitizer_flags(args.mode)!r})\n" +
                            f"env.Append(CPPDEFINES={['ASAN_ENABLED', 'UBSAN_ENABLED'] if args.mode == 'asan' else ['UBSAN_ENABLED'] if args.mode == 'ubsan' else []!r})")
    script = script.replace('env.Append(CPPPATH=[source_dir])',
                            'env.Append(CXXFLAGS=["-std=c++17", "-fexceptions"])\nenv.Append(CPPPATH=[source_dir])')
    (out / "SConstruct").write_text(script.replace("openrc_slipstream", "openrc_native_kernel"))
    command = [*scons, "-C", str(out), f"-j{args.jobs}", "platform=linux", "arch=x86_64",
               "target=template_release", "debug_symbols=yes", "lto=none", "verbose=yes",
               f"optimize={'speed' if args.mode == 'profile' else 'debug'}", "compiledb=yes",
               f"compiledb_file={out / 'compile_commands.json'}"]
    with (out / "build.log").open("w") as log:
        subprocess.run(command, env=dict(os.environ, CC="gcc", CXX="g++"), stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    library = out / "lib/libopenrc_native_kernel.so"
    imports = owner.libm_imports(library)
    if not any(symbol.startswith("pow@") for symbol in imports):
        raise ValueError("missing libm pow import; exactness policy violated")
    entries = validate_compdb(out / "compile_commands.json", args.mode)
    if source_hashes() != before:
        raise ValueError("native sources or tooling changed while building; rerun in a new directory")
    (out / "openrc_native_kernel.gdextension").write_text(
        '[configuration]\nentry_symbol = "openrc_native_kernel_library_init"\n'
        'compatibility_minimum = "4.7"\nreloadable = false\n\n[libraries]\n'
        'linux.x86_64 = "lib/libopenrc_native_kernel.so"\n')
    write_json(out / "development-build.json", {
        "format": FORMAT, "mode": args.mode, "installable": False, "command": command,
        "compiler": compiler, "source_hashes": before, "binary_sha256": digest(library),
        "descriptor_sha256": digest(out / "openrc_native_kernel.gdextension"),
        "compile_database_sha256": digest(out / "compile_commands.json"),
        "native_translation_units": len(entries), "libm_imports": imports,
        "godot_cpp_commit": lock["godot_cpp"]["commit"], "scons_version": lock["scons"]["version"],
    })
    print(f"Development build ({args.mode}): {out}\nCompilation database: {out / 'compile_commands.json'}")
    return 0


def sanitizer_environment(mode: str) -> list[str]:
    if mode == "ubsan":
        return ["env", "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"]
    runtime = Path(subprocess.check_output(["g++", "-print-file-name=libasan.so"], text=True).strip()).resolve()
    if not runtime.is_file():
        raise ValueError("matching GCC libasan is unavailable")
    # Keep preload out of Python/SCons. Leak checking of the uninstrumented engine is a separate task.
    return ["env", f"LD_PRELOAD={runtime}", "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:abort_on_error=0",
            "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"]


def sanitizer_lines(log: Path) -> list[str]:
    with log.open(errors="replace") as stream:
        return [line.rstrip()[:1000] for line in stream if SIGNATURE.search(line)][:20]


def checked(command: list[str], out: Path, label: str, timeout: float, required=None) -> dict:
    runner = module("nk3_checked", ROOT / "tools/godot/run_checked.py")
    report = runner.run_checked(command, out, label=label, timeout=timeout, required=required)
    report["sanitizer_diagnostics"] = sanitizer_lines(Path(report["log"]))
    report["ok"] = report["ok"] and not report["sanitizer_diagnostics"]
    report["diagnostic_report"] = str(Path(report["report"]).with_name("diagnostic-report.json"))
    write_json(Path(report["diagnostic_report"]), report)
    return report


def controls(godot: Path, out: Path, mode: str) -> dict:
    """Prove both detectors in a disposable shared library loaded by the same Godot executable."""
    source = out / "positive-control.cpp"
    source.write_text('''#include <cstdlib>
#include <climits>
__attribute__((constructor)) static void fault() {
    if (std::getenv("NK3_ASAN_CONTROL")) {
        volatile int *p = new int[1]; p[1] = 42; delete[] p;
    } else {
        volatile int x = INT_MAX; volatile int y = x + 1; (void)y;
    }
}
extern "C" bool nk3_control_init(void *, void *, void *) { return false; }
''')
    library = out / "positive-control.so"
    subprocess.run(["g++", "-shared", "-fPIC", "-g", "-O0", *sanitizer_flags(mode), str(source),
                    "-o", str(library)], check=True)
    project = out / "control-project"
    project.mkdir()
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="NK3 detector control"\n')
    descriptor = out / "positive-control.gdextension"
    descriptor.write_text('[configuration]\nentry_symbol="nk3_control_init"\ncompatibility_minimum="4.7"\n'
                          f'[libraries]\nlinux.x86_64="{library}"\n')
    script = out / "positive-control.gd"
    script.write_text('extends SceneTree\nfunc _initialize() -> void:\n'
                      '\tGDExtensionManager.load_extension(OS.get_cmdline_user_args()[0])\n\tquit(0)\n')
    # Exercise the same late GDExtensionManager/dlopen path as the port, including RTLD_DEEPBIND compatibility.
    reports = {}
    cases = [("ubsan", "signed integer overflow")]
    if mode == "asan":
        cases.insert(0, ("asan", "heap-buffer-overflow"))
    for name, expected in cases:
        env = sanitizer_environment(mode)
        env.insert(1, "-u")
        env.insert(2, "NK3_ASAN_CONTROL")
        if name == "asan":
            env.append("NK3_ASAN_CONTROL=1")
        report = checked([*private_environment(out), *env, str(godot), "--headless", "--path", str(project),
                          "--audio-driver", "Dummy", "--script", str(script), "--", str(descriptor)],
                         out / "controls", name, 60)
        log = Path(report["log"]).read_text(errors="replace")
        report["detected"] = (report["complete"] is True and report["process_exit"] not in (None, 0)
                              and report["reason"] == "process_exit" and expected in log)
        reports[name] = report
    write_json(out / "positive-controls.json", reports)
    return reports


def private_environment(out: Path) -> list[str]:
    return ["env", *[f"XDG_{kind}_HOME={out / ('xdg-' + kind.lower())}"
                     for kind in ("DATA", "CONFIG", "CACHE")]]


def snapshot(app: Path, out: Path, godot: Path) -> Path:
    """Private copy including imported resources; import only the copy after excluding native installs."""
    if shutil.disk_usage(out).free < 4 * 1024**3:
        raise ValueError("at least 4 GiB free is required for the private app copy")
    target = out / "app"
    shutil.copytree(app, target, ignore=shutil.ignore_patterns("native", "captures"))
    (target / ".godot/extension_list.cfg").unlink(missing_ok=True)
    return target


def import_snapshot(target: Path, out: Path, godot: Path) -> None:
    report = checked([*private_environment(out), str(godot), "--headless", "--path", str(target), "--audio-driver", "Dummy",
                      "--import"], out / "checks", "import", 600)
    write_json(out / "import.json", report)
    if not report["ok"]:
        raise ValueError(f"private project import failed: {report['log']}")


def app_hashes(app: Path) -> dict:
    return {str(p.relative_to(app)): digest(p) for p in sorted(app.rglob("*"))
            if p.is_file() and not {".godot", "native", "captures"}.intersection(p.relative_to(app).parts)}


def coverage_error(oracle: dict, report: dict, script: str, states: int) -> str:
    """Reuse the existing completed-work policy; literal probes alone cannot qualify a diagnostic."""
    owner = module("nk3_verification", HERE / "build.py")
    try:
        key = "stage_oracle" if script == "stage_oracle.gd" else "trajectory"
        error = owner.verification_error(key, dict(oracle, run_valid=report["ok"], checked_run=report))
        if error:
            return error
        if key == "stage_oracle" and sum(oracle["coverage"][key]["states"]
                                        for key in ("stage_air", "stage_ground", "stage_hull")) != states:
            return "stage coverage differs from requested state count"
    except (KeyError, TypeError, ValueError) as error:
        return f"malformed oracle evidence: {error}"
    return ""


def check(args) -> int:
    build_dir = args.build.resolve()
    receipt = json.loads((build_dir / "development-build.json").read_text())
    library = build_dir / "lib/libopenrc_native_kernel.so"
    descriptor = build_dir / "openrc_native_kernel.gdextension"
    if (receipt["format"] != FORMAT or receipt["installable"] is not False
            or receipt["mode"] not in ("ubsan", "asan", "profile") or receipt["source_hashes"] != source_hashes()
            or receipt["binary_sha256"] != digest(library)
            or receipt["compile_database_sha256"] != digest(build_dir / "compile_commands.json")
            or receipt["descriptor_sha256"] != digest(descriptor)):
        raise ValueError("development build is stale or modified; rebuild before checking")
    validate_compdb(build_dir / "compile_commands.json", receipt["mode"])
    godot = args.godot.resolve()
    engine_hash = digest(godot)
    out = fresh(args.out)
    control_reports = controls(godot, out, receipt["mode"]) if receipt["mode"] != "profile" else {}
    if any(not report["detected"] for report in control_reports.values()):
        raise ValueError(f"sanitizer positive control failed; inspect {out / 'positive-controls.json'}. "
                         "ASan requires a compatible ASan-built Godot; the official editor uses RTLD_DEEPBIND. "
                         "Use the ubsan build with the official editor.")
    before = app_hashes(args.app)
    write_json(out / "source-before.json", before)
    app = snapshot(args.app.resolve(), out, godot)
    copied = app_hashes(app)
    if before != copied or before != app_hashes(args.app):
        write_json(out / "source-copied.json", copied)
        raise ValueError("app sources changed while copying; rerun in a new directory")
    # Import may generate .uid/.import metadata for newly added sources; freeze that completed snapshot too.
    import_snapshot(app, out, godot)
    copied = app_hashes(app)
    harness = out / "harness"
    harness.mkdir()
    for file in HERE.glob("*.gd"):
        shutil.copy2(file, harness / file.name)
    harness_hashes = {p.name: digest(p) for p in harness.glob("*.gd")}
    output = out / "oracle.json"
    command = [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy",
               "--script", str(harness / args.script), "--", f"--extension={descriptor}",
               f"--output={output}", f"--states={args.states}", f"--seed={args.seed}"]
    if args.script == "trajectory.gd":
        command += [f"--ticks={args.ticks}", "--skip-timing=true"]
    if receipt["mode"] != "profile":
        command = [*sanitizer_environment(receipt["mode"]), *command]
    command = [*private_environment(out), *command]
    report = checked(command, out / "checks", "oracle", args.timeout, ["NK3_ORACLE verdict=pass"])
    oracle = json.loads(output.read_text()) if output.is_file() else {}
    unchanged = (engine_hash == digest(godot) and receipt["binary_sha256"] == digest(library)
                 and receipt["descriptor_sha256"] == digest(descriptor) and copied == app_hashes(app)
                 and receipt["source_hashes"] == source_hashes()
                 and receipt["compile_database_sha256"] == digest(build_dir / "compile_commands.json")
                 and harness_hashes == {p.name: digest(p) for p in harness.glob("*.gd")})
    error = coverage_error(oracle, report, args.script, args.states)
    passed = report["ok"] and unchanged and not error
    summary = {"format": "openrc-nk3-development-check v1", "ok": passed, "installable": False,
               "mode": receipt["mode"], "build": receipt, "engine_sha256": engine_hash,
               "source_snapshot": copied, "harness_hashes": harness_hashes, "unchanged": unchanged,
               "checked_run": report, "positive_controls": control_reports, "total": oracle.get("total"),
               "coverage": oracle.get("coverage"), "coverage_error": error, "performance_qualification": False}
    write_json(out / "summary.json", summary)
    print(f"Development check {'PASS' if passed else 'FAIL'}: {out / 'summary.json'}")
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    builder = commands.add_parser("build", help="isolated symbol/sanitizer build with SCons compilation database")
    builder.add_argument("--mode", choices=("ubsan", "asan", "profile"), default="ubsan",
                         help="ubsan: official editor; asan: requires a compatible ASan-built engine; profile: symbols")
    builder.add_argument("--jobs", type=int, choices=range(1, 5), default=2)
    builder.add_argument("--out", type=Path, required=True)
    checker = commands.add_parser("check", help="run existing oracles against a private imported project copy")
    checker.add_argument("--build", type=Path, required=True)
    checker.add_argument("--out", type=Path, required=True)
    checker.add_argument("--app", type=Path, default=ROOT / "app")
    checker.add_argument("--godot", type=Path, default=ROOT / ".tools/Godot_v4.8-beta1_linux.x86_64")
    checker.add_argument("--script", choices=("stage_oracle.gd", "trajectory.gd"), default="stage_oracle.gd")
    checker.add_argument("--states", type=int, default=12000)
    checker.add_argument("--seed", type=int, default=20261027)
    checker.add_argument("--ticks", type=int, default=960)
    checker.add_argument("--timeout", type=float, default=900)
    args = parser.parse_args()
    if args.command == "check" and (args.states < 10000 or args.ticks < 960 or not 0 < args.timeout <= 7200):
        parser.error("states must be >= 10000, ticks >= 960, and 0 < timeout <= 7200")
    try:
        return build(args) if args.command == "build" else check(args)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"NK-3 development tool: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
