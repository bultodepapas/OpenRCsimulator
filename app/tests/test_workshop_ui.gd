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
	var airplane_entries: Array = Catalog.airplane_flyable_entries()
	_check("screen renders its title, preview and test action", title != null and preview != null and test_fly != null)
	_check("airplane selector discovers every fixed-wing flyable aircraft",
		base_selector != null and base_selector.item_count == airplane_entries.size())
	_check("initial keyboard focus enters the library action", _ui.focus_name() == "OpenLibrary", _ui.focus_name())
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
		and title.atr(title.text) == "Taller de aviones", title.atr(title.text) if title != null else "missing title")
	TranslationServer.set_locale("en")
	await _ui.settle()
	await _ui.tap(KEY_TAB)
	_check("Tab advances focus inside the editor", _ui.focus_name() != "" and _ui.focus_name() != "OpenLibrary", _ui.focus_name())

	var unsupported_found := false
	for entry: Dictionary in airplane_entries:
		var aircraft_id := str(entry.get("id", ""))
		workshop.set_aircraft(aircraft_id, true)
		await _ui.settle()
		var selected_index := base_selector.get_selected_id()
		var selected_matches := str(base_selector.get_item_metadata(selected_index)) == aircraft_id
		_check("fixed-wing selection remains aligned: %s" % aircraft_id, selected_matches)
		var raw_base: Dictionary = workshop.get("_base")
		if raw_base.is_empty():
			_check("preview-only aircraft blocks flight build: %s" % aircraft_id, not bool(workshop.get_compiled().get("ok", false)))
			continue
		var caps: Dictionary = Compiler.capabilities(raw_base)
		_check("no-op build validates: %s" % aircraft_id, bool(workshop.get_compiled().get("ok", false)))
		var weight_slider := workshop.get("_factor_sliders")["weight_multiplier"] as HSlider
		var power_slider := workshop.get("_factor_sliders")["power_multiplier"] as HSlider
		var control_slider := workshop.get("_factor_sliders")["control_multiplier"] as HSlider
		var tank_capacity_slider := workshop.get("_factor_sliders")["tank_capacity_multiplier"] as HSlider
		_check("unsupported controls stay visible and inactive: %s" % aircraft_id,
			scale_selector.disabled == not bool(caps.get("scale", false))
			and mass_selector.disabled == not bool(caps.get("weight", false))
			and weight_slider.editable == bool(caps.get("weight", false))
			and power_slider.editable == bool(caps.get("power", false))
			and control_slider.editable == bool(caps.get("controls", false))
			and tank_capacity_slider.editable == bool(caps.get("tank_capacity", false)))
		if not bool(caps.get("tank_capacity", false)):
			var tank_hint: Label = workshop.get("_factor_hints")["tank_capacity_multiplier"]
			_check("tank-size control explains the absence of a declared finite tank: %s" % aircraft_id,
				tank_hint.text.contains("No declared finite tank"), tank_hint.text)
		if not bool(caps.get("scale", false)):
			unsupported_found = true
	_check("catalog includes aircraft with restricted Workshop adjustments", unsupported_found)
	workshop.set_aircraft("gp-extra-300s-60", true)
	await _ui.settle()
	var glow_scale_hint := _find(workshop, "ScaleSupport") as Label
	var glow_capacity_slider := workshop.get("_factor_sliders")["tank_capacity_multiplier"] as HSlider
	_check("finite-glow engine scaling stays disabled with its qualified limitation",
		scale_selector.disabled and glow_scale_hint != null
		and glow_scale_hint.text.contains("finite-glow installation data must remain fixed"),
		glow_scale_hint.text if glow_scale_hint != null else "missing scale limitation")
	_check("finite-glow aircraft still exposes independent finite-tank sizing",
		glow_capacity_slider.editable
		and str(workshop.get("_factor_hints")["tank_capacity_multiplier"].text).contains("Estimated sizing proposal"))
	workshop.set_aircraft("xcell-60-research", true)
	await _ui.settle()
	var rotorcraft_note := _find(workshop, "WorkshopStatus") as Label
	_check("direct rotorcraft requests return to the fixed-wing default",
		workshop.get("_base_id") == Catalog.DEFAULT_ID and bool(workshop.get_compiled().get("ok", false)))
	_check("direct rotorcraft requests explain the Workshop limit",
		rotorcraft_note != null and "fixed-wing" in rotorcraft_note.text.to_lower())

	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	await _ui.settle()
	var tank_capacity_slider := workshop.get("_factor_sliders")["tank_capacity_multiplier"] as HSlider
	var tank_capacity_hint: Label = workshop.get("_factor_hints")["tank_capacity_multiplier"]
	_check("declared tank exposes a separate estimated-capacity control",
		bool(workshop.get("_capabilities").get("tank_capacity", false))
		and tank_capacity_slider.editable and tank_capacity_hint.text.contains("Estimated sizing proposal"))
	workshop.set_recipe({"tank_capacity_multiplier": 1.25}, false)
	_check("tank-size edit compiles and is called out as an estimate",
		bool(workshop.get_compiled().get("ok", false))
		and is_equal_approx(float(workshop.get_recipe().tank_capacity_multiplier), 1.25)
		and is_equal_approx(tank_capacity_slider.value, 1.25)
		and str(workshop.get("_summary_label").text).contains("estimated sizing"),
		str(workshop.get("_summary_label").text))
	workshop.set_recipe({"tank_capacity_multiplier": 1.0}, false)
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
		var presets := _find(workshop, "StartingPreset") as OptionButton
		for index in presets.item_count:
			if presets.get_item_metadata(index) == preset_id:
				presets.select(index)
				presets.item_selected.emit(index)
				break
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
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
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
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
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
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
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
	_discard_pending(workshop)
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
	_discard_pending(workshop)
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
		_discard_pending(workshop)
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
	_discard_pending(workshop)
	_check("backup recovery visibly identifies the earlier revision", int(workshop.get("_saved_variant_revision")) == 1
		and str(workshop.get("_status_label").text).contains("from backup"))
	workshop.save_named_variant()
	_check("saving a recovered draft advances past existing immutable revisions", int(workshop.get("_saved_variant_revision")) == 3
		and not Store.load_variant(recovering_id, store_root).variant.recovered_from_manifest_backup,
		"revision=%s note=%s" % [workshop.get("_saved_variant_revision"), workshop.get("_status_label").text])

	# The store accepts historical recipes with duplicate cosmetic metadata.
	var metadata_recipe: Dictionary = Compiler.defaults()
	metadata_recipe["id"] = "12345678-1234-4234-8234-123456789abc"
	metadata_recipe["name"] = "Historical recipe metadata"
	var metadata_saved: Dictionary = Store.save_variant(metadata_recipe.name, Catalog.DEFAULT_ID,
		source_bytes, metadata_recipe, metadata_recipe.id, store_root)
	_check("historical metadata fixture saves", metadata_saved.get("ok", false), str(metadata_saved.get("errors", [])))
	if metadata_saved.get("ok", false):
		workshop.set("_selected_variant_id", metadata_recipe.id)
		workshop.call("_load_selected_variant")
		_discard_pending(workshop)
		_check("loaded draft separates recipe physics from record metadata",
			not workshop.get_recipe().has("id") and not workshop.get_recipe().has("name"))
		workshop.set_variant_name("Renamed historical build")
		workshop.save_named_variant()
		var renamed_metadata: Dictionary = Store.load_variant(metadata_recipe.id, store_root)
		_check("historical recipe can be renamed", renamed_metadata.get("ok", false)
			and renamed_metadata.variant.name == "Renamed historical build"
			and renamed_metadata.variant.revision == 2)
		workshop.save_variant_copy()
		_check("historical recipe copy receives a separate identity",
			workshop.get("_saved_variant_id") != metadata_recipe.id
			and workshop.get("_saved_variant_revision") == 1)
		_check("copy leaves the source history untouched",
			Store.load_variant(metadata_recipe.id, store_root).variant.revision == 2)

	await _guarded_journey(workshop, store_root)
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


