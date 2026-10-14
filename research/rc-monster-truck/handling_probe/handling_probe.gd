extends SceneTree

## Bounded, state-initialized tire/brake handling traces. The state is seeded
## once before each trace; after that, only VehicleDynamics.step advances it.

const FIXED_HZ := 240
const DT := 1.0 / float(FIXED_HZ)
const SPEED_STOP_M_PER_S := 0.10
const MAX_BRAKE_SECONDS := 10.0
const SWERVE_SECONDS := 4.0
const INITIAL_LATERAL_SPEED_M_PER_S := 0.02
const UNIFORM_NORTH_M := 100.0
const UNIFORM_EAST_M := 100.0
const SURFACES := ["asphalt", "grass", "gravel"]
const BRAKE_INPUTS := [1.0, 0.6]
const SWERVE_PEAK := 0.75
const SWERVE_FIRST_START_S := 0.25
const SWERVE_COUNTERSTEER_START_S := 0.75
const SWERVE_COUNTERSTEER_END_S := 1.25
const RECOVERY_SLIP_LIMIT_RAD := 0.08726646259971647
const RECOVERY_YAW_RATE_LIMIT_RAD_S := 0.15
const RECOVERY_DWELL_TICKS := 60
const HEADING_VALID_MAX_TILT_DEG := 60.0
const BODY_SLIP_MIN_PLANAR_SPEED_M_PER_S := 0.5
const M := preload("res://physics/math3d.gd")

var _scenario := ""
var _solver_mode := ""
var _speed_m_per_s := 0.0
var _vehicle_path := ""
var _output_path := ""
var _solver_path := ""
var _vehicle_data_path := ""
var _course_data_path := ""
var _practice_path := ""
var _dynamics: Script
var _vehicle_data: Script
var _course_data: Script
var _vehicle_result: Dictionary
var _course_result: Dictionary
var _all_rows := PackedStringArray()
var _case_summaries: Array[Dictionary] = []


