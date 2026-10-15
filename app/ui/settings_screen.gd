# UI-24: application settings with reversible display previews. The root applies presentation_changed through
# its shared scale/theme helpers; language is handed to the existing player-preferences owner immediately.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")

signal closed
signal presentation_changed(config: Dictionary)
signal language_changed(language: String)
signal route_requested(route: String, from: Control)

const DISPLAY_TEST_SECONDS := 15
const LANGUAGE_CODES: Array[String] = ["en", "es"]
const SCALE_CHOICES: Array[int] = [100, 125, 150, 175, 200]

var display_preferences: DisplayPreferences
var _surface: Control
var _saved: Dictionary
var _draft: Dictionary
var _language := "en"
var _trial_deadline_msec := 0
var _status_state := "instructions"
var _status_value := 0
var _layout_panel: PanelContainer
var _layout_shell: VBoxContainer
var _scroll: ScrollContainer
var _close_button: Button
var _rows: Array[BoxContainer] = []
var _localized_controls: Array[Dictionary] = []
var _window_picker: OptionButton
var _scale_picker: OptionButton
var _opaque_toggle: CheckBox
var _motion_toggle: CheckBox
var _language_picker: OptionButton
var _status: Label
var _keep_button: Button
var _revert_button: Button


func _init(store: DisplayPreferences = null, initial_language: String = "en") -> void:
	name = "Settings"
	process_mode = Node.PROCESS_MODE_ALWAYS # the 15-second display test uses wall time, even over a paused flight
	display_preferences = store if store != null else DisplayPreferences.new()
	_saved = display_preferences.config.duplicate(true)
	_draft = _saved.duplicate(true)
	_language = initial_language if initial_language in LANGUAGE_CODES else "en"
	_build()


func _process(_delta: float) -> void:
	if _trial_deadline_msec <= 0:
		return
	var remaining_msec: int = _trial_deadline_msec - Time.get_ticks_msec()
	if remaining_msec <= 0:
		_revert()
		_set_status("expired")
		return
	var remaining_seconds := int(ceil(float(remaining_msec) / 1000.0))
	_set_status("trial", remaining_seconds)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_translated_text()


func _ready() -> void:
	_surface.resized.connect(_update_layout)
	_update_layout()
	_close_button.grab_focus.call_deferred()


