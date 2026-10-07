# F1: event statistics, separate from Input and the flight's calibrated controls.
extends RefCounted

const AXES: int = 10 # Pinned Godot JoyAxis.MAX; these are Godot axes, not a raw HID descriptor.
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
	var device: Dictionary = {session = devices.size(), device_id = id,
		guid = info.get("guid", ""), name = info.get("name", ""),
		raw_name = info.get("raw_name"), vendor_id = usb_id(info.get("vendor_id")), product_id = usb_id(info.get("product_id")),
		is_joy_known = info.get("known", false), connected_at_usec = at_usec,
		disconnected_at_usec = null, connected = true, axes = axes}
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


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = devices.duplicate(true)
	for device: Dictionary in result:
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
