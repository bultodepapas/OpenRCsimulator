extends RefCounted
## Versioned, transactional storage for controller profiles.

const ControllerProfile := preload("res://input/controller_profile.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")

const DEFAULT_PATH := "user://controller_profiles.cfg"
const LEGACY_PATH := "user://rc_calibration.cfg"
const STORAGE_SECTION := "controller_profiles"
const BACKUP_SUFFIX := ".rollback"
const TEMP_SUFFIX := ".tmp"

var path: String
var legacy_path: String


func _init(storage_path: String = DEFAULT_PATH, legacy_storage_path: String = LEGACY_PATH) -> void:
	path = storage_path
	legacy_path = legacy_storage_path


## Loads all profiles as candidates. A bad version or bad member rejects the file as a whole.
func load_all() -> Dictionary:
	var primary := _read_file(path)
	if primary.ok:
		return {"ok": true, "profiles": primary.profiles, "errors": []}
	var backup_path := path + BACKUP_SUFFIX
	var backup_exists := FileAccess.file_exists(backup_path)
	if backup_exists:
		var backup := _read_file(backup_path)
		if backup.ok:
			return {"ok": true, "profiles": backup.profiles, "errors": ["Recovered profiles from rollback copy; primary storage is unreadable."], "recovered_from_backup": true}
		if primary.missing:
			return {"ok": false, "profiles": [], "errors": ["Primary profile storage is missing and its rollback copy is unreadable: " + backup.error]}
	if primary.missing:
		return {"ok": true, "profiles": [], "errors": []}
	return {"ok": false, "profiles": [], "errors": [primary.error]}


## Validates and atomically replaces one profile by profile_id. A failed write keeps the previous file.
func save_profile(candidate: Variant) -> Dictionary:
	var validation := ControllerProfile.validate(candidate)
	if not validation.ok:
		return {"ok": false, "profile": {}, "error": "Invalid controller profile: " + "; ".join(validation.errors)}
	var loaded := load_all()
	if not loaded.ok:
		return {"ok": false, "profile": {}, "error": "Existing controller profile storage is unreadable: " + "; ".join(loaded.errors)}
	var profiles: Array = loaded.profiles.duplicate(true)
	var saved_profile: Dictionary = candidate.duplicate(true)
	var found := false
	for index in profiles.size():
		if profiles[index].profile_id == saved_profile.profile_id:
			profiles[index] = saved_profile
			found = true
			break
	if not found:
		profiles.append(saved_profile)
	var transaction := _write_transaction(profiles, bool(loaded.get("recovered_from_backup", false)))
	if not transaction.ok:
		return {"ok": false, "profile": {}, "error": transaction.error}
	return {"ok": true, "profile": saved_profile.duplicate(true), "error": "", "warning": transaction.warning}


## Restores a previously returned load_all() snapshot after a runtime activation refusal.
## The current store is checked first so this cannot overwrite a newly damaged file.
func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if not bool(snapshot.get("ok", false)) or typeof(snapshot.get("profiles")) != TYPE_ARRAY:
		return {"ok": false, "error": "The previous controller profile snapshot is invalid."}
	var profiles: Array = snapshot.profiles.duplicate(true)
	var identifiers: Dictionary = {}
	for candidate in profiles:
		var validation := ControllerProfile.validate(candidate)
		if not validation.ok:
			return {"ok": false, "error": "The previous controller profile snapshot is invalid: " + "; ".join(validation.errors)}
		var profile_id: String = candidate.profile_id
		if identifiers.has(profile_id):
			return {"ok": false, "error": "The previous controller profile snapshot contains duplicate IDs."}
		identifiers[profile_id] = true
	var current := load_all()
	if not current.ok:
		return {"ok": false, "error": "Could not restore controller profiles because current storage is unreadable: " + "; ".join(current.errors)}
	var transaction := _write_transaction(profiles, bool(current.get("recovered_from_backup", false)))
	if not transaction.ok:
		return {"ok": false, "error": transaction.error}
	return {"ok": true, "error": "", "warning": transaction.warning}


## Read-only import candidates from rc_calibration.cfg. Imported profiles remain radio profiles.
func import_legacy_radio(source_path: String = "") -> Dictionary:
	var effective_path := legacy_path if source_path.is_empty() else source_path
	if not FileAccess.file_exists(effective_path):
		return {"ok": true, "profiles": [], "errors": []}
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(effective_path)
	if err != OK:
		return {"ok": false, "profiles": [], "errors": ["Legacy radio calibration file could not be read (%s)." % str(err)]}
	var candidates: Array[Dictionary] = []
	var errors: Array[String] = []
	for section in cfg.get_sections():
		var device_key: Variant = cfg.get_value(section, "device_key", "")
		var raw_profile: Variant = cfg.get_value(section, "profile", {})
		if typeof(device_key) != TYPE_STRING or device_key.is_empty() or device_key.md5_text() != section:
			errors.append("Skipped legacy section with mismatched device identity: " + str(section))
			continue
		if not RcCalibration.valid(raw_profile):
			errors.append("Skipped invalid legacy radio profile for " + _redacted_key(device_key))
			continue
		var sanitized: Dictionary = SmokeAux.sanitize_profile(raw_profile, false)
		var imported := ControllerProfile.upgrade_legacy(sanitized, {"legacy_device_key": device_key})
		if imported.is_empty():
			errors.append("Skipped legacy radio profile that could not be represented by schema 2 for " + _redacted_key(device_key))
			continue
		imported["name"] = "Imported radio profile"
		candidates.append(imported)
	return {"ok": true, "profiles": candidates, "errors": errors}