func _build() -> void:
	_surface = Screen.mount(self)
	_surface.theme = ScreenTheme.build()
	_surface.close_requested.connect(close)
	_surface.dismiss_option_popup_first = true
	_surface.dim(0.58)
	var center: CenterContainer = _surface.center(24.0)
	_layout_panel = PanelContainer.new()
	_layout_panel.theme_type_variation = "Sidebar"
	_layout_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_layout_panel)
	_layout_shell = VBoxContainer.new()
	_layout_shell.add_theme_constant_override("separation", 12)
	_layout_panel.add_child(_layout_shell)
	var heading := HBoxContainer.new()
	var title := _label("Settings", "TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_close_button = _button("Close", "", "Close")
	_close_button.pressed.connect(close)
	heading.add_child(_close_button)
	_layout_shell.add_child(heading)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.focus_mode = Control.FOCUS_ALL
	_layout_shell.add_child(_scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	_scroll.add_child(page)
	page.add_child(_label("Display", "CardTitle"))

	_window_picker = OptionButton.new()
	_window_picker.name = "WindowMode"
	_window_picker.add_item(tr("Windowed"))
	_window_picker.set_item_metadata(0, "windowed")
	_window_picker.add_item(tr("Borderless fullscreen"))
	_window_picker.set_item_metadata(1, "borderless")
	_window_picker.item_selected.connect(_window_mode_selected)
	_add_row(page, "Window mode", _window_picker)

	_scale_picker = OptionButton.new()
	_scale_picker.name = "UiScale"
	for percent: int in SCALE_CHOICES:
		_scale_picker.add_item("%d%%" % percent)
		_scale_picker.set_item_metadata(_scale_picker.item_count - 1, float(percent) / 100.0)
	_scale_picker.item_selected.connect(_scale_selected)
	_add_row(page, "Interface scale", _scale_picker)

	_opaque_toggle = CheckBox.new()
	_opaque_toggle.name = "OpaquePanels"
	_opaque_toggle.text = tr("Use opaque panels")
	_opaque_toggle.toggled.connect(_opaque_toggled)
	_add_row(page, "Panel background", _opaque_toggle)

	_motion_toggle = CheckBox.new()
	_motion_toggle.name = "ReducedMotion"
	_motion_toggle.text = tr("Reduce interface motion")
	_motion_toggle.toggled.connect(_motion_toggled)
	_add_row(page, "Accessibility", _motion_toggle)

	page.add_child(_label("Language", "CardTitle"))
	_language_picker = OptionButton.new()
	_language_picker.name = "Language"
	_language_picker.add_item("English")
	_language_picker.set_item_metadata(0, "en")
	_language_picker.add_item("Español")
	_language_picker.set_item_metadata(1, "es")
	_language_picker.item_selected.connect(_language_selected)
	_add_row(page, "Interface language", _language_picker)

	page.add_child(_label("Help", "CardTitle"))
	var destinations := HBoxContainer.new()
	destinations.add_theme_constant_override("separation", 12)
	var controls_button := _button("Controls", "", "Controls")
	controls_button.pressed.connect(func() -> void: _request_route("controls", controls_button))
	destinations.add_child(controls_button)
	var about_button := _button("Help & About", "", "HelpAbout")
	about_button.pressed.connect(func() -> void: _request_route("about", about_button))
	destinations.add_child(about_button)
	page.add_child(destinations)

	_status = Widgets.label("", "SecondaryLabel", true)
	_status.name = "Status"
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_shell.add_child(_status)
	var actions := Widgets.button_row()
	_revert_button = _button("Revert", "", "Revert")
	_revert_button.pressed.connect(_revert)
	actions.add_child(_revert_button)
	_keep_button = _button("Keep changes", "PrimaryButton", "Keep")
	_keep_button.pressed.connect(keep_changes)
	actions.add_child(_keep_button)
	_layout_shell.add_child(actions)
	_set_status("instructions")
	_sync_controls()


func _add_row(parent: Control, caption: String, input: Control) -> void:
	var row := BoxContainer.new()
	row.vertical = _should_stack_rows()
	row.add_theme_constant_override("separation", 12 if row.vertical else 20)
	var label := _label(caption, "SecondaryLabel")
	label.custom_minimum_size.x = 0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	input.custom_minimum_size.x = 0
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	parent.add_child(row)
	_rows.append(row)


func _window_mode_selected(index: int) -> void:
	_draft.window_mode = str(_window_picker.get_item_metadata(index))
	if _draft.window_mode == _saved.window_mode:
		_trial_deadline_msec = 0
	elif _trial_deadline_msec == 0:
		_trial_deadline_msec = Time.get_ticks_msec() + DISPLAY_TEST_SECONDS * 1000
		_set_status("trial", DISPLAY_TEST_SECONDS)
	_emit_presentation()
	_sync_action_buttons()


func _scale_selected(index: int) -> void:
	_draft.ui_scale = float(_scale_picker.get_item_metadata(index))
	_on_presentation_option_changed()


func _opaque_toggled(enabled: bool) -> void:
	_draft.opaque_panels = enabled
	_on_presentation_option_changed()


func _motion_toggled(enabled: bool) -> void:
	_draft.reduced_motion = enabled
	_on_presentation_option_changed()


func _language_selected(index: int) -> void:
	var selected := str(_language_picker.get_item_metadata(index))
	if selected == _language:
		return
	_language = selected
	language_changed.emit(_language)


func _on_presentation_option_changed() -> void:
	_emit_presentation()
	_sync_action_buttons()
	call_deferred("_refresh_shared_theme")


func _emit_presentation(config: Dictionary = {}) -> void:
	presentation_changed.emit((config if not config.is_empty() else _draft).duplicate(true))


func _request_route(route: String, from: Control) -> void:
	route_requested.emit(route, from)


func keep_changes() -> void:
	var err: Error = display_preferences.save(_draft)
	if err != OK:
		_set_status("save_error", err)
		return
	_saved = _draft.duplicate(true)
	_trial_deadline_msec = 0
	_set_status("saved")
	_sync_action_buttons()


func _revert() -> void:
	_trial_deadline_msec = 0
	_draft = _saved.duplicate(true)
	_emit_presentation(_saved)
	call_deferred("_refresh_shared_theme")
	_sync_controls()
	_set_status("reverted")


func close() -> void:
	if _draft != _saved or _trial_deadline_msec > 0:
		_revert()
	closed.emit()
	if is_inside_tree(): # standalone use; ScreenStack owns restoration for managed screens
		_surface.close()


func _sync_controls() -> void:
	_select_metadata(_window_picker, _draft.window_mode)
	_select_metadata(_scale_picker, _draft.ui_scale)
	_opaque_toggle.set_pressed_no_signal(bool(_draft.opaque_panels))
	_motion_toggle.set_pressed_no_signal(bool(_draft.reduced_motion))
	_select_metadata(_language_picker, _language)
	_sync_action_buttons()


func _sync_action_buttons() -> void:
	var dirty := _draft != _saved
	_keep_button.disabled = not dirty
	_revert_button.disabled = not dirty
	if _trial_deadline_msec <= 0 and _status_state == "trial":
		_set_status("instructions")


func _should_stack_rows() -> bool:
	return ScreenTheme.text_scale > 1.25 or (_surface != null and _surface.size.x < 960.0)


func _update_layout() -> void:
	if _surface == null or _layout_panel == null:
		return
	var available: Vector2 = _surface.size - Vector2(48.0, 48.0)
	_layout_panel.custom_minimum_size = Vector2(maxf(0.0, available.x - 80.0), maxf(0.0, available.y - 80.0))
	var stack_rows := _should_stack_rows()
	for row: BoxContainer in _rows:
		row.vertical = stack_rows
		row.add_theme_constant_override("separation", 12 if stack_rows else 20)


func _refresh_shared_theme() -> void:
	if is_instance_valid(_surface):
		_surface.theme = ScreenTheme.build()
		_update_layout()


func _refresh_translated_text() -> void:
	for entry: Dictionary in _localized_controls:
		var control: Control = entry.control
		if control is Button or control is Label:
			control.text = tr(str(entry.source))
	if _window_picker != null:
		_window_picker.set_item_text(0, tr("Windowed"))
		_window_picker.set_item_text(1, tr("Borderless fullscreen"))
	if _opaque_toggle != null:
		_opaque_toggle.text = tr("Use opaque panels")
	if _motion_toggle != null:
		_motion_toggle.text = tr("Reduce interface motion")
	if _status != null:
		_refresh_status_text()


func _label(source: String, variation: String, wrap := false) -> Label:
	var label := Widgets.label(source, variation, wrap, false)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = tr(source)
	_localized_controls.append({"control": label, "source": source})
	return label


func _button(source: String, variation := "", node_name := "") -> Button:
	var button := Widgets.button(tr(source), variation, node_name)
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_localized_controls.append({"control": button, "source": source})
	return button


func _set_status(state: String, value := 0) -> void:
	_status_state = state
	_status_value = value
	_refresh_status_text()


func _refresh_status_text() -> void:
	if _status == null:
		return
	match _status_state:
		"trial": _status.text = tr("Keep the display test within %d seconds.") % int(_status_value)
		"expired": _status.text = tr("Display test expired. Saved settings restored.")
		"saved": _status.text = tr("Display settings saved.")
		"reverted": _status.text = tr("Changes reverted. Saved display settings restored.")
		"save_error": _status.text = tr("Could not save display settings (error %d).") % int(_status_value)
		_: _status.text = tr("Changes apply immediately. Keep saves them; Revert or Back restores saved display settings.")


func _select_metadata(picker: OptionButton, value: Variant) -> void:
	for index: int in picker.item_count:
		if picker.get_item_metadata(index) == value:
			picker.select(index)
			return
	if value is float:
		for index: int in picker.item_count:
			if is_equal_approx(float(picker.get_item_metadata(index)), value):
				picker.select(index)
				return

