#!/usr/bin/env python3
"""Verify and export an isolated, unqualified SDK 2.4 Windows/Vulkan candidate.

The default operation is read-only preflight. ``--package`` reuses product.py's
current-source snapshot, checked import and export, without changing the legacy
product or its cache. This does not establish a rendered dispatch or GPU support.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import build as native_build
import build_sdk24 as sdk_build
import product
import sdk24

sys.path.insert(0, str(ROOT / "tools/godot"))
from run_checked import inspect_log

SNAPSHOT = ROOT / "tmp/fsr24-product"
OUTPUT = ROOT / "dist/windows-fsr24-candidate"
CHECKS = ROOT / "tmp/godot-checks/fsr24-product"
ARCHIVES = ROOT / "tmp/fsr-sdk24-build-receipts"
SNAPSHOT_FORMAT = "openrc-fsr24-candidate-snapshot v1"
PACKAGE_FORMAT = "openrc-fsr24-candidate-package v1"
COMMON = ("experimental", "production_engine_unchanged", "godot_repository", "godot_commit", "version",
          "fidelityfx_sdk", "fsr_upscaler", "bundled_upscalers", "streamline", "platform", "graphics_api",
          "frame_generation_enabled", "sources", "integration", "sdk_intake", "engine_source", "amd_headers",
          "streamline_headers", "runtime", "licenses")
AMD_DLLS = {
    "amd_fidelityfx_loader_vk.dll": "Kits/FidelityFX/signedbin/amd_fidelityfx_loader_vk.dll",
    "amd_fidelityfx_upscaler_vk.dll": "Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_vk.dll",
}
AMD_NOTICES = {
    "AMD-FSR-SDK-2.4-LICENSE.md": "docs/license.md",
    "AMD-FidelityFX-kit-LICENSE.md": "Kits/FidelityFX/docs/license.md",
    "AMD-FSR-SDK-2.4-third-party.md": "3rdpartynotice.md",
}
PACKAGER_IMPORTS = {name: product.sha(HERE / name) for name in ("product.py", "product_sdk24.py")}


def _safe_file(path: Path) -> Path:
    path = Path(path)
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT.resolve()) or not path.is_file():
        raise RuntimeError(f"Receipt or report is missing or outside the workspace: {path}")
    for entry in (path, *path.parents):
        if entry == ROOT.parent:
            break
        if product.is_link(entry):
            raise RuntimeError(f"Linked receipt or report is not accepted: {entry}")
    return resolved


def _plain_name(name: str) -> bool:
    return isinstance(name, str) and bool(name) and "/" not in name and "\\" not in name and ":" not in name and name not in (".", "..")


def _sdk_receipt_valid(receipt: object) -> None:
    if not isinstance(receipt, dict):
        raise RuntimeError("Missing SDK intake identity")
    tag_check = receipt.get("tag_check")
    try:
        if (not isinstance(tag_check, dict) or set(tag_check) != {"live", "checked_utc"} or
                type(tag_check["live"]) is not bool or
                (tag_check["live"] and (not isinstance(tag_check["checked_utc"], str) or
                 datetime.fromisoformat(tag_check["checked_utc"]).utcoffset() is None)) or
                (not tag_check["live"] and tag_check["checked_utc"] is not None)):
            raise ValueError("invalid tag observation")
        files = {name: {"sha256": pin[0], "git_blob_sha1": pin[1]} for name, pin in sdk24.PINNED_FILES.items()}
        signature = {"status": "Valid", "type": "Authenticode", "subject": sdk24.SIGNER_SUBJECT,
                     "signer": sdk24.SIGNER, "timestamp_signer": sdk24.TIMESTAMP_SIGNER}
        signatures = {name: signature for name in sdk24.SIGNED_DLLS}
        if receipt != sdk24._receipt(files, signatures, tag_check):
            raise ValueError("intake metadata differs from pinned SDK")
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError(f"SDK intake receipt is invalid: {error}") from error


def _expected_sources() -> dict[str, str]:
    return {name: digest for name, _, digest, _ in (native_build.ARCHIVES[0], native_build.ARCHIVES[2])}


def _verify_pair_metadata(editor: dict, template: dict, engine: Path, *, current: bool) -> None:
    expected = {"experimental": True, "production_engine_unchanged": "4.8-beta1",
                "godot_repository": "https://github.com/NVIDIA-RTX/godot", "godot_commit": native_build.COMMIT,
                "fidelityfx_sdk": "2.4.0", "fsr_upscaler": "runtime_queried",
                "bundled_upscalers": ["3.1.6", "4.1.2"], "streamline": "2.11.1",
                "platform": "windows", "graphics_api": "vulkan", "frame_generation_enabled": False,
                "sources": _expected_sources()}
    for label, row in (("editor", editor), ("template_release", template)):
        if (row.get("experimental") is not True or row.get("frame_generation_enabled") is not False or
                any(row.get(key) != value for key, value in expected.items())):
            raise RuntimeError(f"{label} is not a pinned SDK 2.4 Windows/Vulkan candidate")
        if not isinstance(row.get("version"), str) or not row["version"]:
            raise RuntimeError(f"{label} lacks an engine version")
        command = row.get("build_command")
        required = {"platform=windows", f"target={label}", "arch=x86_64", "use_streamline=yes",
                    "d3d12=no", "angle=no", "accesskit=no", "winrt=no"}
        if not isinstance(command, list) or not all(isinstance(item, str) for item in command) or not required.issubset(command):
            raise RuntimeError(f"{label} build command is incomplete or has the wrong target")
        executable = engine / "bin" / f"godot.windows.{label}.x86_64.exe"
        if Path(str(row.get("executable", ""))).resolve() != executable.resolve():
            raise RuntimeError(f"{label} executable path differs from receipt")
        if not isinstance(row.get("executable_sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", row["executable_sha256"]):
            raise RuntimeError(f"{label} executable hash is invalid")
        _sdk_receipt_valid(row.get("sdk_intake"))
    if any(editor.get(key) != template.get(key) for key in COMMON):
        raise RuntimeError("SDK 2.4 editor and template source/runtime identities differ")
    frozen, integration = sdk_build.freeze_integration()
    if current and editor.get("integration") != integration:
        raise RuntimeError("SDK 2.4 integration differs from the current source")
    integration_map = editor.get("integration")
    expected_names = set(integration)
    if not isinstance(integration_map, dict) or set(integration_map) != expected_names:
        raise RuntimeError("SDK 2.4 integration receipt lacks required source files")
    sources = editor.get("engine_source")
    headers = editor.get("amd_headers")
    streamline = editor.get("streamline_headers")
    runtime = editor.get("runtime")
    licenses = editor.get("licenses")
    if not all(isinstance(row, dict) and row for row in (sources, headers, streamline, runtime, licenses)):
        raise RuntimeError("SDK 2.4 receipt lacks source, runtime or license hashes")
    for rel, digest in sources.items():
        product.safe_relative(rel)
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise RuntimeError(f"Invalid engine source hash: {rel}")
    header_pins = {name.removeprefix("Kits/FidelityFX/"): value[0] for name, value in sdk24.PINNED_FILES.items()
                   if name.startswith(("Kits/FidelityFX/api/include/", "Kits/FidelityFX/upscalers/include/"))}
    if headers != header_pins:
        raise RuntimeError("SDK 2.4 header hashes differ from the intake pins")
    required_source = sdk_build.patched_paths(frozen) | set(sdk_build.ADAPTER_FILES.values())
    required_source.update("thirdparty/amd-fsr-sdk24/" + name for name in header_pins)
    for name, target in sdk_build.ADAPTER_FILES.items():
        if sources.get(target) != integration_map.get(name):
            raise RuntimeError(f"Staged adapter source differs from its integration pin: {name}")
    for name, digest in header_pins.items():
        if sources.get("thirdparty/amd-fsr-sdk24/" + name) != digest:
            raise RuntimeError(f"Engine source lacks the pinned SDK header: {name}")
    for name, digest in streamline.items():
        if not _plain_name(name) or sources.get("thirdparty/streamline/include/" + name) != digest:
            raise RuntimeError(f"Streamline header identity differs: {name}")
    required_source.update("thirdparty/streamline/include/" + name for name in streamline)
    if set(sources) != required_source:
        raise RuntimeError("SDK 2.4 engine source receipt does not cover the exact patched/copied inputs")
    for name, path in AMD_DLLS.items():
        if runtime.get(name) != sdk24.PINNED_FILES[path][0]:
            raise RuntimeError(f"SDK 2.4 runtime is not pinned: {name}")
    for name, path in AMD_NOTICES.items():
        if licenses.get(name) != sdk24.PINNED_FILES[path][0]:
            raise RuntimeError(f"SDK 2.4 license or notice is not pinned: {name}")
    for group in (runtime, licenses):
        if any(not _plain_name(name) or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest)
               for name, digest in group.items()):
            raise RuntimeError("Unsafe or invalid runtime/license receipt entry")


def verify_engine_pair(editor_path: Path, template_path: Path, engine: Path) -> tuple[dict, dict, list[Path]]:
    editor = product.load_json(_safe_file(editor_path))
    template = product.load_json(_safe_file(template_path))
    _verify_pair_metadata(editor, template, engine, current=True)
    for label, row in (("editor", editor), ("template_release", template)):
        exe = engine / "bin" / f"godot.windows.{label}.x86_64.exe"
        if product.is_link(exe) or not exe.is_file() or product.sha(exe) != row["executable_sha256"]:
            raise RuntimeError(f"{label} executable differs from receipt")
        sdk_build.verify_build_inputs(engine, row)
    licenses = engine / "bin/licenses"
    if not licenses.is_dir() or product.is_link(licenses):
        raise RuntimeError("SDK 2.4 license directory is missing or linked")
    entries = list(licenses.iterdir())
    if {p.name for p in entries} != set(editor["licenses"]) or any(not p.is_file() or product.is_link(p) for p in entries):
        raise RuntimeError("SDK 2.4 license directory differs from its receipt")
    for name in editor["runtime"]:
        path = engine / "bin" / name
        if product.is_link(path):
            raise RuntimeError(f"Linked runtime DLL: {path}")
    for name in AMD_DLLS:
        sdk24.verify_signature(engine / "bin" / name)
    return editor, template, sorted(entries)


def _receipt_candidates(engine: Path, label: str, explicit: Path | None) -> list[Path]:
    if explicit is not None:
        return [_safe_file(explicit)]
    current = engine / "bin" / f"openrc-{label}-build.json"
    paths = ([current] if current.is_file() else []) + sorted(ARCHIVES.glob(f"openrc-{label}-build-*.json"))
    return [_safe_file(path) for path in paths]


def select_pair(engine: Path, editor_path: Path | None, template_path: Path | None) -> tuple[Path, Path]:
    editors = _receipt_candidates(engine, "editor", editor_path)
    templates = _receipt_candidates(engine, "template_release", template_path)
    if not editors or not templates:
        raise RuntimeError("Both SDK 2.4 editor and release-template receipts are required")
    matches = []
    for editor in editors:
        for template in templates:
            try:
                verify_engine_pair(editor, template, engine)
            except (OSError, RuntimeError, ValueError):
                continue
            matches.append((editor, template))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one matching SDK 2.4 receipt pair, found {len(matches)}; pass explicit receipts")
    return matches[0]


def candidate_launchers() -> dict[str, bytes]:
    prefix = ("@echo off\r\nsetlocal\r\n"
              'set "APPDATA=%LOCALAPPDATA%\\OpenRC-FSR24-Candidate"\r\n'
              'if not exist "%APPDATA%" mkdir "%APPDATA%"\r\n'
              'set "OPENRC_FSR_IMPLEMENTATION=analytical"\r\ncd /d "%~dp0"\r\n')
    def launcher(extra: str = "", settings: str = "") -> bytes:
        return (prefix + settings + f'start "" "%~dp0OpenRC Simulator.exe"{extra}\r\nendlocal\r\n').encode("utf-8")
    return {
        "OpenRC Simulator.cmd": launcher(),
        "Standard Graphics.cmd": launcher(" --rendering-method gl_compatibility"),
        "FSR3 Analytical.cmd": launcher(settings='set "OPENRC_GRAPHICS_PROFILE=high"\r\nset "OPENRC_RECONSTRUCTION=fsr3_quality"\r\n'),
        "EXPERIMENTAL.txt": ("OpenRC SDK 2.4 candidate: experimental Windows/Vulkan build.\r\n"
                             "Provider support, rendered quality, safety and performance are not qualified.\r\n"
                             "Frame generation is not integrated. Candidate settings use a separate profile.\r\n").encode("utf-8"),
    }


@contextmanager
def candidate_profile(engine: Path, editor_path: Path, template_path: Path, output: Path, snapshot: Path):
    def verify():
        return verify_engine_pair(editor_path, template_path, engine)

    def resolve_receipt(label: str) -> Path:
        if label == "editor":
            return editor_path
        if label == "template_release":
            return template_path
        raise ValueError(f"unsupported receipt label: {label}")

    def snapshot_sources() -> list[str]:
        editor, _, _ = verify()
        return [f"tools/graphics/native/{name}" for name in editor["integration"]] + [
            "tools/graphics/native/product.py", "tools/graphics/native/product_sdk24.py"]

    values = {"ENGINE": engine / "bin", "SNAPSHOT": snapshot, "OUTPUT": output, "CHECKS": CHECKS,
              "SNAPSHOT_FORMAT": SNAPSHOT_FORMAT, "PACKAGE_FORMAT": PACKAGE_FORMAT,
              "verify_engine": verify, "engine_receipt_path": resolve_receipt,
              "additional_snapshot_files": snapshot_sources, "launcher_files": candidate_launchers,
              "DEADLINE": time.monotonic() + 1200}
    previous = {name: getattr(product, name) for name in values}
    try:
        _verify_packager_sources()
        for name, value in values.items():
            setattr(product, name, value)
        yield
    finally:
        for name, value in previous.items():
            setattr(product, name, value)


def _verify_packager_sources() -> None:
    for name, digest in PACKAGER_IMPORTS.items():
        path = HERE / name
        if not path.is_file() or product.sha(path) != digest:
            raise RuntimeError(f"Packaging source changed after import: {name}")


def _snapshot_path(receipt: dict) -> Path:
    binding = receipt.get("export_binding")
    if not isinstance(binding, dict) or not isinstance(binding.get("snapshot_path"), str):
        raise RuntimeError("Candidate receipt lacks a source snapshot path")
    path = Path(binding["snapshot_path"])
    if not path.is_absolute() or path.resolve().parent != SNAPSHOT.resolve() or not path.name.startswith("source-"):
        raise RuntimeError("Candidate snapshot is outside its isolated root")
    if product.is_link(path) or product.is_link(path.parent):
        raise RuntimeError("Candidate snapshot path is linked")
    return path.resolve()


def _checked_report(path_value: object, *, export: bool, engine: Path, snapshot: Path) -> tuple[Path, dict]:
    if not isinstance(path_value, str):
        raise RuntimeError("Missing checked runner report path")
    path = _safe_file(Path(path_value))
    if not path.is_relative_to(CHECKS.resolve()):
        raise RuntimeError("Checked report is outside the candidate checks directory")
    report = product.load_json(path)
    command = report.get("command")
    if (report.get("format") != "openrc-godot-check v1" or report.get("ok") is not True or
            report.get("complete") is not True or report.get("exit_code") != 0 or
            report.get("process_exit") != 0 or report.get("counts", {}).get("error") != 0 or
            not isinstance(command, list) or not all(isinstance(value, str) for value in command)):
        raise RuntimeError("Checked import/export report is not complete and successful")
    cwd_value = report.get("cwd")
    if not isinstance(cwd_value, str) or not Path(cwd_value).is_absolute():
        raise RuntimeError("Checked report lacks an absolute working directory")
    cwd = Path(cwd_value).resolve()
    if (not command or command.count("--path") != 1 or "--headless" not in command or
            (cwd / command[0]).resolve() != (engine / "bin/godot.windows.editor.x86_64.exe").resolve()):
        raise RuntimeError("Checked report used a different editor or invocation")
    index = command.index("--path") + 1
    if index >= len(command) or (cwd / command[index]).resolve() != (snapshot / "app").resolve():
        raise RuntimeError("Checked report used a different source snapshot")
    if export:
        if command.count("--export-pack") != 1:
            raise RuntimeError("Checked report is not a Windows PCK export")
        index = command.index("--export-pack")
        if index + 2 >= len(command) or command[index + 1] != "Windows":
            raise RuntimeError("Checked report has the wrong export target")
        pack = (cwd / command[index + 2]).resolve()
        if (pack.name != "OpenRC Simulator.pck" or pack.parent.parent != OUTPUT.parent.resolve() or
                not pack.parent.name.startswith("nvidia-product-export-")):
            raise RuntimeError("Checked export did not target the isolated candidate staging area")
    elif "--import" not in command:
        raise RuntimeError("Checked report is not a source import")
    log = path.parent / "engine.log"
    if Path(str(report.get("log", ""))).resolve() != log or not log.is_file() or product.sha(log) != report.get("log_sha256"):
        raise RuntimeError("Checked runner log differs from its report")
    inspection = inspect_log(log, ["[ DONE ] savepack"] if export else [])
    if inspection["counts"]["error"] or inspection["missing_required_text"]:
        raise RuntimeError("Checked runner log contains errors or lacks export completion")
    return path, report


def verify_candidate_output(output: Path, engine: Path, editor: dict, template: dict) -> dict:
    _verify_packager_sources()
    receipt = product.verify_tree(output, product.PACKAGE_RECEIPT, PACKAGE_FORMAT)
    candidate_editor = product.load_json(output / "openrc-editor-build.json")
    candidate_template = product.load_json(output / "openrc-template_release-build.json")
    if candidate_editor != editor or candidate_template != template:
        raise RuntimeError("Packaged SDK 2.4 receipts differ from the selected build pair")
    _verify_pair_metadata(candidate_editor, candidate_template, engine, current=True)
    exe = output / "OpenRC Simulator.exe"
    if not exe.is_file() or product.sha(exe) != template["executable_sha256"]:
        raise RuntimeError("Candidate executable differs from the release template")
    for name, digest in editor["runtime"].items():
        path = output / name
        if not path.is_file() or product.sha(path) != digest:
            raise RuntimeError(f"Candidate runtime DLL differs from receipt: {name}")
    for name in AMD_DLLS:
        sdk24.verify_signature(output / name)
    license_dir = output / "licenses"
    if not license_dir.is_dir() or {p.name for p in license_dir.iterdir()} != set(editor["licenses"]):
        raise RuntimeError("Candidate licenses and notices differ from the build receipt")
    for name, digest in editor["licenses"].items():
        path = license_dir / name
        if not path.is_file() or product.sha(path) != digest:
            raise RuntimeError(f"Candidate license or notice differs: {name}")
    snapshot_path = _snapshot_path(receipt)
    snapshot = product.verify_tree(snapshot_path, product.SNAPSHOT_RECEIPT, SNAPSHOT_FORMAT, ignore_cache=True)
    packaged_snapshot = output / product.SNAPSHOT_RECEIPT
    if (not packaged_snapshot.is_file() or product.sha(packaged_snapshot) != product.sha(snapshot_path / product.SNAPSHOT_RECEIPT) or
            receipt.get("snapshot_sha256") != product.sha(packaged_snapshot) or
            receipt.get("build_identity") != snapshot.get("build_identity")):
        raise RuntimeError("Candidate and source snapshot identities differ")
    for name, digest in editor["integration"].items():
        if snapshot["files"].get(f"tools/graphics/native/{name}") != digest:
            raise RuntimeError(f"Snapshot does not contain the build integration source: {name}")
    for name, digest in PACKAGER_IMPORTS.items():
        if snapshot["files"].get(f"tools/graphics/native/{name}") != digest:
            raise RuntimeError(f"Snapshot does not contain the executing packaging source: {name}")
    if (receipt.get("godot_commit") != native_build.COMMIT or receipt.get("sources") != editor["sources"] or
            receipt.get("integration") != editor["integration"] or receipt.get("runtime") != editor["runtime"] or
            receipt.get("editor_sha256") != editor["executable_sha256"] or
            receipt.get("template_sha256") != template["executable_sha256"]):
        raise RuntimeError("Candidate package identity differs from its SDK 2.4 build receipts")
    ground = output / "openrc_ground_vehicle.dll"
    if not ground.is_file() or product.sha(ground) != snapshot["files"].get("app/native/ground_vehicle/openrc_ground_vehicle.dll"):
        raise RuntimeError("Candidate ground-vehicle sidecar differs from source snapshot")
    import_path, _ = _checked_report(receipt.get("import_report"), export=False, engine=engine, snapshot=snapshot_path)
    export_path, _ = _checked_report(receipt.get("export_report"), export=True, engine=engine, snapshot=snapshot_path)
    imported = snapshot.get("import", {})
    if (imported.get("report") != str(import_path) or imported.get("report_sha256") != product.sha(import_path) or
            imported.get("editor_sha256") != editor["executable_sha256"]):
        raise RuntimeError("Candidate import receipt does not bind the selected editor and snapshot")
    pack = output / "OpenRC Simulator.pck"
    if not pack.is_file() or not pack.stat().st_size:
        raise RuntimeError("Candidate exported PCK is missing or empty")
    expected_binding = {"snapshot_path": str(snapshot_path), "pck_sha256": product.sha(pack), "snapshot_sha256": product.sha(packaged_snapshot),
                        "import_report_sha256": product.sha(import_path), "export_report_sha256": product.sha(export_path)}
    if receipt.get("export_binding") != expected_binding:
        raise RuntimeError("Candidate PCK, source snapshot and checked reports are not bound")
    return receipt


def _bind_export(output: Path) -> None:
    path = output / product.PACKAGE_RECEIPT
    receipt = product.load_json(path)
    if "export_binding" in receipt:
        raise RuntimeError("Unexpected existing candidate export binding")
    import_path, _ = _checked_report(receipt.get("import_report"), export=False, engine=product.ENGINE.parent, snapshot=product.SNAPSHOT)
    export_path, _ = _checked_report(receipt.get("export_report"), export=True, engine=product.ENGINE.parent, snapshot=product.SNAPSHOT)
    receipt["export_binding"] = {"snapshot_path": str(product.SNAPSHOT.resolve()), "pck_sha256": product.sha(output / "OpenRC Simulator.pck"),
                                 "snapshot_sha256": product.sha(output / product.SNAPSHOT_RECEIPT),
                                 "import_report_sha256": product.sha(import_path), "export_report_sha256": product.sha(export_path)}
    temporary = output / ("candidate-receipt-" + uuid.uuid4().hex + ".tmp")
    try:
        temporary.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def package_candidate(engine: Path, editor_path: Path, template_path: Path) -> dict:
    editor, template, _ = verify_engine_pair(editor_path, template_path, engine)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    pending = OUTPUT.parent / ("fsr24-candidate-pending-" + uuid.uuid4().hex)
    snapshot_path = SNAPSHOT / ("source-" + uuid.uuid4().hex)
    with candidate_profile(engine, editor_path, template_path, pending, snapshot_path):
        previous_hash = None
        if OUTPUT.exists():
            verify_candidate_output(OUTPUT, engine, editor, template)
            previous_hash = product.sha(OUTPUT / product.PACKAGE_RECEIPT)
        snapshot = product.prepare_snapshot()
        product.package_product(snapshot)
        _bind_export(pending)
        verify_engine_pair(editor_path, template_path, engine)
        receipt = verify_candidate_output(pending, engine, editor, template)
        if OUTPUT.exists():
            # Never replace an unreceipted or changed previous candidate.
            if previous_hash is None or product.sha(OUTPUT / product.PACKAGE_RECEIPT) != previous_hash:
                raise RuntimeError("Existing candidate changed during export")
            verify_candidate_output(OUTPUT, engine, editor, template)
        elif previous_hash is not None:
            raise RuntimeError("Existing candidate disappeared during export")
        product.replace_tree(pending, OUTPUT)
    print(f"Packaged unqualified SDK 2.4 candidate: {OUTPUT}")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=sdk_build.DEFAULT_CACHE)
    parser.add_argument("--editor-receipt", type=Path)
    parser.add_argument("--template-receipt", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--package", action="store_true", help="snapshot, import and export the isolated candidate")
    mode.add_argument("--verify", action="store_true", help="verify the existing isolated candidate")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("The SDK 2.4 candidate targets Windows/Vulkan")
    cache = sdk_build.validate_cache(args.cache)
    engine = cache / native_build.ARCHIVES[0][3]
    editor_path, template_path = select_pair(engine, args.editor_receipt, args.template_receipt)
    editor, template, _ = verify_engine_pair(editor_path, template_path, engine)
    if args.package:
        package_candidate(engine, editor_path, template_path)
    elif args.verify:
        snapshot_path = _snapshot_path(product.load_json(OUTPUT / product.PACKAGE_RECEIPT))
        with candidate_profile(engine, editor_path, template_path, OUTPUT, snapshot_path):
            verify_candidate_output(OUTPUT, engine, editor, template)
        print(f"Verified unqualified SDK 2.4 candidate: {OUTPUT}")
    else:
        print(f"SDK 2.4 preflight passed: {editor_path} + {template_path}; no export performed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"SDK 2.4 candidate packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
