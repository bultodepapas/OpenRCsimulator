# L5: render only validated openrc-field v1 data. No camera, atmosphere, aircraft or simulation.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const Treeline = preload("res://render/treeline.gd")
const Ground = preload("res://render/ground.gd")
const Scenery = preload("res://scenery/scenery.gd") # SCENERY-PLAN: no-op unless --scenery=on / OPENRC_SCENERY=on
# Visual separation only, never terrain height or collision geometry. Higher priority wins overlaps.
const SURFACE_LIFT: Dictionary = {"rough": 0.0, "mown": 0.015, "runway": 0.03}


static func build(field: Dictionary) -> Node3D:
	var result: Node3D = Node3D.new()
	result.name = "Field"
	for surface: Dictionary in field.surfaces:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = surface.id
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(surface.length_east_west, surface.width_north_south)
		mesh_instance.mesh = plane
		mesh_instance.material_override = Ground.grass_material() if surface.type == "rough" else Ground.runway_material()
		mesh_instance.position = Frames.ned_to_render([surface.center_north, surface.center_east, -float(SURFACE_LIFT[surface.type])])
		result.add_child(mesh_instance)
	for object_data: Dictionary in field.objects:
		result.add_child(Treeline.build(object_data, field.pilot))
	Scenery.attach(result, field)
	return result
