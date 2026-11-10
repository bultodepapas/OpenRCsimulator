# Bounded settings transaction. Godot's Windows rename can remove the destination before failure.
extends RefCounted

const WeatherSettings := preload("res://physics/wind_config.gd")
const CURRENT_SCHEMA := 7
const WEATHER_EXACT_SCHEMA := 7
const WEATHER_WITNESS_FORMAT := "openrc-weather-witness v1"
# Valid weather has at most 16 layers, 32 gusts and 16 thermal cells, with bounded IDs.
const MAX_WEATHER_WITNESS_BYTES := 1024 * 1024
static var _serial := 0
const PREVIOUS_SUFFIX := ".openrc-previous"
const LOCK_SUFFIX := ".openrc-lock"


## Schemas 1-6 stay unchanged when the engine can write and read every weather bit.
static func weather_requires_witness(weather: Dictionary) -> bool:
	var probe := ConfigFile.new()
	probe.set_value("flight", "weather_config", weather)
	var text := probe.encode_to_text()
	var parsed := ConfigFile.new()
	if parsed.parse(text) != OK or parsed.encode_to_text() != text:
		return true
	var checked := WeatherSettings.validate(parsed.get_value("flight", "weather_config"))
	return not checked.ok or var_to_bytes(checked.config) != var_to_bytes(weather)


## Schema 7 stores canonical validated weather as object-free binary; the calm fallback is not authoritative.
static func set_weather_witness(config: ConfigFile, weather: Dictionary) -> Error:
	var payload := var_to_bytes(weather)
	if payload.is_empty() or payload.size() > MAX_WEATHER_WITNESS_BYTES:
		return ERR_INVALID_DATA
	config.set_value("flight", "weather_config", WeatherSettings.defaults())
	config.set_value("flight", "weather_exact_format", WEATHER_WITNESS_FORMAT)
	config.set_value("flight", "weather_exact_bytes", payload)
	config.set_value("flight", "weather_exact_sha256", _sha256(payload))
	return OK


static func read_weather_witness(config: ConfigFile) -> Dictionary:
	var failed := {ok = false, config = {}}
	for key: String in ["weather_config", "weather_exact_format", "weather_exact_bytes", "weather_exact_sha256"]:
		if not config.has_section_key("flight", key):
			return failed
	if config.get_value("flight", "weather_exact_format") != WEATHER_WITNESS_FORMAT:
		return failed
	var payload: Variant = config.get_value("flight", "weather_exact_bytes")
	var digest: Variant = config.get_value("flight", "weather_exact_sha256")
	if typeof(payload) != TYPE_PACKED_BYTE_ARRAY or payload.is_empty() \
			or payload.size() > MAX_WEATHER_WITNESS_BYTES or typeof(digest) != TYPE_STRING \
			or digest.length() != 64 or _sha256(payload) != digest:
		return failed
	# Only bytes_to_var (never bytes_to_var_with_objects) is allowed for this file.
	var decoded: Variant = bytes_to_var(payload)
	if typeof(decoded) != TYPE_DICTIONARY:
		return failed
	var checked := WeatherSettings.validate(decoded)
	if not checked.ok or var_to_bytes(checked.config) != payload:
		return failed
	var fallback: Variant = config.get_value("flight", "weather_config")
	var checked_fallback := WeatherSettings.validate(fallback)
	if not checked_fallback.ok or var_to_bytes(checked_fallback.config) != var_to_bytes(WeatherSettings.defaults()):
		return failed
	return {ok = true, config = checked.config}


