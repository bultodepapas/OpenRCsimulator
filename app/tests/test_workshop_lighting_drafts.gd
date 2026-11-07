extends SceneTree
## AE-09d-R3 / A17: pending values, accepted data and available actions are separate.

const Workshop := preload("res://ui/workshop.gd")
const DraftStore := preload("res://workshop/draft_store.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
class SourceFixture extends Workshop:
	var fixture_path := ""
	func _catalog_source_bytes(path: String) -> PackedByteArray:
		if not fixture_path.is_empty() and path.ends_with("stik_glow_61fx_2t.json"):
			return FileAccess.get_file_as_bytes(fixture_path) if FileAccess.file_exists(fixture_path) else PackedByteArray()
		return super._catalog_source_bytes(path)

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
	await _raw_witness()
	await _numeric_cases()
	await _invalid_recovery_cases()
	await _nav_cases()
	await _catalog_cases()
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


func _raw_witness() -> void:
	var first := await _editor("raw-witness", true)
	var panel := await _lighting(first)
	panel._zone_brightness.value = 0.42
	var accepted: Dictionary = first.get_presentation()
	await _edit(panel._period.get_line_edit(), "3.75")
	_check("raw witness value remains unsubmitted", panel._period.value == 1.0)
	await create_timer(0.9).timeout
	var saved: Dictionary = DraftStore.load_snapshot(first.recovery_root)
	_check("raw witness recovery completed", saved.ok and saved.compatible)
	first.free()
	await ui.settle()
	var second := await _editor("raw-witness", true)
	await _window_button(second._recovery_dialog, "Restore as a new build")
	panel = second._page_nodes.lighting
	_check("raw witness text survives recovery", panel._period.get_line_edit().text == "3.75", panel._period.get_line_edit().text)
	_check("raw witness brightness and accepted profile survive", panel._zone_brightness.value == 0.42 and second.get_presentation() == accepted)
	second.free()
	await ui.settle()



func _numeric_cases() -> void:
	var first := await _editor("numeric-extra", true)
	var panel := await _lighting(first)
	await _choose(panel._pattern_selector, "pulse")
	await _click(panel._zone_apply)
	var accepted: Dictionary = first.get_presentation()
	for raw: String in ["1", "", "bad", "1e999", "pow(10,500)", "61", "3+0.75"]:
		await _edit(panel._period.get_line_edit(), raw)
		_check("numeric intent pending: " + raw, panel.has_pending_edit() and not panel._zone_cancel.disabled and first.get_presentation() == accepted)
		var expected_valid := raw in ["1", "3+0.75"]
		_check("numeric validity: " + raw, panel._zone_apply.disabled != expected_valid)
		if raw == "bad":
			await ui.tap(KEY_ENTER)
			_check("invalid native submission preserves text and refusal", panel._period.get_line_edit().text == raw and panel._zone_apply.disabled and panel.has_pending_edit())
		panel.cancel_pending_edit()
		await ui.settle()
		_check("Cancel resolves numeric intent: " + raw, not panel.has_pending_edit() and first.get_presentation() == accepted)
	await _edit(panel._period.get_line_edit(), "3+0.75")
	panel._period.get_line_edit().caret_column = 2
	panel._period.queue_redraw()
	await ui.settle()
	_check("redraw keeps the numeric caret", panel._period.get_line_edit().caret_column == 2)
	panel._period.get_line_edit().select(1, 4)
	panel._period.queue_redraw()
	await ui.settle()
	_check("redraw keeps the numeric selection", panel._period.get_line_edit().get_selection_from_column() == 1 and panel._period.get_line_edit().get_selection_to_column() == 4)
	_check("numeric recovery save", first._autosave_draft())
	var saved: Dictionary = DraftStore.load_snapshot(first.recovery_root)
	_check("numeric recovery stores expression", saved.ok and saved.editor.presentation_buffers.lighting.numbers.period == "3+0.75")
	first.free()
	await ui.settle()
	var second := await _editor("numeric-extra", true)
	await _window_button(second._recovery_dialog, "Restore as a new build")
	panel = second._page_nodes.lighting
	_check("numeric expression restored", panel._period.get_line_edit().text == "3+0.75")
	await _click(panel._zone_apply)
	_check("direct Apply after Restore commits expression", _zone(second.get_presentation().lighting).pattern.period_ticks == 900 and not panel.has_pending_edit(), str(_zone(second.get_presentation().lighting).pattern))
	accepted = second.get_presentation()
	await _edit(panel._period.get_line_edit(), "4.25")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter)
	panel.cancel_pending_edit()
	await ui.settle()
	_check("same-frame Enter then Cancel survives deferred native submit", not panel.has_pending_edit() and second.get_presentation() == accepted and panel._zone_draft.pattern.period_ticks == 900 and panel._period.value == 3.75, str(panel._zone_draft))
	second.set_recipe({power_multiplier = 1.1})
	await _choose(panel._reactive_selector, "throttle")
	await _edit(panel._reactive_gain.get_line_edit(), "0.35")
	second._undo()
	_check("gain text survives unrelated history", second.get_recipe().power_multiplier == 1.0 and panel._reactive_gain.get_line_edit().text == "0.35" and panel.has_pending_edit())
	panel.cancel_pending_edit()
	await ui.settle()
	await _click(panel._more_effects_button)
	var effect: Dictionary = panel._effects_controls_by_anchor.vfx_tip_left
	await _edit(effect.intensity.get_line_edit(), "bad")
	_check("invalid effect text disables Apply but allows Cancel", panel._effects_apply.disabled and not panel._effects_cancel.disabled)
	var pending_effect: Dictionary = panel.get_editor_state()
	panel.configure(second._presentation_bindings, second.get_presentation())
	_check("invalid effect state restores", panel.restore_editor_state(pending_effect))
	await ui.settle()
	effect = panel._effects_controls_by_anchor.vfx_tip_left
	_check("restored invalid effect remains visible and blocked", effect.intensity.get_line_edit().text == "bad" and panel._effects_apply.disabled)
	await _edit(effect.intensity.get_line_edit(), "0.4")
	await _edit(effect.lifetime.get_line_edit(), "1.2")
	_check("effect numeric fields remain pending", panel._number_texts.size() == 2 and panel.has_pending_edit())
	effect.intensity.get_line_edit().grab_focus()
	await ui.settle()
	await _click(second._page_buttons.setup)
	_check("refused navigation returns to the most recently focused numeric field", root.gui_get_focus_owner() == effect.intensity.get_line_edit() and second._active_page == "lighting")
	_check("effect numeric recovery", second._autosave_draft())
	second.free()
	await ui.settle()
	var third := await _editor("numeric-extra", true)
	await _window_button(third._recovery_dialog, "Restore as a new build")
	panel = third._page_nodes.lighting
	effect = panel._effects_controls_by_anchor.vfx_tip_left
	_check("effect numeric text restored", effect.intensity.get_line_edit().text == "0.4" and effect.lifetime.get_line_edit().text == "1.2")
	await _click(panel._effects_apply)
	_check("effect direct Apply publishes restored values", third.get_presentation().lighting.effects[0].intensity == 0.4 and third.get_presentation().lighting.effects[0].lifetime_ticks == 288 and not panel.has_pending_edit(), str(third.get_presentation().lighting.effects))
	third.free()
	await ui.settle()


