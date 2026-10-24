# HUD-13: player-facing instruments. Presentation only; consumes the existing 10 Hz telemetry.
extends "res://render/overlays/overlay_frame.gd"

const Units := preload("res://render/overlays/units.gd")
const FlightData := preload("res://render/overlays/flight_data.gd")
const InstrumentSettings := preload("res://render/overlays/overlay_settings.gd")
const ACCENT := Color("f1ca7d")
const INK := Color("f3f5f6")
const MUTED := Color("b6c4cf")
const TRACK := Color("344653")
const SURFACE := Color("101c27")
const BORDER := Color("627888", 0.48)
const TITLES := {speed = "Airspeed", height = "Height & flight", power = "Energy", weather = "Wind conditions", fuel = "Fuel tank", trims = "Trims", engine = "Engine"}

signal moved(id: String, normalized: Vector2)

var handle: Control
var value_label: Label
var unit_label: Label
var subtitle: Label
var left_value: Label
var right_value: Label
var left_caption: Label
var right_caption: Label
var graphic: Control
var layout_locked := false
var dragging := false
var _grab := Vector2.ZERO
var _fraction := NAN
var _wind_from := NAN
var _graphic_color := ACCENT
var _samples := PackedFloat32Array()
var _last_sample_time := -INF
var _style: StyleBoxFlat
var _compact := false
var _separator: HSeparator
var _trim_values := [NAN, NAN, NAN]
var _trim_labels: Array[Label] = []
var _trim_tracks: Array[Control] = []
var _trim_column: VBoxContainer
var _sample_head := 0
var _view_key: Array = []
var _header_icon: TextureRect
var _grip: Control
var _footer: HBoxContainer
var _footer_style: StyleBoxFlat
var _gauge_track: StyleBoxFlat
var _gauge_fill: StyleBoxFlat
var _header_hovered := false


