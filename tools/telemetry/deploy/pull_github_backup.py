"""Copy today's verified GitHub archive from Proxmox to an operator-owned second host."""
import argparse
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

if __package__:
    from .host.openrc_stats_backup import backup_name, utc_day, validate_archive
else:
    directory = Path(__file__).resolve().parent
    validator = directory / "host" if (directory / "host" / "openrc_stats_backup.py").is_file() else directory
    sys.path.insert(0, str(validator))
    from openrc_stats_backup import backup_name, utc_day, validate_archive


def pull(host, key, ct, destination):
    destination = destination.resolve()
    repo = Path(__file__).resolve().parents[3]
    if (repo / ".git").exists() and destination.is_relative_to(repo):
        raise ValueError("backups must live outside the source repository")
    destination.mkdir(parents=True, exist_ok=True)
    day = utc_day()
    name = backup_name(day)
    command = ["ssh", "-i", str(key), "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o",
               "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10", "--", host,
               f"pct exec {ct} -- cat /var/lib/openrc-stats/backups/{name}"]
    handle = tempfile.NamedTemporaryFile(dir=destination, prefix=f".{name}.", delete=False)
    tmp = Path(handle.name)
    try:
        with handle:
            subprocess.run(command, stdout=handle, timeout=45, check=True)
            handle.flush()
            os.fsync(handle.fileno())
        validate_archive(tmp, max_bytes=None)
        if utc_day() != day:
            raise ValueError("UTC date changed during transfer")
        tmp.replace(destination / name)
    finally:
        tmp.unlink(missing_ok=True)
    for old in sorted(destination.glob("github-history-*.sqlite3"))[:-14]:
        old.unlink()
    print(destination / name)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--key", required=True, type=Path)
    parser.add_argument("--ct", default=406, type=int)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        pull(args.host, args.key, args.ct, args.destination)
    except (OSError, subprocess.SubprocessError, sqlite3.Error, ValueError) as error:
        print(f"OpenRC Stats backup transfer failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
