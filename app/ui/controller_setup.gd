extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiInput := preload("res://ui/ui_input.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerPrompts := preload("res://ui/controller_prompts.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")
const JetiRadio := preload("res://input/jeti_radio.gd")

signal close_requested
signal profile_saved(profile: Dictionary)
signal draft_changed
signal calibration_requested

const LAYER := 12
const CAPTURE_AXIS_RELEASE_THRESHOLD := 0.35
const PRESETS: Array[String] = ["mode1", "mode2", "trigger_absolute"]
const PROMPT_FAMILIES: Array[String] = ["auto", "xbox", "playstation", "nintendo", "generic"]
const PROMPT_FAMILY_LABELS: Dictionary = {
	"auto": "Auto",
	"xbox": "Xbox",
	"playstation": "PlayStation",
	"nintendo": "Nintendo",
	"generic": "Generic",
}
const PROFILE_KIND_CHOICES: Array[Dictionary] = [
	{"id": 0, "kind": "gamepad", "label": "Gamepad · Mode 2"},
	{"id": 1, "kind": "radio", "label": "Radio transmitter · custom"},
	{"id": 2, "kind": "joystick", "label": "Joystick · custom"},
]
const CHANNELS: Array[String] = ["roll", "pitch", "yaw", "throttle"]
const CHANNEL_LABELS: Dictionary = {"roll": "Roll", "pitch": "Pitch", "yaw": "Yaw", "throttle": "Throttle"}
const AUX_CHANNELS: Array[String] = ["smoke", "flaps", "gear"]
const AUX_CHANNEL_LABELS: Dictionary = {"smoke": "Smoke", "flaps": "Flaps", "gear": "Landing gear"}

var registry: Object
var profile_store: Object
var flight_device_picker: OptionButton
var ui_device_picker: OptionButton
var profile_picker: OptionButton
var profile_name_edit: LineEdit
var glyph_family_picker: OptionButton
var profile_kind_picker: OptionButton
var preset_picker: OptionButton
var preset_help_label: Label
var axis_grid: GridContainer
var aux_grid: VBoxContainer
var aux_help_label: Label
var action_grid: GridContainer
var preview_label: Label
var status_label: Label
var save_button: Button
var calibrate_button: Button
var legacy_import_button: Button
var legacy_picker: OptionButton
var legacy_help_label: Label
var keep_radio_button: Button
var restore_gamepad_button: Button
var joystick_enabled: CheckBox
var save_and_apply: Callable
var glyph_family_help_label: Label
## Optional test seam. When set, previews use these typed inputs instead of native Input polling.
var axis_preview_provider: Callable
var button_preview_provider: Callable

var action_filter: OptionButton
var _settings_panel: PanelContainer
var _settings_panel_style: StyleBoxFlat
var _shell: VBoxContainer
var _section_pages: Dictionary = {}
var _section_buttons: Dictionary = {}
var _section_navigation: HFlowContainer
var _section_body: VBoxContainer
var _selected_section := "devices"
var _device_summary: Label
var _device_details_label: Label
var _empty_device_label: Label
var _settings_title: Label
var _preview_axis_labels: Dictionary = {}
var _preview_grid: GridContainer
var _axis_columns: BoxContainer
var _axis_compact_grid: VBoxContainer
var _axis_channel_labels: Dictionary = {}
var _axis_layout_is_table := false
var _device_roles: GridContainer
var _profile_fields: GridContainer
var _axis_field_grids: Array[GridContainer] = []
var _aux_channel_rows: Array[BoxContainer] = []
var _aux_field_grids: Array[BoxContainer] = []
var _aux_inline_fields: Array[BoxContainer] = []
var _action_binding_cells: Array[HBoxContainer] = []

var _screen: Control
var _profiles: Array[Dictionary] = []
var _legacy_profiles: Array[Dictionary] = []
var _devices: Array[Dictionary] = []
var _draft_profile: Dictionary = {}
var _drafts_by_context: Dictionary = {}
var _draft_context_key := ""
var _calibration_origins: Dictionary = {} # draft context -> connection that supplied its ranges
var _base_actions: Dictionary = {}
var _action_bindings: Dictionary = {}
var action_capabilities: Dictionary = ControllerActions.SUPPORTED_AUX.duplicate()
var _axis_controls: Dictionary = {}
var _aux_controls: Dictionary = {}
var _clear_action_buttons: Dictionary = {}
var _preview_labels: Dictionary = {}
var _preview_bars: Dictionary = {}
var _draft_flight_device_id := -1
var _draft_ui_device_id := -1
var _capturing_action := ""
var _capturing_device_id := -1
var _capture_button: Button
var _capturing_aux_name := ""
var _capturing_aux_position := -1
var _capture_release_tokens: Dictionary = {}
var _preview_clock := 0.0
var _initial_focus_wait_frames := 0
var _profile_kind_label: Label
var _profile_kind_help_label: Label
var _joystick_label: Label
var _preset_label: Label
var _preset_reset_button: Button
var _preset_ids: Array[String] = []
var _clean_radio_actions_button: Button
var _clean_radio_actions_help_label: Label
var _prompt_texture_cache: Dictionary = {}
var _error_field_controls: Array[Control] = []
var _validation_fields: Dictionary = {}
var _validation_label_captions: Dictionary = {}
var _error_field_styles: Dictionary = {}
var _validation_active := false
var _validation_status := ""
var _status_is_error := false
var _rejected_issues: Array = []
var _rejected_message := ""
var _rejected_errors: Array = []


func _init() -> void:
	name = "ControllerSetup"
	layer = LAYER
	_build()


## The owner injects shared objects before adding this CanvasLayer to the tree.
## Controller choices and profile edits stay draft until one Save operation succeeds.
func configure(controller_registry: Object, store: Object, flight_device_id := -1, ui_device_id := -1,
		capabilities: Dictionary = ControllerActions.SUPPORTED_AUX) -> void:
	action_capabilities = capabilities.duplicate()
	registry = controller_registry
	profile_store = store
	_draft_flight_device_id = flight_device_id if flight_device_id >= 0 else _registry_selected("flight")
	_draft_ui_device_id = ui_device_id if ui_device_id >= 0 else _registry_selected("ui")
	_load_profiles()
	_refresh_devices()
	_load_profile_for_device(_draft_flight_device_id)
	_connect_registry()


## Parent-facing surface API used by the screen stack and the active flight owner.
func request_close() -> void:
	if _is_capture_active():
		_cancel_capture()
		return
	_reset_validation()
	close_requested.emit()


func _cancel_edits() -> void:
	if _is_capture_active():
		_capture_done()
	_reset_validation()
	close_requested.emit()


func current_profile() -> Dictionary:
	return _draft_profile.duplicate(true)


## A preflight wizard never saves or changes selection. Keep edits outside its four channels intact.
func apply_calibration_draft(calibration: Dictionary, device_id: int, generation: int, warning: String = "") -> bool:
	if _draft_flight_device_id != device_id or _draft_profile.get("kind", "") != "radio" \
		or not _calibration_connection_matches(device_id, generation):
		_set_status(tr("The radio connection changed. Calibrate again before saving these settings."), true)
		return false
	var calibrated: Dictionary = ControllerProfile.upgrade_legacy(calibration)
	if calibrated.is_empty() or calibrated.get("kind", "") != "radio":
		_set_status(tr("Invalid calibration. The draft is unchanged."), true)
		return false
	for channel: String in CHANNELS:
		var updated_channel: Dictionary = _draft_profile.get(channel, {}).duplicate(true)
		updated_channel.merge(calibrated[channel], true)
		_draft_profile[channel] = updated_channel
	# The wizard retains valid AUX and reports bindings consumed by newly assigned flight axes.
	_draft_profile["aux"] = calibrated.get("aux", {}).duplicate(true)
	_calibration_origins[_draft_context_key] = {"id": device_id, "generation": generation}
	_update_axis_controls()
	_update_aux_controls()
	_update_preview()
	_remember_current_draft()
	draft_changed.emit()
	var message: String = tr("Calibration is in the draft. Save controller settings to apply it; Cancel discards it.")
	if not warning.is_empty():
		message += " " + tr(warning)
	_set_status(message, false)
	_draft_validation_changed()
	return true


func _calibration_connection_matches(device_id: int, generation: int) -> bool:
	return registry != null and generation > 0 \
		and bool(registry.device_for_id(device_id).get("connected", false)) \
		and int(registry.connection_generation(device_id)) == generation


func load_selected_profile(profile_or_id: Variant) -> bool:
	if profile_or_id is Dictionary:
		_switch_draft_profile(profile_or_id, _profile_context_key(profile_or_id))
		return true
	var target_id := str(profile_or_id)
	for candidate in _profiles:
		if str(candidate.get("profile_id", "")) == target_id:
			_switch_draft_profile(candidate, _profile_context_key(candidate))
			return true
	return false


func selected_flight_device_id() -> int:
	return _draft_flight_device_id


func selected_ui_device_id() -> int:
	return _draft_ui_device_id


func _build() -> void:
	_screen = Screen.mount(self, "Screen")
	_screen.kind = Screen.Kind.MODAL
	_screen.dismiss_option_popup_first = true
	_screen.close_requested.connect(request_close)
	_screen.dim(0.56)
	var center: CenterContainer = _screen.center(20.0)
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "ControllerSettingsPanel"
	var panel_style := _screen.get_theme_stylebox("panel", "Sidebar").duplicate() as StyleBoxFlat
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_bottom = 20.0
	_settings_panel_style = panel_style
	_settings_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_settings_panel)
	var shell := VBoxContainer.new()
	_shell = shell
	shell.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(shell)
	var header := HBoxContainer.new()
	header.name = "ControllerSetupHeader"
	var title := _label("Controls", "TitleLabel")
	title.name = "ControllerSettingsTitle"
	_settings_title = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.x = 0.0
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title)
	var close_button := _button("Close", "", "Close")
	close_button.pressed.connect(request_close)
	header.add_child(close_button)
	shell.add_child(header)
	_device_summary = _label("", "SecondaryLabel", true)
	_device_summary.name = "ControllerDeviceSummary"
	_device_summary.max_lines_visible = 1
	_device_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shell.add_child(_device_summary)
	_device_details_label = _label("", "SecondaryLabel", true)
	_device_details_label.name = "ControllerDeviceDetails"
	_device_details_label.visible = false
	_device_details_label.max_lines_visible = 2
	_device_details_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shell.add_child(_device_details_label)
	_section_navigation = HFlowContainer.new()
	_section_navigation.name = "ControllerSections"
	_section_navigation.add_theme_constant_override("separation", 6)
	_section_navigation.add_theme_constant_override("h_separation", 6)
	_section_navigation.add_theme_constant_override("v_separation", 6)
	shell.add_child(_section_navigation)
	shell.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.name = "ControllerSetupScroll"
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	_section_body = VBoxContainer.new()
	_section_body.name = "ControllerSetupPage"
	_section_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_section_body)
	var page := _make_section("devices", "Devices")
	page.add_child(_label("Choose your controllers, then Save.", "SecondaryLabel", true))
	_empty_device_label = _label("No controllers connected. Connect a gamepad or radio by USB or Bluetooth, then select it here. Keyboard and mouse remain available.", "SecondaryLabel", true)
	_empty_device_label.name = "NoControllersConnected"
	page.add_child(_empty_device_label)
	page.add_child(_section_label("DEVICES"))
	var roles := GridContainer.new()
	_device_roles = roles
	roles.columns = 2
	roles.add_theme_constant_override("h_separation", 24)
	roles.add_theme_constant_override("v_separation", 4)
	page.add_child(roles)
	flight_device_picker = _option("Flight controller")
	flight_device_picker.item_selected.connect(_on_flight_device_selected)
	ui_device_picker = _option("Menu controller")
	ui_device_picker.item_selected.connect(_on_ui_device_selected)
	_add_field(roles, "Flight controller", flight_device_picker)
	_add_field(roles, "Menu controller", ui_device_picker)
	page.add_child(_label("Use a gamepad for menus. Keyboard and mouse are always available.", "SecondaryLabel", true))

	var role_actions := HFlowContainer.new()
	role_actions.add_theme_constant_override("separation", 8)
	role_actions.add_theme_constant_override("h_separation", 8)
	role_actions.add_theme_constant_override("v_separation", 8)
	legacy_import_button = _button("Recover legacy profile…")
	legacy_import_button.pressed.connect(_import_legacy_profiles)
	role_actions.add_child(legacy_import_button)
	calibrate_button = _button("Calibrate selected radio")
	calibrate_button.visible = false
	calibrate_button.disabled = true
	calibrate_button.pressed.connect(func() -> void: calibration_requested.emit())
	role_actions.add_child(calibrate_button)
	page.add_child(role_actions)
	legacy_picker = _option("Legacy profile")
	legacy_picker.visible = false
	legacy_picker.item_selected.connect(_on_legacy_selected)
	page.add_child(legacy_picker)
	legacy_help_label = _label("Legacy radio data stays unchanged. Choose how to copy it into a new profile.", "SecondaryLabel", true)
	legacy_help_label.visible = false
	page.add_child(legacy_help_label)
	var recovery_row := HFlowContainer.new()
	recovery_row.add_theme_constant_override("separation", 8)
	recovery_row.add_theme_constant_override("h_separation", 8)
	recovery_row.add_theme_constant_override("v_separation", 8)
	keep_radio_button = _button("Keep as radio profile")
	keep_radio_button.visible = false
	keep_radio_button.pressed.connect(_keep_legacy_radio)
	recovery_row.add_child(keep_radio_button)
	restore_gamepad_button = _button("Restore gamepad Mode 2")
	restore_gamepad_button.visible = false
	restore_gamepad_button.pressed.connect(_restore_legacy_gamepad)
	recovery_row.add_child(restore_gamepad_button)
	page.add_child(recovery_row)

	page = _make_section("profile", "Profile")
	page.add_child(_section_label("PROFILE"))
	var profile_row := GridContainer.new()
	_profile_fields = profile_row
	profile_row.columns = 2
	profile_row.add_theme_constant_override("h_separation", 24)
	profile_row.add_theme_constant_override("v_separation", 4)
	page.add_child(profile_row)
	profile_picker = _option("Saved profile")
	profile_picker.item_selected.connect(_on_profile_selected)
	profile_name_edit = LineEdit.new()
	profile_name_edit.name = "ProfileName"
	profile_name_edit.max_length = 80
	profile_name_edit.placeholder_text = TranslationServer.translate("Profile name")
	profile_name_edit.text_changed.connect(func(_t: String) -> void: _draft_validation_changed())
	_add_field(profile_row, "Saved profile", profile_picker)
	var name_label := _add_field(profile_row, "Name", profile_name_edit)
	_register_validation_field("name", "profile", profile_name_edit, [name_label], "Name")
	glyph_family_picker = _option("Controller prompts")
	glyph_family_picker.item_selected.connect(_on_glyph_family_selected)
	_add_field(profile_row, "Controller prompts", glyph_family_picker)
	profile_kind_picker = _option("Profile type")
	profile_kind_picker.item_selected.connect(_on_profile_kind_selected)
	_profile_kind_label = _add_field(profile_row, "Profile type", profile_kind_picker)
	_register_validation_field("kind", "profile", profile_kind_picker, [_profile_kind_label], "Profile type")
	preset_picker = _option("Gamepad preset")
	preset_picker.item_selected.connect(_on_preset_selected)
	_preset_label = _add_field(profile_row, "Gamepad preset", preset_picker)
	preset_help_label = _label("Mode 2: left X yaw, left Y throttle; right X roll, right Y pitch.", "SecondaryLabel", true)
	page.add_child(preset_help_label)
	_profile_kind_help_label = _label("Choose an unknown controller type explicitly. Gamepad starts in Mode 2; radio uses a custom profile. Calibration never starts automatically.", "SecondaryLabel", true)
	_profile_kind_help_label.visible = false
	page.add_child(_profile_kind_help_label)
	glyph_family_help_label = _label("Prompt symbols only affect presentation; they never change controller bindings.", "SecondaryLabel", true)
	page.add_child(glyph_family_help_label)
	joystick_enabled = CheckBox.new()
	joystick_enabled.text = "Use this custom mapping for flight"
	joystick_enabled.toggled.connect(_on_joystick_enabled)
	_joystick_label = _add_field(profile_row, "Unknown joystick", joystick_enabled)
	_register_validation_field("configured", "profile", joystick_enabled, [_joystick_label], "Unknown joystick")

	var profile_actions := HFlowContainer.new()
	profile_actions.add_theme_constant_override("separation", 8)
	profile_actions.add_theme_constant_override("h_separation", 8)
	profile_actions.add_theme_constant_override("v_separation", 8)
	var reset_button := _button("Restore selected preset")
	_preset_reset_button = reset_button
	reset_button.pressed.connect(_restore_selected_preset)
	profile_actions.add_child(reset_button)
	_register_validation_field("preset", "profile", reset_button, [_preset_label], "Gamepad preset")
	var duplicate_button := _button("Duplicate profile")
	duplicate_button.pressed.connect(_duplicate_profile)
	profile_actions.add_child(duplicate_button)
	_clean_radio_actions_button = _button("Use safe radio actions in draft")
	_clean_radio_actions_button.name = "CleanRadioActionsDraft"
	_clean_radio_actions_button.pressed.connect(_apply_clean_radio_actions_to_draft)
	profile_actions.add_child(_clean_radio_actions_button)
	page.add_child(profile_actions)
	_clean_radio_actions_help_label = _label("Backspace returns to the menu and Escape pauses. This action map changes only this draft until Save.", "SecondaryLabel", true)
	_clean_radio_actions_help_label.visible = false
	page.add_child(_clean_radio_actions_help_label)

	page = _make_section("axes", "Flight axes")
	page.add_child(_section_label("AXIS MAPPING AND RESPONSE"))
	page.add_child(_label("Each channel uses its own scalar axis. Tune its deadzone, expo and inversion, then move the selected flight controller to preview the conditioned value.", "SecondaryLabel", true))
	_axis_columns = BoxContainer.new()
	var axis_columns := _axis_columns
	axis_columns.add_theme_constant_override("separation", 28)
	page.add_child(axis_columns)
	axis_grid = GridContainer.new()
	axis_grid.name = "AxisMapping"
	axis_grid.columns = 5
	axis_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axis_grid.add_theme_constant_override("h_separation", 14)
	axis_grid.add_theme_constant_override("v_separation", 5)
	axis_grid.visible = false
	axis_columns.add_child(axis_grid)
	for heading in ["Channel", "Source axis", "Deadzone", "Expo", "Invert"]:
		axis_grid.add_child(_label(heading, "SectionLabel"))
	_axis_compact_grid = VBoxContainer.new()
	_axis_compact_grid.name = "AxisMappingCompact"
	_axis_compact_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_axis_compact_grid.add_theme_constant_override("separation", 8)
	axis_columns.add_child(_axis_compact_grid)
	for channel in CHANNELS:
		var channel_block := VBoxContainer.new()
		channel_block.name = "AxisChannel_%s" % channel
		channel_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel_block.add_theme_constant_override("separation", 4)
		_axis_compact_grid.add_child(channel_block)
		var compact_label := _label(str(CHANNEL_LABELS[channel]), "SectionLabel", true)
		channel_block.add_child(compact_label)
		var row_label := _label(str(CHANNEL_LABELS[channel]), "SecondaryLabel")
		row_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_label.custom_minimum_size.x = 120.0
		row_label.name = "AxisTableChannel_%s" % channel
		_axis_channel_labels[channel] = row_label
		axis_grid.add_child(row_label)
		var channel_fields := GridContainer.new()
		channel_fields.name = "AxisFields_%s" % channel
		channel_fields.columns = 2
		channel_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel_fields.add_theme_constant_override("h_separation", 12)
		channel_fields.add_theme_constant_override("v_separation", 6)
		channel_block.add_child(channel_fields)
		_axis_field_grids.append(channel_fields)
		var axis_spin := _spin_box(0.0, float(ControllerProfile.AXIS_COUNT - 1), 1.0)
		axis_spin.custom_minimum_size.x = 100.0
		var deadzone_spin := _spin_box(0.0, 0.95, 0.01)
		deadzone_spin.custom_minimum_size.x = 110.0
		var expo_spin := _spin_box(0.0, 1.0, 0.01)
		expo_spin.custom_minimum_size.x = 110.0
		var invert := CheckBox.new()
		invert.text = "Invert"
		_add_control_field(channel_fields, "Source axis", axis_spin)
		_add_control_field(channel_fields, "Deadzone", deadzone_spin)
		_add_control_field(channel_fields, "Expo", expo_spin)
		_add_control_field(channel_fields, "Direction", invert)
		_axis_controls[channel] = {"axis": axis_spin, "deadzone": deadzone_spin, "expo": expo_spin, "invert": invert}
		for key: String in ["axis", "deadzone", "expo", "invert"]:
			_register_validation_field(channel + "." + key, "axes", _axis_controls[channel][key], [row_label, compact_label], str(CHANNEL_LABELS[channel]))
		axis_spin.value_changed.connect(_on_axis_changed.bind(channel, "axis"))
		deadzone_spin.value_changed.connect(_on_axis_changed.bind(channel, "deadzone"))
		expo_spin.value_changed.connect(_on_axis_changed.bind(channel, "expo"))
		invert.toggled.connect(_on_axis_invert.bind(channel))

	page = _make_section("aux", "Extra channels")
	page.add_child(_section_label("AUXILIARY CHANNELS"))
	aux_help_label = _label("Optional Smoke, Flaps and Landing gear inputs can use axes or buttons. Availability depends on the selected aircraft. Axis endpoints need at least 0.5 travel.", "SecondaryLabel", true)
	aux_help_label.name = "AuxiliaryHelp"
	aux_help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(aux_help_label)
	aux_grid = VBoxContainer.new()
	aux_grid.name = "AuxiliaryMappings"
	aux_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aux_grid.add_theme_constant_override("separation", 8)
	page.add_child(aux_grid)
	for aux_name in AUX_CHANNELS:
		var channel_block := VBoxContainer.new()
		channel_block.name = "AuxChannel_%s" % aux_name
		channel_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel_block.add_theme_constant_override("separation", 3)
		aux_grid.add_child(channel_block)
		var channel_row := BoxContainer.new()
		channel_row.name = "AuxMappingRow_%s" % aux_name
		channel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel_row.add_theme_constant_override("separation", 8)
		_aux_channel_rows.append(channel_row)
		channel_block.add_child(channel_row)
		var aux_label := _label(tr(str(AUX_CHANNEL_LABELS[aux_name])), "SecondaryLabel")
		aux_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		aux_label.custom_minimum_size.x = 160.0
		aux_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		channel_row.add_child(aux_label)
		var type_picker := OptionButton.new()
		type_picker.name = "AuxType_%s" % aux_name
		type_picker.custom_minimum_size.x = 224.0
		type_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for mode_data in [["Disabled", 0], ["Axis", 1], ["Button", 2], ["Switch positions", 3]]:
			var type_index := type_picker.item_count
			type_picker.add_item(tr(str(mode_data[0])), int(mode_data[1]))
			type_picker.set_item_id(type_index, int(mode_data[1]))
		channel_row.add_child(type_picker)
		var mapping := VBoxContainer.new()
		mapping.name = "AuxMapping_%s" % aux_name
		mapping.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mapping.add_theme_constant_override("separation", 6)
		var axis_editor := BoxContainer.new()
		axis_editor.name = "AuxAxisEditor_%s" % aux_name
		axis_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_editor.add_theme_constant_override("separation", 6)
		var axis_spin := _spin_box(0.0, float(ControllerProfile.AXIS_COUNT - 1), 1.0)
		axis_spin.name = "AuxAxis_%s" % aux_name
		axis_spin.custom_minimum_size.x = 58.0
		var off_spin := _spin_box(-1.0, 1.0, 0.05)
		off_spin.name = "AuxOff_%s" % aux_name
		off_spin.custom_minimum_size.x = 66.0
		var on_spin := _spin_box(-1.0, 1.0, 0.05)
		on_spin.name = "AuxOn_%s" % aux_name
		on_spin.custom_minimum_size.x = 66.0
		var aux_invert := CheckBox.new()
		aux_invert.name = "AuxInvert_%s" % aux_name
		aux_invert.text = tr("Invert")
		_aux_inline_fields.append(_add_inline_control_field(axis_editor, "Axis", axis_spin))
		_aux_inline_fields.append(_add_inline_control_field(axis_editor, "Off endpoint", off_spin))
		_aux_inline_fields.append(_add_inline_control_field(axis_editor, "On endpoint", on_spin))
		_aux_inline_fields.append(_add_inline_control_field(axis_editor, "Direction", aux_invert))
		mapping.add_child(axis_editor)
		var button_editor := BoxContainer.new()
		button_editor.name = "AuxButtonEditor_%s" % aux_name
		button_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button_editor.add_theme_constant_override("separation", 8)
		var button_spin := _spin_box(0.0, float(SmokeAux.MAX_BUTTONS - 1), 1.0)
		button_spin.name = "AuxButton_%s" % aux_name
		button_spin.custom_minimum_size.x = 70.0
		var button_mode := OptionButton.new()
		button_mode.name = "AuxButtonMode_%s" % aux_name
		button_mode.custom_minimum_size.x = 144.0
		for mode_data in [["Maintained", "level"], ["Toggle per press", "toggle_edge"]]:
			var mode_index := button_mode.item_count
			button_mode.add_item(tr(str(mode_data[0])), mode_index)
			button_mode.set_item_id(mode_index, mode_index)
		_aux_inline_fields.append(_add_inline_control_field(button_editor, "Button", button_spin))
		_aux_inline_fields.append(_add_inline_control_field(button_editor, "Mode", button_mode))
		mapping.add_child(button_editor)
		var switch_editor := VBoxContainer.new()
		switch_editor.name = "AuxSwitchEditor_%s" % aux_name
		switch_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		switch_editor.add_theme_constant_override("separation", 4)
		var switch_settings := BoxContainer.new()
		switch_settings.name = "AuxSwitchSettings_%s" % aux_name
		switch_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		switch_settings.add_theme_constant_override("separation", 8)
		var position_count := OptionButton.new()
		position_count.name = "AuxSwitchPositions_%s" % aux_name
		position_count.custom_minimum_size.x = 118.0
		position_count.add_item(tr("2 positions"), 2)
		position_count.set_item_id(0, 2)
		position_count.add_item(tr("3 positions"), 3)
		position_count.set_item_id(1, 3)
		var switch_label := LineEdit.new()
		switch_label.name = "AuxSwitchLabel_%s" % aux_name
		switch_label.max_length = 24
		switch_label.placeholder_text = tr("Switch name (optional)")
		switch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var switch_invert := CheckBox.new()
		switch_invert.name = "AuxSwitchInvert_%s" % aux_name
		switch_invert.text = tr("Reverse request")
		switch_settings.add_child(position_count)
		switch_settings.add_child(switch_label)
		switch_settings.add_child(switch_invert)
		switch_editor.add_child(switch_settings)
		var switch_positions := VBoxContainer.new()
		switch_positions.name = "AuxSwitchButtons_%s" % aux_name
		switch_positions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		switch_positions.add_theme_constant_override("separation", 2)
		var switch_button_spins: Array[SpinBox] = []
		var switch_capture_buttons: Array[Button] = []
		var switch_position_rows: Array[HBoxContainer] = []
		var position_names: Array[String] = ["Up", "Middle", "Down"]
		for position_index in 3:
			var position_row := HBoxContainer.new()
			position_row.name = "AuxSwitchButtonRow_%s_%d" % [aux_name, position_index]
			position_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var position_label := _label(tr(position_names[position_index]), "SecondaryLabel")
			position_label.name = "AuxSwitchPositionLabel_%s_%d" % [aux_name, position_index]
			position_label.custom_minimum_size.x = 72.0
			var position_spin := _spin_box(0.0, float(SmokeAux.MAX_BUTTONS - 1), 1.0)
			position_spin.name = "AuxSwitchButton_%s_%d" % [aux_name, position_index]
			position_spin.custom_minimum_size.x = 76.0
			var capture_switch_button := _button("Capture", "", "AuxSwitchCapture_%s_%d" % [aux_name, position_index])
			capture_switch_button.pressed.connect(_start_aux_capture.bind(aux_name, position_index, capture_switch_button))
			position_row.add_child(position_label)
			position_row.add_child(position_spin)
			position_row.add_child(capture_switch_button)
			switch_positions.add_child(position_row)
			switch_position_rows.append(position_row)
			switch_button_spins.append(position_spin)
			switch_capture_buttons.append(capture_switch_button)
			position_spin.value_changed.connect(_on_aux_switch_button_changed.bind(aux_name, position_index))
		switch_editor.add_child(switch_positions)
		mapping.add_child(switch_editor)
		_aux_field_grids.append(axis_editor)
		_aux_field_grids.append(button_editor)
		_aux_field_grids.append(switch_settings)
		var aux_preview := _label(tr("Unbound"), "SecondaryLabel", true)
		aux_preview.name = "AuxPreview_%s" % aux_name
		aux_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		aux_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		aux_preview.max_lines_visible = 1
		aux_preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		channel_row.add_child(aux_preview)
		channel_row.add_child(mapping)
		channel_block.add_child(HSeparator.new())
		_aux_controls[aux_name] = {
			"type": type_picker,
			"row": channel_row,
			"mapping": mapping,
			"axis_editor": axis_editor,
			"axis": axis_spin,
			"off": off_spin,
			"on": on_spin,
			"invert": aux_invert,
			"button_editor": button_editor,
			"button": button_spin,
			"button_mode": button_mode,
			"switch_editor": switch_editor,
			"switch_settings": switch_settings,
			"switch_positions": switch_positions,
			"switch_count": position_count,
			"switch_label": switch_label,
			"switch_invert": switch_invert,
			"switch_button_spins": switch_button_spins,
			"switch_capture_buttons": switch_capture_buttons,
			"switch_position_rows": switch_position_rows,
			"preview": aux_preview,
		}
		for key: String in ["type", "axis", "off", "on", "invert", "button", "button_mode", "switch_count", "switch_label", "switch_invert"]:
			_register_validation_field("aux." + aux_name + "." + key, "aux", _aux_controls[aux_name][key], [aux_label], str(AUX_CHANNEL_LABELS[aux_name]))
		for position_index in 3:
			_register_validation_field("aux." + aux_name + ".buttons.%d" % position_index, "aux", switch_button_spins[position_index], [aux_label], str(AUX_CHANNEL_LABELS[aux_name]))
		type_picker.item_selected.connect(_on_aux_type_selected.bind(aux_name))
		axis_spin.value_changed.connect(_on_aux_axis_changed.bind(aux_name))
		off_spin.value_changed.connect(_on_aux_endpoint_changed.bind(aux_name, "off"))
		on_spin.value_changed.connect(_on_aux_endpoint_changed.bind(aux_name, "on"))
		aux_invert.toggled.connect(_on_aux_invert_toggled.bind(aux_name))
		button_spin.value_changed.connect(_on_aux_button_changed.bind(aux_name))
		button_mode.item_selected.connect(_on_aux_button_mode_selected.bind(aux_name))
		position_count.item_selected.connect(_on_aux_switch_count_selected.bind(aux_name))
		switch_label.text_changed.connect(_on_aux_switch_label_changed.bind(aux_name))
		switch_invert.toggled.connect(_on_aux_switch_invert_toggled.bind(aux_name))

	page = _section_pages["axes"]
	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.add_theme_constant_override("separation", 5)
	axis_columns.add_child(preview_column)
	preview_column.add_child(_section_label("LIVE PREVIEW"))
	_preview_grid = GridContainer.new()
	_preview_grid.name = "AxisLivePreview"
	_preview_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_grid.columns = 2
	_preview_grid.add_theme_constant_override("h_separation", 12)
	_preview_grid.add_theme_constant_override("v_separation", 4)
	preview_column.add_child(_preview_grid)
	for channel in CHANNELS:
		var live_row := VBoxContainer.new()
		live_row.custom_minimum_size.y = 40.0
		live_row.add_theme_constant_override("separation", 3)
		_preview_grid.add_child(live_row)
		var current := _label(tr("%s · raw — · conditioned —") % tr(str(CHANNEL_LABELS[channel])), "SecondaryLabel", false)
		current.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		live_row.add_child(current)
		var meter_row := HBoxContainer.new()
		live_row.add_child(meter_row)
		var meter := ProgressBar.new()
		meter.custom_minimum_size = Vector2(120.0, 10.0)
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter.min_value = -1.0
		meter.max_value = 1.0
		meter.show_percentage = false
		var axis_name := _label("Axis —", "SecondaryLabel")
		_preview_axis_labels[channel] = axis_name
		_preview_labels[channel] = current
		_preview_bars[channel] = meter
		meter_row.add_child(meter)
		meter_row.add_child(axis_name)
	preview_label = _label("Select a flight controller to preview mapped channels.", "SecondaryLabel", true)
	page.add_child(preview_label)

	page = _make_section("buttons", "Buttons")
	var filter_row := HBoxContainer.new()
	var filter_label := _label("ACTIONS", "SectionLabel")
	filter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(filter_label)
	filter_row.add_child(_label("Show actions", "SecondaryLabel"))
	action_filter = _option("Show actions")
	action_filter.name = "ActionFilter"
	for category in ["All", "Flight", "Camera", "Auxiliary", "Menu"]:
		action_filter.add_item(category)
	action_filter.item_selected.connect(_on_action_filter_selected)
	filter_row.add_child(action_filter)
	page.add_child(filter_row)
	page.add_child(_label("Bindings are saved by physical control. A different device cannot trigger them.", "SecondaryLabel", true))
	page.add_child(_label("Gamepads: B/Circle controls retractable gear and RB/R1 controls an installed smoke pump automatically. Flap actions depend on the selected aircraft. Existing assignments take priority; remap other joysticks to choose their buttons.", "SecondaryLabel", true))
	action_grid = GridContainer.new()
	action_grid.name = "SemanticActions"
	action_grid.columns = 3
	action_grid.add_theme_constant_override("h_separation", 18)
	action_grid.add_theme_constant_override("v_separation", 5)
	page.add_child(action_grid)
	for heading in ["Action", "Binding", "Change"]:
		action_grid.add_child(_label(heading, "SectionLabel"))
	for definition in ControllerActions.ACTIONS:
		var action_id := str(definition.id)
		var action_label := _label(tr(str(definition.label)), "SecondaryLabel", true)
		action_label.custom_minimum_size.x = 0.0
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_grid.add_child(action_label)
		var binding_cell := HBoxContainer.new()
		binding_cell.name = "BindingCell_%s" % action_id
		binding_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_cell.add_theme_constant_override("separation", 8)
		_action_binding_cells.append(binding_cell)
		var binding_glyph := TextureRect.new()
		binding_glyph.name = "BindingGlyph_%s" % action_id
		binding_glyph.custom_minimum_size = Vector2(28.0, 28.0)
		binding_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		binding_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		binding_glyph.visible = false
		binding_cell.add_child(binding_glyph)
		var binding_label := _label("Unbound", "SecondaryLabel")
		binding_label.name = "Binding_%s" % action_id
		binding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_label.custom_minimum_size.x = 0.0
		binding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		binding_cell.add_child(binding_label)
		var clear_button := _button("Clear")
		clear_button.name = "Clear_%s" % action_id
		clear_button.pressed.connect(_clear_action_binding.bind(action_id))
		binding_cell.add_child(clear_button)
		_clear_action_buttons[action_id] = clear_button
		action_grid.add_child(binding_cell)
		var change_button := _button("Remap")
		change_button.name = "Remap_%s" % action_id
		change_button.pressed.connect(_start_capture.bind(action_id, change_button))
		action_grid.add_child(change_button)
		_register_validation_field("actions." + action_id, "buttons", change_button, [action_label], str(definition.label))

	shell.add_child(HSeparator.new())
	status_label = _label("", "SecondaryLabel", true)
	status_label.name = "Status"
	status_label.visible = false
	status_label.max_lines_visible = 3
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shell.add_child(status_label)
	var footer := HBoxContainer.new()
	footer.name = "ControllerSetupFooter"
	footer.add_theme_constant_override("separation", 8)
	footer.alignment = BoxContainer.ALIGNMENT_END
	var cancel_button := _button("Cancel", "", "Cancel")
	cancel_button.pressed.connect(_cancel_edits)
	footer.add_child(cancel_button)
	save_button = _button("Save", "PrimaryButton", "SaveProfile")
	save_button.pressed.connect(_save_profile)
	footer.add_child(save_button)
	shell.add_child(footer)
	select_section("devices")
	_screen.resized.connect(_resize_panel)
	_screen.theme_changed.connect(_resize_panel)
	_resize_panel()


