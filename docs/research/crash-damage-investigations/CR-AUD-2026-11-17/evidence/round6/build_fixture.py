#!/usr/bin/env python3
"""Recreate the audited component project from exact source-manifest copies.

This deliberately does not create a full production application or install an
engine. Use a hydrated checkout at the recorded revision. Generated imports,
autoloads, native package receipts and full UI behavior are not represented.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-repo", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--check-source", action="store_true",
                        help="Verify source hashes without writing a fixture.")
    args = parser.parse_args()
    manifest = json.loads((HERE / "source-manifest.json").read_text())
    source = args.source_repo.resolve()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if commit != manifest["source_commit"]:
        parser.error("Source HEAD differs from the recorded audit revision.")
    if not args.check_source and args.out is None:
        parser.error("Provide a fresh --out, or use --check-source.")
    out = args.out.resolve() if args.out else None
    if not args.check_source and out.exists():
        parser.error("--out already exists; existing evidence is never overwritten.")
    # Verify the entire requested source set before creating any deliverable.
    for row in manifest["files"]:
        relative = Path(row["path"])
        if relative.is_absolute() or ".." in relative.parts:
            parser.error("Invalid relative source path in the manifest.")
        path = source / relative
        if not path.is_file():
            parser.error(f"Hydrate the recorded source resource: {relative}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
            parser.error(f"Recorded source hash differs: {relative}")
    if args.check_source:
        print(f"Verified {len(manifest['files'])} source files at {commit}.")
        return 0
    out.mkdir(parents=True)
    for row in manifest["files"]:
        target = out / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / row["path"], target)
    (out / "app" / "project.godot").write_text(manifest["project_text"])
    (out / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Created exact-source component fixture: {out / 'app'}")
    print("Import with the pinned engine through tools/godot/run_checked.py before running probes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
