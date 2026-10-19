# Capture the real Workshop recovery window at the requested viewport and exercise
# Later, Restore, and Discard against a disposable user:// root.
# PowerShell example from the repository root (the helper is outside app/):
#   $scriptPath = (Resolve-Path research/aircraft-editor/capture_recovery.gd).Path
#   $evidencePath = (Resolve-Path docs/research/aircraft-editor/AE-03c/evidence).Path
#   & .tools/Godot_v4.7.2-stable_win64_console.exe --path app --script $scriptPath -- `
#     --lang=en --size=1920x1080 "--out=$evidencePath\recovery-en-1920x1080.png" `
#     "--evidence=$evidencePath\recovery-en-1920x1080.json"
extends SceneTree

const Workshop := preload("res://ui/workshop.gd")
const DraftStore := preload("res://workshop/draft_store.gd")
const Store := preload("res://workshop/store.gd")

const AIRCRAFT_ID: String = "jensen-das-ugly-stik-60"

var _failures := PackedStringArray()


func _initialize() -> void:
	await _run()


func _run() -> void:
	var language := "en"
	var requested_size := Vector2i.ZERO
	var output_path := ""
	var evidence_path := ""
	var scratch := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lang="):
			language = argument.trim_prefix("--lang=")
		elif argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				requested_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--evidence="):
			evidence_path = argument.trim_prefix("--evidence=")
		elif argument.begins_with("--scratch="):
			scratch = argument.trim_prefix("--scratch=")
	if language not in ["en", "es"] or requested_size.x < 640 or requested_size.y < 480 \
			or output_path.is_empty() or evidence_path.is_empty():
		push_error("Capture needs --lang=en|es, --size=WIDTHxHEIGHT, --out, and --evidence.")
		quit(ERR_INVALID_PARAMETER)
		return
	if scratch.is_empty():
		scratch = "user://ae03c_recovery_capture_%s_%d" % [language, Time.get_ticks_usec()]
	if not scratch.begins_with("user://ae03c_recovery_capture_"):
		push_error("Capture scratch must use its isolated user://ae03c_recovery_capture_ prefix.")
		quit(ERR_INVALID_PARAMETER)
		return
	var scratch_absolute := ProjectSettings.globalize_path(scratch).simplify_path()
	var user_root_absolute := ProjectSettings.globalize_path("user://").simplify_path()
	if scratch_absolute.get_base_dir() != user_root_absolute \
			or not scratch_absolute.get_file().begins_with("ae03c_recovery_capture_"):
		push_error("Capture scratch must be one direct child of user://; nested or traversing paths are rejected.")
		quit(ERR_INVALID_PARAMETER)
	var main_window: Window = root
	main_window.gui_embed_subwindows = true
	main_window.size = requested_size
	DisplayServer.window_set_size(requested_size)
	TranslationServer.set_locale(language)
	await _settle(3)

	var first := _make_editor(scratch)
	await _settle(8)
	first.set_recipe({"control_multiplier": 1.03})
	first.set_variant_name("Recover Ñ-27")
	var smoke_page: Node = first.get("_page_nodes").get("smoke")
	smoke_page.call("apply_preset", 5)
	first.call("_set_page", "smoke")
	var color_input: LineEdit = smoke_page.get("_custom_color")
	color_input.text = "#BAD"
	color_input.text_changed.emit(color_input.text)
	var power_input: LineEdit = first.get("_factor_inputs").get("power_multiplier")
	power_input.text = "invalid"
	power_input.text_changed.emit(power_input.text)
	first.get("_preview").set_standard_view("side")
	var expected_recipe: Dictionary = first.get_recipe()
	var expected_profile: Dictionary = first.get_presentation()
	var expected_camera: Dictionary = first.get("_preview").get_view_state()
	var wrote_snapshot: bool = bool(first.call("_autosave_draft"))
	var seeded: Dictionary = DraftStore.load_snapshot(first.recovery_root)
	_check("isolated recovery seed saved", wrote_snapshot and seeded.ok and seeded.compatible)
	_check("seed preserves invalid numeric and color buffers", seeded.ok
		and seeded.editor.numeric_buffers.get("power_multiplier", "") == "invalid"
		and seeded.editor.presentation_buffers.smoke.color_text == "#BAD")
	first.free()
	await _settle(3)

	var editor := _make_editor(scratch)
	await _settle(10)
	var dialog: ConfirmationDialog = editor.get("_recovery_dialog")
	_check("real recovery dialog opened on launch", editor.get("_recovery_pending") and is_instance_valid(dialog) and dialog.visible)
	if not is_instance_valid(dialog) or not dialog.visible:
		_save_evidence(evidence_path, _base_evidence(language, requested_size, scratch, output_path))
		editor.free()
		await _settle(2)
		_remove_tree(ProjectSettings.globalize_path(scratch))
		quit(1)
		return
	var later: Button = dialog.get_cancel_button()
	var restore: Button = dialog.get_ok_button()
	var discard: Button = _find_button(dialog, tr("Discard recovered draft"))
	_check("Later is the initially focused recovery action", dialog.gui_get_focus_owner() == later)
	_check("Restore is enabled only for this compatible fixture", not restore.disabled)
	_check("the prompt visibly retains invalid recovery text", editor.get("_recovery_text").text.contains("invalid")
		and editor.get("_recovery_text").text.contains("#BAD"))
	var dialog_metrics: Dictionary = _measure_dialog(main_window, dialog, [restore, later, discard], requested_size)
	_check("dialog and every action button fit the requested viewport", bool(dialog_metrics.get("fits", false)))
	_check("Restore, Later, and Discard are visible and enabled", bool(dialog_metrics.get("actions_reachable", false)))
	var localized: Dictionary = _localization_metrics(language, dialog, restore, later, discard)
	_check("recovery prompt actions are localized for the requested language", bool(localized.get("complete", false)))
	var summary_metrics: Dictionary = await _scroll_recovery_summary(editor, language)
	_check("scrollable summary exposes both preserved invalid buffers", bool(summary_metrics.get("invalid_values_visible", false)))
	await RenderingServer.frame_post_draw
	var screenshot: Image = main_window.get_texture().get_image()
	if screenshot.get_width() != requested_size.x or screenshot.get_height() != requested_size.y:
		_failures.append("Captured viewport dimensions did not match the requested size.")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image_error: Error = screenshot.save_png(output_path)
	_check("actual recovery window screenshot saved", image_error == OK)

	# Exercise the same UI signals a mouse activation emits and verify each choice.
	later.pressed.emit()
	await _settle(3)
	var later_result: Dictionary = DraftStore.load_snapshot(editor.recovery_root)
	var later_worked: bool = not dialog.visible and later_result.ok and later_result.exists \
		and editor.get("_recovery_pending") and not editor.get("_trial_button").disabled
	_check("Later keeps the snapshot and returns to normal editing", later_worked)
	editor.call("_show_recovery")
	await _settle(3)
	_check("reopening the prompt restores Later focus", dialog.visible and dialog.gui_get_focus_owner() == later)
	restore.pressed.emit()
	await _settle(4)
	var restored: bool = editor.get_recipe() == expected_recipe and editor.get_presentation() == expected_profile \
		and editor.get("_active_page") == "smoke" and editor.get("_preview").get_view_state() == expected_camera \
		and editor.get("_factor_inputs").get("power_multiplier").text == "invalid" \
		and editor.get("_page_nodes").smoke.get("_custom_color").text == "#BAD" \
		and not editor.call("_edit_valid") and editor.get("_saved_variant_id").is_empty()
	_check("Restore returns the complete accepted build as a new unsaved build", restored)
	_check("Restore does not publish a named variant", Store.list_variants(editor.variants_root).is_empty())
	editor.free()
	await _settle(3)

	var final_editor := _make_editor(scratch)
	await _settle(10)
	var final_dialog: ConfirmationDialog = final_editor.get("_recovery_dialog")
	var final_discard: Button = _find_button(final_dialog, tr("Discard recovered draft")) if is_instance_valid(final_dialog) else null
	var discard_pressed: bool = is_instance_valid(final_dialog) and final_dialog.visible and is_instance_valid(final_discard)
	if discard_pressed:
		final_discard.pressed.emit()
		await _settle(3)
	var after_discard: Dictionary = DraftStore.load_snapshot(final_editor.recovery_root)
	var discard_worked: bool = discard_pressed and after_discard.ok and not after_discard.exists \
		and not final_editor.get("_recovery_pending") and Store.list_variants(final_editor.variants_root).is_empty()
	_check("Discard removes only the recovery record and leaves the library empty", discard_worked)

	var evidence := _base_evidence(language, requested_size, scratch, output_path)
	evidence.merge({
		"format": "openrc-ae03c-recovery-capture v1",
		"image_size": [screenshot.get_width(), screenshot.get_height()],
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"dialog": dialog_metrics,
		"summary": summary_metrics,
		"actions": {"later_kept_snapshot": later_worked, "restore_preserved_data": restored,
			"discard_removed_snapshot": discard_worked},
		"localization": localized,
		"seed": {"compatible": seeded.get("compatible", false), "raw_color": "#BAD", "raw_numeric": "invalid"},
		"failures": _failures.duplicate(),
		"power_loss_durability_claim": false,
		"performance_claim": false,
	}, true)
	_save_evidence(evidence_path, evidence)
	final_editor.free()
	await _settle(3)
	_remove_tree(ProjectSettings.globalize_path(scratch))
	print("AE-03c %s %s: %d failures; screenshot %s" % [language, str(requested_size), _failures.size(), output_path])
	quit(1 if not _failures.is_empty() else 0)


