extends VBoxContainer
## Progressive lighting editor. The Workshop owns validation and shared history.

const Profile := preload("res://render/lighting/lighting_profile.gd")
const Widgets := preload("res://ui/widgets.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Sequence := preload("res://workshop/lighting_sequence.gd")
const SequenceEditor := preload("res://ui/workshop_lighting_sequence.gd")

signal profile_changed(profile: Dictionary)
signal validity_changed(page: String, pending: bool)

const PATTERN_IDS := ["steady", "breath", "pulse", "chase", "wave", "rainbow", "segments", "sequence"]
const EFFECT_KIND_IDS := ["spark", "trail", "burst"]
const ZONE_LABELS := {
	"nav_left": "Port navigation", "nav_right": "Starboard navigation", "nav_tail": "Tail light",
	"strobe_left": "Port strobe", "strobe_right": "Starboard strobe", "strobe_dorsal": "Dorsal spine",
	"strobe_ventral": "Ventral bars", "strip_left": "Port wing strip", "strip_right": "Starboard wing strip",
	"strip_top_left": "Port upper strip", "strip_top_right": "Starboard upper strip", "strip_belly": "Belly strip",
	"landing_lamp": "Landing lamp",
}

var _sequence_editor: VBoxContainer
var _bindings: Dictionary = {}
var _presentation: Dictionary = {}
var _profile: Dictionary = {}
var _syncing := false
var _configuration_reusable := false
var _preset: OptionButton
var _enabled: CheckButton
var _brightness: HSlider
var _brightness_value: Label
var _brightness_timer: Timer
var _brightness_pending := false
var _summary: Label
var _capability_report: Dictionary = {}
var _availability: Label
var _availability_button: Button
var _availability_details: Label
var _zone_availability: Label
var _status: Label
var _orientation_lock: CheckButton
var _orientation_hint: Label
var _zone_button: Button
var _zone_section: VBoxContainer
var _zone_selector: OptionButton
var _zone_enabled: CheckButton
var _zone_brightness: HSlider
var _zone_brightness_value: Label
var _palette_list: VBoxContainer
var _add_color_button: Button
var _pattern_selector: OptionButton
var _pattern_hint: Label
var _period: SpinBox
var _period_readout: Label
var _reactive_selector: OptionButton
var _reactive_gain: SpinBox
var _reactive_hint: Label
var _zone_apply: Button
var _zone_cancel: Button
var _zone_reset: Button
var _more_effects_button: Button
var _effects_section: VBoxContainer
var _effects_controls: VBoxContainer
var _effects_apply: Button
var _effects_cancel: Button
var _selected_zone_id := ""
var _zone_draft: Dictionary = {}
var _zone_pending := false
var _zone_text_pending := false
var _zone_text_invalid := false
var _zone_hex_fields: Array[LineEdit] = []
var _effects_draft: Array[Dictionary] = []
var _effects_pending := false
var _effects_controls_by_anchor: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_build_ui()


func _build_ui() -> void:
	var title := Label.new()
	title.text = tr("Lighting")
	title.theme_type_variation = "CardTitle"
	add_child(title)
	var note := Label.new()
	note.text = tr("Choose a lighting style for this build. Preview time of day is temporary and does not change trial conditions.")
	note.theme_type_variation = "SecondaryLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var style_label := Label.new()
	style_label.text = tr("Lighting style")
	style_label.theme_type_variation = "SectionLabel"
	style_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(style_label)
	_preset = OptionButton.new()
	_preset.name = "LightingPreset"
	_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset.fit_to_longest_item = false
	_preset.clip_text = true
	_preset.add_item(tr("Use aircraft default"))
	_preset.set_item_metadata(0, "inherit")
	for preset_id: String in Profile.PRESET_IDS:
		_preset.add_item(tr(Profile.label(preset_id)))
		_preset.set_item_metadata(_preset.item_count - 1, preset_id)
	_preset.item_selected.connect(_on_preset_selected)
	add_child(_preset)
	_enabled = CheckButton.new()
	_enabled.name = "LightingEnabled"
	_enabled.text = tr("Lighting enabled")
	_enabled.toggled.connect(_on_enabled_toggled)
	add_child(_enabled)
	var brightness_row := HBoxContainer.new()
	var brightness_label := Label.new()
	brightness_label.text = tr("Brightness")
	brightness_label.theme_type_variation = "SecondaryLabel"
	brightness_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brightness_row.add_child(brightness_label)
	_brightness_value = Label.new()
	_brightness_value.custom_minimum_size.x = 58
	_brightness_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brightness_row.add_child(_brightness_value)
	add_child(brightness_row)
	_brightness = HSlider.new()
	_brightness.name = "LightingBrightness"
	_brightness.min_value = 0.0
	_brightness.max_value = 2.0
	_brightness.step = 0.01
	_brightness.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brightness.value_changed.connect(_on_brightness_changed)
	_brightness.drag_ended.connect(func(_changed: bool) -> void: _commit_brightness())
	add_child(_brightness)
	_brightness_timer = Timer.new()
	_brightness_timer.one_shot = true
	_brightness_timer.wait_time = 0.28
	_brightness_timer.timeout.connect(_commit_brightness)
	add_child(_brightness_timer)
	_summary = Label.new()
	_summary.name = "LightingSummary"
	_summary.theme_type_variation = "SecondaryLabel"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_availability = Label.new()
	_availability.name = "LightingAvailability"
	_availability.theme_type_variation = "SecondaryLabel"
	_availability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_availability)
	_availability_button = Button.new()
	_availability_button.name = "LightingSupportDetails"
	_availability_button.text = tr("View aircraft support")
	_availability_button.toggle_mode = true
	add_child(_availability_button)
	_availability_details = Label.new()
	_availability_details.name = "LightingSupportList"
	_availability_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_availability_details.visible = false
	add_child(_availability_details)
	_availability_button.toggled.connect(func(open: bool) -> void: _availability_details.visible = open)
	add_child(HSeparator.new())
	var details_label := Label.new()
	details_label.text = tr("Detailed lighting")
	details_label.theme_type_variation = "SectionLabel"
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(details_label)
	_zone_button = Button.new()
	_zone_button.name = "CustomizeLightingZones"
	_zone_button.text = tr("Customize zones")
	_zone_button.toggle_mode = true
	_zone_button.toggled.connect(_toggle_zones)
	add_child(_zone_button)
	_zone_section = VBoxContainer.new()
	_zone_section.name = "LightingZones"
	_zone_section.add_theme_constant_override("separation", 9)
	_zone_section.visible = false
	add_child(_zone_section)
	_build_zone_controls()
	_more_effects_button = Button.new()
	_more_effects_button.name = "LightingMoreEffects"
	_more_effects_button.text = tr("More effects")
	_more_effects_button.toggle_mode = true
	_more_effects_button.toggled.connect(_toggle_effects)
	add_child(_more_effects_button)
	_effects_section = VBoxContainer.new()
	_effects_section.name = "LightingEffects"
	_effects_section.visible = false
	_effects_section.add_theme_constant_override("separation", 8)
	add_child(_effects_section)
	_build_effect_controls()
	_sequence_editor = SequenceEditor.new()
	_sequence_editor.name = "LightingSequenceEditor"
	add_child(_sequence_editor)
	_sequence_editor.profile_changed.connect(_commit_lighting)
	_sequence_editor.pending_changed.connect(func(_pending: bool) -> void: _emit_validity())
	var reset := Button.new()
	reset.name = "ResetLighting"
	reset.text = tr("Reset lighting")
	reset.pressed.connect(reset_lighting)
	add_child(reset)
	_status = Label.new()
	_status.name = "LightingStatus"
	_status.add_theme_color_override("font_color", Color(0.91, 0.70, 0.38))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _build_zone_controls() -> void:
	_orientation_lock = CheckButton.new()
	_orientation_lock.name = "LightingOrientationLock"
	_orientation_lock.text = tr("Lock navigation colors and patterns")
	_orientation_lock.toggled.connect(_on_orientation_lock_toggled)
	_zone_section.add_child(_orientation_lock)
	_orientation_hint = Label.new()
	_orientation_hint.name = "LightingOrientationHint"
	_orientation_hint.theme_type_variation = "SecondaryLabel"
	_orientation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_section.add_child(_orientation_hint)
	var zone_label := Label.new()
	zone_label.text = tr("Lighting zone")
	zone_label.theme_type_variation = "SectionLabel"
	zone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_section.add_child(zone_label)
	_zone_selector = OptionButton.new()
	_zone_selector.name = "LightingZone"
	_zone_selector.fit_to_longest_item = false
	_zone_selector.clip_text = true
	_zone_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_selector.item_selected.connect(_on_zone_selected)
	_zone_section.add_child(_zone_selector)
	_zone_availability = Label.new()
	_zone_availability.name = "LightingZoneAvailability"
	_zone_availability.theme_type_variation = "SecondaryLabel"
	_zone_availability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_section.add_child(_zone_availability)
	_zone_enabled = CheckButton.new()
	_zone_enabled.text = tr("Zone enabled")
	_zone_enabled.toggled.connect(func(value: bool) -> void: _update_zone_draft("enabled", value))
	_zone_section.add_child(_zone_enabled)
	var zone_brightness_row := HBoxContainer.new()
	var zone_brightness_label := Label.new()
	zone_brightness_label.text = tr("Zone brightness")
	zone_brightness_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone_brightness_row.add_child(zone_brightness_label)
	_zone_brightness_value = Label.new()
	_zone_brightness_value.custom_minimum_size.x = 58
	_zone_brightness_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zone_brightness_row.add_child(_zone_brightness_value)
	_zone_section.add_child(zone_brightness_row)
	_zone_brightness = HSlider.new()
	_zone_brightness.name = "LightingZoneBrightness"
	_zone_brightness.tooltip_text = tr("Per-zone multiplier, independent of overall brightness.")
	_zone_brightness.min_value = 0.0
	_zone_brightness.max_value = 2.0
	_zone_brightness.step = 0.01
	_zone_brightness.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_brightness.value_changed.connect(_on_zone_brightness_changed)
	_zone_section.add_child(_zone_brightness)
	var palette_label := Label.new()
	palette_label.text = tr("Colors")
	palette_label.theme_type_variation = "SecondaryLabel"
	_zone_section.add_child(palette_label)
	_palette_list = VBoxContainer.new()
	_palette_list.add_theme_constant_override("separation", 5)
	_zone_section.add_child(_palette_list)
	var palette_actions := HBoxContainer.new()
	_add_color_button = Button.new()
	_add_color_button.name = "AddLightingColor"
	_add_color_button.text = tr("Add color")
	_add_color_button.pressed.connect(_add_palette_color)
	palette_actions.add_child(_add_color_button)
	_zone_section.add_child(palette_actions)
	var pattern_row := HBoxContainer.new()
	var pattern_label := Label.new()
	pattern_label.text = tr("Pattern")
	pattern_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pattern_row.add_child(pattern_label)
	_pattern_selector = OptionButton.new()
	_pattern_selector.name = "LightingPattern"
	for pattern_id: String in PATTERN_IDS:
		_pattern_selector.add_item(tr(pattern_id.capitalize()))
		_pattern_selector.set_item_metadata(_pattern_selector.item_count - 1, pattern_id)
	_pattern_selector.item_selected.connect(_on_pattern_selected)
	pattern_row.add_child(_pattern_selector)
	_zone_section.add_child(pattern_row)
	_pattern_hint = Label.new()
	_pattern_hint.name = "LightingPatternHint"
	_pattern_hint.theme_type_variation = "SecondaryLabel"
	_pattern_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_section.add_child(_pattern_hint)
	var period_row := HBoxContainer.new()
	var period_label := Label.new()
	period_label.text = tr("Cycle")
	period_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	period_row.add_child(period_label)
	_period = SpinBox.new()
	_period.name = "LightingPeriodSeconds"
	_period.min_value = 0.25
	_period.max_value = 60.0
	_period.step = 0.25
	_period.suffix = tr(" s")
	_period.tooltip_text = tr("Shorter cycles run faster; this is the duration of one full cycle.")
	_period.custom_minimum_size.x = 112
	_period.get_line_edit().expand_to_text_length = true
	_period.value_changed.connect(_on_period_changed)
	period_row.add_child(_period)
	_zone_section.add_child(period_row)
	_period_readout = Label.new()
	_period_readout.theme_type_variation = "SecondaryLabel"
	_period_readout.text = tr("Cycle duration applies to animated patterns.")
	_period_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_section.add_child(_period_readout)
	var reactive_row := HBoxContainer.new()
	var reactive_label := Label.new()
	reactive_label.text = tr("Response source")
	reactive_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reactive_row.add_child(reactive_label)
	_reactive_selector = OptionButton.new()
	_reactive_selector.name = "LightingReactiveSource"
	for source_id: String in Profile.REACTIVE_SOURCES:
		var source_label := "None" if source_id == "none" else source_id.replace("_", " ").capitalize()
		_reactive_selector.add_item(tr(source_label))
		_reactive_selector.set_item_metadata(_reactive_selector.item_count - 1, source_id)
	_reactive_selector.item_selected.connect(_on_reactive_source_selected)
	reactive_row.add_child(_reactive_selector)
	_zone_section.add_child(reactive_row)
	var reactive_gain_row := HBoxContainer.new()
	var reactive_gain_label := Label.new()
	reactive_gain_label.text = tr("Response strength")
	reactive_gain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reactive_gain_row.add_child(reactive_gain_label)
	_reactive_gain = SpinBox.new()
	_reactive_gain.name = "LightingReactiveGain"
	_reactive_gain.min_value = 0.0
	_reactive_gain.max_value = 1.0
	_reactive_gain.step = 0.05
	_reactive_gain.get_line_edit().expand_to_text_length = true
	_reactive_gain.value_changed.connect(_on_reactive_gain_changed)
	reactive_gain_row.add_child(_reactive_gain)
	_zone_section.add_child(reactive_gain_row)
	_reactive_hint = Label.new()
	_reactive_hint.theme_type_variation = "SecondaryLabel"
	_reactive_hint.text = tr("Telemetry reactions use accepted values when available; otherwise the zone stays steady.")
	_reactive_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_section.add_child(_reactive_hint)
	var zone_actions := HFlowContainer.new()
	_zone_reset = Button.new()
	_zone_reset.name = "ResetLightingZone"
	_zone_reset.text = tr("Reset zone")
	_zone_reset.pressed.connect(_reset_selected_zone)
	zone_actions.add_child(_zone_reset)
	_zone_cancel = Button.new()
	_zone_cancel.text = tr("Cancel")
	_zone_cancel.pressed.connect(cancel_pending_edit)
	zone_actions.add_child(_zone_cancel)
	_zone_apply = Button.new()
	_zone_apply.name = "ApplyLightingZone"
	_zone_apply.theme_type_variation = "CompactPrimaryButton"
	_zone_apply.text = tr("Apply zone")
	_zone_apply.pressed.connect(_apply_zone)
	zone_actions.add_child(_zone_apply)
	_zone_section.add_child(zone_actions)


