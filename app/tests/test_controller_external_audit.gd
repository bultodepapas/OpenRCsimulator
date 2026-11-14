extends SceneTree

const Setup := preload("res://ui/controller_setup.gd")
const Registry := preload("res://input/controller_registry.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const Service := preload("res://input/controller_service.gd")
const Wizard := preload("res://ui/radio_calibration_setup.gd")

var checks := 0
var failures := 0

class CountingStore extends Store:
	var acquisitions := 0
	func _init(storage: String) -> void:
		super(storage, storage + ".legacy")
	func acquire_write() -> Dictionary:
		acquisitions += 1
		return super.acquire_write()

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func device(id: int, serial: String, kind := "gamepad") -> Dictionary:
	return {id = id, name = "Audit " + kind, raw_name = "Audit " + kind,
		guid = "audit-" + serial, serial_number = serial, known = kind == "gamepad", kind = kind}

func motion(id: int, axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = id
	event.axis = axis as JoyAxis
	event.axis_value = value
	return event

func button(id: int, index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = id
	event.button_index = index as JoyButton
	event.pressed = true
	return event

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	InputMap.load_from_project_settings()
	var store := Store.new("user://external-audit-%d/profiles.cfg" % Time.get_ticks_usec())
	var first := Profile.defaults()
	first.association = {serial_number = "A"}
	first = store.save_profile(first).profile
	var second := Profile.defaults()
	second.association = {serial_number = "A"}
	second = store.save_profile(second).profile
	var repairable := Profile.defaults()
	repairable.roll.range_kind = "absolute"
	var uncenterable := Profile.defaults()
	uncenterable.pitch.range_kind = "absolute"
	uncenterable.pitch.center = uncenterable.pitch.min
	check("old absolute-channel profiles remain storable for repair", store.save_profile(repairable).ok and store.save_profile(uncenterable).ok)
	var mixed := store.load_all()
	check("mixed old and healthy profiles remain available together", mixed.ok and mixed.profiles.size() == 4)
	var admission := Service.new()
	check("uncenterable stored profile cannot be acknowledged for flight", not admission.validate_profile_for_session(uncenterable).ok and admission.validate_profile_for_session(first).ok)
	admission.free()
	var registry := Registry.new()
	var a := device(5, "A")
	a.profile_id = first.profile_id
	registry.update_devices([a, device(6, "Menu")])
	var setup := Setup.new()
	setup.configure(registry, store, 5, 6)
	root.add_child(setup)
	await process_frame
	var closed := [0]
	setup.close_requested.connect(func() -> void: closed[0] += 1)
	setup.profile_name_edit.text = "Unsaved A"
	setup.load_selected_profile(second)
	check("inactive dirty draft is counted", setup.has_unsaved_changes())
	setup.request_close()
	check("closing on clean B protects dirty A", closed[0] == 0 and setup.unsaved_dialog.visible)
	setup._on_unsaved_choice("keep")
	check("Save current keeps other dirty contexts open", setup._save_profile(true) and closed[0] == 0 and setup.has_unsaved_changes())
	setup.load_selected_profile(first)
	check("inactive edited name survives Save B", setup.profile_name_edit.text == "Unsaved A")
	check("saving last dirty context can close", setup._save_profile(true) and closed[0] == 1)
	setup.free()

	# A numeric handle can outlive its original physical connection.
	for kind: String in ["gamepad", "radio"]:
		var original := Profile.defaults(kind, "mode2" if kind == "gamepad" else "radio_custom")
		original.configured = true
		original.association = {serial_number = "A-" + kind}
		original = store.save_profile(original).profile
		var source := device(5, "A-" + kind, kind)
		source.profile_id = original.profile_id
		registry = Registry.new()
		registry.update_devices([source, device(6, "Menu")])
		setup = Setup.new()
		setup.configure(registry, store, 5, 6)
		root.add_child(setup)
		await process_frame
		setup.profile_name_edit.text = "Retained original draft"
		var leases := setup.connection_leases()
		var bytes := FileAccess.get_file_as_bytes(store.path)
		registry.update_devices([device(5, "B-" + kind, kind), device(6, "Menu")])
		check("replacement refuses stale " + kind + " Save", not setup._save_profile(false))
		check("replacement preserves disk and draft " + kind, FileAccess.get_file_as_bytes(store.path) == bytes and setup.profile_name_edit.text == "Retained original draft")
		var service := Service.new()
		service.registry = registry
		service.store = store
		var roles := [registry.selected_device_id("flight"), registry.selected_device_id("ui")]
		var rejected := service.save_settings_from_setup(original, 5, 6, leases)
		check("service refuses stale setup origin " + kind, not rejected.ok and FileAccess.get_file_as_bytes(store.path) == bytes)
		check("rejected Save preserves current roles " + kind, roles == [registry.selected_device_id("flight"), registry.selected_device_id("ui")])
		service.free()
		setup.free()

	# A maintained switch capture owns the same connection generation as action capture.
	registry = Registry.new()
	registry.update_devices([device(5, "Capture", "radio")])
	setup = Setup.new()
	setup.configure(registry, store, 5, -1)
	root.add_child(setup)
	await process_frame
	var radio := Profile.defaults("radio", "radio_custom")
	radio.configured = true
	radio.aux.flaps = {type = "switch", buttons = [20, 21], invert = false}
	setup._set_draft_profile(radio)
	setup._aux_controls.flaps.switch_capture_buttons[0].disabled = false
	setup._start_aux_capture("flaps", 0, setup._aux_controls.flaps.switch_capture_buttons[0])
	var before: Dictionary = setup.current_profile()
	registry.update_devices([device(5, "Replacement", "radio")])
	setup._input(button(5, 42))
	check("AUX capture cancels on atomic replacement", not setup._is_capture_active() and setup.current_profile() == before)
	setup.free()

	registry = Registry.new()
	registry.update_devices([device(5, "Remap", "radio")])
	setup = Setup.new()
	setup.configure(registry, store, 5, -1)
	setup._set_draft_profile(radio)
	setup.axis_preview_provider = func(_id: int, axis: int) -> float: return -1.0 if axis == int(radio.throttle.axis) else 0.0
	root.add_child(setup)
	await process_frame
	var remap := setup.action_grid.find_child("Remap_camera_cycle", true, false) as Button
	setup._start_capture("camera_cycle", remap)
	setup._input(motion(5, int(radio.throttle.axis), -0.999))
	check("resting throttle jitter leaves action capture waiting", setup._is_capture_active())
	setup._input(button(5, 42))
	check("intended button follows irrelevant jitter", not setup._is_capture_active() and setup.current_profile().actions.camera_cycle.button == 42)
	for mode: int in [1, 2]:
		setup.open_setup_assistant()
		setup._assistant_bridge.apply_preset("mode%d" % mode)
		setup._on_registry_devices_changed()
		var wizard := Wizard.new()
		check("wizard accepts explicit mode after registry refresh", wizard.configure(registry, 5, radio, setup._calibration_stick_mode))
		root.add_child(wizard)
		await process_frame
		check("assistant mode reaches calibration diagram", wizard.view.stick_mode == mode)
		wizard.free()
		setup._assistant.cancel()
		await process_frame
	# Keep several measured conflicts reviewable and resolve them one at a time.
	radio.actions = {camera_cycle = {type = "axis", axis = 5, sign = 1, threshold = 0.65},
		camera_previous = {type = "axis", axis = 6, sign = 1, threshold = 0.65}}
	setup._set_draft_profile(radio)
	var measured: Dictionary = preload("res://input/rc_input.gd").DEFAULT_PROFILE.duplicate(true)
	measured.roll.axis = 5
	measured.pitch.axis = 6
	check("calibration retains measurements with several conflicts", setup.apply_calibration_draft(measured, 5, registry.connection_generation(5)))
	check("conflicted calibration cannot save", not setup._save_profile(false))
	setup._clear_action_binding("camera_cycle")
	check("first explicit repair keeps the remaining conflict editable", setup.current_profile().actions.camera_cycle.type == "unbound" and setup.current_profile().roll.axis == 5)
	setup._clear_action_binding("camera_previous")
	check("all repairs retain measurements and produce a valid profile", Profile.validate(setup._profile_candidate()).ok and setup.current_profile().pitch.axis == 6)
	setup._calibration_stick_mode = 1
	setup._set_draft_profile(Profile.defaults("radio", "radio_custom"))
	check("a different profile does not inherit the previous calibration mode", setup._calibration_stick_mode == 0)
	setup.free()

	registry = Registry.new()
	registry.update_devices([device(5, "Generic", "joystick")])
	setup = Setup.new()
	setup.configure(registry, store, 5, -1)
	root.add_child(setup)
	await process_frame
	setup.open_setup_assistant()
	check("generic assistant hands off to actual assignment workflow", setup._assistant_bridge.open_flight_axes() and setup._assistant == null and setup._selected_section == "axes")
	check("handoff does not enable guessed axes", not setup.joystick_enabled.button_pressed and not setup.current_profile().configured)
	setup._on_axis_changed(6.0, "roll", "axis")
	setup.joystick_enabled.button_pressed = true
	check("explicitly reviewed generic mapping can save", setup._save_profile(false))
	setup.free()
	var cache := Service.new()
	var counted := CountingStore.new(store.path)
	cache.store = counted
	cache.registry.update_devices([device(91, "Cache-raw", "joystick"), device(92, "Cache-pad"), device(93, "Retry-pad")])
	cache.profile_for_device(91)
	var after_miss := counted.acquisitions
	for repeat in 10: cache.profile_for_device(91)
	check("negative cache avoids repeated filesystem lock acquisition", counted.acquisitions == after_miss)
	cache.profile_for_device(92)
	var after_hit := counted.acquisitions
	for repeat in 10: cache.profile_for_device(92)
	check("positive cache avoids repeated filesystem lock acquisition", counted.acquisitions == after_hit)
	check("fixture holds independent store lock", store.acquire_write().ok)
	check("busy resolution does not enable fallback", cache.profile_for_device(93).is_empty())
	store.release_write()
	check("busy resolution retries without caching a miss", not cache.profile_for_device(93).is_empty())
	cache.free()
	print("External controller audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
