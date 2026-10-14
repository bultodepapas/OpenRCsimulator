extends SceneTree
## RCV damper probe. Runs the supported 0.45 m drop through the public vehicle
## integrator, with the same course, neutral controls and float64 model on both
## available backends. Experimental laws are applied by changing only normalized
## damper coefficients between bounded integrator calls; production sources are
## never modified by this runner.

const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const CourseData := preload("res://physics/ground_vehicle/course.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const HZ := 240.0
const DT := 1.0 / HZ
const DROP_HEIGHT_M := 0.45
const TICKS := 480
const SETTLE_TICKS_AFTER_LANDING := 120
const CORNER_COUNT := 4
const PROFILES := [
	{"id": "symmetric_baseline", "kind": "symmetric", "compression_ratio": 1.0, "rebound_ratio": 1.0},
	{"id": "compression_biased_control", "kind": "asymmetric", "compression_ratio": 1.2, "rebound_ratio": 0.8},
	{"id": "rebound_biased_candidate", "kind": "asymmetric", "compression_ratio": 0.8, "rebound_ratio": 1.2},
	{"id": "progressive_bump_damper_10mm", "kind": "progressive_bump", "ramp_m": 0.01},
]
const STATE_KEYS := [
	"north_m", "east_m", "down_m", "u_m_per_s", "v_m_per_s", "w_m_per_s",
	"qw", "qx", "qy", "qz", "p_rad_per_s", "q_rad_per_s", "r_rad_per_s",
	"travel_fl_m", "travel_fr_m", "travel_rl_m", "travel_rr_m",
	"travel_rate_fl_m_per_s", "travel_rate_fr_m_per_s", "travel_rate_rl_m_per_s", "travel_rate_rr_m_per_s",
	"wheel_spin_fl_rad_per_s", "wheel_spin_fr_rad_per_s", "wheel_spin_rl_rad_per_s", "wheel_spin_rr_rad_per_s",
	"wheel_angle_fl_rad", "wheel_angle_fr_rad", "wheel_angle_rl_rad", "wheel_angle_rr_rad",
	"steering_right_rad", "steering_rate_right_rad_per_s",
]
const CORNER_NAMES := ["fl", "fr", "rl", "rr"]
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}

var _output_path := ""
var _error := ""
var _csv: FileAccess
var _model: Dictionary
var _road: Callable
var _trajectories: Dictionary = {}
var _case_results: Array[Dictionary] = []


func _initialize() -> void:
	var parsed := _parse_args(OS.get_cmdline_user_args())
	if not bool(parsed.get("ok", false)):
		_fail(str(parsed.get("error", "invalid arguments")))
		return
	_output_path = str(parsed.output)
	_run.call_deferred()


