extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiInput := preload("res://ui/ui_input.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerPrompts := preload("res://ui/controller_prompts.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")
const JetiRadio := preload("res://input/jeti_radio.gd")
const ActionAxisCapture := preload("res://input/action_axis_capture.gd")
const RadioMenu := preload("res://input/radio_menu.gd")
const ControllerDiagnostics := preload("res://input/controller_diagnostics.gd")
const InputReportData := preload("res://input/input_report_data.gd")
const ControlsWorkspace := preload("res://ui/controls/controls_workspace.gd")
const BindingChip := preload("res://ui/controls/binding_chip.gd")
const GimbalView := preload("res://ui/controls/stick_gimbal_view.gd")
const ResponseCurve := preload("res://ui/controls/response_curve.gd")
const CalibrationView := preload("res://ui/controls/calibration_view.gd")
const ControlsReference := preload("res://ui/controls_reference.gd")
const CaptureOverlay := preload("res://ui/controls/capture_overlay.gd")
const SetupAssistant := preload("res://ui/controls/setup_assistant.gd")
const SetupAssistantBridge := preload("res://ui/controls/setup_assistant_bridge.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const KeyCap := preload("res://ui/key_cap.gd")

signal close_requested
signal profile_saved(profile: Dictionary)
signal draft_changed
signal calibration_requested
signal menu_verification_requested
## UI-15-UX-06: emitted exactly once when a capture this screen owns ends. `target_id` is the action id (Remap and
## Learn axis), "aux:<channel>" (switch position Capture, Move the control), "axis:<channel>" (Detect) or "find".
## `ok` is true only when the draft binding was committed (after a Swap/Replace choice when one was needed); for
## "find" it is true when a row was found. `message` is the translated reason when `ok` is false ("" otherwise).
signal capture_finished(target_id: String, ok: bool, message: String)
## Emitted by apply_calibration_draft (ok = its result) and calibration_cancelled (ok = false).
signal calibration_finished(ok: bool, message: String)

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
const AUX_CHANNELS: Array[String] = ["smoke", "flaps", "gear", "arm", "flight_mode"]
const AUX_CHANNEL_LABELS: Dictionary = {"smoke": "Smoke", "flaps": "Flaps", "gear": "Landing gear",
	"arm": "Arm (FPV quad)", "flight_mode": "Flight mode (FPV quad)"}
const AUX_LEGACY_ARM_HINT := "This profile arms the quad from the Landing gear switch. Assign Arm to make it explicit."
## UI-15-UX-03: full-screen workspace (menu-redesign safe inset at 1080p); beyond SPAN the text column stops growing.
const WORKSPACE_INSET := 48.0
const WORKSPACE_SPAN := 2560.0
const RAIL_WIDTH := 300.0
## The device picture sits between the rail and the pages only while the pages keep the former modal's wide
## layouts (axis table, inline AUX editors: an effective canvas of 1100+ px) and their full height.
const PAGE_MIN_EFFECTIVE := 1108.0
const PAGE_MAX_WIDTH := 1400.0
const PICTURE_MIN_WIDTH := 360.0
const KEYBOARD_PAGE_MIN_WIDTH := 700.0
const KEYBOARD_READ_ONLY_NOTE := "Keyboard keys cannot be remapped yet."
## Pages that edit a controller profile; with the Keyboard selected they show its fixed map instead.
const PROFILE_SECTIONS: Array[String] = ["profile", "axes", "aux", "buttons"]
const ACTION_CONFLICT_CODES: Array[String] = ["binding_conflict", "action_aux_source_conflict",
	"action_flight_axis_conflict", "action_aux_conflict"]
## UI-15-UX-06: same-control conflicts that the capture overlay offers to Swap or Replace.
const SWAPPABLE_CONFLICT_CODES: Array[String] = ["binding_conflict", "action_aux_source_conflict", "aux_conflict"]
## Seconds a capture waits for input before it cancels itself (gamepad-only players have no Escape key).
const CAPTURE_SECONDS := 8.0
## UI-15-UX-05: the requested direction per flight channel; a detected axis that moved the other way is inverted.
const DETECT_PROMPTS: Dictionary = {
	"roll": "Move the stick you want for Roll fully RIGHT and hold it.",
	"pitch": "Move the stick you want for Pitch fully BACK (toward you) and hold it.",
	"yaw": "Move the stick you want for Yaw fully RIGHT and hold it.",
	"throttle": "Move the control you want for Throttle to FULL and hold it.",
}

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
var flap_mix_owner_picker: OptionButton
var action_grid: GridContainer
var preview_label: Label
var status_label: Label
var save_button: Button
var calibrate_button: Button
var setup_assistant_button: Button
var _assistant: CanvasLayer
var _assistant_bridge: RefCounted
var _assistant_restore: Dictionary = {}
## Devices already offered the Setup assistant in this app run (one hint per device).
static var _assistant_offered: Dictionary = {}
var choose_radio_profile_button: Button
var calibration_prerequisite: Label
var calibration_scope_help: Label
var device_lifetime_help: Label
var calibration_saves_first := false
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
var diagnostic_capabilities: Dictionary = {}

var action_filter: OptionButton
var _settings_panel: PanelContainer
var _settings_panel_style: StyleBoxFlat
var _shell: VBoxContainer
var _section_pages: Dictionary = {}
var _section_buttons: Dictionary = {}
var _section_navigation: HFlowContainer
var _section_body: VBoxContainer
var _selected_section := "devices"
var _mapping_focus_layout_pending := false
var _mapping_scroll_input_frame := -1
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
var _menu_verification_origins: Dictionary = {}
var verify_menus_button: Button
var disable_menus_button: Button
var _menu_help: Label
var _diagnostics_dialog: FileDialog
var _diagnostics_data: RefCounted
var _diagnostics_connection := ""
var _diagnostics_raw := PackedFloat64Array()
var _diagnostics_seen: Array[bool] = []
var _reused_radio_mappings: Dictionary = {} # explicit Duplicate/legacy choice, never inferred from matching axes
var _base_actions: Dictionary = {}
var _action_bindings: Dictionary = {}
var action_capabilities: Dictionary = ControllerActions.AIRPLANE_CAPABILITIES.duplicate()
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
var _axis_capture_buttons: Dictionary = {}
var _axis_capture: RefCounted
var _axis_capture_dialog: ConfirmationDialog
var _capturing_generation := 0
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
# UI-15-UX-02: full text for help and messages that are clipped to one or a few lines.
var aux_help_info_button: Button
var device_summary_info_button: Button
var status_info_button: Button
var _info_dialog: AcceptDialog
var _info_return_focus: Control
# UI-15-UX-02b: what Save last committed (or what was loaded) per draft context, and the device roles.
var unsaved_dialog: ConfirmationDialog
var _unsaved_discard_button: Button
var _unsaved_pending := false
var _unsaved_return_focus: Control
var _unsaved_marker: Label
var _clean_snapshots: Dictionary = {}
var _clean_flight_device_id := -1
var _clean_ui_device_id := -1
var _unsaved_calibration: Dictionary = {}
var _dirty_marker_queued := false
# UI-15-UX-02c: rows for other vehicles stay bound and validated, only hidden.
var show_all_vehicle_actions: CheckBox
# D6-UX-01: the same filter for the Extra channels page (ControllerActions.aux_applies).
var show_all_vehicle_aux: CheckBox
var aux_legacy_arm_hint: Label

## UI-15-UX-03/04/08: the workspace regions (device rail, device picture, pages) and the live views.
var workspace: ControlsWorkspace
var _workspace_body: HBoxContainer
var _workspace_main: BoxContainer
var _page_column: VBoxContainer
var _workspace_refresh_queued := false
var _binding_chips: Dictionary = {} # action id -> BindingChip
var _axis_gimbals: Array[GimbalView] = []
var _response_curve: ResponseCurve
var _curve_channel := "roll"
var _live_stick_mode := 2
var _axis_raw := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _axis_out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _page_editables: Dictionary = {} # section -> wrapper of the profile editors
var _keyboard_blocks: Dictionary = {} # section -> read-only keyboard view
var _keyboard_mode := false
var _keyboard_tables_vehicle := ""

## UI-15-UX-05/06: capture overlay, flight-axis detection, AUX "Move the control", search by input, conflicts, reset.
var capture_overlay: CaptureOverlay
var axis_advanced_toggle: CheckBox
var aux_advanced_toggle: CheckBox
var find_actions_button: Button
var find_aux_button: Button
var reset_category_button: Button
var reset_all_button: Button
var reset_dialog: ConfirmationDialog
var _reset_scope := -1
var _reset_return_focus: Control
var _axis_detect_buttons: Dictionary = {} # channel -> Button
var _aux_detect_buttons: Dictionary = {} # aux channel -> Button
var _axis_live_views: HFlowContainer
var _capture_target := "" # the capture_finished target of the running capture
var _detect_channel := ""
var _axis_detector: AxisDetector
var _capturing_aux_axis := "" # AUX channel measured by "Move the control" (ActionAxisCapture)
var _finding := false
## Axis values when Find control started; a resting end position is not a deliberate choice.
var _find_baseline := PackedFloat64Array()
const FIND_AXIS_MIN_TRAVEL := 0.5
var _find_origin := ""
var _conflict: Dictionary = {}
var _detect_preview_axis := -1
var _axis_capture_phase := ""


func _init() -> void:
	name = "ControllerSetup"
	layer = LAYER
	_build()
	_screen.visibility_changed.connect(_refresh_visible_preview)
	visibility_changed.connect(_refresh_visible_preview)


func _observe_popup_diagnostics(event: InputEvent) -> void:
	if not is_inside_tree(): return
	var focused := Window.get_focused_window()
	if focused != null and focused != get_tree().root and focused.visible:
		_observe_diagnostics(event)


## The owner injects shared objects before adding this CanvasLayer to the tree.
## Controller choices and profile edits stay draft until one Save operation succeeds.
func configure(controller_registry: Object, store: Object, flight_device_id := -1, ui_device_id := -1,
		capabilities: Dictionary = ControllerActions.AIRPLANE_CAPABILITIES) -> void:
	action_capabilities = capabilities.duplicate()
	registry = controller_registry
	profile_store = store
	_draft_flight_device_id = flight_device_id if flight_device_id >= 0 else _registry_selected("flight")
	_draft_ui_device_id = ui_device_id if ui_device_id >= 0 else _registry_selected("ui")
	_load_profiles()
	_refresh_devices()
	_load_profile_for_device(_draft_flight_device_id)
	_connect_registry()
	_clean_flight_device_id = _draft_flight_device_id
	_clean_ui_device_id = _draft_ui_device_id
	_queue_dirty_marker()


## Parent-facing surface API used by the screen stack and the active flight owner: Close, Escape and Back.
## An open popover or unsaved-changes question is answered first ("Keep editing"), then an active capture is
## cancelled; a dirty draft asks Save / Discard / Keep editing before it closes.
func request_close() -> void:
	if is_instance_valid(_assistant):
		# Back while the Setup assistant is open steps it back (its first step cancels it); capture keeps priority.
		if _is_assignment_busy():
			_cancel_capture()
		elif not _assistant.is_busy():
			_assistant.go_back()
		return
	if _dismiss_own_dialogs():
		return
	if _is_assignment_busy():
		_cancel_capture()
		return
	if is_inside_tree() and has_unsaved_changes():
		_ask_unsaved_changes()
		return
	close_without_prompt()


## Closes now and discards the draft, without asking. For the explicit Cancel and Discard choices and for
## owners that must close programmatically (device loss, hand-offs); nothing is saved.
func close_without_prompt() -> void:
	_hide_unsaved_dialog()
	if is_instance_valid(_info_dialog) and _info_dialog.visible:
		_info_dialog.hide()
	if is_instance_valid(reset_dialog) and reset_dialog.visible:
		reset_dialog.hide()
	if _is_assignment_busy():
		_capture_done(false, tr("Remapping cancelled."))
	_reset_validation()
	close_requested.emit()


func _cancel_edits() -> void:
	close_without_prompt()


## UI-15-UX-02b: the draft differs from what was loaded or last saved: profile fields, device roles, the menu
## preference, or a calibration applied to the draft (even one that measured the same ranges).
func has_unsaved_changes() -> bool:
	if _draft_profile.is_empty():
		return false
	if _draft_flight_device_id != _clean_flight_device_id or _draft_ui_device_id != _clean_ui_device_id:
		return true
	if _unsaved_calibration.has(_draft_context_key) or not _clean_snapshots.has(_draft_context_key):
		return true
	return _clean_snapshots[_draft_context_key] != _dirty_fingerprint()


## What Save would commit, without the device association (that follows the device role, tracked separately).
func _dirty_fingerprint() -> Dictionary:
	if _draft_profile.is_empty():
		return {}
	var candidate := _profile_candidate()
	candidate.erase("association")
	return candidate


func _mark_clean() -> void:
	if not _draft_profile.is_empty():
		_clean_snapshots[_draft_context_key] = _dirty_fingerprint()
	_unsaved_calibration.erase(_draft_context_key)
	_clean_flight_device_id = _draft_flight_device_id
	_clean_ui_device_id = _draft_ui_device_id
	_queue_dirty_marker()


func _queue_dirty_marker() -> void:
	if _dirty_marker_queued:
		return
	_dirty_marker_queued = true
	_refresh_dirty_marker.call_deferred()


## "Controls •" and a worded "Unsaved changes" beside Save, never colour alone.
func _refresh_dirty_marker() -> void:
	_dirty_marker_queued = false
	if _settings_title == null or _unsaved_marker == null:
		return
	var dirty := has_unsaved_changes()
	_settings_title.text = tr("Controls") + " •" if dirty else "Controls"
	_settings_title.tooltip_text = _settings_title.text
	_unsaved_marker.text = tr("Unsaved changes")
	_unsaved_marker.visible = dirty
	save_button.accessibility_description = tr("Unsaved changes") if dirty else ""


func _ask_unsaved_changes() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_unsaved_return_focus = focused if focused != null and _screen.is_ancestor_of(focused) else null
	if unsaved_dialog == null:
		unsaved_dialog = ConfirmationDialog.new()
		unsaved_dialog.name = "UnsavedControlsDialog"
		unsaved_dialog.dialog_autowrap = true
		unsaved_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_unsaved_discard_button = unsaved_dialog.add_button("Discard", true, "discard")
		_unsaved_discard_button.name = "DiscardControls"
		unsaved_dialog.confirmed.connect(_on_unsaved_choice.bind("save"))
		unsaved_dialog.canceled.connect(_on_unsaved_choice.bind("keep"))
		unsaved_dialog.custom_action.connect(func(action: StringName) -> void:
			if action != &"discard": return
			# Hiding may emit `canceled`; that is not the player's answer.
			var waiting := _unsaved_pending
			_unsaved_pending = false
			unsaved_dialog.hide()
			_unsaved_pending = waiting
			_on_unsaved_choice("discard"))
		add_child(unsaved_dialog)
	unsaved_dialog.title = tr("Unsaved changes")
	unsaved_dialog.dialog_text = tr("Your controller changes are not saved. Save them, discard them, or keep editing.")
	unsaved_dialog.get_ok_button().text = tr("Save")
	unsaved_dialog.get_ok_button().name = "SaveControls"
	unsaved_dialog.get_cancel_button().text = tr("Keep editing")
	unsaved_dialog.get_cancel_button().name = "KeepEditingControls"
	_unsaved_discard_button.text = tr("Discard")
	_unsaved_pending = true
	unsaved_dialog.popup_centered_clamped(Vector2i(620, 200), 0.9)
	_focus_if_shown.call_deferred(unsaved_dialog.get_ok_button())


## Save goes through the transactional Save and closes only on success; Discard closes like Cancel;
## Keep editing (also Escape in the question, a window close or a second Back) restores focus.
func _on_unsaved_choice(choice: String) -> void:
	if not _unsaved_pending:
		return
	_unsaved_pending = false
	match choice:
		"save":
			if not _save_profile(true):
				_restore_unsaved_focus.call_deferred(true)
		"discard":
			close_without_prompt()
		_:
			_restore_unsaved_focus.call_deferred(false)


func _restore_unsaved_focus(only_if_lost: bool) -> void:
	if not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if only_if_lost and focused != null and focused.is_visible_in_tree():
		return
	var target := _unsaved_return_focus
	_unsaved_return_focus = null
	if not is_instance_valid(target) or not target.is_visible_in_tree() or target.focus_mode == Control.FOCUS_NONE \
			or (target is BaseButton and target.disabled):
		target = save_button
	target.grab_focus()


func _hide_unsaved_dialog() -> void:
	_unsaved_pending = false
	if is_instance_valid(unsaved_dialog) and unsaved_dialog.visible:
		unsaved_dialog.hide()


## A Back/Escape routed to this screen while one of its own questions is open answers that question.
func _dismiss_own_dialogs() -> bool:
	if is_instance_valid(unsaved_dialog) and unsaved_dialog.visible:
		var waiting := _unsaved_pending
		_unsaved_pending = false
		unsaved_dialog.hide()
		_unsaved_pending = waiting
		_on_unsaved_choice("keep")
		return true
	if is_instance_valid(_info_dialog) and _info_dialog.visible:
		_info_dialog.hide()
		_restore_info_focus()
		return true
	# UI-15-UX-06: Back/Escape answers the conflict question with Cancel and closes the reset question.
	if not _conflict.is_empty():
		_resolve_conflict("cancel")
		return true
	if is_instance_valid(reset_dialog) and reset_dialog.visible:
		reset_dialog.hide()
		_restore_reset_focus()
		return true
	return false


func current_profile() -> Dictionary:
	return _draft_profile.duplicate(true)


## A preflight wizard never saves or changes selection. Keep edits outside its four channels intact.
func apply_calibration_draft(calibration: Dictionary, device_id: int, generation: int, warning: String = "") -> bool:
	if _draft_flight_device_id != device_id or _draft_profile.get("kind", "") != "radio" \
		or not _calibration_connection_matches(device_id, generation):
		_set_status(tr("The radio connection changed. Calibrate again before saving these settings."), true)
		calibration_finished.emit(false, tr("The radio connection changed. Calibrate again before saving these settings."))
		return false
	var calibrated: Dictionary = ControllerProfile.merge_radio_calibration(_draft_profile, calibration)
	if calibrated.is_empty() or calibrated.get("kind", "") != "radio":
		_set_status(tr("Invalid calibration. The draft is unchanged."), true)
		calibration_finished.emit(false, tr("Invalid calibration. The draft is unchanged."))
		return false
	_draft_profile = calibrated
	# The wizard retains valid AUX and reports bindings consumed by newly assigned flight axes.
	_draft_profile["aux"] = calibrated.get("aux", {}).duplicate(true)
	_calibration_origins[_draft_context_key] = {"id": device_id, "generation": generation,
		"mapping": _radio_mapping(_draft_profile)}
	_unsaved_calibration[_draft_context_key] = true
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
	calibration_finished.emit(true, tr(warning) if not warning.is_empty() else "")
	return true


## The calibration owner reports a cancelled or abandoned calibration: the draft is unchanged.
func calibration_cancelled(reason: String) -> void:
	_set_status(reason, false)
	calibration_finished.emit(false, reason)


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


func apply_menu_verification(profile: Dictionary, device_id: int, generation: int) -> bool:
	if str(profile.get("profile_id", "")) != str(_draft_profile.get("profile_id", "")) \
		or _draft_flight_device_id != device_id or not _calibration_connection_matches(device_id, generation) \
		or not RadioMenu.is_verified(profile) or RadioMenu.mapping_fingerprint(profile) != RadioMenu.mapping_fingerprint(_profile_candidate()) \
		or RadioMenu.action_fingerprint(profile) != RadioMenu.action_fingerprint(_profile_candidate()):
		_set_status(tr("Menu verification no longer matches this radio. Verify again; the draft is unchanged."), true)
		return false
	_draft_profile = profile.duplicate(true)
	_draft_profile = _associate_candidate(_draft_profile)
	_invalidate_menu_evidence()
	_menu_verification_origins[str(profile.profile_id)] = {"id": device_id, "generation": generation,
		"mapping": RadioMenu.mapping_fingerprint(profile), "actions": RadioMenu.action_fingerprint(profile)}
	_draft_ui_device_id = device_id
	_refresh_devices()
	_update_menu_controls()
	_remember_current_draft()
	_set_status(tr("Radio menu controls are verified in the draft. Save to use this radio for menus."), false)
	draft_changed.emit()
	return true


func menu_verification_lease(profile: Dictionary) -> Dictionary:
	var origin: Dictionary = _menu_verification_origins.get(str(profile.get("profile_id", "")), {})
	if origin.is_empty() or int(origin.id) != _draft_flight_device_id or not _calibration_connection_matches(int(origin.id), int(origin.generation)) \
		or origin.mapping != RadioMenu.mapping_fingerprint(profile) or origin.actions != RadioMenu.action_fingerprint(profile): return {}
	return origin.duplicate(true)


## Only a challenge completed on this connection permits a current-sample handoff.
func menu_seed_samples(profile: Dictionary) -> Dictionary:
	var lease := menu_verification_lease(profile)
	if lease.is_empty(): return {}
	var axes := PackedFloat64Array()
	for axis: int in RadioMenu.AXES:
		var value: Variant = axis_preview_provider.call(int(lease.id), axis) if axis_preview_provider.is_valid() \
			else Input.get_joy_axis(int(lease.id), axis)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or absf(float(value)) > 1.0: return {}
		axes.append(float(value))
	var buttons := {}
	for action: String in RadioMenu.COMMANDS:
		var binding: Dictionary = profile.actions[action]
		if binding.type != "button": continue
		var value: Variant = button_preview_provider.call(int(lease.id), int(binding.button)) if button_preview_provider.is_valid() \
			else Input.is_joy_button_pressed(int(lease.id), int(binding.button))
		if typeof(value) != TYPE_BOOL: return {}
		buttons[int(binding.button)] = value
	return {"axes": axes, "buttons": buttons, "lease": lease}


static func _radio_mapping(profile: Dictionary) -> Dictionary:
	var result := {}
	for channel_name: String in CHANNELS:
		var channel: Dictionary = profile.get(channel_name, {})
		var measured := {}
		for key: String in ["axis", "invert", "min", "center", "max"]:
			measured[key] = channel.get(key)
		result[channel_name] = measured
	return result


## Existing saved/imported mappings retain compatibility; a new starter needs
## current calibration evidence. A duplicate UUID or a name is not that evidence.
func radio_mapping_verified(candidate: Dictionary) -> bool:
	var observed := _device_for_id(_draft_flight_device_id)
	if candidate.get("kind", "") != "radio" and observed.get("kind", "") != "radio": return true
	var mapping := _radio_mapping(candidate)
	var origin: Dictionary = _calibration_origins.get(_draft_context_key, {})
	if not origin.is_empty():
		return _calibration_connection_matches(int(origin.id), int(origin.generation)) \
			and origin.get("mapping", {}) == mapping
	for saved: Dictionary in _profiles:
		if str(saved.get("profile_id", "")) == str(candidate.get("profile_id", "")) and _radio_mapping(saved) == mapping:
			return true
	var reused: Dictionary = _reused_radio_mappings.get(str(candidate.get("profile_id", "")), {})
	if not reused.is_empty():
		return reused.mapping == mapping and reused.id == _draft_flight_device_id \
			and _calibration_connection_matches(int(reused.id), int(reused.generation))
	return false


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
	# The one-line device summary keeps its full text (and JETI metadata) one focus stop away, in the header.
	device_summary_info_button = _info_button("DeviceSummaryInfo", "Controller details")
	device_summary_info_button.pressed.connect(func() -> void:
		_show_info(tr("Controller details"), _device_summary.tooltip_text if not _device_summary.tooltip_text.is_empty() else _device_summary.text, device_summary_info_button))
	header.add_child(device_summary_info_button)
	header.move_child(device_summary_info_button, close_button.get_index())
	_device_details_label = _label("", "SecondaryLabel", true)
	_device_details_label.name = "ControllerDeviceDetails"
	_device_details_label.visible = false
	_device_details_label.max_lines_visible = 2
	_device_details_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shell.add_child(_device_details_label)
	# UI-15-UX-03: [device rail | [device picture, section tabs + page]]; the picture moves beside the pages on wide
	# canvases and the rail and picture fold away on compact ones (see _resize_panel).
	workspace = ControlsWorkspace.new()
	add_child(workspace)
	workspace.read_axis = _read_axis_preview
	workspace.read_button = _read_button_preview
	workspace.host_visible = func() -> bool: return visible and _screen.is_visible_in_tree()
	workspace.card_activated.connect(_on_rail_card_activated)
	_workspace_body = HBoxContainer.new()
	_workspace_body.name = "ControlsWorkspaceBody"
	_workspace_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_body.add_theme_constant_override("separation", 16)
	shell.add_child(_workspace_body)
	workspace.rail.custom_minimum_size.x = RAIL_WIDTH
	_workspace_body.add_child(workspace.rail)
	_workspace_main = BoxContainer.new()
	_workspace_main.name = "ControlsWorkspaceMain"
	_workspace_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_main.add_theme_constant_override("separation", 12)
	_workspace_body.add_child(_workspace_main)
	_workspace_main.add_child(workspace.picture_panel)
	_page_column = VBoxContainer.new()
	_page_column.name = "ControllerPageColumn"
	_page_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_column.add_theme_constant_override("separation", 12)
	_workspace_main.add_child(_page_column)
	_section_navigation = HFlowContainer.new()
	_section_navigation.name = "ControllerSections"
	_section_navigation.add_theme_constant_override("separation", 6)
	_section_navigation.add_theme_constant_override("h_separation", 6)
	_section_navigation.add_theme_constant_override("v_separation", 6)
	_page_column.add_child(_section_navigation)
	_page_column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.name = "ControllerSetupScroll"
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.resized.connect(_queue_mapping_focus_visibility)
	scroll.get_v_scroll_bar().gui_input.connect(_on_mapping_scroll_input)
	_page_column.add_child(scroll)
	_section_body = VBoxContainer.new()
	_section_body.name = "ControllerSetupPage"
	_section_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_section_body)
	_section_body.resized.connect(_queue_mapping_focus_visibility)
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
	page.add_child(_label("Use a gamepad or a verified radio for menus. Keyboard and mouse are always available.", "SecondaryLabel", true))
	device_lifetime_help = _label("Saved profiles and eligible menu preferences persist. Flight device selections apply for this app session.", "SecondaryLabel", true)
	device_lifetime_help.name = "ControllerDeviceLifetime"
	page.add_child(device_lifetime_help)

	var role_actions := HFlowContainer.new()
	role_actions.add_theme_constant_override("separation", 8)
	role_actions.add_theme_constant_override("h_separation", 8)
	role_actions.add_theme_constant_override("v_separation", 8)
	legacy_import_button = _button("Recover legacy profile…")
	legacy_import_button.pressed.connect(_import_legacy_profiles)
	role_actions.add_child(legacy_import_button)
	var navigation_actions := HFlowContainer.new()
	navigation_actions.add_theme_constant_override("h_separation", 8)
	navigation_actions.add_theme_constant_override("v_separation", 8)
	var export_button := _button("Export diagnostics…", "", "ExportControllerDiagnostics")
	export_button.pressed.connect(_open_diagnostics_export)
	export_button.tooltip_text = tr("Export the current draft and input observed on this screen. Device identifiers are redacted.")
	navigation_actions.add_child(export_button)
	verify_menus_button = _button("Verify radio menus…", "", "VerifyRadioMenus")
	verify_menus_button.pressed.connect(func() -> void: menu_verification_requested.emit())
	navigation_actions.add_child(verify_menus_button)
	disable_menus_button = _button("Disable radio menus", "", "DisableRadioMenus")
	disable_menus_button.pressed.connect(_disable_radio_menus)
	navigation_actions.add_child(disable_menus_button)
	_menu_help = _label("", "SecondaryLabel", true)
	calibrate_button = _button("Calibrate selected radio")
	calibrate_button.name = "CalibrateSelectedRadio"
	calibrate_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	calibrate_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	calibrate_button.visible = false
	calibrate_button.disabled = true
	calibrate_button.pressed.connect(func() -> void: calibration_requested.emit())
	calibrate_button.focus_entered.connect(_queue_mapping_focus_visibility)
	setup_assistant_button = _button("Set up this device…", "PrimaryButton", "SetupAssistantButton")
	setup_assistant_button.tooltip_text = tr("Step by step: controller type, stick mode, calibration, a live test and the main switches.")
	setup_assistant_button.visible = false
	setup_assistant_button.pressed.connect(func() -> void: open_setup_assistant())
	setup_assistant_button.focus_entered.connect(_queue_mapping_focus_visibility)
	page.add_child(setup_assistant_button)
	page.add_child(role_actions)
	page.add_child(calibrate_button)
	calibration_prerequisite = _label("Using an RC transmitter? Choose a radio profile before calibrating.", "SecondaryLabel", true)
	calibration_prerequisite.name = "RadioCalibrationPrerequisite"
	calibration_prerequisite.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	calibration_prerequisite.visible = false
	page.add_child(calibration_prerequisite)
	choose_radio_profile_button = _button("Choose radio profile", "", "ChooseRadioProfile")
	choose_radio_profile_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choose_radio_profile_button.visible = false
	choose_radio_profile_button.pressed.connect(_choose_radio_profile)
	page.add_child(choose_radio_profile_button)
	calibration_scope_help = _label("", "SecondaryLabel", true)
	calibration_scope_help.name = "CalibrationScopeHelp"
	calibration_scope_help.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	calibration_scope_help.visible = false
	page.add_child(calibration_scope_help)
	page.add_child(navigation_actions)
	page.add_child(_menu_help)
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
	axis_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	axis_grid.add_theme_constant_override("h_separation", 14)
	axis_grid.add_theme_constant_override("v_separation", 5)
	axis_grid.visible = false
	# UI-15-UX-05: the table column holds the table (or its compact form) and, under it, the Advanced disclosure for
	# the axis numbers; it is shorter than the live preview beside it, so the page gains no height.
	var table_column := VBoxContainer.new()
	table_column.name = "AxisTableColumn"
	table_column.add_theme_constant_override("separation", 8)
	axis_columns.add_child(table_column)
	table_column.add_child(axis_grid)
	for heading in ["Channel", "Source axis", "Deadzone", "Expo", "Invert"]:
		axis_grid.add_child(_label(heading, "SectionLabel"))
	_axis_compact_grid = VBoxContainer.new()
	_axis_compact_grid.name = "AxisMappingCompact"
	_axis_compact_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_axis_compact_grid.add_theme_constant_override("separation", 8)
	table_column.add_child(_axis_compact_grid)
	# Axes are assigned by moving them (Detect); typing an axis number is the Advanced route.
	axis_advanced_toggle = CheckBox.new()
	axis_advanced_toggle.name = "AxisAdvancedToggle"
	axis_advanced_toggle.text = "Advanced: edit axis numbers"
	axis_advanced_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	axis_advanced_toggle.toggled.connect(func(_on: bool) -> void: _apply_advanced_visibility())
	table_column.add_child(axis_advanced_toggle)
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
		row_label.custom_minimum_size.x = 140.0
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
		var source_cell := HBoxContainer.new()
		source_cell.name = "AxisSource_%s" % channel
		source_cell.add_theme_constant_override("separation", 6)
		# The mapped axis number is in the live preview beside the table ("Axis 2"); its SpinBox is Advanced.
		axis_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		source_cell.add_child(axis_spin)
		var detect_button := _button("Detect", "", "AxisDetect_%s" % channel)
		detect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		detect_button.pressed.connect(_start_axis_detect.bind(channel, detect_button))
		_axis_detect_buttons[channel] = detect_button
		source_cell.add_child(detect_button)
		_add_control_field(channel_fields, "Source axis", source_cell)
		_add_control_field(channel_fields, "Deadzone", deadzone_spin)
		_add_control_field(channel_fields, "Expo", expo_spin)
		_add_control_field(channel_fields, "Direction", invert)
		_axis_controls[channel] = {"axis": axis_spin, "deadzone": deadzone_spin, "expo": expo_spin, "invert": invert,
			"source": source_cell}
		for key: String in ["axis", "deadzone", "expo", "invert"]:
			_register_validation_field(channel + "." + key, "axes", _axis_controls[channel][key], [row_label, compact_label], str(CHANNEL_LABELS[channel]))
		axis_spin.value_changed.connect(_on_axis_changed.bind(channel, "axis"))
		deadzone_spin.value_changed.connect(_on_axis_changed.bind(channel, "deadzone"))
		expo_spin.value_changed.connect(_on_axis_changed.bind(channel, "expo"))
		invert.toggled.connect(_on_axis_invert.bind(channel))

	page = _make_section("aux", "Extra channels")
	# UI-15-UX-05/06: Advanced (axis numbers and endpoints) and Find control sit on the heading line.
	var aux_heading := HFlowContainer.new()
	aux_heading.name = "AuxiliaryHeadingRow"
	aux_heading.add_theme_constant_override("h_separation", 8)
	aux_heading.add_theme_constant_override("v_separation", 6)
	var aux_title := _section_label("AUXILIARY CHANNELS")
	aux_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aux_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	aux_heading.add_child(aux_title)
	page.add_child(aux_heading)
	aux_help_label = _label("Optional Smoke, Flaps and Landing gear inputs can use axes or buttons. Availability depends on the selected aircraft. Axis endpoints need at least 0.5 travel.", "SecondaryLabel", true)
	aux_help_label.name = "AuxiliaryHelp"
	aux_help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var aux_help_row := HBoxContainer.new()
	aux_help_row.name = "AuxiliaryHelpRow"
	aux_help_row.add_theme_constant_override("separation", 8)
	aux_help_row.add_child(aux_help_label)
	aux_help_info_button = _info_button("AuxiliaryHelpInfo", "Extra channels help")
	aux_help_info_button.visible = false
	aux_help_info_button.pressed.connect(func() -> void:
		_show_info(tr("Extra channels"), tr(aux_help_label.text), aux_help_info_button))
	aux_help_row.add_child(aux_help_info_button)
	# D6-UX-01: beside the help text, so the page gains no row (the 1280x720 AUX editors must still fit).
	show_all_vehicle_aux = CheckBox.new()
	show_all_vehicle_aux.name = "ShowAllVehicleAuxChannels"
	# Short visible text keeps this row from widening the page in long languages at large text sizes; the full
	# meaning is the tooltip and the accessible name (refreshed in _update_accessible_names).
	show_all_vehicle_aux.text = "All vehicles"
	show_all_vehicle_aux.set_meta("accessible_caption", "Show channels for all vehicles")
	show_all_vehicle_aux.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	show_all_vehicle_aux.toggled.connect(func(_pressed: bool) -> void: _update_aux_controls())
	aux_help_row.add_child(show_all_vehicle_aux)
	aux_advanced_toggle = CheckBox.new()
	aux_advanced_toggle.name = "AuxAdvancedToggle"
	aux_advanced_toggle.text = "Advanced"
	aux_advanced_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	aux_advanced_toggle.toggled.connect(func(_on: bool) -> void: _apply_advanced_visibility())
	aux_heading.add_child(aux_advanced_toggle)
	find_aux_button = _button("Find control", "", "FindControlAux")
	find_aux_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	find_aux_button.pressed.connect(func() -> void: _start_find(find_aux_button))
	aux_heading.add_child(find_aux_button)
	page.add_child(aux_help_row)
	aux_grid = VBoxContainer.new()
	aux_grid.sort_children.connect(_queue_mapping_focus_visibility)
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
		# UI-15-UX-05: measure OFF then ON by moving the control; the numbers are the page's Advanced disclosure.
		var aux_detect := _button("Move the control", "", "AuxDetect_%s" % aux_name)
		aux_detect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		aux_detect.pressed.connect(_start_aux_axis_capture.bind(aux_name, aux_detect))
		_aux_detect_buttons[aux_name] = aux_detect
		axis_editor.add_child(aux_detect)
		var aux_axis_field := _add_inline_control_field(axis_editor, "Axis", axis_spin)
		var aux_off_field := _add_inline_control_field(axis_editor, "Off endpoint", off_spin)
		var aux_on_field := _add_inline_control_field(axis_editor, "On endpoint", on_spin)
		_aux_inline_fields.append_array([aux_axis_field, aux_off_field, aux_on_field])
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
		if aux_name == "flaps":
			flap_mix_owner_picker = _option("Flap-to-elevator compensation")
			flap_mix_owner_picker.name = "FlapElevatorMixOwner"
			flap_mix_owner_picker.add_item(tr("Simulator"), 0)
			flap_mix_owner_picker.add_item(tr("Transmitter"), 1)
			flap_mix_owner_picker.item_selected.connect(_on_flap_mix_owner_selected)
			var mix_label := _add_control_field(channel_block, "Flap-to-elevator compensation", flap_mix_owner_picker)
			_register_validation_field("flap_elevator_mix_owner", "aux", flap_mix_owner_picker, [mix_label], "Flap-to-elevator compensation")
			var mix_help := _label("Simulator compensation follows actual flap position. Choose Transmitter when your radio already adds flap-to-elevator compensation; the simulator will not add its own.", "SecondaryLabel", true)
			mix_help.name = "FlapElevatorMixHelp"
			channel_block.add_child(mix_help)
		if aux_name == "arm":
			aux_legacy_arm_hint = _label(AUX_LEGACY_ARM_HINT, "SecondaryLabel", true)
			aux_legacy_arm_hint.name = "AuxLegacyArmHint"
			aux_legacy_arm_hint.visible = false
			channel_block.add_child(aux_legacy_arm_hint)
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
			"detect": aux_detect,
			"advanced_fields": [aux_axis_field, aux_off_field, aux_on_field],
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
	# Keep the flap compensation explanation with its channel without pushing a
	# following channel editor below the compact viewport.
	aux_grid.move_child(_aux_controls.gear.row.get_parent(), _aux_controls.flaps.row.get_parent().get_index())

	page = _section_pages["axes"]
	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.add_theme_constant_override("separation", 5)
	axis_columns.add_child(preview_column)
	preview_column.add_child(_section_label("LIVE PREVIEW"))
	# UI-15-UX-04/08: two gimbals in the profile's stick mode and the focused channel's response curve, fed by the
	# same four samples as the value rows (no extra reads), only while this tab is shown.
	var live_views := HFlowContainer.new()
	_axis_live_views = live_views
	live_views.name = "AxisLiveViews"
	live_views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_views.add_theme_constant_override("h_separation", 24)
	live_views.add_theme_constant_override("v_separation", 8)
	# Below the table and its value rows, across the page, so the values keep their place at compact sizes.
	page.add_child(live_views)
	for side in 2:
		var gimbal := GimbalView.new()
		gimbal.name = "AxisGimbalLeft" if side == 0 else "AxisGimbalRight"
		gimbal.side = 150.0
		gimbal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		live_views.add_child(gimbal)
		_axis_gimbals.append(gimbal)
	_response_curve = ResponseCurve.new()
	_response_curve.name = "AxisResponseCurve"
	_response_curve.custom_minimum_size = Vector2(300.0, 270.0)
	_response_curve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_response_curve.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# UI-15-UX-05: shown large in the picture panel when that panel is visible (see _place_response_curve).
	live_views.add_child(_response_curve)
	_preview_grid = GridContainer.new()
	_preview_grid.name = "AxisLivePreview"
	_preview_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_grid.columns = 1
	_preview_grid.add_theme_constant_override("h_separation", 12)
	_preview_grid.add_theme_constant_override("v_separation", 4)
	preview_column.add_child(_preview_grid)
	for channel in CHANNELS:
		var live_row := VBoxContainer.new()
		live_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		live_row.add_theme_constant_override("separation", 3)
		_preview_grid.add_child(live_row)
		var current := _label("%s · — → —" % tr(str(CHANNEL_LABELS[channel])), "SecondaryLabel", false)
		current.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		current.autowrap_mode = TextServer.AUTOWRAP_OFF
		current.custom_minimum_size.y = 22.0
		live_row.add_child(current)
		var meter_row := HBoxContainer.new()
		live_row.add_child(meter_row)
		var meter := ProgressBar.new()
		# Superseded by the gimbals; kept (hidden) because tests read its conditioned value.
		meter.visible = false
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
	preview_label =_label("Select a flight controller to preview mapped channels.", "SecondaryLabel", true)
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
	show_all_vehicle_actions = CheckBox.new()
	show_all_vehicle_actions.name = "ShowAllVehicleActions"
	show_all_vehicle_actions.text = "Show actions for all vehicles"
	show_all_vehicle_actions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	show_all_vehicle_actions.toggled.connect(_on_show_all_vehicle_actions)
	page.add_child(show_all_vehicle_actions)
	# UI-15-UX-06: search by input and reset to defaults (draft only, confirmed first).
	var tools := HFlowContainer.new()
	tools.name = "ActionTools"
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 8)
	find_actions_button = _button("Find control", "", "FindControlActions")
	find_actions_button.pressed.connect(func() -> void: _start_find(find_actions_button))
	tools.add_child(find_actions_button)
	reset_category_button = _button("Reset category", "", "ResetActionsCategory")
	reset_category_button.pressed.connect(func() -> void: _ask_reset_actions(action_filter.selected, reset_category_button))
	tools.add_child(reset_category_button)
	reset_all_button = _button("Reset all actions", "", "ResetActionsAll")
	reset_all_button.pressed.connect(func() -> void: _ask_reset_actions(0, reset_all_button))
	tools.add_child(reset_all_button)
	page.add_child(tools)
	page.add_child(_label("Bindings are saved by physical control. A different device cannot trigger them.", "SecondaryLabel", true))
	page.add_child(_label("Gamepads: B/Circle controls retractable gear and RB/R1 controls an installed smoke pump automatically. Flap actions depend on the selected aircraft. Existing assignments take priority; remap other joysticks to choose their buttons.", "SecondaryLabel", true))
	action_grid = GridContainer.new()
	action_grid.sort_children.connect(_queue_mapping_focus_visibility)
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
		# UI-15-UX-04: the binding is a chip (glyph or physical label, conflict badge, live-press glow). The former
		# glyph and text nodes stay hidden with their names and contents for existing callers and tests.
		var chip := BindingChip.new()
		chip.name = "BindingChip_%s" % action_id
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		binding_cell.add_child(chip)
		_binding_chips[action_id] = chip
		var binding_glyph := TextureRect.new()
		binding_glyph.name = "BindingGlyph_%s" % action_id
		binding_glyph.custom_minimum_size = Vector2(28.0, 28.0)
		binding_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		binding_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		binding_glyph.visible = false
		binding_cell.add_child(binding_glyph)
		var binding_label := _label("Unbound", "SecondaryLabel")
		binding_label.name = "Binding_%s" % action_id
		binding_label.visible = false
		binding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_label.custom_minimum_size.x = 0.0
		binding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		binding_cell.add_child(binding_label)
		var binding_spacer := Control.new()
		binding_spacer.name = "BindingSpacer_%s" % action_id
		binding_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		binding_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_cell.add_child(binding_spacer)
		var clear_button := _button("Clear")
		clear_button.name = "Clear_%s" % action_id
		clear_button.pressed.connect(_clear_action_binding.bind(action_id))
		binding_cell.add_child(clear_button)
		_clear_action_buttons[action_id] = clear_button
		var axis_button := _button("Learn axis")
		axis_button.name = "LearnAxis_%s" % action_id
		axis_button.pressed.connect(_start_axis_capture.bind(action_id, axis_button))
		binding_cell.add_child(axis_button)
		_axis_capture_buttons[action_id] = axis_button
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
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.resized.connect(_update_status_info_button)
	var status_row := HBoxContainer.new()
	status_row.name = "ControllerStatusRow"
	status_row.add_theme_constant_override("separation", 8)
	status_row.add_child(status_label)
	status_info_button = _info_button("StatusInfo", "Full message")
	status_info_button.visible = false
	status_info_button.pressed.connect(func() -> void:
		_show_info(tr("Full message"), status_label.text, status_info_button))
	status_row.add_child(status_info_button)
	status_row.visible = false
	shell.add_child(status_row)
	var footer := HBoxContainer.new()
	footer.name = "ControllerSetupFooter"
	footer.add_theme_constant_override("separation", 8)
	footer.alignment = BoxContainer.ALIGNMENT_END
	_unsaved_marker = _label("Unsaved changes", "SecondaryLabel")
	_unsaved_marker.name = "UnsavedChangesMarker"
	_unsaved_marker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_unsaved_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_unsaved_marker.visible = false
	footer.add_child(_unsaved_marker)
	var cancel_button := _button("Cancel", "", "Cancel")
	cancel_button.pressed.connect(_cancel_edits)
	footer.add_child(cancel_button)
	save_button = _button("Save", "PrimaryButton", "SaveProfile")
	save_button.pressed.connect(_save_profile)
	footer.add_child(save_button)
	shell.add_child(footer)
	capture_overlay = CaptureOverlay.new()
	capture_overlay.set_process(false)
	capture_overlay.cancel_pressed.connect(_cancel_capture)
	capture_overlay.timed_out.connect(_on_capture_timeout)
	capture_overlay.choice_made.connect(_resolve_conflict)
	capture_overlay.confirm_pressed.connect(func() -> void:
		if is_instance_valid(_axis_capture_dialog) and _axis_capture == null:
			_axis_capture_dialog.confirmed.emit())
	_settings_panel.add_child(capture_overlay)
	_build_keyboard_views()
	_tag_workspace_rows()
	_apply_advanced_visibility()
	draft_changed.connect(_queue_workspace_refresh)
	_update_accessible_names()
	select_section("devices")
	_screen.resized.connect(_resize_panel)
	_screen.theme_changed.connect(_resize_panel)
	_resize_panel()


