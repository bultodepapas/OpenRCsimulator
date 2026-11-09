## L9b-R3: scene-owned field turf for the existing opaque worn-path shoulder.
extends RefCounted

const MATERIAL_META := "ground_detail_material"
const SHADER := preload("res://scenery/gravel.gdshader")
const PARAMETERS: Array[StringName] = [
	&"grass", &"tile_m", &"anti_tiling", &"macro_amp", &"dry_amount", &"pilot_xz", &"pilot_pin_m",
	&"club_field_detail", &"turf_detail", &"turf_detail_strength", &"grass_photo_enabled", &"rc_grass_albedo",
]


static func bind(scenery: Node, ground: ShaderMaterial) -> bool:
	var material: ShaderMaterial = scenery.get_meta(MATERIAL_META, null) as ShaderMaterial
	if material == null or material.shader != SHADER:
		return false
	material.set_shader_parameter("field_turf_enabled", false)
	if ground == null or ground.shader == null or ground.get_shader_parameter("grass") == null:
		return false
	for parameter: StringName in PARAMETERS:
		var value: Variant = ground.get_shader_parameter(parameter)
		if value == null:
			value = RenderingServer.shader_get_parameter_default(ground.shader.get_rid(), parameter)
		material.set_shader_parameter(parameter, value)
	material.set_shader_parameter("field_turf_enabled", true)
	return true
