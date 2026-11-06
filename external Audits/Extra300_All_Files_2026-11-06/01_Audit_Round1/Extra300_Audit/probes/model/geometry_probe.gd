extends SceneTree

const Extra := preload("res://aircraft/extra_300s_model.gd")
const ExtraIndexed := preload("res://aircraft/extra_300s_model_indexed.gd")
const PaintAdapter := preload("res://aircraft/procedural_skin.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("CHECK_FAILED ", label)

func meshes(root_node: Node3D) -> Dictionary:
	var found := {}
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		found[str(root_node.get_path_to(node))] = node
	return found

func indexes(arrays: Array) -> PackedInt32Array:
	if arrays[Mesh.ARRAY_INDEX] != null:
		return arrays[Mesh.ARRAY_INDEX]
	var result := PackedInt32Array()
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	result.resize(count)
	for i in count:
		result[i] = i
	return result

func compare_arrays(before: Array, after: Array) -> Dictionary:
	var left := indexes(before)
	var right := indexes(after)
	var unequal := {}
	if left.size() != right.size():
		return {"triangle_corner_count": [left.size(), right.size()]}
	var left_v: int = before[Mesh.ARRAY_VERTEX].size()
	var right_v: int = after[Mesh.ARRAY_VERTEX].size()
	for slot in range(Mesh.ARRAY_INDEX):
		if before[slot] == null and after[slot] == null:
			continue
		if before[slot] == null or after[slot] == null:
			unequal[str(slot)] = "missing"
			continue
		var na: int = before[slot].size()
		var nb: int = after[slot].size()
		if na % left_v != 0 or nb % right_v != 0 or na / left_v != nb / right_v:
			unequal[str(slot)] = [na, left_v, nb, right_v]
			continue
		var stride: int = na / left_v
		var count := 0
		var max_error := 0.0
		for i in left.size():
			for k in stride:
				var a: Variant = before[slot][left[i] * stride + k]
				var b: Variant = after[slot][right[i] * stride + k]
				if a != b:
					count += 1
					if a is Vector3 or a is Vector2:
						max_error = maxf(max_error, a.distance_to(b))
					elif a is float or a is int:
						max_error = maxf(max_error, absf(float(a) - float(b)))
		if count > 0: unequal[str(slot)] = {"differences": count, "max_abs_or_distance": max_error}
	return unequal

func serialized_bytes(mesh: Mesh) -> Dictionary:
	var result := {"vertex_data": 0, "attribute_data": 0, "skin_data": 0, "index_data": 0}
	if not mesh is ArrayMesh: return result
	for surface: Dictionary in mesh.get("_surfaces"):
		for key in result:
			if surface.has(key): result[key] += surface[key].size()
	return result

func inventory(root_node: Node3D) -> Dictionary:
	var seen := {}
	var summary := {"instances": 0, "unique_meshes": 0, "triangles_instance": 0, "vertices_unique": 0,
		"indices_unique": 0, "array_meshes": 0, "vertex_data": 0, "attribute_data": 0, "skin_data": 0, "index_data": 0,
		"shader_materials": 0, "shaders": 0}
	var materials := {}
	var shaders := {}
	for node: MeshInstance3D in meshes(root_node).values():
		var mesh: Mesh = node.mesh
		if mesh == null: continue
		summary.instances += 1
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			summary.triangles_instance += indexes(arrays).size() / 3
			var material: Material = node.get_active_material(surface)
			if material is ShaderMaterial:
				materials[material.get_instance_id()] = true
				shaders[material.shader.get_instance_id()] = true
		if seen.has(mesh.get_instance_id()): continue
		seen[mesh.get_instance_id()] = true
		summary.unique_meshes += 1
		if mesh is ArrayMesh: summary.array_meshes += 1
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			summary.vertices_unique += arrays[Mesh.ARRAY_VERTEX].size()
			if arrays[Mesh.ARRAY_INDEX] != null: summary.indices_unique += arrays[Mesh.ARRAY_INDEX].size()
		var bytes := serialized_bytes(mesh)
		for key in bytes: summary[key] += bytes[key]
	summary.shader_materials = materials.size()
	summary.shaders = shaders.size()
	return summary

func index_unindexed(root_node: Node3D) -> Dictionary:
	var replacements := {}
	var deltas := {}
	for path: String in meshes(root_node):
		var node: MeshInstance3D = meshes(root_node)[path]
		var old: Mesh = node.mesh
		if not old is ArrayMesh or old.get_surface_count() != 1: continue
		var old_id := old.get_instance_id()
		if replacements.has(old_id):
			node.mesh = replacements[old_id]
			continue
		var arrays: Array = old.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_INDEX] != null: continue
		var tool := SurfaceTool.new()
		tool.create_from(old, 0)
		tool.index()
		var candidate := tool.commit()
		var difference := compare_arrays(arrays, candidate.surface_get_arrays(0))
		if not difference.is_empty(): deltas[path] = difference
		replacements[old_id] = candidate
		node.mesh = candidate
	return {"replacements": replacements.size(), "differences": deltas}