## Returns saved profiles whose recorded identity evidence matches this observed device.
func profiles_for_device(info: Dictionary) -> Array[Dictionary]:
	var loaded := load_all()
	if not loaded.ok:
		return []
	var matches: Array[Dictionary] = []
	for profile in loaded.profiles:
		var association: Dictionary = profile.get("association", {})
		if _association_matches(info, association):
			matches.append(profile.duplicate(true))
	return matches


## Returns one unambiguous association suggestion or {}. It never selects a flight/UI device.
func match_profile(info: Dictionary, connected_devices: Array = []) -> Dictionary:
	if connected_devices.is_empty():
		return {}
	var matches := profiles_for_device(info)
	if matches.size() != 1:
		return {}
	var association: Dictionary = matches[0].get("association", {})
	if association.has("serial_number") and not str(association.serial_number).is_empty():
		var serial_matches := 0
		for device in connected_devices:
			if typeof(device) != TYPE_DICTIONARY or not bool(device.get("connected", false)):
				continue
			if str(device.get("serial_number", "")) != str(association.serial_number):
				continue
			if association.has("vendor_id") and _metadata_int(device.get("vendor_id", 0)) != _metadata_int(association.vendor_id):
				continue
			if association.has("product_id") and _metadata_int(device.get("product_id", 0)) != _metadata_int(association.product_id):
				continue
			serial_matches += 1
		if serial_matches != 1:
			return {}
		return matches[0]
	var association_guid: String = str(association.get("guid", ""))
	var association_vendor: int = _metadata_int(association.get("vendor_id", 0))
	var association_product: int = _metadata_int(association.get("product_id", 0))
	var identity_matches := 0
	if not association_guid.is_empty() and association_vendor > 0 and association_product > 0:
		for device in connected_devices:
			if typeof(device) != TYPE_DICTIONARY or not bool(device.get("connected", false)):
				continue
			if str(device.get("guid", "")) == association_guid and _metadata_int(device.get("vendor_id", 0)) == association_vendor and _metadata_int(device.get("product_id", 0)) == association_product:
				identity_matches += 1
		return matches[0] if identity_matches == 1 else {}
	var legacy_key := str(association.get("legacy_device_key", ""))
	if legacy_key.is_empty():
		return {}
	for device in connected_devices:
		if typeof(device) == TYPE_DICTIONARY and bool(device.get("connected", false)) and _legacy_key(device) == legacy_key:
			identity_matches += 1
	return matches[0] if identity_matches == 1 else {}


func _read_file(target_path: String) -> Dictionary:
	if not FileAccess.file_exists(target_path):
		return {"ok": false, "missing": true, "profiles": [], "error": "Profile file is missing."}
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(target_path)
	if err != OK:
		return {"ok": false, "missing": false, "profiles": [], "error": "Could not read controller profile storage (%s)." % str(err)}
	if not cfg.has_section_key(STORAGE_SECTION, "schema_version") or not cfg.has_section_key(STORAGE_SECTION, "profiles"):
		return {"ok": false, "missing": false, "profiles": [], "error": "Controller profile storage is missing required fields."}
	var version: Variant = cfg.get_value(STORAGE_SECTION, "schema_version")
	if typeof(version) != TYPE_INT or version != ControllerProfile.SCHEMA_VERSION:
		return {"ok": false, "missing": false, "profiles": [], "error": "Controller profile storage schema version is unsupported."}
	var stored: Variant = cfg.get_value(STORAGE_SECTION, "profiles")
	if typeof(stored) != TYPE_ARRAY:
		return {"ok": false, "missing": false, "profiles": [], "error": "Controller profile list must be an Array."}
	var profiles: Array[Dictionary] = []
	var identifiers: Dictionary = {}
	for candidate in stored:
		var validation := ControllerProfile.validate(candidate)
		if not validation.ok:
			return {"ok": false, "missing": false, "profiles": [], "error": "Invalid profile in storage: " + "; ".join(validation.errors)}
		var profile_id: String = candidate.profile_id
		if identifiers.has(profile_id):
			return {"ok": false, "missing": false, "profiles": [], "error": "Duplicate profile_id in storage."}
		identifiers[profile_id] = true
		profiles.append(candidate.duplicate(true))
	return {"ok": true, "missing": false, "profiles": profiles, "error": ""}


