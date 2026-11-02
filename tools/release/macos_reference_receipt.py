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
import shutil
import stat
import struct
import subprocess
import unicodedata
import zipfile

FORMAT = "openrc-macos-reference-bundle-v1"
KIND = "macos-reference-bundle-v1"
INPUT_FORMAT = "openrc-macos-reference-inputs-v1"
SUFFIX = ".openrc-reference-receipt"
HEX = re.compile(r"[0-9a-f]{64}\Z")
GIT = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
ARCH = {0x01000007: "x86_64", 0x0100000C: "arm64"}
MAX_FILES = 10000
MAX_RECEIPT = 4 * 1024 * 1024
MAX_MEMBER = 4 * 1024 * 1024 * 1024
MAX_EXPANDED = 8 * 1024 * 1024 * 1024


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
    return bool(value) and not any(c in value for c in "\0\t\r\n\\")


def _relative(value: str) -> bool:
    return _safe(value) and not value.startswith("/") and all(p not in ("", ".", "..") for p in value.split("/"))


def _pack_names(executable: str) -> set[str]:
    name = Path(executable).name
    return {"Contents/Resources/" + Path(name).stem + ".pck", "Contents/Resources/" + name + ".pck"}


def _check_pack_stream(stream, size: int, executable: str, pack: str) -> None:
    if pack not in _pack_names(executable):
        raise ValueError("PCK name is not a standard Godot bundle pack for this executable")
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


def _check_pack(bundle: Path, executable: str, pack: str) -> None:
    if pack not in _pack_names(executable):
        raise ValueError("PCK name is not a standard Godot bundle pack for this executable")
    with (bundle / pack).open("rb") as stream:
        _check_pack_stream(stream, (bundle / pack).stat().st_size, executable, pack)


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


def _macho_architectures_stream(stream, size: int) -> list[str]:
    """Read supported 64-bit Mach-O slices, rejecting malformed/duplicate slices."""
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


def macho_architectures(path: Path) -> list[str]:
    with path.open("rb") as stream:
        return _macho_architectures_stream(stream, path.stat().st_size)


def _manifest():
    if __package__:
        from . import manifest
        return manifest
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


def _payload_paths(files: dict[str, str]) -> tuple[str, str]:
    executables = [p for p in files if p.startswith("Contents/MacOS/") and p.count("/") == 2]
    packs = [p for p in files if p.lower().endswith(".pck")]
    if len(executables) != 1 or len(packs) != 1 or not packs[0].startswith("Contents/Resources/"):
        raise ValueError("bundle must contain one executable and one Resources PCK")
    return executables[0], packs[0]


def _receipt_bytes(bundle_name: str, files: dict[str, str], arches: list[str], source: dict,
                   snapshot_hash: str, probe_hash: str) -> bytes:
    executable, pack = _payload_paths(files)
    lines = [FORMAT, "bundle\t" + bundle_name, "architectures\t" + ",".join(arches),
             "executable\t" + executable, "pack\t" + pack,
             "source_commit\t" + source["commit"], "source_tree\t" + source["tree"],
             "source_worktree_sha256\t" + source["worktree_sha256"], "source_receipt_sha256\t" + snapshot_hash,
             "probe_sha256\t" + probe_hash]
    lines.extend("file\t" + files[name] + "\t" + name for name in sorted(files))
    data = ("\n".join(lines) + "\n").encode("utf-8")
    if len(data) > MAX_RECEIPT:
        raise ValueError("receipt is too large")
    return data


def create(bundle: Path, snapshot: Path, root: Path) -> Path:
    if not bundle.name.endswith(".app") or not _safe(bundle.name):
        raise ValueError("invalid app bundle name")
    root = root.resolve()
    source = _source_snapshot(snapshot, root)
    snapshot_hash = digest(snapshot)
    probe_hash = digest(root / "research/performance/session_probe.gd")
    files = _files(bundle)
    executable, pack = _payload_paths(files)
    _check_pack(bundle, executable, pack)
    arches = macho_architectures(bundle / executable)
    data = _receipt_bytes(bundle.name, files, arches, source, snapshot_hash, probe_hash)
    if _source_snapshot(snapshot, root) != source or digest(snapshot) != snapshot_hash \
            or digest(root / "research/performance/session_probe.gd") != probe_hash or _files(bundle) != files:
        raise ValueError("inputs changed while creating receipt")
    path = bundle.with_name(bundle.name + SUFFIX)
    with path.open("xb") as stream:
        stream.write(data)
    return path


