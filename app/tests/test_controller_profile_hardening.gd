extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")

const RECOVERY_PATH := "user://controller_audit_recovery.cfg"
const CORRUPT_PATH := "user://controller_audit_corrupt.cfg"
const CORRUPT_LEGACY_PATH := "user://controller_audit_corrupt_legacy.cfg"
const CALIBRATION_PATH := "user://controller_audit_calibration.cfg"
const CALIBRATION_LEGACY_PATH := "user://controller_audit_calibration_legacy.cfg"
const WATCHDOG_PATH := "user://controller_audit_watchdog.cfg"
const WATCHDOG_LEGACY_PATH := "user://controller_audit_watchdog_legacy.cfg"

var checks := 0
var failures := 0


class FakeSession extends Node:
	var reject_trigger := false
	var reject_name := ""
	var apply_count := 0
	var disconnected_count := 0
	var _controller_lost := false
	var external_controller_selection := false
	var persist_controller_profile: Callable
	var persist_full_controller_profile: Callable
	var last_profile_id := ""
	var radio := {"connected": true}

	func controller_profile_rejection(profile: Dictionary) -> String:
		if reject_trigger and profile.get("throttle_mode", "") == "trigger_absolute":
			return "trigger profile refused by fixture"
		return ""

	func apply_controller_selection(_id: int, _info: Dictionary, profile: Dictionary, _initial_start := false) -> bool:
		apply_count += 1
		last_profile_id = str(profile.get("profile_id", ""))
		return str(profile.get("name", "")) != reject_name

	func controller_disconnected() -> void:
		disconnected_count += 1
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


