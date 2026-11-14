# UI-15-UX-04: the selected device as a picture with live input. Three kinds:
# - "gamepad" (family xbox / playstation / nintendo / generic): a procedural controller silhouette with two analog
#   sticks, D-pad, four face buttons, shoulders, triggers with fill level, back/guide/menu. Face, shoulder, stick-press,
#   menu and back marks are the vendored CC0 Kenney SVGs resolved through ControllerPrompts; triggers have no glyph in
#   the subset and are drawn as labelled shapes.
# - "radio": a generic, unbranded transmitter with two StickGimbalViews (Mode 1/2 places the throttle) and a row of
#   switch lamps / pot knobs for observed controls.
# - "keyboard": a compact physical keyboard of KeyCaps (named in the player's layout through key_labels.gd) with the
#   flight keys from controls_reference.gd marked and pressed keys lit.
# Presentation only: it never reads profiles from storage, never captures input and never changes a binding.
# Control ids follow the binding they show: "button:<JoyButton>", "axis:<JoyAxis>" and "key:<physical Key>", so a
# caller can map a binding chip to `control_rect(id)` / `leader_anchor(id, toward)` 1:1.
# Drawing is vector in a fixed design space scaled to the control (crisp at 1080p, 1440p and 4K). Setters redraw only
# when a value changes beyond EPSILON; live updates allocate nothing.
extends Control

signal control_hovered(control_id: String)

