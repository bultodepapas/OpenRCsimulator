extends SceneTree

const Experiments := preload("res://workshop/experiments.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Compiler := preload("res://workshop/compiler.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var base_value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var base: Dictionary = base_value if base_value is Dictionary else {}
	_check("default aircraft fixture loaded", not base.is_empty())
	if base.is_empty():
		quit(1)
		return
	_test_static_report(base)
	_test_sweeps(base)
	var frozen: Dictionary = Trial.freeze({"base_id": Catalog.DEFAULT_ID, "base_bytes": bytes, "recipe": {}})
	_check("frozen Trial is available for the tape experiment", frozen.get("ok", false), str(frozen.get("errors", [])))
	if frozen.get("ok", false):
		_test_recipe_and_fixed_tape(frozen)
	_test_catalog_fixed_tape()
	print("Workshop experiments: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_static_report(base: Dictionary) -> void:
	var report: Dictionary = Experiments.static_report(base, {})
	_check("no-op static report compiles", report.get("ok", false), str(report.get("errors", [])))
	if report.get("ok", false):
		_check("static outputs are explicitly separated from flight performance",
			report.get("scope", "") == "bounded_static_estimate"
			and not report.get("metrics", {}).has("climb_mps")
			and not report.get("metrics", {}).has("endurance_s")
			and not str(report.get("limits", [])).is_empty())
		_check("static report only exposes existing compiler outputs",
			report.get("compiled_build_summary", {}).get("mass_kg", 0.0) > 0.0
			and (not report.get("available", false) or report.get("metrics", {}).has("static_thrust_n"))
			and report.get("compiler_version", "") == Compiler.COMPILER_VERSION)
	var rejected: Dictionary = Experiments.static_report(base, {"scale": 2.01})
	_check("static report rejects recipes beyond physical bounds", not rejected.get("ok", false)
		and str(rejected.get("errors", [])).contains("scale"))
	var visual: Dictionary = Experiments.static_report(base, {"paint": []})
	_check("sweeps and static reports reject visual-only keys", not visual.get("ok", false))


func _test_sweeps(base: Dictionary) -> void:
	var grid: Dictionary = {"format": Experiments.SWEEP_FORMAT, "version": 1, "mode": "grid",
		"recipe": {}, "axes": [
			{"key": "scale", "values": [0.75, 1.0]},
			{"key": "weight_multiplier", "values": [0.9, 1.0]},
		]}
	var first: Dictionary = Experiments.sweep(base, grid)
	var again: Dictionary = Experiments.sweep(base, grid)
	_check("bounded four-case grid evaluates", first.get("ok", false) and first.get("candidate_count", 0) == 4,
		str(first.get("errors", [])))
	_check("grid candidate identities and results are deterministic", first.get("ok", false)
		and again.get("ok", false) and first.candidates == again.candidates)
	if first.get("ok", false):
		_check("static sweep candidates are clearly identified as estimates",
			first.candidates.all(func(item: Variant) -> bool:
				return item is Dictionary and item.get("static_report", {}).get("scope", "") == "bounded_static_estimate"))
	var discovery: Dictionary = {"format": Experiments.SWEEP_FORMAT, "version": 1, "mode": "seeded_discovery",
		"seed": 12345, "candidate_count": 8, "recipe": {}, "axes": [
			{"key": "scale", "minimum": 0.6, "maximum": 1.5},
		]}
	var discovered: Dictionary = Experiments.sweep(base, discovery)
	var repeated: Dictionary = Experiments.sweep(base, discovery)
	_check("seeded discovery evaluates a bounded local candidate set", discovered.get("ok", false)
		and discovered.get("candidate_count", 0) == 8, str(discovered.get("errors", [])))
	_check("same discovery seed repeats exact candidates", discovered.get("ok", false)
		and repeated.get("ok", false) and discovered.candidates == repeated.candidates)
	discovery.seed = 12346
	var another: Dictionary = Experiments.sweep(base, discovery)
	_check("different discovery seed changes candidates", discovered.get("ok", false)
		and another.get("ok", false) and discovered.candidates != another.candidates)
	var too_many: Dictionary = grid.duplicate(true)
	too_many.axes = [
		{"key": "scale", "values": [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 1.1]},
		{"key": "weight_multiplier", "values": [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 1.1]},
	]
	_check("Cartesian grid above 32 candidates rejects before compilation",
		not Experiments.validate_sweep(too_many).get("ok", false))
	var bad_axis: Dictionary = grid.duplicate(true)
	bad_axis.axes[0].key = "paint"
	_check("unknown visual sweep axis rejects", not Experiments.validate_sweep(bad_axis).get("ok", false))
	var duplicate_axis: Dictionary = grid.duplicate(true)
	duplicate_axis.axes.append({"key": "scale", "values": [1.25]})
	_check("duplicate sweep axes reject", not Experiments.validate_sweep(duplicate_axis).get("ok", false))
	var unsupported: Dictionary = {"format": Experiments.SWEEP_FORMAT, "version": 1, "mode": "seeded_discovery",
		"seed": true, "candidate_count": 4, "axes": [{"key": "mass_policy", "minimum": 0, "maximum": 1}]}
	_check("boolean seed and categorical random axis reject", not Experiments.validate_sweep(unsupported).get("ok", false))
	var out_of_range: Dictionary = grid.duplicate(true)
	out_of_range.axes[0].values[0] = 0.49
	_check("sweep candidates cannot exceed shared parameter bounds", not Experiments.validate_sweep(out_of_range).get("ok", false))
	var malformed: Dictionary = grid.duplicate(true)
	malformed.unregistered = true
	_check("unknown sweep keys reject", not Experiments.validate_sweep(malformed).get("ok", false))


func _test_recipe_and_fixed_tape(frozen: Dictionary) -> void:
	var recipe: Dictionary = _flight_recipe(120)
	var validated: Dictionary = Experiments.validate_recipe(recipe)
	_check("bounded level experiment recipe validates", validated.get("ok", false), str(validated.get("errors", [])))
	if validated.get("ok", false):
		_check("canonical tape freezes validated weather and exact tick span",
			validated.recipe.environment.weather == WindConfig.defaults()
			and validated.recipe.termination.ticks == 120
			and validated.recipe.segments.size() == 1)
	var bad: Dictionary = recipe.duplicate(true)
	bad.extra = "not allowed"
	_check("unknown experiment fields reject", not Experiments.validate_recipe(bad).get("ok", false))
	bad = recipe.duplicate(true)
	bad.termination.ticks = true
	_check("boolean tick count rejects", not Experiments.validate_recipe(bad).get("ok", false))
	bad = recipe.duplicate(true)
	bad.segments[0].inputs[0] = 1.01
	_check("out-of-domain post-shaping solver input rejects", not Experiments.validate_recipe(bad).get("ok", false))
	bad = recipe.duplicate(true)
	bad.segments[0].extra = 0
	_check("unknown tape segment fields reject", not Experiments.validate_recipe(bad).get("ok", false))
	bad = recipe.duplicate(true)
	bad.segments[0].inputs = [0, 0, 0, 0, 0]
	_check("v1 tape accepts exactly four known post-shaping axes", not Experiments.validate_recipe(bad).get("ok", false))
	bad = recipe.duplicate(true)
	bad.termination.ticks = Experiments.MAX_EXPERIMENT_TICKS + 1
	bad.segments[0].ticks = Experiments.MAX_EXPERIMENT_TICKS + 1
	_check("run above 120 seconds rejects", not Experiments.validate_recipe(bad).get("ok", false))
	bad = recipe.duplicate(true)
	bad.start.mode = "glide"
	_check("unpowered glide refuses a nonzero throttle tape", not Experiments.validate_recipe(bad).get("ok", false))
	bad = recipe.duplicate(true)
	bad.environment.weather.unrecognized = 1
	_check("weather remains governed by closed shared WindConfig", not Experiments.validate_recipe(bad).get("ok", false))
	var frozen_copy: Dictionary = frozen.duplicate(true)
	var corrupted_bytes: PackedByteArray = frozen_copy.raw_bytes.duplicate()
	corrupted_bytes[0] = corrupted_bytes[0] ^ 1
	frozen_copy.raw_bytes = corrupted_bytes
	_check("fixed-tape run refuses frozen Trial bytes with a stale physical hash",
		not Experiments.run_fixed_tape(frozen_copy, recipe).get("ok", false))
	var first: Dictionary = Experiments.run_fixed_tape(frozen, recipe)
	_check("fixed-tape level experiment starts from the frozen Trial", first.get("ok", false),
		str(first.get("errors", [])))
	if first.get("ok", false):
		var result: Dictionary = first.result
		_check("result binds physical identity, exact start checkpoint, weather and tape",
			result.get("format", "") == Experiments.RESULT_FORMAT
			and result.get("trial_identity", {}).get("trial_id", "") == frozen.identity.trial_id
			and str(result.get("initial_checkpoint", "")).length() > 0
			and str(result.get("initial_checkpoint_sha256", "")).length() == 64
			and result.get("environment", {}).get("identity", {}).get("gravity", 0.0) == 9.80665
			and str(result.get("input_tape_sha256", "")).length() == 64
			and result.get("tick_rate_hz", 0) == 240
			and is_equal_approx(float(result.get("dt_s", 0.0)), 1.0 / 240.0))
		_check("fixed-tape result pins the existing solver and build identities",
			str(result.get("source_identity", {}).get("solver_sha256", "")).length() == 64
			and result.get("source_identity", {}).get("build", {}).get("source", "") in ["development", "export"]
			and result.get("identity_report", {}).get("solver_sha256", "") == result.source_identity.solver_sha256
			and result.get("identity_report", {}).get("build", {}) == result.source_identity.build)
		_check("solver input and software limitation are explicit",
			str(result.get("input_domain", "")).contains("post-control-shaping")
			and str(result.get("limits", [])).contains("not physical measurements"))
		var replay: Dictionary = Experiments.run_fixed_tape(frozen, recipe)
		_check("same frozen state, environment and tape reproduce identical metrics",
			replay.get("ok", false) and replay.result.get("input_tape_sha256", "") == result.get("input_tape_sha256", "")
			and replay.result.get("initial_checkpoint_sha256", "") == result.get("initial_checkpoint_sha256", "")
			and replay.result.get("metrics", {}) == result.get("metrics", {})
			and replay.result.get("termination", {}) == result.get("termination", {}))
		_check("run stops at the declared tick bound or reports a specific early failure",
			result.get("termination", {}).get("reason", "") in ["tick_limit", "simulation_fault", "ground_contact", "gear_collapse"]
			and result.get("termination", {}).get("actual_ticks", -1) <= 120
			and (result.get("completed", false) or not str(result.get("failure_reason", "")).is_empty()))
		var glide_recipe: Dictionary = _flight_recipe(120)
		glide_recipe.start.mode = "glide"
		glide_recipe.segments[0].inputs[3] = 0.0
		var glide: Dictionary = Experiments.run_fixed_tape(frozen, glide_recipe)
		_check("unpowered glide start executes through the same bounded fixed-tape runner",
			glide.get("ok", false) and glide.result.start.mode == "glide"
			and (glide.result.completed or not str(glide.result.failure_reason).is_empty()), str(glide.get("errors", [])))
		if glide.get("ok", false):
			var glide_off: bool = _checkpoint_engine_off(str(glide.result.get("initial_checkpoint", "")))
			var accepted_start: Dictionary = glide.result.get("accepted_start", {})
			_check("accepted glide checkpoint and source sampler both show propulsion off",
				glide_off and not accepted_start.get("engine_running", true)
				and not accepted_start.get("propulsion_source_running", true),
				"checkpoint_off=%s accepted_start=%s" % [glide_off, accepted_start])


func _test_catalog_fixed_tape() -> void:
	var entries: Array = Catalog.airplane_flyable_entries()
	_check("catalog-wide launch cases cover all eight airplane defaults", entries.size() == 8,
		"airplane default count: %d" % entries.size())
	var accepted_runs: int = 0
	var unsupported_runs: int = 0
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var aircraft_id: String = str(entry.get("id", ""))
		var base_path: String = str(entry.get("data", ""))
		var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(base_path)
		if base_bytes.is_empty():
			unsupported_runs += 2
			print("UNSUPPORTED ", aircraft_id, ": default aircraft source is unavailable")
			continue
		var frozen: Dictionary = Trial.freeze({"base_id": aircraft_id, "base_bytes": base_bytes, "recipe": {}})
		if not frozen.get("ok", false):
			unsupported_runs += 2
			print("UNSUPPORTED ", aircraft_id, ": frozen default Trial refused: ", str(frozen.get("errors", [])))
			continue
		var frozen_model: Dictionary = frozen.get("data", {}).get("model", {})
		var expected_speed: float = float(frozen_model.get("start_speed", NAN))
		if not is_finite(expected_speed) or expected_speed < 1.0 or expected_speed > 100.0:
			unsupported_runs += 2
			print("UNSUPPORTED ", aircraft_id, ": frozen default model has no bounded start_speed")
			continue
		for mode: String in ["level", "glide"]:
			var recipe: Dictionary = _flight_recipe(60, expected_speed, mode, 30.0, 0.0)
			var run: Dictionary = Experiments.run_fixed_tape(frozen, recipe)
			var label: String = "%s %s" % [aircraft_id, mode]
			if not run.get("ok", false):
				unsupported_runs += 1
				print("UNSUPPORTED ", label, ": ", str(run.get("errors", [])))
				_check("catalog refusal is explicit for " + label, not str(run.get("errors", [])).is_empty())
				continue
			accepted_runs += 1
			var result: Dictionary = run.result
			var metrics: Dictionary = result.get("metrics", {})
			_check("catalog run honors frozen start speed, altitude, gravity and 240 Hz for " + label,
				str(result.get("trial_identity", {}).get("trial_id", "")) == str(frozen.identity.get("trial_id", ""))
				and is_equal_approx(float(result.get("start", {}).get("speed_mps", -1.0)), expected_speed)
				and absf(float(metrics.get("initial_body_speed_mps", -1.0)) - expected_speed) <= 1.0e-5
				and absf(float(metrics.get("initial_altitude_m", -1.0)) - 30.0) <= 1.0e-8
				and is_equal_approx(float(result.get("environment", {}).get("identity", {}).get("gravity", -1.0)), 9.80665)
				and is_equal_approx(float(result.get("dt_s", -1.0)), 1.0 / 240.0)
				and result.get("termination", {}).get("requested_ticks", -1) == 60
				and int(result.get("termination", {}).get("actual_ticks", -1)) <= 60, str(run.get("errors", [])))
			var layout: Array = result.get("input_layout", [])
			var held: Array = result.get("held_registered_inputs", [])
			var input_tape: Array = result.get("input_tape", [])
			var tape_inputs: Array = input_tape[0].get("inputs", []) if not input_tape.is_empty() else []
			var held_consistent: bool = layout.size() == 4 + held.size() and tape_inputs.size() == layout.size()
			if held_consistent:
				for held_index: int in held.size():
					held_consistent = held_consistent and is_equal_approx(float(tape_inputs[4 + held_index]), float(held[held_index]))
			_check("catalog run records its exact accepted extra input channels for " + label, held_consistent)
			_check("catalog run ends only at its declared bound or an explicit simulation stop for " + label,
				str(result.get("termination", {}).get("reason", "")) in ["tick_limit", "simulation_fault", "ground_contact", "gear_collapse"]
				and (bool(result.get("completed", false)) or not str(result.get("failure_reason", "")).is_empty()))
			if mode == "glide":
				var checkpoint_off: bool = _checkpoint_engine_off(str(result.get("initial_checkpoint", "")))
				var accepted_start: Dictionary = result.get("accepted_start", {})
				_check("catalog glide checkpoint and accepted source state are off for " + aircraft_id,
					checkpoint_off and not accepted_start.get("engine_running", true)
					and not accepted_start.get("propulsion_source_running", true),
					"checkpoint_off=%s accepted_start=%s" % [checkpoint_off, accepted_start])
	print("Catalog fixed-tape conformance: %d accepted runs, %d explicit unsupported runs" % [accepted_runs, unsupported_runs])


func _flight_recipe(ticks: int, speed_mps: float = 15.0, mode: String = "level",
		altitude_m: float = 30.0, throttle: float = 0.5) -> Dictionary:
	return {
		"format": Experiments.EXPERIMENT_FORMAT,
		"version": Experiments.EXPERIMENT_VERSION,
		"start": {"mode": mode, "speed_mps": speed_mps, "altitude_m": altitude_m},
		"environment": {"weather": WindConfig.defaults(), "gravity_mps2": 9.80665},
		"fuel_start_fill": 1.0,
		"segments": [{"ticks": ticks, "inputs": [0.0, 0.0, 0.0, throttle]}],
		"termination": {"kind": "tick_limit", "ticks": ticks},
	}


func _checkpoint_engine_off(encoded: String) -> bool:
	var decoded: Dictionary = CheckpointJson.decode(encoded)
	if not bool(decoded.get("ok", false)):
		return false
	var snapshot: Dictionary = decoded.get("snapshot", {})
	var simulation: Dictionary = snapshot.get("simulation", {})
	var modes: Variant = simulation.get("modes", PackedInt32Array())
	if typeof(modes) in [TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY]:
		return not modes.is_empty() and int(modes[0]) == 0
	if modes is Array:
		return not modes.is_empty() and int(modes[0]) == 0
	return false


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)