func _run() -> void:
	var summary_path := _output_path.get_basename() + ".json"
	if not DirAccess.dir_exists_absolute(_output_path.get_base_dir()):
		_fail("output directory does not exist: " + _output_path.get_base_dir())
		return
	if FileAccess.file_exists(_output_path) or FileAccess.file_exists(summary_path):
		_fail("refusing to replace an existing CSV or summary output")
		return
	var loaded := VehicleData.load_default()
	if not bool(loaded.get("ok", false)):
		_fail("vehicle data rejected: " + str(loaded.get("errors", [])))
		return
	var course_loaded := CourseData.load_default()
	if not bool(course_loaded.get("ok", false)):
		_fail("practice course rejected: " + str(course_loaded.get("errors", [])))
		return
	_model = loaded.model.duplicate(true)
	var course: Dictionary = course_loaded.course
	_road = func(north_m: float, east_m: float) -> Dictionary:
		return CourseData.sample(course, north_m, east_m)
	if not _baseline_controls_are_preserved():
		_fail("model no longer matches the required 5.2 Nm, 120 rad/s and 65 mm baseline")
		return
	var spawn := _find_spawn(course, "start")
	if spawn.is_empty():
		_fail("practice course has no supported start spawn")
		return
	spawn["vehicle_up_m"] = float(spawn.vehicle_up_m) + DROP_HEIGHT_M
	var start := Vehicle.make_state(_model, spawn, _road)
	if start.size() != Vehicle.STATE_SIZE:
		_fail("could not build the supported 0.45 m drop state")
		return
	var csv_error := _open_csv()
	if not csv_error.is_empty():
		_fail(csv_error)
		return
	var default_identity := Vehicle.backend_identity()
	var backend_names := PackedStringArray([Vehicle.BACKEND_GDSCRIPT_REFERENCE])
	if str(default_identity.get("backend", "")) == Vehicle.BACKEND_NATIVE:
		backend_names.append(Vehicle.BACKEND_NATIVE)
	for backend in backend_names:
		if not Vehicle.set_backend_override_for_tests(backend):
			_fail("cannot select requested backend: " + backend)
			return
		var backend_identity := Vehicle.backend_identity()
		if str(backend_identity.get("backend", "")) != backend:
			_fail("backend identity did not follow selection: " + backend)
			return
		for profile: Dictionary in PROFILES:
			var result := _run_case(start, _model, profile, backend, backend_identity)
			if not bool(result.get("ok", false)):
				_fail("case failed: %s/%s: %s" % [backend, str(profile.id), str(result.get("error", "unknown error"))])
				return
			_case_results.append(result)
			_trajectories[backend + "/" + str(profile.id)] = result.samples
			result.erase("samples")
	var restored := Vehicle.set_backend_override_for_tests("")
	if not restored:
		_fail("could not restore automatic backend selection")
		return
	var parity := _compare_backend_trajectories(backend_names)
	if not _close_csv():
		_fail("could not close CSV output")
		return
	var summary := {
		"format": "openrc-rcv-damper-drop-probe",
		"version": 1,
		"status": "complete",
		"probe": "supported practice-course start raised 0.45 m; neutral controls; 240 Hz calls; 480 ticks",
		"law_application": "The research wrapper changes normalized damping coefficients once before each public Vehicle.step call. This approximates state-dependent candidate laws at the bounded call interval; it is not a production implementation.",
		"setdown_ticks_after_first_contact": SETTLE_TICKS_AFTER_LANDING,
		"vehicle_identity": loaded.identity,
		"course_identity": course_loaded.identity,
		"required_baseline": {
			"drive_torque_per_wheel_nm": float(_model.drive_torque_per_wheel_nm),
			"drive_torque_fade_rad_s": float(_model.drive_torque_fade_rad_s),
			"cg_height_above_chassis_datum_m": float(_model.cg_height_above_chassis_datum_m),
		},
		"model": {
			"sprung_mass_kg": float(_model.sprung_mass_kg),
			"unsprung_mass_kg": float(_model.unsprung_mass_kg),
			"suspension_stiffness_n_per_m": float(_model.suspension_stiffness_n_per_m),
			"suspension_damping_n_s_per_m": float(_model.suspension_damping_n_s_per_m),
			"travel_droop_m": float(_model.travel_droop_m),
			"travel_bump_m": float(_model.travel_bump_m),
			"bump_stop_stiffness_n_per_m": float(_model.bump_stop_stiffness_n_per_m),
			"bump_stop_damping_n_s_per_m": float(_model.bump_stop_damping_n_s_per_m),
	},
	"source_sha256": _source_hashes(),
	"backend_parity": parity,
	"cases": _case_results,
	}
	var summary_file := FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file == null:
		_fail("could not open summary output: " + summary_path)
		return
	summary_file.store_string(JSON.stringify(summary, "  ") + "\n")
	summary_file.flush()
	if summary_file.get_error() != OK:
		summary_file.close()
		_fail("summary write failed")
		return
	summary_file.close()
	print("RCV damper drop probe complete: %d cases, %d/%d samples per case; CSV %s; summary %s" % [
		_case_results.size(), TICKS + 1, TICKS + 1, _output_path, summary_path,
	])
	quit(0)


