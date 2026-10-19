## Bounded RK4 integration across several scalar event surfaces.
## Event records contain `id`, `type`, `surface(state,time)->float`, `sense` (falling/rising/either),
## `transition(state,time)->{ok,state,event?}`, and optional `enabled(state,time)->bool` and `priority`.
## State is copied before every trial; failure never returns a partially accepted candidate.
extends RefCounted

const RK: Script = preload("res://physics/integrator.gd")
const Bracket: Script = preload("res://physics/event_bracket.gd")

const TIME_TOL: float = 1e-12
const MAX_SEGMENTS: int = 256
const MAX_ROOT_TRIALS: int = 128
const MAX_DT_S: float = 60.0
const SURFACE_TOL: float = 1e-10


static func advance(state: PackedFloat64Array, time_s: float, dt: float,
		derivative: Callable, first: PackedFloat64Array, events: Array,
		max_surface_evaluations: int = 200000) -> Dictionary:
	if state.is_empty() or not _finite(state, state.size()) or not is_finite(time_s) \
			or not is_finite(dt) or dt <= 0.0 or dt > MAX_DT_S or not is_finite(time_s + dt) \
			or not derivative.is_valid() or (not first.is_empty() and not _finite(first, state.size())) \
			or events.is_empty() or max_surface_evaluations <= 0:
		return _failure("resource event step input is malformed")
	var ids: Dictionary = {}
	for event_value: Variant in events:
		if not event_value is Dictionary:
			return _failure("resource event record must be a Dictionary")
		var event: Dictionary = event_value
		var id: Variant = event.get("id", null)
		if not id is String or id.strip_edges().is_empty() or ids.has(id) \
				or not event.get("type", "") is String or not event.get("surface") is Callable \
				or not event.get("transition") is Callable \
				or event.get("sense", "") not in ["falling", "rising", "either"] \
				or not event.get("surface_unit", "") is String or str(event.surface_unit).strip_edges().is_empty() \
				or (event.has("enabled") and not event.enabled is Callable):
			return _failure("resource event definition is malformed")
		ids[id] = true

	var accepted: PackedFloat64Array = state.duplicate()
	var elapsed: float = 0.0
	var step: float = dt
	var initial_rate: PackedFloat64Array = first
	var reported: Array[Dictionary] = []
	var evaluations: int = 0
	for _segment: int in MAX_SEGMENTS:
		var start_values: Dictionary = _surface_values(accepted, time_s + elapsed, events,
			max_surface_evaluations - evaluations)
		evaluations += int(start_values.get("evaluations", 0))
		if not start_values.get("ok", false):
			return _failure(str(start_values.get("message", "event surface failed")))
		var trial: Dictionary = _trial(accepted, time_s + elapsed, step, derivative, initial_rate,
			events, start_values.values, max_surface_evaluations - evaluations)
		evaluations += int(trial.get("evaluations", 0))
		if not trial.get("ok", false):
			return _failure(str(trial.get("message", "resource event trial failed")))

		var endpoint: PackedFloat64Array = trial.state
		var crossings: Array[Dictionary] = []
		var internal_crossing: bool = false
		for event: Dictionary in events:
			var id: String = str(event.id)
			var start_value: float = float(start_values.values[id])
			var end_sample: Dictionary = _surface_sample(event, endpoint, time_s + elapsed + step,
				max_surface_evaluations - evaluations)
			evaluations += int(end_sample.get("evaluations", 0))
			if not end_sample.get("ok", false):
				return _failure(str(end_sample.get("message", "event endpoint surface failed")))
			if not end_sample.enabled:
				continue
			var end_value: float = float(end_sample.value)
			var extrema: Dictionary = trial.extrema[id]
			var crossed_end: bool = _crossed(start_value, end_value, str(event.sense))
			var crossed_inside: bool = _crossed_extrema(start_value, float(extrema.minimum),
				float(extrema.maximum), str(event.sense))
			if crossed_end:
				crossings.append({event = event, start_value = start_value, end_value = end_value})
			elif crossed_inside:
				internal_crossing = true

		if not crossings.is_empty():
			var located: Array[Dictionary] = []
			for crossing: Dictionary in crossings:
				var root: Dictionary = _locate(accepted, time_s + elapsed, step, derivative,
					initial_rate, crossing.event, float(crossing.start_value), float(crossing.end_value),
					max_surface_evaluations - evaluations)
				evaluations += int(root.get("evaluations", 0))
				if not root.get("ok", false):
					return _failure(str(root.get("message", "event root failed")))
				located.append({event = crossing.event, state = root.state, offset_s = float(root.offset_s),
					residual = float(root.residual), time_error_s = float(root.time_error_s)})
			located.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if absf(float(a.offset_s) - float(b.offset_s)) <= TIME_TOL:
					return _event_before(a.event, b.event)
				return float(a.offset_s) < float(b.offset_s))
			var earliest: float = float(located[0].offset_s)
			var root_state: PackedFloat64Array = located[0].state.duplicate()
			var tied: Array[Dictionary] = []
			for candidate: Dictionary in located:
				if absf(float(candidate.offset_s) - earliest) <= TIME_TOL:
					tied.append(candidate)
				else:
					break
			tied.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return _event_before(a.event, b.event))
			var applied: int = 0
			for candidate: Dictionary in tied:
				var event: Dictionary = candidate.event
				var surface_at_root: Dictionary = _surface_sample(event, root_state,
					time_s + elapsed + earliest, max_surface_evaluations - evaluations)
				evaluations += int(surface_at_root.get("evaluations", 0))
				if not surface_at_root.get("ok", false):
					return _failure(str(surface_at_root.get("message", "event tie surface failed")))
				if not surface_at_root.enabled or absf(float(surface_at_root.value)) > _event_tolerance(event):
					continue
				var transitioned: Variant = event.transition.call(root_state.duplicate(),
					time_s + elapsed + earliest)
				if not transitioned is Dictionary or not transitioned.get("ok", false) \
						or not transitioned.get("state") is PackedFloat64Array \
						or not _finite(transitioned.state, accepted.size()):
					return _failure("event transition failed for %s" % str(event.id))
				root_state = transitioned.state.duplicate()
				applied += 1
				var report: Dictionary = {type = str(event.type), time_s = time_s + elapsed + earliest,
					id = str(event.id), surface_residual = float(surface_at_root.value),
					surface_unit = str(event.surface_unit), time_error_bound_s = float(candidate.time_error_s)}
				var details: Variant = transitioned.get("event", {})
				if details is Dictionary:
					report.merge(details, true)
				reported.append(report)
			if applied == 0:
				return _failure("no event transition remained valid at the located boundary")
			if not _finite(root_state, accepted.size()):
				return _failure("event transition returned a nonfinite state")
			accepted = root_state
			elapsed += earliest
			if elapsed >= dt:
				return {ok = true, state = accepted, events = reported, surface_evaluations = evaluations}
			step = dt - elapsed
			initial_rate = PackedFloat64Array()
			continue

		if internal_crossing:
			step *= 0.5
			if step < TIME_TOL:
				return _failure("internal event crossing could not be isolated")
			continue
		accepted = endpoint
		elapsed += step
		if elapsed >= dt:
			return {ok = true, state = accepted, events = reported, surface_evaluations = evaluations}
		step = dt - elapsed
		initial_rate = PackedFloat64Array()
	return _failure("resource event step exceeded its deterministic segment bound")


