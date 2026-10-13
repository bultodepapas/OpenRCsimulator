## Bounded timing probe for the legacy Stik and paired glow flight adapters.
## Research diagnostic only: host isolation is not guaranteed and no physical claim follows.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const Life := preload("res://physics/glow/lifecycle.gd")
const Source := preload("res://physics/glow/source.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")

const STEP_TARGET_US := 500.0
const RELEASE_BINARY_RELATIVE := ".tools/rc7-proof/windows-smoke/OpenRC Simulator.exe"
const RELEASE_PACK_RELATIVE := ".tools/glow-package-20261013/nitro02-candidate.pck"
const CASES := [
	{"label": "legacy_stik", "path": "res://data/aircraft/jensen_ugly_stik_60.json", "input": "app/data/aircraft/jensen_ugly_stik_60.json", "glow": false},
	{"label": "glow_2t", "path": "res://data/aircraft/stik_glow_55ax_2t.json", "input": "app/data/aircraft/stik_glow_55ax_2t.json", "glow": true},
	{"label": "glow_4t", "path": "res://data/aircraft/stik_glow_fs64v_4t.json", "input": "app/data/aircraft/stik_glow_fs64v_4t.json", "glow": true},
]
const SOURCE_PATHS := [
	"research/glow-engines/performance_probe.gd",
	"research/glow-engines/release_probe_wrapper.gd",
	"research/glow-engines/release_probe_wrapper.tscn",
	"research/glow-engines/build_release_probe_project.py",
	"app/sim/flight_session.gd",
	"app/sim/simulation.gd",
	"app/physics/glow/flight.gd",
	"app/physics/glow/lifecycle.gd",
	"app/physics/glow/source.gd",
	"app/physics/glow/two_stroke.gd",
	"app/physics/glow/four_stroke.gd",
	"app/physics/glow/thermal.gd",
	"app/physics/glow/profile.gd",
	"app/physics/glow/propeller.gd",
	"app/physics/glow/fuel_mass.gd",
	"app/physics/glow/installation.gd",
	"app/physics/dynamics.gd",
	"app/physics/math3d.gd",
	"app/physics/air_data.gd",
	"app/physics/aero.gd",
	"app/physics/propulsion.gd",
	"app/physics/rotor_coupling.gd",
	"app/physics/electric_battery_step.gd",
	"app/physics/rigid_body.gd",
	"app/physics/ground_contact.gd",
]
const INPUT_PATHS := [
	"app/data/aircraft/jensen_ugly_stik_60.json",
	"app/data/aircraft/stik_glow_55ax_2t.json",
	"app/data/aircraft/stik_glow_fs64v_4t.json",
	"app/data/glow/stik_55ax_2t.json",
	"app/data/glow/stik_fs64v_4t.json",
	"app/data/glow/os_max_55ax_candidate.json",
	"app/data/glow/os_fs_64v_candidate.json",
	"app/data/glow/profile_contract.json",
]

var hz: int = 240
var warmup_ticks: int = 120
var measured_ticks: int = 600
var micro_groups: int = 25
var output_path: String = ""
var runtime_pack_path: String = ""
var repository_root_override: String = ""
var runtime_mode: String = "standalone_script"
var release_manifest: Dictionary = {}
var release_manifest_sha256: String = ""
var _probe_started: bool = false
var report: Dictionary = {}

# Fixed sampled context for microbenchmarks. Reusing this input state isolates each
# pure evaluator; it does not mutate the committed simulation state.
var _owner: Node
var _body: PackedFloat64Array
var _values: PackedFloat64Array
var _time_s: float
var _model: Dictionary
var _install: Dictionary
var _profile: Dictionary
var _state: Dictionary
var _deflections: Dictionary
var _rho: float
var _wind: PackedFloat64Array
var _ground_up: float
var _downwash: float = NAN
var _air: Dictionary
var _source_context: Dictionary
var _axial_speed: float
var _last_result: Variant


