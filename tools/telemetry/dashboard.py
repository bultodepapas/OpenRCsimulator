"""Operator statistics dashboard: players (telemetry), downloads, GitHub, website and receiver health in one page.

    python tools/telemetry/dashboard.py fetch  --ssh root@<receiver-host> [--key <identity>] [--ct 404]
    python tools/telemetry/dashboard.py render --snapshot <dashboard.snapshot.json>

`fetch` pipes `snapshot.py` to the receiver (Proxmox `pct exec` into the receiver container, or directly with
`--ct ''`), adds the GitHub archive and the GA4 website reports (ga4.py, when a credential is configured), saves
the JSON beside the page and renders it. `render` rebuilds the page from a saved snapshot. The
page is self-contained (no network requests) and is written to a local directory outside the repository, never
published: insight cells are operator-only (see services/telemetry/README.md). Standard library only.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
import html
import json
import math
import os
from pathlib import Path
import shlex
import sqlite3
import subprocess
import sys
import tempfile
import time
import webbrowser

import ga4
import github_archive as downloads

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
REMOTE_ROOT = "/opt/openrc-telemetry/current"
REMOTE_ENV = "/etc/openrc-telemetry/env"
SNAPSHOT_VERSIONS = {1, 2}
# contract.HISTOGRAM_UPPER_US = (8333, 16667, 33333, 50000, 100000, 250000, 1000000, 5000000): buckets from these
# indices up lie wholly above 33.3 / 50 / 100 ms (same rule as report.py).
ABOVE_33_MS, ABOVE_50_MS, ABOVE_100_MS = 3, 4, 5
HIST_LEN = 8
# rollup.py: a UTC day can be rolled up from day start + 25 h until day start + 47 h; cron runs at 01:30.
ELIGIBLE_AFTER_H, EXPIRES_AFTER_H, OVERDUE_AFTER_H = 25, 47, 27
RAW_TTL_H = 48
STALE_AFTER_S = 3600
DOWNLOADS_STALE_S = 12 * 3600
GA4_MAX_AGE_S = 2 * 3600
PLATFORM_SLOTS = (("Windows", "s1"), ("macOS", "s2"), ("Linux", "s3"), ("Other", "s4"))

# Ingest outcome series (fixed order = fixed categorical slot).
INGEST_SERIES = [
    ("accepted", "Accepted", "s1"),
    ("duplicate", "Duplicate replay", "s2"),
    ("rejected", "Rejected (validation)", "s3"),
    ("other", "Other refusals", "s4"),
]
NOT_OUTCOMES = {"forwarded_for_present"}
INGRESS_INTERRUPTION = {"rate_limited", "storage_unavailable", "suspended_all", "suspended_release",
                        "rejected:unapproved_release"}
FLIGHT_TABLES = [("flight_gpu", "GPU family"), ("flight_pacing", "Frame pacing limit"),
                 ("flight_resolution", "Resolution class"), ("flight_platform", "OS / graphics driver"),
                 ("flight_vehicle", "Vehicle")]
MIX_TABLES = [("mix_os", "OS / architecture"), ("mix_cpu", "CPU family / threads"), ("mix_ram", "RAM (GiB)"),
              ("mix_gpu", "GPU family"), ("mix_renderer", "Renderer / driver"), ("mix_display", "Resolution class"),
              ("mix_pacing", "Frame pacing limit"), ("mix_graphics", "Graphics settings"), ("mix_input", "Input")]
# Coverage state -> (css class, glyph, label). Stored statuses first, then derived ones for days without a row.
STATES = {
    "ready": ("good", "\u2713", "ready"),
    "no_data": ("muted", "\u2013", "no data"),
    "suppressed": ("warning", "!", "suppressed"),
    "pending": ("neutral", "\u2026", "pending (not yet eligible)"),
    "partial": ("warning", "!", "incomplete rollup"),
    "overdue": ("warning", "!", "overdue (still fixable)"),
    "missed": ("critical", "\u2716", "missed (traffic, never rolled up)"),
    "none": ("neutral", "\u00b7", "no accepted batches"),
    "unknown": ("neutral", "?", "coverage unknown"),
}
LEVELS = {"critical": (0, "\u2716"), "warning": (1, "!"), "info": (2, "i"), "good": (3, "\u2713")}

e = html.escape


# ---------------------------------------------------------------------------------------------- fetch


def remote_command(ct, root, env_file, days, weeks, floor):
    """Shell command run on the SSH host. Only OPENRC_TELEMETRY_* lines of the service environment are exported
    to the snapshot process (tokens such as GITHUB_TOKEN stay out)."""
    inner = (f"cd {shlex.quote(root + '/services/telemetry')} && set -a && "
             f". <(grep -E '^(export )?OPENRC_TELEMETRY_[A-Z0-9_]+=' {shlex.quote(env_file)}) && set +a && "
             f"exec runuser -u telemetry -- {shlex.quote(root + '/venv/bin/python')} - "
             f"--days {int(days)} --weeks {int(weeks)} --floor {int(floor)}")
    return f"pct exec {int(ct)} -- bash -c {shlex.quote(inner)}" if ct else f"bash -c {shlex.quote(inner)}"


def snapshot_path(out):
    return out.with_name(out.stem + ".snapshot.json")


def fetch(args, out):
    command = ["ssh", "-o", "BatchMode=yes", "-o", f"ConnectTimeout={args.timeout}"]
    if args.key:
        command += ["-i", os.path.expanduser(args.key)]
    command += ["--", args.ssh, remote_command(args.ct, args.remote_root, args.remote_env, args.days, args.weeks,
                                               args.floor)]
    try:
        result = subprocess.run(command, input=(HERE / "snapshot.py").read_bytes(), capture_output=True,
                                timeout=args.timeout + 120)
    except subprocess.TimeoutExpired:
        raise SystemExit("snapshot timed out (SSH or receiver not responding)") from None
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode("utf-8", "replace")[-4000:])
        raise SystemExit(f"snapshot failed (exit {result.returncode})")
    try:
        snapshot = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise SystemExit("snapshot output is not JSON (check the remote command)") from None
    snapshot_path(out).write_text(json.dumps(snapshot, indent=1, sort_keys=True), encoding="utf-8")
    return snapshot


# ---------------------------------------------------------------------------------------------- formatting


def fmt_int(n):
    return f"{n:,}"


def fmt_compact(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M".replace(".0M", "M")
    if n >= 10_000:
        return f"{n / 1000:.0f}K"
    return f"{n:,}"


def fmt_age(seconds):
    if seconds is None:
        return "never"
    if seconds < 90:
        return f"{seconds} s ago"
    if seconds < 5400:
        return f"{seconds // 60} min ago"
    if seconds < 172800:
        return f"{seconds / 3600:.1f} h ago"
    return f"{seconds / 86400:.1f} days ago"


def nice_ticks(maximum, count=4):
    if maximum <= 0:
        return [0, 1]
    raw = maximum / count
    magnitude = 10 ** (len(str(int(raw))) - 1) if raw >= 1 else 1
    for step in (1, 2, 5, 10):
        if step * magnitude >= raw:
            step = step * magnitude
            break
    step = max(1, int(step))
    top = step * -(-maximum // step)
    return list(range(0, int(top) + 1, step))


def rounded_top(x, y, w, h, r=4):
    """Column path with a rounded data-end at the top and a square baseline."""
    r = min(r, w / 2, h)
    return (f"M{x:.1f},{y + h:.1f}V{y + r:.1f}Q{x:.1f},{y:.1f} {x + r:.1f},{y:.1f}H{x + w - r:.1f}"
            f"Q{x + w:.1f},{y:.1f} {x + w:.1f},{y + r:.1f}V{y + h:.1f}Z")


def tip_attrs(lines, role="img", *, tab_index=0):
    """Hover/focus/tap target attributes: tooltip text plus the same text for assistive technology."""
    text = e("\n".join(lines), quote=True)
    label = f' role="{role}" aria-label="{e(" · ".join(lines), quote=True)}"' if role else ""
    return f'tabindex="{tab_index}"{label} data-tip="{text}"'


def scroll(inner, min_width=None):
    style = f' style="min-width:{min_width}px"' if min_width else ""
    return f'<div class="scroll"><div{style}>{inner}</div></div>'


# ---------------------------------------------------------------------------------------------- model


def ingest_rows(snapshot):
    rows = []
    for entry in snapshot["ingest"]:
        counts = {key: 0 for key, _, _ in INGEST_SERIES}
        detail = {}
        for category, count in entry["counts"].items():
            if category in NOT_OUTCOMES:
                continue
            detail[category] = count
            if category in ("accepted", "duplicate"):
                counts[category] += count
            elif category.startswith("rejected:"):
                counts["rejected"] += count
            else:
                counts["other"] += count
        rows.append({"day": entry["day"], "counts": counts, "detail": detail})
    return rows


def day_start(iso):
    return datetime.combine(date.fromisoformat(iso), datetime.min.time(), tzinfo=timezone.utc).timestamp()


def interrupted_ingress(entries):
    return {entry["day"] for entry in entries if any(entry["counts"].get(key, 0) for key in INGRESS_INTERRUPTION)}


def coverage_model(snapshot, rows):
    """Coverage by release and day, including interrupted rollups in older snapshots."""
    now = snapshot["generated_unix"]
    accepted = {row["day"]: row["counts"]["accepted"] for row in rows}
    interrupted = interrupted_ingress(snapshot["ingest"])
    stored = {}
    for c in snapshot["coverage"]:
        stored.setdefault((c["release_id"], c["day"]), {})[c["table"]] = c["status"]
    complete_tables = {"gpu", "vehicle", "cells"}
    stored_days = {day for _, day in stored}
    partial_days = {day for (_, day), tables in stored.items() if not complete_tables <= tables.keys()}
    marks = snapshot.get("rollup_days") or {}
    partial_days.update(day for day, state in marks.items() if state == "partial")
    rolled_days = (stored_days | {day for day, state in marks.items() if state in ("complete", "legacy")}) - partial_days
    releases = list(snapshot.get("releases_with_cells") or [])
    for release in sorted({c["release_id"] for c in snapshot["coverage"]}, reverse=True):
        if release not in releases:
            releases.append(release)

    def derived(day):
        age_h = (now - day_start(day)) / 3600
        if day in partial_days:
            return "partial" if age_h < EXPIRES_AFTER_H else "missed"
        if age_h < OVERDUE_AFTER_H:
            return "pending"
        if not accepted.get(day):
            return "unknown"
        return "overdue" if age_h < EXPIRES_AFTER_H else "missed"

    day_state = {row["day"]: derived(row["day"]) for row in rows if row["day"] not in rolled_days}
    cells = {}
    for release in releases:
        for row in rows:
            tables = stored.get((release, row["day"]))
            if tables:
                state = tables["cells"] if complete_tables <= tables.keys() else day_state.get(row["day"], "partial")
                cells[(release, row["day"])] = (state, tables)
            elif row["day"] in rolled_days:
                complete = marks.get(row["day"]) == "complete"
                cells[(release, row["day"])] = ("none" if complete and row["day"] not in interrupted else "unknown", {})
            else:
                cells[(release, row["day"])] = (day_state[row["day"]], {})
    return releases, cells, day_state


def alerts(snapshot, rows, day_state):
    """[(level, title, detail)], most severe first."""
    status, now = snapshot["status"], snapshot["generated_unix"]
    out = []
    today = rows[-1]["detail"] if rows else {}
    yesterday = rows[-2]["detail"] if len(rows) > 1 else {}
    both = lambda key: today.get(key, 0) + yesterday.get(key, 0)  # noqa: E731
    if status["suspend_all"]:
        out.append(("critical", "All releases suspended", "OPENRC_TELEMETRY_SUSPEND_ALL answers every batch with 410"))
    if not status["retention_ok"]:
        out.append(("critical", "Raw row past 48 h", f"oldest raw row {status['oldest_raw_age_h']} h: run purge"))
    if both("storage_unavailable"):
        out.append(("critical", "Storage unavailable", f"{both('storage_unavailable')} batches answered 503 "
                    "today/yesterday (disk full or database error)"))
    missed = sorted(day for day, state in day_state.items() if state == "missed")
    if missed:
        out.append(("critical", f"{len(missed)} day(s) never rolled up",
                    "rollup missing or incomplete after the 47 h window: " + ", ".join(missed[-5:])))
    partial = sorted(day for day, state in day_state.items() if state == "partial")
    if partial:
        out.append(("critical", "Incomplete rollup", "retry within the 47 h window: " + ", ".join(partial[-5:])))
    overdue = sorted(day for day, state in day_state.items() if state == "overdue")
    for day in overdue:
        left = EXPIRES_AFTER_H - (now - day_start(day)) / 3600
        out.append(("warning", f"Rollup overdue for {day}",
                    f"run python -m openrc_telemetry rollup --day {day} within {left:.1f} h"))
    oldest = status["oldest_raw_age_h"]
    if status["retention_ok"] and oldest is not None and oldest > RAW_TTL_H - 2:
        out.append(("warning", "Raw retention near 48 h", f"oldest raw row {oldest} h: check the purge loop"))
    if status["suspended_releases"]:
        out.append(("warning", "Releases suspended", ", ".join(status["suspended_releases"])))
    if both("rejected:unapproved_release"):
        out.append(("warning", "Unapproved release batches", f"{both('rejected:unapproved_release')} today/yesterday: "
                    "a published tag is missing from OPENRC_TELEMETRY_RELEASES"))
    if both("rate_limited"):
        out.append(("warning", "Rate limiting", f"{both('rate_limited')} batches answered 429 today/yesterday; "
                    "behind a proxy check OPENRC_TELEMETRY_TRUST_PROXY"))
    seen = last_seen(snapshot, rows)
    if seen is None:
        out.append(("info", "Waiting for first batch", f"no accepted batch in the last {len(rows)} days"))
    elif seen[0] > 86400:
        out.append(("warning", "No batch in 24 h", f"last accepted batch {seen[1]}"))
    model = snapshot.get("github")
    if model is not None:
        note, attempt = model.get("collect_note"), model.get("last_attempt")
        if note:
            out.append(("warning", "Download refresh failed", f"{note}; showing the archived counters"))
        else:
            for kind, info in (model.get("attempts") or ({"release assets": attempt} if attempt else {})).items():
                if info and not info["success"]:
                    out.append(("warning", f"GitHub {kind} collection failed", f"last attempt {info['finished']}"))
        age = downloads.age_s(model, now)
        if age is not None and age > DOWNLOADS_STALE_S:
            out.append(("warning", "Download counters stale", f"last collected {fmt_age(age)}: check the "
                         "the GitHub archive collector"))
    website = snapshot.get("website")
    if website and website.get("error"):
        out.append(("warning", "Website analytics failed", f"GA4: {website['error']}"))
    elif website and website.get("refresh_error"):
        out.append(("warning", "Website refresh failed", "showing the previous GA4 collection"))
    elif website and website.get("errors"):
        out.append(("warning", "Website reports failed", ", ".join(sorted(website["errors"]))))
    return sorted(out, key=lambda item: LEVELS[item[0]][0])


def last_accepted_day(rows):
    for row in reversed(rows):
        if row["counts"]["accepted"]:
            return row["day"]
    return None


def last_seen(snapshot, rows):
    """(minimum age in seconds, label, source) of the newest accepted batch, or None if none is known.

    The raw store gives the exact receipt time but forgets everything after 48 h; the daily counters keep the day
    for 180 days. The exact time wins unless the counters show a later UTC day (a counter day only proves a batch
    no later than that day's end, so its age is a lower bound)."""
    now, age = snapshot["generated_unix"], snapshot["status"]["last_accepted_age_s"]
    exact = None if age is None else (age, fmt_age(age), "newest stored batch")
    day = last_accepted_day(rows)
    if day is None:
        return exact
    today = datetime.fromtimestamp(now, tz=timezone.utc).date()
    offset = (today - date.fromisoformat(day)).days
    label = {0: "today", 1: "yesterday"}.get(offset, f"on {day}")
    counter = (int(max(0, now - (day_start(day) + 86400))), label, "daily counters (UTC day)")
    if exact is not None and datetime.fromtimestamp(now - age, tz=timezone.utc).date().isoformat() >= day:
        return exact
    return counter


# ---------------------------------------------------------------------------------------------- sections


def timeline_open(width, height, aria):
    return ('<div class="timeline"><svg class="chart" data-chart="days" role="group" '
            f'viewBox="0 0 {width} {height}" aria-label="{e(aria, quote=True)}" '
            'aria-description="Use Left and Right arrow keys to explore days.">')


def timeline_labels(count):
    intervals = min(6, count - 1)
    if intervals <= 0:
        return {0: True} if count else {}
    return {round(step * (count - 1) / intervals): step % 2 == 0 or step == intervals
            for step in range(intervals + 1)}


def timeline_date(x, height, date_label, major):
    return (f'<text class="tick date-tick{"" if major else " minor-tick"}" x="{x:.1f}" y="{height - 19}" '
            f'text-anchor="middle">{e(date_label[5:])}</text>')


def timeline_tick(value):
    if 1_000 <= value < 10_000:
        return f"{value / 1_000:.1f}K".replace(".0K", "K")
    return fmt_compact(value)


def timeline_target(left, width, center, top, plot_h, lines, latest):
    attrs = tip_attrs(lines, tab_index=0 if latest else -1)
    return (f'<rect class="hit" x="{left:.1f}" y="{top}" width="{width:.1f}" '
            f'height="{plot_h}" data-center="{center:.1f}" {attrs}/>')


def timeline_end(parts, targets, top, plot_h):
    parts.append(f'<line class="crosshair" y1="{top}" y2="{top + plot_h}" aria-hidden="true" hidden=""/>')
    return "".join([*parts, *targets, "</svg></div>"])


def ingest_chart(rows):
    width, height, left, right, top, bottom = 640, 232, 82, 34, 25, 44
    plot_w, plot_h = width - left - right, height - top - bottom
    totals = [sum(r["counts"].values()) for r in rows]
    ticks = nice_ticks(max(totals, default=0))
    scale = plot_h / ticks[-1]
    slot = plot_w / max(len(rows), 1)
    bar = min(24.0, slot * 0.64)
    parts = [timeline_open(width, height, "Ingest outcomes per UTC day")]
    for tick in ticks:
        y = top + plot_h - tick * scale
        cls = "axis" if tick == 0 else "grid"
        parts.append(f'<line class="{cls}" x1="{left}" x2="{width - right}" y1="{y:.1f}" y2="{y:.1f}"/>')
        parts.append(f'<text class="tick" x="{left - 8}" y="{y + 4:.1f}" text-anchor="end">{timeline_tick(tick)}</text>')
    labels = timeline_labels(len(rows))
    targets = []
    for index, row in enumerate(rows):
        x = left + index * slot + (slot - bar) / 2
        base = top + plot_h
        drawn = [(key, row["counts"][key], cls) for key, _, cls in INGEST_SERIES if row["counts"][key]]
        for position, (key, count, cls) in enumerate(drawn):
            h = count * scale
            seg_h = h - (min(1.0, h / 4) if position else 0)
            y = base - h
            if position == len(drawn) - 1:
                parts.append(f'<path class="fill-{cls}" d="{rounded_top(x, y, bar, seg_h)}"/>')
            else:
                parts.append(f'<rect class="fill-{cls}" x="{x:.1f}" y="{y:.1f}" width="{bar:.1f}" height="{seg_h:.1f}"/>')
            base = y
        lines = [row["day"], f"Total {fmt_int(totals[index])}"]
        lines += [f"{label}: {fmt_int(row['counts'][key])}" for key, label, _ in INGEST_SERIES]
        extra = sorted((c, n) for c, n in row["detail"].items() if c not in ("accepted", "duplicate"))
        lines += [f"  {c}: {fmt_int(n)}" for c, n in extra]
        center = left + (index + 0.5) * slot
        targets.append(timeline_target(center - slot / 2, slot, center, top, plot_h, lines, index == len(rows) - 1))
        if index in labels:
            parts.append(timeline_date(center, height, row["day"], labels[index]))
    return timeline_end(parts, targets, top, plot_h)


def ingest_table(rows):
    head = "".join(f"<th>{e(label)}</th>" for _, label, _ in INGEST_SERIES)
    body = "".join(
        f"<tr><td>{e(row['day'])}</td>" + "".join(f"<td>{fmt_int(row['counts'][k])}</td>" for k, _, _ in INGEST_SERIES)
        + "<td>" + e(", ".join(f"{c} {n}" for c, n in sorted(row["detail"].items())
                               if c not in ("accepted", "duplicate")) or "-") + "</td></tr>"
        for row in reversed(rows))
    return (f'<details><summary>Table</summary>{scroll(f"<table><thead><tr><th>UTC day</th>{head}<th>Refusal detail</th>"
            f"</tr></thead><tbody>{body}</tbody></table>")}</details>')


