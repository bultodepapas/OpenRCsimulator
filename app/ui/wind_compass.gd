# UI-40q (UI-40 CO-3): where the wind comes from, drawn over the runway. Field surfaces are axis-aligned and every
# runway runs east-west (data/field_loader.gd SURFACE_KEYS: length_east_west), so the bar is fixed; the runway start
# departs eastbound (physics/wind_config.gd GENTLE_PRACTICE). Presentation only: it shows the dialog's draft.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")

## Departure heading of the runway start, degrees true.
const RUNWAY_HEADING_DEG := 90.0

var speed_mps := 0.0
var from_deg := 0.0


func _init() -> void:
	name = "WindCompass"
	custom_minimum_size = Vector2(72.0, 72.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func set_wind(speed: float, from: float) -> void:
	var clean_speed := speed if is_finite(speed) and speed >= 0.0 else 0.0
	var clean_from := fposmod(from, 360.0) if is_finite(from) else 0.0
	if clean_speed == speed_mps and clean_from == from_deg:
		return
	speed_mps = clean_speed
	from_deg = clean_from
	queue_redraw()


## Components for the eastbound runway start: positive headwind, positive crosswind from the right.
static func components(speed: float, from: float) -> Vector2:
	var relative := deg_to_rad(from - RUNWAY_HEADING_DEG)
	return Vector2(speed * cos(relative), speed * sin(relative))


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 10.0
	if r <= 8.0:
		return
	var ring := Color(UiTheme.EDGE, 0.9)
	draw_arc(c, r, 0.0, TAU, 48, ring, 1.5, true)
	# Screen up is north; east is to the right, as on a map of the field.
	var runway_half := Vector2(r * 0.72, 0.0)
	draw_line(c - runway_half, c + runway_half, Color(UiTheme.TEXT_2, 0.55), 7.0)
	draw_line(c - runway_half, c + runway_half, Color(UiTheme.PANEL, 0.9), 1.0)
	var font := get_theme_default_font()
	var font_size := 12
	draw_string(font, c + Vector2(-4.0, -r - 1.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, UiTheme.TEXT_2)
	if speed_mps <= 0.0:
		draw_circle(c, 4.0, UiTheme.FOCUS)
		return
	var toward := Vector2(sin(deg_to_rad(from_deg)), -cos(deg_to_rad(from_deg))) # unit vector toward the source
	var tail := c + toward * r
	var tip := c - toward * (r * 0.25)
	draw_line(tail, tip, UiTheme.FOCUS, 3.0, true)
	var side := Vector2(-toward.y, toward.x)
	draw_colored_polygon(PackedVector2Array([tip - toward * 2.0, tip + toward * 11.0 + side * 7.0,
		tip + toward * 11.0 - side * 7.0]), UiTheme.FOCUS)