func _initialize() -> void:
	if _probe_started:
		return
	_probe_started = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="):
			hz = arg.trim_prefix("--hz=").to_int()
		elif arg.begins_with("--warmup="):
			warmup_ticks = arg.trim_prefix("--warmup=").to_int()
		elif arg.begins_with("--ticks="):
			measured_ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--micro-groups="):
			micro_groups = arg.trim_prefix("--micro-groups=").to_int()
		elif arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--runtime-pack="):
			runtime_pack_path = arg.trim_prefix("--runtime-pack=")
		elif arg.begins_with("--repo-root="):
			repository_root_override = arg.trim_prefix("--repo-root=")
		elif arg.begins_with("--runtime-mode="):
			runtime_mode = arg.trim_prefix("--runtime-mode=")
	if hz not in [120, 240, 480] or warmup_ticks < 0 or measured_ticks < 100 or micro_groups < 5:
		printerr("Invalid probe settings; use --hz=240 --warmup=120 --ticks=600 --micro-groups=25")
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	report = {
		"format": "openrc-glow-performance-probe v1",
		"purpose": "diagnostic interpreter timing; not a release qualification or physical validation",
		"godot": Engine.get_version_info(),
		"host": {
			"os": OS.get_name(),
			"processor": OS.get_processor_name(),
			"logical_processors": OS.get_processor_count(),
			"isolation": "best effort only; two long-lived Godot sessions were observed at preflight (repository climb-trim watch and unrelated Corruption app) and neither was stopped",
		},
		"runtime": {
			"probe_mode": runtime_mode,
			"binary_path": OS.get_executable_path(),
			"binary_sha256": _sha256_file(OS.get_executable_path()),
			"debug_feature": OS.has_feature("debug"),
			"release_feature": OS.has_feature("release"),
			"main_pack_path": "embedded in executable" if runtime_pack_path == "embedded" else runtime_pack_path,
			"main_pack_sha256": "embedded_in_executable; see binary_sha256" if runtime_pack_path == "embedded" else (_sha256_file(runtime_pack_path) if not runtime_pack_path.is_empty() else "not_supplied"),
		},
		"prior_release_override_attempt": {
			"binary_path": RELEASE_BINARY_RELATIVE,
			"binary_sha256": _sha256_file(_repo_path(RELEASE_BINARY_RELATIVE)),
			"pack_path": RELEASE_PACK_RELATIVE,
			"pack_sha256": _sha256_file(_repo_path(RELEASE_PACK_RELATIVE)),
			"feature_flags": "unavailable; external probe could not execute in release runtime",
			"probe_status": "blocked: --main-pack aborts because path overrides were disabled at Godot build time; --script alone did not execute the external probe",
			"observed_release_errors": [
				"--main-pack: Godot binary compiled without support for path overrides",
				"--script alone: release application parsed --warmup as its own option and required --frametimes",
			],
		},
		"started_at_local": Time.get_datetime_string_from_system(true, true),
		"hash_scope": String(release_manifest.get("hash_scope", "working_tree_at_probe_start")),
		"release_manifest_sha256": release_manifest_sha256 if not release_manifest_sha256.is_empty() else "not_embedded",
		"release_manifest_provenance": String(release_manifest.get("provenance", "Hashes read directly from repository files at probe start.")),
		"source_hashes": release_manifest.get("source_hashes", _hash_paths(SOURCE_PATHS)),
		"input_hashes": release_manifest.get("input_hashes", _hash_paths(INPUT_PATHS)),
		"build_configuration_hashes": release_manifest.get("build_configuration_hashes", {}),
		"propeller_inertia_basis": "Candidate propeller polar inertia follows the inventory's uniform-box surrogate geometry; engine crank polar inertia is inferred (2e-5 kg m2 for the 2T, 3e-5 kg m2 for the 4T). These are estimated mass distributions and inferred terms, with no matched propeller/crank inertia measurements.",
		"configuration": {
			"physics_hz": hz,
			"warmup_ticks": warmup_ticks,
			"measured_ticks_per_case": measured_ticks,
			"counterbalanced_rounds": 2,
			"microprofile_groups": micro_groups,
			"full_step_budget_us": STEP_TARGET_US,
			"step_timing": "Time.get_ticks_usec around each manual Simulation.step(); p50/p95/max of individual ticks",
			"micro_timing": "median/p95/max of batch mean per-call times; callable-dispatch no-op measured separately",
			"flight_state": "trimmed airborne steady scenario at each aircraft's default launch state; neutral controls",
		},
		"cases": [],
	}
	report["source_tree_sha256"] = String(release_manifest.get("source_tree_sha256", _combined_hash(report.source_hashes)))
	report["input_tree_sha256"] = String(release_manifest.get("input_tree_sha256", _combined_hash(report.input_hashes)))
	var ordered_cases: Array[Dictionary] = []
	for case: Dictionary in CASES:
		var first: Dictionary = case.duplicate(true)
		first["round"] = 1
		ordered_cases.append(first)
	for index in range(CASES.size() - 1, -1, -1):
		var second: Dictionary = CASES[index].duplicate(true)
		second["round"] = 2
		ordered_cases.append(second)
	for case: Dictionary in ordered_cases:
		var result: Dictionary = _measure_case(case)
		if not result.get("ok", false):
			printerr("Performance probe failed: ", case.label, " ", result.get("message", "unknown"))
			quit(1)
			return
		report.cases.append(result)
	report["summary"] = _aggregate_runs(report.cases)
	var serialized: String = JSON.stringify(report, "\t", true, true) + "\n"
	if not output_path.is_empty():
		var output_file := FileAccess.open(output_path, FileAccess.WRITE)
		if output_file == null:
			printerr("Could not open report output: ", output_path)
			quit(3)
			return
		output_file.store_string(serialized)
		output_file.close()
		print("Wrote performance report: ", output_path)
	for spec: Dictionary in CASES:
		var result: Dictionary = report.summary[spec.label]
		print("SUMMARY ", spec.label, " rounds=", result.rounds,
			" step_p50_median_us=", result.median_of_round_step_p50_us,
			" step_p95_median_us=", result.median_of_round_step_p95_us,
			" step_p95_worst_us=", result.worst_round_step_p95_us,
			" ratio_to_500us=", result.median_of_round_step_p95_us / STEP_TARGET_US)
	quit(0)


