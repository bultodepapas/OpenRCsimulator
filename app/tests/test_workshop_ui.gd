# AE-09: Workshop controls, supported edits, pinned variants and display sizing stay usable in isolation.
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Store := preload("res://workshop/store.gd")
const Workshop := preload("res://ui/workshop.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var _failures := 0
var _ui: RefCounted


func _initialize() -> void:
	_ui = UiDriver.new(self)
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _find(node: Node, child_name: String) -> Node:
	return node.find_child(child_name, true, false)


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1280, 720)
	var store_root := "user://test_workshop_ui_%d" % Time.get_ticks_usec()
	var workshop: Variant = Workshop.new()
	workshop.initial_aircraft_id = Catalog.DEFAULT_ID
	workshop.variants_root = store_root
	root.add_child(workshop)
	await _ui.settle()

	var title := _find(workshop, "WorkshopTitle") as Label
	var base_selector := _find(workshop, "BaseAircraft") as OptionButton
	var scale_selector := _find(workshop, "Scale") as OptionButton
	var mass_selector := _find(workshop, "MassPolicy") as OptionButton
	var test_fly := _find(workshop, "TestFly") as Button
	var preview := _find(workshop, "AircraftPreview") as Control
	_check("screen renders its title, preview and test action", title != null and preview != null and test_fly != null)
	_check("catalog selector discovers every aircraft", base_selector != null and base_selector.item_count == Catalog.ENTRIES.size())
	_check("initial keyboard focus enters the aircraft selector", _ui.focus_name() == "BaseAircraft", _ui.focus_name())
	_check("Workshop is a still editor with no flight session", workshop.get("_compiled").get("ok", false)
		and workshop.get("_trial_pending") == false)

	# Both target heights keep the preview, editor panel and Test Fly action available.
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await _ui.settle()
		var panel := _find(workshop, "WorkshopPanel") as Control
		_check("layout fits %dp height" % viewport_size.y,
			panel != null and panel.get_rect().size.x > 0.0 and panel.get_rect().size.y > 0.0
			and preview.is_visible_in_tree() and test_fly.is_visible_in_tree()
			and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(test_fly.get_global_rect())
			and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(title.get_global_rect()))
	_check("opening starts at the top of the editor", workshop.get("_body_scroll").scroll_vertical == 0)

	# The same menu labels can translate while the screen is open.
	TranslationServer.set_locale("es")
	await _ui.settle()
	_check("Spanish locale translates the Workshop title", title != null and title.can_auto_translate()
		and title.atr(title.text) == "Laboratorio de aviones", title.atr(title.text) if title != null else "missing title")
	TranslationServer.set_locale("en")
	await _ui.settle()
	await _ui.tap(KEY_TAB)
	_check("Tab advances focus inside the editor", _ui.focus_name() != "" and _ui.focus_name() != "BaseAircraft", _ui.focus_name())

	var unsupported_found := false
	for entry: Dictionary in Catalog.ENTRIES:
		var aircraft_id := str(entry.get("id", ""))
		workshop.set_aircraft(aircraft_id)
		await _ui.settle()
		var selected_index := base_selector.get_selected_id()
		var selected_matches := str(base_selector.get_item_metadata(selected_index)) == aircraft_id
		_check("catalog selection remains aligned: %s" % aircraft_id, selected_matches)
		var raw_base: Dictionary = workshop.get("_base")
		if raw_base.is_empty():
			_check("preview-only aircraft blocks flight build: %s" % aircraft_id, not bool(workshop.get_compiled().get("ok", false)))
			continue
		var caps: Dictionary = Compiler.capabilities(raw_base)
		_check("no-op build validates: %s" % aircraft_id, bool(workshop.get_compiled().get("ok", false)))
		var weight_slider := workshop.get("_factor_sliders")["weight_multiplier"] as HSlider
		var power_slider := workshop.get("_factor_sliders")["power_multiplier"] as HSlider
		var control_slider := workshop.get("_factor_sliders")["control_multiplier"] as HSlider
		_check("unsupported controls stay visible and inactive: %s" % aircraft_id,
			scale_selector.disabled == not bool(caps.get("scale", false))
			and mass_selector.disabled == not bool(caps.get("weight", false))
			and weight_slider.editable == bool(caps.get("weight", false))
			and power_slider.editable == bool(caps.get("power", false))
			and control_slider.editable == bool(caps.get("controls", false)))
		if not bool(caps.get("scale", false)):
			unsupported_found = true
	_check("catalog includes aircraft with restricted Workshop adjustments", unsupported_found)

	workshop.set_aircraft(Catalog.DEFAULT_ID)
	await _ui.settle()
	workshop.set_recipe({"scale": 1.33, "weight_multiplier": 0.731}, false)
	_check("intermediate recipe values are never silently rounded", is_equal_approx(workshop.get_recipe().scale, 1.33)
		and is_equal_approx(workshop.get_recipe().weight_multiplier, 0.731))
	_check("slider displays the exact saved multiplier", is_equal_approx(workshop.get("_factor_sliders")["weight_multiplier"].value, 0.731))
	_check("scale selector includes the exact intermediate size", scale_selector.get_item_metadata(scale_selector.selected) == 1.33)
	var precise_recipe: Dictionary = workshop.get_recipe()
	workshop.set_recipe({"scale": []})
	_check("malformed recipe is refused before changing the draft", workshop.get_recipe() == precise_recipe
		and str(workshop.get("_status_label").text).contains("finite number"))
	for requested_scale: float in [0.5, 2.0]:
		workshop.set_recipe({"scale": requested_scale}, false)
		_check("scale %.0f%% compiles" % (requested_scale * 100.0), bool(workshop.get_compiled().get("ok", false))
			and is_equal_approx(float(workshop.get_recipe().scale), requested_scale))

	for preset_id: String in Workshop.PRESETS:
		var preset_button := _find(workshop, "Preset" + preset_id.capitalize()) as Button
		if preset_button != null:
			preset_button.pressed.emit()
			await _ui.settle()
		_check("%s preset produces a valid recipe" % preset_id.capitalize(),
			bool(workshop.get_compiled().get("ok", false)))

	var previous_recipe: Dictionary = workshop.get_recipe()
	workshop.set_recipe({"scale": 0.5}, true)
	(_find(workshop, "UndoRecipe") as Button).pressed.emit()
	await _ui.settle()
	_check("Undo restores the prior recipe", workshop.get_recipe() == previous_recipe)
	workshop.set_recipe({"scale": 2.0, "weight_multiplier": 1.2, "power_multiplier": 1.1}, false)
	(_find(workshop, "ResetRecipe") as Button).pressed.emit()
	await _ui.settle()
	_check("Reset returns every value to compiler defaults", workshop.get_recipe() == Compiler.defaults())

	# History belongs to this source and handles a slider drag as one edit.
	workshop.set_aircraft(Catalog.DEFAULT_ID)
	var undo_button := _find(workshop, "UndoRecipe") as Button
	var redo_button := _find(workshop, "RedoRecipe") as Button
	workshop.set_recipe({"scale": 0.5})
	workshop.set_recipe({"scale": 2.0})
	undo_button.pressed.emit()
	_check("first Undo restores the preceding edit", workshop.get_recipe().scale == 0.5)
	undo_button.pressed.emit()
	_check("second Undo restores the original", workshop.get_recipe() == Compiler.defaults() and undo_button.disabled)
	redo_button.pressed.emit()
	redo_button.pressed.emit()
	_check("Redo restores both edits", workshop.get_recipe().scale == 2.0 and redo_button.disabled)
	undo_button.pressed.emit()
	workshop.set_recipe({"scale": 1.5})
	_check("new edit clears the redo branch", redo_button.disabled)
	workshop.set_aircraft(Catalog.DEFAULT_ID)
	var power_slider: HSlider = workshop.get("_factor_sliders")["power_multiplier"]
	power_slider.drag_started.emit()
	power_slider.value = 1.15
	power_slider.value = 1.2
	power_slider.drag_ended.emit(true)
	_check("slider drag contributes one history entry", workshop.get("_undo_history").size() == 1)
	undo_button.pressed.emit()
	_check("undoing a slider drag restores its starting value", workshop.get_recipe().power_multiplier == 1.0)
	power_slider.drag_started.emit()
	power_slider.drag_ended.emit(false)
	_check("a drag without changes preserves redo", not redo_button.disabled and undo_button.disabled)
	for edit_index: int in 40:
		workshop.set_recipe({"scale": 0.5 if edit_index % 2 == 0 else 2.0})
	_check("history is bounded", workshop.get("_undo_history").size() == Workshop.HISTORY_LIMIT)
	workshop.set_aircraft(Catalog.DEFAULT_ID)
	_check("changing source clears both history branches", undo_button.disabled and redo_button.disabled)

	# The whole storage flow stays under a per-run user:// directory.
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	workshop.set_variant_name("Workshop UI check")
	workshop.save_named_variant()
	await _ui.settle()
	var variants: Array = Store.list_variants(store_root)
	_check("Save creates one local revision", variants.size() == 1 and int(variants[0].get("revision", 0)) == 1)
	var saved_id := str(variants[0].get("id", "")) if not variants.is_empty() else ""
	workshop.set_recipe({"scale": 2.0}, false)
	workshop.save_named_variant()
	await _ui.settle()
	variants = Store.list_variants(store_root)
	_check("Save updates the same variant as revision two", variants.size() == 1
		and str(variants[0].get("id", "")) == saved_id and int(variants[0].get("revision", 0)) == 2)
	if not variants.is_empty():
		var saved: Dictionary = variants[0]
		_check("saved provenance pins exact source, compiler and dependencies",
			saved.get("base_bytes", PackedByteArray()) == source_bytes
			and str(saved.get("compiler_version", "")) != ""
			and saved.get("dependencies", {}) is Dictionary and not saved.get("dependencies", {}).is_empty())

	var emitted_payloads: Array[Dictionary] = []
	workshop.trial_requested.connect(func(payload: Dictionary) -> void: emitted_payloads.append(payload))
	(_find(workshop, "TestFly") as Button).pressed.emit()
	await _ui.settle()
	var payload: Dictionary = emitted_payloads[0] if not emitted_payloads.is_empty() else {}
	_check("Test Fly emits the exact pinned snapshot and variant revision",
		payload.get("base_bytes", PackedByteArray()) == source_bytes
		and str(payload.get("variant_id", "")) == saved_id
		and int(payload.get("variant_revision", 0)) == 2
		and str(payload.get("compiler_version", "")) == str(variants[0].get("compiler_version", ""))
		and payload.get("dependencies", {}) == variants[0].get("dependencies", {}))
	workshop.set_note("")

	workshop.set_recipe({"scale": 0.5}, false)
	(_find(workshop, "LoadVariant") as Button).pressed.emit()
	await _ui.settle()
	_check("Load restores the saved recipe and original source bytes",
		is_equal_approx(float(workshop.get_recipe().scale), 2.0)
		and workshop.get("_base_bytes") == source_bytes
		and int(workshop.get("_saved_variant_revision")) == 2)
	_check("loading a saved variant clears unrelated undo state", undo_button.disabled and redo_button.disabled)
	(_find(workshop, "DeleteVariant") as Button).pressed.emit()
	await _ui.settle()
	workshop.get("_delete_dialog").confirmed.emit()
	await _ui.settle()
	_check("Delete removes the saved variant and disables its actions", Store.list_variants(store_root).is_empty()
		and (_find(workshop, "LoadVariant") as Button).disabled
		and (_find(workshop, "DeleteVariant") as Button).disabled)
	_check("deleting the current variant leaves an unsaved draft", str(workshop.get("_saved_variant_id")).is_empty()
		and int(workshop.get("_saved_variant_revision")) == 0)
	(_find(workshop, "RestoreVariant") as Button).pressed.emit()
	await _ui.settle()
	var restored: Dictionary = Store.load_variant(saved_id, store_root)
	_check("Undo delete restores the original revision", restored.get("ok", false)
		and restored.get("variant", {}).get("revision", 0) == 2)
	workshop.save_named_variant()
	await _ui.settle()
	_check("saving the retained draft creates a separate variant", Store.list_variants(store_root).size() == 2
		and str(workshop.get("_saved_variant_id")) != saved_id)

	# A second writer cannot be silently overwritten by this older editor draft.
	var current_id: String = workshop.get("_saved_variant_id")
	var current_revision: int = workshop.get("_saved_variant_revision")
	var concurrent_recipe: Dictionary = Compiler.defaults()
	concurrent_recipe.power_multiplier = 1.3
	var concurrent: Dictionary = Store.save_variant("Another editor", Catalog.DEFAULT_ID, source_bytes,
		concurrent_recipe, current_id, store_root, workshop.get("_workshop_descriptor"),
		workshop.get("_variant_dependencies"), current_revision)
	_check("concurrent save fixture advances the revision", concurrent.get("ok", false))
	workshop.set_recipe({"power_multiplier": 0.9})
	workshop.save_named_variant()
	var after_conflict: Dictionary = Store.load_variant(current_id, store_root)
	_check("stale editor save preserves the newer revision and current draft", after_conflict.get("ok", false)
		and after_conflict.variant.recipe.power_multiplier == 1.3
		and workshop.get_recipe().power_multiplier == 0.9
		and int(workshop.get("_saved_variant_revision")) == current_revision)
	workshop.save_variant_copy()
	_check("conflicting draft can be saved as its own copy", str(workshop.get("_saved_variant_id")) != current_id)
	workshop.set_recipe({"scale": 1.33, "weight_multiplier": 0.731})
	workshop.save_named_variant()
	var exact_recipe: Dictionary = workshop.get_recipe()
	workshop.set_recipe({"scale": 0.5})
	(_find(workshop, "LoadVariant") as Button).pressed.emit()
	_check("precise saved recipe round-trips without quantization", workshop.get_recipe() == exact_recipe)

	# A removed catalog entry remains a readable library item, but cannot corrupt the open draft.
	var removed_base: Dictionary = JSON.parse_string(source_bytes.get_string_from_utf8())
	removed_base.id = "removed-catalog-fixture"
	var removed_bytes: PackedByteArray = JSON.stringify(removed_base, "", true, true).to_utf8_buffer()
	var removed_descriptor: Dictionary = Descriptor.load_for(Catalog.DEFAULT_ID, source_bytes).descriptor.duplicate(true)
	removed_descriptor.base_id = removed_base.id
	removed_descriptor.base_sha256 = removed_bytes.get_string_from_utf8().sha256_text()
	var removed: Dictionary = Store.save_variant("Unavailable airplane", removed_base.id, removed_bytes,
		Compiler.defaults(), "", store_root, removed_descriptor)
	_check("removed catalog fixture is stored independently", removed.get("ok", false), str(removed.get("errors", [])))
	if removed.get("ok", false):
		var old_base_id: String = workshop.get("_base_id")
		var old_saved_id: String = workshop.get("_saved_variant_id")
		var old_bytes: PackedByteArray = workshop.get("_base_bytes")
		workshop.set("_selected_variant_id", removed.variant.id)
		(_find(workshop, "LoadVariant") as Button).pressed.emit()
		_check("unavailable source load preserves the entire current draft", workshop.get("_base_id") == old_base_id
			and workshop.get("_base_bytes") == old_bytes and workshop.get_recipe() == exact_recipe
			and workshop.get("_saved_variant_id") == old_saved_id)
	var recovering_id: String = workshop.get("_saved_variant_id")
	var manifest_path := store_root.path_join(recovering_id).path_join("manifest.json")
	var broken_manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	broken_manifest.store_string("{")
	broken_manifest.close()
	broken_manifest = null
	workshop.set("_selected_variant_id", recovering_id)
	(_find(workshop, "LoadVariant") as Button).pressed.emit()
	_check("backup recovery visibly identifies the earlier revision", int(workshop.get("_saved_variant_revision")) == 1
		and str(workshop.get("_status_label").text).contains("from backup"))
	workshop.save_named_variant()
	_check("saving a recovered draft advances past existing immutable revisions", int(workshop.get("_saved_variant_revision")) == 3
		and not Store.load_variant(recovering_id, store_root).variant.recovered_from_manifest_backup,
		"revision=%s note=%s" % [workshop.get("_saved_variant_revision"), workshop.get("_status_label").text])

	workshop.queue_free()
	await _ui.settle()
	var absolute_root := ProjectSettings.globalize_path(store_root)
	if DirAccess.dir_exists_absolute(absolute_root):
		_remove_fixture(absolute_root, absolute_root)
	TranslationServer.set_locale("en")
	print("Workshop UI: %d failed" % _failures)
	quit(1 if _failures else 0)


func _remove_fixture(path: String, fixture_root: String) -> void:
	assert(path == fixture_root or path.begins_with(fixture_root + "/"))
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	for child: String in directory.get_directories():
		_remove_fixture(path.path_join(child), fixture_root)
	directory = null
	DirAccess.remove_absolute(path)
