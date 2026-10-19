# Pause-only time-of-day editor (TOD-08b). Apply is committed by the flight owner; this dialog never resumes it.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")
const Preferences := preload("res://app_state/preferences.gd")
const MoonConfig := preload("res://environment/moon_config.gd")
const SkyControls := preload("res://ui/sky_controls.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

signal applied(config: Dictionary)
signal cancelled

const LAYER: int = 12
const PANEL_VIEWPORT_GUTTER: float = 16.0
const INPUT_ERROR: String = "Check the time, date, UTC offset and location. Apply will not save invalid lighting."
const APPLY_ERROR: String = "Could not apply lighting. The flight remains paused; check the values and try again."

var controls: VBoxContainer
var title_label: Label
var description_label: Label
var dialog_panel: PanelContainer
var cancel_button: Button
var apply_button: Button
var error_label: Label
var panel_column: VBoxContainer
var body_scroll: ScrollContainer
var _focus_order: Array[Control] = []
var night_only: bool = false
var _size_sync_queued: bool = false
var applied_night_options: Dictionary = Preferences.NIGHT_DEFAULTS.duplicate(true)
## FW-MOON-13: the moon choices applied with the dialog (MoonConfig format).
var applied_moon_config: Dictionary = MoonConfig.defaults()
var applied_sky_config: Dictionary = SkyConfig.defaults()
var sky_controls: VBoxContainer
var visual_tabs: TabBar


func _init(initial_config: Variant = null, initial_night_options: Variant = null, field_world_only: bool = false, initial_sky: Variant = null) -> void:
	name = "TimeOfDayDialog"
	layer = LAYER
	night_only = field_world_only
	var initial: Variant = initial_config if initial_config != null else TimeOfDay.defaults()

	var screen := Screen.mount(self, "Modal")
	screen.dismiss_option_popup_first = true
	screen.close_requested.connect(_on_cancel)
	screen.dim(0.68, "Dim")
	var center: CenterContainer = screen.center(16.0)
	dialog_panel = PanelContainer.new()
	dialog_panel.name = "TimeOfDayPanel"
	dialog_panel.theme_type_variation = "Sidebar"
	dialog_panel.custom_minimum_size.x = 720.0
	dialog_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(dialog_panel)
	panel_column = VBoxContainer.new()
	panel_column.add_theme_constant_override("separation", 10)
	dialog_panel.add_child(panel_column)

	title_label = _label("Time of day", "TitleLabel")
	panel_column.add_child(title_label)
	description_label = _label(
		"Choose the lighting for this flight. Apply updates the paused flight and its future restarts.",
		"SecondaryLabel", true
	)
	if initial_sky != null:
		visual_tabs = TabBar.new()
		visual_tabs.name = "VisualConditionsTabs"
		visual_tabs.add_tab(tr("Time of day"))
		visual_tabs.add_tab(tr("Sky & clouds"))
		visual_tabs.focus_mode = Control.FOCUS_ALL
		panel_column.add_child(visual_tabs)

	body_scroll = ScrollContainer.new()
	body_scroll.name = "TimeOfDayScroll"
	body_scroll.custom_minimum_size.y = 120.0 if night_only else 180.0
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.follow_focus = true
	panel_column.add_child(body_scroll)
	var body_stack := VBoxContainer.new()
	body_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_stack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body_scroll.add_child(body_stack)
	body_stack.add_child(description_label)
	controls = TimeOfDayControls.new(initial, initial_night_options, _session_moon_config()) as VBoxContainer
	if night_only:
		controls.call("set_time_editing_visible", false)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.focus_order_changed.connect(_set_focus_order)
	_use_native_option_popups_when_supported()
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_stack.add_child(pages)
	pages.add_child(controls)
	if initial_sky != null:
		sky_controls = SkyControls.new(initial_sky)
		sky_controls.visible = false
		sky_controls.focus_order_changed.connect(_set_focus_order)
		sky_controls.night_requested.connect(func() -> void:
			controls.call("_on_preset_selected", 5)
			visual_tabs.current_tab = 0)
		sky_controls.night_button.disabled = night_only
		pages.add_child(sky_controls)
		visual_tabs.tab_changed.connect(func(index: int) -> void:
			controls.visible = index == 0
			sky_controls.visible = index == 1
			body_scroll.scroll_vertical = 0
			_set_focus_order())

	error_label = _label("", "SecondaryLabel", true)
	error_label.name = "ApplyError"
	error_label.visible = false
	error_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.62))
	panel_column.add_child(error_label)
	var actions := Widgets.button_row()
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
	panel_column.add_child(actions)
	_set_focus_order()
	_update_texts()


func _ready() -> void:
	get_viewport().size_changed.connect(_schedule_panel_size_sync)
	dialog_panel.minimum_size_changed.connect(_schedule_panel_size_sync)
	_sync_panel_size()
	_focus_initial_control.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()
		_schedule_panel_size_sync()


