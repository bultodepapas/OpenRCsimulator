#!/usr/bin/env python3
"""Aggregate graphics-ladder runs (README.md beside this file) into per-config results.

Usage: analyze.py <runs-dir> <plan.json> <out-prefix>   -> <out-prefix>.json and <out-prefix>.md

Per config: headline metrics, per-pass values, the ascending-minus-descending gap (order/heat effect), step
deltas against the previous ladder step, crash results from impacted runs only, the reference-run drift and
effective-setting flags.

Host conditions that change during a campaign (cooling added, a remote-desktop session ending) are recorded in
an optional <runs-dir>/conditions.json:

    {"segments": [{"name": "fanless, remote capture", "from_run": 0, "note": "..."},
                  {"name": "cooled, remote capture", "from_run": 37, "note": "..."},
                  {"name": "cooled, clean", "from_run": 102, "note": "..."}],
     "primary": "cooled, clean",
     "normalize": ["cooled, remote capture", "cooled, clean"]}

Headline metrics use the primary segment's runs. "Normalised" fps scales each run in a `normalize` segment by
the ratio of the primary segment's reference (REF) mean to its own segment's REF mean, so repeated passes taken
under a uniformly slower condition can be pooled; capped runs (VSync or a frame cap) are never scaled. Ladder
step deltas are paired within each pass on normalised fps, with a 95 % t interval across passes. The older
form {"external_cooling_from_run": N} is read as two segments, the later one primary.

`"exclude_passes_from_deltas": [1]` keeps those passes out of every step-delta table (a first pass still paying
first-use pipeline compilation biases the early steps). Besides flight fps, step deltas are also reported for the
Home fps and the crash fps (dive, impact and 4 s after), which can be bound by a different resource than flight.
"""
from __future__ import annotations

import glob
import json
import os
import statistics
import sys

ASCENDING_PASSES = {1, 3, 5}
T95 = {1: 12.71, 2: 4.30, 3: 3.18, 4: 2.78, 5: 2.57, 6: 2.45, 7: 2.36, 8: 2.31, 9: 2.26}


def mean(values, digits=2):
    values = [v for v in values if isinstance(v, (int, float))]
    return round(statistics.mean(values), digits) if values else None


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


def segments_of(conditions):
    if conditions.get("segments"):
        segments = sorted(conditions["segments"], key=lambda s: s["from_run"])
    elif conditions.get("external_cooling_from_run") is not None:
        segments = [{"name": "before cooling", "from_run": 0},
                    {"name": "cooled", "from_run": conditions["external_cooling_from_run"]}]
    else:
        segments = [{"name": "all runs", "from_run": 0}]
    primary = conditions.get("primary") or segments[-1]["name"]
    normalize = conditions.get("normalize") or [primary]
    return segments, primary, normalize


def segment_of(result, segments):
    index, name = run_index(result), segments[0]["name"]
    for segment in segments:
        if index is not None and index >= segment["from_run"]:
            name = segment["name"]
    return name


def capped(result):
    config = result.get("render_config") or {}
    return str(config.get("vsync", "disabled")) != "disabled" or (config.get("max_fps") or 0) > 0


def physics(result):
    """The flight's physics backend ("native", "gdscript_reference") from the engine log line, or None."""
    try:
        return (json.loads(result.get("physics_backend") or "{}").get("identity") or {}).get("backend")
    except ValueError:
        return None


