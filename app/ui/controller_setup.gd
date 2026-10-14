extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiInput := preload("res://ui/ui_input.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerPrompts := preload("res://ui/controller_prompts.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")

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

var action_filter: OptionButton
var _settings_panel: PanelContainer
var _section_pages: Dictionary = {}
var _section_buttons: Dictionary = {}
var _section_navigation: HBoxContainer
var _section_body: VBoxContainer
var _selected_section := "devices"
var _device_summary: Label
var _empty_device_label: Label
var _preview_axis_labels: Dictionary = {}
var _axis_columns: BoxContainer

var _screen: Control
var _profiles: Array[Dictionary] = []
var _legacy_profiles: Array[Dictionary] = []
var _devices: Array[Dictionary] = []
var _draft_profile: Dictionary = {}
var _drafts_by_context: Dictionary = {}
var _draft_context_key := ""
var _base_actions: Dictionary = {}
var _action_bindings: Dictionary = {}
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
var _capture_release_tokens: Dictionary = {}
var _preview_clock := 0.0
var _initial_focus_wait_frames := 0
var _profile_kind_label: Label
var _profile_kind_help_label: Label
var _joystick_label: Label
var _preset_label: Label
var _preset_reset_button: Button
var _prompt_texture_cache: Dictionary = {}


func _init() -> void:
	name = "ControllerSetup"
	layer = LAYER
	_build()


## The owner injects shared objects before adding this CanvasLayer to the tree.
## Controller choices and profile edits stay draft until one Save operation succeeds.
func configure(controller_registry: Object, store: Object, flight_device_id := -1, ui_device_id := -1) -> void:
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
	if not _capturing_action.is_empty():
		_cancel_capture()
		return
	close_requested.emit()


func _cancel_edits() -> void:
	if not _capturing_action.is_empty():
		_capture_done()
	close_requested.emit()


func current_profile() -> Dictionary:
	return _draft_profile.duplicate(true)


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
	_settings_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_settings_panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(shell)
	var header := HBoxContainer.new()
	header.name = "ControllerSetupHeader"
	var title := _label("Controller settings", "TitleLabel")
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := _button("Close", "", "Close")
	close_button.pressed.connect(request_close)
	header.add_child(close_button)
	shell.add_child(header)
	_device_summary = _label("", "SecondaryLabel")
	_device_summary.name = "ControllerDeviceSummary"
	_device_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shell.add_child(_device_summary)
	_section_navigation = HBoxContainer.new()
	_section_navigation.name = "ControllerSections"
	_section_navigation.add_theme_constant_override("separation", 6)
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

	var role_actions := HBoxContainer.new()
	role_actions.add_theme_constant_override("separation", 8)
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
	var recovery_row := HBoxContainer.new()
	recovery_row.add_theme_constant_override("separation", 8)
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
	_add_field(profile_row, "Saved profile", profile_picker)
	_add_field(profile_row, "Name", profile_name_edit)
	glyph_family_picker = _option("Controller prompts")
	glyph_family_picker.item_selected.connect(_on_glyph_family_selected)
	_add_field(profile_row, "Controller prompts", glyph_family_picker)
	profile_kind_picker = _option("Profile type")
	profile_kind_picker.item_selected.connect(_on_profile_kind_selected)
	_profile_kind_label = _label("Profile type", "SecondaryLabel")
	profile_row.add_child(_profile_kind_label)
	profile_row.add_child(profile_kind_picker)
	preset_picker = _option("Gamepad preset")
	preset_picker.item_selected.connect(_on_preset_selected)
	_preset_label = _label("Gamepad preset", "SecondaryLabel")
	profile_row.add_child(_preset_label)
	profile_row.add_child(preset_picker)
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
	_joystick_label = _label("Unknown joystick", "SecondaryLabel")
	profile_row.add_child(_joystick_label)
	profile_row.add_child(joystick_enabled)

	var profile_actions := HBoxContainer.new()
	profile_actions.add_theme_constant_override("separation", 8)
	var reset_button := _button("Restore selected preset")
	_preset_reset_button = reset_button
	reset_button.pressed.connect(_restore_selected_preset)
	profile_actions.add_child(reset_button)
	var duplicate_button := _button("Duplicate profile")
	duplicate_button.pressed.connect(_duplicate_profile)
	profile_actions.add_child(duplicate_button)
	page.add_child(profile_actions)

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
	axis_grid.add_theme_constant_override("h_separation", 14)
	axis_grid.add_theme_constant_override("v_separation", 5)
	axis_columns.add_child(axis_grid)
	for heading in ["Channel", "Source axis", "Deadzone", "Expo", "Invert"]:
		axis_grid.add_child(_label(heading, "SectionLabel"))
	for channel in CHANNELS:
		var channel_label := _label(str(CHANNEL_LABELS[channel]), "SecondaryLabel")
		axis_grid.add_child(channel_label)
		var axis_spin := _spin_box(0.0, float(ControllerProfile.AXIS_COUNT - 1), 1.0)
		axis_spin.custom_minimum_size.x = 100.0
		axis_grid.add_child(axis_spin)
		var deadzone_spin := _spin_box(0.0, 0.95, 0.01)
		deadzone_spin.custom_minimum_size.x = 110.0
		axis_grid.add_child(deadzone_spin)
		var expo_spin := _spin_box(0.0, 1.0, 0.01)
		expo_spin.custom_minimum_size.x = 110.0
		axis_grid.add_child(expo_spin)
		var invert := CheckBox.new()
		invert.text = "Invert"
		axis_grid.add_child(invert)
		_axis_controls[channel] = {"axis": axis_spin, "deadzone": deadzone_spin, "expo": expo_spin, "invert": invert}
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
		var channel_row := HBoxContainer.new()
		channel_row.name = "AuxMappingRow_%s" % aux_name
		channel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel_row.add_theme_constant_override("separation", 8)
		channel_block.add_child(channel_row)
		var aux_label := _label(tr(str(AUX_CHANNEL_LABELS[aux_name])), "SecondaryLabel")
		aux_label.custom_minimum_size.x = 160.0
		channel_row.add_child(aux_label)
		var type_picker := OptionButton.new()
		type_picker.name = "AuxType_%s" % aux_name
		type_picker.custom_minimum_size.x = 224.0
		for mode_data in [["Disabled", 0], ["Axis", 1], ["Button", 2]]:
			var type_index := type_picker.item_count
			type_picker.add_item(tr(str(mode_data[0])), int(mode_data[1]))
			type_picker.set_item_id(type_index, int(mode_data[1]))
		channel_row.add_child(type_picker)
		var mapping := HBoxContainer.new()
		mapping.name = "AuxMapping_%s" % aux_name
		mapping.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mapping.add_theme_constant_override("separation", 4)
		var axis_editor := HBoxContainer.new()
		axis_editor.name = "AuxAxisEditor_%s" % aux_name
		axis_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_editor.add_theme_constant_override("separation", 3)
		var axis_label := _label("Axis", "SecondaryLabel")
		axis_editor.add_child(axis_label)
		var axis_spin := _spin_box(0.0, float(ControllerProfile.AXIS_COUNT - 1), 1.0)
		axis_spin.name = "AuxAxis_%s" % aux_name
		axis_spin.custom_minimum_size.x = 58.0
		axis_editor.add_child(axis_spin)
		var off_label := _label("Off endpoint", "SecondaryLabel")
		axis_editor.add_child(off_label)
		var off_spin := _spin_box(-1.0, 1.0, 0.05)
		off_spin.name = "AuxOff_%s" % aux_name
		off_spin.custom_minimum_size.x = 66.0
		axis_editor.add_child(off_spin)
		var on_label := _label("On endpoint", "SecondaryLabel")
		axis_editor.add_child(on_label)
		var on_spin := _spin_box(-1.0, 1.0, 0.05)
		on_spin.name = "AuxOn_%s" % aux_name
		on_spin.custom_minimum_size.x = 66.0
		axis_editor.add_child(on_spin)
		var aux_invert := CheckBox.new()
		aux_invert.name = "AuxInvert_%s" % aux_name
		aux_invert.text = tr("Invert")
		axis_editor.add_child(aux_invert)
		mapping.add_child(axis_editor)
		var button_editor := HBoxContainer.new()
		button_editor.name = "AuxButtonEditor_%s" % aux_name
		button_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button_editor.add_theme_constant_override("separation", 4)
		button_editor.add_child(_label("Button", "SecondaryLabel"))
		var button_spin := _spin_box(0.0, float(SmokeAux.MAX_BUTTONS - 1), 1.0)
		button_spin.name = "AuxButton_%s" % aux_name
		button_spin.custom_minimum_size.x = 70.0
		button_editor.add_child(button_spin)
		var button_mode := OptionButton.new()
		button_mode.name = "AuxButtonMode_%s" % aux_name
		button_mode.custom_minimum_size.x = 144.0
		for mode_data in [["Maintained", "level"], ["Toggle per press", "toggle_edge"]]:
			var mode_index := button_mode.item_count
			button_mode.add_item(tr(str(mode_data[0])), mode_index)
			button_mode.set_item_id(mode_index, mode_index)
		button_editor.add_child(button_mode)
		mapping.add_child(button_editor)
		channel_block.add_child(mapping)
		var aux_preview := _label(tr("Unbound"), "SecondaryLabel", true)
		aux_preview.name = "AuxPreview_%s" % aux_name
		aux_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel_row.add_child(aux_preview)
		channel_row.move_child(aux_preview, 1)
		channel_block.add_child(HSeparator.new())
		_aux_controls[aux_name] = {
			"type": type_picker,
			"mapping": mapping,
			"axis_editor": axis_editor,
			"axis": axis_spin,
			"off": off_spin,
			"on": on_spin,
			"invert": aux_invert,
			"button_editor": button_editor,
			"button": button_spin,
			"button_mode": button_mode,
			"preview": aux_preview,
		}
		type_picker.item_selected.connect(_on_aux_type_selected.bind(aux_name))
		axis_spin.value_changed.connect(_on_aux_axis_changed.bind(aux_name))
		off_spin.value_changed.connect(_on_aux_endpoint_changed.bind(aux_name, "off"))
		on_spin.value_changed.connect(_on_aux_endpoint_changed.bind(aux_name, "on"))
		aux_invert.toggled.connect(_on_aux_invert_toggled.bind(aux_name))
		button_spin.value_changed.connect(_on_aux_button_changed.bind(aux_name))
		button_mode.item_selected.connect(_on_aux_button_mode_selected.bind(aux_name))

	page = _section_pages["axes"]
	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.add_theme_constant_override("separation", 5)
	axis_columns.add_child(preview_column)
	preview_column.add_child(_section_label("LIVE PREVIEW"))
	for channel in CHANNELS:
		var live_row := VBoxContainer.new()
		live_row.custom_minimum_size.y = 44.0
		live_row.add_theme_constant_override("separation", 3)
		preview_column.add_child(live_row)
		var current := _label(tr("%s · raw — · conditioned —") % tr(str(CHANNEL_LABELS[channel])), "SecondaryLabel", false)
		current.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		live_row.add_child(current)
		var meter_row := HBoxContainer.new()
		live_row.add_child(meter_row)
		var meter := ProgressBar.new()
		meter.custom_minimum_size = Vector2(180.0, 10.0)
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
		action_grid.add_child(_label(tr(str(definition.label)), "SecondaryLabel"))
		var binding_cell := HBoxContainer.new()
		binding_cell.name = "BindingCell_%s" % action_id
		binding_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_cell.add_theme_constant_override("separation", 8)
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
	_resize_panel()


func _resize_panel() -> void:
	_settings_panel.custom_minimum_size = Vector2(minf(1160.0, maxf(0.0, _screen.size.x - 40.0)), minf(780.0, maxf(0.0, _screen.size.y - 40.0)))
	_axis_columns.vertical = _screen.size.x < 1100.0


func _make_section(section_id: String, caption: String) -> VBoxContainer:
	var button := _button(caption, "", "Section_%s" % section_id)
	button.toggle_mode = true
	var active_style := _screen.get_theme_stylebox("normal", "Button").duplicate() as StyleBoxFlat
	active_style.border_width_bottom = 3
	active_style.border_color = Color("f5c65d")
	button.add_theme_stylebox_override("pressed", active_style)
	button.add_theme_stylebox_override("hover_pressed", active_style)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	if section_id != _selected_section and not _capturing_action.is_empty():
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
	var flight := flight_device_picker.get_item_text(flight_device_picker.selected) if flight_device_picker.selected >= 0 else tr("No flight controller")
	var menu := ui_device_picker.get_item_text(ui_device_picker.selected) if ui_device_picker.selected >= 0 else tr("Keyboard + mouse")
	_device_summary.text = tr("Flight: %s   ·   Menus: %s") % [flight, menu]
	_device_summary.tooltip_text = _device_summary.text
	_empty_device_label.visible = not _devices.any(func(device: Dictionary) -> bool: return bool(device.get("connected", true)))


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
	_update_action_controls()
	profile_name_edit.placeholder_text = TranslationServer.translate("Profile name")


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
	if _capturing_action.is_empty():
		return
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
	if not _capturing_action.is_empty():
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
	picker.add_item(tr("Keyboard + mouse") if menu_only else tr("No flight controller"), -1)
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
		if not bool(device.get("connected", true)):
			name += " · " + tr("disconnected")
		var label := "%s · %s" % [name, tr(kind.capitalize())]
		picker.add_item(label, id)
		var item_index := picker.item_count - 1
		picker.get_popup().set_item_tooltip(item_index, label)
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


func _on_flight_device_selected(index: int) -> void:
	var selected_id := flight_device_picker.get_item_id(index)
	var capture_cancelled := selected_id != _draft_flight_device_id and not _capturing_action.is_empty()
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
	var preset := "mode2" if expected_kind == "gamepad" else "radio_custom"
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
	_action_bindings = ControllerActions.effective_bindings(_draft_profile)
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
		if not _capturing_action.is_empty():
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


func _update_preset_options() -> void:
	if preset_picker == null or _draft_profile.is_empty():
		return
	preset_picker.clear()
	var preset_popup := preset_picker.get_popup()
	for index in PRESETS.size():
		var preset := PRESETS[index]
		var label := "Mode 1 · rate throttle" if preset == "mode1" else ("Mode 2 · rate throttle" if preset == "mode2" else "Trigger throttle")
		var translated_label := tr(label)
		preset_picker.add_item(translated_label, index)
		preset_popup.set_item_tooltip(index, translated_label)
	var current := PRESETS.find(str(_draft_profile.get("preset", "mode2")))
	if current >= 0:
		preset_picker.select(current)
	else:
		preset_picker.select(1)
	preset_picker.disabled = str(_draft_profile.get("kind", "")) != "gamepad"
	preset_picker.visible = not preset_picker.disabled
	_preset_label.visible = preset_picker.visible
	_preset_reset_button.visible = preset_picker.visible
	preset_picker.tooltip_text = preset_picker.get_item_text(preset_picker.selected)
	if preset_help_label != null:
		match str(_draft_profile.get("preset", "mode2")):
			"mode1":
				preset_help_label.text = tr("Mode 1: left X yaw, left Y pitch; right X roll, right Y throttle.")
			"trigger_absolute":
				preset_help_label.text = tr("Trigger throttle: left X yaw, right X roll, right Y pitch, RT/R2 throttle (axis 5). Release RT/R2 to arm.")
			_:
				preset_help_label.text = tr("Mode 2: left X yaw, left Y throttle; right X roll, right Y pitch.")
		preset_help_label.visible = str(_draft_profile.get("kind", "")) == "gamepad"


func _on_preset_selected(index: int) -> void:
	if str(_draft_profile.get("kind", "")) != "gamepad" or index < 0 or index >= PRESETS.size():
		return
	_apply_preset(PRESETS[index])


func _restore_selected_preset() -> void:
	if str(_draft_profile.get("kind", "")) == "gamepad":
		_apply_preset(PRESETS[preset_picker.selected])
	else:
		_set_status(tr("This profile is not a gamepad preset. Use legacy recovery to change its controller semantics."), true)


func _apply_preset(preset: String) -> void:
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


func _duplicate_profile() -> void:
	var duplicate := _draft_profile.duplicate(true)
	var id_source := ControllerProfile.defaults(str(duplicate.get("kind", "gamepad")), str(duplicate.get("preset", "mode2")))
	if id_source.is_empty():
		id_source = ControllerProfile.defaults("gamepad", "mode2")
	duplicate["profile_id"] = id_source.get("profile_id", "")
	duplicate["name"] = "%s copy" % str(duplicate.get("name", "Controller profile"))
	_set_draft_profile(duplicate)
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
		var mode_id := 1 if binding_type == "axis" else (2 if binding_type == "button" else 0)
		var type_picker: OptionButton = controls.type
		type_picker.select(mode_id)
		var axis_editor: HBoxContainer = controls.axis_editor
		var button_editor: HBoxContainer = controls.button_editor
		axis_editor.visible = mode_id == 1
		button_editor.visible = mode_id == 2
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
		var preview: Label = controls.preview
		if mode_id == 0:
			preview.text = tr("Unbound")
	_update_aux_preview()


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
	return {}


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


func _commit_aux_binding(aux_name: String, binding: Dictionary, report_status := true) -> void:
	var aux_value: Variant = _draft_profile.get("aux", {})
	var aux: Dictionary = aux_value.duplicate(true) if aux_value is Dictionary else {}
	if binding.is_empty():
		aux.erase(aux_name)
	else:
		aux[aux_name] = binding.duplicate(true)
	if aux.is_empty():
		_draft_profile.erase("aux")
	else:
		_draft_profile["aux"] = aux
	_action_bindings = ControllerActions.effective_bindings(_draft_profile)
	_update_aux_controls()
	_update_action_controls()
	_update_aux_preview()
	if report_status:
		_set_status(tr("Auxiliary input updated. Save the profile to keep it."), false)


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
			var raw := Input.get_joy_axis(_draft_flight_device_id, axis)
			var amount := SmokeAux.axis_amount(raw, binding) * 100.0
			preview.text = tr("Axis %d · raw %+.2f · request %.0f%%") % [axis, raw, amount]
		elif str(binding.get("type", "")) == "button":
			if not SmokeAux.valid_binding(binding):
				preview.text = tr("Invalid auxiliary button mapping.")
				continue
			var button := int(binding.button)
			var pressed := Input.is_joy_button_pressed(_draft_flight_device_id, button)
			var state := tr("Pressed") if pressed else tr("Released")
			preview.text = tr("Button %d · %s · %s") % [button, tr("Toggle per press") if binding.mode == "toggle_edge" else tr("Maintained"), state]
		else:
			preview.text = tr("Unbound")


func _on_axis_changed(value: float, channel_name: String, property: String) -> void:
	if not _draft_profile.has(channel_name):
		return
	var channel: Dictionary = _draft_profile[channel_name]
	channel[property] = int(value) if property == "axis" else value
	_draft_profile[channel_name] = channel
	_update_preview()


func _on_axis_invert(pressed: bool, channel_name: String) -> void:
	if not _draft_profile.has(channel_name):
		return
	var channel: Dictionary = _draft_profile[channel_name]
	channel["invert"] = pressed
	_draft_profile[channel_name] = channel
	_update_preview()


func _on_joystick_enabled(enabled: bool) -> void:
	if str(_draft_profile.get("kind", "")) == "joystick":
		_draft_profile["configured"] = enabled


func _update_preview() -> void:
	if _preview_labels.is_empty() or _draft_profile.is_empty():
		return
	var device := _device_for_id(_draft_flight_device_id)
	var connected := _draft_flight_device_id >= 0 and not device.is_empty() and bool(device.get("connected", true))
	var kind := str(_draft_profile.get("kind", "gamepad"))
	for channel_name in CHANNELS:
		var channel: Dictionary = _draft_profile.get(channel_name, {})
		var axis := int(channel.get("axis", 0))
		var raw := Input.get_joy_axis(_draft_flight_device_id, axis) if connected else 0.0
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
		var prompt: Dictionary = ControllerPrompts.prompt(binding, family, device)
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
	_capturing_action = action_id
	_capturing_device_id = _draft_flight_device_id
	_capture_button = button
	_capture_button.grab_focus()
	_set_status(tr("Press a keyboard key or an input on the selected flight controller. Escape cancels remapping."), false)
	_update_action_controls()


func _capture_binding(event: InputEvent) -> void:
	var binding := ControllerActions.binding_from_event(event)
	if binding.is_empty():
		return
	var candidate := _base_actions.duplicate(true)
	candidate[_capturing_action] = binding
	var candidate_profile := _draft_profile.duplicate(true)
	candidate_profile["actions"] = candidate
	var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate_profile)
	if not bool(validation.get("ok", false)):
		var errors: Array = validation.get("errors", [])
		_set_status(tr("Profile cannot be saved: %s") % "; ".join(errors), true)
	else:
		_base_actions = candidate
		_draft_profile["actions"] = _base_actions.duplicate(true)
		_action_bindings = validation.get("bindings", ControllerActions.effective_bindings(_draft_profile))
		_set_status(tr("Binding updated. Save the profile to keep it."), false)
	_capture_done()
	get_viewport().set_input_as_handled()


