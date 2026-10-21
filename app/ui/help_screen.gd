# Help and about (MENU-PLAN §3/§7, step UI-04b). Opened from Home or from the pause menu; Esc or Close returns the
# focus to the button that opened it. Every key comes from ui/controls_reference.gd (the table the consistency test
# checks against the code) and is named as the player's keyboard layout prints it. The about block shows the build
# identity of UI-04a. While open it swallows every key the GUI leaves (like the pause menu). English source strings.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const Reference := preload("res://ui/controls_reference.gd")
const BuildInfo := preload("res://app_state/build_info.gd")

signal closed

const LAYER := 11 # above the pause menu
const REPOSITORY := "github.com/bultodepapas/OpenRCsimulator"

var close_button: Button
var about_label: Label
var field_conditions_label: Label
var radio_help_label: Label
var _vehicle_type := Reference.AIRPLANE
var _help_panel: PanelContainer
var _help_columns: BoxContainer
var _help_scroll: ScrollContainer
var _key_tables: Array[GridContainer] = []


func _init(return_focus: Control = null, vehicle_type: String = Reference.AIRPLANE) -> void:
	name = "Help"
	layer = LAYER
	_vehicle_type = Reference.ROTORCRAFT if vehicle_type == Reference.ROTORCRAFT else Reference.AIRPLANE
	var screen := Screen.mount(self)
	screen.return_focus = return_focus
	screen.close_requested.connect(close)
	screen.dim(0.55)
	var center: CenterContainer = screen.center(24.0)
	var panel := PanelContainer.new()
	_help_panel = panel
	panel.theme_type_variation = "Sidebar"
	center.add_child(panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 16)
	panel.add_child(shell)
	var scroll := ScrollContainer.new()
	_help_scroll = scroll
	scroll.follow_focus = true # keyboard focus must reach what scaling pushes out of view (research 11)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.gui_input.connect(_scroll_input)
	shell.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 1)
	scroll.add_child(page)

	var header := HBoxContainer.new()
	var title := _text("Help", "TitleLabel", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	# A full-width header line leaves room for the vehicle's startup/radio instructions.
	
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "Close"
	close_button.custom_minimum_size.x = 120
	close_button.pressed.connect(close)
	header.add_child(close_button)
	shell.add_child(header)
	shell.move_child(header, 0)
	page.add_child(_text("Keys are shown as your keyboard layout prints them.", "SecondaryLabel", true))

	var columns := BoxContainer.new()
	_help_columns = columns
	columns.add_theme_constant_override("separation", 48)
	page.add_child(columns)
	var left := _column(columns)
	left.add_child(_text("WHILE FLYING", "SectionLabel"))
	var right := _column(columns)
	right.add_theme_constant_override("separation", 5)
	right.add_child(_text("STICKS", "SectionLabel")) # UI-36 (UI-30 SC-4): not to be confused with WHILE FLYING
	if _vehicle_type == Reference.ROTORCRAFT:
		left.add_child(_key_table(Reference.shortcut_table(_vehicle_type), 2, 340))
		right.add_child(_key_table(Reference.flight_table(_vehicle_type)))
	else:
		# Keep the existing table widths and use compact row spacing so the complete reference fits at 720p.
		var pilot_rows: Array = Reference.SHORTCUTS.filter(func(row: Array) -> bool: return not (KEY_H in row[0] or KEY_J in row[0] or KEY_V in row[0] or KEY_F2 in row[0]))
		# UI-36 (UI-30 SC-4): recording and data-reload keys are tools, listed after what a pilot needs.
		left.add_child(_key_table(pilot_rows.filter(func(row: Array) -> bool: return not _is_developer_row(row))))
		left.add_child(_text("RECORDING AND DEVELOPER", "SectionLabel"))
		left.add_child(_key_table(pilot_rows.filter(_is_developer_row)))
		right.add_child(_key_table(Reference.flight_table(_vehicle_type)))
		right.add_child(_key_table(Reference.SHORTCUTS.filter(func(row: Array) -> bool: return KEY_H in row[0] or KEY_J in row[0] or KEY_V in row[0] or KEY_F2 in row[0]), 4, 145))
	right.add_child(_text("RADIO", "SectionLabel"))
	radio_help_label = _text("", "SecondaryLabel", true)
	radio_help_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_update_radio_help_text()
	right.add_child(radio_help_label)
	right.add_child(_text("RIGHT NOW", "SectionLabel"))
	field_conditions_label = _text("Choose a runway or airborne start on Home. Configure wind, gusts, turbulence and field air density before flying. Flight models are experimental.", "SecondaryLabel", true)
	field_conditions_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_update_field_conditions_text()
	right.add_child(field_conditions_label)

	if _vehicle_type == Reference.AIRPLANE:
		page.add_child(_text("Flight companions", "SectionLabel"))
		page.add_child(_text("Club field offers 1–3 experimental Ugly Stik companions flying circuits. They are Off by default; start with one. Open Flight companions under Home → More flight details or Pause → Session options.", "SecondaryLabel", true))
		page.add_child(_text("Apply changes sound and labels immediately. Flight settings take effect after Restart flight. Remove companions now clears the current roster; disable companions and Apply to keep them off after restarting. Aircraft-to-aircraft contact is disabled.", "SecondaryLabel", true))

	# About spans the body; the focusable scroll area exposes the full reference at small sizes.
	page.add_child(_text("ABOUT", "SectionLabel"))
	about_label = _text("", "SecondaryLabel", true)
	about_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr()
	about_label.custom_minimum_size.x = 0
	page.add_child(about_label)
	screen.resized.connect(_resize_help)
	screen.theme_changed.connect(_resize_help)


func _ready() -> void:
	about_label.text = about_text(BuildInfo.current())
	_resize_help()
	close_button.grab_focus.call_deferred()


func _resize_help() -> void:
	if not is_inside_tree(): return
	var area: Vector2 = get_viewport().get_visible_rect().size
	_help_panel.custom_minimum_size = Vector2(minf(1200, area.x - 48), area.y - 48)
	_help_columns.vertical = preload("res://ui/ui_theme.gd").text_scale > 1.25 or area.x < 1180
	# The scroll viewport receives the space left by the header; a fixed minimum can push Close offscreen.
	for table in _key_tables:
		table.columns = 2 if _help_columns.vertical else int(table.get_meta("wide_columns"))
		for child in table.get_children():
			if child is Label:
				child.custom_minimum_size.x = 0 if _help_columns.vertical else float(table.get_meta("description_width"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_field_conditions_text()
		_update_radio_help_text()
		about_label.text = about_text(BuildInfo.current())


func _scroll_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	var bar := _help_scroll.get_v_scroll_bar()
	var page := maxf(48, _help_scroll.size.y * 0.8)
	match event.keycode:
		KEY_DOWN: bar.value += 40
		KEY_UP: bar.value -= 40
		KEY_PAGEDOWN: bar.value += page
		KEY_PAGEUP: bar.value -= page
		KEY_HOME: bar.value = bar.min_value
		KEY_END: bar.value = bar.max_value
		_: return
	_help_scroll.accept_event()


func _update_field_conditions_text() -> void:
	if field_conditions_label != null:
		if _vehicle_type == Reference.ROTORCRAFT:
			field_conditions_label.text = tr("Helicopter: ground pad or practice hover. On the pad, center controls at zero pitch, arm with B, release hold with H, wait for RPM, then raise collective. Steady wind and gusts are available; flight validation is pending.")
		else:
			field_conditions_label.text = tr("Choose a runway or airborne start on Home. Configure wind, gusts, turbulence and field air density before flying. Flight models are experimental.")


func _update_radio_help_text() -> void:
	if radio_help_label == null:
		return
	if _vehicle_type == Reference.ROTORCRAFT:
		radio_help_label.text = tr("USB radio: lower collective to arm the input, then match the displayed start pitch before motor arming. Gamepads retain the start collective. Assign Helicopter arm, hold and flight mode in Controls. Throttle cut latches hold; releasing it never starts the rotor. K calibrates.")
	else:
		radio_help_label.text = tr("USB radio (EdgeTX): select Advanced Joystick in Model setup. Lower throttle to arm; unplugging pauses. K: calibrate. Assign gear AUX or Toggle landing gear in Controls.")


## Product, build identity (as exported, or "development"), engine and licence: what a bug report needs.
static func about_text(build: Dictionary) -> String:
	var lines := PackedStringArray()
	if build.source == "export":
		lines.append(TranslationServer.translate("OpenRC Simulator %s (build %s, commit %s%s, %s)") % [build.parsed.semver, build.describe,
			build.commit.substr(0, 12), TranslationServer.translate(", with local changes") if build.dirty else "", build.commit_date.substr(0, 10)])
	else:
		lines.append(TranslationServer.translate("OpenRC Simulator %s, development build (run from the source tree)") % build.version)
	lines.append("Godot %s · %s · %s · %s" % [build.godot, TranslationServer.translate("MIT licence"),
		TranslationServer.translate("Ugly Stick designed by Phil Kraft · font Open Sans (SIL OFL)"), REPOSITORY])
	return "\n".join(lines)


func close() -> void:
	closed.emit()
	if is_inside_tree(): # standalone use; the stack restores managed focus after enabling the lower screen
		get_child(0).close()


func _key_table(rows: Array, columns := 2, description_width := 340) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.set_meta("wide_columns", columns)
	grid.set_meta("description_width", description_width)
	_key_tables.append(grid)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 0) # compact rows keep the full reference visible at 720p
	for row in rows:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 4)
		caps.size_flags_vertical = Control.SIZE_SHRINK_CENTER # keys keep their shape next to a wrapped line
		for key in row[0]:
			caps.add_child(KeyCap.for_key(key))
		grid.add_child(caps)
		var what := _text(row[1], "SecondaryLabel")
		what.custom_minimum_size.x = description_width
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(what)
	return grid


## Trace recording, the flight log and the data reload serve evidence and development rather than flying.
static func _is_developer_row(row: Array) -> bool:
	return KEY_T in row[0] or KEY_F10 in row[0] or KEY_F5 in row[0]


static func _gap(height: int) -> Control:
	return Widgets.gap(height)


static func _column(parent: Control) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


static func _text(text: String, variation: String, wrap := false) -> Label:
	return Widgets.label(text, variation, wrap)
