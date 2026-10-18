# HELI-17b: consume one complete Simulation fixed tick around a rotor-stop event.
# The callback contract matches VehicleModel.step_policy(state,t,dt,f,first); since SF-04 the accepted result is
# {state, events} so the kernel records each located rotor stop ({type, time_s, time_error_bound_s}).
# SF-04b: this is the kernel's domain-guarded locator. The rotorcraft law refuses Ω < 0 and a refused stage faults
# the tick, so no stage beyond zero is ever evaluated (the shared physics/event_step.gd needs that continuation).
# Qualified against an analytic stop and cross-checked with event_step: fourth order, agreement to 1e-10 s
# (tests/test_sf_event_refinement.gd).
extends RefCounted

const RK = preload("res://physics/integrator.gd")
const OMEGA: int = 13
const TERMINAL_SPEED_RAD_S: float = 1.0e-4
const EVENT_TIME_TOLERANCE_S: float = 1.0e-12
const MAX_TICK_SUBSTEPS: int = 256
const MAX_EVENT_COUNT: int = 4


## Return one fully advanced combined state. A malformed/error state returns an
## empty array so Simulation rejects the tick and restores its saved snapshot.
static func step(state: PackedFloat64Array, time: float, dt: float, f: Callable,
		first: PackedFloat64Array) -> Variant:
	if state.size() <= OMEGA or first.size() != state.size() or not is_finite(time) \
			or not is_finite(dt) or dt <= 0.0 or not f.is_valid() or not _finite(state) or not _finite(first):
		return PackedFloat64Array()
	if state[OMEGA] < 0.0:
		return PackedFloat64Array()
	var current: PackedFloat64Array = state.duplicate()
	var elapsed: float = 0.0
	var event_count: int = 0
	var events: Array[Dictionary] = []
	var substeps: int = 0
	var derivative: PackedFloat64Array = first.duplicate()
	while elapsed < dt:
		substeps += 1
		if substeps > MAX_TICK_SUBSTEPS:
			return PackedFloat64Array()
		var remaining: float = dt - elapsed
		if remaining <= 0.0:
			break
		if substeps > 1:
			derivative = f.call(current, time + elapsed)
			if derivative.size() != current.size() or not _finite(derivative):
				return PackedFloat64Array()
		var omega: float = current[OMEGA]
		if omega < 0.0:
			return PackedFloat64Array()
		if omega > 0.0 and derivative[OMEGA] < 0.0:
			var stop_estimate: float = omega / -derivative[OMEGA]
			if stop_estimate <= remaining:
				if omega <= TERMINAL_SPEED_RAD_S:
					if event_count >= MAX_EVENT_COUNT:
						return PackedFloat64Array()
					var event: Dictionary = _locate_stop_midpoint(current, time + elapsed,
						remaining, f, derivative, stop_estimate)
					if event.get("event", false):
						current = event.state
						current[OMEGA] = 0.0
						current = RK.normalize_attitude(current)
						elapsed += float(event.elapsed_s)
						event_count += 1
						var bracket: PackedFloat64Array = event.get("event_bracket_s", PackedFloat64Array([0.0, 0.0]))
						events.append({"type": "rotor_stop", "time_s": time + elapsed, "time_error_bound_s": bracket[1] - bracket[0]})
						continue
					if not event.get("ok", false):
						return PackedFloat64Array()
				# Keep all RK stages on the positive-speed side while approaching a
				# finite stop. Once in the terminal band, the event locator handles root.
				remaining = minf(remaining, 0.5 * stop_estimate)
		var h: float = remaining
		var trial: Dictionary = {}
		var accepted: bool = false
		for _attempt: int in range(56):
			trial = _rk4_guarded(current, time + elapsed, h, f, derivative)
			if trial.get("ok", false) and trial.state[OMEGA] >= 0.0:
				accepted = true
				break
			if not trial.get("crossing", false):
				return PackedFloat64Array()
			h *= 0.5
			if h <= EVENT_TIME_TOLERANCE_S:
				break
		if not accepted or h <= 0.0:
			return PackedFloat64Array()
		current = trial.state
		elapsed += h
		if elapsed > dt:
			return PackedFloat64Array()
		if dt - elapsed <= maxf(1.0e-15, dt * 1.0e-14):
			elapsed = dt
	if not _finite(current):
		return PackedFloat64Array()
	return {"state": current, "events": events}