func _discard_pending(editor: Node) -> void:
	var dialog: ConfirmationDialog = editor.get("_guard_dialog")
	if dialog != null: dialog.custom_action.emit("discard")


func _guarded_journey(editor: Node, store_root: String) -> void:
	editor.set_aircraft(Catalog.DEFAULT_ID, true)
	_check("new source begins with a clean full-payload baseline", not editor.has_unsaved_changes())
	editor.set_recipe({power_multiplier = 1.2})
	var draft: Dictionary = editor.get_recipe()
	var history_size: int = editor.get("_undo_history").size()
	var result := {continued = 0, cancelled = 0}
	var proceed := func() -> void: result.continued += 1
	var cancel := func() -> void: result.cancelled += 1
	editor.request_navigation("Back to Home", proceed, cancel)
	var guard: ConfirmationDialog = editor.get("_guard_dialog")
	_check("dirty transition opens an exclusive safe-default decision", guard != null and guard.visible
		and guard.exclusive and guard.get_cancel_button().has_focus())
	guard.canceled.emit()
	_check("Cancel preserves draft, source and undo history", result.continued == 0 and result.cancelled == 1
		and editor.get_recipe() == draft and editor.get("_undo_history").size() == history_size
		and editor.has_unsaved_changes())
	editor.call("_undo")
	_check("undo to complete baseline clears changed state", not editor.has_unsaved_changes())
	editor.call("_set_page", "compare")
	editor.get("_preview").set_view_mode("compare")
	_check("page and camera comparison do not change build identity", not editor.has_unsaved_changes())
	editor.call("_set_page", "setup")
	var previous_descriptor: Dictionary = editor.get("_workshop_descriptor").duplicate(true)
	editor.set("_workshop_descriptor", {test_identity = "different pin"})
	_check("persisted descriptor identity participates in dirty state", editor.has_unsaved_changes())
	editor.set("_workshop_descriptor", previous_descriptor)
	var previous_id: String = editor.get("_base_id")
	editor.set("_base_id", "same-values-other-source")
	_check("equal physical defaults cannot mask a changed source identity", editor.has_unsaved_changes())
	editor.set("_base_id", previous_id)
	_check("restored full baseline is clean", not editor.has_unsaved_changes())

	# Stock browsing is observational; only explicit Open can replace a build.
	editor.set_recipe({power_multiplier = 1.1})
	editor.call("_open_library")
	var selector: OptionButton = editor.get("_base_selector")
	var other := 1 if selector.item_count > 1 else 0
	selector.select(other)
	selector.item_selected.emit(other)
	_check("stock browsing keeps active source and draft", editor.get("_base_id") == previous_id
		and editor.get_recipe().power_multiplier == 1.1)
	(_find(editor, "OpenStockAircraft") as Button).pressed.emit()
	guard = editor.get("_guard_dialog")
	_check("opening another source is guarded before replacement", guard != null and editor.get("_base_id") == previous_id)
	guard.canceled.emit()
	_check("cancelled source replacement retains the outgoing draft", editor.get("_base_id") == previous_id
		and editor.get_recipe().power_multiplier == 1.1)

	# Invalid typed values are never silently clamped, saved or launched.
	var entry: LineEdit = editor.get("_factor_inputs")["weight_multiplier"]
	entry.text = "not a number"
	entry.text_changed.emit(entry.text)
	var saved_count := Store.list_variants(store_root).size()
	_check("invalid numeric input blocks Save and Test fly", editor.save_button.disabled
		and (_find(editor, "TestFly") as Button).disabled and editor.has_unsaved_changes())
	editor.save_named_variant()
	_check("programmatic Save also refuses invalid displayed input", Store.list_variants(store_root).size() == saved_count)
	editor.request_navigation("Back to Home", proceed, cancel)
	guard = editor.get("_guard_dialog")
	_check("invalid draft offers discard/cancel but not false save", guard != null and guard.get_ok_button().disabled)
	guard.canceled.emit()
	_check("Cancel keeps invalid input visible for correction", entry.text == "not a number")
	entry.text = "0.731"
	entry.text_changed.emit(entry.text)
	entry.text_submitted.emit(entry.text)
	_check("numeric entry commits an exact intermediate value", is_equal_approx(editor.get_recipe().weight_multiplier, 0.731)
		and not editor.save_button.disabled)

	# Save and continue is explicit, single-shot and marks exactly the saved payload clean.
	editor.request_navigation("Back to Home", proceed, cancel)
	guard = editor.get("_guard_dialog")
	editor.get("_guard_name").text = "Guarded build"
	guard.confirmed.emit()
	_check("successful Save completes the captured navigation once", result.continued == 1
		and not editor.has_unsaved_changes() and editor.get("_guard_dialog") == null)
	var saved_id: String = editor.get("_saved_variant_id")
	var saved_revision: int = editor.get("_saved_variant_revision")
	var saved_record: Dictionary = Store.load_variant(saved_id, store_root).variant
	var advanced := Store.save_variant("Concurrent save", saved_record.base_id, saved_record.base_bytes,
		saved_record.recipe, saved_id, store_root, saved_record.workshop_descriptor, saved_record.dependencies,
		saved_revision)
	_check("save-failure fixture advances the expected revision", advanced.ok)
	editor.set_recipe({power_multiplier = 1.3})
	editor.request_navigation("Back to Home", proceed, cancel)
	guard = editor.get("_guard_dialog")
	guard.confirmed.emit()
	_check("failed save leaves pending decision and full draft", result.continued == 1 and guard.visible
		and editor.get_recipe().power_multiplier == 1.3 and editor.has_unsaved_changes())
	guard.canceled.emit()

	# A confirmation freezes UUID/revision independently of later library highlights.
	editor.call("_open_library")
	editor.set("_selected_variant_id", saved_id)
	editor.call("_confirm_delete_selected")
	var source_bytes: PackedByteArray = editor.get("_base_bytes")
	var other_saved: Dictionary = Store.save_variant("Another build", Catalog.DEFAULT_ID, source_bytes,
		Compiler.defaults(), "", store_root)
	editor.set("_selected_variant_id", other_saved.variant.id)
	editor.get("_delete_dialog").confirmed.emit()
	_check("changed library selection cannot redirect delete", not Store.load_variant(saved_id, store_root).ok
		and Store.load_variant(other_saved.variant.id, store_root).ok)
	editor.call("_restore_last_deleted")
	_check("exact generation restore recovers captured build", Store.load_variant(saved_id, store_root).ok)
	editor.set("_selected_variant_id", saved_id)
	editor.call("_confirm_delete_selected")
	var record: Dictionary = Store.load_variant(saved_id, store_root).variant
	var concurrent := Store.save_variant("Advanced build", record.base_id, record.base_bytes, record.recipe,
		saved_id, store_root, record.workshop_descriptor, record.dependencies, int(record.revision))
	editor.get("_delete_dialog").confirmed.emit()
	_check("stale confirmation refuses a newer revision", concurrent.ok and Store.load_variant(saved_id, store_root).ok
		and Store.load_variant(saved_id, store_root).variant.revision == saved_revision + 2)
	editor.call("_close_library")
	await _ui.settle()
