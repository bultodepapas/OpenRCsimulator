# Bounded settings transaction. Godot's Windows rename can remove the destination before failure.
extends RefCounted

static var _serial := 0
const PREVIOUS_SUFFIX := ".openrc-previous"
const LOCK_SUFFIX := ".openrc-lock"


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
	if FileAccess.file_exists(path) and current.load(path) == OK and int(current.get_value("meta", "schema", 0)) > 6:
		return ERR_FILE_NO_PERMISSION
	var checked := ConfigFile.new()
	if checked.load(previous) != OK:
		return ERR_FILE_CORRUPT
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
	if FileAccess.file_exists(path) and current.load(path) == OK and int(current.get_value("meta", "schema", 0)) > 6:
		return ERR_FILE_NO_PERMISSION
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
			# If rollback itself fails, retain the validated previous copy for recover() on next load.
			_recover_locked(path)
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	if FileAccess.file_exists(previous_temporary):
		DirAccess.remove_absolute(previous_temporary)
	return error
