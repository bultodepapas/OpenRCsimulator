"""Release download counters for the operator dashboard, read from the local GitHub history archive.

The archive is written by `tools/analytics/github_history.py collect` (its daily Windows task or a manual run):
cumulative GitHub counters per release asset, observed per collection. This module opens it read-only and reuses
that tool's interval comparison and platform naming, so both reports agree. Standard library only.
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
    """Download model from the archive, or None when there is no archive."""
    path = Path(directory) / github_history.DATABASE_NAME
    if not path.is_file():
        return None
    connection = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True, timeout=2)
    try:
        if connection.execute("PRAGMA user_version").fetchone()[0] != github_history.SCHEMA_VERSION:
            raise ValueError("unsupported GitHub history archive version")
        repo, pattern = connection.execute("SELECT repo, asset_glob FROM settings").fetchone()
        attempt = connection.execute("SELECT started_utc, finished_utc, success FROM attempts WHERE kind = "
                                     "'release assets' ORDER BY id DESC LIMIT 1").fetchone()
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
    finally:
        connection.close()
    return {
        "repo": repo, "pattern": pattern,
        "collected_utc": observations[-1][2] if observations else None,
        "last_attempt": None if attempt is None else {"started": attempt[0], "finished": attempt[1],
                                                      "success": bool(attempt[2])},
        "assets": assets, "intervals": intervals,
    }


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
