# UI-15-UX-07: the Setup assistant. A modal CanvasLayer (mounted through Screen like radio_calibration_setup.gd) that
# walks one device through Identify → Mode → Calibrate (radios/joysticks only) → Test → Switches & buttons → Save,
# one page per step, with a progress strip and Cancel / Skip / Back / Next. Keyboard, mouse and gamepad focus all
# work; Esc or the pad's Back goes back one step and cancels on the first step without asking (the assistant edits
# only the owner's draft, so there is nothing of its own to lose).
#
# Presentation only. It never reads or writes profiles or storage, never starts calibration or capture without a
# click on its own button, and talks to its owner only through this host interface (setup_assistant_host.gd
# documents every key; extend that class or pass any Object with the same methods, checked with has_method):
#   device_info() -> Dictionary                       vehicle_capabilities() -> Dictionary
#   set_profile_kind(kind: String) -> bool            apply_preset(preset_id: String) -> bool
#   request_calibration() -> bool                     preview() -> Dictionary
#   set_channel_inverted(channel: String, inverted: bool) -> void
#   binding_for(id: String) -> Dictionary             capture(id: String) -> bool
#   save() -> bool                                    last_error() -> String
# Asynchronous completions come back as calls on this node:
#   notify_calibration_finished(ok: bool, message: String)
#   notify_capture_finished(id: String, ok: bool, message: String)
# Ids passed to binding_for()/capture() are ControllerActions action ids ("flaps_cycle") or "aux:<channel>"
# ("aux:arm", "aux:flight_mode"). The assistant emits finished(saved) once and then closed; the owner frees it.
#
# While the host calibrates, the assistant hides (the owner's calibration surface is on top); while the host
# captures, every assistant button is disabled and its surface ignores input, so the captured press, its release
# and Esc reach the owner only. host.preview() is polled only while the Test step is visible; live widgets redraw
# only on changed samples.
extends CanvasLayer

signal finished(saved: bool)
signal closed

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const DevicePicture := preload("res://ui/controls/device_picture.gd")
const GimbalView := preload("res://ui/controls/stick_gimbal_view.gd")
const ChannelBarView := preload("res://ui/controls/channel_bar.gd")
const BindingChip := preload("res://ui/controls/binding_chip.gd")
const CalibrationView := preload("res://ui/controls/calibration_view.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")

## Above the Controls screen (12). The owner's calibration surface (13) is shown while the assistant hides.
const LAYER := 13
const STEP_IDS: PackedStringArray = ["identify", "mode", "calibrate", "test", "switches", "summary"]
const STEP_NAMES := {
	identify = "Identify", mode = "Mode", calibrate = "Calibrate", test = "Test", switches = "Switches", summary = "Save",
}
const SKIPPABLE_STEPS: PackedStringArray = ["calibrate", "switches"]
const KIND_IDS: PackedStringArray = ["radio", "gamepad", "joystick"]
const KIND_TITLES := { radio = "Radio", gamepad = "Gamepad", joystick = "Joystick" }
const KIND_DESCRIPTIONS := {
	radio = "RC transmitter in USB joystick mode: EdgeTX, OpenTX, JETI and others.",
	gamepad = "Xbox, PlayStation, Nintendo or another game controller.",
	joystick = "Flight stick or other USB joystick. It is calibrated like a radio.",
}
const GAMEPAD_PRESETS: PackedStringArray = ["mode1", "mode2", "trigger_absolute"]
const STICK_PRESETS: PackedStringArray = ["mode1", "mode2"]
const PRESET_TITLES := { mode1 = "Mode 1", mode2 = "Mode 2", trigger_absolute = "Triggers throttle" }
const PRESET_DESCRIPTIONS := {
	mode1 = "Throttle and roll on the right stick; pitch and yaw on the left.",
	mode2 = "Throttle and yaw on the left stick; pitch and roll on the right. The most common layout.",
	trigger_absolute = "The right trigger sets the throttle; the sticks fly yaw, pitch and roll.",
}
const CHANNELS: PackedStringArray = ["roll", "pitch", "yaw", "throttle"]
const CHANNEL_NAMES := { roll = "Roll", pitch = "Pitch", yaw = "Yaw", throttle = "Throttle" }
const AIRPLANE_ESSENTIALS: PackedStringArray = [
	"throttle_cut", "flaps_cycle", "gear_toggle", "smoke_toggle", "camera_cycle", "restart_flight",
]
const HELICOPTER_ESSENTIALS: PackedStringArray = ["helicopter_arm", "helicopter_hold", "helicopter_mode"]
const MULTIROTOR_ESSENTIALS: PackedStringArray = ["aux:arm", "aux:flight_mode"]
## Recovery: Pause stays assignable for every vehicle; Back is shown read-only (it is mandatory and menu-owned).
const RECOVERY_ASSIGNABLE: PackedStringArray = ["pause"]
const RECOVERY_READ_ONLY: PackedStringArray = ["back"]
const AUX_TITLES := { "aux:arm": "Arm motors", "aux:flight_mode": "Flight mode" }
const VEHICLE_NAMES := { airplane = "Airplane", helicopter = "Helicopter", multirotor = "FPV quad" }
const RADIO_CHECKLIST: PackedStringArray = [
	"EdgeTX / OpenTX: select USB Joystick (Classic) for this model.",
	"Turn the internal and external RF modules off while the radio is a joystick.",
	"Calibrate the sticks on the radio first.",
	"Use expo in the radio or in the simulator, not in both.",
	"JETI: set USB joystick mode and your stick mode on the transmitter.",
]
const JOYSTICK_CHECKLIST: PackedStringArray = [
	"Centre the stick and set any throttle lever to LOW.",
	"Close other programs that use the joystick.",
]
const MAX_PRESSED_CHIPS := 6
const MAX_RADIO_LAMPS := 8
const BUSY_CALIBRATION := "calibration"

## The owner's host (see setup_assistant_host.gd); any Object with the interface methods.
var host: Object
## Hide while the host's calibration surface runs; the owner may turn it off when it draws calibration elsewhere.
var hide_while_calibrating := true
## host.preview() calls so far (tests prove polling happens only on the Test step).
var preview_calls := 0

var title_label: Label
var device_label: Label
var strip: CalibrationView.StepStrip
var back_button: Button
var next_button: Button
var skip_button: Button
var cancel_button: Button
var error_banner: PanelContainer
var error_label: Label
## step id → page Control.
var pages := {}
## kind → ChoiceCard; preset → ChoiceCard.
var kind_cards := {}
var mode_cards := {}
var detection_label: Label
var identify_picture: DevicePicture
var start_calibration_button: Button
var calibration_banner: PanelContainer
var calibration_label: Label
var left_gimbal: GimbalView
var right_gimbal: GimbalView
## channel → ChannelBar / CheckButton.
var channel_bars := {}
var reverse_toggles := {}
var aircraft: AircraftView
## id → Assign Button / BindingChip / status Label on the Switches page.
var assign_buttons := {}
var binding_chips := {}
var row_status := {}
var summary_picture: DevicePicture
var summary_overlay: PictureOverlay
var summary_list: VBoxContainer
var summary_facts: Label

var _surface: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _mode_row: HBoxContainer
var _mode_heading: Label
var _mode_intro: Label
var _calibrate_heading: Label
var _checklist: VBoxContainer
var _calibration_art: Pictogram
var _pressed_row: HBoxContainer
var _pressed_chips: Array[BindingChip] = []
var _no_buttons: Label
var _throttle_centered := -1
var _switch_grid: GridContainer
var _vehicle_label: Label
var _steps := PackedStringArray()
var _index := 0
var _info := {}
var _family := "generic"
var _detected_kind := ""
var _kind := ""
var _preset := ""
var _mode_cards_kind := "-"
var _capabilities := {}
var _essentials := PackedStringArray()
var _busy := ""
var _calibration := ""
var _calibration_message := ""
var _calibration_start_error := ""
var _pressed := PackedInt32Array()
var _closing := false