func _build_effect_controls() -> void:
	var note := Label.new()
	note.text = tr("Optional effects follow available registered anchors. Preview bursts start only when playback is requested.")
	note.theme_type_variation = "SecondaryLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effects_section.add_child(note)
	var effect_hint := Label.new()
	effect_hint.name = "LightingEffectHint"
	effect_hint.theme_type_variation = "SecondaryLabel"
	effect_hint.text = tr("Disabling an effect also removes that effect from saved sequence cues.")
	effect_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effects_section.add_child(effect_hint)
	_effects_controls = VBoxContainer.new()
	_effects_controls.add_theme_constant_override("separation", 7)
	_effects_section.add_child(_effects_controls)
	var actions := HFlowContainer.new()
	_effects_cancel = Button.new()
	_effects_cancel.text = tr("Cancel")
	_effects_cancel.pressed.connect(_cancel_effects)
	actions.add_child(_effects_cancel)
	_effects_apply = Button.new()
	_effects_apply.theme_type_variation = "CompactPrimaryButton"
	_effects_apply.text = tr("Apply effects")
	_effects_apply.pressed.connect(_apply_effects)
	actions.add_child(_effects_apply)
	_effects_section.add_child(actions)


func configure(bindings: Dictionary, presentation: Dictionary) -> void:
	var raw: Variant = presentation.get("lighting", Profile.defaults())
	# The owner explicitly restores pending editor buffers after configure resets them.
	# Keep that reset authoritative; reuse only an already accepted, unchanged view.
	var reuse_controls: bool = _configuration_reusable and not has_pending_edit() and _bindings == bindings \
		and _presentation.get("lighting", Profile.defaults()) == raw and _profile == raw
	_presentation = presentation.duplicate(true)
	if reuse_controls:
		_emit_validity()
		return
	var saved_zone := _selected_zone_id
	_capability_report = {}
	_bindings = bindings.duplicate(true)
	_profile = raw.duplicate(true) if raw is Dictionary else Profile.defaults()
	var checked: Dictionary = Profile.validate(_profile)
	if bool(checked.get("ok", false)):
		_profile = checked.profile.duplicate(true)
	_brightness_pending = false
	_zone_pending = false
	_zone_text_pending = false
	_zone_text_invalid = false
	_effects_pending = false
	_effects_draft.clear()
	_syncing = true
	_sync_simple_controls()
	_rebuild_zone_selector(saved_zone)
	_sync_zone_editor()
	_rebuild_effect_controls()
	_sequence_editor.configure(_profile)
	_sync_summary()
	_refresh_capability_feedback()
	_syncing = false
	_configuration_reusable = bool(checked.get("ok", false))
	_emit_validity()


