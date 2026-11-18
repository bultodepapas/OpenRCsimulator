"""VQ-07h: GPU cost of each graphics knob on the RTX 3090 at 4K, per renderer, for per-GPU default extrapolation.

Runs Main's direct scripted route (no saved preferences) with frame diagnostics, one knob changed per row.
Raw per-frame reports go to U:/knob-costs; this folder keeps logs, diagnoses and summary.json/csv.
Usage (repository root): python docs/research/visual-quality-implementation/VQ-07/knob-costs-2026-11-18/run_knobs.py
"""
from __future__ import annotations

import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
GODOT = REPO / ".tools" / "Godot_v4.8-beta2_win64_console.exe"
RAW = Path("U:/knob-costs")
WARMUP, SAMPLE = 5, 20
RENDERERS = {"compat": ("gl_compatibility", None, "standard"), "fp-vk": ("forward_plus", "vulkan", "high"),
             "mobile-vk": ("mobile", "vulkan", "standard")}
# The default and "base" are 4x MSAA (msaa_3d=2 is Viewport.MSAA_4X); "msaa4" is therefore a repeat of base.
KNOBS = {"base": ({}, []), "msaa0": ({"OPENRC_MSAA": "0"}, []), "msaa4": ({"OPENRC_MSAA": "4"}, []),
         "msaa2": ({"OPENRC_MSAA": "2"}, []),
         "meadow-off": ({}, ["--runway_meadow=off"]), "birds-off": ({}, ["--scenery_birds=off"]),
         "detail-medium": ({}, ["--scene_detail=medium"]), "detail-low": ({}, ["--scene_detail=low"])}


def pct(values: list[float], p: float) -> float | None:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(p * len(ordered)))] if ordered else None


def run(rid: str, renderer: str, knob: str) -> dict:
    method, driver, profile = RENDERERS[renderer]
    env_extra, args_extra = KNOBS[knob]
    env = dict(os.environ, OPENRC_GRAPHICS_PROFILE=profile, OPENRC_RECONSTRUCTION="native", **env_extra)
    cmd = [str(GODOT)]
    if method != "gl_compatibility":
        cmd += ["--rendering-method", method]
    if driver:
        cmd += ["--rendering-driver", driver]
    out_json = RAW / f"{rid}.json"
    cmd += ["--path", "app", "--audio-driver", "Dummy", "--resolution", "3840x2160", "--fullscreen", "--disable-vsync",
            "--", "--scripted", f"--frametimes={out_json.as_posix()}", f"--warmup={WARMUP}", f"--t={SAMPLE}",
            "--frame-diagnostics", "--frametimes-max-frames=120000", *args_extra]
    started = time.time()
    proc = subprocess.run(cmd, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    text = proc.stdout.decode("utf-8", "replace")
    (HERE / "logs").mkdir(exist_ok=True)
    (HERE / "logs" / f"{rid}.log").write_text("command: " + " ".join(cmd[1:]) + "\nenv: " + json.dumps(env_extra)
                                               + f"\nexit: {proc.returncode}\nwall_s: {time.time() - started:.1f}\n---\n"
                                               + text, encoding="utf-8")
    result = {"id": rid, "renderer": renderer, "knob": knob, "exit": proc.returncode,
              "engine_errors": sum(line.startswith(("ERROR", "SCRIPT ERROR")) for line in text.splitlines())}
    if not out_json.exists():
        result["status"] = "no_report"
        return result
    (HERE / "diagnoses").mkdir(exist_ok=True)
    diag = HERE / "diagnoses" / f"{rid}.json"
    subprocess.run([sys.executable, "research/performance/frame_diagnose.py", "--report", str(out_json), "--log",
                    str(HERE / "logs" / f"{rid}.log"), "--out", str(diag), "--budget-ms", "16.667"], cwd=REPO,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    report = json.loads(out_json.read_text())
    metrics = report["raw_metrics"]
    wall = [v / 1000.0 for v in report["frame_wall_usec"]]
    gpu = [float(v) for v in metrics.get("render_gpu_ms", []) if float(v) > 0]
    fd = report.get("frame_diagnostics", {})
    result.update(frames=len(wall), wall_p50=pct(wall, .5), wall_p95=pct(wall, .95), gpu_p50=pct(gpu, .5),
                  gpu_p95=pct(gpu, .95), rcpu_p50=pct([float(v) for v in metrics.get("render_cpu_ms", [])], .5),
                  draws_p50=pct([float(v) for v in metrics.get("draw_calls", [])], .5),
                  prims_p50=pct([float(v) for v in metrics.get("primitives", [])], .5),
                  viewport=fd.get("viewport_size"), method=fd.get("rendering_method"),
                  valid=json.loads(diag.read_text()).get("valid") if diag.exists() else None)
    return result


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])  # optional knob names to (re)run; existing rows are kept
    order = [(r, k) for r in RENDERERS for k in KNOBS] + [(r, "base") for r in RENDERERS]
    if only:
        order = [(r, k) for r, k in order if k in only][:len(RENDERERS) * len(only)]
    summary = HERE / "summary.json"
    results: dict[str, dict] = json.loads(summary.read_text()) if only and summary.exists() else {}
    seen: dict[str, int] = {}
    for renderer, knob in order:
        seen[f"{renderer}-{knob}"] = seen.get(f"{renderer}-{knob}", 0) + 1
        rid = f"{renderer}-{knob}" + ("" if seen[f"{renderer}-{knob}"] == 1 else f"-r{seen[f'{renderer}-{knob}']}")
        print(rid, flush=True)
        results[rid] = run(rid, renderer, knob)
        print("   ", {k: results[rid].get(k) for k in ("exit", "valid", "gpu_p50", "wall_p50", "viewport")}, flush=True)
        (HERE / "summary.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
    fields = sorted({k for r in results.values() for k in r}, key=lambda k: (k != "id", k))
    with (HERE / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in results.values():
            writer.writerow({k: json.dumps(v) if isinstance(v, (list, dict)) else v for k, v in row.items()})


if __name__ == "__main__":
    main()
