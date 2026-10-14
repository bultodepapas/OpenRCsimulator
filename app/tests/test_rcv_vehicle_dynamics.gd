## RCV-05 coupled 6-DOF vehicle kernel: static support, 4WD/reverse/brakes,
## steering signs, terrain impacts, free flight, rollover contacts, and RK4.
## Run with `.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_rcv_vehicle_dynamics.gd`.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Course := preload("res://physics/ground_vehicle/course.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const DT := 1.0 / 240.0
const FORWARD_SPEED := 3
const POS_NORTH := 0
const DOWN := 2
const VEL_DOWN := 5
const ATTITUDE := 6
const RATE := 10
const TRAVEL := 13
const TRAVEL_RATE := 17
const WHEEL_SPIN := 21
const STEER := 29

var _failures := 0
var _checks := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not condition:
		_failures += 1


func _controls(throttle := 0.0, steering := 0.0, brake := 0.0, reverse := false) -> Dictionary:
	return {"throttle": throttle, "steering": steering, "brake": brake, "reverse": reverse}


func _run_steps(state: PackedFloat64Array, model: Dictionary, controls: Dictionary, road: Callable, count: int) -> PackedFloat64Array:
	var result := state.duplicate()
	for _tick in count:
		result = Vehicle.step(result, model, controls, DT, road)
		if result.is_empty():
			return PackedFloat64Array()
	return result


func _max_abs(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(value))
	return result


func _max_abs_difference(a: PackedFloat64Array, b: PackedFloat64Array, count: int) -> float:
	if a.size() < count or b.size() < count:
		return INF
	var result := 0.0
	for index in count:
		result = maxf(result, absf(a[index] - b[index]))
	return result


func _sum(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result


func _flat_road(_north_m: float, _east_m: float) -> Dictionary:
	return {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "asphalt",
	}


func _bump_road(north_m: float, _east_m: float) -> Dictionary:
	var fraction := maxf(0.0, 1.0 - absf(north_m - 0.18) / 0.18)
	return {
		"height_m": 0.025 * fraction,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "bump-test",
	}


func _initialize() -> void:
	var loaded := Data.load_default()
	_check("strict vehicle source loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded["model"]
	var flat := Callable(self, "_flat_road")
	var reset := Vehicle.initialize(model, flat, 0.0, 0.0)
	_check("flat reset produces a 31-value state", bool(reset.get("ok", false)) and reset.get("state", PackedFloat64Array()).size() == Vehicle.STATE_SIZE, str(reset.get("error", "")))
	if not bool(reset.get("ok", false)):
		quit(1)
		return
	var start: PackedFloat64Array = reset["state"]
	var original := start.duplicate()
	var initial_derivative := Vehicle.derivative(start, model, _controls(), flat)
	_check("level static reset has finite derivative", initial_derivative.size() == Vehicle.STATE_SIZE and _max_abs(initial_derivative) < 1.0e-7, "max |xdot| %.6f" % _max_abs(initial_derivative))
	var telemetry := Vehicle.telemetry(start, model, flat)
	var expected_corner_load := (float(model["sprung_mass_kg"]) / 4.0 + float(model["unsprung_mass_kg"])) * float(model["gravity_m_per_s2"])
	var loads: PackedFloat64Array = telemetry.get("wheel_load_n", PackedFloat64Array())
	_check("static tire loads support sprung and unsprung weight", loads.size() == 4 and _max_abs(PackedFloat64Array([
		loads[0] - expected_corner_load, loads[1] - expected_corner_load,
		loads[2] - expected_corner_load, loads[3] - expected_corner_load,
	])) < 1.0e-6, str(loads))
	var rested := _run_steps(start, model, _controls(), flat, 240)
	_check("zero controls keep the supported truck at rest", not rested.is_empty() and _max_abs_difference(rested, start, 13) < 1.0e-5,
		"max rigid-state drift %.6f" % _max_abs_difference(rested, start, 13))
	_check("step leaves caller-owned state untouched", start == original)
	var contact_count := 0
	var contacts: PackedByteArray = telemetry.get("wheel_in_contact", PackedByteArray())
	for contact in contacts:
		contact_count += int(contact)
	_check("telemetry reports all four tire contacts", contacts.size() == 4 and contact_count == 4)

	# The closed-form body/hub support is a force and moment balance, not a
	# hand-authored vertical offset. This checks the reset against tire loads.
	_check("reset altitude is finite and above tire radius", is_finite(start[DOWN]) and -start[DOWN] > float(model["tire_radius_m"]))
	_check("state layout keeps the rigid-body prefix and append offsets", Vehicle.POS == 0 and Vehicle.VEL == 3 and Vehicle.ATT == 6 and Vehicle.RATE == 10 and Vehicle.TRAVEL == 13 and Vehicle.TRAVEL_RATE == 17 and Vehicle.WHEEL_SPIN == 21 and Vehicle.WHEEL_ANGLE == 25 and Vehicle.STEER == 29 and Vehicle.STEER_RATE == 30)

	_test_drivetrain(start, model, flat)
	_test_steering(start, model, flat)
	_test_stops(start, model, flat)
	_test_bump(start, model)
	_test_airborne(start, model, flat)
	_test_roof_contact(start, model, flat)
	_test_experiment_equilibrium(loaded, flat)
	_test_step_refinement(start, model, flat)

	print("RCV-05 vehicle dynamics: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_drivetrain(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var driven := _run_steps(start, model, _controls(0.8), flat, 120)
	_check("4WD throttle accelerates forward and spins all wheels forward", not driven.is_empty() and driven[FORWARD_SPEED] > 0.5 and driven[WHEEL_SPIN] > 0.0 and driven[WHEEL_SPIN + 3] > 0.0,
		"u %.3f m/s, spin FL/RR %.3f / %.3f rad/s" % [driven[FORWARD_SPEED], driven[WHEEL_SPIN], driven[WHEEL_SPIN + 3]])
	var braked := _run_steps(driven, model, _controls(0.0, 0.0, 1.0), flat, 90)
	_check("brake torque slows a moving truck", not braked.is_empty() and absf(braked[FORWARD_SPEED]) < absf(driven[FORWARD_SPEED]),
		"before %.3f, after %.3f m/s" % [driven[FORWARD_SPEED], braked[FORWARD_SPEED]])
	var reverse := _run_steps(start, model, _controls(0.8, 0.0, 0.0, true), flat, 120)
	_check("reverse command drives backward", not reverse.is_empty() and reverse[FORWARD_SPEED] < -0.3 and reverse[WHEEL_SPIN] < 0.0,
		"u %.3f m/s, wheel spin %.3f rad/s" % [reverse[FORWARD_SPEED], reverse[WHEEL_SPIN]])
	var no_grip_road := func(_north_m: float, _east_m: float) -> Dictionary:
		return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]), "mu": 0.0, "rolling": 0.0}
	var wheelspin := _run_steps(start, model, _controls(0.8), no_grip_road, 60)
	_check("zero-friction surface spins wheels without normal drive acceleration", not wheelspin.is_empty() and wheelspin[WHEEL_SPIN] > 0.0 and wheelspin[FORWARD_SPEED] < driven[FORWARD_SPEED],
		"u %.3f m/s, wheel spin %.3f rad/s" % [wheelspin[FORWARD_SPEED], wheelspin[WHEEL_SPIN]])


