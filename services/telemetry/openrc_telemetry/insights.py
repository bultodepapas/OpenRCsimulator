"""TELEM-16/17: ID-free daily cells for several context dimensions and a weekly operator report.

Rollup stores every daily cell with its distinct-session count in the operator-only aggregate database (no session
or batch identifier, no free text). Disclosure control happens when a week is reported: cells are pooled over the
closed days of the week and each cell is published only if it reaches the floor (default 20 session-day
observations). Cells below the floor are folded into one combined row when its proven session-day count reaches
the floor. The weekly computation uses a lower bound for combined cells that may share session-days.

Counts are session-day observations: a temporary session token is counted once per UTC day and cell.

Operator-only: tables share sessions (nested dimensions can still be differenced) and the weekly floor counts
session-days, not machines. Public summaries use the conservative report.py form, never both for one week.
"""
from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
import json
import re

from .contract import HISTOGRAM_UPPER_US, ContractError
from .report import (FIRST_ABOVE_33_MS, FIRST_ABOVE_50_MS, FIRST_ABOVE_100_MS, check_release, parse_week,
                     week_closed)
from .rollup import MIN_TOKENS, WINDOW_CAP, unique_events

PRIVATE_MIN_FLOOR = 10  # operator-only reports may go down to 10; anything published publicly uses MIN_TOKENS
HIST_LEN = len(HISTOGRAM_UPPER_US)
VALUE_RE = re.compile(r"^[a-z0-9][a-z0-9_.:-]{0,47}$")
MAX_REPORT_BYTES = 48 * 1024


def cap_class(context):
    """Whether frame pacing is limited by VSync or an FPS cap (the refresh rate is not reported, so the limit itself is
    unknown); `unlimited` only when VSync is off and no cap is set."""
    vsync, cap = context["vsync"], context["fps_cap_bucket"]
    if vsync in ("on", "adaptive", "mailbox") or cap in ("le30", "31_60", "61_120", "121_plus"):
        return "vsync_or_fps_cap"
    if vsync == "off" and cap == "unlimited":
        return "unlimited"
    return "unknown"


# Cadence tables: complete steady windows with observed draw counts.
FLIGHT_TABLES = {
    "flight_gpu": ("GPU family", lambda c, e: (c["gpu_family"],)),
    "flight_pacing": ("Frame pacing limit", lambda c, e: (cap_class(c),)),
    "flight_resolution": ("Resolution class", lambda c, e: (c["resolution_class"],)),
    "flight_platform": ("OS / graphics driver", lambda c, e: (c["os_family"], c["driver"])),
    "flight_vehicle": ("Vehicle", lambda c, e: (e["vehicle_id"],)),
}
MENU_TABLE = ("menus", "Screen", lambda c, e: (e["mode"],))
# Session mix tables: every session seen that day, once per cell.
MIX_TABLES = {
    "mix_os": ("OS", lambda c: (c["os_family"], c["architecture"])),
    "mix_cpu": ("CPU family / threads", lambda c: (c["cpu_family"], c["logical_threads_bucket"])),
    "mix_ram": ("RAM (GiB)", lambda c: (c["ram_gib_bucket"],)),
    "mix_gpu": ("GPU family", lambda c: (c["gpu_family"],)),
    "mix_renderer": ("Renderer / driver", lambda c: (c["renderer"], c["driver"])),
    "mix_display": ("Resolution class", lambda c: (c["resolution_class"],)),
    "mix_pacing": ("Frame pacing limit", lambda c: (cap_class(c),)),
    "mix_graphics": ("Graphics settings", lambda c: (c["graphics_profile"],)),
    "mix_input": ("Input", lambda c: (c["input_class"],)),
}
USAGE_TABLE, ERROR_TABLE = "usage_vehicle", "errors"
# Schema v2 (2026-11-20): which physics backend each activity ran; v1 summaries count as "unknown".
BACKEND_TABLE = "usage_backend"
CADENCE_METRICS = ("windows", "interval_sum_us", "rendered_frames", "interval_count", "excluded_gap_count")
USAGE_METRICS = ("summaries", "complete_summaries", "active_seconds", "simulated_seconds", "classified_summaries",
                 "takeoffs", "landings", "aircraft_crashes")
TITLES = {**{k: v[0] for k, v in FLIGHT_TABLES.items()}, MENU_TABLE[0]: MENU_TABLE[1],
          **{k: v[0] for k, v in MIX_TABLES.items()}, USAGE_TABLE: "Vehicle",
          BACKEND_TABLE: "Vehicle / physics backend", ERROR_TABLE: "Error category"}
