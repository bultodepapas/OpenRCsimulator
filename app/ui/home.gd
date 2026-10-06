# Home screen (MENU-PLAN §3, steps UI-01a/01c/01d): one column over our Ugly Stik (ui/home_scene.gd).
# Top to bottom: the name and build stage; what Fly starts (next to Fly); Fly; Language and Quit; how to control.
# Built in code with containers, so it reflows instead of using absolute positions. Texts are English source
# strings: Labels and Buttons translate themselves when the locale changes (res://i18n/*.po); sentences built at
# runtime use tr() and are rebuilt on NOTIFICATION_TRANSLATION_CHANGED. Proper names are never translated.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const RcInput := preload("res://input/rc_input.gd")
const Preferences := preload("res://app_state/preferences.gd")

## The Fly button was pressed (emitted once: further presses are ignored while the flight starts).
signal fly_requested
signal quit_requested
## The player asked for the next interface language (a Preferences.LANGUAGES code).
signal language_requested(code: String)

const SIDEBAR_WIDTH := 440
## What Fly starts, until the catalog (UI-05/06) reads it from installed content. Presentation only: no physical
## parameter is copied here.
const AIRCRAFT_NAME := "Jensen Das Ugly Stik 60"
## Keyboard legend: keys (QWERTY physical positions, as keyboard.gd reads them) and what they do.
const KEYS := [[["left", "right"], "Roll"], [["up", "down"], "Pitch"], [["A", "D"], "Rudder"], [["W", "S"], "Throttle"]]

var fly_button: Button
var language_button: Button
var quit_button: Button
var control_label: Label
var keys_legend: GridContainer
var note_label: Label
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
	stage.add_child(_label("development build", "SecondaryLabel"))
	column.add_child(stage)
	column.add_child(_spacer())

	column.add_child(_label("NEXT FLIGHT", "SectionLabel"))
	column.add_child(_gap(8))
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var card_lines := VBoxContainer.new()
	card_lines.add_theme_constant_override("separation", 4)
	card_lines.add_child(_label(AIRCRAFT_NAME, "CardTitle", false))
	card_lines.add_child(_label("Test field · Free flight", "SecondaryLabel"))
	var limits := _label("Starts in the air; touching the ground restarts the airplane.", "SecondaryLabel")
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_lines.add_child(limits)
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
	quit_button = _button("Quit", "")
	quit_button.name = "Quit"
	quit_button.custom_minimum_size.x = 120
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
	for k in KEYS:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 4)
		for key in k[0]:
			caps.add_child(KeyCap.make(key))
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 10)
		pair.add_child(caps)
		var action := _label(k[1], "SecondaryLabel")
		pair.add_child(action)
		keys_legend.add_child(pair)
	column.add_child(keys_legend)


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_changed)
	_update_texts()
	fly_button.grab_focus.call_deferred() # keyboard focus starts on Fly, visible


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()


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
	if _fly_sent:
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


static func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


static func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
