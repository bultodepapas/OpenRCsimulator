extends SceneTree

const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const VegetationPlacement := preload("res://scenery/vegetation_placement.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const EXPECTED_TREE_LEAF_TEXTURES := {
	"common_tree_1": "Leaves_NormalTree_C.png",
	"common_tree_2": "Leaves_NormalTree_C.png",
	"common_tree_3": "Leaves_NormalTree_C.png",
	"common_tree_4": "Leaves_NormalTree_C.png",
	"pine_1": "Leaf_Pine_C.png",
	"pine_2": "Leaf_Pine_C.png",
	"pine_3": "Leaf_Pine_C.png",
}
const EXPECTED_MAPLE_TEXTURES := [
	"maple_bark_basecolor.jpg",
	"maple_bark_normal.png",
	"maple_bark_ao-maple_bark_roughness.png",
	"maple_leaves_basecolor.png",
	"maple_leaves_normal.png",
	"maple_leaves_ao-maple_leaves_roughness.png",
]

# L15b-R2 qualifies only trees with a measured collision-bounded sway limit.
const TREE_SAMPLE_ID := "landscapelab_quercus"
const TREE_SAMPLE_PREFIX := TREE_SAMPLE_ID + "_"
const FIELD_CARD_LEAN_M := 0.24 # render/tree_wind.gdshaderinc TREE_WIND_LEAN_M
const TREE_WIND_SHADERS := {
	"double_repeat": "res://scenery/imported_tree_wind.gdshader",
	"back_repeat": "res://scenery/imported_tree_wind_cull_back.gdshader",
	"double_clamp": "res://scenery/imported_tree_wind_clamp.gdshader",
}

var _failures := 0


