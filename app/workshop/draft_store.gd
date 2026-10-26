extends RefCounted
## Bounded, data-only recovery for an in-progress Aircraft Workshop draft.
## This is a single replaceable scratch record beside the variant library; it never
## publishes a variant, rewrites the library index, compiles, or migrates old pins.

const Store := preload("res://workshop/store.gd")
const Bundle := preload("res://workshop/bundle.gd")
const StrictJSON := preload("res://workshop/strict_json.gd")
const Dependencies := preload("res://workshop/dependencies.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Presentation := preload("res://workshop/presentation.gd")
const LightingSequence := preload("res://workshop/lighting_sequence.gd")
const Compiler := preload("res://workshop/compiler.gd")

const FORMAT: String = "openrc-aircraft-workshop-recovery"
const VERSION: int = 1
const RECOVERY_DIRECTORY: String = "_workshop_recovery"
const SNAPSHOT_FILE: String = "snapshot.json"
const BACKUP_FILE: String = "snapshot.json.bak"
const TEMP_FILE: String = "snapshot.json.tmp"
const LOCK_DIRECTORY: String = "write.lock"
const MAX_SNAPSHOT_BYTES: int = 34 * 1024 * 1024
const MAX_EDITOR_BYTES: int = 16384
const MAX_EDITOR_DEPTH: int = 8
const MAX_EDITOR_NODES: int = 256
const SNAPSHOT_KEYS: PackedStringArray = ["format", "version", "bundle_sha256", "bundle_base64", "editor"]
const EDITOR_KEYS: PackedStringArray = ["page", "name", "numeric_buffers", "presentation_buffers"]
const EDITOR_OPTIONAL_KEYS: PackedStringArray = ["camera"]
const PAGES: PackedStringArray = ["appearance", "smoke", "lighting", "audio", "setup", "compare"]
const NUMERIC_BUFFER_KEYS: PackedStringArray = [
	"scale", "weight_multiplier", "power_multiplier", "control_multiplier", "tank_capacity_multiplier",
	"control_multiplier_aileron", "control_multiplier_elevator", "control_multiplier_rudder",
]
const PRESENTATION_PAGES: PackedStringArray = ["appearance", "smoke"]
const PRESENTATION_BUFFER_KEYS: PackedStringArray = [
	"slot", "palette_step", "color_text", "marking_slot", "marking_text", "marking_color",
]
const CAMERA_KEYS: PackedStringArray = [
	"mode", "comparison_original", "yaw_deg", "pitch_deg", "zoom", "standard_view",
]
const FAULT_STAGES: PackedStringArray = [
	"after_temp_write", "after_temp_readback", "after_backup_rotate", "after_primary_commit",
]


## Build may be a Store variant or the current committed Workshop payload. UI-only pending
## text is passed separately and is never used to rewrite the accepted physical/profile data.
static func save_snapshot(root: String = Store.DEFAULT_ROOT, accepted_build: Dictionary = {},
		editor_state: Dictionary = {}, fault_at: String = "", expected_digest: String = "") -> Dictionary:
	if not _valid_expected_digest(expected_digest):
		return _failure("Expected recovery digest must be 'missing' or a lowercase SHA-256 value.")
	var checked_editor: Dictionary = validate_editor_state(editor_state)
	if not bool(checked_editor.get("ok", false)):
		return _result(false, checked_editor.get("errors", PackedStringArray()))
	if not fault_at.is_empty() and not FAULT_STAGES.has(fault_at):
		return _failure("Unknown recovery fault-injection stage.")
	var bundle_record: Dictionary = _bundle_record(accepted_build)
	if not bool(bundle_record.get("ok", false)):
		return _result(false, bundle_record.get("errors", PackedStringArray()))
	var bundle_bytes: PackedByteArray = bundle_record["bytes"]
	var envelope: Dictionary = {
		"format": FORMAT,
		"version": VERSION,
		"bundle_sha256": _sha256(bundle_bytes),
		"bundle_base64": Marshalls.raw_to_base64(bundle_bytes),
		"editor": checked_editor["editor"],
	}
	var snapshot_bytes: PackedByteArray = (JSON.stringify(envelope, "\t", true, true) + "\n").to_utf8_buffer()
	if snapshot_bytes.size() > MAX_SNAPSHOT_BYTES:
		return _failure("Workshop recovery snapshot exceeds its bounded size limit.")
	var snapshot_check: Dictionary = _decode_snapshot(snapshot_bytes)
	if not bool(snapshot_check.get("ok", false)):
		return _result(false, snapshot_check.get("errors", PackedStringArray()))

	var paths_result: Dictionary = _paths(root)
	if not bool(paths_result.get("ok", false)):
		return _result(false, paths_result.get("errors", PackedStringArray()))
	var paths: Dictionary = paths_result["paths"]
	if not expected_digest.is_empty() and expected_digest != "missing" \
			and not DirAccess.dir_exists_absolute(str(paths["directory"])):
		return _cas_conflict("Workshop recovery changed since it was read; review it before saving.")
	var root_error: Error = Store._make_directory(str(paths["root"]))
	if root_error != OK:
		return _failure("Could not create the Workshop recovery root (%s)." % error_string(root_error))
	var recovery_error: Error = Store._make_directory(str(paths["directory"]))
	if recovery_error != OK:
		return _failure("Could not create the Workshop recovery directory (%s)." % error_string(recovery_error))
	var lock_result: Dictionary = _acquire_lock(str(paths["lock"]))
	if not bool(lock_result.get("ok", false)):
		return _result(false, lock_result.get("errors", PackedStringArray()))

	var saved: Dictionary = _save_locked(paths, snapshot_bytes, fault_at, expected_digest)
	var leave_lock: bool = bool(saved.get("leave_lock", false))
	saved.erase("leave_lock")
	if bool(saved.get("ok", false)):
		saved["digest"] = _sha256(snapshot_bytes)
	if not leave_lock:
		var release_error: Error = DirAccess.remove_absolute(str(paths["lock"]))
		if release_error != OK:
			if bool(saved.get("ok", false)):
				saved["warning"] = "Snapshot committed, but its writer lock could not be removed (%s)." % error_string(release_error)
			else:
				var errors: PackedStringArray = saved.get("errors", PackedStringArray())
				errors.append("Recovery writer lock could not be removed (%s)." % error_string(release_error))
				saved["errors"] = errors
				saved["ok"] = false
	return saved


## A valid snapshot is returned even when its pinned dependencies are stale. `compatible`
## is a pin preflight only; callers must restore explicitly and run Trial.freeze before flight.
## Reading never promotes a backup or deletes a temporary file.
static func load_snapshot(root: String = Store.DEFAULT_ROOT) -> Dictionary:
	var paths_result: Dictionary = _paths(root)
	if not bool(paths_result.get("ok", false)):
		return _load_failure(paths_result.get("errors", PackedStringArray()))
	var paths: Dictionary = paths_result["paths"]
	if FileAccess.file_exists(str(paths["directory"])):
		return _load_failure(PackedStringArray(["Workshop recovery directory collides with a file."]))
	if not DirAccess.dir_exists_absolute(str(paths["directory"])):
		return _empty_load()
	var writer_active: bool = DirAccess.dir_exists_absolute(str(paths["lock"])) \
		or FileAccess.file_exists(str(paths["lock"]))
	var primary: Dictionary = _read_record(str(paths["primary"]))
	var backup: Dictionary = _read_record(str(paths["backup"]))
	var temporary_exists: bool = FileAccess.file_exists(str(paths["temporary"])) \
		or DirAccess.dir_exists_absolute(str(paths["temporary"]))
	var found: bool = bool(primary.get("exists", false)) or bool(backup.get("exists", false)) or temporary_exists
	if not found:
		var empty: Dictionary = _empty_load()
		empty["writer_active"] = writer_active
		return empty
	var selected: Dictionary = {}
	var recovered_from_backup: bool = false
	if bool(primary.get("ok", false)) and bool(primary.get("exists", false)):
		selected = primary
	elif bool(backup.get("ok", false)) and bool(backup.get("exists", false)):
		selected = backup
		recovered_from_backup = true
	else:
		var errors := PackedStringArray()
		if bool(primary.get("exists", false)):
			errors.append_array(primary.get("errors", PackedStringArray()))
		if bool(backup.get("exists", false)):
			errors.append_array(backup.get("errors", PackedStringArray()))
		if temporary_exists:
			errors.append("Only an uncommitted recovery temporary remains; it was not promoted.")
		if errors.is_empty():
			errors.append("Workshop recovery snapshot is unavailable.")
		var invalid_digest: String = str(primary.get("digest", ""))
		if invalid_digest.is_empty():
			invalid_digest = str(backup.get("digest", ""))
		return {"ok": false, "exists": true, "payload": {}, "editor": {}, "stale": true,
			"compatible": false, "launchable": false, "recovered_from_backup": false,
			"digest": invalid_digest, "writer_active": writer_active, "errors": errors, "compatibility_errors": PackedStringArray()}

	var compatibility: Dictionary = _check_current_compatibility(
		selected["payload"], bool(selected.get("profile_available", false)))
	var compatible: bool = bool(compatibility.get("compatible", false))
	return {
		"ok": true,
		"exists": true,
		"payload": selected["payload"],
		"editor": selected["editor"],
		"stale": not compatible,
		"compatible": compatible,
		"launchable": false,
		"recovered_from_backup": recovered_from_backup,
		"digest": str(selected.get("digest", "")),
		"writer_active": writer_active,
		"errors": PackedStringArray(),
		"compatibility_errors": compatibility.get("errors", PackedStringArray()),
	}


## Explicit user discard. It deletes only the fixed recovery files, never variants or trash.
## A present writer lock is not reclaimed based on age or guesswork.
static func discard_snapshot(root: String = Store.DEFAULT_ROOT, expected_digest: String = "") -> Dictionary:
	if not _valid_expected_digest(expected_digest):
		return _failure("Expected recovery digest must be 'missing' or a lowercase SHA-256 value.")
	var paths_result: Dictionary = _paths(root)
	if not bool(paths_result.get("ok", false)):
		return _result(false, paths_result.get("errors", PackedStringArray()))
	var paths: Dictionary = paths_result["paths"]
	if FileAccess.file_exists(str(paths["directory"])):
		return _failure("Workshop recovery directory collides with a file.")
	if not DirAccess.dir_exists_absolute(str(paths["directory"])):
		if expected_digest.is_empty() or expected_digest == "missing":
			return {"ok": true, "errors": PackedStringArray(), "discarded": false, "digest": "missing"}
		return _cas_conflict("Workshop recovery changed since it was read; review it before discarding.")
	var lock_result: Dictionary = _acquire_lock(str(paths["lock"]))
	if not bool(lock_result.get("ok", false)):
		return _result(false, lock_result.get("errors", PackedStringArray()))
	if not expected_digest.is_empty():
		var current := _read_record(str(paths["primary"]))
		var backup := _read_record(str(paths["backup"]))
		var compared: Dictionary = _compare_expected_digest(paths, expected_digest, current, backup, true)
		if not bool(compared.get("ok", false)):
			DirAccess.remove_absolute(str(paths["lock"]))
			return compared
	var entries: Dictionary = _directory_entries(str(paths["directory"]))
	if not bool(entries.get("ok", false)):
		DirAccess.remove_absolute(str(paths["lock"]))
		return _result(false, entries.get("errors", PackedStringArray()))
	for filename: String in entries["files"]:
		if filename not in [SNAPSHOT_FILE, BACKUP_FILE, TEMP_FILE]:
			DirAccess.remove_absolute(str(paths["lock"]))
			return _failure("Recovery directory contains an unsupported file; nothing was discarded.")
	for dirname: String in entries["directories"]:
		if dirname != LOCK_DIRECTORY:
			DirAccess.remove_absolute(str(paths["lock"]))
			return _failure("Recovery directory contains an unsupported folder; nothing was discarded.")
	# Inspect every fixed recovery target before deleting any of them. A collision at a
	# later filename must never leave an earlier snapshot partially discarded.
	for filename: String in [SNAPSHOT_FILE, BACKUP_FILE, TEMP_FILE]:
		var file_path: String = str(paths["directory"]).path_join(filename)
		if DirAccess.dir_exists_absolute(file_path):
			DirAccess.remove_absolute(str(paths["lock"]))
			return _failure("Recovery file path collides with a folder; nothing was discarded.")
	for filename: String in [SNAPSHOT_FILE, BACKUP_FILE, TEMP_FILE]:
		var file_path: String = str(paths["directory"]).path_join(filename)
		if FileAccess.file_exists(file_path):
			var remove_error: Error = DirAccess.remove_absolute(file_path)
			if remove_error != OK:
				DirAccess.remove_absolute(str(paths["lock"]))
				return _failure("Could not discard the recovery snapshot (%s)." % error_string(remove_error))
	var unlock_error: Error = DirAccess.remove_absolute(str(paths["lock"]))
	if unlock_error != OK:
		return _failure("Recovery files were removed, but the writer lock remains (%s)." % error_string(unlock_error))
	return {"ok": true, "errors": PackedStringArray(), "discarded": true, "digest": "missing"}


static func validate_editor_state(value: Variant) -> Dictionary:
	var object_result: Dictionary = _normalize_object(value, "editor state")
	if not bool(object_result.get("ok", false)):
		return object_result
	var editor: Dictionary = object_result["value"]
	if not _exact_keys_optional(editor, EDITOR_KEYS, EDITOR_OPTIONAL_KEYS):
		return _failure("Workshop editor recovery state has missing or unsupported fields.")
	if typeof(editor.get("page", null)) != TYPE_STRING or not PAGES.has(str(editor["page"])) \
			or typeof(editor.get("name", null)) != TYPE_STRING or not _bounded_text(str(editor["name"]), 64):
		return _failure("Workshop editor recovery page or name is malformed.")
	var numeric_result: Dictionary = _normalize_object(editor.get("numeric_buffers", null), "numeric buffers")
	if not bool(numeric_result.get("ok", false)):
		return numeric_result
	var numeric: Dictionary = numeric_result["value"]
	for key: String in numeric:
		if not NUMERIC_BUFFER_KEYS.has(key) or typeof(numeric[key]) != TYPE_STRING or not _bounded_text(str(numeric[key]), 64):
			return _failure("Workshop numeric recovery buffer is unsupported or malformed.")
	var presentations_result: Dictionary = _normalize_object(editor.get("presentation_buffers", null), "presentation buffers")
	if not bool(presentations_result.get("ok", false)):
		return presentations_result
	var presentations: Dictionary = presentations_result["value"]
	if not _exact_keys_optional(presentations, PRESENTATION_PAGES, PackedStringArray(["lighting"])):
		return _failure("Workshop presentation recovery pages are missing or unsupported.")
	var checked_presentations: Dictionary = {}
	for page: String in PRESENTATION_PAGES:
		var checked: Dictionary = _validate_presentation_buffer(page, presentations[page])
		if not bool(checked.get("ok", false)):
			return checked
		checked_presentations[page] = checked["value"]
	if presentations.has("lighting"):
		var lighting: Variant = presentations.lighting
		if typeof(lighting) != TYPE_DICTIONARY or not _exact_keys_optional(lighting, PackedStringArray(["zone", "zones_open", "effects_open", "color_text"]), PackedStringArray(["sequence"])):
			return _failure("Lighting editor recovery has missing or unsupported fields.")
		if typeof(lighting.zone) != TYPE_STRING or (not str(lighting.zone).is_empty() and not Presentation.LightingProfile.ZONE_IDS.has(str(lighting.zone))) \
				or typeof(lighting.zones_open) != TYPE_BOOL or typeof(lighting.effects_open) != TYPE_BOOL:
			return _failure("Lighting editor recovery selection is malformed.")
		if typeof(lighting.color_text) != TYPE_ARRAY or lighting.color_text.size() > 8:
			return _failure("Lighting editor recovery palette exceeds eight entries.")
		for text_value: Variant in lighting.color_text:
			if typeof(text_value) != TYPE_STRING or not _bounded_text(str(text_value), 16):
				return _failure("Lighting editor recovery color text is malformed.")
		if lighting.has("sequence") and not LightingSequence.validate_editor_state(lighting.sequence).ok:
			return _failure("Lighting sequence recovery has malformed or unsupported fields.")
		checked_presentations["lighting"] = lighting.duplicate(true)
	var normalized: Dictionary = {
		"page": str(editor["page"]),
		"name": str(editor["name"]),
		"numeric_buffers": numeric.duplicate(true),
		"presentation_buffers": checked_presentations,
	}
	if editor.has("camera"):
		var camera_result: Dictionary = _validate_camera(editor["camera"])
		if not bool(camera_result.get("ok", false)):
			return camera_result
		normalized["camera"] = camera_result["value"]
	var editor_bytes: PackedByteArray = JSON.stringify(normalized, "", true, true).to_utf8_buffer()
	if editor_bytes.size() > MAX_EDITOR_BYTES:
		return _failure("Workshop editor recovery state exceeds its bounded size limit.")
	return {"ok": true, "errors": PackedStringArray(), "editor": normalized}


static func _bundle_record(build: Dictionary) -> Dictionary:
	if _has_bundle_variant_shape(build):
		var exported: Dictionary = Bundle.export_variant(build)
		if not bool(exported.get("ok", false)):
			return exported
		return {"ok": true, "errors": PackedStringArray(), "bytes": exported["bytes"]}
	var base_id: Variant = _build_value(build, "base_id", null)
	var bytes_value: Variant = _build_value(build, "base_bytes", null)
	var recipe_value: Variant = _build_value(build, "recipe", null)
	if typeof(base_id) != TYPE_STRING or typeof(bytes_value) != TYPE_PACKED_BYTE_ARRAY or typeof(recipe_value) != TYPE_DICTIONARY:
		return _failure("Recovery build needs a base ID, exact base bytes, and accepted recipe.")
	var base_bytes: PackedByteArray = bytes_value
	var base_result: Dictionary = StrictJSON.parse(base_bytes, Store.MAX_BASE_BYTES, Store.MAX_JSON_DEPTH, Store.MAX_JSON_NODES)
	if not bool(base_result.get("ok", false)) or typeof(base_result.get("data", null)) != TYPE_DICTIONARY:
		return _result(false, base_result.get("errors", PackedStringArray(["Recovery base snapshot is invalid."])))
	var recipe_result: Dictionary = _normalize_json_object(recipe_value, "physical recipe")
	if not bool(recipe_result.get("ok", false)):
		return recipe_result
	var recipe: Dictionary = recipe_result["value"]
	# A recovery build is detached by design. Bundle v1 already excludes local UUID/name
	# ancestry from its decoded payload; remove only those two metadata fields here too.
	recipe.erase("id")
	recipe.erase("name")
	var descriptor_result: Dictionary = _normalize_json_object(
		_build_value(build, "workshop_descriptor", _build_value(build, "descriptor", {})), "Workshop descriptor")
	if not bool(descriptor_result.get("ok", false)):
		return descriptor_result
	var dependencies_result: Dictionary = _normalize_json_object(
		_build_value(build, "dependencies", {}), "Workshop dependencies")
	if not bool(dependencies_result.get("ok", false)):
		return dependencies_result
	var profile_result: Dictionary = _normalize_json_object(
		_build_value(build, "presentation_profile", {}), "presentation profile")
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var id_value: Variant = _build_value(build, "variant_id", "")
	var revision_value: Variant = _build_value(build, "variant_revision", 0)
	if typeof(id_value) != TYPE_STRING:
		id_value = ""
	if typeof(revision_value) != TYPE_INT:
		revision_value = 0
	var compiler_value: Variant = _build_value(build, "compiler_version", _build_value(build, "compiler", ""))
	var compiler_version: String = str(compiler_value) if typeof(compiler_value) == TYPE_STRING else ""
	if compiler_version.is_empty():
		compiler_version = Compiler.version_for_recipe(recipe)
	var name_value: Variant = _build_value(build, "name", "")
	var bundle_name: String = str(name_value) if typeof(name_value) == TYPE_STRING else ""
	if not Bundle._valid_name(bundle_name):
		bundle_name = "Recovered draft"
	var base: Dictionary = base_result["data"]
	var variant: Dictionary = {
		"id": str(id_value),
		"revision": int(revision_value),
		"name": bundle_name,
		"compiler_version": compiler_version,
		"base_id": str(base_id),
		"recipe": recipe,
		"base": base,
		"base_bytes": base_bytes,
		"base_sha256": Store._sha256(base_bytes),
		"recipe_sha256": Store._sha256(JSON.stringify(recipe, "", true, true).to_utf8_buffer()),
		"workshop_descriptor": descriptor_result["value"],
		"dependencies": dependencies_result["value"],
		"presentation_profile": profile_result["value"],
	}
	var result: Dictionary = Bundle.export_variant(variant)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "errors": PackedStringArray(), "bytes": result["bytes"]}


