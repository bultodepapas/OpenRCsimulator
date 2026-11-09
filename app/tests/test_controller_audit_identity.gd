extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const Flight := preload("res://sim/flight_session.gd")
const Helicopter := preload("res://sim/helicopter_flight_session.gd")
const PATH := "user://controller_audit_identity_test.cfg"
const LEGACY := "user://controller_audit_identity_legacy_test.cfg"

var checks := 0
var failures := 0


class FakeSession extends Node:
	var radio := RcInput.new()
	var _controller_lost := false
	var external_controller_selection := false
	var persist_controller_profile := Callable()
	var persist_full_controller_profile := Callable()
	func apply_controller_selection(id: int, info: Dictionary, profile: Dictionary, _initial: bool) -> bool:
		if id < 0:
			radio.disconnect_device()
			_controller_lost = false
			return true
		if profile.is_empty():
			_controller_lost = true
			return false
		radio.connect_device(id, info, profile)
		_controller_lost = false
		return true
	func controller_disconnected() -> void:
		radio.disconnect_device()
		_controller_lost = true


class FinishedCalibration extends RefCounted:
	var profile: Dictionary
	func _init(value: Dictionary) -> void:
		profile = value.duplicate(true)
	func advance(_axes: PackedFloat64Array) -> bool:
		return true


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func device(id: int, serial: String = "") -> Dictionary:
	return {"id": id, "name": "EdgeTX duplicate radio", "raw_name": "EdgeTX duplicate radio",
		"guid": "duplicate-radio-guid", "vendor_id": 4617, "product_id": 20308,
		"kind": "radio", "known": false, "serial_number": serial}