func _initialize() -> void:
	ShaderClock.register()
	_test_tree_texture_imports()
	_test_opt_in_tree_cells_and_damage()
	_test_tree_wind_with_tree_cells()
	_test_wind_modes_and_material_preservation()
	_test_tree_wind_qualification()
	_test_tree_wind_stays_inside_collision_proxies()
	_test_world_lod_keeps_foliage()
	_test_maple_source_materials()
	_test_oak_blend_fails_closed_to_static_source_material()
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
	var expected_tree_parts := ImportedVegetation.get_parts(TREE_SAMPLE_ID).size()
	var expected_crop_parts := ImportedVegetation.get_parts("wheat_4").size()
	_check("default build keeps one flat batch per source part",
		legacy.get_child_count() == expected_tree_parts + expected_crop_parts)
	_check("default children remain flat MultiMesh instances", _all_children_are_flat_multimeshes(legacy))

	for candidate_size in [64, 128, 256]:
		var cell_root := ImportedVegetation.build(batches, false, {"tree_cell_size_m": candidate_size})
		var expected_cells := _expected_cell_count(batches[TREE_SAMPLE_ID], candidate_size)
		_check("%d m batching emits one batch per tree cell and source part" % candidate_size,
			cell_root.get_child_count() == expected_cells * expected_tree_parts + expected_crop_parts)
		_check("%d m batching preserves flat child traversal" % candidate_size,
			_all_children_are_flat_multimeshes(cell_root))
		_check("%d m batching preserves every tree transform" % candidate_size,
			_tree_transform_signatures(cell_root) == _tree_transform_signatures(legacy))
		var tint_match := _tree_state_tints_match_records(cell_root, batches[TREE_SAMPLE_ID], expected_tree_parts)
		var expected_damage_entries := _damage_record_count(batches[TREE_SAMPLE_ID]) * expected_tree_parts
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
	var records: Array = batches[TREE_SAMPLE_ID]
	var parts := ImportedVegetation.get_parts(TREE_SAMPLE_ID)
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
		and _tree_state_bounds_count(baseline, TREE_SAMPLE_ID) == expected_tree_instances)
	_check("wind-only baseline has complete expanded tree bounds",
		_tree_wind_cull_bounds_match_state(baseline, expected_tree_instances, 0))
	var baseline_tree_bounds := _tree_state_bounds(baseline, TREE_SAMPLE_ID)
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
			_tree_state_bounds_count(cell_root, TREE_SAMPLE_ID) == expected_tree_instances)
		_check("%d m per-cell cull bounds cover all expanded tree instances" % candidate_size,
			_tree_wind_cull_bounds_match_state(cell_root, expected_tree_instances, candidate_size))
		_check("%d m regrouping preserves the complete expanded tree bounds" % candidate_size,
			_aabb_approx_equal(_tree_state_bounds(cell_root, TREE_SAMPLE_ID), baseline_tree_bounds))
		_check("%d m regrouping preserves total imported vegetation bounds" % candidate_size,
			_aabb_approx_equal(ImportedVegetation.bounds(cell_root), baseline_all_bounds))

		var damage_entries := _damage_entries(cell_root, "tree-cell-edge")
		var before_hide_phase_state: Array[String] = []
		if phase_buffer_available:
			before_hide_phase_state = _tree_wind_phase_signatures(cell_root)
		var before_hide_tree_bounds := _tree_state_bounds(cell_root, TREE_SAMPLE_ID)
		_check("%d m wind batching has all source-part damage entries" % candidate_size,
			damage_entries.size() == _damage_record_count(records) * parts.size())
		_check("%d m wind tree damage hides every mapped instance" % candidate_size,
			ImportedVegetation.set_damage_hidden(cell_root, "tree-cell-edge", true)
			and _damage_instances_match_hidden_state(cell_root, "tree-cell-edge", true))
		_check("%d m wind tree damage removes the hidden tree from bounds" % candidate_size,
			_tree_state_bounds_count(cell_root, TREE_SAMPLE_ID) == expected_tree_instances - damage_entries.size()
			and not _aabb_approx_equal(_tree_state_bounds(cell_root, TREE_SAMPLE_ID), before_hide_tree_bounds))
		_check("%d m wind tree damage restores every mapped instance" % candidate_size,
			ImportedVegetation.set_damage_hidden(cell_root, "tree-cell-edge", false)
			and _damage_instances_match_hidden_state(cell_root, "tree-cell-edge", false))
		_check("%d m wind damage restoration restores bounds and seed phases" % candidate_size,
			_tree_state_bounds_count(cell_root, TREE_SAMPLE_ID) == expected_tree_instances
			and _aabb_approx_equal(_tree_state_bounds(cell_root, TREE_SAMPLE_ID), before_hide_tree_bounds)
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
	var include_text := FileAccess.get_file_as_string("res://scenery/imported_tree_wind.gdshaderinc")
	var legacy_text := FileAccess.get_file_as_string("res://scenery/imported_vegetation_wind.gdshader")
	_check("tree wind shaders do not rely on unsupported per-instance uniforms",
		not include_text.contains("instance uniform") and not legacy_text.contains("instance uniform"))
	_check("tree wind adds the analytic inverse-transpose normal term",
		include_text.contains("NORMAL.y -= dot(shear, NORMAL);"))
	_check("tree wind adds the analytic Jacobian term to normal-map tangents",
		include_text.contains("TANGENT += shear * TANGENT.y;")
		and include_text.contains("BINORMAL += shear * BINORMAL.y;"))
	_check("tree wind displaces horizontally only",
		include_text.contains("VERTEX.xz += direction * (top_sway * normalized_height * normalized_height);")
		and not include_text.contains("VERTEX.y +=") and not include_text.contains("VERTEX +="))
	_check("legacy all-role wind shader no longer carries a tree branch",
		not legacy_text.contains("tree_wind_mode"))
	for key: String in TREE_WIND_SHADERS:
		_check("tree wind variant %s includes the shared material mirror" % key,
			FileAccess.get_file_as_string(str(TREE_WIND_SHADERS[key])).contains(
				'#include "res://scenery/imported_tree_wind.gdshaderinc"'))
	var checked_tree := false
	var checked_crop := false
	var saw_tree_shader := false
	var saw_tree_source_material := false
	var saw_bark := false
	var saw_foliage := false
	var parts := ImportedVegetation.get_parts(TREE_SAMPLE_ID)
	for child in tree_wind_root.get_children():
		var instance := child as MultiMeshInstance3D
		var asset_id := str(instance.name).get_slice("_Part_", 0)
		if asset_id == TREE_SAMPLE_ID:
			checked_tree = true
			_check("tree opt-in child is marked separately from legacy wind",
				bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false))
				and not bool(instance.get_meta("_imported_vegetation_wind_enabled", false)))
			var draw_mesh := instance.multimesh.mesh
			var part_index := int(str(instance.name).get_slice("_Part_", 1).get_slice("_", 0))
			var source_materials: Array = parts[part_index].get("materials", [])
			for surface_index in range(draw_mesh.get_surface_count()):
				var output_material := draw_mesh.surface_get_material(surface_index)
				if not output_material is ShaderMaterial:
					saw_tree_source_material = true
					_check("unsupported tree material fails closed without replacement",
						output_material == source_materials[surface_index])
					continue
				saw_tree_shader = true
				var wind_material := output_material as ShaderMaterial
				var source_material := source_materials[surface_index] as BaseMaterial3D
				_check_tree_wind_material(TREE_SAMPLE_ID, surface_index, wind_material, source_material,
					parts[part_index].get("bounds", AABB()))
				saw_bark = saw_bark or source_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				saw_foliage = saw_foliage or source_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
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
	_check("qualified Quercus converts both its opaque bark and alpha-scissor foliage",
		saw_tree_shader and saw_bark and saw_foliage)
	_check("tree asset is either wholly converted or wholly fail-closed",
		not (saw_tree_shader and saw_tree_source_material))
	if saw_tree_shader:
		var static_tree_root := ImportedVegetation.build(batches)
		var static_bounds := _tree_state_bounds(static_tree_root, TREE_SAMPLE_ID)
		var wind_bounds := _tree_state_bounds(tree_wind_root, TREE_SAMPLE_ID)
		_check("tree wind expands only horizontal root bounds for shader sway",
			wind_bounds.size.x > static_bounds.size.x and wind_bounds.size.z > static_bounds.size.z
			and is_equal_approx(wind_bounds.position.y, static_bounds.position.y)
			and is_equal_approx(wind_bounds.size.y, static_bounds.size.y))
		var limit := float(ImportedVegetation.TREE_WIND_LEAN_LIMITS_M[TREE_SAMPLE_ID])
		var state: Dictionary = tree_wind_root.get_meta("_imported_vegetation_state", {})
		var growth_matches := true
		for record: Dictionary in state.get("bounds", []):
			if str(record.get("asset_id", "")) != TREE_SAMPLE_ID:
				continue
			var record_transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
			var grow := limit / record_transform.basis.y.length()
			var source_bounds: AABB = parts[0].get("bounds", AABB())
			var record_bounds: AABB = record.get("bounds", AABB())
			growth_matches = growth_matches \
				and is_equal_approx(record_bounds.size.x, source_bounds.size.x + 2.0 * grow) \
				and is_equal_approx(record_bounds.size.z, source_bounds.size.z + 2.0 * grow) \
				and is_equal_approx(record_bounds.size.y, source_bounds.size.y)
		_check("each tree bound grows by its own scaled crown-top limit", growth_matches)
		var before := _tree_wind_parameter_snapshot(tree_wind_root)
		ImportedVegetation.set_wind(tree_wind_root, 10.0, Vector2(0.0, 1.0))
		_check("legacy set_wind leaves session-driven tree-wind materials unchanged",
			not before.is_empty() and _tree_wind_parameter_snapshot(tree_wind_root) == before)
		var repeat_root := ImportedVegetation.build(batches, false, {"tree_wind": true})
		_check("tree-wind materials are shared across builds",
			_tree_wind_parameter_snapshot(repeat_root) == before
			and _first_tree_wind_material(repeat_root) == _first_tree_wind_material(tree_wind_root))
		repeat_root.free()
		static_tree_root.free()
	var legacy_wind_root := ImportedVegetation.build(batches, true)
	var checked_legacy_roles := {TREE_SAMPLE_ID: false, "wheat_4": false}
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
		is_equal_approx(float(legacy_wind_strengths.get(TREE_SAMPLE_ID, -1.0)), 0.01)
		and is_equal_approx(float(legacy_wind_strengths.get("wheat_4", -1.0)), 0.0375))
	ImportedVegetation.set_wind(legacy_wind_root, 0.0)
	_check("legacy enable_wind remains all-role",
		bool(checked_legacy_roles[TREE_SAMPLE_ID]) and bool(checked_legacy_roles["wheat_4"]))
	_check("legacy set_wind updates all role materials",
		_legacy_wind_materials_have_strength(legacy_wind_root, 0.0))
	tree_wind_root.free()
	legacy_wind_root.free()


