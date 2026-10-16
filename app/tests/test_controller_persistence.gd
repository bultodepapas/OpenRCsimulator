extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Session := preload("res://sim/flight_session.gd")
const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")

const PROFILE_PATH := "user://controller_persistence_v2_test.cfg"
const LEGACY_PATH := "user://controller_persistence_legacy_test.cfg"

var checks := 0
var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _clean(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	for suffix in ["", ".tmp", ".rollback"]:
		var candidate: String = absolute + str(suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
		elif DirAccess.dir_exists_absolute(candidate):
			DirAccess.remove_absolute(candidate)


func _stored_profile(service: Node, profile_id: String) -> Dictionary:
	var loaded: Dictionary = service.store.load_all()
	if not loaded.ok:
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
	var legacy_seed_error: Error = RcCalibration.save_profile(LEGACY_PATH, "unrelated-legacy-device", RcInput.DEFAULT_PROFILE)
	var legacy_before: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_PATH)
	check("legacy test fixture is isolated and readable", legacy_seed_error == OK and not legacy_before.is_empty())

	var service := Service.new()
	service.store = Service.Store.new(PROFILE_PATH, LEGACY_PATH)
	var observed: Array = [
		{"id": 41, "name": "Persistence Gamepad", "raw_name": "Persistence Gamepad", "guid": "persistence-pad", "known": true, "kind": "gamepad", "vendor_id": 100, "product_id": 1, "serial_number": "pad-serial"},
		{"id": 42, "name": "EdgeTX Persistence Radio", "raw_name": "EdgeTX Persistence Radio", "guid": "persistence-radio", "known": false, "kind": "radio", "vendor_id": 200, "product_id": 2, "serial_number": "radio-serial"},
	]
	service.enumerate_devices = func() -> Array: return observed
	service.refresh()
	check("Home defaults prefer radio flight and gamepad menus", service.registry.selected_device_id("flight") == 42 and service.registry.selected_device_id("ui") == 41)
	check("explicit gamepad flight selection succeeds", service.select_devices(41, -1))

	var session = Session.new()
	session.physics_enabled = false
	session.rate_profile = "normal"
	session.read_axis = func(_id: int, _axis: int) -> float: return 0.0
	session.read_button = func(_id: int, _button: int) -> bool: return false
	session.setup()
	service.attach_session(session)
	check("managed session receives full-profile and calibration callbacks", session.persist_full_controller_profile.is_valid() and session.persist_controller_profile.is_valid())
	var gamepad_profile: Dictionary = session.radio.profile.duplicate(true)
	var smoke_binding := {"type": "button", "button": 11, "mode": "toggle_edge"}
	gamepad_profile["aux"] = {"smoke": smoke_binding}
	var restart_binding := {"type": "axis", "axis": 9, "sign": 1, "threshold": 0.65}
	gamepad_profile.actions = {"restart_flight": restart_binding, "flaps_cycle": {"type": "unbound"}}
	var saved: Dictionary = session.persist_full_controller_profile.call(gamepad_profile)
	var gamepad_id := str(gamepad_profile.get("profile_id", ""))
	var stored_gamepad := _stored_profile(service, gamepad_id)
	check("managed AUX save succeeds", saved.get("ok", false), str(saved.get("error", "")))
	check("AUX is persisted inside the V2 controller profile", stored_gamepad.get("aux", {}).get("smoke", {}) == smoke_binding)
	check("restart channel and cleared flap default survive disk reload", stored_gamepad.get("actions", {}) == gamepad_profile.actions)
	check("managed session applies the saved AUX profile", session.radio.profile.get("aux", {}).get("smoke", {}) == smoke_binding)
	check("AUX save leaves legacy calibration bytes unchanged", FileAccess.get_file_as_bytes(LEGACY_PATH) == legacy_before)

	var profile_bytes_before_invalid: PackedByteArray = FileAccess.get_file_as_bytes(PROFILE_PATH)
	var invalid_gamepad: Dictionary = session.radio.profile.duplicate(true)
	invalid_gamepad["roll"]["axis"] = 99
	var rejected: Dictionary = session.persist_full_controller_profile.call(invalid_gamepad)
	check("invalid full-profile save is rejected", not rejected.get("ok", false))
	check("invalid full-profile save preserves old V2 bytes", FileAccess.get_file_as_bytes(PROFILE_PATH) == profile_bytes_before_invalid)
	check("invalid save leaves active AUX profile unchanged", session.radio.profile.get("aux", {}).get("smoke", {}) == smoke_binding)

	observed.clear()
	service.refresh()
	check("disconnect pauses managed session and clears selection", session._controller_lost and service.registry.selected_device_id("flight") == -1)
	observed.append({"id": 41, "name": "Persistence Gamepad", "raw_name": "Persistence Gamepad", "guid": "persistence-pad", "known": true, "kind": "gamepad", "vendor_id": 100, "product_id": 1, "serial_number": "pad-serial"})
	observed.append({"id": 42, "name": "EdgeTX Persistence Radio", "raw_name": "EdgeTX Persistence Radio", "guid": "persistence-radio", "known": false, "kind": "radio", "vendor_id": 200, "product_id": 2, "serial_number": "radio-serial"})
	service.refresh()
	check("same-ID reconnect is not automatically selected", service.registry.selected_device_id("flight") == -1 and not session.radio.connected)
	var reselection_ok: bool = service.select_devices(41, -1)
	check("explicit re-selection reloads the saved AUX profile", reselection_ok and session.radio.profile.get("aux", {}).get("smoke", {}) == smoke_binding, str(service.registry.get_devices()) + " / " + str(session.radio.profile.get("aux", {})))
	check("reconnect restores restart channel and intentional Clear", session.radio.profile.get("actions", {}) == gamepad_profile.actions)
	check("legacy calibration remains unchanged after reconnect", FileAccess.get_file_as_bytes(LEGACY_PATH) == legacy_before)

	check("explicit radio selection succeeds", service.select_devices(42, -1), str(service.registry.get_devices()))
	var radio_before: Dictionary = service.profile_for_device(42)
	var calibration := RcInput.DEFAULT_PROFILE.duplicate(true)
	calibration["aux"] = {"smoke": {"type": "button", "button": 12, "mode": "level"}}
	var calibration_result: Dictionary = session.persist_controller_profile.call(calibration)
	var calibrated: Dictionary = _stored_profile(service, str(radio_before.get("profile_id", "")))
	check("managed radio calibration saves", calibration_result.get("ok", false), str(calibration_result.get("error", "")))
	check("calibration preserves radio role and profile UUID", calibrated.get("kind", "") == "radio" and calibrated.get("profile_id", "") == radio_before.get("profile_id", ""))
	check("calibration preserves profile name, actions, and presentation", calibrated.get("name", "") == radio_before.get("name", "") and calibrated.get("actions", {}) == radio_before.get("actions", {}) and calibrated.get("presentation", {}) == radio_before.get("presentation", {}))
	check("calibration preserves valid AUX data", calibrated.get("aux", {}).get("smoke", {}).get("button", -1) == 12)
	check("calibration leaves legacy file unchanged", FileAccess.get_file_as_bytes(LEGACY_PATH) == legacy_before)

	observed.append({"id": 43, "name": "Custom unknown pad", "guid": "custom-pad", "known": false, "vendor_id": 300, "product_id": 3, "serial_number": "custom-serial"})
	service.refresh()
	check("unknown hardware cannot claim menu ownership before configuration", not service.is_ui_gamepad(43) and not service.select_devices(42, 43))
	var custom: Dictionary = Service.Profile.defaults()
	custom.association = {"guid": "custom-pad", "vendor_id": 300, "product_id": 3, "serial_number": "custom-serial"}
	check("explicit gamepad declaration can be saved for unknown hardware", service.store.save_profile(custom).ok)
	check("saved custom gamepad can be deliberately selected for menus", service.is_ui_gamepad(43) and service.select_devices(42, 43))
	check("radio remains isolated from menus after custom gamepad setup", not service.is_ui_gamepad(42) and service.registry.selected_device_id("flight") == 42)

	service.attach_session(null)
	session.free()
	service.free()
	_clean(PROFILE_PATH)
	_clean(LEGACY_PATH)
	print("Controller persistence: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
