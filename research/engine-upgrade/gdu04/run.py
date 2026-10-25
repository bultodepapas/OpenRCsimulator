#!/usr/bin/env python3
"""Compare frozen kernel inputs across two engines without weakening ORFL identity checks."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools/godot"))
from run_checked import run_checked


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(source: Path, output: Path) -> dict[str, str]:
    pending = ["sim/flight_session.gd", "app_state/aircraft_catalog.gd"]
    sources: set[str] = set()
    while pending:
        relative = pending.pop()
        if relative in sources:
            continue
        sources.add(relative)
        path = source / relative
        if path.suffix in {".gd", ".gdshader"}:
            pending += re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', path.read_text(encoding="utf-8"))
    sources.update(path.relative_to(source).as_posix() for path in (source / "data").rglob("*.json"))
    records = {}
    for relative in sorted(sources):
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, target)
        records[relative] = digest(target)
    (output / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="OpenRC GDU04 Research"\n'
        '[physics]\ncommon/physics_ticks_per_second=240\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8"
    )
    shutil.copyfile(HERE / "probe.gd", output / "probe.gd")
    return records


def compare_case(base: Path, candidate: Path, descriptor: dict) -> dict:
    left, right = base.read_bytes(), candidate.read_bytes()
    stride = sum(item["count"] for item in descriptor["layout"]) * 8
    expected = stride * descriptor["rows"]
    if len(left) != expected or len(right) != expected:
        raise RuntimeError(f"incomplete stream {base.name}: {len(left)}, {len(right)}; expected {expected}")
    first = next((index for index, (a, b) in enumerate(zip(left, right)) if a != b), None)
    result = {"identical": first is None, "rows": descriptor["rows"], "bytes": expected,
              "baseline_sha256": hashlib.sha256(left).hexdigest(),
              "candidate_sha256": hashlib.sha256(right).hexdigest()}
    if first is not None:
        row, within = divmod(first, stride)
        component = within // 8
        for field in descriptor["layout"]:
            if component < field["count"]:
                code = "q" if field["kind"] == "int64" else "d"
                offset = row * stride + (within // 8) * 8
                result["first_difference"] = {"tick": row, "field": field["field"], "component": component,
                    "baseline": struct.unpack_from("<" + code, left, offset)[0],
                    "candidate": struct.unpack_from("<" + code, right, offset)[0]}
                break
            component -= field["count"]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-app", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--ticks", type=int, default=960)
    parser.add_argument("--compare-only", action="store_true", help="analyze completed checked outputs without running engines")
    args = parser.parse_args()
    args.out = args.out.resolve()
    if (args.out.exists() and not args.compare_only) or args.ticks < 1:
        parser.error("output must be new unless --compare-only is supplied; ticks must be positive")
    if not args.compare_only:
        args.out.mkdir(parents=True)
    projects = {}
    engines = {}
    records = None
    for label, engine in (("baseline", args.baseline), ("candidate", args.candidate)):
        project = args.out / (label + "-project")
        if args.compare_only:
            manifest = json.loads((args.out / "source-manifest.json").read_text(encoding="utf-8"))
            if any(digest(project / name) != expected for name, expected in manifest.items()):
                raise RuntimeError("completed snapshot source changed: " + label)
            if digest(project / "probe.gd") != digest(HERE / "probe.gd"):
                raise RuntimeError("completed probe differs from current probe")
        else:
            manifest = snapshot(args.source_app.resolve(), project)
        if records is not None and manifest != records:
            raise RuntimeError("frozen source changed while creating snapshots")
        records = manifest
        projects[label] = project
        engine = engine.resolve()
        engines[label] = {"path": str(engine), "sha256": digest(engine),
                          "version": subprocess.check_output([str(engine), "--version"], text=True).strip()}
    if args.compare_only:
        for label in ("baseline", "candidate"):
            checks = list((args.out / "checks").glob(label + "-numerical-*/report.json"))
            if len(checks) != 1:
                raise RuntimeError("require one completed checked invocation: " + label)
            check = json.loads(checks[0].read_text(encoding="utf-8"))
            if check.get("ok") is not True or Path(check["command"][0]).resolve() != Path(engines[label]["path"]):
                raise RuntimeError("completed invocation failed or used another engine: " + label)
    else:
        (args.out / "source-manifest.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
        previous_appdata = os.environ.get("APPDATA")
        try:
            for label in ("baseline", "candidate"):
                os.environ["APPDATA"] = str(args.out / (label + "-profile"))
                result_dir = args.out / label
                result_dir.mkdir()
                engine = engines[label]["path"]
                checked = run_checked([engine, "--headless", "--path", str(projects[label]), "--import"],
                                      args.out / "checks", timeout=300, label=label + "-import")
                if not checked["ok"]:
                    raise RuntimeError(f"{label} import failed: {checked['report']}")
                command = [engine, "--headless", "--path", str(projects[label]), "--script", "res://probe.gd", "--",
                           "--out=" + result_dir.as_posix(), "--ticks=" + str(args.ticks)]
                if label == "candidate":
                    command.append("--baseline=" + (args.out / "baseline").as_posix())
                checked = run_checked(command, args.out / "checks", timeout=900,
                                      required=["GDU04|COMPLETE|"], label=label + "-numerical")
                if not checked["ok"]:
                    raise RuntimeError(f"{label} probe failed: {checked['report']}")
        finally:
            if previous_appdata is None:
                os.environ.pop("APPDATA", None)
            else:
                os.environ["APPDATA"] = previous_appdata
    reports = {label: json.loads((args.out / label / "report.json").read_text(encoding="utf-8"))
               for label in ("baseline", "candidate")}
    if not all(report.get("complete") for report in reports.values()):
        raise RuntimeError("incomplete report")
    comparisons = {}
    if [case["id"] for case in reports["baseline"]["cases"]] != [case["id"] for case in reports["candidate"]["cases"]]:
        raise RuntimeError("engine reports cover different cases")
    for case, candidate_case in zip(reports["baseline"]["cases"], reports["candidate"]["cases"]):
        if any(case[key] != candidate_case[key] for key in ("layout", "rows", "ticks", "input_sha256")):
            raise RuntimeError("case layout/tape mismatch: " + case["id"])
        name = case["id"] + ".bin"
        comparisons[case["id"]] = compare_case(args.out / "baseline" / name, args.out / "candidate" / name, case)
    wind = {}
    for entry in reports["baseline"]["wind"]:
        seed = entry["seed"]
        for kind in ("wind", "ou"):
            name = f"{kind}-{seed}.bin"
            left, right = (args.out / label / name for label in ("baseline", "candidate"))
            wind[name] = {"identical": left.read_bytes() == right.read_bytes(),
                          "baseline_sha256": digest(left), "candidate_sha256": digest(right)}
    # Check raw words against the existing independent Python PCG32 recurrence too.
    sys.path.insert(0, str(ROOT / "app/tests"))
    spec = importlib.util.spec_from_file_location("wind_oracle", ROOT / "app/tests/check_wind_trace.py")
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    for entry in reports["baseline"]["wind"]:
        seed = entry["seed"]
        for label in ("baseline", "candidate"):
            raw = (args.out / label / f"wind-{seed}.bin").read_bytes()
            state = oracle._seeded_pcg_state(seed)
            actual_initial = struct.unpack_from("<Q", raw)[0]
            assert actual_initial == state, (label, seed, "initial state")
            for index in range(entry["words"]):
                word, state = oracle._pcg32(state)
                actual_word, actual_state = struct.unpack_from("<QQ", raw, 8 + index * 16)
                assert (actual_word, actual_state) == (word, state), (label, seed, index)
    identical = all(case["identical"] for case in comparisons.values()) and all(case["identical"] for case in wind.values())
    result = {"format": "openrc-gdu04-comparison v1", "complete": True, "identical": identical,
              "engines": engines, "source_app": str(args.source_app.resolve()), "source_files": len(records),
              "source_manifest_sha256": digest(args.out / "source-manifest.json"),
              "probe_sha256": digest(HERE / "probe.gd"), "runner_sha256": digest(Path(__file__)), "cases": comparisons, "wind": wind,
              "engine_hash_capture": "engine executable hashes measured at analysis time" if args.compare_only else "before execution",
              "pcg32_oracle_sha256": digest(ROOT / "app/tests/check_wind_trace.py"),
              "independent_pcg32_oracle": "all raw words and states match app/tests/check_wind_trace.py",
              "limits": "Frozen-source research comparison only; not ORFL exact replay, physical validation, all-platform equivalence or performance qualification."}
    (args.out / "comparison.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"complete": True, "identical": identical, "cases": len(comparisons), "wind_streams": len(wind)}))
    return 0 if identical else 1


if __name__ == "__main__":
    raise SystemExit(main())