static func _has_bundle_variant_shape(value: Dictionary) -> bool:
	for key: String in ["id", "revision", "name", "compiler_version", "base_id", "recipe", "base", "base_bytes", "base_sha256", "recipe_sha256"]:
		if not _has(value, key):
			return false
	return true


static func _decode_snapshot(bytes: PackedByteArray) -> Dictionary:
	var parsed: Dictionary = StrictJSON.parse(bytes, MAX_SNAPSHOT_BYTES, 8, 256)
	if not bool(parsed.get("ok", false)):
		return _result(false, parsed.get("errors", PackedStringArray()))
	var object_result: Dictionary = _normalize_object(parsed.get("data", null), "recovery snapshot")
	if not bool(object_result.get("ok", false)):
		return object_result
	var record: Dictionary = object_result["value"]
	if not _exact_keys(record, SNAPSHOT_KEYS):
		return _failure("Workshop recovery snapshot has missing or unsupported fields.")
	if record.get("format") != FORMAT or not _integer_number(record.get("version")) or int(record["version"]) != VERSION:
		return _failure("Workshop recovery snapshot format or version is unsupported.")
	if typeof(record.get("bundle_sha256")) != TYPE_STRING or not _valid_sha256(str(record["bundle_sha256"])) \
			or typeof(record.get("bundle_base64")) != TYPE_STRING:
		return _failure("Workshop recovery bundle fields are malformed.")
	var bundle_bytes: PackedByteArray = Marshalls.base64_to_raw(str(record["bundle_base64"]))
	if bundle_bytes.is_empty() or bundle_bytes.size() > Bundle.MAX_BUNDLE_BYTES \
			or Marshalls.raw_to_base64(bundle_bytes) != str(record["bundle_base64"]):
		return _failure("Workshop recovery bundle encoding is malformed or oversized.")
	if _sha256(bundle_bytes) != str(record["bundle_sha256"]):
		return _failure("Workshop recovery bundle hash does not match its exact bytes.")
	var decoded: Dictionary = Bundle.decode(bundle_bytes)
	if not bool(decoded.get("ok", false)):
		return _result(false, decoded.get("errors", PackedStringArray()))
	var editor_result: Dictionary = validate_editor_state(record.get("editor", null))
	if not bool(editor_result.get("ok", false)):
		return editor_result
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"payload": decoded["payload"],
		"editor": editor_result["editor"],
		"compiler_compatible": bool(decoded.get("compiler_compatible", false)),
		"profile_available": bool(decoded.get("presentation_profile_available", false)),
		"bundle_bytes": bundle_bytes,
	}


