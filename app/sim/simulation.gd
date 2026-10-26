# Fixed-step owner of the rigid-body state. 64-bit floats only (guarded by test.sh).
# Steps in _physics_process at the project's fixed tick (240 Hz), independent of rendering.
# Rendering reads interpolated() with Engine.get_physics_interpolation_fraction().
# SF-01: the kernel steps exactly one VehicleModel (sim/vehicle_model.gd): it declares the state layout and
# supplies the read-only stage evaluators. Sessions and tests configure evaluators only through `model`; the
# pre-SF-01 per-callback properties were retired by the SF-03 alias cleanup.
extends Node

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const EventStep := preload("res://physics/event_step.gd")

signal paused_changed(paused: bool)
## Emitted when a numerical or input-integrity guard stops the simulation.
signal faulted(reason: String)
## Read-only observer boundary after input guards, before any tick transition. FL replay records sparse external edits here.
signal before_step(tick: int)
## SF-04: emitted before `stepped` when the accepted tick located discrete events ({type, time_s, ...} each).
signal events_located(tick: int, events: Array[Dictionary])
## Emitted after every physics step (and once on reset, with tick 0), for recorders and telemetry.
signal stepped(tick: int, t: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array)

var mass := 1.0
var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
var gravity := 9.80665
## The stepped vehicle. Sessions build a VehicleModel and install it with set_model(); the kernel reads only this
## object for layout and evaluators. Mass, inertia and gravity stay here because they roll back with the tick.
var model: VehicleModel = VehicleModel.new()
## Pilot commands, set by the game each frame: model.input_size values (legacy layout [roll, pitch, yaw, throttle],
## −1…1 and throttle 0…1; retractable-gear sessions append deployment target and wheel-brake demand).
var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Loads at the start of the latest step (the RK4 k1 evaluation), for traces.
var last_loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Auxiliary states advanced once per tick, before integration (e.g. [engine_rpm]). Held constant during RK4.
var aux := PackedFloat64Array([0.0])
## Discrete modes belong to the tick transaction, never the RK derivative. Layout owned by the session.
var modes := PackedInt64Array()
## E0b5: coupled float64 state, packed after the body only inside RK4. Empty on legacy aircraft.
var continuous: PackedFloat64Array = PackedFloat64Array()
var _last_valid_continuous: PackedFloat64Array = PackedFloat64Array()
## SF-04: events the latest accepted tick located, in tick order. A diagnostic record, not state: it is not part
## of the checkpoint and is cleared by reset and restore.
var last_events: Array[Dictionary] = []
## Located event times may land one rounding step outside the tick window; wider than that is malformed.
const EVENT_TIME_SLACK_S := 1e-9
## SF-05: bound on a model's declared substeps per tick.
const MAX_SUBSTEPS := 16

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
const ENDPOINT_CHECKPOINT_FORMAT := "openrc-simulation-checkpoint v2"
const MAX_ENDPOINT_EVENTS := 256
var _state_layout_identity := ""
var _endpoint_callback_active := false
var _endpoint_reentry_attempted := false

const MIN_QUATERNION_NORM_SQ := 1e-24


## Install the vehicle to step. The contract's static shape is validated here (VehicleModel.validate); agreement
## with the live arrays is checked at reset and restore. An invalid candidate leaves the current model untouched.
func set_model(candidate: Variant) -> bool:
	if _reject_endpoint_reentry(): return false
	if not (candidate is VehicleModel):
		return false
	if not VehicleModel.validate(candidate).ok:
		return false
	model = candidate
	return true


## Declared sizes (>= 0) must match the arrays; -1 keeps the H8 rule that the arrays at reset fix the layout.
func _layout_matches_model(sampled: PackedFloat64Array, discrete: PackedInt64Array, extra: PackedFloat64Array) -> bool:
	return (model.aux_size < 0 or sampled.size() == model.aux_size) \
		and (model.modes_size < 0 or discrete.size() == model.modes_size) \
		and (model.continuous_size < 0 or extra.size() == model.continuous_size)


func reset(initial: PackedFloat64Array) -> bool:
	if _reject_endpoint_reentry(): return false
	var candidate := prepare_reset(initial)
	if not candidate.ok:
		_fail_safe(str(candidate.message))
		return false
	return commit_prepared_reset(candidate)


