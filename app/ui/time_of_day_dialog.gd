# Pause-only time-of-day editor (TOD-08b). Apply is committed by the flight owner; this dialog never resumes it.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")
const Preferences := preload("res://app_state/preferences.gd")
const SkyControls := preload("res://ui/sky_controls.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

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
var night_only: bool = false
var applied_night_options: Dictionary = Preferences.NIGHT_DEFAULTS.duplicate(true)
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
	if initial_sky != null:
		visual_tabs = TabBar.new()
		visual_tabs.name = "VisualConditionsTabs"
		visual_tabs.add_tab(tr("Time of day"))
		visual_tabs.add_tab(tr("Sky & clouds"))
		visual_tabs.focus_mode = Control.FOCUS_ALL
		column.add_child(visual_tabs)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "TimeOfDayScroll"
	scroll.custom_minimum_size.y = 120.0 if night_only else 180.0
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	controls = TimeOfDayControls.new(initial, initial_night_options) as VBoxContainer
	if night_only:
		controls.call("set_time_editing_visible", false)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.focus_order_changed.connect(_set_focus_order)
	_use_native_option_popups_when_supported()
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
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
			scroll.scroll_vertical = 0
			_set_focus_order())

	error_label = _label("", "SecondaryLabel", true)
	error_label.name = "ApplyError"
	error_label.visible = false
	error_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.62))
	column.add_child(error_label)
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
	if dialog_panel == null or not is_inside_tree():
		return
	var available_height: float = get_viewport().get_visible_rect().size.y - 32.0
	dialog_panel.custom_minimum_size.y = clampf(available_height, 320.0 if night_only else 480.0, 640.0)


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
	error_label.visible = false
	applied_night_options = night_result.options.duplicate(true)
	applied.emit(result.config.duplicate(true))


## The flight reports staging/commit errors here; keep the draft and modal intact for correction or Cancel.
func show_apply_error(_errors: Variant) -> void:
	error_label.text = tr(APPLY_ERROR)
	error_label.visible = true


func _on_cancel() -> void:
	cancelled.emit()


static func _label(text: String, variation: String, wrap_text: bool = false) -> Label:
	return Widgets.label(text, variation, wrap_text, false)
