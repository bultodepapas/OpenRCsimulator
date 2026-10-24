# HUD-13-R6: player navigation instruments, sharing the existing movable widget frame.
extends "res://render/overlays/player_instrument.gd"

const NAV_TITLES := {pilot_radar = "Pilot radar", wind_track = "Wind & drift", cruise_efficiency = "Cruise efficiency"}
const NAV_ICONS := {pilot_radar = "height", wind_track = "weather", cruise_efficiency = "power"}
const HISTORY_LIMIT := 60
const HISTORY_PERIOD := 0.5
var _face: Control
var _system := "metric"
var _north := NAN
var _east := NAN
var _heading := NAN
var _drift := NAN
var _range_m := 100.0
var _trail := PackedVector2Array()
var _trend := PackedFloat32Array()
var _history_time := -INF
var _efficiency := NAN
var _electric := false


func _init(instrument_id: String) -> void:
	super(instrument_id, NAV_TITLES[instrument_id], NAV_ICONS[instrument_id])
	_face = Control.new()
	_face.name = "NavigationFace"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	graphic.add_child(_face)
	_face.draw.connect(_draw_face)
	graphic.resized.connect(_face.queue_redraw)
	minimum_size_changed.connect(_queue_content_fit)
	_apply_density()
	graphic.tooltip_text = tr("North-up · aircraft position relative to the pilot") if id == "pilot_radar" else tr("White: nose heading · amber: ground track")
	if id == "cruise_efficiency": graphic.tooltip_text = tr("Rolling consumption per ground distance; not remaining range")


func _apply_density() -> void:
	super()
	graphic.show()
	graphic.custom_minimum_size.y = (150 if _compact else 190) if id == "pilot_radar" else ((120 if _compact else 156) if id == "wind_track" else (60 if _compact else 82))
	_separator.hide()
	if _face != null: _face.queue_redraw()


func reset_flight() -> void:
	super()
	_trail.clear()
	_trend.clear()
	_history_time = -INF


# Same interface as the other instruments; the manager supplies the shared efficiency reading separately.
func refresh(t: Dictionary, system: String, _peak: float, battery: Dictionary, _fuel: Dictionary, _trims: Dictionary = {}, _rpm: float = NAN) -> void:
	refresh_navigation(t, system, battery, {})