## Evaluate a detached reset candidate in the owner's supplied callback context.
## No state, fault, clock, RNG, or observer event is changed on rejection.
## The owner must keep that context fixed until commit_prepared_reset().
func prepare_reset(initial: PackedFloat64Array) -> Dictionary:
	if _reject_endpoint_reentry(): return {ok = false, message = "reset preparation is unavailable inside an endpoint callback"}
	if not state_is_valid(initial):
		return {ok = false, message = "reset rejected: initial state is nonfinite, malformed, or has a degenerate quaternion"}
	if not _configuration_is_valid():
		return {ok = false, message = "reset rejected: mass, gravity, or inertia is invalid"}
	var contract: Dictionary = VehicleModel.validate(model)
	if not contract.ok:
		return {ok = false, message = "reset rejected: " + str(contract.message)}
	if not _array_is_finite(inputs, model.input_size) or not _array_is_finite(aux) or not _array_is_finite(continuous):
		return {ok = false, message = "reset rejected: input or auxiliary state is nonfinite or malformed"}
	if not _layout_matches_model(aux, modes, continuous):
		return {ok = false, message = "reset rejected: auxiliary, mode or continuous state disagrees with the vehicle model's declared layout"}
	if not _continuous_aux_matches(continuous, aux):
		return {ok = false, message = "reset rejected: continuous and auxiliary states disagree"}
	var next_state := initial.duplicate()
	var a := RB.ATT
	var quaternion_norm_sq := next_state[a] * next_state[a] + next_state[a + 1] * next_state[a + 1] \
		+ next_state[a + 2] * next_state[a + 2] + next_state[a + 3] * next_state[a + 3]
	if absf(quaternion_norm_sq - 1.0) > 1e-12:
		RK.normalize_attitude(next_state)
	if _endpoint_enabled() and not _validate_endpoint_frame(_endpoint_frame(next_state, continuous, aux, modes),
		_endpoint_validation_context(0, 1.0 / Engine.physics_ticks_per_second)):
		return {ok = false, message = "reset rejected: endpoint state validator or layout refused the state"}
	var next_inertia_inv := RB.inertia_inverse(inertia)
	if not _array_is_finite(next_inertia_inv, 6):
		return {ok = false, message = "reset rejected: inertia inverse is nonfinite"}
	var reset_guard: Dictionary = _capture_endpoint_guard() if _endpoint_enabled() else {}
	var reset_loads: Variant = _call_endpoint_read_only(_stage_loads, [_packed_state(next_state), 0.0]) \
		if _endpoint_enabled() else _stage_loads(_packed_state(next_state), 0.0)
	if not reset_guard.is_empty() and not _endpoint_guard_unchanged(reset_guard):
		return {ok = false, message = "reset rejected: evaluator mutated live state or model"}
	if not _loads_are_valid(reset_loads):
		return {ok = false, message = "reset rejected: aircraft returned nonfinite or malformed loads"}
	var prepared := {ok = true, state = next_state, inertia_inverse = next_inertia_inv, loads = reset_loads}
	if _endpoint_enabled():
		prepared.endpoint_guard = _capture_endpoint_guard()
		prepared.endpoint_seal = _endpoint_reset_seal(prepared)
	return prepared


## Only accepts a successful preparation from this owner with unchanged context.
## This is the sole publication boundary for a prepared reset.
func commit_prepared_reset(candidate: Dictionary) -> bool:
	if _reject_endpoint_reentry(): return false
	assert(candidate.get("ok", false))
	if _endpoint_enabled() or candidate.has("endpoint_guard"):
		if not _endpoint_enabled() or not candidate.get("endpoint_guard") is Dictionary \
			or typeof(candidate.get("endpoint_seal")) != TYPE_PACKED_BYTE_ARRAY:
			return false
		# A changed context is refused without overwriting the caller's new context.
		if not _endpoint_guard_matches(candidate.endpoint_guard) \
			or candidate.endpoint_seal != _endpoint_reset_seal(candidate) \
			or not _validate_endpoint_frame(_endpoint_frame(candidate.state, continuous, aux, modes),
				_endpoint_validation_context(0, 1.0 / Engine.physics_ticks_per_second)):
			return false
	state = candidate.state.duplicate()
	previous = state.duplicate()
	tick = 0
	_fixed_dt = 1.0 / Engine.physics_ticks_per_second
	_inertia_inv = candidate.inertia_inverse.duplicate()
	_inertia_cache = inertia.duplicate()
	last_loads = candidate.loads.duplicate()
	last_events = []
	fault_reason = ""
	_state_layout_identity = model.state_layout_identity
	_remember_valid_state()
	stepped.emit(tick, time(), state, last_loads, inputs, aux)
	return true


func dt() -> float:
	return _fixed_dt if _fixed_dt > 0.0 else 1.0 / Engine.physics_ticks_per_second


func time() -> float:
	return tick * dt()


