extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")

const PROFILE_PATH := "user://controller_settings_save_test.cfg"
const LEGACY_PATH := "user://controller_settings_save_legacy.cfg"
const FAILURE_PARENT := "user://controller_settings_save_parent_file"
const CORRUPT_PATH := "user://controller_settings_save_corrupt.cfg"

var checks := 0
var failures := 0


class FakeSession extends Node:
	var _controller_lost := false
	var external_controller_selection := false
	var persist_controller_profile: Callable
	var persist_full_controller_profile: Callable
	var reject_trigger := false
	var reject_runtime_name := ""
	var reject_restore_name := ""
	var current_id := -1
	var current_profile: Dictionary = {}
	var apply_count := 0
	var radio := {"connected": false}

	func controller_profile_rejection(profile: Dictionary) -> String:
		if reject_trigger and profile.get("throttle_mode", "") == "trigger_absolute":
			return "trigger profile refused by fixture"
		return ""

	func apply_controller_selection(id: int, _info: Dictionary, profile: Dictionary, _initial_start := false) -> bool:
		apply_count += 1
		current_id = id
		current_profile = profile.duplicate(true)
		var applied_name := str(profile.get("name", ""))
		return (reject_runtime_name.is_empty() or applied_name != reject_runtime_name) and (reject_restore_name.is_empty() or applied_name != reject_restore_name)

	func controller_disconnected() -> void:
		_controller_lost = true
		radio.connected = false


func check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _clean(path: String) -> void:
	for suffix in ["", ".tmp", ".rollback"]:
		var target: String = path + suffix
		var absolute := _global(target)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(absolute)
		elif DirAccess.dir_exists_absolute(absolute):
			DirAccess.remove_absolute(absolute)


func _device(id: int, serial: String, known := true, name := "Save test gamepad") -> Dictionary:
	return {
		"id": id,
		"name": name,
		"raw_name": name,
		"guid": "save-test-%d" % id,
		"kind": "gamepad" if known else "joystick",
		"known": known,
		"vendor_id": 900 + id,
		"product_id": 100 + id,
		"serial_number": serial,
	}


func _service(storage_path: String, devices: Array) -> Service:
	var service := Service.new()
	# This suite starts inside Controls; Home default selection has its own suite.
	service.allow_automatic_selection = func() -> bool: return false
	service.store = Store.new(storage_path, LEGACY_PATH)
	service.enumerate_devices = func() -> Array: return devices
	service.refresh()
	return service