func refresh_navigation(t: Dictionary, system: String, battery: Dictionary, efficiency: Dictionary) -> void:
	_north = float(t.get("pilot_north_m", NAN))
	_east = float(t.get("pilot_east_m", NAN))
	_heading = float(t.get("heading_deg", NAN))
	_drift = float(t.get("drift_deg", NAN))
	_electric = bool(battery.get("valid", false))
	_efficiency = float(efficiency.get("efficiency_wh_km", NAN))
	var now := float(t.get("time_s", NAN))
	var history_changed := false
	if is_finite(now) and (now < _history_time or now - _history_time > 2.0):
		history_changed = not _trail.is_empty() or not _trend.is_empty()
		_trail.clear()
		_trend.clear()
		_history_time = -INF
	if id == "cruise_efficiency" and not is_finite(_efficiency):
		history_changed = history_changed or not _trend.is_empty()
		_trend.clear()
	if id == "pilot_radar" and (not is_finite(_north) or not is_finite(_east)):
		history_changed = history_changed or not _trail.is_empty()
		_trail.clear()
	if is_finite(now) and now - _history_time >= HISTORY_PERIOD:
		_history_time = now
		if id == "pilot_radar" and is_finite(_north) and is_finite(_east):
			var point := Vector2(_east, -_north)
			if _trail.is_empty() or _trail[-1].distance_to(point) >= 0.5:
				if _trail.size() >= HISTORY_LIMIT: _trail.remove_at(0)
				_trail.append(point)
				history_changed = true
		elif id == "cruise_efficiency" and is_finite(_efficiency):
			if _trend.size() >= HISTORY_LIMIT: _trend.remove_at(0)
			_trend.append(_efficiency)
			history_changed = true
	var fields: Array
	match id:
		"pilot_radar": fields = [_north, _east, _heading, t.get("height_agl")]
		"wind_track": fields = [_heading, _drift, t.get("ground_course_deg"), t.get("headwind_mps"), t.get("crosswind_mps"), is_finite(float(t.get("ground_speed", NAN))), float(t.get("ground_speed", NAN)) < 1.0]
		_: fields = [_efficiency, _electric, efficiency.get("status"), battery.get("power_w"), t.get("ground_speed")]
	var key: Array = [system, TranslationServer.get_locale()]
	for field: Variant in fields:
		key.append(null if field == null or (field is float and not is_finite(field)) else field)
	if key == _view_key and not history_changed: return
	var chart_changed: bool = history_changed or _view_key.is_empty() or _view_key[0] != key[0] or _view_key[1] != key[1]
	if _face != null and (_view_key.is_empty() or _view_key[1] != key[1]): _face.queue_redraw()
	_view_key = key
	_system = system
	match id:
		"pilot_radar":
			var distance := sqrt(_north * _north + _east * _east)
			_reading(Units.length(distance, system))
			_range_m = radar_range(distance)
			subtitle.text = tr("Pilot at centre · north up") if is_finite(distance) else tr("Position unavailable")
			_details(tr("RANGE RING"), Units.format(Units.length(_range_m, system)), "AGL", Units.format(Units.length(float(t.get("height_agl", NAN)), system)))
			value_label.tooltip_text = tr("Horizontal distance to the pilot, not the launch point")
		"wind_track":
			value_label.text = Units.angle(_drift, 0).trim_suffix("°")
			unit_label.text = "°"
			var course := float(t.get("ground_course_deg", NAN))
			var speed := float(t.get("ground_speed", NAN))
			subtitle.text = "%s %s · %s %s" % [tr("Heading"), Units.angle(_heading, 0, false), tr("Track"), Units.angle(course, 0, false)] if is_finite(course) else (tr("Track unavailable below 1 m/s") if is_finite(speed) and speed < 1.0 else tr("Ground track unavailable"))
			var headwind := float(t.get("headwind_mps", NAN))
			var crosswind := float(t.get("crosswind_mps", NAN))
			_details(tr("HEADWIND") if not is_finite(headwind) or headwind >= 0 else tr("TAILWIND"), Units.format(Units.speed(absf(headwind), system)), tr("WIND TO RIGHT") if not is_finite(crosswind) or crosswind >= 0 else tr("WIND TO LEFT"), Units.format(Units.speed(absf(crosswind), system)))
			value_label.tooltip_text = tr("Ground track minus nose heading; positive is right")
		"cruise_efficiency":
			var conversion := 1.609344 if system == "imperial" else 1.0
			value_label.text = String.num(_efficiency * conversion, 1).pad_decimals(1) if is_finite(_efficiency) else "—"
			unit_label.text = "Wh/mi" if system == "imperial" else "Wh/km"
			match str(efficiency.get("status", "power_unavailable")):
				"ready": subtitle.text = tr("10 s rolling window · lower uses less")
				"collecting": subtitle.text = tr("Collecting cruise data")
				"slow": subtitle.text = tr("Cruise above 3 m/s to measure")
				"speed_unavailable": subtitle.text = tr("Ground speed unavailable")
				_: subtitle.text = tr("Electric power telemetry unavailable")
			_details(tr("POWER"), _number(float(battery.get("power_w", NAN)), "W", 0), tr("GROUND"), Units.format(Units.speed(float(t.get("ground_speed", NAN)), system)))
			value_label.tooltip_text = tr("Rolling consumption per ground distance; not remaining range")
	subtitle.tooltip_text = subtitle.text
	if id != "cruise_efficiency" or chart_changed: graphic.queue_redraw()


static func radar_range(distance: float) -> float:
	if not is_finite(distance) or distance < 80.0: return 100.0
	var decade := pow(10.0, floor(log(distance / 0.8) / log(10.0)))
	for multiplier: float in [1.0, 2.0, 5.0, 10.0]:
		if decade * multiplier >= distance / 0.8: return decade * multiplier
	return decade * 10.0


func _geometry() -> Vector3:
	return Vector3(graphic.size.x / 2.0, graphic.size.y / 2.0, minf(graphic.size.x, graphic.size.y) / 2.0 - 17.0)


func _draw_face() -> void:
	var g := _geometry()
	var c := Vector2(g.x, g.y)
	var r := g.z
	if id == "cruise_efficiency":
		for row in 3:
			var y := 10.0 + (graphic.size.y - 20) * row / 2.0
			_face.draw_line(Vector2(0, y), Vector2(graphic.size.x, y), Color(TRACK, 0.65), 1)
		return
	_face.draw_circle(c, r + 3, Color("07121c"), true, -1, true)
	_face.draw_arc(c, r, 0, TAU, 64, Color(MUTED, 0.38), 1, true)
	_face.draw_arc(c, r * 0.5, 0, TAU, 48, Color(TRACK, 0.75), 1, true)
	for index in 24:
		var direction := Vector2(sin(index * TAU / 24), -cos(index * TAU / 24))
		_face.draw_line(c + direction * (r - (7 if index % 6 == 0 else 3)), c + direction * r, MUTED if index % 6 == 0 else TRACK, 1, true)
	_face.draw_line(c - Vector2(r - 10, 0), c + Vector2(r - 10, 0), Color(TRACK, 0.5), 1)
	_face.draw_line(c - Vector2(0, r - 10), c + Vector2(0, r - 10), Color(TRACK, 0.5), 1)
	if id == "pilot_radar":
		_face_text("N", c + Vector2(0, -r - 5), ACCENT)
		_face_text("E", c + Vector2(r + 10, 4), MUTED)
		_face_text("S", c + Vector2(0, r + 14), MUTED)
		_face_text("W", c + Vector2(-r - 10, 4), MUTED)
	else:
		_face_text(tr("NOSE"), c + Vector2(0, -r - 5), INK)
		_face.draw_line(c, c - Vector2(0, r - 8), INK, 2, true)
		_face.draw_circle(c, 3, INK, true, -1, true)


