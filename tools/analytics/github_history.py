#!/usr/bin/env python3
"""Archive GitHub traffic and release-asset counter observations locally."""

from __future__ import annotations

import argparse
import csv
import fnmatch
import html
import io
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, time, timezone


DEFAULT_REPO = "bultodepapas/OpenRCsimulator"
DEFAULT_ASSET_GLOB = "openrc-simulator-*.zip"
DATABASE_NAME = "github-history.sqlite3"
SCHEMA_VERSION = 1


class CollectionError(Exception):
    """A collection or archive cannot be used safely."""


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def parse_timestamp(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError) as exc:
        raise CollectionError("Invalid GitHub timestamp") from exc
    if parsed.tzinfo is None:
        raise CollectionError("GitHub timestamp has no timezone")
    return parsed.astimezone(timezone.utc)


def nonnegative_int(value: object, field: str) -> int:
    if type(value) is not int or value < 0:
        raise CollectionError(f"Invalid {field} in GitHub response")
    return value


def github_json(endpoint: str, paginated: bool = False) -> object:
    # gh handles its own credential store and GH_TOKEN/GITHUB_TOKEN. Never ask it
    # to print a token, pass a token as an argument, or persist command stderr.
    command = [
        "gh", "api", "--hostname", "github.com",
        "-H", "Accept: application/vnd.github+json",
        "-H", "X-GitHub-Api-Version: 2022-11-28",
    ]
    if paginated:
        command.extend(["--paginate", "--slurp"])
    command.append(endpoint)
    environment = os.environ.copy()
    environment.pop("GH_DEBUG", None)
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=120, env=environment, check=False)
    except FileNotFoundError as exc:
        raise CollectionError("GitHub CLI (gh) is not installed or not on PATH") from exc
    except subprocess.TimeoutExpired as exc:
        raise CollectionError("GitHub API request timed out") from exc
    except OSError as exc:
        raise CollectionError("Could not start GitHub CLI") from exc
    if result.returncode:
        raise CollectionError(f"GitHub API request failed (gh exit {result.returncode}); check authentication, access, rate limit, and connectivity")
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise CollectionError("GitHub returned invalid JSON") from exc
    if not paginated:
        return response
    if not isinstance(response, list) or any(not isinstance(page, list) for page in response):
        raise CollectionError("Unexpected paginated GitHub response")
    return [item for page in response for item in page]


def fetch_traffic(repo: str, started: str) -> list[dict]:
    response = github_json(f"repos/{repo}/traffic/views?per=day")
    if not isinstance(response, dict) or not isinstance(response.get("views"), list):
        raise CollectionError("Unexpected traffic response")
    start_day = parse_timestamp(started).date()
    days = []
    seen = set()
    for entry in response["views"]:
        if not isinstance(entry, dict):
            raise CollectionError("Invalid traffic day")
        moment = parse_timestamp(entry.get("timestamp"))
        if moment.time() != time(0) or moment.date() > start_day:
            raise CollectionError("Traffic day is not a UTC midnight at or before collection")
        day = moment.date().isoformat()
        if day in seen:
            raise CollectionError("Duplicate traffic day in response")
        seen.add(day)
        days.append({
            "day": day,
            "views": nonnegative_int(entry.get("count"), "page views"),
            "uniques": nonnegative_int(entry.get("uniques"), "unique visitors"),
            "status": "partial" if moment.date() == start_day else "observed_after_day",
        })
    return days


