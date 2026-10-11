# UI-21: small builders shared by the existing screens. No default dimensions or translation policy are changed.
extends RefCounted

const UiTheme := preload("res://ui/ui_theme.gd")


static func label(text: String, variation: String, wrap := false, translate := true) -> Label:
	var control := Label.new()
	control.text = text
	control.theme_type_variation = variation
	if wrap:
		control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not translate:
		control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return control


static func button(text: String, variation := "", node_name := "") -> Button:
	var control := Button.new()
	control.text = text
	control.theme_type_variation = variation
	if node_name != "":
		control.name = node_name
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
	gradient.colors = PackedColorArray([UiTheme.SIDEBAR, Color(UiTheme.SIDEBAR, 0.0)])
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
