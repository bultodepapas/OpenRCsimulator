extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const Menu := preload("res://input/radio_menu.gd")
const RcInput := preload("res://input/rc_input.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []


class FakeSession extends Node:
	var _controller_lost := false
	var external_controller_selection := false
	var persist_controller_profile: Callable
	var persist_full_controller_profile: Callable
	var radio := {"connected": false}
	var current_id := -1
	var current_profile: Dictionary = {}
	var reject_name := ""
	var reject_roll_axis := -1
	var apply_count := 0

	func controller_profile_rejection(_profile: Dictionary) -> String:
		return ""

	func apply_controller_selection(id: int, _info: Dictionary, profile: Dictionary, _initial := false) -> bool:
		apply_count += 1
		if not reject_name.is_empty() and profile.get("name", "") == reject_name:
			return false
		if reject_roll_axis >= 0 and int(profile.get("roll", {}).get("axis", -1)) == reject_roll_axis:
			return false
		current_id = id
		current_profile = profile.duplicate(true)
		_controller_lost = false
		return true

	func controller_disconnected() -> void:
		_controller_lost = true
		radio.connected = false


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_run.call_deferred()


func _path(label: String) -> String:
	var value := "user://radio_menu_service_%d_%s.cfg" % [OS.get_process_id(), label]
	paths.append(value)
	return value


func _device(id: int, serial: String, radio := true, guid := "family-radio") -> Dictionary:
	var name := "Synthetic EdgeTX radio" if radio else "Synthetic Xbox gamepad"
	return {"id": id, "name": name, "raw_name": name, "kind": "radio" if radio else "gamepad",
		"known": not radio, "guid": guid, "vendor_id": 1209 if radio else 1118,
		"product_id": 500 if radio else 600, "serial_number": serial}


func _radio(serial: String, with_serial := true) -> Dictionary:
	var profile := Profile.defaults("radio", "radio_custom")
	profile.name = "Verified " + serial
	profile.roll.min = -0.812345678
	profile.roll.center = 0.031234567
	profile.roll.max = 0.912345678
	profile.actions["accept"] = {"type": "button", "button": 10}
	profile.actions["back"] = {"type": "axis", "axis": 7, "sign": -1, "threshold": 0.65,
		"off": 0.8, "on": 0.2, "invert": true}
	profile.actions["pause"] = {"type": "button", "button": 11}
	profile.association = {"guid": "family-radio", "vendor_id": 1209, "product_id": 500}
	if with_serial: profile.association["serial_number"] = serial
	return Menu.verified_profile(profile)


func _service(path: String, devices: Array, automatic := false) -> Service:
	var service := Service.new()
	service.store = Store.new(path, path + ".legacy")
	service.enumerate_devices = func() -> Array: return devices
	service.allow_automatic_selection = func() -> bool: return automatic
	service.refresh()
	return service


func _run() -> void:
	_store_compatibility()
	_eligibility_and_restart()
	_automatic_fallback()
	_known_gamepad_radio_override()
	_duplicate_identity()
	_rollback()
	_calibration_invalidates()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".rollback", ".legacy"]:
			var target := path + suffix
			if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("Radio menu service: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _store_compatibility() -> void:
	var path := _path("old")
	var cfg := ConfigFile.new()
	cfg.set_value(Store.STORAGE_SECTION, "schema_version", Profile.SCHEMA_VERSION)
	cfg.set_value(Store.STORAGE_SECTION, "profiles", [Profile.defaults()])
	check("old V2 store fixture writes", cfg.save(path) == OK)
	var store := Store.new(path, path + ".legacy")
	var old: Dictionary = store.load_all()
	check("old profile files default to no menu preference", old.ok and old.profiles.size() == 1 and old.ui_preference == {})
	var radio := _radio("store-serial")
	check("verified radio is a valid profile", not radio.is_empty() and Profile.validate(radio).ok, str(Profile.validate(radio).errors))
	var preference := {"mode": "profile", "profile_id": radio.profile_id}
	var result: Dictionary = store.save_profile_with_ui_preference(radio, preference)
	var loaded: Dictionary = store.load_all()
	check("profile and preference commit together", result.ok and loaded.ok and loaded.profiles.size() == 2 and loaded.ui_preference == preference)
	var reloaded: Dictionary = {}
	for entry: Dictionary in loaded.profiles:
		if entry.profile_id == radio.profile_id: reloaded = entry
	check("calibrated navigation fingerprint survives storage rounding", not reloaded.is_empty() and Menu.is_verified(reloaded))
	check("preference holds profile UUID without a connection handle", loaded.ui_preference.keys().size() == 2 \
		and loaded.ui_preference.has("mode") and loaded.ui_preference.has("profile_id"))
	var before_bytes := FileAccess.get_file_as_bytes(path)
	var invalid: Dictionary = store.save_profile_with_ui_preference(radio, {"mode": "profile", "profile_id": ""})
	check("invalid preference rejects before changing storage", not invalid.ok and FileAccess.get_file_as_bytes(path) == before_bytes)
	var old_snapshot := loaded.duplicate(true)
	check("keyboard preference can be committed", store.save_profile_with_ui_preference(radio, {"mode": "keyboard"}).ok \
		and store.load_all().ui_preference == {"mode": "keyboard"})
	check("snapshot restores profiles and prior preference atomically", store.restore_snapshot(old_snapshot).ok \
		and store.load_all().profiles == old_snapshot.profiles and store.load_all().ui_preference == preference)


func _eligibility_and_restart() -> void:
	var path := _path("restart")
	var radio_info := _device(10, "radio-A")
	var pad_info := _device(5, "pad-A", false, "pad-guid")
	var observed: Array = [radio_info, pad_info]
	var service := _service(path, observed)
	check("unsaved recognized radio is not menu eligible", not service.is_ui_device(10) and not service.is_ui_gamepad(10) \
		and not service.select_devices(-1, 10))
	var verified := _radio("radio-A")
	var starter := verified.duplicate(true)
	starter.erase("ui_navigation")
	check("unverified saved radio starter is not menu eligible", service.store.save_profile(starter).ok \
		and not service.is_ui_device(10) and not service.select_devices(-1, 10))
	var stale := verified.duplicate(true)
	stale.roll.invert = not stale.roll.invert
	check("stale mapping proof cannot be saved or selected", not Menu.is_verified(stale) \
		and not service.store.save_profile(stale).ok and not service.is_ui_device(10))
	var saved: Dictionary = service.store.save_profile(verified)
	check("saved unique verified radio becomes eligible", saved.ok and service.is_ui_device(10) and not service.is_ui_gamepad(10))
	check("verified radio can explicitly own menu controls", service.select_devices(10, 10) \
		and service.registry.selected_device_id("ui") == 10)
	var commit: Dictionary = service.save_settings_from_setup(saved.profile, 10, 10)
	var preference: Dictionary = service.store.load_all().ui_preference
	check("same-device Save persists the verified profile UUID", commit.ok and preference == {"mode": "profile", "profile_id": verified.profile_id})
	var prior: Dictionary = service.store.load_all()
	var stale_after_selection: Dictionary = saved.profile.duplicate(true)
	stale_after_selection.roll.invert = not stale_after_selection.roll.invert
	var rejected: Dictionary = service.save_settings_from_setup(stale_after_selection, 10, 10)
	check("stale candidate cannot replace a live verified profile or its preference", not rejected.ok \
		and service.store.load_all().profiles == prior.profiles and service.store.load_all().ui_preference == prior.ui_preference \
		and service.registry.selected_device_id("ui") == 10)
	service.free()
	var moved_radio := _device(42, "radio-A")
	var moved_pad := _device(3, "pad-A", false, "pad-guid")
	var new_devices: Array = [moved_pad, moved_radio]
	var second := _service(path, new_devices, true)
	check("second session restores radio by identity with a new connection ID", second.registry.selected_device_id("ui") == 42 \
		and second.is_ui_device(42) and second.profile_for_device(42).profile_id == verified.profile_id)
	var impostor_devices: Array = [moved_pad, _device(42, "different-serial")]
	var impostor := _service(path, impostor_devices, true)
	check("reused connection ID with another serial cannot inherit saved UI proof", not impostor.is_ui_device(42) \
		and impostor.registry.selected_device_id("ui") != 42)
	impostor.free()
	check("explicit keyboard choice is accepted", second.select_devices(-1, -1))
	new_devices.append(_device(2, "new-pad", false, "other-pad"))
	second.refresh()
	check("new device cannot steal manual keyboard menu ownership", second.registry.selected_device_id("ui") == -1)
	var pad_profile := Profile.defaults()
	pad_profile.name = "Flight gamepad"
	var distinct: Dictionary = second.save_settings_from_setup(pad_profile, 3, 42)
	var distinct_pref: Dictionary = second.store.load_all().ui_preference
	check("distinct gamepad flight and radio menu can be committed", distinct.ok \
		and second.registry.selected_device_id("flight") == 3 and second.registry.selected_device_id("ui") == 42, str(distinct))
	check("distinct menu persists its own radio profile rather than flight profile", distinct_pref == {"mode": "profile", "profile_id": verified.profile_id} \
		and second.profile_for_device(42).profile_id == verified.profile_id and second.profile_for_device(3).profile_id == pad_profile.profile_id)
	var keyboard: Dictionary = second.save_settings_from_setup(pad_profile, 3, -1)
	check("keyboard menu preference commits", keyboard.ok and second.store.load_all().ui_preference == {"mode": "keyboard"})
	second.free()
	var keyboard_restore := _service(path, new_devices, true)
	check("second launch restores deliberate keyboard preference", keyboard_restore.registry.selected_device_id("ui") == -1)
	keyboard_restore.free()


func _automatic_fallback() -> void:
	var path := _path("automatic_fallback")
	var radio_a := _radio("flight-A")
	var radio_c := _radio("other-C")
	var pad := _device(5, "known-pad", false, "pad-guid")
	var initial := _service(path, [_device(10, "flight-A"), pad])
	var committed: Dictionary = initial.save_settings_from_setup(radio_a, 10, 5)
	var saved: Dictionary = initial.store.load_all()
	check("verified flight radio and unsaved ordinary UI gamepad save", committed.ok \
		and initial.registry.selected_device_id("flight") == 10 and initial.registry.selected_device_id("ui") == 5, str(committed))
	check("ordinary unsaved UI gamepad keeps an empty preference", saved.ok and saved.ui_preference == {} \
		and saved.profiles.size() == 1 and saved.profiles[0].profile_id == radio_a.profile_id)
	initial.free()
	var a_reconnected := _device(30, "flight-A")
	var b_reconnected := _device(42, "known-pad", false, "pad-guid")
	var restarted := _service(path, [a_reconnected, b_reconnected], true)
	check("startup keeps saved flight radio and falls back to ordinary gamepad", \
		restarted.registry.selected_device_id("flight") == 30 and restarted.registry.selected_device_id("ui") == 42 \
		and restarted.is_ui_device(30) and restarted.is_ui_gamepad(42))
	restarted.free()
	var only_radio := _service(path, [a_reconnected], true)
	check("startup without an explicit preference or gamepad uses keyboard, not saved radio", \
		only_radio.is_ui_device(30) and only_radio.registry.selected_device_id("ui") == -1)
	check("different verified radio can be stored", only_radio.store.save_profile(radio_c).ok)
	var preference := {"mode": "profile", "profile_id": radio_a.profile_id}
	check("explicit radio A preference saves", only_radio.store.save_profile_with_ui_preference(radio_a, preference).ok)
	only_radio.free()
	var c_reconnected := _device(44, "other-C")
	var missing_a := _service(path, [c_reconnected], true)
	check("missing preferred radio does not promote another verified radio", missing_a.is_ui_device(44) \
		and missing_a.registry.selected_device_id("flight") == 44 and missing_a.registry.selected_device_id("ui") == -1 \
		and missing_a.store.load_all().ui_preference == preference)
	missing_a.free()
	var missing_a_with_pad := _service(path, [c_reconnected, b_reconnected], true)
	check("missing preferred radio falls back to an ordinary gamepad", missing_a_with_pad.is_ui_device(44) \
		and missing_a_with_pad.registry.selected_device_id("ui") == 42)
	missing_a_with_pad.free()


func _known_gamepad_radio_override() -> void:
	var generic := _device(71, "generic-serial", false, "generic-guid")
	generic.name = "Generic USB controller"
	generic.raw_name = generic.name
	var devices: Array = [generic]
	var path := _path("known_as_radio")
	var service := _service(path, devices)
	check("metadata-known generic gamepad is ordinarily menu eligible", service.is_ui_gamepad(71) and service.is_ui_device(71))
	var unverified := Profile.defaults("radio", "radio_custom")
	var rejected: Dictionary = service.save_settings_from_setup(unverified, 71, 71)
	check("radio draft cannot inherit generic gamepad menu eligibility", not rejected.ok \
		and service.registry.selected_device_id("ui") == -1 and service.store.load_all().profiles.is_empty(), str(rejected))
	unverified.association = {"serial_number": "generic-serial", "vendor_id": 1118, "product_id": 600}
	check("explicit unverified radio fixture saves", service.store.save_profile(unverified).ok)
	service.refresh()
	check("saved explicit radio overrides known-gamepad UI eligibility", not service.is_ui_gamepad(71) \
		and not service.is_ui_device(71) and not service.select_devices(-1, 71))
	var radio_again: Dictionary = service.save_settings_from_setup(unverified, 71, 71)
	check("saved unverified radio still cannot be assigned to UI", not radio_again.ok and service.registry.selected_device_id("ui") == -1)
	service.free()

	var active_path := _path("known_live")
	var active := _service(active_path, devices)
	check("known gamepad can initially own both roles", active.select_devices(71, 71) and active.is_ui_gamepad(71))
	var session := FakeSession.new()
	active.attach_session(session)
	check("known gamepad has an active gamepad profile", active.profile_for_device(71).get("kind", "") == "gamepad")
	check("unverified radio can be explicitly applied to flight", active.apply_profile(unverified, 71))
	check("changing an active known gamepad to unverified radio clears UI immediately", \
		active.registry.selected_device_id("ui") == -1 and not active.is_ui_gamepad(71) \
		and not active.is_ui_device(71) and not active.select_devices(71, 71))
	active.free()
	session.free()

	var verified_path := _path("known_verified")
	var verified_service := _service(verified_path, devices)
	var verified := _radio("generic-serial")
	verified.association = {"guid": "generic-guid", "serial_number": "generic-serial", "vendor_id": 1118, "product_id": 600}
	verified = Menu.verified_profile(verified)
	var accepted: Dictionary = verified_service.save_settings_from_setup(verified, 71, 71)
	check("verified explicit radio may own UI despite generic gamepad metadata", accepted.ok \
		and verified_service.is_ui_device(71) and not verified_service.is_ui_gamepad(71) \
		and verified_service.registry.selected_device_id("ui") == 71, str(accepted))
	var lost_proof: Dictionary = accepted.get("profile", {}).duplicate(true)
	lost_proof.erase("ui_navigation")
	check("verified saved radio can be changed to an unverified active radio", verified_service.apply_profile(lost_proof, 71))
	check("unverified active mapping clears selected UI", verified_service.registry.selected_device_id("ui") == -1)
	check("saved old proof cannot make an unverified active radio eligible", not verified_service.is_ui_device(71))
	check("saved old proof cannot reselect an unverified active radio", not verified_service.select_devices(71, 71))
	verified_service.free()
	var reconnected := generic.duplicate(true)
	reconnected.id = 72
	var second_session := _service(verified_path, [reconnected], true)
	check("new connection restores the saved verified radio rather than stale runtime state", \
		second_session.registry.selected_device_id("ui") == 72 and second_session.is_ui_device(72) \
		and not second_session.is_ui_gamepad(72))
	second_session.free()


func _duplicate_identity() -> void:
	var path := _path("duplicates")
	var device_a := _device(31, "")
	var device_b := _device(32, "")
	var devices: Array = [device_a]
	var service := _service(path, devices)
	var unqualified := _radio("without serial", false)
	check("unqualified profile saves", service.store.save_profile(unqualified).ok)
	check("single nonserial identity is initially eligible", service.is_ui_device(31) and service.select_devices(31, 31))
	var session := FakeSession.new()
	service.attach_session(session)
	devices.append(device_b)
	service.refresh()
	check("duplicate nonserial arrival invalidates UI ownership without stealing flight", not service.is_ui_device(31) \
		and not service.is_ui_device(32) and service.registry.selected_device_id("ui") == -1 \
		and service.registry.selected_device_id("flight") == 31)
	var stored_preference := {"mode": "profile", "profile_id": unqualified.profile_id}
	check("ambiguous preference fixture saves", service.store.save_profile_with_ui_preference(unqualified, stored_preference).ok)
	var other_radio := _radio("fallback-C")
	other_radio.association.guid = "different-radio"
	other_radio = Menu.verified_profile(other_radio)
	check("separate verified radio fixture saves alongside ambiguous preference", service.store.save_profile(other_radio).ok \
		and service.store.load_all().ui_preference == stored_preference)
	var fallback_devices: Array = [device_a, device_b, _device(4, "fallback-C", true, "different-radio"), \
		_device(3, "fallback-pad", false, "fallback-guid")]
	var fallback := _service(path, fallback_devices, true)
	check("ambiguous saved preference falls back without guessing either radio", fallback.registry.selected_device_id("ui") == 3 \
		and not fallback.is_ui_device(31) and not fallback.is_ui_device(32) and fallback.is_ui_device(4))
	fallback.free()
	service.free()
	session.free()
	var serial_path := _path("serial")
	var serial_a := _device(51, "unique-A")
	var serial_b := _device(52, "unique-B")
	var serial_devices: Array = [serial_a, serial_b]
	var serial_service := _service(serial_path, serial_devices)
	var qualified := _radio("unique-A")
	check("serial-qualified profile saves", serial_service.store.save_profile(qualified).ok)
	check("distinct serial identifies one radio despite duplicate family", serial_service.is_ui_device(51) and not serial_service.is_ui_device(52) \
		and serial_service.select_devices(51, 51))
	var serial_session := FakeSession.new()
	serial_service.attach_session(serial_session)
	serial_devices.append(_device(53, "unique-C"))
	serial_service.refresh()
	check("other serials do not steal or invalidate selected UI", serial_service.registry.selected_device_id("ui") == 51 \
		and serial_service.is_ui_device(51) and not serial_service.is_ui_device(53))
	serial_devices.append(_device(54, "unique-A"))
	serial_service.refresh()
	check("duplicate exact serial revokes UI selection without transferring ownership", serial_service.registry.selected_device_id("ui") == -1 \
		and not serial_service.is_ui_device(51) and not serial_service.is_ui_device(54) \
		and serial_service.registry.selected_device_id("flight") == 51)
	serial_service.free()
	serial_session.free()


func _rollback() -> void:
	var path := _path("rollback")
	var devices: Array = [_device(5, "flight-pad", false, "flight-pad-guid"), _device(10, "radio-A")]
	var service := _service(path, devices)
	var radio := _radio("radio-A")
	check("rollback radio fixture saves", service.store.save_profile(radio).ok)
	var session := FakeSession.new()
	service.attach_session(session)
	var flight := Profile.defaults()
	flight.name = "Active flight pad"
	var initial: Dictionary = service.save_settings_from_setup(flight, 5, 10)
	check("rollback baseline selects distinct radio menu", initial.ok and service.registry.selected_device_id("ui") == 10, str(initial))
	var before: Dictionary = service.store.load_all()
	var previous_runtime := session.current_profile.duplicate(true)
	var notifications: Array[int] = []
	service.ui_selection_changed.connect(func(id: int) -> void: notifications.append(id))
	var rejected := flight.duplicate(true)
	rejected.name = "Refuse after write"
	session.reject_name = rejected.name
	var failed: Dictionary = service.save_settings_from_setup(rejected, 5, -1)
	var after: Dictionary = service.store.load_all()
	check("runtime refusal reports failed transaction", not failed.ok)
	check("runtime refusal restores profiles and menu preference", after.ok and after.profiles == before.profiles \
		and after.ui_preference == before.ui_preference, str([before.ui_preference, after.ui_preference, failed]))
	check("runtime refusal restores both selections and old active route", service.registry.selected_device_id("flight") == 5 \
		and service.registry.selected_device_id("ui") == 10 and session.current_profile == previous_runtime and notifications.is_empty())
	service.free()
	session.free()
	var parent := _path("not_directory")
	var file := FileAccess.open(parent, FileAccess.WRITE)
	file.store_string("not a directory")
	file.close()
	var failed_service := _service(parent.path_join("profiles.cfg"), devices)
	var failed_session := FakeSession.new()
	failed_service.attach_session(failed_session)
	var no_write: Dictionary = failed_service.save_settings_from_setup(Profile.defaults(), 5, 5)
	check("failed storage write leaves selection and runtime untouched", not no_write.ok \
		and failed_service.registry.selected_device_id("flight") == -1 and failed_service.registry.selected_device_id("ui") == -1 \
		and failed_session.apply_count == 0)
	failed_service.free()
	failed_session.free()


func _calibration_invalidates() -> void:
	var path := _path("calibration")
	var devices: Array = [_device(10, "cal-radio")]
	var service := _service(path, devices)
	var verified := _radio("cal-radio")
	var preference := {"mode": "profile", "profile_id": verified.profile_id}
	check("calibration verification fixture saves", service.store.save_profile_with_ui_preference(verified, preference).ok and service.select_devices(10, 10))
	var session := FakeSession.new()
	service.attach_session(session)
	var measured: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	measured.roll.axis = 5
	var prior: Dictionary = service.store.load_all()
	session.reject_roll_axis = 5
	var rejected: Dictionary = service.save_calibration(measured)
	var after_rejection: Dictionary = service.store.load_all()
	check("rejected recalibration restores profile and preference", not rejected.ok and after_rejection.profiles == prior.profiles \
		and after_rejection.ui_preference == prior.ui_preference)
	check("rejected recalibration preserves verified menu ownership", service.is_ui_device(10) and service.registry.selected_device_id("ui") == 10)
	session.reject_roll_axis = -1
	var result: Dictionary = service.save_calibration(measured)
	var current: Dictionary = service.profile_for_device(10)
	check("recalibration succeeds and invalidates navigation evidence", result.ok and current.roll.axis == 5 \
		and not Menu.is_verified(current) and not current.has("ui_navigation"), str(result))
	check("recalibration immediately removes ineligible radio UI ownership", not service.is_ui_device(10) \
		and service.registry.selected_device_id("ui") == -1,
		str([service.is_ui_device(10), service.registry.selected_device_id("ui")]))
	service.free()
	session.free()
