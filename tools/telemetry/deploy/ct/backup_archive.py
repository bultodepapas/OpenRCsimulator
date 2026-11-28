"""TELEM-24c: daily consistent copy of the GitHub history archive (the only state that cannot be re-fetched
beyond GitHub's 14-day window). Keeps the newest 14 copies. Standard library only.

    python3 backup_archive.py <archive dir> <backup dir>
"""
from contextlib import closing
import os
from pathlib import Path
import sqlite3
import sys
import tempfile

if __package__:
    from ..host.openrc_stats_backup import backup_name, utc_day, validate_archive
else:
    sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
    from tools.telemetry.deploy.host.openrc_stats_backup import backup_name, utc_day, validate_archive

KEEP = 14


def main(archive, backups):
    source = Path(archive) / "github-history.sqlite3"
    if not source.is_file():
        print("GitHub archive missing; no backup created", file=sys.stderr)
        return 1
    backups = Path(backups)
    backups.mkdir(parents=True, exist_ok=True)
    day = utc_day()
    target = backups / backup_name(day)
    handle, tmp_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=backups)
    os.close(handle)
    tmp = Path(tmp_name)
    try:
        with closing(sqlite3.connect(f"{source.resolve().as_uri()}?mode=ro", uri=True)) as src, \
                closing(sqlite3.connect(tmp)) as dst:
            src.backup(dst)
        validate_archive(tmp, max_bytes=None)
        if utc_day() != day:
            raise ValueError("UTC date changed during backup")
        with tmp.open("r+b") as handle:
            os.fsync(handle.fileno())
        tmp.replace(target)
    finally:
        tmp.unlink(missing_ok=True)
    for old in sorted(backups.glob("github-history-*.sqlite3"))[:-KEEP]:
        old.unlink()
    print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
