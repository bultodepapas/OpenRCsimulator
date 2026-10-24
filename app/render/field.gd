# L5: render only validated openrc-field v1 data. No camera, aircraft or simulation state.
extends RefCounted

const Atmosphere = preload("res://render/atmosphere.gd")
const Frames = preload("res://render/frames.gd")
const FieldLightData = preload("res://render/world/field_lights.gd")
const Treeline = preload("res://render/treeline.gd")
const FieldTreeDetail = preload("res://render/field_tree_detail.gd")
const SceneDetail = preload("res://render/scene_detail.gd")
const Ground = preload("res://render/ground.gd")
const NearGrass = preload("res://render/near_grass.gd")
const ImportedNearGrass = preload("res://scenery/imported_near_grass.gd")
const LakeWorld = preload("res://render/lake/lake_world.gd")
const Horizon = preload("res://render/horizon.gd")
const PilotStation = preload("res://render/pilot_station.gd")
const FlightlineBarrier = preload("res://render/flightline_barrier.gd")
const FieldProjectedShadows = preload("res://render/field_projected_shadows.gd")
const FlightCueShadows = preload("res://render/flight_cue_shadows.gd")
const Windsock = preload("res://render/windsock.gd")
const Scenery = preload("res://scenery/scenery.gd") # SC-02a: on by default; explicit scenery-off remains a no-op.
const PeopleGaze = preload("res://scenery/people_gaze.gd")
const LandscapeOptions = preload("res://render/landscape_upgrade/options.gd")
const DistantRidges = preload("res://render/landscape_upgrade/ridges.gd")
const Countryside = preload("res://render/landscape_upgrade/countryside.gd")
# Legacy fallback separation only; ordinary fields paint their surfaces in the rough ground pass.
const SURFACE_LIFT: Dictionary = {"rough": 0.0, "mown": 0.015, "runway": 0.03, "rotorpad": 0.015}
const GROUND_SUBDIVISIONS := 63
static var _default_light_exclusions_loaded := false
static var _default_light_exclusions_cache: Array[Dictionary] = []


