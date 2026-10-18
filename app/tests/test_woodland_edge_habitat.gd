## L7-R1: default woodland-edge decoration stays bounded, repeatable and collision-free.
## Run from app/: godot --headless --path . --script res://tests/test_woodland_edge_habitat.gd
extends SceneTree

const WoodlandEdges = preload("res://scenery/woodland_edge_habitat.gd")
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
	_check("high tier realizes all 1,956 source triangles", int(high.get_meta("triangles", -1)) == 1956,
		str(high.get_meta("triangles", -1)))
	_check("high tier realizes five merged batches", int(high.get_meta("batches", -1)) == 5,
		str(high.get_meta("batches", -1)))
	_check("high-tier mesh surfaces independently total 1,956 triangles",
		bool(high_geometry.valid) and int(high_geometry.triangles) == 1956, str(high_geometry))
	_check("high-tier subtree independently contains five MultiMesh batches",
		int(high_geometry.batches) == 5, str(high_geometry))
	_check("geometry counts agree with emitted metadata",
		int(high_geometry.triangles) == int(high.get_meta("triangles", -1))
		and int(high_geometry.batches) == int(high.get_meta("batches", -1)), str(high_geometry))
	_check("high tier realizes 60 plants", high_plants.size() == 60, str(high_plants.size()))
	_check("all high-tier plant IDs are unique", bool(high_index.unique), str(high_index.ids.keys()))
	_check("high-tier subtree contains no CollisionObject3D", not _has_collision_object(high))

	var high_again: Node3D = WoodlandEdges.build(field, scenery, "high", lake)
	_check("high rebuild preserves ordered plant records",
		JSON.stringify(high_plants) == JSON.stringify(high_again.get_meta("plants", [])))

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
