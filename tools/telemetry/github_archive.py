"""GitHub statistics for the operator dashboard, read from the local GitHub history archive.

The archive is written by `tools/analytics/github_history.py collect` (its daily Windows task or a manual run):
cumulative release-asset counters per collection, daily page views and clones, repository counters, the 14-day
top referrers and paths, published releases and stars per day. This module opens it read-only and reuses that
tool's interval comparison and platform naming, so both reports agree. Standard library only.
"""
from __future__ import annotations

from datetime import datetime, timezone
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys

ANALYTICS = Path(__file__).resolve().parents[1] / "analytics"
sys.path.insert(0, str(ANALYTICS))
import github_history  # noqa: E402

PLATFORMS = ("Windows", "macOS", "Linux", "Other")
RELEASE_KEY_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.?(\d+))?$")
PRE_RANK = {"alpha": 0, "beta": 1, "rc": 2}


def release_key(release):
    """Semantic order (same rule as snapshot.release_key): v0.3.10 after v0.3.9, final after its pre-releases."""
    match = RELEASE_KEY_RE.match(release)
    if not match:
        return (-1, -1, -1, -1, -1, release)
    major, minor, patch, pre, number = match.groups()
    rank = (PRE_RANK[pre], int(number)) if pre else (9, 0)
    return (int(major), int(minor), int(patch), *rank, release)


def default_dir():
    configured = os.environ.get("OPENRC_ANALYTICS_DIR")
    if configured:
        return Path(configured)
    return Path(os.environ.get("LOCALAPPDATA", Path.home())) / "OpenRCsimulator" / "analytics"