def legend(series, *, lines=False):
    color = ("inkline" if lines else "sw fill")
    items = "".join(f'<span class="key"><i aria-hidden="true" class="{color}-{cls}"></i>{e(label)}</span>'
                    for _, label, cls in series)
    return f'<div class="legend">{items}</div>'


def bar_row(name, value, scale, segments, tip, first, *, combined=False):
    width = f"{scale:.6%}"
    bars = "".join(f'<i class="fill-{slot}" style="flex-grow:{weight}"></i>' for slot, weight in segments)
    return len(value), (f'<div class="bar-row{" combined" if combined else ""}" '
                        f'{tip_attrs([name, *tip], tab_index=0 if first else -1)}>'
                        f'<span class="bar-label">{e(name)}</span><span class="bar-value">{e(value)}</span>'
                        f'<span class="bar-track"><span class="bar-stack" style="width:{width}">{bars}</span>'
                        '</span></div>')


def bar_plot(aria, rows):
    rows = list(rows)
    value_width = max((width for width, _ in rows), default=0) + 1
    return (f'<div class="bar-plot" style="--bar-value-width:{value_width}ch" data-chart="rows" role="group" '
            f'aria-label="{e(aria, quote=True)}" '
            'aria-description="Use Up and Down arrow keys to explore rows.">'
            + "".join(markup for _, markup in rows) + "</div>")


def hbar_chart(rows, unit_fmt, aria):
    """rows: [(label, value, tip_lines, is_combined)] -> horizontal bar chart (single series), largest first."""
    if not rows:
        return '<p class="empty">Nothing to show at this floor.</p>'
    rows = sorted((r for r in rows if not r[3]), key=lambda r: (-r[1], r[0])) + [r for r in rows if r[3]]
    maximum = max(value for _, value, _, _ in rows) or 1
    return bar_plot(aria, (
        bar_row(name, unit_fmt(value), value / maximum, [("other" if combined else "s1", 1)],
                tip, index == 0, combined=combined)
        for index, (name, value, tip, combined) in enumerate(rows)
    ))


def table_rows(entry):
    rows = list(entry["published"]) if entry else []
    if entry and entry.get("combined"):
        rows.append({**entry["combined"], "_combined": True})
    return rows


def report_tables(report):
    tables = report.get("tables") or {}
    if report.get("insights_version") == 2:
        return tables
    # Pre-v2 folds could sum the same session-day more than once and bypass the disclosure floor.
    return {key: {**entry, "combined": None} for key, entry in tables.items()}


def session_days(row):
    value = fmt_int(row["sessions"])
    return f"≥{value}" if row.get("sessions_lower_bound") else value


def cadence(metrics):
    total = sum(metrics[f"hist{i}"] for i in range(HIST_LEN)) or 1
    over = lambda first: sum(metrics[f"hist{i}"] for i in range(first, HIST_LEN))  # noqa: E731
    seconds = metrics["interval_sum_us"] / 1_000_000
    return {"minutes": seconds / 60, "fps": metrics["rendered_frames"] / seconds if seconds else 0.0,
            "p33": 100 * over(ABOVE_33_MS) / total, "p50": 100 * over(ABOVE_50_MS) / total,
            "excluded_gaps": metrics.get("excluded_gap_count"),
            "hitch_per_min": over(ABOVE_100_MS) * 60 / seconds if seconds else 0.0}


def cadence_block(title, entry):
    rows = table_rows(entry)
    bars, body = [], []
    for row in rows:
        name = " / ".join(row["dims"])
        c = cadence(row["metrics"])
        excluded = fmt_int(c["excluded_gaps"]) if c["excluded_gaps"] is not None else "Unknown"
        tip = [f"Session-days {session_days(row)}", f"FPS estimate {c['fps']:.1f}", f"Observed {c['minutes']:.1f} min",
               f"Intervals > 33.3 ms {c['p33']:.1f}%", f"Intervals > 50 ms {c['p50']:.1f}%",
               f"> 100 ms per minute {c['hitch_per_min']:.2f}", f"Excluded gaps {excluded}"]
        bars.append((name, c["hitch_per_min"], tip, row.get("_combined", False)))
        body.append(f"<tr><th scope=\"row\">{e(name)}</th><td>{c['hitch_per_min']:.2f}</td>"
                    f"<td>{c['p33']:.1f}%</td><td>{c['p50']:.1f}%</td><td>{c['minutes']:.1f}</td>"
                    f"<td>{session_days(row)}</td><td>{excluded}</td><td>{c['fps']:.1f}</td></tr>")
    if not rows:
        return (f'<div class="card"><h4>{e(title)}</h4><p class="empty">'
                "No cadence group reached the disclosure floor, or there were no measured intervals.</p></div>")
    chart = hbar_chart(bars, lambda v: f"{v:.2f}", f"Intervals above 100 ms per observed minute by {title}")
    table = ('<details><summary>Cadence data table</summary>' + scroll(
        '<table><thead><tr><th>' + e(title) + '</th><th>&gt; 100 ms / min</th><th>&gt; 33.3 ms</th>'
        '<th>&gt; 50 ms</th><th>Observed min</th><th>Session-days</th><th>Excluded gaps</th>'
        '<th>FPS estimate</th></tr></thead><tbody>' + "".join(body) + "</tbody></table>") + "</details>")
    return (f'<div class="card"><h4>{e(title)}</h4>'
            f'<p class="sub">Intervals above 100 ms per observed minute</p>{chart}{table}</div>')


def simple_block(title, entry, value_of, value_fmt, sub, extra_cols):
    rows = table_rows(entry)
    bars, body = [], []
    for row in rows:
        name = " / ".join(row["dims"])
        cols = [(col, fn(row)) for col, fn in extra_cols]
        chart_name = f"{name} ({session_days(row)} session-days)" if row.get("sessions_lower_bound") else name
        value = value_of(row)
        tip = [f"{sub}: {value_fmt(value)}", f"Session-days {session_days(row)}", *(f"{c} {v}" for c, v in cols)]
        bars.append((chart_name, value, tip, row.get("_combined", False)))
        body.append("<tr><td>" + e(name) + "</td><td>" + session_days(row) + "</td>"
                    + "".join(f"<td>{e(str(v))}</td>" for _, v in cols) + "</tr>")
    chart = hbar_chart(bars, value_fmt, f"{sub} by {title}")
    table = ""
    if body:
        heads = "".join(f"<th>{e(c)}</th>" for c, _ in extra_cols)
        table = ("<details><summary>Table</summary>" + scroll(
            f'<table><thead><tr><th>{e(title)}</th><th>Session-days</th>{heads}</tr></thead>'
            f'<tbody>{"".join(body)}</tbody></table>') + "</details>")
    return f'<div class="card"><h4>{e(title)}</h4><p class="sub">{e(sub)}</p>{chart}{table}</div>'


def error_spans(reports):
    spans = {}
    for report in reports:
        rows = ((report.get("tables") or {}).get("errors") or {}).get("published", [])
        for row in rows:
            key = report["release_id"], tuple(row["dims"])
            spans.setdefault(key, []).append(report["week"])
    return {key: (min(weeks), max(weeks)) for key, weeks in spans.items()}


def error_rows(entry, release, spans):
    rows = []
    for row in sorted(table_rows(entry), key=lambda row: (-row["metrics"]["count"], row["dims"])):
        first, last = spans.get((release, tuple(row["dims"])), ("—", "—"))
        rows.append(f'<tr><th scope="row">{e(" / ".join(row["dims"]))}</th>'
                    f'<td>{fmt_int(row["metrics"]["count"])}</td><td>{session_days(row)}</td>'
                    f'<td>{e(first)}</td><td>{e(last)}</td></tr>')
    if not rows:
        return '<p class="empty">No error category is available at the disclosure floor.</p>'
    return scroll('<table><thead><tr><th>Category</th><th>Occurrences</th><th>Session-days</th>'
                  '<th>First shown</th><th>Last shown</th></tr></thead><tbody>' + "".join(rows) + "</tbody></table>")


def report_section(index, report, hidden, spans, interrupted):
    attrs = f' data-report="{index}"' + (" hidden" if hidden else "")
    if "error" in report:
        return f'<section class="report"{attrs}><p class="empty">Refused: {e(report["error"])}</p></section>'
    tables = report_tables(report)
    chips = []
    for d in report["days"]:
        cls, glyph, label = STATES.get(d["status"], STATES["unknown"])
        chips.append(f'<span class="day st-{cls}" title="{e(d["day"])}: {e(label)}"><b>{glyph}</b>'
                     f'{e(d["day"][5:])}<span class="vh"> {e(label)}</span></span>')
    ready = sum(1 for d in report["days"] if d["status"] == "ready")
    note = "" if report["week_closed"] else '<span class="pill warn">week still open: figures can change</span>'
    affected = sum(day["day"] in interrupted for day in report["days"])
    coverage_note = (f'<p class="note">Receiver-wide ingress interruptions on {affected} day(s). '
                     'The rollup covers accepted batches.</p>') if affected else ""
    head = (f'<div class="reporthead"><div class="days">{"".join(chips)}</div><p class="sub">{ready} of 7 days rolled '
            f'up · cell floor {report["floor"]} session-days {note}</p>{coverage_note}'
            '<p class="note">Category counts can overlap. A ≥ sign marks a conservative lower bound. '
            'Compare FPS within the same frame-pacing class.</p></div>')
    if not any(table_rows(entry) for entry in tables.values()):
        return (f'<section class="report"{attrs}>{head}<p class="empty">No cohort is available at the '
                'disclosure floor for this release and week.</p></section>')
    flight = "".join(cadence_block(title, tables.get(key)) for key, title in FLIGHT_TABLES)
    menus = cadence_block("Screen", tables.get("menus"))
    usage = simple_block(
        "Vehicle", tables.get("usage_vehicle"), lambda r: r["metrics"]["active_seconds"] / 3600,
        lambda v: f"{v:.1f} h", "Active hours",
        [("Summaries", lambda r: r["metrics"]["summaries"]),
         ("Active h", lambda r: f"{r['metrics']['active_seconds'] / 3600:.1f}"),
         ("Takeoffs / landings / crashes", lambda r: (
             f"{r['metrics']['takeoffs']} / {r['metrics']['landings']} / {r['metrics']['aircraft_crashes']}"
             if r["metrics"]["classified_summaries"] else "-"))])
    backend = simple_block(
        "Vehicle / physics evaluator", tables.get("usage_backend"), lambda r: r["metrics"]["active_seconds"] / 3600,
        lambda v: f"{v:.1f} h", "Active hours · evaluator reported by schema v2 clients",
        [("Summaries", lambda r: r["metrics"]["summaries"])])
    errors = ('<div class="card"><h4>Error category</h4><p class="sub">Occurrences in the selected week. '
              'First and last are disclosed weeks for this release in the snapshot.</p>'
              + error_rows(tables.get("errors"), report["release_id"], spans) + "</div>")
    mix = "".join(simple_block(title, tables.get(key), lambda r: r["sessions"], fmt_int, "Session-days", [])
                  for key, title in MIX_TABLES)
    return (f'<section class="report"{attrs}>{head}'
            f'<h3>Flight frame cadence</h3><div class="cards">{flight}</div>'
            f'<h3>Menu and workshop cadence</h3><div class="cards">{menus}</div>'
            f'<h3>Vehicle usage and errors</h3><div class="cards">{usage}{backend}{errors}</div>'
            f'<h3>Hardware and settings mix</h3><div class="cards">{mix}</div></section>')


def coverage_grid(rows, releases, cells, day_state):
    if not rows:
        return '<p class="empty">No days in the snapshot.</p>'
    days = [row["day"] for row in rows]
    months, previous = [], None
    for day in days:
        label = date.fromisoformat(day).strftime("%b %Y")
        if label == previous:
            months[-1][1] += 1
        else:
            months.append([label, 1])
            previous = label
    month_row = "".join(f'<th class="m" colspan="{n}">{e(label)}</th>' for label, n in months)
    head = "".join(f'<th class="d" title="{e(d)}">{e(d[8:])}</th>' for d in days)
    body = []
    for release in releases or ["(none)"]:
        tds = []
        for day in days:
            state, tables = cells.get((release, day), (day_state.get(day, "none"), {}))
            cls, glyph, label = STATES.get(state, STATES["no_data"])
            tip = [f"{release} · {day}", f"insight cells: {label}"] + [f"{t}: {s}" for t, s in sorted(tables.items())
                                                                        if t != "cells"]
            tds.append(f'<td class="cov st-{cls}" {tip_attrs(tip, role=None)}><span aria-hidden="true">{glyph}</span>'
                       f'<span class="vh">{e(label)}</span></td>')
        body.append(f"<tr><th>{e(release)}</th>{''.join(tds)}</tr>")
    keys = "".join(f'<span class="key"><i class="cov st-{cls}">{glyph}</i>{e(label)}</span>'
                   for cls, glyph, label in STATES.values())
    return (scroll(f'<table class="coverage"><thead><tr><th></th>{month_row}</tr><tr><th>Release</th>{head}</tr>'
                   f'</thead><tbody>{"".join(body)}</tbody></table>') + f'<div class="legend">{keys}</div>')


