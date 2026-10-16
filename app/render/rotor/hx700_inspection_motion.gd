# HELI-26a: presentation-time motion only. No physical servo response is claimed.
extends RefCounted

const LIMITS := [13.0, 10.0, 10.0, 20.0]
# Two cascaded first-order filters, solved analytically for a held demand.
# Both stages remain inside the input bounds, including interrupted reversals.
const CONTROL_RATE := 14.0
const ROTATION_RATE := 6.0
const PHASE_LIMIT := 1.0e6

var demand := PackedFloat64Array([0, 0, 0, 0])
var inputs := PackedFloat64Array([0, 0, 0, 0, 0])
var speed_rpm := 0.0
var rpm := 0.0
var smooth := true
var _stage := PackedFloat64Array([0, 0, 0, 0])
var _speed_stage := 0.0


func set_controls(values: PackedFloat64Array) -> bool:
	if values.size() != 4:
		return false
	for i in 4:
		if not is_finite(values[i]) or absf(values[i]) > LIMITS[i]:
			return false
	demand = values.duplicate()
	return true


func set_speed(value: float) -> bool:
	if not is_finite(value) or value < 0 or value > 12:
		return false
	speed_rpm = value
	return true


func set_smooth(enabled: bool) -> void:
	smooth = enabled


func needs_advance() -> bool:
	if rpm > 1e-8 or speed_rpm > 0:
		return true
	for i in 4:
		if absf(inputs[i] - demand[i]) > 1e-8 or absf(_stage[i] - demand[i]) > 1e-8:
			return true
	return false


## Detached presentation state, used only to roll back a rejected visible pose.
func capture_state() -> Dictionary:
	return {"demand": demand.duplicate(), "inputs": inputs.duplicate(), "stage": _stage.duplicate(),
		"speed_rpm": speed_rpm, "rpm": rpm, "speed_stage": _speed_stage, "smooth": smooth}


func restore_state(state: Dictionary) -> void:
	demand = state.demand.duplicate()
	inputs = state.inputs.duplicate()
	_stage = state.stage.duplicate()
	speed_rpm = state.speed_rpm
	rpm = state.rpm
	_speed_stage = state.speed_stage
	smooth = state.smooth


## Inspect the nearest occurrence of this azimuth without discarding whole turns.
## Whole turns matter: the tail and motor have noninteger transmission ratios.
func seek_azimuth(degrees: float) -> bool:
	if not is_finite(degrees) or degrees < 0 or degrees > 360:
		return false
	var requested_turn := deg_to_rad(degrees) - fposmod(inputs[4], TAU)
	var shortest_turn := wrapf(requested_turn, -PI, PI)
	# At exactly half a turn both paths are equally near: follow the slider direction.
	if absf(absf(shortest_turn) - PI) < 1e-12:
		shortest_turn = signf(requested_turn) * PI
	var next_phase := inputs[4] + shortest_turn
	if absf(next_phase) > PHASE_LIMIT:
		return false
	inputs[4] = next_phase
	speed_rpm = 0.0
	rpm = 0.0
	_speed_stage = 0.0
	return true


## Exact held-demand update, including the integral of rotor speed for shaft phase.
## No frame-time truncation: 30, 60 and 144 Hz reach the same presentation state.
func advance(seconds: float) -> bool:
	if not is_finite(seconds) or seconds < 0:
		return false
	if seconds == 0 and smooth:
		return true
	var next_inputs := inputs.duplicate()
	var next_stage := _stage.duplicate()
	var next_rpm := speed_rpm
	var next_speed_stage := speed_rpm
	var revolutions := speed_rpm * seconds / 60.0
	if smooth:
		var x := CONTROL_RATE * seconds
		var decay := exp(-x) if x < 50 else 0.0
		var weighted_decay := x * decay if x < 50 else 0.0
		for i in 4:
			next_inputs[i] = demand[i] + (inputs[i] - demand[i]) * decay + (_stage[i] - demand[i]) * weighted_decay
			next_stage[i] = demand[i] + (_stage[i] - demand[i]) * decay
		x = ROTATION_RATE * seconds
		decay = exp(-x) if x < 50 else 0.0
		weighted_decay = x * decay if x < 50 else 0.0
		next_rpm = speed_rpm + (rpm - speed_rpm) * decay + (_speed_stage - speed_rpm) * weighted_decay
		next_speed_stage = speed_rpm + (_speed_stage - speed_rpm) * decay
		var integral_decay := (1.0 - decay) / ROTATION_RATE
		var integral_weighted := integral_decay - seconds * decay
		revolutions += ((rpm - speed_rpm) * integral_decay + (_speed_stage - speed_rpm) * integral_weighted) / 60.0
	else:
		for i in 4:
			next_inputs[i] = demand[i]
		next_stage = demand.duplicate()
	next_inputs[4] += revolutions * TAU
	if not is_finite(next_inputs[4]) or absf(next_inputs[4]) > PHASE_LIMIT:
		return false
	inputs = next_inputs
	_stage = next_stage
	rpm = next_rpm
	_speed_stage = next_speed_stage
	return true