func _service(storage_path: String, legacy_path: String, devices: Array) -> Service:
	var service := Service.new()
	service.store = Store.new(storage_path, legacy_path)
	service.enumerate_devices = func() -> Array: return devices
	service.refresh()
	return service


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in [RECOVERY_PATH, CORRUPT_PATH, CORRUPT_LEGACY_PATH, CALIBRATION_PATH, CALIBRATION_LEGACY_PATH, WATCHDOG_PATH, WATCHDOG_LEGACY_PATH]:
		_clean(path)

	var invalid_serial: Dictionary = Profile.defaults()
	invalid_serial.association = {"serial_number": 4}
	check("profile rejects non-string serial identity", not Profile.validate(invalid_serial).ok)
	var invalid_vendor: Dictionary = Profile.defaults()
	invalid_vendor.association = {"vendor_id": "999999999999999999999"}
	check("profile rejects oversized string USB identity", not Profile.validate(invalid_vendor).ok)
	var valid_string_ids: Dictionary = Profile.defaults()
	valid_string_ids.association = {"vendor_id": "4617", "product_id": "20308"}
	check("profile accepts bounded decimal USB identities", Profile.validate(valid_string_ids).ok)

	# A corrupt rollback copy beside a missing primary is recovery evidence, not an empty store.
	var unsupported_backup := ConfigFile.new()
	unsupported_backup.set_value(Store.STORAGE_SECTION, "schema_version", 99)
	unsupported_backup.set_value(Store.STORAGE_SECTION, "profiles", [])
	check("unsupported rollback fixture writes", unsupported_backup.save(RECOVERY_PATH + ".rollback") == OK)
	var damaged_store := Store.new(RECOVERY_PATH, "user://unused_legacy.cfg")
	var backup_bytes: PackedByteArray = FileAccess.get_file_as_bytes(RECOVERY_PATH + ".rollback")
	check("unreadable rollback without a primary is reported", not damaged_store.load_all().ok)
	check("save refuses to erase an unreadable recovery artifact", not damaged_store.save_profile(Profile.defaults()).ok)
	check("failed recovery save preserves rollback bytes and missing primary", FileAccess.get_file_as_bytes(RECOVERY_PATH + ".rollback") == backup_bytes and not FileAccess.file_exists(RECOVERY_PATH))

	# An unreadable V2 store must not silently fall through to the older calibration file.
	var corrupt_cfg := ConfigFile.new()
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "schema_version", 99)
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "profiles", [])
	check("corrupt V2 fixture writes", corrupt_cfg.save(CORRUPT_PATH) == OK)
	var radio_legacy_error: Error = RcCalibration.save_profile(CORRUPT_LEGACY_PATH, "radio-key", RcInput.DEFAULT_PROFILE)
	check("legacy fallback fixture writes", radio_legacy_error == OK)
	var corrupt_devices := [{"id": 31, "name": "EdgeTX audit radio", "raw_name": "EdgeTX audit radio", "guid": "audit-radio", "kind": "radio", "known": false}]
	var corrupt_service := _service(CORRUPT_PATH, CORRUPT_LEGACY_PATH, corrupt_devices)
	check("corrupt V2 storage blocks legacy mapping fallback", corrupt_service.profile_for_device(31).is_empty())
	corrupt_service.free()

	# Recalibration changes only calibration channels and retains unrelated V2 settings.
	var calibration_device := {"id": 82, "name": "EdgeTX calibration radio", "raw_name": "EdgeTX calibration radio", "guid": "calibration-radio", "kind": "radio", "known": false, "vendor_id": 200, "product_id": 2, "serial_number": "cal-serial"}
	var calibration_service := _service(CALIBRATION_PATH, CALIBRATION_LEGACY_PATH, [calibration_device])
	var previous := Profile.defaults("radio", "radio_custom")
	previous.name = "Preserve custom values"
	previous.throttle_rate = 1.7
	previous.idle_threshold = 0.12
	previous.neutral_duration_ms = 825
	previous.require_release = false
	previous.presentation.rumble_intensity = 0.25
	previous.aux = {"smoke": {"type": "axis", "axis": 8, "invert": false, "off": -1.0, "on": 1.0}}
	previous.association = {"serial_number": "cal-serial", "vendor_id": 200, "product_id": 2}
	check("custom calibration profile seed saves", calibration_service.store.save_profile(previous).ok)
	var calibration_session := FakeSession.new()
	calibration_service.session = calibration_session
	check("calibration device selection succeeds", calibration_service.select_devices(82, -1))
	var calibrated := RcInput.DEFAULT_PROFILE.duplicate(true)
	calibrated.throttle.axis = 8
	var calibration_result: Dictionary = calibration_service.save_calibration(calibrated)
	var after_calibration: Dictionary = {}
	var calibration_loaded: Dictionary = calibration_service.store.load_all()
	if calibration_loaded.ok:
		for saved_profile in calibration_loaded.profiles:
			if saved_profile.profile_id == previous.profile_id:
				after_calibration = saved_profile
	check("calibration save succeeds", calibration_result.get("ok", false), str(calibration_result.get("error", "")))
	check("calibration preserves UUID, name, and scalar settings", after_calibration.get("profile_id", "") == previous.profile_id and after_calibration.get("name", "") == previous.name and after_calibration.get("throttle_rate", 0.0) == 1.7 and after_calibration.get("idle_threshold", 0.0) == 0.12 and after_calibration.get("neutral_duration_ms", 0) == 825 and after_calibration.get("require_release", true) == false)
	check("calibration preserves presentation but drops AUX colliding with a new flight axis", after_calibration.get("presentation", {}).get("rumble_intensity", 0.0) == 0.25 and after_calibration.get("aux", {}).is_empty())
	check("calibrated throttle axis is applied", after_calibration.get("throttle", {}).get("axis", -1) == 8)

	# Route refusal is preflighted; a later unexpected session refusal rolls back storage and cache.
	var reject_device := {"id": 83, "name": "EdgeTX rejection radio", "raw_name": "EdgeTX rejection radio", "guid": "reject-radio", "kind": "radio", "known": false, "vendor_id": 201, "product_id": 2, "serial_number": "reject-serial"}
	calibration_service.enumerate_devices = func() -> Array: return [calibration_device, reject_device]
	calibration_service.refresh()
	check("rejection fixture selection succeeds", calibration_service.select_devices(83, -1))
	calibration_session.reject_trigger = true
	var trigger_profile := Profile.defaults("gamepad", "trigger_absolute")
	var rejection_before := calibration_session.apply_count
	check("profile activation refusal leaves active profile untouched", not calibration_service.apply_profile(trigger_profile, 83) and calibration_session.apply_count == rejection_before and calibration_service.profile_for_device(83).get("kind", "") == "radio")
	var blocked_setup: Dictionary = calibration_service.save_profile_from_setup(trigger_profile, 83)
	check("setup rejection happens before writing an incompatible profile", not blocked_setup.get("ok", false) and calibration_service.store.load_all().profiles.size() == 1)

	calibration_session.reject_trigger = false
	var unexpected := Profile.defaults("radio", "radio_custom")
	unexpected.name = "Unexpected runtime refusal"
	calibration_session.reject_name = unexpected.name
	var active_before_unexpected: Dictionary = calibration_service.profile_for_device(83)
	var save_before_apply: Dictionary = calibration_service.store.load_all()
	var unexpected_result: Dictionary = calibration_service.save_profile_from_setup(unexpected, 83)
	var save_after_apply: Dictionary = calibration_service.store.load_all()
	check("unexpected session refusal reports save failure", not unexpected_result.get("ok", false))
	check("unexpected session refusal restores the prior stored profile set", save_after_apply.ok and save_after_apply.profiles == save_before_apply.profiles)
	check("unexpected session refusal preserves the previously active profile", calibration_service.profile_for_device(83).get("profile_id", "") == active_before_unexpected.get("profile_id", ""))

	# A newly configured unknown device has no prior runtime profile. The post-write
	# lookup must not mistake the candidate itself for that baseline during rollback.
	var unknown_device := {"id": 84, "name": "Unknown audit stick", "raw_name": "Unknown audit stick", "guid": "unknown-stick", "kind": "joystick", "known": false, "vendor_id": 202, "product_id": 2, "serial_number": "unknown-serial"}
	calibration_service.enumerate_devices = func() -> Array: return [calibration_device, reject_device, unknown_device]
	calibration_service.refresh()
	var observed_profile_ids: Array[String] = []
	calibration_service.flight_selection_changed.connect(func() -> void:
		observed_profile_ids.append(str(calibration_service.profile_for_device(84).get("profile_id", "")))
	)
	check("unknown device selection succeeds before profile configuration", calibration_service.select_devices(84, -1) and calibration_service.profile_for_device(84).is_empty())
	var first_profile := Profile.defaults("joystick", "radio_custom")
	first_profile.name = "First configured unknown stick"
	calibration_session.reject_name = first_profile.name
	var first_save_before: Dictionary = calibration_service.store.load_all()
	var first_rejected: Dictionary = calibration_service.save_profile_from_setup(first_profile, 84)
	var first_save_after: Dictionary = calibration_service.store.load_all()
	check("first setup save can be refused by runtime after persistence", not first_rejected.get("ok", false))
	check("first-save refusal restores storage and leaves no cached candidate", first_save_after.ok and first_save_after.profiles == first_save_before.profiles and calibration_service.profile_for_device(84).is_empty())
	check("first-save refusal restores the unconfigured runtime route", calibration_session.last_profile_id.is_empty())
	check("selection observers see the restored profile after rejection", not observed_profile_ids.is_empty() and observed_profile_ids.back().is_empty())

	var bytes_before_disconnect: PackedByteArray = FileAccess.get_file_as_bytes(CALIBRATION_PATH)
	calibration_service.enumerate_devices = func() -> Array: return []
	calibration_service.refresh()
	var disconnected_result: Dictionary = calibration_service.save_profile_from_setup(Profile.defaults("radio", "radio_custom"), 83)
	check("disconnected setup device cannot be saved by stale ID", not disconnected_result.get("ok", false) and FileAccess.get_file_as_bytes(CALIBRATION_PATH) == bytes_before_disconnect)
	calibration_service.free()
	calibration_session.free()

	# The fresh session boundary resets a stale menu timestamp; subsequent real gaps still disconnect.
	var watchdog_service := _service(WATCHDOG_PATH, WATCHDOG_LEGACY_PATH, [])
	var watchdog_session := FakeSession.new()
	var fake_clock := {"now": 10000}
	watchdog_service.clock_msec = func() -> int: return fake_clock.now
	watchdog_service._last_process_ms = 1
	watchdog_service.attach_session(watchdog_session)
	watchdog_service._process(0.0)
	check("new session ignores only the preceding menu/setup gap", watchdog_session.disconnected_count == 0)
	fake_clock.now = 16001
	watchdog_service._process(0.0)
	check("watchdog still detects a long gap after the session starts", watchdog_session.disconnected_count == 1)
	watchdog_service.free()
	watchdog_session.free()

	for path in [RECOVERY_PATH, CORRUPT_PATH, CORRUPT_LEGACY_PATH, CALIBRATION_PATH, CALIBRATION_LEGACY_PATH, WATCHDOG_PATH, WATCHDOG_LEGACY_PATH]:
		_clean(path)
	print("Controller profile hardening: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