def alerts_panel(items):
    if not items:
        return ('<div class="alerts"><div class="alert lv-good"><span class="badge st-good">\u2713</span>'
                '<div><b>All checks pass</b><span class="ts">retention, storage, rollups, releases and traffic</span>'
                '</div></div></div>')
    cls = {"critical": "critical", "warning": "warning", "info": "muted"}
    return '<div class="alerts">' + "".join(
        f'<div class="alert lv-{level}"><span class="badge st-{cls[level]}">{LEVELS[level][1]}</span>'
        f'<div><b>{e(title)}</b><span class="ts">{e(detail)}</span></div></div>' for level, title, detail in items
    ) + "</div>"


def tiles(snapshot, rows, alert_items):
    status = snapshot["status"]
    blank = {k: 0 for k, _, _ in INGEST_SERIES}
    today = rows[-1]["counts"] if rows else blank
    yesterday = rows[-2]["counts"] if len(rows) > 1 else blank
    worst = alert_items[0] if alert_items else ("good", "Receiving", "")
    state_cls = {"critical": "critical", "warning": "warning", "info": "muted", "good": "good"}[worst[0]]
    health = (f'<span class="badge st-{state_cls}">{LEVELS[worst[0]][1]}</span> {e(worst[1])}')
    seen = last_seen(snapshot, rows)
    if seen is None:
        last_value, last_sub = "never", f"none in the last {len(rows)} days"
    else:
        last_value, last_sub = seen[1], seen[2]
    span = min(7, len(rows))
    recent = sum(r["counts"]["accepted"] for r in rows[-span:]) if span else 0
    trend = f"last {span} days"
    if len(rows) >= 14:
        before = sum(r["counts"]["accepted"] for r in rows[-14:-7])
        trend = (f"vs {fmt_int(before)} the 7 days before ({(recent - before) / before * 100:+.0f}%)" if before
                 else "none the 7 days before")
    oldest = status["oldest_raw_age_h"]
    items = [
        ("Receiver", health, f"{len(alert_items)} open item(s)" if alert_items else "all checks pass"),
        ("Last accepted batch", e(last_value), e(last_sub)),
        ("Accepted today (UTC)", fmt_int(today["accepted"]), f"yesterday {fmt_int(yesterday['accepted'])}"),
        (f"Accepted, last {span} days", fmt_int(recent), e(trend)),
        ("Refused today", fmt_int(today["rejected"] + today["other"]), f"{fmt_int(today['duplicate'])} duplicate replays"),
        ("Raw batches held", fmt_int(status["raw_batches"]),
         "empty" if oldest is None else f"oldest {oldest} h of {RAW_TTL_H} h"),
        ("Accepted releases", e(", ".join(status["releases"]) or "none"),
         "suspended: " + e(", ".join(status["suspended_releases"]) or "none")
         + f" · proxy trust {'on' if status['trust_proxy'] else 'off'}"),
    ]
    return '<div class="tiles">' + "".join(
        f'<div class="tile"><div class="tl">{e(label)}</div><div class="tv">{value}</div><div class="ts">{sub}</div></div>'
        for label, value, sub in items) + "</div>"


def refusal_table(rows):
    totals = {}
    for row in rows:
        for category, count in row["detail"].items():
            if category not in ("accepted", "duplicate"):
                totals[category] = totals.get(category, 0) + count
    if not totals:
        return '<p class="empty">No refusals in this period.</p>'
    body = "".join(f"<tr><td>{e(c)}</td><td>{fmt_int(n)}</td></tr>"
                   for c, n in sorted(totals.items(), key=lambda item: (-item[1], item[0])))
    return f'<table class="narrow"><thead><tr><th>Category</th><th>Count</th></tr></thead><tbody>{body}</tbody></table>'


# ---------------------------------------------------------------------------------------------- downloads


def release_chart(releases):
    """Horizontal stacked bars: downloads per release split by platform (fixed slot per platform)."""
    maximum = max((total for _, _, total in releases), default=0) or 1
    rows = []
    for index, (tag, counts, total) in enumerate(releases):
        segments = [(slot, counts[p]) for p, slot in PLATFORM_SLOTS if counts[p]]
        tip = [f"Total {fmt_int(total)}"] + [f"{p}: {fmt_int(counts[p])}" for p, _ in PLATFORM_SLOTS if counts[p]]
        rows.append(bar_row(tag, fmt_int(total), total / maximum, segments, tip, index == 0))
    return bar_plot("Downloads per release by platform", rows)


def download_daily(model):
    values, uncertain = {}, {}
    if not model:
        return values, uncertain
    for interval in model.get("intervals", []):
        start = datetime.fromisoformat(interval["from_end"])
        end = datetime.fromisoformat(interval["to_end"])
        day = end.astimezone(timezone.utc).date().isoformat()
        if end - start > timedelta(hours=27):
            uncertain[day] = "Long collection interval"
        elif interval["increase"] is None or interval["status"] != "matched_ids":
            uncertain.setdefault(day, "Package set changed or the interval is unavailable")
    for day, (value, partial) in downloads.per_day(model).items():
        if partial:
            uncertain.setdefault(day, "Partial package counters")
        if day not in uncertain:
            values[day] = value
    return values, uncertain



def download_collection_chart(days, values, notes, title):
    """Show matched GitHub counter changes as observations assigned to collection dates."""
    width, height, left, right, top, bottom = 640, 220, 82, 46, 25, 44
    plot_width, plot_height = width - left - right, height - top - bottom
    baseline = top + plot_height
    counts = [values.get(day) for day in days]
    observed = [i for i, count in enumerate(counts) if count is not None]
    ticks = nice_ticks(max((counts[i] for i in observed), default=0))
    scale = plot_height / ticks[-1]
    slot = plot_width / max(len(days), 1)
    bar_width = min(22, slot * 0.66)
    labels = timeline_labels(len(days))
    parts = [timeline_open(width, height, title)]
    for tick in ticks:
        y = baseline - tick * scale
        cls = "axis" if tick == 0 else "grid"
        parts.append(f'<line class="{cls}" x1="{left}" x2="{width - right}" y1="{y:.1f}" y2="{y:.1f}"/>')
        parts.append(f'<text class="tick" x="{left - 8}" y="{y + 4:.1f}" text-anchor="end">{timeline_tick(tick)}</text>')
    start = observed[-1] if observed else len(days) - 1
    targets, rows = [], []
    for index, (day, count) in enumerate(zip(days, counts)):
        center = left + (index + 0.5) * slot
        note = notes.get(day, "")
        if count is None:
            mark_width = min(6, slot * 0.48)
            parts.append(f'<line class="collection-gap" x1="{center - mark_width / 2:.1f}" '
                         f'x2="{center + mark_width / 2:.1f}" y1="{baseline}" y2="{baseline}"/>')
            value = "Unavailable"
        elif count == 0:
            parts.append(f'<circle class="collection-zero fill-s1" cx="{center:.1f}" cy="{baseline}" r="2.5"/>')
            value = "0 (observed)"
        else:
            bar_height = count * scale
            path = rounded_top(center - bar_width / 2, baseline - bar_height, bar_width, bar_height, 3)
            parts.append(f'<path class="collection-bar fill-s1" d="{path}"/>')
            value = fmt_int(count)
        tip = [day, f"Matched counter increase: {value}"] + ([note] if note else [])
        targets.append(timeline_target(center - slot / 2, slot, center, top, plot_height, tip, index == start))
        if index in labels:
            parts.append(timeline_date(center, height, day, labels[index]))
        rows.append(f'<tr><th scope="row">{e(day)}</th><td>{e(value)}</td><td>{e(note)}</td></tr>')
    chart = timeline_end(parts, targets, top, plot_height)
    keys = []
    if 0 in counts:
        keys.append('<span class="key"><i class="collection-zero-key" aria-hidden="true"></i>Observed zero</span>')
    if len(observed) < len(days):
        keys.append('<span class="key"><i class="collection-gap-key" aria-hidden="true"></i>No daily value</span>')
    legend_html = f'<div class="legend collection-legend">{"".join(keys)}</div>' if keys else ""
    return chart + legend_html + timeline_table(title, ("Matched counter increase",), rows, "UTC collection day")


def downloads_section(model, now, days):
    head = ""
    if model is None:
        return (head + '<div class="panel"><p class="empty">No GitHub history archive found. Run '
                "<code>python tools/analytics/github_history.py collect --output-dir &lt;dir&gt;</code> or install "
                "its daily task (tools/analytics/README.md), or pass --downloads-dir.</p></div>")
    releases = downloads.per_release(model)
    total = sum(t for _, _, t in releases)
    platforms = {p: sum(c[p] for _, c, _ in releases) for p, _ in PLATFORM_SLOTS}
    latest = releases[0] if releases else None
    cutoff = now - 7 * 86400
    recent = [row["increase"] for row in model.get("intervals", [])
              if row["increase"] is not None and cutoff <= datetime.fromisoformat(row["to_end"]).timestamp() <= now]
    share = " · ".join(f"{p} {platforms[p] * 100 / total:.0f}%" for p, _ in PLATFORM_SLOTS if platforms[p]) if total else ""
    latest_split = " · ".join(f"{p} {latest[1][p]}" for p, _ in PLATFORM_SLOTS if latest[1][p]) if latest else ""
    items = [
        ("Package downloads, all releases", fmt_int(total) if model.get("collected_utc") else "-", share),
        (f"Latest release {latest[0]}" if latest else "Latest release", fmt_int(latest[2]) if latest else "-",
         latest_split),
        ("Observed download increases", fmt_int(sum(recent)) if recent else "-",
         "intervals that ended in the last seven days"),
        ("Counters collected", fmt_age(downloads.age_s(model, now)), model["collected_utc"] or "never"),
    ]
    tiles_html = '<div class="tiles">' + "".join(
        f'<div class="tile"><div class="tl">{e(a)}</div><div class="tv">{e(b)}</div><div class="ts">{e(c)}</div></div>'
        for a, b, c in items) + "</div>"
    axis = window_days(now, days)
    by_day, uncertain = download_daily(model)
    daily_chart = download_collection_chart(axis, by_day, uncertain, "Downloads per collection day")
    intervals = []
    for row in reversed(model.get("intervals", [])):
        if row["to_end"][:10] < axis[0]:
            continue
        value = "Unavailable" if row["increase"] is None else fmt_int(row["increase"])
        intervals.append(f'<tr><td>{e(row["from_end"])}</td><td>{e(row["to_end"])}</td><td>{value}</td>'
                         f'<td>{e(row["status"].replace("_", " "))}</td></tr>')
    interval_table = ('<table><thead><tr><th>Start</th><th>End</th><th>Known increase</th><th>Status</th></tr>'
                      f'</thead><tbody>{"".join(intervals)}</tbody></table>')
    interval_detail = ('<details><summary>Collection intervals</summary>' + scroll(interval_table) + "</details>"
                       if intervals else "")
    heads = "".join(f"<th>{p}</th>" for p, _ in PLATFORM_SLOTS)
    body = "".join(f"<tr><td>{e(tag)}</td>" + "".join(f"<td>{fmt_int(c[p])}</td>" for p, _ in PLATFORM_SLOTS)
                   + f"<td>{fmt_int(t)}</td></tr>" for tag, c, t in releases)
    table = scroll(f"<table><thead><tr><th>Release</th>{heads}<th>Total</th></tr></thead><tbody>{body}</tbody></table>")
    chart = release_chart(releases) if releases else '<p class="empty">No packages yet.</p>'
    keys = legend([(p, p, c) for p, c in PLATFORM_SLOTS if platforms[p]])
    return (f'{head}<p class="sub">GitHub release package counters ({e(model["pattern"])}) from the local history '
            "archive: cumulative and including repeat or automated downloads, not people or installs</p>"
            f'{tiles_html}<div class="pair"><div class="panel">'
            "<h4>Downloads per collection day</h4><p class=\"sub\">Matched counter increases by collection end day "
            f'(UTC). Long or partial intervals stay in the interval table.</p>{daily_chart}{interval_detail}</div>'
            f'<div class="panel"><h4>Downloads per release</h4>{keys}{chart}'
            f"<details><summary>Table</summary>{table}</details></div></div>")


# ---------------------------------------------------------------------------------------------- statistics views


def window_days(now, count):
    """The `count` UTC days ending today (ISO strings, oldest first)."""
    today = datetime.fromtimestamp(now, tz=timezone.utc).date()
    return [(today - timedelta(days=offset)).isoformat() for offset in range(count - 1, -1, -1)]


def release_days(model):
    """{ISO day: [tags published that UTC day]} for final releases (pre-releases would crowd the charts)."""
    out = {}
    for release in (model or {}).get("releases") or []:
        if release["prerelease"]:
            continue
        out.setdefault(release["published"][:10], []).append(release["tag"])
    return out


def line_chart(days, series, aria, markers=None, height=240, notes=None, *, provisional=None, key_html=""):
    """Lines on one shared axis. series: [(label, values aligned with days (None = unknown), slot)].
    notes: {day: text} appended to that day's tooltip."""
    markers, notes = markers or {}, notes or {}
    provisional = provisional or {}
    width, left, right, top, bottom = 640, 82, 46, 25, 44
    plot_w, plot_h = width - left - right, height - top - bottom
    known = [v for _, values, _ in series for v in values if v is not None]
    ticks = nice_ticks(max(known, default=0))
    scale = plot_h / ticks[-1]
    n = len(days)
    x_of = (lambda i: left + plot_w / 2) if n < 2 else (lambda i: left + i * plot_w / (n - 1))  # noqa: E731
    y_of = lambda v: top + plot_h - v * scale  # noqa: E731
    parts = [timeline_open(width, height, aria)]
    for tick in ticks:
        y = y_of(tick)
        parts.append(f'<line class="{"axis" if tick == 0 else "grid"}" x1="{left}" x2="{width - right}" '
                     f'y1="{y:.1f}" y2="{y:.1f}"/>')
        parts.append(f'<text class="tick" x="{left - 8}" y="{y + 4:.1f}" text-anchor="end">{timeline_tick(tick)}</text>')
    for index, day in enumerate(days):
        if day in markers:
            x = x_of(index)
            parts.append(f'<line class="mark" x1="{x:.1f}" x2="{x:.1f}" y1="{top}" y2="{top + plot_h}"/>')
            parts.append(f'<path class="markhead" d="M{x - 4:.1f},{top + plot_h + 1}l4,6l4,-6z"/>')
    end_labels = []
    for label, values, slot in series:
        path, pen = [], False
        for index, value in enumerate(values):
            if value is None or days[index] in provisional.get(label, ()):
                pen = False
                continue
            path.append(f'{"L" if pen else "M"}{x_of(index):.1f},{y_of(value):.1f}')
            pen = True
        if path:
            parts.append(f'<path class="line line-{slot}" d="{"".join(path)}"/>')
        for index, value in enumerate(values):
            if value is not None and days[index] in provisional.get(label, ()):
                parts.append(f'<circle class="provisional line-{slot}" cx="{x_of(index):.1f}" '
                             f'cy="{y_of(value):.1f}" r="4"/>')
        for index, value in enumerate(values):  # a point with no known neighbour would draw nothing
            provisional_days = provisional.get(label, ())
            if value is not None and days[index] not in provisional_days and (
                    index == 0 or values[index - 1] is None or days[index - 1] in provisional_days) and (
                    index == n - 1 or values[index + 1] is None or days[index + 1] in provisional_days):
                parts.append(f'<circle class="pt fill-{slot}" cx="{x_of(index):.1f}" cy="{y_of(value):.1f}" r="2.5"/>')
        last = next((i for i in range(n - 1, -1, -1) if values[i] is not None
                     and days[i] not in provisional.get(label, ())), None)
        if last is not None:
            parts.append(f'<circle class="dot fill-{slot}" cx="{x_of(last):.1f}" cy="{y_of(values[last]):.1f}" r="4"/>')
            if last == n - 1:
                end_labels.append((y_of(values[last]), x_of(last), values[last]))
    placed = []
    for y, x, value in end_labels:  # direct end labels only where they do not collide
        if all(abs(y - other) >= 13 for other in placed):
            placed.append(y)
            parts.append(f'<text class="value end-value" x="{x + 8:.1f}" y="{y + 4:.1f}">{fmt_compact(value)}</text>')
    labels = timeline_labels(n)
    step = plot_w / max(n - 1, 1)
    focus_index = next((i for i in range(n - 1, -1, -1) if any(values[i] is not None for _, values, _ in series)),
                       n - 1)
    table_rows_html = []
    targets = []
    for index, day in enumerate(days):
        values_today = []
        for label, values, _ in series:
            value = "Unavailable" if values[index] is None else fmt_int(values[index])
            if day in provisional.get(label, ()):
                value += " (provisional)"
            elif values[index] == 0:
                value += " (observed)"
            values_today.append((label, value))
        tip = [day] + [f"{label}: {value}" for label, value in values_today]
        tip += [f"Release {tag}" for tag in markers.get(day, [])]
        if day in notes:
            tip.append(notes[day])
        columns = "".join(f"<td>{e(value)}</td>" for _, value in values_today)
        comment = " · ".join([*(f"Release {tag}" for tag in markers.get(day, [])), notes.get(day, "")]).rstrip(" ·")
        table_rows_html.append(f'<tr><th scope="row">{e(day)}</th>{columns}<td>{e(comment)}</td></tr>')
        x = x_of(index)
        band_left = left if index == 0 else x - step / 2
        band_right = width - right if index == n - 1 else x + step / 2
        targets.append(timeline_target(band_left, band_right - band_left, x, top, plot_h, tip, index == focus_index))
        if index in labels:
            parts.append(timeline_date(x, height, day, labels[index]))
    chart = timeline_end(parts, targets, top, plot_h)
    return chart + key_html + timeline_table(aria, [label for label, _, _ in series], table_rows_html)