func _init(instrument_id: String) -> void:
	super(instrument_id, tr(TITLES[instrument_id]))
	custom_minimum_size = Vector2(286, 0)
	_style = backplate()
	_style.bg_color = Color(SURFACE, 0.94)
	_style.border_color = BORDER
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(14)
	_style.shadow_color = Color(0.015, 0.025, 0.04, 0.22)
	_style.shadow_size = 6
	_style.shadow_offset = Vector2(0, 3)
	_style.content_margin_left = 16
	_style.content_margin_right = 16
	_style.content_margin_top = 10
	_style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", _style)
	draw.connect(_draw_chrome)
	resized.connect(queue_redraw)
	_footer_style = _surface_style(Color("263744", 0.58), 8)
	_gauge_track = _surface_style(Color("0b141d", 0.8), 4)
	_gauge_track.border_color = Color(TRACK, 0.8)
	_gauge_track.set_border_width_all(1)
	_gauge_fill = _surface_style(ACCENT, 3)
	var header := title_label.get_parent() as HBoxContainer
	header.add_theme_constant_override("separation", 8)
	_header_icon = TextureRect.new()
	_header_icon.name = "InstrumentIcon"
	_header_icon.texture = load("res://assets/ui/instruments/%s.svg" % id)
	_header_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header_icon.custom_minimum_size = Vector2(18, 18)
	_header_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_icon.modulate = ACCENT
	header.add_child(_header_icon)
	header.move_child(_header_icon, 0)
	title_label.text = tr(TITLES[id]).to_upper()
	title_label.add_theme_color_override("font_color", INK)
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.custom_minimum_size = Vector2(0, 28)
	handle = header
	handle.name = "DragHandle"
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.tooltip_text = tr("Drag to move · positions are saved")
	handle.gui_input.connect(_handle_input)
	handle.mouse_entered.connect(func() -> void: _header_hovered = true; _highlight(true))
	handle.mouse_exited.connect(func() -> void: _header_hovered = false; _highlight(dragging))
	visibility_changed.connect(_cancel_drag)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(body.get_parent() as VBoxContainer).add_theme_constant_override("separation", 8)
	close_button.flat = false
	close_button.add_theme_font_size_override("font_size", 18)
	for state: String in ["normal", "hover", "pressed"]:
		var close_style := _surface_style(Color("283b48", 0.75) if state == "normal" else Color(ACCENT, 0.18 if state == "hover" else 0.3), 8)
		close_button.add_theme_stylebox_override(state, close_style)
	close_button.add_theme_color_override("font_hover_color", ACCENT)
	_grip = Control.new()
	_grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grip.custom_minimum_size = Vector2(12, 28)
	_grip.draw.connect(_draw_grip)
	header.add_child(_grip)
	header.move_child(_grip, close_button.get_index())
	body.add_theme_constant_override("separation", 6)
	var reading := HBoxContainer.new()
	reading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reading.add_theme_constant_override("separation", 8)
	body.add_child(reading)
	value_label = text_label("—", 52, INK)
	value_label.name = "Reading"
	reading.add_child(value_label)
	unit_label = text_label("", 14, ACCENT)
	unit_label.name = "Unit"
	unit_label.size_flags_vertical = Control.SIZE_SHRINK_END
	unit_label.custom_minimum_size.y = 32
	unit_label.add_theme_constant_override("outline_size", 0)
	reading.add_child(unit_label)
	subtitle = text_label("", 12, MUTED)
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.custom_minimum_size.y = 20
	body.add_child(subtitle)
	graphic = Control.new()
	graphic.name = "Instrument"
	graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graphic.custom_minimum_size = Vector2(240, 58 if id == "speed" else 40)
	graphic.draw.connect(_draw_instrument)
	body.add_child(graphic)
	if id == "weather":
		graphic.custom_minimum_size.y = 112
	var line := HSeparator.new()
	_separator = line
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_stylebox_override("separator", _surface_style(Color.TRANSPARENT, 0))
	line.add_theme_constant_override("separation", 2)
	body.add_child(line)
	var details := HBoxContainer.new()
	_footer = details
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", 12)
	body.add_child(details)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for column: VBoxContainer in [left, right]:
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_child(column)
		column.add_theme_constant_override("separation", 3)
	left_caption = text_label("", 11, MUTED)
	left_value = text_label("—", 19, INK)
	right_caption = text_label("", 11, MUTED)
	right_value = text_label("—", 19, INK)
	left.add_child(left_caption)
	left.add_child(left_value)
	right.add_child(right_caption)
	right.add_child(right_value)
	for label: Label in [left_caption, right_caption, left_value, right_value]:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 108
	for label: Label in [right_value, right_caption]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer.resized.connect(queue_redraw)
	_footer.item_rect_changed.connect(queue_redraw)
	if id == "trims":
		_build_trims()
		reading.hide()
		graphic.hide()
		line.hide()
		details.hide()
	set_process_input(false)
	graphic.resized.connect(graphic.queue_redraw)
	_apply_density()


static func _surface_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _draw_chrome() -> void:
	# Light, static edge detailing: no blur shader, texture animation or frame callback.
	draw_line(Vector2(18, 1), Vector2(size.x - 18, 1), Color("93a9b8", 0.22), 1, true)
	draw_line(Vector2(16, 44), Vector2(size.x - 16, 44), Color(TRACK, 0.62), 1)
	draw_line(Vector2(16, 44), Vector2(42, 44), Color(ACCENT, 0.8), 2)
	if _footer != null and _footer.is_visible_in_tree():
		var box := Rect2(_footer.position - Vector2(8, 5), _footer.size + Vector2(16, 10))
		box.position = (get_global_transform().affine_inverse() * _footer.get_global_transform()).origin - Vector2(8, 5)
		draw_style_box(_footer_style, box)
		var centre := box.get_center().x
		draw_line(Vector2(centre, box.position.y + 8), Vector2(centre, box.end.y - 8), Color(TRACK, 0.8), 1)


func _draw_grip() -> void:
	var color := Color(ACCENT, 0.9) if _header_hovered and not layout_locked else Color(MUTED, 0.35)
	for row in 3:
		for column in 2:
			_grip.draw_circle(Vector2(3 + column * 4, 9 + row * 4), 0.9, color)


