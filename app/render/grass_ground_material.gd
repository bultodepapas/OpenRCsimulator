## L9e-R2: shared grass detail only. Soil and track coverage remain owned by the RC binder.
extends RefCounted

const ALBEDO := preload("res://assets/landscape/rc-ground/grass-albedo.jpg")
const NORMAL := preload("res://assets/landscape/rc-ground/grass-normal.jpg")
const ROUGHNESS := preload("res://assets/landscape/rc-ground/grass-roughness.jpg")


static func configure(material: ShaderMaterial) -> void:
	material.set_shader_parameter("grass_photo_enabled", true)
	material.set_shader_parameter("rc_grass_albedo", ALBEDO)
	material.set_shader_parameter("rc_grass_normal", NORMAL)
	material.set_shader_parameter("rc_grass_roughness", ROUGHNESS)
