# L5: render only validated openrc-field v1 data. No camera, aircraft or simulation state.
extends RefCounted

const Atmosphere = preload("res://render/atmosphere.gd")
const Frames = preload("res://render/frames.gd")
const Treeline = preload("res://render/treeline.gd")
const Ground = preload("res://render/ground.gd")
const NearGrass = preload("res://render/near_grass.gd")
const Horizon = preload("res://render/horizon.gd")
const PilotStation = preload("res://render/pilot_station.gd")
const FlightlineBarrier = preload("res://render/flightline_barrier.gd")
const FieldProjectedShadows = preload("res://render/field_projected_shadows.gd")
const FlightCueShadows = preload("res://render/flight_cue_shadows.gd")
const Windsock = preload("res://render/windsock.gd")
const Scenery = preload("res://scenery/scenery.gd") # SC-02a: on by default; explicit scenery-off remains a no-op.
# Legacy fallback separation only; ordinary fields paint their surfaces in the rough ground pass.
const SURFACE_LIFT: Dictionary = {"rough": 0.0, "mown": 0.015, "runway": 0.03}
const GROUND_SUBDIVISIONS := 63


static func build(field: Dictionary, lighting: Dictionary = {}) -> Node3D:
	var result: Node3D = Node3D.new()
	result.name = "Field"
	# L9c: one ground pass for contained flat rectangles; retain legacy geometry for other valid fields.
	var grass: ShaderMaterial = Ground.grass_material(lighting)
	var materials: Array[ShaderMaterial] = [grass]
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
		if not materials.has(mesh_instance.material_override):
			materials.append(mesh_instance.material_override as ShaderMaterial)
		result.add_child(mesh_instance)
	for object_data: Dictionary in field.objects:
		result.add_child(Treeline.build(object_data, field.pilot))
	var near_grass: Node3D = NearGrass.build(field, grass)
	result.add_child(near_grass)
	if near_grass.has_meta("lighting_material"):
		materials.append(near_grass.get_meta("lighting_material") as ShaderMaterial)
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.type == "pilot_station":
			result.add_child(PilotStation.build(cue))
		elif cue.type == "flightline_barrier":
			result.add_child(FlightlineBarrier.build(cue))
		else:
			result.add_child(Windsock.build(cue))
	if not field.get("flight_cues", []).is_empty():
		result.add_child(FlightCueShadows.build(field.flight_cues, lighting.has("solar")))
	Scenery.attach(result, field, lighting)
	FieldProjectedShadows.attach(result, field, lighting)
	result.set_meta("lighting_materials", materials)
	result.set_meta("lighting_snapshot", lighting.duplicate(true))
	return result


## Prepare shadow geometry before a checkpoint can commit physical state. Materials are retained by this field.
static func prepare_lighting(field_node: Node3D, lighting: Dictionary) -> Dictionary:
	if not field_node.has_meta("lighting_materials"):
		return {ok = false}
	var changed: bool = field_node.get_meta("lighting_snapshot") != lighting
	var scenery: Dictionary = Scenery.prepare_lighting(field_node, lighting) if changed else {ok = true}
	return {ok = scenery.ok, changed = changed, lighting = lighting.duplicate(true), scenery = scenery}


## No await: publish one snapshot across all cached consumers while retaining scene/resource ownership.
static func commit_lighting(field_node: Node3D, prepared: Dictionary) -> bool:
	if not prepared.changed:
		return false
	if not Scenery.commit_lighting(field_node, prepared.scenery):
		return false
	var lighting: Dictionary = prepared.lighting
	for mat: ShaderMaterial in field_node.get_meta("lighting_materials"):
		Atmosphere.update_ground_material(mat, lighting)
	var cues: MeshInstance3D = field_node.get_node_or_null("FlightCueShadows") as MeshInstance3D
	if cues != null and cues.mesh.get_surface_count() > 0:
		var material: StandardMaterial3D = cues.mesh.surface_get_material(0) as StandardMaterial3D
		material.albedo_color = Color.BLACK if lighting.has("solar") else Color.WHITE
	FieldProjectedShadows.apply_lighting(field_node, lighting)
	field_node.set_meta("lighting_snapshot", lighting.duplicate(true))
	return true


static func update_lighting(field_node: Node3D, lighting: Dictionary) -> bool:
	var prepared: Dictionary = prepare_lighting(field_node, lighting)
	return commit_lighting(field_node, prepared) if prepared.ok else false
