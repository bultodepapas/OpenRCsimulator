# Home screen (MENU-PLAN §3, steps UI-01a/01c/01d/05): one column over the selected airplane (ui/home_scene.gd).
# Top to bottom: the name and build stage; the aircraft selector and what Fly starts (next to Fly); Fly; Language,
# Help and Quit; how to control. The aircraft come from app_state/aircraft_catalog.gd; a preview can be looked at but
# not flown (Fly is disabled and the card says why).
# Built in code with containers, so it reflows instead of using absolute positions. Texts are English source
# strings: Labels and Buttons translate themselves when the locale changes (res://i18n/*.po); sentences built at
# runtime use tr() and are rebuilt on NOTIFICATION_TRANSLATION_CHANGED. Proper names are never translated.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const Reference := preload("res://ui/controls_reference.gd")
const RcInput := preload("res://input/rc_input.gd")
const Preferences := preload("res://app_state/preferences.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

## The Fly button was pressed (emitted once: further presses are ignored while the flight starts).
signal fly_requested
signal quit_requested
## The player asked for the next interface language (a Preferences.LANGUAGES code).
signal language_requested(code: String)
## The player asked for Help (it returns the focus to `from` when it closes).
signal help_requested(from: Control)
## The player chose another aircraft (a catalog ID); the owner remembers it and calls set_aircraft().
signal aircraft_requested(id: String)

const SIDEBAR_WIDTH := 440

## The catalog aircraft that Fly starts (set_aircraft() changes it).
var aircraft_id := Catalog.DEFAULT_ID

var fly_button: Button
var language_button: Button
var help_button: Button
var quit_button: Button
var control_label: Label
var keys_legend: GridContainer
var note_label: Label
var previous_button: Button
var next_button: Button
var aircraft_count_label: Label
var aircraft_name_label: Label
var aircraft_summary_label: Label
var aircraft_status_label: Label
var limits_label: Label
var _fly_sent := false


func _init() -> void:
	name = "Home"
	theme = UiTheme.build() # on this screen's top Control: Window.theme would not reach CanvasLayers
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sidebar := PanelContainer.new()
	sidebar.name = "Sidebar"
	sidebar.theme_type_variation = "Sidebar"
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.custom_minimum_size.x = SIDEBAR_WIDTH
	add_child(sidebar)
	add_child(_fade())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	sidebar.add_child(column)

	var title := _label("OpenRC Simulator", "TitleLabel", false)
	column.add_child(title)
	var stage := HBoxContainer.new()
	stage.add_theme_constant_override("separation", 10)
	var badge := PanelContainer.new()
	badge.theme_type_variation = "Badge"
	badge.add_child(_label("ALPHA", "SectionLabel", false))
	stage.add_child(badge)
	# The build identity (UI-04a): the version an exported build carries, or "development build" from the source tree.
	var build := BuildInfo.current()
	var version_label := _label(build.label if build.source == "export" else "development build", "SecondaryLabel", build.source != "export")
	version_label.name = "Version"
	stage.add_child(version_label)
	column.add_child(stage)
	column.add_child(_spacer())

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	var section := _label("NEXT FLIGHT", "SectionLabel")
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(section)
	aircraft_count_label = _label("", "SecondaryLabel", false) # built with tr()
	aircraft_count_label.name = "AircraftCount"
	aircraft_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(aircraft_count_label)
	previous_button = _arrow_button("PreviousAircraft", "left")
	previous_button.pressed.connect(func() -> void: aircraft_requested.emit(Catalog.step(aircraft_id, -1)))
	heading.add_child(previous_button)
	next_button = _arrow_button("NextAircraft", "right")
	next_button.pressed.connect(func() -> void: aircraft_requested.emit(Catalog.step(aircraft_id, 1)))
	heading.add_child(next_button)
	column.add_child(heading)
	column.add_child(_gap(8))
	var card := PanelContainer.new()
	card.name = "AircraftCard"
	card.theme_type_variation = "Card"
	var card_lines := VBoxContainer.new()
	card_lines.add_theme_constant_override("separation", 4)
	aircraft_name_label = _label("", "CardTitle", false) # a proper name: never translated
	aircraft_name_label.name = "AircraftName"
	aircraft_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # long names and translations wrap, never widen the column
	card_lines.add_child(aircraft_name_label)
	aircraft_summary_label = _label("", "SecondaryLabel")
	aircraft_summary_label.name = "AircraftSummary"
	aircraft_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_lines.add_child(aircraft_summary_label)
	aircraft_status_label = _label("", "SecondaryLabel")
	aircraft_status_label.name = "AircraftStatus"
	aircraft_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_lines.add_child(aircraft_status_label)
	card_lines.add_child(_label("Test field · Free flight", "SecondaryLabel"))
	limits_label = _label("Starts in the air. A crash restarts the flight.", "SecondaryLabel")
	limits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_lines.add_child(limits_label)
	card.add_child(card_lines)
	column.add_child(card)
	column.add_child(_gap(18))

	fly_button = _button("FLY", "PrimaryButton")
	fly_button.name = "Fly"
	fly_button.custom_minimum_size.y = 66
	fly_button.pressed.connect(_on_fly)
	column.add_child(fly_button)
	column.add_child(_gap(12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	language_button = _button("", "")
	language_button.name = "Language"
	language_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr(); language names stay as they are
	language_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_button.pressed.connect(func() -> void: language_requested.emit(next_language(current_language())))
	row.add_child(language_button)
	help_button = _button("Help", "")
	help_button.name = "Help"
	help_button.custom_minimum_size.x = 92
	help_button.pressed.connect(func() -> void: help_requested.emit(help_button))
	row.add_child(help_button)
	quit_button = _button("Quit", "")
	quit_button.name = "Quit"
	quit_button.custom_minimum_size.x = 92
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	row.add_child(quit_button)
	column.add_child(row)
	note_label = _label("", "SecondaryLabel", false)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.visible = false
	column.add_child(note_label)
	column.add_child(_spacer())

	column.add_child(_label("CONTROLS", "SectionLabel"))
	column.add_child(_gap(8))
	control_label = _label("", "SecondaryLabel", false) # built with tr()
	control_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(control_label)
	column.add_child(_gap(10))
	keys_legend = GridContainer.new()
	keys_legend.columns = 2
	keys_legend.add_theme_constant_override("h_separation", 18)
	keys_legend.add_theme_constant_override("v_separation", 8)
	_fill_legend()
	column.add_child(keys_legend)
	set_aircraft(aircraft_id) # the card is never empty; the owner sets the saved choice before adding Home


func _ready() -> void:
	# Down from Fly lands on the row's first button (geometry alone picks the middle one, Help). Left and right from
	# Fly reach the aircraft arrows, so changing airplane is two keys away from the start.
	fly_button.focus_neighbor_bottom = fly_button.get_path_to(language_button)
	fly_button.focus_neighbor_left = fly_button.get_path_to(previous_button)
	fly_button.focus_neighbor_right = fly_button.get_path_to(next_button)
	Input.joy_connection_changed.connect(_on_joy_changed)
	_update_texts()
	# Keyboard focus starts on Fly, visible (on the next arrow when the saved aircraft is a preview: Fly is disabled).
	(fly_button if not fly_button.disabled else next_button).grab_focus.call_deferred()


## Shows `id` on the card and enables Fly only for an aircraft that can fly. Unknown IDs fall back to the default
## (a stale preference must never leave Home without a valid airplane).
func set_aircraft(id: String) -> void:
	aircraft_id = id if Catalog.has(id) else Catalog.DEFAULT_ID
	var e := Catalog.entry(aircraft_id)
	var flyable := Catalog.can_fly(aircraft_id)
	var had_focus := fly_button.has_focus()
	aircraft_name_label.text = e.name
	aircraft_summary_label.text = e.summary
	aircraft_status_label.text = e.status_note
	limits_label.visible = flyable
	fly_button.disabled = _fly_sent or not flyable
	fly_button.focus_mode = Control.FOCUS_ALL if flyable else Control.FOCUS_NONE
	if had_focus and not flyable:
		next_button.grab_focus()
	if is_node_ready():
		_update_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		_fill_legend() # the player may have switched keyboard layout meanwhile (no engine signal for it, research 25)


## The keyboard legend from the shared table (ui/controls_reference.gd), keys named as the current layout prints them.
func _fill_legend() -> void:
	for c in keys_legend.get_children():
		keys_legend.remove_child(c)
		c.queue_free()
	for k in Reference.FLIGHT:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 4)
		for key in k[0]:
			caps.add_child(KeyCap.for_key(key))
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 10)
		pair.add_child(caps)
		pair.add_child(_label(k[1], "SecondaryLabel"))
		keys_legend.add_child(pair)


## A one-line message under the buttons (e.g. a settings file that could not be saved); "" hides it.
func set_note(text: String) -> void:
	note_label.text = text
	note_label.visible = text != ""


## The interface language in use, as a Preferences.LANGUAGES code ("en" when the locale is not one of ours).
static func current_language() -> String:
	var code := TranslationServer.get_locale().get_slice("_", 0)
	return code if Preferences.LANGUAGES.has(code) else "en"


static func next_language(code: String) -> String:
	var codes: Array = Preferences.LANGUAGES.keys()
	return codes[(codes.find(code) + 1) % codes.size()]


func _update_texts() -> void:
	language_button.text = tr("Language: %s") % Preferences.LANGUAGES[current_language()]
	aircraft_count_label.text = tr("Aircraft %d of %d") % [Catalog.ids().find(aircraft_id) + 1, Catalog.ids().size()]
	previous_button.tooltip_text = tr("Previous aircraft")
	next_button.tooltip_text = tr("Next aircraft")
	_update_control()


## Same rule as FlightSession: the first connected joypad flies, and its throttle must go low to arm the engine.
## Whole sentences per case (never a translated word inserted into another translated sentence).
func _update_control() -> void:
	var pads := Input.get_connected_joypads()
	keys_legend.visible = pads.is_empty() # the keys only fly while no joypad is connected
	if pads.is_empty():
		control_label.text = tr("Keyboard — no radio connected.")
		return
	var pad_name := Input.get_joy_name(pads[0])
	if RcInput.looks_like_radio(pad_name):
		control_label.text = tr("Radio “%s”. Lower the throttle to arm the engine. To fly with the keyboard, unplug it.") % pad_name
	else:
		control_label.text = tr("Controller “%s”. Lower the throttle to arm the engine. To fly with the keyboard, unplug it.") % pad_name


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_update_control()


func _on_fly() -> void:
	if _fly_sent or not Catalog.can_fly(aircraft_id):
		return
	_fly_sent = true
	fly_button.disabled = true
	fly_requested.emit()


## The column's edge fades into the scene instead of cutting it with a hard line.
func _fade() -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([UiTheme.SIDEBAR, Color(UiTheme.SIDEBAR, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 4
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rect.offset_left = SIDEBAR_WIDTH
	rect.offset_right = SIDEBAR_WIDTH + 32
	return rect


static func _label(text: String, variation: String, translate := true) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if not translate:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


static func _button(text: String, variation: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	return b


## A small square button with a drawn arrow (the default font has no arrow glyphs, see ui/key_cap.gd).
static func _arrow_button(button_name: String, direction: String) -> Button:
	var b := _button("", "")
	b.name = button_name
	b.custom_minimum_size = Vector2(44, 40)
	var arrow: Control = KeyCap.Arrow.new()
	arrow.direction = direction
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(arrow)
	return b


static func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


static func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