func _resize_panel() -> void:
	if not is_instance_valid(_settings_panel) or not is_instance_valid(_screen):
		return
	_settings_panel.custom_minimum_size = Vector2(minf(1160.0, maxf(0.0, _screen.size.x - 40.0)), minf(780.0, maxf(0.0, _screen.size.y - 40.0)))
	var scale := maxf(0.5, ScreenTheme.text_scale)
	var effective_width := _screen.size.x / scale
	var compact_height := _screen.size.y < 760.0
	_shell.add_theme_constant_override("separation", 6 if compact_height else 12)
	_settings_panel_style.content_margin_left = 16.0 if _screen.size.x < 1100.0 else 24.0
	_settings_panel_style.content_margin_right = _settings_panel_style.content_margin_left
	_settings_panel_style.content_margin_top = 12.0 if compact_height else 20.0
	_settings_panel_style.content_margin_bottom = _settings_panel_style.content_margin_top
	status_label.max_lines_visible = 2 if compact_height else 3
	_settings_title.tooltip_text = _settings_title.text
	var navigation_in_scroll := compact_height
	if navigation_in_scroll and _section_navigation.get_parent() != _section_body:
		if _section_navigation.get_parent() != null:
			_section_navigation.get_parent().remove_child(_section_navigation)
		_section_body.add_child(_section_navigation)
		_section_body.move_child(_section_navigation, 0)
		(_section_body.get_parent() as ScrollContainer).scroll_vertical = 0
	elif not navigation_in_scroll and _section_navigation.get_parent() != _shell:
		if _section_navigation.get_parent() != null:
			_section_navigation.get_parent().remove_child(_section_navigation)
		_shell.add_child(_section_navigation)
		_shell.move_child(_section_navigation, 2)
		(_section_body.get_parent() as ScrollContainer).scroll_vertical = 0
	var compact_fields := effective_width < 1280.0
	_device_roles.columns = 1 if compact_fields else 2
	_profile_fields.columns = 1 if compact_fields else 2
	aux_grid.add_theme_constant_override("separation", 2 if effective_width >= 1100.0 else 8)
	(_section_pages["aux"] as VBoxContainer).add_theme_constant_override("separation", 4 if effective_width >= 1100.0 else 10)
	if effective_width >= 1100.0:
		aux_help_label.max_lines_visible = 1
		aux_help_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		aux_help_label.tooltip_text = aux_help_label.text
	else:
		aux_help_label.max_lines_visible = 0
		aux_help_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		aux_help_label.tooltip_text = ""
	var use_axis_table := effective_width >= 1100.0
	_axis_columns.vertical = not use_axis_table
	_set_axis_grid_layout(use_axis_table)
	var axis_columns_count := 1 if effective_width < 700.0 else 2
	for fields in _axis_field_grids:
		fields.columns = axis_columns_count
	for fields in _aux_field_grids:
		fields.vertical = effective_width < 1100.0
	for field in _aux_inline_fields:
		field.vertical = effective_width >= 1100.0
	for row in _aux_channel_rows:
		row.vertical = effective_width < 820.0
		(row.get_parent() as VBoxContainer).add_theme_constant_override("separation", 1 if effective_width >= 1100.0 else 3)
	_preview_grid.columns = 1 if effective_width < 1100.0 else 2


