## L9d: activity-local material binding. No simulation, geometry or global state changes.
extends RefCounted

const GROUND_SHADER := preload("res://render/ground.gdshader")
const DIRT_ALBEDO := preload("res://assets/landscape/rc-ground/dirt-albedo.jpg")
const DIRT_NORMAL := preload("res://assets/landscape/rc-ground/dirt-normal.jpg")
const DIRT_ROUGHNESS := preload("res://assets/landscape/rc-ground/dirt-roughness.jpg")
const GRASS_ALBEDO := preload("res://assets/landscape/rc-ground/grass-albedo.jpg")
const GRASS_NORMAL := preload("res://assets/landscape/rc-ground/grass-normal.jpg")
const GRASS_ROUGHNESS := preload("res://assets/landscape/rc-ground/grass-roughness.jpg")

static func configure(material: ShaderMaterial) -> void:
	material.set_shader_parameter("rc_surface_enabled", true)
	material.set_shader_parameter("rc_dirt_albedo", DIRT_ALBEDO)
	material.set_shader_parameter("rc_dirt_normal", DIRT_NORMAL)
	material.set_shader_parameter("rc_dirt_roughness", DIRT_ROUGHNESS)
	material.set_shader_parameter("rc_grass_albedo", GRASS_ALBEDO)
	material.set_shader_parameter("rc_grass_normal", GRASS_NORMAL)
	material.set_shader_parameter("rc_grass_roughness", GRASS_ROUGHNESS)

static func configure_field(field_node: Node3D) -> ShaderMaterial:
	var ground: ShaderMaterial
	for material: ShaderMaterial in field_node.get_meta("lighting_materials", []):
		if material.shader == GROUND_SHADER:
			configure(material)
			if ground == null:
				ground = material
	return ground