def timeline_table(title, labels, rows, day_label="Day"):
    heads = "".join(f'<th scope="col">{e(label)}</th>' for label in labels)
    table = (f'<table><caption>{e(title)}</caption><thead><tr><th scope="col">{e(day_label)}</th>{heads}'
             f'<th scope="col">Notes</th></tr></thead><tbody>{"".join(rows)}</tbody></table>')
    return '<details><summary>Data table</summary>' + scroll(table) + "</details>"


def stat_tiles(items):
    """items: [(label, value_html, sub_text)]"""
    return '<div class="tiles">' + "".join(
        f'<div class="tile"><div class="tl">{e(a)}</div><div class="tv">{b}</div><div class="ts">{e(c)}</div></div>'
        for a, b, c in items) + "</div>"


def panel(title, sub, body):
    return f'<div class="panel"><h4>{e(title)}</h4>' + (f'<p class="sub">{e(sub)}</p>' if sub else "") + body + "</div>"


def daily_values(rows, days, key):
    lookup = {r["day"]: r[key] for r in rows}
    return [lookup.get(day) for day in days]


def partial_notes(rows):
    return {r["day"]: "partial day: sampled before it ended" for r in rows if r.get("status") == "partial"}


def path_label(path, repo):
    prefix = "/" + (repo or "").strip("/")
    rest = path[len(prefix):] if repo and path.startswith(prefix) else path
    return rest.strip("/") or "(repository home)"


def latest_week_players(snapshot):
    """Lower bound on observed session-days in the newest disclosed release/week."""
    for report in snapshot.get("insights") or []:
        rows = table_rows(report_tables(report).get("mix_os"))
        if rows:
            return report["week"], report["release_id"], max(row["sessions"] for row in rows)
    return None


def delta_html(current, previous):
    """Present a weekly comparison only when both totals are comparable."""
    if current is None or previous is None:
        return '<span class="delta">No comparison yet</span>'
    diff = current - previous
    if not diff:
        text = "No activity in either week" if current == 0 else "No change vs prior 7 days"
        return f'<span class="delta">{text}</span>'
    direction, glyph = ("up", "↑") if diff > 0 else ("down", "↓")
    change = "New" if previous == 0 else f"{abs(diff) * 100 / previous:.0f}%"
    sign = "+" if diff > 0 else "−"
    return (f'<span class="delta delta-{direction}"><span class="delta-change">'
            f'<span aria-hidden="true">{glyph}</span><span class="vh">{direction.title()} </span>'
            f'{change} ({sign}{fmt_int(abs(diff))})</span><span>vs prior 7 days</span></span>')


@dataclass(frozen=True)
class WeekMetric:
    title: str
    target: str
    source: str
    zone: str
    days: list[str]
    observed_utc: str | None
    value: int | None
    previous: int | None
    coverage: int
    condition: str
    detail: str


def week_metric(title, target, source, zone, days, previous, values, observed_utc, detail="", uncertain=(),
                unavailable=False):
    known = [values[d] for d in days if values.get(d) is not None]
    comparable = len(known) == len(days) and not unavailable and not set(days).intersection(uncertain)
    prior = [values[d] for d in previous if values.get(d) is not None]
    prior_value = sum(prior) if comparable and previous and len(prior) == len(previous) and (
        not set(previous).intersection(uncertain)) else None
    state = ("Unavailable" if unavailable or not known else "Partial coverage" if not comparable
             else "Observed zero" if not any(known) else "Observed")
    return WeekMetric(title, target, source, zone, days, observed_utc,
                      None if unavailable or not known else sum(known), prior_value, len(known), state, detail)


def kpi_period(days, zone):
    start, end = date.fromisoformat(days[0]), date.fromisoformat(days[-1])
    if start.year != end.year:
        return f"{start.isoformat()} to {end.isoformat()} · {zone}"
    start_label = f"{start:%b} {start.day}"
    end_label = str(end.day) if start.month == end.month else f"{end:%b} {end.day}"
    return f"{start_label}–{end_label} · {zone}"


def kpi_observation(stamp):
    if stamp:
        try:
            parsed = datetime.fromisoformat(stamp)
            if parsed.tzinfo is not None:
                moment = parsed.astimezone(timezone.utc)
                label = f"{moment:%b} {moment.day}, {moment:%H:%M} UTC"
                return f'<time datetime="{e(stamp)}" title="Last observation {e(stamp)}">{e(label)}</time>'
        except ValueError:
            pass
    return "Observation time unknown"


def kpi_tiles(items):
    tiles = []
    for metric in items:
        value = "—" if metric.value is None else fmt_int(metric.value)
        delta = delta_html(metric.value, metric.previous)
        coverage = " kpi-partial" if metric.condition == "Partial coverage" else ""
        period = f"{metric.days[0]} to {metric.days[-1]} · {metric.zone}"
        tiles.append(f'<div class="tile week-kpi"><div class="tl">{e(metric.title)}</div>'
                     f'<div class="tv">{e(value)}</div>{delta}<div class="kpi-evidence">'
                     f'<div class="kpi-coverage{coverage}"><b>{e(metric.condition)}</b>'
                     f'<span>{metric.coverage}/{len(metric.days)} days observed</span></div>'
                     f'<div class="ts" title="{e(period)}">{e(kpi_period(metric.days, metric.zone))}</div>'
                     f'<div class="ts">{e(metric.source)} · {kpi_observation(metric.observed_utc)}</div>'
                     + (f'<div class="ts kpi-detail">{e(metric.detail)}</div>' if metric.detail else "") + "</div></div>")
    return '<div class="tiles">' + "".join(tiles) + "</div>"


def review_items(snapshot, alert_items, metrics):
    """At most three actions. A weekly change qualifies only with two comparable periods."""
    items = []
    for level, title, evidence in alert_items:
        if level not in ("critical", "warning"):
            continue
        target = ("downloads" if title.startswith("Download") else "github" if title.startswith("GitHub")
                  else "website" if title.startswith("Website") else "receiver")
        if not any(item[2] == target for item in items):
            items.append((title, evidence, target))
    for metric in metrics:
        if metric.previous is None or metric.value is None:
            continue
        change = metric.value - metric.previous
        if abs(change) >= max(5, metric.previous * 0.2):
            items.append((f"{metric.title} {'increased' if change > 0 else 'decreased'}",
                          f"{fmt_int(metric.value)} versus {fmt_int(metric.previous)} · {metric.source} · "
                          f"{metric.zone}", metric.target))
    model = snapshot.get("github") or {}
    github_sources = github_health(model, max(time.time(), snapshot["generated_unix"]))
    if not any(item[2] == "github" for item in items) and any(
        github_sources[key]["status"] != "ok" for key in ("github_views", "github_referrals")
    ):
        items.append(("Check private GitHub coverage", "Views or referrers are missing or need a fresh collection.",
                      "github"))
    if (snapshot.get("website") or {}).get("missing") and not any(item[2] == "website" for item in items):
        items.append(("Complete website breakdowns", "GA4 custom dimensions are pending.", "website"))
    if not items:
        return ""
    label = dict(TABS)
    return ('<section class="review"><h2>What to review</h2><ul>' + "".join(
        f'<li><div><b>{e(title)}</b><span>{e(evidence)}</span></div>'
        f'<a href="#{target}">Open {e(label[target])}</a></li>'
        for title, evidence, target in items[:3]) + "</ul></section>")


def collected_text(age):
    return "collected with this snapshot" if age < 300 else f"collected {fmt_age(age)}"


def freshness_strip(snapshot):
    """One chip per data source: is each number on this page current?"""
    now = max(time.time(), snapshot["generated_unix"])
    chips = [("good", "Receiver", "snapshot of this page")]
    model, website = snapshot.get("github"), snapshot.get("website")
    sources = github_health(model, now)
    for key, label in (("github_downloads", "GitHub downloads"), ("github_views", "GitHub views"),
                       ("github_clones", "GitHub clones"), ("github_community", "GitHub community"),
                       ("github_stars", "GitHub star history"),
                       ("github_referrals", "GitHub referrers")):
        status, age = sources[key]["status"], sources[key]["age_s"]
        detail = collected_text(max(0, age)) if age is not None else "never collected"
        if status == "error":
            detail = "refresh failed · " + detail
        chips.append(("good" if status == "ok" else "warning", label, detail))
    if website is None:
        chips.append(("warning", "Website (GA4)", "not connected"))
    elif website.get("error"):
        chips.append(("critical", "Website (GA4)", "collection failed"))
    else:
        age = timestamp_age(website.get("collected_utc"), now)
        detail = collected_text(max(0, age)) if age is not None else "collection date unknown"
        issues = (website.get("refresh_error") or website.get("errors") or website.get("missing")
                  or website.get("report_quality"))
        chips.append(("good" if age is not None and age <= GA4_MAX_AGE_S and not issues else "warning",
                      "Website (GA4)", ("partial · " if issues else "") + detail))
    glyph = {"good": "✓", "warning": "!", "critical": "✖"}
    return '<div class="chips" aria-label="Data freshness">' + "".join(
        f'<span class="chip"><i class="badge st-{level}" aria-hidden="true">{glyph[level]}</i>'
        f'<b>{e(name)}</b> {e(detail)}</span>' for level, name, detail in chips) + "</div>"


def release_panel(model, now):
    """Recent releases: age, downloads so far and the daily pace, newest first."""
    totals = {tag: (counts, total) for tag, counts, total in downloads.per_release(model)}
    recent = sorted(model.get("releases") or [], key=lambda r: r["published"], reverse=True)[:6]
    if not recent:
        return panel("Recent releases", None, '<p class="empty">No releases collected yet.</p>')
    rows = []
    age = timestamp_age(model.get("collected_utc"), now)
    collected_at = now - age if age is not None else None
    for release in recent:
        published = datetime.fromisoformat(release["published"].replace("Z", "+00:00")).timestamp()
        days_live = max((now - published) / 86400, 0)
        total = totals.get(release["tag"], (None, None))[1]
        observed_days = (collected_at - published) / 86400 if collected_at is not None else 0
        pace = f"{total / observed_days:.1f}" if total is not None and observed_days >= 1 else "—"
        kind = " (pre-release)" if release["prerelease"] else ""
        rows.append(f"<tr><td>{e(release['tag'])}{e(kind)}</td><td>{e(release['published'][:10])}</td>"
                    f"<td>{days_live:.1f}</td><td>{fmt_int(total) if total is not None else '—'}</td><td>{pace}</td></tr>")
    latest = recent[0]
    counts = totals.get(latest["tag"], ({p: 0 for p, _ in PLATFORM_SLOTS}, 0))[0]
    split = " · ".join(f"{p} {fmt_int(counts[p])}" for p, _ in PLATFORM_SLOTS if counts.get(p))
    table = scroll("<table><thead><tr><th>Release</th><th>Published (UTC)</th><th>Days live</th><th>Downloads</th>"
                   f"<th>Per day</th></tr></thead><tbody>{''.join(rows)}</tbody></table>")
    sub = f"latest {latest['tag']}: {split}" if split else f"latest {latest['tag']}"
    return panel("Recent releases", sub + " · pace at collection after at least one day",
                 table + '<p class="note"><a href="#releases">Open release comparison</a></p>')


def release_age_reports(snapshot, release):
    """Reports keyed by their starting release-age day, measured in whole UTC days."""
    published = datetime.fromisoformat(release["published"]).astimezone(timezone.utc).date()
    observed = {}
    commits = snapshot.get("rollup_days") or {}
    interrupted = interrupted_ingress(snapshot.get("ingest", ()))
    for report in snapshot.get("insights", []):
        days = report.get("days", [])
        if (report["release_id"] != release["tag"] or not report.get("week_closed") or len(days) != 7
                or any(day["status"] not in ("ready", "no_data") or commits.get(day["day"]) != "complete"
                       or day["day"] in interrupted
                       for day in days)):
            continue
        age = (date.fromisoformat(days[0]["day"]) - published).days
        if age > 0:
            observed[age] = report
    return observed


def release_cadence(snapshot, current, previous):
    left = release_age_reports(snapshot, current)
    right = release_age_reports(snapshot, previous)
    ages = sorted(((a, b) for a in left for b in right if abs(a - b) <= 2),
                  key=lambda item: (abs(item[0] - item[1]), max(item)))
    for age_a, age_b in ages:
        pair = left[age_a], right[age_b]
        for key, name in (("flight_pacing", "Frame pacing"), ("flight_gpu", "GPU family")):
            cohort_a, cohort_b = ({tuple(row["dims"]): row for row in
                                   (report["tables"].get(key) or {}).get("published", [])} for report in pair)
            shared = sorted(cohort_a.keys() & cohort_b.keys())
            if not shared:
                continue
            rows = []
            for dims in shared:
                cells = []
                for row in (cohort_a[dims], cohort_b[dims]):
                    result = cadence(row["metrics"])
                    cells.append(f'<td>{result["hitch_per_min"]:.2f}</td><td>{result["p50"]:.1f}%</td>'
                                 f'<td>{result["minutes"]:.1f} min · {fmt_int(row["sessions"])} session-days</td>')
                rows.append(f'<tr><th scope="row">{e(" / ".join(dims))}</th>{"".join(cells)}</tr>')
            columns = '<th scope="col">&gt; 100 ms/min</th><th scope="col">&gt; 50 ms</th><th scope="col">Coverage</th>'
            table = (f'<table><thead><tr><th rowspan="2">{e(name)}</th>'
                     f'<th colspan="3" scope="colgroup">{e(current["tag"])} · {e(pair[0]["week"])}</th>'
                     f'<th colspan="3" scope="colgroup">{e(previous["tag"])} · {e(pair[1]["week"])}</th>'
                     f'</tr><tr>{columns * 2}</tr></thead><tbody>{"".join(rows)}</tbody></table>')
            if age_a == age_b:
                caption = f"Release-age days {age_a}–{age_a + 6} (UTC)."
            else:
                caption = (f"Nearby windows in UTC. {current['tag']} days {age_a}–{age_a + 6}, "
                           f"{previous['tag']} days {age_b}–{age_b + 6}.")
            title = "Comparable flight cadence" if age_a == age_b else "Flight cadence at nearby release ages"
            return panel(title, f"{caption} Field observations help choose a controlled replay.", scroll(table))
    return panel("Comparable flight cadence", None,
                 '<p class="empty">Comparable data is unavailable. Both releases need closed, covered ISO weeks '
                 'starting within two release-age days, verified daily rollups without observed ingress '
                 'interruptions, and a shared segment above the '
                 'disclosure floor.</p>')


def releases_section(snapshot):
    model = snapshot.get("github") or {}
    stable = sorted((r for r in model.get("releases", []) if not r["prerelease"]),
                    key=lambda r: r["published"], reverse=True)[:8]
    if not stable:
        return '<p class="empty">Stable release history is unavailable.</p>'
    totals = {tag: total for tag, _, total in downloads.per_release(model)}
    rows = []
    for release in stable:
        tag = release["tag"]
        cells = []
        for observed in downloads.release_milestones(model, tag):
            if observed is None:
                cells.append("<td>Unavailable</td>")
            else:
                cells.append(f'<td>{fmt_int(observed["downloads"])}<br><small>{observed["age_s"] / 3600:.1f} h · '
                             f'{fmt_int(observed["packages"])} packages<br>{e(observed["observed_utc"])}</small></td>')
        total = totals.get(tag)
        rows.append(f'<tr><th scope="row">{e(tag)}</th><td>{e(release["published"][:10])}</td>'
                    f'{"".join(cells)}<td>{fmt_int(total) if total is not None else "Unavailable"}</td></tr>')
    milestones = "".join(f'<th scope="col">Near {e(label)}</th>' for label, _, _ in downloads.RELEASE_MILESTONES)
    table = (f'<table><thead><tr><th>Release</th><th>Published (UTC)</th>{milestones}<th>Latest counter</th></tr>'
             f'</thead><tbody>{"".join(rows)}</tbody></table>')
    distribution = panel("Downloads by release age", "Cumulative package counters from the closest observation "
                         "within each milestone window.", scroll(table))
    if len(stable) < 2:
        return distribution
    current, previous = stable[:2]
    related = [r for r in snapshot.get("insights", []) if r["release_id"] == current["tag"] and "error" not in r]
    entry = (related[0]["tables"].get("errors") if related else None)
    errors = panel(f'{current["tag"]} errors', f'{related[0]["week"]} · disclosed occurrences' if related else None,
                   error_rows(entry, current["tag"], error_spans(related)))
    return distribution + '<div class="pair">' + release_cadence(snapshot, current, previous) + errors + "</div>"