func _write_transaction(profiles: Array, recovered_from_backup := false) -> Dictionary:
	var parent_dir := ProjectSettings.globalize_path(path).get_base_dir()
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
	if dir_error != OK:
		return {"ok": false, "error": "Could not create controller profile directory (%s)." % str(dir_error), "warning": ""}
	var temporary := path + TEMP_SUFFIX
	var backup := path + BACKUP_SUFFIX
	if FileAccess.file_exists(temporary):
		var remove_temp: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		if remove_temp != OK:
			return {"ok": false, "error": "Could not clear stale profile temporary file (%s)." % str(remove_temp), "warning": ""}
	var cfg := ConfigFile.new()
	cfg.set_value(STORAGE_SECTION, "schema_version", ControllerProfile.SCHEMA_VERSION)
	cfg.set_value(STORAGE_SECTION, "profiles", profiles)
	var write_error: Error = cfg.save(temporary)
	if write_error != OK:
		return {"ok": false, "error": "Could not write temporary controller profiles (%s)." % str(write_error), "warning": ""}
	var verify := _read_file(temporary)
	if not verify.ok or verify.profiles != profiles:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"ok": false, "error": "Temporary controller profiles failed validation.", "warning": ""}
	var target_exists := FileAccess.file_exists(path)
	var preserve_recovery_copy := recovered_from_backup and FileAccess.file_exists(backup)
	if target_exists:
		if preserve_recovery_copy:
			var remove_corrupt: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if remove_corrupt != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
				return {"ok": false, "error": "Could not replace unreadable controller storage while preserving its valid rollback copy (%s)." % str(remove_corrupt), "warning": ""}
		elif FileAccess.file_exists(backup):
			var remove_backup: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
			if remove_backup != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
				return {"ok": false, "error": "Could not clear stale profile rollback file (%s)." % str(remove_backup), "warning": ""}
		if not preserve_recovery_copy:
			var backup_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
			if backup_error != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
				return {"ok": false, "error": "Could not stage existing controller profiles for rollback (%s)." % str(backup_error), "warning": ""}
	var commit_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if commit_error != OK:
		var restore_error: Error = OK
		if preserve_recovery_copy:
			restore_error = DirAccess.copy_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path))
		elif target_exists and FileAccess.file_exists(backup):
			restore_error = DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		var restore_message := "; previous data was restored." if target_exists and restore_error == OK else ("; rollback data remains available at the rollback path (%s)." % str(restore_error) if restore_error != OK else "; no previous primary file was replaced.")
		return {"ok": false, "error": "Could not commit controller profiles (%s)%s" % [str(commit_error), restore_message], "warning": ""}
	var warning := ""
	if FileAccess.file_exists(backup):
		var clean_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		if clean_error != OK:
			warning = "Profiles were saved, but the rollback copy could not be removed (%s)." % str(clean_error)
	return {"ok": true, "error": "", "warning": warning}


func _association_matches(info: Dictionary, association: Dictionary) -> bool:
	if association.is_empty():
		return false
	var stored_serial := str(association.get("serial_number", ""))
	var observed_serial := str(info.get("serial_number", ""))
	var stored_guid := str(association.get("guid", ""))
	var observed_guid := str(info.get("guid", ""))
	var stored_vendor := _metadata_int(association.get("vendor_id", 0))
	var stored_product := _metadata_int(association.get("product_id", 0))
	var observed_vendor := _metadata_int(info.get("vendor_id", 0))
	var observed_product := _metadata_int(info.get("product_id", 0))
	if not stored_serial.is_empty():
		return stored_serial == observed_serial and (stored_vendor == 0 or stored_vendor == observed_vendor) and (stored_product == 0 or stored_product == observed_product)
	if not stored_guid.is_empty() and not observed_guid.is_empty() and stored_guid != observed_guid:
		return false
	if stored_vendor > 0 and observed_vendor > 0 and stored_vendor != observed_vendor:
		return false
	if stored_product > 0 and observed_product > 0 and stored_product != observed_product:
		return false
	if not stored_guid.is_empty() and stored_vendor > 0 and stored_product > 0:
		return stored_guid == observed_guid and stored_vendor == observed_vendor and stored_product == observed_product
	if association.has("legacy_device_key"):
		var legacy_key: String = str(association.legacy_device_key)
		return not legacy_key.is_empty() and _legacy_key(info) == legacy_key
	return false


func _legacy_key(info: Dictionary) -> String:
	if info.has("device_key") and typeof(info.device_key) == TYPE_STRING:
		return info.device_key
	var name := str(info.get("raw_name", info.get("name", "")))
	return "%s|%04x:%04x|%s" % [str(info.get("guid", "")), _metadata_int(info.get("vendor_id", 0)), _metadata_int(info.get("product_id", 0)), name]


func _metadata_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING and value.strip_edges().is_valid_int():
		return value.strip_edges().to_int()
	return 0


func _redacted_key(key: String) -> String:
	return "device-" + key.md5_text().substr(0, 8)
