# Fixed-step owner of the rigid-body state. 64-bit floats only (guarded by test.sh).
# Steps in _physics_process at the project's fixed tick (240 Hz), independent of rendering.
# Rendering reads interpolated() with Engine.get_physics_interpolation_fraction().
extends Node

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")

signal paused_changed(paused: bool)
## Emitted when a numerical or input-integrity guard stops the simulation.
signal faulted(reason: String)
## Emitted after every physics step (and once on reset, with tick 0), for recorders and telemetry.
signal stepped(tick: int, t: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array)

var mass := 1.0
var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
var gravity := 9.80665
## loads(state, t) -> PackedFloat64Array [Fx, Fy, Fz, Mx, My, Mz], body axes, gravity excluded.
var loads: Callable = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

## Pilot commands, set by the game each frame: [roll, pitch, yaw, throttle] (−1…1, throttle 0…1).
var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Loads at the start of the latest step (the RK4 k1 evaluation), for traces.
var last_loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Auxiliary states advanced once per tick, before integration (e.g. [engine_rpm]). Held constant during RK4.
var aux := PackedFloat64Array([0.0])
## Discrete modes belong to the tick transaction, never the RK derivative. Layout owned by the session.
var modes := PackedInt64Array()
## pre_step(aux, inputs, dt) -> PackedFloat64Array: new aux values. Runs at the fixed tick, so it stays deterministic.
var pre_step: Callable = func(a: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
	return a
## rotor_momentum(aux) -> PackedFloat64Array: angular momentum of spinning parts in body axes (N·m·s), or empty.
var rotor_momentum: Callable = func(_a: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array()

## E0b5: coupled float64 state, packed after the body only inside RK4. Empty on legacy aircraft.
## Callbacks receive (body_state, continuous_state, stage_time); both are read-only.
var continuous: PackedFloat64Array = PackedFloat64Array()
var continuous_loads: Callable
var continuous_derivative: Callable
## G2a stage-cost slice: one pure evaluation may supply all three stage results together.
## {loads: float64[6], derivative: float64[continuous.size], rotor_momentum: float64[3]}.
## An unset Callable retains the separate-callback path; no stage result survives the tick.
var continuous_evaluate: Callable
## G2a: optional stage-local spinning momentum and pure endpoint projection into sampled telemetry.
## Empty callbacks retain the legacy sampled-rotor policy. Projection is validated before any commit.
var continuous_rotor_momentum: Callable
var continuous_aux: Callable
var _last_valid_continuous: PackedFloat64Array = PackedFloat64Array()

var state := PackedFloat64Array()
var previous := PackedFloat64Array()
var tick := 0
var _fixed_dt := 0.0
var paused := false
## Stop stepping at this tick (-1 = never). Makes runs end at an exact tick, e.g. for replays.
var stop_at_tick := -1
## Wall-clock cost of a step (µs, smoothed), for the performance overlay. Measured, never fed back into the state.
var step_usec := 0.0
var _inertia_inv := PackedFloat64Array()
var _inertia_cache := PackedFloat64Array()
## A numerical fault is sticky until an explicit, valid reset succeeds.
var fault_reason := ""
var _last_valid_state := PackedFloat64Array()
var _last_valid_previous := PackedFloat64Array()
var _last_valid_aux := PackedFloat64Array()
var _last_valid_inputs := PackedFloat64Array()
var _last_valid_loads := PackedFloat64Array()
var _last_valid_modes := PackedInt64Array()
var _last_valid_tick := 0
var _last_valid_stop := -1
var _last_valid_mass := 1.0
var _last_valid_gravity := 9.80665
var _last_valid_inertia := PackedFloat64Array()
const CHECKPOINT_FORMAT := "openrc-simulation-checkpoint v1"

const MIN_QUATERNION_NORM_SQ := 1e-24


func reset(initial: PackedFloat64Array) -> bool:
	if not state_is_valid(initial):
		_fail_safe("reset rejected: initial state is nonfinite, malformed, or has a degenerate quaternion")
		return false
	if not _configuration_is_valid():
		_fail_safe("reset rejected: mass, gravity, or inertia is invalid")
		return false
	if not _array_is_finite(inputs, 4) or not _array_is_finite(aux) or not _array_is_finite(continuous):
		_fail_safe("reset rejected: input or auxiliary state is nonfinite or malformed")
		return false
	if not _continuous_aux_matches(continuous, aux):
		_fail_safe("reset rejected: continuous and auxiliary states disagree")
		return false
	var next_state := initial.duplicate()
	var a := RB.ATT
	var quaternion_norm_sq := next_state[a] * next_state[a] + next_state[a + 1] * next_state[a + 1] \
		+ next_state[a + 2] * next_state[a + 2] + next_state[a + 3] * next_state[a + 3]
	if absf(quaternion_norm_sq - 1.0) > 1e-12:
		RK.normalize_attitude(next_state)
	var next_inertia_inv := RB.inertia_inverse(inertia)
	if not _array_is_finite(next_inertia_inv, 6):
		_fail_safe("reset rejected: inertia inverse is nonfinite")
		return false
	var reset_loads: Variant = _stage_loads(_packed_state(next_state), 0.0)
	if not _loads_are_valid(reset_loads):
		_fail_safe("reset rejected: aircraft returned nonfinite or malformed loads")
		return false
	state = next_state
	previous = next_state.duplicate()
	tick = 0
	_fixed_dt = 1.0 / Engine.physics_ticks_per_second
	_inertia_inv = next_inertia_inv
	_inertia_cache = inertia.duplicate()
	last_loads = reset_loads
	fault_reason = ""
	_remember_valid_state()
	stepped.emit(tick, time(), state, last_loads, inputs, aux)
	return true


func dt() -> float:
	return _fixed_dt if _fixed_dt > 0.0 else 1.0 / Engine.physics_ticks_per_second


func time() -> float:
	return tick * dt()


func set_paused(value: bool) -> void:
	if not value and not fault_reason.is_empty():
		return
	if value != paused:
		paused = value
		paused_changed.emit(paused)


func _notification(what: int) -> void:
	# Losing focus pauses; resuming is an explicit action (set_paused(false)), never automatic.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_paused(true)


func step() -> void:
	if not fault_reason.is_empty():
		return
	var started := Time.get_ticks_usec()
	var t := time()
	if _fixed_dt != 1.0 / Engine.physics_ticks_per_second:
		_fail_safe("step rejected: fixed timestep changed; reset required")
		return
	if not state_is_valid(state):
		_fail_safe("step rejected: current state is nonfinite, malformed, or has a degenerate quaternion")
		return
	if not _configuration_is_valid():
		_fail_safe("step rejected: mass, gravity, or inertia is invalid")
		return
	if not _refresh_inertia_inverse():
		return
	if not _array_is_finite(inputs, 4) or not _array_is_finite(aux, _last_valid_aux.size()) or modes.size() != _last_valid_modes.size() \
			or not _array_is_finite(continuous, _last_valid_continuous.size()):
		_fail_safe("step rejected: input or auxiliary state is nonfinite or malformed")
		return
	var old_aux := aux.duplicate()
	var next_aux: Variant = pre_step.call(old_aux, inputs, dt())
	if not _array_is_finite(next_aux) or next_aux.size() != old_aux.size():
		_fail_safe("step rejected: pre-step produced nonfinite or malformed auxiliary state")
		return
	aux = next_aux
	var combined: PackedFloat64Array = _packed_state(state)
	var current_joint: Dictionary = {}
	if not continuous.is_empty() and continuous_evaluate.is_valid():
		var candidate: Variant = continuous_evaluate.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), t)
		if not _joint_stage_is_valid(candidate):
			aux = old_aux
			_fail_safe("step rejected: joint stage evaluation is nonfinite or malformed")
			return
		current_joint = candidate
	var current_loads: Variant = current_joint.loads if not current_joint.is_empty() else _stage_loads(combined, t)
	if not _loads_are_valid(current_loads):
		aux = old_aux
		_fail_safe("step rejected: aircraft returned nonfinite or malformed loads")
		return
	var rotor: Variant = rotor_momentum.call(aux) # held constant during RK4, like aux
	if not _array_is_finite(rotor) or (not rotor.is_empty() and rotor.size() != 3):
		aux = old_aux
		_fail_safe("step rejected: rotor momentum is nonfinite or malformed")
		return
	var h: PackedFloat64Array = rotor
	var stage_error := { message = "" }
	var derive := func(s: PackedFloat64Array, l: PackedFloat64Array, stage_t: float, joint: Dictionary = {}) -> PackedFloat64Array:
		var stage_h: PackedFloat64Array = h
		if not joint.is_empty():
			stage_h = joint.rotor_momentum
		elif not continuous.is_empty() and continuous_rotor_momentum.is_valid():
			var candidate_h: Variant = continuous_rotor_momentum.call(s.slice(0, RB.SIZE), s.slice(RB.SIZE), stage_t)
			if not _array_is_finite(candidate_h, 3):
				stage_error.message = "RK rotor momentum is nonfinite or malformed"
				return _zero_derivative()
			stage_h = candidate_h
		var derivative := RB.derivative(s, mass, inertia, _inertia_inv, M.v3(l[0], l[1], l[2]), M.v3(l[3], l[4], l[5]), gravity, stage_h)
		if not _array_is_finite(derivative, RB.SIZE):
			stage_error.message = "RK stage derivative is nonfinite or malformed"
			return _zero_derivative()
		if not continuous.is_empty():
			var extra: Variant = joint.derivative if not joint.is_empty() else continuous_derivative.call(s.slice(0, RB.SIZE), s.slice(RB.SIZE), stage_t)
			if not _array_is_finite(extra, continuous.size()):
				stage_error.message = "RK continuous derivative is nonfinite or malformed"
				return _zero_derivative()
			derivative.append_array(extra)
		return derivative
	var f := func(s: PackedFloat64Array, stage_t: float) -> PackedFloat64Array:
		if not stage_error.message.is_empty():
			return _zero_derivative()
		if not _stage_state_is_valid(s):
			stage_error.message = "RK stage state is nonfinite, malformed, or has a degenerate quaternion"
			return _zero_derivative()
		var joint: Dictionary = {}
		if not continuous.is_empty() and continuous_evaluate.is_valid():
			var candidate: Variant = continuous_evaluate.call(s.slice(0, RB.SIZE), s.slice(RB.SIZE), stage_t)
			if not _joint_stage_is_valid(candidate):
				stage_error.message = "RK joint stage evaluation is nonfinite or malformed"
				return _zero_derivative()
			joint = candidate
		var l: Variant = joint.loads if not joint.is_empty() else _stage_loads(s, stage_t)
		if not _loads_are_valid(l):
			stage_error.message = "RK stage loads are nonfinite or malformed"
			return _zero_derivative()
		return derive.call(s, l, stage_t, joint)
	# H2: the loads are a pure function of (state, aux, t), so stage 1 reuses the tick's own evaluation.
	var next_state := RK.rk4_step_at(combined, t, dt(), f, derive.call(combined, current_loads, t, current_joint))
	if not stage_error.message.is_empty():
		aux = old_aux
		_fail_safe("step rejected: " + stage_error.message)
		return
	if not _stage_state_is_valid(next_state):
		aux = old_aux
		_fail_safe("step rejected: integrated state is nonfinite, malformed, or has a degenerate quaternion")
		return
	if not continuous.is_empty() and continuous_aux.is_valid():
		var projected: Variant = continuous_aux.call(next_state.slice(RB.SIZE), aux.duplicate())
		if not _array_is_finite(projected, aux.size()):
			aux = old_aux
			_fail_safe("step rejected: continuous auxiliary projection is nonfinite or malformed")
			return
		aux = projected
	previous = state.duplicate()
	if not continuous.is_empty():
		continuous = next_state.slice(RB.SIZE)
		next_state = next_state.slice(0, RB.SIZE)
	state = next_state
	last_loads = current_loads
	tick += 1
	step_usec = lerpf(step_usec, float(Time.get_ticks_usec() - started), 0.05) if step_usec > 0.0 else float(Time.get_ticks_usec() - started)
	_remember_valid_state()
	stepped.emit(tick, time(), state, last_loads, inputs, aux)


