#!/usr/bin/env python3
"""Compare the wing-loop Aero candidate in paired whole-flight runs; never edit the source app."""
from __future__ import annotations

import argparse
import copy
import difflib
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot import harness module: {path}")
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


sharing = module("wing_loop_stage_sharing", HERE.parent / "stage-sharing/run.py")
prepared = module("wing_loop_prepared_model", HERE.parent / "prepared-model/run.py")
native = sharing.native
replace = sharing.replace


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def app_snapshot(project: Path) -> dict[str, str]:
    ignored = {".godot", "captures", ".git", "__pycache__"}
    result: dict[str, str] = {}
    for path in sorted(project.rglob("*")):
        if path.is_file() and not any(part in ignored for part in path.relative_to(project).parts):
            result["app/" + str(path.relative_to(project))] = sha256(path)
    return result


def build_snapshot(project: Path, candidate_path: Path, verify_path: Path,
                   baseline_override: Path | None, build_manifest: Path | None) -> dict[str, str]:
    """Hash all source inputs which affect this run, including its disposable-app source set."""
    result = app_snapshot(project)
    for path in (candidate_path, verify_path, HERE / "run.py", HERE.parent / "stage-sharing/probe.gd",
                 HERE.parent / "stage-sharing/run.py", HERE.parent / "prepared-model/run.py",
                 HERE.parent / "native/run.py", HERE.parent / "native/adapter.gd"):
        result[str(path.relative_to(ROOT))] = sha256(path)
    if baseline_override is not None:
        result["baseline_aero_override"] = sha256(baseline_override)
    if build_manifest is not None:
        result[str(build_manifest)] = sha256(build_manifest)
        manifest = json.loads(build_manifest.read_text(encoding="utf-8"))
        for source in manifest.get("sources", {}).values():
            path = (ROOT / source["path"]).resolve()
            result[str(path.relative_to(ROOT))] = sha256(path)
        library = Path(manifest["library"]["path"]).expanduser().resolve()
        result[str(library)] = sha256(library)
    return result


def verify_build_manifest(path: Path) -> tuple[dict, Path]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("format") != "openrc-e0b6p-prepared-model-build v1":
        raise RuntimeError("Unexpected prepared-model build manifest")
    for name, source in manifest.get("sources", {}).items():
        source_path = (ROOT / source["path"]).resolve()
        if not source_path.is_file() or sha256(source_path) != source.get("sha256"):
            raise RuntimeError(f"Prepared-model build source changed: {name} ({source_path})")
    library = Path(manifest.get("library", {}).get("path", "")).expanduser().resolve()
    if not library.is_file() or sha256(library) != manifest["library"].get("sha256"):
        raise RuntimeError("Prepared-model library differs from its immutable build manifest")
    return manifest, library


def write_diff(before: str, after: str, output: Path, source_name: str) -> None:
    patch = difflib.unified_diff(before.splitlines(True), after.splitlines(True),
        fromfile=f"a/app/{source_name}", tofile=f"b/app/tests/wing_loops/aero.gd")
    (output / "candidate.patch").write_text("".join(patch), encoding="utf-8")


