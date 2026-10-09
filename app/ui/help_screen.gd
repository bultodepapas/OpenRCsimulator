# Help and about (MENU-PLAN §3/§7, step UI-04b). Opened from Home or from the pause menu; Esc or Close returns the
# focus to the button that opened it. Every key comes from ui/controls_reference.gd (the table the consistency test
# checks against the code) and is named as the player's keyboard layout prints it. The about block shows the build
# identity of UI-04a. While open it swallows every key the GUI leaves (like the pause menu). English source strings.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const Reference := preload("res://ui/controls_reference.gd")
const BuildInfo := preload("res://app_state/build_info.gd")

signal closed

const LAYER := 11 # above the pause menu
const REPOSITORY := "github.com/bultodepapas/OpenRCsimulator"

var close_button: Button
var about_label: Label
var _return_focus: Control


func _init(return_focus: Control = null) -> void:
	name = "Help"
	layer = LAYER
	_return_focus = return_focus
	var screen := Control.new()
	screen.theme = UiTheme.build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Sidebar"
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true # keyboard focus must reach what scaling pushes out of view (research 11)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(1120, 600) # wide: Spanish lines stay on one row and everything fits at 720p
	panel.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)

	var header := HBoxContainer.new()
	var title := _text("Help", "TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "Close"
	close_button.custom_minimum_size.x = 120
	close_button.pressed.connect(close)
	header.add_child(close_button)
	page.add_child(header)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	page.add_child(columns)
	var left := _column(columns)
	left.add_child(_text("WHILE FLYING", "SectionLabel"))
	left.add_child(_key_table(Reference.SHORTCUTS))
	var right := _column(columns)
	right.add_child(_text("FLY", "SectionLabel"))
	right.add_child(_key_table(Reference.FLIGHT))
	right.add_child(_text("Keys are shown as your keyboard layout prints them.", "SecondaryLabel", true))
	right.add_child(_text("RADIO", "SectionLabel"))
	right.add_child(_text("Connect an EdgeTX radio over USB (Model setup → USB Joystick: Advanced, Joystick). It flies while connected; the engine starts once the throttle stick has been low. Unplugging it pauses the flight with the engine at idle. K calibrates it.", "SecondaryLabel", true))
	right.add_child(_text("RIGHT NOW", "SectionLabel"))
	right.add_child(_text("Flights start in the air. Wind is uniform across the field; smooth gusts repeat on a timer. No turbulence or spatial variation. Wheel landings are experimental; a crash restarts the flight.", "SecondaryLabel", true))

	# About across the width, in two lines: everything fits at 1280x720 without scrolling, because nothing below
	# Close is focusable and keyboard players could not scroll to it (tests/test_ui_help.gd checks the fit).
	page.add_child(_text("ABOUT", "SectionLabel"))
	about_label = _text("", "SecondaryLabel", true)
	about_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr()
	about_label.custom_minimum_size.x = 1100
	page.add_child(about_label)


func _ready() -> void:
	about_label.text = about_text(BuildInfo.current())
	close_button.grab_focus.call_deferred()


## Product, build identity (as exported, or "development"), engine and licence: what a bug report needs.
static func about_text(build: Dictionary) -> String:
	var lines := PackedStringArray()
	if build.source == "export":
		lines.append(TranslationServer.translate("OpenRC Simulator %s (build %s, commit %s%s, %s)") % [build.parsed.semver, build.describe,
			build.commit.substr(0, 12), TranslationServer.translate(", with local changes") if build.dirty else "", build.commit_date.substr(0, 10)])
	else:
		lines.append(TranslationServer.translate("OpenRC Simulator %s, development build (run from the source tree)") % build.version)
	lines.append("Godot %s · %s · %s · %s" % [build.godot, TranslationServer.translate("MIT licence"),
		TranslationServer.translate("Jensen Das Ugly Stik designed by Phil Kraft · font Open Sans (SIL OFL)"), REPOSITORY])
	return "\n".join(lines)


func close() -> void:
	if _return_focus != null and is_instance_valid(_return_focus) and _return_focus.is_inside_tree():
		_return_focus.grab_focus()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled() # Esc may free this screen; nothing reaches the menus or the flight below
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			close()


func _key_table(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for row in rows:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 4)
		caps.size_flags_vertical = Control.SIZE_SHRINK_CENTER # keys keep their shape next to a wrapped line
		for key in row[0]:
			caps.add_child(KeyCap.for_key(key))
		grid.add_child(caps)
		var what := _text(row[1], "SecondaryLabel")
		what.custom_minimum_size.x = 340
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(what)
	return grid


static func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


static func _column(parent: Control) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


static func _text(text: String, variation: String, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 400
	return l