static func _sha256(payload: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(payload) != OK:
		return ""
	return hashing.finish().hex_encode()


static func _check_current(config: ConfigFile) -> Error:
	var schema: Variant = config.get_value("meta", "schema", 0)
	if typeof(schema) != TYPE_INT:
		# Preserve the pre-schema-7 guard for coercible malformed/future version markers.
		if typeof(schema) in [TYPE_FLOAT, TYPE_STRING, TYPE_BOOL] and int(schema) > 6:
			return ERR_FILE_NO_PERMISSION
		return OK
	if schema > CURRENT_SCHEMA:
		return ERR_FILE_NO_PERMISSION
	if schema == WEATHER_EXACT_SCHEMA and not read_weather_witness(config).ok:
		return ERR_FILE_CORRUPT
	return OK


## One writer/recovery per profile, also across app processes. Unknown owners fail closed.
static func _acquire(path: String) -> Error:
	var lock := path + LOCK_SUFFIX
	if DirAccess.dir_exists_absolute(lock):
		# Never reclaim by PID: a second reclaimer could delete a new owner's lock.
		# An interrupted owner leaves accepted bytes/backup intact and requires explicit lock recovery.
		return ERR_BUSY
	var error := DirAccess.make_dir_absolute(lock)
	if error != OK:
		return error
	var file := FileAccess.open(lock.path_join("pid"), FileAccess.WRITE)
	if file == null:
		DirAccess.remove_absolute(lock)
		return ERR_CANT_CREATE
	file.store_string(str(OS.get_process_id()))
	error = file.get_error()
	file.close()
	if error != OK:
		_release(path)
	return error


static func _release(path: String) -> void:
	var lock := path + LOCK_SUFFIX
	DirAccess.remove_absolute(lock.path_join("pid"))
	DirAccess.remove_absolute(lock)


## A remaining previous file means publication was never acknowledged. Restore it before reading.
## This is transaction recovery only; ordinary preference loading does not write or migrate selection.
static func recover(path: String) -> Error:
	if not FileAccess.file_exists(path + PREVIOUS_SUFFIX):
		return OK
	var error := _acquire(path)
	if error != OK:
		return error
	error = _recover_locked(path)
	_release(path)
	return error


static func _recover_locked(path: String) -> Error:
	var previous := path + PREVIOUS_SUFFIX
	if not FileAccess.file_exists(previous):
		return OK
	var current := ConfigFile.new()
	if FileAccess.file_exists(path) and current.load(path) == OK:
		var current_error := _check_current(current)
		if current_error != OK:
			return current_error
	return _restore_locked(path)


static func _restore_locked(path: String) -> Error:
	var previous := path + PREVIOUS_SUFFIX
	var checked := ConfigFile.new()
	if checked.load(previous) != OK:
		return ERR_FILE_CORRUPT
	var previous_error := _check_current(checked)
	if previous_error != OK:
		return previous_error
	var bytes := FileAccess.get_file_as_bytes(previous)
	var error := DirAccess.copy_absolute(previous, path)
	if error != OK or FileAccess.get_file_as_bytes(path) != bytes:
		return error if error != OK else ERR_FILE_CORRUPT
	return DirAccess.remove_absolute(previous)


static func save(path: String, config: ConfigFile, publish := Callable()) -> Error:
	var error := _acquire(path)
	if error != OK:
		return error
	error = _save_locked(path, config, publish)
	_release(path)
	return error


static func _save_locked(path: String, config: ConfigFile, publish: Callable) -> Error:
	var current := ConfigFile.new()
	if FileAccess.file_exists(path) and current.load(path) == OK:
		var current_error := _check_current(current)
		if current_error != OK:
			return current_error
	var candidate_error := _check_current(config)
	if candidate_error != OK:
		return candidate_error
	var error := _recover_locked(path)
	if error != OK:
		return error
	_serial += 1
	var temporary := "%s.tmp-%d-%d" % [path, OS.get_process_id(), _serial]
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
		return ERR_ALREADY_EXISTS
	error = config.save(temporary)
	if error == OK:
		var checked := ConfigFile.new()
		error = checked.load(temporary)
		if error == OK and checked.encode_to_text() != config.encode_to_text():
			error = ERR_FILE_CORRUPT
		if error == OK:
			error = _check_current(checked)
	var previous := path + PREVIOUS_SUFFIX
	var previous_temporary := temporary + ".previous"
	if error == OK and FileAccess.file_exists(path):
		var accepted := ConfigFile.new()
		if accepted.load(path) != OK:
			error = ERR_FILE_CORRUPT
		else:
			var original := FileAccess.get_file_as_bytes(path)
			error = DirAccess.copy_absolute(path, previous_temporary)
			if error == OK and FileAccess.get_file_as_bytes(previous_temporary) != original:
				error = ERR_FILE_CORRUPT
			if error == OK:
				# Publish only a complete verified backup, to a destination that does not exist.
				error = DirAccess.rename_absolute(previous_temporary, previous)
	var expected := FileAccess.get_file_as_bytes(temporary) if error == OK else PackedByteArray()
	if error == OK:
		# The callable exercises the Windows failure after destination removal in disposable profiles.
		error = publish.call(temporary, path) if publish.is_valid() else DirAccess.rename_absolute(temporary, path)
		if error == OK and FileAccess.get_file_as_bytes(path) != expected:
			error = ERR_FILE_CORRUPT
		if error == OK and FileAccess.file_exists(previous):
			error = DirAccess.remove_absolute(previous)
		if error != OK and FileAccess.file_exists(previous):
			# This writer owns the attempted publication; restore its verified previous bytes directly.
			# If rollback fails, retain that copy for recover() on next load.
			_restore_locked(path)
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	if FileAccess.file_exists(previous_temporary):
		DirAccess.remove_absolute(previous_temporary)
	return error
