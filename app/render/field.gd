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
const ShadowFieldPolicy = preload("res://render/shadow_field_policy.gd")
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
## A checkpoint draws a frame, so batch deterministic scenery units into bounded CPU chunks.
## One indivisible unit may exceed this budget; large subsystems are isolated by stage.
const SCENERY_BUILD_BUDGET_USEC := 16000
static var _default_light_exclusions_loaded := false
static var _default_light_exclusions_cache: Array[Dictionary] = []


enum _BuildPhase {
	GROUND_SETUP,
	GROUND_SURFACES,
	TREES,
	FLIGHT_CUES,
	SCENERY_RESOLVE,
	SCENERY_ATTACH,
	LAKE_ATTACH,
	POPULATION,
	NEAR_GRASS,
	DISTANT_RIDGES,
	COUNTRYSIDE,
	PROJECTED_SHADOWS,
	FIELD_READY,
	DONE,
}


class _BuildContext:
	extends RefCounted
	var field: Dictionary
	var lighting: Dictionary
	var extra_grass_exclusions: Array
	var result: Node3D
	var phase: int = 0
	var work_usec: int = 0
	var grass: ShaderMaterial
	var materials: Array[ShaderMaterial] = []
	var surface_index: int = 0
	var object_index: int = 0
	var cue_index: int = 0
	var trees_initialized: bool = false
	var front_azimuth: float = 0.0
	var tree_half_angle: float = 0.0
	var flight_cues: Array
	var scenery_options: Dictionary
	var scenery_build: Variant
	var scenery_started: bool = false
	var lake: Dictionary
	var scenery_node: Node3D
	var exclusions: Array
	var field_light_exclusions: Array[Dictionary] = []
	var build_ridges: bool = false
	var build_countryside: bool = false

	func _init(field_input: Dictionary, lighting_input: Dictionary, extra_input: Array) -> void:
		var started := Time.get_ticks_usec()
		field = field_input.duplicate(true)
		lighting = lighting_input.duplicate(true)
		extra_grass_exclusions = extra_input.duplicate(true)
		flight_cues = field.get("flight_cues", [])
		result = Node3D.new()
		result.name = "Field"
		work_usec = Time.get_ticks_usec() - started


## Synchronous builder: drain the exact same ordered steps as build_staged without yielding or workers.
static func build(field: Dictionary, lighting: Dictionary = {}, extra_grass_exclusions: Array = []) -> Node3D:
	var context := _BuildContext.new(field, lighting, extra_grass_exclusions)
	while context.phase != _BuildPhase.DONE:
		var started_usec: int = Time.get_ticks_usec()
		var stage: String = _next_build_stage(context)
		if stage.is_empty():
			break
		_advance_build(context)
		context.work_usec += Time.get_ticks_usec() - started_usec
	context.result.set_meta("field_build_ms", float(context.work_usec) / 1000.0)
	return context.result


## Staged builder: each callback labels and gates the next chunk. Returning false frees the detached partial field.
static func build_staged(field: Dictionary, lighting: Dictionary = {}, extra_grass_exclusions: Array = [],
		checkpoint: Callable = Callable()) -> Node3D:
	var context := _BuildContext.new(field, lighting, extra_grass_exclusions)
	while context.phase != _BuildPhase.DONE:
		var selection_started_usec: int = Time.get_ticks_usec()
		var stage: String = _next_build_stage(context)
		var selection_usec: int = Time.get_ticks_usec() - selection_started_usec
		if stage.is_empty():
			break
		if checkpoint.is_valid():
			var keep_going: Variant = await checkpoint.call(stage)
			if not (keep_going is bool and keep_going):
				if context.scenery_build != null:
					Scenery.cancel_build(context.scenery_build)
					context.scenery_build = null
				var partial: Node3D = context.result
				context.result = null
				partial.free()
				return null
		var work_started_usec: int = Time.get_ticks_usec()
		_advance_build(context)
		context.work_usec += selection_usec + Time.get_ticks_usec() - work_started_usec
	context.result.set_meta("field_build_ms", float(context.work_usec) / 1000.0)
	return context.result


