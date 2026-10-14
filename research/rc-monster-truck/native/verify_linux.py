#!/usr/bin/env python3
"""Build and exercise the Linux x86_64 ground-vehicle GDExtension in WSL.

Run this from Linux/WSL with the repository visible under /mnt/c or another
Linux path. It copies only the native source, lock, builder, and parity inputs
into a private workspace outside the repository. The build cache is therefore
kept out of the shared Windows .tools directory.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import platform
from pathlib import PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
from typing import Any


HERE = Path(__file__).resolve().parent
SOURCE_ROOT = HERE.parents[2]
NATIVE_REL = Path("research/rc-monster-truck/native")
SHARED_BUILDER_REL = Path("research/native-slipstream/build.py")
PARITY_APP_FILES = (
    "physics/math3d.gd",
    "physics/integrator.gd",
    "physics/ground_vehicle/vehicle_dynamics.gd",
    "physics/ground_vehicle/vehicle_data.gd",
    "physics/ground_vehicle/course.gd",
    "data/vehicles/ground/mt8_bisonte.json",
    "data/ground_vehicle/practice.json",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command: list[str], *, cwd: Path | None = None, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )


def must_run(command: list[str], *, cwd: Path | None = None, timeout: int = 60) -> str:
    result = run(command, cwd=cwd, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command!r}\n{result.stdout}")
    return result.stdout.strip()


def source_inputs(source_root: Path) -> list[Path]:
    native = source_root / NATIVE_REL
    paths = [
        native / "build.py",
        native / "toolchain-lock.json",
        native / "parity_harness.gd",
        source_root / SHARED_BUILDER_REL,
    ]
    paths.extend(sorted((native / "src").glob("*.cpp")))
    paths.extend(sorted((native / "src").glob("*.hpp")))
    paths.extend(source_root / "app" / relative for relative in PARITY_APP_FILES)
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError("Required Linux native build inputs are missing:\n" + "\n".join(map(str, missing)))
    return paths


def input_digest(source_root: Path, paths: list[Path]) -> tuple[str, dict[str, str]]:
    entries: dict[str, str] = {}
    digest = hashlib.sha256()
    for path in paths:
        relative = path.relative_to(source_root).as_posix()
        contents = path.read_bytes()
        entries[relative] = sha256_bytes(contents)
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(contents)
        digest.update(b"\0")
    return digest.hexdigest(), entries


def ensure_outside_source(path: Path, source_root: Path, what: str) -> Path:
    resolved = path.expanduser().resolve()
    source_resolved = source_root.resolve()
    if resolved == source_resolved or resolved.is_relative_to(source_resolved):
        raise ValueError(f"{what} must be outside the shared repository: {resolved}")
    return resolved


def tracked_head_inputs(source_root: Path, paths: list[Path]) -> list[str]:
    tracked: list[str] = []
    for path in paths:
        relative = path.relative_to(source_root).as_posix()
        result = run(["git", "ls-files", "--error-unmatch", "--", relative], cwd=source_root)
        if result.returncode == 0:
            tracked.append(relative)
    return tracked


def extract_archive_safely(archive_bytes: bytes, destination_root: Path) -> None:
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:") as archive:
        for member in archive.getmembers():
            relative = PurePosixPath(member.name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError(f"Unsafe path in git archive: {member.name!r}")
            destination = destination_root.joinpath(*relative.parts)
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                destination.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise ValueError(f"Git archive file has no contents: {member.name!r}")
                with source, destination.open("wb") as output:
                    shutil.copyfileobj(source, output)
            else:
                raise ValueError(f"Unsupported file type in git archive: {member.name!r}")


def copy_snapshot(source_root: Path, workspace: Path, paths: list[Path], digest: str) -> dict[str, Any]:
    marker = workspace / ".openrc-rcv-linux-workspace.json"
    if workspace.exists():
        if not marker.is_file():
            raise ValueError(f"Refusing to reuse unmarked workspace: {workspace}")
        existing = json.loads(marker.read_text(encoding="utf-8"))
        if existing.get("input_sha256") != digest:
            raise ValueError(f"Workspace input hash differs; choose a new --workspace: {workspace}")
    else:
        workspace.mkdir(parents=True)

    baseline_commit = ""
    tracked = tracked_head_inputs(source_root, paths)
    overlays: list[dict[str, Any]] = []
    if tracked:
        baseline_commit = must_run(["git", "rev-parse", "HEAD"], cwd=source_root)
        archive = subprocess.run(
            ["git", "archive", "--format=tar", "HEAD", "--", *tracked],
            cwd=source_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if archive.returncode:
            error = archive.stderr.decode("utf-8", errors="replace")
            raise RuntimeError(f"Could not archive tracked HEAD inputs:\n{error}")
        extract_archive_safely(archive.stdout, workspace)

    for source in paths:
        relative = source.relative_to(source_root)
        destination = workspace / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        base_sha256 = sha256_file(destination) if destination.is_file() else None
        current_sha256 = sha256_file(source)
        shutil.copy2(source, destination)
        overlays.append({
            "path": relative.as_posix(),
            "head_sha256": base_sha256,
            "working_sha256": current_sha256,
            "changed_or_untracked": base_sha256 != current_sha256,
        })
    marker.write_text(
        json.dumps({
            "format": "openrc-rcv-linux-build-workspace-v1",
            "input_sha256": digest,
            "baseline_commit": baseline_commit,
        }, indent=2)
        + "\n",
        encoding="utf-8",
    )
    return {"baseline_commit": baseline_commit or None, "tracked_head_paths": tracked, "overlays": overlays}


def git_info(source_root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    try:
        completed = run(["git", "rev-parse", "HEAD"], cwd=source_root)
        if completed.returncode == 0:
            result["head"] = completed.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return result


def default_godot(source_root: Path) -> Path:
    return source_root / ".tools/Godot_v4.7.2-stable_linux.x86_64"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=SOURCE_ROOT, help="shared repository root visible to WSL")
    parser.add_argument("--workspace", type=Path, help="isolated Linux build workspace outside the source repository")
    parser.add_argument("--out", type=Path, help="evidence directory (defaults under repository tmp/)")
    parser.add_argument("--godot", type=Path, help="existing Linux Godot 4.7.2 binary")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()

    if sys.platform != "linux":
        parser.error("Run this verifier inside Linux/WSL; it does not invoke wsl.exe or alter Windows build tools.")
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")

    source_root = args.source_root.expanduser().resolve()
    if not source_root.is_dir() or not (source_root / NATIVE_REL / "build.py").is_file():
        parser.error(f"--source-root does not contain the native build: {source_root}")

    # Never permit the temporary builder or artifact destination to land in
    # the shared checkout or its .tools cache.
    default_workspace_parent = Path(tempfile.gettempdir()) / "openrc-rcv-native-linux"
    workspace_parent = ensure_outside_source(default_workspace_parent, source_root, "default workspace")
    inputs = source_inputs(source_root)
    snapshot_sha256, input_hashes = input_digest(source_root, inputs)
    workspace = args.workspace or (workspace_parent / snapshot_sha256[:16])
    workspace = ensure_outside_source(workspace, source_root, "build workspace")
    output_dir = args.out.expanduser().resolve() if args.out else (
        source_root / "tmp/rcv-native-linux" / f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{snapshot_sha256[:12]}"
    )
    shared_tool_root = source_root / ".tools/native-ground-vehicle"
    if output_dir == shared_tool_root.resolve() or output_dir.is_relative_to(shared_tool_root.resolve()):
        parser.error("--out cannot target the shared .tools/native-ground-vehicle cache")
    if output_dir == workspace or output_dir.is_relative_to(workspace):
        parser.error("--out must be separate from the isolated build workspace")

    lock_path = source_root / NATIVE_REL / "toolchain-lock.json"
    lock: dict[str, Any] = json.loads(lock_path.read_text(encoding="utf-8"))
    platform_lock = lock["linux"]
    if platform.machine() != "x86_64":
        raise SystemExit(f"Linux native build is locked to x86_64; found {platform.machine()}.")
    compiler_version = must_run(["g++", "-dumpfullversion", "-dumpversion"])
    if compiler_version != platform_lock["compiler_version"]:
        raise SystemExit(
            f"Locked g++ is {platform_lock['compiler_version']}, but WSL reports {compiler_version}."
        )

    godot = (args.godot or default_godot(source_root)).expanduser().resolve()
    if not godot.is_file():
        raise SystemExit(f"Linux Godot binary not found: {godot}; pass --godot PATH if it is elsewhere.")
    godot_version = must_run([str(godot), "--headless", "--version"], timeout=30).splitlines()[-1]
    if godot_version != lock["godot"]["version"]:
        raise SystemExit(f"Locked Godot is {lock['godot']['version']}, but the binary reports {godot_version}.")

    source_snapshot = copy_snapshot(source_root, workspace, inputs, snapshot_sha256)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_library = output_dir / "libopenrc_ground_vehicle.so"
    build_script = workspace / NATIVE_REL / "build.py"
    command = [
        sys.executable,
        str(build_script),
        "--jobs",
        str(args.jobs),
        "--output",
        str(output_library),
        "--godot",
        str(godot),
    ]
    started = datetime.now(timezone.utc).isoformat()
    result: subprocess.CompletedProcess[str]
    try:
        result = run(command, cwd=workspace, timeout=1800)
        build_output = result.stdout
        return_code = result.returncode
    except subprocess.TimeoutExpired as exc:
        timed_out_output = exc.stdout or ""
        if isinstance(timed_out_output, bytes):
            timed_out_output = timed_out_output.decode("utf-8", errors="replace")
        build_output = timed_out_output + "\nBuild timed out after 1800 seconds.\n"
        return_code = 124

    tool_root = workspace / ".tools/native-ground-vehicle"
    receipt_path = tool_root / "build-receipt.linux.json"
    receipt: dict[str, Any] | None = None
    if receipt_path.is_file():
        try:
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            receipt = None
    library_sha256 = sha256_file(output_library) if output_library.is_file() else None
    smoke_passed = "Verified GDExtension load and PackedFloat64Array round-trip." in build_output
    parity_passed = "OPENRC_NATIVE_PARITY_OK" in build_output
    report: dict[str, Any] = {
        "format": "openrc-rcv-linux-native-verification-v1",
        "started_utc": started,
        "finished_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "WSL Ubuntu x86_64 build from a sparse git archive of HEAD paths plus exact working-file overlays in an isolated workspace; not a full repository clone or CI run.",
        "source_root": str(source_root),
        "source_git": git_info(source_root),
        "snapshot_input_sha256": snapshot_sha256,
        "snapshot_inputs": input_hashes,
        "source_snapshot": source_snapshot,
        "workspace": str(workspace),
        "host": {
            "distribution": must_run(["bash", "-lc", ". /etc/os-release; printf '%s %s' \"$NAME\" \"$VERSION_ID\""]),
            "kernel": must_run(["uname", "-a"]),
            "architecture": platform.machine(),
            "gxx_version": compiler_version,
            "gxx_banner": must_run(["g++", "--version"]).splitlines()[0],
            "python": sys.version.split()[0],
            "godot": godot_version,
            "godot_path": str(godot),
        },
        "lock": {
            "sha256": sha256_file(lock_path),
            "linux_compiler_version": platform_lock["compiler_version"],
            "linux_floating_point_flags": platform_lock["floating_point_flags"],
            "godot_version": lock["godot"]["version"],
            "godot_cpp_commit": lock["godot_cpp"]["commit"],
            "scons_version": lock["scons"]["version"],
        },
        "command": command,
        "exit_code": return_code,
        "smoke_passed": smoke_passed,
        "parity_passed": parity_passed,
        "library_path": str(output_library),
        "library_sha256": library_sha256,
        "isolated_build_receipt": receipt,
        "build_output": build_output,
    }
    report_path = output_dir / "verification.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "build.log").write_text(build_output, encoding="utf-8")
    print(f"Wrote Linux native verification report: {report_path}")
    if return_code or not library_sha256 or not smoke_passed or not parity_passed:
        print(build_output, file=sys.stderr)
        return return_code or 1
    print(f"Linux native build, Godot load, and parity passed: {output_library}")
    print(f"SHA-256: {library_sha256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