def stage_variant_scripts(app: Path, candidate_aero: str, backend: str,
                         library: Path | None) -> dict[str, Path]:
    """Write baseline/candidate dependency closures with isolated Aero and adapter resources."""
    root = app / "tests/wing_loops"
    base_dir = root / "baseline"
    candidate_dir = root / "candidate"
    base_dir.mkdir(parents=True, exist_ok=True)
    candidate_dir.mkdir(parents=True, exist_ok=True)
    (root / "aero.gd").write_text(candidate_aero, encoding="utf-8")

    base_slipstream = (app / "physics/slipstream.gd").read_text(encoding="utf-8")
    candidate_slipstream = replace(base_slipstream,
        'const Aero := preload("res://physics/aero.gd")',
        'const Aero := preload("res://tests/wing_loops/aero.gd")')
    (base_dir / "slipstream.gd").write_text(base_slipstream, encoding="utf-8")
    (candidate_dir / "slipstream.gd").write_text(candidate_slipstream, encoding="utf-8")

    base_wash = replace((app / "physics/wash_transport.gd").read_text(encoding="utf-8"),
        'preload("res://physics/slipstream.gd")',
        'preload("res://tests/wing_loops/baseline/slipstream.gd")')
    candidate_wash = replace((app / "physics/wash_transport.gd").read_text(encoding="utf-8"),
        'preload("res://physics/slipstream.gd")',
        'preload("res://tests/wing_loops/candidate/slipstream.gd")')
    (base_dir / "wash_transport.gd").write_text(base_wash, encoding="utf-8")
    (candidate_dir / "wash_transport.gd").write_text(candidate_wash, encoding="utf-8")

    baseline_adapter_path = app / "tests/wing_loops/baseline_adapter.gd"
    candidate_adapter_path = app / "tests/wing_loops/candidate_adapter.gd"
    staged: dict[str, Path] = {
        "candidate_aero": root / "aero.gd",
        "baseline_dynamics": base_dir / "dynamics.gd",
        "baseline_flight": base_dir / "flight_session.gd",
        "baseline_slipstream": base_dir / "slipstream.gd",
        "baseline_wash_transport": base_dir / "wash_transport.gd",
        "candidate_dynamics": candidate_dir / "dynamics.gd",
        "candidate_flight": candidate_dir / "flight_session.gd",
        "candidate_slipstream": candidate_dir / "slipstream.gd",
        "candidate_wash_transport": candidate_dir / "wash_transport.gd",
    }
    base_dynamics = (app / "physics/dynamics.gd").read_text(encoding="utf-8")
    candidate_dynamics = replace(base_dynamics,
        'const Aero := preload("res://physics/aero.gd")',
        'const Aero := preload("res://tests/wing_loops/aero.gd")')
    base_slip_path = 'preload("res://tests/wing_loops/baseline/slipstream.gd")'
    candidate_slip_path = 'preload("res://tests/wing_loops/candidate/slipstream.gd")'
    if backend == "prepared":
        if library is None:
            raise RuntimeError("Prepared backend requires a verified native library")
        native_probe = native._install_probe(app, library)
        extension = native_probe / "smooth_wake.gdextension"
        extension.write_text(replace(extension.read_text(encoding="utf-8"),
            "openrc_smooth_wake_library_init", "openrc_prepared_wake_library_init"), encoding="utf-8")
        adapter_source = replace((native_probe / "adapter.gd").read_text(encoding="utf-8"),
            '"OpenRCSmoothWake"', '"OpenRCPreparedWake"')
        base_adapter = prepared.prepared_adapter(adapter_source)
        base_adapter = replace(base_adapter,
            'preload("res://physics/slipstream.gd")',
            'preload("res://tests/wing_loops/baseline/slipstream.gd")')
        candidate_adapter = prepared.prepared_adapter(adapter_source)
        candidate_adapter = replace(candidate_adapter,
            'preload("res://physics/slipstream.gd")',
            'preload("res://tests/wing_loops/candidate/slipstream.gd")')
        candidate_adapter = replace(candidate_adapter,
            'preload("res://physics/aero.gd")',
            'preload("res://tests/wing_loops/aero.gd")')
        base_adapter = add_profile_route_counters(base_adapter)
        candidate_adapter = add_profile_route_counters(candidate_adapter)
        baseline_adapter_path.write_text(base_adapter, encoding="utf-8")
        candidate_adapter_path.write_text(candidate_adapter, encoding="utf-8")
        staged["baseline_adapter"] = baseline_adapter_path
        staged["candidate_adapter"] = candidate_adapter_path
        base_slip_path = 'preload("res://tests/wing_loops/baseline_adapter.gd")'
        candidate_slip_path = 'preload("res://tests/wing_loops/candidate_adapter.gd")'

    base_dynamics = replace(base_dynamics,
        'const Slipstream := preload("res://physics/slipstream.gd")',
        f"const Slipstream := {base_slip_path}")
    candidate_dynamics = replace(candidate_dynamics,
        'const Slipstream := preload("res://physics/slipstream.gd")',
        f"const Slipstream := {candidate_slip_path}")
    (base_dir / "dynamics.gd").write_text(base_dynamics, encoding="utf-8")
    (candidate_dir / "dynamics.gd").write_text(candidate_dynamics, encoding="utf-8")

    base_flight = (app / "sim/flight_session.gd").read_text(encoding="utf-8")
    base_flight = replace(base_flight,
        'const WashTransport := preload("res://physics/wash_transport.gd")',
        'const WashTransport := preload("res://tests/wing_loops/baseline/wash_transport.gd")')
    base_flight = replace(base_flight,
        'const Dynamics := preload("res://physics/dynamics.gd")',
        'const Dynamics := preload("res://tests/wing_loops/baseline/dynamics.gd")')
    candidate_flight = (app / "sim/flight_session.gd").read_text(encoding="utf-8")
    candidate_flight = replace(candidate_flight,
        'const Aero := preload("res://physics/aero.gd")',
        'const Aero := preload("res://tests/wing_loops/aero.gd")')
    candidate_flight = replace(candidate_flight,
        'const WashTransport := preload("res://physics/wash_transport.gd")',
        'const WashTransport := preload("res://tests/wing_loops/candidate/wash_transport.gd")')
    candidate_flight = replace(candidate_flight,
        'const Dynamics := preload("res://physics/dynamics.gd")',
        'const Dynamics := preload("res://tests/wing_loops/candidate/dynamics.gd")')
    (base_dir / "flight_session.gd").write_text(base_flight, encoding="utf-8")
    (candidate_dir / "flight_session.gd").write_text(candidate_flight, encoding="utf-8")
    return staged


