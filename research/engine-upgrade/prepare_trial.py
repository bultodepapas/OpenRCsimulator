#!/usr/bin/env python3
"""GDU-02: reproducible Windows trial of the official engine in a separate worktree.

This does not qualify companions, change production pins, or integrate NVIDIA DLSS.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "4.8-beta1"
ENGINE_ID = "4.8.beta1.official.4d10419ca"
DEFAULT_REVISION = "a6c2ce38a80a44327392367520c828b42ba0acda"
ARCHIVE = f"Godot_v{VERSION}_win64.exe.zip"
SHA512 = "bdc79f8ef47c3794c6984751bbac2c1934cf1c7c9ceebc2d0e87db0846766411b7bbbb6fecf90f3485f951a1289c3171b1c7bebca18dcdd8e08bd81de95b6cc0"
URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}/{ARCHIVE}"
TEMPLATES_SHA512 = "fa53ad6883ae6c78ee9d2f8d14ca4d34852fa21c462d1f4b0f599138d7de40897cc058f15083a1fa80c7d4b7590b2222dea6f056be7b49e3a584eb64fc30b0b7"
DEFAULT_DESTINATION = ROOT / "tmp" / "godot-4.8-beta1-trial"


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()


def digest(path: Path, algorithm: str = "sha256") -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, algorithm).hexdigest()


def install_engine() -> Path:
    cache = ROOT / ".tools" / "engine-upgrade" / VERSION
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / ARCHIVE
    if not archive.exists():
        partial = archive.with_suffix(".download")
        urllib.request.urlretrieve(URL, partial)
        if digest(partial, "sha512") != SHA512:
            raise RuntimeError("official editor archive SHA-512 mismatch")
        partial.replace(archive)
    if digest(archive, "sha512") != SHA512:
        raise RuntimeError("cached editor archive SHA-512 mismatch")
    # Only extract the two named editor executables; never arbitrary archive paths.
    with zipfile.ZipFile(archive) as package:
        for name in (f"Godot_v{VERSION}_win64.exe", f"Godot_v{VERSION}_win64_console.exe"):
            content = package.read(name)
            target = cache / name
            if not target.exists() or target.read_bytes() != content:
                target.write_bytes(content)
    engine = cache / f"Godot_v{VERSION}_win64_console.exe"
    actual = subprocess.check_output([str(engine), "--version"], text=True).strip()
    if actual != ENGINE_ID:
        raise RuntimeError(f"unexpected editor identity: {actual}")
    return engine


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"expected exactly one source anchor: {old!r}")
    return text.replace(old, new, 1)


def project_settings(text: str) -> str:
    text = replace_once(text, 'config/name="OpenRC Simulator"',
                        'config/name="OpenRC Simulator - Godot 4.8 beta1 Trial"\n'
                        'config/use_custom_user_dir=true\n'
                        'config/custom_user_dir_name="OpenRC Simulator/Godot 4.8 beta1 Trial"')
    text = replace_once(text, 'config/features=PackedStringArray("4.7")',
                        'config/features=PackedStringArray("4.8")')
    text = replace_once(text, "[display]\n", "[display]\n\n"
                        "window/size/enable_toggle_fullscreen_shortcut=false\n")
    # Same renderer, physics, and viewport as the source; launch at the 1080p target.
    return text + "\n[gui]\n\ncommon/auto_focus_strategy=0\n\n" \
        "[input_devices]\n\njoypads/ignore_joypad_on_unfocused_application=false\n"


def prepare(destination: Path, revision: str, engine: Path) -> dict:
    destination = destination.resolve()
    temporary = (ROOT / "tmp").resolve()
    # Permit a separate drive, but never the production tree or one of its parents.
    if destination == ROOT or ROOT.is_relative_to(destination) or (
        destination.is_relative_to(ROOT) and
        (not destination.is_relative_to(temporary) or destination == temporary)
    ):
        raise RuntimeError("trial must be below tmp/ or outside the production tree")
    revision = git("rev-parse", "--verify", f"{revision}^{{commit}}")
    if not destination.exists():
        subprocess.run(["git", "worktree", "add", "--detach", str(destination), revision],
                       cwd=ROOT, check=True)
    if Path(git("rev-parse", "--show-toplevel", cwd=destination)).resolve() != destination:
        raise RuntimeError("destination is not an independent worktree")
    if git("rev-parse", "HEAD", cwd=destination) != revision:
        raise RuntimeError("existing worktree has a different source revision")

    transforms = {
        "app/project.godot": project_settings,
        "app/render/presentation_sources.gd": lambda t: replace_once(t,
            'const ENGINE_VERSION_PIN := "4.7.2"', 'const ENGINE_VERSION_PIN := "4.8.0"'),
        "app/workshop/presentation.gd": lambda t: replace_once(t,
            'const PRESENTATION_ENGINE_VERSION: String = "4.7.2"',
            'const PRESENTATION_ENGINE_VERSION: String = "4.8.0"'),
        "research/aircraft-standardization/build_customization.py": lambda t: replace_once(t,
            'PRESENTATION_ENGINE_VERSION = "4.7.2"', 'PRESENTATION_ENGINE_VERSION = "4.8.0"'),
        "app/tests/test_aircraft_customization.gd": lambda t: replace_once(t,
            'str(bindings.get("presentation_engine_version", "")) == "4.7.2"',
            'str(bindings.get("presentation_engine_version", "")) == PresentationSources.ENGINE_VERSION_PIN'),
        "app/tests/test_workshop_presentation.gd": lambda t: replace_once(t,
            '"presentation_engine_version": "4.7.2",',
            '"presentation_engine_version": Profile.PRESENTATION_ENGINE_VERSION,'),
        "app/tests/test_smoke_bindings.gd": lambda t: replace_once(t,
            '"presentation_engine_version": "4.7.2",',
            '"presentation_engine_version": Sources.ENGINE_VERSION_PIN,'),
    }
    prepared = {}
    # Check all direct edits before writing. Re-running must not discard local work.
    for relative, transform in transforms.items():
        baseline = subprocess.check_output(["git", "show", f"{revision}:{relative}"], cwd=ROOT).decode()
        content = transform(baseline)
        current = (destination / relative).read_text(encoding="utf-8")
        if current not in (baseline, content):
            raise RuntimeError(f"unexpected local edit in trial: {relative}")
        prepared[relative] = content
    registry = destination / "app/data/aircraft_customization.json"
    receipt_path = destination / "trial-receipt.json"
    previous = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    baseline_registry = subprocess.check_output(
        ["git", "show", f"{revision}:app/data/aircraft_customization.json"], cwd=ROOT)
    allowed_registry = {hashlib.sha256(baseline_registry).hexdigest(),
                        previous.get("generated_registry_sha256")}
    if digest(registry) not in allowed_registry:
        # A Windows checkout may normalize line endings.
        normalized = registry.read_text(encoding="utf-8").encode()
        if hashlib.sha256(normalized).hexdigest() not in allowed_registry:
            raise RuntimeError("unexpected edit to generated trial registry")
    models = list((destination / "app/data/aircraft_models").glob("*.json"))
    for model in models:
        relative = model.relative_to(destination).as_posix()
        baseline = subprocess.check_output(["git", "show", f"{revision}:{relative}"], cwd=ROOT)
        allowed = {hashlib.sha256(baseline).hexdigest(),
                   previous.get("generated_models", {}).get(relative)}
        if hashlib.sha256(model.read_text(encoding="utf-8").encode()).hexdigest() not in allowed:
            raise RuntimeError(f"unexpected edit to generated model: {relative}")
    gui_engine = engine.with_name(f"Godot_v{VERSION}_win64.exe")
    launchers = {}
    for name, options in (("Play Godot 4.8.cmd", "--resolution 1920x1080"),
                          ("Edit Godot 4.8.cmd", "--editor")):
        content = ('@echo off\nsetlocal\n'
                   'set "APPDATA=%~dp0profile"\n'
                   'set "OPENRC_GRAPHICS_PROFILE="\nset "OPENRC_RECONSTRUCTION="\n'
                   f'"{gui_engine}" --path "%~dp0app" {options} %*\n')
        target = destination / name
        if target.exists() and target.read_text(encoding="utf-8") != content:
            raise RuntimeError(f"unexpected local launcher edit: {name}")
        launchers[name] = content
    for relative, content in prepared.items():
        (destination / relative).write_text(content, encoding="utf-8", newline="\n")
    subprocess.run([sys.executable, str(ROOT / "tools/godot/run_checked.py"),
        "--label", "gdu02-import", "--out-dir", str(destination / "tmp/import-checks"),
        "--timeout", "1200", "--", str(engine), "--headless", "--path", str(destination / "app"),
        "--audio-driver", "Dummy", "--import"],
        env=dict(os.environ, APPDATA=str(destination / "profile")), check=True)
    # Reimport adds tracked .import keys. Rebuild their dependency hashes through
    # the owning generator before rebuilding customization's model-manifest pins.
    model_generator = destination / "research/aircraft-standardization/build_models.py"
    subprocess.run([sys.executable, str(model_generator), "--root", str(destination)], check=True)
    subprocess.run([sys.executable, str(model_generator), "--root", str(destination), "--check"], check=True)
    generator = destination / "research/aircraft-standardization/build_customization.py"
    subprocess.run([sys.executable, str(generator), "--root", str(destination)], check=True)
    subprocess.run([sys.executable, str(generator), "--root", str(destination), "--check"], check=True)

    # Dedicated user data lives beside the trial, including editor state and test saves.
    # No inherited renderer/reconstruction experiment may silently change this variant.
    for name, content in launchers.items():
        (destination / name).write_text(content, encoding="utf-8", newline="\r\n")
    receipt = {
        "format": "openrc-official-godot-trial v1", "step": "GDU-02",
        "source_commit": revision, "engine_version": ENGINE_ID,
        "editor_url": URL, "editor_archive_sha512": SHA512,
        "editor_executable_sha256": digest(engine),
        "editor_gui_sha256": digest(gui_engine),
        "presentation_engine_version": "4.8.0",
        "presentation_qualification": "experimental; not accepted for production",
        "companion_qualification": "unchanged 4.7.2 guard; unavailable on 4.8",
        "renderer": "gl_compatibility", "dlss": False,
        "generated_registry_sha256": digest(registry),
        "generated_models": {p.relative_to(destination).as_posix(): digest(p) for p in models},
        "adapted_files": {p: digest(destination / p) for p in prepared},
        "launchers": {p: digest(destination / p) for p in launchers},
    }
    # A commit alone does not identify this intentionally dirty experimental tree.
    patch = subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=destination)
    (destination / "trial-source.patch").write_bytes(patch)
    receipt["tracked_diff_sha256"] = hashlib.sha256(patch).hexdigest()
    untracked = git("ls-files", "--others", "--exclude-standard", "app", "research", "tools", cwd=destination)
    receipt["untracked_sources"] = {p: digest(destination / p) for p in untracked.splitlines()}
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Trial: {destination}\nEngine: {engine}\nSource: {revision}")
    return receipt


def export_windows(destination: Path, engine: Path) -> None:
    """Use the official matching templates without installing into the user's editor."""
    cache = engine.parent
    name = f"Godot_v{VERSION}_export_templates.tpz"
    archive = cache / name
    if not archive.exists():
        partial = archive.with_suffix(".download")
        urllib.request.urlretrieve(
            f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}/{name}", partial)
        if digest(partial, "sha512") != TEMPLATES_SHA512:
            raise RuntimeError("official templates SHA-512 mismatch")
        partial.replace(archive)
    if digest(archive, "sha512") != TEMPLATES_SHA512:
        raise RuntimeError("cached templates SHA-512 mismatch")
    template = cache / "windows_release_x86_64.exe"
    with zipfile.ZipFile(archive) as package:
        template.write_bytes(package.read("templates/windows_release_x86_64.exe"))
    config = destination / "app/export_presets.cfg"
    revision = git("rev-parse", "HEAD", cwd=destination)
    baseline = subprocess.check_output(["git", "show", f"{revision}:app/export_presets.cfg"], cwd=ROOT).decode()
    content = replace_once(baseline, "[preset.1.options]\n",
        f'[preset.1.options]\n\ncustom_template/release="{template.as_posix()}"\n')
    if config.read_text(encoding="utf-8") not in (baseline, content):
        raise RuntimeError("unexpected local export preset edit")
    config.write_text(content, encoding="utf-8", newline="\n")
    output = destination / "experimental-windows"
    output.mkdir(exist_ok=True)
    executable = output / "OpenRC Godot 4.8 Trial.exe"
    env = dict(os.environ, APPDATA=str(destination / "profile"))
    for key in ("OPENRC_GRAPHICS_PROFILE", "OPENRC_RECONSTRUCTION"):
        env.pop(key, None)
    subprocess.run([sys.executable, str(ROOT / "tools/godot/run_checked.py"),
        "--label", "gdu02-export-windows", "--out-dir", str(destination / "tmp/export-checks"),
        "--timeout", "900", "--", str(engine), "--headless", "--path", str(destination / "app"),
        "--audio-driver", "Dummy", "--export-release", "Windows", str(executable)],
        env=env, check=True)
    (output / "Play.cmd").write_text(
        '@echo off\nsetlocal\nset "APPDATA=%~dp0profile"\n'
        'set "OPENRC_GRAPHICS_PROFILE="\nset "OPENRC_RECONSTRUCTION="\n'
        '"%~dp0OpenRC Godot 4.8 Trial.exe" --resolution 1920x1080 %*\n',
        encoding="utf-8", newline="\r\n")
    manifest = {"format": "openrc-official-godot-trial-export v1", "engine": ENGINE_ID,
        "templates_sha512": TEMPLATES_SHA512, "source_commit": revision,
        "qualification": "experimental Windows export; production gates remain open",
        "files": {p.name: digest(p) for p in output.iterdir() if p.is_file() and p.name != "manifest.json"}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    # Include the final export-preset change and editor-generated source artifacts.
    prepare(destination, revision, engine)
    print(f"Windows experiment: {executable}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default=DEFAULT_REVISION)
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    parser.add_argument("--export-windows", action="store_true")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("this trial launcher currently targets Windows x86_64")
    engine = install_engine()
    prepare(args.destination, args.revision, engine)
    if args.export_windows:
        export_windows(args.destination.resolve(), engine)


if __name__ == "__main__":
    main()
