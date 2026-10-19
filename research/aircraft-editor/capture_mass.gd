extends SceneTree
## Native-rendered Workshop evidence for measured component mass editing.
## All mutable stores are isolated below the requested ae12_13_mass_capture_ user:// root.

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Workshop := preload("res://ui/workshop.gd")
const MassEdit := preload("res://workshop/mass_edit.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Store := preload("res://workshop/store.gd")
const Trial := preload("res://workshop/trial.gd")

const SCRATCH_PREFIX := "ae12_13_mass_capture_"
const FIXTURE_DELTA_KG := 0.0001
const FIXTURE_SOURCE := "Calibrated scale; tiny-delta capture fixture, software evidence only."

var _failures := PackedStringArray()
var _log_lines := PackedStringArray()


func _initialize() -> void:
	await _run()


func _run() -> void:
	var language := "en"
	var requested_size := Vector2i(1920, 1080)
	var text_scale := 1.0
	var output_dir := ""
	var evidence_path := ""
	var scratch := ""
	var user_arguments := OS.get_cmdline_user_args()
	print("Capture user arguments: ", user_arguments)
	for argument: String in user_arguments:
		if argument.begins_with("--lang="):
			language = argument.trim_prefix("--lang=")
		elif argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				requested_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument.begins_with("--text-scale="):
			text_scale = argument.trim_prefix("--text-scale=").to_float()
		elif argument.begins_with("--out-dir="):
			output_dir = argument.trim_prefix("--out-dir=")
		elif argument.begins_with("--evidence="):
			evidence_path = argument.trim_prefix("--evidence=")
		elif argument.begins_with("--scratch="):
			scratch = argument.trim_prefix("--scratch=")
	if language not in ["en", "es"] or requested_size.x < 640 or requested_size.y < 480 \
			or not is_finite(text_scale) or text_scale < 1.0 or text_scale > 2.0 \
			or output_dir.is_empty() or evidence_path.is_empty():
		push_error("Capture needs --lang=en|es, --size=WIDTHxHEIGHT, --text-scale=1..2, --out-dir, and --evidence.")
		quit(ERR_INVALID_PARAMETER)
		return
	if scratch.is_empty():
		scratch = "user://%s%s_%d" % [SCRATCH_PREFIX, language, Time.get_ticks_usec()]
	if not _is_isolated_scratch(scratch):
		push_error("Scratch must be one direct child of user:// with the ae12_13_mass_capture_ prefix.")
		quit(ERR_INVALID_PARAMETER)
	var library_root := scratch.path_join("library")
	var absolute_output := _absolute_path(output_dir)
	var absolute_evidence := _absolute_path(evidence_path)
	if absolute_output.is_empty() or absolute_evidence.is_empty():
		push_error("Output paths must be absolute filesystem paths.")
		quit(ERR_INVALID_PARAMETER)
	DirAccess.make_dir_recursive_absolute(absolute_output)
	DirAccess.make_dir_recursive_absolute(absolute_evidence.get_base_dir())

	var main_window: Window = root
	main_window.gui_embed_subwindows = true
	main_window.size = requested_size
	DisplayServer.window_set_size(requested_size)
	var canvas_policy := UiScale.apply(main_window)
	UiTheme.compact_layout = bool(canvas_policy.get("compact", false))
	UiTheme.text_scale = text_scale
	UiTheme.reduced_motion = true
	TranslationServer.set_locale(language)
	await _settle(3)

	var workshop: CanvasLayer = Workshop.new()
	workshop.initial_aircraft_id = Catalog.DEFAULT_ID
	workshop.variants_root = library_root
	workshop.recovery_enabled = false
	workshop.recovery_root = scratch.path_join("recovery")
	root.add_child(workshop)
	await _settle(12)
	_check("real Workshop loads the selected catalog source", str(workshop.get("_base_id")) == Catalog.DEFAULT_ID
		and not workshop.get("_base").is_empty() and bool(workshop.get("_compiled").get("ok", false)))
	if _failures.size() > 0:
		await _finish(workshop, scratch, absolute_evidence, _base_evidence(language, requested_size, text_scale, scratch, absolute_output))
		quit(1)
		return

	var preview: Control = workshop.get("_preview")
	var preview_focused := UiTheme.text_scale >= 1.5
	if preview_focused:
		workshop.call("_toggle_compact_view")
		await _settle(6)
	preview.set_standard_view("side")
	await _settle(4)
	var model_geometry := _projected_geometry(preview)
	_check("full aircraft model has projected native geometry", int(model_geometry.get("vertex_count", 0)) > 0)
	_check("full model stays inside the preview camera frame", _rect_inside_view(model_geometry))
	await RenderingServer.frame_post_draw
	var main_capture_path := absolute_output.path_join("workshop-%s-%dx%d.png" % [language, requested_size.x, requested_size.y])
	var main_image := main_window.get_texture().get_image()
	var main_save_error := main_image.save_png(main_capture_path)
	_check("real Workshop viewport screenshot saved", main_save_error == OK
		and main_image.get_width() == requested_size.x and main_image.get_height() == requested_size.y)
	if preview_focused:
		workshop.call("_toggle_compact_view")
		await _settle(6)

	var mass_button := workshop.find_child("MeasuredComponents", true, false) as Button
	_check("Workshop exposes the measured-components action", is_instance_valid(mass_button))
	if not is_instance_valid(mass_button):
		await _finish(workshop, scratch, absolute_evidence, _base_evidence(language, requested_size, text_scale, scratch, absolute_output))
		quit(1)
		return
	mass_button.pressed.emit()
	await _settle(6)
	var dialog: ConfirmationDialog = workshop.get("_mass_dialog")
	_check("measured-components action opens the real modal", is_instance_valid(dialog) and dialog.visible)
	if not is_instance_valid(dialog) or not dialog.visible:
		await _finish(workshop, scratch, absolute_evidence, _base_evidence(language, requested_size, text_scale, scratch, absolute_output))
		quit(1)
		return

	var cancel_button := dialog.get_cancel_button()
	var apply_button := dialog.find_child("ApplyMassBuild", true, false) as Button
	var stage_button := dialog.find_child("StageMeasurement", true, false) as Button
	var report_button := dialog.find_child("CheckMassTarget", true, false) as Button
	var solve_button := dialog.find_child("SolveFixedStation", true, false) as Button
	_check("fresh modal focuses safe-default Cancel", dialog.gui_get_focus_owner() == cancel_button)
	var modal_metrics: Dictionary = await _dialog_metrics(main_window, dialog, [cancel_button, apply_button],
		[stage_button, report_button, solve_button], requested_size)
	_check("modal and footer actions fit the native viewport", bool(modal_metrics.get("dialog_inside_main", false))
		and bool(modal_metrics.get("footer_actions_fit", false)))
	_check("all measurement and analysis actions are scroll-reachable", bool(modal_metrics.get("content_actions_reachable", false)))
	var dialog_capture_path := absolute_output.path_join("measured-components-%s-%dx%d-text-%d.png" % [
		language, requested_size.x, requested_size.y, roundi(text_scale * 100.0)])
	await RenderingServer.frame_post_draw
	var dialog_image := main_window.get_texture().get_image()
	var dialog_save_error := dialog_image.save_png(dialog_capture_path)
	_check("measured-components modal screenshot saved at the requested native size",
		dialog_save_error == OK and dialog_image.get_width() == requested_size.x
		and dialog_image.get_height() == requested_size.y)
	var localization := _localization_metrics(language, dialog, cancel_button, apply_button, stage_button)
	_check("measured-components actions are localized", bool(localization.get("ok", false)))

	var baseline_recipe: Dictionary = workshop.get_recipe()
	var cancel_mutations_before: Dictionary = workshop.get_recipe().duplicate(true)
	cancel_button.pressed.emit()
	await _settle(4)
	var cancel_preserved: bool = not dialog.visible and workshop.get_recipe() == cancel_mutations_before
	_check("Cancel closes the modal without changing the recipe", cancel_preserved)
	_check("Cancel returns focus to the Workshop action", main_window.gui_get_focus_owner() == mass_button)

	# Save a named baseline only inside the unique capture root. Apply must fork this record,
	# and cleanup deletes the entire isolated root after all evidence is flushed.
	workshop.set_variant_name("AE-12/13 mass capture baseline")
	workshop.save_named_variant()
	await _settle(4)
	var source_variant_id := str(workshop.get("_saved_variant_id"))
	var source_variant_load: Dictionary = Store.load_variant(source_variant_id, library_root) if not source_variant_id.is_empty() else {"ok": false}
	_check("capture baseline variant is saved only in the isolated library",
		not source_variant_id.is_empty() and bool(source_variant_load.get("ok", false))
		and Store.list_variants(library_root).size() == 1)

	# Reopen through the Workshop action and stage a small measured mass delta on a stable source ID.
	mass_button.pressed.emit()
	await _settle(5)
	dialog = workshop.get("_mass_dialog")
	var picker := dialog.find_child("MassComponent", true, false) as OptionButton
	var mass_input := dialog.find_child("MassKg", true, false).get_node("Value") as LineEdit
	var source_input := dialog.find_child("MeasurementSource", true, false).get_node("Value") as LineEdit
	var inspection: Dictionary = MassEdit.inspect(workshop.get("_base"))
	var eligible: Array[Dictionary] = []
	for row_variant: Variant in inspection.get("inventory", []):
		var row: Dictionary = row_variant
		if bool(row.get("editable", false)):
			eligible.append(row)
	_check("source inventory provides stable editable measurement rows", bool(inspection.get("ok", false)) and eligible.size() >= 2)
	if eligible.size() < 2:
		await _finish(workshop, scratch, absolute_evidence, _base_evidence(language, requested_size, text_scale, scratch, absolute_output))
		quit(1)
		return
	var selected_row: Dictionary = eligible[0]
	var source_before_measurement: Dictionary = workshop.get("_base").duplicate(true)
	var selected_id := str(selected_row.get("id", ""))
	var selected_index := _picker_index(picker, selected_id)
	var alternate_id := str(eligible[1].get("id", ""))
	var alternate_index := _picker_index(picker, alternate_id)
	_check("component picker contains exact source IDs", selected_index >= 0 and alternate_index >= 0 and selected_id != alternate_id)
	if selected_index < 0 or alternate_index < 0:
		await _finish(workshop, scratch, absolute_evidence, _base_evidence(language, requested_size, text_scale, scratch, absolute_output))
		quit(1)
		return
	picker.select(selected_index)
	picker.item_selected.emit(selected_index)
	var measured_mass := float(selected_row.get("mass_kg", 0.0)) + FIXTURE_DELTA_KG
	var mass_text := "%.7f" % measured_mass
	mass_input.text = mass_text
	source_input.text = FIXTURE_SOURCE
	dialog.call("_on_measurement_changed", mass_text)
	picker.select(alternate_index)
	picker.item_selected.emit(alternate_index)
	await _settle(2)
	var dirty_fields_preserved := picker.selected == selected_index and mass_input.text == mass_text \
		and source_input.text == FIXTURE_SOURCE
	_check("attempted component change preserves both dirty measurement fields", dirty_fields_preserved)
	var attempt_notice := str((dialog.find_child("MassDialogError", true, false) as Label).text)
	_check("dirty-field guard explains why selection stayed fixed",
		attempt_notice.contains(tr("Stage or correct the current measurement before changing components.")))
	if not dirty_fields_preserved:
		await _finish(workshop, scratch, absolute_evidence, _base_evidence(language, requested_size, text_scale, scratch, absolute_output))
		quit(1)
		return

	stage_button.pressed.emit()
	await _settle(3)
	var staged: Array = dialog.get("_staged_edits")
	var staged_exact := staged.size() == 1 and str(staged[0].get("id", "")) == selected_id \
		and is_equal_approx(float(staged[0].get("mass_kg", 0.0)), measured_mass) \
		and str(staged[0].get("source", "")) == FIXTURE_SOURCE
	_check("staging records the tiny change as measured with its source", staged_exact)
	_check("source aircraft data remains byte-for-byte equivalent after staging", workshop.get("_base") == source_before_measurement)
	var recipe_with_measurement := baseline_recipe.duplicate(true)
	recipe_with_measurement["mass_edits"] = staged.duplicate(true)
	var expected_compile: Dictionary = Compiler.compile(workshop.get("_base"), recipe_with_measurement)
	_check("small measured candidate passes the full compiler", bool(expected_compile.get("ok", false)))
	if not expected_compile.get("ok", false):
		await _finish(workshop, scratch, absolute_evidence, _base_evidence(language, requested_size, text_scale, scratch, absolute_output))
		quit(1)
		return

	apply_button.pressed.emit()
	await _settle(5)
	var applied_recipe: Dictionary = workshop.get_recipe()
	var candidate_summary: Dictionary = workshop.get("_compiled").get("summary", {})
	var original_after_apply: Dictionary = Store.load_variant(source_variant_id, library_root) if not source_variant_id.is_empty() else {"ok": false}
	var candidate_data: Dictionary = expected_compile.get("data", {}).get("model", {})
	var applied_ok: bool = not dialog.visible and applied_recipe.get("mass_edits", []) == staged \
		and str(workshop.get("_saved_variant_id")).is_empty() \
		and bool(original_after_apply.get("ok", false)) \
		and original_after_apply.get("variant", {}).get("recipe", {}) == baseline_recipe
	_check("Apply to a new build detaches saved ancestry without editing the original", applied_ok)
	_check("applied total mass changes by the measured component delta",
		is_equal_approx(float(candidate_summary.get("mass_kg", NAN)) - float((Compiler.compile(workshop.get("_base"), baseline_recipe)).summary.mass_kg), FIXTURE_DELTA_KG))

	var undo_button := workshop.get("_undo_button") as Button
	var redo_button := workshop.get("_redo_button") as Button
	undo_button.pressed.emit()
	await _settle(3)
	var undo_ok: bool = workshop.get_recipe() == baseline_recipe
	_check("Undo restores the complete unmeasured recipe", undo_ok)
	redo_button.pressed.emit()
	await _settle(3)
	var redo_ok: bool = workshop.get_recipe().get("mass_edits", []) == staged
	_check("Redo restores the measured recipe and its source record", redo_ok)

	var baseline_compile: Dictionary = Compiler.compile(workshop.get("_base"), baseline_recipe)
	var baseline_data: Dictionary = baseline_compile.get("data", {}).get("model", {})
	var comparison := {
		"aircraft_id": str(workshop.get("_base_id")),
		"component_id": selected_id,
		"position_le_m": selected_row.get("position_le_m", []),
		"original_mass_kg": float(selected_row.get("mass_kg", 0.0)),
		"measured_mass_kg": measured_mass,
		"mass_delta_kg": measured_mass - float(selected_row.get("mass_kg", 0.0)),
		"source": FIXTURE_SOURCE,
		"baseline_compiler": baseline_compile.get("summary", {}).get("compiler_version", ""),
		"measured_compiler": candidate_summary.get("compiler_version", ""),
		"baseline_total_mass_kg": baseline_compile.get("summary", {}).get("mass_kg", NAN),
		"measured_total_mass_kg": candidate_summary.get("mass_kg", NAN),
		"baseline_cg_le_m": _vector_array(baseline_data.get("cg_le", [])),
		"measured_cg_le_m": _vector_array(candidate_data.get("cg_le", [])),
		"baseline_mass_tensor_kg_m2": _vector_array(baseline_data.get("inertia", [])),
		"measured_mass_tensor_kg_m2": _vector_array(candidate_data.get("inertia", [])),
		"undo_restored": undo_ok,
		"redo_restored": redo_ok,
	}
	_check("measured compiler is distinct from the legacy compiler", str(comparison.measured_compiler) == Compiler.MEASURED_MASS_COMPILER_VERSION
		and str(comparison.baseline_compiler) == Compiler.COMPILER_VERSION)
	_check("measured mass/CG/tensor comparison is finite", _comparison_is_finite(comparison))

	var trial_payloads: Array[Dictionary] = []
	workshop.trial_requested.connect(func(payload: Dictionary) -> void: trial_payloads.append(payload))
	workshop.call("_request_trial")
	var frozen_trial: Dictionary = Trial.freeze(trial_payloads[0]) if trial_payloads.size() == 1 else {"ok": false, "errors": ["Workshop emitted no trial request."]}
	var trial_identity: Dictionary = frozen_trial.get("identity", {})
	_check("Workshop trial request freezes exact measured build pins",
		bool(frozen_trial.get("ok", false))
		and str(trial_identity.get("compiler", "")) == Compiler.MEASURED_MASS_COMPILER_VERSION
		and trial_identity.get("base_id", "") == Catalog.DEFAULT_ID,
		str(frozen_trial.get("errors", [])))
	comparison["trial_freeze_ok"] = bool(frozen_trial.get("ok", false))
	comparison["trial_identity"] = trial_identity
	comparison["trial_errors"] = frozen_trial.get("errors", [])
	comparison["trial_base_sha256"] = str(trial_identity.get("base_sha256", ""))
	comparison["trial_resolved_model_sha256"] = str(trial_identity.get("resolved_model_sha256", ""))
	comparison["trial_compiler"] = str(trial_identity.get("compiler", ""))
	var comparison_path := absolute_output.path_join("measured-build-comparison-%s.json" % language)
	_write_json(comparison_path, comparison)
	var viewport_final := _base_evidence(language, requested_size, text_scale, scratch, absolute_output)
	viewport_final["format"] = "openrc-aircraft-mass-native-capture v1"
	viewport_final["screenshots"] = {"workshop": main_capture_path, "measured_components": dialog_capture_path}
	viewport_final["renderer"] = RenderingServer.get_current_rendering_method()
	viewport_final["adapter"] = RenderingServer.get_video_adapter_name()
	viewport_final["display_server"] = DisplayServer.get_name()
	viewport_final["full_model"] = model_geometry
	viewport_final["dialog"] = modal_metrics
	viewport_final["localization"] = localization
	viewport_final["cancel_focus"] = true
	viewport_final["dirty_fields_preserved"] = dirty_fields_preserved
	viewport_final["cancel_preserved_recipe"] = cancel_preserved
	viewport_final["applied_new_build"] = applied_ok
	viewport_final["undo"] = undo_ok
	viewport_final["redo"] = redo_ok
	viewport_final["comparison"] = comparison_path
	viewport_final["checks"] = {"count": _log_lines.size(), "failures": _failures.duplicate()}
	viewport_final["source_sha256"] = _source_hashes()
	await _finish(workshop, scratch, absolute_evidence, viewport_final)
	print("AE-12/13 mass native capture %s %s text %.0f%%: %d failures" % [
		language, str(requested_size), text_scale * 100.0, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)


func _dialog_metrics(main_window: Window, dialog: ConfirmationDialog, footer_buttons: Array,
		content_buttons: Array, requested_size: Vector2i) -> Dictionary:
	var main_rect := Rect2(Vector2.ZERO, Vector2(requested_size))
	var dialog_rect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
	var dialog_viewport := dialog.get_visible_rect().size
	var dialog_inside_main := main_rect.encloses(dialog_rect)
	var footer_records: Array[Dictionary] = []
	var footer_fit := footer_buttons.size() == 2
	for item: Variant in footer_buttons:
		if not item is Button:
			footer_fit = false
			continue
		var button: Button = item
		var rect := button.get_global_rect()
		var fits := button.is_visible_in_tree() and not button.disabled and rect.size.x > 0.0 and rect.size.y > 0.0 \
			and Rect2(Vector2.ZERO, dialog_viewport).encloses(rect)
		footer_fit = footer_fit and fits
		footer_records.append({"text": button.text, "rect": _rect_array(rect), "visible": button.is_visible_in_tree(),
			"enabled": not button.disabled, "inside_dialog_viewport": fits, "focus_mode": button.focus_mode})
	var scroll := dialog.find_child("MassDialogScroll", true, false) as ScrollContainer
	var content_records: Array[Dictionary] = []
	var actions_reachable := is_instance_valid(scroll) and content_buttons.size() == 3
	var original_scroll := scroll.scroll_vertical if is_instance_valid(scroll) else 0
	for item: Variant in content_buttons:
		if not item is Button or not is_instance_valid(scroll):
			actions_reachable = false
			continue
		var button: Button = item
		scroll.ensure_control_visible(button)
		await _settle(2)
		var scroll_rect := scroll.get_global_rect()
		var button_rect := button.get_global_rect()
		var visible_part := scroll_rect.intersection(button_rect)
		var reachable := button.is_visible_in_tree() and not button.disabled and button_rect.size.x > 0.0 \
			and visible_part.size.x >= button_rect.size.x - 1.0 and visible_part.size.y >= button_rect.size.y - 1.0
		actions_reachable = actions_reachable and reachable
		content_records.append({"text": button.text, "rect": _rect_array(button_rect), "scroll_rect": _rect_array(scroll_rect),
			"visible_intersection": _rect_array(visible_part), "reachable_by_scroll": reachable})
	if is_instance_valid(scroll):
		scroll.scroll_vertical = original_scroll
		await _settle(2)
	return {"window_rect": _rect_array(main_rect), "dialog_rect": _rect_array(dialog_rect),
		"dialog_size": [dialog.size.x, dialog.size.y], "dialog_viewport": [dialog_viewport.x, dialog_viewport.y],
		"dialog_inside_main": dialog_inside_main, "footer_actions_fit": footer_fit,
		"footer_buttons": footer_records, "content_actions_reachable": actions_reachable,
		"content_buttons": content_records, "embedded_subwindows": main_window.gui_embed_subwindows,
		"scroll_enabled": is_instance_valid(scroll) and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED}


func _localization_metrics(language: String, dialog: ConfirmationDialog, cancel_button: Button,
		apply_button: Button, stage_button: Button) -> Dictionary:
	var expected := {"title": "Measured component mass", "cancel": "Cancel",
		"apply": "Apply to a new build", "stage": "Add or update measurement"}
	if language == "es":
		expected = {"title": "Masa medida de componentes", "cancel": "Cancelar",
		"apply": "Aplicar a una nueva versión", "stage": "Agregar o actualizar medición"}
	var actual := {"title": dialog.title, "cancel": cancel_button.text,
		"apply": apply_button.text, "stage": stage_button.text}
	return {"ok": actual == expected, "language": language, "expected": expected, "actual": actual}


func _projected_geometry(preview: Control) -> Dictionary:
	var camera: Camera3D = preview.get("_camera")
	var model: Node3D = preview.get("_airplane_root")
	if not is_instance_valid(camera) or not is_instance_valid(model):
		return {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var vertex_count := 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.is_visible_in_tree() or mesh_instance.mesh == null:
			continue
		for surface_index: int in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not vertices is PackedVector3Array:
				continue
			for vertex: Vector3 in vertices:
				var world_point := mesh_instance.global_transform * vertex
				if camera.is_position_behind(world_point):
					continue
				var screen_point := camera.unproject_position(world_point)
				minimum = minimum.min(screen_point)
				maximum = maximum.max(screen_point)
				vertex_count += 1
	if vertex_count == 0:
		return {}
	var canvas_size := camera.get_viewport().get_visible_rect().size
	return {"viewport": [canvas_size.x, canvas_size.y], "vertex_count": vertex_count,
		"rect": [minimum.x, minimum.y, maximum.x - minimum.x, maximum.y - minimum.y],
		"width_fraction": (maximum.x - minimum.x) / maxf(canvas_size.x, 1.0),
		"height_fraction": (maximum.y - minimum.y) / maxf(canvas_size.y, 1.0)}


func _rect_inside_view(geometry: Dictionary) -> bool:
	if geometry.is_empty():
		return false
	var viewport: Array = geometry.get("viewport", [])
	var rect_data: Array = geometry.get("rect", [])
	if viewport.size() != 2 or rect_data.size() != 4:
		return false
	var view := Rect2(Vector2.ZERO, Vector2(float(viewport[0]), float(viewport[1])))
	var rect := Rect2(Vector2(float(rect_data[0]), float(rect_data[1])), Vector2(float(rect_data[2]), float(rect_data[3])))
	return view.encloses(rect) and rect.size.x > 0.0 and rect.size.y > 0.0


func _picker_index(picker: OptionButton, stable_id: String) -> int:
	for index: int in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == stable_id:
			return index
	return -1


func _vector_array(value: Variant) -> Array:
	if value is Array:
		return value.duplicate(true)
	if value is PackedFloat64Array or value is PackedVector3Array:
		var result: Array = []
		for item: Variant in value:
			result.append(item)
		return result
	return []


func _comparison_is_finite(comparison: Dictionary) -> bool:
	for key: String in ["baseline_total_mass_kg", "measured_total_mass_kg", "mass_delta_kg"]:
		if not is_finite(float(comparison.get(key, NAN))):
			return false
	for key: String in ["baseline_cg_le_m", "measured_cg_le_m", "baseline_mass_tensor_kg_m2", "measured_mass_tensor_kg_m2"]:
		var values: Array = comparison.get(key, [])
		if values.is_empty():
			return false
		for value: Variant in values:
			if not is_finite(float(value)):
				return false
	return true


func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in [
		"res://workshop/mass_edit.gd",
		"res://workshop/compiler.gd",
		"res://workshop/trial.gd",
		"res://ui/workshop_mass.gd",
		"res://ui/workshop_preview.gd",
		"res://ui/ui_scale.gd",
		"res://ui/ui_theme.gd",
		"res://physics/aircraft_data.gd",
		"res://physics/physical_identity.gd",
		"res://i18n/es.po",
		"res://tests/test_workshop_mass_edit.gd",
		"res://tests/test_workshop_mass_ui.gd",
		"res://tests/test_workshop_mass_recipe.gd",
	]:
		var bytes := FileAccess.get_file_as_bytes(path)
		var hash := HashingContext.new()
		var start_error := hash.start(HashingContext.HASH_SHA256)
		var update_error := hash.update(bytes) if start_error == OK else start_error
		result[path.trim_prefix("res://")] = hash.finish().hex_encode() if update_error == OK else "unavailable"
	var repo_root := ProjectSettings.globalize_path("res://").simplify_path().get_base_dir()
	var capture_path := repo_root.path_join("research/aircraft-editor/capture_mass.gd")
	var capture_bytes := FileAccess.get_file_as_bytes(capture_path)
	var capture_hash := HashingContext.new()
	var capture_start := capture_hash.start(HashingContext.HASH_SHA256)
	var capture_update := capture_hash.update(capture_bytes) if capture_start == OK else capture_start
	result["research/aircraft-editor/capture_mass.gd"] = capture_hash.finish().hex_encode() if capture_update == OK else "unavailable"
	return result


func _base_evidence(language: String, requested_size: Vector2i, text_scale: float,
		scratch: String, output_dir: String) -> Dictionary:
	return {"language": language, "requested_size": [requested_size.x, requested_size.y],
		"text_scale": text_scale, "scratch_root": scratch, "output_dir": output_dir,
		"engine_version": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"isolated_from_player_library": true, "physical_validation_claim": false}


func _is_isolated_scratch(scratch: String) -> bool:
	if not scratch.begins_with("user://%s" % SCRATCH_PREFIX):
		return false
	var absolute := ProjectSettings.globalize_path(scratch).simplify_path()
	var user_absolute := ProjectSettings.globalize_path("user://").simplify_path()
	return absolute.get_base_dir() == user_absolute and absolute.get_file().begins_with(SCRATCH_PREFIX)


func _absolute_path(path: String) -> String:
	var normalized := path.replace("\\", "/").strip_edges()
	if normalized.is_empty() or not normalized.is_absolute_path():
		return ""
	return normalized.simplify_path()


func _write_json(path: String, value: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "\t", true, true) + "\n")
	file.flush()
	var result := file.get_error()
	file.close()
	return result


func _check(label: String, passed: bool, detail: String = "") -> void:
	var line := ("PASS " if passed else "FAIL ") + label
	if not detail.is_empty():
		line += " — " + detail
	_log_lines.append(line)
	print(_log_lines[_log_lines.size() - 1])
	if not passed:
		_failures.append(label)
		push_error(label)


func _finish(workshop: Node, scratch: String, evidence_path: String, evidence: Dictionary) -> void:
	evidence["checks"] = {"count": _log_lines.size(), "failures": _failures.duplicate()}
	evidence["source_sha256"] = _source_hashes()
	var evidence_error := _write_json(evidence_path, evidence)
	if evidence_error != OK:
		_failures.append("Could not write evidence JSON: %s" % error_string(evidence_error))
	var log_path := evidence_path.get_basename() + ".log"
	var log_file := FileAccess.open(log_path, FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("\n".join(_log_lines) + "\nFAILURES %d\n" % _failures.size())
		log_file.flush()
		log_file.close()
	else:
		_failures.append("Could not write native capture log.")
	if is_instance_valid(workshop):
		workshop.free()
	await _settle(2)
	_remove_tree(ProjectSettings.globalize_path(scratch))


func _settle(count: int) -> void:
	for _frame: int in count:
		await process_frame


func _remove_tree(path: String) -> void:
	var absolute := path.simplify_path()
	var user_absolute := ProjectSettings.globalize_path("user://").simplify_path()
	if absolute.get_base_dir() != user_absolute or not absolute.get_file().begins_with(SCRATCH_PREFIX):
		push_error("Refusing to clean a capture scratch path outside its isolated user:// prefix.")
		return
	_remove_tree_contents(absolute)


func _remove_tree_contents(absolute: String) -> void:
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(absolute.path_join(file))
	for child: String in directory.get_directories():
		_remove_tree_contents(absolute.path_join(child))
	directory = null
	DirAccess.remove_absolute(absolute)


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
