"""TELEM-24c: daily consistent copy of the GitHub history archive (the only state that cannot be re-fetched
beyond GitHub's 14-day window). Keeps the newest 14 copies. Standard library only.

    python3 backup_archive.py <archive dir> <backup dir>
"""
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
import sys

KEEP = 14


def main(archive, backups):
    source = Path(archive) / "github-history.sqlite3"
    if not source.is_file():
        print("no archive yet")
        return 0
    backups = Path(backups)
    backups.mkdir(parents=True, exist_ok=True)
    target = backups / f"github-history-{datetime.now(timezone.utc):%Y-%m-%d}.sqlite3"
    tmp = target.with_suffix(".tmp")
    with sqlite3.connect(f"file:{source}?mode=ro", uri=True) as src, sqlite3.connect(tmp) as dst:
        src.backup(dst)
    tmp.replace(target)
    for old in sorted(backups.glob("github-history-*.sqlite3"))[:-KEEP]:
        old.unlink()
    print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