func get_editor_state() -> Dictionary:
	return {
		"zone": _selected_zone_id,
		"zones_open": _zone_section.visible,
		"effects_open": _effects_section.visible,
		"color_text": _zone_hex_fields.map(func(field: LineEdit) -> String: return field.text),
		"sequence": _sequence_editor.get_editor_state(),
	}


func restore_editor_state(state: Dictionary) -> bool:
	var keys := ["zone", "zones_open", "effects_open", "color_text"]
	if state.size() != keys.size() + (1 if state.has("sequence") else 0):
		return false
	for key: String in keys:
		if not state.has(key):
			return false
	if typeof(state.zone) != TYPE_STRING or str(state.zone).length() > 80:
		return false
	if typeof(state.zones_open) != TYPE_BOOL or typeof(state.effects_open) != TYPE_BOOL or not state.color_text is Array:
		return false
	if state.color_text.size() > 8:
		return false
	if state.zone != "" and not _zone_exists(str(state.zone)):
		return false
	for color_text: Variant in state.color_text:
		if typeof(color_text) != TYPE_STRING or str(color_text).length() > 16:
			return false
	if state.has("sequence") and not Sequence.validate_editor_state(state.sequence).ok:
		return false
	if state.has("sequence") and not _sequence_editor.restore_editor_state(state.sequence):
		return false
	_selected_zone_id = str(state.zone)
	_zone_section.visible = bool(state.zones_open)
	_zone_button.button_pressed = _zone_section.visible
	_zone_button.text = tr("Hide zone controls" if _zone_section.visible else "Customize zones")
	_effects_section.visible = bool(state.effects_open)
	_more_effects_button.button_pressed = _effects_section.visible
	_more_effects_button.text = tr("Hide effects" if _effects_section.visible else "More effects")
	_rebuild_zone_selector(_selected_zone_id)
	_sync_zone_editor()
	_sync_simple_controls()
	for index in mini(state.color_text.size(), _zone_hex_fields.size()):
		var text_value := str(state.color_text[index])
		var accepted: Array = _zone_draft.get("pattern", {}).get("palette", [])
		if index < accepted.size() and text_value.to_upper() != str(accepted[index]).to_upper():
			_zone_hex_fields[index].text = text_value
			_on_zone_hex_changed(text_value, index)
	return true


func has_pending_edit() -> bool:
	return _brightness_pending or _zone_pending or _effects_pending or _zone_text_pending or _sequence_pending()


func _sequence_pending() -> bool:
	return is_instance_valid(_sequence_editor) and _sequence_editor.has_pending_edit()


func pending_control() -> Control:
	if _sequence_pending():
		return _sequence_editor.pending_control()
	if _zone_text_invalid and not _zone_hex_fields.is_empty():
		for field: LineEdit in _zone_hex_fields:
			if not _valid_hex(field.text):
				return field
	if _brightness_pending:
		return _brightness
	return _zone_apply if _zone_pending else (_effects_apply if _effects_pending else null)


func cancel_pending_edit() -> bool:
	if not has_pending_edit():
		return false
	_sequence_editor.cancel_pending_edit()
	_brightness_timer.stop()
	_brightness_pending = false
	_zone_draft.clear()
	_zone_pending = false
	_zone_text_pending = false
	_zone_text_invalid = false
	_effects_draft.clear()
	_effects_pending = false
	_syncing = true
	_sync_simple_controls()
	_sync_zone_editor()
	_rebuild_effect_controls()
	_syncing = false
	_set_status("")
	_emit_validity()
	return true


func reset_lighting() -> void:
	if has_pending_edit():
		cancel_pending_edit()
	var reset_profile: Dictionary = Profile.defaults()
	_commit_lighting(reset_profile)


func _sync_simple_controls() -> void:
	var selection := str(_profile.get("selection", "inherit"))
	var target := "inherit" if selection == "inherit" else str(_profile.get("preset_id", ""))	
	if selection == "custom":
		target = "custom"
	if selection == "disabled":
		target = "disabled"
	# Disabled is an explicit state, kept separate from inherited aircraft equipment.
	var target_index := _find_item_metadata(_preset, target)
	if target_index < 0 and target == "disabled":
		_enabled.set_pressed_no_signal(false)
		_preset.select(_find_item_metadata(_preset, "inherit"))
	else:
		_enabled.set_pressed_no_signal(true)
		_preset.select(maxi(target_index, 0))
	var brightness := float(_profile.get("brightness", 1.0))
	_brightness.set_value_no_signal(clampf(brightness, 0.0, 2.0))
	_brightness_value.text = "%d%%" % roundi(brightness * 100.0)
	_orientation_lock.set_pressed_no_signal(bool(_profile.get("orientation_lock", false)))
	_orientation_lock.disabled = selection not in ["preset", "custom"]
	_brightness.editable = selection != "disabled" and not _zone_section.visible and not _effects_section.visible
	_preset.disabled = not _enabled.button_pressed
	_brightness_value.modulate.a = 1.0 if _brightness.editable else 0.55


