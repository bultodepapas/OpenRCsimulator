extends SceneTree

const Setup := preload("res://ui/controller_setup.gd")
const Profile := preload("res://input/controller_profile.gd")
const Store := preload("res://input/controller_profile_store.gd")

var checks := 0
var failures := 0
var store: Store


class Registry extends RefCounted:

	signal devices_changed

	var devices: Array[Dictionary] = []
	var generation := 1

	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)

	func selected_device_id(_role: String) -> int:
		return 41

	func device_for_id(device_id: int) -> Dictionary:
		for device: Dictionary in devices:
			if device.id == device_id:
				return device.duplicate(true)
		return {}

	func connection_generation(_device_id: int) -> int:
		return generation


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


func select_profile(setup: Setup, item_id: int) -> void:
	var index := setup.profile_picker.get_item_index(item_id)
	setup.profile_picker.select(index)
	setup.profile_picker.item_selected.emit(index)


func stored(profile_id: String) -> Dictionary:
	for profile: Dictionary in store.load_all().profiles:
		if profile.profile_id == profile_id:
			return profile
	return {}


func open_setup(registry: Registry) -> Setup:
	var setup := Setup.new()
	setup.configure(registry, store, 41, 41)
	root.add_child(setup)
	return setup


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	var directory := "user://profile-creation-%d" % Time.get_ticks_usec()
	store = Store.new(directory + "/profiles.cfg", directory + "/legacy.cfg")
	var original := Profile.defaults("gamepad", "mode1")
	original.name = "Shared name"
	original.roll.axis = 8
	original.actions = {"camera_previous": {"type": "button", "button": 25}}
	original.association = {"serial_number": "original-profile-device"}
	var saved := store.save_profile(original)
	check("baseline profile is valid and saved", saved.ok)
	original = saved.profile
	var registry := Registry.new()
	registry.devices = [{"id": 41, "name": "Creation fixture", "kind": "gamepad", "known": true,
		"connected": true, "profile_id": original.profile_id, "serial_number": "creation-device"}]
	var setup := open_setup(registry)
	await process_frame
	check("saved profile is selected initially", setup.current_profile().profile_id == original.profile_id)
	setup.profile_name_edit.text = "Unsaved original name"
	setup._on_axis_changed(9.0, "roll", "axis")
	var remap := setup.action_grid.find_child("Remap_camera_previous", true, false) as Button
	setup._start_capture("camera_previous", remap)
	select_profile(setup, -1)
	var new_id: String = setup.current_profile().profile_id
	check("New cancels active remapping", not setup._is_capture_active())
	check("New gets a distinct valid identity", new_id != original.profile_id and Profile.validate(setup.current_profile()).ok)
	check("New uses device defaults rather than copying saved mappings", setup.current_profile().preset == "mode2" and setup.current_profile().roll.axis == 2 and setup.current_profile().actions.is_empty())
	check("New does not inherit the old association", setup.current_profile().association.is_empty())
	check("New remains selected", setup.profile_picker.get_selected_id() == -1)
	check("creating a draft leaves disk unchanged", store.load_all().profiles == [original])
	setup.profile_name_edit.text = "Shared name"
	setup._on_axis_changed(7.0, "roll", "axis")
	select_profile(setup, 0)
	check("switching back restores unsaved original edits", setup.profile_name_edit.text == "Unsaved original name" and setup.current_profile().roll.axis == 9)
	select_profile(setup, -1)
	check("switching back to New restores its identity and edits", setup.current_profile().profile_id == new_id and setup.current_profile().roll.axis == 7 and setup.profile_name_edit.text == "Shared name")
	setup.save_and_apply = func(_candidate: Dictionary, _flight: int, _menu: int) -> Dictionary:
		return {"ok": false, "error": "fixture activation refusal"}
	check("failed save keeps New editable with the same identity", not setup._save_profile(false) and setup.current_profile().profile_id == new_id)
	check("failed save preserves stored original", store.load_all().profiles == [original])
	setup.save_and_apply = Callable()
	check("New saves successfully on retry", setup._save_profile(false))
	check("same name creates two profiles with distinct IDs", store.load_all().profiles.size() == 2 and stored(new_id).name == original.name)
	check("original profile remains identical after New save", stored(original.profile_id) == original)
	check("new mapping and selected-device association persist", stored(new_id).roll.axis == 7 and stored(new_id).association.serial_number == "creation-device")
	check("saved New is selected as an existing profile", setup.profile_picker.get_selected_id() == 1)
	select_profile(setup, -1)
	check("New after a nonclosing Save starts a different draft", setup.current_profile().profile_id not in [new_id, original.profile_id] and setup.current_profile().roll.axis == 2)
	var closes := [0]
	setup.close_requested.connect(func() -> void: closes[0] += 1)
	setup._cancel_edits()
	check("Cancel closes without creating the pending third profile", closes[0] == 1 and store.load_all().profiles.size() == 2 and stored(original.profile_id) == original)
	setup.free()
	await process_frame
	setup = open_setup(registry)
	await process_frame
	check("reload keeps both saved identities", setup._profiles.size() == 2 and setup.current_profile() == original)
	select_profile(setup, 1)
	check("new profile reloads its mapping", setup.current_profile().profile_id == new_id and setup.current_profile().roll.axis == 7)
	setup.profile_name_edit.text = "Updated new profile"
	check("editing an existing profile updates rather than duplicates", setup._save_profile(false) and store.load_all().profiles.size() == 2 and stored(new_id).name == "Updated new profile")
	check("updating the new profile still preserves original", stored(original.profile_id) == original)
	setup._duplicate_profile()
	var duplicate_id: String = setup.current_profile().profile_id
	check("Duplicate has a distinct identity and retains mappings", duplicate_id not in [new_id, original.profile_id] and setup.current_profile().roll.axis == 7)
	check("Duplicate saves separately", setup._save_profile(false) and store.load_all().profiles.size() == 3 and stored(duplicate_id).roll.axis == 7)
	check("Duplicate leaves both source profiles intact", stored(original.profile_id) == original and stored(new_id).name == "Updated new profile")
	setup.free()
	await process_frame
	await check_initial_drafts(original)
	await check_calibration_context(original)
	for suffix: String in ["", ".tmp", ".rollback"]:
		var path := store.path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	print("controller profile creation: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check_initial_drafts(original: Dictionary) -> void:
	var cases: Array[Dictionary] = [
		{"kind": "gamepad", "known": true, "name": "Gamepad", "preset": "mode2"},
		{"kind": "radio", "known": false, "name": "Radio", "preset": "radio_custom"},
		{"kind": "joystick", "known": false, "name": "Joystick", "preset": "radio_custom"},
		{"kind": "radio", "known": false, "name": "JETI DS-16", "preset": "jeti_mode2", "vendor_id": 0x0483, "product_id": 0xA07C},
	]
	for device: Dictionary in cases:
		var registry := Registry.new()
		device["id"] = 41
		device["connected"] = true
		registry.devices = [device]
		var setup := open_setup(registry)
		await process_frame
		var initial := setup.current_profile()
		check("initial %s draft uses its device preset" % device.name, initial.kind == device.kind and initial.preset == device.preset)
		check("unknown joystick still requires explicit configuration", initial.configured == (device.kind != "joystick"))
		setup.profile_name_edit.text = "Pending " + str(device.name)
		setup._on_axis_changed(9.0, "roll", "axis")
		select_profile(setup, 0)
		check("initial draft can switch to an existing profile", setup.current_profile().profile_id == original.profile_id)
		select_profile(setup, -1)
		check("New restores the initial device draft and edits", setup.current_profile().profile_id == initial.profile_id and setup.current_profile().roll.axis == 9 and setup.profile_name_edit.text == "Pending " + str(device.name))
		select_profile(setup, -1)
		check("reselecting New preserves the current draft", setup.current_profile().profile_id == initial.profile_id and setup.current_profile().roll.axis == 9)
		var file_before := FileAccess.get_sha256(store.path)
		setup._cancel_edits()
		check("cancelling device draft preserves storage bytes", FileAccess.get_sha256(store.path) == file_before)
		setup.free()
		await process_frame


func check_calibration_context(original: Dictionary) -> void:
	var registry := Registry.new()
	registry.devices = [{"id": 41, "name": "Calibrated radio", "kind": "radio", "known": false,
		"connected": true, "profile_id": original.profile_id}]
	var setup := open_setup(registry)
	await process_frame
	select_profile(setup, -1)
	var calibration := Profile.defaults("radio", "radio_custom")
	check("New radio accepts calibration into its draft", setup.apply_calibration_draft(calibration, 41, registry.generation))
	check("calibrated New profile saves", setup._save_profile(false))
	var calibrated_id: String = setup.current_profile().profile_id
	registry.generation += 1
	check("save context migration retains calibration connection guard", not setup._save_profile(false))
	registry.generation -= 1
	setup.profile_name_edit.text = "Updated calibrated radio"
	check("same-context update saves with the original connection", setup._save_profile(false) and stored(calibrated_id).name == "Updated calibrated radio")
	registry.generation += 1
	check("same-context update retains calibration connection guard", not setup._save_profile(false))
	select_profile(setup, -1)
	check("next New does not inherit stale calibration provenance", setup.current_profile().profile_id != calibrated_id and setup._save_profile(false))
	check("radio creation still leaves original profile unchanged", stored(original.profile_id) == original)
	setup.free()
	await process_frame
