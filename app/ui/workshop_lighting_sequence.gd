extends VBoxContainer
## Bounded cue editor. Its owner validates and records the emitted lighting profile.

const Profile := preload("res://render/lighting/lighting_profile.gd")
const Sequence := preload("res://workshop/lighting_sequence.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

signal profile_changed(lighting: Dictionary)
signal pending_changed(pending: bool)

const CUE_LIMIT := 32
const PALETTE_LIMIT := 8
const TICKS_PER_SECOND := 240.0
const MAX_TEXT_CHARS := 24
const MAX_COLOR_TEXT_CHARS := 16
const ZONE_LABELS := {
	"nav_left": "Port navigation", "nav_right": "Starboard navigation", "nav_tail": "Tail light",
	"strobe_left": "Port strobe", "strobe_right": "Starboard strobe", "strobe_dorsal": "Dorsal spine",
	"strobe_ventral": "Ventral bars", "strip_left": "Port wing strip", "strip_right": "Starboard wing strip",
	"strip_top_left": "Port upper strip", "strip_top_right": "Starboard upper strip", "strip_belly": "Belly strip",
	"landing_lamp": "Landing lamp",
}

var _profile: Dictionary = {}
var _profile_valid := false
var _open := false
var _selected_id := ""
var _pending := false
var _external_pending := false
var _syncing := false
var _last_errors: Array = []

var _open_button: Button
var _body: VBoxContainer
var _cue_selector: OptionButton
var _cue_summary: Label
var _duration: LineEdit
var _period: LineEdit
var _pattern_selector: OptionButton
var _palette_list: VBoxContainer
var _add_color: Button
var _zone_targets: FlowContainer
var _effect_targets: FlowContainer
var _zone_controls: Dictionary = {}
var _effect_controls: Dictionary = {}
var _color_fields: Array[LineEdit] = []
var _apply_button: Button
var _cancel_button: Button
var _status: Label
var _structure_buttons: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 9)
	_build_ui()
	if _profile.is_empty():
		configure(Profile.defaults())
	else:
		_sync_view()


