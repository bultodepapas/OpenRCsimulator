# SF-04: the kernel's event locator for one declared boundary. A continuous state value (combined index at or
# beyond the rigid body) is held at or above zero: RK4 trials run through the model's validated stage derivative,
# a crossing is bracketed with physics/event_bracket.gd and located to TIME_TOL in local tick time, the model's
# transition projects the state onto the boundary, and the remainder of the tick continues from there. A trial
# that dips below zero without a negative endpoint is halved. Negative trial values are continuations used only
# to locate a crossing; accepted states never cross. This is the EL1d rotor-stop algorithm (physics/electric_stop.gd
# remains its compatibility wrapper); its numerics are unchanged, so existing trajectories are byte-identical.
# Local tick time and the absolute clock have different precision: the bracket tolerance applies to the former.
# SF-04b: the derivative must accept those beyond-boundary stage states (a smooth continuation); a law that refuses
# them belongs behind a domain-guarded step policy such as physics/rotorcraft/simulation_step_adapter.gd.
extends RefCounted

const RK: Script = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/integrator.gd")
const Bracket: Script = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/event_bracket.gd")
const TIME_TOL: float = 1e-12
const VALUE_TOL: float = 1e-7
const MAX_SEGMENTS: int = 128
const MAX_ROOT_TRIALS: int = 128
const MAX_DT_S: float = 60.0
const BODY_SIZE: int = 13


## Advance `s` (body plus continuous blocks) from `time_s` by `dt`. `derivative(state, stage_t)` is the validated
## stage derivative; `first` may carry the tick's own evaluation at `s`. `transition(state, index) -> state`
## applies the discrete change at the boundary and must leave `state[index]` at exactly zero.
## Returns {ok, state, events: [{type, time_s}]}, events in tick order.
static func advance(s: PackedFloat64Array, time_s: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, index: int, transition: Callable, type: String = "stop") -> Dictionary:
	if index < BODY_SIZE or index >= s.size() or not _finite(s, s.size()) or s[index] < 0.0 \
			or not is_finite(time_s) or not is_finite(dt) or dt <= 0.0 or dt > MAX_DT_S or not is_finite(time_s + dt) \
			or not derivative.is_valid() or not transition.is_valid() \
			or (not first.is_empty() and not _finite(first, s.size())):
		return {ok = false}
	var state: PackedFloat64Array = s.duplicate()
	var elapsed: float = 0.0
	var step: float = dt
	var events: Array[Dictionary] = []
	var initial: PackedFloat64Array = first
	for segment: int in MAX_SEGMENTS:
		var probe: Dictionary = _trial(state, time_s + elapsed, step, derivative, initial, index)
		if not probe.ok:
			return {ok = false}
		var candidate: PackedFloat64Array = probe.state
		if candidate[index] == 0.0 and state[index] > 0.0 and probe.max_rate <= 0.0:
			state = transition.call(candidate, index)
			if not _finite(state, s.size()) or state[index] != 0.0:
				return {ok = false}
			elapsed += step
			events.append({"type": type, "time_s": time_s + elapsed})
			if elapsed >= dt:
				return {ok = true, state = state, events = events}
			step = dt - elapsed
			initial = PackedFloat64Array()
			continue
		if candidate[index] <= 0.0 and state[index] > 0.0 and probe.max_rate <= 0.0:
			var crossing_result: Dictionary = _locate_crossing(state, time_s + elapsed, step,
				derivative, initial, index, candidate)
			if not crossing_result.ok:
				return {ok = false}
			var at: PackedFloat64Array = crossing_result.state
			var crossing: float = crossing_result.offset_s
			state = transition.call(at, index)
			if not _finite(state, s.size()) or state[index] != 0.0:
				return {ok = false}
			elapsed += crossing
			events.append({"type": type, "time_s": time_s + elapsed})
		elif probe.minimum < 0.0:
			# An internal crossing without a negative endpoint needs a smaller trial.
			# A departure from exact rest into unsupported reverse motion also fails boundedly.
			step *= 0.5
			if step < TIME_TOL:
				return {ok = false}
			continue
		else:
			state = candidate
			elapsed += step
		if elapsed >= dt:
			return {ok = true, state = state, events = events}
		step = dt - elapsed
		initial = PackedFloat64Array()
	return {ok = false}


## The upper side remains nonpositive; the transition only follows a bounded time AND value error.
static func _locate_crossing(start: PackedFloat64Array, time_s: float, dt: float,
		derivative: Callable, first: PackedFloat64Array, index: int,
		high_state: PackedFloat64Array) -> Dictionary:
	var lo: float = 0.0
	var hi: float = dt
	var low_value: float = start[index]
	var high: PackedFloat64Array = high_state
	var bisect: bool = false
	for iteration: int in MAX_ROOT_TRIALS:
		if hi - lo <= TIME_TOL and high[index] <= 0.0 and absf(high[index]) <= VALUE_TOL:
			return {ok = true, state = high, offset_s = hi}
		var old_width: float = hi - lo
		var mid: float = Bracket.propose(lo, hi, low_value, high[index], TIME_TOL, bisect)
		if not is_finite(mid):
			break
		var located: Dictionary = _trial(start, time_s, mid, derivative, first, index)
		if not located.ok:
			return {ok = false}
		var value: float = located.state[index]
		if value > 0.0:
			lo = mid
			low_value = value
		else:
			hi = mid
			high = located.state
		bisect = not bisect and hi - lo > 0.5 * old_width
	if hi - lo <= TIME_TOL and high[index] <= 0.0 and absf(high[index]) <= VALUE_TOL:
		return {ok = true, state = high, offset_s = hi}
	return {ok = false}


static func _trial(s: PackedFloat64Array, t: float, h: float, f: Callable,
		first: PackedFloat64Array, index: int) -> Dictionary:
	var initial: PackedFloat64Array = f.call(s, t) if first.is_empty() else first
	if not _finite(initial, s.size()):
		return {ok = false}
	var sample: Dictionary = {minimum = s[index], max_rate = initial[index], valid = true}
	var tracked: Callable = func(values: PackedFloat64Array, at: float) -> PackedFloat64Array:
		sample.minimum = minf(sample.minimum, values[index])
		var evaluation: PackedFloat64Array = values
		if s[index] > 0.0 and values[index] == 0.0:
			# Use the moving-side limit when a trial lands exactly on the boundary.
			# This is only a derivative query, never a committed value or time offset.
			evaluation = values.duplicate()
			evaluation[index] = VALUE_TOL * 0.01
		var rate: PackedFloat64Array = f.call(evaluation, at)
		if not _finite(rate, s.size()):
			sample.valid = false
			rate = s.duplicate()
			rate.fill(0.0)
		sample.max_rate = maxf(sample.max_rate, rate[index])
		return rate
	var result: PackedFloat64Array = RK.rk4_step_at(s, t, h, tracked, initial)
	return {ok = sample.valid and _finite(result, s.size()), state = result,
		minimum = minf(sample.minimum, result[index]), max_rate = sample.max_rate}


static func _finite(values: PackedFloat64Array, size: int) -> bool:
	if values.size() != size:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true