def window_metrics(result):
    window = (result.get("windows") or [{}])[0]
    thermal = result.get("thermal") or {}
    frames, proc = window.get("frames", {}), window.get("process_gpu", {})
    render = result.get("render") or {}
    count, seconds, over25 = frames.get("frames"), frames.get("duration_s"), frames.get("over_25ms_pct")
    return {
        # Long frames per second: a rate equal across configurations points to periodic work, not an option.
        "over_25ms_per_s": (round(over25 * count / 100.0 / seconds, 2)
                            if isinstance(over25, (int, float)) and count and seconds else None),
        "fps": frames.get("fps_mean"), "p50_ms": frames.get("p50_ms"), "p95_ms": frames.get("p95_ms"),
        "p99_ms": frames.get("p99_ms"), "max_ms": frames.get("max_ms"), "low1_fps": frames.get("fps_1pct_low"),
        "over_8_33ms_pct": frames.get("over_8_33ms_pct"), "over_12_5ms_pct": frames.get("over_12_5ms_pct"),
        "over_16_7ms_pct": frames.get("over_16_7ms_pct"), "over_20ms_pct": frames.get("over_20ms_pct"),
        "over_25ms_pct": frames.get("over_25ms_pct"), "over_33_3ms_pct": frames.get("over_33_3ms_pct"),
        "hitches": frames.get("hitches"), "frames": frames.get("frames"), "duration_s": frames.get("duration_s"),
        "gpu_pct": proc.get("gpu_device_pct_mean"), "cpu_pct": proc.get("cpu_pct_mean"), "rss_mib": proc.get("rss_mib_max"),
        "gpu_mem_mib": proc.get("gpu_inuse_mib_max"),
        "video_mem_mib": (result.get("perf") or {}).get("video_memory_mib") or (result.get("render_config") or {}).get("video_mem_mib"),
        "draw_calls": render.get("draw_calls"), "shadow_draw_calls": render.get("shadow_draw_calls"),
        "primitives": render.get("primitives"),
        "home_fps": (result.get("home_frames") or {}).get("fps_mean"),
        "fly_load_s": result.get("fly_load_s"), "launch_s": result.get("launch_s"),
        "thermal_start": result.get("thermal_at_start"),
        # macOS thermalState seconds; Windows records GPU temperatures instead, so these stay empty there.
        "thermal_fair_s": None if "gpu_temp_c_max" in thermal else thermal.get("fair", 0),
        "thermal_serious_s": None if "gpu_temp_c_max" in thermal else thermal.get("serious", 0),
        # Windows/NVIDIA (nvidia-smi): clocks, board power and temperature over the window.
        "gpu_clock_mhz": proc.get("gpu_clock_mhz_mean"), "gpu_power_w": proc.get("gpu_power_w_mean"),
        "gpu_temp_c": proc.get("gpu_temp_c_max"),
        "root_gpu_ms": render.get("root_gpu_ms") or render.get("gpu_ms"), "root_cpu_ms": render.get("root_cpu_ms"),
        "top_thread_pct": (proc.get("thread_cpu_pct_top") or [None])[0],
    }


METRICS = ["fps", "over_25ms_per_s", "p50_ms", "p95_ms", "p99_ms", "max_ms", "low1_fps", "over_8_33ms_pct", "over_12_5ms_pct",
           "over_16_7ms_pct", "over_20ms_pct", "over_25ms_pct", "over_33_3ms_pct", "hitches",
           "gpu_pct", "cpu_pct", "rss_mib", "gpu_mem_mib", "video_mem_mib", "draw_calls", "shadow_draw_calls",
           "primitives", "home_fps", "fly_load_s", "launch_s", "thermal_fair_s", "gpu_clock_mhz", "gpu_power_w",
           "gpu_temp_c", "root_gpu_ms", "root_cpu_ms", "top_thread_pct"]


def reference_scale(results, segments, primary, normalize):
    """fps multiplier per segment: primary REF mean / segment REF mean (1.0 without REF runs)."""
    refs = {}
    for r in results:
        if r["spec"]["config"] == "REF" and r.get("ok"):
            refs.setdefault(segment_of(r, segments), []).append(window_metrics(r)["fps"])
    base = mean(refs.get(primary, []), 4)
    scale = {}
    for segment in segments:
        own = mean(refs.get(segment["name"], []), 4)
        if segment["name"] == primary:
            scale[segment["name"]] = 1.0
        else:
            scale[segment["name"]] = (base / own) if (base and own and segment["name"] in normalize) else None
    return scale, {name: mean(values) for name, values in refs.items()}


def normalised_fps(result, segments, scale):
    fps = window_metrics(result)["fps"]
    factor = scale.get(segment_of(result, segments))
    if fps is None or factor is None:
        return None
    return fps if capped(result) else fps * factor