func _set_axis_grid_layout(use_table: bool) -> void:
	if use_table == _axis_layout_is_table:
		return
	_axis_layout_is_table = use_table
	axis_grid.visible = use_table
	_axis_compact_grid.visible = not use_table
	var control_keys: Array[String] = ["axis", "deadzone", "expo", "invert"]
	for channel_index in CHANNELS.size():
		var channel: String = CHANNELS[channel_index]
		var controls: Dictionary = _axis_controls[channel]
		var fields: GridContainer = _axis_field_grids[channel_index]
		var row_label: Label = _axis_channel_labels[channel]
		var table_row_start := axis_grid.columns + channel_index * axis_grid.columns
		if use_table:
			if row_label.get_parent() != axis_grid:
				axis_grid.add_child(row_label)
			axis_grid.move_child(row_label, table_row_start)
			for field_index in control_keys.size():
				var key: String = control_keys[field_index]
				var control: Control = controls[key]
				if control.get_parent() != null:
					control.get_parent().remove_child(control)
				axis_grid.add_child(control)
				axis_grid.move_child(control, table_row_start + field_index + 1)
			controls.invert.text = ""
		else:
			for field_index in control_keys.size():
				var key := control_keys[field_index]
				var control: Control = controls[key]
				if control.get_parent() != null:
					control.get_parent().remove_child(control)
				var field: VBoxContainer = fields.get_child(field_index)
				field.add_child(control)
			controls.invert.text = tr("Invert")


func _make_section(section_id: String, caption: String) -> VBoxContainer:
	var button := _button(caption, "", "Section_%s" % section_id)
	button.toggle_mode = true
	var active_style := _screen.get_theme_stylebox("normal", "Button").duplicate() as StyleBoxFlat
	active_style.border_width_bottom = 3
	active_style.border_color = Color("f5c65d")
	button.add_theme_stylebox_override("pressed", active_style)
	button.add_theme_stylebox_override("hover_pressed", active_style)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(select_section.bind(section_id))
	_section_navigation.add_child(button)
	_section_buttons[section_id] = button
	var page := VBoxContainer.new()
	page.name = "SectionPage_%s" % section_id
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	_section_body.add_child(page)
	_section_pages[section_id] = page
	return page


## Switching sections changes presentation only; all fields share the same draft.
func select_section(section_id: String, focus_content := false) -> void:
	if not _section_pages.has(section_id):
		return
	if section_id != _selected_section and _is_capture_active():
		_cancel_capture()
	_selected_section = section_id
	for key in _section_pages:
		_section_pages[key].visible = key == section_id
		_section_buttons[key].set_pressed_no_signal(key == section_id)
	var scroll := _section_body.get_parent() as ScrollContainer
	scroll.scroll_vertical = 0
	if not is_inside_tree():
		return
	var target: Control = _section_buttons[section_id]
	if focus_content:
		match section_id:
			"devices": target = flight_device_picker
			"profile": target = profile_picker
			"axes": target = _axis_controls.roll.axis.get_line_edit()
			"aux": target = _aux_controls.smoke.type
			"buttons": target = action_filter
	target.grab_focus()


func _on_action_filter_selected(_index: int) -> void:
	if not _capturing_action.is_empty():
		_cancel_capture()
	_update_action_controls()
	(_section_body.get_parent() as ScrollContainer).scroll_vertical = 0
	_refresh_validation_feedback()


func _action_category(definition: Dictionary) -> int:
	var action_id := str(definition.id)
	if action_id.begins_with("camera_") or action_id == "view_reset":
		return 2
	if action_id in ["smoke_toggle", "flaps_up", "flaps_down", "flaps_cycle", "gear_toggle"]:
		return 3
	if str(definition.context) in ["menu", "both"]:
		return 4
	return 1


func _update_device_summary() -> void:
	if _device_summary == null:
		return
	var flight := flight_device_picker.get_item_text(flight_device_picker.selected) if flight_device_picker.selected >= 0 else tr("Keyboard")
	var menu := ui_device_picker.get_item_text(ui_device_picker.selected) if ui_device_picker.selected >= 0 else tr("Keyboard + mouse")
	_device_summary.text = tr("Flight: %s   ·   Menus: %s") % [flight, menu]
	var selected_device := _device_for_id(_draft_flight_device_id)
	var details := _device_details_text(selected_device) if _is_jeti_device(selected_device) else ""
	_device_details_label.visible = not details.is_empty()
	_device_details_label.text = details
	var metadata := _device_metadata_tooltip(selected_device) if not details.is_empty() else ""
	_device_details_label.tooltip_text = metadata
	_device_summary.tooltip_text = _device_summary.text if metadata.is_empty() else "%s\n%s" % [_device_summary.text, metadata]
	_empty_device_label.visible = not _devices.any(func(device: Dictionary) -> bool: return bool(device.get("connected", true)))