func _clear_action_binding(action_id: String) -> void:
	if action_id in ["back", "pause"]:
		return
	var candidate := _base_actions.duplicate(true)
	candidate[action_id] = {"type": "unbound"}
	var candidate_profile := _draft_profile.duplicate(true)
	candidate_profile["actions"] = candidate
	var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate_profile)
	if not bool(validation.get("ok", false)):
		var errors: Array = validation.get("errors", [])
		_set_status(tr("Profile cannot be saved: %s") % "; ".join(errors), true)
		return
	_base_actions = candidate
	_draft_profile["actions"] = _base_actions.duplicate(true)
	_action_bindings = validation.get("bindings", ControllerActions.effective_bindings(_draft_profile))
	_update_action_controls()
	_set_status(tr("Action cleared. Save the profile to keep it."), false)


func _cancel_capture() -> void:
	_capture_done()
	_set_status(tr("Remapping cancelled."), false)


func _capture_done() -> void:
	_capturing_action = ""
	_capturing_device_id = -1
	_capture_button = null
	_update_action_controls()


func _save_profile(close_on_success := true) -> bool:
	if not _capturing_action.is_empty():
		_set_status(tr("Finish or cancel remapping before saving."), true)
		return false
	if _draft_profile.is_empty() or profile_store == null:
		_set_status(tr("There is no controller profile to save."), true)
		return false
	var candidate := _draft_profile.duplicate(true)
	var profile_name := profile_name_edit.text.strip_edges()
	if profile_name.is_empty():
		_set_status(tr("Enter a profile name before saving."), true)
		return false
	candidate["name"] = profile_name
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
	var inherited_actions := ControllerActions.effective_bindings(candidate)
	for action_id: Variant in _action_bindings:
		if not inherited_actions.has(action_id) or _action_bindings[action_id] != inherited_actions[action_id]:
			candidate.actions[str(action_id)] = _action_bindings[action_id].duplicate(true)
	var actions_validation: Dictionary = ControllerActions.validate_profile_bindings(candidate)
	if not bool(actions_validation.get("ok", false)):
		var errors: Array = actions_validation.get("errors", [])
		_set_status(tr("Profile cannot be saved: %s") % "; ".join(errors), true)
		return false
	var validation: Dictionary = ControllerProfile.validate(candidate)
	if not bool(validation.get("ok", false)):
		var errors: Array = validation.get("errors", [])
		_set_status(tr("Profile cannot be saved: %s") % "; ".join(errors), true)
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
	if status_label == null:
		return
	status_label.tooltip_text = text
	status_label.text = text
	status_label.visible = not text.is_empty()
	status_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.42) if is_error else Color(0.86, 0.9, 0.94))


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


static func _add_field(grid: GridContainer, label_text: String, control: Control) -> void:
	grid.add_child(_label(label_text, "SecondaryLabel"))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
