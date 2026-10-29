## SCENERY-PLAN: the scenery track's single entry point. render/field.gd calls `attach(field_node, field)` once; with the
## switch off (the default until Gate SC) it returns at once and nothing changes, byte for byte. With it on, the
## validated `openrc-scenery v1` data becomes compact 40 m cells — each ONE merged mesh with ONE vertex-colour material
## (Compatibility does no 3D batching: SC-01) — plus contact shadows, moving parts on sim_clock, flower MultiMeshes,
## the parked fleet and the synthesised ambience. Visual only: nothing here reads or writes the simulation.
## The two open pit shelters use one damage-aware PBR surface each beside the ordinary cell batches.
extends RefCounted

const Loader = preload("res://scenery/scenery_loader.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Prefabs = preload("res://scenery/prefabs.gd")
const BuildingRoofs = preload("res://scenery/building_roofs.gd")
const PowerLines = preload("res://scenery/power_lines.gd")
const Models = preload("res://scenery/models.gd")
const ParkedAircraft = preload("res://scenery/parked_aircraft.gd")
const Population = preload("res://scenery/population.gd")
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")
const VegetationPlacement = preload("res://scenery/vegetation_placement.gd")
const ImportedHedge = preload("res://scenery/imported_hedge.gd")
const SupportSurfaces = preload("res://scenery/support_surfaces.gd")
const Palette = preload("res://scenery/palette.gd")
const GroundFeatures = preload("res://scenery/ground_features.gd")
const FenceParts = preload("res://scenery/fence_parts.gd")
const DamageBatches = preload("res://scenery/damage_batches.gd")
const GrassMask = preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const Flowers = preload("res://scenery/flowers.gd")
const BotanicalHabitats = preload("res://scenery/botanical_habitats.gd")
const SceneDetail = preload("res://render/scene_detail.gd")
const AirfieldDetail = preload("res://scenery/airfield_detail.gd")
const WoodlandEdges = preload("res://scenery/woodland_edge_habitat.gd")
const Ambience = preload("res://scenery/ambience.gd")
const Birds = preload("res://scenery/birds.gd")
const Frames = preload("res://render/frames.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const GRAVEL_SHADER: Shader = preload("res://scenery/gravel.gdshader")
const MOTION_SHADER: Shader = preload("res://scenery/motion.gdshader")
const PIT_SHELTER_SHADER: Shader = preload("res://scenery/pit_shelter_roof.gdshader")

const CELL_M := 40.0
const FAR_CELL_M := 400.0
const FAR_M := 400.0
const SHADOW_RANGE_M := 300.0
const QUALITIES: Array[String] = ["low", "balanced", "high"]
# L6c-R2: club LandscapeLab bark may show this many pixels of LOD error (foliage keeps 1 px).
# Half the field trees' 8 px, because club trees are seen from 10-60 m. Maples are not world-LOD
# assets, so the protected clubhouse maple keeps its chain.
const CLUB_BARK_LOD_ERROR_PX := 4.0
static var _default_layout_geometry_ready: bool = false
static var _default_layout_geometry: PackedByteArray = PackedByteArray()


## The switch and options. CLI (after --) wins, then the environment, then the defaults. On by default (SC-02a).
static func options() -> Dictionary:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "on"
	var get := func(key: String, env: String, fallback: String) -> String:
		if args.has(key):
			return str(args[key])
		var e := OS.get_environment(env)
		return e if not e.is_empty() else fallback
	var on := func(v: String) -> bool: return ["on", "1", "true", "yes"].has(v.to_lower())
	return {
		enabled = on.call(get.call("scenery", "OPENRC_SCENERY", "on")),
		theme = get.call("scenery_theme", "OPENRC_SCENERY_THEME", ""),
		# VQ-06b: the Scene detail preset supplies the default tier; the explicit switches still win.
		quality = get.call("scenery_quality", "OPENRC_SCENERY_QUALITY", str(SceneDetail.profile().scenery_quality)),
		audio = on.call(get.call("scenery_audio", "OPENRC_SCENERY_AUDIO", "on")),
		birds = on.call(get.call("scenery_birds", "OPENRC_SCENERY_BIRDS", "on")),
		tree_wind = on.call(get.call("tree_wind", "OPENRC_TREE_WIND", "on")),
		tree_cell_size_m = float(get.call("tree_cell_size_m", "OPENRC_TREE_CELL_SIZE_M", "0")),
		file = get.call("scenery_file", "OPENRC_SCENERY_FILE", Loader.DEFAULT_PATH),
		file_explicit = args.has("scenery_file") or not OS.get_environment("OPENRC_SCENERY_FILE").is_empty(),
	}


static func enabled() -> bool:
	return options().enabled


## Use the bundled layout only for the default field's normalized spatial geometry.
## Explicit files always proceed to Loader validation, including field-id and placement checks.
static func layout_file_applies(field: Dictionary, opts: Dictionary) -> bool:
	if bool(opts.get("file_explicit", false)):
		return true
	if str(opts.get("file", Loader.DEFAULT_PATH)) != Loader.DEFAULT_PATH:
		return false
	if str(field.get("id", "")) != "default":
		return false
	var expected: PackedByteArray = _bundled_layout_geometry()
	if expected.is_empty():
		return false
	return _layout_geometry(field) == expected


static func _bundled_layout_geometry() -> PackedByteArray:
	if not _default_layout_geometry_ready:
		_default_layout_geometry_ready = true
		var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
		if loaded.get("ok", false):
			_default_layout_geometry = _layout_geometry(loaded.field)
	return _default_layout_geometry


static func _layout_geometry(field: Dictionary) -> PackedByteArray:
	var pilot_value: Variant = field.get("pilot", null)
	var surfaces_value: Variant = field.get("surfaces", null)
	var objects_value: Variant = field.get("objects", null)
	if typeof(pilot_value) != TYPE_DICTIONARY or typeof(surfaces_value) != TYPE_ARRAY \
			or typeof(objects_value) != TYPE_ARRAY:
		return PackedByteArray()
	var pilot: Dictionary = pilot_value
	var pilot_spatial: Array[float] = []
	for key: String in ["north", "east", "down"]:
		var value: Variant = pilot.get(key, null)
		if not _finite_number(value):
			return PackedByteArray()
		pilot_spatial.append(float(value))
	var surfaces: Array = []
	for surface_value: Variant in surfaces_value:
		if typeof(surface_value) != TYPE_DICTIONARY:
			return PackedByteArray()
		var surface: Dictionary = surface_value
		var surface_id: Variant = surface.get("id", null)
		var surface_type: Variant = surface.get("type", null)
		if typeof(surface_id) != TYPE_STRING or typeof(surface_type) != TYPE_STRING:
			return PackedByteArray()
		var dimensions: Array[float] = []
		for key: String in ["center_north", "center_east", "length_east_west", "width_north_south"]:
			var value: Variant = surface.get(key, null)
			if not _finite_number(value):
				return PackedByteArray()
			dimensions.append(float(value))
		surfaces.append([str(surface_id), str(surface_type), dimensions])
	surfaces.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	var objects: Array = []
	for object_value: Variant in objects_value:
		if typeof(object_value) != TYPE_DICTIONARY:
			return PackedByteArray()
		var field_object: Dictionary = object_value
		var object_id: Variant = field_object.get("id", null)
		var object_type: Variant = field_object.get("type", null)
		var positions_value: Variant = field_object.get("positions", null)
		if typeof(object_id) != TYPE_STRING or typeof(object_type) != TYPE_STRING \
				or typeof(positions_value) != TYPE_ARRAY:
			return PackedByteArray()
		var positions: Array = []
		for point_value: Variant in positions_value:
			if typeof(point_value) != TYPE_ARRAY or (point_value as Array).size() < 2:
				return PackedByteArray()
			var point: Array = point_value
			var coordinates: Array[float] = []
			for coordinate: Variant in point:
				if not _finite_number(coordinate):
					return PackedByteArray()
				coordinates.append(float(coordinate))
			positions.append(coordinates)
		positions.sort_custom(func(a: Array, b: Array) -> bool:
			if float(a[0]) == float(b[0]):
				return float(a[1]) < float(b[1])
			return float(a[0]) < float(b[0]))
		objects.append([str(object_id), str(object_type), positions])
	objects.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	return var_to_bytes([str(field.get("runway", "")), pilot_spatial, surfaces, objects])


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


## Called by render/field.gd after it built the field. No-op when the switch is off.
## Synchronous attach drains the same ordered units used by the field's staged build.
static func attach(field_node: Node3D, field: Dictionary, lighting: Dictionary = {}, lake: Dictionary = {}) -> void:
	var context := begin_attach(field, lighting, lake)
	if context == null:
		return
	while not build_finished(context):
		advance_build(context)
	field_node.add_child(take_build(context))


## Resolve the same switch, layout and validation as attach; a null job is a no-op.
static func begin_attach(field: Dictionary, lighting: Dictionary = {}, lake: Dictionary = {}) -> _SceneryBuild:
	var opts := options()
	if not opts.enabled or not layout_file_applies(field, opts):
		return null
	var loaded := Loader.load_from(str(opts.file), field)
	if not loaded.ok:
		for e: String in loaded.errors:
			push_error("scenery: " + e)
		return null
	return begin_build(field, loaded.scenery, opts, lighting, lake)


static func opaque_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.88
	m.metallic_specular = 0.3
	return m


static func pit_shelter_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PIT_SHELTER_SHADER
	material.set_shader_parameter("roof_albedo", load("res://assets/landscape/pit-shelter/corrugated_iron_02_diff_2k.jpg"))
	material.set_shader_parameter("roof_normal", load("res://assets/landscape/pit-shelter/corrugated_iron_02_nor_gl_2k.png"))
	material.set_shader_parameter("roof_arm", load("res://assets/landscape/pit-shelter/corrugated_iron_02_arm_2k.jpg"))
	material.set_shader_parameter("wood_albedo", load("res://assets/landscape/flightline/Wood049_1K-JPG_Color.jpg"))
	material.set_shader_parameter("wood_normal", load("res://assets/landscape/flightline/Wood049_1K-JPG_NormalGL.jpg"))
	material.set_shader_parameter("wood_roughness", load("res://assets/landscape/flightline/Wood049_1K-JPG_Roughness.jpg"))
	material.set_shader_parameter("slab_albedo", load("res://assets/landscape/pilot-station/Concrete034_1K-JPG_Color.jpg"))
	material.set_shader_parameter("slab_normal", load("res://assets/landscape/pilot-station/Concrete034_1K-JPG_NormalGL.jpg"))
	material.set_shader_parameter("slab_roughness", load("res://assets/landscape/pilot-station/Concrete034_1K-JPG_Roughness.jpg"))
	return material


static func shadow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = -1
	return m


## Tier filter (SC-24): low keeps landmarks and standard props; balanced drops half the ornaments (a fixed, seeded half,
## so changing quality never reshuffles); high keeps everything.
static func keep(tier: String, seed: int, quality: String) -> bool:
	if tier == "landmark" or tier == "standard" or quality == "high":
		return true
	if quality == "low":
		return false
	return Palette.hash01(seed, 4242) < 0.5


static func _cell(n: float, e: float) -> Vector2i:
	var far := Vector2(n, e).length() > FAR_M
	var size := FAR_CELL_M if far else CELL_M
	var key := Vector2i(floori(n / size), floori(e / size))
	return key * (1000 if far else 1) + (Vector2i(1, 1) * 1000000 if far else Vector2i.ZERO)


static func _kit(cells: Dictionary, key: Vector2i) -> MeshKit:
	if not cells.has(key):
		cells[key] = MeshKit.new()
	return cells[key]


static func _placement_xf(n: float, e: float, heading_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(heading_deg)), Frames.ned_to_render([n, e, 0.0]))


## A job owns its detached root until take_build(). No node refers back to the job.
enum _SceneryPhase { SETUP, GROUPS, FLEET, VEGETATION, POPULATION, BOTANICALS, DETAIL, WOODLAND,
	CELLS, SHELTER_MATERIAL, SHELTERS, SHADOWS, POPULATION_SHADOW, AMBIENCE, BIRDS, FINAL, DONE }


class _SceneryBuild:
	extends RefCounted
	var field: Dictionary
	var scenery: Dictionary
	var opts: Dictionary
	var lighting: Dictionary
	var lake: Dictionary
	var root: Node3D
	var phase: int = _SceneryPhase.SETUP
	var work_usec: int = 0
	var theme: String
	var quality: String
	var opaque: StandardMaterial3D
	var shade: StandardMaterial3D
	var sun: Vector3
	var shadow_strength: float
	var pilot: Vector2
	var cells: Dictionary
	var pit_shelter_kits: Dictionary
	var population_batches: Dictionary
	var vegetation_batches: Dictionary
	var vegetation_triangles: int = 0
	var support_surfaces: Array[Dictionary]
	var ground_cells: Dictionary
	var gravel: ShaderMaterial
	var shadow_cells: Dictionary
	var population_contact_kit: MeshKit
	var population_shadow_groups: Array[Dictionary]
	var shadow_groups: Dictionary
	var shadow_nodes: Dictionary = {}
	var population_shadow_node: MeshInstance3D
	var birds_node: Node3D
	var birds_build_usec: int = 0
	var stats: Dictionary
	var timing: Dictionary
	var motion_parent: Node3D
	var roof_parent: Node3D
	var fleet_parent: Node3D
	var fleet_batches: Dictionary
	var group_index: int = 0
	var placement_index: int = 0
	var wire_index: int = 0
	var fence_prepared: bool = false
	var fence_pieces: Array[Dictionary] = []
	var fence_index: int = 0
	var fleet_keys: Array = []
	var fleet_index: int = 0
	var cell_keys: Array = []
	var cell_index: int = 0
	var cells_prepared: bool = false
	var shelter_ids: Array = []
	var shelter_index: int = 0
	var shelter_material: ShaderMaterial
	var shadow_keys: Array = []
	var shadow_index: int = 0

	func _init(field_input: Dictionary, scenery_input: Dictionary, opts_input: Dictionary,
			lighting_input: Dictionary, lake_input: Dictionary) -> void:
		# A checkpoint can yield to unrelated callers. Pin the complete job inputs before the first unit.
		var started := Time.get_ticks_usec()
		field = field_input.duplicate(true)
		scenery = scenery_input.duplicate(true)
		opts = opts_input.duplicate(true)
		lighting = lighting_input.duplicate(true)
		lake = lake_input.duplicate(true)
		work_usec = Time.get_ticks_usec() - started

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and is_instance_valid(root):
			root.free()


static func begin_build(field: Dictionary, scenery: Dictionary, opts: Dictionary,
		lighting: Dictionary = {}, lake: Dictionary = {}) -> _SceneryBuild:
	return _SceneryBuild.new(field, scenery, opts, lighting, lake)


static func build(field: Dictionary, scenery: Dictionary, opts: Dictionary, lighting: Dictionary = {}, lake: Dictionary = {}) -> Node3D:
	var context := begin_build(field, scenery, opts, lighting, lake)
	while not build_finished(context):
		advance_build(context)
	return take_build(context)


static func build_finished(context: _SceneryBuild) -> bool:
	return context == null or context.phase == _SceneryPhase.DONE


## The owner explicitly cancels before freeing its detached field. A dropped job also frees its root.
static func cancel_build(context: _SceneryBuild) -> void:
	if context == null: return
	if is_instance_valid(context.root): context.root.free()
	context.root = null
	context.phase = _SceneryPhase.DONE


static func take_build(context: _SceneryBuild) -> Node3D:
	if context == null or context.phase != _SceneryPhase.DONE: return null
	var root := context.root
	context.root = null
	return root


static func next_build_stage(context: _SceneryBuild) -> String:
	if context == null or context.phase == _SceneryPhase.DONE: return ""
	match context.phase:
		_SceneryPhase.GROUPS: return "Building scenery placements"
		_SceneryPhase.FLEET: return "Building parked aircraft"
		_SceneryPhase.VEGETATION: return "Building scenery trees"
		_SceneryPhase.POPULATION: return "Building scenery population"
		_SceneryPhase.BOTANICALS: return "Building scenery botanicals"
		_SceneryPhase.DETAIL: return "Building scenery detail"
		_SceneryPhase.WOODLAND: return "Building woodland edges"
		_SceneryPhase.CELLS: return "Building scenery cells"
		_SceneryPhase.SHELTER_MATERIAL, _SceneryPhase.SHELTERS: return "Building scenery shelters"
		_SceneryPhase.SHADOWS, _SceneryPhase.POPULATION_SHADOW: return "Building scenery shadows"
		_: return "Building field scenery"


## One deterministic unit. The caller chooses how many units fit between its existing checkpoints.
## Timings are sums of work only, so a staged build never counts checkpoint waits.
static func advance_build(context: _SceneryBuild) -> void:
	if build_finished(context): return
	var started := Time.get_ticks_usec()
	var phase := context.phase
	var group_type := str(context.scenery.groups[context.group_index].type) if phase == _SceneryPhase.GROUPS else ""
	match phase:
		_SceneryPhase.SETUP: _setup_build(context)
		_SceneryPhase.GROUPS: _advance_group(context)
		_SceneryPhase.FLEET: _advance_fleet(context)
		_SceneryPhase.VEGETATION: _build_vegetation(context)
		_SceneryPhase.POPULATION: _build_population(context)
		_SceneryPhase.BOTANICALS: _build_botanicals(context)
		_SceneryPhase.DETAIL: _build_detail(context)
		_SceneryPhase.WOODLAND: _build_woodland(context)
		_SceneryPhase.CELLS: _advance_cell(context)
		_SceneryPhase.SHELTER_MATERIAL: _build_shelter_material(context)
		_SceneryPhase.SHELTERS: _advance_shelter(context)
		_SceneryPhase.SHADOWS: _advance_shadow(context)
		_SceneryPhase.POPULATION_SHADOW: _build_population_shadow(context)
		_SceneryPhase.AMBIENCE: _build_ambience(context)
		_SceneryPhase.BIRDS: _build_birds(context)
		_SceneryPhase.FINAL: _finish_build(context)
	var elapsed: int = Time.get_ticks_usec() - started
	var key := ""
	match phase:
		_SceneryPhase.GROUPS: key = group_type
		_SceneryPhase.VEGETATION: key = "vegetation"
		_SceneryPhase.POPULATION: key = "population"
		_SceneryPhase.BOTANICALS: key = "botanicals"
		_SceneryPhase.DETAIL: key = "airfield_detail"
		_SceneryPhase.WOODLAND: key = "woodland_edges"
		_SceneryPhase.CELLS: key = "cell_meshes"
		_SceneryPhase.SHELTER_MATERIAL: key = "shelter_material"
		_SceneryPhase.SHELTERS: key = "shelter_meshes"
	if phase == _SceneryPhase.GROUPS or not key.is_empty():
		context.timing[key] = float(context.timing.get(key, 0.0)) + float(elapsed) / 1000.0
	if phase >= _SceneryPhase.CELLS and phase <= _SceneryPhase.BIRDS:
		context.timing["meshes"] = float(context.timing.get("meshes", 0.0)) + float(elapsed) / 1000.0
	if phase == _SceneryPhase.BIRDS:
		context.timing["meshes"] += float(context.birds_build_usec) / 1000.0
	context.work_usec += Time.get_ticks_usec() - started
	if phase == _SceneryPhase.FINAL:
		context.stats.build_ms = float(context.work_usec) / 1000.0


static func _setup_build(context: _SceneryBuild) -> void:
	var field := context.field
	var scenery := context.scenery
	var opts := context.opts
	var lighting := context.lighting
	var root := Node3D.new()
	context.root = root
	root.name = "Scenery"
	root.set_meta("source_definition", scenery.duplicate(true))
	root.set_meta("grass_exclusions", GrassMask.footprints(scenery))
	var theme: String = opts.theme if Palette.THEMES.has(opts.theme) else scenery.theme
	var quality: String = opts.quality if QUALITIES.has(opts.quality) else "high"
	var opaque := opaque_material()
	var shade := shadow_material()
	var sun := Atmosphere.sun_direction(lighting)
	var shadow_strength: float = Atmosphere.shadow_strength(lighting)
	shade.albedo_color.a = shadow_strength
	# Capture birds' atmosphere, cloud and preference state alongside the shadows before any yield.
	var birds: Node3D = null
	var birds_started := Time.get_ticks_usec()
	if opts.get("birds", false):
		birds = Birds.build(lighting, str(opts.get("quality", "high")))
		if birds != null: root.add_child(birds)
	var birds_build_usec: int = Time.get_ticks_usec() - birds_started
	var pilot := Vector2(float(field.pilot.north), float(field.pilot.east))
	var cells := {}
	var pit_shelter_kits := {}
	var population_batches := {}
	var vegetation_batches := {}
	var vegetation_triangles := 0
	var support_surfaces := SupportSurfaces.build(scenery)
	var ground_cells := {}
	var gravel := ShaderMaterial.new()
	gravel.shader = GRAVEL_SHADER
	if str(field.get("id", "")) == "default":
		gravel.set_shader_parameter("use_photo_aggregate", true)
		gravel.set_shader_parameter("aggregate_albedo",
			load("res://assets/landscape/airfield_detail/river_small_rocks/river_small_rocks_Diffuse_2k.jpg"))
		gravel.set_shader_parameter("use_photo_worn", true)
		gravel.set_shader_parameter("worn_albedo",
			load("res://assets/landscape/airfield_detail/sparse_grass/sparse_grass_Diffuse_2k.jpg"))
	var shadow_cells := {}
	var population_contact_kit := MeshKit.new()
	var population_shadow_groups: Array[Dictionary] = []
	var shadow_groups: Dictionary = {}
	var stats := {instances = 0, skipped = 0, shadows = 0, motion = 0, flowers = 0, fleet = 0,
		fleet_triangles = 0, fleet_surfaces = 0, theme = theme, quality = quality}
	var motion_parent := Node3D.new()
	motion_parent.name = "Motion"
	root.add_child(motion_parent)
	var roof_parent := Node3D.new()
	roof_parent.name = "BuildingRoofs"
	root.add_child(roof_parent)
	var fleet_parent := Node3D.new()
	fleet_parent.name = "ParkedAircraft"
	fleet_parent.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(fleet_parent)
	var fleet_batches := {}
	var timing := {}
	context.theme = theme
	context.quality = quality
	context.opaque = opaque
	context.shade = shade
	context.sun = sun
	context.shadow_strength = shadow_strength
	context.pilot = pilot
	context.cells = cells
	context.pit_shelter_kits = pit_shelter_kits
	context.population_batches = population_batches
	context.vegetation_batches = vegetation_batches
	context.vegetation_triangles = vegetation_triangles
	context.support_surfaces = support_surfaces
	context.ground_cells = ground_cells
	context.gravel = gravel
	context.shadow_cells = shadow_cells
	context.population_contact_kit = population_contact_kit
	context.population_shadow_groups = population_shadow_groups
	context.shadow_groups = shadow_groups
	context.birds_node = birds
	context.birds_build_usec = birds_build_usec
	context.stats = stats
	context.motion_parent = motion_parent
	context.roof_parent = roof_parent
	context.fleet_parent = fleet_parent
	context.fleet_batches = fleet_batches
	context.timing = timing
	if scenery.groups.is_empty():
		_start_fleet(context)
	else:
		context.phase = _SceneryPhase.GROUPS


static func _start_fleet(context: _SceneryBuild) -> void:
	context.stats.fleet_batch_surfaces = 0
	context.fleet_keys = context.fleet_batches.keys()
	context.phase = _SceneryPhase.FLEET


static func _finish_group(context: _SceneryBuild) -> void:
	context.group_index += 1
	context.placement_index = 0
	context.wire_index = 0
	context.fence_prepared = false
	context.fence_pieces = []
	context.fence_index = 0
	if context.group_index >= context.scenery.groups.size(): _start_fleet(context)


static func _advance_group(context: _SceneryBuild) -> void:
	var group: Dictionary = context.scenery.groups[context.group_index]
	match group.type:
		"instances":
			if context.placement_index < group.placements.size():
				_build_instance(context, group, context.placement_index)
				context.placement_index += 1
			elif context.wire_index < group.placements.size() - 1:
				_build_wire(context, group, context.wire_index)
				context.wire_index += 1
			else: _finish_group(context)
		"fleet":
			if context.placement_index < group.placements.size():
				_build_fleet_placement(context, group, context.placement_index)
				context.placement_index += 1
			else: _finish_group(context)
		"fence":
			if not context.fence_prepared:
				var points := PackedVector2Array()
				for point: Vector2 in group.points: points.append(_xz(point))
				context.fence_pieces = FenceParts.build(points, group.style, group.seed)
				context.fence_prepared = true
			elif context.fence_index < context.fence_pieces.size():
				var piece: Dictionary = context.fence_pieces[context.fence_index]
				context.fence_index += 1
				var center: Vector3 = (piece.a + piece.b) * 0.5
				var kit := _kit(context.cells, _cell(-center.z, center.x))
				var damage_first := kit.verts.size()
				kit.beam(piece.a, piece.b, piece.width, piece.color)
				kit.tag_damage(damage_first, "fence:%s:%s" % [group.id, piece.id])
				kit.damage_ranges.back()["beam"] = piece
			else: _finish_group(context)
		"hedge":
			var pts: Array[Vector2] = []
			for point: Vector2 in group.points: pts.append(_xz(point))
			var hedge := ImportedHedge.build(pts, group.height, group.width, group.seed, context.quality)
			hedge.name = "ImportedHedge_" + str(group.id)
			context.root.add_child(hedge)
			_finish_group(context)
		"track", "patch":
			var poly := PackedVector2Array()
			for p: Vector2 in group.points: poly.append(_xz(p))
			var first: Vector2 = group.points[0]
			var key := _cell(first.x, first.y) + Vector2i(0, 7777)
			context.ground_cells[key] = true
			var kit := _kit(context.cells, key)
			if group.type == "track": GroundFeatures.track(kit, poly, group.width, group.surface, context.theme)
			else: GroundFeatures.patch(kit, poly, group.surface, context.theme, group.seed)
			_finish_group(context)
		_: _finish_group(context) # The retired procedural flowers and unknown types are no-ops.


static func _build_instance(context: _SceneryBuild, group: Dictionary, placement_index: int) -> void:
	var quality := context.quality
	var theme := context.theme
	var cells := context.cells
	var pit_shelter_kits := context.pit_shelter_kits
	var population_batches := context.population_batches
	var vegetation_batches := context.vegetation_batches
	var support_surfaces: Array[Dictionary] = context.support_surfaces
	var shadow_cells := context.shadow_cells
	var population_contact_kit := context.population_contact_kit
	var population_shadow_groups := context.population_shadow_groups
	var shadow_groups := context.shadow_groups
	var stats := context.stats
	var motion_parent := context.motion_parent
	var roof_parent := context.roof_parent
	var pilot := context.pilot
	var sun := context.sun
	var shadow_strength := context.shadow_strength
	var pl: Dictionary = group.placements[placement_index]
	var damage_id := "prop:%s:%02d" % [group.id, placement_index]
	var prefab: String = pl.prefab
	var spec: Dictionary = Prefabs.CATALOG[prefab] if Prefabs.CATALOG.has(prefab) else Models.CATALOG[prefab]
	if not keep(spec.tier, pl.seed, quality):
		stats.skipped += 1
		return
	var xf := _placement_xf(pl.north, pl.east, pl.heading)
	var kit: MeshKit = null
	if not Population.handles(prefab) and not VegetationPlacement.handles(prefab):
		if prefab == "pit_shelter":
			kit = MeshKit.new()
			pit_shelter_kits[damage_id] = kit
		else:
			kit = _kit(cells, _cell(pl.north, pl.east))
	var damage_first := kit.verts.size() if kit != null else 0
	if VegetationPlacement.handles(prefab):
		var plant := VegetationPlacement.spec(prefab, pl.seed, str(group.id))
		var plant_xf := ImportedVegetation.fit_to_height(plant.asset_id, plant.height, xf)
		var tone := 0.90 + 0.10 * Palette.hash01(pl.seed, 834)
		var tint := Color(tone, minf(1.0, tone + 0.035), tone, 1.0)
		if plant.asset_id == "maple_tree":
			tint = Color.WHITE # Preserve the supplier's leaf/bark PBR color.
		ImportedVegetation.queue(vegetation_batches, plant.asset_id, plant_xf, pl.seed, damage_id, tint)
		context.vegetation_triangles += int(plant.triangles)
	elif Population.handles(prefab):
		var foot_height := SupportSurfaces.height_at(pl.north, pl.east, support_surfaces) if prefab.begins_with("person_") else 0.0
		if prefab == "person_sitting":
			foot_height += SupportSurfaces.SEATED_OFFSET_M
		Population.queue(population_batches, prefab, xf, pl.seed, spec.size, foot_height, str(group.get("zone", "")))
	elif Prefabs.CATALOG.has(prefab):
		kit.xf = xf
		var moving: Array = Prefabs.build(prefab, kit, pl.seed, theme)
		kit.xf = Transform3D.IDENTITY
		for roof: MeshInstance3D in BuildingRoofs.create(prefab, xf, pl.seed, damage_id):
			roof_parent.add_child(roof)
		for part: Dictionary in moving:
			var moving_node := _motion_node(part, xf, pl.seed)
			moving_node.set_meta("damage_motion_id", damage_id)
			motion_parent.add_child(moving_node)
			stats.motion += 1
	else:
		var arr := Models.arrays(prefab)
		if arr.is_empty():
			return
		var paint: Variant = Palette.pick(Palette.PAINTS, pl.seed, 17) if spec.get("paint", false) else null
		kit.xf = Transform3D.IDENTITY
		kit.append_arrays(arr.pos, arr.nrm, arr.col, xf, paint)
	if kit != null:
		kit.tag_damage(damage_first, damage_id)
	stats.instances += 1
	var mode: Variant = spec.get("shadow", false)
	if mode != false and Vector2(pl.north, pl.east).distance_to(pilot) <= SHADOW_RANGE_M:
		var shadow_cell: Vector2i = _cell(pl.north, pl.east)
		var shadow_mode: String = "solid" if mode == true else str(mode)
		var shadow_xf := xf
		if prefab.begins_with("car_"):
			shadow_mode = "vehicle"
		elif prefab.begins_with("person_"):
			shadow_mode = "person"
			shadow_xf.origin.y = SupportSurfaces.height_at(pl.north, pl.east, support_surfaces)
		var shadow_size: Vector3 = spec.size
		if VegetationPlacement.handles(prefab):
			var plant := VegetationPlacement.spec(prefab, pl.seed, str(group.id))
			shadow_size = Vector3(plant.width, plant.height, plant.depth)
			if plant.asset_id == "maple_tree":
				shadow_mode = "crown"
		var shadow_source := {transform = shadow_xf, size = shadow_size, mode = shadow_mode, damage_id = damage_id}
		var population_shadow := shadow_mode == "person" or shadow_mode == "vehicle"
		if population_shadow:
			# These props live in MultiMeshes, outside the static cell mask.
			# Keep their compact contact/hull shadow in its own batch.
			population_shadow_groups.append(shadow_source)
		else:
			if not shadow_groups.has(shadow_cell):
				shadow_groups[shadow_cell] = []
			shadow_groups[shadow_cell].append(shadow_source)
		if shadow_strength > 0.0:
			var contact_kit: MeshKit = population_contact_kit if population_shadow else _kit(shadow_cells, shadow_cell)
			GroundFeatures.contact_shadow(contact_kit, shadow_xf, shadow_size, shadow_mode, sun)
			stats.shadows += 1


static func _build_wire(context: _SceneryBuild, group: Dictionary, i: int) -> void:
	var a: Dictionary = group.placements[i]
	var b: Dictionary = group.placements[i + 1]
	if a.prefab != "pylon" or b.prefab != "pylon": return
	var wire_kit := _kit(context.cells, _cell((a.north + b.north) * 0.5, (a.east + b.east) * 0.5))
	wire_kit.xf = Transform3D.IDENTITY
	var first_wire := wire_kit.verts.size()
	PowerLines.append_span(wire_kit, _placement_xf(a.north, a.east, a.heading),
		_placement_xf(b.north, b.east, b.heading))
	wire_kit.tag_damage(first_wire, "prop:%s:%02d" % [group.id, i])


static func _build_fleet_placement(context: _SceneryBuild, group: Dictionary, placement_index: int) -> void:
	var quality := context.quality
	var fleet_batches := context.fleet_batches
	var support_surfaces: Array[Dictionary] = context.support_surfaces
	var population_shadow_groups := context.population_shadow_groups
	var shadow_strength := context.shadow_strength
	var population_contact_kit := context.population_contact_kit
	var sun := context.sun
	var stats := context.stats
	var pl: Dictionary = group.placements[placement_index]
	# SC-09-R2: below High the Stik engine detail merges into one surface per batch.
	var mesh := ParkedAircraft.mesh(pl.aircraft, pl.get("configuration", "assembled"), quality)
	if mesh == null:
		return
	# Batch repeated airframes per shelter, keeping east/west culling independent.
	var batch_id := "%s_%s_%s" % [pl.aircraft, pl.get("configuration", "assembled"), "west" if pl.east < 0 else "east"]
	if not fleet_batches.has(batch_id):
		fleet_batches[batch_id] = {mesh = mesh, placements = []}
	fleet_batches[batch_id].placements.append(pl)
	var info := ParkedAircraft.info(pl.aircraft, pl.get("configuration", "assembled"))
	var size := Vector3(float(info.size[0]), float(info.size[1]), float(info.size[2])) * float(pl.get("scale", 1.0))
	var contact_xf := _placement_xf(pl.north, pl.east, pl.heading)
	contact_xf.origin.y = SupportSurfaces.height_at(pl.north, pl.east, support_surfaces)
	var mode := "aircraft_jet" if pl.aircraft == "sebart-avanti-s-a200-p100rx" else "aircraft_prop"
	if pl.get("configuration", "assembled") == "service":
		mode = "aircraft_service"
	if float(pl.get("elevation", 0.0)) >= 0.90:
		# The occupied 2.4 x 0.8 m worktops receive the shadow; foam blocks occlude it naturally.
		contact_xf.origin.y = 0.90
		mode += "_bench"
	population_shadow_groups.append({transform = contact_xf, size = size, mode = mode, damage_id = ""})
	if shadow_strength > 0.0:
		GroundFeatures.contact_shadow(population_contact_kit, contact_xf, size, mode, sun)
		stats.shadows += 1
	stats.fleet += 1
	stats.fleet_triangles += Population.triangles(mesh)
	stats.fleet_surfaces += mesh.get_surface_count()


static func _advance_fleet(context: _SceneryBuild) -> void:
	if context.fleet_index >= context.fleet_keys.size():
		context.stats.fleet_batches = context.fleet_batches.size()
		context.phase = _SceneryPhase.VEGETATION
		return
	var batch_id: String = context.fleet_keys[context.fleet_index]
	context.fleet_index += 1
	var batch: Dictionary = context.fleet_batches[batch_id]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = batch.mesh
	multimesh.instance_count = batch.placements.size()
	for index: int in batch.placements.size():
		multimesh.set_instance_transform(index, ParkedAircraft.transform_for(batch.placements[index]))
	var parked := MultiMeshInstance3D.new()
	parked.name = batch_id
	parked.multimesh = multimesh
	parked.visibility_range_end = 350.0
	parked.visibility_range_end_margin = 25.0
	parked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parked.set_meta("placements", batch.placements)
	context.fleet_parent.add_child(parked)
	context.stats.fleet_batch_surfaces += batch.mesh.get_surface_count()


static func _build_vegetation(context: _SceneryBuild) -> void:
	var vegetation := ImportedVegetation.build(context.vegetation_batches, false, {
		tree_wind = bool(context.opts.get("tree_wind", true)),
		tree_cell_size_m = context.opts.get("tree_cell_size_m", 0),
		bark_lod_error_px = CLUB_BARK_LOD_ERROR_PX,
	})
	context.root.add_child(vegetation)
	context.stats.vegetation_triangles = context.vegetation_triangles
	context.stats.vegetation_instances = context.vegetation_batches.values().reduce(func(total: int, list: Array) -> int: return total + list.size(), 0)
	context.phase = _SceneryPhase.POPULATION


static func _build_population(context: _SceneryBuild) -> void:
	var population := Population.build(context.population_batches)
	context.root.add_child(population)
	context.stats.population = population.get_meta("instances", 0)
	context.stats.population_triangles = population.get_meta("triangles", 0)
	context.stats.moving_people = population.get_meta("moving_people", 0)
	context.phase = _SceneryPhase.BOTANICALS


static func _build_botanicals(context: _SceneryBuild) -> void:
	var habitats := BotanicalHabitats.build(context.field, context.scenery, context.theme, context.quality, context.lake)
	context.root.add_child(habitats)
	context.stats.botanical_plants = habitats.get_meta("plants", []).size()
	context.stats.botanical_triangles = habitats.get_meta("triangles", 0)
	context.stats.botanical_batches = habitats.get_meta("batches", 0)
	context.phase = _SceneryPhase.DETAIL


static func _build_detail(context: _SceneryBuild) -> void:
	var detail := AirfieldDetail.build(context.field, context.scenery, context.quality)
	context.root.add_child(detail)
	context.stats.airfield_detail_instances = detail.get_meta("instances", 0)
	context.stats.airfield_detail_triangles = detail.get_meta("triangles", 0)
	context.stats.airfield_detail_batches = detail.get_meta("batches", 0)
	context.phase = _SceneryPhase.WOODLAND


static func _build_woodland(context: _SceneryBuild) -> void:
	var woodland := WoodlandEdges.build(context.field, context.scenery, context.quality, context.lake)
	context.root.add_child(woodland)
	context.stats.woodland_edge_plants = woodland.get_meta("plants", []).size()
	context.stats.woodland_edge_triangles = woodland.get_meta("triangles", 0)
	context.stats.woodland_edge_batches = woodland.get_meta("batches", 0)
	context.phase = _SceneryPhase.CELLS


static func _advance_cell(context: _SceneryBuild) -> void:
	if not context.cells_prepared:
		context.cell_keys = context.cells.keys()
		context.cell_keys.sort()
		context.cells_prepared = true
	if context.cell_index >= context.cell_keys.size():
		context.phase = _SceneryPhase.SHELTER_MATERIAL
		return
	var key: Vector2i = context.cell_keys[context.cell_index]
	context.cell_index += 1
	var kit: MeshKit = context.cells[key]
	if kit.is_empty(): return
	var mi := MeshInstance3D.new()
	mi.name = "cell_%d_%d" % [key.x, key.y]
	mi.mesh = kit.to_mesh(context.gravel if context.ground_cells.has(key) else context.opaque)
	DamageBatches.capture(mi, kit.damage_ranges)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	context.root.add_child(mi)


static func _build_shelter_material(context: _SceneryBuild) -> void:
	context.shelter_ids = context.pit_shelter_kits.keys()
	context.shelter_ids.sort()
	context.shelter_material = pit_shelter_material() if not context.shelter_ids.is_empty() else null
	context.phase = _SceneryPhase.SHELTERS


static func _advance_shelter(context: _SceneryBuild) -> void:
	if context.shelter_index >= context.shelter_ids.size():
		context.stats.pit_shelter_surfaces = context.shelter_ids.size()
		context.shadow_keys = context.shadow_groups.keys()
		context.shadow_keys.sort()
		context.phase = _SceneryPhase.SHADOWS
		return
	var shelter_id: String = context.shelter_ids[context.shelter_index]
	context.shelter_index += 1
	var kit: MeshKit = context.pit_shelter_kits[shelter_id]
	var node := MeshInstance3D.new()
	node.name = "PitShelter_" + shelter_id.replace(":", "_")
	node.mesh = kit.to_mesh(context.shelter_material)
	DamageBatches.capture(node, kit.damage_ranges)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	context.root.add_child(node)


static func _advance_shadow(context: _SceneryBuild) -> void:
	if context.shadow_index >= context.shadow_keys.size():
		context.phase = _SceneryPhase.POPULATION_SHADOW
		return
	var key: Vector2i = context.shadow_keys[context.shadow_index]
	context.shadow_index += 1
	var kit: MeshKit = context.shadow_cells[key] if context.shadow_cells.has(key) else MeshKit.new()
	var mi := MeshInstance3D.new()
	mi.name = _shadow_batch_name(key)
	mi.mesh = kit.to_mesh(context.shade)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	context.root.add_child(mi)
	context.shadow_nodes[key] = mi


static func _build_population_shadow(context: _SceneryBuild) -> void:
	if not context.population_shadow_groups.is_empty():
		var node := MeshInstance3D.new()
		node.name = "PopulationContacts"
		node.mesh = context.population_contact_kit.to_mesh(context.shade)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		context.root.add_child(node)
		context.population_shadow_node = node
	context.phase = _SceneryPhase.AMBIENCE


static func _build_ambience(context: _SceneryBuild) -> void:
	if context.opts.get("audio", false): context.root.add_child(Ambience.player())
	context.phase = _SceneryPhase.BIRDS


static func _build_birds(context: _SceneryBuild) -> void:
	# It was already built and owned by the detached root; publish its original final position.
	if is_instance_valid(context.birds_node):
		context.root.move_child(context.birds_node, context.root.get_child_count() - 1)
	context.phase = _SceneryPhase.FINAL


static func _finish_build(context: _SceneryBuild) -> void:
	var root := context.root
	context.stats.timing_ms = context.timing
	context.stats.cells = context.cell_keys.size()
	root.set_meta("stats", context.stats)
	root.set_meta("directional_shadow_material", context.shade)
	root.set_meta("directional_shadow_groups", context.shadow_groups)
	root.set_meta("directional_shadow_nodes", context.shadow_nodes)
	root.set_meta("directional_population_shadow_groups", context.population_shadow_groups)
	root.set_meta("directional_population_shadow_node", context.population_shadow_node)
	root.set_meta("directional_shadow_signature", _shadow_signature(context.sun, context.shadow_strength))
	root.set_meta("directional_shadow_strength", context.shadow_strength)
	root.set_meta("damage_state", {})
	root.set_meta("damage_lighting", context.lighting.duplicate(true))
	context.phase = _SceneryPhase.DONE


## Prepare scene-local scenery shadows from their retained source placements. No live scene resources are changed here,
## so callers can prepare all visual state before restoring physics or committing a checkpoint.
static func prepare_lighting(field_node: Node3D, lighting: Dictionary, force_geometry: bool = false) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var root: Node3D = _find_scenery(field_node)
	if root == null or not root.has_meta("directional_shadow_nodes"):
		return {ok = true, changed = false, no_op = true, prepare_ms = 0.0, batches = []}
	var material: StandardMaterial3D = root.get_meta("directional_shadow_material") as StandardMaterial3D
	var nodes: Dictionary = root.get_meta("directional_shadow_nodes")
	var groups: Dictionary = root.get_meta("directional_shadow_groups")
	var population_groups: Array = root.get_meta("directional_population_shadow_groups", [])
	var population_node: MeshInstance3D = root.get_meta("directional_population_shadow_node") as MeshInstance3D if root.has_meta("directional_population_shadow_node") else null
	var sun: Vector3 = Atmosphere.sun_direction(lighting)
	var strength: float = Atmosphere.shadow_strength(lighting)
	var signature: Dictionary = _shadow_signature(sun, strength)
	var geometry_changed: bool = force_geometry or signature != root.get_meta("directional_shadow_signature", {})
	var damage: Dictionary = root.get_meta("damage_state", {})
	var strength_changed: bool = strength != float(root.get_meta("directional_shadow_strength", 1.0))
	var prepared_batches: Array[Dictionary] = []
	var triangles: int = 0
	if geometry_changed:
		var keys: Array = nodes.keys()
		keys.sort()
		for key: Vector2i in keys:
			var kit := MeshKit.new()
			if strength > 0.0:
				for source: Dictionary in groups.get(key, []):
					if damage.get(source.get("damage_id", ""), {}).get("state", "") == "broken":
						continue
					GroundFeatures.contact_shadow(kit, source.transform, source.size, source.mode, sun)
			triangles += kit.triangle_count()
			prepared_batches.append({node = nodes[key], mesh = kit.to_mesh(material)})
		if population_node != null:
			var population_kit := MeshKit.new()
			if strength > 0.0:
				for source: Dictionary in population_groups:
					if damage.get(source.get("damage_id", ""), {}).get("state", "") == "broken":
						continue
					GroundFeatures.contact_shadow(population_kit, source.transform, source.size, source.mode, sun)
			triangles += population_kit.triangle_count()
			prepared_batches.append({node = population_node, mesh = population_kit.to_mesh(material)})
	return {
		ok = true,
		changed = geometry_changed or strength_changed,
		no_op = false,
		root = root,
		material = material,
		strength = strength,
		base_signature = root.get_meta("directional_shadow_signature", {}),
		base_strength = float(root.get_meta("directional_shadow_strength", 1.0)),
		signature = signature,
		batches = prepared_batches,
		geometry_changed = geometry_changed,
		triangles = triangles,
		prepare_ms = float(Time.get_ticks_usec() - started) / 1000.0,
		lighting = lighting.duplicate(true),
	}


## Commit a prepared scenery-lighting update. The existing shadow material and per-cell nodes stay stable; only their
## alpha and ArrayMesh resources change. Returns false only if the prepared field no longer owns that scenery root.
static func commit_lighting(field_node: Node3D, prepared: Dictionary) -> bool:
	if not bool(prepared.get("ok", false)):
		return false
	if bool(prepared.get("no_op", false)):
		return true
	var root: Node3D = prepared.get("root") as Node3D
	if not is_instance_valid(root) or _find_scenery(field_node) != root:
		return false
	if root.get_meta("directional_shadow_signature", {}) != prepared.get("base_signature", {}):
		return false
	if float(root.get_meta("directional_shadow_strength", 1.0)) != float(prepared.get("base_strength", 1.0)):
		return false
	var material: StandardMaterial3D = prepared.get("material") as StandardMaterial3D
	if not is_instance_valid(material) or root.get_meta("directional_shadow_material", null) != material:
		return false
	var replacements: Array = prepared.get("batches", [])
	for replacement: Dictionary in replacements:
		var node: MeshInstance3D = replacement.get("node") as MeshInstance3D
		var mesh: ArrayMesh = replacement.get("mesh") as ArrayMesh
		if not is_instance_valid(node) or node.get_parent() != root or not is_instance_valid(mesh):
			return false
	var tint: Color = material.albedo_color
	tint.a = float(prepared.get("strength", tint.a))
	material.albedo_color = tint
	for replacement: Dictionary in replacements:
		var node: MeshInstance3D = replacement.get("node") as MeshInstance3D
		node.mesh = replacement.get("mesh") as ArrayMesh
	root.set_meta("directional_shadow_signature", prepared.get("signature", {}))
	root.set_meta("directional_shadow_strength", float(prepared.get("strength", tint.a)))
	root.set_meta("damage_lighting", prepared.lighting)
	Birds.apply_lighting(root.get_node_or_null(Birds.NODE_NAME), prepared.lighting)
	return true


## Convenience for live time-of-day changes that do not need a separate atomic prepare/commit boundary.
static func update_lighting(field_node: Node3D, lighting: Dictionary) -> bool:
	var prepared: Dictionary = prepare_lighting(field_node, lighting)
	return commit_lighting(field_node, prepared)


## Mesh resources stay cell-batched before and after damage; reset restores the exact original resources.
static func apply_damage(field_node: Node3D, damage: Dictionary, force_shadows: bool = false) -> void:
	var root := _find_scenery(field_node)
	if root == null:
		return
	var changed := var_to_bytes(root.get_meta("damage_state", {})) != var_to_bytes(damage)
	root.set_meta("damage_state", damage.duplicate(true))
	if not changed and not force_shadows:
		return
	var vegetation: Node3D = root.get_node_or_null("ImportedVegetationBatches")
	if vegetation != null:
		var state: Dictionary = vegetation.get_meta("_imported_vegetation_state", {})
		for id: String in state.get("damage", {}):
			ImportedVegetation.set_damage_hidden(vegetation, id, damage.get(id, {}).get("state", "") == "broken")
	for child: Node in root.get_children():
		if child is MeshInstance3D and child.has_meta("damage_ranges"):
			DamageBatches.apply(child, damage)
	var roofs: Node3D = root.get_node_or_null("BuildingRoofs")
	if roofs != null:
		for roof: Node3D in roofs.get_children():
			roof.visible = damage.get(roof.get_meta("damage_motion_id"), {}).get("state", "") != "broken"
	commit_lighting(field_node, prepare_lighting(field_node, root.get_meta("damage_lighting", {}), true))

static func _find_scenery(field_node: Node3D) -> Node3D:
	if field_node == null:
		return null
	if field_node.name == "Scenery" and field_node.has_meta("directional_shadow_nodes"):
		return field_node
	return field_node.get_node_or_null("Scenery") as Node3D


static func _shadow_batch_name(cell: Vector2i) -> String:
	return "shadows_%d_%d" % [cell.x, cell.y]


static func _shadow_signature(sun: Vector3, strength: float) -> Dictionary:
	var visible: bool = strength > 0.0
	return {cast = GroundFeatures.shadow_cast(sun) if visible else Vector2.ZERO, visible = visible}


static func _xz(ne: Vector2) -> Vector2:
	var p := Frames.ned_to_render([ne.x, ne.y, 0.0])
	return Vector2(p.x, p.z)


static func _motion_node(part: Dictionary, xf: Transform3D, seed: int) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = MOTION_SHADER
	mat.set_shader_parameter("mode", int(part.get("motion_mode", 0 if part.kind == "rotor" else 1)))
	mat.set_shader_parameter("rate", float(part.get("rate", 0.0)))
	mat.set_shader_parameter("phase", float(part.get("phase", Palette.hash01(seed, 77))))
	var kit: MeshKit = part.kit
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [part.kind, seed]
	mi.mesh = kit.to_mesh(mat)
	mi.transform = xf * Transform3D(Basis.IDENTITY, part.pivot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := mi.mesh.get_aabb()
	if part.kind == "rotor": # bounds cover every rotation (VQ §10)
		var r := maxf(box.size.x, box.size.y)
		mi.custom_aabb = AABB(Vector3(-r, -r, box.position.z - 1.0), Vector3(2.0 * r, 2.0 * r, box.size.z + 2.0))
	else:
		mi.custom_aabb = box.grow(0.6)
	return mi
