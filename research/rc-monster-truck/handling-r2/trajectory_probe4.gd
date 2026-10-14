extends SceneTree

## Isolated braking-contact trajectory comparison against a frozen evaluator.
## Only the cloned evaluator runs; runtime and native sources are read-only.

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
const SOURCE_PATH := "res://physics/ground_vehicle/vehicle_dynamics.gd"
const DT := 1.0 / 240.0
const SPEED_MPS := 9.8872212131554
const BRAKE_NM := 1.2
const DRIVE := {"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}
const BRAKE := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}
const BASELINE_ARG := "--handling-baseline="
const SOURCE_ARG := "--handling-source="

const EUCLIDEAN_BLOCK := """
			var trial_norm := M.sqrt_(trial_long * trial_long + trial_lateral * trial_lateral)
			var force_limit := maxf(0.0, float(contact["mu_load"]))
			if trial_norm > force_limit and trial_norm > 0.0:
				var ratio := force_limit / trial_norm
				trial_long *= ratio
				trial_lateral *= ratio
"""
const METRIC_BLOCK := """
			var force_limit := maxf(0.0, float(contact["mu_load"]))
			var projected := _project_contact_metric(w00, w01, w10, w11,
				trial_long, trial_lateral, force_limit)
			trial_long = projected[0]
			trial_lateral = projected[1]
"""
const KINETIC_BLOCK := """
			var trial_norm := M.sqrt_(trial_long * trial_long + trial_lateral * trial_lateral)
			var force_limit := maxf(0.0, float(contact["mu_load"]))
			if trial_norm > force_limit and trial_norm > 0.0:
				var slip: PackedFloat64Array = contact["slip"]
				var slip_norm := M.sqrt_(slip[0] * slip[0] + slip[1] * slip[1])
				if slip_norm > 1.0e-9:
					trial_long = -force_limit * slip[0] / slip_norm
					trial_lateral = -force_limit * slip[1] / slip_norm
				else:
					var ratio := force_limit / trial_norm
					trial_long *= ratio
					trial_lateral *= ratio
"""

func _initialize() -> void:
	_run.call_deferred()

func _road(_north: float, _east: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 1.0, "surface_id": "handling_r2_flat"}

