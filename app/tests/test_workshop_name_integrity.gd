# AE-09d-R2 / A14 F11: valid stored names survive every editor persistence path.
extends SceneTree

const Workshop := preload("res://ui/workshop.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Store := preload("res://workshop/store.gd")
const Bundle := preload("res://workshop/bundle.gd")
const DraftStore := preload("res://workshop/draft_store.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var checks := 0
var failures := 0
var ui: RefCounted
var scratch := ""
var source_bytes := PackedByteArray()

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed: failures += 1

func make_editor(library: String, recovery: String) -> Variant:
	var editor := Workshop.new()
	editor.variants_root = library
	editor.recovery_root = recovery
	editor.recovery_enabled = true
	root.add_child(editor)
	return editor

func window_key(window: Window, code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		window.push_input(event)
	await ui.settle()

func _run() -> void:
	TranslationServer.set_locale("en")
	InputMap.load_from_project_settings()
	root.size = Vector2i(1920, 1080)
	ui = UiDriver.new(self)
	scratch = "user://test_workshop_names_%d" % Time.get_ticks_usec()
	source_bytes = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	for length: int in [64, 65, 80, 96]:
		await exercise_name("Build-" + "A".repeat(length - 6), str(length))
	await exercise_name("Ñ航空🙂".repeat(24), "unicode96")
	await exercise_name("é".repeat(48), "combining96")
	_remove_fixture(ProjectSettings.globalize_path(scratch))
	print("Workshop name integrity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func exercise_name(full_name: String, label: String) -> void:
	var library := scratch.path_join(label).path_join("library")
	var recovery := scratch.path_join(label).path_join("recovery")
	var original := Store.save_variant(full_name, Catalog.DEFAULT_ID, source_bytes, Compiler.defaults(), "", library)
	check(label + " source name is valid in the existing format", original.ok)
	if not original.ok: return
	var exported := Bundle.export_variant(original.variant)
	var imported := Bundle.import_variant(exported.bytes, library) if exported.ok else {"ok": false}
	check(label + " portable import retains the full name under a new identity", imported.ok and imported.variant.name == full_name and imported.variant.id != original.variant.id)
	if not imported.ok: return
	var id: String = imported.variant.id
	var editor: Variant = make_editor(library, recovery)
	await ui.settle()
	editor.call("_load_variant_snapshot", id)
	check(label + " opening a saved build preserves the complete name", editor.get("_variant_name").text == full_name)
	check(label + " clean baseline retains the source identity", not editor.has_unsaved_changes() and editor.call("_draft_payload").name == full_name)
	editor.set_recipe({"control_multiplier": 1.10})
	check(label + " unrelated edit saves successfully", editor.call("_save_variant"))
	var revised := Store.load_variant(id, library)
	check(label + " unrelated save preserves name in revision two", revised.ok and revised.variant.revision == 2 and revised.variant.name == full_name and revised.variant.recipe.control_multiplier == 1.10)
	editor.call("_load_variant_snapshot", id)
	check(label + " reload preserves the full name and clean state", editor.get("_variant_name").text == full_name and not editor.has_unsaved_changes())
	var revised_export := Bundle.export_variant(revised.variant)
	var decoded: Dictionary = JSON.parse_string(revised_export.bytes.get_string_from_utf8()) if revised_export.ok else {}
	check(label + " re-export preserves the full accepted name", decoded.get("name", "") == full_name)
	check(label + " original record remains unchanged", Store.load_variant(original.variant.id, library).variant.name == full_name and Store.load_variant(original.variant.id, library).variant.revision == 1)

	# The navigation guard has its own name field and must share the same contract.
	editor.set_recipe({"control_multiplier": 1.20})
	var navigation := {"continued": 0}
	editor.request_navigation("Back to Home", func() -> void: navigation.continued += 1)
	var guard: ConfirmationDialog = editor.get("_guard_dialog")
	var guard_name: LineEdit = editor.get("_guard_name")
	check(label + " Save and continue displays the full existing name", guard.visible and guard_name.text == full_name)
	guard_name.grab_focus()
	await window_key(guard, KEY_ENTER)
	var after_guard := Store.load_variant(id, library)
	check(label + " keyboard Save and continue preserves name in revision three", navigation.continued == 1 and after_guard.ok and after_guard.variant.revision == 3 and after_guard.variant.name == full_name)
	editor.set_recipe({"control_multiplier": 1.23})
	editor.request_navigation("Back to Home", func() -> void: navigation.continued += 1)
	guard = editor.get("_guard_dialog")
	guard_name = editor.get("_guard_name")
	guard_name.text = "Cancelled-" + "Z".repeat(86)
	await window_key(guard, KEY_ESCAPE)
	check(label + " cancelling a guard rename preserves full editor name and revision", navigation.continued == 1 and editor.get("_variant_name").text == full_name and Store.load_variant(id, library).variant.name == full_name and Store.load_variant(id, library).variant.revision == 3)

	# Wait for the real debounce; do not substitute a direct snapshot write.
	editor.call("_set_page", "setup")
	editor.set_recipe({"control_multiplier": 1.25})
	var number: LineEdit = editor.get("_factor_inputs").power_multiplier
	number.text = "invalid"
	number.text_changed.emit(number.text)
	await create_timer(1.0).timeout
	var snapshot := DraftStore.load_snapshot(recovery)
	check(label + " completed recovery snapshot contains the full name", snapshot.ok and snapshot.exists and snapshot.editor.name == full_name and snapshot.payload.name == full_name)
	check(label + " recovery retains unrelated pending text", snapshot.ok and snapshot.exists and snapshot.editor.numeric_buffers.get("power_multiplier", "") == "invalid")
	if not snapshot.ok or not snapshot.exists:
		editor.free()
		await ui.settle()
		return
	var state: Dictionary = snapshot.editor.duplicate(true)
	state.name = "B".repeat(97)
	check(label + " recovery rejects an over-limit name without replacing its snapshot", not DraftStore.validate_editor_state(state).ok and not DraftStore.save_snapshot(recovery, editor.call("_draft_payload"), state, "", snapshot.digest).ok and DraftStore.load_snapshot(recovery).digest == snapshot.digest)
	# Draft text is intentionally less restrictive than a published record name.
	for raw: String in ["", "  Unsaved name  "]:
		state.name = raw
		var raw_checked := DraftStore.validate_editor_state(state)
		check(label + " raw editor name remains recoverable: '" + raw + "'", raw_checked.ok and raw_checked.editor.name == raw)
	editor.free()
	await ui.settle()
	editor = make_editor(library, recovery)
	await ui.settle()
	editor.call("_request_recovery_restore")
	check(label + " actual recovery restores the entire name without ancestry", editor.get("_variant_name").text == full_name and editor.get("_saved_variant_id").is_empty() and editor.has_unsaved_changes())
	check(label + " restored pending numeric input remains blocking", editor.get("_factor_inputs").power_multiplier.text == "invalid" and editor.get("_trial_button").disabled)
	number = editor.get("_factor_inputs").power_multiplier
	number.grab_focus()
	editor.call("_request_close")
	check(label + " recovered build saves as a new copy", editor.call("_save_variant"))
	var copy_id: String = editor.get("_saved_variant_id")
	var copy := Store.load_variant(copy_id, library) if not copy_id.is_empty() else {"ok": false}
	check(label + " recovered copy keeps the complete name", copy.ok and copy_id != id and copy.variant.name == full_name and copy.variant.recipe.control_multiplier == 1.25)
	var copy_export := Bundle.export_variant(copy.variant) if copy.ok else {"ok": false}
	var copy_json: Dictionary = JSON.parse_string(copy_export.bytes.get_string_from_utf8()) if copy_export.ok else {}
	check(label + " export after recovery retains the full name", copy_json.get("name", "") == full_name)
	check(label + " recovering a copy preserves the original imported revision", Store.load_variant(id, library).variant.name == full_name and Store.load_variant(id, library).variant.revision == 3)

	var count_before := Store.list_variants(library).size()
	check(label + " store refuses 97 characters without publication", not Store.save_variant("B".repeat(97), Catalog.DEFAULT_ID, source_bytes, Compiler.defaults(), "", library).ok and Store.list_variants(library).size() == count_before)
	decoded.name = "B".repeat(97)
	check(label + " bundle refuses 97 characters without publication", not Bundle.import_variant(JSON.stringify(decoded).to_utf8_buffer(), library).ok and Store.list_variants(library).size() == count_before)
	if full_name.length() == 96:
		state.name = full_name + "Q"
		decoded.name = state.name
		check(label + " one extra character rejects consistently across all data boundaries", not Store.save_variant(state.name, Catalog.DEFAULT_ID, source_bytes, Compiler.defaults(), "", library).ok and not Bundle.import_variant(JSON.stringify(decoded).to_utf8_buffer(), library).ok and not DraftStore.validate_editor_state(state).ok and Store.list_variants(library).size() == count_before)
	editor.free()
	await ui.settle()

func _remove_fixture(path: String) -> void:
	assert(path.begins_with(ProjectSettings.globalize_path("user://test_workshop_names_")))
	var directory := DirAccess.open(path)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories(): _remove_fixture(path.path_join(child))
	DirAccess.remove_absolute(path)