func _build_trims() -> void:
	_trim_column = VBoxContainer.new()
	_trim_column.add_theme_constant_override("separation", 10)
	_trim_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_trim_column)
	for axis in 3:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_trim_column.add_child(row)
		var label := text_label(tr(["Aileron", "Elevator", "Rudder"][axis]), 13, MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var value := text_label("—", 18, INK)
		row.add_child(value)
		_trim_labels.append(value)
		var track := Control.new()
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.custom_minimum_size = Vector2(240, 16)
		track.draw.connect(_draw_trim.bind(track, axis))
		track.resized.connect(track.queue_redraw)
		_trim_column.add_child(track)
		_trim_tracks.append(track)


func set_appearance(size_name: String, opacity: float, compact: bool) -> void:
	var next_scale := Vector2.ONE * float(InstrumentSettings.WIDGET_SIZE_SCALES.get(size_name, 1.0))
	if scale != next_scale:
		_finish_drag()
		scale = next_scale
	_style.bg_color = Color(SURFACE, clampf(opacity, 0.80, 1.0))
	if _compact != compact:
		_compact = compact
		_apply_density()
		# Containers can grow automatically, but need an explicit shrink after hiding details.
		_fit_content.call_deferred()


func _fit_content() -> void:
	reset_size()


func _apply_density() -> void:
	value_label.add_theme_font_size_override("font_size", 36 if _compact else 52)
	unit_label.custom_minimum_size.y = 26 if _compact else 32
	_style.content_margin_bottom = 10 if _compact else 16
	body.add_theme_constant_override("separation", 3 if _compact else 6)
	graphic.visible = id != "trims" and not _compact
	_separator.visible = id != "trims" and not _compact
	if _trim_column != null:
		_trim_column.add_theme_constant_override("separation", 4 if _compact else 10)
	queue_redraw()


func _ready() -> void:
	get_window().focus_exited.connect(_finish_drag)


func set_locked(on: bool) -> void:
	layout_locked = on
	if on:
		_finish_drag()
	handle.mouse_default_cursor_shape = Control.CURSOR_ARROW if on else Control.CURSOR_MOVE
	handle.tooltip_text = tr("Widget position locked") if on else tr("Drag to move · positions are saved")


func _handle_input(event: InputEvent) -> void:
	if layout_locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			_grab = handle.get_global_transform() * event.position - global_position
			move_to_front()
			_highlight(true)
			set_process_input(true)
		else:
			_finish_drag()
		handle.accept_event()
	elif event is InputEventMouseMotion and dragging:
		move_bounded(handle.get_global_transform() * event.position - _grab)
		handle.accept_event()


func _input(event: InputEvent) -> void:
	# Only enabled during a drag; release outside the moving header still completes the gesture.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag()


func _cancel_drag() -> void:
	if not is_visible_in_tree():
		_finish_drag()
		_samples.clear()
		_sample_head = 0
		_last_sample_time = -INF
		_view_key.clear()


func _finish_drag() -> void:
	if not dragging:
		return
	dragging = false
	set_process_input(false)
	_highlight(false)
	moved.emit(id, normalized_position())


func _highlight(on: bool) -> void:
	_style.border_color = Color(ACCENT, 0.8) if on and not layout_locked else BORDER
	if _grip != null: _grip.queue_redraw()


func move_bounded(wanted: Vector2) -> void:
	var extent := (get_parent() as Control).size
	position = Vector2(clampf(wanted.x, 12.0, maxf(12.0, extent.x - size.x * scale.x - 12.0)),
		clampf(wanted.y, 12.0, maxf(12.0, extent.y - size.y * scale.y - 12.0)))


func normalized_position() -> Vector2:
	var travel := (get_parent() as Control).size - size * scale - Vector2(24, 24)
	return Vector2(clampf((position.x - 12.0) / maxf(1.0, travel.x), 0.0, 1.0),
		clampf((position.y - 12.0) / maxf(1.0, travel.y), 0.0, 1.0))


func place_normalized(point: Vector2) -> void:
	if dragging:
		return
	var travel := (get_parent() as Control).size - size * scale - Vector2(24, 24)
	move_bounded(Vector2(12, 12) + Vector2(maxf(0, travel.x), maxf(0, travel.y)) * point)


func reset_flight() -> void:
	_samples.clear()
	_sample_head = 0
	_view_key.clear()
	_last_sample_time = -INF
	graphic.queue_redraw()


func refresh(t: Dictionary, system: String, peak: float, battery: Dictionary, fuel: Dictionary, trims: Dictionary = {}, rpm: float = NAN) -> void:
	# Ignore unrelated telemetry and repeated paused snapshots. No redraw or label work when unchanged.
	var key := _make_view_key(t, system, peak, battery, fuel, trims, rpm)
	if key == _view_key:
		return
	_view_key = key
	match id:
		"speed":
			_reading(Units.speed(float(t.get("airspeed", NAN)), system))
			subtitle.text = tr("Airspeed · recent trend")
			_details(tr("FLIGHT MAX"), Units.format(Units.speed(peak, system)), tr("GROUND"), Units.format(Units.speed(float(t.get("ground_speed", NAN)), system)))
			left_value.tooltip_text = tr("Maximum sampled airspeed this flight (10 Hz). Resets with the flight.")
			var now := float(t.get("time_s", NAN))
			var speed := float(t.get("airspeed", NAN))
			if is_finite(now) and is_finite(speed) and now != _last_sample_time:
				if now < _last_sample_time: reset_flight()
				if _samples.size() < 120:
					_samples.append(speed)
				else:
					_samples[_sample_head] = speed
					_sample_head = (_sample_head + 1) % 120
				_last_sample_time = now
		"height":
			_reading(Units.length(float(t.get("height_agl", NAN)), system))
			subtitle.text = tr("Above terrain · %s from pilot") % Units.format(Units.length(float(t.get("distance_pilot", NAN)), system))
			_fraction = float(t.get("vertical_speed", NAN))
			var elapsed := float(t.get("time_s", NAN))
			_details(tr("CLIMB / SINK"), Units.format(Units.vertical(_fraction, system), true), tr("FLIGHT TIME"), FlightData.clock(elapsed) if is_finite(elapsed) and elapsed >= 0.0 else "—")
		"power":
			_refresh_power(battery, fuel)
		"fuel":
			_refresh_fuel(fuel)
		"trims":
			subtitle.text = tr("Trim offset · % of full travel") if not trims.is_empty() else tr("No trim data")
			for axis in 3:
				_trim_values[axis] = float(trims.get(["roll", "pitch", "yaw"][axis], NAN))
				_trim_labels[axis].text = _signed_percent(_trim_values[axis])
				_trim_tracks[axis].queue_redraw()
		"engine":
			_reading([rpm, "rpm"])
			_fraction = float(t.get("throttle", NAN))
			subtitle.text = tr("Engine RPM · throttle command") if is_finite(rpm) else tr("Engine telemetry unavailable")
			_details(tr("THROTTLE"), _number(_fraction * 100.0, "%", 0), tr("FLIGHT LOAD"), _number(t.get("load_factor", NAN), "g", 1))
		"weather":
			_reading(Units.speed(float(t.get("wind_speed", NAN)), system))
			_wind_from = float(t.get("wind_from_deg", NAN))
			subtitle.text = tr("No telemetry") if t.is_empty() else (tr("Calm") if float(t.get("wind_speed", 0.0)) < 0.05 else tr("Direction wind comes from"))
			_details(tr("FROM"), Units.angle(_wind_from, 0, false), tr("VERTICAL AIR"), Units.format(Units.vertical(float(t.get("wind_up", NAN)), system), true))
	subtitle.tooltip_text = subtitle.text
	if graphic.visible:
		graphic.queue_redraw()


func _make_view_key(t: Dictionary, system: String, peak: float, battery: Dictionary, fuel: Dictionary, trims: Dictionary, rpm: float) -> Array:
	var values: Array = [system, TranslationServer.get_locale()]
	match id:
		"speed": values.append_array([t.get("time_s"), t.get("airspeed"), t.get("ground_speed"), peak])
		"height": values.append_array([t.get("height_agl"), t.get("distance_pilot"), t.get("vertical_speed"), t.get("time_s")])
		"weather": values.append_array([t.is_empty(), t.get("wind_speed"), t.get("wind_from_deg"), t.get("wind_up")])
		"trims": values.append_array([trims.is_empty(), trims.get("roll"), trims.get("pitch"), trims.get("yaw")])
		"engine": values.append_array([rpm, t.get("throttle"), t.get("load_factor")])
		"power", "fuel":
			for key: String in ["ok", "finite_fuel", "fill_fraction", "volume_ml", "fuel_remaining_kg", "low_fuel", "reserve_estimated"]:
				values.append(fuel.get(key))
			if id == "power":
				for key: String in ["valid", "remaining_pct", "pack_voltage_v", "current_a"]:
					values.append(battery.get(key))
				values.append(Array(battery.get("alarms", [])).duplicate())
	for i in values.size():
		if typeof(values[i]) == TYPE_FLOAT and not is_finite(values[i]):
			values[i] = null
	return values


static func _signed_percent(value: float) -> String:
	if not is_finite(value): return "—"
	var percent := snappedf(value * 100.0, 0.1)
	return ("+" if percent > 0.0 else "") + String.num(0.0 if is_zero_approx(percent) else percent, 1) + "%"


func _refresh_fuel(fuel: Dictionary) -> void:
	_graphic_color = ACCENT
	if not fuel.get("ok", false) or not fuel.get("finite_fuel", false):
		_fraction = NAN
		value_label.text = "—"
		unit_label.text = ""
		subtitle.text = tr("No finite fuel tank")
		_details(tr("REMAINING"), "—", tr("FUEL MASS"), "—")
		return
	_fraction = float(fuel.get("fill_fraction", NAN))
	_reading([_fraction * 100.0, "%"])
	subtitle.text = tr("Tank level · remaining fuel")
	_details(tr("REMAINING"), _number(fuel.get("volume_ml", NAN), "mL", 0), tr("FUEL MASS"), _number(float(fuel.get("fuel_remaining_kg", NAN)) * 1000.0, "g", 0))
	if fuel.get("low_fuel", false):
		_graphic_color = Color("ff8a75")
		subtitle.text = tr("Estimated reserve · land soon") if fuel.get("reserve_estimated", false) else tr("Fuel reserve · land soon")


func _reading(pair: Array) -> void:
	var formatted := Units.format(pair)
	value_label.text = formatted.trim_suffix(" " + str(pair[1]))
	unit_label.text = str(pair[1])


func _details(left_name: String, left_text: String, right_name: String, right_text: String) -> void:
	left_caption.text = left_name
	left_value.text = left_text
	right_caption.text = right_name
	right_value.text = right_text
	left_value.tooltip_text = left_text
	right_value.tooltip_text = right_text


func _refresh_power(battery: Dictionary, fuel: Dictionary) -> void:
	_graphic_color = ACCENT
	if battery.get("valid", false):
		_fraction = float(battery.get("remaining_pct", NAN)) / 100.0
		_reading([_fraction * 100.0, "%"])
		subtitle.text = tr("Battery · estimated remaining")
		_details(tr("PACK VOLTAGE"), _number(battery.get("pack_voltage_v", NAN), "V", 1), tr("CURRENT"), _number(battery.get("current_a", NAN), "A", 1))
		var alarms: Array = battery.get("alarms", [])
		if alarms.has("cell_critical") or alarms.has("exhausted") or alarms.has("lvc"):
			_graphic_color = Color("ff8a75")
			subtitle.text = tr("Battery critical · land now")
		elif not alarms.is_empty():
			subtitle.text = tr("Battery warning · check pack")
	elif fuel.get("ok", false) and fuel.get("finite_fuel", false):
		_fraction = float(fuel.get("fill_fraction", NAN))
		_reading([_fraction * 100.0, "%"])
		subtitle.text = tr("Fuel remaining")
		_details(tr("FUEL"), _number(fuel.get("volume_ml", NAN), "mL", 0), tr("RESERVE"), tr("Low") if fuel.get("low_fuel", false) else tr("Normal"))
		if fuel.get("low_fuel", false):
			_graphic_color = Color("ff8a75")
			subtitle.text = tr("Fuel reserve · land soon")
	else:
		_fraction = NAN
		value_label.text = "—"
		unit_label.text = ""
		subtitle.text = tr("Energy level unavailable")
		_details(tr("BATTERY"), "—", tr("FUEL"), "—")


static func _number(value: float, unit: String, decimals: int) -> String:
	return (String.num(value, decimals) if is_finite(value) else "—") + " " + unit


func _draw_instrument() -> void:
	var w := graphic.size.x
	var h := graphic.size.y
	match id:
		"speed":
			for i in 3:
				graphic.draw_line(Vector2(0, 5 + i * 17), Vector2(w, 5 + i * 17), Color(TRACK, 0.7), 1)
			_graphic_text(tr("RECENT"), Vector2(0, h - 1), MUTED, 9)
			_graphic_text(tr("NOW"), Vector2(w, h - 1), MUTED, 9, HORIZONTAL_ALIGNMENT_RIGHT)
			if _samples.is_empty(): return
			var ceiling := 1.0
			for sample in _samples: ceiling = maxf(ceiling, sample)
			ceiling *= 1.08
			var points := PackedVector2Array()
			for i in _samples.size():
				var sample: float = _samples[(_sample_head + i) % _samples.size()]
				points.append(Vector2(3 + (w - 6) * float(120 - _samples.size() + i) / 119.0, h - 18 - (h - 24) * sample / ceiling))
			if points.size() > 1:
				# Baseline sits below the zero-speed trace, so an idle aircraft still makes a valid polygon.
				var area := points.duplicate()
				area.append(Vector2(points[-1].x, h - 16))
				area.append(Vector2(points[0].x, h - 16))
				graphic.draw_colored_polygon(area, Color(ACCENT, 0.08))
				graphic.draw_polyline(points, ACCENT, 2.0, true)
			graphic.draw_circle(points[-1], 5, Color(ACCENT, 0.16), true, -1, true)
			graphic.draw_circle(points[-1], 2.5, INK, true, -1, true)
		"power":
			_draw_level_bar(true)
		"fuel", "engine":
			_draw_level_bar(false)
		"height":
			for side: int in [-1, 1]:
				graphic.draw_line(Vector2(w / 2 + side * 32, h / 2), Vector2(w / 2 + side * (w / 2 - 2), h / 2), TRACK, 1)
				for tick in 4:
					var x := w / 2 + side * (42 + tick * 20)
					graphic.draw_line(Vector2(x, h / 2 - 3), Vector2(x, h / 2 + 3), Color(TRACK, 0.8), 1)
			graphic.draw_circle(Vector2(w / 2, h / 2), 17, Color(TRACK, 0.4), true, -1, true)
			graphic.draw_arc(Vector2(w / 2, h / 2), 17, 0, TAU, 48, Color(ACCENT, 0.25), 1, true)
			if is_finite(_fraction):
				var c := Vector2(w / 2, h / 2)
				if absf(_fraction) < 0.05:
					graphic.draw_line(c - Vector2(8, 0), c + Vector2(8, 0), ACCENT, 3)
				else:
					var sign_up := -1.0 if _fraction > 0.0 else 1.0
					graphic.draw_colored_polygon(PackedVector2Array([c + Vector2(0, sign_up * 9), c + Vector2(-7, -sign_up * 5), c + Vector2(7, -sign_up * 5)]), ACCENT)
		"weather":
			var c := Vector2(w / 2, h / 2)
			var r := h / 2 - 16
			graphic.draw_circle(c, r - 8, Color("0b141d", 0.6), true, -1, true)
			graphic.draw_arc(c, r - 8, 0, TAU, 64, Color(TRACK, 0.65), 1, true)
			graphic.draw_arc(c, r + 2, 0, TAU, 64, Color(TRACK, 0.5), 1, true)
			for i in 36:
				var direction := Vector2(sin(i * TAU / 36), -cos(i * TAU / 36))
				graphic.draw_line(c + direction * (r - (7 if i % 9 == 0 else 3)), c + direction * r, ACCENT if i == 0 else (MUTED if i % 9 == 0 else TRACK), 1, true)
			_graphic_text(tr("N"), c + Vector2(0, -r - 5), ACCENT, 10, HORIZONTAL_ALIGNMENT_CENTER)
			_graphic_text(tr("E"), c + Vector2(r + 12, 4), MUTED, 10, HORIZONTAL_ALIGNMENT_CENTER)
			_graphic_text(tr("S"), c + Vector2(0, r + 14), MUTED, 10, HORIZONTAL_ALIGNMENT_CENTER)
			_graphic_text(tr("W"), c + Vector2(-r - 12, 4), MUTED, 10, HORIZONTAL_ALIGNMENT_CENTER)
			if is_finite(_wind_from):
				var dir := Vector2(sin(deg_to_rad(_wind_from)), -cos(deg_to_rad(_wind_from)))
				var side := Vector2(-dir.y, dir.x)
				graphic.draw_line(c - dir * (r - 13), c + dir * (r - 10), Color(ACCENT, 0.35), 1.5, true)
				graphic.draw_colored_polygon(PackedVector2Array([c + dir * (r - 10), c - dir * 5 + side * 6, c, c - dir * 5 - side * 6]), ACCENT)
				graphic.draw_line(c, c + dir * (r - 12), INK, 1, true)
				graphic.draw_circle(c, 3, INK, true, -1, true)
			else:
				graphic.draw_circle(c, 3, MUTED)


func _graphic_text(value: String, point: Vector2, color: Color, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if align == HORIZONTAL_ALIGNMENT_RIGHT: point.x -= width
	elif align == HORIZONTAL_ALIGNMENT_CENTER: point.x -= width / 2
	graphic.draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_level_bar(segmented: bool) -> void:
	var w := graphic.size.x
	var bar := Rect2(1, 7, w - 2, 12)
	graphic.draw_style_box(_gauge_track, bar)
	if is_finite(_fraction):
		var fill := clampf(_fraction, 0, 1)
		_gauge_fill.bg_color = _graphic_color
		if segmented:
			for i in 16:
				var cell_width := (w - 8) / 16.0
				var amount := clampf(fill * 16.0 - i, 0, 1)
				var rect := Rect2(4 + i * cell_width, 10, cell_width - 3, 6)
				graphic.draw_rect(rect, Color(TRACK, 0.8))
				if amount > 0:
					graphic.draw_rect(Rect2(rect.position, Vector2(rect.size.x * amount, 6)), _graphic_color)
		else:
			if fill > 0.002:
				graphic.draw_style_box(_gauge_fill, Rect2(3, 9, (w - 6) * fill, 8))
			var x := 3 + (w - 6) * fill
			graphic.draw_line(Vector2(x, 5), Vector2(x, 21), INK, 2, true)
	for i in 5:
		var x := 3 + (w - 6) * i / 4.0
		graphic.draw_line(Vector2(x, 23), Vector2(x, 26 if i % 2 == 0 else 25), Color(MUTED, 0.55), 1)
	_graphic_text("0", Vector2(1, 38), MUTED, 9)
	_graphic_text("50", Vector2(w / 2, 38), MUTED, 9, HORIZONTAL_ALIGNMENT_CENTER)
	_graphic_text("100%", Vector2(w - 1, 38), MUTED, 9, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_trim(track: Control, axis: int) -> void:
	var w := track.size.x
	var y := track.size.y / 2.0
	track.draw_style_box(_gauge_track, Rect2(0, y - 3, w, 6))
	for tick in 9:
		var x := 2 + (w - 4) * tick / 8.0
		track.draw_line(Vector2(x, y - 5), Vector2(x, y + 5), Color(MUTED, 0.8) if tick == 4 else Color(TRACK, 0.8), 1)
	var value: float = _trim_values[axis]
	if is_finite(value):
		var x := w / 2.0 + clampf(value, -1.0, 1.0) * (w / 2.0 - 3)
		track.draw_line(Vector2(w / 2.0, y), Vector2(x, y), Color(ACCENT, 0.8), 3, true)
		track.draw_circle(Vector2(x, y), 6, Color(ACCENT, 0.12), true, -1, true)
		track.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 5), Vector2(x + 3, y), Vector2(x, y + 5), Vector2(x - 3, y)]), INK)
