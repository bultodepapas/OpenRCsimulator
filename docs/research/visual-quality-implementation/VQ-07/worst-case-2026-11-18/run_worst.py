"""VQ-07h-A5 worst-case scene protocol on one machine (scratch runner, same route as ../rtx3090-matrix-2026-11-17).

Worst case = Extreme Scene detail, night (22:30) with airfield lights forced on and the campfire, an electrical
storm sky, Ultra lens rain at 50 mm/h and planar lake reflections (High only), against the default day scene.
Each row runs the official engine through Main's direct frame-time route, then reduces wall, GPU, render CPU,
frame setup and physics step percentiles. Raw reports stay outside the repository (RAW)."""
from __future__ import annotations

import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]
GODOT = REPO / ".tools" / "Godot_v4.8-beta2_win64_console.exe"
EVIDENCE = Path(__file__).resolve().parent
RAW = Path(os.environ.get("OPENRC_WORST_RAW", "U:/worst-case"))
WARMUP, SAMPLE = 5, 20

WORST_ARGS = ["--scene_detail=extreme", "--time-of-day=22:30", "--field-lighting=airfield", "--field-activation=on",
              "--campfire=on", "--sky=electrical_storm", "--lens-effects=ultra", "--lens-rain=on",
              "--lens-rain-mmph=50"]
BASE_ARGS = ["--scene_detail=high"]
FP, CO = "forward_plus", "gl_compatibility"


def row(rid, scene, method=FP, res=(1920, 1080), planar=True, workload="scripted", detail=None):
    args = list(WORST_ARGS if scene == "worst" else BASE_ARGS)
    if detail:
        args = [a for a in args if not a.startswith("--scene_detail=")] + [f"--scene_detail={detail}"]
    return dict(id=rid, scene=scene, method=method, res=res, full=res[1] > 1440, planar=planar and scene == "worst",
                workload=workload, args=args)


ROWS = [
    row("base-1080", "base"), row("worst-1080", "worst"),
    row("worst-1080-noplanar", "worst", planar=False), row("worst-1080-high", "worst", detail="high"),
    row("worst-1080-live", "worst", workload="live"), row("worst-1080-compat", "worst", method=CO),
    row("base-1080-compat", "base", method=CO),
    row("base-1440", "base", res=(2560, 1440)), row("worst-1440", "worst", res=(2560, 1440)),
    row("base-2160", "base", res=(3840, 2160)), row("worst-2160", "worst", res=(3840, 2160)),
    row("worst-2160-noplanar", "worst", res=(3840, 2160), planar=False),
]
for rep in (2, 3):  # interleaved repeats of the core pairs
    for base in ("base-1080", "worst-1080", "base-2160", "worst-2160"):
        ROWS.append(dict(next(r for r in ROWS if r["id"] == base), id=f"{base}-r{rep}"))


def pct(values, p):
    ordered = sorted(values)
    return round(ordered[min(len(ordered) - 1, int(p * len(ordered)))], 3) if ordered else None