func _init() -> void:
	name = "SetupAssistant"
	layer = LAYER
	_surface = Screen.mount(self, "Screen")
	_surface.escape_before_gui = true
	_surface.close_requested.connect(_on_escape)
	_surface.focus_fallback = _focus_default
	_surface.dim(0.6)
	var center: CenterContainer = _surface.call("center", 0.0)
	_panel = PanelContainer.new()
	_panel.name = "AssistantPanel"
	# The opaque Controls panel style: the assistant covers a live 3D scene, which must not show through its text.
	var panel_style := _surface.get_theme_stylebox("panel", "Sidebar").duplicate() as StyleBoxFlat
	if panel_style != null:
		panel_style.content_margin_left = 24.0
		panel_style.content_margin_right = 24.0
		panel_style.content_margin_top = 20.0
		panel_style.content_margin_bottom = 20.0
		_panel.add_theme_stylebox_override("panel", panel_style)
	else:
		_panel.theme_type_variation = "SettingsPanel"
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	title_label = Widgets.label("Controller setup", "TitleLabel")
	title_label.name = "Title"
	header.add_child(title_label)
	device_label = Widgets.label("", "SecondaryLabel", false, false)
	device_label.name = "Device"
	device_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	device_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	device_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	device_label.clip_text = true
	header.add_child(device_label)
	strip = CalibrationView.StepStrip.new()
	strip.name = "Progress"
	column.add_child(strip)
	_scroll = ScrollContainer.new()
	_scroll.name = "Pages"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var page_column := VBoxContainer.new()
	page_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(page_column)
	_build_identify(page_column)
	_build_mode(page_column)
	_build_calibrate(page_column)
	_build_test(page_column)
	_build_switches(page_column)
	_build_summary(page_column)
	error_banner = _banner("ErrorBanner", UiTheme.ERROR)
	error_label = error_banner.get_child(0) as Label
	error_banner.visible = false
	column.add_child(error_banner)
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	cancel_button = Widgets.button("Cancel", "QuietButton", "CancelSetup")
	cancel_button.pressed.connect(cancel)
	footer.add_child(cancel_button)
	var note := Widgets.label("Changes stay in the draft until you Save.", "SecondaryLabel", true)
	note.name = "DraftNote"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(note)
	skip_button = Widgets.button("Skip", "", "SkipStep")
	skip_button.pressed.connect(skip)
	footer.add_child(skip_button)
	back_button = Widgets.button("Back", "", "BackStep")
	back_button.pressed.connect(go_back)
	footer.add_child(back_button)
	next_button = Widgets.button("Next", "PrimaryButton", "NextStep")
	next_button.custom_minimum_size.x = 160.0
	next_button.pressed.connect(go_next)
	footer.add_child(next_button)
	_compute_steps()
	_retranslate()


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_resize_panel):
		viewport.size_changed.connect(_resize_panel)
	_resize_panel()
	set_process(_should_poll())


# --- Public API -------------------------------------------------------------------------------------------------

## Attach the host and read the device. Call before or after adding to the tree, then open().
func configure(next_host: Object) -> void:
	host = next_host
	_info = _host_dict("device_info")
	_capabilities = _host_dict("vehicle_capabilities")
	_family = ControllerPrompts.resolve_family(str(_info.get("family", "auto")), _info)
	_detected_kind = detected_kind(_info)
	_kind = _detected_kind
	_preset = _default_preset(_kind)
	_calibration = ""
	_busy = ""
	_index = 0
	_essentials = essentials_for(_capabilities)
	_build_switch_rows()
	_compute_steps()
	_show_step()


## Show the assistant; `from` regains focus when it closes.
func open(from: Control = null) -> void:
	_surface.open(from)
	_show_step()


func current_step() -> String:
	return _steps[_index] if _index >= 0 and _index < _steps.size() else ""


func steps() -> PackedStringArray:
	return _steps


func chosen_kind() -> String:
	return _kind


func chosen_preset() -> String:
	return _preset


## True while the host calibrates or captures for the assistant.
func is_busy() -> bool:
	return not _busy.is_empty()


func surface() -> Control:
	return _surface


## The kind a device may be preselected with, or "" when the pilot must choose: an existing configured profile's
## kind, a radio the registry identified (JETI), or a gamepad SDL knows or whose family is recognised. A generic
## "joystick" observation is unknown. Family names never imply channel order.
static func detected_kind(info: Dictionary) -> String:
	var profile_kind := str(info.get("profile_kind", ""))
	if profile_kind in KIND_IDS:
		return profile_kind
	var kind := str(info.get("kind", ""))
	if kind == "radio":
		return "radio"
	if kind == "gamepad" and (bool(info.get("known", false))
			or ControllerPrompts.resolve_family(str(info.get("family", "auto")), info) != "generic"):
		return "gamepad"
	return ""


## Essentials for a vehicle's capabilities (Switches page), before the recovery rows.
static func essentials_for(capabilities: Dictionary) -> PackedStringArray:
	var list := PackedStringArray()
	if bool(capabilities.get("helicopter", false)):
		list.append_array(HELICOPTER_ESSENTIALS)
	elif bool(capabilities.get("multirotor", false)):
		list.append_array(MULTIROTOR_ESSENTIALS)
	else:
		for id in AIRPLANE_ESSENTIALS:
			if ControllerActions.action_applies(id, capabilities):
				list.append(id)
	list.append_array(RECOVERY_ASSIGNABLE)
	return list


static func vehicle_name(capabilities: Dictionary) -> String:
	if bool(capabilities.get("helicopter", false)):
		return VEHICLE_NAMES.helicopter
	if bool(capabilities.get("multirotor", false)):
		return VEHICLE_NAMES.multirotor
	return VEHICLE_NAMES.airplane


## The untranslated label of an action or AUX id.
static func item_title(id: String) -> String:
	if AUX_TITLES.has(id):
		return AUX_TITLES[id]
	return str(ControllerActions.action_definition(id).get("label", id))


