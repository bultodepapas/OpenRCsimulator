# RC transmitter / joystick / gamepad reader (D6a, D6b): raw axes → stick positions, with the safety rules a real
# radio needs. A pure state machine: it never reads Input itself (the caller passes axis values and events), so
# every rule is testable headless. Facts behind the rules (Godot 4.7.2 + EdgeTX source, RESEARCH.md plan review #3):
#   - Godot exposes axes 0–9 (JoyAxis.MAX = 10), in −1…+1, with no deadzone at get_joy_axis.
#   - An axis reads 0.0 until it first MOVES (SDL sends no event before that), so a resting throttle reads as
#     mid-throttle. Hence ARMING: the throttle stays at idle until the throttle axis has been seen (an event
#     arrived since connection) at or below ARM_THROTTLE.
#   - Unplugging zeroes every axis; the caller applies the failsafe (idle, neutral, pause) on disconnect.
# Profiles (rc_calibration.gd makes them): each channel maps one axis through its calibration
# { axis, invert, min, center, max }. Radios pass positions through unshaped (they already apply expo and rates);
# gamepads get a deadzone and expo, and their spring-centred throttle stick drives the throttle as a RATE.
extends RefCounted

const AXES := 10 # Godot's JoyAxis.MAX
## Throttle at or below this (0…1) arms a radio.
const ARM_THROTTLE := 0.05

## Default radio profile: EdgeTX's AETR order in USB Joystick Classic mode (Ch1–4 → HID X, Y, Z, Rx = axes 0–3),
## full-range endpoints. Directions assume EdgeTX's "stick forward/right = +100" (elevator forward = +1, so pitch,
## +1 = stick back, is inverted). Evidence: estimated, to verify with the owner's radio (D6d); a calibration replaces it.
const DEFAULT_PROFILE := {
	kind = "radio",
	roll = { axis = 0, invert = false, min = -1.0, center = 0.0, max = 1.0 },
	pitch = { axis = 1, invert = true, min = -1.0, center = 0.0, max = 1.0 },
	throttle = { axis = 2, invert = false, min = -1.0, center = 0.0, max = 1.0 },
	yaw = { axis = 3, invert = false, min = -1.0, center = 0.0, max = 1.0 },
}

## Standard gamepad (SDL mapping), Mode 2: left stick = throttle (rate) + rudder, right stick = aileron + elevator.
## SDL's stick Y is −1 up, so stick back (+pitch) is already positive; throttle rises when the left stick is pushed up.
## deadzone (rescaled) and expo (y = (1−e)·x + e·x³) are typical gamepad-flying values (estimated).
const GAMEPAD_PROFILE := {
	kind = "gamepad",
	roll = { axis = 2, invert = false, min = -1.0, center = 0.0, max = 1.0 },
	pitch = { axis = 3, invert = false, min = -1.0, center = 0.0, max = 1.0 },
	throttle = { axis = 1, invert = true, min = -1.0, center = 0.0, max = 1.0 },
	yaw = { axis = 0, invert = false, min = -1.0, center = 0.0, max = 1.0 },
	deadzone = 0.08,
	expo = 0.3,
	throttle_rate = 0.5, # per second at full stick
}

## Device names that are radios even when SDL maps them as gamepads (Linux maps EdgeTX Classic as a gamepad).
const RADIO_NAMES := ["edgetx", "opentx", "frsky", "radiomaster", "jumper", "taranis", "betafpv", "flysky", "ethos"]

var profile := DEFAULT_PROFILE.duplicate(true)
var connected := false
var device_id := -1
## Identity for saving a calibration: "guid|vid:pid|name".
var device_key := ""
var device_name := ""
## Where the profile came from: "default", "gamepad" or "calibrated".
var profile_source := "default"
var armed := false
## Latest raw axis values (−1…+1), polled once per physics tick.
var axes := PackedFloat64Array()
var _seen := {} # axis index → true once an event arrived for it since connection
var _rate_throttle := 0.0 # gamepad throttle (0…1), integrated from the stick


func _init() -> void:
	axes.resize(AXES)


## info: { guid, name, vendor_id, product_id, known } (see Input.get_joy_guid / get_joy_info / is_joy_known).
## saved: a calibrated profile for this device, or {}.
func connect_device(id: int, info: Dictionary, saved := {}) -> void:
	connected = true
	device_id = id
	device_name = str(info.get("name", "joystick %d" % id))
	device_key = key_for(id, info)
	if not saved.is_empty():
		profile = saved.duplicate(true)
		profile_source = "calibrated"
	elif info.get("known", false) and not looks_like_radio(device_name):
		profile = GAMEPAD_PROFILE.duplicate(true)
		profile_source = "gamepad"
	else:
		profile = DEFAULT_PROFILE.duplicate(true)
		profile_source = "default"
	armed = false
	_rate_throttle = 0.0
	_seen.clear()
	axes.fill(0.0)


