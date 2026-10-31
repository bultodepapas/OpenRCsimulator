# HUD-13-R3: optional native cockpit instruments. Telemetry presentation, not simulated avionics.
extends "res://render/overlays/player_instrument.gd"

const DIAL_TITLES := {airspeed_dial = "Airspeed dial", attitude = "Artificial horizon", altimeter = "Altimeter", heading = "Heading indicator", variometer = "Vertical speed indicator"}
const DIAL_ICONS := {airspeed_dial = "speed", attitude = "height", altimeter = "height", heading = "weather", variometer = "height"}
const SKY := Color("35789e")
const EARTH := Color("78513b")
const DIAL := Color("101010")
const BEZEL_OUTER := Color("414141")
const BEZEL_INNER := Color("181818")
const BEZEL_HIGHLIGHT := Color("727272")
const DIAL_INK := Color("f2eee2")
const DIAL_MINOR := Color("b8b5aa")
const DIAL_LEGEND := Color("cbc7bb")
const HEADER_PADDING := Vector2(8, 2)
var _horizon_disc := PackedVector2Array()
var _face: Control
var _readout_style: StyleBoxFlat
var _dial_value := NAN
var _pitch := NAN
var _bank := NAN
var _system := "metric"
var _unit := ""
var _maximum := 240.0
var _available := false
var _over_range := false
var _header_highlighted := false


func _init(instrument_id: String) -> void:
	super(instrument_id, DIAL_TITLES[instrument_id], DIAL_ICONS[instrument_id])
	# Keep the shared widget layout and hit targets, but give only the title a
	# crystal surface. The dial and readouts have their own independent shapes.
	_style.set_border_width_all(0)
	_style.shadow_size = 0
	_style.content_margin_left = 8
	_style.content_margin_right = 8
	_footer_style.bg_color = Color("0b0b0b", 0.9)
	if id == "attitude": _horizon_disc = _make_horizon_disc()
	value_label.get_parent().hide()
	graphic.custom_minimum_size = Vector2(240, 270)
	body.move_child(graphic, 0)
	# Keep the existing drag and close controls, placing their only title below the dial.
	handle.get_parent().remove_child(handle)
	body.add_child(handle)
	body.move_child(handle, 1)
	handle.resized.connect(_resize_glass)
	handle.resized.connect(handle.queue_redraw)
	handle.draw.connect(_draw_header_chrome)
	_header_icon.item_rect_changed.connect(handle.queue_redraw)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.max_lines_visible = 2
	var readout := _surface_style(Color("090909", 0.85), 6)
	readout.border_color = Color("858585", 0.25)
	readout.set_border_width_all(1)
	readout.content_margin_top = 5
	readout.content_margin_bottom = 5
	readout.content_margin_left = 6
	readout.content_margin_right = 6
	subtitle.add_theme_stylebox_override("normal", readout)
	_readout_style = readout
	_face = Control.new()
	_face.name = "DialFace"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	graphic.add_child(_face)
	_face.draw.connect(_draw_face)
	graphic.resized.connect(_face.queue_redraw)
	# Text can briefly require more height while telemetry/units initialize. Keep every dial fitted to
	# its final contents instead of retaining that transient height and misaligning the cockpit row.
	minimum_size_changed.connect(_queue_content_fit)
	_apply_density()


func set_appearance(size_name: String, opacity: float, compact: bool) -> void:
	super(size_name, opacity, compact)
	var alpha := clampf(opacity, 0.80, 1.0)
	if _readout_style != null:
		var readout_color := _readout_style.bg_color
		var readout_alpha := maxf(0.85, alpha)
		if not is_equal_approx(readout_color.a, readout_alpha):
			readout_color.a = readout_alpha
			_readout_style.bg_color = readout_color
			subtitle.queue_redraw()
	var footer_color := _footer_style.bg_color
	var footer_alpha := maxf(0.90, alpha)
	if not is_equal_approx(footer_color.a, footer_alpha):
		footer_color.a = footer_alpha
		_footer_style.bg_color = footer_color
		queue_redraw()


func _apply_density() -> void:
	super()
	graphic.show()
	graphic.custom_minimum_size.y = 248 if _compact else 270
	_separator.hide()
	if _footer != null: _footer.visible = not _compact
	if _face != null: _face.queue_redraw()


func _build_glass() -> void:
	super()
	# Reuse the lazy underlay as a child of the title so its position follows
	# container layout without synchronizing global coordinates.
	var underlay := _glass.get_parent()
	remove_child(underlay)
	handle.add_child(underlay, false, Node.INTERNAL_MODE_BACK)
	_resize_glass()


