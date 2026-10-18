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
const TRIANGLE_BUDGET := 1956
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
	if not data is Dictionary or data.get("format") != "openrc-woodland-edges v1" \
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
		var pieces: Array[MultiMeshInstance3D] = []
		var shrub_records: Array[Dictionary] = []
		var holders: Array[Node3D] = []
		for path_index in patch.paths_ne_m.size():
			var points: Array[Vector2] = []
			for point: Array in patch.paths_ne_m[path_index]:
				points.append(Vector2(float(point[1]), -float(point[0])))
			var hedge := Hedge.build(points, float(patch.shrub_height_m), float(patch.shrub_width_m),
				int(patch.path_seeds[path_index]), quality, false)
			holders.append(hedge)
			for child in hedge.get_children():
				if child is MultiMeshInstance3D: pieces.append(child)
			for record: Dictionary in hedge.get_meta("cpu_placements", []):
				shrub_records.append(record)
				var location: Vector2 = record.position
				plants.append({id = record.id, asset_id = Hedge.BUSH_SOURCE_ID,
					north = -location.y, east = location.x, height_m = record.height_m, patch = patch.id})
		var merged := _merge_shrubs(pieces, shrub_records, surfaces.rects, terrain_lake)
		for holder in holders: holder.free()
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
			placement = Library.fit_to_height(GRASS_ID, float(patch.grass_height_m), placement)
			if Library.queue(grass_batches, GRASS_ID, placement, seed).is_empty(): continue
			triangles += grass_triangles
			plants.append({id = "%s:grass:%d" % [patch.id, index], asset_id = GRASS_ID,
				north = north, east = east, height_m = patch.grass_height_m, patch = patch.id})
	var grass := Library.build(grass_batches, false)
	for child in grass.get_children():
		if child is GeometryInstance3D: child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(grass)
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
static func _merge_shrubs(pieces: Array[MultiMeshInstance3D], records: Array[Dictionary], surfaces: PackedFloat64Array,
	lake: Dictionary) -> MultiMeshInstance3D:
	if pieces.is_empty(): return null
	var count := records.size()
	if count == 0: return null
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = pieces[0].multimesh.mesh
	mesh.instance_count = count
	var bounds := AABB()
	var cursor := 0
	# Read the existing CPU placement records, not GPU buffers (headless renderers return dummy transforms).
	for record in records:
		var transform: Transform3D = record.transform
		var ground := GroundTerrain.sample_validated(-transform.origin.z, transform.origin.x, surfaces, lake)
		if ground.size() == 3: transform.origin.y += ground[0]
		mesh.set_instance_transform(cursor, transform)
		mesh.set_instance_color(cursor, Color.WHITE)
		mesh.set_instance_custom_data(cursor, Color(fposmod(float(record.yaw_rad), TAU) / TAU, 0.0, 0.0, 1.0))
		# A sphere also contains the source card after its shader rotates it toward the camera.
		var scale := transform.basis.get_scale().abs()
		var radius := mesh.mesh.get_aabb().size.length() * maxf(scale.x, maxf(scale.y, scale.z)) * 0.5
		var box := AABB(transform.origin - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
		bounds = box if cursor == 0 else bounds.merge(box)
		cursor += 1
	mesh.custom_aabb = bounds
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mesh
	instance.material_override = pieces[0].material_override
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("source_asset_id", Hedge.BUSH_SOURCE_ID)
	return instance