## DevicePicture control ids a binding occupies ("button:N", "axis:N"; a switch group lights each position).
static func control_ids_for(binding: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	match str(binding.get("type", "")):
		"button":
			ids.append("button:%d" % int(binding.get("button", -1)))
		"axis":
			ids.append("axis:%d" % int(binding.get("axis", -1)))
		"switch":
			for button: Variant in SmokeAux.bound_buttons(binding):
				ids.append("button:%d" % int(button))
	return ids


func go_next() -> void:
	if _closing or is_busy():
		return
	_hide_error()
	match current_step():
		"identify":
			if _kind.is_empty():
				return
			if not _host_bool("set_profile_kind", [_kind]):
				_show_error(_host_error("This controller type could not be applied."))
				return
		"mode":
			if _preset.is_empty():
				return
			if not _host_bool("apply_preset", [_preset]):
				_show_error(_host_error("This stick layout could not be applied."))
				return
		"calibrate":
			if _calibration != "ok":
				return
		"summary":
			_save()
			return
	_go_to(_index + 1)


func go_back() -> void:
	if _closing or is_busy():
		return
	if _index <= 0:
		cancel()
		return
	_hide_error()
	_go_to(_index - 1)


func skip() -> void:
	if _closing or is_busy() or not current_step() in SKIPPABLE_STEPS:
		return
	_hide_error()
	_go_to(_index + 1)


## Close without saving. The owner restores its draft as it was before the assistant opened.
func cancel() -> void:
	if _closing:
		return
	_close(false)


func notify_calibration_finished(ok: bool, message: String) -> void:
	if _busy != BUSY_CALIBRATION:
		return
	_busy = ""
	if not _closing:
		_surface.set_active(true)
	_calibration = "ok" if ok else "failed"
	_calibration_message = message
	_calibration_start_error = ""
	if current_step() == "calibrate":
		_refresh_calibrate()
		_update_footer()
		_focus_default()


func notify_capture_finished(id: String, ok: bool, message: String) -> void:
	if _busy != id or id.is_empty() or id == BUSY_CALIBRATION:
		return
	_set_capture_input(true)
	_busy = ""
	_refresh_chip(id)
	var status: Label = row_status.get(id)
	if status != null:
		status.text = message if not message.is_empty() else (tr("Assigned") if ok else tr("Not assigned."))
		status.add_theme_color_override("font_color", UiTheme.FOCUS if ok else UiTheme.CAUTION)
	_set_switch_buttons_enabled(true)
	_update_footer()
	var focus_target: Button = assign_buttons.get(id)
	if ok:
		var order := _essentials.find(id)
		focus_target = assign_buttons[_essentials[order + 1]] if order >= 0 and order + 1 < _essentials.size() else next_button
	if focus_target != null and focus_target.is_visible_in_tree():
		focus_target.grab_focus()


# --- Flow -------------------------------------------------------------------------------------------------------

func _compute_steps() -> void:
	var list := PackedStringArray(["identify", "mode"])
	if _kind != "gamepad":
		list.append("calibrate")
	list.append_array(["test", "switches", "summary"])
	var current := current_step()
	_steps = list
	if not current.is_empty() and _steps.has(current):
		_index = _steps.find(current)
	_index = clampi(_index, 0, _steps.size() - 1)
	var names := PackedStringArray()
	for id in _steps:
		names.append(tr(STEP_NAMES[id]))
	strip.names = names


func _go_to(index: int) -> void:
	_index = clampi(index, 0, _steps.size() - 1)
	_show_step()


func _show_step() -> void:
	var id := current_step()
	for page_id: String in pages:
		(pages[page_id] as Control).visible = page_id == id
	strip.set_state(_index, false)
	device_label.text = _device_name()
	match id:
		"identify":
			_refresh_identify()
		"mode":
			_refresh_mode()
		"calibrate":
			_refresh_calibrate()
		"test":
			_refresh_test()
		"switches":
			_refresh_switches()
		"summary":
			_refresh_summary()
	_update_footer()
	set_process(_should_poll())
	_scroll.scroll_vertical = 0
	_focus_default()


func _update_footer() -> void:
	var id := current_step()
	var busy := is_busy()
	back_button.visible = _index > 0
	back_button.disabled = busy
	cancel_button.disabled = busy
	skip_button.visible = id in SKIPPABLE_STEPS
	skip_button.disabled = busy
	next_button.text = "Save" if id == "summary" else "Next"
	next_button.accessibility_name = tr("Save controller settings") if id == "summary" else tr("Next step")
	next_button.disabled = busy or not _can_advance(id)


func _can_advance(id: String) -> bool:
	match id:
		"identify":
			return not _kind.is_empty()
		"mode":
			return not _preset.is_empty()
		"calibrate":
			return _calibration == "ok"
	return true


func _focus_default() -> void:
	if not is_inside_tree() or not _surface.is_visible_in_tree():
		return
	var target: Control = next_button
	match current_step():
		"identify":
			target = kind_cards.get(_kind, kind_cards.radio)
		"mode":
			target = mode_cards.get(_preset, next_button)
		"calibrate":
			target = next_button if _calibration == "ok" else start_calibration_button
		"switches":
			if not _essentials.is_empty() and assign_buttons.has(_essentials[0]):
				target = assign_buttons[_essentials[0]]
	if not Screen.can_focus(target):
		for candidate: Control in [next_button, back_button, cancel_button]:
			if Screen.can_focus(candidate):
				target = candidate
				break
	target.grab_focus()


func _on_escape() -> void:
	go_back()


func _unhandled_input(event: InputEvent) -> void:
	# Screen handles Escape on keyboards; this covers the pad's Back (ui_cancel) while the surface is active.
	if _closing or is_busy() or not _surface.visible or event is InputEventKey:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and title_label != null:
		_retranslate()


func _save() -> void:
	if _host_bool("save", []):
		_close(true)
		return
	_show_error(_host_error("Controller settings could not be saved."))
	next_button.grab_focus()


func _close(saved: bool) -> void:
	_closing = true
	set_process(false)
	_busy = ""
	finished.emit(saved)
	closed.emit()
	if is_instance_valid(_surface):
		_surface.close(true)
		_surface.set_active(false)


func _should_poll() -> bool:
	return current_step() == "test" and not is_busy() and not _closing and _surface != null and _surface.visible


func _process(delta: float) -> void:
	if not _should_poll():
		set_process(false)
		return
	# About 20 samples a second is smooth for the test widgets and keeps the host's work small.
	_preview_wait -= delta
	if _preview_wait > 0.0:
		return
	_preview_wait = PREVIEW_INTERVAL
	_poll_preview()


const PREVIEW_INTERVAL := 0.05
var _preview_wait := 0.0


func _resize_panel() -> void:
	if not is_inside_tree():
		return
	var area := get_viewport().get_visible_rect().size
	var width := minf(1640.0, area.x - 96.0) if area.x >= 1500.0 else area.x - 24.0
	var height := minf(960.0, area.y - 96.0) if area.y >= 850.0 else area.y - 24.0
	_panel.custom_minimum_size = Vector2(maxf(320.0, width), maxf(320.0, height))


# --- Host access ------------------------------------------------------------------------------------------------

func _host_call(method: String, arguments: Array) -> Variant:
	if host == null or not is_instance_valid(host) or not host.has_method(method):
		return null
	return host.callv(method, arguments)


func _host_bool(method: String, arguments: Array) -> bool:
	var value: Variant = _host_call(method, arguments)
	return value is bool and value


func _host_dict(method: String, arguments: Array = []) -> Dictionary:
	var value: Variant = _host_call(method, arguments)
	return value if value is Dictionary else {}


func _host_error(fallback: String) -> String:
	var value: Variant = _host_call("last_error", [])
	var text := str(value).strip_edges() if value != null else ""
	return text if not text.is_empty() else tr(fallback)


func _device_name() -> String:
	var text := str(_info.get("display_name", _info.get("name", ""))).strip_edges()
	return text if not text.is_empty() else tr("Unnamed device")


func _default_preset(kind: String) -> String:
	if kind.is_empty():
		return ""
	var options := GAMEPAD_PRESETS if kind == "gamepad" else STICK_PRESETS
	var current := str(_info.get("preset", ""))
	if current in options:
		return current
	return "mode1" if int(_info.get("stick_mode", 2)) == 1 else "mode2"


func _stick_mode() -> int:
	return 1 if _preset == "mode1" else 2


func _show_error(text: String) -> void:
	error_label.text = text
	error_banner.visible = true


func _hide_error() -> void:
	error_banner.visible = false
	error_label.text = ""


# --- Step 1: Identify -------------------------------------------------------------------------------------------

func _build_identify(parent: Control) -> void:
	var page := _page(parent, "identify", "What kind of controller is this?",
		"Choose the type that matches the device. A recognised device is preselected; an unknown one must be chosen before you continue.")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	page.add_child(top)
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(360.0, 210.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(frame)
	identify_picture = DevicePicture.new()
	identify_picture.name = "IdentifyPicture"
	identify_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identify_picture.custom_minimum_size = Vector2.ZERO
	identify_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(identify_picture)
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(facts)
	var name_label := Widgets.label("", "CardTitle", true, false)
	name_label.name = "DeviceName"
	facts.add_child(name_label)
	detection_label = Widgets.label("", "SecondaryLabel", true, false)
	detection_label.name = "Detection"
	facts.add_child(detection_label)
	var cards := HBoxContainer.new()
	cards.name = "KindCards"
	cards.add_theme_constant_override("separation", 20)
	page.add_child(cards)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for kind in KIND_IDS:
		var card := ChoiceCard.new(kind, kind, "", KIND_TITLES[kind], KIND_DESCRIPTIONS[kind])
		card.name = "Kind" + KIND_TITLES[kind]
		card.button_group = group
		card.base_height = 300.0
		card.set_picture_height(160.0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_on_kind_chosen.bind(kind))
		cards.add_child(card)
		kind_cards[kind] = card


func _on_kind_chosen(kind: String) -> void:
	if is_busy() or kind == _kind:
		_refresh_identify()
		_update_footer()
		return
	_kind = kind
	_preset = _default_preset(kind)
	_calibration = ""
	_calibration_message = ""
	_compute_steps()
	_refresh_identify()
	_update_footer()


func _refresh_identify() -> void:
	(pages.identify.find_child("DeviceName", true, false) as Label).text = _device_name()
	if _detected_kind.is_empty():
		detection_label.text = tr("Not recognised. Choose its type to continue.")
	else:
		detection_label.text = tr("Detected as: %s. Change it if this is wrong.") % tr(KIND_TITLES[_detected_kind])
	for kind: String in kind_cards:
		var card: ChoiceCard = kind_cards[kind]
		card.set_pressed_no_signal(kind == _kind)
		card.set_badge(tr("Detected") if kind == _detected_kind else "")
		card.refresh()
	identify_picture.set_device(_kind if not _kind.is_empty() else "radio", _family)
	identify_picture.set_stick_mode(_stick_mode())
	identify_picture.modulate.a = 1.0 if not _kind.is_empty() else 0.0


# --- Step 2: Mode -----------------------------------------------------------------------------------------------

func _build_mode(parent: Control) -> void:
	var page := _page(parent, "mode", "Which stick does what?", "")
	_mode_heading = page.get_child(0) as Label
	_mode_intro = page.get_child(1) as Label
	_mode_row = HBoxContainer.new()
	_mode_row.name = "ModeCards"
	_mode_row.add_theme_constant_override("separation", 20)
	page.add_child(_mode_row)


func _rebuild_mode_cards() -> void:
	var kind := _kind if not _kind.is_empty() else "radio"
	if _mode_cards_kind == kind:
		return
	_mode_cards_kind = kind
	for child in _mode_row.get_children():
		_mode_row.remove_child(child)
		child.queue_free()
	mode_cards.clear()
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var options := GAMEPAD_PRESETS if kind == "gamepad" else STICK_PRESETS
	for preset in options:
		var card := ChoiceCard.new(preset, "gamepad" if kind == "gamepad" else "radio", preset, PRESET_TITLES[preset],
			PRESET_DESCRIPTIONS[preset])
		card.name = "Preset_" + preset
		card.button_group = group
		card.base_height = 420.0
		card.set_picture_height(250.0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_on_preset_chosen.bind(preset))
		_mode_row.add_child(card)
		mode_cards[preset] = card
	_retranslate_cards()


func _on_preset_chosen(preset: String) -> void:
	if is_busy():
		return
	_preset = preset
	_refresh_mode()
	_update_footer()


func _refresh_mode() -> void:
	_rebuild_mode_cards()
	_mode_intro.text = tr("Pick the layout you fly with. You can change it later in Controls.") if _kind == "gamepad" \
		else tr("Pick your transmitter's stick mode. Calibration still detects each channel by movement.")
	for preset: String in mode_cards:
		var card: ChoiceCard = mode_cards[preset]
		card.set_pressed_no_signal(preset == _preset)
		card.set_badge(tr("Current") if preset == str(_info.get("preset", "")) else "")
		card.refresh()


# --- Step 3: Calibrate ------------------------------------------------------------------------------------------

func _build_calibrate(parent: Control) -> void:
	var page := _page(parent, "calibrate", "Calibrate the radio",
		"The simulator measures which channel each stick sends, its centre and its endpoints. Nothing starts until you press Start calibration, and the result stays in the draft until you Save.")
	_calibrate_heading = page.get_child(0) as Label
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 36)
	page.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	left.add_child(Widgets.label("Before you start", "SectionLabel"))
	_checklist = VBoxContainer.new()
	_checklist.name = "Checklist"
	_checklist.add_theme_constant_override("separation", 6)
	left.add_child(_checklist)
	left.add_child(Widgets.gap(8))
	var actions := HBoxContainer.new()
	left.add_child(actions)
	start_calibration_button = Widgets.button("Start calibration", "PrimaryButton", "StartCalibration")
	start_calibration_button.custom_minimum_size.x = 280.0
	start_calibration_button.pressed.connect(_start_calibration)
	actions.add_child(start_calibration_button)
	calibration_banner = _banner("CalibrationResult", UiTheme.FOCUS)
	calibration_label = calibration_banner.get_child(0) as Label
	calibration_banner.visible = false
	left.add_child(calibration_banner)
	_calibration_art = Pictogram.new()
	_calibration_art.subject = "radio"
	_calibration_art.custom_minimum_size = Vector2(380.0, 260.0)
	_calibration_art.name = "CalibrationArt"
	body.add_child(_calibration_art)


func _refresh_calibrate() -> void:
	var joystick := _kind == "joystick"
	_calibrate_heading.text = "Calibrate the joystick" if joystick else "Calibrate the radio"
	var lines := JOYSTICK_CHECKLIST if joystick else RADIO_CHECKLIST
	if _checklist.get_child_count() != lines.size() or str(_checklist.get_meta("kind", "")) != _kind:
		for child in _checklist.get_children():
			_checklist.remove_child(child)
			child.queue_free()
		for line in lines:
			var row := Widgets.label("•  " + tr(line), "SecondaryLabel", true, false)
			row.set_meta("msgid", line)
			_checklist.add_child(row)
		_checklist.set_meta("kind", _kind)
	_calibration_art.subject = "joystick" if joystick else "radio"
	var busy := _busy == BUSY_CALIBRATION
	start_calibration_button.disabled = is_busy()
	start_calibration_button.text = "Calibrate again" if _calibration == "ok" else "Start calibration"
	start_calibration_button.accessibility_name = tr("Calibrate again") if _calibration == "ok" else tr("Start calibration")
	var text := ""
	var color := UiTheme.FOCUS
	if busy:
		text = tr("Calibration is running…")
	elif not _calibration_start_error.is_empty():
		text = _calibration_start_error
		color = UiTheme.ERROR
	elif _calibration == "ok":
		text = tr("Calibration finished.") + ("" if _calibration_message.is_empty() else "  " + _calibration_message)
	elif _calibration == "failed":
		text = _calibration_message if not _calibration_message.is_empty() else tr("Calibration did not finish.")
		color = UiTheme.CAUTION
	calibration_label.text = text
	calibration_banner.add_theme_stylebox_override("panel", _banner_style(color))
	calibration_banner.visible = not text.is_empty()


func _start_calibration() -> void:
	if _closing or is_busy() or current_step() != "calibrate":
		return
	_calibration_start_error = ""
	if not _host_bool("request_calibration", []):
		_calibration_start_error = _host_error("Calibration could not start.")
		_refresh_calibrate()
		return
	_busy = BUSY_CALIBRATION
	_calibration = ""
	_calibration_message = ""
	_refresh_calibrate()
	_update_footer()
	set_process(false)
	if hide_while_calibrating:
		_surface.set_active(false)


# --- Step 4: Test -----------------------------------------------------------------------------------------------

func _build_test(parent: Control) -> void:
	var page := _page(parent, "test", "Test the controls",
		"Move each stick. The model should move the way you expect; if a channel works backwards, turn on Reverse next to it.")
	var body := HFlowContainer.new()
	body.name = "TestBody"
	body.add_theme_constant_override("h_separation", 40)
	body.add_theme_constant_override("v_separation", 24)
	page.add_child(body)
	var sticks := HBoxContainer.new()
	sticks.add_theme_constant_override("separation", 24)
	body.add_child(sticks)
	left_gimbal = GimbalView.new()
	left_gimbal.name = "LeftGimbal"
	left_gimbal.side = 210.0
	sticks.add_child(left_gimbal)
	right_gimbal = GimbalView.new()
	right_gimbal.name = "RightGimbal"
	right_gimbal.side = 210.0
	sticks.add_child(right_gimbal)
	aircraft = AircraftView.new()
	aircraft.name = "Aircraft"
	body.add_child(aircraft)
	var channels := VBoxContainer.new()
	channels.name = "Channels"
	channels.add_theme_constant_override("separation", 10)
	body.add_child(channels)
	for channel in CHANNELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		channels.add_child(row)
		var bar := ChannelBarView.new()
		bar.name = "Bar_" + channel
		bar.label_width = 100.0
		bar.track_width = 180.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.one_ended = channel == "throttle"
		row.add_child(bar)
		channel_bars[channel] = bar
		var toggle := CheckButton.new()
		toggle.name = "Reverse_" + channel
		toggle.text = "Reverse"
		toggle.theme_type_variation = "SettingsToggle"
		toggle.toggled.connect(_on_reverse_toggled.bind(channel))
		row.add_child(toggle)
		reverse_toggles[channel] = toggle
	channels.add_child(Widgets.gap(4))
	channels.add_child(Widgets.label("Buttons held now", "SectionLabel"))
	_pressed_row = HBoxContainer.new()
	_pressed_row.name = "PressedButtons"
	_pressed_row.add_theme_constant_override("separation", 8)
	_pressed_row.custom_minimum_size.y = 40.0
	channels.add_child(_pressed_row)
	_no_buttons = Widgets.label("None", "SecondaryLabel")
	_no_buttons.name = "NoButtons"
	_no_buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pressed_row.add_child(_no_buttons)
	for index in MAX_PRESSED_CHIPS:
		var chip := BindingChip.new()
		chip.visible = false
		chip.live_pressed = true
		_pressed_row.add_child(chip)
		_pressed_chips.append(chip)


func _refresh_test() -> void:
	var trigger := _preset == "trigger_absolute"
	var layout: Array = CalibrationView.gimbal_functions(_stick_mode())
	if trigger:
		layout = [["yaw", ""], ["roll", "pitch"]]
	for index in 2:
		var gimbal := left_gimbal if index == 0 else right_gimbal
		var functions: Array = layout[index]
		var y_name := str(functions[1])
		var words := PackedStringArray()
		if not y_name.is_empty():
			words.append(tr(CHANNEL_NAMES[y_name]))
		words.append(tr(CHANNEL_NAMES[str(functions[0])]))
		gimbal.caption = " · ".join(words)
	for channel: String in channel_bars:
		(channel_bars[channel] as ChannelBarView).label = tr(CHANNEL_NAMES[channel])
		var toggle: CheckButton = reverse_toggles[channel]
		toggle.add_theme_font_size_override("font_size", toggle.get_theme_font_size("font_size", "SecondaryLabel"))
	_throttle_centered = -1
	_poll_preview()


## A radio or trigger throttle rests at LOW (one-ended); a gamepad rate-throttle stick is centred.
func _apply_throttle_layout(centered: bool) -> void:
	var state := 1 if centered else 0
	if state == _throttle_centered:
		return
	_throttle_centered = state
	var layout: Array = CalibrationView.gimbal_functions(_stick_mode())
	if _preset == "trigger_absolute":
		layout = [["yaw", ""], ["roll", "pitch"]]
	for index in 2:
		var gimbal := left_gimbal if index == 0 else right_gimbal
		gimbal.one_ended_y = str(layout[index][1]) == "throttle" and not centered
		gimbal.end_labels = PackedStringArray([tr("FULL"), tr("LOW")]) if gimbal.one_ended_y else PackedStringArray()
	(channel_bars.throttle as ChannelBarView).one_ended = not centered


func _poll_preview() -> void:
	preview_calls += 1
	var sample := _host_dict("preview")
	var roll := _number(sample, "roll", -1.0, 1.0)
	var pitch := _number(sample, "pitch", -1.0, 1.0)
	var yaw := _number(sample, "yaw", -1.0, 1.0)
	var centered := bool(sample.get("throttle_centered", false))
	var throttle := _number(sample, "throttle", -1.0 if centered else 0.0, 1.0)
	var level := _number(sample, "throttle_level", 0.0, 1.0) if sample.has("throttle_level") else clampf(throttle, 0.0, 1.0)
	var values := { roll = roll, pitch = pitch, yaw = yaw, throttle = throttle }
	_apply_throttle_layout(centered)
	for channel: String in channel_bars:
		var bar: ChannelBarView = channel_bars[channel]
		bar.set_value(values[channel])
		bar.highlight = ChannelBarView.Highlight.MOVING if absf(float(values[channel])) > 0.05 and not (channel == "throttle" and not centered and throttle < 0.05) else ChannelBarView.Highlight.IDLE
	var trigger := _preset == "trigger_absolute"
	var layout: Array = CalibrationView.gimbal_functions(_stick_mode())
	if trigger:
		layout = [["yaw", ""], ["roll", "pitch"]]
	for index in 2:
		var gimbal := left_gimbal if index == 0 else right_gimbal
		var functions: Array = layout[index]
		var x := float(values[str(functions[0])])
		var y := 0.0
		match str(functions[1]):
			"pitch":
				y = pitch
			"throttle":
				y = GimbalView.throttle_to_y(throttle) if not centered else -throttle
		gimbal.set_stick(Vector2(x, y), true)
	aircraft.set_controls(roll, pitch, yaw, level)
	var inverted: Variant = sample.get("inverted", {})
	var reverse_available := bool(sample.get("reverse_available", true))
	if inverted is Dictionary:
		for channel: String in reverse_toggles:
			var toggle: CheckButton = reverse_toggles[channel]
			if toggle.disabled == reverse_available:
				toggle.disabled = not reverse_available
				toggle.tooltip_text = "" if reverse_available else tr("A radio's directions come from calibration. Reverse a channel on the transmitter, or calibrate again.")
			var on := bool(inverted.get(channel, false))
			if toggle.button_pressed != on:
				toggle.set_pressed_no_signal(on)
	var buttons := PackedInt32Array()
	var raw: Variant = sample.get("buttons", [])
	if raw is Array or raw is PackedInt32Array or raw is PackedInt64Array:
		for button: Variant in raw:
			if buttons.size() < MAX_PRESSED_CHIPS:
				buttons.append(int(button))
	if buttons != _pressed:
		_pressed = buttons
		_no_buttons.visible = buttons.is_empty()
		for index in _pressed_chips.size():
			var chip := _pressed_chips[index]
			chip.visible = index < buttons.size()
			if chip.visible:
				chip.set_binding({"type": "button", "button": buttons[index]}, _family, _info, {"kind": _kind})


func _on_reverse_toggled(on: bool, channel: String) -> void:
	if is_busy() or _closing:
		return
	_host_call("set_channel_inverted", [channel, on])


static func _number(sample: Dictionary, key: String, lo: float, hi: float) -> float:
	var value: Variant = sample.get(key, 0.0)
	if not (value is float or value is int) or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), lo, hi)


