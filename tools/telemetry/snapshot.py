"""Read-only operator snapshot of the telemetry receiver, printed as JSON.

Runs on the receiver host with the deployed service package importable (current directory
`services/telemetry`, the service venv and the service's OPENRC_TELEMETRY_* environment). It uses only the
package's public read paths: `status_report`, `AggStore.ingest_counts`, `AggStore.day_statuses` and
`insights.collect`, so every insight cell has passed the same per-cell disclosure floor as the weekly operator
report. No session or batch identifier, raw body or address is read or printed. It refuses to run unless both
databases already exist, so a wrong data directory never creates empty stores.

    python snapshot.py [--days 30] [--weeks 4] [--floor 20]

`tools/telemetry/dashboard.py fetch` pipes this file to the receiver over SSH.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
import re
import sys
import time

from openrc_telemetry import insights
from openrc_telemetry.cli import status_report
from openrc_telemetry.config import Config
from openrc_telemetry.contract import ContractError
from openrc_telemetry.storage import AggStore, RawStore, StorageUnavailable

SNAPSHOT_VERSION = 2
RELEASE_KEY_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.?(\d+))?$")
PRE_RANK = {"alpha": 0, "beta": 1, "rc": 2}


def release_key(release):
    """Semantic order: v0.3.10 after v0.3.9, a final release after its pre-releases; unknown forms last."""
    match = RELEASE_KEY_RE.match(release)
    if not match:
        return (-1, -1, -1, -1, -1, release)
    major, minor, patch, pre, number = match.groups()
    rank = (PRE_RANK[pre], int(number)) if pre else (9, 0)
    return (int(major), int(minor), int(patch), *rank, release)


def _iso_week(day):
    year, week, _ = day.isocalendar()
    return f"{year}-W{week:02d}"


def collect(config, now, days=30, weeks=4, floor=20):
    for path in (config.raw_path, config.aggregates_path):
        if not path.is_file():
            raise FileNotFoundError(f"receiver database not found: {path} (check OPENRC_TELEMETRY_* paths)")
    raw = RawStore(config.raw_path, config.max_raw_bytes)
    agg = AggStore(config.aggregates_path)
    try:
        today = datetime.fromtimestamp(int(now), tz=timezone.utc).date()
        # Release discovery reaches back over every reported week, not only the ingest window.
        lookback = max(days, 7 * weeks + 7)
        ingest, coverage, releases = [], [], set()
        for offset in range(lookback - 1, -1, -1):
            iso = (today - timedelta(days=offset)).isoformat()
            in_window = offset < days
            if in_window:
                ingest.append({"day": iso, "counts": agg.ingest_counts(iso)})
            for key, status in agg.day_statuses(iso).items():
                release, table = key.split("/", 1)
                if in_window:
                    coverage.append({"day": iso, "release_id": release, "table": table, "status": status})
                if table == "cells":
                    releases.add(release)
        ordered = sorted(releases, key=release_key, reverse=True)
        week_ids = sorted({_iso_week(today - timedelta(weeks=offset)) for offset in range(weeks)}, reverse=True)
        reports = []
        for week in week_ids:
            for release in ordered:
                try:
                    data = insights.collect(agg, week, release, floor, now=now)
                except ContractError as error:
                    reports.append({"week": week, "release_id": release, "error": str(error)})
                    continue
                if any(d["status"] != "missing" for d in data["days"]):
                    reports.append(data)
        return {
            "snapshot_version": SNAPSHOT_VERSION, "generated_unix": int(now), "days": days, "weeks": weeks,
            "floor": floor, "status": status_report(config, now, raw, agg), "ingest": ingest,
            "coverage": coverage, "releases_with_cells": ordered, "insights": reports,
        }
    finally:
        raw.close()
        agg.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--days", type=int, default=30, help="ingest and coverage history in UTC days (1-180)")
    parser.add_argument("--weeks", type=int, default=4, help="recent ISO weeks of insights (1-25)")
    parser.add_argument("--floor", type=int, default=20, help="insight cell floor (>= 10, as the insights command)")
    args = parser.parse_args(argv)
    if not 1 <= args.days <= 180 or not 1 <= args.weeks <= 25 or args.floor < insights.PRIVATE_MIN_FLOOR:
        parser.error(f"--days must be 1-180, --weeks 1-25 and --floor >= {insights.PRIVATE_MIN_FLOOR}")
    try:
        result = collect(Config.from_env(), time.time(), args.days, args.weeks, args.floor)
    except FileNotFoundError as error:
        print(f"snapshot refused: {error}", file=sys.stderr)
        return 3
    except StorageUnavailable as error:
        print(f"snapshot refused: storage unavailable ({error})", file=sys.stderr)
        return 3
    json.dump(result, sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
