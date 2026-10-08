#!/usr/bin/env python3
"""Compare stage-local propulsion sharing in disposable copies; never patch the app."""
from __future__ import annotations

import argparse
import copy
import difflib
import importlib.util
import json
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SPEC = importlib.util.spec_from_file_location("native_runner", HERE.parent / "native/run.py")
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)


def replace(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"Expected exactly one patch anchor: {old!r}")
    return source.replace(old, new, 1)


def candidate_sources(app: Path) -> dict[str, str]:
    """The complete experiment, also saved as a reviewable patch with every run."""
    prop = (app / "physics/propulsion.gd").read_text()
    prop = replace(prop,
        "static func loads(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:",
        "static func loads(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float,\n"
        "\t\tstage_tq: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:")
    prop = replace(prop, "\tvar tq := thrust_torque(v_air, rpm, prop, rho)",
        "\tvar tq: PackedFloat64Array = thrust_torque(v_air, rpm, prop, rho) if stage_tq.is_empty() else stage_tq")
    wake = (app / "physics/slipstream.gd").read_text()
    wake = replace(wake,
        "transported_dv: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:",
        "transported_dv: PackedFloat64Array = PackedFloat64Array(),\n"
        "\t\tstage_tq: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:")
    wake = replace(wake, "\tvar tq := Propulsion.thrust_torque(v, rpm, prop, rho)",
        "\tvar tq: PackedFloat64Array = Propulsion.thrust_torque(v, rpm, prop, rho) if stage_tq.is_empty() else stage_tq")
    dynamics = (app / "physics/dynamics.gd").read_text()
    dynamics = replace(dynamics,
        "\tvar propulsion_loads := Propulsion.loads(air.v_air, rpm, model.propulsion, rho)",
        "\tvar has_wash: bool = not model.propulsion.get(\"slipstream\", {}).is_empty()\n"
        "\t# Local to this evaluation: never retain across RK stages, calls or ticks.\n"
        "\tvar stage_tq: PackedFloat64Array = PackedFloat64Array()\n"
        "\tif has_wash and not Turbine.is_turbine(model.propulsion) and rpm >= Propulsion.STOPPED_RPM:\n"
        "\t\tstage_tq = Propulsion.thrust_torque(air.v_air, rpm, model.propulsion, rho)\n"
        "\tvar propulsion_loads := Propulsion.loads(air.v_air, rpm, model.propulsion, rho, stage_tq)")
    dynamics = replace(dynamics,
        'if not model.propulsion.get("slipstream", {}).is_empty():', 'if has_wash:')
    dynamics = replace(dynamics,
        "Slipstream.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv)",
        "Slipstream.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv, stage_tq)")
    return {"physics/propulsion.gd": prop, "physics/slipstream.gd": wake,
            "physics/dynamics.gd": dynamics}


def stage(app: Path, output: Path, library: Path | None) -> None:
    changed = candidate_sources(app)
    patch = []
    for name, content in changed.items():
        patch.extend(difflib.unified_diff((app / name).read_text().splitlines(True),
                     content.splitlines(True), fromfile="a/app/" + name, tofile="b/app/" + name))
    (output / "candidate.patch").write_text("".join(patch))
    probe = app / "tests/stage_sharing"
    probe.mkdir(parents=True)
    for name, content in changed.items():
        # Independent script resources keep baseline and candidate loaded in the same process.
        for dependency in ("propulsion", "slipstream"):
            content = content.replace(f'res://physics/{dependency}.gd',
                                      f'res://tests/stage_sharing/{dependency}.gd')
        (probe / Path(name).name).write_text(content)
    flight = (app / "sim/flight_session.gd").read_text()
    flight = replace(flight, 'preload("res://physics/dynamics.gd")',
                     'preload("res://tests/stage_sharing/dynamics.gd")')
    (probe / "flight_session.gd").write_text(flight)
    shutil.copy2(HERE / "probe.gd", probe / "probe.gd")
    if library is not None:
        native_probe = native._install_probe(app, library)
        native._replace_dynamics_slipstream(app, True)
        adapter = (native_probe / "adapter.gd").read_text()
        adapter = replace(adapter,
            "transported_dv: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:",
            "transported_dv: PackedFloat64Array = PackedFloat64Array(),\n"
            "\t\tstage_tq: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:")
        adapter = replace(adapter,
            "Oracle.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv)",
            "Oracle.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv, stage_tq)")
        adapter = replace(adapter,
            "var tq_full: PackedFloat64Array = Propulsion.thrust_torque(velocity, rpm, prop, rho)",
            "var tq_full: PackedFloat64Array = Propulsion.thrust_torque(velocity, rpm, prop, rho) if stage_tq.is_empty() else stage_tq")
        for dependency in ("propulsion", "slipstream"):
            adapter = adapter.replace(f'res://physics/{dependency}.gd',
                                      f'res://tests/stage_sharing/{dependency}.gd')
        (probe / "adapter.gd").write_text(adapter)
        path = probe / "dynamics.gd"
        path.write_text(replace(path.read_text(),
            'preload("res://tests/stage_sharing/slipstream.gd")',
            'preload("res://tests/stage_sharing/adapter.gd")'))