static func _read_record(path: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(path):
		return {"ok": false, "exists": true, "errors": PackedStringArray(["Recovery file path collides with a folder."])}
	if not FileAccess.file_exists(path):
		return {"ok": true, "exists": false, "errors": PackedStringArray()}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "exists": true, "errors": PackedStringArray(["Recovery snapshot could not be opened."])}
	var length: int = file.get_length()
	if length <= 0 or length > MAX_SNAPSHOT_BYTES:
		file.close()
		return {"ok": false, "exists": true, "errors": PackedStringArray(["Recovery snapshot is empty or exceeds its byte limit."])}
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK or bytes.size() != length:
		return {"ok": false, "exists": true, "errors": PackedStringArray(["Recovery snapshot could not be read completely."])}
	var decoded: Dictionary = _decode_snapshot(bytes)
	decoded["exists"] = true
	decoded["digest"] = _sha256(bytes)
	return decoded


static func _save_locked(paths: Dictionary, snapshot_bytes: PackedByteArray, fault_at: String,
		expected_digest: String = "") -> Dictionary:
	var primary_path: String = str(paths["primary"])
	var backup_path: String = str(paths["backup"])
	var temporary_path: String = str(paths["temporary"])
	var current: Dictionary = _read_record(primary_path)
	var backup: Dictionary = _read_record(backup_path)
	if not expected_digest.is_empty():
		var compared: Dictionary = _compare_expected_digest(paths, expected_digest, current, backup, false)
		if not bool(compared.get("ok", false)):
			return compared
	if bool(current.get("exists", false)) and not bool(current.get("ok", false)):
		return _result(false, PackedStringArray(["Current recovery snapshot is invalid; review or explicitly discard it before replacing it."]))
	if not bool(current.get("exists", false)) and bool(backup.get("exists", false)) and not bool(backup.get("ok", false)):
		return _result(false, PackedStringArray(["Recovery backup is invalid; review or explicitly discard it before replacing it."]))
	if DirAccess.dir_exists_absolute(temporary_path):
		return _failure("Recovery temporary path collides with a folder.")
	if FileAccess.file_exists(temporary_path):
		var stale_temp_error: Error = DirAccess.remove_absolute(temporary_path)
		if stale_temp_error != OK:
			return _failure("Could not clear the prior uncommitted recovery temporary.")
	var write_result: Dictionary = _write_bytes(temporary_path, snapshot_bytes)
	if not bool(write_result.get("ok", false)):
		return write_result
	if fault_at == "after_temp_write":
		return {"ok": false, "errors": PackedStringArray(["Injected recovery interruption after temporary write."]), "leave_lock": true}
	var readback: Dictionary = _read_record(temporary_path)
	if not bool(readback.get("ok", false)) or readback.get("bundle_bytes", PackedByteArray()) == PackedByteArray():
		# _read_record's parser verifies the whole envelope and Bundle payload.
		DirAccess.remove_absolute(temporary_path)
		return _result(false, readback.get("errors", PackedStringArray(["Recovery temporary could not be validated."])))
	var readback_file: FileAccess = FileAccess.open(temporary_path, FileAccess.READ)
	if readback_file == null:
		DirAccess.remove_absolute(temporary_path)
		return _failure("Recovery temporary could not be reopened for exact-byte verification.")
	var readback_length: int = readback_file.get_length()
	var readback_bytes: PackedByteArray = readback_file.get_buffer(readback_length)
	var readback_error: Error = readback_file.get_error()
	readback_file.close()
	if readback_error != OK or readback_bytes != snapshot_bytes:
		DirAccess.remove_absolute(temporary_path)
		return _failure("Recovery temporary failed exact-byte readback.")
	if fault_at == "after_temp_readback":
		return {"ok": false, "errors": PackedStringArray(["Injected recovery interruption after temporary readback."]), "leave_lock": true}

	var rotated_primary: bool = false
	if bool(current.get("exists", false)) and bool(current.get("ok", false)):
		if bool(backup.get("exists", false)):
			var remove_backup_error: Error = DirAccess.remove_absolute(backup_path)
			if remove_backup_error != OK:
				DirAccess.remove_absolute(temporary_path)
				return _failure("Could not rotate the prior recovery backup.")
		var rotate_error: Error = DirAccess.rename_absolute(primary_path, backup_path)
		if rotate_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return _failure("Could not preserve the last committed recovery snapshot (%s)." % error_string(rotate_error))
		rotated_primary = true
	if fault_at == "after_backup_rotate":
		return {"ok": false, "errors": PackedStringArray(["Injected recovery interruption after backup rotation."]), "leave_lock": true}
	var commit_error: Error = DirAccess.rename_absolute(temporary_path, primary_path)
	if commit_error != OK:
		if rotated_primary and not FileAccess.file_exists(primary_path):
			DirAccess.rename_absolute(backup_path, primary_path)
		DirAccess.remove_absolute(temporary_path)
		return _failure("Could not atomically commit the recovery snapshot (%s)." % error_string(commit_error))
	if fault_at == "after_primary_commit":
		return {"ok": false, "errors": PackedStringArray(["Injected recovery interruption after primary commit."]), "leave_lock": true}
	return {"ok": true, "errors": PackedStringArray(), "saved": true}