func _initialize() -> void:
	var parsed := _parse_args(OS.get_cmdline_user_args())
	if not bool(parsed.get("ok", false)):
		_fail(str(parsed.get("error", "invalid arguments")))
		return
	_scenario = str(parsed.scenario)
	_solver_mode = str(parsed.solver)
	_speed_m_per_s = float(parsed.speed)
	_vehicle_path = str(parsed.vehicle)
	_output_path = str(parsed.output)
	if FileAccess.file_exists(_output_path) or FileAccess.file_exists(_json_path()):
		_fail("refusing to replace an existing CSV or JSON result")
		return
	if not DirAccess.dir_exists_absolute(_output_path.get_base_dir()):
		_fail("output directory does not exist: " + _output_path.get_base_dir())
		return
	if not _load_sources():
		return
	if not _load_inputs():
		return
	_all_rows.append(_csv_header())
	for surface_id in SURFACES:
		if _scenario == "all" or _scenario == "brake":
			for brake_value in BRAKE_INPUTS:
				_case_summaries.append(_run_case("brake", str(surface_id), float(brake_value)))
		if _scenario == "all" or _scenario == "swerve":
			_case_summaries.append(_run_case("swerve", str(surface_id), 0.0))
	var csv_file := FileAccess.open(_output_path, FileAccess.WRITE)
	if csv_file == null:
		_fail("cannot create CSV output (error %d): %s" % [FileAccess.get_open_error(), _output_path])
		return
	for row in _all_rows:
		csv_file.store_line(row)
	csv_file.close()
	var source_state_hashes := PackedStringArray()
	for summary in _case_summaries:
		source_state_hashes.append(str(summary.get("initial_state_sha256", "")))
	var unique_initial_states := {}
	for digest in source_state_hashes:
		unique_initial_states[digest] = true
	var identity: Dictionary = _dynamics.backend_identity()
	var all_complete := true
	for summary in _case_summaries:
		all_complete = all_complete and bool(summary.get("complete", false)) and bool(summary.get("finite", false))
	var report := {
		"format": "openrc-rcv-handling-probe",
		"version": 1,
		"scenario": _scenario,
		"solver_mode": _solver_mode,
		"vehicle_path": _vehicle_path,
		"vehicle_identity": _vehicle_result.identity.duplicate(true),
		"vehicle_parameters": {
			"drive_torque_per_wheel_nm": float(_vehicle_result.model.drive_torque_per_wheel_nm),
			"drive_torque_fade_rad_s": float(_vehicle_result.model.drive_torque_fade_rad_s),
			"brake_torque_per_wheel_nm": float(_vehicle_result.model.brake_torque_per_wheel_nm),
			"brake_front_fraction": float(_vehicle_result.model.get("brake_front_fraction", 0.5)),
			"cg_height_above_chassis_datum_m": float(_vehicle_result.model.get("cg_height_above_chassis_datum_m", NAN)),
			"tire_radius_m": float(_vehicle_result.model.tire_radius_m),
		},
		"course_identity": _course_result.identity.duplicate(true),
		"backend_identity": identity.duplicate(true),
		"solver_version": str(_dynamics.SOLVER_VERSION),
		"fixed_hz": FIXED_HZ,
		"initial_conditions": {
			"protocol": "VehicleDynamics.initialize at static support, then seed body rolling velocity and pure-rolling wheel spin once; state advances only through VehicleDynamics.step",
			"forward_speed_m_per_s": _speed_m_per_s,
			"lateral_speed_m_per_s": INITIAL_LATERAL_SPEED_M_PER_S,
			"wheel_spin": "pure rolling at forward speed / tire radius",
			"pose": {"north_m": UNIFORM_NORTH_M, "east_m": UNIFORM_EAST_M, "heading_rad": 0.0, "vehicle_up_m": "computed from descriptor static support"},
			"seeded_components": ["forward velocity", "lateral velocity", "four wheel angular velocities"],
			"surface_geometry": "flat fallback course sample, held uniform; mu and rolling use the named synthetic practice-course material",
			"unique_initial_state_hashes": unique_initial_states.size(),
			"initial_state_sha256": source_state_hashes,
		},
		"control_tape": {
			"brake": {"throttle": 0.0, "steering": 0.0, "brake_inputs": BRAKE_INPUTS, "stop_speed_m_per_s": SPEED_STOP_M_PER_S},
			"swerve": {
				"throttle": 0.0,
				"brake": 0.0,
				"steering": [
					{"start_s": 0.0, "end_s": SWERVE_FIRST_START_S, "input": 0.0},
					{"start_s": SWERVE_FIRST_START_S, "end_s": SWERVE_COUNTERSTEER_START_S, "input": SWERVE_PEAK},
					{"start_s": SWERVE_COUNTERSTEER_START_S, "end_s": SWERVE_COUNTERSTEER_END_S, "input": -SWERVE_PEAK},
					{"start_s": SWERVE_COUNTERSTEER_END_S, "end_s": SWERVE_SECONDS, "input": 0.0},
				],
				"recovery_gate": {"slip_angle_deg": 5.0, "yaw_rate_rad_s": RECOVERY_YAW_RATE_LIMIT_RAD_S, "dwell_s": float(RECOVERY_DWELL_TICKS) / FIXED_HZ},
			},
			"sha256": _tape_sha256(),
		},
		"metric_validity": {
			"heading_yaw": "valid only while body tilt is at most %.1f degrees; cumulative change resets across invalid samples" % HEADING_VALID_MAX_TILT_DEG,
			"body_slip_angle": "valid only while heading is valid and body planar speed is at least %.2f m/s" % BODY_SLIP_MIN_PLANAR_SPEED_M_PER_S,
		},
		"surface_fixtures": _surface_fixtures(),
		"cases": _case_summaries,
		"complete": all_complete,
		"failure_reason": "" if all_complete else "one or more cases failed to stop or emitted invalid state/telemetry",
		"csv": {"path": _output_path, "sha256": FileAccess.get_sha256(_output_path), "rows": _all_rows.size() - 1},
		"source_paths": {
			"vehicle_dynamics": _solver_path,
			"vehicle_data": _vehicle_data_path,
			"course_data": _course_data_path,
			"practice_course": _practice_path,
		},
	}
	var json_file := FileAccess.open(_json_path(), FileAccess.WRITE)
	if json_file == null:
		_fail("cannot create JSON output (error %d): %s" % [FileAccess.get_open_error(), _json_path()])
		return
	json_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	json_file.close()
	print("RCV handling probe: scenario=%s complete=%s backend=%s cases=%d csv=%s" % [
		_scenario, str(all_complete), str(identity.get("backend", "")), _case_summaries.size(), _output_path])
	quit(0 if all_complete else 2)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var values := {}
	for arg in args:
		var split_at := arg.find("=")
		if not arg.begins_with("--") or split_at <= 2:
			return {"ok": false, "error": "expected --name=value arguments"}
		var key := arg.substr(2, split_at - 2)
		if values.has(key):
			return {"ok": false, "error": "duplicate option --" + key}
		values[key] = arg.substr(split_at + 1)
	for key in values.keys():
		if not key in ["scenario", "solver", "speed", "vehicle", "output"]:
			return {"ok": false, "error": "unknown option --" + str(key)}
	var scenario := str(values.get("scenario", ""))
	if scenario not in ["all", "brake", "swerve"]:
		return {"ok": false, "error": "--scenario must be all, brake, or swerve"}
	var solver := str(values.get("solver", "baseline"))
	if solver not in ["baseline", "current"]:
		return {"ok": false, "error": "--solver must be baseline or current"}
	var speed_text := str(values.get("speed", "10.0"))
	if not speed_text.is_valid_float() or not is_finite(speed_text.to_float()):
		return {"ok": false, "error": "--speed must be a finite number"}
	var speed := speed_text.to_float()
	if speed < 1.0 or speed > 20.0:
		return {"ok": false, "error": "--speed must be in [1, 20] m/s"}
	var output := str(values.get("output", ""))
	if output.is_empty() or output.get_extension().to_lower() != "csv":
		return {"ok": false, "error": "--output must name a fresh .csv file"}
	return {"ok": true, "scenario": scenario, "solver": solver, "speed": speed,
		"vehicle": str(values.get("vehicle", "")), "output": output}


