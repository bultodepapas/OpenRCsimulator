extends Control
## UI-28-R5: shared loading bar for the brand intro and the flight loading surface.
## `value` is truthful: the owner sets it from completed preparation stages, never from elapsed time.
## Motion only signals activity: a sweep crosses the track and the fill eases toward the new value.
## Reduced motion shows the same value without sweep or easing.

const TRACK := Color(0.09, 0.17, 0.21)
const FILL_START := Color(0.04, 0.38, 0.50)
const FILL_END := Color(0.10, 0.72, 0.85)
const SHEEN := Color(0.70, 0.95, 1.0)

## Target fraction in [0, 1]. Monotonic: a lower value is ignored.
var value := 0.0:
	set(next):
		if is_finite(next):
			value = clampf(maxf(value, next), 0.0, 1.0)
			if reduced_motion:
				shown = value
			queue_redraw()
## Fraction currently drawn; eases toward `value`.
var shown := 0.0
var reduced_motion := false:
	set(enabled):
		reduced_motion = enabled
		if enabled:
			shown = value
		queue_redraw()
## False stops the sweep (for example after completion or while cancelling).
var active := true
var accent := FILL_END
var _clock := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 6.0)


func _process(delta: float) -> void:
	if reduced_motion or not is_visible_in_tree():
		return
	delta = minf(delta, 0.1) # A blocked frame must not jump the sweep or easing.
	_clock += delta
	shown = move_toward(shown, value, (value - shown) * minf(1.0, delta * 7.0) + delta * 0.03)
	queue_redraw()


## Advance part of the way to `limit` for one real sub-stage event; never reaches `limit`.
func nudge(limit: float, share := 0.12) -> void:
	if is_finite(limit) and limit > value:
		value = value + (minf(limit, 1.0) - value) * clampf(share, 0.0, 1.0)


func _draw() -> void:
	var bar := Rect2(Vector2.ZERO, size)
	if bar.size.x <= 0.0 or bar.size.y <= 0.0:
		return
	var radius := bar.size.y * 0.5
	_capsule(bar, TRACK, radius)
	var width := bar.size.x * clampf(shown, 0.0, 1.0)
	if width > 0.5:
		var fill := Rect2(bar.position, Vector2(maxf(width, bar.size.y), bar.size.y))
		var start := FILL_START.lerp(accent, 0.15)
		var left := fill.position.x + radius
		var right := fill.end.x - radius
		draw_circle(Vector2(left, fill.get_center().y), radius, start)
		draw_circle(Vector2(right, fill.get_center().y), radius, accent)
		if right > left:
			draw_polygon(PackedVector2Array([Vector2(left, fill.position.y), Vector2(right, fill.position.y),
				Vector2(right, fill.end.y), Vector2(left, fill.end.y)]), PackedColorArray([start, accent, accent, start]))
		if not reduced_motion:
			# Soft head glow: the leading edge reads as the place where work is happening.
			var pulse := 0.55 + 0.45 * sin(_clock * 4.2)
			var head := Vector2(fill.end.x, bar.get_center().y)
			for ring in 4:
				var extent := bar.size.y * (0.9 + ring * 0.85)
				draw_circle(head, extent, Color(accent, (0.10 - ring * 0.022) * pulse))
			draw_circle(head, bar.size.y * 0.62, Color(SHEEN, 0.85))
	if not reduced_motion and active:
		# One sweep every ~1.8 s across the whole track: activity, independent of the value.
		var travel := fmod(_clock / 1.8, 1.0)
		var band := maxf(bar.size.x * 0.16, bar.size.y * 6.0)
		var center := lerpf(-band, bar.size.x + band, travel)
		var lit := 0.30 if center > width else 0.55
		var left := clampf(center - band, 0.0, bar.size.x)
		var mid := clampf(center, 0.0, bar.size.x)
		var right := clampf(center + band, 0.0, bar.size.x)
		var top := bar.position.y + bar.size.y * 0.18
		var bottom := bar.end.y - bar.size.y * 0.18
		var clear := Color(SHEEN, 0.0)
		var bright := Color(SHEEN, lit)
		if mid > left:
			draw_polygon(PackedVector2Array([Vector2(left, top), Vector2(mid, top), Vector2(mid, bottom), Vector2(left, bottom)]),
				PackedColorArray([clear, bright, bright, clear]))
		if right > mid:
			draw_polygon(PackedVector2Array([Vector2(mid, top), Vector2(right, top), Vector2(right, bottom), Vector2(mid, bottom)]),
				PackedColorArray([bright, clear, clear, bright]))


func _capsule(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(Rect2(rect.position + Vector2(radius, 0.0), Vector2(maxf(0.0, rect.size.x - radius * 2.0), rect.size.y)), color)
	draw_circle(rect.position + Vector2(radius, radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.position.y + radius), radius, color)
