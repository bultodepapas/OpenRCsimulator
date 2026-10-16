# Shared interface tokens and named variations for the application shell.
# Font sizes are logical pixels at 1920x1080; UiScale selects a compact type set for smaller viewports.
extends RefCounted

const PANEL := Color("#111A20")
const SIDEBAR := Color("#111A20", 0.92)
const CARD := Color("#1A272E")
const TEXT := Color("#F3F1EB")
const TEXT_2 := Color("#B8C4C9")
const FOCUS := Color("#EABF66")
const EDGE := Color("#52616A")
const BUTTON := {
	normal = Color("#26353D"),
	hover = Color("#33444C"),
	pressed = Color("#1C2930"),
	disabled = Color("#263238"),
}
const PRIMARY := {
	normal = Color("#EABF66"),
	hover = Color("#F2CC7E"),
	pressed = Color("#D8AA53"),
	disabled = Color("#B99455"),
}
const PRIMARY_TEXT := Color("#111A20")
const DANGER := {
	normal = Color("#8E3735"),
	hover = Color("#A44340"),
	pressed = Color("#762D2B"),
	disabled = Color("#563332"),
}
const DESTRUCTIVE := DANGER
const ERROR := Color("#F08D83")
const DISABLED_TEXT := Color("#A8B2B5")
const KEYCAP := { bg = Color("#223139"), edge = Color("#66767C") }

const SIZE := {
	brand = 48,
	header = 42,
	title = 38,
	card_title = 28,
	body = 26,
	small = 22,
	section = 18,
	button = 24,
	nav = 28,
	primary = 28,
	key = 18,
}
const FOCUS_WIDTH := 3
const RADIUS := 7
const COMPACT_FACTOR := 0.8461538462

static var text_scale := 1.0
static var opaque_panels := false
static var reduced_motion := false
static var compact_layout := false


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = _font_size(SIZE.body)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "RichTextLabel", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, 20))
	theme.set_type_variation("Sidebar", "PanelContainer")
	var sidebar := _box(Color(SIDEBAR, 1.0) if opaque_panels else SIDEBAR, 0)
	sidebar.set_corner_radius_all(0)
	sidebar.content_margin_left = 26
	sidebar.content_margin_right = 26
	sidebar.content_margin_top = 30
	sidebar.content_margin_bottom = 24
	theme.set_stylebox("panel", "Sidebar", sidebar)

	theme.set_type_variation("Card", "PanelContainer")
	var card := _box(CARD, 18)
	card.set_border_width_all(1)
	card.border_color = EDGE
	theme.set_stylebox("panel", "Card", card)

	theme.set_type_variation("Badge", "PanelContainer")
	var badge := StyleBoxFlat.new()
	badge.draw_center = false
	badge.set_border_width_all(1)
	badge.border_color = TEXT_2
	badge.set_corner_radius_all(4)
	badge.content_margin_left = 8
	badge.content_margin_right = 8
	badge.content_margin_top = 1
	badge.content_margin_bottom = 1
	theme.set_stylebox("panel", "Badge", badge)

	theme.set_type_variation("Notice", "PanelContainer")
	var notice := _box(CARD, 16)
	notice.set_border_width_all(1)
	notice.border_color = EDGE
	theme.set_stylebox("panel", "Notice", notice)

	theme.set_type_variation("KeyCap", "PanelContainer")
	var key := _box(KEYCAP.bg, 0)
	key.set_border_width_all(1)
	key.border_width_bottom = 3
	key.border_color = KEYCAP.edge
	key.set_corner_radius_all(5)
	key.content_margin_left = 8
	key.content_margin_right = 8
	key.content_margin_top = 2
	key.content_margin_bottom = 3
	theme.set_stylebox("panel", "KeyCap", key)

	_button(theme, "Button", BUTTON, EDGE, 1, SIZE.button)
	theme.set_type_variation("PrimaryButton", "Button")
	_button(theme, "PrimaryButton", PRIMARY, PRIMARY.normal, 0, SIZE.primary, PRIMARY_TEXT, PRIMARY_TEXT)
	for state in ["normal", "hover"]:
		var primary_box := theme.get_stylebox(state, "PrimaryButton") as StyleBoxFlat
		primary_box.shadow_color = Color(0, 0, 0, 0.24)
		primary_box.shadow_size = 4
		primary_box.shadow_offset = Vector2(0, 2)

	theme.set_type_variation("CompactPrimaryButton", "PrimaryButton")
	_button(theme, "CompactPrimaryButton", PRIMARY, PRIMARY.normal, 0, SIZE.button, PRIMARY_TEXT, PRIMARY_TEXT)
	theme.set_type_variation("DestructiveButton", "Button")
	_button(theme, "DestructiveButton", DESTRUCTIVE, DESTRUCTIVE.normal, 0, SIZE.button)

	_label(theme, "BrandLabel", TEXT, SIZE.brand)
	_label(theme, "HeaderLabel", TEXT, SIZE.header)
	_label(theme, "TitleLabel", TEXT, SIZE.title)
	_label(theme, "SectionTitle", TEXT, SIZE.card_title)
	_label(theme, "CardTitle", TEXT, SIZE.card_title)
	_label(theme, "SecondaryLabel", TEXT_2, SIZE.small)
	_label(theme, "SectionLabel", TEXT_2, SIZE.section)
	_label(theme, "ErrorLabel", ERROR, SIZE.small)
	_label(theme, "KeyLabel", TEXT, SIZE.key)
	_controls(theme)
	_settings(theme)
	_home(theme)
	return theme


