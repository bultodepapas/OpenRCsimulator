extends SceneTree

const ResourceStep := preload("res://physics/resource_event_step.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_ordered_resource_depletion()
	_test_tied_event_priority()
	_test_failure_rolls_back()
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
