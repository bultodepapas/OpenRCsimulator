"""Runway scenario report (pinned visual venv: numpy, Pillow). Reads <run>/scenario.json and its PNGs and writes:
  <run>/filmstrip-<view>.png   every captured instant of one camera, in time order
  <run>/sync.json              automatic sync checks (pass/fail with numbers)
  <run>/compare.json + diff/   with a previous run: per-frame changed pixels, heatmaps and state differences
  <run>/report.html            all of it on one page (open it in a browser)
    python -I tools/scenery/scenario_report.py <run> [<previous run>]
    python -I tools/scenery/scenario_report.py --history <history dir>   (timeline index.html of past runs)
Exit status 1 only when a sync check fails; differences from the previous run are reported, never fatal (a deliberate
change is expected to show up here).
"""
import html
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

THUMB = (320, 180)
CHANGED_LEVELS = 8          # a pixel "changed" when any channel moves more than this (out of 255)
STATE_TOL = {"north_m": 1e-6, "east_m": 1e-6, "height_m": 1e-6, "speed_ms": 1e-6, "heading_deg": 1e-6,
             "pitch_deg": 1e-6, "roll_deg": 1e-6, "rpm": 1e-6, "prop_angle_deg": 1e-6, "sim_clock": 1e-9}


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.int16)


def filmstrips(run, data):
    out = {}
    for view in data["views"]:
        rows = [r for r in data["frames"] if r["view"] == view]
        if not rows:
            continue
        sheet = Image.new("RGB", (THUMB[0] * len(rows), THUMB[1] + 18), "white")
        d = ImageDraw.Draw(sheet)
        for i, r in enumerate(rows):
            sheet.paste(Image.open(run / r["image"]).convert("RGB").resize(THUMB), (i * THUMB[0], 18))
            d.text((i * THUMB[0] + 4, 3), f"t={r['t_s']:.1f}s {r['phase']} {r['speed_ms']:.1f} m/s h={r['height_m']:.1f} m", fill="black")
        name = f"filmstrip-{view}.png"
        sheet.save(run / name, optimize=True)
        out[view] = name
    return out


def sync_checks(data):
    """What must hold between the physics and the picture, frame by frame."""
    checks = []
    frames = data["frames"]
    dt = data["dt_s"]

    def add(name, ok, detail):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})

    # 1. Scenery animation clock = simulation time (wrapped at 1024 s, L0d).
    worst = max(abs(r["sim_clock"] - math.fmod(r["t_s"], 1024.0)) for r in frames)
    add("sim_clock equals simulation time", worst < 1e-6, f"worst |sim_clock − t| = {worst:.2e} s")
    # 2. Capture instants land on whole ticks of the 240 Hz simulation.
    worst = max(abs(r["tick"] * dt - r["t_s"]) for r in frames)
    add("frames on simulation ticks", worst < 1e-9, f"worst |tick·dt − t| = {worst:.2e} s")
    # 3. Every view of one instant shows the same physical state (cameras never move the airplane).
    by_t = {}
    for r in frames:
        by_t.setdefault(r["t_s"], []).append(r)
    spread = 0.0
    for rs in by_t.values():
        for k in ("north_m", "east_m", "height_m", "heading_deg", "prop_angle_deg"):
            vals = [x[k] for x in rs]
            spread = max(spread, max(vals) - min(vals))
    add("all cameras of an instant share one state", spread == 0.0, f"largest spread {spread:.2e}")
    # 4. The propeller turns by the integral of the rpm (checked between consecutive instants at constant rpm).
    pilot = [r for r in frames if r["view"] == "pilot"]
    worst = 0.0
    for a, b in zip(pilot, pilot[1:]):
        if a["rpm"] == b["rpm"]:
            expected = math.fmod(a["prop_angle_deg"] + a["rpm"] / 60.0 * 360.0 * (b["t_s"] - a["t_s"]), 360.0)
            err = abs((b["prop_angle_deg"] - expected + 180.0) % 360.0 - 180.0)
            worst = max(worst, err)
    add("propeller angle follows the rpm", worst < 1e-3, f"worst error {worst:.2e} deg (constant-rpm intervals)")
    # 5. The pilot camera keeps the airplane centred.
    worst = max(math.hypot(r["airplane_px"][0] - 640.0, r["airplane_px"][1] - 360.0) for r in pilot if r["airplane_px"])
    add("pilot camera centred on the airplane", worst < 1.0, f"worst offset {worst:.2f} px")
    # 6. On the ground the sun shadow touches the airplane (chase view: shadow and airplane within a few px).
    ground = [r for r in frames if r["view"] == "chase" and r["height_m"] < 0.5 and r["shadow_px"] and r["airplane_px"]]
    worst = max((math.hypot(r["shadow_px"][0] - r["airplane_px"][0], r["shadow_px"][1] - r["airplane_px"][1]) for r in ground), default=0.0)
    add("shadow under the airplane while rolling", worst < 40.0, f"worst shadow–CG distance {worst:.1f} px (chase, on the ground)")
    # 7. The scenario itself: rests still at idle, takes off, holds the runway heading.
    idle = [r for r in pilot if r["phase"] == "idle"]
    add("still at the threshold while idling", all(r["speed_ms"] < 0.01 for r in idle), f"max idle speed {max(r['speed_ms'] for r in idle):.2e} m/s")
    last = pilot[-1]
    add("airborne at the end", last["height_m"] > 10.0, f"height {last['height_m']:.1f} m at t = {last['t_s']} s")
    add("runway heading held", all(abs(r["heading_deg"] - data["start"]["heading_deg"]) < 5.0 for r in pilot),
        f"max heading error {max(abs(r['heading_deg'] - data['start']['heading_deg']) for r in pilot):.2f} deg")
    return checks


