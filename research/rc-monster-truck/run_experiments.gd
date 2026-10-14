extends SceneTree
## Reproducible full-vehicle experiments using the current estimated MT8 model
## and analytical practice course. This is a research harness, not a calibrated
## vehicle or a production Session replacement.

const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const CourseData := preload("res://physics/ground_vehicle/course.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const FORMAT := "openrc-ground-vehicle-experiment"
const VERSION := 1
const DEFAULT_DURATION_S := 3.0
const MAX_DURATION_S := 15.0
const PUBLIC_HZ := 240
const INITIAL_BRAKING_SPEED_M_PER_S := 6.0
const INITIAL_BUMP_SPEED_M_PER_S := 4.0
const DROP_HEIGHT_M := 0.45
const SCENARIOS := ["braking", "bump", "drop"]
const BRAKING_RUNS := [
	{"surface_id": "asphalt", "spawn_id": "start"},
	{"surface_id": "gravel", "spawn_id": "gravel"},
	{"surface_id": "grass", "spawn_id": "grass"},
	{"surface_id": "slippery", "spawn_id": "slippery"},
]
const TELEMETRY_ARRAYS := [
	{"key": "wheel_load_n", "prefix": "wheel_load", "unit": "n"},
	{"key": "wheel_longitudinal_force_n", "prefix": "wheel_longitudinal_force", "unit": "n"},
	{"key": "wheel_slip_ratio", "prefix": "wheel_slip_ratio", "unit": ""},
	{"key": "suspension_travel_m", "prefix": "reported_travel", "unit": "m"},
]

var _error_reported := false


func _initialize() -> void:
	var parsed := _parse_options(OS.get_cmdline_user_args())
	if not bool(parsed.get("ok", false)):
		_fail(str(parsed.get("error", "invalid command line")))
		return
	var options: Dictionary = parsed.options
	var vehicle_loaded: Dictionary = VehicleData.load_default()
	if not bool(vehicle_loaded.get("ok", false)):
		_fail("vehicle data rejected: " + str(vehicle_loaded.get("errors", [])))
		return
	var course_loaded: Dictionary = CourseData.load_default()
	if not bool(course_loaded.get("ok", false)):
		_fail("practice course rejected: " + str(course_loaded.get("errors", [])))
		return
	var output_path: String = _resolve_path(str(options.output))
	if output_path.get_extension().to_lower() != "csv":
		_fail("--output must end in .csv")
		return
	var summary_path := output_path.get_basename() + ".json"
	if not DirAccess.dir_exists_absolute(output_path.get_base_dir()):
		_fail("output directory does not exist: " + output_path.get_base_dir())
		return
	if FileAccess.file_exists(output_path) or FileAccess.file_exists(summary_path):
		_fail("refusing to replace an existing CSV or summary output")
		return
	var vehicle_path := ProjectSettings.globalize_path(VehicleData.DEFAULT_PATH).simplify_path()
	var course_path := ProjectSettings.globalize_path(CourseData.DEFAULT_PATH).simplify_path()
	if output_path.to_lower() == vehicle_path.to_lower() or output_path.to_lower() == course_path.to_lower() \
		or summary_path.to_lower() == vehicle_path.to_lower() or summary_path.to_lower() == course_path.to_lower():
		_fail("output paths must not replace vehicle or course input data")
		return
	if not _run_experiment(options, vehicle_loaded, course_loaded, output_path, summary_path):
		return
	quit(0)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var options := {"scenario": "", "output": "", "duration_s": DEFAULT_DURATION_S}
	var seen: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--"):
			return {"ok": false, "error": "unexpected argument: " + arg}
		var equals_at: int = arg.find("=")
		if equals_at < 3:
			return {"ok": false, "error": "options must use --name=value syntax: " + arg}
		var name: String = arg.substr(2, equals_at - 2)
		var value: String = arg.substr(equals_at + 1)
		if not name in options:
			return {"ok": false, "error": "unknown option: --" + name}
		if seen.has(name):
			return {"ok": false, "error": "duplicate option: --" + name}
		seen[name] = true
		if value.strip_edges().is_empty():
			return {"ok": false, "error": "--%s must be nonempty" % name}
		if name == "scenario":
			if not value in SCENARIOS:
				return {"ok": false, "error": "--scenario must be braking, bump, or drop"}
			options.scenario = value
		elif name == "output":
			options.output = value
		elif name == "duration":
			if not value.is_valid_float():
				return {"ok": false, "error": "--duration must be a finite number of seconds"}
			var duration_s: float = value.to_float()
			if not is_finite(duration_s) or duration_s <= 0.0 or duration_s > MAX_DURATION_S:
				return {"ok": false, "error": "--duration must be > 0 and <= 15 seconds"}
			options.duration_s = duration_s
	if str(options.scenario).is_empty():
		return {"ok": false, "error": "missing required --scenario=braking|bump|drop"}
	if str(options.output).is_empty():
		return {"ok": false, "error": "missing required --output=<csv>"}
	var ticks: float = float(options.duration_s) * float(PUBLIC_HZ)
	if ticks < 1.0 or absf(ticks - roundf(ticks)) > 1.0e-9:
		return {"ok": false, "error": "duration * 240 must be a positive integer number of ticks"}
	return {"ok": true, "options": options}


func _run_experiment(
	options: Dictionary,
	vehicle_loaded: Dictionary,
	course_loaded: Dictionary,
	output_path: String,
	summary_path: String,
) -> bool:
	var scenario: String = str(options.scenario)
	var duration_s: float = float(options.duration_s)
	var ticks: int = roundi(duration_s * float(PUBLIC_HZ))
	var dt: float = 1.0 / float(PUBLIC_HZ)
	var model: Dictionary = vehicle_loaded.model
	var course: Dictionary = course_loaded.course
	var road := Callable(CourseData, "sample").bind(course)
	var run_definitions: Array[Dictionary] = _build_run_definitions(scenario)
	var prepared_runs: Array[Dictionary] = []
	for definition in run_definitions:
		var spawn: Dictionary = _find_spawn(course, str(definition.spawn_id))
		if spawn.is_empty():
			_fail("course is missing spawn '%s'" % str(definition.spawn_id))
			return false
		var pose: Dictionary = spawn.duplicate(true)
		pose["vehicle_up_m"] = float(pose.vehicle_up_m) + float(definition.get("start_height_offset_m", 0.0))
		var state: PackedFloat64Array = VehicleDynamics.make_state(model, pose, road)
		if state.size() != VehicleDynamics.STATE_SIZE:
			_fail("could not make supported initial state for run '%s'" % str(definition.run_id))
			return false
		var initial_speed: float = float(definition.get("initial_speed_m_per_s", 0.0))
		state[3] = initial_speed
		# Relative spin is initialized at the pure-rolling rate so braking begins
		# from a reproducible no-slip wheel/chassis state.
		for corner in 4:
			state[VehicleDynamics.WHEEL_SPIN + corner] = initial_speed / float(model.tire_radius_m)
		var controls: Dictionary = definition.controls.duplicate(true)
		var initial_road: Dictionary = CourseData.sample(course, float(state[0]), float(state[1]))
		if str(initial_road.surface_id) != str(definition.surface_id):
			_fail("spawn '%s' samples surface '%s', expected '%s'" % [str(definition.spawn_id), str(initial_road.surface_id), str(definition.surface_id)])
			return false
		prepared_runs.append({
			"definition": definition,
			"state": state,
			"controls": controls,
			"initial_road": initial_road,
			"initial_position_ned_m": PackedFloat64Array([state[0], state[1], state[2]]),
		})
	var csv := FileAccess.open(output_path, FileAccess.WRITE)
	if csv == null:
		_fail("cannot open CSV output %s (error %d)" % [output_path, FileAccess.get_open_error()])
		return false
	var header := PackedStringArray(["run_id", "scenario", "surface_id", "sample_index", "time_s"])
	header.append_array(VehicleDynamics.STATE_LAYOUT)
	header.append_array(PackedStringArray([
		"speed_m_per_s", "forward_speed_m_per_s", "airborne",
		"road_height_m", "road_mu", "road_surface_id", "total_energy_j",
		"wheel_load_fl_n", "wheel_load_fr_n", "wheel_load_rl_n", "wheel_load_rr_n",
		"wheel_longitudinal_force_fl_n", "wheel_longitudinal_force_fr_n", "wheel_longitudinal_force_rl_n", "wheel_longitudinal_force_rr_n",
		"wheel_slip_ratio_fl", "wheel_slip_ratio_fr", "wheel_slip_ratio_rl", "wheel_slip_ratio_rr",
		"telemetry_travel_fl_m", "telemetry_travel_fr_m", "telemetry_travel_rl_m", "telemetry_travel_rr_m",
	]))
	csv.store_line(",".join(header))
	if csv.get_error() != OK:
		csv.close()
		_fail("could not write CSV header")
		return false
	var run_summaries: Array[Dictionary] = []
	var total_sample_count := 0
	for run_index in prepared_runs.size():
		var prepared: Dictionary = prepared_runs[run_index]
		var definition: Dictionary = prepared.definition
		var state: PackedFloat64Array = prepared.state
		var controls: Dictionary = prepared.controls
		var expected_samples := ticks + 1
		var min_load := INF
		var max_load := -INF
		var max_speed := 0.0
		var max_abs_travel := 0.0
		var airborne_samples := 0
		for tick in range(expected_samples):
			var time_s: float = float(tick) / float(PUBLIC_HZ)
			if not _finite_state(state):
				csv.close()
				_fail("non-finite state in '%s' at sample %d" % [str(definition.run_id), tick])
				return false
			var telemetry: Dictionary = VehicleDynamics.telemetry(state, model, road)
			if not bool(telemetry.get("ok", false)):
				csv.close()
				_fail("telemetry failed in '%s' at sample %d: %s" % [str(definition.run_id), tick, str(telemetry.get("error", "unknown error"))])
				return false
			var energy_j: float = VehicleDynamics.energy(state, model, road)
			if not is_finite(energy_j) or not _finite_telemetry(telemetry):
				csv.close()
				_fail("non-finite telemetry or energy in '%s' at sample %d" % [str(definition.run_id), tick])
				return false
			var surface: Dictionary = CourseData.sample(course, state[0], state[1])
			var row := PackedStringArray([
				str(definition.run_id), scenario, str(definition.surface_id), str(tick), _num(time_s),
			])
			for component in state:
				row.append(_num(component))
			row.append_array(PackedStringArray([
				_num(float(telemetry.speed_m_per_s)),
				_num(float(telemetry.forward_speed_m_per_s)),
				"true" if bool(telemetry.airborne) else "false",
				_num(float(surface.height_m)), _num(float(surface.mu)), str(surface.surface_id), _num(energy_j),
			]))
		for descriptor: Dictionary in TELEMETRY_ARRAYS:
			var values: PackedFloat64Array = telemetry[str(descriptor.key)]
			for corner in 4:
				row.append(_num(values[corner]))
		csv.store_line(",".join(row))
			if csv.get_error() != OK:
				csv.close()
				_fail("failed writing sample %d for run '%s'" % [tick, str(definition.run_id)])
				return false
			var loads: PackedFloat64Array = telemetry.wheel_load_n
			for load in loads:
				min_load = minf(min_load, load)
				max_load = maxf(max_load, load)
			max_speed = maxf(max_speed, float(telemetry.speed_m_per_s))
			for travel in state.slice(VehicleDynamics.TRAVEL, VehicleDynamics.TRAVEL + 4):
				max_abs_travel = maxf(max_abs_travel, absf(travel))
			if bool(telemetry.airborne):
				airborne_samples += 1
			total_sample_count += 1
			if tick < ticks:
				state = VehicleDynamics.step(state, model, controls, dt, road)
				if state.size() != VehicleDynamics.STATE_SIZE:
					csv.close()
				_fail("kernel step failed in '%s' after tick %d" % [str(definition.run_id), tick])
				return false
		var final_telemetry: Dictionary = VehicleDynamics.telemetry(state, model, road)
		if not bool(final_telemetry.get("ok", false)):
			csv.close()
			_fail("final telemetry failed in '%s'" % str(definition.run_id))
			return false
		run_summaries.append({
			"run_id": str(definition.run_id),
			"spawn_id": str(definition.spawn_id),
			"surface_id": str(definition.surface_id),
			"surface_mu_at_spawn": float(prepared.initial_road.mu),
			"initial_position_ned_m": prepared.initial_position_ned_m,
			"initial_speed_m_per_s": float(definition.get("initial_speed_m_per_s", 0.0)),
			"initial_wheel_spin_rad_per_s": float(definition.get("initial_speed_m_per_s", 0.0)) / float(model.tire_radius_m),
			"initial_height_offset_m": float(definition.get("start_height_offset_m", 0.0)),
			"controls": controls,
			"sample_count": expected_samples,
			"finite_sample_count": expected_samples,
			"airborne_sample_count": airborne_samples,
			"max_speed_m_per_s": max_speed,
			"max_abs_suspension_travel_m": max_abs_travel,
			"minimum_wheel_load_n": min_load,
			"maximum_wheel_load_n": max_load,
			"final_speed_m_per_s": float(final_telemetry.speed_m_per_s),
		})
	csv.flush()
	var csv_error: Error = csv.get_error()
	csv.close()
	if csv_error != OK:
		_fail("CSV flush failed with error %d" % csv_error)
		return false
	var csv_sha256 := _sha256_file(output_path)
	if csv_sha256.is_empty():
		_fail("could not calculate CSV SHA-256")
		return false
	var vehicle_identity: Dictionary = vehicle_loaded.identity.duplicate(true)
	var course_identity: Dictionary = course_loaded.identity.duplicate(true)
	var source_vehicle_path := ProjectSettings.globalize_path(VehicleData.DEFAULT_PATH).simplify_path()
	var source_course_path := ProjectSettings.globalize_path(CourseData.DEFAULT_PATH).simplify_path()
	var summary := {
		"format": FORMAT,
		"version": VERSION,
		"complete": true,
		"status": "complete",
		"scope": "Deterministic full-vehicle software experiment using an estimated MT8 model and synthetic course; not measured or physically validated vehicle evidence.",
		"scenario": scenario,
		"public_hz": PUBLIC_HZ,
		"substeps_per_tick": int(VehicleDynamics.SUBSTEPS_PER_TICK),
		"duration_s": duration_s,
		"ticks_per_run": ticks,
		"expected_samples_per_run": ticks + 1,
		"sample_count": total_sample_count,
		"finite_sample_count": total_sample_count,
		"vehicle_identity": vehicle_identity,
		"course_identity": course_identity,
		"vehicle_path": source_vehicle_path,
		"course_path": source_course_path,
		"model_parameters": {
			"sprung_mass_kg": float(model.sprung_mass_kg),
			"unsprung_mass_kg_per_wheel": float(model.unsprung_mass_kg),
			"total_mass_kg": float(model.sprung_mass_kg) + 4.0 * float(model.unsprung_mass_kg),
			"gravity_m_per_s2": float(model.gravity_m_per_s2),
			"tire_radius_m": float(model.tire_radius_m),
			"travel_droop_m": float(model.travel_droop_m),
			"travel_bump_m": float(model.travel_bump_m),
		},
		"experiment_settings": _experiment_settings(scenario),
		"comparison_policy": "All trials use the same loaded model bytes, course bytes, fixed 240 Hz public tick, initial forward speed, wheel rolling speed, and brake command. Braking varies only the selected course spawn/surface; bump and drop are single fixed trials.",
		"runs": run_summaries,
		"csv_path": output_path,
		"csv_sha256": csv_sha256,
		"commands": _command_templates(scenario),
	}
	var summary_file := FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file == null:
		_fail("cannot open JSON summary %s (error %d)" % [summary_path, FileAccess.get_open_error()])
		return false
	summary_file.store_string(JSON.stringify(summary, "  ") + "\n")
	summary_file.flush()
	var summary_error: Error = summary_file.get_error()
	summary_file.close()
	if summary_error != OK:
		_fail("could not write JSON summary (error %d)" % summary_error)
		return false
	print("vehicle experiment complete: %s (%s, %d finite samples; metadata %s)" % [output_path, scenario, total_sample_count, summary_path])
	return true


func _build_run_definitions(scenario: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if scenario == "braking":
		for trial: Dictionary in BRAKING_RUNS:
			result.append({
				"run_id": "braking_%s" % str(trial.surface_id),
				"surface_id": str(trial.surface_id),
				"spawn_id": str(trial.spawn_id),
				"initial_speed_m_per_s": INITIAL_BRAKING_SPEED_M_PER_S,
				"controls": {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false},
			})
	elif scenario == "bump":
		result.append({
			"run_id": "bump_bump_lane",
			"surface_id": "asphalt",
			"spawn_id": "bump_lane",
			"initial_speed_m_per_s": INITIAL_BUMP_SPEED_M_PER_S,
			"controls": {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false},
		})
	else:
		result.append({
			"run_id": "drop_start",
			"surface_id": "asphalt",
			"spawn_id": "start",
			"initial_speed_m_per_s": 0.0,
			"start_height_offset_m": DROP_HEIGHT_M,
			"controls": {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false},
		})
	return result


func _experiment_settings(scenario: String) -> Dictionary:
	if scenario == "braking":
		return {"initial_speed_m_per_s": INITIAL_BRAKING_SPEED_M_PER_S, "brake": 1.0, "initial_wheel_spin": "pure rolling", "surfaces": ["asphalt", "gravel", "grass", "slippery"]}
	if scenario == "bump":
		return {"initial_speed_m_per_s": INITIAL_BUMP_SPEED_M_PER_S, "feature_id": "bump-lane-01", "throttle": 0.0}
	return {"freefall_height_offset_m": DROP_HEIGHT_M, "initial_speed_m_per_s": 0.0, "gravity_only_until_contact": true}


func _command_templates(scenario: String) -> Dictionary:
	var common := "& $Godot --headless --audio-driver Dummy --path app --script research/rc-monster-truck/run_experiments.gd -- --duration=3"
	return {
		"scenario": scenario,
		"replay": common + " --scenario=%s --output=<fresh-output.csv>" % scenario,
		"braking_surface_comparison": common + " --scenario=braking --output=<fresh-output.csv>",
		"comparison_variable": "surface_id; all braking runs share identical model/course identities, initial 6 m/s forward and pure-rolling wheel rates, and full brake input",
	}


func _find_spawn(course: Dictionary, spawn_id: String) -> Dictionary:
	for spawn: Dictionary in course.get("spawns", []):
		if str(spawn.get("id", "")) == spawn_id:
			return spawn.duplicate(true)
	return {}


func _finite_state(state: PackedFloat64Array) -> bool:
	if state.size() != VehicleDynamics.STATE_SIZE:
		return false
	for value in state:
		if not is_finite(value):
			return false
	return true


func _finite_telemetry(telemetry: Dictionary) -> bool:
	for key in ["speed_m_per_s", "forward_speed_m_per_s", "total_energy_j"]:
		if not telemetry.has(key) or not is_finite(float(telemetry[key])):
			return false
	for descriptor: Dictionary in TELEMETRY_ARRAYS:
		var values: Variant = telemetry.get(str(descriptor.key))
		if not values is PackedFloat64Array or values.size() != 4:
			return false
		for value in values:
			if not is_finite(value):
				return false
	return telemetry.has("airborne") and typeof(telemetry.airborne) == TYPE_BOOL


func _num(value: float) -> String:
	return String.num(value, 17)


func _read_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot read %s (error %d)" % [path, FileAccess.get_open_error()]}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"ok": false, "error": "could not read %s (error %d)" % [path, read_error]}
	return {"ok": true, "bytes": bytes}


func _sha256_file(path: String) -> String:
	var read: Dictionary = _read_bytes(path)
	if not bool(read.ok):
		return ""
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(read.bytes)
	return hashing.finish().hex_encode()


func _resolve_path(path: String) -> String:
	path = path.replace("\\", "/")
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.begins_with("/") or (path.length() >= 3 and path.substr(1, 1) == ":"):
		return path.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


func _fail(message: String) -> void:
	if not _error_reported:
		_error_reported = true
		printerr("ERROR: " + message)
	quit(1)
