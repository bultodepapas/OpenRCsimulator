# Home screen (MENU-PLAN §3, steps UI-01a/UI-01d): Fly, language and Quit, a summary of what Fly starts, and which
# control flies. No physics runs behind it. Built in code with containers, so it reflows instead of using absolute
# positions. Texts are English source strings: Labels and Buttons translate themselves when the locale changes
# (res://i18n/*.po); sentences built at runtime use tr() and are rebuilt on NOTIFICATION_TRANSLATION_CHANGED.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")
const RcInput := preload("res://input/rc_input.gd")
const Preferences := preload("res://app_state/preferences.gd")

## The Fly button was pressed (emitted once: further presses are ignored while the flight starts).
signal fly_requested
signal quit_requested
## The player asked for the next interface language (a Preferences.LANGUAGES code).
signal language_requested(code: String)

## What Fly starts, until the catalog (UI-05/06) reads it from installed content. Presentation only: no physical
## parameter is copied here. The aircraft name is a proper name and is not translated.
const SUMMARY := ["Jensen Das Ugly Stik 60", "Test field", "Free flight · starts in the air"]

var fly_button: Button
var language_button: Button
var quit_button: Button
var control_label: Label
var note_label: Label
var _fly_sent := false


func _init() -> void:
	name = "Home"
	theme = UiTheme.build() # on this screen's top Control: Window.theme would not reach CanvasLayers
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)

	var menu := PanelContainer.new()
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.custom_minimum_size.x = 380
	row.add_child(menu)
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 14)
	menu.add_child(items)
	var title := _label("OpenRC Simulator", "TitleLabel")
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # product name
	items.add_child(title)
	items.add_child(_label("Alpha · development", "SecondaryLabel"))
	items.add_child(_gap(18))
	fly_button = _button("FLY", "PrimaryButton")
	fly_button.name = "Fly"
	fly_button.custom_minimum_size.y = 64
	fly_button.pressed.connect(_on_fly)
	items.add_child(fly_button)
	language_button = _button("", "")
	language_button.name = "Language"
	language_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr(); language names stay as they are
	language_button.pressed.connect(func() -> void: language_requested.emit(next_language(current_language())))
	items.add_child(language_button)
	quit_button = _button("Quit", "")
	quit_button.name = "Quit"
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	items.add_child(quit_button)
	items.add_child(_gap(18))
	control_label = _label("", "SecondaryLabel")
	control_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr()
	control_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	items.add_child(control_label)
	note_label = _label("", "SecondaryLabel")
	note_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.visible = false
	items.add_child(note_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_SHRINK_END
	card.custom_minimum_size.x = 360
	row.add_child(card)
	var lines := VBoxContainer.new()
	card.add_child(lines)
	var aircraft := _label(SUMMARY[0], "")
	aircraft.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lines.add_child(aircraft)
	for s in SUMMARY.slice(1):
		lines.add_child(_label(s, "SecondaryLabel"))
	var limits := _label("For now the flight starts in the air; touching the ground restarts the airplane.", "SecondaryLabel")
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(limits)


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_changed)
	_update_texts()
	fly_button.grab_focus.call_deferred() # keyboard focus starts on Fly, visible


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()


## A one-line message under the control status (e.g. a settings file that could not be saved); "" hides it.
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
	if pads.is_empty():
		# Physical keys (QWERTY positions); labels for other layouts arrive with the help screen (UI-04b).
		control_label.text = tr("Control: keyboard. Arrows: roll and pitch · A/D: rudder · W/S: throttle.")
		return
	var pad_name := Input.get_joy_name(pads[0])
	if RcInput.looks_like_radio(pad_name):
		control_label.text = tr("Control: radio “%s”. Lower the throttle to arm the engine. To fly with the keyboard, unplug it.") % pad_name
	else:
		control_label.text = tr("Control: controller “%s”. Lower the throttle to arm the engine. To fly with the keyboard, unplug it.") % pad_name


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_update_control()


func _on_fly() -> void:
	if _fly_sent:
		return
	_fly_sent = true
	fly_button.disabled = true
	fly_requested.emit()


func _backdrop() -> TextureRect:
	# A calm field (MENU-PLAN §7): sky over grass, drawn from a gradient until our own capture replaces it (UI-01c).
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 0.62, 1.0])
	g.colors = PackedColorArray([Color("#5b8fc4"), Color("#c9dbe6"), Color("#6f8f4f"), Color("#3f5a2d")])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func _label(text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
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
