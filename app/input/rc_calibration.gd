# Radio calibration wizard (D6b): "move the stick" channel assignment, per-side endpoints, inversion. Pure state
# machine (the caller feeds raw axes, −1…+1, once per tick, and calls advance() when the pilot presses Enter).
# Steps: rest (sticks centred, throttle low) → throttle → aileron → elevator → rudder. For each control the axis with
# the largest sweep is assigned; its direction comes from the first deflection the prompt asks for (e.g. aileron
# RIGHT first). Profiles are saved per device key in a ConfigFile (save/load below).
extends RefCounted

const RcInput := preload("res://input/rc_input.gd")

const STEPS := ["rest", "throttle", "roll", "pitch", "yaw"]
const PROMPTS := {
	rest = "Centre the sticks, throttle LOW, hands off. Press Enter",
	throttle = "Move the THROTTLE to FULL and back to LOW. Press Enter",
	roll = "Move the AILERON stick fully RIGHT, then LEFT, then centre. Press Enter",
	pitch = "Pull the ELEVATOR stick fully BACK, then FORWARD, then centre. Press Enter",
	yaw = "Move the RUDDER stick fully RIGHT, then LEFT, then centre. Press Enter",
}
## An axis must sweep at least this much (of the −1…+1 range) to count as moved.
const MIN_SWEEP := 0.5
## A deflection beyond this from rest decides the direction (the first one the prompt asked for).
const DIRECTION_THRESHOLD := 0.25

var step := 0
var error := ""
var profile := {}
var _rest := PackedFloat64Array()
var _lo := PackedFloat64Array()
var _hi := PackedFloat64Array()
var _first := PackedFloat64Array() # sign of each axis's first deflection beyond the threshold (0 = none yet)
var _used := {}


func _init() -> void:
	profile = { kind = "radio" }
	for a in [_rest, _lo, _hi, _first]:
		a.resize(RcInput.AXES)


func done() -> bool:
	return step >= STEPS.size()


func prompt() -> String:
	return "" if done() else "%d/%d %s" % [step + 1, STEPS.size(), PROMPTS[STEPS[step]]]


## Feed the latest raw axes, once per tick.
func sample(axes: PackedFloat64Array) -> void:
	if step == 0 or done():
		return
	for i in RcInput.AXES:
		_lo[i] = minf(_lo[i], axes[i])
		_hi[i] = maxf(_hi[i], axes[i])
		var d := axes[i] - _rest[i]
		if _first[i] == 0.0 and absf(d) > DIRECTION_THRESHOLD:
			_first[i] = signf(d)


## The pilot pressed Enter. Returns true when the wizard finished. On a problem, sets `error` and stays on the step.
func advance(axes: PackedFloat64Array) -> bool:
	error = ""
	if done():
		return true
	if step == 0:
		_rest = axes.duplicate()
		_next()
		return false
	var name: String = STEPS[step]
	var best := -1
	for i in RcInput.AXES:
		if not _used.has(i) and (best < 0 or _hi[i] - _lo[i] > _hi[best] - _lo[best]):
			best = i
	if best < 0 or _hi[best] - _lo[best] < MIN_SWEEP:
		error = "no stick moved enough (need a full sweep); try again"
		_reset_sweep()
		return false
	var lo := _lo[best]
	var hi := _hi[best]
	if name == "throttle":
		# The pilot started at LOW (the rest reading): whichever end is nearer rest is idle.
		profile.throttle = { axis = best, invert = absf(_rest[best] - hi) < absf(_rest[best] - lo), min = lo, center = lo, max = hi }
	else:
		var c := _rest[best]
		if c - lo < 0.2 * (hi - lo) or hi - c < 0.2 * (hi - lo):
			error = "the stick did not return to centre before Enter (or moved only one way); try again"
			_reset_sweep()
			return false
		# Prompts ask for the positive direction first: aileron RIGHT, elevator BACK (nose up), rudder RIGHT.
		profile[name] = { axis = best, invert = _first[best] < 0.0, min = lo, center = c, max = hi }
	_used[best] = true
	_next()
	return done()


func _next() -> void:
	step += 1
	_reset_sweep()


func _reset_sweep() -> void:
	for i in RcInput.AXES:
		_lo[i] = _rest[i]
		_hi[i] = _rest[i]
		_first[i] = 0.0


## Saves a profile for a device. Sections are keyed by an MD5 of the device key (ConfigFile-safe).
static func save_profile(path: String, device_key: String, p: Dictionary) -> Error:
	if device_key.is_empty() or not valid(p):
		return ERR_INVALID_DATA
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		return err # Do not overwrite other devices when the existing file cannot be read.
	var section := device_key.md5_text()
	cfg.set_value(section, "device_key", device_key)
	cfg.set_value(section, "profile", p)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	return cfg.save(path)


## The saved profile for a device, or {} if none (or the file is unreadable).
static func load_profile(path: String, device_key: String) -> Dictionary:
	if device_key.is_empty():
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var section := device_key.md5_text()
	var identity: Variant = cfg.get_value(section, "device_key", "")
	if typeof(identity) != TYPE_STRING or identity != device_key:
		return {}
	var p = cfg.get_value(section, "profile", {})
	return p if valid(p) else {}


## Persisted wizard profiles are radios; the built-in gamepad rate profile is not a calibration.
## Reject the whole profile before it reaches RcInput. Throttle ignores center, so its endpoints are allowed;
## centred sticks require min < center < max. Do not coerce malformed types into plausible control mappings.
static func valid(p: Variant) -> bool:
	if typeof(p) != TYPE_DICTIONARY:
		return false
	if typeof(p.get("kind")) != TYPE_STRING or p.kind != "radio":
		return false
	var used_axes: Dictionary = {}
	for name in ["throttle", "roll", "pitch", "yaw"]:
		var ch: Variant = p.get(name)
		if typeof(ch) != TYPE_DICTIONARY:
			return false
		if typeof(ch.get("axis")) != TYPE_INT or typeof(ch.get("invert")) != TYPE_BOOL:
			return false
		var axis: int = ch.axis
		if axis < 0 or axis >= RcInput.AXES or used_axes.has(axis):
			return false
		used_axes[axis] = true
		for key in ["min", "center", "max"]:
			var value: Variant = ch.get(key)
			if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]):
				return false
			if not is_finite(float(value)) or float(value) < -1.0 or float(value) > 1.0:
				return false
		if ch.min >= ch.max or ch.center < ch.min or ch.center > ch.max:
			return false
		if name != "throttle" and (ch.center == ch.min or ch.center == ch.max):
			return false
	return true
