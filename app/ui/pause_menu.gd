# Pause menu (MENU-PLAN §3/§8, steps UI-02/UI-03). Shown over the frozen flight on its own CanvasLayer (above the
# flight's HUD and panel layers). It never pauses anything itself: app_root holds the session ("menu") while it
# is open. While open it swallows every key the GUI did not use, so flight shortcuts (R, T, K, P, F5...) never act
# behind it; Esc goes back to the flight. Texts are English source strings (res://i18n/*.po).
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")

signal continue_requested
signal restart_requested
signal end_requested
signal quit_requested

const LAYER := 10 # above the flight's HUD/panel CanvasLayers
const WIDTH := 400

var continue_button: Button
var restart_button: Button
var end_button: Button
var quit_button: Button
var status_label: Label
var note_label: Label
var _session: Node


## `can_end`: whether "End flight" (back to Home) is offered; the direct route (`--` arguments) has no Home.
func _init(can_end := true) -> void:
	name = "PauseMenu"
	layer = LAYER
	var screen := Control.new()
	screen.name = "Screen"
	screen.theme = UiTheme.build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.25) # the frozen flight stays readable: the airplane is what was paused
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	# A column on the left, like Home: the airplane, centred by the pilot camera, stays in view.
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Sidebar"
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = WIDTH
	screen.add_child(panel)
	screen.add_child(_fade())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = "TitleLabel"
	column.add_child(title)
	status_label = _wrapped_label()
	column.add_child(status_label)
	column.add_child(_gap(6))
	continue_button = _button("Continue", "PrimaryButton", "Continue")
	continue_button.custom_minimum_size.y = 58
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	column.add_child(continue_button)
	restart_button = _button("Restart flight", "", "Restart")
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	column.add_child(restart_button)
	end_button = _button("End flight", "", "End")
	end_button.pressed.connect(func() -> void: end_requested.emit())
	end_button.visible = can_end
	column.add_child(end_button)
	quit_button = _button("Quit", "", "Quit")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit_button)
	note_label = _wrapped_label()
	note_label.visible = false
	column.add_child(note_label)


## Shows why the flight is paused and whether it can go on, and puts the keyboard focus on the first action.
## `session`: the flight's FlightSession. Updated again when a joypad comes or goes while the menu is open.
func show_for(session: Node) -> void:
	_session = session
	refresh()
	(continue_button if not continue_button.disabled else restart_button).grab_focus.call_deferred()


func refresh() -> void:
	continue_button.disabled = not _session.is_flyable()
	status_label.text = status_text(_session)
	status_label.visible = status_label.text != ""


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_changed) # disconnected automatically when the menu is freed


func _on_joy_changed(_device: int, _connected: bool) -> void:
	refresh.call_deferred() # after the session has handled the same signal (failsafe, new profile)


## One sentence about the pause cause, translated where the cause is known; technical reasons stay as they are.
func status_text(session: Node) -> String:
	if not session.is_flyable():
		return tr("This flight cannot continue: %s") % session.pause_reason
	if not session.crash.is_empty():
		return tr("Crashed. The flight restarts by itself after you continue.")
	match session.pause_reason:
		"":
			return ""
		"radio disconnected":
			return tr("The radio was disconnected: engine at idle, sticks centred. Continue flies with the keyboard, or plug the radio back in.")
		"calibration cancelled":
			return tr("Radio calibration cancelled; the previous profile stays.")
	return session.pause_reason


## A message under the buttons (e.g. a trace that could not be saved); "" hides it.
func set_note(text: String) -> void:
	note_label.text = text
	note_label.visible = text != ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		# Handled first: Esc may close (free) this menu, and nothing may reach the flight's shortcuts while it is open.
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			continue_requested.emit() # Esc: back to the flight (refused by the session when it cannot fly)


func _button(text: String, variation: String, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.theme_type_variation = variation
	return b


func _wrapped_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = "SecondaryLabel"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # built with tr()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	return l


## The column's edge fades into the scene (as on Home).
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
	rect.offset_left = WIDTH
	rect.offset_right = WIDTH + 32
	return rect


static func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c