def fetch_assets(repo: str, pattern: str) -> list[dict]:
    releases = github_json(f"repos/{repo}/releases?per_page=100", paginated=True)
    assets = []
    seen_releases = set()
    seen_assets = set()
    for release in releases:
        if not isinstance(release, dict) or type(release.get("draft")) is not bool:
            raise CollectionError("Invalid release in GitHub response")
        release_id = nonnegative_int(release.get("id"), "release ID")
        if release_id in seen_releases:
            raise CollectionError("Duplicate release ID in response")
        seen_releases.add(release_id)
        tag = release.get("tag_name")
        if not isinstance(tag, str):
            raise CollectionError("Invalid release tag in GitHub response")
        if release["draft"]:
            continue
        started = timestamp()
        release_assets = github_json(f"repos/{repo}/releases/{release_id}/assets?per_page=100", paginated=True)
        finished = timestamp()
        if finished < started:
            raise CollectionError("System clock moved backwards during asset collection")
        for asset in release_assets:
            if not isinstance(asset, dict) or not isinstance(asset.get("name"), str):
                raise CollectionError("Invalid release asset in GitHub response")
            asset_id = nonnegative_int(asset.get("id"), "asset ID")
            if asset_id in seen_assets:
                raise CollectionError("Duplicate asset ID in response")
            seen_assets.add(asset_id)
            if not isinstance(asset.get("state"), str):
                raise CollectionError("Invalid release asset state in GitHub response")
            if asset["state"] != "uploaded" or not fnmatch.fnmatchcase(asset["name"], pattern):
                continue
            assets.append({
                "asset_id": asset_id, "release_id": release_id, "tag": tag,
                "name": asset["name"],
                "count": nonnegative_int(asset.get("download_count"), "asset download count"),
                "started": started, "finished": finished,
            })
    return assets


def initialize(connection: sqlite3.Connection, repo: str, pattern: str) -> None:
    version = connection.execute("PRAGMA user_version").fetchone()[0]
    if version not in (0, SCHEMA_VERSION):
        raise CollectionError(f"Unsupported analytics database version {version}")
    connection.execute("CREATE TABLE IF NOT EXISTS settings (repo TEXT NOT NULL, asset_glob TEXT NOT NULL)")
    connection.execute("CREATE TABLE IF NOT EXISTS observations (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, started_utc TEXT NOT NULL, finished_utc TEXT NOT NULL)")
    connection.execute("CREATE TABLE IF NOT EXISTS attempts (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, started_utc TEXT NOT NULL, finished_utc TEXT NOT NULL, success INTEGER NOT NULL)")
    connection.execute("""CREATE TABLE IF NOT EXISTS traffic_days (
        day_utc TEXT PRIMARY KEY, views INTEGER NOT NULL, uniques INTEGER NOT NULL,
        status TEXT NOT NULL, started_utc TEXT NOT NULL, finished_utc TEXT NOT NULL)""")
    connection.execute("""CREATE TABLE IF NOT EXISTS asset_counts (
        observation_id INTEGER NOT NULL REFERENCES observations(id), asset_id INTEGER NOT NULL,
        release_id INTEGER NOT NULL, tag TEXT NOT NULL, name TEXT NOT NULL, count INTEGER NOT NULL,
        started_utc TEXT NOT NULL, finished_utc TEXT NOT NULL, PRIMARY KEY(observation_id, asset_id))""")
    saved = connection.execute("SELECT repo, asset_glob FROM settings").fetchall()
    if not saved:
        connection.execute("INSERT INTO settings VALUES (?, ?)", (repo, pattern))
    elif len(saved) != 1 or saved[0] != (repo, pattern):
        raise CollectionError("Output directory already belongs to a different repository or asset pattern")
    connection.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")


def add_observation(connection: sqlite3.Connection, kind: str, started: str, finished: str) -> int:
    if finished < started:
        raise CollectionError("System clock moved backwards during collection")
    previous = connection.execute("SELECT MAX(finished_utc) FROM observations WHERE kind = ?", (kind,)).fetchone()[0]
    if previous is not None and started <= previous:
        raise CollectionError("System clock precedes the previous observation; archive was not changed for this source")
    cursor = connection.execute("INSERT INTO observations(kind, started_utc, finished_utc) VALUES (?, ?, ?)",
                                (kind, started, finished))
    return cursor.lastrowid