## L15b-R2: every accepted source material term is carried by the matching variant.
func _check_tree_wind_material(asset_id: String, surface_index: int, wind_material: ShaderMaterial,
		source_material: BaseMaterial3D, part_bounds: AABB) -> void:
	var label := "%s surface %d" % [asset_id, surface_index]
	var expected_key := ImportedVegetation._tree_wind_shader_key(source_material)
	_check(label + " uses the variant for its cull mode and texture repeat",
		not expected_key.is_empty()
		and wind_material.shader.resource_path == str(TREE_WIND_SHADERS[expected_key]))
	_check(label + " preserves albedo color, texture, UV and vertex-color settings",
		wind_material.get_shader_parameter("albedo_color") == source_material.albedo_color
		and wind_material.get_shader_parameter("albedo_texture") == source_material.albedo_texture
		and bool(wind_material.get_shader_parameter("use_albedo_texture")) == (source_material.albedo_texture != null)
		and wind_material.get_shader_parameter("uv1_scale") == Vector2(source_material.uv1_scale.x, source_material.uv1_scale.y)
		and wind_material.get_shader_parameter("uv1_offset") == Vector2(source_material.uv1_offset.x, source_material.uv1_offset.y)
		and bool(wind_material.get_shader_parameter("use_vertex_color")) == source_material.vertex_color_use_as_albedo)
	_check(label + " preserves metallic, roughness and specular values, maps and channels",
		is_equal_approx(float(wind_material.get_shader_parameter("metallic")), source_material.metallic)
		and wind_material.get_shader_parameter("metallic_texture") == source_material.metallic_texture
		and bool(wind_material.get_shader_parameter("use_metallic_texture")) == (source_material.metallic_texture != null)
		and wind_material.get_shader_parameter("metallic_texture_channel")
			== ImportedVegetation._texture_channel_mask(source_material.metallic_texture_channel)
		and is_equal_approx(float(wind_material.get_shader_parameter("roughness")), source_material.roughness)
		and wind_material.get_shader_parameter("roughness_texture") == source_material.roughness_texture
		and bool(wind_material.get_shader_parameter("use_roughness_texture")) == (source_material.roughness_texture != null)
		and is_equal_approx(float(wind_material.get_shader_parameter("specular")), source_material.metallic_specular))
	var normal_map := source_material.normal_enabled and source_material.normal_texture != null
	_check(label + " preserves its normal map",
		bool(wind_material.get_shader_parameter("use_normal_texture")) == normal_map
		and wind_material.get_shader_parameter("normal_texture") == source_material.normal_texture
		and is_equal_approx(float(wind_material.get_shader_parameter("normal_scale")), source_material.normal_scale))
	var ambient_occlusion := source_material.get_feature(BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION)
	_check(label + " preserves ambient occlusion map, channel and light affect",
		bool(wind_material.get_shader_parameter("use_ao")) == ambient_occlusion
		and wind_material.get_shader_parameter("ao_texture") == source_material.ao_texture
		and wind_material.get_shader_parameter("ao_texture_channel")
			== ImportedVegetation._texture_channel_mask(source_material.ao_texture_channel)
		and is_equal_approx(float(wind_material.get_shader_parameter("ao_light_affect")), source_material.ao_light_affect))
	var scissor := source_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_check(label + " preserves alpha-scissor mode and threshold",
		bool(wind_material.get_shader_parameter("use_alpha_scissor")) == scissor
		and is_equal_approx(float(wind_material.get_shader_parameter("alpha_scissor_threshold")),
			source_material.alpha_scissor_threshold))
	var max_mip: Variant = wind_material.get_shader_parameter("alpha_scissor_max_mip")
	_check(label + " clamps only foliage to the last coverage-preserving mip",
		max_mip is float and is_equal_approx(max_mip, ImportedVegetation.FOLIAGE_ALPHA_MAX_MIP if scissor else 1000.0))
	_check(label + " bends in its own source-part height frame",
		is_equal_approx(float(wind_material.get_shader_parameter("plant_height")), part_bounds.size.y)
		and is_equal_approx(float(wind_material.get_shader_parameter("plant_base_y")), part_bounds.position.y))
	_check(label + " uses its measured crown-top limit",
		is_equal_approx(float(wind_material.get_shader_parameter("tree_lean_limit_m")),
			float(ImportedVegetation.TREE_WIND_LEAN_LIMITS_M.get(asset_id, -1.0))))
	_check(label + " flutters only foliage without a normal map",
		is_equal_approx(float(wind_material.get_shader_parameter("leaf_flutter_tilt")),
			ImportedVegetation.LEAF_FLUTTER_TILT if scissor and not normal_map else 0.0))
	_check(label + " keeps its render priority", wind_material.render_priority == source_material.render_priority)


func _tree_wind_parameter_snapshot(root: Node3D) -> Array[String]:
	var snapshot: Array[String] = []
	for child in root.get_children():
		if not bool(child.get_meta("_imported_vegetation_tree_wind_enabled", false)):
			continue
		var mesh := (child as MultiMeshInstance3D).multimesh.mesh
		for surface_index in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface_index) as ShaderMaterial
			if material == null:
				continue
			snapshot.append("%s|%s|%s|%s" % [material.shader.resource_path,
				material.get_shader_parameter("tree_lean_limit_m"),
				material.get_shader_parameter("leaf_flutter_tilt"),
				material.get_shader_parameter("plant_height")])
	return snapshot