func _resize_glass() -> void:
	if _glass == null or _glass_material == null: return
	var header_size: Vector2 = handle.size + HEADER_PADDING * 2
	if not _glass.position.is_equal_approx(-HEADER_PADDING) or not _glass.size.is_equal_approx(header_size):
		_glass.position = -HEADER_PADDING
		_glass.size = header_size
		_glass_material.set_shader_parameter("rect_size", header_size)


func _draw_chrome() -> void:
	if _footer != null and _footer.is_visible_in_tree():
		var footer_origin := (get_global_transform().affine_inverse() * _footer.get_global_transform()).origin
		var box := Rect2(footer_origin - Vector2(8, 5), _footer.size + Vector2(16, 10))
		draw_style_box(_footer_style, box)
		var centre := box.get_center().x
		draw_line(Vector2(centre, box.position.y + 8), Vector2(centre, box.end.y - 8), Color(TRACK, 0.8), 1)


func _draw_header_chrome() -> void:
	var header := Rect2(-HEADER_PADDING, handle.size + HEADER_PADDING * 2)
	handle.draw_line(header.position + Vector2(14, 1), Vector2(header.end.x - 14, header.position.y + 1), Color("e0e0e0", 0.2), 1, true)
	handle.draw_line(Vector2(header.position.x + 14, header.end.y - 1), header.end - Vector2(14, 1), Color(TRACK, 0.62), 1, true)
	var accent_end := header.end.x - 14 if _header_highlighted else header.position.x + 40
	handle.draw_line(Vector2(header.position.x + 14, header.end.y - 1), Vector2(accent_end, header.end.y - 1), Color(CHROME_ACCENT, 0.95 if _header_highlighted else 0.8), 2, true)
	if _header_icon != null:
		var icon_origin := (handle.get_global_transform().affine_inverse() * _header_icon.get_global_transform()).origin
		handle.draw_style_box(_icon_style, Rect2(icon_origin - Vector2(4, 4), _header_icon.size + Vector2(8, 8)))


func _highlight(on: bool) -> void:
	_header_highlighted = on and not layout_locked
	if _grip != null: _grip.queue_redraw()
	handle.queue_redraw()


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
	if _face != null and (_view_key.is_empty() or _view_key[0] != key[0] or _view_key[1] != key[1]):
		_face.queue_redraw()
	_view_key = key
	_system = system
	_over_range = false
	match id:
		"attitude":
			_pitch = float(t.get("pitch_deg", NAN))
			_bank = float(t.get("bank_deg", NAN))
			_available = is_finite(_pitch) and is_finite(_bank)
			subtitle.text = "%s\u00a0%s · %s\u00a0%s" % [tr("Nose pitch"), Units.angle(_pitch, 0), tr("Bank"), Units.angle(_bank, 0)] if _available else tr("No attitude data")
			_details(tr("Nose pitch"), Units.angle(_pitch, 1), tr("Bank"), Units.angle(_bank, 1))
		"heading":
			_dial_value = float(t.get("heading_deg", NAN))
			_available = is_finite(_dial_value)
			if _available: _dial_value = fposmod(_dial_value, 360.0)
			subtitle.text = "%s · %s" % [Units.angle(fposmod(roundf(_dial_value), 360.0) if _available else NAN, 0, false), tr("True heading")]
			_details(tr("True heading"), Units.angle(_dial_value, 1, false), tr("Reference"), "N / E / S / W")
		"altimeter":
			var pair := Units.length(float(t.get("height_datum", NAN)), system)
			_dial_value = pair[0]
			_unit = pair[1]
			_available = is_finite(_dial_value)
			subtitle.text = "%s · %s" % [Units.format(pair), tr("Datum")]
			_details(tr("Datum"), Units.format(pair), "AGL", Units.format(Units.length(float(t.get("height_agl", NAN)), system)))
			left_value.tooltip_text = tr("Height above datum")
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
			_details(tr("Climb / sink"), Units.format(pair, true), tr("Dial range"), "±" + Units.format([_maximum, _unit]))
	if _over_range: subtitle.text += " · " + tr("Scale exceeded")
	subtitle.add_theme_color_override("font_color", ACCENT if _over_range else INK)
	subtitle.tooltip_text = subtitle.text
	graphic.tooltip_text = tr("Hundreds / thousands") if id == "altimeter" else tr(DIAL_TITLES[id])
	graphic.queue_redraw()


