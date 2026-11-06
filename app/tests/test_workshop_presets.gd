# AE-09d-R1 / A14 F10: presets must preserve authored data and unresolved input.
extends SceneTree

const Workshop := preload("res://ui/workshop.gd")
const Compiler := preload("res://workshop/compiler.gd")
const MassEdit := preload("res://workshop/mass_edit.gd")
const Store := preload("res://workshop/store.gd")
const Trial := preload("res://workshop/trial.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var checks := 0
var failures := 0
var editor: Variant
var ui: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed: failures += 1

func select_preset(id: String) -> void:
	var selector: OptionButton = editor.get("_preset_selector")
	for index in selector.item_count:
		if selector.get_item_metadata(index) == id:
			selector.select(index)
			selector.item_selected.emit(index)
			return

func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	ui = UiDriver.new(self)
	editor = Workshop.new()
	editor.variants_root = "user://test_workshop_presets_%d" % Time.get_ticks_usec()
	root.add_child(editor)
	await ui.settle()
	editor.call("_set_page", "setup")
	var base: Dictionary = editor.get("_base")
	var inventory: Dictionary = MassEdit.inspect(base)
	var measured: Dictionary = Compiler.defaults()
	measured.mass_edits = []
	for item: Dictionary in inventory.get("inventory", []):
		if item.editable:
			measured.mass_edits.append({"id": item.id, "mass_kg": float(item.mass_kg) * 1.0001,
				"source": "Synthetic preset regression fixture; not physical evidence"})
			if measured.mass_edits.size() == 2: break
	check("fixture has two compatible measured components", measured.mass_edits.size() == 2 and Compiler.compile(base, measured).ok)
	if measured.mass_edits.size() != 2: editor.free(); quit(1); return
	measured.control_multiplier_aileron = 1.31
	editor.set_recipe(measured, false)
	measured = editor.get_recipe()
	editor.call("_clear_history")
	var presentation: Dictionary = editor.get_presentation()
	select_preset("fast")
	var accepted: Dictionary = editor.get_recipe()
	check("More power retains exact measurements and provenance", accepted.get("mass_edits", []) == measured.mass_edits)
	check("More power retains explicit individual control travel", accepted.get("control_multiplier_aileron", 0.0) == 1.31)
	check("preset applies its supported declared control change", accepted.control_multiplier == 1.15 and editor.get_compiled().ok)
	check("unchanged scale preserves legacy size identity", not accepted.has("size_model"))
	check("preset preserves presentation and records one Undo", editor.get_presentation() == presentation and editor.get("_undo_history").size() == 1)
	editor.call("_undo")
	check("one Undo restores the complete measured recipe", editor.get_recipe() == measured)
	editor.call("_redo")
	check("one Redo restores the reviewed preset recipe", editor.get_recipe() == accepted)
	select_preset("fast")
	check("repeating the same preset creates no history entry", editor.get("_undo_history").size() == 1)
	editor.call("_undo")
	var redo_before: Array = editor.get("_redo_history").duplicate(true)
	var compiled_before: Dictionary = editor.get_compiled()
	select_preset("mini")
	check("refused preset preserves compiled values, presentation and Redo", editor.get_compiled() == compiled_before and editor.get_presentation() == presentation and editor.get("_redo_history") == redo_before)
	editor.call("_redo")
	check("Redo remains usable after refusing a preset", editor.get_recipe() == accepted)
	var repairable: Dictionary = measured.duplicate(true)
	repairable.weight_multiplier = 1.2
	editor.set_recipe(repairable, false)
	check("fixture exposes an incompatible accepted recipe", not editor.get_compiled().ok)
	select_preset("fast")
	check("compatible preset can repair a compiler-invalid recipe without removing measurements", editor.get_compiled().ok and editor.get_recipe() == accepted)

	# Both measurement-incompatible size and weight changes must fail atomically.
	for id: String in ["mini", "light", "heavy", "agile", "slow", "giant"]:
		editor.set_recipe(measured, false)
		editor.call("_clear_history")
		select_preset(id)
		check(id + " refuses an incompatible measured recipe without data loss", editor.get_recipe() == measured and editor.get_compiled().ok)
		check(id + " refusal leaves no history and no applied preset label", editor.get("_undo_history").is_empty() and editor.get("_preset_selector").selected == 0)
		check(id + " refusal explains the preserved measurement constraint", str(editor.get("_status_label").text).contains("measured components require"))

	# Tank capacity and explicit surface values are outside every starting preset.
	var custom: Dictionary = Compiler.defaults()
	custom.tank_capacity_multiplier = 1.23
	custom.control_multiplier_aileron = 1.31
	for id: String in Workshop.PRESETS:
		editor.set_recipe(custom, false)
		editor.call("_clear_history")
		select_preset(id)
		var recipe: Dictionary = editor.get_recipe()
		check(id + " preserves unrelated tank capacity and individual travel", recipe.tank_capacity_multiplier == 1.23 and recipe.get("control_multiplier_aileron", 0.0) == 1.31)
		check(id + " accepts a compatible patch as one Undo", editor.get_compiled().ok and editor.get("_undo_history").size() == 1)
		check(id + " changes size identity only when scale changes", recipe.has("size_model") == (id in ["mini", "giant"]))
		editor.call("_undo")
		check(id + " Undo restores all authored values", editor.get_recipe() == custom)

	var payloads: Array[Dictionary] = []
	editor.trial_requested.connect(func(payload: Dictionary) -> void: payloads.append(payload))
	var weight: LineEdit = editor.get("_factor_inputs").weight_multiplier
	for raw: String in ["bad", "", "999", "0.731"]:
		editor.set_recipe(Compiler.defaults(), false)
		editor.call("_clear_history")
		weight.text = raw
		weight.text_changed.emit(raw)
		var before: Dictionary = editor.get_recipe()
		var pending: Dictionary = editor.get("_pending_numbers").duplicate(true)
		var invalid: Dictionary = editor.get("_invalid_fields").duplicate(true)
		select_preset("fast")
		check("pending '%s' survives preset unchanged" % raw, weight.text == raw and editor.get_recipe() == before and editor.get("_pending_numbers") == pending and editor.get("_invalid_fields") == invalid)
		check("pending '%s' refusal is focusable and undo-neutral" % raw, root.gui_get_focus_owner() == weight and editor.get("_undo_history").is_empty() and editor.get("_preset_selector").selected == 0)
		if raw != "0.731":
			check("invalid '%s' keeps Save and Test fly blocked" % raw, editor.save_button.disabled and editor.get("_trial_button").disabled and not editor.call("_save_variant"))
			editor.call("_request_trial")
			check("invalid '%s' emits no trial payload" % raw, payloads.is_empty())
		# Explicit cancellation, rather than a preset, removes unresolved input.
		weight.grab_focus()
		if editor.get("_pending_numbers").has("weight_multiplier"):
			editor.call("_request_close")
		check("explicit Back cancels only the numeric buffer", weight.text == String.num(float(before.weight_multiplier), 4) and editor.get("_pending_numbers").is_empty())
		editor.set("_trial_pending", false)
		payloads.clear()

	# A hidden advanced field must become visible before issue focus is restored.
	var advanced: LineEdit = editor.get("_factor_inputs").control_multiplier_aileron
	advanced.text = "bad"
	advanced.text_changed.emit(advanced.text)
	editor.get("_advanced_controls_toggle").button_pressed = false
	select_preset("fast")
	check("preset refusal reveals a hidden invalid surface field", advanced.is_visible_in_tree() and root.gui_get_focus_owner() == advanced and advanced.text == "bad")
	editor.call("_request_close")

	editor.call("_set_page", "appearance")
	var appearance: Control = editor.get("_page_nodes").appearance
	var inscription: LineEdit = appearance.get("_marking_text")
	inscription.text = "Bad@"
	inscription.text_changed.emit(inscription.text)
	var before_visual: Dictionary = editor.get_recipe()
	select_preset("fast")
	check("preset preserves unresolved presentation text and accepted recipe", inscription.text == "Bad@" and editor.get_recipe() == before_visual and editor.get("_presentation_buffers").has("appearance"))
	check("presentation refusal returns focus to the pending field", root.gui_get_focus_owner() == inscription and editor.get("_trial_button").disabled)
	appearance.call("cancel_pending_edit")

	# Exercise focus loss and real keyboard activation of the preset popup.
	editor.call("_set_page", "setup")
	editor.set_recipe(Compiler.defaults(), false)
	weight.grab_focus()
	weight.text = "bad"
	weight.text_changed.emit(weight.text)
	var selector: OptionButton = editor.get("_preset_selector")
	selector.select(0)
	selector.grab_focus()
	await ui.settle()
	check("invalid text survives leaving the field for the preset selector", weight.text == "bad" and editor.get("_pending_numbers").has("weight_multiplier"))
	await ui.tap(KEY_SPACE)
	await ui.tap(KEY_HOME)
	for unused in 5: await ui.tap(KEY_DOWN)
	await ui.tap(KEY_ENTER)
	check("keyboard preset selection refuses invalid text and restores field focus", not selector.get_popup().visible and weight.text == "bad" and root.gui_get_focus_owner() == weight and editor.get_recipe() == Compiler.defaults())
	# Explicit correction retains the existing submit/focus-loss commit semantics.
	weight.text = "0.731"
	weight.text_changed.emit(weight.text)
	await ui.tap(KEY_ENTER)
	check("keyboard correction commits the exact accepted value", editor.get_recipe().weight_multiplier == 0.731 and editor.get("_pending_numbers").is_empty())
	select_preset("fast")
	check("resolved numeric edit permits a later preset", editor.get_recipe().control_multiplier == 1.15 and editor.get_compiled().ok)

	# Save, reload and the real frozen trial consume precisely the accepted recipe.
	editor.set_recipe(measured, false)
	select_preset("fast")
	accepted = editor.get_recipe()
	editor.get("_variant_name").text = "Scoped preset fixture"
	var saved: bool = editor.call("_save_variant")
	check("reviewed measured preset saves", saved)
	if saved:
		var loaded: Dictionary = Store.load_variant(editor.get("_saved_variant_id"), editor.variants_root)
		check("stored recipe retains measurements and every reviewed value", loaded.ok and loaded.variant.recipe == accepted)
		editor.call("_load_variant_snapshot", loaded.variant.id)
		check("editor reload retains the accepted recipe", editor.get_recipe() == accepted)
	editor.call("_request_trial")
	var frozen: Dictionary = Trial.freeze(payloads[0]) if payloads.size() == 1 else {"ok": false}
	check("Test fly consumes the exact reviewed measured recipe", payloads.size() == 1 and payloads[0].recipe == accepted and frozen.ok and frozen.identity.compiler == Compiler.SURFACE_CONTROLS_COMPILER_VERSION)
	var fixture_root := ProjectSettings.globalize_path(str(editor.variants_root))
	editor.free()
	await process_frame
	_remove_fixture(fixture_root)
	print("Workshop presets: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _remove_fixture(path: String) -> void:
	assert(path.begins_with(ProjectSettings.globalize_path("user://test_workshop_presets_")))
	var directory := DirAccess.open(path)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories(): _remove_fixture(path.path_join(child))
	DirAccess.remove_absolute(path)
