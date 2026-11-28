"""GitHub statistics for the operator dashboard, read from the local GitHub history archive.

The archive is written by `tools/analytics/github_history.py collect` (its daily Windows task or a manual run):
cumulative release-asset counters per collection, daily page views and clones, repository counters, the 14-day
top referrers and paths, published releases and stars per day. This module opens it read-only and reuses that
tool's interval comparison and platform naming, so both reports agree. Standard library only.
"""
from __future__ import annotations

from datetime import datetime, timezone
from fnmatch import fnmatchcase
import hashlib
import json
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
RELEASE_MILESTONES = (("24 h", 24, 6), ("72 h", 72, 12), ("7 days", 168, 24))  # label, target hours, tolerance hours


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


def collect(directory, timeout=180, *, public_only=False):
    """Run the archive collector using public endpoints or the existing `gh` login.
    Returns (ok, message); a failure keeps the previous archive usable."""
    command = [sys.executable, str(ANALYTICS / "github_history.py"), "collect", "--output-dir", str(directory)]
    if public_only:
        command.append("--public-only")
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        return False, f"collector did not finish: {error.__class__.__name__}"
    if result.returncode != 0:
        lines = (result.stderr or result.stdout).strip().splitlines()
        return False, lines[-1] if lines else f"collector exit {result.returncode}"
    return True, "collected"


def public_release_inventory(pattern=github_history.DEFAULT_ASSET_GLOB):
    """Look for public release and package changes without reading download counts."""
    api = github_history.public_github_json
    endpoint = f"repos/{github_history.DEFAULT_REPO}/releases"
    releases = api(f"{endpoint}?per_page=100", paginated=True)
    error = github_history.CollectionError
    if not isinstance(releases, list):
        raise error("Invalid public release list")
    inventory = {}
    for release in releases:
        if not isinstance(release, dict) or type(release.get("draft")) is not bool:
            raise error("Invalid release in public list")
        if release["draft"] or release.get("published_at") is None:
            continue
        tag = github_history.text_field(release.get("tag_name"), "release tag", 200)
        if tag in inventory or type(release.get("prerelease")) is not bool:
            raise error("Invalid or duplicate public release")
        published = github_history.parse_timestamp(release["published_at"])
        embedded = release.get("assets")
        if not isinstance(embedded, list) or len(embedded) >= 100:
            release_id = github_history.nonnegative_int(release.get("id"), "release ID")
            embedded = api(f"{endpoint}/{release_id}/assets?per_page=100", paginated=True)
        assets = set()
        for asset in embedded:
            if not isinstance(asset, dict) or not isinstance(asset.get("name"), str) or (
                    not isinstance(asset.get("state"), str)):
                raise error("Invalid public release asset")
            if asset["state"] == "uploaded" and fnmatchcase(asset["name"], pattern):
                assets.add((asset["name"], github_history.nonnegative_int(asset.get("id"), "asset ID")))
        inventory[tag] = (published, release["prerelease"], assets)
    return inventory


def release_inventory_changed(inventory, model):
    """Compare the public page of releases with the last published dashboard snapshot."""
    model = model or {}
    releases = {row["tag"]: (_parse(row["published"]), row["prerelease"]) for row in model.get("releases", [])}
    if releases.keys() != inventory.keys():
        return True
    assets = {}
    for asset in model.get("assets", []):
        assets.setdefault(asset["tag"], {})[asset["name"]] = asset.get("id")
    for tag, (published, prerelease, packages) in inventory.items():
        if releases.get(tag) != (published, prerelease):
            return True
        known = assets.get(tag, {})
        if known.keys() != {name for name, _ in packages} or any(
                known[name] is not None and known[name] != asset_id for name, asset_id in packages):
            return True
    return False


def release_inventory_token(model):
    """Identify the release data shared by the stored snapshot and its published HTML."""
    model = model or {}
    releases = sorted((r["tag"], r.get("published") or "", bool(r.get("prerelease")))
                      for r in model.get("releases", []))
    assets = sorted((a["tag"], a["name"], a.get("id") or 0) for a in model.get("assets", []))
    return hashlib.sha256(json.dumps([releases, assets]).encode("utf-8")).hexdigest()


