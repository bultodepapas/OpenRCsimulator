# Reproducible synthetic families for D8b-R2 pipeline testing; no member is a calibrated repair.
extends SceneTree
const Fixture := preload("res://tests/wing_polar_fixture.gd")
const AD := preload("res://physics/aircraft_data.gd")


func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../research/flight-robustness/d8b-r2/candidates")
	var check_only := "--check" in OS.get_cmdline_user_args()
	if not check_only:
		DirAccess.make_dir_recursive_absolute(folder)
	for name in {steep = 0.5, intermediate = 0.7, retained = 0.9}:
		var raw := Fixture.raw({steep = 0.5, intermediate = 0.7, retained = 0.9}[name])
		var validation := AD.validate_and_derive(raw)
		if not validation.ok:
			printerr(validation.errors)
			quit(1)
			return
		var content := JSON.stringify(raw,"  ",true,true)+"\n"
		var path: String = folder.path_join(name+".json")
		if check_only:
			if FileAccess.get_file_as_string(path) != content:
				printerr("stale or missing synthetic polar candidate: ",path)
				quit(1)
				return
		else:
			var file := FileAccess.open(path,FileAccess.WRITE)
			if file == null:
				quit(1)
				return
			file.store_string(content)
			file.close()
	print("3 synthetic polar candidates %s; NONE selected for production" % ("verified" if check_only else "generated"))
	quit(0)
