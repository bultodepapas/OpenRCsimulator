"""Operator telemetry dashboard: fetch a receiver snapshot over SSH and render a local HTML page.

    python tools/telemetry/dashboard.py fetch  --ssh root@<receiver-host> [--key <identity>] [--ct 404]
    python tools/telemetry/dashboard.py render --snapshot <snapshot.json>

`fetch` pipes `snapshot.py` to the receiver (Proxmox `pct exec` into the receiver container, or directly with
`--ct ''`), saves the JSON beside the page and renders it. `render` rebuilds the page from a saved snapshot. The
page is self-contained (no network requests) and is written to a local directory, never published: insight cells
are operator-only (see services/telemetry/README.md). Standard library only.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import html
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import webbrowser

HERE = Path(__file__).resolve().parent
REMOTE_ROOT = "/opt/openrc-telemetry/current"
REMOTE_ENV = "/etc/openrc-telemetry/env"
# contract.HISTOGRAM_UPPER_US = (8333, 16667, 33333, 50000, 100000, 250000, 1000000, 5000000): buckets from these
# indices up lie wholly above 33.3 / 50 / 100 ms (same rule as report.py).
ABOVE_33_MS, ABOVE_50_MS, ABOVE_100_MS = 3, 4, 5
HIST_LEN = 8

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
STATUS_GLYPH = {"ready": ("good", "\u2713", "ready"), "no_data": ("muted", "\u2013", "no data"),
                "suppressed": ("warning", "!", "suppressed"), "missing": ("missing", "\u00b7", "missing")}

e = html.escape


# ---------------------------------------------------------------------------------------------- fetch


def remote_command(ct, root, env_file, days, weeks, floor):
    inner = (f"cd {shlex.quote(root + '/services/telemetry')} && set -a && . {shlex.quote(env_file)} && set +a && "
             f"exec runuser -u telemetry -- {shlex.quote(root + '/venv/bin/python')} - "
             f"--days {int(days)} --weeks {int(weeks)} --floor {int(floor)}")
    return f"pct exec {int(ct)} -- bash -c {shlex.quote(inner)}" if ct else f"bash -c {shlex.quote(inner)}"


def fetch(args):
    command = ["ssh", "-o", "BatchMode=yes", "-o", f"ConnectTimeout={args.timeout}"]
    if args.key:
        command += ["-i", os.path.expanduser(args.key)]
    command += [args.ssh, remote_command(args.ct, args.remote_root, args.remote_env, args.days, args.weeks,
                                         args.floor)]
    result = subprocess.run(command, input=(HERE / "snapshot.py").read_bytes(), capture_output=True,
                            timeout=args.timeout + 120)
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode("utf-8", "replace"))
        raise SystemExit(f"snapshot failed (exit {result.returncode})")
    snapshot = json.loads(result.stdout.decode("utf-8"))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    (out.parent / "snapshot.json").write_text(json.dumps(snapshot, indent=1, sort_keys=True), encoding="utf-8")
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
    for step in (1, 2, 2.5, 5, 10):
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


def tip_attr(lines):
    return e("\n".join(lines), quote=True)


# ---------------------------------------------------------------------------------------------- sections


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


def ingest_chart(rows):
    width, height, left, right, top, bottom = 900, 260, 52, 8, 12, 34
    plot_w, plot_h = width - left - right, height - top - bottom
    totals = [sum(r["counts"].values()) for r in rows]
    ticks = nice_ticks(max(totals, default=0))
    scale = plot_h / ticks[-1]
    slot = plot_w / max(len(rows), 1)
    bar = min(24.0, slot * 0.64)
    parts = [f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="Ingest outcomes per UTC day" '
             f'class="chart">']
    for tick in ticks:
        y = top + plot_h - tick * scale
        cls = "axis" if tick == 0 else "grid"
        parts.append(f'<line class="{cls}" x1="{left}" x2="{width - right}" y1="{y:.1f}" y2="{y:.1f}"/>')
        parts.append(f'<text class="tick" x="{left - 8}" y="{y + 4:.1f}" text-anchor="end">{fmt_compact(tick)}</text>')
    label_every = max(1, round(len(rows) / 10))
    for index, row in enumerate(rows):
        x = left + index * slot + (slot - bar) / 2
        base = top + plot_h
        drawn = [(key, row["counts"][key], slot_cls) for key, _, slot_cls in INGEST_SERIES if row["counts"][key]]
        for position, (key, count, slot_cls) in enumerate(drawn):
            h = count * scale
            gap = 2 if position else 0
            seg_h = max(h - gap, 1)
            y = base - h
            if position == len(drawn) - 1:
                parts.append(f'<path class="fill-{slot_cls}" d="{rounded_top(x, y, bar, seg_h)}"/>')
            else:
                parts.append(f'<rect class="fill-{slot_cls}" x="{x:.1f}" y="{y:.1f}" width="{bar:.1f}" '
                             f'height="{seg_h:.1f}"/>')
            base = y
        lines = [row["day"], f"Total {fmt_int(totals[index])}"]
        lines += [f"{label}: {fmt_int(row['counts'][key])}" for key, label, _ in INGEST_SERIES]
        extra = sorted((c, n) for c, n in row["detail"].items() if c not in ("accepted", "duplicate"))
        lines += [f"  {c}: {fmt_int(n)}" for c, n in extra]
        parts.append(f'<rect class="hit" x="{left + index * slot:.1f}" y="{top}" width="{slot:.1f}" '
                     f'height="{plot_h}" data-tip="{tip_attr(lines)}"/>')
        if index % label_every == 0 or index == len(rows) - 1:
            parts.append(f'<text class="tick" x="{left + index * slot + slot / 2:.1f}" y="{height - 12}" '
                         f'text-anchor="middle">{e(row["day"][5:])}</text>')
    parts.append("</svg>")
    return "".join(parts)


def legend(series):
    items = "".join(f'<span class="key"><i class="sw fill-{cls}"></i>{e(label)}</span>' for _, label, cls in series)
    return f'<div class="legend">{items}</div>'


def hbar_chart(rows, label, unit_fmt, aria):
    """rows: [(label, value, tip_lines, is_combined)] -> horizontal bar chart (single series)."""
    if not rows:
        return '<p class="empty">Nothing to show at this floor.</p>'
    width, label_w, value_w, row_h, bar_h = 560, 190, 70, 26, 14
    plot_w = width - label_w - value_w
    maximum = max(value for _, value, _, _ in rows) or 1
    height = row_h * len(rows) + 4
    parts = [f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="{e(aria, quote=True)}" class="chart hbar">',
             f'<line class="axis" x1="{label_w}" x2="{label_w}" y1="0" y2="{height}"/>']
    for index, (name, value, tip, combined) in enumerate(rows):
        y = index * row_h + (row_h - bar_h) / 2 + 2
        w = max(value / maximum * plot_w, 1.5)
        cls = "fill-other" if combined else "fill-s1"
        short = name if len(name) <= 28 else name[:27] + "\u2026"
        parts.append(f'<text class="rowlabel{" muted" if combined else ""}" x="{label_w - 8}" y="{y + bar_h - 3:.1f}" '
                     f'text-anchor="end">{e(short)}</text>')
        parts.append(f'<path class="{cls}" d="{rounded_right(label_w, y, w, bar_h)}"/>')
        parts.append(f'<text class="value" x="{label_w + w + 6:.1f}" y="{y + bar_h - 3:.1f}">{e(unit_fmt(value))}</text>')
        parts.append(f'<rect class="hit" x="0" y="{index * row_h + 2}" width="{width}" height="{row_h}" '
                     f'data-tip="{tip_attr([name, *tip])}"/>')
    parts.append("</svg>")
    return "".join(parts)


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
            "hitch_per_min": over(ABOVE_100_MS) * 60 / seconds if seconds else 0.0,
            "gaps": metrics["excluded_gap_count"], "windows": metrics["windows"]}


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
    chart = hbar_chart(bars, title, lambda v: f"{v:.1f} fps", f"FPS estimate by {title}")
    table = ""
    if body:
        table = ('<table><thead><tr><th>' + e(title) + '</th><th>Session-days</th><th>Minutes</th><th>FPS</th>'
                 '<th>&gt; 33.3 ms</th><th>&gt; 50 ms</th><th>&gt; 100 ms / min</th></tr></thead><tbody>'
                 + "".join(body) + "</tbody></table>")
    return f'<div class="card"><h4>{e(title)}</h4><p class="sub">FPS estimate (render cadence)</p>{chart}{table}</div>'


def simple_block(title, entry, value_of, value_fmt, sub, extra_cols):
    rows = table_rows(entry)
    bars, body = [], []
    for row in rows:
        name = " / ".join(row["dims"])
        value = value_of(row)
        cols = [(col, fn(row)) for col, fn in extra_cols]
        bars.append((name, value, [f"Session-days {row['sessions']}", *(f"{c} {v}" for c, v in cols)],
                     row.get("_combined", False)))
        body.append("<tr><td>" + e(name) + "</td><td>" + str(row["sessions"]) + "</td>"
                    + "".join(f"<td>{e(str(v))}</td>" for _, v in cols) + "</tr>")
    chart = hbar_chart(bars, title, value_fmt, f"{sub} by {title}")
    table = ""
    if body:
        heads = "".join(f"<th>{e(c)}</th>" for c, _ in extra_cols)
        table = (f'<details><summary>Table</summary><table><thead><tr><th>{e(title)}</th><th>Session-days</th>{heads}'
                 f'</tr></thead><tbody>{"".join(body)}</tbody></table></details>')
    return f'<div class="card"><h4>{e(title)}</h4><p class="sub">{e(sub)}</p>{chart}{table}</div>'


def report_section(index, report, hidden):
    attrs = f' data-report="{index}"' + (" hidden" if hidden else "")
    if "error" in report:
        return f'<section class="report"{attrs}><p class="empty">Refused: {e(report["error"])}</p></section>'
    tables = report["tables"]
    days = "".join(
        f'<span class="day st-{STATUS_GLYPH.get(d["status"], STATUS_GLYPH["missing"])[0]}" '
        f'title="{e(d["day"])}: {e(d["status"])}"><b>{STATUS_GLYPH.get(d["status"], STATUS_GLYPH["missing"])[1]}</b>'
        f'{e(d["day"][5:])}</span>' for d in report["days"])
    ready = sum(1 for d in report["days"] if d["status"] == "ready")
    note = "" if report["week_closed"] else '<span class="pill warn">week still open: figures can change</span>'
    head = (f'<div class="reporthead"><div class="days">{days}</div><p class="sub">{ready} of 7 days rolled up · '
            f'cell floor {report["floor"]} session-days {note}</p></div>')
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


def coverage_grid(snapshot):
    releases = sorted({c["release_id"] for c in snapshot["coverage"]}, reverse=True)
    days = [entry["day"] for entry in snapshot["ingest"]]
    if not releases:
        return '<p class="empty">No day has been rolled up yet.</p>'
    by_key = {}
    for c in snapshot["coverage"]:
        by_key.setdefault((c["release_id"], c["day"]), {})[c["table"]] = c["status"]
    head = "".join(f'<th class="d">{e(d[8:])}</th>' for d in days)
    body = []
    for release in releases:
        cells = []
        for day in days:
            statuses = by_key.get((release, day))
            status = (statuses or {}).get("cells", "missing")
            cls, glyph, label = STATUS_GLYPH.get(status, STATUS_GLYPH["missing"])
            tip = [f"{release} · {day}"] + [f"{t}: {s}" for t, s in sorted((statuses or {"cells": "missing"}).items())]
            cells.append(f'<td class="cov st-{cls}" data-tip="{tip_attr(tip)}" aria-label="{e(label)}">{glyph}</td>')
        body.append(f"<tr><th>{e(release)}</th>{''.join(cells)}</tr>")
    keys = "".join(f'<span class="key"><i class="cov st-{cls}">{glyph}</i>{e(label)}</span>'
                   for cls, glyph, label in STATUS_GLYPH.values())
    return (f'<div class="scroll"><table class="coverage"><thead><tr><th>Release</th>{head}</tr></thead>'
            f'<tbody>{"".join(body)}</tbody></table></div><div class="legend">{keys}</div>')


def tiles(snapshot, rows):
    status = snapshot["status"]
    today = rows[-1]["counts"] if rows else {k: 0 for k, _, _ in INGEST_SERIES}
    if status["suspend_all"]:
        health = ("critical", "\u2716", "All releases suspended")
    elif not status["retention_ok"]:
        health = ("critical", "\u2716", "Raw row past 48 h")
    elif status["last_accepted_age_s"] is None or status["last_accepted_age_s"] > 86400:
        health = ("warning", "!", "No batch in 24 h")
    else:
        health = ("good", "\u2713", "Receiving")
    rejected_today = today["rejected"] + today["other"]
    week_total = sum(r["counts"]["accepted"] for r in rows[-7:])
    items = [
        ("Receiver", f'<span class="badge st-{health[0]}">{health[1]}</span> {e(health[2])}',
         f"retention {'ok' if status['retention_ok'] else 'VIOLATED'} · oldest raw "
         f"{'-' if status['oldest_raw_age_h'] is None else str(status['oldest_raw_age_h']) + ' h'}"),
        ("Last accepted batch", e(fmt_age(status["last_accepted_age_s"])), "since the newest stored batch"),
        ("Accepted today", fmt_int(today["accepted"]), f"{fmt_int(week_total)} in the last 7 days"),
        ("Refused today", fmt_int(rejected_today), f"{fmt_int(today['duplicate'])} duplicate replays"),
        ("Raw batches held", fmt_int(status["raw_batches"]), "48 h retention window"),
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


CSS = """
:root{color-scheme:light;--surface:#fcfcfb;--page:#f9f9f7;--ink:#0b0b0b;--ink2:#52514e;--muted:#898781;
--grid:#e1e0d9;--axis:#c3c2b7;--ring:rgba(11,11,11,.10);--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;
--other:#b5b3ab;--good:#0ca30c;--warning:#fab219;--critical:#d03b3b;--wash:rgba(11,11,11,.04)}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){color-scheme:dark;--surface:#1a1a19;--page:#0d0d0d;
--ink:#f0efec;--ink2:#c3c2b7;--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#3987e5;--s2:#d95926;
--s3:#199e70;--s4:#c98500;--other:#5c5b56;--wash:rgba(255,255,255,.05)}}
:root[data-theme="dark"]{color-scheme:dark;--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;
--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#3987e5;--s2:#d95926;--s3:#199e70;--s4:#c98500;
--other:#5c5b56;--wash:rgba(255,255,255,.05)}
*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);
font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1440px;margin:0 auto;padding:24px 16px 64px}
header{display:flex;flex-wrap:wrap;gap:8px 24px;align-items:baseline;justify-content:space-between}
h1{font-size:22px;margin:0}h2{font-size:17px;margin:32px 0 4px}h3{font-size:15px;margin:24px 0 8px;color:var(--ink2)}
h4{font-size:14px;margin:0}.sub{color:var(--ink2);margin:2px 0 8px;font-size:13px}.muted{fill:var(--muted)}
.warnbox{border:1px solid var(--ring);background:var(--surface);border-left:4px solid var(--warning);
padding:8px 12px;border-radius:6px;margin:12px 0;color:var(--ink2)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;margin-top:16px}
.tile,.card,.panel{background:var(--surface);border:1px solid var(--ring);border-radius:10px;padding:14px 16px}
.tl{color:var(--ink2);font-size:13px}.tv{font-size:22px;font-weight:600;margin:4px 0;overflow-wrap:anywhere}
.ts{color:var(--muted);font-size:12px}
.badge{display:inline-flex;width:22px;height:22px;border-radius:50%;align-items:center;justify-content:center;
font-size:13px;color:#fff;vertical-align:3px}.badge.st-warning{color:#0b0b0b}
.st-good{background:var(--good);color:#fff}.st-warning{background:var(--warning);color:#0b0b0b}
.st-critical{background:var(--critical);color:#fff}.st-muted{background:var(--grid);color:var(--ink2)}
.st-missing{background:transparent;color:var(--muted);box-shadow:inset 0 0 0 1px var(--axis)}
.chart{width:100%;height:auto;display:block}line.grid{stroke:var(--grid);stroke-width:1}
line.axis{stroke:var(--axis);stroke-width:1}.tick{fill:var(--muted);font-size:11px;font-variant-numeric:tabular-nums}
.rowlabel{fill:var(--ink2);font-size:12px}.value{fill:var(--ink);font-size:12px;font-variant-numeric:tabular-nums}
.fill-s1{fill:var(--s1);background:var(--s1)}.fill-s2{fill:var(--s2);background:var(--s2)}
.fill-s3{fill:var(--s3);background:var(--s3)}.fill-s4{fill:var(--s4);background:var(--s4)}
.fill-other{fill:var(--other);background:var(--other)}
.hit{fill:transparent;cursor:default}.hit:hover{fill:var(--wash)}
.legend{display:flex;flex-wrap:wrap;gap:6px 16px;margin:8px 0;color:var(--ink2);font-size:13px}
.key{display:inline-flex;align-items:center;gap:6px}.sw{display:inline-block;width:12px;height:12px;border-radius:3px}
.split{display:grid;grid-template-columns:minmax(0,3fr) minmax(220px,1fr);gap:16px}
@media (max-width:800px){.split{grid-template-columns:1fr}}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,420px),1fr));gap:12px}
table{border-collapse:collapse;width:100%;margin-top:8px;font-size:12.5px;font-variant-numeric:tabular-nums}
th,td{text-align:right;padding:4px 6px;border-bottom:1px solid var(--grid)}th:first-child,td:first-child{text-align:left}
th{color:var(--ink2);font-weight:600}table.narrow{max-width:420px}
.scroll{overflow-x:auto}table.coverage{width:auto}table.coverage td,table.coverage th.d{text-align:center;padding:2px}
td.cov,i.cov{display:inline-flex;width:20px;height:20px;border-radius:4px;align-items:center;justify-content:center;
font-style:normal;font-size:12px;margin:1px}table.coverage td.cov{display:table-cell;width:22px;height:22px}
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

