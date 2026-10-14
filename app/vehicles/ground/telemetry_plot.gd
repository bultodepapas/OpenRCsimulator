## Read-only short suspension history; samples are tied to accepted simulation ticks.
extends Control
var samples: Array[PackedFloat64Array] = []
var last_tick := -1
const COLORS := [Color("79efd0"), Color("f4d183"), Color("85aaff"), Color("f29ac4")]

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(300, 120)

func observe(tick: int, travel: PackedFloat64Array) -> void:
	if tick < last_tick:
		samples.clear()
	if tick == last_tick or travel.size() != 4:
		return
	last_tick = tick
	samples.append(travel.duplicate())
	if samples.size() > 240: samples.pop_front()
	queue_redraw()

func clear_history() -> void:
	samples.clear()
	last_tick = -1
	queue_redraw()

func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	var left := 8.0
	var top := 25.0
	var height := size.y - 38.0
	var width := size.x - 16.0
	var font := ThemeDB.fallback_font
	for i in 4:
		draw_string(font, Vector2(8 + i * 29, 17), ["FL", "FR", "RL", "RR"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLORS[i])
	draw_string(font, Vector2(135, 17), "-70 … +50 mm", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e7e5df"))
	var zero := top + height * 0.05 / 0.12
	draw_line(Vector2(left, zero), Vector2(left + width, zero), Color(0.7, 0.8, 0.8, 0.35))
	if samples.size() < 2: return
	for wheel in 4:
		var points := PackedVector2Array()
		for i in samples.size():
			points.append(Vector2(left + width * float(i) / 239.0, top + height * (0.05 - samples[i][wheel]) / 0.12))
		draw_polyline(points, COLORS[wheel], 1.5, true)

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.11, 0.84)
	return style