func _load_sources() -> bool:
	var snapshot_root := "res://../research/rc-monster-truck/handling_probe/baseline_sources/"
	if _solver_mode == "baseline":
		_solver_path = ProjectSettings.globalize_path("res://physics/ground_vehicle/vehicle_dynamics.gd")
		_vehicle_data_path = ProjectSettings.globalize_path("res://physics/ground_vehicle/vehicle_data.gd")
		_course_data_path = ProjectSettings.globalize_path("res://physics/ground_vehicle/course.gd")
		_practice_path = ProjectSettings.globalize_path("res://data/ground_vehicle/practice.json")
	else:
		_solver_path = ProjectSettings.globalize_path("res://physics/ground_vehicle/vehicle_dynamics.gd")
		_vehicle_data_path = ProjectSettings.globalize_path("res://physics/ground_vehicle/vehicle_data.gd")
		_course_data_path = ProjectSettings.globalize_path(snapshot_root + "app/physics/ground_vehicle/course.gd")
		_practice_path = ProjectSettings.globalize_path(snapshot_root + "app/data/ground_vehicle/practice.json")
	_dynamics = load(_solver_path)
	_vehicle_data = load(_vehicle_data_path)
	_course_data = load(_course_data_path)
	if _dynamics == null or _vehicle_data == null or _course_data == null:
		_fail("could not load the selected/frozen solver and course source files")
		return false
	return true


func _load_inputs() -> bool:
	if _vehicle_path.is_empty():
		if _solver_mode == "baseline":
			_vehicle_path = ProjectSettings.globalize_path("res://data/vehicles/ground/mt8_bisonte.json")
		else:
			_vehicle_path = ProjectSettings.globalize_path("res://data/vehicles/ground/mt8_bisonte.json")
	_vehicle_result = _vehicle_data.load_file(_vehicle_path)
	if not bool(_vehicle_result.get("ok", false)):
		_fail("vehicle descriptor rejected: " + str(_vehicle_result.get("errors", [])))
		return false
	_course_result = _course_data.load_file(_practice_path)
	if not bool(_course_result.get("ok", false)):
		_fail("practice course rejected: " + str(_course_result.get("errors", [])))
		return false
	var model: Dictionary = _vehicle_result.model
	if absf(float(model.drive_torque_per_wheel_nm) - 4.2) > 1.0e-9 and _solver_mode == "baseline":
		_fail("baseline descriptor is not the 4.2 Nm per-wheel reference")
		return false
	if absf(float(model.drive_torque_fade_rad_s) - 100.0) > 1.0e-9 and _solver_mode == "baseline":
		_fail("baseline descriptor is not the 100 rad/s reference")
		return false
	if absf(float(model.brake_torque_per_wheel_nm) - 2.0) > 1.0e-9 and _solver_mode == "baseline":
		_fail("baseline descriptor is not the 2.0 Nm per-wheel reference")
		return false
	var backend: Dictionary = _dynamics.backend_identity()
	if str(backend.get("backend", "")) != "native":
		_fail("native backend is required for handling comparisons; active backend was " + str(backend.get("backend", "")))
		return false
	return true