static func _check_current_compatibility(payload: Dictionary, profile_available: bool) -> Dictionary:
	var errors := PackedStringArray()
	var recipe: Dictionary = payload.get("recipe", {})
	var expected_compiler: String = Compiler.version_for_recipe(recipe)
	if str(payload.get("compiler_version", "")) != expected_compiler:
		errors.append("Saved recipe uses a different Workshop compiler version.")
	var dependency_check: Dictionary = Dependencies.verify(payload.get("base", {}), payload.get("dependencies", {}))
	if not bool(dependency_check.get("ok", false)):
		errors.append_array(dependency_check.get("errors", PackedStringArray(["Pinned Workshop dependencies are stale."])))
	var descriptor_check: Dictionary = Descriptor.verify_presentation(payload.get("workshop_descriptor", {}))
	if not bool(descriptor_check.get("ok", false)):
		errors.append_array(descriptor_check.get("errors", PackedStringArray(["Pinned model presentation is stale."])))
	var profile: Dictionary = payload.get("presentation_profile", {})
	if ResourceLoader.exists("res://render/aircraft_customization.gd"):
		var customization: Script = load("res://render/aircraft_customization.gd")
		var described: Dictionary = customization.describe(str(payload.get("base_id", "")))
		if bool(described.get("ok", false)) and typeof(described.get("bindings", null)) == TYPE_DICTIONARY:
			var profile_check: Dictionary = Presentation.validate(profile, described["bindings"])
			if not bool(profile_check.get("ok", false)) or not bool(profile_check.get("available", false)):
				errors.append_array(profile_check.get("errors", PackedStringArray(["Pinned presentation profile is stale or unavailable."])))
		else:
			errors.append_array(described.get("errors", PackedStringArray(["Current presentation bindings are unavailable."])))
	elif not profile_available:
		errors.append("Pinned presentation profile is unavailable without its current companion.")
	return {"compatible": errors.is_empty(), "errors": errors}


