#!/usr/bin/env python3
"""Package the pinned experimental Windows/Vulkan reconstruction trial."""
from __future__ import annotations

import hashlib
import json
import os
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build as native_build
import prepare_candidate as candidate_pins

COMMIT = native_build.COMMIT
BASE = candidate_pins.BASE_COMMIT
INTEGRATION_COMMIT = candidate_pins.INTEGRATION_COMMIT
CANDIDATE = ROOT / "tmp/native-reconstruction-candidate"
OUT = ROOT / "tmp/native-reconstruction-export"
CHECKS = ROOT / "tmp/godot-checks/native-package-export"
INTEGRATION = ("engine.patch", "vulkan_validation.patch", "dlss_validation.patch", "shutdown_thread.patch", "load_token_lifetime.patch", "fidelityfx.patch", "build_fidelityfx.py", "fsr3.h", "fsr3.cpp", "fsr3_prepare.glsl")
OVERLAYS = candidate_pins.INTEGRATION_OVERLAYS
FORMAT = "openrc-native-reconstruction-package v1"
sys.path.insert(0, str(ROOT / "tools/godot"))
from run_checked import run_checked


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid receipt: {path}") from error
    if not isinstance(value, dict): raise RuntimeError(f"receipt is not an object: {path}")
    return value

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-only", action="store_true",
                        help="validate package inputs without exporting or writing files")
    args = parser.parse_args()
    engine = ROOT / ".tools/advanced-rendering" / f"godot-{COMMIT}" / "bin"
    editor_receipt_path = engine / "openrc-editor-build.json"
    template_receipt_path = engine / "openrc-template_release-build.json"
    candidate_receipt_path = CANDIDATE / "presentation-engine-receipt.json"
    editor, template = read_json(editor_receipt_path), read_json(template_receipt_path)
    candidate = read_json(candidate_receipt_path)
    expected_integration = {name: digest(HERE / name) for name in INTEGRATION}
    expected_sources = {name: digest for name, _, digest, _ in native_build.ARCHIVES}
    shared = ("godot_commit", "version", "fidelityfx_sdk", "fsr_upscaler", "streamline", "platform", "graphics_api", "frame_generation_enabled", "sources", "integration", "streamline_headers", "runtime", "fidelityfx_runtime_build")
    for label, receipt in (("editor", editor), ("template_release", template)):
        if receipt.get("experimental") is not True or receipt.get("godot_commit") != COMMIT:
            raise RuntimeError(f"{label} receipt is not for the pinned experimental engine")
        if receipt.get("platform") != "windows" or receipt.get("graphics_api") != "vulkan" or receipt.get("frame_generation_enabled") is not False:
            raise RuntimeError(f"{label} receipt has the wrong platform/backend")
        if receipt.get("integration") != expected_integration:
            raise RuntimeError(f"{label} integration receipt is stale versus tools/graphics/native")
        if receipt.get("sources") != expected_sources:
            raise RuntimeError(f"{label} SDK/source archive identities do not match the pinned build")
        if not isinstance(receipt.get("streamline_headers"), dict) or not receipt["streamline_headers"]:
            raise RuntimeError(f"{label} receipt has no Streamline header hashes")
        if not isinstance(receipt.get("runtime"), dict) or not receipt["runtime"]:
            raise RuntimeError(f"{label} receipt has no runtime DLL hashes")
        exe = Path(str(receipt.get("executable", ""))).resolve()
        wanted = (engine / ("godot.windows.editor.x86_64.exe" if label == "editor"
                            else "godot.windows.template_release.x86_64.exe")).resolve()
        if exe != wanted or not exe.is_file() or digest(exe) != receipt.get("executable_sha256"):
            raise RuntimeError(f"{label} executable path/hash does not match its receipt")
    if any(editor.get(key) != template.get(key) for key in shared):
        raise RuntimeError("editor and release-template receipts describe different source/runtime identities")
    for name, expected in editor["runtime"].items():
        if Path(name).name != name or not isinstance(expected, str):
            raise RuntimeError(f"invalid runtime DLL receipt entry: {name}")
        runtime = engine / name
        if not runtime.is_file() or digest(runtime) != expected:
            raise RuntimeError(f"runtime DLL hash mismatch: {name}")

    if (candidate.get("source_base_commit") != BASE or
            candidate.get("integration_source_commit") != INTEGRATION_COMMIT or
            candidate.get("engine_identity") != "4.8.0" or
            candidate.get("candidate_renderer") != "forward_plus"):
        raise RuntimeError("candidate receipt does not match the pinned Forward+ source/engine identity")
    if digest(CANDIDATE / "app/project.godot") != candidate.get("candidate_project_sha256"): raise RuntimeError("candidate project changed after its receipt")
    registry = CANDIDATE / "app/data/aircraft_customization.json"
    if digest(registry) != candidate.get("generated_registry_sha256"): raise RuntimeError("candidate presentation registry changed after generation")
    generator = CANDIDATE / "research/aircraft-standardization/build_customization.py"
    if digest(generator) != candidate.get("candidate_generator_sha256") or candidate.get("generator_source_sha256") != "a78b580aa320dfd4d34e27ef2e017cb395e19f71a5e35b25132a7228482e7ac6":
        raise RuntimeError("candidate generator identity is stale")
    source_records = candidate.get("presentation_sources", [])
    for record in source_records:
        source = CANDIDATE / "app" / str(record.get("path", "")).removeprefix("res://")
        text = source.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != record.get("sha256"):
            raise RuntimeError(f"candidate presentation source is stale: {source}")
    bindings = json.loads(registry.read_text(encoding="utf-8"))
    if any(item.get("presentation_engine_version") != "4.8.0" or item.get("presentation_sources") != source_records
           for item in bindings.get("families", [])):
        raise RuntimeError("candidate family registry does not match its presentation receipt")
    overlay_records = candidate.get("integration_overlays", {})
    if set(overlay_records) != set(OVERLAYS): raise RuntimeError("candidate receipt does not cover the exact app integration files")
    expected_overlay_records = candidate_pins.expected_integration_overlays()
    for name in OVERLAYS:
        expected = expected_overlay_records[name]
        actual = overlay_records[name]
        if (actual.get("source_commit") != expected["source_commit"] or
                actual.get("source_sha256") != expected["source_sha256"] or
                actual.get("expected_final_sha256") != expected["expected_final_sha256"] or
                actual.get("prepared_sha256") != expected["expected_final_sha256"] or
                digest(CANDIDATE / name) != expected["expected_final_sha256"]):
            raise RuntimeError(f"candidate app integration is stale: {name}")

    licenses = engine / "licenses"
    license_entries = list(licenses.iterdir())
    license_files = sorted(path for path in license_entries if path.is_file())
    if not license_files or len(license_files) != len(license_entries):
        raise RuntimeError("engine license directory is empty or contains non-file entries")
    pck = OUT / "OpenRC Native Trial.pck"
    template_exe = engine / "godot.windows.template_release.x86_64.exe"
    date = subprocess.check_output(["git", "show", "-s", "--format=%cI", BASE], cwd=ROOT, text=True).strip()
    build_id = {"describe": f"experimental-{BASE[:12]}", "commit": BASE, "dirty": True, "commit_date": date}
    launchers = {"Native.cmd": "native", "FSR3 Quality.cmd": "fsr3_quality", "DLSS Quality.cmd": "dlss_quality"}
    managed: dict[str, bytes] = {
        "OpenRC Native Trial.exe": template_exe.read_bytes(),
        "openrc-editor-build.json": editor_receipt_path.read_bytes(),
        "openrc-template_release-build.json": template_receipt_path.read_bytes(),
        "presentation-engine-receipt.json": candidate_receipt_path.read_bytes(),
    }
    for name in editor["runtime"]:
        managed[name] = (engine / name).read_bytes()
    for source in license_files:
        managed[f"licenses/{source.name}"] = source.read_bytes()
    for name, mode in launchers.items():
        slug = mode.replace("_", "-")
        body = ("@echo off\r\nsetlocal\r\n" f'set "APPDATA=%~dp0profile-{slug}"\r\n'
                'if not exist "%APPDATA%" mkdir "%APPDATA%"\r\n'
                f'set "OPENRC_GRAPHICS_PROFILE=high"\r\nset "OPENRC_RECONSTRUCTION={mode}"\r\n'
                'cd /d "%~dp0"\r\nstart "" "%~dp0OpenRC Native Trial.exe" -- --quick-flight\r\nendlocal\r\n')
        managed[name] = body.encode("utf-8")
    managed["Graphics Options.cmd"] = (
        '@echo off\r\nsetlocal\r\nset "APPDATA=%~dp0profile-options"\r\n'
        'if not exist "%APPDATA%" mkdir "%APPDATA%"\r\n'
        'set "OPENRC_GRAPHICS_PROFILE=high"\r\nset "OPENRC_RECONSTRUCTION=native"\r\n'
        'cd /d "%~dp0"\r\nstart "" "%~dp0OpenRC Native Trial.exe"\r\nendlocal\r\n'
    ).encode("utf-8")

    if OUT.exists() and not OUT.is_dir():
        raise RuntimeError(f"package output path is not a directory: {OUT}")
    previous_path = OUT / "package-receipt.json"
    previous = read_json(previous_path) if previous_path.exists() else {}
    if previous and (previous.get("format") != FORMAT or previous.get("godot_commit") != COMMIT):
        raise RuntimeError("existing output receipt belongs to another package")
    previous_files = previous.get("files", {})
    if previous and not isinstance(previous_files, dict):
        raise RuntimeError("existing package receipt has no managed-file map")
    for relative, content in managed.items():
        target = OUT / relative
        if target.exists() and digest(target) != hashlib.sha256(content).hexdigest():
            if previous_files.get(relative) != digest(target):
                raise RuntimeError(f"refusing to overwrite unexpected output: {target}")
    if pck.exists() and (not previous or previous_files.get(pck.name) != digest(pck)):
        raise RuntimeError(f"refusing to overwrite unreceipted PCK: {pck}")

    if args.preflight_only:
        print(f"Package preflight passed for pinned candidate {BASE} + {INTEGRATION_COMMIT}; no export or files written.")
        return 0

    OUT.mkdir(parents=True, exist_ok=True)

    os.environ.update({"OPENRC_BUILD_DESCRIBE": build_id["describe"], "OPENRC_BUILD_COMMIT": BASE,
                       "OPENRC_BUILD_DIRTY": "1", "OPENRC_BUILD_DATE": date})
    result = run_checked([str(engine / "godot.windows.editor.x86_64.exe"), "--headless", "--path",
                          str(CANDIDATE / "app"), "--export-pack", "Windows", str(pck)],
                         CHECKS, timeout=900, required=["[ DONE ] savepack"], label="native-windows-trial-pack")
    if not result.get("ok") or not pck.is_file() or not pck.stat().st_size:
        raise RuntimeError(f"Windows PCK export failed; runner report: {result.get('report')}")
    files = {pck.name: digest(pck)}
    for relative, content in managed.items():
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        files[relative] = digest(target)
    package = {"format": FORMAT, "build_identity": build_id,
               "godot_commit": COMMIT, "engine_version": editor["version"],
               "sources": editor["sources"], "integration": editor["integration"],
               "streamline_headers": editor["streamline_headers"],
               "runtime": editor["runtime"], "candidate": {key: candidate[key] for key in
                   ("source_base_commit", "integration_source_commit", "engine_identity", "candidate_renderer",
                    "generated_registry_sha256", "integration_overlays")}, "export_report": result["report"], "files": files}
    (OUT / "package-receipt.json").write_text(json.dumps(package, indent=2) + "\n", encoding="utf-8")
    print(f"Packaged {len(files)} files in {OUT}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"native trial packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
