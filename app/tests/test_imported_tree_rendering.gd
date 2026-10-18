extends SceneTree

const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const EXPECTED_TREE_LEAF_TEXTURES := {
	"common_tree_1": "Leaves_NormalTree_C.png",
	"common_tree_2": "Leaves_NormalTree_C.png",
	"common_tree_3": "Leaves_NormalTree_C.png",
	"common_tree_4": "Leaves_NormalTree_C.png",
	"pine_1": "Leaf_Pine_C.png",
	"pine_2": "Leaf_Pine_C.png",
	"pine_3": "Leaf_Pine_C.png",
}

var _failures := 0


func _initialize() -> void:
	ShaderClock.register()
	_test_opt_in_tree_cells_and_damage()
	_test_tree_wind_with_tree_cells()
	_test_wind_modes_and_material_preservation()
	_test_all_tree_sources_accept_tree_wind()
	_test_tree_wind_transform_guard()
	_test_invalid_cell_option_falls_back()
	if _failures == 0:
		print("imported tree rendering tests passed")
		quit(0)
	else:
		push_error("%d imported tree rendering test(s) failed" % _failures)
		quit(1)


func _test_opt_in_tree_cells_and_damage() -> void:
	var batches := _sample_batches()
	var legacy := ImportedVegetation.build(batches)
	var expected_tree_parts := ImportedVegetation.get_parts("common_tree_1").size()
	var expected_crop_parts := ImportedVegetation.get_parts("wheat_4").size()
	_check("default build keeps one flat batch per source part",
		legacy.get_child_count() == expected_tree_parts + expected_crop_parts)
	_check("default children remain flat MultiMesh instances", _all_children_are_flat_multimeshes(legacy))

	for candidate_size in [64, 128, 256]:
		var cell_root := ImportedVegetation.build(batches, false, {"tree_cell_size_m": candidate_size})
		var expected_cells := _expected_cell_count(batches["common_tree_1"], candidate_size)
		_check("%d m batching emits one batch per tree cell and source part" % candidate_size,
			cell_root.get_child_count() == expected_cells * expected_tree_parts + expected_crop_parts)
		_check("%d m batching preserves flat child traversal" % candidate_size,
			_all_children_are_flat_multimeshes(cell_root))
		_check("%d m batching preserves every tree transform" % candidate_size,
			_tree_transform_signatures(cell_root) == _tree_transform_signatures(legacy))
		var tint_match := _tree_state_tints_match_records(cell_root, batches["common_tree_1"], expected_tree_parts)
		var expected_damage_entries := _damage_record_count(batches["common_tree_1"]) * expected_tree_parts
		_check("%d m batching preserves tree tint records" % candidate_size, tint_match)
		_check("%d m batching preserves damage IDs and indices" % candidate_size,
			_tree_damage_entry_count(cell_root) == expected_damage_entries)
		cell_root.free()

	var damaged_root := ImportedVegetation.build(batches, false, {"tree_cell_size_m": 64})
	var before_hide := ImportedVegetation.bounds(damaged_root)
	_check("cell-batched tree damage ID hides all matching instances",
		ImportedVegetation.set_damage_hidden(damaged_root, "tree-cell-edge", true))
	var after_hide := ImportedVegetation.bounds(damaged_root)
	_check("cell-batched bounds exclude the damaged tree", after_hide.size.x < before_hide.size.x)
	_check("cell-batched tree damage ID restores all matching instances",
		ImportedVegetation.set_damage_hidden(damaged_root, "tree-cell-edge", false))
	var after_restore := ImportedVegetation.bounds(damaged_root)
	_check("cell-batched bounds restore after damage recovery",
		is_equal_approx(after_restore.position.x, before_hide.position.x)
		and is_equal_approx(after_restore.end.x, before_hide.end.x))
	legacy.free()
	damaged_root.free()