func _face_text(value: String, point: Vector2, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_face.draw_string(font, point - Vector2(width / 2, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_instrument() -> void:
	var g := _geometry()
	var c := Vector2(g.x, g.y)
	var r := g.z
	match id:
		"pilot_radar":
			graphic.draw_circle(c, 4, INK, true, -1, true)
			graphic.draw_arc(c, 7, 0, TAU, 24, Color(INK, 0.4), 1, true)
			if not is_finite(_north) or not is_finite(_east): return
			for i in range(1, _trail.size()):
				# Older points outside the current automatic range are omitted, never drawn off-panel.
				if _trail[i - 1].length() > _range_m or _trail[i].length() > _range_m: continue
				graphic.draw_line(c + _trail[i - 1] / _range_m * r, c + _trail[i] / _range_m * r, Color(ACCENT, 0.12 + 0.45 * i / _trail.size()), 1.5, true)
			var position_on_disc := c + Vector2(_east, -_north) / _range_m * r
			graphic.draw_line(c, position_on_disc, Color(ACCENT, 0.2), 1, true)
			if is_finite(_heading):
				_aircraft(position_on_disc, deg_to_rad(_heading))
			else:
				graphic.draw_circle(position_on_disc, 4, ACCENT, true, -1, true)
		"wind_track":
			if not is_finite(_drift): return
			var angle := deg_to_rad(_drift)
			var direction := Vector2(sin(angle), -cos(angle))
			var side := Vector2(-direction.y, direction.x)
			graphic.draw_line(c, c + direction * (r - 10), ACCENT, 2, true)
			graphic.draw_colored_polygon(PackedVector2Array([c + direction * (r - 5), c + direction * (r - 16) + side * 5, c + direction * (r - 16) - side * 5]), ACCENT)
			if absf(angle) > 0.01:
				graphic.draw_arc(c, r * 0.6, -PI / 2 + minf(0, angle), -PI / 2 + maxf(0, angle), 32, Color(ACCENT, 0.45), 2, true)
		"cruise_efficiency":
			if _trend.size() < 2: return
			var maximum := maxf(1.0, _trend[_trend.size() - 1])
			for value in _trend: maximum = maxf(maximum, value)
			var points := PackedVector2Array()
			for i in _trend.size():
				points.append(Vector2(graphic.size.x * (HISTORY_LIMIT - _trend.size() + i) / float(HISTORY_LIMIT - 1), graphic.size.y - 10 - _trend[i] / maximum * (graphic.size.y - 26)))
			graphic.draw_polyline(points, Color(ACCENT, 0.12), 5, true)
			graphic.draw_polyline(points, ACCENT, 1.8, true)
			graphic.draw_circle(points[-1], 2.5, INK, true, -1, true)
			_graphic_text("%s %s" % [String.num(maximum * (1.609344 if _system == "imperial" else 1.0), 1), "Wh/mi" if _system == "imperial" else "Wh/km"], Vector2(0, 10), MUTED, 11)


func _aircraft(at: Vector2, angle: float) -> void:
	# Small plan-view symbol; heading follows true yaw, position uses horizontal N/E offsets.
	var shape := PackedVector2Array([Vector2(0, -10), Vector2(2, -2), Vector2(9, 3), Vector2(9, 5), Vector2(2, 2), Vector2(2, 7), Vector2(5, 9), Vector2(5, 10), Vector2(0, 8), Vector2(-5, 10), Vector2(-5, 9), Vector2(-2, 7), Vector2(-2, 2), Vector2(-9, 5), Vector2(-9, 3), Vector2(-2, -2)])
	for i in shape.size(): shape[i] = at + shape[i].rotated(angle)
	graphic.draw_colored_polygon(shape, ACCENT)