func _build_ui() -> void:
	_open_button = Button.new()
	_open_button.name = "LightingSequenceToggle"
	_open_button.text = tr("Edit sequence")
	_open_button.toggle_mode = true
	_open_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_open_button.toggled.connect(_on_open_toggled)
	add_child(_open_button)

	_body = VBoxContainer.new()
	_body.name = "LightingSequenceEditor"
	_body.add_theme_constant_override("separation", 12)
	_body.visible = false
	add_child(_body)

	var cue_heading := Label.new()
	cue_heading.text = tr("Sequence cues")
	cue_heading.theme_type_variation = "SectionLabel"
	cue_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(cue_heading)
	var preview_note := Label.new()
	preview_note.name = "LightingSequencePreviewNote"
	preview_note.text = tr("Cues play in order. Use Restart preview, then Play preview to review their timing.")
	preview_note.theme_type_variation = "SecondaryLabel"
	preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(preview_note)
	var target_note := Label.new()
	target_note.name = "LightingSequenceTargetNote"
	target_note.text = tr("Cue targets use the Sequence pattern. Zones left without cues return to steady lighting; Undo restores the prior profile.")
	target_note.theme_type_variation = "SecondaryLabel"
	target_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(target_note)

	var cue_label := Label.new()
	cue_label.text = tr("Selected cue")
	cue_label.theme_type_variation = "SecondaryLabel"
	cue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(cue_label)
	_cue_selector = OptionButton.new()
	_cue_selector.name = "LightingSequenceCue"
	_cue_selector.fit_to_longest_item = false
	_cue_selector.clip_text = true
	_cue_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cue_selector.item_selected.connect(_on_cue_selected)
	_body.add_child(_cue_selector)

	_cue_summary = Label.new()
	_cue_summary.name = "LightingSequenceSummary"
	_cue_summary.theme_type_variation = "SecondaryLabel"
	_cue_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_cue_summary)

	var cue_actions := HFlowContainer.new()
	cue_actions.name = "LightingSequenceActions"
	cue_actions.add_theme_constant_override("h_separation", 6)
	cue_actions.add_theme_constant_override("v_separation", 6)
	_body.add_child(cue_actions)
	_add_structure_button(cue_actions, "AddLightingCue", "Add cue", _add_cue)
	_add_structure_button(cue_actions, "DuplicateLightingCue", "Duplicate cue", _duplicate_cue)
	_add_structure_button(cue_actions, "MoveLightingCueEarlier", "Move earlier", _move_earlier)
	_add_structure_button(cue_actions, "MoveLightingCueLater", "Move later", _move_later)
	_add_structure_button(cue_actions, "RemoveLightingCue", "Remove cue", _remove_cue)

	_body.add_child(HSeparator.new())
	var timing_heading := Label.new()
	timing_heading.text = tr("Timing and pattern")
	timing_heading.theme_type_variation = "SectionLabel"
	timing_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(timing_heading)
	var duration_label := Label.new()
	duration_label.text = tr("Cue duration (seconds)")
	duration_label.theme_type_variation = "SecondaryLabel"
	_body.add_child(duration_label)
	_duration = LineEdit.new()
	_duration.name = "LightingSequenceDuration"
	_duration.placeholder_text = tr("Seconds, up to 60")
	_duration.max_length = MAX_TEXT_CHARS
	_duration.text_changed.connect(_on_text_edited)
	_duration.text_submitted.connect(func(_value: String) -> void: _duration.release_focus())
	_body.add_child(_duration)

	var cycle_label := Label.new()
	cycle_label.text = tr("Pattern cycle (seconds)")
	cycle_label.theme_type_variation = "SecondaryLabel"
	_body.add_child(cycle_label)
	_period = LineEdit.new()
	_period.name = "LightingSequenceCycle"
	_period.placeholder_text = tr("0.25 to 60 seconds")
	_period.max_length = MAX_TEXT_CHARS
	_period.text_changed.connect(_on_text_edited)
	_period.text_submitted.connect(func(_value: String) -> void: _period.release_focus())
	_body.add_child(_period)

	var pattern_label := Label.new()
	pattern_label.text = tr("Pattern")
	pattern_label.theme_type_variation = "SecondaryLabel"
	_body.add_child(pattern_label)
	_pattern_selector = OptionButton.new()
	_pattern_selector.name = "LightingSequencePattern"
	_pattern_selector.fit_to_longest_item = false
	_pattern_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pattern_id: String in Profile.PATTERN_IDS:
		if pattern_id == "sequence":
			continue
		_pattern_selector.add_item(tr(pattern_id.capitalize()))
		_pattern_selector.set_item_metadata(_pattern_selector.item_count - 1, pattern_id)
	_pattern_selector.item_selected.connect(_on_pattern_selected)
	_body.add_child(_pattern_selector)

	_body.add_child(HSeparator.new())
	var palette_heading := Label.new()
	palette_heading.text = tr("RGB palette")
	palette_heading.theme_type_variation = "SectionLabel"
	_body.add_child(palette_heading)
	_palette_list = VBoxContainer.new()
	_palette_list.name = "LightingSequencePalette"
	_palette_list.add_theme_constant_override("separation", 5)
	_body.add_child(_palette_list)
	_add_color = Button.new()
	_add_color.name = "AddLightingSequenceColor"
	_add_color.text = tr("Add color")
	_add_color.pressed.connect(_add_palette_color)
	_body.add_child(_add_color)

	var zones_heading := Label.new()
	zones_heading.text = tr("Target zones")
	zones_heading.theme_type_variation = "SectionLabel"
	_body.add_child(zones_heading)
	_zone_targets = FlowContainer.new()
	_zone_targets.name = "LightingSequenceZones"
	_zone_targets.add_theme_constant_override("h_separation", 8)
	_zone_targets.add_theme_constant_override("v_separation", 3)
	_body.add_child(_zone_targets)

	var effects_heading := Label.new()
	effects_heading.text = tr("Enabled effects")
	effects_heading.theme_type_variation = "SectionLabel"
	_body.add_child(effects_heading)
	_effect_targets = FlowContainer.new()
	_effect_targets.name = "LightingSequenceEffects"
	_effect_targets.add_theme_constant_override("h_separation", 8)
	_effect_targets.add_theme_constant_override("v_separation", 3)
	_body.add_child(_effect_targets)

	var actions := HFlowContainer.new()
	actions.name = "LightingSequenceEditActions"
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	_body.add_child(actions)
	_cancel_button = Button.new()
	_cancel_button.name = "CancelLightingCue"
	_cancel_button.text = tr("Cancel")
	_cancel_button.pressed.connect(cancel_pending_edit)
	actions.add_child(_cancel_button)
	_apply_button = Button.new()
	_apply_button.name = "ApplyLightingCue"
	_apply_button.text = tr("Apply cue")
	_apply_button.pressed.connect(_apply_cue)
	actions.add_child(_apply_button)

	_status = Label.new()
	_status.name = "LightingSequenceStatus"
	_status.add_theme_color_override("font_color", Color(0.91, 0.70, 0.38))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)