func _test_tree_wind_with_tree_cells() -> void:
	var batches := _sample_batches()
	var records: Array = batches["common_tree_1"]
	var parts := ImportedVegetation.get_parts("common_tree_1")
	var expected_tree_instances := records.size() * parts.size()
	var baseline := ImportedVegetation.build(batches, false, {
		"tree_wind": true,
		"tree_cell_size_m": 0,
	})
	# The Dummy headless renderer exposes no MultiMesh buffer; its branch checks grouped seed records and custom-data setup.
	# Native Compatibility validates the per-instance transforms, colors and phase stored in the renderer buffer.
	var phase_buffer_available := _tree_multimesh_buffers_available(baseline)
	_check("wind-only baseline keeps one tree state per source record and part",
		_tree_wind_state_matches_records(baseline, records, parts, 0, phase_buffer_available)
		and _tree_state_bounds_count(baseline, "common_tree_1") == expected_tree_instances)
	_check("wind-only baseline has complete expanded tree bounds",
		_tree_wind_cull_bounds_match_state(baseline, expected_tree_instances, 0))
	var baseline_tree_bounds := _tree_state_bounds(baseline, "common_tree_1")
	var baseline_all_bounds := ImportedVegetation.bounds(baseline)

	for candidate_size in [64, 128, 256]:
		var cell_root := ImportedVegetation.build(batches, false, {
			"tree_wind": true,
			"tree_cell_size_m": candidate_size,
		})
		var expected_cells := _expected_cell_count(records, candidate_size)
		var expected_tree_parts := parts.size()
		var crop_parts := ImportedVegetation.get_parts("wheat_4").size()
		_check("%d m wind batching keeps flat tree/crop children" % candidate_size,
			cell_root.get_child_count() == expected_cells * expected_tree_parts + crop_parts
			and _all_children_are_flat_multimeshes(cell_root))
		_check("%d m regrouping preserves each tree transform, tint and seed-derived wind phase" % candidate_size,
			_tree_wind_state_matches_records(cell_root, records, parts, candidate_size, phase_buffer_available))
		_check("%d m regrouping retains the same number of tree bounds" % candidate_size,
			_tree_state_bounds_count(cell_root, "common_tree_1") == expected_tree_instances)
		_check("%d m per-cell cull bounds cover all expanded tree instances" % candidate_size,
			_tree_wind_cull_bounds_match_state(cell_root, expected_tree_instances, candidate_size))
		_check("%d m regrouping preserves the complete expanded tree bounds" % candidate_size,
			_aabb_approx_equal(_tree_state_bounds(cell_root, "common_tree_1"), baseline_tree_bounds))
		_check("%d m regrouping preserves total imported vegetation bounds" % candidate_size,
			_aabb_approx_equal(ImportedVegetation.bounds(cell_root), baseline_all_bounds))

		var damage_entries := _damage_entries(cell_root, "tree-cell-edge")
		var before_hide_phase_state: Array[String] = []
		if phase_buffer_available:
			before_hide_phase_state = _tree_wind_phase_signatures(cell_root)
		var before_hide_tree_bounds := _tree_state_bounds(cell_root, "common_tree_1")
		_check("%d m wind batching has all source-part damage entries" % candidate_size,
			damage_entries.size() == _damage_record_count(records) * parts.size())
		_check("%d m wind tree damage hides every mapped instance" % candidate_size,
			ImportedVegetation.set_damage_hidden(cell_root, "tree-cell-edge", true)
			and _damage_instances_match_hidden_state(cell_root, "tree-cell-edge", true))
		_check("%d m wind tree damage removes the hidden tree from bounds" % candidate_size,
			_tree_state_bounds_count(cell_root, "common_tree_1") == expected_tree_instances - damage_entries.size()
			and not _aabb_approx_equal(_tree_state_bounds(cell_root, "common_tree_1"), before_hide_tree_bounds))
		_check("%d m wind tree damage restores every mapped instance" % candidate_size,
			ImportedVegetation.set_damage_hidden(cell_root, "tree-cell-edge", false)
			and _damage_instances_match_hidden_state(cell_root, "tree-cell-edge", false))
		_check("%d m wind damage restoration restores bounds and seed phases" % candidate_size,
			_tree_state_bounds_count(cell_root, "common_tree_1") == expected_tree_instances
			and _aabb_approx_equal(_tree_state_bounds(cell_root, "common_tree_1"), before_hide_tree_bounds)
			and _aabb_approx_equal(ImportedVegetation.bounds(cell_root), baseline_all_bounds)
			and (not phase_buffer_available
				or (_tree_wind_phase_signatures(cell_root) == before_hide_phase_state
					and _tree_wind_state_matches_records(cell_root, records, parts, candidate_size, true))))
		cell_root.free()
	baseline.free()