def platform_panel(model):
    releases = downloads.per_release(model)
    platforms = [(p, sum(c[p] for _, c, _ in releases), cls) for p, cls in PLATFORM_SLOTS]
    total = sum(n for _, n, _ in platforms)
    rows = [(p, n, [f"{fmt_int(n)} downloads", f"{n * 100 / total:.0f}% of all package downloads"], False)
            for p, n, _ in platforms if n]
    return panel("Downloads by platform", "all releases, GitHub package counters",
                 hbar_chart(rows, fmt_int, "Package downloads by platform") if rows else
                 '<p class="empty">No packages yet.</p>')


def sources_panel(website, model):
    """Where people come from: website sources with conversion, then GitHub referrers."""
    blocks = []
    funnel = ((website or {}).get("funnels") or {}).get("source") if website and not website.get("error") else None
    if funnel:
        body = "".join(f"<tr><td>{e(r['name'] or '(not set)')}</td><td>{fmt_int(r['users'])}</td>"
                       f"<td>{pct(r['requesting'], r['users'])}</td></tr>" for r in funnel[:6])
        blocks.append(f"<h3>Website, {len(website['days'])} days</h3>" + scroll(
            "<table><thead><tr><th>Source</th><th>Users</th><th>Requested a download</th></tr></thead>"
            f"<tbody>{body}</tbody></table>"))
    referrers = (model or {}).get("referrers") or []
    if referrers:
        body = "".join(f"<tr><td>{e(r['name'])}</td><td>{fmt_int(r['count'])}</td><td>{fmt_int(r['uniques'])}</td></tr>"
                       for r in referrers[:6])
        blocks.append("<h3>Repository referrers, 14 days</h3>" + scroll(
            "<table><thead><tr><th>Referrer</th><th>Views</th><th>Unique visitors</th></tr></thead>"
            f"<tbody>{body}</tbody></table>"))
    return panel("Where people come from", None, "".join(blocks) or '<p class="empty">No source data yet.</p>')


def countries_panel(website):
    rows = ((website or {}).get("tables") or {}).get("countries") if website and not website.get("error") else None
    if not rows:
        return panel("Top countries", None, '<p class="empty">Website analytics not connected.</p>')
    return panel("Top countries", f"website users, {len(website['days'])} days",
                 hbar_chart(ga_rows(rows[:8], "activeUsers", [("activeUsers", "Users"), ("sessions", "Sessions")]),
                            fmt_int, "Top countries by website users"))


def overview_section(snapshot, rows, alert_items):
    """Where the project stands this week, then the 30-day context (TELEM-24 overview)."""
    now, model, website = snapshot["generated_unix"], snapshot.get("github"), snapshot.get("website")
    if website and website.get("error"):
        website = None
    days, base = window_days(now, 30), window_days(now, 15)
    current, previous = base[7:14], base[:7]  # the last 7 full UTC days and the 7 before (today is partial)
    markers = release_days(model)
    metrics = []
    sources = github_health(model, now)
    dl, daily, traffic = {}, {}, []
    download_values, download_partial = download_daily(model)
    if model:
        traffic = model.get("traffic") or []
    metrics.append(week_metric("Package downloads by collection day", "downloads", "GitHub release assets", "UTC",
                               current, [],
                               download_values, sources["github_downloads"]["observed_utc"],
                               "Increases assigned to their collection end dates", download_partial))
    views = {r["day"]: r["count"] for r in traffic if r.get("status") != "partial"}
    visitor_days = sum(r["uniques"] for r in traffic if r["day"] in current and r["day"] in views)
    metrics.append(week_metric("Repository views", "github", "GitHub traffic", "UTC", current, previous, views,
                               sources["github_views"]["observed_utc"],
                               f"{fmt_int(visitor_days)} visitor-days" if any(d in views for d in current) else ""))
    star_days = (model or {}).get("star_days") or {}
    counters = ((model or {}).get("counters") or [None])[-1]
    star_stamp = sources["github_stars"]["observed_utc"]
    observed = (star_stamp or "")[:10]
    star_values = {d: star_days.get(d, 0) for d in base if d < observed}
    metrics.append(week_metric("New stars", "github", "GitHub star history", "UTC", current, previous, star_values,
                               star_stamp, f"{fmt_int(counters['stars'])} current stars" if counters else ""))
    ga_period, ga_provisional = "", set()
    ga_current, ga_previous, zone = current, previous, "property timezone unavailable"
    if website:
        today, zone_ok = ga4.property_today(website.get("time_zone"), now)
        if website.get("zone_fallback"):
            today, zone_ok = ga4.property_today(None, now)
        zone = website.get("time_zone") if zone_ok else "UTC fallback"
        cutoff = website.get("comparison_through", (today - timedelta(days=1)).isoformat())
        ga_provisional = set(website.get("provisional_days", [])) | {today.isoformat()}
        synchronous_cutoff = (today - timedelta(days=1)).isoformat()
        end = date.fromisoformat(min(cutoff, synchronous_cutoff) if cutoff else synchronous_cutoff)
        ga_base = [(end - timedelta(days=offset)).isoformat() for offset in range(13, -1, -1)]
        ga_current, ga_previous = ga_base[7:], ga_base[:7]
        ga_period = (f' Website days follow {zone}, {ga_current[0]} to {ga_current[-1]}.')
        daily = {r["day"]: r["sessions"] for r in website.get("daily") or []}
        dl = {r["day"]: r["count"] for r in website.get("downloads_daily") or []}
        quality = website.get("report_quality") or {}
        stamp = website.get("collected_utc")
        metrics.insert(1, week_metric("Website sessions", "website", "GA4", zone, ga_current, ga_previous, daily,
                                      stamp, uncertain=ga_base if quality.get("daily") else ga_provisional,
                                      unavailable=cutoff is None))
        if "downloads" in (website.get("errors") or {}):
            metrics.insert(2, week_metric("Website download requests", "website", "GA4", zone, ga_current,
                                          ga_previous, {}, stamp, "download requests: report failed"))
        else:
            days_in_report = len(website.get("days", []))
            users = website.get("conversion_users", (website.get("totals") or {}).get("users"))
            conversion = pct(website.get("downloads_users"), users)
            conversion_note = f"{conversion} of {days_in_report}-day users request a download"
            if conversion != "-" and ga_provisional.intersection(website.get("days", [])):
                conversion_note += " · period includes provisional days"
            metrics.insert(2, week_metric("Website download requests", "website", "GA4", zone, ga_current,
                                          ga_previous, dl, stamp, conversion_note if conversion != "-" else "",
                                          ga_base if quality.get("downloads") else ga_provisional,
                                          unavailable=cutoff is None))
    else:
        for index, title in enumerate(("Website sessions", "Website download requests"), 1):
            metrics.insert(index, week_metric(title, "website", "GA4", zone, ga_current, ga_previous, {}, None))
    accepted = {r["day"]: r["counts"]["accepted"] for r in rows}
    players = latest_week_players(snapshot)
    metrics.append(week_metric("Telemetry batches", "receiver", "Receiver", "UTC", current, previous, accepted,
                               utc_stamp(now), f"≥{fmt_int(players[2])} session-days · {players[0]} · {players[1]}"
                               if players else "Player rollup unavailable or below the disclosure floor"))

    charts = []
    if model:
        title = "GitHub package downloads by collection day"
        charts.append(panel("GitHub package downloads", "Matched counter increases by collection day · UTC.",
                            download_collection_chart(days, download_values, download_partial, title)))
    if website and "downloads" not in (website.get("errors") or {}):
        request_days = website.get("days") or [(today - timedelta(days=i)).isoformat() for i in range(29, -1, -1)]
        request_label = "Download requests"
        provisional_key = ""
        if any(day in ga_provisional and dl.get(day) is not None for day in request_days):
            provisional_key = ('<div class="legend collection-legend"><span class="key">'
                               '<i class="provisional-key" aria-hidden="true"></i>Provisional day</span></div>')
        request_chart = line_chart(request_days, [(request_label, [dl.get(d) for d in request_days], "s1")],
                                   "Website download requests per day", height=220,
                                   provisional={request_label: ga_provisional}, key_html=provisional_key)
        charts.append(panel("Website download requests", f"Requests recorded by GA4 · {zone}.", request_chart))
    if model or website:
        session_label = f"Website sessions ({zone})"
        interest = [("Repository views (UTC)", daily_values(traffic, days, "count"), "s1")] if model else []
        if website:
            interest.append((session_label, [daily.get(d) for d in days], "s2"))
        charts.append(panel("Interest per day", "Each series uses the reporting time zone in its label.",
                            legend([(s[0], s[0], s[2]) for s in interest], lines=True) + line_chart(
                                days, interest, "Interest per day", markers, 220,
                                 partial_notes(traffic), provisional={session_label: ga_provisional,
                                                                      "Repository views (UTC)": partial_notes(traffic)})))
    if accepted:
        charts.append(panel("Telemetry batches accepted per day", "consenting players' sessions reaching the "
                            "receiver", line_chart(days, [("Accepted", [accepted.get(d) for d in days], "s1")],
                                                    "Telemetry batches per day", markers, 220,
                                                    provisional={"Accepted": {days[-1]}})))
    pair = lambda a, b: f'<div class="pair">{a}{b}</div>'  # noqa: E731
    context = ""
    if model:
        context += pair(release_panel(model, now), platform_panel(model))
    context += pair(sources_panel(website, model), countries_panel(website))
    return (review_items(snapshot, alert_items, metrics) + alerts_panel(alert_items) + freshness_strip(snapshot)
            + f'<h2>Last 7 full days</h2><p class="sub">{e(current[0])} to {e(current[-1])} (UTC). Deltas require '
            f'two complete periods.{e(ga_period)}</p>' + kpi_tiles(metrics)
            + context
            + f'<h2>Last 30 days</h2><div class="pair">{"".join(charts)}</div>')


def github_section(model, now):
    if not model:
        return '<div class="panel"><p class="empty">No GitHub history archive found (tools/analytics).</p></div>'
    traffic, clones = model.get("traffic") or [], model.get("clones") or []
    first = min([r["day"] for r in traffic + clones] + list((model.get("star_days") or {}).keys()) or
                [window_days(now, 1)[0]])
    span = (datetime.fromtimestamp(now, tz=timezone.utc).date() - date.fromisoformat(first)).days + 1
    star_window = window_days(now, max(14, span))  # stars: the whole history
    days = window_days(now, min(90, max(14, span)))  # views and clones: at most 90 days
    markers = release_days(model)
    counters = (model.get("counters") or [None])[-1]
    last14 = days[-14:]
    items = [
        ("Stars", fmt_int(counters["stars"]) if counters else "-", "current"),
        ("Forks", fmt_int(counters["forks"]) if counters else "-", "current"),
        ("Watchers", fmt_int(counters["watchers"]) if counters else "-", "subscribed to notifications"),
        ("Open issues and PRs", fmt_int(counters["open_issues"]) if counters else "-", "GitHub's combined count"),
        ("Page views, 14 days", fmt_int(downloads.window_sum(traffic, last14)),
         f"{fmt_int(downloads.window_sum(traffic, days))} since {days[0]}"),
        ("Git clones, 14 days", fmt_int(downloads.window_sum(clones, last14)), "mostly automated (CI, mirrors)"),
    ]
    if not counters:
        items = items[4:] + [("Community counters", "-", "collected from the next run")]
    referrers = [(r["name"], r["count"], [f"Views {fmt_int(r['count'])}", f"Unique visitors {fmt_int(r['uniques'])}"],
                  False) for r in model.get("referrers") or []]
    paths = [(path_label(r["name"], model.get("repo")), r["count"],
              [r["title"][:80], f"Views {fmt_int(r['count'])}", f"Unique visitors {fmt_int(r['uniques'])}"], False)
             for r in model.get("paths") or []]
    totals = {tag: t for tag, _, t in downloads.per_release(model)}
    release_rows = "".join(
        f"<tr><td>{e(r['tag'])}</td><td>{e(r['published'][:10])}</td><td>{'pre-release' if r['prerelease'] else 'release'}"
        f"</td><td>{fmt_int(totals.get(r['tag'], 0))}</td></tr>"
        for r in sorted(model.get("releases") or [], key=lambda r: r["published"], reverse=True))
    window = f"GitHub's 14-day window, collected {model['community_utc'][:16].replace('T', ' ')} UTC" \
        if model.get("community_utc") else "not collected yet"
    pair = lambda a, b: f'<div class="pair">{a}{b}</div>'  # noqa: E731
    return (stat_tiles(items)
            + pair(panel("Repository page views", "per UTC day; triangles mark releases",
                         legend([("v", "Page views", "s1"), ("u", "Unique visitors", "s2")], lines=True) + line_chart(
                             days, [("Page views", daily_values(traffic, days, "count"), "s1"),
                                    ("Unique visitors", daily_values(traffic, days, "uniques"), "s2")],
                             "Repository page views per day", markers, notes=partial_notes(traffic))),
                   panel("Git clones", "per UTC day; archived from the first collection",
                         legend([("c", "Clones", "s1"), ("u", "Unique cloners", "s2")], lines=True) + line_chart(
                             days, [("Clones", daily_values(clones, days, "count"), "s1"),
                                    ("Unique cloners", daily_values(clones, days, "uniques"), "s2")],
                             "Git clones per day", markers, notes=partial_notes(clones))))
            + pair(panel("Stars over time", "current stargazers by the day they starred", line_chart(
                star_window, [("Stars", downloads.stars_cumulative(model, star_window), "s1")], "Stars over time",
                markers)),
                   panel("Releases", f"{len(model.get('releases') or [])} published", scroll(
                       "<table><thead><tr><th>Release</th><th>Published (UTC)</th><th>Type</th><th>Downloads</th></tr>"
                       f"</thead><tbody>{release_rows}</tbody></table>") if release_rows else
                       '<p class="empty">Collected from the next run.</p>'))
            + pair(panel("Top referrers", window, hbar_chart(referrers, fmt_int, "Top referrers by views")),
                   panel("Popular pages", window, hbar_chart(paths, fmt_int, "Popular repository pages by views"))))


GA_SETUP = ('<p>Give <code>dashboard.py fetch</code> a read-only Google credential (<code>analytics.readonly</code>): '
            'a service-account JSON key added as <b>Viewer</b> in GA Admin → Property access management, with the '
            'Google Analytics Data API enabled in its Cloud project (set <code>OPENRC_GA4_CREDENTIALS</code> to the '
            'key, kept outside the repository), or a gcloud application-default login. Set '
            '<code>OPENRC_GA4_PROPERTY</code> to the numeric property ID, or enable the Admin API too and it is found '
            'from the web stream. See tools/telemetry/README.md.</p>')
VITAL_RATINGS = (("good", "Good"), ("needs-improvement", "Needs improvement"), ("poor", "Poor"))


def ga_rows(table, metric, tip_metrics):
    """GA4 report rows -> hbar_chart rows; tip_metrics: [(api name, label)]."""
    return [(" / ".join(r["dims"]) or "(not set)", r["values"].get(metric, 0),
             [f"{label} {fmt_int(r['values'].get(name, 0))}" for name, label in tip_metrics], False)
            for r in table or []]


def ga_panel(model, key, title, sub, metric, tip_metrics):
    if key in model.get("missing", {}):
        names = ", ".join(f"<code>{e(n.split(':', 1)[1])}</code>" for n in model["missing"][key])
        body = (f'<p class="empty">Not registered in GA4.</p><p class="note">Register the event-scoped custom '
                f'dimension(s) {names} in GA Admin → Custom definitions; GA4 reports them from registration '
                'onwards.</p>')
    elif key in model.get("errors", {}):
        body = f'<p class="empty">Report failed: {e(model["errors"][key])}</p>'
    elif not (model.get("tables") or {}).get(key):
        body = '<p class="empty">No data in this period.</p>'
    else:
        body = hbar_chart(ga_rows(model["tables"][key], metric, tip_metrics), fmt_int, title)
    body += ga_quality_note(model, key)
    return panel(title, sub, body)


