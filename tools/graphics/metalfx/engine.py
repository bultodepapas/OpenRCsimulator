#!/usr/bin/env python3
"""Pinned, isolated macOS MetalFX engine intake; never changes the product getter.

Python 3.11+, Git; native builds additionally require macOS/ARM64 and SCons 4.10.1.
Source intake is also usable on Windows/Linux. No downloads or global installs.
"""
from __future__ import annotations

import argparse
import contextlib
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
ZSTANDARD_VERSION = "0.25.0"
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


def archive_catalog(archive: Path, expected: str | None = None,
                    prefix: str | None = None) -> dict[str, str]:
    expected = SOURCE_SHA256 if expected is None else expected
    prefix = SOURCE_PREFIX if prefix is None else prefix
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
    env = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}
    env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    result = subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(directory), *arguments],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"git {arguments[0]} failed: {result.stderr.decode(errors='replace')[:2000]}")


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
    if source.is_symlink() or not source.is_dir():
        raise ValueError("Engine source must be an ordinary directory")
    for name, identity in expected.items():
        path = source / name
        if (any(parent.is_symlink() for parent in path.parents if parent.is_relative_to(source))
                or path.is_symlink() or not path.is_file() or sha256(path) != identity):
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


@contextlib.contextmanager
def frozen_inputs(archive: Path, patches: list[Path], scratch: Path):
    """Hash, inspect, apply and extract the same private input copies."""
    with tempfile.TemporaryDirectory(prefix="metalfx-inputs-", dir=scratch) as temporary:
        root = Path(temporary)
        frozen_archive = root / "source.zip"
        shutil.copyfile(archive, frozen_archive)
        frozen_patches = []
        for index, patch in enumerate(patches):
            directory = root / str(index)
            directory.mkdir()
            frozen = directory / patch.name
            frozen.write_bytes(patch.read_bytes())
            frozen_patches.append(frozen)
        yield frozen_archive, frozen_patches


