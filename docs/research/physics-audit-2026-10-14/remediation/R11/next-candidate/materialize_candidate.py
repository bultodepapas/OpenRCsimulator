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


def walk_entries(
    root: Path,
    *,
    exclude_git_metadata: bool = False,
    exclude_support_tools: bool = False,
) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for directory in sorted(dirs):
            path = current_path / directory
            rel = path.relative_to(root).as_posix()
            if exclude_git_metadata and rel == ".git":
                continue
            if exclude_support_tools and rel == ".tools":
                continue
            if path.is_symlink():
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


def file_inventory_item(rel: str, path: Path) -> dict[str, object]:
    mode = f"0o{stat.S_IMODE(path.lstat().st_mode):o}"
    if path.is_symlink():
        return {"path": rel, "kind": "symlink", "target": os.readlink(path), "mode": mode}
    return {
        "path": rel,
        "kind": "file",
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
        "mode": mode,
    }


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


def git_state(repo: Path) -> dict[str, object]:
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, check=True,
        capture_output=True, text=True,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=repo, check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    staged_diff = subprocess.run(
        ["git", "diff", "--cached", "--quiet"], cwd=repo,
        check=False, capture_output=True, text=True,
    )
    if staged_diff.returncode not in (0, 1):
        raise RuntimeError(f"git diff --cached failed in {repo}: {staged_diff.stderr}")
    return {
        "head": head,
        "status_porcelain_v1_untracked_all": status,
        "status_entry_count": len(status),
        "status_sha256": hashlib.sha256(("\n".join(status) + "\n").encode("utf-8")).hexdigest(),
        "staged_diff_exit": staged_diff.returncode,
    }


