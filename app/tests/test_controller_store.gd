extends SceneTree

const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")

const PROFILE_PATH := "user://controller_core_store_test.cfg"
const CORRUPT_PATH := "user://controller_core_store_corrupt.cfg"
const LEGACY_PATH := "user://controller_core_legacy_test.cfg"
const DEVICE_KEY := "fake-guid|1209:4f54|Test EdgeTX"

var checks := 0
var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_global(path))


func _clean(path: String) -> void:
	for suffix in ["", ".tmp", ".rollback"]:
		_remove_file(path + suffix)


func _initialize() -> void:
	_clean(PROFILE_PATH)
	_clean(CORRUPT_PATH)
	_clean(LEGACY_PATH)
	var store := Store.new(PROFILE_PATH, LEGACY_PATH)
	var loaded := store.load_all()
	check("missing store is an empty successful result", loaded.ok and loaded.profiles.is_empty())

	var profile := Profile.defaults("gamepad", "mode2")
	var saved := store.save_profile(profile)
	check("valid candidate saves", saved.ok, str(saved.error))
	check("save returns a detached saved profile", saved.ok and saved.profile.profile_id == profile.profile_id)
	loaded = store.load_all()
	check("saved V2 profile reloads", loaded.ok and loaded.profiles.size() == 1 and loaded.profiles[0] == profile, str(loaded))
	var updated: Dictionary = profile.duplicate(true)
	updated.name = "Living room pad"
	check("save replaces matching UUID", store.save_profile(updated).ok and store.load_all().profiles.size() == 1 and store.load_all().profiles[0].name == "Living room pad")
	var before_invalid_save: PackedByteArray = FileAccess.get_file_as_bytes(PROFILE_PATH)
	var invalid: Dictionary = updated.duplicate(true)
	invalid.roll.deadzone = NAN
	var failed := store.save_profile(invalid)
	check("invalid profile does not save", not failed.ok and not failed.error.is_empty())
	check("invalid save leaves existing bytes unchanged", FileAccess.get_file_as_bytes(PROFILE_PATH) == before_invalid_save)

	# A blocked temp path simulates an I/O failure after a working profile exists.
	var temp_path := PROFILE_PATH + ".tmp"
	DirAccess.make_dir_absolute(_global(temp_path))
	var changed: Dictionary = updated.duplicate(true)
	changed.name = "Must not replace old profile"
	var io_failure := store.save_profile(changed)
	check("temporary write failure is surfaced", not io_failure.ok)
	check("temporary write failure preserves previous stored profile", store.load_all().ok and store.load_all().profiles[0].name == "Living room pad")
	var remove_dir_error: Error = DirAccess.remove_absolute(_global(temp_path))
	check("test temp directory cleans up", remove_dir_error == OK)

	# The importer must be read-only and preserve the old radio mapping and AUX data.
	var legacy: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	legacy["aux"] = {"smoke": {"type": "axis", "axis": 9, "invert": false, "off": -1.0, "on": 1.0}}
	var legacy_save_error: Error = RcCalibration.save_profile(LEGACY_PATH, DEVICE_KEY, legacy)
	check("legacy calibration fixture saves", legacy_save_error == OK)
	var legacy_bytes: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_PATH)
	var empty_primary_store := Store.new("user://controller_core_import_not_saved.cfg", LEGACY_PATH)
	_clean("user://controller_core_import_not_saved.cfg")
	var imported := empty_primary_store.import_legacy_radio()
	check("legacy import returns one radio candidate", imported.ok and imported.profiles.size() == 1 and imported.profiles[0].kind == "radio", str(imported))
	if imported.profiles.size() == 1:
		var imported_profile: Dictionary = imported.profiles[0]
		check("imported legacy identity is attached", imported_profile.association.get("legacy_device_key", "") == DEVICE_KEY)
		check("imported smoke AUX survives", imported_profile.get("aux", {}).get("smoke", {}).get("axis", -1) == 9)
		var original := RcCalibration.load_profile(LEGACY_PATH, DEVICE_KEY)
		var equivalent := true
		for axis in [-1.0, -0.4, 0.0, 0.7, 1.0]:
			for channel in ["roll", "pitch", "yaw"]:
				equivalent = equivalent and absf(Profile.normalize_axis(axis, imported_profile[channel]) - RcInput.normalize(axis, original[channel])) < 1e-12
			equivalent = equivalent and absf(Profile.normalize_axis(axis, imported_profile.throttle) - RcInput.normalize_throttle(axis, original.throttle)) < 1e-12
		check("legacy imported radio output is unchanged", equivalent)
	check("legacy import does not mutate original file", FileAccess.get_file_as_bytes(LEGACY_PATH) == legacy_bytes)
	check("legacy import does not save a V2 primary store", not FileAccess.file_exists("user://controller_core_import_not_saved.cfg"))

	# Match evidence is strict and duplicate connected identity is ambiguous.
	var associated: Dictionary = Profile.defaults("radio", "radio_custom")
	associated.association = {"serial_number": "S-1", "vendor_id": "4617", "product_id": "20308"}
	var match_store := Store.new("user://controller_core_match_test.cfg", LEGACY_PATH)
	_clean("user://controller_core_match_test.cfg")
	check("association profile saves", match_store.save_profile(associated).ok)
	var info := {"id": 4, "serial_number": "S-1", "vendor_id": 4617, "product_id": 20308}
	var connected := [{"id": 4, "serial_number": "S-1", "vendor_id": "4617", "product_id": "20308", "connected": true}]
	check("decimal/string metadata match a unique connected serial", match_store.match_profile(info, connected).profile_id == associated.profile_id)
	check("detached matching device is ignored", match_store.match_profile(info, [{"id": 4, "serial_number": "S-1", "vendor_id": 4617, "product_id": 20308, "connected": false}]).is_empty())
	check("missing connected flag is not proof of active identity", match_store.match_profile(info, [{"id": 4, "serial_number": "S-1", "vendor_id": 4617, "product_id": 20308}]).is_empty())
	check("duplicate connected serial is ambiguous", match_store.match_profile(info, [connected[0], {"id": 8, "serial_number": "S-1", "vendor_id": 4617, "product_id": 20308, "connected": true}]).is_empty())
	check("no connected snapshot is conservatively ambiguous", match_store.match_profile(info).is_empty())

	var family_profile: Dictionary = Profile.defaults("gamepad", "mode2")
	family_profile.association = {"guid": "family", "vendor_id": 4617, "product_id": 20308}
	check("family association profile saves", match_store.save_profile(family_profile).ok)
	var family_info := {"id": 10, "guid": "family", "vendor_id": "4617", "product_id": "20308"}
	var family_devices := [family_info.duplicate(true)]
	family_devices[0].connected = true
	check("GUID and USB IDs match a unique active device", match_store.match_profile(family_info, family_devices).is_empty() == false)
	family_devices.append({"id": 11, "guid": "family", "vendor_id": 4617, "product_id": 20308, "connected": false})
	check("detached duplicate does not make identity ambiguous", not match_store.match_profile(family_info, family_devices).is_empty())
	family_devices.append({"id": 12, "guid": "family", "vendor_id": 4617, "product_id": 20308, "connected": true})
	check("second active family identity blocks association", match_store.match_profile(family_info, family_devices).is_empty())

	var strong_store := Store.new("user://controller_core_strong_match_test.cfg", LEGACY_PATH)
	_clean("user://controller_core_strong_match_test.cfg")
	var strong_profile: Dictionary = Profile.defaults("radio", "radio_custom")
	strong_profile.association = {"legacy_device_key": "shared-legacy-key", "serial_number": "serial-A", "vendor_id": 4617, "product_id": 20308}
	check("strong identity fixture saves", strong_store.save_profile(strong_profile).ok)
	var wrong_serial := {"device_key": "shared-legacy-key", "serial_number": "serial-B", "vendor_id": 4617, "product_id": 20308}
	check("serial mismatch cannot fall back to a matching legacy key", strong_store.profiles_for_device(wrong_serial).is_empty() and strong_store.match_profile(wrong_serial, [{"id": 20, "device_key": "shared-legacy-key", "serial_number": "serial-B", "vendor_id": 4617, "product_id": 20308, "connected": true}]).is_empty())

	var corrupt_cfg := ConfigFile.new()
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "schema_version", 99)
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "profiles", [])
	check("unknown version fixture writes", corrupt_cfg.save(CORRUPT_PATH) == OK)
	var corrupt_store := Store.new(CORRUPT_PATH, LEGACY_PATH)
	var corrupt_bytes: PackedByteArray = FileAccess.get_file_as_bytes(CORRUPT_PATH)
	check("unknown profile store schema is rejected", not corrupt_store.load_all().ok)
	check("save refuses to overwrite unknown schema", not corrupt_store.save_profile(Profile.defaults()).ok and FileAccess.get_file_as_bytes(CORRUPT_PATH) == corrupt_bytes)

	# A valid rollback copy recovers a damaged primary, and is reported.
	var rollback_path := "user://controller_core_rollback_test.cfg"
	_clean(rollback_path)
	var rollback_store := Store.new(rollback_path, LEGACY_PATH)
	check("rollback fixture profile saves", rollback_store.save_profile(Profile.defaults()).ok)
	var rollback_copy_error := DirAccess.copy_absolute(_global(rollback_path), _global(rollback_path + ".rollback"))
	check("rollback fixture copied", rollback_copy_error == OK)
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "schema_version", 999)
	corrupt_cfg.set_value(Store.STORAGE_SECTION, "profiles", [])
	check("rollback primary corruption writes", corrupt_cfg.save(rollback_path) == OK)
	var recovered := rollback_store.load_all()
	check("valid rollback copy recovers unreadable primary", recovered.ok and recovered.get("recovered_from_backup", false) and recovered.profiles.size() == 1)

	for path in [PROFILE_PATH, CORRUPT_PATH, LEGACY_PATH, "user://controller_core_import_not_saved.cfg", "user://controller_core_match_test.cfg", "user://controller_core_rollback_test.cfg", "user://controller_core_strong_match_test.cfg"]:
		_clean(path)
	print("Controller profile store: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