func _measure_case(spec: Dictionary) -> Dictionary:
	var flight := Session.new()
	flight.setup(String(spec.path))
	flight.input_enabled = false
	if not flight.is_flyable() or flight.sim == null:
		flight.free()
		return {"ok": false, "message": "aircraft did not reach a flyable setup"}
	for _tick in warmup_ticks:
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			var warm_fault: String = flight.sim.fault_reason
			flight.free()
			return {"ok": false, "message": "fault during warmup: " + warm_fault}
	var costs: Array[float] = []
	for _tick in measured_ticks:
		var started: int = Time.get_ticks_usec()
		flight.sim.step()
		costs.append(float(Time.get_ticks_usec() - started))
		if not flight.sim.fault_reason.is_empty():
			var fault: String = flight.sim.fault_reason
			flight.free()
			return {"ok": false, "message": "fault during measurement: " + fault}
	costs.sort()
	var step_stats := _stats(costs)
	var result: Dictionary = {
		"ok": true,
		"case": String(spec.label),
		"round": int(spec.round),
		"aircraft_id": String(flight.aircraft.model.id),
		"aircraft_input": String(spec.input),
		"aircraft_input_sha256": String(report.input_hashes.get(String(spec.input), "missing")),
		"glow_active": bool(flight.glow_is_active()),
		"shaft_integrator": flight.shaft_integrator(),
		"start_time_s": flight.sim.time() - float(measured_ticks) / float(hz),
		"step_cost_us": step_stats,
		"step_p95_to_500us_budget_ratio": step_stats.p95 / STEP_TARGET_US,
	}
	if bool(spec.glow):
		_context_from_flight(flight)
		result["microprofile"] = _microprofile_glow()
	else:
		_context_from_flight(flight)
		result["microprofile"] = {"dynamics_loads": _measure(Callable(self, "_micro_dynamics_loads"), 24)}
	flight.free()
	return result


