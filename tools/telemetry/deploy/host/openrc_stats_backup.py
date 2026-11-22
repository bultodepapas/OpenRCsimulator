"""Stage and pull the operator-only GitHub SQLite backup between OpenRC Stats hosts."""
from contextlib import closing
from datetime import datetime, timezone
import argparse
import ipaddress
import os
from pathlib import Path
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile


if __package__ == "tools.telemetry.deploy.host":
    from ... import github_archive
else:
    # The installed host script sits alongside telemetry/ and analytics/.
    directory = Path(__file__).resolve().parent
    reader = directory / "telemetry"
    if not (reader / "github_archive.py").is_file():
        reader = directory.parents[1]
    sys.path.insert(0, str(reader))
    import github_archive


EXPORT_DIR = Path("/var/lib/openrc-stats-backup-export")
PULL_DIR = Path("/var/lib/openrc-stats-backup")
CT_BACKUP_DIR = "/var/lib/openrc-stats/backups"
BACKUP_NAME = re.compile(r"github-history-\d{4}-\d{2}-\d{2}\.sqlite3", re.ASCII)
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024


def utc_day() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def backup_name(day: str) -> str:
    return f"github-history-{day}.sqlite3"


def validate_archive(path: Path, *, max_bytes=MAX_ARCHIVE_BYTES) -> None:
    size = path.stat().st_size
    if size <= 0 or (max_bytes is not None and size > max_bytes):
        raise ValueError("archive size is outside the allowed range")
    with closing(sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro&immutable=1", uri=True)) as db:
        db.execute("PRAGMA trusted_schema = OFF")
        if db.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise ValueError("archive failed SQLite quick_check")
        version = db.execute("PRAGMA user_version").fetchone()[0]
        history = github_archive.github_history
        if version not in history.READABLE_VERSIONS:
            raise ValueError("unknown GitHub archive schema version")
        # A restored archive must also accept new collector writes. The collector uses positional inserts.
        required = {"settings": "repo asset_glob", "attempts": "id kind started_utc finished_utc success",
                    "observations": "id kind started_utc finished_utc",
                    "asset_counts": "observation_id asset_id release_id tag name count started_utc finished_utc",
                    "traffic_days": "day_utc views uniques status started_utc finished_utc"}
        if version >= 2:
            required.update(clone_days="day_utc views uniques status started_utc finished_utc",
                            repo_counters="observation_id stars forks watchers open_issues",
                            popular_referrers="observation_id referrer count uniques",
                            popular_paths="observation_id path title count uniques",
                            releases="tag published_utc prerelease", star_days="day_utc stars")
        tables = {name for (name,) in db.execute("SELECT name FROM sqlite_schema WHERE type = 'table'")}
        for table, fields in required.items():
            if table not in tables:
                raise ValueError(f"missing GitHub archive table: {table}")
            columns = [row[1] for row in db.execute(f"PRAGMA table_info({table})")]
            if columns != fields.split():
                raise ValueError(f"incomplete GitHub archive table: {table}")
        if db.execute("SELECT repo, asset_glob FROM settings LIMIT 2").fetchall() != [
                (history.DEFAULT_REPO, history.DEFAULT_ASSET_GLOB)]:
            raise ValueError("unexpected GitHub archive repository or asset pattern")
        if db.execute("SELECT 1 FROM observations LIMIT 1").fetchone() is None:
            raise ValueError("GitHub archive has no observations")
        if db.execute("PRAGMA foreign_key_check").fetchone() is not None:
            raise ValueError("GitHub archive contains missing references")
    # Use the same queries and data interpretation as the dashboard on this closed copy.
    try:
        github_archive.load_path(path, immutable=True)
    except (TypeError, AttributeError, OverflowError) as error:
        raise ValueError("invalid data in GitHub archive") from error


def store_archive(command: list[str], directory: Path, day: str, *, mode: int, keep: int) -> Path:
    name = backup_name(day)
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(dir=directory, prefix=f".{name}.", delete=False) as handle:
            tmp = Path(handle.name)
            subprocess.run(command, stdin=subprocess.DEVNULL, stdout=handle, check=True, timeout=60)
            handle.flush()
            os.fsync(handle.fileno())
        validate_archive(tmp)
        if utc_day() != day:
            raise ValueError("UTC date changed during transfer")
        tmp.chmod(mode)
        target = tmp.replace(directory / name)
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)

    copies = sorted(path for path in directory.iterdir() if BACKUP_NAME.fullmatch(path.name) and path.is_file())
    for old in copies[:-keep]:
        old.unlink()
    if os.name == "posix":
        directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    return target


def export_archive() -> Path:
    day = utc_day()
    command = ["/usr/sbin/pct", "exec", "406", "--", "/usr/bin/cat", "--",
               f"{CT_BACKUP_DIR}/{backup_name(day)}"]
    return store_archive(command, EXPORT_DIR, day, mode=0o640, keep=1)


def serve_archive(output) -> None:
    # The dedicated key has a forced command. Reject shell arguments even if the client supplied them.
    if os.environ.get("SSH_ORIGINAL_COMMAND"):
        raise ValueError("this key accepts an archive transfer only")
    path = EXPORT_DIR / backup_name(utc_day())
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    with os.fdopen(fd, "rb") as handle:
        metadata = os.fstat(handle.fileno())
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_ARCHIVE_BYTES:
            raise ValueError("staged archive is not a readable backup file")
        shutil.copyfileobj(handle, output)
        output.flush()


def pull_archive(host: str, credentials: Path) -> Path:
    address = str(ipaddress.ip_address(host))
    command = ["/usr/bin/ssh", "-F", "/dev/null", "-T", "-n", "-i", str(credentials / "ssh-key"),
               "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none",
               "-o", "PreferredAuthentications=publickey", "-o", "ClearAllForwardings=yes",
               "-o", "StrictHostKeyChecking=yes", "-o", "HostKeyAlgorithms=ssh-ed25519",
               "-o", f"UserKnownHostsFile={credentials / 'known-hosts'}",
               "-o", "GlobalKnownHostsFile=/dev/null", "-o", "UpdateHostKeys=no",
               "-o", "ConnectTimeout=10", "-o", "ConnectionAttempts=1", "--", f"openrc-stats-export@{address}"]
    return store_archive(command, PULL_DIR, utc_day(), mode=0o600, keep=14)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("export")
    subparsers.add_parser("serve")
    pull = subparsers.add_parser("pull")
    pull.add_argument("--host", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "serve":
            serve_archive(sys.stdout.buffer)
        elif args.command == "export":
            print(export_archive())
        else:
            print(pull_archive(args.host, Path(os.environ["CREDENTIALS_DIRECTORY"])))
    except (OSError, ValueError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
        print(f"OpenRC Stats backup failed ({error})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