func _add_structure_button(parent: Control, control_name: String, label_text: String, callback: Callable) -> void:
	var button := Button.new()
	button.name = control_name
	button.text = tr(label_text)
	button.pressed.connect(callback)
	parent.add_child(button)
	_structure_buttons[control_name] = button


func configure(lighting: Dictionary) -> void:
	var previous_id := _selected_id
	var was_open := _open
	var checked: Dictionary = Profile.validate(lighting)
	_profile_valid = bool(checked.get("ok", false))
	_profile = checked.get("profile", Profile.defaults()).duplicate(true) if _profile_valid else Profile.defaults()
	_open = was_open
	_selected_id = previous_id if _cue_exists(previous_id) else _first_cue_id()
	_last_errors.clear()
	if not _profile_valid:
		_last_errors = checked.get("errors", []).duplicate()
		_set_status(_first_error(_last_errors, tr("Lighting sequence profile is invalid.")))
	else:
		_set_status("")
	_set_pending(false)
	_sync_view()


func get_editor_state() -> Dictionary:
	var state: Dictionary = Sequence.editor_state(_profile, _selected_id, _open).duplicate(true)
	if state.size() != 8:
		state = _empty_editor_state()
	state.open = _open
	state.selected_id = _selected_id
	if is_instance_valid(_duration):
		state.duration_text = _duration.text.substr(0, MAX_TEXT_CHARS)
	if is_instance_valid(_period):
		state.period_text = _period.text.substr(0, MAX_TEXT_CHARS)
	if is_instance_valid(_pattern_selector) and _pattern_selector.item_count > 0:
		var metadata: Variant = _pattern_selector.get_item_metadata(maxi(_pattern_selector.selected, 0))
		if metadata != null:
			state.pattern_id = str(metadata).substr(0, MAX_TEXT_CHARS)
	var colors: Array[String] = []
	for field: LineEdit in _color_fields:
		colors.append(field.text.substr(0, MAX_COLOR_TEXT_CHARS))
	if is_instance_valid(_palette_list):
		state.color_text = colors
	var zones: Array[String] = []
	for zone_id: String in _zone_controls:
		var control: CheckButton = _zone_controls[zone_id]
		if control.button_pressed:
			zones.append(zone_id)
	if is_instance_valid(_zone_targets):
		state.zone_ids = zones
	var anchors: Array[String] = []
	for anchor_id: String in _effect_controls:
		var control: CheckButton = _effect_controls[anchor_id]
		if control.button_pressed:
			anchors.append(anchor_id)
	if is_instance_valid(_effect_targets):
		state.effect_anchor_ids = anchors
	return state


func restore_editor_state(state: Dictionary) -> bool:
	var validation: Dictionary = Sequence.validate_editor_state(state)
	if not bool(validation.get("ok", false)):
		return false
	var value: Dictionary = validation.get("value", {})
	if value.size() != 8:
		return false
	var selected_id := str(value.get("selected_id", ""))
	if selected_id.is_empty():
		if not _profile.get("sequence", []).is_empty():
			return false
	elif not _cue_exists(selected_id):
		return false
	if not _state_references_current_profile(value):
		return false
	_open = bool(value.open)
	_selected_id = selected_id
	_sync_view(value)
	_recompute_pending()
	return true


func has_pending_edit() -> bool:
	return _pending