KINDS = {**{k: "cadence" for k in FLIGHT_TABLES}, MENU_TABLE[0]: "cadence", **{k: "mix" for k in MIX_TABLES},
         USAGE_TABLE: "usage", BACKEND_TABLE: "usage", ERROR_TABLE: "errors"}


def _metric_names(table):
    kind = KINDS[table]
    if kind == "cadence":
        return CADENCE_METRICS + tuple(f"hist{i}" for i in range(HIST_LEN))
    if kind == "usage":
        return USAGE_METRICS
    if kind == "errors":
        return ("count",)
    return ()


def daily_cells(payloads):
    """[(table, dims_tuple, sessions, metrics_dict)] for one closed day and one release. Input is validated payloads."""
    cells = {}

    def cell(table, dims):
        key = (table, dims)
        if key not in cells:
            cells[key] = {"sessions": set(), "metrics": dict.fromkeys(_metric_names(table), 0), "per_session": {}}
        return cells[key]

    for payload in payloads:
        context, session = payload["context"], payload["session_id"]
        for table, (_title, dims_of) in MIX_TABLES.items():
            cell(table, dims_of(context))["sessions"].add(session)
    for payload, event in unique_events(payloads):
        context, session, name = payload["context"], payload["session_id"], event["name"]
        if name == "performance_window":
            if (event["phase"] != "steady" or not event["window_complete"]
                    or event["draw_counter_status"] != "observed"):
                continue
            if event["mode"] == "flight":
                targets = [(t, dims_of(context, event)) for t, (_title, dims_of) in FLIGHT_TABLES.items()]
            else:
                targets = [(MENU_TABLE[0], MENU_TABLE[2](context, event))]
            for table, dims in targets:
                entry = cell(table, dims)
                seen = entry["per_session"].get(session, 0)
                if seen >= WINDOW_CAP:
                    continue
                entry["per_session"][session] = seen + 1
                entry["sessions"].add(session)
                m = entry["metrics"]
                m["windows"] += 1
                m["interval_sum_us"] += int(event["interval_sum_us"])
                m["rendered_frames"] += int(event["rendered_frames"])
                m["interval_count"] += int(event["interval_count"])
                m["excluded_gap_count"] += int(event["excluded_gap_count"])
                for i, count in enumerate(event["interval_histogram"]):
                    m[f"hist{i}"] += int(count)
        elif name == "activity_summary":
            backend = event.get("physics_backend", "unknown")
            for table, dims in ((USAGE_TABLE, (event["vehicle_id"],)), (BACKEND_TABLE, (event["vehicle_id"], backend))):
                entry = cell(table, dims)
                seen = entry["per_session"].get(session, 0)
                if seen >= WINDOW_CAP:
                    continue
                entry["per_session"][session] = seen + 1
                entry["sessions"].add(session)
                m = entry["metrics"]
                m["summaries"] += 1
                m["complete_summaries"] += 1 if event["complete_observation"] else 0
                m["active_seconds"] += int(event["active_seconds"])
                m["simulated_seconds"] += int(event["simulated_seconds"])
                if event["classification"] == "accepted_fixed_wing":
                    m["classified_summaries"] += 1
                    for field in ("takeoffs", "landings", "aircraft_crashes"):
                        m[field] += int(event[field] or 0)
        elif name == "error_count":
            entry = cell(ERROR_TABLE, (event["category"],))
            entry["sessions"].add(session)
            entry["metrics"]["count"] += int(event["count"])
    return [(table, dims, len(entry["sessions"]), entry["metrics"])
            for (table, dims), entry in sorted(cells.items()) if entry["sessions"]]


def validate_cell(table, dims, sessions, metrics):
    """Bounds for a stored cell; a corrupt or foreign row is refused instead of reported."""
    if table not in KINDS or type(sessions) is not int or not 1 <= sessions <= 10**9:
        raise ContractError("insight_cell")
    if (not isinstance(dims, (list, tuple)) or not 1 <= len(dims) <= 3
            or not all(isinstance(v, str) and VALUE_RE.fullmatch(v) for v in dims)):
        raise ContractError("insight_cell")
    names = _metric_names(table)
    if not isinstance(metrics, dict) or set(metrics) != set(names):
        raise ContractError("insight_cell")
    if any(type(metrics[n]) is not int or not 0 <= metrics[n] <= 10**15 for n in names):
        raise ContractError("insight_cell")
    if KINDS[table] == "cadence":
        hist = sum(metrics[f"hist{i}"] for i in range(HIST_LEN))
        if hist != metrics["interval_count"] or metrics["windows"] < 1 or metrics["interval_sum_us"] < 1:
            raise ContractError("insight_cell")