func clean() -> void:
	for base in [PATH, LEGACY]:
		for suffix in ["", ".tmp", ".rollback"]:
			var path: String = base + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	clean()
	var legacy: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	legacy.roll.axis = 7
	var first := device(1)
	var second := device(2)
	check("legacy fixture saves", Calibration.save_profile(LEGACY, RcInput.key_for(1, first), legacy) == OK)
	var legacy_bytes := FileAccess.get_file_as_bytes(LEGACY)
	var observed: Array = [first]
	var service := Service.new()
	service.store = Service.Store.new(PATH, LEGACY)
	service.enumerate_devices = func() -> Array: return observed
	service.refresh()
	var cached: Dictionary = service.profile_for_device(1)
	check("unique legacy identity loads", cached.get("roll", {}).get("axis", -1) == 7)
	var session := FakeSession.new()
	service.attach_session(session)
	check("unique legacy mapping binds to current session", session.radio.connected and session.radio.profile.get("roll", {}).get("axis", -1) == 7)
	var generation: int = service.registry.connection_generation(1)
	observed.append(second)
	service.refresh()
	check("duplicate arrival invalidates the cached match for the newcomer", service.registry.connection_generation(1) > generation and service.profile_for_device(2).is_empty())
	check("uninterrupted current connection stays session-bound", service.registry.selected_device_id("flight") == 1 and session.radio.connected and session.radio.device_id == 1 and session.radio.profile.get("roll", {}).get("axis", -1) == 7)
	check("all consumers keep the exact bound profile during ambiguity", service.profile_for_device(1) == session.radio.profile and service.profile_for_device(1).get("actions", {}) == cached.get("actions", {}))
	service.refresh()
	check("repeated duplicate snapshot cannot recover cached calibration", service.profile_for_device(2).is_empty())
	observed.remove_at(0)
	service.refresh()
	check("disconnect never transfers active ownership", service.registry.selected_device_id("flight") == -1 and session._controller_lost and not session.radio.connected)
	check("remaining unique identity can be selected explicitly", service.select_devices(2, -1) and session.radio.profile.get("roll", {}).get("axis", -1) == 7)
	observed.append(first)
	service.refresh()
	observed.remove_at(0)
	service.refresh()
	observed.append(second)
	service.refresh()
	check("same handle reconnect among duplicates does not borrow the old cache", service.registry.selected_device_id("flight") == -1 and service.profile_for_device(1).is_empty() and service.profile_for_device(2).is_empty())
	var explicit := Profile.upgrade_legacy(legacy)
	var saved: Dictionary = service.save_settings_from_setup(explicit, 2, -1)
	check("explicit current-connection recovery applies the chosen profile", saved.get("ok", false) and session.radio.connected and session.radio.device_id == 2 and session.radio.profile.get("roll", {}).get("axis", -1) == 7)
	check("ambiguous persisted association is not an automatic match", service.store.match_profile(service.registry.device_for_id(2), service.registry.get_devices()).is_empty())
	service.attach_session(null)
	session.free()
	service.free()
	clean()

	# Family duplicates do not prevent matching a distinct, serial-qualified V2 profile.
	var strong := Profile.defaults("radio", "radio_custom")
	strong.association = {"guid": "duplicate-radio-guid", "vendor_id": 4617, "product_id": 20308, "serial_number": "serial-A"}
	observed = [device(3, "serial-A"), device(4, "serial-B")]
	service = Service.new()
	service.store = Service.Store.new(PATH, LEGACY)
	service.enumerate_devices = func() -> Array: return observed
	check("serial-qualified profile fixture saves", service.store.save_profile(strong).ok)
	service.refresh()
	check("serial-qualified V2 survives family ambiguity", service.profile_for_device(3).get("profile_id", "") == strong.profile_id and service.profile_for_device(4).is_empty())
	observed.clear()
	observed.append_array([device(8, "serial-B"), device(9, "serial-A")])
	service.refresh()
	check("serial-qualified V2 follows swapped handles", service.profile_for_device(9).get("profile_id", "") == strong.profile_id and service.profile_for_device(8).is_empty())
	service.free()
	clean()

	check("direct legacy fixture saves", Calibration.save_profile(LEGACY, RcInput.key_for(1, first), legacy) == OK)
	for session_kind in ["fixed wing", "helicopter"]:
		check(session_kind + " starts from the same legacy fixture", Calibration.save_profile(LEGACY, RcInput.key_for(1, first), legacy) == OK)
		legacy_bytes = FileAccess.get_file_as_bytes(LEGACY)
		var direct: Node = Flight.new() if session_kind == "fixed wing" else Helicopter.new()
		if session_kind == "fixed wing":
			direct.physics_enabled = false
			direct.setup()
		direct.profiles_path = LEGACY
		var ids: Array = [1]
		direct.connected_device_ids = func() -> Array: return ids
		direct.device_info = func(id: int) -> Dictionary: return device(id)
		direct._on_joy_connection_changed(1, true)
		check(session_kind + " direct unique legacy loads", direct.radio.profile.get("roll", {}).get("axis", -1) == 7)
		ids.append(2)
		direct._on_joy_connection_changed(2, true)
		check(session_kind + " duplicate arrival retains current handle", direct.radio.device_id == 1 and direct.radio.profile.get("roll", {}).get("axis", -1) == 7)
		var updated := legacy.duplicate(true)
		updated.roll.axis = 6
		direct.calibration = FinishedCalibration.new(updated)
		direct.advance_calibration()
		check(session_kind + " ambiguous direct calibration is not persisted", FileAccess.get_file_as_bytes(LEGACY) == legacy_bytes and "NOT saved" in direct.pause_reason)
		direct._on_joy_connection_changed(1, false)
		direct._on_joy_connection_changed(2, true)
		check(session_kind + " direct duplicate cannot load legacy calibration", direct.radio.device_id == 2 and not direct.radio.profile.get("configured", false) and not direct.radio.armed)
		ids.remove_at(0)
		direct.calibration = FinishedCalibration.new(updated)
		direct.advance_calibration()
		var newly_saved: Dictionary = Calibration.load_profile(LEGACY, RcInput.key_for(2, second))
		check(session_kind + " first calibration uses clean radio actions and persists them", direct.radio.profile.get("actions", {}) == Profile.ControllerActions.clean_radio_bindings() and newly_saved.get("actions", {}) == Profile.ControllerActions.clean_radio_bindings())
		direct.free()
	clean()
	print("Controller audit identity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
