# HUD-13-R7: maneuver practice, glide monitoring and flight-scoped summary.
extends "res://render/overlays/player_instrument.gd"

const Metrics := preload("res://render/overlays/flight_metrics.gd")
const TRAINING_TITLES := {maneuver = "Maneuver meter", glide = "Glide monitor", flight_summary = "Flight summary"}
const TRAINING_ICONS := {maneuver = "engine", glide = "height", flight_summary = "speed"}
const HISTORY_SIZE := 60
const HISTORY_PERIOD_S := 0.5
const G_MIN := -4.0
const G_MAX := 8.0
var _face: Control
var _load := NAN
var _minimum_load := NAN
var _maximum_load := NAN
var _sink_history := PackedFloat32Array()
var _history_time := -INF
var _system := "metric"
var _distance_text := "—"
var _load_range_text := "—"


func _init(instrument_id: String) -> void:
	super(instrument_id, TRAINING_TITLES[instrument_id], TRAINING_ICONS[instrument_id])
	_face = Control.new()
	_face.name = "TrainingFace"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.show_behind_parent = true
	graphic.add_child(_face)
	_face.draw.connect(_draw_face)
	graphic.resized.connect(_face.queue_redraw)
	minimum_size_changed.connect(_queue_content_fit)
	_apply_density()
	match id:
		"maneuver": graphic.tooltip_text = tr("Body-axis load factor, not total acceleration. Flight extrema are sampled at 10 Hz.")
		"glide": graphic.tooltip_text = tr("Vertical speed history. Ground glide is distance over height lost, not aerodynamic L/D.")
		"flight_summary": graphic.tooltip_text = tr("Sampled statistics since flight reset, including time on the ground. Distance follows the ground track.")


func _apply_density() -> void:
	super()
	graphic.show()
	_separator.hide()
	match id:
		"maneuver": graphic.custom_minimum_size.y = 112 if _compact else 148
		"glide": graphic.custom_minimum_size.y = 80 if _compact else 108
		"flight_summary": graphic.custom_minimum_size.y = 86 if _compact else 104
	if _face != null: _face.queue_redraw()


func reset_flight() -> void:
	super()
	_sink_history.clear()
	_history_time = -INF


func refresh(t: Dictionary, system: String, peak: float, _battery: Dictionary, _fuel: Dictionary, _trims: Dictionary = {}, _rpm: float = NAN) -> void:
	refresh_training(t, system, peak, {})


func refresh_training(t: Dictionary, system: String, peak: float, metrics: Dictionary) -> void:
	var now := float(t.get("time_s", NAN))
	var vertical_speed := float(t.get("vertical_speed", NAN))
	var history_changed := false
	if id == "glide":
		if not is_finite(now) or not is_finite(vertical_speed) or now < _history_time or now - _history_time > 2.0:
			history_changed = not _sink_history.is_empty()
			_sink_history.clear()
			_history_time = -INF
		if is_finite(now) and is_finite(vertical_speed) and now - _history_time >= HISTORY_PERIOD_S:
			if _sink_history.size() == HISTORY_SIZE: _sink_history.remove_at(0)
			_sink_history.append(vertical_speed)
			_history_time = now
			history_changed = true
	_load = float(t.get("load_factor", NAN))
	_minimum_load = float(metrics.get("min_load_factor", NAN))
	_maximum_load = float(metrics.get("max_load_factor", NAN))
	var reading := "—"
	var unit := ""
	var detail := ""
	var left_title := ""
	var left_text := ""
	var right_title := ""
	var right_text := ""
	match id:
		"maneuver":
			reading = _signed(_load, 1)
			unit = "g"
			detail = "%s %s · AoA %s" % [tr("Bank"), Units.angle(float(t.get("bank_deg", NAN)), 0), Units.angle(float(t.get("alpha_deg", NAN)), 1)]
			if is_finite(_load) and (_load < G_MIN or _load > G_MAX): detail = tr("Scale exceeded") + " · " + detail
			left_title = tr("MIN LOAD")
			right_title = tr("MAX LOAD")
			left_text = _signed(_minimum_load, 1) + " g"
			right_text = _signed(_maximum_load, 1) + " g"
		"glide":
			var pair := Units.vertical(vertical_speed, system)
			unit = str(pair[1])
			reading = Units.format(pair, true).trim_suffix(" " + unit)
			var glide: Dictionary = Metrics.glide(t)
			match str(glide.glide_status):
				"gliding": detail = tr("Low throttle · ground glide")
				"powered": detail = tr("Reduce throttle to measure glide")
				"turning": detail = tr("Level the wings to measure glide")
				"slow": detail = tr("Too slow to measure glide")
				"not_descending": detail = tr("No descent to measure")
				_: detail = tr("Glide data unavailable")
			left_title = tr("GROUND GLIDE")
			left_text = _ratio(float(glide.ground_glide_ratio))
			right_title = tr("THROTTLE")
			var throttle := float(t.get("throttle", NAN))
			right_text = _number(throttle * 100.0, "%", 0)
		"flight_summary":
			reading = FlightData.clock(now) if is_finite(now) else "—"
			detail = tr("This flight · sampled statistics")
			_distance_text = Units.format(Units.length(float(metrics.get("distance_m", NAN)), system))
			if bool(metrics.get("distance_partial", false)):
				_distance_text += " *"
				detail = tr("* Distance excludes missing samples")
			_load_range_text = "%s / %s g" % [_signed(_minimum_load, 1), _signed(_maximum_load, 1)]
			left_title = tr("MAX AIRSPEED")
			left_text = Units.format(Units.speed(peak, system))
			right_title = tr("MAX AGL")
			right_text = Units.format(Units.length(float(metrics.get("max_height_agl", NAN)), system))
	var key: Array = [system, TranslationServer.get_locale(), reading, unit, detail, left_title, left_text, right_title, right_text, _distance_text, _load_range_text]
	if id == "maneuver":
		for value: float in [_load, _minimum_load, _maximum_load]: key.append(snappedf(value, 0.01) if is_finite(value) else null)
	if key == _view_key and not history_changed: return
	var face_changed: bool = _view_key.is_empty() or _view_key[0] != key[0] or _view_key[1] != key[1]
	if face_changed and _face != null: _face.queue_redraw()
	_view_key = key
	_system = system
	value_label.text = reading
	unit_label.text = unit
	subtitle.text = detail
	subtitle.tooltip_text = detail
	_details(left_title, left_text, right_title, right_text)
	if id != "glide" or history_changed or face_changed: graphic.queue_redraw()