func _on_preset_selected(index: int) -> void:
	if _syncing or has_pending_edit():
		_syncing = true
		_sync_simple_controls()
		_syncing = false
		return
	var selected: String = str(_preset.get_item_metadata(index))
	var next := Profile.defaults() if selected == "inherit" else Profile.preset(selected)
	if selected == "inherit":
		_enabled.set_pressed_no_signal(true)
	var checked: Dictionary = Profile.validate(next)
	if not bool(checked.get("ok", false)):
		_set_status(_first_error(checked.get("errors", [])))
		return
	_enabled.set_pressed_no_signal(true)
	_commit_lighting(checked.profile)


func _on_enabled_toggled(enabled: bool) -> void:
	if _syncing:
		return
	if has_pending_edit():
		_syncing = true
		_sync_simple_controls()
		_syncing = false
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	var next: Dictionary = Profile.defaults()
	if enabled:
		var selected := str(_profile.get("selection", "inherit"))
		next = Profile.preset(str(_profile.get("preset_id", "classic_rc"))) if selected in ["preset", "custom"] else Profile.defaults()
	else:
		next.selection = "disabled"
	var checked: Dictionary = Profile.validate(next)
	if bool(checked.get("ok", false)):
		_commit_lighting(checked.profile)
	else:
		_set_status(_first_error(checked.get("errors", [])))


func _on_orientation_lock_toggled(value: bool) -> void:
	if _syncing:
		return
	if has_pending_edit():
		_syncing = true
		_sync_simple_controls()
		_syncing = false
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	var next := _profile.duplicate(true)
	next.orientation_lock = value
	_mark_custom(next)
	var checked: Dictionary = Profile.validate(next)
	if bool(checked.get("ok", false)):
		_commit_lighting(checked.profile)
	else:
		_set_status(_first_error(checked.get("errors", [])))


func _on_brightness_changed(value: float) -> void:
	if _syncing or not _enabled.button_pressed:
		return
	if _zone_pending or _zone_text_pending or _effects_pending or _sequence_pending():
		_syncing = true
		_brightness.set_value_no_signal(float(_profile.get("brightness", 1.0)))
		_brightness_value.text = "%d%%" % roundi(float(_profile.get("brightness", 1.0)) * 100.0)
		_syncing = false
		_set_status(tr("Apply or cancel the advanced edit before changing overall brightness."))
		return
	_brightness_value.text = "%d%%" % roundi(value * 100.0)
	_brightness_pending = true
	_emit_validity()
	_brightness_timer.start()


func _commit_brightness() -> void:
	if _syncing or not _brightness_pending or not _enabled.button_pressed:
		return
	_brightness_pending = false
	var next := _profile.duplicate(true)
	next.brightness = clampf(_brightness.value, 0.0, 2.0)
	var checked: Dictionary = Profile.validate(next)
	if not bool(checked.get("ok", false)):
		_set_status(_first_error(checked.get("errors", [])))
		return
	_commit_lighting(checked.profile)


func _toggle_zones(open: bool) -> void:
	if has_pending_edit():
		_zone_button.set_pressed_no_signal(_zone_section.visible)
		_set_status(tr("Apply or cancel the current lighting edit before changing panels."))
		return
	_zone_section.visible = open
	_zone_button.text = tr("Hide zone controls" if open else "Customize zones")
	if open:
		_rebuild_zone_selector(_selected_zone_id)
		_sync_zone_editor()
	_sync_simple_controls()


func _toggle_effects(open: bool) -> void:
	if has_pending_edit():
		_more_effects_button.set_pressed_no_signal(_effects_section.visible)
		_set_status(tr("Apply or cancel the current lighting edit before changing panels."))
		return
	_effects_section.visible = open
	_more_effects_button.text = tr("Hide effects" if open else "More effects")
	if open:
		_rebuild_effect_controls()
	_sync_simple_controls()


func _rebuild_zone_selector(preferred: String) -> void:
	if not is_instance_valid(_zone_selector):
		return
	var entries: Array = _profile.get("zones", [])
	var ids := PackedStringArray()
	for zone_value: Variant in entries:
		if not zone_value is Dictionary:
			continue
		var zone_id := str(zone_value.get("id", ""))
		if zone_id in ZONE_LABELS and zone_id not in ids:
			ids.append(zone_id)
	_zone_selector.clear()
	for zone_id: String in ids:
		_zone_selector.add_item(tr(str(ZONE_LABELS[zone_id])))
		_zone_selector.set_item_metadata(_zone_selector.item_count - 1, zone_id)
	var selected_index := _find_item_metadata(_zone_selector, preferred)
	if selected_index < 0 and _zone_selector.item_count > 0:
		selected_index = 0
	if selected_index >= 0:
		_zone_selector.select(selected_index)
		_selected_zone_id = str(_zone_selector.get_item_metadata(selected_index))
	else:
		_selected_zone_id = ""
	_zone_selector.disabled = _zone_pending or _zone_selector.item_count == 0
	_zone_section.visible = _zone_section.visible and _zone_selector.item_count > 0
	_zone_button.disabled = _zone_selector.item_count == 0
	if _zone_selector.item_count == 0:
		_set_status(tr("Choose a supported preset to see its registered lighting zones."))


func _on_zone_selected(index: int) -> void:
	if _syncing or has_pending_edit():
		_syncing = true
		_rebuild_zone_selector(_selected_zone_id)
		_syncing = false
		return
	_selected_zone_id = str(_zone_selector.get_item_metadata(index))
	_sync_zone_editor()


func _sync_zone_editor() -> void:
	_zone_draft = _zone_for_id(_selected_zone_id)
	_refresh_capability_feedback()
	_zone_pending = false
	_zone_text_pending = false
	_zone_text_invalid = false
	_zone_hex_fields.clear()
	if _zone_draft.is_empty():
		_orientation_hint.text = ""
		_zone_enabled.disabled = true
		_zone_brightness.editable = false
		_zone_brightness_value.text = ""
		_pattern_selector.disabled = true
		_period.editable = false
		_reactive_selector.disabled = true
		_reactive_gain.editable = false
		_zone_apply.disabled = true
		_zone_cancel.disabled = true
		_zone_reset.disabled = true
		_add_color_button.disabled = true
		_clear_children(_palette_list)
		return
	_zone_enabled.set_pressed_no_signal(bool(_zone_draft.get("enabled", true)))
	_zone_enabled.disabled = false
	var zone_brightness := float(_zone_draft.get("brightness", 1.0))
	_zone_brightness.set_value_no_signal(clampf(zone_brightness, 0.0, 2.0))
	_zone_brightness_value.text = "%d%%" % roundi(zone_brightness * 100.0)
	_zone_brightness.editable = true
	var pattern: Dictionary = _zone_draft.get("pattern", {})
	var locked_navigation := bool(_profile.get("orientation_lock", false)) and _selected_zone_id.begins_with("nav_")
	var pattern_index := _find_item_metadata(_pattern_selector, str(pattern.get("id", "steady")))
	_pattern_selector.select(maxi(pattern_index, 0))
	var sequence_available := _sequence_available_for_zone(_selected_zone_id)
	var sequence_index := _find_item_metadata(_pattern_selector, "sequence")
	if sequence_index >= 0:
		_pattern_selector.set_item_disabled(sequence_index, not sequence_available)
	_pattern_hint.text = tr("Sequence follows the saved cue list for this zone.") if sequence_available else (
		tr("Sequence is available only when this profile has saved cues for the selected zone."))
	if locked_navigation:
		_orientation_hint.text = tr("Orientation lock preserves the saved navigation cue colors and patterns. Turn it off to edit them.")
		_pattern_selector.disabled = true
		_period.editable = false
		_pattern_hint.text = tr("Unlock orientation cues to change their color or pattern.")
	else:
		_orientation_hint.text = tr("Navigation colors and patterns are available when orientation lock is off.")
		_pattern_selector.disabled = false
	_period.set_value_no_signal(clampf(float(pattern.get("period_ticks", 960)) / 240.0, 0.25, 60.0))
	_period_readout.text = tr("Cycle: %.2f seconds") % [float(pattern.get("period_ticks", 960)) / 240.0]
	if not locked_navigation:
		_period.editable = true
	var reactive: Dictionary = _zone_draft.get("reactive", {"source": "none", "gain": 0.0})
	var source_index := _find_item_metadata(_reactive_selector, str(reactive.get("source", "none")))
	_reactive_selector.select(maxi(source_index, 0))
	_reactive_selector.disabled = false
	_reactive_gain.set_value_no_signal(clampf(float(reactive.get("gain", 0.0)), 0.0, 1.0))
	_reactive_gain.editable = str(reactive.get("source", "none")) != "none"
	_rebuild_palette_rows()
	_set_palette_controls_disabled(locked_navigation)
	_zone_apply.disabled = true
	_zone_cancel.disabled = true
	_zone_reset.disabled = false
	_refresh_zone_pending()


