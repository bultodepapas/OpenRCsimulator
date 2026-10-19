## L7-R1: sparse decorative woodland margins from existing downloaded shrubs and grass.
## No field/scenery definitions or collision records are created or modified here.
extends RefCounted

const Hedge = preload("res://scenery/imported_hedge.gd")
const Palette = preload("res://scenery/palette.gd")
const Frames = preload("res://render/frames.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")

const DATA_PATH := "res://data/woodland_edges.json"
const GRASS_ID := "grass_common_short"
const TRIANGLE_BUDGET := 472
const SPECIES: Array[String] = ["grass_common_tall", "bush_common_flowers", "fern_1", GRASS_ID]
static var _card_material: ShaderMaterial
static var _floor_material: ShaderMaterial
static var _card_manifests: Dictionary = {}
static var _defaults: Dictionary = {}
static var _ground_heights: Dictionary = {}


static func applicable(field: Dictionary, scenery: Dictionary, lake: Dictionary = {}) -> bool:
	if _defaults.is_empty():
		var loaded := FieldLoader.load_from()
		if not loaded.ok: return false
		var scene := SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, loaded.field)
		var water := LakeLoader.load_from()
		if not scene.ok or not water.ok: return false
		_defaults = {field = loaded.field, scenery = scene.scenery, lake = water.lake}
	for key in ["id", "pilot", "runway", "surfaces", "objects"]:
		if field.get(key) != _defaults.field.get(key): return false
	if scenery.get("groups") != _defaults.scenery.get("groups"): return false
	# An omitted lake uses the same bounded default terrain as the checked placement recipe.
	return lake.is_empty() or lake == _defaults.lake


