## Check actual exported resources and the notices that must travel with them.
extends SceneTree
func _initialize() -> void:
	var failures := 0
	for path: String in ["res://assets/crash/sources.json", "res://assets/crash/LICENSE-Kenney.txt", "res://assets/audio/crash/sources.json", "res://assets/audio/crash/LICENSE.txt"]:
		if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path).is_empty():
			printerr("FAIL missing packed notice: ",path)
			failures += 1
	for path: String in ["res://assets/crash/smoke.png", "res://assets/crash/flame.png"]:
		if not load(path) is Texture2D:
			printerr("FAIL missing packed texture: ",path)
			failures += 1
	for name: String in ["crack_heavy", "crack_light", "debris", "engine_cut", "fire_loop", "impact_dirt", "impact_grass", "impact_hard", "scrape", "secondary_hit", "tear", "turbine_spool"]:
		var stream: Variant = load("res://assets/audio/crash/"+name+".wav")
		if not stream is AudioStreamWAV or stream.get_length() <= 0:
			printerr("FAIL missing packed audio: ",name)
			failures += 1
	print("CR-22a pack: 18 resources/notices, %d failures" % failures)
	quit(1 if failures else 0)