func _add_palette_row(index: int, raw_color: String) -> void:
	var row := HBoxContainer.new()
	row.name = "LightingPaletteColor%d" % index
	var picker := ColorPickerButton.new()
	Widgets.fit_color_picker_popup(picker)
	picker.name = "LightingPalettePicker%d" % index
	picker.custom_minimum_size = Vector2(42, 32)
	picker.edit_alpha = false
	picker.color = Color.from_string(raw_color, Color.WHITE)
	picker.tooltip_text = tr("Choose palette color %d") % (index + 1)
	picker.color_changed.connect(func(color: Color) -> void: _set_palette_color(index, "#" + color.to_html(false).to_upper()))
	row.add_child(picker)
	var hex := LineEdit.new()
	hex.name = "LightingPaletteHex%d" % index
	hex.placeholder_text = tr("Hex color")
	hex.max_length = 16
	hex.text = raw_color.to_upper()
	hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hex.text_changed.connect(func(value: String) -> void: _on_zone_hex_changed(value, index))
	hex.text_submitted.connect(func(_value: String) -> void: hex.release_focus())
	row.add_child(hex)
	var remove := Button.new()
	remove.name = "RemoveLightingColor%d" % index
	remove.text = "−"
	remove.tooltip_text = tr("Remove this palette color")
	remove.disabled = _zone_draft.get("pattern", {}).get("palette", []).size() <= 1
	remove.pressed.connect(func() -> void: _remove_palette_color(index))
	row.add_child(remove)
	_palette_list.add_child(row)
	_zone_hex_fields.append(hex)
	var locked_navigation := bool(_profile.get("orientation_lock", false)) and _selected_zone_id.begins_with("nav_")
	picker.disabled = locked_navigation
	hex.editable = not locked_navigation
	remove.disabled = locked_navigation or _zone_draft.get("pattern", {}).get("palette", []).size() <= 1


func _set_palette_controls_disabled(disabled: bool) -> void:
	_add_color_button.disabled = disabled or _zone_draft.get("pattern", {}).get("palette", []).size() >= 8
	for row: Node in _palette_list.get_children():
		var picker := row.get_child(0) as ColorPickerButton if row.get_child_count() > 0 else null
		var hex := row.get_child(1) as LineEdit if row.get_child_count() > 1 else null
		var remove := row.get_child(2) as Button if row.get_child_count() > 2 else null
		if picker != null:
			picker.disabled = disabled
		if hex != null:
			hex.editable = not disabled
		if remove != null:
			remove.disabled = disabled or _zone_draft.get("pattern", {}).get("palette", []).size() <= 1


func _set_palette_color(index: int, color_text: String) -> void:
	if _syncing:
		return
	if _brightness_pending or _effects_pending or _sequence_pending():
		_restore_palette_color(index)
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	var pattern: Dictionary = _zone_draft.get("pattern", {}).duplicate(true)
	var palette: Array = pattern.get("palette", []).duplicate()
	if index < 0 or index >= palette.size():
		return
	palette[index] = color_text
	pattern.palette = palette
	_zone_draft.pattern = pattern
	_sync_palette_color(index, color_text)
	_refresh_zone_pending()


func _restore_palette_color(index: int) -> void:
	var palette: Array = _zone_draft.get("pattern", {}).get("palette", [])
	if index >= 0 and index < palette.size():
		_sync_palette_color(index, str(palette[index]))


func _sync_palette_color(index: int, color_text: String) -> void:
	# Rejection must not destroy the focused field or an open color picker.
	_syncing = true
	if index < _zone_hex_fields.size():
		_zone_hex_fields[index].text = color_text
	var picker := _palette_list.get_node_or_null("LightingPaletteColor%d/LightingPalettePicker%d" % [index, index]) as ColorPickerButton
	if picker != null:
		picker.color = Color.from_string(color_text, Color.WHITE)
	_syncing = false


func _on_zone_hex_changed(value: String, index: int) -> void:
	if _syncing:
		return
	if _brightness_pending or _effects_pending or _sequence_pending():
		_restore_palette_color(index)
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	_zone_text_pending = true
	if not _valid_hex(value):
		_zone_text_invalid = _has_invalid_zone_text()
		_set_status(tr("Enter a six-digit hex color such as #20DFFF."))
		_emit_validity()
		return
	_zone_text_invalid = _has_invalid_zone_text()
	_set_palette_color(index, value.to_upper())
	_set_status(tr("Correct the remaining color fields before applying this zone.") if _zone_text_invalid else "")


func _valid_hex(value: String) -> bool:
	return value.is_valid_html_color() and value.length() == 7


func _has_invalid_zone_text() -> bool:
	for field: LineEdit in _zone_hex_fields:
		if not _valid_hex(field.text):
			return true
	return false


func _add_palette_color() -> void:
	if _zone_text_invalid or _brightness_pending or _effects_pending or _sequence_pending():
		return
	var pattern: Dictionary = _zone_draft.get("pattern", {}).duplicate(true)
	var palette: Array = pattern.get("palette", []).duplicate()
	if palette.size() >= 8:
		return
	var restore_focus := _add_color_button.has_focus()
	palette.append(palette.back() if not palette.is_empty() else "#FFFFFF")
	pattern.palette = palette
	_zone_draft.pattern = pattern
	_syncing = true
	_rebuild_palette_rows()
	_syncing = false
	_refresh_zone_pending()
	if restore_focus:
		_zone_hex_fields.back().grab_focus()


func _remove_palette_color(index: int) -> void:
	if _zone_text_invalid or _brightness_pending or _effects_pending or _sequence_pending():
		return
	var pattern: Dictionary = _zone_draft.get("pattern", {}).duplicate(true)
	var palette: Array = pattern.get("palette", []).duplicate()
	if palette.size() <= 1 or index < 0 or index >= palette.size():
		return
	var focused := get_viewport().gui_get_focus_owner()
	var restore_focus := focused != null and _palette_list.is_ancestor_of(focused)
	palette.remove_at(index)
	pattern.palette = palette
	_zone_draft.pattern = pattern
	_syncing = true
	_rebuild_palette_rows()
	_syncing = false
	_refresh_zone_pending()
	if restore_focus:
		_zone_hex_fields[mini(index, _zone_hex_fields.size() - 1)].grab_focus()