func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	var source_path := ""
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with(BASELINE_ARG):
			loaded = Data.load_file(str(argument).substr(BASELINE_ARG.length()))
		elif str(argument).begins_with(SOURCE_ARG):
			source_path = str(argument).substr(SOURCE_ARG.length())
	if source_path.is_empty():
		_fail("frozen source path argument is required")
		return
	if not bool(loaded.get("ok", false)):
		_fail("vehicle data failed to load: " + JSON.stringify(loaded))
		return
	var base: Dictionary = loaded.model.duplicate(true)
	base.brake_torque_per_wheel_nm = BRAKE_NM
	var initialized: Dictionary = Vehicle.initialize(base, _road, 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		_fail("initialization failed: " + JSON.stringify(initialized))
		return
	var straight: PackedFloat64Array = initialized.state.duplicate()
	straight[Vehicle.VEL] = SPEED_MPS
	for corner in 4:
		straight[Vehicle.WHEEL_SPIN + corner] = SPEED_MPS / float(base.tire_radius_m)
	var source := FileAccess.get_file_as_string(source_path)
	if source.is_empty():
		_fail("could not read frozen evaluator source: " + source_path)
		return
	var outputs: Array[Dictionary] = []
	for case_name in ["metric256"]:
		var kernel := _make_kernel(source, case_name)
		if kernel == null:
			_fail("could not compile evaluator clone: " + case_name)
			return
		var adaptive: bool = case_name == "metric256"
		var starts: Array[Dictionary] = [{"name": "exact_symmetric", "state": straight.duplicate()}]
		if case_name == "metric256":
			for lateral_speed in [0.05, -0.05]:
				var perturbed := straight.duplicate()
				perturbed[Vehicle.VEL + 1] = lateral_speed
				starts.append({"name": "lateral_%+.2f_mps" % lateral_speed, "state": perturbed})
		var runs: Array[Dictionary] = []
		for start in starts:
			runs.append({"start_name": start.name,
				"result": _case(kernel, case_name, base, start.state, adaptive)})
		outputs.append({"name": case_name, "adaptive_early_out": adaptive, "runs": runs})
		print("CASE ", JSON.stringify(outputs[-1]))
	var result := {
		"vehicle_descriptor_identity": loaded.get("identity", {}),
		"vehicle_drive_parameters": {"drive_torque_per_wheel_nm": base.drive_torque_per_wheel_nm,
			"drive_torque_fade_rad_s": base.drive_torque_fade_rad_s,
			"brake_torque_per_wheel_nm": base.brake_torque_per_wheel_nm},
		"trajectory_evaluator": "Frozen GDScript source clone; manual RK4 calls clone._evaluate directly",
		"native_evaluator_used": false,
		"frequency_hz": 240,
		"fixture": "flat mu=0.85, rolling=1.0; 9.887221 m/s straight braking; four matched wheel speeds",
		"brake_torque_per_wheel_nm": BRAKE_NM,
		"sources": ["metric256: mobility-metric projection, cap 256, adaptive convergence at 1e-6 N / N·m"],
		"cases": outputs,
	}
	print("RESULT_JSON ", JSON.stringify(result))
	quit(0)

func _make_kernel(source: String, case_name: String) -> GDScript:
	var code := source
	var cap := 6
	if case_name.ends_with("64"):
		cap = 64
	elif case_name.ends_with("128"):
		cap = 128
	elif case_name.ends_with("256"):
		cap = 256
	code = code.replace("const FRICTION_SWEEPS := 6", "const FRICTION_SWEEPS := %d" % cap)
	if case_name.begins_with("metric"):
		code = code.replace(EUCLIDEAN_BLOCK, METRIC_BLOCK)
	if case_name.begins_with("metric"):
		code = code.replace("const FRICTION_CONVERGENCE_FORCE_TOLERANCE_N := 0.001",
			"const FRICTION_CONVERGENCE_FORCE_TOLERANCE_N := 1.0e-6")
		code = code.replace("const BRAKE_CONVERGENCE_TORQUE_TOLERANCE_N_M := 0.001",
			"const BRAKE_CONVERGENCE_TORQUE_TOLERANCE_N_M := 1.0e-6")
	code = code.replace("\"wheel_slip_speed_m_per_s\": tire_slip_speed,",
		"\"wheel_slip_speed_m_per_s\": tire_slip_speed,\n\t\t\"probe_slip_long\": tire_slip_long,\n\t\t\"probe_slip_lateral\": tire_slip_lat,")
	code += """

static func _project_contact_metric(w00: float, w01: float, w10: float, w11: float,
		unconstrained_x: float, unconstrained_y: float, limit: float) -> PackedFloat64Array:
	var unconstrained_norm := sqrt(unconstrained_x * unconstrained_x + unconstrained_y * unconstrained_y)
	if unconstrained_norm <= limit:
		return PackedFloat64Array([unconstrained_x, unconstrained_y])
	if limit <= 0.0:
		return PackedFloat64Array([0.0, 0.0])
	# KKT multiplier for min .5 f^T W f - b^T f, ||f|| <= limit,
	# where b=W*unconstrained. This is the constrained mass-metric projection.
	var b0 := w00 * unconstrained_x + w01 * unconstrained_y
	var b1 := w10 * unconstrained_x + w11 * unconstrained_y
	var lo := 0.0
	var hi := maxf(maxf(w00, w11), maxf(absf(w01), absf(w10)))
	hi = maxf(hi, 1.0e-12)
	for _grow in 80:
		var trial := _metric_candidate(w00, w01, w10, w11, b0, b1, hi)
		if M.sqrt_(trial[0] * trial[0] + trial[1] * trial[1]) <= limit:
			break
		hi *= 2.0
	for _bisect in 56:
		var mid := 0.5 * (lo + hi)
		var trial := _metric_candidate(w00, w01, w10, w11, b0, b1, mid)
		if M.sqrt_(trial[0] * trial[0] + trial[1] * trial[1]) > limit:
			lo = mid
		else:
			hi = mid
	return _metric_candidate(w00, w01, w10, w11, b0, b1, hi)

static func _metric_candidate(w00: float, w01: float, w10: float, w11: float,
		b0: float, b1: float, lambda: float) -> PackedFloat64Array:
	var a00 := w00 + lambda
	var a11 := w11 + lambda
	var determinant := a00 * a11 - w01 * w10
	if determinant <= 0.0:
		return PackedFloat64Array([0.0, 0.0])
	return PackedFloat64Array([(a11 * b0 - w01 * b1) / determinant,
		(-w10 * b0 + a00 * b1) / determinant])
"""
	var script := GDScript.new()
	script.source_code = code
	if script.reload() != OK:
		print("COMPILE_ERROR ", case_name, " ", script.get_error())
		return null
	return script

func _case(kernel: GDScript, name: String, model: Dictionary, start: PackedFloat64Array,
		adaptive: bool) -> Dictionary:
	var initial_eval: Dictionary = kernel.call("_evaluate", start, model, BRAKE, _road, false, adaptive)
	if not bool(initial_eval.get("ok", false)):
		return {"error": "initial evaluation failed: " + str(initial_eval.get("error", "unknown"))}
	var slip_long: PackedFloat64Array = initial_eval.get("probe_slip_long", PackedFloat64Array())
	var slip_lat: PackedFloat64Array = initial_eval.get("probe_slip_lateral", PackedFloat64Array())
	var friction_power := 0.0
	var signed_slip_force := PackedFloat64Array()
	signed_slip_force.resize(4)
	for corner in 4:
		signed_slip_force[corner] = (initial_eval.wheel_longitudinal_force_n[corner] * slip_long[corner]
			+ initial_eval.wheel_lateral_force_n[corner] * slip_lat[corner])
		friction_power += signed_slip_force[corner]
	var initial := {
		"yaw_accel_rad_s2": initial_eval.generalized_acceleration[5],
		"lateral_accel_m_s2": initial_eval.generalized_acceleration[1],
		"wheel_load_n_fl_fr_rl_rr": initial_eval.wheel_load_n,
		"long_force_n_fl_fr_rl_rr": initial_eval.wheel_longitudinal_force_n,
		"lat_force_n_fl_fr_rl_rr": initial_eval.wheel_lateral_force_n,
		"brake_torque_nm_fl_fr_rl_rr": initial_eval.wheel_brake_torque_n_m,
		"patch_slip_long_mps_fl_fr_rl_rr": slip_long,
		"patch_slip_lateral_mps_fl_fr_rl_rr": slip_lat,
		"slip_force_power_w_per_corner": signed_slip_force,
		"sum_slip_force_power_w": friction_power,
		"sweeps": initial_eval.friction_sweeps_used,
	}
	var state := start.duplicate()
	var max_yaw := absf(_yaw(state))
	var max_lateral_speed := absf(state[Vehicle.VEL + 1])
	var max_abs_yaw_rate := absf(state[Vehicle.RATE + 2])
	var peak_yaw_accel := absf(initial_eval.generalized_acceleration[5])
	var peak_sweeps := int(initial_eval.friction_sweeps_used)
	var max_positive_slip_power := 0.0
	var sample_points: Array[Dictionary] = []
	for tick in int(round(1.8 / DT)):
		state = _manual_step(kernel, state, model, DT, adaptive)
		if state.size() != Vehicle.STATE_SIZE:
			return {"error": "trajectory failed"}
		var evaluation: Dictionary = kernel.call("_evaluate", state, model, BRAKE, _road, false, adaptive)
		if not bool(evaluation.get("ok", false)):
			return {"error": "sample evaluation failed: " + str(evaluation.get("error", "unknown"))}
		max_yaw = maxf(max_yaw, absf(_yaw(state)))
		max_lateral_speed = maxf(max_lateral_speed, absf(state[Vehicle.VEL + 1]))
		max_abs_yaw_rate = maxf(max_abs_yaw_rate, absf(state[Vehicle.RATE + 2]))
		peak_yaw_accel = maxf(peak_yaw_accel, absf(evaluation.generalized_acceleration[5]))
		peak_sweeps = maxi(peak_sweeps, int(evaluation.friction_sweeps_used))
		var point_slip_long: PackedFloat64Array = evaluation.get("probe_slip_long", PackedFloat64Array())
		var point_slip_lat: PackedFloat64Array = evaluation.get("probe_slip_lateral", PackedFloat64Array())
		var point_power := 0.0
		for corner in 4:
			point_power += evaluation.wheel_longitudinal_force_n[corner] * point_slip_long[corner]
			point_power += evaluation.wheel_lateral_force_n[corner] * point_slip_lat[corner]
		max_positive_slip_power = maxf(max_positive_slip_power, point_power)
		if tick + 1 in [1, 6, 24, 48]:
			sample_points.append({"t_s": float(tick + 1) * DT,
				"yaw_accel_rad_s2": evaluation.generalized_acceleration[5],
				"slip_force_power_w": point_power,
				"wheel_load_n": evaluation.wheel_load_n,
				"long_force_n": evaluation.wheel_longitudinal_force_n,
				"lat_force_n": evaluation.wheel_lateral_force_n,
				"patch_slip_long_mps": point_slip_long,
				"patch_slip_lateral_mps": point_slip_lat})
		if sqrt(state[Vehicle.VEL] ** 2 + state[Vehicle.VEL + 1] ** 2 + state[Vehicle.VEL + 2] ** 2) < 0.1:
			break
	return {
		"initial_force_diagnostic": initial,
		"early_trajectory_force_samples": sample_points,
		"trajectory": {
			"start_u_mps": start[Vehicle.VEL], "start_v_mps": start[Vehicle.VEL + 1],
			"start_yaw_rad": _yaw(start), "end_u_mps": state[Vehicle.VEL],
			"end_v_mps": state[Vehicle.VEL + 1], "end_yaw_rad": _yaw(state),
			"max_abs_yaw_rad": max_yaw, "max_abs_yaw_deg": rad_to_deg(max_yaw),
			"max_abs_lateral_speed_mps": max_lateral_speed,
			"max_abs_yaw_rate_rad_s": max_abs_yaw_rate, "peak_abs_yaw_accel_rad_s2": peak_yaw_accel,
			"peak_sweeps_used": peak_sweeps, "max_positive_slip_force_power_w": max_positive_slip_power,
		},
		"evaluator": "GDScript reference clone direct _evaluate, manual RK4",
		"adaptive_early_out": adaptive,
	}

func _manual_step(kernel: GDScript, state: PackedFloat64Array, model: Dictionary, dt: float,
		adaptive: bool) -> PackedFloat64Array:
	var k1 := _derivative(kernel, state, model, adaptive)
	var k2 := _derivative(kernel, _axpy(state, dt * 0.5, k1), model, adaptive)
	var k3 := _derivative(kernel, _axpy(state, dt * 0.5, k2), model, adaptive)
	var k4 := _derivative(kernel, _axpy(state, dt, k3), model, adaptive)
	if k1.is_empty() or k2.is_empty() or k3.is_empty() or k4.is_empty():
		return PackedFloat64Array()
	var next := state.duplicate()
	for i in next.size():
		next[i] += dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	var q := M.q_normalized(PackedFloat64Array([next[Vehicle.ATT], next[Vehicle.ATT + 1], next[Vehicle.ATT + 2], next[Vehicle.ATT + 3]]))
	for i in 4:
		next[Vehicle.ATT + i] = q[i]
	return next

func _derivative(kernel: GDScript, state: PackedFloat64Array, model: Dictionary,
		adaptive: bool) -> PackedFloat64Array:
	var evaluated: Dictionary = kernel.call("_evaluate", state, model, BRAKE, _road, false, adaptive)
	if not bool(evaluated.get("ok", false)):
		return PackedFloat64Array()
	var accel: PackedFloat64Array = evaluated.generalized_acceleration
	var result := PackedFloat64Array()
	result.resize(Vehicle.STATE_SIZE)
	var velocity := PackedFloat64Array([state[Vehicle.VEL], state[Vehicle.VEL + 1], state[Vehicle.VEL + 2]])
	var rate := PackedFloat64Array([state[Vehicle.RATE], state[Vehicle.RATE + 1], state[Vehicle.RATE + 2]])
	var velocity_rate := M.sub(PackedFloat64Array([accel[0], accel[1], accel[2]]), M.cross(rate, velocity))
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	var position_rate := M.q_rotate(q, velocity)
	for i in 3:
		result[Vehicle.POS + i] = position_rate[i]
		result[Vehicle.VEL + i] = velocity_rate[i]
		result[Vehicle.RATE + i] = accel[3 + i]
	var qdot := M.q_mul(q, M.quat(0.0, rate[0], rate[1], rate[2]))
	for i in 4:
		result[Vehicle.ATT + i] = 0.5 * qdot[i]
		result[Vehicle.TRAVEL + i] = state[Vehicle.TRAVEL_RATE + i]
		result[Vehicle.TRAVEL_RATE + i] = accel[6 + i]
		result[Vehicle.WHEEL_SPIN + i] = accel[10 + i]
		result[Vehicle.WHEEL_ANGLE + i] = state[Vehicle.WHEEL_SPIN + i]
	result[Vehicle.STEER] = state[Vehicle.STEER_RATE]
	result[Vehicle.STEER_RATE] = float(evaluated.steering_acceleration_rad_per_s2)
	return result

func _axpy(a: PackedFloat64Array, scale: float, b: PackedFloat64Array) -> PackedFloat64Array:
	var result := a.duplicate()
	for i in result.size():
		result[i] += scale * b[i]
	return result

func _yaw(state: PackedFloat64Array) -> float:
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	var forward := M.q_rotate(q, PackedFloat64Array([1.0, 0.0, 0.0]))
	return M.atan2_(forward[1], forward[0])

func _fail(message: String) -> void:
	print("FAIL ", message)
	quit(1)
