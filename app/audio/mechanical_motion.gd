extends RefCounted
class_name MechanicalMotion

## Small observer for accepted actuator positions. The caller owns the state and
## supplies one coherent post-tick snapshot; targets never create movement.
const DEFAULT_TICK_RATE_HZ: float = 240.0
const SERVO_SPEED_FLOOR_DEG_S: float = 0.2
const EXTENSION_EPSILON: float = 0.000001
const MAX_CHANNELS: int = 6


## Returns a new observer state, current motion levels, and transition events.
## The first sample, pause, and tick rewind only prime the observer.
static func observe(previous: Dictionary, snapshot: Dictionary) -> Dictionary:
	var tick_value: Variant = snapshot.get("tick", null)
	if not _number_is_finite(tick_value) or float(tick_value) < 0.0:
		return {state = previous, channels = [], gear = {}, events = [], valid = false,
			primed = false, tick_advanced = false}
	var tick: int = int(tick_value)
	var rate: float = _tick_rate(snapshot.get("tick_rate", DEFAULT_TICK_RATE_HZ))
	var paused: bool = bool(snapshot.get("paused", false))
	var channel_rows: Array[Dictionary] = _read_channels(snapshot.get("channels", []))
	var gear_row: Dictionary = _read_gear(snapshot.get("gear", {}))
	var old_tick: int = int(previous.get("tick", -1))
	if previous.is_empty() or old_tick < 0 or tick < old_tick or paused:
		var primed_state: Dictionary = _prime_state(tick, channel_rows, gear_row)
		return {state = primed_state, channels = primed_state.channels_motion,
			gear = primed_state.gear_motion, events = [], valid = true,
			primed = true, tick_advanced = false}
	var tick_delta: int = tick - old_tick
	if tick_delta == 0:
		var refreshed: Dictionary = _refresh_state(previous, channel_rows, gear_row)
		return {state = refreshed, channels = refreshed.channels_motion,
			gear = refreshed.gear_motion, events = [], valid = true,
			primed = false, tick_advanced = false}

	var old_channels: Dictionary = previous.get("channels", {})
	var next_channels: Dictionary = {}
	var events: Array[Dictionary] = []
	# Normalize once, then complete each new row in place. State and output share
	# these read-only rows; no dictionary from the prior snapshot is modified.
	var angular_floor: float = SERVO_SPEED_FLOOR_DEG_S * float(tick_delta) / rate
	for row: Dictionary in channel_rows:
		var identity: String = str(row.id)
		var old: Dictionary = old_channels.get(identity, {})
		var event_kind: String = ""
		if old.is_empty():
			_set_stationary(row)
		else:
			# A rate floor is independent of render sampling frequency. A fixed angular
			# epsilon per frame made the same slow correction disappear at high FPS.
			_measure_row(row, float(old.value), tick_delta, rate, angular_floor)
			event_kind = _transition_kind(old, row, false)
		if not event_kind.is_empty():
			events.append(_event("servo", event_kind, identity, row.position, row.position_valid,
				float(row.speed_per_s), int(row.direction)))
		next_channels[identity] = row

	var old_gear: Dictionary = previous.get("gear", {})
	if not gear_row.is_empty():
		var gear_event: String = ""
		if old_gear.is_empty():
			_set_stationary(gear_row)
		else:
			_measure_row(gear_row, float(old_gear.value),
				tick_delta, rate, EXTENSION_EPSILON)
			var endpoint_locked: bool = is_locked_endpoint(float(gear_row.value), bool(gear_row.target_down))
			gear_event = _transition_kind(old_gear, gear_row, endpoint_locked)
		if not gear_event.is_empty():
			events.append(_event("gear", gear_event, "gear", gear_row.position,
				bool(gear_row.position_valid), float(gear_row.speed_per_s),
				int(gear_row.direction)))

	var state: Dictionary = {tick = tick, channels = next_channels, gear = gear_row,
		channels_motion = channel_rows, gear_motion = gear_row}
	return {state = state, channels = channel_rows, gear = gear_row, events = events,
		valid = true, primed = false, tick_advanced = true}


## Delta/rate are derived only from two accepted endpoint values and elapsed ticks.
static func measure_delta(previous_value: float, current_value: float, tick_delta: int,
		tick_rate_hz: float, epsilon: float = 0.0) -> Dictionary:
	if not is_finite(previous_value) or not is_finite(current_value):
		return {moving = false, delta = 0.0, speed_per_s = 0.0, direction = 0, valid = false}
	var delta_value: float = current_value - previous_value
	var threshold: float = maxf(0.0, epsilon)
	var moving: bool = tick_delta > 0 and absf(delta_value) > threshold
	var rate: float = _tick_rate(tick_rate_hz)
	var speed: float = absf(delta_value) * rate / float(tick_delta) if tick_delta > 0 else 0.0
	return {moving = moving, delta = delta_value, speed_per_s = speed,
		direction = int(signf(delta_value)) if moving else 0, valid = true}


## A change in target is not an event. Reversal/start/stop follow accepted motion;
## the caller declares a lock only for an observed arrival at a qualified endpoint.
static func transition_for(previous_state: Dictionary, measured: Dictionary,
		endpoint_locked: bool = false) -> Dictionary:
	return {event = _transition_kind(previous_state, measured, endpoint_locked)}