func pending_control() -> Control:
	if not _pending:
		return null
	if not _duration_is_valid():
		return _duration
	if not _period_is_valid():
		return _period
	for field: LineEdit in _color_fields:
		if not _is_rgb_hex(field.text):
			return field
	return _apply_button


func cancel_pending_edit() -> bool:
	if not _pending:
		return false
	_last_errors.clear()
	_set_status("")
	_sync_view()
	_set_pending(false)
	return true


func set_external_pending(value: bool) -> void:
	_external_pending = value
	_update_control_states()


func _empty_editor_state() -> Dictionary:
	return {
		"open": _open,
		"selected_id": _selected_id,
		"duration_text": "1.0",
		"period_text": "1.0",
		"pattern_id": "steady",
		"color_text": ["#FFFFFF"],
		"zone_ids": [],
		"effect_anchor_ids": [],
	}


func _on_open_toggled(value: bool) -> void:
	if _syncing:
		return
	if _pending or _external_pending:
		_syncing = true
		_open_button.button_pressed = _open
		_syncing = false
		_set_status(tr("Apply or cancel this cue before changing sequence sections."))
		return
	_open = value
	_body.visible = value
	_open_button.text = tr("Hide sequence" if value else "Edit sequence")


func _on_cue_selected(index: int) -> void:
	if _syncing or index < 0 or index >= _cue_selector.item_count:
		return
	if _pending or _external_pending:
		_sync_cue_selector()
		_set_status(tr("Apply or cancel the current cue before selecting another cue."))
		return
	var selected: Variant = _cue_selector.get_item_metadata(index)
	if selected == null or not _cue_exists(str(selected)):
		return
	_selected_id = str(selected)
	_last_errors.clear()
	_set_status("")
	_sync_view()


func _on_text_edited(_value: String) -> void:
	if _syncing:
		return
	_last_errors.clear()
	_set_status("")
	_recompute_pending()


func _on_pattern_selected(index: int) -> void:
	if _syncing or index < 0 or index >= _pattern_selector.item_count:
		return
	var pattern_id := str(_pattern_selector.get_item_metadata(index))
	if pattern_id == "sequence":
		return
	_last_errors.clear()
	_set_status("")
	_recompute_pending()


func _on_color_text_changed(value: String, index: int) -> void:
	if _syncing:
		return
	if index >= 0 and index < _color_fields.size() and _is_rgb_hex(value):
		var picker := _palette_list.get_node_or_null("SequencePaletteColor%d/SequencePalettePicker%d" % [index, index]) as ColorPickerButton
		if picker != null:
			_syncing = true
			picker.color = Color.from_string(value, Color.WHITE)
			_syncing = false
	_last_errors.clear()
	_set_status("")
	_recompute_pending()


func _on_color_picked(index: int, color: Color) -> void:
	if _syncing or index < 0 or index >= _color_fields.size():
		return
	_syncing = true
	_color_fields[index].text = "#" + color.to_html(false).to_upper()
	_syncing = false
	_last_errors.clear()
	_set_status("")
	_recompute_pending()


func _on_zone_toggled(_pressed: bool, _zone_id: String) -> void:
	if _syncing:
		return
	_last_errors.clear()
	_set_status("")
	_recompute_pending()


func _on_effect_toggled(_pressed: bool, _anchor_id: String) -> void:
	if _syncing:
		return
	_last_errors.clear()
	_set_status("")
	_recompute_pending()


func _add_palette_color() -> void:
	if _syncing or _color_fields.size() >= PALETTE_LIMIT or _has_invalid_palette_text():
		return
	var colors: Array[String] = []
	for field: LineEdit in _color_fields:
		colors.append(field.text)
	colors.append(colors.back() if not colors.is_empty() else "#FFFFFF")
	var state := get_editor_state()
	state.color_text = colors
	_sync_view(state)
	_last_errors.clear()
	_recompute_pending()


func _remove_palette_color(index: int) -> void:
	if _syncing or _color_fields.size() <= 1 or _has_invalid_palette_text():
		return
	var colors: Array[String] = []
	for field: LineEdit in _color_fields:
		colors.append(field.text)
	if index < 0 or index >= colors.size():
		return
	colors.remove_at(index)
	var state := get_editor_state()
	state.color_text = colors
	_sync_view(state)
	_last_errors.clear()
	_recompute_pending()