def encode_cells(cells):
    """Storage form: [(table, dims_json, sessions, metrics_json)]."""
    out = []
    for table, dims, sessions, metrics in cells:
        validate_cell(table, list(dims), sessions, metrics)
        out.append((table, json.dumps(list(dims), separators=(",", ":")), sessions,
                    json.dumps(metrics, sort_keys=True, separators=(",", ":"))))
    return out


def _pool(daily_rows):
    """Pool each cell over receipt days while keeping daily counts for disclosure."""
    pooled = {}
    for day, rows in daily_rows.items():
        for table, dims_json, sessions, metrics_json in rows:
            dims, metrics = json.loads(dims_json), json.loads(metrics_json)
            validate_cell(table, dims, sessions, metrics)
            entry = pooled.setdefault(table, {}).setdefault(tuple(dims), {
                "sessions": 0, "sessions_by_day": {}, "metrics": dict.fromkeys(_metric_names(table), 0)})
            entry["sessions"] += sessions
            entry["sessions_by_day"][day] = sessions
            for name, value in metrics.items():
                entry["metrics"][name] += value
    return pooled


def _combined_session_floor(rows):
    # A token can appear in several cells on one day, even for context fields from different batches.
    # Each day's union contains at least its largest cell. Different days contribute separate session-days.
    largest = {}
    for row in rows:
        for day, count in row["sessions_by_day"].items():
            largest[day] = max(largest.get(day, 0), count)
    return sum(largest.values())


def _disclose(cells, floor):
    """Disclose a complete set of cells, with small cells folded together, or withhold the table."""
    rows = sorted(({"dims": list(dims), **entry} for dims, entry in cells.items()),
                  key=lambda row: (row["sessions"], row["dims"]))
    published = [row for row in rows if row["sessions"] >= floor]
    small = [row for row in rows if row["sessions"] < floor]
    combined = None
    if small:
        sessions = _combined_session_floor(small)
        if sessions < floor or len(small) < 2:
            if not published:
                return [], None
            small.append(published.pop(0))  # one already eligible row is enough to clear the floor
            sessions = _combined_session_floor(small)
        metrics = dict.fromkeys(small[0]["metrics"], 0)
        for row in small:
            for name, value in row["metrics"].items():
                metrics[name] += value
        combined = {"dims": ["combined small cells"], "sessions": sessions, "metrics": metrics}
        if sessions < sum(row["sessions"] for row in small):
            combined["sessions_lower_bound"] = True
    # Day-level marginals stay internal. Published named cells contain their exact per-cell counts.
    for row in published:
        del row["sessions_by_day"]
    return sorted(published, key=lambda row: row["dims"]), combined


def collect(agg, week, release_id, floor=MIN_TOKENS, *, now=None):
    if type(floor) is not int or floor < PRIVATE_MIN_FLOOR:
        raise ContractError("cohort_floor")
    days = [d.isoformat() for d in parse_week(week)]
    check_release(release_id)
    rows, covered = {}, []
    for day in days:
        status = agg.cells_status(day, release_id)
        covered.append({"day": day, "status": status or "missing"})
        if status == "ready":
            rows[day] = agg.get_cells(day, release_id)
    tables = {}
    for table, cells in _pool(rows).items():
        published, combined = _disclose(cells, floor)
        if published or combined:
            tables[table] = {"published": published, "combined": combined}
    return {"insights_version": 2, "week": week, "release_id": release_id, "floor": floor,
            "week_closed": week_closed(week, now if now is not None else datetime.now(timezone.utc).timestamp()),
            "days": covered, "tables": tables}


def _cadence_columns(m):
    total = sum(m[f"hist{i}"] for i in range(HIST_LEN)) or 1
    over = lambda first: sum(m[f"hist{i}"] for i in range(first, HIST_LEN))  # noqa: E731
    fps = m["rendered_frames"] * 1_000_000 / m["interval_sum_us"]
    hitches = over(FIRST_ABOVE_100_MS) * 60_000_000 / m["interval_sum_us"]
    minutes = m["interval_sum_us"] / 60_000_000
    return (f"{minutes:.0f}", f"{fps:.1f}", f"{100 * over(FIRST_ABOVE_33_MS) / total:.1f}%",
            f"{100 * over(FIRST_ABOVE_50_MS) / total:.1f}%", f"{hitches:.2f}")


