## Source-only hedgerows: a Bush_Common impostor atlas plus sparse imported canopy trees.
extends RefCounted

const Vegetation := preload("res://scenery/imported_vegetation.gd")
const Palette := preload("res://scenery/palette.gd")
const ImpostorShader := preload("res://assets/landscape/vegetation/impostors/bush_common_4view.gdshader")

const ATLAS_PATH := "res://assets/landscape/vegetation/impostors/bush_common_flowers_4view.png"
const MANIFEST_PATH := "res://assets/landscape/vegetation/impostors/bush_common_flowers_4view.json"
const BUSH_SOURCE_ID := "bush_common_flowers"
const BUSH_ATLAS_ASSET_ID := "bush_common_flowers_4view_impostor"
const TREE_SOURCE_ID := "common_tree_3"
const CARD_TRIANGLES := 2
const CARD_SPACING_M := 1.35
const CARD_INSTANCE_LIMITS := {"low": 64, "balanced": 128, "high": 256}
const TREE_INSTANCE_LIMITS := {"low": 2, "balanced": 3, "high": 4}
const QUALITY_RANK_LIMITS := {"low": 0.45, "balanced": 0.74, "high": 1.0}
const TREE_TRIANGLE_BUDGET := 16000
const TOTAL_TRIANGLE_BUDGET := 20000

static var _manifest_cache: Dictionary = {}
static var _atlas_texture: Texture2D
static var _shader_material: ShaderMaterial


