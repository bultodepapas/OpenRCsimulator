# DATA-4a: use the production file loader; Python owns cases and expectations.
# Run outside app/ so this offline harness is not a runtime dependency.
extends SceneTree

const AircraftData = preload("res://physics/aircraft_data.gd")


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("expected one manifest path")
		quit(2)
		return
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not paths is Array or paths.is_empty():
		printerr("invalid or empty manifest")
		quit(2)
		return
	for index in paths.size():
		var result: Dictionary = AircraftData.load_file(str(paths[index]))
		print("DATA4A ", JSON.stringify({"index": index, "ok": result.ok, "errors": result.errors}))
	quit(0)