func _physics_process(_delta: float) -> void:
	if paused:
		return
	if stop_at_tick >= 0 and tick >= stop_at_tick:
		return
	step()


## State between the previous and current step: position lerp, attitude nlerp (shortest path).
## Only position and attitude are interpolated; rates are taken from the current state.
func interpolated(fraction: float) -> PackedFloat64Array:
	if not is_finite(fraction):
		_fail_safe("interpolation rejected: fraction is nonfinite")
		return state.duplicate()
	if not state_is_valid(state) or not state_is_valid(previous):
		_fail_safe("interpolation rejected: current or previous state is invalid")
		return state.duplicate()
	var out := state.duplicate()
	for i in 3:
		out[RB.POS + i] = lerpf(previous[RB.POS + i], state[RB.POS + i], fraction)
	var a := RB.ATT
	var sign := 1.0
	if previous[a] * state[a] + previous[a + 1] * state[a + 1] + previous[a + 2] * state[a + 2] + previous[a + 3] * state[a + 3] < 0.0:
		sign = -1.0
	for i in 4:
		out[a + i] = lerpf(previous[a + i], sign * state[a + i], fraction)
	return RK.normalize_attitude(out)


## State integrity shared with aircraft preparation. A unit quaternion is expected; a nonzero quaternion is
## normalized at reset, while a degenerate or nonfinite one is rejected before RK4 can divide by zero.
static func state_is_valid(candidate: PackedFloat64Array) -> bool:
	if candidate.size() != RB.SIZE:
		return false
	for value in candidate:
		if not is_finite(value):
			return false
	var a := RB.ATT
	var norm_sq := candidate[a] * candidate[a] + candidate[a + 1] * candidate[a + 1] \
		+ candidate[a + 2] * candidate[a + 2] + candidate[a + 3] * candidate[a + 3]
	return is_finite(norm_sq) and norm_sq > MIN_QUATERNION_NORM_SQ


