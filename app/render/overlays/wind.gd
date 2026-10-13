# O4 Wind (HUD-07): where the wind blows, seen from the pilot's station, and how strong it is.
extends "res://render/overlays/overlay_frame.gd"

const Units := preload("res://render/overlays/units.gd")
const Telemetry := preload("res://render/overlays/telemetry.gd")

const DIAL := 56.0
## Fixed text column: the box keeps its size when a gust's updraft line comes and goes (no jitter at 10 Hz).
const TEXT_WIDTH := 150.0

var dial: Control
var speed_label: Label
var detail_label: Label
var updraft_label: Label
## Screen angle of the downwind arrow (deg clockwise from up), NAN when calm.
var arrow_deg := NAN


func _init() -> void:
	super("wind", tr("Wind"))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	dial = Control.new()
	dial.name = "Dial"
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial.custom_minimum_size = Vector2(DIAL, DIAL)
	dial.draw.connect(_draw_dial)
	row.add_child(dial)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	texts.custom_minimum_size.x = TEXT_WIDTH
	row.add_child(texts)
	speed_label = text_label("–", VALUE_SIZE, UiTheme.TEXT)
	texts.add_child(speed_label)
	detail_label = text_label("", LABEL_SIZE, UiTheme.TEXT_2)
	detail_label.name = "From"
	texts.add_child(detail_label)
	updraft_label = text_label("", LABEL_SIZE, UiTheme.TEXT_2)
	updraft_label.name = "Updraft"
	texts.add_child(updraft_label)
	for line: Label in [detail_label, updraft_label]:
		line.custom_minimum_size.y = LABEL_SIZE * 1.4 # an empty line keeps its height


## t: Telemetry.compute() output or {}; view_heading_deg: where the pilot looks.
func refresh(t: Dictionary, view_heading_deg: float, system: String) -> void:
	if t.is_empty() or (float(t.wind_speed) < 0.05 and absf(float(t.wind_up)) < 0.05):
		arrow_deg = NAN
		speed_label.text = tr("Calm") if not t.is_empty() else "–"
		detail_label.text = ""
		updraft_label.text = ""
	else:
		arrow_deg = Telemetry.wind_arrow_deg(t.wind_from_deg, view_heading_deg) if is_finite(t.wind_from_deg) else NAN
		speed_label.text = Units.format(Units.speed(t.wind_speed, system))
		detail_label.text = tr("from %03d°") % (roundi(t.wind_from_deg) % 360) if is_finite(t.wind_from_deg) else ""
		updraft_label.text = tr("up %s") % Units.format(Units.vertical(t.wind_up, system), true) \
			if absf(float(t.wind_up)) >= 0.05 else ""
	dial.queue_redraw()


func _draw_dial() -> void:
	var c := Vector2(DIAL, DIAL) * 0.5
	var r := DIAL * 0.5 - 2.0
	dial.draw_arc(c, r, 0.0, TAU, 40, Color(UiTheme.TEXT_2, 0.6), 1.5)
	dial.draw_line(c + Vector2(0.0, -r), c + Vector2(0.0, -r + 5.0), UiTheme.TEXT_2, 2.0) # straight ahead
	if is_nan(arrow_deg):
		dial.draw_circle(c, 3.0, UiTheme.TEXT_2)
		return
	var dir := Vector2(sin(deg_to_rad(arrow_deg)), -cos(deg_to_rad(arrow_deg)))
	var tip := c + dir * (r - 4.0)
	var tail := c - dir * (r - 8.0)
	dial.draw_line(tail, tip, UiTheme.TEXT, 3.0)
	var side := Vector2(-dir.y, dir.x)
	dial.draw_colored_polygon(PackedVector2Array([tip + dir * 2.0, tip - dir * 9.0 + side * 6.0, tip - dir * 9.0 - side * 6.0]), UiTheme.TEXT)
