# SM-03/04: optional, failsafe auxiliary input for the smoke pump. It has no access to flight commands or traces.
extends RefCounted

const AXES := 10
const MAX_BUTTONS := 128
const MIN_AXIS_SPAN := 0.5
const ARM_OFF_THRESHOLD := 0.05
const AXIS_OFF_THRESHOLD := 0.05
const AXIS_ON_THRESHOLD := 0.12

var binding: Dictionary = {}
var connected: bool = false
var device_id: int = -1
var _armed: bool = false
var _amount: float = 0.0
var _axis_active: bool = false
var _axis_observed: bool = false
var _button_observed: bool = false
var _last_button_pressed: bool = false
var _toggle_on: bool = false


## Accepts a saved aux.smoke binding and the current AETR axes. Invalid AUX disables only smoke.
func configure(value: Variant, flight_axes: Array = []) -> bool:
	binding = value.duplicate(true) if valid_binding(value, flight_axes) else {}
	_reset_state()
	return not binding.is_empty()


func connect_device(id: int) -> void:
	connected = true
	device_id = id
	_reset_state()


func disconnect_device() -> void:
	connected = false
	device_id = -1
	_reset_state()


## Current pump request, 0…1. It is presentation input only; callers decide whether smoke is visible.
func amount() -> float:
	return _amount


func is_armed() -> bool:
	return _armed


func on_motion(id: int, axis: int, value: float) -> void:
	if not connected or id != device_id or binding.get("type", "") != "axis":
		return
	if axis != int(binding.axis):
		return
	_axis_observed = true
	sample_axis(value, true)


func on_button(id: int, button: int, pressed: bool) -> void:
	if not connected or id != device_id or binding.get("type", "") != "button":
		return
	if button != int(binding.button):
		return
	_button_observed = true
	_observe_button(pressed, true)


## Track the current axis value. Polling alone is never OFF evidence; only a matching device event can arm it.
func sample_axis(value: float, event_evidence: bool = false) -> float:
	if not connected or binding.get("type", "") != "axis":
		_amount = 0.0
		return _amount
	if not is_finite(value):
		_armed = false
		_axis_active = false
		_axis_observed = false
		_amount = 0.0
		return _amount
	var x := axis_amount(value, binding)
	if not _armed:
		if event_evidence and _axis_observed and x <= ARM_OFF_THRESHOLD:
			_armed = true
		_amount = 0.0
		return _amount
	if _axis_active:
		if x <= AXIS_OFF_THRESHOLD:
			_axis_active = false
	elif x >= AXIS_ON_THRESHOLD:
		_axis_active = true
	_amount = x if _axis_active else 0.0
	return _amount


## Track a polled button state. Polling alone is never OFF evidence; only a matching release event can arm it.
func sample_button(pressed: bool) -> float:
	if not connected or binding.get("type", "") != "button":
		_amount = 0.0
		return _amount
	_observe_button(pressed, false)
	return _amount


static func axis_amount(value: float, axis_binding: Dictionary) -> float:
	var off_value: float = float(axis_binding.off)
	var on_value: float = float(axis_binding.on)
	return clampf((value - off_value) / (on_value - off_value), 0.0, 1.0)


static func flight_axes(profile: Variant) -> Array:
	var result: Array = []
	if typeof(profile) != TYPE_DICTIONARY:
		return result
	for name in ["roll", "pitch", "yaw", "throttle"]:
		var channel: Variant = profile.get(name)
		if typeof(channel) == TYPE_DICTIONARY and typeof(channel.get("axis")) == TYPE_INT:
			if not result.has(channel.axis):
				result.append(channel.axis)
	return result


static func valid_binding(value: Variant, reserved_axes: Array = []) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("type")) != TYPE_STRING:
		return false
	match value.type:
		"axis":
			if typeof(value.get("axis")) != TYPE_INT or typeof(value.get("invert")) != TYPE_BOOL:
				return false
			var axis: int = value.axis
			if axis < 0 or axis >= AXES or reserved_axes.has(axis):
				return false
			for field in ["off", "on"]:
				var endpoint: Variant = value.get(field)
				if not (typeof(endpoint) in [TYPE_INT, TYPE_FLOAT]):
					return false
				if not is_finite(float(endpoint)) or float(endpoint) < -1.0 or float(endpoint) > 1.0:
					return false
			if absf(float(value.on) - float(value.off)) < MIN_AXIS_SPAN:
				return false
			return value.invert == (float(value.on) < float(value.off))
		"button":
			if typeof(value.get("button")) != TYPE_INT or typeof(value.get("mode")) != TYPE_STRING:
				return false
			if value.button < 0 or value.button >= MAX_BUTTONS:
				return false
			return value.mode in ["level", "toggle_edge"]
	return false


## Keep a valid AETR profile when aux.smoke is corrupt or overlaps an AETR axis.
static func sanitize_profile(value: Variant, warn: bool = true) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary = value.duplicate(true)
	if not result.has("aux"):
		return result
	var aux: Variant = result.get("aux")
	if typeof(aux) != TYPE_DICTIONARY:
		if warn:
			push_warning("Ignoring malformed aux profile; radio flight channels remain available.")
		result.erase("aux")
		return result
	if aux.has("smoke") and not valid_binding(aux.get("smoke"), flight_axes(result)):
		if warn:
			push_warning("Ignoring invalid aux.smoke assignment; radio flight channels remain available.")
		aux.erase("smoke")
	if aux.is_empty():
		result.erase("aux")
	else:
		result.aux = aux
	return result


func _observe_button(pressed: bool, event_evidence: bool) -> void:
	if event_evidence:
		_button_observed = true
	if not _armed:
		if event_evidence and _button_observed and not pressed:
			_armed = true
		_last_button_pressed = false
		_amount = 0.0
		return
	if binding.mode == "level":
		_amount = 1.0 if pressed else 0.0
	else:
		if pressed and not _last_button_pressed:
			_toggle_on = not _toggle_on
		_amount = 1.0 if _toggle_on else 0.0
	_last_button_pressed = pressed


func _reset_state() -> void:
	_armed = false
	_amount = 0.0
	_axis_active = false
	_axis_observed = false
	_button_observed = false
	_last_button_pressed = false
	_toggle_on = false