func _first_tree_wind_material(root: Node3D) -> Material:
	for child in root.get_children():
		if bool(child.get_meta("_imported_vegetation_tree_wind_enabled", false)):
			return (child as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0)
	return null


func _test_tree_wind_transform_guard() -> void:
	var parts := ImportedVegetation.get_parts(TREE_SAMPLE_ID)
	var separate_crown: Array[Dictionary] = [parts[0], parts[0]]
	_check("separate source crown and stem parts retain source materials until a shared bend frame is qualified",
		not ImportedVegetation._tree_asset_wind_supported(TREE_SAMPLE_ID, separate_crown, []))
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
	ImportedVegetation.queue(batches, TREE_SAMPLE_ID, tilt, 17)
	var guarded_root := ImportedVegetation.build(batches, false, {"tree_wind": true})
	_check("tilted tree batches fail closed to source materials",
		_not_tree_wind_enabled(guarded_root))
	guarded_root.free()
	var front := StandardMaterial3D.new()
	front.cull_mode = BaseMaterial3D.CULL_FRONT
	var back_clamp := StandardMaterial3D.new()
	back_clamp.texture_repeat = false
	var orm := ORMMaterial3D.new()
	orm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ao_uv2 := StandardMaterial3D.new()
	ao_uv2.ao_enabled = true
	ao_uv2.ao_on_uv2 = true
	for case: Array in [[front, "front-face culling"], [back_clamp, "non-repeating textures"],
			[orm, "ORM materials"], [ao_uv2, "ambient occlusion on UV2"]]:
		_check("tree wind rejects %s it does not mirror" % case[1],
			ImportedVegetation._tree_material_support_reason(case[0]).contains(str(case[1])))


func _test_tree_wind_qualification() -> void:
	var actual_tree_ids: Array[String] = []
	for asset_value: Dictionary in ImportedVegetation.catalog().get("assets", []):
		if str(asset_value.get("role", "")) == "tree":
			actual_tree_ids.append(str(asset_value.get("id", "")))
	actual_tree_ids.sort()
	var expected_all_tree_ids: Array[String] = []
	for asset_id: String in EXPECTED_TREE_LEAF_TEXTURES:
		expected_all_tree_ids.append(asset_id)
	expected_all_tree_ids.append_array(["oak_tree", "maple_tree", "landscapelab_quercus", "landscapelab_pine",
		"landscapelab_fagus", "landscapelab_quercus2"])
	expected_all_tree_ids.sort()
	_check("catalog covers seven library forms, Maple, oak, Quercus, Pine, Fagus and Quercus 2 sources",
		actual_tree_ids == expected_all_tree_ids)
	var qualified: Array = ImportedVegetation.TREE_WIND_LEAN_LIMITS_M.keys()
	qualified.sort()
	_check("only the placed downloaded LandscapeLab trees carry measured sway limits",
		qualified == ["landscapelab_fagus", "landscapelab_pine", "landscapelab_quercus", "landscapelab_quercus2"])

	var batches: Dictionary = {}
	for index in range(actual_tree_ids.size()):
		var asset_id := actual_tree_ids[index]
		var placement := Transform3D(Basis(Vector3.UP, float(index) * 0.19),
			Vector3(float(index) * 30.0, 0.0, float(index % 2) * 9.0))
		placement = ImportedVegetation.fit_to_height(asset_id, 10.0, placement)
		_check("%s queues as a retained source ID" % asset_id,
			ImportedVegetation.queue(batches, asset_id, placement, 100 + index) == asset_id)
	var wind_root := ImportedVegetation.build(batches, false, {"tree_wind": true, "tree_cell_size_m": 0})
	var converted_surfaces: Dictionary = {}
	var static_sources: Dictionary = {}
	for child in wind_root.get_children():
		var instance := child as MultiMeshInstance3D
		var asset_id := str(instance.name).get_slice("_Part_", 0)
		var part_index := int(str(instance.name).get_slice("_Part_", 1).get_slice("_", 0))
		var source_parts := ImportedVegetation.get_parts(asset_id)
		var source_materials: Array = source_parts[part_index].get("materials", [])
		var draw_mesh: Mesh = instance.multimesh.mesh
		_check("%s keeps its imported surface count" % asset_id, draw_mesh.get_surface_count() == source_materials.size())
		var tree_wind := bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false))
		_check("%s is never marked for legacy wind" % asset_id,
			not bool(instance.get_meta("_imported_vegetation_wind_enabled", false)))
		for surface_index in range(mini(draw_mesh.get_surface_count(), source_materials.size())):
			var output_material := draw_mesh.surface_get_material(surface_index)
			if tree_wind:
				_check("%s surface %d converts to tree wind" % [asset_id, surface_index], output_material is ShaderMaterial)
				if output_material is ShaderMaterial:
					_check_tree_wind_material(asset_id, surface_index, output_material as ShaderMaterial,
						source_materials[surface_index] as BaseMaterial3D, source_parts[part_index].get("bounds", AABB()))
					converted_surfaces[asset_id] = int(converted_surfaces.get(asset_id, 0)) + 1
			else:
				_check("%s surface %d keeps its original source material" % [asset_id, surface_index],
					output_material == source_materials[surface_index])
				static_sources[asset_id] = true
	for asset_id: String in actual_tree_ids:
		var surfaces := 0
		for part: Dictionary in ImportedVegetation.get_parts(asset_id):
			surfaces += (part.get("mesh") as Mesh).get_surface_count()
		if asset_id in qualified:
			_check("%s converts every bark and foliage surface" % asset_id, int(converted_surfaces.get(asset_id, 0)) == surfaces)
		else:
			_check("%s stays static with its source materials" % asset_id,
				bool(static_sources.get(asset_id, false)) and not converted_surfaces.has(asset_id))
	_check("the protected clubhouse Maple source never receives wind",
		bool(static_sources.get("maple_tree", false)) and not converted_surfaces.has("maple_tree"))
	wind_root.free()