func _add_cue() -> void:
	if not _can_run_structure_action():
		return
	var result: Dictionary = Sequence.add_cue(_profile, _selected_id)
	_commit_structure_result(result)


func _duplicate_cue() -> void:
	if not _can_run_structure_action() or _selected_id.is_empty():
		return
	var result: Dictionary = Sequence.duplicate_cue(_profile, _selected_id)
	_commit_structure_result(result)


func _move_earlier() -> void:
	_move_cue(-1)


func _move_later() -> void:
	_move_cue(1)


func _move_cue(direction: int) -> void:
	if not _can_run_structure_action() or _selected_id.is_empty():
		return
	var result: Dictionary = Sequence.move_cue(_profile, _selected_id, direction)
	_commit_structure_result(result)


func _remove_cue() -> void:
	if not _can_run_structure_action() or _selected_id.is_empty():
		return
	var result: Dictionary = Sequence.remove_cue(_profile, _selected_id)
	_commit_structure_result(result)


func _apply_cue() -> void:
	if not _pending or _external_pending or _selected_id.is_empty():
		return
	var result: Dictionary = Sequence.apply_cue(_profile, get_editor_state())
	if not bool(result.get("ok", false)):
		_last_errors = result.get("errors", []).duplicate()
		_set_status(_first_error(_last_errors, tr("Correct this cue before applying it.")))
		_update_control_states()
		return
	_commit_profile_result(result)


func _commit_structure_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_last_errors = result.get("errors", []).duplicate()
		_set_status(_first_error(_last_errors, tr("This cue change is not available.")))
		return
	_commit_profile_result(result)


func _commit_profile_result(result: Dictionary) -> void:
	var raw: Variant = result.get("profile", {})
	var checked: Dictionary = Profile.validate(raw)
	if not bool(checked.get("ok", false)):
		_last_errors = checked.get("errors", []).duplicate()
		_set_status(_first_error(_last_errors, tr("The cue change did not produce a valid lighting profile.")))
		_update_control_states()
		return
	_profile = checked.profile.duplicate(true)
	_profile_valid = true
	_selected_id = str(result.get("selected_id", _selected_id))
	if not _cue_exists(_selected_id):
		_selected_id = _first_cue_id()
	_last_errors.clear()
	_set_status("")
	_set_pending(false)
	_sync_view()
	profile_changed.emit(_profile.duplicate(true))


func _can_run_structure_action() -> bool:
	return _profile_valid and not _pending and not _external_pending


func _sync_view(raw_state: Dictionary = {}) -> void:
	if not is_instance_valid(_open_button):
		return
	_syncing = true
	_body.visible = _open
	_open_button.button_pressed = _open
	_open_button.text = tr("Hide sequence" if _open else "Edit sequence")
	_sync_cue_selector()
	var state := raw_state.duplicate(true) if not raw_state.is_empty() else Sequence.editor_state(_profile, _selected_id, _open)
	if state.size() != 8:
		state = _empty_editor_state()
	state.open = _open
	state.selected_id = _selected_id
	_duration.text = str(state.get("duration_text", "1.0")).substr(0, MAX_TEXT_CHARS)
	_period.text = str(state.get("period_text", "1.0")).substr(0, MAX_TEXT_CHARS)
	_select_metadata(_pattern_selector, str(state.get("pattern_id", "steady")))
	_rebuild_palette(state.get("color_text", ["#FFFFFF"]))
	_rebuild_target_controls(state)
	_cue_summary.text = _build_cue_summary()
	_syncing = false
	_update_control_states()


func _sync_cue_selector() -> void:
	_cue_selector.clear()
	var cues: Array = _profile.get("sequence", [])
	var elapsed_ticks := 0
	for index: int in cues.size():
		var cue: Dictionary = cues[index]
		var duration_ticks := int(cue.get("duration_ticks", 0))
		var start_seconds := float(elapsed_ticks) / TICKS_PER_SECOND
		var duration_seconds := float(duration_ticks) / TICKS_PER_SECOND
		_cue_selector.add_item(tr("Cue %d · %s s · %s s") % [index + 1, String.num(start_seconds, 2), String.num(duration_seconds, 2)])
		_cue_selector.set_item_metadata(_cue_selector.item_count - 1, str(cue.get("id", "")))
		elapsed_ticks += duration_ticks
	_select_metadata(_cue_selector, _selected_id)