def save_traffic(connection: sqlite3.Connection, days: list[dict], started: str, finished: str) -> None:
    add_observation(connection, "traffic", started, finished)
    for day in days:
        connection.execute("""INSERT INTO traffic_days VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(day_utc) DO UPDATE SET views=excluded.views, uniques=excluded.uniques,
            status=excluded.status, started_utc=excluded.started_utc, finished_utc=excluded.finished_utc
            WHERE excluded.started_utc >= traffic_days.started_utc""",
            (day["day"], day["views"], day["uniques"], day["status"], started, finished))


def save_assets(connection: sqlite3.Connection, assets: list[dict], started: str, finished: str) -> None:
    observation_id = add_observation(connection, "assets", started, finished)
    connection.executemany("INSERT INTO asset_counts VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [
        (observation_id, a["asset_id"], a["release_id"], a["tag"], a["name"], a["count"], a["started"], a["finished"])
        for a in assets
    ])


def compare_assets(previous: dict[int, int], current: dict[int, int]) -> dict:
    old_ids, new_ids = set(previous), set(current)
    shared = old_ids & new_ids
    decreased = {asset_id for asset_id in shared if current[asset_id] < previous[asset_id]}
    comparable = shared - decreased
    added, removed = new_ids - old_ids, old_ids - new_ids
    partial = bool(added or removed or decreased)
    return {
        "increase": (sum(current[asset_id] - previous[asset_id] for asset_id in comparable)
                     if comparable or not partial else None),
        "comparable": len(comparable), "added": len(added), "removed": len(removed),
        "decreased": len(decreased),
        "status": "partial" if partial else "matched_ids",
    }


def csv_text(header: list[str], rows: list[tuple]) -> str:
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(header)
    writer.writerows(rows)
    return output.getvalue()


def atomic_write(path: Path, contents: str) -> None:
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="", dir=path.parent,
                                         prefix=f".{path.name}.", delete=False) as output:
            temporary = Path(output.name)
            output.write(contents)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def html_table(headers: list[str], rows: list[tuple]) -> str:
    head = "".join(f"<th scope=\"col\">{html.escape(str(value))}</th>" for value in headers)
    if not rows:
        body = f'<tr><td colspan="{len(headers)}">No observations yet.</td></tr>'
    else:
        body = "".join("<tr>" + "".join(f"<td>{html.escape(str(value) if value is not None else '—')}</td>" for value in row) + "</tr>" for row in rows)
    return f"<div class=\"scroll\"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>"


def asset_platform(name: str) -> str:
    lowered = name.lower()
    for marker, label in (("-windows-", "Windows"), ("-linux-", "Linux"), ("-macos-", "macOS")):
        if marker in lowered:
            return label
    return "Other"