def run(spec):
    rid = spec["id"]
    out_json = RAW / f"{rid}.json"
    if out_json.exists():
        out_json.unlink()
    log = EVIDENCE / "logs" / f"{rid}.log"
    env = dict(os.environ)
    env["OPENRC_GRAPHICS_PROFILE"] = "high" if spec["method"] == FP else "standard"
    env["OPENRC_RECONSTRUCTION"] = "native"
    env.pop("OPENRC_LAKE_REFLECTIONS", None)
    if spec["planar"]:
        env["OPENRC_LAKE_REFLECTIONS"] = "planar"
    cmd = [str(GODOT)]
    if spec["method"] == FP:
        cmd += ["--rendering-method", FP, "--rendering-driver", "vulkan"]
    cmd += ["--path", "app", "--audio-driver", "Dummy", "--resolution", "%dx%d" % spec["res"],
            "--fullscreen" if spec["full"] else "--windowed", "--disable-vsync", "--"]
    if spec["workload"] == "scripted":
        cmd.append("--scripted")
    cmd += spec["args"] + [f"--frametimes={out_json.as_posix()}", f"--warmup={WARMUP}", f"--t={SAMPLE}",
                           "--frame-diagnostics", "--frametimes-max-frames=120000"]
    started = time.time()
    try:
        proc = subprocess.run(cmd, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
        code, text = proc.returncode, proc.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired as exc:
        code, text = "timeout", (exc.stdout or b"").decode("utf-8", "replace")
    header = "command: " + " ".join(cmd[1:]) + "\nenv: " + json.dumps(
        {k: env[k] for k in ("OPENRC_GRAPHICS_PROFILE", "OPENRC_RECONSTRUCTION", "OPENRC_LAKE_REFLECTIONS") if k in env}) \
        + f"\nexit: {code}\nwall_s: {time.time() - started:.1f}\n---\n"
    log.write_text(header + text, encoding="utf-8")
    result = dict(id=rid, scene=spec["scene"], method=spec["method"], res="%dx%d" % spec["res"], planar=spec["planar"],
                  workload=spec["workload"], args=" ".join(spec["args"]), exit=code,
                  engine_errors=sum(1 for line in text.splitlines()
                                    if line.startswith(("ERROR", "SCRIPT ERROR", "SHADER ERROR"))))
    if not out_json.exists():
        result["status"] = "no_report"
        return result
    report = json.loads(out_json.read_text())
    fd = report.get("frame_diagnostics", {})
    lake = fd.get("lake_reflections", {}) or {}
    rec = fd.get("reconstruction_at_report") or fd.get("reconstruction_at_start") or {}
    m = report["raw_metrics"]
    wall = [v / 1000.0 for v in report["frame_wall_usec"]]

    def series(key, scale=1.0):
        return [float(v) * scale for v in m.get(key, []) if v is not None]

    gpu, rcpu, setup = series("render_gpu_ms"), series("render_cpu_ms"), series("frame_setup_cpu_ms")
    physics = series("physics_step_usec", 0.001)
    result.update(
        actual_method=fd.get("rendering_method"), actual_driver=fd.get("rendering_driver"),
        viewport=fd.get("viewport_size"), msaa=rec.get("msaa_3d"), lake_mode=lake.get("mode"),
        planar_active=lake.get("planar_active_at_report"), progress=report.get("render_progress", {}).get("status"),
        complete=report.get("complete"), frames=len(wall),
        fps_mean=round(len(wall) / (sum(wall) / 1000.0), 1) if wall else None,
        wall_p50=pct(wall, .5), wall_p95=pct(wall, .95), wall_p99=pct(wall, .99), wall_max=round(max(wall), 3) if wall else None,
        over_16_67=sum(v > 16.667 for v in wall),
        gpu_p50=pct(gpu, .5), gpu_p95=pct(gpu, .95), gpu_p99=pct(gpu, .99),
        rcpu_p50=pct(rcpu, .5), rcpu_p95=pct(rcpu, .95), setup_p95=pct(setup, .95),
        render_cpu_p95=pct([a + b for a, b in zip(rcpu, setup)], .95) if len(rcpu) == len(setup) else None,
        physics_step_p95=pct(physics, .95),
        draws_p50=pct(series("draw_calls"), .5), prims_p50=pct(series("primitives"), .5),
        vram_max_mb=round(max(series("render_video_memory_bytes")) / 1e6) if m.get("render_video_memory_bytes") else None,
    )
    return result


def main():
    only = set(sys.argv[1:])
    (EVIDENCE / "logs").mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)
    summary_path = EVIDENCE / "summary.json"
    results = json.loads(summary_path.read_text()) if summary_path.exists() else {}
    for index, spec in enumerate(ROWS):
        if only and spec["id"] not in only:
            continue
        if not only and results.get(spec["id"], {}).get("frames"):
            continue
        print(f"[{index + 1}/{len(ROWS)}] {spec['id']}", flush=True)
        result = run(spec)
        results[spec["id"]] = result
        summary_path.write_text(json.dumps(results, indent=1), encoding="utf-8")
        print("   ", {k: result.get(k) for k in ("exit", "engine_errors", "frames", "wall_p95", "gpu_p95",
                                                   "render_cpu_p95", "lake_mode", "planar_active")}, flush=True)
    fields = sorted({k for r in results.values() for k in r}, key=lambda k: (k != "id", k))
    with (EVIDENCE / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for r in results.values():
            writer.writerow({k: (json.dumps(v) if isinstance(v, (list, dict)) else v) for k, v in r.items()})


if __name__ == "__main__":
    main()
