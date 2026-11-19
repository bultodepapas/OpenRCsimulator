#!/usr/bin/env python3
"""Aggregate graphics-ladder runs (README.md beside this file) into per-config results.

Usage: analyze.py <runs-dir> <plan.json> <out-prefix>   -> <out-prefix>.json and <out-prefix>.md

Per config: the mean over passes (the ladder's passes alternate direction, so the mean is balanced),
per-pass values, the ascending-minus-descending gap (order/heat effect), step deltas against the previous
ladder step, crash results from impacted runs only, the reference-run drift and effective-setting flags.

An optional <runs-dir>/conditions.json records a mid-campaign change of cooling as
{"external_cooling_from_run": <first run index>, "note": "..."}. The headline metrics then use only the runs
from that index on, and each config also reports its earlier runs as "before cooling".
"""
from __future__ import annotations

import glob
import json
import os
import statistics
import sys

ASCENDING_PASSES = {1, 3, 5}


def mean(values):
    values = [v for v in values if isinstance(v, (int, float))]
    return round(statistics.mean(values), 2) if values else None


def load(runs_dir):
    results = []
    for path in sorted(glob.glob(os.path.join(runs_dir, "*", "result.json"))):
        if ".failed-" not in path:
            with open(path) as handle:
                results.append(json.load(handle))
    return results


def run_index(result):
    try:
        return int(str(result.get("id", ""))[:3])
    except ValueError:
        return None


def load_conditions(runs_dir):
    path = os.path.join(runs_dir, "conditions.json")
    if not os.path.exists(path):
        return {}
    with open(path) as handle:
        return json.load(handle)


def cooled(result, conditions):
    start, index = conditions.get("external_cooling_from_run"), run_index(result)
    return start is not None and index is not None and index >= start


def window_metrics(result):
    window = (result.get("windows") or [{}])[0]
    frames, proc = window.get("frames", {}), window.get("process_gpu", {})
    return {
        "fps": frames.get("fps_mean"), "p50_ms": frames.get("p50_ms"), "p95_ms": frames.get("p95_ms"),
        "p99_ms": frames.get("p99_ms"), "max_ms": frames.get("max_ms"), "low1_fps": frames.get("fps_1pct_low"),
        "over_16_7ms_pct": frames.get("over_16_7ms_pct"), "over_20ms_pct": frames.get("over_20ms_pct"),
        "over_25ms_pct": frames.get("over_25ms_pct"), "over_33_3ms_pct": frames.get("over_33_3ms_pct"),
        "hitches": frames.get("hitches"), "frames": frames.get("frames"), "duration_s": frames.get("duration_s"),
        "gpu_pct": proc.get("gpu_device_pct_mean"), "cpu_pct": proc.get("cpu_pct_mean"), "rss_mib": proc.get("rss_mib_max"),
        "gpu_mem_mib": proc.get("gpu_inuse_mib_max"),
        "video_mem_mib": (result.get("perf") or {}).get("video_memory_mib"),
        "draw_calls": (result.get("render") or {}).get("draw_calls"),
        "shadow_draw_calls": (result.get("render") or {}).get("shadow_draw_calls"),
        "primitives": (result.get("render") or {}).get("primitives"),
        "home_fps": (result.get("home_frames") or {}).get("fps_mean"),
        "fly_load_s": result.get("fly_load_s"), "launch_s": result.get("launch_s"),
        "thermal_start": result.get("thermal_at_start"),
        "thermal_fair_s": (result.get("thermal") or {}).get("fair", 0),
        "thermal_serious_s": (result.get("thermal") or {}).get("serious", 0),
    }


METRICS = ["fps", "p50_ms", "p95_ms", "p99_ms", "max_ms", "low1_fps", "over_16_7ms_pct", "over_20ms_pct",
           "over_25ms_pct", "over_33_3ms_pct", "hitches",
           "gpu_pct", "cpu_pct", "rss_mib", "gpu_mem_mib", "video_mem_mib", "draw_calls", "shadow_draw_calls",
           "primitives", "home_fps", "fly_load_s", "launch_s", "thermal_fair_s"]


