#!/usr/bin/env python3
"""Exercise explicit native model preparation in a disposable app; never patch production."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


sharing = module("sharing", HERE.parent / "stage-sharing/run.py")
native = sharing.native
replace = sharing.replace
execute = sharing.execute


def prepared_adapter(source: str) -> str:
    # Setup is an explicit harness mode, never a fallback after failed preparation.
    source = replace(source, 'static var backend: Object = null', '''static var backend: Object = null
static var setup_mode: bool = true
static var prepared_token: int = 0
static var prepared_model: Dictionary = {}
static var prepared_smooth: bool = false
static var preparation_attempts: int = 0
static var prepared_calls: int = 0
static var setup_calls: int = 0


static func begin_setup() -> void:
	setup_mode = true
	prepared_token = 0
	prepared_model = {}
	if available():
		backend.call("invalidate_model")


## Caller must explicitly reprepare after every model edit, including nested in-place changes.
## No dictionary-identity cache is used. The identity guard only detects replacement, not mutation.
static func prepare(model: Dictionary) -> bool:
	setup_mode = false
	prepared_token = 0
	prepared_model = model
	prepared_smooth = model.get("propulsion", {}).get("slipstream", {}).has("edge_fraction")
	preparation_attempts += 1
	if not available():
		return false
	backend.call("invalidate_model")
	var ss: Dictionary = model.get("propulsion", {}).get("slipstream", {})
	if not ss.has("edge_fraction"):
		return true # Legacy/no-wake data never goes to the prepared native kernel.
	prepared_token = int(backend.call("prepare_model", model))
	return prepared_token > 0
''')
    source = replace(source, '\tvar prop: Dictionary = model.propulsion',
        '''\tif not setup_mode:
		var smooth: bool = model.get("propulsion", {}).get("slipstream", {}).has("edge_fraction")
		if not is_same(model, prepared_model) or smooth != prepared_smooth:
			route_counts["refused"] = int(route_counts["refused"]) + 1
			return _non_finite_loads()
	var prop: Dictionary = model.propulsion''')
    source = replace(source, '\troute_counts["native"] = int(route_counts["native"]) + 1',
        '''\troute_counts["native"] = int(route_counts["native"]) + 1
	if not setup_mode and (prepared_token <= 0 or not is_same(model, prepared_model)):
		route_counts["refused"] = int(route_counts["refused"]) + 1
		return _non_finite_loads()''')
    source = replace(source, '''\tvar result: Variant = backend.call("loads", state, velocity, d, model, thrust_torque, rho, fade,
		resolved_downwash, transported_dv)''', '''\tvar result: Variant
	if setup_mode:
		setup_calls += 1
		result = backend.call("loads", state, velocity, d, model, thrust_torque, rho, fade,
			resolved_downwash, transported_dv)
	else:
		prepared_calls += 1
		result = backend.call("loads_prepared", state, velocity, d, prepared_token, thrust_torque, rho, fade,
			resolved_downwash, transported_dv)''')
    return source


def stage(app: Path, library: Path) -> Path:
    baseline = native._install_probe(app, library)
    extension = baseline / "smooth_wake.gdextension"
    extension.write_text(replace(extension.read_text(), "openrc_smooth_wake_library_init",
                                 "openrc_prepared_wake_library_init"))
    base_adapter = replace((baseline / "adapter.gd").read_text(), '"OpenRCSmoothWake"', '"OpenRCPreparedWake"')
    (baseline / "adapter.gd").write_text(base_adapter)
    probe = app / "tests/e0b6p_prepared"
    probe.mkdir(parents=True)
    (probe / "adapter.gd").write_text(prepared_adapter(base_adapter))
    dynamics = (app / "physics/dynamics.gd").read_text()
    (probe / "dynamics.gd").write_text(replace(dynamics,
        'preload("res://physics/slipstream.gd")', 'preload("res://tests/e0b6p_prepared/adapter.gd")'))
    flight = (app / "sim/flight_session.gd").read_text()
    (probe / "flight_session.gd").write_text(replace(flight,
        'preload("res://physics/dynamics.gd")', 'preload("res://tests/e0b6p_prepared/dynamics.gd")'))
    native._replace_dynamics_slipstream(app, True)
    profile = (HERE.parent / "stage-sharing/probe.gd").read_text().replace(
        "res://tests/stage_sharing/", "res://tests/e0b6p_prepared/")
    profile = replace(profile, "extends SceneTree", '''extends SceneTree
const Prepared: Script = preload("res://tests/e0b6p_prepared/adapter.gd")''')
    profile = replace(profile, "func _append_direct_case(fixture: Dictionary) -> void:",
        '''func _append_direct_case(fixture: Dictionary) -> void:
	if not Prepared.prepare(fixture.model):
		_fail("explicit direct model preparation failed")
		return''')
    profile = replace(profile, "\tif not baseline_ok or not candidate_ok:",
        '''\tif baseline_ok and candidate_ok:
		candidate_ok = Prepared.prepare(candidate.aircraft.model)
	if not baseline_ok or not candidate_ok:''')
    profile = replace(profile,
        "func _configure_flight(flight: Node, aircraft_id: String, regime: String, smooth_mode: String) -> bool:",
        '''func _configure_flight(flight: Node, aircraft_id: String, regime: String, smooth_mode: String) -> bool:
	Prepared.begin_setup()''')
    profile = replace(profile, '\t\t"backend_routes": routes,', '''\t\t"backend_routes": routes,
		"prepared_protocol": {attempts = Prepared.preparation_attempts, prepared_calls = Prepared.prepared_calls,
			setup_calls = Prepared.setup_calls, setup_mode_at_end = Prepared.setup_mode},''')
    # The reused profile format deliberately keeps its strict roster/hash comparator unchanged.
    (probe / "profile.gd").write_text(profile)
    for name in ("verify_lifecycle", "verify_adapter"):
        shutil.copy2(HERE / f"{name}.gd", probe / f"{name}.gd")

    # Reuse all 165 model/control field mutations through the prepared API.
    fields = (HERE.parent / "decoder/verify_fields.gd").read_text()
    fields = replace(fields,
        '''\treturn Adapter.backend.call("loads", _state, _velocity, controls, model, _thrust_torque,
		RHO, _fade, HELD_CL, PackedFloat64Array())''',
        '''\tvar token: int = int(Adapter.backend.call("prepare_model", model))
	if token <= 0:
		return PackedFloat64Array()
	return Adapter.backend.call("loads_prepared", _state, _velocity, controls, token, _thrust_torque,
		RHO, _fade, HELD_CL, PackedFloat64Array())''')
    (probe / "verify_fields.gd").write_text(fields)

    verifier = (baseline / "verify.gd").read_text()
    verifier = replace(verifier, 'const Adapter = preload("res://tests/e0b6p_native/adapter.gd")',
        '''const Adapter = preload("res://tests/e0b6p_prepared/adapter.gd")
const RawAdapter = preload("res://tests/e0b6p_native/adapter.gd")''')
    verifier = replace(verifier, "\tvar expected: PackedFloat64Array = Oracle.loads(state, air, controls, model, rpm, rho,",
        '''\t_check("model explicitly prepared: " + label, Adapter.prepare(model))
	var expected: PackedFloat64Array = Oracle.loads(state, air, controls, model, rpm, rho,''')
    verifier = replace(verifier, "\t_compared += 1", '''\tvar raw_load: PackedFloat64Array = RawAdapter.loads(state, air, controls, model, rpm, rho,
		downwash_cl, transported_dv)
	_check("prepared equals raw native bytes: " + label, actual.to_byte_array() == raw_load.to_byte_array())
	_compared += 1''')
    verifier = replace(verifier, "func _check_malformed_refusal(model: Dictionary) -> void:",
        '''func _check_malformed_refusal(model: Dictionary) -> void:
	_check("malformed probe model prepared", Adapter.prepare(model))''')
    verifier = replace(verifier, '\tvar model: Dictionary = loaded.model',
        '\tvar model: Dictionary = loaded.model\n\t_check("legacy model explicitly prepared", Adapter.prepare(model))')
    (probe / "verify_native.gd").write_text(verifier)
    return probe


def check_adapter_mutations(godot: str, app: Path, probe: Path, output: Path) -> list[dict]:
    """Demonstrate that successful load equality cannot hide a bypassed lifecycle."""
    path = probe / "adapter.gd"
    original = path.read_text()
    mutations = {
        "allow_route_change": replace(original, "smooth != prepared_smooth", "false"),
        "bypass_prepared_dispatch": replace(original,
            'backend.call("loads_prepared", state, velocity, d, prepared_token, thrust_torque, rho, fade,',
            'backend.call("loads", state, velocity, d, model, thrust_torque, rho, fade,'),
    }
    rows = []
    try:
        for name, source in mutations.items():
            path.write_text(source)
            target = output / f"mutation_{name}.json"
            target.unlink(missing_ok=True)
            try:
                execute(godot, app, probe / "verify_adapter.gd", target)
            except RuntimeError:
                # A parse failure, crash, or stale report is not a caught assertion.
                if not target.is_file():
                    raise
                report = native._read_json(target)
                if report.get("failures", 0) <= 0:
                    raise
                rows.append({"mutation": name, "rejected": True,
                             "failures": report["failures"]})
            else:
                raise RuntimeError(f"Adapter mutation escaped: {name}")
    finally:
        path.write_text(original)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--build", type=Path, default=ROOT / ".tools/native-prepared/build.json")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--keep-work", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    project = args.project.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    build = json.loads(args.build.read_text())
    library = Path(build["library"]["path"])
    if native._sha256(library) != build["library"]["sha256"]:
        raise RuntimeError("Library differs from its build manifest")
    for name, source in build["sources"].items():
        if native._sha256(ROOT / source["path"]) != source["sha256"]:
            raise RuntimeError(f"Build is stale: {name}")
    godot = native._resolve_godot(args.godot)
    work = Path(tempfile.mkdtemp(prefix="openrc-prepared-"))
    app = work / "app"
    evidence = {"format": "openrc-e0b6p-prepared-evidence v1", "status": "running", "build": build,
                "source_revision": native._source_revision(project), "verify_only": args.verify_only}
    try:
        native._copy_project(project, app)
        evidence["source_sha256"] = native._source_hashes(app)
        evidence["harness_sha256"] = {str(p.relative_to(ROOT)): native._sha256(p)
            for p in list(HERE.glob("*.py")) + list(HERE.glob("*.gd")) + [HERE / "native_extension.inc",
                HERE.parent / "stage-sharing/probe.gd", HERE.parent / "stage-sharing/run.py",
                HERE.parent / "decoder/verify_fields.gd"]}
        probe = stage(app, library)
        for name in ("verify_lifecycle", "verify_adapter", "verify_fields", "verify_native"):
            execute(godot, app, probe / f"{name}.gd", output / f"{name}.json")
            report = native._read_json(output / f"{name}.json")
            key = "failed" if name == "verify_fields" else "failures"
            if report.get(key) != 0:
                raise RuntimeError(f"Verification failed: {name}")
            if name == "verify_lifecycle" and report.get("case_count") != 68:
                raise RuntimeError("Incomplete lifecycle checks")
            if name == "verify_adapter" and report.get("case_count") != 35:
                raise RuntimeError("Incomplete adapter checks")
            if name == "verify_fields" and report.get("cases") != 165:
                raise RuntimeError("Incomplete field checks")
            if name == "verify_native" and report.get("compared_loads") != 297:
                raise RuntimeError("Incomplete native comparisons")
        if not args.verify_only:
            execute(godot, app, probe / "profile.gd", output / "profile.json")
            profile = native._read_json(output / "profile.json")
            evidence["timing_summary"] = sharing.summarize(profile)
            evidence["comparator_mutations_rejected"] = sharing.check_comparator(profile)
            protocol = profile.get("prepared_protocol", {})
            if protocol.get("attempts") != 49 or protocol.get("prepared_calls", 0) <= 0 or protocol.get("setup_mode_at_end") is not False:
                raise RuntimeError("Profile did not exercise the explicit preparation protocol")
        evidence["adapter_mutations"] = check_adapter_mutations(godot, app, probe, output)
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
    print(f"Prepared-model experiment passed: {output / 'evidence.json'}")


if __name__ == "__main__":
    main()
