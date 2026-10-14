extends SceneTree
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const CLOUD_TEXTURES := {
	"FX_CloudAlpha03": "res://assets/sky/weather/clouds/FX_CloudAlpha03.png",
	"FX_CloudAlpha06": "res://assets/sky/weather/clouds/FX_CloudAlpha06.png",
}
var failures := 0
var checks := 0
var results: Array[Dictionary] = []

func _initialize() -> void:
	for id: String in ["classic", "clear", "cirrus", "fair_cumulus", "broken", "overcast", "prestorm", "distant_storm", "electrical_storm"]:
		check("pack profile " + id, SkyConfig.validate(SkyConfig.for_preset(id)).ok)
		check("pack thumbnail " + id, load("res://assets/sky/weather/previews/" + id + ".png") is Texture2D)
	check("pack thunder", load("res://assets/audio/storm/thunder_01.ogg") is AudioStreamOggVorbis)
	check("pack MIT notice", FileAccess.get_file_as_string("res://assets/sky/weather/LICENSES.md").contains("AurelienCaille"))
	check("pack CC0 notice", FileAccess.get_file_as_string("res://assets/audio/storm/LICENSE.txt").contains("rubberduck"))
	check("pack storm shader", load("res://render/weather/cloud_flash.gdshader") is Shader)
	check("pack sky checkpoint", load("res://app_state/sky_checkpoint.gd") is Script)
	for texture_name: String in CLOUD_TEXTURES:
		_check_cloud_texture(texture_name, str(CLOUD_TEXTURES[texture_name]))
	check("pack storm-bank shader", load("res://render/weather/storm_bank.gdshader") is Shader)
	check("pack rain-curtain shader", load("res://render/weather/rain_curtain.gdshader") is Shader)
	check("pack storm-bank script", load("res://render/weather/storm_bank.gd") is Script)
	var sky_notice: String = FileAccess.get_file_as_string("res://assets/sky/weather/LICENSES.md")
	check("pack WickedInsignia CC0 notice", sky_notice.contains("WickedInsignia") and sky_notice.contains("CC0 1.0"))
	for result: Dictionary in results:
		print("%s %s" % ["PASS" if result.passed else "FAIL", result.name])
	print("sky package checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _check_cloud_texture(texture_name: String, path: String) -> void:
	var texture: Texture2D = load(path) as Texture2D
	check("pack cloud texture resource " + texture_name, texture != null)
	if texture == null:
		return
	var image: Image = texture.get_image()
	check("pack cloud texture 2048x2048 " + texture_name,
		image != null and image.get_width() == 2048 and image.get_height() == 2048)
	check("pack cloud texture LA8 " + texture_name, image != null and image.get_format() == Image.FORMAT_LA8)
	check("pack cloud texture mipmaps " + texture_name, image != null and image.has_mipmaps())

func check(label: String, passed: bool) -> void:
	checks += 1
	results.append({"name": label, "passed": passed})
	if not passed:
		failures += 1
		printerr("FAIL " + label)