func _build_cue_summary() -> String:
	var cues: Array = _profile.get("sequence", [])
	var total_ticks := 0
	var selected_index := -1
	for index: int in cues.size():
		var cue: Dictionary = cues[index]
		total_ticks += int(cue.get("duration_ticks", 0))
		if str(cue.get("id", "")) == _selected_id:
			selected_index = index
	if cues.is_empty():
		return tr("No cues yet. Add a cue to create a sequence for this lighting profile.")
	var total_seconds := float(total_ticks) / TICKS_PER_SECOND
	if selected_index >= 0:
		var start_ticks := 0
		for index in selected_index:
			start_ticks += int(cues[index].get("duration_ticks", 0))
		var selected: Dictionary = cues[selected_index]
		return tr("Cue %d starts at %s s; duration %s s. Total sequence: %s s.") % [
			selected_index + 1,
			String.num(float(start_ticks) / TICKS_PER_SECOND, 2),
			String.num(float(selected.get("duration_ticks", 0)) / TICKS_PER_SECOND, 2),
			String.num(total_seconds, 2),
		]
	return tr("Total sequence: %s s.") % String.num(total_seconds, 2)


func _rebuild_palette(raw_colors: Variant) -> void:
	_clear_children(_palette_list)
	_color_fields.clear()
	var colors: Array = raw_colors if raw_colors is Array else ["#FFFFFF"]
	for index: int in mini(colors.size(), PALETTE_LIMIT):
		_add_palette_row(index, str(colors[index]))
	_add_color.disabled = _color_fields.size() >= PALETTE_LIMIT


func _add_palette_row(index: int, color_text: String) -> void:
	var row := HFlowContainer.new()
	row.name = "SequencePaletteColor%d" % index
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	var picker := ColorPickerButton.new()
	picker.name = "SequencePalettePicker%d" % index
	picker.custom_minimum_size = Vector2(42, 32)
	picker.edit_alpha = false
	picker.color = Color.from_string(color_text, Color.WHITE)
	picker.tooltip_text = tr("Choose palette color %d") % (index + 1)
	picker.color_changed.connect(func(color: Color) -> void: _on_color_picked(index, color))
	row.add_child(picker)
	var hex := LineEdit.new()
	hex.name = "SequencePaletteHex%d" % index
	hex.placeholder_text = tr("#RRGGBB")
	hex.max_length = MAX_COLOR_TEXT_CHARS
	hex.text = color_text.substr(0, MAX_COLOR_TEXT_CHARS)
	hex.custom_minimum_size.x = 100
	hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hex.add_theme_font_size_override("font_size", UiTheme._font_size(13))
	hex.text_changed.connect(func(value: String) -> void: _on_color_text_changed(value, index))
	hex.text_submitted.connect(func(_value: String) -> void: hex.release_focus())
	row.add_child(hex)
	var remove := Button.new()
	remove.name = "SequencePaletteRemove%d" % index
	remove.text = tr("Remove")
	remove.pressed.connect(func() -> void: _remove_palette_color(index))
	row.add_child(remove)
	_palette_list.add_child(row)
	_color_fields.append(hex)