func _test_wind_modes_and_material_preservation() -> void:
	var batches := _sample_batches()
	var source_crop_parts := ImportedVegetation.get_parts("wheat_4")
	var tree_wind_root := ImportedVegetation.build(batches, false, {"tree_wind": true})
	var tree_mode_shader := load("res://scenery/imported_vegetation_wind.gdshader") as Shader
	var shader_text := FileAccess.get_file_as_string("res://scenery/imported_vegetation_wind.gdshader")
	_check("shared wind shader does not rely on unsupported per-instance uniforms",
		not shader_text.contains("instance uniform"))
	_check("tree wind applies the analytic inverse-transpose normal correction",
		shader_text.contains("source_normal.y - sway_gradient_y * dot(direction, source_normal.xz)"))
	_check("tree wind applies the analytic Jacobian to normal-map tangents",
		shader_text.contains("source_tangent.x + direction.x * sway_gradient_y * source_tangent.y")
		and shader_text.contains("source_binormal.z + direction.y * sway_gradient_y * source_binormal.y"))
	_check("zero tree-wind gradient preserves the source normal frame exactly",
		shader_text.contains("if (sway_gradient_y != 0.0)"))
	var checked_tree := false
	var checked_crop := false
	var saw_tree_shader := false
	var saw_tree_source_material := false
	var saw_tree_normal_map := false
	for child in tree_wind_root.get_children():
		var instance := child as MultiMeshInstance3D
		var asset_id := str(instance.name).get_slice("_Part_", 0)
		if asset_id == "common_tree_1":
			checked_tree = true
			_check("tree opt-in child is marked separately from legacy wind",
				bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false))
				and not bool(instance.get_meta("_imported_vegetation_wind_enabled", false)))
			var draw_mesh := instance.multimesh.mesh
			var parts := ImportedVegetation.get_parts("common_tree_1")
			var part_index := int(str(instance.name).get_slice("_Part_", 1).get_slice("_", 0))
			var source_materials: Array = parts[part_index].get("materials", [])
			for surface_index in range(draw_mesh.get_surface_count()):
				var output_material := draw_mesh.surface_get_material(surface_index)
				if output_material is ShaderMaterial:
					saw_tree_shader = true
					var shader_material := output_material as ShaderMaterial
					var source_material := source_materials[surface_index] as BaseMaterial3D
					_check("tree wind material uses the compatibility-safe shader",
						shader_material.shader == tree_mode_shader
						and bool(shader_material.get_shader_parameter("tree_wind_mode")))
					_check("tree wind preserves source color and texture",
						shader_material.get_shader_parameter("albedo_color") == source_material.albedo_color
						and shader_material.get_shader_parameter("albedo_texture") == source_material.albedo_texture)
					_check("tree wind preserves source UV, roughness, metallic and specular values",
						shader_material.get_shader_parameter("uv1_scale") == Vector2(source_material.uv1_scale.x, source_material.uv1_scale.y)
						and shader_material.get_shader_parameter("uv1_offset") == Vector2(source_material.uv1_offset.x, source_material.uv1_offset.y)
						and is_equal_approx(float(shader_material.get_shader_parameter("roughness")), source_material.roughness)
						and is_equal_approx(float(shader_material.get_shader_parameter("metallic")), source_material.metallic)
						and is_equal_approx(float(shader_material.get_shader_parameter("specular")), source_material.metallic_specular))
					_check("tree wind preserves source normal-map and alpha-scissor settings",
						bool(shader_material.get_shader_parameter("use_normal_texture"))
							== (source_material.normal_enabled and source_material.normal_texture != null)
						and bool(shader_material.get_shader_parameter("use_alpha_scissor"))
							== (source_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
						and is_equal_approx(float(shader_material.get_shader_parameter("alpha_scissor_threshold")),
							source_material.alpha_scissor_threshold))
					saw_tree_normal_map = saw_tree_normal_map or bool(shader_material.get_shader_parameter("use_normal_texture"))
					_check("tree wind keeps per-part height coordinates",
						is_equal_approx(float(shader_material.get_shader_parameter("plant_height")),
							float(parts[part_index].get("bounds", AABB()).size.y)))
				else:
					saw_tree_source_material = true
					_check("unsupported tree material fails closed without replacement",
						output_material == source_materials[surface_index])
			if instance.multimesh.mesh.surface_get_material(0) is ShaderMaterial:
				var tree_aabb: AABB = instance.custom_aabb
				_check("tree wind custom cull bounds are explicit and nonempty",
					tree_aabb.size.length_squared() > 0.0)
		elif asset_id == "wheat_4":
			checked_crop = true
			_check("tree-only wind leaves crop batch static",
				not bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false))
				and not bool(instance.get_meta("_imported_vegetation_wind_enabled", false)))
			var crop_materials: Array = source_crop_parts[0].get("materials", [])
			for surface_index in range(instance.multimesh.mesh.get_surface_count()):
				_check("tree-only wind retains crop source materials",
					instance.multimesh.mesh.surface_get_material(surface_index) == crop_materials[surface_index])
	_check("tree-only wind build includes a tree batch", checked_tree)
	_check("tree-only wind build includes a non-tree control batch", checked_crop)
	if saw_tree_shader:
		_check("tree wind enables imported tangent-space bark normal maps",
			saw_tree_normal_map)
	_check("tree asset is either wholly converted or wholly fail-closed",
		not (saw_tree_shader and saw_tree_source_material))
	if saw_tree_shader:
		var static_tree_root := ImportedVegetation.build(batches)
		var static_bounds := ImportedVegetation.bounds(static_tree_root)
		var wind_bounds := ImportedVegetation.bounds(tree_wind_root)
		_check("tree wind expands transformed root bounds for shader sway",
			wind_bounds.size.x > static_bounds.size.x and wind_bounds.size.z > static_bounds.size.z)
		ImportedVegetation.set_wind(tree_wind_root, 10.0, Vector2(0.0, 1.0))
		var clamped_strength := -1.0
		for child in tree_wind_root.get_children():
			var instance := child as MultiMeshInstance3D
			if bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false)):
				var material := instance.multimesh.mesh.surface_get_material(0) as ShaderMaterial
				clamped_strength = float(material.get_shader_parameter("wind_strength"))
				break
		_check("tree wind setter caps displacement to its bounded maximum",
			clamped_strength >= 0.0 and clamped_strength <= 0.025)
		static_tree_root.free()
	var legacy_wind_root := ImportedVegetation.build(batches, true)
	var checked_legacy_roles := {"common_tree_1": false, "wheat_4": false}
	var legacy_wind_strengths: Dictionary = {}
	for child in legacy_wind_root.get_children():
		var instance := child as MultiMeshInstance3D
		var asset_id := str(instance.name).get_slice("_Part_", 0)
		if asset_id in checked_legacy_roles:
			var output_material := instance.multimesh.mesh.surface_get_material(0)
			checked_legacy_roles[asset_id] = output_material is ShaderMaterial
			if output_material is ShaderMaterial:
				legacy_wind_strengths[asset_id] = float((output_material as ShaderMaterial).get_shader_parameter("wind_strength"))
			_check("legacy enable_wind still covers role %s" % asset_id,
				bool(checked_legacy_roles[asset_id]))
	_check("legacy role-specific wind defaults remain unchanged",
		is_equal_approx(float(legacy_wind_strengths.get("common_tree_1", -1.0)), 0.01)
		and is_equal_approx(float(legacy_wind_strengths.get("wheat_4", -1.0)), 0.0375))
	ImportedVegetation.set_wind(legacy_wind_root, 0.0)
	_check("legacy enable_wind remains all-role",
		bool(checked_legacy_roles["common_tree_1"]) and bool(checked_legacy_roles["wheat_4"]))
	_check("legacy set_wind updates all role materials",
		_legacy_wind_materials_have_strength(legacy_wind_root, 0.0))
	tree_wind_root.free()
	legacy_wind_root.free()


