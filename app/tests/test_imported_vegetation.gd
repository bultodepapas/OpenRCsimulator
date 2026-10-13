extends SceneTree

var _failures := 0


func _initialize() -> void:
	_test_catalog_and_parts()
	_test_fit_and_aliases()
	_test_batch_build_and_damage()
	if _failures == 0:
		print("imported vegetation tests passed")
		quit(0)
	else:
		push_error("%d imported vegetation test(s) failed" % _failures)
		quit(1)


func _test_catalog_and_parts() -> void:
	var data := ImportedVegetation.catalog()
	var counts: Dictionary = data.get("counts", {})
	_check("three downloaded tree variants", counts.get("trees", 0) == 3)
	_check("two downloaded shrubs", counts.get("shrubs", 0) == 2)
	_check("four downloaded grass and herb assets", counts.get("grass_and_herbs", 0) == 4)
	_check("three downloaded flowering assets", counts.get("flowers", 0) == 3)
	_check("two downloaded crops", counts.get("crops", 0) == 2)
	_check("one downloaded reed clump", counts.get("reeds", 0) == 1)
	_check("all pinned sources are cataloged", data.get("sources", []).size() == 3)

	var assets: Array = data.get("assets", [])
	_check("15 assets are cataloged", assets.size() == 15)
	for asset_value in assets:
		var asset: Dictionary = asset_value
		var asset_id := str(asset.get("id", ""))
		var part_list := ImportedVegetation.get_parts(asset_id)
		_check("%s source geometry loads" % asset_id, not part_list.is_empty())
		_check("%s source hash is present" % asset_id, str(asset.get("source_sha256", "")).length() == 64)
		_check("%s has authored grounded bounds" % asset_id, asset.get("grounded_bounds_m", {}).has("size"))
		var triangles := 0
		var surfaces := 0
		for part in part_list:
			var mesh: Mesh = part.get("mesh")
			_check("%s returns a source mesh" % asset_id, mesh != null)
			triangles += int(part.get("source_triangles", 0))
			surfaces += int(part.get("source_surfaces", 0))
			_check(
				"%s exposes one original material per surface" % asset_id,
				(part.get("materials", []) as Array).size() == mesh.get_surface_count()
			)
		_check("%s triangle count matches source" % asset_id, triangles == int(asset.get("source_triangles", -1)))
		_check("%s surface count matches source" % asset_id, surfaces == int(asset.get("source_surfaces", -1)))


func _test_fit_and_aliases() -> void:
	_check("shade tree alias resolves by seed", ImportedVegetation.resolve_id("shade_tree", 7) == "common_tree_3")
	_check("bush alias resolves deterministically", ImportedVegetation.resolve_id("bush", 5) == "bush_common_flowers")
	_check("unknown alias is rejected", ImportedVegetation.resolve_id("missing_plant", 0).is_empty())
	var source: Dictionary = ImportedVegetation.get_asset("common_tree_3")
	var source_height := float(source["source_bounds_m"]["height"])
	var requested_height := 4.5
	var placement := Transform3D(Basis.from_scale(Vector3(2.0, 3.0, 4.0)), Vector3(12.0, 8.0, -4.0))
	var fitted := ImportedVegetation.fit_to_height("common_tree_3", requested_height, placement)
	var uniform_scale := fitted.basis.x.length()
	_check("fit preserves requested tree height", is_equal_approx(source_height * uniform_scale, requested_height))
	_check("fit removes nonuniform scale", is_equal_approx(fitted.basis.x.length(), fitted.basis.y.length()) and is_equal_approx(fitted.basis.y.length(), fitted.basis.z.length()))
	_check("fit retains placement XZ", is_equal_approx(fitted.origin.x, placement.origin.x) and is_equal_approx(fitted.origin.z, placement.origin.z))


func _test_batch_build_and_damage() -> void:
	var batches: Dictionary = {}
	var tree_transform := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var second_transform := Transform3D(Basis.IDENTITY, Vector3(30.0, 0.0, 0.0))
	_check("tree alias queues resolved asset", ImportedVegetation.queue(batches, "shade_tree", tree_transform, 1, "tree-damaged") == "common_tree_3")
	_check("exact asset queues without changing ID", ImportedVegetation.queue(batches, "wheat_4", second_transform, 2) == "wheat_4")
	var root := ImportedVegetation.build(batches)
	var expected_part_nodes := ImportedVegetation.get_parts("common_tree_3").size() + ImportedVegetation.get_parts("wheat_4").size()
	_check("builder emits one shared batch per source part", root.get_child_count() == expected_part_nodes)
	for child in root.get_children():
		_check("batch child is a MultiMeshInstance3D", child is MultiMeshInstance3D)
		if child is MultiMeshInstance3D:
			_check("batch has both queued plants", (child as MultiMeshInstance3D).multimesh.instance_count == 1)
	var original_bounds := ImportedVegetation.bounds(root)
	_check("bounds include both plants", original_bounds.position.x < 0.0 and original_bounds.end.x > 30.0)
	_check("damage ID hides its source instances", ImportedVegetation.set_damage_hidden(root, "tree-damaged", true))
	var after_hide := ImportedVegetation.bounds(root)
	_check("bounds exclude hidden plant", after_hide.position.x > 29.0)
	_check("damage ID restores its source instances", ImportedVegetation.set_damage_hidden(root, "tree-damaged", false))
	var after_restore := ImportedVegetation.bounds(root)
	_check("bounds restore after crash recovery", is_equal_approx(after_restore.position.x, original_bounds.position.x))
	root.free()


func _check(label: String, condition: bool) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % label)
