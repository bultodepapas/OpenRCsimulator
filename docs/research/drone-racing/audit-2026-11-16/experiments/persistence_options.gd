# Option comparison, not a production repair. Run with the pinned checked runner and an isolated profile.
# Uses fresh disposable files and the existing PreferencesFile failure seam; never touches player settings.
# Linux observations and injected publication failure do not establish power-loss or cross-platform durability.
extends SceneTree

const Preferences := preload("res://app_state/preferences_file.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s %s" % ["ok  " if condition else "FAIL", label, detail])

func _write(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.flush()
	var result := file.get_error() == OK
	file.close()
	return result

func _config(marker: String) -> ConfigFile:
	var value := ConfigFile.new()
	value.set_value("meta", "schema", 1)
	value.set_value("audit", "marker", marker)
	return value

func _run() -> void:
	var folder := "user://fpv_persistence_options_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check("unique disposable folder creates", DirAccess.make_dir_absolute(folder) == OK)
	var target := folder.path_join("target.txt")
	var temporary := folder.path_join("candidate.txt")
	var missing := folder.path_join("missing.txt")
	_check("replacement fixtures write", _write(target, "old") and _write(temporary, "new"))
	var replaced := DirAccess.rename_absolute(temporary, target)
	_check("pinned Linux rename replaces a regular file without caller unlink", replaced == OK \
		and FileAccess.get_file_as_string(target) == "new" and not FileAccess.file_exists(temporary),
		"rename=%s" % error_string(replaced))
	_check("failure control rewrites accepted bytes", _write(target, "accepted"))
	var failed_rename := DirAccess.rename_absolute(missing, target)
	_check("failed Linux rename without caller unlink retains destination", failed_rename != OK \
		and FileAccess.get_file_as_string(target) == "accepted", "rename=%s" % error_string(failed_rename))
	var removed := DirAccess.remove_absolute(target)
	failed_rename = DirAccess.rename_absolute(missing, target)
	_check("unlink-before-failed-rename loses the previous destination", removed == OK and failed_rename != OK \
		and not FileAccess.file_exists(target))
	var prefs_path := folder.path_join("preferences.cfg")
	_check("existing PreferencesFile saves initial accepted configuration", Preferences.save(prefs_path, _config("accepted")) == OK)
	var accepted := FileAccess.get_file_as_bytes(prefs_path)
	var injected: Callable = func(_from: String, to: String) -> Error:
		# Models the documented Windows destination-removal failure, without pretending this is a Windows run.
		if DirAccess.remove_absolute(to) != OK:
			return FAILED
		return ERR_CANT_CREATE
	var saved := Preferences.save(prefs_path, _config("candidate"), injected)
	_check("existing transaction reports failed publication", saved == ERR_CANT_CREATE)
	_check("existing transaction restores exact previous bytes after destination removal", \
		FileAccess.get_file_as_bytes(prefs_path) == accepted)
	_check("rollback leaves no abandoned lock or backup", not DirAccess.dir_exists_absolute(prefs_path + Preferences.LOCK_SUFFIX) \
		and not FileAccess.file_exists(prefs_path + Preferences.PREVIOUS_SUFFIX))
	_check("subsequent ordinary save can publish after recovery", Preferences.save(prefs_path, _config("later")) == OK)
	var loaded := ConfigFile.new()
	_check("subsequent published configuration reads back", loaded.load(prefs_path) == OK \
		and loaded.get_value("audit", "marker", "") == "later")
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)
	print("persistence options: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