func compare_roots(first: Node3D, second: Node3D) -> Dictionary:
	var a := meshes(first)
	var b := meshes(second)
	var differences := {}
	if a.keys() != b.keys(): differences["paths"] = "different"
	for path in a:
		if not b.has(path): continue
		var left: MeshInstance3D = a[path]
		var right: MeshInstance3D = b[path]
		if left.transform != right.transform: differences[path + "/transform"] = true
		if left.mesh.get_surface_count() != right.mesh.get_surface_count():
			differences[path + "/surfaces"] = true
			continue
		for surface in left.mesh.get_surface_count():
			var diff := compare_arrays(left.mesh.surface_get_arrays(surface), right.mesh.surface_get_arrays(surface))
			if not diff.is_empty(): differences[path + "/" + str(surface)] = diff
	return differences

func run() -> void:
	var baseline := Extra.build()
	var independent := Extra.build()
	var candidate := ExtraIndexed.build()
	root.add_child(baseline.root)
	root.add_child(independent.root)
	root.add_child(candidate.root)
	var base_meshes := meshes(baseline.root)
	var cand_meshes := meshes(independent.root)
	var shared := 0
	for path in base_meshes:
		if base_meshes[path].mesh == cand_meshes[path].mesh: shared += 1
	var original := inventory(baseline.root)
	var independent_diff := compare_roots(baseline.root, independent.root)
	var indexed := inventory(candidate.root)
	var stock_diff := compare_roots(baseline.root, candidate.root)
	print("STOCK ", JSON.stringify(original))
	print("STOCK_CROSS_BUILD_MESH_INSTANCES_SHARED ", shared)
	print("STOCK_CROSS_BUILD_DIFFERENCES ", JSON.stringify(independent_diff))
	print("INDEXED ", JSON.stringify(indexed))
	print("STOCK_INDEX_DIFFERENCES ", JSON.stringify(stock_diff))
	var skin_a: Dictionary = PaintAdapter.prepare(PaintAdapter.EXTRA, baseline.root)
	var skin_b: Dictionary = PaintAdapter.prepare(PaintAdapter.EXTRA, candidate.root)
	check(skin_a.ok and skin_b.ok, "custom skin prepare")
	if skin_a.ok and skin_b.ok:
		var paint_a := inventory(baseline.root)
		var paint_b := inventory(candidate.root)
		var paint_diff := compare_roots(baseline.root, candidate.root)
		check(paint_diff.is_empty(), "indexed custom-prepared attributes")
		var paint_variants := {}
		var paint_shaders := {}
		var paint_codes := {}
		var base_codes := {}
		var paint_resources: Array[Material] = []
		for node: MeshInstance3D in meshes(baseline.root).values():
			for surface in node.mesh.get_surface_count():
				var material: Material = node.get_active_material(surface)
				if not material is ShaderMaterial or material.resource_name != "openrc-paint": continue
				base_codes[material.shader.code.sha256_text()] = true
				if paint_variants.has(material.get_instance_id()): continue
				var painted: ShaderMaterial = PaintAdapter.paint(material, {"base_color": [1.0, 1.0, 1.0, 1.0]}, null)
				check(painted != null, "paint material")
				if painted != null:
					paint_resources.append(painted)
					paint_variants[material.get_instance_id()] = true
					paint_shaders[painted.shader.get_instance_id()] = true
					paint_codes[painted.shader.code.sha256_text()] = true
		print("PREPARED_ORIGINAL ", JSON.stringify(paint_a))
		print("PREPARED_INDEXED ", JSON.stringify(paint_b))
		print("PREPARED_INDEX_DIFFERENCES ", JSON.stringify(paint_diff))
		print("PAINT_SHADER_COUNTS ", JSON.stringify({"prepared_distinct_code": base_codes.size(), "paint_materials": paint_variants.size(), "paint_shaders": paint_shaders.size(), "paint_distinct_code": paint_codes.size()}))
	check(independent_diff.is_empty(), "independent builds")
	check(stock_diff.is_empty(), "indexed source attributes")
	baseline.root.free()
	independent.root.free()
	candidate.root.free()
	print("EXTRA_GEOMETRY_PROBE_DONE failures=", failures)
	quit(1 if failures else 0)
