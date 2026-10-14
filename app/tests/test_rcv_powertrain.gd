## RCV-05/09 power revision: real coupled dynamics, no velocity clamps or impulses.
## Verifies speed, braking, integration convergence and backend parity.
extends SceneTree

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
const DT := 1.0 / 240.0
const DRIVE := {"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}
const BRAKE := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}
var _failures := 0
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _road(_n: float, _e: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 1.0, "surface_id": "powertrain_flat_fixture"}

func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	_check("current generated model loads", bool(loaded.get("ok", false)))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var current: Dictionary = loaded.model
	var legacy: Dictionary = current.duplicate(true)
	# Historical 2026-10-14 drivetrain; all other parameters identical.
	legacy.drive_torque_per_wheel_nm = 3.0
	legacy.drive_torque_fade_rad_s = 40.0
	legacy.brake_torque_per_wheel_nm = 6.0
	var before := _accelerate(legacy, DT, 6.0)
	var after := _accelerate(current, DT, 6.0)
	_check("both full-throttle runs complete with finite coupled states", before.ok and after.ok)
	if not before.ok or not after.ok:
		quit(1)
		return
	_check("new drive more than doubles sustained flat-ground speed",
		after.speed_mps > 2.0 * before.speed_mps and after.speed_mps > 8.0,
		"old %.3f m/s, new %.3f m/s" % [before.speed_mps, after.speed_mps])
	_check("new drive reaches 3 m/s sooner under the same grip",
		after.time_to_3_mps > 0.0 and after.time_to_3_mps < before.time_to_3_mps * 0.95,
		"old %.4f s, new %.4f s" % [before.time_to_3_mps, after.time_to_3_mps])
	_check("straight acceleration remains upright without hull strikes",
		after.min_upright_cos > 0.95 and after.hull_contact_ticks == 0,
		"upright %.6f, hull ticks %d" % [after.min_upright_cos, after.hull_contact_ticks])
	var stopped := _brake(after.state, current)
	_check("full braking stops the faster vehicle without reversing or rolling over",
		stopped.ok and stopped.speed_mps < 0.1 and stopped.time_s < 2.5
		and stopped.distance_m > 0.0 and stopped.distance_m < 15.0
		and stopped.min_upright_cos > 0.90,
		"time %.3f s, distance %.3f m, residual %.4f m/s, upright %.5f" % [
			stopped.time_s, stopped.distance_m, stopped.speed_mps, stopped.min_upright_cos])
	var fine_stop := _brake(after.state, current, DT * 0.5)
	_check("240/480 Hz hard braking agrees in stopping distance and attitude",
		fine_stop.ok and stopped.ok and absf(fine_stop.distance_m - stopped.distance_m) < 0.01
		and absf(fine_stop.time_s - stopped.time_s) < 0.01
		and absf(fine_stop.min_upright_cos - stopped.min_upright_cos) < 0.001)
	var fine := _accelerate(current, DT * 0.5, 6.0)
	var position_error := INF
	var velocity_error := INF
	if fine.ok:
		position_error = absf(after.state[Vehicle.POS] - fine.state[Vehicle.POS])
		velocity_error = absf(after.speed_mps - fine.speed_mps)
	_check("240/480 Hz high-power runs converge in distance and speed",
		fine.ok and position_error < 0.03 and velocity_error < 0.01,
		"distance delta %.7f m, speed delta %.7f m/s" % [position_error, velocity_error])
	# Representative high wheel speeds, braking and reverse exercise both backends.
	var state: PackedFloat64Array = after.state
	var parity_error := 0.0
	var parity_ok := true
	for controls in [DRIVE, BRAKE, {"throttle": 1.0, "steering": 0.15, "brake": 0.0, "reverse": true}]:
		var active := Vehicle.derivative(state, current, controls, _road)
		Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE)
		var reference := Vehicle.derivative(state, current, controls, _road)
		Vehicle.set_backend_override_for_tests("")
		parity_ok = parity_ok and active.size() == Vehicle.STATE_SIZE and reference.size() == Vehicle.STATE_SIZE
		if active.size() == reference.size():
			for index in active.size():
				parity_error = maxf(parity_error, absf(active[index] - reference[index]))
	_check("active/reference derivatives agree at increased wheel speeds",
		parity_ok and parity_error < 1.0e-7, "max delta %.10f" % parity_error)
	print("RCV powertrain: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(1 if _failures > 0 else 0)

func _accelerate(model: Dictionary, dt: float, duration: float) -> Dictionary:
	var initial: Dictionary = Vehicle.initialize(model, _road, 0.0, 0.0)
	var result := {"ok": false, "state": PackedFloat64Array(), "speed_mps": 0.0,
		"time_to_3_mps": -1.0, "min_upright_cos": 1.0, "hull_contact_ticks": 0}
	if not bool(initial.get("ok", false)):
		return result
	var state: PackedFloat64Array = initial.state
	for tick in int(round(duration / dt)):
		state = Vehicle.step(state, model, DRIVE, dt, _road)
		if state.size() != Vehicle.STATE_SIZE:
			return result
		var speed := M.norm(PackedFloat64Array([state[Vehicle.VEL], state[Vehicle.VEL + 1], state[Vehicle.VEL + 2]]))
		if speed >= 3.0 and result.time_to_3_mps < 0.0:
			result.time_to_3_mps = (tick + 1) * dt
		result.min_upright_cos = minf(result.min_upright_cos, _upright(state))
		if tick % 12 == 0:
			var report := Vehicle.telemetry(state, model, _road, DRIVE)
			if not bool(report.get("ok", false)):
				return result
			if report.hull_in_contact.count(1) > 0:
				result.hull_contact_ticks += 1
		result.speed_mps = speed
	result.state = state
	result.ok = true
	return result

func _brake(initial: PackedFloat64Array, model: Dictionary, dt: float = DT) -> Dictionary:
	var state := initial.duplicate()
	var result := {"ok": false, "time_s": 0.0, "distance_m": 0.0, "speed_mps": INF, "min_upright_cos": 1.0}
	for tick in int(round(4.0 / dt)):
		state = Vehicle.step(state, model, BRAKE, dt, _road)
		if state.size() != Vehicle.STATE_SIZE:
			return result
		result.speed_mps = M.norm(PackedFloat64Array([state[Vehicle.VEL], state[Vehicle.VEL + 1], state[Vehicle.VEL + 2]]))
		result.min_upright_cos = minf(result.min_upright_cos, _upright(state))
		result.time_s = (tick + 1) * dt
		result.distance_m = state[Vehicle.POS] - initial[Vehicle.POS]
		if state[Vehicle.VEL] < -0.02:
			return result
		if result.speed_mps < 0.1:
			result.ok = true
			return result
	return result

func _upright(state: PackedFloat64Array) -> float:
	var q := PackedFloat64Array([state[6], state[7], state[8], state[9]])
	return -M.q_rotate(q, PackedFloat64Array([0.0, 0.0, -1.0]))[2]

func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print(("PASS: " if condition else "FAIL: ") + label + (" | " + detail if not detail.is_empty() else ""))