func _resize_panel() -> void:
	if not is_instance_valid(_settings_panel) or not is_instance_valid(_screen):
		return
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var scale := maxf(0.5, ScreenTheme.text_scale)
	var screen_size := _screen.size
	var effective_screen := screen_size / scale
	var compact_height := effective_screen.y < 760.0
	# UI-15-UX-03: a full-screen workspace with the 48 px safe inset from 1080p up (20 px on smaller canvases, as
	# before); past WORKSPACE_SPAN the rail and picture grow instead of the text column.
	var inset := WORKSPACE_INSET if screen_size.x >= 1600.0 and screen_size.y >= 900.0 else 20.0
	var panel_size := Vector2(minf(WORKSPACE_SPAN * maxf(1.0, scale), maxf(0.0, screen_size.x - inset * 2.0)),
		maxf(0.0, screen_size.y - inset * 2.0))
	_settings_panel.custom_minimum_size = panel_size
	_shell.add_theme_constant_override("separation", 6 if compact_height else 12)
	_page_column.add_theme_constant_override("separation", 6 if compact_height else 12)
	_settings_panel_style.content_margin_left = 16.0 if screen_size.x < 1100.0 else 24.0
	_settings_panel_style.content_margin_right = _settings_panel_style.content_margin_left
	_settings_panel_style.content_margin_top = 12.0 if compact_height else 20.0
	_settings_panel_style.content_margin_bottom = _settings_panel_style.content_margin_top
	status_label.max_lines_visible = (1 if scale >= 1.5 else 2) if compact_height else 3
	_settings_title.tooltip_text = _settings_title.text
	# Three regions [rail | picture | pages] when the pages keep their wide layouts (PAGE_MIN_EFFECTIVE) and full
	# height; otherwise the rail goes first (the Devices tab has the same picker), then the picture.
	var rail_width := clampf(RAIL_WIDTH * scale, RAIL_WIDTH, 560.0)
	var inner_width := panel_size.x - _settings_panel_style.content_margin_left * 2.0
	var page_min := PAGE_MIN_EFFECTIVE * scale - 88.0
	var picture_need := PICTURE_MIN_WIDTH * scale + 12.0
	var rail_allowed := effective_screen.x >= 1500.0 and not compact_height
	var picture_allowed := effective_screen.y >= 880.0 and effective_screen.x >= 1100.0
	var show_rail := false
	var show_picture := false
	if rail_allowed and picture_allowed and inner_width - rail_width - 16.0 >= page_min + picture_need:
		show_rail = true
		show_picture = true
	elif picture_allowed and inner_width >= page_min + picture_need:
		show_picture = true
	elif rail_allowed and inner_width - rail_width - 16.0 >= page_min:
		show_rail = true
	var centre_width := inner_width - (rail_width + 16.0 if show_rail else 0.0)
	var page_width := clampf(centre_width * 0.62, page_min, PAGE_MAX_WIDTH * scale) if show_picture else centre_width
	page_width = minf(page_width, centre_width - (picture_need if show_picture else 0.0))
	if show_picture and _keyboard_mode:
		# The Keyboard's pages are short read-only tables; its wide key map gets the room instead.
		page_width = clampf(centre_width * 0.5, minf(page_width, KEYBOARD_PAGE_MIN_WIDTH * scale), page_width)
	var hiding_focus := is_instance_valid(focused) and not show_rail and workspace.rail.is_ancestor_of(focused)
	workspace.rail.visible = show_rail
	workspace.rail.custom_minimum_size.x = rail_width
	workspace.picture_panel.visible = show_picture
	_page_column.custom_minimum_size.x = page_width if show_picture else 0.0
	_page_column.size_flags_horizontal = Control.SIZE_FILL if show_picture else Control.SIZE_EXPAND_FILL
	var navigation_in_scroll := compact_height
	if navigation_in_scroll and _section_navigation.get_parent() != _section_body:
		if _section_navigation.get_parent() != null:
			_section_navigation.get_parent().remove_child(_section_navigation)
		_section_body.add_child(_section_navigation)
		_section_body.move_child(_section_navigation, 0)
	elif not navigation_in_scroll and _section_navigation.get_parent() != _page_column:
		if _section_navigation.get_parent() != null:
			_section_navigation.get_parent().remove_child(_section_navigation)
		_page_column.add_child(_section_navigation)
		_page_column.move_child(_section_navigation, 0)
	if hiding_focus and is_inside_tree():
		select_section("devices")
		flight_device_picker.grab_focus()
		focused = flight_device_picker
	# Page layouts keep their earlier thresholds, now measured on the page column: the former modal's page was
	# the canvas width minus 88 px.
	var effective_width := (page_width + 88.0) / scale
	var compact_fields := effective_width < 1280.0
	_device_roles.columns = 1 if compact_fields else 2
	_profile_fields.columns = 1 if compact_fields else 2
	aux_grid.add_theme_constant_override("separation", 2 if effective_width >= 1100.0 else 8)
	(_page_editables.get("aux", _section_pages["aux"]) as VBoxContainer).add_theme_constant_override("separation", 4 if effective_width >= 1100.0 else 10)
	if effective_width >= 1100.0:
		aux_help_label.max_lines_visible = 1
		aux_help_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		aux_help_label.tooltip_text = aux_help_label.text
	else:
		aux_help_label.max_lines_visible = 0
		aux_help_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		aux_help_label.tooltip_text = ""
	# UX-02: the one-line help is readable in full from a focusable button, not only a mouse tooltip.
	var help_had_focus := aux_help_info_button.has_focus()
	aux_help_info_button.visible = effective_width >= 1100.0
	if help_had_focus and not aux_help_info_button.visible and is_inside_tree():
		_aux_controls.smoke.type.grab_focus()
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
	# One preview column leaves room for a readable channel label beside the axis table.
	_preview_grid.columns = 1
	_place_response_curve()
	# Reparenting navigation or axis fields removes native focus. Keep the same
	# control through reflow; follow its final bounds after containers have settled.
	if is_instance_valid(focused) and _screen.is_ancestor_of(focused) and focused.is_visible_in_tree() \
		and get_viewport().gui_get_focus_owner() == null:
		focused.grab_focus()
	_queue_mapping_focus_visibility()


