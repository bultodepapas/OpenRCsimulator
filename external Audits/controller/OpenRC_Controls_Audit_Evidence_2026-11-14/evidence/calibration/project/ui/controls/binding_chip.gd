# UI-15-UX-04/06 (component): one binding as a small chip for the action list and the conflict dialog. It shows the
# family glyph (ControllerPrompts, the vendored Kenney SVGs) and/or a physical label: a key cap for keyboard keys
# (named in the player's layout through key_labels.gd), "Axis 5 +" for axes, "Sa Up · Button 3" for radio switch
# positions, or a caller-supplied label. A conflict badge and a live-press glow are optional states.
# Presentation only: it never captures input or edits a binding. Setters redraw only on change.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")
const KeyLabels := preload("res://ui/key_labels.gd")
const KeyCap := preload("res://ui/key_cap.gd")

const PAD_X := 10.0
const PAD_Y := 4.0
const GLYPH_GAP := 6.0

## Action this chip belongs to, already translated ("Flaps down"); part of the accessible name.
var action_name := "":
	set(value):
		if action_name != value:
			action_name = value
			_refresh_accessibility()
## Another action uses the same control: an amber badge and "conflict" in the accessible name.
var conflict := false:
	set(value):
		if conflict != value:
			conflict = value
			_refresh_accessibility()
			_request_redraw()
## The bound control is held right now: the chip glows in the focus accent.
var live_pressed := false:
	set(value):
		if live_pressed != value:
			live_pressed = value
			_request_redraw()
## Physical keycode → label keycode used to name key caps (tests pass a fixed layout); see key_labels.gd.
var key_mapper := Callable()
## Redraw requests since creation (tests).
var redraw_requests := 0

var _binding := {}
var _family := "auto"
var _device_info := {}
var _profile := {}
var _label := ""
var _label_override := ""
var _texture: Texture2D
var _key := KEY_NONE
var _modifiers := PackedStringArray()
var _unbound := true
var _show_text_with_glyph := false
var _style := StyleBoxFlat.new()
var _cap_style := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_style.set_corner_radius_all(UiTheme.RADIUS)
	_style.set_border_width_all(1)
	_style.anti_aliasing = true
	_cap_style.set_corner_radius_all(4)
	_cap_style.set_border_width_all(1)
	_cap_style.border_width_bottom = 2
	_cap_style.bg_color = UiTheme.KEYCAP.bg
	_cap_style.border_color = UiTheme.KEYCAP.edge
	_refresh()


## Show `binding` ({"type": "button" | "axis" | "switch" | "key" | "unbound", …}) with the glyph family's prompt.
func set_binding(binding: Dictionary, family: String = "auto", device_info: Dictionary = {}, profile: Dictionary = {}) -> void:
	if binding == _binding and family == _family and device_info == _device_info and profile == _profile:
		return
	_binding = binding.duplicate(true)
	_family = family
	_device_info = device_info.duplicate(true)
	_profile = profile.duplicate(true)
	_refresh()


## Replace the computed text with a physical label from the caller ("Sa Up", "S1 > 60 %"); "" restores it.
func set_label(text: String) -> void:
	if text != _label_override:
		_label_override = text
		_refresh()


func label_text() -> String:
	return _label


func has_glyph() -> bool:
	return _texture != null


## Whether the label is drawn next to the glyph. A family glyph already names the control (LB, Y, Cross) and the
## text stays in the accessible name and tooltip; generic glyphs carry no letter, so they keep their text.
func shows_text() -> bool:
	return _texture == null or _show_text_with_glyph


func is_key() -> bool:
	return _key != KEY_NONE


func is_unbound() -> bool:
	return _unbound


