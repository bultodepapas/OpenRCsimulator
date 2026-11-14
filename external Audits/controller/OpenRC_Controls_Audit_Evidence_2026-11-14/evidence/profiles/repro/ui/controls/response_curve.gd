# UI-15-UX-08: output vs input for one flight channel, with a live dot at the current stick value. The curve is
# sampled through ControllerProfile.channel_value(), the same public function the flight uses (rc_input.gd _stick),
# so calibration endpoints, inversion, the rescaled deadzone and the cubic expo are never re-implemented here.
# Shaping is drawn disabled where the profile does not apply it: absolute throttles (trigger or radio) and radio /
# joystick profiles (shaping belongs to the transmitter). Presentation only: it never edits the profile.
# Samples are recomputed only when the channel changes; the live dot redraws only when it moves beyond EPSILON.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")

const SAMPLES := 97
const EPSILON := 0.002
const FUNCTION_NAMES := { roll = "Roll", pitch = "Pitch", yaw = "Yaw", throttle = "Throttle" }

## Redraw requests since creation; tests use it to prove unchanged samples cost nothing.
var redraw_requests := 0

var _profile := {}
var _channel := {}
## The channel without inversion and with default endpoints: maps a raw value to the physical stick position.
var _plain_channel := {}
var _channel_name := "roll"
var _kind := "gamepad"
var _absolute := false
var _shaping := true
var _inputs := PackedFloat64Array()
var _outputs := PackedFloat64Array()
var _points := PackedVector2Array()
var _points_size := Vector2.ZERO
var _live := false
var _live_input := 0.0
var _live_output := 0.0
var _title := ""
var _detail := ""
var _note := ""
var _x_label := ""
var _y_label := ""
var _plot_style := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(300.0, 240.0)
	_inputs.resize(SAMPLES)
	_outputs.resize(SAMPLES)
	_points.resize(SAMPLES)
	_plot_style.set_corner_radius_all(UiTheme.RADIUS)
	_plot_style.set_border_width_all(1)
	_plot_style.border_color = UiTheme.EDGE
	_plot_style.bg_color = Color(UiTheme.PANEL, 0.9)


## Plot `channel_name` (roll / pitch / yaw / throttle) of a draft profile. Only the profile's own values are read.
func set_channel(profile: Dictionary, channel_name: String) -> void:
	var channel: Variant = profile.get(channel_name, {})
	var next_channel: Dictionary = channel if channel is Dictionary else {}
	if channel_name == _channel_name and next_channel == _channel and _same_shape(profile):
		return
	_profile = profile.duplicate(true)
	_channel = next_channel.duplicate(true)
	_channel_name = channel_name
	_plain_channel = {"min": -1.0, "center": 0.0, "max": 1.0, "range_kind": "centered"}
	_plain_channel.merge(_channel, true)
	_plain_channel["invert"] = false
	_kind = str(profile.get("kind", "radio"))
	var mode := str(profile.get("throttle_mode", "stick_rate" if _kind == "gamepad" else "radio_absolute"))
	_absolute = channel_name == "throttle" and mode in ["trigger_absolute", "radio_absolute"]
	_shaping = _kind == "gamepad" and not _absolute
	for index in SAMPLES:
		var x := input_at(index)
		_inputs[index] = x
		_outputs[index] = ControllerProfile.channel_value(raw_for_input(x), _channel_name, _profile)
	_points_size = Vector2.ZERO
	if _live:
		_live_output = ControllerProfile.channel_value(raw_for_input(_live_input), _channel_name, _profile)
	_refresh_texts()
	_request_redraw()


## True when the profile applies this channel's deadzone and expo (a gamepad's centred channel).
func is_shaping_applied() -> bool:
	return _shaping


## True for absolute throttles (input and output 0 … 1).
func is_absolute() -> bool:
	return _absolute


## The x domain: −1 … +1, or 0 … 1 for an absolute throttle.
func input_range() -> Vector2:
	return Vector2(0.0, 1.0) if _absolute else Vector2(-1.0, 1.0)


func input_at(index: int) -> float:
	var domain := input_range()
	return lerpf(domain.x, domain.y, float(index) / float(SAMPLES - 1))