static func build(field: Dictionary, scenery: Dictionary, quality: String, lake: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "WoodlandEdges"
	root.set_meta("decorative_soft_vegetation", true)
	root.set_meta("triangles", 0)
	root.set_meta("batches", 0)
	root.set_meta("plants", [])
	if quality == "low" or not applicable(field, scenery, lake): return root
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not data is Dictionary or data.get("format") != "openrc-woodland-edges v3" \
			or not data.get("patches") is Array or data.patches.size() != 4:
		push_error("Woodland edge recipe is missing or invalid")
		return root
	var surface_table := GroundSurfaces.load_table()
	if not surface_table.ok: return root
	var surfaces := GroundSurfaces.build(surface_table.table, field)
	if not surfaces.ok: return root
	var terrain_lake: Dictionary = _defaults.lake if lake.is_empty() else lake
	var plants: Array[Dictionary] = []
	var triangles := 0
	for patch: Dictionary in data.patches:
		var shrub_records: Array[Dictionary] = []
		for path_index in patch.paths_ne_m.size():
			var points: Array[Vector2] = []
			for point: Array in patch.paths_ne_m[path_index]:
				points.append(Vector2(float(point[1]), -float(point[0])))
			var placements := Hedge.layout(points, float(patch.shrub_heights_m[path_index]), float(patch.shrub_width_m),
				int(patch.path_seeds[path_index]), quality)
			for record: Dictionary in placements:
				_fit_species(record, str(patch.shrub_species[path_index]), int(patch.path_seeds[path_index]),
					float(patch.shrub_height_m) / float(patch.shrub_heights_m[path_index]))
				shrub_records.append(record)
				var location: Vector2 = record.position
				plants.append({id = record.id, asset_id = record.species,
					north = -location.y, east = location.x, height_m = record.height_m, patch = patch.id})
		for plant: Dictionary in patch.grass_cards:
			var seed := int(plant.seed)
			if quality == "balanced" and Palette.hash01(seed, 4242) >= 0.5: continue
			shrub_records.append(_grass_record(plant))
			plants.append({id = plant.id, asset_id = GRASS_ID, north = plant.north_m,
				east = plant.east_m, height_m = plant.height_m, patch = patch.id})
		var merged := _merge_shrubs(shrub_records, surfaces.rects, terrain_lake)
		if merged != null:
			merged.name = str(patch.id) + "_Shrubs"
			root.add_child(merged)
			triangles += merged.multimesh.instance_count * Hedge.CARD_TRIANGLES
	var floor_mesh := _floor(data.patches, surfaces.rects, terrain_lake)
	root.add_child(floor_mesh)
	triangles += int(floor_mesh.get_meta("triangles", 0))
	if triangles > TRIANGLE_BUDGET:
		push_error("Woodland edges exceed their qualified source geometry budget")
		root.free()
		return Node3D.new()
	root.set_meta("triangles", triangles)
	root.set_meta("batches", root.get_child_count())
	root.set_meta("plants", plants)
	root.set_meta("source_recipe_sha256", FileAccess.get_sha256(DATA_PATH))
	return root


## Reuse the existing card geometry/material; combine the short source paths in each patch.
static func _merge_shrubs(records: Array[Dictionary], surfaces: PackedFloat64Array,
	lake: Dictionary) -> MultiMeshInstance3D:
	var count := records.size()
	if count == 0: return null
	var manifest := Hedge._manifest()
	var frame_size := Hedge._frame_size(manifest)
	var card_mesh := QuadMesh.new()
	card_mesh.size = Vector2(frame_size, frame_size)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = card_mesh
	mesh.instance_count = count
	var bounds := AABB()
	var cursor := 0
	# Read the existing CPU placement records, not GPU buffers (headless renderers return dummy transforms).
	for record in records:
		var transform: Transform3D = record.transform
		transform.origin.y += _ground_height(transform.origin.x, transform.origin.z, surfaces, lake)
		mesh.set_instance_transform(cursor, transform)
		mesh.set_instance_color(cursor, record.tint)
		mesh.set_instance_custom_data(cursor, Color(fposmod(float(record.yaw_rad), TAU) / TAU, float(SPECIES.find(record.species)), 0.0, 1.0))
		# A sphere also contains the source card after its shader rotates it toward the camera.
		var scale := transform.basis.get_scale().abs()
		var radius := mesh.mesh.get_aabb().size.length() * maxf(scale.x, maxf(scale.y, scale.z)) * 0.5
		var box := AABB(transform.origin - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
		bounds = box if cursor == 0 else bounds.merge(box)
		cursor += 1
	mesh.custom_aabb = bounds
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mesh
	instance.material_override = _material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("source_asset_ids", SPECIES.duplicate())
	return instance


## applicable() restricts builds to the immutable default world held in _defaults.
## Cache scalar terrain samples only (at most the 220 qualified plant centers),
## never nodes, meshes or caller-owned metadata. Quality subsets share these centers.
static func _ground_height(east: float, south: float, surfaces: PackedFloat64Array, lake: Dictionary) -> float:
	var key := Vector2(east, south)
	if _ground_heights.has(key): return float(_ground_heights[key])
	var ground := GroundTerrain.sample_validated(-south, east, surfaces, lake)
	var height := float(ground[0]) if ground.size() == 3 else 0.0
	if _ground_heights.size() < 220: _ground_heights[key] = height
	return height


## Fit each source image inside the previously qualified flowering-card envelope.
## Ground contact uses the source's true height within its square bake, not the quad bottom.
static func _fit_species(record: Dictionary, species: String, seed: int, envelope_scale: float) -> void:
	var manifest := _species_manifest(species)
	var source_height := float(manifest.source_height_m)
	var source_frame := float(manifest.frame_world_size_m[0])
	var original: Transform3D = record.transform
	var flower_frame := Hedge._frame_size(Hedge._manifest())
	var maximum_side := flower_frame * original.basis.get_scale().x * envelope_scale
	var side := minf(float(record.height_m) * source_frame / source_height, maximum_side)
	var actual_height := side * source_height / source_frame
	record.transform = Transform3D(Basis(Vector3.UP, float(record.yaw_rad)).scaled(Vector3.ONE * side / flower_frame),
		Vector3(original.origin.x, actual_height * 0.5, original.origin.z))
	record.height_m = actual_height
	record.species = species
	var tone := 0.91 + 0.09 * Palette.hash01(seed, 611)
	# Restrained source-color modulation; no synthetic replacement leaf texture.
	record.tint = Color(tone, tone, tone * (0.96 + 0.04 * Palette.hash01(seed, 613)), 1.0)


static func _species_manifest(species: String) -> Dictionary:
	if not _card_manifests.has(species):
		_card_manifests[species] = JSON.parse_string(FileAccess.get_file_as_string(
			"res://assets/landscape/vegetation/impostors/%s_4view.json" % species))
	return _card_manifests[species]


## The generator certifies each complete grass card against field exclusions.
## Use the same measured source frame for height fitting and the ground-contact pivot.
static func _grass_record(plant: Dictionary) -> Dictionary:
	var manifest := _species_manifest(GRASS_ID)
	var height := float(plant.height_m)
	var side := height * float(manifest.frame_world_size_m[0]) / float(manifest.source_height_m)
	var scale := side / Hedge._frame_size(Hedge._manifest())
	var yaw := float(plant.yaw_rad)
	var tone := 0.94 + 0.06 * Palette.hash01(int(plant.seed), 611)
	return {id = plant.id, species = GRASS_ID, height_m = height, yaw_rad = yaw,
		tint = Color(tone, tone, tone * 0.98, 1.0),
		transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale),
			Vector3(float(plant.east_m), height * 0.5, -float(plant.north_m)))}