func _transform(canvas: Control) -> void:
	canvas.draw_set_transform(graphic.size * 0.5, 0.0, Vector2.ONE * (minf(graphic.size.x, graphic.size.y) - 4.0) / 224.0)


func _draw_face() -> void:
	_transform(_face)
	# A circular shadow and restrained rim leave the dial silhouette unobstructed.
	_face.draw_circle(Vector2(0, 2), 111, Color(0, 0, 0, 0.5))
	_face.draw_circle(Vector2.ZERO, 109, Color("080808"))
	_face.draw_circle(Vector2.ZERO, 107, BEZEL_OUTER)
	_face.draw_circle(Vector2.ZERO, 105, BEZEL_INNER)
	_face.draw_circle(Vector2.ZERO, 103.5, Color(BEZEL_HIGHLIGHT, 0.75))
	_face.draw_circle(Vector2.ZERO, 102, Color("080808"))
	_face.draw_circle(Vector2.ZERO, 100.5, DIAL)
	_face.draw_arc(Vector2.ZERO, 107, PI * 1.08, PI * 1.92, 40, Color("d2d2d2", 0.48), 1.2, true)
	_face.draw_arc(Vector2.ZERO, 106, PI * 0.1, PI * 0.9, 32, Color("050505", 0.88), 1.5, true)
	_face.draw_arc(Vector2.ZERO, 103, 0, TAU, 90, Color("b0b0b0", 0.38), 1, true)
	_face.draw_arc(Vector2.ZERO, 100, PI * 1.08, PI * 1.92, 40, Color("c0c0c0", 0.16), 1, true)
	match id:
		"airspeed_dial":
			var limit := 160.0 if _system == "imperial" else (70.0 if _system == "si" else 240.0)
			_scale(_face, 0.0, limit, 32 if _system == "imperial" else (28 if _system == "si" else 48), 6 if _system == "metric" else 4, -225.0, 45.0)
			_dial_legend("TAS", Vector2(0, -35), 13)
			_dial_legend(str(Units.speed(0, _system)[1]), Vector2(0, 51), 13)
		"altimeter":
			_scale(_face, 0, 10, 50, 5, -90, 270, true)
			_dial_legend(tr("Datum").to_upper(), Vector2(0, -34), 12)
			_dial_legend("×100 / ×1000", Vector2(0, 40), 12)
			_dial_legend(str(Units.length(0, _system)[1]), Vector2(0, 57), 13)
		"variometer":
			var limit := 2.0 if _system == "imperial" else 10.0
			_scale(_face, -limit, limit, 40, 10, 45, 315)
			_dial_legend("+ ↑", Vector2(0, -34), 14)
			_dial_legend("− ↓", Vector2(0, 42), 14)
			_dial_legend("×1000 ft/min" if _system == "imperial" else "m/s", Vector2(0, 26), 12)
		"attitude":
			for angle: float in [-60.0, -45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0, 60.0]:
				var dir := Vector2.UP.rotated(deg_to_rad(angle))
				_face.draw_line(dir * 94, dir * (103 if fmod(angle, 30.0) == 0 else 99), DIAL_INK, 2, true)
		_:
			pass
	_face.draw_set_transform(Vector2.ZERO)


func _dial_legend(text: String, center: Vector2, font_size: int) -> void:
	_text(_face, text, center + Vector2(0, 0.8), font_size, Color("050505"))
	_text(_face, text, center, font_size, DIAL_LEGEND)


func _scale(canvas: Control, low: float, high: float, divisions: int, major: int, start: float, end: float, wrap := false) -> void:
	for tick in range(divisions if wrap else divisions + 1):
		var fraction := float(tick) / divisions
		var direction := Vector2.RIGHT.rotated(deg_to_rad(lerpf(start, end, fraction)))
		var bold := tick % major == 0
		canvas.draw_line(direction * (83 if bold else 90), direction * 97, DIAL_INK if bold else Color(DIAL_MINOR, 0.8), 2 if bold else 1, true)
		if bold: canvas.draw_line(direction * 98, direction * 100, Color(DIAL_INK, 0.65), 1.5, true)
		if bold: _text(canvas, String.num(lerpf(low, high, fraction), 0), direction * 70, 16, DIAL_INK)


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
			"airspeed_dial": _needle(deg_to_rad(lerpf(-225, 45, clampf(_dial_value / _maximum, 0, 1))), 78, 3, DIAL_INK)
			"altimeter":
				_needle(altimeter_angles(_dial_value).y, 48, 6, MUTED)
				_needle(altimeter_angles(_dial_value).x, 81, 3, DIAL_INK)
			"variometer": _needle(PI + clampf(_dial_value / _maximum, -1, 1) * PI * 0.75, 78, 3, DIAL_INK)
		if id not in ["attitude", "heading"]:
			_draw_pivot()
	graphic.draw_set_transform(Vector2.ZERO)