func _test_tree_wind_transform_guard() -> void:
	var parts := ImportedVegetation.get_parts("common_tree_1")
	var separate_crown: Array[Dictionary] = [parts[0], parts[0]]
	_check("separate source crown and stem parts retain source materials until a shared bend frame is qualified",
		not ImportedVegetation._tree_asset_wind_supported("multipart-fixture", separate_crown, []))
	var yaw := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.0, 0.0, -2.0))
	var tilt := Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3.ZERO)
	var nonuniform := Transform3D(Basis.from_scale(Vector3(1.0, 1.1, 1.0)), Vector3.ZERO)
	_check("tree wind accepts upright yaw and uniform scale transforms",
		ImportedVegetation._tree_wind_transform_support_reason(yaw) == "")
	_check("tree wind rejects source or placement pitch and roll",
		not ImportedVegetation._tree_wind_transform_support_reason(tilt).is_empty())
	_check("tree wind rejects non-uniform source or placement scale",
		not ImportedVegetation._tree_wind_transform_support_reason(nonuniform).is_empty())
	var batches: Dictionary = {}
	ImportedVegetation.queue(batches, "common_tree_1", tilt, 17)
	var guarded_root := ImportedVegetation.build(batches, false, {"tree_wind": true})
	_check("tilted tree batches fail closed to source materials",
		_not_tree_wind_enabled(guarded_root))
	guarded_root.free()