static func _is_jeti_device(device: Dictionary) -> bool:
	return not device.is_empty() and JetiRadio.matches(device)


func _device_details_text(device: Dictionary) -> String:
	if not _is_jeti_device(device):
		return ""
	var raw_name := str(device.get("raw_name", device.get("name", JetiRadio.display_name(device))))
	return "%s · %s" % [tr("JETI radio family"), tr("Device name: %s") % raw_name]


func _device_metadata_tooltip(device: Dictionary) -> String:
	if not _is_jeti_device(device):
		return ""
	var raw_name := str(device.get("raw_name", device.get("name", JetiRadio.display_name(device))))
	var parts: Array[String] = [tr("JETI radio family"), tr("Device name: %s") % raw_name]
	var manufacturer := str(device.get("manufacturer", ""))
	var product := str(device.get("product", ""))
	if not manufacturer.is_empty():
		parts.append(tr("Manufacturer: %s") % manufacturer)
	if not product.is_empty():
		parts.append(tr("Product: %s") % product)
	return " · ".join(parts)


func _ready() -> void:
	if registry == null:
		_set_status(tr("Controller services are not available."), true)
		return
	if profile_store == null:
		_set_status(tr("Controller profile storage is not available."), true)
		return
	if _draft_profile.is_empty():
		_load_profile_for_device(_draft_flight_device_id)
	_update_profile_options()
	_update_axis_controls()
	_update_aux_controls()
	_update_action_controls()
	_update_preview()
	_initial_focus_wait_frames = 2


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return
	_refresh_devices()
	_update_profile_options()
	_update_glyph_family_picker()
	_update_profile_kind_picker()
	_update_preset_options()
	_update_aux_controls()
	_update_action_controls()
	profile_name_edit.placeholder_text = TranslationServer.translate("Profile name")
	_refresh_validation_feedback()


func close_button_focus() -> void:
	select_section("devices")
	# Wait for measured controls before follow_focus scrolls the selected field.
	var scroll := _screen.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0
	var focus_target := flight_device_picker if flight_device_picker != null else save_button
	if focus_target != null:
		focus_target.grab_focus()
	if scroll != null:
		scroll.scroll_vertical = 0


func _process(delta: float) -> void:
	if _initial_focus_wait_frames > 0:
		_initial_focus_wait_frames -= 1
		if _initial_focus_wait_frames == 0:
			close_button_focus()
	_preview_clock += delta
	if _preview_clock >= 0.08:
		_preview_clock = 0.0
		_update_preview()


func _input(event: InputEvent) -> void:
	if _consume_capture_release(event):
		get_viewport().set_input_as_handled()
		return
	if not _is_capture_active():
		return
	if not _capturing_aux_name.is_empty():
		if event is InputEventKey:
			var aux_key := event as InputEventKey
			if aux_key.pressed and not aux_key.echo and (aux_key.physical_keycode == KEY_ESCAPE or aux_key.keycode == KEY_ESCAPE):
				get_viewport().set_input_as_handled()
				_track_capture_release(aux_key)
				_cancel_capture()
			return
		if event is InputEventJoypadButton:
			var aux_button_event := event as InputEventJoypadButton
			if aux_button_event.device != _capturing_device_id:
				return
			get_viewport().set_input_as_handled()
			if aux_button_event.pressed:
				_track_capture_release(aux_button_event)
				_capture_aux_button(int(aux_button_event.button_index))
		return
		# Maintained switch capture is button-only; ignore its analog axes.
	if event is InputEventKey:
		var key_event := event as InputEventKey
		get_viewport().set_input_as_handled()
		if not key_event.pressed or key_event.echo:
			return
		_track_capture_release(key_event)
		if key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE:
			_cancel_capture()
			return
		_capture_binding(key_event)
		return
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		if button_event.device != _capturing_device_id:
			return
		get_viewport().set_input_as_handled()
		if not button_event.pressed:
			return
		_track_capture_release(button_event)
		_capture_binding(button_event)
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.device != _capturing_device_id:
			return
		get_viewport().set_input_as_handled()
		if not is_finite(motion.axis_value) or absf(motion.axis_value) < 0.65:
			return
		_track_capture_release(motion)
		_capture_binding(motion)


func _event_release_token(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return "keyboard:%d:%s" % [key_event.device, ControllerActions.event_source(key_event)]
	return ControllerActions.event_source(event)


func _track_capture_release(event: InputEvent) -> void:
	var token := _event_release_token(event)
	if not token.is_empty() and (not event is InputEventJoypadMotion or absf((event as InputEventJoypadMotion).axis_value) >= 0.65):
		_capture_release_tokens[token] = true


func _consume_capture_release(event: InputEvent) -> bool:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return false
	var token := _event_release_token(event)
	if token.is_empty() or not _capture_release_tokens.has(token):
		return false
	if event is InputEventKey and not (event as InputEventKey).pressed:
		_capture_release_tokens.erase(token)
	elif event is InputEventJoypadButton and not (event as InputEventJoypadButton).pressed:
		_capture_release_tokens.erase(token)
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) <= CAPTURE_AXIS_RELEASE_THRESHOLD:
			_capture_release_tokens.erase(token)
	return true


func _connect_registry() -> void:
	if registry != null and registry.has_signal("devices_changed"):
		var callback := Callable(self, "_on_registry_devices_changed")
		if not registry.is_connected("devices_changed", callback):
			registry.connect("devices_changed", callback)


func _on_registry_devices_changed() -> void:
	_refresh_devices()
	draft_changed.emit()
	_update_preset_options()
	if _is_capture_active():
		var captured_device := _device_for_id(_capturing_device_id)
		if captured_device.is_empty() or not bool(captured_device.get("connected", true)):
			_capture_done()
			_set_status(tr("The selected flight controller disconnected; remapping was cancelled."), true)
	_update_action_controls()
	_update_preview()


func _load_profiles() -> void:
	_profiles.clear()
	if profile_store == null:
		return
	var result: Dictionary = profile_store.call("load_all")
	for profile in result.get("profiles", []):
		if profile is Dictionary:
			_profiles.append(profile.duplicate(true))
	if not bool(result.get("ok", false)):
		var errors: Array = result.get("errors", [])
		_set_status(tr("Could not load controller profiles: %s") % "; ".join(errors), true)
	elif not result.get("errors", []).is_empty():
		_set_status(tr("Controller profiles recovered: %s") % "; ".join(result.errors), false)


func _refresh_devices() -> void:
	_devices.clear()
	if registry != null:
		var found: Variant = registry.call("get_devices")
		if found is Array:
			for device in found:
				if device is Dictionary:
					_devices.append(device.duplicate(true))
	_fill_device_picker(flight_device_picker, false, _draft_flight_device_id)
	_fill_device_picker(ui_device_picker, true, _draft_ui_device_id)
	_update_device_summary()


func _fill_device_picker(picker: OptionButton, menu_only: bool, target_id: int) -> void:
	if picker == null:
		return
	picker.clear()
	picker.add_item(tr("Keyboard + mouse") if menu_only else tr("Keyboard"), -1)
	picker.set_item_id(0, -1)
	var found_selection := target_id == -1
	if found_selection:
		picker.select(0)
	for device in _devices:
		var id := int(device.get("id", -1))
		var kind := str(device.get("kind", "joystick"))
		if id < 0 or (menu_only and kind == "radio"):
			continue
		var name := str(device.get("name", device.get("raw_name", tr("Controller %d") % id)))
		if _is_jeti_device(device):
			name = JetiRadio.display_name(device)
		if not bool(device.get("connected", true)):
			name += " · " + tr("disconnected")
		var label := "%s · %s" % [name, tr(kind.capitalize())]
		picker.add_item(label, id)
		var item_index := picker.item_count - 1
		var detail_text := _device_details_text(device)
		picker.get_popup().set_item_tooltip(item_index, label if detail_text.is_empty() else "%s\n%s" % [label, detail_text])
		if menu_only and not _is_menu_device_eligible(device):
			picker.set_item_disabled(item_index, true)
		if id == target_id:
			picker.select(item_index)
			found_selection = true
	if not found_selection and target_id >= 0:
		picker.add_item(tr("Disconnected controller %d") % target_id, target_id)
		picker.set_item_disabled(picker.item_count - 1, true)
		picker.select(picker.item_count - 1)
	if picker.selected >= 0:
		picker.tooltip_text = picker.get_item_text(picker.selected)
		var selected_device := _device_for_id(picker.get_item_id(picker.selected))
		var selected_details := _device_metadata_tooltip(selected_device)
		if not selected_details.is_empty():
			picker.tooltip_text = "%s\n%s" % [picker.tooltip_text, selected_details]


func _on_flight_device_selected(index: int) -> void:
	var selected_id := flight_device_picker.get_item_id(index)
	var capture_cancelled := selected_id != _draft_flight_device_id and _is_capture_active()
	if capture_cancelled:
		_capture_done()
	_draft_flight_device_id = selected_id
	_update_device_summary()
	_load_profile_for_device(_draft_flight_device_id)
	_set_status(tr("The flight controller changed; remapping was cancelled.") if capture_cancelled else "", false)
	_update_profile_options()
	_update_axis_controls()
	_update_aux_controls()
	_update_action_controls()
	_update_preview()


func _on_ui_device_selected(index: int) -> void:
	_draft_ui_device_id = ui_device_picker.get_item_id(index)
	_update_device_summary()
	_set_status("", false)


func _is_menu_device_eligible(device: Dictionary) -> bool:
	if device.is_empty() or not bool(device.get("connected", true)):
		return false
	if bool(device.get("ambiguous", false)) or str(device.get("kind", "")) == "radio":
		return false
	if str(device.get("kind", "")) == "gamepad" and bool(device.get("known", false)):
		return true
	return _has_saved_gamepad_profile(device)


func _has_saved_gamepad_profile(device: Dictionary) -> bool:
	if profile_store == null or not profile_store.has_method("match_profile"):
		return false
	var matched: Variant = profile_store.call("match_profile", device, _devices)
	if not matched is Dictionary or matched.is_empty():
		return false
	if str(matched.get("kind", "")) != "gamepad" or not bool(matched.get("configured", true)):
		return false
	return bool(ControllerProfile.validate(matched).get("ok", false))


func _load_profile_for_device(device_id: int) -> void:
	var device := _device_for_id(device_id)
	var profile_id := str(device.get("profile_id", ""))
	if profile_id.is_empty() and not device.is_empty() and profile_store != null and profile_store.has_method("match_profile"):
		var suggestion: Dictionary = profile_store.call("match_profile", device, _devices)
		profile_id = str(suggestion.get("profile_id", ""))
	if not profile_id.is_empty():
		for candidate in _profiles:
			if str(candidate.get("profile_id", "")) == profile_id:
				_switch_draft_profile(candidate, _profile_context_key(candidate))
				return
	var expected_kind := str(device.get("kind", "gamepad"))
	var preset := "mode2" if expected_kind == "gamepad" else ("jeti_mode2" if _is_jeti_device(device) else "radio_custom")
	var candidate_profile := ControllerProfile.defaults(expected_kind, preset)
	if candidate_profile.is_empty():
		candidate_profile = ControllerProfile.defaults("gamepad", "mode2")
	if expected_kind == "joystick":
		candidate_profile["configured"] = false
	_switch_draft_profile(candidate_profile, "device:%d" % device_id)


func _profile_context_key(profile: Dictionary) -> String:
	var profile_id := str(profile.get("profile_id", ""))
	return "profile:%s" % profile_id if not profile_id.is_empty() else ""


func _remember_current_draft() -> void:
	if _draft_profile.is_empty() or _draft_context_key.is_empty():
		return
	var snapshot := _draft_profile.duplicate(true)
	if profile_name_edit != null:
		snapshot["name"] = profile_name_edit.text
	_drafts_by_context[_draft_context_key] = snapshot


func _switch_draft_profile(profile: Dictionary, context_key: String) -> void:
	_remember_current_draft()
	var target: Dictionary = _drafts_by_context.get(context_key, profile)
	_set_draft_profile(target, context_key)


func _set_draft_profile(profile: Dictionary, context_key := "") -> void:
	_reset_validation()
	var previous_profile_id := str(_draft_profile.get("profile_id", ""))
	_draft_profile = profile.duplicate(true)
	if not context_key.is_empty():
		_draft_context_key = context_key
	elif _draft_context_key.is_empty() or previous_profile_id != str(_draft_profile.get("profile_id", "")):
		_draft_context_key = _profile_context_key(_draft_profile)
	profile_name_edit.text = str(_draft_profile.get("name", "Controller profile"))
	var profile_kind := str(_draft_profile.get("kind", "gamepad"))
	joystick_enabled.visible = profile_kind == "joystick"
	_joystick_label.visible = joystick_enabled.visible
	joystick_enabled.set_pressed_no_signal(bool(_draft_profile.get("configured", true)))
	var existing_actions: Dictionary = _draft_profile.get("actions", {}).duplicate(true)
	_base_actions = existing_actions
	_action_bindings = ControllerActions.effective_bindings(_draft_profile, action_capabilities)
	if _clean_radio_actions_button != null:
		var can_clean_radio_actions := _supports_clean_radio_actions(_draft_profile)
		_clean_radio_actions_button.visible = can_clean_radio_actions
		_clean_radio_actions_help_label.visible = can_clean_radio_actions
		_clean_radio_actions_button.tooltip_text = tr("Use Backspace for Back and Escape for Pause; all button and switch actions will be cleared in this draft.")
	_update_profile_kind_picker()
	_update_glyph_family_picker()
	_update_preset_options()
	_update_profile_options()
	_update_axis_controls()
	_update_aux_controls()
	_update_action_controls()
	_update_preview()
	draft_changed.emit()


func _update_profile_options() -> void:
	if profile_picker == null:
		return
	profile_picker.clear()
	profile_picker.add_item(tr("New profile"), -1)
	profile_picker.set_item_id(0, -1)
	var current_id := str(_draft_profile.get("profile_id", ""))
	var selected := 0
	for index in _profiles.size():
		var candidate := _profiles[index]
		profile_picker.add_item("%s · %s" % [str(candidate.get("name", "Controller profile")), tr(str(candidate.get("kind", "")).capitalize())], index)
		if str(candidate.get("profile_id", "")) == current_id:
			selected = profile_picker.item_count - 1
	if selected >= 0:
		profile_picker.select(selected)


func _on_profile_selected(index: int) -> void:
	var profile_index := profile_picker.get_item_id(index)
	if profile_index >= 0 and profile_index < _profiles.size():
		if _is_capture_active():
			_cancel_capture()
		var profile: Dictionary = _profiles[profile_index]
		_switch_draft_profile(profile, _profile_context_key(profile))