static func _transition_kind(previous_state: Dictionary, measured: Dictionary,
		endpoint_locked: bool) -> String:
	var was_moving: bool = bool(previous_state.get("moving", false))
	var moving: bool = bool(measured.get("moving", false))
	var previous_direction: int = int(previous_state.get("direction", 0))
	var direction: int = int(measured.get("direction", 0))
	if moving:
		if was_moving and direction != previous_direction:
			return "reverse"
		if not was_moving:
			return "start"
		return ""
	if was_moving:
		return "lock" if endpoint_locked else "stop"
	return ""


static func is_locked_endpoint(extension: float, target_down: bool) -> bool:
	if not is_finite(extension):
		return false
	return absf(extension - 1.0) <= EXTENSION_EPSILON if target_down \
		else absf(extension) <= EXTENSION_EPSILON


static func finite_vector(value: Variant) -> bool:
	return value is Vector3 and value.is_finite()


static func _prime_state(tick: int, channel_rows: Array[Dictionary], gear_row: Dictionary) -> Dictionary:
	var channels: Dictionary = {}
	for row: Dictionary in channel_rows:
		_set_stationary(row)
		channels[str(row.id)] = row
	if not gear_row.is_empty():
		_set_stationary(gear_row)
	return {tick = tick, channels = channels, gear = gear_row,
		channels_motion = channel_rows, gear_motion = gear_row}


static func _refresh_state(previous: Dictionary, channel_rows: Array[Dictionary], gear_row: Dictionary) -> Dictionary:
	var old_channels: Dictionary = previous.get("channels", {})
	var next_channels: Dictionary = {}
	for row: Dictionary in channel_rows:
		var old: Dictionary = old_channels.get(str(row.id), {})
		_refresh_motion(row, old)
		next_channels[str(row.id)] = row
	if not gear_row.is_empty():
		_refresh_motion(gear_row, previous.get("gear", {}))
	return {tick = previous.tick, channels = next_channels, gear = gear_row,
		channels_motion = channel_rows, gear_motion = gear_row}


static func _refresh_motion(row: Dictionary, old: Dictionary) -> void:
	if old.is_empty():
		_set_stationary(row)
		return
	# Camera/source transforms can change between accepted ticks. Keep the last
	# accepted travel while refreshing spatial data and the gear's target/status.
	row["value"] = old.value
	row["delta"] = old.delta
	row["speed_per_s"] = old.speed_per_s
	row["moving"] = old.moving
	row["direction"] = old.direction
	if old.has("load"):
		row["load"] = old.load
	else:
		row.erase("load")


static func _read_channels(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not value is Array:
		return rows
	var seen: Dictionary = {}
	for item: Variant in value:
		if rows.size() >= MAX_CHANNELS:
			break
		if not item is Dictionary:
			continue
		var identity: String = str(item.get("id", "")).strip_edges()
		var angle_value: Variant = item.get("angle_deg", item.get("value", null))
		if identity.is_empty() or seen.has(identity) or not _number_is_finite(angle_value):
			continue
		seen[identity] = true
		var position: Variant = item.get("position", Vector3.ZERO)
		var position_valid: bool = finite_vector(position)
		var row: Dictionary = {id = identity, value = float(angle_value),
			position = position if position_valid else Vector3.ZERO, position_valid = position_valid}
		if _number_is_finite(item.get("load", null)):
			row["load"] = clampf(float(item.load), 0.0, 1.0)
		rows.append(row)
	return rows


static func _read_gear(value: Variant) -> Dictionary:
	if not value is Dictionary or not bool(value.get("available", true)):
		return {}
	var extension_value: Variant = value.get("extension", null)
	if not _number_is_finite(extension_value):
		return {}
	var target_value: Variant = value.get("target_down", value.get("target", null))
	var target_down: bool = false
	if typeof(target_value) == TYPE_BOOL:
		target_down = bool(target_value)
	elif _number_is_finite(target_value):
		target_down = float(target_value) >= 0.5
	elif target_value is String:
		target_down = str(target_value).to_lower() in ["down", "extend", "extending"]
	var position_value: Variant = value.get("position", Vector3.ZERO)
	var position_valid: bool = finite_vector(position_value)
	return {id = "gear", value = clampf(float(extension_value), 0.0, 1.0), target_down = target_down,
		position = position_value if position_valid else Vector3.ZERO, position_valid = position_valid,
		status = str(value.get("status", ""))}


static func _measure_row(row: Dictionary, previous_value: float, tick_delta: int,
		tick_rate_hz: float, epsilon: float) -> void:
	var travel: float = float(row.value) - previous_value
	var moving: bool = absf(travel) > epsilon
	row["delta"] = travel
	row["speed_per_s"] = absf(travel) * tick_rate_hz / float(tick_delta)
	row["direction"] = int(signf(travel)) if moving else 0
	row["moving"] = moving


static func _event(system: String, event_kind: String, identity: String, position: Vector3,
		position_valid: bool, speed: float, direction: int) -> Dictionary:
	return {system = system, event = event_kind, id = identity, position = position,
		position_valid = position_valid, speed_per_s = speed, direction = direction}


static func _set_stationary(row: Dictionary) -> void:
	row["moving"] = false
	row["delta"] = 0.0
	row["speed_per_s"] = 0.0
	row["direction"] = 0


static func _tick_rate(value: Variant) -> float:
	return maxf(1.0, float(value)) if _number_is_finite(value) and float(value) > 0.0 else DEFAULT_TICK_RATE_HZ


static func _number_is_finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
