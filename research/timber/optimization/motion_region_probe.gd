extends SceneTree

## Native probe for ArrayMesh's dynamic vertex-region API. This is only an API gate;
## it never imports or changes the Turbo Lumber source assets.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_path := "res://../docs/research/timber-integration/TT-21/motion/region-api-probe.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var mesh := ArrayMesh.new()
	var initial_vertices := PackedVector3Array([
		Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = initial_vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var original_aabb := mesh.get_aabb()
	var moved_vertices := PackedVector3Array([
		Vector3(-1.0, 0.0, 2.0), Vector3(1.0, 0.0, 2.0), Vector3(0.0, 1.0, 2.0),
	])
	mesh.surface_update_vertex_region(0, 0, moved_vertices.to_byte_array())
	var after_arrays: Array = mesh.surface_get_arrays(0)
	var after_vertices: PackedVector3Array = after_arrays[Mesh.ARRAY_VERTEX]
	var after_aabb := mesh.get_aabb()
	var duplicate := mesh.duplicate(true) as ArrayMesh
	var duplicate_vertices: PackedVector3Array = duplicate.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var report := {
		"schema": "tt21-arraymesh-region-api-probe-v1",
		"engine_version": Engine.get_version_info(),
		"flags": mesh.surface_get_format(0),
		"initial_vertices": _vectors(initial_vertices),
		"requested_vertices": _vectors(moved_vertices),
		"surface_get_arrays_after_region_update": _vectors(after_vertices),
		"original_aabb": _aabb(original_aabb),
		"aabb_after_region_update": _aabb(after_aabb),
		"duplicate_vertices_after_region_update": _vectors(duplicate_vertices),
		"surface_arrays_match_updated_positions": after_vertices == moved_vertices,
		"mesh_aabb_changed": original_aabb != after_aabb,
		"duplicate_arrays_match_updated_positions": duplicate_vertices == moved_vertices,
	}
	var report_path := ProjectSettings.globalize_path(out_path)
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		printerr("Could not write region API report: ", report_path)
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t") + "\n")
	print("TT-21 ArrayMesh region API probe: arrays, AABB, duplicate remain stale; report: ", report_path)
	quit(0)


func _vectors(values: PackedVector3Array) -> Array:
	var result: Array = []
	for value: Vector3 in values:
		result.append([value.x, value.y, value.z])
	return result


func _aabb(bounds: AABB) -> Dictionary:
	return {"position": [bounds.position.x, bounds.position.y, bounds.position.z],
		"size": [bounds.size.x, bounds.size.y, bounds.size.z]}