func _set_axis_grid_layout(use_table: bool) -> void:
	if use_table == _axis_layout_is_table:
		return
	_axis_layout_is_table = use_table
	axis_grid.visible = use_table
	_axis_compact_grid.visible = not use_table
	var control_keys: Array[String] = ["source", "deadzone", "expo", "invert"]
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
	active_style.border_color = ScreenTheme.FOCUS
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


func _queue_mapping_focus_visibility() -> void:
	if _mapping_scroll_input_frame == Engine.get_process_frames():
		return
	_mapping_focus_layout_pending = true


func _on_mapping_scroll_input(event: InputEvent) -> void:
	# Explicit wheel, touch or scrollbar input wins over a queued layout follow.
	if event is InputEventMouseButton or event is InputEventPanGesture \
		or event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		_mapping_scroll_input_frame = Engine.get_process_frames()
		_mapping_focus_layout_pending = false


func _keep_mapping_focus_visible() -> void:
	if not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not focused.is_visible_in_tree():
		return
	if _selected_section == "devices" and focused == calibrate_button and calibration_scope_help.is_visible_in_tree():
		var scroll := _section_body.get_parent() as ScrollContainer
		var area := scroll.get_global_rect()
		var action := calibrate_button.get_global_rect()
		var explanation := calibration_scope_help.get_global_rect()
		if explanation.end.y - action.position.y <= area.size.y:
			var shift := 0.0
			if explanation.end.y > area.end.y: shift = explanation.end.y - area.end.y
			elif action.position.y < area.position.y: shift = action.position.y - area.position.y
			if shift != 0.0: scroll.scroll_vertical += int(ceil(shift))
		else:
			scroll.ensure_control_visible(focused)
		return
	# Capture/status text can resize the viewport without changing focus.
	# Follow the current mapping control, never a stale capture target. Navigation
	# can also move into the scroll body when the available height changes.
	if (_selected_section == "buttons" and action_grid.is_ancestor_of(focused)) \
		or (_selected_section == "aux" and aux_grid.is_ancestor_of(focused)) \
		or (_selected_section == "axes" and _section_pages.axes.is_ancestor_of(focused)) \
		or (_section_navigation.get_parent() == _section_body and _section_navigation.is_ancestor_of(focused)):
		_ensure_whole_control_visible(focused)