func _context_from_flight(flight: Node) -> void:
	_owner = flight
	_body = flight.sim.state.duplicate()
	_values = flight.sim.continuous.duplicate()
	_time_s = flight.sim.time()
	_model = flight.aircraft.model
	_rho = flight.air_density()
	_wind = flight.wind_at(_time_s)
	_deflections = flight._deflections(flight.sim.aux)
	_ground_up = flight._ground_up(_body)
	var lag_index: int = flight.downwash_index()
	_downwash = flight.sim.aux[lag_index] if lag_index >= 0 else NAN
	_air = flight.air_data(_body, _time_s)
	_install = _model.propulsion.get("glow", {})
	if _install.is_empty():
		_profile = {}
		_state = {}
		_source_context = {}
		_axial_speed = 0.0
	else:
		_profile = _install.profile
		_state = GlowFlight.unpack(_values, _install)
		_source_context = {
			"rpm": maxf(0.0, _values[0]),
			"admission": float(_values[4]),
			"mixture": float(_values[12]),
			"density": 1.225 * float(flight.engine_charge_ratio()),
			"running": bool(flight.engine_running),
		}
		_axial_speed = M.dot(_air.v_air, _model.propulsion.axis)


func _microprofile_glow() -> Dictionary:
	var tests: Array[Dictionary] = [
		{"name": "flight_evaluate", "method": "_micro_flight_evaluate", "calls_per_group": 4},
		{"name": "flight_point", "method": "_micro_flight_point", "calls_per_group": 12},
		{"name": "lifecycle_evaluate", "method": "_micro_lifecycle_evaluate", "calls_per_group": 24},
		{"name": "source_evaluate", "method": "_micro_source_evaluate", "calls_per_group": 48},
		{"name": "blade_evaluate", "method": "_micro_blade_evaluate", "calls_per_group": 96},
		{"name": "fuel_mass_evaluate", "method": "_micro_fuel_mass_evaluate", "calls_per_group": 48},
		{"name": "dynamics_loads", "method": "_micro_dynamics_loads", "calls_per_group": 24},
	]
	var noop := _measure(Callable(self, "_micro_noop"), 96)
	var output: Dictionary = {"callable_dispatch_noop": noop, "results": {}}
	for test: Dictionary in tests:
		var gross: Dictionary = _measure(Callable(self, String(test.method)), int(test.calls_per_group))
		gross["median_kernel_estimate_us"] = maxf(0.0, gross.p50 - noop.p50)
		gross["dispatch_adjustment_note"] = "gross minus the measured no-op callable median; approximate only"
		output.results[test.name] = gross
	return output


func _measure(callback: Callable, calls_per_group: int) -> Dictionary:
	for _warm in 5:
		callback.call()
	var group_means: Array[float] = []
	for _group in micro_groups:
		var started: int = Time.get_ticks_usec()
		for _call in calls_per_group:
			_last_result = callback.call()
		var elapsed: float = float(Time.get_ticks_usec() - started)
		group_means.append(elapsed / float(calls_per_group))
	group_means.sort()
	var stats := _stats(group_means)
	stats["calls_per_group"] = calls_per_group
	stats["groups"] = micro_groups
	return stats


func _stats(sorted_values: Array[float]) -> Dictionary:
	var n: int = sorted_values.size()
	return {
		"p50": sorted_values[int(floor(float(n - 1) * 0.50))],
		"p95": sorted_values[int(floor(float(n - 1) * 0.95))],
		"maximum": sorted_values[n - 1],
	}