func _rebuild_palette_rows() -> void:
	_clear_children(_palette_list)
	_zone_hex_fields.clear()
	var palette: Array = _zone_draft.get("pattern", {}).get("palette", [])
	_add_color_button.disabled = palette.size() >= 8
	for index in palette.size():
		_add_palette_row(index, str(palette[index]))


func _on_pattern_selected(index: int) -> void:
	if _syncing:
		return
	if _brightness_pending or _effects_pending or _sequence_pending():
		_syncing = true
		_sync_zone_editor()
		_syncing = false
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	if str(_pattern_selector.get_item_metadata(index)) == "sequence" and not _sequence_available_for_zone(_selected_zone_id):
		var previous := _find_item_metadata(_pattern_selector, str(_zone_draft.get("pattern", {}).get("id", "steady")))
		_pattern_selector.select(maxi(previous, 0))
		_set_status(tr("This profile has no saved sequence cue for the selected zone."))
		return
	var pattern: Dictionary = _zone_draft.get("pattern", {}).duplicate(true)
	pattern.id = str(_pattern_selector.get_item_metadata(index))
	_zone_draft.pattern = pattern
	_refresh_zone_pending()


func _on_period_changed(value: float) -> void:
	if _syncing or _zone_draft.is_empty():
		return
	if _brightness_pending or _effects_pending or _sequence_pending():
		_syncing = true
		_sync_zone_editor()
		_syncing = false
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	var pattern: Dictionary = _zone_draft.get("pattern", {}).duplicate(true)
	pattern.period_ticks = clampi(roundi(value * 240.0), 60, 14400)
	_zone_draft.pattern = pattern
	_period_readout.text = tr("Cycle: %.2f seconds") % [float(pattern.period_ticks) / 240.0]
	_refresh_zone_pending()


func _update_zone_draft(key: String, value: Variant) -> void:
	if _syncing or _zone_draft.is_empty():
		return
	if _brightness_pending or _effects_pending or _sequence_pending():
		_syncing = true
		_sync_zone_editor()
		_syncing = false
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	_zone_draft[key] = value
	_refresh_zone_pending()


func _on_zone_brightness_changed(value: float) -> void:
	_zone_brightness_value.text = "%d%%" % roundi(value * 100.0)
	_update_zone_draft("brightness", clampf(value, 0.0, 2.0))


func _on_reactive_source_selected(index: int) -> void:
	if _syncing or _zone_draft.is_empty():
		return
	if _brightness_pending or _effects_pending or _sequence_pending():
		_syncing = true
		_sync_zone_editor()
		_syncing = false
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	var reactive: Dictionary = _zone_draft.get("reactive", {}).duplicate(true)
	var source := str(_reactive_selector.get_item_metadata(index))
	reactive.source = source
	if source == "none":
		reactive.gain = 0.0
		_reactive_gain.set_value_no_signal(0.0)
	_reactive_gain.editable = source != "none"
	_zone_draft.reactive = reactive
	_refresh_zone_pending()


func _on_reactive_gain_changed(value: float) -> void:
	if _syncing or _zone_draft.is_empty():
		return
	if _brightness_pending or _effects_pending or _sequence_pending():
		_syncing = true
		_sync_zone_editor()
		_syncing = false
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	var reactive: Dictionary = _zone_draft.get("reactive", {}).duplicate(true)
	if str(reactive.get("source", "none")) == "none":
		return
	reactive.gain = clampf(value, 0.0, 1.0)
	_zone_draft.reactive = reactive
	_refresh_zone_pending()


func _sequence_available_for_zone(zone_id: String) -> bool:
	for cue_value: Variant in _profile.get("sequence", []):
		if cue_value is Dictionary and zone_id in cue_value.get("zone_ids", []):
			return true
	return false


func _refresh_zone_pending() -> void:
	if _zone_draft.is_empty():
		return
	_zone_pending = _zone_draft != _zone_for_id(_selected_zone_id) or _zone_text_pending
	_zone_apply.disabled = not _zone_pending or _zone_text_invalid
	_zone_cancel.disabled = not _zone_pending
	_zone_selector.disabled = has_pending_edit() or _zone_selector.item_count == 0
	_emit_validity()


func _apply_zone() -> void:
	if not _zone_pending or _zone_text_invalid or _brightness_pending or _effects_pending or _sequence_pending():
		return
	var next := _profile.duplicate(true)
	var zones: Array = next.get("zones", []).duplicate(true)
	var replaced := false
	for index in zones.size():
		if zones[index].get("id", "") == _selected_zone_id:
			zones[index] = _zone_draft.duplicate(true)
			replaced = true
			break
	if not replaced:
		_set_status(tr("This zone is no longer in the selected lighting profile."))
		return
	next.zones = zones
	_mark_custom(next)
	if str(_zone_draft.get("pattern", {}).get("id", "")) != "sequence":
		for cue_index in next.sequence.size():
			var cue: Dictionary = next.sequence[cue_index].duplicate(true)
			var cue_zones: Array = cue.get("zone_ids", []).duplicate()
			cue_zones.erase(_selected_zone_id)
			cue.zone_ids = cue_zones
			next.sequence[cue_index] = cue
	var has_sequence_zone := false
	for zone: Dictionary in zones:
		if str(zone.get("pattern", {}).get("id", "")) == "sequence":
			has_sequence_zone = true
			break
	if not has_sequence_zone:
		next.sequence = []
	var checked: Dictionary = Profile.validate(next)
	if not bool(checked.get("ok", false)):
		_set_status(_first_error(checked.get("errors", [])))
		return
	_zone_pending = false
	_zone_text_pending = false
	_zone_text_invalid = false
	_commit_lighting(checked.profile)
	_set_status(tr("Zone changes applied to the draft."))
	_emit_validity()


func _cancel_zone() -> void:
	_zone_pending = false
	_zone_text_pending = false
	_zone_text_invalid = false
	_syncing = true
	_sync_zone_editor()
	_syncing = false
	_set_status("")
	_emit_validity()


func _reset_selected_zone() -> void:
	if has_pending_edit():
		_set_status(tr("Apply or cancel the current edits before resetting this zone."))
		return
	var base_id := str(_profile.get("preset_id", ""))
	if base_id not in Profile.PRESET_IDS:
		_set_status(tr("This inherited profile has no editable zone default. Choose a preset first."))
		return
	var revision := int(_profile.get("preset_revision", 0))
	var defaults: Dictionary = Profile.preset(base_id, revision)
	var zone: Dictionary = {}
	for item: Dictionary in defaults.get("zones", []):
		if str(item.get("id", "")) == _selected_zone_id:
			zone = item.duplicate(true)
			break
	if zone.is_empty():
		for item: Dictionary in Profile.preset("custom", revision).get("zones", []):
			if str(item.get("id", "")) == _selected_zone_id:
				zone = item.duplicate(true)
				break
	if zone.is_empty():
		_set_status(tr("The selected preset has no default for this zone."))
		return
	var next := _profile.duplicate(true)
	var zones: Array = next.get("zones", []).duplicate(true)
	for index in zones.size():
		if str(zones[index].get("id", "")) == _selected_zone_id:
			zones[index] = zone
			next.zones = zones
			if str(zone.get("pattern", {}).get("id", "")) == "sequence" and next.sequence.is_empty():
				next.sequence = defaults.get("sequence", []).duplicate(true)
				var enabled_effects: Dictionary = {}
				for effect: Dictionary in next.get("effects", []):
					if bool(effect.get("enabled", false)):
						enabled_effects[str(effect.get("anchor_id", ""))] = true
				for cue_index in next.sequence.size():
					var cue: Dictionary = next.sequence[cue_index].duplicate(true)
					var anchors: Array = cue.get("effect_anchor_ids", []).duplicate()
					for anchor_index in range(anchors.size() - 1, -1, -1):
						if not enabled_effects.has(str(anchors[anchor_index])):
							anchors.remove_at(anchor_index)
					cue.effect_anchor_ids = anchors
					next.sequence[cue_index] = cue
			_mark_custom(next)
			var checked: Dictionary = Profile.validate(next)
			if bool(checked.get("ok", false)):
				_commit_lighting(checked.profile)
				_set_status(tr("Zone reset to its preset default."))
			return