static func _font_size(size: int, decorative: bool = false) -> int:
	var compact_size := float(size)
	if compact_layout:
		if size >= SIZE.card_title or size == SIZE.body:
			compact_size *= COMPACT_FACTOR
		elif size >= SIZE.button:
			compact_size *= 0.91
		else:
			compact_size *= 0.94
	var scale := text_scale
	if decorative:
		scale = minf(scale, 1.33)
	return maxi(1, roundi(compact_size * scale))


static func _label(theme: Theme, variation: String, color: Color, font_size: int) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_color("font_color", variation, color)
	theme.set_font_size("font_size", variation, _font_size(font_size))


static func _button(
	theme: Theme,
	type: String,
	backgrounds: Dictionary,
	border: Color,
	border_width: int,
	font_size: int,
	font_color: Color = TEXT,
	disabled_font_color: Color = DISABLED_TEXT,
) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := _box(backgrounds[state], 12)
		box.set_border_width_all(border_width)
		box.border_color = border
		theme.set_stylebox(state, type, box)
	theme.set_font_size("font_size", type, _font_size(font_size))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(key, type, font_color)
	theme.set_color("font_disabled_color", type, disabled_font_color)
	if type == "Button":
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.set_border_width_all(FOCUS_WIDTH)
		focus.border_color = FOCUS
		focus.set_corner_radius_all(RADIUS + FOCUS_WIDTH)
		focus.set_expand_margin_all(FOCUS_WIDTH + 1)
		theme.set_stylebox("focus", type, focus)


static func _controls(theme: Theme) -> void:
	_button(theme, "OptionButton", BUTTON, EDGE, 1, SIZE.button)
	for type in ["OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit"]:
		theme.set_stylebox("focus", type, theme.get_stylebox("focus", "Button"))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(key, type, TEXT)
		theme.set_color("font_disabled_color", type, DISABLED_TEXT)
	for type in ["LineEdit", "TextEdit"]:
		for state in ["normal", "read_only"]:
			var field := _box(BUTTON.normal, 10)
			field.set_border_width_all(1)
			field.border_color = EDGE
			theme.set_stylebox(state, type, field)
		theme.set_color("caret_color", type, FOCUS)
		theme.set_color("selection_color", type, Color("#43545B"))
	for type in ["PopupMenu", "TooltipPanel"]:
		theme.set_stylebox("panel", type, _box(PANEL, 12))
		theme.set_color("font_color", type, TEXT)
		theme.set_font_size("font_size", type, _font_size(SIZE.body))
	theme.set_stylebox("hover", "PopupMenu", _box(BUTTON.hover, 8))
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", DISABLED_TEXT)
	for type in ["TabBar", "TabContainer"]:
		for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
			var tab := _box(CARD if state == "tab_selected" else PANEL, 12)
			tab.border_width_bottom = 3 if state == "tab_selected" else 1
			tab.border_color = FOCUS if state == "tab_selected" else EDGE
			theme.set_stylebox(state, type, tab)
		for state in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
			theme.set_color(state, type, TEXT)
		theme.set_color("font_disabled_color", type, DISABLED_TEXT)
		theme.set_stylebox("tab_focus", type, theme.get_stylebox("focus", "Button"))
	theme.set_stylebox("panel", "TabContainer", _box(PANEL, 12))
	# A visible full track makes a slider's range readable even at low volume.
	for item: String in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track := _box(Color("#64737C") if item == "slider" else FOCUS, 0)
		track.content_margin_top = 2.0
		track.content_margin_bottom = 2.0
		track.set_corner_radius_all(2)
		theme.set_stylebox(item, "HSlider", track)


static func _box(color: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(RADIUS)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.6
	box.content_margin_bottom = padding * 0.6
	return box


## WCAG 2.x ratio; translucent surfaces are checked over both bright and dark surroundings.
static func contrast(a: Color, b: Color) -> float:
	if b.a < 1.0:
		return minf(contrast(a, Color.WHITE.lerp(Color(b, 1.0), b.a)), contrast(a, Color.BLACK.lerp(Color(b, 1.0), b.a)))
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(color: Color) -> float:
	var linear := func(value: float) -> float: return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)
	return 0.2126 * linear.call(color.r) + 0.7152 * linear.call(color.g) + 0.0722 * linear.call(color.b)