## L15b-R2: the saturated shader bend keeps every source vertex inside the unchanged
## CollisionWorld envelopes, so close-tree wind stays render-only (no world change).
func _test_tree_wind_stays_inside_collision_proxies() -> void:
	for asset_id: String in ImportedVegetation.TREE_WIND_LEAN_LIMITS_M:
		var limit := float(ImportedVegetation.TREE_WIND_LEAN_LIMITS_M[asset_id])
		_check("%s sway limit is positive and within the field-card lean" % asset_id,
			limit > 0.0 and limit <= FIELD_CARD_LEAN_M)
		# The allowance grows with placed height, so the smallest placed tree is the worst case.
		var smallest: Dictionary = {}
		for prefab: String in ["shade_tree", "sapling"]:
			for seed in range(512):
				var spec := VegetationPlacement.spec(prefab, seed)
				if str(spec.get("asset_id", "")) == asset_id \
						and (smallest.is_empty() or float(spec.height) < float(smallest.height)):
					smallest = spec
		_check("%s is placed by shade-tree or sapling specs" % asset_id, not smallest.is_empty())
		if smallest.is_empty():
			continue
		var parts := ImportedVegetation.get_parts(asset_id)
		var part_bounds: AABB = parts[0].get("bounds", AABB())
		var source_bounds: Dictionary = ImportedVegetation.get_asset(asset_id).source_bounds_m
		var ground_offset := float(source_bounds.get("ground_offset", 0.0))
		var scale := float(smallest.scale)
		var height := float(smallest.height)
		var margin := float(smallest.wind_margin)
		var half_x := float(smallest.width) * 0.5 + margin
		var half_z := float(smallest.depth) * 0.5 + margin
		# CollisionWorld crown bottom: the trunk-height range, lowered for low broadleaf foliage.
		var crown_bottoms: Array[float] = []
		for trunk_hash in [0.0, 1.0]:
			var trunk_height: float = height * (CollisionWorld.SHADE_TREE_TRUNK_HEIGHT_FRACTION
				+ CollisionWorld.SHADE_TREE_TRUNK_HEIGHT_VARIATION_FRACTION * trunk_hash)
			trunk_height = minf(trunk_height,
				height * float(CollisionWorld.LANDSCAPELAB_CROWN_BOTTOM_FRACTIONS.get(asset_id, 1.0)))
			crown_bottoms.append(trunk_height)
		var crown_escape_m := -INF
		var trunk_band_sway_m := 0.0
		var mesh: Mesh = parts[0].get("mesh")
		for surface_index in range(mesh.get_surface_count()):
			var vertices: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var weight := clampf((vertex.y - part_bounds.position.y) / part_bounds.size.y, 0.0, 1.0)
				var sway := limit * weight * weight
				var above_ground := (vertex.y + ground_offset) * scale
				for crown_bottom: float in crown_bottoms:
					if above_ground >= crown_bottom:
						crown_escape_m = maxf(crown_escape_m, maxf(
							absf(vertex.x * scale - float(smallest.crown_offset_x)) + sway - half_x,
							absf(vertex.z * scale - float(smallest.crown_offset_z)) + sway - half_z))
					else:
						trunk_band_sway_m = maxf(trunk_band_sway_m, sway)
		_check("%s saturated sway keeps every crown vertex inside its crown proxy (escape %.4f m)" % [
			asset_id, crown_escape_m], crown_escape_m <= 0.0)
		_check("%s trunk-band sway stays within the trunk capsule's wind margin (%.4f m)" % [
			asset_id, trunk_band_sway_m], trunk_band_sway_m <= margin)


## L6c-R1: MultiMesh LOD ignored the ~9.5x instance scale of the 1 m Fagus source, and generated
## LODs dropped whole leaf cards, so beech crowns turned bare from about 60 m. LandscapeLab batches
## now bias LOD by their largest instance scale and drop only the near-empty foliage levels.
func _test_world_lod_keeps_foliage() -> void:
	var placements := {
		"landscapelab_fagus": [9.4, 10.2],
		"landscapelab_quercus2": [3.2, 4.8],
		"landscapelab_quercus": [9.5, 10.1],
		"landscapelab_pine": [3.3, 10.3],
		"maple_tree": [14.0],
	}
	for tree_wind: bool in [true, false]:
		var batches := {}
		var expected_bias := {}
		for asset_id: String in placements:
			var heights: Array = placements[asset_id]
			for index in range(heights.size()):
				var placement := ImportedVegetation.fit_to_height(asset_id, float(heights[index]),
					Transform3D(Basis(Vector3.UP, 0.4 * float(index)), Vector3(float(index) * 25.0, 0.0, 40.0 * float(batches.size()))))
				ImportedVegetation.queue(batches, asset_id, placement, 300 + index)
				expected_bias[asset_id] = maxf(float(expected_bias.get(asset_id, 0.0)), placement.basis.get_scale().x)
		var root := ImportedVegetation.build(batches, false, {"tree_wind": tree_wind, "tree_cell_size_m": 0})
		var mode := "tree wind" if tree_wind else "static"
		for child in root.get_children():
			var instance := child as MultiMeshInstance3D
			var asset_id := str(instance.name).get_slice("_Part_", 0)
			var part_index := int(str(instance.name).get_slice("_Part_", 1).get_slice("_", 0))
			var source_part: Dictionary = ImportedVegetation.get_parts(asset_id)[part_index]
			var source_mesh: Mesh = source_part.mesh
			var draw_mesh: Mesh = instance.multimesh.mesh
			if asset_id == "maple_tree":
				_check("%s: the protected Maple keeps default LOD and its source LOD chain" % mode,
					is_equal_approx(instance.lod_bias, 1.0) and _lod_counts(draw_mesh) == _lod_counts(source_mesh))
				continue
			_check("%s: %s LOD bias is its largest instance scale (%.3f)" % [mode, asset_id, instance.lod_bias],
				is_equal_approx(instance.lod_bias, float(expected_bias[asset_id])))
			var source_materials: Array = source_part.get("materials", [])
			for surface_index in range(source_mesh.get_surface_count()):
				var source_info := RenderingServer.mesh_get_surface(source_mesh.get_rid(), surface_index)
				var draw_info := RenderingServer.mesh_get_surface(draw_mesh.get_rid(), surface_index)
				var foliage := (source_materials[surface_index] as BaseMaterial3D).transparency \
					== BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_check("%s: %s surface %d keeps its exact vertex and index data" % [mode, asset_id, surface_index],
					draw_info.get("vertex_data") == source_info.get("vertex_data")
					and draw_info.get("attribute_data") == source_info.get("attribute_data")
					and draw_info.get("index_data") == source_info.get("index_data"))
				var draw_lods: Array = draw_info.get("lods", [])
				var source_lods: Array = source_info.get("lods", [])
				if foliage:
					var dense: Array = []
					var dropped := 0
					for lod: Dictionary in source_lods:
						if _lod_triangle_share(source_info, lod.index_data) >= ImportedVegetation.FOLIAGE_LOD_MIN_FRACTION:
							dense.append(lod)
						else:
							dropped += 1
					_check("%s: %s foliage surface %d keeps only its dense LOD levels (%d dropped)" % [
						mode, asset_id, surface_index, dropped], draw_lods == dense and dropped > 0)
				else:
					_check("%s: %s bark surface %d keeps its generated LOD chain" % [mode, asset_id, surface_index],
						draw_lods.size() == source_lods.size() and not draw_lods.is_empty())
			var shadow_mesh := (draw_mesh as ArrayMesh).shadow_mesh
			var source_shadow := (source_mesh as ArrayMesh).shadow_mesh
			_check("%s: %s shadow mesh drops the same sparse foliage levels" % [mode, asset_id],
				shadow_mesh != null and shadow_mesh != source_shadow
				and _lod_counts(shadow_mesh) == _lod_counts(draw_mesh))
		root.free()
	_check("the imported source meshes keep their generated foliage LODs",
		_lod_counts(ImportedVegetation.get_parts("landscapelab_fagus")[0].mesh).min() > 0)