def compare(run, prev, cur, old):
    old_rows = {(r["view"], r["t_s"]): r for r in old["frames"]}
    (run / "diff").mkdir(exist_ok=True)
    rows = []
    for r in cur["frames"]:
        o = old_rows.get((r["view"], r["t_s"]))
        if o is None:
            rows.append({"image": r["image"], "status": "new frame"})
            continue
        state = {k: r[k] - o[k] for k in STATE_TOL if abs(r[k] - o[k]) > STATE_TOL[k]}
        if r["sha256"] == o["sha256"]:
            rows.append({"image": r["image"], "status": "identical", "changed_pixels": 0, "state_changes": state})
            continue
        a, b = load(run / r["image"]), load(prev / o["image"])
        d = np.abs(a - b).max(axis=2)
        changed = int((d > CHANGED_LEVELS).sum())
        heat = np.zeros((*d.shape, 3), dtype=np.uint8)
        heat[..., 0] = np.clip(d * 4, 0, 255)
        base = (a.mean(axis=2) * 0.35).astype(np.uint8)
        heat[..., 1] = base
        heat[..., 2] = base
        name = "diff/" + r["image"].replace("/", "_")
        Image.fromarray(heat).save(run / name, optimize=True)
        rows.append({"image": r["image"], "status": "changed", "changed_pixels": changed,
                     "changed_share": round(changed / d.size, 5), "max_level": int(d.max()), "diff": name,
                     "state_changes": state, "previous": str(prev / o["image"])})
    physics = any(x.get("state_changes") for x in rows)
    visual = any(x["status"] == "changed" for x in rows)
    verdict = "physics changed" if physics else ("visual-only change" if visual else "identical")
    return {"previous": str(prev), "verdict": verdict, "frames": rows}


def write_html(run, data, strips, checks, comp):
    e = html.escape
    parts = ["<!doctype html><meta charset=utf-8><title>Runway scenario</title>",
             "<style>body{font:14px system-ui;margin:16px;background:#111;color:#ddd}img{max-width:100%}"
             "table{border-collapse:collapse}td,th{border:1px solid #444;padding:3px 6px}.ok{color:#5c5}.bad{color:#f66}"
             "h2{margin-top:28px}</style>",
             f"<h1>Runway scenario</h1><p>{e(data['aircraft'])} · scenery {'on' if data['scenery'] else 'off'} · "
             f"start N {data['start']['north']} E {data['start']['east']} heading {data['start']['heading_deg']}° · {e(data['adapter'])}</p>"]
    if comp:
        parts.append(f"<h2>Against the previous run: {e(comp['verdict'])}</h2><table><tr><th>frame</th><th>status</th><th>changed px</th><th>state changes</th><th>diff</th></tr>")
        for r in comp["frames"]:
            diff = f"<a href='{e(r['diff'])}'>heatmap</a>" if r.get("diff") else ""
            parts.append(f"<tr><td>{e(r['image'])}</td><td>{e(r['status'])}</td><td>{r.get('changed_pixels', '')}</td>"
                         f"<td>{e(json.dumps(r.get('state_changes', {})))}</td><td>{diff}</td></tr>")
        parts.append("</table>")
    parts.append("<h2>Sync checks</h2><table><tr><th>check</th><th>result</th><th>detail</th></tr>")
    for c in checks:
        parts.append(f"<tr><td>{e(c['check'])}</td><td class={'ok' if c['ok'] else 'bad'}>{'pass' if c['ok'] else 'FAIL'}</td><td>{e(c['detail'])}</td></tr>")
    parts.append("</table>")
    for view, name in strips.items():
        parts.append(f"<h2>{e(view)}</h2><img src='{e(name)}'>")
    parts.append("<h2>Frames</h2><table><tr><th>t</th><th>view</th><th>phase</th><th>N/E/h (m)</th><th>speed</th>"
                 "<th>hdg/pitch/roll</th><th>throttle</th><th>rpm</th><th>prop°</th><th>draws</th></tr>")
    for r in data["frames"]:
        parts.append(f"<tr><td>{r['t_s']}</td><td><a href='{e(r['image'])}'>{e(r['view'])}</a></td><td>{e(r['phase'])}</td>"
                     f"<td>{r['north_m']:.2f} / {r['east_m']:.2f} / {r['height_m']:.2f}</td><td>{r['speed_ms']:.2f}</td>"
                     f"<td>{r['heading_deg']:.1f} / {r['pitch_deg']:.1f} / {r['roll_deg']:.1f}</td><td>{r['commands']['throttle']:.2f}</td>"
                     f"<td>{r['rpm']:.0f}</td><td>{r['prop_angle_deg']:.1f}</td><td>{r['draw_calls']:.0f}</td></tr>")
    parts.append("</table>")
    (run / "report.html").write_text("\n".join(parts) + "\n")


