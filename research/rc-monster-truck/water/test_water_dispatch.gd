## Active-dispatch regression for wet generalized loads and bounded RK4 stepping.
## Run with the pinned Godot binary: --headless --path app --script <this file>.
extends SceneTree

const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const DT := 1.0 / 240.0
const WATER_UP_M := -0.45
const WATER_DEPTH_M := 5.0
const BED_UP_M := WATER_UP_M - WATER_DEPTH_M
const SPEEDS_M_PER_S := [1.0, 8.0, 20.0]
const ABS_TOLERANCE := 2.0e-8
const REL_TOLERANCE := 2.0e-10

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	print(("PASS: " if passed else "FAIL: ") + label + ("" if detail.is_empty() else "  " + detail))
	if not passed:
		_failures += 1


func _surface(is_wet: bool) -> Dictionary:
	var result := {
		"height_m": BED_UP_M,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "same-bed",
	}
	if is_wet:
		result.merge({
			"wet_zone": true,
			"water_height_m": WATER_UP_M,
			"water_depth_m": WATER_DEPTH_M,
			"mud_fraction": 0.0,
		})
	return result


func _wet_road(_north_m: float, _east_m: float) -> Dictionary:
	return _surface(true)


func _dry_road(_north_m: float, _east_m: float) -> Dictionary:
	return _surface(false)


