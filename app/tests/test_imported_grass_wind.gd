## L15c source fidelity, exclusion envelope and material lifetime contracts.
## Rendering/clock parity is verified separately with tools/grass/material_capture.gd.
extends SceneTree

const PlantLibrary := preload("res://scenery/imported_vegetation.gd")
const GrassMaterial := preload("res://scenery/imported_grass_material.gd")
const NearGrass := preload("res://scenery/imported_near_grass.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const ImportedNearGrass := preload("res://scenery/imported_near_grass.gd")
const GrassQuality := preload("res://render/grass_quality.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GRASS_QUALITY_ENV := "OPENRC_GRASS_QUALITY"

const ASSET_IDS: Array[String] = [
	"grass_common_short",
	"grass_common_tall",
	"grass_wispy_tall",
]
const TEST_HEIGHTS: Array[float] = [0.12, 0.16, 0.22, 0.25]
const TEST_YAWS: Array[float] = [0.0, 0.37, PI * 0.5, TAU - 0.01]
const FLOAT_EPSILON := 0.00001

var _checks := 0
var _failures := 0
var _field: Dictionary = {}


func _initialize() -> void:
	var previous_quality := OS.get_environment(GRASS_QUALITY_ENV)
	OS.set_environment(GRASS_QUALITY_ENV, "")
	_check("default environment keeps the downloaded grass on its static material path", not GrassQuality.enhanced())
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads for the integrated static-route contract", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if bool(loaded.get("ok", false)):
		_field = loaded.field
		_test_mode(false)
	OS.set_environment(GRASS_QUALITY_ENV, "enhanced")
	_check("enhanced route is an explicit process-local opt-in", GrassQuality.enhanced())
	if bool(loaded.get("ok", false)):
		_test_mode(true)
	OS.set_environment(GRASS_QUALITY_ENV, previous_quality)
	print("%d imported-grass wind checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_mode(expect_enhanced: bool) -> void:
	if expect_enhanced:
		_test_shader_contract()
	for asset_id: String in ASSET_IDS:
		_test_asset_build_and_material_fidelity(asset_id, expect_enhanced)
		_test_bounds_clearance_and_margin(asset_id, expect_enhanced)
	_test_integrated_quality_route(expect_enhanced)
	if not expect_enhanced:
		return
	_test_private_materials_across_builds()
	_test_unsupported_material_rejection("normal map")
	_test_unsupported_material_rejection("alpha scissor")
	_test_unsupported_material_rejection("sRGB vertex color")
	_test_unsupported_material_rejection("metallic texture")
	_test_unsupported_material_rejection("roughness texture")
	_test_unsupported_material_rejection("missing albedo texture")
	_test_unsupported_material_rejection("disabled fog")
	var expected_unsupported_features: Array[String] = [
		"normal_enabled", "bent_normal_enabled", "emission_enabled", "rim_enabled", "clearcoat_enabled",
		"anisotropy_enabled", "ao_enabled", "backlight_enabled", "heightmap_enabled",
		"subsurf_scatter_enabled", "subsurf_scatter_transmittance_enabled", "refraction_enabled",
		"detail_enabled", "albedo_texture_msdf", "disable_specular_occlusion", "shadow_to_opacity",
		"proximity_fade_enabled", "uv1_world_triplanar", "uv2_world_triplanar", "billboard_keep_scale",
		"fixed_size", "use_point_size", "use_particle_trails", "use_z_clip_scale", "use_fov_override", "grow",
	]
	_check("unsupported material mutation matrix explicitly matches adapter guards",
		expected_unsupported_features == GrassMaterial.UNSUPPORTED_MATERIAL_FEATURES)
	for feature_name: String in expected_unsupported_features:
		_test_unsupported_material_property_rejection(feature_name, true)
	var unsupported_settings: Array[Dictionary] = [
		{"name": "ORM texture", "property": "orm_texture"},
		{"name": "render priority", "property": "render_priority", "value": 1},
		{"name": "inverted depth test", "property": "depth_test", "value": BaseMaterial3D.DEPTH_TEST_INVERTED},
		{"name": "distance fade", "property": "distance_fade_mode", "value": BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA},
		{"name": "billboard mode", "property": "billboard_mode", "value": BaseMaterial3D.BILLBOARD_ENABLED},
		{"name": "stencil mode", "property": "stencil_mode", "value": BaseMaterial3D.STENCIL_MODE_OUTLINE},
		{"name": "next pass", "property": "next_pass", "value": StandardMaterial3D.new()},
		{"name": "disabled texture repeat", "property": "texture_repeat", "value": false},
		{"name": "UV1 triplanar mapping", "property": "uv1_triplanar", "value": true},
		{"name": "UV2 triplanar mapping", "property": "uv2_triplanar", "value": true},
	]
	for setting: Dictionary in unsupported_settings:
		_test_unsupported_material_property_rejection(str(setting.name), setting.get("value"), str(setting.property))
	_test_nonuniform_scale_rejection()
	_test_queue_normalizes_nonuniform_scale()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _test_shader_contract() -> void:
	var shader := load("res://scenery/imported_grass.gdshader") as Shader
	_check("grass-only shader loads", shader != null)
	if shader == null:
		return
	var code := shader.code
	_check("shader retains source double-sided Burley/Schlick opaque modes",
		code.contains("render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;"))
	_check("shader uses source-color mipmapped repeating albedo sampling",
		code.contains("source_color, filter_linear_mipmap, repeat_enable"))
	_check("wind magnitude is clamped to the audited 0.12 displacement ratio",
		code.contains("clamp(wind_strength, 0.0, 0.12)"))
	_check("zero-wind imported vertex-color contract is represented by a false default",
		code.contains("uniform bool use_vertex_color = false;"))
	_check("vertex-color sRGB conversion is absent and must remain rejected if requested",
		not code.contains("vertex_color_is_srgb") and not code.contains("srgb_to_linear"))
	_check("grass shader has no unused root-darkening parameter",
		not code.contains("root_darkening"))


func _test_asset_build_and_material_fidelity(asset_id: String, expect_enhanced: bool) -> void:
	var parts: Array[Dictionary] = PlantLibrary.get_parts(asset_id)
	var asset: Dictionary = PlantLibrary.get_asset(asset_id)
	_check("%s source part loads" % asset_id, not parts.is_empty())
	if parts.is_empty():
		return
	var queued: Dictionary = _queue_test_transforms(asset_id)
	var root := PlantLibrary.build(queued, false)
	var nodes := _batch_nodes(root)
	_check("%s build emits all source part batches" % asset_id, nodes.size() == parts.size())
	if nodes.size() != parts.size():
		root.free()
		return
	var expected_triangles := 0
	for part: Dictionary in parts:
		expected_triangles += _triangle_count(part.get("mesh") as Mesh)
	var output_triangles := 0
	var captured_transforms: Array[Transform3D] = _state_transforms_for_asset(root, asset_id)
	var built_transforms_match_queue := _state_transforms_match_queue(root, queued, parts, asset_id)
	for node_value: Variant in nodes:
		var node := node_value as MultiMeshInstance3D
		var part_index := int(node.name.get_slice("_Part_", 1))
		var part: Dictionary = parts[part_index]
		var source_mesh := part.get("mesh") as Mesh
		var draw_mesh := node.multimesh.mesh
		_check("%s part %d uses a private draw-mesh duplicate" % [asset_id, part_index], draw_mesh != source_mesh)
		_check("%s part %d surface count preserved" % [asset_id, part_index], draw_mesh.get_surface_count() == source_mesh.get_surface_count())
		_check("%s part %d receives every supported scale/yaw instance" % [asset_id, part_index], node.multimesh.instance_count == TEST_HEIGHTS.size())
		output_triangles += _triangle_count(draw_mesh)
		for surface_index in range(source_mesh.get_surface_count()):
			var source_material := source_mesh.surface_get_material(surface_index) as StandardMaterial3D
			_check("%s source surface %d is a StandardMaterial3D" % [asset_id, surface_index], source_material != null)
			_check("%s source surface %d has the expected opaque double-sided material" % [asset_id, surface_index],
				source_material != null and source_material.cull_mode == BaseMaterial3D.CULL_DISABLED
				and source_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				and source_material.diffuse_mode == BaseMaterial3D.DIFFUSE_BURLEY
				and source_material.specular_mode == BaseMaterial3D.SPECULAR_SCHLICK_GGX)
			_check("%s source surface %d does not use unsupported normal/alpha features" % [asset_id, surface_index],
				source_material != null and not source_material.normal_enabled
				and source_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	var adaptation_ok := GrassMaterial.apply(root) if expect_enhanced else false
	_check("%s selected route matches the explicit quality mode" % asset_id,
		GrassQuality.enhanced() == expect_enhanced
		and (adaptation_ok if expect_enhanced else not root.has_meta("grass_wind")))
	var geometry_preserved := true
	var static_materials_preserved := true
	for node_value: Variant in nodes:
		var node := node_value as MultiMeshInstance3D
		var part_index := int(node.name.get_slice("_Part_", 1))
		var source_mesh := parts[part_index].get("mesh") as Mesh
		var draw_mesh := node.multimesh.mesh
		for surface_index in range(source_mesh.get_surface_count()):
			geometry_preserved = geometry_preserved and _surface_geometry_equal(source_mesh, draw_mesh, surface_index)
			var source_material := source_mesh.surface_get_material(surface_index) as StandardMaterial3D
			var actual_material := draw_mesh.surface_get_material(surface_index)
			if not expect_enhanced:
				static_materials_preserved = static_materials_preserved and actual_material == source_material
				continue
			var output_material := actual_material as ShaderMaterial
			_check("%s surface %d enhanced route converts to the qualified ShaderMaterial" % [asset_id, surface_index], output_material != null)
			if output_material == null or source_material == null:
				static_materials_preserved = false
				continue
			_check("%s surface %d albedo texture copied by identity" % [asset_id, surface_index],
				output_material.get_shader_parameter("albedo_texture") == source_material.albedo_texture)
			_check("%s surface %d albedo color copied" % [asset_id, surface_index],
				_approximately_equal(output_material.get_shader_parameter("albedo_color"), source_material.albedo_color))
			_check("%s surface %d vertex-color flag matches effective source" % [asset_id, surface_index],
				bool(output_material.get_shader_parameter("use_vertex_color")) == source_material.vertex_color_use_as_albedo)
			_check("%s surface %d UV1 scale/offset copied" % [asset_id, surface_index],
				_approximately_equal(output_material.get_shader_parameter("uv1_scale"), Vector2(source_material.uv1_scale.x, source_material.uv1_scale.y))
				and _approximately_equal(output_material.get_shader_parameter("uv1_offset"), Vector2(source_material.uv1_offset.x, source_material.uv1_offset.y)))
			_check("%s surface %d roughness/metallic/specular copied" % [asset_id, surface_index],
				_approximately_equal(output_material.get_shader_parameter("roughness"), source_material.roughness)
				and _approximately_equal(output_material.get_shader_parameter("metallic"), source_material.metallic)
				and _approximately_equal(output_material.get_shader_parameter("specular"), source_material.metallic_specular))
	_check("%s source triangle count unchanged by material conversion" % asset_id, output_triangles == expected_triangles)
	_check("%s vertex/normal/tangent/UV/index arrays remain unchanged" % asset_id, geometry_preserved)
	_check("%s default route preserves every imported source material reference" % asset_id,
		expect_enhanced or static_materials_preserved)
	_check("%s enhanced route marks only the grass root for wind" % asset_id,
		bool(root.has_meta("grass_wind")) == expect_enhanced)
	_check("%s source placement transforms remain unchanged by material conversion" % asset_id,
		_transform_lists_equal(captured_transforms, _state_transforms_for_asset(root, asset_id)))
	_check("%s all queued uniform-scale/yaw transforms reach their MultiMesh batches" % asset_id, built_transforms_match_queue)
	root.free()


func _test_bounds_clearance_and_margin(asset_id: String, expect_enhanced: bool) -> void:
	var parts: Array[Dictionary] = PlantLibrary.get_parts(asset_id)
	var asset: Dictionary = PlantLibrary.get_asset(asset_id)
	if parts.is_empty() or asset.is_empty():
		_check("%s bounds data available" % asset_id, false)
		return
	var source_height := float(asset.get("source_bounds_m", {}).get("height", 0.0))
	var max_scale := NearGrass.MAX_HEIGHT_M / maxf(source_height, 0.000001)
	var max_radius := 0.0
	var max_shader_displacement := 0.0
	var supported_part_transforms := true
	for part: Dictionary in parts:
		var mesh := part.get("mesh") as Mesh
		var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		supported_part_transforms = supported_part_transforms and _is_uniform_yaw_transform(part_transform)
		var bounds: AABB = part.get("bounds", AABB())
		var max_blade_height := 0.0
		for surface_index in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := part_transform * vertex
				max_radius = maxf(max_radius, Vector2(point.x, point.z).length())
				var normalized_height := clampf((vertex.y - bounds.position.y) / maxf(bounds.size.y, 0.001), 0.0, 1.0)
				max_blade_height = maxf(max_blade_height, normalized_height)
		max_shader_displacement = maxf(max_shader_displacement, bounds.size.y * part_transform.basis.y.length() * max_scale * GrassMaterial.MAX_BEND_RATIO * max_blade_height * max_blade_height)
	var total_exclusion_envelope := max_radius * max_scale + max_shader_displacement
	_check("%s source part transform is in supported uniform-scale/yaw family" % asset_id, supported_part_transforms)
	_check("%s maximum geometric radius plus 0.12 wind stays inside 0.4 m mask clearance" % asset_id,
		total_exclusion_envelope <= GrassMask.CLEARANCE_M + FLOAT_EPSILON,
		"radius=%.5f wind=%.5f envelope=%.5f clearance=%.5f" % [max_radius * max_scale, max_shader_displacement, total_exclusion_envelope, GrassMask.CLEARANCE_M])
	var root := PlantLibrary.build(_queue_test_transforms(asset_id), false)
	var adaptation_ok := GrassMaterial.apply(root) if expect_enhanced else false
	_check("%s bounds fixture follows selected material route" % asset_id,
		adaptation_ok == expect_enhanced and bool(root.has_meta("grass_wind")) == expect_enhanced)
	var margin_valid := true
	var margin_matches_bound := true
	for node_value: Variant in _batch_nodes(root):
		var node := node_value as MultiMeshInstance3D
		var part_index := int(node.name.get_slice("_Part_", 1))
		var bounds: AABB = parts[part_index].get("bounds", AABB())
		var expected_margin := 0.0
		if expect_enhanced:
			for transform: Transform3D in _state_transforms_for_asset(root, asset_id):
				var scale := transform.basis.y.length()
				expected_margin = maxf(expected_margin, bounds.size.y * scale * GrassMaterial.MAX_BEND_RATIO)
			margin_valid = margin_valid and node.extra_cull_margin + FLOAT_EPSILON >= expected_margin
			margin_matches_bound = margin_matches_bound and _approximately_equal(node.extra_cull_margin, expected_margin)
			margin_matches_bound = margin_matches_bound and _approximately_equal(float(node.get_meta("grass_wind_max_displacement_m", -1.0)), expected_margin)
		else:
			margin_valid = margin_valid and _approximately_equal(node.extra_cull_margin, 0.0)
			margin_matches_bound = margin_matches_bound and not node.has_meta("grass_wind_max_displacement_m")
	_check("%s cull margin follows the selected route and bounds 0.12 wind only when enhanced" % asset_id, margin_valid)
	_check("%s displacement metadata is present only on enhanced grass batches" % asset_id, margin_matches_bound)
	root.free()


func _test_integrated_quality_route(expect_enhanced: bool) -> void:
	var root := ImportedNearGrass.build(_field, "high")
	var route_ok := root != null and bool(root.has_meta("grass_wind")) == expect_enhanced
	var batch_count := 0
	if root != null:
		for child: Node in root.get_children():
			if not child is MultiMeshInstance3D:
				route_ok = false
				continue
			batch_count += 1
			var batch := child as MultiMeshInstance3D
			var mesh := batch.multimesh.mesh if batch.multimesh != null else null
			if mesh == null:
				route_ok = false
				continue
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index)
				if expect_enhanced:
					route_ok = route_ok and material is ShaderMaterial
				else:
					route_ok = route_ok and material is StandardMaterial3D
		_check("integrated high-tier build uses %s material route" % ("enhanced grass-only" if expect_enhanced else "original static"),
			GrassQuality.enhanced() == expect_enhanced and route_ok and batch_count > 0,
			"batches=%d grass_wind=%s" % [batch_count, str(root.has_meta("grass_wind") if root != null else false)])
		if root != null:
			root.free()


func _test_private_materials_across_builds() -> void:
	var first := _build_asset_root(ASSET_IDS[0])
	var second := _build_asset_root(ASSET_IDS[0])
	var first_applied := GrassMaterial.apply(first)
	var second_applied := GrassMaterial.apply(second)
	_check("both independent source builds pass adapter validation", first_applied and second_applied)
	var first_node := _first_batch(first)
	var second_node := _first_batch(second)
	var first_mesh := first_node.multimesh.mesh
	var second_mesh := second_node.multimesh.mesh
	var first_material := first_mesh.surface_get_material(0) as ShaderMaterial
	var second_material := second_mesh.surface_get_material(0) as ShaderMaterial
	_check("two grass builds own different ArrayMesh resources", first_mesh != second_mesh)
	_check("two grass builds own different ShaderMaterial resources", first_material != second_material)
	_check("both private materials use the same immutable shader resource", first_material.shader == second_material.shader)
	_check("both builds intentionally share the source albedo texture", first_material.get_shader_parameter("albedo_texture") == second_material.get_shader_parameter("albedo_texture"))
	second_material.set_shader_parameter("roughness", 1.0)
	first_material.set_shader_parameter("roughness", 0.25)
	_check("changing one build's shader uniforms cannot mutate the other build",
		_approximately_equal(first_material.get_shader_parameter("roughness"), 0.25)
		and _approximately_equal(second_material.get_shader_parameter("roughness"), 1.0))
	first.free()
	second.free()


func _test_unsupported_material_rejection(feature: String) -> void:
	var parts: Array[Dictionary] = PlantLibrary.get_parts(ASSET_IDS[0])
	if parts.is_empty():
		_check("adapter source material available for unsupported %s case" % feature, false)
		return
	var materials: Array = parts[0].get("materials", [])
	var material := materials[0] as StandardMaterial3D if not materials.is_empty() else null
	if material == null:
		_check("adapter source material available for unsupported %s case" % feature, false)
		return
	var previous_normal_enabled := material.normal_enabled
	var previous_normal_texture := material.normal_texture
	var previous_transparency := material.transparency
	var previous_alpha_threshold := material.alpha_scissor_threshold
	var previous_vertex_color_use := material.vertex_color_use_as_albedo
	var previous_vertex_color_srgb := material.vertex_color_is_srgb
	var previous_metallic_texture := material.metallic_texture
	var previous_roughness_texture := material.roughness_texture
	var previous_albedo_texture := material.albedo_texture
	var previous_disable_fog := material.get_flag(BaseMaterial3D.FLAG_DISABLE_FOG)
	match feature:
		"normal map":
			material.normal_enabled = true
			material.normal_texture = material.albedo_texture
		"alpha scissor":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.42
		"sRGB vertex color":
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = true
		"metallic texture":
			material.metallic_texture = material.albedo_texture
		"roughness texture":
			material.roughness_texture = material.albedo_texture
		"missing albedo texture":
			material.albedo_texture = null
		"disabled fog":
			material.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG, true)
	var root := _build_asset_root(ASSET_IDS[0])
	var node := _first_batch(root)
	var snapshot := _capture_static_root(root)
	var mesh := node.multimesh.mesh
	var accepted := _apply_expected_rejection(root)
	var output := mesh.surface_get_material(0)
	_check("adapter rejects unsupported %s instead of silently dropping it" % feature,
		not accepted and output == material and _static_root_matches_snapshot(root, snapshot, material),
		"accepted=%s, adapter output class=%s, grass_wind_meta=%s" % [str(accepted), str(output.get_class()) if output != null else "null", str(root.has_meta("grass_wind"))])
	root.free()
	material.normal_enabled = previous_normal_enabled
	material.normal_texture = previous_normal_texture
	material.transparency = previous_transparency
	material.alpha_scissor_threshold = previous_alpha_threshold
	material.vertex_color_use_as_albedo = previous_vertex_color_use
	material.vertex_color_is_srgb = previous_vertex_color_srgb
	material.metallic_texture = previous_metallic_texture
	material.roughness_texture = previous_roughness_texture
	material.albedo_texture = previous_albedo_texture
	material.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG, previous_disable_fog)


func _test_unsupported_material_property_rejection(label: String, value: Variant, property_name: String = "") -> void:
	var feature_name := property_name if not property_name.is_empty() else label
	var parts: Array[Dictionary] = PlantLibrary.get_parts(ASSET_IDS[0])
	var materials: Array = parts[0].get("materials", []) if not parts.is_empty() else []
	var material := materials[0] as StandardMaterial3D if not materials.is_empty() else null
	if material == null:
		_check("adapter source material available for unsupported %s case" % label, false)
		return
	var previous_value: Variant = material.get(feature_name)
	var mutation_value: Variant = material.albedo_texture if feature_name == "orm_texture" else value
	material.set(feature_name, mutation_value)
	var mutation_applied: bool = material.get(feature_name) == mutation_value
	var root := _build_asset_root(ASSET_IDS[0])
	var snapshot := _capture_static_root(root)
	var accepted := _apply_expected_rejection(root)
	_check("adapter rejects unsupported %s instead of silently dropping it" % label,
		mutation_applied and not accepted and _static_root_matches_snapshot(root, snapshot, material, feature_name, mutation_value),
		"mutation_applied=%s accepted=%s property=%s" % [str(mutation_applied), str(accepted), feature_name])
	root.free()
	material.set(feature_name, previous_value)


func _capture_static_root(root: Node3D) -> Dictionary:
	var batches := _batch_nodes(root)
	var multimeshes: Array = []
	var meshes: Array = []
	var margins: Array = []
	for batch: MultiMeshInstance3D in batches:
		multimeshes.append(batch.multimesh)
		meshes.append(batch.multimesh.mesh if batch.multimesh != null else null)
		margins.append(batch.extra_cull_margin)
	var source_state: Dictionary = root.get_meta("_imported_vegetation_state")
	return {
		"state": source_state.duplicate(true),
		"batches": batches,
		"multimeshes": multimeshes,
		"meshes": meshes,
		"margins": margins,
	}


func _static_root_matches_snapshot(
	root: Node3D,
	snapshot: Dictionary,
	source_material: StandardMaterial3D,
	property_name: String = "",
	expected_property_value: Variant = null
) -> bool:
	var batches: Array = snapshot.get("batches", [])
	if root.has_meta("grass_wind") or root.get_child_count() != batches.size():
		return false
	if not root.has_meta("_imported_vegetation_state") or root.get_meta("_imported_vegetation_state") != snapshot.get("state"):
		return false
	if not property_name.is_empty() and source_material.get(property_name) != expected_property_value:
		return false
	var multimeshes: Array = snapshot.get("multimeshes", [])
	var meshes: Array = snapshot.get("meshes", [])
	var margins: Array = snapshot.get("margins", [])
	var current_batches := _batch_nodes(root)
	if current_batches.size() != batches.size():
		return false
	for index in range(current_batches.size()):
		var batch: MultiMeshInstance3D = current_batches[index]
		if batch != batches[index] or batch.multimesh != multimeshes[index]:
			return false
		if batch.multimesh == null or batch.multimesh.mesh != meshes[index]:
			return false
		if not _approximately_equal(batch.extra_cull_margin, float(margins[index])):
			return false
		if batch.has_meta("grass_wind_max_displacement_m"):
			return false
		if batch.multimesh.mesh.surface_get_material(0) != source_material:
			return false
	return true


## Only these deliberate rejection calls suppress their expected push_error output.
## Successful adaptation and every other test keep engine error reporting enabled.
func _apply_expected_rejection(root: Node3D) -> bool:
	var previous := Engine.print_error_messages
	Engine.print_error_messages = false
	var accepted := GrassMaterial.apply(root)
	Engine.print_error_messages = previous
	return accepted


func _test_nonuniform_scale_rejection() -> void:
	var root := _build_asset_root(ASSET_IDS[0])
	var node := _first_batch(root)
	var state: Dictionary = root.get_meta("_imported_vegetation_state")
	var bounds_records: Array = state.get("bounds", [])
	var first_record: Dictionary = bounds_records[0]
	var original: Transform3D = first_record.get("transform", Transform3D.IDENTITY)
	var yaw := original.basis.orthonormalized()
	var nonuniform := Transform3D(yaw * Basis.from_scale(Vector3(1.5, 1.0, 0.75)), original.origin)
	first_record["transform"] = nonuniform
	bounds_records[0] = first_record
	state["bounds"] = bounds_records
	root.set_meta("_imported_vegetation_state", state)
	_check("nonuniform fixture differs on all three scale axes", absf(nonuniform.basis.x.length() - nonuniform.basis.y.length()) > FLOAT_EPSILON
		and absf(nonuniform.basis.z.length() - nonuniform.basis.y.length()) > FLOAT_EPSILON)
	_check("adapter transform predicate rejects a nonuniform scale", not GrassMaterial._is_positive_uniform_yaw(nonuniform.basis))
	var source_material := node.multimesh.mesh.surface_get_material(0)
	var accepted := _apply_expected_rejection(root)
	_check("adapter rejects nonuniform raw MultiMesh scale whose cull envelope it cannot bound",
		not accepted and node.multimesh.mesh.surface_get_material(0) == source_material and not root.has_meta("grass_wind"),
		"accepted=%s, nonuniform scales x/y/z=%.3f/%.3f/%.3f" % [str(accepted), nonuniform.basis.x.length(), nonuniform.basis.y.length(), nonuniform.basis.z.length()])
	root.free()


func _test_queue_normalizes_nonuniform_scale() -> void:
	var asset_id := ASSET_IDS[0]
	var transform := Transform3D(Basis(Vector3.UP, 0.61) * Basis.from_scale(Vector3(0.12, 0.18, 0.24)), Vector3(2.0, 0.0, -3.0))
	var batches: Dictionary = {}
	var queued_id := PlantLibrary.queue(batches, asset_id, transform, 94)
	var normalized: Transform3D = batches[queued_id][0].get("transform", Transform3D.IDENTITY)
	_check("library normalizes a nonuniform requested scale before the grass adapter sees it",
		queued_id == asset_id and _basis_is_uniform_yaw(normalized.basis),
		"normalized axis scales=%.6f/%.6f/%.6f" % [normalized.basis.x.length(), normalized.basis.y.length(), normalized.basis.z.length()])


func _queue_test_transforms(asset_id: String) -> Dictionary:
	var batches: Dictionary = {}
	var asset: Dictionary = PlantLibrary.get_asset(asset_id)
	var source_height := float(asset.get("source_bounds_m", {}).get("height", 0.0))
	for index in range(TEST_HEIGHTS.size()):
		var scale := TEST_HEIGHTS[index] / maxf(source_height, 0.000001)
		var origin := Vector3(float(index) * 1.7, 0.0, -float(index) * 0.8)
		var placement := Transform3D(Basis(Vector3.UP, TEST_YAWS[index]) * Basis.from_scale(Vector3.ONE * scale), origin)
		var fitted := PlantLibrary.fit_to_height(asset_id, TEST_HEIGHTS[index], placement)
		PlantLibrary.queue(batches, asset_id, fitted, 780 + index)
	return batches


func _build_asset_root(asset_id: String) -> Node3D:
	return PlantLibrary.build(_queue_test_transforms(asset_id), false)


func _batch_nodes(root: Node3D) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D:
			result.append(child as MultiMeshInstance3D)
	result.sort_custom(func(left: MultiMeshInstance3D, right: MultiMeshInstance3D) -> bool: return left.name < right.name)
	return result


func _first_batch(root: Node3D) -> MultiMeshInstance3D:
	var nodes := _batch_nodes(root)
	return nodes[0] if not nodes.is_empty() else null


func _state_transforms_for_asset(root: Node3D, asset_id: String) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if not root.has_meta("_imported_vegetation_state"):
		return result
	var state: Dictionary = root.get_meta("_imported_vegetation_state")
	for record_value: Variant in state.get("bounds", []):
		if record_value is Dictionary and str(record_value.get("asset_id", "")) == asset_id:
			result.append(record_value.get("transform", Transform3D.IDENTITY))
	return result


func _state_transforms_match_queue(root: Node3D, queued: Dictionary, parts: Array[Dictionary], asset_id: String) -> bool:
	var actual := _state_transforms_for_asset(root, asset_id)
	var expected: Array[Transform3D] = []
	var records: Array = queued.get(asset_id, [])
	for part: Dictionary in parts:
		var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		for record: Dictionary in records:
			expected.append(record.get("transform", Transform3D.IDENTITY) * part_transform)
	return _transform_lists_equal(expected, actual)


func _transform_lists_equal(left: Array[Transform3D], right: Array[Transform3D]) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not _transform_equal(left[index], right[index]):
			return false
	return true


func _transform_equal(left: Transform3D, right: Transform3D) -> bool:
	return _approximately_equal(left.origin, right.origin) and _approximately_equal(left.basis.x, right.basis.x) \
		and _approximately_equal(left.basis.y, right.basis.y) and _approximately_equal(left.basis.z, right.basis.z)


func _surface_geometry_equal(source: Mesh, output: Mesh, surface_index: int) -> bool:
	if source.get_surface_count() != output.get_surface_count():
		return false
	var source_arrays := source.surface_get_arrays(surface_index)
	var output_arrays := output.surface_get_arrays(surface_index)
	if source_arrays.size() != output_arrays.size():
		return false
	for slot in range(source_arrays.size()):
		if source_arrays[slot] != output_arrays[slot]:
			return false
	return true


func _triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var result := 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		result += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return result


func _is_uniform_yaw_transform(transform: Transform3D) -> bool:
	return _basis_is_uniform_yaw(transform.basis)


func _basis_is_uniform_yaw(basis: Basis) -> bool:
	var x_scale := basis.x.length()
	var y_scale := basis.y.length()
	var z_scale := basis.z.length()
	if minf(x_scale, minf(y_scale, z_scale)) <= 0.000001:
		return false
	var orthogonal := absf(basis.x.normalized().dot(basis.y.normalized())) < FLOAT_EPSILON \
		and absf(basis.x.normalized().dot(basis.z.normalized())) < FLOAT_EPSILON \
		and absf(basis.y.normalized().dot(basis.z.normalized())) < FLOAT_EPSILON
	var yaw_only := absf(basis.y.normalized().dot(Vector3.UP)) > 1.0 - FLOAT_EPSILON
	return orthogonal and yaw_only and _approximately_equal(x_scale, y_scale) and _approximately_equal(y_scale, z_scale)


func _approximately_equal(left: Variant, right: Variant) -> bool:
	if left is Color and right is Color:
		return absf(left.r - right.r) < FLOAT_EPSILON and absf(left.g - right.g) < FLOAT_EPSILON \
			and absf(left.b - right.b) < FLOAT_EPSILON and absf(left.a - right.a) < FLOAT_EPSILON
	if left is Vector2 and right is Vector2:
		return left.distance_to(right) < FLOAT_EPSILON
	if left is Vector3 and right is Vector3:
		return left.distance_to(right) < FLOAT_EPSILON
	if left is int or left is float:
		return (right is int or right is float) and absf(float(left) - float(right)) < FLOAT_EPSILON
	return left == right