def ga_quality_note(model, key):
    flags = (model.get("report_quality") or {}).get(key) or []
    if not flags:
        return ""
    text = ", ".join(flag.replace("_", " ") for flag in flags)
    return f'<p class="note">GA4 coverage limit · {e(text)}</p>'


def vitals_panel(model):
    title, sub = "Web Vitals ratings", "sampled web_vital events (about 10% of page views), by metric and rating"
    if "vitals" in model.get("missing", {}) or "vitals" in model.get("errors", {}) or \
            not (model.get("tables") or {}).get("vitals"):
        return ga_panel(model, "vitals", title, sub, "eventCount", [])
    counts, known = {}, {k for k, _ in VITAL_RATINGS}
    for row in model["tables"]["vitals"]:
        if len(row["dims"]) == 2 and row["dims"][1] in known:
            counts.setdefault(row["dims"][0], {}).setdefault(row["dims"][1], 0)
            counts[row["dims"][0]][row["dims"][1]] += row["values"].get("eventCount", 0)
    body = []
    quality = ga_quality_note(model, "vitals")
    for name in sorted(counts, key=lambda n: ({"LCP": 0, "INP": 1, "CLS": 2}.get(n, 9), n)):
        total = sum(counts[name].values())
        values = []
        for key, _ in VITAL_RATINGS:
            count = counts[name].get(key)
            if quality:
                values.append(observed_count(count))
            else:
                values.append(f"{fmt_int(count or 0)} ({(count or 0) * 100 / max(total, 1):.0f}%)")
        cells = "".join(f"<td>{value}</td>" for value in values)
        body.append(f"<tr><td>{e(name)}</td>{cells}<td>{fmt_int(total)}</td></tr>")
    heads = "".join(f"<th>{label}</th>" for _, label in VITAL_RATINGS)
    table = (f"<table><thead><tr><th>Metric</th>{heads}<th>Visible samples</th></tr></thead>"
             f"<tbody>{''.join(body)}</tbody></table>")
    return panel(title, sub, quality + scroll(table) + '<p class="note">Ratings use the web-vitals thresholds (LCP 2.5/4 s, '
                 'INP 200/500 ms, CLS 0.1/0.25). Sampled field data, not a lab measurement.</p>')


def pct(part, whole):
    return f"{part * 100 / whole:.0f}%" if part is not None and whole and 0 <= part <= whole else "-"


def observed_count(value):
    return fmt_int(value) if value is not None else "-"


def funnel_panel(model):
    """Users and users who sent download_request, per source, device and OS (TELEM-24b)."""
    blocks = []
    for key, title in (("source", "Source"), ("device", "Device"), ("os", "Operating system")):
        if f"funnel_{key}" in (model.get("errors") or {}):
            blocks.append(f'<p class="empty">{e(title)}: report failed: {e(model["errors"]["funnel_" + key])}</p>')
            continue
        rows = (model.get("funnels") or {}).get(key) or []
        if not rows:
            continue
        body = "".join(f"<tr><td>{e(r['name'] or '(not set)')}</td><td>{observed_count(r['users'])}</td>"
                       f"<td>{observed_count(r['requesting'])}</td><td>{pct(r['requesting'], r['users'])}</td></tr>"
                       for r in rows[:10])
        blocks.append(scroll(f"<table><thead><tr><th>{e(title)}</th><th>Users</th><th>Requested a download</th>"
                             f"<th>Conversion</th></tr></thead><tbody>{body}</tbody></table>"))
    body = "".join(blocks) or '<p class="empty">No data in this period.</p>'
    base = "tracked users" if "conversion_users" in model else "active users (legacy report)"
    return panel("Download conversion", f"Users who sent a request ÷ {base} in the same period.", body)


def setup_panel(model):
    """WEB-17 property checklist read through the Admin API."""
    setup = model.get("setup") or {}
    items = []
    retention = setup.get("retention")
    items.append((retention == "FOURTEEN_MONTHS", "Event data retention 14 months",
                  "unknown" if retention is None else retention.replace("_", " ").lower()))
    keys = setup.get("key_events")
    items.append(("download_request" in (keys or []), "download_request is a key event",
                  "unknown" if keys is None else (", ".join(keys) or "none")))
    dims = setup.get("dimensions")
    if dims is None:
        items.append((False, "Custom dimensions registered", "unknown"))
    else:
        missing = [name for name, ok in dims.items() if not ok]
        items.append((not missing, "Custom dimensions registered",
                      "all registered" if not missing else "missing: " + ", ".join(missing)))
    rows = "".join(f'<tr><td><i class="cov st-{"good" if ok else "warning"}" aria-hidden="true">'
                   f'{"&#10003;" if ok else "!"}</i> {e(label)}</td><td>{e(detail)}</td></tr>'
                   for ok, label, detail in items)
    note = ("Change these in GA4 Admin (the dashboard credential is read-only); see "
            "docs/plans/website-analytics.md, WEB-17. Custom dimensions report only from registration onwards.")
    return panel("Property setup (WEB-17)", f"only {model.get('host') or 'the published site'} is counted",
                 scroll(f'<table class="narrow"><tbody>{rows}</tbody></table>') + f'<p class="note">{e(note)}</p>')


def website_section(model, github_model, now):
    head = ('<p class="sub">Public website (GA4 web stream <code>' + e(ga4.MEASUREMENT_ID) + '</code>, through Tag '
            'Manager): page views, <code>download_request</code> events and sampled Web Vitals. Blocked analytics '
            'and direct GitHub downloads are not measured; a download request is not a completed download.</p>')
    if model is None:
        return (head + '<div class="panel"><h4>Google Analytics 4</h4><p class="sub">Not connected</p>' + GA_SETUP
                + '<p>Until then, open <a href="https://analytics.google.com/analytics/web/" rel="noopener">Google '
                'Analytics</a>.</p></div>')
    if model.get("error"):
        return (head + f'<div class="panel"><h4>Google Analytics 4</h4><p class="sub">Collection failed '
                f'{e((model.get("collected_utc") or "")[:16].replace("T", " "))} UTC</p>'
                f'<p><b>{e(model["error"])}</b></p>{GA_SETUP}</div>')
    if model.get("refresh_error"):
        head += (f'<p class="banner stale">GA4 refresh failed. Data last collected '
                 f'{e(model.get("collected_utc") or "at an unknown time")}.</p>')
    totals, days = model.get("totals") or {}, model.get("days") or []
    sessions = totals.get("sessions")
    engaged_rate = pct(totals.get("engaged"), sessions)
    engaged = f"{engaged_rate} engaged" if engaged_rate != "-" else ""
    span = f"{len(days)} days"
    errors = model.get("errors") or {}
    dl_total_failed = "download_totals" in errors or ("report_quality" not in model and "downloads" in errors)
    recent_requests = ga4.window(model, 7)
    conversion_users = model.get("conversion_users", totals.get("users"))
    conversion = pct(model.get("downloads_users"), conversion_users)
    items = [
        (f"Active users, {span}", observed_count(totals.get("users")), f"{observed_count(totals.get('new_users'))} new"),
        (f"Sessions, {span}", observed_count(sessions), engaged),
        (f"Page views, {span}", observed_count(totals.get("views")), "all locales"),
        (f"Download requests, {span}", observed_count(model.get("downloads_total")),
         "report failed" if dl_total_failed else f"{fmt_int(recent_requests)} in the latest 7 days"
         if recent_requests is not None else "latest 7 days incomplete"),
        ("Download conversion", conversion,
         f"{fmt_int(model['downloads_users'])} of {fmt_int(conversion_users)} tracked users sent a request"
         if conversion != "-" else "report unavailable"),
        ("Phone hand-offs", "-" if model.get("handoffs") is None else fmt_int(model["handoffs"]),
         "download links opened on phones or tablets (WEB-20)"),
        ("Active users now", "-" if model.get("realtime_users") is None else fmt_int(model["realtime_users"]),
         f"last 30 minutes · property {model.get('property')}"),
    ]
    markers = release_days(github_model)
    daily = model.get("daily") or []
    provisional_days = set(model.get("provisional_days", []))
    if days:
        head += (f'<p class="note">Website report period {e(days[0])} to {e(days[-1])} · '
                 f'{e(model.get("time_zone") or "time zone unavailable")}.')
        if provisional_days.intersection(days):
            head += " Totals and breakdowns include provisional days. Hollow points show provisional daily values."
        head += "</p>"
    zone = (f"per UTC day: time zone {model.get('time_zone') or 'unknown'} could not be loaded (pip install "
            "tzdata), so the newest day can be partial or empty; triangles mark releases"
            if model.get("zone_fallback") else
            f"per day in the property time zone ({model.get('time_zone') or 'unknown'}); triangles mark releases")
    visitors = panel("Visitors per day", zone, legend([("u", "Active users", "s1"), ("s", "Sessions", "s2"),
                                                       ("v", "Page views", "s3")], lines=True) + line_chart(
        days, [("Active users", daily_values(daily, days, "users"), "s1"),
               ("Sessions", daily_values(daily, days, "sessions"), "s2"),
               ("Page views", daily_values(daily, days, "views"), "s3")], "Website visitors per day", markers,
        provisional=dict.fromkeys(("Active users", "Sessions", "Page views"), provisional_days)))
    if "downloads" in model.get("errors", {}):
        dl_body = f'<p class="empty">Report failed: {e(model["errors"]["downloads"])}</p>'
    else:
        dl_body = line_chart(days, [("Download requests", daily_values(model.get("downloads_daily") or [], days,
                                                                        "count"), "s1")],
                             "Website download requests per day", markers,
                             provisional={"Download requests": provisional_days})
    requests = panel("Download requests per day", "download_request events (automatic and manual)", dl_body)
    pair = lambda a, b: f'<div class="pair">{a}{b}</div>'  # noqa: E731
    users_sessions = [("activeUsers", "Users"), ("sessions", "Sessions")]
    extra_errors = {k: v for k, v in errors.items() if k in ("metadata", "realtime", "totals", "download_totals")}
    error_note = "".join(f'<p class="note">{e(k.capitalize())} report failed: {e(v)}</p>'
                         for k, v in extra_errors.items())
    quality = model.get("report_quality") or {}
    if quality:
        notes = " · ".join(f'{key.replace("_", " ")} ({", ".join(flag.replace("_", " ") for flag in flags)})'
                           for key, flags in sorted(quality.items()))
        error_note += f'<p class="note">GA4 coverage limits · {e(notes)}</p>'
    event_panels = "".join(ga_panel(model, key, title, label, "eventCount", [("eventCount", "Events")])
                           for key, title, label in (
                               ("download_methods", "Download requests by method", "Automatic and manual"),
                               ("handoff_actions", "Phone hand-off actions", "Shown, copied or shared"))
                           if any(key in (model.get(section) or {}) for section in ("tables", "missing", "errors")))
    return (head + stat_tiles(items) + error_note + pair(visitors, requests)
            + pair(ga_panel(model, "countries", "Countries", "active users", "activeUsers", users_sessions),
                   ga_panel(model, "download_countries", "Download requests by country", "download_request events",
                            "eventCount", [("eventCount", "Requests")]))
            + pair(ga_panel(model, "sources", "Traffic sources", "sessions by source / medium", "sessions",
                            [("sessions", "Sessions"), ("activeUsers", "Users")]),
                   ga_panel(model, "pages", "Top pages", "page views (one page per locale)", "screenPageViews",
                            [("screenPageViews", "Views"), ("activeUsers", "Users")]))
            + pair(ga_panel(model, "download_platforms", "Download requests by platform", "download_platform",
                            "eventCount", [("eventCount", "Requests")]),
                   ga_panel(model, "download_sources", "Download requests by source",
                            "download_source: website or the GitHub README link", "eventCount",
                            [("eventCount", "Requests")]))
            + pair(ga_panel(model, "devices", "Devices", "active users by device category", "activeUsers",
                            [("activeUsers", "Users")]), vitals_panel(model))
            + pair(funnel_panel(model),
                   ga_panel(model, "download_releases", "Download requests by release", "release_version",
                            "eventCount", [("eventCount", "Requests")]))
            + (pair(event_panels, "") if event_panels else "")
            + pair(setup_panel(model), ""))


def players_section(snapshot, insight_html, rows):
    players = latest_week_players(snapshot)
    if not snapshot.get("insights"):
        state = ("The receiver has accepted batches. Weekly rollup data is unavailable."
                 if last_seen(snapshot, rows) is not None else "Waiting for the first accepted batch.")
        return (f'<div class="panel"><p class="empty">{state} The daily rollup runs at 01:30 UTC. '
                f'Weekly categories require at least {snapshot["floor"]} session-days.</p></div>')
    observed_weeks = {report["week"] for report in snapshot["insights"]
                      if any(day["status"] == "ready" for day in report.get("days", ()))}
    tiles_html = stat_tiles([
        ("Observed session-days, newest disclosed week", f"≥{fmt_int(players[2])}" if players else "-",
         f"{players[0]} · {players[1]}" if players else ""),
        ("Weeks with data", fmt_int(len(observed_weeks)), "selected range"),
    ])
    return tiles_html + insight_html


