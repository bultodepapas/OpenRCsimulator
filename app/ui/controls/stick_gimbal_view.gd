# UI-15-UX-01: one transmitter gimbal drawn as a square: centre cross, live dot with a short fading trail, optional
# deadzone ring, measured envelope, requested target zone with an arrow, and a caption below. Presentation only.
# Coordinates are normalised: x −1 (left) … +1 (right), y −1 (forward / throttle FULL) … +1 (back / throttle LOW).
# Setters redraw only when a value changes beyond EPSILON; the trail is a fixed ring buffer (no per-frame allocation).
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")

const EPSILON := 0.002
const TRAIL_LENGTH := 10
## Half-size of a target zone, in normalised units.
const TARGET_HALF := 0.22
const NO_TARGET := Vector2(INF, INF)

## The Y axis is one-ended (radio throttle): its rest is LOW at the bottom, not the centre.
var one_ended_y := false:
	set(value):
		if one_ended_y != value:
			one_ended_y = value
			_request_redraw()
var caption := "":
	set(value):
		if caption != value:
			caption = value
			update_minimum_size()
			_request_redraw()
## Short end labels drawn inside a one-ended axis ("FULL" at the top, "LOW" at the bottom); already translated.
var end_labels := PackedStringArray()
## Requested-zone label drawn next to the target ("RIGHT", "LOW" …); already translated.
var target_label := "":
	set(value):
		if target_label != value:
			target_label = value
			_request_redraw()
var side := 220.0:
	set(value):
		if not is_equal_approx(side, value):
			side = value
			update_minimum_size()
			_request_redraw()
## Redraw requests since creation; tests use it to prove unchanged samples cost nothing.
var redraw_requests := 0

var _position := Vector2.ZERO
var _live := false
var _deadzone := 0.0
var _envelope := Rect2()
var _has_envelope := false
var _target := NO_TARGET
var _arrow_from := NO_TARGET
var _trail := PackedVector2Array()
var _trail_head := 0
var _trail_settled := true
var _fill_style := StyleBoxFlat.new()
var _line_style := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_trail.resize(TRAIL_LENGTH)
	_trail.fill(Vector2.ZERO)
	_line_style.draw_center = false


func _get_minimum_size() -> Vector2:
	var width := side
	if not caption.is_empty():
		var font := get_theme_font("font", "Label")
		width = maxf(width, font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1,
			get_theme_font_size("font_size", "SecondaryLabel")).x)
	return Vector2(width, side + _caption_height())


## The live stick position (normalised). `live` false draws a hollow dot: no channel known yet for this gimbal.
func set_stick(point: Vector2, live: bool = true) -> void:
	var clamped := point.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	var moved := not _close(clamped, _position)
	if moved or live != _live:
		if live and not _live:
			_trail.fill(clamped) # a newly live dot has no history yet
		_position = clamped
		_live = live
		_push_trail(clamped)
		_request_redraw()
	elif not _trail_settled:
		_push_trail(clamped) # let the trail collapse onto a still stick, then stop redrawing
		_request_redraw()


## Convenience for a one-ended Y axis: throttle amount 0 (LOW, bottom) … 1 (FULL, top).
static func throttle_to_y(amount: float) -> float:
	return 1.0 - 2.0 * clampf(amount, 0.0, 1.0)


func stick() -> Vector2:
	return _position


func is_live() -> bool:
	return _live


func set_deadzone(radius: float) -> void:
	var value := clampf(radius, 0.0, 1.0)
	if absf(value - _deadzone) > EPSILON:
		_deadzone = value
		_request_redraw()


## Measured min/max envelope in normalised coordinates; a zero-size side draws as a line.
func set_envelope(rect: Rect2) -> void:
	if not _has_envelope or not _close(rect.position, _envelope.position) or not _close(rect.size, _envelope.size):
		_envelope = rect
		_has_envelope = true
		_request_redraw()


func clear_envelope() -> void:
	if _has_envelope:
		_has_envelope = false
		_request_redraw()


func envelope() -> Rect2:
	return _envelope if _has_envelope else Rect2()


func has_envelope() -> bool:
	return _has_envelope


## Highlight the requested zone around `point`, with an arrow from `arrow_from` (NO_TARGET for no arrow).
func set_target(point: Vector2, arrow_from: Vector2 = NO_TARGET) -> void:
	if not _same_point(point, _target) or not _same_point(arrow_from, _arrow_from):
		_target = point
		_arrow_from = arrow_from
		_request_redraw()


func clear_target() -> void:
	set_target(NO_TARGET, NO_TARGET)
	target_label = ""


