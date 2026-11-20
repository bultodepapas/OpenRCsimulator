"""Per-run macOS profile isolation over GOD TEST's immutable source snapshot.

Godot ignores XDG_DATA_HOME/APPDATA on macOS. Reuse the graphics tools' guarded
project-settings parser and APFS clone helper, but change only the project name:
this benchmark must retain the actual production renderer/effects configuration.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import uuid

from tools.graphics.launch import _research_project_settings


def _hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare_macos_launch(snapshot: dict, run_dir: Path, *, user_home: Path | None = None) -> dict:
    """Make a verified private launch copy; never rename or edit shared inputs.

    The canonical snapshot remains reusable across suite cases and platforms.
    macOS keeps this run's unique profile in its standard Application Support
    location. The exact owned path is retained in the receipt, never the player's
    normal profile, and is validated again by the in-app startup observer.
    """
    source = Path(snapshot["root"])
    settings, original_hash = _research_project_settings(source / "app")
    if settings.get("application/config/name") != '"OpenRC Simulator"':
        raise ValueError("macOS GOD TEST requires a canonical source project name")
    if settings.get("application/config/use_custom_user_dir", "false") != "false":
        raise ValueError("macOS GOD TEST refuses custom user-directory settings")
    if settings.get("application/config/project_settings_override", '""') != '""':
        raise ValueError("macOS GOD TEST refuses project settings overrides")
    if settings.get("application/config/use_hidden_project_data_directory", "true") != "true":
        raise ValueError("macOS GOD TEST requires the snapshot's separate .godot cache")
    for name in ("override.cfg", "project.binary"):
        if os.path.lexists(source / "app" / name):
            raise ValueError(f"macOS GOD TEST refuses {name}")
    project_name = "OpenRC-GodTest-" + uuid.uuid4().hex
    user_dir = (user_home or Path.home()) / "Library/Application Support/Godot/app_userdata" / project_name
    if os.path.lexists(user_dir):
        raise ValueError("macOS GOD TEST profile already exists")
    destination = run_dir / "mac-source"
    destination.mkdir(exist_ok=False)
    clone = None
    if sys.platform == "darwin":
        from tools.graphics.prepare_research import _macos_clonefile
        clone = _macos_clonefile()
    copy_mode = "apfs_clone" if clone else "copy"
    for relative, expected in {**snapshot["files"], **snapshot["imports"]}.items():
        item = Path(relative)
        if item.is_absolute() or ".." in item.parts or "\\" in relative:
            raise ValueError("invalid snapshot input path")
        original, copied = source / item, destination / item
        if original.is_symlink() or not original.resolve().is_relative_to(source.resolve()) or _hash(original) != expected:
            raise ValueError(f"snapshot changed or linked input: {relative}")
        copied.parent.mkdir(parents=True, exist_ok=True)
        if clone:
            # APFS clone is exclusive and has no silent cross-filesystem fallback.
            clone(original, copied)
        else:
            shutil.copy2(original, copied)
        if _hash(copied) != expected or _hash(original) != expected:
            raise ValueError(f"snapshot changed during macOS preparation: {relative}")
    project = destination / "app/project.godot"
    original = project.read_bytes()
    line = b'config/name="OpenRC Simulator"'
    if original.count(line) != 1 or _hash(project) != original_hash:
        raise ValueError("canonical project name changed during macOS preparation")
    project.write_bytes(original.replace(line, f'config/name="{project_name}"'.encode(), 1))
    files = dict(snapshot["files"], **{"app/project.godot": _hash(project)})
    user_dir.mkdir(parents=True, exist_ok=False)
    return {**snapshot, "root": str(destination), "files": files,
            "source_digest": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(),
            "project_mutated": True,
            "profile_isolation": {"format": "openrc-godtest-macos-profile-v1", "copy_mode": copy_mode,
                "project_name": project_name, "user_dir": str(user_dir),
                "canonical_source_digest": snapshot.get("source_digest"),
                "original_project_sha256": original_hash, "launch_project_sha256": files["app/project.godot"],
                "changed_settings": ["application/config/name"], "player_profile_touched": False,
                "retention": "owned unique macOS profile retained; do not remove until evidence is retained"}}