func _stored_profile(service: Service, profile_id: String) -> Dictionary:
	var loaded: Dictionary = service.store.load_all()
	if not bool(loaded.get("ok", false)):
		return {}
	for profile in loaded.profiles:
		if str(profile.get("profile_id", "")) == profile_id:
			return profile.duplicate(true)
	return {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean(PROFILE_PATH)
	_clean(LEGACY_PATH)
	_clean(FAILURE_PARENT)
	_clean(CORRUPT_PATH)
	var first_device := _device(71, "save-serial-71")
	var second_device := _device(72, "save-serial-72")
	var menu_device := _device(73, "save-serial-73")
	var stale_device := _device(74, "save-serial-74")
	var observed_devices: Array = [first_device, second_device, menu_device, stale_device]
	var service := _service(PROFILE_PATH, observed_devices)
	var session := FakeSession.new()
	service.session = session
	var notifications := {"flight": 0, "ui": []}
	service.flight_selection_changed.connect(func() -> void: notifications.flight += 1)
	service.ui_selection_changed.connect(func(id: int) -> void: notifications.ui.append(id))

	var first_profile: Dictionary = Profile.defaults()
	first_profile.name = "First Save"
	var first_result: Dictionary = service.save_settings_from_setup(first_profile, 71, 71)
	check("first Save from no selection applies both roles", first_result.get("ok", false) and service.registry.selected_device_id("flight") == 71 and service.registry.selected_device_id("ui") == 71)
	check("first Save associates and activates the configured flight profile", _stored_profile(service, first_profile.profile_id).get("association", {}).get("serial_number", "") == "save-serial-71" and session.current_id == 71 and session.current_profile.get("profile_id", "") == first_profile.profile_id)
	check("first Save emits one coherent notification for each changed role", notifications.flight == 1 and notifications.ui == [71])

	var second_profile: Dictionary = Profile.defaults()
	second_profile.name = "Second device profile"
	var switch_result: Dictionary = service.save_settings_from_setup(second_profile, 72, 72)
	check("Save switches flight and menu devices together", switch_result.get("ok", false) and service.registry.selected_device_id("flight") == 72 and service.registry.selected_device_id("ui") == 72 and session.current_id == 72)
	check("switching retains the first device profile", _stored_profile(service, first_profile.profile_id).get("name", "") == "First Save")

	var update := second_profile.duplicate(true)
	update.name = "Updated same target"
	var update_result: Dictionary = service.save_settings_from_setup(update, 72, 72)
	check("Save updates the same target profile in place", update_result.get("ok", false) and service.store.load_all().profiles.size() == 2 and _stored_profile(service, update.profile_id).get("name", "") == update.name)
	check("same-target profile update reaches the active runtime route", session.current_profile.get("name", "") == update.name)

	var applies_before_menu_change := session.apply_count
	var flight_notifications_before_menu_change: int = notifications.flight
	var menu_only_result: Dictionary = service.save_settings_from_setup(update, 72, 73)
	check("menu-only role change leaves the active flight route untouched", menu_only_result.get("ok", false) and service.registry.selected_device_id("flight") == 72 and service.registry.selected_device_id("ui") == 73 and session.apply_count == applies_before_menu_change and session.current_id == 72)
	check("menu-only role change emits only the UI notification", notifications.flight == flight_notifications_before_menu_change and notifications.ui.back() == 73)

	var bytes_before_incompatible: PackedByteArray = FileAccess.get_file_as_bytes(PROFILE_PATH)
	var roles_before_incompatible := [service.registry.selected_device_id("flight"), service.registry.selected_device_id("ui")]
	var applies_before_incompatible := session.apply_count
	session.reject_trigger = true
	var incompatible: Dictionary = Profile.defaults("gamepad", "trigger_absolute")
	var incompatible_result: Dictionary = service.save_settings_from_setup(incompatible, 72, 73)
	session.reject_trigger = false
	check("incompatible profile is rejected before storage or aircraft activation", not incompatible_result.get("ok", false) and FileAccess.get_file_as_bytes(PROFILE_PATH) == bytes_before_incompatible and [service.registry.selected_device_id("flight"), service.registry.selected_device_id("ui")] == roles_before_incompatible and session.apply_count == applies_before_incompatible)

	var store_before_rejection: Dictionary = service.store.load_all()
	var old_route := session.current_profile.duplicate(true)
	var old_notification_counts := [notifications.flight, notifications.ui.size()]
	var runtime_rejection := update.duplicate(true)
	runtime_rejection.name = "Refused after write"
	session.reject_runtime_name = runtime_rejection.name
	var rejected_result: Dictionary = service.save_settings_from_setup(runtime_rejection, 71, 71)
	session.reject_runtime_name = ""
	var store_after_rejection: Dictionary = service.store.load_all()
	check("unexpected runtime refusal rolls back the saved profile set", not rejected_result.get("ok", false) and store_after_rejection.get("ok", false) and store_after_rejection.profiles == store_before_rejection.profiles)
	check("runtime refusal restores both roles, runtime route, and cache", service.registry.selected_device_id("flight") == 72 and service.registry.selected_device_id("ui") == 73 and session.current_id == 72 and session.current_profile == old_route and service.profile_for_device(72).get("name", "") == "Updated same target")
	check("runtime refusal emits no partial selection notifications", [notifications.flight, notifications.ui.size()] == old_notification_counts)

	var before_same_target_rejection: Dictionary = service.store.load_all()
	var same_target_route := session.current_profile.duplicate(true)
	var same_target_notifications := [notifications.flight, notifications.ui.size()]
	var same_target_rejection := update.duplicate(true)
	same_target_rejection.name = "Refused same target"
	session.reject_runtime_name = same_target_rejection.name
	var same_target_result: Dictionary = service.save_settings_from_setup(same_target_rejection, 72, 71)
	session.reject_runtime_name = ""
	var after_same_target_rejection: Dictionary = service.store.load_all()
	check("same-target runtime refusal rolls back storage and the menu role", not same_target_result.get("ok", false) and after_same_target_rejection.get("ok", false) and after_same_target_rejection.profiles == before_same_target_rejection.profiles and service.registry.selected_device_id("flight") == 72 and service.registry.selected_device_id("ui") == 73)
	check("same-target refusal restores the old cached and runtime profile", session.current_id == 72 and session.current_profile == same_target_route and service.profile_for_device(72).get("name", "") == "Updated same target" and [notifications.flight, notifications.ui.size()] == same_target_notifications)

	observed_devices.erase(stale_device)
	service.refresh()
	var disconnected_ui_result: Dictionary = service.save_settings_from_setup(update, 72, 74)
	var disconnected_result: Dictionary = service.save_settings_from_setup(Profile.defaults(), 74, 73)
	check("disconnected UI and flight devices are rejected before saving", not disconnected_ui_result.get("ok", false) and not disconnected_result.get("ok", false) and service.registry.selected_device_id("flight") == 72 and service.registry.selected_device_id("ui") == 73 and service.store.load_all().profiles == store_before_rejection.profiles)

	var keyboard_result: Dictionary = service.save_settings_from_setup(update, -1, -1)
	check("keyboard fallback saves offline and clears both selected device roles", keyboard_result.get("ok", false) and service.registry.selected_device_id("flight") == -1 and service.registry.selected_device_id("ui") == -1 and session.current_id == -1, str(keyboard_result) + " roles=" + str([service.registry.selected_device_id("flight"), service.registry.selected_device_id("ui")]) + " runtime=" + str(session.current_id))
	service.free()
	session.free()

	# An unknown stick cannot drive the menu without a declaration. A single Save
	# that declares the same flight target as a configured gamepad may do both.
	var unknown_device := _device(81, "save-unknown-81", false, "Unknown save pad")
	var unknown_service := _service("user://controller_settings_unknown.cfg", [unknown_device])
	_clean("user://controller_settings_unknown.cfg")
	var no_declaration: Dictionary = unknown_service.save_settings_from_setup(Profile.defaults(), -1, 81)
	check("unknown menu device without a saved declaration is rejected", not no_declaration.get("ok", false) and unknown_service.registry.selected_device_id("ui") == -1)
	var declared_profile: Dictionary = Profile.defaults()
	declared_profile.name = "Declared unknown gamepad"
	var declared_result: Dictionary = unknown_service.save_settings_from_setup(declared_profile, 81, 81)
	check("first Save can declare an unambiguous unknown gamepad for both roles", declared_result.get("ok", false) and unknown_service.is_ui_gamepad(81) and unknown_service.registry.selected_device_id("flight") == 81 and unknown_service.registry.selected_device_id("ui") == 81)
	unknown_service.free()
	_clean("user://controller_settings_unknown.cfg")

	var refusal_service := _service("user://controller_settings_restore_refusal.cfg", [first_device, second_device])
	var refusal_session := FakeSession.new()
	refusal_service.session = refusal_session
	var baseline_profile: Dictionary = Profile.defaults()
	baseline_profile.name = "Baseline route"
	var baseline_result: Dictionary = refusal_service.save_settings_from_setup(baseline_profile, 71, 71)
	var refused_route := baseline_profile.duplicate(true)
	refused_route.name = "Refused route"
	refusal_session.reject_runtime_name = refused_route.name
	refusal_session.reject_restore_name = baseline_profile.name
	var restore_refusal: Dictionary = refusal_service.save_settings_from_setup(refused_route, 72, 72)
	check("runtime restore refusal is reported without claiming route restoration", baseline_result.get("ok", false) and not restore_refusal.get("ok", false) and str(restore_refusal.get("error", "")).contains("The previous runtime route could not be restored.") and not str(restore_refusal.get("error", "")).contains("The previous runtime route was restored."))
	check("restore refusal still reports storage and role restoration accurately", str(restore_refusal.get("error", "")).contains("Previous stored profiles were restored.") and str(restore_refusal.get("error", "")).contains("Previous device selections were restored.") and refusal_service.registry.selected_device_id("flight") == 71 and refusal_service.registry.selected_device_id("ui") == 71)
	refusal_service.free()
	refusal_session.free()
	_clean("user://controller_settings_restore_refusal.cfg")

	var radio_device := _device(82, "save-radio-82", false, "EdgeTX Save Radio")
	var radio_service := _service("user://controller_settings_radio.cfg", [radio_device])
	var radio_ui_result: Dictionary = radio_service.save_settings_from_setup(Profile.defaults("radio", "radio_custom"), 82, 82)
	check("radio isolation prevents assigning a transmitter to menu controls", not radio_ui_result.get("ok", false) and radio_service.registry.selected_device_id("flight") == -1 and radio_service.registry.selected_device_id("ui") == -1)
	radio_service.free()
	_clean("user://controller_settings_radio.cfg")

	var corrupt_cfg := ConfigFile.new()
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "schema_version", 999)
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "profiles", [])
	check("corrupt storage fixture writes", corrupt_cfg.save(CORRUPT_PATH) == OK)
	var corrupt_service := _service(CORRUPT_PATH, [first_device])
	var corrupt_bytes: PackedByteArray = FileAccess.get_file_as_bytes(CORRUPT_PATH)
	var corrupt_result: Dictionary = corrupt_service.save_settings_from_setup(Profile.defaults(), 71, 71)
	check("settings save preserves corrupt-store errors without selecting devices", not corrupt_result.get("ok", false) and str(corrupt_result.get("error", "")).contains("unreadable") and corrupt_service.registry.selected_device_id("flight") == -1 and corrupt_service.registry.selected_device_id("ui") == -1 and FileAccess.get_file_as_bytes(CORRUPT_PATH) == corrupt_bytes)
	corrupt_service.free()
	_clean(CORRUPT_PATH)

	# A file where the parent directory should be forces the store's write path to
	# fail after preflight, without depending on OS permissions.
	var parent_file := FileAccess.open(FAILURE_PARENT, FileAccess.WRITE)
	parent_file.store_string("not a directory")
	parent_file.close()
	var failed_service := _service(FAILURE_PARENT.path_join("profiles.cfg"), [first_device])
	var failed_session := FakeSession.new()
	failed_service.session = failed_session
	var failed_save: Dictionary = failed_service.save_settings_from_setup(Profile.defaults(), 71, 71)
	check("storage failure leaves both role IDs and runtime route unchanged", not failed_save.get("ok", false) and failed_service.registry.selected_device_id("flight") == -1 and failed_service.registry.selected_device_id("ui") == -1 and failed_session.apply_count == 0)
	failed_service.free()
	failed_session.free()
	_clean(FAILURE_PARENT)
	_clean(PROFILE_PATH)
	_clean(LEGACY_PATH)
	_clean(CORRUPT_PATH)
	print("Controller settings save: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
