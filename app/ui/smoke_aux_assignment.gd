# SM-04: small guided device-assignment panel. The caller pauses flight and persists `profile_ready`.
extends PanelContainer

signal profile_ready(profile: Dictionary)
signal cancelled

const AXES := 10
const MIN_CANDIDATE_MOVE := 0.25
const MIN_AXIS_SPAN := 0.5
const RETURN_TOLERANCE := 0.25
const SmokeAux := preload("res://input/smoke_aux.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var device_id: int = -1
var device_key: String = ""
var base_profile: Dictionary = {}
var stage: int = -1 # 0 OFF baseline, 1 ON capture, 2 return to OFF
var error: String = ""
var button_mode: String = "level"

var _profiles_path: String = "user://rc_calibration.cfg"
var _reserved_axes: Array = []
var _axis_values := PackedFloat64Array()
var _off_axes := PackedFloat64Array()
var _candidates: Dictionary = {}
var _chosen: Dictionary = {}
var _button_release_seen: bool = false
var _message: Label
var _detail: Label
var _mode_options: OptionButton


func _ready() -> void:
	theme = UiTheme.build()
	custom_minimum_size = Vector2(560, 220)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	_mode_options = OptionButton.new()
	_mode_options.add_item(tr("Button: pump while held"), 0)
	_mode_options.add_item(tr("Button: toggle on press"), 1)
	_mode_options.item_selected.connect(_mode_selected)
	column.add_child(_mode_options)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail)
	visible = false
	set_process(false)
	set_process_input(false)
	_refresh()


## Start for the active radio. Pass `radio.axes` as baseline when available; no AUX is inferred.
func begin(id: int, profile: Dictionary, key: String = "", profiles_path: String = "user://rc_calibration.cfg", baseline_axes: PackedFloat64Array = PackedFloat64Array()) -> void:
	device_id = id
	device_key = key
	_profiles_path = profiles_path
	base_profile = SmokeAux.sanitize_profile(profile)
	_reserved_axes = SmokeAux.flight_axes(base_profile)
	_axis_values = PackedFloat64Array()
	_axis_values.resize(AXES)
	for axis in AXES:
		_axis_values[axis] = baseline_axes[axis] if baseline_axes.size() == AXES else Input.get_joy_axis(device_id, axis)
	_off_axes = _axis_values.duplicate()
	_candidates.clear()
	_chosen.clear()
	_button_release_seen = false
	button_mode = "level"
	stage = 0
	error = ""
	visible = true
	set_process(true)
	set_process_input(true)
	_refresh()


## Set programmatically or through the selector. Applies only if a button is assigned.
func set_button_mode(mode: String) -> void:
	if mode not in ["level", "toggle_edge"]:
		return
	button_mode = mode
	if _mode_options != null:
		_mode_options.select(0 if mode == "level" else 1)


func sample_axis(id: int, axis: int, value: float) -> void:
	if not visible or id != device_id or axis < 0 or axis >= AXES or not is_finite(value):
		return
	_axis_values[axis] = clampf(value, -1.0, 1.0)
	if stage != 1 or _reserved_axes.has(axis):
		return
	var off_value: float = _off_axes[axis]
	var distance := absf(_axis_values[axis] - off_value)
	if distance < MIN_CANDIDATE_MOVE:
		return
	var key := "axis:%d" % axis
	var candidate: Dictionary = _candidates.get(key, { type = "axis", index = axis, off = off_value, on = _axis_values[axis] })
	if distance > absf(float(candidate.on) - float(candidate.off)):
		candidate.on = _axis_values[axis]
	_candidates[key] = candidate
	_refresh()


func sample_button(id: int, button: int, pressed: bool) -> void:
	if not visible or id != device_id or button < 0:
		return
	if stage == 1 and pressed:
		var key := "button:%d" % button
		_candidates[key] = { type = "button", index = button }
		_refresh()
	elif stage == 2 and _chosen.get("type", "") == "button" and button == int(_chosen.index) and not pressed:
		_button_release_seen = true