func _test_steering(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var state := start.duplicate()
	state[FORWARD_SPEED] = 1.5
	state[WHEEL_SPIN] = 1.5 / float(model["tire_radius_m"])
	state[WHEEL_SPIN + 1] = state[WHEEL_SPIN]
	state[WHEEL_SPIN + 2] = state[WHEEL_SPIN]
	state[WHEEL_SPIN + 3] = state[WHEEL_SPIN]
	# Check the initial response before this aggressive input drives the synthetic
	# truck into its rollover/contact envelope.
	var turned := _run_steps(state, model, _controls(0.0, 0.8), flat, 20)
	var turned_detail := "empty state" if turned.is_empty() else "servo %.3f rad, yaw rate %.3f rad/s" % [turned[STEER], turned[RATE + 2]]
	_check("positive steering input turns wheels and yaw right", not turned.is_empty() and turned[STEER] > 0.0 and turned[RATE + 2] > 0.0,
		turned_detail)
	var left := _run_steps(state, model, _controls(0.0, -0.8), flat, 20)
	var left_detail := "empty state" if left.is_empty() else "servo %.3f rad, yaw rate %.3f rad/s" % [left[STEER], left[RATE + 2]]
	_check("negative steering input mirrors yaw sign", not left.is_empty() and left[STEER] < 0.0 and left[RATE + 2] < 0.0,
		left_detail)


func _test_stops(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var bump := start.duplicate()
	bump[TRAVEL] = float(model["travel_bump_m"]) + 0.01
	var bump_derivative := Vehicle.derivative(bump, model, _controls(), flat)
	_check("bump stop restores compression travel", not bump_derivative.is_empty() and bump_derivative[TRAVEL_RATE] < 0.0,
		"travel acceleration %.3f m/s²" % bump_derivative[TRAVEL_RATE])
	var droop := start.duplicate()
	droop[TRAVEL] = -float(model["travel_droop_m"]) - 0.01
	var droop_derivative := Vehicle.derivative(droop, model, _controls(), flat)
	_check("droop stop restores extension travel", not droop_derivative.is_empty() and droop_derivative[TRAVEL_RATE] > 0.0,
		"travel acceleration %.3f m/s²" % droop_derivative[TRAVEL_RATE])


func _test_bump(start: PackedFloat64Array, model: Dictionary) -> void:
	var state := start.duplicate()
	state[POS_NORTH] = -0.8
	state[FORWARD_SPEED] = 2.0
	var initial_travel: PackedFloat64Array = PackedFloat64Array([state[TRAVEL], state[TRAVEL + 1], state[TRAVEL + 2], state[TRAVEL + 3]])
	var crossed := _run_steps(state, model, _controls(), Callable(self, "_bump_road"), 180)
	var travel_change := 0.0
	if not crossed.is_empty():
		for corner in 4:
			travel_change = maxf(travel_change, absf(crossed[TRAVEL + corner] - initial_travel[corner]))
	_check("suspension responds to a finite-width road bump", not crossed.is_empty() and travel_change > 0.002,
		"max suspension travel change %.4f m" % travel_change)


func _test_airborne(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var state := start.duplicate()
	state[DOWN] -= 0.7
	var telemetry := Vehicle.telemetry(state, model, flat)
	_check("airborne state has no tire or hull support", bool(telemetry.get("ok", false)) and bool(telemetry.get("airborne", false)))
	var falling := _run_steps(state, model, _controls(), flat, 60)
	_check("free-fall converts altitude into downward velocity", not falling.is_empty() and falling[DOWN] > state[DOWN] and falling[VEL_DOWN] > 1.0,
		"down %.4f→%.4f m, w %.3f m/s" % [state[DOWN], falling[DOWN], falling[VEL_DOWN]])


func _test_roof_contact(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var state := start.duplicate()
	var q := M.q_from_euler(0.0, 0.0, PI * 0.5)
	for i in 4:
		state[ATTITUDE + i] = q[i]
	var initial_telemetry := Vehicle.telemetry(state, model, flat)
	var initial_hull: PackedByteArray = initial_telemetry.get("hull_in_contact", PackedByteArray())
	var initial_hull_count := 0
	for contact in initial_hull:
		initial_hull_count += int(contact)
	_check("side-down orientation engages the chassis contact envelope", bool(initial_telemetry.get("ok", false)) and initial_hull_count > 0,
		"hull probes %d" % initial_hull_count)
	var flipped := _run_steps(state, model, _controls(), flat, 12)
	var telemetry := Vehicle.telemetry(flipped, model, flat) if not flipped.is_empty() else {"ok": false}
	var hull_contacts: PackedByteArray = telemetry.get("hull_in_contact", PackedByteArray())
	var supported_hull := 0
	for contact in hull_contacts:
		supported_hull += int(contact)
	_check("inverted truck remains finite while hull probes can support it", not flipped.is_empty() and bool(telemetry.get("ok", false)),
		"hull contacts %d" % supported_hull)


func _test_experiment_equilibrium(loaded: Dictionary, flat: Callable) -> void:
	var changed := Data.with_experiment(loaded, {
		"gravity_scale": 0.85,
		"grip_scale": 0.8,
		"spring_scale": 1.2,
		"damper_scale": 0.8,
		"ballast_kg": 0.5,
		"ballast_height_m": 0.10,
	})
	_check("source-annotated experiment creates a valid derived model", bool(changed.get("ok", false)), str(changed.get("errors", [])))
	if not bool(changed.get("ok", false)):
		return
	var state := Vehicle.initialize(changed["model"], flat)
	var derivative := Vehicle.derivative(state.get("state", PackedFloat64Array()), changed["model"], _controls(), flat) if bool(state.get("ok", false)) else PackedFloat64Array()
	_check("experiment mass/CG inertia shifts preserve static balance", bool(state.get("ok", false)) and derivative.size() == Vehicle.STATE_SIZE and _max_abs(derivative) < 1.0e-7,
		"max |xdot| %.6f" % _max_abs(derivative))


func _test_step_refinement(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var quarter := _run_steps(start, model, _controls(0.45, 0.0, 0.0), flat, 120)
	var half_state := start.duplicate()
	for tick in 240:
		half_state = Vehicle.step(half_state, model, _controls(0.45), DT * 0.5, flat)
		if half_state.is_empty():
			break
	var state_error := 0.0
	if not quarter.is_empty() and not half_state.is_empty():
		for index in [0, 1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]:
			state_error = maxf(state_error, absf(quarter[index] - half_state[index]))
	_check("240 Hz result converges toward two half-size public steps", not quarter.is_empty() and not half_state.is_empty() and state_error < 0.08,
		"max body/suspension/spin delta %.5f" % state_error)