func _array_is_finite(candidate: Variant, expected_size := -1) -> bool:
	if typeof(candidate) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	if expected_size >= 0 and candidate.size() != expected_size:
		return false
	for value in candidate:
		if not is_finite(value):
			return false
	return true


func _loads_are_valid(candidate: Variant) -> bool:
	return _array_is_finite(candidate, 6)


func _configuration_is_valid() -> bool:
	if not continuous.is_empty() and not continuous_evaluate.is_valid() and (not continuous_loads.is_valid() or not continuous_derivative.is_valid()):
		return false
	if not is_finite(mass) or mass <= 0.0 or not is_finite(gravity) or gravity < 0.0 or inertia.size() != 6:
		return false
	for value in inertia:
		if not is_finite(value):
			return false
	var c00 := inertia[0] * inertia[1] - inertia[3] * inertia[3]
	var determinant := inertia[0] * (inertia[1] * inertia[2] - inertia[5] * inertia[5]) \
		- inertia[3] * (inertia[3] * inertia[2] - inertia[4] * inertia[5]) \
		+ inertia[4] * (inertia[3] * inertia[5] - inertia[4] * inertia[1])
	return inertia[0] > 0.0 and c00 > 0.0 and determinant > 0.0 \
		and is_finite(c00) and is_finite(determinant)