def _parse(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(timezone.utc)


def _record_release_milestones(milestones, published, rows):
    """Select near-target sums from one package collection, retaining the actual release capture time."""
    samples = {}
    for _, tag, _, count, finished in rows:
        if tag not in published:
            continue
        total, packages, observed = samples.get(tag, (0, 0, finished))
        samples[tag] = (total + count, packages + 1, max(observed, finished))
    for tag, (total, packages, observed) in samples.items():
        age_s = (_parse(observed) - published[tag]).total_seconds()
        slots = milestones.setdefault(tag, [None] * len(RELEASE_MILESTONES))
        for index, (_, target_hours, tolerance_hours) in enumerate(RELEASE_MILESTONES):
            target_s = target_hours * 3600
            distance_s = abs(age_s - target_s)
            if distance_s > tolerance_hours * 3600:
                continue
            previous = slots[index]
            if previous is not None:
                previous_age = previous["age_s"]
                if (distance_s, age_s) >= (abs(previous_age - target_s), previous_age):
                    continue
            slots[index] = {"downloads": total, "packages": packages, "observed_utc": observed, "age_s": age_s}


def load(directory):
    """GitHub model from the archive, or None when there is no archive. Version 1 archives (before the
    community tables) load with empty traffic extras until their next collection upgrades them."""
    path = Path(directory) / github_history.DATABASE_NAME
    return load_path(path) if path.is_file() else None


def load_path(path, *, immutable=False):
    """Read either the live archive or an immutable, closed backup file."""
    flags = "mode=ro&immutable=1" if immutable else "mode=ro"
    connection = sqlite3.connect(f"{Path(path).resolve().as_uri()}?{flags}", uri=True, timeout=2)
    try:
        connection.execute("PRAGMA trusted_schema = OFF")
        connection.execute("BEGIN")  # Read one archive generation if collection commits concurrently.
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version not in github_history.READABLE_VERSIONS:
            raise ValueError("unsupported GitHub history archive version")
        repo, pattern = connection.execute("SELECT repo, asset_glob FROM settings").fetchone()
        attempts = {}
        attempt_kinds = github_history.ATTEMPT_KINDS if version >= 2 else ("traffic", "release assets")
        for kind in attempt_kinds:
            row = connection.execute("SELECT started_utc, finished_utc, success FROM attempts WHERE kind = ? "
                                     "ORDER BY id DESC LIMIT 1", (kind,)).fetchone()
            if row:
                attempts[kind] = {"started": row[0], "finished": row[1], "success": bool(row[2])}
        attempt = attempts.get("release assets")
        observations = connection.execute("SELECT id, started_utc, finished_utc FROM observations "
                                          "WHERE kind = 'assets' ORDER BY started_utc, id").fetchall()
        extras = _extras(connection, version)
        published = {release["tag"]: _parse(release["published"]) for release in extras["releases"]
                     if not release["prerelease"]}
        milestones = {}
        intervals, previous, assets = [], None, []
        platform_history = {}
        for observation_id, started, finished in observations:
            rows = connection.execute("SELECT asset_id, tag, name, count, finished_utc FROM asset_counts "
                                      "WHERE observation_id = ?",
                                      (observation_id,)).fetchall()
            counts = {asset_id: count for asset_id, _, _, count, _ in rows}
            if previous is not None:
                result = github_history.compare_assets(previous[1], counts)
                intervals.append({"from_end": previous[0], "to_end": finished, "increase": result["increase"],
                                  "status": result["status"]})
            previous = (finished, counts)
            assets = [{"id": asset_id, "tag": tag, "name": name,
                       "platform": github_history.asset_platform(name), "count": count}
                      for asset_id, tag, name, count, _ in rows]
            totals = {}
            for asset in assets:
                platform = asset["platform"]
                totals[platform] = totals.get(platform, 0) + asset["count"]
            day = _parse(finished).date().isoformat()
            if day not in platform_history or _parse(finished) >= _parse(platform_history[day]["observed"]):
                platform_history[day] = {"day": day, "observed": finished, "counts": totals}
            _record_release_milestones(milestones, published, rows)
        observations_utc = dict(connection.execute(
            "SELECT kind, MAX(finished_utc) FROM observations GROUP BY kind"))
    finally:
        connection.close()
    if version < 2:
        observations_utc = {kind: observations_utc.get(kind) for kind in ("assets", "traffic")}
    public_community = observations_utc.get("public community")
    private_community = observations_utc.get("community")
    community = max(filter(None, (public_community, private_community)), default=None)
    source_utc = {"release assets": observations_utc.get("assets"), "traffic": observations_utc.get("traffic"),
                  "clones": observations_utc.get("clones"), "community": community, "referrals": private_community,
                  "star history": private_community}
    latest_community_attempt = max((kind for kind in ("community", "public community") if kind in attempts),
                                   key=lambda kind: attempts[kind]["started"], default=None)
    source_attempts = {kind: attempts.get(kind) for kind in ("release assets", "traffic", "clones")}
    private_attempt = attempts.get("community")
    source_attempts.update({"community": attempts.get(latest_community_attempt), "referrals": private_attempt,
                            "star history": private_attempt})
    access = None
    if latest_community_attempt or community:
        public = latest_community_attempt == "public community" if latest_community_attempt else community == public_community
        access = "public" if public else "authenticated"
    return {
        "repo": repo, "pattern": pattern,
        "collected_utc": observations[-1][2] if observations else None,
        "last_attempt": attempt, "attempts": attempts,
        "source_utc": source_utc, "source_attempts": source_attempts, "access": access,
        "assets": assets, "intervals": intervals, "release_age": milestones,
        "platform_history": [platform_history[d] for d in sorted(platform_history)], **extras,
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
    sources = model.get("source_utc")
    observed = sources.get("star history") if sources is not None else model.get("community_utc")
    if not observed and (sources is not None or not star_days and not model.get("counters")):
        return [None] * len(days)  # never collected: unknown, not zero
    last_day = _parse(observed).date().isoformat() if observed else None
    total = sum(n for d, n in star_days.items() if d < days[0]) if days else 0
    out = []
    for day in days:
        total += star_days.get(day, 0)
        out.append(None if last_day and day > last_day else total)
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


def release_milestones(model, tag):
    """An observation or None for each RELEASE_MILESTONES entry, independently of archive age."""
    return tuple((model.get("release_age") or {}).get(tag, [None] * len(RELEASE_MILESTONES)))


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
