extends RefCounted

## Pure 240 Hz scheduler for presentation-only smoke emitters.
## A failed interval latches a fault until reset; event overflow is never truncated.

const TICKS_PER_SECOND := 240
const MAX_INTERVAL_TICKS := 24
const MAX_EVENTS_PER_EMITTER := 32
const MAX_INPUT_CHANGES := 25

var entries: Array[Dictionary] = []
var _runtime: Dictionary = {}
var _fault := ""
var _last_tick := -1


func configure(profile_entries: Array[Dictionary], slot_info: Dictionary) -> bool:
	entries.clear()
	_runtime.clear()
	_fault = ""
	_last_tick = -1
	for entry: Dictionary in profile_entries:
		var slot := str(entry.get("slot", ""))
		if slot.is_empty() or not slot_info.has(slot):
			_fault = "unknown slot"
			return false
		var registration: Variant = slot_info[slot]
		var kind := str(registration.get("kind", "")) if registration is Dictionary else str(registration)
		if kind != "show" and kind != "source":
			_fault = "invalid slot kind"
			return false
		var runtime_entry := entry.duplicate(true)
		runtime_entry["kind"] = kind
		if kind == "source":
			if registration is not Dictionary or str(registration.get("source_kind", "")).is_empty():
				_fault = "source slot has no accepted source kind"
				return false
			runtime_entry["source_kind"] = str(registration.source_kind)
		entries.append(runtime_entry)
		_runtime[slot] = {
			"signal_level": 0.0,
			"source_kind": "",
			"source_running": false,
			"burst_until": -1,
			"burst_level": 0.0,
			"activation_tick": -1,
			"output_level": 0.0,
			"output_color": _base_color(runtime_entry),
		}
	return true


func reset() -> void:
	_fault = ""
	_last_tick = -1
	for entry: Dictionary in entries:
		var slot := str(entry.slot)
		_runtime[slot] = {
			"signal_level": 0.0,
			"source_kind": "",
			"source_running": false,
			"burst_until": -1,
			"burst_level": 0.0,
			"activation_tick": -1,
			"output_level": 0.0,
			"output_color": _base_color(entry),
		}


func rebase(tick: int) -> void:
	if tick >= 0:
		_last_tick = tick


func fault_reason() -> String:
	return _fault


func advance(start_tick: int, end_tick: int, request: Variant, source_sample: Variant) -> Dictionary:
	if not _fault.is_empty():
		return _failure(_fault)
	if start_tick < 0 or end_tick < start_tick or end_tick - start_tick > MAX_INTERVAL_TICKS:
		return _latch_failure("interval outside 0..24 tick bounds")
	if _last_tick >= 0 and start_tick != _last_tick:
		return _latch_failure("non-contiguous tick interval; reset required")
	if end_tick == start_tick:
		_last_tick = end_tick
		return {"ok": true, "events": {}, "event_log": [], "interval_ticks": 0}

	var next_runtime: Dictionary = _runtime.duplicate(true)
	var all_events: Dictionary = {}
	var event_log: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var slot := str(entry.slot)
		var current: Dictionary = next_runtime[slot]
		var changes_result := _input_changes(entry, start_tick, end_tick, request, source_sample, current)
		if not bool(changes_result.ok):
			return _latch_failure(str(changes_result.error))
		var changes: Array = changes_result.changes
		if changes_result.has("initial"):
			var initial: Dictionary = changes_result.initial
			current.signal_level = float(initial.level)
			if str(entry.kind) == "source":
				current.source_kind = str(initial.kind)
				current.source_running = bool(initial.running)
		if changes.size() > MAX_INPUT_CHANGES:
			return _latch_failure("more than 25 input changes in one interval")
		var per_slot: Array[Dictionary] = []
		var input_index := 0
		for tick in range(start_tick, end_tick + 1):
			while input_index < changes.size() and int(changes[input_index].tick) == tick:
				var change: Dictionary = changes[input_index]
				current.signal_level = float(change.level)
				if str(entry.kind) == "source":
					current.source_kind = str(change.kind)
					current.source_running = bool(change.running)
				input_index += 1
			var output := _evaluate(entry, current, tick)
			var color: Color = output.color
			var level := float(output.level)
			if tick == start_tick or not _same_output(current.output_level, current.output_color, level, color):
				var item := {
					"tick": tick,
					"offset_s": float(tick - start_tick) / TICKS_PER_SECOND,
					"level": level,
					"color": color,
				}
				per_slot.append(item)
				if tick > start_tick:
					event_log.append({"slot": slot, "tick": tick, "level": level, "color": color})
			current.output_level = level
			current.output_color = color
		if input_index != changes.size():
			return _latch_failure("input change escaped the interval")
		if per_slot.size() > MAX_EVENTS_PER_EMITTER:
			return _latch_failure("per-birth event capacity exceeded for " + slot)
		all_events[slot] = per_slot
		next_runtime[slot] = current

	_runtime = next_runtime
	_last_tick = end_tick
	return {"ok": true, "events": all_events, "event_log": event_log, "interval_ticks": end_tick - start_tick}