static func _material() -> ShaderMaterial:
	if _card_material == null:
		_card_material = ShaderMaterial.new()
		_card_material.shader = load("res://scenery/woodland_cards.gdshader")
		_card_material.set_shader_parameter("alpha_cutoff", 0.32)
		_card_material.set_shader_parameter("atlas_frames", 4.0)
		_card_material.set_shader_parameter("impostor_atlas", Hedge._atlas())
		_card_material.set_shader_parameter("plain_atlas", load("res://assets/landscape/vegetation/impostors/grass_common_tall_4view.png"))
		_card_material.set_shader_parameter("short_grass_atlas", load("res://assets/landscape/vegetation/impostors/grass_common_short_4view.png"))
		_card_material.set_shader_parameter("fern_atlas", load("res://assets/landscape/vegetation/impostors/fern_1_4view.png"))
	return _card_material


## Small, terrain-sampled litter patches: 2x2 cells each, combined in one draw batch.
static func _floor(patches: Array, surfaces: PackedFloat64Array, lake: Dictionary) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for patch: Dictionary in patches:
		var center: Array = patch.floor_center_ne_m
		var half_size := float(patch.floor_half_size_m)
		var first := vertices.size()
		for row in 3:
			for column in 3:
				var north := float(center[0]) + float(row - 1) * half_size
				var east := float(center[1]) + float(column - 1) * half_size
				var sample := GroundTerrain.sample_validated(north, east, surfaces, lake)
				vertices.append(Frames.ned_to_render([north, east, -sample[0] - 0.02]))
				normals.append(Vector3.UP)
				uvs.append(Vector2(column, row) * 0.5)
		for row in 2:
			for column in 2:
				var a := first + row * 3 + column
				indices.append_array(PackedInt32Array([a, a + 3, a + 1, a + 1, a + 3, a + 4]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Immutable world-space material: retain its small texture across Home/Fly rebuilds.
	# Each build still owns its sampled mesh and node; no scene objects are cached.
	if _floor_material == null:
		_floor_material = ShaderMaterial.new()
		_floor_material.shader = load("res://scenery/woodland_floor.gdshader")
		_floor_material.set_shader_parameter("litter_albedo", load("res://assets/landscape/vegetation/woodland/forest_leaves_02_diffuse_1k.jpg"))
	var instance := MeshInstance3D.new()
	instance.name = "WoodlandLitter"
	instance.mesh = mesh
	instance.material_override = _floor_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("triangles", indices.size() / 3)
	return instance
