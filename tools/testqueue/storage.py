"""Bounded local storage inventory and non-binding capacity estimates."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PureWindowsPath
import shutil
import stat
import sys
from typing import Sequence

from tools.godot import storage_audit

MAX_ROOTS = 4
MAX_ENTRIES = 100_000
MAX_SECONDS = 30.0
MAX_BYTES = (1 << 63) - 1


def _directory(path: Path) -> Path:
    """Refuse links/reparse points in every existing path component."""
    expanded = Path(os.path.expanduser(os.fspath(path)))
    if ".." in expanded.parts:
        raise ValueError("paths must not contain '..' components")
    absolute = Path(os.path.abspath(expanded))
    # UNC and mapped network drives are not local. Other remote mounts cannot
    # be reliably identified portably; operators must select local directories.
    if os.name == "nt":
        if absolute.drive.startswith("\\\\"):
            raise ValueError("UNC paths are not local roots")
        import ctypes
        get_drive_type = ctypes.windll.kernel32.GetDriveTypeW
        get_drive_type.argtypes = [ctypes.c_wchar_p]
        get_drive_type.restype = ctypes.c_uint
        if get_drive_type(absolute.anchor) in (0, 1, 4):
            raise ValueError("drive is remote or its type is unavailable")
    current = Path(absolute.anchor)
    for part in (None, *absolute.parts[1:]):
        if part is not None:
            current /= part
        info = current.lstat()
        if stat.S_ISLNK(info.st_mode) or storage_audit._is_reparse_point(info):
            raise ValueError(f"symlink/junction/reparse path component refused: {current}")
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError(f"path component is not a directory: {current}")
    return absolute


def _roots(paths: Sequence[Path]) -> list[Path]:
    if not 1 <= len(paths) <= MAX_ROOTS:
        raise ValueError(f"select between 1 and {MAX_ROOTS} roots")
    roots = [_directory(path) for path in paths]
    for root in roots:
        if any(part.casefold() == ".git" for part in root.parts):
            raise ValueError("inventory roots must not be inside a .git directory")
    for index, root in enumerate(roots):
        for previous in roots[:index]:
            try:
                common = os.path.normcase(os.path.commonpath((root, previous)))
            except ValueError:  # Different Windows drives.
                common = ""
            if common in (os.path.normcase(str(root)), os.path.normcase(str(previous))):
                raise ValueError("inventory roots must not duplicate or overlap one another")
            # Also detect a root or ancestor reachable by a second mount path.
            if (any(os.path.samefile(previous, parent) for parent in (root, *root.parents))
                    or any(os.path.samefile(root, parent) for parent in (previous, *previous.parents))):
                raise ValueError("inventory roots must not duplicate or overlap one another")
    return roots


def _validate_windows_output_path(path: str) -> None:
    """Refuse alternate streams and device names in every non-drive part."""
    windows_path = PureWindowsPath(path)
    for part in windows_path.parts:
        if part != windows_path.anchor and (":" in part or PureWindowsPath(part).is_reserved()):
            raise ValueError("Windows output path contains a data stream or reserved device name")


def _output_path(path: Path) -> Path:
    if ".." in path.parts:
        raise ValueError("paths must not contain '..' components")
    path = Path(os.path.abspath(os.path.expanduser(os.fspath(path))))
    if os.name == "nt":
        _validate_windows_output_path(os.fspath(path))
    _directory(path.parent)  # Never create parent directories.
    try:
        path.lstat()
    except FileNotFoundError:
        return path
    raise FileExistsError(f"output must be a new path: {path}")


def _write_report(path: Path, payload: str) -> None:
    """Exclusively create the final file; pin parents where dir_fd is supported."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    flags |= getattr(os, "O_BINARY", 0)
    if (os.open in os.supports_dir_fd and hasattr(os, "O_DIRECTORY")
            and hasattr(os, "O_NOFOLLOW")):
        directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        current_fd = os.open(path.anchor, directory_flags)
        try:
            for part in path.parent.parts[1:]:
                next_fd = os.open(part, directory_flags, dir_fd=current_fd)
                os.close(current_fd)
                current_fd = next_fd
            descriptor = os.open(path.name, flags, 0o600, dir_fd=current_fd)
        finally:
            os.close(current_fd)
    else:
        # Windows has no portable dir_fd traversal; recheck immediately before
        # exclusive creation. Concurrent path replacement remains a limitation.
        _directory(path.parent)
        descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        stream.write(payload)


def _nonnegative_bytes(value: str) -> int:
    if not value.isascii() or not value.isdecimal():
        raise argparse.ArgumentTypeError("bytes must be a nonnegative decimal integer")
    try:
        number = int(value)
    except (TypeError, ValueError) as error:
        raise argparse.ArgumentTypeError("bytes must be a nonnegative integer") from error
    if not 0 <= number <= MAX_BYTES:
        raise argparse.ArgumentTypeError(f"bytes must be between 0 and {MAX_BYTES}")
    return number