func _input_changes(entry: Dictionary, start_tick: int, end_tick: int, request: Variant,
		source_sample: Variant, current: Dictionary) -> Dictionary:
	var raw: Variant = source_sample if str(entry.kind) == "source" else _request_for_slot(request, str(entry.slot))
	if raw is Dictionary and raw.has("changes"):
		var changes_raw: Variant = raw.changes
		if not changes_raw is Array:
			return {"ok": false, "error": "changes must be an array"}
		if changes_raw.size() > MAX_INPUT_CHANGES:
			return {"ok": false, "error": "more than 25 input changes in one interval"}
		var output: Array[Dictionary] = []
		var initial := {"level": float(current.signal_level), "kind": str(current.source_kind),
			"running": bool(current.source_running)}
		if raw.has("level"):
			var initial_level := _finite_level(raw.level)
			if initial_level < 0.0:
				return {"ok": false, "error": "snapshot level must be finite and in 0..1"}
			initial.level = initial_level
		if str(entry.kind) == "source" and raw.has("kind"):
			if typeof(raw.get("running")) != TYPE_BOOL:
				return {"ok": false, "error": "source sample requires running state"}
			initial.kind = str(raw.kind)
			initial.running = bool(raw.running)
		var last_tick := start_tick - 1
		for raw_change: Variant in changes_raw:
			if not raw_change is Dictionary:
				return {"ok": false, "error": "change must be a dictionary"}
			var change: Dictionary = raw_change
			if typeof(change.get("tick")) != TYPE_INT or int(change.tick) < start_tick or int(change.tick) > end_tick:
				return {"ok": false, "error": "change tick outside current interval"}
			if int(change.tick) <= last_tick:
				return {"ok": false, "error": "change ticks must be strictly increasing"}
			last_tick = int(change.tick)
			var level := _finite_level(change.get("level", NAN))
			if level < 0.0:
				return {"ok": false, "error": "change level must be finite and in 0..1"}
			var normalized := {"tick": int(change.tick), "level": level, "kind": "", "running": false}
			if str(entry.kind) == "source":
				if not change.has("kind") or typeof(change.get("running")) != TYPE_BOOL:
					return {"ok": false, "error": "source changes require kind and running"}
				normalized.kind = str(change.kind)
				normalized.running = bool(change.running)
			output.append(normalized)
		return {"ok": true, "changes": output, "initial": initial}
	if raw is Dictionary:
		var level := _finite_level(raw.get("level", NAN))
		if level < 0.0:
			return {"ok": false, "error": "snapshot level must be finite and in 0..1"}
		var change := {"tick": start_tick, "level": level, "kind": "", "running": false}
		if str(entry.kind) == "source":
			if typeof(raw.get("running")) != TYPE_BOOL or not raw.has("kind"):
				return {"ok": false, "error": "source sample requires kind and running"}
			change.kind = str(raw.kind)
			change.running = bool(raw.running)
		return {"ok": true, "changes": [change]}
	if str(entry.kind) == "source":
		return {"ok": false, "error": "source sample must include accepted kind and running state"}
	var scalar_level := _finite_level(raw)
	if scalar_level < 0.0:
		return {"ok": false, "error": "request must be finite and in 0..1"}
	return {"ok": true, "changes": [{"tick": start_tick, "level": scalar_level, "kind": "", "running": false}]}


