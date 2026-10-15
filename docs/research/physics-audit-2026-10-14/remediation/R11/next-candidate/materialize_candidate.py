#!/usr/bin/env python3
"""Physically clone the reviewed R11 source snapshot and apply an exact allowlist."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json_sha256(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def safe_relpath(value: str) -> PurePosixPath:
    rel = PurePosixPath(value)
    if rel.is_absolute() or not rel.parts or any(part in ("", ".", "..") for part in rel.parts):
        raise RuntimeError(f"unsafe relative path in manifest: {value!r}")
    return rel


def walk_entries(root: Path) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for directory in sorted(dirs):
            path = current_path / directory
            if path.is_symlink():
                rel = path.relative_to(root).as_posix()
                entries.append({
                    "path": rel,
                    "kind": "symlink",
                    "target": os.readlink(path),
                    "mode": f"0o{stat.S_IMODE(path.lstat().st_mode):o}",
                })
            else:
                kept_dirs.append(directory)
        dirs[:] = kept_dirs
        for filename in sorted(files):
            path = current_path / filename
            rel = path.relative_to(root).as_posix()
            mode = f"0o{stat.S_IMODE(path.lstat().st_mode):o}"
            if path.is_symlink():
                entries.append({"path": rel, "kind": "symlink", "target": os.readlink(path), "mode": mode})
            else:
                entries.append({
                    "path": rel,
                    "kind": "file",
                    "sha256": sha256_file(path),
                    "size_bytes": path.stat().st_size,
                    "mode": mode,
                })
    entries.sort(key=lambda item: str(item["path"]))
    return entries


def write_manifest(path: Path, root: Path, entries: list[dict[str, object]], purpose: str) -> dict[str, object]:
    tree_sha = canonical_json_sha256(entries)
    value = {
        "format": "openrc-r11-candidate-tree-manifest-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "purpose": purpose,
        "root": str(root),
        "entry_count": len(entries),
        "tree_sha256": tree_sha,
        "entries": entries,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    value["manifest_path"] = str(path)
    value["manifest_sha256"] = sha256_file(path)
    return value


def manifest_summary(value: dict[str, object]) -> dict[str, object]:
    return {
        "manifest_path": value["manifest_path"],
        "manifest_sha256": value["manifest_sha256"],
        "root": value["root"],
        "entry_count": value["entry_count"],
        "tree_sha256": value["tree_sha256"],
    }


def copy_stream(src: Path, dst: Path, mode: int, expected_sha: str) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    with src.open("rb") as source, dst.open("wb") as target:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b""):
            digest.update(block)
            target.write(block)
    actual_sha = digest.hexdigest()
    if actual_sha != expected_sha:
        dst.unlink(missing_ok=True)
        raise RuntimeError(f"source bytes drifted for {src}: expected {expected_sha}, got {actual_sha}")
    os.chmod(dst, mode)


def git_mode(repo: Path, rel: str) -> int:
    result = subprocess.run(
        ["git", "ls-files", "--stage", "--", rel],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )
    rows = [line for line in result.stdout.splitlines() if line.strip()]
    if len(rows) != 1:
        raise RuntimeError(f"expected one tracked mode for {rel}, got {rows!r}")
    mode_text = rows[0].split(" ", 1)[0]
    return stat.S_IMODE(int(mode_text, 8))


def expected_overlay_files(allowlist: dict[str, object]) -> list[tuple[dict[str, object], dict[str, object] | None]]:
    result: list[tuple[dict[str, object], dict[str, object] | None]] = []
    for group in allowlist.get("overlays", []):
        native_root = group.get("staged_source_root")
        for item in group.get("files", []):
            result.append((item, group if native_root else None))
    return result


def manifest_entry_map(entries: list[dict[str, object]]) -> dict[str, dict[str, object]]:
    return {str(entry["path"]): entry for entry in entries}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--allowlist", required=True, type=Path)
    parser.add_argument("--candidate-manifest", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--native-stage-root", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args()

    allowlist_path = args.allowlist.resolve(strict=True)
    source_root = args.source_root.resolve(strict=True)
    candidate_manifest_path = args.candidate_manifest.resolve(strict=True)
    candidate_manifest = json.loads(candidate_manifest_path.read_text(encoding="utf-8"))
    allowlist = json.loads(allowlist_path.read_text(encoding="utf-8"))
    native_stage_root = args.native_stage_root.resolve(strict=True)
    allowlisted_native_roots = {
        str(Path(str(group["staged_source_root"])).resolve(strict=True))
        for group in allowlist.get("overlays", [])
        if group.get("staged_source_root")
    }
    if allowlisted_native_roots != {str(native_stage_root)}:
        raise RuntimeError(f"native source root differs from allowlist: {allowlisted_native_roots!r}")
    target = args.target.resolve(strict=False)
    evidence_dir = args.evidence_dir.resolve(strict=False)

    expected_manifest_sha = allowlist["base"]["physical_copy_source_manifest_sha256"]
    if sha256_file(candidate_manifest_path) != expected_manifest_sha:
        raise RuntimeError("physical-copy source manifest SHA-256 does not match allowlist")
    source_candidate = Path(candidate_manifest["snapshot_root"]).resolve(strict=True)
    if str(source_candidate) != allowlist["base"]["candidate_root"]:
        raise RuntimeError("candidate source root differs from allowlist")
    if target.exists():
        raise RuntimeError(f"candidate target already exists; refusing overwrite: {target}")
    if evidence_dir.exists():
        raise RuntimeError(f"evidence directory already exists; refusing overwrite: {evidence_dir}")
    if source_root != Path("/mnt/c/DEVELOPMENT/OpenRCsimulator").resolve(strict=True):
        raise RuntimeError(f"unexpected source root: {source_root}")
    if not source_candidate.is_dir() or source_candidate == target:
        raise RuntimeError("invalid candidate source/target")

    overlay_items = expected_overlay_files(allowlist)
    preflight_sources: list[dict[str, object]] = []
    seen_overlay_paths: set[str] = set()
    for item, native_group in overlay_items:
        rel = str(item["path"])
        safe_relpath(rel)
        if rel in seen_overlay_paths:
            raise RuntimeError(f"duplicate overlay path: {rel}")
        seen_overlay_paths.add(rel)
        if native_group is not None:
            native_root = Path(str(native_group["staged_source_root"])).resolve(strict=True)
            source = native_root / Path(rel).name
            mode = stat.S_IMODE(source.stat().st_mode)
        else:
            source = source_root.joinpath(*safe_relpath(rel).parts)
            mode = git_mode(source_root, rel)
        if not source.is_file():
            raise RuntimeError(f"overlay source is missing: {source}")
        actual_sha = sha256_file(source)
        if actual_sha != str(item["sha256"]):
            raise RuntimeError(f"overlay source hash mismatch for {rel}: expected {item['sha256']}, got {actual_sha}")
        preflight_sources.append({
            "path": rel,
            "source": str(source),
            "sha256": actual_sha,
            "mode": f"0o{mode:o}",
        })

    preflight_evidence: list[dict[str, str]] = []
    for group in allowlist.get("overlays", []):
        for evidence in group.get("derivation_evidence", []):
            rel = str(evidence["path"])
            source = source_root.joinpath(*safe_relpath(rel).parts)
            actual_sha = sha256_file(source)
            if actual_sha != str(evidence["sha256"]):
                raise RuntimeError(f"derivation evidence hash mismatch for {rel}: expected {evidence['sha256']}, got {actual_sha}")
            preflight_evidence.append({"path": rel, "sha256": actual_sha})
        provenance = group.get("provenance")
        if isinstance(provenance, dict):
            for field_name, hash_name in (("verification_report", "verification_report_sha256"), ("stage_receipt", "stage_receipt_sha256")):
                rel = str(provenance[field_name])
                source = source_root.joinpath(*safe_relpath(rel).parts)
                actual_sha = sha256_file(source)
                if actual_sha != str(provenance[hash_name]):
                    raise RuntimeError(f"provenance hash mismatch for {rel}: expected {provenance[hash_name]}, got {actual_sha}")
                preflight_evidence.append({"path": rel, "sha256": actual_sha})
                if field_name == "stage_receipt":
                    receipt = json.loads(source.read_text(encoding="utf-8"))
                    expected_lib = next(str(item["sha256"]) for item, native_group in overlay_items if native_group is not None and str(item["path"]).endswith(".so"))
                    if receipt.get("native_library_sha256") != expected_lib:
                        raise RuntimeError("native stage receipt does not identify the allowlisted library")
                    if receipt.get("native_receipt_sha256") != next(str(item["sha256"]) for item, native_group in overlay_items if native_group is not None and str(item["path"]).endswith("build-receipt.json")):
                        raise RuntimeError("native stage receipt does not identify the allowlisted build receipt")

    evidence_dir.mkdir(parents=True, exist_ok=False)
    preflight_path = evidence_dir / "source-preflight.json"
    preflight_record = {
        "format": "openrc-r11-candidate-source-preflight-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "pwd": os.getcwd(),
        "source_root": str(source_root),
        "candidate_source_root": str(source_candidate),
        "allowlist": str(allowlist_path),
        "allowlist_sha256": sha256_file(allowlist_path),
        "overlay_sources_verified": preflight_sources,
        "derivation_evidence_verified": preflight_evidence,
    }
    preflight_path.write_text(json.dumps(preflight_record, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")

    expected_source_entries = candidate_manifest["files"]
    expected_paths = {str(entry["path"]) for entry in expected_source_entries}
    if len(expected_paths) != len(expected_source_entries):
        raise RuntimeError("candidate source manifest contains duplicate paths")

    # The old candidate has import cache and untracked UID sidecars from prior test runs.
    # The archived source manifest intentionally excludes those generated files.
    dirty_untracked = {
        line[3:]
        for line in candidate_manifest.get("post_run_dirty_manifest", [])
        if line.startswith("?? ")
    }
    actual_paths: set[str] = set()
    cache_files: list[tuple[str, Path]] = []
    uid_files: list[tuple[str, Path]] = []
    unexpected: list[str] = []
    for current, dirs, files in os.walk(source_candidate, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for name in sorted(dirs):
            path = current_path / name
            rel = path.relative_to(source_candidate).as_posix()
            if rel == "app/.godot" or rel.startswith("app/.godot/"):
                if path.is_symlink():
                    cache_files.append((rel, path))
                else:
                    kept_dirs.append(name)
            elif path.is_symlink():
                if rel not in expected_paths:
                    unexpected.append(rel)
                else:
                    actual_paths.add(rel)
            else:
                kept_dirs.append(name)
        dirs[:] = kept_dirs
        for name in sorted(files):
            path = current_path / name
            rel = path.relative_to(source_candidate).as_posix()
            if rel in expected_paths:
                actual_paths.add(rel)
            elif rel.startswith("app/.godot/"):
                cache_files.append((rel, path))
            elif rel in dirty_untracked and rel.endswith(".uid"):
                uid_files.append((rel, path))
            else:
                unexpected.append(rel)
    if unexpected:
        raise RuntimeError(f"unclassified files in source candidate: {unexpected[:20]!r} ({len(unexpected)} total)")
    missing_paths = sorted(expected_paths - actual_paths)
    if missing_paths:
        raise RuntimeError(f"source candidate is missing manifested paths: {missing_paths[:20]!r} ({len(missing_paths)} total)")
    expected_uids = {path for path in dirty_untracked if path.endswith(".uid")}
    actual_uids = {rel for rel, _path in uid_files}
    if expected_uids != actual_uids:
        raise RuntimeError(f"generated UID sidecar inventory mismatch: expected={sorted(expected_uids)!r}, actual={sorted(actual_uids)!r}")

    excluded_uid_entries: list[dict[str, object]] = []
    for rel, path in sorted(uid_files):
        excluded_uid_entries.append({
            "path": rel,
            "sha256": sha256_file(path),
            "size_bytes": path.stat().st_size,
            "mode": f"0o{stat.S_IMODE(path.stat().st_mode):o}",
        })
    excluded_cache_bytes = sum(path.stat().st_size for _rel, path in cache_files if path.is_file())
    excluded_cache_names = sorted(rel for rel, _path in cache_files)

    # Check every copied byte against the captured source manifest while streaming it.
    source_by_path = manifest_entry_map(expected_source_entries)
    print(f"Source files verified: {len(expected_paths)}; excluded app/.godot files: {len(cache_files)} ({excluded_cache_bytes} bytes); excluded generated UID sidecars: {len(uid_files)}", flush=True)

    target.mkdir(parents=True, exist_ok=False)
    base_entries: list[dict[str, object]] = []
    for index, rel in enumerate(sorted(expected_paths), start=1):
        expected = source_by_path[rel]
        source = source_candidate.joinpath(*safe_relpath(rel).parts)
        destination = target.joinpath(*safe_relpath(rel).parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        mode = int(str(expected["snapshot_mode"]), 8)
        if expected.get("symlink") is True:
            if not source.is_symlink() or os.readlink(source) != expected.get("symlink_target"):
                raise RuntimeError(f"source symlink mismatch: {rel}")
            if stat.S_IMODE(source.lstat().st_mode) != mode:
                raise RuntimeError(f"source symlink mode mismatch: {rel}")
            os.symlink(str(expected["symlink_target"]), destination)
            base_entries.append({
                "path": rel,
                "kind": "symlink",
                "target": expected["symlink_target"],
                "mode": expected["snapshot_mode"],
            })
        else:
            if stat.S_IMODE(source.stat().st_mode) != mode:
                raise RuntimeError(f"source file mode mismatch: {rel}")
            copy_stream(source, destination, mode, str(expected["snapshot_sha256"]))
            base_entries.append({
                "path": rel,
                "kind": "file",
                "sha256": expected["snapshot_sha256"],
                "size_bytes": expected["snapshot_size_bytes"],
                "mode": expected["snapshot_mode"],
            })
        if index % 2500 == 0:
            print(f"Copied base snapshot {index}/{len(expected_paths)}", flush=True)

    source_manifest_record = manifest_summary(write_manifest(
        evidence_dir / "pre-overlay-base.json", target, base_entries,
        "Verified physical copy of the focused -03 candidate source manifest before any new allowlisted overlays.",
    ))

    applied: list[dict[str, object]] = []
    seen: set[str] = set()
    for item, native_group in overlay_items:
        rel = str(item["path"])
        safe_relpath(rel)
        if rel in seen:
            raise RuntimeError(f"duplicate overlay path: {rel}")
        seen.add(rel)
        expected_sha = str(item["sha256"])
        if native_group is not None:
            native_root = Path(str(native_group["staged_source_root"])).resolve(strict=True)
            source = native_root / Path(rel).name
            mode = stat.S_IMODE(source.stat().st_mode)
        else:
            source = source_root.joinpath(*safe_relpath(rel).parts)
            mode = git_mode(source_root, rel)
        if not source.is_file():
            raise RuntimeError(f"overlay source is missing: {source}")
        actual_sha = sha256_file(source)
        if actual_sha != expected_sha:
            raise RuntimeError(f"overlay source hash mismatch for {rel}: expected {expected_sha}, got {actual_sha}")
        if rel.startswith("app/native/") and stat.S_IMODE(source.stat().st_mode) != mode:
            raise RuntimeError(f"native artifact mode is unstable: {rel}")
        destination = target.joinpath(*safe_relpath(rel).parts)
        before_exists = destination.exists()
        before_sha = sha256_file(destination) if before_exists and destination.is_file() else None
        before_mode = f"0o{stat.S_IMODE(destination.stat().st_mode):o}" if before_exists else None
        copy_stream(source, destination, mode, expected_sha)
        applied.append({
            "path": rel,
            "source_sha256": actual_sha,
            "source_mode": f"0o{mode:o}",
            "before_sha256": before_sha,
            "before_mode": before_mode,
            "added": not before_exists,
        })
        if len(applied) % 10 == 0:
            print(f"Applied approved overlays {len(applied)}/{len(overlay_items)}", flush=True)

    after_entries = walk_entries(target)
    after_map = manifest_entry_map(after_entries)
    before_map = manifest_entry_map(base_entries)
    added = sorted(after_map.keys() - before_map.keys())
    removed = sorted(before_map.keys() - after_map.keys())
    changed = sorted(
        path for path in before_map.keys() & after_map.keys()
        if before_map[path] != after_map[path]
    )
    overlay_paths = {str(item["path"]) for item, _native in overlay_items}
    unexpected_changes = sorted((set(added) | set(changed)) - overlay_paths)
    if removed or unexpected_changes:
        raise RuntimeError(f"unexpected source tree delta: removed={removed[:20]!r}, changed_or_added_not_allowlisted={unexpected_changes[:20]!r}")
    required = {
        "app/physics/aero.gd": "7ac94f6003f2cb7660a56dd94755c6a7d6143d90cc446c6b6c20433038ce38e3",
        "app/test.sh": "dae260326426be613b065b0ae00f040842c310fab217979b537a274b3b36b7d6",
        "app/tests/check_math_sensitivity.py": "d31a14be6489fd820a19e4c3adc84e95310bec735ff57ed68d5b4772fc0b1140",
    }
    for rel, expected_sha in required.items():
        entry = after_map.get(rel)
        if entry is None or entry.get("sha256") != expected_sha:
            raise RuntimeError(f"required base/overlay identity mismatch for {rel}: {entry!r}")

    hardlinks: list[str] = []
    for entry in after_entries:
        if entry.get("kind") == "file":
            path = target.joinpath(*safe_relpath(str(entry["path"])).parts)
            if path.stat().st_nlink != 1:
                hardlinks.append(f"{entry['path']} (nlink={path.stat().st_nlink})")
    if hardlinks:
        raise RuntimeError(f"hard-linked files found in candidate: {hardlinks[:20]!r}")

    after_manifest_record = manifest_summary(write_manifest(
        evidence_dir / "post-overlay-initial.json", target, after_entries,
        "Candidate after exact reviewed overlays; D11g generator/data overlays are included as listed.",
    ))
    receipt = {
        "format": "openrc-r11-candidate-materialization-receipt-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "pwd": os.getcwd(),
        "source_root": str(source_root),
        "source_candidate_root": str(source_candidate),
        "source_candidate_manifest": str(candidate_manifest_path),
        "source_candidate_manifest_sha256": sha256_file(candidate_manifest_path),
        "allowlist": str(allowlist_path),
        "allowlist_sha256": sha256_file(allowlist_path),
        "target_root": str(target),
        "expected_source_file_count": len(expected_paths),
        "pre_overlay_manifest": source_manifest_record,
        "post_overlay_manifest": after_manifest_record,
        "excluded_source_cache": {
            "path": "app/.godot",
            "file_entry_count": len(cache_files),
            "total_bytes": excluded_cache_bytes,
            "relative_paths": excluded_cache_names,
            "reason": "Ignored Godot import/editor cache omitted from the new source candidate; a fresh canonical run must import in the new copy.",
        },
        "excluded_generated_uid_sidecars": excluded_uid_entries,
        "overlay_items_verified_and_applied": applied,
        "overlay_tree_delta": {"added": added, "removed": removed, "changed": changed},
        "hardlinks_verified": 0,
        "pending": allowlist.get("pending_before_candidate_creation", []),
        "note": "Candidate is a physical copy. The immutable -03 source tree and archive were not modified.",
    }
    receipt_path = evidence_dir / "materialization-receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(f"Candidate materialized: {target}", flush=True)
    print(f"Base entries: {len(base_entries)}; overlays: {len(applied)}; added: {len(added)}; changed: {len(changed)}; hardlinks: 0", flush=True)
    print(f"Receipt: {receipt_path}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr, flush=True)
        raise