func _run_case(case_scenario: String, surface_id: String, brake_value: float) -> Dictionary:
	var model: Dictionary = _vehicle_result.model
	var course: Dictionary = _course_result.course
	var surface_by_id: Dictionary = course.get("surface_by_id", {})
	if not surface_by_id.has(surface_id):
		return {"case_id": "", "complete": false, "finite": false, "failure_reason": "missing surface " + surface_id}
	var material: Dictionary = surface_by_id[surface_id]
	var mu := float(material.mu)
	var rolling := float(material.rolling)
	var road: Callable = func(north_m: float, east_m: float) -> Dictionary:
		var sample: Dictionary = _course_data.sample(course, north_m, east_m)
		sample["mu"] = mu
		sample["rolling"] = rolling
		sample["surface_id"] = surface_id
		return sample
	var initialized: Dictionary = _dynamics.initialize(model, road, UNIFORM_NORTH_M, UNIFORM_EAST_M)
	if not bool(initialized.get("ok", false)):
		return {"case_id": "", "complete": false, "finite": false,
			"failure_reason": "supported initialization failed: " + str(initialized.get("error", "unknown error"))}
	var state: PackedFloat64Array = initialized.state.duplicate()
	if state.size() != int(_dynamics.STATE_SIZE):
		return {"case_id": "", "complete": false, "finite": false, "failure_reason": "supported initializer returned an invalid state"}
	var initial_vehicle_up_m := -float(state[int(_dynamics.POS) + 2])
	state[int(_dynamics.VEL)] = _speed_m_per_s
	state[int(_dynamics.VEL) + 1] = INITIAL_LATERAL_SPEED_M_PER_S
	for corner in int(_dynamics.CORNER_COUNT):
		state[int(_dynamics.WHEEL_SPIN) + corner] = _speed_m_per_s / float(model.tire_radius_m)
	var initial_state_sha256 := _array_sha256(state)
	var initial_north := float(state[int(_dynamics.POS)])
	var initial_east := float(state[int(_dynamics.POS) + 1])
	var case_id := "%s_%s_%s" % [case_scenario, surface_id, "full" if brake_value == 1.0 else ("partial" if brake_value > 0.0 else "swerve")]
	var max_ticks := int(MAX_BRAKE_SECONDS * FIXED_HZ) if case_scenario == "brake" else int(SWERVE_SECONDS * FIXED_HZ)
	var max_abs_yaw_rate := 0.0
	var max_abs_beta_rad := 0.0
	var max_abs_v_m_per_s := 0.0
	var max_abs_wheel_slip_ratio := 0.0
	var max_abs_wheel_slip_angle_rad := 0.0
	var max_energy_j := -INF
	var min_energy_j := INF
	var initial_energy_j := NAN
	var final_energy_j := NAN
	var path_length_m := 0.0
	var previous_north := initial_north
	var previous_east := initial_east
	var previous_yaw := 0.0
	var accumulated_yaw_change := 0.0
	var max_abs_yaw_change := 0.0
	var max_lateral_displacement_m := 0.0
	var stop_tick := -1
	var recovery_first_stable_tick := -1
	var recovery_stable_ticks := 0
	var recovery_time_s := -1.0
	var max_tilt_deg := 0.0
	var complete := false
	var finite := true
	var failure_reason := ""
	var start_upright_cos := 1.0
	var case_row_start := _all_rows.size()
	var previous_heading_valid := false
	var max_wheel_contacts := 0
	var max_hull_contacts := 0
	var max_wall_contacts := 0
	var initial_wheel_contacts := -1
	var initial_hull_contacts := -1
	var initial_airborne := false
	var initial_support_valid := false
	var first_hull_contact_tick := -1
	var first_airborne_tick := -1
	var first_inverted_tick := -1
	var inverted_ticks := 0
	var heading_valid_ticks := 0
	var body_slip_valid_ticks := 0
	for tick in range(max_ticks + 1):
		var time_s := float(tick) * DT
		var controls := _controls(case_scenario, brake_value, time_s)
		var report: Dictionary = _dynamics.telemetry(state, model, road, controls)
		if not bool(report.get("ok", false)):
			finite = false
			failure_reason = "telemetry failed at tick %d: %s" % [tick, str(report.get("error", "unknown error"))]
			break
		if not _finite_state(state) or not _finite_report(report):
			finite = false
			failure_reason = "non-finite state or telemetry at tick %d" % tick
			break
		var speed := float(report.speed_m_per_s)
		var dn := float(state[int(_dynamics.POS)]) - initial_north
		var de := float(state[int(_dynamics.POS) + 1]) - initial_east
		max_lateral_displacement_m = maxf(max_lateral_displacement_m, absf(de))
		path_length_m += M.sqrt_(pow(float(state[int(_dynamics.POS)]) - previous_north, 2.0)
			+ pow(float(state[int(_dynamics.POS) + 1]) - previous_east, 2.0))
		previous_north = float(state[int(_dynamics.POS)])
		previous_east = float(state[int(_dynamics.POS) + 1])
		var q := _quaternion(state)
		var up_body := M.q_rotate(q, PackedFloat64Array([0.0, 0.0, -1.0]))
		var upright_cos := clampf(-float(up_body[2]), -1.0, 1.0)
		var tilt_deg := rad_to_deg(acos(upright_cos))
		max_tilt_deg = maxf(max_tilt_deg, tilt_deg)
		if tilt_deg > 90.0:
			inverted_ticks += 1
			if first_inverted_tick < 0:
				first_inverted_tick = tick
		if tick == 0:
			start_upright_cos = upright_cos
		var heading_valid := tilt_deg <= HEADING_VALID_MAX_TILT_DEG
		var yaw := NAN
		var yaw_rate := NAN
		var yaw_rate_valid := false
		var yaw_delta := 0.0
		if heading_valid:
			heading_valid_ticks += 1
			yaw = float(M.q_to_euler(q)[0])
			if previous_heading_valid:
				yaw_delta = wrapf(yaw - previous_yaw, -PI, PI)
				accumulated_yaw_change += yaw_delta
				yaw_rate = yaw_delta / DT
				yaw_rate_valid = true
				max_abs_yaw_change = maxf(max_abs_yaw_change, absf(accumulated_yaw_change))
				max_abs_yaw_rate = maxf(max_abs_yaw_rate, absf(yaw_rate))
			previous_yaw = yaw
		else:
			previous_heading_valid = false
			accumulated_yaw_change = 0.0
		previous_heading_valid = heading_valid
		var planar_speed := M.sqrt_(pow(float(state[int(_dynamics.VEL)]), 2.0)
			+ pow(float(state[int(_dynamics.VEL) + 1]), 2.0))
		var body_slip_valid := heading_valid and planar_speed >= BODY_SLIP_MIN_PLANAR_SPEED_M_PER_S
		var beta := NAN
		if body_slip_valid:
			body_slip_valid_ticks += 1
			beta = atan2(float(state[int(_dynamics.VEL) + 1]), float(state[int(_dynamics.VEL)]))
		var energy_j := float(report.total_energy_j)
		if not is_finite(energy_j):
			finite = false
			failure_reason = "non-finite energy at tick %d" % tick
			break
		if tick == 0:
			initial_energy_j = energy_j
		max_energy_j = maxf(max_energy_j, energy_j)
		min_energy_j = minf(min_energy_j, energy_j)
		final_energy_j = energy_j
		if body_slip_valid:
			max_abs_beta_rad = maxf(max_abs_beta_rad, absf(beta))
			max_abs_v_m_per_s = maxf(max_abs_v_m_per_s, absf(float(state[int(_dynamics.VEL) + 1])))
		max_abs_wheel_slip_ratio = maxf(max_abs_wheel_slip_ratio, _max_abs_array(report.get("wheel_slip_ratio", PackedFloat64Array())))
		max_abs_wheel_slip_angle_rad = maxf(max_abs_wheel_slip_angle_rad, _max_abs_array(report.get("wheel_slip_angle_rad", PackedFloat64Array())))
		var wheel_contacts := _count_set(report.get("wheel_in_contact", PackedByteArray()))
		var hull_contacts := _count_set(report.get("hull_in_contact", PackedByteArray()))
		var wall_contacts := int(report.get("wall_contact_count", 0))
		if tick == 0:
			initial_wheel_contacts = wheel_contacts
			initial_hull_contacts = hull_contacts
			initial_airborne = bool(report.get("airborne", false))
			initial_support_valid = wheel_contacts == int(_dynamics.CORNER_COUNT) \
				and hull_contacts == 0 and not initial_airborne
		max_wheel_contacts = maxi(max_wheel_contacts, wheel_contacts)
		max_hull_contacts = maxi(max_hull_contacts, hull_contacts)
		max_wall_contacts = maxi(max_wall_contacts, wall_contacts)
		if hull_contacts > 0 and first_hull_contact_tick < 0:
			first_hull_contact_tick = tick
		if bool(report.get("airborne", false)) and first_airborne_tick < 0:
			first_airborne_tick = tick
		_all_rows.append(_csv_row(case_id, case_scenario, surface_id, mu, rolling, brake_value,
			tick, time_s, controls, state, speed, yaw, heading_valid, yaw_rate, yaw_rate_valid,
			beta, body_slip_valid,
			path_length_m, energy_j, energy_j - initial_energy_j, report,
			wheel_contacts, hull_contacts, wall_contacts, tilt_deg))
		if case_scenario == "brake" and tick > 0 and speed <= SPEED_STOP_M_PER_S:
			stop_tick = tick
			complete = true
			break
		if case_scenario == "swerve" and time_s >= SWERVE_COUNTERSTEER_END_S:
			if heading_valid and body_slip_valid and yaw_rate_valid:
				if absf(beta) <= RECOVERY_SLIP_LIMIT_RAD and absf(yaw_rate) <= RECOVERY_YAW_RATE_LIMIT_RAD_S:
					if recovery_stable_ticks == 0:
						recovery_first_stable_tick = tick
					recovery_stable_ticks += 1
					if recovery_stable_ticks >= RECOVERY_DWELL_TICKS and recovery_time_s < 0.0:
						recovery_time_s = maxf(0.0, float(recovery_first_stable_tick) * DT - SWERVE_COUNTERSTEER_END_S)
				else:
					recovery_stable_ticks = 0
					recovery_first_stable_tick = -1
			else:
				recovery_stable_ticks = 0
				recovery_first_stable_tick = -1
		if case_scenario == "swerve" and tick == max_ticks:
			complete = true
			break
		if tick < max_ticks:
			var next_state: PackedFloat64Array = _dynamics.step(state, model, controls, DT, road)
			if next_state.size() != int(_dynamics.STATE_SIZE) or not _finite_state(next_state):
				finite = false
				failure_reason = "VehicleDynamics.step returned invalid state after tick %d" % tick
				break
			state = next_state
	if not initial_support_valid:
		complete = false
		failure_reason = "initial state did not report four supported wheels with no hull contact or airborne flag"
	if not complete and failure_reason.is_empty():
		failure_reason = "run limit reached before the stop threshold" if case_scenario == "brake" else "swerve tape incomplete"
	var final_dn := float(state[int(_dynamics.POS)]) - initial_north
	var final_de := float(state[int(_dynamics.POS) + 1]) - initial_east
	var stop_distance_m := M.sqrt_(final_dn * final_dn + final_de * final_de)
	var stop_time_s := float(stop_tick) * DT if stop_tick >= 0 else -1.0
	var final_tilt_deg := rad_to_deg(acos(clampf(-float(M.q_rotate(_quaternion(state), PackedFloat64Array([0.0, 0.0, -1.0]))[2]), -1.0, 1.0)))
	var final_yaw: Variant = float(M.q_to_euler(_quaternion(state))[0]) if final_tilt_deg <= HEADING_VALID_MAX_TILT_DEG else null
	return {
		"case_id": case_id,
		"scenario": case_scenario,
		"surface_id": surface_id,
		"mu": mu,
		"rolling": rolling,
		"initial_speed_m_per_s": _speed_m_per_s,
		"initial_lateral_speed_m_per_s": INITIAL_LATERAL_SPEED_M_PER_S,
		"initial_vehicle_up_m": initial_vehicle_up_m,
		"initial_support_initialized": true,
		"initial_state_sha256": initial_state_sha256,
		"brake_input": brake_value,
		"complete": complete,
		"finite": finite,
		"failure_reason": failure_reason,
		"sample_count": _all_rows.size() - case_row_start,
		"stop_tick": stop_tick,
		"stop_time_s": stop_time_s,
		"stop_distance_m": stop_distance_m if stop_tick >= 0 else -1.0,
		"stop_path_length_m": path_length_m if stop_tick >= 0 else -1.0,
		"path_length_m": path_length_m,
		"max_abs_yaw_rate_rad_s": max_abs_yaw_rate,
		"max_abs_body_slip_angle_deg": rad_to_deg(max_abs_beta_rad),
		"max_abs_lateral_speed_m_per_s": max_abs_v_m_per_s,
		"max_abs_wheel_slip_ratio": max_abs_wheel_slip_ratio,
		"max_abs_wheel_slip_angle_deg": rad_to_deg(max_abs_wheel_slip_angle_rad),
		"max_abs_yaw_change_rad": max_abs_yaw_change,
		"max_lateral_displacement_m": max_lateral_displacement_m,
		"max_tilt_deg": max_tilt_deg,
		"inverted_ticks": inverted_ticks,
		"first_inverted_tick": first_inverted_tick,
		"max_wheel_contacts": max_wheel_contacts,
		"max_hull_contacts": max_hull_contacts,
		"max_wall_contacts": max_wall_contacts,
		"first_hull_contact_tick": first_hull_contact_tick,
		"first_airborne_tick": first_airborne_tick,
		"heading_valid_ticks": heading_valid_ticks,
		"body_slip_valid_ticks": body_slip_valid_ticks,
		"initial_upright_cos": start_upright_cos,
		"initial_wheel_contacts": initial_wheel_contacts,
		"initial_hull_contacts": initial_hull_contacts,
		"initial_airborne": initial_airborne,
		"initial_support_valid": initial_support_valid,
		"initial_energy_j": initial_energy_j,
		"final_energy_j": final_energy_j,
		"max_energy_j": max_energy_j,
		"min_energy_j": min_energy_j,
		"max_energy_gain_from_start_j": max_energy_j - initial_energy_j,
		"energy_change_j": final_energy_j - initial_energy_j,
		"recovery_time_after_neutral_s": recovery_time_s,
		"final_yaw_rad": final_yaw,
		"final_speed_m_per_s": float(M.norm(PackedFloat64Array([state[int(_dynamics.VEL)], state[int(_dynamics.VEL) + 1], state[int(_dynamics.VEL) + 2]]))),
	}


