## L9b-R3: scene-owned field turf for the existing opaque worn-path shoulder.
extends RefCounted

const MATERIAL_META := "ground_detail_material"
const SHADER := preload("res://scenery/gravel.gdshader")
const SceneDetail := preload("res://render/scene_detail.gd")
const PARAMETERS: Array[StringName] = [
	&"grass", &"tile_m", &"anti_tiling", &"macro_amp", &"dry_amount", &"pilot_xz", &"pilot_pin_m",
	&"club_field_detail", &"turf_detail", &"turf_detail_strength", &"grass_photo_enabled", &"rc_grass_albedo",
]


## Independent launch override; otherwise follow the saved Scene detail at the next build.
static func enabled() -> bool:
	var requested := OS.get_environment("OPENRC_WORN_PATH_TURF").strip_edges().to_lower()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--worn_path_turf="):
			requested = argument.trim_prefix("--worn_path_turf=").strip_edges().to_lower()
	if requested == "on":
		return true
	if requested == "off":
		return false
	return bool(SceneDetail.profile().worn_path_turf)


static func bind(scenery: Node, ground: ShaderMaterial) -> bool:
	if scenery == null:
		return false
	var material: ShaderMaterial = scenery.get_meta(MATERIAL_META, null) as ShaderMaterial
	if material == null or material.shader != SHADER:
		return false
	material.set_shader_parameter("field_turf_enabled", false)
	if ground == null or ground.shader == null or ground.get_shader_parameter("grass") == null:
		for parameter: StringName in PARAMETERS:
			material.set_shader_parameter(parameter, null)
		return false
	for parameter: StringName in PARAMETERS:
		var value: Variant = ground.get_shader_parameter(parameter)
		if value == null:
			value = RenderingServer.shader_get_parameter_default(ground.shader.get_rid(), parameter)
		# The dummy renderer cannot resolve uniforms. Null keeps the canonical
		# defaults from the same shared shader includes on the destination.
		material.set_shader_parameter(parameter, value)
	material.set_shader_parameter("field_turf_enabled", true)
	return true