def history_index(root):
    runs = sorted((d for d in root.iterdir() if (d / "scenario.json").exists()), reverse=True)
    views = ["pilot", "chase", "side", "wide", "closeup"]
    e = html.escape
    parts = ["<!doctype html><meta charset=utf-8><title>Runway scenario history</title>",
             "<style>body{font:14px system-ui;margin:16px;background:#111;color:#ddd}img{max-width:100%}td{padding:4px;vertical-align:top}"
             ".ok{color:#5c5}.bad{color:#f66}</style><h1>Runway scenario history</h1>",
             "<p>Newest first. Each run: its sync checks, its verdict against the run before it, and one filmstrip per camera.</p>"]
    view = "<select onchange=\"for(const i of document.querySelectorAll('img[data-v]'))i.style.display=(this.value=='all'||i.dataset.v==this.value)?'':'none'\">"
    view += "<option>all</option>" + "".join(f"<option>{v}</option>" for v in views) + "</select>"
    parts.append(f"<p>Camera: {view}</p>")
    for d in runs:
        checks = json.loads((d / "sync.json").read_text()) if (d / "sync.json").exists() else []
        ok = all(c["ok"] for c in checks)
        verdict = json.loads((d / "compare.json").read_text())["verdict"] if (d / "compare.json").exists() else "no previous run"
        parts.append(f"<h2>{e(d.name)} · <span class={'ok' if ok else 'bad'}>sync {'pass' if ok else 'FAIL'}</span> · {e(verdict)}</h2>")
        for v in views:
            if (d / f"filmstrip-{v}.png").exists():
                parts.append(f"<img data-v='{v}' src='{e(d.name)}/filmstrip-{v}.png' title='{v}'>")
    (root / "index.html").write_text("\n".join(parts) + "\n")
    print(f"history: {len(runs)} runs in {root / 'index.html'}")


def main():
    if sys.argv[1] == "--history":
        history_index(Path(sys.argv[2]))
        return
    run = Path(sys.argv[1])
    data = json.loads((run / "scenario.json").read_text())
    strips = filmstrips(run, data)
    checks = sync_checks(data)
    (run / "sync.json").write_text(json.dumps(checks, indent=1) + "\n")
    comp = None
    if len(sys.argv) > 2:
        prev = Path(sys.argv[2])
        comp = compare(run, prev, data, json.loads((prev / "scenario.json").read_text()))
        (run / "compare.json").write_text(json.dumps(comp, indent=1) + "\n")
    write_html(run, data, strips, checks, comp)
    for c in checks:
        print(f"{'ok  ' if c['ok'] else 'FAIL'} {c['check']}: {c['detail']}")
    if comp:
        counts = {}
        for r in comp["frames"]:
            counts[r["status"]] = counts.get(r["status"], 0) + 1
        print(f"against {comp['previous']}: {comp['verdict']} {counts}")
    print(f"report: {run / 'report.html'}")
    sys.exit(0 if all(c["ok"] for c in checks) else 1)


if __name__ == "__main__":
    main()
