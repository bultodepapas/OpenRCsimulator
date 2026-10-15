#!/usr/bin/env python3
"""Build a reproducible Linux test archive from one Git commit plus named overlays."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import tarfile
from datetime import datetime, timezone


GODOT_REL = ".tools/Godot_v4.7.2-stable_linux.x86_64"
GODOT_SHA256 = "8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e"
GODOT_SHA512 = "ac9f3af3d8b62237694bc03e7422b8f7b1a39095cf4eeaa8361b7465f13bc9dbaad47f60ac0ac217c9f0b2b3712be207039cd83953f4c72087214bd0357cabbc"


def git(root: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    return subprocess.run(
        ["git", "-C", os.fspath(root), *args],
        input=input_bytes,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout


def sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def sha512_file(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def git_blob_sha1(path: Path, symlink: bool = False) -> str:
    if symlink:
        payload = os.fsencode(os.readlink(path))
        digest = hashlib.sha1(f"blob {len(payload)}\0".encode("ascii"))
        digest.update(payload)
        return digest.hexdigest()
    size = path.stat().st_size
    digest = hashlib.sha1(f"blob {size}\0".encode("ascii"))
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def git_attributes(root: Path, paths: list[str]) -> dict[str, dict[str, str]]:
    """Read the checkout attributes that git archive applies to each path."""
    payload = b"\0".join(os.fsencode(path) for path in paths) + b"\0"
    raw = git(root, "check-attr", "-z", "--all", "--stdin", input_bytes=payload)
    fields = raw.split(b"\0")
    if fields[-1] == b"":
        fields.pop()
    if len(fields) % 3:
        raise RuntimeError("unexpected NUL-delimited git check-attr output")
    result: dict[str, dict[str, str]] = {path: {} for path in paths}
    for index in range(0, len(fields), 3):
        path, name, value = (os.fsdecode(item) for item in fields[index:index + 3])
        result.setdefault(path, {})[name] = value
    return result


def clean_chunks(path: Path, normalize_eol: bool):
    with path.open("rb") as stream:
        if not normalize_eol:
            while block := stream.read(1024 * 1024):
                yield block
            return
        pending = b""
        while block := stream.read(1024 * 1024):
            data = pending + block
            pending = b"\r" if data.endswith(b"\r") else b""
            if pending:
                data = data[:-1]
            if data:
                yield data.replace(b"\r\n", b"\n")
        if pending:
            yield pending


def normalized_blob_oid(path: Path, attributes: dict[str, str]) -> str:
    text = attributes.get("text", "unspecified")
    eol = attributes.get("eol", "unspecified")
    unsupported = {
        key: value for key, value in attributes.items()
        if key in ("filter", "ident", "working-tree-encoding") and value not in ("unspecified", "unset")
    }
    if unsupported:
        raise RuntimeError(f"cannot clean-normalize attributes for {path}: {unsupported}")
    if text == "unset":
        normalize_eol = False
    elif text in ("set", "auto") or eol in ("lf", "crlf"):
        normalize_eol = True
    elif text in ("unspecified", "unset") and eol == "unspecified":
        normalize_eol = False
    else:
        raise RuntimeError(f"unsupported text/eol attributes for {path}: text={text} eol={eol}")
    if text == "auto" and normalize_eol:
        with path.open("rb") as stream:
            has_nul = b"\0" in stream.read(8192)
        if has_nul:
            normalize_eol = False
    size = 0
    for block in clean_chunks(path, normalize_eol):
        size += len(block)
    # Git blob hashes include the canonicalized byte count in their header.
    clean_hash = hashlib.sha1()
    clean_hash.update(f"blob {size}\0".encode("ascii"))
    for block in clean_chunks(path, normalize_eol):
        clean_hash.update(block)
    return clean_hash.hexdigest()


def materialize_git_archive(root: Path, revision: str, stage: Path, entries: dict[str, dict]) -> list[dict]:
    """Extract a fixed commit with Git's checkout attributes, then verify clean object IDs."""
    if ".gitattributes" in entries:
        attr_path = root / ".gitattributes"
        if not attr_path.is_file() or git_blob_sha1(attr_path) != entries[".gitattributes"]["blob_oid"]:
            raise RuntimeError("live .gitattributes differs from the fixed commit; cannot verify archive checkout attributes")
    source = subprocess.Popen(
        ["git", "-C", os.fspath(root), "archive", "--format=tar", revision],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert source.stdout is not None
    extractor = subprocess.Popen(
        ["tar", "-xf", "-", "-C", os.fspath(stage), "--no-same-owner"],
        stdin=source.stdout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    source.stdout.close()
    _, extract_error = extractor.communicate()
    archive_error = source.stderr.read() if source.stderr else b""
    source_return = source.wait()
    if source_return or extractor.returncode:
        raise RuntimeError(
            f"git archive/tar extraction failed: git={source_return} tar={extractor.returncode}; "
            f"git={os.fsdecode(archive_error)} tar={os.fsdecode(extract_error)}"
        )
    actual_paths = {
        path.relative_to(stage).as_posix()
        for path in stage.rglob("*")
        if path.is_file() or path.is_symlink()
    }
    expected_paths = set(entries)
    if actual_paths != expected_paths:
        missing = sorted(expected_paths - actual_paths)[:10]
        extra = sorted(actual_paths - expected_paths)[:10]
        raise RuntimeError(f"Git archive path set differs from commit tree: missing={missing}, extra={extra}")
    attrs = git_attributes(root, sorted(entries))
    checks: list[dict] = []
    for rel, entry in sorted(entries.items()):
        path = stage / Path(rel)
        info = path.lstat()
        expected_mode = entry["git_mode"]
        if expected_mode == 0o120000:
            if not stat.S_ISLNK(info.st_mode):
                raise RuntimeError(f"git archive mode mismatch (expected symlink): {rel}")
            clean_oid = git_blob_sha1(path, symlink=True)
            archive_sha256 = hashlib.sha256(os.fsencode(os.readlink(path))).hexdigest()
            archive_size = len(os.fsencode(os.readlink(path)))
        elif expected_mode in (0o100644, 0o100755):
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != (expected_mode & 0o777):
                raise RuntimeError(f"git archive mode mismatch: {rel} got={oct(stat.S_IMODE(info.st_mode))}")
            clean_oid = normalized_blob_oid(path, attrs.get(rel, {}))
            archive_sha256, archive_size = sha256_file(path)
        else:
            raise RuntimeError(f"unsupported Git mode {oct(expected_mode)}: {rel}")
        if clean_oid != entry["blob_oid"]:
            raise RuntimeError(
                f"Git archive clean-normalization failed for {rel}: expected={entry['blob_oid']} actual={clean_oid} "
                f"attributes={attrs.get(rel, {})}"
            )
        checks.append({
            "path": rel,
            "git_blob_oid": entry["blob_oid"],
            "checkout_sha256": archive_sha256,
            "checkout_size_bytes": archive_size,
            "git_mode": oct(expected_mode),
            "checkout_attributes": attrs.get(rel, {}),
            "clean_normalization_verified": True,
        })
    return checks


def tree_entries(root: Path, revision: str) -> dict[str, dict]:
    raw = git(root, "ls-tree", "-r", "-z", "--full-tree", revision)
    result: dict[str, dict] = {}
    for record in raw.split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, kind, oid = metadata.split()
        rel = os.fsdecode(raw_path).replace("\\", "/")
        if kind != b"blob":
            raise RuntimeError(f"unsupported non-blob tree entry {kind!r}: {rel}")
        result[rel] = {"git_mode": int(mode, 8), "blob_oid": oid.decode("ascii")}
    return result


def worktree_delta(root: Path, revision: str) -> tuple[list[dict], dict]:
    base = tree_entries(root, revision)
    raw_diff = git(root, "diff", "--no-renames", "--name-status", "-z", revision, "--")
    fields = raw_diff.split(b"\0")
    diff_status: dict[str, str] = {}
    cursor = 0
    while cursor + 1 < len(fields):
        status = os.fsdecode(fields[cursor])
        rel = os.fsdecode(fields[cursor + 1]).replace("\\", "/")
        if not status:
            break
        diff_status[rel] = status
        cursor += 2
    untracked = [
        os.fsdecode(item).replace("\\", "/")
        for item in git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
        if item
    ]
    paths = sorted(set(diff_status) | set(untracked))
    delta: list[dict] = []
    for rel in paths:
        item: dict = {
            "path": rel,
            "status_vs_revision": diff_status.get(rel, "untracked_nonignored"),
            "base_blob_oid": base.get(rel, {}).get("blob_oid"),
            "base_git_mode": oct(base[rel]["git_mode"]) if rel in base else None,
        }
        path = root / Path(rel)
        if path.exists() or path.is_symlink():
            info = path.lstat()
            is_symlink = stat.S_ISLNK(info.st_mode)
            if is_symlink:
                payload = os.fsencode(os.readlink(path))
                digest = hashlib.sha256(payload).hexdigest()
                size = len(payload)
                blob_oid = git_blob_sha1(path, symlink=True)
            elif stat.S_ISREG(info.st_mode):
                digest, size = sha256_file(path)
                blob_oid = git_blob_sha1(path)
            else:
                raise RuntimeError(f"unsupported live delta entry type: {rel}")
            item.update({
                "working_sha256": digest,
                "working_size_bytes": size,
                "working_blob_oid": blob_oid,
                "working_mode": oct(stat.S_IMODE(info.st_mode)),
                "symlink": is_symlink,
                "symlink_target": os.fsdecode(os.readlink(path)) if is_symlink else None,
            })
        else:
            item.update({"working_sha256": None, "working_size_bytes": None, "working_blob_oid": None, "working_mode": None, "symlink": False})
        delta.append(item)
    metadata = {
        "revision": revision,
        "current_head": os.fsdecode(git(root, "rev-parse", "HEAD")).strip(),
        "porcelain_status": [x for x in os.fsdecode(git(root, "status", "--porcelain=v1", "--untracked-files=all", "-z")).split("\0") if x],
        "diff_path_count": len(diff_status),
        "untracked_nonignored_count": len(untracked),
        "ignored_paths": "not enumerated; the fixed-commit archive defines the test source scope",
    }
    return delta, metadata


def normalize_shells(stage: Path) -> list[str]:
    changed: list[str] = []
    for path in sorted(stage.rglob("*.sh")):
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        normalized = data.replace(b"\r\n", b"\n")
        if normalized != data:
            path.write_bytes(normalized)
            changed.append(path.relative_to(stage).as_posix())
        path.chmod(0o755)
    return changed


def snapshot_files(stage: Path) -> list[dict]:
    records: list[dict] = []
    for path in sorted(stage.rglob("*")):
        rel = path.relative_to(stage).as_posix()
        if rel == ".git" or rel.startswith(".git/") or rel == GODOT_REL or rel.startswith(GODOT_REL + "/"):
            continue
        info = path.lstat()
        is_symlink = stat.S_ISLNK(info.st_mode)
        if is_symlink:
            target = os.fsencode(os.readlink(path))
            size = len(target)
            digest = hashlib.sha256(target).hexdigest()
            mode = 0
            symlink_target = os.fsdecode(target)
        elif stat.S_ISREG(info.st_mode):
            digest, size = sha256_file(path)
            mode = stat.S_IMODE(info.st_mode)
            symlink_target = None
        else:
            continue
        records.append({
            "path": rel,
            "source_sha256": digest,
            "source_size_bytes": size,
            "snapshot_sha256": digest,
            "snapshot_size_bytes": size,
            "source_git_mode": None,
            "source_observed_mode": oct(mode),
            "source_class": "commit_archive_or_explicit_overlay",
            "snapshot_mode": oct(mode),
            "shell_normalized": False,
            "symlink": is_symlink,
            "symlink_target": symlink_target,
        })
    return records


def apply_overlays(root: Path, stage: Path, base_entries: dict[str, dict], overlay_specs: list[str]) -> list[dict]:
    outputs: list[dict] = []
    seen: set[str] = set()
    for spec in overlay_specs:
        if "=" in spec:
            raw_rel, raw_source = spec.split("=", 1)
        else:
            raw_rel = raw_source = spec
        rel = PurePosixPath(raw_rel.replace("\\", "/")).as_posix()
        if rel.startswith("/") or ".." in PurePosixPath(rel).parts or rel in seen:
            raise RuntimeError(f"invalid or duplicate overlay destination: {raw_rel}")
        seen.add(rel)
        source_arg = Path(raw_source)
        source = source_arg.resolve() if source_arg.is_absolute() else (root / source_arg).resolve()
        destination = stage / Path(rel)
        if not source.exists() and not source.is_symlink():
            raise FileNotFoundError(f"overlay source does not exist: {source}")
        if destination.exists() or destination.is_symlink():
            if destination.is_dir() and not destination.is_symlink():
                raise RuntimeError(f"overlay would replace a directory: {rel}")
            destination.unlink()
        destination.parent.mkdir(parents=True, exist_ok=True)
        info = source.lstat()
        if stat.S_ISLNK(info.st_mode):
            link = os.readlink(source)
            os.symlink(link, destination)
            digest = hashlib.sha256(os.fsencode(link)).hexdigest()
            size = len(os.fsencode(link))
            is_symlink = True
        elif stat.S_ISREG(info.st_mode):
            shutil.copyfile(source, destination)
            is_symlink = False
            digest, size = sha256_file(source)
            source_mode = base_entries.get(rel, {}).get("git_mode", 0o100644)
            mode = 0o755 if rel.lower().endswith(".sh") else (source_mode & 0o777)
            destination.chmod(mode)
        else:
            raise RuntimeError(f"unsupported overlay entry type: {rel}")
        outputs.append({
            "path": rel,
            "source_path": os.fspath(source),
            "working_sha256": digest,
            "working_size_bytes": size,
            "base_blob_oid": base_entries.get(rel, {}).get("blob_oid"),
            "base_git_mode": oct(base_entries[rel]["git_mode"]) if rel in base_entries else None,
            "symlink": is_symlink,
            "reason": "explicitly named final audit overlay",
        })
    return outputs


def capture(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    archive = Path(args.archive).resolve()
    manifest_path = Path(args.manifest).resolve()
    stage = Path(args.staging).resolve()
    for target in (archive, manifest_path, stage):
        if target == root or root in target.parents:
            raise RuntimeError("archive, manifest, and staging must be outside the source repository")
    if archive.exists() or manifest_path.exists() or stage.exists():
        raise FileExistsError("refusing to overwrite existing archive, manifest, or staging path")
    stage.mkdir(parents=True)
    revision = os.fsdecode(git(root, "rev-parse", "--verify", args.revision)).strip()
    tree_oid = os.fsdecode(git(root, "rev-parse", f"{revision}^{{tree}}")).strip()
    base_entries = tree_entries(root, revision)
    if not base_entries:
        raise RuntimeError("commit archive contains no tracked files")

    archive.parent.mkdir(parents=True, exist_ok=True)
    base_blob_checks = materialize_git_archive(root, revision, stage, base_entries)

    overlay_records = apply_overlays(root, stage, base_entries, args.overlay)
    overlay_source_manifest_data = None
    if args.overlay_manifest:
        overlay_source_manifest_path = Path(args.overlay_manifest).resolve()
        overlay_source_manifest_data = json.loads(overlay_source_manifest_path.read_text(encoding="utf-8"))
        expected_overlay_hashes = overlay_source_manifest_data.get("files", {})
        normalized_paths = set(args.overlay_normalized)
        for record in overlay_records:
            expected_hash = expected_overlay_hashes.get(record["path"])
            record["integrated_source_manifest_sha256"] = expected_hash
            record["matches_integrated_source_manifest"] = expected_hash == record["working_sha256"]
            if expected_hash is None:
                raise RuntimeError(f"overlay path missing from integrated source manifest: {record['path']}")
            if expected_hash != record["working_sha256"] and record["path"] not in normalized_paths:
                raise RuntimeError(
                    f"overlay hash differs from integrated source manifest for {record['path']}: "
                    f"expected={expected_hash} actual={record['working_sha256']}"
                )
            if record["path"] in normalized_paths and expected_hash == record["working_sha256"]:
                raise RuntimeError(f"declared normalized overlay unexpectedly matches unnormalized source: {record['path']}")
    normalized_shells = normalize_shells(stage)

    godot_source = root / GODOT_REL
    if not godot_source.is_file():
        raise FileNotFoundError(f"pinned Godot binary missing: {godot_source}")
    godot_sha256, godot_size = sha256_file(godot_source)
    godot_sha512 = sha512_file(godot_source)
    if godot_sha256 != GODOT_SHA256 or godot_sha512 != GODOT_SHA512:
        raise RuntimeError(f"pinned Godot hash mismatch: sha256={godot_sha256} sha512={godot_sha512}")
    godot_destination = stage / Path(GODOT_REL)
    godot_destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(godot_source, godot_destination)
    godot_destination.chmod(0o755)

    files = snapshot_files(stage)
    with tarfile.open(archive, mode="w", format=tarfile.PAX_FORMAT) as output_tar:
        for record in files:
            rel = record["path"]
            path = stage / Path(rel)
            member = tarfile.TarInfo(rel)
            member.mtime = 0
            member.uid = 0
            member.gid = 0
            member.uname = ""
            member.gname = ""
            member.mode = int(record["snapshot_mode"], 8)
            if record["symlink"]:
                member.type = tarfile.SYMTYPE
                member.linkname = record["symlink_target"]
                member.size = 0
                output_tar.addfile(member)
            else:
                member.size = path.stat().st_size
                with path.open("rb") as stream:
                    output_tar.addfile(member, stream)
        member = tarfile.TarInfo(GODOT_REL)
        member.size = godot_size
        member.mode = 0o755
        member.mtime = 0
        member.uid = 0
        member.gid = 0
        member.uname = ""
        member.gname = ""
        with godot_destination.open("rb") as stream:
            output_tar.addfile(member, stream)

    live_delta, live_metadata = worktree_delta(root, revision)
    live_delta_path = Path(args.live_delta).resolve() if args.live_delta else None
    if live_delta_path:
        live_delta_path.parent.mkdir(parents=True, exist_ok=True)
        live_delta_path.write_text(json.dumps({
            "format": "openrc-live-working-tree-delta-vs-fixed-commit-v1",
            "captured_utc": datetime.now(timezone.utc).isoformat(),
            "metadata": live_metadata,
            "paths": live_delta,
        }, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    overlay_manifest_record = None
    if args.overlay_manifest:
        overlay_manifest_path = Path(args.overlay_manifest).resolve()
        digest, size = sha256_file(overlay_manifest_path)
        overlay_manifest_record = {
            "path": os.fspath(overlay_manifest_path),
            "sha256": digest,
            "size_bytes": size,
        }
    overlay_transform_record = None
    if args.overlay_transform_manifest:
        transform_path = Path(args.overlay_transform_manifest).resolve()
        transform_data = json.loads(transform_path.read_text(encoding="utf-8"))
        transform_digest, transform_size = sha256_file(transform_path)
        transformed = [r for r in overlay_records if r["path"] == transform_data.get("path")]
        if len(transformed) != 1 or transformed[0]["working_sha256"] != transform_data.get("overlay_sha256"):
            raise RuntimeError("R05B overlay transform metadata does not match its staged file hash")
        overlay_transform_record = {
            "path": os.fspath(transform_path),
            "sha256": transform_digest,
            "size_bytes": transform_size,
            "content": transform_data,
        }

    manifest = {
        "format": "openrc-linux-verification-source-manifest-v2",
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "source_root": os.fspath(root),
        "source_scope": "Git archive checkout of one fixed commit, honoring its .gitattributes eol rules, plus only the explicitly listed overlay paths; commit blobs are verified by clean-normalizing each extracted file back to its Git object ID. This is not the complete live working tree",
        "source_revision": revision,
        "source_tree_oid": tree_oid,
        "source_file_count": len(files),
        "commit_file_count": len(base_entries),
        "commit_blob_verification_count": len(base_blob_checks),
        "commit_blobs_verified": True,
        "checkout_attributes_source": "fixed commit .gitattributes; live .gitattributes raw blob was required to equal that commit blob before git archive",
        "commit_blob_checks": base_blob_checks,
        "commit_archive_overlay_records": overlay_records,
        "overlay_source_manifest": overlay_manifest_record,
        "overlay_transform_manifest": overlay_transform_record,
        "overlay_notes": args.overlay_note,
        "shell_files_normalized": normalized_shells,
        "shell_policy": "all *.sh have CRLF converted to LF and executable mode 0755",
        "live_delta_manifest": os.fspath(live_delta_path) if live_delta_path else None,
        "live_delta_path_count": len(live_delta),
        "live_delta_metadata": live_metadata,
        "files": files,
        "pinned_godot": {
            "path": GODOT_REL,
            "sha256": godot_sha256,
            "sha512": godot_sha512,
            "size_bytes": godot_size,
            "snapshot_mode": "0o755",
        },
        "archive": os.fspath(archive),
        "archive_size_bytes": archive.stat().st_size,
        "archive_sha256": sha256_file(archive)[0],
        "staging_root": os.fspath(stage),
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"captured fixed commit {revision} ({tree_oid}); base files={len(base_entries)} overlays={len(overlay_records)} "
        f"normalized_shells={len(normalized_shells)} live_delta_paths={len(live_delta)}"
    )
    print(f"archive={archive} bytes={archive.stat().st_size} sha256={manifest['archive_sha256']}")
    print(f"manifest={manifest_path}")
    if overlay_records:
        print("overlay paths: " + ", ".join(item["path"] for item in overlay_records))


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)
    cap = sub.add_parser("capture")
    cap.add_argument("--root", required=True)
    cap.add_argument("--revision", required=True)
    cap.add_argument("--archive", required=True)
    cap.add_argument("--manifest", required=True)
    cap.add_argument("--staging", required=True)
    cap.add_argument("--live-delta")
    cap.add_argument("--overlay", action="append", default=[])
    cap.add_argument("--overlay-manifest")
    cap.add_argument("--overlay-normalized", action="append", default=[])
    cap.add_argument("--overlay-transform-manifest")
    cap.add_argument("--overlay-note", action="append", default=[])
    cap.set_defaults(func=capture)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