## The raw axis value that puts the physical stick at `input` (the calibrated min / centre / max endpoints; inversion
## and shaping stay in channel_value).
func raw_for_input(input: float) -> float:
	var lo := float(_channel.get("min", -1.0))
	var hi := float(_channel.get("max", 1.0))
	if _absolute or str(_channel.get("range_kind", "centered")) == "absolute":
		return lerpf(lo, hi, clampf(input, 0.0, 1.0) if _absolute else (clampf(input, -1.0, 1.0) + 1.0) * 0.5)
	var center := float(_channel.get("center", 0.0))
	var x := clampf(input, -1.0, 1.0)
	return center + x * ((hi - center) if x >= 0.0 else (center - lo))


## The plotted output at sample `index` (tests compare it with ControllerProfile).
func sample_output(index: int) -> float:
	return _outputs[index]


func sample_count() -> int:
	return SAMPLES


## The live stick as a RAW axis value (as read from the device). `live` false hides the dot.
func set_raw_value(raw: float, live: bool = true) -> void:
	# The stick's physical position is the profile's own endpoint normalisation without inversion.
	var input := ControllerProfile.normalize_absolute(raw, _plain_channel) if _absolute 		else ControllerProfile.normalize_axis(raw, _plain_channel)
	set_input_value(input, live)


## The live stick as a physical position in `input_range()`.
func set_input_value(input: float, live: bool = true) -> void:
	var value := input if is_finite(input) else 0.0
	if live == _live and absf(value - _live_input) <= EPSILON:
		return
	_live = live
	_live_input = value
	_live_output = ControllerProfile.channel_value(raw_for_input(value), _channel_name, _profile)
	_request_redraw()


func live_point() -> Vector2:
	return Vector2(_live_input, _live_output)


func is_live() -> bool:
	return _live


## Plot rectangle in local pixels.
func plot_rect() -> Rect2:
	var font := get_theme_font("font", "Label")
	var small := get_theme_font_size("font_size", "SectionLabel")
	var line := font.get_height(small)
	var top := line + 10.0
	var bottom := line * 3.0 + 14.0 # axis name and up to two detail lines
	var left := line + 10.0
	var edge := maxf(40.0, minf(size.x - left - 8.0, size.y - top - bottom))
	return Rect2(Vector2(left + (size.x - left - 8.0 - edge) * 0.5, top), Vector2(edge, edge))


## (input, output) → local pixels.
func to_plot(input: float, output: float) -> Vector2:
	var rect := plot_rect().grow(-6.0)
	var domain := input_range()
	var fx := (input - domain.x) / (domain.y - domain.x)
	var low := 0.0 if _absolute else -1.0
	var fy := (clampf(output, low, 1.0) - low) / (1.0 - low)
	return Vector2(rect.position.x + fx * rect.size.x, rect.end.y - fy * rect.size.y)


func _same_shape(profile: Dictionary) -> bool:
	return str(profile.get("kind", "")) == _kind and profile.get("throttle_mode") == _profile.get("throttle_mode")