JS = """
const tip=document.getElementById('tip');
document.addEventListener('mousemove',ev=>{const t=ev.target.closest('[data-tip]');
 if(!t){tip.style.display='none';return}tip.textContent=t.dataset.tip;tip.style.display='block';
 const w=tip.offsetWidth,h=tip.offsetHeight;let x=ev.clientX+14,y=ev.clientY+14;
 if(x+w>innerWidth-8)x=ev.clientX-w-14;if(y+h>innerHeight-8)y=ev.clientY-h-14;
 tip.style.left=Math.max(8,x)+'px';tip.style.top=Math.max(8,y)+'px'});
const sel=document.getElementById('report');
if(sel){const show=()=>{document.querySelectorAll('[data-report]').forEach(s=>s.hidden=s.dataset.report!==sel.value);
 try{localStorage.setItem('openrc-telem-report',sel.selectedOptions[0].text)}catch(_){}};
 try{const saved=localStorage.getItem('openrc-telem-report');
  for(const o of sel.options)if(o.text===saved)sel.value=o.value}catch(_){}
 sel.addEventListener('change',show);show()}
const tb=document.getElementById('theme');
tb.addEventListener('click',()=>{const r=document.documentElement;const dark=r.dataset.theme?r.dataset.theme==='dark'
 :matchMedia('(prefers-color-scheme: dark)').matches;r.dataset.theme=dark?'light':'dark';
 try{localStorage.setItem('openrc-telem-theme',r.dataset.theme)}catch(_){}});
try{const t=localStorage.getItem('openrc-telem-theme');if(t)document.documentElement.dataset.theme=t}catch(_){}
"""


