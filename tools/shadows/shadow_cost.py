"""Shadow cost matrix (VQ-04b SA-25): GPU time per shadow technique, renderer and view, with offscreen attribution.

python tools/shadows/shadow_cost.py --godot .tools/Godot_v4.8-beta2_win64_console.exe --out NEW_DIRECTORY \
    [--profiles high standard] [--techniques off native projected auto] [--views aircraftground pavilion] \
    [--widths 1920] [--repeats 3] [--seconds 8]

Each run is the production graphics producer (tools/graphics/capture.gd) profiling one view after its warm-up. The
aircraft view draws the production planar cue and spins the aircraft a little every frame, so its mask and the
native maps do a flight's work; scenery views are static. Runs alternate technique order in every repeat, so drift
spreads over all techniques. The summary reports the root viewport's GPU median and p95, the median delta against
Off in the same profile/view/width, and each offscreen SubViewport's median GPU time with its update mode.

Limits (printed in the report): the root delta is the native shadow passes plus everything a technique switches;
masks that did not redraw report zero; cold bakes before the warm-up are excluded; timings belong to this machine,
renderer, resolution and scene only. Never run concurrently with other GPU work.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LAUNCH = ROOT / "tools" / "graphics" / "launch.py"


def quantile(values: list[float], q: float) -> float:
    values = sorted(values)
    return values[min(len(values) - 1, max(0, math.ceil(len(values) * q) - 1))]


def run_one(args: argparse.Namespace, out: Path, profile: str, technique: str, view: str, width: int,
            repeat: int) -> dict:
    label = f"{profile}-{view}-{width}-{technique}-r{repeat}"
    target = out / "runs" / label
    command = [sys.executable, str(LAUNCH), "--godot", args.godot, "--profile", profile,
               "--script", "../tools/graphics/capture.gd", "--",
               f"--out={target.as_posix()}", f"--width={width}", f"--view={view}",
               f"--shadow-technique={technique}", f"--seconds={args.seconds}"]
    if view == "aircraftground":
        command += ["--aircraft-cue=on", "--aircraft-motion=spin"]
    log = out / "logs" / f"{label}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as handle:
        status = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT,
                                timeout=args.timeout).returncode
    report_path = target / "report.json"
    if status != 0 or not report_path.exists():
        return {"label": label, "ok": False, "status": status, "log": str(log)}
    report = json.loads(report_path.read_text(encoding="utf-8"))
    case = report["cases"][0]
    profile_data = case["profile"]
    gpu = [float(s["gpu_ms"]) for s in profile_data["samples_wall_cpu_gpu_ms"]]
    cpu = [float(s["cpu_ms"]) for s in profile_data["samples_wall_cpu_gpu_ms"]]
    return {"label": label, "ok": True, "profile": profile, "renderer": report.get("renderer"),
            "gpu_name": report.get("gpu", {}).get("name"), "technique": technique, "view": view, "width": width,
            "repeat": repeat, "samples": len(gpu), "gpu_median_ms": statistics.median(gpu),
            "gpu_p95_ms": quantile(gpu, 0.95), "cpu_median_ms": statistics.median(cpu),
            "counters": case.get("counters", {}), "shadows": report.get("shadows", {}).get("effective", {}),
            "native_field_casters": report.get("native_field_casters", {}),
            "subviewports": {key: {"size": value["size"], "gpu_ms_median": value["gpu_ms_median"],
                                   "gpu_ms_max": value["gpu_ms_max"], "update_modes": value["update_modes"]}
                             for key, value in profile_data.get("subviewports", {}).items()}}


def summarize(runs: list[dict]) -> list[dict]:
    groups: dict[tuple, list[dict]] = {}
    for run in runs:
        if run.get("ok"):
            groups.setdefault((run["profile"], run["view"], run["width"], run["technique"]), []).append(run)
    rows = []
    for (profile, view, width, technique), items in sorted(groups.items()):
        medians = [item["gpu_median_ms"] for item in items]
        offscreen: dict[str, list[float]] = {}
        for item in items:
            for key, value in item["subviewports"].items():
                offscreen.setdefault(key, []).append(value["gpu_ms_median"])
        rows.append({"profile": profile, "renderer": items[0]["renderer"], "view": view, "width": width,
                     "technique": technique, "runs": len(items),
                     "gpu_median_ms": statistics.median(medians),
                     "gpu_median_spread_ms": max(medians) - min(medians),
                     "gpu_p95_ms": statistics.median(item["gpu_p95_ms"] for item in items),
                     "draw_calls": items[0]["counters"].get("draw_calls"),
                     "offscreen_gpu_ms": {key: statistics.median(values) for key, values in offscreen.items()
                                          if statistics.median(values) > 0.0}})
    baseline = {(r["profile"], r["view"], r["width"]): r["gpu_median_ms"] for r in rows if r["technique"] == "off"}
    for row in rows:
        reference = baseline.get((row["profile"], row["view"], row["width"]))
        row["delta_vs_off_ms"] = None if reference is None else row["gpu_median_ms"] - reference
    return rows


def markdown(rows: list[dict], meta: dict) -> str:
    lines = [f"# Shadow cost matrix", "", f"GPU: {meta.get('gpu')} · engine runs: {meta.get('runs')} · "
             f"repeats: {meta.get('repeats')} · {meta.get('seconds')} s per run after the producer's warm-up.", "",
             "| Profile | View | Width | Technique | GPU median ms | Δ vs Off | p95 ms | Spread | Draws | Offscreen (median ms) |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        delta = "—" if r["delta_vs_off_ms"] is None else f"{r['delta_vs_off_ms']:+.3f}"
        offscreen = ", ".join(f"{k.split('/')[-2]} {v:.3f}" for k, v in r["offscreen_gpu_ms"].items()) or "none redrawn"
        lines.append(f"| {r['profile']} ({r['renderer']}) | {r['view']} | {r['width']} | {r['technique']} | "
                     f"{r['gpu_median_ms']:.3f} | {delta} | {r['gpu_p95_ms']:.3f} | {r['gpu_median_spread_ms']:.3f} | "
                     f"{r['draw_calls']} | {offscreen} |")
    lines += ["", "Spread is max − min of the per-run medians: deltas smaller than it are not resolved."]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--profiles", nargs="+", default=["high", "standard"], choices=["high", "standard"])
    parser.add_argument("--techniques", nargs="+", default=["off", "native", "projected", "auto"],
                        choices=["off", "native", "projected", "auto"])
    parser.add_argument("--views", nargs="+", default=["aircraftground", "pavilion"],
                        choices=["aircraftground", "pilot", "pavilion", "lake", "flightline", "windsock"])
    parser.add_argument("--widths", nargs="+", type=int, default=[1920], choices=[1280, 1920, 2560, 3840])
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--seconds", type=float, default=8.0)
    parser.add_argument("--timeout", type=float, default=900.0)
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace") # Windows consoles default to cp1252
    if args.out.exists():
        parser.error("--out must be a new directory")
    args.out.mkdir(parents=True)
    runs: list[dict] = []
    for repeat in range(args.repeats):
        techniques = args.techniques if repeat % 2 == 0 else list(reversed(args.techniques))
        for profile in args.profiles:
            for width in args.widths:
                for view in args.views:
                    for technique in techniques:
                        result = run_one(args, args.out, profile, technique, view, width, repeat)
                        runs.append(result)
                        state = f"{result['gpu_median_ms']:.3f} ms" if result.get("ok") else f"FAILED ({result['log']})"
                        print(f"{result['label']}: {state}", flush=True)
    rows = summarize(runs)
    meta = {"gpu": next((r["gpu_name"] for r in runs if r.get("ok")), None), "runs": len(runs),
            "repeats": args.repeats, "seconds": args.seconds, "failed": [r["label"] for r in runs if not r.get("ok")]}
    (args.out / "summary.json").write_text(json.dumps({"meta": meta, "rows": rows, "runs": runs}, indent=1),
                                           encoding="utf-8")
    (args.out / "summary.md").write_text(markdown(rows, meta), encoding="utf-8")
    print(markdown(rows, meta))
    return 1 if meta["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
