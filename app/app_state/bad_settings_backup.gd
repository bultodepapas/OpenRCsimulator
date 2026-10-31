# Preserve unreadable preferences for inspection without replacing earlier recoveries.
extends RefCounted

const MAX_BACKUPS := 1000


## Returns {error, backup}; on failure the original must remain protected from later saves.
static func preserve(path: String) -> Dictionary:
	var backup := path + ".bad"
	var parent_path := path.get_base_dir()
	var parent := DirAccess.open(parent_path if not parent_path.is_empty() else ".")
	var err := ERR_CANT_OPEN if parent == null else ERR_ALREADY_EXISTS
	# A directory at the conventional backup name is an obstruction, as in the original recovery contract.
	if parent != null and not DirAccess.dir_exists_absolute(backup):
		for index in range(MAX_BACKUPS):
			backup = path + ".bad" + ("" if index == 0 else ".%d" % index)
			if FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup) or parent.is_link(backup.get_file()):
				continue
			err = DirAccess.rename_absolute(path, backup)
			break
	return {error = err, backup = backup}
