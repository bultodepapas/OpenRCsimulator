# HUD-13-R3: optional native cockpit instruments. Telemetry presentation, not simulated avionics.
extends "res://render/overlays/player_instrument.gd"

const DIAL_TITLES := {airspeed_dial = "Airspeed dial", attitude = "Artificial horizon", altimeter = "Altimeter", heading = "Heading indicator", variometer = "Vertical speed indicator"}
const DIAL_ICONS := {airspeed_dial = "speed", attitude = "height", altimeter = "height", heading = "weather", variometer = "height"}
const SKY := Color("35789e")
const EARTH := Color("78513b")
const DIAL := Color("0b141c")
const RADIUS := 100.0
var _face: Control
var _dial_value := NAN
var _pitch := NAN
var _bank := NAN
var _system := "metric"
var _unit := ""
var _maximum := 240.0
var _available := false
var _over_range := false


func _init(instrument_id: String) -> void:
	super(instrument_id, DIAL_TITLES[instrument_id], DIAL_ICONS[instrument_id])
	value_label.get_parent().hide()
	graphic.custom_minimum_size = Vector2(240, 236)
	body.move_child(graphic, 0)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_face = Control.new()
	_face.name = "DialFace"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	graphic.add_child(_face)
	_face.draw.connect(_draw_face)
	graphic.resized.connect(_face.queue_redraw)
	_apply_density()


func _apply_density() -> void:
	super()
	graphic.show()
	graphic.custom_minimum_size.y = 196 if _compact else 236
	_separator.hide()
	if _footer != null: _footer.visible = not _compact
	if _face != null: _face.queue_redraw()


func refresh(t: Dictionary, system: String, peak: float, _battery: Dictionary, _fuel: Dictionary, _trims: Dictionary = {}, _rpm: float = NAN) -> void:
	var fields: Array
	match id:
		"attitude": fields = [t.get("pitch_deg"), t.get("bank_deg")]
		"heading": fields = [t.get("heading_deg")]
		"altimeter": fields = [t.get("height_datum"), t.get("height_agl")]
		"airspeed_dial": fields = [t.get("airspeed"), peak]
		_: fields = [t.get("vertical_speed")]
	var key: Array = [system, TranslationServer.get_locale()]
	for field: Variant in fields:
		key.append(field if field != null and is_finite(float(field)) else null)
	if key == _view_key: return
	_view_key = key
	if _system != system and _face != null: _face.queue_redraw()
	_system = system
	_over_range = false
	match id:
		"attitude":
			_pitch = float(t.get("pitch_deg", NAN))
			_bank = float(t.get("bank_deg", NAN))
			_available = is_finite(_pitch) and is_finite(_bank)
			subtitle.text = "%s %s · %s %s" % [tr("Pitch"), Units.angle(_pitch, 0), tr("Bank"), Units.angle(_bank, 0)] if _available else tr("No attitude data")
			_details(tr("Pitch"), Units.angle(_pitch, 1), tr("Bank"), Units.angle(_bank, 1))
		"heading":
			_dial_value = float(t.get("heading_deg", NAN))
			_available = is_finite(_dial_value)
			if _available: _dial_value = fposmod(_dial_value, 360.0)
			subtitle.text = "%s · %s" % [Units.angle(fposmod(roundf(_dial_value), 360.0) if _available else NAN, 0, false), tr("True heading")]
			_details(tr("True heading"), Units.angle(_dial_value, 1, false), tr("REFERENCE"), "N / E / S / W")
		"altimeter":
			var pair := Units.length(float(t.get("height_datum", NAN)), system)
			_dial_value = pair[0]
			_unit = pair[1]
			_available = is_finite(_dial_value)
			subtitle.text = "%s · %s" % [Units.format(pair), tr("Datum")]
			_details(tr("Height above datum"), Units.format(pair), "AGL", Units.format(Units.length(float(t.get("height_agl", NAN)), system)))
		"airspeed_dial":
			var pair := Units.speed(float(t.get("airspeed", NAN)), system)
			_dial_value = pair[0]
			_unit = pair[1]
			_maximum = 160.0 if system == "imperial" else (70.0 if system == "si" else 240.0)
			_available = is_finite(_dial_value) and _dial_value >= 0.0
			_over_range = _available and _dial_value > _maximum
			subtitle.text = "%s · TAS" % Units.format(pair)
			_details(tr("True airspeed"), Units.format(pair), tr("FLIGHT MAX"), Units.format(Units.speed(peak, system)))
		"variometer":
			var pair := Units.vertical(float(t.get("vertical_speed", NAN)), system)
			_dial_value = pair[0]
			_unit = pair[1]
			_maximum = 2000.0 if system == "imperial" else 10.0
			_available = is_finite(_dial_value)
			_over_range = _available and absf(_dial_value) > _maximum
			subtitle.text = Units.format(pair, true)
			_details(tr("Climb / sink"), Units.format(pair, true), tr("REFERENCE"), "↑ + / ↓ −")
	if _over_range: subtitle.text += " · " + tr("Scale exceeded")
	subtitle.add_theme_color_override("font_color", ACCENT if _over_range else INK)
	subtitle.tooltip_text = subtitle.text
	graphic.tooltip_text = tr("Hundreds / thousands") if id == "altimeter" else tr(DIAL_TITLES[id])
	graphic.queue_redraw()