const UiTheme := preload("res://ui/ui_theme.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const KeyLabels := preload("res://ui/key_labels.gd")
const ControlsReference := preload("res://ui/controls_reference.gd")
const GimbalView := preload("res://ui/controls/stick_gimbal_view.gd")

const KINDS: PackedStringArray = ["gamepad", "radio", "keyboard"]
const GAMEPAD_FAMILIES: PackedStringArray = ["xbox", "playstation", "nintendo", "generic"]
const EPSILON := 0.004
const AXIS_COUNT := 10
## Design space every layout is authored in; it is scaled uniformly and centred in the control.
const DESIGN := Vector2(620.0, 380.0)
## Trigger names per family; physical letters, never translated.
const TRIGGER_NAMES := {
	xbox = ["LT", "RT"], playstation = ["L2", "R2"], nintendo = ["ZL", "ZR"], generic = ["LT", "RT"],
}
## Fallback radio channel axes (ControllerProfile radio defaults) until the caller supplies the profile's channels.
const RADIO_DEFAULT_AXES := { roll = 0, pitch = 1, throttle = 2, yaw = 3 }
const FUNCTION_NAMES := { roll = "Roll", pitch = "Pitch", yaw = "Yaw", throttle = "Throttle" }
## Stick functions per mode as [[left x, left y], [right x, right y]]; the same table as calibration_view.gd
## gimbal_functions(), kept here so the picture does not load the calibration wizard.
const MODE_FUNCTIONS := {
	1: [["yaw", "pitch"], ["roll", "throttle"]],
	2: [["yaw", "throttle"], ["roll", "pitch"]],
}
const FACE_BUTTONS: PackedInt32Array = [JOY_BUTTON_Y, JOY_BUTTON_X, JOY_BUTTON_B, JOY_BUTTON_A]
const DPAD_BUTTONS: PackedInt32Array = [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
const SHOULDER_BUTTONS: PackedInt32Array = [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
const CENTRE_BUTTONS: PackedInt32Array = [JOY_BUTTON_BACK, JOY_BUTTON_START]
## Keyboard rows: [physical key, column, row, width] in key units.
const KEY_UNIT := 36.0
const KEY_GAP := 4.0

## The control the caller has emphasised ("" for none); also lit by `highlight()`.
var highlighted_id := ""
## Redraw requests since creation; tests use it to prove unchanged samples cost nothing.
var redraw_requests := 0
## Physical keycode → label keycode used to name keyboard caps (tests pass a fixed layout); see key_labels.gd.
var key_mapper := Callable()

var _kind := "gamepad"
var _family := "generic"
var _stick_mode := 2
var _vehicle_type := ControlsReference.AIRPLANE
var _axes := PackedFloat64Array()
var _pressed_mask := 0
var _pressed_keys := {}
var _hovered_id := ""
## control id → Rect2 in design units; rebuilt only when the device or layout changes.
var _rects := {}
var _order := PackedStringArray()
var _textures := {}
var _texts := {}
var _silhouette := PackedVector2Array()
var _scale := 1.0
var _origin := Vector2.ZERO
var _layout_bounds := Rect2(Vector2.ZERO, DESIGN)
# Radio
var _radio_channels := {}
var _lamps: Array[Dictionary] = []
var _left_gimbal: GimbalView
var _right_gimbal: GimbalView
var _gimbal_functions: Array = []
var _captions := PackedStringArray(["", ""])
# Keyboard
var _caps := {}
var _flight_keys := {}
var _shortcut_keys := {}
var _legend: Array = []
var _cap_styles := {}
var _cap_font_size := 0
# Reused drawing state (never allocated while drawing).
var _fill_style := StyleBoxFlat.new()
var _line_style := StyleBoxFlat.new()
## "button:N" / "axis:N" ids built once, so drawing formats no strings.
var _button_ids := PackedStringArray()
var _axis_ids := PackedStringArray()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(400.0, 245.0)
	clip_contents = false
	_axes.resize(AXIS_COUNT)
	_axes.fill(0.0)
	_line_style.draw_center = false
	for index in 64:
		_button_ids.append("button:%d" % index)
	for index in AXIS_COUNT:
		_axis_ids.append("axis:%d" % index)
	for state in ["normal", "unused", "flight", "pressed", "highlight"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(5)
		style.set_border_width_all(1)
		style.border_width_bottom = 3
		style.set_content_margin_all(1.0)
		_cap_styles[state] = style
	_style_caps()
	set_device("gamepad", "generic")


# --- Public API -------------------------------------------------------------------------------------------------

## Select what is drawn: kind "gamepad" (family xbox / playstation / nintendo / generic or "auto" → generic),
## "radio" or "keyboard". Rebuilds the layout only when the kind or family changes.
func set_device(kind: String, family: String = "generic") -> void:
	# A raw joystick is drawn as the generic transmitter (two gimbals and a control row).
	var next_kind := "radio" if kind == "joystick" else (kind if kind in KINDS else "gamepad")
	var next_family := family.strip_edges().to_lower()
	if next_kind != "gamepad":
		next_family = ""
	elif not next_family in GAMEPAD_FAMILIES:
		next_family = "generic"
	if next_kind == _kind and next_family == _family and not _rects.is_empty():
		return
	_kind = next_kind
	_family = next_family
	_rebuild()


func device_kind() -> String:
	return _kind


func device_family() -> String:
	return _family


## Mode 1 or 2: which stick carries the throttle. Presentation only; it never changes a profile.
func set_stick_mode(mode: int) -> void:
	var next := 1 if mode == 1 else 2
	if next != _stick_mode:
		_stick_mode = next
		if _kind != "keyboard":
			_rebuild()


func stick_mode() -> int:
	return _stick_mode


## Which side of the picture carries the throttle stick ("left" in Mode 2, "right" in Mode 1).
func throttle_side() -> String:
	return "right" if _stick_mode == 1 else "left"


## Keyboard map: the vehicle whose flight keys are marked (ControlsReference.AIRPLANE or ROTORCRAFT).
func set_vehicle_type(vehicle_type: String) -> void:
	var next := ControlsReference.ROTORCRAFT if vehicle_type == ControlsReference.ROTORCRAFT else ControlsReference.AIRPLANE
	if next != _vehicle_type:
		_vehicle_type = next
		if _kind == "keyboard":
			_rebuild()


## Radio: the profile's channel dictionaries ({roll, pitch, yaw, throttle} → {axis, invert, min, center, max,
## range_kind}) or plain axis indices. Used only to place live values and control ids on the gimbals.
func set_radio_channels(channels: Dictionary) -> void:
	var next := {}
	for function: String in RADIO_DEFAULT_AXES:
		var value: Variant = channels.get(function, RADIO_DEFAULT_AXES[function])
		if value is Dictionary:
			next[function] = value
		elif value is int or value is float:
			next[function] = {"axis": int(value)}
	if next != _radio_channels:
		_radio_channels = next
		if _kind == "radio":
			_rebuild()


## Radio switch row: up to eight entries, each {"button": int, "label": "Sa"} (a lamp) or
## {"axis": int, "label": "S1"} (a pot knob). Labels are physical names and are drawn as given.
func set_radio_controls(entries: Array) -> void:
	var next: Array[Dictionary] = []
	for entry: Variant in entries:
		if entry is Dictionary and next.size() < 8 and (entry.has("button") or entry.has("axis")):
			next.append(entry)
	if next != _lamps:
		_lamps = next
		if _kind == "radio":
			_rebuild()


## Live axes indexed by Godot JoyAxis (−1 … +1; triggers 0 … 1). Redraws only on a visible change.
func set_axes(values: PackedFloat64Array) -> void:
	var changed := false
	for axis in mini(values.size(), AXIS_COUNT):
		var value := values[axis] if is_finite(values[axis]) else 0.0
		if absf(value - _axes[axis]) > EPSILON:
			_axes[axis] = value
			changed = true
	if not changed:
		return
	if _kind == "radio":
		_update_gimbals()
		if _has_knobs():
			_request_redraw()
	elif _kind == "gamepad":
		_request_redraw()


func axis_value(axis: int) -> float:
	return _axes[axis] if axis >= 0 and axis < AXIS_COUNT else 0.0


## Pressed Godot JoyButton indices (any Array or PackedInt32Array of ints, buttons 0 … 62).
func set_pressed_buttons(indices: Variant) -> void:
	var mask := 0
	if indices is Array or indices is PackedInt32Array or indices is PackedInt64Array:
		for index: Variant in indices:
			var button := int(index)
			if button >= 0 and button < 63:
				mask |= 1 << button
	if mask != _pressed_mask:
		_pressed_mask = mask
		if _kind != "keyboard":
			_request_redraw()


func is_button_pressed(button: int) -> bool:
	return button >= 0 and button < 63 and (_pressed_mask >> button) & 1 == 1


## Keyboard: the physical keycodes currently held. Only changed caps are restyled.
func set_pressed_keys(keys: Variant) -> void:
	if not (keys is Array or keys is PackedInt32Array or keys is PackedInt64Array):
		return
	var same: bool = keys.size() == _pressed_keys.size()
	if same:
		for key: Variant in keys:
			if not _pressed_keys.has(int(key)):
				same = false
				break
	if same:
		return
	var previous := _pressed_keys
	_pressed_keys = {}
	for key: Variant in keys:
		_pressed_keys[int(key)] = true
	for key: Variant in previous:
		_restyle_cap(int(key))
	for key: Variant in _pressed_keys:
		_restyle_cap(int(key))


func is_key_pressed(physical: int) -> bool:
	return _pressed_keys.has(physical)


## Emphasise one control (an action row is focused); "" clears. Unknown ids clear too.
func highlight(control_id: String) -> void:
	var next := control_id if _rects.has(control_id) else ""
	if next == highlighted_id:
		return
	var previous := highlighted_id
	highlighted_id = next
	if _kind == "keyboard":
		_restyle_cap(_key_of(previous))
		_restyle_cap(_key_of(next))
	_request_redraw()


func has_control(control_id: String) -> bool:
	return _rects.has(control_id)


## Every control id the current picture can show, in drawing order.
func control_ids() -> PackedStringArray:
	return _order


## The control's rectangle in this Control's local pixels (Rect2() for an unknown id). Stable for a given
## kind/family/mode and size.
func control_rect(control_id: String) -> Rect2:
	if not _rects.has(control_id):
		return Rect2()
	var rect: Rect2 = _rects[control_id]
	return Rect2(_origin + rect.position * _scale, rect.size * _scale)


## Where a leader line from `toward` (local pixels, e.g. a binding chip's edge) meets the control's outline:
## the middle of the rectangle side facing `toward`. Without `toward`, the side facing the nearer picture edge.
func leader_anchor(control_id: String, toward: Vector2 = Vector2(INF, INF)) -> Vector2:
	var rect := control_rect(control_id)
	if rect.size == Vector2.ZERO:
		return Vector2(INF, INF)
	var centre := rect.get_center()
	var target := toward
	if not target.is_finite():
		target = Vector2(-1.0 if centre.x < size.x * 0.5 else size.x + 1.0, centre.y)
	var delta := target - centre
	if absf(delta.x) * rect.size.y >= absf(delta.y) * rect.size.x:
		return Vector2(rect.end.x if delta.x > 0.0 else rect.position.x, centre.y)
	return Vector2(centre.x, rect.end.y if delta.y > 0.0 else rect.position.y)


## The preferred side for this control's leader line: SIDE_LEFT for the left half of the picture, else SIDE_RIGHT.
func leader_side(control_id: String) -> Side:
	var rect := control_rect(control_id)
	return SIDE_LEFT if rect.get_center().x < size.x * 0.5 else SIDE_RIGHT


## The control under a local pixel position, or "".
func control_at(point: Vector2) -> String:
	var design := (point - _origin) / maxf(_scale, 0.0001)
	for index in range(_order.size() - 1, -1, -1):
		var id := _order[index]
		var rect: Rect2 = _rects[id]
		if rect.grow(2.0).has_point(design):
			return id
	return ""


## Current design → pixel scale (tests and callers sizing chips next to the picture).
func picture_scale() -> float:
	return _scale


# --- Layout -----------------------------------------------------------------------------------------------------

func _rebuild() -> void:
	_rects.clear()
	_order = PackedStringArray()
	_textures.clear()
	_texts.clear()
	_silhouette = PackedVector2Array()
	_legend.clear()
	for child in get_children():
		if child == _left_gimbal or child == _right_gimbal or _caps.values().has(child):
			remove_child(child)
			child.queue_free()
	_left_gimbal = null
	_right_gimbal = null
	_caps.clear()
	match _kind:
		"gamepad":
			_layout_gamepad()
		"radio":
			_layout_radio()
		"keyboard":
			_layout_keyboard()
	if not _rects.has(highlighted_id):
		highlighted_id = ""
	_refresh_texts()
	accessibility_name = _accessible_summary()
	_fit()
	_request_redraw()


func _add(control_id: String, rect: Rect2) -> void:
	if not _rects.has(control_id):
		_order.append(control_id)
	_rects[control_id] = rect


func _layout_gamepad() -> void:
	_layout_bounds = Rect2(Vector2.ZERO, DESIGN)
	var ps := _family == "playstation"
	var left_stick := Vector2(250.0, 250.0) if ps else Vector2(190.0, 165.0)
	var right_stick := Vector2(370.0, 250.0)
	var dpad := Vector2(190.0, 165.0) if ps else Vector2(250.0, 248.0)
	var face := Vector2(436.0, 165.0)
	var stick_radius := 36.0 if ps else 38.0
	_add("axis:%d" % JOY_AXIS_TRIGGER_LEFT, Rect2(128.0, 8.0, 84.0, 38.0))
	_add("axis:%d" % JOY_AXIS_TRIGGER_RIGHT, Rect2(408.0, 8.0, 84.0, 38.0))
	_add("button:%d" % JOY_BUTTON_LEFT_SHOULDER, Rect2(116.0, 52.0, 108.0, 30.0))
	_add("button:%d" % JOY_BUTTON_RIGHT_SHOULDER, Rect2(396.0, 52.0, 108.0, 30.0))
	var left_rect := Rect2(left_stick - Vector2.ONE * stick_radius, Vector2.ONE * stick_radius * 2.0)
	var right_rect := Rect2(right_stick - Vector2.ONE * stick_radius, Vector2.ONE * stick_radius * 2.0)
	_add("axis:%d" % JOY_AXIS_LEFT_X, left_rect)
	_add("axis:%d" % JOY_AXIS_LEFT_Y, left_rect)
	_add("axis:%d" % JOY_AXIS_RIGHT_X, right_rect)
	_add("axis:%d" % JOY_AXIS_RIGHT_Y, right_rect)
	_add("button:%d" % JOY_BUTTON_LEFT_STICK, left_rect.grow(-stick_radius * 0.35))
	_add("button:%d" % JOY_BUTTON_RIGHT_STICK, right_rect.grow(-stick_radius * 0.35))
	var arm := 31.0
	var half := 11.0
	_add("button:%d" % JOY_BUTTON_DPAD_UP, Rect2(dpad + Vector2(-half, -arm), Vector2(half * 2.0, arm - half)))
	_add("button:%d" % JOY_BUTTON_DPAD_DOWN, Rect2(dpad + Vector2(-half, half), Vector2(half * 2.0, arm - half)))
	_add("button:%d" % JOY_BUTTON_DPAD_LEFT, Rect2(dpad + Vector2(-arm, -half), Vector2(arm - half, half * 2.0)))
	_add("button:%d" % JOY_BUTTON_DPAD_RIGHT, Rect2(dpad + Vector2(half, -half), Vector2(arm - half, half * 2.0)))
	var spread := 38.0
	var face_radius := 18.0
	for entry: Array in [[JOY_BUTTON_Y, Vector2(0, -spread)], [JOY_BUTTON_X, Vector2(-spread, 0)],
			[JOY_BUTTON_B, Vector2(spread, 0)], [JOY_BUTTON_A, Vector2(0, spread)]]:
		var centre: Vector2 = face + entry[1]
		_add("button:%d" % int(entry[0]), Rect2(centre - Vector2.ONE * face_radius, Vector2.ONE * face_radius * 2.0))
	var small := 12.0
	var back := Vector2(240.0, 112.0) if ps else Vector2(266.0, 150.0)
	var menu := Vector2(380.0, 112.0) if ps else Vector2(354.0, 150.0)
	var guide := Vector2(310.0, 196.0) if ps else Vector2(310.0, 118.0)
	_add("button:%d" % JOY_BUTTON_BACK, Rect2(back - Vector2.ONE * small, Vector2.ONE * small * 2.0))
	_add("button:%d" % JOY_BUTTON_START, Rect2(menu - Vector2.ONE * small, Vector2.ONE * small * 2.0))
	_add("button:%d" % JOY_BUTTON_GUIDE, Rect2(guide - Vector2.ONE * 14.0, Vector2.ONE * 28.0))
	_silhouette = _smooth_closed([
		Vector2(205, 88), Vector2(310, 95), Vector2(415, 88), Vector2(470, 98), Vector2(507, 130), Vector2(530, 182),
		Vector2(550, 252), Vector2(562, 312), Vector2(549, 348), Vector2(514, 357), Vector2(481, 338),
		Vector2(450, 300), Vector2(418, 282), Vector2(310, 276), Vector2(202, 282), Vector2(170, 300),
		Vector2(139, 338), Vector2(106, 357), Vector2(71, 348), Vector2(58, 312), Vector2(70, 252), Vector2(90, 182),
		Vector2(113, 130), Vector2(150, 98),
	])
	for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_BACK, JOY_BUTTON_START,
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
		var prompt := ControllerPrompts.prompt({"type": "button", "button": button}, _family, {})
		var path := str(prompt.get("texture_path", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			_textures[button] = load(path) as Texture2D


func _layout_radio() -> void:
	_layout_bounds = Rect2(Vector2.ZERO, DESIGN)
	_gimbal_functions = MODE_FUNCTIONS[_stick_mode]
	var boxes := [Rect2(118.0, 146.0, 166.0, 166.0), Rect2(336.0, 146.0, 166.0, 166.0)]
	for side in 2:
		for function: String in _gimbal_functions[side]:
			_add("axis:%d" % _radio_axis(function), boxes[side])
	var count := _lamps.size()
	if count > 0:
		var pitch := minf(52.0, 380.0 / float(count))
		var start := 310.0 - pitch * float(count) * 0.5
		for index in count:
			var entry := _lamps[index]
			var centre := Vector2(start + pitch * (float(index) + 0.5), 100.0)
			var id := "button:%d" % int(entry.button) if entry.has("button") else "axis:%d" % int(entry.axis)
			var extent := Vector2(17.0, 15.0) if entry.has("button") else Vector2(15.0, 15.0)
			_add(id, Rect2(centre - extent, extent * 2.0))
	for side in 2:
		var gimbal := GimbalView.new()
		gimbal.name = "LeftGimbal" if side == 0 else "RightGimbal"
		gimbal.one_ended_y = _gimbal_functions[side][1] == "throttle"
		add_child(gimbal)
		if side == 0:
			_left_gimbal = gimbal
		else:
			_right_gimbal = gimbal
	_update_gimbals()


func _layout_keyboard() -> void:
	var rows: Array = []
	rows.append([KEY_ESCAPE, 0.0, 0.0, 1.0])
	for index in 12:
		rows.append([KEY_F1 + index, 1.25 + float(index) + 0.25 * floorf(index / 4.0), 0.0, 1.0])
	var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
	for index in digits.size():
		rows.append([digits[index], float(index), 1.25, 1.0])
	rows.append([KEY_BACKSPACE, 12.0, 1.25, 1.75])
	var top := [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P, KEY_BRACKETLEFT, KEY_BRACKETRIGHT]
	for index in top.size():
		rows.append([top[index], 0.5 + float(index), 2.25, 1.0])
	var home := [KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L]
	for index in home.size():
		rows.append([home[index], 0.75 + float(index), 3.25, 1.0])
	var bottom := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_COMMA, KEY_PERIOD]
	for index in bottom.size():
		rows.append([bottom[index], 1.25 + float(index), 4.25, 1.0])
	rows.append([KEY_SPACE, 3.25, 5.25, 6.0])
	rows.append([KEY_PAGEUP, 16.25, 1.25, 1.25])
	rows.append([KEY_PAGEDOWN, 16.25, 2.25, 1.25])
	rows.append([KEY_UP, 15.5, 4.25, 1.0])
	rows.append([KEY_LEFT, 14.5, 5.25, 1.0])
	rows.append([KEY_DOWN, 15.5, 5.25, 1.0])
	rows.append([KEY_RIGHT, 16.5, 5.25, 1.0])
	_flight_keys.clear()
	_shortcut_keys.clear()
	for row: Array in ControlsReference.flight_table(_vehicle_type):
		for key: Variant in row[0]:
			_flight_keys[int(key)] = true
	for row: Array in ControlsReference.shortcut_table(_vehicle_type):
		for key: Variant in row[0]:
			_shortcut_keys[int(key)] = true
	var right_edge := 0.0
	for entry: Array in rows:
		var key := int(entry[0])
		var rect := Rect2(float(entry[1]) * KEY_UNIT, float(entry[2]) * KEY_UNIT,
			float(entry[3]) * KEY_UNIT - KEY_GAP, KEY_UNIT - KEY_GAP)
		right_edge = maxf(right_edge, rect.end.x)
		_add("key:%d" % key, rect)
		var cap := KeyCap.for_key(key as Key, key_mapper)
		cap.name = "Key%d" % key
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.custom_minimum_size = Vector2.ZERO
		if cap.get_child_count() > 0 and cap.get_child(0) is Label:
			var label := cap.get_child(0) as Label
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(cap)
		_caps[key] = cap
	# Legend: one entry per flight row, drawn under the keys.
	var legend_y := 6.25 * KEY_UNIT + 14.0
	for row: Array in ControlsReference.flight_table(_vehicle_type):
		_legend.append([row[0], str(row[1])])
	_layout_bounds = Rect2(0.0, 0.0, right_edge, legend_y + 30.0)
	for key: Variant in _caps:
		_restyle_cap(int(key))


func _radio_axis(function: String) -> int:
	var channel: Variant = _radio_channels.get(function)
	if channel is Dictionary and channel.has("axis"):
		return int(channel.axis)
	return int(RADIO_DEFAULT_AXES[function])


func _has_knobs() -> bool:
	for entry in _lamps:
		if entry.has("axis"):
			return true
	return false


## Normalised gimbal value for one radio function through the profile's own public mapping.
func _radio_value(function: String) -> float:
	var axis := _radio_axis(function)
	var raw := axis_value(axis)
	var channel: Variant = _radio_channels.get(function)
	if channel is Dictionary and channel.has("min") and channel.has("max"):
		if function == "throttle":
			return GimbalView.throttle_to_y(ControllerProfile.normalize_absolute(raw, channel))
		return ControllerProfile.normalize_axis(raw, channel)
	if channel is Dictionary and bool(channel.get("invert", false)):
		return -raw
	return raw


func _update_gimbals() -> void:
	if _left_gimbal == null or _right_gimbal == null:
		return
	for side in 2:
		var gimbal := _left_gimbal if side == 0 else _right_gimbal
		var functions: Array = _gimbal_functions[side]
		gimbal.set_stick(Vector2(_radio_value(functions[0]), _radio_value(functions[1])), true)


## Catmull-Rom → Bézier handles through `points`, tessellated once per layout.
static func _smooth_closed(points: Array) -> PackedVector2Array:
	var curve := Curve2D.new()
	var count := points.size()
	for index in count + 1:
		var point: Vector2 = points[index % count]
		var previous: Vector2 = points[(index - 1 + count) % count]
		var following: Vector2 = points[(index + 1) % count]
		var handle := (following - previous) * 0.18
		curve.add_point(point, -handle, handle)
	var polygon := curve.tessellate(5, 3.0)
	if polygon.size() > 1 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
		polygon.remove_at(polygon.size() - 1)
	return polygon


func _fit() -> void:
	var bounds := _layout_bounds
	var available := size
	if available.x <= 1.0 or available.y <= 1.0 or bounds.size.x <= 0.0:
		_scale = 1.0
		_origin = -bounds.position
	else:
		_scale = minf(available.x / bounds.size.x, available.y / bounds.size.y)
		_origin = (available - bounds.size * _scale) * 0.5 - bounds.position * _scale
	_place_children()


func _place_children() -> void:
	if _kind == "radio" and _left_gimbal != null:
		for side in 2:
			var gimbal := _left_gimbal if side == 0 else _right_gimbal
			var functions: Array = _gimbal_functions[side]
			var rect := control_rect("axis:%d" % _radio_axis(functions[0]))
			gimbal.side = rect.size.x
			gimbal.position = rect.position
			gimbal.size = rect.size
	elif _kind == "keyboard":
		var font_size := maxi(11, roundi(15.0 * _scale))
		for key: Variant in _caps:
			var cap: Control = _caps[key]
			var rect := control_rect("key:%d" % int(key))
			cap.position = rect.position
			cap.size = rect.size
			if cap.get_child_count() > 0 and cap.get_child(0) is Label and font_size != _cap_font_size:
				var label := cap.get_child(0) as Label
				var named := int(key) in [KEY_ESCAPE, KEY_BACKSPACE, KEY_PAGEUP, KEY_PAGEDOWN, KEY_SPACE] \
					or (int(key) >= KEY_F1 and int(key) <= KEY_F12)
				label.add_theme_font_size_override("font_size", maxi(9, roundi(font_size * (0.72 if named else 1.0))))
		_cap_font_size = font_size


func _style_caps() -> void:
	var normal: StyleBoxFlat = _cap_styles.normal
	normal.bg_color = UiTheme.KEYCAP.bg
	normal.border_color = UiTheme.KEYCAP.edge
	var unused: StyleBoxFlat = _cap_styles.unused
	unused.bg_color = Color(UiTheme.KEYCAP.bg, 0.55)
	unused.border_color = Color(UiTheme.KEYCAP.edge, 0.45)
	var flight: StyleBoxFlat = _cap_styles.flight
	flight.bg_color = UiTheme.KEYCAP.bg.lerp(UiTheme.FOCUS, 0.12)
	flight.border_color = Color(UiTheme.FOCUS, 0.8)
	var pressed: StyleBoxFlat = _cap_styles.pressed
	pressed.bg_color = UiTheme.FOCUS
	pressed.border_color = UiTheme.CRYSTAL
	var lit: StyleBoxFlat = _cap_styles.highlight
	lit.bg_color = UiTheme.KEYCAP.bg.lerp(UiTheme.CRYSTAL, 0.18)
	lit.border_color = UiTheme.CRYSTAL
	lit.set_border_width_all(2)
	lit.border_width_bottom = 3


## The cap's look: pressed > highlighted > flight key > shortcut key > unused.
func cap_state(physical: int) -> String:
	if not _caps.has(physical):
		return ""
	if _pressed_keys.has(physical):
		return "pressed"
	if highlighted_id == "key:%d" % physical:
		return "highlight"
	if _flight_keys.has(physical):
		return "flight"
	if _shortcut_keys.has(physical):
		return "normal"
	return "unused"


func _restyle_cap(physical: int) -> void:
	if not _caps.has(physical):
		return
	var cap: Control = _caps[physical]
	var state := cap_state(physical)
	cap.add_theme_stylebox_override("panel", _cap_styles[state])
	var ink := UiTheme.ACCENT_INK if state == "pressed" else (UiTheme.DISABLED_TEXT if state == "unused" else UiTheme.TEXT)
	if cap.get_child_count() > 0:
		var child := cap.get_child(0)
		# Arrow caps draw their own triangle in the KeyLabel colour; it stays readable on every cap state.
		if child is Label:
			(child as Label).add_theme_color_override("font_color", ink)


func _key_of(control_id: String) -> int:
	return int(control_id.substr(4)) if control_id.begins_with("key:") else -1


func _refresh_texts() -> void:
	_texts.clear()
	if _kind == "radio":
		for side in 2:
			var functions: Array = _gimbal_functions[side]
			_captions[side] = "%s · %s" % [tr(FUNCTION_NAMES[functions[1]]), tr(FUNCTION_NAMES[functions[0]])]
		_texts["mode"] = tr("Mode %d") % _stick_mode
	elif _kind == "gamepad":
		var names: Array = TRIGGER_NAMES.get(_family, TRIGGER_NAMES.generic)
		_texts["axis:%d" % JOY_AXIS_TRIGGER_LEFT] = names[0]
		_texts["axis:%d" % JOY_AXIS_TRIGGER_RIGHT] = names[1]
		var functions: Array = MODE_FUNCTIONS[_stick_mode]
		for side in 2:
			_captions[side] = "%s · %s" % [tr(FUNCTION_NAMES[functions[side][1]]), tr(FUNCTION_NAMES[functions[side][0]])]
	else:
		_texts["flight"] = tr("Flight keys")
		_texts["pressed"] = tr("Pressed")
		for entry: Array in _legend:
			entry.resize(3)
			var names := PackedStringArray()
			for key: Variant in entry[0]:
				if not int(key) in KeyCap.ARROW_KEYS:
					names.append(KeyLabels.label(int(key) as Key, key_mapper))
			entry[2] = tr(entry[1])
			if not names.is_empty():
				entry[2] = "%s %s" % [" ".join(names), entry[2]]


func _accessible_summary() -> String:
	match _kind:
		"radio":
			return tr("Radio transmitter picture")
		"keyboard":
			return tr("Keyboard picture")
	return tr("Gamepad picture")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_fit()
			queue_redraw()
		NOTIFICATION_THEME_CHANGED:
			_cap_font_size = 0
			_fit()
			queue_redraw()
		NOTIFICATION_TRANSLATION_CHANGED:
			if not _rects.is_empty():
				_refresh_texts()
				accessibility_name = _accessible_summary()
				queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := control_at((event as InputEventMouseMotion).position)
		if id != _hovered_id:
			_hovered_id = id
			control_hovered.emit(id)


func _bid(button: int) -> String:
	return _button_ids[button] if button >= 0 and button < _button_ids.size() else "button:%d" % button


func _aid(axis: int) -> String:
	return _axis_ids[axis] if axis >= 0 and axis < _axis_ids.size() else "axis:%d" % axis


func _request_redraw() -> void:
	redraw_requests += 1
	queue_redraw()


# --- Drawing ----------------------------------------------------------------------------------------------------

func _draw() -> void:
	match _kind:
		"gamepad":
			_draw_gamepad()
		"radio":
			_draw_radio()
		"keyboard":
			_draw_keyboard()


func _design() -> void:
	draw_set_transform(_origin, 0.0, Vector2(_scale, _scale))


func _pixels() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _font() -> Font:
	return get_theme_font("font", "Label")


func _font_px(design_size: float) -> int:
	return maxi(11, roundi(design_size * _scale))


## Text centred on a design-space point, drawn in pixel space so glyphs stay sharp.
func _text_at(design_point: Vector2, text: String, design_size: float, color: Color) -> void:
	_pixels()
	var font := _font()
	var font_size := _font_px(design_size)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var point := _origin + design_point * _scale
	var baseline := point.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(point.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	_design()


func _rounded(rect: Rect2, color: Color, radius: float, filled: bool, width: float = 1.0) -> void:
	var style := _fill_style if filled else _line_style
	style.set_corner_radius_all(maxi(0, int(radius)))
	style.anti_aliasing = true
	if filled:
		style.bg_color = color
	else:
		style.border_color = color
		style.set_border_width_all(maxi(1, int(round(width))))
	draw_style_box(style, rect)


func _state_color(control_id: String, pressed: bool) -> Color:
	if pressed:
		return UiTheme.FOCUS
	if control_id == highlighted_id:
		return UiTheme.CRYSTAL
	return UiTheme.TEXT_2


func _halo(rect: Rect2, circle: bool) -> void:
	var glow := Color(UiTheme.FOCUS, 0.22)
	if circle:
		var centre := rect.get_center()
		var radius := maxf(rect.size.x, rect.size.y) * 0.5
		draw_circle(centre, radius + 9.0, glow, true, -1.0, true)
		draw_circle(centre, radius + 6.0, UiTheme.CRYSTAL, false, 2.0, true)
	else:
		_rounded(rect.grow(7.0), glow, 10.0, true)
		_rounded(rect.grow(5.0), UiTheme.CRYSTAL, 8.0, false, 2.0)


func _is_lit(control_id: String) -> bool:
	return control_id == highlighted_id


func _draw_gamepad() -> void:
	_design()
	var body := Color("#252825")
	var well := Color("#141614")
	# Triggers sit behind the body's top edge, then the bumpers.
	for side in 2:
		var axis := JOY_AXIS_TRIGGER_LEFT if side == 0 else JOY_AXIS_TRIGGER_RIGHT
		var id := _aid(axis)
		var rect: Rect2 = _rects[id]
		if _is_lit(id):
			_halo(rect, false)
		var amount := clampf(_axes[axis], 0.0, 1.0)
		_rounded(rect, Color("#1C1E1C"), 12.0, true)
		if amount > 0.01:
			var fill := Rect2(rect.position + Vector2(3.0, rect.size.y - 3.0 - (rect.size.y - 6.0) * amount),
				Vector2(rect.size.x - 6.0, (rect.size.y - 6.0) * amount))
			_rounded(fill, Color(UiTheme.FOCUS, 0.8), 9.0, true)
		_rounded(rect, UiTheme.CRYSTAL if _is_lit(id) else (UiTheme.FOCUS if amount > 0.01 else UiTheme.EDGE), 12.0, false, 1.5)
		var ink := UiTheme.ACCENT_INK if amount > 0.55 else (UiTheme.CRYSTAL if _is_lit(id) else UiTheme.TEXT)
		_text_at(rect.get_center() + Vector2(0.0, -2.0), str(_texts.get(id, "")), 15.0, ink)
	for button in SHOULDER_BUTTONS:
		var id := _bid(button)
		var rect: Rect2 = _rects[id]
		var pressed := is_button_pressed(button)
		if _is_lit(id):
			_halo(rect, false)
		_rounded(rect, Color("#1F221F") if not pressed else UiTheme.FOCUS.darkened(0.55), 13.0, true)
		_rounded(rect, UiTheme.FOCUS if pressed else (UiTheme.CRYSTAL if _is_lit(id) else UiTheme.EDGE), 13.0, false, 1.5)
		_glyph(button, rect.get_center(), 34.0, _state_color(id, pressed))
	# Body: soft shadow, fill, rim and an inner highlight.
	if _silhouette.size() >= 3:
		draw_set_transform(_origin + Vector2(0.0, 6.0 * _scale), 0.0, Vector2(_scale, _scale))
		draw_colored_polygon(_silhouette, Color(0, 0, 0, 0.35))
		_design()
		draw_colored_polygon(_silhouette, body)
		draw_polyline(_silhouette, UiTheme.EDGE, 2.0, true)
		draw_line(_silhouette[_silhouette.size() - 1], _silhouette[0], UiTheme.EDGE, 2.0, true)
	if _family == "playstation":
		var pad := Rect2(258.0, 92.0, 104.0, 66.0)
		_rounded(pad, Color("#1C1F1C"), 10.0, true)
		_rounded(pad, Color(UiTheme.EDGE, 0.7), 10.0, false, 1.0)
	# D-pad.
	var up: Rect2 = _rects[_bid(JOY_BUTTON_DPAD_UP)]
	var down: Rect2 = _rects[_bid(JOY_BUTTON_DPAD_DOWN)]
	var left: Rect2 = _rects[_bid(JOY_BUTTON_DPAD_LEFT)]
	var right: Rect2 = _rects[_bid(JOY_BUTTON_DPAD_RIGHT)]
	var dpad_centre := Vector2(up.get_center().x, left.get_center().y)
	draw_circle(dpad_centre, 40.0, well, true, -1.0, true)
	var vertical := Rect2(up.position, Vector2(up.size.x, down.end.y - up.position.y))
	var horizontal := Rect2(left.position, Vector2(right.end.x - left.position.x, left.size.y))
	for button in DPAD_BUTTONS:
		if _is_lit(_bid(button)):
			_halo(_rects[_bid(button)], false)
	_rounded(vertical, Color("#343834"), 4.0, true)
	_rounded(horizontal, Color("#343834"), 4.0, true)
	for button in DPAD_BUTTONS:
		var id := _bid(button)
		var arm: Rect2 = _rects[id]
		var pressed := is_button_pressed(button)
		if pressed or _is_lit(id):
			_rounded(arm, UiTheme.FOCUS if pressed else Color(UiTheme.CRYSTAL, 0.55), 4.0, true)
		_dpad_arrow(arm, button, UiTheme.ACCENT_INK if pressed else _state_color(id, false))
	# Sticks.
	_stick(JOY_AXIS_LEFT_X, JOY_BUTTON_LEFT_STICK, well)
	_stick(JOY_AXIS_RIGHT_X, JOY_BUTTON_RIGHT_STICK, well)
	# Face, back, guide, menu.
	for button in FACE_BUTTONS:
		var id := _bid(button)
		var rect: Rect2 = _rects[id]
		var pressed := is_button_pressed(button)
		if _is_lit(id):
			_halo(rect, true)
		draw_circle(rect.get_center(), rect.size.x * 0.5 + 3.0, well, true, -1.0, true)
		if pressed:
			draw_circle(rect.get_center(), rect.size.x * 0.5 + 3.0, Color(UiTheme.FOCUS, 0.35), true, -1.0, true)
		_glyph(button, rect.get_center(), rect.size.x / 0.75, _state_color(id, pressed))
	for button in CENTRE_BUTTONS:
		var id := _bid(button)
		var rect: Rect2 = _rects[id]
		var pressed := is_button_pressed(button)
		if _is_lit(id):
			_halo(rect, true)
		_glyph(button, rect.get_center(), rect.size.x * 1.45, _state_color(id, pressed))
	var guide_id := _bid(JOY_BUTTON_GUIDE)
	var guide: Rect2 = _rects[guide_id]
	if _is_lit(guide_id):
		_halo(guide, true)
	var guide_pressed := is_button_pressed(JOY_BUTTON_GUIDE)
	draw_circle(guide.get_center(), guide.size.x * 0.5, UiTheme.FOCUS if guide_pressed else Color("#303430"), true, -1.0, true)
	draw_circle(guide.get_center(), guide.size.x * 0.5, _state_color(guide_id, guide_pressed), false, 1.5, true)
	draw_circle(guide.get_center(), guide.size.x * 0.18, _state_color(guide_id, guide_pressed), true, -1.0, true)
	# Stick-function captions under the grips.
	_text_at(Vector2(118.0, 372.0), _captions[0], 14.0, get_theme_color("font_color", "SecondaryLabel"))
	_text_at(Vector2(502.0, 372.0), _captions[1], 14.0, get_theme_color("font_color", "SecondaryLabel"))
	_pixels()


func _stick(axis_x: int, press_button: int, well: Color) -> void:
	var id := _aid(axis_x)
	var rect: Rect2 = _rects[id]
	var press_id := _bid(press_button)
	var lit := _is_lit(id) or _is_lit(_aid(axis_x + 1)) or _is_lit(press_id)
	var pressed := is_button_pressed(press_button)
	var centre := rect.get_center()
	var radius := rect.size.x * 0.5
	if lit:
		_halo(rect, true)
	draw_circle(centre, radius, well, true, -1.0, true)
	draw_circle(centre, radius, UiTheme.EDGE, false, 1.5, true)
	draw_circle(centre, radius * 0.62, Color(UiTheme.EDGE, 0.35), false, 1.0, true)
	var offset := Vector2(clampf(_axes[axis_x], -1.0, 1.0), clampf(_axes[axis_x + 1], -1.0, 1.0))
	if offset.length() > 1.0:
		offset = offset.normalized()
	var moved := offset.length() > 0.05
	var cap_centre := centre + offset * radius * 0.4
	var cap_radius := radius * 0.56
	draw_circle(cap_centre + Vector2(0.0, 2.5), cap_radius, Color(0, 0, 0, 0.35), true, -1.0, true)
	draw_circle(cap_centre, cap_radius, Color("#3A3F3A") if not pressed else UiTheme.FOCUS.darkened(0.45), true, -1.0, true)
	var rim := UiTheme.FOCUS if pressed or moved else (UiTheme.CRYSTAL if lit else Color("#5A605A"))
	draw_circle(cap_centre, cap_radius, rim, false, 2.0, true)
	_glyph(press_button, cap_centre, cap_radius * 1.4, _state_color(press_id, pressed))
	if moved:
		draw_line(centre, cap_centre, Color(UiTheme.FOCUS, 0.5), 2.0, true)
		draw_circle(centre, 2.5, Color(UiTheme.FOCUS, 0.7), true, -1.0, true)


func _glyph(button: int, centre: Vector2, edge: float, tint: Color) -> void:
	var texture: Texture2D = _textures.get(button)
	if texture == null:
		draw_circle(centre, edge * 0.36, tint, false, 2.0, true)
		return
	draw_texture_rect(texture, Rect2(centre - Vector2.ONE * edge * 0.5, Vector2.ONE * edge), false, tint)


func _dpad_arrow(rect: Rect2, button: int, color: Color) -> void:
	var tip := Vector2.ZERO
	match button:
		JOY_BUTTON_DPAD_UP: tip = Vector2(0, -1)
		JOY_BUTTON_DPAD_DOWN: tip = Vector2(0, 1)
		JOY_BUTTON_DPAD_LEFT: tip = Vector2(-1, 0)
		_: tip = Vector2(1, 0)
	var centre := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.3
	var normal := Vector2(-tip.y, tip.x)
	var a := centre + tip * r
	var b := centre - tip * r * 0.6 + normal * r
	var c := centre - tip * r * 0.6 - normal * r
	draw_line(a, b, color, 2.0, true)
	draw_line(b, c, color, 2.0, true)
	draw_line(c, a, color, 2.0, true)


func _draw_radio() -> void:
	_design()
	var case_rect := Rect2(78.0, 62.0, 464.0, 298.0)
	# Carry handle and two short antenna stubs; deliberately generic (no brand shape).
	_rounded(Rect2(250.0, 18.0, 120.0, 54.0), Color("#1B1D1B"), 22.0, true)
	_rounded(Rect2(250.0, 18.0, 120.0, 54.0), UiTheme.EDGE, 22.0, false, 2.0)
	_rounded(Rect2(270.0, 34.0, 80.0, 30.0), UiTheme.PANEL, 14.0, true)
	draw_set_transform(_origin + Vector2(0.0, 7.0 * _scale), 0.0, Vector2(_scale, _scale))
	_rounded(case_rect, Color(0, 0, 0, 0.35), 46.0, true)
	_design()
	_rounded(case_rect, Color("#252825"), 46.0, true)
	_rounded(case_rect, UiTheme.EDGE, 46.0, false, 2.0)
	_rounded(case_rect.grow(-10.0), Color(UiTheme.EDGE, 0.25), 38.0, false, 1.0)
	# Switch row.
	for entry in _lamps:
		var is_button := entry.has("button")
		var id := _bid(int(entry.button)) if is_button else _aid(int(entry.axis))
		var rect: Rect2 = _rects.get(id, Rect2())
		if rect.size == Vector2.ZERO:
			continue
		var lit := _is_lit(id)
		if lit:
			_halo(rect, not is_button)
		var label := str(entry.get("label", ""))
		if is_button:
			var pressed := is_button_pressed(int(entry.button))
			_rounded(rect, Color("#161816"), 6.0, true)
			var lamp := Rect2(rect.position + Vector2(5.0, 5.0), Vector2(rect.size.x - 10.0, 8.0))
			_rounded(lamp, UiTheme.FOCUS if pressed else Color("#3A3F3A"), 3.0, true)
			_rounded(rect, UiTheme.CRYSTAL if lit else UiTheme.EDGE, 6.0, false, 1.5)
			if label.is_empty():
				label = "B%d" % (int(entry.button) + 1)
			_text_at(rect.get_center() + Vector2(0.0, 6.0), label, 13.0, UiTheme.CRYSTAL if lit or pressed else UiTheme.TEXT)
		else:
			var centre := rect.get_center()
			var radius := rect.size.x * 0.5
			var value := clampf(axis_value(int(entry.axis)), -1.0, 1.0)
			draw_circle(centre, radius, Color("#161816"), true, -1.0, true)
			draw_arc(centre, radius - 2.0, PI * 0.75, PI * 2.25, 24, Color(UiTheme.EDGE, 0.8), 2.0, true)
			var angle := PI * 1.5 + value * PI * 0.75
			draw_arc(centre, radius - 2.0, PI * 1.5, angle, 16, UiTheme.FOCUS, 2.5, true)
			draw_line(centre, centre + Vector2.from_angle(angle) * (radius - 4.0), UiTheme.TEXT, 2.0, true)
			if label.is_empty():
				label = "A%d" % (int(entry.axis) + 1)
		_text_at(Vector2(rect.get_center().x, rect.end.y + 11.0), label if not is_button else "", 12.0, UiTheme.TEXT_2)
	# Gimbal wells (the StickGimbalViews draw on top as children) and their captions.
	for side in 2:
		var functions: Array = _gimbal_functions[side]
		var rect: Rect2 = _rects[_aid(_radio_axis(functions[0]))]
		var lit := _is_lit(_aid(_radio_axis(functions[0]))) or _is_lit(_aid(_radio_axis(functions[1])))
		if lit:
			_halo(rect, false)
		_rounded(rect.grow(6.0), Color("#161816"), 12.0, true)
		_text_at(Vector2(rect.get_center().x, rect.end.y + 22.0), _captions[side], 14.0,
			UiTheme.CRYSTAL if lit else get_theme_color("font_color", "SecondaryLabel"))
	# The stick mode reads like a label plate in the handle opening.
	_text_at(Vector2(310.0, 49.0), str(_texts.get("mode", "")), 13.0, UiTheme.TEXT_2)
	_pixels()


func _draw_keyboard() -> void:
	_design()
	var bounds := _layout_bounds
	_rounded(Rect2(bounds.position - Vector2(10.0, 10.0), Vector2(bounds.size.x + 20.0, 6.25 * KEY_UNIT + 16.0)),
		Color("#1A1C1A"), 12.0, true)
	if highlighted_id.begins_with("key:") and _rects.has(highlighted_id):
		_halo(_rects[highlighted_id], false)
	# Legend: flight swatch + entries, then pressed swatch.
	var y := 6.25 * KEY_UNIT + 26.0
	var x := 0.0
	var font := _font()
	var font_size := _font_px(14.0)
	x = _legend_swatch(x, y, _cap_styles.flight, str(_texts.get("flight", "")), font, font_size)
	for entry: Array in _legend:
		if entry.size() < 3:
			continue
		var arrows := PackedInt32Array()
		for key: Variant in entry[0]:
			if int(key) in KeyCap.ARROW_KEYS:
				arrows.append(int(key))
		for key in arrows:
			_mini_arrow(Rect2(x, y - 9.0, 18.0, 18.0), int(key))
			x += 20.0
		_pixels()
		var text: String = entry[2]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / _scale
		_text_left(Vector2(x + 2.0, y), text, font, font_size, UiTheme.TEXT_2)
		x += width + 18.0
	_legend_swatch(x, y, _cap_styles.pressed, str(_texts.get("pressed", "")), font, font_size)
	_pixels()


func _legend_swatch(x: float, y: float, style: StyleBoxFlat, text: String, font: Font, font_size: int) -> float:
	_design()
	draw_style_box(style, Rect2(x, y - 8.0, 16.0, 16.0))
	_text_left(Vector2(x + 22.0, y), text, font, font_size, UiTheme.TEXT)
	return x + 22.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / _scale + 18.0


func _text_left(design_point: Vector2, text: String, font: Font, font_size: int, color: Color) -> void:
	_pixels()
	var point := _origin + design_point * _scale
	draw_string(font, Vector2(point.x, point.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	_design()


func _mini_arrow(rect: Rect2, key: int) -> void:
	_design()
	_rounded(rect, UiTheme.KEYCAP.bg, 3.0, true)
	_rounded(rect, Color(UiTheme.FOCUS, 0.8), 3.0, false, 1.0)
	var tip: Vector2 = {KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0), KEY_UP: Vector2(0, -1), KEY_DOWN: Vector2(0, 1)}[key]
	var centre := rect.get_center()
	var r := rect.size.x * 0.26
	var normal := Vector2(-tip.y, tip.x)
	draw_colored_polygon(PackedVector2Array([centre + tip * r, centre - tip * r * 0.7 + normal * r,
		centre - tip * r * 0.7 - normal * r]), UiTheme.TEXT)