func set_paused(value: bool) -> void:
	if _reject_endpoint_reentry(): return
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
	if _reject_endpoint_reentry(): return
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
	if model.input_size != _last_valid_inputs.size() or not _array_is_finite(inputs, model.input_size) or not _array_is_finite(aux, _last_valid_aux.size()) or modes.size() != _last_valid_modes.size() \
			or not _array_is_finite(continuous, _last_valid_continuous.size()):
		_fail_safe("step rejected: input or auxiliary state is nonfinite or malformed")
		return
	if _state_layout_identity != model.state_layout_identity or (_endpoint_enabled() \
		and not _validate_endpoint_frame(_endpoint_frame(state, continuous, aux, modes), _endpoint_validation_context(tick, dt()))):
		_fail_safe("step rejected: endpoint state validator or layout identity refused the current state")
		return
	before_step.emit(tick)
	var endpoint_previous: Dictionary = _endpoint_frame(state, continuous, aux, modes) if _endpoint_enabled() else {}
	var old_aux := aux.duplicate()
	var next_aux: Variant = model.pre_tick.call(old_aux, inputs, dt())
	if not _array_is_finite(next_aux) or next_aux.size() != old_aux.size():
		_fail_safe("step rejected: pre-step produced nonfinite or malformed auxiliary state")
		return
	aux = next_aux
	var combined: PackedFloat64Array = _packed_state(state)
	var current_joint: Dictionary = {}
	if not continuous.is_empty() and model.stage.is_valid():
		var candidate: Variant = model.stage.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), t)
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
	var rotor: Variant = model.rotor_momentum.call(aux) # held constant during RK4, like aux
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
		elif not continuous.is_empty() and model.stage_rotor_momentum.is_valid():
			var candidate_h: Variant = model.stage_rotor_momentum.call(s.slice(0, RB.SIZE), s.slice(RB.SIZE), stage_t)
			if not _array_is_finite(candidate_h, 3):
				stage_error.message = "RK rotor momentum is nonfinite or malformed"
				return _zero_derivative()
			stage_h = candidate_h
		# A qualified open-system law may supply its stage body derivative (finite fuel mass/CG).
		var derivative: PackedFloat64Array = joint.body_derivative if joint.has("body_derivative") else RB.derivative(s, mass, inertia, _inertia_inv, M.v3(l[0], l[1], l[2]), M.v3(l[3], l[4], l[5]), gravity, stage_h)
		if not _array_is_finite(derivative, RB.SIZE):
			stage_error.message = "RK stage derivative is nonfinite or malformed"
			return _zero_derivative()
		if not continuous.is_empty():
			var extra: Variant = joint.derivative if not joint.is_empty() else model.block_derivative.call(s.slice(0, RB.SIZE), s.slice(RB.SIZE), stage_t)
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
		if not continuous.is_empty() and model.stage.is_valid():
			var candidate: Variant = model.stage.call(s.slice(0, RB.SIZE), s.slice(RB.SIZE), stage_t)
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
	var first: PackedFloat64Array = derive.call(combined, current_loads, t, current_joint)
	# SF-04: one tick policy. A declared event runs the kernel's locator; a model policy may return the combined
	# state alone or {state, events}; located events are validated against the tick window and recorded.
	# SF-05: a model may ask for n substeps this tick (stiff contacts within reach); the kernel's own RK4 and the
	# declared-event locator then integrate n pieces of dt/n, re-evaluating k1 at each piece. A policy owns its tick.
	var substeps: int = 1
	var declared_substeps: Variant = 1
	if model.substeps_joint.is_valid():
		declared_substeps = model.substeps_joint.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), t, current_joint)
	elif model.substeps.is_valid():
		declared_substeps = model.substeps.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), t)
	if typeof(declared_substeps) != TYPE_INT or declared_substeps < 1 or declared_substeps > MAX_SUBSTEPS:
		aux = old_aux
		_fail_safe("step rejected: substep count is not an integer within 1..%d" % MAX_SUBSTEPS)
		return
	substeps = declared_substeps
	# SF-04b: a step policy owns the whole tick and is never split. Refuse the tick rather than integrate a stiff
	# contact over the full dt, where the loader's per-substep ω·dt rule would silently not hold.
	if substeps > 1 and model.step_policy.is_valid():
		aux = old_aux
		_fail_safe("step rejected: the step policy owns the tick and cannot honour %d contact substeps" % substeps)
		return
	var policy_result: Variant
	if model.step_policy.is_valid():
		policy_result = model.step_policy.call(combined, t, dt(), f, first)
	elif not model.events.is_empty():
		policy_result = _locate_substeps(combined, t, dt(), f, first, model.events[0], substeps)
	elif substeps == 1:
		policy_result = RK.rk4_step_at(combined, t, dt(), f, first)
	else:
		policy_result = _rk4_substeps(combined, t, dt(), f, first, substeps)
	if not stage_error.message.is_empty():
		aux = old_aux
		_fail_safe("step rejected: " + stage_error.message)
		return
	var tick_events: Array[Dictionary] = []
	var integration_receipt: Dictionary = {}
	var next_state: PackedFloat64Array = PackedFloat64Array()
	if policy_result is Dictionary:
		var unpacked: Dictionary = _unpack_policy_result(policy_result, t)
		if not unpacked.ok:
			aux = old_aux
			_fail_safe("step rejected: " + str(unpacked.message))
			return
		next_state = unpacked.state
		tick_events = unpacked.events
		integration_receipt = unpacked.get("integration_receipt", {})
	elif policy_result is PackedFloat64Array:
		next_state = policy_result
	else:
		aux = old_aux
		_fail_safe("step rejected: the event locator could not bound the tick" if policy_result == null \
			else "step rejected: step policy returned a malformed result")
		return
	if not _stage_state_is_valid(next_state):
		aux = old_aux
		_fail_safe("step rejected: integrated state is nonfinite, malformed, or has a degenerate quaternion")
		return
	var accepted_body_state: PackedFloat64Array = next_state.slice(0, RB.SIZE)
	var integrated_body_state: PackedFloat64Array = accepted_body_state.duplicate() if _endpoint_enabled() else PackedFloat64Array()
	if model.post_tick.is_valid() or model.post_tick_joint.is_valid():
		var filter_guard: Dictionary = _capture_endpoint_guard() if _endpoint_enabled() else {}
		var filter_callback: Callable = model.post_tick_joint if model.post_tick_joint.is_valid() else model.post_tick
		var filter_arguments: Array = [state.duplicate(), accepted_body_state.duplicate(), tick + 1]
		if model.post_tick_joint.is_valid():
			filter_arguments.append(continuous.duplicate())
			filter_arguments.append(next_state.slice(RB.SIZE))
		var filtered: Variant = _call_endpoint_read_only(filter_callback, filter_arguments) if _endpoint_enabled() \
			else filter_callback.callv(filter_arguments)
		if not filter_guard.is_empty() and not _endpoint_guard_unchanged(filter_guard):
			_fail_safe("step rejected: endpoint body filter mutated live state or model")
			return
		# post_tick owns only the 13-value rigid body. Continuous states are integrated independently
		# and remain the already-validated tail of next_state.
		if not (filtered is PackedFloat64Array) or not state_is_valid(filtered):
			aux = old_aux
			_fail_safe("step rejected: post-step contact filter returned a malformed body state")
			return
		accepted_body_state = filtered.duplicate()
	var accepted_continuous: PackedFloat64Array = next_state.slice(RB.SIZE)
	var accepted_aux: PackedFloat64Array = aux
	var accepted_modes: PackedInt64Array = modes
	if model.endpoint_transition.is_valid():
		var candidate_frame := _endpoint_frame(accepted_body_state, accepted_continuous, aux, modes)
		var context := {tick = tick + 1, time_s = t + dt(), dt = dt(), events = tick_events.duplicate(true),
			body_filtered = integrated_body_state.to_byte_array() != accepted_body_state.to_byte_array()}
		if not integration_receipt.is_empty():
			context.integration_receipt = integration_receipt.duplicate(true)
		var previous_copy: Dictionary = endpoint_previous.duplicate(true)
		var context_copy: Dictionary = context.duplicate(true)
		var transition_guard := _capture_endpoint_guard()
		var transitioned: Variant = _call_endpoint_read_only(model.endpoint_transition, [endpoint_previous, candidate_frame, context])
		var pure := _endpoint_guard_unchanged(transition_guard)
		if not pure or not _guard_values_equal(endpoint_previous, previous_copy) or not _guard_values_equal(context, context_copy):
			_fail_safe("step rejected: endpoint transition mutated live state, previous frame or context")
			return
		if not transitioned is Dictionary or transitioned.size() != 5 \
			or not transitioned.has_all(["body", "continuous", "aux", "modes", "events"]):
			_fail_safe("step rejected: endpoint transition returned a malformed frame")
			return
		var frame_only: Dictionary = transitioned.duplicate(true)
		frame_only.erase("events")
		if not _endpoint_frame_shape_is_valid(frame_only):
			_fail_safe("step rejected: endpoint transition returned nonfinite or resized state")
			return
		var merged: Dictionary = _endpoint_events(transitioned.events, tick_events, t)
		if not merged.ok:
			_fail_safe("step rejected: " + str(merged.message))
			return
		accepted_body_state = frame_only.body.duplicate()
		accepted_continuous = frame_only.continuous.duplicate()
		accepted_aux = frame_only.aux.duplicate()
		accepted_modes = frame_only.modes.duplicate()
		tick_events = merged.events
	if not continuous.is_empty() and model.block_aux.is_valid():
		var projection_guard: Dictionary = _capture_endpoint_guard() if _endpoint_enabled() else {}
		var projected: Variant = _call_endpoint_read_only(model.block_aux, [accepted_continuous.duplicate(), accepted_aux.duplicate()]) \
			if _endpoint_enabled() else model.block_aux.call(accepted_continuous, accepted_aux.duplicate())
		if not projection_guard.is_empty() and not _endpoint_guard_unchanged(projection_guard):
			_fail_safe("step rejected: endpoint auxiliary projection mutated live state or model")
			return
		if not _array_is_finite(projected, aux.size()):
			aux = old_aux
			_fail_safe("step rejected: continuous auxiliary projection is nonfinite or malformed")
			return
		accepted_aux = projected
	if _endpoint_enabled() and (not _continuous_aux_matches(accepted_continuous, accepted_aux) \
		or not _validate_endpoint_frame(_endpoint_frame(accepted_body_state, accepted_continuous, accepted_aux, accepted_modes),
			_endpoint_validation_context(tick + 1, dt()))):
		_fail_safe("step rejected: endpoint projection or validator refused the final state")
		return
	if _endpoint_enabled() and not model.endpoint_transition.is_valid():
		var checked_events := _endpoint_events([], tick_events, t)
		if not checked_events.ok:
			_fail_safe("step rejected: " + str(checked_events.message))
			return
		tick_events = checked_events.events
	previous = state.duplicate()
	if not continuous.is_empty():
		continuous = accepted_continuous
	aux = accepted_aux
	modes = accepted_modes
	state = accepted_body_state
	last_loads = current_loads
	last_events = tick_events
	tick += 1
	step_usec = lerpf(step_usec, float(Time.get_ticks_usec() - started), 0.05) if step_usec > 0.0 else float(Time.get_ticks_usec() - started)
	_remember_valid_state()
	if not tick_events.is_empty():
		events_located.emit(tick, tick_events)
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
	if _reject_endpoint_reentry(): return state.duplicate()
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
	if (not model.state_layout_identity.is_empty() or model.endpoint_transition.is_valid() \
		or model.state_validator.is_valid()) and not VehicleModel.validate(model).ok:
		return false
	# Joint stages require a continuous block. Never silently discard that evaluator
	# in favour of the body-only loads callback (whose default returns zero loads).
	if continuous.is_empty() and (model.stage.is_valid() or not model.loads.is_valid()):
		return false
	if model.post_tick.is_valid() and model.post_tick_joint.is_valid():
		return false
	if model.substeps.is_valid() and model.substeps_joint.is_valid():
		return false
	if model.substeps_joint.is_valid() and (not model.stage.is_valid() or continuous.is_empty()):
		return false
	if not continuous.is_empty() and not model.stage.is_valid() and (not model.block_loads.is_valid() or not model.block_derivative.is_valid()):
		return false
	if not model.events.is_empty():
		if model.step_policy.is_valid() or model.events.size() != 1:
			return false
		var declared_index: int = int(model.events[0].get("index", -1))
		if declared_index < RB.SIZE or declared_index >= RB.SIZE + continuous.size():
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
	if not model.block_aux.is_valid():
		return true
	var projection_guard: Dictionary = _capture_endpoint_guard() if _endpoint_enabled() else {}
	var projected: Variant = _call_endpoint_read_only(model.block_aux, [extra.duplicate(), sampled.duplicate()]) \
		if _endpoint_enabled() else model.block_aux.call(extra.duplicate(), sampled.duplicate())
	if not projection_guard.is_empty() and not _endpoint_guard_unchanged(projection_guard):
		return false
	return _array_is_finite(projected, sampled.size()) and _same_array(projected, sampled)