def _verify_receipt(data: bytes, bundle_name: str, executable: str, actual_files: dict[str, str],
                    actual_arches: list[str], architecture: str) -> dict:
    if len(data) > MAX_RECEIPT:
        raise ValueError("receipt is too large")
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
    if values["bundle"] != bundle_name or values["executable"] != executable:
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
    if _payload_paths(files) != (values["executable"], values["pack"]):
        raise ValueError("receipt must identify the only executable and Resources PCK")
    if actual_files != files or actual_arches != arches:
        raise ValueError("bundle differs from its receipt")
    receipt_hash = hashlib.sha256(data).hexdigest()
    identity = hashlib.sha256((receipt_hash + "\n" + architecture).encode("utf-8")).hexdigest()
    return {"kind": KIND, "sha256": identity, "receipt_sha256": receipt_hash,
            "executable_sha256": files[values["executable"]], "pack_sha256": files[values["pack"]],
            "probe_sha256": values["probe_sha256"], "architecture": architecture,
            "architectures": arches,
            "source_commit": values["source_commit"], "source_tree": values["source_tree"],
            "source_worktree_sha256": values["source_worktree_sha256"],
            "source_receipt_sha256": values["source_receipt_sha256"]}


def verify(executable: Path, architecture: str) -> dict:
    bundle = bundle_from_executable(executable)
    receipt = bundle.with_name(bundle.name + SUFFIX)
    if receipt.is_symlink() or not receipt.is_file() or receipt.stat().st_size > MAX_RECEIPT:
        raise ValueError("missing or unsafe bundle receipt")
    files = _files(bundle)
    _, pack = _payload_paths(files)
    relative_executable = executable.relative_to(bundle).as_posix()
    result = _verify_receipt(receipt.read_bytes(), bundle.name, relative_executable, files,
                             macho_architectures(executable), architecture)
    _check_pack(bundle, relative_executable, pack)
    return result


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


def _archive_contents(path: Path, *, receipt_required: bool):
    """Inspect the ZIP in place; never extract or change the signed bundle."""
    if path.is_symlink() or not path.is_file():
        raise ValueError("archive must be a regular file")
    before = path.stat()
    with zipfile.ZipFile(path) as archive:
        members = {}
        total = 0
        for info in archive.infolist():
            name = info.orig_filename
            is_dir = info.is_dir()
            normalized = name[:-1] if is_dir else name
            if not _relative(normalized) or len(normalized.split("/")) > 33 or normalized in members:
                raise ValueError(f"unsafe or duplicate ZIP member: {name!r}")
            mode = info.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if kind not in ((0, stat.S_IFDIR) if is_dir else (0, stat.S_IFREG)):
                raise ValueError(f"ZIP contains a link or special file: {name!r}")
            if (info.flag_bits & 1 or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    or (is_dir and info.file_size) or info.file_size > MAX_MEMBER):
                raise ValueError(f"unsafe or oversized ZIP member: {name!r}")
            total += info.file_size
            if total > MAX_EXPANDED or len(members) >= MAX_FILES:
                raise ValueError("ZIP exceeds inventory limits")
            members[normalized] = info
        for name in members:
            parents = name.split("/")[:-1]
            for index in range(1, len(parents) + 1):
                parent = members.get("/".join(parents[:index]))
                if parent is not None and not parent.is_dir():
                    raise ValueError("ZIP file is a parent of another member")
        # Common Mac filesystems fold case and Unicode normalization. Check
        # implicit directories too, so extraction cannot merge distinct paths.
        aliases = {}
        for name in members:
            parts = name.split("/")
            for end in range(1, len(parts) + 1):
                part = "/".join(parts[:end])
                key = unicodedata.normalize("NFD", unicodedata.normalize("NFD", part).casefold())
                previous = aliases.setdefault(key, part)
                if previous != part:
                    raise ValueError(f"ZIP paths collide on Mac filesystems: {previous!r}, {part!r}")
        roots = {name.split("/", 1)[0] for name in members if name.split("/", 1)[0].endswith(".app")}
        if len(roots) != 1:
            raise ValueError("ZIP must contain exactly one app bundle")
        bundle_name = roots.pop()
        receipt_name = bundle_name + SUFFIX
        if bundle_name in members and not members[bundle_name].is_dir():
            raise ValueError("app bundle is not a directory")
        for name, info in members.items():
            if name == bundle_name or name.startswith(bundle_name + "/"):
                continue
            if receipt_required and name == receipt_name and not info.is_dir():
                continue
            raise ValueError(f"unexpected ZIP member outside app bundle: {name!r}")
        if receipt_required and receipt_name not in members:
            raise ValueError("missing external bundle receipt in ZIP")
        if receipt_required and members[receipt_name].file_size > MAX_RECEIPT:
            raise ValueError("receipt is too large")

        files = {}
        prefix = bundle_name + "/"
        for name, info in members.items():
            if not name.startswith(prefix) or info.is_dir():
                continue
            if name.endswith(SUFFIX):
                raise ValueError("reference receipt must be outside the signed app bundle")
            relative = name[len(prefix):]
            h = hashlib.sha256()
            read = 0
            with archive.open(info) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    read += len(block)
                    if read > info.file_size:
                        raise ValueError(f"ZIP member exceeds declared size: {name!r}")
                    h.update(block)
            if read != info.file_size:
                raise ValueError(f"ZIP member has an incorrect size: {name!r}")
            files[relative] = h.hexdigest()
        executable, pack = _payload_paths(files)
        executable_info = members[prefix + executable]
        if not (executable_info.external_attr >> 16) & stat.S_IXUSR:
            raise ValueError("ZIP app executable lacks user execute permission")
        with archive.open(executable_info) as stream:
            arches = _macho_architectures_stream(stream, executable_info.file_size)
        pack_info = members[prefix + pack]
        with archive.open(pack_info) as stream:
            _check_pack_stream(stream, pack_info.file_size, executable, pack)
        bundle_attributes = {name: (info.create_system, info.external_attr) for name, info in members.items()
                             if name == bundle_name or name.startswith(prefix)}
        data = archive.read(members[receipt_name]) if receipt_required else None
    after = path.stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
        raise ValueError("ZIP changed while inspecting it")
    return bundle_name, files, arches, executable, bundle_attributes, data