func _update_texts() -> void:
	if cancel_button == null:
		return
	title_label.text = tr("Field lighting") if night_only else tr("Time of day")
	if sky_controls != null:
		title_label.text = tr("Sky and lighting")
		visual_tabs.set_tab_title(0, tr("Time of day"))
		visual_tabs.set_tab_title(1, tr("Sky & clouds"))
	description_label.text = tr("Choose the field lights and campfire for this paused flight. These visual options do not change flight behavior.") \
		if night_only else tr("Choose the lighting for this flight. Apply updates the paused flight and its future restarts.")
	cancel_button.text = tr("Cancel")
	apply_button.text = tr("Apply")


func _focus_initial_control() -> void:
	if not is_inside_tree():
		return
	if controls != null and night_only and controls.field_lighting_picker != null:
		controls.field_lighting_picker.grab_focus()
	elif controls != null and controls.mode_picker != null:
		controls.mode_picker.grab_focus()
	else:
		cancel_button.grab_focus()


func _use_native_option_popups_when_supported() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		return
	# Godot's embedded Popup teardown emits release-build disconnect errors; native subwindows avoid that path.
	var pickers: Array[OptionButton] = [
		controls.get("mode_picker") as OptionButton,
		controls.get("preset_picker") as OptionButton,
		controls.get("field_lighting_picker") as OptionButton,
		controls.get("campfire_picker") as OptionButton,
	]
	for picker: OptionButton in pickers:
		picker.get_popup().force_native = true


func _sync_panel_size() -> void:
	_size_sync_queued = false
	if dialog_panel == null or not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available_width: float = maxf(0.0, viewport_size.x - PANEL_VIEWPORT_GUTTER * 2.0)
	var available_height: float = maxf(0.0, viewport_size.y - PANEL_VIEWPORT_GUTTER * 2.0)
	var minimum_height: float = 320.0 if night_only else 480.0
	var target_height: float = minf(640.0, available_height)
	if available_height >= minimum_height:
		target_height = maxf(target_height, minimum_height)
	var target_width: float = minf(720.0, available_width)
	if available_height < 620.0:
		panel_column.add_theme_constant_override("separation", 6)
	else:
		panel_column.add_theme_constant_override("separation", 10)
	if dialog_panel.custom_minimum_size != Vector2(target_width, target_height):
		dialog_panel.custom_minimum_size = Vector2(target_width, target_height)
	var fixed_chrome_height: float = dialog_panel.get_combined_minimum_size().y - body_scroll.custom_minimum_size.y
	var body_capacity: float = maxf(0.0, available_height - fixed_chrome_height)
	var maximum_body_height: float = 120.0 if night_only else 180.0
	var target_body_height: float = minf(maximum_body_height, body_capacity)
	if absf(body_scroll.custom_minimum_size.y - target_body_height) >= 0.5:
		body_scroll.custom_minimum_size.y = target_body_height


func _schedule_panel_size_sync() -> void:
	if _size_sync_queued or not is_inside_tree():
		return
	_size_sync_queued = true
	_sync_panel_size.call_deferred()


func _set_focus_order() -> void:
	if controls == null or cancel_button == null or apply_button == null:
		return
	_focus_order.clear()
	if visual_tabs != null:
		_focus_order.append(visual_tabs)
	var time_controls: Array[Control] = sky_controls.call("focus_controls") if sky_controls != null and sky_controls.visible else controls.call("focus_controls")
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
	if sky_controls != null:
		var checked_sky: Dictionary = sky_controls.call("read_draft")
		if not checked_sky.ok:
			show_apply_error(checked_sky.errors)
			return
		applied_sky_config = checked_sky.config
	var night_result: Dictionary = controls.call("read_night_options")
	if not night_result.get("ok", false):
		error_label.text = tr(INPUT_ERROR)
		error_label.visible = true
		return
	var result: Dictionary = {"ok": true, "config": {}} if night_only else controls.call("read_draft")
	if not result.get("ok", false):
		error_label.text = tr(INPUT_ERROR)
		error_label.visible = true
		return
	var moon_result: Dictionary = controls.call("read_moon_config")
	if not moon_result.get("ok", false):
		error_label.text = tr(INPUT_ERROR)
		error_label.visible = true
		return
	error_label.visible = false
	applied_night_options = night_result.options.duplicate(true)
	applied_moon_config = moon_result.config.duplicate()
	applied.emit(result.config.duplicate(true))


## The flight reports staging/commit errors here; keep the draft and modal intact for correction or Cancel.
func show_apply_error(_errors: Variant) -> void:
	error_label.text = tr(APPLY_ERROR)
	error_label.visible = true


func _on_cancel() -> void:
	cancelled.emit()


static func _label(text: String, variation: String, wrap_text: bool = false) -> Label:
	return Widgets.label(text, variation, wrap_text, false)


## The session's moon choices (app_root sets them from preferences), or the defaults.
static func _session_moon_config() -> Dictionary:
	var checked: Dictionary = MoonConfig.validate(MoonConfig.session_config)
	return checked.config if checked.ok else MoonConfig.defaults()