## ScrollContainer.ensure_control_visible truncates fractional row offsets, which can leave a focused row a
## fraction of a pixel outside the viewport (for example after a longer footer message). Finish that last pixel.
func _ensure_whole_control_visible(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	var scroll := _section_body.get_parent() as ScrollContainer
	var area := scroll.get_global_rect()
	var bounds := control.get_global_rect()
	var before := scroll.scroll_vertical
	scroll.ensure_control_visible(control)
	if bounds.size.y > area.size.y:
		return
	var moved := float(scroll.scroll_vertical - before)
	var below := bounds.end.y - moved - area.end.y
	var above := area.position.y - (bounds.position.y - moved)
	if below > 0.0:
		scroll.scroll_vertical += int(ceil(below))
	elif above > 0.0:
		scroll.scroll_vertical -= int(ceil(above))


## Expose the existing radio prerequisite without choosing or saving a profile.
func update_calibration_controls(available: bool, can_choose_radio: bool, connected_nonradio: bool) -> void:
	var hiding_choice := choose_radio_profile_button.visible and not can_choose_radio and choose_radio_profile_button.has_focus()
	calibrate_button.visible = available
	calibrate_button.disabled = not available
	calibrate_button.text = tr("Save controller settings and calibrate") if calibration_saves_first else tr("Calibrate selected radio")
	calibrate_button.tooltip_text = calibrate_button.text
	calibration_prerequisite.visible = connected_nonradio
	if can_choose_radio:
		calibration_prerequisite.text = tr("Using an RC transmitter? Choose a radio profile before calibrating.")
	elif bool(_device_for_id(_draft_flight_device_id).get("known", false)) and str(_device_for_id(_draft_flight_device_id).get("kind", "")) == "gamepad":
		calibration_prerequisite.text = tr("This controller is recognized as a gamepad. Radio calibration requires a supported radio profile.")
	else:
		calibration_prerequisite.text = tr("Radio calibration requires a supported radio profile.")
	choose_radio_profile_button.visible = can_choose_radio
	calibration_scope_help.visible = available
	calibration_scope_help.text = tr("The profile is saved and device selections are applied before calibration. Cancelling keeps them.") if calibration_saves_first else tr("Calibration changes only the draft. Cancelling calibration leaves the draft unchanged; Save applies it.")
	if hiding_choice and is_inside_tree() and flight_device_picker.is_visible_in_tree():
		flight_device_picker.grab_focus()


func _choose_radio_profile() -> void:
	if not choose_radio_profile_button.visible: return
	select_section("profile")
	if profile_kind_picker.is_visible_in_tree(): profile_kind_picker.grab_focus()


## Switching sections changes presentation only; all fields share the same draft.
func select_section(section_id: String, focus_content := false) -> void:
	if not _section_pages.has(section_id):
		return
	var section_changed := section_id != _selected_section
	if section_changed and _is_assignment_busy():
		_cancel_capture()
	_selected_section = section_id
	for key in _section_pages:
		_section_pages[key].visible = key == section_id
		_section_buttons[key].set_pressed_no_signal(key == section_id)
	_place_response_curve()
	if section_changed:
		_queue_workspace_refresh()
	if section_changed:
		_refresh_visible_preview()
	var scroll := _section_body.get_parent() as ScrollContainer
	scroll.scroll_vertical = 0
	if not is_inside_tree():
		return
	var target: Control = _section_buttons[section_id]
	if focus_content:
		match section_id:
			"devices": target = flight_device_picker
			"profile": target = profile_picker
			"axes": target = _axis_detect_buttons.roll if not axis_advanced_toggle.button_pressed else _axis_controls.roll.axis.get_line_edit()
			"aux": target = _aux_controls.smoke.type
			"buttons": target = action_filter
		if section_id == "aux" and not target.is_visible_in_tree():
			for aux_name: String in AUX_CHANNELS:
				if (_aux_controls[aux_name].type as Control).is_visible_in_tree():
					target = _aux_controls[aux_name].type
					break
		# The Keyboard's read-only pages have nothing to edit; their tab keeps focus.
		if not target.is_visible_in_tree():
			target = _section_buttons[section_id]
	target.grab_focus()


func _on_action_filter_selected(_index: int) -> void:
	if _is_assignment_busy():
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
	_set_keyboard_mode(_draft_flight_device_id < 0)
	_update_setup_assistant_button()
	_queue_workspace_refresh()
	_queue_dirty_marker()


## UI-15-UX-07: the Setup assistant is offered for every connected controller; a device that still needs setup
## (an unconfigured joystick or an uncalibrated radio) gets a one-time hint per app run. It never opens by itself.
func _update_setup_assistant_button() -> void:
	if setup_assistant_button == null:
		return
	var device := _device_for_id(_draft_flight_device_id)
	var available := _draft_flight_device_id >= 0 and bool(device.get("connected", false))
	setup_assistant_button.visible = available
	setup_assistant_button.disabled = not available
	if not available or not _device_needs_setup():
		return
	var key := "%s|%s" % [str(device.get("guid", "")), str(device.get("name", ""))]
	if _assistant_offered.has(key):
		return
	_assistant_offered[key] = true
	_set_status(tr("New controller detected. Choose Set up this device to configure it step by step."), false)


func _device_needs_setup() -> bool:
	var kind := str(_draft_profile.get("kind", ""))
	if kind == "joystick":
		return not bool(_draft_profile.get("configured", true))
	return kind == "radio" and not radio_mapping_verified(_draft_profile)


## Opens the Setup assistant over this screen. It edits only this draft through setup_assistant_bridge.gd;
## Cancel restores the draft as it was when the assistant opened, Save uses the normal transactional Save.
func open_setup_assistant() -> bool:
	if is_instance_valid(_assistant) or _is_assignment_busy() or setup_assistant_button == null or setup_assistant_button.disabled:
		return false
	_assistant_restore = {
		"profile": _draft_profile.duplicate(true), "context": _draft_context_key,
		"unsaved_calibration": _unsaved_calibration.duplicate(true), "calibration_origins": _calibration_origins.duplicate(true),
		"menu_origins": _menu_verification_origins.duplicate(true), "ui_device": _draft_ui_device_id,
	}
	_assistant_bridge = SetupAssistantBridge.new(self)
	_assistant = SetupAssistant.new()
	_assistant.name = "SetupAssistant"
	_assistant.configure(_assistant_bridge)
	_assistant_bridge.assistant = _assistant
	_assistant.finished.connect(_on_assistant_finished)
	_assistant.closed.connect(_on_assistant_closed)
	add_child(_assistant)
	_screen.set_active(false)
	_assistant.open(setup_assistant_button)
	return true


## The assistant hides while this screen captures for it, so the capture overlay and the Swap/Replace question show.
func _assistant_capture_started() -> void:
	if is_instance_valid(_assistant):
		_assistant.visible = false
		_screen.set_active(true)


func _assistant_capture_aborted() -> void:
	if is_instance_valid(_assistant):
		_screen.set_active(false)
		_assistant.visible = true


func _on_capture_finished_for_assistant(target_id: String, ok: bool, message: String) -> void:
	if not is_instance_valid(_assistant):
		return
	_screen.set_active(false)
	_assistant.visible = true
	_assistant.notify_capture_finished(target_id, ok, message)


func _on_calibration_finished_for_assistant(ok: bool, message: String) -> void:
	if not is_instance_valid(_assistant):
		return
	_screen.set_active(false) # the calibration screen's pop re-activated this one
	if ok and _assistant_bridge != null:
		_assistant_bridge.reset_reverse_baseline()
	_assistant.notify_calibration_finished(ok, message)


func _on_assistant_finished(saved: bool) -> void:
	if saved or _assistant_restore.is_empty():
		return
	_unsaved_calibration = _assistant_restore.unsaved_calibration
	_calibration_origins = _assistant_restore.calibration_origins
	_set_draft_profile(_assistant_restore.profile, str(_assistant_restore.context))
	# Edits can invalidate radio menu evidence and drop the radio as menu device; Cancel brings both back.
	_menu_verification_origins = _assistant_restore.menu_origins
	if _draft_ui_device_id != int(_assistant_restore.ui_device):
		_draft_ui_device_id = int(_assistant_restore.ui_device)
		_refresh_devices()
	_set_status(tr("Setup cancelled. The previous draft is back."), false)


func _on_assistant_closed() -> void:
	var finished_assistant := _assistant
	_assistant = null
	_assistant_bridge = null
	_assistant_restore = {}
	_screen.set_active(true)
	if is_instance_valid(finished_assistant):
		finished_assistant.queue_free()
	_update_device_summary()
	_draft_validation_changed()
	if is_inside_tree() and is_instance_valid(setup_assistant_button) and setup_assistant_button.is_visible_in_tree():
		setup_assistant_button.grab_focus()


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
	get_tree().root.window_input.connect(_observe_popup_diagnostics)
	capture_finished.connect(_on_capture_finished_for_assistant)
	calibration_finished.connect(_on_calibration_finished_for_assistant)
	get_viewport().gui_focus_changed.connect(_on_workspace_focus_changed)
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _axis_capture_dialog != null:
		_cancel_capture()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _axis_detector != null:
		var lost := tr("The window lost focus; detection was cancelled.")
		_set_status(lost, false)
		_capture_done(false, lost)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _axis_capture_dialog != null:
		_check_axis_capture_focus.call_deferred()
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return
	_refresh_devices()
	_update_profile_options()
	_update_glyph_family_picker()
	_update_profile_kind_picker()
	update_calibration_controls(calibrate_button.visible, choose_radio_profile_button.visible, calibration_prerequisite.visible)
	_update_preset_options()
	_update_aux_controls()
	_update_action_controls()
	profile_name_edit.placeholder_text = TranslationServer.translate("Profile name")
	_update_accessible_names()
	_refresh_validation_feedback()
	_queue_dirty_marker()
	_keyboard_tables_vehicle = ""
	_set_keyboard_mode(_keyboard_mode)
	_configure_live_axis_views()
	_queue_workspace_refresh()


## The OFF confirmation transfers focus to our own native popup. Resolve that
## transfer after the window event; an actual application loss still cancels.
func _check_axis_capture_focus() -> void:
	if not is_instance_valid(_axis_capture_dialog) or DisplayServer.get_name() == "headless": return
	if get_window().has_focus() or _axis_capture_dialog.has_focus(): return
	_cancel_capture()


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
	if _axis_capture != null:
		_sample_axis_capture(delta)
	if _axis_detector != null:
		_sample_axis_detect(delta)
	if capture_overlay != null and capture_overlay.is_capturing():
		capture_overlay.advance(delta)
	# Containers finish sorting at the end of the previous frame. Coalesce their
	# layout notifications; ordinary wheel scrolling must not force focus back.
	if _mapping_focus_layout_pending:
		_mapping_focus_layout_pending = false
		_keep_mapping_focus_visible()
	if _initial_focus_wait_frames > 0:
		_initial_focus_wait_frames -= 1
		if _initial_focus_wait_frames == 0:
			close_button_focus()
	if visible and _screen.is_visible_in_tree() and _selected_section in ["axes", "aux"]:
		_preview_clock += delta
		if _preview_clock >= 0.08:
			_refresh_visible_preview()


## Preview values are presentation only. Keep capture and device-change handling active when covered.
func _refresh_visible_preview() -> void:
	if not is_inside_tree() or not visible or not _screen.is_visible_in_tree():
		return
	match _selected_section:
		"axes": _update_axis_preview()
		"aux": _update_aux_preview()
		_: return
	_preview_clock = 0.0


func _input(event: InputEvent) -> void:
	_observe_diagnostics(event)
	if event is InputEventPanGesture or event is InputEventScreenDrag \
		or event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var scroll := _section_body.get_parent() as ScrollContainer
		if scroll.get_global_rect().has_point(event.position):
			_on_mapping_scroll_input(event)
	if _consume_capture_release(event):
		get_viewport().set_input_as_handled()
		return
	if not _conflict.is_empty():
		# The question's buttons take gamepad/keyboard navigation; Escape answers Cancel (Back does via the Screen).
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
				and ((event as InputEventKey).physical_keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			_track_capture_release(event)
			_resolve_conflict("cancel")
		return
	if not _is_capture_active():
		return
	if _axis_capture_dialog != null:
		if _axis_capture == null:
			# OFF step: the overlay's focused Confirm OFF takes Enter/accept; Escape cancels.
			var off_key := event as InputEventKey
			if off_key != null and off_key.pressed and not off_key.echo \
					and (off_key.keycode == KEY_ESCAPE or off_key.physical_keycode == KEY_ESCAPE):
				get_viewport().set_input_as_handled()
				_track_capture_release(event)
				_cancel_capture()
			return
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
			if event.pressed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE): _cancel_capture()
		elif (event is InputEventJoypadMotion or event is InputEventJoypadButton) and event.device == _capturing_device_id:
			get_viewport().set_input_as_handled()
		return
	if _axis_detector != null:
		_input_axis_detect(event)
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
		_on_capture_event(key_event)
		return
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		if button_event.device != _capturing_device_id:
			return
		get_viewport().set_input_as_handled()
		if not button_event.pressed:
			return
		_track_capture_release(button_event)
		_on_capture_event(button_event)
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.device != _capturing_device_id:
			return
		get_viewport().set_input_as_handled()
		if not is_finite(motion.axis_value) or absf(motion.axis_value) < 0.65:
			return
		# Find control: an axis resting at an end (radio throttle at LOW, an axis switch) only counts once it moves
		# well away from where it was when Find started, so its resting jitter is never reported as a choice.
		if _finding and motion.axis < _find_baseline.size() 				and absf(motion.axis_value - _find_baseline[motion.axis]) < FIND_AXIS_MIN_TRAVEL:
			return
		_track_capture_release(motion)
		_on_capture_event(motion)


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
		if captured_device.is_empty() or not bool(captured_device.get("connected", true)) \
			or (_capturing_generation > 0 and not _calibration_connection_matches(_capturing_device_id, _capturing_generation)):
			_set_status(tr("The selected flight controller disconnected; remapping was cancelled."), true)
			_capture_done(false, tr("The selected flight controller disconnected; remapping was cancelled."))
	_update_axis_controls()
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
		if id < 0:
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
	var capture_cancelled := selected_id != _draft_flight_device_id and _is_assignment_busy()
	if capture_cancelled:
		_capture_done(false, tr("The flight controller changed; remapping was cancelled."))
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
	if _radio_menu_profile_for_device(device).size() > 0: return true
	if int(device.get("id", -1)) == _draft_flight_device_id and _draft_profile.get("kind", "") == "radio": return false
	if profile_store != null and profile_store.has_method("match_profile"):
		var saved: Dictionary = profile_store.match_profile(device, _devices)
		if saved.get("kind", "") == "radio": return false
	if bool(device.get("ambiguous", false)) or str(device.get("kind", "")) == "radio":
		return false
	if str(device.get("kind", "")) == "gamepad" and bool(device.get("known", false)):
		return true
	return _has_saved_gamepad_profile(device)


func _radio_menu_profile_for_device(device: Dictionary) -> Dictionary:
	var id := int(device.get("id", -1))
	var profile := {}
	if id == _draft_flight_device_id and RadioMenu.is_verified(_profile_candidate()): profile = _profile_candidate()
	elif profile_store != null and profile_store.has_method("match_profile"):
		profile = profile_store.match_profile(device, _devices)
	if not RadioMenu.is_verified(profile): return {}
	# A serial-qualified association may still be unique within a duplicated family.
	var association: Dictionary = profile.get("association", {})
	if bool(device.get("ambiguous", false)) and str(association.get("serial_number", "")).is_empty(): return {}
	return profile


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
	_switch_draft_profile(_default_profile_for_device(device_id), "device:%d" % device_id)


func _default_profile_for_device(device_id: int) -> Dictionary:
	var device := _device_for_id(device_id)
	var expected_kind := str(device.get("kind", "gamepad"))
	var preset := "mode2" if expected_kind == "gamepad" else ("jeti_mode2" if _is_jeti_device(device) else "radio_custom")
	var candidate_profile := ControllerProfile.defaults(expected_kind, preset)
	if candidate_profile.is_empty():
		candidate_profile = ControllerProfile.defaults("gamepad", "mode2")
	if expected_kind == "joystick":
		candidate_profile["configured"] = false
	return candidate_profile


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
	var remembered := _drafts_by_context.has(context_key)
	var target: Dictionary = _drafts_by_context.get(context_key, profile)
	_set_draft_profile(target, context_key)
	# UX-02b: a context's first load is its clean reference; a remembered draft keeps the earlier one.
	if not remembered and not _clean_snapshots.has(context_key):
		_clean_snapshots[context_key] = _dirty_fingerprint()
		_queue_dirty_marker()


func _set_draft_profile(profile: Dictionary, context_key := "") -> void:
	_reset_validation()
	var previous_profile_id := str(_draft_profile.get("profile_id", ""))
	_draft_profile = profile.duplicate(true)
	if not _draft_profile.is_empty() and not _draft_profile.has("flap_elevator_mix_owner"):
		_draft_profile["flap_elevator_mix_owner"] = "simulator"
	_invalidate_menu_evidence()
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
	_update_menu_controls()
	draft_changed.emit()
	_queue_dirty_marker()


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
	if profile_index == -1:
		if _is_assignment_busy():
			_cancel_capture()
		# New and the initial device draft share one unsaved context. Returning
		# here restores pending edits without borrowing a saved profile's UUID.
		_switch_draft_profile(_default_profile_for_device(_draft_flight_device_id), "device:%d" % _draft_flight_device_id)
	elif profile_index >= 0 and profile_index < _profiles.size():
		if _is_assignment_busy():
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
		_profile_kind_help_label.text = tr("Choose the flight profile for this controller. Gamepad starts in Mode 2; radio uses a custom profile. Calibration never starts automatically.")
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
	if selected_kind in ["radio", "joystick"] and str(_draft_profile.get("kind", "")) in ["radio", "joystick"]:
		replacement["flap_elevator_mix_owner"] = ControllerProfile.flap_elevator_mix_owner(_draft_profile)
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
		_set_status(tr("Could not prepare the safe radio action map: %s") % _friendly_validation_text(validation.get("issues", []), validation.get("errors", [])), true)
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
		for key in ["profile_id", "name", "association", "actions", "presentation", "aux", "flap_elevator_mix_owner"]:
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
	for key in ["profile_id", "name", "association", "presentation", "aux", "flap_elevator_mix_owner"]:
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
		_set_status(tr("Could not restore the JETI Mode 2 preset: %s") % _friendly_validation_text(validation.get("issues", []), validation.get("errors", [])), true)
		return
	_set_draft_profile(replacement)
	_set_status(tr("JETI Mode 2 mapping is in the draft. Confirm your own switch installation, then Save to keep it."), false)


func _duplicate_profile() -> void:
	var verified := radio_mapping_verified(_draft_profile)
	var calibration_origin: Dictionary = _calibration_origins.get(_draft_context_key, {}).duplicate(true)
	var duplicate := _draft_profile.duplicate(true)
	var id_source := ControllerProfile.defaults(str(duplicate.get("kind", "gamepad")), str(duplicate.get("preset", "mode2")))
	if id_source.is_empty():
		id_source = ControllerProfile.defaults("gamepad", "mode2")
	duplicate["profile_id"] = id_source.get("profile_id", "")
	duplicate["name"] = "%s copy" % str(duplicate.get("name", "Controller profile"))
	_set_draft_profile(duplicate)
	if verified and duplicate.get("kind", "") == "radio":
		_reused_radio_mappings[str(duplicate.profile_id)] = {mapping = _radio_mapping(duplicate),
			id = _draft_flight_device_id, generation = int(registry.connection_generation(_draft_flight_device_id))}
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
		var has_shaping := profile_kind == "gamepad" and not (channel_name == "throttle" \
			and str(_draft_profile.get("throttle_mode", "")) == "trigger_absolute")
		deadzone_spin.set_value_no_signal(float(channel.get("deadzone", ControllerProfile.DEFAULT_DEADZONE)))
		deadzone_spin.editable = has_shaping
		var expo_spin: SpinBox = controls.expo
		expo_spin.set_value_no_signal(float(channel.get("expo", ControllerProfile.DEFAULT_EXPO)))
		expo_spin.editable = has_shaping
		var invert: CheckBox = controls.invert
		invert.set_pressed_no_signal(bool(channel.get("invert", false)))
		axis_spin.editable = true
		invert.disabled = false
		var detect: Button = _axis_detect_buttons[channel_name]
		detect.text = tr("Listening…") if _detect_channel == channel_name else tr("Detect")
		detect.disabled = not _flight_device_connected()
		detect.tooltip_text = tr(str(DETECT_PROMPTS[channel_name]))


func _update_aux_controls() -> void:
	if _draft_profile.is_empty() or _aux_controls.is_empty():
		return
	flap_mix_owner_picker.select(1 if ControllerProfile.flap_elevator_mix_owner(_draft_profile) == "transmitter" else 0)
	flap_mix_owner_picker.disabled = str(_draft_profile.get("kind", "")) not in ["radio", "joystick"]
	var aux_value: Variant = _draft_profile.get("aux", {})
	var aux: Dictionary = aux_value.duplicate(true) if aux_value is Dictionary else {}
	aux_legacy_arm_hint.visible = _legacy_gear_arms_quad()
	for aux_name in AUX_CHANNELS:
		var controls: Dictionary = _aux_controls[aux_name]
		(controls.row.get_parent() as Control).visible = _aux_row_shown(aux_name)
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
		var aux_detect: Button = controls.detect
		aux_detect.text = tr("Listening…") if _capturing_aux_axis == aux_name else tr("Move the control")
		aux_detect.disabled = not _flight_device_connected()
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


## D6-UX-01: an Extra channels row shows when its channel serves the active vehicle (ControllerActions.aux_applies)
## or "Show channels for all vehicles" is on; for the FPV quad a bound Landing gear row that still arms it (legacy)
## stays visible too. Hidden rows keep their bindings and still take part in validation.
func _aux_row_shown(aux_name: String) -> bool:
	if show_all_vehicle_aux.button_pressed or ControllerActions.aux_applies(aux_name, action_capabilities):
		return true
	return aux_name == "gear" and _legacy_gear_arms_quad()


## The FPV quad is active and this radio/joystick draft arms it from the Landing gear AUX because Arm is unbound
## (multirotor_input.gd keeps that legacy fallback; gamepads never used it).
func _legacy_gear_arms_quad() -> bool:
	if not ControllerActions.aux_applies("arm", action_capabilities) or str(_draft_profile.get("kind", "")) not in ["radio", "joystick"]:
		return false
	var aux_value: Variant = _draft_profile.get("aux", {})
	if not aux_value is Dictionary:
		return false
	var gear: Variant = aux_value.get("gear", {})
	var arm: Variant = aux_value.get("arm", {})
	return gear is Dictionary and not gear.is_empty() and not (arm is Dictionary and not arm.is_empty())


func _on_flap_mix_owner_selected(index: int) -> void:
	if _draft_profile.is_empty() or str(_draft_profile.get("kind", "")) not in ["radio", "joystick"] \
			or index < 0 or index >= flap_mix_owner_picker.item_count:
		_update_aux_controls()
		return
	_draft_profile["flap_elevator_mix_owner"] = "transmitter" if flap_mix_owner_picker.get_item_id(index) == 1 else "simulator"
	_set_status(tr("Flap compensation changed. Save the profile to keep it."), false)
	_refresh_validation_feedback()


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
	_configure_live_axis_views()
	_update_axis_preview()
	_update_aux_preview()


func _update_axis_preview() -> void:
	if _preview_labels.is_empty() or _draft_profile.is_empty():
		return
	var device := _device_for_id(_draft_flight_device_id)
	var connected := _draft_flight_device_id >= 0 and not device.is_empty() and bool(device.get("connected", true))
	var kind := str(_draft_profile.get("kind", "gamepad"))
	for channel_index in CHANNELS.size():
		var channel_name: String = CHANNELS[channel_index]
		var channel: Dictionary = _draft_profile.get(channel_name, {})
		var axis := int(channel.get("axis", 0))
		var raw := _read_axis_preview(_draft_flight_device_id, axis) if connected else 0.0
		var conditioned := ControllerProfile.channel_value(raw, channel_name, _draft_profile) if connected else 0.0
		_axis_raw[channel_index] = raw
		_axis_out[channel_index] = conditioned
		var current: Label = _preview_labels[channel_name]
		if connected and channel_name == "throttle" and str(_draft_profile.get("throttle_mode", "")) == "radio_absolute":
			current.text = tr("%s: %.0f%% · raw %+.2f") % [tr(str(CHANNEL_LABELS[channel_name])), conditioned * 100.0, raw]
			current.tooltip_text = current.text
		else:
			current.text = tr("%s · in %+.2f → out %+.2f") % [tr(str(CHANNEL_LABELS[channel_name])), raw, conditioned] if connected else "%s · —" % tr(str(CHANNEL_LABELS[channel_name]))
			current.tooltip_text = tr("%s · raw %+.2f · conditioned %+.2f") % [tr(str(CHANNEL_LABELS[channel_name])), raw, conditioned] if connected else current.text
		_preview_axis_labels[channel_name].text = tr("Axis %d") % axis
		var meter: ProgressBar = _preview_bars[channel_name]
		var absolute := str(channel.get("range_kind", "centered")) == "absolute"
		meter.min_value = 0.0 if absolute else -1.0
		meter.value = conditioned
	var axis_label: String
	if connected:
			axis_label = tr("Draft: throttle LOW should read 0%. Then Use calibration and Save.") if kind == "radio" else tr("Live values are read only. No controller input reaches the aircraft from this screen.")
	else:
		axis_label = tr("Select a connected flight controller to preview mapped channels.")
	preview_label.text = axis_label
	_update_live_axis_views(connected)


## UI-15-UX-04/08: gimbal captions, throttle end and deadzone ring follow the draft and its stick mode; the curve
## plots the focused channel through ControllerProfile.channel_value. Called on draft changes, never per sample.
func _configure_live_axis_views() -> void:
	if _axis_gimbals.is_empty() or _draft_profile.is_empty():
		return
	_live_stick_mode = _stick_mode_for_profile()
	var functions: Array = CalibrationView.gimbal_functions(_live_stick_mode)
	var gamepad := str(_draft_profile.get("kind", "")) == "gamepad"
	var absolute_throttle := _throttle_is_absolute()
	for side in 2:
		var gimbal := _axis_gimbals[side]
		var x_function: String = functions[side][0]
		var y_function: String = functions[side][1]
		# Vertical function first, as the device picture names its gimbals ("Throttle · Yaw").
		gimbal.caption = "%s · %s" % [tr(str(CHANNEL_LABELS[y_function])), tr(str(CHANNEL_LABELS[x_function]))]
		var one_ended := y_function == "throttle" and absolute_throttle
		gimbal.one_ended_y = one_ended
		gimbal.end_labels = PackedStringArray([tr("FULL"), tr("LOW")]) if one_ended else PackedStringArray()
		var deadzone := 0.0
		if gamepad:
			for function: String in [x_function, y_function]:
				if function == "throttle" and absolute_throttle:
					continue
				var channel: Variant = _draft_profile.get(function, {})
				if channel is Dictionary:
					deadzone = maxf(deadzone, float(channel.get("deadzone", 0.0)))
		gimbal.set_deadzone(deadzone)
	_response_curve.set_channel(_draft_profile, _curve_channel)


func _throttle_is_absolute() -> bool:
	var throttle: Variant = _draft_profile.get("throttle", {})
	return throttle is Dictionary and str(throttle.get("range_kind", "centered")) == "absolute"


## Profile preset Mode 1 / Mode 2 when it names one, else the pilot's HUD stick mode (presentation only).
func _stick_mode_for_profile() -> int:
	match str(_draft_profile.get("preset", "")):
		"mode1": return 1
		"mode2", "jeti_mode2": return 2
	return CalibrationView.presentation_stick_mode(self)


## Live samples only: the values the four rows above already read (no extra provider calls).
func _update_live_axis_views(connected: bool) -> void:
	if _axis_gimbals.is_empty() or not _section_pages.axes.is_visible_in_tree():
		return
	var functions: Array = CalibrationView.gimbal_functions(_live_stick_mode)
	var absolute_throttle := _axis_gimbals[0].one_ended_y or _axis_gimbals[1].one_ended_y
	for side in 2:
		var x := _axis_out[CHANNELS.find(functions[side][0])]
		var y_function: String = functions[side][1]
		var y := _axis_out[CHANNELS.find(y_function)]
		if y_function == "throttle":
			# Output +1 is throttle up: the stick forward (up in the picture).
			y = GimbalView.throttle_to_y(y) if absolute_throttle else -y
		_axis_gimbals[side].set_stick(Vector2(x, y), connected)
	_response_curve.set_raw_value(_axis_raw[CHANNELS.find(_curve_channel)], connected)


func _update_action_controls() -> void:
	if action_grid == null:
		return
	var presentation: Dictionary = _draft_profile.get("presentation", {})
	var family := str(presentation.get("glyph_family", "auto"))
	var device := _device_for_id(_draft_flight_device_id)
	var child_index := 3
	var last_change_button: Button
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_in_rows := focused != null and action_grid.is_ancestor_of(focused)
	var conflicts := _action_conflicts()
	var chip_profile: Dictionary = _draft_profile if str(_draft_profile.get("kind", "")) in ["radio", "joystick"] else {}
	var chips_by_control: Dictionary = {}
	for definition in ControllerActions.ACTIONS:
		var action_id := str(definition.id)
		var label_control: Label = action_grid.get_child(child_index)
		var binding_cell: HBoxContainer = action_grid.get_child(child_index + 1)
		var binding_control: Label = binding_cell.get_node("Binding_%s" % action_id)
		var glyph_control: TextureRect = binding_cell.get_node("BindingGlyph_%s" % action_id)
		var capture_button: Button = action_grid.get_child(child_index + 2)
		var clear_button: Button = _clear_action_buttons[action_id]
		var axis_button: Button = _axis_capture_buttons[action_id]
		axis_button.text = tr("Learn axis")
		axis_button.visible = str(_draft_profile.get("kind", "")) in ["radio", "joystick"] \
			and (str(definition.context) in ["flight", "both"] or (_draft_profile.get("kind", "") == "radio" and action_id in ["accept", "back"]))
		axis_button.disabled = _is_capture_active()
		var radio_navigation: bool = _draft_profile.get("kind", "") == "radio" and action_id.begins_with("navigate_")
		capture_button.disabled = radio_navigation
		capture_button.tooltip_text = tr("Radio menu movement uses the calibrated roll and pitch controls.") if radio_navigation else ""
		label_control.text = tr(str(definition.label))
		if action_id == "rates_toggle":
			label_control.tooltip_text = tr("Airplane dual rates: press the left stick (L3) on a gamepad, or remap Dual rates below for a joystick. Each press alternates normal and high rates. Existing assignments take priority. Radio profiles use the transmitter's rates.")
		var binding: Dictionary = _action_bindings.get(action_id, {})
		var prompt: Dictionary = ControllerPrompts.prompt(binding, family, device, _draft_profile)
		var fallback_text := ControllerActions.binding_text(binding)
		var prompt_text := str(prompt.get("text", fallback_text))
		binding_control.text = prompt_text if not prompt_text.is_empty() else fallback_text
		if radio_navigation: binding_control.text = tr("Calibrated roll / pitch")
		var texture_path := str(prompt.get("texture_path", ""))
		glyph_control.texture = _get_prompt_texture(texture_path)
		glyph_control.visible = false
		var chip: BindingChip = _binding_chips[action_id]
		chip.action_name = label_control.text
		chip.set_binding(binding, family, device, chip_profile)
		chip.set_label(binding_control.text if radio_navigation else "")
		chip.conflict = conflicts.has(action_id)
		if _capturing_action == action_id:
			capture_button.text = tr("Listening…")
		else:
			capture_button.text = tr("Remap")
		clear_button.text = tr("Clear")
		var clear_had_focus := clear_button.has_focus()
		clear_button.disabled = action_id in ["back", "pause"] or binding.get("type", "unbound") == "unbound"
		if radio_navigation: clear_button.disabled = true
		clear_button.focus_mode = Control.FOCUS_NONE if clear_button.disabled else Control.FOCUS_ALL
		if clear_had_focus and clear_button.disabled and capture_button.is_visible_in_tree():
			capture_button.grab_focus()
		var row_visible := _action_row_shown(definition)
		label_control.visible = row_visible
		binding_cell.visible = row_visible
		capture_button.visible = row_visible
		capture_button.focus_neighbor_bottom = NodePath()
		if row_visible:
			last_change_button = capture_button
			if not radio_navigation:
				for control_id: String in _binding_control_ids(binding):
					(chips_by_control.get_or_add(control_id, []) as Array).append(chip)
		child_index += 3
	if reset_category_button != null:
		var category := action_filter.selected
		reset_category_button.visible = category > 0
		if category > 0:
			reset_category_button.text = tr("Reset %s") % tr(action_filter.get_item_text(category))
	if workspace != null:
		workspace.set_chips(chips_by_control)
	# The shorter Save caption must remain the next D-pad target below the list,
	# regardless of the Cancel button's relative width in the current language.
	if is_inside_tree() and last_change_button != null:
		last_change_button.focus_neighbor_bottom = last_change_button.get_path_to(save_button)
	# A filter change may hide the focused row; keep keyboard/gamepad focus on a visible control nearby.
	if focus_in_rows and is_instance_valid(focused) and not focused.is_visible_in_tree():
		for target: Control in [show_all_vehicle_actions, action_filter]:
			if target.is_visible_in_tree():
				target.grab_focus()
				break
	_repaint_validation_feedback()


## UI-15-UX-02c: the category filter and the active vehicle together choose the rows; hidden rows keep
## their bindings and still take part in validation.
func _action_row_shown(definition: Dictionary) -> bool:
	if action_filter.selected > 0 and _action_category(definition) != action_filter.selected:
		return false
	return show_all_vehicle_actions.button_pressed or ControllerActions.action_applies(str(definition.id), action_capabilities)


## Make one action's row visible (public capture requests and validation focus may target a hidden row).
func _reveal_action_row(action_id: String) -> void:
	var definition := ControllerActions.action_definition(action_id)
	if definition.is_empty() or _action_row_shown(definition):
		return
	if action_filter.selected > 0 and _action_category(definition) != action_filter.selected:
		action_filter.select(0)
	if not ControllerActions.action_applies(action_id, action_capabilities):
		show_all_vehicle_actions.set_pressed_no_signal(true)
	_update_action_controls()


func _on_show_all_vehicle_actions(_pressed: bool) -> void:
	if _is_assignment_busy():
		_cancel_capture()
	_update_action_controls()
	_refresh_validation_feedback()


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
	_queue_workspace_refresh()
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
	if _draft_profile.get("kind", "") == "radio" and action_id.begins_with("navigate_"): return
	if _is_assignment_busy(): _capture_done()
	# Selecting even the current section resets its scroll and focuses its tab.
	# A row edit is not navigation: keep its viewport and keyboard/gamepad focus.
	if _selected_section != "buttons":
		select_section("buttons")
	# Public callers may request an action currently hidden by the category or vehicle filter.
	if not button.visible:
		_reveal_action_row(action_id)
	_capturing_aux_name = ""
	_capturing_aux_position = -1
	_capturing_action = action_id
	_capturing_device_id = _draft_flight_device_id
	_capturing_generation = int(registry.connection_generation(_capturing_device_id)) \
		if registry != null and registry.has_method("connection_generation") else 0
	_capture_button = button
	_capture_target = action_id
	_capture_button.grab_focus()
	_set_status(tr("Press a keyboard key or an input on the selected flight controller. Escape cancels remapping."), false)
	var caption := _target_caption("action:" + action_id)
	_show_capture_overlay(tr("Remap %s") % caption, tr("Move or press the control for %s…") % caption)
	_update_action_controls()


func _start_aux_capture(aux_name: String, row_index: int, button: Button) -> void:
	if button.disabled or not _aux_controls.has(aux_name):
		return
	if _is_assignment_busy(): _capture_done()
	if _selected_section != "aux":
		select_section("aux")
	if not _aux_row_shown(aux_name):
		show_all_vehicle_aux.set_pressed_no_signal(true)
		_update_aux_controls()
	_capturing_action = ""
	_capturing_aux_name = aux_name
	_capturing_aux_position = row_index
	_capturing_device_id = _draft_flight_device_id
	_capture_button = button
	_capture_target = "aux:" + aux_name
	_capture_button.grab_focus()
	_set_status(tr("Move the selected radio switch to this position. The next button press is captured; no other switch needs to be released."), false)
	var position := "%s %s" % [_target_caption("aux:" + aux_name), tr(_switch_position_name(row_index))]
	_show_capture_overlay(tr("Capture %s position") % position,
		tr("Move the selected radio switch to this position. The next button press is captured; no other switch needs to be released."))
	_update_aux_controls()


func _is_capture_active() -> bool:
	return not _capturing_action.is_empty() or not _capturing_aux_name.is_empty() or _axis_detector != null \
		or not _capturing_aux_axis.is_empty() or _finding


func _capture_binding(event: InputEvent) -> void:
	if not _capturing_aux_name.is_empty():
		return
	var binding := ControllerActions.binding_from_event(event)
	if binding.is_empty():
		return
	_accept_captured_binding(binding)


func _accept_captured_binding(binding: Dictionary) -> void:
	var action_id := _capturing_action
	var target := _capture_target
	var return_focus := _capture_button
	var previous: Dictionary = _action_bindings.get(action_id, {}).duplicate(true)
	var candidate := _base_actions.duplicate(true)
	candidate[action_id] = binding
	var candidate_profile := _draft_profile.duplicate(true)
	candidate_profile["actions"] = candidate
	var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate_profile, action_capabilities)
	var accepted := bool(validation.get("ok", false))
	if accepted:
		_base_actions = candidate
		_draft_profile["actions"] = _base_actions.duplicate(true)
		_action_bindings = validation.get("bindings", ControllerActions.effective_bindings(_draft_profile, action_capabilities))
	_end_capture_state()
	if accepted:
		_set_status(tr("Binding updated. Save the profile to keep it."), false)
		_draft_validation_changed()
		_emit_capture_finished(target, true, "")
	else:
		# UI-15-UX-06: one action or extra channel already uses this control: ask Swap / Replace / Cancel.
		var owner := _single_conflict_owner(validation.get("issues", []), "action:" + action_id)
		if not owner.is_empty():
			_offer_conflict({"target": "action:" + action_id, "report": target, "owner": owner,
				"candidate": candidate_profile, "binding": binding, "previous": previous, "rejected": validation,
				"rejected_message": "Binding was not changed: %s", "focus": return_focus,
				"success": tr("Binding updated. Save the profile to keep it.")})
		else:
			_show_rejected_validation(validation, "Binding was not changed: %s")
			_emit_capture_finished(target, false, _rejection_text())
	get_viewport().set_input_as_handled()