## n full RK4 pieces of dt/n with the same inputs; the first piece reuses the tick's k1, later pieces re-evaluate it.
func _rk4_substeps(combined: PackedFloat64Array, t: float, dt_tick: float, f: Callable, first: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var current: PackedFloat64Array = combined
	var piece: float = dt_tick / float(n)
	var elapsed: float = 0.0
	for i in n:
		var k1: PackedFloat64Array = first if i == 0 else f.call(current, t + elapsed)
		current = RK.rk4_step_at(current, t + elapsed, piece, f, k1)
		elapsed += piece
	return current


## The declared-event locator over n pieces of dt/n; events keep their absolute times. null = the locator failed.
func _locate_substeps(combined: PackedFloat64Array, t: float, dt_tick: float, f: Callable, first: PackedFloat64Array,
		declared: Dictionary, n: int) -> Variant:
	var current: PackedFloat64Array = combined
	var piece: float = dt_tick / float(n)
	var elapsed: float = 0.0
	var events: Array[Dictionary] = []
	for i in n:
		var located: Dictionary = EventStep.advance(current, t + elapsed, piece, f, first if i == 0 else PackedFloat64Array(),
			int(declared.index), declared.transition, str(declared.type))
		if not located.get("ok", false):
			return null
		current = located.state
		for event: Dictionary in located.events:
			events.append(event)
		elapsed += piece
	return {state = current, events = events}


## A policy's {state, events[, integration_receipt]} result. State is validated by
## the caller; events need a type/time inside the tick. Optional accepted-path
## evidence is bounded/detached and requires an explicit endpoint owner. Its
## physical meaning stays with that model; it is not published or checkpointed.
func _unpack_policy_result(result: Dictionary, t: float) -> Dictionary:
	if typeof(result.get("state")) != TYPE_PACKED_FLOAT64_ARRAY:
		return {ok = false, message = "step policy returned no state"}
	var integration_receipt := {}
	if result.has("integration_receipt"):
		if not _endpoint_enabled() or not model.endpoint_transition.is_valid() \
			or typeof(result.integration_receipt) != TYPE_DICTIONARY \
			or not _endpoint_event_value(result.integration_receipt, 0, {left = 4096}):
			return {ok = false, message = "integration receipt requires an opt-in endpoint owner and bounded finite payload"}
		integration_receipt = result.integration_receipt.duplicate(true)
	var raw: Variant = result.get("events", [])
	if typeof(raw) != TYPE_ARRAY:
		return {ok = false, message = "step policy returned malformed events"}
	var events: Array[Dictionary] = []
	var earliest: float = t - EVENT_TIME_SLACK_S
	var latest: float = t + dt() + EVENT_TIME_SLACK_S
	for item: Variant in raw:
		if typeof(item) != TYPE_DICTIONARY or typeof(item.get("type")) != TYPE_STRING or str(item.type).is_empty() \
				or typeof(item.get("time_s")) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(item.time_s)) \
				or float(item.time_s) < earliest or float(item.time_s) > latest:
			return {ok = false, message = "step policy returned malformed events"}
		events.append(item.duplicate(true))
	var unpacked := {ok = true, state = result.state, events = events}
	if not integration_receipt.is_empty(): unpacked.integration_receipt = integration_receipt
	return unpacked


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
		if _last_valid_inputs.size() > 0 and _array_is_finite(_last_valid_inputs):
			model.input_size = _last_valid_inputs.size()
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
	if _reject_endpoint_reentry(): return {}
	if not fault_reason.is_empty() or not _array_is_finite(continuous, _last_valid_continuous.size()):
		return {}
	if _state_layout_identity != model.state_layout_identity:
		return {}
	var snapshot: Dictionary = { format = CHECKPOINT_FORMAT, tick = tick, dt = dt(), state = state.duplicate(),
		previous = previous.duplicate(), aux = aux.duplicate(), inputs = inputs.duplicate(),
		modes = modes.duplicate(), last_loads = last_loads.duplicate(), mass = mass,
		inertia = inertia.duplicate(), gravity = gravity, stop_at_tick = stop_at_tick }
	if not continuous.is_empty():
		snapshot.continuous = continuous.duplicate()
	if _endpoint_enabled():
		snapshot.format = ENDPOINT_CHECKPOINT_FORMAT
		snapshot.state_layout_identity = model.state_layout_identity
	# A producer must not emit a boundary that its own reader refuses.
	return snapshot if can_restore_checkpoint(snapshot) else {}


