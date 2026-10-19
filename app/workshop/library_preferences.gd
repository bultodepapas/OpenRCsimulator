extends RefCounted
## Bounded, data-only UI metadata beside immutable Workshop variant records.

const StrictJSON := preload("res://workshop/strict_json.gd")
const DEFAULT_ROOT: String = "user://aircraft_variants"
const FILE_NAME: String = "_favorites.json"
const FORMAT: String = "openrc-aircraft-library-preferences"
const VERSION: int = 1
const MAX_FAVORITES: int = 256
const MAX_STATE_BYTES: int = 16384
const MAX_JSON_DEPTH: int = 4
const MAX_JSON_NODES: int = 1024


class WriteGuard extends RefCounted:
	var directory: String = ""
	var acquired: bool = false

	func _init(root_path: String) -> void:
		var locks_root: String = root_path.path_join("_locks")
		if DirAccess.make_dir_recursive_absolute(locks_root) != OK:
			return
		directory = locks_root.path_join("_favorites")
		acquired = DirAccess.make_dir_absolute(directory) == OK

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and acquired:
			DirAccess.remove_absolute(directory)


static func load_state(root: String = DEFAULT_ROOT) -> Dictionary:
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		return _result(false, root_result["errors"])
	return _load_from_root(str(root_result["path"]))


static func set_favorite(id: String, value: bool, root: String = DEFAULT_ROOT) -> Dictionary:
	if not _valid_variant_uuid(id):
		return _result(false, PackedStringArray(["Favorite ID must be a lowercase RFC 4122 version-4 variant UUID."]))
	var root_result: Dictionary = _resolve_root(root)
	if not bool(root_result["ok"]):
		return _result(false, root_result["errors"])
	var root_path: String = str(root_result["path"])
	var preflight: Dictionary = _load_from_root(root_path)
	if not bool(preflight["ok"]):
		return _result(false, preflight["errors"])
	var make_error: Error = DirAccess.make_dir_recursive_absolute(root_path)
	if make_error != OK and not DirAccess.dir_exists_absolute(root_path):
		return _result(false, PackedStringArray(["Could not create Workshop preferences directory (%s)." % error_string(make_error)]))
	var guard := WriteGuard.new(root_path)
	if not guard.acquired:
		return _result(false, PackedStringArray(["Workshop library preferences are busy or their write lock is unavailable."]))
	var current: Dictionary = _load_from_root(root_path)
	if not bool(current["ok"]):
		return _result(false, current["errors"])
	var favorites: Array[String] = current["favorites"].duplicate()
	var present: bool = favorites.has(id)
	if present == value:
		return _result(true, PackedStringArray(), favorites, bool(current.get("recovered_from_backup", false)))
	if value:
		if favorites.size() >= MAX_FAVORITES:
			return _result(false, PackedStringArray(["The Workshop library supports at most %d favorites." % MAX_FAVORITES]), favorites)
		favorites.append(id)
	else:
		favorites.erase(id)
	favorites.sort()
	var write_result: Dictionary = _write_state_atomic(root_path, favorites)
	if not bool(write_result["ok"]):
		return _result(false, write_result["errors"], current["favorites"])
	return _result(true, PackedStringArray(), favorites)


static func _load_from_root(root_path: String) -> Dictionary:
	var state_path: String = root_path.path_join(FILE_NAME)
	var backup_path: String = state_path + ".bak"
	if DirAccess.dir_exists_absolute(state_path):
		return _result(false, PackedStringArray(["Workshop favorites path is a directory, not a state file."]))
	if FileAccess.file_exists(state_path):
		return _read_state_file(state_path)
	if DirAccess.dir_exists_absolute(backup_path):
		return _result(false, PackedStringArray(["Workshop favorites backup path is a directory, not a state file."]))
	if FileAccess.file_exists(backup_path):
		var recovered: Dictionary = _read_state_file(backup_path)
		if not bool(recovered["ok"]):
			var errors := PackedStringArray(["Current favorites file is missing and its backup is invalid."])
			errors.append_array(recovered["errors"])
			return _result(false, errors)
		recovered["recovered_from_backup"] = true
		return recovered
	return _result(true, PackedStringArray(), [])


static func _read_state_file(path: String) -> Dictionary:
	var read_result: Dictionary = _read_bytes(path)
	if not bool(read_result["ok"]):
		return _result(false, read_result["errors"])
	return _parse_state_bytes(read_result["bytes"])