static func _trial(state: PackedFloat64Array, time_s: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, events: Array, start_values: Dictionary,
		remaining_evaluations: int) -> Dictionary:
	if remaining_evaluations <= 0:
		return {ok = false, message = "resource event surface evaluation budget exhausted"}
	var tracker: Dictionary = {ok = true, message = "", evaluations = 0, extrema = {}}
	for event: Dictionary in events:
		var id: String = str(event.id)
		var value: float = float(start_values[id])
		tracker.extrema[id] = {minimum = value, maximum = value}
	var initial: PackedFloat64Array = derivative.call(state, time_s) if first.is_empty() else first
	if not _finite(initial, state.size()):
		return {ok = false, message = "initial derivative is malformed or nonfinite"}
	var tracked: Callable = func(values: PackedFloat64Array, at: float) -> PackedFloat64Array:
		if not _finite(values, state.size()):
			tracker.ok = false
			tracker.message = "RK event stage state is malformed or nonfinite"
			return _zero(state.size())
		for event: Dictionary in events:
			var sample: Dictionary = _surface_sample(event, values, at,
				remaining_evaluations - int(tracker.evaluations))
			tracker.evaluations = int(tracker.evaluations) + int(sample.get("evaluations", 0))
			if not sample.get("ok", false):
				tracker.ok = false
				tracker.message = str(sample.get("message", "RK event surface failed"))
				return _zero(state.size())
			if sample.enabled:
				var extrema: Dictionary = tracker.extrema[str(event.id)]
				extrema.minimum = minf(float(extrema.minimum), float(sample.value))
				extrema.maximum = maxf(float(extrema.maximum), float(sample.value))
		var raw_rate: Variant = derivative.call(values, at)
		if not raw_rate is PackedFloat64Array or not _finite(raw_rate, state.size()):
			tracker.ok = false
			tracker.message = "event derivative returned a malformed or nonfinite rate"
			return _zero(state.size())
		return raw_rate
	var candidate: PackedFloat64Array = RK.rk4_step_at(state, time_s, dt, tracked, initial)
	if not tracker.ok or not _finite(candidate, state.size()):
		return {ok = false, message = str(tracker.message if not tracker.message.is_empty() else "RK event trial failed"),
			evaluations = int(tracker.evaluations)}
	for event: Dictionary in events:
		var sample: Dictionary = _surface_sample(event, candidate, time_s + dt,
			remaining_evaluations - int(tracker.evaluations))
		tracker.evaluations = int(tracker.evaluations) + int(sample.get("evaluations", 0))
		if not sample.get("ok", false):
			return {ok = false, message = str(sample.get("message", "RK endpoint surface failed")),
				evaluations = int(tracker.evaluations)}
		if sample.enabled:
			var extrema: Dictionary = tracker.extrema[str(event.id)]
			extrema.minimum = minf(float(extrema.minimum), float(sample.value))
			extrema.maximum = maxf(float(extrema.maximum), float(sample.value))
	return {ok = true, state = candidate, extrema = tracker.extrema, evaluations = int(tracker.evaluations)}