func _lod_triangle_share(surface_info: Dictionary, lod_indices: PackedByteArray) -> float:
	var bytes_per_index := float((surface_info.index_data as PackedByteArray).size()) / float(surface_info.index_count)
	return float(lod_indices.size()) / bytes_per_index / float(surface_info.index_count)


func _lod_counts(mesh: Mesh) -> Array[int]:
	var counts: Array[int] = []
	for surface_index in range(mesh.get_surface_count()):
		counts.append((RenderingServer.mesh_get_surface(mesh.get_rid(), surface_index).get("lods", []) as Array).size())
	return counts


func _test_maple_source_materials() -> void:
	var maple := ImportedVegetation.get_asset("maple_tree")
	var parts := ImportedVegetation.get_parts("maple_tree")
	_check("Maple metadata pins LOD1 with 5,541 triangles and two source surfaces",
		str(maple.get("source_id", "")) == "lolipop_maple_2026"
		and int(maple.get("source_triangles", 0)) == 5541
		and int(maple.get("source_surfaces", 0)) == 2
		and (maple.get("lod", {}) as Dictionary).get("imported_supplied_levels", []) == ["LOD1"])
	_check("Maple imports source mesh parts", not parts.is_empty())
	if parts.is_empty():
		return
	var pbr_and_alpha_valid := true
	var source_mapping_valid := true
	var maple_triangles := 0
	var maple_surfaces := 0
	var maple_mask_surfaces := 0
	var maple_opaque_surfaces := 0
	for part: Dictionary in parts:
		var maple_mesh: Mesh = part.get("mesh")
		var source_materials: Array = part.get("materials", [])
		if maple_mesh == null:
			pbr_and_alpha_valid = false
			source_mapping_valid = false
			continue
		maple_triangles += maple_mesh.get_faces().size() / 3
		maple_surfaces += maple_mesh.get_surface_count()
		source_mapping_valid = source_mapping_valid \
			and source_materials.size() == maple_mesh.get_surface_count()
		for surface_index in range(mini(maple_mesh.get_surface_count(), source_materials.size())):
			var source_value: Variant = source_materials[surface_index]
			source_mapping_valid = source_mapping_valid \
				and maple_mesh.surface_get_material(surface_index) == source_value
			if not source_value is BaseMaterial3D:
				pbr_and_alpha_valid = false
				continue
			var material := source_value as BaseMaterial3D
			var alpha_mode_valid := false
			if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				maple_mask_surfaces += 1
				alpha_mode_valid = material.cull_mode == BaseMaterial3D.CULL_DISABLED \
					and is_equal_approx(material.alpha_scissor_threshold, 0.5)
			elif material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				maple_opaque_surfaces += 1
				alpha_mode_valid = material.cull_mode == BaseMaterial3D.CULL_BACK
			var surface_pbr_valid := alpha_mode_valid
			surface_pbr_valid = surface_pbr_valid and material.albedo_texture != null
			surface_pbr_valid = surface_pbr_valid and material.normal_enabled and material.normal_texture != null
			var orm_source_texture: Texture2D = material.orm_texture
			var orm_channels_valid := false
			if orm_source_texture != null:
				orm_channels_valid = (material.ao_texture == null or material.ao_texture == orm_source_texture) \
					and (material.roughness_texture == null or material.roughness_texture == orm_source_texture) \
					and (material.metallic_texture == null or material.metallic_texture == orm_source_texture)
			else:
				orm_source_texture = material.roughness_texture
				orm_channels_valid = orm_source_texture != null \
					and material.ao_texture == orm_source_texture \
					and material.metallic_texture == orm_source_texture
			surface_pbr_valid = surface_pbr_valid and orm_channels_valid
			surface_pbr_valid = surface_pbr_valid \
				and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			surface_pbr_valid = surface_pbr_valid \
				and material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
			surface_pbr_valid = surface_pbr_valid \
				and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			surface_pbr_valid = surface_pbr_valid \
				and material.get_feature(BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION)
			surface_pbr_valid = surface_pbr_valid \
				and is_finite(material.roughness) and is_equal_approx(material.roughness, 1.0)
			surface_pbr_valid = surface_pbr_valid \
				and is_finite(material.metallic) and is_zero_approx(material.metallic)
			surface_pbr_valid = surface_pbr_valid \
				and is_finite(material.metallic_specular) \
				and material.metallic_specular >= 0.0 and material.metallic_specular <= 1.0
			pbr_and_alpha_valid = pbr_and_alpha_valid and surface_pbr_valid
	_check("Maple source meshes retain 5,541 triangles and two material surfaces",
		maple_triangles == 5541 and maple_surfaces == 2)
	_check("Maple foliage remains double-sided MASK and bark remains opaque",
		maple_mask_surfaces == 1 and maple_opaque_surfaces == 1 and pbr_and_alpha_valid)
	_check("Maple imported parts retain their original surface mappings", source_mapping_valid)
	_test_maple_texture_imports(parts)
	var batches: Dictionary = {}
	_check("Maple queues as its canonical source ID",
		ImportedVegetation.queue(batches, "maple_tree", Transform3D.IDENTITY, 91) == "maple_tree")
	var static_root := ImportedVegetation.build(batches)
	var matched_part_indices: Dictionary = {}
	var retained_source_materials := true
	for child in static_root.get_children():
		if not child is MultiMeshInstance3D or not str(child.name).begins_with("maple_tree_Part_"):
			continue
		var part_index := int(str(child.name).get_slice("_Part_", 1).get_slice("_", 0))
		if part_index < 0 or part_index >= parts.size():
			retained_source_materials = false
			continue
		var draw_mesh: Mesh = (child as MultiMeshInstance3D).multimesh.mesh
		var source_materials: Array = parts[part_index].get("materials", [])
		var surfaces_match := draw_mesh.get_surface_count() == source_materials.size()
		for surface_index in range(mini(draw_mesh.get_surface_count(), source_materials.size())):
			surfaces_match = surfaces_match \
				and draw_mesh.surface_get_material(surface_index) == source_materials[surface_index]
		retained_source_materials = retained_source_materials and surfaces_match
		matched_part_indices[part_index] = true
	_check("Maple static batches retain the original materials for every source part",
		retained_source_materials and matched_part_indices.size() == parts.size())
	static_root.free()


