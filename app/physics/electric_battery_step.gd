# EL2a: bounded battery-exhaustion localization composed with the EL1d rotor-stop step.
# Negative charge and RPM are trial continuations only; accepted states stay in-domain.
extends RefCounted

const Stop: Script = preload("res://physics/electric_stop.gd")

const BODY_RATE_INDEX: int = 10
const BODY_STATE_SIZE: int = 13
const TIME_TOL: float = 1e-12
const CHARGE_TOL_C: float = 1e-10
const LEFT_LIMIT_CHARGE_C: float = 1e-30
const MAX_DT_S: float = 60.0
const MAX_SEGMENTS: int = 128
const MAX_REFINEMENTS: int = 64
const MAX_BISECTIONS: int = 128


## Advance a coupled state containing shaft RPM and remaining pack charge in coulombs.
## `derivative(state, time_s)` owns source evaluation and the charge/energy/loss rates.
## `project_rotor(state, rpm_index)` must preserve all state fields except body rates and RPM.
## Returns chronological `{type, time_s}` events; the rotor event comes first at a shared time.
static func advance(s: PackedFloat64Array, time_s: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, rpm_index: int, charge_index: int,
		project_rotor: Callable) -> Dictionary:
	if rpm_index < BODY_STATE_SIZE or rpm_index >= s.size() or charge_index < BODY_STATE_SIZE \
			or charge_index >= s.size() or charge_index == rpm_index or not _finite(s, s.size()) \
			or s[rpm_index] < 0.0 or s[charge_index] < 0.0 or not is_finite(time_s) \
			or not is_finite(dt) or dt <= 0.0 or dt > MAX_DT_S or not is_finite(time_s + dt) \
			or time_s + dt <= time_s or not derivative.is_valid() or not project_rotor.is_valid() \
			or (not first.is_empty() and not _finite(first, s.size())):
		return _failure("invalid state, indices, callback, or bounded timestep")
	if not first.is_empty() and first[charge_index] > 0.0:
		return _failure("positive charge derivative is unsupported")

	var state: PackedFloat64Array = s.duplicate()
	var events: Array[Dictionary] = []
	var elapsed: float = 0.0
	var initial: PackedFloat64Array = first
	var accepted_segments: int = 0

	if state[charge_index] == 0.0:
		return _finish_exhausted(state, time_s, dt, derivative, rpm_index, charge_index,
			project_rotor, events)

	while accepted_segments < MAX_SEGMENTS:
		var remaining: float = dt - elapsed
		if remaining <= 0.0:
			return _success(state, events)
		var trial_step: float = remaining
		var refined: bool = false
		var accepted_piece: bool = false
		for refinement: int in MAX_REFINEMENTS:
			var trial: Dictionary = _stop_trial(state, time_s + elapsed, trial_step, derivative,
				initial, rpm_index, charge_index, project_rotor, true)
			if not trial.ok:
				return _failure(str(trial.get("message", "active battery trial failed")))
			var candidate: PackedFloat64Array = trial.state
			var candidate_charge: float = candidate[charge_index]
			if candidate_charge > state[charge_index]:
				return _failure("charge increased during a motoring-only trial")

			if candidate_charge > 0.0:
				if float(trial.minimum_charge_c) <= 0.0:
					# A negative RK stage with a positive endpoint is unresolved, not a safe step.
					trial_step *= 0.5
					refined = true
					if trial_step < TIME_TOL:
						return _failure("charge boundary excursion did not resolve under step halving")
					continue
				_append_rotor_events(events, trial.rotor_times, NAN)
				state = candidate
				elapsed += trial_step
				initial = PackedFloat64Array()
				accepted_segments += 1
				accepted_piece = true
				break

			var crossing: Dictionary = _locate_battery_crossing(state, time_s + elapsed,
				trial_step, derivative, initial, rpm_index, charge_index, project_rotor, trial)
			if not crossing.ok:
				return _failure(str(crossing.get("message", "battery exhaustion localization failed")))
			var crossing_state: PackedFloat64Array = crossing.state.duplicate()
			var residual_c: float = crossing_state[charge_index]
			if residual_c > 0.0 or absf(residual_c) > CHARGE_TOL_C:
				return _failure("localized battery charge residual exceeded tolerance")
			var event_time: float = time_s + elapsed + float(crossing.offset_s)
			_append_rotor_events(events, crossing.rotor_times, event_time)
			crossing_state[charge_index] = 0.0
			_append_battery_event(events, event_time, residual_c, float(crossing.time_error_s))
			var after_crossing: float = dt - elapsed - float(crossing.offset_s)
			if after_crossing <= 0.0:
				return _success(crossing_state, events)
			return _finish_exhausted(crossing_state, event_time, after_crossing, derivative,
				rpm_index, charge_index, project_rotor, events)

		if not accepted_piece:
			if refined:
				return _failure("battery step refinement exhausted its bounded attempts")
			return _failure("battery step did not accept a bounded segment")
	return _failure("battery step exceeded its bounded segment count")


