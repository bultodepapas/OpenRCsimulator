#!/usr/bin/env python3
"""Run a disposable FPCR detector control against a verified Mac build.

This creates a different, non-installable library in a new tmp/ directory.  Its
private copy of nk_kernel.cpp flips FZ on the first FPCR observation and restores
it on the second, in the isolated Godot process.  The original signed candidate,
source, descriptor and receipts are never modified.  A passing control means
that the existing base oracle actually noticed the change, not that the mutant
is a valid physics backend.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import re
import shlex
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FORMAT = "openrc-nk3-macos-fpcr-control v1"
MASK = 0x07C8BF07
FZ = 1 << 24
MARKER = "OPENRC_FPCR_CONTROL_MUTANT"
ERROR = "macOS FPCR controls changed at after_transport"


def _module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def mutated_source(source: str) -> str:
    """Replace only the unique FPCR snapshot in a disposable source copy."""
    header = "#include <cstdint>\n"
    anchor = '\t\t__asm__ __volatile__("mrs %0, fpcr" : "=r"(fpcr) : : "memory");\n'
    if source.count(header) != 1 or source.count(anchor) != 1:
        raise ValueError("Expected unique include and FPCR observation anchors")
    injection = r'''#if defined(OPENRC_FPCR_CONTROL_MUTANT)
		static thread_local std::uint64_t saved_fpcr = 0;
		static thread_local unsigned int observation = 0;
		if (observation == 0) {
			saved_fpcr = fpcr;
			const std::uint64_t changed = fpcr ^ (std::uint64_t(1) << 24);
			__asm__ __volatile__("msr fpcr, %0\n\tisb" : : "r"(changed) : "memory");
			observation = 1;
		} else if (observation == 1) {
			__asm__ __volatile__("msr fpcr, %0\n\tisb" : : "r"(saved_fpcr) : "memory");
			std::uint64_t restored = 0;
			__asm__ __volatile__("mrs %0, fpcr" : "=r"(restored) : : "memory");
			std::fprintf(stderr, "OPENRC_FPCR_CONTROL_MUTANT initial=%016llx observed=%016llx restored=%016llx\n",
				static_cast<unsigned long long>(saved_fpcr), static_cast<unsigned long long>(fpcr),
				static_cast<unsigned long long>(restored));
			std::fflush(stderr);
			observation = 2;
		}
#endif
'''
    return source.replace(header, header + "#include <cstdio>\n", 1).replace(anchor, anchor + injection, 1)


def _output_index(args: list[str]) -> int:
    indices = [index for index, value in enumerate(args) if value == "-o"]
    if len(indices) != 1 or indices[0] + 1 >= len(args):
        raise ValueError("Command must have exactly one separate -o output")
    return indices[0] + 1


def compile_command(row: dict, compiler: Path, work: Path, source: Path,
                    copied: Path, obj: Path, source_dir: Path,
                    extra_flags: tuple[str, ...] = ("-DOPENRC_FPCR_CONTROL_MUTANT=1",)) -> tuple[list[str], Path]:
    args = row.get("arguments")
    if args is None and isinstance(row.get("command"), str):
        args = shlex.split(row["command"])
    if not isinstance(args, list) or not args or any(not isinstance(value, str) for value in args):
        raise ValueError("Malformed compiler command")
    args = list(args)
    if Path(args[0]).absolute() != compiler.absolute() or Path(row.get("directory", "")).resolve() != work.resolve():
        raise ValueError("Compiler or working directory differs from the candidate")
    if args.count("-c") != 1 or args.count(row.get("file")) != 1 or Path(row["file"]).resolve() != source.resolve():
        raise ValueError("Compilation does not identify exactly the candidate kernel source")
    forbidden = ("@", "-M", "-save-temps", "-serialize-diagnostics", "-fprofile", "-fmodules",
                 "-ftime-trace", "-gsplit-dwarf", "-Xclang", "-Xlinker", "-Wl,")
    if any(arg.startswith(forbidden) for arg in args[1:]):
        raise ValueError("Compiler command has an unreviewed side-output option")
    out_index = _output_index(args)
    original_obj = (work / args[out_index]).resolve()
    if (not original_obj.is_relative_to((work / "lib/obj").resolve()) or not original_obj.is_file()
            or (work / row.get("output", "")).resolve() != original_obj):
        raise ValueError("Compilation output is not the retained candidate object")
    source_index = args.index(row["file"])
    args[out_index] = str(obj)
    args[source_index] = str(copied)
    args.extend(["-I" + str(source_dir.resolve()), *extra_flags])
    return args, original_obj


def link_command(original: list[str], compiler: Path, work: Path, old_obj: Path,
                 obj: Path, library: Path) -> tuple[list[str], list[Path]]:
    if not original or Path(original[0]).absolute() != compiler.absolute():
        raise ValueError("Link command does not use the selected compiler")
    args = list(original)
    output_index = _output_index(args)
    if (work / args[output_index]).resolve() != (work / "lib/libopenrc_native_kernel.dylib").resolve():
        raise ValueError("Link output is not the candidate library")
    objects = [index for index, arg in enumerate(args) if arg.endswith(".o")
               and (work / arg).resolve() == old_obj]
    if len(objects) != 1:
        raise ValueError("Link must use the candidate object exactly once")
    archives = [(work / arg).resolve() for arg in args if arg.endswith(".a")]
    if not archives or any(not path.is_relative_to((work / "dependencies/godot-cpp/bin").resolve())
                           or not path.is_file() or path.is_symlink() for path in archives):
        raise ValueError("Expected retained godot-cpp archive is missing")
    # Only the observed linker shape is admitted; no response files, map files,
    # or alternate output-producing linker options can escape the new directory.
    value_options = {"-o", "-arch", "-isysroot"}
    flags = {"-fvisibility=hidden", "-fno-lto", "-shared", "-mmacosx-version-min=11.0",
             "-Wl,-install_name,@rpath/libopenrc_native_kernel.dylib"}
    i = 1
    while i < len(args):
        if args[i] in value_options:
            i += 2
        elif args[i] in flags or i == objects[0] or args[i].endswith(".a"):
            i += 1
        else:
            raise ValueError(f"Unreviewed link argument: {args[i]}")
    args[output_index], args[objects[0]] = str(library), str(obj)
    return args, archives


def control_result(result: dict, checked: dict, log: str) -> dict:
    """Require the real changed snapshot, restoration and the oracle's rejection."""
    boundary = result.get("macos_boundary", {})
    fpcr = boundary.get("fpcr", {}) if isinstance(boundary, dict) else {}
    coverage = result.get("coverage", {}).get("macos_fpcr", {})
    matches = re.findall(r"OPENRC_FPCR_CONTROL_MUTANT initial=([0-9a-f]{16}) "
                         r"observed=([0-9a-f]{16}) restored=([0-9a-f]{16})", log)
    if (result.get("format") != "openrc-nk3-oracle v1" or result.get("verdict") != "fail"
            or ERROR not in result.get("failures", []) or boundary.get("control_unchanged") is not False
            or coverage.get("observations") != 2 or coverage.get("changed") != 1 or len(matches) != 1
            or checked.get("complete") is not True or checked.get("reason") != "process_exit"
            or checked.get("process_exit") != 1 or checked.get("counts", {}).get("error") != 0
            or checked.get("missing_required_text") != []):
        raise ValueError("The isolated checked oracle did not reject the FPCR change cleanly")
    before, changed, restored = (int(value, 16) for value in matches[0])
    if ((before ^ changed) & MASK != FZ or (before ^ restored) & MASK
            or int(fpcr["before_transport"]["raw"], 16) != before
            or int(fpcr["after_transport"]["raw"], 16) != changed
            or int(fpcr["before_transport"]["control"], 16) != before & MASK
            or int(fpcr["after_transport"]["control"], 16) != changed & MASK):
        raise ValueError("FPCR mutation, oracle snapshots or restoration differ")
    return {"initial": f"0x{before:016x}", "observed": f"0x{changed:016x}",
            "restored": f"0x{restored:016x}", "control_mask": f"0x{MASK:08x}", "flipped_bit": 24}