func _rebuild_target_controls(state: Dictionary) -> void:
	_clear_children(_zone_targets)
	_clear_children(_effect_targets)
	_zone_controls.clear()
	_effect_controls.clear()
	var selected_zones: Array = state.get("zone_ids", [])
	var selected_effects: Array = state.get("effect_anchor_ids", [])
	var orientation_locked := bool(_profile.get("orientation_lock", false))
	for zone_value: Variant in _profile.get("zones", []):
		if not zone_value is Dictionary:
			continue
		var zone: Dictionary = zone_value
		var zone_id := str(zone.get("id", ""))
		if zone_id.is_empty():
			continue
		var checkbox := CheckButton.new()
		checkbox.name = "SequenceZone_" + zone_id
		checkbox.text = tr(_zone_label(zone_id))
		checkbox.set_pressed_no_signal(selected_zones.has(zone_id))
		var orientation_locked_zone := orientation_locked and zone_id.begins_with("nav_")
		var unavailable_zone := not bool(zone.get("enabled", false)) and not selected_zones.has(zone_id)
		checkbox.disabled = orientation_locked_zone or unavailable_zone
		checkbox.tooltip_text = tr("Orientation lock preserves this navigation target.") if orientation_locked_zone else ""
		checkbox.toggled.connect(_on_zone_toggled.bind(zone_id))
		_zone_targets.add_child(checkbox)
		_zone_controls[zone_id] = checkbox
	for effect_value: Variant in _profile.get("effects", []):
		if not effect_value is Dictionary:
			continue
		var effect: Dictionary = effect_value
		var anchor_id := str(effect.get("anchor_id", ""))
		if anchor_id.is_empty():
			continue
		var checkbox := CheckButton.new()
		checkbox.name = "SequenceEffect_" + anchor_id
		checkbox.text = tr(_effect_label(anchor_id))
		checkbox.set_pressed_no_signal(selected_effects.has(anchor_id))
		var installed_and_enabled := bool(effect.get("enabled", false))
		checkbox.disabled = not installed_and_enabled
		checkbox.tooltip_text = tr("This effect anchor must be installed and enabled in Lighting effects.") if not installed_and_enabled else ""
		checkbox.toggled.connect(_on_effect_toggled.bind(anchor_id))
		_effect_targets.add_child(checkbox)
		_effect_controls[anchor_id] = checkbox


func _update_control_states() -> void:
	if not is_instance_valid(_open_button):
		return
	var can_navigate := not _pending and not _external_pending
	var has_cue := _cue_exists(_selected_id)
	var can_edit_fields := _profile_valid and has_cue and not _external_pending
	_open_button.disabled = not can_navigate
	_cue_selector.disabled = not can_navigate or _cue_selector.item_count <= 1
	_structure_buttons["AddLightingCue"].disabled = not _can_run_structure_action() or _profile.get("sequence", []).size() >= CUE_LIMIT
	_structure_buttons["DuplicateLightingCue"].disabled = not _can_run_structure_action() or not has_cue or _profile.get("sequence", []).size() >= CUE_LIMIT
	var cue_index := _cue_index(_selected_id)
	_structure_buttons["MoveLightingCueEarlier"].disabled = not _can_run_structure_action() or cue_index <= 0
	_structure_buttons["MoveLightingCueLater"].disabled = not _can_run_structure_action() or cue_index < 0 or cue_index >= _profile.get("sequence", []).size() - 1
	_structure_buttons["RemoveLightingCue"].disabled = not _can_run_structure_action() or not has_cue
	_duration.editable = can_edit_fields
	_period.editable = can_edit_fields
	_pattern_selector.disabled = not can_edit_fields
	_add_color.disabled = not can_edit_fields or _color_fields.size() >= PALETTE_LIMIT or _has_invalid_palette_text()
	for field: LineEdit in _color_fields:
		field.editable = can_edit_fields
	for row: Node in _palette_list.get_children():
		var picker := row.find_child("SequencePalettePicker%d" % _palette_row_index(row), false, false) as ColorPickerButton
		var remove := row.find_child("SequencePaletteRemove%d" % _palette_row_index(row), false, false) as Button
		if picker != null:
			picker.disabled = not can_edit_fields
		if remove != null:
			remove.disabled = not can_edit_fields or _color_fields.size() <= 1 or _has_invalid_palette_text()
	for zone_id: String in _zone_controls:
		var checkbox: CheckButton = _zone_controls[zone_id]
		var zone := _zone_by_id(zone_id)
		var locked_navigation := bool(_profile.get("orientation_lock", false)) and zone_id.begins_with("nav_")
		var disabled_target := not bool(zone.get("enabled", false)) and not checkbox.button_pressed
		checkbox.disabled = not can_edit_fields or locked_navigation or disabled_target
	for checkbox: CheckButton in _effect_controls.values():
		var effect: Dictionary = _effect_by_anchor(checkbox.name.trim_prefix("SequenceEffect_"))
		checkbox.disabled = not can_edit_fields or not bool(effect.get("enabled", false))
	_apply_button.disabled = not _pending or _external_pending or not has_cue
	_cancel_button.disabled = not _pending
	_status.visible = not _status.text.is_empty()