def add_profile_route_counters(source: str) -> str:
    source = replace(source, "static var setup_calls: int = 0", '''static var setup_calls: int = 0
static var profile_routes: Dictionary = {"prepared": 0, "setup": 0, "refused": 0}


static func reset_profile_routes() -> void:
	profile_routes = {"prepared": 0, "setup": 0, "refused": 0}''')
    refused = 'route_counts["refused"] = int(route_counts["refused"]) + 1'
    source = re.sub(r'(?m)^([ \t]*)' + re.escape(refused) + r'$',
        lambda match: match.group(1) + refused + '\n' + match.group(1)
            + 'profile_routes["refused"] = int(profile_routes["refused"]) + 1', source)
    source = replace(source, '''		setup_calls += 1
		result = backend.call("loads", state, velocity, d, model, thrust_torque, rho, fade,
			resolved_downwash, transported_dv)''', '''		setup_calls += 1
		profile_routes["setup"] = int(profile_routes["setup"]) + 1
		result = backend.call("loads", state, velocity, d, model, thrust_torque, rho, fade,
			resolved_downwash, transported_dv)''')
    return replace(source, '''		prepared_calls += 1
		result = backend.call("loads_prepared", state, velocity, d, prepared_token, thrust_torque, rho, fade,
			resolved_downwash, transported_dv)''', '''		prepared_calls += 1
		profile_routes["prepared"] = int(profile_routes["prepared"]) + 1
		result = backend.call("loads_prepared", state, velocity, d, prepared_token, thrust_torque, rho, fade,
			resolved_downwash, transported_dv)''')