func _update_profile_kind_picker() -> void:
	if profile_kind_picker == null:
		return
	var device := _device_for_id(_draft_flight_device_id)
	var can_choose_kind := not device.is_empty() and (not bool(device.get("known", false)) or str(device.get("kind", "")) == "joystick")
	profile_kind_picker.visible = can_choose_kind
	if _profile_kind_label != null:
		_profile_kind_label.visible = can_choose_kind
	if _profile_kind_help_label != null:
		_profile_kind_help_label.visible = can_choose_kind
		_profile_kind_help_label.text = tr("Choose the flight profile for this unknown controller. Gamepad starts in Mode 2; radio uses a custom profile. Calibration never starts automatically.")
	if not can_choose_kind:
		return
	profile_kind_picker.clear()
	for index in PROFILE_KIND_CHOICES.size():
		var choice: Dictionary = PROFILE_KIND_CHOICES[index]
		profile_kind_picker.add_item(tr(str(choice.label)), int(choice.id))
		profile_kind_picker.set_item_id(index, int(choice.id))
	var current_kind := str(_draft_profile.get("kind", "joystick"))
	var selected_index := 0
	for index in PROFILE_KIND_CHOICES.size():
		if str(PROFILE_KIND_CHOICES[index].kind) == current_kind:
			selected_index = index
			break
	profile_kind_picker.select(selected_index)
	profile_kind_picker.tooltip_text = profile_kind_picker.get_item_text(selected_index)


func _on_profile_kind_selected(index: int) -> void:
	if index < 0 or index >= profile_kind_picker.item_count:
		return
	var choice_id := profile_kind_picker.get_item_id(index)
	var selected_kind := ""
	for choice in PROFILE_KIND_CHOICES:
		if int(choice.id) == choice_id:
			selected_kind = str(choice.kind)
			break
	if selected_kind.is_empty() or selected_kind == str(_draft_profile.get("kind", "")):
		return
	var preset := "mode2" if selected_kind == "gamepad" else "radio_custom"
	var replacement := ControllerProfile.defaults(selected_kind, preset)
	if replacement.is_empty():
		_set_status(tr("Could not create a profile for that controller type."), true)
		return
	for key in ["profile_id", "association", "actions", "presentation"]:
		if _draft_profile.has(key):
			replacement[key] = _draft_profile[key].duplicate(true) if _draft_profile[key] is Dictionary else _draft_profile[key]
	var entered_name := profile_name_edit.text.strip_edges()
	if not entered_name.is_empty() and entered_name != str(_draft_profile.get("name", "")):
		replacement["name"] = entered_name
	if selected_kind == "joystick":
		replacement["configured"] = false
	_set_draft_profile(replacement)
	_set_status(tr("Profile type changed. Save the profile to keep this draft."), false)


func _apply_clean_radio_actions_to_draft() -> void:
	if not _supports_clean_radio_actions(_draft_profile):
		return
	var candidate := ControllerProfile.clean_radio_actions(_draft_profile)
	if candidate.is_empty():
		_set_status(tr("Could not prepare the safe radio action map. The current draft is unchanged."), true)
		return
	var validation: Dictionary = ControllerProfile.validate(candidate)
	if not bool(validation.get("ok", false)):
		_set_status(tr("Could not prepare the safe radio action map: %s") % "; ".join(validation.get("errors", [])), true)
		return
	_set_draft_profile(candidate, _draft_context_key)
	_set_status(tr("Safe radio actions are in the draft. Save keeps them; Cancel discards them."), false)


func _supports_clean_radio_actions(profile: Dictionary) -> bool:
	var kind := str(profile.get("kind", ""))
	if kind == "radio":
		return true
	return kind == "joystick" and _is_jeti_device(_device_for_id(_draft_flight_device_id))


func _update_preset_options() -> void:
	if preset_picker == null or _draft_profile.is_empty():
		return
	preset_picker.clear()
	var preset_popup := preset_picker.get_popup()
	_preset_ids.clear()
	var kind := str(_draft_profile.get("kind", ""))
	var choices: Array[Dictionary] = []
	if kind == "gamepad":
		for preset in PRESETS:
			var label := "Mode 1 · rate throttle" if preset == "mode1" else ("Mode 2 · rate throttle" if preset == "mode2" else "Trigger throttle")
			choices.append({"id": preset, "label": label})
	elif kind == "radio" and _is_jeti_device(_device_for_id(_draft_flight_device_id)):
		choices.append({"id": "radio_custom", "label": "Radio custom"})
		choices.append({"id": "jeti_mode2", "label": "JETI Mode 2"})
	for option in choices:
		var option_index := preset_picker.item_count
		var translated_label := tr(str(option.label))
		preset_picker.add_item(translated_label, option_index)
		preset_picker.set_item_id(option_index, option_index)
		preset_popup.set_item_tooltip(option_index, translated_label)
		_preset_ids.append(str(option.id))
	var current := _preset_ids.find(str(_draft_profile.get("preset", "mode2")))
	if not _preset_ids.is_empty():
		preset_picker.select(current if current >= 0 else 0)
	preset_picker.disabled = _preset_ids.is_empty()
	preset_picker.visible = not preset_picker.disabled
	_preset_label.visible = preset_picker.visible
	_preset_reset_button.visible = preset_picker.visible
	preset_picker.tooltip_text = preset_picker.get_item_text(preset_picker.selected) if preset_picker.selected >= 0 else ""
	if preset_help_label != null:
		match str(_draft_profile.get("preset", "mode2")):
			"mode1":
				preset_help_label.text = tr("Mode 1: left X yaw, left Y pitch; right X roll, right Y throttle.")
				preset_help_label.visible = kind == "gamepad"
			"trigger_absolute":
				preset_help_label.text = tr("Trigger throttle: left X yaw, right X roll, right Y pitch, RT/R2 throttle (axis 5).")
				preset_help_label.visible = kind == "gamepad"
			"jeti_mode2":
				preset_help_label.text = tr("JETI Mode 2: roll axis 0, inverted pitch axis 1, absolute throttle axis 2, yaw axis 3. Confirm your own stick and switch installation before flight.")
				preset_help_label.visible = true
			"radio_custom":
				preset_help_label.text = tr("Custom radio mapping. Axis assignments and calibration stay in this profile.")
				preset_help_label.visible = kind == "radio" and _is_jeti_device(_device_for_id(_draft_flight_device_id))
			_:
				preset_help_label.text = tr("Mode 2: left X yaw, left Y throttle; right X roll, right Y pitch.")
				preset_help_label.visible = kind == "gamepad"


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= _preset_ids.size():
		return
	_apply_preset(_preset_ids[index])


func _restore_selected_preset() -> void:
	if preset_picker.selected >= 0 and preset_picker.selected < _preset_ids.size():
		_apply_preset(_preset_ids[preset_picker.selected])
	else:
		_set_status(tr("There is no preset available for this controller."), true)


func _apply_preset(preset: String) -> void:
	if preset == "jeti_mode2":
		_apply_jeti_mode2_preset()
		return
	if preset == "radio_custom":
		var custom := ControllerProfile.defaults("radio", "radio_custom")
		if custom.is_empty():
			_set_status(tr("Could not restore the selected radio profile."), true)
			return
		for key in ["profile_id", "name", "association", "actions", "presentation", "aux"]:
			if _draft_profile.has(key):
				custom[key] = _draft_profile[key].duplicate(true) if _draft_profile[key] is Dictionary else _draft_profile[key]
		custom["preset"] = "radio_custom"
		for channel_name in CHANNELS:
			var current_channel: Variant = _draft_profile.get(channel_name, {})
			var next_channel: Dictionary = custom.get(channel_name, {}).duplicate(true)
			if current_channel is Dictionary:
				for calibration_key in ["min", "center", "max", "invert"]:
					if current_channel.has(calibration_key):
						next_channel[calibration_key] = current_channel[calibration_key]
			custom[channel_name] = next_channel
		custom["name"] = profile_name_edit.text.strip_edges() if not profile_name_edit.text.strip_edges().is_empty() else str(custom.get("name", "Radio Custom"))
		_set_draft_profile(custom)
		_set_status(tr("Custom radio mapping restored. Save keeps this draft."), false)
		return
	var replacement := ControllerProfile.defaults("gamepad", preset)
	if replacement.is_empty():
		_set_status(tr("Could not restore the selected gamepad preset."), true)
		return
	for key in ["profile_id", "name", "association", "actions", "presentation", "aux"]:
		if _draft_profile.has(key):
			replacement[key] = _draft_profile[key].duplicate(true) if _draft_profile[key] is Dictionary else _draft_profile[key]
	replacement["preset"] = preset
	if profile_name_edit.text.strip_edges().is_empty():
		profile_name_edit.text = str(replacement.get("name", "Gamepad profile"))
	else:
		replacement["name"] = profile_name_edit.text.strip_edges()
	_set_draft_profile(replacement)
	_set_status(tr("Preset restored. Save the profile to keep this mapping."), false)


func _apply_jeti_mode2_preset() -> void:
	if not _is_jeti_device(_device_for_id(_draft_flight_device_id)):
		_set_status(tr("JETI Mode 2 is available only for a recognized JETI radio."), true)
		return
	var replacement := ControllerProfile.defaults("radio", "jeti_mode2")
	if replacement.is_empty():
		_set_status(tr("Could not restore the JETI Mode 2 preset."), true)
		return
	for key in ["profile_id", "name", "association", "presentation", "aux"]:
		if _draft_profile.has(key):
			replacement[key] = _draft_profile[key].duplicate(true) if _draft_profile[key] is Dictionary else _draft_profile[key]
	var actions_value: Variant = _draft_profile.get("actions", {})
	if actions_value is Dictionary:
		var actions: Dictionary = replacement.actions.duplicate(true)
		for action_id: Variant in actions_value:
			actions[str(action_id)] = actions_value[action_id].duplicate(true) if actions_value[action_id] is Dictionary else actions_value[action_id]
		replacement["actions"] = actions
	for channel_name in CHANNELS:
		var current_channel: Variant = _draft_profile.get(channel_name, {})
		var next_channel: Dictionary = replacement.get(channel_name, {}).duplicate(true)
		if current_channel is Dictionary:
			for calibration_key in ["min", "center", "max", "invert"]:
				if current_channel.has(calibration_key):
					next_channel[calibration_key] = current_channel[calibration_key]
		replacement[channel_name] = next_channel
	replacement["preset"] = "jeti_mode2"
	replacement["name"] = profile_name_edit.text.strip_edges() if not profile_name_edit.text.strip_edges().is_empty() else str(replacement.get("name", "JETI USB Mode 2"))
	var validation: Dictionary = ControllerProfile.validate(replacement)
	if not bool(validation.get("ok", false)):
		_set_status(tr("Could not restore the JETI Mode 2 preset: %s") % "; ".join(validation.get("errors", [])), true)
		return
	_set_draft_profile(replacement)
	_set_status(tr("JETI Mode 2 mapping is in the draft. Confirm your own switch installation, then Save to keep it."), false)


func _duplicate_profile() -> void:
	var calibration_origin: Dictionary = _calibration_origins.get(_draft_context_key, {}).duplicate(true)
	var duplicate := _draft_profile.duplicate(true)
	var id_source := ControllerProfile.defaults(str(duplicate.get("kind", "gamepad")), str(duplicate.get("preset", "mode2")))
	if id_source.is_empty():
		id_source = ControllerProfile.defaults("gamepad", "mode2")
	duplicate["profile_id"] = id_source.get("profile_id", "")
	duplicate["name"] = "%s copy" % str(duplicate.get("name", "Controller profile"))
	_set_draft_profile(duplicate)
	if not calibration_origin.is_empty():
		_calibration_origins[_draft_context_key] = calibration_origin
	_set_status(tr("Profile duplicated. Save it to add a separate profile."), false)


func _update_axis_controls() -> void:
	if _draft_profile.is_empty():
		return
	var profile_kind := str(_draft_profile.get("kind", "gamepad"))
	for channel_name in CHANNELS:
		var controls: Dictionary = _axis_controls[channel_name]
		var channel: Dictionary = _draft_profile.get(channel_name, {})
		var axis_spin: SpinBox = controls.axis
		axis_spin.set_value_no_signal(float(channel.get("axis", 0)))
		var deadzone_spin: SpinBox = controls.deadzone
		var has_shaping := profile_kind == "gamepad"
		deadzone_spin.set_value_no_signal(float(channel.get("deadzone", ControllerProfile.DEFAULT_DEADZONE)))
		deadzone_spin.editable = has_shaping
		var expo_spin: SpinBox = controls.expo
		expo_spin.set_value_no_signal(float(channel.get("expo", ControllerProfile.DEFAULT_EXPO)))
		expo_spin.editable = has_shaping
		var invert: CheckBox = controls.invert
		invert.set_pressed_no_signal(bool(channel.get("invert", false)))
		axis_spin.editable = true
		invert.disabled = false


