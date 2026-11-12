# Radio calibration wizard (D6b): "move the stick" channel assignment, per-side endpoints, inversion. Pure state
# machine (the caller feeds raw axes, −1…+1, once per tick, and calls advance() when the pilot confirms the step).
# Steps: rest (sticks centred, throttle low) → throttle → aileron → elevator → rudder. Each centered stick's
# requested direction is confirmed while held, before measuring the opposite endpoint. Profiles are saved per device
# key in a ConfigFile (save/load below).
extends RefCounted

const RcInput := preload("res://input/rc_input.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")

const STEPS := ["rest", "throttle", "roll", "pitch", "yaw"]
# UI-15-UX-01: prompts name the function first (Roll/Pitch/Yaw/Throttle) with the RC word second, and never a key:
# each host shows its own Next button or key hint.
const PROMPTS := {
	rest = "Centre the sticks EXCEPT the THROTTLE: leave the THROTTLE fully DOWN (LOW). Keep these positions.",
	throttle = "Move the THROTTLE to FULL and back to LOW.",
	roll = "Hold the ROLL stick (aileron) fully RIGHT.",
	pitch = "Hold the PITCH stick (elevator) fully BACK.",
	yaw = "Hold the YAW stick (rudder) fully RIGHT.",
}
const OPPOSITE_PROMPTS := {
	roll = "Move the ROLL stick (aileron) fully LEFT, then centre.",
	pitch = "Move the PITCH stick (elevator) fully FORWARD, then centre.",
	yaw = "Move the YAW stick (rudder) fully LEFT, then centre.",
}
## Requested direction per centred function: the held endpoint first, then the opposite one (read-only queries).
const HELD_DIRECTIONS := { roll = "right", pitch = "back", yaw = "right" }
const OPPOSITE_DIRECTIONS := { roll = "left", pitch = "forward", yaw = "left" }
## AUX channels other than smoke that a recalibration keeps when they do not overlap the new flight axes. Mirrors
## ControllerActions.AUX_CHANNEL_IDS without "smoke" (checked by tests/test_multirotor_arm_mode_aux.gd).
const EXTRA_AUX_CHANNELS: PackedStringArray = ["flaps", "gear", "arm", "flight_mode"]
## An axis must sweep at least this much (of the −1…+1 range) to count as moved.
const MIN_SWEEP := 0.5
## A second moving channel or a stick left away from its starting position makes an assignment ambiguous.
const OTHER_AXIS_THRESHOLD := 0.25
const THROTTLE_RETURN_FRACTION := 0.05
const CENTER_RETURN_FRACTION := 0.1
## A held deflection must be distinguishable from small center noise. Endpoint validation still
## requires a full sweep and adequate travel on both sides before accepting the channel.
const DIRECTION_THRESHOLD := 0.1

var step := 0
var error := ""
var profile := {}
var _rest := PackedFloat64Array()
var _lo := PackedFloat64Array()
var _hi := PackedFloat64Array()
var _direction_axis := -1
var _direction_sign := 0.0
var _used := {}
var _preserved_smoke: Dictionary = {}
var _preserved_extra_aux: Dictionary = {}
var aux_warning: String = ""


func _init(existing_profile: Dictionary = {}) -> void:
	profile = { kind = "radio" }
	var clean := SmokeAux.sanitize_profile(existing_profile)
	var aux: Variant = clean.get("aux", {})
	if typeof(aux) == TYPE_DICTIONARY:
		var smoke: Variant = aux.get("smoke", {})
		if SmokeAux.valid_binding(smoke, SmokeAux.flight_axes(clean)):
			_preserved_smoke = smoke.duplicate(true)
		for channel_name in EXTRA_AUX_CHANNELS:
			if SmokeAux.valid_binding(aux.get(channel_name), SmokeAux.flight_axes(clean)):
				_preserved_extra_aux[channel_name] = aux[channel_name].duplicate(true)
	for a in [_rest, _lo, _hi]:
		a.resize(RcInput.AXES)


func done() -> bool:
	return step >= STEPS.size()


func prompt() -> String:
	return "" if done() else "%d/%d %s" % [step + 1, STEPS.size(), instruction()]


## The prompt changes within each centered-channel step after confirming direction.
func instruction() -> String:
	if done():
		return ""
	var name: String = STEPS[step]
	return str(OPPOSITE_PROMPTS[name]) if _direction_axis >= 0 else str(PROMPTS[name])


## Read-only presentation queries (UI-15-UX-01). They never change a step, a sweep or the profile.

## The function the current step calibrates ("rest", "throttle", "roll", "pitch", "yaw"), or "" when done.
func current_function() -> String:
	return "" if done() else str(STEPS[step])


