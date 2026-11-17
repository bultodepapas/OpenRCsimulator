"""Reclaim the writable source copy of finished, passing local attempts.

Each local attempt materializes a full writable copy of the frozen source
(about 3 GB here) that is never read again once the attempt has finished.
This removes only ``<attempt>/source`` for attempts whose durable record is
FINISHED with outcome PASSED, evidence COMPLETE and cleanup CONFIRMED, and
that hold no claim. Verdicts, logs, reports, imports, profiles, temp and
failed, incomplete or UNKNOWN attempts are kept for inspection.

The store is opened read-only; the worker never revisits a finished attempt.
Deletion never follows a symbolic link, junction or other reparse point: the
link itself is removed and its target is left untouched.

    python tools/testqueue/local_gc.py            # dry run
    python tools/testqueue/local_gc.py --execute
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sqlite3
import stat
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import state_root

_REPARSE = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)


def _is_link(info) -> bool:
    return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & _REPARSE)


def safe_remove_tree(path: Path) -> int:
    """Delete ``path`` bottom-up without traversing any link or reparse point."""
    removed = 0
    info = os.lstat(path)
    if _is_link(info):
        (os.rmdir if stat.S_ISDIR(info.st_mode) else os.unlink)(path)
        return 0
    if not stat.S_ISDIR(info.st_mode):
        size = info.st_size
        os.chmod(path, stat.S_IWRITE)
        os.unlink(path)
        return size
    with os.scandir(path) as entries:
        children = list(entries)
    for entry in children:
        removed += safe_remove_tree(Path(entry.path))
    os.rmdir(path)
    return removed


def candidates(root: Path):
    database = sqlite3.connect(f"file:{(root / 'queue.sqlite3').as_posix()}?mode=ro", uri=True)
    try:
        claimed = {row[0] for row in database.execute("SELECT attempt FROM claims")}
        rows = database.execute("SELECT attempts.id, attempts.state, attempts.data, jobs.state FROM attempts "
                                "JOIN jobs ON jobs.id = attempts.job").fetchall()
    finally:
        database.close()
    for attempt, attempt_state, data, job_state in rows:
        try:
            data = json.loads(data)
        except ValueError:
            continue
        if (attempt_state, job_state) != ("FINISHED", "FINISHED") or attempt in claimed:
            continue
        if (data.get("outcome"), data.get("evidence"), data.get("cleanup")) != ("PASSED", "COMPLETE", "CONFIRMED"):
            continue
        source = root / "attempts" / attempt / "source"
        if source.exists() or source.is_symlink():
            yield attempt, source


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args(argv)
    root = (args.root or state_root()).resolve()
    found = list(candidates(root))
    report = {"root": str(root), "candidates": len(found), "execute": args.execute}
    if args.execute:
        removed, errors = 0, []
        for attempt, source in found:
            try:
                removed += safe_remove_tree(source)
            except OSError as error:
                errors.append({"attempt": attempt, "error": str(error)[:200]})
        report.update(logical_bytes_removed=removed, errors=errors)
    print(json.dumps(report, indent=2))
    return 0 if not report.get("errors") else 1


if __name__ == "__main__":
    raise SystemExit(main())