## Resolves transitions that have no work so the callback labels the next chunk before it starts.
static func _next_build_stage(context: _BuildContext) -> String:
	while context.phase != _BuildPhase.DONE:
		match context.phase:
			_BuildPhase.GROUND_SETUP:
				return "Field ground"
			_BuildPhase.GROUND_SURFACES:
				while context.surface_index < context.field.surfaces.size():
					var surface: Dictionary = context.field.surfaces[context.surface_index]
					if context.result.get_meta("surfaces_consolidated", false) and surface.type != "rough":
						context.surface_index += 1
						continue
					return "Field ground"
				context.phase = _BuildPhase.TREES
				continue
			_BuildPhase.TREES:
				if not context.trees_initialized or context.object_index < context.field.objects.size():
					return "Field trees"
				context.phase = _BuildPhase.FLIGHT_CUES
				continue
			_BuildPhase.FLIGHT_CUES:
				if context.cue_index < context.flight_cues.size():
					return "Flight cues"
				return "Flight cue shadows"
			_BuildPhase.SCENERY_RESOLVE:
				return "Resolving field scenery"
			_BuildPhase.SCENERY_ATTACH:
				return "Building field scenery"
			_BuildPhase.LAKE_ATTACH:
				return "Building field lake"
			_BuildPhase.POPULATION:
				return "Preparing field vegetation"
			_BuildPhase.NEAR_GRASS:
				return "Near grass"
			_BuildPhase.DISTANT_RIDGES:
				context.build_ridges = LandscapeOptions.enabled() and context.field.get("id", "") == "default"
				if context.build_ridges:
					return "Distant ridges"
				context.phase = _BuildPhase.COUNTRYSIDE
				continue
			_BuildPhase.COUNTRYSIDE:
				context.build_countryside = _countryside_layout_is_present(context)
				if context.build_countryside:
					return "Countryside"
				context.phase = _BuildPhase.PROJECTED_SHADOWS
				continue
			_BuildPhase.PROJECTED_SHADOWS:
				return "Projected shadows"
			_BuildPhase.FIELD_READY:
				return "Attaching landscape"
	return ""


