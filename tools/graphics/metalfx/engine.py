#!/usr/bin/env python3
"""Pinned, isolated macOS MetalFX engine intake; never changes the product getter.

Python 3.11+, Git; native builds additionally require macOS/ARM64 and SCons 4.10.1.
Source intake is also usable on Windows/Linux. No downloads or global installs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

COMMIT = "cafc17a192acf67903910a68aeb3c076c0907a4b"
SOURCE_URL = f"https://codeload.github.com/godotengine/godot/zip/{COMMIT}"
SOURCE_SHA256 = "83cf257bc53427f2b1ea07015dbad298252c20546e916c5daa30a1cf78c45c1e"
SOURCE_PREFIX = f"godot-{COMMIT}"
SCONS_VERSION = "4.10.1"
HERE = Path(__file__).resolve().parent
SCHEMA = "openrc-metalfx-engine-v1"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def digest_catalog(catalog: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(catalog, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def safe_path(name: str) -> str:
    path = PurePosixPath(name)
    if (not name or "\\" in name or ":" in name or path.is_absolute()
            or any(part in (".", "..", ".git") for part in name.split("/"))
            or "//" in name):
        raise ValueError(f"Unsafe source path: {name!r}")
    return path.as_posix()


def archive_catalog(archive: Path, expected: str = SOURCE_SHA256,
                    prefix: str = SOURCE_PREFIX) -> dict[str, str]:
    if sha256(archive) != expected:
        raise ValueError("Source archive SHA-256 differs from the pin")
    result = {}
    folded = set()
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            if member.is_dir():
                continue
            if not member.filename.startswith(prefix + "/"):
                raise ValueError("Source archive has an unexpected root")
            name = safe_path(member.filename[len(prefix) + 1:])
            # A case collision is unsafe for the Windows intake as well as macOS.
            if name.casefold() in folded or (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f"Duplicate or symbolic-link archive member: {name}")
            folded.add(name.casefold())
            with package.open(member) as stream:
                result[name] = hashlib.file_digest(stream, "sha256").hexdigest()
    if not result:
        raise ValueError("Empty source archive")
    return result


def git(directory: Path, *arguments: str) -> None:
    env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(directory), *arguments],
                   env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def patch_paths(patches: list[Path]) -> set[str]:
    paths = set()
    for patch in patches:
        content = patch.read_text(encoding="utf-8")
        if re.search(r"^(?:rename |copy |.*file mode|GIT binary patch|Binary files)", content, re.M):
            raise ValueError("Only ordinary text patches are accepted")
        headers = re.findall(r"^(?:---|\+\+\+) (.+)$", content, re.M)
        if not headers:
            raise ValueError("Patch contains no text file headers")
        for name in headers:
            if name == "/dev/null":
                continue
            if not name.startswith(("a/", "b/")):
                raise ValueError("Patch must use a/ and b/ source paths")
            paths.add(safe_path(name[2:]))
    return paths


def expected_catalog(archive: Path, patches: list[Path], scratch: Path) -> dict[str, str]:
    catalog = archive_catalog(archive)
    paths = patch_paths(patches) if patches else set()
    with tempfile.TemporaryDirectory(prefix="metalfx-patch-", dir=scratch) as temporary:
        tree = Path(temporary)
        with zipfile.ZipFile(archive) as package:
            for name in paths & catalog.keys():
                target = tree / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(package.read(SOURCE_PREFIX + "/" + name))
        git(tree, "init", "--quiet")
        for patch in patches:
            git(tree, "apply", "--check", str(patch.resolve()))
            git(tree, "apply", str(patch.resolve()))
        for name in paths:
            target = tree / name
            if target.is_file():
                catalog[name] = sha256(target)
            else:
                catalog.pop(name, None)
    return catalog


def verify_source(source: Path, expected: dict[str, str], strict: bool = True) -> None:
    for name, identity in expected.items():
        path = source / name
        if path.is_symlink() or not path.is_file() or sha256(path) != identity:
            raise ValueError(f"Engine source drift: {name}")
    if strict:
        for directory, directories, files in os.walk(source, followlinks=False):
            directories[:] = [name for name in directories if name != ".git"]
            for name in directories + files:
                path = Path(directory) / name
                if path.is_symlink():
                    raise ValueError(f"Symbolic link in engine tree: {path}")
            for name in files:
                relative = (Path(directory) / name).relative_to(source).as_posix()
                if relative not in expected:
                    raise ValueError(f"Unexpected engine input: {relative}")


def prepare(archive: Path, output: Path, patches: list[Path]) -> dict:
    if output.exists():
        raise ValueError("Intake output must be a fresh directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    expected = expected_catalog(archive, patches, output.parent)
    output.mkdir()
    source = output / "source"
    source.mkdir()
    # The pinned hash and the complete member inventory are checked before writing.
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            if member.is_dir():
                continue
            name = member.filename[len(SOURCE_PREFIX) + 1:]
            target = source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with package.open(member) as incoming, target.open("wb") as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            if member.external_attr >> 16 & 0o111:
                target.chmod(0o755)
    git(source, "init", "--quiet")
    for patch in patches:
        git(source, "apply", "--check", str(patch.resolve()))
        git(source, "apply", str(patch.resolve()))
    verify_source(source, expected)
    result = {
        "schema": SCHEMA, "source_commit": COMMIT, "source_url": SOURCE_URL,
        "source_archive_sha256": sha256(archive),
        "patches": [{"name": patch.name, "sha256": sha256(patch)} for patch in patches],
        "source_catalog_sha256": digest_catalog(expected), "source_files": len(expected),
        "intake_helper_sha256": sha256(Path(__file__)),
        "native_build": "not_run", "hardware_qualification": "not_run",
    }
    (output / "intake.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def verify_intake(archive: Path, output: Path, patches: list[Path], strict: bool = True) -> dict:
    receipt = json.loads((output / "intake.json").read_text(encoding="utf-8"))
    expected = expected_catalog(archive, patches, output.parent)
    if (receipt.get("schema") != SCHEMA or receipt.get("source_commit") != COMMIT
            or receipt.get("source_archive_sha256") != SOURCE_SHA256
            or receipt.get("source_catalog_sha256") != digest_catalog(expected)
            or receipt.get("patches") != [{"name": p.name, "sha256": sha256(p)} for p in patches]
            or receipt.get("intake_helper_sha256") != sha256(Path(__file__))):
        raise ValueError("Intake receipt does not match the pinned inputs/helper")
    verify_source(output / "source", expected, strict=strict)
    return receipt


def capture(*command: str) -> str:
    return subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=30).stdout.strip()


def build(archive: Path, output: Path, patches: list[Path], target: str, jobs: int) -> dict:
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise ValueError("Native build requires an ARM64 macOS process")
    receipt_path = output / f"build-{target}.json"
    log_path = output / f"build-{target}.log"
    if receipt_path.exists() or log_path.exists():
        raise ValueError("Build receipt/log already exists; use a fresh intake for a new attempt")
    # Generated build products are admitted only after a successful strict intake.
    intake = verify_intake(archive, output, patches, strict=not any(output.glob("build-*.json")))
    if capture(sys.executable, "-m", "SCons", "--version").splitlines()[0] != f"SCons by Steven Knight et al.:":
        raise ValueError("Unexpected SCons version response")
    import SCons
    if SCons.__version__ != SCONS_VERSION:
        raise ValueError(f"SCons must be {SCONS_VERSION}")
    sdk = capture("xcrun", "--show-sdk-path")
    command = [sys.executable, "-m", "SCons", f"-j{jobs}", "platform=macos", "arch=arm64",
               f"target={target}", "metal=yes", "vulkan=no", "opengl3=yes", "d3d12=no",
               "debug_symbols=no", "optimize=speed", "lto=none", "accesskit=no", "use_sowrap=no",
               "generate_bundle=no", f"MACOS_SDK_PATH={sdk}"]
    result = {"schema": SCHEMA, "intake": intake, "target": target, "command": command,
              "sdk_path": sdk, "sdk_version": capture("xcrun", "--show-sdk-version"),
              "clang": capture("xcrun", "clang", "--version"),
              "host_os": capture("sw_vers", "-productVersion"), "process_arch": platform.machine(),
              "scons": SCons.__version__, "deployment_target": "13.0 (pinned ARM64 platform defaults)",
              "hardware_qualification": "not_run", "status": "running"}
    receipt_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    with log_path.open("wb") as log:
        completed = subprocess.run(command, cwd=output / "source", stdout=log, stderr=subprocess.STDOUT)
    result.update(returncode=completed.returncode, status="built" if completed.returncode == 0 else "failed",
                  log_sha256=sha256(log_path))
    verify_intake(archive, output, patches, strict=False)
    artifacts = sorted((output / "source" / "bin").glob(f"godot.macos.{target}.arm64*"))
    result["artifacts"] = [{"name": p.name, "sha256": sha256(p), "bytes": p.stat().st_size}
                           for p in artifacts if p.is_file()]
    if completed.returncode == 0 and not result["artifacts"]:
        result["status"] = "missing_artifact"
    receipt_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if result["status"] != "built":
        raise RuntimeError(f"Native build {result['status']}; see {log_path}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "verify", "build"))
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--patch", type=Path, action="append", default=[])
    parser.add_argument("--target", choices=("editor", "template_release"), default="editor")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1 or args.jobs > 32:
        parser.error("--jobs must be between 1 and 32")
    if args.operation == "prepare":
        result = prepare(args.archive, args.out, args.patch)
    elif args.operation == "verify":
        result = verify_intake(args.archive, args.out, args.patch)
    else:
        result = build(args.archive, args.out, args.patch, args.target, args.jobs)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
