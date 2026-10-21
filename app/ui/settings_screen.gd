# UI-24: application settings with reversible display previews. The root applies presentation_changed through
# its shared scale/theme helpers; language is handed to the existing player-preferences owner immediately.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")

signal closed
signal presentation_changed(config: Dictionary)
signal presentation_committed
signal presentation_reverted
signal language_changed(language: String)
signal route_requested(route: String, from: Control)
signal sound_preview_requested
signal graphics_restart_requested(profile: String)

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
var _layout_center: CenterContainer
var _layout_shell: VBoxContainer
var _scroll: ScrollContainer
var _destinations: BoxContainer
var _close_button: Button
var _rows: Array[BoxContainer] = []
var _localized_controls: Array[Dictionary] = []
var _window_picker: OptionButton
var _resolution_picker: OptionButton
var _fps_picker: OptionButton
var _vsync_picker: OptionButton
var _msaa_picker: OptionButton
var _graphics_info: Label
var _graphics_restart_button: Button
var _scale_picker: OptionButton
var _opaque_toggle: CheckButton
var _motion_toggle: CheckButton
var _language_picker: OptionButton
var _category_buttons: Array[Button] = []
var _categories: GridContainer
var _category_picker: OptionButton
var _pages: Array[VBoxContainer] = []
var _volume_slider: HSlider
var _volume_value: Label
var _master_slider: HSlider
var _master_value: Label
var _test_sound_button: Button
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
	# UI-35a (UI-30 AL-4): start on the first category, so a pad or keyboard moves straight into the settings.
	(_category_picker if _category_picker.visible else _category_buttons[0]).grab_focus.call_deferred()


