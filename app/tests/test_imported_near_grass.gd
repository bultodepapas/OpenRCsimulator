extends SceneTree

const ImportedNearGrass := preload("res://scenery/imported_near_grass.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const NearGrass := preload("res://render/near_grass.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const FieldLoader := preload("res://data/field_loader.gd")

var _checks := 0
var _failures := 0
var _field: Dictionary = {}


func _initialize() -> void:
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if bool(loaded.get("ok", false)):
		_field = loaded.field
		_test_quality_layouts()
		_test_path_and_bank_exclusions()
		_test_batched_source_build()
	print("%d downloaded near-grass checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_quality_layouts() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(NearGrass.DATA_PATH))
	var rows: Array = NearGrass.validated_rows(raw)
	_check("reuses the existing checksum-validated 6,000 grass rows", rows.size() == NearGrass.COUNT)
	var low := ImportedNearGrass.layout(_field, "low")
	var balanced := ImportedNearGrass.layout(_field, "balanced")
	var high := ImportedNearGrass.layout(_field, "high")
	_check("layout has a stable high-tier identity", _signature(high) == _signature(ImportedNearGrass.layout(_field, "high")))
	_check("all three downloaded grass families are represented", _asset_counts(high).size() == 3, str(_asset_counts(high)))
	_check("quality levels are nested low ⊆ balanced ⊆ high",
		_subset(low, balanced) and _subset(balanced, high), "%d / %d / %d" % [low.size(), balanced.size(), high.size()])
	_check("high-quality clumps stay under 50,000 source triangles", _triangle_count(high) <= ImportedNearGrass.MAX_SOURCE_TRIANGLES,
		str(_triangle_count(high)))
	_check("quality tiers retain accepted ground placements", _all_accepted(low) and _all_accepted(balanced) and _all_accepted(high))
	_check("natural heights remain between 0.12 and 0.25 m", _heights_valid(high))
	_check("existing yaw and size bytes drive orientation and natural uniform height", _source_rows_match(high, rows))
	_check("tier counts are bounded by their per-asset budgets", low.size() <= 38 and balanced.size() <= 76 and high.size() <= 150)


func _test_path_and_bank_exclusions() -> void:
	var high := ImportedNearGrass.layout(_field, "high")
	if high.is_empty():
		_check("exclusion fixtures have an accepted source placement", false)
		return
	var path_target: Dictionary = high[0]
	var path_north := float(path_target.north)
	var path_east := float(path_target.east)
	var path_scenery := {
		"groups": [{
			"id": "test-worn-path",
			"type": "track",
			"surface": "worn",
			"width": 1.0,
			"points": [Vector2(path_north, path_east - 1.0), Vector2(path_north, path_east + 1.0)],
		}],
	}
	var path_exclusions := ImportedNearGrass.exclusions_for(path_scenery)
	_check("worn scenery paths become grass exclusion polygons", not path_exclusions.is_empty())
	_check("NearGrass.accepts rejects the path center", not NearGrass.accepts(path_north, path_east, _field, path_exclusions))
	var after_path := ImportedNearGrass.layout(_field, "high", path_exclusions)
	_check("path-clipped layout replaces excluded rows with other stable candidates",
		not _contains_row(after_path, int(path_target.row_index)) and _same_asset_caps(after_path))
	_check("every emitted placement clears the path mask", _all_outside(after_path, path_exclusions))

	var bank_target: Dictionary = high[mini(1, high.size() - 1)]
	var bank_north := float(bank_target.north)
	var bank_east := float(bank_target.east)
	var bank := PackedFloat64Array([
		bank_north - 1.0, bank_east - 1.0,
		bank_north - 1.0, bank_east + 1.0,
		bank_north + 1.0, bank_east + 1.0,
		bank_north + 1.0, bank_east - 1.0,
	])
	var bank_exclusions := ImportedNearGrass.exclusions_for({}, {"id": "test-lake", "bank_ne_m": bank})
	_check("normalized lake bank becomes a grass exclusion polygon", bank_exclusions.size() == 1)
	_check("NearGrass.accepts rejects the lake bank", not NearGrass.accepts(bank_north, bank_east, _field, bank_exclusions))
	var after_bank := ImportedNearGrass.layout(_field, "high", bank_exclusions)
	_check("bank-clipped layout replaces excluded rows", not _contains_row(after_bank, int(bank_target.row_index)))
	_check("every emitted placement clears the bank mask", _all_outside(after_bank, bank_exclusions))


func _test_batched_source_build() -> void:
	var expected := ImportedNearGrass.layout(_field, "high")
	var root := ImportedNearGrass.build(_field, "high")
	_check("runtime seam retains the NearGrass root name", root.name == "NearGrass")
	_check("root declares downloaded source geometry", bool(root.get_meta("imported", false)))
	_check("root keeps all CPU placements for diagnostics and damage integration",
		(root.get_meta("cpu_placements", []) as Array).size() == expected.size()
		and (root.get_meta("placements", []) as Array).size() == expected.size())
	_check("metadata triangle count matches placements", int(root.get_meta("source_triangles", -1)) == _triangle_count(expected)
		and int(root.get_meta("triangles", -1)) == _triangle_count(expected))
	_check("root contains no more than three source asset batches", int(root.get_meta("asset_batches", -1)) <= 3
		and int(root.get_meta("batches", -1)) <= 3
		and root.get_child_count() <= 3, "%d MultiMeshes" % root.get_child_count())
	_check("source clumps preserve proportions with uniform instance scale", _uniform_scales_valid(root))
	_check("root uses only instanced source meshes", _only_multimeshes(root) and _count_colliders(root) == 0)
	_check("source batches retain instance color data and cast no shadows", _color_data_and_shadows_off(root))
	_check("source materials and surface geometry remain intact", _matches_source_parts(root))
	root.free()


func _signature(placements: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for placement: Dictionary in placements:
		parts.append("%s:%d:%d:%d" % [str(placement.asset_id), int(placement.row_index), int(placement.yaw_u16), int(placement.height_m * 1000000.0)])
	return "\n".join(parts)


func _asset_counts(placements: Array[Dictionary]) -> Dictionary:
	var counts := {}
	for placement: Dictionary in placements:
		var asset_id := str(placement.asset_id)
		counts[asset_id] = int(counts.get(asset_id, 0)) + 1
	return counts


func _triangle_count(placements: Array[Dictionary]) -> int:
	var result := 0
	for placement: Dictionary in placements:
		result += int(placement.source_triangles)
	return result


func _row_set(placements: Array[Dictionary]) -> Dictionary:
	var result := {}
	for placement: Dictionary in placements:
		result[int(placement.row_index)] = true
	return result


func _subset(source: Array[Dictionary], target: Array[Dictionary]) -> bool:
	var target_rows := _row_set(target)
	for placement: Dictionary in source:
		if not target_rows.has(int(placement.row_index)):
			return false
	return true


func _contains_row(placements: Array[Dictionary], row_index: int) -> bool:
	for placement: Dictionary in placements:
		if int(placement.row_index) == row_index:
			return true
	return false


func _same_asset_caps(placements: Array[Dictionary]) -> bool:
	var counts := _asset_counts(placements)
	return int(counts.get("grass_common_short", 0)) <= 67 \
		and int(counts.get("grass_common_tall", 0)) <= 42 \
		and int(counts.get("grass_wispy_tall", 0)) <= 41


func _all_accepted(placements: Array[Dictionary]) -> bool:
	for placement: Dictionary in placements:
		if not NearGrass.accepts(float(placement.north), float(placement.east), _field):
			return false
	return true


func _heights_valid(placements: Array[Dictionary]) -> bool:
	for placement: Dictionary in placements:
		var height := float(placement.height_m)
		if height < ImportedNearGrass.MIN_HEIGHT_M or height > ImportedNearGrass.MAX_HEIGHT_M:
			return false
	return not placements.is_empty()


func _source_rows_match(placements: Array[Dictionary], rows: Array) -> bool:
	for placement: Dictionary in placements:
		var row: Array = rows[int(placement.row_index)]
		if int(placement.yaw_u16) != int(row[2]) or int(placement.size_u8) != int(row[3]):
			return false
		var expected_height := lerpf(ImportedNearGrass.MIN_HEIGHT_M, ImportedNearGrass.MAX_HEIGHT_M,
			float(row[3]) / 255.0)
		if not is_equal_approx(float(placement.height_m), expected_height):
			return false
	return true


func _all_outside(placements: Array[Dictionary], exclusions: Array) -> bool:
	for placement: Dictionary in placements:
		if GrassMask.excludes(float(placement.north), float(placement.east), exclusions):
			return false
	return true


func _only_multimeshes(root: Node) -> bool:
	for child: Node in root.get_children():
		if not child is MultiMeshInstance3D:
			return false
	return true


func _color_data_and_shadows_off(root: Node) -> bool:
	if root.get_child_count() == 0:
		return false
	for child: Node in root.get_children():
		if not child is MultiMeshInstance3D:
			return false
		var instance := child as MultiMeshInstance3D
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
		if instance.multimesh == null or not instance.multimesh.use_colors or not instance.multimesh.use_custom_data:
			return false
	return true


func _uniform_scales_valid(root: Node) -> bool:
	var placements: Array = root.get_meta("cpu_placements", [])
	if placements.is_empty():
		return false
	for placement_value: Variant in placements:
		if not placement_value is Dictionary:
			return false
		var placement: Dictionary = placement_value
		var transform: Transform3D = placement.get("transform", Transform3D.IDENTITY)
		var scale := transform.basis.get_scale()
		if scale.x <= 0.0 or not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z):
			return false
	return true


func _matches_source_parts(root: Node) -> bool:
	var seen := {}
	for child: Node in root.get_children():
		if not child is MultiMeshInstance3D:
			return false
		var instance := child as MultiMeshInstance3D
		var asset_id := str(instance.name).get_slice("_Part_", 0)
		var part_index := int(str(instance.name).get_slice("_Part_", 1))
		var source_parts := ImportedVegetation.get_parts(asset_id)
		if part_index < 0 or part_index >= source_parts.size():
			return false
		var source_mesh: Mesh = source_parts[part_index].get("mesh")
		var runtime_mesh: Mesh = instance.multimesh.mesh
		if source_mesh == null or runtime_mesh == null or source_mesh.get_surface_count() != runtime_mesh.get_surface_count():
			return false
		for surface_index: int in range(source_mesh.get_surface_count()):
			if source_mesh.surface_get_material(surface_index) != runtime_mesh.surface_get_material(surface_index):
				return false
			var source_arrays := source_mesh.surface_get_arrays(surface_index)
			var runtime_arrays := runtime_mesh.surface_get_arrays(surface_index)
			if source_arrays[Mesh.ARRAY_VERTEX] != runtime_arrays[Mesh.ARRAY_VERTEX] \
				or source_arrays[Mesh.ARRAY_INDEX] != runtime_arrays[Mesh.ARRAY_INDEX]:
				return false
		seen[asset_id] = true
	return seen.size() == 3


func _count_colliders(node: Node) -> int:
	var total := 1 if node is CollisionObject3D else 0
	for child: Node in node.get_children():
		total += _count_colliders(child)
	return total


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
