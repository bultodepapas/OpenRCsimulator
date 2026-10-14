# F1: event statistics, separate from Input and the flight's calibrated controls.
extends RefCounted

const AXES: int = 10 # Pinned Godot JoyAxis.MAX; these are Godot axes, not a raw HID descriptor.
const MAX_TRACKED_BUTTONS: int = 64
const MAX_RECORDED_BUTTON_TRANSITIONS: int = 256
var devices: Array[Dictionary] = []
var rejected_events: int = 0
var _active: Dictionary = {}


func connect_device(id: int, info: Dictionary, at_usec: int) -> void:
	if id < 0 or _active.has(id):
		return
	var axes: Array[Dictionary] = []
	for axis: int in AXES:
		axes.append({axis = axis, events = 0, min = null, max = null,
			first_event_usec = null, last_event_usec = null, zero_spacing_events = 0})
	var button_index_to_slot: Dictionary = {}
	var device: Dictionary = {session = devices.size(), device_id = id,
		guid = string_or_empty(info.get("guid")), name = string_or_empty(info.get("name")),
		raw_name = string_or_null(info.get("raw_name")), vendor_id = usb_id(info.get("vendor_id")), product_id = usb_id(info.get("product_id")),
		is_joy_known = bool_or_default(info.get("known"), false),
		capabilities = {standard_mapping = bool_or_default(info.get("known"), false),
			vibration_supported = bool_or_null(info.get("vibration_supported"))},
		backend_hints = {steam_input_index = optional_index(info.get("steam_input_index")),
			xinput_index = optional_index(info.get("xinput_index"))},
		connected_at_usec = at_usec, disconnected_at_usec = null, connected = true, axes = axes,
		button_events = 0, button_press_events = 0, button_release_events = 0,
		button_transition_count = 0, button_transitions_omitted = 0, button_transitions = [], buttons = [],
		untracked_button_events = 0, untracked_button_press_events = 0, untracked_button_release_events = 0,
		_button_index_to_slot = button_index_to_slot, _button_states = {}, _last_button_event_usec = at_usec}
	_active[id] = devices.size()
	devices.append(device)


## SDL's pinned Godot backend supplies decimal strings; other providers may supply integers.
static func usb_id(value: Variant) -> Variant:
	if typeof(value) == TYPE_STRING:
		if value.length() > 6 or not value.is_valid_int():
			return null
		value = value.to_int()
	if typeof(value) != TYPE_INT or value < 0 or value > 65535:
		return null
	return value


static func optional_index(value: Variant) -> Variant:
	if typeof(value) == TYPE_STRING:
		if value.length() > 6 or not value.is_valid_int():
			return null
		value = value.to_int()
	if typeof(value) != TYPE_INT or value < 0 or value > 65535:
		return null
	return value


static func bool_or_default(value: Variant, fallback: bool) -> bool:
	return value if typeof(value) == TYPE_BOOL else fallback


static func bool_or_null(value: Variant) -> Variant:
	return value if typeof(value) == TYPE_BOOL else null


static func string_or_empty(value: Variant) -> String:
	return value if typeof(value) == TYPE_STRING else ""


static func string_or_null(value: Variant) -> Variant:
	return value if typeof(value) == TYPE_STRING else null


func disconnect_device(id: int, at_usec: int) -> void:
	if not _active.has(id):
		return
	var device: Dictionary = devices[_active[id]]
	device.connected = false
	device.disconnected_at_usec = at_usec
	_active.erase(id)


func motion(id: int, axis: int, value: float, at_usec: int) -> void:
	if not _active.has(id) or axis < 0 or axis >= AXES or not is_finite(value) or absf(value) > 1.0:
		rejected_events += 1
		return
	var device: Dictionary = devices[_active[id]]
	var sample: Dictionary = device.axes[axis]
	if at_usec < int(device.connected_at_usec) or (sample.events > 0 and at_usec < int(sample.last_event_usec)):
		rejected_events += 1
		return
	if sample.events == 0:
		sample.min = value
		sample.max = value
		sample.first_event_usec = at_usec
	else:
		sample.min = minf(sample.min, value)
		sample.max = maxf(sample.max, value)
		if at_usec == sample.last_event_usec:
			sample.zero_spacing_events += 1
	sample.last_event_usec = at_usec
	sample.events += 1


func button_event(id: int, button_index: int, pressed: bool, at_usec: int) -> void:
	if not _active.has(id) or button_index < 0:
		rejected_events += 1
		return
	var device: Dictionary = devices[_active[id]]
	if at_usec < int(device.connected_at_usec) or at_usec < int(device._last_button_event_usec):
		rejected_events += 1
		return
	device._last_button_event_usec = at_usec
	device.button_events += 1
	if pressed:
		device.button_press_events += 1
	else:
		device.button_release_events += 1
	var slot: int = int(device._button_index_to_slot.get(button_index, -1))
	if slot < 0:
		if device.buttons.size() >= MAX_TRACKED_BUTTONS:
			device.untracked_button_events += 1
			if pressed:
				device.untracked_button_press_events += 1
			else:
				device.untracked_button_release_events += 1
			return
		var buttons: Array = device.buttons
		slot = buttons.size()
		device._button_index_to_slot[button_index] = slot
		device._button_states[button_index] = false
		buttons.append({button = button_index, events = 0, press_events = 0, release_events = 0,
			press_transitions = 0, release_transitions = 0, pressed = false})
	var button: Dictionary = device.buttons[slot]
	button.events += 1
	if pressed:
		button.press_events += 1
	else:
		button.release_events += 1
	var previous: bool = bool(device._button_states[button_index])
	if pressed == previous:
		return
	device._button_states[button_index] = pressed
	button.pressed = pressed
	if pressed:
		button.press_transitions += 1
	else:
		button.release_transitions += 1
	device.button_transition_count += 1
	if device.button_transitions.size() < MAX_RECORDED_BUTTON_TRANSITIONS:
		device.button_transitions.append({button = button_index, pressed = pressed, at_usec = at_usec})
	else:
		device.button_transitions_omitted += 1


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = devices.duplicate(true)
	for device: Dictionary in result:
		device.erase("_button_index_to_slot")
		device.erase("_button_states")
		device.erase("_last_button_event_usec")
		device.axes_seen = []
		device.axes_moved = []
		for axis: Dictionary in device.axes:
			axis.mean_event_spacing_usec = null
			if axis.events > 0:
				device.axes_seen.append(axis.axis)
				if axis.min != axis.max:
					device.axes_moved.append(axis.axis)
			if axis.events > 1:
				axis.mean_event_spacing_usec = float(axis.last_event_usec - axis.first_event_usec) / float(axis.events - 1)
	return result
