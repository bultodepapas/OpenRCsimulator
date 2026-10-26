extends SceneTree
## AE-09d: named-build saves use the real dialog-window Enter/Cancel routes.

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Store := preload("res://workshop/store.gd")
const Workshop := preload("res://ui/workshop.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var _checks := 0
var _failures := 0
var _ui: RefCounted
var _variants_root := ""


func _initialize() -> void:
	_ui = UiDriver.new(self)
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _find(node: Node, child_name: String) -> Node:
	return node.find_child(child_name, true, false) if node != null else null


## Inject a real key into the modal Window; Input.parse_input_event can miss embedded subwindows.
func _window_key(window: Window, code: Key) -> void:
	if not is_instance_valid(window): return
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		window.push_input(event)
	await _ui.settle()


func _run() -> void:
	TranslationServer.set_locale("en")
	InputMap.load_from_project_settings()
	root.size = Vector2i(1920, 1080)
	_variants_root = "user://test_workshop_document_flow_%d" % Time.get_ticks_usec()
	var workshop: Variant = Workshop.new()
	workshop.initial_aircraft_id = Catalog.DEFAULT_ID
	workshop.variants_root = _variants_root
	workshop.recovery_enabled = false
	root.add_child(workshop)
	await _ui.settle()

	var name_field := workshop.get("_variant_name") as LineEdit
	var name_dialog := workshop.get("_name_dialog") as ConfirmationDialog
	var library := workshop.get("_library_dialog") as AcceptDialog
	_check("delete confirmation names its destructive action", workshop.get("_delete_dialog").get_ok_button().text == "Delete")

	var empty_state := workshop.find_child("SavedBuildEmptyState", true, false) as Label
	_check("empty library explains how to create its first saved build",
		is_instance_valid(empty_state) and empty_state.visible
		and empty_state.text.contains("No saved builds yet")
		and workshop.get("_variant_selector").disabled)

	# First save: the Workshop opens the name dialog and Enter on its Window publishes once.
	workshop.call("_request_save")
	await _ui.settle()
	_check("first Save opens the name dialog", name_dialog != null and name_dialog.visible
		and name_field != null and name_dialog.is_ancestor_of(name_field))
	name_field.text = "First saved build"
	name_field.grab_focus()
	await _window_key(name_dialog, KEY_ENTER)
	var first_rows: Array = Store.list_variants(_variants_root)
	var first_id := str(workshop.get("_saved_variant_id"))
	var first_result: Dictionary = Store.load_variant(first_id, _variants_root) if not first_id.is_empty() else {}
	var first_enter_succeeded: bool = first_rows.size() == 1 and first_id.length() == 36 \
		and first_result.get("ok", false) and int(first_result.variant.revision) == 1 \
		and str(first_result.variant.name) == "First saved build"
	_check("real Enter creates exactly one UUID at revision one", first_enter_succeeded,
		"rows=%d id=%s result=%s" % [first_rows.size(), first_id, str(first_result.get("errors", []))])
	# Keep later checks independent if a runner does not route key input to this Window.
	if first_id.is_empty() and is_instance_valid(name_dialog):
		name_dialog.confirmed.emit()
		await _ui.settle()
	first_id = str(workshop.get("_saved_variant_id"))
	first_result = Store.load_variant(first_id, _variants_root) if not first_id.is_empty() else {}
	_check("first-save fallback leaves a readable revision-one fixture",
		first_result.get("ok", false) and int(first_result.variant.revision) == 1,
		str(first_result.get("errors", [])))

	# A normal update must retain the record UUID and advance its immutable revision.
	var updated_recipe: Dictionary = workshop.get_recipe()
	updated_recipe.power_multiplier = 1.08
	workshop.set_recipe(updated_recipe)
	workshop.call("_request_save")
	await _ui.settle()
	var updated := Store.load_variant(first_id, _variants_root)
	_check("updating a saved build keeps its UUID and creates revision two",
		updated.get("ok", false) and str(workshop.get("_saved_variant_id")) == first_id
		and int(workshop.get("_saved_variant_revision")) == 2
		and int(updated.variant.revision) == 2
		and is_equal_approx(float(updated.variant.recipe.power_multiplier), 1.08),
		str(updated.get("errors", [])))

	# Save a copy changes storage identity while leaving the source revision untouched.
	workshop.call("_request_copy")
	await _ui.settle()
	_check("Save a copy labels the dialog and its primary action consistently",
		name_dialog.visible and name_dialog.title == "Save a copy"
		and name_dialog.get_ok_button().text == "Save a copy",
		"title=%s button=%s" % [name_dialog.title, name_dialog.get_ok_button().text])
	var copy_name := "Copied build"
	name_field.text = copy_name
	name_field.grab_focus()
	await _window_key(name_dialog, KEY_ENTER)
	var copy_id := str(workshop.get("_saved_variant_id"))
	var copy_result: Dictionary = Store.load_variant(copy_id, _variants_root) if not copy_id.is_empty() else {}
	var copy_enter_succeeded: bool = not copy_id.is_empty() and copy_id != first_id \
		and copy_result.get("ok", false) and int(copy_result.variant.revision) == 1
	_check("real Enter saves a separate first revision", copy_enter_succeeded,
		"copy_id=%s result=%s" % [copy_id, str(copy_result.get("errors", []))])
	if copy_id == first_id and is_instance_valid(name_dialog):
		name_dialog.confirmed.emit()
		await _ui.settle()
	copy_id = str(workshop.get("_saved_variant_id"))
	copy_result = Store.load_variant(copy_id, _variants_root) if not copy_id.is_empty() else {}
	var source_after_copy := Store.load_variant(first_id, _variants_root)
	_check("copy leaves the original UUID and revision two intact",
		copy_id != first_id and copy_result.get("ok", false)
		and source_after_copy.get("ok", false) and int(source_after_copy.variant.revision) == 2
		and str(source_after_copy.variant.name) == "First saved build",
		"copy=%s source=%s" % [str(copy_result.get("errors", [])), str(source_after_copy.get("errors", []))])

	# Search feedback and operation failures remain readable inside the library.
	workshop.call("_open_library")
	var search: LineEdit = workshop.get("_build_search")
	search.text = "no matching build 627"
	search.text_changed.emit(search.text)
	_check("unmatched search has distinct empty feedback and disables loading",
		is_instance_valid(empty_state) and empty_state.visible
		and empty_state.text.contains("match these filters")
		and workshop.get("_load_button").disabled)
	workshop.set_note("The selected build could not be changed. " + "Detailed diagnostic. ".repeat(80))
	await _ui.settle()
	var feedback: Label = workshop.get("_library_note")
	var before_scroll := feedback.get_global_rect()
	var library_scroll := workshop.find_child("LibraryScroll", true, false) as ScrollContainer
	library_scroll.scroll_vertical = 10000
	await _ui.settle()
	_check("long library feedback stays in view while the library scrolls",
		feedback.is_visible_in_tree() and feedback.get_global_rect() == before_scroll
		and Rect2(Vector2.ZERO, Vector2(library.size)).encloses(feedback.get_global_rect())
		and feedback.tooltip_text == feedback.text)
	search.text = ""
	search.text_changed.emit(search.text)
	workshop.set_note("")
	var rename_button := workshop.find_child("RenameBuild", true, false) as Button
	rename_button.grab_focus()

	# Cancelling rename restores its prior draft name and does not publish a revision.
	var name_before_rename := name_field.text
	workshop.call("_show_name_dialog", false)
	await _ui.settle()
	name_field.text = "Cancelled rename"
	var rename_dialog: ConfirmationDialog = workshop.get("_name_dialog")
	if rename_dialog != null:
		rename_dialog.get_cancel_button().grab_focus()
		await _window_key(rename_dialog, KEY_ENTER)
	var after_rename_cancel := Store.load_variant(copy_id, _variants_root) if not copy_id.is_empty() else {}
	var rename_cancel_succeeded: bool = name_field.text == name_before_rename \
		and str(workshop.get("_saved_variant_id")) == copy_id \
		and after_rename_cancel.get("ok", false) and int(after_rename_cancel.variant.revision) == 1
	_check("Cancel in the rename dialog restores its prior name without saving",
		rename_cancel_succeeded, "name=%s prior=%s" % [name_field.text, name_before_rename])
	_check("Cancel returns to the originating library and rename action",
		library.visible and not name_dialog.visible
		and library.gui_get_focus_owner() == rename_button)
	if library.visible: workshop.call("_close_library")
	if rename_dialog != null and rename_dialog.visible:
		rename_dialog.canceled.emit()
		await _ui.settle()

	# Save and continue uses the real Enter route and calls its captured continuation once.
	var navigation_recipe: Dictionary = workshop.get_recipe()
	navigation_recipe.power_multiplier = 1.12
	workshop.set_recipe(navigation_recipe)
	var navigation := {continued = 0, cancelled = 0}
	var proceed := func() -> void: navigation.continued += 1
	var cancel := func() -> void: navigation.cancelled += 1
	workshop.request_navigation("Back to Home", proceed, cancel)
	var nav_guard := workshop.get("_guard_dialog") as ConfirmationDialog
	var guard_name := workshop.get("_guard_name") as LineEdit
	_check("dirty navigation opens a named Save and continue decision",
		nav_guard != null and nav_guard.visible and guard_name != null)
	if guard_name != null:
		guard_name.text = "Navigation revision"
		guard_name.grab_focus()
	if nav_guard != null: await _window_key(nav_guard, KEY_ENTER)
	var navigation_enter_succeeded: bool = int(navigation.continued) == 1
	_check("real Enter completes the captured navigation once", navigation_enter_succeeded,
		"continued=%d" % int(navigation.continued))
	if int(navigation.continued) == 0 and is_instance_valid(nav_guard) and nav_guard.visible:
		nav_guard.confirmed.emit()
		await _ui.settle()
	var after_navigation := Store.load_variant(copy_id, _variants_root) if not copy_id.is_empty() else {}
	_check("Save and continue stores the current copy as revision two",
		int(navigation.continued) == 1 and int(navigation.cancelled) == 0
		and str(workshop.get("_saved_variant_id")) == copy_id
		and int(workshop.get("_saved_variant_revision")) == 2
		and after_navigation.get("ok", false) and int(after_navigation.variant.revision) == 2
		and str(after_navigation.variant.name) == "Navigation revision"
		and is_equal_approx(float(after_navigation.variant.recipe.power_multiplier), 1.12),
		str(after_navigation.get("errors", [])))

	# A competing writer advances the same UUID. Failed Save must preserve the local candidate;
	# Cancel must also discard the guard's proposed name, not the editor's existing name.
	var external_record: Dictionary = after_navigation.get("variant", {})
	var external_recipe: Dictionary = external_record.get("recipe", {}).duplicate(true)
	external_recipe.power_multiplier = 1.30
	var external := Store.save_variant(
		"Concurrent revision",
		str(external_record.get("base_id", "")),
		external_record.get("base_bytes", PackedByteArray()),
		external_recipe,
		copy_id,
		_variants_root,
		external_record.get("workshop_descriptor", {}),
		external_record.get("dependencies", {}),
		int(external_record.get("revision", 0)),
		external_record.get("presentation_profile", {})
	)
	_check("external writer fixture creates the stale-revision conflict",
		external.get("ok", false) and int(external.variant.revision) == 3,
		str(external.get("errors", [])))
	var local_recipe: Dictionary = workshop.get_recipe()
	local_recipe.power_multiplier = 1.17
	workshop.set_recipe(local_recipe)
	var original_name := name_field.text
	var stale_navigation := {continued = 0, cancelled = 0}
	var stale_proceed := func() -> void: stale_navigation.continued += 1
	var stale_cancel := func() -> void: stale_navigation.cancelled += 1
	workshop.request_navigation("Back to Home", stale_proceed, stale_cancel)
	var stale_guard := workshop.get("_guard_dialog") as ConfirmationDialog
	var stale_name := workshop.get("_guard_name") as LineEdit
	var stale_error := workshop.get("_guard_error") as Label
	if stale_name != null:
		stale_name.text = "Rejected guard name"
		stale_name.grab_focus()
	if stale_guard != null: await _window_key(stale_guard, KEY_ENTER)
	var stale_enter_reported_error: bool = stale_guard != null and stale_guard.visible \
		and stale_error != null and not stale_error.text.is_empty()
	_check("real Enter attempts the stale save and keeps the decision open",
		stale_enter_reported_error and int(stale_navigation.continued) == 0,
		"visible=%s error=%s" % [str(stale_guard.visible if stale_guard != null else false),
		str(stale_error.text if stale_error != null else "missing")])
	if not stale_enter_reported_error and is_instance_valid(stale_guard) and stale_guard.visible:
		stale_guard.confirmed.emit()
		await _ui.settle()
	var record_after_stale_failure := Store.load_variant(copy_id, _variants_root)
	_check("failed overwrite keeps the newer stored revision and local recipe",
		record_after_stale_failure.get("ok", false)
		and int(record_after_stale_failure.variant.revision) == 3
		and is_equal_approx(float(record_after_stale_failure.variant.recipe.power_multiplier), 1.30)
		and str(workshop.get("_saved_variant_id")) == copy_id
		and int(workshop.get("_saved_variant_revision")) == 2
		and workshop.get_recipe() == local_recipe and workshop.has_unsaved_changes(),
		str(record_after_stale_failure.get("errors", [])))
	if stale_guard != null and stale_guard.visible:
		stale_guard.get_cancel_button().grab_focus()
		await _window_key(stale_guard, KEY_ENTER)
	var stale_cancel_succeeded: bool = int(stale_navigation.continued) == 0 \
		and int(stale_navigation.cancelled) == 1 \
		and name_field.text == original_name and workshop.get_recipe() == local_recipe \
		and str(workshop.get("_saved_variant_id")) == copy_id \
		and int(workshop.get("_saved_variant_revision")) == 2
	_check("Cancel after failed stale Save restores the original name and full recipe",
		stale_cancel_succeeded,
		"name=%s prior=%s recipe_preserved=%s" % [name_field.text, original_name,
		str(workshop.get_recipe() == local_recipe)])
	if is_instance_valid(stale_guard) and stale_guard.visible:
		stale_guard.canceled.emit()
		await _ui.settle()

	if name_field.text != original_name:
		name_field.text = original_name
		workshop.call("_refresh_identity")

	# Close every fixture node before removing only this test's user:// store.
	if library != null and library.visible: workshop.call("_close_library")
	root.remove_child(workshop)
	workshop.free()
	await _ui.settle()
	_remove_tree(ProjectSettings.globalize_path(_variants_root))
	print("Workshop document flow: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty(): break
		if entry == "." or entry == "..": continue
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)