def profile_source(backend: str) -> str:
    source = (HERE.parent / "stage-sharing/probe.gd").read_text(encoding="utf-8")
    source = source.replace("res://tests/stage_sharing/dynamics.gd",
                            "res://tests/wing_loops/candidate/dynamics.gd")
    source = source.replace("res://tests/stage_sharing/flight_session.gd",
                            "res://tests/wing_loops/candidate/flight_session.gd")
    source = replace(source, 'const WashTransport: Script = preload("res://physics/wash_transport.gd")',
        'const WashTransport: Script = preload("res://physics/wash_transport.gd")\n'
        'const CandidateWashTransport: Script = preload("res://tests/wing_loops/candidate/wash_transport.gd")')
    source = replace(source,
        'var candidate_ok: bool = _configure_flight(candidate, aircraft_id, regime, smooth_mode)',
        'var candidate_ok: bool = _configure_flight(candidate, aircraft_id, regime, smooth_mode, true)')
    source = replace(source,
        'func _configure_flight(flight: Node, aircraft_id: String, regime: String, smooth_mode: String) -> bool:',
        'func _configure_flight(flight: Node, aircraft_id: String, regime: String, smooth_mode: String, use_candidate: bool = false) -> bool:')
    source = replace(source, 'return _set_smooth_regime(flight, regime)',
        'return _set_smooth_regime(flight, regime, use_candidate)')
    source = replace(source, 'func _set_smooth_regime(flight: Node, regime: String) -> bool:',
        'func _set_smooth_regime(flight: Node, regime: String, use_candidate: bool = false) -> bool:')
    source = replace(source,
        'flight.sim.continuous = WashTransport.settled(air.v_air, maximum_rpm, model.propulsion, Air.RHO_SEA_LEVEL)',
        'flight.sim.continuous = CandidateWashTransport.settled(air.v_air, maximum_rpm, model.propulsion, Air.RHO_SEA_LEVEL) if use_candidate else WashTransport.settled(air.v_air, maximum_rpm, model.propulsion, Air.RHO_SEA_LEVEL)')
    if backend == "prepared":
        source = source.replace('res://physics/dynamics.gd', 'res://tests/wing_loops/baseline/dynamics.gd')
        source = source.replace('res://sim/flight_session.gd', 'res://tests/wing_loops/baseline/flight_session.gd')
        source = replace(source, 'extends SceneTree', '''extends SceneTree
const BasePrepared: Script = preload("res://tests/wing_loops/baseline_adapter.gd")
const CandidatePrepared: Script = preload("res://tests/wing_loops/candidate_adapter.gd")

var _prepared_measured_routes: Dictionary = {
	"baseline": {"prepared": 0, "setup": 0, "refused": 0},
	"candidate": {"prepared": 0, "setup": 0, "refused": 0},
}
var _prepared_route_rows: Array[Dictionary] = []''')
        source = replace(source, 'func _append_direct_case(fixture: Dictionary) -> void:', '''func _append_direct_case(fixture: Dictionary) -> void:
	if not BasePrepared.prepare(fixture.model) or not CandidatePrepared.prepare(fixture.model):
		_fail(fixture.label + " direct preparation failed")
		return
	BasePrepared.reset_profile_routes()
	CandidatePrepared.reset_profile_routes()''')
        source = replace(source, 'var baseline: Node = BaseFlight.new()', '''BasePrepared.begin_setup()
	CandidatePrepared.begin_setup()
	var baseline: Node = BaseFlight.new()''')
        source = replace(source, 'if not baseline_ok or not candidate_ok:', '''if baseline_ok and candidate_ok:
		baseline_ok = BasePrepared.prepare(baseline.aircraft.model)
		candidate_ok = CandidatePrepared.prepare(candidate.aircraft.model)
	if not baseline_ok or not candidate_ok:''')
        source = replace(source, '\t_direct_rows.append({', '''\t_capture_prepared_routes(fixture.label)
\t_direct_rows.append({''')
        source = replace(source, '\tvar fixture_equal: bool = _compare_boundary(label + \" initial\", baseline.sim, candidate.sim,',
            '''\tBasePrepared.reset_profile_routes()
\tCandidatePrepared.reset_profile_routes()
\tvar fixture_equal: bool = _compare_boundary(label + \" initial\", baseline.sim, candidate.sim,''')
        source = replace(source, '\tbaseline.free()\n\tcandidate.free()', '''\t_capture_prepared_routes(label)
\tbaseline.free()
\tcandidate.free()''')
        source = replace(source,
            '"backend_routes": routes,', '''"backend_routes": routes,
		"prepared_protocol": {
			"baseline": {"attempts": BasePrepared.preparation_attempts, "prepared_calls": BasePrepared.prepared_calls,
				"setup_calls": BasePrepared.setup_calls, "setup_mode_at_end": BasePrepared.setup_mode},
			"candidate": {"attempts": CandidatePrepared.preparation_attempts, "prepared_calls": CandidatePrepared.prepared_calls,
				"setup_calls": CandidatePrepared.setup_calls, "setup_mode_at_end": CandidatePrepared.setup_mode},
			"measured_routes": _prepared_measured_routes,
			"measured_route_rows": _prepared_route_rows,
		},''')
        source = replace(source, 'func _write_report() -> void:', '''func _capture_prepared_routes(label: String) -> void:
	for entry: Array in [["baseline", BasePrepared], ["candidate", CandidatePrepared]]:
		var route: Dictionary = entry[1].profile_routes
		var summary: Dictionary = _prepared_measured_routes[entry[0]]
		for key: String in ["prepared", "setup", "refused"]:
			summary[key] = int(summary[key]) + int(route.get(key, 0))
		if int(route.get("setup", 0)) != 0 or int(route.get("refused", 0)) != 0:
			_fail(label + " measured prepared route failed: " + str(route))
	var baseline_route: Dictionary = BasePrepared.profile_routes.duplicate()
	var candidate_route: Dictionary = CandidatePrepared.profile_routes.duplicate()
	if baseline_route != candidate_route:
		_fail(label + " baseline/candidate adapter routes differ")
	_prepared_route_rows.append({"case": label, "baseline": baseline_route, "candidate": candidate_route})


func _write_report() -> void:''')
    return source