func _controls(case_scenario: String, brake_value: float, time_s: float) -> Dictionary:
	if case_scenario == "brake":
		return {"throttle": 0.0, "steering": 0.0, "brake": brake_value, "reverse": false}
	var steering := 0.0
	if time_s >= SWERVE_FIRST_START_S and time_s < SWERVE_COUNTERSTEER_START_S:
		steering = SWERVE_PEAK
	elif time_s >= SWERVE_COUNTERSTEER_START_S and time_s < SWERVE_COUNTERSTEER_END_S:
		steering = -SWERVE_PEAK
	return {"throttle": 0.0, "steering": steering, "brake": 0.0, "reverse": false}


func _surface_fixtures() -> Dictionary:
	var result := {}
	var surfaces: Dictionary = _course_result.course.get("surface_by_id", {})
	for surface_id in SURFACES:
		var material: Dictionary = surfaces.get(surface_id, {})
		result[str(surface_id)] = {"mu": float(material.get("mu", NAN)), "rolling": float(material.get("rolling", NAN)), "source": "synthetic estimated practice-course material"}
	return result


func _csv_header() -> String:
	var names := PackedStringArray([
		"case_id", "scenario", "surface_id", "mu", "rolling", "brake_input", "steering_input",
		"tick", "time_s", "north_m", "east_m", "down_m", "speed_m_per_s", "u_m_per_s",
		"v_m_per_s", "w_m_per_s", "yaw_rad", "yaw_valid", "yaw_rate_rad_s", "yaw_rate_valid",
		"body_slip_angle_rad", "body_slip_valid",
		"path_length_m", "straight_distance_m", "lateral_displacement_m", "total_energy_j",
		"energy_change_from_start_j", "max_abs_wheel_slip_ratio", "max_abs_wheel_slip_angle_rad",
		"wheel_contact_count", "hull_contact_count", "wall_contact_count", "airborne", "tilt_deg",
	])
	for state_name in _dynamics.STATE_LAYOUT:
		names.append("state_" + str(state_name))
	return ",".join(names)


