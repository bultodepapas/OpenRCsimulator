# Shared interface tokens and named variations for the application shell.
# Font sizes are logical pixels at 1920x1080; UiScale selects a compact type set for smaller viewports.
extends RefCounted

const PANEL := Color("#111111")
const SIDEBAR := Color("#111111", 0.92)
const CARD := Color("#202020")
const TEXT := Color("#F2F2F2")
const TEXT_2 := Color("#C4C4C4")
const FOCUS := Color("#66FF16")
const CRYSTAL := Color("#C4FFB3")
const GLASS_EMISSION := Color("#3DFF0A")
const SURFACE_LIGHT := Color("#F0F0F0")
const EDGE := Color("#606060")
const BUTTON := {
	normal = Color("#292929"),
	hover = Color("#363636"),
	pressed = Color("#1D1D1D"),
	disabled = Color("#292929"),
}
const PRIMARY := {
	normal = Color("#08290F", 0.86),
	hover = Color("#0B3A14", 0.88),
	pressed = Color("#061E0B", 0.92),
	disabled = Color("#242A24"),
}
const PRIMARY_TEXT := Color("#E4FFDA")
const ACCENT_INK := Color("#111111")
const DANGER := {
	normal = Color("#8E3735"),
	hover = Color("#A44340"),
	pressed = Color("#762D2B"),
	disabled = Color("#563332"),
}
const DESTRUCTIVE := DANGER
const ERROR := Color("#F08D83")
const DISABLED_TEXT := Color("#B0B0B0")
const KEYCAP := { bg = Color("#252525"), edge = Color("#717171") }

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
static var _icon_cache := {}


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
	card.border_color = Color(SURFACE_LIGHT, 0.22)
	card.shadow_color = Color(0, 0, 0, 0.24)
	card.shadow_size = 8
	card.shadow_offset = Vector2(0, 3)
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
	_primary_button(theme, "PrimaryButton", SIZE.primary)

	theme.set_type_variation("CompactPrimaryButton", "PrimaryButton")
	_primary_button(theme, "CompactPrimaryButton", SIZE.button)
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
		box.border_color = CRYSTAL if state == "hover" and border_width > 0 else border
		theme.set_stylebox(state, type, box)
	theme.set_stylebox("hover_pressed", type, theme.get_stylebox("pressed", type))
	theme.set_font_size("font_size", type, _font_size(font_size))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(key, type, font_color)
	theme.set_color("font_disabled_color", type, disabled_font_color)
	if type == "Button":
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.set_border_width_all(FOCUS_WIDTH)
		focus.border_color = FOCUS
		# Keep the complete focus outline inside scrollable rows and viewport edges.
		focus.set_corner_radius_all(RADIUS)
		focus.set_expand_margin_all(0)
		theme.set_stylebox("focus", type, focus)


