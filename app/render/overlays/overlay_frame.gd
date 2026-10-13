# One flight overlay (HUD-02/03): translucent theme backplate, a title and an X that closes only this overlay.
# The X never takes keyboard focus, so every flight key keeps working after a click.
extends PanelContainer

const UiTheme := preload("res://ui/ui_theme.gd")

signal close_requested(id: String)

## Backplate opacity: secondary text keeps ≥ 4.5:1 over a white sky (tests/test_overlay_manager.gd).
const BACKPLATE_ALPHA := 0.84
const TITLE_SIZE := 13
const LABEL_SIZE := 14
const VALUE_SIZE := 20

var id: String
var title_label: Label
var close_button: Button
var body: VBoxContainer


func _init(overlay_id: String, title: String) -> void:
	id = overlay_id
	name = overlay_id.capitalize().replace(" ", "") + "Overlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", backplate())
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	title_label = text_label(title.to_upper(), TITLE_SIZE, UiTheme.TEXT_2)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	close_button = close_x(func() -> void: close_requested.emit(id))
	header.add_child(close_button)
	body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 2)
	column.add_child(body)


static func backplate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTheme.PANEL, BACKPLATE_ALPHA)
	box.set_corner_radius_all(UiTheme.RADIUS)
	box.content_margin_left = 10
	box.content_margin_right = 6
	box.content_margin_top = 4
	box.content_margin_bottom = 8
	return box


## A small flat × button that never takes focus (mouse only; presets and keys are the keyboard path).
static func close_x(on_press: Callable) -> Button:
	var button := Button.new()
	button.name = "Close"
	button.text = "×"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Close"
	button.custom_minimum_size = Vector2(24, 22)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", UiTheme.TEXT_2)
	button.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(UiTheme.BUTTON.hover, 0.0 if state == "normal" else 0.9)
		box.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state, box)
	button.pressed.connect(on_press)
	return button


static func text_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # callers pass tr() text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## A [name, value] row grid; returns the value labels by key, in order.
func add_rows(rows: Array) -> Dictionary:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 0)
	body.add_child(grid)
	var values := {}
	for row: Array in rows:
		grid.add_child(text_label(row[1], LABEL_SIZE, UiTheme.TEXT_2))
		var value := text_label("–", VALUE_SIZE, UiTheme.TEXT)
		value.name = str(row[0]).capitalize().replace(" ", "")
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size.x = 112
		grid.add_child(value)
		values[row[0]] = value
	return values


static func monospace(font_size: int) -> Label:
	var label := text_label("", font_size, UiTheme.TEXT)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace"])
	label.add_theme_font_override("font", font)
	return label