def summarize(results, plan, conditions):
    segments, primary, normalize = segments_of(conditions)
    scale, _refs = reference_scale(results, segments, primary, normalize)
    by_config = {}
    for result in results:
        by_config.setdefault(result["spec"]["config"], []).append(result)
    summary = {}
    for config, runs in by_config.items():
        good = [r for r in runs if r.get("ok")]
        head = [r for r in good if segment_of(r, segments) == primary]
        rows = [(r["spec"].get("pass"), window_metrics(r)) for r in head]
        entry = {"label": plan["configs"].get(config, {}).get("label", config), "runs": len(runs), "ok_runs": len(good),
                 "basis": primary, "basis_runs": len(head), "errors": [r.get("error") for r in runs if not r.get("ok")]}
        for metric in METRICS:
            entry[metric] = mean([m[metric] for _p, m in rows])
        entry["segments"] = {}
        for segment in segments:
            members = [window_metrics(r) for r in good if segment_of(r, segments) == segment["name"]]
            if members:
                entry["segments"][segment["name"]] = {k: mean([m[k] for m in members])
                                                      for k in ("fps", "p95_ms", "gpu_pct", "cpu_pct", "thermal_fair_s")}
                entry["segments"][segment["name"]]["runs"] = len(members)
        pooled = [(r["spec"].get("pass"), normalised_fps(r, segments, scale)) for r in good]
        pooled = [(p, v) for p, v in pooled if v is not None]
        entry["fps_norm"] = mean([v for _p, v in pooled])
        entry["fps_norm_runs"] = len(pooled)
        entry["fps_norm_by_pass"] = {str(p): round(v, 2) for p, v in pooled}
        values = [v for _p, v in pooled]
        entry["fps_norm_range"] = round(max(values) - min(values), 2) if len(values) > 1 else None
        asc = [v for p, v in pooled if p in ASCENDING_PASSES]
        desc = [v for p, v in pooled if p not in ASCENDING_PASSES]
        entry["fps_asc_minus_desc"] = round(mean(asc) - mean(desc), 2) if asc and desc else None
        entry["fps_by_pass_all"] = {str(r["spec"].get("pass")): window_metrics(r)["fps"] for r in good}
        entry["home_fps_by_pass"] = {str(r["spec"].get("pass")): window_metrics(r)["home_fps"] for r in good
                                     if window_metrics(r)["home_fps"] is not None}
        entry["crash_fps_by_pass"] = {str(r["spec"].get("pass")): ((r.get("crash") or {}).get("frames_dive_impact_plus4s") or {}).get("fps_mean")
                                      for r in good if (r.get("crash") or {}).get("impacted")
                                      and ((r.get("crash") or {}).get("frames_dive_impact_plus4s") or {}).get("fps_mean") is not None}
        crashes = [r.get("crash") or {} for r in good]
        hit = [c for c in crashes if c.get("impacted")]
        crash_frames = [c.get("frames_dive_impact_plus4s") or {} for c in hit]
        entry["crash"] = {
            "impacted": "%d/%d" % (len(hit), len(crashes)),
            "impact_points": [[round(v, 1) for v in (c.get("impact_state") or {}).get("position_ned_m") or []] for c in hit],
            "fps": mean([f.get("fps_mean") for f in crash_frames]), "p95_ms": mean([f.get("p95_ms") for f in crash_frames]),
            "max_ms": mean([f.get("max_ms") for f in crash_frames]), "hitches": mean([f.get("hitches") for f in crash_frames]),
            "max_ms_first": mean([(c.get("frames_dive_impact_plus4s") or {}).get("max_ms")
                                  for c, r in zip(crashes, good) if c.get("impacted") and r is min(good, key=run_index)]),
            "causes": sorted({cause for f in crash_frames for h in f.get("bridge_hitches") or [] for cause in h.get("causes") or []}),
            "log_lines": sorted({line.split(" at ")[0] for c in hit for line in c.get("log_lines") or []}),
        }
        entry["restart_after_crash_s"] = mean([r.get("restart_after_crash_s") for r in good])
        entry["effective_mismatch"] = [r.get("effective_mismatch") for r in good if r.get("effective_mismatch")]
        config_seen = (good[0].get("render_config") or {}) if good else {}
        entry["effective"] = {k: config_seen.get(k) for k in ("renderer", "size", "window", "vsync", "msaa_3d",
                                                              "scaling_3d_mode", "scaling_3d_scale", "mesh_lod_threshold")}
        if good and good[0].get("identity"):
            entry["effective"]["driver"] = good[0]["identity"].get("driver")
        entry["physics"] = sorted({str(physics(r)) for r in good})
        windows = [w for r in good for w in (r.get("windows") or [])]
        if len(windows) > 1 and config.startswith("S-"):
            entry["soak"] = [{"t0": w.get("flight_t0"), "fps": w["frames"].get("fps_mean"), "p95_ms": w["frames"].get("p95_ms"),
                              "gpu_pct": (w.get("process_gpu") or {}).get("gpu_device_pct_mean"),
                              "cpu_pct": (w.get("process_gpu") or {}).get("cpu_pct_mean")} for w in windows]
        summary[config] = entry
    return summary