func _transform(canvas: Control) -> void:
	canvas.draw_set_transform(graphic.size * 0.5, 0.0, Vector2.ONE * (minf(graphic.size.x, graphic.size.y) - 12.0) / 224.0)


func _draw_face() -> void:
	_transform(_face)
	_face.draw_circle(Vector2(0, 3), 111, Color(0, 0, 0, 0.5))
	_face.draw_circle(Vector2.ZERO, 109, Color("3a4d5b"))
	_face.draw_circle(Vector2.ZERO, 106, Color("101a22"))
	_face.draw_circle(Vector2.ZERO, 101, DIAL)
	_face.draw_arc(Vector2.ZERO, 108, PI * 1.08, PI * 1.92, 40, Color("9bafbc", 0.5), 1.5, true)
	_face.draw_arc(Vector2.ZERO, 103, 0, TAU, 90, Color("597181", 0.5), 1, true)
	match id:
		"airspeed_dial":
			var limit := 160.0 if _system == "imperial" else (70.0 if _system == "si" else 240.0)
			_scale(_face, 0.0, limit, 32 if _system == "imperial" else (28 if _system == "si" else 48), 4, -225.0, 45.0)
			_text(_face, "TAS", Vector2(0, -35), 13, MUTED)
			_text(_face, str(Units.speed(0, _system)[1]), Vector2(0, 51), 13, ACCENT)
		"altimeter":
			_scale(_face, 0, 10, 50, 5, -90, 270, true)
			_text(_face, tr("Datum").to_upper(), Vector2(0, -34), 12, MUTED)
			_text(_face, "×100 / ×1000", Vector2(0, 40), 12, MUTED)
			_text(_face, str(Units.length(0, _system)[1]), Vector2(0, 57), 13, ACCENT)
		"variometer":
			var limit := 2.0 if _system == "imperial" else 10.0
			_scale(_face, -limit, limit, 40, 10, 45, 315)
			_text(_face, "+ ↑", Vector2(0, -34), 14, MUTED)
			_text(_face, "− ↓", Vector2(0, 42), 14, MUTED)
			_text(_face, "×1000 ft/min" if _system == "imperial" else "m/s", Vector2(0, 62), 12, ACCENT)
		"attitude":
			for angle: float in [-60.0, -45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0, 60.0]:
				var dir := Vector2.UP.rotated(deg_to_rad(angle))
				_face.draw_line(dir * 94, dir * (103 if fmod(angle, 30.0) == 0 else 99), INK, 2, true)
		_:
			pass
	_face.draw_set_transform(Vector2.ZERO)


func _scale(canvas: Control, low: float, high: float, divisions: int, major: int, start: float, end: float, wrap := false) -> void:
	for tick in range(divisions if wrap else divisions + 1):
		var fraction := float(tick) / divisions
		var direction := Vector2.RIGHT.rotated(deg_to_rad(lerpf(start, end, fraction)))
		var bold := tick % major == 0
		canvas.draw_line(direction * (83 if bold else 90), direction * 97, INK if bold else MUTED, 2 if bold else 1, true)
		if bold: _text(canvas, "%g" % lerpf(low, high, fraction), direction * 70, 16, INK)


func _draw_instrument() -> void:
	_transform(graphic)
	if not _available:
		# No needle or level horizon is shown when the source is missing.
		graphic.draw_style_box(_surface_style(Color("482c23"), 4), Rect2(-36, -13, 72, 26))
		_text(graphic, "—", Vector2.ZERO, 20, ACCENT)
	else:
		match id:
			"attitude": _draw_horizon()
			"heading": _draw_heading()
			"airspeed_dial": _needle(deg_to_rad(lerpf(-225, 45, clampf(_dial_value / _maximum, 0, 1))), 78, 3, INK)
			"altimeter":
				_needle(altimeter_angles(_dial_value).y, 48, 6, ACCENT)
				_needle(altimeter_angles(_dial_value).x, 81, 3, INK)
			"variometer": _needle(PI + clampf(_dial_value / _maximum, -1, 1) * PI * 0.75, 78, 3, INK)
		if id not in ["attitude", "heading"]:
			graphic.draw_circle(Vector2.ZERO, 9, Color("415665"))
			graphic.draw_circle(Vector2.ZERO, 5, DIAL)
			graphic.draw_circle(Vector2(-1, -2), 2, Color("8399a8"))
	graphic.draw_set_transform(Vector2.ZERO)


static func altimeter_angles(altitude: float) -> Vector2:
	return Vector2(fposmod(altitude, 1000.0) / 1000.0 * TAU - PI / 2, fposmod(altitude, 10000.0) / 10000.0 * TAU - PI / 2)