# --- Step 5: Switches & buttons ---------------------------------------------------------------------------------

func _build_switches(parent: Control) -> void:
	var page := _page(parent, "switches", "Switches and buttons",
		"Assign the controls you use most: press Assign, then move the switch or press the button. Skip any you do not need; you can change them later in Controls.")
	_vehicle_label = Widgets.label("", "SectionLabel", false, false)
	_vehicle_label.name = "Vehicle"
	page.add_child(_vehicle_label)
	_switch_grid = GridContainer.new()
	_switch_grid.name = "SwitchRows"
	_switch_grid.columns = 4
	_switch_grid.add_theme_constant_override("h_separation", 20)
	_switch_grid.add_theme_constant_override("v_separation", 10)
	page.add_child(_switch_grid)


func _build_switch_rows() -> void:
	for child in _switch_grid.get_children():
		_switch_grid.remove_child(child)
		child.queue_free()
	assign_buttons.clear()
	binding_chips.clear()
	row_status.clear()
	var recovery_heading_added := false
	for id in _essentials:
		if id in RECOVERY_ASSIGNABLE and not recovery_heading_added:
			_grid_heading("Recovery (always available)")
			recovery_heading_added = true
		_switch_row(id, false)
	if not recovery_heading_added:
		_grid_heading("Recovery (always available)")
	for id in RECOVERY_READ_ONLY:
		_switch_row(id, true)


