extends SceneTree
const Workshop := preload("res://ui/workshop.gd")
const DraftStore := preload("res://workshop/draft_store.gd")
const Store := preload("res://workshop/store.gd")
const Compiler := preload("res://workshop/compiler.gd")
var failures := 0
var checks := 0
var scratch := ""
func _initialize() -> void: run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed: failures += 1
func make_editor(library_path: String = "", recovery_path: String = "") -> Node:
	var editor := Workshop.new()
	editor.variants_root = library_path if not library_path.is_empty() else scratch + "/library"
	editor.recovery_root = recovery_path if not recovery_path.is_empty() else scratch + "/recovery"
	editor.recovery_enabled = true
	root.add_child(editor)
	return editor
func settle() -> void:
	for tick in 5: await process_frame
func run() -> void:
	scratch = "user://test_workshop_recovery_ui_%d" % Time.get_ticks_usec()
	var first := make_editor()
	await settle()
	check("missing recovery does not create a record or interrupt editing", not first.get("_recovery_pending") and not DraftStore.load_snapshot(first.recovery_root).exists)
	first.set_recipe({"control_multiplier": 1.03})
	first.set_variant_name("Recover Ñ-27")
	first.get("_page_nodes").smoke.apply_preset(5)
	first.call("_set_page", "smoke")
	var color: LineEdit = first.get("_page_nodes").smoke.get("_custom_color")
	color.text = "#BAD"
	color.text_changed.emit(color.text)
	var number: LineEdit = first.get("_factor_inputs").power_multiplier
	number.text = "invalid"
	number.text_changed.emit(number.text)
	first.get("_preview").set_standard_view("side")
	var accepted: Dictionary = first.get_recipe()
	var visual: Dictionary = first.get_presentation()
	var camera: Dictionary = first.get("_preview").get_view_state()
	check("automatic recovery is bounded and debounced", first.get("_recovery_timer").one_shot and first.get("_recovery_timer").wait_time == 0.75)
	check("dirty invalid draft can be snapshotted independently of named saves", first.call("_autosave_draft"))
	var recovered := DraftStore.load_snapshot(first.recovery_root)
	check("snapshot stores accepted build separately from both raw text buffers", recovered.ok and recovered.compatible and recovered.payload.recipe == accepted and recovered.payload.presentation_profile == visual and recovered.editor.numeric_buffers.power_multiplier == "invalid" and recovered.editor.presentation_buffers.smoke.color_text == "#BAD")
	check("autosave does not publish library variants", Store.list_variants(first.variants_root).is_empty())
	first.free()
	await settle()
	var second := make_editor()
	await settle()
	var dialog: ConfirmationDialog = second.get("_recovery_dialog")
	check("reopening presents explicit recovery with Later initially focused", second.get("_recovery_pending") and dialog.visible and dialog.gui_get_focus_owner() == dialog.get_cancel_button())
	var before: Dictionary = second.get_recipe()
	var requests := [0]
	second.trial_requested.connect(func(_payload: Dictionary) -> void: requests[0] += 1)
	second.call("_request_trial")
	check("recovery review cannot accidentally start a trial", requests[0] == 0 and second.get_recipe() == before)
	second.call("dismiss_modal_for_exit")
	check("Later preserves stored recovery and restores normal editing actions", not dialog.visible and DraftStore.load_snapshot(second.recovery_root).exists and not second.get("_trial_button").disabled and second.get_recipe() == before)
	var clean_navigation := [false]
	second.request_navigation("Back to Home", func() -> void: clean_navigation[0] = true)
	check("clean navigation after Later preserves recovery awaiting a decision", clean_navigation[0]
		and DraftStore.load_snapshot(second.recovery_root).digest == recovered.digest)
	second.set_recipe({"control_multiplier": 1.1})
	check("editing after Later cannot overwrite the pending recovered draft", not second.call("_autosave_draft") and DraftStore.load_snapshot(second.recovery_root).payload.recipe == accepted)
	second.call("_show_recovery")
	second.call("_request_recovery_restore")
	check("restoring over another dirty draft requires its existing loss guard", is_instance_valid(second.get("_guard_dialog")) and second.get_recipe().control_multiplier == 1.1)
	second.call("_navigation_abort")
	check("Cancel during restore returns to a usable editor without altering recovery", not second.get("_trial_button").disabled and second.get_recipe().control_multiplier == 1.1 and DraftStore.load_snapshot(second.recovery_root).payload.recipe == accepted)
	second.set_recipe({})
	second.call("_show_recovery")
	second.call("_request_recovery_restore")
	check("restore preserves full accepted physical and presentation data", second.get_recipe() == accepted and second.get_presentation() == visual)
	check("restore retains invalid text, page, camera and blocked launch", second.get("_active_page") == "smoke" and second.get("_preview").get_view_state() == camera and second.get("_factor_inputs").power_multiplier.text == "invalid" and second.get("_page_nodes").smoke.get("_custom_color").text == "#BAD" and not second.call("_edit_valid"))
	check("recovery has detached ancestry and requires a new named save", second.get("_saved_variant_id").is_empty() and second.get("_saved_variant_revision") == 0 and second.has_unsaved_changes())
	second.get("_page_nodes").smoke.cancel_pending_edit()
	number = second.get("_factor_inputs").power_multiplier
	number.text = "1"
	number.text_changed.emit(number.text)
	check("correcting the restored buffers enables save and trial", second.call("_edit_valid"))
	second.save_named_variant()
	check("explicit named save succeeds", not second.get("_saved_variant_id").is_empty())
	check("saving clears recovery only after a complete named record exists", Store.list_variants(second.variants_root).size() == 1 and not DraftStore.load_snapshot(second.recovery_root).exists and not second.has_unsaved_changes())
	second.set_recipe({"control_multiplier": 1.04})
	check("a later edit creates a new recovery snapshot", second.call("_autosave_draft") and DraftStore.load_snapshot(second.recovery_root).exists)
	second.free()
	await settle()
	var third := make_editor()
	await settle()
	third.call("_discard_pending_recovery")
	check("explicit discard leaves the named library unchanged", not DraftStore.load_snapshot(third.recovery_root).exists and Store.list_variants(third.variants_root).size() == 1 and not third.get("_recovery_pending"))
	third.free()
	await settle()
	var unavailable: Dictionary = recovered.editor.duplicate(true)
	unavailable.presentation_buffers.smoke.slot = "missing_emitter"
	check("unavailable selection fixture remains readable recovery data", DraftStore.save_snapshot(scratch + "/recovery", recovered.payload, unavailable).ok)
	var fourth := make_editor()
	await settle()
	var untouched: Dictionary = fourth.get_recipe()
	fourth.call("_request_recovery_restore")
	check("unavailable recovered fields refuse before changing the active draft", fourth.get_recipe() == untouched and fourth.get("_recovery_pending") and not fourth.get("_trial_button").disabled)
	check("failed restore cannot replace stored text with fallback UI values", not fourth.call("_autosave_draft") and DraftStore.load_snapshot(fourth.recovery_root).editor.presentation_buffers.smoke.slot == "missing_emitter")
	fourth.call("_discard_pending_recovery")
	fourth.free()
	await settle()
	var writer_a := make_editor()
	var writer_b := make_editor()
	await settle()
	writer_a.set_recipe({"control_multiplier": 1.01})
	writer_b.set_recipe({"control_multiplier": 1.02})
	check("two fresh editors start with the same missing recovery identity", writer_a.get("_recovery_digest") == "missing" and writer_b.get("_recovery_digest") == "missing")
	check("first editor can publish its recovery snapshot", writer_a.call("_autosave_draft"))
	var first_digest: String = DraftStore.load_snapshot(writer_a.recovery_root).digest
	check("second editor refuses to overwrite another session and retains its own draft", not writer_b.call("_autosave_draft") and writer_b.get("_recovery_pending") and writer_b.get_recipe().control_multiplier == 1.02 and DraftStore.load_snapshot(writer_a.recovery_root).payload.recipe.control_multiplier == 1.01)
	var reviewer := make_editor()
	await settle()
	reviewer.call("dismiss_modal_for_exit")
	var restore_reviewer := make_editor()
	await settle()
	check("recovery review pins the exact snapshot shown to the user", reviewer.get("_recovery_digest") == first_digest and reviewer.get("_recovery_pending"))
	writer_a.set_recipe({"control_multiplier": 1.03})
	check("owning editor can replace the snapshot it last wrote", writer_a.call("_autosave_draft") and DraftStore.load_snapshot(writer_a.recovery_root).digest != first_digest)
	var restore_before: Dictionary = restore_reviewer.get_recipe()
	restore_reviewer.call("_request_recovery_restore")
	check("stale restore requires review of the replacement before mutating the editor", restore_reviewer.get_recipe() == restore_before and restore_reviewer.get("_recovery_pending") and restore_reviewer.get("_recovery_dialog").visible and restore_reviewer.get("_recovery_digest") == DraftStore.load_snapshot(writer_a.recovery_root).digest)
	restore_reviewer.call("dismiss_modal_for_exit")
	var reviewer_before: Dictionary = reviewer.get_recipe()
	reviewer.call("_show_recovery")
	reviewer.call("_discard_pending_recovery")
	check("stale discard keeps the newer recovery and active editor unchanged", reviewer.get("_recovery_pending") and reviewer.get_recipe() == reviewer_before and DraftStore.load_snapshot(writer_a.recovery_root).payload.recipe.control_multiplier == 1.03)
	check("conflict refreshes the review identity and restores normal editing actions", reviewer.get("_recovery_digest") == DraftStore.load_snapshot(writer_a.recovery_root).digest and not reviewer.get("_trial_button").disabled)
	reviewer.call("_show_recovery")
	reviewer.call("_discard_pending_recovery")
	check("explicit discard after refreshed review removes only the reviewed snapshot", not DraftStore.load_snapshot(writer_a.recovery_root).exists and Store.list_variants(writer_a.variants_root).size() == 1)
	writer_a.free()
	writer_b.free()
	reviewer.free()
	restore_reviewer.free()
	await settle()
	await test_clean_recovery()
	await test_legacy_surface_override_recovery()
	await test_empty_recovery_discard()
	_remove_tree(ProjectSettings.globalize_path(scratch))
	print("Workshop recovery UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_clean_recovery() -> void:
	# AE-03c-R1: exercise the real debounce, not only explicit autosave calls.
	var editor := make_editor()
	await settle()
	editor.set_recipe({"control_multiplier": 1.1})
	await create_timer(1.0).timeout
	check("edit reaches automatic recovery before Undo", DraftStore.load_snapshot(editor.recovery_root).exists)
	editor.call("_undo")
	await create_timer(1.0).timeout
	check("Undo to the baseline automatically removes obsolete recovery", not editor.has_unsaved_changes()
		and not DraftStore.load_snapshot(editor.recovery_root).exists)
	editor.call("_redo")
	await create_timer(1.0).timeout
	var redone: Dictionary = DraftStore.load_snapshot(editor.recovery_root)
	check("Redo republishes the same edit after clean recovery removal", redone.exists
		and redone.payload.recipe.control_multiplier == 1.1)
	editor.call("_undo")
	# Closing before the next timeout must perform the same cleanup synchronously.
	var closed := [false]
	editor.closed.connect(func() -> void: closed[0] = true)
	editor.call("_request_close")
	check("immediate clean close clears recovery without an unsaved prompt", closed[0]
		and not is_instance_valid(editor.get("_guard_dialog"))
		and not DraftStore.load_snapshot(editor.recovery_root).exists)
	editor.free()
	await settle()
	editor = make_editor()
	await settle()
	check("reopening after Undo and clean close has no recovery prompt", not editor.get("_recovery_pending")
		and not is_instance_valid(editor.get("_recovery_dialog")))
	if editor.get("_recovery_pending"): editor.call("_discard_pending_recovery")
	# A saved baseline can differ from stock; cleanup must not delete the library record.
	editor.set_recipe({"control_multiplier": 1.05})
	editor.set_variant_name("Recovery baseline")
	editor.save_named_variant()
	var saved_id: String = editor.get("_saved_variant_id")
	check("non-stock baseline saves", not saved_id.is_empty())
	editor.set_recipe({"control_multiplier": 1.15})
	check("later edit records recovery", editor.call("_autosave_draft"))
	editor.call("_undo")
	check("clean synchronization clears recovery against a saved baseline", not editor.has_unsaved_changes()
		and editor.call("_autosave_draft") and not DraftStore.load_snapshot(editor.recovery_root).exists
		and Store.load_variant(saved_id, editor.variants_root).variant.recipe.control_multiplier == 1.05)
	# A newer writer's digest must survive both delayed cleanup and immediate navigation.
	for navigate: bool in [false, true]:
		editor.set_recipe({"control_multiplier": 1.15})
		check("owner records a snapshot for concurrent cleanup", editor.call("_autosave_draft"))
		var owned: Dictionary = DraftStore.load_snapshot(editor.recovery_root)
		var replacement: Dictionary = owned.editor.duplicate(true)
		replacement.name = "Another editor's draft"
		var written: Dictionary = DraftStore.save_snapshot(editor.recovery_root, owned.payload, replacement, "", owned.digest)
		check("concurrent writer replaces the owner's recovery", written.ok)
		editor.call("_undo")
		if navigate:
			var continued := [false]
			editor.request_navigation("Back to Home", func() -> void: continued[0] = true)
			check("clean navigation can finish without discarding another writer", continued[0])
		else:
			check("clean synchronization detects a replaced recovery", not editor.call("_autosave_draft"))
		check("cleanup preserves the newer snapshot for explicit review", DraftStore.load_snapshot(editor.recovery_root).digest == written.digest
			and editor.get("_recovery_pending"))
		if not editor.get("_recovery_pending"): editor.call("_refresh_recovery_after_conflict")
		editor.call("_show_recovery")
		editor.call("_discard_pending_recovery")
	editor.free()
	await settle()

func test_legacy_surface_override_recovery() -> void:
	var library_path := scratch + "/legacy_surface/library"
	var recovery_path := scratch + "/legacy_surface/recovery"
	var source_editor := make_editor(library_path, recovery_path)
	await settle()
	source_editor.set_recipe({"control_multiplier": 1.05})
	source_editor.set_variant_name("Legacy surface recovery")
	source_editor.save_named_variant()
	var saved_id := str(source_editor.get("_saved_variant_id"))
	var original_result: Dictionary = Store.load_variant(saved_id, library_path) if not saved_id.is_empty() else {}
	var original: Dictionary = original_result.get("variant", {})
	var original_pin := str(original.get("compiler_version", ""))
	var original_recipe: Dictionary = original.get("recipe", {}).duplicate(true)
	check("surface recovery starts from a real legacy-pinned library build",
		original_result.get("ok", false) and original_pin == Compiler.COMPILER_VERSION
		and not original_recipe.has("control_multiplier_aileron"))
	if not original_result.get("ok", false):
		source_editor.free()
		await settle()
		return

	var valid_baseline: Dictionary = source_editor.get("_baseline").duplicate(true)
	var stale_baseline: Dictionary = valid_baseline.duplicate(true)
	stale_baseline.compiler = "openrc-aircraft-workshop-v1-obsolete"
	source_editor.set("_baseline", stale_baseline)
	var candidate_recipe: Dictionary = original_recipe.duplicate(true)
	candidate_recipe["control_multiplier_aileron"] = 1.25
	source_editor.set_recipe(candidate_recipe)
	var pending_text := "unfinished elevator value"
	var elevator_input: LineEdit = source_editor.get("_factor_inputs").control_multiplier_elevator
	elevator_input.text = pending_text
	elevator_input.text_changed.emit(pending_text)
	check("recovery refuses an edited candidate from a truly stale baseline compiler pin",
		not source_editor.call("_autosave_draft") and not DraftStore.load_snapshot(recovery_path).exists)
	source_editor.set("_baseline", valid_baseline)
	check("valid legacy baseline allows recovery with the candidate compiler",
		source_editor.call("_autosave_draft"))
	var recovered := DraftStore.load_snapshot(recovery_path)
	check("legacy surface candidate recovery is compatible and uses its current compiler",
		recovered.get("ok", false) and recovered.get("compatible", false)
		and recovered.payload.compiler_version == Compiler.version_for_recipe(candidate_recipe)
		and recovered.payload.recipe == candidate_recipe
		and recovered.editor.numeric_buffers.get("control_multiplier_elevator", "") == pending_text)
	check("autosave preserves the loaded library pin and ancestry",
		source_editor.get("_saved_compiler_version") == original_pin
		and source_editor.get("_saved_variant_id") == saved_id
		and source_editor.get("_saved_variant_revision") == original.revision)
	var saved_after_autosave: Dictionary = Store.load_variant(saved_id, library_path)
	check("autosave leaves the original legacy revision unchanged",
		saved_after_autosave.get("ok", false)
		and saved_after_autosave.variant.revision == original.revision
		and saved_after_autosave.variant.compiler_version == original_pin
		and saved_after_autosave.variant.recipe == original_recipe)

	source_editor.free()
	await settle()
	var fresh_editor := make_editor(library_path, recovery_path)
	await settle()
	var recovery_text: Label = fresh_editor.get("_recovery_text")
	var aileron_label := str(fresh_editor.call("_parameter_label", "control_multiplier_aileron"))
	var elevator_label := str(fresh_editor.call("_parameter_label", "control_multiplier_elevator"))
	check("recovery review names accepted and pending surface controls",
		not aileron_label.is_empty() and aileron_label != "Setting"
		and not elevator_label.is_empty() and elevator_label != "Setting"
		and recovery_text.text.contains(aileron_label) and recovery_text.text.contains(elevator_label))
	fresh_editor.call("_request_recovery_restore")
	await settle()
	var restored_recipe: Dictionary = fresh_editor.get_recipe()
	check("fresh editor restores the candidate as a detached build with the new pin",
		restored_recipe == candidate_recipe
		and fresh_editor.get("_saved_compiler_version") == Compiler.version_for_recipe(candidate_recipe)
		and str(fresh_editor.get("_saved_variant_id")).is_empty()
		and int(fresh_editor.get("_saved_variant_revision")) == 0
		and fresh_editor.has_unsaved_changes())
	check("fresh editor restores invalid surface input without applying it physically",
		fresh_editor.get("_factor_inputs").control_multiplier_elevator.text == pending_text
		and not restored_recipe.has("control_multiplier_elevator")
		and not fresh_editor.call("_edit_valid"))
	var saved_after_restore: Dictionary = Store.load_variant(saved_id, library_path)
	check("detached restore still leaves the original legacy revision unchanged",
		saved_after_restore.get("ok", false)
		and saved_after_restore.variant.revision == original.revision
		and saved_after_restore.variant.compiler_version == original_pin
		and saved_after_restore.variant.recipe == original_recipe)
	if is_instance_valid(fresh_editor.get("_recovery_timer")):
		fresh_editor.get("_recovery_timer").stop()
	fresh_editor.free()
	await settle()
	DraftStore.discard_snapshot(recovery_path)

func test_empty_recovery_discard() -> void:
	# A truncated file must be discardable without disabling future recovery.
	for backup: bool in [false, true]:
		var recovery_path := scratch + ("/empty_backup" if backup else "/empty_primary")
		var directory := ProjectSettings.globalize_path(recovery_path + "/_workshop_recovery")
		var filename := "snapshot.json.bak" if backup else "snapshot.json"
		var snapshot_path := directory.path_join(filename)
		check("empty %s fixture directory creates" % filename, DirAccess.make_dir_recursive_absolute(directory) == OK)
		var file := FileAccess.open(snapshot_path, FileAccess.WRITE)
		check("empty %s fixture opens" % filename, file != null)
		if file == null: return
		file.close()
		var editor := make_editor("", recovery_path)
		await settle()
		check("empty %s is shown as unavailable for restore" % filename, editor.get("_recovery_pending")
			and editor.get("_recovery_dialog").visible and editor.get("_recovery_dialog").get_ok_button().disabled)
		check("empty %s has its exact-byte SHA-256 identity" % filename,
			editor.get("_recovery_digest") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
		editor.call("_discard_pending_recovery")
		check("explicit discard clears the reviewed empty %s" % filename, not editor.get("_recovery_pending")
			and not FileAccess.file_exists(snapshot_path) and DraftStore.load_snapshot(recovery_path).digest == "missing")
		editor.set_recipe({"control_multiplier": 1.07})
		check("automatic recovery resumes after discarding empty %s" % filename, editor.call("_autosave_draft")
			and DraftStore.load_snapshot(recovery_path).get("ok", false))
		editor.free()
		await settle()

	# A different corrupt file arriving after review must not be discarded as the empty one.
	var stale_path := scratch + "/empty_recovery_stale"
	var stale_directory := ProjectSettings.globalize_path(stale_path + "/_workshop_recovery")
	var stale_primary := stale_directory.path_join("snapshot.json")
	check("stale empty recovery fixture directory creates", DirAccess.make_dir_recursive_absolute(stale_directory) == OK)
	var file := FileAccess.open(stale_primary, FileAccess.WRITE)
	check("stale empty recovery fixture opens", file != null)
	if file == null: return
	file.close()
	var reviewer := make_editor("", stale_path)
	await settle()
	var replacement := "new corrupt recovery".to_utf8_buffer()
	file = FileAccess.open(stale_primary, FileAccess.WRITE)
	check("concurrent replacement fixture opens", file != null)
	if file == null:
		reviewer.free()
		return
	file.store_buffer(replacement)
	file.close()
	reviewer.call("_discard_pending_recovery")
	var refreshed := DraftStore.load_snapshot(stale_path)
	check("stale discard preserves the changed file and refreshes the review identity",
		reviewer.get("_recovery_pending") and FileAccess.get_file_as_bytes(stale_primary) == replacement
		and not str(refreshed.get("digest", "")).is_empty()
		and reviewer.get("_recovery_digest") == refreshed.digest)
	reviewer.call("_show_recovery")
	reviewer.call("_discard_pending_recovery")
	check("discard after renewed review clears the replacement", not reviewer.get("_recovery_pending")
		and not DraftStore.load_snapshot(stale_path).exists)
	reviewer.free()
	await settle()

func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories(): _remove_tree(path.path_join(child))
	directory = null
	DirAccess.remove_absolute(path)
