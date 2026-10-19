extends SceneTree
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Parameters := preload("res://workshop/parameters.gd")
const MassEdit := preload("res://workshop/mass_edit.gd")
const Store := preload("res://workshop/store.gd")
const Trial := preload("res://workshop/trial.gd")
const Bundle := preload("res://workshop/bundle.gd")
const Experiments := preload("res://workshop/experiments.gd")
const Qualification := preload("res://workshop/start_qualification.gd")
const Field := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")
const Workshop := preload("res://ui/workshop.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed: failures += 1
func run() -> void:
	var bytes := FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var base: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var original := JSON.stringify(base, "", true, true)
	var inventory := MassEdit.inspect(base)
	var selected: Dictionary = {}
	for item: Dictionary in inventory.get("inventory", []):
		if item.editable: selected = item; break
	check("real source provides a stable editable component", not selected.is_empty())
	if selected.is_empty(): quit(1); return
	var edit := {"id": selected.id, "mass_kg": float(selected.mass_kg) * 1.0001, "source": "Test measurement fixture, 2026-10-19; software verification only"}
	var recipe := Parameters.defaults()
	recipe["mass_edits"] = [edit]
	var compiled := Compiler.compile(base, recipe)
	check("measured recipe compiles through the existing aircraft loader", compiled.ok)
	if not compiled.ok: printerr(compiled.errors); quit(1); return
	var legacy := Compiler.compile(base, Parameters.defaults())
	check("component delta changes actual total mass", absf(float(compiled.summary.mass_kg) - float(legacy.summary.mass_kg) - (float(edit.mass_kg) - float(selected.mass_kg))) < 1e-12)
	check("compilation leaves exact input data unchanged", JSON.stringify(base, "", true, true) == original)
	check("mass extension has a distinct evaluator identity", compiled.summary.compiler_version == Compiler.MEASURED_MASS_COMPILER_VERSION and legacy.summary.compiler_version == Compiler.COMPILER_VERSION)
	var empty := Parameters.defaults()
	empty["mass_edits"] = []
	check("empty extension preserves legacy normalized recipe and compiler", Parameters.validate(empty).values == Parameters.defaults() and Compiler.version_for_recipe(empty) == Compiler.COMPILER_VERSION)
	for key: String in ["scale", "weight_multiplier", "tank_capacity_multiplier"]:
		var mixed := recipe.duplicate(true)
		mixed[key] = 1.01
		check("measured masses refuse unqualified virtual " + key, not Compiler.compile(base, mixed).ok)
	var malformed := recipe.duplicate(true)
	malformed.mass_edits[0].position = [0, 0, 0]
	check("recipe cannot smuggle station edits", not Parameters.validate(malformed).ok)
	malformed = recipe.duplicate(true)
	malformed.mass_edits[0].mass_kg = NAN
	check("nonfinite measured mass is rejected before compilation", not Parameters.validate(malformed).ok)
	var integer_bytes := FileAccess.get_file_as_bytes(Catalog.entry("p51d-mustang-120").data)
	var integer_recipe := Parameters.defaults()
	integer_recipe["mass_edits"] = [{"id": "gear_main_left", "mass_kg": 1, "source": "Integer/float identity fixture; not a physical measurement"}]
	var float_recipe := integer_recipe.duplicate(true)
	float_recipe.mass_edits[0].mass_kg = 1.0
	var integer_trial := Trial.freeze({"base_id": "p51d-mustang-120", "base_bytes": integer_bytes, "recipe": integer_recipe})
	var float_trial := Trial.freeze({"base_id": "p51d-mustang-120", "base_bytes": integer_bytes, "recipe": float_recipe})
	check("nested integer and float masses freeze the same exact identity", integer_trial.ok and float_trial.ok and integer_trial.identity == float_trial.identity and integer_trial.raw_bytes == float_trial.raw_bytes)
	var ordered := integer_recipe.duplicate(true)
	ordered.mass_edits.append({"id": "gear_main_right", "mass_kg": 1, "source": "Integer/float identity fixture; not a physical measurement"})
	var reversed := ordered.duplicate(true)
	reversed.mass_edits.reverse()
	check("independent component edits have stable canonical order", Parameters.validate(ordered).values == Parameters.validate(reversed).values)
	var frozen := Trial.freeze({"base_id": Catalog.DEFAULT_ID, "base_bytes": bytes, "recipe": recipe})
	var frozen_legacy := Trial.freeze({"base_id": Catalog.DEFAULT_ID, "base_bytes": bytes, "recipe": {}})
	check("trial freezes the measured evaluator without changing the legacy identity", frozen.ok and frozen_legacy.ok and frozen.identity.compiler == Compiler.MEASURED_MASS_COMPILER_VERSION and frozen.identity != frozen_legacy.identity)
	var field := Field.load_from()
	check("measurement trial has a real field fixture", field.ok)
	if field.ok and frozen.ok:
		for start: String in ["airborne", "runway"]:
			var qualified := Qualification.qualify(frozen, field.field, Weather.defaults(), start)
			check("measured candidate qualifies the actual " + start + " session", qualified.ok and qualified.available)
		var tape: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../research/aircraft-editor/examples/glide.json"))
		var flight := Experiments.run_fixed_tape(frozen, tape)
		check("measured candidate completes a bounded fixed-tick software flight", flight.ok and int(flight.result.termination.actual_ticks) == 60 and flight.result.trial_identity.compiler == Compiler.MEASURED_MASS_COMPILER_VERSION)
	var root_path := "user://test_workshop_mass_recipe_%d" % Time.get_ticks_usec()
	var integer_saved := Store.save_variant("Integer fixture", "p51d-mustang-120", integer_bytes, integer_recipe, "", root_path)
	check("direct integer-mass save reads back its new revision successfully", integer_saved.ok and integer_saved.variant.revision == 1 and not integer_saved.variant.get("recovered_from_manifest_backup", false))
	if integer_saved.ok:
		var integer_updated := Store.save_variant("Integer fixture", "p51d-mustang-120", integer_bytes, integer_recipe, integer_saved.variant.id, root_path, integer_saved.variant.workshop_descriptor, integer_saved.variant.dependencies, 1, integer_saved.variant.presentation_profile)
		check("integer-mass update cannot silently return the previous revision", integer_updated.ok and integer_updated.variant.revision == 2 and not integer_updated.variant.get("recovered_from_manifest_backup", false))
	var invalid_recipe := recipe.duplicate(true)
	invalid_recipe.mass_edits[0].id = "missing_inventory_id"
	var before_invalid := Store.list_variants(root_path).size()
	check("direct Store calls reject unknown component IDs without publishing", not Store.save_variant("Invalid measurement", Catalog.DEFAULT_ID, bytes, invalid_recipe, "", root_path).ok and Store.list_variants(root_path).size() == before_invalid)
	invalid_recipe = recipe.duplicate(true)
	invalid_recipe.scale = 1.01
	check("direct Store calls reject unqualified mixed measured recipes", not Store.save_variant("Invalid combination", Catalog.DEFAULT_ID, bytes, invalid_recipe, "", root_path).ok and Store.list_variants(root_path).size() == before_invalid)
	var saved := Store.save_variant("Measured fixture", Catalog.DEFAULT_ID, bytes, recipe, "", root_path)
	check("save pins the measured compiler", saved.ok and saved.variant.compiler_version == Compiler.MEASURED_MASS_COMPILER_VERSION)
	if not saved.ok: printerr(saved.errors)
	if saved.ok:
		var loaded := Store.load_variant(saved.variant.id, root_path)
		check("immutable record round trips measured recipe", loaded.ok and loaded.variant.recipe.mass_edits == recipe.mass_edits)
		var portable := Bundle.export_variant(loaded.variant)
		var imported := Bundle.import_variant(portable.bytes, root_path) if portable.ok else {"ok": false}
		check("portable import preserves measured identity under a new UUID", portable.ok and imported.ok and imported.variant.id != saved.variant.id and imported.variant.compiler_version == Compiler.MEASURED_MASS_COMPILER_VERSION)
		if portable.ok:
			var invalid_bundle: Dictionary = JSON.parse_string(portable.bytes.get_string_from_utf8())
			invalid_bundle.recipe.mass_edits[0].id = "missing_inventory_id"
			invalid_bundle.recipe_sha256 = Store._sha256(JSON.stringify(invalid_bundle.recipe, "", true, true).to_utf8_buffer())
			var count_before := Store.list_variants(root_path).size()
			var invalid_import := Bundle.import_variant(JSON.stringify(invalid_bundle, "", true, true).to_utf8_buffer(), root_path)
			check("import rejects unknown component IDs before publishing a library record", not invalid_import.ok and Store.list_variants(root_path).size() == count_before)
		var updated := recipe.duplicate(true)
		updated.control_multiplier = 1.05
		var update := Store.save_variant("Measured fixture", Catalog.DEFAULT_ID, bytes, updated, saved.variant.id, root_path, saved.variant.workshop_descriptor, saved.variant.dependencies, 1, saved.variant.presentation_profile)
		check("same evaluator can publish a new measured revision", update.ok and update.variant.revision == 2)
	var stock := Store.save_variant("Legacy fixture", Catalog.DEFAULT_ID, bytes, Parameters.defaults(), "", root_path)
	check("new legacy records still use compiler-2", stock.ok and stock.variant.compiler_version == Compiler.COMPILER_VERSION)
	if stock.ok:
		var refused := Store.save_variant("Legacy fixture", Catalog.DEFAULT_ID, bytes, recipe, stock.variant.id, root_path, stock.variant.workshop_descriptor, stock.variant.dependencies, 1, stock.variant.presentation_profile)
		var retained := Store.load_variant(stock.variant.id, root_path)
		check("adding a new evaluator requires Save a copy and leaves old revision intact", not refused.ok and retained.ok and retained.variant.revision == 1 and retained.variant.compiler_version == Compiler.COMPILER_VERSION and not retained.variant.recipe.has("mass_edits"))
	var report := Experiments.static_report(base, recipe)
	check("bounded reports retain measured compiler identity", report.ok and report.compiler_version == Compiler.MEASURED_MASS_COMPILER_VERSION and report.recipe.mass_edits == recipe.mass_edits)
	if not report.ok: printerr(report.errors)
	var editor := Workshop.new()
	editor.variants_root = root_path
	root.add_child(editor)
	await process_frame
	editor.set_variant_name("Original UI fixture")
	editor.save_named_variant()
	var original_id: String = editor.get("_saved_variant_id")
	var prior_visual: Dictionary = editor.get_presentation()
	editor.call("_show_mass_editor")
	check("measurement dialog initially focuses Cancel", editor.get("_mass_dialog").visible and editor.get("_mass_dialog").gui_get_focus_owner() == editor.get("_mass_dialog").get_cancel_button())
	var history: int = editor.get("_undo_history").size()
	editor.call("_apply_measured_recipe", recipe)
	check("applying measurements creates one history entry and detached new draft", editor.get_recipe().mass_edits == recipe.mass_edits and editor.get("_saved_variant_id").is_empty() and editor.get("_saved_variant_revision") == 0 and editor.get("_undo_history").size() == history + 1 and editor.get_presentation() == prior_visual)
	check("original named record retains exact legacy recipe", Store.load_variant(original_id, root_path).variant.recipe == Parameters.defaults())
	editor.call("_undo")
	check("measurement Undo restores the complete prior physical recipe", editor.get_recipe() == Parameters.defaults())
	editor.call("_redo")
	check("measurement Redo restores the full measured payload", editor.get_recipe() == recipe)
	editor.call("_show_mass_editor")
	var later_recipe := recipe.duplicate(true)
	later_recipe.control_multiplier = 1.05
	editor.set_recipe(later_recipe)
	editor.call("_apply_measured_recipe", recipe)
	check("stale measurement review cannot overwrite later draft edits", editor.get_recipe() == later_recipe and editor.get("_status_label").text.contains("draft changed"))
	check("Back consumes the measurement modal before the draft loss guard", editor.call("dismiss_modal_for_exit") and not editor.get("_mass_dialog").visible and not is_instance_valid(editor.get("_guard_dialog")))
	editor.save_named_variant()
	var measured_id: String = editor.get("_saved_variant_id")
	editor.call("_show_mass_editor")
	editor.call("_apply_measured_recipe", recipe)
	check("explicit new-build action also preserves an already measured saved record", not measured_id.is_empty() and editor.get("_saved_variant_id").is_empty() and Store.load_variant(measured_id, root_path).variant.recipe == later_recipe)
	var payloads: Array[Dictionary] = []
	editor.trial_requested.connect(func(payload: Dictionary) -> void: payloads.append(payload))
	editor.call("_request_trial")
	var prepared := Trial.freeze(payloads[0]) if payloads.size() == 1 else {"ok": false}
	check("actual Workshop trial payload freezes measured evaluator with detached ancestry", payloads.size() == 1 and prepared.ok and prepared.identity.compiler == Compiler.MEASURED_MASS_COMPILER_VERSION and prepared.identity.ancestor_variant_id.is_empty())
	editor.free()
	await process_frame
	_remove_tree(ProjectSettings.globalize_path(root_path))
	print("Workshop mass recipe: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories(): _remove_tree(path.path_join(child))
	directory = null
	DirAccess.remove_absolute(path)
