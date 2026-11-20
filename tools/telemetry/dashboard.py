"""Operator telemetry dashboard: fetch a receiver snapshot over SSH and render a local HTML page.

    python tools/telemetry/dashboard.py fetch  --ssh root@<receiver-host> [--key <identity>] [--ct 404]
    python tools/telemetry/dashboard.py render --snapshot <dashboard.snapshot.json>

`fetch` pipes `snapshot.py` to the receiver (Proxmox `pct exec` into the receiver container, or directly with
`--ct ''`), saves the JSON beside the page and renders it. `render` rebuilds the page from a saved snapshot. The
page is self-contained (no network requests) and is written to a local directory outside the repository, never
published: insight cells are operator-only (see services/telemetry/README.md). Standard library only.
"""
from __future__ import annotations

import argparse
from datetime import date, datetime, timedelta, timezone
import html
import json
import os
from pathlib import Path
import shlex
import sqlite3
import subprocess
import sys
import time
import webbrowser

import downloads

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
DOWNLOADS_STALE_S = 36 * 3600
PLATFORM_SLOTS = (("Windows", "s1"), ("macOS", "s2"), ("Linux", "s3"), ("Other", "s4"))

# Ingest outcome series (fixed order = fixed categorical slot).
INGEST_SERIES = [
    ("accepted", "Accepted", "s1"),
    ("duplicate", "Duplicate replay", "s2"),
    ("rejected", "Rejected (validation)", "s3"),
    ("other", "Other refusals", "s4"),
]
NOT_OUTCOMES = {"forwarded_for_present"}
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
    "overdue": ("warning", "!", "overdue (still fixable)"),
    "missed": ("critical", "\u2716", "missed (traffic, never rolled up)"),
    "none": ("neutral", "\u00b7", "no traffic"),
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


def rounded_right(x, y, w, h, r=4):
    """Bar path with a rounded data-end on the right and a square baseline on the left."""
    r = min(r, h / 2, w)
    return (f"M{x:.1f},{y:.1f}H{x + w - r:.1f}Q{x + w:.1f},{y:.1f} {x + w:.1f},{y + r:.1f}V{y + h - r:.1f}"
            f"Q{x + w:.1f},{y + h:.1f} {x + w - r:.1f},{y + h:.1f}H{x:.1f}Z")


def tip_attrs(lines, role="img"):
    """Hover/focus/tap target attributes: tooltip text plus the same text for assistive technology."""
    text = e("\n".join(lines), quote=True)
    label = f' role="{role}" aria-label="{e(" · ".join(lines), quote=True)}"' if role else ""
    return f'tabindex="0"{label} data-tip="{text}"'


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


def coverage_model(snapshot, rows):
    """{(release, day): state}, release list and day-level states for days no release rolled up."""
    now = snapshot["generated_unix"]
    accepted = {row["day"]: row["counts"]["accepted"] for row in rows}
    stored, rolled_days = {}, set()
    for c in snapshot["coverage"]:
        stored.setdefault((c["release_id"], c["day"]), {})[c["table"]] = c["status"]
        rolled_days.add(c["day"])
    releases = list(snapshot.get("releases_with_cells") or [])
    for release in sorted({c["release_id"] for c in snapshot["coverage"]}, reverse=True):
        if release not in releases:
            releases.append(release)

    def derived(day):
        age_h = (now - day_start(day)) / 3600
        if age_h < OVERDUE_AFTER_H:
            return "pending"
        if not accepted.get(day):
            return "none"
        return "overdue" if age_h < EXPIRES_AFTER_H else "missed"

    day_state = {row["day"]: derived(row["day"]) for row in rows if row["day"] not in rolled_days}
    cells = {}
    for release in releases:
        for row in rows:
            tables = stored.get((release, row["day"]))
            if tables:
                cells[(release, row["day"])] = (tables.get("cells", "none"), tables)
            elif row["day"] in rolled_days:
                cells[(release, row["day"])] = ("none", {})
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
                    "traffic arrived but no rollup ran inside the 47 h window: " + ", ".join(missed[-5:])))
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
    model = snapshot.get("downloads")
    if model is not None:
        note, attempt = model.get("collect_note"), model.get("last_attempt")
        if note:
            out.append(("warning", "Download refresh failed", f"{note}; showing the archived counters"))
        elif attempt and not attempt["success"]:
            out.append(("warning", "Last download collection failed", f"at {attempt['finished']}"))
        age = downloads.age_s(model, now)
        if age is not None and age > DOWNLOADS_STALE_S:
            out.append(("warning", "Download counters stale", f"last collected {fmt_age(age)}: check the "
                        "'OpenRC GitHub Analytics' task"))
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