def summarize(results, plan, conditions):
    split = conditions.get("external_cooling_from_run") is not None
    by_config = {}
    for result in results:
        by_config.setdefault(result["spec"]["config"], []).append(result)
    summary = {}
    for config, runs in by_config.items():
        good = [r for r in runs if r.get("ok")]
        primary = [r for r in good if cooled(r, conditions)] if split else good
        before = [window_metrics(r) for r in good if not cooled(r, conditions)] if split else []
        rows = [(r["spec"].get("pass"), window_metrics(r)) for r in primary]
        entry = {"label": plan["configs"].get(config, {}).get("label", config), "runs": len(runs), "ok_runs": len(good),
                 "basis": "runs with external cooling" if split else "all runs", "basis_runs": len(primary),
                 "errors": [r.get("error") for r in runs if not r.get("ok")]}
        for metric in METRICS:
            entry[metric] = mean([m[metric] for _p, m in rows])
        if split:
            entry["before_cooling"] = {k: mean([m[k] for m in before]) for k in ("fps", "p95_ms", "gpu_pct", "thermal_fair_s")}
            entry["before_cooling"]["runs"] = len(before)
            entry["cooled_minus_before_fps"] = (round(entry["fps"] - entry["before_cooling"]["fps"], 2)
                                                if entry["fps"] is not None and entry["before_cooling"]["fps"] is not None
                                                else None)
        entry["fps_by_pass_all"] = {str(r["spec"].get("pass")): window_metrics(r)["fps"] for r in good}
        entry["fps_by_pass"] = {str(p): m["fps"] for p, m in rows}
        asc = [m["fps"] for p, m in rows if p in ASCENDING_PASSES]
        desc = [m["fps"] for p, m in rows if p not in ASCENDING_PASSES]
        entry["fps_asc_minus_desc"] = round(mean(asc) - mean(desc), 2) if asc and desc else None
        fps_values = [m["fps"] for _p, m in rows if isinstance(m["fps"], (int, float))]
        entry["fps_range"] = round(max(fps_values) - min(fps_values), 2) if len(fps_values) > 1 else None
        crashes = [r.get("crash") or {} for r in good]
        hit = [c for c in crashes if c.get("impacted")]
        crash_frames = [c.get("frames_dive_impact_plus4s") or {} for c in hit]
        entry["crash"] = {
            "impacted": "%d/%d" % (len(hit), len(crashes)),
            "impact_points": [[round(v, 1) for v in (c.get("impact_state") or {}).get("position_ned_m") or []] for c in hit],
            "fps": mean([f.get("fps_mean") for f in crash_frames]), "p95_ms": mean([f.get("p95_ms") for f in crash_frames]),
            "max_ms": mean([f.get("max_ms") for f in crash_frames]), "hitches": mean([f.get("hitches") for f in crash_frames]),
            "max_ms_pass1": mean([(c.get("frames_dive_impact_plus4s") or {}).get("max_ms") for c, r in zip(crashes, good)
                                  if c.get("impacted") and r["spec"].get("pass") == 1]),
            "causes": sorted({cause for f in crash_frames for h in f.get("bridge_hitches") or [] for cause in h.get("causes") or []}),
            "log_lines": sorted({line.split(" at ")[0] for c in hit for line in c.get("log_lines") or []}),
        }
        entry["restart_after_crash_s"] = mean([r.get("restart_after_crash_s") for r in good])
        entry["effective_mismatch"] = [r.get("effective_mismatch") for r in good if r.get("effective_mismatch")]
        config_seen = (good[0].get("render_config") or {}) if good else {}
        entry["effective"] = {k: config_seen.get(k) for k in ("renderer", "size", "window", "vsync", "msaa_3d",
                                                              "scaling_3d_mode", "scaling_3d_scale", "mesh_lod_threshold")}
        windows = [w for r in good for w in (r.get("windows") or [])]
        if len(windows) > 1 and config.startswith("S-"):
            entry["soak"] = [{"t0": w.get("flight_t0"), "fps": w["frames"].get("fps_mean"), "p95_ms": w["frames"].get("p95_ms"),
                              "gpu_pct": (w.get("process_gpu") or {}).get("gpu_device_pct_mean"),
                              "cpu_pct": (w.get("process_gpu") or {}).get("cpu_pct_mean")} for w in windows]
        summary[config] = entry
    return summary


