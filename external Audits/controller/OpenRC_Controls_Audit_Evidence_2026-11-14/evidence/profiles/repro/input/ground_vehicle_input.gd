## Testable sampler for RC ground-vehicle controls. The caller owns Input polling and
## passes only normalized booleans/axes; this class never reads engine input state.
extends RefCounted

const STEERING_DEADZONE := 0.12
const TRIGGER_NEUTRAL := 0.04

var _keyboard_armed := true
var _gamepad_armed := false
var _gamepad_was_connected := false
var _gamepad_device_id := -1


## `keys`: accelerate, reverse, left, right, brake, blocked, focused.
## `joy`: connected, device_id, left_x (-1..1), right_trigger/left_trigger (0..1), reverse.
## Gamepad presence is exclusive. Connect, reconnect, focus/modal release and device loss all
## require a neutral sample before drive commands can pass through.
func sample(keys: Dictionary, joy: Dictionary) -> Dictionary:
	var blocked := _flag(keys, "blocked") or (keys.has("focused") and not _flag(keys, "focused"))
	if blocked:
		_keyboard_armed = false
		_gamepad_armed = false
		return _result("none", false)

	var connected := _flag(joy, "connected")
	if connected:
		var device_id := _integer(joy.get("device_id", -1), -1)
		if not _gamepad_was_connected or device_id != _gamepad_device_id:
			_gamepad_armed = false
			_gamepad_device_id = device_id
			_keyboard_armed = false
		_gamepad_was_connected = true
		var values := _validated_gamepad(joy)
		if device_id < 0 or values.is_empty():
			_gamepad_armed = false
			return _result("gamepad", false)
		if not _gamepad_armed:
			if _gamepad_is_neutral(values):
				_gamepad_armed = true
			return _result("gamepad", _gamepad_armed)
		var steer := _shape_steering(float(values.left_x))
		var throttle := _shape_trigger(float(values.right_trigger))
		var brake := _shape_trigger(float(values.left_trigger))
		if brake > 0.0:
			throttle = 0.0
		return {
			"throttle": throttle,
			"steering": steer,
			"brake": brake,
			"reverse": bool(values.reverse),
			"source": "gamepad",
			"armed": true,
		}

	if _gamepad_was_connected:
		_gamepad_was_connected = false
		_gamepad_device_id = -1
		_gamepad_armed = false
		_keyboard_armed = false
		return _result("none", false)

	var key_neutral := not _flag(keys, "accelerate") and not _flag(keys, "reverse") \
		and not _flag(keys, "left") and not _flag(keys, "right") and not _flag(keys, "brake")
	if not _keyboard_armed:
		if key_neutral:
			_keyboard_armed = true
		return _result("keyboard", _keyboard_armed)

	var forward := _flag(keys, "accelerate")
	var backward := _flag(keys, "reverse")
	var left := _flag(keys, "left")
	var right := _flag(keys, "right")
	var brake := 1.0 if _flag(keys, "brake") else 0.0
	var throttle := 1.0 if forward != backward and brake == 0.0 else 0.0
	var reverse := backward and not forward and brake == 0.0
	var steering := float(int(right) - int(left))
	return {
		"throttle": throttle,
		"steering": steering,
		"brake": brake,
		"reverse": reverse,
		"source": "keyboard",
		"armed": true,
	}


func reset() -> void:
	_keyboard_armed = true
	_gamepad_armed = false
	_gamepad_was_connected = false
	_gamepad_device_id = -1


func _validated_gamepad(joy: Dictionary) -> Dictionary:
	for key in ["left_x", "right_trigger", "left_trigger"]:
		var value: Variant = joy.get(key, NAN)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or typeof(value) == TYPE_BOOL or not is_finite(float(value)):
			return {}
	var left_x := float(joy.left_x)
	var right_trigger := float(joy.right_trigger)
	var left_trigger := float(joy.left_trigger)
	if absf(left_x) > 1.0 or right_trigger < 0.0 or right_trigger > 1.0 or left_trigger < 0.0 or left_trigger > 1.0:
		return {}
	if joy.has("reverse") and typeof(joy.reverse) != TYPE_BOOL:
		return {}
	return {"left_x": left_x, "right_trigger": right_trigger, "left_trigger": left_trigger,
		"reverse": _flag(joy, "reverse")}


func _gamepad_is_neutral(values: Dictionary) -> bool:
	return absf(float(values.left_x)) <= STEERING_DEADZONE \
		and float(values.right_trigger) <= TRIGGER_NEUTRAL \
		and float(values.left_trigger) <= TRIGGER_NEUTRAL \
		and not bool(values.reverse)


func _shape_steering(value: float) -> float:
	var magnitude := absf(value)
	if magnitude <= STEERING_DEADZONE:
		return 0.0
	return signf(value) * (magnitude - STEERING_DEADZONE) / (1.0 - STEERING_DEADZONE)


## Use the same rest region for arming and driving. Raw trigger noise must not
## become a command immediately after the one neutral sample that armed the pad.
func _shape_trigger(value: float) -> float:
	return maxf(0.0, (value - TRIGGER_NEUTRAL) / (1.0 - TRIGGER_NEUTRAL))


func _flag(source: Dictionary, key: String) -> bool:
	return source.get(key, false) == true


func _integer(value: Variant, fallback: int) -> int:
	return int(value) if typeof(value) == TYPE_INT else fallback


func _result(source: String, armed: bool) -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false,
		"source": source, "armed": armed}