func _refresh() -> void:
	_texture = null
	_key = KEY_NONE
	_modifiers = PackedStringArray()
	_show_text_with_glyph = false
	var type := str(_binding.get("type", "unbound"))
	_unbound = type == "unbound" or _binding.is_empty()
	if _unbound:
		_label = tr("Unbound")
	elif type == "key":
		var keycode := int(_binding.get("physical_keycode", 0))
		if keycode == 0:
			keycode = int(_binding.get("keycode", 0))
		_key = keycode as Key
		for modifier in ["ctrl", "alt", "shift", "meta"]:
			if bool(_binding.get(modifier, false)):
				_modifiers.append("Ctrl" if modifier == "ctrl" else modifier.capitalize())
		_label = _key_name(_key)
	else:
		var prompt := ControllerPrompts.prompt(_binding, _family, _device_info, _profile)
		_label = str(prompt.get("text", ""))
		var path := str(prompt.get("texture_path", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			_texture = load(path) as Texture2D
		_show_text_with_glyph = ControllerPrompts.resolve_family(_family, _device_info) == "generic"
	if not _label_override.is_empty():
		_label = _label_override
		_show_text_with_glyph = true
	_refresh_accessibility()
	update_minimum_size()
	_request_redraw()


func _key_name(key: Key) -> String:
	if key == KEY_NONE:
		return tr("Keyboard key")
	if KeyCap.ARROW_KEYS.has(key):
		return tr(KeyLabels.NAMES[key])
	return KeyLabels.label(key, key_mapper)


## "Flaps down: LB", "Flaps down: LB, conflict"; without an action name just the binding.
func accessible_text() -> String:
	var shown := _label
	if not _modifiers.is_empty():
		shown = "+".join(_modifiers) + "+" + _label
	var text := "%s: %s" % [action_name, shown] if not action_name.is_empty() else shown
	if conflict:
		text += ", " + tr("conflict")
	return text


func _refresh_accessibility() -> void:
	accessibility_name = accessible_text()
	tooltip_text = accessible_text()


func _get_minimum_size() -> Vector2:
	var font := get_theme_font("font", "Label")
	var font_size := _font_size()
	var height := maxf(font.get_height(font_size) + PAD_Y * 2.0, _glyph_edge() + PAD_Y)
	return Vector2(_content_width(font, font_size) + PAD_X * 2.0 + (8.0 if conflict else 0.0), height)


func _font_size() -> int:
	return get_theme_font_size("font_size", "SecondaryLabel")


func _glyph_edge() -> float:
	var font := get_theme_font("font", "Label")
	return roundf(font.get_height(_font_size()) * 1.25)


func _content_width(font: Font, font_size: int) -> float:
	if _key != KEY_NONE:
		var width := 0.0
		for modifier in _modifiers:
			width += _cap_width(modifier, font, font_size) + 4.0
		return width + (_glyph_edge() if KeyCap.ARROW_KEYS.has(_key) else _cap_width(_label, font, font_size))
	var text_width := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if _texture != null:
		return _glyph_edge() + (GLYPH_GAP + text_width if shows_text() else 0.0)
	return text_width


func _cap_width(text: String, font: Font, font_size: int) -> float:
	return maxf(_glyph_edge(), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 12.0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_THEME_CHANGED:
			update_minimum_size()
			queue_redraw()
		NOTIFICATION_TRANSLATION_CHANGED:
			_refresh()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var font_size := _font_size()
	var rect := Rect2(Vector2.ZERO, size)
	if conflict:
		rect.size.x -= 8.0
	if live_pressed:
		_style.bg_color = Color(UiTheme.FOCUS, 0.22)
		_style.border_color = UiTheme.FOCUS
		_style.shadow_color = Color(UiTheme.FOCUS, 0.35)
		_style.shadow_size = 6
	else:
		_style.bg_color = Color(UiTheme.BUTTON.normal, 0.0) if _unbound else UiTheme.BUTTON.normal
		_style.border_color = UiTheme.ERROR if conflict else (Color(UiTheme.EDGE, 0.7) if _unbound else UiTheme.EDGE)
		_style.shadow_size = 0
	draw_style_box(_style, rect)
	var ink := UiTheme.FOCUS if live_pressed else (UiTheme.DISABLED_TEXT if _unbound else UiTheme.TEXT)
	var x := PAD_X
	var centre_y := rect.size.y * 0.5
	var baseline := centre_y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	if _key != KEY_NONE:
		var cap_h := minf(rect.size.y - 6.0, _glyph_edge())
		for modifier in _modifiers:
			x = _draw_cap(x, centre_y, cap_h, modifier, font, font_size, ink) + 4.0
		if KeyCap.ARROW_KEYS.has(_key):
			var cap := Rect2(Vector2(x, centre_y - cap_h * 0.5), Vector2(_glyph_edge(), cap_h))
			draw_style_box(_cap_style, cap)
			_arrow(cap, str(KeyCap.ARROW_KEYS[_key]), ink)
		else:
			_draw_cap(x, centre_y, cap_h, _label, font, font_size, ink)
	else:
		if _texture != null:
			var edge := _glyph_edge()
			draw_texture_rect(_texture, Rect2(Vector2(x, centre_y - edge * 0.5), Vector2(edge, edge)), false, ink)
			x += edge + GLYPH_GAP
		if shows_text():
			draw_string(font, Vector2(x, baseline), _label, HORIZONTAL_ALIGNMENT_LEFT, maxf(4.0, rect.size.x - x - PAD_X * 0.5),
				font_size, ink)
	if conflict:
		var badge := Vector2(size.x - 9.0, 9.0)
		draw_circle(badge, 8.0, UiTheme.CAUTION, true, -1.0, true)
		draw_circle(badge, 8.0, UiTheme.ACCENT_INK, false, 1.5, true)
		var small := get_theme_font_size("font_size", "SectionLabel") - 4
		var mark_width := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		draw_string(font, Vector2(badge.x - mark_width * 0.5, badge.y + (font.get_ascent(small) - font.get_descent(small)) * 0.5),
			"!", HORIZONTAL_ALIGNMENT_LEFT, -1, small, UiTheme.ACCENT_INK)


func _draw_cap(x: float, centre_y: float, height: float, text: String, font: Font, font_size: int, ink: Color) -> float:
	var width := _cap_width(text, font, font_size)
	var cap := Rect2(Vector2(x, centre_y - height * 0.5), Vector2(width, height))
	draw_style_box(_cap_style, cap)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(cap.get_center().x - text_width * 0.5, centre_y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5 - 1.0),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	return cap.end.x


func _arrow(cap: Rect2, direction: String, ink: Color) -> void:
	var tip: Vector2 = {"left": Vector2(-1, 0), "right": Vector2(1, 0), "up": Vector2(0, -1), "down": Vector2(0, 1)}[direction]
	var centre := cap.get_center() - Vector2(0.0, 1.0)
	var r := minf(cap.size.x, cap.size.y) * 0.26
	var side := Vector2(-tip.y, tip.x)
	draw_colored_polygon(PackedVector2Array([centre + tip * r, centre - tip * r * 0.7 + side * r,
		centre - tip * r * 0.7 - side * r]), ink)


func _request_redraw() -> void:
	redraw_requests += 1
	queue_redraw()
