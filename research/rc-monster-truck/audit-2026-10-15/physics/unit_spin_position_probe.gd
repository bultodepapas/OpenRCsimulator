extends SceneTree

const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const DURATION_S := 2.0
const SPIN_RAD_PER_S := 12.0
const SPEED_NORTH := 12.0
const SPEED_EAST := 0.5


func _flat_road(_north_m: float, _east_m: float) -> Dictionary:
	return {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "spin-probe",
	}


func _controls() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}


func _integrate(state: PackedFloat64Array, model: Dictionary, road: Callable, dt: float, ticks: int) -> PackedFloat64Array:
	var next := state.duplicate()
	for _tick in ticks:
		next = Vehicle.step(next, model, _controls(), dt, road)
		if next.is_empty():
			return next
	return next


func _initialize() -> void:
	Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE)
	var loaded := Data.load_default()
	if not bool(loaded.get("ok", false)):
		push_error("vehicle model failed to load: " + str(loaded.get("errors", [])))
		quit(1)
		return
	var model: Dictionary = loaded["model"].duplicate(true)
	model["gravity_m_per_s2"] = 0.0
	var road := Callable(self, "_flat_road")
	var reset: Dictionary = Vehicle.initialize(model, road)
	if not bool(reset.get("ok", false)):
		push_error("zero-gravity spin setup failed: " + str(reset.get("error", "")))
		quit(1)
		return
	var state: PackedFloat64Array = reset["state"].duplicate()
	state[2] = -20.0
	state[3] = SPEED_NORTH
	state[4] = SPEED_EAST
	state[5] = 0.0
	state[10] = 0.0
	state[11] = 0.0
	state[12] = SPIN_RAD_PER_S
	var derivative := Vehicle.derivative(state, model, _controls(), road)
	var initial_position_rate := PackedFloat64Array([derivative[0], derivative[1], derivative[2]])
	var rates := [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]
	var ticks := [60, 120, 240]
	for index in rates.size():
		var end_state := _integrate(state, model, road, rates[index], ticks[index])
		if end_state.is_empty():
			push_error("spin integration failed at dt=" + str(rates[index]))
			quit(1)
			return
		var expected_position := PackedFloat64Array([SPEED_NORTH * DURATION_S, SPEED_EAST * DURATION_S, state[2]])
		var position_delta := PackedFloat64Array([
			end_state[0] - expected_position[0],
			end_state[1] - expected_position[1],
			end_state[2] - expected_position[2],
		])
		print("dt=%.9f ticks=%d pos=[%.12f, %.12f, %.12f] delta=[%.12f, %.12f, %.12f] |delta|=%.12f attitude_norm=%.12f" % [
			rates[index], ticks[index], end_state[0], end_state[1], end_state[2],
			position_delta[0], position_delta[1], position_delta[2],
			sqrt(position_delta[0] * position_delta[0] + position_delta[1] * position_delta[1] + position_delta[2] * position_delta[2]),
			sqrt(end_state[6] * end_state[6] + end_state[7] * end_state[7] + end_state[8] * end_state[8] + end_state[9] * end_state[9]),
		])
	print("unit_input_norm=%.12f spin_rad_s=%.6f derivative_position_rate=[%.12f, %.12f, %.12f]" % [
		sqrt(state[6] * state[6] + state[7] * state[7] + state[8] * state[8] + state[9] * state[9]),
		SPIN_RAD_PER_S, initial_position_rate[0], initial_position_rate[1], initial_position_rate[2],
	])
	quit()