def execute(godot: str, app: Path, script: Path, output: Path) -> None:
    command = [godot, "--headless", "--path", str(app), "--script", str(script)]
    for suffix, args in (("parse", ["--check-only"]), ("run", ["--", str(output)])):
        result = subprocess.run(command + args, capture_output=True, text=True, timeout=1200)
        log = result.stdout + result.stderr
        output.with_suffix(f".{suffix}.log").write_text(log)
        if result.returncode or native.ERROR_RE.search(log):
            match = native.ERROR_RE.search(log)
            excerpt = log[match.start():match.start() + 2000] if match else log[-2000:]
            raise RuntimeError(f"{suffix} failed: {script}; see {output.with_suffix(f'.{suffix}.log')}\n{excerpt}")


def summarize(report: dict) -> dict:
    if (report.get("format") != "openrc-e0b6p-stage-sharing v1"
            or report.get("status") != "pass" or report.get("failures") != 0):
        raise RuntimeError("Stage-sharing probe failed")
    fleet = ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120",
             "sebart-avanti-s-a200-p100rx"]
    smooth = [f"smooth:{r}:swirl={s:.1f}" for r in native.REGIMES for s in (0.0, 0.4)]
    expected = {
        "direct_rows": [f"fleet:{f}" for f in fleet] + smooth +
                       ["smooth:transport_on", "smooth:stopped", "smooth:stopped_residual"],
        "flight_rows": [f"fleet:{f}:{r}" for f in fleet for r in ("trim", "stall", "spin", "ground")] +
                       smooth + ["smooth:transport_on", "smooth:stopped_residual"],
    }
    counts = report.get("counts", {})
    if counts.get("direct_calls_compared") != 1216 or counts.get("flight_boundaries_compared") != 7230:
        raise RuntimeError("Incomplete load/trajectory coverage")
    result = {}
    for key in ("direct_rows", "flight_rows"):
        rows = report.get(key, [])
        if [row.get("case") for row in rows] != expected[key]:
            raise RuntimeError(f"Unexpected {key} roster")
        summaries = []
        for row in rows:
            old, new = row["baseline_samples_us"], row["candidate_samples_us"]
            pairs = 15 if key == "direct_rows" else 9
            if len(old) != pairs or len(new) != pairs:
                raise RuntimeError("Missing timing pairs")
            if key == "direct_rows":
                if row.get("exact") is not True or row.get("exact_calls") != 64:
                    raise RuntimeError("Direct load comparison failed")
            elif (row.get("trajectory_exact") is not True or row.get("boundaries_compared") != 241
                  or row.get("baseline_trajectory_sha256") != row.get("candidate_trajectory_sha256")
                  or not re.fullmatch(r"[0-9a-f]{64}", row.get("baseline_trajectory_sha256", ""))):
                raise RuntimeError("Flight trajectory comparison failed")
            for value in old + new:
                if native._assert_finite_number(value, key) <= 0:
                    raise RuntimeError("Nonpositive timing")
            deltas = [a - b for a, b in zip(old, new, strict=True)]
            summaries.append({"case": row["case"], "baseline_median_us": statistics.median(old),
                "candidate_median_us": statistics.median(new),
                "paired_saving_median_us": statistics.median(deltas),
                "candidate_faster_pairs": sum(x > 0 for x in deltas), "pairs": len(deltas)})
        result[key] = summaries
    return result


