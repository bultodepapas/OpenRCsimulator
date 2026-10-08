extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
func _initialize() -> void:
	var baseline: Script = load(OS.get_environment("OPENRC_DATA2_BASELINE"))
	for file in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var path: String = "res://data/aircraft/" + file + ".json"
		var baseline_ms: Array[float] = []
		var candidate_ms: Array[float] = []
		var same: bool = true
		for i in 12:
			var old: Dictionary
			var new: Dictionary
			for version in ([0, 1] if i % 2 == 0 else [1, 0]):
				var begin: int = Time.get_ticks_usec()
				if version == 0:
					old = baseline.load_file(path)
					baseline_ms.append((Time.get_ticks_usec() - begin) / 1000.0)
				else:
					new = AD.load_file(path)
					candidate_ms.append((Time.get_ticks_usec() - begin) / 1000.0)
			same = same and old == new and old.ok
		var sorted: Array[float] = candidate_ms.duplicate()
		sorted.sort()
		print(JSON.stringify({aircraft = file, exact_load_result = same, baseline_ms = baseline_ms, candidate_ms = candidate_ms, candidate_median_ms = 0.5*(sorted[5]+sorted[6])}))
		if not same:
			quit(1)
			return
	quit()