## Build a batched hedgerow from render-XZ points. `include_trees` adds sparse CommonTree_3 meshes.
static func build(
	points: Array[Vector2],
	height: float,
	width: float,
	seed: int,
	quality: String = "balanced",
	include_trees: bool = false
) -> Node3D:
	var root := Node3D.new()
	root.name = "ImportedHedge"
	var quality_id := _quality_id(quality)
	var placements := layout(points, height, width, seed, quality_id)
	var all_cpu_placements: Array[Dictionary] = []
	var group_stats: Dictionary = {}
	var source_triangles := 0
	var batch_count := 0
	var asset_batches := 0
	var atlas_manifest := _manifest()
	if not placements.is_empty():
		var atlas_material := _impostor_material()
		var frame_size := _frame_size(atlas_manifest)
		var card_mesh := QuadMesh.new()
		card_mesh.size = Vector2(frame_size, frame_size)
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = card_mesh
		multi_mesh.use_colors = true
		multi_mesh.use_custom_data = true
		multi_mesh.instance_count = placements.size()
		for instance_index: int in range(placements.size()):
			var placement: Dictionary = placements[instance_index]
			var transform: Transform3D = placement.get("transform", Transform3D.IDENTITY)
			multi_mesh.set_instance_transform(instance_index, transform)
			multi_mesh.set_instance_color(instance_index, Color.WHITE)
			var yaw := float(placement.get("yaw_rad", 0.0))
			multi_mesh.set_instance_custom_data(instance_index, Color(fposmod(yaw, TAU) / TAU, 0.0, 0.0, 1.0))
		var cards := MultiMeshInstance3D.new()
		cards.name = "Bush_Common_Flowers_4View"
		cards.multimesh = multi_mesh
		cards.material_override = atlas_material
		cards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cards.set_meta("source_asset_id", BUSH_SOURCE_ID)
		cards.set_meta("atlas_asset_id", BUSH_ATLAS_ASSET_ID)
		root.add_child(cards)
		batch_count += 1
		asset_batches += 1
		var card_records: Array[Dictionary] = []
		for placement: Dictionary in placements:
			var record := placement.duplicate(true)
			record["type"] = "source_impostor"
			record["source_asset_id"] = BUSH_SOURCE_ID
			record["asset_id"] = BUSH_ATLAS_ASSET_ID
			record["source_triangles"] = CARD_TRIANGLES
			card_records.append(record)
		all_cpu_placements.append_array(card_records)
		var bush_triangles := placements.size() * CARD_TRIANGLES
		source_triangles += bush_triangles
		group_stats[BUSH_ATLAS_ASSET_ID] = {
			"source_asset_id": BUSH_SOURCE_ID,
			"instances": placements.size(),
			"triangles": bush_triangles,
			"draw_batches": 1,
		}

	var tree_records: Array[Dictionary] = []
	if include_trees:
		tree_records = tree_layout(points, seed, quality_id)
	if not tree_records.is_empty():
		var tree_batches: Dictionary = {}
		var tree_source_triangles := int(Vegetation.get_asset(TREE_SOURCE_ID).get("source_triangles", 0))
		var actual_tree_count := 0
		for tree_record: Dictionary in tree_records:
			var tree_transform: Transform3D = tree_record.get("transform", Transform3D.IDENTITY)
			var fitted := Vegetation.fit_to_height(TREE_SOURCE_ID, float(tree_record.get("height_m", 0.0)), tree_transform)
			var queued_id := Vegetation.queue(tree_batches, TREE_SOURCE_ID, fitted, int(tree_record.get("seed", seed)))
			if queued_id.is_empty():
				continue
			var records: Array = tree_batches[queued_id]
			actual_tree_count += 1
			var queued_record: Dictionary = records[records.size() - 1]
			var committed := tree_record.duplicate(true)
			committed["transform"] = queued_record.get("transform", fitted)
			committed["source_asset_id"] = TREE_SOURCE_ID
			committed["asset_id"] = queued_id
			committed["source_triangles"] = tree_source_triangles
			committed["type"] = "imported_tree"
			all_cpu_placements.append(committed)
		if actual_tree_count > 0:
			var tree_root := Vegetation.build(tree_batches, false)
			tree_root.name = "SparseImportedHedgeTrees"
			for child: Node in tree_root.get_children():
				if child is MultiMeshInstance3D:
					(child as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(tree_root)
			var tree_triangles := actual_tree_count * tree_source_triangles
			source_triangles += tree_triangles
			batch_count += _multimesh_count(tree_root)
			asset_batches += 1
			group_stats[TREE_SOURCE_ID] = {
				"instances": actual_tree_count,
				"triangles": tree_triangles,
				"draw_batches": _multimesh_count(tree_root),
			}

	root.set_meta("imported", true)
	root.set_meta("source_only", true)
	root.set_meta("quality", quality_id)
	root.set_meta("source_assets", [BUSH_SOURCE_ID] if not placements.is_empty() else [])
	if not tree_records.is_empty() and group_stats.has(TREE_SOURCE_ID):
		(root.get_meta("source_assets") as Array).append(TREE_SOURCE_ID)
	root.set_meta("asset_batches", asset_batches)
	root.set_meta("batches", batch_count)
	root.set_meta("bush_cards", placements.size())
	root.set_meta("trees", int(group_stats.get(TREE_SOURCE_ID, {}).get("instances", 0)))
	root.set_meta("placements", all_cpu_placements)
	root.set_meta("cpu_placements", all_cpu_placements)
	root.set_meta("groups", group_stats)
	root.set_meta("source_triangles", source_triangles)
	root.set_meta("triangles", source_triangles)
	root.set_meta("triangle_budget", TOTAL_TRIANGLE_BUDGET)
	root.set_meta("tree_triangle_budget", TREE_TRIANGLE_BUDGET)
	root.set_meta("source_geometry_sha256", str(atlas_manifest.get("source_geometry_sha256", "")))
	root.set_meta("atlas_sha256", str(atlas_manifest.get("atlas_sha256", "")))
	return root


## Convenience wrapper for existing packed scenery polylines.
static func build_packed(
	points: PackedVector2Array,
	height: float,
	width: float,
	seed: int,
	quality: String = "balanced",
	include_trees: bool = false
) -> Node3D:
	var point_array: Array[Vector2] = []
	for point: Vector2 in points:
		point_array.append(point)
	return build(point_array, height, width, seed, quality, include_trees)


## Deterministic nested quality layout for source-derived cards along the path.
static func layout(points: Array[Vector2], height: float, width: float, seed: int, quality: String = "balanced") -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if height <= 0.0 or width < 0.0 or points.size() < 2:
		return output
	var clean_points := _clean_points(points)
	if clean_points.size() < 2:
		return output
	var candidates: Array[Dictionary] = []
	var candidate_id := 0
	for segment_index: int in range(clean_points.size() - 1):
		var start: Vector2 = clean_points[segment_index]
		var finish: Vector2 = clean_points[segment_index + 1]
		var delta := finish - start
		var segment_length := delta.length()
		if segment_length <= 0.01:
			continue
		var direction := delta / segment_length
		var normal := Vector2(-direction.y, direction.x)
		var step_count := int(floor(segment_length / CARD_SPACING_M))
		for step_index: int in range(step_count):
			var along := CARD_SPACING_M * (float(step_index) + 0.5)
			var max_jitter := maxf(0.0, minf(0.18, minf(along - 0.1, segment_length - along - 0.1)))
			along += (Palette.hash01(seed, candidate_id, 41) * 2.0 - 1.0) * max_jitter
			var centre := start.lerp(finish, clampf(along / segment_length, 0.0, 1.0))
			var lateral := (Palette.hash01(seed, candidate_id, 43) - 0.5) * minf(width * 0.7, 1.0)
			var position := centre + normal * lateral
			var yaw := atan2(-direction.y, direction.x) + (Palette.hash01(seed, candidate_id, 47) - 0.5) * 0.28
			var height_scale := height * (0.82 + 0.30 * Palette.hash01(seed, candidate_id, 53))
			var rank := Palette.hash01(seed, candidate_id, 59)
			var scale := height_scale / _source_height(_manifest())
			var transform := Transform3D(
				Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale),
				Vector3(position.x, height_scale * 0.5, position.y)
			)
			candidates.append({
				"id": "hedge:%d:bush:%d" % [seed, candidate_id],
			"asset_id": BUSH_ATLAS_ASSET_ID,
				"source_asset_id": BUSH_SOURCE_ID,
				"candidate_index": candidate_id,
				"rank": rank,
				"position": position,
				"yaw_rad": yaw,
				"height_m": height_scale,
				"width_m": width,
				"source_triangles": CARD_TRIANGLES,
				"seed": seed + candidate_id,
				"transform": transform,
			})
			candidate_id += 1
	var quality_id := _quality_id(quality)
	var rank_limit := float(QUALITY_RANK_LIMITS.get(quality_id, 0.74))
	var ranked: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if float(candidate.rank) <= rank_limit:
			ranked.append(candidate)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if not is_equal_approx(float(left.rank), float(right.rank)):
			return float(left.rank) < float(right.rank)
		return int(left.candidate_index) < int(right.candidate_index)
	)
	var cap := int(CARD_INSTANCE_LIMITS.get(quality_id, CARD_INSTANCE_LIMITS.balanced))
	if ranked.size() > cap:
		ranked.resize(cap)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.candidate_index) < int(right.candidate_index)
	)
	output.assign(ranked)
	return output


