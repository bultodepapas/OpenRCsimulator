"""Capture and verify one attempt's independent source tree.

The caller owns the destination and must use a different tree and runtime profile
for every attempt. A successful receipt identifies bytes and relevant file metadata;
it is not an atomic, semantically consistent multi-file filesystem snapshot.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess


DEFAULT_SCOPE = ("app", "tools", "research/performance")
RESERVE_BYTES = 512 * 1024 * 1024
FORMAT = "openrc-testqueue-snapshot-v1"
_BLOCK = 1024 * 1024
_ADAPTERS = ("tools/debug/", "tools/godot/", "tools/godtest/", "tools/testqueue/")
_CACHE_FILES = ("uid_cache.bin", "global_script_class_cache.cfg", "extension_list.cfg")
_REPARSE = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
_WINDOWS_RELEVANT = 0x01 | 0x02 | 0x04 | 0x20 | 0x100 | 0x1000 | 0x2000


def _canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


def _digest(value: object) -> str:
    return hashlib.sha256(_canonical(value)).hexdigest()


def _relative(value: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        raise ValueError(f"invalid relative path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in (".", "..", ".git") or ":" in part for part in path.parts):
        raise ValueError(f"invalid relative path: {value!r}")
    if path.as_posix() != value:
        raise ValueError(f"invalid relative path: {value!r}")
    return value


def _check_no_links(path: Path) -> None:
    """Refuse symlinks and Windows junctions/reparse points in every component."""
    for component in reversed((path, *path.parents)):
        try:
            metadata = component.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, "st_file_attributes", 0) & _REPARSE:
            raise ValueError(f"linked or reparse-point path is not allowed: {component}")


def _signature(metadata: os.stat_result) -> tuple:
    return (
        metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_size,
        metadata.st_mtime_ns, metadata.st_ctime_ns,
        getattr(metadata, "st_file_attributes", None),
    )


def _file_stat(path: Path) -> os.stat_result:
    _check_no_links(path)
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"not a regular file: {path}")
    return metadata


def _git(root: Path, *args: str) -> bytes:
    try:
        return subprocess.check_output(
            ["git", "--literal-pathspecs", "-C", str(root), *args],
            stderr=subprocess.PIPE, timeout=120,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ValueError(f"Git command failed ({args[0]}): {exc}") from exc


def _git_paths(root: Path, args: tuple[str, ...], scope: tuple[str, ...]) -> set[str]:
    data = _git(root, *args, "--", *scope)
    return {_relative(os.fsdecode(item)) for item in data.split(b"\0") if item}


def _status(root: Path, scope: tuple[str, ...]) -> list[dict]:
    parts = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", *scope).split(b"\0")
    result = []
    index = 0
    while index < len(parts) and parts[index]:
        record = os.fsdecode(parts[index])
        if len(record) < 4 or record[2] != " ":
            raise ValueError("invalid Git status record")
        entry = {"status": record[:2], "path": _relative(record[3:])}
        if "R" in record[:2] or "C" in record[:2]:
            index += 1
            if index >= len(parts) or not parts[index]:
                raise ValueError("invalid Git rename status record")
            entry["original_path"] = _relative(os.fsdecode(parts[index]))
        result.append(entry)
        index += 1
    return result


def _walk_files(root: Path, relative: str, *, native: bool = False) -> set[str]:
    base = root / relative
    _check_no_links(base)
    if not base.exists():
        return set()
    if not base.is_dir():
        raise ValueError(f"not a directory: {base}")
    found: set[str] = set()
    pending = [base]
    while pending:
        directory = pending.pop()
        _check_no_links(directory)
        with os.scandir(directory) as entries:
            for entry in entries:
                # Godot/Windows leaves temporary DLL replacement files that cannot
                # be loaded by the extension and may still be held by the editor.
                if native and entry.name.startswith("~") and entry.name.lower().endswith(".tmp"):
                    continue
                path = Path(entry.path)
                _check_no_links(path)
                metadata = path.lstat()
                if stat.S_ISDIR(metadata.st_mode):
                    pending.append(path)
                elif stat.S_ISREG(metadata.st_mode):
                    found.add(_relative(path.relative_to(root).as_posix()))
                else:
                    raise ValueError(f"not a regular file or directory: {path}")
    return found


def _covered(path: str, scope: tuple[str, ...]) -> bool:
    return any(path == item or path.startswith(item + "/") for item in scope)


def _authoring_inputs(root: Path, candidates: set[str]) -> tuple[set[str], set[str]]:
    """Include the same aircraft authoring references consumed by GOD TEST."""
    present: set[str] = set()
    missing: set[str] = set()

    def collect(value: object) -> None:
        if isinstance(value, dict):
            for nested in value.values():
                collect(nested)
        elif isinstance(value, list):
            for nested in value:
                collect(nested)
        elif isinstance(value, str) and value.startswith("assets/"):
            name = _relative(value)
            path = root / name
            _check_no_links(path)
            try:
                _file_stat(path)
            except FileNotFoundError:
                missing.add(name)
            else:
                present.add(name)

    for name in sorted(candidates):
        parts = PurePosixPath(name).parts
        if (len(parts) != 4 or parts[:2] != ("app", "data")
                or parts[2] not in ("aircraft_models", "aircraft_model_overlays")
                or not name.endswith(".json")):
            continue
        path = root / name
        try:
            metadata = _file_stat(path)
        except FileNotFoundError:
            continue  # A tracked deletion is recorded by the normal inventory.
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        with os.fdopen(os.open(path, flags), "rb") as stream:
            if _signature(os.fstat(stream.fileno())) != _signature(metadata):
                raise ValueError(f"source changed during snapshot: {name}")
            text = stream.read().decode("utf-8")
            if _signature(os.fstat(stream.fileno())) != _signature(metadata):
                raise ValueError(f"source changed during snapshot: {name}")
        if _signature(_file_stat(path)) != _signature(metadata):
            raise ValueError(f"source changed during snapshot: {name}")
        collect(json.loads(text))
    return present, missing


def _native_inputs(root: Path, scope: tuple[str, ...]) -> set[str]:
    if _covered("app/native", scope):
        return _walk_files(root, "app/native", native=True)
    found: set[str] = set()
    for item in scope:
        if not item.startswith("app/native/"):
            continue
        path = root / item
        _check_no_links(path)
        if not path.exists():
            continue
        if path.is_dir():
            found |= _walk_files(root, item, native=True)
        elif not (path.name.startswith("~") and path.name.lower().endswith(".tmp")):
            _file_stat(path)
            found.add(item)
    return found


def _inventory(root: Path, scope: tuple[str, ...], include_imports: bool) -> dict:
    commit = _git(root, "rev-parse", "--verify", "HEAD").decode("ascii").strip()
    tracked = _git_paths(root, ("ls-files", "-z", "--cached"), scope)
    tracked |= _git_paths(root, ("ls-tree", "-r", "--name-only", "-z", "HEAD"), scope)
    untracked = _git_paths(root, ("ls-files", "-z", "--others", "--exclude-standard"), scope)
    authoring, missing_authoring = _authoring_inputs(root, tracked | untracked)
    status = _status(root, scope + tuple(sorted(authoring | missing_authoring)))
    native = _native_inputs(root, scope)
    imports: set[str] = set()
    if include_imports:
        if not _covered("app", scope):
            raise ValueError("prepared imports require app in the declared scope")
        imports = _walk_files(root, "app/.godot/imported")
        if not imports:
            raise ValueError("prepared import cache is absent or empty")
        for name in _CACHE_FILES:
            path = f"app/.godot/{name}"
            _file_stat(root / path)
            imports.add(path)
        gdignore = root / "app/.godot/.gdignore"
        _check_no_links(gdignore)
        if gdignore.exists():
            _file_stat(gdignore)
            imports.add("app/.godot/.gdignore")
    files = {}
    deleted = []
    for relative in sorted(tracked | untracked | native | imports | authoring):
        path = root / relative
        _check_no_links(path)
        try:
            metadata = _file_stat(path)
        except FileNotFoundError:
            if relative in tracked and relative not in untracked | native | imports | authoring:
                deleted.append(relative)
                continue
            raise ValueError(f"source disappeared during snapshot: {relative}") from None
        files[relative] = metadata
    return {"commit": commit, "status": status, "files": files, "deleted": deleted,
            "native": sorted(native), "imports": sorted(imports), "authoring": sorted(authoring),
            "missing_authoring": sorted(missing_authoring)}


def _same_inventory(before: dict, after: dict) -> bool:
    if any(before[key] != after[key] for key in ("commit", "status", "deleted", "native", "imports", "authoring", "missing_authoring")):
        return False
    if before["files"].keys() != after["files"].keys():
        return False
    return all(_signature(before["files"][key]) == _signature(after["files"][key]) for key in before["files"])


def _read_hash(path: Path, expected: os.stat_result, destination: Path | None = None) -> str:
    before = _file_stat(path)
    if _signature(before) != _signature(expected):
        raise ValueError(f"source changed during snapshot: {path}")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    digest = hashlib.sha256()
    try:
        with os.fdopen(os.open(path, flags), "rb") as source:
            if _signature(os.fstat(source.fileno())) != _signature(expected):
                raise ValueError(f"source changed during snapshot: {path}")
            if destination is None:
                for block in iter(lambda: source.read(_BLOCK), b""):
                    digest.update(block)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                _check_no_links(destination.parent)
                with destination.open("xb") as output:
                    for block in iter(lambda: source.read(_BLOCK), b""):
                        output.write(block)
                        digest.update(block)
            if _signature(os.fstat(source.fileno())) != _signature(expected):
                raise ValueError(f"source changed during snapshot: {path}")
    except FileNotFoundError as exc:
        raise ValueError(f"source disappeared during snapshot: {path}") from exc
    if _signature(_file_stat(path)) != _signature(expected):
        raise ValueError(f"source changed during snapshot: {path}")
    return digest.hexdigest()


def _set_metadata(path: Path, source: os.stat_result) -> None:
    os.utime(path, ns=(source.st_atime_ns, source.st_mtime_ns))
    os.chmod(path, stat.S_IMODE(source.st_mode))
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        setter = ctypes.WinDLL("kernel32", use_last_error=True).SetFileAttributesW
        setter.argtypes = (wintypes.LPCWSTR, wintypes.DWORD)
        setter.restype = wintypes.BOOL
        attrs = getattr(source, "st_file_attributes", 0) & _WINDOWS_RELEVANT
        if not setter(str(path), attrs or 0x80):
            raise ctypes.WinError(ctypes.get_last_error())


def _identity(manifest: dict) -> dict:
    return {key: manifest[key] for key in ("scope", "files", "deleted", "native_files", "import_files",
                                            "authoring_files", "missing_authoring_files")}


def capture(source: Path, destination: Path, *, scope: tuple[str, ...] = DEFAULT_SCOPE,
            include_imports: bool = False) -> dict:
    """Capture scoped worktree bytes into a new destination outside the checkout.

    Git history and ignored files are excluded, except installed app/native inputs,
    referenced aircraft authoring inputs and optionally the Godot import caches. Failed captures leave an
    incomplete directory for the owner to inspect or remove. Retrying requires a
    fresh destination. `include_imports` does not qualify cache compatibility.
    """
    root = Path(os.path.abspath(source))
    output = Path(os.path.abspath(destination))
    _check_no_links(root)
    _check_no_links(output)
    if not root.is_dir() or not output.parent.is_dir():
        raise ValueError("source and destination parent must be existing directories")
    if not isinstance(scope, tuple) or not scope or len(set(scope)) != len(scope):
        raise ValueError("scope must be a nonempty tuple of distinct relative paths")
    scope = tuple(_relative(item) for item in scope)
    if type(include_imports) is not bool:
        raise ValueError("include_imports must be boolean")
    try:
        inside = os.path.commonpath((str(root), str(output))) == str(root)
    except ValueError:
        inside = False
    if inside:
        raise ValueError("snapshot destination must be outside the source repository")
    git_root = Path(os.fsdecode(_git(root, "rev-parse", "--show-toplevel")).strip())
    if os.path.normcase(os.path.abspath(git_root)) != os.path.normcase(str(root)):
        raise ValueError("source must be the Git worktree root")
    before = _inventory(root, scope, include_imports)
    required = sum(metadata.st_size for metadata in before["files"].values())
    if shutil.disk_usage(output.parent).free < required + RESERVE_BYTES:
        raise ValueError(f"snapshot needs {required} bytes plus a {RESERVE_BYTES}-byte free reserve")
    output.mkdir()
    materialized = output / "source"
    materialized.mkdir()
    files = {}
    for relative, metadata in before["files"].items():
        target = materialized / relative
        checksum = _read_hash(root / relative, metadata, target)
        _set_metadata(target, metadata)
        copied = _file_stat(target)
        if (copied.st_size != metadata.st_size or stat.S_IMODE(copied.st_mode) != stat.S_IMODE(metadata.st_mode)
                or copied.st_mtime_ns != metadata.st_mtime_ns
                or (getattr(copied, "st_file_attributes", 0) & _WINDOWS_RELEVANT)
                != (getattr(metadata, "st_file_attributes", 0) & _WINDOWS_RELEVANT)):
            raise ValueError(f"cannot preserve source metadata: {relative}")
        files[relative] = {"sha256": checksum, "size": copied.st_size,
                           "mode": stat.S_IMODE(copied.st_mode), "mtime_ns": copied.st_mtime_ns,
                           "windows_attributes": getattr(copied, "st_file_attributes", None),
                           "source_windows_attributes": getattr(metadata, "st_file_attributes", None)}
    if not _same_inventory(before, _inventory(root, scope, include_imports)):
        raise ValueError("source changed during snapshot; retry in a fresh destination")
    # Verify every original file after all copies. Earlier files are not exempt.
    for relative, metadata in before["files"].items():
        if _read_hash(root / relative, metadata) != files[relative]["sha256"]:
            raise ValueError(f"source changed during snapshot: {relative}")
    if not _same_inventory(before, _inventory(root, scope, include_imports)):
        raise ValueError("source changed during snapshot; retry in a fresh destination")
    manifest = {
        "format": FORMAT, "source_root": str(root), "commit": before["commit"],
        "dirty": bool(before["status"]), "status": before["status"], "scope": list(scope),
        "files": files, "deleted": before["deleted"], "native_files": before["native"],
        "import_files": before["imports"], "authoring_files": before["authoring"],
        "missing_authoring_files": before["missing_authoring"], "history_included": False,
        "adapter_digests": {name: item["sha256"] for name, item in files.items() if name.startswith(_ADAPTERS)},
        "limitations": [
            "Per-file verified copy; not an atomic or semantically consistent multi-file snapshot.",
            "Git history is absent; history-dependent suites need a suitable checkout or bundle.",
            "Prepared caches are copied inputs, not proof of engine, platform or source compatibility.",
            "Each attempt requires an independent writable project, cache and runtime profile.",
            "Ignored files are excluded except installed native inputs, referenced aircraft authoring files and requested import caches; native ~*.tmp files are excluded.",
        ],
    }
    manifest["source_digest"] = _digest(_identity(manifest))
    manifest["manifest_digest"] = _digest(manifest)
    (output / "manifest.json").write_bytes(_canonical(manifest) + b"\n")
    report = verify(output)
    if not report["ok"]:
        raise ValueError(f"snapshot verification failed: {report['errors']}")
    return manifest


def verify(snapshot_dir: Path, *, canceled=None) -> dict:
    """Validate receipt, file hashes, metadata, links and unexpected materialized files."""
    errors = []
    manifest = None
    try:
        directory = Path(os.path.abspath(snapshot_dir))
        _check_no_links(directory)
        receipt = directory / "manifest.json"
        _file_stat(receipt)
        manifest = json.loads(receipt.read_text(encoding="utf-8"))
        if not isinstance(manifest, dict) or manifest.get("format") != FORMAT:
            raise ValueError("unsupported snapshot manifest")
        if manifest.get("manifest_digest") != _digest({key: value for key, value in manifest.items() if key != "manifest_digest"}):
            errors.append("manifest digest does not match")
        files = manifest.get("files")
        if not isinstance(files, dict):
            raise ValueError("invalid snapshot files")
        for name, item in files.items():
            _relative(name)
            if (not isinstance(item, dict) or not isinstance(item.get("sha256"), str)
                    or len(item["sha256"]) != 64 or any(c not in "0123456789abcdef" for c in item["sha256"])):
                raise ValueError(f"invalid file entry: {name}")
        if manifest.get("source_digest") != _digest(_identity(manifest)):
            errors.append("manifest source digest does not match")
        if manifest.get("adapter_digests") != {name: item["sha256"] for name, item in files.items() if name.startswith(_ADAPTERS)}:
            errors.append("adapter digests do not match manifest files")
        root = directory / "source"
        if not root.is_dir():
            raise ValueError("snapshot source directory is absent")
        actual = _walk_files(directory, "source")
        actual = {name[len("source/"):] for name in actual}
        for name in sorted(set(files) - actual):
            errors.append(f"missing file: {name}")
        for name in sorted(actual - set(files)):
            errors.append(f"unexpected file: {name}")
        for name in sorted(set(files) & actual):
            if canceled is not None and canceled():
                raise InterruptedError("snapshot verification canceled")
            path = root / name
            expected = files[name]
            metadata = _file_stat(path)
            if metadata.st_nlink != 1:
                errors.append(f"hard-linked file: {name}")
            if (metadata.st_size != expected.get("size") or stat.S_IMODE(metadata.st_mode) != expected.get("mode")
                    or metadata.st_mtime_ns != expected.get("mtime_ns")
                    or getattr(metadata, "st_file_attributes", None) != expected.get("windows_attributes")):
                errors.append(f"metadata mismatch: {name}")
            if _read_hash(path, metadata) != expected["sha256"]:
                errors.append(f"hash mismatch: {name}")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        errors.append(str(exc))
    return {"ok": not errors, "errors": errors,
            "source_digest": manifest.get("source_digest") if isinstance(manifest, dict) else None}
