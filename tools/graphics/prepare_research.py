#!/usr/bin/env python3
"""Prepare a new isolated OpenRC app copy for graphics research; do not launch it."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import uuid

try:
    from . import launch
except ImportError:  # Support execution as a script.
    import launch  # type: ignore[no-redef]


FORMAT = "openrc-graphics-research-preparation v1"
RECEIPT = "research-preparation.json"
_EXCLUDED_TOP = {".godot", ".tools", "captures", "tmp"}
_EXCLUDED_ANY = {".godot", ".tools", "__pycache__"}
_NAME_LINE = b'config/name="OpenRC Simulator"'
_MULTI_BOUNCE_ON = b"lights_and_shadows/multi_bounce_occlusion/enabled=true"
_MULTI_BOUNCE_OFF = b"lights_and_shadows/multi_bounce_occlusion/enabled=false"


class PreparationError(ValueError):
    """A failed preparation; any created destination remains for inspection."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _is_link(path: Path) -> bool:
    if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
        return True
    attributes = getattr(path.lstat(), "st_file_attributes", 0)
    return bool(attributes & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))


def _inside(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def _git_identity(source: Path) -> dict:
    """Optional labels; the copied-file manifest is the content identity."""
    try:
        commit = subprocess.run(
            ["git", "rev-parse", "--verify", "HEAD"], cwd=source, capture_output=True,
            text=True, check=True, timeout=10,
        ).stdout.strip()
        status = subprocess.run(
            ["git", "status", "--porcelain=v1", "--untracked-files=normal", "--", "app/", "assets/"],
            cwd=source, capture_output=True, text=True, check=True, timeout=30,
        ).stdout
        return {"commit": commit, "app_or_assets_dirty": bool(status),
                "status_sha256": hashlib.sha256(status.encode("utf-8")).hexdigest()}
    except (OSError, UnicodeError, subprocess.SubprocessError):
        return {"commit": None, "app_or_assets_dirty": None, "status_sha256": None}


def _preflight(source: Path, destination: Path) -> tuple[Path, Path, bytes]:
    source_app = (source / "app").resolve()
    source_assets = (source / "assets").resolve()
    if not source_app.is_dir() or not source_assets.is_dir():
        raise PreparationError("source must contain app/ and sibling assets/ directories")
    if destination == source or _inside(destination, source_app) or _inside(destination, source_assets):
        raise PreparationError("destination must be outside the source app/ and assets/ directories")
    if any((source_app / name).exists() or (source_app / name).is_symlink()
           for name in ("override.cfg", "project.binary")):
        raise PreparationError("source app cannot contain override.cfg or project.binary")
    project = source_app / "project.godot"
    profile = source_app / "render" / "high_graphics_profile.gd"
    if not project.is_file() or not profile.is_file() or _is_link(project) or _is_link(profile):
        raise PreparationError("source needs regular project.godot and render/high_graphics_profile.gd files")
    try:
        original = project.read_bytes()
        settings, _ = launch._research_project_settings(source_app)
        live_profile = launch.APP_DIR / "render" / "high_graphics_profile.gd"
        if profile.read_bytes() != live_profile.read_bytes():
            raise PreparationError("source graphics profile differs from this launcher")
    except (OSError, launch.LaunchError) as error:
        raise PreparationError(f"cannot validate source project: {error}") from error
    if settings.get("application/config/name") != '"OpenRC Simulator"' or original.count(_NAME_LINE) != 1:
        raise PreparationError("source project must have the canonical OpenRC Simulator project name")
    if settings.get("application/config/use_custom_user_dir", "false") != "false":
        raise PreparationError("source project cannot set a custom user-data directory")
    if settings.get("application/config/project_settings_override", '""') != '""':
        raise PreparationError("source project cannot use a settings override")
    if settings.get("application/config/use_hidden_project_data_directory", "true") != "true":
        raise PreparationError("source project must use its .godot cache")
    bounce = settings.get("rendering/lights_and_shadows/multi_bounce_occlusion/enabled")
    if bounce not in ("true", "false") or original.count(_MULTI_BOUNCE_ON) + original.count(_MULTI_BOUNCE_OFF) != 1:
        raise PreparationError("source must have one explicit startup multi-bounce setting")
    return source_app, source_assets, original


def prepare(source: Path, destination: Path) -> dict:
    """Create an exclusive copy, validate it, and publish the receipt last."""
    try:
        source = source.expanduser().resolve()
        raw_destination = destination.expanduser()
        if os.path.lexists(raw_destination):
            raise PreparationError(f"destination already exists: {raw_destination}")
        destination = raw_destination.resolve()
        if os.path.lexists(destination):
            raise PreparationError(f"destination already exists: {destination}")
        source_app, source_assets, original_project = _preflight(source, destination)
        source_git = _git_identity(source)
    except (OSError, RuntimeError) as error:
        raise PreparationError(f"cannot inspect source or destination: {error}") from error
    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Re-resolve after creating parents, and create the final component exclusively.
        if destination.resolve() != destination:
            raise PreparationError("destination parent changed during preparation")
        destination.mkdir()
    except OSError as error:
        raise PreparationError(f"cannot create exclusive destination {destination}: {error}") from error

    entries: list[dict] = []
    try:
        try:
            (destination / "assets").symlink_to(source_assets, target_is_directory=True)
        except OSError as error:
            raise PreparationError("cannot create the sibling assets symlink; on Windows enable symlink support "
                                   "or prepare on the Mac: " + str(error)) from error

        def ignore(directory: str, names: list[str]) -> set[str]:
            root = Path(directory)
            excluded = {name for name in names if name in _EXCLUDED_ANY
                        or (root == source_app and name in _EXCLUDED_TOP)}
            for name in names:
                if name not in excluded and _is_link(root / name):
                    raise PreparationError(f"source app contains a link; refusing to copy it: {root / name}")
            return excluded

        def copy_verified(src: str, dst: str) -> str:
            source_file, copied_file = Path(src), Path(dst)
            if not stat.S_ISREG(source_file.stat().st_mode):
                raise PreparationError(f"source app contains a non-regular file: {source_file}")
            before = _sha256(source_file)
            shutil.copy2(source_file, copied_file)
            after = _sha256(source_file)
            copied = _sha256(copied_file)
            if before != after or before != copied:
                raise PreparationError(f"source changed or copy verification failed: {source_file}")
            entries.append({"path": source_file.relative_to(source_app).as_posix(),
                            "bytes": copied_file.stat().st_size, "sha256": copied})
            return str(copied_file)

        copied_app = destination / "app"
        shutil.copytree(source_app, copied_app, ignore=ignore, copy_function=copy_verified)
        project_path = copied_app / "project.godot"
        copied_project = project_path.read_bytes()
        if copied_project != original_project or (source_app / "project.godot").read_bytes() != original_project:
            raise PreparationError("source project settings changed while preparing the copy")
        project_name = "OpenRC-Research-" + uuid.uuid4().hex
        isolated_project = copied_project.replace(_NAME_LINE, f'config/name="{project_name}"'.encode(), 1)
        isolated_project = isolated_project.replace(_MULTI_BOUNCE_ON, _MULTI_BOUNCE_OFF, 1)
        project_path.write_bytes(isolated_project)
        entries.sort(key=lambda item: item["path"])
        validated = launch._research_project(str(copied_app), cwd=destination)
        if validated["project_name"] != project_name:
            raise PreparationError("prepared project identity does not match its generated name")

        def inventory(root: Path, *, source_tree: bool) -> list[dict]:
            found: list[dict] = []

            def fail_walk(error: OSError) -> None:
                raise PreparationError(f"cannot inspect copied file identities: {error}") from error

            for directory, dirs, files in os.walk(root, followlinks=False, onerror=fail_walk):
                excluded = ignore(directory, dirs + files) if source_tree else set()
                dirs[:] = sorted(name for name in dirs if name not in excluded)
                for name in dirs + files:
                    if name not in excluded and _is_link(Path(directory) / name):
                        raise PreparationError(f"link appeared during preparation: {Path(directory) / name}")
                for name in sorted(name for name in files if name not in excluded):
                    path = Path(directory) / name
                    if not stat.S_ISREG(path.stat().st_mode):
                        raise PreparationError(f"non-regular file appeared during preparation: {path}")
                    found.append({"path": path.relative_to(root).as_posix(),
                                  "bytes": path.stat().st_size, "sha256": _sha256(path)})
            return sorted(found, key=lambda item: item["path"])

        if inventory(source_app, source_tree=True) != entries:
            raise PreparationError("source app changed during preparation; retry from a frozen snapshot")
        expected_copy = [dict(item) for item in entries]
        for item in expected_copy:
            if item["path"] == "project.godot":
                item["bytes"] = len(isolated_project)
                item["sha256"] = hashlib.sha256(isolated_project).hexdigest()
        verified_copy = inventory(copied_app, source_tree=False)
        if verified_copy != expected_copy:
            raise PreparationError("copied app changed during verification; partial destination retained")
        if _git_identity(source) != source_git:
            raise PreparationError("source Git identity changed during preparation; retry from a frozen snapshot")
        manifest = json.dumps(entries, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
        manifest_sha256 = hashlib.sha256(manifest).hexdigest()
        destination_manifest = json.dumps(verified_copy, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
        destination_manifest_sha256 = hashlib.sha256(destination_manifest).hexdigest()
        receipt = {
            "format": FORMAT, "complete": True,
            "source": {"root": str(source), "app": str(source_app), "git": source_git,
                       "project_sha256": hashlib.sha256(original_project).hexdigest(),
                       "copied_app_manifest_sha256": manifest_sha256,
                       "copied_files": len(entries), "copied_bytes": sum(item["bytes"] for item in entries),
                       "excluded_top_level": sorted(_EXCLUDED_TOP), "excluded_anywhere": sorted(_EXCLUDED_ANY)},
            "destination": {"root": str(destination), "app": str(copied_app),
                            "project_name": project_name, "project_sha256": validated["project_sha256"],
                            "profile_sha256": validated["profile_sha256"],
                            "copied_app_manifest_sha256": destination_manifest_sha256,
                            "copy_manifest_sha256_before_project_edits": manifest_sha256,
                            "assets_symlink_target": str(source_assets)},
            "scope": "Per-file copy hashes verified before the two project-setting edits. "
                     "Sibling author assets are linked, not copied or hashed; freeze them separately. "
                     "No import, launch, renderer or hardware qualification was performed.",
        }
        pending = destination / "research-preparation.pending.json"
        with pending.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(receipt, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        # A hard-link publishes exclusively without replacing another receipt.
        # A failed/interrupted write leaves only a visibly pending artifact.
        os.link(pending, destination / RECEIPT)
        try:
            pending.unlink()
        except OSError:
            pass  # The complete receipt is already published; the duplicate is harmless.
        return receipt
    except (OSError, shutil.Error, PreparationError, launch.LaunchError) as error:
        raise PreparationError(f"preparation failed; partial destination retained at {destination}: {error}") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=launch.REPO_ROOT, help="source repository (default: this checkout)")
    parser.add_argument("--dest", type=Path, required=True, help="new destination directory; never overwritten")
    options = parser.parse_args(argv)
    try:
        receipt = prepare(options.source, options.dest)
    except PreparationError as error:
        print(f"Research preparation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(receipt, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