static func _parse_state_bytes(bytes: PackedByteArray) -> Dictionary:
	var parsed: Dictionary = StrictJSON.parse(bytes, MAX_STATE_BYTES, MAX_JSON_DEPTH, MAX_JSON_NODES)
	if not bool(parsed["ok"]):
		return _result(false, parsed["errors"])
	var document: Variant = parsed["data"]
	if typeof(document) != TYPE_DICTIONARY:
		return _result(false, PackedStringArray(["Workshop favorites must be a JSON object."]))
	var state: Dictionary = document
	if state.size() != 3 or not state.has("format") or not state.has("version") or not state.has("favorites"):
		return _result(false, PackedStringArray(["Workshop favorites contain missing or unknown fields."]))
	if typeof(state["format"]) != TYPE_STRING or str(state["format"]) != FORMAT:
		return _result(false, PackedStringArray(["Workshop favorites format is not supported."]))
	if not _integer_number(state["version"]) or int(state["version"]) != VERSION:
		return _result(false, PackedStringArray(["Workshop favorites version is not supported."]))
	if typeof(state["favorites"]) != TYPE_ARRAY:
		return _result(false, PackedStringArray(["Workshop favorites must be an array of variant UUIDs."]))
	var source: Array = state["favorites"]
	if source.size() > MAX_FAVORITES:
		return _result(false, PackedStringArray(["Workshop favorites exceed the %d-item limit." % MAX_FAVORITES]))
	var favorites: Array[String] = []
	for item: Variant in source:
		if typeof(item) != TYPE_STRING or not _valid_variant_uuid(str(item)):
			return _result(false, PackedStringArray(["Workshop favorites contain an invalid variant UUID."]))
		var id: String = str(item)
		if favorites.has(id):
			return _result(false, PackedStringArray(["Workshop favorites contain a duplicate UUID."]))
		favorites.append(id)
	favorites.sort()
	return _result(true, PackedStringArray(), favorites)


static func _write_state_atomic(root_path: String, favorites: Array[String]) -> Dictionary:
	var errors := PackedStringArray()
	var state_path: String = root_path.path_join(FILE_NAME)
	var backup_path: String = state_path + ".bak"
	if DirAccess.dir_exists_absolute(state_path):
		errors.append("Workshop favorites path is a directory, not a state file.")
		return {"ok": false, "errors": errors}
	var document: Dictionary = {"format": FORMAT, "version": VERSION, "favorites": favorites.duplicate()}
	var bytes: PackedByteArray = (JSON.stringify(document, "\t", true, true) + "\n").to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > MAX_STATE_BYTES:
		errors.append("Workshop favorites output exceeds its byte limit.")
		return {"ok": false, "errors": errors}
	var temporary: String = ""
	for attempt: int in range(8):
		var nonce: String = _new_uuid()
		if nonce.is_empty():
			break
		var candidate: String = state_path + ".tmp-" + nonce
		if not FileAccess.file_exists(candidate) and not DirAccess.dir_exists_absolute(candidate):
			temporary = candidate
			break
	if temporary.is_empty():
		errors.append("Could not reserve a unique favorites temporary file.")
		return {"ok": false, "errors": errors}
	var write_result: Dictionary = _write_bytes(temporary, bytes)
	if not bool(write_result["ok"]):
		errors.append_array(write_result["errors"])
		return {"ok": false, "errors": errors}
	var readback: Dictionary = _read_bytes(temporary)
	if not bool(readback["ok"]) or (readback.get("bytes", PackedByteArray()) as PackedByteArray) != bytes:
		DirAccess.remove_absolute(temporary)
		errors.append("Temporary favorites file failed exact-byte readback.")
		return {"ok": false, "errors": errors}
	var checked: Dictionary = _parse_state_bytes(bytes)
	if not bool(checked["ok"]) or checked.get("favorites", []) != favorites:
		DirAccess.remove_absolute(temporary)
		errors.append("Temporary favorites file failed schema readback.")
		return {"ok": false, "errors": errors}
	var moved_current: bool = false
	if FileAccess.file_exists(state_path):
		var backup_remove: Error = _remove_existing(backup_path)
		if backup_remove != OK:
			DirAccess.remove_absolute(temporary)
			errors.append("Could not rotate the prior favorites backup (%s)." % error_string(backup_remove))
			return {"ok": false, "errors": errors}
		var move_error: Error = DirAccess.rename_absolute(state_path, backup_path)
		if move_error != OK:
			DirAccess.remove_absolute(temporary)
			errors.append("Could not preserve the prior favorites file (%s)." % error_string(move_error))
			return {"ok": false, "errors": errors}
		moved_current = true
	elif DirAccess.dir_exists_absolute(backup_path):
		errors.append("Workshop favorites backup path is a directory, not a state file.")
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "errors": errors}
	var commit_error: Error = DirAccess.rename_absolute(temporary, state_path)
	if commit_error != OK:
		if moved_current and not FileAccess.file_exists(state_path) and not DirAccess.dir_exists_absolute(state_path):
			var rollback_error: Error = DirAccess.rename_absolute(backup_path, state_path)
			if rollback_error != OK:
				errors.append("Could not restore the previous favorites file (%s)." % error_string(rollback_error))
		DirAccess.remove_absolute(temporary)
		errors.append("Could not atomically replace Workshop favorites (%s)." % error_string(commit_error))
		return {"ok": false, "errors": errors}
	var final_readback: Dictionary = _read_bytes(state_path)
	if not bool(final_readback["ok"]) or (final_readback.get("bytes", PackedByteArray()) as PackedByteArray) != bytes:
		DirAccess.remove_absolute(state_path)
		if moved_current and FileAccess.file_exists(backup_path) and not DirAccess.dir_exists_absolute(state_path):
			var restore_error: Error = DirAccess.rename_absolute(backup_path, state_path)
			if restore_error != OK:
				errors.append("Could not restore the previous favorites file (%s)." % error_string(restore_error))
		errors.append("Committed favorites file failed exact-byte readback.")
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors}


