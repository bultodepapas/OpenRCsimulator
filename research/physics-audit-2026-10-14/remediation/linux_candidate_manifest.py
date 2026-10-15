#!/usr/bin/env python3
"""Derive a candidate Linux verification manifest from a verified base and explicit overlays."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import stat
from datetime import datetime, timezone


def sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def build(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    base_path = Path(args.base).resolve()
    after_path = Path(args.after).resolve()
    overlay_path = Path(args.overlay_manifest).resolve()
    patch_path = Path(args.patch).resolve()
    output_path = Path(args.output).resolve()
    base = json.loads(base_path.read_text(encoding="utf-8"))
    after = json.loads(after_path.read_text(encoding="utf-8"))
    overlay = json.loads(overlay_path.read_text(encoding="utf-8"))
    before_files = {item["path"]: item for item in base["files"]}
    after_files = {item["path"]: item for item in after["files"]}
    overlay_files = overlay.get("files", {})
    changed = set(after["comparison_to_snapshot"]["changed"])
    added = set(after["comparison_to_snapshot"]["added"])
    removed = set(after["comparison_to_snapshot"]["removed"])
    if removed or changed != set(overlay_files):
        raise RuntimeError(f"unexpected source deltas: changed={sorted(changed)} removed={sorted(removed)}")
    if any(not path.endswith(".uid") for path in added):
        raise RuntimeError(f"unexpected non-Godot-UID additions: {sorted(added)}")
    records: list[dict] = []
    for rel, expected_hash in sorted(overlay_files.items()):
        path = root / Path(rel)
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            raise RuntimeError(f"overlay candidate is not a regular file: {rel}")
        actual_hash, actual_size = sha256_file(path)
        if actual_hash != expected_hash:
            raise RuntimeError(f"overlay source hash mismatch for {rel}: {actual_hash} != {expected_hash}")
        record = after_files.get(rel)
        if record is None or record["snapshot_sha256"] != expected_hash or record["snapshot_size_bytes"] != actual_size:
            raise RuntimeError(f"post-overlay source manifest does not bind {rel}")
        record["source_observed_mode"] = oct(stat.S_IMODE(info.st_mode))
        record["snapshot_mode"] = oct(stat.S_IMODE(info.st_mode))
        records.append({
            "path": rel,
            "sha256": actual_hash,
            "size_bytes": actual_size,
            "mode": oct(stat.S_IMODE(info.st_mode)),
        })

    patch_sha256, patch_size = sha256_file(patch_path)
    overlay_sha256, overlay_size = sha256_file(overlay_path)
    base_sha256, base_size = sha256_file(base_path)
    candidate = copy.deepcopy(base)
    candidate["format"] = "openrc-linux-candidate-source-manifest-v1"
    candidate["captured_utc"] = datetime.now(timezone.utc).isoformat()
    candidate["source_scope"] = (
        "fixed-commit Git archive with R05B overlays, plus the four explicit AV-17-R2 portability overlay files; "
        "the original fixed-commit archive remains the immutable base identity"
    )
    candidate["files"] = after["files"]
    candidate["source_file_count"] = len(candidate["files"])
    candidate["candidate_overlay"] = {
        "base_manifest": {"path": os.fspath(base_path), "sha256": base_sha256, "size_bytes": base_size},
        "post_test_pre_overlay_manifest": {"path": os.fspath(after_path), "captured_utc": after["captured_utc"]},
        "overlay_manifest": {"path": os.fspath(overlay_path), "sha256": overlay_sha256, "size_bytes": overlay_size},
        "patch": {"path": os.fspath(patch_path), "sha256": patch_sha256, "size_bytes": patch_size},
        "files": records,
        "pre_candidate_test_sidecars": sorted(added),
        "pre_candidate_changed_source_paths": sorted(changed),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(candidate, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"candidate manifest written: {output_path}; overlay files={len(records)}; "
        f"pre-existing Godot UID sidecars={len(added)}; candidate paths verified"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--overlay-manifest", required=True)
    parser.add_argument("--patch", required=True)
    parser.add_argument("--output", required=True)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