func _run_case(
	start: PackedFloat64Array,
	base_model: Dictionary,
	profile: Dictionary,
	backend: String,
	backend_identity: Dictionary,
) -> Dictionary:
	var model := base_model.duplicate(true)
	var state := start.duplicate()
	var contact_tick := -1
	var contact_speed := NAN
	var peak_total_wheel_load := 0.0
	var peak_individual_wheel_load := 0.0
	var peak_abs_travel_rate := 0.0
	var max_travel := -INF
	var min_travel := INF
	var peak_suspension_force := 0.0
	var peak_suspension_plus_stop_force := 0.0
	var peak_damping_power := 0.0
	var integrated_damping_work := 0.0
	var bounce_count := 0
	var previous_airborne := true
	var mixed_rate_ticks := 0
	var min_damping_power := INF
	var energy_at_start := NAN
	var energy_at_settle := NAN
	var settle_max_abs_rate := NAN
	var settle_max_abs_travel_delta := NAN
	var samples: Array[PackedFloat64Array] = []
	for tick in range(TICKS + 1):
		model = _model_for_profile(base_model, profile, state)
		var telemetry := Vehicle.telemetry(state, model, _road, NEUTRAL)
		if not bool(telemetry.get("ok", false)):
			return {"ok": false, "error": str(telemetry.get("error", "telemetry rejected"))}
		var rates: PackedFloat64Array = state.slice(Vehicle.TRAVEL_RATE, Vehicle.TRAVEL_RATE + CORNER_COUNT)
		var travels: PackedFloat64Array = state.slice(Vehicle.TRAVEL, Vehicle.TRAVEL + CORNER_COUNT)
		var rate_min := rates[0]
		var rate_max := rates[0]
		var row_suspension: PackedFloat64Array = telemetry.suspension_force_n
		var row_loads: PackedFloat64Array = telemetry.wheel_load_n
		var load_sum := 0.0
		for corner in CORNER_COUNT:
			rate_min = minf(rate_min, rates[corner])
			rate_max = maxf(rate_max, rates[corner])
			peak_abs_travel_rate = maxf(peak_abs_travel_rate, absf(rates[corner]))
			max_travel = maxf(max_travel, travels[corner])
			min_travel = minf(min_travel, travels[corner])
			peak_suspension_force = maxf(peak_suspension_force, absf(row_suspension[corner]))
			var stop_force := Vehicle._travel_stop_force(travels[corner], rates[corner], model)
			peak_suspension_plus_stop_force = maxf(
				peak_suspension_plus_stop_force,
				absf(row_suspension[corner]) + absf(stop_force),
			)
			load_sum += row_loads[corner]
			peak_individual_wheel_load = maxf(peak_individual_wheel_load, row_loads[corner])
		if rate_min < -1.0e-9 and rate_max > 1.0e-9:
			mixed_rate_ticks += 1
		peak_total_wheel_load = maxf(peak_total_wheel_load, load_sum)
		var airborne := bool(telemetry.airborne)
		if contact_tick < 0 and not airborne:
			contact_tick = tick
			contact_speed = absf(state[Vehicle.VEL + 2])
		elif contact_tick >= 0 and not previous_airborne and airborne:
			bounce_count += 1
		previous_airborne = airborne
		var energy := float(telemetry.total_energy_j)
		if tick == 0:
			energy_at_start = energy
		if contact_tick >= 0 and tick == contact_tick + SETTLE_TICKS_AFTER_LANDING:
			energy_at_settle = energy
			settle_max_abs_rate = _max_abs_array(rates)
			var start_travel := start.slice(Vehicle.TRAVEL, Vehicle.TRAVEL + CORNER_COUNT)
			var delta := PackedFloat64Array()
			for corner in CORNER_COUNT:
				delta.append(travels[corner] - start_travel[corner])
			settle_max_abs_travel_delta = _max_abs_array(delta)
		var power := _damping_power_w(profile, base_model, state, model)
		peak_damping_power = maxf(peak_damping_power, power)
		min_damping_power = minf(min_damping_power, power)
		var row := _sample_row(backend, str(profile.id), tick, state, telemetry, model, power, integrated_damping_work)
		_csv.store_csv_line(row)
		var sample := state.duplicate()
		samples.append(sample)
		if tick == TICKS:
			break
		var next := Vehicle.step(state, model, NEUTRAL, DT, _road)
		if next.size() != Vehicle.STATE_SIZE:
			return {"ok": false, "error": "Vehicle.step returned an invalid state at tick %d" % tick}
		var midpoint := state.duplicate()
		for index in Vehicle.STATE_SIZE:
			midpoint[index] = 0.5 * (state[index] + next[index])
		var midpoint_model := _model_for_profile(base_model, profile, midpoint)
		var midpoint_power := _damping_power_w(profile, base_model, midpoint, midpoint_model)
		if not is_finite(midpoint_power) or midpoint_power < -1.0e-10:
			return {"ok": false, "error": "damper law injected energy at tick %d" % tick}
		integrated_damping_work += maxf(midpoint_power, 0.0) * DT
		state = next
	var result := {
		"ok": true,
		"backend": backend,
		"backend_identity": backend_identity,
		"profile": profile,
		"sample_count": samples.size(),
		"first_contact_tick": contact_tick,
		"first_contact_time_s": float(contact_tick) * DT if contact_tick >= 0 else -1.0,
		"first_contact_down_speed_m_per_s": contact_speed,
		"peak_total_tire_normal_load_n": peak_total_wheel_load,
		"peak_individual_tire_normal_load_n": peak_individual_wheel_load,
		"maximum_travel_m": max_travel,
		"minimum_travel_m": min_travel,
		"peak_abs_travel_rate_m_per_s": peak_abs_travel_rate,
		"peak_abs_base_suspension_force_n": peak_suspension_force,
		"peak_abs_suspension_plus_stop_force_n": peak_suspension_plus_stop_force,
		"peak_suspension_damping_power_w": peak_damping_power,
		"minimum_suspension_damping_power_w": min_damping_power,
		"integrated_suspension_and_stop_damper_work_j": integrated_damping_work,
		"post_contact_airborne_bounces": bounce_count,
		"mixed_corner_rate_ticks": mixed_rate_ticks,
		"energy_j_at_drop_start": energy_at_start,
		"energy_j_120_ticks_after_contact": energy_at_settle,
		"settle_max_abs_travel_rate_m_per_s": settle_max_abs_rate,
		"settle_max_abs_travel_delta_from_supported_pose_m": settle_max_abs_travel_delta,
		"final_down_m": state[Vehicle.POS + 2],
		"final_vertical_speed_down_m_per_s": state[Vehicle.VEL + 2],
		"samples": samples,
	}
	return result


