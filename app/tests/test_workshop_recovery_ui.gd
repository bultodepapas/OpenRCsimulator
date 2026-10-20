extends SceneTree
const Workshop := preload("res://ui/workshop.gd")
const DraftStore := preload("res://workshop/draft_store.gd")
const Store := preload("res://workshop/store.gd")
var failures := 0
var checks := 0
var scratch := ""
func _initialize() -> void: run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed: failures += 1
func make_editor() -> Node:
	var editor := Workshop.new()
	editor.variants_root = scratch + "/library"
	editor.recovery_root = scratch + "/recovery"
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

func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories(): _remove_tree(path.path_join(child))
	directory = null
	DirAccess.remove_absolute(path)