func _apply_effects() -> void:
	if not _effects_pending or _brightness_pending or _zone_pending or _zone_text_pending or _sequence_pending():
		return
	var next := _profile.duplicate(true)
	next.effects = _effects_draft.duplicate(true)
	var enabled_effects: Dictionary = {}
	for effect: Dictionary in next.effects:
		if bool(effect.get("enabled", false)):
			enabled_effects[str(effect.get("anchor_id", ""))] = true
	for cue_index in next.sequence.size():
		var cue: Dictionary = next.sequence[cue_index].duplicate(true)
		var anchors: Array = cue.get("effect_anchor_ids", []).duplicate()
		for index in range(anchors.size() - 1, -1, -1):
			if not enabled_effects.has(str(anchors[index])):
				anchors.remove_at(index)
		cue.effect_anchor_ids = anchors
		next.sequence[cue_index] = cue
	_mark_custom(next)
	var checked: Dictionary = Profile.validate(next)
	if not bool(checked.get("ok", false)):
		_set_status(_first_error(checked.get("errors", [])))
		return
	_effects_pending = false
	_commit_lighting(checked.profile)
	_set_status(tr("Effect changes applied to the draft."))
	_emit_validity()


func _cancel_effects() -> void:
	_effects_pending = false
	_effects_draft.clear()
	_syncing = true
	_rebuild_effect_controls()
	_syncing = false
	_set_status("")
	_emit_validity()


func _rebuild_effect_controls() -> void:
	if not is_instance_valid(_effects_controls):
		return
	_clear_children(_effects_controls)
	_effects_controls_by_anchor.clear()
	_effects_draft = _profile.get("effects", []).duplicate(true)
	for entry_value: Variant in _effects_draft:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var anchor := str(entry.get("anchor_id", ""))
		if _effects_controls.get_child_count() > 0:
			_effects_controls.add_child(HSeparator.new())
		var row := VBoxContainer.new()
		var toggle := CheckButton.new()
		toggle.text = tr("%s effect") % tr(_effect_anchor_label(anchor))
		toggle.button_pressed = bool(entry.get("enabled", false))
		toggle.toggled.connect(func(value: bool) -> void: _set_effect_value(anchor, "enabled", value))
		row.add_child(toggle)
		var availability := Label.new()
		availability.name = "EffectAvailability_" + anchor
		availability.theme_type_variation = "SecondaryLabel"
		availability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(availability)
		var kind_row := HBoxContainer.new()
		var kind_label := Label.new()
		kind_label.text = tr("Effect")
		kind_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind_row.add_child(kind_label)
		var kind_selector := OptionButton.new()
		kind_selector.name = "EffectKind_" + anchor
		for kind_id: String in EFFECT_KIND_IDS:
			kind_selector.add_item(tr(kind_id.capitalize()))
			kind_selector.set_item_metadata(kind_selector.item_count - 1, kind_id)
		kind_selector.select(maxi(_find_item_metadata(kind_selector, str(entry.get("kind", "spark"))), 0))
		kind_selector.item_selected.connect(func(index: int) -> void:
			_set_effect_value(anchor, "kind", str(kind_selector.get_item_metadata(index)))
		)
		kind_row.add_child(kind_selector)
		row.add_child(kind_row)
		var intensity_row := HBoxContainer.new()
		var intensity_label := Label.new()
		intensity_label.text = tr("Intensity")
		intensity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		intensity_row.add_child(intensity_label)
		var intensity := SpinBox.new()
		intensity.name = "EffectIntensity_" + anchor
		intensity.min_value = 0.0
		intensity.max_value = 1.0
		intensity.step = 0.05
		intensity.get_line_edit().expand_to_text_length = true
		intensity.value = float(entry.get("intensity", 0.0))
		intensity.value_changed.connect(func(value: float) -> void: _set_effect_value(anchor, "intensity", value))
		intensity_row.add_child(intensity)
		row.add_child(intensity_row)
		var lifetime_row := HBoxContainer.new()
		var lifetime_label := Label.new()
		lifetime_label.text = tr("Lifetime")
		lifetime_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lifetime_row.add_child(lifetime_label)
		var lifetime := SpinBox.new()
		lifetime.name = "EffectLifetime_" + anchor
		lifetime.min_value = 0.05
		lifetime.max_value = 2.0
		lifetime.step = 0.05
		lifetime.suffix = tr(" s")
		lifetime.get_line_edit().expand_to_text_length = true
		lifetime.value = float(entry.get("lifetime_ticks", 96)) / 240.0
		lifetime.value_changed.connect(func(value: float) -> void:
			_set_effect_value(anchor, "lifetime_ticks", clampi(roundi(value * 240.0), 12, 480))
		)
		lifetime_row.add_child(lifetime)
		row.add_child(lifetime_row)
		_effects_controls.add_child(row)
		_effects_controls_by_anchor[anchor] = {"enabled": toggle, "kind": kind_selector, "intensity": intensity, "lifetime": lifetime, "availability": availability}
	var has_effects := not _effects_draft.is_empty()
	_effects_controls.visible = true
	_effects_apply.disabled = not _effects_pending or not has_effects
	_effects_cancel.disabled = not _effects_pending
	if not has_effects:
		var empty := Label.new()
		empty.text = tr("This preset has no registered show effects.")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_effects_controls.add_child(empty)
	_refresh_capability_feedback()


func _effect_anchor_label(anchor_id: String) -> String:
	match anchor_id:
		"vfx_tip_left": return tr("Left wingtip")
		"vfx_tip_right": return tr("Right wingtip")
		_: return anchor_id.replace("_", " ").capitalize()


func _set_effect_value(anchor_id: String, key: String, value: Variant) -> void:
	if _syncing:
		return
	if _brightness_pending or _zone_pending or _zone_text_pending or _sequence_pending():
		_restore_effect_value(anchor_id, key)
		_set_status(tr("Apply or cancel the current lighting edit first."))
		return
	for index in _effects_draft.size():
		if str(_effects_draft[index].get("anchor_id", "")) == anchor_id:
			_effects_draft[index][key] = value
			_effects_pending = _effects_draft != _profile.get("effects", [])
			_effects_apply.disabled = not _effects_pending
			_effects_cancel.disabled = not _effects_pending
			_emit_validity()
			return


func _restore_effect_value(anchor_id: String, key: String) -> void:
	# Keep the same input (including SpinBox's LineEdit) through rejected edits.
	var controls: Dictionary = _effects_controls_by_anchor.get(anchor_id, {})
	if controls.is_empty():
		return
	for entry: Dictionary in _effects_draft:
		if str(entry.get("anchor_id", "")) != anchor_id:
			continue
		match key:
			"enabled": controls.enabled.set_pressed_no_signal(bool(entry.get("enabled", false)))
			"kind": controls.kind.select(maxi(_find_item_metadata(controls.kind, str(entry.get("kind", "spark"))), 0))
			"intensity": controls.intensity.set_value_no_signal(float(entry.get("intensity", 0.0)))
			"lifetime_ticks": controls.lifetime.set_value_no_signal(float(entry.get("lifetime_ticks", 96)) / 240.0)
		return


