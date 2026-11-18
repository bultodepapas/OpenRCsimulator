"""Deterministic weekly report built only from ID-free daily aggregates."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
import json
import re

from .contract import ContractError
from .rollup import VEHICLE_BASIS

WEEK_RE = re.compile(r"^[0-9]{4}-W[0-9]{2}$")
RELEASE_RE = re.compile(r"^v[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(-(alpha|beta|rc)\.?[0-9]{1,3})?\Z")
MAX_REPORT_BYTES = 32 * 1024
PUBLISH_AFTER_H = 25  # Sunday (last day) closed + 1 h


def parse_week(week):
    """'YYYY-Www' -> list of the seven ISO dates (Monday first)."""
    if not isinstance(week, str) or not WEEK_RE.fullmatch(week):
        raise ContractError("week")
    try:
        year, number = week.split("-W")
        monday = date.fromisocalendar(int(year), int(number), 1)
    except ValueError:
        raise ContractError("week") from None
    return [monday + timedelta(days=i) for i in range(7)]


def check_release(release_id):
    if not isinstance(release_id, str) or not RELEASE_RE.fullmatch(release_id):
        raise ContractError("release")
    return release_id


def week_closed(week, now):
    """True once the final Sunday has closed (+1 h) so that every day could be rolled up."""
    sunday = parse_week(week)[-1]
    start = datetime.combine(sunday, datetime.min.time(), tzinfo=timezone.utc)
    return datetime.fromtimestamp(now, tz=timezone.utc) >= start + timedelta(hours=PUBLISH_AFTER_H)


def report_key(week, release_id):
    return f"weekly-v1/{week}/{release_id}"


def report_title(week, release_id):
    return f"OpenRC telemetry: {week} / {release_id} / weekly GPU and vehicle v1"


def collect(contracts, agg, week, release_id):
    """Structured weekly data. Daily GPU reports are validated against the canonical schema."""
    days = parse_week(week)
    check_release(release_id)
    daily, gpu_pool, vehicle_pool = [], {}, {}
    for day in days:
        entry = {"day": day.isoformat()}
        for table in ("gpu", "vehicle"):
            found = agg.get_day(day.isoformat(), release_id, table)
            entry[table] = "missing" if found is None else found[0]
            if found is None or found[0] != "ready":
                continue
            rows = found[1]
            if table == "gpu":
                contracts.validate_report({
                    "report_version": 1, "aggregation_scope": "closed_day", "day": day.isoformat(),
                    "period": week, "release_id": release_id, "status": "ready",
                    "basis": "eligible_daily_session_observations", "rows": rows})
                for row in rows:
                    cell = gpu_pool.setdefault(row["gpu_family"], {"session_observations": 0,
                                                                   "interval_sum_us": 0, "rendered_frames": 0})
                    for name in cell:
                        cell[name] += row[name]
            else:
                for row in rows:
                    cell = vehicle_pool.setdefault(row["vehicle_id"], {"session_observations": 0,
                                                                       "activity_summaries": 0, "active_seconds": 0})
                    for name in cell:
                        cell[name] += row[name]
        daily.append(entry)
    return {
        "report_version": 1, "aggregation_scope": "closed_week", "week": week, "release_id": release_id,
        "first_day": days[0].isoformat(), "last_day": days[-1].isoformat(), "vehicle_basis": VEHICLE_BASIS,
        "days": daily,
        "gpu_rows": [{"gpu_family": k, **v} for k, v in sorted(gpu_pool.items())],
        "vehicle_rows": [{"vehicle_id": k, **v} for k, v in sorted(vehicle_pool.items())],
    }


def render(data):
    ready = lambda table: sum(1 for d in data["days"] if d[table] == "ready")  # noqa: E731
    lines = [
        f"<!-- openrc-telemetry:{report_key(data['week'], data['release_id'])} -->",
        "# OpenRC telemetry weekly summary",
        "",
        f"ISO week: {data['week']} ({data['first_day']} to {data['last_day']} UTC) · Release: {data['release_id']} · "
        f"Days with a published GPU table: {ready('gpu')} of 7",
        "",
        "Coverage: closed UTC days only; complete steady-flight windows with at least 30 s observed time and observed draw counts.",
        "This release-wide GPU table pools channels and other contexts; it cannot establish channel-specific or matched-settings regressions.",
        "Intervals over 5 s, including real foreground stalls, are excluded. This censored cadence estimate does not measure freeze incidence; gap counts are not in this table.",
        "Temporary sessions are not unique players or machines. FPS is an engine render-cadence estimate, not monitor presentation.",
        "Counts are contributing session-day observations: temporary sessions counted once per closed UTC day and cell, summed over the published days. They are not unique sessions, players, devices or the whole week's population.",
        "Suppressed (a cell below 20 session tokens), no-data and missing days are excluded and listed below.",
        "",
        "## Day coverage",
        "",
        "| UTC day | GPU table | Vehicle table |",
        "| --- | --- | --- |",
    ]
    for entry in data["days"]:
        lines.append(f"| {entry['day']} | {entry['gpu']} | {entry['vehicle']} |")
    lines.extend(["", "## GPU summary", ""])
    if data["gpu_rows"]:
        lines.extend(["| GPU family | Contributing session-day observations | Weighted FPS estimate |",
                      "| --- | ---: | ---: |"])
        for row in data["gpu_rows"]:
            fps = row["rendered_frames"] * 1_000_000 / row["interval_sum_us"]
            lines.append(f"| {row['gpu_family']} | {row['session_observations']} | {fps:.2f} |")
    else:
        lines.append("No GPU cells are published. This status is not a claim of zero players or zero FPS.")
    lines.extend(["", "## Stock vehicle usage", ""])
    if data["vehicle_rows"]:
        lines.extend(["| Vehicle | Contributing session-day observations | Activity summaries | Active time (hours) |",
                      "| --- | ---: | ---: | ---: |"])
        for row in data["vehicle_rows"]:
            lines.append(f"| {row['vehicle_id']} | {row['session_observations']} | {row['activity_summaries']} "
                         f"| {row['active_seconds'] / 3600:.2f} |")
        lines.append("")
        lines.append("Activity summaries are accepted activity closes or 30-minute slices, not successful flights or players.")
    else:
        lines.append("No vehicle cells are published. This status is not a claim of zero activity.")
    content = "\n".join(lines) + "\n"
    if len(content.encode("utf-8")) > MAX_REPORT_BYTES:
        raise ContractError("report_too_large")
    return content


def material(contracts, agg, week, release_id):
    """(title, body, digest). Digest = SHA-256 of compact sorted-key JSON of title+body."""
    data = collect(contracts, agg, week, release_id)
    title, body = report_title(week, release_id), render(data)
    return title, body, digest_of(title, body)


def digest_of(title, body):
    artifact = json.dumps({"title": title, "body": body}, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=False)
    return sha256(artifact.encode("utf-8")).hexdigest()