## What the pilot is asked to do now: {function, direction, phase}. Phases: "rest" (direction "centre"), "sweep"
## (throttle, direction "full_low"), "hold" (held endpoint), "opposite" (opposite endpoint, then centre), "done".
func requested_target() -> Dictionary:
	if done():
		return { function = "", direction = "", phase = "done" }
	var name: String = STEPS[step]
	if name == "rest":
		return { function = name, direction = "centre", phase = "rest" }
	if name == "throttle":
		return { function = name, direction = "full_low", phase = "sweep" }
	if _direction_axis >= 0:
		return { function = name, direction = str(OPPOSITE_DIRECTIONS[name]), phase = "opposite" }
	return { function = name, direction = str(HELD_DIRECTIONS[name]), phase = "hold" }


## The raw axis assigned to `function` so far ("throttle", "roll", "pitch", "yaw"), or -1.
func assigned_axis(function: String) -> int:
	var channel: Variant = profile.get(function)
	return int(channel.get("axis", -1)) if typeof(channel) == TYPE_DICTIONARY else -1


## True once the rest sample has been taken (after the first step).
func has_rest() -> bool:
	return step > 0


## The rest reading of one raw axis (0.0 before the rest step or for an out-of-range axis).
func rest_value(axis: int) -> float:
	return _rest[axis] if has_rest() and axis >= 0 and axis < RcInput.AXES else 0.0


## The axis confirmed by the held direction of the current centred step, or -1.
func held_axis() -> int:
	return _direction_axis


## +1/−1 for the raw sign of the held (requested) direction, 0 before it is confirmed.
func held_sign() -> float:
	return _direction_sign


## The current step's measured sweep of one raw axis (the rest value when nothing moved yet).
func sweep_min(axis: int) -> float:
	return _lo[axis] if axis >= 0 and axis < RcInput.AXES else 0.0


func sweep_max(axis: int) -> float:
	return _hi[axis] if axis >= 0 and axis < RcInput.AXES else 0.0


## Feed the latest raw axes, once per tick.
func sample(axes: PackedFloat64Array) -> void:
	if step == 0 or done():
		return
	if not _valid_axis_sample(axes):
		error = "invalid axis sample; calibration needs ten finite axes in the -1…+1 range"
		_reset_sweep()
		return
	for i in RcInput.AXES:
		_lo[i] = minf(_lo[i], axes[i])
		_hi[i] = maxf(_hi[i], axes[i])


## The pilot pressed Enter. Returns true when the wizard finished. On a problem, sets `error` and stays on the step.
func advance(axes: PackedFloat64Array) -> bool:
	error = ""
	if done():
		return true
	if not _valid_axis_sample(axes):
		error = "invalid axis sample; calibration needs ten finite axes in the -1…+1 range"
		if step > 0:
			_reset_sweep()
		return false
	if step == 0:
		_rest = axes.duplicate()
		_next()
		return false
	var name: String = STEPS[step]
	# Include the Enter sample even when a caller has not sampled this frame.
	sample(axes)
	if name != "throttle" and _direction_axis < 0:
		_capture_direction(axes)
		return false
	var best := -1
	if name == "throttle":
		for i in RcInput.AXES:
			if not _used.has(i) and (best < 0 or _hi[i] - _lo[i] > _hi[best] - _lo[best]):
				best = i
	else:
		best = _direction_axis
	if best < 0 or _hi[best] - _lo[best] < MIN_SWEEP:
		error = "An already assigned axis moved. Restart calibration and check each requested stick." if _assigned_axis_moved() else "no stick moved enough (need a full sweep); try again"
		_reset_sweep()
		return false
	for i in RcInput.AXES:
		if i != best and (_hi[i] - _lo[i] >= OTHER_AXIS_THRESHOLD or absf(axes[i] - _rest[i]) >= OTHER_AXIS_THRESHOLD):
			error = "More than one axis moved. Move only the requested stick; check transmitter mixes, then try again."
			_reset_sweep()
			return false
	var lo := _lo[best]
	var hi := _hi[best]
	if name == "throttle":
		# The pilot started at LOW (the rest reading): whichever end is nearer rest is idle.
		var return_tolerance: float = THROTTLE_RETURN_FRACTION * (hi - lo)
		if absf(axes[best] - _rest[best]) > return_tolerance or minf(absf(_rest[best] - lo), absf(_rest[best] - hi)) > return_tolerance:
			error = "Return throttle to LOW before continuing; then try again."
			_reset_sweep()
			return false
		profile.throttle = { axis = best, invert = absf(_rest[best] - hi) < absf(_rest[best] - lo), min = lo, center = lo, max = hi }
	else:
		var c := _rest[best]
		if c - lo < 0.2 * (hi - lo) or hi - c < 0.2 * (hi - lo) or absf(axes[best] - c) > CENTER_RETURN_FRACTION * minf(c - lo, hi - c):
			error = "the stick did not return to centre before you continued (or moved only one way); try again"
			_reset_sweep()
			return false
		# The captured held direction is positive: aileron RIGHT, elevator BACK, rudder RIGHT.
		profile[name] = { axis = best, invert = _direction_sign < 0.0, min = lo, center = c, max = hi }
	_used[best] = true
	_next()
	return done()


