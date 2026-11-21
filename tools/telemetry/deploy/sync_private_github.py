#!/usr/bin/env python3
"""Transfer private GitHub aggregates from an authenticated operator to OpenRC Stats."""

import argparse
from contextlib import closing
from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path
import re
import shlex
import sqlite3
import subprocess
import sys


HERE = Path(__file__).resolve().parent
if (HERE / "github_history.py").is_file():
    ANALYTICS = HERE
elif (HERE.parents[1] / "analytics" / "github_history.py").is_file():
    ANALYTICS = HERE.parents[1] / "analytics"
else:
    ANALYTICS = Path("/opt/openrc-stats/current/tools/analytics")
sys.path.insert(0, str(ANALYTICS))
import github_history as history


DATABASE = Path("/var/lib/openrc-stats/github") / history.DATABASE_NAME
REMOTE_IMPORT = (
    "flock", "--timeout", "75", "/var/lib/openrc-stats/state/build.lock",
    "runuser", "-u", "openrc-stats", "--", "/usr/bin/python3",
    "/usr/local/lib/openrc-stats/sync_private_github.py", "import",
)
SOURCE_NAMES = ("traffic", "clones", "community")
COUNTERS = ("stars", "forks", "watchers", "open_issues")
COMMUNITY_FIELDS = ("counters", "referrers", "paths", "releases", "star_days")
MAX_BYTES = 256 * 1024
MAX_COUNT = 2**63 - 1
UTC = timezone.utc


def fields(value, names):
    if type(value) is not dict or value.keys() != set(names):
        raise ValueError("Unexpected private GitHub fields")
    return value


def rows(value, limit, names):
    if type(value) is not list or len(value) > limit:
        raise ValueError("Invalid private GitHub rows")
    for row in value:
        yield fields(row, names)


def count(value):
    if type(value) is not int or not 0 <= value <= MAX_COUNT:
        raise ValueError("Invalid private GitHub count")


def day(value):
    if not isinstance(value, str):
        raise ValueError("Invalid private GitHub day")
    parsed = date.fromisoformat(value)
    if parsed.isoformat() != value:
        raise ValueError("Invalid private GitHub day")
    return parsed


def validate_daily(value, today):
    seen = set()
    for row in rows(value, 15, ("day", "views", "uniques", "status")):
        observed = day(row["day"])
        if observed in seen or not 0 <= (today - observed).days <= 14:
            raise ValueError("Unexpected private GitHub daily range")
        status = "partial" if observed == today else "observed_after_day"
        if row["status"] != status:
            raise ValueError("Invalid private GitHub daily status")
        count(row["views"])
        count(row["uniques"])
        seen.add(observed)


def validate_community(value, finished):
    value = fields(value, COMMUNITY_FIELDS)
    for counter in fields(value["counters"], COUNTERS).values():
        count(counter)
    for kind, identity, columns in (
        ("referrers", "referrer", ("referrer", "count", "uniques")),
        ("paths", "path", ("path", "title", "count", "uniques")),
    ):
        seen = set()
        for row in rows(value[kind], 10, columns):
            key = history.text_field(row[identity], identity)
            if key in seen:
                raise ValueError("Duplicate private GitHub community row")
            count(row["count"])
            count(row["uniques"])
            seen.add(key)
            if kind == "paths" and (not isinstance(row["title"], str) or len(row["title"]) > 1000):
                raise ValueError("Invalid private GitHub path title")
    tags = set()
    for release in rows(value["releases"], 5000, ("tag", "published", "prerelease")):
        tag = history.text_field(release["tag"], "release tag", 200)
        published = history.parse_timestamp(release["published"])
        if tag in tags or type(release["prerelease"]) is not bool or published > finished:
            raise ValueError("Invalid GitHub release")
        if published.isoformat().replace("+00:00", "Z") != release["published"]:
            raise ValueError("Invalid GitHub release timestamp")
        tags.add(tag)
    stars = value["star_days"]
    if type(stars) is not dict:
        raise ValueError("Invalid private GitHub star history")
    for stamp, total in stars.items():
        if day(stamp) > finished.date():
            raise ValueError("Invalid private GitHub star day")
        count(total)
    star_total = value["counters"]["stars"]
    if star_total >= 50 and sum(stars.values()) < star_total // 2:
        raise ValueError("Incomplete private GitHub star history")


def parse_stamp(value):
    parsed = history.parse_timestamp(value)
    if parsed.isoformat(timespec="microseconds").replace("+00:00", "Z") != value:
        raise ValueError("Invalid private GitHub observation timestamp")
    return parsed


def validate_payload(payload, now):
    fields(payload, ("version", "repo", "sources"))
    if type(payload["version"]) is not int or payload["version"] != 1 or payload["repo"] != history.DEFAULT_REPO:
        raise ValueError("Unexpected private GitHub transfer version or repository")
    sources = payload["sources"]
    if type(sources) is not dict or not sources or sources.keys() - set(SOURCE_NAMES):
        raise ValueError("Unexpected private GitHub sources")
    for kind, source in sources.items():
        fields(source, ("started", "finished", "data"))
        started = parse_stamp(source["started"])
        finished = parse_stamp(source["finished"])
        if not now - timedelta(hours=1) <= started <= finished <= now + timedelta(minutes=5):
            raise ValueError("Private GitHub observation is outside the accepted time window")
        if kind == "community":
            validate_community(source["data"], finished)
        else:
            validate_daily(source["data"], started.date())
    return sources


