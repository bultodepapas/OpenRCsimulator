# A keyboard key drawn as a key (Theme variation "KeyCap"), for the Home controls legend. Arrow keys are drawn as
# triangles: the engine's default font has no arrow glyphs (U+2190-2193), and a system fallback would make the
# picture differ between machines.
extends PanelContainer

const KeyLabels = preload("res://ui/key_labels.gd")
const ARROWS := ["left", "right", "up", "down"]
const ARROW_KEYS := { KEY_LEFT: "left", KEY_RIGHT: "right", KEY_UP: "up", KEY_DOWN: "down" }
const ARROW_NAMES := { "left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN }

var _arrow_keycap := false
var _physical_key: Key = KEY_NONE
var _key_mapper := Callable()


## A key cap for a PHYSICAL key: arrows drawn, others named as the player's layout prints them (ui/key_labels.gd).
static func for_key(physical: Key, mapper := Callable()) -> PanelContainer:
	if ARROW_KEYS.has(physical):
		return make(ARROW_KEYS[physical])
	var cap := make(KeyLabels.label(physical, mapper))
	cap.set("_physical_key", physical)
	cap.set("_key_mapper", mapper)
	return cap


## A key cap showing `key`: "left", "right", "up", "down" (drawn) or a key label such as "A" (never translated).
static func make(key: String) -> PanelContainer:
	var cap: PanelContainer = load("res://ui/key_cap.gd").new()
	cap.theme_type_variation = "KeyCap"
	cap.custom_minimum_size = Vector2(32, 30)
	if key in ARROWS:
		cap.set("_arrow_keycap", true)
		# Control translates this source name as the active locale changes.
		cap.accessibility_name = KeyLabels.NAMES[ARROW_NAMES[key]]
		var arrow := Arrow.new()
		arrow.direction = key
		arrow.keycap_decoration = true
		cap.add_child(arrow)
	else:
		var label := Label.new()
		label.text = key
		label.theme_type_variation = "KeyLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cap.add_child(label)
	return cap


func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE and _arrow_keycap:
		var element := get_accessibility_element()
		if element.is_valid():
			AccessibilityServer.update_set_role(element, AccessibilityServer.ROLE_STATIC_TEXT)
	elif what == NOTIFICATION_TRANSLATION_CHANGED:
		if _arrow_keycap:
			queue_accessibility_update()
		else:
			_refresh_physical_label()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_refresh_physical_label()


func _refresh_physical_label() -> void:
	if _physical_key != KEY_NONE and get_child_count() > 0 and get_child(0) is Label:
		get_child(0).text = KeyLabels.label(_physical_key, _key_mapper)


class Arrow extends Control:
	var direction := "up"
	# Arrow is also used directly by navigation buttons, where its accessibility belongs to that button.
	var keycap_decoration := false

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_ACCESSIBILITY_UPDATE and keycap_decoration:
			var element := get_accessibility_element()
			if element.is_valid():
				AccessibilityServer.update_set_flag(element, AccessibilityServer.FLAG_HIDDEN, true)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.32
		var tip := { left = Vector2(-1, 0), right = Vector2(1, 0), up = Vector2(0, -1), down = Vector2(0, 1) }[direction] as Vector2
		var side := Vector2(-tip.y, tip.x)
		var points := PackedVector2Array([c + tip * r, c - tip * r * 0.7 + side * r, c - tip * r * 0.7 - side * r])
		draw_colored_polygon(points, get_theme_color("font_color", "KeyLabel"))