func _csv_row(case_id: String, scenario: String, surface_id: String, mu: float, rolling: float,
		brake_value: float, tick: int, time_s: float, controls: Dictionary, state: PackedFloat64Array,
		speed: float, yaw: float, yaw_valid: bool, yaw_rate: float, yaw_rate_valid: bool,
		beta: float, body_slip_valid: bool,
		path_length: float, energy_j: float, energy_delta: float, report: Dictionary,
		wheel_contacts: int, hull_contacts: int, wall_contacts: int, tilt_deg: float) -> String:
	var north := float(state[int(_dynamics.POS)])
	var east := float(state[int(_dynamics.POS) + 1])
	var dn := north - UNIFORM_NORTH_M
	var de := east - UNIFORM_EAST_M
	var columns := PackedStringArray([
		_csv(case_id), _csv(scenario), _csv(surface_id), _f(mu), _f(rolling), _f(brake_value),
		_f(float(controls.steering)), str(tick), _f(time_s), _f(north), _f(east),
		_f(float(state[int(_dynamics.POS) + 2])), _f(speed), _f(float(state[int(_dynamics.VEL)])),
		_f(float(state[int(_dynamics.VEL) + 1])), _f(float(state[int(_dynamics.VEL) + 2])),
		_optional_f(yaw, yaw_valid), str(yaw_valid), _optional_f(yaw_rate, yaw_rate_valid), str(yaw_rate_valid),
		_optional_f(beta, body_slip_valid), str(body_slip_valid), _f(path_length),
		_f(M.sqrt_(dn * dn + de * de)), _f(de),
		_f(energy_j), _f(energy_delta), _f(_max_abs_array(report.get("wheel_slip_ratio", PackedFloat64Array()))),
		_f(_max_abs_array(report.get("wheel_slip_angle_rad", PackedFloat64Array()))), str(wheel_contacts),
		str(hull_contacts), str(wall_contacts), str(bool(report.get("airborne", false))), _f(tilt_deg),
	])
	for value in state:
		columns.append(_f(float(value)))
	return ",".join(columns)