def render(snapshot):
    rows = ingest_rows(snapshot)
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
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenRC Telemetry Dashboard</title><style>{CSS}</style></head>
<body><main>
<header><h1>OpenRC telemetry</h1><div class="controls"><span class="sub">Snapshot {e(generated)} ·
last {snapshot['days']} UTC days</span><button id="theme" type="button">Light / dark</button></div></header>
<div class="warnbox"><b>Operator-only.</b> Do not publish or share this page. Counts are session-day observations
from consenting sessions, not players or machines; insight cells below {snapshot['floor']} session-days are combined
or hidden. FPS is an engine render-cadence estimate; VSync or an FPS cap limits it by design.</div>
{tiles(snapshot, rows)}
<h2>Ingest outcomes per day</h2><p class="sub">Every POST /v1/batches, by fixed outcome category (UTC days)</p>
<div class="split"><div class="panel">{legend(INGEST_SERIES)}{ingest_chart(rows)}</div>
<div class="panel"><h4>Refusals in the period</h4>{refusal_table(rows)}</div></div>
<h2>Daily rollup coverage</h2><p class="sub">Insight cells per release and UTC day (hover for every table)</p>
<div class="panel">{coverage_grid(snapshot)}</div>
<h2>Weekly insights</h2><p class="sub">Pooled over the rolled-up days of each ISO week, per-cell disclosure floor</p>
{insight_html}
</main><div id="tip" role="tooltip"></div><script>{JS}</script></body></html>
"""


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
    r = sub.add_parser("render", help="render a saved snapshot")
    r.add_argument("--snapshot", required=True)
    for p in (f, r):
        p.add_argument("--out", default=default_out(), help="HTML output path (local, never in the repository)")
        p.add_argument("--no-open", action="store_true", help="do not open the page in a browser")
    args = parser.parse_args(argv)
    if args.command == "fetch":
        if not args.ssh:
            parser.error("--ssh (or OPENRC_TELEMETRY_SSH) is required")
        snapshot = fetch(args)
    else:
        snapshot = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(snapshot), encoding="utf-8")
    print(out)
    if not args.no_open:
        webbrowser.open(out.resolve().as_uri())
    return 0


if __name__ == "__main__":
    sys.exit(main())
