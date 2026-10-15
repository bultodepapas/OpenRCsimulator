#!/usr/bin/env python3
"""Capture or audit a Linux test snapshot without altering the Windows source tree."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import tarfile
from datetime import datetime, timezone


GODOT_REL = ".tools/Godot_v4.7.2-stable_linux.x86_64"
GODOT_BINARY_SHA256 = "8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e"
GODOT_BINARY_SHA512 = "ac9f3af3d8b62237694bc03e7422b8f7b1a39095cf4eeaa8361b7465f13bc9dbaad47f60ac0ac217c9f0b2b3712be207039cd83953f4c72087214bd0357cabbc"
GODOT_RELEASE_ZIP_SHA512 = (
    "9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b14"
    "67edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
)


def run_git(root: Path, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", os.fspath(root), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hash_regular_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def hash_file_sha512(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def git_modes(root: Path) -> dict[str, tuple[int, str]]:
    result: dict[str, tuple[int, str]] = {}
    for record in run_git(root, "ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, _object_id, _stage = metadata.split()
        result[os.fsdecode(raw_path)] = (int(mode, 8), "tracked")
    return result


def source_paths(root: Path) -> list[str]:
    raw = run_git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    return sorted(os.fsdecode(item) for item in raw.split(b"\0") if item)


def status_records(root: Path) -> list[str]:
    raw = run_git(root, "status", "--porcelain=v1", "--untracked-files=all", "-z")
    return [os.fsdecode(item) for item in raw.split(b"\0") if item]


def file_record(root: Path, rel: str, indexed_mode: tuple[int, str] | None) -> tuple[dict, bytes | None]:
    path = root / Path(rel)
    if not path.exists() and not path.is_symlink():
        raise FileNotFoundError(f"tracked/nonignored source path missing: {rel}")
    info = path.lstat()
    is_symlink = stat.S_ISLNK(info.st_mode)
    if is_symlink:
        link = os.readlink(path)
        raw_link = os.fsencode(link)
        source_hash, source_size = sha(raw_link), len(raw_link)
    elif stat.S_ISREG(info.st_mode):
        source_hash, source_size = hash_regular_file(path)
        raw_link = None
    else:
        raise RuntimeError(f"unsupported source entry type: {rel}")

    is_shell = rel.lower().endswith(".sh")
    normalized = False
    normalized_bytes: bytes | None = None
    snapshot_size = source_size
    if is_shell and not is_symlink:
        raw = path.read_bytes()
        normalized_bytes = raw.replace(b"\r\n", b"\n")
        normalized = normalized_bytes != raw
        snapshot_size = len(normalized_bytes)
        snapshot_hash = sha(normalized_bytes)
        snapshot_mode = 0o755
    else:
        snapshot_hash = source_hash
        snapshot_mode = indexed_mode[0] & 0o777 if indexed_mode else 0o644

    record = {
        "path": rel.replace("\\", "/"),
        "source_sha256": source_hash,
        "source_size_bytes": source_size,
        "snapshot_sha256": snapshot_hash,
        "snapshot_size_bytes": snapshot_size,
        "source_git_mode": oct(indexed_mode[0]) if indexed_mode else None,
        "source_observed_mode": oct(stat.S_IMODE(info.st_mode)),
        "source_class": indexed_mode[1] if indexed_mode else "untracked_nonignored",
        "snapshot_mode": oct(snapshot_mode),
        "shell_normalized": normalized,
        "symlink": is_symlink,
        "symlink_target": os.fsdecode(raw_link) if is_symlink else None,
    }
    return record, normalized_bytes if is_symlink else None


def capture(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    archive = Path(args.archive).resolve()
    manifest_path = Path(args.manifest).resolve()
    if root == archive or root in archive.parents:
        raise RuntimeError("place the snapshot archive outside the source root")
    if root == manifest_path or root in manifest_path.parents:
        raise RuntimeError("place the capture manifest outside the source root")
    if archive == manifest_path:
        raise RuntimeError("archive and manifest paths must differ")
    if archive.exists() or manifest_path.exists():
        raise FileExistsError("refusing to overwrite an existing archive or manifest")
    godot = root / GODOT_REL
    if not godot.is_file():
        raise FileNotFoundError(f"pinned Linux Godot binary not found: {godot}")
    godot_sha256, godot_size = hash_regular_file(godot)
    godot_sha512 = hash_file_sha512(godot)
    if godot_sha256 != GODOT_BINARY_SHA256 or godot_sha512 != GODOT_BINARY_SHA512:
        raise RuntimeError(
            "pinned Godot executable digest mismatch: "
            f"sha256={godot_sha256} sha512={godot_sha512}"
        )

    modes = git_modes(root)
    records: list[dict] = []
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for rel in source_paths(root):
            record, _unused = file_record(root, rel, modes.get(rel))
            records.append(record)
            source = root / Path(rel)
            info = source.lstat()
            target = PurePosixPath(rel.replace("\\", "/")).as_posix()
            ti = tarfile.TarInfo(target)
            ti.mtime = 0
            ti.uid = 0
            ti.gid = 0
            ti.uname = ""
            ti.gname = ""
            ti.mode = int(record["snapshot_mode"], 8)
            if record["symlink"]:
                ti.type = tarfile.SYMTYPE
                ti.linkname = record["symlink_target"]
                ti.size = 0
                tar.addfile(ti)
            elif rel.lower().endswith(".sh"):
                contents = source.read_bytes().replace(b"\r\n", b"\n")
                ti.size = len(contents)
                tar.addfile(ti, io.BytesIO(contents))
            else:
                ti.size = info.st_size
                with source.open("rb") as stream:
                    tar.addfile(ti, stream)

        ti = tarfile.TarInfo(GODOT_REL)
        ti.size = godot_size
        ti.mode = 0o755
        ti.mtime = 0
        ti.uid = 0
        ti.gid = 0
        ti.uname = ""
        ti.gname = ""
        with godot.open("rb") as stream:
            tar.addfile(ti, stream)

    manifest = {
        "format": "openrc-linux-verification-source-manifest-v1",
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "source_root": os.fspath(root),
        "source_head": os.fsdecode(run_git(root, "rev-parse", "HEAD")).strip(),
        "source_dirty_manifest": status_records(root),
        "source_file_count": len(records),
        "shell_files_normalized": [r["path"] for r in records if r["shell_normalized"]],
        "files": records,
        "pinned_godot": {
            "path": GODOT_REL,
            "sha256": godot_sha256,
            "sha512": godot_sha512,
            "repository_download_zip_sha512": GODOT_RELEASE_ZIP_SHA512,
            "size_bytes": godot_size,
            "snapshot_mode": "0o755",
        },
        "archive": os.fspath(archive),
        "archive_size_bytes": archive.stat().st_size,
        "archive_sha256": hash_regular_file(archive)[0],
        "snapshot_shell_policy": "CRLF converted to LF and *.sh marked executable; all other source bytes preserved",
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"captured {len(records)} source files; normalized {len(manifest['shell_files_normalized'])} shell scripts")
    print(f"source HEAD {manifest['source_head']}; archive {archive} ({archive.stat().st_size} bytes)")
    print(f"manifest {manifest_path}")


def verify_snapshot(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    before_path = Path(args.before).resolve()
    before = json.loads(before_path.read_text(encoding="utf-8"))
    expected_records = {r["path"]: r for r in before["files"]}
    expected_names = set(expected_records)
    actual_names = set(source_paths(root))
    added = sorted(actual_names - expected_names)
    removed = sorted(expected_names - actual_names)
    mismatched: list[str] = []
    for rel in sorted(expected_names & actual_names):
        path = root / Path(rel)
        record = expected_records[rel]
        info = path.lstat()
        if record["symlink"]:
            if not stat.S_ISLNK(info.st_mode):
                mismatched.append(rel)
                continue
            raw = os.fsencode(os.readlink(path))
            digest, size = sha(raw), len(raw)
        else:
            if not stat.S_ISREG(info.st_mode):
                mismatched.append(rel)
                continue
            digest, size = hash_regular_file(path)
            if oct(stat.S_IMODE(info.st_mode)) != record["snapshot_mode"]:
                mismatched.append(rel)
        if digest != record["snapshot_sha256"] or size != record["snapshot_size_bytes"]:
            mismatched.append(rel)

    godot_path = root / GODOT_REL
    godot = before["pinned_godot"]
    if not godot_path.is_file():
        godot_ok = False
        godot_sha256 = None
        godot_sha512 = None
    else:
        godot_sha256, _godot_size = hash_regular_file(godot_path)
        godot_sha512 = hash_file_sha512(godot_path)
        godot_ok = (
            godot_sha256 == godot["sha256"]
            and godot_sha512 == godot["sha512"]
            and godot_sha256 == GODOT_BINARY_SHA256
            and godot_sha512 == GODOT_BINARY_SHA512
            and oct(stat.S_IMODE(godot_path.stat().st_mode)) == godot["snapshot_mode"]
        )

    archive_ok = True
    if args.archive:
        archive_path = Path(args.archive).resolve()
        archive_ok = archive_path.is_file() and hash_regular_file(archive_path)[0] == before["archive_sha256"]

    ok = not added and not removed and not mismatched and godot_ok and archive_ok
    print(
        f"snapshot integrity: {'PASS' if ok else 'FAIL'}; "
        f"added={len(added)} removed={len(removed)} mismatched={len(set(mismatched))}; "
        f"pinned_godot={'PASS' if godot_ok else 'FAIL'} archive={'PASS' if archive_ok else 'FAIL'}"
    )
    if added:
        print("added paths:", ", ".join(added))
    if removed:
        print("removed paths:", ", ".join(removed))
    if mismatched:
        print("mismatched paths:", ", ".join(sorted(set(mismatched))))
    if not godot_ok:
        print(f"pinned Godot sha256={godot_sha256} sha512={godot_sha512}")
    if not archive_ok:
        print("snapshot archive digest does not match the pre-run manifest")
    if not ok:
        raise SystemExit(1)


def audit_after(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    before_path = Path(args.before).resolve()
    out_path = Path(args.out).resolve()
    before = json.loads(before_path.read_text(encoding="utf-8"))
    before_files = {r["path"]: r for r in before["files"]}
    current: list[dict] = []
    modes = git_modes(root)
    for rel in source_paths(root):
        record, _unused = file_record(root, rel, modes.get(rel))
        current.append(record)
    after_files = {r["path"]: r for r in current}
    godot_path = root / GODOT_REL
    godot_sha256 = hash_regular_file(godot_path)[0] if godot_path.is_file() else None
    godot_sha512 = hash_file_sha512(godot_path) if godot_path.is_file() else None
    if godot_sha256 is not None:
        after_files[GODOT_REL] = {
            "source_sha256": godot_sha256,
            "source_observed_mode": oct(stat.S_IMODE(godot_path.stat().st_mode)),
            "symlink": False,
        }
    before_files[GODOT_REL] = {
        "snapshot_sha256": before["pinned_godot"]["sha256"],
        "snapshot_mode": before["pinned_godot"]["snapshot_mode"],
        "symlink": False,
    }
    before_names = set(before_files)
    after_names = set(after_files)
    changed = sorted(
        path
        for path in before_names & after_names
        if before_files[path].get("snapshot_sha256") != after_files[path].get("source_sha256")
        or (
            not before_files[path].get("symlink", False)
            and before_files[path].get("snapshot_mode") != after_files[path].get("source_observed_mode")
        )
    )
    added = sorted(after_names - before_names)
    removed = sorted(before_names - after_names)
    report = {
        "format": "openrc-linux-verification-post-run-manifest-v1",
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "snapshot_root": os.fspath(root),
        "synthetic_snapshot_head": os.fsdecode(run_git(root, "rev-parse", "HEAD")).strip(),
        "post_run_dirty_manifest": status_records(root),
        "post_run_file_count": len(current),
        "pinned_godot": {
            "path": GODOT_REL,
            "sha256": godot_sha256,
            "sha512": godot_sha512,
            "matches_pre_run": (
                godot_sha256 == before["pinned_godot"]["sha256"]
                and godot_sha512 == before["pinned_godot"]["sha512"]
            ),
        },
        "files": current,
        "comparison_to_snapshot": {
            "changed": changed,
            "added": added,
            "removed": removed,
            "unchanged_count": len(before_names & after_names) - len(changed),
        },
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "post-run source comparison: "
        f"{len(report['comparison_to_snapshot']['changed'])} changed, "
        f"{len(added)} added, {len(removed)} removed; manifest {out_path}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)
    cap = sub.add_parser("capture", help="manifest source and create a normalized snapshot tar")
    cap.add_argument("--root", required=True)
    cap.add_argument("--archive", required=True)
    cap.add_argument("--manifest", required=True)
    cap.set_defaults(func=capture)
    post = sub.add_parser("after", help="compare snapshot files after the test run")
    post.add_argument("--root", required=True)
    post.add_argument("--before", required=True)
    post.add_argument("--out", required=True)
    post.set_defaults(func=audit_after)
    check = sub.add_parser("verify", help="verify extracted source and pinned tools before tests")
    check.add_argument("--root", required=True)
    check.add_argument("--before", required=True)
    check.add_argument("--archive")
    check.set_defaults(func=verify_snapshot)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
