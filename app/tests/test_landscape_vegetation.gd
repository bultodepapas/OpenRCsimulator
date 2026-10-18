## LU-17: preserve the bounded, batched vegetation interface while improving close foliage and plant form.
## Run: godot --headless --path . --script res://tests/test_landscape_vegetation.gd
extends SceneTree

const Vegetation = preload("res://scenery/vegetation.gd")
const Flowers = preload("res://scenery/flowers.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Prefabs = preload("res://scenery/prefabs.gd")
const Scenery = preload("res://scenery/scenery.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Population = preload("res://scenery/population.gd")
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")
const VegetationPlacement = preload("res://scenery/vegetation_placement.gd")

const TREE_XZ_LIMIT := 3.84 # baseline max half-extent across the measured seed sample; catalog width remains 8 m.
const TREE_TOP_LIMIT := 10.0 # measured baseline top is below 10.0 m; catalog/collision height remains 10.5 m.
const TRIANGLE_LIMIT := 650000 # LU-21: native-qualified source-scene ceiling; counts surfaces and indexed instances.

var checks := 0
var failures := 0


func _initialize() -> void:
	ShaderClock.register()
	_test_three_crown_habits()
	_test_sampled_tree_envelope()
	_test_flower_cluster_mesh_and_batching()
	_test_prefab_flower_clump()
	_test_complete_scenery_budget()
	print("LU-17 vegetation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_three_crown_habits() -> void:
	var seeds := {}
	for seed in 256:
		var habit := int(Palette.hash01(seed, 3) * 3.0)
		if not seeds.has(habit):
			seeds[habit] = seed
	_check("a deterministic seed represents each broadleaf habit", seeds.size() == 3)
	if seeds.size() != 3:
		return
	var triangle_counts: Array[int] = []
	var digests: Array[String] = []
	for habit in 3:
		var seed: int = seeds[habit]
		var first: Dictionary = _tree(seed)
		var second: Dictionary = _tree(seed)
		var kit: MeshKit = first.kit
		var moving: Array = first.moving
		var triangle_count := kit.triangle_count()
		var digest := kit.digest()
		var bounds := _bounds(kit.verts)
		var within := bounds.position.y >= -0.001 and bounds.end.y <= TREE_TOP_LIMIT
		for axis in [0, 2]:
			within = within and bounds.position[axis] >= -TREE_XZ_LIMIT and bounds.end[axis] <= TREE_XZ_LIMIT
		for part: Dictionary in moving:
			var part_kit: MeshKit = part.kit
			triangle_count += part_kit.triangle_count()
			var part_box := _bounds(part_kit.verts)
			var world_y_min := float(part_box.position.y + part.pivot.y)
			var world_y_max := float(part_box.end.y + part.pivot.y)
			within = within and world_y_min >= -0.001 and world_y_max <= TREE_TOP_LIMIT
			# Mode 3 y-axis rotation can reach any azimuth; preserve the pre-LU-17 radial crown envelope.
			for vertex: Vector3 in part_kit.verts:
				within = within and Vector2(vertex.x, vertex.z).length() <= TREE_XZ_LIMIT
		_check("habit %d stays inside the previous foliage envelope" % habit, within,
			"seed=%d bounds=%s..%s" % [seed, bounds.position, bounds.end])
		_check("habit %d keeps its single bounded mode-3 crown part" % habit,
			moving.size() == 1 and moving[0].kind == "crown" and int(moving[0].motion_mode) == 3)
		_check("habit %d rebuild is byte-identical" % habit,
			kit.digest() == second.kit.digest() and _moving_digest(moving) == _moving_digest(second.moving))
		_check("habit %d crown normals remain finite and follow the deformed surface" % habit,
			_normals_follow_faces(kit))
		triangle_counts.append(triangle_count)
		digests.append(digest)
	_check("all three crown habits retain distinct geometry budgets", triangle_counts.size() == 3
		and triangle_counts[0] != triangle_counts[1] and triangle_counts[1] != triangle_counts[2])
	_check("crown construction remains seed-varied", digests.size() == 3 and digests[0] != digests[1] and digests[1] != digests[2])


func _test_flower_cluster_mesh_and_batching() -> void:
	var mesh := Flowers.cushion_mesh("temperate")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var triangles := vertices.size() / 3
	var petal_triangles := 0
	var stem_triangles := 0
	var leaf_triangles := 0
	for i in range(0, vertices.size(), 3):
		var petal := colours[i].a < 0.5 and colours[i + 1].a < 0.5 and colours[i + 2].a < 0.5
		if petal:
			petal_triangles += 1
			continue
		var y_min := minf(vertices[i].y, minf(vertices[i + 1].y, vertices[i + 2].y))
		var y_max := maxf(vertices[i].y, maxf(vertices[i + 1].y, vertices[i + 2].y))
		if y_min < 0.03 and y_max > 0.25:
			stem_triangles += 1
		elif y_min > 0.04 and y_max < 0.30:
			leaf_triangles += 1
	var mesh_bounds := mesh.get_aabb()
	_check("plant mesh uses 24 triangles and stays in the same small-plant budget", triangles == 24)
	_check("petals remain species-colour marked while stems and leaves use vertex colour", petal_triangles == 12
		and stem_triangles == 3 and leaf_triangles == 6)
	_check("plant stays below 0.45 m with ground contact", mesh_bounds.position.y >= -0.001
		and mesh_bounds.end.y <= 0.45)
	_check("plant foliage remains inside its previous half-metre footprint", absf(mesh_bounds.position.x) <= 0.5
		and absf(mesh_bounds.end.x) <= 0.5 and absf(mesh_bounds.position.z) <= 0.5
		and absf(mesh_bounds.end.z) <= 0.5)

	var positions: Array = [Vector3(1.0, 1.0, 0.4), Vector3(2.0, 1.5, 0.5), Vector3(70.0, 2.0, 0.7)]
	var include := func(_id: int) -> bool: return true
	var nodes: Array[MultiMeshInstance3D] = Flowers.build(positions, "temperate", include)
	_check("flower positions remain grouped into the same sixty-metre chunks", nodes.size() == 2)
	if nodes.size() == 2:
		var shared_id := nodes[0].multimesh.mesh.get_instance_id()
		var shared := true
		var all_bounds := true
		for node: MultiMeshInstance3D in nodes:
			shared = shared and node.multimesh.mesh.get_instance_id() == shared_id
			var actual := node.multimesh.get_aabb()
			all_bounds = all_bounds and node.custom_aabb.has_point(actual.position) and node.custom_aabb.has_point(actual.end)
		_check("flower chunks still share one draw mesh and the existing sway AABB", shared and all_bounds)
	for node: MultiMeshInstance3D in nodes:
		node.free()


func _test_prefab_flower_clump() -> void:
	var kit := MeshKit.new()
	Prefabs._flower_clump(kit, 417, "temperate")
	var box := _bounds(kit.verts)
	var petal_colours: Array = Palette.FLOWERS.values()
	var stem_triangles := 0
	var petal_triangles := 0
	var largest_low_stem_span := 0.0
	for i in range(0, kit.verts.size(), 3):
		var a: Vector3 = kit.verts[i]
		var b: Vector3 = kit.verts[i + 1]
		var c: Vector3 = kit.verts[i + 2]
		var colour: Color = kit.cols[i]
		if colour == Palette.veg("stem", "temperate") and kit.cols[i + 1] == colour and kit.cols[i + 2] == colour:
			stem_triangles += 1
			var max_y := maxf(a.y, maxf(b.y, c.y))
			if max_y <= 0.04:
				var span := Vector2(maxf(a.x, maxf(b.x, c.x)) - minf(a.x, minf(b.x, c.x)),
					maxf(a.z, maxf(b.z, c.z)) - minf(a.z, minf(b.z, c.z))).length()
				largest_low_stem_span = maxf(largest_low_stem_span, span)
		if petal_colours.has(colour) and kit.cols[i + 1] == colour and kit.cols[i + 2] == colour:
			petal_triangles += 1
	var count := kit.triangle_count()
	_check("prefab flower border replaces its mound with six visible stems and petals",
		stem_triangles >= 72 and petal_triangles >= 48,
		"triangles=%d stems=%d petals=%d" % [count, stem_triangles, petal_triangles])
	_check("rounded prefab flowers stay within the LU-24 300-triangle budget", count <= 300, "triangles=%d" % count)
	_check("prefab flower cluster stays inside the old 0.62 m footprint and 0.42 m height",
		box.position.x >= -0.31 and box.end.x <= 0.31 and box.position.z >= -0.31 and box.end.z <= 0.31
		and box.position.y >= -0.001 and box.end.y <= 0.42, str(box))
	_check("flower stems touch the ground without a broad green base mound", largest_low_stem_span <= 0.03,
		"low stem span=%.4f m" % largest_low_stem_span)


func _test_sampled_tree_envelope() -> void:
	var stays_inside := true
	for seed in 256:
		var built := _tree(seed)
		var kit: MeshKit = built.kit
		for vertex: Vector3 in kit.verts:
			stays_inside = stays_inside and absf(vertex.x) <= TREE_XZ_LIMIT and absf(vertex.z) <= TREE_XZ_LIMIT
			stays_inside = stays_inside and vertex.y >= -0.001 and vertex.y <= TREE_TOP_LIMIT
		for part: Dictionary in built.moving:
			var part_kit: MeshKit = part.kit
			for vertex: Vector3 in part_kit.verts:
				stays_inside = stays_inside and Vector2(vertex.x, vertex.z).length() <= TREE_XZ_LIMIT
				var y: float = vertex.y + part.pivot.y
				stays_inside = stays_inside and y >= -0.001 and y <= TREE_TOP_LIMIT
	_check("all 256 sampled trees keep the measured XZ, height and mode-3 wind envelope", stays_inside)


func _test_complete_scenery_budget() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var scenery: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("normalized lake loads for the complete scenery budget", bool(lake_result.get("ok", false)))
	var lake: Dictionary = lake_result.get("lake", {})
	var built := Scenery.build(field, scenery, {audio = false, birds = false, theme = "", quality = "high"}, {}, lake)
	var stats: Dictionary = built.get_meta("stats")
	var motion := built.get_node("Motion")
	var counts := {crown = 0, bush_tips = 0}
	for part: Node in motion.get_children():
		for kind: String in counts:
			if str(part.name).begins_with(kind + "_"):
				counts[kind] += 1
	_check("imported trees and shrubs stay out of the procedural motion tree; people use their population batch",
		int(stats.motion) == 5 and motion.get_child_count() == 5 and counts.crown == 0 and counts.bush_tips == 0
		and int(stats.moving_people) == 7)
	var static_cells := 0
	for child: Node in built.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("cell_"):
			static_cells += 1
	_check("static scenery remains within the current 63-cell budget", static_cells > 0 and static_cells <= 63, "actual=%d allocated=%d" % [static_cells, int(stats.cells)])
	var imported_plants: Node3D = built.get_node_or_null("ImportedVegetationBatches") as Node3D
	var botanical: Node3D = built.get_node_or_null("BotanicalHabitats") as Node3D
	var plants: Array = botanical.get_meta("plants", []) if botanical != null else []
	_check("production trees and shrubs are downloaded source meshes",
		imported_plants != null and int(stats.get("vegetation_instances", 0)) >= 16
		and imported_plants.get_children().all(func(child: Node) -> bool: return child is MultiMeshInstance3D))
	_check("downloaded flowers replace the retired 2,970 procedural cushions",
		int(stats.flowers) == 0 and botanical != null and plants.size() == int(stats.get("botanical_plants", -1)))
	_check("downloaded habitat triangles and batches meet their provisional budgets",
		int(stats.get("botanical_triangles", 0)) > 0 and int(stats.botanical_triangles) <= 90000
		and int(stats.get("botanical_batches", 99)) <= 24)
	var state: Dictionary = imported_plants.get_meta("_imported_vegetation_state", {}) if imported_plants != null else {}
	var damage_ids: Array = (state.get("damage", {}) as Dictionary).keys()
	_check("production imported vegetation retains source damage IDs", not damage_ids.is_empty())
	if not damage_ids.is_empty():
		var damage_id := str(damage_ids[0])
		var hidden := ImportedVegetation.set_damage_hidden(imported_plants, damage_id, true)
		var restored := ImportedVegetation.set_damage_hidden(imported_plants, damage_id, false)
		_check("source damage IDs hide and restore imported plants", hidden and restored, damage_id)
	var triangles := _triangle_count(built)
	var source_tree_counts: Dictionary = {}
	var source_tree_triangles := 0
	for group: Dictionary in scenery.groups:
		if str(group.get("type", "")) != "instances":
			continue
		for placement: Dictionary in group.get("placements", []):
			var prefab := str(placement.get("prefab", ""))
			if prefab not in ["shade_tree", "sapling"]:
				continue
			var tree: Dictionary = VegetationPlacement.spec(prefab, int(placement.get("seed", 0)))
			var asset_id := str(tree.get("asset_id", ""))
			source_tree_counts[asset_id] = int(source_tree_counts.get(asset_id, 0)) + 1
			source_tree_triangles += int(tree.get("triangles", 0))
	_check("complete scene uses eight downloaded forms at the same 17 trees",
		source_tree_counts == {common_tree_1 = 4, common_tree_2 = 1, common_tree_3 = 4,
			common_tree_4 = 1, pine_1 = 2, pine_2 = 2, pine_3 = 2, oak_tree = 1}
		and source_tree_triangles == 79215,
		"sources=%s triangles=%d" % [source_tree_counts, source_tree_triangles])
	_check("whole scenery stays below the approved LU-21 triangle ceiling", triangles <= TRIANGLE_LIMIT,
		"triangles=%d" % triangles)
	print("     LU-17 complete scenery triangles: %d (limit %d), imported tree sources=%s (%d triangles)" %
		[triangles, TRIANGLE_LIMIT, source_tree_counts, source_tree_triangles])
	built.free()


func _tree(seed: int) -> Dictionary:
	var kit := MeshKit.new()
	var moving: Array = Vegetation.shade_tree(kit, seed, "temperate")
	return {kit = kit, moving = moving}


func _bounds(vertices: PackedVector3Array) -> AABB:
	var box := AABB(vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		box = box.expand(vertex)
	return box


func _normals_follow_faces(kit: MeshKit) -> bool:
	if kit.norms.size() != kit.verts.size() or kit.verts.size() % 3 != 0:
		return false
	for i in range(0, kit.verts.size(), 3):
		var face := (kit.verts[i + 1] - kit.verts[i]).cross(kit.verts[i + 2] - kit.verts[i])
		if face.length_squared() < 1e-10:
			return false
		face = face.normalized()
		for j in 3:
			var normal: Vector3 = kit.norms[i + j]
			# MeshKit stores clockwise front faces, so their raw geometric cross points opposite the outward vertex normal.
			if not normal.is_finite() or not is_equal_approx(normal.length(), 1.0) or normal.dot(face) >= 0.0:
				return false
	return true


func _moving_digest(moving: Array) -> String:
	var result := ""
	for part: Dictionary in moving:
		result += str(part.kind, ":", part.motion_mode, ":", part.kit.digest(), ":", part.pivot, ":", part.axis)
	return result


func _triangle_count(root: Node) -> int:
	var count := 0
	for child: Node in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var mesh := (child as MeshInstance3D).mesh
			count += Population.triangles(mesh)
		elif child is MultiMeshInstance3D:
			var multimesh := (child as MultiMeshInstance3D).multimesh
			count += multimesh.instance_count * Population.triangles(multimesh.mesh)
		if child.get_child_count() > 0:
			count += _triangle_count(child)
	return count


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL %s %s" % [label, detail])