func _model_for_profile(base_model: Dictionary, profile: Dictionary, state: PackedFloat64Array) -> Dictionary:
	var model := base_model.duplicate(true)
	var base_damping := float(base_model["suspension_damping_n_s_per_m"])
	var kind := str(profile.kind)
	if kind == "asymmetric":
		var rate := _mean(state.slice(Vehicle.TRAVEL_RATE, Vehicle.TRAVEL_RATE + CORNER_COUNT))
		var ratio := float(profile.compression_ratio) if rate >= 0.0 else float(profile.rebound_ratio)
		model["suspension_damping_n_s_per_m"] = base_damping * ratio
	elif kind == "progressive_bump":
		var travel := _mean(state.slice(Vehicle.TRAVEL, Vehicle.TRAVEL + CORNER_COUNT))
		var rate := _mean(state.slice(Vehicle.TRAVEL_RATE, Vehicle.TRAVEL_RATE + CORNER_COUNT))
		var bump := float(base_model["travel_bump_m"])
		var ramp := float(profile.ramp_m)
		var weight := 0.0
		if rate > 0.0 and ramp > 0.0:
			var x := clampf((travel - (bump - ramp)) / ramp, 0.0, 1.0)
			weight = x * x * (3.0 - 2.0 * x)
		model["suspension_damping_n_s_per_m"] = base_damping + float(base_model["bump_stop_damping_n_s_per_m"]) * weight
		# The progressive ramp carries the existing 80 N s/m bump dashpot through
		# the stop limit; clear the old threshold term to avoid applying it twice.
		model["bump_stop_damping_n_s_per_m"] = 0.0
	return model