func _update_aux_controls() -> void:
	if _draft_profile.is_empty() or _aux_controls.is_empty():
		return
	var aux_value: Variant = _draft_profile.get("aux", {})
	var aux: Dictionary = aux_value.duplicate(true) if aux_value is Dictionary else {}
	for aux_name in AUX_CHANNELS:
		var controls: Dictionary = _aux_controls[aux_name]
		var binding_value: Variant = aux.get(aux_name, {})
		var binding: Dictionary = binding_value if binding_value is Dictionary else {}
		var binding_type := str(binding.get("type", ""))
		var mode_id := 1 if binding_type == "axis" else (2 if binding_type == "button" else (3 if binding_type == "switch" else 0))
		var type_picker: OptionButton = controls.type
		type_picker.select(mode_id)
		var channel_row: BoxContainer = controls.row
		var mapping: VBoxContainer = controls.mapping
		var preview: Label = controls.preview
		var desired_preview_parent: Node = mapping if mode_id == 3 else channel_row
		if preview.get_parent() != desired_preview_parent:
			preview.get_parent().remove_child(preview)
			desired_preview_parent.add_child(preview)
			if mode_id != 3:
				channel_row.move_child(preview, channel_row.get_children().find(mapping))
		var axis_editor: BoxContainer = controls.axis_editor
		var button_editor: BoxContainer = controls.button_editor
		var switch_editor: VBoxContainer = controls.switch_editor
		axis_editor.visible = mode_id == 1
		button_editor.visible = mode_id == 2
		switch_editor.visible = mode_id == 3
		var axis_spin: SpinBox = controls.axis
		axis_spin.set_value_no_signal(float(binding.get("axis", _default_aux_axis(aux_name))))
		var off_spin: SpinBox = controls.off
		off_spin.set_value_no_signal(float(binding.get("off", -1.0)))
		var on_spin: SpinBox = controls.on
		on_spin.set_value_no_signal(float(binding.get("on", 1.0)))
		var invert: CheckBox = controls.invert
		invert.set_pressed_no_signal(bool(binding.get("invert", false)))
		var button_spin: SpinBox = controls.button
		button_spin.set_value_no_signal(float(binding.get("button", 0)))
		var button_mode: OptionButton = controls.button_mode
		button_mode.select(1 if str(binding.get("mode", "level")) == "toggle_edge" else 0)
		var switch_buttons: Array = binding.get("buttons", []) if binding_type == "switch" else []
		var switch_count := switch_buttons.size() if switch_buttons.size() in [2, 3] else 2
		var count_picker: OptionButton = controls.switch_count
		count_picker.select(0 if switch_count == 2 else 1)
		var name_edit: LineEdit = controls.switch_label
		name_edit.text = str(binding.get("label", "")) if binding_type == "switch" else ""
		var switch_invert: CheckBox = controls.switch_invert
		switch_invert.set_pressed_no_signal(bool(binding.get("invert", false)))
		var button_spins: Array = controls.switch_button_spins
		var capture_buttons: Array = controls.switch_capture_buttons
		var row_indices := _switch_row_indices(switch_count)
		var row_buttons: Dictionary = {}
		for array_index in row_indices.size():
			row_buttons[int(row_indices[array_index])] = switch_buttons[array_index] if array_index < switch_buttons.size() else 0
		for row_index in 3:
			var row: HBoxContainer = controls.switch_position_rows[row_index]
			var visible_position := row_indices.has(row_index)
			row.visible = visible_position
			var switch_button_spin: SpinBox = button_spins[row_index]
			switch_button_spin.set_value_no_signal(float(row_buttons.get(row_index, 0)))
			var position_name := _switch_position_name(row_index)
			var group_name := str(binding.get("label", "")) if binding_type == "switch" else ""
			var label_control := row.get_node("AuxSwitchPositionLabel_%s_%d" % [aux_name, row_index]) as Label
			label_control.text = "%s — %s" % [group_name, tr(position_name)] if not group_name.is_empty() else tr(position_name)
			switch_button_spin.editable = visible_position
			var capture_button: Button = capture_buttons[row_index]
			capture_button.visible = visible_position
			capture_button.disabled = _draft_flight_device_id < 0 or not bool(_device_for_id(_draft_flight_device_id).get("connected", false))
			capture_button.text = tr("Listening…") if _capturing_aux_name == aux_name and _capturing_aux_position == row_index else tr("Capture")
		if mode_id == 0:
			preview.text = tr("Unbound")
	_update_aux_preview()


static func _switch_row_indices(position_count: int) -> Array:
	return [0, 2] if position_count == 2 else [0, 1, 2]


static func _switch_with_member_swap(binding: Dictionary, row_index: int, button_index: int) -> Dictionary:
	if button_index < 0 or button_index >= SmokeAux.MAX_BUTTONS:
		return {}
	var buttons: Array = SmokeAux.bound_buttons(binding)
	var row_indices := _switch_row_indices(buttons.size())
	var target_index := row_indices.find(row_index)
	if target_index < 0 or buttons.size() not in [2, 3]:
		return {}
	var existing_index := buttons.find(button_index)
	if existing_index >= 0 and existing_index != target_index:
		buttons[existing_index] = buttons[target_index]
	buttons[target_index] = button_index
	var candidate := binding.duplicate(true)
	candidate["buttons"] = buttons
	return candidate


static func _switch_position_name(row_index: int) -> String:
	return ["Up", "Middle", "Down"][clampi(row_index, 0, 2)]


func _default_aux_axis(aux_name: String) -> int:
	var used_axes := SmokeAux.flight_axes(_draft_profile)
	var aux_value: Variant = _draft_profile.get("aux", {})
	if aux_value is Dictionary:
		for other_name in AUX_CHANNELS:
			if other_name == aux_name:
				continue
			var other: Variant = aux_value.get(other_name, {})
			if other is Dictionary and str(other.get("type", "")) == "axis":
				var axis := int(other.get("axis", -1))
				if axis >= 0 and not used_axes.has(axis):
					used_axes.append(axis)
	for axis_index in ControllerProfile.AXIS_COUNT:
		if not used_axes.has(axis_index):
			return axis_index
	return 0


func _aux_binding_for_type(aux_name: String, binding_type: String) -> Dictionary:
	var aux_value: Variant = _draft_profile.get("aux", {})
	var aux: Dictionary = aux_value if aux_value is Dictionary else {}
	var existing_value: Variant = aux.get(aux_name, {})
	var existing: Dictionary = existing_value if existing_value is Dictionary else {}
	if str(existing.get("type", "")) == binding_type:
		return existing.duplicate(true)
	if binding_type == "axis":
		var axis := _default_aux_axis(aux_name)
		return {"type": "axis", "axis": axis, "off": -1.0, "on": 1.0, "invert": false}
	if binding_type == "button":
		return {"type": "button", "button": 0, "mode": "level"}
	if binding_type == "switch":
		return _new_switch_binding(aux_name, 2)
	return {}


func _new_switch_binding(aux_name: String, position_count: int, previous: Dictionary = {}) -> Dictionary:
	var buttons: Array = []
	var base_buttons: Array = previous.get("buttons", []) if previous.get("type", "") == "switch" else []
	if position_count == 2 and base_buttons.size() == 3:
		buttons = [base_buttons[0], base_buttons[2]]
	elif position_count == 3 and base_buttons.size() == 2:
		for middle in SmokeAux.MAX_BUTTONS:
			if middle in base_buttons:
				continue
			var proposed := [base_buttons[0], middle, base_buttons[1]]
			if _switch_group_is_available(aux_name, _candidate_switch(previous, proposed)):
				buttons = proposed
				break
	elif base_buttons.size() == position_count:
		buttons = base_buttons.duplicate()
	else:
		for start in SmokeAux.MAX_BUTTONS:
			var proposed := _contiguous_buttons(start, position_count)
			if _switch_group_is_available(aux_name, _candidate_switch(previous, proposed)):
				buttons = proposed
				break
	if buttons.is_empty():
		return {}
	var result: Dictionary = {"type": "switch", "buttons": buttons, "invert": bool(previous.get("invert", false))}
	var label := str(previous.get("label", "")).strip_edges()
	if not label.is_empty():
		result["label"] = label
	return result if _switch_group_is_available(aux_name, result) else {}


static func _contiguous_buttons(start: int, count: int) -> Array:
	var result: Array = []
	for offset in count:
		result.append(start + offset)
	return result


func _candidate_switch(previous: Dictionary, buttons: Array) -> Dictionary:
	var result := {"type": "switch", "buttons": buttons.duplicate(), "invert": bool(previous.get("invert", false))}
	var label := str(previous.get("label", "")).strip_edges()
	if not label.is_empty():
		result["label"] = label
	return result


func _switch_group_is_available(aux_name: String, binding: Dictionary) -> bool:
	var candidate_profile := _draft_profile.duplicate(true)
	var aux_value: Variant = candidate_profile.get("aux", {})
	var aux: Dictionary = aux_value.duplicate(true) if aux_value is Dictionary else {}
	aux[aux_name] = binding.duplicate(true)
	candidate_profile["aux"] = aux
	var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate_profile, action_capabilities)
	return bool(validation.get("ok", false))


func _on_aux_type_selected(index: int, aux_name: String) -> void:
	if _draft_profile.is_empty() or not _aux_controls.has(aux_name):
		return
	var mode_id: int = int(_aux_controls[aux_name].type.get_item_id(index))
	if mode_id == 0:
		_commit_aux_binding(aux_name, {})
	elif mode_id == 1:
		_commit_aux_binding(aux_name, _aux_binding_for_type(aux_name, "axis"))
	elif mode_id == 2:
		_commit_aux_binding(aux_name, _aux_binding_for_type(aux_name, "button"))
	elif mode_id == 3:
		var switch_binding := _aux_binding_for_type(aux_name, "switch")
		if switch_binding.is_empty():
			_update_aux_controls()
			_set_status(tr("No conflict-free switch buttons are available for this channel."), true)
		else:
			_commit_aux_binding(aux_name, switch_binding)


func _on_aux_axis_changed(value: float, aux_name: String) -> void:
	var binding := _aux_binding_for_type(aux_name, "axis")
	binding["axis"] = int(value)
	_commit_aux_binding(aux_name, binding, false)


func _on_aux_endpoint_changed(value: float, aux_name: String, endpoint: String) -> void:
	var binding := _aux_binding_for_type(aux_name, "axis")
	binding[endpoint] = value
	binding["invert"] = float(binding.get("on", 1.0)) < float(binding.get("off", -1.0))
	var invert: CheckBox = _aux_controls[aux_name].invert
	invert.set_pressed_no_signal(bool(binding.invert))
	_commit_aux_binding(aux_name, binding, false)


func _on_aux_invert_toggled(pressed: bool, aux_name: String) -> void:
	var binding := _aux_binding_for_type(aux_name, "axis")
	var off_value := float(binding.get("off", -1.0))
	var on_value := float(binding.get("on", 1.0))
	var current_inverted := on_value < off_value
	if current_inverted != pressed:
		binding["off"] = on_value
		binding["on"] = off_value
	binding["invert"] = pressed
	var controls: Dictionary = _aux_controls[aux_name]
	(controls.off as SpinBox).set_value_no_signal(float(binding.off))
	(controls.on as SpinBox).set_value_no_signal(float(binding.on))
	_commit_aux_binding(aux_name, binding, false)


func _on_aux_button_changed(value: float, aux_name: String) -> void:
	var binding := _aux_binding_for_type(aux_name, "button")
	binding["button"] = int(value)
	_commit_aux_binding(aux_name, binding, false)


func _on_aux_button_mode_selected(index: int, aux_name: String) -> void:
	var binding := _aux_binding_for_type(aux_name, "button")
	binding["mode"] = "toggle_edge" if index == 1 else "level"
	_commit_aux_binding(aux_name, binding, false)


func _on_aux_switch_count_selected(index: int, aux_name: String) -> void:
	if not _aux_controls.has(aux_name):
		return
	var position_count: OptionButton = _aux_controls[aux_name].switch_count
	if index < 0 or index >= position_count.item_count:
		return
	var requested_count := int(position_count.get_item_id(index))
	var previous := _aux_binding_for_type(aux_name, "switch")
	var binding := _new_switch_binding(aux_name, requested_count, previous)
	if binding.is_empty():
		_update_aux_controls()
		_set_status(tr("Switch positions could not be changed without a conflict."), true)
		return
	_commit_aux_binding(aux_name, binding)


func _on_aux_switch_button_changed(value: float, aux_name: String, row_index: int) -> void:
	var binding := _aux_binding_for_type(aux_name, "switch")
	var candidate := _switch_with_member_swap(binding, row_index, int(value))
	if candidate.is_empty():
		_update_aux_controls()
		return
	_commit_aux_binding(aux_name, candidate, false)


func _on_aux_switch_label_changed(value: String, aux_name: String) -> void:
	var binding := _aux_binding_for_type(aux_name, "switch")
	var switch_label := value.strip_edges()
	if switch_label.is_empty():
		binding.erase("label")
	else:
		binding["label"] = switch_label
	_commit_aux_binding(aux_name, binding, false)


func _on_aux_switch_invert_toggled(pressed: bool, aux_name: String) -> void:
	var binding := _aux_binding_for_type(aux_name, "switch")
	binding["invert"] = pressed
	_commit_aux_binding(aux_name, binding, false)


func _commit_aux_binding(aux_name: String, binding: Dictionary, report_status := true) -> bool:
	var candidate_profile := _draft_profile.duplicate(true)
	var aux_value: Variant = candidate_profile.get("aux", {})
	var aux: Dictionary = aux_value.duplicate(true) if aux_value is Dictionary else {}
	if binding.is_empty():
		aux.erase(aux_name)
	else:
		aux[aux_name] = binding.duplicate(true)
	if aux.is_empty():
		candidate_profile.erase("aux")
	else:
		candidate_profile["aux"] = aux
	var has_switch := false
	for candidate_binding: Variant in aux.values():
		if candidate_binding is Dictionary and str(candidate_binding.get("type", "")) == "switch":
			has_switch = true
			break
	if has_switch:
		var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate_profile, action_capabilities)
		if not bool(validation.get("ok", false)):
			_update_aux_controls()
			_show_rejected_validation(validation, "Switch mapping was not changed: %s")
			return false
	_draft_profile = candidate_profile
	_action_bindings = ControllerActions.effective_bindings(_draft_profile, action_capabilities)
	_update_aux_controls()
	_update_action_controls()
	_update_aux_preview()
	if report_status:
		_set_status(tr("Auxiliary input updated. Save the profile to keep it."), false)
	_draft_validation_changed()
	return true


func _update_aux_preview() -> void:
	if _aux_controls.is_empty() or _draft_profile.is_empty():
		return
	var device := _device_for_id(_draft_flight_device_id)
	var connected := _draft_flight_device_id >= 0 and not device.is_empty() and bool(device.get("connected", true))
	var aux_value: Variant = _draft_profile.get("aux", {})
	var aux: Dictionary = aux_value if aux_value is Dictionary else {}
	for aux_name in AUX_CHANNELS:
		var preview: Label = _aux_controls[aux_name].preview
		var binding_value: Variant = aux.get(aux_name, {})
		if not binding_value is Dictionary or binding_value.is_empty():
			preview.text = tr("Unbound")
			continue
		var binding: Dictionary = binding_value
		if not connected:
			preview.text = tr("Connect a flight controller to preview this input.")
			continue
		if str(binding.get("type", "")) == "axis":
			if not SmokeAux.valid_binding(binding, SmokeAux.flight_axes(_draft_profile)):
				preview.text = tr("Invalid auxiliary axis mapping.")
				continue
			var axis := int(binding.axis)
			var raw := _read_axis_preview(_draft_flight_device_id, axis)
			var amount := SmokeAux.axis_amount(raw, binding) * 100.0
			preview.text = tr("Axis %d · raw %+.2f · request %.0f%%") % [axis, raw, amount]
		elif str(binding.get("type", "")) == "button":
			if not SmokeAux.valid_binding(binding):
				preview.text = tr("Invalid auxiliary button mapping.")
				continue
			var button := int(binding.button)
			var pressed := _read_button_preview(_draft_flight_device_id, button)
			var state := tr("Pressed") if pressed else tr("Released")
			preview.text = tr("Button %d · %s · %s") % [button, tr("Toggle per press") if binding.mode == "toggle_edge" else tr("Maintained"), state]
		elif str(binding.get("type", "")) == "switch":
			if not SmokeAux.valid_binding(binding):
				preview.text = tr("Invalid switch group.")
				continue
			var buttons: Array = SmokeAux.bound_buttons(binding)
			var active_positions: Array[int] = []
			for button_index in buttons.size():
				if _read_button_preview(_draft_flight_device_id, int(buttons[button_index])):
					active_positions.append(button_index)
			if active_positions.size() > 1:
				preview.text = tr("%s · multiple positions active") % _switch_display_name(binding)
			elif active_positions.is_empty():
				preview.text = tr("%s · no position active") % _switch_display_name(binding)
			else:
				var position_index := active_positions[0]
				var row_index := position_index if buttons.size() == 3 else (0 if position_index == 0 else 2)
				var amount := float(position_index) / float(buttons.size() - 1)
				if bool(binding.get("invert", false)):
					amount = 1.0 - amount
				preview.text = tr("%s · %s · Button %d · request %.0f%%") % [
					_switch_display_name(binding), tr(_switch_position_name(row_index)), int(buttons[position_index]), amount * 100.0,
				]
		else:
			preview.text = tr("Unbound")


