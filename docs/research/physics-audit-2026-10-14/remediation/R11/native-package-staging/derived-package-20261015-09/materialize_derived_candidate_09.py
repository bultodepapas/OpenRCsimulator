#!/usr/bin/env python3
"""Build a physical -09 candidate from the frozen -08 manifest plus three reviewed overlays."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess


REPO = Path("/mnt/c/DEVELOPMENT/OpenRCsimulator")
SOURCE = Path("/home/bulto/openrc-r11-package-20261015-08")
TARGET = Path("/home/bulto/openrc-r11-package-20261015-09")
EVIDENCE = REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/derived-package-20261015-09"
BASE_MANIFEST = REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/derived-package-20261015-08/candidate-after-overlays.json"
EXPECTED_BASE_MANIFEST_SHA = "f61830ce291e789a76d43d059a5d6253ffa2d367e8857a9fa322ebc1e2b4f5f4"
EXPECTED_BASE_TREE_SHA = "84fdc89552592750909ab85407b4e7ded9aa18327d8dd22da6e3c7d3d69a51a1"
EXPECTED_BASE_COUNT = 14923

OVERLAYS = [
    {
        "path": "app/native/ground_vehicle/build-receipt.json",
        "source": REPO / "docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/receipt-merge-20261015-02/build-receipt.json",
        "sha256": "8718896783cb792f949732a5a4d74c6d08a1bde0bd52c43f9d1982efb3fd9ff7",
        "mode": "0o644",
    },
    {
        "path": "app/export.sh",
        "source": REPO / "app/export.sh",
        "sha256": "dd7230a202a0ca01f805a6797963c37ece39306d8fbed956f5ed8d733c2a75e4",
        "mode": "0o755",
    },
    {
        "path": "app/tests/check_native_pack.gd",
        "source": REPO / "app/tests/check_native_pack.gd",
        "sha256": "2249f62dfa8a4c8ffdabe78cab853a6247044be329d94c382c612e91f516d3ba",
        "mode": "0o644",
    },
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def safe_path(value: str) -> PurePosixPath:
    relative = PurePosixPath(value)
    if relative.is_absolute() or not relative.parts or any(part in ("", ".", "..") for part in relative.parts):
        raise RuntimeError(f"unsafe relative path: {value!r}")
    return relative


def entry_for(path: Path, relative: str) -> dict[str, object]:
    mode = f"0o{stat.S_IMODE(path.lstat().st_mode):o}"
    if path.is_symlink():
        return {"path": relative, "kind": "symlink", "target": os.readlink(path), "mode": mode}
    if not path.is_file():
        raise RuntimeError(f"manifest path is not a regular file or symlink: {path}")
    return {"path": relative, "kind": "file", "sha256": sha256_file(path), "size_bytes": path.stat().st_size, "mode": mode}


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
    return sorted(entries, key=lambda item: str(item["path"]))


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
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8", newline="\n")
    return value | {"manifest_path": str(path), "manifest_sha256": sha256_file(path)}


def copy_entry(source: Path, destination: Path, expected: dict[str, object]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if expected["kind"] == "symlink":
        os.symlink(os.readlink(source), destination)
        return
    shutil.copyfile(source, destination)
    shutil.copystat(source, destination, follow_symlinks=False)
    actual = entry_for(destination, str(expected["path"]))
    if actual != expected:
        raise RuntimeError(f"physical copy differs from manifest: {expected['path']}")
    if destination.stat().st_nlink != 1:
        raise RuntimeError(f"copied file has a shared inode: {expected['path']}")


def copy_overlay(source: Path, destination: Path, expected_hash: str, mode: str) -> dict[str, object]:
    if sha256_file(source) != expected_hash:
        raise RuntimeError(f"overlay source hash changed: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    os.chmod(destination, int(mode, 8))
    actual_hash = sha256_file(destination)
    if actual_hash != expected_hash or destination.stat().st_nlink != 1:
        raise RuntimeError(f"overlay copy failed hash/inode check: {destination}")
    return {"sha256": actual_hash, "size_bytes": destination.stat().st_size, "mode": mode}


def git_report(root: Path) -> dict[str, object]:
    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, env=env, check=True, capture_output=True, text=True).stdout.strip()
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=root, env=env, check=True, capture_output=True, text=True).stdout.strip()
    status = subprocess.run(["git", "status", "--porcelain=v1", "--untracked-files=all"], cwd=root, env=env, check=True, capture_output=True, text=True).stdout.splitlines()
    status_hash = hashlib.sha256(("\n".join(status) + "\n").encode("utf-8")).hexdigest()
    return {"head": head, "branch": branch, "status_count": len(status), "status_sha256": status_hash, "status": status}


def classify_unmanifested_output(relative: str) -> str | None:
    if relative == ".tools/Godot_v4.7.2-stable_linux.x86_64":
        return "pinned_linux_godot_tool"
    if relative.startswith("app/.godot/"):
        return "godot_import_or_editor_cache"
    if relative.startswith("dist/"):
        return "export_output"
    if relative == "app/native/ground_vehicle/openrc_ground_vehicle.gdextension.uid":
        return "godot_generated_resource_uid_sidecar"
    return None


def verify_manifested_subset(actual_entries: list[dict[str, object]], expected_entries: list[dict[str, object]]) -> list[dict[str, object]]:
    actual_map = {str(item["path"]): item for item in actual_entries}
    if len(actual_map) != len(actual_entries):
        raise RuntimeError("source scan contains duplicate paths")
    expected_map = {str(item["path"]): item for item in expected_entries}
    missing = sorted(set(expected_map) - set(actual_map))
    if missing:
        raise RuntimeError(f"frozen -08 manifest paths are missing from its source tree: {missing[:20]!r}")
    selected = [actual_map[str(item["path"])] for item in expected_entries]
    if selected != expected_entries:
        changed = [str(expected_entries[index]["path"]) for index, (actual, expected) in enumerate(zip(selected, expected_entries)) if actual != expected]
        raise RuntimeError(f"frozen -08 manifested paths differ from its captured identity: {changed[:20]!r}")
    extras = [item for item in actual_entries if str(item["path"]) not in expected_map]
    unclassified = [str(item["path"]) for item in extras if classify_unmanifested_output(str(item["path"])) is None]
    if unclassified:
        raise RuntimeError(f"unmanifested -08 paths are not known generated outputs: {unclassified[:40]!r}")
    return extras


def main() -> None:
    if TARGET.exists():
        raise RuntimeError(f"refusing to overwrite existing candidate: {TARGET}")
    if not EVIDENCE.is_dir():
        raise RuntimeError(f"task-owned evidence directory is missing: {EVIDENCE}")
    existing_outputs = sorted(path.name for path in EVIDENCE.iterdir()
                              if path.name != "materialize_derived_candidate_09.py")
    if existing_outputs:
        raise RuntimeError(f"refusing to overwrite existing evidence: {existing_outputs!r}")
    if sha256_file(BASE_MANIFEST) != EXPECTED_BASE_MANIFEST_SHA:
        raise RuntimeError("frozen -08 source manifest identity changed")
    if not (SOURCE / ".git").is_dir():
        raise RuntimeError("frozen -08 .git support directory is absent")

    source_value = json.loads(BASE_MANIFEST.read_text(encoding="utf-8"))
    source_entries = source_value.get("entries")
    if not isinstance(source_entries, list) or source_value.get("entry_count") != EXPECTED_BASE_COUNT \
            or source_value.get("tree_sha256") != EXPECTED_BASE_TREE_SHA:
        raise RuntimeError("frozen -08 source manifest metadata differs from the authorized identity")
    if source_value.get("root") != str(SOURCE):
        raise RuntimeError(f"frozen -08 manifest root mismatch: {source_value.get('root')!r}")
    source_map = {str(item["path"]): item for item in source_entries}
    if len(source_map) != len(source_entries):
        raise RuntimeError("frozen -08 manifest has duplicate paths")
    forbidden_roots = (".tools", "dist", "tmp")
    for relative in source_map:
        first = PurePosixPath(relative).parts[0]
        if first in forbidden_roots or relative == "app/.godot" or relative.startswith("app/.godot/"):
            raise RuntimeError(f"source manifest unexpectedly includes excluded cache/output: {relative}")
    expected_old_hashes = {
        "app/export.sh": "53469f21c4f897036b571c19c628e8749e5a2282d0462794219aa01a9a5ad369",
        "app/native/ground_vehicle/build-receipt.json": "be1d0b04910c8a98b630b0db6616f650d5c61e8bc60900cf4b4af48a43e306ec",
    }
    for relative, expected_hash in expected_old_hashes.items():
        prior = source_map.get(relative)
        if prior is None or prior.get("sha256") != expected_hash:
            raise RuntimeError(f"frozen -08 baseline does not match the reviewed file: {relative}")
    if "app/tests/check_native_pack.gd" in source_map:
        raise RuntimeError("frozen -08 unexpectedly already includes the new native package probe")

    source_git_report = git_report(SOURCE)
    source_git_before = walk_files(SOURCE / ".git")
    actual_before = walk_files(SOURCE, omit_git=True)
    unmanifested_before = verify_manifested_subset(actual_before, source_entries)
    if canonical_sha256(source_entries) != EXPECTED_BASE_TREE_SHA:
        raise RuntimeError("captured -08 manifest entries do not match the authorized tree identity")
    output_classes: dict[str, int] = {}
    for entry in unmanifested_before:
        category = classify_unmanifested_output(str(entry["path"]))
        assert category is not None
        output_classes[category] = output_classes.get(category, 0) + 1
    output_inventory = {
        "format": "openrc-r11-unmanifested-generated-output-inventory-v1",
        "source_candidate": str(SOURCE),
        "base_manifest_sha256": EXPECTED_BASE_MANIFEST_SHA,
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "classification_counts": dict(sorted(output_classes.items())),
        "entry_count": len(unmanifested_before),
        "tree_sha256": canonical_sha256(unmanifested_before),
        "entries": unmanifested_before,
        "copied_to_candidate": False,
    }
    inventory_path = EVIDENCE / "source-unmanifested-output-inventory.json"
    inventory_path.write_text(json.dumps(output_inventory, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8", newline="\n")
    total_bytes = sum(int(entry.get("size_bytes", 0)) for entry in source_entries)
    print(f"Verified -08 input: {len(source_entries)} manifested files, {total_bytes} bytes, {len(unmanifested_before)} classified generated outputs excluded from copy", flush=True)

    TARGET.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(BASE_MANIFEST, EVIDENCE / "frozen-08-source-manifest.json")
    allowlist = {
        "format": "openrc-r11-derived-package-overlay-allowlist-v1",
        "base_manifest_sha256": EXPECTED_BASE_MANIFEST_SHA,
        "source_candidate": str(SOURCE),
        "target_candidate": str(TARGET),
        "overlays": [
            {"path": item["path"], "source": str(item["source"]), "sha256": item["sha256"], "mode": item["mode"]}
            for item in OVERLAYS
        ],
    }
    allowlist_path = EVIDENCE / "overlay-allowlist.json"
    allowlist_path.write_text(json.dumps(allowlist, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8", newline="\n")

    for index, expected in enumerate(source_entries, start=1):
        relative = str(expected["path"])
        source = SOURCE.joinpath(*safe_path(relative).parts)
        destination = TARGET.joinpath(*safe_path(relative).parts)
        copy_entry(source, destination, expected)
        if index % 1000 == 0:
            print(f"Copied {index}/{len(source_entries)} source entries", flush=True)

    shutil.copytree(SOURCE / ".git", TARGET / ".git", copy_function=shutil.copy2, symlinks=True)
    before_entries = walk_files(TARGET, omit_git=True)
    if before_entries != source_entries or canonical_sha256(before_entries) != EXPECTED_BASE_TREE_SHA:
        raise RuntimeError("physical -09 base copy differs from frozen -08 manifest")
    before_manifest = write_manifest(
        EVIDENCE / "candidate-before-overlays.json", TARGET, before_entries,
        "Physical copy of all -08 manifest entries; .git copied separately; caches and outputs omitted.",
    )

    applied: list[dict[str, object]] = []
    for item in OVERLAYS:
        relative = str(item["path"])
        destination = TARGET.joinpath(*safe_path(relative).parts)
        prior = entry_for(destination, relative) if destination.exists() else None
        copied = copy_overlay(item["source"], destination, str(item["sha256"]), str(item["mode"]))
        applied.append({"path": relative, "before": prior, "after": copied, "source": str(item["source"])})

    after_entries = walk_files(TARGET, omit_git=True)
    after_map = {str(item["path"]): item for item in after_entries}
    added = sorted(set(after_map) - set(source_map))
    removed = sorted(set(source_map) - set(after_map))
    changed = sorted(path for path in set(source_map) & set(after_map) if source_map[path] != after_map[path])
    expected_added = ["app/tests/check_native_pack.gd"]
    expected_changed = ["app/export.sh", "app/native/ground_vehicle/build-receipt.json"]
    if added != expected_added or removed or changed != expected_changed:
        raise RuntimeError(f"-09 delta differs from three-file allowlist: added={added!r}, changed={changed!r}, removed={removed!r}")
    after_manifest = write_manifest(
        EVIDENCE / "candidate-after-overlays.json", TARGET, after_entries,
        "Derived -09 package source after exactly the reviewed receipt, export pipeline and native package smoke overlays.",
    )

    hardlinks: list[str] = []
    for entry in after_entries:
        if entry.get("kind") == "file":
            path = TARGET.joinpath(*safe_path(str(entry["path"])).parts)
            if path.stat().st_nlink != 1:
                hardlinks.append(str(entry["path"]))
    git_entries = walk_files(TARGET / ".git")
    for entry in git_entries:
        if entry.get("kind") == "file":
            path = (TARGET / ".git").joinpath(*safe_path(str(entry["path"])).parts)
            if path.stat().st_nlink != 1:
                hardlinks.append(f".git/{entry['path']}")
    if hardlinks:
        raise RuntimeError(f"hard-linked files found in -09 candidate: {hardlinks[:20]!r}")

    actual_after = walk_files(SOURCE, omit_git=True)
    source_git_after = walk_files(SOURCE / ".git")
    unmanifested_after = verify_manifested_subset(actual_after, source_entries)
    if actual_after != actual_before or unmanifested_after != unmanifested_before or source_git_after != source_git_before or git_report(SOURCE) != source_git_report:
        raise RuntimeError("frozen -08 source changed during -09 materialization")
    target_git_report = git_report(TARGET)
    if target_git_report["head"] != source_git_report["head"]:
        raise RuntimeError("-09 Git HEAD differs from frozen -08")

    receipt = {
        "format": "openrc-r11-derived-package-materialization-v1",
        "captured_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_candidate": str(SOURCE),
        "target_candidate": str(TARGET),
        "base_manifest": {"path": str(BASE_MANIFEST), "sha256": EXPECTED_BASE_MANIFEST_SHA, "tree_sha256": EXPECTED_BASE_TREE_SHA, "entry_count": EXPECTED_BASE_COUNT, "total_bytes": total_bytes},
        "excluded": [".tools", "app/.godot", "dist", "tmp", "unmanifested source generated files"],
        "unmanifested_generated_outputs": {
            "inventory_path": str(inventory_path),
            "inventory_sha256": sha256_file(inventory_path),
            "entry_count": len(unmanifested_before),
            "tree_sha256": canonical_sha256(unmanifested_before),
            "classification_counts": dict(sorted(output_classes.items())),
            "source_outputs_unchanged_after_copy": unmanifested_after == unmanifested_before,
            "copied": False,
        },
        "git_copied_separately": {"head": source_git_report["head"], "branch": source_git_report["branch"], "git_entry_count": len(git_entries), "tree_sha256": canonical_sha256(git_entries), "all_file_nlink_one": True},
        "candidate_before_overlays": before_manifest,
        "candidate_after_overlays": after_manifest,
        "overlay_allowlist": {"path": str(allowlist_path), "sha256": sha256_file(allowlist_path), "applied": applied, "added": added, "changed": changed, "removed": removed},
        "candidate_git_report": target_git_report,
        "hardlinked_files": hardlinks,
        "source_unchanged_after_copy": True,
    }
    receipt_path = EVIDENCE / "materialization-receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({
        "format": receipt["format"],
        "candidate": str(TARGET),
        "entry_count": after_manifest["entry_count"],
        "tree_sha256": after_manifest["tree_sha256"],
        "manifest_sha256": after_manifest["manifest_sha256"],
        "overlay_paths_added": added,
        "overlay_paths_changed": changed,
        "source_unchanged": True,
        "hardlinked_files": len(hardlinks),
        "receipt": str(receipt_path),
    }, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