static func altimeter_angles(altitude: float) -> Vector2:
	return Vector2(fposmod(altitude, 1000.0) / 1000.0 * TAU - PI / 2, fposmod(altitude, 10000.0) / 10000.0 * TAU - PI / 2)


func _needle(angle: float, length: float, width: float, color: Color) -> void:
	var dir := Vector2.RIGHT.rotated(angle)
	var side := dir.orthogonal() * width
	var tail := PackedVector2Array([
		-dir * 22 - side * 1.1, -dir * 15 - side * 1.1, -dir * 8 - side * 0.55,
		dir * 3 - side * 0.55, dir * 3 + side * 0.55, -dir * 8 + side * 0.55,
		-dir * 15 + side * 1.1, -dir * 22 + side * 1.1])
	var points := PackedVector2Array([
		-dir * 5 - side, dir * (length - 10) - side * 0.4, dir * length,
		dir * (length - 10) + side * 0.4, -dir * 5 + side])
	var shadow := PackedVector2Array()
	for point: Vector2 in tail: shadow.append(point + Vector2(1.5, 2.5))
	graphic.draw_colored_polygon(shadow, Color(0, 0, 0, 0.5))
	shadow.clear()
	for point: Vector2 in points: shadow.append(point + Vector2(1.5, 2.5))
	graphic.draw_colored_polygon(shadow, Color(0, 0, 0, 0.5))
	graphic.draw_colored_polygon(tail, Color("464646"))
	graphic.draw_polyline(PackedVector2Array([-dir * 22 - side * 1.1, -dir * 15 - side * 1.1, -dir * 8 - side * 0.55]), Color("909090", 0.55), 0.8, true)
	graphic.draw_colored_polygon(points, color)
	graphic.draw_colored_polygon(PackedVector2Array([-dir * 5, dir * length, dir * (length - 10) + side * 0.4, -dir * 5 + side]), color.darkened(0.22))
	graphic.draw_line(-dir * 3 - side * 0.72, dir * (length - 11) - side * 0.32, color.lightened(0.1), 0.8, true)


func _draw_pivot() -> void:
	graphic.draw_circle(Vector2(1, 2), 10, Color(0, 0, 0, 0.48), true, -1, true)
	graphic.draw_circle(Vector2.ZERO, 9, Color("111111"), true, -1, true)
	graphic.draw_circle(Vector2.ZERO, 7.5, Color("777777"), true, -1, true)
	graphic.draw_circle(Vector2.ZERO, 5.8, Color("262626"), true, -1, true)
	graphic.draw_arc(Vector2.ZERO, 7, PI * 1.05, PI * 1.9, 18, Color("eeeeee", 0.7), 1, true)
	graphic.draw_arc(Vector2.ZERO, 5.5, PI * 0.08, PI * 0.9, 16, Color("080808", 0.8), 1, true)
	graphic.draw_circle(Vector2.ZERO, 2, Color("aaa9a5"), true, -1, true)


func _draw_heading() -> void:
	for tick in 72:
		var bearing := tick * 5.0
		var direction := Vector2.UP.rotated(deg_to_rad(bearing - _dial_value))
		var major := tick % 6 == 0
		var middle := tick % 3 == 0
		graphic.draw_line(direction * (84 if major else (89 if middle else 92)), direction * 98, DIAL_INK if major else DIAL_MINOR, 2 if major else 1, true)
		if major:
			var caption: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(int(bearing), "%02d" % int(bearing / 10))
			_text(graphic, caption, direction * 70, 17, ACCENT if tick % 18 == 0 else DIAL_INK)
	graphic.draw_colored_polygon(PackedVector2Array([Vector2(-6, -104), Vector2(6, -104), Vector2(0, -94)]), ACCENT)
	graphic.draw_line(Vector2(0, -32), Vector2(0, 32), Color("181818"), 6, true)
	graphic.draw_polyline(PackedVector2Array([Vector2(-30, 9), Vector2(0, -7), Vector2(30, 9)]), Color("181818"), 6, true)
	graphic.draw_line(Vector2(-12, 27), Vector2(12, 27), Color("181818"), 6, true)
	graphic.draw_line(Vector2(0, -32), Vector2(0, 32), ACCENT, 3, true)
	graphic.draw_polyline(PackedVector2Array([Vector2(-30, 9), Vector2(0, -7), Vector2(30, 9)]), ACCENT, 3, true)
	graphic.draw_line(Vector2(-12, 27), Vector2(12, 27), ACCENT, 3, true)