static func build(field: Dictionary, lighting: Dictionary = {}, extra_grass_exclusions: Array = []) -> Node3D:
	var result: Node3D = Node3D.new()
	result.name = "Field"
	# L9c: one ground pass for contained flat rectangles; retain legacy geometry for other valid fields.
	var grass: ShaderMaterial = Ground.grass_material(lighting)
	# The default club's mowing and taxi detail is presentation only. Field surfaces and contact stay authoritative.
	grass.set_shader_parameter("club_field_detail", str(field.get("id", "")) == "default")
	if str(field.get("id", "")) == "default":
		# Reuse the bundled CC0 grass maps at walking distance; the shader fades them before the flight view.
		var grass_detail := load("res://render/grass_ground_material.gd")
		grass_detail.configure(grass)
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
	var front_azimuth := Treeline.front_azimuth_deg(field)
	var tree_half_angle := float(SceneDetail.profile().field_tree_half_angle_deg)
	for object_data: Dictionary in field.objects:
		result.add_child(Treeline.build(object_data, field.pilot, front_azimuth, tree_half_angle))
		var detail := FieldTreeDetail.build(object_data, field.pilot, front_azimuth, tree_half_angle)
		if detail.get_child_count() > 0:
			result.add_child(detail)
		else:
			detail.free()
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.type == "pilot_station":
			result.add_child(PilotStation.build(cue))
		elif cue.type == "flightline_barrier":
			result.add_child(FlightlineBarrier.build(cue))
		else:
			result.add_child(Windsock.build(cue))
	# Cache only this field's wind cues; frame updates never scan the scenery tree.
	var wind_cues: Array[Node3D] = []
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.type == "windsock":
			wind_cues.append(result.get_node(str(cue.id)) as Node3D)
	result.set_meta("wind_cues", wind_cues)
	if not field.get("flight_cues", []).is_empty():
		result.add_child(FlightCueShadows.build(field.flight_cues, lighting.has("solar")))
	var scenery_options := Scenery.options()
	var lake_resolution := LakeWorld.resolve(field, scenery_options)
	if not lake_resolution.ok:
		push_error("lake: " + "; ".join(lake_resolution.errors))
		result.set_meta("lake_error", "; ".join(lake_resolution.errors))
	var lake: Dictionary = lake_resolution.lake
	if not lake.is_empty():
		# A ground plane's optimized opaque shadow pass does not retain its shoreline discard.
		# It must not cast a solid lid over the excavated bank and bed.
		for surface: Dictionary in field.surfaces:
			if surface.type == "rough":
				(result.get_node(surface.id) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Scenery.attach(result, field, lighting, lake)
	var lake_node := LakeWorld.attach(result, field, grass, lake, lighting, bool(scenery_options.audio))
	if lake_node != null:
		materials.append_array(lake_node.get_meta("lighting_materials"))
	var scenery_node := result.get_node_or_null("Scenery")
	# SC-HUM-03: low scenery quality keeps the population static.
	if scenery_node != null and str(scenery_options.quality) != "low":
		var gaze: RefCounted = PeopleGaze.from_population(scenery_node.get_node_or_null("Population") as Node3D)
		if gaze != null:
			result.set_meta("people_gaze", gaze)
	var exclusions: Array = scenery_node.get_meta("grass_exclusions", []) if scenery_node != null else []
	exclusions = exclusions.duplicate()
	exclusions.append_array(extra_grass_exclusions)
	var field_light_exclusions: Array[Dictionary] = []
	if str(field.get("id", "")) == "default":
		field_light_exclusions = _default_field_light_exclusions()
	exclusions.append_array(field_light_exclusions)
	var near_grass: Node3D
	if scenery_node != null and field.id == "default":
		var masks := ImportedNearGrass.exclusions_for(scenery_node.get_meta("source_definition", {}), lake)
		masks.append_array(extra_grass_exclusions)
		masks.append_array(field_light_exclusions)
		near_grass = ImportedNearGrass.build(field, str(scenery_options.quality), masks)
	else:
		near_grass = NearGrass.build(field, grass, exclusions)
	result.add_child(near_grass)
	if near_grass.has_meta("lighting_material"):
		materials.append(near_grass.get_meta("lighting_material") as ShaderMaterial)
	if LandscapeOptions.enabled() and field.get("id", "") == "default":
		var ridges := DistantRidges.build(lighting)
		result.add_child(ridges)
		materials.append(ridges.get_meta("lighting_material") as ShaderMaterial)
	if LandscapeOptions.enabled() and scenery_node != null and field.get("id", "") == "default":
		var definition: Dictionary = scenery_node.get_meta("source_definition", {})
		var has_plain_layout := false
		for group: Dictionary in definition.get("groups", []):
			has_plain_layout = has_plain_layout or group.get("id") == "countryside-hamlet"
		if has_plain_layout:
			var countryside := Countryside.build(lighting)
			result.add_child(countryside)
			if countryside.has_meta("lighting_material"):
				materials.append(countryside.get_meta("lighting_material") as ShaderMaterial)
	FieldProjectedShadows.attach(result, field, lighting)
	result.set_meta("lighting_materials", materials)
	result.set_meta("lighting_snapshot", lighting.duplicate(true))
	return result


static func _default_field_light_exclusions() -> Array[Dictionary]:
	if not _default_light_exclusions_loaded:
		_default_light_exclusions_loaded = true
		var loaded: Dictionary = FieldLightData.load_from()
		if bool(loaded.get("ok", false)):
			_default_light_exclusions_cache = NearGrass.light_exclusions(loaded.lights)
		else:
			push_warning("default field lights could not be validated for grass clearance: %s" % "; ".join(loaded.get("errors", [])))
	return _default_light_exclusions_cache


## Read-only consumer of committed wind samples. No flight solver, RNG or input changes.
static func advance_wind(field_node: Node3D, time_s: float, wind_ned: Array) -> void:
	if field_node == null:
		return
	for cue: Node3D in field_node.get_meta("wind_cues", []):
		Windsock.advance(cue, time_s, wind_ned)


static func reset_wind(field_node: Node3D, time_s: float, wind_ned: Array) -> void:
	if field_node == null:
		return
	for cue: Node3D in field_node.get_meta("wind_cues", []):
		Windsock.reset(cue, time_s, wind_ned)


## SC-HUM-03/04: advance the people's head state with the simulation tick. `aircraft_ned` is the
## player's aircraft position in NED; `companions_ned` holds one NED position (or null) per companion
## slot, flown by the flight-line pilots. `player_crashed` starts the crash glance (SC-HUM-05).
## Reset restarts every head at rest (tick zero, restarts).
static func advance_people(field_node: Node3D, time_s: float, aircraft_ned: Array, reset: bool = false,
		companions_ned: Array = [], player_crashed: bool = false) -> void:
	if field_node == null or not field_node.has_meta("people_gaze"):
		return
	var gaze: RefCounted = field_node.get_meta("people_gaze")
	var target: Vector3 = Frames.ned_to_render(aircraft_ned)
	var companions: Array = []
	for position: Variant in companions_ned:
		companions.append(Frames.ned_to_render(position) if position is Array else null)
	if reset:
		gaze.reset(time_s, target, companions, player_crashed)
	else:
		gaze.update_to(time_s, target, companions, player_crashed)


## Publish the latest head angles once per rendered frame.
static func update_people(field_node: Node3D) -> void:
	if field_node == null or not field_node.has_meta("people_gaze"):
		return
	(field_node.get_meta("people_gaze") as RefCounted).apply()


## Render boundary: world wind is east/up/south; the motion model consumes north/east/down.
static func update_wind(field_node: Node3D, time_s: float, wind: Vector3) -> void:
	if field_node == null:
		return
	var wind_ned: Array = [-wind.z, wind.x, -wind.y]
	for cue: Node3D in field_node.get_meta("wind_cues", []):
		Windsock.update(cue, time_s, wind_ned)


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