## Confirm the axis and sign from the currently held requested direction, not from a later larger sweep.
func _capture_direction(axes: PackedFloat64Array) -> void:
	var best := -1
	for i in RcInput.AXES:
		if not _used.has(i) and absf(axes[i] - _rest[i]) >= DIRECTION_THRESHOLD \
				and (best < 0 or absf(axes[i] - _rest[i]) > absf(axes[best] - _rest[best])):
			best = i
	if best < 0:
		error = "An already assigned axis moved. Restart calibration and check each requested stick." if _assigned_axis_moved() else "Hold the requested direction away from centre before continuing; then try again."
		_reset_sweep()
		return
	for i in RcInput.AXES:
		if i != best and (_hi[i] - _lo[i] >= OTHER_AXIS_THRESHOLD or absf(axes[i] - _rest[i]) >= DIRECTION_THRESHOLD):
			error = "More than one axis moved. Move only the requested stick; check transmitter mixes, then try again."
			_reset_sweep()
			return
	var direction := signf(axes[best] - _rest[best])
	# Only the explicitly held endpoint and subsequent opposite sweep form the accepted range.
	_reset_sweep()
	_direction_axis = best
	_direction_sign = direction
	sample(axes)


func _assigned_axis_moved() -> bool:
	for axis in _used:
		if _hi[axis] - _lo[axis] >= MIN_SWEEP:
			return true
	return false


func _next() -> void:
	step += 1
	_reset_sweep()
	if done():
		_preserve_smoke_if_clear()


func _reset_sweep() -> void:
	_direction_axis = -1
	_direction_sign = 0.0
	for i in RcInput.AXES:
		_lo[i] = _rest[i]
		_hi[i] = _rest[i]


static func _valid_axis_sample(axes: PackedFloat64Array) -> bool:
	if axes.size() != RcInput.AXES:
		return false
	for value in axes:
		if not is_finite(value) or value < -1.0 or value > 1.0:
			return false
	return true


## Saves a profile for a device. Sections are keyed by an MD5 of the device key (ConfigFile-safe).
static func save_profile(path: String, device_key: String, p: Dictionary) -> Error:
	var clean := SmokeAux.sanitize_profile(p)
	if device_key.is_empty() or not valid(clean):
		return ERR_INVALID_DATA
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		return err # Do not overwrite other devices when the existing file cannot be read.
	var section := device_key.md5_text()
	cfg.set_value(section, "device_key", device_key)
	cfg.set_value(section, "profile", clean)
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
	return SmokeAux.sanitize_profile(p) if valid(p) else {}


## Saves only the optional smoke binding in the existing per-device section.
## Gamepad AUX never enters or weakens the radio flight-profile schema.
static func save_smoke_binding(path: String, device_key: String, binding: Variant) -> Error:
	if device_key.is_empty() or not SmokeAux.valid_binding(binding):
		return ERR_INVALID_DATA
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		return err # Never overwrite another device's settings when storage is unreadable.
	var section := device_key.md5_text()
	if cfg.has_section(section):
		var identity: Variant = cfg.get_value(section, "device_key", "")
		if typeof(identity) != TYPE_STRING or identity != device_key:
			return ERR_INVALID_DATA
	cfg.set_value(section, "device_key", device_key)
	cfg.set_value(section, "smoke_binding", binding.duplicate(true))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	return cfg.save(path)


## The device's valid smoke binding, or {} if it is unknown or storage is unreadable/corrupt.
static func load_smoke_binding(path: String, device_key: String) -> Dictionary:
	if device_key.is_empty():
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var section := device_key.md5_text()
	var identity: Variant = cfg.get_value(section, "device_key", "")
	if typeof(identity) != TYPE_STRING or identity != device_key:
		return {}
	var binding: Variant = cfg.get_value(section, "smoke_binding", {})
	return binding.duplicate(true) if SmokeAux.valid_binding(binding) else {}


func _preserve_smoke_if_clear() -> void:
	var extra: Dictionary = {}
	for channel_name in _preserved_extra_aux:
		if SmokeAux.valid_binding(_preserved_extra_aux[channel_name], SmokeAux.flight_axes(profile)):
			extra[channel_name] = _preserved_extra_aux[channel_name].duplicate(true)
		else:
			aux_warning = "Existing %s control overlaps a newly calibrated AETR axis; reassign that auxiliary channel." % channel_name
			push_warning(aux_warning)
	if not extra.is_empty(): profile["aux"] = extra
	if _preserved_smoke.is_empty():
		return
	if SmokeAux.valid_binding(_preserved_smoke, SmokeAux.flight_axes(profile)):
		if not profile.has("aux"): profile["aux"] = {}
		profile.aux["smoke"] = _preserved_smoke.duplicate(true)
		return
	aux_warning = "Existing smoke control overlaps a newly calibrated AETR axis; smoke was disabled and needs reassignment."
	push_warning(aux_warning)


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