def generate_reports(connection: sqlite3.Connection, output_dir: Path) -> None:
    settings = connection.execute("SELECT repo, asset_glob FROM settings").fetchone()
    if not settings:
        raise CollectionError("Analytics database has not been initialized")
    repo, pattern = settings
    attempts = []
    for kind in ("traffic", "release assets"):
        row = connection.execute("SELECT started_utc, finished_utc, success FROM attempts WHERE kind = ? ORDER BY id DESC LIMIT 1", (kind,)).fetchone()
        attempts.append((kind, "succeeded" if row and row[2] else "failed" if row else "not attempted",
                         row[0] if row else "—", row[1] if row else "—"))
    traffic = connection.execute("SELECT day_utc, views, uniques, status, started_utc, finished_utc FROM traffic_days ORDER BY day_utc DESC").fetchall()
    observations = connection.execute("SELECT id, started_utc, finished_utc FROM observations WHERE kind='assets' ORDER BY started_utc, id").fetchall()
    interval_rows = []
    previous_observation = None
    previous_counts = None
    current_asset_rows = []
    for observation in observations:
        observation_id, started, finished = observation
        assets = connection.execute("SELECT asset_id, tag, name, count, started_utc, finished_utc FROM asset_counts WHERE observation_id = ? ORDER BY tag, name", (observation_id,)).fetchall()
        current_counts = {row[0]: row[3] for row in assets}
        current_asset_rows = [(tag, name, asset_id, count, asset_start, asset_end)
                              for asset_id, tag, name, count, asset_start, asset_end in assets]
        if previous_observation is not None:
            result = compare_assets(previous_counts, current_counts)
            interval_rows.append((previous_observation[1], previous_observation[2], started, finished,
                                  result["increase"], result["comparable"], result["added"], result["removed"],
                                  result["decreased"], result["status"]))
        previous_observation, previous_counts = observation, current_counts
    interval_rows.reverse()
    traffic_headers = ["day_utc", "page_views", "unique_visitors", "status", "observed_start_utc", "observed_end_utc"]
    interval_headers = ["from_start_utc", "from_end_utc", "to_start_utc", "to_end_utc", "matched_asset_increase",
                        "comparable_assets", "added_assets", "removed_assets", "decreased_assets", "status"]
    asset_headers = ["release_tag", "asset_name", "asset_id", "cumulative_downloads", "observed_start_utc", "observed_end_utc"]
    atomic_write(output_dir / "daily-traffic.csv", csv_text(traffic_headers, traffic))
    atomic_write(output_dir / "download-intervals.csv", csv_text(interval_headers, interval_rows))
    atomic_write(output_dir / "asset-counters.csv", csv_text(asset_headers, current_asset_rows))

    latest = "No release-asset observation yet."
    if observations:
        latest = (f"Latest collection: {observations[-1][1]} to {observations[-1][2]}; "
                  f"{len(current_asset_rows)} currently visible matching assets; "
                  f"their observed cumulative counters sum to {sum(row[3] for row in current_asset_rows)}.")
    asset_display_rows = [(tag, asset_platform(name), name, count)
                          for tag, name, _asset_id, count, _start, _end in current_asset_rows]
    report = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>GitHub traffic and downloads</title>