def verify_zip(path: Path, *, source: dict | None = None, snapshot_hash: str | None = None,
               probe_hash: str | None = None, staged_zip: Path | None = None) -> dict:
    bundle_name, files, arches, executable, attributes, data = _archive_contents(path, receipt_required=True)
    identity = _verify_receipt(data, bundle_name, executable, files, arches, arches[0])
    if staged_zip is not None:
        staged = _archive_contents(staged_zip, receipt_required=False)
        if staged[:5] != (bundle_name, files, arches, executable, attributes):
            raise ValueError("final Mac bundle differs from the checked staged ZIP")
    if source is not None:
        for field in ("commit", "tree", "worktree_sha256"):
            if identity["source_" + field] != source[field]:
                raise ValueError(f"ZIP receipt source {field} differs from release identity")
    if snapshot_hash is not None and identity["source_receipt_sha256"] != snapshot_hash:
        raise ValueError("ZIP receipt differs from captured release inputs")
    if probe_hash is not None and identity["probe_sha256"] != probe_hash:
        raise ValueError("ZIP receipt differs from the captured probe")
    return identity


def package_zip(source_zip: Path, output_zip: Path, snapshot: Path, root: Path) -> dict:
    """Add one sibling receipt to a copy of Godot's final signed app ZIP."""
    root = root.resolve()
    source = _source_snapshot(snapshot, root)
    snapshot_hash = digest(snapshot)
    probe_hash = digest(root / "research/performance/session_probe.gd")
    bundle_name, files, arches, _, _, _ = _archive_contents(source_zip, receipt_required=False)
    data = _receipt_bytes(bundle_name, files, arches, source, snapshot_hash, probe_hash)
    # Exclusive creation preserves the exporter's existing-output contract.
    with source_zip.open("rb") as incoming, output_zip.open("xb") as outgoing:
        shutil.copyfileobj(incoming, outgoing, length=1024 * 1024)
    info = zipfile.ZipInfo(bundle_name + SUFFIX)
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with zipfile.ZipFile(output_zip, "a") as archive:
        archive.writestr(info, data)
    identity = verify_zip(output_zip, source=source, snapshot_hash=snapshot_hash, probe_hash=probe_hash,
                          staged_zip=source_zip)
    if (_source_snapshot(snapshot, root) != source or digest(snapshot) != snapshot_hash
            or digest(root / "research/performance/session_probe.gd") != probe_hash
            or identity["receipt_sha256"] != hashlib.sha256(data).hexdigest()):
        raise ValueError("inputs changed while creating ZIP receipt")
    return identity


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
    package = commands.add_parser("package-zip", help="add a sibling receipt to a new final ZIP")
    package.add_argument("archive", type=Path)
    package.add_argument("--output", type=Path, required=True)
    package.add_argument("--inputs", type=Path, required=True)
    package.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
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
        if args.command == "package-zip":
            identity = package_zip(args.archive, args.output, args.inputs, args.root)
            print(f"Wrote {args.output}; receipt {identity['receipt_sha256']}; signing trust is checked separately.")
            return
        path = create(args.bundle.absolute(), args.inputs, args.root)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, f"receipt failed: {error}\n")
    print(f"Wrote {path}; consistency only, signature and publisher trust require separate verification.")


if __name__ == "__main__":
    main()
