"""RTX 3090 graphics matrix runner (scratch). Runs the official engine through Main's direct
frame-time route, reduces each run with frame_diagnose.py and writes compact evidence."""
from __future__ import annotations

import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(r"C:\DEVELOPMENT\OpenRCsimulator")
GODOT = REPO / ".tools" / "Godot_v4.8-beta2_win64_console.exe"
EVIDENCE = REPO / "docs/research/visual-quality-implementation/VQ-07/rtx3090-matrix-2026-11-17"
RAW = Path("U:/rtx3090-matrix")
WARMUP, SAMPLE = 5, 20


def row(rid, method="gl_compatibility", driver=None, recon="native", res=(1920, 1080), full=False,
        vsync=False, detail="high", workload="scripted", view=None, tod=None, shadow=None, contact=False):
    return dict(id=rid, method=method, driver=driver, recon=recon, res=res, full=full, vsync=vsync,
                detail=detail, workload=workload, view=view, tod=tod, shadow=shadow, contact=contact)


FP, CO, MO = "forward_plus", "gl_compatibility", "mobile"
ROWS = []
# 1. Renderer x driver, Native, 1080p uncapped, two workloads. Core rows repeat (interleaved below).
for wl in ("scripted", "static"):
    ROWS += [row(f"{wl}-compat", CO, workload=wl), row(f"{wl}-fp-vk", FP, "vulkan", workload=wl),
             row(f"{wl}-fp-d3d12", FP, "d3d12", workload=wl), row(f"{wl}-mobile-vk", MO, "vulkan", workload=wl),
             row(f"{wl}-mobile-d3d12", MO, "d3d12", workload=wl)]
# 2. Reconstruction ladder on Forward+.
for drv in ("vulkan", "d3d12"):
    tag = "vk" if drv == "vulkan" else "d3d12"
    for mode in ("fsr2_native", "fsr2_85", "fsr2_quality", "fsr2_balanced", "fsr2_performance"):
        ROWS.append(row(f"recon-{tag}-{mode}", FP, drv, recon=mode))
# 3. Scene detail.
for d in ("low", "medium"):
    ROWS += [row(f"detail-{d}-compat", CO, detail=d), row(f"detail-{d}-fp-vk", FP, "vulkan", detail=d)]
# 4. Resolution: higher first, 720p last.
ROWS += [row("res1440-compat", CO, res=(2560, 1440)), row("res1440-fp-vk", FP, "vulkan", res=(2560, 1440)),
         row("res1440-fp-vk-fsr2_quality", FP, "vulkan", recon="fsr2_quality", res=(2560, 1440))]
for r, m in (("compat", None), ("fp-vk", "native"), ("fp-vk-fsr2_85", "fsr2_85"),
             ("fp-vk-fsr2_quality", "fsr2_quality"), ("fp-vk-fsr2_performance", "fsr2_performance"),
             ("fp-d3d12", "native")):
    method = CO if r == "compat" else FP
    drv = None if r == "compat" else ("d3d12" if "d3d12" in r else "vulkan")
    ROWS.append(row(f"res2160-{r}", method, drv, recon=m or "native", res=(3840, 2160), full=True))
ROWS += [row("static-res2160-compat", CO, res=(3840, 2160), full=True, workload="static"),
         row("static-res2160-fp-vk", FP, "vulkan", res=(3840, 2160), full=True, workload="static")]
# 5. VSync pacing at the display's 120 Hz.
ROWS += [row("vsync-compat", CO, vsync=True), row("vsync-fp-vk", FP, "vulkan", vsync=True),
         row("vsync-res2160-fp-vk", FP, "vulkan", res=(3840, 2160), full=True, vsync=True)]
# 6. Lighting, shadows, camera.
ROWS += [row("tod-sunset-fp-vk", FP, "vulkan", tod="18:45"), row("tod-night-fp-vk", FP, "vulkan", tod="22:30"),
         row("tod-night-compat", CO, tod="22:30"),
         row("contact-shadows-fp-vk", FP, "vulkan", contact=True), row("shadow-off-fp-vk", FP, "vulkan", shadow="off"),
         row("view-chase-fp-vk", FP, "vulkan", view="chase"), row("view-chase-compat", CO, view="chase")]
ROWS += [row("res720-compat", CO, res=(1280, 720)), row("res720-fp-vk", FP, "vulkan", res=(1280, 720))]
# Interleaved repeats of the core comparison (A B C D A B C D).
CORE = [row("scripted-compat", CO), row("scripted-fp-vk", FP, "vulkan"),
        row("recon-vk-fsr2_quality", FP, "vulkan", recon="fsr2_quality"), row("scripted-fp-d3d12", FP, "d3d12")]
for rep in (2, 3):
    for base in CORE:
        ROWS.append(dict(base, id=f"{base['id']}-r{rep}"))


def pct(values, p):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(p * len(ordered)))] if ordered else None