## Sparse, stable CommonTree_3 positions mirroring old boundary-tree spacing.
static func tree_layout(points: Array[Vector2], seed: int, quality: String = "balanced") -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if points.size() < 2:
		return output
	var clean_points := _clean_points(points)
	if clean_points.size() < 2:
		return output
	var total_length := _path_length(clean_points)
	if total_length < 22.0:
		return output
	var candidates: Array[Dictionary] = []
	var distance := 20.0 + 25.0 * Palette.hash01(seed, 1)
	var candidate_index := 0
	while distance < total_length:
		var sample := _sample_path(clean_points, distance)
		var position: Vector2 = sample.get("position", Vector2.ZERO)
		var direction: Vector2 = sample.get("direction", Vector2.RIGHT)
		var yaw := atan2(-direction.y, direction.x) + (Palette.hash01(seed, candidate_index, 103) - 0.5) * 0.24
		var rank := Palette.hash01(seed, candidate_index, 107)
		var tree_height := 7.0 + 4.0 * Palette.hash01(seed, candidate_index, 109)
		var transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(position.x, 0.0, position.y))
		candidates.append({
			"id": "hedge:%d:tree:%d" % [seed, candidate_index],
			"asset_id": TREE_SOURCE_ID,
			"source_asset_id": TREE_SOURCE_ID,
			"candidate_index": candidate_index,
			"distance_m": distance,
			"rank": rank,
			"position": position,
			"yaw_rad": yaw,
			"height_m": tree_height,
			"seed": seed + candidate_index + 91000,
			"transform": transform,
		})
		candidate_index += 1
		distance += 35.0 + 30.0 * Palette.hash01(seed, candidate_index, 113)
	var quality_id := _quality_id(quality)
	var rank_limit := float(QUALITY_RANK_LIMITS.get(quality_id, 0.74))
	var ranked: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if float(candidate.rank) <= rank_limit:
			ranked.append(candidate)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if not is_equal_approx(float(left.rank), float(right.rank)):
			return float(left.rank) < float(right.rank)
		return int(left.candidate_index) < int(right.candidate_index)
	)
	var cap := int(TREE_INSTANCE_LIMITS.get(quality_id, TREE_INSTANCE_LIMITS.balanced))
	if ranked.size() > cap:
		ranked.resize(cap)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.candidate_index) < int(right.candidate_index)
	)
	output.assign(ranked)
	return output