static func _finish_exhausted(state: PackedFloat64Array, time_s: float, dt: float,
		derivative: Callable, rpm_index: int, charge_index: int, project_rotor: Callable,
		events: Array[Dictionary]) -> Dictionary:
	if dt <= 0.0:
		return _success(state, events)
	var exhausted: Dictionary = _stop_trial(state, time_s, dt, derivative,
		PackedFloat64Array(), rpm_index, charge_index, project_rotor, false)
	if not exhausted.ok:
		return _failure(str(exhausted.get("message", "exhausted-source coast failed")))
	var endpoint: PackedFloat64Array = exhausted.state
	if endpoint[charge_index] != 0.0:
		return _failure("exhausted source changed remaining charge")
	_append_rotor_events(events, exhausted.rotor_times, NAN)
	return _success(endpoint, events)


static func _locate_battery_crossing(start: PackedFloat64Array, time_s: float, dt: float,
		derivative: Callable, first: PackedFloat64Array, rpm_index: int, charge_index: int,
		project_rotor: Callable, high_trial: Dictionary) -> Dictionary:
	var lo: float = 0.0
	var hi: float = dt
	var high_state: PackedFloat64Array = high_trial.state
	var high_times: PackedFloat64Array = high_trial.rotor_times
	if high_state[charge_index] > 0.0:
		return {ok = false, message = "battery crossing probe did not reach zero"}
	for iteration: int in MAX_BISECTIONS:
		if hi - lo <= TIME_TOL and absf(high_state[charge_index]) <= CHARGE_TOL_C:
			return {ok = true, state = high_state, rotor_times = high_times,
				offset_s = hi, time_error_s = hi - lo}
		var mid: float = lo + 0.5 * (hi - lo)
		if mid <= lo or mid >= hi:
			break
		var located: Dictionary = _stop_trial(start, time_s, mid, derivative, first,
			rpm_index, charge_index, project_rotor, true)
		if not located.ok:
			return {ok = false, message = str(located.get("message", "battery root trial failed"))}
		var q: float = located.state[charge_index]
		if q > 0.0:
			lo = mid
		else:
			hi = mid
			high_state = located.state
			high_times = located.rotor_times
		if hi - lo <= TIME_TOL and absf(high_state[charge_index]) <= CHARGE_TOL_C:
			return {ok = true, state = high_state, rotor_times = high_times,
				offset_s = hi, time_error_s = hi - lo}
	# A positive lower endpoint is not a battery event. The negative upper endpoint is the
	# deterministic accepted side once both its charge residual and the time bracket are bounded.
	if hi - lo <= TIME_TOL and high_state[charge_index] <= 0.0 \
			and absf(high_state[charge_index]) <= CHARGE_TOL_C:
		return {ok = true, state = high_state, rotor_times = high_times,
			offset_s = hi, time_error_s = hi - lo}
	return {ok = false, message = "battery event failed charge/time localization bounds"}


