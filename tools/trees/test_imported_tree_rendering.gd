extends SceneTree

const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")

var _failures := 0


func _initialize() -> void:
	_test_opt_in_tree_cells_and_damage()
	_test_wind_modes_and_material_preservation()
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


func _test_wind_modes_and_material_preservation() -> void:
	var batches := _sample_batches()
	var source_crop_parts := ImportedVegetation.get_parts("wheat_4")
	var tree_wind_root := ImportedVegetation.build(batches, false, {"tree_wind": true})
	var tree_mode_shader := load("res://scenery/imported_vegetation_wind.gdshader") as Shader
	var shader_text := FileAccess.get_file_as_string("res://scenery/imported_vegetation_wind.gdshader")
	_check("shared wind shader does not rely on unsupported per-instance uniforms",
		not shader_text.contains("instance uniform"))
	var checked_tree := false
	var checked_crop := false
	var saw_tree_shader := false
	var saw_tree_source_material := false
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
	for child in legacy_wind_root.get_children():
		var instance := child as MultiMeshInstance3D
		var asset_id := str(instance.name).get_slice("_Part_", 0)
		if asset_id in checked_legacy_roles:
			checked_legacy_roles[asset_id] = instance.multimesh.mesh.surface_get_material(0) is ShaderMaterial
			_check("legacy enable_wind still covers role %s" % asset_id,
				bool(checked_legacy_roles[asset_id]))
	ImportedVegetation.set_wind(legacy_wind_root, 0.0)
	_check("legacy enable_wind remains all-role",
		bool(checked_legacy_roles["common_tree_1"]) and bool(checked_legacy_roles["wheat_4"]))
	tree_wind_root.free()
	legacy_wind_root.free()


func _test_invalid_cell_option_falls_back() -> void:
	var batches := _sample_batches()
	var legacy := ImportedVegetation.build(batches)
	var invalid_a := ImportedVegetation.build(batches, false, {"tree_cell_size_m": 32})
	var invalid_b := ImportedVegetation.build(batches, false, {"tree_cell_size_m": 32})
	var invalid_wind_a := ImportedVegetation.build(batches, false, {"tree_wind": "true"})
	var invalid_wind_b := ImportedVegetation.build(batches, false, {"tree_wind": "true"})
	_check("unsupported cell sizes fail back to legacy grouping",
		invalid_a.get_child_count() == legacy.get_child_count()
		and invalid_b.get_child_count() == legacy.get_child_count())
	_check("unsupported cell fallback preserves transforms",
		_tree_transform_signatures(invalid_a) == _tree_transform_signatures(legacy))
	_check("non-boolean tree wind options fail closed without enabling wind",
		_not_tree_wind_enabled(invalid_wind_a) and _not_tree_wind_enabled(invalid_wind_b))
	legacy.free()
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


func _check(label: String, condition: bool) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % label)