func _grid_heading(text: String) -> void:
	var heading := Widgets.label(text, "SectionLabel")
	heading.custom_minimum_size.y = 40.0
	heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_switch_grid.add_child(heading)
	for index in 3:
		var filler := Control.new()
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_switch_grid.add_child(filler)


func _switch_row(id: String, read_only: bool) -> void:
	var title := Widgets.label(item_title(id), "", false)
	title.name = "Title_" + id.replace(":", "_")
	title.custom_minimum_size.x = 360.0
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_switch_grid.add_child(title)
	var chip := BindingChip.new()
	chip.name = "Chip_" + id.replace(":", "_")
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.custom_minimum_size.x = 120.0
	_switch_grid.add_child(chip)
	binding_chips[id] = chip
	if read_only:
		var note := Widgets.label("Always kept", "SecondaryLabel")
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_switch_grid.add_child(note)
	else:
		var button := Widgets.button("Assign", "", "Assign_" + id.replace(":", "_"))
		button.custom_minimum_size.x = 150.0
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_start_capture.bind(id))
		_switch_grid.add_child(button)
		assign_buttons[id] = button
	var status := Widgets.label("", "SecondaryLabel", false, false)
	status.name = "Status_" + id.replace(":", "_")
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.clip_text = true
	_switch_grid.add_child(status)
	row_status[id] = status


func _refresh_switches() -> void:
	_vehicle_label.text = tr("Suggested for: %s") % tr(vehicle_name(_capabilities))
	for id: String in binding_chips:
		_refresh_chip(id)
		if id in RECOVERY_READ_ONLY:
			(row_status[id] as Label).text = tr("Needed to leave menus and dialogs.")
	_set_switch_buttons_enabled(not is_busy())


func _refresh_chip(id: String) -> void:
	var chip: BindingChip = binding_chips.get(id)
	if chip == null:
		return
	var binding := _host_dict("binding_for", [id])
	if binding.is_empty():
		binding = {"type": "unbound"}
	chip.action_name = tr(item_title(id))
	chip.set_binding(binding, _family, _info, {"kind": _kind})
	chip.set_label(str(binding.get("display_label", "")))


func _start_capture(id: String) -> void:
	if _closing or is_busy() or current_step() != "switches":
		return
	var status: Label = row_status.get(id)
	if not _host_bool("capture", [id]):
		if status != null:
			status.text = _host_error("Assignment could not start.")
			status.add_theme_color_override("font_color", UiTheme.ERROR)
		return
	_busy = id
	if status != null:
		status.text = tr("Waiting: move a switch or press a button. Esc or Back cancels.")
		status.add_theme_color_override("font_color", UiTheme.CAUTION)
	_set_switch_buttons_enabled(false)
	_set_capture_input(false)
	_update_footer()


func _set_switch_buttons_enabled(enabled: bool) -> void:
	for id: String in assign_buttons:
		(assign_buttons[id] as Button).disabled = not enabled


## While the host captures, the surface stops handling keys so Esc, the press and its release reach the owner.
func _set_capture_input(enabled: bool) -> void:
	_surface.set_process_input(enabled)
	_surface.set_process_unhandled_input(enabled)


# --- Step 6: Summary --------------------------------------------------------------------------------------------

func _build_summary(parent: Control) -> void:
	var page := _page(parent, "summary", "Check and save",
		"The numbers on the picture match the list. Save keeps these settings; Back changes them.")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 36)
	page.add_child(body)
	var stage := Control.new()
	stage.name = "SummaryStage"
	stage.custom_minimum_size = Vector2(620.0, 380.0)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stage)
	summary_picture = DevicePicture.new()
	summary_picture.name = "SummaryPicture"
	summary_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_picture.custom_minimum_size = Vector2.ZERO
	summary_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(summary_picture)
	summary_overlay = PictureOverlay.new()
	summary_overlay.picture = summary_picture
	summary_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(summary_overlay)
	summary_picture.resized.connect(summary_overlay.queue_redraw)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	body.add_child(right)
	summary_facts = Widgets.label("", "SecondaryLabel", true, false)
	summary_facts.name = "Facts"
	right.add_child(summary_facts)
	summary_list = VBoxContainer.new()
	summary_list.name = "SummaryList"
	summary_list.add_theme_constant_override("separation", 8)
	right.add_child(summary_list)


