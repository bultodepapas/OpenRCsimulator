extends RefCounted

const Frames = preload("res://render/frames.gd")
const Ground = preload("res://render/ground.gd")

const ID: String = "green_paradise"
const DISPLAY_NAME: String = "Green paradise"
const FIELD_PATH: String = "res://landscapes/green_paradise/field.json"
const GROUND_SUBDIVISIONS: int = 63


static func build(field: Dictionary, lighting: Dictionary = {}) -> Node3D:
	var result: Node3D = Node3D.new()
	result.name = "Field"

	var grass: ShaderMaterial = Ground.grass_material(lighting)
	var station: Vector3 = Frames.ned_to_render([
		float(field.pilot.north),
		float(field.pilot.east),
		0.0,
	])
	grass.set_shader_parameter("pilot_xz", Vector2(station.x, station.z))

	var ground_surface: Dictionary = {}
	for surface: Dictionary in field.get("surfaces", []):
		if surface.get("type", "") == "rough":
			ground_surface = surface
			break
	if not ground_surface.is_empty():
		var ground: MeshInstance3D = MeshInstance3D.new()
		ground.name = "rough"
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(
			float(ground_surface.length_east_west),
			float(ground_surface.width_north_south),
		)
		plane.subdivide_width = GROUND_SUBDIVISIONS
		plane.subdivide_depth = GROUND_SUBDIVISIONS
		ground.mesh = plane
		ground.position = Frames.ned_to_render([
			float(ground_surface.center_north),
			float(ground_surface.center_east),
			0.0,
		])
		ground.material_override = grass
		result.add_child(ground)

	var materials: Array[ShaderMaterial] = [grass]
	result.set_meta("lighting_materials", materials)
	result.set_meta("lighting_snapshot", lighting.duplicate(true))
	return result


static func collision_world(_field: Dictionary) -> Dictionary:
	return {ok = true, world = {}, errors = PackedStringArray()}