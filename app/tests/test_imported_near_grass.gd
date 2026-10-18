extends SceneTree

const ImportedNearGrass := preload("res://scenery/imported_near_grass.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const NearGrass := preload("res://render/near_grass.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GrassQuality := preload("res://render/grass_quality.gd")
const GRASS_QUALITY_ENV := "OPENRC_GRASS_QUALITY"

var _checks := 0
var _failures := 0
var _field: Dictionary = {}


func _initialize() -> void:
	var previous_quality := OS.get_environment(GRASS_QUALITY_ENV)
	OS.set_environment(GRASS_QUALITY_ENV, "")
	_check("default environment selects the original static grass path", not GrassQuality.enhanced())
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if bool(loaded.get("ok", false)):
		_field = loaded.field
		_test_mode("default", false)
	OS.set_environment(GRASS_QUALITY_ENV, "enhanced")
	_check("enhanced opt-in is read from the process-local environment", GrassQuality.enhanced())
	if bool(loaded.get("ok", false)):
		_test_mode("enhanced", true)
	OS.set_environment(GRASS_QUALITY_ENV, previous_quality)
	print("%d downloaded near-grass checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_mode(label: String, expect_enhanced: bool) -> void:
	_test_empty_layout(label, expect_enhanced)
	_test_quality_layouts(label, expect_enhanced)
	_test_path_and_bank_exclusions(label, expect_enhanced)
	_test_batched_source_build(label, expect_enhanced)


func _test_empty_layout(label: String, expect_enhanced: bool) -> void:
	var empty_root := ImportedNearGrass.build({}, "high")
	_check("%s empty layout avoids grass material adaptation" % label,
		GrassQuality.enhanced() == expect_enhanced and empty_root != null
		and empty_root.get_child_count() == 0 and not empty_root.has_meta("grass_wind"))
	empty_root.free()


func _test_quality_layouts(label: String, expect_enhanced: bool) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(NearGrass.DATA_PATH))
	var rows: Array = NearGrass.validated_rows(raw)
	_check("reuses the existing checksum-validated 6,000 grass rows", rows.size() == NearGrass.COUNT)
	var low := ImportedNearGrass.layout(_field, "low")
	var balanced := ImportedNearGrass.layout(_field, "balanced")
	var high := ImportedNearGrass.layout(_field, "high")
	_check("%s layout has a stable high-tier identity" % label, _signature(high) == _signature(ImportedNearGrass.layout(_field, "high")))
	_check("%s route represents all three downloaded grass families" % label, _asset_counts(high).size() == 3, str(_asset_counts(high)))
	_check("%s quality levels are nested low ⊆ balanced ⊆ high" % label,
		_subset(low, balanced) and _subset(balanced, high), "%d / %d / %d" % [low.size(), balanced.size(), high.size()])
	_check("%s high-quality clumps stay under 50,000 source triangles" % label, _triangle_count(high) <= ImportedNearGrass.MAX_SOURCE_TRIANGLES,
		str(_triangle_count(high)))
	_check("%s tiers retain accepted ground placements" % label, _all_accepted(low) and _all_accepted(balanced) and _all_accepted(high))
	_check("%s natural heights remain between 0.12 and 0.25 m" % label, _heights_valid(high))
	_check("%s existing yaw and size bytes drive orientation and uniform height" % label, _source_rows_match(high, rows))
	_check("%s tier limits come from the selected quality table" % label,
		GrassQuality.enhanced() == expect_enhanced
		and _within_quality_limits(low, "low", expect_enhanced)
		and _within_quality_limits(balanced, "balanced", expect_enhanced)
		and _within_quality_limits(high, "high", expect_enhanced))


func _test_path_and_bank_exclusions(label: String, expect_enhanced: bool) -> void:
	var high := ImportedNearGrass.layout(_field, "high")
	if high.is_empty():
		_check("%s exclusion fixtures have an accepted source placement" % label, false)
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
	_check("%s worn scenery paths become grass exclusion polygons" % label, not path_exclusions.is_empty())
	_check("%s NearGrass.accepts rejects the path center" % label, not NearGrass.accepts(path_north, path_east, _field, path_exclusions))
	var after_path := ImportedNearGrass.layout(_field, "high", path_exclusions)
	_check("%s path-clipped layout replaces excluded rows within the active caps" % label,
		not _contains_row(after_path, int(path_target.row_index)) and _within_quality_limits(after_path, "high", expect_enhanced))
	_check("%s every emitted placement clears the path mask" % label, _all_outside(after_path, path_exclusions))

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
	_check("%s normalized lake bank becomes a grass exclusion polygon" % label, bank_exclusions.size() == 1)
	_check("%s NearGrass.accepts rejects the lake bank" % label, not NearGrass.accepts(bank_north, bank_east, _field, bank_exclusions))
	var after_bank := ImportedNearGrass.layout(_field, "high", bank_exclusions)
	_check("%s bank-clipped layout replaces excluded rows" % label, not _contains_row(after_bank, int(bank_target.row_index)))
	_check("%s every emitted placement clears the bank mask" % label, _all_outside(after_bank, bank_exclusions))


func _test_batched_source_build(label: String, expect_enhanced: bool) -> void:
	var expected := ImportedNearGrass.layout(_field, "high")
	var root := ImportedNearGrass.build(_field, "high")
	_check("%s runtime seam retains the NearGrass root name" % label, root.name == "NearGrass")
	_check("%s root declares downloaded source geometry" % label, bool(root.get_meta("imported", false)))
	_check("%s root keeps all CPU placements for diagnostics and integration" % label,
		(root.get_meta("cpu_placements", []) as Array).size() == expected.size()
		and (root.get_meta("placements", []) as Array).size() == expected.size())
	_check("%s metadata triangle count matches placements" % label, int(root.get_meta("source_triangles", -1)) == _triangle_count(expected)
		and int(root.get_meta("triangles", -1)) == _triangle_count(expected))
	_check("%s root contains at most three source asset batches" % label, int(root.get_meta("asset_batches", -1)) <= 3
		and int(root.get_meta("batches", -1)) <= 3
		and root.get_child_count() <= 3, "%d MultiMeshes" % root.get_child_count())
	_check("%s source clumps preserve proportions with uniform instance scale" % label, _uniform_scales_valid(root))
	_check("%s root uses only instanced source meshes" % label, _only_multimeshes(root) and _count_colliders(root) == 0)
	_check("%s batches retain instance colors and cast no shadows" % label, _color_data_and_shadows_off(root))
	_check("%s material route matches the environment switch" % label,
		GrassQuality.enhanced() == expect_enhanced and bool(root.has_meta("grass_wind")) == expect_enhanced)
	_check("%s source materials and complete surface geometry remain intact" % label,
		_matches_source_parts(root, expect_enhanced))
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
	return _within_quality_limits(placements, "high", GrassQuality.enhanced())


func _within_quality_limits(placements: Array[Dictionary], quality: String, enhanced: bool) -> bool:
	var counts := _asset_counts(placements)
	var quality_table: Dictionary = ImportedNearGrass.ENHANCED_QUALITY_LIMITS if enhanced else ImportedNearGrass.QUALITY_LIMITS
	var limits: Dictionary = quality_table.get(quality, {})
	for asset_id: String in ImportedNearGrass.ASSET_IDS:
		if int(counts.get(asset_id, 0)) > int(limits.get(asset_id, 0)):
			return false
	return true


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


func _matches_source_parts(root: Node, expect_enhanced: bool) -> bool:
	var shader: Shader = load("res://scenery/imported_grass.gdshader") as Shader if expect_enhanced else null
	if expect_enhanced and (shader == null or not shader.code.contains("render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;")):
		return false
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
		var effective_materials: Array = source_parts[part_index].get("materials", [])
		if source_mesh == null or runtime_mesh == null or source_mesh == runtime_mesh \
			or source_mesh.get_surface_count() != runtime_mesh.get_surface_count() \
			or effective_materials.size() != source_mesh.get_surface_count():
			return false
		for surface_index: int in range(source_mesh.get_surface_count()):
			var source_material := effective_materials[surface_index] as StandardMaterial3D
			var actual_material := runtime_mesh.surface_get_material(surface_index)
			if source_material == null:
				return false
			var source_arrays := source_mesh.surface_get_arrays(surface_index)
			var runtime_arrays := runtime_mesh.surface_get_arrays(surface_index)
			if source_arrays != runtime_arrays:
				return false
			if expect_enhanced:
				var runtime_material := actual_material as ShaderMaterial
				if runtime_material == null or runtime_material.shader != shader \
					or runtime_material.get_shader_parameter("albedo_texture") != source_material.albedo_texture \
					or bool(runtime_material.get_shader_parameter("use_vertex_color")) != source_material.vertex_color_use_as_albedo \
					or not _approximately_equal(runtime_material.get_shader_parameter("albedo_color"), source_material.albedo_color) \
					or not _approximately_equal(runtime_material.get_shader_parameter("uv1_scale"), Vector2(source_material.uv1_scale.x, source_material.uv1_scale.y)) \
					or not _approximately_equal(runtime_material.get_shader_parameter("uv1_offset"), Vector2(source_material.uv1_offset.x, source_material.uv1_offset.y)) \
					or not is_equal_approx(float(runtime_material.get_shader_parameter("roughness")), source_material.roughness) \
					or not is_equal_approx(float(runtime_material.get_shader_parameter("metallic")), source_material.metallic) \
					or not is_equal_approx(float(runtime_material.get_shader_parameter("specular")), source_material.metallic_specular):
					return false
			elif actual_material != source_material:
				return false
		seen[asset_id] = true
	return seen.size() == 3


func _approximately_equal(left: Variant, right: Variant) -> bool:
	if left is Color and right is Color:
		return is_equal_approx(left.r, right.r) and is_equal_approx(left.g, right.g) \
			and is_equal_approx(left.b, right.b) and is_equal_approx(left.a, right.a)
	if left is Vector2 and right is Vector2:
		return left.distance_to(right) < 0.0001
	return left == right


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
