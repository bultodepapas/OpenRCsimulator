extends SceneTree

const ResourceStep = preload("res://physics/resource_event_step.gd")
const FrameSamples = preload("res://render/frame_samples.gd")

func _initialize() -> void:
	var output := {engine = Engine.get_version_info().string, cases = []}
	var a := PackedFloat64Array([1.0, 2.0])
	var holder := {values = a}
	var b: PackedFloat64Array = holder.values
	b.append(3.0)
	output.packed_alias = {original = Array(a), stored = Array(holder.values), local = Array(b)}
	var comparator: Callable = func(left: Dictionary, right: Dictionary) -> bool:
		if absf(float(left.offset_s) - float(right.offset_s)) <= ResourceStep.TIME_TOL:
			return ResourceStep._event_before(left.event, right.event)
		return float(left.offset_s) < float(right.offset_s)
	var roots := [
		{offset_s = 0.0, event = {id = "A", priority = 20}},
		{offset_s = 0.75e-12, event = {id = "B", priority = 11}},
		{offset_s = 1.5e-12, event = {id = "C", priority = 0}},
	]
	output.comparator_cycle = {b_before_a = comparator.call(roots[1], roots[0]),
		c_before_b = comparator.call(roots[2], roots[1]), a_before_c = comparator.call(roots[0], roots[2])}
	for order: Array in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		var sorted: Array = []
		var events: Array = []
		for index: int in order:
			sorted.append(roots[index])
			events.append(_event(index, (1.0 + float(index) * 0.75) * 1e-12))
		sorted.sort_custom(comparator)
		var state := PackedFloat64Array()
		state.resize(16)
		state[6] = 1.0
		var derivative: Callable = func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
			var rate := PackedFloat64Array()
			rate.resize(values.size())
			return rate
		var result: Dictionary = ResourceStep.advance(state, 0.0, 4e-12, derivative, PackedFloat64Array(), events)
		var case := {input = order, sorted = sorted.map(func(x: Dictionary) -> String: return x.event.id),
			ok = result.get("ok", false), message = result.get("message", ""), events = result.get("events", [])}
		if result.get("ok", false):
			case.event_flags = [result.state[13], result.state[14], result.state[15]]
		output.cases.append(case)
	output.internal_crossing = []
	for reverse: bool in [false, true]:
		var state := PackedFloat64Array()
		state.resize(15)
		state[6] = 1.0
		var tick_dt := 1.0 / 240.0
		var derivative: Callable = func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
			var rate := PackedFloat64Array()
			rate.resize(values.size())
			return rate
		var endpoint := {id = "A_endpoint", type = "boundary", sense = "falling", surface_unit = "1",
			enabled = func(values: PackedFloat64Array, _at: float) -> bool: return values[13] == 0.0,
			surface = func(_values: PackedFloat64Array, at: float) -> float: return 0.75 - at / tick_dt,
			transition = func(values: PackedFloat64Array, _at: float) -> Dictionary:
				values[13] = 1.0
				return {ok = true, state = values}}
		var internal := {id = "B_internal", type = "boundary", sense = "falling", surface_unit = "1",
			enabled = func(values: PackedFloat64Array, _at: float) -> bool: return values[14] == 0.0,
			surface = func(_values: PackedFloat64Array, at: float) -> float: return (at / tick_dt - 0.2) * (at / tick_dt - 0.8),
			transition = func(values: PackedFloat64Array, _at: float) -> Dictionary:
				values[14] = 1.0
				return {ok = true, state = values}}
		var events: Array = [internal, endpoint] if reverse else [endpoint, internal]
		var result: Dictionary = ResourceStep.advance(state, 0.0, tick_dt, derivative, PackedFloat64Array(), events)
		output.internal_crossing.append({reverse = reverse, ok = result.get("ok", false),
			events = result.get("events", []), expected_ids = ["B_internal", "A_endpoint"],
			message = result.get("message", ""), flags = [result.state[13], result.state[14]] if result.get("ok", false) else []})
	print("AUDIT_JSON " + JSON.stringify(output, "", true, true))
	print("Audit probe complete")
	quit(0)

func _event(index: int, target: float) -> Dictionary:
	return {id = ["A", "B", "C"][index], type = "time_boundary", sense = "falling", surface_unit = "s",
		priority = [20, 11, 0][index], surface_tolerance = 1e-22,
		enabled = func(state: PackedFloat64Array, _at: float) -> bool: return state[13 + index] == 0.0,
		surface = func(_state: PackedFloat64Array, at: float) -> float: return target - at,
		transition = func(state: PackedFloat64Array, _at: float) -> Dictionary:
			state[13 + index] = 1.0
			return {ok = true, state = state}}
