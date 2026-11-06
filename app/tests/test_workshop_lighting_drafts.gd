extends SceneTree
## AE-09d-R3 / A17: pending values, accepted data and available actions are separate.

const Workshop := preload("res://ui/workshop.gd")
const DraftStore := preload("res://workshop/draft_store.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
var ui: RefCounted
var _checks := 0
var _failures := 0
var _root := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	ui = UiDriver.new(self)
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	_root = "user://test_lighting_drafts_%d" % Time.get_ticks_usec()
	await _history()
	await _recovery()
	await _replacement()
	ui = null
	await process_frame
	print("Lighting drafts: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok: print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _editor(key: String, recover := false) -> CanvasLayer:
	var editor: CanvasLayer = Workshop.new()
	editor.variants_root = _root + "/" + key + "/library"
	editor.recovery_root = _root + "/" + key + "/recovery"
	editor.recovery_enabled = recover
	root.add_child(editor)
	await ui.settle()
	return editor


func _click(button: Button) -> void:
	_check("action is enabled: " + button.name, not button.disabled)
	if button.disabled: return
	button.grab_focus()
	await ui.tap(KEY_ENTER)


func _choose(picker: OptionButton, metadata: String) -> void:
	var index := -1
	for item: int in picker.item_count:
		if str(picker.get_item_metadata(item)) == metadata: index = item
	_check("choice exists: " + metadata, index >= 0)
	if index < 0: return
	picker.grab_focus()
	await ui.tap(KEY_SPACE)
	var popup := picker.get_popup()
	popup.set_focused_item(index)
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		event.window_id = popup.get_window_id()
		Input.parse_input_event(event)
	await ui.settle()
	_check("popup selected " + metadata, picker.selected == index and not popup.visible)


func _edit(field: LineEdit, text: String) -> void:
	field.grab_focus()
	field.edit()
	field.select_all()
	await ui.tap(KEY_BACKSPACE)
	for index: int in text.length():
		var event := InputEventKey.new()
		event.unicode = text.unicode_at(index)
		event.pressed = true
		Input.parse_input_event(event)
	await ui.settle()
	_check("raw text entered through the field", field.text == text, field.text)


func _window_button(dialog: Window, label: String) -> void:
	var target: Button
	for button: Node in dialog.find_children("*", "Button", true, false):
		if button.text == label: target = button
	_check("dialog action exists: " + label, target != null and not target.disabled)
	if target == null: return
	target.grab_focus()
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		dialog.push_input(event)
	await ui.settle()


func _lighting(editor: CanvasLayer) -> Control:
	editor._set_page("lighting")
	var panel: Control = editor._page_nodes.lighting
	await _choose(panel._preset, "custom")
	await _click(panel._zone_button)
	await _choose(panel._zone_selector, "landing_lamp")
	return panel


func _zone(profile: Dictionary) -> Dictionary:
	for zone: Dictionary in profile.zones:
		if zone.id == "landing_lamp": return zone
	return {}


func _same_data(left: Variant, right: Variant) -> bool:
	# JSON has neither typed arrays nor separate integer/float number types.
	# Full-precision round trips compare every value without those runtime tags.
	return JSON.parse_string(JSON.stringify(left, "", true, true)) == JSON.parse_string(JSON.stringify(right, "", true, true))


func _blocked(editor: CanvasLayer, panel: Control) -> bool:
	return panel.has_pending_edit() and editor.has_unsaved_changes() and editor.save_button.disabled and editor._trial_button.disabled


func _history() -> void:
	var editor := await _editor("history")
	var panel := await _lighting(editor)
	editor._clear_history()
	editor.set_recipe({power_multiplier = 1.1})
	var accepted: Dictionary = editor.get_presentation()
	panel._zone_brightness.value = 0.42
	await _click(editor._undo_button)
	_check("Undo changes only the accepted recipe", editor.get_recipe().power_multiplier == 1.0 and editor.get_presentation() == accepted)
	_check("Undo retains proposed zone brightness and blocked actions", panel._zone_brightness.value == 0.42 and _blocked(editor, panel))
	await _click(editor._redo_button)
	_check("Redo retains the same unapplied zone", editor.get_recipe().power_multiplier == 1.1
		and panel._zone_brightness.value == 0.42 and _blocked(editor, panel) and editor.get_presentation() == accepted)
	await _click(panel._zone_apply)
	_check("explicit Apply publishes restored brightness", _zone(editor.get_presentation().lighting).brightness == 0.42 and not panel.has_pending_edit())
	panel._zone_brightness.value = 0.18
	var undo: Array = editor._undo_history.duplicate(true)
	var redo: Array = editor._redo_history.duplicate(true)
	await _click(editor._undo_button)
	_check("incompatible Undo preserves both history stacks and the draft", editor._undo_history == undo and editor._redo_history == redo
		and panel._zone_brightness.value == 0.18 and _zone(editor.get_presentation().lighting).brightness == 0.42)
	await _click(panel._zone_cancel)
	await _click(editor._undo_button)
	_check("Cancel then Undo resolves the guarded transition", _zone(editor.get_presentation().lighting).brightness == 1.0)
	panel._zone_brightness.value = 0.3
	undo = editor._undo_history.duplicate(true)
	redo = editor._redo_history.duplicate(true)
	await _click(editor._redo_button)
	_check("incompatible Redo also preserves both stacks", editor._undo_history == undo and editor._redo_history == redo and panel._zone_brightness.value == 0.3)
	await _click(panel._zone_cancel)
	await _click(editor._redo_button)
	editor.set_recipe({power_multiplier = 1.2})
	await _edit(panel._zone_hex_fields[0], "#BAD")
	await _click(editor._undo_button)
	_check("unrelated history preserves invalid color and Cancel availability", panel._zone_hex_fields[0].text == "#BAD"
		and panel._zone_text_invalid and panel._zone_apply.disabled and not panel._zone_cancel.disabled and _blocked(editor, panel))
	await _click(panel._zone_cancel)
	_check("visible Cancel resolves an invalid first color", not panel.has_pending_edit() and editor._edit_valid())
	editor.set_recipe({power_multiplier = 1.25})
	var unchanged_color: String = panel._zone_hex_fields[0].text
	await _edit(panel._zone_hex_fields[0], unchanged_color)
	await _click(editor._undo_button)
	_check("text-dirty intent survives even when the color equals accepted data", panel._zone_text_pending
		and panel._zone_hex_fields[0].text == unchanged_color and _blocked(editor, panel))
	await _click(panel._zone_cancel)
	await _click(panel._more_effects_button)
	editor.set_recipe({power_multiplier = 1.3})
	var effect: Dictionary = panel._effects_controls_by_anchor.vfx_tip_left
	effect.enabled.button_pressed = true
	await _choose(effect.kind, "trail")
	effect.intensity.value = 0.4
	effect.lifetime.value = 1.2
	var effects: Array = panel._effects_draft.duplicate(true)
	accepted = editor.get_presentation()
	await _click(editor._undo_button)
	await _click(editor._redo_button)
	_check("effects and their controls survive Undo/Redo without publishing", _same_data(panel._effects_draft, effects)
		and panel._effects_controls_by_anchor.vfx_tip_left.intensity.value == 0.4 and editor.get_presentation() == accepted and _blocked(editor, panel))
	await _click(panel._effects_apply)
	_check("explicit Apply publishes the complete effect proposal", editor.get_presentation().lighting.effects == effects and not panel.has_pending_edit())
	editor.set_recipe({power_multiplier = 1.4})
	panel._brightness.value = 0.63
	editor._undo()
	_check("pending overall brightness survives synchronous history refresh", panel._brightness_pending and panel._brightness.value == 0.63)
	await create_timer(0.4).timeout
	_check("restored brightness resumes its bounded commit timer", not panel.has_pending_edit() and editor.get_presentation().lighting.brightness == 0.63)
	panel._brightness.value = 0.27
	panel.cancel_pending_edit()
	await create_timer(0.4).timeout
	_check("cancelled brightness timer cannot publish later", editor.get_presentation().lighting.brightness == 0.63)
	panel._brightness.value = 0.0
	var zero_state: Dictionary = panel.get_editor_state()
	panel.configure(editor._presentation_bindings, editor.get_presentation())
	_check("pending zero brightness restores as a value, not an absent edit", panel.restore_editor_state(zero_state)
		and panel._brightness_pending and panel._brightness.value == 0.0)
	await create_timer(0.4).timeout
	_check("restored zero brightness commits once its debounce expires", not panel.has_pending_edit()
		and editor.get_presentation().lighting.brightness == 0.0)
	editor.free()
	await ui.settle()


func _recovery() -> void:
	var first := await _editor("recovery", true)
	var panel := await _lighting(first)
	first.set_recipe({power_multiplier = 1.1})
	panel._zone_brightness.value = 0.42
	panel._period.value = 3.75 # Steady normalizes on Apply, but this is still a raw proposal.
	for _index: int in 7: panel._add_palette_color()
	await _edit(panel._zone_hex_fields[7], "#BAD")
	var proposed: Dictionary = panel._zone_draft.duplicate(true)
	var accepted: Dictionary = first.get_presentation()
	await create_timer(0.9).timeout
	var saved: Dictionary = DraftStore.load_snapshot(first.recovery_root)
	_check("completed debounce snapshot decodes the maximum palette depth", saved.ok and saved.compatible, str(saved.get("errors", [])))
	var state: Dictionary = saved.get("editor", {}).get("presentation_buffers", {}).get("lighting", {})
	_check("snapshot separates accepted profile from the complete pending zone", state.has("draft")
		and _same_data(state.get("draft", {}).get("zone", {}), proposed) and saved.get("payload", {}).get("presentation_profile", {}) == accepted)
	first.free()
	await ui.settle()
	var second := await _editor("recovery", true)
	await _window_button(second._recovery_dialog, "Restore as a new build")
	panel = second._page_nodes.lighting
	_check("recovery restores raw values without canonicalizing steady period", _same_data(panel._zone_draft, proposed)
		and panel._period.value == 3.75 and panel._zone_hex_fields.size() == 8, str(panel._zone_draft))
	_check("recovery preserves invalid text, accepted profile and blocked actions", panel._zone_hex_fields.back().text == "#BAD"
		and panel._zone_text_invalid and second.get_presentation() == accepted and _blocked(second, panel))
	var intact: Dictionary = panel.get_editor_state()
	var invalid: Dictionary = intact.duplicate(true)
	invalid["unsupported"] = true
	_check("unknown state is refused atomically", not panel.restore_editor_state(invalid) and panel.get_editor_state() == intact)
	if intact.has("draft"):
		invalid = intact.duplicate(true)
		invalid.draft.zone.brightness = INF
		_check("nonfinite draft is refused atomically", not panel.restore_editor_state(invalid) and panel.get_editor_state() == intact)
		invalid = intact.duplicate(true)
		invalid.draft.zone.pattern.reverse = not invalid.draft.zone.pattern.reverse
		_check("hidden pattern fields cannot change through recovery", not panel.restore_editor_state(invalid) and panel.get_editor_state() == intact)
		invalid = intact.duplicate(true)
		invalid.draft.zone.pattern = "malformed"
		_check("malformed nested data is refused without runtime errors", not panel.restore_editor_state(invalid) and panel.get_editor_state() == intact)
		var malformed_editor: Dictionary = saved.editor.duplicate(true)
		malformed_editor.presentation_buffers.lighting = invalid
		var refused: Dictionary = DraftStore.save_snapshot(second.recovery_root, saved.payload, malformed_editor)
		_check("malformed recovery cannot replace the completed snapshot", not refused.ok
			and DraftStore.load_snapshot(second.recovery_root).digest == saved.digest)
	await _click(panel._zone_cancel)
	_check("Cancel resolves recovered raw state", not panel.has_pending_edit() and second._edit_valid())
	var legacy: Dictionary = panel.get_editor_state()
	legacy.erase("draft")
	_check("legacy five-key state still restores", panel.restore_editor_state(legacy))
	legacy.erase("sequence")
	_check("legacy four-key state still restores", panel.restore_editor_state(legacy))
	await _click(panel._more_effects_button)
	panel._effects_controls_by_anchor.vfx_tip_right.enabled.button_pressed = true
	panel._effects_controls_by_anchor.vfx_tip_right.intensity.value = 0.25
	var effects: Array = panel._effects_draft.duplicate(true)
	_check("pending effects can be snapshotted", second._autosave_draft())
	second.free()
	await ui.settle()
	var third := await _editor("recovery", true)
	await _window_button(third._recovery_dialog, "Restore as a new build")
	panel = third._page_nodes.lighting
	_check("JSON effects recover into typed controls and remain pending", _same_data(panel._effects_draft, effects)
		and panel._effects_controls_by_anchor.vfx_tip_right.intensity.value == 0.25 and _blocked(third, panel))
	await _click(panel._effects_apply)
	_check("restored effects can be explicitly applied", third.get_presentation().lighting.effects == effects and third._edit_valid())
	third.free()
	await ui.settle()


func _replacement() -> void:
	var editor := await _editor("replacement", true)
	var panel := await _lighting(editor)
	var smoke: Control = editor._page_nodes.smoke
	smoke.apply_preset(5)
	editor.set_variant_name("Pending replacement fixture")
	editor.save_named_variant()
	var saved_id: String = editor._saved_variant_id
	var accepted: Dictionary = editor.get_presentation()
	_check("named build fixture saves", not saved_id.is_empty())
	editor.set_recipe({power_multiplier = 1.1})
	editor._set_page("smoke")
	await _edit(smoke._custom_color, "#BAD")
	_check("outgoing draft recovery completes", editor._autosave_draft())
	var before: Dictionary = DraftStore.load_snapshot(editor.recovery_root)
	editor._selected_variant_id = saved_id
	editor._load_selected_variant()
	await _window_button(editor._guard_dialog, "Cancel")
	_check("cancelled load retains the outgoing field and recovery", smoke._custom_color.text == "#BAD"
		and DraftStore.load_snapshot(editor.recovery_root).digest == before.digest)
	editor._selected_variant_id = "missing-build"
	editor._load_selected_variant()
	await _window_button(editor._guard_dialog, "Discard changes")
	_check("failed load retains the outgoing field and recovery", smoke._custom_color.text == "#BAD"
		and editor.get_recipe().power_multiplier == 1.1 and DraftStore.load_snapshot(editor.recovery_root).digest == before.digest)
	editor._selected_variant_id = saved_id
	editor._load_selected_variant()
	await _window_button(editor._guard_dialog, "Discard changes")
	_check("successful replacement clears outgoing presentation drafts", not smoke.has_pending_color() and not smoke.has_pending_marking() and not panel.has_pending_edit()
		and editor.get_presentation() == accepted and editor.get_recipe().power_multiplier == 1.0)
	_check("loaded build is clean with coherent actions and no stale recovery", not editor.has_unsaved_changes()
		and editor._edit_valid() and not editor.save_button.disabled and not editor._trial_button.disabled
		and not DraftStore.load_snapshot(editor.recovery_root).exists)
	editor.free()
	await ui.settle()
