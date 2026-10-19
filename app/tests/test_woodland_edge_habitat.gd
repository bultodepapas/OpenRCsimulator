## L7-R1: default woodland-edge decoration stays bounded, repeatable and collision-free.
## Run from app/: godot --headless --path . --script res://tests/test_woodland_edge_habitat.gd
extends SceneTree

const WoodlandEdges = preload("res://scenery/woodland_edge_habitat.gd")
const Hedge = preload("res://scenery/imported_hedge.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ShaderClock.register()
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(field_result.get("ok", false)), str(field_result.get("errors", [])))
	if not bool(field_result.get("ok", false)):
		_finish()
		return
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("default scenery loads", bool(scenery_result.get("ok", false)), str(scenery_result.get("errors", [])))
	if not bool(scenery_result.get("ok", false)):
		_finish()
		return
	var scenery: Dictionary = scenery_result.scenery
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("default lake loads", bool(lake_result.get("ok", false)), str(lake_result.get("errors", [])))
	if not bool(lake_result.get("ok", false)):
		_finish()
		return
	var lake: Dictionary = lake_result.lake

	var field_before := JSON.stringify(field)
	var scenery_before := JSON.stringify(scenery)
	var lake_before := JSON.stringify(lake)
	var input_hashes_before := _input_hashes()
	_check("the exact default field/scenery/lake pair is applicable",
		WoodlandEdges.applicable(field, scenery, lake))
	_check("the documented recipe hash is readable", FileAccess.get_sha256(WoodlandEdges.DATA_PATH).length() == 64)

	var high: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	var high_plants: Array = high.get_meta("plants", [])
	var high_index := _plant_index(high_plants)
	var high_geometry := _geometry_totals(high)
	_check("high tier realizes all 472 source triangles", int(high.get_meta("triangles", -1)) == 472,
		str(high.get_meta("triangles", -1)))
	_check("high tier realizes five merged batches", int(high.get_meta("batches", -1)) == 5,
		str(high.get_meta("batches", -1)))
	_check("high-tier mesh surfaces independently total 472 triangles",
		bool(high_geometry.valid) and int(high_geometry.triangles) == 472, str(high_geometry))
	_check("high-tier subtree independently contains five render batches",
		int(high_geometry.batches) == 5, str(high_geometry))
	_check("geometry counts agree with emitted metadata",
		int(high_geometry.triangles) == int(high.get_meta("triangles", -1))
		and int(high_geometry.batches) == int(high.get_meta("batches", -1)), str(high_geometry))
	_check("high tier realizes 220 plants", high_plants.size() == 220, str(high_plants.size()))
	_check("all high-tier plant IDs are unique", bool(high_index.unique), str(high_index.ids.keys()))
	_check("high-tier subtree contains no CollisionObject3D", not _has_collision_object(high))

	var mix_counts: Dictionary = {}
	for plant: Dictionary in high_plants:
		mix_counts[plant.asset_id] = int(mix_counts.get(plant.asset_id, 0)) + 1
	_check("source mix has 24 ferns, 16 tall grasses, 8 flowering shrubs and 172 short-grass cards",
		mix_counts == {fern_1 = 24, grass_common_tall = 16, bush_common_flowers = 8, grass_common_short = 172}, str(mix_counts))
	var floor_mesh: MeshInstance3D = high.get_node("WoodlandLitter")
	_check("litter uses 32 terrain triangles and casts no shadow",
		_mesh_triangle_count(floor_mesh.mesh) == 32 and floor_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var high_again: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	_check("high rebuild preserves ordered plant records",
		JSON.stringify(high_plants) == JSON.stringify(high_again.get_meta("plants", [])))
	_check("high tier emits four 55-card mixed patch batches",
		_shrub_layout_contract(high), str(_shrub_batch_counts(high)))
	_check("high tier preserves shrub render settings and shared source-atlas material",
		_shrub_render_contract(high))

	var balanced: Node3D = WoodlandEdges.build(field, scenery, "balanced", lake)
	var balanced_plants: Array = balanced.get_meta("plants", [])
	var balanced_index := _plant_index(balanced_plants)
	var subset := bool(balanced_index.unique) and balanced_plants.size() < high_plants.size()
	for plant_id: Variant in balanced_index.ids:
		if not high_index.ids.has(plant_id) or balanced_index.ids[plant_id] != high_index.ids[plant_id]:
			subset = false
	_check("balanced tier is a stable strict subset of high", subset,
		"balanced=%d high=%d" % [balanced_plants.size(), high_plants.size()])
	var balanced_again: Node3D = WoodlandEdges.build(field, scenery, "balanced", lake)
	_check("balanced rebuild preserves ordered plant records",
		JSON.stringify(balanced_plants) == JSON.stringify(balanced_again.get_meta("plants", [])))
	_check("all final shrub batches own separate MultiMesh and card meshes",
		_shrub_resources_are_independent([high, high_again, balanced, balanced_again]))

	_check("terrain sample cache stays bounded across quality rebuilds",
		WoodlandEdges._ground_heights.size() == 220, str(WoodlandEdges._ground_heights.size()))

	var low: Node3D = WoodlandEdges.build(field, scenery, "low", lake)
	_check("low tier builds zero woodland plants, triangles and batches",
		low.get_meta("plants", []).is_empty() and int(low.get_meta("triangles", -1)) == 0
		and int(low.get_meta("batches", -1)) == 0 and low.get_child_count() == 0)

	var custom_field := field.duplicate(true)
	custom_field["pilot"]["north"] = float(custom_field.pilot.north) + 1.0
	var custom_scenery := scenery.duplicate(true)
	custom_scenery["groups"] = []
	var custom_lake := lake.duplicate(true)
	custom_lake["water_level_down_m"] = float(custom_lake.water_level_down_m) + 0.01
	_check("custom field is not applicable", not WoodlandEdges.applicable(custom_field, scenery, lake))
	_check("custom scenery is not applicable", not WoodlandEdges.applicable(field, custom_scenery, lake))
	_check("custom lake is not applicable", not WoodlandEdges.applicable(field, scenery, custom_lake))
	var custom_field_root: Node3D = WoodlandEdges.build(custom_field, scenery, "high", lake)
	var custom_scenery_root: Node3D = WoodlandEdges.build(field, custom_scenery, "high", lake)
	var custom_lake_root: Node3D = WoodlandEdges.build(field, scenery, "high", custom_lake)
	_check("all custom inputs skip woodland geometry",
		custom_field_root.get_child_count() == 0 and custom_scenery_root.get_child_count() == 0
		and custom_lake_root.get_child_count() == 0
		and int(custom_field_root.get_meta("triangles", -1)) == 0
		and int(custom_scenery_root.get_meta("triangles", -1)) == 0
		and int(custom_lake_root.get_meta("triangles", -1)) == 0)

	_check("field/scenery/lake dictionaries are read-only",
		JSON.stringify(field) == field_before and JSON.stringify(scenery) == scenery_before
		and JSON.stringify(lake) == lake_before)
	_check("recipe, field, scenery and lake input hashes are unchanged",
		_input_hashes() == input_hashes_before, str(input_hashes_before) + " -> " + str(_input_hashes()))

	for node: Node in [high, high_again, balanced, balanced_again, low,
		custom_field_root, custom_scenery_root, custom_lake_root]:
		node.free()
	_finish()


func _shrub_layout_contract(root: Node3D) -> bool:
	var batches := _shrub_batches(root)
	if batches.size() != 4:
		return false
	for batch_value: Variant in batches.values():
		var batch: MultiMeshInstance3D = batch_value
		if batch.multimesh == null or batch.multimesh.instance_count != 55:
			return false
	return true


func _shrub_render_contract(root: Node3D) -> bool:
	var batches := _shrub_batches(root)
	var manifest := Hedge._manifest()
	var frame_value: Variant = manifest.get("frame_world_size_m", [])
	var frame_size := maxf(float(frame_value[0]), 0.001) if frame_value is Array and not frame_value.is_empty() else 2.16
	for batch_value: Variant in batches.values():
		var batch: MultiMeshInstance3D = batch_value
		var multimesh := batch.multimesh
		if multimesh == null or not multimesh.mesh is QuadMesh:
			return false
		var card := multimesh.mesh as QuadMesh
		if card.size != Vector2(frame_size, frame_size):
			return false
		if multimesh.transform_format != MultiMesh.TRANSFORM_3D or not multimesh.use_colors or not multimesh.use_custom_data:
			return false
		if batch.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
		if batch.get_meta("source_asset_ids", []) != WoodlandEdges.SPECIES:
			return false
		if batch.material_override != WoodlandEdges._material():
			return false
		var material := batch.material_override as ShaderMaterial
		if material == null or material.shader.resource_path != "res://scenery/woodland_cards.gdshader":
			return false
		if material.get_shader_parameter("impostor_atlas") != Hedge._atlas() \
			or material.get_shader_parameter("plain_atlas") == null or material.get_shader_parameter("fern_atlas") == null \
			or material.get_shader_parameter("short_grass_atlas") == null:
			return false
		if not is_equal_approx(float(material.get_shader_parameter("alpha_cutoff")), 0.32):
			return false
		if not is_equal_approx(float(material.get_shader_parameter("atlas_frames")), 4.0):
			return false
	return batches.size() == 4


func _shrub_resources_are_independent(roots: Array[Node3D]) -> bool:
	var multimesh_ids: Dictionary = {}
	var mesh_ids: Dictionary = {}
	var material_ids: Dictionary = {}
	for root: Node3D in roots:
		for batch_value: Variant in _shrub_batches(root).values():
			var batch: MultiMeshInstance3D = batch_value
			if batch.multimesh == null or batch.multimesh.mesh == null or batch.material_override == null:
				return false
			var multimesh_id := batch.multimesh.get_instance_id()
			var mesh_id := batch.multimesh.mesh.get_instance_id()
			var material_id := batch.material_override.get_instance_id()
			if multimesh_ids.has(multimesh_id) or mesh_ids.has(mesh_id):
				return false
			multimesh_ids[multimesh_id] = true
			mesh_ids[mesh_id] = true
			material_ids[material_id] = true
	return multimesh_ids.size() == 16 and mesh_ids.size() == 16 and material_ids.size() == 1


func _shrub_batches(root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D and str(child.name).ends_with("_Shrubs"):
			result[str(child.name)] = child
	return result


func _shrub_batch_counts(root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var batches := _shrub_batches(root)
	for batch_name: Variant in batches:
		var batch: MultiMeshInstance3D = batches[batch_name]
		result[batch_name] = -1 if batch.multimesh == null else batch.multimesh.instance_count
	return result


func _plant_index(plants: Array) -> Dictionary:
	var ids: Dictionary = {}
	var unique := true
	for plant_value: Variant in plants:
		if typeof(plant_value) != TYPE_DICTIONARY:
			unique = false
			continue
		var plant: Dictionary = plant_value
		var plant_id := str(plant.get("id", ""))
		if plant_id.is_empty() or ids.has(plant_id):
			unique = false
		else:
			ids[plant_id] = plant
	return {unique = unique, ids = ids}


func _has_collision_object(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child: Node in node.get_children():
		if _has_collision_object(child):
			return true
	return false


func _geometry_totals(node: Node) -> Dictionary:
	var result := {triangles = 0, batches = 0, valid = true}
	if node is MultiMeshInstance3D:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		if multimesh == null or multimesh.mesh == null:
			result.valid = false
		else:
			var surface_count := _mesh_triangle_count(multimesh.mesh)
			if surface_count < 0 or multimesh.instance_count <= 0:
				result.valid = false
			else:
				result.triangles += surface_count * multimesh.instance_count
				result.batches += 1
	elif node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			result.valid = false
		else:
			var surface_count := _mesh_triangle_count(mesh)
			if surface_count < 0:
				result.valid = false
			else:
				result.triangles += surface_count
				result.batches += 1
	for child: Node in node.get_children():
		var child_totals := _geometry_totals(child)
		result.triangles += int(child_totals.triangles)
		result.batches += int(child_totals.batches)
		result.valid = bool(result.valid) and bool(child_totals.valid)
	return result


func _mesh_triangle_count(mesh: Mesh) -> int:
	var triangles := 0
	for surface_index in mesh.get_surface_count():
		if mesh is ArrayMesh:
			if (mesh as ArrayMesh).surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				return -1
		elif not mesh is QuadMesh:
			return -1
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			return -1
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and not index_data.is_empty():
			if index_data.size() % 3 != 0:
				return -1
			triangles += int(index_data.size() / 3)
		else:
			var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not vertex_data is PackedVector3Array or vertex_data.is_empty() or vertex_data.size() % 3 != 0:
				return -1
			triangles += int(vertex_data.size() / 3)
	return triangles


func _input_hashes() -> Dictionary:
	return {
		"field": FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
		"scenery": FileAccess.get_sha256(SceneryLoader.DEFAULT_PATH),
		"lake": FileAccess.get_sha256(LakeLoader.DEFAULT_PATH),
		"recipe": FileAccess.get_sha256(WoodlandEdges.DATA_PATH),
	}


func _finish() -> void:
	print("woodland-edge habitat: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