func _damping_power_w(
	profile: Dictionary,
	base_model: Dictionary,
	state: PackedFloat64Array,
	active_model: Dictionary,
) -> float:
	var power := 0.0
	for corner in CORNER_COUNT:
		var travel := state[Vehicle.TRAVEL + corner]
		var rate := state[Vehicle.TRAVEL_RATE + corner]
		power += float(active_model["suspension_damping_n_s_per_m"]) * rate * rate
		if str(profile.kind) == "progressive_bump":
			continue
		if travel > float(base_model["travel_bump_m"]) and rate > 0.0:
			power += float(base_model["bump_stop_damping_n_s_per_m"]) * rate * rate
		elif travel < -float(base_model["travel_droop_m"]) and rate < 0.0:
			power += float(base_model["droop_stop_damping_n_s_per_m"]) * rate * rate
	return power


func _sample_row(
	backend: String,
	profile_id: String,
	tick: int,
	state: PackedFloat64Array,
	telemetry: Dictionary,
	model: Dictionary,
	power: float,
	work_j: float,
) -> PackedStringArray:
	var row := PackedStringArray([backend, profile_id, str(tick), _num(float(tick) * DT)])
	for index in STATE_KEYS.size():
		row.append(_num(state[index]))
	var forces: PackedFloat64Array = telemetry.suspension_force_n
	var loads: PackedFloat64Array = telemetry.wheel_load_n
	var contacts: PackedByteArray = telemetry.wheel_in_contact
	row.append("true" if bool(telemetry.airborne) else "false")
	row.append(_num(float(telemetry.total_energy_j)))
	row.append(_num(power))
	row.append(_num(work_j))
	row.append(_num(float(model["suspension_damping_n_s_per_m"])))
	row.append(_num(float(model["bump_stop_damping_n_s_per_m"])))
	for corner in CORNER_COUNT:
		row.append(_num(forces[corner]))
	for corner in CORNER_COUNT:
		row.append(_num(loads[corner]))
	for corner in CORNER_COUNT:
		row.append("1" if contacts[corner] else "0")
	return row


func _open_csv() -> String:
	_csv = FileAccess.open(_output_path, FileAccess.WRITE)
	if _csv == null:
		return "cannot open CSV output %s (error %d)" % [_output_path, FileAccess.get_open_error()]
	var header := PackedStringArray(["backend", "profile", "tick", "time_s"])
	header.append_array(STATE_KEYS)
	header.append_array(PackedStringArray([
		"airborne", "total_energy_j", "suspension_damping_power_w", "integrated_suspension_damper_work_j",
		"suspension_damping_n_s_per_m", "bump_stop_damping_n_s_per_m",
	]))
	for corner in CORNER_NAMES:
		header.append("suspension_force_%s_n" % corner)
	for corner in CORNER_NAMES:
		header.append("wheel_load_%s_n" % corner)
	for corner in CORNER_NAMES:
		header.append("wheel_contact_%s" % corner)
	_csv.store_csv_line(header)
	return ""