static func _clean_points(points: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point: Vector2 in points:
		if result.is_empty() or (result[result.size() - 1] - point).length() > 0.01:
			result.append(point)
	return result


static func _path_length(points: Array[Vector2]) -> float:
	var total := 0.0
	for index: int in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
	return total


static func _sample_path(points: Array[Vector2], distance: float) -> Dictionary:
	var walked := 0.0
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var finish: Vector2 = points[index + 1]
		var delta := finish - start
		var length := delta.length()
		if length <= 0.01:
			continue
		if distance <= walked + length or index == points.size() - 2:
			var fraction := clampf((distance - walked) / length, 0.0, 1.0)
			return {"position": start.lerp(finish, fraction), "direction": delta / length}
		walked += length
	return {"position": points[points.size() - 1], "direction": Vector2.RIGHT}


static func _manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("Bush_Common impostor manifest is missing: %s" % MANIFEST_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_manifest_cache = parsed
	return _manifest_cache


static func _atlas() -> Texture2D:
	if _atlas_texture == null:
		_atlas_texture = load(ATLAS_PATH) as Texture2D
	return _atlas_texture


static func _impostor_material() -> ShaderMaterial:
	if _shader_material != null:
		return _shader_material
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = ImpostorShader
	_shader_material.set_shader_parameter("impostor_atlas", _atlas())
	_shader_material.set_shader_parameter("alpha_cutoff", 0.32)
	_shader_material.set_shader_parameter("atlas_frames", 4.0)
	return _shader_material


static func _source_height(manifest: Dictionary) -> float:
	var height := float(manifest.get("source_height_m", 0.0))
	return maxf(height, 0.001)


static func _frame_size(manifest: Dictionary) -> float:
	var frame: Variant = manifest.get("frame_world_size_m", [])
	if frame is Array and not frame.is_empty():
		return maxf(float(frame[0]), 0.001)
	return 2.16


static func _quality_id(quality: String) -> String:
	return quality if QUALITY_RANK_LIMITS.has(quality) else "balanced"


static func _multimesh_count(root: Node) -> int:
	var total := 1 if root is MultiMeshInstance3D else 0
	for child: Node in root.get_children():
		total += _multimesh_count(child)
	return total