## "guid|vid:pid|name": stable across sessions and USB ports for the same radio.
static func key_for(id: int, info: Dictionary) -> String:
	return "%s|%04x:%04x|%s" % [info.get("guid", ""), int(info.get("vendor_id", 0)), int(info.get("product_id", 0)), str(info.get("name", "joystick %d" % id))]


static func looks_like_radio(name: String) -> bool:
	var n := name.to_lower()
	for word in RADIO_NAMES:
		if word in n:
			return true
	return false


## A new profile (e.g. a finished calibration). The throttle must be seen low again before it flies.
func use_profile(p: Dictionary, source: String) -> void:
	profile = p.duplicate(true)
	profile_source = source
	armed = false
	_rate_throttle = 0.0


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


func is_rate_throttle() -> bool:
	return profile.get("kind", "radio") == "gamepad"


## Whether this raw axis has reported since the current connection; polling zero is not evidence.
func has_axis_sample(axis: int) -> bool:
	return connected and axis >= 0 and axis < AXES and _seen.has(axis)


## Polls every axis once per physics tick. read_axis(device_id, axis) -> float, e.g. Input.get_joy_axis.
func poll(read_axis: Callable, dt: float) -> void:
	if not connected:
		return
	for i in AXES:
		axes[i] = clampf(read_axis.call(device_id, i), -1.0, 1.0)
	if is_rate_throttle():
		# Spring-centred stick: the throttle starts at idle and moves at a rate, so it is safe from the start.
		armed = true
		_rate_throttle = clampf(_rate_throttle + _shaped(_stick("throttle")) * float(profile.throttle_rate) * dt, 0.0, 1.0)
	elif not armed and _seen.has(int(profile.throttle.axis)) and throttle_position() <= ARM_THROTTLE:
		armed = true


## Calibrated position of a centred stick: −1…+1, piecewise linear on each side of its centre.
static func normalize(v: float, ch: Dictionary) -> float:
	var c: float = ch.center
	var x: float = (v - c) / maxf(float(ch.max) - c, 1e-6) if v >= c else (v - c) / maxf(c - float(ch.min), 1e-6)
	x = clampf(x, -1.0, 1.0)
	return -x if ch.invert else x


## Calibrated throttle stick: 0…1 between its endpoints (invert: the min end is full throttle).
static func normalize_throttle(v: float, ch: Dictionary) -> float:
	var x := clampf((v - float(ch.min)) / maxf(float(ch.max) - float(ch.min), 1e-6), 0.0, 1.0)
	return 1.0 - x if ch.invert else x


## Gamepad shaping: rescaled deadzone, then expo. Radios: unchanged.
func _shaped(x: float) -> float:
	if profile.get("kind", "radio") != "gamepad":
		return x
	var dz: float = profile.deadzone
	var m := maxf(0.0, absf(x) - dz) / (1.0 - dz)
	var e: float = profile.expo
	return signf(x) * ((1.0 - e) * m + e * m * m * m)


func _stick(name: String) -> float:
	var ch: Dictionary = profile[name]
	return normalize(axes[int(ch.axis)], ch)


## Throttle stick position 0…1, whether or not the radio is armed (gamepads: the integrated throttle).
func throttle_position() -> float:
	if is_rate_throttle():
		return _rate_throttle
	var ch: Dictionary = profile.throttle
	return normalize_throttle(axes[int(ch.axis)], ch)


## Stick positions { roll, pitch, yaw: −1…1, throttle: 0…1 }. Throttle is idle (0) until armed.
func sticks() -> Dictionary:
	return {
		roll = _shaped(_stick("roll")),
		pitch = _shaped(_stick("pitch")),
		yaw = _shaped(_stick("yaw")),
		throttle = throttle_position() if armed else 0.0,
	}


## One line for the panel.
func describe() -> String:
	if not connected:
		return "input: keyboard"
	var what := "gamepad" if profile.get("kind", "radio") == "gamepad" else "radio"
	var state := "ARMED" if armed else "SAFE - move throttle to low to arm"
	return "input: %s \"%s\" (%s profile, [K] calibrate) %s" % [what, device_name, profile_source, state]
