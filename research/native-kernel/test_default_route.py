#!/usr/bin/env python3
"""Check the production CLI backend route after installing the verified NK-3 library.

This is a software routing regression, not a physical validation or benchmark. The
missing-library case uses a private project and does not change the installation.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "app/tests"))
from test_atmosphere_cli import _read_parts  # noqa: E402: reuse the production trace parser

SPEC = importlib.util.spec_from_file_location("openrc_checked_runner", ROOT / "tools/godot/run_checked.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


def run_case(engine: Path, project: Path | None, output: Path, label: str, args: list[str],
             success: bool = True) -> tuple[dict, str]:
    command = [str(engine), "--headless"]
    if project is not None:
        command += ["--path", str(project)]
    command += ["--audio-driver", "Dummy", "--", *args]
    result = RUNNER.run_checked(
        command, output / "checks", timeout=180, label=label,
    )
    log = Path(result["log"]).read_text(encoding="utf-8", errors="replace")
    if success and not result["ok"]:
        raise AssertionError(f"{label}: checked run failed: {result['reason']}\n{log}")
    if not success and (not result["complete"] or result["reason"] != "process_exit"
                        or result["counts"]["error"]):
        raise AssertionError(f"{label}: expected a clean explicit refusal: {result}\n{log}")
    return result, log


def status(log: str) -> dict:
    prefix = "physics backend: "
    lines = [line[len(prefix):] for line in log.splitlines() if line.startswith(prefix)]
    if len(lines) != 1:
        raise AssertionError(f"expected exactly one backend status, got {len(lines)}\n{log}")
    return json.loads(lines[0])


def trace_parts(path: Path) -> tuple[dict, list]:
    if not path.is_file():
        raise AssertionError(f"trace was not written: {path}")
    _, metadata, rows = _read_parts(path)
    if len(rows) != 14:  # CSV header plus ticks 0..12 for 0.05 s at 240 Hz
        raise AssertionError(f"unexpected row count in {path}: {len(rows)}")
    return metadata, rows


def missing_binary_project(source: Path, destination: Path) -> None:
    """Copy project metadata; link read-only source/assets and the existing imported cache.

    No import runs in this fixture, and only the copy of native/ is modified.
    """
    destination.parent.mkdir()
    # Aircraft manifests resolve authoring sources relative to the app's parent.
    (destination.parent / "assets").symlink_to(source.parent / "assets", target_is_directory=True)
    destination.mkdir()
    for entry in source.iterdir():
        target = destination / entry.name
        if entry.name == "native":
            shutil.copytree(entry, target)
        elif entry.name == ".godot":
            target.mkdir()
            for cached in entry.iterdir():
                if cached.name == "imported":
                    (target / cached.name).symlink_to(cached, target_is_directory=True)
                elif cached.is_dir():
                    shutil.copytree(cached, target / cached.name)
                else:
                    shutil.copy2(cached, target / cached.name)
        else:
            target.symlink_to(entry, target_is_directory=entry.is_dir())
    (destination / "native/kernel/libopenrc_native_kernel.so").unlink()


def sha256_file(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def link_or_copy_verified(source: Path, destination: Path) -> None:
    """Keep unchanged package files byte-identical without writing through a hard link."""
    try:
        os.link(source.resolve(), destination)
    except OSError:
        shutil.copy2(source, destination)
    if sha256_file(source) != sha256_file(destination):
        raise RuntimeError(f"private package file differs from its source: {source}")


def private_package(executable: Path, destination: Path) -> Path:
    """Keep the exact executable and root sidecars; copy native/ for private mutations."""
    destination.mkdir()
    private_executable = destination / executable.name
    link_or_copy_verified(executable, private_executable)
    for sidecar in executable.parent.iterdir():
        if sidecar.name != executable.name and sidecar.is_file():
            link_or_copy_verified(sidecar, destination / sidecar.name)
    shutil.copytree(executable.parent / "native", destination / "native")
    return private_executable


def missing_binary_package(executable: Path, destination: Path) -> Path:
    private_executable = private_package(executable, destination)
    (destination / "native/kernel/libopenrc_native_kernel.so").unlink()
    return private_executable


def corrupt_package(executable: Path, destination: Path, case: str) -> Path:
    private_executable = private_package(executable, destination)
    kernel = destination / "native/kernel"
    receipt_path = kernel / "package-receipt.json"
    if case == "corrupt-descriptor":
        with (kernel / "openrc_native_kernel.gdextension").open("ab") as descriptor:
            descriptor.write(b"\n; altered in private fallback fixture\n")
    elif case == "corrupt-binary":
        library = kernel / "libopenrc_native_kernel.so"
        with library.open("ab") as binary:
            binary.write(b"\nopenrc private fallback fixture\n")
        # Even a sidecar receipt updated to match the altered file must not override the embedded pin.
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt["native_binary_sha256"] = sha256_file(library)
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
    elif case == "malformed-receipt":
        receipt_path.write_text("{", encoding="utf-8")
    elif case == "wrong-executable-hash":
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        original = receipt["executable_sha256"]
        receipt["executable_sha256"] = ("1" if original[0] == "0" else "0") + original[1:]
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
    else:
        raise ValueError(f"unknown private package mutation: {case}")
    return private_executable


def check(engine: Path, project: Path | None, output: Path) -> None:
    common = ["--quick-flight", "--weather=calm", "--t=.05"]

    default_trace = output / "default.csv"
    _, default_log = run_case(engine, project, output, "default", common + [f"--trace={default_trace}"])
    default_status = status(default_log)
    if default_status.get("requested") != "native" or default_status.get("identity", {}).get("backend") != "native" \
            or default_status.get("reason") != "":
        raise AssertionError(f"default must use the installed verified native stage: {default_status}")
    default_meta, default_rows = trace_parts(default_trace)
    # Godot writes StringName dictionary keys with an ampersand in trace metadata.
    trace_identity = json.loads(default_meta["stage_backend"].replace('&"', '"'))
    if trace_identity != default_status["identity"]:
        raise AssertionError("native trace identity differs from the selected stage")
    print("PASS default native trace", flush=True)

    reference_trace = output / "reference.csv"
    _, reference_log = run_case(engine, project, output, "reference", common + [
        "--physics-backend=gdscript_reference", f"--trace={reference_trace}"])
    reference_status = status(reference_log)
    if reference_status != {"requested": "gdscript_reference", "identity": {"backend": "gdscript_reference"},
                            "reason": ""}:
        raise AssertionError(f"explicit reference was not selected: {reference_status}")
    reference_meta, reference_rows = trace_parts(reference_trace)
    if "stage_backend" in reference_meta or default_rows != reference_rows:
        raise AssertionError("reference trace metadata or native/reference sample rows differ")
    print("PASS explicit reference and matching trace rows", flush=True)

    unsupported_trace = output / "unsupported.csv"
    _, unsupported_log = run_case(engine, project, output, "unsupported", common + [
        "--aircraft=p51d-mustang-120", f"--trace={unsupported_trace}"])
    unsupported = status(unsupported_log)
    if unsupported.get("requested") != "native" or unsupported.get("identity", {}).get("backend") != "gdscript_reference" \
            or "only the stock Ugly Stik" not in unsupported.get("reason", ""):
        raise AssertionError(f"unsupported aircraft did not report its reference fallback: {unsupported}")
    unsupported_meta, _ = trace_parts(unsupported_trace)
    if "stage_backend" in unsupported_meta:
        raise AssertionError("unsupported-aircraft trace claimed a native stage")
    print("PASS unsupported aircraft fallback", flush=True)

    missing_engine = engine
    private_project = None
    if project is None:
        missing_engine = missing_binary_package(engine, output / "missing-binary-package")
    else:
        private_project = output / "missing-binary-project/app"
        missing_binary_project(project, private_project)
    missing_trace = output / "missing.csv"
    _, missing_log = run_case(missing_engine, private_project, output, "missing-binary", common + [f"--trace={missing_trace}"])
    missing = status(missing_log)
    if missing.get("requested") != "native" or missing.get("identity", {}).get("backend") != "gdscript_reference" \
            or not any(word in missing.get("reason", "") for word in ("binary", "library")):
        raise AssertionError(f"missing binary did not report its reference fallback: {missing}")
    missing_meta, missing_rows = trace_parts(missing_trace)
    if "stage_backend" in missing_meta or missing_rows != reference_rows:
        raise AssertionError("missing-library trace metadata or reference sample rows differ")
    print("PASS missing binary fallback in private project or package", flush=True)

    if project is None:
        corrupt_cases = {
            "corrupt-descriptor": "native package descriptor differs from the verified loader contract",
            "corrupt-binary": "native package binary differs from its embedded identity",
            "malformed-receipt": "native package artifact receipt is missing or malformed",
            "wrong-executable-hash": "native package executable differs from its artifact receipt",
        }
        for name, expected_reason in corrupt_cases.items():
            candidate = corrupt_package(engine, output / f"{name}-package", name)
            candidate_trace = output / f"{name}.csv"
            _, candidate_log = run_case(candidate, None, output, name, common + [f"--trace={candidate_trace}"])
            actual = status(candidate_log)
            if actual.get("requested") != "native" or actual.get("identity", {}).get("backend") != "gdscript_reference" \
                    or actual.get("reason") != expected_reason:
                raise AssertionError(f"{name} did not report its expected reference fallback: {actual}")
            candidate_meta, candidate_rows = trace_parts(candidate_trace)
            if "stage_backend" in candidate_meta or candidate_rows != reference_rows:
                raise AssertionError(f"{name} trace metadata or reference sample rows differ")
            print(f"PASS {name} fallback in private package", flush=True)

    invalid_trace = output / "invalid.csv"
    _, invalid_log = run_case(engine, project, output, "invalid", common + [
        "--physics-backend=invalid", f"--trace={invalid_trace}"], success=False)
    if "physics backend refused:" not in invalid_log or invalid_trace.exists():
        raise AssertionError("invalid backend was not refused before writing a trace")
    print("PASS invalid backend refusal", flush=True)

    _, qualification_log = run_case(engine, project, output, "qualification-refusal", [
        "--quick-flight", "--native-qualification-invalid"], success=False)
    if "NATIVE_QUALIFICATION mode= verdict=fail" not in qualification_log \
            or "physics backend: " in qualification_log:
        raise AssertionError("malformed qualification request reached a normal physics flight")
    print("PASS malformed qualification refusal before flight", flush=True)

    frame_path = output / "scripted.json"
    _, scripted_log = run_case(engine, project, output, "scripted", [
        "--scripted", f"--frametimes={frame_path}", "--warmup=0", "--t=.05"])
    frame = json.loads(frame_path.read_text(encoding="utf-8"))
    if "physics backend: " in scripted_log or frame.get("route") != "scripted-fixed" \
            or frame.get("simulation", {}).get("physics_enabled") is not False:
        raise AssertionError("scripted route unexpectedly activated physics")
    _, scripted_refusal = run_case(engine, project, output, "scripted-backend", [
        "--scripted", "--physics-backend=native", f"--frametimes={output / 'scripted-refusal.json'}",
        "--warmup=0", "--t=.05"], success=False)
    if "physics backend refused: requires a physics flight" not in scripted_refusal:
        raise AssertionError("scripted route did not refuse an explicit backend")
    print("PASS scripted route and backend refusal", flush=True)

    live_frame = output / "live.json"
    _, live_log = run_case(engine, project, output, "live", [
        "--quick-flight", "--weather=calm", f"--frametimes={live_frame}", "--warmup=0", "--t=.05"])
    live = json.loads(live_frame.read_text(encoding="utf-8"))
    if status(live_log).get("identity", {}).get("backend") != "native" \
            or live.get("route") != "live-input" or live.get("simulation", {}).get("physics_enabled") is not True:
        raise AssertionError("the ordinary flight route did not activate native physics")
    print("PASS ordinary flight native route", flush=True)
    print("NK3_DEFAULT_ROUTE verdict=pass", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    executable = parser.add_mutually_exclusive_group()
    executable.add_argument("--godot", type=Path, help="pinned Godot executable; defaults to app/get-godot.sh")
    executable.add_argument("--release-executable", type=Path, help="actual exported executable with native/ sidecars")
    parser.add_argument("--project", type=Path, default=ROOT / "app", help="imported app with installed native stage")
    parser.add_argument("--out", type=Path, help="new output directory (default: a unique directory under tmp/)")
    args = parser.parse_args()
    engine = args.release_executable or args.godot or Path(subprocess.check_output(
        [str(ROOT / "app/get-godot.sh")], text=True).strip())
    engine = engine.resolve()
    project = None if args.release_executable else args.project.resolve()
    native_root = engine.parent if project is None else project
    if not engine.is_file() or not (native_root / "native/kernel/libopenrc_native_kernel.so").is_file():
        raise SystemExit("The executable and its verified NK-3 library are required.")
    tmp = ROOT / "tmp"
    tmp.mkdir(exist_ok=True)
    output = args.out.resolve() if args.out else Path(tempfile.mkdtemp(prefix="nk3-default-route-", dir=tmp)).resolve()
    if args.out:
        if not output.is_relative_to(tmp.resolve()):
            raise SystemExit("--out must be a new directory under tmp/")
        output.mkdir(parents=True, exist_ok=False)
    for variable, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        os.environ[variable] = str(output / name)
    print(f"NK3 default-route evidence: {output}", flush=True)
    check(engine, project, output)


if __name__ == "__main__":
    main()
