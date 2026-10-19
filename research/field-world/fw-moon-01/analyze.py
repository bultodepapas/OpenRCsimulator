# FW-MOON-01: summarise run.sh output (frame timing per case, parity, lights) as Markdown tables.
# Usage: python3 -I research/field-world/fw-moon-01/analyze.py OUT_DIR [> summary.md]
# Per run: median and p95 of wall frame time (Time.get_ticks_usec between _process calls) and of the viewport's
# measured render time (CPU and GPU, RenderingServer.viewport_get_measured_render_time_*). Per case: the median of the
# run medians, the median of the run p95s, and the spread (min-max) of the run medians. Delta = case - static.
# Writes OUT_DIR/summary.json (per case) and OUT_DIR/runs.csv (per run) next to the Markdown on stdout.
import glob
import json
import os
import statistics
import sys


def pct(values, q):
    v = sorted(values)
    if not v:
        return float("nan")
    k = (len(v) - 1) * q
    lo = int(k)
    hi = min(lo + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def main(out):
    runs = {}
    for path in sorted(glob.glob(os.path.join(out, "runs", "*.json"))):
        d = json.load(open(path))
        res = "%dx%d" % (d["size"][0], d["size"][1])
        key = (d["case"], res)
        row = {"frames": len(d["wall_ms"]), "draw_calls": statistics.median(d["draw_calls"])}
        for m in ("wall_ms", "cpu_ms", "gpu_ms"):
            row[m + "_p50"] = pct(d[m], 0.5)
            row[m + "_p95"] = pct(d[m], 0.95)
            row[m + "_max"] = max(d[m])
        row["run"] = os.path.basename(path)[:-5]
        runs.setdefault(key, []).append(row)
    summary = {}
    for key, rows in runs.items():
        s = {"runs": len(rows), "frames": rows[0]["frames"], "draw_calls": rows[0]["draw_calls"]}
        for m in ("wall_ms", "cpu_ms", "gpu_ms"):
            p50 = [r[m + "_p50"] for r in rows]
            s[m + "_p50"] = statistics.median(p50)
            s[m + "_p50_min"] = min(p50)
            s[m + "_p50_max"] = max(p50)
            s[m + "_p95"] = statistics.median([r[m + "_p95"] for r in rows])
            s[m + "_max"] = max(r[m + "_max"] for r in rows)
        summary["%s@%s" % key] = s
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=1, sort_keys=True)
    cols = ["frames", "draw_calls"] + ["%s_%s" % (m, q) for m in ("wall_ms", "cpu_ms", "gpu_ms") for q in ("p50", "p95", "max")]
    with open(os.path.join(out, "runs.csv"), "w") as f:
        f.write("run,case,resolution," + ",".join(cols) + "\n")
        for key in sorted(runs):
            for r in sorted(runs[key], key=lambda r: r["run"]):
                f.write("%s,%s,%s," % (r["run"], key[0], key[1]) + ",".join("%.3f" % r[c] for c in cols) + "\n")

    for res in sorted({k[1] for k in runs}):
        base = summary.get("static@" + res)
        print("\n### %s\n" % res)
        print("| Case | Runs × frames | Wall p50 (min–max) | Wall p95 | Δ wall p50 vs static | CPU p50 / p95 | GPU p50 / p95 | Draw calls |")
        print("| --- | --- | --- | --- | --- | --- | --- | --- |")
        order = [k for k in summary if k.endswith("@" + res)]
        order.sort(key=lambda k: summary[k]["wall_ms_p50"])
        for k in order:
            s = summary[k]
            delta = ""
            if base:
                dv = s["wall_ms_p50"] - base["wall_ms_p50"]
                delta = "%+.1f ms (%+.1f %%)" % (dv, 100.0 * dv / base["wall_ms_p50"])
            print("| %s | %d × %d | %.1f (%.1f–%.1f) | %.1f | %s | %.1f / %.1f | %.1f / %.1f | %d |" % (
                k.split("@")[0], s["runs"], s["frames"], s["wall_ms_p50"], s["wall_ms_p50_min"], s["wall_ms_p50_max"],
                s["wall_ms_p95"], delta, s["cpu_ms_p50"], s["cpu_ms_p95"], s["gpu_ms_p50"], s["gpu_ms_p95"],
                s["draw_calls"]))

    parity = os.path.join(out, "parity.json")
    if os.path.exists(parity):
        d = json.load(open(parity))
        print("\n### Parity (2° FOV, disc ≈ 185 px)\n")
        for r in d["parity_look"]:
            print("- look %s: B/A disc signal (8-bit) %.3f; centre A %s, B %s" % (
                r["tag"], r["signal_ratio_b_over_a_8bit"], r["centre_a_8bit"], r["centre_b_8bit"]))
        partial = [r for r in d["parity_mask"] if r["mean_t_a"] < 0.99]
        print("- mask: %d positions, %d partly occluded; |t_A - t_B| over %d pixels: p50 %.4f, p99 %.4f, max %.4f" % (
            len(d["parity_mask"]), len(partial), d["mask_pixels"], d["mask_abs_dt_p50"], d["mask_abs_dt_p99"],
            d["mask_abs_dt_max"]))
        for r in partial:
            print("  - %s: mean t_A %.3f, t_B %.3f, max |Δt| %.3f" % (r["tag"], r["mean_t_a"], r["mean_t_b"], r["max_abs_dt"]))
    paired = os.path.join(out, "paired.json")
    if os.path.exists(paired):
        d = json.load(open(paired))
        print("\n### Paired, one process (%d cycles × blocks of %d frames, %d settle; %s)\n" % (
            d["cycles"], d["block"], d["settle"], "%dx%d" % (d["size"][0], d["size"][1])))
        print("| Config | Samples | Wall p50 / p95 | CPU p50 | GPU p50 | Paired Δ wall vs static: median (IQR) | Δ / static |")
        print("| --- | --- | --- | --- | --- | --- | --- |")
        by_cycle = {}
        for b in d["paired_blocks"]:
            by_cycle.setdefault(b["cycle"], {})[b["config"]] = b
        static_p50 = pct(d["paired_samples"]["static"]["wall"], 0.5)
        for c, smp in d["paired_samples"].items():
            deltas = [cy[c]["wall"] - cy["static"]["wall"] for cy in by_cycle.values() if c in cy and "static" in cy]
            dm = statistics.median(deltas) if deltas else float("nan")
            print("| %s | %d | %.1f / %.1f | %.1f | %.1f | %+.2f ms (%+.2f … %+.2f), %d cycles | %+.2f %% |" % (
                c, len(smp["wall"]), pct(smp["wall"], 0.5), pct(smp["wall"], 0.95), pct(smp["cpu"], 0.5),
                pct(smp["gpu"], 0.5), dm, pct(deltas, 0.25), pct(deltas, 0.75), len(deltas), 100.0 * dm / static_p50))
    profiles = os.path.join(out, "profiles.json")
    if os.path.exists(profiles):
        d = json.load(open(profiles))
        print("\n### Cloud-occlusion parity per weather preset (|t_A - t_B|, %d pixels: p50 %.4f, p99 %.4f, max %.4f)\n" % (
            d["mask_pixels"], d["mask_abs_dt_p50"], d["mask_abs_dt_p99"], d["mask_abs_dt_max"]))
        for r in d["profiles"]:
            if "note" in r:
                print("- %s: %s" % (r["preset"], r["note"]))
            else:
                ts = ", ".join("%.2f" % p["mean_t_a"] for p in r["positions"])
                print("- %s (%d decks): partial positions %d/8, max |Δt| %.3f, max |Δ mean t| %.4f; mean t_A per position: %s" % (
                    r["preset"], r["layers"], r["partial_positions"], r["max_abs_dt"], r["max_abs_mean_dt"], ts))
    lights = os.path.join(out, "lights.json")
    if os.path.exists(lights):
        d = json.load(open(lights))
        print("\n### Lights (captures)\n")
        for r in d["lights"]:
            print("- %s: ground luma %.4f, draw calls %d" % (r["config"], r["ground_luma"], r["draw_calls"]))


if __name__ == "__main__":
    main(sys.argv[1])