def run(spec):
    rid = spec["id"]
    out_json = RAW / f"{rid}.json"
    log = EVIDENCE / "logs" / f"{rid}.log"
    env = dict(os.environ)
    env["OPENRC_GRAPHICS_PROFILE"] = "high" if spec["method"] == FP else "standard"
    env["OPENRC_RECONSTRUCTION"] = spec["recon"]
    if spec["contact"]:
        env["OPENRC_CONTACT_SHADOWS"] = "on"
    cmd = [str(GODOT)]
    if spec["method"] != CO:
        cmd += ["--rendering-method", spec["method"]]
    if spec["driver"]:
        cmd += ["--rendering-driver", spec["driver"]]
    cmd += ["--path", "app", "--audio-driver", "Dummy", "--resolution", "%dx%d" % spec["res"],
            "--fullscreen" if spec["full"] else "--windowed"]
    if not spec["vsync"]:
        cmd.append("--disable-vsync")
    cmd.append("--")
    if spec["workload"] == "scripted":
        cmd.append("--scripted")
    cmd += [f"--scene_detail={spec['detail']}", f"--frametimes={out_json.as_posix()}", f"--warmup={WARMUP}",
            f"--t={SAMPLE}", "--frame-diagnostics", "--frametimes-max-frames=120000"]
    if spec["view"]:
        cmd.append(f"--view={spec['view']}")
    if spec["tod"]:
        cmd.append(f"--time-of-day={spec['tod']}")
    if spec["shadow"]:
        cmd.append(f"--shadow={spec['shadow']}")
    started = time.time()
    try:
        proc = subprocess.run(cmd, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
        code, text = proc.returncode, proc.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired as exc:
        code, text = "timeout", (exc.stdout or b"").decode("utf-8", "replace")
    header = "command: " + " ".join(cmd[1:]) + "\nenv: " + json.dumps(
        {k: env[k] for k in ("OPENRC_GRAPHICS_PROFILE", "OPENRC_RECONSTRUCTION", "OPENRC_CONTACT_SHADOWS") if k in env}) \
        + f"\nexit: {code}\nwall_s: {time.time() - started:.1f}\n---\n"
    log.write_text(header + text, encoding="utf-8")
    result = dict(id=rid, exit=code, engine_errors=sum(1 for l in text.splitlines()
                                                       if l.startswith(("ERROR", "SCRIPT ERROR", "SHADER ERROR"))))
    result.update({k: spec[k] for k in ("method", "driver", "recon", "full", "vsync", "detail", "workload", "view", "tod", "shadow", "contact")})
    result["requested_res"] = "%dx%d" % spec["res"]
    if not out_json.exists():
        result["status"] = "no_report"
        return result
    diag = EVIDENCE / "diagnoses" / f"{rid}.json"
    if diag.exists():
        diag.unlink()
    subprocess.run([sys.executable, "research/performance/frame_diagnose.py", "--report", str(out_json), "--log", str(log),
                    "--out", str(diag), "--budget-ms", "16.667"], cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    report = json.loads(out_json.read_text())
    fd = report.get("frame_diagnostics", {})
    rec = fd.get("reconstruction_at_report") or fd.get("reconstruction_at_start") or {}
    m = report["raw_metrics"]
    wall = [v / 1000.0 for v in report["frame_wall_usec"]]
    gpu = [float(v) for v in m.get("render_gpu_ms", [])]
    rcpu = [float(v) for v in m.get("render_cpu_ms", [])]
    result.update(
        actual_method=fd.get("rendering_method"), actual_driver=fd.get("rendering_driver"),
        api=fd.get("adapter_api_version"), viewport=fd.get("viewport_size"),
        effective=rec.get("effective"), provider=rec.get("provider"), scale=rec.get("scale"),
        nominal_3d=rec.get("nominal_3d_size"), output=rec.get("output_size"), msaa=rec.get("msaa_3d"),
        progress=report.get("render_progress", {}).get("status"), complete=report.get("complete"), frames=len(wall),
        fps_mean=round(len(wall) / (sum(wall) / 1000.0), 1) if wall else None,
        wall_p50=pct(wall, .5), wall_p95=pct(wall, .95), wall_p99=pct(wall, .99), wall_p999=pct(wall, .999),
        wall_max=max(wall) if wall else None,
        over_8_33=sum(v > 8.333 for v in wall), over_16_67=sum(v > 16.667 for v in wall),
        gpu_p50=pct(gpu, .5), gpu_p95=pct(gpu, .95), rcpu_p50=pct(rcpu, .5), rcpu_p95=pct(rcpu, .95),
        draws_p50=pct([float(v) for v in m.get("draw_calls", [])], .5),
        prims_p50=pct([float(v) for v in m.get("primitives", [])], .5),
        vram_max_mb=round(max(float(v) for v in m["render_video_memory_bytes"]) / 1e6) if m.get("render_video_memory_bytes") else None,
        observer_p95_us=pct([float(v) for v in m.get("observer_poll_usec", [])], .95),
    )
    if diag.exists():
        d = json.loads(diag.read_text())
        result["diagnosis_valid"] = d.get("valid")
        result["diagnosis_issues"] = " | ".join(d.get("measurement_issues", []))[:300]
    return result


def main():
    only = set(sys.argv[1:])
    (EVIDENCE / "logs").mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "diagnoses").mkdir(parents=True, exist_ok=True)
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
        print("   ", {k: result.get(k) for k in ("exit", "engine_errors", "progress", "frames", "wall_p50", "wall_p95", "gpu_p50")}, flush=True)
    fields = sorted({k for r in results.values() for k in r}, key=lambda k: (k != "id", k))
    with (EVIDENCE / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for r in results.values():
            writer.writerow({k: (json.dumps(v) if isinstance(v, (list, dict)) else v) for k, v in r.items()})


if __name__ == "__main__":
    main()
