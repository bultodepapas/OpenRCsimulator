extends "res://main.gd"
## L1–L4 reference field, frozen at VQ-01a. Keep sky, ground haze, runway and aircraft probes;
## future trees/props/terrain belong to main's field, never to this fixture.
## This intentionally duplicates the two simple reference meshes, not production field construction.

func _build_field() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Spec.GROUND_SIZE, Spec.GROUND_SIZE)
	ground.mesh = plane
	var grass: ShaderMaterial = Ground.grass_material()
	# L1–L4 isolates sky/radiance drift; L15d moving ground shadows are checked on the production field.
	grass.set_shader_parameter("cloud_shadow_strength", 0.0)
	ground.material_override = grass
	add_child(ground)

	var runway := MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(Spec.RUNWAY.length_east_west, Spec.RUNWAY.width_north_south)
	runway.mesh = strip
	runway.material_override = Ground.runway_material()
	runway.position = Frames.ned_to_render([Spec.RUNWAY.center_north, 0.0, -0.03])
	add_child(runway)


func _capture_scene_id() -> String:
	return "atmosphere"