func _make_editor(scratch: String) -> Node:
	var editor: Node = Workshop.new()
	editor.initial_aircraft_id = AIRCRAFT_ID
	editor.variants_root = scratch.path_join("library")
	editor.recovery_root = scratch.path_join("recovery")
	editor.recovery_enabled = true
	root.add_child(editor)
	return editor


func _measure_dialog(main_window: Window, dialog: ConfirmationDialog, buttons: Array, requested_size: Vector2i) -> Dictionary:
	var main_rect := Rect2(Vector2.ZERO, Vector2(requested_size))
	var dialog_rect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
	var dialog_fits: bool = dialog_rect.position.x >= 0.0 and dialog_rect.position.y >= 0.0 \
		and dialog_rect.end.x <= main_rect.end.x and dialog_rect.end.y <= main_rect.end.y
	var viewport_size: Vector2 = dialog.get_visible_rect().size
	var action_records: Array[Dictionary] = []
	var actions_reachable := buttons.size() == 3
	for item: Variant in buttons:
		if not item is Button:
			actions_reachable = false
			continue
		var button: Button = item
		var rect: Rect2 = button.get_global_rect()
		var fits_button: bool = button.is_visible_in_tree() and not button.disabled \
			and rect.size.x > 0.0 and rect.size.y > 0.0 and rect.position.x >= 0.0 and rect.position.y >= 0.0 \
			and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y
		actions_reachable = actions_reachable and fits_button
		action_records.append({"text": button.text, "rect": _rect_array(rect), "visible": button.is_visible_in_tree(),
			"enabled": not button.disabled, "inside_dialog_viewport": fits_button,
			"focus_mode": button.focus_mode})
	return {"main_rect": _rect_array(main_rect), "dialog_rect": _rect_array(dialog_rect),
		"dialog_viewport_size": [viewport_size.x, viewport_size.y], "dialog_inside_main": dialog_fits,
		"action_buttons": action_records, "fits": dialog_fits and actions_reachable,
		"actions_reachable": actions_reachable, "embedded_subwindows": main_window.gui_embed_subwindows}