func _read_axis_preview(device_id: int, axis: int) -> float:
	if axis_preview_provider.is_valid():
		var sample: Variant = axis_preview_provider.call(device_id, axis)
		if typeof(sample) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(sample)):
			return float(sample)
		return 0.0
	return Input.get_joy_axis(device_id, axis) if device_id >= 0 else 0.0


func _read_button_preview(device_id: int, button: int) -> bool:
	if button_preview_provider.is_valid():
		var sample: Variant = button_preview_provider.call(device_id, button)
		return sample if typeof(sample) == TYPE_BOOL else false
	return Input.is_joy_button_pressed(device_id, button) if device_id >= 0 else false


static func _switch_display_name(binding: Dictionary) -> String:
	var label := str(binding.get("label", "")).strip_edges()
	return label if not label.is_empty() else TranslationServer.translate("Switch")


func _on_axis_changed(value: float, channel_name: String, property: String) -> void:
	if not _draft_profile.has(channel_name):
		return
	var channel: Dictionary = _draft_profile[channel_name]
	channel[property] = int(value) if property == "axis" else value
	_draft_profile[channel_name] = channel
	_update_preview()
	_draft_validation_changed()


func _on_axis_invert(pressed: bool, channel_name: String) -> void:
	if not _draft_profile.has(channel_name):
		return
	var channel: Dictionary = _draft_profile[channel_name]
	channel["invert"] = pressed
	_draft_profile[channel_name] = channel
	_update_preview()
	_draft_validation_changed()


func _on_joystick_enabled(enabled: bool) -> void:
	if str(_draft_profile.get("kind", "")) == "joystick":
		_draft_profile["configured"] = enabled
		_draft_validation_changed()


func _update_preview() -> void:
	if _preview_labels.is_empty() or _draft_profile.is_empty():
		return
	var device := _device_for_id(_draft_flight_device_id)
	var connected := _draft_flight_device_id >= 0 and not device.is_empty() and bool(device.get("connected", true))
	var kind := str(_draft_profile.get("kind", "gamepad"))
	for channel_name in CHANNELS:
		var channel: Dictionary = _draft_profile.get(channel_name, {})
		var axis := int(channel.get("axis", 0))
		var raw := _read_axis_preview(_draft_flight_device_id, axis) if connected else 0.0
		var conditioned := ControllerProfile.conditioned_axis(raw, channel, kind) if connected else 0.0
		var current: Label = _preview_labels[channel_name]
		current.text = tr("%s · raw %+.2f · conditioned %+.2f") % [tr(str(CHANNEL_LABELS[channel_name])), raw, conditioned] if connected else "%s · —" % tr(str(CHANNEL_LABELS[channel_name]))
		current.tooltip_text = current.text
		_preview_axis_labels[channel_name].text = tr("Axis %d") % axis
		var meter: ProgressBar = _preview_bars[channel_name]
		var absolute := str(channel.get("range_kind", "centered")) == "absolute"
		meter.min_value = 0.0 if absolute else -1.0
		meter.value = conditioned
	var axis_label: String
	if connected:
		axis_label = tr("Live values are read only. No controller input reaches the aircraft from this screen.")
	else:
		axis_label = tr("Select a connected flight controller to preview mapped channels.")
	preview_label.text = axis_label
	_update_aux_preview()


func _update_action_controls() -> void:
	if action_grid == null:
		return
	var presentation: Dictionary = _draft_profile.get("presentation", {})
	var family := str(presentation.get("glyph_family", "auto"))
	var device := _device_for_id(_draft_flight_device_id)
	var child_index := 3
	var last_change_button: Button
	for definition in ControllerActions.ACTIONS:
		var action_id := str(definition.id)
		var label_control: Label = action_grid.get_child(child_index)
		var binding_cell: HBoxContainer = action_grid.get_child(child_index + 1)
		var binding_control: Label = binding_cell.get_node("Binding_%s" % action_id)
		var glyph_control: TextureRect = binding_cell.get_node("BindingGlyph_%s" % action_id)
		var capture_button: Button = action_grid.get_child(child_index + 2)
		var clear_button: Button = _clear_action_buttons[action_id]
		label_control.text = tr(str(definition.label))
		var binding: Dictionary = _action_bindings.get(action_id, {})
		var prompt: Dictionary = ControllerPrompts.prompt(binding, family, device, _draft_profile)
		var fallback_text := ControllerActions.binding_text(binding)
		var prompt_text := str(prompt.get("text", fallback_text))
		binding_control.text = prompt_text if not prompt_text.is_empty() else fallback_text
		var texture_path := str(prompt.get("texture_path", ""))
		glyph_control.texture = _get_prompt_texture(texture_path)
		glyph_control.visible = glyph_control.texture != null
		if _capturing_action == action_id:
			capture_button.text = tr("Listening…")
		else:
			capture_button.text = tr("Remap")
		clear_button.text = tr("Clear")
		var clear_had_focus := clear_button.has_focus()
		clear_button.disabled = action_id in ["back", "pause"] or binding.get("type", "unbound") == "unbound"
		clear_button.focus_mode = Control.FOCUS_NONE if clear_button.disabled else Control.FOCUS_ALL
		if clear_had_focus and clear_button.disabled and capture_button.is_visible_in_tree():
			capture_button.grab_focus()
		var row_visible := action_filter.selected <= 0 or _action_category(definition) == action_filter.selected
		label_control.visible = row_visible
		binding_cell.visible = row_visible
		capture_button.visible = row_visible
		capture_button.focus_neighbor_bottom = NodePath()
		if row_visible:
			last_change_button = capture_button
		child_index += 3
	# The shorter Save caption must remain the next D-pad target below the list,
	# regardless of the Cancel button's relative width in the current language.
	if is_inside_tree() and last_change_button != null:
		last_change_button.focus_neighbor_bottom = last_change_button.get_path_to(save_button)
	_repaint_validation_feedback()


func _update_glyph_family_picker() -> void:
	if glyph_family_picker == null:
		return
	glyph_family_picker.clear()
	for family_index in PROMPT_FAMILIES.size():
		var family := PROMPT_FAMILIES[family_index]
		glyph_family_picker.add_item(tr(str(PROMPT_FAMILY_LABELS[family])), family_index)
		glyph_family_picker.set_item_id(family_index, family_index)
	var presentation: Dictionary = _draft_profile.get("presentation", {})
	var selected_index := PROMPT_FAMILIES.find(str(presentation.get("glyph_family", "auto")))
	if selected_index < 0:
		selected_index = 0
	glyph_family_picker.select(selected_index)
	glyph_family_picker.tooltip_text = tr("Prompt symbols only affect presentation; they never change controller bindings.")
	if glyph_family_help_label != null:
		glyph_family_help_label.text = tr("Prompt symbols only affect presentation; they never change controller bindings.")


func _on_glyph_family_selected(index: int) -> void:
	if _draft_profile.is_empty() or index < 0 or index >= PROMPT_FAMILIES.size():
		return
	var family := PROMPT_FAMILIES[index]
	var presentation_value: Variant = _draft_profile.get("presentation", {})
	var presentation: Dictionary = presentation_value.duplicate(true) if presentation_value is Dictionary else {}
	if str(presentation.get("glyph_family", "auto")) == family:
		return
	presentation["glyph_family"] = family
	_draft_profile["presentation"] = presentation
	_update_action_controls()
	_set_status(tr("Controller prompt family changed. Save the profile to keep it."), false)
	_refresh_validation_feedback()


func _get_prompt_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null
	if not _prompt_texture_cache.has(texture_path):
		var resource: Resource = load(texture_path)
		_prompt_texture_cache[texture_path] = resource as Texture2D
	return _prompt_texture_cache[texture_path] as Texture2D


func _start_capture(action_id: String, button: Button) -> void:
	select_section("buttons")
	# Public callers may request an action currently hidden by the category filter.
	if not button.visible:
		action_filter.select(0)
		_update_action_controls()
	_capturing_aux_name = ""
	_capturing_aux_position = -1
	_capturing_action = action_id
	_capturing_device_id = _draft_flight_device_id
	_capture_button = button
	_capture_button.grab_focus()
	_set_status(tr("Press a keyboard key or an input on the selected flight controller. Escape cancels remapping."), false)
	_update_action_controls()


func _start_aux_capture(aux_name: String, row_index: int, button: Button) -> void:
	if button.disabled or not _aux_controls.has(aux_name):
		return
	select_section("aux")
	_capturing_action = ""
	_capturing_aux_name = aux_name
	_capturing_aux_position = row_index
	_capturing_device_id = _draft_flight_device_id
	_capture_button = button
	_capture_button.grab_focus()
	_set_status(tr("Move the selected radio switch to this position. The next button press is captured; no other switch needs to be released."), false)
	_update_aux_controls()


func _is_capture_active() -> bool:
	return not _capturing_action.is_empty() or not _capturing_aux_name.is_empty()


func _capture_binding(event: InputEvent) -> void:
	if not _capturing_aux_name.is_empty():
		return
	var binding := ControllerActions.binding_from_event(event)
	if binding.is_empty():
		return
	var candidate := _base_actions.duplicate(true)
	candidate[_capturing_action] = binding
	var candidate_profile := _draft_profile.duplicate(true)
	candidate_profile["actions"] = candidate
	var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate_profile, action_capabilities)
	var accepted := bool(validation.get("ok", false))
	if accepted:
		_base_actions = candidate
		_draft_profile["actions"] = _base_actions.duplicate(true)
		_action_bindings = validation.get("bindings", ControllerActions.effective_bindings(_draft_profile, action_capabilities))
	_capture_done()
	if accepted:
		_set_status(tr("Binding updated. Save the profile to keep it."), false)
		_draft_validation_changed()
	else:
		_show_rejected_validation(validation, "Binding was not changed: %s")
	get_viewport().set_input_as_handled()


func _capture_aux_button(button_index: int) -> void:
	if _capturing_aux_name.is_empty() or button_index < 0 or button_index >= SmokeAux.MAX_BUTTONS:
		return
	var binding := _aux_binding_for_type(_capturing_aux_name, "switch")
	var candidate := _switch_with_member_swap(binding, _capturing_aux_position, button_index)
	if candidate.is_empty():
		_capture_done()
		_set_status(tr("That switch position is no longer available. Capture was cancelled."), true)
		return
	var captured_aux := _capturing_aux_name
	var committed := _commit_aux_binding(captured_aux, candidate, false)
	_capture_done()
	if committed:
		_set_status(tr("Button %d captured for this switch position. Save the profile to keep it.") % button_index, false)
		_draft_validation_changed()
	get_viewport().set_input_as_handled()


func _clear_action_binding(action_id: String) -> void:
	if action_id in ["back", "pause"]:
		return
	var candidate := _base_actions.duplicate(true)
	candidate[action_id] = {"type": "unbound"}
	var candidate_profile := _draft_profile.duplicate(true)
	candidate_profile["actions"] = candidate
	var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate_profile, action_capabilities)
	if not bool(validation.get("ok", false)):
		_show_rejected_validation(validation, "Binding was not changed: %s")
		return
	_base_actions = candidate
	_draft_profile["actions"] = _base_actions.duplicate(true)
	_action_bindings = validation.get("bindings", ControllerActions.effective_bindings(_draft_profile, action_capabilities))
	_update_action_controls()
	_set_status(tr("Action cleared. Save the profile to keep it."), false)
	_draft_validation_changed()


func _cancel_capture() -> void:
	_capture_done()
	_set_status(tr("Remapping cancelled."), false)


func _capture_done() -> void:
	_capturing_action = ""
	_capturing_aux_name = ""
	_capturing_aux_position = -1
	_capturing_device_id = -1
	_capture_button = null
	_update_action_controls()
	_update_aux_controls()


func _profile_candidate() -> Dictionary:
	var candidate := _draft_profile.duplicate(true)
	candidate["name"] = profile_name_edit.text.strip_edges()
	var selected_device := _device_for_id(_draft_flight_device_id)
	if not selected_device.is_empty():
		var association: Dictionary = candidate.get("association", {}).duplicate(true)
		var serial := str(selected_device.get("serial_number", ""))
		var guid := str(selected_device.get("guid", ""))
		var vendor_id := int(selected_device.get("vendor_id", 0))
		var product_id := int(selected_device.get("product_id", 0))
		if not serial.is_empty():
			association["serial_number"] = serial
		if not guid.is_empty() and vendor_id > 0 and product_id > 0:
			association["guid"] = guid
			association["vendor_id"] = vendor_id
			association["product_id"] = product_id
		if not serial.is_empty() or (not guid.is_empty() and vendor_id > 0 and product_id > 0):
			candidate["association"] = association
	candidate["actions"] = _base_actions.duplicate(true)
	if str(candidate.get("kind", "")) == "joystick":
		candidate["configured"] = joystick_enabled.button_pressed
	var inherited_actions := ControllerActions.effective_bindings(candidate, action_capabilities)
	for action_id: Variant in _action_bindings:
		if not inherited_actions.has(action_id) or _action_bindings[action_id] != inherited_actions[action_id]:
			candidate.actions[str(action_id)] = _action_bindings[action_id].duplicate(true)
	return candidate


func _save_profile(close_on_success := true) -> bool:
	_reset_validation()
	if _is_capture_active():
		_set_status(tr("Finish or cancel remapping before saving."), true)
		return false
	if _draft_profile.is_empty() or profile_store == null:
		_set_status(tr("There is no controller profile to save."), true)
		return false
	var calibration_origin: Dictionary = _calibration_origins.get(_draft_context_key, {})
	if not calibration_origin.is_empty() and (_draft_flight_device_id != int(calibration_origin.id) \
		or not _calibration_connection_matches(int(calibration_origin.id), int(calibration_origin.generation))):
		_set_status(tr("The radio connection changed. Calibrate again before saving these settings."), true)
		return false
	var candidate := _profile_candidate()
	var validation := _validate_candidate(candidate)
	if not bool(validation.ok):
		_validation_active = true
		_show_validation(validation, true)
		return false
	var result: Dictionary
	if save_and_apply.is_valid():
		result = save_and_apply.call(candidate, _draft_flight_device_id, _draft_ui_device_id)
	else:
		result = profile_store.call("save_profile", candidate)
	if not bool(result.get("ok", false)):
		_set_status(tr("Profile was not saved: %s") % str(result.get("error", tr("storage error"))), true)
		return false
	var saved: Dictionary = result.get("profile", candidate).duplicate(true)
	_replace_saved_profile(saved)
	_draft_profile = saved.duplicate(true)
	_drafts_by_context[_draft_context_key] = saved.duplicate(true)
	_refresh_devices()
	profile_saved.emit(saved.duplicate(true))
	if close_on_success:
		close_requested.emit()
	_reset_validation()
	return true


