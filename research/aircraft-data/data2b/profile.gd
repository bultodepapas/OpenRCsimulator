# DATA-2b: whole-load cost versus its envelope stage; instrumentation lives in a disposable loader.
extends SceneTree
func _initialize() -> void:
	if not FileAccess.file_exists(OS.get_environment("OPENRC_PROFILE_LOADER")):
		printerr("FAIL missing OPENRC_PROFILE_LOADER")
		quit(2)
		return
	var loader: Script = load(OS.get_environment("OPENRC_PROFILE_LOADER"))
	for file in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var rows := []
		for i in 16:
			var begin := Time.get_ticks_usec()
			var result: Dictionary = loader.load_file("res://data/aircraft/" + file + ".json")
			var elapsed := Time.get_ticks_usec() - begin
			if not result.ok:
				push_error(str(result.errors))
				quit(1)
				return
			rows.append({load_us = elapsed, envelope_us = loader.envelope_us, induced_us = loader.induced_us, map_calls = loader.map_calls})
		print(JSON.stringify({aircraft = file, rows = rows}))
	quit()