def ingest_chart(rows):
    width, height, left, right, top, bottom = 900, 260, 52, 8, 12, 34
    plot_w, plot_h = width - left - right, height - top - bottom
    totals = [sum(r["counts"].values()) for r in rows]
    ticks = nice_ticks(max(totals, default=0))
    scale = plot_h / ticks[-1]
    slot = plot_w / max(len(rows), 1)
    bar = min(24.0, slot * 0.64)
    parts = [f'<svg viewBox="0 0 {width} {height}" aria-label="Ingest outcomes per UTC day" class="chart">']
    for tick in ticks:
        y = top + plot_h - tick * scale
        cls = "axis" if tick == 0 else "grid"
        parts.append(f'<line class="{cls}" x1="{left}" x2="{width - right}" y1="{y:.1f}" y2="{y:.1f}"/>')
        parts.append(f'<text class="tick" x="{left - 8}" y="{y + 4:.1f}" text-anchor="end">{fmt_compact(tick)}</text>')
    label_every = max(1, round(len(rows) / 10))
    for index, row in enumerate(rows):
        x = left + index * slot + (slot - bar) / 2
        base = top + plot_h
        drawn = [(key, row["counts"][key], cls) for key, _, cls in INGEST_SERIES if row["counts"][key]]
        for position, (key, count, cls) in enumerate(drawn):
            h = count * scale
            seg_h = max(h - (2 if position else 0), 1)
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
        parts.append(f'<rect class="hit" x="{left + index * slot:.1f}" y="{top}" width="{slot:.1f}" '
                     f'height="{plot_h}" {tip_attrs(lines)}/>')
        if index % label_every == 0 or index == len(rows) - 1:
            parts.append(f'<text class="tick" x="{left + index * slot + slot / 2:.1f}" y="{height - 12}" '
                         f'text-anchor="middle">{e(row["day"][5:])}</text>')
    parts.append("</svg>")
    return scroll("".join(parts), 640)


def ingest_table(rows):
    head = "".join(f"<th>{e(label)}</th>" for _, label, _ in INGEST_SERIES)
    body = "".join(
        f"<tr><td>{e(row['day'])}</td>" + "".join(f"<td>{fmt_int(row['counts'][k])}</td>" for k, _, _ in INGEST_SERIES)
        + "<td>" + e(", ".join(f"{c} {n}" for c, n in sorted(row["detail"].items())
                               if c not in ("accepted", "duplicate")) or "-") + "</td></tr>"
        for row in reversed(rows))
    return (f'<details><summary>Table</summary>{scroll(f"<table><thead><tr><th>UTC day</th>{head}<th>Refusal detail</th>"
            f"</tr></thead><tbody>{body}</tbody></table>")}</details>')


def legend(series):
    items = "".join(f'<span class="key"><i class="sw fill-{cls}"></i>{e(label)}</span>' for _, label, cls in series)
    return f'<div class="legend">{items}</div>'


