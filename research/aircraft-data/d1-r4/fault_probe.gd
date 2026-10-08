extends SceneTree

func _initialize() -> void:
	var loader: Script = load(OS.get_environment("OPENRC_ENVELOPE_LOADER"))
	var failed: int = 0
	for file: String in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var result: Dictionary = loader.load_file("res://data/aircraft/%s.json" % file)
		var refused: bool = not result.ok and result.model.is_empty() and str(result.errors).contains("aero.envelope")
		print(JSON.stringify({aircraft = file, refused = refused, errors = Array(result.errors)}))
		if not refused:
			failed += 1
	print("D1-R4 solver faults: 4 checks, %d failed" % failed)
	quit(0 if failed == 0 else 1)