func _refresh_inertia_inverse() -> bool:
	if _same_array(inertia, _inertia_cache) and _array_is_finite(_inertia_inv, 6):
		return true
	var next_inverse := RB.inertia_inverse(inertia)
	if not _array_is_finite(next_inverse, 6):
		_fail_safe("step rejected: inertia inverse is nonfinite")
		return false
	_inertia_inv = next_inverse
	_inertia_cache = inertia.duplicate()
	return true


func _same_array(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for i in left.size():
		if left[i] != right[i]:
			return false
	return true


func _continuous_aux_matches(extra: PackedFloat64Array, sampled: PackedFloat64Array) -> bool:
	if not continuous_aux.is_valid():
		return true
	var projected: Variant = continuous_aux.call(extra.duplicate(), sampled.duplicate())
	return _array_is_finite(projected, sampled.size()) and _same_array(projected, sampled)


func _zero_derivative() -> PackedFloat64Array:
	var zero: PackedFloat64Array = PackedFloat64Array()
	zero.resize(RB.SIZE + continuous.size())
	return zero


func _remember_valid_state() -> void:
	_last_valid_continuous = continuous.duplicate()
	_last_valid_state = state.duplicate()
	_last_valid_previous = previous.duplicate()
	_last_valid_aux = aux.duplicate()
	_last_valid_inputs = inputs.duplicate()
	_last_valid_loads = last_loads.duplicate()
	_last_valid_modes = modes.duplicate()
	_last_valid_tick = tick
	_last_valid_stop = stop_at_tick
	_last_valid_mass = mass
	_last_valid_gravity = gravity
	_last_valid_inertia = inertia.duplicate()


func _restore_last_valid() -> void:
	if state_is_valid(_last_valid_state):
		continuous = _last_valid_continuous.duplicate()
		tick = _last_valid_tick
		stop_at_tick = _last_valid_stop
		modes = _last_valid_modes.duplicate()
		mass = _last_valid_mass
		gravity = _last_valid_gravity
		inertia = _last_valid_inertia.duplicate()
		state = _last_valid_state.duplicate()
		previous = _last_valid_previous.duplicate() if state_is_valid(_last_valid_previous) else state.duplicate()
		if _array_is_finite(_last_valid_aux):
			aux = _last_valid_aux.duplicate()
		if _array_is_finite(_last_valid_inputs, 4):
			inputs = _last_valid_inputs.duplicate()
		if _loads_are_valid(_last_valid_loads):
			last_loads = _last_valid_loads.duplicate()


func _fail_safe(reason: String) -> void:
	_restore_last_valid()
	fault_reason = reason
	set_paused(true)
	faulted.emit(fault_reason)


## Exact, detached tick-boundary snapshot. var_to_bytes/bytes_to_var preserves float64 bits;
## JSON/CSV are diagnostics, not this format. Callbacks and model configuration stay with the owner.
func checkpoint() -> Dictionary:
	if not fault_reason.is_empty() or not _array_is_finite(continuous, _last_valid_continuous.size()):
		return {}
	var snapshot: Dictionary = { format = CHECKPOINT_FORMAT, tick = tick, dt = dt(), state = state.duplicate(),
		previous = previous.duplicate(), aux = aux.duplicate(), inputs = inputs.duplicate(),
		modes = modes.duplicate(), last_loads = last_loads.duplicate(), mass = mass,
		inertia = inertia.duplicate(), gravity = gravity, stop_at_tick = stop_at_tick }
	if not continuous.is_empty():
		snapshot.continuous = continuous.duplicate()
	# A producer must not emit a boundary that its own reader refuses.
	return snapshot if can_restore_checkpoint(snapshot) else {}


## Validate before changing anything. Restoring across a layout, timestep or mass configuration is refused.
func can_restore_checkpoint(candidate: Dictionary, expected_aux_size: int = -1, expected_modes_size: int = -1) -> bool:
	for key in ["format", "tick", "dt", "state", "previous", "aux", "inputs", "modes", "last_loads", "mass", "inertia", "gravity", "stop_at_tick"]:
		if not candidate.has(key):
			return false
	if typeof(candidate.format) != TYPE_STRING or candidate.format != CHECKPOINT_FORMAT or typeof(candidate.tick) != TYPE_INT or candidate.tick < 0 \
			or typeof(candidate.stop_at_tick) != TYPE_INT or candidate.stop_at_tick < -1:
		return false
	for key in ["dt", "mass", "gravity"]:
		if typeof(candidate[key]) != TYPE_FLOAT or not is_finite(candidate[key]):
			return false
	if not _checkpoint_clock_is_valid(candidate.tick, candidate.dt):
		return false
	if candidate.dt != dt() or candidate.dt != 1.0 / Engine.physics_ticks_per_second or candidate.mass != mass or candidate.gravity != gravity \
			or not _array_is_finite(candidate.inertia, 6) or not _same_array(candidate.inertia, inertia):
		return false
	if not _checkpoint_state_is_valid(candidate.state) or not _checkpoint_state_is_valid(candidate.previous):
		return false
	return _array_is_finite(candidate.get("continuous", PackedFloat64Array()), continuous.size()) \
		and _array_is_finite(candidate.aux, aux.size() if expected_aux_size < 0 else expected_aux_size) and _array_is_finite(candidate.inputs, 4) \
		and _loads_are_valid(candidate.last_loads) and typeof(candidate.modes) == TYPE_PACKED_INT64_ARRAY \
		and candidate.modes.size() == (modes.size() if expected_modes_size < 0 else expected_modes_size) and _configuration_is_valid() \
		and _array_is_finite(RB.inertia_inverse(inertia), 6) \
		and _continuous_aux_matches(candidate.get("continuous", PackedFloat64Array()), candidate.aux)


## Explicit recovery restores all dynamic state and pauses. No tick/trace sample is emitted.
func restore_checkpoint(candidate: Dictionary) -> bool:
	if not can_restore_checkpoint(candidate):
		return false
	continuous = candidate.get("continuous", PackedFloat64Array()).duplicate()
	state = candidate.state.duplicate()
	previous = candidate.previous.duplicate()
	aux = candidate.aux.duplicate()
	inputs = candidate.inputs.duplicate()
	modes = candidate.modes.duplicate()
	last_loads = candidate.last_loads.duplicate()
	tick = candidate.tick
	_fixed_dt = candidate.dt # a compatible fresh owner has no reset-established clock yet
	stop_at_tick = candidate.stop_at_tick
	_inertia_inv = RB.inertia_inverse(inertia)
	_inertia_cache = inertia.duplicate()
	fault_reason = ""
	_remember_valid_state()
	set_paused(true)
	return true


## Restored clocks must support another integer tick and distinct RK4 stage times.
## Checking only finiteness misses both int64 wrap and float64 time stagnation.
func _checkpoint_clock_is_valid(at: int, timestep: float) -> bool:
	if at < 0 or at == 9223372036854775807 or not is_finite(timestep) or timestep <= 0.0:
		return false
	var start_time: float = at * timestep
	var half_time: float = start_time + 0.5 * timestep
	var end_time: float = start_time + timestep
	return is_finite(end_time) and half_time > start_time and end_time > half_time \
		and (at + 1) * timestep > start_time


func _checkpoint_state_is_valid(candidate: Variant) -> bool:
	if not _array_is_finite(candidate, RB.SIZE) or not state_is_valid(candidate):
		return false
	var norm_sq := 0.0
	for i in range(RB.ATT, RB.ATT + 4):
		norm_sq += candidate[i] * candidate[i]
	return absf(norm_sq - 1.0) <= 1e-10


func _packed_state(body: PackedFloat64Array) -> PackedFloat64Array:
	if continuous.is_empty():
		return body
	var combined: PackedFloat64Array = body.duplicate()
	combined.append_array(continuous)
	return combined


func _stage_loads(combined: PackedFloat64Array, stage_t: float) -> Variant:
	if continuous.is_empty():
		return loads.call(combined, stage_t)
	if continuous_evaluate.is_valid():
		var candidate: Variant = continuous_evaluate.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), stage_t)
		return candidate.loads if _joint_stage_is_valid(candidate) else PackedFloat64Array([NAN])
	return continuous_loads.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), stage_t)


func _joint_stage_is_valid(candidate: Variant) -> bool:
	return candidate is Dictionary and candidate.size() == 3 and candidate.has_all(["loads", "derivative", "rotor_momentum"]) \
		and _loads_are_valid(candidate.loads) and _array_is_finite(candidate.derivative, continuous.size()) \
		and _array_is_finite(candidate.rotor_momentum, 3)


func _stage_state_is_valid(combined: PackedFloat64Array) -> bool:
	if continuous.is_empty():
		return state_is_valid(combined)
	return _array_is_finite(combined, RB.SIZE + continuous.size()) and state_is_valid(combined.slice(0, RB.SIZE))
