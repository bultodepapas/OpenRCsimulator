#!/usr/bin/env python3
"""Store an identical visual mutation project once; reconstruct independent files.

This is an artifact-storage optimization, never a capture/check result. Prepare
only after capture success. Originals are never changed. An unsupported or
different tree leaves the existing full upload intact.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import stat
import sys
import tempfile

FORMAT = "openrc-capture-project-copy v1"
REFERENCE = "l9c/unfiltered-stripe-app"
TARGET = "l9c/stripes/raw-app"
MANIFEST = "capture-project-copy.json"
RESTORER = "restore-capture-project.py"


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def inventory(root: Path) -> dict[str, dict]:
    """Match the current artifact's non-hidden files; refuse links/special files.

    The upload action follows links. Rather than guess their external contents
    or directory traversal, any visible link keeps the full original upload.
    Hidden entries were already excluded by upload-artifact v4.6.2.
    """
    if not root.is_dir() or root.is_symlink():
        raise ValueError(f"missing or unsupported project: {root}")
    entries = {}
    def unreadable(error: OSError) -> None:
        raise error

    for directory, directories, files in os.walk(root, onerror=unreadable):
        directories[:] = sorted(name for name in directories if not name.startswith("."))
        for name in [*directories, *(name for name in files if not name.startswith("."))]:
            path = Path(directory, name)
            before = path.lstat()
            if stat.S_ISDIR(before.st_mode):
                continue
            if not stat.S_ISREG(before.st_mode):
                raise ValueError(f"unsupported artifact entry: {path}")
            sha = digest(path)
            after = path.stat()
            if (before.st_ino, before.st_size, before.st_mtime_ns, before.st_mode) != (
                    after.st_ino, after.st_size, after.st_mtime_ns, after.st_mode):
                raise ValueError(f"project changed during inspection: {path}")
            entries[path.relative_to(root).as_posix()] = {
                "size": after.st_size, "sha256": sha,
                "mode": stat.S_IMODE(after.st_mode),
            }
    if not entries:
        raise ValueError(f"empty project: {root}")
    if len({name.casefold() for name in entries}) != len(entries):
        raise ValueError(f"case-insensitive path collision: {root}")
    return dict(sorted(entries.items()))


def project_root(captures: Path, relative: str) -> Path:
    root = captures / relative
    if any(path.is_symlink() for path in [root, *root.parents] if path != captures.parent):
        raise ValueError(f"symbolic project ancestor: {root}")
    return root


def prepare(captures: Path) -> dict:
    reference = project_root(captures, REFERENCE)
    target = project_root(captures, TARGET)
    first, second = inventory(reference), inventory(target)
    if first != second:
        raise ValueError("mutation projects differ; retaining both complete trees")
    destinations = [captures / MANIFEST, captures / RESTORER]
    if any(path.exists() or path.is_symlink() for path in destinations):
        raise ValueError("reconstruction metadata already exists; retaining original upload")
    helper = Path(__file__).read_bytes()
    manifest = {
        "format": FORMAT,
        "reference": REFERENCE,
        "target": TARGET,
        "eligibility": "non-hidden regular files; links use the full upload",
        "files": first,
        "file_count": len(first),
        "duplicate_bytes": sum(item["size"] for item in first.values()),
        "restorer_sha256": hashlib.sha256(helper).hexdigest(),
    }
    # Publish metadata completely before the workflow is allowed to omit a tree.
    with tempfile.TemporaryDirectory(prefix=".capture-copy-", dir=captures) as staging:
        stage = Path(staging)
        (stage / RESTORER).write_bytes(helper)
        (stage / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if digest(stage / RESTORER) != manifest["restorer_sha256"]:
            raise ValueError("reconstruction helper verification failed")
        validate_manifest(json.loads((stage / MANIFEST).read_text(encoding="utf-8")))
        # Do not replace earlier evidence, even if a second preparer raced us.
        for name in (RESTORER, MANIFEST):
            with (captures / name).open("xb") as stream:
                stream.write((stage / name).read_bytes())
    if digest(captures / RESTORER) != manifest["restorer_sha256"] or (
            json.loads((captures / MANIFEST).read_text(encoding="utf-8")) != manifest):
        raise ValueError("published reconstruction metadata verification failed")
    return manifest


def validate_manifest(value: dict) -> dict[str, dict]:
    if not isinstance(value, dict) or value.get("format") != FORMAT or (
            value.get("reference"), value.get("target")) != (REFERENCE, TARGET):
        raise ValueError("unrecognized project-copy manifest")
    files = value.get("files")
    if (not isinstance(files, dict) or not files or type(value.get("file_count")) is not int
            or value["file_count"] != len(files)):
        raise ValueError("invalid project-copy file roster")
    for name, entry in files.items():
        path = PurePosixPath(name)
        if (not name or path.is_absolute() or path.as_posix() != name or "\\" in name
                or PureWindowsPath(name).drive
                or any(part.startswith(".") for part in path.parts)):
            raise ValueError(f"invalid project-copy path: {name}")
        if not isinstance(entry, dict) or set(entry) != {"size", "sha256", "mode"}:
            raise ValueError(f"invalid project-copy record: {name}")
        if type(entry["size"]) is not int or entry["size"] < 0 or (
                type(entry["mode"]) is not int or not 0 <= entry["mode"] <= 0o777):
            raise ValueError(f"invalid project-copy metadata: {name}")
        if not isinstance(entry["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]):
            raise ValueError(f"invalid project-copy digest: {name}")
    if (type(value.get("duplicate_bytes")) is not int
            or value["duplicate_bytes"] != sum(item["size"] for item in files.values())):
        raise ValueError("project-copy byte count does not match roster")
    return files


def content_inventory(entries: dict[str, dict]) -> dict[str, dict]:
    # GitHub's ZIP download normalizes file permissions. Bytes/roster must match;
    # restore applies the original mode recorded before upload to the new files.
    return {name: {key: entry[key] for key in ("size", "sha256")} for name, entry in entries.items()}


def restore(captures: Path) -> dict:
    value = json.loads((captures / MANIFEST).read_text(encoding="utf-8"))
    files = validate_manifest(value)
    if digest(captures / RESTORER) != value.get("restorer_sha256"):
        raise ValueError("reconstruction helper differs from the recorded helper")
    reference = project_root(captures, REFERENCE)
    target = project_root(captures, TARGET)
    if target.exists() or target.is_symlink():
        raise ValueError(f"refusing existing reconstruction destination: {target}")
    if content_inventory(inventory(reference)) != content_inventory(files):
        raise ValueError("retained project no longer matches the complete file roster")
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".raw-app-restore-", dir=target.parent) as staging:
        staged = Path(staging) / "project"
        staged.mkdir()
        for name, entry in files.items():
            destination = staged / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            # Fresh copies are essential: hard links would couple later edits in
            # independent mutation projects and invalidate their experiments.
            shutil.copyfile(reference / name, destination)
            destination.chmod(entry["mode"])
        observed = inventory(staged)
        if (content_inventory(observed) != content_inventory(files)
                or (os.name != "nt" and observed != files)):
            raise ValueError("reconstructed project failed its byte/mode verification")
        if target.exists() or target.is_symlink():
            raise ValueError(f"reconstruction destination appeared during copy: {target}")
        staged.rename(target)
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "restore"))
    parser.add_argument("--captures", type=Path)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    captures = (args.captures or Path(__file__).resolve().parent).absolute()
    if args.command == "restore":
        if args.github_output:
            parser.error("--github-output is only valid for prepare")
        value = restore(captures)
        print(f"Restored {value['file_count']} independent files to {captures / TARGET}.")
        return 0
    if args.captures is None:
        parser.error("prepare requires --captures")
    equivalent = False
    try:
        value = prepare(captures)
        equivalent = True
        print(f"Identical mutation project: {value['file_count']} files, "
              f"{value['duplicate_bytes']} uncompressed duplicate bytes. "
              "Captures and original projects are unchanged; upload/elapsed savings are not measured here.")
    except (OSError, ValueError) as exc:
        print(f"Full capture upload retained: {exc}")
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as stream:
            stream.write(f"equivalent={'true' if equivalent else 'false'}\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"Capture project evidence failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