def save_community(db, data, started, finished, *, replace_catalogue):
    observation = history.add_observation(db, "community", started, finished)
    db.execute("INSERT INTO repo_counters VALUES (?, ?, ?, ?, ?)",
               (observation, *(data["counters"][key] for key in COUNTERS)))
    db.executemany("INSERT INTO popular_referrers VALUES (?, ?, ?, ?)", [
        (observation, row["referrer"], row["count"], row["uniques"]) for row in data["referrers"]
    ])
    db.executemany("INSERT INTO popular_paths VALUES (?, ?, ?, ?, ?)", [
        (observation, row["path"], row["title"], row["count"], row["uniques"]) for row in data["paths"]
    ])
    db.execute("DELETE FROM star_days")
    db.executemany("INSERT INTO star_days VALUES (?, ?)", sorted(data["star_days"].items()))
    if replace_catalogue:
        db.execute("DELETE FROM releases")
        db.executemany("INSERT INTO releases VALUES (?, ?, ?)", [
            (release["tag"], release["published"], int(release["prerelease"]))
            for release in data["releases"]
        ])


def import_private(path, payload, now):
    sources = validate_payload(payload, now)
    savers = {"traffic": history.save_traffic, "clones": history.save_clones}
    imported = []
    with closing(sqlite3.connect(f"{path.resolve().as_uri()}?mode=rw", uri=True, timeout=5)) as db, db:
        db.execute("BEGIN IMMEDIATE")
        identity = db.execute("SELECT repo, asset_glob FROM settings").fetchall()
        if identity != [(history.DEFAULT_REPO, history.DEFAULT_ASSET_GLOB)]:
            raise ValueError("Private GitHub archive identity does not match")
        # Preserve version-1 history if this is the first refresh after an upgrade.
        history.initialize(db, history.DEFAULT_REPO, history.DEFAULT_ASSET_GLOB)
        for kind, source in sources.items():
            started, finished = source["started"], source["finished"]
            previous = db.execute("SELECT MAX(finished_utc) FROM observations WHERE kind = ?", (kind,)).fetchone()[0]
            if previous is not None and started <= previous:
                continue
            if kind == "community":
                public = db.execute("SELECT MAX(finished_utc) FROM observations "
                                    "WHERE kind = 'public community'").fetchone()[0]
                # A list read during overlapping collections cannot be ordered by completion time.
                if public is not None and started <= public <= finished:
                    continue
                save_community(db, source["data"], started, finished,
                               replace_catalogue=public is None or public < started)
            else:
                savers[kind](db, source["data"], started, finished)
            attempt = db.execute("SELECT MAX(finished_utc) FROM attempts WHERE kind = ?", (kind,)).fetchone()[0]
            if attempt is None or finished > attempt:
                db.execute("INSERT INTO attempts (kind, started_utc, finished_utc, success) VALUES (?, ?, ?, 1)",
                           (kind, started, finished))
            imported.append(kind)
    return imported


def read_payload(stream):
    raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError("Private GitHub transfer exceeds size limit")
    return json.loads(raw)


def collect():
    repo = history.DEFAULT_REPO
    fetchers = {
        "traffic": lambda started: history.fetch_traffic(repo, started),
        "clones": lambda started: history.fetch_clones(repo, started),
        "community": lambda _started: history.fetch_community(repo),
    }
    sources = {}
    for kind, fetch in fetchers.items():
        started = history.timestamp()
        try:
            data = fetch(started)
            if kind == "community":
                data = {field: data[field] for field in COMMUNITY_FIELDS}
            finished = history.timestamp()
            source = {"started": started, "finished": finished, "data": data}
            validate_payload({"version": 1, "repo": repo, "sources": {kind: source}}, datetime.now(UTC))
        except (history.CollectionError, ValueError):
            print(f"Private GitHub {kind} collection failed", file=sys.stderr)
            continue
        sources[kind] = source
    return {"version": 1, "repo": repo, "sources": sources}


def ssh_command(host, key, remote):
    return [
        "ssh", "-T", "-i", str(key), "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=8", "--", host,
        shlex.join(("pct", "exec", "406", "--", *remote)),
    ]


def push(host, key):
    if not re.fullmatch(r"root@[A-Za-z0-9_.:-]+", host):
        raise ValueError("Use an operator SSH destination in the form root@host")
    payload = collect()
    sources = payload["sources"]
    if not sources:
        return 1
    encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    if len(encoded) > MAX_BYTES:
        raise ValueError("Private GitHub transfer exceeds size limit")
    result = subprocess.run(ssh_command(host, key, REMOTE_IMPORT),
                            input=encoded, capture_output=True, timeout=100, check=True)
    imported = result.stdout.decode("ascii").split()
    if len(set(imported)) != len(imported) or set(imported) - sources.keys():
        raise ValueError("Unexpected private GitHub import response")
    if imported:
        build = ("systemctl", "start", "openrc-stats-build.service")
        subprocess.run(ssh_command(host, key, build), stdin=subprocess.DEVNULL,
                       capture_output=True, timeout=630, check=True)
        print("Imported private GitHub sources", *imported)
    else:
        print("Private GitHub archive already has newer observations")
    return int(len(sources) < len(SOURCE_NAMES))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    operator = commands.add_parser("push")
    operator.add_argument("--host", required=True)
    operator.add_argument("--key", required=True, type=Path)
    commands.add_parser("import")
    args = parser.parse_args(argv)
    try:
        if args.command == "push":
            return push(args.host, args.key)
        payload = read_payload(sys.stdin.buffer)
        print(*import_private(DATABASE, payload, datetime.now(UTC)))
    except subprocess.CalledProcessError as error:
        print(f"Private GitHub sync SSH command exited {error.returncode}", file=sys.stderr)
        return 1
    except (OSError, subprocess.TimeoutExpired, sqlite3.Error, history.CollectionError, ValueError, RecursionError) as error:
        print(f"Private GitHub sync failed ({type(error).__name__})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
