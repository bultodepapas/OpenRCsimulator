# L5: render only validated openrc-field v1 data. No camera, atmosphere, aircraft or simulation.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const Treeline = preload("res://render/treeline.gd")
const Ground = preload("res://render/ground.gd")
const NearGrass = preload("res://render/near_grass.gd")
const Horizon = preload("res://render/horizon.gd")
const PilotStation = preload("res://render/pilot_station.gd")
const Windsock = preload("res://render/windsock.gd")
const Scenery = preload("res://scenery/scenery.gd") # SCENERY-PLAN: no-op unless --scenery=on / OPENRC_SCENERY=on
# Legacy fallback separation only; ordinary fields paint their surfaces in the rough ground pass.
const SURFACE_LIFT: Dictionary = {"rough": 0.0, "mown": 0.015, "runway": 0.03}
const GROUND_SUBDIVISIONS := 63


static func build(field: Dictionary) -> Node3D:
	var result: Node3D = Node3D.new()
	result.name = "Field"
	# L9c: one ground pass for contained flat rectangles; retain legacy geometry for other valid fields.
	var grass: ShaderMaterial = Ground.grass_material()
	var station := Frames.ned_to_render([field.pilot.north, field.pilot.east, 0.0])
	grass.set_shader_parameter("pilot_xz", Vector2(station.x, station.z)) # Phase 2: the macro tone is pinned here
	var consolidated: bool = Ground.configure_surfaces(grass, field.surfaces)
	result.set_meta("surfaces_consolidated", consolidated)
	for surface: Dictionary in field.surfaces:
		if consolidated and surface.type != "rough":
			continue
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = surface.id
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(surface.length_east_west, surface.width_north_south)
		if surface.type == "rough":
			# G-1: a 40 km plane of two triangles interpolates depth badly once clipped and hid the 3 cm runway in raised
			# views (SC-01: 4 of 12 views at 30 m). 64 × 64 quads (8,192 triangles, one draw) fix it with margin.
			plane.subdivide_width = GROUND_SUBDIVISIONS
			plane.subdivide_depth = GROUND_SUBDIVISIONS
		mesh_instance.mesh = plane
		# L7: replace the default footprint, never stack hills over the old plane. Small/custom rectangles
		# retain L5's flat contract. No collision or simulation heights are introduced by this renderer.
		if surface.type == "rough" and plane.size == Vector2(40000.0, 40000.0):
			mesh_instance.mesh = Horizon.mesh()
		mesh_instance.position = Frames.ned_to_render([surface.center_north, surface.center_east, -float(SURFACE_LIFT[surface.type])])
		var half := Vector2(surface.length_east_west, surface.width_north_south) / 2.0
		mesh_instance.material_override = grass if surface.type == "rough" \
			else Ground.surface_material(grass, surface.type, Vector2(mesh_instance.position.x, mesh_instance.position.z), half)
		result.add_child(mesh_instance)
	for object_data: Dictionary in field.objects:
		result.add_child(Treeline.build(object_data, field.pilot))
	result.add_child(NearGrass.build(field, grass))
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.type == "pilot_station":
			result.add_child(PilotStation.build(cue))
		else:
			result.add_child(Windsock.build(cue))
	Scenery.attach(result, field)
	return result
