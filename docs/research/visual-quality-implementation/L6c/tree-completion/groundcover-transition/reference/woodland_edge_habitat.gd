## L7-R1: sparse decorative woodland margins from existing downloaded shrubs and grass.
## No field/scenery definitions or collision records are created or modified here.
extends RefCounted

const Hedge = preload("res://scenery/imported_hedge.gd")
const Library = preload("res://scenery/imported_vegetation.gd")
const Palette = preload("res://scenery/palette.gd")
const Frames = preload("res://render/frames.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")

const DATA_PATH := "res://data/woodland_edges.json"
const GRASS_ID := "grass_common_short"
const TRIANGLE_BUDGET := 1988
const SPECIES: Array[String] = ["grass_common_tall", "bush_common_flowers", "fern_1"]
static var _card_material: ShaderMaterial
static var _floor_material: ShaderMaterial
static var _card_manifests: Dictionary = {}
static var _defaults: Dictionary = {}


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
	if not data is Dictionary or data.get("format") != "openrc-woodland-edges v2" \
			or not data.get("patches") is Array or data.patches.size() != 4:
		push_error("Woodland edge recipe is missing or invalid")
		return root
	var surface_table := GroundSurfaces.load_table()
	if not surface_table.ok: return root
	var surfaces := GroundSurfaces.build(surface_table.table, field)
	if not surfaces.ok: return root
	var terrain_lake: Dictionary = _defaults.lake if lake.is_empty() else lake
	var grass_batches: Dictionary = {}
	var plants: Array[Dictionary] = []
	var triangles := 0
	var grass_triangles := int(Library.get_asset(GRASS_ID).get("source_triangles", 0))
	if grass_triangles != 155:
		push_error("Woodland source geometry changed; requalify its budget")
		return root
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
		var merged := _merge_shrubs(shrub_records, surfaces.rects, terrain_lake)
		if merged != null:
			merged.name = str(patch.id) + "_Shrubs"
			root.add_child(merged)
			triangles += merged.multimesh.instance_count * Hedge.CARD_TRIANGLES
		for index in patch.grass_ne_m.size():
			var seed: int = int(patch.path_seeds[0]) + 100 + index
			if quality == "balanced" and Palette.hash01(seed, 4242) >= 0.5: continue
			var point: Array = patch.grass_ne_m[index]
			var north := float(point[0])
			var east := float(point[1])
			var ground := GroundTerrain.sample_validated(north, east, surfaces.rects, terrain_lake)
			if ground.size() != 3: continue
			var placement := Transform3D(Basis(Vector3.UP, TAU * Palette.hash01(seed, 32)),
				Frames.ned_to_render([north, east, -ground[0]]))
			placement = Library.fit_to_height(GRASS_ID, float(patch.grass_heights_m[index]), placement)
			if Library.queue(grass_batches, GRASS_ID, placement, seed).is_empty(): continue
			triangles += grass_triangles
			plants.append({id = "%s:grass:%d" % [patch.id, index], asset_id = GRASS_ID,
				north = north, east = east, height_m = patch.grass_heights_m[index], patch = patch.id})
	var grass := Library.build(grass_batches, false)
	for child in grass.get_children():
		if child is GeometryInstance3D: child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(grass)
	var floor_mesh := _floor(data.patches, surfaces.rects, terrain_lake)
	root.add_child(floor_mesh)
	triangles += int(floor_mesh.get_meta("triangles", 0))
	if triangles > TRIANGLE_BUDGET:
		push_error("Woodland edges exceed their qualified source geometry budget")
		root.free()
		return Node3D.new()
	root.set_meta("triangles", triangles)
	root.set_meta("batches", root.get_child_count() - 1 + grass.get_child_count())
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
		var ground := GroundTerrain.sample_validated(-transform.origin.z, transform.origin.x, surfaces, lake)
		if ground.size() == 3: transform.origin.y += ground[0]
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


## Fit each source image inside the previously qualified flowering-card envelope.
## Ground contact uses the source's true height within its square bake, not the quad bottom.
static func _fit_species(record: Dictionary, species: String, seed: int, envelope_scale: float) -> void:
	if not _card_manifests.has(species):
		_card_manifests[species] = JSON.parse_string(FileAccess.get_file_as_string(
			"res://assets/landscape/vegetation/impostors/%s_4view.json" % species))
	var manifest: Dictionary = _card_manifests[species]
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


static func _material() -> ShaderMaterial:
	if _card_material == null:
		_card_material = ShaderMaterial.new()
		_card_material.shader = load("res://scenery/woodland_cards.gdshader")
		_card_material.set_shader_parameter("alpha_cutoff", 0.32)
		_card_material.set_shader_parameter("atlas_frames", 4.0)
		_card_material.set_shader_parameter("impostor_atlas", Hedge._atlas())
		_card_material.set_shader_parameter("plain_atlas", load("res://assets/landscape/vegetation/impostors/grass_common_tall_4view.png"))
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