func _select_page(picker: OptionButton, index: int) -> void:
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


func _selection_matches_lighting(editor: CanvasLayer) -> bool:
	if editor._active_page != "lighting" or editor._page_selector.selected != editor.PAGE_IDS.find("lighting"): return false
	for id: String in editor.PAGE_IDS:
		if editor._page_buttons[id].button_pressed != (id == "lighting"): return false
	return true


func _nav_cases() -> void:
	var editor := await _editor("navigation-extra")
	var panel := await _lighting(editor)
	await _edit(panel._zone_hex_fields[0], "#BAD")
	editor._body_scroll.ensure_control_visible(panel._zone_hex_fields[0])
	await ui.settle()
	var scroll: int = editor._body_scroll.scroll_vertical
	for id: String in editor.PAGE_IDS:
		if id == "lighting": continue
		await _click(editor._page_buttons[id])
		_check("refused desktop destination " + id, _selection_matches_lighting(editor) and root.gui_get_focus_owner() == panel._zone_hex_fields[0] and editor._body_scroll.scroll_vertical == scroll)
	root.size = Vector2i(1000, 1080)
	editor._resize_layout()
	for index: int in editor.PAGE_IDS.size():
		if editor.PAGE_IDS[index] == "lighting": continue
		await _select_page(editor._page_selector, index)
		_check("refused compact destination " + editor.PAGE_IDS[index], _selection_matches_lighting(editor) and root.gui_get_focus_owner() == panel._zone_hex_fields[0])
	await _click(panel._zone_cancel)
	await _select_page(editor._page_selector, editor.PAGE_IDS.find("setup"))
	_check("one selection opens the destination after Cancel", editor._active_page == "setup" and editor._page_selector.selected == editor.PAGE_IDS.find("setup"))
	root.size = Vector2i(1920, 1080)
	editor._resize_layout()
	editor._set_page("lighting")
	await _edit(panel._period.get_line_edit(), "3.75")
	editor._body_scroll.ensure_control_visible(panel._period.get_line_edit())
	await ui.settle()
	scroll = editor._body_scroll.scroll_vertical
	await _click(editor._page_buttons.setup)
	_check("refused desktop navigation focuses valid raw numeric text", _selection_matches_lighting(editor) and root.gui_get_focus_owner() == panel._period.get_line_edit() and editor._body_scroll.scroll_vertical == scroll)
	root.size = Vector2i(1000, 1080)
	editor._resize_layout()
	await _select_page(editor._page_selector, editor.PAGE_IDS.find("setup"))
	_check("refused compact navigation focuses valid raw numeric text", _selection_matches_lighting(editor) and root.gui_get_focus_owner() == panel._period.get_line_edit())
	await _edit(panel._zone_hex_fields[0], "#BAD")
	await _select_page(editor._page_selector, editor.PAGE_IDS.find("setup"))
	_check("invalid color takes focus over a valid numeric proposal", _selection_matches_lighting(editor) and root.gui_get_focus_owner() == panel._zone_hex_fields[0])
	panel.cancel_pending_edit()
	editor.free()
	root.size = Vector2i(1920, 1080)
	await ui.settle()