static func _stop_trial(start: PackedFloat64Array, time_s: float, dt: float,
		derivative: Callable, first: PackedFloat64Array, rpm_index: int, charge_index: int,
		project_rotor: Callable, connected: bool) -> Dictionary:
	var tracker: Dictionary = {
		"ok": true,
		"message": "",
		"minimum_charge_c": start[charge_index],
	}
	var start_connected: bool = connected and start[charge_index] > 0.0
	if not first.is_empty() and first[charge_index] > 0.0:
		return {ok = false, message = "positive charge derivative is unsupported"}
	if not first.is_empty() and not connected and first[charge_index] != 0.0:
		return {ok = false, message = "exhausted source must hold charge at zero"}

	var tracked: Callable = func(values: PackedFloat64Array, at: float) -> PackedFloat64Array:
		if not _finite(values, start.size()):
			tracker.ok = false
			tracker.message = "nonfinite or malformed derivative state"
			return _zero_state(start.size())
		tracker.minimum_charge_c = minf(float(tracker.minimum_charge_c), values[charge_index])
		var evaluated: PackedFloat64Array = values
		if start_connected and values[charge_index] == 0.0:
			# OCV(0) connected left-limit for this derivative query only. The trial value and
			# accepted state are never changed by this adapter.
			evaluated = values.duplicate()
			evaluated[charge_index] = -LEFT_LIMIT_CHARGE_C
		var raw_rate: Variant = derivative.call(evaluated, at)
		if typeof(raw_rate) != TYPE_PACKED_FLOAT64_ARRAY:
			tracker.ok = false
			tracker.message = "derivative must return a PackedFloat64Array"
			return _zero_state(start.size())
		var rate: PackedFloat64Array = raw_rate
		if not _finite(rate, start.size()):
			tracker.ok = false
			tracker.message = "derivative returned a nonfinite or malformed rate"
			return _zero_state(start.size())
		if rate[charge_index] > 0.0:
			tracker.ok = false
			tracker.message = "positive charge derivative is unsupported"
		elif not connected and rate[charge_index] != 0.0:
			tracker.ok = false
			tracker.message = "exhausted source must hold charge at zero"
		return rate

	var safe_project: Callable = func(values: PackedFloat64Array, index: int) -> PackedFloat64Array:
		var raw_projected: Variant = project_rotor.call(values, index)
		if typeof(raw_projected) != TYPE_PACKED_FLOAT64_ARRAY:
			tracker.ok = false
			tracker.message = "rotor projection must return a PackedFloat64Array"
			return _zero_state(start.size())
		var projected: PackedFloat64Array = raw_projected
		if not _finite(projected, start.size()) or index != rpm_index:
			tracker.ok = false
			tracker.message = "rotor projection returned an invalid state"
			return _zero_state(start.size())
		for i: int in projected.size():
			if i != rpm_index and (i < BODY_RATE_INDEX or i >= BODY_RATE_INDEX + 3) \
					and projected[i] != values[i]:
				tracker.ok = false
				tracker.message = "rotor projection changed a non-rotor state field"
				return _zero_state(start.size())
		return projected

	var stopped: Dictionary = Stop.advance(start, time_s, dt, tracked, first, rpm_index, safe_project)
	if not tracker.ok:
		return {ok = false, message = str(tracker.message)}
	if not stopped.ok:
		return {ok = false, message = "rotor stop integration failed"}
	var endpoint: PackedFloat64Array = stopped.state
	if not _finite(endpoint, start.size()) or endpoint[rpm_index] < 0.0:
		return {ok = false, message = "rotor stop returned an invalid endpoint"}
	if not connected and endpoint[charge_index] != 0.0:
		return {ok = false, message = "exhausted source changed remaining charge"}
	return {
		"ok": true,
		"state": endpoint,
		"rotor_times": stopped.events,
		"minimum_charge_c": float(tracker.minimum_charge_c),
	}


static func _append_rotor_events(events: Array[Dictionary], times: PackedFloat64Array,
		shared_time: float) -> void:
	for at: float in times:
		var event_time: float = at
		if is_finite(shared_time) and absf(event_time - shared_time) <= TIME_TOL:
			event_time = shared_time
		events.append({"type": "rotor_stop", "time_s": event_time})


static func _append_battery_event(events: Array[Dictionary], at: float, residual_c: float,
		time_error_s: float) -> void:
	# Give an event at the same numerical boundary one canonical timestamp and stable order.
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].type != "rotor_stop":
			break
		if absf(float(events[i].time_s) - at) <= TIME_TOL:
			events[i].time_s = at
	events.append({
		"type": "battery_exhausted",
		"time_s": at,
		"charge_residual_c": residual_c,
		"time_error_bound_s": time_error_s,
	})


static func _success(state: PackedFloat64Array, events: Array[Dictionary]) -> Dictionary:
	if state.size() <= 0:
		return _failure("empty accepted state")
	return {"ok": true, "state": state, "events": events}


static func _finite(values: PackedFloat64Array, size: int) -> bool:
	if values.size() != size:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _zero_state(size: int) -> PackedFloat64Array:
	var state: PackedFloat64Array = PackedFloat64Array()
	state.resize(size)
	return state


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