## Validate before changing anything. Restoring across a layout, timestep or mass configuration is refused.
func can_restore_checkpoint(candidate: Dictionary, expected_aux_size: int = -1, expected_modes_size: int = -1) -> bool:
	if _reject_endpoint_reentry(): return false
	if not VehicleModel.validate(model).ok:
		return false
	for key in ["format", "tick", "dt", "state", "previous", "aux", "inputs", "modes", "last_loads", "mass", "inertia", "gravity", "stop_at_tick"]:
		if not candidate.has(key):
			return false
	var expected_format: String = ENDPOINT_CHECKPOINT_FORMAT if _endpoint_enabled() else CHECKPOINT_FORMAT
	if typeof(candidate.format) != TYPE_STRING or candidate.format != expected_format or typeof(candidate.tick) != TYPE_INT or candidate.tick < 0 \
			or typeof(candidate.stop_at_tick) != TYPE_INT or candidate.stop_at_tick < -1:
		return false
	if _endpoint_enabled():
		if typeof(candidate.get("state_layout_identity")) != TYPE_STRING \
			or candidate.state_layout_identity != model.state_layout_identity \
			or candidate.size() != 14 + (1 if candidate.has("continuous") else 0):
			return false
	elif candidate.has("state_layout_identity"):
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
	var structural: bool = _array_is_finite(candidate.get("continuous", PackedFloat64Array()), continuous.size()) \
		and _array_is_finite(candidate.aux, aux.size() if expected_aux_size < 0 else expected_aux_size) and _array_is_finite(candidate.inputs, model.input_size) \
		and _loads_are_valid(candidate.last_loads) and typeof(candidate.modes) == TYPE_PACKED_INT64_ARRAY \
		and candidate.modes.size() == (modes.size() if expected_modes_size < 0 else expected_modes_size) and _configuration_is_valid() \
		and _array_is_finite(RB.inertia_inverse(inertia), 6) \
		and _continuous_aux_matches(candidate.get("continuous", PackedFloat64Array()), candidate.aux) \
		and _layout_matches_model(candidate.aux, candidate.modes, candidate.get("continuous", PackedFloat64Array()))
	return structural and (not _endpoint_enabled() or _validate_endpoint_frame(_endpoint_frame(candidate.state,
		candidate.get("continuous", PackedFloat64Array()), candidate.aux, candidate.modes),
		_endpoint_validation_context(candidate.tick, candidate.dt)))


