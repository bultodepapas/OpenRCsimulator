## Automatic trace destinations are reserved by creating a unique directory.
## A completed CSV is published inside that directory only after its writer flushes.
extends RefCounted

const DEFAULT_DIRECTORY := "user://traces"
const MAX_RESERVATIONS := 10000


static func save(trace: RefCounted, prefix: String, directory: String = DEFAULT_DIRECTORY, timestamp: String = "") -> Dictionary:
	if timestamp.is_empty():
		timestamp = Time.get_datetime_string_from_system(true).replace(":", "-")
	var root := ProjectSettings.globalize_path(directory)
	var error := DirAccess.make_dir_recursive_absolute(root)
	if error != OK and not (error == ERR_ALREADY_EXISTS and DirAccess.dir_exists_absolute(root)):
		return {error = error, path = ""}
	for index in MAX_RESERVATIONS:
		var suffix := "" if index == 0 else "-%d" % index
		var reserved := root.path_join("%s-%s%s" % [prefix, timestamp, suffix])
		error = DirAccess.make_dir_absolute(reserved)
		if error == ERR_ALREADY_EXISTS:
			continue
		if error != OK:
			return {error = error, path = ""}
		var staged := reserved.path_join("recording.partial")
		var destination := reserved.path_join(prefix + ".csv")
		error = trace.save(staged)
		if error == OK:
			# Only the owner of this newly created directory writes its destination.
			if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
				error = ERR_ALREADY_EXISTS
			else:
				error = DirAccess.rename_absolute(staged, destination)
		if error != OK:
			# Never remove an existing destination or a nonempty directory.
			if FileAccess.file_exists(staged):
				DirAccess.remove_absolute(staged)
			DirAccess.remove_absolute(reserved)
			return {error = error, path = ""}
		return {error = OK, path = destination}
	return {error = ERR_ALREADY_EXISTS, path = ""}