func _close_csv() -> bool:
	if _csv == null:
		return false
	_csv.flush()
	var file_error := _csv.get_error()
	_csv.close()
	return file_error == OK


func _compare_backend_trajectories(backends: PackedStringArray) -> Dictionary:
	if backends.size() < 2:
		return {"status": "not_available", "reason": "only one qualified backend was loaded"}
	var left := backends[0]
	var right := backends[1]
	var maximum_delta := 0.0
	var compared_states := 0
	for profile: Dictionary in PROFILES:
		var left_states: Array = _trajectories[left + "/" + str(profile.id)]
		var right_states: Array = _trajectories[right + "/" + str(profile.id)]
		if left_states.size() != right_states.size():
			return {"status": "failed", "reason": "sample count differs for " + str(profile.id)}
		for tick in left_states.size():
			var a: PackedFloat64Array = left_states[tick]
			var b: PackedFloat64Array = right_states[tick]
			for index in Vehicle.STATE_SIZE:
				maximum_delta = maxf(maximum_delta, absf(a[index] - b[index]))
			compared_states += 1
	return {
		"status": "pass" if maximum_delta < 2.0e-6 else "failed",
		"backends": [left, right],
		"profiles": PROFILES.map(func(profile: Dictionary) -> String: return str(profile.id)),
		"compared_state_count": compared_states,
		"maximum_absolute_state_delta": maximum_delta,
		"acceptance_tolerance": 2.0e-6,
	}


func _source_hashes() -> Dictionary:
	var paths := {
		"vehicle_dynamics_gd": "res://physics/ground_vehicle/vehicle_dynamics.gd",
		"vehicle_data_gd": "res://physics/ground_vehicle/vehicle_data.gd",
		"course_gd": "res://physics/ground_vehicle/course.gd",
		"practice_json": "res://data/ground_vehicle/practice.json",
		"mt8_vehicle_json": "res://data/vehicles/ground/mt8_bisonte.json",
		"native_kernel_hpp": "res://../research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp",
		"native_extension_cpp": "res://../research/rc-monster-truck/native/src/ground_vehicle_native.cpp",
	}
	var result := {}
	for key: String in paths:
		var path := ProjectSettings.globalize_path(str(paths[key])).simplify_path()
		result[key] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	return result


func _baseline_controls_are_preserved() -> bool:
	return absf(float(_model["drive_torque_per_wheel_nm"]) - 5.2) < 1.0e-12 \
		and absf(float(_model["drive_torque_fade_rad_s"]) - 120.0) < 1.0e-12 \
		and absf(float(_model["cg_height_above_chassis_datum_m"]) - 0.065) < 1.0e-12


func _find_spawn(course: Dictionary, spawn_id: String) -> Dictionary:
	for spawn: Dictionary in course.get("spawns", []):
		if str(spawn.get("id", "")) == spawn_id:
			return spawn.duplicate(true)
	return {}


func _mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size()) if not values.is_empty() else 0.0


func _max_abs_array(values: PackedFloat64Array) -> float:
	var maximum := 0.0
	for value in values:
		maximum = maxf(maximum, absf(value))
	return maximum


func _num(value: float) -> String:
	return String.num(value, 17)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var output := ""
	for argument in args:
		if not argument.begins_with("--output=") or not output.is_empty():
			return {"ok": false, "error": "expected one --output=<absolute .csv> argument"}
		output = argument.trim_prefix("--output=").replace("\\", "/")
	if output.get_extension().to_lower() != "csv" or not _is_absolute_path(output):
		return {"ok": false, "error": "--output must be an absolute .csv path"}
	return {"ok": true, "output": output}


func _is_absolute_path(path: String) -> bool:
	if path.begins_with("/"):
		return true
	return path.length() >= 3 and path[1] == ":" and path[2] == "/"


func _fail(message: String) -> void:
	if _csv != null:
		_csv.close()
	printerr("ERROR: " + message)
	quit(2)