def hbar_chart(rows, unit_fmt, aria):
    """rows: [(label, value, tip_lines, is_combined)] -> horizontal bar chart (single series), largest first."""
    if not rows:
        return '<p class="empty">Nothing to show at this floor.</p>'
    rows = sorted((r for r in rows if not r[3]), key=lambda r: (-r[1], r[0])) + [r for r in rows if r[3]]
    width, label_w, value_w, row_h, bar_h = 560, 210, 72, 26, 14
    plot_w = width - label_w - value_w
    maximum = max(value for _, value, _, _ in rows) or 1
    height = row_h * len(rows) + 4
    parts = [f'<svg viewBox="0 0 {width} {height}" aria-label="{e(aria, quote=True)}" class="chart hbar">',
             f'<line class="axis" x1="{label_w}" x2="{label_w}" y1="0" y2="{height}"/>']
    for index, (name, value, tip, combined) in enumerate(rows):
        y = index * row_h + (row_h - bar_h) / 2 + 2
        w = max(value / maximum * plot_w, 1.5)
        cls = "fill-other" if combined else "fill-s1"
        short = name if len(name) <= 30 else name[:29] + "\u2026"
        parts.append(f'<text class="rowlabel{" muted" if combined else ""}" x="{label_w - 8}" y="{y + bar_h - 3:.1f}" '
                     f'text-anchor="end"><title>{e(name)}</title>{e(short)}</text>')
        parts.append(f'<path class="{cls}" d="{rounded_right(label_w, y, w, bar_h)}"/>')
        parts.append(f'<text class="value" x="{label_w + w + 6:.1f}" y="{y + bar_h - 3:.1f}">{e(unit_fmt(value))}</text>')
        parts.append(f'<rect class="hit" x="0" y="{index * row_h + 2}" width="{width}" height="{row_h}" '
                     f'{tip_attrs([name, *tip])}/>')
    parts.append("</svg>")
    return scroll("".join(parts), 420)


def table_rows(entry):
    rows = list(entry["published"]) if entry else []
    if entry and entry.get("combined"):
        rows.append({**entry["combined"], "_combined": True})
    return rows


def cadence(metrics):
    total = sum(metrics[f"hist{i}"] for i in range(HIST_LEN)) or 1
    over = lambda first: sum(metrics[f"hist{i}"] for i in range(first, HIST_LEN))  # noqa: E731
    seconds = metrics["interval_sum_us"] / 1_000_000
    return {"minutes": seconds / 60, "fps": metrics["rendered_frames"] / seconds if seconds else 0.0,
            "p33": 100 * over(ABOVE_33_MS) / total, "p50": 100 * over(ABOVE_50_MS) / total,
            "hitch_per_min": over(ABOVE_100_MS) * 60 / seconds if seconds else 0.0}


def cadence_block(title, entry):
    rows = table_rows(entry)
    bars, body = [], []
    for row in rows:
        name = " / ".join(row["dims"])
        c = cadence(row["metrics"])
        tip = [f"Session-days {row['sessions']}", f"FPS estimate {c['fps']:.1f}", f"Observed {c['minutes']:.0f} min",
               f"Intervals > 33.3 ms {c['p33']:.1f}%", f"Intervals > 50 ms {c['p50']:.1f}%",
               f"> 100 ms per minute {c['hitch_per_min']:.2f}"]
        bars.append((name, c["fps"], tip, row.get("_combined", False)))
        body.append(f"<tr><td>{e(name)}</td><td>{row['sessions']}</td><td>{c['minutes']:.0f}</td>"
                    f"<td>{c['fps']:.1f}</td><td>{c['p33']:.1f}%</td><td>{c['p50']:.1f}%</td>"
                    f"<td>{c['hitch_per_min']:.2f}</td></tr>")
    chart = hbar_chart(bars, lambda v: f"{v:.1f} fps", f"FPS estimate by {title}")
    table = ""
    if body:
        table = scroll('<table><thead><tr><th>' + e(title) + '</th><th>Session-days</th><th>Minutes</th><th>FPS</th>'
                       '<th>&gt; 33.3 ms</th><th>&gt; 50 ms</th><th>&gt; 100 ms / min</th></tr></thead><tbody>'
                       + "".join(body) + "</tbody></table>")
    return f'<div class="card"><h4>{e(title)}</h4><p class="sub">FPS estimate (render cadence)</p>{chart}{table}</div>'


def simple_block(title, entry, value_of, value_fmt, sub, extra_cols):
    rows = table_rows(entry)
    bars, body = [], []
    for row in rows:
        name = " / ".join(row["dims"])
        cols = [(col, fn(row)) for col, fn in extra_cols]
        bars.append((name, value_of(row), [f"Session-days {row['sessions']}", *(f"{c} {v}" for c, v in cols)],
                     row.get("_combined", False)))
        body.append("<tr><td>" + e(name) + "</td><td>" + str(row["sessions"]) + "</td>"
                    + "".join(f"<td>{e(str(v))}</td>" for _, v in cols) + "</tr>")
    chart = hbar_chart(bars, value_fmt, f"{sub} by {title}")
    table = ""
    if body:
        heads = "".join(f"<th>{e(c)}</th>" for c, _ in extra_cols)
        table = ("<details><summary>Table</summary>" + scroll(
            f'<table><thead><tr><th>{e(title)}</th><th>Session-days</th>{heads}</tr></thead>'
            f'<tbody>{"".join(body)}</tbody></table>') + "</details>")
    return f'<div class="card"><h4>{e(title)}</h4><p class="sub">{e(sub)}</p>{chart}{table}</div>'