def prepare(archive: Path, output: Path, patches: list[Path]) -> dict:
    if output.exists():
        raise ValueError("Intake output must be a fresh directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    with frozen_inputs(archive, patches, output.parent) as (frozen_archive, frozen_patches):
        return _prepare(frozen_archive, output, frozen_patches)


def _prepare(archive: Path, output: Path, patches: list[Path]) -> dict:
    expected = expected_catalog(archive, patches, output.parent)
    output.mkdir()
    source = output / "source"
    source.mkdir()
    # The pinned hash and the complete member inventory are checked before writing.
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            if member.is_dir():
                continue
            if not member.filename.startswith(SOURCE_PREFIX + "/"):
                raise ValueError("Source archive has an unexpected root")
            name = safe_path(member.filename[len(SOURCE_PREFIX) + 1:])
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
    with frozen_inputs(archive, patches, output.parent) as (frozen_archive, frozen_patches):
        return _verify_intake(frozen_archive, output, frozen_patches, strict)


def _verify_intake(archive: Path, output: Path, patches: list[Path], strict: bool) -> dict:
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
    # One fresh source per target. Build-generated source cannot become an
    # unrecorded input to another target (including after an interrupted build).
    if any(output.glob("build-*.json")):
        raise ValueError("Each target requires a fresh intake")
    intake = verify_intake(archive, output, patches, strict=True)
    import SCons
    import zstandard
    if SCons.__version__ != SCONS_VERSION or zstandard.__version__ != ZSTANDARD_VERSION:
        raise ValueError(f"Build requires SCons {SCONS_VERSION} and zstandard {ZSTANDARD_VERSION}")
    build_source = output / f"build-source-{target}"
    if build_source.exists():
        raise ValueError("Build source already exists; use a fresh intake")
    shutil.copytree(output / "source", build_source, ignore=shutil.ignore_patterns(".git"))
    expected = expected_catalog(archive, patches, output.parent)
    verify_source(build_source, expected)
    sdk = capture("xcrun", "--show-sdk-path")
    command = [sys.executable, "-m", "SCons", f"-j{jobs}", "platform=macos", "arch=arm64",
               f"target={target}", "metal=yes", "vulkan=no", "opengl3=yes", "d3d12=no",
               "debug_symbols=no", "optimize=speed", "lto=none", "accesskit=no",
               "generate_bundle=no", f"MACOS_SDK_PATH={sdk}",
               f"cxxflags=-isystem {sdk}/usr/include/c++/v1"]
    controlled = ("CC", "CXX", "CCFLAGS", "CXXFLAGS", "CFLAGS", "LDFLAGS", "SCONSFLAGS",
                  "CPATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT", "ARCHFLAGS",
                  "MACOSX_DEPLOYMENT_TARGET", "CCACHE", "CUSTOM_MODULES", "GODOT_VERSION_STATUS", "BUILD_NAME",
                  "OSXCROSS_ROOT", "APPLE_LLVM_CROSS", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR")
    build_env = dict(os.environ)
    for name in controlled:
        build_env.pop(name, None)
    for name in list(build_env):
        if name.startswith("GIT_"):
            build_env.pop(name)
    # xcrun tools are selected explicitly by the pinned native platform path;
    # do not let a Homebrew/cross clang shadow the compiler in the receipt.
    build_env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    build_env.update(GODOT_VERSION_STATUS="beta2", BUILD_NAME="openrc_metalfx")
    result = {"schema": SCHEMA, "intake": intake, "target": target, "command": command,
              "sdk_path": sdk, "sdk_version": capture("xcrun", "--show-sdk-version"),
              "clang": capture("xcrun", "clang", "--version"),
              "host_os": capture("sw_vers", "-productVersion"), "process_arch": platform.machine(),
              "controlled_environment": {name: build_env.get(name) for name in controlled},
              "path": build_env.get("PATH"),
              "scons": SCons.__version__, "zstandard": zstandard.__version__, "python": sys.version,
              "deployment_target": "13.0 (pinned ARM64 platform defaults)",
              "hardware_qualification": "not_run", "status": "running"}
    receipt_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    with log_path.open("wb") as log:
        completed = subprocess.run(command, cwd=build_source, env=build_env,
                                   stdout=log, stderr=subprocess.STDOUT)
    result.update(returncode=completed.returncode, status="built" if completed.returncode == 0 else "failed",
                  log_sha256=sha256(log_path))
    verify_intake(archive, output, patches, strict=True)
    verify_source(build_source, expected, strict=False)
    artifact = build_source / "bin" / f"godot.macos.{target}.arm64"
    result["artifacts"] = []
    if artifact.is_file():
        architectures = capture("lipo", "-archs", str(artifact)).split()
        result["artifacts"] = [{"name": artifact.name, "sha256": sha256(artifact),
                                "bytes": artifact.stat().st_size, "architectures": architectures}]
        if architectures != ["arm64"]:
            result["status"] = "unexpected_architecture"
    if completed.returncode == 0 and not result["artifacts"]:
        result["status"] = "missing_artifact"
    receipt_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if result["status"] != "built":
        raise RuntimeError(f"Native build {result['status']}; see {log_path}")
    return result


def verify_pair(archive: Path, editor: Path, template: Path, patches: list[Path]) -> dict:
    builds = []
    for directory, target in ((editor, "editor"), (template, "template_release")):
        intake = verify_intake(archive, directory, patches)
        build_receipt = json.loads((directory / f"build-{target}.json").read_text(encoding="utf-8"))
        if (build_receipt.get("schema") != SCHEMA or build_receipt.get("status") != "built"
                or build_receipt.get("target") != target or build_receipt.get("intake") != intake):
            raise ValueError("Pair contains an incomplete or mismatched build")
        artifacts = build_receipt.get("artifacts", [])
        expected_name = f"godot.macos.{target}.arm64"
        if len(artifacts) != 1 or artifacts[0].get("name") != expected_name:
            raise ValueError("Pair requires the exact named editor and release template")
        artifact = directory / f"build-source-{target}" / "bin" / expected_name
        if (artifact.is_symlink() or not artifact.is_file() or sha256(artifact) != artifacts[0].get("sha256")
                or artifact.stat().st_size != artifacts[0].get("bytes")
                or artifacts[0].get("architectures") != ["arm64"]):
            raise ValueError("Pair artifact identity changed")
        if sha256(directory / f"build-{target}.log") != build_receipt.get("log_sha256"):
            raise ValueError("Pair build log identity changed")
        builds.append(build_receipt)
    keys = ("intake", "sdk_path", "sdk_version", "clang", "host_os", "process_arch", "scons", "zstandard", "python",
            "deployment_target", "controlled_environment", "path")
    if any(any(key not in receipt for key in keys) for receipt in builds):
        raise ValueError("Pair lacks required toolchain facts")
    if any(builds[0].get(key) != builds[1].get(key) for key in keys):
        raise ValueError("Editor/template source or toolchain differs")
    commands = [[arg for arg in receipt["command"] if not arg.startswith(("-j", "target="))]
                for receipt in builds]
    if commands[0] != commands[1]:
        raise ValueError("Editor/template build flags differ")
    return {"schema": SCHEMA, "status": "pair_verified", "source_commit": COMMIT,
            "build_receipts": [sha256(editor / "build-editor.json"), sha256(template / "build-template_release.json")],
            "artifacts": [receipt["artifacts"][0] for receipt in builds],
            "hardware_qualification": "not_run", "public_distribution": "deferred"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "verify", "build", "pair"))
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--patch", type=Path, action="append", default=[])
    parser.add_argument("--target", choices=("editor", "template_release"), default="editor")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--template", type=Path, help="second pristine intake for pair verification")
    args = parser.parse_args()
    if args.jobs < 1 or args.jobs > 32:
        parser.error("--jobs must be between 1 and 32")
    if args.operation == "prepare":
        result = prepare(args.archive, args.out, args.patch)
    elif args.operation == "verify":
        result = verify_intake(args.archive, args.out, args.patch)
    elif args.operation == "build":
        result = build(args.archive, args.out, args.patch, args.target, args.jobs)
    else:
        if args.template is None:
            parser.error("pair requires --template")
        result = verify_pair(args.archive, args.out, args.template, args.patch)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
