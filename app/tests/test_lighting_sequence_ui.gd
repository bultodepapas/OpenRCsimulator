extends SceneTree

const SequenceEditor := preload("res://ui/workshop_lighting_sequence.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")

var _checks := 0
var _failures := 0
var _profiles: Array[Dictionary] = []
var _pending_events: Array[bool] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _record_profile(lighting: Dictionary) -> void:
	_profiles.append(lighting.duplicate(true))


func _record_pending(pending: bool) -> void:
	_pending_events.append(pending)


func _run() -> void:
	var editor := SequenceEditor.new()
	root.add_child(editor)
	await process_frame
	editor.profile_changed.connect(_record_profile)
	editor.pending_changed.connect(_record_pending)
	editor.configure(Profile.preset("neon_rgb"))
	editor.call("_on_open_toggled", true)
	var initial_state: Dictionary = editor.get_editor_state()
	_check("editor recovery state has the exact eight-field contract", initial_state.size() == 8
		and ["open", "selected_id", "duration_text", "period_text", "pattern_id", "color_text", "zone_ids", "effect_anchor_ids"].all(
			func(key: String) -> bool: return initial_state.has(key)))
	_check("Neon targets stay limited to zones present in its profile",
		not editor.get("_zone_controls").has("landing_lamp"))

	var pattern_selector := editor.get("_pattern_selector") as OptionButton
	_check("cue pattern menu excludes nested Sequence", _metadata_index(pattern_selector, "sequence") < 0)
	_press(editor, "AddLightingCue")
	var after_add: Dictionary = editor.get("_profile")
	var new_cue_id := str(editor.get("_selected_id"))
	var sequence_zone := _first_sequence_zone(after_add)
	_check("Add cue creates a valid custom sequence from Neon", after_add.selection == "custom"
		and after_add.sequence.size() == 1 and not new_cue_id.is_empty()
		and Profile.validate(after_add).ok and not sequence_zone.is_empty())
	_check("Add cue emits one complete profile immediately", _profiles.size() == 1
		and _profiles[0].sequence.size() == 1)

	var duration := editor.get("_duration") as LineEdit
	duration.text = "2.5"
	duration.text_changed.emit(duration.text)
	_check("unapplied duration is pending without emitting a profile", editor.has_pending_edit()
		and _profiles.size() == 1 and editor.pending_control() == editor.get("_apply_button"))
	_press(editor, "ApplyLightingCue")
	var after_apply: Dictionary = editor.get("_profile")
	_check("Apply converts duration seconds to accepted ticks", not editor.has_pending_edit()
		and after_apply.sequence[0].duration_ticks == 600 and _profiles.size() == 2)

	_press(editor, "DuplicateLightingCue")
	var duplicate_id := str(editor.get("_selected_id"))
	var cue_selector := editor.get("_cue_selector") as OptionButton
	_check("Duplicate inserts an ordered second cue", duplicate_id != new_cue_id
		and editor.get("_profile").sequence.size() == 2 and cue_selector.item_count == 2)
	_check("cue selector shows cumulative start and duration seconds",
		cue_selector.get_item_text(0).contains("Cue 1") and cue_selector.get_item_text(0).contains("0.0 s")
		and cue_selector.get_item_text(0).contains("2.5 s") and cue_selector.get_item_text(1).contains("2.5 s"),
		"first=%s second=%s" % [cue_selector.get_item_text(0), cue_selector.get_item_text(1)])
	_press(editor, "MoveLightingCueEarlier")
	_check("Move earlier changes saved order while preserving cue identity",
		editor.get("_profile").sequence[0].id == duplicate_id
		and str(editor.get("_selected_id")) == duplicate_id)

	duration = editor.get("_duration") as LineEdit
	duration.text = "not seconds"
	duration.text_changed.emit(duration.text)
	var profile_count := _profiles.size()
	editor.call("_on_cue_selected", 1)
	_check("pending raw text holds cue navigation", str(editor.get_editor_state().selected_id) == duplicate_id
		and editor.get("_cue_selector").selected == 0)
	_press(editor, "ApplyLightingCue")
	_check("invalid Apply remains pending and does not emit", editor.has_pending_edit()
		and _profiles.size() == profile_count and editor.pending_control() == duration)
	_check("Cancel restores accepted duration and releases navigation", editor.cancel_pending_edit()
		and not editor.has_pending_edit() and duration.text == "2.5")

	var hex := editor.find_child("SequencePaletteHex0", true, false) as LineEdit
	if hex != null:
		hex.text = "#3FA6FF"
		hex.text_changed.emit(hex.text)
	_check("hex palette edit stays local until Apply", editor.has_pending_edit() and _profiles.size() == profile_count)
	_press(editor, "ApplyLightingCue")
	_check("hex palette Apply updates the committed cue", not editor.has_pending_edit()
		and editor.get("_profile").sequence[0].pattern.palette[0] == "#3FA6FF")
	var picker := editor.find_child("SequencePalettePicker0", true, false) as ColorPickerButton
	if picker != null:
		picker.color_changed.emit(Color("#C05080"))
	_check("RGB picker updates the local hex entry", editor.has_pending_edit()
		and editor.get("_color_fields")[0].text == "#C05080")
	_press(editor, "ApplyLightingCue")
	_check("RGB picker color commits through Apply", editor.get("_profile").sequence[0].pattern.palette[0] == "#C05080")

	var add_color := editor.get("_add_color") as Button
	for _index: int in range(7):
		add_color.pressed.emit()
	_check("palette supports eight colors and blocks a ninth", editor.get("_color_fields").size() == 8
		and add_color.disabled)
	_press(editor, "ApplyLightingCue")
	_check("eight-color palette applies as one cue edit", editor.get("_profile").sequence[0].pattern.palette.size() == 8)
	var remove_color := editor.find_child("SequencePaletteRemove0", true, false) as Button
	if remove_color != null:
		remove_color.pressed.emit()
	_check("palette removal is a pending cue edit", editor.has_pending_edit()
		and editor.get_editor_state().color_text.size() == 7)
	_check("Cancel restores the accepted palette after removal", editor.cancel_pending_edit()
		and editor.get_editor_state().color_text.size() == 8)

	_press(editor, "RemoveLightingCue")
	_check("Remove cue preserves the remaining cue", editor.get("_profile").sequence.size() == 1)
	_press(editor, "RemoveLightingCue")
	var empty_sequence: Dictionary = editor.get("_profile")
	_check("removing the last cue clears orphan Sequence zone patterns", empty_sequence.sequence.is_empty()
		and empty_sequence.zones.all(func(zone: Dictionary) -> bool: return zone.pattern.id != "sequence"))

	_press(editor, "AddLightingCue")
	duration = editor.get("_duration") as LineEdit
	duration.text = "unfinished"
	duration.text_changed.emit(duration.text)
	var recovery: Dictionary = editor.get_editor_state()
	var accepted_profile: Dictionary = editor.get("_profile").duplicate(true)
	var recovery_emit_count := _profiles.size()
	editor.configure(accepted_profile)
	_check("configure clears pending state while retaining selected cue and section", not editor.has_pending_edit()
		and editor.get_editor_state().open and editor.get_editor_state().selected_id == recovery.selected_id)
	_check("explicit editor recovery preserves invalid raw timing", editor.restore_editor_state(recovery)
		and editor.has_pending_edit() and editor.get_editor_state().duration_text == "unfinished"
		and editor.pending_control() == editor.get("_duration"))
	_check("restoring pending text does not emit a lighting profile", _profiles.size() == recovery_emit_count)
	editor.cancel_pending_edit()

	_test_effect_and_lock_gates(editor)
	_check("pending signal reports dirty and applied transitions", _pending_events.has(true) and _pending_events.has(false))
	editor.free()
	await process_frame
	print("FW-RGB-09 sequence UI: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_effect_and_lock_gates(editor: VBoxContainer) -> void:
	var lighting: Dictionary = Profile.preset("night_aerobatics")
	lighting.effects.remove_at(1)
	var checked: Dictionary = Profile.validate(lighting)
	_check("test effect profile remains valid", checked.ok)
	if not checked.ok:
		return
	editor.configure(checked.profile)
	var zones: Dictionary = editor.get("_zone_controls")
	var effects: Dictionary = editor.get("_effect_controls")
	_check("orientation lock disables navigation targets", zones.has("nav_left") and zones.nav_left.disabled)
	_check("only installed anchors appear and disabled effects cannot be targeted",
		effects.has("vfx_tip_left") and not effects.has("vfx_tip_right") and effects.vfx_tip_left.disabled)

	var enabled_lighting: Dictionary = checked.profile.duplicate(true)
	enabled_lighting.effects[0].enabled = true
	var enabled_check: Dictionary = Profile.validate(enabled_lighting)
	_check("enabled effect fixture is a valid profile", enabled_check.ok)
	if not enabled_check.ok:
		return
	editor.configure(enabled_check.profile)
	_press(editor, "AddLightingCue")
	effects = editor.get("_effect_controls")
	_check("installed and enabled anchor becomes selectable", effects.has("vfx_tip_left")
		and not effects.vfx_tip_left.disabled)
	var effect_target: CheckButton = effects.get("vfx_tip_left")
	effect_target.set_pressed_no_signal(true)
	effect_target.toggled.emit(true)
	_press(editor, "ApplyLightingCue")
	_check("enabled effect target is saved with the cue",
		editor.get("_profile").sequence[0].effect_anchor_ids == ["vfx_tip_left"])


func _press(editor: Node, control_name: String) -> void:
	var button := editor.find_child(control_name, true, false) as Button
	if button != null:
		button.pressed.emit()


func _metadata_index(selector: OptionButton, metadata: String) -> int:
	for index: int in selector.item_count:
		if str(selector.get_item_metadata(index)) == metadata:
			return index
	return -1


func _first_sequence_zone(profile: Dictionary) -> Dictionary:
	for zone: Dictionary in profile.get("zones", []):
		if str(zone.get("pattern", {}).get("id", "")) == "sequence":
			return zone
	return {}
