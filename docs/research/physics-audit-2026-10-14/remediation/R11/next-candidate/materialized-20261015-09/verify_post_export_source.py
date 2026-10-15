#!/usr/bin/env python3
"""Verify -09 source-manifest bytes after export, classifying separate support/output files."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess


ROOT = Path("/home/bulto/openrc-r11-package-20261015-09")
REPO = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator")
MANIFEST = REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/derived-package-20261015-09/candidate-after-overlays.json"
EXPECTED_MANIFEST_SHA = "bd9cc04069b725b1317bb3125c5f06bb0d338336d1f5e41b93c81e552ce3eebc"
OUT = REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-09/post-export-source-audit-01.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def entry(path: Path, relative: str) -> dict[str, object]:
    mode = f"0o{stat.S_IMODE(path.lstat().st_mode):o}"
    if path.is_symlink():
        return {"path": relative, "kind": "symlink", "target": os.readlink(path), "mode": mode}
    if not path.is_file():
        raise RuntimeError(f"unexpected non-file manifest entry: {relative}")
    return {
        "path": relative,
        "kind": "file",
        "sha256": sha256(path),
        "size_bytes": path.stat().st_size,
        "mode": mode,
    }


def classify(relative: str) -> str | None:
    if relative == ".tools/Godot_v4.7.2-stable_linux.x86_64":
        return "separately_recorded_pinned_engine_support"
    if relative.startswith("app/.godot/"):
        return "generated_godot_import_cache"
    if relative.startswith("dist/"):
        return "export_artifact"
    if relative.endswith(".uid"):
        return "generated_uid_sidecar"
    if relative.startswith("tmp/"):
        return "temporary_tool_output"
    return None


def main() -> None:
    if sha256(MANIFEST) != EXPECTED_MANIFEST_SHA:
        raise RuntimeError("approved -09 candidate manifest changed")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = manifest["entries"]
    expected_map = {str(item["path"]): item for item in expected}
    if len(expected_map) != len(expected):
        raise RuntimeError("approved source manifest has duplicate paths")

    actual_map: dict[str, dict[str, object]] = {}
    for current, dirs, files in os.walk(ROOT, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for name in sorted(dirs):
            path = current_path / name
            relative = path.relative_to(ROOT).as_posix()
            if relative == ".git":
                continue
            if path.is_symlink():
                actual_map[relative] = entry(path, relative)
            else:
                kept_dirs.append(name)
        dirs[:] = kept_dirs
        for name in sorted(files):
            path = current_path / name
            relative = path.relative_to(ROOT).as_posix()
            if relative.startswith(".git/"):
                continue
            actual_map[relative] = entry(path, relative)

    missing = sorted(set(expected_map) - set(actual_map))
    changed = [
        {"path": relative, "expected": expected_map[relative], "actual": actual_map[relative]}
        for relative in sorted(set(expected_map) & set(actual_map))
        if expected_map[relative] != actual_map[relative]
    ]
    extra = []
    for relative in sorted(set(actual_map) - set(expected_map)):
        row = actual_map[relative]
        extra.append(row | {"classification": classify(relative) or "unclassified"})
    unclassified = [str(row["path"]) for row in extra if row["classification"] == "unclassified"]

    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, env=env, check=True, capture_output=True, text=True).stdout.strip()
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=ROOT, env=env, check=True, capture_output=True, text=True).stdout.strip()
    status = subprocess.run(["git", "status", "--porcelain=v1", "--untracked-files=all"], cwd=ROOT, env=env, check=True, capture_output=True, text=True).stdout.splitlines()
    status_hash = hashlib.sha256(("\n".join(status) + "\n").encode("utf-8")).hexdigest()

    report = {
        "format": "openrc-r11-post-export-source-audit-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "candidate": str(ROOT),
        "approved_source_manifest": str(MANIFEST),
        "approved_source_manifest_sha256": EXPECTED_MANIFEST_SHA,
        "expected_source_entries": len(expected),
        "missing_source_paths": missing,
        "changed_source_paths": changed,
        "extra_entry_count": len(extra),
        "extra_classification_counts": {
            category: sum(1 for row in extra if row["classification"] == category)
            for category in sorted({str(row["classification"]) for row in extra})
        },
        "unclassified_extra_paths": unclassified,
        "extra_entries": extra,
        "git": {"head": head, "branch": branch, "status_count": len(status), "status_sha256": status_hash, "status": status},
        "source_manifest_matches": not missing and not changed and not unclassified,
    }
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(OUT),
        "source_manifest_matches": report["source_manifest_matches"],
        "expected_source_entries": len(expected),
        "missing": len(missing),
        "changed": len(changed),
        "extra": len(extra),
        "unclassified_extra": len(unclassified),
        "git_head": head,
        "git_status_count": len(status),
        "git_status_sha256": status_hash,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