<style>body{{font:16px/1.5 system-ui,sans-serif;color:#18212b;background:#f6f8fa;max-width:1200px;margin:auto;padding:2rem}}h1,h2{{line-height:1.2}}section{{background:white;padding:1.2rem;margin:1rem 0;border:1px solid #d0d7de;border-radius:8px}}table{{border-collapse:collapse;width:100%;font-size:.88rem}}th,td{{text-align:left;padding:.5rem;border-bottom:1px solid #d8dee4;white-space:nowrap}}th{{background:#f6f8fa}}.scroll{{overflow-x:auto}}code{{overflow-wrap:anywhere}}a{{color:#0969da}}</style></head>
<body><h1>GitHub traffic and downloads</h1><p>Repository: <code>{html.escape(repo)}</code>. All dates and times are UTC.</p>
<section><h2>Last collection attempts</h2><p>A failed source keeps its previous observations; those figures may be stale. Run collection again after fixing access or connectivity.</p>{html_table(["Source", "Result", "Started", "Finished"], attempts)}</section>
<section><h2>GitHub repository traffic</h2><p>GitHub's daily page views and unique visitors are separate measures. A partial day was observed while it was still in progress; older buckets may still be revised by GitHub. Missing dates are unknown. Unique visitors cannot be added across days.</p>
{html_table(["UTC day", "Page views", "Unique visitors", "Status", "Observation start", "Observation end"], traffic)}<p><a href="daily-traffic.csv">Download daily traffic CSV</a></p></section>
<section><h2>Website download requests by country and time</h2><p>Open <a href="https://analytics.google.com/analytics/web/">Google Analytics</a> and select the website's GA4 property. In Explore, create a Free form report with Country and Date or Hour as dimensions, Event count as the metric, and a filter for Event name exactly <code>download_request</code>.</p><p>These countries describe website download requests only. GitHub repository traffic does not report reader countries, and a website request is not a confirmed release download.</p></section>
<section><h2>Release asset downloads</h2><p>{html.escape(latest)} The selected asset pattern is <code>{html.escape(pattern)}</code>; checksum files are excluded by the default pattern.</p>
<h3>Latest cumulative counters by version and platform</h3><p>Each row is the latest observed GitHub counter for that asset, not a count of unique people. Its precise request window is in the asset counters CSV.</p>
{html_table(["Release", "Platform", "Asset", "Cumulative downloads"], asset_display_rows)}
<p>GitHub reports cumulative counters, not calendar-day downloads. Each increase compares matching asset IDs across two collection windows. The first observation is a baseline. <code>partial</code> means assets appeared, disappeared or had a lower counter; the shown increase covers only comparable IDs and is not a total. A dash means no asset counters could be compared. A replacement or a short-lived asset between observations can go unseen. Counts include repeat and automated downloads.</p>
{html_table(["Earlier start", "Earlier end", "Later start", "Later end", "Matched increase", "Comparable", "Added", "Removed", "Decreased", "Status"], interval_rows)}<p><a href="download-intervals.csv">Download interval CSV</a> · <a href="asset-counters.csv">Download latest asset counters CSV</a></p></section>
<p>Views, unique visitors, website clicks and release downloads are independent measurements. These figures do not identify people, installs or conversions.</p></body></html>"""
    atomic_write(output_dir / "report.html", report)


def validate_repo(repo: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise CollectionError("Repository must have the form owner/name")


def collect(output_dir: Path, repo: str, pattern: str) -> int:
    validate_repo(repo)
    if not pattern:
        raise CollectionError("Asset pattern cannot be empty")
    output_dir.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(output_dir / DATABASE_NAME, timeout=1, isolation_level=None)
    errors = []
    try:
        # Keep the lock during requests: overlapping scheduled/manual collections
        # must not interleave samples or render stale reports.
        connection.execute("BEGIN IMMEDIATE")
        initialize(connection, repo, pattern)
        for kind, fetch, save in (
            ("traffic", lambda started: fetch_traffic(repo, started), save_traffic),
            ("release assets", lambda _started: fetch_assets(repo, pattern), save_assets),
        ):
            started = timestamp()
            try:
                values = fetch(started)
                finished = timestamp()
                save(connection, values, started, finished)
                connection.execute("INSERT INTO attempts(kind, started_utc, finished_utc, success) VALUES (?, ?, ?, 1)", (kind, started, finished))
                print(f"Collected {kind}: {len(values)} records")
            except CollectionError as exc:
                errors.append(f"{kind}: {exc}")
                connection.execute("INSERT INTO attempts(kind, started_utc, finished_utc, success) VALUES (?, ?, ?, 0)", (kind, started, timestamp()))
        connection.commit()
        connection.execute("BEGIN IMMEDIATE")
        generate_reports(connection, output_dir)
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
    for error in errors:
        print(f"Collection failed for {error}", file=sys.stderr)
    print(f"Report: {output_dir / 'report.html'}")
    return 1 if errors else 0


def report(output_dir: Path) -> int:
    path = output_dir / DATABASE_NAME
    if not path.is_file():
        raise CollectionError(f"No analytics database at {path}")
    connection = sqlite3.connect(path, timeout=1, isolation_level=None)
    try:
        connection.execute("BEGIN IMMEDIATE")
        if connection.execute("PRAGMA user_version").fetchone()[0] != SCHEMA_VERSION:
            raise CollectionError("Unsupported analytics database version")
        generate_reports(connection, output_dir)
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
    print(f"Report: {output_dir / 'report.html'}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    collect_parser = subparsers.add_parser("collect", help="Collect GitHub data and refresh reports")
    collect_parser.add_argument("--output-dir", type=Path, required=True)
    collect_parser.add_argument("--repo", default=DEFAULT_REPO)
    collect_parser.add_argument("--asset-glob", default=DEFAULT_ASSET_GLOB)
    report_parser = subparsers.add_parser("report", help="Refresh reports from the local archive")
    report_parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "collect":
            return collect(args.output_dir, args.repo, args.asset_glob)
        return report(args.output_dir)
    except (CollectionError, OSError, sqlite3.Error) as exc:
        print(f"Analytics error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