func _zone_for_id(zone_id: String) -> Dictionary:
	for entry_value: Variant in _profile.get("zones", []):
		if entry_value is Dictionary and str(entry_value.get("id", "")) == zone_id:
			return entry_value.duplicate(true)
	return {}


func _zone_exists(zone_id: String) -> bool:
	return not _zone_for_id(zone_id).is_empty()


func _mark_custom(profile: Dictionary) -> void:
	if str(profile.get("selection", "")) == "preset":
		profile.selection = "custom"


func _commit_lighting(lighting: Dictionary) -> void:
	var checked: Dictionary = Profile.validate(lighting)
	if not bool(checked.get("ok", false)):
		_set_status(_first_error(checked.get("errors", [])))
		return
	var next := _presentation.duplicate(true)
	var migration_report: Dictionary = {}
	if int(next.get("version", 0)) == 1:
		var promoted: Dictionary = Presentation.migrate_v1(next, _bindings, _bindings)
		if not bool(promoted.get("ok", false)):
			_set_status(_first_error(promoted.get("errors", [])))
			return
		next = promoted.profile.duplicate(true)
		migration_report = promoted.get("report", {})
	if int(next.get("version", 0)) < 3:
		next.version = 3
	next["lighting"] = checked.profile.duplicate(true)
	var presentation_check: Dictionary = Presentation.validate(next, _bindings)
	if not bool(presentation_check.get("ok", false)):
		_set_status(_first_error(presentation_check.get("errors", [])))
		return
	_set_status("")
	_profile = checked.profile.duplicate(true)
	profile_changed.emit(presentation_check.profile)
	if not migration_report.is_empty() and not _presentation.get("smoke", []).is_empty():
		var enabled_count := 0
		for entry: Dictionary in next.get("smoke", []):
			if bool(entry.get("enabled", false)):
				enabled_count += 1
		_set_status(tr("Created a v3 lighting profile with %d migrated smoke outlet(s). Review their settings; the saved revision is unchanged.") % enabled_count)
	_sync_summary()
	_emit_validity()


func _sync_summary() -> void:
	var enabled_count := 0
	for zone: Dictionary in _profile.get("zones", []):
		if bool(zone.get("enabled", false)):
			enabled_count += 1
	var enabled_effect_count := 0
	for effect: Dictionary in _profile.get("effects", []):
		if bool(effect.get("enabled", false)):
			enabled_effect_count += 1
	var selection := str(_profile.get("selection", "inherit"))
	var style := tr("Aircraft equipment") if selection == "inherit" else tr("Lighting off") if selection == "disabled" else tr(Profile.label("custom" if selection == "custom" else str(_profile.get("preset_id", ""))))
	var state := tr("No lighting overrides") if selection == "inherit" else tr("Lighting disabled") if selection == "disabled" else tr("%d configured zones · %d enabled") % [_profile.get("zones", []).size(), enabled_count]
	if selection in ["preset", "custom"]:
		state += tr(" · %d effects enabled") % enabled_effect_count
	_summary.text = tr("%s · %s") % [style, state]


## Feedback from the isolated preview only; never edits accepted or pending settings.
func set_capability_report(report: Dictionary) -> void:
	_capability_report = report.duplicate(true)
	_refresh_capability_feedback()


func _refresh_capability_feedback() -> void:
	if not is_instance_valid(_availability):
		return
	var state := str(_capability_report.get("state", "unavailable"))
	var configured := state == "configured"
	var details := PackedStringArray()
	if configured:
		var zones := _available_counts("zones")
		var effects := _available_counts("effects")
		_availability.text = tr("%d of %d enabled zones available on this aircraft.") % [zones.x, zones.y]
		if effects.y > 0:
			_availability.text += "\n" + tr("%d of %d enabled effects available.") % [effects.x, effects.y]
		for row: Dictionary in _capability_report.get("zones", []):
			var label := tr(str(ZONE_LABELS.get(str(row.get("id", "")), "Light")))
			details.append("%s — %s" % [label, _capability_status(row)])
		for row: Dictionary in _capability_report.get("effects", []):
			details.append("%s — %s" % [_effect_anchor_label(str(row.get("id", ""))), _capability_status(row)])
		details.append("")
		details.append(tr("Availability follows applied settings. Daylight, gear position and playback can hide supported lights or effects. Unavailable choices remain saved."))
	else:
		match state:
			"inherit": _availability.text = tr("Using the aircraft's standard lighting equipment.")
			"disabled": _availability.text = tr("Lighting is disabled for this build.")
			"original": _availability.text = tr("Showing original aircraft lighting. Select Draft to check your lighting choices.")
			_: _availability.text = tr("Lighting availability cannot be checked in this preview.")
	_availability_button.visible = configured
	_availability_details.text = "\n".join(details)
	_availability_details.visible = configured and _availability_button.button_pressed
	if is_instance_valid(_zone_selector):
		for index in _zone_selector.item_count:
			var id := str(_zone_selector.get_item_metadata(index))
			var row := _capability_row("zones", id)
			var label := tr(str(ZONE_LABELS.get(id, id)))
			if configured and not row.is_empty() and not bool(row.get("available", false)):
				label = tr("%s (unavailable)") % label
			_zone_selector.set_item_text(index, label)
	if is_instance_valid(_zone_availability):
		var zone := _capability_row("zones", _selected_zone_id)
		_zone_availability.text = _capability_status(zone) if configured and not zone.is_empty() else ""
		_zone_availability.visible = not _zone_availability.text.is_empty()
	for anchor: String in _effects_controls_by_anchor:
		var hint: Label = _effects_controls_by_anchor[anchor].get("availability")
		if not is_instance_valid(hint):
			continue
		var effect := _capability_row("effects", anchor)
		hint.text = _capability_status(effect) if configured and not effect.is_empty() else ""
		hint.visible = not hint.text.is_empty()


func _available_counts(key: String) -> Vector2i:
	var counts := Vector2i.ZERO
	for row: Dictionary in _capability_report.get(key, []):
		if bool(row.get("enabled", false)):
			counts.y += 1
			if bool(row.get("available", false)): counts.x += 1
	return counts


func _capability_row(key: String, id: String) -> Dictionary:
	for row: Dictionary in _capability_report.get(key, []):
		if str(row.get("id", "")) == id: return row
	return {}


func _capability_status(row: Dictionary) -> String:
	var status := tr("Available")
	if not bool(row.get("available", false)):
		match str(row.get("reason", "")):
			"unsupported_group": status = tr("Unavailable: this aircraft does not support this light group.")
			"missing_anchor": status = tr("Unavailable: no effect attachment is fitted.")
			_: status = tr("Unavailable: no compatible light fitting.")
	if not bool(row.get("enabled", false)):
		status = tr("Off in applied settings · %s") % status
	return status


func _emit_validity() -> void:
	if is_instance_valid(_sequence_editor):
		_sequence_editor.set_external_pending(_brightness_pending or _zone_pending or _effects_pending or _zone_text_pending)
	validity_changed.emit("lighting", has_pending_edit())


func _set_status(message: String) -> void:
	if is_instance_valid(_status):
		_status.text = tr(message)
		_status.visible = not message.is_empty()


func _find_item_metadata(selector: OptionButton, metadata: String) -> int:
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == metadata:
			return index
	return -1


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _first_error(errors: Variant) -> String:
	if errors is Array and not errors.is_empty():
		return str(errors[0])
	return tr("The lighting profile could not be applied.")