def ladder_deltas(summary, ladder, by_pass="fps_norm_by_pass", exclude=()):
    """Step deltas paired within each pass (normalised flight fps by default; also Home or crash fps), with a
    95 % t interval across passes. Passes in `exclude` (e.g. a first-use pass) are left out."""
    deltas = []
    excluded = {str(p) for p in exclude}
    for previous, current in zip(ladder, ladder[1:]):
        a, b = summary.get(previous), summary.get(current)
        if not a or not b:
            continue
        passes = sorted((set(a[by_pass]) & set(b[by_pass])) - excluded, key=int)
        paired = [b[by_pass][p] - a[by_pass][p] for p in passes]
        relative = [100.0 * (b[by_pass][p] / a[by_pass][p] - 1.0) for p in passes]
        ci = None
        if len(paired) > 1:
            ci = T95.get(len(paired) - 1, 2.0) * statistics.stdev(paired) / len(paired) ** 0.5
        fps_delta = mean(paired)
        deltas.append({"step": current, "fps_delta": fps_delta, "fps_delta_pct": mean(relative, 1),
                       "ci95_fps": round(ci, 2) if ci is not None else None, "passes": len(paired),
                       "primary_fps_delta": (round(b["fps"] - a["fps"], 2) if a.get("fps") is not None and b.get("fps") is not None
                                             else None),
                       "p95_ms_delta": (round(b["p95_ms"] - a["p95_ms"], 2) if a.get("p95_ms") and b.get("p95_ms") else None),
                       "draw_calls_delta": round((b.get("draw_calls") or 0) - (a.get("draw_calls") or 0)),
                       "resolved": bool(ci is not None and fps_delta is not None and abs(fps_delta) > ci)})
    return deltas


def reference_drift(results, conditions):
    segments, _primary, _normalize = segments_of(conditions)
    rows = []
    for r in sorted(results, key=lambda x: x.get("started_unix", 0)):
        if r["spec"]["config"] == "REF" and r.get("ok"):
            m = window_metrics(r)
            rows.append({"run": r["id"], "fps": m["fps"], "p95_ms": m["p95_ms"], "gpu_pct": m["gpu_pct"],
                         "thermal_start": m["thermal_start"], "thermal_fair_s": m["thermal_fair_s"],
                         "gpu_clock_mhz": m["gpu_clock_mhz"], "gpu_temp_c": m["gpu_temp_c"],
                         "segment": segment_of(r, segments)})
    return rows


def fmt(value):
    return "" if value is None else str(value)


def delta_table(title, deltas):
    lines = ["", "| %s step | Δ | Δ %% | 95 %% CI | passes | resolved |" % title, "|" + " --- |" * 6]
    for d in deltas:
        lines.append("| %s | %s | %s | ±%s | %s | %s |" % (d["step"], fmt(d["fps_delta"]), fmt(d["fps_delta_pct"]),
                                                       fmt(d["ci95_fps"]), d["passes"], d["resolved"]))
    return lines


