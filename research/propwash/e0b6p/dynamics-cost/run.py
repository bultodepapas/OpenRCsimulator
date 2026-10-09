#!/usr/bin/env python3
"""Split prepared-path aero and simulation cost in a disposable Godot project."""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import platform
import statistics
import struct
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


tick = module('prepared_dynamics_tick', HERE.parent / 'prepared-cost/tick_run.py')
aero = module('prepared_dynamics_aero', HERE / 'aero_cost.py')
simulation = module('prepared_dynamics_simulation', HERE / 'simulation_cost.py')
prepared, attribution = tick.prepared, tick.attribution


def add_bytes(source):
    anchor = 'loads=Array(flight.sim.last_loads)' if 'loads=Array(flight.sim.last_loads)' in source else 'loads = Array(flight.sim.last_loads)'
    return tick.replace(source, anchor, anchor + ', raw_bytes = ' +
        'flight.sim.state.to_byte_array().hex_encode() + flight.sim.aux.to_byte_array().hex_encode() + ' +
        'flight.sim.continuous.to_byte_array().hex_encode() + flight.sim.last_loads.to_byte_array().hex_encode()')


def compare(base, prof):
    result = tick.compare(base, prof)
    for left, right in zip(base['rows'], prof['rows'], strict=True):
        for a, b in zip(left['boundaries'], right['boundaries'], strict=True):
            for row in (a, b):
                value = row.get('raw_bytes')
                expected = b''.join(struct.pack('<d', v) for field in ('state', 'aux', 'continuous', 'loads') for v in row[field])
                if not isinstance(value, str) or value != expected.hex():
                    raise RuntimeError('Original Godot float64 buffer bytes missing or inconsistent')
            if a['raw_bytes'] != b['raw_bytes']:
                raise RuntimeError('Original Godot buffer bytes differ')
        for sample, ticks in [(s['profile'], 24) for s in right['enabled_samples']] + [(right['trajectory_profile'], 240)]:
            if any(v <= 0 for v in sample['calls'].values()):
                raise RuntimeError('Present timer counters must be positive')
            allowed = set(attribution.COMPONENTS) | {'adapter_native_dispatch', 'adapter_thrust_torque'} | set(aero.TIMERS) | set(aero.ROUTES) | set(simulation.TIMERS)
            if any(type(v) is not int or v < 0 for v in sample['elapsed_usec'].values()):
                raise RuntimeError('Elapsed microseconds must be nonnegative integers')
            if set(sample['calls']) - allowed:
                raise RuntimeError('Unknown timer in profile')
            aero.reduce(sample, ticks)
            simulation.reduce(sample, ticks)
    result['original_godot_buffer_bytes_exact'] = True
    result['buffer_byte_order'] = 'little-endian Linux host'
    return result


def summarize(base, prof):
    rows = tick.summarize(base, prof)
    for summary, row in zip(rows, prof['rows'], strict=True):
        buckets = summary['exclusive_component_mean_us_per_tick']
        del buckets['Aero.loads']
        del buckets['rest sim.step']
        components = []
        for sample in row['enabled_samples']:
            components.append(aero.reduce(sample['profile'], 24) | simulation.reduce(sample['profile'], 24))
        buckets.update({name: statistics.mean(c[name] for c in components) for name in components[0]})
        if abs(sum(buckets.values()) - summary['instrumented_step_timer_mean_us_per_tick']) > 1e-9:
            raise RuntimeError('Expanded exclusive accounting does not sum')
        summary['nested_samples_us_per_tick'] = components
    return rows


