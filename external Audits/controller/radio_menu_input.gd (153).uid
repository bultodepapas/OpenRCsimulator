# UI-15-UX-01: one channel as a horizontal bar: label, track, fill from the centre (bidirectional, −1…+1) or from the
# left (one-ended, 0…1), centre mark, measured min/max endpoint ticks and a percent value. Presentation only.
# Setters redraw only when a value changes beyond EPSILON; drawing reuses its StyleBoxes and allocates nothing.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")

enum Highlight { IDLE, MOVING, ASSIGNED }

const EPSILON := 0.002
## Width reserved for the percent text, measured on this sample.
const PERCENT_SAMPLE := "+100%"

var one_ended := false:
	set(value):
		if one_ended != value:
			one_ended = value
			_request_redraw()
## Already translated, e.g. "Axis 3" or "Axis 3 · Roll".
var label := "":
	set(value):
		if label != value:
			label = value
			update_minimum_size()
			_request_redraw()
## Minimum label column width in pixels, so a column of bars aligns; the label's own width wins when larger.
var label_width := 0.0:
	set(value):
		if not is_equal_approx(label_width, value):
			label_width = value
			update_minimum_size()
			_request_redraw()
var track_width := 120.0:
	set(value):
		if not is_equal_approx(track_width, value):
			track_width = value
			update_minimum_size()
var highlight: Highlight = Highlight.IDLE:
	set(value):
		if highlight != value:
			highlight = value
			_request_redraw()
## Redraw requests since creation; tests use it to prove unchanged samples cost nothing.
var redraw_requests := 0

var _value := 0.0
var _min := 0.0
var _max := 0.0
var _has_endpoints := false
var _track_style := StyleBoxFlat.new()
var _fill_style := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_track_style.set_corner_radius_all(4)
	_track_style.set_border_width_all(1)
	_fill_style.set_corner_radius_all(3)


func set_value(value: float) -> void:
	var clamped := clampf(value, 0.0 if one_ended else -1.0, 1.0) if is_finite(value) else 0.0
	if absf(clamped - _value) > EPSILON:
		_value = clamped
		_request_redraw()


func current_value() -> float:
	return _value


## Measured endpoints in the bar's own range (−1…+1, or 0…1 when one-ended).
func set_endpoints(minimum: float, maximum: float) -> void:
	var lo := minf(minimum, maximum)
	var hi := maxf(minimum, maximum)
	if not _has_endpoints or absf(lo - _min) > EPSILON or absf(hi - _max) > EPSILON:
		_min = lo
		_max = hi
		_has_endpoints = true
		_request_redraw()


func clear_endpoints() -> void:
	if _has_endpoints:
		_has_endpoints = false
		_request_redraw()


func endpoints() -> Vector2:
	return Vector2(_min, _max) if _has_endpoints else Vector2(NAN, NAN)


## The value as the user reads it: "+45%" (bidirectional) or "45%" (one-ended).
func percent_text() -> String:
	var percent := roundi(_value * 100.0)
	return "%d%%" % percent if one_ended else "%+d%%" % percent


## Track rectangle in local pixels.
func track_rect() -> Rect2:
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "SecondaryLabel")
	var left := _label_column(font, font_size) + 10.0
	var right := font.get_string_size(PERCENT_SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 10.0
	var height := minf(size.y, maxf(10.0, font.get_height(font_size) * 0.55))
	return Rect2(Vector2(left, (size.y - height) * 0.5), Vector2(maxf(8.0, size.x - left - right), height))


## Value (in the bar's range) → local x on the track.
func value_to_x(v: float) -> float:
	var track := track_rect()
	var fraction := clampf(v, 0.0, 1.0) if one_ended else (clampf(v, -1.0, 1.0) + 1.0) * 0.5
	return track.position.x + fraction * track.size.x


func _get_minimum_size() -> Vector2:
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "SecondaryLabel")
	var percent := font.get_string_size(PERCENT_SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Vector2(_label_column(font, font_size) + 10.0 + track_width + 10.0 + percent, font.get_height(font_size) + 6.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		update_minimum_size()
		queue_redraw()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "SecondaryLabel")
	var muted := get_theme_color("font_color", "SecondaryLabel")
	var accent := _accent()
	var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var label_color := UiTheme.TEXT if highlight != Highlight.IDLE else muted
	draw_string(font, Vector2(0.0, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
	var track := track_rect()
	_track_style.bg_color = Color(UiTheme.BUTTON.normal, 1.0)
	_track_style.border_color = accent if highlight == Highlight.MOVING else UiTheme.EDGE
	draw_style_box(_track_style, track)
	var origin := track.position.x if one_ended else value_to_x(0.0)
	var tip := value_to_x(_value)
	var fill := Rect2(Vector2(minf(origin, tip), track.position.y + 2.0), Vector2(absf(tip - origin), track.size.y - 4.0))
	if fill.size.x >= 1.0:
		_fill_style.bg_color = accent
		draw_style_box(_fill_style, fill)
	if not one_ended:
		draw_line(Vector2(origin, track.position.y - 3.0), Vector2(origin, track.end.y + 3.0), UiTheme.TEXT_2, 1.0)
	if _has_endpoints:
		var lo_x := value_to_x(_min)
		var hi_x := value_to_x(_max)
		draw_line(Vector2(lo_x, track.position.y - 4.0), Vector2(lo_x, track.end.y + 4.0), UiTheme.CRYSTAL, 2.0)
		draw_line(Vector2(hi_x, track.position.y - 4.0), Vector2(hi_x, track.end.y + 4.0), UiTheme.CRYSTAL, 2.0)
	draw_string(font, Vector2(track.end.x + 10.0, baseline), percent_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		label_color)


func _accent() -> Color:
	match highlight:
		Highlight.MOVING:
			return UiTheme.FOCUS
		Highlight.ASSIGNED:
			return UiTheme.CRYSTAL
	return UiTheme.TEXT_2


func _label_column(font: Font, font_size: int) -> float:
	return maxf(label_width, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)


func _request_redraw() -> void:
	redraw_requests += 1
	queue_redraw()
