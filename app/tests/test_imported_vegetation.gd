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
	_check("eleven retained tree variants", counts.get("trees", 0) == 11)
	_check("three downloaded shrubs", counts.get("shrubs", 0) == 3)
	_check("seven downloaded grass and herb assets", counts.get("grass_and_herbs", 0) == 7)
	_check("four downloaded flowering assets", counts.get("flowers", 0) == 4)
	_check("two downloaded crops", counts.get("crops", 0) == 2)
	_check("one downloaded reed clump", counts.get("reeds", 0) == 1)
	_check("all pinned sources are cataloged", data.get("sources", []).size() == 10)

	var assets: Array = data.get("assets", [])
	_check("28 assets are cataloged", assets.size() == 28)
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

	var oak := ImportedVegetation.get_asset("oak_tree")
	var oak_parts := ImportedVegetation.get_parts("oak_tree")
	_check("oak entry pins the OpenGameArt source and retained LOD0 geometry",
		oak.get("source_id", "") == "opengameart_oak_tree_lod_2026"
		and oak.get("role", "") == "tree"
		and int(oak.get("source_triangles", 0)) == 5303
		and int(oak.get("source_surfaces", 0)) == 1)
	_check("oak LOD0 imports as one original mesh part", oak_parts.size() == 1)
	if oak_parts.size() == 1:
		var oak_mesh: Mesh = oak_parts[0].get("mesh")
		var oak_materials: Array = oak_parts[0].get("materials", [])
		_check("oak source mesh has one surface and 5,303 triangles",
			oak_mesh != null
			and oak_mesh.get_surface_count() == 1
			and oak_mesh.get_faces().size() / 3 == 5303)
		_check("oak part preserves the imported source material reference",
			oak_materials.size() == 1
			and oak_mesh != null
			and oak_mesh.surface_get_material(0) == oak_materials[0])

	var maple := ImportedVegetation.get_asset("maple_tree")
	var maple_parts := ImportedVegetation.get_parts("maple_tree")
	var maple_lod: Dictionary = maple.get("lod", {})
	_check("Maple pins the reviewed LOLIPOP LOD1 source and geometry",
		maple.get("source_id", "") == "lolipop_maple_2026"
		and maple.get("role", "") == "tree"
		and int(maple.get("source_triangles", 0)) == 5541
		and int(maple.get("source_surfaces", 0)) == 2
		and maple_lod.get("imported_supplied_levels", []) == ["LOD1"])
	_check("Maple source mesh parts load", not maple_parts.is_empty())
	var maple_triangles := 0
	var maple_surfaces := 0
	var maple_material_mapping_valid := true
	for part: Dictionary in maple_parts:
		var maple_mesh: Mesh = part.get("mesh")
		var maple_materials: Array = part.get("materials", [])
		if maple_mesh == null:
			maple_material_mapping_valid = false
			continue
		maple_triangles += maple_mesh.get_faces().size() / 3
		maple_surfaces += maple_mesh.get_surface_count()
		maple_material_mapping_valid = maple_material_mapping_valid \
			and maple_materials.size() == maple_mesh.get_surface_count()
		for surface_index in range(mini(maple_mesh.get_surface_count(), maple_materials.size())):
			maple_material_mapping_valid = maple_material_mapping_valid \
				and maple_mesh.surface_get_material(surface_index) == maple_materials[surface_index]
	_check("Maple source meshes retain 5,541 triangles and two material surfaces",
		maple_triangles == 5541 and maple_surfaces == 2)
	_check("Maple source materials stay attached to their imported surfaces", maple_material_mapping_valid)
	for asset_id in ["landscapelab_quercus", "landscapelab_pine"]:
		for part: Dictionary in ImportedVegetation.get_parts(asset_id):
			var source_mesh: Mesh = part.mesh
			for surface_index in source_mesh.get_surface_count():
				var original := source_mesh.surface_get_material(surface_index) as StandardMaterial3D
				var effective := part.materials[surface_index] as StandardMaterial3D
				_check("%s keeps supplier materials immutable and renders dielectric vegetation" % asset_id,
					original != null and effective != null and original != effective
					and is_equal_approx(original.metallic, 0.5) and is_zero_approx(effective.metallic)
					and original.albedo_texture == effective.albedo_texture
					and original.normal_texture == effective.normal_texture
					and original.transparency == effective.transparency
					and is_equal_approx(original.alpha_scissor_threshold, effective.alpha_scissor_threshold))