func _evaluate(entry: Dictionary, state: Dictionary, tick: int) -> Dictionary:
	var signal_level := float(state.signal_level)
	if str(entry.kind) == "source":
		var expected_kind := str(entry.get("source_kind", ""))
		if not bool(state.source_running) or str(state.source_kind) != expected_kind:
			signal_level = 0.0
	if not bool(entry.get("enabled", false)):
		signal_level = 0.0
	var previous := float(state._previous_signal_level) if state.has("_previous_signal_level") else 0.0
	if previous <= 0.0 and signal_level > 0.0:
		state.activation_tick = tick
		if str(entry.mode) == "burst":
			state.burst_until = tick + _seconds_to_ticks(float(entry.burst_s))
			state.burst_level = signal_level
	if signal_level <= 0.0 and str(entry.kind) == "source":
		state.burst_until = -1
	var mode := str(entry.mode)
	var level := 0.0
	match mode:
		"hold":
			level = signal_level
		"burst":
			level = float(state.burst_level) if tick < int(state.burst_until) else 0.0
		"pulse":
			if signal_level > 0.0 and int(state.activation_tick) >= 0:
				var period_ticks := _seconds_to_ticks(float(entry.pulse_period_s))
				var duty_ticks := clampi(roundi(period_ticks * float(entry.pulse_duty)), 1, period_ticks)
				var phase := posmod(tick - int(state.activation_tick), period_ticks)
				if phase < duty_ticks:
					level = signal_level
	state._previous_signal_level = signal_level
	var color := _color_at(entry, tick, int(state.activation_tick))
	return {"level": level, "color": color}


func _color_at(entry: Dictionary, tick: int, activation_tick: int) -> Color:
	var palette: Array = entry.get("palette", [])
	if palette.is_empty():
		return _parse_color(str(entry.color))
	if palette.size() == 1 or float(entry.step_s) <= 0.0 or activation_tick < 0:
		return _parse_color(str(palette[0]))
	var step_ticks := _seconds_to_ticks(float(entry.step_s))
	var index := posmod(floori(float(maxi(0, tick - activation_tick)) / step_ticks), palette.size())
	return _parse_color(str(palette[index]))


func _request_for_slot(request: Variant, slot: String) -> Variant:
	if request is Dictionary and request.has(slot):
		return request[slot]
	return request


func _same_output(a_level: float, a_color: Color, b_level: float, b_color: Color) -> bool:
	if a_level <= 0.0 and b_level <= 0.0:
		return true
	return is_equal_approx(a_level, b_level) and a_color.is_equal_approx(b_color)


func _finite_level(value: Variant) -> float:
	if typeof(value) == TYPE_BOOL:
		return 1.0 if bool(value) else 0.0
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number > 1.0:
		return -1.0
	return number


func _base_color(entry: Dictionary) -> Color:
	var palette: Array = entry.get("palette", [])
	return _parse_color(str(palette[0] if not palette.is_empty() else entry.get("color", "#FFFFFFFF")))


func _parse_color(text: String) -> Color:
	return Color.from_string(text, Color.WHITE)


func _seconds_to_ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * TICKS_PER_SECOND))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "events": {}, "event_log": [], "interval_ticks": 0}


func _latch_failure(message: String) -> Dictionary:
	_fault = message
	return _failure(message)