func _capture_aux_button(button_index: int) -> void:
	if _capturing_aux_name.is_empty() or button_index < 0 or button_index >= SmokeAux.MAX_BUTTONS:
		return
	var binding := _aux_binding_for_type(_capturing_aux_name, "switch")
	var candidate := _switch_with_member_swap(binding, _capturing_aux_position, button_index)
	if candidate.is_empty():
		_set_status(tr("That switch position is no longer available. Capture was cancelled."), true)
		_capture_done(false, tr("That switch position is no longer available. Capture was cancelled."))
		return
	var captured_aux := _capturing_aux_name
	var committed := _commit_aux_binding(captured_aux, candidate, false)
	if committed:
		_capture_done(true)
		_set_status(tr("Button %d captured for this switch position. Save the profile to keep it.") % button_index, false)
		_draft_validation_changed()
	else:
		_capture_done(false, _rejection_text())
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
	_set_status(tr("Remapping cancelled."), false)
	_capture_done(false, tr("Remapping cancelled."))


## Ends any capture (and a pending conflict question) and reports it once through capture_finished.
func _capture_done(ok := false, message := "") -> void:
	var target := _capture_target
	var reason := "" if ok else (message if not message.is_empty() else tr("Remapping cancelled."))
	_drop_conflict(reason)
	_end_capture_state()
	_emit_capture_finished(target, ok, reason)


## The capture state machine's reset, without reporting: the overlay closes unless a conflict question follows.
func _end_capture_state() -> void:
	# A cancelled Confirm OFF step (Learn axis / Move the control) owned focus inside the overlay; give it back to the
	# row that started the capture so keyboard and gamepad users are never left without a focus owner.
	var focus_return := _capture_button if is_instance_valid(_capture_button) else null
	var overlay_had_focus := capture_overlay != null and is_inside_tree() 		and capture_overlay.is_ancestor_of(get_viewport().gui_get_focus_owner()) if get_viewport() != null else false
	_axis_capture = null
	if is_instance_valid(_axis_capture_dialog): _axis_capture_dialog.queue_free()
	_axis_capture_dialog = null
	_capturing_generation = 0
	_capturing_action = ""
	_capturing_aux_name = ""
	_capturing_aux_position = -1
	_capturing_device_id = -1
	_capture_button = null
	_capture_target = ""
	_axis_detector = null
	_detect_channel = ""
	_detect_preview_axis = -1
	_capturing_aux_axis = ""
	_axis_capture_phase = ""
	_finding = false
	if capture_overlay != null and capture_overlay.is_capturing():
		capture_overlay.hide_overlay()
	if workspace != null:
		workspace.set_capture_control("")
	_update_axis_controls()
	_update_action_controls()
	_update_aux_controls()
	if overlay_had_focus or (is_inside_tree() and get_viewport().gui_get_focus_owner() == null):
		_restore_capture_focus.call_deferred(focus_return)


func _restore_capture_focus(target: Control) -> void:
	if not is_inside_tree() or is_instance_valid(_assistant) or not _screen.visible:
		return # the Setup assistant (or a covering screen) owns focus now
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and focused.is_visible_in_tree():
		return
	for candidate: Control in [target, save_button]:
		if is_instance_valid(candidate) and candidate.is_visible_in_tree() and candidate.focus_mode != Control.FOCUS_NONE 				and not (candidate is BaseButton and (candidate as BaseButton).disabled):
			candidate.grab_focus()
			return


func _start_axis_capture(action_id: String, button: Button) -> void:
	if _draft_flight_device_id < 0 or _is_capture_active(): return
	_drop_conflict(tr("Remapping cancelled."))
	var definition := ControllerActions.action_definition(action_id)
	if definition.get("context", "menu") not in ["flight", "both"] \
		and not (_draft_profile.get("kind", "") == "radio" and action_id in ["accept", "back"]): return
	_capturing_action = action_id
	_capturing_device_id = _draft_flight_device_id
	_capturing_generation = int(registry.connection_generation(_capturing_device_id))
	_capture_button = button
	_capture_target = action_id
	var text := tr("Hold the chosen switch at OFF, then confirm. Keep the flight sticks still. Next hold ON until asked to return to OFF.")
	_open_axis_off_dialog(tr("Learn axis switch"), text)
	_show_capture_overlay(tr("Learn axis for %s") % _target_caption("action:" + action_id), text)
	capture_overlay.show_confirm(tr("Confirm OFF"))
	_update_action_controls()


## UI-15-UX-05: AUX "Move the control": the same OFF confirmation and OFF→ON→OFF measurement as Learn axis
## (ActionAxisCapture), stored as the channel's axis endpoints.
func _start_aux_axis_capture(aux_name: String, button: Button) -> void:
	if not _aux_controls.has(aux_name) or _draft_profile.is_empty():
		return
	if _is_assignment_busy(): _capture_done()
	if not _flight_device_connected() or registry == null or not registry.has_method("connection_generation"):
		_set_status(tr("Connect the flight controller to measure this control."), true)
		return
	if _selected_section != "aux":
		select_section("aux")
	if not _aux_row_shown(aux_name):
		show_all_vehicle_aux.set_pressed_no_signal(true)
		_update_aux_controls()
	_capturing_aux_axis = aux_name
	_capturing_device_id = _draft_flight_device_id
	_capturing_generation = int(registry.connection_generation(_capturing_device_id))
	_capture_button = button
	_capture_target = "aux:" + aux_name
	if button.is_visible_in_tree():
		button.grab_focus()
	var caption := _target_caption("aux:" + aux_name)
	var text := tr("Hold the control for %s at OFF, then confirm. Keep the flight sticks still. Next move it to ON and hold until asked to return to OFF.") % caption
	_open_axis_off_dialog(tr("Move the control"), text)
	_show_capture_overlay(tr("Move the control for %s") % caption, text)
	capture_overlay.show_confirm(tr("Confirm OFF"))
	_update_aux_controls()


func _open_axis_off_dialog(title: String, text: String) -> void:
	_axis_capture_dialog = ConfirmationDialog.new()
	_axis_capture_dialog.dialog_autowrap = true
	_axis_capture_dialog.title = title
	_axis_capture_dialog.dialog_text = text
	_axis_capture_dialog.get_ok_button().text = tr("Confirm OFF")
	_axis_capture_dialog.confirmed.connect(_confirm_axis_off)
	_axis_capture_dialog.canceled.connect(_cancel_capture)
	# UI-15-UX-06: the OFF step is confirmed in the in-workspace overlay (show_confirm); the dialog object only
	# carries the confirmed/canceled contract and is never shown as a native window.
	add_child(_axis_capture_dialog)


func _capture_axes() -> PackedFloat64Array:
	var axes := PackedFloat64Array()
	for axis: int in SmokeAux.AXES:
		var raw: Variant = axis_preview_provider.call(_capturing_device_id, axis) if axis_preview_provider.is_valid() \
			else Input.get_joy_axis(_capturing_device_id, axis)
		if typeof(raw) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(raw)) or absf(float(raw)) > 1.0:
			return PackedFloat64Array()
		axes.append(float(raw))
	return axes


func _confirm_axis_off() -> void:
	if not _calibration_connection_matches(_capturing_device_id, _capturing_generation):
		_cancel_capture()
		return
	_axis_capture = ActionAxisCapture.new()
	if not _axis_capture.begin(_capture_axes(), SmokeAux.flight_axes(_draft_profile)):
		_set_status(tr("Invalid or interrupted switch capture. The binding is unchanged."), true)
		_capture_done(false, tr("Invalid or interrupted switch capture. The binding is unchanged."))
		return
	_axis_capture_dialog.hide()
	_set_status(tr("Hold the switch at ON. Keep all other switches still."), false)
	_axis_capture_phase = "on"
	if capture_overlay.is_capturing():
		capture_overlay.hide_confirm()
		capture_overlay.set_prompt(tr("Hold the switch at ON. Keep all other switches still."))
		capture_overlay.restart_countdown()
	# The row's button keeps focus while the control is measured (as before the OFF step).
	if is_instance_valid(_capture_button) and _capture_button.is_visible_in_tree():
		_capture_button.grab_focus()


func _sample_axis_capture(delta: float) -> void:
	if not _calibration_connection_matches(_capturing_device_id, _capturing_generation):
		_cancel_capture()
		return
	var result: Dictionary = _axis_capture.sample(_capture_axes(), delta)
	if result.has("error"):
		_set_status(tr(str(result.error)), true)
		_capture_done(false, tr(str(result.error)))
	elif result.has("binding") and not _capturing_aux_axis.is_empty():
		_accept_aux_axis_binding(result.binding)
	elif result.has("binding"):
		var action_id := _capturing_action
		_accept_captured_binding(result.binding)
		if _base_actions.get(action_id, {}) == result.binding:
			_set_status(tr("Axis switch learned. Save, then move away from OFF and back to OFF before use."), false)
	elif _axis_capture.returning:
		_set_status(tr("Return the switch to OFF and hold it there to finish learning."), false)
		if _axis_capture_phase != "return":
			_axis_capture_phase = "return"
			capture_overlay.set_prompt(tr("Return the switch to OFF and hold it there to finish learning."))
			capture_overlay.restart_countdown()


func _update_menu_controls() -> void:
	if verify_menus_button == null: return
	var radio: bool = _draft_profile.get("kind", "") == "radio"
	var connected := bool(_device_for_id(_draft_flight_device_id).get("connected", false))
	var verified := RadioMenu.is_verified(_profile_candidate())
	verify_menus_button.visible = radio
	verify_menus_button.disabled = not connected or _is_capture_active() or not radio_mapping_verified(_draft_profile) \
		or not RadioMenu.is_verified(RadioMenu.verified_profile(_draft_profile))
	disable_menus_button.visible = radio and verified
	disable_menus_button.disabled = _is_capture_active()
	_menu_help.visible = radio
	_menu_help.text = tr("Radio menus verified. Save to keep this menu controller.") if verified else \
		tr("Calibrate this radio and assign physical Accept, Back and Pause controls, then verify radio menus. Text entry still uses a keyboard.")


func _invalidate_menu_evidence() -> void:
	if not _draft_profile.has("ui_navigation") or RadioMenu.is_verified(_associate_candidate(_draft_profile.duplicate(true))): return
	_draft_profile.erase("ui_navigation")
	_menu_verification_origins.erase(str(_draft_profile.get("profile_id", "")))
	if _draft_ui_device_id == _draft_flight_device_id:
		_draft_ui_device_id = -1
		_fill_device_picker(ui_device_picker, true, -1)
	_set_status(tr("Menu control verification expired. Verify again before selecting this radio for menus."), false)


func _disable_radio_menus() -> void:
	_draft_profile.erase("ui_navigation")
	_menu_verification_origins.erase(str(_draft_profile.get("profile_id", "")))
	if _draft_ui_device_id == _draft_flight_device_id: _draft_ui_device_id = -1
	_refresh_devices()
	_update_menu_controls()
	_draft_validation_changed()
	_set_status(tr("Radio menus disabled in the draft. Save to apply; keyboard and mouse remain available."), false)


func _observe_diagnostics(event: InputEvent) -> void:
	if not (event is InputEventJoypadMotion or event is InputEventJoypadButton) or event.device != _draft_flight_device_id: return
	_ensure_diagnostics()
	if _diagnostics_data == null: return
	if event is InputEventJoypadMotion and event.axis >= 0 and event.axis < RadioMenu.AXES:
		_diagnostics_raw[event.axis] = event.axis_value
		_diagnostics_seen[event.axis] = true
	if _diagnostics_data == null: return
	var now := Time.get_ticks_usec()
	if event is InputEventJoypadMotion: _diagnostics_data.motion(event.device, int(event.axis), event.axis_value, now)
	else: _diagnostics_data.button_event(event.device, int(event.button_index), event.pressed, now)


func _ensure_diagnostics() -> void:
	var info := _device_for_id(_draft_flight_device_id)
	if info.is_empty() or not bool(info.get("connected", false)): return
	var generation := int(registry.connection_generation(_draft_flight_device_id)) if registry.has_method("connection_generation") else 0
	var identity := "%d:%d" % [_draft_flight_device_id, generation]
	if _diagnostics_data != null and identity == _diagnostics_connection: return
	_diagnostics_data = InputReportData.new()
	_diagnostics_data.connect_device(_draft_flight_device_id, info, Time.get_ticks_usec())
	_diagnostics_connection = identity
	_diagnostics_raw.resize(RadioMenu.AXES)
	_diagnostics_raw.fill(0.0)
	_diagnostics_seen.resize(RadioMenu.AXES)
	_diagnostics_seen.fill(false)


func diagnostics_report() -> Dictionary:
	var observations := {}
	var info := _device_for_id(_draft_flight_device_id)
	if _diagnostics_data != null:
		var generation := int(registry.connection_generation(_draft_flight_device_id)) if registry.has_method("connection_generation") else 0
		if _diagnostics_connection == "%d:%d" % [_draft_flight_device_id, generation]:
			var records: Array = _diagnostics_data.snapshot()
			if records.size() == 1:
				observations = records[0]
				observations["current_samples"] = {"raw_axes": _diagnostics_raw, "observed": _diagnostics_seen}
	if not diagnostic_capabilities.is_empty(): observations["activity_capabilities"] = diagnostic_capabilities.duplicate()
	var report := ControllerDiagnostics.build(info, _profile_candidate(), observations)
	report["profile_scope"] = "controller_setup_draft"
	return report


func _open_diagnostics_export() -> void:
	if _is_capture_active():
		_set_status(tr("Finish or cancel remapping before exporting diagnostics."), true)
		return
	if is_instance_valid(_diagnostics_dialog):
		_diagnostics_dialog.popup_centered_ratio(0.7)
		return
	_diagnostics_dialog = FileDialog.new()
	_diagnostics_dialog.name = "ControllerDiagnosticsExport"
	_diagnostics_dialog.title = tr("Export controller diagnostics")
	_diagnostics_dialog.use_native_dialog = false
	_diagnostics_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_diagnostics_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_diagnostics_dialog.add_filter("*.json", tr("Controller diagnostic report"))
	_diagnostics_dialog.current_file = "openrc-controller-%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	_diagnostics_dialog.file_selected.connect(_export_diagnostics_to)
	add_child(_diagnostics_dialog)
	_diagnostics_dialog.popup_centered_ratio(0.7)


func _export_diagnostics_to(path: String) -> void:
	var result := ControllerDiagnostics.write_new(path, diagnostics_report())
	if result == OK:
		_set_status(tr("Controller diagnostics exported with device identifiers redacted."), false)
	else:
		_set_status(tr("Diagnostics were not exported (%s). Choose a new filename in a writable folder.") % error_string(result), true)


func _profile_candidate() -> Dictionary:
	var candidate := _draft_profile.duplicate(true)
	candidate["name"] = profile_name_edit.text.strip_edges()
	candidate = _associate_candidate(candidate)
	candidate["actions"] = _base_actions.duplicate(true)
	if str(candidate.get("kind", "")) == "joystick":
		candidate["configured"] = joystick_enabled.button_pressed
	var inherited_actions := ControllerActions.effective_bindings(candidate, action_capabilities)
	for action_id: Variant in _action_bindings:
		if not inherited_actions.has(action_id) or _action_bindings[action_id] != inherited_actions[action_id]:
			candidate.actions[str(action_id)] = _action_bindings[action_id].duplicate(true)
	if candidate.has("ui_navigation") and not RadioMenu.is_verified(candidate): candidate.erase("ui_navigation")
	return candidate


func _associate_candidate(candidate: Dictionary) -> Dictionary:
	var selected_device := _device_for_id(_draft_flight_device_id)
	if not selected_device.is_empty():
		var serial := str(selected_device.get("serial_number", ""))
		var guid := str(selected_device.get("guid", ""))
		var vendor_id := int(selected_device.get("vendor_id", 0))
		var product_id := int(selected_device.get("product_id", 0))
		# Match the service's activation representation before verification, even
		# when a backend exposes only a serial or legacy descriptor identity.
		var association := {"legacy_device_key": RcInput.key_for(_draft_flight_device_id, selected_device),
			"guid": guid, "vendor_id": vendor_id, "product_id": product_id}
		if not serial.is_empty():
			association["serial_number"] = serial
		candidate["association"] = association
	return candidate