func _test_maple_texture_imports(parts: Array) -> void:
	var textures_by_name: Dictionary = {}
	for part: Dictionary in parts:
		for source_value: Variant in part.get("materials", []):
			if not source_value is BaseMaterial3D:
				continue
			var material := source_value as BaseMaterial3D
			for source_texture: Variant in [
				material.albedo_texture,
				material.normal_texture,
				material.orm_texture,
				material.ao_texture,
				material.roughness_texture,
				material.metallic_texture,
			]:
				if source_texture is Texture2D:
					textures_by_name[_texture_filename(source_texture)] = source_texture
	var expected_names: Array = EXPECTED_MAPLE_TEXTURES.duplicate()
	expected_names.sort()
	var actual_names: Array = textures_by_name.keys()
	actual_names.sort()
	_check("Maple materials reference exactly the six source PBR textures", actual_names == expected_names)
	for filename: String in EXPECTED_MAPLE_TEXTURES:
		var texture_path := "res://assets/landscape/vegetation/models/maple_tree/textures/" + filename
		var config := ConfigFile.new()
		var loaded := config.load(texture_path + ".import") == OK
		_check(filename + " pins its VRAM and mipmap import recipe", loaded)
		if not loaded:
			continue
		var expected_normal_mode := 1 if filename.ends_with("_normal.png") else 0
		# Keep leaf alpha coverage at farm/forest viewing distances; ordinary
		# color mip averaging erodes this atlas at the authored 0.5 cutoff.
		var expected_mips := filename != "maple_leaves_basecolor.png"
		var metadata: Variant = config.get_value("remap", "metadata", {})
		var metadata_has_vram := metadata is Dictionary \
			and bool((metadata as Dictionary).get("vram_texture", false))
		_check(filename + " imports as VRAM-compressed with the reviewed mip policy",
			config.get_value("remap", "type", "") == "CompressedTexture2D"
			and config.get_value("params", "compress/mode", -1) == 2
			and config.get_value("params", "mipmaps/generate", null) == expected_mips
			and config.get_value("params", "mipmaps/limit", 0) == -1
			and config.get_value("params", "detect_3d/compress_to", -1) == 1
			and metadata_has_vram
			and str(config.get_value("remap", "path.s3tc", "")).ends_with(".s3tc.ctex")
			and str(config.get_value("remap", "path.etc2", "")).ends_with(".etc2.ctex"))
		_check(filename + " uses the expected normal-map compression semantics",
			config.get_value("params", "compress/normal_map", -1) == expected_normal_mode)
		var material_texture: Texture2D = textures_by_name.get(filename)
		_check(filename + " remains assigned to a Maple material", material_texture != null)
		var imported_texture := load(texture_path) as Texture2D
		_check(filename + " loads as the imported compressed texture",
			imported_texture is CompressedTexture2D
			and imported_texture.resource_path == texture_path
			and imported_texture.get_width() > 0 and imported_texture.get_height() > 0)
		if imported_texture == null:
			continue
		if DisplayServer.get_name() == "headless":
			continue # Dummy can verify imported resource metadata but not native image readback.
		var picture := imported_texture.get_image()
		_check(filename + " has native imported image data", picture != null and not picture.is_empty())
		if picture == null or picture.is_empty():
			continue
		var expected_mip_levels := _complete_mipmap_count(picture.get_width(), picture.get_height()) if expected_mips else 0
		_check(filename + " retains all native texture mip levels",
			picture.get_mipmap_count() == expected_mip_levels
			and picture.has_mipmaps() == (expected_mip_levels > 0))


func _complete_mipmap_count(width: int, height: int) -> int:
	var largest_dimension := maxi(width, height)
	var mip_levels := 0
	while largest_dimension > 1:
		largest_dimension >>= 1
		mip_levels += 1
	return mip_levels