func _invalid_recovery_cases() -> void:
	for raw: String in ["bad", "", "1", "1e999"]:
		var name := "number-recovery-" + str(raw.length()) + "-" + str(raw.hash())
		var first := await _editor(name, true)
		var panel := await _lighting(first)
		await _edit(panel._period.get_line_edit(), raw)
		_check("raw numeric recovery writes: " + raw, first._autosave_draft())
		var saved: Dictionary = DraftStore.load_snapshot(first.recovery_root)
		var state: Dictionary = panel.get_editor_state()
		var malformed := state.duplicate(true)
		malformed.numbers.period = "1".repeat(65)
		_check("oversize numeric state is refused atomically", not panel.restore_editor_state(malformed) and panel.get_editor_state() == state)
		malformed = state.duplicate(true)
		malformed.numbers["unexpected"] = "1"
		_check("unknown numeric key is refused atomically", not panel.restore_editor_state(malformed) and panel.get_editor_state() == state)
		var bad_editor: Dictionary = saved.editor.duplicate(true)
		bad_editor.presentation_buffers.lighting = malformed
		var refused: Dictionary = DraftStore.save_snapshot(first.recovery_root, saved.payload, bad_editor)
		_check("malformed numeric recovery preserves completed digest", not refused.ok and DraftStore.load_snapshot(first.recovery_root).digest == saved.digest)
		first.free()
		await ui.settle()
		var restored := await _editor(name, true)
		await _window_button(restored._recovery_dialog, "Restore as a new build")
		panel = restored._page_nodes.lighting
		_check("raw numeric text and intent survive recovery: " + raw, panel._period.get_line_edit().text == raw and _blocked(restored, panel) and not panel._zone_cancel.disabled)
		_check("invalid restored number blocks Apply: " + raw, panel._zone_apply.disabled == (raw != "1"))
		panel.cancel_pending_edit()
		restored.free()
		await ui.settle()