func _needle(angle: float, length: float, width: float, color: Color) -> void:
	var dir := Vector2.RIGHT.rotated(angle)
	var side := dir.orthogonal() * width
	var points := PackedVector2Array([-dir * 17 - side, dir * (length - 9) - side * 0.4, dir * length, dir * (length - 9) + side * 0.4, -dir * 17 + side])
	graphic.draw_colored_polygon(points, color)


func _draw_heading() -> void:
	for tick in 72:
		var bearing := tick * 5.0
		var direction := Vector2.UP.rotated(deg_to_rad(bearing - _dial_value))
		var major := tick % 6 == 0
		graphic.draw_line(direction * (84 if major else 92), direction * 98, INK if major else MUTED, 2 if major else 1, true)
		if major:
			var caption: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(int(bearing), "%02d" % int(bearing / 10))
			_text(graphic, caption, direction * 70, 17, ACCENT if tick % 18 == 0 else INK)
	graphic.draw_colored_polygon(PackedVector2Array([Vector2(-6, -104), Vector2(6, -104), Vector2(0, -94)]), ACCENT)
	graphic.draw_line(Vector2(0, -32), Vector2(0, 32), ACCENT, 3, true)
	graphic.draw_polyline(PackedVector2Array([Vector2(-30, 9), Vector2(0, -7), Vector2(30, 9)]), ACCENT, 3, true)
	graphic.draw_line(Vector2(-12, 27), Vector2(12, 27), ACCENT, 3, true)


## Screen coordinates in the rolling horizon plane. Nose-up lowers the horizon; right bank rotates it left.
static func horizon_point(point: Vector2, pitch: float, bank: float) -> Vector2:
	return (point + Vector2(0, pitch * 2.0)).rotated(deg_to_rad(-bank))


static func ground_polygon(pitch: float, bank: float) -> PackedVector2Array:
	var circle := PackedVector2Array()
	for i in 96: circle.append(Vector2.RIGHT.rotated(float(i) / 96.0 * TAU) * 91)
	var normal := Vector2.DOWN.rotated(deg_to_rad(-bank))
	var offset := pitch * 2.0
	var clipped := PackedVector2Array()
	var previous := circle[circle.size() - 1]
	var prev_distance := normal.dot(previous) - offset
	for current: Vector2 in circle:
		var distance := normal.dot(current) - offset
		if (distance >= 0) != (prev_distance >= 0):
			clipped.append(previous.lerp(current, prev_distance / (prev_distance - distance)))
		if distance >= 0: clipped.append(current)
		previous = current
		prev_distance = distance
	return clipped


func _draw_horizon() -> void:
	graphic.draw_circle(Vector2.ZERO, 91, SKY)
	var ground := ground_polygon(_pitch, _bank)
	if ground.size() >= 3: graphic.draw_colored_polygon(ground, EARTH)
	var offset := _pitch * 2.0
	if absf(offset) < 91:
		var half := sqrt(91.0 * 91.0 - offset * offset)
		graphic.draw_line(horizon_point(Vector2(-half, 0), _pitch, _bank), horizon_point(Vector2(half, 0), _pitch, _bank), INK, 2, true)
	for angle in range(-80, 81, 10):
		if angle == 0: continue
		var width := 27.0 if angle % 20 == 0 else 16.0
		var left := horizon_point(Vector2(-width, -angle * 2.0), _pitch, _bank)
		var right := horizon_point(Vector2(width, -angle * 2.0), _pitch, _bank)
		if maxf(left.length(), right.length()) < 75:
			graphic.draw_line(left, right, Color(INK, 0.85), 1, true)
			if angle % 20 == 0:
				var label_position := horizon_point(Vector2(width + 13, -angle * 2.0), _pitch, _bank)
				if label_position.length() < 73: _text(graphic, str(absi(angle)), label_position, 11, INK)
	var bank_tip := Vector2.UP.rotated(deg_to_rad(-_bank))
	var bank_side := bank_tip.orthogonal() * 5
	graphic.draw_colored_polygon(PackedVector2Array([bank_tip * 92, bank_tip * 82 + bank_side, bank_tip * 82 - bank_side]), INK)
	# The fixed aircraft reference always stays centred, independent of the horizon.
	for side: float in [-1.0, 1.0]:
		graphic.draw_polyline(PackedVector2Array([Vector2(side * 54, 0), Vector2(side * 23, 0), Vector2(side * 17, 7)]), Color("15202a"), 7, true)
		graphic.draw_polyline(PackedVector2Array([Vector2(side * 54, 0), Vector2(side * 23, 0), Vector2(side * 17, 7)]), ACCENT, 3, true)
	graphic.draw_circle(Vector2.ZERO, 4, ACCENT)


func _text(canvas: Control, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_font("font")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	canvas.draw_string(font, center + Vector2(-width * 0.5, font.get_ascent(font_size) * 0.5 - 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
