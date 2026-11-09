## L9d: activity-local material binding. No simulation, geometry or global state changes.
extends RefCounted

const GROUND_SHADER := preload("res://render/ground.gdshader")
# Bind only when a circuit is built; importing this script must not load six 2K maps.
const TEXTURES := {
	"rc_dirt_albedo": "res://assets/landscape/rc-ground/dirt-albedo.jpg",
	"rc_dirt_normal": "res://assets/landscape/rc-ground/dirt-normal.jpg",
	"rc_dirt_roughness": "res://assets/landscape/rc-ground/dirt-roughness.jpg",
	"rc_grass_albedo": "res://assets/landscape/rc-ground/grass-albedo.jpg",
	"rc_grass_normal": "res://assets/landscape/rc-ground/grass-normal.jpg",
	"rc_grass_roughness": "res://assets/landscape/rc-ground/grass-roughness.jpg",
}

static func configure(material: ShaderMaterial) -> void:
	material.set_shader_parameter("rc_surface_enabled", true)
	for parameter: String in TEXTURES:
		material.set_shader_parameter(parameter, load(TEXTURES[parameter]))

static func configure_field(field_node: Node3D) -> ShaderMaterial:
	var ground: ShaderMaterial
	for material: ShaderMaterial in field_node.get_meta("lighting_materials", []):
		if material.shader == GROUND_SHADER:
			configure(material)
			if ground == null:
				ground = material
	return ground