## Screen coordinates in the rolling horizon plane. Nose-up lowers the horizon; right bank rotates it left.
static func horizon_point(point: Vector2, pitch: float, bank: float) -> Vector2:
	return (point + Vector2(0, pitch * 2.0)).rotated(deg_to_rad(-bank))


static func _make_horizon_disc() -> PackedVector2Array:
	var circle := PackedVector2Array()
	for i in 96: circle.append(Vector2.RIGHT.rotated(float(i) / 96.0 * TAU) * 91)
	return circle


static func ground_polygon(pitch: float, bank: float, disc := PackedVector2Array()) -> PackedVector2Array:
	if disc.is_empty(): disc = _make_horizon_disc()
	var normal := Vector2.DOWN.rotated(deg_to_rad(-bank))
	var offset := pitch * 2.0
	var clipped := PackedVector2Array()
	var previous := disc[disc.size() - 1]
	var prev_distance := normal.dot(previous) - offset
	for current: Vector2 in disc:
		var distance := normal.dot(current) - offset
		if (distance >= 0) != (prev_distance >= 0):
			clipped.append(previous.lerp(current, prev_distance / (prev_distance - distance)))
		if distance >= 0: clipped.append(current)
		previous = current
		prev_distance = distance
	return clipped


func _draw_horizon() -> void:
	graphic.draw_circle(Vector2.ZERO, 91, SKY)
	var ground := ground_polygon(_pitch, _bank, _horizon_disc)
	if ground.size() >= 3: graphic.draw_colored_polygon(ground, EARTH)
	var offset := _pitch * 2.0
	if absf(offset) < 91:
		var half := sqrt(91.0 * 91.0 - offset * offset)
		graphic.draw_line(horizon_point(Vector2(-half, 0), _pitch, _bank), horizon_point(Vector2(half, 0), _pitch, _bank), INK, 2, true)
	for angle in range(-80, 81, 5):
		if angle == 0: continue
		var width := 27.0 if angle % 20 == 0 else (16.0 if angle % 10 == 0 else 8.0)
		var left := horizon_point(Vector2(-width, -angle * 2.0), _pitch, _bank)
		var right := horizon_point(Vector2(width, -angle * 2.0), _pitch, _bank)
		if maxf(left.length(), right.length()) < 75:
			graphic.draw_line(left, right, Color(INK, 0.85), 1, true)
			if angle % 20 == 0:
				var label_position := horizon_point(Vector2(width + 13, -angle * 2.0), _pitch, _bank)
				if label_position.length() < 73: _text(graphic, str(absi(angle)), label_position, 11, INK)
	graphic.draw_arc(Vector2.ZERO, 91, 0, TAU, 96, Color("080808", 0.65), 3, true)
	graphic.draw_arc(Vector2.ZERO, 90, PI * 1.12, PI * 1.88, 36, Color("050505", 0.48), 2, true)
	var bank_tip := Vector2.UP.rotated(deg_to_rad(-_bank))
	var bank_side := bank_tip.orthogonal() * 5
	graphic.draw_colored_polygon(PackedVector2Array([bank_tip * 92, bank_tip * 82 + bank_side, bank_tip * 82 - bank_side]), INK)
	# The fixed aircraft reference always stays centred, independent of the horizon.
	for side: float in [-1.0, 1.0]:
		graphic.draw_polyline(PackedVector2Array([Vector2(side * 54, 0), Vector2(side * 23, 0), Vector2(side * 17, 7)]), Color("181818"), 7, true)
		graphic.draw_polyline(PackedVector2Array([Vector2(side * 54, 0), Vector2(side * 23, 0), Vector2(side * 17, 7)]), ACCENT, 3, true)
	graphic.draw_circle(Vector2.ZERO, 4, ACCENT)


func _text(canvas: Control, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_font("font")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	canvas.draw_string(font, center + Vector2(-width * 0.5, font.get_ascent(font_size) * 0.5 - 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