func _test_fit_and_aliases() -> void:
	_check("shade tree alias starts with the mature Maple source", ImportedVegetation.resolve_id("shade_tree", 7) == "maple_tree")
	var mature_forms: Dictionary = {}
	for seed in range(-7, 7):
		var id := ImportedVegetation.resolve_id("shade_tree", seed)
		mature_forms[id] = true
		_check("tree aliases share the same deterministic source", id == ImportedVegetation.resolve_id("tree", seed))
	_check("mature aliases retain protected Maple and use realistic oak/pine replacements",
		mature_forms.size() == 3
		and mature_forms.has("maple_tree")
		and mature_forms.has("landscapelab_quercus") and mature_forms.has("landscapelab_pine")
		and not mature_forms.has(""))
	var maple := VegetationPlacement.spec("shade_tree", 793949324)
	_check("production Maple placement uses its mature height and source geometry budget",
		maple.get("asset_id", "") == "maple_tree"
		and is_equal_approx(float(maple.get("height", 0.0)), 14.0)
		and int(maple.get("triangles", 0)) == 5541
		and absf(float(maple.get("width", 0.0)) - 9.63) < 0.05
		and absf(float(maple.get("depth", 0.0)) - 13.24) < 0.05)
	_check("sapling alias uses downloaded oak and pine variants",
		ImportedVegetation.resolve_id("sapling", 0) == "landscapelab_quercus"
		and ImportedVegetation.resolve_id("sapling", 1) == "landscapelab_pine"
		and ImportedVegetation.resolve_id("sapling", 2) == "landscapelab_pine")
	var sapling_assets: Dictionary = {}
	var sapling_heights_valid := true
	for seed in 32:
		var sapling: Dictionary = VegetationPlacement.spec("sapling", seed)
		sapling_assets[sapling.get("asset_id", "")] = true
		sapling_heights_valid = sapling_heights_valid and float(sapling.get("height", 0.0)) >= 3.2 \
			and float(sapling.get("height", 99.0)) <= 4.8 and float(sapling.get("triangles", 0)) > 0
	_check("sapling placement keeps natural height and source triangle metadata", sapling_heights_valid)
	_check("saplings sample both downloaded realistic variants", sapling_assets.size() == 2 \
		and sapling_assets.has("landscapelab_quercus") and sapling_assets.has("landscapelab_pine"))
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
	# Retain the legacy wind-compatible source for this batching/wind regression.
	_check("exact retained tree queues its source", ImportedVegetation.queue(batches, "common_tree_3", tree_transform, 1, "tree-damaged") == "common_tree_3")
	_check("exact asset queues without changing ID", ImportedVegetation.queue(
		batches, "wheat_4", second_transform, 2, "", Color(0.4, 1.2, 0.9, 0.0)) == "wheat_4")
	var queued_tint: Color = batches["wheat_4"][0].get("tint", Color.WHITE)
	_check("queue clamps tint RGB and keeps alpha opaque",
		is_equal_approx(queued_tint.r, 0.86) and is_equal_approx(queued_tint.g, 1.0)
		and is_equal_approx(queued_tint.b, 0.9) and is_equal_approx(queued_tint.a, 1.0))
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
	var bounds_records: Array = root.get_meta("_imported_vegetation_state", {}).get("bounds", [])
	var wheat_tint_retained := false
	for bounds_record: Dictionary in bounds_records:
		if str(bounds_record.get("asset_id", "")) == "wheat_4":
			var tint: Color = bounds_record.get("tint", Color.WHITE)
			wheat_tint_retained = is_equal_approx(tint.r, 0.86) and is_equal_approx(tint.g, 1.0) \
				and is_equal_approx(tint.b, 0.9) and is_equal_approx(tint.a, 1.0)
	_check("builder retains bounded tint with CPU instance bounds", wheat_tint_retained)
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
	var landscape_maples := 0
	for group: Dictionary in scenery_result.scenery.groups:
		if str(group.get("id", "")).begins_with("maple-"):
			for placement: Dictionary in group.get("placements", []):
				var maple := VegetationPlacement.spec("shade_tree", int(placement.seed))
				_check("landscape maple uses a smaller proportional crown",
					maple.get("asset_id") == "maple_tree" and float(maple.height) >= 9.5 and float(maple.height) <= 12.0)
				landscape_maples += 1
		if str(group.get("id", "")) != "saplings":
			continue
		found = true
		var placements: Array = group.get("placements", [])
		_check("four club saplings remain after three trees move into the landscape", placements.size() == 4)
		var valid := true
		var assets: Dictionary = {}
		for placement: Dictionary in placements:
			var plant: Dictionary = VegetationPlacement.spec("sapling", int(placement.seed))
			assets[str(plant.get("asset_id", ""))] = true
			valid = valid and float(placement.north) < 0.0 \
				and plant.get("asset_id", "") in ["landscapelab_quercus", "landscapelab_pine"] \
				and float(plant.get("height", 0.0)) >= 3.2 and float(plant.get("height", 99.0)) <= 4.8
		_check("sapling rows stay behind the club and fit downloaded sources proportionally", valid)
		_check("sapling rows exercise both downloaded source variants", assets.has("landscapelab_quercus") and assets.has("landscapelab_pine"))
	_check("default layout contains its downloaded saplings group", found)
	_check("three additional maples reach the farm and forest", landscape_maples == 3)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s %s" % [label, detail])