## Explicit recovery restores all dynamic state and pauses. No tick/trace sample is emitted.
func restore_checkpoint(candidate: Dictionary) -> bool:
	if _reject_endpoint_reentry(): return false
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
	last_events = []
	_state_layout_identity = model.state_layout_identity
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
		return model.loads.call(combined, stage_t)
	if model.stage.is_valid():
		var candidate: Variant = model.stage.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), stage_t)
		return candidate.loads if _joint_stage_is_valid(candidate) else PackedFloat64Array([NAN])
	return model.block_loads.call(combined.slice(0, RB.SIZE), combined.slice(RB.SIZE), stage_t)


func _joint_stage_is_valid(candidate: Variant) -> bool:
	if not candidate is Dictionary or not candidate.has_all(["loads", "derivative", "rotor_momentum"]):
		return false
	# Every required field is present; exact size rejects unknown keys without allocating keys() on RK stages.
	var expected_size: int = 3
	if candidate.has("body_derivative"):
		expected_size += 1
	if candidate.has("stage_context"):
		expected_size += 1
	if candidate.size() != expected_size:
		return false
	if candidate.has("body_derivative") and not _array_is_finite(candidate.body_derivative, RB.SIZE):
		return false
	if candidate.has("stage_context") and typeof(candidate.stage_context) != TYPE_DICTIONARY:
		return false
	return _loads_are_valid(candidate.loads) and _array_is_finite(candidate.derivative, continuous.size()) \
		and _array_is_finite(candidate.rotor_momentum, 3)