func _finite_state(state: PackedFloat64Array) -> bool:
	if state.size() != int(_dynamics.STATE_SIZE):
		return false
	for value in state:
		if not is_finite(float(value)):
			return false
	return true


func _finite_report(report: Dictionary) -> bool:
	for key in ["speed_m_per_s", "forward_speed_m_per_s", "total_energy_j"]:
		if not is_finite(float(report.get(key, NAN))):
			return false
	for key in ["wheel_load_n", "wheel_longitudinal_force_n", "wheel_lateral_force_n", "wheel_slip_ratio", "wheel_slip_angle_rad", "wheel_slip_speed_m_per_s"]:
		for value in report.get(key, PackedFloat64Array()):
			if not is_finite(float(value)):
				return false
	return true


func _max_abs_array(values: Variant) -> float:
	var maximum := 0.0
	if typeof(values) == TYPE_PACKED_FLOAT64_ARRAY:
		for value in values:
			maximum = maxf(maximum, absf(float(value)))
	return maximum


func _count_set(values: Variant) -> int:
	var count := 0
	if typeof(values) == TYPE_PACKED_BYTE_ARRAY:
		for value in values:
			if int(value) != 0:
				count += 1
	return count


func _quaternion(state: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		state[int(_dynamics.ATT)], state[int(_dynamics.ATT) + 1],
		state[int(_dynamics.ATT) + 2], state[int(_dynamics.ATT) + 3],
	])


func _array_sha256(values: PackedFloat64Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(values).to_utf8_buffer())
	return context.finish().hex_encode()


func _tape_sha256() -> String:
	var tape := {
		"fixed_hz": FIXED_HZ,
		"speed_m_per_s": _speed_m_per_s,
		"lateral_speed_seed_m_per_s": INITIAL_LATERAL_SPEED_M_PER_S,
		"brake_inputs": BRAKE_INPUTS,
		"steering": [SWERVE_FIRST_START_S, SWERVE_COUNTERSTEER_START_S, SWERVE_COUNTERSTEER_END_S, SWERVE_PEAK],
	}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(tape, "", true, true).to_utf8_buffer())
	return context.finish().hex_encode()


func _json_path() -> String:
	return _output_path.get_basename() + ".json"


func _f(value: float) -> String:
	return "%.9f" % value


func _optional_f(value: float, valid: bool) -> String:
	return _f(value) if valid and is_finite(value) else ""


func _csv(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\""


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
