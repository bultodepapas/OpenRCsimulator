#!/usr/bin/env python3
"""Explicit local MetalFX engine identity for Mac native research.

The caller supplies independent binary and version pins.  The retained intake
and build receipt are checked for consistency; they are not an attestation of
who built the executable or a hardware, product, or distribution qualification.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tools/graphics/metalfx/engine.py"
SOURCE_COMMIT = "cafc17a192acf67903910a68aeb3c076c0907a4b"
GODOT_CPP_COMMIT = "507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"
OFFICIAL_VERSION = "4.8.beta2.official.cafc17a19"
OFFICIAL_ARM64_SHA256 = "2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80"
RESEARCH_CLI = "4.8.beta2.openrc_metalfx"
RESEARCH_RUNTIME = "4.8-beta2 (openrc_metalfx)"
SCOPE = "source-editor-local-custom-engine-research-v1"
APPLE_CLANG = "Apple clang version 21.0.0 (clang-2100.3.34.2)"
MAX_API_BYTES = 64 * 1024 * 1024
CONTROLLED = ("CC", "CXX", "CCFLAGS", "CXXFLAGS", "CFLAGS", "LDFLAGS", "SCONSFLAGS",
              "CPATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT", "ARCHFLAGS",
              "MACOSX_DEPLOYMENT_TARGET", "CCACHE", "CUSTOM_MODULES", "GODOT_VERSION_STATUS", "BUILD_NAME",
              "OSXCROSS_ROOT", "APPLE_LLVM_CROSS", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR")


class _Once(argparse.Action):
    def __call__(self, parser: argparse.ArgumentParser, namespace: argparse.Namespace,
                 value: object, option_string: str | None = None) -> None:
        if getattr(namespace, self.dest, None) is not None:
            parser.error(f"{option_string} may be specified only once")
        setattr(namespace, self.dest, value)


def add_arguments(parser: argparse.ArgumentParser) -> None:
    group = parser.add_argument_group("explicit local MetalFX research engine")
    group.add_argument("--research-engine-sha256", action=_Once, help="independently selected exact editor SHA-256")
    group.add_argument("--research-engine-cli-version", action=_Once, help="independently selected exact --version output")
    group.add_argument("--research-engine-runtime-version", action=_Once, help="independently selected exact runtime display")
    group.add_argument("--research-engine-build-receipt", action=_Once, type=Path, help="original build-editor.json")
    group.add_argument("--research-engine-archive", action=_Once, type=Path, help="pinned upstream source ZIP")
    group.add_argument("--research-engine-extension-api", action=_Once, type=Path,
                       help="4.7 bindings API JSON in the clean pinned godot-cpp checkout")
    group.add_argument("--research-engine-reference-godot", action=_Once, type=Path,
                       help="independently pinned official macOS Godot editor for the 4.8 API comparison")
    group.add_argument("--research-engine-patch", type=Path, action="append", default=[],
                       help="exact source patch, in build order; repeat")


def selection_from_args(args: argparse.Namespace) -> dict[str, Any] | None:
    names = ("research_engine_sha256", "research_engine_cli_version", "research_engine_runtime_version",
             "research_engine_build_receipt", "research_engine_archive", "research_engine_extension_api",
             "research_engine_reference_godot", "research_engine_patch")
    values = [getattr(args, name, None) for name in names]
    if not any(values):
        return None
    if any(not value for value in values):
        raise ValueError("All local research-engine pins, receipt, archive, official reference and ordered patches are required")
    digest, cli, runtime, receipt, archive, extension_api, reference, patches = values
    reject_dyld_environment()
    if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
        raise ValueError("Research engine SHA-256 must be 64 lowercase hexadecimal digits")
    if cli != RESEARCH_CLI or runtime != RESEARCH_RUNTIME:
        raise ValueError("Research engine versions do not match the supported local build identity")
    if not isinstance(patches, list) or any(not isinstance(p, Path) for p in patches):
        raise ValueError("Research engine patches must be explicit paths")
    paths = [str(p.expanduser().absolute()) for p in patches]
    if len(paths) != len(set(paths)):
        raise ValueError("Research engine patches must be distinct and ordered")
    return {"sha256": digest, "cli_version": cli, "runtime_version": runtime,
            "receipt": str(Path(receipt).expanduser().absolute()),
            "archive": str(Path(archive).expanduser().absolute()),
            "extension_api": str(Path(extension_api).expanduser().absolute()),
            "reference_godot": str(Path(reference).expanduser().absolute()), "patches": paths}


def reject_dyld_environment() -> None:
    if any(name.startswith("DYLD_") for name in os.environ):
        raise ValueError("Local research engine requires a parent environment without DYLD_* overrides")


def clean_child_environment() -> dict[str, str]:
    """Ordinary research children never inherit loader or sanitizer overrides."""
    return {name: value for name, value in os.environ.items()
            if not name.startswith("DYLD_") and name not in {"ASAN_OPTIONS", "UBSAN_OPTIONS"}}


@contextmanager
def clean_process_environment():
    """For a synchronous checked-runner API which does not accept an env map."""
    keys = {name for name in os.environ if name.startswith("DYLD_") or name in {"ASAN_OPTIONS", "UBSAN_OPTIONS"}}
    saved = {name: os.environ.pop(name) for name in keys}
    try:
        yield
    finally:
        for name in list(os.environ):
            if name.startswith("DYLD_") or name in {"ASAN_OPTIONS", "UBSAN_OPTIONS"}:
                os.environ.pop(name, None)
        os.environ.update(saved)


def _sha(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Missing or redirected research engine input: {path}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _json(path: Path) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 2 * 1024 * 1024:
        raise ValueError(f"Missing, redirected or oversized engine receipt: {path}")
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate engine receipt key: {key}")
            result[key] = value
        return result
    def invalid(value: str) -> None:
        raise ValueError(f"Non-finite engine receipt value: {value}")
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique, parse_constant=invalid)
    if not isinstance(value, dict):
        raise ValueError("Engine build receipt must be a JSON object")
    return value


def _helper() -> Any:
    spec = importlib.util.spec_from_file_location("openrc_metalfx_engine_identity", HELPER)
    if spec is None or spec.loader is None:
        raise ValueError("Cannot load the pinned MetalFX intake helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _git_text(checkout: Path, *args: str) -> str:
    env = {name: value for name, value in clean_child_environment().items() if not name.startswith("GIT_")}
    env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_OPTIONAL_LOCKS="0",
               GIT_TERMINAL_PROMPT="0")
    try:
        return subprocess.run(["git", "-C", str(checkout), *args], check=True, capture_output=True,
                              text=True, timeout=30, env=env).stdout.strip()
    except subprocess.SubprocessError as error:
        raise ValueError(f"Cannot verify pinned godot-cpp checkout: {error}") from error


def extension_api_identity(api: Path, lock: dict) -> dict[str, str]:
    """Bind the 4.7 API file to the exact clean, locked godot-cpp commit."""
    if (api.name != "extension_api-4-7.json" or api.parent.name != "gdextension"
            or api.is_symlink() or api.parent.is_symlink() or not api.is_file()
            or lock.get("godot_cpp", {}).get("commit") != GODOT_CPP_COMMIT):
        raise ValueError("Research engine requires the pinned godot-cpp 4.7 API file")
    checkout = api.parent.parent
    if checkout.is_symlink() or not checkout.is_dir():
        raise ValueError("Research godot-cpp checkout is missing or redirected")
    before = _sha(api)
    root = _git_text(checkout, "rev-parse", "--show-toplevel")
    head = _git_text(checkout, "rev-parse", "--verify", "HEAD")
    status = _git_text(checkout, "status", "--porcelain", "--untracked-files=no")
    expected_blob = _git_text(checkout, "rev-parse", f"{GODOT_CPP_COMMIT}:gdextension/extension_api-4-7.json")
    observed_blob = _git_text(checkout, "hash-object", "--no-filters", str(api))
    if (Path(root).resolve() != checkout.resolve() or head != GODOT_CPP_COMMIT or status
            or re.fullmatch(r"[0-9a-f]{40}", expected_blob) is None or observed_blob != expected_blob
            or _sha(api) != before):
        raise ValueError("Godot-cpp 4.7 API checkout, commit, or blob differs from the lock")
    return {"checkout": str(checkout.resolve()), "commit": head, "blob": expected_blob, "sha256": before}


def _reference_api_dump(path: Path) -> dict[str, Any]:
    """Read a fresh official 4.8 API dump, with a bound independent of the receipt."""
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= MAX_API_BYTES:
        raise ValueError("Official 4.8 extension API dump is missing, redirected or oversized")
    with path.open("rb") as stream:
        raw = stream.read(MAX_API_BYTES + 1)
    if len(raw) > MAX_API_BYTES:
        raise ValueError("Official 4.8 extension API dump exceeds its size limit")
    try:
        data = json.loads(raw)
        header = data["header"]
        if (not isinstance(header, dict) or type(header.get("version_major")) is not int
                or type(header.get("version_minor")) is not int or type(header.get("version_patch")) is not int
                or (header["version_major"], header["version_minor"], header["version_patch"]) != (4, 8, 0)
                or header.get("version_status") != "beta2" or header.get("version_build") != "official"
                or header.get("precision") != "single"
                or any(not isinstance(data.get(name), list) or not data[name] for name in (
                    "global_constants", "global_enums", "utility_functions", "builtin_classes",
                    "classes", "singletons", "native_structures"))):
            raise ValueError("header or API collections differ")
    except (KeyError, TypeError, json.JSONDecodeError, UnicodeDecodeError, ValueError) as error:
        raise ValueError(f"Invalid official 4.8 extension API dump: {error}") from error
    return {"version": "4.8", "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}


def _reject_api_diagnostics(output: str) -> None:
    # The pinned validator has printed these incompatibilities with exit status 0.
    if re.search(r"Validate\s+extension\s+JSON:|\b(?:SCRIPT\s+|SHADER\s+)?ERROR(?:\s*:|\b)",
                 output, flags=re.IGNORECASE):
        raise ValueError("Research engine extension API check emitted an incompatibility or engine error")


def identify(godot: Path, lock: dict, selection: dict[str, Any], *,
             architectures: Callable[[Path], list[str]], output: Callable[..., str]) -> dict[str, Any]:
    """Recheck the caller's pins and the real retained local build inputs/outputs."""
    if not isinstance(selection, dict) or set(selection) != {
            "sha256", "cli_version", "runtime_version", "receipt", "archive", "extension_api", "reference_godot", "patches"}:
        raise ValueError("Malformed local research-engine selection")
    checked = selection_from_args(argparse.Namespace(
        research_engine_sha256=selection["sha256"], research_engine_cli_version=selection["cli_version"],
        research_engine_runtime_version=selection["runtime_version"],
        research_engine_build_receipt=Path(selection["receipt"]), research_engine_archive=Path(selection["archive"]),
        research_engine_extension_api=Path(selection["extension_api"]),
        research_engine_reference_godot=Path(selection["reference_godot"]),
        research_engine_patch=[Path(p) for p in selection["patches"]]))
    if checked != selection or lock.get("godot", {}).get("version") != OFFICIAL_VERSION \
            or lock["godot"].get("extension_api") != "4.7":
        raise ValueError("Research engine selection or pinned upstream ABI differs")
    receipt_path, archive, extension_api = (Path(selection[name]) for name in ("receipt", "archive", "extension_api"))
    reference = Path(selection["reference_godot"])
    patches = [Path(p) for p in selection["patches"]]
    executable = godot.absolute()
    if executable.is_symlink() or not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("Research engine must be an ordinary executable")
    intake_root = receipt_path.parent
    expected_executable = intake_root / "build-source-editor/bin/godot.macos.editor.arm64"
    if receipt_path.name != "build-editor.json" or executable.resolve() != expected_executable.resolve() \
            or expected_executable.is_symlink() or expected_executable.parent.is_symlink():
        raise ValueError("Research engine must be the editor artifact selected by its build receipt")
    log = intake_root / "build-editor.log"
    intake_path = intake_root / "intake.json"
    if reference.is_symlink() or not reference.is_file() or not os.access(reference, os.X_OK):
        raise ValueError("Official reference Godot must be an ordinary executable")
    inputs = [receipt_path, intake_path, archive, extension_api, reference, *patches, log, HELPER, Path(__file__), executable]
    before = {str(path): _sha(path) for path in inputs}
    if before[str(reference)] != OFFICIAL_ARM64_SHA256:
        raise ValueError("Official reference Godot differs from the independent macOS SHA-256 pin")
    receipt = _json(receipt_path)
    intake_record = _json(intake_path)
    helper = _helper()
    if helper.COMMIT != SOURCE_COMMIT or helper.SOURCE_SHA256 != before[str(archive)]:
        raise ValueError("Research engine upstream source pin differs")
    api_identity = extension_api_identity(extension_api, lock)
    if any(name == "core/extension" or name.startswith("core/extension/") for name in helper.patch_paths(patches)):
        raise ValueError("Research engine patches may not alter the pinned core/extension C interface")
    try:
        intake = helper.verify_intake(archive, intake_root, patches)
    except (RuntimeError, subprocess.SubprocessError) as error:
        raise ValueError(f"Research engine intake verification failed: {error}") from error
    if (receipt.get("schema") != helper.SCHEMA or receipt.get("status") != "built"
            or type(receipt.get("returncode")) is not int or receipt["returncode"] != 0
            or receipt.get("target") != "editor" or receipt.get("intake") != intake or intake_record != intake
            or receipt.get("process_arch") != "arm64"
            or receipt.get("log_sha256") != before[str(log)]
            or receipt.get("hardware_qualification") != "not_run"):
        raise ValueError("Research engine build receipt is incomplete or inconsistent")
    artifacts = receipt.get("artifacts")
    if (not isinstance(artifacts, list) or len(artifacts) != 1 or not isinstance(artifacts[0], dict)
            or type(artifacts[0].get("bytes")) is not int
            or artifacts[0] != {"name": expected_executable.name, "sha256": selection["sha256"],
                                "bytes": executable.stat().st_size, "architectures": ["arm64"]}
            or before[str(executable)] != selection["sha256"]):
        raise ValueError("Research engine artifact differs from its independent binary pin")
    environment = receipt.get("controlled_environment")
    controlled = dict.fromkeys(CONTROLLED)
    controlled.update(GODOT_VERSION_STATUS="beta2", BUILD_NAME="openrc_metalfx")
    sdk = receipt.get("sdk_path")
    command = receipt.get("command")
    if (environment != controlled or receipt.get("path") != "/usr/bin:/bin:/usr/sbin:/sbin"
            or receipt.get("sdk_version") != "27.0" or receipt.get("scons") != helper.SCONS_VERSION
            or receipt.get("zstandard") != helper.ZSTANDARD_VERSION
            or not isinstance(receipt.get("clang"), str) or receipt["clang"].splitlines()[0] != APPLE_CLANG
            or not isinstance(sdk, str) or not sdk.startswith("/") or "\n" in sdk
            or not isinstance(command, list) or len(command) != 18
            or not isinstance(command[0], str) or not command[0].startswith("/")
            or command[1:3] != ["-m", "SCons"] or not isinstance(command[3], str)
            or re.fullmatch(r"-j(?:[1-9]|[12][0-9]|3[0-2])", command[3]) is None
            or command[4:] != ["platform=macos", "arch=arm64", "target=editor", "metal=yes", "vulkan=no",
                               "opengl3=yes", "d3d12=no", "debug_symbols=no", "optimize=speed", "lto=none",
                               "accesskit=no", "generate_bundle=no", f"MACOS_SDK_PATH={sdk}",
                               f"cxxflags=-isystem {sdk}/usr/include/c++/v1"]):
        raise ValueError("Research engine build settings differ from the pinned local route")
    try:
        expected = helper.expected_catalog(archive, patches, intake_root.parent)
    except (RuntimeError, subprocess.SubprocessError) as error:
        raise ValueError(f"Research engine source catalog reconstruction failed: {error}") from error
    if (type(intake.get("source_files")) is not int or intake["source_files"] != len(expected)
            or intake.get("source_url") != helper.SOURCE_URL
            or intake.get("native_build") != "not_run" or intake.get("hardware_qualification") != "not_run"):
        raise ValueError("Research engine intake catalog or scope differs")
    helper.verify_source(intake_root / "build-source-editor", expected, strict=False)
    try:
        actual_architectures = architectures(executable)
        actual_version = output([str(executable), "--version"])
        reference_architectures = architectures(reference)
        reference_version = output([str(reference), "--version"])
    except subprocess.SubprocessError as error:
        raise ValueError(f"Research engine executable inspection failed: {error}") from error
    if actual_architectures != ["arm64"] or actual_version != selection["cli_version"]:
        raise ValueError("Research engine architecture or CLI version differs from its independent pin")
    if "arm64" not in reference_architectures or reference_version != OFFICIAL_VERSION:
        raise ValueError("Official reference Godot architecture or version differs from its independent pin")
    try:
        with tempfile.TemporaryDirectory(prefix="openrc-godot-api-") as directory:
            api_dump = Path(directory) / "extension_api.json"
            dump_output = output([str(reference), "--headless", "--dump-extension-api"], cwd=directory)
            _reject_api_diagnostics(dump_output)
            compatibility = _reference_api_dump(api_dump)
            validation_output = output([str(executable), "--headless", "--validate-extension-api", str(api_dump)])
            _reject_api_diagnostics(validation_output)
            if _reference_api_dump(api_dump) != compatibility:
                raise ValueError("Official 4.8 extension API dump changed during validation")
    except subprocess.SubprocessError as error:
        raise ValueError(f"Research engine 4.8 extension API compatibility check failed: {error}") from error
    if extension_api_identity(extension_api, lock) != api_identity:
        raise ValueError("Pinned extension API changed during validation")
    helper.verify_source(intake_root / "source", expected, strict=True)
    helper.verify_source(intake_root / "build-source-editor", expected, strict=False)
    if {str(path): _sha(path) for path in inputs} != before:
        raise ValueError("Research engine provenance changed during validation")
    return {"path": str(executable.resolve()), "version": actual_version, "sha256": selection["sha256"],
            "architectures": actual_architectures,
            "research_engine": {"scope": SCOPE, "selection": selection,
                                "runtime_version": selection["runtime_version"], "source_commit": SOURCE_COMMIT,
                                "source_catalog_sha256": intake["source_catalog_sha256"],
                                "build_receipt_sha256": before[str(receipt_path)],
                                "intake_sha256": before[str(intake_path)],
                                "source_archive_sha256": before[str(archive)],
                                "ordered_patches": [{"path": str(path), "sha256": before[str(path)]} for path in patches],
                                "binding_api_4_7": api_identity,
                                "compatibility_api_4_8": {**compatibility, "validation": "passed without diagnostics",
                                    "reference": {"path": str(reference.resolve()), "sha256": before[str(reference)],
                                                  "version": reference_version, "architectures": reference_architectures}},
                                "intake_helper_sha256": before[str(HELPER)],
                                "identity_helper_sha256": before[str(Path(__file__))],
                                "build_log_sha256": before[str(log)]}}