def without_git_index(entries: list[dict[str, object]]) -> list[dict[str, object]]:
    return [entry for entry in entries if entry.get("path") != "index"]


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
    source_git = source_candidate / ".git"
    if source_git.is_symlink() or not source_git.is_dir():
        raise RuntimeError(f"expected a physical .git directory in source candidate: {source_git}")
    source_git_before = git_state(source_candidate)
    source_git_entries = walk_entries(source_git)

    support_inputs = allowlist.get("base", {}).get("support_inputs", [])
    if len(support_inputs) != 1 or support_inputs[0].get("path") != ".tools/Godot_v4.7.2-stable_linux.x86_64":
        raise RuntimeError("allowlist must identify exactly the pinned Linux Godot support input")
    support_item = support_inputs[0]
    support_rel = str(support_item["path"])
    support_source = source_candidate.joinpath(*safe_relpath(support_rel).parts)
    if not support_source.is_file() or support_source.is_symlink():
        raise RuntimeError(f"pinned Godot support input is missing or not a regular file: {support_source}")
    support_sha = sha256_file(support_source)
    support_mode = stat.S_IMODE(support_source.stat().st_mode)
    if support_sha != str(support_item["sha256"]):
        raise RuntimeError(f"pinned Godot support-input hash mismatch: expected {support_item['sha256']}, got {support_sha}")
    if support_source.stat().st_size != int(support_item["size_bytes"]) or f"0o{support_mode:o}" != str(support_item["mode"]):
        raise RuntimeError("pinned Godot support-input size/mode mismatch")
    support_version = subprocess.run([str(support_source), "--version"], check=True, capture_output=True, text=True).stdout.strip()
    if support_version != str(support_item["version"]):
        raise RuntimeError(f"pinned Godot version mismatch: expected {support_item['version']}, got {support_version}")

    overlay_items = expected_overlay_files(allowlist)
    preflight_sources: list[dict[str, object]] = []
    preflight_sources.append({
        "path": support_rel,
        "source": str(support_source),
        "sha256": support_sha,
        "size_bytes": support_source.stat().st_size,
        "mode": f"0o{support_mode:o}",
        "version": support_version,
        "role": "Pinned local Linux test/export tool input; copied separately from the repository source manifest.",
    })
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
    actual_paths: set[str] = set()
    cache_files: list[tuple[str, Path]] = []
    python_cache_files: list[tuple[str, Path]] = []
    flight_log_scratch_files: list[tuple[str, Path]] = []
    unexpected: list[str] = []
    for current, dirs, files in os.walk(source_candidate, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for name in sorted(dirs):
            path = current_path / name
            rel = path.relative_to(source_candidate).as_posix()
            if rel == ".git":
                if path.is_symlink() or not path.is_dir():
                    unexpected.append(rel)
            elif rel == "app/.godot" or rel.startswith("app/.godot/"):
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
            if rel.startswith(".git/"):
                continue
            elif rel in expected_paths:
                actual_paths.add(rel)
            elif rel == support_rel:
                continue
            elif rel.startswith("app/.godot/"):
                cache_files.append((rel, path))
            elif "__pycache__" in PurePosixPath(rel).parts and rel.endswith(".pyc"):
                python_cache_files.append((rel, path))
            elif rel.startswith("tmp/flight-log-960337/"):
                flight_log_scratch_files.append((rel, path))
            else:
                unexpected.append(rel)
    if unexpected:
        raise RuntimeError(f"unclassified files in source candidate: {unexpected[:20]!r} ({len(unexpected)} total)")
    missing_paths = sorted(expected_paths - actual_paths)
    if missing_paths:
        raise RuntimeError(f"source candidate is missing manifested paths: {missing_paths[:20]!r} ({len(missing_paths)} total)")
    excluded_cache_bytes = sum(path.stat().st_size for _rel, path in cache_files if path.is_file())
    excluded_cache_names = sorted(rel for rel, _path in cache_files)
    if not python_cache_files:
        raise RuntimeError("expected ignored Python bytecode caches were not found; review the source extras inventory")
    if not flight_log_scratch_files:
        raise RuntimeError("expected identified tmp/flight-log-960337 scratch files were not found")
    python_cache_entries = [file_inventory_item(rel, path) for rel, path in sorted(python_cache_files)]
    flight_log_scratch_entries = [file_inventory_item(rel, path) for rel, path in sorted(flight_log_scratch_files)]
    app_cache_entries = [file_inventory_item(rel, path) for rel, path in sorted(cache_files)]

    # Check every copied byte against the captured source manifest while streaming it.
    source_by_path = manifest_entry_map(expected_source_entries)
    print(f"Source files verified: {len(expected_paths)} (including all 22 manifested untracked UID sidecars); pinned tool input: {support_version}; excluded app/.godot files: {len(cache_files)} ({excluded_cache_bytes} bytes); Python cache files: {len(python_cache_files)}; old flight-log scratch files: {len(flight_log_scratch_files)}", flush=True)

    target.mkdir(parents=True, exist_ok=False)
    shutil.copytree(source_git, target / ".git", symlinks=True, copy_function=shutil.copy2)
    support_destination = target.joinpath(*safe_relpath(support_rel).parts)
    copy_stream(support_source, support_destination, support_mode, support_sha)
    support_entries = walk_entries(source_candidate / ".tools")
    copied_support_entries = walk_entries(target / ".tools")
    if copied_support_entries != support_entries or len(support_entries) != 1:
        raise RuntimeError("copied pinned Godot support tool does not match the source support manifest")
    copied_support_version = subprocess.run([str(support_destination), "--version"], check=True, capture_output=True, text=True).stdout.strip()
    if copied_support_version != support_version:
        raise RuntimeError(f"copied pinned Godot version mismatch: expected {support_version}, got {copied_support_version}")
    copied_git_entries = walk_entries(target / ".git")
    if copied_git_entries != source_git_entries:
        raise RuntimeError("copied .git metadata differs from source metadata manifest")
    target_git_support_only = git_state(target)
    if target_git_support_only["head"] != source_git_before["head"]:
        raise RuntimeError("copied .git HEAD does not match source candidate HEAD")
    write_manifest(
        evidence_dir / "git-metadata-source-before.json", source_git, source_git_entries,
        "Separately hashed synthetic .git support metadata from the source candidate; excluded from the source tree manifest.",
    )
    write_manifest(
        evidence_dir / "pinned-godot-source.json", source_candidate / ".tools", support_entries,
        "Separately hashed pinned Linux Godot support tool from the source candidate; excluded from the source tree manifest.",
    )
    write_manifest(
        evidence_dir / "pinned-godot-copy.json", target / ".tools", copied_support_entries,
        "Separately hashed copy of the pinned Linux Godot support tool retained at the candidate root for app/get-godot.sh.",
    )
    if any(
        (target / ".git").joinpath(*safe_relpath(str(entry["path"])).parts).stat().st_nlink != 1
        for entry in copied_git_entries if entry.get("kind") == "file"
    ):
        raise RuntimeError("hard-linked .git support files found in physical candidate")
    if support_destination.stat().st_nlink != 1:
        raise RuntimeError("hard-linked pinned Godot support tool found in physical candidate")
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
    target_git_before_overlay = git_state(target)
    if target_git_before_overlay["head"] != source_git_before["head"]:
        raise RuntimeError("target candidate HEAD changed during physical source copy")
    if target_git_before_overlay["status_porcelain_v1_untracked_all"] != source_git_before["status_porcelain_v1_untracked_all"]:
        raise RuntimeError("Git working-tree status changed during physical copy before overlays")
    write_manifest(
        evidence_dir / "git-metadata-target-before-overlays.json", target / ".git", walk_entries(target / ".git"),
        "Target synthetic Git metadata immediately after the manifested source copy and before overlays; Git may refresh the index stat cache during status.",
    )

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

    after_entries = walk_entries(target, exclude_git_metadata=True, exclude_support_tools=True)
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
    target_git_after_overlay = git_state(target)
    source_git_after = git_state(source_candidate)
    if source_git_after != source_git_before:
        raise RuntimeError("source candidate Git HEAD/status changed during candidate materialization")
    target_git_after_overlay_entries = walk_entries(target / ".git")
    source_git_after_entries = walk_entries(source_git)
    if without_git_index(target_git_after_overlay_entries) != without_git_index(source_git_entries):
        raise RuntimeError("non-index .git support metadata differs after allowlisted overlays")
    if without_git_index(source_git_after_entries) != without_git_index(source_git_entries):
        raise RuntimeError("source .git support metadata changed outside expected index stat-cache refresh")
    if source_git_before["staged_diff_exit"] != 0 or target_git_after_overlay["staged_diff_exit"] != 0:
        raise RuntimeError("source or target Git index has staged changes; expected clean staged diff")
    write_manifest(
        evidence_dir / "git-metadata-source-after.json", source_git, source_git_after_entries,
        "Source candidate synthetic Git metadata after final status capture; a Git status index stat-cache refresh is recorded separately.",
    )
    write_manifest(
        evidence_dir / "git-metadata-target-after.json", target / ".git", target_git_after_overlay_entries,
        "Separately hashed .git support metadata retained in the final physical candidate after source overlays.",
    )
    receipt = {
        "format": "openrc-r11-candidate-materialization-receipt-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "pwd": os.getcwd(),
        "source_root": str(source_root),
        "source_candidate_root": str(source_candidate),
        "source_candidate_manifest": str(candidate_manifest_path),
        "source_candidate_manifest_sha256": sha256_file(candidate_manifest_path),
        "source_git_state_before_and_after": {
            "before": source_git_before,
            "after": source_git_after,
        },
        "target_git_state_before_overlays": target_git_before_overlay,
        "target_git_state_reconciliation": {
            "source_status_exactly_matches_target_before_overlays": True,
            "manifested_untracked_uid_paths": sorted(
                line[3:] for line in source_git_before["status_porcelain_v1_untracked_all"]
                if line.startswith("?? ") and line.endswith(".uid")
            ),
        },
        "target_git_state_after_overlays": target_git_after_overlay,
        "git_metadata_support": {
            "included_in_candidate": True,
            "separate_from_source_manifest": True,
            "source_tree_sha256_before": canonical_json_sha256(source_git_entries),
            "source_tree_sha256_after": canonical_json_sha256(source_git_after_entries),
            "target_tree_sha256_after": canonical_json_sha256(target_git_after_overlay_entries),
            "only_git_index_stat_cache_may_change_after_status": True,
            "non_index_metadata_equal_to_source": True,
            "source_index_before_sha256": next(entry["sha256"] for entry in source_git_entries if entry.get("path") == "index"),
            "source_index_after_sha256": next(entry["sha256"] for entry in source_git_after_entries if entry.get("path") == "index"),
            "target_index_after_sha256": next(entry["sha256"] for entry in target_git_after_overlay_entries if entry.get("path") == "index"),
            "staged_diff_exit_source_and_target": [source_git_after["staged_diff_exit"], target_git_after_overlay["staged_diff_exit"]],
            "entry_count": len(source_git_entries),
            "source_before_manifest": str(evidence_dir / "git-metadata-source-before.json"),
            "target_before_overlays_manifest": str(evidence_dir / "git-metadata-target-before-overlays.json"),
            "source_after_manifest": str(evidence_dir / "git-metadata-source-after.json"),
            "target_after_manifest": str(evidence_dir / "git-metadata-target-after.json"),
            "hardlinks_verified": 0,
        },
        "pinned_godot_support_input": {
            "path": support_rel,
            "source_sha256": support_sha,
            "candidate_sha256": sha256_file(support_destination),
            "size_bytes": support_destination.stat().st_size,
            "mode": f"0o{stat.S_IMODE(support_destination.stat().st_mode):o}",
            "version": support_version,
            "source_manifest": str(evidence_dir / "pinned-godot-source.json"),
            "candidate_manifest": str(evidence_dir / "pinned-godot-copy.json"),
            "hardlinks_verified": 0,
        },
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
            "entries": app_cache_entries,
        },
        "excluded_python_bytecode_cache": {
            "entry_count": len(python_cache_entries),
            "total_bytes": sum(int(entry.get("size_bytes", 0)) for entry in python_cache_entries),
            "entries": python_cache_entries,
            "reason": "Python __pycache__ bytecode is generated interpreter cache and is not an input to the source snapshot.",
        },
        "excluded_prior_flight_log_scratch": {
            "entry_count": len(flight_log_scratch_entries),
            "total_bytes": sum(int(entry.get("size_bytes", 0)) for entry in flight_log_scratch_entries),
            "entries": flight_log_scratch_entries,
            "reason": "Identified prior tmp/flight-log-960337 output artifacts are exploratory recorder scratch, not test inputs; exact files are retained by hash here and omitted from the fresh candidate.",
        },
        "overlay_items_verified_and_applied": applied,
        "overlay_tree_delta": {"added": added, "removed": removed, "changed": changed},
        "hardlinks_verified": 0,
        "pending": allowlist.get("pending_before_candidate_creation", []),
        "note": "Candidate is a physical copy. Synthetic .git support metadata is preserved separately from the app/source manifest so build identity resolves inside this copy. No commit, reset, or staging was performed. The immutable -03 source tree and archive were not modified.",
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