func target() -> Vector2:
	return _target


func has_target() -> bool:
	return _target != NO_TARGET


## The square gimbal area inside the control (the caption sits below it).
func box_rect() -> Rect2:
	var edge := maxf(1.0, minf(size.x, size.y - _caption_height()))
	return Rect2(Vector2((size.x - edge) * 0.5, 0.0), Vector2(edge, edge))


## Normalised → local pixels inside `box`.
static func to_local_point(normalized: Vector2, box: Rect2) -> Vector2:
	var inset := box.size.x * 0.08
	var inner := box.grow(-inset)
	return inner.position + (normalized.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0)) + Vector2.ONE) * 0.5 * inner.size


func dot_point() -> Vector2:
	return to_local_point(_position, box_rect())


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		update_minimum_size()
		queue_redraw()


func _draw() -> void:
	var box := box_rect()
	var radius := float(UiTheme.RADIUS)
	_rounded(box, Color(UiTheme.PANEL, 0.9), radius, true)
	_rounded(box, UiTheme.EDGE, radius, false, 1.0)
	var inner := box.grow(-box.size.x * 0.08)
	var grid := Color(UiTheme.EDGE, 0.55)
	var centre := to_local_point(Vector2.ZERO, box)
	# Centre cross; a one-ended axis has no centre detent, so its horizontal line is dashed.
	draw_line(Vector2(centre.x, inner.position.y), Vector2(centre.x, inner.end.y), grid, 1.0)
	if one_ended_y:
		draw_dashed_line(Vector2(inner.position.x, centre.y), Vector2(inner.end.x, centre.y), grid, 1.0, 6.0)
	else:
		draw_line(Vector2(inner.position.x, centre.y), Vector2(inner.end.x, centre.y), grid, 1.0)
	draw_rect(inner, Color(UiTheme.EDGE, 0.35), false, 1.0)
	if _deadzone > 0.0:
		draw_arc(centre, _deadzone * inner.size.x * 0.5, 0.0, TAU, 40, Color(UiTheme.TEXT_2, 0.45), 1.0, true)
	if _target != NO_TARGET:
		_draw_target(box)
	if _has_envelope:
		var a := to_local_point(_envelope.position, box)
		var b := to_local_point(_envelope.end, box)
		var env := Rect2(a, b - a).abs()
		draw_rect(env, Color(UiTheme.CRYSTAL, 0.10), true)
		draw_rect(env, Color(UiTheme.CRYSTAL, 0.70), false, 1.5)
	var font := get_theme_font("font", "Label")
	var small := get_theme_font_size("font_size", "SectionLabel")
	if one_ended_y and end_labels.size() >= 2:
		# An end label that names the current target is lit in the target colour instead of being drawn twice.
		var muted := get_theme_color("font_color", "SecondaryLabel")
		var lit := _target_color() if _target != NO_TARGET else muted
		draw_string(font, Vector2(inner.position.x + 4.0, inner.position.y + font.get_ascent(small) + 2.0), end_labels[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, lit if end_labels[0] == target_label else muted)
		draw_string(font, Vector2(inner.position.x + 4.0, inner.end.y - font.get_descent(small) - 2.0), end_labels[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, lit if end_labels[1] == target_label else muted)
	# Trail, oldest first and faintest.
	var dot_radius := maxf(5.0, box.size.x * 0.045)
	var accent := UiTheme.FOCUS
	if _live:
		for k in range(1, TRAIL_LENGTH):
			var older := _trail[(_trail_head + k - 1) % TRAIL_LENGTH]
			var newer := _trail[(_trail_head + k) % TRAIL_LENGTH]
			if not _close(older, newer):
				var alpha := float(k) / float(TRAIL_LENGTH) * 0.6
				draw_line(to_local_point(older, box), to_local_point(newer, box), Color(accent, alpha), maxf(2.0, dot_radius * 0.5), true)
	var dot := to_local_point(_position, box)
	if _live:
		draw_circle(dot, dot_radius, accent, true, -1.0, true)
		draw_circle(dot, dot_radius, UiTheme.ACCENT_INK, false, 1.5, true)
	else:
		draw_circle(dot, dot_radius, UiTheme.TEXT_2, false, 2.0, true)
	if not caption.is_empty():
		var body := get_theme_font_size("font_size", "SecondaryLabel")
		var baseline := box.end.y + 6.0 + font.get_ascent(body)
		draw_string(font, Vector2(0.0, baseline), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, body,
			get_theme_color("font_color", "SecondaryLabel"))


func _draw_target(box: Rect2) -> void:
	var zone_half := Vector2(TARGET_HALF, TARGET_HALF)
	var lo := (_target - zone_half).clamp(Vector2(-1.12, -1.12), Vector2(1.12, 1.12))
	var hi := (_target + zone_half).clamp(Vector2(-1.12, -1.12), Vector2(1.12, 1.12))
	var a := to_local_point(lo, box)
	var b := to_local_point(hi, box)
	# to_local_point clamps to ±1; widen the zone so a full-deflection target reaches the inner edge.
	if _target.x >= 0.99: b.x += box.size.x * 0.04
	if _target.x <= -0.99: a.x -= box.size.x * 0.04
	if _target.y >= 0.99: b.y += box.size.y * 0.04
	if _target.y <= -0.99: a.y -= box.size.y * 0.04
	var zone := Rect2(a, b - a).abs()
	var color := _target_color()
	_rounded(zone, Color(color, 0.18), 5.0, true)
	_rounded(zone, Color(color, 0.85), 5.0, false, 2.0)
	if _arrow_from != NO_TARGET and not _close(_arrow_from, _target):
		var start := to_local_point(_arrow_from, box)
		var tip := to_local_point(_target, box)
		var direction := (tip - start).normalized()
		var length := start.distance_to(tip)
		var head := minf(14.0, length * 0.35)
		var shaft_end := tip - direction * (head * 0.6 + box.size.x * 0.06)
		var arrow_tip := tip - direction * box.size.x * 0.06
		var arrow := Color(UiTheme.CAUTION, 0.9)
		draw_line(start + direction * box.size.x * 0.05, shaft_end, arrow, 3.0, true)
		var normal := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([arrow_tip, arrow_tip - direction * head + normal * head * 0.55,
			arrow_tip - direction * head - normal * head * 0.55]), arrow)
	if not target_label.is_empty() and not (one_ended_y and end_labels.has(target_label)):
		var font := get_theme_font("font", "Label")
		var small := get_theme_font_size("font_size", "SectionLabel")
		var text_size := font.get_string_size(target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small)
		# Beside the zone, across the arrow's line rather than on it: above a left/right zone, beside a
		# forward/back zone and below a centre zone; always inside the box.
		var anchor := Vector2(zone.get_center().x - text_size.x * 0.5, zone.end.y + 2.0)
		if absf(_target.x) >= 0.99:
			anchor.y = zone.position.y - text_size.y - 2.0
			if anchor.y < box.position.y + 2.0:
				anchor.y = zone.end.y + 2.0
		elif absf(_target.y) >= 0.99:
			anchor = Vector2(zone.end.x + 6.0, zone.get_center().y - text_size.y * 0.5)
		anchor = anchor.clamp(box.position + Vector2(2.0, 2.0), box.end - text_size - Vector2(2.0, 2.0))
		draw_string(font, anchor + Vector2(0.0, font.get_ascent(small)), target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small, color)


## Caution amber while the stick is away from the requested zone, the focus accent once it is inside.
func _target_color() -> Color:
	var reached := _live and absf(_position.x - _target.x) <= TARGET_HALF and absf(_position.y - _target.y) <= TARGET_HALF
	return UiTheme.FOCUS if reached else UiTheme.CAUTION


## One reusable StyleBoxFlat per kind; drawing never allocates a style.
func _rounded(rect: Rect2, color: Color, radius: float, filled: bool, width: float = -1.0) -> void:
	var style := _fill_style if filled else _line_style
	style.set_corner_radius_all(int(radius))
	if filled:
		style.bg_color = color
	else:
		style.border_color = color
		style.set_border_width_all(maxi(1, int(width)))
	draw_style_box(style, rect)


func _caption_height() -> float:
	if caption.is_empty():
		return 0.0
	var font := get_theme_font("font", "Label")
	return 6.0 + font.get_height(get_theme_font_size("font_size", "SecondaryLabel"))


## `_trail_head` is the oldest sample (the next to be overwritten); the newest is just before it.
func _push_trail(point: Vector2) -> void:
	_trail[_trail_head] = point
	_trail_head = (_trail_head + 1) % TRAIL_LENGTH
	_trail_settled = true
	for k in TRAIL_LENGTH:
		if not _close(_trail[k], point):
			_trail_settled = false
			break


func _request_redraw() -> void:
	redraw_requests += 1
	queue_redraw()


static func _close(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) <= EPSILON and absf(a.y - b.y) <= EPSILON


static func _same_point(a: Vector2, b: Vector2) -> bool:
	if a == NO_TARGET or b == NO_TARGET:
		return a == b
	return _close(a, b)
