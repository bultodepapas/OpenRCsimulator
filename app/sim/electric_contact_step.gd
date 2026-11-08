## Compose the existing finite-battery/rotor step with an explicitly requested
## contact subdivision. The owning session applies sampled supervision once at
## the accepted outer endpoint; this helper never publishes partial results.
extends RefCounted

const BatteryStep := preload("res://physics/electric_battery_step.gd")
const MAX_PIECES := 16
const MAX_EVENTS := 128
const TIME_TOL := 1e-12
# Matches Simulation.EVENT_TIME_SLACK_S for absolute-clock event windows.
const EVENT_WINDOW_SLACK_S := 1e-9
const FLOAT64_EPSILON := 2.220446049250313e-16


static func advance(combined: PackedFloat64Array, at: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, rpm_index: int, charge_index: int, project: Callable, pieces: int) -> Dictionary:
	if pieces < 1 or pieces > MAX_PIECES or not is_finite(at) or not is_finite(dt) or dt <= 0.0:
		return {ok = false, message = "invalid contact subdivision"}
	# Identical one-piece route, including event payload and evaluation order.
	if pieces == 1:
		return BatteryStep.advance(combined, at, dt, derivative, first, rpm_index, charge_index, project)
	var state: PackedFloat64Array = combined.duplicate()
	var events: Array[Dictionary] = []
	# Events on the same local boundary can differ by an absolute clock ULP.
	# Keep this separate from BatteryStep's 1e-12 local root tolerance.
	var clock_tolerance := minf(EVENT_WINDOW_SLACK_S, maxf(TIME_TOL,
		2.0 * FLOAT64_EPSILON * maxf(absf(at), absf(at + dt))))
	for i: int in pieces:
		var begin := dt * float(i) / float(pieces)
		var end := dt * float(i + 1) / float(pieces)
		var result: Dictionary = BatteryStep.advance(state, at + begin, end - begin, derivative,
			first if i == 0 else PackedFloat64Array(), rpm_index, charge_index, project)
		if not result.get("ok", false) or not result.get("state") is PackedFloat64Array \
				or not result.get("events") is Array:
			return {ok = false, message = "finite-battery contact piece failed"}
		var piece_event_index := 0
		for event: Variant in result.events:
			if not event is Dictionary or typeof(event.get("type")) != TYPE_STRING \
					or typeof(event.get("time_s")) not in [TYPE_FLOAT, TYPE_INT] \
					or not is_finite(float(event.time_s)) or float(event.time_s) < at + begin - EVENT_WINDOW_SLACK_S \
					or float(event.time_s) > at + end + EVENT_WINDOW_SLACK_S or events.size() >= MAX_EVENTS:
				return {ok = false, message = "malformed or out-of-range contact piece event"}
			if not _append_ordered(events, event, piece_event_index, clock_tolerance):
				return {ok = false, message = "contact piece events out of order"}
			piece_event_index += 1
		state = result.state
	return {ok = true, state = state, events = events}


static func _append_ordered(events: Array[Dictionary], event: Dictionary, piece_index: int,
		clock_tolerance: float) -> bool:
	var copy: Dictionary = event.duplicate(true)
	if not events.is_empty():
		var previous: Dictionary = events[-1]
		var difference := float(copy.time_s) - float(previous.time_s)
		if difference < 0.0 and (piece_index > 0 or difference < -clock_tolerance):
			return false
		# Preserve each BatteryStep result's order and exact timestamps.
		# Only repair a rounding inversion at the join between pieces.
		if piece_index == 0 and difference < 0.0:
			copy.time_s = previous.time_s
			difference = 0.0
		if piece_index == 0 and difference == 0.0 and previous.type == "battery_exhausted" and copy.type == "rotor_stop":
			events.insert(events.size() - 1, copy)
			return true
	events.append(copy)
	return true
