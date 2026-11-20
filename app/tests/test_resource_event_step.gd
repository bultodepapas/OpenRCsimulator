extends SceneTree

const ResourceStep := preload("res://physics/resource_event_step.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_ordered_resource_depletion()
	_test_tied_event_priority()
	_test_failure_rolls_back()
	_test_small_boundary_signs()
	_test_invalid_definitions()
	_test_internal_crossing_precedes_endpoint()
	_test_near_tie_order_is_discovery_independent()
	_test_unsampled_crossing_before_anchor()
	print("resource event step: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_ordered_resource_depletion() -> void:
	var initial := _padded([0.8, 0.5, 0.0, 1.3])
	var derivative: Callable = func(state: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		var rate := _zero_state()
		if state[2] == 0.0:
			rate[0] = -1.0
			rate[3] = -1.0
		elif state[2] == 1.0:
			rate[1] = -1.0
			rate[3] = -1.0
		return rate
	var main_event := {
		"id": "main_floor", "type": "main_empty", "sense": "falling", "surface_unit": "kg", "priority": 10,
		"surface": func(state: PackedFloat64Array, _time_s: float) -> float: return state[0],
		"enabled": func(state: PackedFloat64Array, _time_s: float) -> bool: return state[2] == 0.0,
		"transition": func(state: PackedFloat64Array, _time_s: float) -> Dictionary:
			state[0] = 0.0
			state[2] = 1.0
			return {"ok": true, "state": state, "event": {"source": "main"}},
	}
	var line_event := {
		"id": "line_empty", "type": "line_empty", "sense": "falling", "surface_unit": "kg", "priority": 20,
		"surface": func(state: PackedFloat64Array, _time_s: float) -> float: return state[1],
		"enabled": func(state: PackedFloat64Array, _time_s: float) -> bool: return state[2] == 1.0,
		"transition": func(state: PackedFloat64Array, _time_s: float) -> Dictionary:
			state[1] = 0.0
			state[2] = 2.0
			return {"ok": true, "state": state, "event": {"source": "line"}},
	}
	var result: Dictionary = ResourceStep.advance(initial, 0.0, 2.0, derivative,
		_padded([-1.0, 0.0, 0.0, -1.0]), [line_event, main_event])
	_check("main depletes before the primed line", result.get("ok", false), str(result.get("message", "")))
	if not result.get("ok", false):
		return
	var events: Array = result.events
	_check("earliest resource event is first", events.size() == 2 and events[0].id == "main_floor"
		and events[1].id == "line_empty", str(events))
	if events.size() == 2:
		_near("main boundary time", float(events[0].time_s), 0.8)
		_near("line boundary time", float(events[1].time_s), 1.3)
	_check("event surfaces carry explicit mass units", events[0].surface_unit == "kg" and events[1].surface_unit == "kg")
	var final_state: PackedFloat64Array = result.state
	_near("main resource reaches its boundary", final_state[0], 0.0)
	_near("line resource reaches its boundary", final_state[1], 0.0)
	_near("total liquid is conserved across source changes", final_state[3], 0.0)
	_check("depletion ends in the starved mode", final_state[2] == 2.0)
	_check("boundary solve remains within deterministic budget",
		int(result.surface_evaluations) > 0 and int(result.surface_evaluations) < 200000)


func _test_tied_event_priority() -> void:
	var initial := _padded([0.5, 0.0])
	var derivative: Callable = func(state: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		var rate := _zero_state()
		rate[0] = -1.0 if state[1] == 0.0 else 0.0
		return rate
	var low_priority := {
		"id": "z_later", "type": "losing_tie", "sense": "falling", "surface_unit": "1", "priority": 20,
		"surface": func(state: PackedFloat64Array, _time_s: float) -> float: return state[0],
		"enabled": func(state: PackedFloat64Array, _time_s: float) -> bool: return state[1] == 0.0,
		"transition": func(state: PackedFloat64Array, _time_s: float) -> Dictionary:
			state[1] = 2.0
			return {"ok": true, "state": state},
	}
	var high_priority := {
		"id": "a_first", "type": "winning_tie", "sense": "falling", "surface_unit": "1", "priority": 10,
		"surface": func(state: PackedFloat64Array, _time_s: float) -> float: return state[0],
		"enabled": func(state: PackedFloat64Array, _time_s: float) -> bool: return state[1] == 0.0,
		"transition": func(state: PackedFloat64Array, _time_s: float) -> Dictionary:
			state[0] = 0.0
			state[1] = 1.0
			return {"ok": true, "state": state},
	}
	var result: Dictionary = ResourceStep.advance(initial, 0.0, 1.0, derivative,
		_padded([-1.0, 0.0]), [low_priority, high_priority])
	_check("simultaneous boundaries integrate", result.get("ok", false), str(result.get("message", "")))
	if not result.get("ok", false):
		return
	_check("tie priority and stable ordering select one active transition",
		result.events.size() == 1 and result.events[0].id == "a_first")
	_near("tied boundary is located once", float(result.events[0].time_s), 0.5)
	_near("post-transition remainder follows the new mode", result.state[0], 0.0)


func _test_failure_rolls_back() -> void:
	var initial := _padded([0.25])
	var derivative: Callable = func(_state: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		return _padded([-1.0])
	var rejected := {
		"id": "reject", "type": "test", "sense": "falling", "surface_unit": "1",
		"surface": func(state: PackedFloat64Array, _time_s: float) -> float: return state[0],
		"transition": func(state: PackedFloat64Array, _time_s: float) -> Dictionary:
			state[0] = -99.0
			return {"ok": false, "state": state},
	}
	var result: Dictionary = ResourceStep.advance(initial, 0.0, 1.0, derivative,
		_padded([-1.0]), [rejected])
	_check("failed event transition rejects the complete trial", not result.get("ok", true))
	_near("failed transition leaves caller state untouched", initial[0], 0.25)
	_check("failed trial exposes no partially accepted state", not result.has("state"))


func _near(label: String, actual: float, expected: float, tolerance: float = 2.0e-10) -> void:
	_check(label, is_finite(actual) and absf(actual - expected) <= tolerance,
		"got %s expected %s (tol %s)" % [actual, expected, tolerance])


func _test_small_boundary_signs() -> void:
	for sense: String in ["falling", "rising", "either"]:
		var direction: float = 1.0 if sense == "rising" else -1.0
		for exhaust: bool in [false, true]:
			var amount: float = 5e-11 if exhaust else 1.0
			var rate: float = 1e-6 if exhaust else 1.0
			var dt: float = 1e-3 if exhaust else 1.0-5e-11
			var initial := _padded([-direction*amount, 0.0])
			var derivative: Callable = func(state: PackedFloat64Array, _at: float) -> PackedFloat64Array:
				return _padded([direction*rate if state[1] == 0.0 else 0.0, 0.0])
			var event := {id="small", type="boundary", sense=sense, surface_unit="kg",
				enabled=func(state: PackedFloat64Array, _at: float) -> bool: return state[1] == 0.0,
				surface=func(state: PackedFloat64Array, _at: float) -> float: return state[0],
				transition=func(state: PackedFloat64Array, _at: float) -> Dictionary:
					state[0]=0.0
					state[1]=1.0
					return {ok=true, state=state}}
			var result: Dictionary = ResourceStep.advance(initial, 0.0, dt, derivative, PackedFloat64Array(), [event])
			_check(sense+" tiny boundary integrates", result.get("ok", false), str(result.get("message", "")))
			if not result.get("ok", false): continue
			if exhaust:
				_check(sense+" tiny initial distance still triggers the event", result.events.size()==1 and result.state[1]==1.0 and result.state[0]==0.0)
				_near(sense+" tiny boundary time", result.events[0].time_s, amount/rate, 1e-12)
			else:
				_check(sense+" positive endpoint distance is not a zero crossing", result.events.is_empty() and result.state[1]==0.0 and direction*result.state[0]<0.0)
	# Multiplying opposite subnormal signs can underflow to signed zero. Same-side
	# values must not manufacture an `either` crossing through that multiplication.
	_check("subnormal same-side endpoints do not cross", not ResourceStep._crossed(1e-300, 2e-300, "either"))


func _test_invalid_definitions() -> void:
	var event := {id="empty", type="empty", sense="falling", surface_unit="kg",
		surface=func(state: PackedFloat64Array, _at: float) -> float: return state[0],
		transition=func(state: PackedFloat64Array, _at: float) -> Dictionary: return {ok=true, state=state}}
	var derivative: Callable = func(_state: PackedFloat64Array, _at: float) -> PackedFloat64Array: return _padded([-1.0])
	var invalid: Array[Dictionary] = [{surface=Callable()}, {transition=Callable()}, {enabled=Callable()},
		{priority="first"}, {priority=true}, {surface_tolerance=NAN}, {surface_tolerance=-1.0}, {type=" "}]
	for fields: Dictionary in invalid:
		var candidate: Dictionary = event.duplicate()
		candidate.merge(fields, true)
		var state := _padded([1.0])
		var result: Dictionary = ResourceStep.advance(state, 0.0, 0.1, derivative, PackedFloat64Array(), [candidate])
		_check("malformed event refuses cleanly "+str(fields.keys()), not result.get("ok", true) and not result.has("state") and state[0]==1.0)
	for field: String in ["type", "surface_unit", "surface", "transition"]:
		var candidate: Dictionary = event.duplicate()
		candidate.erase(field)
		var result: Dictionary = ResourceStep.advance(_padded([1.0]), 0.0, 0.1, derivative, PackedFloat64Array(), [candidate])
		_check("missing event field refuses cleanly "+field, not result.get("ok", true) and not result.has("state"))
	for output: Variant in [null, [], 1, false, PackedFloat64Array([NAN])]:
		var malformed_rate: Callable = func(_state: PackedFloat64Array, _at: float) -> Variant: return output
		var result: Dictionary = ResourceStep.advance(_padded([1.0]), 0.0, 0.1, malformed_rate, PackedFloat64Array(), [event])
		_check("malformed first derivative refuses cleanly "+str(typeof(output)), not result.get("ok", true) and not result.has("state"))
	for size: int in [0, 1, 12]:
		var truncated := PackedFloat64Array()
		truncated.resize(size)
		var result: Dictionary = ResourceStep.advance(truncated, 0.0, 0.1, derivative, PackedFloat64Array(), [event])
		_check("truncated rigid body refuses before RK "+str(size), not result.get("ok", true) and not result.has("state"))
	var stalled_clock: Dictionary = ResourceStep.advance(_padded([1.0]), 1e20, 0.1, derivative, PackedFloat64Array(), [event])
	_check("a timestep must advance the absolute clock", not stalled_clock.get("ok", true) and not stalled_clock.has("state"))


# Audit 2026-11-19 F01: B crosses at 0.2T between RK samples, A at 0.75T on the endpoint.
func _test_internal_crossing_precedes_endpoint() -> void:
	var tick_dt := 1.0 / 240.0
	for sense: String in ["falling", "rising"]:
		var sign: float = 1.0 if sense == "falling" else -1.0
		for reverse: bool in [false, true]:
			var endpoint := {id = "A_endpoint", type = "boundary", sense = sense, surface_unit = "1",
				enabled = func(values: PackedFloat64Array, _at: float) -> bool: return values[13] == 0.0,
				surface = func(_values: PackedFloat64Array, at: float) -> float: return sign * (0.75 - at / tick_dt),
				transition = func(values: PackedFloat64Array, _at: float) -> Dictionary:
					values[13] = 1.0
					return {ok = true, state = values}}
			var internal := {id = "B_internal", type = "boundary", sense = sense, surface_unit = "1",
				enabled = func(values: PackedFloat64Array, _at: float) -> bool: return values[14] == 0.0,
				surface = func(_values: PackedFloat64Array, at: float) -> float:
					return sign * (at / tick_dt - 0.2) * (at / tick_dt - 0.8),
				transition = func(values: PackedFloat64Array, _at: float) -> Dictionary:
					values[14] = 1.0
					return {ok = true, state = values}}
			var label := "%s %s mixed crossing" % [sense, "reversed" if reverse else "listed"]
			var result: Dictionary = ResourceStep.advance(_flags_state(2), 0.0, tick_dt, _still(),
				PackedFloat64Array(), [internal, endpoint] if reverse else [endpoint, internal])
			_check(label + " integrates", result.get("ok", false), str(result.get("message", "")))
			if not result.get("ok", false):
				continue
			_check(label + " applies the interior crossing first", result.events.size() == 2
				and result.events[0].id == "B_internal" and result.events[1].id == "A_endpoint"
				and result.state[13] == 1.0 and result.state[14] == 1.0, str(result.events))
			_near(label + " interior time", float(result.events[0].time_s), 0.2 * tick_dt, 1e-12)
			_near(label + " endpoint time", float(result.events[1].time_s), 0.75 * tick_dt, 1e-12)


# Audit 2026-11-19 F02: offsets 0.75e-12 s apart chain across TIME_TOL; priorities oppose time.
func _test_near_tie_order_is_discovery_independent() -> void:
	var targets := [1.0e-12, 1.75e-12, 2.5e-12]
	var priorities := [20, 11, 0]
	for order: Array in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		var events: Array = []
		for index: int in order:
			events.append(_time_event(index, float(targets[index]), int(priorities[index])))
		var result: Dictionary = ResourceStep.advance(_flags_state(3), 0.0, 4e-12, _still(),
			PackedFloat64Array(), events)
		var label := "near-tie order %s" % str(order)
		_check(label + " integrates", result.get("ok", false), str(result.get("message", "")))
		if not result.get("ok", false):
			continue
		var ids: Array = result.events.map(func(event: Dictionary) -> String: return str(event.id))
		_check(label + " applies every transition in time order", ids == ["A", "B", "C"]
			and result.state[13] == 1.0 and result.state[14] == 1.0 and result.state[15] == 1.0, str(ids))


# B is below zero only on [0.6, 0.9] of the step, so no RK sample (0, 0.5, 1) sees it; A crosses
# on the endpoint at 0.75. B is past zero at A's root, which must trigger a shorter retry, not a drop.
# (Several roots of one surface between samples remain undetectable by design.)
func _test_unsampled_crossing_before_anchor() -> void:
	for sense: String in ["falling", "rising"]:
		var sign: float = 1.0 if sense == "falling" else -1.0
		var endpoint := {id = "A_endpoint", type = "boundary", sense = sense, surface_unit = "1",
			enabled = func(values: PackedFloat64Array, _at: float) -> bool: return values[13] == 0.0,
			surface = func(_values: PackedFloat64Array, at: float) -> float: return sign * (0.75 - at),
			transition = func(values: PackedFloat64Array, _at: float) -> Dictionary:
				values[13] = 1.0
				return {ok = true, state = values}}
		var hidden := {id = "B_hidden", type = "boundary", sense = sense, surface_unit = "1",
			enabled = func(values: PackedFloat64Array, _at: float) -> bool: return values[14] == 0.0,
			surface = func(_values: PackedFloat64Array, at: float) -> float: return sign * (at - 0.6) * (at - 0.9),
			transition = func(values: PackedFloat64Array, _at: float) -> Dictionary:
				values[14] = 1.0
				return {ok = true, state = values}}
		var result: Dictionary = ResourceStep.advance(_flags_state(2), 0.0, 1.0, _still(), PackedFloat64Array(),
			[endpoint, hidden])
		var label := sense + " unsampled crossing"
		_check(label + " integrates", result.get("ok", false), str(result.get("message", "")))
		if not result.get("ok", false):
			continue
		_check(label + " is applied before the endpoint root", result.events.size() == 2
			and result.events[0].id == "B_hidden" and result.events[1].id == "A_endpoint"
			and result.state[13] == 1.0 and result.state[14] == 1.0, str(result.events))
		_near(label + " time", float(result.events[0].time_s), 0.6, 1e-12)
	# Only a surface enabled at the segment start has a real side of zero to have crossed from.
	var below := {id = "below", type = "boundary", sense = "falling", surface_unit = "1",
		surface = func(_values: PackedFloat64Array, _at: float) -> float: return -1.0,
		transition = func(values: PackedFloat64Array, _at: float) -> Dictionary: return {ok = true, state = values}}
	var anchor := _flags_state(0)
	_check("a surface past zero at the boundary is a missed crossing",
		bool(ResourceStep._crossed_before(anchor, 0.5, [below], {"below": 1.0}, {"below": true}, 100).crossed))
	_check("a surface enabled only inside the segment is not",
		not bool(ResourceStep._crossed_before(anchor, 0.5, [below], {"below": 1.0}, {"below": false}, 100).crossed))


func _time_event(index: int, target: float, priority: int) -> Dictionary:
	return {id = ["A", "B", "C"][index], type = "time_boundary", sense = "falling", surface_unit = "s",
		priority = priority, surface_tolerance = 1e-22,
		enabled = func(state: PackedFloat64Array, _at: float) -> bool: return state[13 + index] == 0.0,
		surface = func(_state: PackedFloat64Array, at: float) -> float: return target - at,
		transition = func(state: PackedFloat64Array, _at: float) -> Dictionary:
			state[13 + index] = 1.0
			return {ok = true, state = state}}


func _flags_state(flags: int) -> PackedFloat64Array:
	var state := _zero_state()
	state.resize(13 + flags)
	return state


func _still() -> Callable:
	return func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		var rate := PackedFloat64Array()
		rate.resize(values.size())
		return rate


func _padded(values: Array) -> PackedFloat64Array:
	var result := _zero_state()
	for index: int in values.size():
		result[index] = float(values[index])
	return result


func _zero_state() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(13)
	result[6] = 1.0
	return result


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1