## Native edge, halo and focus remain above the decorative crystal underlay.
static func _primary_button(theme: Theme, type: String, font_size: int) -> void:
	_button(theme, type, PRIMARY, FOCUS, 1, font_size, PRIMARY_TEXT, DISABLED_TEXT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := theme.get_stylebox(state, type) as StyleBoxFlat
		box.border_color = Color(GLASS_EMISSION, 0.20 if state == "pressed" else 0.28) if state != "disabled" else EDGE
		box.border_width_top = 1
		box.border_blend = true
		box.set_corner_radius_all(12)
		if opaque_panels: box.bg_color.a = 1.0
		if state != "disabled":
			box.shadow_color = Color(GLASS_EMISSION, 0.16 if state == "hover" else 0.10)
			box.shadow_size = 8 if state == "hover" else (3 if state == "pressed" else 6)
	# Native side brackets sit inside the dark well, clear of the luminous wall and label ink.
	var focus := theme.get_stylebox("focus", "Button").duplicate() as StyleBoxFlat
	focus.border_color = CRYSTAL
	focus.set_expand_margin_all(-9.0)
	focus.set_corner_radius_all(3)
	focus.border_width_top = 0
	focus.border_width_bottom = 0
	theme.set_stylebox("focus", type, focus)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_disabled_color"]:
		theme.set_color(state, type, DISABLED_TEXT if state == "icon_disabled_color" else PRIMARY_TEXT)


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
		theme.set_color("selection_color", type, Color("#435C35"))
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
		var track := _box(Color("#707070") if item == "slider" else (CRYSTAL if item == "grabber_area_highlight" else FOCUS), 0)
		track.content_margin_top = 2.0
		track.content_margin_bottom = 2.0
		track.set_corner_radius_all(2)
		theme.set_stylebox(item, "HSlider", track)
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		var fill: Color = DISABLED_TEXT if state == "grabber_disabled" else (CRYSTAL if state == "grabber_highlight" else FOCUS)
		theme.set_icon(state, "HSlider", _svg_icon('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="24"><circle cx="10" cy="12" r="8" fill="#%s" stroke="#%s" stroke-width="2"/><circle cx="10" cy="12" r="2" fill="#%s"/></svg>' % [fill.to_html(false), PANEL.to_html(false), PANEL.to_html(false)]))
	# UI-35b (UI-30 VC-3): every focusable control shows the same inside outline, and toggles share one look.
	theme.set_stylebox("focus", "HSlider", theme.get_stylebox("focus", "Button"))
	for checked in [false, true]:
		for disabled in [false, true]:
			var state := ("checked" if checked else "unchecked") + ("_disabled" if disabled else "")
			theme.set_icon(state, "CheckButton", _svg_icon(_toggle_svg(checked, disabled)))
			theme.set_icon(state, "CheckBox", _svg_icon(_check_svg(checked, disabled)))
	for type in ["VScrollBar", "HScrollBar"]:
		var track := _box(Color(PANEL, 0.35), 0)
		track.set_content_margin_all(3)
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grabber := _box(FOCUS if state == "grabber_pressed" else Color(TEXT_2, 0.75 if state == "grabber_highlight" else 0.45), 0)
			grabber.set_content_margin_all(3)
			grabber.set_corner_radius_all(3)
			theme.set_stylebox(state, type, grabber)


## Small vector icons drawn at the current text scale, so they stay crisp at every canvas size.
static func _svg_icon(svg: String) -> ImageTexture:
	var key := "%s@%.3f" % [svg, text_scale]
	if not _icon_cache.has(key): # build() runs per screen; rasterize each icon once per text scale
		var bitmap := Image.new()
		bitmap.load_svg_from_string(svg, text_scale)
		_icon_cache[key] = ImageTexture.create_from_image(bitmap)
	return _icon_cache[key]


## The Settings pill, shared by every on/off switch.
static func _toggle_svg(checked: bool, disabled: bool) -> String:
	var alpha := 0.45 if disabled else 1.0
	return '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="24" opacity="%.2f"><rect x="1" y="1" width="42" height="22" rx="11" fill="%s" stroke="%s"/><circle cx="%d" cy="12" r="7" fill="%s"/></svg>' \
		% [alpha, "#" + (FOCUS if checked else BUTTON.normal).to_html(false), "#" + (CRYSTAL if checked else DISABLED_TEXT).to_html(false), 32 if checked else 12, "#" + (ACCENT_INK if checked else TEXT).to_html(false)]


## A square check for multiple-choice lists (overlay sets, failure options).
static func _check_svg(checked: bool, disabled: bool) -> String:
	var alpha := 0.45 if disabled else 1.0
	var mark := '<path d="M6 12.5l4 4 8-9" fill="none" stroke="#%s" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>' % ACCENT_INK.to_html(false) if checked else ""
	return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" opacity="%.2f"><rect x="1.5" y="1.5" width="21" height="21" rx="5" fill="%s" stroke="%s" stroke-width="1.5"/>%s</svg>' \
		% [alpha, "#" + (FOCUS if checked else BUTTON.normal).to_html(false), "#" + (CRYSTAL if checked else DISABLED_TEXT).to_html(false), mark]


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
	panel.border_color = Color(SURFACE_LIGHT, 0.24)
	panel.shadow_color = Color(0, 0, 0, 0.42)
	panel.shadow_size = 24
	panel.shadow_offset = Vector2(0, 8)
	theme.set_stylebox("panel", "SettingsPanel", panel)
	theme.set_type_variation("SettingsAction", "Button")
	_primary_button(theme, "SettingsAction", SIZE.button)
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
		theme.set_icon("checked" if checked else "unchecked", "SettingsToggle", _svg_icon(_toggle_svg(checked, false)))


static func _home(theme: Theme) -> void:
	theme.set_type_variation("HomeSidebar", "PanelContainer")
	var surface := theme.get_stylebox("panel", "Sidebar").duplicate() as StyleBoxFlat
	surface.content_margin_top = 12
	surface.content_margin_bottom = 8
	theme.set_stylebox("panel", "HomeSidebar", surface)

	var quiet_row := {normal = Color.TRANSPARENT, hover = Color(BUTTON.hover, 0.78), pressed = Color(BUTTON.pressed, 0.92), disabled = Color.TRANSPARENT}
	theme.set_type_variation("HomeAction", "Button")
	_button(theme, "HomeAction", quiet_row, Color.TRANSPARENT, 0, SIZE.button, TEXT)
	# UI-33 (UI-30 HN-1): rows that cycle a value or open a dialog reserve room for their right-hand glyph.
	theme.set_type_variation("HomeChoice", "HomeAction")
	for state: StringName in theme.get_stylebox_list("HomeAction"):
		var reserved := theme.get_stylebox(state, "HomeAction").duplicate() as StyleBox
		reserved.content_margin_right = maxf(reserved.content_margin_right, 24.0)
		theme.set_stylebox(state, "HomeChoice", reserved)

	var nav := {normal = Color.TRANSPARENT, hover = Color(BUTTON.hover, 0.58), pressed = Color.TRANSPARENT, disabled = Color.TRANSPARENT}
	theme.set_type_variation("HomeNav", "Button")
	_button(theme, "HomeNav", nav, Color.TRANSPARENT, 0, SIZE.nav, TEXT_2)
	var selected_nav := _box(Color(FOCUS, 0.07), 10)
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