func _build() -> void:
	_surface = Screen.mount(self)
	_surface.theme = ScreenTheme.build()
	_surface.close_requested.connect(close)
	_surface.dismiss_option_popup_first = true
	_surface.dim(0.58)
	_layout_center = _surface.center(24.0)
	_layout_panel = PanelContainer.new()
	_layout_panel.theme_type_variation = "SettingsPanel"
	_layout_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_layout_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_layout_center.add_child(_layout_panel)
	_layout_shell = VBoxContainer.new()
	_layout_shell.add_theme_constant_override("separation", 12)
	_layout_panel.add_child(_layout_shell)
	var heading := HBoxContainer.new()
	var title := _label("Settings", "SettingsTitle")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_close_button = _button("Close", "QuietButton", "Close")
	_close_button.pressed.connect(close)
	heading.add_child(_close_button)
	_layout_shell.add_child(heading)
	var categories := GridContainer.new()
	_categories = categories
	categories.columns = 4
	categories.add_theme_constant_override("h_separation", 8)
	categories.add_theme_constant_override("v_separation", 8)
	var category_group := ButtonGroup.new()
	for caption: String in ["Display", "Interface", "Sound", "Graphics"]:
		var tab := _button(caption, "HomeTab", caption + "Category")
		tab.toggle_mode = true
		tab.button_group = category_group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_show_category.bind(_category_buttons.size()))
		_category_buttons.append(tab)
		categories.add_child(tab)
	_layout_shell.add_child(categories)
	_category_picker = OptionButton.new()
	_category_picker.name = "SettingsCategory"
	for caption: String in ["Display", "Interface", "Sound", "Graphics"]:
		_category_picker.add_item(tr(caption))
	_category_picker.item_selected.connect(_show_category)
	_category_picker.hide()
	_layout_shell.add_child(_category_picker)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.focus_mode = Control.FOCUS_ALL
	_layout_shell.add_child(_scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	_scroll.add_child(page)
	for index: int in 4:
		var category := VBoxContainer.new()
		category.name = "Category%d" % index
		category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category.add_theme_constant_override("separation", 16)
		page.add_child(category)
		_pages.append(category)
	var display_page := _pages[0]
	var interface_page := _pages[1]
	var sound_page := _pages[2]
	var graphics_page := _pages[3]

	_window_picker = OptionButton.new()
	_window_picker.name = "WindowMode"
	_window_picker.add_item(tr("Windowed"))
	_window_picker.set_item_metadata(0, "windowed")
	_window_picker.add_item(tr("Borderless fullscreen"))
	_window_picker.set_item_metadata(1, "borderless")
	_window_picker.item_selected.connect(_window_mode_selected)
	_add_row(display_page, "Window mode", _window_picker)

	_resolution_picker = _choice_picker("WindowResolution", "window_resolution", DisplayPreferences.WINDOW_RESOLUTIONS)
	_add_row(display_page, "Window resolution", _resolution_picker)


	_scale_picker = OptionButton.new()
	_scale_picker.name = "UiScale"
	for percent: int in SCALE_CHOICES:
		_scale_picker.add_item("%d%%" % percent)
		_scale_picker.set_item_metadata(_scale_picker.item_count - 1, float(percent) / 100.0)
	_scale_picker.item_selected.connect(_scale_selected)
	_add_row(display_page, "Text size", _scale_picker)
	display_page.add_child(_label("Display and graphics changes have a 15-second safety timer.", "SecondaryLabel", true))

	display_page.add_child(_label("Window sizes fit the available desktop. Fullscreen uses the desktop resolution.", "SecondaryLabel", true))

	_fps_picker = _choice_picker("MaxFps", "max_fps", DisplayPreferences.MAX_FPS_VALUES)
	_add_row(graphics_page, "Frame rate limit", _fps_picker)
	_vsync_picker = _choice_picker("VSync", "vsync_mode", DisplayPreferences.VSYNC_MODES)
	_add_row(graphics_page, "Vertical synchronization", _vsync_picker)
	_msaa_picker = _choice_picker("Msaa3D", "msaa_3d", DisplayPreferences.MSAA_3D_VALUES)
	_add_row(graphics_page, "Antialiasing (MSAA)", _msaa_picker)
	_msaa_picker.tooltip_text = tr("Higher antialiasing smooths edges at a higher GPU cost. VSync reduces tearing; a frame limit can save power. Test what feels smooth on your display.")
	_graphics_info = _label("", "SecondaryLabel", true)
	graphics_page.add_child(_graphics_info)
	var defaults_button := _button("Restore graphics defaults", "QuietButton", "GraphicsDefaults")
	defaults_button.pressed.connect(_restore_graphics_defaults)
	var graphics_actions := HFlowContainer.new()
	graphics_page.add_child(graphics_actions)
	graphics_actions.add_child(defaults_button)
	_graphics_restart_button = _button("Restart in Standard" if HighGraphics.active() else "Try High (restart)", "QuietButton", "GraphicsRestart")
	_graphics_restart_button.disabled = true
	_graphics_restart_button.pressed.connect(func() -> void:
		_revert()
		graphics_restart_requested.emit("standard" if HighGraphics.active() else "high"))
	graphics_actions.add_child(_graphics_restart_button)
	graphics_page.add_child(_label("High is a temporary experiment. Keep your changes before restarting. A normal launch returns to Standard.", "SecondaryLabel", true))

	_opaque_toggle = CheckButton.new()
	_opaque_toggle.name = "OpaquePanels"
	_opaque_toggle.theme_type_variation = "SettingsToggle"
	_opaque_toggle.tooltip_text = tr("Use opaque panels")
	_opaque_toggle.toggled.connect(_opaque_toggled)
	_add_row(interface_page, "Use opaque panels", _opaque_toggle)

	_motion_toggle = CheckButton.new()
	_motion_toggle.name = "ReducedMotion"
	_motion_toggle.theme_type_variation = "SettingsToggle"
	_motion_toggle.tooltip_text = tr("Reduce interface motion")
	_motion_toggle.toggled.connect(_motion_toggled)
	_add_row(interface_page, "Reduce interface motion", _motion_toggle)

	_language_picker = OptionButton.new()
	_language_picker.name = "Language"
	_language_picker.add_item("English")
	_language_picker.set_item_metadata(0, "en")
	_language_picker.add_item("Español")
	_language_picker.set_item_metadata(1, "es")
	_language_picker.item_selected.connect(_language_selected)
	_add_row(interface_page, "Language", _language_picker)
	interface_page.add_child(_label("Language is saved immediately.", "SecondaryLabel", true))

	var master_control := _volume_control("MasterVolumeControl", "MasterVolume", "MasterVolumeValue", _master_volume_changed)
	_master_slider = master_control.get_child(0) as HSlider
	_master_value = master_control.get_child(1) as Label
	_add_row(sound_page, "Game volume", master_control)
	sound_page.add_child(_label("Everything you hear: aircraft, scenery, weather, crashes and menus.", "SecondaryLabel", true))
	var volume_control := _volume_control("VolumeControl", "MenuVolume", "VolumeValue", _volume_changed)
	_volume_slider = volume_control.get_child(0) as HSlider
	_volume_value = volume_control.get_child(1) as Label
	_add_row(sound_page, "Menu volume", volume_control)
	sound_page.add_child(_label("Subtle cues for focus, selection and navigation.", "SecondaryLabel", true))
	_test_sound_button = _button("Test sound", "QuietButton", "TestSound")
	_test_sound_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_test_sound_button.pressed.connect(func() -> void: sound_preview_requested.emit())
	sound_page.add_child(_test_sound_button)

	_destinations = BoxContainer.new()
	_destinations.add_theme_constant_override("separation", 12)
	var controls_button := _button("Controls", "QuietButton", "Controls")
	controls_button.pressed.connect(func() -> void: _request_route("controls", controls_button))
	_destinations.add_child(controls_button)
	var about_button := _button("Help", "QuietButton", "HelpAbout")
	about_button.pressed.connect(func() -> void: _request_route("about", about_button))
	_destinations.add_child(about_button)
	interface_page.add_child(_destinations)

	_status = Widgets.label("", "SecondaryLabel", true)
	_status.name = "Status"
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_shell.add_child(_status)
	var actions := Widgets.button_row()
	_revert_button = _button("Revert", "", "Revert")
	_revert_button.pressed.connect(_revert)
	actions.add_child(_revert_button)
	_keep_button = _button("Keep changes", "SettingsAction", "Keep")
	_keep_button.pressed.connect(keep_changes)
	actions.add_child(_keep_button)
	_layout_shell.add_child(actions)
	_set_status("instructions")
	_sync_controls()
	_show_category(0)


func _show_category(index: int) -> void:
	_category_picker.select(index)
	for page_index: int in _pages.size():
		_pages[page_index].visible = page_index == index
		_category_buttons[page_index].set_pressed_no_signal(page_index == index)
	_scroll.scroll_vertical = 0


func _volume_control(container_name: String, slider_name: String, value_name: String, on_changed: Callable) -> HBoxContainer:
	var control := HBoxContainer.new()
	control.name = container_name
	control.add_theme_constant_override("separation", 12)
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 48.0
	slider.value_changed.connect(on_changed)
	slider.focus_entered.connect(func() -> void: _reveal_focused_control.call_deferred())
	control.add_child(slider)
	var value := _label("", "SecondaryLabel")
	value.name = value_name
	value.custom_minimum_size.x = 78.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	control.add_child(value)
	return control


func _master_volume_changed(value: float) -> void:
	_draft.master_volume = value
	_refresh_volume_text()
	_emit_presentation()
	_sync_action_buttons()


func _volume_changed(value: float) -> void:
	_draft.menu_volume = value
	_refresh_volume_text()
	_emit_presentation()
	_sync_action_buttons()


func _refresh_volume_text() -> void:
	if _volume_value == null:
		return
	_volume_value.text = _volume_text(float(_draft.menu_volume))
	if _master_value != null:
		_master_value.text = _volume_text(float(_draft.get("master_volume", 1.0)))
	_test_sound_button.disabled = float(_draft.menu_volume) <= 0.0


func _volume_text(level: float) -> String:
	return tr("Muted") if level <= 0.0 else "%d%%" % roundi(level * 100.0)


func _add_row(parent: Control, caption: String, input: Control) -> void:
	var row := BoxContainer.new()
	row.vertical = _should_stack_rows()
	row.add_theme_constant_override("separation", 12 if row.vertical else 20)
	var label := _label(caption, "")
	label.custom_minimum_size.x = 0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	input.custom_minimum_size.x = 0
	input.size_flags_horizontal = Control.SIZE_SHRINK_END
	input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(input)
	input.focus_entered.connect(func() -> void: _reveal_focused_control.call_deferred())
	parent.add_child(row)
	_rows.append(row)


func _reveal_focused_control() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not focused.is_visible_in_tree() or not _scroll.is_ancestor_of(focused):
		return
	var body := _scroll.get_global_rect()
	var control := focused.get_global_rect().grow(6.0)
	# Scroll offsets are integers; ceil preserves fractional-sized controls and their focus outline.
	if control.end.y > body.end.y:
		_scroll.scroll_vertical += ceili(control.end.y - body.end.y)
	elif control.position.y < body.position.y:
		_scroll.scroll_vertical -= ceili(body.position.y - control.position.y)


func _window_mode_selected(index: int) -> void:
	_draft.window_mode = str(_window_picker.get_item_metadata(index))
	_on_graphics_option_changed()


func _choice_picker(node_name: String, key: String, values: Array) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name
	for value: Variant in values:
		picker.add_item(_choice_caption(key, value))
		picker.set_item_metadata(picker.item_count - 1, value)
	picker.item_selected.connect(func(index: int) -> void:
		_draft[key] = picker.get_item_metadata(index)
		_on_graphics_option_changed())
	return picker


func _choice_caption(key: String, value: Variant) -> String:
	match key:
		"window_resolution": return tr("Automatic") if value == "auto" else str(value).replace("x", " × ")
		"max_fps": return tr("Unlimited") if value == 0 else "%d FPS" % int(value)
		"vsync_mode": return tr("On") if value == "enabled" else tr("Off")
		"msaa_3d": return tr("Off") if value == 0 else "%d×" % (1 << int(value))
	return str(value)


func _on_graphics_option_changed() -> void:
	var changed := false
	for key: String in ["window_mode", "window_resolution", "max_fps", "vsync_mode", "msaa_3d"]:
		changed = changed or _draft[key] != _saved[key]
	if not changed:
		_trial_deadline_msec = 0
	elif _trial_deadline_msec == 0:
		_trial_deadline_msec = Time.get_ticks_msec() + DISPLAY_TEST_SECONDS * 1000
		_set_status("trial", DISPLAY_TEST_SECONDS)
	_emit_presentation()
	if not changed:
		# Selecting the saved option is a rollback even if Close sees a clean draft.
		presentation_reverted.emit()
	_sync_controls()
	_refresh_graphics_info.call_deferred()


func _restore_graphics_defaults() -> void:
	for key: String in ["max_fps", "vsync_mode", "msaa_3d"]:
		_draft[key] = DisplayPreferences.DEFAULTS[key]
	_on_graphics_option_changed()


func _refresh_graphics_info() -> void:
	if not is_inside_tree() or _graphics_info == null:
		return
	_graphics_info.tooltip_text = tr("The driver or desktop compositor may override VSync.")
	_graphics_info.text = tr("Output: %d × %d · VSync: %s") % [get_window().size.x, get_window().size.y,
		tr("On") if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else tr("Off")]
	_graphics_info.text += "\n" + tr("Graphics mode: %s") % (tr("High (experimental)") if HighGraphics.active() else tr("Standard"))
	_graphics_info.text += " · " + RenderingServer.get_current_rendering_method()
	if HighGraphics.requested() == "high" and not HighGraphics.active():
		_graphics_info.text += "\n" + tr("High is unavailable with the current renderer. Standard remains active.")


func set_graphics_restart_available(available: bool) -> void:
	_graphics_restart_button.disabled = not available
	_graphics_restart_button.tooltip_text = tr("Softer shadows, ambient occlusion and sky reflections. Requires a Forward+ capable GPU.") if available else tr("End your flight and return Home to change graphics mode.")


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
	presentation_committed.emit()


func _revert() -> void:
	_trial_deadline_msec = 0
	_draft = _saved.duplicate(true)
	_emit_presentation(_saved)
	presentation_reverted.emit()
	_refresh_graphics_info.call_deferred()
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
	_select_metadata(_resolution_picker, _draft.window_resolution)
	_resolution_picker.disabled = _draft.window_mode == "borderless"
	_select_metadata(_fps_picker, _draft.max_fps)
	_select_metadata(_vsync_picker, _draft.vsync_mode)
	_select_metadata(_msaa_picker, _draft.msaa_3d)
	_select_metadata(_scale_picker, _draft.ui_scale)
	_opaque_toggle.set_pressed_no_signal(bool(_draft.opaque_panels))
	_motion_toggle.set_pressed_no_signal(bool(_draft.reduced_motion))
	_select_metadata(_language_picker, _language)
	_volume_slider.set_value_no_signal(float(_draft.menu_volume))
	_master_slider.set_value_no_signal(float(_draft.get("master_volume", 1.0)))
	_refresh_volume_text()
	_sync_action_buttons()


func _sync_action_buttons() -> void:
	var dirty := _draft != _saved
	_keep_button.disabled = not dirty
	_revert_button.disabled = not dirty
	if dirty and _trial_deadline_msec <= 0 and _status_state in ["saved", "reverted", "expired"]:
		_set_status("instructions")
	elif _status_state == "instructions":
		_refresh_status_text() # the instructions say whether there is anything to keep
	if _trial_deadline_msec <= 0 and _status_state == "trial":
		_set_status("instructions")


func _should_stack_rows() -> bool:
	return ScreenTheme.text_scale > 1.25 or (_surface != null and _surface.size.x < 960.0)


func _update_layout() -> void:
	if _surface == null or _layout_panel == null:
		return
	var compact_height := ScreenTheme.text_scale >= 1.75 and _surface.size.y <= 600.0
	var gutter := 16.0 if compact_height else 24.0
	_layout_center.offset_left = gutter
	_layout_center.offset_top = gutter
	_layout_center.offset_right = -gutter
	_layout_center.offset_bottom = -gutter
	_layout_shell.add_theme_constant_override("separation", 4 if compact_height else 12)
	if compact_height:
		var panel_style := _surface.theme.get_stylebox("panel", "SettingsPanel").duplicate() as StyleBoxFlat
		panel_style.content_margin_top = 12
		panel_style.content_margin_bottom = 12
		_layout_panel.add_theme_stylebox_override("panel", panel_style)
	else:
		_layout_panel.remove_theme_stylebox_override("panel")
	var available: Vector2 = _surface.size - Vector2(gutter * 2.0, gutter * 2.0)
	_layout_panel.custom_minimum_size = Vector2(minf(800.0, maxf(0.0, available.x)), minf(720.0, maxf(0.0, available.y)))
	_refresh_graphics_info()
	var stack_rows := _should_stack_rows()
	_categories.columns = 2 if stack_rows else 4
	_categories.visible = not compact_height
	_category_picker.visible = compact_height
	_destinations.vertical = stack_rows
	for row: BoxContainer in _rows:
		row.vertical = stack_rows
		row.add_theme_constant_override("separation", 8 if stack_rows else 24)
		var input := row.get_child(1) as Control
		if input is OptionButton or input.name in ["VolumeControl", "MasterVolumeControl"]:
			input.custom_minimum_size.x = minf(300.0 * ScreenTheme.text_scale, _layout_panel.custom_minimum_size.x - 64.0)
			input.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if stack_rows else Control.SIZE_SHRINK_END
		else:
			row.vertical = false


func _refresh_shared_theme() -> void:
	if is_instance_valid(_surface):
		_surface.theme = ScreenTheme.build()
		_update_layout()


func _refresh_translated_text() -> void:
	var categories := ["Display", "Interface", "Sound", "Graphics"]
	for index: int in categories.size():
		_category_picker.set_item_text(index, tr(categories[index]))
	for entry: Dictionary in _localized_controls:
		var control: Control = entry.control
		if control is Button or control is Label:
			control.text = tr(str(entry.source))
	if _window_picker != null:
		_window_picker.set_item_text(0, tr("Windowed"))
		_window_picker.set_item_text(1, tr("Borderless fullscreen"))
	for entry: Array in [[_resolution_picker, "window_resolution"], [_fps_picker, "max_fps"], [_vsync_picker, "vsync_mode"], [_msaa_picker, "msaa_3d"]]:
		var picker: OptionButton = entry[0]
		for index: int in picker.item_count:
			picker.set_item_text(index, _choice_caption(entry[1], picker.get_item_metadata(index)))
	_refresh_graphics_info()
	if _opaque_toggle != null:
		_opaque_toggle.tooltip_text = tr("Use opaque panels")
	if _motion_toggle != null:
		_motion_toggle.tooltip_text = tr("Reduce interface motion")
	if _status != null:
		_refresh_status_text()
	_refresh_volume_text()


func _label(source: String, variation: String, wrap := false) -> Label:
	var label := Widgets.label(source, variation, wrap, false)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = tr(source)
	_localized_controls.append({"control": label, "source": source})
	return label


func _button(source: String, variation := "", node_name := "") -> Button:
	var button := Widgets.button(tr(source), variation, node_name)
	button.focus_entered.connect(func() -> void: _reveal_focused_control.call_deferred())
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
		"saved": _status.text = tr("Settings saved.")
		"reverted": _status.text = tr("Changes reverted. Saved settings restored.")
		"save_error": _status.text = tr("Could not save settings (error %d).") % int(_status_value)
		# UI-36 (UI-30 SC-1): one transaction, stated plainly; Keep changes is the only commit.
		_: _status.text = tr("Unsaved preview: Keep changes saves it, Close discards it.") if _draft != _saved \
			else tr("Changes preview at once. Keep changes saves them; Close discards them.")


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

