#!/usr/bin/env python3
"""Serial native static-scene tree comparison; this is not a flight acceptance gate."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CAPTURE = Path(__file__).with_name("quality_capture.gd")
IDENTITY_FILES = (
    "project.godot", "data/fields/default.json", "data/scenery/default.json",
    "scenery/scenery.gd", "scenery/imported_vegetation.gd",
    "scenery/imported_vegetation_wind.gdshader", "assets/landscape/vegetation/catalog.json",
    "assets/landscape/vegetation/models/Bark_NormalTree.png.import",
    "assets/landscape/vegetation/models/Bark_NormalTree_Normal.png.import",
    "assets/landscape/vegetation/models/Leaves_NormalTree_C.png.import",
    "assets/landscape/vegetation/models/Leaf_Pine_C.png.import",
)
OPTIONAL_IDENTITY_FILES = (
    "assets/landscape/vegetation/LICENSE_OAK.txt",
    "assets/landscape/vegetation/models/oak_tree/oak_lod0.gltf.import",
    "assets/landscape/vegetation/models/oak_tree/Quercus_A_1024.png.import",
    # L15b-R2 close-tree wind; absent from earlier baselines.
    "scenery/imported_tree_wind.gdshaderinc", "scenery/imported_tree_wind.gdshader",
    "scenery/imported_tree_wind_cull_back.gdshader", "scenery/imported_tree_wind_clamp.gdshader",
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_identity(project: Path) -> dict[str, str | None]:
    result = {name: digest(project / name) for name in IDENTITY_FILES}
    result.update({name: digest(project / name) if (project / name).is_file() else None
                   for name in OPTIONAL_IDENTITY_FILES})
    return result


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    rank = (len(ordered) - 1) * fraction
    lower = math.floor(rank)
    upper = math.ceil(rank)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (rank - lower)


def reduce_run(report: dict) -> dict:
    if not report.get("complete") or not report.get("samples"):
        raise ValueError("incomplete measurement")
    metrics = {}
    for name in ("wall_ms", "cpu_ms", "gpu_ms"):
        values = [float(row[name]) for row in report["samples"]]
        if not all(math.isfinite(value) and value >= 0 for value in values):
            raise ValueError("invalid timing sample")
        metrics[name] = {
            "available": any(value > 0 for value in values),
            **{f"p{quantile}": percentile(values, quantile / 100) for quantile in (50, 95, 99)},
        }
    return {"sample_count": len(report["samples"]), "duration_s": report["duration_s"],
            "metrics": metrics, "counters": report["counters"]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True, help="already imported frozen app")
    parser.add_argument("--candidate", type=Path, required=True, help="already imported frozen app")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pairs", type=int, default=5)
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--warmup", type=float, default=10)
    parser.add_argument("--view", default="car_park")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--candidate-cell", type=int, choices=(0, 64, 128, 256), default=0)
    parser.add_argument("--candidate-wind", choices=("on", "off"), default="on")
    args = parser.parse_args()
    if (args.pairs < 1 or not math.isfinite(args.seconds) or not math.isfinite(args.warmup)
            or args.seconds <= 0 or args.warmup < 0 or min(args.width, args.height) < 128):
        parser.error("positive pairs/duration/dimensions and nonnegative warmup required")
    output = args.out.resolve()
    if output.exists():
        parser.error("output must not already exist")
    projects = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    for project in projects.values():
        if not (project / ".godot").is_dir():
            parser.error(f"import this frozen project first: {project}")
    output.mkdir(parents=True)
    identities = {label: project_identity(project) for label, project in projects.items()}
    summary = {
        "format": "openrc-tree-static-profile v1", "complete": False,
        "scope": "Uncapped static Compatibility viewport; excludes aircraft simulation, UI, audio, active-flight ratio and owner acceptance.",
        "godot_sha256": digest(args.godot.resolve()), "fixture_sha256": digest(CAPTURE),
        "identities": identities, "arguments": {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        "runs": [], "pairs": [],
    }
    expected_backend = None
    for pair_index in range(args.pairs):
        pair = {}
        order = ("baseline", "candidate") if pair_index % 2 == 0 else ("candidate", "baseline")
        for label in order:
            run_id = f"{pair_index + 1:02d}-{label}"
            run_dir = output / run_id
            command = [str(args.godot.resolve()), "--path", str(projects[label]), "--audio-driver", "Dummy",
                       "--script", str(CAPTURE), "--", f"--out={run_dir}", "--mode=field",
                       f"--view={args.view}", f"--profile={args.seconds}", f"--warmup={args.warmup}",
                       f"--width={args.width}", f"--height={args.height}"]
            if label == "candidate":
                command += [f"--wind={args.candidate_wind}", f"--cell={args.candidate_cell}"]
            print(f"START {run_id}", flush=True)
            with (output / f"{run_id}.log").open("w", encoding="utf-8") as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                        timeout=args.seconds + args.warmup + 180)
            text = (output / f"{run_id}.log").read_text(encoding="utf-8", errors="replace")
            if result.returncode or "ERROR:" in text or "Parse Error" in text:
                raise RuntimeError(f"engine failed: {run_id}; see log")
            report = json.loads((run_dir / "report.json").read_text(encoding="utf-8"))
            backend = {key: report[key] for key in ("godot", "renderer", "adapter", "api", "viewport", "msaa")}
            if expected_backend is not None and backend != expected_backend:
                raise RuntimeError("backend changed between paired runs")
            expected_backend = backend
            reduced = reduce_run(report)
            if reduced["duration_s"] < args.seconds:
                raise RuntimeError("short measurement")
            pair[label] = reduced
            summary["runs"].append({"id": run_id, "label": label, "report_sha256": digest(run_dir / "report.json"), **reduced})
            print(f"DONE {run_id}: wall p95={reduced['metrics']['wall_ms']['p95']:.3f} ms; GPU p95={reduced['metrics']['gpu_ms']['p95']:.3f} ms", flush=True)
        summary["pairs"].append({"index": pair_index + 1, "order": order,
            "wall_p95_delta_ms": pair["candidate"]["metrics"]["wall_ms"]["p95"] - pair["baseline"]["metrics"]["wall_ms"]["p95"],
            "gpu_p95_delta_ms": pair["candidate"]["metrics"]["gpu_ms"]["p95"] - pair["baseline"]["metrics"]["gpu_ms"]["p95"]})
    for label, project in projects.items():
        if identities[label] != project_identity(project):
            raise RuntimeError(f"{label} changed during measurements")
    summary["backend"] = expected_backend
    summary["median_paired_wall_p95_delta_ms"] = statistics.median(p["wall_p95_delta_ms"] for p in summary["pairs"])
    summary["median_paired_gpu_p95_delta_ms"] = statistics.median(p["gpu_p95_delta_ms"] for p in summary["pairs"])
    summary["complete"] = True
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in summary.items() if key.startswith("median_")}), flush=True)


if __name__ == "__main__":
    main()
