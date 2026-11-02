#!/usr/bin/env python3
"""Bind a final signed macOS app to an external, architecture-specific reference identity.

Create the receipt only after signing/notarization/stapling, without modifying the
.app. The recorded source snapshot is a checked build-input declaration; neither
it nor the hashes establish publisher trust or prove source-to-binary reproducibility.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess

FORMAT = "openrc-macos-reference-bundle-v1"
KIND = "macos-reference-bundle-v1"
INPUT_FORMAT = "openrc-macos-reference-inputs-v1"
SUFFIX = ".openrc-reference-receipt"
HEX = re.compile(r"[0-9a-f]{64}\Z")
GIT = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
ARCH = {0x01000007: "x86_64", 0x0100000C: "arm64"}
MAX_FILES = 10000
MAX_RECEIPT = 4 * 1024 * 1024


def digest(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"not a regular file: {path}")
    before = path.stat()
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
        raise ValueError(f"file changed while hashing: {path}")
    return h.hexdigest()


def _safe(value: str) -> bool:
    return bool(value) and not any(c in value for c in "\t\r\n\\")


def _relative(value: str) -> bool:
    return _safe(value) and not value.startswith("/") and all(p not in ("", ".", "..") for p in value.split("/"))


def _pack_names(executable: str) -> set[str]:
    name = Path(executable).name
    return {"Contents/Resources/" + Path(name).stem + ".pck", "Contents/Resources/" + name + ".pck"}


def _check_pack(bundle: Path, executable: str, pack: str) -> None:
    if pack not in _pack_names(executable):
        raise ValueError("PCK name is not a standard Godot bundle pack for this executable")
    with (bundle / pack).open("rb") as stream:
        size = (bundle / pack).stat().st_size
        header = stream.read(40)
        if len(header) != 40:
            raise ValueError("truncated bundle PCK header")
        magic, version, major, minor, _patch, flags, _file_base, directory = struct.unpack("<4sIIIIIQQ", header)
        if magic != b"GDPC" or version not in (2, 3, 4) or major != 4 or minor > 8 or flags & ~2:
            raise ValueError("unsupported, encrypted or sparse bundle PCK")
        directory = 96 if version == 2 else directory
        if directory < 40 or directory > size - 4:
            raise ValueError("bundle PCK directory is outside the file")
        stream.seek(directory)
        count_bytes = stream.read(4)
        if len(count_bytes) != 4:
            raise ValueError("bundle PCK changed while reading its directory")
        count = struct.unpack("<I", count_bytes)[0]
        if not 1 <= count <= 200000:
            raise ValueError("bundle PCK directory is empty or oversized")


def bundle_from_executable(executable: Path) -> Path:
    if executable.parent.name != "MacOS" or executable.parent.parent.name != "Contents":
        raise ValueError("executable must be inside .app/Contents/MacOS")
    bundle = executable.parent.parent.parent
    if not bundle.name.endswith(".app") or not _safe(bundle.name):
        raise ValueError("invalid app bundle name")
    return bundle


def looks_like_bundle_executable(executable: Path) -> bool:
    return executable.parent.name == "MacOS" and executable.parent.parent.name == "Contents"


def _files(bundle: Path) -> dict[str, str]:
    if bundle.is_symlink() or not bundle.is_dir():
        raise ValueError("bundle must be a real directory")
    entries: dict[str, str] = {}
    def fail_walk(error: OSError) -> None:
        raise error

    count = 0
    for root, dirs, files in os.walk(bundle, followlinks=False, onerror=fail_walk):
        count += len(dirs) + len(files)
        if count > MAX_FILES or len(Path(root).relative_to(bundle).parts) > 32:
            raise ValueError("bundle has too many entries or exceeds the depth limit")
        for name in dirs:
            path = Path(root) / name
            if path.is_symlink():
                raise ValueError(f"bundle contains symlink: {path}")
        for name in files:
            path = Path(root) / name
            relative = path.relative_to(bundle).as_posix()
            if not _relative(relative) or path.is_symlink() or not stat.S_ISREG(path.stat().st_mode):
                raise ValueError(f"unsafe bundle entry: {path}")
            entries[relative] = digest(path)
    return entries


def macho_architectures(path: Path) -> list[str]:
    """Read supported 64-bit Mach-O slices, rejecting malformed/duplicate slices."""
    size = path.stat().st_size
    with path.open("rb") as stream:
        if size < 32:
            raise ValueError("truncated Mach-O")
        stream.seek(-4, os.SEEK_END)
        if stream.read(4) == b"GDPC":
            raise ValueError("embedded executable PCK is not a separate reference bundle")
        stream.seek(0)
        head = stream.read(8)
        if len(head) != 8:
            raise ValueError("truncated Mach-O")
        magic = struct.unpack(">I", head[:4])[0]
        if magic == 0xCAFEBABE:
            count = struct.unpack(">I", head[4:])[0]
            if not 1 <= count <= 2:
                raise ValueError("unsupported Mach-O slice count")
            table = stream.read(count * 20)
            if len(table) != count * 20:
                raise ValueError("truncated Mach-O slice table")
            slices = []
            for index in range(count):
                cpu, _, offset, length, _ = struct.unpack_from(">IIIII", table, index * 20)
                if offset < 8 + count * 20 or length < 32 or offset + length > size:
                    raise ValueError("invalid Mach-O slice bounds")
                stream.seek(offset)
                inner = stream.read(8)
                if len(inner) != 8 or struct.unpack("<II", inner) != (0xFEEDFACF, cpu):
                    raise ValueError("Mach-O slice header disagrees with table")
                slices.append((cpu, offset, offset + length))
            if len(slices) == 2 and max(slices[0][1], slices[1][1]) < min(slices[0][2], slices[1][2]):
                raise ValueError("overlapping Mach-O slices")
            cpus = [row[0] for row in slices]
        elif struct.unpack("<I", head[:4])[0] == 0xFEEDFACF and size >= 32:
            cpus = [struct.unpack("<I", head[4:])[0]]
        else:
            raise ValueError("not a supported 64-bit Mach-O")
    if len(set(cpus)) != len(cpus) or any(cpu not in ARCH for cpu in cpus):
        raise ValueError("unsupported or duplicate architecture")
    return sorted(ARCH[cpu] for cpu in cpus)


def _manifest():
    spec = importlib.util.spec_from_file_location("openrc_release_manifest", Path(__file__).with_name("manifest.py"))
    if spec is None or spec.loader is None:
        raise ValueError("release manifest validator unavailable")
    manifest = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(manifest)
    return manifest


def capture_source(root: Path, editor: Path, template: Path) -> dict:
    """Capture the Mac build inputs without reading any NK-3 receipt or library."""
    manifest = _manifest()
    root = root.resolve()
    dirty, worktree_hash = manifest.worktree_identity(root)
    source = {"commit": manifest.git(root, "rev-parse", "HEAD").decode().strip(),
              "tree": manifest.git(root, "rev-parse", "HEAD^{tree}").decode().strip(),
              "dirty": dirty, "worktree_sha256": worktree_hash}
    paths = {"editor": str(editor.absolute()), "macos_template": str(template.absolute()),
             "probe": str(root / "research/performance/session_probe.gd")}
    return {"format": INPUT_FORMAT, "source": source,
            "inputs": {key: manifest.file_info(Path(path)) for key, path in paths.items()}, "paths": paths}


def _source_snapshot(snapshot: Path, root: Path) -> dict:
    manifest = _manifest()
    captured = manifest.read_json(snapshot)
    if captured.get("format") == INPUT_FORMAT:
        if set(captured) != {"format", "source", "inputs", "paths"} or not isinstance(captured.get("paths"), dict) \
                or set(captured["paths"]) != {"editor", "macos_template", "probe"}:
            raise ValueError("invalid Mac reference input snapshot")
        paths = captured["paths"]
        if capture_source(root, Path(paths["editor"]), Path(paths["macos_template"])) != captured:
            raise ValueError("Mac reference source or inputs changed since capture")
        return captured["source"]
    if captured.get("format") != "openrc-release-inputs-v1" or not isinstance(captured.get("source"), dict):
        raise ValueError("invalid release input snapshot")
    source = captured["source"]
    env = {"OPENRC_BUILD_DESCRIBE": source["version"], "OPENRC_BUILD_COMMIT": source["commit"],
           "OPENRC_BUILD_DATE": source["commit_date"], "OPENRC_BUILD_DIRTY": "1" if source["dirty"] else "0",
           "GITHUB_REF": "refs/tags/" + source["tag"] if source["tag"] else ""}
    if manifest.source_identity(root, env) != source:
        raise ValueError("source differs from the release input snapshot")
    if set(captured["paths"]) != set(captured["inputs"]):
        raise ValueError("incomplete release input snapshot")
    for name, path in captured["paths"].items():
        if manifest.file_info(Path(path)) != captured["inputs"][name]:
            raise ValueError(f"release input changed: {name}")
    return source


def create(bundle: Path, snapshot: Path, root: Path) -> Path:
    if not bundle.name.endswith(".app") or not _safe(bundle.name):
        raise ValueError("invalid app bundle name")
    root = root.resolve()
    source = _source_snapshot(snapshot, root)
    snapshot_hash = digest(snapshot)
    probe_hash = digest(root / "research/performance/session_probe.gd")
    files = _files(bundle)
    executables = [p for p in files if p.startswith("Contents/MacOS/") and p.count("/") == 2]
    packs = [p for p in files if p.lower().endswith(".pck")]
    if len(executables) != 1 or len(packs) != 1 or not packs[0].startswith("Contents/Resources/"):
        raise ValueError("bundle must contain one executable and one Resources PCK")
    _check_pack(bundle, executables[0], packs[0])
    arches = macho_architectures(bundle / executables[0])
    lines = [FORMAT, "bundle\t" + bundle.name, "architectures\t" + ",".join(arches),
             "executable\t" + executables[0], "pack\t" + packs[0],
             "source_commit\t" + source["commit"], "source_tree\t" + source["tree"],
             "source_worktree_sha256\t" + source["worktree_sha256"], "source_receipt_sha256\t" + snapshot_hash,
             "probe_sha256\t" + probe_hash]
    lines.extend("file\t" + files[name] + "\t" + name for name in sorted(files))
    data = ("\n".join(lines) + "\n").encode("utf-8")
    if len(data) > MAX_RECEIPT:
        raise ValueError("receipt is too large")
    if _source_snapshot(snapshot, root) != source or digest(snapshot) != snapshot_hash \
            or digest(root / "research/performance/session_probe.gd") != probe_hash or _files(bundle) != files:
        raise ValueError("inputs changed while creating receipt")
    path = bundle.with_name(bundle.name + SUFFIX)
    with path.open("xb") as stream:
        stream.write(data)
    return path


def verify(executable: Path, architecture: str) -> dict:
    bundle = bundle_from_executable(executable)
    receipt = bundle.with_name(bundle.name + SUFFIX)
    if receipt.is_symlink() or not receipt.is_file() or receipt.stat().st_size > MAX_RECEIPT:
        raise ValueError("missing or unsafe bundle receipt")
    data = receipt.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("receipt is not UTF-8") from exc
    if not text.endswith("\n") or "\r" in text:
        raise ValueError("malformed receipt")
    lines = text[:-1].split("\n")
    fields = ("bundle", "architectures", "executable", "pack", "source_commit", "source_tree",
              "source_worktree_sha256", "source_receipt_sha256", "probe_sha256")
    if len(lines) < 11 or lines[0] != FORMAT:
        raise ValueError("unsupported or incomplete receipt")
    values = {}
    for line, field in zip(lines[1:10], fields):
        parts = line.split("\t")
        if len(parts) != 2 or parts[0] != field or not _safe(parts[1]):
            raise ValueError(f"malformed receipt field: {field}")
        values[field] = parts[1]
    arches = values["architectures"].split(",")
    if arches != sorted(set(arches)) or any(a not in ("arm64", "x86_64") for a in arches) or architecture not in arches:
        raise ValueError("receipt does not support this architecture")
    if values["bundle"] != bundle.name or values["executable"] != executable.relative_to(bundle).as_posix():
        raise ValueError("receipt identifies a different bundle or executable")
    for field in ("source_commit", "source_tree"):
        if not GIT.fullmatch(values[field]):
            raise ValueError(f"invalid {field}")
    for field in ("source_worktree_sha256", "source_receipt_sha256", "probe_sha256"):
        if not HEX.fullmatch(values[field]):
            raise ValueError(f"invalid {field}")
    files = {}
    for line in lines[10:]:
        row = line.split("\t")
        if len(row) != 3 or row[0] != "file" or not HEX.fullmatch(row[1]) or not _relative(row[2]) or row[2] in files:
            raise ValueError("malformed receipt file row")
        files[row[2]] = row[1]
    if not files or len(files) > MAX_FILES or list(files) != sorted(files):
        raise ValueError("invalid receipt file inventory")
    executables = [p for p in files if p.startswith("Contents/MacOS/") and p.count("/") == 2]
    packs = [p for p in files if p.lower().endswith(".pck")]
    if executables != [values["executable"]] or packs != [values["pack"]] or not values["pack"].startswith("Contents/Resources/"):
        raise ValueError("receipt must identify the only executable and Resources PCK")
    if _files(bundle) != files or macho_architectures(executable) != arches:
        raise ValueError("bundle differs from its receipt")
    _check_pack(bundle, values["executable"], values["pack"])
    receipt_hash = hashlib.sha256(data).hexdigest()
    identity = hashlib.sha256((receipt_hash + "\n" + architecture).encode("utf-8")).hexdigest()
    return {"kind": KIND, "sha256": identity, "receipt_sha256": receipt_hash,
            "executable_sha256": files[values["executable"]], "pack_sha256": files[values["pack"]],
            "probe_sha256": values["probe_sha256"], "architecture": architecture,
            "architectures": arches,
            "source_commit": values["source_commit"], "source_tree": values["source_tree"],
            "source_worktree_sha256": values["source_worktree_sha256"],
            "source_receipt_sha256": values["source_receipt_sha256"]}


def verify_for_launch(executable: Path) -> dict:
    arches = macho_architectures(executable)
    result = verify(executable, arches[0])
    result.pop("architecture")
    result.pop("sha256")
    result["identities"] = {
        arch: hashlib.sha256((result["receipt_sha256"] + "\n" + arch).encode("utf-8")).hexdigest()
        for arch in arches
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("capture", help="capture Mac-only build inputs before export")
    capture.add_argument("--editor", type=Path, required=True)
    capture.add_argument("--template", type=Path, required=True, help="exact Mac export template")
    capture.add_argument("--output", type=Path, required=True, help="new private input snapshot")
    capture.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    finalize = commands.add_parser("finalize", help="write the external receipt after signing")
    finalize.add_argument("bundle", type=Path, help="final signed .app, kept unchanged")
    finalize.add_argument("--inputs", type=Path, required=True, help="captured input snapshot from export")
    finalize.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    check = commands.add_parser("verify", help="verify an existing bundle and receipt")
    check.add_argument("executable", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "capture":
            data = capture_source(args.root, args.editor, args.template)
            with args.output.open("x", encoding="utf-8", newline="\n") as stream:
                json.dump(data, stream, ensure_ascii=True, sort_keys=True, indent=2)
                stream.write("\n")
            print(f"Wrote private source/input snapshot {args.output}")
            return
        if args.command == "verify":
            print(json.dumps(verify_for_launch(args.executable.absolute()), indent=2, sort_keys=True))
            return
        path = create(args.bundle.absolute(), args.inputs, args.root)
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"receipt failed: {error}\n")
    print(f"Wrote {path}; consistency only, signature and publisher trust require separate verification.")


if __name__ == "__main__":
    main()