static func _locate(start: PackedFloat64Array, time_s: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, event: Dictionary, start_value: float, end_value: float,
		remaining_evaluations: int) -> Dictionary:
	var sense: String = str(event.sense)
	var sign: float = -1.0 if sense == "rising" or (sense == "either" and start_value < 0.0) else 1.0
	var lo: float = 0.0
	var hi: float = dt
	var low_value: float = sign * start_value
	var high_value: float = sign * end_value
	var high_state: PackedFloat64Array
	var bisect: bool = false
	var evaluations: int = 0
	if low_value <= 0.0 or high_value > 0.0:
		return {ok = false, message = "event root is not bracketed"}
	var high_trial: Dictionary = _trial(start, time_s, dt, derivative, first, [event],
		{str(event.id): start_value}, remaining_evaluations)
	evaluations += int(high_trial.get("evaluations", 0))
	if not high_trial.get("ok", false):
		return {ok = false, message = str(high_trial.get("message", "event root endpoint trial failed")),
			evaluations = evaluations}
	high_state = high_trial.state
	var high_sample: Dictionary = _surface_sample(event, high_state, time_s + dt,
		remaining_evaluations - evaluations)
	evaluations += int(high_sample.get("evaluations", 0))
	if not high_sample.get("ok", false):
		return {ok = false, message = str(high_sample.get("message", "event root endpoint surface failed")),
			evaluations = evaluations}
	high_value = sign * float(high_sample.value)
	if high_value > 0.0:
		return {ok = false, message = "event root endpoint is on the original side", evaluations = evaluations}
	for _iteration: int in MAX_ROOT_TRIALS:
		if hi - lo <= TIME_TOL and absf(high_value) <= _event_tolerance(event):
			return {ok = true, state = high_state, offset_s = hi, residual = float(high_sample.value),
				time_error_s = hi - lo, evaluations = evaluations}
		var old_width: float = hi - lo
		var next: float = Bracket.propose(lo, hi, low_value, high_value, TIME_TOL, bisect)
		if not is_finite(next):
			break
		var trial: Dictionary = _trial(start, time_s, next, derivative, first, [event],
			{str(event.id): start_value}, remaining_evaluations - evaluations)
		evaluations += int(trial.get("evaluations", 0))
		if not trial.get("ok", false):
			return {ok = false, message = str(trial.get("message", "event root trial failed")), evaluations = evaluations}
		var sample: Dictionary = _surface_sample(event, trial.state, time_s + next,
			remaining_evaluations - evaluations)
		evaluations += int(sample.get("evaluations", 0))
		if not sample.get("ok", false):
			return {ok = false, message = str(sample.get("message", "event root surface failed")), evaluations = evaluations}
		var residual: float = sign * float(sample.value)
		if residual > 0.0:
			lo = next
			low_value = residual
		else:
			hi = next
			high_value = residual
			high_state = trial.state
			high_sample = sample
		bisect = hi - lo > 0.5 * old_width
	if hi - lo <= TIME_TOL and absf(high_value) <= _event_tolerance(event):
		return {ok = true, state = high_state, offset_s = hi, residual = float(high_sample.value),
			time_error_s = hi - lo, evaluations = evaluations}
	return {ok = false, message = "event failed time and surface residual bounds", evaluations = evaluations}


