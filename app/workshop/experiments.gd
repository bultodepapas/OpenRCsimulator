extends RefCounted
## AE-20/22 bounded Workshop analysis. Every result is a software estimate or a fixed-tick
## simulation result; neither is presented as physical aircraft validation.

const Parameters := preload("res://workshop/parameters.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Session := preload("res://sim/flight_session.gd")
const Simulation := preload("res://sim/simulation.gd")
const RigidBody := preload("res://physics/rigid_body.gd")
const Math3D := preload("res://physics/math3d.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const BuildInfo := preload("res://app_state/build_info.gd")

const SWEEP_FORMAT: String = "openrc-aircraft-workshop-sweep"
const SWEEP_VERSION: int = 1
const EXPERIMENT_FORMAT: String = "openrc-aircraft-workshop-flight-experiment"
const EXPERIMENT_VERSION: int = 1
const RESULT_FORMAT: String = "openrc-aircraft-workshop-experiment-result"
const RESULT_VERSION: int = 1
const MAX_AXES: int = 4
const MAX_AXIS_VALUES: int = 8
const MAX_CANDIDATES: int = 32
const MAX_SEGMENTS: int = 64
const MAX_EXPERIMENT_TICKS: int = 28800 # 120 s at the required 240 Hz.
const MAX_CHECKPOINT_BYTES: int = 262144
const MAX_SAFE_INTEGER: float = 9007199254740991.0
const UINT32_MAX: float = 4294967295.0
const FLOAT32_RANGE: float = 4294967296.0
const UINT32_MASK: int = 0xFFFFFFFF
const PHYSICAL_KEYS: PackedStringArray = [
	"scale", "mass_policy", "weight_multiplier", "power_multiplier", "control_multiplier",
	"tank_capacity_multiplier",
]
const SWEEP_COMMON_KEYS: PackedStringArray = ["format", "version", "mode", "recipe", "axes"]
const EXPERIMENT_KEYS: PackedStringArray = [
	"format", "version", "start", "environment", "fuel_start_fill", "segments", "termination",
]
const START_KEYS: PackedStringArray = ["mode", "speed_mps", "altitude_m"]
const ENVIRONMENT_KEYS: PackedStringArray = ["weather", "gravity_mps2"]
const SEGMENT_KEYS: PackedStringArray = ["ticks", "inputs"]
const TERMINATION_KEYS: PackedStringArray = ["kind", "ticks"]


## Validate one closed, physical-only recipe with the exact bounds consumed by Compiler.
static func validate_recipe(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or not _has_exact_keys(value, EXPERIMENT_KEYS):
		errors.append("Flight experiment has missing or unsupported fields.")
		return _failure(errors)
	var source: Dictionary = value
	if source["format"] != EXPERIMENT_FORMAT or not _integral(source["version"]) \
			or int(source["version"]) != EXPERIMENT_VERSION:
		errors.append("Flight experiment format or version is unsupported.")
	var start_value: Variant = source["start"]
	var environment_value: Variant = source["environment"]
	var termination_value: Variant = source["termination"]
	if typeof(start_value) != TYPE_DICTIONARY or not _has_exact_keys(start_value, START_KEYS):
		errors.append("Experiment start must contain exactly mode, speed_mps, and altitude_m.")
	if typeof(environment_value) != TYPE_DICTIONARY or not _has_exact_keys(environment_value, ENVIRONMENT_KEYS):
		errors.append("Experiment environment must contain exactly weather and gravity_mps2.")
	if typeof(termination_value) != TYPE_DICTIONARY or not _has_exact_keys(termination_value, TERMINATION_KEYS):
		errors.append("Experiment termination must contain exactly kind and ticks.")
	if not errors.is_empty():
		return _failure(errors)
	var start: Dictionary = start_value
	var mode: Variant = start["mode"]
	if typeof(mode) != TYPE_STRING or mode not in ["level", "glide"]:
		errors.append("Experiment start mode must be level or glide.")
	var speed: float = _bounded_number(start["speed_mps"], 1.0, 100.0, "start.speed_mps", errors)
	var altitude: float = _bounded_number(start["altitude_m"], 5.0, 5000.0, "start.altitude_m", errors)
	var environment: Dictionary = environment_value
	var gravity: float = _bounded_number(environment["gravity_mps2"], 1.0, 30.0, "environment.gravity_mps2", errors)
	var weather_checked: Dictionary = WindConfig.validate(environment["weather"])
	if not bool(weather_checked.get("ok", false)):
		errors.append_array(weather_checked.get("errors", PackedStringArray()))
	var fuel_fill: float = _bounded_number(source["fuel_start_fill"], 0.000001, 1.0, "fuel_start_fill", errors)
	var termination: Dictionary = termination_value
	if termination["kind"] != "tick_limit" or not _integral(termination["ticks"]) \
			or int(termination["ticks"]) < 1 or int(termination["ticks"]) > MAX_EXPERIMENT_TICKS:
		errors.append("Experiment termination must be a tick_limit from 1 through %d ticks." % MAX_EXPERIMENT_TICKS)
	var total_ticks: int = int(termination["ticks"]) if _integral(termination["ticks"]) else 0
	var segments_value: Variant = source["segments"]
	if typeof(segments_value) != TYPE_ARRAY or segments_value.is_empty() or segments_value.size() > MAX_SEGMENTS:
		errors.append("Experiment segments must contain 1–%d bounded input spans." % MAX_SEGMENTS)
		return _failure(errors)
	var segments: Array = []
	var summed_ticks: int = 0
	for segment_value: Variant in segments_value:
		if typeof(segment_value) != TYPE_DICTIONARY or not _has_exact_keys(segment_value, SEGMENT_KEYS):
			errors.append("Experiment segment has missing or unsupported fields.")
			continue
		var segment: Dictionary = segment_value
		if not _integral(segment["ticks"]) or int(segment["ticks"]) < 1:
			errors.append("Experiment segment ticks must be a positive integer.")
			continue
		var ticks: int = int(segment["ticks"])
		var inputs_value: Variant = segment["inputs"]
		if typeof(inputs_value) != TYPE_ARRAY or inputs_value.size() != 4:
			errors.append("Each tape span needs four post-control-shaping solver inputs: roll, pitch, yaw, throttle.")
			continue
		var inputs: Array = []
		for axis: int in 4:
			var lower: float = 0.0 if axis == 3 else -1.0
			var upper: float = 1.0
			inputs.append(_bounded_number(inputs_value[axis], lower, upper, "segment.inputs[%d]" % axis, errors))
		if mode == "glide" and float(inputs[3]) != 0.0:
			errors.append("Glide experiments require zero throttle throughout the input tape.")
		if ticks > MAX_EXPERIMENT_TICKS or summed_ticks > MAX_EXPERIMENT_TICKS - ticks:
			errors.append("Experiment input tape exceeds the %d-tick bound." % MAX_EXPERIMENT_TICKS)
			continue
		summed_ticks += ticks
		var normalized_segment: Dictionary = {"ticks": ticks, "inputs": inputs}
		if not segments.is_empty() and segments[-1]["inputs"] == inputs:
			segments[-1]["ticks"] = int(segments[-1]["ticks"]) + ticks
		else:
			segments.append(normalized_segment)
	if summed_ticks != total_ticks:
		errors.append("Experiment tape spans %d ticks but termination requests %d." % [summed_ticks, total_ticks])
	if segments.size() > MAX_SEGMENTS:
		errors.append("Canonical experiment tape exceeds its segment limit.")
	if not errors.is_empty():
		return _failure(errors)
	var normalized: Dictionary = {
		"format": EXPERIMENT_FORMAT,
		"version": EXPERIMENT_VERSION,
		"start": {"mode": str(mode), "speed_mps": speed, "altitude_m": altitude},
		"environment": {"weather": weather_checked.config, "gravity_mps2": gravity},
		"fuel_start_fill": fuel_fill,
		"segments": segments,
		"termination": {"kind": "tick_limit", "ticks": total_ticks},
	}
	return {"ok": true, "errors": errors, "recipe": normalized}


## Existing evaluator outputs only. No speed, climb, roll response, or endurance is synthesized here.
static func static_report(base: Dictionary, recipe: Dictionary) -> Dictionary:
	var physical: Dictionary = _physical_recipe(recipe)
	if not bool(physical.get("ok", false)):
		return _failure(physical.errors)
	var compiled: Dictionary = Compiler.compile(base, physical.recipe)
	if not bool(compiled.get("ok", false)):
		return _failure(compiled.get("errors", PackedStringArray()))
	return _static_report_from_compiled(compiled, physical.recipe)


## Capability-safe parameter sweep; candidates are bounded to 32 and each uses the existing compiler.
static func sweep(base: Dictionary, raw_spec: Variant) -> Dictionary:
	var checked: Dictionary = validate_sweep(raw_spec)
	if not bool(checked.get("ok", false)):
		return checked
	if typeof(base) != TYPE_DICTIONARY or base.is_empty():
		return _failure(PackedStringArray(["Sweep requires a nonempty validated aircraft source object."]))
	var spec: Dictionary = checked.spec
	var base_sha256: String = _sha(JSON.stringify(base, "", true, true).to_utf8_buffer())
	var sweep_sha256: String = _sha(JSON.stringify({"base_sha256": base_sha256, "spec": spec}, "", true, true).to_utf8_buffer())
	var recipes: Array = _candidate_recipes(spec)
	var candidates: Array = []
	for index: int in range(recipes.size()):
		var recipe: Dictionary = recipes[index]
		var compiled: Dictionary = Compiler.compile(base, recipe)
		var candidate_id: String = "candidate-" + _sha((base_sha256 + ":" + JSON.stringify(recipe, "", true, true)
			+ ":" + Compiler.version_for_recipe(recipe)).to_utf8_buffer()).substr(0, 24)
		if bool(compiled.get("ok", false)):
			candidates.append({"index": index, "candidate_id": candidate_id, "recipe": recipe,
				"ok": true, "static_report": _static_report_from_compiled(compiled, recipe)})
		else:
			candidates.append({"index": index, "candidate_id": candidate_id, "recipe": recipe,
				"ok": false, "errors": compiled.get("errors", PackedStringArray()),
				"static_report": {"available": false, "scope": "bounded_static_estimate",
					"unavailable_reason": "; ".join(compiled.get("errors", PackedStringArray()))}})
	return {"ok": true, "errors": PackedStringArray(), "format": SWEEP_FORMAT,
		"version": SWEEP_VERSION, "sweep_sha256": sweep_sha256, "mode": spec.mode,
		"seed": int(spec.get("seed", 0)), "candidate_count": candidates.size(), "candidates": candidates,
		"limits": ["At most %d candidates." % MAX_CANDIDATES,
			"Each candidate is compiled against declared Workshop bounds and capabilities.",
			"Static estimates are not scripted flight performance or physical validation."]}


## Validate a grid or a local-seed numeric discovery search without evaluating a candidate.
static func validate_sweep(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure(PackedStringArray(["Sweep specification must be an object."]))
	var source: Dictionary = raw
	var mode: Variant = source.get("mode", null)
	var allowed: PackedStringArray = SWEEP_COMMON_KEYS.duplicate()
	var required: PackedStringArray = ["format", "version", "mode", "axes"]
	if mode == "seeded_discovery":
		allowed.append_array(["seed", "candidate_count"])
		required.append_array(["seed", "candidate_count"])
	if not _has_exact_required_keys(source, required, allowed):
		errors.append("Sweep specification has missing or unsupported fields.")
	if source.get("format", null) != SWEEP_FORMAT or not _integral(source.get("version", null)) \
			or int(source.get("version", 0)) != SWEEP_VERSION:
		errors.append("Sweep format or version is unsupported.")
	if typeof(mode) != TYPE_STRING or mode not in ["grid", "seeded_discovery"]:
		errors.append("Sweep mode must be grid or seeded_discovery.")
	var recipe: Dictionary = {}
	var recipe_value: Variant = source.get("recipe", {})
	if typeof(recipe_value) != TYPE_DICTIONARY:
		errors.append("Sweep recipe must be an object.")
	else:
		var recipe_check: Dictionary = _physical_recipe(recipe_value)
		if not bool(recipe_check.get("ok", false)):
			errors.append_array(recipe_check.get("errors", PackedStringArray()))
		else:
			recipe = recipe_check.recipe
	var axes_value: Variant = source.get("axes", null)
	if typeof(axes_value) != TYPE_ARRAY or axes_value.is_empty() or axes_value.size() > MAX_AXES:
		errors.append("Sweep axes must contain 1–%d parameter ranges." % MAX_AXES)
		return _failure(errors)
	var axes: Array = []
	var seen: Dictionary = {}
	var candidate_count: int = 1
	var definitions: Dictionary = _definition_map()
	for axis_value: Variant in axes_value:
		if typeof(axis_value) != TYPE_DICTIONARY:
			errors.append("Sweep axis must be an object.")
			continue
		var axis: Dictionary = axis_value
		var key_value: Variant = axis.get("key", null)
		if typeof(key_value) != TYPE_STRING or not PHYSICAL_KEYS.has(str(key_value)):
			errors.append("Sweep axis key must name a physical Workshop parameter.")
			continue
		var key: String = str(key_value)
		if seen.has(key):
			errors.append("Sweep contains duplicate axis '%s'." % key)
			continue
		seen[key] = true
		var definition: Dictionary = definitions[key]
		if mode == "grid":
			if not _has_exact_keys(axis, ["key", "values"]):
				errors.append("Grid axis requires exactly key and values.")
				continue
			var values_value: Variant = axis["values"]
			if typeof(values_value) != TYPE_ARRAY or values_value.is_empty() or values_value.size() > MAX_AXIS_VALUES:
				errors.append("Grid axis values must contain 1–%d choices." % MAX_AXIS_VALUES)
				continue
			var values: Array = []
			for candidate_value: Variant in values_value:
				var normalized_value: Variant = _axis_value(key, candidate_value, errors)
				if errors.is_empty() and values.has(normalized_value):
					errors.append("Grid axis '%s' contains a duplicate value." % key)
				if not errors.is_empty():
					break
				values.append(normalized_value)
			if not errors.is_empty():
				continue
			candidate_count *= values.size()
			axes.append({"key": key, "values": values})
		else:
			if not _has_exact_keys(axis, ["key", "minimum", "maximum"]):
				errors.append("Seeded discovery axis requires exactly key, minimum, and maximum.")
				continue
			if definition.get("kind", "") != "number":
				errors.append("Seeded discovery supports numeric parameter axes only.")
				continue
			var lower: Variant = _axis_value(key, axis["minimum"], errors)
			var upper: Variant = _axis_value(key, axis["maximum"], errors)
			if errors.is_empty() and float(lower) >= float(upper):
				errors.append("Seeded discovery axis minimum must be below maximum.")
			if errors.is_empty():
				axes.append({"key": key, "minimum": float(lower), "maximum": float(upper)})
		if not errors.is_empty():
			continue
	var seed_value: int = 0
	var discovery_count: int = 0
	if mode == "seeded_discovery":
		if not _integral(source.get("seed", null)) or float(source.get("seed", -1)) < 0.0 \
				or float(source.get("seed", UINT32_MAX + 1.0)) > UINT32_MAX:
			errors.append("Discovery seed must be an integer in [0, 4294967295].")
		else:
			seed_value = int(source["seed"])
		if not _integral(source.get("candidate_count", null)) or int(source.get("candidate_count", 0)) < 1 \
				or int(source.get("candidate_count", MAX_CANDIDATES + 1)) > MAX_CANDIDATES:
			errors.append("Discovery candidate_count must be from 1 through %d." % MAX_CANDIDATES)
		else:
			discovery_count = int(source["candidate_count"])
		candidate_count = discovery_count
	if mode == "grid" and candidate_count > MAX_CANDIDATES:
		errors.append("Grid creates %d candidates; the maximum is %d." % [candidate_count, MAX_CANDIDATES])
	if not errors.is_empty():
		return _failure(errors)
	var normalized: Dictionary = {"format": SWEEP_FORMAT, "version": SWEEP_VERSION,
		"mode": str(mode), "recipe": recipe, "axes": axes}
	if mode == "seeded_discovery":
		normalized["seed"] = seed_value
		normalized["candidate_count"] = discovery_count
	return {"ok": true, "errors": errors, "spec": normalized, "candidate_count": candidate_count}


## Run one closed tape through a fresh 240 Hz Session using a frozen Trial as its only aircraft source.
static func run_fixed_tape(frozen_trial: Dictionary, raw_recipe: Variant) -> Dictionary:
	var recipe_check: Dictionary = validate_recipe(raw_recipe)
	if not bool(recipe_check.get("ok", false)):
		return recipe_check
	var trial_check: Dictionary = _validate_frozen_trial(frozen_trial)
	if not bool(trial_check.get("ok", false)):
		return _failure(trial_check.get("errors", PackedStringArray()))
	var hz: int = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 240))
	if hz != 240:
		return _failure(PackedStringArray(["Fixed-tape experiments require the project physics rate to be 240 Hz."]))
	var recipe: Dictionary = recipe_check.recipe
	var model: Dictionary = frozen_trial.data.get("model", {})
	var vehicle_check: Dictionary = _frozen_vehicle(frozen_trial)
	if not bool(vehicle_check.get("ok", false)):
		return _failure(vehicle_check.get("errors", PackedStringArray()))
	var solver_sha256: String = FlightLog.solver_identity()
	if solver_sha256 == "unavailable-export" or not _is_sha256(solver_sha256):
		return _failure(PackedStringArray(["Fixed-tape reproducibility requires an available solver source identity."]))
	var build_identity: Dictionary = BuildInfo.current()
	var session: Variant = Session.new()
	session.physics_enabled = true
	session.input_enabled = false
	session.rate_profile = "full"
	session.crash_auto_restart = false
	session.soft_hull_contacts = false
	session.setup("", str(model.get("id", "")), frozen_trial.data)
	if not bool(session.aircraft.get("ok", false)) or session.sim == null or session.sim.model == null:
		var setup_error: PackedStringArray = PackedStringArray(["Frozen trial could not install a flight session."])
		session.free()
		return _failure(setup_error)
	if not _known_input_layout(session):
		var layout_error: PackedStringArray = PackedStringArray(["FlightSession exposed an unknown solver-input channel layout."])
		session.free()
		return _failure(layout_error)
	var environment: Dictionary = recipe.environment
	session.sim.gravity = float(environment.gravity_mps2)
	session.environment.gravity = float(environment.gravity_mps2)
	if not session.setup_weather(environment.weather):
		var weather_error: PackedStringArray = PackedStringArray([str(session.weather_error)])
		session.free()
		return _failure(weather_error)
	if not session.set_fuel_start_fill(float(recipe.fuel_start_fill)):
		var fuel_error: PackedStringArray = PackedStringArray(["Fuel start fill is incompatible with the frozen aircraft."])
		session.free()
		return _failure(fuel_error)
	session.set_start_altitude(float(recipe.start.altitude_m))
	var trim: Dictionary = session.trim_at(float(recipe.start.speed_mps), str(recipe.start.mode))
	if not bool(trim.get("ok", false)):
		var trim_error: PackedStringArray = PackedStringArray(["Experiment start could not be trimmed: %s" % str(trim.get("message", "unknown trim failure"))])
		session.free()
		return _failure(trim_error)
	session.reset()
	if not bool(session.start.get("ok", false)) or not session.is_flyable() or not session.sim.fault_reason.is_empty():
		var start_error: PackedStringArray = PackedStringArray(["Experiment start was not accepted by FlightSession: %s" % str(session.start.get("message", session.start_error))])
		session.free()
		return _failure(start_error)
	var accepted_engine_running: bool = session.engine_running
	var accepted_source_running: bool = session.propulsion_source_running()
	if str(recipe.start.mode) == "glide" and (accepted_engine_running or accepted_source_running):
		var glide_source_error: PackedStringArray = PackedStringArray([
			"FlightSession accepted a glide start with the propulsion source still active."])
		session.free()
		return _failure(glide_source_error)
	var input_layout: Array = _input_layout(session)
	var start_inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	if start_inputs.size() != input_layout.size():
		var inputs_error: PackedStringArray = PackedStringArray(["FlightSession initial solver inputs do not match its registered layout."])
		session.free()
		return _failure(inputs_error)
	var held_inputs: Array = []
	for index: int in range(4, start_inputs.size()):
		held_inputs.append(float(start_inputs[index]))
	var segments: Array = recipe.segments
	var first_solver_inputs: PackedFloat64Array = _solver_input(segments[0].inputs, held_inputs)
	session.sim.inputs = first_solver_inputs.duplicate()
	session.sim.stop_at_tick = int(recipe.termination.ticks)
	var initial_checkpoint: String = str(session.checkpoint_json())
	if initial_checkpoint.is_empty() or initial_checkpoint.to_utf8_buffer().size() > MAX_CHECKPOINT_BYTES:
		var checkpoint_error: PackedStringArray = PackedStringArray(["Initial experiment checkpoint is missing or exceeds the bounded result size."])
		session.free()
		return _failure(checkpoint_error)
	var initial_state: PackedFloat64Array = session.sim.state.duplicate()
	var initial_environment: Dictionary = session.environment.identity()
	var full_segments: Array = []
	for segment: Dictionary in segments:
		full_segments.append({"ticks": int(segment.ticks),
			"inputs": Array(_solver_input(segment.inputs, held_inputs))})
	var full_tape: Dictionary = {"tick_rate_hz": 240, "input_layout": input_layout,
		"segments": full_segments}
	var tape_sha256: String = _sha(JSON.stringify(full_tape, "", true, true).to_utf8_buffer())
	var initial_checkpoint_sha256: String = _sha(initial_checkpoint.to_utf8_buffer())
	var peak_altitude: float = -float(initial_state[RigidBody.POS + 2])
	var minimum_altitude: float = peak_altitude
	var minimum_airspeed: float = _airspeed(initial_state)
	var maximum_airspeed: float = minimum_airspeed
	var maximum_abs_roll: float = absf(_roll_deg(initial_state))
	var termination_reason: String = "tick_limit"
	var failure_reason: String = ""
	var current_segment: int = 0
	var segment_end_tick: int = int(segments[0].ticks)
	for tick: int in range(int(recipe.termination.ticks)):
		if current_segment < segments.size() and tick >= segment_end_tick:
			current_segment += 1
			if current_segment < segments.size():
				segment_end_tick += int(segments[current_segment].ticks)
		if current_segment >= segments.size():
			termination_reason = "invalid_tape_cursor"
			failure_reason = "input tape ended before the declared tick limit"
			break
		session.sim.inputs = _solver_input(segments[current_segment].inputs, held_inputs)
		session.sim.step()
		if not str(session.sim.fault_reason).is_empty():
			termination_reason = "simulation_fault"
			failure_reason = str(session.sim.fault_reason)
			break
		if int(session.sim.tick) != tick + 1 or not Simulation.state_is_valid(session.sim.state):
			termination_reason = "simulation_fault"
			failure_reason = "simulation step did not accept one finite fixed tick"
			break
		var state: PackedFloat64Array = session.sim.state
		var altitude: float = -float(state[RigidBody.POS + 2])
		var airspeed: float = _airspeed(state)
		peak_altitude = maxf(peak_altitude, altitude)
		minimum_altitude = minf(minimum_altitude, altitude)
		minimum_airspeed = minf(minimum_airspeed, airspeed)
		maximum_airspeed = maxf(maximum_airspeed, airspeed)
		maximum_abs_roll = maxf(maximum_abs_roll, absf(_roll_deg(state)))
		if session.touches_ground(state):
			termination_reason = "ground_contact"
			failure_reason = "crash-hull contact with the default flat ground"
			break
		if session.gear_collapsed(state):
			termination_reason = "gear_collapse"
			failure_reason = "landing-gear travel exceeded its validated limit"
			break
	var final_state: PackedFloat64Array = session.sim.state.duplicate()
	var reached_ticks: int = int(session.sim.tick)
	var elapsed: float = float(reached_ticks) / 240.0
	var final_altitude: float = -float(final_state[RigidBody.POS + 2])
	var final_airspeed: float = _airspeed(final_state)
	var metrics: Dictionary = {
		"initial_altitude_m": -float(initial_state[RigidBody.POS + 2]),
		"final_altitude_m": final_altitude,
		"altitude_change_m": final_altitude + float(initial_state[RigidBody.POS + 2]),
		"average_altitude_change_mps": (final_altitude + float(initial_state[RigidBody.POS + 2])) / elapsed if elapsed > 0.0 else 0.0,
		"initial_body_speed_mps": _airspeed(initial_state),
		"final_body_speed_mps": final_airspeed,
		"minimum_body_speed_mps": minimum_airspeed,
		"maximum_body_speed_mps": maximum_airspeed,
		"peak_altitude_m": peak_altitude,
		"minimum_altitude_m": minimum_altitude,
		"maximum_abs_roll_deg": maximum_abs_roll,
	}
	var result: Dictionary = {
		"format": RESULT_FORMAT,
		"version": RESULT_VERSION,
		"scope": "fixed_tick_software_simulation",
		"completed": termination_reason == "tick_limit",
		"failure_reason": failure_reason,
		"trial_identity": frozen_trial.identity.duplicate(true),
		"presentation_identity": frozen_trial.get("presentation_identity", {}).duplicate(true),
		"source_identity": {"solver_sha256": solver_sha256, "build": build_identity.duplicate(true)},
		"initial_checkpoint": initial_checkpoint,
		"initial_checkpoint_sha256": initial_checkpoint_sha256,
		"environment": {"configuration": environment.duplicate(true), "identity": initial_environment},
		"tick_rate_hz": 240,
		"dt_s": 1.0 / 240.0,
		"input_domain": "post-control-shaping solver inputs [roll, pitch, yaw, throttle]; optional registered channels held at their exact launch values",
		"input_layout": input_layout,
		"held_registered_inputs": held_inputs,
		"accepted_start": {"engine_running": accepted_engine_running,
			"propulsion_source_running": accepted_source_running},
		"input_tape": full_segments,
		"post_control_axis_tape": recipe.segments.duplicate(true),
		"input_tape_sha256": tape_sha256,
		"start": recipe.start.duplicate(true),
		"fuel_start_fill": float(recipe.fuel_start_fill),
		"domain": {"state": "fixed-wing 64-bit float simulation", "step_policy": "project fixed 240 Hz FlightSession/Simulation"},
		"termination": {"requested_kind": "tick_limit", "requested_ticks": int(recipe.termination.ticks),
			"actual_ticks": reached_ticks, "actual_time_s": elapsed, "reason": termination_reason},
		"metrics": metrics,
		"limits": ["These are model simulation outputs, not physical measurements or qualification evidence.",
			"Static thrust/RPM estimates remain separate Compiler evaluator outputs.",
			"This bounded run does not establish full-flight stability, endurance, target-aircraft accuracy, or pilot acceptance."],
	}
	result["identity_report"] = {
		"physical_trial": frozen_trial.identity.duplicate(true),
		"presentation": frozen_trial.get("presentation_identity", {}).duplicate(true),
		"solver_sha256": solver_sha256,
		"build": build_identity.duplicate(true),
		"initial_checkpoint_sha256": initial_checkpoint_sha256,
		"environment": initial_environment.duplicate(true),
		"tick_rate_hz": 240,
		"dt_s": 1.0 / 240.0,
		"input_tape_sha256": tape_sha256,
	}
	session.free()
	return {"ok": true, "errors": PackedStringArray(), "result": result}


static func _static_report_from_compiled(compiled: Dictionary, recipe: Dictionary) -> Dictionary:
	var summary: Dictionary = compiled.get("summary", {})
	var static_metrics: Dictionary = {}
	var build_summary: Dictionary = {}
	for key: String in ["static_thrust_n", "static_power_w", "idle_rpm", "max_rpm"]:
		if summary.has(key):
			static_metrics[key] = summary[key]
	for key: String in ["mass_kg", "wing_area_m2", "wing_span_m", "wing_loading_kg_m2", "fuel_capacity_l",
		"scale", "mass_policy", "weight_multiplier", "power_multiplier", "control_multiplier", "tank_capacity_multiplier"]:
		if summary.has(key):
			build_summary[key] = summary[key]
	var unavailable_reason: String = ""
	if static_metrics.is_empty():
		unavailable_reason = "The current compiler exposes no prescribed-RPM propeller static coefficient estimate for this candidate."
	return {"ok": true, "available": not static_metrics.is_empty(), "scope": "bounded_static_estimate",
		"recipe": recipe.duplicate(true), "metrics": static_metrics, "compiled_build_summary": build_summary,
		"method": str(summary.get("power_reference_note", "Current Workshop compiler build summary; no flight-performance evaluator was run.")),
		"unavailable_reason": unavailable_reason,
		"compiler_version": Compiler.version_for_recipe(recipe),
		"limits": ["Static estimates use the existing Workshop compiler/evaluator outputs only.",
			"They do not predict scripted speed, climb, roll response, endurance, or measured engine output.",
			"Numerical validity is not physical aircraft validation."]}


static func _candidate_recipes(spec: Dictionary) -> Array:
	var candidates: Array = []
	if spec.mode == "grid":
		var partial: Array = [spec.recipe.duplicate(true)]
		for axis: Dictionary in spec.axes:
			var expanded: Array = []
			for prefix_variant: Variant in partial:
				var prefix: Dictionary = prefix_variant
				for value: Variant in axis.values:
					var candidate: Dictionary = prefix.duplicate(true)
					candidate[str(axis.key)] = value
					expanded.append(candidate)
			partial = expanded
		return partial
	var rng: Dictionary = {"state": int(spec.seed) if int(spec.seed) != 0 else 1831565813}
	for candidate_index: int in range(int(spec.candidate_count)):
		var candidate: Dictionary = spec.recipe.duplicate(true)
		for axis: Dictionary in spec.axes:
			var sample: float = _random_unit(rng)
			candidate[str(axis.key)] = float(axis.minimum) + (float(axis.maximum) - float(axis.minimum)) * sample
		var checked: Dictionary = Parameters.validate(candidate)
		candidates.append(checked.values if bool(checked.get("ok", false)) else candidate)
	return candidates


static func _random_unit(rng: Dictionary) -> float:
	var value: int = int(rng.state) & UINT32_MASK
	value = (value ^ ((value << 13) & UINT32_MASK)) & UINT32_MASK
	value = (value ^ (value >> 17)) & UINT32_MASK
	value = (value ^ ((value << 5) & UINT32_MASK)) & UINT32_MASK
	rng.state = value
	return float(value) / FLOAT32_RANGE


static func _physical_recipe(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": PackedStringArray(["Physical experiment recipe must be an object."])}
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or (not PHYSICAL_KEYS.has(str(key)) and key != "mass_edits"):
			errors.append("Physical experiment recipe contains unsupported key '%s'." % str(key))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var checked: Dictionary = Parameters.validate(value)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "errors": checked.get("errors", PackedStringArray())}
	var physical: Dictionary = {}
	for key: String in PHYSICAL_KEYS:
		physical[key] = checked.values[key]
	if checked.values.has("mass_edits"): physical["mass_edits"] = checked.values.mass_edits.duplicate(true)
	return {"ok": true, "errors": PackedStringArray(), "recipe": physical}


static func _definition_map() -> Dictionary:
	var result: Dictionary = {}
	for item: Variant in Parameters.definitions().get("parameters", []):
		if item is Dictionary:
			result[str(item.get("key", ""))] = item
	return result


static func _axis_value(key: String, value: Variant, errors: PackedStringArray) -> Variant:
	var checked: Dictionary = Parameters.validate({key: value})
	if not bool(checked.get("ok", false)):
		errors.append_array(checked.get("errors", PackedStringArray()))
		return null
	return checked.values[key]


static func _validate_frozen_trial(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or not bool(value.get("ok", false)):
		errors.append("A successful frozen Workshop Trial is required.")
		return {"ok": false, "errors": errors}
	var identity: Variant = value.get("identity", null)
	var data: Variant = value.get("data", null)
	var raw_bytes: Variant = value.get("raw_bytes", null)
	if typeof(identity) != TYPE_DICTIONARY or identity.get("format", "") != "openrc-aircraft-trial v1" \
			or typeof(identity.get("trial_id", null)) != TYPE_STRING or str(identity.trial_id).is_empty():
		errors.append("Frozen Trial physical identity is missing or unsupported.")
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("model", null)) != TYPE_DICTIONARY:
		errors.append("Frozen Trial has no validated resolved aircraft model.")
	if typeof(raw_bytes) != TYPE_PACKED_BYTE_ARRAY:
		errors.append("Frozen Trial has no exact resolved source bytes.")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if _sha(raw_bytes) != str(identity.get("resolved_sha256", "")):
		errors.append("Frozen Trial source bytes do not match the physical identity pin.")
	if _sha(var_to_bytes(data.model)) != str(identity.get("resolved_model_sha256", "")):
		errors.append("Frozen Trial model does not match the physical identity pin.")
	if data.get("input_identity", {}).get("sha256", "") != str(identity.get("resolved_sha256", "")):
		errors.append("Frozen Trial validated data do not name the pinned resolved source bytes.")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors}


static func _frozen_vehicle(frozen_trial: Dictionary) -> Dictionary:
	var raw_bytes: PackedByteArray = frozen_trial.get("raw_bytes", PackedByteArray())
	var text: String = raw_bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != raw_bytes:
		return _failure(PackedStringArray(["Frozen Trial source is not canonical UTF-8."]))
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _failure(PackedStringArray(["Frozen Trial source does not contain a valid aircraft object."]))
	var vehicle: Variant = parser.data.get("vehicle", "airplane")
	if typeof(vehicle) != TYPE_STRING or str(vehicle) != "airplane":
		return _failure(PackedStringArray(["Fixed-tape runner supports only frozen airplane models; this vehicle family is unsupported."]))
	return {"ok": true, "errors": PackedStringArray(), "vehicle": "airplane"}


static func _known_input_layout(session: Variant) -> bool:
	if session.sim == null or session.sim.model == null:
		return false
	var expected: int = 4 + (2 if session.gear_is_retractable() else 0) + (1 if session.flaps_available() else 0)
	return int(session.sim.model.input_size) == expected and expected in [4, 5, 6, 7]


static func _input_layout(session: Variant) -> Array:
	var layout: Array = ["roll", "pitch", "yaw", "throttle"]
	if session.gear_is_retractable():
		layout.append_array(["gear_down", "wheel_brake"])
	if session.flaps_available():
		layout.append("flap")
	return layout


static func _solver_input(axes: Array, held_registered_inputs: Array) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	for item: Variant in axes:
		values.append(float(item))
	for item: Variant in held_registered_inputs:
		values.append(float(item))
	return values


static func _airspeed(state: PackedFloat64Array) -> float:
	if state.size() != RigidBody.SIZE:
		return NAN
	return sqrt(state[RigidBody.VEL] * state[RigidBody.VEL]
		+ state[RigidBody.VEL + 1] * state[RigidBody.VEL + 1]
		+ state[RigidBody.VEL + 2] * state[RigidBody.VEL + 2])


static func _roll_deg(state: PackedFloat64Array) -> float:
	if state.size() != RigidBody.SIZE:
		return NAN
	var quaternion := PackedFloat64Array([state[RigidBody.ATT], state[RigidBody.ATT + 1],
		state[RigidBody.ATT + 2], state[RigidBody.ATT + 3]])
	var euler: PackedFloat64Array = Math3D.q_to_euler(quaternion)
	return rad_to_deg(float(euler[2])) if euler.size() >= 3 else NAN


static func _bounded_number(value: Variant, low: float, high: float, field: String,
		errors: PackedStringArray) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		errors.append("%s must be a finite number." % field)
		return 0.0
	var number: float = float(value)
	if number < low or number > high:
		errors.append("%s is outside [%s, %s]." % [field, str(low), str(high)])
	return number


static func _integral(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) \
		and absf(float(value)) <= MAX_SAFE_INTEGER and float(value) == floor(float(value))


static func _has_exact_keys(value: Variant, keys: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var expected: Array = []
	for key: Variant in keys:
		expected.append(str(key))
	var source: Dictionary = value
	if source.size() != expected.size() or not source.has_all(expected):
		return false
	for key: Variant in source.keys():
		if typeof(key) != TYPE_STRING or not expected.has(str(key)):
			return false
	return true


static func _has_exact_required_keys(value: Dictionary, required: Variant, allowed: Variant) -> bool:
	for key: Variant in required:
		if not value.has(str(key)):
			return false
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(str(key)):
			return false
	return true


static func _failure(errors: Variant) -> Dictionary:
	var packed: PackedStringArray = errors if errors is PackedStringArray else PackedStringArray(errors)
	return {"ok": false, "errors": packed}


static func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true