func _stage_state_is_valid(combined: PackedFloat64Array) -> bool:
	if continuous.is_empty():
		return state_is_valid(combined)
	return _array_is_finite(combined, RB.SIZE + continuous.size()) and state_is_valid(combined.slice(0, RB.SIZE))


func _endpoint_enabled() -> bool:
	return not model.state_layout_identity.is_empty()


func _endpoint_frame(body: PackedFloat64Array, extra: PackedFloat64Array,
		sampled: PackedFloat64Array, discrete: PackedInt64Array) -> Dictionary:
	return {body = body.duplicate(), continuous = extra.duplicate(), aux = sampled.duplicate(), modes = discrete.duplicate()}


func _endpoint_frame_shape_is_valid(frame: Dictionary) -> bool:
	return frame.size() == 4 and frame.has_all(["body", "continuous", "aux", "modes"]) \
		and _checkpoint_state_is_valid(frame.body) \
		and _array_is_finite(frame.continuous, model.continuous_size) \
		and _array_is_finite(frame.aux, model.aux_size) \
		and typeof(frame.modes) == TYPE_PACKED_INT64_ARRAY and frame.modes.size() == model.modes_size


static func _endpoint_validation_context(at_tick: int, timestep: float) -> Dictionary:
	return {tick = at_tick, time_s = at_tick * timestep, dt = timestep}


func _validate_endpoint_frame(frame: Dictionary, context: Dictionary) -> bool:
	if not _endpoint_frame_shape_is_valid(frame):
		return false
	if not model.state_validator.is_valid():
		return true
	var original: Dictionary = frame.duplicate(true)
	var original_context: Dictionary = context.duplicate(true)
	var guard := _capture_endpoint_guard()
	var result: Variant = _call_endpoint_read_only(model.state_validator, [frame, context])
	var pure := _endpoint_guard_unchanged(guard)
	return pure and _guard_values_equal(original, frame) and _guard_values_equal(original_context, context) \
		and typeof(result) == TYPE_BOOL and result


func _endpoint_reset_seal(candidate: Dictionary) -> PackedByteArray:
	return var_to_bytes([candidate.get("state"), candidate.get("inertia_inverse"), candidate.get("loads")])


## Only new endpoint callbacks use these guards. Legacy RK/pre_tick behavior is unchanged.
## They detect net mutation of owned state/model; arbitrary user code is not a sandbox.
const _ENDPOINT_STATE_FIELDS := ["mass", "inertia", "gravity", "inputs", "last_loads", "aux", "modes", "continuous",
	"state", "previous", "tick", "_fixed_dt", "paused", "stop_at_tick", "step_usec", "fault_reason", "last_events",
	"_inertia_inv", "_inertia_cache", "_state_layout_identity", "_endpoint_callback_active", "_endpoint_reentry_attempted",
	"_last_valid_continuous", "_last_valid_state",
	"_last_valid_previous", "_last_valid_aux", "_last_valid_inputs", "_last_valid_loads", "_last_valid_modes",
	"_last_valid_tick", "_last_valid_stop", "_last_valid_mass", "_last_valid_gravity", "_last_valid_inertia"]
