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


EXPORT_DIR = Path("/var/lib/openrc-stats-backup-export")
PULL_DIR = Path("/var/lib/openrc-stats-backup")
CT_BACKUP_DIR = "/var/lib/openrc-stats/backups"
BACKUP_NAME = re.compile(r"github-history-\d{4}-\d{2}-\d{2}\.sqlite3", re.ASCII)
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024


def utc_day() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def backup_name(day: str) -> str:
    return f"github-history-{day}.sqlite3"


def validate_archive(path: Path) -> None:
    if not 0 < path.stat().st_size <= MAX_ARCHIVE_BYTES:
        raise ValueError("archive size is outside the allowed range")
    with closing(sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro&immutable=1", uri=True)) as db:
        db.execute("PRAGMA trusted_schema = OFF")
        if db.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise ValueError("archive failed SQLite quick_check")
        if db.execute("PRAGMA user_version").fetchone()[0] not in (1, 2):
            raise ValueError("unknown GitHub archive schema version")
        required_tables = {"settings", "observations", "asset_counts", "traffic_days"}
        tables = {name for (name,) in db.execute("SELECT name FROM sqlite_schema WHERE type = 'table'")}
        if not required_tables <= tables:
            raise ValueError("file is not a GitHub history archive")
        if db.execute("SELECT 1 FROM observations LIMIT 1").fetchone() is None:
            raise ValueError("GitHub archive has no observations")


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
