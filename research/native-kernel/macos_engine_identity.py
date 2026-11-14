#!/usr/bin/env python3
"""Explicit local MetalFX engine identity for Mac native research.

The caller supplies independent binary and version pins.  The retained intake
and build receipt are checked for consistency; they are not an attestation of
who built the executable or a hardware, product, or distribution qualification.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tools/graphics/metalfx/engine.py"
SOURCE_COMMIT = "cafc17a192acf67903910a68aeb3c076c0907a4b"
OFFICIAL_VERSION = "4.8.beta2.official.cafc17a19"
RESEARCH_CLI = "4.8.beta2.openrc_metalfx"
RESEARCH_RUNTIME = "4.8-beta2 (openrc_metalfx)"
SCOPE = "source-editor-local-custom-engine-research-v1"
APPLE_CLANG = "Apple clang version 21.0.0 (clang-2100.3.34.2)"
CONTROLLED = ("CC", "CXX", "CCFLAGS", "CXXFLAGS", "CFLAGS", "LDFLAGS", "SCONSFLAGS",
              "CPATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT", "ARCHFLAGS",
              "MACOSX_DEPLOYMENT_TARGET", "CCACHE", "CUSTOM_MODULES", "GODOT_VERSION_STATUS", "BUILD_NAME",
              "OSXCROSS_ROOT", "APPLE_LLVM_CROSS", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR")


def add_arguments(parser: argparse.ArgumentParser) -> None:
    group = parser.add_argument_group("explicit local MetalFX research engine")
    group.add_argument("--research-engine-sha256", help="independently selected exact editor SHA-256")
    group.add_argument("--research-engine-cli-version", help="independently selected exact --version output")
    group.add_argument("--research-engine-runtime-version", help="independently selected exact runtime display")
    group.add_argument("--research-engine-build-receipt", type=Path, help="original build-editor.json")
    group.add_argument("--research-engine-archive", type=Path, help="pinned upstream source ZIP")
    group.add_argument("--research-engine-patch", type=Path, action="append", default=[],
                       help="exact source patch, in build order; repeat")


def selection_from_args(args: argparse.Namespace) -> dict[str, Any] | None:
    names = ("research_engine_sha256", "research_engine_cli_version", "research_engine_runtime_version",
             "research_engine_build_receipt", "research_engine_archive", "research_engine_patch")
    values = [getattr(args, name, None) for name in names]
    if not any(values):
        return None
    if any(not value for value in values):
        raise ValueError("All local research-engine pins, receipt, archive and ordered patches are required")
    digest, cli, runtime, receipt, archive, patches = values
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
            "archive": str(Path(archive).expanduser().absolute()), "patches": paths}


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


def identify(godot: Path, lock: dict, selection: dict[str, Any], *,
             architectures: Callable[[Path], list[str]], output: Callable[[list[str]], str]) -> dict[str, Any]:
    """Recheck the caller's pins and the real retained local build inputs/outputs."""
    if not isinstance(selection, dict) or set(selection) != {
            "sha256", "cli_version", "runtime_version", "receipt", "archive", "patches"}:
        raise ValueError("Malformed local research-engine selection")
    checked = selection_from_args(argparse.Namespace(
        research_engine_sha256=selection["sha256"], research_engine_cli_version=selection["cli_version"],
        research_engine_runtime_version=selection["runtime_version"],
        research_engine_build_receipt=Path(selection["receipt"]), research_engine_archive=Path(selection["archive"]),
        research_engine_patch=[Path(p) for p in selection["patches"]]))
    if checked != selection or lock.get("godot", {}).get("version") != OFFICIAL_VERSION \
            or lock["godot"].get("extension_api") != "4.7":
        raise ValueError("Research engine selection or pinned upstream ABI differs")
    receipt_path, archive = Path(selection["receipt"]), Path(selection["archive"])
    patches = [Path(p) for p in selection["patches"]]
    executable = godot.absolute()
    if executable.is_symlink() or not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("Research engine must be an ordinary executable")
    intake_root = receipt_path.parent
    expected_executable = intake_root / "build-source-editor/bin/godot.macos.editor.arm64"
    if receipt_path.name != "build-editor.json" or executable.resolve() != expected_executable.resolve() \
            or expected_executable.is_symlink():
        raise ValueError("Research engine must be the editor artifact selected by its build receipt")
    log = intake_root / "build-editor.log"
    inputs = [receipt_path, archive, *patches, log, HELPER, Path(__file__), executable]
    before = {str(path): _sha(path) for path in inputs}
    receipt = _json(receipt_path)
    helper = _helper()
    if helper.COMMIT != SOURCE_COMMIT or helper.SOURCE_SHA256 != before[str(archive)]:
        raise ValueError("Research engine upstream source pin differs")
    intake = helper.verify_intake(archive, intake_root, patches)
    if (receipt.get("schema") != helper.SCHEMA or receipt.get("status") != "built"
            or receipt.get("returncode") != 0 or receipt.get("target") != "editor"
            or receipt.get("intake") != intake or receipt.get("process_arch") != "arm64"
            or receipt.get("log_sha256") != before[str(log)]
            or receipt.get("hardware_qualification") != "not_run"):
        raise ValueError("Research engine build receipt is incomplete or inconsistent")
    artifacts = receipt.get("artifacts")
    if (not isinstance(artifacts, list) or len(artifacts) != 1 or not isinstance(artifacts[0], dict)
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
    expected = helper.expected_catalog(archive, patches, intake_root.parent)
    helper.verify_source(intake_root / "build-source-editor", expected, strict=False)
    actual_architectures = architectures(executable)
    actual_version = output([str(executable), "--version"])
    if actual_architectures != ["arm64"] or actual_version != selection["cli_version"]:
        raise ValueError("Research engine architecture or CLI version differs from its independent pin")
    if {str(path): _sha(path) for path in inputs} != before:
        raise ValueError("Research engine provenance changed during validation")
    return {"path": str(executable.resolve()), "version": actual_version, "sha256": selection["sha256"],
            "architectures": actual_architectures,
            "research_engine": {"scope": SCOPE, "selection": selection,
                                "runtime_version": selection["runtime_version"], "source_commit": SOURCE_COMMIT,
                                "source_catalog_sha256": intake["source_catalog_sha256"],
                                "build_receipt_sha256": before[str(receipt_path)],
                                "intake_helper_sha256": before[str(HELPER)],
                                "identity_helper_sha256": before[str(Path(__file__))],
                                "build_log_sha256": before[str(log)]}}