def mechanism(godot: str, app: Path, output: Path) -> None:
    # Counters are installed only after uninstrumented timings, in the disposable copy.
    for relative in ("physics/propulsion.gd", "tests/stage_sharing/propulsion.gd"):
        path = app / relative
        if "static var stage_probe_calls: int = 0" in path.read_text():
            continue
        source = replace(path.read_text(), "extends RefCounted",
                         "extends RefCounted\n\nstatic var stage_probe_calls: int = 0")
        signature = ("static func thrust_torque(v_air: PackedFloat64Array, rpm: float, "
                     "prop: Dictionary, rho: float) -> PackedFloat64Array:\n")
        source = replace(source, signature, signature + "\tstage_probe_calls += 1\n")
        path.write_text(source)
    script = app / "tests/stage_sharing/mechanism.gd"
    shutil.copy2(HERE / "mechanism.gd", script)
    execute(godot, app, script, output / "mechanism.json")
    report = native._read_json(output / "mechanism.json")
    roster = ["smooth_active", "legacy_active", "no_wash_active", "turbine",
              "stopped_no_residual", "stopped_residual"]
    if (report.get("format") != "openrc-e0b6p-stage-sharing-mechanism v1"
            or report.get("status") != "pass" or report.get("failures") != 0
            or [row.get("case") for row in report.get("rows", [])] != roster
            or any(row.get("passed") is not True for row in report.get("rows", []))):
        raise RuntimeError("Mechanism proof failed")
    # Prove that the assertions reject both lost sharing and changed forces. Mutate only this copy.
    prop_path = app / "tests/stage_sharing/propulsion.gd"
    original = prop_path.read_text()
    mutations = {
        "duplicate_work": replace(original,
            "thrust_torque(v_air, rpm, prop, rho) if stage_tq.is_empty() else stage_tq",
            "thrust_torque(v_air, rpm, prop, rho)"),
        "changed_thrust": replace(original, "var thrust := tq[0]", "var thrust := tq[0] + 0.01"),
    }
    mutation_rows = []
    try:
        for name, source in mutations.items():
            prop_path.write_text(source)
            path = output / f"mutation-{name}.json"
            try:
                execute(godot, app, script, path)
            except RuntimeError:
                value = native._read_json(path)
                log = path.with_suffix(".run.log").read_text()
                if value.get("status") != "fail" or value.get("failures", 0) < 1 or native.ERROR_RE.search(log):
                    raise RuntimeError(f"Mutation {name} did not fail by a mechanism assertion")
                mutation_rows.append({"mutation": name, "assertion_failures": value["failures"]})
            else:
                raise RuntimeError(f"Mechanism missed mutation {name}")
    finally:
        prop_path.write_text(original)
    (output / "mutations.json").write_text(json.dumps(mutation_rows, indent=2) + "\n")


def check_comparator(report: dict) -> list[str]:
    mutations = {
        "missing_row": lambda d: d["flight_rows"].pop(),
        "nonfinite_timing": lambda d: d["direct_rows"][0]["baseline_samples_us"].__setitem__(0, float("nan")),
        "different_hash": lambda d: d["flight_rows"][0].__setitem__("candidate_trajectory_sha256", "0" * 64),
        "missing_boundaries": lambda d: d["counts"].__setitem__("flight_boundaries_compared", 0),
    }
    for name, mutate in mutations.items():
        candidate = copy.deepcopy(report)
        mutate(candidate)
        try:
            summarize(candidate)
        except RuntimeError:
            continue
        raise RuntimeError(f"Comparator accepted mutation {name}")
    return list(mutations)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--library", type=Path, help="Omit for the production GDScript wake")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--keep-work", action="store_true")
    args = parser.parse_args()
    args.project = args.project.expanduser().resolve()
    if args.library:
        args.library = args.library.expanduser().resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    godot = native._resolve_godot(args.godot)
    evidence = {"format": "openrc-e0b6p-stage-sharing-evidence v1", "status": "running",
                "host": platform.platform(), "godot": godot,
                "backend": "native" if args.library else "gdscript",
                "source_revision": native._source_revision(args.project),
                "source_sha256": native._source_hashes(args.project),
                "harness_sha256": {p.name: native._sha256(p) for p in HERE.glob("*.*")
                                   if p.suffix in (".py", ".gd")}}
    if args.library:
        evidence["library_sha256"] = native._sha256(args.library)
    work = Path(tempfile.mkdtemp(prefix="openrc-stage-sharing-"))
    app = work / "app"
    try:
        native._copy_project(args.project, app)
        stage(app, output, args.library)
        execute(godot, app, app / "tests/stage_sharing/probe.gd", output / "profile.json")
        profile = native._read_json(output / "profile.json")
        evidence["timing_summary"] = summarize(profile)
        evidence["comparator_mutations_rejected"] = check_comparator(profile)
        mechanism(godot, app, output)
        evidence["status"] = "pass"
    except Exception as error:
        evidence.update(status="fail", error=str(error))
        raise
    finally:
        if args.keep_work:
            evidence["work"] = str(work)
        else:
            shutil.rmtree(work)
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n")
    print(f"Stage-sharing experiment passed: {output / 'evidence.json'}")


if __name__ == "__main__":
    main()