## Executes exactly one chunk selected by _next_build_stage; no await or worker runs here.
static func _advance_build(context: _BuildContext) -> void:
	match context.phase:
		_BuildPhase.GROUND_SETUP:
			_build_ground_setup(context)
			context.phase = _BuildPhase.GROUND_SURFACES
		_BuildPhase.GROUND_SURFACES:
			var surface: Dictionary = context.field.surfaces[context.surface_index]
			context.surface_index += 1
			_build_ground_surface(context, surface)
		_BuildPhase.TREES:
			if not context.trees_initialized:
				context.front_azimuth = Treeline.front_azimuth_deg(context.field)
				context.tree_half_angle = float(SceneDetail.profile().field_tree_half_angle_deg)
				context.trees_initialized = true
			if context.object_index < context.field.objects.size():
				var object_data: Dictionary = context.field.objects[context.object_index]
				context.object_index += 1
				context.result.add_child(Treeline.build(object_data, context.field.pilot,
					context.front_azimuth, context.tree_half_angle))
				var detail := FieldTreeDetail.build(object_data, context.field.pilot,
					context.front_azimuth, context.tree_half_angle)
				if detail.get_child_count() > 0:
					context.result.add_child(detail)
				else:
					detail.free()
			else:
				context.phase = _BuildPhase.FLIGHT_CUES
		_BuildPhase.FLIGHT_CUES:
			if context.cue_index < context.flight_cues.size():
				var cue: Dictionary = context.flight_cues[context.cue_index]
				context.cue_index += 1
				if cue.type == "pilot_station":
					context.result.add_child(PilotStation.build(cue))
				elif cue.type == "flightline_barrier":
					context.result.add_child(FlightlineBarrier.build(cue))
				else:
					context.result.add_child(Windsock.build(cue))
			else:
				# Cache only this field's wind cues; frame updates never scan the scenery tree.
				var wind_cues: Array[Node3D] = []
				for cue: Dictionary in context.flight_cues:
					if cue.type == "windsock":
						wind_cues.append(context.result.get_node(str(cue.id)) as Node3D)
				context.result.set_meta("wind_cues", wind_cues)
				if not context.flight_cues.is_empty():
					context.result.add_child(FlightCueShadows.build(context.flight_cues, context.lighting.has("solar")))
				context.phase = _BuildPhase.SCENERY_RESOLVE
		_BuildPhase.SCENERY_RESOLVE:
			context.scenery_options = Scenery.options()
			var lake_resolution: Dictionary = LakeWorld.resolve(context.field, context.scenery_options)
			if not lake_resolution.ok:
				push_error("lake: " + "; ".join(lake_resolution.errors))
				context.result.set_meta("lake_error", "; ".join(lake_resolution.errors))
			context.lake = lake_resolution.lake
			if not context.lake.is_empty():
				# A ground plane's optimized opaque shadow pass does not retain its shoreline discard.
				# It must not cast a solid lid over the excavated bank and bed.
				for surface: Dictionary in context.field.surfaces:
					if surface.type == "rough":
						(context.result.get_node(surface.id) as MeshInstance3D).cast_shadow = \
							GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			context.phase = _BuildPhase.SCENERY_ATTACH
		_BuildPhase.SCENERY_ATTACH:
			var started := Time.get_ticks_usec()
			if not context.scenery_started:
				context.scenery_started = true
				context.scenery_build = Scenery.begin_attach(context.field, context.lighting, context.lake)
				if context.scenery_build == null:
					context.phase = _BuildPhase.LAKE_ATTACH
					return
				if Time.get_ticks_usec() - started >= SCENERY_BUILD_BUDGET_USEC:
					return
			var stage: String = Scenery.next_build_stage(context.scenery_build)
			while not Scenery.build_finished(context.scenery_build):
				Scenery.advance_build(context.scenery_build)
				if Time.get_ticks_usec() - started >= SCENERY_BUILD_BUDGET_USEC \
						or Scenery.next_build_stage(context.scenery_build) != stage:
					break
			if Scenery.build_finished(context.scenery_build):
				context.result.add_child(Scenery.take_build(context.scenery_build))
				context.scenery_build = null
				context.phase = _BuildPhase.LAKE_ATTACH
		_BuildPhase.LAKE_ATTACH:
			var lake_node := LakeWorld.attach(context.result, context.field, context.grass, context.lake,
				context.lighting, bool(context.scenery_options.audio))
			if lake_node != null:
				context.materials.append_array(lake_node.get_meta("lighting_materials"))
			context.phase = _BuildPhase.POPULATION
		_BuildPhase.POPULATION:
			context.scenery_node = context.result.get_node_or_null("Scenery") as Node3D
			# SC-HUM-03: low scenery quality keeps the population static.
			if context.scenery_node != null and str(context.scenery_options.quality) != "low":
				var gaze: RefCounted = PeopleGaze.from_population(
					context.scenery_node.get_node_or_null("Population") as Node3D)
				if gaze != null:
					context.result.set_meta("people_gaze", gaze)
			context.exclusions = context.scenery_node.get_meta("grass_exclusions", []) \
				if context.scenery_node != null else []
			context.exclusions = context.exclusions.duplicate()
			context.exclusions.append_array(context.extra_grass_exclusions)
			if str(context.field.get("id", "")) == "default":
				context.field_light_exclusions = _default_field_light_exclusions()
			context.exclusions.append_array(context.field_light_exclusions)
			context.phase = _BuildPhase.NEAR_GRASS
		_BuildPhase.NEAR_GRASS:
			var near_grass: Node3D
			if context.scenery_node != null and context.field.id == "default":
				var masks := ImportedNearGrass.exclusions_for(
					context.scenery_node.get_meta("source_definition", {}), context.lake)
				masks.append_array(context.extra_grass_exclusions)
				masks.append_array(context.field_light_exclusions)
				near_grass = ImportedNearGrass.build(context.field,
					str(context.scenery_options.quality), masks)
			else:
				near_grass = NearGrass.build(context.field, context.grass, context.exclusions)
			context.result.add_child(near_grass)
			if near_grass.has_meta("lighting_material"):
				context.materials.append(near_grass.get_meta("lighting_material") as ShaderMaterial)
			context.phase = _BuildPhase.DISTANT_RIDGES
		_BuildPhase.DISTANT_RIDGES:
			if context.build_ridges:
				var ridges := DistantRidges.build(context.lighting)
				context.result.add_child(ridges)
				context.materials.append(ridges.get_meta("lighting_material") as ShaderMaterial)
			context.phase = _BuildPhase.COUNTRYSIDE
		_BuildPhase.COUNTRYSIDE:
			if context.build_countryside:
				var countryside := Countryside.build(context.lighting)
				context.result.add_child(countryside)
				if countryside.has_meta("lighting_material"):
					context.materials.append(countryside.get_meta("lighting_material") as ShaderMaterial)
			context.phase = _BuildPhase.PROJECTED_SHADOWS
		_BuildPhase.PROJECTED_SHADOWS:
			FieldProjectedShadows.attach(context.result, context.field, context.lighting)
			ShadowFieldPolicy.attach(context.result, context.field)
			context.result.set_meta("lighting_materials", context.materials)
			context.result.set_meta("lighting_snapshot", context.lighting.duplicate(true))
			context.phase = _BuildPhase.FIELD_READY
		_BuildPhase.FIELD_READY:
			context.phase = _BuildPhase.DONE


static func _countryside_layout_is_present(context: _BuildContext) -> bool:
	if not LandscapeOptions.enabled() or context.scenery_node == null \
			or context.field.get("id", "") != "default":
		return false
	var definition: Dictionary = context.scenery_node.get_meta("source_definition", {})
	for group: Dictionary in definition.get("groups", []):
		if group.get("id") == "countryside-hamlet":
			return true
	return false


