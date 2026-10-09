#!/usr/bin/env python3
"""Measure prepared wake whole ticks in a disposable app with exclusive timers."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path
import platform
import statistics
import struct

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


prepared = module("prepared_cost_model", HERE.parent / "prepared-model/run.py")
attribution = module("prepared_cost_attribution", HERE.parent / "attribution/run.py")
replace = prepared.replace
number = attribution._number


def add_protocol(source, adapter, checkpoint):
    source = replace(source, "\t\t\tvar flight: Node = Flight.new()",
                     f"\t\t\t{adapter}.begin_setup()\n\t\t\tvar flight: Node = Flight.new()")
    source = replace(source, checkpoint,
        f"\t\t\tif not {adapter}.prepare(flight.aircraft.model):\n"
        "\t\t\t\tpush_error(\"Explicit model preparation failed\")\n"
        "\t\t\t\tquit(1)\n\t\t\t\treturn\n"
        f"\t\t\tvar setup_before: int = {adapter}.setup_calls\n"
        f"\t\t\tvar prepared_before: int = {adapter}.prepared_calls\n" + checkpoint)
    source = replace(source, "\t\t\tflight.free()",
        f"\t\t\trows[-1][\"protocol\"] = {{setup_calls = {adapter}.setup_calls - setup_before,\n"
        f"\t\t\t\tprepared_calls = {adapter}.prepared_calls - prepared_before,\n"
        f"\t\t\t\tsetup_mode = {adapter}.setup_mode}}\n\t\t\tflight.free()")
    # Preserve the original state fixtures and add an untimed load boundary check.
    if "continuous=Array(flight.sim.continuous)" in source:
        source = replace(source, "continuous=Array(flight.sim.continuous)",
                         "continuous=Array(flight.sim.continuous), loads=Array(flight.sim.last_loads)")
    else:
        source = replace(source, "continuous = Array(flight.sim.continuous)",
                         "continuous = Array(flight.sim.continuous), loads = Array(flight.sim.last_loads)")
    return source


def instrument_adapter(app):
    path = app / "tests/e0b6p_native/adapter.gd"
    source = replace(path.read_text(), "extends RefCounted",
        'extends RefCounted\nconst Cost = preload("res://tests/e0b6p_attribution/profiler.gd")')
    tq = "\tvar tq_full: PackedFloat64Array = Propulsion.thrust_torque(velocity, rpm, prop, rho)"
    source = replace(source, tq,
        "\tvar cost_started: int = Time.get_ticks_usec() if Cost.enabled else 0\n" + tq +
        '\n\tif Cost.enabled:\n\t\tCost.add("adapter_thrust_torque", Time.get_ticks_usec() - cost_started)')
    source = replace(source, "\tvar result: Variant",
        "\tif Cost.enabled:\n\t\tcost_started = Time.get_ticks_usec()\n\tvar result: Variant")
    source = replace(source, "\tif result is PackedFloat64Array and result.size() == 6 and _all_finite(result):",
        '\tif Cost.enabled:\n\t\tCost.add("adapter_native_dispatch", Time.get_ticks_usec() - cost_started)\n'
        "\tif result is PackedFloat64Array and result.size() == 6 and _all_finite(result):")
    path.write_text(source)


def compare(base, prof):
    attribution._validate_profile(prof)
    attribution._validate_routes(base, "prepared baseline")
    if base.get("format") != "openrc-e0b6p-swirl-cost v1" or len(base.get("rows", [])) != 12:
        raise RuntimeError("Incomplete baseline roster")
    if base.get("ticks_per_batch") != 24 or prof.get("ticks_per_timing_batch") != 24 \
            or prof.get("warmup_batches") != 1 or prof.get("measured_batches") != 5:
        raise RuntimeError("Unexpected timing workload metadata")
    count = 0
    for left, right in zip(base["rows"], prof["rows"], strict=True):
        if (left["regime"], left["swirl_factor"]) != (right["regime"], right["swirl_factor"]):
            raise RuntimeError("Changed case roster")
        if len(left.get("batches_us", [])) != 5:
            raise RuntimeError("Incomplete baseline timing batches")
        if [s.get("pair") for s in right["enabled_samples"]] != list(range(5)):
            raise RuntimeError("Invalid observer-overhead pair order")
        for row in (left, right):
            protocol = row.get("protocol", {})
            if protocol.get("setup_calls") != 0 or protocol.get("setup_mode") is not False:
                raise RuntimeError("Stateless setup leaked into measured work")
            if type(protocol.get("prepared_calls")) is not int or protocol["prepared_calls"] <= 0:
                raise RuntimeError("Prepared calls not observed")
            if len(row.get("boundaries", [])) != 240:
                raise RuntimeError("Incomplete trajectory")
        # Every value is checked even when both arrays compare equal (including NaN/Inf).
        for old, new in zip(left["boundaries"], right["boundaries"], strict=True):
            for field, size in (("state", 13), ("aux", 14), ("continuous", 0), ("loads", 6)):
                x, y = old.get(field), new.get(field)
                if not isinstance(x, list) or not isinstance(y, list) or len(x) != size or len(y) != size:
                    raise RuntimeError(f"Wrong {field} boundary shape")
                for a, b in zip(x, y, strict=True):
                    a, b = number(a, field), number(b, field)
                    if struct.pack("<d", a) != struct.pack("<d", b):
                        raise RuntimeError(f"Changed {field} boundary bits")
                    count += 1
        for sample in right["enabled_samples"] + [{"profile": right["trajectory_profile"]}]:
            profile = sample["profile"]
            calls = profile["calls"]
            if any(type(value) is not int or value < 0 for value in calls.values()):
                raise RuntimeError("Invalid integer call counter")
            if set(profile["elapsed_usec"]) != set(calls):
                raise RuntimeError("Missing or unexpected elapsed timer")
            # Reverse-cutoff can re-enter active flow during the long trajectory;
            # check the actual nested calls instead of assuming its initial branch persists.
            nested = calls.get("adapter_native_dispatch", 0)
            if type(nested) is not int or not 0 <= nested <= calls["slipstream_loads"]:
                raise RuntimeError("Invalid prepared dispatch count")
            if calls.get("adapter_thrust_torque", 0) != nested:
                raise RuntimeError("Adapter timer count mismatch")
            if right["regime"] != "reverse_off" and nested != calls["slipstream_loads"]:
                raise RuntimeError("Active prepared dispatch calls missing")
            for value in profile["elapsed_usec"].values():
                if number(value, "elapsed timer") < 0:
                    raise RuntimeError("Negative timer")
    return {"cases": 12, "boundaries_per_case": 240, "scalars_compared": count,
            "fields": ["state", "aux", "continuous", "loads"], "bit_exact": True}


def summarize(base, prof):
    rows = attribution._summarize_rows(base, prof)
    for summary, row in zip(rows, prof["rows"], strict=True):
        dispatch, thrust, rest = [], [], []
        for batch in row["enabled_samples"]:
            elapsed = batch["profile"]["elapsed_usec"]
            native = number(elapsed.get("adapter_native_dispatch", 0), "native dispatch") / 24
            tq = number(elapsed.get("adapter_thrust_torque", 0), "adapter thrust torque") / 24
            remainder = number(elapsed["slipstream_loads"], "wake") / 24 - native - tq
            if remainder < 0:
                raise RuntimeError("Overlapping adapter timers")
            dispatch.append(native)
            thrust.append(tq)
            rest.append(remainder)
        buckets = summary["exclusive_component_mean_us_per_tick"]
        del buckets["Slipstream.loads"]
        buckets.update({"Prepared native dispatch (inclusive binding)": statistics.mean(dispatch),
                        "Adapter thrust/torque": statistics.mean(thrust),
                        "Adapter remainder": statistics.mean(rest)})
        if abs(sum(buckets.values()) - summary["instrumented_step_timer_mean_us_per_tick"]) > 1e-9:
            raise RuntimeError("Exclusive prepared accounting does not sum")
        summary["prepared_adapter_samples_us_per_tick"] = {
            "native_dispatch": dispatch, "thrust_torque": thrust, "remainder": rest}
        summary["prepared_protocol"] = row["protocol"]
    return rows


def negative_controls(base, prof):
    def check(b, p):
        compare(b, p)
        summarize(b, p)
    rejected = []
    mutations = {
        "missing_dispatch": lambda b, p: p["rows"][0]["enabled_samples"][0]["profile"]["calls"].update(adapter_native_dispatch=0),
        "stateless_fallback": lambda b, p: p["rows"][0]["protocol"].update(setup_calls=1),
        "truncated_trajectory": lambda b, p: p["rows"][0]["boundaries"].pop(),
        "changed_load": lambda b, p: p["rows"][0]["boundaries"][0]["loads"].__setitem__(0, 123.0),
        "matching_nonfinite": lambda b, p: [q["rows"][0]["boundaries"][0]["state"].__setitem__(0, float("inf")) for q in (b, p)],
        "overlapping_timers": lambda b, p: p["rows"][0]["enabled_samples"][0]["profile"]["elapsed_usec"].update(adapter_native_dispatch=10**9),
        "wrong_roster": lambda b, p: p["rows"][0].update(regime="absent"),
        "fractional_counter": lambda b, p: p["rows"][0]["enabled_samples"][0]["profile"]["calls"].update(air_dynamics=96.5),
        "missing_timing_batch": lambda b, p: b["rows"][0]["batches_us"].pop(),
        "duplicate_observer_pair": lambda b, p: p["rows"][0]["enabled_samples"][1].update(pair=0),
        "changed_timing_workload": lambda b, p: b.update(ticks_per_batch=48),
        "missing_elapsed_timer": lambda b, p: p["rows"][0]["enabled_samples"][0]["profile"]["elapsed_usec"].pop("aero_loads"),
    }
    for name, mutate in mutations.items():
        b, p = copy.deepcopy(base), copy.deepcopy(prof)
        mutate(b, p)
        try:
            check(b, p)
        except (RuntimeError, KeyError, TypeError, ValueError):
            rejected.append(name)
        else:
            raise RuntimeError(f"Negative control escaped: {name}")
    return rejected


def app_inputs(project):
    """Freeze all staged app inputs, including loader, fixtures and project settings."""
    return {str(p.relative_to(project)): attribution._sha256(p)
            for p in sorted(project.rglob("*")) if p.is_file()
            and not any(part in {".godot", "captures", ".git", "__pycache__"}
                        for part in p.relative_to(project).parts)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--build", type=Path, default=ROOT / ".tools/native-prepared/build.json")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = args.project.resolve()
    build = json.loads(args.build.read_text())
    library = Path(build["library"]["path"])
    hashes = {library: build["library"]["sha256"]}
    hashes.update({ROOT / v["path"]: v["sha256"] for v in build["sources"].values()})
    for path, digest in hashes.items():
        if attribution._sha256(path) != digest:
            raise RuntimeError(f"Stale prepared build: {path}")
    godot = attribution._resolve(args.godot)
    app = output / "work/app"
    input_hashes = app_inputs(project)
    prepared.native._copy_project(project, app)
    if app_inputs(app) != input_hashes:
        raise RuntimeError("App inputs changed while copying")
    original_hashes = prepared.native._source_hashes(app)
    harness = [Path(__file__), Path(prepared.__file__), Path(attribution.__file__),
               attribution.APP_BENCH, attribution.PROFILE_SCRIPT, attribution.PROFILER_SCRIPT,
               attribution.ADAPTER_SCRIPT, Path(prepared.sharing.__file__), Path(prepared.native.__file__),
               HERE.parent / "prepared-model/verify_lifecycle.gd",
               HERE.parent / "prepared-model/verify_adapter.gd"]
    harness_hashes = {str(p.relative_to(ROOT)): attribution._sha256(p) for p in harness}
    evidence = {"format": "openrc-prepared-tick-cost v1", "status": "running", "build": build,
                "host": platform.platform(), "source_sha256": original_hashes,
                "app_input_sha256": input_hashes, "harness_sha256": harness_hashes,
                "source_revision": prepared.native._source_revision(project)}
    try:
        probe = prepared.stage(app, library)
        for name, key, count_key, expected in (
            ("verify_lifecycle", "failures", "case_count", 68),
            ("verify_adapter", "failures", "case_count", 35),
        ):
            prepared.execute(godot, app, probe / f"{name}.gd", output / f"{name}.json")
            r = json.loads((output / f"{name}.json").read_text())
            if r.get(key) != 0 or r.get(count_key) != expected:
                raise RuntimeError(f"Incomplete lifecycle verification: {name}")
        evidence["adapter_mutations"] = prepared.check_adapter_mutations(godot, app, probe, output)
        native_probe = app / "tests/e0b6p_native"
        (native_probe / "adapter.gd").write_text((probe / "adapter.gd").read_text())
        base_path = attribution._instrument_baseline_bench(app, native_probe)
        base_path.write_text(add_protocol(base_path.read_text(), "NativeAdapter",
                                         "\t\t\tvar cp: Dictionary = flight.sim.checkpoint()"))
        attribution._check_only(godot, app, base_path, output / "baseline-parse.log")
        attribution._run_godot(godot, app, base_path, output / "baseline.json", 600)
        prof_path = attribution._instrument_project(app)
        prof_path.write_text(add_protocol(prof_path.read_text(), "Adapter",
                                         "\t\t\tvar checkpoint: Dictionary = flight.sim.checkpoint()"))
        instrument_adapter(app)
        attribution._check_only(godot, app, prof_path, output / "instrumented-parse.log")
        attribution._run_godot(godot, app, prof_path, output / "instrumented.json", 600)
        base = json.loads((output / "baseline.json").read_text())
        prof = json.loads((output / "instrumented.json").read_text())
        evidence.update(comparison=compare(base, prof), rows=summarize(base, prof),
                        negative_controls_rejected=negative_controls(base, prof))
        for path, digest in hashes.items():
            if attribution._sha256(path) != digest:
                raise RuntimeError(f"Build changed during measurement: {path}")
        if app_inputs(project) != input_hashes:
            raise RuntimeError("Source app changed during measurement")
        if any(attribution._sha256(ROOT / p) != digest for p, digest in harness_hashes.items()):
            raise RuntimeError("Research harness changed during measurement")
        evidence["generated_instrumentation_sha256"] = {
            str(p.relative_to(app)): attribution._sha256(p) for p in (
                base_path, prof_path, native_probe / "adapter.gd", app / "physics/dynamics.gd",
                app / "sim/flight_session.gd", app / "sim/simulation.gd")}
        evidence["godot"] = prof["godot"]
        evidence["cpu"] = prof["cpu"]
        evidence["raw_sha256"] = {n: attribution._sha256(output / n) for n in ("baseline.json", "instrumented.json")}
        evidence["status"] = "pass"
    except Exception as error:
        evidence.update(status="fail", error=str(error))
        raise
    finally:
        (output / "tick-evidence.json").write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n")
    print(f"Prepared tick attribution passed: {output / 'tick-evidence.json'}")


if __name__ == "__main__":
    main()