func _localization_metrics(language: String, dialog: ConfirmationDialog, restore: Button,
		later: Button, discard: Button) -> Dictionary:
	var source_values := {
		"title": "Recovered draft", "restore": "Restore as a new build", "later": "Later",
		"discard": "Discard recovered draft",
	}
	var expected := source_values.duplicate()
	if language == "es":
		expected = {
			"title": "Borrador recuperado", "restore": "Restaurar como configuración nueva",
			"later": "Más tarde", "discard": "Descartar borrador recuperado",
		}
	var actual := {"title": dialog.title, "restore": restore.text, "later": later.text,
		"discard": discard.text if is_instance_valid(discard) else ""}
	return {"locale": TranslationServer.get_locale(), "complete": actual == expected,
		"source": source_values, "expected": expected, "actual": actual}


func _scroll_recovery_summary(editor: Node, language: String) -> Dictionary:
	var summary: Label = editor.get("_recovery_text")
	var scroll := summary.get_parent() as ScrollContainer if is_instance_valid(summary) else null
	if not is_instance_valid(scroll):
		return {"found": false, "invalid_values_visible": false}
	await _settle(2)
	var bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(bar.max_value)
	await _settle(2)
	var viewport_rect: Rect2 = scroll.get_global_rect()
	var text_rect: Rect2 = summary.get_global_rect()
	var visible_rect: Rect2 = viewport_rect.intersection(text_rect)
	var maximum_scroll := maxi(0, int(bar.max_value - bar.page))
	var scroll_to_end := scroll.scroll_vertical >= maximum_scroll
	var numeric_label := "Power" if language == "en" else "Potencia"
	var smoke_label := "Smoke" if language == "en" else "Humo"
	var text_contains_values := summary.text.contains("%s: invalid" % numeric_label) \
		and summary.text.contains("%s: #BAD" % smoke_label)
	# The current source line list places the raw values at the end. Scrolling the actual
	# UI control to its bottom makes both available for the 1080p and 720p captures.
	var visible_fraction := visible_rect.size.y / maxf(1.0, text_rect.size.y)
	return {"found": true, "vertical": scroll.scroll_vertical, "maximum": maximum_scroll,
		"scroll_to_end": scroll_to_end, "text_contains_values": text_contains_values,
		"visible_fraction": visible_fraction,
		"invalid_values_visible": scroll_to_end and text_contains_values and visible_rect.size.y > 0.0}


func _find_button(parent: Node, expected_text: String) -> Button:
	if not is_instance_valid(parent):
		return null
	for candidate: Node in parent.find_children("*", "Button", true, false):
		var button := candidate as Button
		if button != null and button.text == expected_text:
			return button
	return null


func _base_evidence(language: String, size: Vector2i, scratch: String, output_path: String) -> Dictionary:
	return {"language": language, "requested_size": [size.x, size.y], "scratch_root": scratch,
		"image": output_path.get_file(), "engine_version": Engine.get_version_info().string,
		"isolated_from_player_library": true, "stored_library_variants_before_discard": 0}


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _save_evidence(path: String, evidence: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create capture evidence JSON: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(evidence, "\t", true, true) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		_failures.append("Could not flush capture evidence JSON: %s" % error_string(error))


func _check(label: String, passed: bool) -> void:
	if not passed:
		_failures.append(label)
		push_error(label)


func _settle(count: int) -> void:
	for _frame: int in count:
		await process_frame


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories():
		_remove_tree(path.path_join(child))
	directory = null
	DirAccess.remove_absolute(path)
