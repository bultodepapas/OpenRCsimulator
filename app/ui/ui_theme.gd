# The interface Theme, built in code (MENU-PLAN §7/§8, research 17): colours stay readable hex in git, and a
# saved .tres would change 16 lines between two identical saves (random sub-resource ids).
# Sizes are logical pixels at the 1280x720 base; UI scaling (UI-09a) goes through Window.content_scale_factor.
# Contrast of every text/background and focus/background pair is checked on the resolved Theme by
# tests/test_ui_home.gd (targets: 4.5:1 text, 3:1 focus and control boundaries).
extends RefCounted

const PANEL := Color("#17252a") # opaque reading surface
const TEXT := Color("#f5f2e9") # 14.06:1 on PANEL
const TEXT_2 := Color("#bbc8c6") # secondary text, 9.13:1 on PANEL
const FOCUS := Color("#f5c65d") # keyboard focus outline, 9.83:1 on PANEL (drawn outside the control)
const BUTTON := { normal = Color("#2a3b41"), hover = Color("#354a51"), pressed = Color("#203038"), disabled = Color("#22313a") }
## Ugly Stik red. Only 2.61:1 on PANEL, so the Fly button never relies on it alone: cream label and cream border.
const PRIMARY := { normal = Color("#b6322e"), hover = Color("#a92d29"), pressed = Color("#932623"), disabled = Color("#5a2a28") }
const DISABLED_TEXT := Color("#8e9b99")

const SIZE := { title = 34, body = 18, small = 16, button = 20, primary = 24 }
const FOCUS_WIDTH := 3
const RADIUS := 6


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = SIZE.body # the engine's default font (Open Sans SemiBold, OFL) until UI-09c
	t.set_color("font_color", "Label", TEXT)

	var panel := _box(PANEL, 24)
	t.set_stylebox("panel", "PanelContainer", panel)

	_button(t, "Button", BUTTON, TEXT_2, 1, SIZE.button)
	# The primary action (Fly) as a type variation of Button: it inherits focus and font colours.
	t.set_type_variation("PrimaryButton", "Button")
	_button(t, "PrimaryButton", PRIMARY, TEXT, 2, SIZE.primary)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", SIZE.title)
	t.set_type_variation("SecondaryLabel", "Label")
	t.set_color("font_color", "SecondaryLabel", TEXT_2)
	t.set_font_size("font_size", "SecondaryLabel", SIZE.small)
	return t


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


## WCAG 2.x contrast ratio of two opaque sRGB colours (used by the Theme test).
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)
