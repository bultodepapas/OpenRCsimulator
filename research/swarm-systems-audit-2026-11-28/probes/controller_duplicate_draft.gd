extends SceneTree

const Setup := preload("res://ui/controller_setup.gd")
const Profile := preload("res://input/controller_profile.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Registry := preload("res://input/controller_registry.gd")


func _initialize() -> void:
	_run.call_deferred()


func _select(setup: Setup, index: int) -> void:
	setup.profile_picker.select(index)
	setup.profile_picker.item_selected.emit(index)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	var directory := "user://r2-draft-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store := Store.new(directory.path_join("profiles.cfg"), directory.path_join("legacy.cfg"))
	var initial := Profile.defaults("gamepad", "mode1")
	initial.name = "Training"
	var stored: Dictionary = store.save_profile(initial)
	if not stored.ok:
		print("R2_CONTROLLER_DRAFT seed failed ", stored)
		quit(1)
		return
	var original: String = stored.profile.profile_id
	var registry := Registry.new()
	registry.update_devices([{id = 41, name = "Audit gamepad", kind = "gamepad", known = true,
		profile_id = original, serial_number = "draft-audit"}])
	var setup := Setup.new()
	setup.configure(registry, store, 41, 41)
	root.add_child(setup)
	await process_frame
	var closes := [0]
	setup.close_requested.connect(func() -> void: closes[0] += 1)
	setup._duplicate_profile()
	var pending_id: String = setup.current_profile().profile_id
	setup.profile_name_edit.text = "Turn practice"
	setup._on_axis_changed(9.0, "roll", "axis")
	# Leave the duplicate, then visit every entry the profile picker offers.
	_select(setup, setup.profile_picker.get_item_index(0))
	var pending_found := false
	var offered := PackedStringArray()
	for index in setup.profile_picker.item_count:
		offered.append(setup.profile_picker.get_item_text(index))
		_select(setup, index)
		pending_found = pending_found or setup.current_profile().profile_id == pending_id
	_select(setup, setup.profile_picker.get_item_index(0))
	var saved_original: bool = setup._save_profile(true)
	var save_message: String = setup.status_label.text
	var close_signals_before_discard: int = closes[0]
	var remains_dirty: bool = setup.has_unsaved_changes()
	var orphan: Dictionary = setup._drafts_by_context.get("profile:" + pending_id, {})
	var remembered: bool = orphan.get("name") == "Turn practice" and int(orphan.get("roll", {}).get("axis", -1)) == 9
	setup._cancel_edits()
	var closed_on_discard: bool = closes[0] == 1
	setup.free()
	var after: Dictionary = store.load_all()
	var only_original: bool = after.ok and after.profiles.size() == 1 and after.profiles[0].profile_id == original \
		and after.profiles[0].name == initial.name and int(after.profiles[0].roll.axis) == int(initial.roll.axis)
	# Immediate Save is the working control, using another widget and the same durable store.
	var fresh := Setup.new()
	fresh.configure(registry, store, 41, 41)
	root.add_child(fresh)
	await process_frame
	fresh._duplicate_profile()
	fresh.profile_name_edit.text = "Saved immediately"
	fresh._on_axis_changed(9.0, "roll", "axis")
	var immediate: bool = fresh._save_profile(false)
	var retained_count := 0
	for item: Dictionary in store.load_all().profiles:
		if item.name == "Saved immediately" and item.profile_id != original and int(item.roll.axis) == 9:
			retained_count += 1
	fresh.free()
	var ok: bool = not pending_found and offered.size() == 2 and remembered and saved_original and remains_dirty \
		and close_signals_before_discard == 0 and save_message.contains("select them") and closed_on_discard \
		and only_original and immediate and retained_count == 1
	print("R2_CONTROLLER_DRAFT ", JSON.stringify({picker = offered, found_duplicate = pending_found,
		in_memory_name_and_axis = remembered, saved_original = saved_original, after_save_dirty = remains_dirty,
		close_signals_after_save = close_signals_before_discard, save_message = save_message,
		explicit_discard_closed = closed_on_discard, only_original_on_disk_after_discard = only_original,
		immediate_duplicate_saved = immediate and retained_count == 1, reproduced = ok}))
	quit(0 if ok else 1)
