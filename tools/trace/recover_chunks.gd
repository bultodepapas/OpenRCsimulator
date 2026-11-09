## Developer recovery of an interrupted manual T recording. Never marks a prefix complete.
extends SceneTree

const Store := preload("res://sim/trace_chunk_store.gd")


func _initialize() -> void:
	var source := ""
	var destination := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--spool="):
			source = argument.trim_prefix("--spool=")
		elif argument.begins_with("--out="):
			destination = argument.trim_prefix("--out=")
		else:
			printerr("Unknown recovery argument: " + argument)
			quit(2)
			return
	if source.is_empty() or destination.is_empty():
		printerr("Usage: -- --spool=<trace-spool-directory> --out=<new-output-directory>")
		quit(2)
		return
	var result := Store.recover_csv(source, destination)
	print(JSON.stringify(result))
	print("TRACE_CHUNK_RECOVERY_COMPLETE")
	quit(0 if result.get("error", ERR_INVALID_DATA) == OK else 1)
