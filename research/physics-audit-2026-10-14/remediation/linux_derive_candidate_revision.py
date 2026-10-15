#!/usr/bin/env python3
"""Derive an R11 candidate manifest from an existing verified Linux candidate.

Only explicitly named patch outputs may differ from the parent manifest. This avoids
recapturing the multi-gigabyte fixed-commit archive between small, audited revisions.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
from datetime import datetime, timezone


def sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def tracked_and_nonignored(root: Path) -> set[str]:
    raw = subprocess.run(
        ["git", "-C", os.fspath(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    return {os.fsdecode(item) for item in raw.split(b"\0") if item}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--parent-manifest", required=True, type=Path)
    parser.add_argument("--overlay", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    parent_path = args.parent_manifest.resolve()
    overlay_path = args.overlay.resolve()
    output_path = args.output.resolve()
    parent = json.loads(parent_path.read_text(encoding="utf-8"))
    overlay = json.loads(overlay_path.read_text(encoding="utf-8"))
    expected_files = {record["path"]: record for record in parent["files"]}
    actual_paths = tracked_and_nonignored(root)
    if actual_paths != set(expected_files):
        raise RuntimeError(
            "candidate path-set changed: "
            f"added={sorted(actual_paths - set(expected_files))}; "
            f"removed={sorted(set(expected_files) - actual_paths)}"
        )

    permitted = overlay.get("files", {})
    if not permitted:
        raise RuntimeError("overlay must bind changed source paths to SHA-256 values")
    changed: list[dict] = []
    records: list[dict] = []
    for rel in sorted(expected_files):
        old = copy.deepcopy(expected_files[rel])
        path = root / Path(rel)
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            raise RuntimeError(f"expected a regular file: {rel}")
        digest, size = sha256_file(path)
        mode = oct(stat.S_IMODE(info.st_mode))
        if rel in permitted:
            if digest != permitted[rel]["sha256"]:
                raise RuntimeError(f"overlay hash mismatch for {rel}: {digest}")
            old.update({
                "source_sha256": digest,
                "source_size_bytes": size,
                "snapshot_sha256": digest,
                "snapshot_size_bytes": size,
                "source_observed_mode": mode,
                "snapshot_mode": mode,
            })
            changed.append({"path": rel, "sha256": digest, "size_bytes": size, "mode": mode})
        elif digest != old["snapshot_sha256"] or size != old["snapshot_size_bytes"] or mode != old["snapshot_mode"]:
            raise RuntimeError(f"unexpected change outside overlay: {rel}")
        records.append(old)

    if set(permitted) != {item["path"] for item in changed}:
        raise RuntimeError("overlay paths do not match the observed candidate changes")
    if len(changed) != len(permitted):
        raise RuntimeError("overlay contains duplicate or missing changed paths")

    patch_records: list[dict] = []
    for item in overlay.get("patches", []):
        patch_path = Path(item["path"]).resolve()
        digest, size = sha256_file(patch_path)
        if digest != item["sha256"]:
            raise RuntimeError(f"patch hash mismatch for {patch_path}: {digest}")
        patch_records.append({"path": os.fspath(patch_path), "sha256": digest, "size_bytes": size})
    parent_hash, parent_size = sha256_file(parent_path)
    overlay_hash, overlay_size = sha256_file(overlay_path)

    candidate = copy.deepcopy(parent)
    candidate["format"] = "openrc-linux-candidate-source-manifest-v1"
    candidate["captured_utc"] = datetime.now(timezone.utc).isoformat()
    candidate["source_scope"] += "; derived from the prior candidate with only the explicitly listed R11 patches"
    candidate["files"] = records
    candidate["source_file_count"] = len(records)
    candidate.setdefault("candidate_overlay", {}).setdefault("derived_revisions", []).append({
        "revision_id": overlay["revision_id"],
        "parent_manifest": {"path": os.fspath(parent_path), "sha256": parent_hash, "size_bytes": parent_size},
        "overlay_manifest": {"path": os.fspath(overlay_path), "sha256": overlay_hash, "size_bytes": overlay_size},
        "patches": patch_records,
        "files": changed,
    })
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(candidate, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"derived candidate manifest: {output_path}; changed files={len(changed)}; source paths={len(records)}")


if __name__ == "__main__":
    main()