const _ENDPOINT_MODEL_FIELDS := ["input_size", "aux_size", "modes_size", "continuous_size", "identity", "state_layout_identity",
	"loads", "stage", "block_loads", "block_derivative", "stage_rotor_momentum", "rotor_momentum", "pre_tick",
	"post_tick", "post_tick_joint", "block_aux", "step_policy", "events", "substeps", "substeps_joint",
	"endpoint_transition", "state_validator"]


static func _guard_copy(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY, TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return value.duplicate(true) if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY] else value.duplicate()
		_:
			return value


func _reject_endpoint_reentry() -> bool:
	if not _endpoint_callback_active:
		return false
	_endpoint_reentry_attempted = true
	return true


func _call_endpoint_read_only(callback: Callable, arguments: Array) -> Variant:
	_endpoint_callback_active = true
	var result: Variant = callback.callv(arguments)
	_endpoint_callback_active = false
	return result


static func _guard_values_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if typeof(left) == TYPE_DICTIONARY:
		if left.keys() != right.keys(): return false
		for key: Variant in left:
			if not _guard_values_equal(left[key], right[key]): return false
		return true
	if typeof(left) == TYPE_ARRAY:
		if left.size() != right.size(): return false
		for index: int in left.size():
			if not _guard_values_equal(left[index], right[index]): return false
		return true
	if typeof(left) in [TYPE_CALLABLE, TYPE_OBJECT, TYPE_SIGNAL]:
		return left == right
	return var_to_bytes(left) == var_to_bytes(right)


func _capture_endpoint_guard() -> Dictionary:
	var owner_values := {}
	var model_values := {}
	for field: String in _ENDPOINT_STATE_FIELDS:
		owner_values[field] = _guard_copy(get(field))
	for field: String in _ENDPOINT_MODEL_FIELDS:
		model_values[field] = _guard_copy(model.get(field))
	return {owner_id = get_instance_id(), owner = owner_values, vehicle = model, contract = model_values}


func _endpoint_guard_matches(guard: Dictionary) -> bool:
	if guard.get("owner_id") != get_instance_id() or model != guard.get("vehicle") \
		or not guard.get("owner") is Dictionary or not guard.get("contract") is Dictionary:
		return false
	for field: String in _ENDPOINT_STATE_FIELDS:
		if not guard.owner.has(field) or not _guard_values_equal(get(field), guard.owner[field]): return false
	for field: String in _ENDPOINT_MODEL_FIELDS:
		if not guard.contract.has(field) or not _guard_values_equal(model.get(field), guard.contract[field]): return false
	return true


func _endpoint_guard_unchanged(guard: Dictionary) -> bool:
	if _endpoint_guard_matches(guard):
		return true
	model = guard.vehicle
	for field: String in _ENDPOINT_STATE_FIELDS:
		set(field, _guard_copy(guard.owner[field]))
	for field: String in _ENDPOINT_MODEL_FIELDS:
		model.set(field, _guard_copy(guard.contract[field]))
	return false


func _endpoint_events(added: Variant, located: Array[Dictionary], start_time: float) -> Dictionary:
	if typeof(added) != TYPE_ARRAY or added.size() + located.size() > MAX_ENDPOINT_EVENTS:
		return {ok = false, message = "endpoint event count or array is invalid"}
	var merged: Array = located.duplicate()
	merged.append_array(added)
	var ids := {}
	var payload_budget := {left = 4096}
	for event: Variant in merged:
		if typeof(event) != TYPE_DICTIONARY or not _endpoint_event_value(event, 0, payload_budget):
			return {ok = false, message = "endpoint event payload is nonfinite, unsupported or exceeds bounds"}
		if event.has("event_id"):
			var id: Variant = event.event_id
			if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 256 or ids.has(id):
				return {ok = false, message = "endpoint event_id must be a unique bounded nonempty string"}
			ids[id] = true
	return _unpack_policy_result({state = PackedFloat64Array(), events = merged}, start_time)


static func _endpoint_event_value(value: Variant, depth: int, budget: Dictionary) -> bool:
	if depth > 8 or budget.left <= 0: return false
	budget.left -= 1
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			return value.length() <= 1024
		TYPE_DICTIONARY:
			if value.size() > 64: return false
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).length() > 256 or not _endpoint_event_value(value[key], depth + 1, budget): return false
			return true
		TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			if value.size() > 256: return false
			for item: Variant in value:
				if not _endpoint_event_value(item, depth + 1, budget): return false
			return true
		_:
			return false