def report_section(index, report, hidden):
    attrs = f' data-report="{index}"' + (" hidden" if hidden else "")
    if "error" in report:
        return f'<section class="report"{attrs}><p class="empty">Refused: {e(report["error"])}</p></section>'
    tables = report["tables"]
    chips = []
    for d in report["days"]:
        cls, glyph, label = STATES.get(d["status"], STATES["none"] if d["status"] == "missing" else STATES["no_data"])
        chips.append(f'<span class="day st-{cls}" title="{e(d["day"])}: {e(d["status"])}"><b>{glyph}</b>'
                     f'{e(d["day"][5:])}<span class="vh"> {e(d["status"])}</span></span>')
    ready = sum(1 for d in report["days"] if d["status"] == "ready")
    note = "" if report["week_closed"] else '<span class="pill warn">week still open: figures can change</span>'
    head = (f'<div class="reporthead"><div class="days">{"".join(chips)}</div><p class="sub">{ready} of 7 days rolled '
            f'up · cell floor {report["floor"]} session-days {note}</p>'
            f'<p class="note"><i class="sw fill-other"></i> <b>combined small cells</b> pools every cell below the floor '
            f'(plus the smallest shown cell when needed), so each table still adds up to its full population. FPS is '
            f'only comparable within one frame-pacing class: VSync or an FPS cap limits it by design.</p></div>')
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
    errors = simple_block(
        "Error category", tables.get("errors"), lambda r: r["metrics"]["count"], fmt_int, "Occurrences",
        [("Occurrences", lambda r: fmt_int(r["metrics"]["count"]))])
    mix = "".join(simple_block(title, tables.get(key), lambda r: r["sessions"], fmt_int, "Session-days", [])
                  for key, title in MIX_TABLES)
    return (f'<section class="report"{attrs}>{head}'
            f'<h3>Flight frame cadence</h3><div class="cards">{flight}</div>'
            f'<h3>Menu and workshop cadence</h3><div class="cards">{menus}</div>'
            f'<h3>Vehicle usage and errors</h3><div class="cards">{usage}{errors}</div>'
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
    width, label_w, value_w, row_h, bar_h = 640, 110, 56, 24, 14
    plot_w = width - label_w - value_w
    maximum = max((total for _, _, total in releases), default=0) or 1
    height = row_h * len(releases) + 4
    parts = [f'<svg viewBox="0 0 {width} {height}" aria-label="Downloads per release by platform" class="chart">',
             f'<line class="axis" x1="{label_w}" x2="{label_w}" y1="0" y2="{height}"/>']
    for index, (tag, counts, total) in enumerate(releases):
        y = index * row_h + (row_h - bar_h) / 2 + 2
        x = float(label_w)
        drawn = [(platform, counts[platform], cls) for platform, cls in PLATFORM_SLOTS if counts[platform]]
        for position, (platform, count, cls) in enumerate(drawn):
            w = count / maximum * plot_w
            last = position == len(drawn) - 1
            seg = max(w - (0 if last else 2), 1)
            if last:
                parts.append(f'<path class="fill-{cls}" d="{rounded_right(x, y, seg, bar_h)}"/>')
            else:
                parts.append(f'<rect class="fill-{cls}" x="{x:.1f}" y="{y:.1f}" width="{seg:.1f}" height="{bar_h}"/>')
            x += w
        parts.append(f'<text class="rowlabel" x="{label_w - 8}" y="{y + bar_h - 3:.1f}" text-anchor="end">{e(tag)}</text>')
        parts.append(f'<text class="value" x="{x + 6:.1f}" y="{y + bar_h - 3:.1f}">{fmt_int(total)}</text>')
        tip = [tag, f"Total {fmt_int(total)}"] + [f"{p}: {fmt_int(counts[p])}" for p, _ in PLATFORM_SLOTS if counts[p]]
        parts.append(f'<rect class="hit" x="0" y="{index * row_h + 2}" width="{width}" height="{row_h}" '
                     f'{tip_attrs(tip)}/>')
    parts.append("</svg>")
    return scroll("".join(parts), 480)


def column_chart(points, aria):
    """Single-series columns: points [(iso_day, value, tip_lines)]."""
    width, height, left, right, top, bottom = 900, 220, 52, 8, 12, 34
    plot_w, plot_h = width - left - right, height - top - bottom
    ticks = nice_ticks(max((v for _, v, _ in points), default=0))
    scale = plot_h / ticks[-1]
    slot = plot_w / max(len(points), 1)
    bar = min(24.0, slot * 0.64)
    parts = [f'<svg viewBox="0 0 {width} {height}" aria-label="{e(aria, quote=True)}" class="chart">']
    for tick in ticks:
        y = top + plot_h - tick * scale
        parts.append(f'<line class="{"axis" if tick == 0 else "grid"}" x1="{left}" x2="{width - right}" '
                     f'y1="{y:.1f}" y2="{y:.1f}"/>')
        parts.append(f'<text class="tick" x="{left - 8}" y="{y + 4:.1f}" text-anchor="end">{fmt_compact(tick)}</text>')
    label_every = max(1, round(len(points) / 10))
    for index, (label, value, tip) in enumerate(points):
        x = left + index * slot + (slot - bar) / 2
        if value:
            h = value * scale
            parts.append(f'<path class="fill-s1" d="{rounded_top(x, top + plot_h - h, bar, h)}"/>')
        parts.append(f'<rect class="hit" x="{left + index * slot:.1f}" y="{top}" width="{slot:.1f}" '
                     f'height="{plot_h}" {tip_attrs(tip)}/>')
        if index % label_every == 0 or index == len(points) - 1:
            parts.append(f'<text class="tick" x="{left + index * slot + slot / 2:.1f}" y="{height - 12}" '
                         f'text-anchor="middle">{e(label[5:])}</text>')
    parts.append("</svg>")
    return scroll("".join(parts), 640)


def downloads_section(model, now, days):
    head = "<h2>Release downloads</h2>"
    if model is None:
        return (head + '<div class="panel"><p class="empty">No GitHub history archive found. Run '
                "<code>python tools/analytics/github_history.py collect --output-dir &lt;dir&gt;</code> or install "
                "its daily task (tools/analytics/README.md), or pass --downloads-dir.</p></div>")
    releases = downloads.per_release(model)
    total = sum(t for _, _, t in releases)
    platforms = {p: sum(c[p] for _, c, _ in releases) for p, _ in PLATFORM_SLOTS}
    latest = releases[0] if releases else None
    share = " · ".join(f"{p} {platforms[p] * 100 / total:.0f}%" for p, _ in PLATFORM_SLOTS if platforms[p]) if total else ""
    latest_split = " · ".join(f"{p} {latest[1][p]}" for p, _ in PLATFORM_SLOTS if latest[1][p]) if latest else ""
    items = [
        ("Package downloads, all releases", fmt_int(total), share),
        (f"Latest release {latest[0]}" if latest else "Latest release", fmt_int(latest[2]) if latest else "-",
         latest_split),
        ("Downloads, last 7 days", fmt_int(downloads.recent_increase(model, now, 7)),
         "matched counter increases between collections"),
        ("Counters collected", fmt_age(downloads.age_s(model, now)), model["collected_utc"] or "never"),
    ]
    tiles_html = '<div class="tiles">' + "".join(
        f'<div class="tile"><div class="tl">{e(a)}</div><div class="tv">{e(b)}</div><div class="ts">{e(c)}</div></div>'
        for a, b, c in items) + "</div>"
    by_day = downloads.per_day(model)
    today = datetime.fromtimestamp(now, tz=timezone.utc).date()
    points = []
    for offset in range(days - 1, -1, -1):
        day = (today - timedelta(days=offset)).isoformat()
        value, partial = by_day.get(day, (0, False))
        tip = [day, f"Downloads {fmt_int(value)}" if day in by_day else "no collection ended this day"]
        if partial:
            tip.append("partial: assets added, removed or reset")
        points.append((day, value, tip))
    heads = "".join(f"<th>{p}</th>" for p, _ in PLATFORM_SLOTS)
    body = "".join(f"<tr><td>{e(tag)}</td>" + "".join(f"<td>{fmt_int(c[p])}</td>" for p, _ in PLATFORM_SLOTS)
                   + f"<td>{fmt_int(t)}</td></tr>" for tag, c, t in releases)
    table = scroll(f"<table><thead><tr><th>Release</th>{heads}<th>Total</th></tr></thead><tbody>{body}</tbody></table>")
    chart = release_chart(releases) if releases else '<p class="empty">No packages yet.</p>'
    keys = legend([(p, p, c) for p, c in PLATFORM_SLOTS if platforms[p]])
    return (f'{head}<p class="sub">GitHub release package counters ({e(model["pattern"])}) from the local history '
            "archive: cumulative and including repeat or automated downloads, not people or installs</p>"
            f'{tiles_html}<div class="pair"><div class="panel">'
            "<h4>Downloads per collection day</h4><p class=\"sub\">Counter increase between consecutive collections, "
            f'dated by the later collection (UTC)</p>{column_chart(points, "Downloads per collection day")}</div>'
            f'<div class="panel"><h4>Downloads per release</h4>{keys}{chart}'
            f"<details><summary>Table</summary>{table}</details></div></div>")


CSS = """
:root{color-scheme:light;--surface:#fcfcfb;--page:#f9f9f7;--ink:#0b0b0b;--ink2:#52514e;--muted:#6b6964;
--grid:#e1e0d9;--axis:#c3c2b7;--ring:rgba(11,11,11,.10);--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;
--other:#b5b3ab;--good:#0ca30c;--warning:#fab219;--critical:#d03b3b;--wash:rgba(11,11,11,.05);--focus:#2a78d6}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){color-scheme:dark;--surface:#1a1a19;--page:#0d0d0d;
--ink:#f0efec;--ink2:#c3c2b7;--muted:#9a988f;--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#3987e5;
--s2:#d95926;--s3:#199e70;--s4:#c98500;--other:#5c5b56;--wash:rgba(255,255,255,.06);--focus:#86b6ef}}
:root[data-theme="dark"]{color-scheme:dark;--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;
--muted:#9a988f;--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#3987e5;--s2:#d95926;--s3:#199e70;
--s4:#c98500;--other:#5c5b56;--wash:rgba(255,255,255,.06);--focus:#86b6ef}
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
.alerts{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,360px),1fr));gap:8px;margin-top:12px}
.alert{display:flex;gap:10px;align-items:flex-start;background:var(--surface);border:1px solid var(--ring);
border-radius:8px;padding:8px 12px}.alert b{display:block}.alert code{font-size:12px}
.badge{display:inline-flex;flex:none;width:22px;height:22px;border-radius:50%;align-items:center;
justify-content:center;font-size:13px;font-weight:700;vertical-align:3px}
.st-good{background:var(--good);color:#0b0b0b}.st-warning{background:var(--warning);color:#0b0b0b}
.st-critical{background:var(--critical);color:#fff}.st-muted{background:var(--grid);color:var(--ink2)}
.st-neutral{background:transparent;color:var(--muted);box-shadow:inset 0 0 0 1px var(--axis)}
.chart{width:100%;height:auto;display:block}line.grid{stroke:var(--grid);stroke-width:1}
line.axis{stroke:var(--axis);stroke-width:1}.tick{fill:var(--muted);font-size:11px;font-variant-numeric:tabular-nums}
.rowlabel{fill:var(--ink2);font-size:12px}.value{fill:var(--ink);font-size:12px;font-variant-numeric:tabular-nums}
.fill-s1{fill:var(--s1);background:var(--s1)}.fill-s2{fill:var(--s2);background:var(--s2)}
.fill-s3{fill:var(--s3);background:var(--s3)}.fill-s4{fill:var(--s4);background:var(--s4)}
.fill-other{fill:var(--other);background:var(--other)}
.hit{fill:transparent;cursor:default;outline:none}.hit:hover,.hit:focus{fill:var(--wash)}
.hit:focus-visible{stroke:var(--focus);stroke-width:2}
.legend{display:flex;flex-wrap:wrap;gap:6px 16px;margin:8px 0;color:var(--ink2);font-size:13px}
.key{display:inline-flex;align-items:center;gap:6px}.sw{display:inline-block;width:12px;height:12px;border-radius:3px;
vertical-align:-1px}.note{color:var(--ink2);font-size:12.5px;margin:6px 0 0}
.split{display:grid;grid-template-columns:minmax(0,3fr) minmax(0,1fr);gap:16px}
@media (max-width:900px){.split{grid-template-columns:minmax(0,1fr)}}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,440px),1fr));gap:12px}
.pair{display:grid;align-items:start;grid-template-columns:repeat(auto-fit,minmax(min(100%,520px),1fr));gap:12px;margin-top:12px}
.scroll{overflow-x:auto;max-width:100%}
table{border-collapse:collapse;width:100%;margin-top:8px;font-size:12.5px;font-variant-numeric:tabular-nums}
th,td{text-align:right;padding:4px 6px;border-bottom:1px solid var(--grid);white-space:nowrap}
th:first-child,td:first-child{text-align:left}th{color:var(--ink2);font-weight:600}table.narrow{max-width:420px}
table.coverage{width:auto}table.coverage th.d,table.coverage th.m{text-align:center;padding:2px;font-weight:500}
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
#tip{position:fixed;pointer-events:none;background:var(--surface);color:var(--ink);border:1px solid var(--ring);
border-radius:8px;padding:8px 10px;font-size:12px;white-space:pre;box-shadow:0 4px 16px rgba(0,0,0,.18);
display:none;z-index:9;font-variant-numeric:tabular-nums}
@media (forced-colors:active){.sw,.fill-s1,.fill-s2,.fill-s3,.fill-s4{forced-color-adjust:none}}
"""

HEAD_JS = ("try{const t=localStorage.getItem('openrc-telem-theme');if(t)document.documentElement.dataset.theme=t}"
           "catch(_){}")

JS = """
const tip=document.getElementById('tip');
function place(x,y){const w=tip.offsetWidth,h=tip.offsetHeight;let px=x+14,py=y+14;
 if(px+w>innerWidth-8)px=x-w-14;if(py+h>innerHeight-8)py=y-h-14;
 tip.style.left=Math.max(8,px)+'px';tip.style.top=Math.max(8,py)+'px'}
function show(t,x,y){tip.textContent=t.dataset.tip;tip.style.display='block';place(x,y)}
function hide(){tip.style.display='none'}
document.addEventListener('mousemove',ev=>{const t=ev.target.closest('[data-tip]');if(t)show(t,ev.clientX,ev.clientY);
 else if(!document.activeElement||!document.activeElement.dataset||!document.activeElement.dataset.tip)hide()});
document.addEventListener('focusin',ev=>{const t=ev.target.closest('[data-tip]');if(!t)return hide();
 const r=t.getBoundingClientRect();show(t,r.left+r.width/2,r.top+r.height/2)});
document.addEventListener('focusout',hide);
document.addEventListener('keydown',ev=>{if(ev.key==='Escape')hide()});
document.addEventListener('scroll',hide,{passive:true});
const sel=document.getElementById('report');
if(sel){const pick=()=>{document.querySelectorAll('[data-report]').forEach(s=>s.hidden=s.dataset.report!==sel.value);
 try{localStorage.setItem('openrc-telem-report',sel.selectedOptions[0].text)}catch(_){}};
 try{const saved=localStorage.getItem('openrc-telem-report');
  for(const o of sel.options)if(o.text===saved)sel.value=o.value}catch(_){}
 sel.addEventListener('change',pick);pick()}
document.getElementById('theme').addEventListener('click',()=>{const r=document.documentElement;
 const dark=r.dataset.theme?r.dataset.theme==='dark':matchMedia('(prefers-color-scheme: dark)').matches;
 r.dataset.theme=dark?'light':'dark';try{localStorage.setItem('openrc-telem-theme',r.dataset.theme)}catch(_){}});
const gen=Number(document.body.dataset.generated)*1000,stale=document.getElementById('stale'),age=document.getElementById('age');
function tick(){const s=Math.max(0,(Date.now()-gen)/1000);age.textContent=s<5400?Math.round(s/60)+' min old'
 :s<172800?(s/3600).toFixed(1)+' h old':(s/86400).toFixed(1)+' days old';stale.hidden=s<STALE}
const STALE=Number(document.body.dataset.stale);tick();setInterval(tick,30000);
"""


def render(snapshot):
    version = snapshot.get("snapshot_version")
    if version not in SNAPSHOT_VERSIONS:
        raise ValueError(f"unsupported snapshot_version {version!r} (supported: {sorted(SNAPSHOT_VERSIONS)})")
    rows = ingest_rows(snapshot)
    releases, cells, day_state = coverage_model(snapshot, rows)
    alert_items = alerts(snapshot, rows, day_state)
    generated = datetime.fromtimestamp(snapshot["generated_unix"], tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    reports = snapshot["insights"]
    if reports:
        options = "".join(f'<option value="{i}">{e(r["week"])} · {e(r["release_id"])}</option>'
                          for i, r in enumerate(reports))
        insight_html = (f'<div class="controls"><label for="report">Week and release</label>'
                        f'<select id="report">{options}</select></div>'
                        + "".join(report_section(i, r, i > 0) for i, r in enumerate(reports)))
    else:
        insight_html = '<p class="empty">No rolled-up insight days in the selected weeks yet.</p>'
    stale_hidden = "" if time.time() - snapshot["generated_unix"] >= STALE_AFTER_S else " hidden"
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenRC Telemetry Dashboard</title><script>{HEAD_JS}</script><style>{CSS}</style></head>
<body data-generated="{snapshot['generated_unix']}" data-stale="{STALE_AFTER_S}"><main>
<header><h1>OpenRC telemetry</h1><div class="controls"><span class="sub">Snapshot {e(generated)}
(<span id="age">just taken</span>) · last {len(rows)} UTC days</span>
<button id="theme" type="button">Light / dark</button></div></header>
<div id="stale" class="banner stale"{stale_hidden}><b>Old snapshot.</b> Figures and alerts are as of {e(generated)};
run <code>dashboard.py fetch</code> for current data.</div>
<div class="banner"><b>Operator-only.</b> Do not publish or share this page. Counts are session-day observations from
consenting sessions, not players or machines; insight cells below {snapshot['floor']} session-days are combined or
hidden.</div>
{alerts_panel(alert_items)}
{tiles(snapshot, rows, alert_items)}
{downloads_section(snapshot.get("downloads"), snapshot["generated_unix"], len(rows) or 30)}
<h2>Ingest outcomes per day</h2><p class="sub">Every POST /v1/batches by fixed outcome category, UTC days; hover,
tap or tab to a day for detail</p>
<div class="split"><div class="panel">{legend(INGEST_SERIES)}{ingest_chart(rows)}{ingest_table(rows)}</div>
<div class="panel"><h4>Refusals in the period</h4>{refusal_table(rows)}</div></div>
<h2>Daily rollup coverage</h2><p class="sub">Insight cells per release and UTC day; a day becomes eligible at
01:00 UTC the next day and expires 47 h after it starts</p>
<div class="panel">{coverage_grid(rows, releases, cells, day_state)}</div>
<h2>Weekly insights</h2><p class="sub">Pooled over the rolled-up days of each ISO week, per-cell disclosure floor</p>
{insight_html}
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


def default_out():
    base = Path("U:/OpenRC/telemetry-dashboard") if Path("U:/").exists() else (
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
    r = sub.add_parser("render", help="render a saved snapshot")
    r.add_argument("--snapshot", required=True)
    for p in (f, r):
        p.add_argument("--out", default=default_out(), help="HTML output path (local, outside the repository)")
        p.add_argument("--no-open", action="store_true", help="do not open the page in a browser")
        p.add_argument("--downloads-dir", type=Path, default=downloads.default_dir(),
                       help="GitHub history archive directory (tools/analytics); env OPENRC_ANALYTICS_DIR")
    args = parser.parse_args(argv)
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
        snapshot["downloads"] = load_downloads(args.downloads_dir, note)
        snapshot_path(out).write_text(json.dumps(snapshot, indent=1, sort_keys=True), encoding="utf-8")
    else:
        snapshot = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
        if "downloads" not in snapshot:
            snapshot["downloads"] = load_downloads(args.downloads_dir, None)
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