func _refresh_texts() -> void:
	_title = tr(FUNCTION_NAMES.get(_channel_name, "Roll"))
	_x_label = tr("Stick")
	_y_label = tr("Output")
	if _shaping:
		_detail = tr("Deadzone %d %% · Expo %d %%") % [
			roundi(float(_channel.get("deadzone", ControllerProfile.DEFAULT_DEADZONE)) * 100.0),
			roundi(float(_channel.get("expo", ControllerProfile.DEFAULT_EXPO)) * 100.0)]
		if bool(_channel.get("invert", false)):
			_detail += " · " + tr("Inverted")
		_note = ""
	else:
		_detail = tr("Inverted") if bool(_channel.get("invert", false)) else ""
		_note = tr("Absolute throttle: no deadzone or expo") if _absolute \
			else tr("Linear: shape the response on the radio")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED, NOTIFICATION_THEME_CHANGED:
			_points_size = Vector2.ZERO
			queue_redraw()
		NOTIFICATION_TRANSLATION_CHANGED:
			_refresh_texts()
			queue_redraw()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var small := get_theme_font_size("font_size", "SectionLabel")
	var rect := plot_rect()
	var inner := rect.grow(-6.0)
	var muted := get_theme_color("font_color", "SecondaryLabel")
	draw_style_box(_plot_style, rect)
	# Title above, axis names beside and below.
	draw_string(font, Vector2(rect.position.x, rect.position.y - 8.0 - font.get_descent(small)), _title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small + 2, UiTheme.TEXT)
	draw_string(font, Vector2(rect.position.x, rect.end.y + 4.0 + font.get_ascent(small)), _x_label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, small, muted)
	draw_set_transform(Vector2(rect.position.x - 6.0, rect.get_center().y), -PI * 0.5, Vector2.ONE)
	var y_width := font.get_string_size(_y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, Vector2(-y_width * 0.5, -font.get_descent(small)), _y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small, muted)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Detail line (deadzone / expo, or why shaping is unused) under the axis name, across the whole control.
	var detail := _detail if _note.is_empty() else (_note if _detail.is_empty() else "%s · %s" % [_note, _detail])
	if not detail.is_empty():
		draw_multiline_string(font, Vector2(0.0, rect.end.y + 8.0 + font.get_height(small) + font.get_ascent(small)),
			detail, HORIZONTAL_ALIGNMENT_CENTER, size.x, small, 2, UiTheme.TEXT_2 if _shaping else UiTheme.CAUTION)
	# Grid: quarters, centre lines solid.
	var grid := Color(UiTheme.EDGE, 0.35)
	for step in range(1, 4):
		var t := float(step) / 4.0
		var gx := lerpf(inner.position.x, inner.end.x, t)
		var gy := lerpf(inner.position.y, inner.end.y, t)
		draw_line(Vector2(gx, inner.position.y), Vector2(gx, inner.end.y), Color(UiTheme.EDGE, 0.6) if step == 2 and not _absolute else grid, 1.0)
		draw_line(Vector2(inner.position.x, gy), Vector2(inner.end.x, gy), Color(UiTheme.EDGE, 0.6) if step == 2 and not _absolute else grid, 1.0)
	# Deadzone band.
	var deadzone := float(_channel.get("deadzone", 0.0)) if _shaping else 0.0
	if deadzone > 0.0:
		var a := to_plot(-deadzone, 0.0)
		var b := to_plot(deadzone, 0.0)
		draw_rect(Rect2(Vector2(a.x, inner.position.y), Vector2(b.x - a.x, inner.size.y)), Color(UiTheme.CAUTION, 0.10))
	# Linear reference (dashed) in the curve's own direction.
	var domain := input_range()
	var first_linear := _outputs[0] if not _shaping else (-1.0 if _outputs[SAMPLES - 1] >= _outputs[0] else 1.0)
	var last_linear := _outputs[SAMPLES - 1] if not _shaping else -first_linear
	if _shaping:
		draw_dashed_line(to_plot(domain.x, first_linear), to_plot(domain.y, last_linear), Color(UiTheme.TEXT_2, 0.35), 1.0, 6.0)
	# Curve.
	if _points_size != size:
		for index in SAMPLES:
			_points[index] = to_plot(_inputs[index], _outputs[index])
		_points_size = size
	var curve_color := UiTheme.FOCUS if _shaping else Color(UiTheme.TEXT_2, 0.7)
	draw_polyline(_points, curve_color, 2.5 if _shaping else 2.0, true)
	# Live dot with guide lines to both axes.
	if _live:
		var dot := to_plot(clampf(_live_input, domain.x, domain.y), _live_output)
		var guide := Color(UiTheme.CRYSTAL, 0.35)
		draw_line(Vector2(dot.x, inner.end.y), dot, guide, 1.0)
		draw_line(Vector2(inner.position.x, dot.y), dot, guide, 1.0)
		var radius := maxf(5.0, rect.size.x * 0.022)
		draw_circle(dot, radius, UiTheme.FOCUS if _shaping else UiTheme.TEXT_2, true, -1.0, true)
		draw_circle(dot, radius, UiTheme.ACCENT_INK, false, 1.5, true)
		var value := "%+d%%" % roundi(_live_output * 100.0) if not _absolute else "%d%%" % roundi(_live_output * 100.0)
		var value_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var label_x := clampf(dot.x + 10.0, inner.position.x + 2.0, inner.end.x - value_width - 2.0)
		var label_y := clampf(dot.y - 8.0, inner.position.y + font.get_ascent(small), inner.end.y - 4.0)
		draw_string(font, Vector2(label_x, label_y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, small, UiTheme.TEXT)


func _request_redraw() -> void:
	redraw_requests += 1
	queue_redraw()
