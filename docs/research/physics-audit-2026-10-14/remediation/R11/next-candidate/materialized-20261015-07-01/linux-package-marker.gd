extends SceneTree

func _initialize() -> void:
	var packed_aircraft_data := FileAccess.file_exists("res://data/aircraft/jensen_ugly_stik_60.json")
	print("R11_EXPORTED_SCENETREE_MARKER enter packed_aircraft_data=", packed_aircraft_data)
	print("executable=", OS.get_executable_path())
	print("cwd=", DirAccess.open(".").get_current_dir())
	quit(0 if packed_aircraft_data else 9)
