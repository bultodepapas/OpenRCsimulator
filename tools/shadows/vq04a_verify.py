"""Matched native rendering evidence. Inputs are copied; output must be new.

python tools/shadows/vq04a_verify.py --godot PATH --baseline OLD_APP \
    --candidate app --out NEW_DIRECTORY
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

from PIL import Image, ImageChops


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summary(rows):
    def quantile(values, q):
        values = sorted(values)
        return values[min(len(values) - 1, math.ceil(len(values) * q) - 1)]
    columns = {"wall": [r[0] for r in rows],
               "cpu": [r[1] + r[3] for r in rows],
               "gpu": [r[2] + r[4] for r in rows],
               "mask_gpu": [r[4] for r in rows]}
    return {key: {"p50": statistics.median(v), "p95": quantile(v, .95)}
            for key, v in columns.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("godot", "baseline", "candidate", "out"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--profile-seconds", type=float, default=5.0)
    parser.add_argument("--resume", action="store_true", help="Reuse completed capture stages in this output; re-run profiling and traces")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=args.resume)
    godot = args.godot.resolve()
    here = Path(__file__).resolve().parent
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0

    def other_renderers():
        if os.name != "nt":
            return []
        probe = subprocess.run(["powershell", "-NoProfile", "-Command",
            'Get-CimInstance Win32_Process -Filter "name LIKE \'Godot%\'" | '
            'Select-Object -ExpandProperty CommandLine | ConvertTo-Json -Compress'],
            capture_output=True, text=True, creationflags=flags, check=True)
        processes = json.loads(probe.stdout) if probe.stdout.strip() else []
        if isinstance(processes, str):
            processes = [processes]
        return [p for p in processes if p and "--headless" not in p
                and str(out).lower() not in p.lower()]

    def wait_for_gpu():
        deadline = time.monotonic() + 900
        while other_renderers():
            if time.monotonic() > deadline:
                raise RuntimeError("Other native Godot renderers still active; profiling deferred")
            print("Waiting for other Godot GPU work before profiling", flush=True)
            time.sleep(10)

    def run(label, project, command, timeout=180):
        log = out / (label + ".log")
        with log.open("w", encoding="utf-8") as stream:
            completed = subprocess.run([str(godot), "--path", str(project),
                                        "--audio-driver", "Dummy", *command],
                                       stdout=stream, stderr=subprocess.STDOUT,
                                       timeout=timeout, creationflags=flags)
        text = log.read_text(encoding="utf-8", errors="replace")
        if completed.returncode or re.search(r"^(?:SCRIPT |SHADER )?ERROR:", text, re.M):
            raise RuntimeError(f"{label} failed (exit {completed.returncode}): {log}")
        print(label + " passed", flush=True)

    projects = {}
    hashes = {}
    for name in ("baseline", "candidate"):
        project = out / name / "app"
        if args.resume:
            projects[name] = project
            continue
        shutil.copytree(getattr(args, name).resolve(), project,
                        ignore=shutil.ignore_patterns(".godot", "captures"))
        shutil.copy2(here / "vq04a_capture.gd", project / "vq04a_capture.gd")
        if name == "candidate":
            shutil.copy2(here / "vq04a_gpu_probe.gd", project / "vq04a_gpu_probe.gd")
        projects[name] = project
        hashes[name] = {str(p.relative_to(project)): digest(p) for p in project.rglob("*")
                        if p.is_file() and p.suffix in (".gd", ".gdshader", ".json", ".gdshaderinc", ".godot")}
        run(name + "-import", project, ["--headless", "--import"])
    if args.resume:
        hashes = json.loads((out / "source-hashes.json").read_text())
        for name, files in hashes.items():
            for relative, expected in files.items():
                assert digest(projects[name] / relative) == expected, "Frozen evidence source changed: " + relative
    else:
        (out / "source-hashes.json").write_text(json.dumps(hashes, indent=2))

    if not args.resume:
        run("gpu-probe", projects["candidate"], ["--rendering-method", "gl_compatibility",
            "--script", "res://vq04a_gpu_probe.gd", "--", "--out=" + str(out / "gpu-probe")])
        for name in ("baseline", "candidate", "repeat"):
            project = projects["candidate" if name == "repeat" else name]
            run(name + "-captures", project, ["--rendering-method", "gl_compatibility",
                "--script", "res://vq04a_capture.gd", "--", "--out=" + str(out / (name + "-captures"))])
    pngs = list((out / "candidate-captures").glob("*.png"))
    assert len(pngs) == 40, len(pngs)
    repeat_differences = {}
    def compare_repeat(files, repeat_folder):
        for path in files:
            other = repeat_folder / path.name
            if digest(path) == digest(other):
                continue
            difference = ImageChops.difference(Image.open(path).convert("RGBA"), Image.open(other).convert("RGBA"))
            pixels = list(difference.get_flattened_data())
            changed = sum(any(pixel) for pixel in pixels)
            maximum = max(max(pixel) for pixel in pixels)
            # Native MSAA edge ties can vary by one quantization step. Silhouette
            # targets must remain exact; whole-scene tolerance is <=8 pixels/1 LSB.
            assert "mask" not in path.name and changed <= 8 and maximum <= 1, (path, changed, maximum)
            repeat_differences[path.name] = {"pixels": changed, "max_channel_delta": maximum}
    compare_repeat(pngs, out / "repeat-captures")
    field_pngs = []
    for name in (() if args.resume else ("baseline", "candidate", "repeat")):
        project = projects["candidate" if name == "repeat" else name]
        run(name + "-field", project, ["--rendering-method", "gl_compatibility",
            "--script", "res://vq04a_capture.gd", "--", "--field=on", "--scenery=on",
            "--scenery_audio=off", "--out=" + str(out / (name + "-field"))])
    field_pngs = list((out / "candidate-field").glob("*.png"))
    assert len(field_pngs) == 3
    compare_repeat(field_pngs, out / "repeat-field")

    # Exercise the actual main-scene bind hook, including the shadow-off contract.
    for mode in (() if args.resume else ("sun", "off")):
        for name in ("baseline", "candidate"):
            run(f"route-{name}-{mode}", projects[name], ["--rendering-method", "gl_compatibility", "--",
                "--capture", "--scripted", "--aircraft=p51d-mustang-120", "--visual_pose=level",
                "--visual_distance=20", "--visual_elevation=0", "--autozoom=1", "--t=0",
                "--shadow=" + mode, "--out=" + str(out / f"route-{name}-{mode}.png"),
                *(["--field-shadows=off"] if name == "candidate" and mode == "off" else [])])
    assert digest(out / "route-baseline-off.png") == digest(out / "route-candidate-off.png"), "off route changed"

    campaigns = json.loads((out / "profiles-summary.json").read_text()) if args.resume and (out / "profiles-summary.json").exists() else {}
    for campaign in ("aircraft", "field"):
        if campaign in campaigns:
            delta = campaigns[campaign]["increment_ms"]
            assert delta["gpu"]["p50"] <= .5 and delta["gpu"]["p95"] <= 1.0 and delta["wall"]["p95"] <= 2.0
            continue
        profiles = []
        # Reversed order pairs reduce (but cannot remove) warm-machine/order bias.
        for index, name in enumerate(("baseline", "candidate", "candidate", "baseline", "baseline", "candidate")):
            folder = out / f"profile-{campaign}-{index}-{name}"
            attempt = 0
            while True:
                wait_for_gpu()
                attempt += 1
                run(folder.name + f"-attempt{attempt}", projects[name], ["--rendering-method", "gl_compatibility", "--script",
                    "res://vq04a_capture.gd", "--", "--profile=on", "--warmup=2",
                    f"--seconds={args.profile_seconds}", "--out=" + str(folder),
                    *(["--field=on", "--scenery=on", "--scenery_audio=off"] if campaign == "field" else [])])
                if not other_renderers():
                    break
                shutil.move(str(folder), str(folder) + f"-discarded-contention-{attempt}")
                print("Discarded contended profiling run; retrying after other work", flush=True)
                assert attempt < 12, "Repeated contention: keep artifacts and resume later"
            report = json.loads((folder / "report.json").read_text())
            rows = report["cases"][0]["samples_wall_maincpu_maingpu_maskcpu_maskgpu_ms"]
            assert len(rows) >= 100 and all(r[2] > 0 for r in rows), "missing GPU measurements"
            if name == "candidate" and campaign == "aircraft":
                assert statistics.median(r[4] for r in rows) > 0, "missing offscreen GPU timings"
            profiles.append({"variant": name, "samples": len(rows), "timing_ms": summary(rows)})
        medians = {name: {metric: {q: statistics.median(p["timing_ms"][metric][q]
                            for p in profiles if p["variant"] == name) for q in ("p50", "p95")}
                            for metric in ("wall", "gpu", "cpu", "mask_gpu")}
                   for name in ("baseline", "candidate")}
        delta = {metric: {q: medians["candidate"][metric][q] - medians["baseline"][metric][q]
                         for q in ("p50", "p95")} for metric in medians["baseline"]}
        campaigns[campaign] = {"profiles": profiles, "median_of_runs_ms": medians, "increment_ms": delta}
        (out / "profiles-summary.json").write_text(json.dumps(campaigns, indent=2))
        assert delta["gpu"]["p50"] <= .5 and delta["gpu"]["p95"] <= 1.0, delta
        assert delta["wall"]["p95"] <= 2.0, delta

    ids = ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]
    traces = {}
    for aircraft in ids:
        for name in ("baseline", "candidate"):
            path = out / f"{name}-{aircraft}.csv"
            # Historical snapshots must use the same solver identity for byte-exact CSV comparisons.
            run(f"trace-{name}-{aircraft}", projects[name], ["--headless", "--",
                "--aircraft=" + aircraft, "--physics-backend=gdscript_reference", "--trace=" + str(path), "--t=3"])
        before = out / f"baseline-{aircraft}.csv"
        after = out / f"candidate-{aircraft}.csv"
        # Snapshot preparation normalized CRLF in candidate JSON. Validate that
        # the exact-input-byte hash discrepancy is only that encoding difference;
        # creation time is intentionally volatile. Compare every remaining byte.
        model_line = next(line for line in before.read_text().splitlines() if line.startswith("# aircraft: "))
        model_path = model_line.split("(res://", 1)[1].rstrip(")")
        original_data = (projects["baseline"] / model_path).read_bytes()
        candidate_data = (projects["candidate"] / model_path).read_bytes()
        assert original_data.replace(b"\r\n", b"\n") == candidate_data.replace(b"\r\n", b"\n"), "aircraft input changed"
        excluded = (b"# created_utc:", b"# aircraft_input_sha256:")
        def canonical(path):
            return b"\n".join(line for line in path.read_bytes().splitlines() if not line.startswith(excluded))
        assert canonical(before) == canonical(after), f"trace state/metadata changed: {aircraft}"
        traces[aircraft] = {"baseline_file": digest(before), "candidate_file": digest(after),
                            "matching_state_and_stable_metadata": hashlib.sha256(canonical(after)).hexdigest(),
                            "excluded_metadata": [x.decode() for x in excluded]}
    result = {"compared_pngs": len(pngs) + len(field_pngs), "repeat_differences": repeat_differences,
              "campaigns": campaigns, "trace_sha256": traces, "budget_pass": True}
    (out / "summary.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
