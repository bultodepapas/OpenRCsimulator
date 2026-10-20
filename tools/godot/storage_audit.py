#!/usr/bin/env python3
"""Bounded read-only inventory of logical file storage and volume capacity."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path, PureWindowsPath
import shutil
import stat
import sys
import time
from typing import Any, Sequence


FORMAT = "openrc-storage-audit v1"
DEFAULT_TOP = 20
MAX_TOP = 100
DEFAULT_MAX_ENTRIES = 100_000
MAX_ENTRIES = 1_000_000
DEFAULT_MAX_SECONDS = 10.0
MAX_SECONDS = 300.0
DEFAULT_MAX_DEPTH = 128
MAX_DEPTH = 1024
MAX_EXCLUDES = 100
MAX_EXCLUDE_LENGTH = 4096
MAX_ERROR_SAMPLES = 20
MAX_ERROR_TEXT = 300
DEFAULT_EXCLUDES = (".git",)
REPARSE_POINT_FLAG = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x0400)

CATEGORY_NAMES = (
    "app/.godot cache",
    "app/assets",
    ".godot cache",
    "assets",
    "tmp/logs",
    "tmp",
    "logs",
    "research",
    "app/other",
    "other",
)


class AuditConfigurationError(ValueError):
    """Invalid root or finite scan option."""


def _positive_integer(value: int, label: str, maximum: int) -> int:
    if type(value) is not int or not 1 <= value <= maximum:
        raise AuditConfigurationError(f"{label} must be an integer from 1 to {maximum}")
    return value


def _validate_limits(top: int, max_entries: int, max_seconds: float, max_depth: int) -> None:
    _positive_integer(top, "top", MAX_TOP)
    _positive_integer(max_entries, "max_entries", MAX_ENTRIES)
    _positive_integer(max_depth, "max_depth", MAX_DEPTH)
    try:
        finite_seconds = type(max_seconds) in (int, float) and math.isfinite(float(max_seconds))
    except (OverflowError, TypeError, ValueError):
        finite_seconds = False
    if not finite_seconds or not 0.0 < max_seconds <= MAX_SECONDS:
        raise AuditConfigurationError(f"max_seconds must be finite and in (0, {MAX_SECONDS:g}]")


def normalize_exclude_prefix(raw: str) -> str:
    """Normalize one root-relative prefix and reject rooted or escaping paths."""
    if not isinstance(raw, str) or not raw or len(raw) > MAX_EXCLUDE_LENGTH:
        raise AuditConfigurationError(f"exclude prefix must contain 1..{MAX_EXCLUDE_LENGTH} characters")
    normalized = raw.replace("\\", "/")
    windows_path = PureWindowsPath(raw)
    if normalized.startswith("/") or windows_path.drive or windows_path.root:
        raise AuditConfigurationError(f"exclude prefix must be root-relative: {raw!r}")
    parts = [part for part in normalized.split("/") if part not in ("", ".")]
    if not parts or any(part == ".." for part in parts):
        raise AuditConfigurationError(f"exclude prefix must not be empty or escape the root: {raw!r}")
    return "/".join(parts)


def _normalize_excludes(excludes: Sequence[str] | None) -> list[str]:
    user_excludes = list(excludes or ())
    if len(user_excludes) > MAX_EXCLUDES:
        raise AuditConfigurationError(f"at most {MAX_EXCLUDES} --exclude prefixes are allowed")
    normalized = list(DEFAULT_EXCLUDES)
    for raw in user_excludes:
        prefix = normalize_exclude_prefix(raw)
        if prefix not in normalized:
            normalized.append(prefix)
    return normalized


def _prefix_matches(relative: str, prefix: str) -> bool:
    if os.name == "nt":
        relative = os.path.normcase(relative)
        prefix = os.path.normcase(prefix)
    if prefix == ".git":
        return ".git" in relative.split("/")
    return relative == prefix or relative.startswith(prefix + "/")


def _excluded(relative: str, prefixes: Sequence[str]) -> bool:
    return any(_prefix_matches(relative, prefix) for prefix in prefixes)


def _category(relative: str) -> str:
    parts = relative.split("/") if relative else []
    if len(parts) >= 2 and parts[:2] == ["app", ".godot"]:
        return "app/.godot cache"
    if parts and parts[0] == ".godot":
        return ".godot cache"
    if len(parts) >= 2 and parts[:2] == ["app", "assets"]:
        return "app/assets"
    if parts and parts[0] == "assets":
        return "assets"
    if len(parts) >= 2 and parts[:2] == ["tmp", "logs"]:
        return "tmp/logs"
    if parts and parts[0] == "tmp":
        return "tmp"
    if parts and parts[0] == "logs":
        return "logs"
    if parts and parts[0] == "research":
        return "research"
    if parts and parts[0] == "app":
        return "app/other"
    return "other"


def _is_reparse_point(file_stat: os.stat_result) -> bool:
    return bool(getattr(file_stat, "st_file_attributes", 0) & REPARSE_POINT_FLAG)


def _validate_root(root: Path) -> Path:
    try:
        absolute = Path(os.path.abspath(os.path.expanduser(os.fspath(root))))
        root_stat = absolute.lstat()
    except (OSError, RuntimeError, ValueError) as error:
        raise AuditConfigurationError(f"root is unavailable: {error}") from error
    if stat.S_ISLNK(root_stat.st_mode) or _is_reparse_point(root_stat):
        raise AuditConfigurationError("root itself is a symlink/junction/reparse point; choose its real directory")
    if not stat.S_ISDIR(root_stat.st_mode):
        raise AuditConfigurationError("root must be an existing directory")
    return absolute


def _category_totals() -> dict[str, dict[str, int]]:
    return {name: {"file_count": 0, "directory_count": 0, "logical_file_bytes": 0}
            for name in CATEGORY_NAMES}


def _retain_largest_file(largest_files: list[tuple[int, str, str]],
                         entry: tuple[int, str, str], top: int) -> None:
    """Keep a deterministically ranked, bounded list (largest bytes, then path)."""
    largest_files.append(entry)
    largest_files.sort(key=lambda item: (-item[0], item[1]))
    if len(largest_files) > top:
        del largest_files[top:]


def _root_report_path(root: Path) -> str:
    return str(root)


def scan_storage(root: Path, *, top: int = DEFAULT_TOP, max_entries: int = DEFAULT_MAX_ENTRIES,
                 max_seconds: float = DEFAULT_MAX_SECONDS, max_depth: int = DEFAULT_MAX_DEPTH,
                 excludes: Sequence[str] | None = None) -> dict[str, Any]:
    """Scan regular-file metadata only; never read file contents or follow links."""
    _validate_limits(top, max_entries, max_seconds, max_depth)
    root = _validate_root(Path(root))
    excluded_prefixes = _normalize_excludes(excludes)
    started_monotonic = time.monotonic()
    started_utc = datetime.now(timezone.utc).isoformat(timespec="seconds")
    deadline = started_monotonic + float(max_seconds)

    entries_encountered = 0
    entries_stat_attempted = 0
    file_count = 0
    directory_count = 0
    logical_file_bytes = 0
    excluded_entries = 0
    symlink_entries_skipped = 0
    reparse_entries_skipped = 0
    special_entries_skipped = 0
    errors_count = 0
    error_samples: list[dict[str, str]] = []
    partial_reasons: list[str] = []
    categories = _category_totals()
    largest_files: list[tuple[int, str, str]] = []

    def partial(reason: str) -> None:
        if reason not in partial_reasons:
            partial_reasons.append(reason)

    def filesystem_error(phase: str, relative: str, error: BaseException) -> None:
        nonlocal errors_count
        errors_count += 1
        partial("filesystem_error")
        if len(error_samples) < MAX_ERROR_SAMPLES:
            message = f"{type(error).__name__}: {error}"[:MAX_ERROR_TEXT]
            error_samples.append({"phase": phase, "path": relative, "message": message})

    def close_iterator(iterator: Any, relative: str) -> None:
        try:
            iterator.close()
        except OSError as error:
            filesystem_error("close", relative, error)

    def add_file(relative: str, size: int) -> None:
        nonlocal file_count, logical_file_bytes
        file_count += 1
        logical_file_bytes += size
        bucket = categories[_category(relative)]
        bucket["file_count"] += 1
        bucket["logical_file_bytes"] += size
        entry = (size, relative, _category(relative))
        _retain_largest_file(largest_files, entry, top)

    def add_directory(relative: str) -> None:
        nonlocal directory_count
        directory_count += 1
        categories[_category(relative)]["directory_count"] += 1

    try:
        usage = shutil.disk_usage(root)
        volume_capacity: dict[str, Any] = {
            "available": True,
            "total_bytes": usage.total,
            "used_bytes": usage.used,
            "free_bytes": usage.free,
            "meaning": "filesystem volume capacity; separate from logical_file_bytes scanned under root",
        }
    except (OSError, PermissionError, RuntimeError) as error:
        volume_capacity = {"available": False, "total_bytes": None, "used_bytes": None,
                           "free_bytes": None, "meaning": "filesystem capacity query failed"}
        filesystem_error("volume_capacity", "", error)

    stack: list[tuple[Path, str, Any, int]] = []
    try:
        try:
            stack.append((root, "", os.scandir(root), 0))
        except OSError as error:
            filesystem_error("scandir", "", error)

        while stack:
            if time.monotonic() >= deadline:
                partial("elapsed_time_limit")
                break
            if entries_encountered >= max_entries:
                partial("entry_limit")
                break

            directory, relative_directory, iterator, depth = stack[-1]
            try:
                entry = next(iterator)
            except StopIteration:
                close_iterator(iterator, relative_directory)
                stack.pop()
                continue
            except OSError as error:
                filesystem_error("scandir", relative_directory, error)
                close_iterator(iterator, relative_directory)
                stack.pop()
                continue

            entries_encountered += 1
            relative = f"{relative_directory}/{entry.name}" if relative_directory else entry.name
            if time.monotonic() >= deadline:
                partial("elapsed_time_limit")
                break
            if _excluded(relative, excluded_prefixes):
                excluded_entries += 1
                if entries_encountered >= max_entries:
                    partial("entry_limit")
                    break
                continue

            try:
                entries_stat_attempted += 1
                info = entry.stat(follow_symlinks=False)
            except OSError as error:
                filesystem_error("stat", relative, error)
                if entries_encountered >= max_entries:
                    partial("entry_limit")
                    break
                continue

            if stat.S_ISLNK(info.st_mode):
                symlink_entries_skipped += 1
            elif _is_reparse_point(info):
                reparse_entries_skipped += 1
            elif stat.S_ISDIR(info.st_mode):
                add_directory(relative)
                child_depth = depth + 1
                if child_depth > max_depth:
                    partial("depth_limit")
                elif entries_encountered >= max_entries:
                    partial("entry_limit")
                else:
                    try:
                        stack.append((Path(entry.path), relative, os.scandir(entry.path), child_depth))
                    except OSError as error:
                        filesystem_error("scandir", relative, error)
            elif stat.S_ISREG(info.st_mode):
                size = info.st_size
                if type(size) is not int or size < 0:
                    filesystem_error("stat", relative, ValueError("regular file has invalid st_size"))
                else:
                    add_file(relative, size)
            else:
                special_entries_skipped += 1

            if entries_encountered >= max_entries:
                partial("entry_limit")
                break
    finally:
        for _directory, relative, iterator, _depth in reversed(stack):
            close_iterator(iterator, relative)

    elapsed = max(0.0, time.monotonic() - started_monotonic)
    is_complete = not partial_reasons
    categories_sorted = [
        {"category": name, **values}
        for name, values in sorted(categories.items(), key=lambda item: (-item[1]["logical_file_bytes"], item[0]))
    ]
    top_files = [
        {"path": relative, "logical_bytes": size, "category": category}
        for size, relative, category in sorted(largest_files, key=lambda item: (-item[0], item[1]))
    ]
    return {
        "format": FORMAT,
        "version": 1,
        "complete": is_complete,
        "status": "complete" if is_complete else "partial",
        "partial_reasons": partial_reasons,
        "started_utc": started_utc,
        "root": _root_report_path(root),
        "scan_limits": {
            "top": top,
            "max_entries": max_entries,
            "max_seconds": float(max_seconds),
            "max_depth": max_depth,
        },
        "scan": {
            "elapsed_seconds": round(elapsed, 6),
            "entries_encountered": entries_encountered,
            "entries_stat_attempted": entries_stat_attempted,
            "file_count": file_count,
            "directory_count": directory_count,
            "logical_file_bytes": logical_file_bytes,
            "excluded_entries": excluded_entries,
            "symlink_entries_skipped": symlink_entries_skipped,
            "reparse_entries_skipped": reparse_entries_skipped,
            "special_entries_skipped": special_entries_skipped,
        },
        "scope": {
            "logical_file_bytes": "sum of st_size for scanned regular-file paths only; hard links count once per path and may be double-counted",
            "volume_capacity": "shutil.disk_usage(root), shown separately from the scanned logical bytes",
            "links": "symbolic links and Windows reparse points are not traversed or included as regular-file bytes",
            "contents": "file contents are never opened or read",
            "output": "the new report is written after the scan and is not included in its own totals",
            "excludes": ".git path components are skipped anywhere by default; extra prefixes are root-relative and component-boundary matched",
            "directory_count": "counts encountered directories below root; root itself is excluded",
        },
        "excluded_prefixes": excluded_prefixes,
        "volume_capacity": volume_capacity,
        "categories": categories_sorted,
        "largest_files": top_files,
        "filesystem_errors": {"count": errors_count, "samples": error_samples,
                               "samples_omitted": max(0, errors_count - len(error_samples))},
    }


def write_new_report(path: Path, report: dict[str, Any]) -> None:
    """Create a JSON report exclusively; never replace an existing file or link."""
    path = Path(path)
    if path.exists() or path.is_symlink():
        raise FileExistsError(f"output must be a new path: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(report, ensure_ascii=True, indent=2, sort_keys=True, allow_nan=False) + "\n"
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(payload)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="existing directory to scan")
    parser.add_argument("--out", type=Path, required=True, help="new JSON report path; existing files/links are refused")
    parser.add_argument("--top", type=int, default=DEFAULT_TOP, help=f"largest files to report (1..{MAX_TOP}, default {DEFAULT_TOP})")
    parser.add_argument("--max-entries", type=int, default=DEFAULT_MAX_ENTRIES,
                        help=f"maximum directory entries encountered (1..{MAX_ENTRIES})")
    parser.add_argument("--max-seconds", type=float, default=DEFAULT_MAX_SECONDS,
                        help=f"cooperative scan deadline in seconds (0..{MAX_SECONDS:g}] (default {DEFAULT_MAX_SECONDS:g})")
    parser.add_argument("--max-depth", type=int, default=DEFAULT_MAX_DEPTH,
                        help=f"maximum traversed directory depth (1..{MAX_DEPTH}, default {DEFAULT_MAX_DEPTH})")
    parser.add_argument("--exclude", action="append", default=[], metavar="PREFIX",
                        help="root-relative path prefix to skip; repeatable; .git components are excluded by default")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except (AttributeError, OSError, ValueError):
            pass
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        report = scan_storage(args.root, top=args.top, max_entries=args.max_entries,
                              max_seconds=args.max_seconds, max_depth=args.max_depth,
                              excludes=args.exclude)
        write_new_report(args.out, report)
    except (AuditConfigurationError, OSError, ValueError, RuntimeError, OverflowError, TypeError) as error:
        print(f"storage audit configuration/output error: {error}", file=sys.stderr)
        return 2

    scan = report["scan"]
    print(f"storage audit: {report['status']}; {scan['file_count']} files, "
          f"{scan['logical_file_bytes']} logical bytes; {scan['entries_encountered']} entries; "
          f"report {args.out}")
    volume = report["volume_capacity"]
    if volume["available"]:
        free_percent = 100.0 * volume['free_bytes'] / volume['total_bytes'] if volume['total_bytes'] else 0.0
        print(f"  volume free: {volume['free_bytes'] / 1073741824:.2f} GiB ({free_percent:.1f}%); "
              f"total {volume['total_bytes']} bytes, "
              f"used {volume['used_bytes']}, free {volume['free_bytes']} (separate filesystem measure)")
    for rank, item in enumerate(report["largest_files"][:min(args.top, 5)], start=1):
        size = item["logical_bytes"]
        mib = size / (1024 * 1024)
        print(f"  largest {rank}: {item['path']} - {mib:.2f} MiB ({size} bytes)")
    for category in report["categories"]:
        if category["logical_file_bytes"]:
            print(f"  {category['category']}: {category['logical_file_bytes']} bytes in {category['file_count']} files")
    for item in report["filesystem_errors"]["samples"][:3]:
        print(f"  filesystem {item['phase']} {item['path']}: {item['message']}", file=sys.stderr)
    if report["partial_reasons"]:
        for reason in report["partial_reasons"]:
            print(f"  partial: {reason}", file=sys.stderr)
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