static func _rk4_guarded(state: PackedFloat64Array, time: float, h: float,
		f: Callable, first: PackedFloat64Array) -> Dictionary:
	var k1: PackedFloat64Array = first
	var stage2: PackedFloat64Array = _axpy(state, h * 0.5, k1)
	if stage2[OMEGA] < 0.0:
		return {"ok": false, "crossing": true}
	var k2: PackedFloat64Array = f.call(stage2, time + h * 0.5)
	if k2.size() != state.size() or not _finite(k2):
		return {"ok": false, "crossing": false}
	var stage3: PackedFloat64Array = _axpy(state, h * 0.5, k2)
	if stage3[OMEGA] < 0.0:
		return {"ok": false, "crossing": true}
	var k3: PackedFloat64Array = f.call(stage3, time + h * 0.5)
	if k3.size() != state.size() or not _finite(k3):
		return {"ok": false, "crossing": false}
	var stage4: PackedFloat64Array = _axpy(state, h, k3)
	if stage4[OMEGA] < 0.0:
		return {"ok": false, "crossing": true}
	var k4: PackedFloat64Array = f.call(stage4, time + h)
	if k4.size() != state.size() or not _finite(k4):
		return {"ok": false, "crossing": false}
	var result: PackedFloat64Array = state.duplicate()
	for index: int in range(result.size()):
		result[index] += h / 6.0 * (k1[index] + 2.0 * k2[index] + 2.0 * k3[index] + k4[index])
	if not _finite(result):
		return {"ok": false, "crossing": false}
	if result[OMEGA] < 0.0:
		return {"ok": false, "crossing": true}
	return {"ok": true, "state": RK.normalize_attitude(result)}


## Bisection locates the integrated Ω(t+h)=0 root with an explicit-midpoint
## candidate. Its only callback stage is at t+h/2, which stays on the positive
## side around the root; a negative predicted endpoint is used only as a scalar
## bracket and is never returned to Simulation or passed to the callback.
static func _locate_stop_midpoint(state: PackedFloat64Array, time: float, remaining: float,
		f: Callable, first: PackedFloat64Array, estimate: float) -> Dictionary:
	var low: float = 0.0
	var high: float = minf(remaining, maxf(1.5 * estimate, EVENT_TIME_TOLERANCE_S))
	var bracketed: bool = false
	for _expand: int in range(24):
		var upper: Dictionary = _midpoint_candidate(state, time, high, f, first)
		if upper.get("crossing", false) or (upper.get("ok", false) and upper.state[OMEGA] <= 0.0):
			bracketed = true
			break
		if not upper.get("ok", false):
			return {"ok": false}
		if high >= remaining:
			return {"ok": true, "event": false}
		high = minf(remaining, high * 2.0)
	if not bracketed:
		return {"ok": true, "event": false}
	var low_state: PackedFloat64Array = state.duplicate()
	for _iteration: int in range(64):
		if high - low <= maxf(EVENT_TIME_TOLERANCE_S, remaining * 1.0e-13):
			break
		var middle: float = 0.5 * (low + high)
		var candidate: Dictionary = _midpoint_candidate(state, time, middle, f, first)
		if candidate.get("crossing", false):
			high = middle
		elif not candidate.get("ok", false):
			return {"ok": false}
		elif candidate.state[OMEGA] > 0.0:
			low = middle
			low_state = candidate.state
		else:
			high = middle
	var event_time: float = 0.5 * (low + high)
	var event_state: PackedFloat64Array = low_state
	if event_state.size() != state.size():
		return {"ok": false}
	return {"ok": true, "event": true, "state": event_state, "elapsed_s": event_time,
		"event_bracket_s": PackedFloat64Array([low, high])}


static func _midpoint_candidate(state: PackedFloat64Array, time: float, h: float,
		f: Callable, first: PackedFloat64Array) -> Dictionary:
	var middle: PackedFloat64Array = _axpy(state, h * 0.5, first)
	if middle[OMEGA] < 0.0:
		return {"ok": false, "crossing": true}
	var derivative: PackedFloat64Array = f.call(middle, time + h * 0.5)
	if derivative.size() != state.size() or not _finite(derivative):
		return {"ok": false, "crossing": false}
	var result: PackedFloat64Array = _axpy(state, h, derivative)
	if not _finite(result):
		return {"ok": false, "crossing": false}
	return {"ok": true, "state": RK.normalize_attitude(result)}
static func _axpy(base: PackedFloat64Array, scale: float, direction: PackedFloat64Array) -> PackedFloat64Array:
	var result: PackedFloat64Array = base.duplicate()
	for index: int in range(result.size()):
		result[index] += scale * direction[index]
	return result


static func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
