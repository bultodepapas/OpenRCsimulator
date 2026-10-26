# UI-24: application settings with reversible display previews. The root applies presentation_changed through
# its shared scale/theme helpers; language is handed to the existing player-preferences owner immediately.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const CameraSettings := preload("res://render/camera/camera_settings.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
## CAM-06b/28 pilot-view aid combinations offered by one picker.
const CAMERA_AIDS: Array[String] = ["off", "horizon", "overhead", "both"]
## Settings pages, in tab order. CAM-17 added Camera.
const CATEGORIES: Array[String] = ["Display", "Interface", "Sound", "Graphics", "Camera", "Lighting"]
const HighGraphics := preload("res://render/high_graphics_profile.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const SceneDetail := preload("res://render/scene_detail.gd")

signal closed
signal presentation_changed(config: Dictionary)
signal presentation_committed
signal presentation_reverted
signal language_changed(language: String)
signal route_requested(route: String, from: Control)
signal sound_preview_requested
signal feedback_requested(cue: StringName)
signal graphics_restart_requested(profile: String)

const DISPLAY_TEST_SECONDS := 15
const LANGUAGE_CODES: Array[String] = ["en", "es"]
const SCALE_CHOICES: Array[int] = [100, 125, 150, 175, 200]

var display_preferences: DisplayPreferences
var window_close_managed := false # AppRoot owns save/recovery decisions before closing this route.
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
var _reconstruction_picker: OptionButton
var _fsr2_sharpness_slider: HSlider
var _fsr2_sharpness_value: Label
var _fsr2_sharpness_dragging := false
var _scene_detail_picker: OptionButton
var _birds_picker: OptionButton
var _lighting_quality_picker: OptionButton
var _lighting_vfx_toggle: CheckButton
var _lighting_flashes_toggle: CheckButton
var _camera_view_picker: OptionButton
var _camera_fov_picker: OptionButton
var _camera_chase_picker: OptionButton
var _camera_sensitivity_picker: OptionButton
var _camera_zoom_picker: OptionButton
var _camera_aids_picker: OptionButton
var _camera_magnifier_picker: OptionButton
var _camera_invert_toggle: CheckButton
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
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not window_close_managed:
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
	for caption: String in CATEGORIES:
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
	for caption: String in CATEGORIES:
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
	for index: int in CATEGORIES.size():
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
	graphics_page.add_theme_constant_override("separation", 10)
	var camera_page := _pages[4]
	var lighting_page := _pages[5]

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
	_reconstruction_picker = _choice_picker("Reconstruction", "reconstruction", DisplayPreferences.RECONSTRUCTION_MODES)
	_add_row(graphics_page, "3D reconstruction", _reconstruction_picker)
	var sharpness_control := _volume_control("Fsr2SharpnessControl", "Fsr2Sharpness", "Fsr2SharpnessValue", _fsr2_sharpness_changed)
	_fsr2_sharpness_slider = sharpness_control.get_node("Fsr2Sharpness")
	_fsr2_sharpness_value = sharpness_control.get_node("Fsr2SharpnessValue")
	_fsr2_sharpness_slider.drag_started.connect(func() -> void: _fsr2_sharpness_dragging = true)
	_fsr2_sharpness_slider.drag_ended.connect(_fsr2_sharpness_drag_ended)
	_add_row(graphics_page, "FSR sharpness", sharpness_control)
	_msaa_picker = _choice_picker("Msaa3D", "msaa_3d", DisplayPreferences.MSAA_3D_VALUES)
	_add_row(graphics_page, "Antialiasing (MSAA)", _msaa_picker)
	_msaa_picker.tooltip_text = tr("Higher antialiasing smooths edges at a higher GPU cost. VSync reduces tearing; a frame limit can save power. Test what feels smooth on your display.")
	# VQ-06b: no display trial; it cannot blank the screen. Trees and props change from the next flight.
	_scene_detail_picker = OptionButton.new()
	_scene_detail_picker.name = "SceneDetail"
	for level: String in DisplayPreferences.SCENE_DETAILS:
		_scene_detail_picker.add_item(_choice_caption("scene_detail", level))
		_scene_detail_picker.set_item_metadata(_scene_detail_picker.item_count - 1, level)
	_scene_detail_picker.item_selected.connect(_scene_detail_selected)
	_add_row(graphics_page, "Scene detail", _scene_detail_picker)
	var detected: Dictionary = SceneDetail.detected()
	_scene_detail_picker.tooltip_text = tr("Trees, props and model detail, from your next flight. Automatic picks a level for your GPU. Extreme draws every nearby field tree in 3D and needs a strong GPU.") \
		+ "\n" + tr("Detected: %s (%s).") % [RenderingServer.get_video_adapter_name(), tr(str(detected.reason))]
	# SC-BIRD (birds-sky-life plan D2): presentation only and live; birds fly away or arrive instead of popping.
	_birds_picker = OptionButton.new()
	_birds_picker.name = "Birds"
	for level: String in DisplayPreferences.BIRD_LEVELS:
		_birds_picker.add_item(_choice_caption("birds", level))
		_birds_picker.set_item_metadata(_birds_picker.item_count - 1, level)
	_birds_picker.item_selected.connect(_birds_selected)
	_add_row(graphics_page, "Birds", _birds_picker)
	_birds_picker.tooltip_text = tr("Vultures and storks in thermals, kites, swallows and evening swifts, by time of day and weather. Changes apply at once: birds fly away or arrive. Normal follows Scene detail; Many keeps full flocks at every level.")
	_graphics_info = _label("", "SecondaryLabel", true)
	_lighting_quality_picker = OptionButton.new()
	_lighting_quality_picker.name = "AircraftLightingQuality"
	for level: String in ["low", "standard", "high"]:
		_lighting_quality_picker.add_item(_choice_caption("aircraft_lighting_quality", level))
		_lighting_quality_picker.set_item_metadata(_lighting_quality_picker.item_count - 1, level)
	_lighting_quality_picker.item_selected.connect(func(index: int) -> void:
		_draft.aircraft_lighting_quality = str(_lighting_quality_picker.get_item_metadata(index))
		_on_presentation_option_changed())
	_add_row(lighting_page, "Aircraft lighting", _lighting_quality_picker)
	_lighting_quality_picker.tooltip_text = tr("Low keeps aircraft LEDs and landing lights. Standard adds nearby spill and fewer show particles. High uses the full bounded show effects.")
	_lighting_vfx_toggle = CheckButton.new()
	_lighting_vfx_toggle.name = "AircraftLightingShowVfx"
	_lighting_vfx_toggle.theme_type_variation = "SettingsToggle"
	_lighting_vfx_toggle.toggled.connect(func(enabled: bool) -> void:
		_draft.aircraft_lighting_show_vfx = enabled
		_on_presentation_option_changed())
	_add_row(lighting_page, "Aircraft show effects", _lighting_vfx_toggle)
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

	# CAM-17: camera preferences; presentation only, applied to a Home flight at once.
	_camera_view_picker = _camera_picker("CameraView", "camera_view", CameraSettings.VIEWS)
	_add_row(camera_page, "First view", _camera_view_picker)
	_camera_view_picker.tooltip_text = tr("The pilot view stays the reference for learning to fly; chase and orbit are aids. Right-drag turns the orbit; the wheel or +/− zooms.")
	_camera_fov_picker = _camera_picker("CameraFov", "camera_fov", CameraSettings.FOVS)
	_add_row(camera_page, "Pilot field of view", _camera_fov_picker)
	_camera_fov_picker.tooltip_text = tr("The pilot view's widest angle; auto zoom narrows it for a distant airplane. About 30° shows the airplane at its real size on a 24–27-inch screen at arm's length.")
	# CAM-06: one picker for auto zoom on/off (Z in flight) and its law.
	_camera_zoom_picker = OptionButton.new()
	_camera_zoom_picker.name = "CameraAutoZoom"
	for value: String in ["off"] + Array(PilotCamera.ZOOM_LAWS):
		_camera_zoom_picker.add_item(_choice_caption("camera_zoom", value))
		_camera_zoom_picker.set_item_metadata(_camera_zoom_picker.item_count - 1, value)
	_camera_zoom_picker.item_selected.connect(func(index: int) -> void:
		var value := str(_camera_zoom_picker.get_item_metadata(index))
		_draft.camera_auto_zoom = value != "off"
		if value != "off":
			_draft.camera_zoom_law = value
		_on_presentation_option_changed())
	_camera_zoom_picker.tooltip_text = tr("Constant size keeps a distant airplane the same size on screen. Keeps looming lets it shrink slowly, so you still see it come and go. Gentle zooms least. Z turns auto zoom off and on in flight.")
	_add_row(camera_page, "Auto zoom (Z)", _camera_zoom_picker)
	# CAM-06b/28: one picker for the two pilot-view aids keeps the page within 1080p without scrolling.
	_camera_aids_picker = OptionButton.new()
	_camera_aids_picker.name = "CameraPilotAids"
	for value: String in CAMERA_AIDS:
		_camera_aids_picker.add_item(_choice_caption("camera_aids", value))
		_camera_aids_picker.set_item_metadata(_camera_aids_picker.item_count - 1, value)
	_camera_aids_picker.item_selected.connect(func(index: int) -> void:
		var value := str(_camera_aids_picker.get_item_metadata(index))
		_draft.camera_horizon_bias = value in ["horizon", "both"]
		_draft.camera_overhead_smoothing = value in ["overhead", "both"]
		_on_presentation_option_changed())
	_camera_aids_picker.tooltip_text = tr("Keep the horizon in view: the view tilts down so the ground shows under a high airplane. Smooth overhead passes: the picture turns gradually instead of flipping when the airplane passes overhead.")
	_add_row(camera_page, "Pilot view aids", _camera_aids_picker)
	_camera_magnifier_picker = _camera_picker("CameraMagnifier", "camera_magnifier", CameraSettings.MAGNIFIER_MODES)
	_camera_magnifier_picker.tooltip_text = tr("Pilot view: a small window at the top shows the airplane up close, so its attitude reads while the main view keeps the real distance. Automatic shows it when the airplane gets small.")
	_add_row(camera_page, "Magnifier", _camera_magnifier_picker)
	_camera_chase_picker = _camera_picker("CameraChaseDistance", "camera_chase_distance", CameraSettings.CHASE_DISTANCES)
	_add_row(camera_page, "Chase distance", _camera_chase_picker)
	_camera_sensitivity_picker = _camera_picker("CameraSensitivity", "camera_sensitivity", CameraSettings.SENSITIVITIES)
	_add_row(camera_page, "Orbit sensitivity", _camera_sensitivity_picker)
	_camera_invert_toggle = _camera_toggle("CameraInvertY", "camera_invert_y", "Invert orbit up/down")
	_add_row(camera_page, "Invert orbit up/down", _camera_invert_toggle)

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
	_lighting_flashes_toggle = CheckButton.new()
	_lighting_flashes_toggle.name = "AircraftLightingReducedFlashes"
	_lighting_flashes_toggle.theme_type_variation = "SettingsToggle"
	_lighting_flashes_toggle.toggled.connect(func(enabled: bool) -> void:
		_draft.aircraft_lighting_reduced_flashes = enabled
		_on_presentation_option_changed())
	_add_row(lighting_page, "Reduce aircraft flashes", _lighting_flashes_toggle)
	_lighting_flashes_toggle.tooltip_text = tr("Keep aircraft lights steady and disable show effects. Saved aircraft colors and sequences are preserved.")
	lighting_page.add_child(_label("These preferences apply to every aircraft and Workshop preview. Customize individual colors and sequences in Workshop.", "SecondaryLabel", true))
	var lighting_defaults := _button("Restore lighting defaults", "QuietButton", "AircraftLightingDefaults")
	lighting_defaults.pressed.connect(func() -> void:
		for key: String in ["aircraft_lighting_quality", "aircraft_lighting_show_vfx", "aircraft_lighting_reduced_flashes"]:
			_draft[key] = DisplayPreferences.DEFAULTS[key]
		_sync_controls()
		_on_presentation_option_changed())
	lighting_page.add_child(lighting_defaults)

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


func _grab_settings_focus(control: Control) -> void:
	# A suspended Settings screen must never reclaim focus from its top-level child screen.
	if not is_inside_tree() or not _surface.is_visible_in_tree() or not is_instance_valid(control):
		return
	if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
		control.grab_focus()


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
	var test_sound_had_focus := is_inside_tree() and get_viewport().gui_get_focus_owner() == _test_sound_button
	_test_sound_button.disabled = float(_draft.menu_volume) <= 0.0
	if test_sound_had_focus and _test_sound_button.disabled:
		_grab_settings_focus(_volume_slider)


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


## CAM-17: a camera option; it changes presentation only, so it applies live without the display trial timer.
func _camera_picker(node_name: String, key: String, values: Array) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name
	for value: Variant in values:
		picker.add_item(_choice_caption(key, value))
		picker.set_item_metadata(picker.item_count - 1, value)
	picker.item_selected.connect(func(index: int) -> void:
		_draft[key] = picker.get_item_metadata(index)
		_on_presentation_option_changed())
	return picker


func _camera_toggle(node_name: String, key: String, tooltip: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = node_name
	toggle.theme_type_variation = "SettingsToggle"
	toggle.tooltip_text = tr(tooltip)
	toggle.toggled.connect(func(enabled: bool) -> void:
		_draft[key] = enabled
		_on_presentation_option_changed())
	return toggle


func _choice_caption(key: String, value: Variant) -> String:
	match key:
		"window_resolution": return tr("Automatic") if value == "auto" else str(value).replace("x", " × ")
		"max_fps": return tr("Unlimited") if value == 0 else "%d FPS" % int(value)
		"vsync_mode": return tr("On") if value == "enabled" else tr("Off")
		"msaa_3d": return tr("Off") if value == 0 else "%d×" % (1 << int(value))
		"reconstruction": return {native = tr("Native"),
			fsr2_native = tr("FSR2 · Native AA"), fsr2_85 = tr("FSR2 · 85%"), fsr2_quality = tr("FSR2 · Quality"),
			fsr2_balanced = tr("FSR2 · Balanced"), fsr2_performance = tr("FSR2 · Performance"),
			fsr3_native = tr("FSR3 · Native AA"), fsr3_85 = tr("FSR3 · 85%"), fsr3_quality = tr("FSR3 · Quality"),
			fsr3_balanced = tr("FSR3 · Balanced"), fsr3_performance = tr("FSR3 · Performance"),
			dlss_native = tr("DLSS · Native AA"), dlss_quality = tr("DLSS · Quality"),
			dlss_balanced = tr("DLSS · Balanced"), dlss_performance = tr("DLSS · Performance")}.get(value, str(value))
		"scene_detail":
			if value == SceneDetail.AUTO:
				return tr("Automatic (%s)") % tr(str(SceneDetail.detected().level).capitalize())
			return tr(str(value).capitalize())
		"birds": return {off = tr("Off"), few = tr("Few"), normal = tr("Normal"), many = tr("Many")}.get(value, str(value))
		"aircraft_lighting_quality": return {low = tr("Low"), standard = tr("Standard"), high = tr("High")}.get(value, str(value))
		"camera_magnifier": return {off = tr("Off"), auto = tr("Automatic"), on = tr("On")}.get(value, str(value))
		"camera_aids": return {off = tr("Off"), horizon = tr("Keep the horizon in view"), overhead = tr("Smooth overhead passes"),
			both = tr("Both")}.get(value, str(value))
		"camera_view": return {pilot = tr("Pilot"), chase = tr("Chase"), flyby = tr("Fly-by"), orbit = tr("Orbit")}.get(value, str(value))
		"camera_zoom": return {off = tr("Off"), constant = tr("%s (default)") % tr("Constant size"), partial = tr("Keeps looming"),
			gentle = tr("Gentle")}.get(value, str(value))
		"camera_fov":
			var degrees := "%d°" % int(value)
			return tr("%s (default)") % degrees if int(value) == int(CameraSettings.DEFAULTS.camera_fov) else degrees
		"camera_chase_distance", "camera_sensitivity":
			var percent := "%d %%" % roundi(float(value) * 100.0)
			return tr("%s (default)") % percent if is_equal_approx(float(value), 1.0) else percent
	return str(value)


func _fsr2_sharpness_changed(value: float) -> void:
	_draft.fsr2_sharpness = value
	_fsr2_sharpness_value.text = tr("Off") if is_zero_approx(value) else "%d %%" % roundi(value * 100.0)
	# Godot 4.7.2 reconfigures render buffers on sharpness changes. Coalesce a
	# pointer drag into one preview on release; keyboard steps still apply at once.
	if _fsr2_sharpness_dragging:
		return
	_on_graphics_option_changed()


func _fsr2_sharpness_drag_ended(changed: bool) -> void:
	_fsr2_sharpness_dragging = false
	if changed:
		_on_graphics_option_changed()


func _on_graphics_option_changed() -> void:
	var changed := false
	for key: String in ["window_mode", "window_resolution", "max_fps", "vsync_mode", "msaa_3d", "reconstruction", "fsr2_sharpness"]:
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
	for key: String in ["max_fps", "vsync_mode", "msaa_3d", "scene_detail", "birds", "reconstruction", "fsr2_sharpness"]:
		_draft[key] = DisplayPreferences.DEFAULTS[key]
	_on_graphics_option_changed()


func _refresh_graphics_info() -> void:
	if not is_inside_tree() or _graphics_info == null:
		return
	# SC-BIRD: one line (the renderer name moved to the tooltip) so the Graphics page, with its Birds row, still fits
	# at 1080p; it ends with the effective VSync state.
	_graphics_info.tooltip_text = tr("The driver or desktop compositor may override VSync.") + "\n" \
		+ tr("Renderer: %s") % RenderingServer.get_current_rendering_method()
	_graphics_info.text = tr("Graphics mode: %s") % (tr("High (experimental)") if HighGraphics.active() else tr("Standard")) \
		+ " · " + tr("Output: %d × %d · VSync: %s") % [get_window().size.x, get_window().size.y,
		tr("On") if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else tr("Off")]
	if HighGraphics.requested() == "high" and not HighGraphics.active():
		_graphics_info.text += "\n" + tr("High is unavailable with the current renderer. Standard remains active.")
	var requested := str(_draft.get("reconstruction", "native"))
	var capabilities := Reconstruction.runtime_capabilities()
	var active_policy: Dictionary = Reconstruction.resolve(requested, capabilities)
	var viewport := get_viewport()
	var receipt := Reconstruction.describe(viewport)
	# The viewport receipt includes runtime rollback, while this settings draft remains the
	# user's requested choice. Use it only when it describes the same preview.
	if str(receipt.get("requested", "")) == requested:
		active_policy = receipt
	var effective := str(active_policy.get("effective", "native"))
	var output_size := viewport.get_visible_rect().size
	var scale := float(active_policy.get("scale", 1.0))
	var input_width := roundi(output_size.x * scale)
	var input_height := roundi(output_size.y * scale)
	_graphics_info.text += "\n" + tr("Reconstruction: Requested %s → Active %s") % [
		_choice_caption("reconstruction", requested), _choice_caption("reconstruction", effective)]
	_graphics_info.text += "\n" + tr("Estimated 3D input: %d × %d → Output: %d × %d") % [
		input_width, input_height, roundi(output_size.x), roundi(output_size.y)]
	if bool(active_policy.get("fallback", false)):
		var reason := str(active_policy.get("fallback_reason", ""))
		_graphics_info.text += "\n" + _reconstruction_fallback_text(requested, reason)


func set_graphics_restart_available(available: bool) -> void:
	_graphics_restart_button.disabled = not available
	# VQ-06b: the experiment note moved here from its own label so Scene detail fits the page at 1080p.
	_graphics_restart_button.tooltip_text = tr("Softer shadows, ambient occlusion and sky reflections. Requires a Forward+ capable GPU.") \
		+ "\n" + tr("High is a temporary experiment. Keep your changes before restarting. A normal launch returns to Standard.") \
		if available else tr("End your flight and return Home to change graphics mode.")


func _scale_selected(index: int) -> void:
	_draft.ui_scale = float(_scale_picker.get_item_metadata(index))
	_on_presentation_option_changed()


func _scene_detail_selected(index: int) -> void:
	_draft.scene_detail = str(_scene_detail_picker.get_item_metadata(index))
	_on_presentation_option_changed()


func _birds_selected(index: int) -> void:
	_draft.birds = str(_birds_picker.get_item_metadata(index))
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
		feedback_requested.emit(&"reject")
		return
	_saved = _draft.duplicate(true)
	_trial_deadline_msec = 0
	_set_status("saved")
	_sync_action_buttons()
	presentation_committed.emit()
	feedback_requested.emit(&"saved")


func _revert() -> void:
	_trial_deadline_msec = 0
	_draft = _saved.duplicate(true)
	_emit_presentation(_saved)
	presentation_reverted.emit()
	_refresh_graphics_info.call_deferred()
	call_deferred("_refresh_shared_theme")
	_sync_controls()
	_set_status("reverted")
	feedback_requested.emit(&"cancel")


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
	_select_metadata(_reconstruction_picker, _draft.get("reconstruction", "native"))
	_sync_reconstruction_controls()
	_select_metadata(_scene_detail_picker, _draft.scene_detail)
	_select_metadata(_birds_picker, _draft.get("birds", DisplayPreferences.DEFAULTS.birds))
	_select_metadata(_lighting_quality_picker, _draft.get("aircraft_lighting_quality", "standard"))
	_lighting_vfx_toggle.set_pressed_no_signal(bool(_draft.get("aircraft_lighting_show_vfx", true)))
	_lighting_flashes_toggle.set_pressed_no_signal(bool(_draft.get("aircraft_lighting_reduced_flashes", false)))
	_select_metadata(_camera_view_picker, _draft.get("camera_view", CameraSettings.DEFAULTS.camera_view))
	_select_metadata(_camera_fov_picker, _draft.get("camera_fov", CameraSettings.DEFAULTS.camera_fov))
	_select_metadata(_camera_chase_picker, _draft.get("camera_chase_distance", CameraSettings.DEFAULTS.camera_chase_distance))
	_select_metadata(_camera_sensitivity_picker, _draft.get("camera_sensitivity", CameraSettings.DEFAULTS.camera_sensitivity))
	_select_metadata(_camera_zoom_picker, str(_draft.get("camera_zoom_law", CameraSettings.DEFAULTS.camera_zoom_law))
		if bool(_draft.get("camera_auto_zoom", CameraSettings.DEFAULTS.camera_auto_zoom)) else "off")
	_select_metadata(_camera_magnifier_picker, str(_draft.get("camera_magnifier", CameraSettings.DEFAULTS.camera_magnifier)))
	var horizon := bool(_draft.get("camera_horizon_bias", CameraSettings.DEFAULTS.camera_horizon_bias))
	var overhead := bool(_draft.get("camera_overhead_smoothing", CameraSettings.DEFAULTS.camera_overhead_smoothing))
	_select_metadata(_camera_aids_picker, "both" if horizon and overhead else ("horizon" if horizon else ("overhead" if overhead else "off")))
	_camera_invert_toggle.set_pressed_no_signal(bool(_draft.get("camera_invert_y", CameraSettings.DEFAULTS.camera_invert_y)))
	_select_metadata(_scale_picker, _draft.ui_scale)
	_opaque_toggle.set_pressed_no_signal(bool(_draft.opaque_panels))
	_motion_toggle.set_pressed_no_signal(bool(_draft.reduced_motion))
	_select_metadata(_language_picker, _language)
	_volume_slider.set_value_no_signal(float(_draft.menu_volume))
	_master_slider.set_value_no_signal(float(_draft.get("master_volume", 1.0)))
	_refresh_volume_text()
	_sync_action_buttons()


func _sync_reconstruction_controls() -> void:
	var capabilities := Reconstruction.runtime_capabilities()
	var high_active := bool(capabilities.high)
	_reconstruction_picker.disabled = not high_active
	_reconstruction_picker.tooltip_text = tr("Choose a reconstruction option available in High graphics. Check distant aircraft detail in motion.") if high_active \
		else tr("Restart in High from Home to use reconstruction.")
	_reconstruction_picker.tooltip_text += "\n" + tr("At 1080p, Quality uses about 1280 × 720 3D input; Performance uses 960 × 540. Quality keeps more input detail than Balanced or Performance. Lower input may soften distant detail; compare while moving.")
	for index: int in _reconstruction_picker.item_count:
		var mode := str(_reconstruction_picker.get_item_metadata(index))
		var status := Reconstruction.option_status(mode, capabilities)
		var is_unavailable := not bool(status.available)
		_reconstruction_picker.set_item_disabled(index, is_unavailable)
		_reconstruction_picker.set_item_text(index, _choice_caption("reconstruction", mode)
			+ (" — " + tr("Unavailable") if is_unavailable else ""))
		_reconstruction_picker.set_item_tooltip(index, _reconstruction_option_tooltip(mode, str(status.reason)))
	var policy := Reconstruction.resolve(str(_draft.get("reconstruction", "native")), capabilities)
	var strength := float(_draft.get("fsr2_sharpness", DisplayPreferences.DEFAULTS.fsr2_sharpness))
	_fsr2_sharpness_slider.set_value_no_signal(strength)
	_fsr2_sharpness_slider.editable = high_active and policy.provider in ["fsr2", "fsr3"]
	_fsr2_sharpness_slider.focus_mode = Control.FOCUS_ALL if _fsr2_sharpness_slider.editable else Control.FOCUS_NONE
	_fsr2_sharpness_value.text = tr("Off") if is_zero_approx(strength) else "%d %%" % roundi(strength * 100.0)
	var requested_mode := str(_draft.get("reconstruction", "native"))
	var requested_provider := str(Reconstruction.MODE_PROVIDERS.get(requested_mode, ""))
	if policy.provider == "dlss":
		_fsr2_sharpness_slider.tooltip_text = tr("DLSS controls its own reconstruction sharpness. This saved FSR value is kept for FSR2 or FSR3.")
	elif requested_provider == "dlss" and policy.fallback:
		_fsr2_sharpness_slider.tooltip_text = tr("FSR sharpness is inactive while Native is active. This saved value stays for FSR2 or FSR3. DLSS controls sharpness when it is active.")
	elif policy.provider in ["fsr2", "fsr3"]:
		_fsr2_sharpness_slider.tooltip_text = tr("0% disables FSR sharpening. Higher values sharpen edges but can exaggerate halos and shimmer.")
	else:
		_fsr2_sharpness_slider.tooltip_text = tr("Native rendering does not use FSR sharpness. This saved value is kept for FSR2 or FSR3.")
	_msaa_picker.disabled = high_active and bool(policy.temporal)
	_msaa_picker.tooltip_text = tr("Temporal reconstruction provides antialiasing. Your MSAA choice returns with Native rendering.") if _msaa_picker.disabled \
		else tr("Higher antialiasing smooths edges at a higher GPU cost. VSync reduces tearing; a frame limit can save power. Test what feels smooth on your display.")


func _reconstruction_option_tooltip(mode: String, reason: String) -> String:
	var provider := str(Reconstruction.MODE_PROVIDERS.get(mode, ""))
	if not reason.is_empty():
		if reason == "high_profile_inactive":
			return tr("Restart in High from Home to use reconstruction.")
		return _reconstruction_unavailable_text(provider, reason)
	if not is_inside_tree():
		return ""
	var output_size := get_viewport().get_visible_rect().size
	var policy := Reconstruction.resolve(mode, Reconstruction.runtime_capabilities())
	var input_width := roundi(output_size.x * float(policy.scale))
	var input_height := roundi(output_size.y * float(policy.scale))
	if provider == "native":
		return tr("Native keeps full-resolution 3D input and uses your MSAA choice.")
	if is_equal_approx(float(policy.scale), 1.0):
		return tr("%s keeps full-resolution 3D input and provides antialiasing. Your MSAA choice returns with Native rendering.") % _choice_caption("reconstruction", mode)
	return tr("%s renders 3D at about %d × %d while output stays %d × %d. Lower input may soften distant detail; compare while moving.") % [
		_choice_caption("reconstruction", mode), input_width, input_height,
		roundi(output_size.x), roundi(output_size.y)]


func _reconstruction_unavailable_text(provider: String, reason: String) -> String:
	if reason == "engine_mode_missing":
		return tr("The current game build does not offer %s reconstruction.") % str({
			"fsr2": "FSR2", "fsr3": "FSR3", "dlss": "DLSS"}.get(provider, "this"))
	match reason:
		"fsr3_support_missing": return tr("FSR3 support is not included in this game build.")
		"fsr3_unavailable": return tr("The current graphics session does not report FSR3 support.")
		"fsr3_runtime_failure": return tr("FSR3 could not continue in this graphics session.")
		"dlss_support_missing": return tr("DLSS support is not included in this game build.")
		"dlss_unavailable": return tr("The current graphics session does not report DLSS support.")
		"dlss_runtime_failure": return tr("DLSS could not continue in this graphics session.")
		"fsr2_unavailable": return tr("The current graphics session does not offer FSR2.")
	match provider:
		"fsr2": return tr("The current graphics session does not offer FSR2.")
		"fsr3": return tr("The current graphics session does not report FSR3 support.")
		"dlss": return tr("The current graphics session does not report DLSS support.")
	return tr("This reconstruction option is unavailable in the current graphics session.")


func _reconstruction_fallback_text(mode: String, reason: String) -> String:
	var provider := str(Reconstruction.MODE_PROVIDERS.get(mode, ""))
	if reason == "high_profile_inactive":
		return tr("High graphics is not active. Native rendering is active; restart in High to use your saved choice.")
	var unavailable := _reconstruction_unavailable_text(provider, reason)
	return tr("%s Native rendering is active, and your saved choice is kept.") % unavailable


func _sync_action_buttons() -> void:
	var dirty := _draft != _saved
	var focus_was_on_action := false
	if is_inside_tree():
		var focused := get_viewport().gui_get_focus_owner()
		focus_was_on_action = focused == _keep_button or focused == _revert_button
	_keep_button.disabled = not dirty
	_revert_button.disabled = not dirty
	if not dirty and focus_was_on_action:
		_grab_settings_focus(_close_button)
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
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_on_category_button := false
	for category_button: Button in _category_buttons:
		if focused == category_button:
			focus_on_category_button = true
			break
	var transfer_category_focus := (compact_height and focus_on_category_button) \
		or (not compact_height and focused == _category_picker)
	var selected_category := clampi(_category_picker.selected, 0, _category_buttons.size() - 1)
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
	_layout_panel.custom_minimum_size = Vector2(minf(800.0, maxf(0.0, available.x)), minf(880.0, maxf(0.0, available.y)))
	_refresh_graphics_info()
	_sync_reconstruction_controls()
	var stack_rows := _should_stack_rows()
	# Two rows of tabs when stacked, as with four categories: a third row would leave the page no room at 200 % text.
	_categories.columns = ceili(CATEGORIES.size() / 2.0) if stack_rows else CATEGORIES.size()
	_categories.visible = not compact_height
	_category_picker.visible = compact_height
	if transfer_category_focus:
		_grab_settings_focus(_category_picker if compact_height else _category_buttons[selected_category])
	_destinations.vertical = stack_rows
	for row: BoxContainer in _rows:
		row.vertical = stack_rows
		row.add_theme_constant_override("separation", 8 if stack_rows else 24)
		var input := row.get_child(1) as Control
		if input is OptionButton or input.name in ["VolumeControl", "MasterVolumeControl", "Fsr2SharpnessControl"]:
			input.custom_minimum_size.x = minf(300.0 * ScreenTheme.text_scale, _layout_panel.custom_minimum_size.x - 64.0)
			input.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if stack_rows else Control.SIZE_SHRINK_END
		else:
			row.vertical = false


func _refresh_shared_theme() -> void:
	if is_instance_valid(_surface):
		_surface.theme = ScreenTheme.build()
		_update_layout()


func _refresh_translated_text() -> void:
	for index: int in CATEGORIES.size():
		_category_picker.set_item_text(index, tr(CATEGORIES[index]))
	for entry: Dictionary in _localized_controls:
		var control: Control = entry.control
		if control is Button or control is Label:
			control.text = tr(str(entry.source))
	if _window_picker != null:
		_window_picker.set_item_text(0, tr("Windowed"))
		_window_picker.set_item_text(1, tr("Borderless fullscreen"))
	for entry: Array in [[_resolution_picker, "window_resolution"], [_fps_picker, "max_fps"], [_vsync_picker, "vsync_mode"], [_msaa_picker, "msaa_3d"], [_reconstruction_picker, "reconstruction"], [_scene_detail_picker, "scene_detail"],
			[_lighting_quality_picker, "aircraft_lighting_quality"],
			[_camera_view_picker, "camera_view"], [_camera_fov_picker, "camera_fov"], [_camera_zoom_picker, "camera_zoom"], [_camera_magnifier_picker, "camera_magnifier"], [_camera_aids_picker, "camera_aids"], [_camera_chase_picker, "camera_chase_distance"], [_camera_sensitivity_picker, "camera_sensitivity"]]:
		var picker: OptionButton = entry[0]
		for index: int in picker.item_count:
			picker.set_item_text(index, _choice_caption(entry[1], picker.get_item_metadata(index)))
	_refresh_graphics_info()
	_sync_reconstruction_controls()
	if _opaque_toggle != null:
		_opaque_toggle.tooltip_text = tr("Use opaque panels")
	if _motion_toggle != null:
		_motion_toggle.tooltip_text = tr("Reduce interface motion")
	if _lighting_quality_picker != null:
		_lighting_quality_picker.tooltip_text = tr("Low keeps aircraft LEDs and landing lights. Standard adds nearby spill and fewer show particles. High uses the full bounded show effects.")
	if _lighting_flashes_toggle != null:
		_lighting_flashes_toggle.tooltip_text = tr("Keep aircraft lights steady and disable show effects. Saved aircraft colors and sequences are preserved.")
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