static func _settings(theme: Theme) -> void:
	_label(theme, "SettingsTitle", TEXT, SIZE.title)
	theme.set_font_size("font_size", "SettingsTitle", _font_size(SIZE.title, true))
	theme.set_type_variation("SettingsPanel", "PanelContainer")
	var panel := _box(Color(PANEL, 1.0 if opaque_panels else 0.97), 24)
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	panel.set_border_width_all(1)
	panel.border_color = EDGE
	panel.shadow_color = Color(0, 0, 0, 0.22)
	panel.shadow_size = 12
	theme.set_stylebox("panel", "SettingsPanel", panel)
	theme.set_type_variation("SettingsAction", "Button")
	_button(theme, "SettingsAction", PRIMARY, PRIMARY.normal, 0, SIZE.button, PRIMARY_TEXT, PRIMARY_TEXT)
	theme.set_stylebox("disabled", "SettingsAction", _box(BUTTON.disabled, 12))
	theme.set_color("font_disabled_color", "SettingsAction", DISABLED_TEXT)
	theme.set_type_variation("QuietButton", "Button")
	var quiet := {normal = Color.TRANSPARENT, hover = BUTTON.hover, pressed = BUTTON.pressed, disabled = Color.TRANSPARENT}
	_button(theme, "QuietButton", quiet, Color.TRANSPARENT, 0, SIZE.small)
	theme.set_type_variation("SettingsToggle", "CheckButton")
	for state in ["normal", "pressed", "disabled", "hover", "hover_pressed"]:
		theme.set_stylebox(state, "SettingsToggle", _box(BUTTON.hover if state.begins_with("hover") else Color.TRANSPARENT, 8))
	var separator := StyleBoxLine.new()
	separator.color = Color(EDGE, 0.45)
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	theme.set_constant("separation", "HSeparator", 12)

	for checked in [false, true]:
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="24"><rect x="1" y="1" width="42" height="22" rx="11" fill="%s" stroke="%s"/><circle cx="%d" cy="12" r="7" fill="%s"/></svg>' % ["#EABF66" if checked else "#26353D", "#EABF66" if checked else "#A8B2B5", 32 if checked else 12, "#111A20" if checked else "#F3F1EB"]
		var bitmap := Image.new()
		bitmap.load_svg_from_string(svg, text_scale)
		theme.set_icon("checked" if checked else "unchecked", "SettingsToggle", ImageTexture.create_from_image(bitmap))


static func _home(theme: Theme) -> void:
	theme.set_type_variation("HomeSidebar", "PanelContainer")
	var surface := theme.get_stylebox("panel", "Sidebar").duplicate() as StyleBoxFlat
	surface.content_margin_top = 12
	surface.content_margin_bottom = 8
	theme.set_stylebox("panel", "HomeSidebar", surface)

	var quiet_row := {normal = Color.TRANSPARENT, hover = Color(BUTTON.hover, 0.78), pressed = Color(BUTTON.pressed, 0.92), disabled = Color.TRANSPARENT}
	theme.set_type_variation("HomeAction", "Button")
	_button(theme, "HomeAction", quiet_row, Color.TRANSPARENT, 0, SIZE.button, TEXT)

	var nav := {normal = Color.TRANSPARENT, hover = Color(BUTTON.hover, 0.58), pressed = Color.TRANSPARENT, disabled = Color.TRANSPARENT}
	theme.set_type_variation("HomeNav", "Button")
	_button(theme, "HomeNav", nav, Color.TRANSPARENT, 0, SIZE.nav, TEXT_2)
	var selected_nav := _box(Color.TRANSPARENT, 10)
	selected_nav.border_width_bottom = 2
	selected_nav.border_color = FOCUS
	theme.set_stylebox("pressed", "HomeNav", selected_nav)
	theme.set_stylebox("hover_pressed", "HomeNav", selected_nav)
	theme.set_color("font_pressed_color", "HomeNav", FOCUS)
	theme.set_color("font_hover_pressed_color", "HomeNav", FOCUS)

	theme.set_type_variation("HomeTab", "Button")
	_button(theme, "HomeTab", nav, Color.TRANSPARENT, 0, SIZE.small, TEXT_2)
	theme.set_stylebox("pressed", "HomeTab", selected_nav)
	theme.set_stylebox("hover_pressed", "HomeTab", selected_nav)
	theme.set_color("font_pressed_color", "HomeTab", FOCUS)
	theme.set_color("font_hover_pressed_color", "HomeTab", FOCUS)
