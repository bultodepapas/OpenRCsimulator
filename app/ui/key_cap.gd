# A keyboard key drawn as a key (Theme variation "KeyCap"), for the Home controls legend. Arrow keys are drawn as
# triangles: the engine's default font has no arrow glyphs (U+2190-2193), and a system fallback would make the
# picture differ between machines.
extends PanelContainer

const ARROWS := ["left", "right", "up", "down"]


## A key cap showing `key`: "left", "right", "up", "down" (drawn) or a key label such as "A" (never translated).
static func make(key: String) -> PanelContainer:
	var cap: PanelContainer = load("res://ui/key_cap.gd").new()
	cap.theme_type_variation = "KeyCap"
	cap.custom_minimum_size = Vector2(32, 30)
	if key in ARROWS:
		var arrow := Arrow.new()
		arrow.direction = key
		cap.add_child(arrow)
	else:
		var label := Label.new()
		label.text = key
		label.theme_type_variation = "KeyLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cap.add_child(label)
	return cap


class Arrow extends Control:
	var direction := "up"

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.32
		var tip := { left = Vector2(-1, 0), right = Vector2(1, 0), up = Vector2(0, -1), down = Vector2(0, 1) }[direction] as Vector2
		var side := Vector2(-tip.y, tip.x)
		var points := PackedVector2Array([c + tip * r, c - tip * r * 0.7 + side * r, c - tip * r * 0.7 - side * r])
		draw_colored_polygon(points, get_theme_color("font_color", "KeyLabel"))