def negative_controls(base, prof):
    rejected = tick.negative_controls(base, prof)
    def first(p):
        return p['rows'][0]['enabled_samples'][0]['profile']
    def remove(p, name):
        for field in ('calls', 'elapsed_usec'):
            first(p)[field].pop(name)
    # Require local wing/tail phases even when both its timer and counter vanish.
    def remove_local(p):
        for row in p['rows']:
            for sample in row['enabled_samples']:
                if sample['profile']['calls'].get('aero_local', 0):
                    for field in ('calls', 'elapsed_usec'):
                        sample['profile'][field].pop('aero_local_strips')
                    return
        raise RuntimeError('Positive control never exercised local strips')
    def remove_branch(p, branch):
        for row in p['rows']:
            for sample in row['enabled_samples']:
                profile = sample['profile']
                if profile['calls'].get('aero_local', 0) and profile['calls'].get('aero_global', 0):
                    names = ('aero_local', *aero.TIMERS[3:7]) if branch == 'local' else ('aero_global', 'aero_global_downwash')
                    for field in ('calls', 'elapsed_usec'):
                        for name in names:
                            profile[field].pop(name)
                    return
        raise RuntimeError('Positive control never exercised both aero branches')
    mutations = {
        'missing_blend_timer_and_counter': lambda b, p: remove(p, 'aero_blend'),
        'missing_global_downwash_phase': lambda b, p: remove(p, 'aero_global_downwash'),
        'missing_entire_local_branch': lambda b, p: remove_branch(p, 'local'),
        'missing_entire_global_branch': lambda b, p: remove_branch(p, 'global'),
        'missing_local_strip_phase': lambda b, p: remove_local(p),
        'overlapping_aero_phases': lambda b, p: first(p)['elapsed_usec'].update(aero_blend=10**9),
        'missing_original_bytes': lambda b, p: p['rows'][0]['boundaries'][0].pop('raw_bytes'),
        'changed_original_bytes': lambda b, p: p['rows'][0]['boundaries'][0].update(raw_bytes='00' * 264),
        'missing_simulation_phase': lambda b, p: remove(p, simulation.TIMERS[0]),
        'overlapping_simulation_phases': lambda b, p: first(p)['elapsed_usec'].update({simulation.TIMERS[0]: 10**9}),
        'fractional_elapsed_timer': lambda b, p: first(p)['elapsed_usec'].update(aero_blend=0.5),
        'unknown_timer': lambda b, p: [first(p)[field].update(unexpected=0) for field in ('calls', 'elapsed_usec')],
    }
    for name, mutate in mutations.items():
        b, p = copy.deepcopy(base), copy.deepcopy(prof)
        mutate(b, p)
        try:
            compare(b, p)
            summarize(b, p)
        except (RuntimeError, KeyError, TypeError, ValueError):
            rejected.append(name)
        else:
            raise RuntimeError(f'Negative control escaped: {name}')
    return rejected


def main():
    if sys.platform != "linux" or sys.byteorder != "little":
        raise RuntimeError("This probe requires a little-endian Linux host")
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
    input_hashes = tick.app_inputs(project)
    prepared.native._copy_project(project, app)
    if tick.app_inputs(app) != input_hashes:
        raise RuntimeError("App inputs changed while copying")
    original_hashes = prepared.native._source_hashes(app)
    harness = sorted(p for p in HERE.parent.rglob("*") if p.is_file()
                     and p.suffix in {".py", ".gd", ".cpp", ".h", ".json"}
                     and "__pycache__" not in p.parts)
    harness_hashes = {str(p.relative_to(ROOT)): attribution._sha256(p) for p in harness}
    evidence = {"format": "openrc-prepared-dynamics-cost v1", "status": "running", "build": build,
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
        base_path.write_text(add_bytes(tick.add_protocol(base_path.read_text(), "NativeAdapter",
                                         "\t\t\tvar cp: Dictionary = flight.sim.checkpoint()")))
        attribution._check_only(godot, app, base_path, output / "baseline-parse.log")
        attribution._run_godot(godot, app, base_path, output / "baseline.json", 600)
        prof_path = attribution._instrument_project(app)
        prof_path.write_text(add_bytes(tick.add_protocol(prof_path.read_text(), "Adapter",
                                         "\t\t\tvar checkpoint: Dictionary = flight.sim.checkpoint()")))
        tick.instrument_adapter(app)
        aero.instrument(app)
        evidence["simulation_timers"] = simulation.instrument(app)
        attribution._check_only(godot, app, prof_path, output / "instrumented-parse.log")
        attribution._run_godot(godot, app, prof_path, output / "instrumented.json", 600)
        base = json.loads((output / "baseline.json").read_text())
        prof = json.loads((output / "instrumented.json").read_text())
        evidence.update(comparison=compare(base, prof), rows=summarize(base, prof),
                        negative_controls_rejected=negative_controls(base, prof))
        for path, digest in hashes.items():
            if attribution._sha256(path) != digest:
                raise RuntimeError(f"Build changed during measurement: {path}")
        if tick.app_inputs(project) != input_hashes:
            raise RuntimeError("Source app changed during measurement")
        if any(attribution._sha256(ROOT / p) != digest for p, digest in harness_hashes.items()):
            raise RuntimeError("Research harness changed during measurement")
        evidence["generated_instrumentation_sha256"] = {
            str(p.relative_to(app)): attribution._sha256(p) for p in (
                base_path, prof_path, native_probe / "adapter.gd", app / "physics/dynamics.gd",
                app / "sim/flight_session.gd", app / "sim/simulation.gd",
                app / "physics/aero.gd", app / "physics/integrator.gd",
                app / "tests/e0b6p_attribution/profiler.gd")}
        evidence["godot"] = prof["godot"]
        evidence["cpu"] = prof["cpu"]
        evidence["raw_sha256"] = {n: attribution._sha256(output / n) for n in ("baseline.json", "instrumented.json")}
        evidence["status"] = "pass"
    except Exception as error:
        evidence.update(status="fail", error=str(error))
        raise
    finally:
        (output / "dynamics-evidence.json").write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n")
    print(f"Prepared dynamics attribution passed: {output / 'dynamics-evidence.json'}")


if __name__ == "__main__":
    main()