static func _validate_presentation_buffer(page: String, value: Variant) -> Dictionary:
	var object_result: Dictionary = _normalize_object(value, "presentation buffer")
	if not bool(object_result.get("ok", false)):
		return object_result
	var buffer: Dictionary = object_result["value"]
	if not _exact_keys(buffer, PRESENTATION_BUFFER_KEYS):
		return _failure("Presentation editor buffer has missing or unsupported fields.")
	for key: String in ["slot", "color_text", "marking_slot", "marking_text"]:
		if typeof(buffer.get(key, null)) != TYPE_STRING:
			return _failure("Presentation editor text buffer is malformed.")
	if not _valid_slot_or_empty(str(buffer["slot"])) or not _bounded_text(str(buffer["color_text"]), 9) \
			or not _valid_slot_or_empty(str(buffer["marking_slot"])) or not _bounded_text(str(buffer["marking_text"]), 12):
		return _failure("Presentation editor buffer exceeds its fixed text bounds.")
	if not _integer_number(buffer.get("palette_step")) or int(buffer["palette_step"]) < 0 or int(buffer["palette_step"]) > 7 \
			or not _integer_number(buffer.get("marking_color")) or int(buffer["marking_color"]) < 0 or int(buffer["marking_color"]) > 7:
		return _failure("Presentation editor selection is outside its supported bounds.")
	if (page == "appearance" and int(buffer["palette_step"]) != 0) \
			or (page == "smoke" and (not str(buffer["marking_slot"]).is_empty() or not str(buffer["marking_text"]).is_empty() or int(buffer["marking_color"]) != 0)):
		return _failure("Presentation editor buffer does not match its page contract.")
	return {"ok": true, "errors": PackedStringArray(), "value": buffer.duplicate(true)}