CSS = """
:root{color-scheme:light;--surface:#fcfcfb;--page:#f9f9f7;--ink:#0b0b0b;--ink2:#52514e;--muted:#6b6964;
--grid:#e7e6e1;--axis:#c3c2b7;--ring:rgba(11,11,11,.10);--s1:#276bc0;--s2:#a64528;--s3:#187c67;--s4:#7158aa;
--up-ink:#146344;--up-fill:#e5f4eb;--down-ink:#a22d42;--down-fill:#fbe9ed;--partial-ink:#805315;
--other:#75736b;--good:#0ca30c;--warning:#fab219;--critical:#d03b3b;--wash:rgba(11,11,11,.05);--focus:#276bc0}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){color-scheme:dark;--surface:#1a1a19;--page:#0d0d0d;
--ink:#f0efec;--ink2:#c3c2b7;--muted:#9a988f;--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#73aff7;
--s2:#f5a078;--s3:#62cbb0;--s4:#b39be9;--other:#76746c;--wash:rgba(255,255,255,.06);--focus:#86b6ef;
--up-ink:#85dfae;--up-fill:#20372b;--down-ink:#ff9dab;--down-fill:#43282e;--partial-ink:#ecc382}}
:root[data-theme="dark"]{color-scheme:dark;--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;
--muted:#9a988f;--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#73aff7;--s2:#f5a078;--s3:#62cbb0;
--s4:#b39be9;--other:#76746c;--wash:rgba(255,255,255,.06);--focus:#86b6ef;
--up-ink:#85dfae;--up-fill:#20372b;--down-ink:#ff9dab;--down-fill:#43282e;--partial-ink:#ecc382}
*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);
font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1440px;margin:0 auto;padding:24px 16px 64px}
header{display:flex;flex-wrap:wrap;gap:8px 24px;align-items:baseline;justify-content:space-between}
h1{font-size:22px;margin:0}h2{font-size:17px;margin:32px 0 4px}h3{font-size:15px;margin:24px 0 8px;color:var(--ink2)}
h4{font-size:14px;margin:0}.sub{color:var(--ink2);margin:2px 0 8px;font-size:13px}text.muted{fill:var(--muted)}
.vh{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
.banner{border:1px solid var(--ring);background:var(--surface);border-left:4px solid var(--warning);
padding:8px 12px;border-radius:6px;margin:12px 0;color:var(--ink2)}.banner[hidden]{display:none}
.banner.stale{border-left-color:var(--critical);color:var(--ink)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,170px),1fr));gap:12px;margin-top:12px}
.tile,.card,.panel{background:var(--surface);border:1px solid var(--ring);border-radius:10px;padding:14px 16px;min-width:0}
.tl{color:var(--ink2);font-size:13px}.tv{font-size:21px;font-weight:600;margin:4px 0;overflow-wrap:anywhere}
.ts{color:var(--muted);font-size:12px;display:block}
.week-kpi .tl{font-weight:600;line-height:1.3;min-height:2.6em}
.week-kpi .tv{font-size:28px;line-height:1.15;font-variant-numeric:tabular-nums;margin:5px 0 7px}
.delta{display:flex;align-items:center;flex-wrap:wrap;gap:3px 6px;min-height:24px;
color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}
.delta-change{display:inline-flex;align-items:center;gap:5px;border-radius:5px;padding:2px 6px;font-weight:700}
.delta-up .delta-change{color:var(--up-ink);background:var(--up-fill)}
.delta-down .delta-change{color:var(--down-ink);background:var(--down-fill)}
.kpi-evidence{border-top:1px solid var(--grid);margin-top:9px;padding-top:9px}
.kpi-coverage{display:flex;flex-wrap:wrap;gap:0 7px;color:var(--ink2);font-size:12px;margin-bottom:3px}
.kpi-coverage span{color:var(--muted);white-space:nowrap}.kpi-partial b{color:var(--partial-ink)}
.kpi-detail{margin-top:5px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.chip{display:inline-flex;align-items:center;gap:6px;background:var(--surface);border:1px solid var(--ring);
border-radius:999px;padding:4px 12px 4px 4px;font-size:12.5px;color:var(--ink2)}.chip b{color:var(--ink)}
.chip .badge{width:20px;height:20px;font-size:11px;vertical-align:0}
.alerts{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,360px),1fr));gap:8px;margin-top:12px}
.alert{display:flex;gap:10px;align-items:flex-start;background:var(--surface);border:1px solid var(--ring);
border-radius:8px;padding:8px 12px}.alert b{display:block}.alert code{font-size:12px}
.badge{display:inline-flex;flex:none;width:22px;height:22px;border-radius:50%;align-items:center;
justify-content:center;font-size:13px;font-weight:700;vertical-align:3px}
.st-good{background:var(--good);color:#0b0b0b}.st-warning{background:var(--warning);color:#0b0b0b}
.st-critical{background:var(--critical);color:#fff}.st-muted{background:var(--grid);color:var(--ink2)}
.st-neutral{background:transparent;color:var(--muted);box-shadow:inset 0 0 0 1px var(--axis)}
.timeline,.bar-plot{container-type:inline-size}
.chart{width:100%;height:auto;display:block}
line.grid{stroke:var(--grid);stroke-width:1;vector-effect:non-scaling-stroke}
line.axis{stroke:var(--axis);stroke-width:1;vector-effect:non-scaling-stroke}
.tick,.value{font-variant-numeric:tabular-nums}.tick{fill:var(--muted);font-size:13px}
.value{fill:var(--ink2);font-size:13px;font-weight:600}
.date-tick{dominant-baseline:central}
.collection-gap{stroke:var(--muted);stroke-opacity:.75;stroke-width:1.5;vector-effect:non-scaling-stroke}
.collection-zero-key{width:6px;height:6px;border-radius:50%;background:var(--s1)}
.collection-gap-key{width:9px;border-top:2px solid var(--muted)}
.provisional-key{width:8px;height:8px;border:1.5px solid var(--s1);border-radius:50%}
.collection-legend{font-size:12px;margin:2px 0 6px}
@media (forced-colors:active){.collection-zero-key{background:CanvasText}.collection-gap-key{border-color:CanvasText}}
.crosshair{stroke:var(--focus);stroke-width:1;stroke-dasharray:3 3;vector-effect:non-scaling-stroke;pointer-events:none}
.crosshair[hidden]{display:none}
@container (max-width:510px){.tick{font-size:16px}.minor-tick,.end-value{display:none}}
@container (max-width:390px){.tick{font-size:20px}}
@container (max-width:330px){.tick{font-size:23px}.chart circle{r:5px}}
@container (max-width:280px){.tick{font-size:27px}.chart circle{r:6px}}
.fill-s1{fill:var(--s1);background:var(--s1)}.fill-s2{fill:var(--s2);background:var(--s2)}
.fill-s3{fill:var(--s3);background:var(--s3)}.fill-s4{fill:var(--s4);background:var(--s4)}
.fill-other{fill:var(--other);background:var(--other)}
.hit{fill:transparent;outline:none;cursor:crosshair}.hit.inspected{fill:var(--wash)}
.hit:focus-visible{stroke:var(--focus);stroke-width:1.5;vector-effect:non-scaling-stroke}
.bar-row{display:grid;grid-template:"name track value" auto/minmax(0,38%) minmax(0,1fr) max(3ch,var(--bar-value-width));
align-items:center;gap:8px 12px;padding:5px 5px;border-radius:6px;min-height:29px;font-size:13px}
.bar-label{grid-area:name;color:var(--ink2);overflow-wrap:anywhere;line-height:1.3}
.bar-value{grid-area:value;justify-self:end;font-weight:600;font-variant-numeric:tabular-nums}
.bar-track{grid-area:track;height:8px;border-radius:4px;background:var(--grid);overflow:hidden}
.bar-stack{height:100%;display:flex;border-radius:inherit;overflow:hidden}
.bar-stack i{flex-basis:0;min-width:0}
.bar-row.inspected{background:var(--wash)}.bar-row:focus-visible{outline:2px solid var(--focus);outline-offset:-2px}
.bar-row.combined .bar-label{color:var(--muted)}
@container (max-width:395px){
 .bar-row{grid-template:"name value" auto "track track" auto/minmax(0,1fr) max-content;gap:5px 12px;padding:6px 5px 8px}
 .bar-track{height:6px}
}
.legend{display:flex;flex-wrap:wrap;gap:6px 16px;margin:8px 0;color:var(--ink2);font-size:13px}
.key{display:inline-flex;align-items:center;gap:6px}.sw{display:inline-block;width:12px;height:12px;border-radius:3px;
vertical-align:-1px}.note{color:var(--ink2);font-size:12.5px;margin:6px 0 0}
[class^="inkline-"]{width:18px;border-top:2px solid var(--s1)}
.inkline-s2{border-color:var(--s2);border-top-style:dashed}.inkline-s3{border-color:var(--s3);border-top-style:dotted}
.inkline-s4{border-color:var(--s4);border-top-style:dashed}
.split{display:grid;grid-template-columns:minmax(0,3fr) minmax(0,1fr);gap:16px}
@media (max-width:900px){.split{grid-template-columns:minmax(0,1fr)}}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,440px),1fr));gap:12px}
.tabs{display:flex;gap:2px;border-bottom:1px solid var(--grid);margin:16px 0 4px;overflow-x:auto}
.tab{border:0;border-bottom:2px solid transparent;border-radius:0;background:transparent;color:var(--ink2);
padding:10px 14px;cursor:pointer;white-space:nowrap}.tab:hover{color:var(--ink)}
.tab[aria-selected="true"]{color:var(--ink);border-bottom-color:var(--s1);font-weight:600}
.tab:focus-visible{outline:2px solid var(--focus);outline-offset:-2px}
.count{display:inline-block;min-width:18px;padding:0 5px;border-radius:9px;background:var(--warning);color:#0b0b0b;
font-size:11px;font-weight:700;text-align:center}
.tabpanel[hidden]{display:none}
path.line{fill:none;stroke-width:2;stroke-linejoin:round;stroke-linecap:round;vector-effect:non-scaling-stroke}
path.line-s2{stroke-dasharray:5 4}path.line-s3{stroke-dasharray:1 4}path.line-s4{stroke-dasharray:7 4}
.line-s1{stroke:var(--s1)}.line-s2{stroke:var(--s2)}.line-s3{stroke:var(--s3)}.line-s4{stroke:var(--s4)}
circle.provisional{fill:var(--surface);stroke-width:1.5;vector-effect:non-scaling-stroke}
.review{margin:14px 0}.review ul{padding:0;margin:0;list-style:none;display:grid;gap:8px}
.review li{background:var(--surface);border:1px solid var(--ring);border-radius:8px;padding:10px 12px;
 display:flex;flex-wrap:wrap;gap:6px 18px;align-items:center;justify-content:space-between}
.review span{display:block;color:var(--ink2);overflow-wrap:anywhere}.review a{white-space:nowrap}
circle.dot{stroke:var(--surface);stroke-width:1.5;vector-effect:non-scaling-stroke}
circle.pt{stroke:none}line.mark{stroke:var(--axis);stroke-width:1;stroke-dasharray:2 4;vector-effect:non-scaling-stroke}
path.markhead{fill:var(--muted)}
.pair{display:grid;align-items:start;grid-template-columns:repeat(auto-fit,minmax(min(100%,520px),1fr));gap:12px;margin-top:12px}
.scroll{overflow-x:auto;max-width:100%}
table{border-collapse:collapse;width:100%;margin-top:8px;font-size:12.5px;font-variant-numeric:tabular-nums}
th,td{text-align:right;padding:4px 6px;border-bottom:1px solid var(--grid);white-space:nowrap}
th:first-child,td:first-child{text-align:left}th{color:var(--ink2);font-weight:600}table.narrow{max-width:420px}
table.coverage{position:relative;width:auto}table.coverage th.d,table.coverage th.m{text-align:center;padding:2px;font-weight:500}
table.coverage th.m{text-align:left;color:var(--muted);border-bottom:0}
td.cov{text-align:center;padding:0;width:22px;height:22px;border:2px solid var(--surface);border-radius:5px;
font-size:12px;cursor:default}td.cov:focus-visible{outline:2px solid var(--focus)}
i.cov{display:inline-flex;width:20px;height:20px;border-radius:4px;align-items:center;justify-content:center;
font-style:normal;font-size:12px}
details summary{cursor:pointer;color:var(--ink2);font-size:12.5px;margin-top:6px}
.empty{color:var(--muted);font-style:italic}
.controls{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:8px 0}
select,button{font:inherit;color:var(--ink);background:var(--surface);border:1px solid var(--axis);border-radius:6px;
padding:5px 10px}
.days{display:flex;flex-wrap:wrap;gap:6px}.day{display:inline-flex;gap:4px;align-items:center;border-radius:6px;
padding:2px 8px;font-size:12px}.pill{border-radius:999px;padding:1px 8px;font-size:12px;margin-left:6px}
.pill.warn{background:var(--warning);color:#0b0b0b}
#tip{position:fixed;pointer-events:none;background:var(--surface);color:var(--ink);border:1px solid var(--axis);
border-radius:8px;padding:8px 10px;font-size:13px;white-space:pre-line;max-width:min(330px,calc(100vw - 16px));
overflow-wrap:anywhere;box-shadow:0 6px 22px rgba(0,0,0,.22);
display:none;z-index:9;font-variant-numeric:tabular-nums}
@media (forced-colors:active){.sw,.fill-s1,.fill-s2,.fill-s3,.fill-s4{forced-color-adjust:none}}
"""

HEAD_JS = ("try{const t=localStorage.getItem('openrc-telem-theme');if(t)document.documentElement.dataset.theme=t}"
           "catch(_){}")

JS = """
const tip=document.getElementById('tip');
let inspected=null;
function place(x,y){const w=tip.offsetWidth,h=tip.offsetHeight;let px=x+14,py=y+14;
 if(px+w>innerWidth-8)px=x-w-14;if(py+h>innerHeight-8)py=y-h-14;
 tip.style.left=Math.max(8,px)+'px';tip.style.top=Math.max(8,py)+'px'}
function mark(point,on){if(!point)return;point.classList.toggle('inspected',on);
 const cursor=point.closest('[data-chart]')?.querySelector('.crosshair');
 if(!cursor)return;
 if(on){cursor.setAttribute('x1',point.dataset.center);cursor.setAttribute('x2',point.dataset.center)}
 cursor.toggleAttribute('hidden',!on)}
function show(t,x,y){if(t!==inspected){mark(inspected,false);inspected=t;mark(t,true);tip.textContent=t.dataset.tip}
 tip.style.display='block';place(x,y)}
function hide(){mark(inspected,false);inspected=null;tip.style.display='none'}
function showAt(t){const r=t.getBoundingClientRect();show(t,r.left+r.width/2,r.top+r.height/2)}
document.addEventListener('mousemove',ev=>{const t=ev.target.closest('[data-tip]');if(t)show(t,ev.clientX,ev.clientY);
 else if(inspected!==document.activeElement)hide()});
document.addEventListener('click',ev=>{const t=ev.target.closest('[data-chart] [data-tip]');if(t)showAt(t)});
document.addEventListener('focusin',ev=>{const t=ev.target.closest('[data-tip]');if(!t)return hide();
 const plot=t.closest('[data-chart]');
 if(plot&&t.tabIndex!==0){plot.querySelector('[data-tip][tabindex="0"]')?.setAttribute('tabindex','-1');t.tabIndex=0}
 showAt(t)});
document.addEventListener('focusout',hide);
document.addEventListener('keydown',ev=>{
 if(ev.key==='Escape'){hide();return}
 if(ev.altKey||ev.ctrlKey||ev.metaKey||ev.shiftKey)return;
 const point=ev.target.closest('[data-tip]'),plot=point?.closest('[data-chart]');
 if(!plot)return;
 const days=plot.dataset.chart==='days',previous=days?'ArrowLeft':'ArrowUp',next=days?'ArrowRight':'ArrowDown';
 if(![previous,next,'Home','End'].includes(ev.key))return;
 const points=[...plot.querySelectorAll('[data-tip]')],index=points.indexOf(point);
 const dest=ev.key==='Home'?0:ev.key==='End'?points.length-1:
  Math.min(points.length-1,Math.max(0,index+(ev.key===next?1:-1)));
 ev.preventDefault();
 const target=points[dest];if(target!==point)target.focus();else showAt(point);
});
document.addEventListener('scroll',()=>{
 const visible=inspected&&inspected===document.activeElement&&inspected.matches(':focus-visible');
 if(visible){const rect=inspected.getBoundingClientRect();if(rect.bottom>0&&rect.top<innerHeight){showAt(inspected);return}}
 hide();
},{capture:true,passive:true});
const tabs=[...document.querySelectorAll('[data-tab]')];
function openTab(key,focus){const t=tabs.find(b=>b.dataset.tab===key)||tabs[0];
 tabs.forEach(b=>{const on=b===t;b.setAttribute('aria-selected',on);b.tabIndex=on?0:-1;
  document.getElementById('panel-'+b.dataset.tab).hidden=!on});
 if(focus)t.focus();try{localStorage.setItem('openrc-stats-tab',t.dataset.tab)}catch(_){}
  return t.dataset.tab}
 function navigateTab(key,focus){const hash='#'+openTab(key,focus);
  if(location.hash!==hash)try{history.pushState(null,'',hash)}catch(_){location.hash=hash}}
 tabs.forEach((b,i)=>{b.addEventListener('click',()=>navigateTab(b.dataset.tab));
 b.addEventListener('keydown',ev=>{const d=ev.key==='ArrowRight'?1:ev.key==='ArrowLeft'?-1:0;
  const j=ev.key==='Home'?0:ev.key==='End'?tabs.length-1:d?(i+d+tabs.length)%tabs.length:-1;
   if(j>=0){ev.preventDefault();navigateTab(tabs[j].dataset.tab,true)}})});
 function syncTab(){const focused=document.activeElement;
   openTab(location.hash.slice(1),tabs.includes(focused)||focused?.closest('[role=tabpanel]'))}
 addEventListener('hashchange',syncTab);
 addEventListener('popstate',syncTab);
let first=location.hash.slice(1);try{first=first||localStorage.getItem('openrc-stats-tab')}catch(_){}
 const initial='#'+openTab(first||'overview');
 if(location.hash!==initial)try{history.replaceState(null,'',initial)}catch(_){}
const sel=document.getElementById('report');
if(sel){const pick=()=>{document.querySelectorAll('[data-report]').forEach(s=>s.hidden=s.dataset.report!==sel.value);
 try{localStorage.setItem('openrc-telem-report',sel.selectedOptions[0].text)}catch(_){}};
 try{const saved=localStorage.getItem('openrc-telem-report');
  for(const o of sel.options)if(o.text===saved)sel.value=o.value}catch(_){}
 sel.addEventListener('change',pick);pick()}
 const theme=document.getElementById('theme'), root=document.documentElement;
 const systemTheme=matchMedia('(prefers-color-scheme: dark)');
 const isDark=()=>root.dataset.theme?root.dataset.theme==='dark':systemTheme.matches;
 const indicateTheme=()=>theme.setAttribute('aria-pressed',isDark());
 theme.addEventListener('click',()=>{root.dataset.theme=isDark()?'light':'dark';indicateTheme();
  try{localStorage.setItem('openrc-telem-theme',root.dataset.theme)}catch(_){}});
 systemTheme.addEventListener('change',indicateTheme);indicateTheme();
const gen=Number(document.body.dataset.generated)*1000,stale=document.getElementById('stale'),age=document.getElementById('age');
function tick(){const s=Math.max(0,(Date.now()-gen)/1000);age.textContent=s<5400?Math.round(s/60)+' min old'
 :s<172800?(s/3600).toFixed(1)+' h old':(s/86400).toFixed(1)+' days old';stale.hidden=s<STALE}
const STALE=Number(document.body.dataset.stale);tick();setInterval(tick,30000);
"""


TABS = [("overview", "Overview"), ("players", "Players"), ("releases", "Releases"), ("downloads", "Downloads"), ("github", "GitHub"),
        ("website", "Website"), ("receiver", "Receiver")]