func _state_at_speed(model: Dictionary, speed_m_per_s: float) -> PackedFloat64Array:
	var initialized: Dictionary = Vehicle.initialize(model, Callable(self, "_dry_road"), 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		return PackedFloat64Array()
	var state: PackedFloat64Array = initialized.state.duplicate()
	# Keep the vehicle inside the water column, clear of both the mean surface and bed.
	state[Vehicle.POS + 2] = 1.5
	state[Vehicle.VEL] = speed_m_per_s
	for corner in Vehicle.CORNER_COUNT:
		state[Vehicle.WHEEL_SPIN + corner] = speed_m_per_s / float(model.tire_radius_m)
	return state


func _finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _maximum_absolute_delta(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	if left.size() != Vehicle.STATE_SIZE or right.size() != Vehicle.STATE_SIZE:
		return INF
	var maximum := 0.0
	for index in Vehicle.STATE_SIZE:
		maximum = maxf(maximum, absf(left[index] - right[index]))
	return maximum


func _maximum_tolerance_ratio(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	if left.size() != Vehicle.STATE_SIZE or right.size() != Vehicle.STATE_SIZE:
		return INF
	var maximum := 0.0
	for index in Vehicle.STATE_SIZE:
		var allowed := ABS_TOLERANCE + REL_TOLERANCE * maxf(absf(left[index]), absf(right[index]))
		maximum = maxf(maximum, absf(left[index] - right[index]) / allowed)
	return maximum


func _dispatch_case(model: Dictionary, speed_m_per_s: float) -> Dictionary:
	var state := _state_at_speed(model, speed_m_per_s)
	if state.is_empty():
		return {"ok": false, "error": "fixture state did not initialize"}
	var dry_derivative: PackedFloat64Array = Vehicle.derivative(
		state, model, Vehicle.DEFAULT_CONTROLS, Callable(self, "_dry_road"))
	var wet_derivative: PackedFloat64Array = Vehicle.derivative(
		state, model, Vehicle.DEFAULT_CONTROLS, Callable(self, "_wet_road"))
	var wet_telemetry: Dictionary = Vehicle.telemetry(
		state, model, Callable(self, "_wet_road"), Vehicle.DEFAULT_CONTROLS)
	if wet_derivative.size() != Vehicle.STATE_SIZE or dry_derivative.size() != Vehicle.STATE_SIZE \
			or not _finite(wet_derivative) or not _finite(dry_derivative) \
			or not bool(wet_telemetry.get("ok", false)):
		return {"ok": false, "error": "active derivative or telemetry failed"}
	var environment: Dictionary = wet_telemetry.environment
	return {
		"ok": true,
		"state": state,
		"dry_derivative": dry_derivative,
		"wet_derivative": wet_derivative,
		"vertical_delta": wet_derivative[Vehicle.VEL + 2] - dry_derivative[Vehicle.VEL + 2],
		"forward_delta": wet_derivative[Vehicle.VEL] - dry_derivative[Vehicle.VEL],
		"buoyancy_n": float(environment.buoyancy_n),
		"drag_power_w": float(environment.drag_power_w),
	}


func _test_active_dispatch(model: Dictionary) -> void:
	var by_backend := {}
	for backend in [Vehicle.BACKEND_NATIVE, Vehicle.BACKEND_GDSCRIPT_REFERENCE]:
		var selected: bool = Vehicle.set_backend_override_for_tests(backend)
		_check("select active backend " + backend, selected)
		if not selected:
			continue
		by_backend[backend] = {}
		for speed in SPEEDS_M_PER_S:
			var observation := _dispatch_case(model, float(speed))
			var valid: bool = bool(observation.get("ok", false))
			_check("active wet/dry derivative resolves at %.0f m/s (%s)" % [speed, backend], valid,
				str(observation.get("error", "")))
			if not valid:
				continue
			var upward_delta := float(observation.vertical_delta)
			var forward_delta := float(observation.forward_delta)
			var buoyancy := float(observation.buoyancy_n)
			var drag_power := float(observation.drag_power_w)
			_check("wet buoyancy reduces downward acceleration at %.0f m/s (%s)" % [speed, backend],
			upward_delta < -1.0e-6, "delta_down_accel=%.9f m/s^2, buoyancy=%.9f N" % [upward_delta, buoyancy])
			_check("wet drag reduces forward acceleration at %.0f m/s (%s)" % [speed, backend],
				forward_delta < -1.0e-6 and drag_power < 0.0,
			"delta_forward_accel=%.9f m/s^2, drag_power=%.9f W" % [forward_delta, drag_power])
			by_backend[backend][float(speed)] = observation.wet_derivative

	if by_backend.has(Vehicle.BACKEND_NATIVE) and by_backend.has(Vehicle.BACKEND_GDSCRIPT_REFERENCE):
		for speed in SPEEDS_M_PER_S:
			var native_derivative: PackedFloat64Array = by_backend[Vehicle.BACKEND_NATIVE].get(float(speed), PackedFloat64Array())
			var reference_derivative: PackedFloat64Array = by_backend[Vehicle.BACKEND_GDSCRIPT_REFERENCE].get(float(speed), PackedFloat64Array())
			var max_delta := _maximum_absolute_delta(native_derivative, reference_derivative)
			var ratio := _maximum_tolerance_ratio(native_derivative, reference_derivative)
			_check("full wet state derivative matches native/reference at %.0f m/s" % speed,
				ratio <= 1.0, "max_abs_delta=%.12f, max_tolerance_ratio=%.12f" % [max_delta, ratio])
			print("DISPATCH speed=%.0f m/s full_state_max_abs_delta=%.12f max_tolerance_ratio=%.12f" % [speed, max_delta, ratio])


func _test_timestep_refinement(model: Dictionary) -> void:
	var selected: bool = Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_NATIVE)
	_check("native backend selected for capped-step refinement", selected)
	if not selected:
		return
	for speed in SPEEDS_M_PER_S:
		var state := _state_at_speed(model, float(speed))
		if state.is_empty():
			_check("step fixture initializes at %.0f m/s" % speed, false)
			continue
		var road := Callable(self, "_wet_road")
		var capped: PackedFloat64Array = Vehicle.step(state, model, Vehicle.DEFAULT_CONTROLS, DT, road)
		var half: PackedFloat64Array = Vehicle.step(state, model, Vehicle.DEFAULT_CONTROLS, DT * 0.5, road)
		var two_half: PackedFloat64Array = Vehicle.step(half, model, Vehicle.DEFAULT_CONTROLS, DT * 0.5, road) if half.size() == Vehicle.STATE_SIZE else PackedFloat64Array()
		var direct_240: PackedFloat64Array = Vehicle._rk4_step(state, model, Vehicle.DEFAULT_CONTROLS, road, DT)
		var split_delta := _maximum_absolute_delta(capped, two_half)
		var direct_delta := _maximum_absolute_delta(capped, direct_240)
		var current_valid: bool = capped.size() == Vehicle.STATE_SIZE and two_half.size() == Vehicle.STATE_SIZE \
				and _finite(capped) and _finite(two_half)
		_check("480 Hz capped step and two half-steps are finite at %.0f m/s" % speed, current_valid)
		_check("480 Hz capped step agrees with two half-steps at %.0f m/s" % speed,
			current_valid and split_delta <= 1.0e-12, "max_abs_delta=%.12f" % split_delta)
		var direct_finite: bool = direct_240.size() == Vehicle.STATE_SIZE and _finite(direct_240)
		print("TIMESTEP speed=%.0f m/s capped_vs_two_half_max_abs_delta=%.12f direct_240_finite=%s direct_240_vs_capped_max_abs_delta=%s direct_240_final_u=%s capped_final_u=%s" % [
			speed, split_delta, str(direct_finite), "%.12f" % direct_delta if direct_finite else "unavailable",
			"%.12f" % direct_240[Vehicle.VEL] if direct_finite else "unavailable",
			"%.12f" % capped[Vehicle.VEL] if capped.size() == Vehicle.STATE_SIZE else "unavailable",
		])


func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	_check("default vehicle model loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded.model
	var native_ready: bool = Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_NATIVE)
	_check("pinned native v3 backend is available", native_ready)
	if not native_ready:
		quit(1)
		return
	_test_active_dispatch(model)
	_test_timestep_refinement(model)
	Vehicle.set_backend_override_for_tests("")
	print("WATER_DISPATCH summary: %d checks, %d failures" % [_checks, _failures])
	await process_frame
	quit(1 if _failures > 0 else 0)
