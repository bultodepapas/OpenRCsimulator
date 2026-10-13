extends SceneTree

const VegetationPlacement := preload("res://scenery/vegetation_placement.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")

var _failures := 0


func _initialize() -> void:
	_test_catalog_and_parts()
	_test_fit_and_aliases()
	_test_default_sapling_group()
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
	_check("sapling alias is restricted to downloaded broadleaf variants",
		ImportedVegetation.resolve_id("sapling", 0) == "common_tree_1"
		and ImportedVegetation.resolve_id("sapling", 1) == "common_tree_3"
		and ImportedVegetation.resolve_id("sapling", 2) == "common_tree_1")
	var sapling_assets: Dictionary = {}
	var sapling_heights_valid := true
	for seed in 32:
		var sapling: Dictionary = VegetationPlacement.spec("sapling", seed)
		sapling_assets[sapling.get("asset_id", "")] = true
		sapling_heights_valid = sapling_heights_valid and float(sapling.get("height", 0.0)) >= 3.2 \
			and float(sapling.get("height", 99.0)) <= 4.8 and float(sapling.get("triangles", 0)) > 0
	_check("sapling placement keeps natural height and source triangle metadata", sapling_heights_valid)
	_check("saplings sample both downloaded broadleaf variants", sapling_assets.size() == 2 \
		and sapling_assets.has("common_tree_1") and sapling_assets.has("common_tree_3"))
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
	var checked_source_materials := false
	for child in root.get_children():
		_check("batch child is a MultiMeshInstance3D", child is MultiMeshInstance3D)
		if child is MultiMeshInstance3D:
			var multi_mesh := (child as MultiMeshInstance3D).multimesh
			_check("batch has one queued plant", multi_mesh.instance_count == 1)
			_check("batch retains instance color data", multi_mesh.use_colors)
			if str(child.name).begins_with("common_tree_3_"):
				var source_materials: Array = ImportedVegetation.get_parts("common_tree_3")[0].get("materials", [])
				_check("default batch keeps original material per surface", multi_mesh.mesh.get_surface_count() == source_materials.size())
				for surface_index in range(mini(multi_mesh.mesh.get_surface_count(), source_materials.size())):
					_check(
						"tree source material %d is retained" % surface_index,
						multi_mesh.mesh.surface_get_material(surface_index) == source_materials[surface_index]
					)
				checked_source_materials = true
	_check("tree source material path was checked", checked_source_materials)
	var original_bounds := ImportedVegetation.bounds(root)
	_check("bounds include both plants", original_bounds.position.x < 0.0 and original_bounds.end.x > 30.0)
	_check("damage ID hides its source instances", ImportedVegetation.set_damage_hidden(root, "tree-damaged", true))
	var after_hide := ImportedVegetation.bounds(root)
	_check("bounds exclude hidden plant", after_hide.position.x > 29.0)
	_check("damage ID restores its source instances", ImportedVegetation.set_damage_hidden(root, "tree-damaged", false))
	var after_restore := ImportedVegetation.bounds(root)
	_check("bounds restore after crash recovery", is_equal_approx(after_restore.position.x, original_bounds.position.x))
	root.free()

	var wind_root := ImportedVegetation.build(batches, true)
	var checked_wind_materials := false
	for child in wind_root.get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with("common_tree_3_"):
			var wind_mesh := (child as MultiMeshInstance3D).multimesh.mesh
			var source_surface_count: int = ImportedVegetation.get_parts("common_tree_3")[0].get("materials", []).size()
			_check("wind mesh retains every source surface", wind_mesh.get_surface_count() == source_surface_count)
			for surface_index in range(wind_mesh.get_surface_count()):
				_check("wind material is shader-backed", wind_mesh.surface_get_material(surface_index) is ShaderMaterial)
			checked_wind_materials = true
	_check("wind shader path is explicitly opt-in", checked_wind_materials)
	ImportedVegetation.set_wind(wind_root, 0.0)
	wind_root.free()


func _test_default_sapling_group() -> void:
	var field_result := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads for sapling scene validation", bool(field_result.get("ok", false)))
	if not bool(field_result.get("ok", false)):
		return
	var scenery_result := SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	_check("generated sapling group passes scene validation", bool(scenery_result.get("ok", false)), str(scenery_result.get("errors", [])))
	if not bool(scenery_result.get("ok", false)):
		return
	var found := false
	for group: Dictionary in scenery_result.scenery.groups:
		if str(group.get("id", "")) != "saplings":
			continue
		found = true
		var placements: Array = group.get("placements", [])
		_check("default sapling group preserves seven stable source rows", placements.size() == 7)
		var valid := true
		var assets: Dictionary = {}
		for placement: Dictionary in placements:
			var plant: Dictionary = VegetationPlacement.spec("sapling", int(placement.seed))
			assets[str(plant.get("asset_id", ""))] = true
			valid = valid and float(placement.north) < 0.0 \
				and plant.get("asset_id", "") in ["common_tree_1", "common_tree_3"] \
				and float(plant.get("height", 0.0)) >= 3.2 and float(plant.get("height", 99.0)) <= 4.8
		_check("sapling rows stay behind the club and fit downloaded sources proportionally", valid)
		_check("sapling rows exercise both downloaded source variants", assets.has("common_tree_1") and assets.has("common_tree_3"))
	_check("default layout contains its downloaded saplings group", found)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s %s" % [label, detail])