def run_godot(godot: str, app: Path, script: Path, output: Path, timeout: int = 1200) -> None:
    command = [godot, "--headless", "--path", str(app), "--script", str(script), "--", str(output)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    combined = result.stdout + result.stderr
    output.with_suffix(".log").write_text(combined, encoding="utf-8")
    if result.returncode != 0 or native.ERROR_RE.search(combined):
        raise RuntimeError(f"Godot run failed ({result.returncode}): {script}\n{combined[-5000:]}")
    if not output.is_file():
        raise RuntimeError(f"Godot exited without writing report: {output}")


def validate_profile(report: dict, backend: str, check_negative_controls: bool = True) -> dict:
    summary = sharing.summarize(report)
    if report.get("timing", {}).get("direct_calls_per_pair") != 64:
        raise RuntimeError("The paired direct-load workload must use 64 calls per sample")
    if report.get("timing", {}).get("flight_ticks_per_pair") != 24:
        raise RuntimeError("The paired flight workload must use 24 ticks per sample")
    for row in report.get("direct_rows", []):
        if row.get("calls_per_sample") != 64 or row.get("exact_calls") != 64:
            raise RuntimeError(f"Wrong direct workload for {row.get('case')}")
    for row in report.get("flight_rows", []):
        if row.get("timing_ticks_per_sample") != 24:
            raise RuntimeError(f"Wrong flight workload for {row.get('case')}")
    negative_controls = sharing.check_comparator(report) if check_negative_controls else []
    prepared_summary = None
    if backend == "prepared":
        protocol = report.get("prepared_protocol", {})
        if set(protocol) != {"baseline", "candidate", "measured_routes", "measured_route_rows"}:
            raise RuntimeError("Prepared adapter protocol report is incomplete")
        for name in ("baseline", "candidate"):
            item = protocol[name]
            if item.get("attempts") != 49 or item.get("setup_mode_at_end") is not False:
                raise RuntimeError(f"Unexpected {name} preparation lifecycle: {item}")
        measured = protocol["measured_routes"]
        expected_route_keys = {"prepared", "setup", "refused"}
        if set(measured) != {"baseline", "candidate"} or any(
                set(measured[name]) != expected_route_keys or
                any(type(measured[name][key]) is not int or measured[name][key] < 0 for key in expected_route_keys)
                for name in ("baseline", "candidate")):
            raise RuntimeError("Measured route totals have invalid fields or values")
        for name in ("baseline", "candidate"):
            route = measured.get(name, {})
            if route.get("setup") != 0 or route.get("refused") != 0 or route.get("prepared", 0) <= 0:
                raise RuntimeError(f"Measured {name} loads bypassed the prepared route: {route}")
        expected_routes = [row["case"] for row in report["direct_rows"] + report["flight_rows"]]
        route_rows = protocol.get("measured_route_rows", [])
        if [row.get("case") for row in route_rows] != expected_routes:
            raise RuntimeError("Prepared-route detail does not match the strict profile roster")
        totals = {name: {"prepared": 0, "setup": 0, "refused": 0} for name in ("baseline", "candidate")}
        for row in route_rows:
            row_routes = []
            for name in ("baseline", "candidate"):
                route = row.get(name, {})
                if set(route) != expected_route_keys:
                    raise RuntimeError(f"Measured route fields changed in {row.get('case')}: {route}")
                if any(type(route.get(key)) is not int or route[key] < 0 for key in totals[name]):
                    raise RuntimeError(f"Invalid measured route counts in {row.get('case')}: {route}")
                if route.get("setup") != 0 or route.get("refused") != 0:
                    raise RuntimeError(f"Measured prepared route refused/fell back in {row.get('case')}: {route}")
                for key in totals[name]:
                    totals[name][key] += int(route.get(key, 0))
                label = row.get("case", "")
                active = any(label.startswith("smooth:" + regime + ":") for regime in
                             ("forward", "stall", "static", "spin", "reverse_fade"))
                if active and route["prepared"] <= 0:
                    raise RuntimeError(f"Active smooth case skipped prepared dispatch: {label}")
                row_routes.append(route)
            if row_routes[0] != row_routes[1]:
                raise RuntimeError(f"Baseline/candidate adapter routes differ in {row.get('case')}")
        if totals != measured:
            raise RuntimeError("Prepared route totals differ from measured per-case routes")
        prepared_summary = {name: protocol[name] for name in ("baseline", "candidate")}
    if check_negative_controls:
        controls = {
            "direct_workload_changed": lambda item: item["timing"].__setitem__("direct_calls_per_pair", 63),
            "flight_workload_changed": lambda item: item["timing"].__setitem__("flight_ticks_per_pair", 23),
            "profile_row_missing": lambda item: item["flight_rows"].pop(),
        }
        if backend == "prepared":
            controls.update({
                "measured_setup_fallback": lambda item: item["prepared_protocol"]["measured_route_rows"][0]["baseline"].__setitem__("setup", 1),
                "measured_refusal": lambda item: item["prepared_protocol"]["measured_route_rows"][0]["candidate"].__setitem__("refused", 1),
                "prepared_route_missing": lambda item: item["prepared_protocol"]["measured_route_rows"].pop(),
            })
        for name, mutate in controls.items():
            changed = copy.deepcopy(report)
            mutate(changed)
            try:
                validate_profile(changed, backend, check_negative_controls=False)
            except RuntimeError:
                negative_controls.append(name)
            else:
                raise RuntimeError(f"Profile validator accepted negative control {name}")
    return {"timing_summary": summary, "negative_controls_rejected": negative_controls,
            "prepared_protocol": prepared_summary}



def check_mutations(godot: str, app: Path, output: Path) -> list[dict]:
    """Perturb the candidate only, after timing; require complete assertion failures."""
    path = app / "tests/wing_loops/aero.gd"
    original = path.read_text()
    mutants = {
        "shifted_map_column": original.replace("e_map[row_start + k]", "e_map[(row_start + k + 1) % e_map.size()]"),
        "reversed_left_aileron": replace(original, "var da_left: float = float(d.aileron_left)",
                                         "var da_left: float = -float(d.aileron_left)"),
    }
    result = []
    try:
        for name, source in mutants.items():
            if source == original:
                raise RuntimeError("Mutation did not change the candidate")
            path.write_text(source)
            report_path = output / ("mutation-" + name + ".json")
            try:
                run_godot(godot, app, app / "tests/wing_loops/verify.gd", report_path, timeout=300)
            except RuntimeError:
                if not report_path.is_file() or native.ERROR_RE.search(report_path.with_suffix(".log").read_text()):
                    raise
                report = native._read_json(report_path)
                if (type(report.get("failures")) is not int or report["failures"] <= 0
                        or report.get("comparisons") != 5120 or report.get("scalars") != 25600
                        or report.get("baseline_sha256") == report.get("candidate_sha256")):
                    raise RuntimeError("Mutation did not fail through the full equivalence sweep: " + name)
                result.append({"name": name, "assertion_failures": report["failures"], "rejected": True,
                               "report_sha256": sha256(report_path)})
            else:
                raise RuntimeError("Equivalence checks missed mutation: " + name)
    finally:
        path.write_text(original)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--backend", choices=("gd", "prepared"), default="prepared")
    parser.add_argument("--build", type=Path, default=ROOT / ".tools/native-prepared/build.json")
    parser.add_argument("--baseline-aero", type=Path,
                        help="optional baseline Aero source copied only into the disposable app")
    parser.add_argument("--keep-work", action="store_true")
    args = parser.parse_args()
    project = args.project.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if output.exists():
        raise RuntimeError(f"Use a new output directory for each run: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir()
    candidate_path = HERE / "candidate.py"
    verify_path = HERE / "verify.gd"
    baseline_override = args.baseline_aero.expanduser().resolve() if args.baseline_aero else None
    if not candidate_path.is_file() or not verify_path.is_file():
        raise RuntimeError("candidate.py and verify.gd must sit beside run.py")
    build_manifest = None
    library = None
    manifest = None
    if args.backend == "prepared":
        build_manifest = args.build.expanduser().resolve()
        manifest, library = verify_build_manifest(build_manifest)
    godot = native._resolve_godot(args.godot)
    source_before = build_snapshot(project, candidate_path, verify_path, baseline_override, build_manifest)
    source_aero = baseline_override.read_text(encoding="utf-8") if baseline_override else (project / "physics/aero.gd").read_text(encoding="utf-8")
    candidate_aero = module("wing_loop_candidate", candidate_path).candidate_source(source_aero)
    if candidate_aero == source_aero:
        raise RuntimeError("candidate_source produced no change")
    write_diff(source_aero, candidate_aero, output, "physics/aero.gd")
    work = Path(tempfile.mkdtemp(prefix="openrc-wing-loops-"))
    app = work / "app"
    evidence = {"format": "openrc-e0b6p-wing-loops-evidence v1", "status": "running",
        "backend": args.backend, "host": platform.platform(), "python": platform.python_version(),
        "godot": godot, "source_revision": native._source_revision(project),
        "source_app_snapshot": app_snapshot(project),
        "input_hashes_before": source_before, "baseline_aero_sha256": sha256(baseline_override) if baseline_override else sha256(project / "physics/aero.gd"),
        "candidate_source_sha256": sha256(candidate_path), "candidate_aero_sha256": hashlib.sha256(candidate_aero.encode()).hexdigest(),
        "candidate_patch": str(output / "candidate.patch"),
        "harness_sha256": {str(path.relative_to(ROOT)): sha256(path) for path in
            [HERE / "run.py", candidate_path, verify_path, HERE.parent / "stage-sharing/probe.gd",
             HERE.parent / "stage-sharing/run.py", HERE.parent / "prepared-model/run.py",
             HERE.parent / "native/run.py", HERE.parent / "native/adapter.gd"]},
        "build_manifest": manifest, "build_manifest_sha256": sha256(build_manifest) if build_manifest else None}
    try:
        native._copy_project(project, app)
        if app_snapshot(app) != evidence["source_app_snapshot"]:
            raise RuntimeError("App inputs changed while staging")
        if baseline_override is not None:
            shutil.copy2(baseline_override, app / "physics/aero.gd")
        probe_paths = stage_variant_scripts(app, candidate_aero, args.backend, library)
        (app / "tests/wing_loops/verify.gd").write_text(verify_path.read_text(encoding="utf-8"), encoding="utf-8")
        profile = profile_source(args.backend)
        (app / "tests/wing_loops/probe.gd").write_text(profile, encoding="utf-8")
        staged_scripts = sorted((app / "tests/wing_loops").rglob("*.gd"))
        staged_scripts += sorted((app / "tests/e0b6p_native").glob("*.gd")) if args.backend == "prepared" else []
        evidence["staged_script_sha256"] = {
            str(path.relative_to(app)): sha256(path) for path in staged_scripts}
        evidence["candidate_patch_sha256"] = sha256(output / "candidate.patch")
        verify_output = output / "verify.json"
        run_godot(godot, app, app / "tests/wing_loops/verify.gd", verify_output, timeout=300)
        verify = native._read_json(verify_output)
        if (verify.get("format") != "openrc-wing-loop-equivalence v1" or verify.get("failures") != 0
                or verify.get("requests") != 1024 or verify.get("comparisons") != 5120
                or verify.get("scalars") != 25600):
            raise RuntimeError(f"Wing-loop verification incomplete or failed: {verify}")
        baseline_hash = verify.get("baseline_sha256")
        candidate_hash = verify.get("candidate_sha256")
        if (not isinstance(baseline_hash, str) or not isinstance(candidate_hash, str)
                or not re.fullmatch(r"[0-9a-f]{64}", baseline_hash)
                or baseline_hash != candidate_hash):
            raise RuntimeError("Wing-loop verification original-buffer hashes differ or are malformed")
        expected_micro = ["wing_lift_coefficient", "local_loads"]
        timing_rows = verify.get("timing", [])
        if [row.get("function") for row in timing_rows] != expected_micro:
            raise RuntimeError("Wing-loop microbenchmark roster changed")
        for row in timing_rows:
            for key in ("baseline_us_per_call", "candidate_us_per_call"):
                values = row.get(key, [])
                if len(values) != 9 or any(not isinstance(value, (int, float)) or
                        not math.isfinite(float(value)) or float(value) <= 0 for value in values):
                    raise RuntimeError(f"Invalid wing-loop timing pairs in {row.get('function')}")
        profile_output = output / "profile.json"
        run_godot(godot, app, app / "tests/wing_loops/probe.gd", profile_output, timeout=2400)
        profile_report = native._read_json(profile_output)
        evidence["profile_validation"] = validate_profile(profile_report, args.backend)
        evidence["verification"] = {key: verify.get(key) for key in
            ("format", "failures", "requests", "comparisons", "scalars", "baseline_sha256", "candidate_sha256", "timing")}
        evidence["report_sha256"] = {"verify": sha256(verify_output), "profile": sha256(profile_output)}
        evidence["profile"] = {"format": profile_report.get("format"), "counts": profile_report.get("counts"),
            "timing": profile_report.get("timing"), "direct_rows": profile_report.get("direct_rows"),
            "flight_rows": profile_report.get("flight_rows"), "prepared_protocol": profile_report.get("prepared_protocol")}
        evidence["staged_paths"] = {name: str(path.relative_to(app)) for name, path in probe_paths.items()}
        evidence["candidate_mutations"] = check_mutations(godot, app, output)
        after = build_snapshot(project, candidate_path, verify_path, baseline_override, build_manifest)
        evidence["input_hashes_after"] = after
        if source_before != after:
            raise RuntimeError("An input changed during the wing-loop run")
        if args.backend == "prepared":
            manifest_after, library_after = verify_build_manifest(build_manifest)
            if manifest_after != manifest or library_after != library:
                raise RuntimeError("The prepared build manifest changed during the run")
            evidence["prepared_library_sha256"] = sha256(library_after)
        if any(sha256(app / name) != digest for name, digest in evidence["staged_script_sha256"].items()):
            raise RuntimeError("Generated scripts changed during measurement")
        evidence["status"] = "pass"
    except Exception as error:
        evidence.update(status="fail", error=str(error))
        raise
    finally:
        if args.keep_work:
            evidence["work"] = str(work)
        else:
            shutil.rmtree(work)
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Wing-loop paired experiment passed: {output / 'evidence.json'}")


if __name__ == "__main__":
    main()