def inventory(roots: Sequence[Path], *, top: int = 20, max_entries: int = 25_000,
              max_seconds: float = 5.0, max_depth: int = 128,
              excludes: Sequence[str] = ()) -> dict:
    """Scan independently; no logical-size or volume totals are combined."""
    storage_audit._validate_limits(top, max_entries, max_seconds, max_depth)
    if max_entries > MAX_ENTRIES or max_seconds > MAX_SECONDS:
        raise ValueError(f"per-root limits are at most {MAX_ENTRIES} entries and {MAX_SECONDS:g} seconds")
    storage_audit._normalize_excludes(excludes)
    selected = _roots(roots)
    audits = []
    for root in selected:
        try:
            audit = storage_audit.scan_storage(root, top=top, max_entries=max_entries,
                                              max_seconds=max_seconds, max_depth=max_depth,
                                              excludes=excludes)
        except (storage_audit.AuditConfigurationError, OSError, RuntimeError) as error:
            # Root and options were validated before any scan. Retain completed
            # roots if a later root disappears or changes while scanning.
            audit = {"format": "openrc-testqueue-storage-root-unavailable v1", "root": str(root),
                     "complete": False, "status": "unavailable",
                     "partial_reasons": ["root_unavailable_after_validation"],
                     "error": f"{type(error).__name__}: {error}"[:storage_audit.MAX_ERROR_TEXT]}
        audits.append(audit)
    complete = all(audit["complete"] for audit in audits)
    return {
        "format": "openrc-testqueue-storage-inventory v1",
        "complete": complete,
        "status": "complete" if complete else "partial",
        "max_roots": MAX_ROOTS,
        "bounds": "entry, time and depth limits apply per root; total cooperative scan time can reach root count times max_seconds",
        "scope": "logical bytes cover only scanned regular-file paths; case-insensitive .git components, observed links and configured prefixes are skipped subject to the consistency caveat. Incomplete scans omit more. These bytes are not physical volume usage.",
        "capacity": "each root's volume free space is independent of scanned logical bytes; volumes are not summed",
        "lifecycle": "not assessed; no path is classified as safe to delete",
        "consistency": "non-atomic observation; path checks are best-effort, concurrent replacements can still follow links, and remote mounts cannot always be detected; use stable local directories",
        "roots": audits,
    }


def budget(root: Path, *, peak_bytes: int, reserved_bytes: int, floor_bytes: int) -> dict:
    """Compare explicit future demand to one volume's observed free space."""
    for value in (peak_bytes, reserved_bytes, floor_bytes):
        if type(value) is not int or not 0 <= value <= MAX_BYTES:
            raise ValueError(f"budget values must be integers between 0 and {MAX_BYTES}")
    selected = _directory(root)
    report = {
        "format": "openrc-testqueue-storage-budget v1",
        "root": str(selected),
        "observed_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "peak_bytes": peak_bytes,
        "reserved_bytes": reserved_bytes,
        "free_space_floor_bytes": floor_bytes,
        "volume_free_bytes": None,
        "headroom_after_reservations_and_floor_bytes": None,
        "assessment": "indeterminate",
        "scope": "snapshot only; reservations are caller-supplied future demand and must not include bytes already reflected in volume use",
        "consistency": "non-atomic diagnostic, not admission, a reservation, enforcement or a guarantee of future space; path checks are best-effort and remote mounts cannot always be detected; use a stable local directory",
    }
    try:
        free = shutil.disk_usage(selected).free
        if type(free) is not int or free < 0:
            raise ValueError("invalid free space")
    except (OSError, ValueError, RuntimeError, OverflowError):
        report["reason"] = "volume free space unavailable"
        return report
    headroom = free - reserved_bytes - floor_bytes
    report.update(volume_free_bytes=free,
                  headroom_after_reservations_and_floor_bytes=headroom,
                  assessment="observed_fit" if peak_bytes <= headroom else "insufficient")
    return report


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    sub = parser.add_subparsers(dest="mode", required=True)
    scan = sub.add_parser("inventory", allow_abbrev=False, help="scan explicitly selected roots without reading file contents")
    scan.add_argument("--root", action="append", required=True, type=Path, help="existing local directory; repeat up to four times")
    scan.add_argument("--top", type=int, default=20, help="largest files per root (1..100)")
    scan.add_argument("--max-entries", type=int, default=25_000, help="per-root entry limit (1..100000)")
    scan.add_argument("--max-seconds", type=float, default=5.0, help="per-root cooperative limit (0..30]")
    scan.add_argument("--max-depth", type=int, default=128, help="per-root maximum directory depth (1..1024)")
    scan.add_argument("--exclude", action="append", default=[], metavar="PREFIX", help="root-relative prefix; repeatable")
    estimate = sub.add_parser("budget", allow_abbrev=False, help="compare explicit demand with observed free space")
    estimate.add_argument("--root", required=True, type=Path, help="existing local directory on the volume")
    estimate.add_argument("--peak-bytes", required=True, type=_nonnegative_bytes)
    estimate.add_argument("--reserved-bytes", required=True, type=_nonnegative_bytes, help="existing future commitments not already reflected in free space")
    estimate.add_argument("--floor-bytes", required=True, type=_nonnegative_bytes)
    for command in (scan, estimate):
        command.add_argument("--out", type=Path, help="optional new JSON file; parent must exist")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        out = _output_path(args.out) if args.out is not None else None
        if args.mode == "inventory":
            report = inventory(args.root, top=args.top, max_entries=args.max_entries,
                               max_seconds=args.max_seconds, max_depth=args.max_depth,
                               excludes=args.exclude)
            code = 0 if report["complete"] else 1
        else:
            report = budget(args.root, peak_bytes=args.peak_bytes,
                            reserved_bytes=args.reserved_bytes, floor_bytes=args.floor_bytes)
            code = {"observed_fit": 0, "insufficient": 1, "indeterminate": 2}[report["assessment"]]
        payload = json.dumps(report, sort_keys=True, indent=2, ensure_ascii=True, allow_nan=False) + "\n"
        if out is None:
            sys.stdout.write(payload)
        else:
            _write_report(out, payload)
        return code
    except (OSError, ValueError, RuntimeError, OverflowError) as error:
        print(f"testctl storage: {error}", file=sys.stderr)
        return 2