func _replace_saved_profile(profile: Dictionary) -> void:
	var profile_id := str(profile.get("profile_id", ""))
	for index in _profiles.size():
		if str(_profiles[index].get("profile_id", "")) == profile_id:
			_profiles[index] = profile.duplicate(true)
			_update_profile_options()
			return
	_profiles.append(profile.duplicate(true))
	_update_profile_options()


func _import_legacy_profiles() -> void:
	if profile_store == null:
		return
	var result: Dictionary = profile_store.call("import_legacy_radio")
	_legacy_profiles.clear()
	for candidate in result.get("profiles", []):
		if candidate is Dictionary:
			_legacy_profiles.append(candidate.duplicate(true))
	legacy_picker.clear()
	for index in _legacy_profiles.size():
		var candidate := _legacy_profiles[index]
		legacy_picker.add_item("%s · %s" % [str(candidate.get("name", "Legacy radio")), tr(str(candidate.get("kind", "radio")).capitalize())], index)
	legacy_picker.visible = not _legacy_profiles.is_empty()
	legacy_help_label.visible = not _legacy_profiles.is_empty()
	keep_radio_button.visible = not _legacy_profiles.is_empty()
	restore_gamepad_button.visible = not _legacy_profiles.is_empty()
	if _legacy_profiles.is_empty():
		_set_status(tr("No valid legacy radio profiles were found. The original file was not changed."), true)
	else:
		legacy_picker.select(0)
		_set_status(tr("Choose whether to preserve this as radio control or restore a gamepad preset. The legacy file remains unchanged."), false)


func _on_legacy_selected(_index: int) -> void:
	_set_status(tr("Legacy data remains unchanged until you explicitly Save a copied profile."), false)


func _selected_legacy_profile() -> Dictionary:
	if _legacy_profiles.is_empty() or legacy_picker.selected < 0 or legacy_picker.selected >= _legacy_profiles.size():
		return {}
	return _legacy_profiles[legacy_picker.selected].duplicate(true)


func _keep_legacy_radio() -> void:
	var candidate := _selected_legacy_profile()
	if candidate.is_empty():
		return
	var new_id := ControllerProfile.defaults("radio", "radio_custom")
	candidate["profile_id"] = new_id.get("profile_id", candidate.get("profile_id", ""))
	candidate["name"] = "%s · radio" % str(candidate.get("name", "Legacy profile"))
	candidate["kind"] = "radio"
	candidate["throttle_mode"] = "radio_absolute"
	_set_draft_profile(candidate)
	_set_status(tr("Radio semantics and auxiliary data are preserved. Save writes a separate v2 profile."), false)


func _restore_legacy_gamepad() -> void:
	var legacy := _selected_legacy_profile()
	if legacy.is_empty():
		return
	var candidate := ControllerProfile.defaults("gamepad", "mode2")
	candidate["name"] = "%s · Gamepad Mode 2" % str(legacy.get("name", "Controller"))
	if legacy.get("aux", {}) is Dictionary:
		candidate["aux"] = legacy.aux.duplicate(true)
	if legacy.get("association", {}) is Dictionary:
		candidate["association"] = legacy.association.duplicate(true)
	_set_draft_profile(candidate)
	_set_status(tr("This draft uses gamepad Mode 2 rate throttle. Legacy radio calibration remains in the original file."), false)


func _device_for_id(device_id: int) -> Dictionary:
	for device in _devices:
		if int(device.get("id", -1)) == device_id:
			return device.duplicate(true)
	return {}


func _registry_selected(role: String) -> int:
	if registry == null or not registry.has_method("selected_device_id"):
		return -1
	return int(registry.call("selected_device_id", role))


func _set_status(text: String, is_error: bool) -> void:
	_status_is_error = is_error and not text.is_empty()
	if status_label == null:
		return
	status_label.tooltip_text = text
	status_label.text = text
	status_label.visible = not text.is_empty()
	# UI-35b (UI-30 VC-5, AL-3): the theme's error colour plus a word, so an error never relies on colour alone.
	status_label.add_theme_color_override("font_color", ScreenTheme.ERROR if is_error else Color(0.86, 0.9, 0.94))
	if is_error and not text.is_empty():
		status_label.text = tr("Problem: %s") % text


func _register_validation_field(path: String, section: String, control: Control, labels: Array, caption: String) -> void:
	_validation_fields[path] = {"section": section, "control": control, "labels": labels, "caption": caption}
	for label: Label in labels:
		_validation_label_captions[label] = caption
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _validate_candidate(candidate: Dictionary) -> Dictionary:
	var actions := ControllerActions.validate_profile_bindings(candidate, action_capabilities)
	var profile := ControllerProfile.validate(candidate)
	var issues: Array = []
	var seen: Dictionary = {}
	for report: Dictionary in [profile, actions]:
		for issue: Dictionary in report.get("issues", []):
			var key: String = str(issue.code) + str(issue.paths)
			if not seen.has(key):
				seen[key] = true
				issues.append(issue)
	return {"ok": bool(actions.ok) and bool(profile.ok), "issues": issues,
		"errors": actions.errors if not bool(actions.ok) else profile.errors}


func _reset_validation() -> void:
	_clear_field_errors()
	_validation_active = false
	_rejected_issues.clear()
	_rejected_message = ""
	_rejected_errors.clear()
	if status_label != null and status_label.text == _validation_status:
		_set_status("", false)
	_validation_status = ""


func _draft_validation_changed() -> void:
	if not _rejected_issues.is_empty():
		_rejected_issues.clear()
		_rejected_message = ""
		_rejected_errors.clear()
		_clear_field_errors()
		if status_label.text == _validation_status:
			_set_status("", false)
	_refresh_validation_feedback()


func _refresh_validation_feedback() -> void:
	if not _rejected_issues.is_empty():
		_render_validation_fields(_rejected_issues, false, true)
		if status_label.text == _validation_status:
			_set_status(tr(_rejected_message) % "; ".join(_rejected_errors), true)
			_validation_status = status_label.text
	elif _validation_active and not _draft_profile.is_empty():
		_show_validation(_validate_candidate(_profile_candidate()), false)


func _repaint_validation_feedback() -> void:
	if not _rejected_issues.is_empty():
		_render_validation_fields(_rejected_issues, false, true)
	elif _validation_active and not _draft_profile.is_empty():
		_render_validation_fields(_validate_candidate(_profile_candidate()).issues, false)


func _show_validation(report: Dictionary, focus_error: bool) -> void:
	_render_validation_fields(report.get("issues", []), focus_error)
	# An unrelated storage/disconnection error owns the footer until explicitly retried.
	if not focus_error and status_label.text != _validation_status and _status_is_error:
		return
	if bool(report.ok):
		if status_label.text == _validation_status:
			_set_status("", false)
	else:
		var errors: Array = report.get("errors", [])
		var text := tr("Profile cannot be saved: %s") % "; ".join(errors)
		if profile_name_edit.text.strip_edges().is_empty():
			text = tr("Enter a profile name before saving.")
		_set_status(text, true)
	_validation_status = status_label.text


func _show_rejected_validation(report: Dictionary, message: String) -> void:
	_rejected_issues = report.get("issues", []).duplicate(true)
	_rejected_message = message
	_rejected_errors = report.get("errors", []).duplicate()
	_render_validation_fields(_rejected_issues, false, true)
	_set_status(tr(message) % "; ".join(report.get("errors", [])), true)
	_validation_status = status_label.text


func _validation_field_keys(path: String) -> Array[String]:
	var parts := path.split(".")
	if parts.size() == 3 and parts[0] == "aux" and parts[2] == "invert":
		var aux: Variant = _draft_profile.get("aux", {})
		if aux is Dictionary and aux.get(parts[1], {}) is Dictionary and aux.get(parts[1], {}).get("type", "") == "switch":
			return ["aux." + parts[1] + ".switch_invert"]
	if _validation_fields.has(path):
		return [path]
	if parts[0] == "aux" and parts.size() >= 2 and _aux_controls.has(parts[1]):
		var base := "aux." + parts[1] + "."
		var member := parts[2] if parts.size() > 2 else "type"
		if member == "mode":
			return [base + "button_mode"]
		if member == "label":
			return [base + "switch_label"]
		if member == "buttons":
			var binding: Dictionary = _draft_profile.get("aux", {}).get(parts[1], {})
			var buttons: Array = binding.get("buttons", [])
			var keys: Array[String] = []
			for index: int in _switch_row_indices(buttons.size()):
				keys.append(base + "buttons.%d" % index)
			return keys
		return [base + "type"]
	if parts[0] in CHANNELS or path == "throttle_mode":
		# Calibration ranges have no direct editor. The row explains the repair route.
		return [parts[0] + ".axis"] if parts[0] in CHANNELS else ["throttle.axis"]
	return []


func _validation_message(issue: Dictionary) -> String:
	var names: Array[String] = []
	for path: String in issue.get("paths", []):
		for key: String in _validation_field_keys(path):
			var caption: String = tr(str(_validation_fields[key].caption))
			if not names.has(caption):
				names.append(caption)
	match str(issue.get("code", "")):
		"name_invalid": return tr("Enter a profile name before saving.")
		"axis_conflict", "binding_conflict", "aux_conflict", "action_flight_axis_conflict", "action_aux_source_conflict":
			return tr("Choose separate inputs for %s.") % ", ".join(names)
		"action_aux_conflict": return tr("Use either the action or the extra channel: %s.") % ", ".join(names)
		"axis_invalid": return tr("Choose a source axis from 0 to 9.")
		"range_invalid", "channel_invalid": return tr("Calibrate this channel or restore a preset.")
		"deadzone_invalid": return tr("Set the deadzone between 0 and 0.95.")
		"expo_invalid": return tr("Set expo between 0 and 1.")
		"recovery_binding_missing": return tr("Assign an input so you can return or pause.")
		"binding_invalid", "action_unknown": return tr("Remap this action to a valid input.")
		"aux_invalid": return tr("Check this input and its endpoints; keep it separate from the flight axes.")
	return tr("Check this setting or restore a preset.")


func _render_validation_fields(issues: Array, focus_error: bool, rejected := false) -> void:
	_clear_field_errors()
	var messages: Dictionary = {}
	for issue: Dictionary in issues:
		var explanation := _validation_message(issue)
		if rejected:
			explanation = tr("Assignment not applied: %s") % explanation
		for path: String in issue.get("paths", []):
			for key: String in _validation_field_keys(path):
				if not messages.has(key):
					messages[key] = []
				if not messages[key].has(explanation):
					messages[key].append(explanation)
	if focus_error:
		for key: String in _validation_fields:
			if messages.has(key) and _focus_validation_field(key):
				break
	var label_messages: Dictionary = {}
	for key: String in messages:
		var entry: Dictionary = _validation_fields[key]
		var control: Control = entry.control
		_mark_field_error(control.get_line_edit() if control is SpinBox else control)
		for label: Label in entry.labels:
			if not label_messages.has(label):
				label_messages[label] = []
			for message: String in messages[key]:
				if not label_messages[label].has(message):
					label_messages[label].append(message)
	for label: Label in label_messages:
		label.text = tr(str(_validation_label_captions[label])) + "\n" + tr("Problem: %s") % "\n".join(label_messages[label])


func _focus_validation_field(key: String) -> bool:
	var entry: Dictionary = _validation_fields[key]
	select_section(str(entry.section))
	var control: Control = entry.control
	if entry.section == "buttons" and not control.is_visible_in_tree():
		action_filter.select(0)
		_update_action_controls()
	if control is SpinBox:
		control = control.get_line_edit()
	if not control.is_visible_in_tree() or (control is BaseButton and control.disabled) or (control is LineEdit and not control.editable):
		return false
	_initial_focus_wait_frames = 0
	control.grab_focus()
	(_section_body.get_parent() as ScrollContainer).ensure_control_visible.call_deferred(control)
	return true


func _mark_field_error(control: Control) -> void:
	if not is_instance_valid(control) or control in _error_field_controls:
		return
	_error_field_controls.append(control)
	var saved_styles: Dictionary = {}
	var style_names: Array[String] = ["normal", "focus"]
	if control is BaseButton:
		style_names.append_array(["hover", "pressed", "hover_pressed"])
	for style_name: String in style_names:
		var original := control.get_theme_stylebox(style_name)
		saved_styles[style_name] = original if control.has_theme_stylebox_override(style_name) else null
		var style: StyleBoxFlat = original.duplicate() as StyleBoxFlat
		if style == null:
			style = StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT
		style.border_color = ScreenTheme.ERROR
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_border_width(side, maxi(2, style.get_border_width(side)))
		control.add_theme_stylebox_override(style_name, style)
	_error_field_styles[control] = saved_styles


func _clear_field_errors() -> void:
	for control: Control in _error_field_controls:
		if is_instance_valid(control):
			for style_name: String in _error_field_styles.get(control, {}):
				var original: StyleBox = _error_field_styles[control][style_name]
				if original != null:
					control.add_theme_stylebox_override(style_name, original)
				else:
					control.remove_theme_stylebox_override(style_name)
	_error_field_controls.clear()
	_error_field_styles.clear()
	for label: Label in _validation_label_captions:
		if is_instance_valid(label):
			label.text = tr(str(_validation_label_captions[label]))


static func _section_label(text: String) -> Label:
	var result := _label(text, "SectionLabel")
	result.add_theme_constant_override("margin_top", 6)
	return result


static func _label(text: String, variation: String, wrap := false) -> Label:
	return Widgets.label(text, variation, wrap)


static func _button(text: String, variation := "", node_name := "") -> Button:
	return Widgets.button(text, variation, node_name)


static func _option(placeholder: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = 250.0
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = TranslationServer.translate(placeholder)
	return picker


static func _spin_box(minimum: float, maximum: float, step_value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.rounded = false
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.x = 110.0
	return spin


static func _add_field(grid: GridContainer, label_text: String, control: Control) -> Label:
	return _add_control_field(grid, label_text, control)


static func _add_control_field(parent: Container, label_text: String, control: Control) -> Label:
	var field := VBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 3)
	var label := _label(label_text, "SecondaryLabel", true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(control)
	parent.add_child(field)
	return label


static func _add_inline_control_field(parent: BoxContainer, label_text: String, control: Control) -> BoxContainer:
	var field := BoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 4)
	var label := _label(label_text, "SectionLabel", true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 42.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(control)
	parent.add_child(field)
	return field