func _palette_row_index(row: Node) -> int:
	var name_value := str(row.name)
	return name_value.trim_prefix("SequencePaletteColor").to_int()


func _recompute_pending() -> void:
	var baseline: Dictionary = Sequence.editor_state(_profile, _selected_id, _open)
	var current := get_editor_state()
	_set_pending(current != baseline)


func _set_pending(value: bool) -> void:
	if _pending == value:
		_update_control_states()
		return
	_pending = value
	pending_changed.emit(value)
	_update_control_states()


func _duration_is_valid() -> bool:
	return _bounded_number(_duration.text, 1.0 / TICKS_PER_SECOND, 60.0)


func _period_is_valid() -> bool:
	return _bounded_number(_period.text, 0.25, 60.0)


func _bounded_number(raw: String, minimum: float, maximum: float) -> bool:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty() or not trimmed.is_valid_float():
		return false
	var value := float(trimmed)
	return is_finite(value) and value >= minimum and value <= maximum


func _has_invalid_palette_text() -> bool:
	for field: LineEdit in _color_fields:
		if not _is_rgb_hex(field.text):
			return true
	return false


func _is_rgb_hex(value: String) -> bool:
	return value.length() == 7 and value.begins_with("#") and value.substr(1).is_valid_hex_number()


func _state_references_current_profile(state: Dictionary) -> bool:
	var zone_ids: Dictionary = {}
	for zone_value: Variant in _profile.get("zones", []):
		if zone_value is Dictionary:
			zone_ids[str(zone_value.get("id", ""))] = true
	for zone_id: Variant in state.get("zone_ids", []):
		if typeof(zone_id) != TYPE_STRING or not zone_ids.has(str(zone_id)):
			return false
	var anchors: Dictionary = {}
	for effect_value: Variant in _profile.get("effects", []):
		if effect_value is Dictionary:
			anchors[str(effect_value.get("anchor_id", ""))] = true
	for anchor_id: Variant in state.get("effect_anchor_ids", []):
		if typeof(anchor_id) != TYPE_STRING or not anchors.has(str(anchor_id)):
			return false
	return true


func _cue_exists(cue_id: String) -> bool:
	return _cue_index(cue_id) >= 0


func _cue_index(cue_id: String) -> int:
	if cue_id.is_empty():
		return -1
	var cues: Array = _profile.get("sequence", [])
	for index: int in cues.size():
		if str(cues[index].get("id", "")) == cue_id:
			return index
	return -1


func _first_cue_id() -> String:
	var cues: Array = _profile.get("sequence", [])
	return str(cues[0].get("id", "")) if not cues.is_empty() else ""


func _select_metadata(control: OptionButton, value: String) -> void:
	for index: int in control.item_count:
		if str(control.get_item_metadata(index)) == value:
			control.select(index)
			return
	if control.item_count > 0:
		control.select(0)


func _zone_label(zone_id: String) -> String:
	if ZONE_LABELS.has(zone_id):
		return tr(str(ZONE_LABELS[zone_id]))
	var words := zone_id.replace("_", " ").split(" ", false)
	for index: int in words.size():
		words[index] = words[index].capitalize()
	return " ".join(words)


func _effect_label(anchor_id: String) -> String:
	match anchor_id:
		"vfx_tip_left": return tr("Left wingtip")
		"vfx_tip_right": return tr("Right wingtip")
		_: return _zone_label(anchor_id)


func _effect_by_anchor(anchor_id: String) -> Dictionary:
	for effect_value: Variant in _profile.get("effects", []):
		if effect_value is Dictionary and str(effect_value.get("anchor_id", "")) == anchor_id:
			return effect_value
	return {}


func _zone_by_id(zone_id: String) -> Dictionary:
	for zone_value: Variant in _profile.get("zones", []):
		if zone_value is Dictionary and str(zone_value.get("id", "")) == zone_id:
			return zone_value
	return {}


func _first_error(errors: Array, fallback: String) -> String:
	return str(errors[0]) if not errors.is_empty() else fallback


func _set_status(value: String) -> void:
	if is_instance_valid(_status):
		_status.text = value
		_status.visible = not value.is_empty()


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
