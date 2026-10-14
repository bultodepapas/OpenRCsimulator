extends SceneTree

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
const DT := 1.0 / 240.0
const DRIVE := {"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _road(_n: float, _e: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 1.0, "surface_id": "brake_audit_flat"}

func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	if not bool(loaded.get("ok", false)):
		print("LOAD_FAIL ", JSON.stringify(loaded))
		quit(1)
		return
	var base: Dictionary = loaded.model
	for hz in [240, 480]:
		var dt := 1.0 / float(hz)
		var start: PackedFloat64Array = _accelerate(base, dt)
		if start.is_empty():
			print("ACCEL_FAIL hz=", hz)
			_failures += 1
			continue
		for brake_nm in [0.8, 1.0, 1.2, 1.5, 1.8, 2.0, 2.2]:
			var model: Dictionary = base.duplicate(true)
			model.brake_torque_per_wheel_nm = brake_nm
			_run_brake(hz, dt, brake_nm, model, start, true)
			_run_brake(hz, dt, brake_nm, model, start, false)
	print("BRAKE_AUDIT failures=", _failures)
	quit(1 if _failures > 0 else 0)

func _accelerate(model: Dictionary, dt: float) -> PackedFloat64Array:
	var initialized: Dictionary = Vehicle.initialize(model, _road, 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		return PackedFloat64Array()
	var state: PackedFloat64Array = initialized.state
	for _tick in int(round(6.0 / dt)):
		state = Vehicle.step(state, model, DRIVE, dt, _road)
		if state.size() != Vehicle.STATE_SIZE:
			return PackedFloat64Array()
	return state

func _run_brake(hz: int, dt: float, brake_nm: float, model: Dictionary,
		initial: PackedFloat64Array, adaptive: bool) -> void:
	var controls := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}
	var state := initial.duplicate()
	var first_u := state[Vehicle.VEL]
	var max_yaw := 0.0
	var min_upright := 1.0
	var flip_at := -1.0
	var stop_at := -1.0
	var stop_distance := 0.0
	var stop_u := 0.0
	var sample_stride := maxi(1, int(round(0.1 / dt)))
	var max_ticks := int(round(2.5 / dt))
	var elapsed_ticks := 0
	for tick in max_ticks:
		elapsed_ticks = tick + 1
		state = _manual_step(state, model, controls, dt, adaptive)
		if state.size() != Vehicle.STATE_SIZE:
			print("STEP_FAIL hz=", hz, " brake=", brake_nm, " adaptive=", adaptive)
			_failures += 1
			return
		var yaw := _yaw(state)
		var upright := _upright(state)
		max_yaw = maxf(max_yaw, absf(yaw))
		min_upright = minf(min_upright, upright)
		if flip_at < 0.0 and state[Vehicle.VEL] < -0.02:
			flip_at = (tick + 1) * dt
		if stop_at < 0.0 and M.sqrt_(state[Vehicle.VEL] ** 2 + state[Vehicle.VEL + 1] ** 2 + state[Vehicle.VEL + 2] ** 2) < 0.1:
			stop_at = (tick + 1) * dt
			stop_distance = state[Vehicle.POS] - initial[Vehicle.POS]
			stop_u = state[Vehicle.VEL]
		if tick % sample_stride == 0 or tick == max_ticks - 1:
			var e: Dictionary = Vehicle._evaluate(state, model, controls, _road, false, adaptive)
			var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
			var forward := M.q_rotate(q, PackedFloat64Array([1.0, 0.0, 0.0]))
			var world_n := state[Vehicle.POS] - initial[Vehicle.POS]
			var world_e := state[Vehicle.POS + 1] - initial[Vehicle.POS + 1]
			var speed := M.sqrt_(state[Vehicle.VEL] ** 2 + state[Vehicle.VEL + 1] ** 2 + state[Vehicle.VEL + 2] ** 2)
			print("SAMPLE ", JSON.stringify({
				"hz": hz, "brake_nm": brake_nm, "adaptive": adaptive,
				"t_s": (tick + 1) * dt, "u": state[Vehicle.VEL], "v": state[Vehicle.VEL + 1],
				"r": state[Vehicle.RATE + 2], "yaw_rad": yaw, "forward_ne": [forward[0], forward[1]],
				"speed": speed, "upright": upright, "pos_ne": [world_n, world_e],
				"sweeps": e.get("friction_sweeps_used", -1),
				"wheel_load": e.get("wheel_load_n", PackedFloat64Array()),
				"long_force": e.get("wheel_longitudinal_force_n", PackedFloat64Array()),
				"lat_force": e.get("wheel_lateral_force_n", PackedFloat64Array()),
				"brake_torque": e.get("wheel_brake_torque_n_m", PackedFloat64Array()),
				"slip_ratio": e.get("wheel_slip_ratio", PackedFloat64Array()),
				"slip_angle_rad": e.get("wheel_slip_angle_rad", PackedFloat64Array())
			}))
		if stop_at >= 0.0 and tick * dt > stop_at + 0.2:
			break
	var final_speed := M.sqrt_(state[Vehicle.VEL] ** 2 + state[Vehicle.VEL + 1] ** 2 + state[Vehicle.VEL + 2] ** 2)
	print("SUMMARY ", JSON.stringify({
		"hz": hz, "brake_nm": brake_nm, "adaptive": adaptive,
		"u_start": first_u, "u_end": state[Vehicle.VEL], "speed_end": final_speed,
		"max_abs_yaw_rad": max_yaw, "min_upright": min_upright,
		"u_flip_at_s": flip_at, "stop_at_s": stop_at, "stop_distance_m": stop_distance,
		"stop_u_mps": stop_u, "elapsed_s": elapsed_ticks * dt
	}))

func _manual_step(state: PackedFloat64Array, model: Dictionary, controls: Dictionary,
		dt: float, adaptive: bool) -> PackedFloat64Array:
	var k1 := _manual_derivative(state, model, controls, adaptive)
	var k2 := _manual_derivative(_axpy(state, dt * 0.5, k1), model, controls, adaptive)
	var k3 := _manual_derivative(_axpy(state, dt * 0.5, k2), model, controls, adaptive)
	var k4 := _manual_derivative(_axpy(state, dt, k3), model, controls, adaptive)
	if k1.is_empty() or k2.is_empty() or k3.is_empty() or k4.is_empty():
		return PackedFloat64Array()
	var next := state.duplicate()
	for i in next.size():
		next[i] += dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	var q := M.q_normalized(PackedFloat64Array([next[Vehicle.ATT], next[Vehicle.ATT + 1], next[Vehicle.ATT + 2], next[Vehicle.ATT + 3]]))
	for i in 4:
		next[Vehicle.ATT + i] = q[i]
	return next

func _manual_derivative(state: PackedFloat64Array, model: Dictionary, controls: Dictionary, adaptive: bool) -> PackedFloat64Array:
	var evaluated: Dictionary = Vehicle._evaluate(state, model, controls, _road, false, adaptive)
	if not bool(evaluated.get("ok", false)):
		return PackedFloat64Array()
	var accel: PackedFloat64Array = evaluated.generalized_acceleration
	var result := PackedFloat64Array()
	result.resize(Vehicle.STATE_SIZE)
	var velocity := PackedFloat64Array([state[Vehicle.VEL], state[Vehicle.VEL + 1], state[Vehicle.VEL + 2]])
	var rate := PackedFloat64Array([state[Vehicle.RATE], state[Vehicle.RATE + 1], state[Vehicle.RATE + 2]])
	var accel_body := PackedFloat64Array([accel[0], accel[1], accel[2]])
	var velocity_rate := M.sub(accel_body, M.cross(rate, velocity))
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	var position_rate := M.q_rotate(q, velocity)
	for i in 3:
		result[Vehicle.POS + i] = position_rate[i]
		result[Vehicle.VEL + i] = velocity_rate[i]
		result[Vehicle.RATE + i] = accel[3 + i]
	for i in 4:
		var qdot := M.q_mul(q, M.quat(0.0, rate[0], rate[1], rate[2]))
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

func _upright(state: PackedFloat64Array) -> float:
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	return -M.q_rotate(q, PackedFloat64Array([0.0, 0.0, -1.0]))[2]