func _test_oak_blend_fails_closed_to_static_source_material() -> void:
	var oak := ImportedVegetation.get_asset("oak_tree")
	var parts := ImportedVegetation.get_parts("oak_tree")
	_check("oak source metadata retains its 5,303-triangle one-surface LOD0",
		str(oak.get("source_id", "")) == "opengameart_oak_tree_lod_2026"
		and int(oak.get("source_triangles", 0)) == 5303
		and int(oak.get("source_surfaces", 0)) == 1)
	_check("oak has one imported mesh part", parts.size() == 1)
	if parts.size() != 1:
		return
	var oak_mesh: Mesh = parts[0].get("mesh")
	var source_materials: Array = parts[0].get("materials", [])
	_check("oak source mesh preserves one atlas surface and 5,303 triangles",
		oak_mesh != null
		and oak_mesh.get_surface_count() == 1
		and oak_mesh.get_faces().size() / 3 == 5303)
	_check("oak source material array maps one material to its one surface",
		source_materials.size() == 1
		and oak_mesh != null
		and oak_mesh.surface_get_material(0) == source_materials[0])
	if source_materials.size() != 1 or not source_materials[0] is BaseMaterial3D:
		return
	var oak_material := source_materials[0] as BaseMaterial3D
	_check("oak preserves the packed Quercus base-color atlas with BLEND depth pre-pass",
		oak_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		and _texture_filename(oak_material.albedo_texture) == "Quercus_A_1024.png")
	_check("oak uses the matte roughness mapping and records Godot's native specular default",
		is_equal_approx(float(oak_material.get("roughness")), 1.0)
		and is_equal_approx(float(oak_material.get("metallic_specular")), 0.5))
	_check("BLEND alpha is rejected by the tree-wind material gate",
		ImportedVegetation._tree_material_support_reason(oak_material).contains("transparency mode"))

	var batches: Dictionary = {}
	_check("oak queues as its exact retained source ID",
		ImportedVegetation.queue(batches, "oak_tree", Transform3D.IDENTITY, 408) == "oak_tree")
	var static_root := ImportedVegetation.build(batches, false, {"tree_wind": true})
	var checked_static_source := false
	for child in static_root.get_children():
		if not child is MultiMeshInstance3D or not str(child.name).begins_with("oak_tree_Part_"):
			continue
		var instance := child as MultiMeshInstance3D
		var static_mesh: Mesh = instance.multimesh.mesh
		_check("oak BLEND fallback leaves tree wind disabled",
			not bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false)))
		_check("oak BLEND fallback retains its original material reference",
			static_mesh.get_surface_count() == 1
			and static_mesh.surface_get_material(0) == oak_material)
		checked_static_source = true
	_check("oak BLEND fallback emits its static source mesh", checked_static_source)
	static_root.free()


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
		ImportedVegetation.queue(batches, TREE_SAMPLE_ID, transform, index + 10, damage_id,
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
		if not str(instance.name).begins_with(TREE_SAMPLE_PREFIX):
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
		if not str(instance.name).begins_with(TREE_SAMPLE_PREFIX):
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
	if _tree_state_bounds_count(root, TREE_SAMPLE_ID) != expected_instance_count:
		return false
	var has_cull_bounds := false
	var cull_bounds := AABB()
	var expected_cells: Dictionary = {}
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {})
	for record: Dictionary in state.get("bounds", []):
		if str(record.get("asset_id", "")) != TREE_SAMPLE_ID or bool(record.get("hidden", false)):
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
		_tree_state_bounds(root, TREE_SAMPLE_ID)
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
		if not child is MultiMeshInstance3D or not str(child.name).begins_with(TREE_SAMPLE_PREFIX):
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
		if not child is MultiMeshInstance3D or not str(child.name).begins_with(TREE_SAMPLE_PREFIX):
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
		if str(record.get("asset_id", "")) != TREE_SAMPLE_ID:
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


func _test_tree_texture_imports() -> void:
	# Regression: headless editor imports silently kept the four 3D maps without mips.
	# Pinned settings protect fresh checkouts; native execution checks decoded resources.
	for filename in ["Bark_NormalTree.png", "Bark_NormalTree_Normal.png", "Leaves_NormalTree_C.png", "Leaf_Pine_C.png"]:
		var path: String = "res://assets/landscape/vegetation/models/" + filename
		var settings := ConfigFile.new()
		var loaded := settings.load(path + ".import") == OK
		_check(filename + " has a pinned import recipe", loaded)
		if not loaded:
			continue
		_check(filename + " keeps its reviewed mip policy and lossless full-size import",
			settings.get_value("params", "mipmaps/generate", null) == filename.begins_with("Bark_")
			and settings.get_value("params", "mipmaps/limit", 0) == -1
			and settings.get_value("params", "compress/mode", -1) == 0
			and settings.get_value("params", "process/size_limit", -1) == 0
			and settings.get_value("params", "detect_3d/compress_to", -1) == 0)
		var expected_normal := 1 if filename == "Bark_NormalTree_Normal.png" else 2
		_check(filename + " declares color or renormalized normal-map mip semantics",
			settings.get_value("params", "compress/normal_map", -1) == expected_normal)
		_check(filename + " retains straight alpha, repaired borders and original normal direction",
			settings.get_value("params", "process/fix_alpha_border", false)
			and not settings.get_value("params", "process/premult_alpha", true)
			and not settings.get_value("params", "process/normal_map_invert_y", true))
		if DisplayServer.get_name() == "headless":
			continue # Dummy cannot establish native texture readback or GPU sampling.
		var texture := load(path) as Texture2D
		_check(filename + " loads a native texture", texture != null)
		if texture == null:
			continue
		var picture := texture.get_image()
		_check(filename + " has native image data", picture != null and not picture.is_empty())
		if picture == null or picture.is_empty():
			continue
		var dimension := 1024 if filename == "Leaves_NormalTree_C.png" else 2048
		var levels := 11 if filename.begins_with("Bark_") else 0
		_check(filename + " retains source dimensions and its complete mip chain",
			picture.get_width() == dimension and picture.get_height() == dimension
			and picture.get_mipmap_count() == levels and picture.has_mipmaps() == (levels > 0))
