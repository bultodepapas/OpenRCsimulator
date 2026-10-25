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
	var channel_motion: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	for row: Dictionary in channel_rows:
		var identity: String = str(row.id)
		var old: Dictionary = old_channels.get(identity, {})
		var measured: Dictionary
		var event_kind: String = ""
		if old.is_empty():
			measured = _stationary(float(row.value))
		else:
			# A rate floor is independent of render sampling frequency. A fixed angular
			# epsilon per frame made the same slow correction disappear at high FPS.
			var angular_floor: float = SERVO_SPEED_FLOOR_DEG_S * float(tick_delta) / rate
			measured = measure_delta(float(old.value), float(row.value), tick_delta, rate, angular_floor)
			var transition: Dictionary = transition_for(old, measured, false)
			event_kind = str(transition.get("event", ""))
		if not event_kind.is_empty():
			events.append(_event("servo", event_kind, identity, row.position, row.position_valid,
				float(measured.speed_per_s), int(measured.direction)))
		var motion: Dictionary = _motion_record(row, measured)
		channel_motion.append(motion)
		next_channels[identity] = {value = float(row.value), moving = bool(measured.moving),
			direction = int(measured.direction), position = row.position,
			position_valid = bool(row.position_valid)}

	var old_gear: Dictionary = previous.get("gear", {})
	var gear_motion: Dictionary = {}
	var next_gear: Dictionary = {}
	if not gear_row.is_empty():
		var measured_gear: Dictionary
		var gear_event: String = ""
		if old_gear.is_empty():
			measured_gear = _stationary(float(gear_row.value))
		else:
			measured_gear = measure_delta(float(old_gear.value), float(gear_row.value),
				tick_delta, rate, EXTENSION_EPSILON)
			var endpoint_locked: bool = is_locked_endpoint(float(gear_row.value), bool(gear_row.target_down))
			var transition: Dictionary = transition_for(old_gear, measured_gear, endpoint_locked)
			gear_event = str(transition.get("event", ""))
		if not gear_event.is_empty():
			events.append(_event("gear", gear_event, "gear", gear_row.position,
				bool(gear_row.position_valid), float(measured_gear.speed_per_s),
				int(measured_gear.direction)))
		gear_motion = _motion_record(gear_row, measured_gear)
		gear_motion["target_down"] = bool(gear_row.target_down)
		gear_motion["status"] = str(gear_row.status)
		next_gear = {value = float(gear_row.value), moving = bool(measured_gear.moving),
			direction = int(measured_gear.direction), target_down = bool(gear_row.target_down),
			position = gear_row.position, position_valid = bool(gear_row.position_valid),
			status = str(gear_row.status)}

	var state: Dictionary = {tick = tick, channels = next_channels, gear = next_gear,
		channels_motion = channel_motion, gear_motion = gear_motion}
	return {state = state, channels = channel_motion, gear = gear_motion, events = events,
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
	var was_moving: bool = bool(previous_state.get("moving", false))
	var moving: bool = bool(measured.get("moving", false))
	var previous_direction: int = int(previous_state.get("direction", 0))
	var direction: int = int(measured.get("direction", 0))
	if moving:
		if was_moving and direction != previous_direction:
			return {event = "reverse"}
		if not was_moving:
			return {event = "start"}
		return {event = ""}
	if was_moving:
		return {event = "lock" if endpoint_locked else "stop"}
	return {event = ""}


static func is_locked_endpoint(extension: float, target_down: bool) -> bool:
	if not is_finite(extension):
		return false
	return absf(extension - 1.0) <= EXTENSION_EPSILON if target_down \
		else absf(extension) <= EXTENSION_EPSILON


static func finite_vector(value: Variant) -> bool:
	return value is Vector3 and value.is_finite()


static func _prime_state(tick: int, channel_rows: Array[Dictionary], gear_row: Dictionary) -> Dictionary:
	var channels: Dictionary = {}
	var motion: Array[Dictionary] = []
	for row: Dictionary in channel_rows:
		var stationary: Dictionary = _stationary(float(row.value))
		channels[str(row.id)] = {value = float(row.value), moving = false, direction = 0,
			position = row.position, position_valid = bool(row.position_valid)}
		motion.append(_motion_record(row, stationary))
	var gear_state: Dictionary = {}
	var gear_motion: Dictionary = {}
	if not gear_row.is_empty():
		gear_state = {value = float(gear_row.value), moving = false, direction = 0,
			target_down = bool(gear_row.target_down), position = gear_row.position,
			position_valid = bool(gear_row.position_valid), status = str(gear_row.status)}
		gear_motion = _motion_record(gear_row, _stationary(float(gear_row.value)))
		gear_motion["target_down"] = bool(gear_row.target_down)
		gear_motion["status"] = str(gear_row.status)
	return {tick = tick, channels = channels, gear = gear_state,
		channels_motion = motion, gear_motion = gear_motion}


static func _refresh_state(previous: Dictionary, channel_rows: Array[Dictionary], gear_row: Dictionary) -> Dictionary:
	var state: Dictionary = previous.duplicate()
	var old_channels: Dictionary = state.get("channels", {})
	var next_channels: Dictionary = {}
	var old_motion: Dictionary = {}
	for motion: Dictionary in state.get("channels_motion", []):
		old_motion[str(motion.id)] = motion
	var current_rows: Dictionary = {}
	for row: Dictionary in channel_rows:
		current_rows[str(row.id)] = row
		var old: Dictionary = old_channels.get(str(row.id), {})
		if old.is_empty():
			old = {value = row.value, moving = false, direction = 0,
				position = row.position, position_valid = row.position_valid}
		else:
			old = old.duplicate()
			old["position"] = row.position
			old["position_valid"] = row.position_valid
		next_channels[str(row.id)] = old
	var next_motion: Array[Dictionary] = []	
	for id: String in current_rows:
		var row: Dictionary = current_rows[id]
		var motion: Dictionary = old_motion.get(id, _motion_record(row, _stationary(float(row.value)))).duplicate()
		motion["position"] = row.position
		motion["position_valid"] = row.position_valid
		next_motion.append(motion)
	state["channels"] = next_channels
	state["channels_motion"] = next_motion
	if not gear_row.is_empty():
		var old_gear: Dictionary = state.get("gear", {})
		if old_gear.is_empty():
			old_gear = {value = gear_row.value, moving = false, direction = 0,
				target_down = gear_row.target_down, position = gear_row.position,
				position_valid = gear_row.position_valid, status = gear_row.status}
		else:
			old_gear = old_gear.duplicate()
			old_gear["position"] = gear_row.position
			old_gear["position_valid"] = gear_row.position_valid
			old_gear["target_down"] = gear_row.target_down
			old_gear["status"] = gear_row.status
		state["gear"] = old_gear
		var old_gear_motion: Dictionary = state.get("gear_motion", _motion_record(gear_row, _stationary(float(gear_row.value)))).duplicate()
		old_gear_motion["position"] = gear_row.position
		old_gear_motion["position_valid"] = gear_row.position_valid
		old_gear_motion["target_down"] = gear_row.target_down
		old_gear_motion["status"] = gear_row.status
		state["gear_motion"] = old_gear_motion
	else:
		state["gear"] = {}
		state["gear_motion"] = {}
	return state


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
	return {value = clampf(float(extension_value), 0.0, 1.0), target_down = target_down,
		position = position_value if position_valid else Vector3.ZERO, position_valid = position_valid,
		status = str(value.get("status", ""))}


static func _motion_record(row: Dictionary, measured: Dictionary) -> Dictionary:
	var result: Dictionary = {id = str(row.get("id", "gear")), value = float(row.get("value", 0.0)),
		delta = float(measured.get("delta", 0.0)), speed_per_s = float(measured.get("speed_per_s", 0.0)),
		direction = int(measured.get("direction", 0)), moving = bool(measured.get("moving", false)),
		position = row.get("position", Vector3.ZERO), position_valid = bool(row.get("position_valid", false))}
	if row.has("load"):
		result["load"] = float(row.load)
	return result


static func _event(system: String, event_kind: String, identity: String, position: Vector3,
		position_valid: bool, speed: float, direction: int) -> Dictionary:
	return {system = system, event = event_kind, id = identity, position = position,
		position_valid = position_valid, speed_per_s = speed, direction = direction}


static func _stationary(value: float) -> Dictionary:
	return {moving = false, delta = 0.0, speed_per_s = 0.0, direction = 0, valid = is_finite(value)}


static func _tick_rate(value: Variant) -> float:
	return maxf(1.0, float(value)) if _number_is_finite(value) and float(value) > 0.0 else DEFAULT_TICK_RATE_HZ


static func _number_is_finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