func _test_all_tree_sources_accept_tree_wind() -> void:
	var actual_tree_ids: Array[String] = []
	for asset_value: Dictionary in ImportedVegetation.catalog().get("assets", []):
		if str(asset_value.get("role", "")) == "tree":
			actual_tree_ids.append(str(asset_value.get("id", "")))
	actual_tree_ids.sort()
	var expected_tree_ids: Array[String] = []
	for asset_id: String in EXPECTED_TREE_LEAF_TEXTURES:
		expected_tree_ids.append(asset_id)
	expected_tree_ids.sort()
	_check("tree-wind source fixture covers all seven retained tree forms",
		actual_tree_ids == expected_tree_ids)

	var batches: Dictionary = {}
	var expected_surfaces := 0
	for index in range(expected_tree_ids.size()):
		var asset_id := expected_tree_ids[index]
		var parts := ImportedVegetation.get_parts(asset_id)
		_check("%s has imported parts for tree-wind coverage" % asset_id, not parts.is_empty())
		for part: Dictionary in parts:
			var mesh: Mesh = part.get("mesh")
			if mesh != null:
				expected_surfaces += mesh.get_surface_count()
		var placement := Transform3D(
			Basis(Vector3.UP, float(index) * 0.19),
			Vector3(float(index) * 12.0, 0.0, float(index % 2) * 6.0)
		)
		_check("%s queues as a retained source ID" % asset_id,
			ImportedVegetation.queue(batches, asset_id, placement, 100 + index) == asset_id)

	var wind_root := ImportedVegetation.build(batches, false, {
		"tree_wind": true,
		"tree_cell_size_m": 0,
	})
	var seen_tree_ids: Dictionary = {}
	var converted_surface_counts: Dictionary = {}
	var accepted_all := true
	var converted_surfaces := 0
	for child in wind_root.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var instance := child as MultiMeshInstance3D
		var asset_id := str(instance.name).get_slice("_Part_", 0)
		if not EXPECTED_TREE_LEAF_TEXTURES.has(asset_id):
			continue
		seen_tree_ids[asset_id] = true
		_check("%s instance opts into tree-only wind" % asset_id,
			bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false))
			and not bool(instance.get_meta("_imported_vegetation_wind_enabled", false)))
		var part_suffix := str(instance.name).get_slice("_Part_", 1)
		var part_index := int(part_suffix.get_slice("_", 0))
		var source_parts := ImportedVegetation.get_parts(asset_id)
		if part_index < 0 or part_index >= source_parts.size():
			accepted_all = false
			_check("%s output part index maps to a source part" % asset_id, false)
			continue
		var source_materials: Array = source_parts[part_index].get("materials", [])
		var draw_mesh: Mesh = instance.multimesh.mesh
		_check("%s wind mesh retains its imported surface count" % asset_id,
			draw_mesh.get_surface_count() == source_materials.size())
		for surface_index in range(mini(draw_mesh.get_surface_count(), source_materials.size())):
			var source_value: Variant = source_materials[surface_index]
			var output_material := draw_mesh.surface_get_material(surface_index)
			if not source_value is BaseMaterial3D or not output_material is ShaderMaterial:
				accepted_all = false
				_check("%s surface %d is accepted for opt-in tree wind" % [asset_id, surface_index], false)
				continue
			var source_material := source_value as BaseMaterial3D
			var wind_material := output_material as ShaderMaterial
			converted_surfaces += 1
			converted_surface_counts[asset_id] = int(converted_surface_counts.get(asset_id, 0)) + 1
			_check("%s surface %d uses tree-wind mode" % [asset_id, surface_index],
				bool(wind_material.get_shader_parameter("tree_wind_mode")))
			_check("%s surface %d preserves imported albedo features" % [asset_id, surface_index],
				wind_material.get_shader_parameter("albedo_texture") == source_material.albedo_texture
				and bool(wind_material.get_shader_parameter("use_albedo_texture")) == (source_material.albedo_texture != null)
				and wind_material.get_shader_parameter("albedo_color") == source_material.albedo_color)
			var albedo_name := _texture_filename(source_material.albedo_texture)
			if albedo_name == "Bark_NormalTree.png":
				_check("%s bark keeps its source normal map and alpha scissor" % asset_id,
					source_material.normal_enabled
					and _texture_filename(source_material.normal_texture) == "Bark_NormalTree_Normal.png"
					and bool(wind_material.get_shader_parameter("use_normal_texture"))
					and wind_material.get_shader_parameter("normal_texture") == source_material.normal_texture
					and source_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					and bool(wind_material.get_shader_parameter("use_alpha_scissor"))
					and is_equal_approx(float(wind_material.get_shader_parameter("alpha_scissor_threshold")),
						source_material.alpha_scissor_threshold))
			elif albedo_name == str(EXPECTED_TREE_LEAF_TEXTURES[asset_id]):
				_check("%s foliage keeps its expected source atlas and alpha scissor" % asset_id,
					(not source_material.normal_enabled or source_material.normal_texture == null)
					and not bool(wind_material.get_shader_parameter("use_normal_texture"))
					and source_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					and bool(wind_material.get_shader_parameter("use_alpha_scissor"))
					and is_equal_approx(float(wind_material.get_shader_parameter("alpha_scissor_threshold")),
						source_material.alpha_scissor_threshold))
			else:
				accepted_all = false
				_check("%s surface %d has its expected bark or foliage atlas (texture=%s)" % [
					asset_id, surface_index, albedo_name,
				], false)
	_check("tree-wind conversion covers every retained source tree", seen_tree_ids.size() == 7 and accepted_all)
	_check("tree-wind converts every source surface", converted_surfaces == expected_surfaces)
	for asset_id: String in expected_tree_ids:
		var source_surfaces := 0
		for part: Dictionary in ImportedVegetation.get_parts(asset_id):
			var mesh: Mesh = part.get("mesh")
			if mesh != null:
				source_surfaces += mesh.get_surface_count()
		_check("%s converts every bark and foliage surface" % asset_id,
			int(converted_surface_counts.get(asset_id, 0)) == source_surfaces)
	wind_root.free()