def collect(directory, timeout=180):
    """Run the archive collector (read-only GitHub API calls through the existing `gh` login).
    Returns (ok, message); a failure keeps the previous archive usable."""
    try:
        result = subprocess.run([sys.executable, str(ANALYTICS / "github_history.py"), "collect", "--output-dir",
                                 str(directory)], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        return False, f"collector did not finish: {error.__class__.__name__}"
    if result.returncode != 0:
        lines = (result.stderr or result.stdout).strip().splitlines()
        return False, lines[-1] if lines else f"collector exit {result.returncode}"
    return True, "collected"


def _parse(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(timezone.utc)


def load(directory):
    """GitHub model from the archive, or None when there is no archive. Version 1 archives (before the
    community tables) load with empty traffic extras until their next collection upgrades them."""
    path = Path(directory) / github_history.DATABASE_NAME
    if not path.is_file():
        return None
    connection = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True, timeout=2)
    try:
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version not in github_history.READABLE_VERSIONS:
            raise ValueError("unsupported GitHub history archive version")
        repo, pattern = connection.execute("SELECT repo, asset_glob FROM settings").fetchone()
        attempts = {}
        for kind in ("traffic", "release assets", "clones", "community"):
            row = connection.execute("SELECT started_utc, finished_utc, success FROM attempts WHERE kind = ? "
                                     "ORDER BY id DESC LIMIT 1", (kind,)).fetchone()
            if row:
                attempts[kind] = {"started": row[0], "finished": row[1], "success": bool(row[2])}
        attempt = attempts.get("release assets")
        observations = connection.execute("SELECT id, started_utc, finished_utc FROM observations "
                                          "WHERE kind = 'assets' ORDER BY started_utc, id").fetchall()
        intervals, previous, assets = [], None, []
        for observation_id, started, finished in observations:
            rows = connection.execute("SELECT asset_id, tag, name, count FROM asset_counts WHERE observation_id = ?",
                                      (observation_id,)).fetchall()
            counts = {asset_id: count for asset_id, _, _, count in rows}
            if previous is not None:
                result = github_history.compare_assets(previous[1], counts)
                intervals.append({"from_end": previous[0], "to_end": finished, "increase": result["increase"],
                                  "status": result["status"]})
            previous = (finished, counts)
            assets = [{"tag": tag, "name": name, "platform": github_history.asset_platform(name), "count": count}
                      for _, tag, name, count in rows]
        extras = _extras(connection, version)
    finally:
        connection.close()
    return {
        "repo": repo, "pattern": pattern,
        "collected_utc": observations[-1][2] if observations else None,
        "last_attempt": attempt, "attempts": attempts,
        "assets": assets, "intervals": intervals, **extras,
    }


def _days(connection, table):
    return [{"day": d, "count": v, "uniques": u, "status": s}
            for d, v, u, s in connection.execute(f"SELECT day_utc, views, uniques, status FROM {table} ORDER BY day_utc")]


def _extras(connection, version):
    extras = {"traffic": _days(connection, "traffic_days"), "clones": [], "counters": [], "referrers": [],
              "paths": [], "community_utc": None, "releases": [], "star_days": {}}
    if version < 2:
        return extras
    extras["clones"] = _days(connection, "clone_days")
    extras["counters"] = [
        {"observed": finished, "stars": stars, "forks": forks, "watchers": watchers, "open_issues": issues}
        for finished, stars, forks, watchers, issues in connection.execute(
            "SELECT o.finished_utc, c.stars, c.forks, c.watchers, c.open_issues FROM repo_counters c "
            "JOIN observations o ON o.id = c.observation_id ORDER BY o.finished_utc")]
    latest = connection.execute("SELECT id, finished_utc FROM observations WHERE kind = 'community' "
                                "ORDER BY finished_utc DESC, id DESC LIMIT 1").fetchone()
    if latest:
        extras["community_utc"] = latest[1]
        extras["referrers"] = [{"name": r, "count": c, "uniques": u} for r, c, u in connection.execute(
            "SELECT referrer, count, uniques FROM popular_referrers WHERE observation_id = ? ORDER BY count DESC",
            (latest[0],))]
        extras["paths"] = [{"name": p, "title": t, "count": c, "uniques": u} for p, t, c, u in connection.execute(
            "SELECT path, title, count, uniques FROM popular_paths WHERE observation_id = ? ORDER BY count DESC",
            (latest[0],))]
    extras["releases"] = [{"tag": t, "published": p, "prerelease": bool(pre)} for t, p, pre in connection.execute(
        "SELECT tag, published_utc, prerelease FROM releases ORDER BY published_utc")]
    extras["star_days"] = dict(connection.execute("SELECT day_utc, stars FROM star_days ORDER BY day_utc"))
    return extras


def stars_cumulative(model, days):
    """Cumulative stars at the end of each ISO day in `days` (stars given before the window count at its start).
    Stars later withdrawn are not in GitHub's list, so history reflects current stargazers."""
    star_days = model.get("star_days") or {}
    if not star_days and not model.get("counters"):
        return [None] * len(days)  # never collected: unknown, not zero
    total = sum(n for d, n in star_days.items() if d < days[0]) if days else 0
    out = []
    for day in days:
        total += star_days.get(day, 0)
        out.append(total)
    return out


def window_sum(rows, days, key="count"):
    """Sum of a daily series over the ISO days given."""
    wanted = set(days)
    return sum(r[key] for r in rows if r["day"] in wanted)


def per_release(model):
    """[(tag, {platform: count}, total)] newest release first."""
    releases = {}
    for asset in model["assets"]:
        counts = releases.setdefault(asset["tag"], dict.fromkeys(PLATFORMS, 0))
        counts[asset["platform"] if asset["platform"] in PLATFORMS else "Other"] += asset["count"]
    return [(tag, counts, sum(counts.values()))
            for tag, counts in sorted(releases.items(), key=lambda item: release_key(item[0]), reverse=True)]


def per_day(model):
    """{UTC day of the later collection: (increase, partial)} summed over intervals ending that day."""
    days = {}
    for interval in model["intervals"]:
        if interval["increase"] is None:
            continue
        day = _parse(interval["to_end"]).date().isoformat()
        total, partial = days.get(day, (0, False))
        days[day] = (total + interval["increase"], partial or interval["status"] != "matched_ids")
    return days


def recent_increase(model, now, days=7):
    """Matched downloads in intervals that ended within `days` of `now` (seconds)."""
    return sum(i["increase"] or 0 for i in model["intervals"]
               if now - _parse(i["to_end"]).timestamp() <= days * 86400)


def age_s(model, now):
    if not model or not model["collected_utc"]:
        return None
    return max(0, int(now - _parse(model["collected_utc"]).timestamp()))  # collected after the receiver snapshot