func _refresh_summary() -> void:
	var kind := _kind if not _kind.is_empty() else "radio"
	summary_picture.set_device(kind, _family)
	summary_picture.set_stick_mode(_stick_mode())
	var calibration := tr("not needed for gamepads")
	if kind != "gamepad":
		calibration = tr("done") if _calibration == "ok" else tr("skipped; the current calibration is kept")
	summary_facts.text = "%s\n%s\n%s" % [
		tr("Device type: %s") % tr(KIND_TITLES[kind]),
		tr("Stick layout: %s") % tr(PRESET_TITLES.get(_preset, "Mode 2")),
		tr("Calibration: %s") % calibration,
	]
	for child in summary_list.get_children():
		summary_list.remove_child(child)
		child.queue_free()
	var marks: Array = []
	var lamps: Array = []
	if kind != "gamepad":
		summary_picture.set_radio_controls([])
	var picture_ids := summary_picture.control_ids()
	var number := 0
	for id: String in Array(_essentials) + Array(RECOVERY_READ_ONLY):
		var binding := _host_dict("binding_for", [id])
		if binding.is_empty():
			binding = {"type": "unbound"}
		var bound := str(binding.get("type", "unbound")) != "unbound"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		summary_list.add_child(row)
		var badge := NumberBadge.new()
		if bound:
			number += 1
			badge.number = number
			for control_id in control_ids_for(binding):
				if kind != "gamepad" and not picture_ids.has(control_id) and lamps.size() < MAX_RADIO_LAMPS:
					# The lamp shows the physical control; the badge beside it carries the list number.
					var entry := {}
					if control_id.begins_with("button:"):
						entry["button"] = int(control_id.trim_prefix("button:"))
						entry["label"] = "B%d" % int(entry.button)
					else:
						entry["axis"] = int(control_id.trim_prefix("axis:"))
						entry["label"] = "A%d" % int(entry.axis)
					lamps.append(entry)
				marks.append([control_id, number])
		row.add_child(badge)
		var title := Widgets.label(item_title(id), "SecondaryLabel")
		title.custom_minimum_size.x = 340.0
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(title)
		var chip := BindingChip.new()
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.action_name = tr(item_title(id))
		chip.set_binding(binding, _family, _info, {"kind": _kind})
		chip.set_label(str(binding.get("display_label", "")))
		row.add_child(chip)
	if kind != "gamepad":
		summary_picture.set_radio_controls(lamps)
	summary_overlay.marks = marks
	summary_overlay.queue_redraw()


# --- Shared builders --------------------------------------------------------------------------------------------

func _page(parent: Control, id: String, heading: String, intro: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "Page_" + id
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16)
	page.visible = false
	parent.add_child(page)
	var title := Widgets.label(heading, "SectionTitle", true)
	title.name = "Heading"
	page.add_child(title)
	var body := Widgets.label(intro, "SecondaryLabel", true, not intro.is_empty())
	body.name = "Intro"
	page.add_child(body)
	pages[id] = page
	return page