static func _build_ground_setup(context: _BuildContext) -> void:
	# L9c: one ground pass for contained flat rectangles; retain legacy geometry for other valid fields.
	context.grass = Ground.grass_material(context.lighting)
	# The default club's mowing and taxi detail is presentation only. Field surfaces and contact stay authoritative.
	context.grass.set_shader_parameter("club_field_detail", str(context.field.get("id", "")) == "default")
	if str(context.field.get("id", "")) == "default":
		# Reuse the bundled CC0 grass maps at walking distance; the shader fades them before the flight view.
		var grass_detail := load("res://render/grass_ground_material.gd")
		grass_detail.configure(context.grass)
	context.materials.append(context.grass)
	var station := Frames.ned_to_render([context.field.pilot.north, context.field.pilot.east, 0.0])
	context.grass.set_shader_parameter("pilot_xz", Vector2(station.x, station.z)) # Phase 2: the macro tone is pinned here
	var consolidated: bool = Ground.configure_surfaces(context.grass, context.field.surfaces)
	context.result.set_meta("surfaces_consolidated", consolidated)


static func _build_ground_surface(context: _BuildContext, surface: Dictionary) -> void:
	if context.result.get_meta("surfaces_consolidated", false) and surface.type != "rough":
		return
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = surface.id
	mesh_instance.layers |= Ground.MARK_RECEIVER_LAYER
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
	mesh_instance.position = Frames.ned_to_render([surface.center_north, surface.center_east,
		-float(SURFACE_LIFT[surface.type])])
	var half := Vector2(surface.length_east_west, surface.width_north_south) / 2.0
	mesh_instance.material_override = context.grass if surface.type == "rough" else Ground.surface_material(
		context.grass, surface.type, Vector2(mesh_instance.position.x, mesh_instance.position.z), half)
	if not context.materials.has(mesh_instance.material_override):
		context.materials.append(mesh_instance.material_override as ShaderMaterial)
	context.result.add_child(mesh_instance)


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
static func advance_wind(field_node: Node3D, time_s: float, wind_ned: Array, sampler: Callable = Callable()) -> void:
	if field_node == null:
		return
	field_node.set_meta("wind_world_sampler", sampler)
	for cue: Node3D in field_node.get_meta("wind_cues", []):
		var local: Array = _cue_wind(field_node, cue, time_s, wind_ned)
		if local.size() == 3:
			Windsock.advance(cue, time_s, local)


static func reset_wind(field_node: Node3D, time_s: float, wind_ned: Array, sampler: Callable = Callable()) -> void:
	if field_node == null:
		return
	field_node.set_meta("wind_world_sampler", sampler)
	for cue: Node3D in field_node.get_meta("wind_cues", []):
		var local: Array = _cue_wind(field_node, cue, time_s, wind_ned)
		if local.size() == 3:
			Windsock.reset(cue, time_s, local)


## Fixed observation point at the pole head; cloth motion does not move the physical sample.
## Conversion happens only here at the render boundary. Invalid observations leave the cue unchanged.
static func _cue_wind(field_node: Node3D, cue: Node3D, time_s: float, fallback: Array) -> Array:
	var sampler: Variant = field_node.get_meta("wind_world_sampler", Callable())
	if not sampler is Callable or not sampler.is_valid():
		return fallback
	var dimensions: Dictionary = cue.get_meta("windsock_dimensions", {})
	var height: float = float(dimensions.get("height_m", 0.0))
	var position: Vector3 = cue.global_transform * Vector3(0.0, height, 0.0)
	var result: Variant = sampler.call(PackedFloat64Array([-position.z, position.x, -position.y]), time_s)
	if not result is PackedFloat64Array or result.size() != 3:
		return []
	for value: float in result:
		if not is_finite(value):
			return []
	return Array(result)


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
		var local: Array = _cue_wind(field_node, cue, time_s, wind_ned)
		if local.size() == 3:
			Windsock.update(cue, time_s, local)


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
	var policy: Node = field_node.get_meta("shadow_field_policy") if field_node.has_meta("shadow_field_policy") else null
	if is_instance_valid(policy):
		policy.apply_lighting(lighting)
	else:
		FieldProjectedShadows.apply_lighting(field_node, lighting)
	field_node.set_meta("lighting_snapshot", lighting.duplicate(true))
	return true


static func update_lighting(field_node: Node3D, lighting: Dictionary) -> bool:
	var prepared: Dictionary = prepare_lighting(field_node, lighting)
	return commit_lighting(field_node, prepared) if prepared.ok else false
