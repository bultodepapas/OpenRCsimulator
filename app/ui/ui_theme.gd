# The interface Theme, built in code (MENU-PLAN §7/§8, research 17): colours stay readable hex in git, and a
# saved .tres would change 16 lines between two identical saves (random sub-resource ids).
# Sizes are logical pixels at the 1280x720 base; UI scaling (UI-09a) goes through Window.content_scale_factor.
# Contrast of every text/background and focus/background pair is checked on the resolved Theme by
# tests/test_ui_home.gd (targets: 4.5:1 text, 3:1 focus), over the worst sky behind translucent surfaces.
extends RefCounted

const PANEL := Color("#17252a") # reading surface
const SIDEBAR := Color("#17252a", 0.97) # Home's column: barely translucent (at 0.94 the horizon split it in two tones)
const CARD := Color("#203238") # a grouped block on the panel (next flight)
const TEXT := Color("#f5f2e9") # 14.06:1 on PANEL
const TEXT_2 := Color("#bbc8c6") # secondary text, 9.13:1 on PANEL
const FOCUS := Color("#f5c65d") # keyboard focus outline, 9.83:1 on PANEL (drawn outside the control)
const EDGE := Color("#40565c") # quiet outline of secondary controls; their label identifies them
const BUTTON := { normal = Color("#2a3b41"), hover = Color("#354a51"), pressed = Color("#203038"), disabled = Color("#22313a") }
## Ugly Stik red. Only 2.61:1 on PANEL: the cream label (5.38:1) identifies the Fly button, never the red alone.
const PRIMARY := { normal = Color("#b6322e"), hover = Color("#a92d29"), pressed = Color("#932623"), disabled = Color("#5a2a28") }
const DISABLED_TEXT := Color("#8e9b99")
const KEYCAP := { bg = Color("#22333a"), edge = Color("#5c7277") }

const SIZE := { title = 36, card_title = 22, body = 18, small = 16, section = 13, button = 19, primary = 26, key = 15 }
const FOCUS_WIDTH := 3
const RADIUS := 6


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = SIZE.body # the engine's default font (Open Sans SemiBold, OFL) until UI-09c
	t.set_color("font_color", "Label", TEXT)

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 24))
	t.set_type_variation("Sidebar", "PanelContainer")
	var sidebar := _box(SIDEBAR, 0)
	sidebar.set_corner_radius_all(0)
	sidebar.content_margin_left = 40
	sidebar.content_margin_right = 40
	sidebar.content_margin_top = 44
	sidebar.content_margin_bottom = 36
	t.set_stylebox("panel", "Sidebar", sidebar)
	t.set_type_variation("Card", "PanelContainer")
	var card := _box(CARD, 18)
	card.border_width_left = 4
	card.border_color = PRIMARY.normal # an accent, not information: the card's text says what it is
	t.set_stylebox("panel", "Card", card)
	t.set_type_variation("Badge", "PanelContainer")
	var badge := StyleBoxFlat.new()
	badge.draw_center = false
	badge.set_border_width_all(1)
	badge.border_color = TEXT_2
	badge.set_corner_radius_all(4)
	badge.content_margin_left = 8
	badge.content_margin_right = 8
	badge.content_margin_top = 1
	badge.content_margin_bottom = 1
	t.set_stylebox("panel", "Badge", badge)
	t.set_type_variation("KeyCap", "PanelContainer")
	var key := _box(KEYCAP.bg, 0)
	key.set_border_width_all(1)
	key.border_width_bottom = 3 # a key's front edge
	key.border_color = KEYCAP.edge
	key.set_corner_radius_all(5)
	key.content_margin_left = 8
	key.content_margin_right = 8
	key.content_margin_top = 2
	key.content_margin_bottom = 3
	t.set_stylebox("panel", "KeyCap", key)

	_button(t, "Button", BUTTON, EDGE, 1, SIZE.button)
	# The primary action (Fly) as a type variation of Button: it inherits focus and font colours.
	t.set_type_variation("PrimaryButton", "Button")
	_button(t, "PrimaryButton", PRIMARY, PRIMARY.normal, 0, SIZE.primary)
	for state in ["normal", "hover"]:
		var box := t.get_stylebox(state, "PrimaryButton") as StyleBoxFlat
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_size = 8
		box.shadow_offset = Vector2(0, 3)

	_label(t, "TitleLabel", TEXT, SIZE.title)
	_label(t, "CardTitle", TEXT, SIZE.card_title)
	_label(t, "SecondaryLabel", TEXT_2, SIZE.small)
	_label(t, "SectionLabel", TEXT_2, SIZE.section)
	_label(t, "KeyLabel", TEXT, SIZE.key)
	return t


static func _label(t: Theme, variation: String, color: Color, font_size: int) -> void:
	t.set_type_variation(variation, "Label")
	t.set_color("font_color", variation, color)
	t.set_font_size("font_size", variation, font_size)


static func _button(t: Theme, type: String, bg: Dictionary, border: Color, border_width: int, font_size: int) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := _box(bg[state], 14)
		box.set_border_width_all(border_width)
		box.border_color = border
		t.set_stylebox(state, type, box)
	t.set_font_size("font_size", type, font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, TEXT)
	t.set_color("font_disabled_color", type, DISABLED_TEXT)
	if type == "Button":
		# Keyboard focus: an amber outline outside the control, no fill (Godot 4.6+ hides it after mouse clicks).
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.set_border_width_all(FOCUS_WIDTH)
		focus.border_color = FOCUS
		focus.set_corner_radius_all(RADIUS + FOCUS_WIDTH)
		focus.set_expand_margin_all(FOCUS_WIDTH + 1)
		t.set_stylebox("focus", type, focus)


static func _box(color: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(RADIUS)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.6
	box.content_margin_bottom = padding * 0.6
	return box


## WCAG 2.x contrast ratio of two sRGB colours. A translucent background is composited over both white and black
## (the brightest and darkest sky or ground behind it) and the worse ratio is returned.
static func contrast(a: Color, b: Color) -> float:
	if b.a < 1.0:
		return minf(contrast(a, Color.WHITE.lerp(Color(b, 1.0), b.a)), contrast(a, Color.BLACK.lerp(Color(b, 1.0), b.a)))
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)