func _test_invalid_cell_option_falls_back() -> void:
	var batches := _sample_batches()
	var legacy := ImportedVegetation.build(batches)
	var explicit_disabled := ImportedVegetation.build(batches, false, {"tree_cell_size_m": 0})
	_check("explicit zero cell size is accepted without an option warning",
		not ImportedVegetation._option_warnings.has("tree_cell_size_m_range"))
	var invalid_a := ImportedVegetation.build(batches, false, {"tree_cell_size_m": 32})
	var invalid_b := ImportedVegetation.build(batches, false, {"tree_cell_size_m": 32})
	var invalid_wind_a := ImportedVegetation.build(batches, false, {"tree_wind": "true"})
	var invalid_wind_b := ImportedVegetation.build(batches, false, {"tree_wind": "true"})
	_check("unsupported cell sizes fail back to legacy grouping",
		invalid_a.get_child_count() == legacy.get_child_count()
		and invalid_b.get_child_count() == legacy.get_child_count())
	_check("explicit zero cell size disables batching without changing legacy grouping",
		explicit_disabled.get_child_count() == legacy.get_child_count()
		and _tree_transform_signatures(explicit_disabled) == _tree_transform_signatures(legacy))
	_check("unsupported cell fallback preserves transforms",
		_tree_transform_signatures(invalid_a) == _tree_transform_signatures(legacy))
	_check("non-boolean tree wind options fail closed without enabling wind",
		_not_tree_wind_enabled(invalid_wind_a) and _not_tree_wind_enabled(invalid_wind_b))
	legacy.free()
	explicit_disabled.free()
	invalid_a.free()
	invalid_b.free()
	invalid_wind_a.free()
	invalid_wind_b.free()


func _sample_batches() -> Dictionary:
	var batches: Dictionary = {}
	var positions := [
		Vector3(-0.01, 0.0, 0.0),
		Vector3(0.01, 0.0, 0.0),
		Vector3(63.99, 0.0, 0.0),
		Vector3(64.0, 0.0, 0.0),
		Vector3(128.0, 0.0, 0.0),
	]
	for index in range(positions.size()):
		var rotation := Basis(Vector3.UP, 0.11 * float(index))
		var scale := Basis.from_scale(Vector3.ONE * (1.0 + 0.1 * float(index)))
		var transform := Transform3D(rotation * scale, positions[index])
		var damage_id := "tree-cell-edge" if index == positions.size() - 1 else ""
		ImportedVegetation.queue(batches, "common_tree_1", transform, index + 10, damage_id,
			Color(0.9 + 0.02 * float(index), 0.93, 0.96, 1.0))
	ImportedVegetation.queue(batches, "wheat_4", Transform3D(Basis.IDENTITY, Vector3(9.0, 0.0, 9.0)), 5)
	return batches


func _expected_cell_count(records: Array, cell_size: int) -> int:
	var cells: Dictionary = {}
	for value in records:
		var transform: Transform3D = value.get("transform", Transform3D.IDENTITY)
		var cell := Vector2i(floori(transform.origin.x / cell_size), floori(transform.origin.z / cell_size))
		cells[cell] = true
	return cells.size()


func _tree_transform_signatures(root: Node3D) -> Array[String]:
	var signatures: Array[String] = []
	for child in root.get_children():
		var instance := child as MultiMeshInstance3D
		if not str(instance.name).begins_with("common_tree_1_"):
			continue
		for index in range(instance.multimesh.instance_count):
			var transform := instance.multimesh.get_instance_transform(index)
			signatures.append("%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f" % [
				transform.origin.x, transform.origin.y, transform.origin.z,
				transform.basis.x.x, transform.basis.x.y, transform.basis.x.z,
				transform.basis.y.x, transform.basis.y.y, transform.basis.y.z,
				transform.basis.z.x, transform.basis.z.y, transform.basis.z.z,
			])
	signatures.sort()
	return signatures


func _tree_wind_phase_signatures(root: Node3D) -> Array[String]:
	var signatures: Array[String] = []
	for child in root.get_children():
		var instance := child as MultiMeshInstance3D
		if not str(instance.name).begins_with("common_tree_1_"):
			continue
		for index in range(instance.multimesh.instance_count):
			var transform := instance.multimesh.get_instance_transform(index)
			var phase_state := instance.multimesh.get_instance_custom_data(index)
			var tint := instance.multimesh.get_instance_color(index)
			signatures.append(_transform_phase_signature(transform, phase_state.r, tint))
	signatures.sort()
	return signatures


func _tree_wind_phase_signatures_from_records(records: Array, parts: Array[Dictionary]) -> Array[String]:
	var signatures: Array[String] = []
	for record: Dictionary in records:
		var plant_transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
		var seed_value := float(record.get("seed", 0))
		var phase := fposmod(seed_value * 0.61803398875, 1.0)
		var tint: Color = record.get("tint", Color.WHITE)
		for part: Dictionary in parts:
			var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
			signatures.append(_transform_phase_signature(plant_transform * part_transform, phase, tint))
	signatures.sort()
	return signatures


func _transform_phase_signature(transform: Transform3D, phase: float, tint: Color) -> String:
	return "%.5f,%.5f,%.5f|%.5f,%.5f,%.5f|%.5f,%.5f,%.5f|%.5f,%.5f,%.5f|%.3f|%.3f,%.3f,%.3f,%.3f" % [
		transform.origin.x, transform.origin.y, transform.origin.z,
		transform.basis.x.x, transform.basis.x.y, transform.basis.x.z,
		transform.basis.y.x, transform.basis.y.y, transform.basis.y.z,
		transform.basis.z.x, transform.basis.z.y, transform.basis.z.z,
		phase, tint.r, tint.g, tint.b, tint.a,
	]