static func _signed(value: float, decimals: int) -> String:
	if not is_finite(value): return "—"
	var rounded := snappedf(value, pow(10.0, -decimals))
	return ("+" if rounded > 0.0 else ("-" if rounded < 0.0 else "")) + String.num(absf(rounded), decimals).pad_decimals(decimals)


static func _ratio(value: float) -> String:
	return String.num(value, 1).pad_decimals(1) + " : 1" if is_finite(value) else "— : 1"


func _draw_face() -> void:
	var w := graphic.size.x
	var h := graphic.size.y
	match id:
		"maneuver":
			var c := Vector2(w / 2.0, h * 0.62)
			var r := minf(w * 0.40, h * 0.48)
			_face.draw_arc(c, r, deg_to_rad(-210), deg_to_rad(30), 64, Color(TRACK, 0.8), 8, true)
			for tick in range(-4, 9):
				var direction := _load_direction(float(tick))
				_face.draw_line(c + direction * (r - 7), c + direction * (r + 4), INK if tick == 1 else MUTED, 2 if tick == 1 else 1, true)
				if tick % 2 == 0: _face_text(str(tick), c + direction * (r + 15) + Vector2(0, 4), 11, MUTED, true)
			_face_text(tr("BODY LOAD"), c + Vector2(0, 21), 11, MUTED, true)
		"glide":
			for row in 3:
				var y := 15.0 + (h - 30) * row / 2.0
				_face.draw_line(Vector2(0, y), Vector2(w, y), Color(MUTED, 0.45) if row == 1 else Color(TRACK, 0.65), 1)
			_face_text("0", Vector2(1, h / 2 - 3), 10, MUTED)
		"flight_summary":
			_face_text(tr("TRACK DISTANCE"), Vector2(0, 14), 11, MUTED)
			_face.draw_line(Vector2(0, h * 0.55), Vector2(w, h * 0.55), TRACK, 1)
			_face_text(tr("LOAD MIN / MAX"), Vector2(0, h * 0.55 + 16), 11, MUTED)


func _draw_instrument() -> void:
	var w := graphic.size.x
	var h := graphic.size.y
	match id:
		"maneuver":
			if not is_finite(_load): return
			var c := Vector2(w / 2.0, h * 0.62)
			var r := minf(w * 0.40, h * 0.48)
			for extreme: float in [_minimum_load, _maximum_load]:
				if is_finite(extreme): graphic.draw_circle(c + _load_direction(extreme) * r, 3, Color(ACCENT, 0.65), true, -1, true)
			var direction := _load_direction(_load)
			var side := Vector2(-direction.y, direction.x)
			graphic.draw_colored_polygon(PackedVector2Array([c + direction * (r - 4), c - direction * 6 + side * 4, c - direction * 6 - side * 4]), ACCENT)
			graphic.draw_circle(c, 6, TRACK, true, -1, true)
			graphic.draw_circle(c, 3, INK, true, -1, true)
		"glide":
			if _sink_history.is_empty(): return
			var maximum := 1.0
			for value in _sink_history: maximum = maxf(maximum, absf(value))
			var points := PackedVector2Array()
			for i in _sink_history.size():
				points.append(Vector2(w * (HISTORY_SIZE - _sink_history.size() + i) / float(HISTORY_SIZE - 1), h / 2.0 - _sink_history[i] / maximum * (h / 2.0 - 20)))
			if points.size() > 1:
				graphic.draw_polyline(points, Color(ACCENT, 0.12), 5, true)
				graphic.draw_polyline(points, ACCENT, 1.8, true)
			graphic.draw_circle(points[-1], 2.5, INK, true, -1, true)
			_graphic_text("±" + Units.format(Units.vertical(maximum, _system)), Vector2(w, 10), MUTED, 11, HORIZONTAL_ALIGNMENT_RIGHT)
		"flight_summary":
			_graphic_text(_distance_text, Vector2(0, h * 0.55 - 9), INK, 24)
			_graphic_text(_load_range_text, Vector2(w, h - 3), ACCENT, 20, HORIZONTAL_ALIGNMENT_RIGHT)


static func _load_direction(value: float) -> Vector2:
	var angle := deg_to_rad(lerpf(-210.0, 30.0, inverse_lerp(G_MIN, G_MAX, clampf(value, G_MIN, G_MAX))))
	return Vector2(cos(angle), sin(angle))


func _face_text(value: String, point: Vector2, font_size: int, color: Color, centered := false) -> void:
	var font := get_theme_default_font()
	if centered: point.x -= font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2
	_face.draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
