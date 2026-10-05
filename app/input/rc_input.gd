# RC transmitter / joystick reader (D6a): raw axes → stick positions, with the safety rules a real radio needs.
# A pure state machine: it never reads Input itself (the caller passes axis values and events), so every rule is
# testable headless. Facts behind the rules (Godot 4.7.2 + EdgeTX source, RESEARCH.md plan review #3):
#   - Godot exposes axes 0–9 (JoyAxis.MAX = 10), in −1…+1, with no deadzone at get_joy_axis.
#   - An axis reads 0.0 until it first MOVES (SDL sends no event before that), so a resting throttle reads as
#     mid-throttle. Hence ARMING: the throttle stays at idle until the throttle axis has been seen (an event
#     arrived since connection) at or below ARM_THROTTLE.
#   - Unplugging zeroes every axis; the caller applies the failsafe (idle, neutral, pause) on disconnect.
# Radios already apply expo, rates and mixes: positions pass through unshaped (no deadzone, no expo).
extends RefCounted

const AXES := 10 # Godot's JoyAxis.MAX
## Throttle at or below this (0…1) arms the radio.
const ARM_THROTTLE := 0.05

## Default channel map: EdgeTX's AETR order in USB Joystick Classic mode (Ch1–4 → HID X, Y, Z, Rx = axes 0–3).
## Directions assume EdgeTX's "stick forward/right = +100" (elevator forward = +1, so pitch, +1 = stick back, is
## inverted). Evidence: estimated, to verify with the owner's radio (D6d); D6b replaces this with a calibration.
## throttle_unipolar: the throttle axis spans 0…1 (an SDL gamepad trigger) instead of −1…+1.
const DEFAULT_PROFILE := {
	roll = { axis = 0, invert = false },
	pitch = { axis = 1, invert = true },
	throttle = { axis = 2, invert = false },
	yaw = { axis = 3, invert = false },
	throttle_unipolar = false,
}

var profile := DEFAULT_PROFILE.duplicate(true)
var connected := false
var device_id := -1
## Identity for saving a calibration (D6b): "guid|vid:pid|name".
var device_key := ""
var device_name := ""
var armed := false
## Latest raw axis values (−1…+1), polled once per physics tick.
var axes := PackedFloat64Array()
var _seen := {} # axis index → true once an event arrived for it since connection


func _init() -> void:
	axes.resize(AXES)


## info: { guid, name, vendor_id, product_id } (see Input.get_joy_guid / get_joy_info / get_joy_name).
func connect_device(id: int, info: Dictionary) -> void:
	connected = true
	device_id = id
	device_name = str(info.get("name", "joystick %d" % id))
	device_key = "%s|%04x:%04x|%s" % [info.get("guid", ""), int(info.get("vendor_id", 0)), int(info.get("product_id", 0)), device_name]
	armed = false
	_seen.clear()
	axes.fill(0.0)


func disconnect_device() -> void:
	connected = false
	armed = false
	_seen.clear()
	axes.fill(0.0)


## An axis event from the device (InputEventJoypadMotion): the axis has really reported a position.
func on_motion(id: int, axis: int, value: float) -> void:
	if not connected or id != device_id or axis < 0 or axis >= AXES:
		return
	_seen[axis] = true
	axes[axis] = value


## Polls every axis once per physics tick. read_axis(device_id, axis) -> float, e.g. Input.get_joy_axis.
func poll(read_axis: Callable) -> void:
	if not connected:
		return
	for i in AXES:
		axes[i] = clampf(read_axis.call(device_id, i), -1.0, 1.0)
	if not armed and _seen.has(int(profile.throttle.axis)) and throttle_position() <= ARM_THROTTLE:
		armed = true


func _channel(name: String) -> float:
	var ch: Dictionary = profile[name]
	var v := axes[int(ch.axis)]
	return -v if ch.invert else v


## Throttle stick position 0…1, whether or not the radio is armed.
func throttle_position() -> float:
	var v := _channel("throttle")
	return clampf(v if profile.throttle_unipolar else (v + 1.0) * 0.5, 0.0, 1.0)


## Stick positions { roll, pitch, yaw: −1…1, throttle: 0…1 }. Throttle is idle (0) until armed.
func sticks() -> Dictionary:
	return {
		roll = clampf(_channel("roll"), -1.0, 1.0),
		pitch = clampf(_channel("pitch"), -1.0, 1.0),
		yaw = clampf(_channel("yaw"), -1.0, 1.0),
		throttle = throttle_position() if armed else 0.0,
	}


## One line for the panel.
func describe() -> String:
	if not connected:
		return "input: keyboard"
	return "input: radio \"%s\" %s" % [device_name, "ARMED" if armed else "SAFE - move throttle to low to arm"]