func _tree_wind_cull_bounds_match_state(root: Node3D, expected_instance_count: int, cell_size: int) -> bool:
	if _tree_state_bounds_count(root, "common_tree_1") != expected_instance_count:
		return false
	var has_cull_bounds := false
	var cull_bounds := AABB()
	var expected_cells: Dictionary = {}
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	for record: Dictionary in state.get("bounds", []):
		if str(record.get("asset_id", "")) != "common_tree_1" or bool(record.get("hidden", false)):
			continue
		var transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
		var cell := Vector2i.ZERO
		if cell_size > 0:
			cell = Vector2i(
				floori(transform.origin.x / float(cell_size)),
				floori(transform.origin.z / float(cell_size))
			)
		var key := "all" if cell_size == 0 else "%d_%d" % [cell.x, cell.y]
		var transformed_bounds := ImportedVegetation._transform_aabb(record.get("bounds", AABB()), transform)
		if not expected_cells.has(key):
			expected_cells[key] = {"bounds": transformed_bounds, "count": 1}
		else:
			var cell_record: Dictionary = expected_cells[key]
			cell_record["bounds"] = (cell_record["bounds"] as AABB).merge(transformed_bounds)
			cell_record["count"] = int(cell_record["count"]) + 1
			expected_cells[key] = cell_record
	var seen_cells: Dictionary = {}
	for child in root.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var instance := child as MultiMeshInstance3D
		if not bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false)):
			continue
		if instance.multimesh == null or instance.multimesh.mesh == null:
			return false
		var key := "all"
		if cell_size > 0:
			var cell_value := str(instance.name).get_slice("_Cell_", 1)
			if cell_value.is_empty():
				return false
			key = "%s_%s" % [cell_value.get_slice("_", 0), cell_value.get_slice("_", 1)]
		if not expected_cells.has(key) or seen_cells.has(key):
			return false
		var expected_cell: Dictionary = expected_cells[key]
		var child_bounds: AABB = instance.custom_aabb
		if int(expected_cell.get("count", 0)) != instance.multimesh.instance_count \
			or not _aabb_approx_equal(child_bounds, expected_cell.get("bounds", AABB())) \
			or not _aabb_approx_equal(instance.multimesh.custom_aabb, child_bounds):
			return false
		seen_cells[key] = true
		if not has_cull_bounds:
			cull_bounds = child_bounds
			has_cull_bounds = true
		else:
			cull_bounds = cull_bounds.merge(child_bounds)
	return has_cull_bounds and seen_cells.size() == expected_cells.size() and _aabb_approx_equal(
		cull_bounds,
		_tree_state_bounds(root, "common_tree_1")
	)


func _tree_state_bounds_count(root: Node3D, asset_id: String) -> int:
	var count := 0
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	for record: Dictionary in state.get("bounds", []):
		if str(record.get("asset_id", "")) == asset_id and not bool(record.get("hidden", false)):
			count += 1
	return count


func _tree_state_bounds(root: Node3D, asset_id: String) -> AABB:
	var have_bounds := false
	var result := AABB()
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	for record: Dictionary in state.get("bounds", []):
		if str(record.get("asset_id", "")) != asset_id or bool(record.get("hidden", false)):
			continue
		var local_bounds: AABB = record.get("bounds", AABB())
		var transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
		var world_bounds := ImportedVegetation._transform_aabb(local_bounds, transform)
		if not have_bounds:
			result = world_bounds
			have_bounds = true
		else:
			result = result.merge(world_bounds)
	return result if have_bounds else AABB()


func _damage_entries(root: Node3D, damage_id: String) -> Array:
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	var damage: Dictionary = state.get("damage", {})
	return damage.get(damage_id, [])


func _damage_instances_match_hidden_state(root: Node3D, damage_id: String, hidden: bool) -> bool:
	var entries := _damage_entries(root, damage_id)
	if entries.is_empty():
		return false
	var zero_transform := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	var bounds_records: Array = state.get("bounds", [])
	for item: Dictionary in entries:
		var multimesh: MultiMesh = item.get("multimesh")
		var index := int(item.get("index", -1))
		if multimesh == null or index < 0 or index >= multimesh.instance_count:
			return false
		if _multimesh_buffer_available(multimesh):
			var actual := multimesh.get_instance_transform(index)
			var expected: Transform3D = zero_transform if hidden else item.get("transform", Transform3D.IDENTITY)
			if not actual.is_equal_approx(expected):
				return false
		var bounds_index := int(item.get("bounds_index", -1))
		if bounds_index < 0 or bounds_index >= bounds_records.size():
			return false
		if bool(bounds_records[bounds_index].get("hidden", false)) != hidden:
			return false
	return true


func _tree_multimesh_buffers_available(root: Node3D) -> bool:
	var found_tree := false
	for child in root.get_children():
		if not child is MultiMeshInstance3D or not str(child.name).begins_with("common_tree_1_"):
			continue
		found_tree = true
		if not _multimesh_buffer_available((child as MultiMeshInstance3D).multimesh):
			return false
	return found_tree