static func _surface_values(state: PackedFloat64Array, at: float, events: Array,
		remaining_evaluations: int) -> Dictionary:
	if remaining_evaluations <= 0:
		return {ok = false, message = "resource event surface evaluation budget exhausted"}
	var values: Dictionary = {}
	var evaluations: int = 0
	for event: Dictionary in events:
		var sample: Dictionary = _surface_sample(event, state, at, remaining_evaluations - evaluations)
		evaluations += int(sample.get("evaluations", 0))
		if not sample.get("ok", false):
			return {ok = false, message = str(sample.get("message", "event start surface failed")), evaluations = evaluations}
		values[str(event.id)] = float(sample.value) if sample.enabled else 1.0
	return {ok = true, values = values, evaluations = evaluations}


static func _surface_sample(event: Dictionary, state: PackedFloat64Array, at: float,
		remaining_evaluations: int) -> Dictionary:
	if remaining_evaluations <= 0:
		return {ok = false, message = "resource event surface evaluation budget exhausted", evaluations = 0}
	var enabled: bool = true
	if event.has("enabled"):
		var enabled_value: Variant = event.enabled.call(state, at)
		if typeof(enabled_value) != TYPE_BOOL:
			return {ok = false, message = "event enabled callback must return bool", evaluations = 1}
		enabled = bool(enabled_value)
	if not enabled:
		return {ok = true, enabled = false, value = 1.0, evaluations = 1}
	var raw_value: Variant = event.surface.call(state, at)
	if typeof(raw_value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(raw_value)):
		return {ok = false, message = "event surface must return a finite scalar", evaluations = 1}
	return {ok = true, enabled = true, value = float(raw_value), evaluations = 1}


static func _crossed(start_value: float, end_value: float, sense: String) -> bool:
	match sense:
		"falling":
			return start_value > SURFACE_TOL and end_value <= SURFACE_TOL
		"rising":
			return start_value < -SURFACE_TOL and end_value >= -SURFACE_TOL
		"either":
			return absf(start_value) > SURFACE_TOL and start_value * end_value <= 0.0
	return false


static func _crossed_extrema(start_value: float, minimum: float, maximum: float, sense: String) -> bool:
	match sense:
		"falling":
			return start_value > SURFACE_TOL and minimum <= SURFACE_TOL
		"rising":
			return start_value < -SURFACE_TOL and maximum >= -SURFACE_TOL
		"either":
			return absf(start_value) > SURFACE_TOL and minimum <= 0.0 and maximum >= 0.0
	return false


static func _event_tolerance(event: Dictionary) -> float:
	var value: Variant = event.get("surface_tolerance", SURFACE_TOL)
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0 else SURFACE_TOL


static func _event_before(a: Dictionary, b: Dictionary) -> bool:
	var a_priority: int = int(a.get("priority", 100))
	var b_priority: int = int(b.get("priority", 100))
	if a_priority != b_priority:
		return a_priority < b_priority
	return str(a.get("id", "")) < str(b.get("id", ""))


static func _finite(values: PackedFloat64Array, size: int) -> bool:
	if values.size() != size:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _zero(size: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(size)
	return result


static func _failure(message: String) -> Dictionary:
	return {ok = false, message = message}