def markdown(summary, order, deltas, drift, conditions, extra_deltas=()):
    segments, primary, _normalize = segments_of(conditions)
    others = [s["name"] for s in segments if s["name"] != primary]
    nvidia = any(e.get("gpu_clock_mhz") is not None for e in summary.values())
    head = ["Config", "Setting", "fps", "p50 ms", "p95 ms", "1 % low fps"]
    head += [">8.33 ms %", ">12.5 ms %"] if nvidia else []
    head += [">16.7 ms %", ">20 ms %", "GPU %", "CPU %"]
    head += ["GPU MHz", "board W", "top thread %"] if nvidia else []
    head += ["draw calls", "primitives", "RSS MiB", "physics", "normalised fps (runs)", "asc−desc fps"]
    head += ["fps " + name for name in others]
    head += ["runs ok"]
    lines = ["Headline columns use the **%s** runs; normalised fps pools the listed segments (see `conditions.json`)."
             % primary, "", "| " + " | ".join(head) + " |", "|" + " --- |" * len(head)]
    for config in order:
        e = summary.get(config)
        if not e:
            continue
        cells = [config, e["label"], e["fps"], e["p50_ms"], e["p95_ms"], e["low1_fps"]]
        cells += [e["over_8_33ms_pct"], e["over_12_5ms_pct"]] if nvidia else []
        cells += [e["over_16_7ms_pct"], e["over_20ms_pct"], e["gpu_pct"], e["cpu_pct"]]
        cells += [e["gpu_clock_mhz"], e["gpu_power_w"], e["top_thread_pct"]] if nvidia else []
        cells += [e["draw_calls"], e["primitives"], e["rss_mib"], "/".join(e["physics"]),
                  "%s (%d)" % (fmt(e["fps_norm"]), e["fps_norm_runs"]), e["fps_asc_minus_desc"]]
        cells += [(e["segments"].get(name) or {}).get("fps") for name in others]
        cells += ["%d/%d" % (e["ok_runs"], e["runs"])]
        lines.append("| " + " | ".join(fmt(c) for c in cells) + " |")
    lines += ["", "| Step | Δ fps (paired, normalised) | Δ %% | 95 %% CI fps | passes | Δ fps %s | Δ p95 ms | Δ draw calls | resolved |"
              % primary, "|" + " --- |" * 9]
    for d in deltas:
        lines.append("| %s | %s | %s | ±%s | %s | %s | %s | %s | %s |" % (
            d["step"], fmt(d["fps_delta"]), fmt(d["fps_delta_pct"]), fmt(d["ci95_fps"]), d["passes"],
            fmt(d["primary_fps_delta"]), fmt(d["p95_ms_delta"]), d["draw_calls_delta"], d["resolved"]))
    for title, rows in extra_deltas:
        lines += delta_table(title, rows)
    lines += ["", "| Config | crash impacted | crash fps | crash p95 ms | crash max ms | first-crash max ms | hitches |",
              "|" + " --- |" * 7]
    for config in order:
        e = summary.get(config)
        if e:
            c = e["crash"]
            lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (config, c["impacted"], fmt(c["fps"]), fmt(c["p95_ms"]),
                                                                 fmt(c["max_ms"]), fmt(c["max_ms_first"]), fmt(c["hitches"])))
    lines += ["", "| Reference run | segment | fps | p95 ms | GPU % | thermal at start | fair s | GPU MHz | GPU °C |",
              "|" + " --- |" * 9]
    for row in drift:
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            row["run"], row["segment"], fmt(row["fps"]), fmt(row["p95_ms"]), fmt(row["gpu_pct"]), fmt(row["thermal_start"]),
            fmt(row["thermal_fair_s"]), fmt(row["gpu_clock_mhz"]), fmt(row["gpu_temp_c"])))
    return "\n".join(lines) + "\n"


def main():
    runs_dir, plan_path, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(plan_path) as handle:
        plan = json.load(handle)
    results = load(runs_dir)
    conditions = load_conditions(runs_dir)
    summary = summarize(results, plan, conditions)
    order = []
    for run in plan["runs"]:
        if run["config"] not in order:
            order.append(run["config"])
    ladder = [c for c in order if c.startswith("L") and c[1:].isdigit()]
    exclude = conditions.get("exclude_passes_from_deltas") or []
    deltas = ladder_deltas(summary, ladder, exclude=exclude)
    home_deltas = ladder_deltas(summary, ladder, "home_fps_by_pass", exclude)
    crash_deltas = ladder_deltas(summary, ladder, "crash_fps_by_pass", exclude)
    drift = reference_drift(results, conditions)
    segments, primary, normalize = segments_of(conditions)
    scale, ref_means = reference_scale(results, segments, primary, normalize)
    with open(prefix + ".json", "w") as handle:
        json.dump({"conditions": conditions, "reference_means": ref_means, "reference_scale": scale,
                   "configs": summary, "ladder_deltas": deltas, "home_ladder_deltas": home_deltas,
                   "crash_ladder_deltas": crash_deltas, "reference_drift": drift}, handle, indent=1)
    text = markdown(summary, order, deltas, drift, conditions,
                    [("Home fps (raw, %s)" % ("passes without %s" % exclude if exclude else "all passes"), home_deltas),
                     ("Crash fps (raw, %s)" % ("passes without %s" % exclude if exclude else "all passes"), crash_deltas)])
    with open(prefix + ".md", "w", encoding="utf-8") as handle:
        handle.write(text)
    print(text)


if __name__ == "__main__":
    main()
