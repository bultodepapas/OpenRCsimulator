# RC transmitter / joystick / gamepad reader. A pure sampling seam: the caller
# supplies input events and the axis reader; this class owns mapping, shaping,
# arming evidence, and the fixed-tick rate-throttle integrator.
extends RefCounted

const SmokeAux := preload("res://input/smoke_aux.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const AXES := 10
const ARM_THROTTLE := 0.05

## Legacy EdgeTX AETR mapping, retained for calibration/migration callers.
const DEFAULT_PROFILE := {
	"kind": "radio",
	"roll": {"axis": 0, "invert": false, "min": -1.0, "center": 0.0, "max": 1.0},
	"pitch": {"axis": 1, "invert": true, "min": -1.0, "center": 0.0, "max": 1.0},
	"throttle": {"axis": 2, "invert": false, "min": -1.0, "center": 0.0, "max": 1.0},
	"yaw": {"axis": 3, "invert": false, "min": -1.0, "center": 0.0, "max": 1.0},
}

## Legacy spring-centred SDL gamepad profile, kept as an import fixture.
const GAMEPAD_PROFILE := {
	"kind": "gamepad",
	"roll": {"axis": 2, "invert": false, "min": -1.0, "center": 0.0, "max": 1.0},
	"pitch": {"axis": 3, "invert": false, "min": -1.0, "center": 0.0, "max": 1.0},
	"throttle": {"axis": 1, "invert": true, "min": -1.0, "center": 0.0, "max": 1.0},
	"yaw": {"axis": 0, "invert": false, "min": -1.0, "center": 0.0, "max": 1.0},
	"deadzone": 0.08,
	"expo": 0.3,
	"throttle_rate": 0.5,
}

const RADIO_NAMES := ["edgetx", "opentx", "frsky", "radiomaster", "jumper", "taranis", "betafpv", "flysky", "ethos"]

var profile: Dictionary = DEFAULT_PROFILE.duplicate(true)
var connected := false
var device_id := -1
var device_key := ""
var device_name := ""
var profile_source := "default"
var profile_error := ""
var input_error := ""
var armed := false
var axes := PackedFloat64Array()
var smoke_aux = SmokeAux.new()
## These are input requests, not simulated flap/gear actuator positions.
var _extra_aux := {"flaps": SmokeAux.new(), "gear": SmokeAux.new()}
var _aux_action_values := {"smoke": 0.0, "flaps": 0.0, "gear": 0.0}
var _auxiliary_enabled := true

var _seen: Dictionary = {}
var _throttle_low_seen := false
var _rate_throttle := 0.0
var _neutral_elapsed := 0.0
var _pressed_buttons: Dictionary = {}
var _neutral_release_pending := false
var _profile_ready := false
var _profile_snapshot: Dictionary = {}


func _init() -> void:
	axes.resize(AXES)
	_profile_ready = _activate_profile(DEFAULT_PROFILE, "default", false)


## info: {guid,name,vendor_id,product_id,known}; saved may be a V2 or legacy profile.
func connect_device(id: int, info: Dictionary, saved: Dictionary = {}) -> void:
	connected = true
	device_id = id
	device_name = str(info.get("name", "joystick %d" % id))
	device_key = key_for(id, info)
	input_error = ""
	profile_error = ""
	_pressed_buttons.clear()
	var upgraded: Dictionary = ControllerProfile.upgrade_legacy(saved) if not saved.is_empty() else {}
	if not upgraded.is_empty():
		_activate_profile(upgraded, "calibrated", false)
	elif bool(info.get("known", false)) and not looks_like_radio(device_name):
		_activate_profile(ControllerProfile.defaults("gamepad", "mode2"), "gamepad", false)
	elif looks_like_radio(device_name):
		_activate_profile(ControllerProfile.defaults("radio", "radio_custom"), "default", false)
	else:
		profile = ControllerProfile.unconfigured()
		_profile_ready = false
		profile_source = "unconfigured"
		profile_error = "Controller role and flight channels are not configured."
		_reset_controls(false)
		_configure_smoke_aux()
	smoke_aux.connect_device(id)
	for channel in _extra_aux.values(): channel.connect_device(id)
	_auxiliary_enabled = true
	_reset_controls(false)
	if _profile_ready:
		profile_error = ""


## "guid|vid:pid|name", retained only as legacy lookup evidence.
static func key_for(id: int, info: Dictionary) -> String:
	return "%s|%04x:%04x|%s" % [info.get("guid", ""), int(info.get("vendor_id", 0)), int(info.get("product_id", 0)), str(info.get("raw_name", info.get("name", "joystick %d" % id)))]


static func looks_like_radio(name: String) -> bool:
	var lowered := name.to_lower()
	for token in RADIO_NAMES:
		if token in lowered:
			return true
	return false


## Activates only a wholly valid candidate. Profile changes clear stale samples and arming evidence.
func use_profile(candidate: Dictionary, source: String) -> bool:
	var upgraded := ControllerProfile.upgrade_legacy(candidate)
	if upgraded.is_empty():
		profile_error = "Profile is invalid and was not applied."
		return false
	if not _activate_profile(upgraded, source, false, true):
		return false
	profile_error = ""
	return true


func disconnect_device() -> void:
	connected = false
	device_id = -1
	smoke_aux.disconnect_device()
	for channel in _extra_aux.values(): channel.disconnect_device()
	_aux_action_values = {"smoke": 0.0, "flaps": 0.0, "gear": 0.0}
	_reset_controls(false)
	_pressed_buttons.clear()
	input_error = ""


func is_gamepad() -> bool:
	return _profile_ready and profile.get("kind", "radio") == "gamepad"


func is_rate_throttle() -> bool:
	if not _profile_ready:
		return false
	return profile.get("throttle_mode", "stick_rate" if profile.get("kind", "radio") == "gamepad" else "radio_absolute") == "stick_rate"


## Ordinary menus keep the connection's axis evidence and virtual throttle.
## Focus recovery requires new axis events independently of preserving throttle.
func require_neutral(preserve_throttle: bool = true, fresh_samples: bool = false) -> void:
	_neutral_elapsed = 0.0
	_neutral_release_pending = bool(profile.get("require_release", true)) and not _pressed_buttons.is_empty()
	if is_gamepad():
		armed = false
		if is_rate_throttle() and not preserve_throttle:
			_rate_throttle = 0.0
		if not is_rate_throttle():
			_rate_throttle = 0.0
	elif not preserve_throttle:
		# Radios keep their absolute-throttle contract; a full ownership change
		# asks for fresh low-throttle evidence but not centered-stick dwell.
		armed = false
		_throttle_low_seen = false
	if not preserve_throttle or (is_gamepad() and fresh_samples):
		_seen.clear()
		axes.fill(0.0)
	input_error = ""
	if not preserve_throttle or fresh_samples:
		_configure_smoke_aux()


## Explicit scenario-start boundary for a spring-centred gamepad.
func set_rate_throttle_for_start(position: float) -> bool:
	if not is_gamepad() or not is_rate_throttle() or not is_finite(position) or position < 0.0 or position > 1.0:
		return false
	_rate_throttle = position
	return true


func has_axis_sample(axis: int) -> bool:
	return connected and axis >= 0 and axis < AXES and _seen.has(axis)


func on_motion(id: int, axis: int, value: float) -> void:
	if not connected or id != device_id or axis < 0 or axis >= AXES:
		return
	if _auxiliary_enabled and input_error.is_empty() and profile_error.is_empty():
		smoke_aux.on_motion(id, axis, value)
		for channel in _extra_aux.values(): channel.on_motion(id, axis, value)
	if not is_finite(value):
		_invalidate_input("Non-finite axis sample; controls require fresh neutral evidence.")
		return
	_seen[axis] = true
	axes[axis] = clampf(value, -1.0, 1.0)
	if not armed and axis == _throttle_axis() and not is_rate_throttle():
		_throttle_low_seen = _normalized_throttle(axes[axis]) <= _idle_threshold()


func on_button(id: int, button: int, pressed: bool) -> void:
	if not connected or id != device_id or button < 0:
		return
	if _auxiliary_enabled and input_error.is_empty() and profile_error.is_empty():
		smoke_aux.on_button(id, button, pressed)
		for channel in _extra_aux.values(): channel.on_button(id, button, pressed)
	if pressed:
		_pressed_buttons[button] = true
	else:
		_pressed_buttons.erase(button)
		_neutral_release_pending = bool(profile.get("require_release", true)) and not _pressed_buttons.is_empty()


## Synchronizes held-button evidence from the selected device on focus/selection return.
func observe_pressed_buttons(buttons: Array) -> void:
	_pressed_buttons.clear()
	for button in buttons:
		if typeof(button) == TYPE_INT and int(button) >= 0:
			_pressed_buttons[int(button)] = true
	_neutral_release_pending = bool(profile.get("require_release", true)) and not _pressed_buttons.is_empty()


## Samples all axes and optional smoke AUX. `integrate=false` still collects fresh
## neutral evidence, but cannot move a rate throttle during a hold/menu.
func poll(read_axis: Callable, dt: float, read_button: Callable = Callable(), integrate: bool = true) -> void:
	if not connected:
		return
	set_auxiliary_enabled(integrate)
	if not _profile_ready or profile != _profile_snapshot:
		var validation := ControllerProfile.validate(profile)
		if not validation.ok:
			_profile_ready = false
			_profile_snapshot.clear()
			profile_error = "Invalid active profile: " + "; ".join(validation.errors)
			_invalidate_input("Invalid profile; flight commands are disabled.")
			return
		_profile_ready = true
		_profile_snapshot = profile.duplicate(true)
		_configure_smoke_aux()
	if not is_finite(dt) or dt < 0.0 or not read_axis.is_valid():
		_invalidate_input("Invalid input sample interval or axis reader.")
		return
	for axis in AXES:
		var value: float = float(read_axis.call(device_id, axis))
		if not is_finite(value):
			_invalidate_input("Non-finite polled axis sample; controls require fresh neutral evidence.")
			return
		axes[axis] = clampf(value, -1.0, 1.0)
	if read_button.is_valid():
		var held_buttons: Array[int] = []
		for button in 128:
			if bool(read_button.call(device_id, button)):
				held_buttons.append(button)
		observe_pressed_buttons(held_buttons)
	if _auxiliary_enabled and input_error.is_empty() and profile_error.is_empty():
		for channel in [smoke_aux, _extra_aux.flaps, _extra_aux.gear]:
			var binding: Dictionary = channel.binding
			if binding.get("type", "") == "axis":
				channel.sample_axis(axes[int(binding.axis)])
			elif binding.get("type", "") == "button" and read_button.is_valid():
				channel.sample_button(bool(read_button.call(device_id, int(binding.button))))
	if is_gamepad():
		_update_neutral_gate(dt)
		if is_rate_throttle() and armed and integrate:
			var rate: float = float(profile.get("throttle_rate", ControllerProfile.DEFAULT_THROTTLE_RATE))
			_rate_throttle = clampf(_rate_throttle + _stick("throttle") * rate * dt, 0.0, 1.0)
	elif not armed and _throttle_low_seen and _normalized_throttle(axes[_throttle_axis()]) <= _idle_threshold():
		armed = true
		input_error = ""


## Compatibility helpers for radio calibration scripts and old fixtures.
static func normalize(value: float, channel: Dictionary) -> float:
	return ControllerProfile.normalize_axis(value, channel)


static func normalize_throttle(value: float, channel: Dictionary) -> float:
	if not is_finite(value):
		return 0.0
	var low: float = float(channel.get("min", -1.0))
	var high: float = float(channel.get("max", 1.0))
	var normalized: float = clampf((value - low) / maxf(high - low, 0.000001), 0.0, 1.0)
	return 1.0 - normalized if bool(channel.get("invert", false)) else normalized


func _stick(name: String) -> float:
	if not _profile_ready:
		return 0.0
	var channel: Variant = profile.get(name, {})
	if typeof(channel) != TYPE_DICTIONARY:
		return 0.0
	return ControllerProfile.conditioned_axis(axes[int(channel.get("axis", -1))], channel, str(profile.get("kind", "radio"))) if int(channel.get("axis", -1)) in range(AXES) else 0.0


func _shaped(value: float) -> float:
	# Legacy helper used by a few diagnostics; channel-specific shaping is used in flight output.
	var channel: Dictionary = {"deadzone": float(profile.get("deadzone", ControllerProfile.DEFAULT_DEADZONE)), "expo": float(profile.get("expo", ControllerProfile.DEFAULT_EXPO))}
	return ControllerProfile.condition_axis(value, channel, str(profile.get("kind", "radio")))


func _normalized_throttle(value: float) -> float:
	var channel: Variant = profile.get("throttle", {})
	return normalize_throttle(value, channel) if typeof(channel) == TYPE_DICTIONARY else 0.0


func throttle_position() -> float:
	if not _profile_ready:
		return 0.0
	if is_rate_throttle():
		return _rate_throttle
	return _normalized_throttle(axes[_throttle_axis()])


func sticks() -> Dictionary:
	if not connected or not _profile_ready:
		return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
	if is_gamepad() and not armed:
		return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
	return {
		"roll": _stick("roll"),
		"pitch": _stick("pitch"),
		"yaw": _stick("yaw"),
		"throttle": throttle_position() if armed else 0.0,
	}


func smoke_amount() -> float:
	return auxiliary_amount("smoke")


## Normalized requests: flaps 0=retracted/1=full, gear 0=down/1=up.
## No aircraft consumes flap/gear requests until its physical capability is implemented.
func auxiliary_amount(channel_name: String) -> float:
	if not connected or not _profile_ready or not _auxiliary_enabled or not input_error.is_empty() or not profile_error.is_empty(): return 0.0
	var channel = smoke_aux if channel_name == "smoke" else _extra_aux.get(channel_name)
	if channel == null: return 0.0
	return channel.amount() if not channel.binding.is_empty() else float(_aux_action_values.get(channel_name, 0.0))


func auxiliary_action(action: String) -> bool:
	if not connected or not _profile_ready or not _auxiliary_enabled or not input_error.is_empty() or not profile_error.is_empty(): return false
	var channel_name := "smoke" if action == "smoke_toggle" else ("gear" if action == "gear_toggle" else "flaps")
	if not action in ["smoke_toggle", "gear_toggle", "flaps_up", "flaps_down", "flaps_cycle"]: return false
	var channel = smoke_aux if channel_name == "smoke" else _extra_aux[channel_name]
	if not channel.binding.is_empty(): return false # one source per function
	match action:
		"flaps_up": _aux_action_values.flaps = 0.0
		"flaps_down": _aux_action_values.flaps = 1.0
		"flaps_cycle": _aux_action_values.flaps = fmod(float(_aux_action_values.flaps) + 0.5, 1.5)
		_: _aux_action_values[channel_name] = 1.0 - float(_aux_action_values[channel_name])
	return true


## Menu/focus input cannot queue toggles to be applied after resume.
func set_auxiliary_enabled(enabled: bool) -> void:
	if enabled == _auxiliary_enabled: return
	_auxiliary_enabled = enabled
	_configure_smoke_aux()


func smoke_is_armed() -> bool:
	return smoke_aux.is_armed()


func _activate_profile(candidate: Dictionary, source: String, preserve_rate: bool, preserve_radio_history: bool = false) -> bool:
	var upgraded := ControllerProfile.upgrade_legacy(candidate)
	if upgraded.is_empty():
		_profile_ready = false
		profile_error = "Profile is invalid and cannot drive flight commands."
		return false
	var keep_radio_history := preserve_radio_history and _profile_ready and connected and str(profile.get("kind", "")) == "radio" and str(upgraded.get("kind", "")) == "radio"
	var old_rate := _rate_throttle
	var previous_axes: PackedFloat64Array = axes.duplicate()
	var previous_seen: Dictionary = _seen.duplicate(true)
	profile = upgraded
	_profile_ready = true
	_profile_snapshot = profile.duplicate(true)
	profile_source = source
	input_error = ""
	_rate_throttle = old_rate if preserve_rate and profile.get("throttle_mode", "") == "stick_rate" else 0.0
	if keep_radio_history:
		armed = false
		_throttle_low_seen = false
		_neutral_elapsed = 0.0
		_neutral_release_pending = bool(profile.get("require_release", true)) and not _pressed_buttons.is_empty()
		axes = previous_axes
		_seen = previous_seen
	else:
		_reset_controls(preserve_rate)
	_configure_smoke_aux()
	return true


func _reset_controls(preserve_rate: bool) -> void:
	armed = false
	_throttle_low_seen = false
	_neutral_elapsed = 0.0
	_neutral_release_pending = bool(profile.get("require_release", true)) and not _pressed_buttons.is_empty()
	_seen.clear()
	axes.fill(0.0)
	if not preserve_rate:
		_rate_throttle = 0.0


func _invalidate_input(message: String) -> void:
	input_error = message
	armed = false
	_throttle_low_seen = false
	_neutral_elapsed = 0.0
	_seen.clear()
	axes.fill(0.0)
	_rate_throttle = 0.0
	_configure_smoke_aux()


func _update_neutral_gate(dt: float) -> void:
	if armed:
		return
	if _neutral_release_pending or not _fresh_neutral_sample():
		_neutral_elapsed = 0.0
		return
	_neutral_elapsed += dt
	var required: float = float(profile.get("neutral_duration_ms", 200)) / 1000.0
	if _neutral_elapsed + 1e-12 >= required:
		armed = true
		_neutral_elapsed = required
		input_error = ""


func _fresh_neutral_sample() -> bool:
	for channel_name in ["roll", "pitch", "yaw", "throttle"]:
		var channel: Dictionary = profile[channel_name]
		var axis: int = int(channel.axis)
		if not _seen.has(axis):
			return false
		var normalized: float = ControllerProfile.normalize_axis(axes[axis], channel)
		if channel_name == "throttle" and not is_rate_throttle():
			if _normalized_throttle(axes[axis]) > _idle_threshold():
				return false
		else:
			var deadzone: float = float(channel.get("deadzone", ControllerProfile.DEFAULT_DEADZONE))
			if absf(normalized) > deadzone:
				return false
	return true


func _throttle_axis() -> int:
	var throttle: Variant = profile.get("throttle", {})
	return int(throttle.get("axis", 0)) if typeof(throttle) == TYPE_DICTIONARY else 0


func _idle_threshold() -> float:
	return float(profile.get("idle_threshold", ARM_THROTTLE))


func _configure_smoke_aux() -> void:
	var axes_in_use := SmokeAux.flight_axes(profile)
	smoke_aux.configure(_smoke_binding(), axes_in_use)
	var aux: Dictionary = profile.get("aux", {}) if profile.get("aux", {}) is Dictionary else {}
	for channel_name in _extra_aux:
		_extra_aux[channel_name].configure(aux.get(channel_name, {}), axes_in_use)
	_aux_action_values = {"smoke": 0.0, "flaps": 0.0, "gear": 0.0}


func _smoke_binding() -> Dictionary:
	var aux: Variant = profile.get("aux", {})
	if typeof(aux) != TYPE_DICTIONARY:
		return {}
	var binding: Variant = aux.get("smoke", {})
	return binding if typeof(binding) == TYPE_DICTIONARY else {}


func _describe_state() -> String:
	if not profile_error.is_empty():
		return "UNCONFIGURED - set a controller role and controls"
	if not input_error.is_empty():
		return "SAFE - " + input_error
	if is_gamepad():
		return "ARMED" if armed else "SAFE - move bound controls, return to neutral, then wait to arm"
	return "ARMED" if armed else "SAFE - move throttle to low to arm"


func describe() -> String:
	if not connected:
		return "input: keyboard"
	var what := str(profile.get("kind", "joystick"))
	return "input: %s \"%s\" (%s profile) %s" % [what, device_name, profile_source, _describe_state()]