def _run_to_log(command: list[str], cwd: Path, env: dict[str, str], log: Path, timeout: float) -> None:
    with log.open("x", encoding="utf-8") as output:
        completed = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT,
                                   text=True, timeout=timeout)
    if completed.returncode:
        raise ValueError(f"Command failed ({completed.returncode}); retained log: {log}")


def run(args: argparse.Namespace) -> dict:
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 1800:
        raise ValueError("--timeout must be finite and between 0 and 1800 seconds")
    mac = _module("openrc_fpcr_mac_builder", HERE / "build_macos.py")
    runner = _module("openrc_fpcr_oracle_runner", HERE / "run.py")
    checked_runner = _module("openrc_fpcr_checked_runner", ROOT / "tools/godot/run_checked.py")
    root, project = args.tool_root.resolve(), args.project.resolve()
    tmp = (ROOT / "tmp").resolve()
    raw_out = args.out.expanduser()
    if raw_out.exists() or raw_out.is_symlink():
        raise ValueError("--out must be a new directory")
    out = raw_out.resolve()
    if (not out.is_relative_to(tmp) or out == tmp or not out.parent.is_dir()
            or out.is_relative_to(root) or root.is_relative_to(out)
            or out.is_relative_to(project) or project.is_relative_to(out)):
        raise ValueError("--out must be a new tmp/ directory separate from the build and project")
    if root == tmp or not root.is_relative_to(tmp):
        raise ValueError("--tool-root must be a candidate directory inside tmp/")
    lock = mac.locked.load_lock()
    toolchain = mac.host_toolchain()
    engine = mac.godot_identity(args.godot, lock)
    identity = mac._identity()
    built = mac.validate_build(root, False, identity, toolchain, engine, lock)
    project_proof = runner.validate_project(project)
    if not project_proof:
        raise ValueError("Use a verified isolated research project, not the canonical app")
    work = root / "work/candidate"
    database_path = work / "compile_commands.json"
    rows = json.loads(database_path.read_text(encoding="utf-8"))
    source = (HERE / "src/nk_kernel.cpp").resolve()
    selected = [row for row in rows if isinstance(row, dict) and
                (Path(row.get("directory", "")) / row.get("file", "")).resolve() == source]
    if len(selected) != 1:
        raise ValueError("Compilation database must have one kernel translation unit")
    out.mkdir(exist_ok=False)
    copied = out / "nk_kernel.control.cpp"
    obj = out / "nk_kernel.control.o"
    library = out / "libopenrc_native_kernel.dylib"
    descriptor = out / "fpcr-control.gdextension"
    result_path = out / "oracle-result.json"
    with copied.open("x", encoding="utf-8", newline="\n") as output:
        output.write(mutated_source(source.read_text(encoding="utf-8")))
    compile_args, old_obj = compile_command(selected[0], Path(toolchain["compiler"]), work, source,
                                            copied, obj, HERE / "src")
    link_args, archives = link_command(built["link_command"], Path(toolchain["compiler"]), work,
                                      old_obj, obj, library)
    inputs = {str(path): _sha(path) for path in [source, old_obj, database_path, root / "build-receipt.json", *archives]}
    env = mac.clean_build_environment(Path(toolchain["compiler"]), Path(toolchain["sdk_path"]))
    env["CC"] = toolchain["c_compiler"]
    _run_to_log(compile_args, work, env, out / "compile.log", args.timeout)
    _run_to_log(link_args, work, env, out / "link.log", args.timeout)
    if not obj.is_file() or not library.is_file() or mac.architectures(library) != ["arm64"]:
        raise ValueError("Diagnostic compilation or ARM64 link did not produce its output")
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(library)],
                   check=True, env=env, capture_output=True)
    subprocess.run(["codesign", "--verify", "--strict", str(library)], check=True, env=env, capture_output=True)
    signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(library)], check=True, env=env,
                               text=True, capture_output=True).stderr
    if "adhoc" not in signature.lower():
        raise ValueError("Diagnostic library lacks its expected ad-hoc signature")
    with descriptor.open("x", encoding="utf-8", newline="\n") as output:
        output.write('[configuration]\nentry_symbol = "openrc_native_kernel_library_init"\n'
                     'compatibility_minimum = "4.7"\nreloadable = false\n\n[libraries]\n'
                     'macos.arm64 = "libopenrc_native_kernel.dylib"\n')
    command = [str(args.godot.resolve()), "--headless", "--path", str(project), "--audio-driver", "Dummy",
               "--script", str(HERE / "oracle.gd"), "--", f"--extension={descriptor}",
               f"--output={result_path}", "--seed=20261027", "--states=1", "--variant-states=1",
               "--timing-rounds=1", "--experimental-native-macos=false"]
    checked = checked_runner.run_checked(command, out / "checks", timeout=args.timeout,
                                         required=["NK3_ORACLE verdict=fail", MARKER], label="fpcr-control")
    result = json.loads(result_path.read_text(encoding="utf-8"))
    log = Path(checked["log"]).read_text(encoding="utf-8", errors="replace")
    observed = control_result(result, checked, log)
    if (inputs != {name: _sha(Path(name)) for name in inputs} or mac._identity() != identity
            or mac.godot_identity(args.godot, lock) != engine or runner.validate_project(project) != project_proof):
        raise ValueError("Candidate inputs, engine or project changed during the control")
    receipt = {"format": FORMAT, "installable": False, "result": "detected", "scope":
               "Disposable calling-thread FPCR detector control; not a qualification or candidate build",
               "candidate_build_receipt_sha256": inputs[str(root / "build-receipt.json")],
               "candidate_binary_sha256": built["binary_sha256"], "engine_sha256": engine["sha256"],
               "project": str(project), "project_inventory": project_proof, "input_sha256": inputs,
               "archive_scope": "Retained archives were hashed before/after; the candidate receipt does not bind their bytes.",
               "mutated_source_sha256": _sha(copied), "object_sha256": _sha(obj),
               "diagnostic_binary_sha256": _sha(library), "descriptor_sha256": _sha(descriptor),
               "oracle_sha256": _sha(HERE / "oracle.gd"), "script_sha256": _sha(Path(__file__)),
               "compile_command": compile_args, "link_command": link_args, "oracle_command": command,
               "compile_log_sha256": _sha(out / "compile.log"), "link_log_sha256": _sha(out / "link.log"),
               "oracle_result_sha256": _sha(result_path), "checked": checked, "fpcr": observed,
               "signing": {"kind": "ad-hoc", "verified": True, "details": signature.strip()}}
    with (out / "control-receipt.json").open("x", encoding="utf-8", newline="\n") as file:
        json.dump(receipt, file, indent=2, sort_keys=True, allow_nan=False)
        file.write("\n")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-root", type=Path, required=True, help="verified candidate build root")
    parser.add_argument("--godot", type=Path, required=True, help="exact Godot executable bound by the candidate")
    parser.add_argument("--project", type=Path, required=True, help="verified isolated research app")
    parser.add_argument("--out", type=Path, required=True, help="new directory under tmp/, outside the candidate")
    parser.add_argument("--timeout", type=float, default=600, help="per compile, link and checked oracle timeout")
    args = parser.parse_args()
    try:
        receipt = run(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"FPCR control failed; partial output retained: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"result": receipt["result"], "fpcr": receipt["fpcr"], "receipt": str(args.out.resolve() / "control-receipt.json")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