func _aggregate_runs(runs: Array) -> Dictionary:
	var output: Dictionary = {}
	for spec: Dictionary in CASES:
		var matching: Array[Dictionary] = []
		for run: Dictionary in runs:
			if run.case == spec.label:
				matching.append(run)
		var p50s: Array[float] = []
		var p95s: Array[float] = []
		for run: Dictionary in matching:
			p50s.append(float(run.step_cost_us.p50))
			p95s.append(float(run.step_cost_us.p95))
		p50s.sort()
		p95s.sort()
		var summary: Dictionary = {
			"rounds": matching.size(),
			"median_of_round_step_p50_us": _median(p50s),
			"median_of_round_step_p95_us": _median(p95s),
			"worst_round_step_p95_us": p95s[-1],
			"round_step_p95_us": p95s,
		}
		if bool(spec.glow):
			var micro_names: Array[String] = ["flight_evaluate", "flight_point", "lifecycle_evaluate", "source_evaluate", "blade_evaluate", "fuel_mass_evaluate", "dynamics_loads"]
			var micro_summary: Dictionary = {}
			for name: String in micro_names:
				var values: Array[float] = []
				for run: Dictionary in matching:
					values.append(float(run.microprofile.results[name].p50))
				values.sort()
				micro_summary[name] = {"median_of_round_us_per_call": _median(values), "round_p50_us_per_call": values}
			summary["microprofile"] = micro_summary
		else:
			var dynamics: Array[float] = []
			for run: Dictionary in matching:
				dynamics.append(float(run.microprofile.dynamics_loads.p50))
			dynamics.sort()
			summary["microprofile"] = {"dynamics_loads": {"median_of_round_us_per_call": _median(dynamics), "round_p50_us_per_call": dynamics}}
		output[spec.label] = summary
	return output


func _median(sorted_values: Array[float]) -> float:
	var n: int = sorted_values.size()
	if n % 2 == 1:
		return sorted_values[n / 2]
	return 0.5 * (sorted_values[n / 2 - 1] + sorted_values[n / 2])


func _hash_paths(paths: Array) -> Dictionary:
	var output: Dictionary = {}
	for relative_path: String in paths:
		output[relative_path] = _sha256_file(_repo_path(relative_path))
	return output


func _repo_path(relative_path: String) -> String:
	var root: String = repository_root_override
	if root.is_empty():
		root = ProjectSettings.globalize_path("res://..").simplify_path()
	return root.path_join(relative_path)


func _sha256_file(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return "missing_or_empty"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unreadable"
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		var bytes: PackedByteArray = file.get_buffer(1048576)
		if not bytes.is_empty():
			context.update(bytes)
	file.close()
	return context.finish().hex_encode()


func _combined_hash(hashes: Dictionary) -> String:
	var paths: Array = hashes.keys()
	paths.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path: String in paths:
		context.update(path.to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(String(hashes[path]).to_utf8_buffer())
		context.update(PackedByteArray([0]))
	return context.finish().hex_encode()


func _micro_noop() -> bool:
	return true


func _micro_flight_evaluate() -> Dictionary:
	return GlowFlight.evaluate(_body, _values, _time_s, _owner)


func _micro_flight_point() -> Dictionary:
	return GlowFlight.point(_owner, _body, _values, _time_s)


func _micro_lifecycle_evaluate() -> Dictionary:
	return Life.evaluate(_install.profile, _install.settings, _state, _source_context.rpm,
		float(_owner.sim.inputs[3]), _source_context.mixture, _source_context.density,
		float(_owner.atmosphere_configuration().get("temperature_k", 288.15)), M.norm(_air.v_air))


func _micro_source_evaluate() -> Dictionary:
	return Source.evaluate(_profile, _source_context.rpm, _source_context.admission,
		_source_context.mixture, _source_context.density, _source_context.running, 1.0)


func _micro_blade_evaluate() -> Dictionary:
	return Blade.evaluate(_source_context.rpm, _axial_speed, _rho, _install.propeller)


func _micro_fuel_mass_evaluate() -> Dictionary:
	return FuelMass.evaluate(_model.mass_kg, _model.inertia, _install.initial_fuel_kg,
		maxf(0.0, _values[1]), _install.tank_position, _install.tank_size)


func _micro_dynamics_loads() -> PackedFloat64Array:
	return Dynamics.loads(_body, _model, _deflections, maxf(0.0, _values[0]), _rho, _wind,
		_downwash, PackedFloat64Array(), _ground_up)
