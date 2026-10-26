# UI-21: small builders shared by the existing screens. No default dimensions or translation policy are changed.
extends RefCounted

const UiTheme := preload("res://ui/ui_theme.gd")
const Crystal := preload("res://ui/crystal_surface.gd")


static func label(text: String, variation: String, wrap := false, translate := true) -> Label:
	var control := Label.new()
	control.text = text
	control.theme_type_variation = variation
	if wrap:
		control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not translate:
		control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return control


## GDU-11f: one-line headings may fit within theme bounds, never engine defaults.
## Call when the containing screen receives its theme/scale update.
static func fit_title(control: Label, minimum_size: int, maximum_size := -1) -> void:
	var maximum := maximum_size if maximum_size > 0 else control.get_theme_font_size("font_size")
	var minimum := clampi(minimum_size, 1, maximum)
	control.minimum_font_size = minimum
	control.maximum_font_size = maximum
	control.resize_font_to_fit = true
	control.autowrap_mode = TextServer.AUTOWRAP_OFF
	control.max_lines_visible = 1
	control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	control.clip_text = true
	# A VBox otherwise allocates only the minimum font's height, shrinking even short titles.
	var style := control.get_theme_stylebox("normal")
	control.custom_minimum_size.y = ceilf(control.get_theme_font("font").get_height(maximum)) + style.get_minimum_size().y


static func button(text: String, variation := "", node_name := "") -> Button:
	var control := Button.new()
	control.text = text
	control.theme_type_variation = variation
	if node_name != "":
		control.name = node_name
	Crystal.attach(control)
	return control


static func gap(height: int) -> Control:
	var control := Control.new()
	control.custom_minimum_size.y = height
	return control


static func button_row(separation := 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", separation)
	return row


static func sidebar_fade(width: int) -> TextureRect:
	var gradient := Gradient.new()
	# UI-35b (UI-30 AL-3): opaque panels continue into their fade.
	gradient.colors = PackedColorArray([Color(UiTheme.SIDEBAR, 1.0) if UiTheme.opaque_panels else UiTheme.SIDEBAR,
		Color(UiTheme.SIDEBAR, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 4
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rect.offset_left = width
	rect.offset_right = width + 32
	return rect


## UI-33 (UI-30 HN-1): what a Home row does when pressed. "cycle" changes its value in place (two small arrows);
## "open" opens a dialog or an editor (a chevron). Drawn in the secondary text colour, so no icon asset is needed.
class RowGlyph extends Control:
	var kind := "open"

	func _init(glyph_kind := "open") -> void:
		kind = glyph_kind
		name = "RowGlyph"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		offset_left = -22.0
		offset_right = -4.0
		offset_top = -9.0
		offset_bottom = 9.0

	func _draw() -> void:
		var color := get_theme_color("font_color", "SecondaryLabel")
		var c := size * 0.5
		var h := minf(size.y * 0.3, 5.0)
		if kind == "cycle":
			for side: float in [-1.0, 1.0]:
				var tip := c + Vector2(side * (h + 4.0), 0.0)
				var back := tip - Vector2(side * h * 1.2, 0.0)
				draw_colored_polygon(PackedVector2Array([tip, back + Vector2(0.0, -h), back + Vector2(0.0, h)]), color)
		else:
			draw_polyline(PackedVector2Array([c + Vector2(-h * 0.5, -h), c + Vector2(h * 0.5, 0.0), c + Vector2(-h * 0.5, h)]),
				color, 2.0, true)


static func mark_row(button: Button, kind: String) -> void:
	button.add_child(RowGlyph.new(kind))