## Enter advances one instruction at a time. Returns true when the profile is ready.
func advance() -> bool:
	if stage < 0:
		return false
	error = ""
	if stage == 0:
		_off_axes = _axis_values.duplicate()
		_candidates.clear()
		stage = 1
		_refresh()
		return false
	if stage == 1:
		if _candidates.size() != 1:
			error = tr("Move exactly one unused control. Multiple controls are ambiguous; try again.")
			_candidates.clear()
			_refresh()
			return false
		_chosen = _candidates.values()[0].duplicate(true)
		if _chosen.type == "axis" and absf(float(_chosen.on) - float(_chosen.off)) < MIN_AXIS_SPAN:
			error = tr("The axis needs a larger OFF-to-ON sweep. Try again.")
			_candidates.clear()
			_refresh()
			return false
		_button_release_seen = false
		stage = 2
		_refresh()
		return false
	if stage == 2:
		var binding := _make_binding()
		if binding.is_empty():
			_refresh()
			return false
		var updated := base_profile.duplicate(true)
		var aux: Dictionary = updated.get("aux", {}).duplicate(true)
		aux.smoke = binding
		updated.aux = aux
		if not SmokeAux.valid_binding(updated.aux.smoke, _reserved_axes):
			error = tr("This assignment conflicts with the flight controls or has invalid endpoints.")
			_refresh()
			return false
		if not _calibration_profile_valid_for_save(updated):
			_refresh()
			return false
		profile_ready.emit(updated)
		stage = -1
		visible = false
		set_process(false)
		set_process_input(false)
		_refresh()
		return true
	return false


func cancel() -> void:
	if stage < 0:
		return
	stage = -1
	visible = false
	set_process(false)
	set_process_input(false)
	cancelled.emit()
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadMotion:
		sample_axis(event.device, event.axis, event.axis_value)
		if event.device == device_id:
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		sample_button(event.device, event.button_index, event.pressed)
		if event.device == device_id:
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			advance()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if device_id < 0:
		return
	for axis in AXES:
		sample_axis(device_id, axis, Input.get_joy_axis(device_id, axis))


func _make_binding() -> Dictionary:
	if _chosen.get("type", "") == "axis":
		var axis: int = int(_chosen.index)
		var off_value: float = _axis_values[axis]
		if absf(off_value - float(_off_axes[axis])) > RETURN_TOLERANCE:
			error = tr("The axis did not return to OFF. Return it to OFF and press Enter.")
			return {}
		var on_value: float = float(_chosen.on)
		if absf(on_value - off_value) < MIN_AXIS_SPAN:
			error = tr("The saved OFF and ON positions are too close. Repeat the assignment.")
			return {}
		return { type = "axis", axis = axis, off = off_value, on = on_value, invert = on_value < off_value }
	if _chosen.get("type", "") == "button":
		if not _button_release_seen:
			error = tr("Release the assigned button after entering this step, then press Enter.")
			return {}
		return { type = "button", button = int(_chosen.index), mode = button_mode }
	return {}


func _calibration_profile_valid_for_save(profile: Dictionary) -> bool:
	# The radio profile validator remains the authority for AETR; gamepads keep their built-in mapping.
	if profile.get("kind", "") == "radio":
		if not RcCalibration.valid(profile):
			error = tr("The current flight profile is invalid; the AUX assignment was not saved.")
			return false
	return true


func _mode_selected(index: int) -> void:
	button_mode = "level" if index == 0 else "toggle_edge"


func _refresh() -> void:
	if _message == null or _detail == null:
		return
	if stage == 0:
		_message.text = tr("Smoke pump assignment\nKeep the intended control OFF, then press Enter.")
	elif stage == 1:
		_message.text = tr("Turn the intended control ON\nMove or press exactly one unused control, then press Enter.")
	elif stage == 2:
		var control := tr("axis %d") % int(_chosen.index) if _chosen.get("type", "") == "axis" else tr("button %d") % int(_chosen.index)
		_message.text = tr("Return %s to OFF, then press Enter. For a button, release it after this step begins.") % control
	else:
		_message.text = tr("Smoke pump assignment closed.")
	if not error.is_empty():
		_detail.text = error
	elif stage == 1 and not _candidates.is_empty():
		_detail.text = tr("Detected live: %s. Use one control only; AETR axes are ignored.") % ", ".join(_candidates.keys())
	elif stage == 2:
		var selected := tr("axis %d") % int(_chosen.index) if _chosen.get("type", "") == "axis" else tr("button %d") % int(_chosen.index)
		_detail.text = tr("Selected: %s. Only events from the active device count.") % selected
	else:
		_detail.text = tr("Only the active device is read. AETR axes cannot be assigned. Esc cancels.")
	if _mode_options != null:
		_mode_options.visible = stage >= 0 and (_chosen.is_empty() or _chosen.get("type", "") == "button")
