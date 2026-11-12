# UI-15-UX-03 (component): one device in the Controls workspace's left rail, as a focusable toggle button. It draws a
# device icon (the family's face glyph on a drawn gamepad, or a drawn radio / joystick / keyboard), the display name
# (ellipsized; the full name stays in the tooltip and accessible description), the kind and status chips, and the
# selected state. Presentation only: the caller decides what is selected, connected or calibrated.
extends Button

const UiTheme := preload("res://ui/ui_theme.gd")

const KINDS: PackedStringArray = ["radio", "gamepad", "joystick", "keyboard"]
const KIND_NAMES := { radio = "Radio", gamepad = "Gamepad", joystick = "Joystick", keyboard = "Keyboard" }
## Status chips in display order; "needs_setup" is the only caution chip.
const STATUSES: PackedStringArray = ["connected", "disconnected", "calibrated", "needs_setup", "flight", "menus"]
const STATUS_NAMES := {
	connected = "Connected", disconnected = "Disconnected", calibrated = "Calibrated", needs_setup = "Needs setup",
	flight = "Flight", menus = "Menus",
}
const ICON_SIZE := 46.0
const PADDING := 14.0
const CHIP_GAP := 6.0

var display_name := "":
	set(value):
		if display_name != value:
			display_name = value
			_refresh()
var kind := "gamepad":
	set(value):
		var next := value if value in KINDS else "gamepad"
		if kind != next:
			kind = next
			_refresh()
## Glyph family for a gamepad icon: auto, xbox, playstation, nintendo or generic (presentation only).
var family := "generic":
	set(value):
		if family != value:
			family = value
			_refresh()
## Redraw requests since creation (tests).
var redraw_requests := 0

var _statuses := PackedStringArray()
var _name_line := TextLine.new()
var _kind_text := ""
var _chip_texts := PackedStringArray()
var _glyph: Texture2D
var _card_styles := {}
var _chip_style := StyleBoxFlat.new()
var _laid_width := -1.0
var _name_truncated := false


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	text = ""
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	_chip_style.set_corner_radius_all(5)
	_chip_style.set_border_width_all(1)
	_chip_style.anti_aliasing = true
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(UiTheme.RADIUS + 3)
		style.set_border_width_all(1)
		var selected: bool = state in ["pressed", "hover_pressed"]
		style.bg_color = UiTheme.CARD.lerp(UiTheme.FOCUS, 0.07) if selected else (UiTheme.BUTTON.hover if state == "hover" else UiTheme.CARD)
		style.border_color = UiTheme.FOCUS if selected else (UiTheme.CRYSTAL if state == "hover" else Color(UiTheme.SURFACE_LIGHT, 0.18))
		if selected:
			style.border_width_left = 4
		style.set_content_margin_all(PADDING)
		_card_styles[state] = style
		add_theme_stylebox_override(state, style)
	toggled.connect(func(_on: bool) -> void: _refresh_accessibility(); _request_redraw())
	_refresh()


## Mark this card as the workspace's current device (the toggle's pressed state; no signal is emitted).
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)
	_refresh_accessibility()
	_request_redraw()


func is_selected() -> bool:
	return button_pressed


## Status ids from STATUSES (unknown ids are ignored; display order is fixed).
func set_statuses(ids: Variant) -> void:
	var next := PackedStringArray()
	for status in STATUSES:
		if (ids is Array or ids is PackedStringArray) and ids.has(status):
			next.append(status)
	if next != _statuses:
		_statuses = next
		_refresh()


func statuses() -> PackedStringArray:
	return _statuses


## The translated kind word ("Gamepad").
func kind_text() -> String:
	return _kind_text


## The translated chip words in display order.
func status_texts() -> PackedStringArray:
	return _chip_texts


## Name, kind and status as one sentence for assistive technology: "Xbox Wireless Controller, Gamepad, Connected".
func accessible_text() -> String:
	var parts := PackedStringArray([_shown_name(), _kind_text])
	parts.append_array(_chip_texts)
	return ", ".join(parts)


## Whether the drawn name is shortened with an ellipsis at the current width.
func name_is_truncated() -> bool:
	_layout_name()
	return _name_truncated


func _shown_name() -> String:
	return display_name if not display_name.strip_edges().is_empty() else tr("Unnamed device")


