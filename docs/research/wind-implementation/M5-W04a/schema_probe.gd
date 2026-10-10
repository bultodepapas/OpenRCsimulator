# Run against current app to write, then the frozen fca70b2 app to test older-reader protection.
# godot --headless --path <app> --script <absolute probe path> -- --write|--read --settings=<path> --out=<json>
extends SceneTree
const Preferences = preload("res://app_state/preferences.gd")
const Weather = preload("res://physics/wind_config.gd")
func _initialize() -> void:
	var writing := false
	var path := "/tmp/openrc-turbulence-schema2.cfg"
	var output_path := "/tmp/openrc-older-reader.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--write":
			writing = true
		elif arg.begins_with("--settings="):
			path = arg.trim_prefix("--settings=")
		elif arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
	if writing:
		var settings: Dictionary = Preferences.DEFAULTS.duplicate(true)
		settings.weather_config = Weather.preset("turbulent")
		var error: Error = Preferences.save_to(path, settings)
		quit(0 if error == OK else 1)
		return
	var before := FileAccess.get_sha256(path)
	var settings: Dictionary = Preferences.load_from(path)
	settings.language = "es"
	var error: Error = Preferences.save_to(path, settings)
	var after := FileAccess.get_sha256(path)
	var report: Dictionary = {reader_schema = Preferences.SCHEMA, writable = settings.writable, save_error = error,
		file_sha256_before = before, file_sha256_after = after, unchanged = before == after}
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify(report,"\t",true,true)+"\n")
	quit(0 if not settings.writable and error == ERR_FILE_NO_PERMISSION and before == after else 1)
