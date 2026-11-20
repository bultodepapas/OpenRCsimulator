"""Daily rollup of one closed day. Ports reference.aggregate_daily_gpu and adds a stock vehicle table.

Output rows are ID-free. GPU rows also sum the 8-bucket frame-interval histogram and excluded gaps. Whole tables are suppressed when any cell has fewer than 20 distinct
ephemeral session tokens.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from hashlib import sha256

from .contract import HISTOGRAM_UPPER_US, ContractError, encode

MIN_TOKENS = 20
WINDOW_CAP = 120
ELIGIBLE_AFTER_H = 25   # day close + 1 h
EXPIRES_AFTER_H = 47    # raw data still guaranteed complete
VEHICLE_BASIS = "eligible_daily_vehicle_observations"


def day_bounds(day):
    try:
        closed = date.fromisoformat(day)
        if closed.isoformat() != day:
            raise ValueError
    except (ValueError, TypeError):
        raise ContractError("day_not_eligible") from None
    start = datetime.combine(closed, datetime.min.time(), tzinfo=timezone.utc)
    return closed, start


def check_eligible(day, as_of_utc):
    """Return (date, 'YYYY-Www'). Rollup runs from day close + 1 h until day start + 47 h."""
    closed, start = day_bounds(day)
    try:
        current = datetime.fromisoformat(as_of_utc.replace("Z", "+00:00"))
        if (current.utcoffset() != timedelta(0) or
                not start + timedelta(hours=ELIGIBLE_AFTER_H) <= current < start + timedelta(hours=EXPIRES_AFTER_H)):
            raise ValueError
    except (ValueError, TypeError, AttributeError, OverflowError):
        raise ContractError("day_not_eligible") from None
    iso = closed.isocalendar()
    return closed, f"{iso.year:04d}-W{iso.week:02d}"


def utc_iso(unix):
    return datetime.fromtimestamp(unix, tz=timezone.utc).isoformat()


def eligibility_window(day):
    _, start = day_bounds(day)
    return (start + timedelta(hours=ELIGIBLE_AFTER_H), start + timedelta(hours=EXPIRES_AFTER_H))


def unique_events(payloads):
    """Yield (payload, event) once per (session, seq); a differing duplicate is an error."""
    seen = {}
    for payload in payloads:
        session = payload["session_id"]
        for event in payload["events"]:
            key = (session, event["seq"])
            digest = sha256(encode([payload["build"], payload["context"], event])).digest()
            if key in seen:
                if seen[key] != digest:
                    raise ContractError("conflicting_event")
                continue
            seen[key] = digest
            yield payload, event


def gpu_report(contracts, payloads, day, release_id, period, minimum=MIN_TOKENS):
    groups, counts = {}, {}
    for payload, event in unique_events(payloads):
        if (event["name"] != "performance_window" or event["mode"] != "flight" or
                event["phase"] != "steady" or not event["window_complete"] or
                event["draw_counter_status"] != "observed"):
            continue
        session = payload["session_id"]
        if counts.get(session, 0) >= WINDOW_CAP:
            continue
        counts[session] = counts.get(session, 0) + 1
        group = groups.setdefault(payload["context"]["gpu_family"], {
            "sessions": set(), "time": 0, "frames": 0, "intervals": 0, "gaps": 0,
            "histogram": [0] * len(HISTOGRAM_UPPER_US)})
        group["sessions"].add(session)
        group["time"] += event["interval_sum_us"]
        group["frames"] += event["rendered_frames"]
        group["intervals"] += event["interval_count"]
        group["gaps"] += event["excluded_gap_count"]
        group["histogram"] = [a + b for a, b in zip(group["histogram"], event["interval_histogram"])]
    status = "no_data" if not groups else "ready"
    if any(len(group["sessions"]) < minimum for group in groups.values()):
        status = "suppressed"
    rows = []
    if status == "ready":
        for family, group in sorted(groups.items()):
            if sum(group["histogram"]) != group["intervals"]:
                raise ContractError("report_histogram")  # validate_body already guarantees it per window
            rows.append({"gpu_family": family, "session_observations": len(group["sessions"]),
                         "interval_sum_us": group["time"], "rendered_frames": group["frames"],
                         "interval_histogram": group["histogram"], "excluded_gap_count": group["gaps"]})
    report = {"report_version": 2, "aggregation_scope": "closed_day", "day": day, "period": period,
              "release_id": release_id, "status": status, "basis": "eligible_daily_session_observations",
              "rows": rows}
    contracts.validate_report(report)
    return report


def vehicle_report(payloads, day, release_id, period, minimum=MIN_TOKENS):
    """Stock vehicle usage: activity_summary count and summed active_seconds per vehicle_id."""
    if minimum < MIN_TOKENS:
        raise ContractError("cohort_floor")  # the disclosure floor can be raised, never lowered
    groups, counts = {}, {}
    for payload, event in unique_events(payloads):
        if event["name"] != "activity_summary":
            continue
        session = payload["session_id"]
        if counts.get(session, 0) >= WINDOW_CAP:
            continue
        counts[session] = counts.get(session, 0) + 1
        group = groups.setdefault(event["vehicle_id"], {"sessions": set(), "count": 0, "seconds": 0})
        group["sessions"].add(session)
        group["count"] += 1
        group["seconds"] += event["active_seconds"]
    status = "no_data" if not groups else "ready"
    if any(len(group["sessions"]) < minimum for group in groups.values()):
        status = "suppressed"
    rows = [] if status != "ready" else [
        {"vehicle_id": vehicle, "session_observations": len(group["sessions"]),
         "activity_summaries": group["count"], "active_seconds": group["seconds"]}
        for vehicle, group in sorted(groups.items())]
    report = {"report_version": 1, "aggregation_scope": "closed_day", "day": day, "period": period,
              "release_id": release_id, "status": status, "basis": VEHICLE_BASIS, "rows": rows}
    for row in rows:
        sessions = row["session_observations"]
        if (sessions < minimum or row["activity_summaries"] < sessions or
                row["activity_summaries"] > sessions * WINDOW_CAP or
                row["active_seconds"] > row["activity_summaries"] * 1800):
            raise ContractError("report_exposure")
    return report


def _validated(contracts, records, day, release_id):
    payloads = []
    for receipt_day, body in records:
        if receipt_day != day:
            raise ContractError("mixed_receipt_day")
        payload = contracts.validate_body(body)
        if payload["build"]["release_id"] != release_id:
            raise ContractError("mixed_release")
        payloads.append(payload)
    return payloads


def aggregate_daily_gpu(contracts, records, day, release_id, minimum=MIN_TOKENS, *, as_of_utc):
    """Same contract as reference.aggregate_daily_gpu(records, day, release_id, minimum, as_of_utc=...)."""
    if type(minimum) is not int or minimum < MIN_TOKENS:
        raise ContractError("cohort_floor")
    _, period = check_eligible(day, as_of_utc)
    # Validate even a no-data request before consuming any record iterator.
    contracts.validate_report({"report_version": 2, "aggregation_scope": "closed_day", "day": day,
                               "period": period, "release_id": release_id, "status": "no_data",
                               "basis": "eligible_daily_session_observations", "rows": []})
    return gpu_report(contracts, _validated(contracts, records, day, release_id), day, release_id, period, minimum)


def run_rollup(contracts, raw, agg, day, now, releases):
    """Roll up one closed day for every release seen in the data plus the configured allowlist.

    Returns [(release_id, table, status)]. Refuses a day that is not closed or no longer complete.
    """
    as_of = utc_iso(now)
    _, period = check_eligible(day, as_of)
    by_release = {}
    for receipt_day, body in raw.records_for_day(day):
        payload = contracts.validate_body(body)
        by_release.setdefault(payload["build"]["release_id"], []).append(payload)
    from .insights import daily_cells, encode_cells  # insights imports this module
    results = []
    for release_id in sorted(set(by_release) | {r for r in releases if "*" not in r}):
        payloads = by_release.get(release_id, [])
        # Compute and validate everything before any write, so a refusal never leaves a half-rolled day.
        reports = {"gpu": gpu_report(contracts, payloads, day, release_id, period),
                   "vehicle": vehicle_report(payloads, day, release_id, period)}
        cells = encode_cells(daily_cells(payloads))
        for table, report in reports.items():
            agg.put_day(day, release_id, table, report["status"], report["rows"], now)
            results.append((release_id, table, report["status"]))
        agg.put_cells(day, release_id, cells, now)
        results.append((release_id, "cells", f"ready ({len(cells)} cells)" if cells else "no_data"))
    return results