func _refresh() -> void:
	_kind_text = tr(KIND_NAMES.get(kind, "Gamepad"))
	_chip_texts = PackedStringArray()
	for status in _statuses:
		_chip_texts.append(tr(STATUS_NAMES[status]))
	_glyph = null
	if kind == "gamepad":
		var prompt := ControllerPrompts.prompt({"type": "button", "button": JOY_BUTTON_A}, family, {})
		var path := str(prompt.get("texture_path", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			_glyph = load(path) as Texture2D
	tooltip_text = _shown_name()
	_laid_width = -1.0
	_refresh_accessibility()
	custom_minimum_size = _card_minimum_size()
	_request_redraw()


func _refresh_accessibility() -> void:
	accessibility_name = accessible_text()
	accessibility_description = "%s (%s)" % [_shown_name(), tr("selected") if button_pressed else tr("not selected")]


## Button computes its own minimum size natively, so the card publishes it through custom_minimum_size.
func _card_minimum_size() -> Vector2:
	var font := _font()
	var title := _title_size()
	var small := _small_size()
	var height := PADDING * 2.0 + font.get_height(title) + 2.0 + font.get_height(small)
	var rows := _chip_rows(font, small)
	if rows > 0:
		height += 8.0 + rows * _chip_height(font, small) + (rows - 1) * CHIP_GAP
	return Vector2(240.0, maxf(height, ICON_SIZE + PADDING * 2.0))


## Chips wrap onto as many rows as the card's width needs (every status stays visible).
func _chip_rows(font: Font, font_size: int) -> int:
	if _statuses.is_empty():
		return 0
	var available := maxf(80.0, (size.x if size.x > 1.0 else 320.0) - _text_left() - PADDING)
	var rows := 1
	var x := 0.0
	for index in _statuses.size():
		var width := _chip_width(index, font, font_size)
		if x > 0.0 and x + width > available:
			rows += 1
			x = 0.0
		x += width + CHIP_GAP
	return rows


func _chip_width(index: int, font: Font, font_size: int) -> float:
	return font.get_string_size(_chip_texts[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14.0 		+ (12.0 if _statuses[index] == "connected" else 0.0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED, NOTIFICATION_THEME_CHANGED:
			_laid_width = -1.0
			var minimum := _card_minimum_size()
			if not minimum.is_equal_approx(custom_minimum_size):
				custom_minimum_size = minimum
			queue_redraw()
		NOTIFICATION_TRANSLATION_CHANGED:
			_refresh()


func _font() -> Font:
	return get_theme_font("font", "Label")


func _title_size() -> int:
	return get_theme_font_size("font_size", "SecondaryLabel") + 2


func _small_size() -> int:
	return get_theme_font_size("font_size", "SectionLabel")


func _chip_height(font: Font, font_size: int) -> float:
	return font.get_height(font_size) + 4.0


func _text_left() -> float:
	return PADDING + ICON_SIZE + 14.0 + (3.0 if button_pressed else 0.0)


func _layout_name() -> void:
	var width := maxf(10.0, size.x - _text_left() - PADDING)
	if is_equal_approx(width, _laid_width):
		return
	_laid_width = width
	_name_line.clear()
	_name_line.add_string(_shown_name(), _font(), _title_size())
	var natural := _name_line.get_size().x
	_name_line.width = width
	_name_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_truncated = natural > width + 0.5


func _draw() -> void:
	_layout_name()
	var font := _font()
	var small := _small_size()
	var left := _text_left()
	var top := PADDING
	var icon_rect := Rect2(Vector2(PADDING + (3.0 if button_pressed else 0.0), (size.y - ICON_SIZE) * 0.5), Vector2(ICON_SIZE, ICON_SIZE))
	_draw_icon(icon_rect)
	var name_color := UiTheme.TEXT if not disabled else UiTheme.DISABLED_TEXT
	_name_line.draw(get_canvas_item(), Vector2(left, top), name_color)
	top += _name_line.get_size().y + 2.0
	draw_string(font, Vector2(left, top + font.get_ascent(small)), _kind_text, HORIZONTAL_ALIGNMENT_LEFT,
		size.x - left - PADDING, small, UiTheme.TEXT_2)
	top += font.get_height(small) + 8.0
	var x := left
	var chip_h := _chip_height(font, small)
	for index in _statuses.size():
		var status := _statuses[index]
		var label := _chip_texts[index]
		var dot := status == "connected"
		var width := _chip_width(index, font, small)
		if x > left and x + width > size.x - PADDING:
			x = left
			top += chip_h + CHIP_GAP
		var color := _chip_color(status)
		_chip_style.bg_color = Color(color, 0.12)
		_chip_style.border_color = Color(color, 0.7)
		var chip := Rect2(Vector2(x, top), Vector2(width, chip_h))
		draw_style_box(_chip_style, chip)
		var text_x := x + 7.0
		if dot:
			draw_circle(Vector2(x + 11.0, chip.get_center().y), 3.5, color, true, -1.0, true)
			text_x += 12.0
		draw_string(font, Vector2(text_x, top + 2.0 + font.get_ascent(small)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, small,
			color if status in ["needs_setup", "connected"] else UiTheme.TEXT)
		x += width + CHIP_GAP


static func _chip_color(status: String) -> Color:
	match status:
		"connected", "calibrated":
			return UiTheme.FOCUS
		"needs_setup":
			return UiTheme.CAUTION
		"disconnected":
			return UiTheme.DISABLED_TEXT
	return UiTheme.TEXT_2


## A small drawn icon per kind; gamepads carry their family's bottom face glyph.
func _draw_icon(rect: Rect2) -> void:
	var ink := UiTheme.FOCUS if button_pressed else UiTheme.TEXT_2
	var centre := rect.get_center()
	var s := rect.size.x / 46.0
	var plate := Color("#161816")
	draw_circle(centre, rect.size.x * 0.5, plate, true, -1.0, true)
	draw_circle(centre, rect.size.x * 0.5, Color(ink, 0.45), false, 1.0, true)
	match kind:
		"gamepad":
			var body := Rect2(centre + Vector2(-15, -8) * s, Vector2(30, 15) * s)
			draw_rect(body.grow_individual(-6 * s, 0, -6 * s, 0), ink, false, 1.6)
			draw_arc(centre + Vector2(-9, 0) * s, 7.5 * s, PI * 0.5, PI * 1.5, 10, ink, 1.6, true)
			draw_arc(centre + Vector2(9, 0) * s, 7.5 * s, -PI * 0.5, PI * 0.5, 10, ink, 1.6, true)
			draw_line(centre + Vector2(-9, -7.5) * s, centre + Vector2(9, -7.5) * s, ink, 1.6, true)
			draw_line(centre + Vector2(-9, 7.5) * s, centre + Vector2(9, 7.5) * s, ink, 1.6, true)
			draw_line(centre + Vector2(-12, 0) * s, centre + Vector2(-6, 0) * s, ink, 1.6, true)
			draw_line(centre + Vector2(-9, -3) * s, centre + Vector2(-9, 3) * s, ink, 1.6, true)
			if _glyph != null:
				draw_texture_rect(_glyph, Rect2(centre + Vector2(4, -6) * s, Vector2(12, 12) * s), false, ink)
			else:
				draw_circle(centre + Vector2(10, 0) * s, 2.5 * s, ink, true, -1.0, true)
		"radio", "joystick":
			var case_rect := Rect2(centre + Vector2(-14, -9) * s, Vector2(28, 20) * s)
			draw_rect(case_rect, ink, false, 1.6)
			if kind == "radio":
				draw_line(centre + Vector2(-9, -9) * s, centre + Vector2(-13, -17) * s, ink, 1.6, true)
				draw_circle(centre + Vector2(-7, 2) * s, 4 * s, ink, false, 1.4, true)
				draw_circle(centre + Vector2(7, 2) * s, 4 * s, ink, false, 1.4, true)
				draw_circle(centre + Vector2(-7, 2) * s, 1.4 * s, ink, true, -1.0, true)
				draw_circle(centre + Vector2(7, 2) * s, 1.4 * s, ink, true, -1.0, true)
			else:
				draw_line(centre + Vector2(0, -1) * s, centre + Vector2(0, -15) * s, ink, 2.0, true)
				draw_circle(centre + Vector2(0, -15) * s, 3.2 * s, ink, true, -1.0, true)
		_:
			var board := Rect2(centre + Vector2(-16, -9) * s, Vector2(32, 18) * s)
			draw_rect(board, ink, false, 1.6)
			for row in 3:
				for column in 6:
					if row == 2 and column > 0 and column < 5:
						continue
					draw_rect(Rect2(board.position + Vector2(3 + column * 4.6, 3 + row * 4.4) * s, Vector2(3, 2.6) * s), ink)
			draw_line(board.position + Vector2(8, 15) * s, board.position + Vector2(24, 15) * s, ink, 1.6, true)


func _request_redraw() -> void:
	redraw_requests += 1
	queue_redraw()
