extends SceneTree
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	for id: String in ["classic", "clear", "cirrus", "fair_cumulus", "broken", "overcast", "prestorm", "distant_storm", "electrical_storm"]:
		check("pack profile " + id, SkyConfig.validate(SkyConfig.for_preset(id)).ok)
		check("pack thumbnail " + id, load("res://assets/sky/weather/previews/" + id + ".png") is Texture2D)
	check("pack thunder", load("res://assets/audio/storm/thunder_01.ogg") is AudioStreamOggVorbis)
	check("pack MIT notice", FileAccess.get_file_as_string("res://assets/sky/weather/LICENSES.md").contains("AurelienCaille"))
	check("pack CC0 notice", FileAccess.get_file_as_string("res://assets/audio/storm/LICENSE.txt").contains("rubberduck"))
	check("pack storm shader", load("res://render/weather/cloud_flash.gdshader") is Shader)
	check("pack sky checkpoint", load("res://app_state/sky_checkpoint.gd") is Script)
	print("sky package checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)