func _save_profile(close_on_success := true) -> bool:
	_reset_validation()
	if _is_assignment_busy():
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
	var menu_origin := menu_verification_lease(candidate)
	if RadioMenu.is_verified(candidate) and not _menu_verification_origins.is_empty() \
		and _menu_verification_origins.has(str(candidate.profile_id)) and menu_verification_lease(candidate).is_empty():
		_set_status(tr("The radio connection changed. Verify menu controls again before saving."), true)
		return false
	if not radio_mapping_verified(candidate):
		_set_status(tr("Calibrate this new radio before saving. A device name cannot verify its channel mapping."), true)
		return false
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
	# ConfigFile canonicalizes floats. Carry the same successful measurements to
	# their committed representation only after storage and runtime both succeed.
	if not calibration_origin.is_empty() and calibration_origin.get("mapping", {}) == _radio_mapping(candidate):
		calibration_origin["mapping"] = _radio_mapping(saved)
		_calibration_origins[_draft_context_key] = calibration_origin
	if not menu_origin.is_empty():
		menu_origin["mapping"] = RadioMenu.mapping_fingerprint(saved)
		menu_origin["actions"] = RadioMenu.action_fingerprint(saved)
		_menu_verification_origins[str(saved.profile_id)] = menu_origin
	_replace_saved_profile(saved)
	_unsaved_calibration.erase(_draft_context_key)
	var saved_context := _profile_context_key(saved)
	if _draft_context_key != saved_context:
		# A committed New draft is now an Update target. Free its device slot
		# only after success so the next New cannot recover this saved UUID.
		_drafts_by_context.erase(_draft_context_key)
		if _calibration_origins.has(_draft_context_key):
			_calibration_origins[saved_context] = _calibration_origins[_draft_context_key]
			_calibration_origins.erase(_draft_context_key)
		_draft_context_key = saved_context
	_set_draft_profile(saved, _draft_context_key)
	_drafts_by_context[_draft_context_key] = saved.duplicate(true)
	_refresh_devices()
	_mark_clean()
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
	_reused_radio_mappings[str(candidate.profile_id)] = {mapping = _radio_mapping(candidate),
		id = _draft_flight_device_id, generation = int(registry.connection_generation(_draft_flight_device_id))}
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
	status_label.get_parent().visible = status_label.visible
	_update_status_info_button()
	_queue_dirty_marker()


func _register_validation_field(path: String, section: String, control: Control, labels: Array, caption: String) -> void:
	_validation_fields[path] = {"section": section, "control": control, "labels": labels, "caption": caption}
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	_invalidate_menu_evidence()
	_update_menu_controls()
	_queue_workspace_refresh()
	if not _rejected_issues.is_empty():
		_rejected_issues.clear()
		_rejected_message = ""
		_rejected_errors.clear()
		_clear_field_errors()
		if status_label.text == _validation_status:
			_set_status("", false)
	_refresh_validation_feedback()


func _refresh_validation_feedback() -> void:
	_queue_dirty_marker()
	if not _rejected_issues.is_empty():
		_render_validation_fields(_rejected_issues, false, true)
		if status_label.text == _validation_status:
			_set_status(tr(_rejected_message) % _friendly_validation_text(_rejected_issues, _rejected_errors), true)
			_validation_status = status_label.text
	elif _validation_active and not _draft_profile.is_empty():
		_show_validation(_validate_candidate(_profile_candidate()), false)


func _repaint_validation_feedback() -> void:
	if not _rejected_issues.is_empty():
		_render_validation_fields(_rejected_issues, false, true)
	elif _validation_active and not _draft_profile.is_empty():
		_render_validation_fields(_validate_candidate(_profile_candidate()).issues, false)


func _show_validation(report: Dictionary, focus_error: bool) -> void:
	if focus_error:
		_reveal_vehicle_rows_for(report.get("issues", []))
	_render_validation_fields(report.get("issues", []), focus_error)
	# An unrelated storage/disconnection error owns the footer until explicitly retried.
	if not focus_error and status_label.text != _validation_status and _status_is_error:
		return
	if bool(report.ok):
		if status_label.text == _validation_status:
			_set_status("", false)
	else:
		var errors: Array = report.get("errors", [])
		var text := tr("Profile cannot be saved: %s") % _friendly_validation_text(report.get("issues", []), errors)
		if profile_name_edit.text.strip_edges().is_empty():
			text = tr("Enter a profile name before saving.")
		_set_status(text, true)
	_validation_status = status_label.text


func _show_rejected_validation(report: Dictionary, message: String) -> void:
	_rejected_issues = report.get("issues", []).duplicate(true)
	_rejected_message = message
	_rejected_errors = report.get("errors", []).duplicate()
	_reveal_vehicle_rows_for(_rejected_issues)
	_render_validation_fields(_rejected_issues, false, true)
	_set_status(tr(message) % _friendly_validation_text(_rejected_issues, _rejected_errors), true)
	_validation_status = status_label.text


## UX-02c: an error on another vehicle's action shows that row, so the message never points at hidden fields.
func _reveal_vehicle_rows_for(issues: Array) -> void:
	for issue: Variant in issues:
		if not issue is Dictionary:
			continue
		for path: Variant in issue.get("paths", []):
			var text := str(path)
			if not show_all_vehicle_actions.button_pressed and text.begins_with("actions.") \
					and not ControllerActions.action_applies(text.trim_prefix("actions."), action_capabilities):
				show_all_vehicle_actions.set_pressed_no_signal(true)
				_update_action_controls()
			# D6-UX-01: the same for an Extra channels row hidden for this vehicle.
			var parts := text.split(".")
			if text.begins_with("aux.") and parts.size() > 1 and _aux_controls.has(parts[1]) \
					and not _aux_row_shown(parts[1]):
				show_all_vehicle_aux.set_pressed_no_signal(true)
				_update_aux_controls()


## UX-02: validator issues as sentences naming actions, extra channels and axes by their labels. Codes without
## a sentence keep the validator's own text; with no structured issue the raw errors are shown as before.
func _friendly_validation_text(issues: Array, errors: Array) -> String:
	var sentences: Array[String] = []
	for issue: Variant in issues:
		if not issue is Dictionary:
			continue
		var sentence := _friendly_issue_text(issue)
		if not sentence.is_empty() and not sentences.has(sentence):
			sentences.append(sentence)
	if sentences.is_empty():
		for error: Variant in errors:
			sentences.append(str(error))
	return " ".join(sentences)


func _friendly_issue_text(issue: Dictionary) -> String:
	var actions: Array[String] = []
	var aux: Array[String] = []
	var channels: Array[String] = []
	for path: Variant in issue.get("paths", []):
		var parts := str(path).split(".")
		var caption := ""
		if parts[0] == "actions" and parts.size() > 1:
			var definition := ControllerActions.action_definition(parts[1])
			caption = tr(str(definition.label)) if not definition.is_empty() else parts[1]
			if not actions.has(caption): actions.append(caption)
		elif parts[0] == "aux" and parts.size() > 1 and AUX_CHANNEL_LABELS.has(parts[1]):
			caption = tr(str(AUX_CHANNEL_LABELS[parts[1]]))
			if not aux.has(caption): aux.append(caption)
		elif parts[0] in CHANNELS:
			caption = tr(str(CHANNEL_LABELS[parts[0]]))
			if not channels.has(caption): channels.append(caption)
	match str(issue.get("code", "")):
		"binding_conflict":
			if actions.size() >= 2:
				return tr("“%s” and “%s” use the same control. Change one of them.") % [actions[0], actions[1]]
		"recovery_binding_missing":
			if not actions.is_empty():
				return tr("“%s” needs a control so you can always go back or pause. Assign one.") % actions[0]
		"action_aux_source_conflict":
			if not actions.is_empty() and not aux.is_empty():
				return tr("“%s” uses the same control as the %s extra channel. Change one of them.") % [actions[0], aux[0]]
		"action_aux_conflict":
			if not actions.is_empty() and not aux.is_empty():
				return tr("“%s” and the %s extra channel do the same job. Use only one of them.") % [actions[0], aux[0]]
		"action_flight_axis_conflict":
			if not actions.is_empty():
				return tr("“%s” uses a flight stick axis. Choose another control.") % actions[0]
		"aux_conflict":
			if aux.size() >= 2:
				return tr("The %s and %s extra channels use the same control. Change one of them.") % [aux[0], aux[1]]
		"aux_invalid":
			if not aux.is_empty():
				return tr("Check the %s extra channel: its input is incomplete or uses a flight stick axis.") % aux[0]
		"binding_invalid", "action_unknown":
			if not actions.is_empty():
				return tr("“%s” has an invalid control. Remap it.") % actions[0]
		"axis_conflict":
			if channels.size() >= 2:
				return tr("%s and %s use the same source axis. Change one of them.") % [channels[0], channels[1]]
		"name_invalid":
			return tr("Enter a profile name before saving.")
	return str(issue.get("message", ""))


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
			return tr("Shared input: %s.") % ", ".join(names)
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
	var displayed_issues: Array = issues.duplicate()
	var draft_issue_keys: Dictionary = {}
	if rejected and _validation_active:
		# Rejected attempts must not hide errors already present in the accepted draft.
		var draft_report := _validate_candidate(_profile_candidate())
		for issue: Dictionary in draft_report.issues:
			draft_issue_keys[str(issue.code) + str(issue.paths)] = true
			if not displayed_issues.has(issue):
				displayed_issues.append(issue)
	for issue: Dictionary in displayed_issues:
		var explanation := _validation_message(issue)
		if rejected and not draft_issue_keys.has(str(issue.code) + str(issue.paths)):
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
		_open_advanced_for(control)
		_mark_field_error(control.get_line_edit() if control is SpinBox else control)
		for label: Label in entry.labels:
			if not label_messages.has(label):
				label_messages[label] = []
			for message: String in messages[key]:
				if not label_messages[label].has(message):
					label_messages[label].append(message)
	for label: Label in label_messages:
		label.text = tr(str(_validation_label_captions[label])) + "\n" + "\n".join(label_messages[label])


func _focus_validation_field(key: String) -> bool:
	var entry: Dictionary = _validation_fields[key]
	select_section(str(entry.section))
	var control: Control = entry.control
	if entry.section == "buttons" and not control.is_visible_in_tree() and key.begins_with("actions."):
		_reveal_action_row(key.trim_prefix("actions."))
	_open_advanced_for(control)
	if control is SpinBox:
		control = control.get_line_edit()
	if not control.is_visible_in_tree() or (control is BaseButton and control.disabled) or (control is LineEdit and not control.editable):
		return false
	_initial_focus_wait_frames = 0
	control.grab_focus()
	_ensure_whole_control_visible.call_deferred(control)
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


# --- UI-15-UX-03/04: workspace (device rail, device picture, live highlight, keyboard view) -----------------------

func _queue_workspace_refresh() -> void:
	if _workspace_refresh_queued:
		return
	_workspace_refresh_queued = true
	_refresh_workspace.call_deferred()


## Rail cards and the device picture follow the draft selection and profile (coalesced to once per frame).
func _refresh_workspace() -> void:
	_workspace_refresh_queued = false
	if workspace == null or _draft_profile.is_empty():
		return
	workspace.set_cards(_device_rail_entries())
	var device := _device_for_id(_draft_flight_device_id)
	var keyboard := _draft_flight_device_id < 0
	var kind := str(_draft_profile.get("kind", device.get("kind", "gamepad")))
	var presentation: Variant = _draft_profile.get("presentation", {})
	var requested_family := str(presentation.get("glyph_family", "auto")) if presentation is Dictionary else "auto"
	var family := ControllerPrompts.resolve_family(requested_family, device)
	var channels: Dictionary = {}
	for channel_name: String in CHANNELS:
		var channel: Variant = _draft_profile.get(channel_name, {})
		if channel is Dictionary:
			channels[channel_name] = channel
	# UI-15-UX-05: a compact caption (the device name is on its rail card and in the header).
	var title := tr("LIVE INPUT")
	var hint := tr("Move a stick or press a button: it lights up here and on its action.")
	if _selected_section == "axes" and _response_curve.get_parent() == workspace.context_box:
		hint = "" # the response curve below the picture names its channel and explains itself
	if keyboard:
		hint = tr(KEYBOARD_READ_ONLY_NOTE) + " " + tr("Flight keys are marked; keys you hold light up.")
	elif not bool(device.get("connected", false)):
		hint = tr("Connect this controller to see its input live.")
	workspace.show_device(_draft_flight_device_id, kind, family, _stick_mode_for_profile(), channels, _radio_lamps(),
		title, hint, _keyboard_vehicle_type())
	_refresh_row_highlight()


func _device_display_name(device: Dictionary, device_id: int) -> String:
	if device.is_empty():
		return tr("Disconnected controller %d") % device_id
	if _is_jeti_device(device):
		return JetiRadio.display_name(device)
	return str(device.get("name", device.get("raw_name", tr("Controller %d") % device_id)))


## One card per connected controller (and the selected one even while disconnected), then the Keyboard.
func _device_rail_entries() -> Array:
	var entries: Array = []
	var selected_listed := _draft_flight_device_id < 0
	for device: Dictionary in _devices:
		var id := int(device.get("id", -1))
		var connected := bool(device.get("connected", true))
		if id < 0 or (not connected and id != _draft_flight_device_id):
			continue
		selected_listed = selected_listed or id == _draft_flight_device_id
		entries.append(_rail_entry(device, id))
	if not selected_listed:
		entries.append(_rail_entry({}, _draft_flight_device_id))
	var keyboard_statuses: Array[String] = ["connected"]
	if _draft_flight_device_id < 0:
		keyboard_statuses.append("flight")
	if _draft_ui_device_id < 0:
		keyboard_statuses.append("menus")
	entries.append({"id": -1, "name": tr("Keyboard"), "kind": "keyboard", "family": "generic",
		"statuses": keyboard_statuses, "selected": _draft_flight_device_id < 0})
	return entries


func _rail_entry(device: Dictionary, id: int) -> Dictionary:
	var selected := id == _draft_flight_device_id
	var profile: Dictionary = _draft_profile if selected else {}
	if not selected and profile_store != null and profile_store.has_method("match_profile"):
		var matched: Variant = profile_store.call("match_profile", device, _devices)
		profile = matched if matched is Dictionary else {}
	var kind := str(profile.get("kind", device.get("kind", "joystick")))
	var presentation: Variant = profile.get("presentation", {})
	var requested_family := str(presentation.get("glyph_family", "auto")) if presentation is Dictionary else "auto"
	var statuses: Array[String] = ["connected" if bool(device.get("connected", false)) else "disconnected"]
	if kind == "radio":
		# The draft's mapping needs this connection's calibration evidence; a saved radio profile carries its own.
		var calibrated := radio_mapping_verified(_draft_profile) if selected else not profile.is_empty()
		statuses.append("calibrated" if calibrated else "needs_setup")
	elif kind == "joystick" and (profile.is_empty() or not bool(profile.get("configured", true))):
		statuses.append("needs_setup")
	if selected:
		statuses.append("flight")
	if id == _draft_ui_device_id:
		statuses.append("menus")
	return {"id": id, "name": _device_display_name(device, id), "kind": kind,
		"family": ControllerPrompts.resolve_family(requested_family, device), "statuses": statuses, "selected": selected}


## A card selects the draft flight controller through the flight device picker's own path.
func _on_rail_card_activated(device_id: int) -> void:
	if device_id != _draft_flight_device_id:
		for index in flight_device_picker.item_count:
			if flight_device_picker.get_item_id(index) == device_id and not flight_device_picker.is_item_disabled(index):
				flight_device_picker.select(index)
				_on_flight_device_selected(index)
				break
	_queue_workspace_refresh()


## Radio switch row: AUX switch positions (named "Sa1", "Sa2" … from the group's physical label), AUX buttons and
## pots, then button actions; the picture shows up to eight.
func _radio_lamps() -> Array:
	var lamps: Array = []
	var seen: Dictionary = {}
	var aux: Variant = _draft_profile.get("aux", {})
	if aux is Dictionary:
		for aux_name: String in AUX_CHANNELS:
			var binding: Variant = aux.get(aux_name, {})
			if not binding is Dictionary or binding.is_empty():
				continue
			match str(binding.get("type", "")):
				"switch":
					var label := str(binding.get("label", "")).strip_edges()
					var buttons: Array = binding.get("buttons", [])
					for index in buttons.size():
						if not seen.has("button:%d" % int(buttons[index])):
							seen["button:%d" % int(buttons[index])] = true
							lamps.append({"button": int(buttons[index]), "label": "%s%d" % [label, index + 1] if not label.is_empty() else ""})
				"button":
					if not seen.has("button:%d" % int(binding.get("button", -1))):
						seen["button:%d" % int(binding.get("button", -1))] = true
						lamps.append({"button": int(binding.get("button", 0)), "label": ""})
				"axis":
					lamps.append({"axis": int(binding.get("axis", 0)), "label": ""})
	for definition in ControllerActions.ACTIONS:
		var binding: Dictionary = _action_bindings.get(str(definition.id), {})
		if str(binding.get("type", "")) == "button" and not seen.has("button:%d" % int(binding.get("button", -1))):
			seen["button:%d" % int(binding.get("button", -1))] = true
			lamps.append({"button": int(binding.get("button", 0)), "label": ""})
	return lamps.slice(0, 8)