static func _validate_camera(value: Variant) -> Dictionary:
	var object_result: Dictionary = _normalize_object(value, "preview camera state")
	if not bool(object_result.get("ok", false)):
		return object_result
	var camera: Dictionary = object_result["value"]
	if not _exact_keys(camera, CAMERA_KEYS):
		return _failure("Preview camera recovery state has missing or unsupported fields.")
	if typeof(camera.get("mode")) != TYPE_STRING or not ["inspect", "compare"].has(str(camera["mode"])) \
			or typeof(camera.get("comparison_original")) != TYPE_BOOL \
			or typeof(camera.get("standard_view")) != TYPE_STRING \
			or not ["default", "front", "side", "top", "custom"].has(str(camera["standard_view"])):
		return _failure("Preview camera recovery mode or selection is malformed.")
	for key: String in ["yaw_deg", "pitch_deg", "zoom"]:
		if typeof(camera.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(camera[key])):
			return _failure("Preview camera recovery values must be finite numbers.")
	if float(camera["yaw_deg"]) < 0.0 or float(camera["yaw_deg"]) >= 360.0 \
			or float(camera["pitch_deg"]) < -88.0 or float(camera["pitch_deg"]) > 88.0 \
			or float(camera["zoom"]) < 0.5 or float(camera["zoom"]) > 4.0:
		return _failure("Preview camera recovery values exceed the camera bounds.")
	return {"ok": true, "errors": PackedStringArray(), "value": camera.duplicate(true)}