def ladder_deltas(summary, ladder):
    deltas = []
    for previous, current in zip(ladder, ladder[1:]):
        a, b = summary.get(previous), summary.get(current)
        if not a or not b or not a.get("p50_ms") or not b.get("p50_ms"):
            continue
        noise = max(abs(a.get("fps_asc_minus_desc") or 0), abs(b.get("fps_asc_minus_desc") or 0))
        deltas.append({"step": current, "fps_delta": round(b["fps"] - a["fps"], 1),
                       "p50_ms_delta": round(b["p50_ms"] - a["p50_ms"], 2),
                       "p95_ms_delta": round(b["p95_ms"] - a["p95_ms"], 2),
                       "draw_calls_delta": round((b.get("draw_calls") or 0) - (a.get("draw_calls") or 0)),
                       "order_gap_fps": noise,
                       "resolved": abs(b["fps"] - a["fps"]) > noise})
    return deltas


def reference_drift(results, conditions):
    rows = []
    for r in sorted(results, key=lambda x: x.get("started_unix", 0)):
        if r["spec"]["config"] == "REF" and r.get("ok"):
            m = window_metrics(r)
            rows.append({"run": r["id"], "fps": m["fps"], "p95_ms": m["p95_ms"], "gpu_pct": m["gpu_pct"],
                         "thermal_start": m["thermal_start"], "thermal_fair_s": m["thermal_fair_s"],
                         "cooled": cooled(r, conditions)})
    return rows


def markdown(summary, order, deltas, drift):
    lines = ["| Config | Setting | fps | p50 ms | p95 ms | 1 % low fps | >16.7 ms % | >20 ms % | GPU % | CPU % | "
             "draw calls | primitives | RSS MiB | asc−desc fps | basis runs | fps before cooling | runs ok |",
             "|" + " --- |" * 17]
    for config in order:
        e = summary.get(config)
        if e:
            lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %d | %s | %d/%d |" % (
                config, e["label"], e["fps"], e["p50_ms"], e["p95_ms"], e["low1_fps"], e["over_16_7ms_pct"],
                e["over_20ms_pct"], e["gpu_pct"], e["cpu_pct"], e["draw_calls"], e["primitives"], e["rss_mib"], e["fps_asc_minus_desc"],
                e["basis_runs"], (e.get("before_cooling") or {}).get("fps"), e["ok_runs"], e["runs"]))
    lines += ["", "| Step | Δ fps | Δ p50 ms | Δ p95 ms | Δ draw calls | order gap fps | resolved |", "|" + " --- |" * 7]
    for d in deltas:
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (d["step"], d["fps_delta"], d["p50_ms_delta"],
                                                             d["p95_ms_delta"], d["draw_calls_delta"],
                                                             d["order_gap_fps"], d["resolved"]))
    lines += ["", "| Config | crash impacted | crash fps | crash p95 ms | crash max ms | pass-1 max ms | hitches |",
              "|" + " --- |" * 7]
    for config in order:
        e = summary.get(config)
        if e:
            c = e["crash"]
            lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (config, c["impacted"], c["fps"], c["p95_ms"],
                                                                 c["max_ms"], c["max_ms_pass1"], c["hitches"]))
    lines += ["", "| Reference run | fps | p95 ms | GPU % | thermal at start | fair s | external cooling |",
              "|" + " --- |" * 7]
    for row in drift:
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (row["run"], row["fps"], row["p95_ms"], row["gpu_pct"],
                                                               row["thermal_start"], row["thermal_fair_s"], row["cooled"]))
    return "\n".join(lines) + "\n"


def main():
    runs_dir, plan_path, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    plan = json.load(open(plan_path))
    results = load(runs_dir)
    conditions = load_conditions(runs_dir)
    summary = summarize(results, plan, conditions)
    order = []
    for run in plan["runs"]:
        if run["config"] not in order:
            order.append(run["config"])
    ladder = [c for c in order if c.startswith("L") and c[1:].isdigit()]
    deltas = ladder_deltas(summary, ladder)
    drift = reference_drift(results, conditions)
    json.dump({"conditions": conditions, "configs": summary, "ladder_deltas": deltas, "reference_drift": drift},
              open(prefix + ".json", "w"), indent=1)
    text = markdown(summary, order, deltas, drift)
    open(prefix + ".md", "w").write(text)
    print(text)


if __name__ == "__main__":
    main()