def render(snapshot):
    version = snapshot.get("snapshot_version")
    if version not in SNAPSHOT_VERSIONS:
        raise ValueError(f"unsupported snapshot_version {version!r} (supported: {sorted(SNAPSHOT_VERSIONS)})")
    if "github" not in snapshot:  # snapshots saved before the GitHub tab kept the archive under "downloads"
        snapshot = {**snapshot, "github": snapshot.get("downloads")}
    rows = ingest_rows(snapshot)
    releases, cells, day_state = coverage_model(snapshot, rows)
    alert_items = alerts(snapshot, rows, day_state)
    now = snapshot["generated_unix"]
    generated = datetime.fromtimestamp(now, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    reports = snapshot["insights"]
    if reports:
        spans = error_spans(reports)
        interrupted = interrupted_ingress(snapshot["ingest"])
        options = "".join(f'<option value="{i}">{e(r["week"])} · {e(r["release_id"])}</option>'
                          for i, r in enumerate(reports))
        insight_html = (f'<div class="controls"><label for="report">Week and release</label>'
                        f'<select id="report">{options}</select></div>'
                        + "".join(report_section(i, r, i > 0, spans, interrupted) for i, r in enumerate(reports)))
    else:
        insight_html = ""
    receiver = (f"{tiles(snapshot, rows, alert_items)}"
                f'<h2>Ingest outcomes per day</h2><p class="sub">Every POST /v1/batches by fixed outcome category, '
                f'UTC days. Hover, tap or use the arrow keys in the chart for details.</p>'
                f'<div class="split"><div class="panel">{legend(INGEST_SERIES)}{ingest_chart(rows)}{ingest_table(rows)}'
                f'</div><div class="panel"><h4>Refusals in the period</h4>{refusal_table(rows)}</div></div>'
                f'<h2>Daily rollup coverage</h2><p class="sub">Insight cells per release and UTC day; a day becomes '
                f'eligible at 01:00 UTC the next day and expires 47 h after it starts</p>'
                f'<div class="panel">{coverage_grid(rows, releases, cells, day_state)}</div>')
    if "legacy" in (snapshot.get("rollup_days") or {}).values():
        receiver += '<p class="note">Legacy rows predate whole-day rollup verification.</p>'
    panels = {
        "overview": overview_section(snapshot, rows, alert_items),
        "players": players_section(snapshot, insight_html, rows),
        "releases": releases_section(snapshot),
        "downloads": downloads_section(snapshot["github"], now, len(rows) or 30),
        "github": github_section(snapshot["github"], now),
        "website": website_section(snapshot.get("website"), snapshot["github"], now),
        "receiver": receiver,
    }
    count = len(alert_items)
    tabs = "".join(
        f'<button class="tab" role="tab" id="tab-{key}" aria-controls="panel-{key}" '
        f'aria-selected="{str(key == "overview").lower()}" tabindex="{0 if key == "overview" else -1}" '
        f'data-tab="{key}" type="button">{e(label)}'
        + (f' <span class="count">{count}</span>' if key == "overview" and count else "") + "</button>"
        for key, label in TABS)
    sections = "".join(f'<section class="tabpanel" role="tabpanel" id="panel-{key}" aria-labelledby="tab-{key}" '
                       f'tabindex="0"{"" if key == "overview" else " hidden"}>{panels[key]}</section>'
                       for key, _ in TABS)
    stale_hidden = "" if time.time() - now >= STALE_AFTER_S else " hidden"
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenRC Stats Dashboard</title><link rel="icon" href="data:,">
<script>{HEAD_JS}</script><style>{CSS}</style>
<noscript><style>.tabpanel[hidden]{{display:block}}.tabs,#theme{{display:none}}</style></noscript></head>
<body data-generated="{now}" data-stale="{STALE_AFTER_S}"><main>
<header><h1>OpenRC statistics</h1><div class="controls"><span class="sub">Snapshot {e(generated)}
(<span id="age">just taken</span>)</span>
<button id="theme" type="button" aria-label="Dark theme" aria-pressed="false">Light / dark</button></div></header>
<div id="stale" class="banner stale"{stale_hidden}><b>Old snapshot.</b> Figures and alerts are as of {e(generated)};
run <code>dashboard.py fetch</code> for current data.</div>
<div class="banner"><b>Operator-only.</b> Do not publish or share this page: player cells come from consenting
sessions with a floor of {snapshot['floor']} session-days, and GitHub traffic is owner-only data.</div>
<nav class="tabs" role="tablist" aria-label="Dashboard sections">{tabs}</nav>
{sections}
</main><div id="tip" role="tooltip"></div><script>{JS}</script></body></html>
"""


def load_downloads(directory, note):
    try:
        model = downloads.load(directory)
    except (OSError, ValueError, TypeError, sqlite3.Error) as error:
        print(f"download archive unreadable: {error}", file=sys.stderr)
        return None
    if model is not None and note:
        model["collect_note"] = note
    return model


def write_atomic(path, text, mode=0o644):
    """Replace a file with a complete, uniquely staged file on the same filesystem."""
    path = Path(path)
    handle = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=f".{path.name}.", delete=False)
    tmp = Path(handle.name)
    try:
        with handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        tmp.chmod(mode)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def publish_page(www, page, report):
    """Keep the previous HTML if publishing the new health report fails."""
    index = www / "index.html"
    with tempfile.TemporaryDirectory(prefix=".publish-", dir=www) as directory:
        previous = Path(directory) / "index.html"
        if index.exists():
            os.link(index, previous)
        write_atomic(index, page)
        try:
            write_atomic(www / "health.json", json.dumps(report, indent=1))
        except OSError:
            if previous.exists():
                os.replace(previous, index)
            else:
                index.unlink(missing_ok=True)
            raise


def utc_stamp(now):
    return datetime.fromtimestamp(now, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def timestamp_age(stamp, now):
    if not isinstance(stamp, str):
        return None
    try:
        parsed = datetime.fromisoformat(stamp)
        if parsed.tzinfo is not None:
            return round(now - parsed.timestamp())
    except (ValueError, OverflowError, OSError):
        pass
    return None


def source_health(stamp, now, max_age, *, error=False):
    age = timestamp_age(stamp, now)
    if error:
        status = "error"
    elif age is None:
        status = "missing"
    elif age < -300:
        status = "error"
    else:
        status = "stale" if age > max_age else "ok"
    return {"status": status, "observed_utc": stamp, "age_s": age}


def github_health(model, now):
    model = model or {}
    attempts = model.get("source_attempts") or model.get("attempts") or {}
    observed = model.get("source_utc") or {}
    result = {}
    for name, kind, legacy_stamp in (
        ("github_downloads", "release assets", model.get("collected_utc")),
        ("github_views", "traffic", None),
        ("github_clones", "clones", None),
        ("github_community", "community", model.get("community_utc")),
        ("github_stars", "star history", model.get("community_utc") if model.get("star_days") else None),
        ("github_referrals", "referrals", model.get("community_utc")),
    ):
        attempt = attempts.get(kind) or {}
        stamp = observed.get(kind) or legacy_stamp or (attempt.get("finished") if attempt.get("success") else None)
        result[name] = source_health(stamp, now, DOWNLOADS_STALE_S,
                                     error=attempt.get("success") is False)
    return result


def health(snapshot, now, receiver_max_age_s, github_note, problems, *, no_ga4=False):
    """Machine-readable build and source status. The reader must also measure build age."""
    snapshot = snapshot or {}
    receiver_age = round(now - snapshot["generated_unix"]) if "generated_unix" in snapshot else None
    website = snapshot.get("website") or {}
    sources = github_health(snapshot.get("github"), now)
    sources["website"] = source_health(website.get("collected_utc"), now, GA4_MAX_AGE_S,
                                       error=bool(website.get("error") or website.get("refresh_error")))
    if no_ga4:
        sources["website"] = {"status": "disabled", "observed_utc": None, "age_s": None}
    elif sources["website"]["status"] == "ok" and (website.get("errors") or website.get("missing")
                                                    or website.get("report_quality")):
        sources["website"]["status"] = "partial"
    issues = []
    if snapshot and not problems:
        rows = ingest_rows(snapshot)
        _, _, day_state = coverage_model(snapshot, rows)
        issues = [title for level, title, _ in alerts(snapshot, rows, day_state) if level == "critical"]
    if receiver_age is None or receiver_age < -300 or problems:
        status = "error"
    elif receiver_age > receiver_max_age_s:
        status = "stale"
    elif issues or github_note or any(s["status"] not in ("ok", "disabled") for s in sources.values()):
        status = "degraded"
    else:
        status = "ok"
    return {"status": status, "built_utc": utc_stamp(now), "receiver_age_s": receiver_age,
            "receiver_issues": issues, "sources": sources, "github_error": bool(github_note),
            "website_error": bool(website.get("error") or website.get("refresh_error")),
            "website_connected": bool(website), "problems": problems}


def read_snapshot(path):
    snapshot = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(snapshot, dict) or snapshot.get("snapshot_version") not in SNAPSHOT_VERSIONS:
        raise ValueError("unsupported snapshot format or version")
    stamp = snapshot.get("generated_unix")
    if type(stamp) not in (int, float) or not math.isfinite(stamp) or stamp <= 0:
        raise ValueError("missing or invalid generated_unix")
    datetime.fromtimestamp(stamp, tz=timezone.utc)
    return snapshot


def refresh_github(directory):
    authenticated = bool(os.environ.get("GH_TOKEN"))
    ok, note = downloads.collect(directory, public_only=not authenticated)
    if ok:
        return None
    if authenticated:
        public_ok, public_note = downloads.collect(directory, public_only=True)
        return (f"{note}; public counters refreshed" if public_ok else
                f"{note}; public fallback also failed: {public_note}")
    return note


def build(args):
    """TELEM-24c: unattended build for an always-on host. Reads a receiver snapshot file (pushed by the Proxmox
    host), optionally refreshes the GitHub archive and GA4, then writes index.html and health.json atomically into
    --www and the combined snapshot into --state-dir (not served). A failure keeps the last good page."""
    www, state = Path(args.www).resolve(), Path(args.state_dir).resolve()
    for directory in (www, state):
        if directory.is_relative_to(REPO):
            raise SystemExit("--www and --state-dir must be outside the repository (operator-only data)")
        directory.mkdir(parents=True, exist_ok=True)
    problems, snapshot, note = [], None, None
    combined_path = state / "dashboard.snapshot.json"
    try:
        snapshot = read_snapshot(args.receiver_snapshot)
    except (OSError, ValueError, OverflowError) as error:
        problems.append(f"receiver snapshot unreadable: {error.__class__.__name__}: {error}"[:300])
    if snapshot is not None:
        try:
            if snapshot["generated_unix"] > time.time() + 300:
                raise ValueError("receiver snapshot timestamp is in the future")
            try:
                previous = read_snapshot(combined_path)
            except (OSError, ValueError, OverflowError):
                previous = {}
            note = previous.get("github_refresh_error")
            if args.github_collect:
                note = refresh_github(args.downloads_dir)
            snapshot["github_refresh_error"] = note
            snapshot["github"] = load_downloads(args.downloads_dir, note)
            website = None if args.no_ga4 else ga4.fetch(args.days, args.ga4_property, args.ga4_credentials)
            old_website = previous.get("website") or {}
            if website and website.get("error") and old_website.get("daily") and not old_website.get("error"):
                website = {**old_website, "refresh_error": website["error"]}
            snapshot["website"] = website
            page = render(snapshot)
            report = health(snapshot, time.time(), args.receiver_max_age, note, problems, no_ga4=args.no_ga4)
            write_atomic(combined_path, json.dumps(snapshot, indent=1, sort_keys=True), mode=0o600)
            publish_page(www, page, report)
            print(json.dumps(report))
            return 0
        except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError) as error:
            print(f"dashboard build failed: {error!r}", file=sys.stderr)
            problems.append(f"dashboard build failed: {type(error).__name__}")
    report = health(None, time.time(), args.receiver_max_age, note, problems, no_ga4=args.no_ga4)
    write_atomic(www / "health.json", json.dumps(report, indent=1))
    print(json.dumps(report))
    return 1


def default_out():
    base = Path("U:/OpenRC/telemetry-dashboard") if os.name == "nt" and Path("U:/").exists() else (
        Path(os.environ.get("LOCALAPPDATA", Path.home())) / "OpenRCsimulator" / "telemetry-dashboard")
    return str(base / "dashboard.html")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    f = sub.add_parser("fetch", help="snapshot the receiver over SSH and render")
    f.add_argument("--ssh", default=os.environ.get("OPENRC_TELEMETRY_SSH"),
                   help="user@host of the Proxmox node (or receiver host); env OPENRC_TELEMETRY_SSH")
    f.add_argument("--key", default=os.environ.get("OPENRC_TELEMETRY_SSH_KEY"), help="SSH identity file")
    f.add_argument("--ct", default=os.environ.get("OPENRC_TELEMETRY_CT", "404"),
                   help="Proxmox container id; empty string runs directly on the SSH host")
    f.add_argument("--remote-root", default=REMOTE_ROOT)
    f.add_argument("--remote-env", default=REMOTE_ENV)
    f.add_argument("--days", type=int, default=30)
    f.add_argument("--weeks", type=int, default=4)
    f.add_argument("--floor", type=int, default=20)
    f.add_argument("--timeout", type=int, default=15)
    f.add_argument("--no-download-collect", action="store_true",
                   help="use the archived download counters without collecting from GitHub first")
    f.add_argument("--ga4-property", default=os.environ.get("OPENRC_GA4_PROPERTY"),
                   help="numeric GA4 property ID; env OPENRC_GA4_PROPERTY (default: found from the web stream)")
    f.add_argument("--ga4-credentials", default=None,
                   help="GA4 credential JSON (service account or authorized_user); env OPENRC_GA4_CREDENTIALS")
    f.add_argument("--no-ga4", action="store_true", help="skip the website (GA4) collection")
    b = sub.add_parser("build", help="unattended build from a receiver snapshot file (always-on host, TELEM-24c)")
    b.add_argument("--receiver-snapshot", required=True, help="JSON written by snapshot.py (pushed by the host)")
    b.add_argument("--www", required=True, help="served directory: index.html and health.json")
    b.add_argument("--state-dir", required=True, help="unserved directory for the combined snapshot")
    b.add_argument("--github-collect", action="store_true", help="refresh the GitHub archive first (needs gh)")
    b.add_argument("--no-ga4", action="store_true", help="skip the website (GA4) collection")
    b.add_argument("--ga4-property", default=os.environ.get("OPENRC_GA4_PROPERTY"))
    b.add_argument("--ga4-credentials", default=None)
    b.add_argument("--days", type=int, default=30)
    b.add_argument("--receiver-max-age", type=int, default=2 * 3600,
                   help="seconds before health.json reports the receiver snapshot as stale")
    b.add_argument("--downloads-dir", type=Path, default=downloads.default_dir(),
                   help="GitHub history archive directory; env OPENRC_ANALYTICS_DIR")
    r = sub.add_parser("render", help="render a saved snapshot")
    r.add_argument("--snapshot", required=True)
    r.add_argument("--ga4", action="store_true",
                   help="collect the website (GA4) reports now and save them into the snapshot before rendering")
    for p in (f, r):
        p.add_argument("--out", default=default_out(), help="HTML output path (local, outside the repository)")
        p.add_argument("--no-open", action="store_true", help="do not open the page in a browser")
        p.add_argument("--downloads-dir", type=Path, default=downloads.default_dir(),
                       help="GitHub history archive directory (tools/analytics); env OPENRC_ANALYTICS_DIR")
    args = parser.parse_args(argv)
    if args.command == "build":
        return build(args)
    out = Path(args.out).resolve()
    if out.is_relative_to(REPO):
        parser.error("--out must be outside the repository: the page holds operator-only data")
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.command == "fetch":
        if not args.ssh:
            parser.error("--ssh (or OPENRC_TELEMETRY_SSH) is required")
        snapshot = fetch(args, out)
        note = None
        if not args.no_download_collect and args.downloads_dir.is_dir():
            ok, message = downloads.collect(args.downloads_dir)
            note = None if ok else message
        snapshot["github"] = load_downloads(args.downloads_dir, note)
        snapshot["website"] = None if args.no_ga4 else ga4.fetch(args.days, args.ga4_property, args.ga4_credentials)
        snapshot_path(out).write_text(json.dumps(snapshot, indent=1, sort_keys=True), encoding="utf-8")
    else:
        snapshot = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
        if "github" not in snapshot and "downloads" not in snapshot:
            snapshot["github"] = load_downloads(args.downloads_dir, None)
        if args.ga4:
            snapshot["website"] = ga4.fetch(len(snapshot.get("ingest") or []) or 30)
            Path(args.snapshot).write_text(json.dumps(snapshot, indent=1, sort_keys=True), encoding="utf-8")
    try:
        page = render(snapshot)
    except (ValueError, KeyError) as error:
        raise SystemExit(f"cannot render this snapshot: {error!r}") from None
    out.write_text(page, encoding="utf-8")
    print(out)
    if not args.no_open:
        webbrowser.open(out.as_uri())
    return 0


if __name__ == "__main__":
    sys.exit(main())