func _catalog_cases() -> void:
	var editor := SourceFixture.new()
	editor.variants_root = _root + "/catalog-extra/library"
	editor.recovery_root = _root + "/catalog-extra/recovery"
	editor.recovery_enabled = true
	root.add_child(editor)
	await ui.settle()
	var panel := await _lighting(editor)
	editor.set_variant_name("Catalog fixture")
	editor.save_named_variant()
	editor.set_recipe({power_multiplier = 1.1})
	var numeric: LineEdit = editor._factor_inputs.control_multiplier
	numeric.text = "invalid"
	numeric.text_changed.emit(numeric.text)
	await _edit(panel._zone_hex_fields[0], "#BAD")
	_check("catalog fixture saves recovery", editor._autosave_draft())
	var before: Dictionary = editor._draft_payload()
	var buffer: Dictionary = panel.get_editor_state()
	var digest: String = DraftStore.load_snapshot(editor.recovery_root).digest
	var numbers: Dictionary = editor._pending_numbers.duplicate(true)
	var errors: Dictionary = editor._invalid_fields.duplicate(true)
	var history: Array = editor._undo_history.duplicate(true)
	var saved_id: String = editor._saved_variant_id
	var revision: int = editor._saved_variant_revision
	var directory := _root + "/catalog-extra/fixture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for content: String in ["missing", "{broken", "{}"]:
		editor.fixture_path = directory + "/" + str(content.length()) + ".json"
		if content != "missing":
			var file := FileAccess.open(editor.fixture_path, FileAccess.WRITE)
			file.store_string(content)
			file.close()
		editor.set_aircraft("stik-glow-61fx-2t")
		await _window_button(editor._guard_dialog, "Discard changes")
		_check("refused catalog source retains payload: " + content, editor._draft_payload() == before)
		_check("refused catalog source retains pending text and actions: " + content, panel.get_editor_state() == buffer and _blocked(editor, panel))
		_check("refused catalog source retains numeric text, identity and history: " + content, editor._pending_numbers == numbers and editor._invalid_fields == errors and editor._undo_history == history and editor._saved_variant_id == saved_id and editor._saved_variant_revision == revision)
		_check("refused catalog source retains recovery: " + content, DraftStore.load_snapshot(editor.recovery_root).digest == digest and editor._recovery_digest == digest)
	var valid_file := FileAccess.open(directory + "/valid.json", FileAccess.WRITE)
	valid_file.store_buffer(FileAccess.get_file_as_bytes("res://data/aircraft/stik_glow_61fx_2t.json"))
	valid_file.close()
	editor.fixture_path = directory + "/valid.json"
	editor.set_aircraft("stik-glow-61fx-2t")
	await _window_button(editor._guard_dialog, "Discard changes")
	_check("admitted catalog source clears the outgoing draft", editor._base_id == "stik-glow-61fx-2t" and not panel.has_pending_edit() and editor._pending_numbers.is_empty() and editor._invalid_fields.is_empty() and not editor.has_unsaved_changes())
	_check("admitted catalog replacement clears recovery", not DraftStore.load_snapshot(editor.recovery_root).exists)
	editor.free()
	await ui.settle()
