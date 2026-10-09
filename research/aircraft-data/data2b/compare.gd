# DATA-2b: alternating whole-loader pairs, including exact model/diagnostic/input-identity bytes.
extends SceneTree
func _initialize() -> void:
	for key in ["OPENRC_DATA2B_BEFORE", "OPENRC_DATA2B_AFTER"]:
		if not FileAccess.file_exists(OS.get_environment(key)):
			printerr("FAIL missing loader path: ", key)
			quit(2)
			return
	var before: Script = load(OS.get_environment("OPENRC_DATA2B_BEFORE"))
	var after: Script = load(OS.get_environment("OPENRC_DATA2B_AFTER"))
	for file in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var rows := []
		for i in 24:
			var results := []
			results.resize(2)
			var times := [0, 0]
			for version in ([0, 1] if i % 2 == 0 else [1, 0]):
				var loader: Script = before if version == 0 else after
				var begin := Time.get_ticks_usec()
				results[version] = loader.load_file("res://data/aircraft/" + file + ".json")
				times[version] = Time.get_ticks_usec() - begin
			if not results[0].ok or var_to_bytes(results[0]) != var_to_bytes(results[1]):
				push_error("load result changed: " + file)
				quit(1)
				return
			rows.append({before_us = times[0], after_us = times[1]})
		print(JSON.stringify({aircraft = file, exact_pairs = rows.size(), rows = rows}))
	quit()
