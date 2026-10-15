#!/usr/bin/env python3
"""Materialize the reviewed frozen-07 file manifest and its two package overlays."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys


REPO = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator")
SOURCE = Path("/home/bulto/openrc-r11-b09-r05b-20261015-07")
TARGET = Path("/home/bulto/openrc-r11-package-20261015-08")
EVIDENCE = REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/derived-package-20261015-08"
SOURCE_MANIFEST = REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-07-01/post-overlay-initial.json"
OVERLAY_SPEC = EVIDENCE / "overlay-allowlist.json"
DLL_SOURCE = REPO / "tmp/physics-audit-r11-native-package-staging-20261015-01/bin/openrc_ground_vehicle.dll"
CHECKER_SOURCE = REPO / "app/tests/check_trimmed_flight.py"

EXPECTED_SOURCE_MANIFEST_SHA = "7f7d14b202a18d270dbb1cc8c04aaad6471318a0f0a3a9f9b75e21a4cce804f6"
EXPECTED_SOURCE_TREE_SHA = "b9108ec7cfa993a396a218fd809f9d58bee6e9e54d299424a6a42599f6f77e5c"
EXPECTED_DLL_SHA = "adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c"
EXPECTED_CHECKER_SHA = "bcaa40377bda39fc8e8e7a2be6753fc41441bf2901b0ca60d8c5feb11c203d81"
EXPECTED_COUNT = 14922


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def safe_path(value: str) -> PurePosixPath:
    rel = PurePosixPath(value)
    if rel.is_absolute() or not rel.parts or any(part in ("", ".", "..") for part in rel.parts):
        raise RuntimeError(f"unsafe relative path: {value!r}")
    return rel


def entry_for(path: Path, relative: str) -> dict[str, object]:
    mode = f"0o{stat.S_IMODE(path.lstat().st_mode):o}"
    if path.is_symlink():
        return {"path": relative, "kind": "symlink", "target": os.readlink(path), "mode": mode}
    if not path.is_file():
        raise RuntimeError(f"manifest path is not a file or symlink: {path}")
    return {
        "path": relative,
        "kind": "file",
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
        "mode": mode,
    }


def walk_files(root: Path, *, omit_git: bool = False) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for name in sorted(dirs):
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            if omit_git and relative == ".git":
                continue
            if path.is_symlink():
                entries.append(entry_for(path, relative))
            else:
                kept_dirs.append(name)
        dirs[:] = kept_dirs
        for name in sorted(files):
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            if omit_git and relative.startswith(".git/"):
                continue
            entries.append(entry_for(path, relative))
    entries.sort(key=lambda item: str(item["path"]))
    return entries


def write_manifest(path: Path, root: Path, entries: list[dict[str, object]], purpose: str) -> dict[str, object]:
    value = {
        "format": "openrc-r11-derived-package-tree-manifest-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "purpose": purpose,
        "root": str(root),
        "entry_count": len(entries),
        "tree_sha256": canonical_sha256(entries),
        "entries": entries,
    }
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    value["manifest_path"] = str(path)
    value["manifest_sha256"] = sha256_file(path)
    return value


def git_identity(root: Path) -> dict[str, object]:
    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, env=env, check=True, capture_output=True, text=True).stdout.strip()
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=root, env=env, check=True, capture_output=True, text=True).stdout.strip()
    return {"head": head, "branch": branch}


def git_report(root: Path) -> dict[str, object]:
    identity = git_identity(root)
    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    status = subprocess.run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=root, env=env, check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    return identity | {
        "status_porcelain_v1_untracked_all": status,
        "status_entry_count": len(status),
        "status_sha256": hashlib.sha256(("\n".join(status) + "\n").encode("utf-8")).hexdigest(),
    }


def manifest_map(entries: list[dict[str, object]]) -> dict[str, dict[str, object]]:
    return {str(entry["path"]): entry for entry in entries}


def require_hash(path: Path, expected: str, label: str) -> str:
    if not path.is_file() or path.is_symlink():
        raise RuntimeError(f"{label} is not a regular file: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise RuntimeError(f"{label} SHA-256 mismatch: expected {expected}, got {actual}")
    return actual


def copy_physical(source: Path, destination: Path, expected_sha: str, mode: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    os.chmod(destination, mode)
    actual_sha = sha256_file(destination)
    if actual_sha != expected_sha:
        raise RuntimeError(f"copied bytes mismatch at {destination}: expected {expected_sha}, got {actual_sha}")
    if destination.stat().st_nlink != 1:
        raise RuntimeError(f"hard-linked output detected: {destination} (nlink={destination.stat().st_nlink})")


def git_entries(root: Path) -> list[dict[str, object]]:
    return walk_files(root)


def main() -> int:
    for path, label in ((SOURCE, "frozen source"), (SOURCE_MANIFEST, "frozen source manifest"),
                        (OVERLAY_SPEC, "overlay allowlist"), (DLL_SOURCE, "staged DLL"),
                        (CHECKER_SOURCE, "live trim checker")):
        if not path.exists():
            raise RuntimeError(f"missing {label}: {path}")
    if SOURCE.resolve() != Path("/home/bulto/openrc-r11-b09-r05b-20261015-07"):
        raise RuntimeError("unexpected frozen source path")
    if TARGET.exists():
        raise RuntimeError(f"refusing to overwrite existing target: {TARGET}")
    if not EVIDENCE.is_dir():
        raise RuntimeError(f"evidence directory was not pre-created: {EVIDENCE}")
    forbidden = (".git/", ".tools/", "app/.godot/", "dist/", "tmp/")

    manifest_sha = sha256_file(SOURCE_MANIFEST)
    if manifest_sha != EXPECTED_SOURCE_MANIFEST_SHA:
        raise RuntimeError(f"frozen manifest hash mismatch: expected {EXPECTED_SOURCE_MANIFEST_SHA}, got {manifest_sha}")
    source_manifest = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    if source_manifest.get("root") != str(SOURCE):
        raise RuntimeError(f"manifest root mismatch: {source_manifest.get('root')!r}")
    source_entries = source_manifest.get("entries")
    if not isinstance(source_entries, list) or len(source_entries) != EXPECTED_COUNT:
        raise RuntimeError("frozen source entry count mismatch")
    if source_manifest.get("tree_sha256") != EXPECTED_SOURCE_TREE_SHA or canonical_sha256(source_entries) != EXPECTED_SOURCE_TREE_SHA:
        raise RuntimeError("frozen source tree identity mismatch")
    source_map = manifest_map(source_entries)
    if len(source_map) != len(source_entries):
        raise RuntimeError("duplicate paths in frozen source manifest")
    for relative, expected in source_map.items():
        safe_path(relative)
        if any(relative == prefix.rstrip("/") or relative.startswith(prefix) for prefix in forbidden):
            raise RuntimeError(f"mutable cache/output or support path is in the frozen source manifest: {relative}")
        if expected.get("kind") != "file":
            raise RuntimeError(f"unexpected non-file in frozen source manifest: {relative}")

    checker_rel = "app/tests/check_trimmed_flight.py"
    dll_rel = "app/native/ground_vehicle/openrc_ground_vehicle.dll"
    old_checker = source_map.get(checker_rel)
    if old_checker is None or old_checker.get("sha256") != "55c6d0f6a9ddf088c60de1050b964250f0af39ea36d1268574319273d9a69295":
        raise RuntimeError("frozen checker does not match the reviewed baseline hash")
    if dll_rel in source_map:
        raise RuntimeError("frozen manifest unexpectedly already contains the Windows DLL")
    if require_hash(DLL_SOURCE, EXPECTED_DLL_SHA, "historical staged Windows DLL") != EXPECTED_DLL_SHA:
        raise RuntimeError("unreachable DLL hash check")
    if require_hash(CHECKER_SOURCE, EXPECTED_CHECKER_SHA, "updated live trim checker") != EXPECTED_CHECKER_SHA:
        raise RuntimeError("unreachable checker hash check")

    spec = json.loads(OVERLAY_SPEC.read_text(encoding="utf-8"))
    if spec.get("base", {}).get("manifest_sha256") != EXPECTED_SOURCE_MANIFEST_SHA:
        raise RuntimeError("overlay allowlist identifies a different frozen manifest")
    expected_overlays = [
        {"path": dll_rel, "source": str(DLL_SOURCE), "sha256": EXPECTED_DLL_SHA, "mode": "0o644"},
        {"path": checker_rel, "source": str(CHECKER_SOURCE), "sha256": EXPECTED_CHECKER_SHA, "mode": str(old_checker["mode"])},
    ]
    observed_overlays = [
        {key: item.get(key) for key in ("path", "source", "sha256", "mode")}
        for item in spec.get("overlays", [])
    ]
    if observed_overlays != expected_overlays:
        raise RuntimeError("overlay allowlist does not match the two approved files")

    source_git = SOURCE / ".git"
    if source_git.is_symlink() or not source_git.is_dir():
        raise RuntimeError("frozen source .git metadata is not a physical directory")
    source_git_before = git_entries(source_git)
    source_git_tree_sha = canonical_sha256(source_git_before)
    # Do not run `git status` against frozen-07: it can refresh Git's index. The
    # frozen source identity is its read-only HEAD/branch plus the raw .git manifest.
    source_git_report = git_identity(SOURCE)

    # Rehash the entire manifested source before copying. This reads frozen-07 only.
    print(f"Preflight hashing {len(source_entries)} frozen files before physical copy", flush=True)
    for index, expected in enumerate(source_entries, start=1):
        relative = str(expected["path"])
        source = SOURCE.joinpath(*safe_path(relative).parts)
        if source.is_symlink() or not source.is_file():
            raise RuntimeError(f"frozen path is not a regular file: {relative}")
        actual = entry_for(source, relative)
        if actual != expected:
            raise RuntimeError(f"frozen file no longer matches captured manifest: {relative}")
        if index % 2500 == 0:
            print(f"Preflight verified {index}/{len(source_entries)} files", flush=True)

    TARGET.mkdir(parents=True, exist_ok=False)
    shutil.copytree(source_git, TARGET / ".git", symlinks=True, copy_function=shutil.copy2)
    copied_git_entries = git_entries(TARGET / ".git")
    if copied_git_entries != source_git_before:
        raise RuntimeError("separate physical .git copy differs from frozen source .git")

    print(f"Physically copying {len(source_entries)} files ({sum(int(e['size_bytes']) for e in source_entries)} bytes)", flush=True)
    copied_entries: list[dict[str, object]] = []
    total_bytes = 0
    for index, expected in enumerate(source_entries, start=1):
        relative = str(expected["path"])
        source = SOURCE.joinpath(*safe_path(relative).parts)
        destination = TARGET.joinpath(*safe_path(relative).parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        mode = int(str(expected["mode"]), 8)
        os.chmod(destination, mode)
        actual = entry_for(destination, relative)
        if actual != expected:
            raise RuntimeError(f"copied file differs from frozen manifest: {relative}")
        if destination.stat().st_nlink != 1:
            raise RuntimeError(f"source file was not physically copied: {relative} (nlink={destination.stat().st_nlink})")
        copied_entries.append(actual)
        total_bytes += int(expected["size_bytes"])
        if index % 1000 == 0:
            print(f"Copied {index}/{len(source_entries)} files ({total_bytes} bytes)", flush=True)

    before_manifest = write_manifest(
        EVIDENCE / "candidate-before-overlays.json", TARGET, copied_entries,
        "Physical copy of every file in frozen-07 post-overlay-initial.json; .git copied separately; .tools, caches and outputs omitted.",
    )
    if before_manifest["tree_sha256"] != EXPECTED_SOURCE_TREE_SHA or before_manifest["entry_count"] != EXPECTED_COUNT:
        raise RuntimeError("new candidate pre-overlay manifest differs from frozen-07 tree")
    shutil.copyfile(SOURCE_MANIFEST, EVIDENCE / "frozen-07-source-manifest.json")
    if sha256_file(EVIDENCE / "frozen-07-source-manifest.json") != EXPECTED_SOURCE_MANIFEST_SHA:
        raise RuntimeError("retained frozen source manifest copy changed")

    applied: list[dict[str, object]] = []
    for item in spec["overlays"]:
        relative = str(item["path"])
        destination = TARGET.joinpath(*safe_path(relative).parts)
        existed = destination.exists()
        before_sha = sha256_file(destination) if existed else None
        before_mode = f"0o{stat.S_IMODE(destination.stat().st_mode):o}" if existed else None
        mode = int(str(item["mode"]), 8)
        copy_physical(Path(str(item["source"])), destination, str(item["sha256"]), mode)
        applied.append({
            "path": relative,
            "source": str(item["source"]),
            "source_sha256": str(item["sha256"]),
            "mode_after": str(item["mode"]),
            "before_sha256": before_sha,
            "before_mode": before_mode,
            "added": not existed,
        })

    after_entries = walk_files(TARGET, omit_git=True)
    after_map = manifest_map(after_entries)
    source_paths = set(source_map)
    after_paths = set(after_map)
    added = sorted(after_paths - source_paths)
    removed = sorted(source_paths - after_paths)
    changed = sorted(path for path in source_paths & after_paths if source_map[path] != after_map[path])
    if added != [dll_rel] or removed or changed != [checker_rel]:
        raise RuntimeError(f"candidate tree delta exceeds allowlist: added={added!r}, removed={removed!r}, changed={changed!r}")
    after_manifest = write_manifest(
        EVIDENCE / "candidate-after-overlays.json", TARGET, after_entries,
        "Derived package candidate after exactly the historical Windows DLL and updated trim-checker overlays.",
    )

    # Every regular file in both the copied source tree and copied Git support tree must have a unique inode.
    hardlinks: list[str] = []
    for entry in after_entries:
        if entry.get("kind") == "file":
            path = TARGET.joinpath(*safe_path(str(entry["path"])).parts)
            if path.stat().st_nlink != 1:
                hardlinks.append(str(entry["path"]))
    for entry in copied_git_entries:
        if entry.get("kind") == "file":
            path = (TARGET / ".git").joinpath(*safe_path(str(entry["path"])).parts)
            if path.stat().st_nlink != 1:
                hardlinks.append(f".git/{entry['path']}")
    if hardlinks:
        raise RuntimeError(f"hard-linked files found in derived candidate: {hardlinks[:20]!r}")

    source_git_after = git_entries(source_git)
    if source_git_after != source_git_before:
        raise RuntimeError("frozen-07 .git metadata changed during materialization")
    target_git_report = git_report(TARGET)
    if target_git_report["head"] != source_git_report["head"]:
        raise RuntimeError("candidate Git HEAD differs from frozen-07")
    target_git_after = git_entries(TARGET / ".git")

    receipt = {
        "format": "openrc-r11-derived-package-materialization-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_candidate": str(SOURCE),
        "source_manifest": {
            "path": str(SOURCE_MANIFEST),
            "sha256": EXPECTED_SOURCE_MANIFEST_SHA,
            "entry_count": EXPECTED_COUNT,
            "tree_sha256": EXPECTED_SOURCE_TREE_SHA,
            "total_bytes": sum(int(entry["size_bytes"]) for entry in source_entries),
            "retained_copy": str(EVIDENCE / "frozen-07-source-manifest.json"),
        },
        "excluded_support_cache_output": [".git (copied separately)", ".tools (not copied)", "app/.godot (not copied)", "dist (not copied)", "tmp (not copied)"],
        "candidate": str(TARGET),
        "candidate_before_overlays": before_manifest,
        "candidate_after_overlays": after_manifest,
        "overlay_allowlist": {
            "path": str(OVERLAY_SPEC),
            "sha256": sha256_file(OVERLAY_SPEC),
            "only_changes": applied,
            "added_paths": added,
            "changed_paths": changed,
            "removed_paths": removed,
        },
        "git_identity": {
            "source": source_git_report,
            "candidate_after_overlays": target_git_report,
            "source_git_entries_sha256_before": source_git_tree_sha,
            "source_git_entries_sha256_after": canonical_sha256(source_git_after),
            "candidate_git_entries_sha256_after": canonical_sha256(target_git_after),
            "source_git_unchanged": source_git_after == source_git_before,
            "candidate_head_matches_source": target_git_report["head"] == source_git_report["head"],
        },
        "native_provenance": json.loads((EVIDENCE.parent / "manifest.json").read_text(encoding="utf-8")),
        "physical_copy": {
            "source_files": len(source_entries),
            "source_bytes": sum(int(entry["size_bytes"]) for entry in source_entries),
            "candidate_source_files_before_overlays": len(copied_entries),
            "candidate_source_files_after_overlays": len(after_entries),
            "hardlinks_detected": 0,
            "files_using_manifested_digest_and_mode": True,
        },
        "export_performed": False,
    }
    receipt_path = EVIDENCE / "materialization-receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({
        "candidate": str(TARGET),
        "before_tree_sha256": before_manifest["tree_sha256"],
        "after_tree_sha256": after_manifest["tree_sha256"],
        "added": added,
        "changed": changed,
        "git_head": target_git_report["head"],
        "hardlinks_detected": 0,
        "receipt": str(receipt_path),
    }, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr, flush=True)
        raise