func _banner(node_name: String, color: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.name = node_name
	banner.add_theme_stylebox_override("panel", _banner_style(color))
	var text := Widgets.label("", "SecondaryLabel", true, false)
	text.name = "Text"
	banner.add_child(text)
	return banner


static func _banner_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.12)
	style.border_color = Color(color, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(UiTheme.RADIUS)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _retranslate() -> void:
	_compute_steps()
	cancel_button.accessibility_name = tr("Cancel setup")
	skip_button.accessibility_name = tr("Skip this step")
	back_button.accessibility_name = tr("Previous step")
	for channel: String in reverse_toggles:
		(reverse_toggles[channel] as CheckButton).accessibility_name = tr("Reverse %s") % tr(CHANNEL_NAMES[channel])
	for id: String in assign_buttons:
		(assign_buttons[id] as Button).accessibility_name = tr("Assign %s") % tr(item_title(id))
	_retranslate_cards()
	aircraft.set_texts(tr("Seen from behind"), tr("Ailerons"), tr("Elevator"), tr("Rudder"), tr("Throttle"))
	for row in _checklist.get_children():
		if row.has_meta("msgid"):
			(row as Label).text = "•  " + tr(str(row.get_meta("msgid")))
	if not current_step().is_empty() and host != null:
		_show_step()


func _retranslate_cards() -> void:
	for kind: String in kind_cards:
		(kind_cards[kind] as ChoiceCard).accessibility_name = tr("Controller type: %s") % tr(KIND_TITLES[kind])
	for preset: String in mode_cards:
		(mode_cards[preset] as ChoiceCard).accessibility_name = tr("Stick layout: %s") % tr(PRESET_TITLES[preset])


# --- Inner widgets ----------------------------------------------------------------------------------------------

## A large toggle card: pictogram, title, one-line description and an optional badge ("Detected", "Current").
class ChoiceCard extends Button:
	var choice := ""
	var base_height := 280.0
	var pictogram: Pictogram
	var title: Label
	var description: Label
	var badge: Label
	var _content: VBoxContainer
	var _check := StyleBoxFlat.new()

	func _init(choice_id: String, subject: String, preset: String, title_text: String, description_text: String) -> void:
		choice = choice_id
		toggle_mode = true
		focus_mode = Control.FOCUS_ALL
		clip_contents = true
		text = ""
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.set_corner_radius_all(UiTheme.RADIUS + 5)
			style.anti_aliasing = true
			var selected: bool = state in ["pressed", "hover_pressed"]
			style.bg_color = UiTheme.CARD.lerp(UiTheme.FOCUS, 0.08) if selected else (UiTheme.BUTTON.hover if state == "hover" else UiTheme.CARD)
			style.border_color = UiTheme.FOCUS if selected else (UiTheme.CRYSTAL if state == "hover" else Color(UiTheme.SURFACE_LIGHT, 0.16))
			style.set_border_width_all(2 if selected else 1)
			add_theme_stylebox_override(state, style)
		_content = VBoxContainer.new()
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content.offset_left = 20.0
		_content.offset_top = 18.0
		_content.offset_right = -20.0
		_content.offset_bottom = -18.0
		_content.add_theme_constant_override("separation", 8)
		add_child(_content)
		pictogram = Pictogram.new()
		pictogram.subject = subject
		pictogram.preset = preset
		pictogram.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_content.add_child(pictogram)
		title = Label.new()
		title.text = title_text
		title.theme_type_variation = "CardTitle"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(title)
		description = Label.new()
		description.text = description_text
		description.theme_type_variation = "SecondaryLabel"
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_content.add_child(description)
		badge = Label.new()
		badge.theme_type_variation = "SectionLabel"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		badge.add_theme_color_override("font_color", UiTheme.FOCUS)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.text = " "
		_content.add_child(badge)
		toggled.connect(func(_on: bool) -> void: refresh())
		custom_minimum_size = Vector2(260.0, base_height)

	## The row is always reserved, so titles line up across cards with and without a badge.
	func set_badge(text_value: String) -> void:
		badge.text = text_value if not text_value.is_empty() else " "

	func set_picture_height(height: float) -> void:
		pictogram.custom_minimum_size = Vector2(pictogram.custom_minimum_size.x, height)

	func refresh() -> void:
		pictogram.lit = button_pressed
		_fit()
		queue_redraw()

	func _notification(what: int) -> void:
		if what in [NOTIFICATION_RESIZED, NOTIFICATION_THEME_CHANGED]:
			_fit.call_deferred()

	func _fit() -> void:
		if not is_inside_tree():
			return
		var needed := maxf(base_height, _content.get_combined_minimum_size().y + 36.0)
		if not is_equal_approx(custom_minimum_size.y, needed):
			custom_minimum_size = Vector2(custom_minimum_size.x, needed)

	func _draw() -> void:
		if not button_pressed:
			return
		# A check badge in the top-right corner marks the selection independently of focus.
		var centre := Vector2(size.x - 24.0, 24.0)
		draw_circle(centre, 12.0, UiTheme.FOCUS, true, -1.0, true)
		draw_polyline(PackedVector2Array([centre + Vector2(-5.5, 0.5), centre + Vector2(-1.5, 4.5), centre + Vector2(6.0, -4.0)]),
			UiTheme.ACCENT_INK, 2.5, true)


## A vector pictogram of a device kind ("radio", "gamepad", "joystick"). With a preset ("mode1", "mode2",
## "trigger_absolute") each stick shows its functions as arrows and named rows below the device.
class Pictogram extends Control:
	const DESIGN := Vector2(240.0, 150.0)
	var subject := "gamepad":
		set(value):
			if subject != value:
				subject = value
				queue_redraw()
	var preset := "":
		set(value):
			if preset != value:
				preset = value
				update_minimum_size()
				queue_redraw()
	var lit := false:
		set(value):
			if lit != value:
				lit = value
				queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(200.0, 120.0)

	func _get_minimum_size() -> Vector2:
		return Vector2(0.0, 0.0 if preset.is_empty() else _rows_height() + 150.0)

	func _rows_height() -> float:
		var font := get_theme_font("font", "Label")
		return (font.get_height(_font_size()) + 4.0) * 2.0 + 10.0

	func _font_size() -> int:
		return get_theme_font_size("font_size", "SecondaryLabel")

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			update_minimum_size()
			queue_redraw()

	## [[left x, left y], [right x, right y]] function names; "" for an unused axis.
	func stick_functions() -> Array:
		match preset:
			"mode1":
				return [["yaw", "pitch"], ["roll", "throttle"]]
			"trigger_absolute":
				return [["yaw", ""], ["roll", "pitch"]]
		return [["yaw", "throttle"], ["roll", "pitch"]]

	func _draw() -> void:
		var rows := 0.0 if preset.is_empty() else _rows_height()
		var area := Rect2(Vector2.ZERO, Vector2(size.x, maxf(1.0, size.y - rows)))
		var s := minf(area.size.x / DESIGN.x, area.size.y / DESIGN.y)
		var origin := area.get_center() - DESIGN * s * 0.5
		var ink := UiTheme.FOCUS if lit else UiTheme.TEXT_2
		var fill := Color(UiTheme.FOCUS, 0.07) if lit else Color(UiTheme.TEXT_2, 0.06)
		var centres: Array[Vector2] = []
		match subject:
			"radio":
				centres = _draw_radio(origin, s, ink, fill)
			"joystick":
				_draw_joystick(origin, s, ink, fill)
			_:
				centres = _draw_gamepad(origin, s, ink, fill)
		if preset.is_empty() or centres.is_empty():
			return
		var functions := stick_functions()
		var font := get_theme_font("font", "Label")
		var font_size := _font_size()
		var line := font.get_height(font_size) + 4.0
		var top := area.end.y + 8.0
		for side in 2:
			var centre: Vector2 = centres[side]
			var reach := (26.0 if subject == "radio" else 21.0) * s * 0.85
			var x_name := str(functions[side][0])
			var y_name := str(functions[side][1])
			if not y_name.is_empty():
				_double_arrow(centre, Vector2(0.0, reach), _function_color(y_name), 2.5)
			if not x_name.is_empty():
				_double_arrow(centre, Vector2(reach, 0.0), _function_color(x_name), 2.5)
			var column_x := size.x * (0.27 if side == 0 else 0.73)
			var row := 0
			for entry: Array in [[y_name, true], [x_name, false]]:
				var function := str(entry[0])
				if function.is_empty():
					continue
				var label := tr(CHANNEL_NAMES[function])
				var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 28.0
				var left := column_x - width * 0.5
				var mid := Vector2(left + 9.0, top + row * line + line * 0.5 - 2.0)
				var color := _function_color(function)
				_double_arrow(mid, Vector2(0.0, 9.0) if bool(entry[1]) else Vector2(9.0, 0.0), color, 2.0)
				draw_string(font, Vector2(left + 28.0, top + row * line + font.get_ascent(font_size)), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
				row += 1
		if preset == "trigger_absolute" and subject == "gamepad":
			var trigger := Rect2(origin + Vector2(148.0, 20.0) * s, Vector2(36.0, 12.0) * s)
			draw_rect(trigger, UiTheme.FOCUS, true)
			var label := tr("Throttle")
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, Vector2(trigger.get_center().x - width * 0.5, trigger.position.y - 6.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.FOCUS)

	func _function_color(function: String) -> Color:
		if function == "throttle":
			return UiTheme.FOCUS
		return UiTheme.TEXT if lit else Color(UiTheme.TEXT, 0.85)

	func _double_arrow(centre: Vector2, half: Vector2, color: Color, width: float) -> void:
		draw_line(centre - half, centre + half, color, width, true)
		var direction := half.normalized()
		var normal := Vector2(-direction.y, direction.x)
		var head := maxf(4.0, half.length() * 0.35)
		for tip: Vector2 in [centre + half, centre - half]:
			var back := -direction if tip == centre + half else direction
			draw_colored_polygon(PackedVector2Array([tip + direction * 0.0 - back * 1.5, tip + back * head + normal * head * 0.6,
				tip + back * head - normal * head * 0.6]), color)

	func _p(origin: Vector2, s: float, design: Vector2) -> Vector2:
		return origin + design * s

	func _draw_gamepad(origin: Vector2, s: float, ink: Color, fill: Color) -> Array[Vector2]:
		var outline := _smooth([
			Vector2(70, 36), Vector2(120, 40), Vector2(170, 36), Vector2(198, 40), Vector2(216, 54), Vector2(228, 84),
			Vector2(236, 120), Vector2(230, 140), Vector2(212, 146), Vector2(194, 136), Vector2(176, 114), Vector2(120, 110),
			Vector2(64, 114), Vector2(46, 136), Vector2(28, 146), Vector2(10, 140), Vector2(4, 120), Vector2(12, 84),
			Vector2(24, 54), Vector2(42, 40)])
		var points := PackedVector2Array()
		for point in outline:
			points.append(_p(origin, s, point))
		draw_colored_polygon(points, fill)
		points.append(points[0])
		draw_polyline(points, ink, 2.0, true)
		for x: float in [56.0, 148.0]:
			draw_rect(Rect2(_p(origin, s, Vector2(x, 20.0)), Vector2(36.0, 12.0) * s), ink, false, 1.5)
		var centres: Array[Vector2] = [_p(origin, s, Vector2(84, 80)), _p(origin, s, Vector2(156, 80))]
		var stick := 17.0 if preset.is_empty() else 21.0
		for centre in centres:
			draw_circle(centre, stick * s, Color(UiTheme.PANEL, 0.9), true, -1.0, true)
			draw_circle(centre, stick * s, ink, false, 1.8, true)
			if preset.is_empty():
				draw_circle(centre, 9.0 * s, ink, false, 1.2, true)
		var dpad := _p(origin, s, Vector2(44, 62))
		draw_line(dpad - Vector2(7, 0) * s, dpad + Vector2(7, 0) * s, ink, 3.0 * s, true)
		draw_line(dpad - Vector2(0, 7) * s, dpad + Vector2(0, 7) * s, ink, 3.0 * s, true)
		var face := _p(origin, s, Vector2(198, 62))
		for offset: Vector2 in [Vector2(0, -8), Vector2(0, 8), Vector2(-8, 0), Vector2(8, 0)]:
			draw_circle(face + offset * s, 3.4 * s, ink, true, -1.0, true)
		for x: float in [108.0, 132.0]:
			draw_circle(_p(origin, s, Vector2(x, 58)), 2.6 * s, ink, true, -1.0, true)
		return centres

	func _draw_radio(origin: Vector2, s: float, ink: Color, fill: Color) -> Array[Vector2]:
		var body := Rect2(_p(origin, s, Vector2(34, 42)), Vector2(172, 98) * s)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(int(16 * s))
		style.bg_color = fill
		style.border_color = ink
		style.set_border_width_all(2)
		style.anti_aliasing = true
		draw_style_box(style, body)
		draw_line(_p(origin, s, Vector2(188, 42)), _p(origin, s, Vector2(200, 8)), ink, 3.0, true)
		draw_circle(_p(origin, s, Vector2(200, 8)), 3.0 * s, ink, true, -1.0, true)
		draw_rect(Rect2(_p(origin, s, Vector2(104, 50)), Vector2(32, 15) * s), ink, false, 1.5)
		for x: float in [52.0, 66.0, 174.0, 188.0]:
			draw_circle(_p(origin, s, Vector2(x, 60)), 3.0 * s, ink, false, 1.2, true)
			draw_line(_p(origin, s, Vector2(x, 60)), _p(origin, s, Vector2(x + 2.0, 50)), ink, 2.0, true)
		var centres: Array[Vector2] = [_p(origin, s, Vector2(82, 100)), _p(origin, s, Vector2(158, 100))]
		for centre in centres:
			draw_rect(Rect2(centre - Vector2(26, 26) * s, Vector2(52, 52) * s), Color(UiTheme.PANEL, 0.9), true)
			draw_rect(Rect2(centre - Vector2(26, 26) * s, Vector2(52, 52) * s), ink, false, 1.5)
			draw_circle(centre, 5.0 * s, ink, true, -1.0, true)
		return centres

	func _draw_joystick(origin: Vector2, s: float, ink: Color, fill: Color) -> void:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(int(10 * s))
		style.bg_color = fill
		style.border_color = ink
		style.set_border_width_all(2)
		style.anti_aliasing = true
		draw_style_box(style, Rect2(_p(origin, s, Vector2(66, 116)), Vector2(108, 30) * s))
		draw_rect(Rect2(_p(origin, s, Vector2(115, 58)), Vector2(10, 62) * s), ink, true)
		style.set_corner_radius_all(int(12 * s))
		draw_style_box(style, Rect2(_p(origin, s, Vector2(102, 14)), Vector2(36, 54) * s))
		draw_circle(_p(origin, s, Vector2(120, 26)), 5.0 * s, ink, false, 1.5, true)
		draw_rect(Rect2(_p(origin, s, Vector2(96, 38)), Vector2(6, 14) * s), ink, true)
		for x: float in [84.0, 156.0]:
			draw_circle(_p(origin, s, Vector2(x, 131)), 4.0 * s, ink, true, -1.0, true)

	static func _smooth(points: Array) -> PackedVector2Array:
		var result := PackedVector2Array()
		var count := points.size()
		for index in count:
			var p0: Vector2 = points[(index - 1 + count) % count]
			var p1: Vector2 = points[index]
			var p2: Vector2 = points[(index + 1) % count]
			var p3: Vector2 = points[(index + 2) % count]
			for step in 6:
				var t := float(step) / 6.0
				var t2 := t * t
				var t3 := t2 * t
				result.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
		return result


## A small aircraft seen from behind: ailerons, elevator and rudder trailing edges deflect with roll, pitch and yaw
## (pitch +1 = stick back = elevator up), and a throttle bar. Redraws only when a value changes.
class AircraftView extends Control:
	const DESIGN := Vector2(400.0, 230.0)
	const EPSILON := 0.003
	var redraw_requests := 0
	var _roll := 0.0
	var _pitch := 0.0
	var _yaw := 0.0
	var _throttle := 0.0
	var _texts := PackedStringArray(["", "", "", "", ""])

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(500.0, 300.0)

	func set_texts(caption: String, ailerons: String, elevator: String, rudder: String, throttle: String) -> void:
		var next := PackedStringArray([caption, ailerons, elevator, rudder, throttle])
		if next != _texts:
			_texts = next
			queue_redraw()

	func set_controls(roll: float, pitch: float, yaw: float, throttle: float) -> void:
		if absf(roll - _roll) <= EPSILON and absf(pitch - _pitch) <= EPSILON and absf(yaw - _yaw) <= EPSILON \
				and absf(throttle - _throttle) <= EPSILON:
			return
		_roll = roll
		_pitch = pitch
		_yaw = yaw
		_throttle = throttle
		redraw_requests += 1
		queue_redraw()

	func controls() -> Vector4:
		return Vector4(_roll, _pitch, _yaw, _throttle)

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var small := get_theme_font_size("font_size", "SectionLabel")
		var caption_h := font.get_height(get_theme_font_size("font_size", "SecondaryLabel")) + 6.0
		var area := Rect2(Vector2.ZERO, Vector2(size.x, maxf(1.0, size.y - caption_h)))
		var s := minf(area.size.x / DESIGN.x, area.size.y / DESIGN.y)
		var origin := area.get_center() - DESIGN * s * 0.5
		var frame := UiTheme.TEXT_2
		var surface_ink := UiTheme.FOCUS
		var p := func(x: float, y: float) -> Vector2: return origin + Vector2(x, y) * s
		# Propeller disc, brighter with throttle.
		draw_circle(p.call(180.0, 124.0), 50.0 * s, Color(UiTheme.FOCUS, 0.04 + 0.16 * clampf(_throttle, 0.0, 1.0)), true, -1.0, true)
		draw_circle(p.call(180.0, 124.0), 50.0 * s, Color(UiTheme.EDGE, 0.8), false, 1.0, true)
		# Wing with a little dihedral; ailerons on the outer panels.
		draw_polyline(PackedVector2Array([p.call(16.0, 112.0), p.call(162.0, 124.0), p.call(198.0, 124.0), p.call(344.0, 112.0)]),
			frame, 7.0 * s, true)
		_surface(p.call(30.0, 113.2), p.call(118.0, 120.4), Vector2(0.0, _roll * 26.0 * s), surface_ink)
		_surface(p.call(242.0, 120.4), p.call(330.0, 113.2), Vector2(0.0, -_roll * 26.0 * s), surface_ink)
		# Fin and rudder.
		draw_line(p.call(180.0, 108.0), p.call(180.0, 24.0), frame, 6.0 * s, true)
		_surface(p.call(180.0, 32.0), p.call(180.0, 96.0), Vector2(_yaw * 26.0 * s, 0.0), surface_ink)
		# Stabiliser and elevator.
		draw_line(p.call(124.0, 104.0), p.call(236.0, 104.0), frame, 5.0 * s, true)
		_surface(p.call(128.0, 104.0), p.call(172.0, 104.0), Vector2(0.0, -_pitch * 24.0 * s), surface_ink)
		_surface(p.call(188.0, 104.0), p.call(232.0, 104.0), Vector2(0.0, -_pitch * 24.0 * s), surface_ink)
		draw_circle(p.call(180.0, 124.0), 17.0 * s, UiTheme.CARD, true, -1.0, true)
		draw_circle(p.call(180.0, 124.0), 17.0 * s, frame, false, 2.0, true)
		var muted := get_theme_color("font_color", "SecondaryLabel")
		_text(font, small, p.call(74.0, 150.0), _texts[1], muted)
		_text(font, small, p.call(286.0, 150.0), _texts[1], muted)
		# The elevator sits between the ailerons, so its label stands off with a leader line.
		draw_line(p.call(234.0, 100.0), p.call(270.0, 70.0), Color(muted, 0.6), 1.0, true)
		_text(font, small, p.call(300.0, 62.0), _texts[2], muted)
		_text(font, small, p.call(226.0, 30.0), _texts[3], muted)
		# Throttle bar.
		var track := Rect2(p.call(376.0, 40.0), Vector2(16.0, 160.0) * s)
		draw_rect(track, UiTheme.BUTTON.normal, true)
		draw_rect(track, UiTheme.EDGE, false, 1.0)
		var level := clampf(_throttle, 0.0, 1.0)
		var filled := Rect2(Vector2(track.position.x, track.end.y - track.size.y * level), Vector2(track.size.x, track.size.y * level))
		if filled.size.y >= 1.0:
			draw_rect(filled, UiTheme.FOCUS, true)
		_text(font, small, Vector2(track.get_center().x, track.position.y - 12.0 * s), _texts[4], muted)
		_text(font, small, Vector2(track.get_center().x, track.end.y + 14.0 * s), "%d%%" % roundi(level * 100.0), UiTheme.TEXT)
		var body := get_theme_font_size("font_size", "SecondaryLabel")
		draw_string(font, Vector2(0.0, size.y - font.get_descent(body)), _texts[0], HORIZONTAL_ALIGNMENT_CENTER, size.x, body, muted)

	## A control surface from hinge a→b whose trailing edge is displaced by `offset`.
	func _surface(a: Vector2, b: Vector2, offset: Vector2, color: Color) -> void:
		var moved := offset.length() > 0.5
		var shade := Color(color, 0.85) if moved else Color(UiTheme.EDGE, 0.9)
		if moved:
			draw_colored_polygon(PackedVector2Array([a, b, b + offset, a + offset]), Color(color, 0.30))
			draw_line(a + offset, b + offset, shade, 3.0, true)
		draw_line(a, b, shade, 3.0, true)

	func _text(font: Font, font_size: int, centre: Vector2, value: String, color: Color) -> void:
		var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(centre.x - width * 0.5, centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5),
			value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A numbered circle matching a summary row to its mark on the picture; 0 draws an empty ring (unbound).
class NumberBadge extends Control:
	var number := 0:
		set(value):
			if number != value:
				number = value
				queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _get_minimum_size() -> Vector2:
		var edge := get_theme_font("font", "Label").get_height(get_theme_font_size("font_size", "SectionLabel")) + 8.0
		return Vector2(edge, edge)

	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 1.0
		if number <= 0:
			draw_circle(centre, radius, Color(UiTheme.EDGE, 0.8), false, 1.5, true)
			return
		PictureOverlay.draw_badge(self, centre, radius, number)


## Draws a halo and a numbered badge on each assigned control of a DevicePicture (same rect as the picture).
class PictureOverlay extends Control:
	var picture: Control
	## [[control id, number], …]
	var marks: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE

	static func draw_badge(canvas: Control, centre: Vector2, radius: float, value: int) -> void:
		var font: Font = canvas.get_theme_font("font", "Label")
		var font_size := maxi(11, roundi(radius * 1.25))
		canvas.draw_circle(centre, radius, UiTheme.FOCUS, true, -1.0, true)
		canvas.draw_circle(centre, radius, UiTheme.ACCENT_INK, false, 1.5, true)
		var text := str(value)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		canvas.draw_string(font, Vector2(centre.x - width * 0.5, centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.ACCENT_INK)

	func _draw() -> void:
		if picture == null or not picture.has_method("control_rect"):
			return
		var used := {}
		for mark: Variant in marks:
			if not mark is Array or (mark as Array).size() < 2:
				continue
			var rect: Rect2 = picture.call("control_rect", str(mark[0]))
			if rect.size == Vector2.ZERO:
				continue
			var key := str(mark[0])
			var stacked := int(used.get(key, 0))
			used[key] = stacked + 1
			if stacked == 0:
				var halo := StyleBoxFlat.new()
				halo.draw_center = false
				halo.set_border_width_all(2)
				halo.border_color = UiTheme.CRYSTAL
				halo.set_corner_radius_all(8)
				halo.anti_aliasing = true
				draw_style_box(halo, rect.grow(5.0))
			# Badges stand outward from the picture's centre, so neighbouring controls keep their own corner.
			var radius := 13.0
			var away := rect.get_center() - size * 0.5
			var outward := Vector2(1.0 if away.x >= 0.0 else -1.0, -1.0 if away.y < 0.0 else 1.0)
			var corner := rect.get_center() + rect.size * 0.5 * outward
			var centre := corner + outward * (radius * 0.55) + Vector2(outward.x * stacked * (radius * 2.0 + 3.0), 0.0)
			draw_badge(self, centre, radius, int(mark[1]))