def _row_cells(kind, row):
    m, label = row["metrics"], " / ".join(row["dims"])
    sessions = str(row["sessions"])
    if row.get("sessions_lower_bound"):
        sessions = f"≥ {sessions}"
    if kind == "cadence":
        return [label, sessions, *_cadence_columns(m)]
    if kind == "usage":
        hours = m["active_seconds"] / 3600
        rates = "-"
        if m["classified_summaries"]:
            rates = f"{m['takeoffs']} / {m['landings']} / {m['aircraft_crashes']}"
        return [label, sessions, str(m["summaries"]), f"{hours:.1f}", rates]
    if kind == "errors":
        return [label, sessions, str(m["count"])]
    return [label, sessions]


HEADERS = {
    "cadence": ["{title}", "Session-days", "Observed minutes", "FPS estimate", "Intervals > 33.3 ms",
                "Intervals > 50 ms", "Intervals > 100 ms per minute"],
    "usage": ["{title}", "Session-days", "Activity summaries", "Active hours", "Takeoffs / landings / crashes"],
    "errors": ["{title}", "Session-days", "Occurrences"],
    "mix": ["{title}", "Session-days"],
}
SECTIONS = [
    ("Flight frame cadence", list(FLIGHT_TABLES)),
    ("Menu and workshop frame cadence", [MENU_TABLE[0]]),
    ("Vehicle usage", [USAGE_TABLE, BACKEND_TABLE]),
    ("Software errors", [ERROR_TABLE]),
    ("Hardware and settings mix", list(MIX_TABLES)),
]


def render(data):
    ready = sum(1 for d in data["days"] if d["status"] == "ready")
    lines = [
        f"<!-- openrc-telemetry:insights-v{data['insights_version']}/{data['week']}/{data['release_id']} -->",
        "# OpenRC telemetry weekly insights",
        "",
        f"ISO week: {data['week']} · Release: {data['release_id']} · Rolled-up days: {ready} of 7"
        f"{'' if data['week_closed'] else ' · week still open (figures can change)'} · Cell floor: {data['floor']}",
        "",
        "**Operator-only report: do not publish.** Its tables share the same sessions, so comparing tables can "
        "reveal small groups, and the floor counts session-days (a new temporary session starts at each launch, "
        "every UTC day and every four hours), so one very active player can fill a cell. Public summaries use the "
        "conservative weekly report instead, never both for the same week.",
        "",
        "Counts are session-day observations, not players or machines; observations cover consenting sessions only "
        f"and are not representative. A cell is shown with at least {data['floor']} session-days; smaller cells, "
        "with the smallest shown cell when needed, form one combined row, and a table below the floor is not shown. "
        "A combined count marked ≥ is a lower bound. Individual cells can share session-days. "
        "FPS is an engine render-cadence estimate; intervals over 5 s are excluded, so these figures understate "
        "freezes. VSync or an FPS cap limits cadence by design: compare rows within the same frame-pacing class.",
    ]
    if data["floor"] < MIN_TOKENS:
        lines += ["", f"**Private floor {data['floor']} (below the public floor of {MIN_TOKENS}): do not publish "
                  "this report outside the operations repository.**"]
    lines += ["", "## Day coverage", "", "| UTC day | Cells |", "| --- | --- |"]
    lines += [f"| {d['day']} | {d['status']} |" for d in data["days"]]
    for heading, tables in SECTIONS:
        lines += ["", f"## {heading}"]
        for table in tables:
            kind, title = KINDS[table], TITLES[table]
            entry = data["tables"].get(table)
            lines += ["", f"### {title}" if len(tables) > 1 else f"_{title}_", ""]
            rows = [] if entry is None else entry["published"] + ([entry["combined"]] if entry["combined"] else [])
            if not rows:
                lines.append("Nothing to show at this floor this week.")
                continue
            header = [h.format(title=title) for h in HEADERS[kind]]
            lines += ["| " + " | ".join(header) + " |",
                      "| --- | " + " | ".join("---:" for _ in header[1:]) + " |"]
            lines += ["| " + " | ".join(_row_cells(kind, row)) + " |" for row in rows]
    content = "\n".join(lines) + "\n"
    if len(content.encode("utf-8")) > MAX_REPORT_BYTES:
        raise ContractError("report_too_large")
    return content


def material(agg, week, release_id, floor=MIN_TOKENS, *, now=None):
    """(title, body, digest, data)."""
    data = collect(agg, week, release_id, floor, now=now)
    title = f"OpenRC telemetry insights: {week} / {release_id}"
    body = render(data)
    artifact = json.dumps({"title": title, "body": body}, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return title, body, sha256(artifact.encode("utf-8")).hexdigest(), data