static func _normalize_object(value: Variant, label: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("%s must be a data object." % label)
	var normalized: Dictionary = {}
	for raw_key: Variant in value.keys():
		if typeof(raw_key) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure("%s contains a non-text key." % label)
		var key: String = str(raw_key)
		if normalized.has(key):
			return _failure("%s contains duplicate normalized keys." % label)
		normalized[key] = value[raw_key]
	return {"ok": true, "errors": PackedStringArray(), "value": normalized}


static func _normalize_json_object(value: Variant, label: String) -> Dictionary:
	var normalized_result: Dictionary = _normalize_json_value(value, label, 0, {"remaining": Store.MAX_JSON_NODES})
	if not bool(normalized_result.get("ok", false)):
		return normalized_result
	if typeof(normalized_result.get("value", null)) != TYPE_DICTIONARY:
		return _failure("%s must be a JSON object." % label)
	return normalized_result


static func _normalize_json_value(value: Variant, label: String, depth: int, budget: Dictionary) -> Dictionary:
	budget["remaining"] = int(budget.get("remaining", 0)) - 1
	if depth > Store.MAX_JSON_DEPTH or int(budget["remaining"]) < 0:
		return _failure("%s exceeds its data-tree bounds." % label)
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return {"ok": true, "errors": PackedStringArray(), "value": value}
		TYPE_FLOAT:
			if not is_finite(float(value)):
				return _failure("%s contains a non-finite number." % label)
			return {"ok": true, "errors": PackedStringArray(), "value": value}
		TYPE_STRING_NAME:
			return {"ok": true, "errors": PackedStringArray(), "value": str(value)}
		TYPE_ARRAY:
			var array: Array = []
			for item: Variant in value:
				var item_result: Dictionary = _normalize_json_value(item, label, depth + 1, budget)
				if not bool(item_result.get("ok", false)):
					return item_result
				array.append(item_result["value"])
			return {"ok": true, "errors": PackedStringArray(), "value": array}
		TYPE_DICTIONARY:
			var object: Dictionary = {}
			for raw_key: Variant in value.keys():
				if typeof(raw_key) not in [TYPE_STRING, TYPE_STRING_NAME]:
					return _failure("%s contains a non-text key." % label)
				var key: String = str(raw_key)
				if object.has(key):
					return _failure("%s contains duplicate normalized keys." % label)
				var item_result: Dictionary = _normalize_json_value(value[raw_key], label, depth + 1, budget)
				if not bool(item_result.get("ok", false)):
					return item_result
				object[key] = item_result["value"]
			return {"ok": true, "errors": PackedStringArray(), "value": object}
		_:
			return _failure("%s contains unsupported non-JSON data." % label)


static func _paths(root: String) -> Dictionary:
	var checked: Dictionary = Store._resolve_root(root)
	if not bool(checked.get("ok", false)):
		return _result(false, checked.get("errors", PackedStringArray()))
	var absolute_root: String = str(checked["path"])
	var directory: String = absolute_root.path_join(RECOVERY_DIRECTORY)
	var primary: String = directory.path_join(SNAPSHOT_FILE)
	return {"ok": true, "errors": PackedStringArray(), "paths": {
		"root": absolute_root,
		"directory": directory,
		"primary": primary,
		"backup": primary + ".bak",
		"temporary": primary + ".tmp",
		"lock": directory.path_join(LOCK_DIRECTORY),
	}}


static func _directory_entries(path: String) -> Dictionary:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return _failure("Could not inspect Workshop recovery directory.")
	var files := PackedStringArray()
	var directories := PackedStringArray()
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		if directory.current_is_dir():
			directories.append(entry)
		else:
			files.append(entry)
	directory.list_dir_end()
	return {"ok": true, "errors": PackedStringArray(), "files": files, "directories": directories}


static func _acquire_lock(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		return _failure("Workshop recovery is locked by another writer; retry after it finishes.")
	var error: Error = DirAccess.make_dir_absolute(path)
	if error != OK:
		return _failure("Workshop recovery is locked or the writer lock is unavailable (%s)." % error_string(error))
	return {"ok": true, "errors": PackedStringArray()}


static func _write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("Recovery temporary could not be opened for writing (%s)." % error_string(FileAccess.get_open_error()))
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(path)
		return _failure("Recovery temporary flush failed (%s)." % error_string(error))
	return {"ok": true, "errors": PackedStringArray()}


static func _valid_slot_or_empty(value: String) -> bool:
	if value.is_empty():
		return true
	if value.length() > 80:
		return false
	var first: int = value.unicode_at(0)
	if first < 97 or first > 122:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


static func _bounded_text(value: String, maximum: int) -> bool:
	if value.length() > maximum:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code < 32 or code == 127:
			return false
	return true


static func _exact_keys(value: Dictionary, expected: PackedStringArray) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING or not expected.has(str(raw_key)):
			return false
	return true


static func _exact_keys_optional(value: Dictionary, required: PackedStringArray, optional: PackedStringArray) -> bool:
	for key: String in required:
		if not value.has(key):
			return false
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING or (not required.has(str(raw_key)) and not optional.has(str(raw_key))):
			return false
	return true


static func _build_value(value: Dictionary, key: String, fallback: Variant = null) -> Variant:
	if value.has(key):
		return value[key]
	var name := StringName(key)
	return value[name] if value.has(name) else fallback


static func _has(value: Dictionary, key: String) -> bool:
	return value.has(key) or value.has(StringName(key))


static func _integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return floor(float(value)) == float(value) and abs(float(value)) <= 9007199254740991.0


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


static func _valid_expected_digest(value: String) -> bool:
	return value.is_empty() or value == "missing" or _valid_sha256(value)


## Compare-and-swap is based on the exact committed record selected by load_snapshot.
## This function runs only while the caller owns write.lock. A stale temporary or any
## unknown/colliding path makes the comparison fail closed before files are changed.
static func _compare_expected_digest(paths: Dictionary, expected_digest: String,
		current: Dictionary, backup: Dictionary, for_discard: bool) -> Dictionary:
	if expected_digest.is_empty():
		return {"ok": true, "errors": PackedStringArray(), "selected_backup": false}
	var primary_path: String = str(paths["primary"])
	var backup_path: String = str(paths["backup"])
	var temporary_path: String = str(paths["temporary"])
	for path: String in [primary_path, backup_path, temporary_path]:
		if DirAccess.dir_exists_absolute(path):
			return _cas_conflict("Workshop recovery changed since it was read; review it before writing.")
	if FileAccess.file_exists(temporary_path):
		return _cas_conflict("An uncommitted recovery temporary exists; review it before writing.")
	var entries: Dictionary = _directory_entries(str(paths["directory"]))
	if not bool(entries.get("ok", false)):
		return _cas_conflict("Workshop recovery changed since it was read; review it before writing.")
	for filename: String in entries["files"]:
		if filename not in [SNAPSHOT_FILE, BACKUP_FILE]:
			return _cas_conflict("Workshop recovery contains an unknown file; review it before writing.")
	for dirname: String in entries["directories"]:
		if dirname != LOCK_DIRECTORY:
			return _cas_conflict("Workshop recovery contains an unknown folder; review it before writing.")
	if expected_digest == "missing":
		if bool(current.get("exists", false)) or bool(backup.get("exists", false)):
			return _cas_conflict("Workshop recovery changed since it was read; review it before writing.")
		return {"ok": true, "errors": PackedStringArray(), "selected_backup": false}
	var selected: Dictionary = {}
	var selected_backup: bool = false
	if bool(current.get("exists", false)) and bool(current.get("ok", false)):
		selected = current
	elif bool(backup.get("exists", false)) and bool(backup.get("ok", false)):
		selected = backup
		selected_backup = true
	if selected.is_empty():
		if for_discard:
			var raw_record: Dictionary = current if bool(current.get("exists", false)) else backup
			if bool(raw_record.get("exists", false)) and not bool(raw_record.get("ok", false)) \
					and str(raw_record.get("digest", "")) == expected_digest:
				return {"ok": true, "errors": PackedStringArray(),
					"selected_backup": not bool(current.get("exists", false))}
		return _cas_conflict("Workshop recovery changed since it was read; review it before writing.")
	if not for_discard and (not bool(current.get("ok", false)) and bool(current.get("exists", false)) \
			or not bool(backup.get("ok", false)) and bool(backup.get("exists", false))):
		return _cas_conflict("Workshop recovery contains a corrupt record; review or explicitly discard it.")
	if str(selected.get("digest", "")) != expected_digest:
		return _cas_conflict("Workshop recovery changed since it was read; review it before writing.")
	return {"ok": true, "errors": PackedStringArray(), "selected_backup": selected_backup}


static func _cas_conflict(message: String) -> Dictionary:
	return {"ok": false, "conflict": true, "errors": PackedStringArray([message])}


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


static func _empty_load() -> Dictionary:
	return {"ok": true, "exists": false, "payload": {}, "editor": {}, "stale": false,
		"compatible": false, "launchable": false, "recovered_from_backup": false,
		"digest": "missing", "writer_active": false, "errors": PackedStringArray(), "compatibility_errors": PackedStringArray()}


static func _load_failure(errors: Variant) -> Dictionary:
	return {"ok": false, "exists": false, "payload": {}, "editor": {}, "stale": true,
		"compatible": false, "launchable": false, "recovered_from_backup": false,
		"digest": "", "writer_active": false, "errors": PackedStringArray(errors), "compatibility_errors": PackedStringArray()}


static func _failure(message: String) -> Dictionary:
	return _result(false, PackedStringArray([message]))


static func _result(ok: bool, errors: Variant) -> Dictionary:
	return {"ok": ok, "errors": PackedStringArray(errors)}