func _multimesh_buffer_available(multimesh: MultiMesh) -> bool:
	if multimesh == null:
		return false
	var expected_values := multimesh.instance_count * 12
	if multimesh.use_colors:
		expected_values += multimesh.instance_count * 4
	if multimesh.use_custom_data:
		expected_values += multimesh.instance_count * 4
	return multimesh.buffer.size() == expected_values


func _tree_wind_state_matches_records(
	root: Node3D,
	records: Array,
	parts: Array[Dictionary],
	cell_size: int,
	phase_buffer_available: bool
) -> bool:
	if phase_buffer_available:
		return _tree_wind_phase_signatures(root) == _tree_wind_phase_signatures_from_records(records, parts)
	return _tree_wind_groups_preserve_records(root, records, parts, cell_size)


func _tree_wind_groups_preserve_records(
	root: Node3D,
	records: Array,
	parts: Array[Dictionary],
	cell_size: int
) -> bool:
	var expected_counts: Dictionary = {}
	var expected_phase_signatures := _tree_wind_phase_signatures_from_records(records, parts)
	if expected_phase_signatures.size() != records.size() * parts.size():
		return false
	var grouped_phase_signatures: Array[String] = []
	for group: Dictionary in ImportedVegetation._record_groups(records, cell_size):
		var group_records: Array = group.get("records", [])
		var cell: Vector2i = group.get("cell", Vector2i.ZERO)
		var key := "all" if cell_size == 0 else "%d_%d" % [cell.x, cell.y]
		expected_counts[key] = group_records.size() * parts.size()
		grouped_phase_signatures.append_array(_tree_wind_phase_signatures_from_records(group_records, parts))
	grouped_phase_signatures.sort()
	if grouped_phase_signatures != expected_phase_signatures:
		return false
	var seen: Dictionary = {}
	for child in root.get_children():
		if not child is MultiMeshInstance3D or not str(child.name).begins_with("common_tree_1_"):
			continue
		var instance := child as MultiMeshInstance3D
		var key := "all"
		if cell_size > 0:
			var cell_value := str(instance.name).get_slice("_Cell_", 1)
			if cell_value.is_empty():
				return false
			key = "%s_%s" % [cell_value.get_slice("_", 0), cell_value.get_slice("_", 1)]
		if not expected_counts.has(key) or seen.has(key):
			return false
		if instance.multimesh.instance_count != int(expected_counts[key]) or not instance.multimesh.use_custom_data:
			return false
		seen[key] = true
	return seen.size() == expected_counts.size()


func _aabb_approx_equal(left: AABB, right: AABB) -> bool:
	return left.position.is_equal_approx(right.position) and left.size.is_equal_approx(right.size)


func _tree_state_tints_match_records(root: Node3D, records: Array, part_count: int) -> bool:
	var expected: Dictionary = {}
	for record: Dictionary in records:
		var tint: Color = record.get("tint", Color.WHITE)
		var key := _color_key(tint)
		expected[key] = int(expected.get(key, 0)) + part_count
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	for record: Dictionary in state.get("bounds", []):
		if str(record.get("asset_id", "")) != "common_tree_1":
			continue
		var key := _color_key(record.get("tint", Color.WHITE))
		if not expected.has(key) or int(expected[key]) <= 0:
			return false
		expected[key] = int(expected[key]) - 1
	for remaining in expected.values():
		if int(remaining) != 0:
			return false
	return true


func _tree_damage_entry_count(root: Node3D) -> int:
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	return (state.get("damage", {}).get("tree-cell-edge", []) as Array).size()


func _damage_record_count(records: Array) -> int:
	var count := 0
	for record: Dictionary in records:
		if str(record.get("damage_id", "")) == "tree-cell-edge":
			count += 1
	return count


func _color_key(color: Color) -> String:
	return "%.4f,%.4f,%.4f,%.4f" % [color.r, color.g, color.b, color.a]


func _all_children_are_flat_multimeshes(root: Node3D) -> bool:
	for child in root.get_children():
		if not child is MultiMeshInstance3D or child.get_child_count() != 0:
			return false
	return true


func _not_tree_wind_enabled(root: Node3D) -> bool:
	for child in root.get_children():
		if bool(child.get_meta("_imported_vegetation_tree_wind_enabled", false)):
			return false
	return true


func _legacy_wind_materials_have_strength(root: Node3D, expected: float) -> bool:
	for child in root.get_children():
		if not bool(child.get_meta("_imported_vegetation_wind_enabled", false)):
			continue
		var instance := child as MultiMeshInstance3D
		for surface_index in range(instance.multimesh.mesh.get_surface_count()):
			var material := instance.multimesh.mesh.surface_get_material(surface_index)
			if not material is ShaderMaterial or not is_equal_approx(
				float((material as ShaderMaterial).get_shader_parameter("wind_strength")), expected):
				return false
	return true


func _texture_filename(texture: Texture2D) -> String:
	return texture.resource_path.get_file() if texture != null else ""


func _check(label: String, condition: bool) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % label)