static func _read_bytes(path: String) -> Dictionary:
	var errors := PackedStringArray()
	if DirAccess.dir_exists_absolute(path):
		errors.append("Favorites state path is a directory.")
		return {"ok": false, "errors": errors}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Could not open favorites state file (%s)." % error_string(FileAccess.get_open_error()))
		return {"ok": false, "errors": errors}
	var length: int = file.get_length()
	if length <= 0 or length > MAX_STATE_BYTES:
		file.close()
		errors.append("Favorites state file is empty or exceeds the %d-byte limit." % MAX_STATE_BYTES)
		return {"ok": false, "errors": errors}
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK or bytes.size() != length:
		errors.append("Could not read the complete favorites state file.")
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors, "bytes": bytes}


static func _write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var errors := PackedStringArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("Could not open a temporary favorites file (%s)." % error_string(FileAccess.get_open_error()))
		return {"ok": false, "errors": errors}
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(path)
		errors.append("Could not flush temporary favorites data (%s)." % error_string(write_error))
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors}


static func _remove_existing(path: String) -> Error:
	if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
		return DirAccess.remove_absolute(path)
	return OK


static func _resolve_root(root: String) -> Dictionary:
	var errors := PackedStringArray()
	if not root.begins_with("user://") or root.contains("\\") or root.substr("user://".length()).contains(":"):
		errors.append("Workshop preferences root must be a safe path under user://.")
		return {"ok": false, "errors": errors}
	var relative: String = root.substr("user://".length())
	while relative.ends_with("/"):
		relative = relative.substr(0, relative.length() - 1)
	if relative.is_empty():
		errors.append("Workshop preferences root cannot be the user data directory itself.")
		return {"ok": false, "errors": errors}
	for segment: String in relative.split("/", false):
		if segment.is_empty() or segment == "." or segment == "..":
			errors.append("Workshop preferences root contains an unsafe path segment.")
			return {"ok": false, "errors": errors}
		for index: int in range(segment.length()):
			var code: int = segment.unicode_at(index)
			var allowed: bool = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95 or code == 46
			if not allowed:
				errors.append("Workshop preferences root contains an unsupported path character.")
				return {"ok": false, "errors": errors}
	var absolute: String = ProjectSettings.globalize_path("user://" + relative)
	var user_absolute: String = ProjectSettings.globalize_path("user://")
	var normalized_lower: String = absolute.replace("\\", "/").to_lower()
	var user_lower: String = user_absolute.replace("\\", "/").trim_suffix("/").to_lower()
	if not normalized_lower.begins_with(user_lower + "/"):
		errors.append("Workshop preferences root resolves outside user data.")
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": errors, "path": absolute.replace("\\", "/")}


static func _valid_variant_uuid(value: String) -> bool:
	if value.length() != 36:
		return false
	for index: int in range(36):
		var code: int = value.unicode_at(index)
		if index == 8 or index == 13 or index == 18 or index == 23:
			if code != 45:
				return false
		elif not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return value[14] == "4" and value[19] in ["8", "9", "a", "b"]


static func _integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return floor(float(value)) == float(value) and abs(float(value)) <= 9007199254740991.0


static func _new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		return ""
	bytes[6] = (int(bytes[6]) & 15) | 64
	bytes[8] = (int(bytes[8]) & 63) | 128
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


static func _result(
		ok: bool,
		errors: PackedStringArray,
		favorites: Array[String] = [],
		recovered_from_backup: bool = false
) -> Dictionary:
	return {
		"ok": ok,
		"errors": errors,
		"favorites": favorites.duplicate(),
		"recovered_from_backup": recovered_from_backup,
	}
