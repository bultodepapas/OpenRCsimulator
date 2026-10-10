# Pause-only time-of-day editor (TOD-08b). Apply is committed by the flight owner; this dialog never resumes it.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")

signal applied(config: Dictionary)
signal cancelled

const LAYER: int = 12
const INPUT_ERROR: String = "Check the time, date, UTC offset and location. Apply will not save invalid lighting."
const APPLY_ERROR: String = "Could not apply lighting. The flight remains paused; check the values and try again."

var controls: VBoxContainer
var title_label: Label
var description_label: Label
var dialog_panel: PanelContainer
var cancel_button: Button
var apply_button: Button
var error_label: Label
var _focus_order: Array[Control] = []


func _init(initial_config: Variant = null) -> void:
	name = "TimeOfDayDialog"
	layer = LAYER
	var initial: Variant = initial_config if initial_config != null else TimeOfDay.defaults()

	var screen: Control = Control.new()
	screen.name = "Modal"
	screen.theme = UiTheme.build()
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.68)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 16.0
	center.offset_top = 16.0
	center.offset_right = -16.0
	center.offset_bottom = -16.0
	screen.add_child(center)
	dialog_panel = PanelContainer.new()
	dialog_panel.name = "TimeOfDayPanel"
	dialog_panel.theme_type_variation = "Sidebar"
	dialog_panel.custom_minimum_size.x = 720.0
	dialog_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(dialog_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	dialog_panel.add_child(column)

	title_label = _label("Time of day", "TitleLabel")
	column.add_child(title_label)
	description_label = _label(
		"Choose the lighting for this flight. Apply updates the paused flight and its future restarts.",
		"SecondaryLabel", true
	)
	column.add_child(description_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "TimeOfDayScroll"
	scroll.custom_minimum_size.y = 180.0
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	controls = TimeOfDayControls.new(initial) as VBoxContainer
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.focus_order_changed.connect(_set_focus_order)
	scroll.add_child(controls)

	error_label = _label("", "SecondaryLabel", true)
	error_label.name = "ApplyError"
	error_label.visible = false
	error_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.62))
	column.add_child(error_label)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_on_cancel)
	actions.add_child(cancel_button)
	apply_button = Button.new()
	apply_button.name = "Apply"
	apply_button.text = "Apply"
	apply_button.theme_type_variation = "PrimaryButton"
	apply_button.pressed.connect(_on_apply)
	actions.add_child(apply_button)
	column.add_child(actions)
	_set_focus_order()
	_update_texts()


func _ready() -> void:
	get_viewport().size_changed.connect(_sync_panel_size)
	_sync_panel_size()
	_focus_initial_control.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()


func _update_texts() -> void:
	if cancel_button == null:
		return
	title_label.text = tr("Time of day")
	description_label.text = tr("Choose the lighting for this flight. Apply updates the paused flight and its future restarts.")
	cancel_button.text = tr("Cancel")
	apply_button.text = tr("Apply")


func _focus_initial_control() -> void:
	if controls != null and controls.mode_picker != null:
		controls.mode_picker.grab_focus()
	else:
		cancel_button.grab_focus()


func _sync_panel_size() -> void:
	if dialog_panel == null or not is_inside_tree():
		return
	var available_height: float = get_viewport().get_visible_rect().size.y - 32.0
	dialog_panel.custom_minimum_size.y = clampf(available_height, 480.0, 640.0)


func _set_focus_order() -> void:
	if controls == null or cancel_button == null or apply_button == null:
		return
	_focus_order.clear()
	var time_controls: Array[Control] = controls.call("focus_controls")
	for control: Control in time_controls:
		_focus_order.append(control)
	_focus_order.append(cancel_button)
	_focus_order.append(apply_button)
	for index: int in _focus_order.size():
		var current: Control = _focus_order[index]
		var next: Control = _focus_order[(index + 1) % _focus_order.size()]
		var previous: Control = _focus_order[(index + _focus_order.size() - 1) % _focus_order.size()]
		current.focus_next = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
	cancel_button.focus_neighbor_right = cancel_button.get_path_to(apply_button)
	apply_button.focus_neighbor_left = apply_button.get_path_to(cancel_button)


func _on_apply() -> void:
	var result: Dictionary = controls.call("read_draft")
	if not result.get("ok", false):
		error_label.text = tr(INPUT_ERROR)
		error_label.visible = true
		return
	error_label.visible = false
	applied.emit(result.config.duplicate(true))


## The flight reports staging/commit errors here; keep the draft and modal intact for correction or Cancel.
func show_apply_error(_errors: Variant) -> void:
	error_label.text = tr(APPLY_ERROR)
	error_label.visible = true


func _on_cancel() -> void:
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo \
		or event.physical_keycode != KEY_ESCAPE:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is OptionButton:
		var popup: PopupMenu = (focused as OptionButton).get_popup()
		if popup.visible:
			popup.hide()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			cancelled.emit() # Esc cancels this draft; the pause menu remains open underneath.


static func _label(text: String, variation: String, wrap_text: bool = false) -> Label:
	var label_control: Label = Label.new()
	label_control.text = text
	label_control.theme_type_variation = variation
	label_control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if wrap_text:
		label_control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label_control