## Picture control ids a binding shows: "button:N", "axis:N", "key:K"; every member of a switch group.
static func _binding_control_ids(binding: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	match str(binding.get("type", "")):
		"button":
			ids.append("button:%d" % int(binding.get("button", -1)))
		"axis":
			ids.append("axis:%d" % int(binding.get("axis", -1)))
		"key":
			var key := int(binding.get("physical_keycode", 0))
			ids.append("key:%d" % (key if key != 0 else int(binding.get("keycode", 0))))
		"switch":
			for button: Variant in binding.get("buttons", []):
				ids.append("button:%d" % int(button))
	return ids


## Actions the draft reports in a conflict (the chip's badge); the draft stays as it is.
func _action_conflicts() -> Dictionary:
	var result: Dictionary = {}
	if _draft_profile.is_empty():
		return result
	var report: Dictionary = ControllerActions.validate_profile_bindings(_draft_profile, action_capabilities)
	for issue: Variant in report.get("issues", []):
		if not issue is Dictionary or not str(issue.get("code", "")) in ACTION_CONFLICT_CODES:
			continue
		for path: Variant in issue.get("paths", []):
			if str(path).begins_with("actions."):
				result[str(path).trim_prefix("actions.")] = true
	return result


## Rows name the control they edit ("action:flaps_down", "aux:smoke", "axis:roll"); focus or pointer over one
## highlights its bound control on the picture.
func _tag_workspace_rows() -> void:
	for definition in ControllerActions.ACTIONS:
		var action_id := str(definition.id)
		for control: Control in [action_grid.find_child("Remap_%s" % action_id, false, false), _clear_action_buttons[action_id],
				_axis_capture_buttons[action_id]]:
			_tag_row(control, "action:" + action_id)
	for aux_name: String in AUX_CHANNELS:
		var controls: Dictionary = _aux_controls[aux_name]
		for key: String in ["type", "axis", "off", "on", "invert", "button", "button_mode", "switch_count", "switch_label", "switch_invert"]:
			_tag_row(controls[key], "aux:" + aux_name)
		for control: Control in controls.switch_button_spins:
			_tag_row(control, "aux:" + aux_name)
		for control: Control in controls.switch_capture_buttons:
			_tag_row(control, "aux:" + aux_name)
	for channel: String in CHANNELS:
		for control: Control in _axis_controls[channel].values():
			_tag_row(control, "axis:" + channel)
		_tag_row(_axis_detect_buttons[channel], "axis:" + channel)
		(_axis_controls[channel].axis as Control).set_meta("advanced_page", "axes")
	for aux_name: String in AUX_CHANNELS:
		_tag_row(_aux_detect_buttons[aux_name], "aux:" + aux_name)
		for key: String in ["axis", "off", "on"]:
			(_aux_controls[aux_name][key] as Control).set_meta("advanced_page", "aux")


func _tag_row(control: Control, row: String) -> void:
	if control == null:
		return
	control.set_meta("controls_row", row)
	control.mouse_entered.connect(_on_row_hovered.bind(row))
	control.mouse_exited.connect(_on_row_hovered.bind(""))
	if control is SpinBox:
		_tag_row((control as SpinBox).get_line_edit(), row)


func _on_workspace_focus_changed(control: Control) -> void:
	if workspace == null or control == null or not _screen.is_ancestor_of(control):
		return
	var row := str(control.get_meta("controls_row", ""))
	if row.begins_with("axis:") and row.trim_prefix("axis:") != _curve_channel:
		_curve_channel = row.trim_prefix("axis:")
		_response_curve.set_channel(_draft_profile, _curve_channel)
		_response_curve.set_raw_value(_axis_raw[CHANNELS.find(_curve_channel)], _response_curve.is_live())
	workspace.set_focus_control(_row_control_id(row))


func _on_row_hovered(row: String) -> void:
	if workspace != null:
		workspace.set_hover_control(_row_control_id(row))


func _refresh_row_highlight() -> void:
	if not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	workspace.set_focus_control(_row_control_id(str(focused.get_meta("controls_row", ""))) if focused != null else "")


## The picture control a row's current draft binding uses, or "".
func _row_control_id(row: String) -> String:
	var parts := row.split(":")
	if parts.size() != 2 or _draft_profile.is_empty():
		return ""
	var ids := PackedStringArray()
	match parts[0]:
		"action":
			ids = _binding_control_ids(_action_bindings.get(parts[1], {}))
		"aux":
			var aux: Variant = _draft_profile.get("aux", {})
			if aux is Dictionary and aux.get(parts[1], {}) is Dictionary:
				ids = _binding_control_ids(aux.get(parts[1], {}))
		"axis":
			var channel: Variant = _draft_profile.get(parts[1], {})
			if channel is Dictionary:
				ids.append("axis:%d" % int(channel.get("axis", -1)))
	return ids[0] if not ids.is_empty() else ""


## UI-15-UX-03: with the Keyboard selected, the profile pages show its fixed map read-only (keyboard remapping is
## D6-UX-02). Each page's editors move into one wrapper so the switch never fights their own visibility rules.
func _build_keyboard_views() -> void:
	for section: String in PROFILE_SECTIONS:
		var page: VBoxContainer = _section_pages[section]
		var editable := VBoxContainer.new()
		editable.name = "EditablePage_%s" % section
		editable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		editable.add_theme_constant_override("separation", page.get_theme_constant("separation"))
		for child in page.get_children():
			page.remove_child(child)
			editable.add_child(child)
		page.add_child(editable)
		_page_editables[section] = editable
		var block := VBoxContainer.new()
		block.name = "KeyboardReadOnly_%s" % section
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation", 10)
		block.visible = false
		var note := _label(KEYBOARD_READ_ONLY_NOTE, "CardTitle", true)
		note.name = "KeyboardReadOnlyNote_%s" % section
		block.add_child(note)
		block.add_child(_label("The keyboard uses the fixed layout shown in the picture. To edit a controller profile, select a gamepad or radio in the device list.", "SecondaryLabel", true))
		var keys := VBoxContainer.new()
		keys.name = "KeyboardKeys_%s" % section
		keys.add_theme_constant_override("separation", 8)
		block.add_child(keys)
		page.add_child(block)
		page.move_child(block, 0)
		_keyboard_blocks[section] = block


func _keyboard_vehicle_type() -> String:
	return ControlsReference.ROTORCRAFT if bool(action_capabilities.get("helicopter", false)) else ControlsReference.AIRPLANE


## The Flight axes page lists the flight keys and Buttons the shortcuts, from the shared reference table.
func _ensure_keyboard_tables() -> void:
	var vehicle := _keyboard_vehicle_type()
	if vehicle == _keyboard_tables_vehicle:
		return
	_keyboard_tables_vehicle = vehicle
	for section: String in PROFILE_SECTIONS:
		var keys := (_keyboard_blocks[section] as Node).get_node("KeyboardKeys_%s" % section) as VBoxContainer
		for child in keys.get_children():
			keys.remove_child(child)
			child.queue_free()
		match section:
			"axes":
				keys.add_child(_section_label("FLIGHT KEYS"))
				keys.add_child(_keyboard_table(ControlsReference.flight_table(vehicle)))
			"buttons":
				keys.add_child(_section_label("SHORTCUTS"))
				keys.add_child(_keyboard_table(ControlsReference.shortcut_table(vehicle)))


static func _keyboard_table(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for row: Array in rows:
		var caps := HFlowContainer.new()
		caps.add_theme_constant_override("h_separation", 4)
		caps.add_theme_constant_override("v_separation", 4)
		caps.custom_minimum_size.x = 150.0
		caps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for key: Variant in row[0]:
			caps.add_child(KeyCap.for_key(int(key) as Key))
		grid.add_child(caps)
		var what := _label(str(row[1]), "SecondaryLabel", true)
		what.custom_minimum_size.x = 0.0
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
	return grid


func _set_keyboard_mode(on: bool) -> void:
	if _keyboard_blocks.is_empty():
		return
	if on:
		_ensure_keyboard_tables()
	if on == _keyboard_mode:
		return
	_keyboard_mode = on
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for section: String in PROFILE_SECTIONS:
		(_page_editables[section] as Control).visible = not on
		(_keyboard_blocks[section] as Control).visible = on
	_resize_panel()
	_place_response_curve()
	if is_instance_valid(focused) and _screen.is_ancestor_of(focused) and not focused.is_visible_in_tree():
		(_section_buttons[_selected_section] as Control).grab_focus()


## UX-02: a small focusable "?" beside clipped text; keyboard, gamepad and pointer open the full text.
func _info_button(node_name: String, accessible: String) -> Button:
	var button := _button("?", "", node_name)
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size.x = 36.0
	button.set_meta("accessible_caption", accessible)
	button.tooltip_text = tr(accessible)
	button.accessibility_name = tr(accessible)
	return button


func _show_info(title: String, text: String, from: Control) -> void:
	if not is_inside_tree():
		return
	if _info_dialog == null:
		_info_dialog = AcceptDialog.new()
		_info_dialog.name = "ControllerInfoDialog"
		_info_dialog.dialog_autowrap = true
		_info_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_info_dialog.confirmed.connect(_restore_info_focus)
		_info_dialog.canceled.connect(_restore_info_focus)
		add_child(_info_dialog)
	_info_return_focus = from
	_info_dialog.title = title
	_info_dialog.dialog_text = text
	_info_dialog.get_ok_button().text = tr("Close")
	_info_dialog.popup_centered_clamped(Vector2i(640, 220), 0.9)
	_focus_if_shown.call_deferred(_info_dialog.get_ok_button())


## A question answered (or the screen closed) in the same frame must not take focus afterwards.
## Untyped: the control may have been freed (screen closed) before the deferred call runs.
static func _focus_if_shown(control: Variant) -> void:
	if is_instance_valid(control) and control is Control and control.is_inside_tree() and control.is_visible_in_tree():
		(control as Control).grab_focus()


func _restore_info_focus() -> void:
	var target := _info_return_focus
	_info_return_focus = null
	if is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree():
		_focus_if_shown.call_deferred(target)


## The footer shows one to three lines; "?" appears only when the message does not fit.
func _update_status_info_button() -> void:
	if status_info_button == null:
		return
	var clipped := status_label.visible and status_label.max_lines_visible > 0 \
		and status_label.get_line_count() > status_label.max_lines_visible
	if status_info_button.visible != clipped:
		var had_focus := status_info_button.has_focus()
		status_info_button.visible = clipped
		if had_focus and not clipped and save_button.is_visible_in_tree():
			save_button.grab_focus()


## UX-02 (A9): every per-row control names its action or channel, so assistive technology and the debug
## bridge never list dozens of identical "Clear", "Remap" or "Invert" entries.
func _update_accessible_names() -> void:
	for button: Button in [aux_help_info_button, device_summary_info_button, status_info_button, show_all_vehicle_aux]:
		if button != null:
			button.tooltip_text = tr(str(button.get_meta("accessible_caption", "")))
			button.accessibility_name = button.tooltip_text
	for channel: String in CHANNELS:
		var caption := tr(str(CHANNEL_LABELS[channel]))
		var controls: Dictionary = _axis_controls[channel]
		_name_control(controls.axis, tr("%s source axis") % caption)
		_name_control(controls.deadzone, tr("%s deadzone") % caption)
		_name_control(controls.expo, tr("%s expo") % caption)
		_name_control(controls.invert, tr("Invert %s") % caption)
		_name_control(_axis_detect_buttons[channel], tr("Detect %s axis") % caption)
	for aux_name: String in AUX_CHANNELS:
		var caption := tr(str(AUX_CHANNEL_LABELS[aux_name]))
		var controls: Dictionary = _aux_controls[aux_name]
		_name_control(controls.type, tr("%s input type") % caption)
		_name_control(controls.detect, tr("Move the control for %s") % caption)
		_name_control(controls.axis, tr("%s source axis") % caption)
		_name_control(controls.off, tr("%s Off endpoint") % caption)
		_name_control(controls.on, tr("%s On endpoint") % caption)
		_name_control(controls.invert, tr("Invert %s") % caption)
		_name_control(controls.button, tr("%s button") % caption)
		_name_control(controls.button_mode, tr("%s button mode") % caption)
		_name_control(controls.switch_count, tr("%s switch positions") % caption)
		_name_control(controls.switch_label, tr("%s switch name") % caption)
		_name_control(controls.switch_invert, tr("Reverse %s request") % caption)
		for row_index in 3:
			var position := "%s %s" % [caption, tr(_switch_position_name(row_index))]
			_name_control(controls.switch_button_spins[row_index], tr("%s button") % position)
			_name_control(controls.switch_capture_buttons[row_index], tr("Capture %s position") % position)
	for definition in ControllerActions.ACTIONS:
		var action_id := str(definition.id)
		var caption := tr(str(definition.label))
		_name_control(_clear_action_buttons[action_id], tr("Clear %s") % caption)
		_name_control(_axis_capture_buttons[action_id], tr("Learn axis for %s") % caption)
		var remap_button := action_grid.find_child("Remap_%s" % action_id, false, false) as Control
		if remap_button != null:
			_name_control(remap_button, tr("Remap %s") % caption)


static func _name_control(control: Control, accessible: String) -> void:
	control.accessibility_name = accessible
	# A SpinBox is edited through its inner LineEdit; name both so either reports the field.
	if control is SpinBox:
		(control as SpinBox).get_line_edit().accessibility_name = accessible


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


# --- UI-15-UX-05/06: capture overlay, axis detection, conflicts, search by input, reset -----------------------------

## A capture or a pending conflict question: either owns input, blocks Save, and navigation cancels it.
func _is_assignment_busy() -> bool:
	return _is_capture_active() or not _conflict.is_empty()


## Public (Setup assistant): start the capture a row's button would start. `target_id` is an action id,
## "aux:<channel>" (the channel's first capture slot: Move the control for an axis, the first position of a switch
## group), "axis:<channel>" (Detect) or "find". False when it cannot start now (keyboard selected, no connected
## controller for axes, a locked radio navigation row, a disabled or button-type AUX channel).
func start_capture_for(target_id: String) -> bool:
	if _draft_profile.is_empty() or _keyboard_mode:
		return false
	if target_id == "find":
		_start_find(find_aux_button if _selected_section == "aux" else find_actions_button)
		return _finding
	if target_id.begins_with("axis:"):
		var channel := target_id.trim_prefix("axis:")
		if not _axis_detect_buttons.has(channel):
			return false
		_start_axis_detect(channel, _axis_detect_buttons[channel])
		return _detect_channel == channel
	if target_id.begins_with("aux:"):
		var aux_name := target_id.trim_prefix("aux:")
		if not _aux_controls.has(aux_name):
			return false
		var binding := _draft_aux(aux_name)
		match str(binding.get("type", "")):
			"axis":
				_start_aux_axis_capture(aux_name, _aux_detect_buttons[aux_name])
				return _capturing_aux_axis == aux_name
			"switch":
				var rows := _switch_row_indices(SmokeAux.bound_buttons(binding).size())
				var slot := int(rows[0])
				_start_aux_capture(aux_name, slot, _aux_controls[aux_name].switch_capture_buttons[slot])
				return _capturing_aux_name == aux_name
		return false
	if ControllerActions.action_definition(target_id).is_empty():
		return false
	var remap := action_grid.find_child("Remap_%s" % target_id, false, false) as Button
	if remap == null or remap.disabled:
		return false
	_start_capture(target_id, remap)
	return _capturing_action == target_id


func _flight_device_connected() -> bool:
	return _draft_flight_device_id >= 0 and bool(_device_for_id(_draft_flight_device_id).get("connected", false))


func _registry_generation(device_id: int) -> int:
	if registry == null or not registry.has_method("connection_generation"):
		return 0
	return int(registry.connection_generation(device_id))


## The capturing controller is still the same connection (a registry without generations: still connected).
func _capture_connection_ok() -> bool:
	if _capturing_generation > 0:
		return _calibration_connection_matches(_capturing_device_id, _capturing_generation)
	return bool(_device_for_id(_capturing_device_id).get("connected", false))


func _glyph_family() -> String:
	var presentation: Variant = _draft_profile.get("presentation", {})
	return str(presentation.get("glyph_family", "auto")) if presentation is Dictionary else "auto"


func _chip_profile() -> Dictionary:
	return _draft_profile if str(_draft_profile.get("kind", "")) in ["radio", "joystick"] else {}


## "action:flaps_down" → “Flaps down”, "aux:smoke" → “Smoke”, "axis:roll" → “Roll”.
func _target_caption(target: String) -> String:
	var parts := target.split(":")
	if parts.size() != 2:
		return target
	match parts[0]:
		"action":
			var definition := ControllerActions.action_definition(parts[1])
			return tr(str(definition.get("label", parts[1])))
		"aux":
			return tr(str(AUX_CHANNEL_LABELS.get(parts[1], parts[1])))
		"axis":
			return tr(str(CHANNEL_LABELS.get(parts[1], parts[1])))
	return target


func _binding_caption(binding: Dictionary) -> String:
	var prompt: Dictionary = ControllerPrompts.prompt(binding, _glyph_family(), _device_for_id(_draft_flight_device_id), _draft_profile)
	var text := str(prompt.get("text", ""))
	return text if not text.is_empty() else ControllerActions.binding_text(binding)


## Overlay over the workspace for the capture that just started. `back_cancels`: the profile's Back button also
## cancels (axis detection, where buttons are not captured).
func _show_capture_overlay(title: String, prompt: String, back_cancels := false) -> void:
	if capture_overlay == null:
		return
	var bindings: Array = [{"type": "key", "physical_keycode": KEY_ESCAPE}]
	if back_cancels:
		var back: Dictionary = _action_bindings.get("back", {})
		if str(back.get("type", "")) == "button":
			bindings.append(back)
	var hint := tr("cancels. Listening stops after %d seconds without input.") % int(CAPTURE_SECONDS)
	capture_overlay.show_capture(title, prompt, hint, bindings, _glyph_family(), _device_for_id(_capturing_device_id),
		_chip_profile(), CAPTURE_SECONDS)


func _emit_capture_finished(target: String, ok: bool, message: String) -> void:
	if not target.is_empty():
		capture_finished.emit(target, ok, "" if ok else message)


## The last rejected attempt's sentence, as the footer shows it without the "Problem:" prefix.
func _rejection_text() -> String:
	if _rejected_message.is_empty():
		return status_label.text
	return tr(_rejected_message) % _friendly_validation_text(_rejected_issues, _rejected_errors)


func _on_capture_timeout() -> void:
	if not _is_capture_active():
		return
	var message := tr("No input was detected in time. Nothing changed.")
	_set_status(message, false)
	_capture_done(false, message)


func _on_capture_event(event: InputEvent) -> void:
	if _finding:
		_find_by_event(event)
	else:
		_capture_binding(event)


# Flight-axis detection (UX-05) --------------------------------------------------------------------------------------

func _start_axis_detect(channel: String, button: Button) -> void:
	if not _axis_controls.has(channel) or _draft_profile.is_empty():
		return
	if _is_assignment_busy(): _capture_done()
	if not _flight_device_connected():
		_set_status(tr("Connect the flight controller to detect its axes."), true)
		return
	if _selected_section != "axes":
		select_section("axes")
	_capturing_device_id = _draft_flight_device_id
	_capturing_generation = _registry_generation(_capturing_device_id)
	var detector := AxisDetector.new()
	if not detector.begin(_capture_axes()):
		_capturing_device_id = -1
		_capturing_generation = 0
		_set_status(tr("Invalid or interrupted input. Nothing changed."), true)
		return
	_axis_detector = detector
	_detect_channel = channel
	_detect_preview_axis = -1
	_capture_target = "axis:" + channel
	_capture_button = button
	if button.is_visible_in_tree():
		button.grab_focus()
	var prompt := tr(str(DETECT_PROMPTS[channel]))
	_set_status(prompt, false)
	_show_capture_overlay(tr("Detect %s") % _target_caption("axis:" + channel), prompt, true)
	_update_axis_controls()


## Keys and the capturing controller's events belong to detection (axes are polled); Escape or the profile's Back
## button cancels and its release is consumed.
func _input_axis_detect(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE):
			_track_capture_release(key)
			_cancel_capture()
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion) or event.device != _capturing_device_id:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var back: Dictionary = _action_bindings.get("back", {})
		if str(back.get("type", "")) == "button" and int(back.get("button", -1)) == int((event as InputEventJoypadButton).button_index):
			_track_capture_release(event)
			_cancel_capture()


func _sample_axis_detect(delta: float) -> void:
	if not _capture_connection_ok():
		_set_status(tr("The selected flight controller disconnected; remapping was cancelled."), true)
		_capture_done(false, tr("The selected flight controller disconnected; remapping was cancelled."))
		return
	var axes := _capture_axes()
	var result: Dictionary = _axis_detector.sample(axes, delta)
	if result.has("error"):
		var message := tr(str(result.error))
		_set_status(message, true)
		_capture_done(false, message)
		return
	if result.has("axis"):
		_finish_axis_detect(int(result.axis), bool(result.negative), axes)
		return
	var lead := int(result.get("candidate", -1))
	if lead == _detect_preview_axis:
		return
	_detect_preview_axis = lead
	if lead >= 0:
		capture_overlay.set_preview({"type": "axis", "axis": lead}, tr("Axis %d") % lead)
		workspace.set_capture_control("axis:%d" % lead)
	else:
		capture_overlay.clear_preview()
		workspace.set_capture_control("")


func _finish_axis_detect(axis: int, negative: bool, axes: PackedFloat64Array) -> void:
	var channel := _detect_channel
	var target := _capture_target
	var return_focus := _capture_button
	var baseline := _axis_detector.baseline[axis] if axis < _axis_detector.baseline.size() else 0.0
	# A stick held away from a centred rest is released after detection; that release is not navigation.
	if absf(baseline) <= CAPTURE_AXIS_RELEASE_THRESHOLD and axis < axes.size() and absf(axes[axis]) >= 0.65:
		var motion := InputEventJoypadMotion.new()
		motion.device = _capturing_device_id
		motion.axis = axis as JoyAxis
		var token := _event_release_token(motion)
		if not token.is_empty():
			_capture_release_tokens[token] = true
	var previous: Dictionary = _draft_profile.get(channel, {})
	var updated := previous.duplicate(true)
	updated["axis"] = axis
	updated["invert"] = negative
	var candidate := _draft_profile.duplicate(true)
	candidate[channel] = updated
	var caption := _target_caption("axis:" + channel)
	var success := tr("%s uses axis %d. Save the profile to keep it.") % [caption, axis]
	if negative:
		success += " " + tr("It moved the other way, so %s is inverted.") % caption
	if str(_draft_profile.get("kind", "")) == "radio":
		success += " " + tr("Calibrate the radio again before saving.")
	var owners := _axis_owners(candidate, channel, axis)
	_end_capture_state()
	if owners.is_empty():
		_commit_candidate_profile(candidate)
		_set_status(success, false)
		_emit_capture_finished(target, true, "")
		return
	if owners.size() > 1:
		var names: Array[String] = []
		for owner: String in owners:
			names.append("“%s”" % _target_caption(owner))
		var message := tr("Axis %d is already used by %s. Nothing changed.") % [axis, ", ".join(names)]
		_set_status(message, true)
		_emit_capture_finished(target, false, message)
		return
	_offer_conflict({"target": "axis:" + channel, "report": target, "owner": owners[0], "candidate": candidate,
		"binding": {"type": "axis", "axis": axis}, "previous": int(previous.get("axis", -1)), "focus": return_focus,
		"success": success, "cancel_message": tr("%s keeps its axis. Nothing changed.") % caption})


## Other users of a raw axis: flight channels, AUX axis channels and flight actions learned on an axis.
func _axis_owners(profile: Dictionary, channel: String, axis: int) -> Array[String]:
	var owners: Array[String] = []
	for other: String in CHANNELS:
		var data: Variant = profile.get(other, {})
		if other != channel and data is Dictionary and int(data.get("axis", -1)) == axis:
			owners.append("axis:" + other)
	var aux: Variant = profile.get("aux", {})
	if aux is Dictionary:
		for aux_name: String in AUX_CHANNELS:
			var binding: Variant = aux.get(aux_name, {})
			if binding is Dictionary and str(binding.get("type", "")) == "axis" and int(binding.get("axis", -1)) == axis:
				owners.append("aux:" + aux_name)
	for definition in ControllerActions.ACTIONS:
		var binding: Dictionary = _action_bindings.get(str(definition.id), {})
		if str(definition.context) in ["flight", "both"] and str(binding.get("type", "")) == "axis" and int(binding.get("axis", -1)) == axis:
			owners.append("action:" + str(definition.id))
	return owners


func _draft_aux(aux_name: String) -> Dictionary:
	var aux: Variant = _draft_profile.get("aux", {})
	if aux is Dictionary and aux.get(aux_name, {}) is Dictionary:
		return (aux.get(aux_name, {}) as Dictionary).duplicate(true)
	return {}


## AUX "Move the control" result: the channel's axis with the measured OFF and ON endpoints.
func _accept_aux_axis_binding(learned: Dictionary) -> void:
	var aux_name := _capturing_aux_axis
	var target := _capture_target
	var return_focus := _capture_button
	var off := float(learned.get("off", -1.0))
	var on := float(learned.get("on", 1.0))
	var binding := {"type": "axis", "axis": int(learned.get("axis", 0)), "off": off, "on": on, "invert": on < off}
	var previous := _draft_aux(aux_name)
	var candidate := _draft_profile.duplicate(true)
	var aux: Dictionary = (candidate.get("aux", {}) as Dictionary).duplicate(true) if candidate.get("aux", {}) is Dictionary else {}
	aux[aux_name] = binding
	candidate["aux"] = aux
	var validation: Dictionary = ControllerActions.validate_profile_bindings(candidate, action_capabilities)
	var caption := _target_caption("aux:" + aux_name)
	var success := tr("%s uses axis %d (Off %+.2f, On %+.2f). Save the profile to keep it.") % [caption, int(binding.axis), off, on]
	_end_capture_state()
	if bool(validation.get("ok", false)):
		_commit_candidate_profile(candidate)
		_set_status(success, false)
		_emit_capture_finished(target, true, "")
		return
	var owner := _single_conflict_owner(validation.get("issues", []), "aux:" + aux_name)
	if not owner.is_empty():
		_offer_conflict({"target": "aux:" + aux_name, "report": target, "owner": owner, "candidate": candidate,
			"binding": binding, "previous": previous, "rejected": validation,
			"rejected_message": "Extra channel was not changed: %s", "focus": return_focus, "success": success})
		return
	_show_rejected_validation(validation, "Extra channel was not changed: %s")
	_emit_capture_finished(target, false, _rejection_text())


# Conflicts (UX-06) --------------------------------------------------------------------------------------------------

## "action:x", "aux:y" or "axis:z" for a validation path ("actions.x", "aux.y.button", "roll.axis").
func _path_owner(path: String) -> String:
	var parts := path.split(".")
	if parts.size() >= 2 and parts[0] == "actions":
		return "action:" + parts[1]
	if parts.size() >= 2 and parts[0] == "aux":
		return "aux:" + parts[1]
	if parts[0] in CHANNELS:
		return "axis:" + parts[0]
	return ""


## The one action or extra channel whose same-control conflict is the only reason `target` was rejected, or "".
func _single_conflict_owner(issues: Array, target: String) -> String:
	var owners: Dictionary = {}
	for issue: Variant in issues:
		if not issue is Dictionary:
			return ""
		if not str(issue.get("code", "")) in SWAPPABLE_CONFLICT_CODES:
			return ""
		var ids: Array[String] = []
		for path: Variant in issue.get("paths", []):
			ids.append(_path_owner(str(path)))
		if not ids.has(target):
			return ""
		for id: String in ids:
			if id != target and not id.is_empty():
				owners[id] = true
	return str(owners.keys()[0]) if owners.size() == 1 else ""


## Show "<control> is already used by <owner>" with Swap / Replace / Cancel over the workspace. Both choices are
## whole draft candidates validated now; an invalid one is disabled with its reason. Nothing changes until a choice.
func _offer_conflict(request: Dictionary) -> void:
	var target := str(request.target)
	var owner := str(request.owner)
	var swap := _swap_candidate(target, owner, request.candidate, request.binding, request.get("previous"))
	var replace := _replace_candidate(target, owner, request.candidate)
	_conflict = request.duplicate()
	_conflict["swap"] = swap.get("profile", {})
	_conflict["replace"] = replace.get("profile", {})
	var target_caption := "“%s”" % _target_caption(target)
	var owner_caption := "“%s”" % _target_caption(owner)
	var control_caption := _binding_caption(request.binding)
	var question := tr("%s is already used by %s.") % [control_caption, owner_caption]
	_conflict["question"] = question
	capture_overlay.show_conflict({
		"title": tr("Assign to %s") % target_caption,
		"text": question,
		"details": "%s\n%s" % [_swap_detail(owner_caption, target_caption, request.get("previous")),
			tr("Replace: %s loses this control.") % owner_caption],
		"binding": request.binding, "family": _glyph_family(), "device": _device_for_id(_draft_flight_device_id),
		"profile": _chip_profile(), "swap_reason": str(swap.get("reason", "")), "replace_reason": str(replace.get("reason", "")),
	})
	_set_status(question + " " + tr("Choose Swap, Replace or Cancel."), false)


func _swap_detail(owner_caption: String, target_caption: String, previous: Variant) -> String:
	var given := ""
	if previous is Dictionary and str((previous as Dictionary).get("type", "unbound")) != "unbound":
		given = _binding_caption(previous)
	elif (previous is int or previous is float) and int(previous) >= 0:
		given = tr("Axis %d") % int(previous)
	if given.is_empty():
		return tr("Swap: %s takes the control %s had.") % [owner_caption, target_caption]
	return tr("Swap: %s gets %s, the control %s had.") % [owner_caption, given, target_caption]


func _swap_candidate(target: String, owner: String, candidate: Dictionary, binding: Dictionary, previous: Variant) -> Dictionary:
	var t := target.split(":")
	var o := owner.split(":")
	var profile := candidate.duplicate(true)
	if _radio_navigation_owner(owner):
		return {"reason": tr("Radio menu movement uses the calibrated roll and pitch controls.")}
	if t[0] == "axis":
		if o[0] != "axis" or int(previous) < 0:
			return {"reason": tr("Only another flight channel can take an axis in exchange.")}
		var other: Dictionary = (profile.get(o[1], {}) as Dictionary).duplicate(true)
		other["axis"] = int(previous)
		profile[o[1]] = other
		return _checked_axis_candidate(profile)
	var given: Dictionary = previous if previous is Dictionary else {}
	if given.is_empty() or str(given.get("type", "unbound")) == "unbound":
		return {"reason": tr("“%s” has no control to give in exchange.") % _target_caption(target)}
	if o[0] == "action" and t[0] == "action":
		var actions: Dictionary = (profile.get("actions", {}) as Dictionary).duplicate(true)
		actions[o[1]] = given.duplicate(true)
		profile["actions"] = actions
	elif o[0] == "aux":
		var aux: Dictionary = (profile.get("aux", {}) as Dictionary).duplicate(true)
		var other: Dictionary = (aux.get(o[1], {}) as Dictionary).duplicate(true)
		if t[0] == "aux":
			other = given.duplicate(true)
		elif str(other.get("type", "")) == "button" and str(given.get("type", "")) == "button":
			other["button"] = int(given.button)
		elif str(other.get("type", "")) == "switch" and str(given.get("type", "")) == "button" \
				and str(binding.get("type", "")) == "button":
			var buttons: Array = (other.get("buttons", []) as Array).duplicate()
			var member := buttons.find(int(binding.button))
			if member < 0:
				return {"reason": tr("The %s extra channel cannot use that kind of control.") % _target_caption(owner)}
			buttons[member] = int(given.button)
			other["buttons"] = buttons
		else:
			return {"reason": tr("The %s extra channel cannot use that kind of control.") % _target_caption(owner)}
		aux[o[1]] = other
		profile["aux"] = aux
	else:
		return {"reason": tr("“%s” cannot take that kind of control. Use Replace or Cancel.") % _target_caption(owner)}
	return _checked_binding_candidate(profile)


## Radio navigation rows stay locked to the calibrated sticks: a conflict never rewrites them.
func _radio_navigation_owner(owner: String) -> bool:
	return str(_draft_profile.get("kind", "")) == "radio" and owner.begins_with("action:navigate_")


func _replace_candidate(target: String, owner: String, candidate: Dictionary) -> Dictionary:
	var o := owner.split(":")
	var profile := candidate.duplicate(true)
	if _radio_navigation_owner(owner):
		return {"reason": tr("Radio menu movement uses the calibrated roll and pitch controls.")}
	match o[0]:
		"axis":
			return {"reason": tr("Every flight channel needs its own axis.")}
		"action":
			if o[1] in ["back", "pause"]:
				return {"reason": tr("“%s” must always keep a control.") % _target_caption(owner)}
			var actions: Dictionary = (profile.get("actions", {}) as Dictionary).duplicate(true)
			actions[o[1]] = {"type": "unbound"}
			profile["actions"] = actions
		"aux":
			var aux: Dictionary = (profile.get("aux", {}) as Dictionary).duplicate(true)
			aux.erase(o[1])
			if aux.is_empty():
				profile.erase("aux")
			else:
				profile["aux"] = aux
		_:
			return {"reason": tr("Replace is not available here.")}
	return _checked_axis_candidate(profile) if target.begins_with("axis:") else _checked_binding_candidate(profile)


func _checked_binding_candidate(profile: Dictionary) -> Dictionary:
	var validation: Dictionary = ControllerActions.validate_profile_bindings(profile, action_capabilities)
	if bool(validation.get("ok", false)):
		return {"profile": profile}
	return {"reason": _friendly_validation_text(validation.get("issues", []), validation.get("errors", []))}


## A flight-channel candidate may not add problems the current draft does not already have.
func _checked_axis_candidate(profile: Dictionary) -> Dictionary:
	var known: Dictionary = {}
	for issue: Dictionary in _validate_candidate(_named_candidate(_draft_profile)).get("issues", []):
		known[str(issue.code) + str(issue.paths)] = true
	var fresh: Array = []
	for issue: Dictionary in _validate_candidate(_named_candidate(profile)).get("issues", []):
		if not known.has(str(issue.code) + str(issue.paths)):
			fresh.append(issue)
	return {"profile": profile} if fresh.is_empty() else {"reason": _friendly_validation_text(fresh, [])}


func _named_candidate(profile: Dictionary) -> Dictionary:
	var candidate := profile.duplicate(true)
	candidate["name"] = profile_name_edit.text.strip_edges()
	return candidate


## Swap and Replace commit their candidate atomically; Cancel (or Back/Escape) keeps the draft and reports the
## attempt like a rejected remap.
func _resolve_conflict(choice: String) -> void:
	if _conflict.is_empty():
		return
	var request := _conflict
	_conflict = {}
	capture_overlay.hide_overlay()
	var report := str(request.get("report", ""))
	var profile: Dictionary = request.get(choice, {}) if choice in ["swap", "replace"] else {}
	if not profile.is_empty():
		_commit_candidate_profile(profile)
		var owner_caption := "“%s”" % _target_caption(str(request.owner))
		var note := tr("%s took the previous control.") % owner_caption if choice == "swap" \
			else tr("%s no longer uses this control.") % owner_caption
		_set_status("%s %s" % [str(request.success), note], false)
		_restore_conflict_focus(request.get("focus"))
		_emit_capture_finished(report, true, "")
		return
	var message := ""
	var rejected: Dictionary = request.get("rejected", {})
	if not rejected.is_empty():
		_show_rejected_validation(rejected, str(request.get("rejected_message", "Binding was not changed: %s")))
		message = _rejection_text()
	else:
		message = str(request.get("cancel_message", tr("Nothing changed.")))
		_set_status(message, false)
	_restore_conflict_focus(request.get("focus"))
	_emit_capture_finished(report, false, message)


## A pending question ends without a choice (navigation, device change, a new capture, close): nothing changes.
func _drop_conflict(reason: String) -> void:
	if _conflict.is_empty():
		return
	var report := str(_conflict.get("report", ""))
	_conflict = {}
	capture_overlay.hide_overlay()
	_emit_capture_finished(report, false, reason)


func _restore_conflict_focus(target: Variant) -> void:
	if is_instance_valid(target) and target is Control and (target as Control).is_visible_in_tree() \
			and (target as Control).focus_mode != Control.FOCUS_NONE:
		(target as Control).grab_focus()


## One draft write for a whole candidate (conflict choices, detection, reset): actions, AUX and channels together.
func _commit_candidate_profile(profile: Dictionary) -> void:
	_draft_profile = profile.duplicate(true)
	_base_actions = (_draft_profile.get("actions", {}) as Dictionary).duplicate(true) if _draft_profile.get("actions", {}) is Dictionary else {}
	_draft_profile["actions"] = _base_actions.duplicate(true)
	_action_bindings = ControllerActions.effective_bindings(_draft_profile, action_capabilities)
	_update_axis_controls()
	_update_aux_controls()
	_update_action_controls()
	_update_preview()
	_draft_validation_changed()


# Search by input (UX-06) --------------------------------------------------------------------------------------------

func _start_find(button: Button) -> void:
	if _draft_profile.is_empty() or _keyboard_mode:
		return
	if _is_assignment_busy(): _capture_done()
	_find_origin = _selected_section
	_finding = true
	_capturing_device_id = _draft_flight_device_id
	_capturing_generation = _registry_generation(_capturing_device_id)
	_find_baseline = _capture_axes()
	_capture_button = button
	_capture_target = "find"
	if button != null and button.is_visible_in_tree():
		button.grab_focus()
	var prompt := tr("Press or move any control to find what it does.")
	_set_status(prompt, false)
	_show_capture_overlay(tr("Find control"), prompt)


func _event_control_id(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		return "key:%d" % (int(key.physical_keycode) if key.physical_keycode != KEY_NONE else int(key.keycode))
	if event is InputEventJoypadButton:
		return "button:%d" % int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		return "axis:%d" % int((event as InputEventJoypadMotion).axis)
	return ""


## Reveal (including other vehicles' rows), scroll to and focus the rows the pressed control drives.
func _find_by_event(event: InputEvent) -> void:
	var control_id := _event_control_id(event)
	var caption := _binding_caption(ControllerActions.binding_from_event(event))
	var radio := str(_draft_profile.get("kind", "")) == "radio"
	var actions: Array[String] = []
	for definition in ControllerActions.ACTIONS:
		var action_id := str(definition.id)
		if radio and action_id.begins_with("navigate_"):
			continue
		if _binding_control_ids(_action_bindings.get(action_id, {})).has(control_id):
			actions.append(action_id)
	var aux_rows: Array[String] = []
	for aux_name: String in AUX_CHANNELS:
		if _binding_control_ids(_draft_aux(aux_name)).has(control_id):
			aux_rows.append(aux_name)
	var channels: Array[String] = []
	for channel: String in CHANNELS:
		var data: Variant = _draft_profile.get(channel, {})
		if data is Dictionary and control_id == "axis:%d" % int(data.get("axis", -1)):
			channels.append(channel)
	var origin := _find_origin
	var return_focus := _capture_button
	_end_capture_state()
	get_viewport().set_input_as_handled()
	if actions.is_empty() and aux_rows.is_empty() and channels.is_empty():
		var missing := tr("%s is not assigned.") % caption
		_set_status(missing, false)
		_restore_conflict_focus(return_focus)
		_emit_capture_finished("find", false, missing)
		return
	var names: Array[String] = []
	for action_id: String in actions:
		names.append("“%s”" % _target_caption("action:" + action_id))
	for aux_name: String in aux_rows:
		names.append("“%s”" % _target_caption("aux:" + aux_name))
	for channel: String in channels:
		names.append("“%s”" % _target_caption("axis:" + channel))
	var focus_target: Control
	if not aux_rows.is_empty() and (origin == "aux" or actions.is_empty()):
		focus_target = _reveal_found_aux(aux_rows)
	elif not actions.is_empty():
		focus_target = _reveal_found_actions(actions)
	else:
		select_section("axes")
		focus_target = _axis_detect_buttons[channels[0]]
	_set_status(tr("%s is used by %s.") % [caption, ", ".join(names)], false)
	if focus_target != null and focus_target.is_visible_in_tree():
		focus_target.grab_focus()
		_ensure_whole_control_visible.call_deferred(focus_target)
		_queue_mapping_focus_visibility()
	_emit_capture_finished("find", true, "")


func _reveal_found_actions(actions: Array[String]) -> Control:
	if _selected_section != "buttons":
		select_section("buttons")
	for action_id: String in actions:
		_reveal_action_row(action_id)
	var remap := action_grid.find_child("Remap_%s" % actions[0], false, false) as Button
	return remap if remap != null and not remap.disabled else _binding_chips.get(actions[0])


func _reveal_found_aux(aux_rows: Array[String]) -> Control:
	if _selected_section != "aux":
		select_section("aux")
	for aux_name: String in aux_rows:
		if not _aux_row_shown(aux_name):
			show_all_vehicle_aux.set_pressed_no_signal(true)
			_update_aux_controls()
	return _aux_controls[aux_rows[0]].type


# Reset to defaults (UX-06) ------------------------------------------------------------------------------------------

## Ask before resetting `category` (the action filter index: 0 = every action, 1–4 = Flight, Camera, Auxiliary, Menu).
func _ask_reset_actions(category: int, from: Control) -> void:
	if _draft_profile.is_empty() or _is_assignment_busy():
		return
	_reset_scope = category
	_reset_return_focus = from
	if reset_dialog == null:
		reset_dialog = ConfirmationDialog.new()
		reset_dialog.name = "ResetActionsDialog"
		reset_dialog.dialog_autowrap = true
		reset_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		reset_dialog.confirmed.connect(func() -> void:
			reset_actions(_reset_scope)
			_restore_reset_focus())
		reset_dialog.canceled.connect(_restore_reset_focus)
		add_child(reset_dialog)
	reset_dialog.title = tr("Reset to defaults")
	if category <= 0:
		reset_dialog.dialog_text = tr("Reset every action to its default control? Back and Pause always keep a control. The change stays in the draft until you Save.")
	else:
		reset_dialog.dialog_text = tr("Reset the %s actions shown to their default controls? Back and Pause always keep a control. The change stays in the draft until you Save.") % tr(action_filter.get_item_text(category))
	reset_dialog.get_ok_button().text = tr("Reset")
	reset_dialog.get_ok_button().name = "ConfirmResetActions"
	reset_dialog.get_cancel_button().text = tr("Keep")
	reset_dialog.popup_centered_clamped(Vector2i(620, 200), 0.9)
	_focus_if_shown.call_deferred(reset_dialog.get_cancel_button())


func _restore_reset_focus() -> void:
	var target := _reset_return_focus
	_reset_return_focus = null
	if is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree():
		_focus_if_shown.call_deferred(target)


## Draft only. Category 0 resets every action; 1–4 the rows of that category shown now (the vehicle filter
## applies). Radio and JETI profiles reset to the safe radio map; radio navigation stays locked to the sticks.
func reset_actions(category: int) -> bool:
	if _draft_profile.is_empty() or _is_assignment_busy():
		return false
	var candidate := _base_actions.duplicate(true)
	var clean: Dictionary = ControllerActions.clean_radio_bindings() if _supports_clean_radio_actions(_draft_profile) else {}
	var radio := str(_draft_profile.get("kind", "")) == "radio"
	for definition in ControllerActions.ACTIONS:
		var action_id := str(definition.id)
		if category > 0 and (_action_category(definition) != category or not _action_row_shown(definition)):
			continue
		if radio and action_id.begins_with("navigate_"):
			continue
		if clean.is_empty():
			candidate.erase(action_id)
		else:
			candidate[action_id] = (clean.get(action_id, {"type": "unbound"}) as Dictionary).duplicate(true)
	var profile := _draft_profile.duplicate(true)
	profile["actions"] = candidate
	var validation: Dictionary = ControllerActions.validate_profile_bindings(profile, action_capabilities)
	if not bool(validation.get("ok", false)):
		_show_rejected_validation(validation, "Actions were not reset: %s")
		return false
	_commit_candidate_profile(profile)
	_set_status(tr("Actions are back to their defaults in the draft. Save keeps them; Cancel discards them."), false)
	return true


# Advanced disclosure and the response curve placement (UX-05) ------------------------------------------------------

func _apply_advanced_visibility() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var axes_open := axis_advanced_toggle.button_pressed
	for channel: String in CHANNELS:
		(_axis_controls[channel].axis as Control).visible = axes_open
	var aux_open := aux_advanced_toggle.button_pressed
	for aux_name: String in AUX_CHANNELS:
		for field: Control in _aux_controls[aux_name].advanced_fields:
			field.visible = aux_open
	if is_instance_valid(focused) and _screen.is_ancestor_of(focused) and not focused.is_visible_in_tree():
		(axis_advanced_toggle if _selected_section == "axes" else aux_advanced_toggle).grab_focus()
	_queue_mapping_focus_visibility()


## A validation error or focus request on a number inside a closed Advanced disclosure opens it.
func _open_advanced_for(control: Control) -> void:
	if control == null or not control.has_meta("advanced_page"):
		return
	var toggle := axis_advanced_toggle if str(control.get_meta("advanced_page")) == "axes" else aux_advanced_toggle
	if not toggle.button_pressed:
		toggle.set_pressed_no_signal(true)
		_apply_advanced_visibility()


## The response curve is drawn large in the picture panel on Flight axes; where the panel is folded away (compact
## canvases) it stays with the gimbals on the page.
func _place_response_curve() -> void:
	if _response_curve == null or workspace == null or _axis_live_views == null:
		return
	if workspace.picture_panel.visible and _selected_section == "axes" and not _keyboard_mode:
		workspace.set_context(_response_curve)
		return
	workspace.set_context(null)
	if _response_curve.get_parent() != _axis_live_views:
		if _response_curve.get_parent() != null:
			_response_curve.get_parent().remove_child(_response_curve)
		_axis_live_views.add_child(_response_curve)

## UI-15-UX-05: "move the stick you want for Roll". Pure detection over raw axis samples, using the radio wizard's
## movement thresholds (rc_calibration.gd): an axis must move MIN_SWEEP from the baseline sampled when detection
## starts and stay there for HOLD_SECONDS; the largest deviation wins; a second axis that moved OTHER_AXIS_THRESHOLD
## (or two axes past MIN_SWEEP at once) makes it ambiguous; deviations under DIRECTION_THRESHOLD are noise and never
## count, so a jittering axis (a radio throttle resting at an endpoint) can neither win nor end detection.
## A pure helper beside rc_calibration.gd in app/input would be cleaner (input owner, D6-UX); kept here for UX-05.
class AxisDetector extends RefCounted:
	const Thresholds := preload("res://input/rc_calibration.gd")
	const HOLD_SECONDS := 0.25
	const AMBIGUOUS := "More than one axis moved. Move only the stick you want, then try again."
	const INVALID := "Invalid or interrupted input. Nothing changed."

	var baseline := PackedFloat64Array()
	var peaks := PackedFloat64Array()
	var leader := -1
	var held := 0.0

	func begin(axes: PackedFloat64Array) -> bool:
		if not _valid(axes):
			return false
		baseline = axes.duplicate()
		peaks.resize(axes.size())
		peaks.fill(0.0)
		leader = -1
		held = 0.0
		return true

	## {} while waiting, {candidate: axis} while one axis leads, {axis, negative} when done, {error} when rejected.
	func sample(axes: PackedFloat64Array, delta: float) -> Dictionary:
		if baseline.is_empty() or axes.size() != baseline.size() or not _valid(axes):
			return {error = INVALID}
		var step := delta if is_finite(delta) and delta > 0.0 and delta <= 1.0 else 0.0
		var lead := -1
		var lead_size := 0.0
		var moving := 0
		for axis in axes.size():
			var size := absf(axes[axis] - baseline[axis])
			if size < Thresholds.DIRECTION_THRESHOLD:
				continue
			peaks[axis] = maxf(peaks[axis], size)
			if size >= Thresholds.MIN_SWEEP:
				moving += 1
			if size > lead_size:
				lead = axis
				lead_size = size
		if moving > 1:
			return {error = AMBIGUOUS}
		if lead < 0 or lead_size < Thresholds.MIN_SWEEP:
			held = 0.0
			leader = -1
			return {candidate = lead} if lead >= 0 else {}
		if lead != leader:
			leader = lead
			held = 0.0
		held += step
		if held < HOLD_SECONDS:
			return {candidate = lead}
		for axis in peaks.size():
			if axis != lead and peaks[axis] >= Thresholds.OTHER_AXIS_THRESHOLD:
				return {error = AMBIGUOUS}
		return {axis = lead, negative = axes[lead] < baseline[lead]}

	static func _valid(axes: PackedFloat64Array) -> bool:
		if axes.is_empty():
			return false
		for value: float in axes:
			if not is_finite(value) or absf(value) > 1.0:
				return false
		return true
