extends "res://tests/bench_spatial_original.gd"

func _initialize() -> void:
	for case_id: String in SESSION_WEATHER_CASES:
		var checked: Dictionary = _session_weather_config(case_id)
		if not checked.ok:
			quit(1)
			return
		print(case_id, " ", JSON.stringify(checked.config, "", true, true).sha256_text())
	quit()
