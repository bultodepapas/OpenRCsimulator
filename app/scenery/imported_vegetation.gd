class_name ImportedVegetation
extends RefCounted

const CATALOG_PATH := "res://assets/landscape/vegetation/catalog.json"
const WIND_SHADER_PATH := "res://scenery/imported_vegetation_wind.gdshader"
const DEFAULT_WIND_STRENGTH := 0.025
const TREE_CELL_SIZES_M := [64, 128, 256]
# L15b-R2 tree-wind variants, keyed by source cull mode and texture repeat.
const TREE_WIND_SHADER_PATHS := {
	"double_repeat": "res://scenery/imported_tree_wind.gdshader",
	"back_repeat": "res://scenery/imported_tree_wind_cull_back.gdshader",
	"double_clamp": "res://scenery/imported_tree_wind_clamp.gdshader",
}
# Largest crown-top sway (m) keeping every displaced source vertex inside the existing
# collision proxies (VegetationPlacement wind_margin) at the smallest placed height.
# test_imported_tree_rendering.gd recomputes the bound from the imported vertices.
# Unlisted trees, including the protected clubhouse maple, keep static source materials.
const TREE_WIND_LEAN_LIMITS_M := {
	"landscapelab_quercus": 0.12,
	"landscapelab_pine": 0.22,
	"landscapelab_fagus": 0.13,
	"landscapelab_quercus2": 0.15,
}
# Foliage normal tilt at full flutter; shading only, so it cannot change any envelope.
const LEAF_FLUTTER_TILT := 0.12
# L6c-R1: distant LandscapeLab crowns turned bare. MultiMesh LOD ignores per-instance scale
# (Fagus is authored 1 m tall), so these batches bias LOD by their largest instance scale.
# Generated LODs drop whole leaf cards at small geometric error, so foliage keeps only levels
# with at least FOLIAGE_LOD_MIN_FRACTION of its triangles. Averaged alpha mips past
# FOLIAGE_ALPHA_MAX_MIP fall under the cutoff on every LandscapeLab leaf atlas (box-filter
# coverage ratio 0.60-0.98 at mip 7 versus 1.00-1.11 through mip 6), so tree-wind foliage
# samples no coarser mip than that.
const WORLD_LOD_SOURCE_IDS := ["landscapelab_tree_2026"]
const FOLIAGE_LOD_MIN_FRACTION := 0.25
const FOLIAGE_ALPHA_MAX_MIP := 6.0

const ALIASES := {
	# Keep the seven alias slots: slot zero protects all four existing maples,
	# including the clubhouse specimen. Beech (Fagus) in slots two and four adds a
	# second broadleaf species; pine in slots three and six keeps the mixed grove,
	# and the prominent car-park oak in slot five stays Quercus. Saplings use the
	# young open-grown Quercus 2 rather than a scaled-down mature oak.
	"shade_tree": ["maple_tree", "landscapelab_quercus", "landscapelab_fagus", "landscapelab_pine", "landscapelab_fagus", "landscapelab_quercus", "landscapelab_pine"],
	"tree": ["maple_tree", "landscapelab_quercus", "landscapelab_fagus", "landscapelab_pine", "landscapelab_fagus", "landscapelab_quercus", "landscapelab_pine"],
	"sapling": ["landscapelab_quercus2", "landscapelab_pine", "landscapelab_quercus2", "landscapelab_pine"],
	"bush": [
		"bush_common_flowers", "bush_common_flowers", "bush_common_flowers", "bush_common_flowers",
		"bush_common_flowers", "bush_common_flowers", "bush_common_flowers", "bush_common",
	],
	"green_bush": ["bush_common_flowers"],
	"red_bush": ["bush_common"],
	"flower_clump": ["flower_3_group", "flower_4_group", "clover_1"],
	"grass": ["grass_common_short", "grass_common_tall", "grass_wispy_tall", "fern_1"],
	"herb": ["fern_1", "clover_1"],
	"crop": ["corn_4", "wheat_4"],
	"reed": ["reed_aredon"],
	"reeds": ["reed_aredon"],
}

static var _catalog_data: Dictionary = {}
static var _asset_index: Dictionary = {}
static var _parts_cache: Dictionary = {}
static var _wind_shader: Shader
static var _wind_material_cache: Dictionary = {}
static var _tree_wind_shaders: Dictionary = {}
static var _tree_wind_material_cache: Dictionary = {}
static var _foliage_shadow_mesh_cache: Dictionary = {}
static var _option_warnings: Dictionary = {}
static var _tree_wind_warnings: Dictionary = {}


static func catalog() -> Dictionary:
	_ensure_catalog()
	return _catalog_data.duplicate(true)


static func get_asset(asset_id: String) -> Dictionary:
	_ensure_catalog()
	var canonical_id := resolve_id(asset_id, 0)
	if canonical_id.is_empty():
		return {}
	return (_asset_index[canonical_id] as Dictionary).duplicate(true)


static func resolve_id(asset_id: String, seed: int = 0) -> String:
	_ensure_catalog()
	if _asset_index.has(asset_id):
		return asset_id
	var choices: Array = ALIASES.get(asset_id, [])
	if choices.is_empty():
		return ""
	var index := posmod(seed, choices.size())
	var selected := str(choices[index])
	return selected if _asset_index.has(selected) else ""


static func get_parts(asset_id: String) -> Array[Dictionary]:
	var canonical_id := resolve_id(asset_id, 0)
	if canonical_id.is_empty():
		return []
	if not _parts_cache.has(canonical_id):
		_parts_cache[canonical_id] = _load_parts(canonical_id)
	var result: Array[Dictionary] = []
	for part in _parts_cache[canonical_id]:
		result.append((part as Dictionary).duplicate(false))
	return result


static func fit_to_height(asset_id: String, target_height: float, placement: Transform3D = Transform3D.IDENTITY) -> Transform3D:
	var canonical_id := resolve_id(asset_id, 0)
	if canonical_id.is_empty() or target_height <= 0.0:
		return placement
	var asset: Dictionary = _asset_index[canonical_id]
	var source_bounds: Dictionary = asset.get("source_bounds_m", {})
	var source_height := float(source_bounds.get("height", 0.0))
	if source_height <= 0.0:
		return placement
	var uniform_scale := target_height / source_height
	var rotation := placement.basis.orthonormalized()
	return Transform3D(rotation * Basis.from_scale(Vector3.ONE * uniform_scale), placement.origin)


static func queue(
	batches: Dictionary,
	asset_id: String,
	placement: Transform3D,
	seed: int,
	damage_id: String = "",
	tint: Color = Color.WHITE
) -> String:
	var canonical_id := resolve_id(asset_id, seed)
	if canonical_id.is_empty():
		return ""
	var asset: Dictionary = _asset_index[canonical_id]
	var grounded := _ground_transform(asset, _uniformize_transform(placement))
	if not batches.has(canonical_id):
		batches[canonical_id] = []
	(batches[canonical_id] as Array).append({
		"transform": grounded,
		"seed": seed,
		"damage_id": damage_id,
		"tint": _bounded_instance_tint(tint),
	})
	return canonical_id


static func build(batches: Dictionary, enable_wind: bool = false, options: Dictionary = {}) -> Node3D:
	var tree_cell_size := _tree_cell_size_from_options(options)
	var tree_wind_requested := _tree_wind_from_options(options)
	var root := Node3D.new()
	root.name = "ImportedVegetationBatches"
	var wind_materials: Dictionary = {}
	var state := {
		"damage": {},
		"bounds": [],
		"multimeshes": [],
	}
	for asset_id_variant in batches.keys():
		var asset_id := str(asset_id_variant)
		var records: Array = batches[asset_id_variant]
		var parts := get_parts(asset_id)
		if parts.is_empty() or records.is_empty():
			continue
		var asset: Dictionary = _asset_index.get(asset_id, {})
		var role := str(asset.get("role", ""))
		var tree_opt_in := tree_wind_requested and role == "tree"
		var use_tree_wind := tree_opt_in and _tree_asset_wind_supported(asset_id, parts, records)
		var use_legacy_wind := enable_wind and not tree_opt_in
		var groups := _record_groups(records, tree_cell_size if role == "tree" else 0)
		var world_lod := WORLD_LOD_SOURCE_IDS.has(str(asset.get("source_id", "")))
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var source_mesh: Mesh = part.get("mesh")
			if source_mesh == null:
				continue
			var source_bounds: AABB = part.get("bounds", AABB())
			var source_height := float(asset.get("source_bounds_m", {}).get("height", 1.0))
			var lean_limit := float(TREE_WIND_LEAN_LIMITS_M.get(asset_id, 0.0)) if use_tree_wind else 0.0
			var draw_mesh: Mesh
			if use_tree_wind:
				draw_mesh = _prepare_tree_wind_mesh(source_mesh, part.get("materials", []), source_bounds, lean_limit)
			else:
				draw_mesh = _prepare_mesh(
					source_mesh,
					part.get("materials", []),
					source_height,
					source_bounds,
					use_legacy_wind,
					_wind_strength_for_role(role),
					wind_materials
				)
			if world_lod:
				draw_mesh = _without_sparse_foliage_lods(draw_mesh, part.get("materials", []))
			var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
			for group in groups:
				var cell_records: Array = group.get("records", [])
				if cell_records.is_empty():
					continue
				var multi_mesh := MultiMesh.new()
				multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
				multi_mesh.use_colors = true
				multi_mesh.use_custom_data = true
				multi_mesh.mesh = draw_mesh
				multi_mesh.instance_count = cell_records.size()
				var bounds_indices: Array[int] = []
				var has_cull_bounds := false
				var cull_bounds := AABB()
				var lod_scale := 0.0
				for instance_index in range(cell_records.size()):
					var record: Dictionary = cell_records[instance_index]
					var plant_transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
					var instance_transform := plant_transform * part_transform
					multi_mesh.set_instance_transform(instance_index, instance_transform)
					var axis_scale := instance_transform.basis.get_scale().abs()
					lod_scale = maxf(lod_scale, maxf(axis_scale.x, maxf(axis_scale.y, axis_scale.z)))
					var phase := fposmod(float(record.get("seed", 0)) * 0.61803398875, 1.0)
					multi_mesh.set_instance_custom_data(instance_index, Color(phase, 0.0, 0.0, 1.0))
					var instance_tint: Color = record.get("tint", Color.WHITE)
					multi_mesh.set_instance_color(instance_index, instance_tint)
					var damage_id := str(record.get("damage_id", ""))
					var render_bounds := _tree_wind_render_bounds(source_bounds, lean_limit, instance_transform) \
						if use_tree_wind else source_bounds
					var bounds_index := (state["bounds"] as Array).size()
					(state["bounds"] as Array).append({
						"asset_id": asset_id,
						"bounds": render_bounds,
						"transform": instance_transform,
						"damage_id": damage_id,
						"tint": instance_tint,
						"hidden": false,
					})
					bounds_indices.append(bounds_index)
					if use_tree_wind:
						var transformed_bounds := _transform_aabb(render_bounds, instance_transform)
						if not has_cull_bounds:
							cull_bounds = transformed_bounds
							has_cull_bounds = true
						else:
							cull_bounds = cull_bounds.merge(transformed_bounds)

				var instance := MultiMeshInstance3D.new()
				var cell: Vector2i = group.get("cell", Vector2i.ZERO)
				instance.name = "%s_Part_%02d" % [asset_id, part_index]
				if int(group.get("cell_size", 0)) > 0:
					instance.name += "_Cell_%d_%d" % [cell.x, cell.y]
				instance.multimesh = multi_mesh
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if world_lod and lod_scale > 0.0:
					# LOD error is authored in source units; the largest instance keeps the batch conservative.
					instance.lod_bias = lod_scale
				instance.set_meta("_imported_vegetation_wind_enabled", use_legacy_wind)
				instance.set_meta("_imported_vegetation_tree_wind_enabled", use_tree_wind)
				if use_tree_wind and has_cull_bounds:
					multi_mesh.custom_aabb = cull_bounds
					instance.custom_aabb = cull_bounds
				root.add_child(instance)
				(state["multimeshes"] as Array).append(multi_mesh)

				for instance_index in range(cell_records.size()):
					var record: Dictionary = cell_records[instance_index]
					var damage_id := str(record.get("damage_id", ""))
					if damage_id.is_empty():
						continue
					if not (state["damage"] as Dictionary).has(damage_id):
						(state["damage"] as Dictionary)[damage_id] = []
					((state["damage"] as Dictionary)[damage_id] as Array).append({
						"multimesh": multi_mesh,
						"index": instance_index,
						"transform": multi_mesh.get_instance_transform(instance_index),
						"bounds_index": bounds_indices[instance_index],
					})

	root.set_meta("_imported_vegetation_state", state)
	return root


static func set_damage_hidden(root: Node3D, damage_id: String, hidden: bool) -> bool:
	if not is_instance_valid(root) or not root.has_meta("_imported_vegetation_state"):
		return false
	var state: Dictionary = root.get_meta("_imported_vegetation_state")
	var damage: Dictionary = state.get("damage", {})
	if damage_id.is_empty() or not damage.has(damage_id):
		return false
	var zero_transform := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for item in damage[damage_id]:
		var multi_mesh: MultiMesh = item.get("multimesh")
		var index := int(item.get("index", -1))
		if multi_mesh == null or index < 0 or index >= multi_mesh.instance_count:
			continue
		multi_mesh.set_instance_transform(index, zero_transform if hidden else item.get("transform", Transform3D.IDENTITY))
		var bounds_index := int(item.get("bounds_index", -1))
		var bounds_records: Array = state.get("bounds", [])
		if bounds_index >= 0 and bounds_index < bounds_records.size():
			var bounds_record: Dictionary = bounds_records[bounds_index]
			bounds_record["hidden"] = hidden
			bounds_records[bounds_index] = bounds_record
		state["bounds"] = bounds_records
	root.set_meta("_imported_vegetation_state", state)
	return true


static func bounds(root: Node3D) -> AABB:
	if not is_instance_valid(root) or not root.has_meta("_imported_vegetation_state"):
		return AABB()
	var state: Dictionary = root.get_meta("_imported_vegetation_state")
	var have_bounds := false
	var result := AABB()
	for record in state.get("bounds", []):
		if bool(record.get("hidden", false)):
			continue
		var transformed := _transform_aabb(record.get("bounds", AABB()), record.get("transform", Transform3D.IDENTITY))
		if not have_bounds:
			result = transformed
			have_bounds = true
		else:
			result = result.merge(transformed)
	return result if have_bounds else AABB()


## Legacy all-role batches only. Tree wind follows the session's wind_vec, like the field cards.
static func set_wind(root: Node3D, strength: float, direction: Vector2 = Vector2(1.0, 0.0)) -> void:
	if not is_instance_valid(root):
		return
	var normalized_direction := direction.normalized()
	for child in root.get_children():
		if child is MultiMeshInstance3D and bool(child.get_meta("_imported_vegetation_wind_enabled", false)):
			_set_batch_wind_parameters(child as MultiMeshInstance3D, maxf(strength, 0.0), normalized_direction)


static func _set_batch_wind_parameters(instance: MultiMeshInstance3D, strength: float, direction: Vector2) -> void:
	if instance.multimesh == null or instance.multimesh.mesh == null:
		return
	var mesh := instance.multimesh.mesh
	for surface_index in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface_index)
		if not material is ShaderMaterial or (material as ShaderMaterial).shader != _wind_shader:
			continue
		(material as ShaderMaterial).set_shader_parameter("wind_strength", strength)
		(material as ShaderMaterial).set_shader_parameter("wind_direction", direction)


static func _tree_wind_from_options(options: Dictionary) -> bool:
	if not options.has("tree_wind"):
		return false
	var value: Variant = options["tree_wind"]
	if typeof(value) != TYPE_BOOL:
		_warn_option_once("tree_wind_type", "ImportedVegetation option tree_wind must be a boolean; ignoring it")
		return false
	return value


static func _tree_cell_size_from_options(options: Dictionary) -> int:
	if not options.has("tree_cell_size_m"):
		return 0
	var value: Variant = options["tree_cell_size_m"]
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		_warn_option_once(
			"tree_cell_size_m_value",
			"ImportedVegetation option tree_cell_size_m must be 0, 64, 128, or 256; using legacy batching"
		)
		return 0
	var size := float(value)
	if size == 0.0:
		return 0
	if size != 64.0 and size != 128.0 and size != 256.0:
		_warn_option_once(
			"tree_cell_size_m_range",
			"ImportedVegetation option tree_cell_size_m must be 0, 64, 128, or 256; using legacy batching"
		)
		return 0
	return int(size)


static func _warn_option_once(key: String, message: String) -> void:
	if _option_warnings.has(key):
		return
	_option_warnings[key] = true
	push_warning(message)


static func _record_groups(records: Array, cell_size: int) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	if cell_size <= 0:
		groups.append({"cell": Vector2i.ZERO, "cell_size": 0, "records": records})
		return groups
	var group_indices: Dictionary = {}
	for value in records:
		var record: Dictionary = value
		var transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
		var cell := Vector2i(
			floori(transform.origin.x / float(cell_size)),
			floori(transform.origin.z / float(cell_size))
		)
		if not group_indices.has(cell):
			group_indices[cell] = groups.size()
			groups.append({"cell": cell, "cell_size": cell_size, "records": []})
		var group_index := int(group_indices[cell])
		(groups[group_index]["records"] as Array).append(record)
	return groups


static func _tree_asset_wind_supported(asset_id: String, parts: Array[Dictionary], records: Array) -> bool:
	if float(TREE_WIND_LEAN_LIMITS_M.get(asset_id, 0.0)) <= 0.0:
		# Static by design (protected maples, oak, library-only forms): not a warning-worthy failure.
		print_verbose("Tree wind is disabled for %s: no measured collision-bounded sway limit" % asset_id)
		return false
	# The reviewed trees contain one mesh with bark/foliage surfaces. Independent
	# part-local height ramps would pull separately modeled crowns off their stems.
	if parts.size() != 1:
		_warn_tree_wind_once(asset_id + ":parts", "Tree wind is disabled for %s: a shared multi-part bend frame is not qualified" % asset_id)
		return false
	for part: Dictionary in parts:
		var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		var transform_reason := _tree_wind_transform_support_reason(part_transform)
		if not transform_reason.is_empty():
			_warn_tree_wind_once(
				asset_id + ":transform",
				"Tree wind is disabled for %s because a source part transform is unsupported (%s)" % [asset_id, transform_reason]
			)
			return false
		var mesh: Mesh = part.get("mesh")
		if mesh == null or mesh.get_surface_count() <= 0:
			_warn_tree_wind_once(asset_id + ":mesh", "Tree wind is disabled for %s: source part has no surfaces" % asset_id)
			return false
		var materials: Array = part.get("materials", [])
		for surface_index in range(mesh.get_surface_count()):
			var source_material: Material = materials[surface_index] if surface_index < materials.size() else mesh.surface_get_material(surface_index)
			var reason := _tree_material_support_reason(source_material)
			if not reason.is_empty():
				var material_id := str(source_material.get_instance_id()) if source_material != null else "null"
				_warn_tree_wind_once(
					asset_id + ":" + material_id,
					"Tree wind is disabled for %s because source material %s is unsupported (%s)" % [asset_id, material_id, reason]
				)
				return false
	for record: Dictionary in records:
		var plant_transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
		var transform_reason := _tree_wind_transform_support_reason(plant_transform)
		if not transform_reason.is_empty():
			_warn_tree_wind_once(
				asset_id + ":placement_transform",
				"Tree wind is disabled for %s because a placement transform is unsupported (%s)" % [asset_id, transform_reason]
			)
			return false
	return true


static func _tree_wind_transform_support_reason(transform: Transform3D) -> String:
	if not transform.is_finite():
		return "transform is not finite"
	var basis := transform.basis
	var x_length := basis.x.length()
	var y_length := basis.y.length()
	var z_length := basis.z.length()
	var scale_max := maxf(x_length, maxf(y_length, z_length))
	if scale_max <= 0.000001:
		return "basis has zero scale"
	if absf(x_length - y_length) > scale_max * 0.0001 \
		or absf(y_length - z_length) > scale_max * 0.0001 \
		or absf(z_length - x_length) > scale_max * 0.0001:
		return "non-uniform scale is unsupported"
	var x_axis := basis.x / x_length
	var y_axis := basis.y / y_length
	var z_axis := basis.z / z_length
	if absf(x_axis.dot(y_axis)) > 0.0001 \
		or absf(y_axis.dot(z_axis)) > 0.0001 \
		or absf(z_axis.dot(x_axis)) > 0.0001:
		return "shear is unsupported"
	if y_axis.dot(Vector3.UP) < 0.99999:
		return "part is not upright around local Y"
	if basis.determinant() <= 0.0:
		return "mirrored transforms are unsupported"
	return ""


static func _warn_tree_wind_once(key: String, message: String) -> void:
	if _tree_wind_warnings.has(key):
		return
	_tree_wind_warnings[key] = true
	push_warning(message)


static func _tree_material_support_reason(source_material: Material) -> String:
	if not source_material is BaseMaterial3D:
		return "material is not BaseMaterial3D"
	var material := source_material as BaseMaterial3D
	if material is ORMMaterial3D:
		return "ORM materials are not supported"
	if material.cull_mode == BaseMaterial3D.CULL_FRONT:
		return "front-face culling is not supported"
	if _tree_wind_shader_key(material).is_empty():
		return "back-face culling with non-repeating textures has no tree-wind variant"
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return "shading mode is not per-pixel"
	if material.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY:
		return "diffuse mode is not Burley"
	if material.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX:
		return "specular mode is not Schlick-GGX"
	if material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY:
		return "depth draw mode is not opaque-only"
	if material.depth_test != BaseMaterial3D.DEPTH_TEST_DEFAULT or material.no_depth_test:
		return "non-default depth testing is not supported"
	if material.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
		return "blend mode is not mix"
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		and material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return "transparency mode is not opaque or alpha scissor"
	if material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or material.fixed_size:
		return "billboarding or fixed-size rendering is not supported"
	if material.grow or material.use_point_size or material.use_z_clip_scale:
		return "material vertex expansion is not supported"
	if material.distance_fade_mode != 0 or material.proximity_fade_enabled:
		return "material distance fading is not supported"
	if material.disable_ambient_light or material.disable_fog or material.disable_receive_shadows \
		or material.disable_specular_occlusion or material.shadow_to_opacity:
		return "material lighting or shadow flags are not supported"
	if material.albedo_texture_msdf:
		return "MSDF albedo textures are not supported"
	if material.get_flag(BaseMaterial3D.FLAG_ALBEDO_TEXTURE_FORCE_SRGB):
		return "forced sRGB albedo textures are not supported"
	if material.get_flag(BaseMaterial3D.FLAG_PARTICLE_TRAILS_MODE) or material.get_flag(BaseMaterial3D.FLAG_USE_FOV_OVERRIDE):
		return "particle-trail or FOV-override vertex modes are not supported"
	if material.stencil_flags != 0:
		return "stencil rendering is not supported"
	if material.next_pass != null:
		return "material next pass is not supported"
	if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		return "texture filter is not linear with mipmaps"
	if material.uv1_triplanar or material.uv1_world_triplanar or material.uv2_triplanar or material.uv2_world_triplanar:
		return "triplanar UVs are not supported"
	if not is_equal_approx(material.uv1_scale.z, 1.0) or not is_zero_approx(material.uv1_offset.z):
		return "UV1 triplanar components are not supported"
	if material.uv2_scale != Vector3.ONE or material.uv2_offset != Vector3.ZERO:
		return "UV2 transforms are not supported"
	if material.alpha_antialiasing_mode != 0:
		return "alpha antialiasing is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_EMISSION):
		return "emission is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_RIM):
		return "rim lighting is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_CLEARCOAT):
		return "clearcoat is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_ANISOTROPY):
		return "anisotropy is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION) and material.get_flag(BaseMaterial3D.FLAG_AO_ON_UV2):
		return "ambient occlusion on UV2 is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_HEIGHT_MAPPING):
		return "height mapping is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_SUBSURFACE_SCATTERING):
		return "subsurface scattering is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_SUBSURFACE_TRANSMITTANCE):
		return "subsurface transmittance is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_BACKLIGHT):
		return "backlight is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_REFRACTION):
		return "refraction is not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_DETAIL):
		return "detail textures are not supported"
	if material.get_feature(BaseMaterial3D.FEATURE_BENT_NORMAL_MAPPING):
		return "bent normal mapping is not supported"
	return ""


static func _ensure_catalog() -> void:
	if _catalog_data.is_empty():
		if not FileAccess.file_exists(CATALOG_PATH):
			push_error("Imported vegetation catalog is missing: %s" % CATALOG_PATH)
			return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if not parsed is Dictionary:
			push_error("Imported vegetation catalog is not a JSON object")
			return
		_catalog_data = parsed
	if _asset_index.is_empty():
		for asset in _catalog_data.get("assets", []):
			if asset is Dictionary and asset.has("id"):
				_asset_index[str(asset["id"])] = asset


static func _bounded_instance_tint(value: Color) -> Color:
	return Color(clampf(value.r, 0.86, 1.0), clampf(value.g, 0.86, 1.0),
		clampf(value.b, 0.86, 1.0), 1.0)


static func _load_parts(asset_id: String) -> Array[Dictionary]:
	_ensure_catalog()
	var asset: Dictionary = _asset_index.get(asset_id, {})
	if asset.is_empty():
		return []
	var parts: Array[Dictionary] = []
	var source_height := float(asset.get("source_bounds_m", {}).get("height", 0.0))
	if asset.has("mesh"):
		var mesh_resource: Resource = ResourceLoader.load(str(asset["mesh"]))
		if mesh_resource is Mesh:
			parts.append(_part(mesh_resource, Transform3D.IDENTITY, asset, source_height))
		return parts
	if not asset.has("scene"):
		return parts
	var packed_scene: Resource = ResourceLoader.load(str(asset["scene"]))
	if not packed_scene is PackedScene:
		push_error("Imported vegetation scene did not load: %s" % asset["scene"])
		return parts
	var instance := (packed_scene as PackedScene).instantiate()
	_collect_parts(instance, Transform3D.IDENTITY, asset, source_height, parts)
	instance.free()
	return parts


static func _collect_parts(
	node: Node,
	parent_transform: Transform3D,
	asset: Dictionary,
	source_height: float,
	output: Array[Dictionary]
) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			output.append(_part(mesh_instance.mesh, node_transform, asset, source_height, mesh_instance))
	for child in node.get_children():
		_collect_parts(child, node_transform, asset, source_height, output)


static func _part(
	mesh: Mesh,
	transform: Transform3D,
	asset: Dictionary,
	source_height: float,
	mesh_instance: MeshInstance3D = null
) -> Dictionary:
	var materials: Array[Material] = []
	for surface_index in range(mesh.get_surface_count()):
		var material: Material = mesh.surface_get_material(surface_index)
		if mesh_instance != null:
			var override_material := mesh_instance.get_active_material(surface_index)
			if override_material != null:
				material = override_material
		if str(asset.get("source_id", "")) == "landscapelab_tree_2026" \
				and material is StandardMaterial3D:
			# Every supplier GLB assigns metallicFactor=0.5 to bark and foliage.
			# These are dielectric surfaces. Keep downloaded resources untouched;
			# the cached draw material retains their textures, alpha and roughness.
			material = material.duplicate() as StandardMaterial3D
			(material as StandardMaterial3D).metallic = 0.0
		materials.append(material)
	return {
		"mesh": mesh,
		"material": materials[0] if not materials.is_empty() else null,
		"materials": materials,
		"transform": transform,
		"bounds": mesh.get_aabb(),
		"source_triangles": _triangle_count(mesh),
		"source_surfaces": mesh.get_surface_count(),
		"source_materials": materials.size(),
		"asset_height": source_height,
		"grounded_bounds": asset.get("grounded_bounds_m", {}),
	}


static func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	# Count the imported buffers directly; surface_get_arrays would unpack every
	# attribute just to measure its length during source registration.
	if mesh is ArrayMesh:
		var array_mesh := mesh as ArrayMesh
		for surface_index in array_mesh.get_surface_count():
			var index_count := array_mesh.surface_get_array_index_len(surface_index)
			total += (index_count if index_count > 0 else array_mesh.surface_get_array_len(surface_index)) / 3
		return total
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return total


static func _prepare_mesh(
	source_mesh: Mesh,
	source_materials: Array,
	source_height: float,
	bounds_value: AABB,
	enable_wind: bool,
	default_strength: float,
	root_wind_materials: Dictionary
) -> Mesh:
	var draw_mesh := source_mesh.duplicate() as Mesh
	for surface_index in range(draw_mesh.get_surface_count()):
		var base_material: Material = source_materials[surface_index] if surface_index < source_materials.size() else source_mesh.surface_get_material(surface_index)
		var output_material := base_material
		if enable_wind:
			var wind_template := _wind_material(base_material, source_height, bounds_value.position.y)
			if wind_template != null:
				var cache_key := "legacy:%s:%0.6f" % [wind_template.get_instance_id(), default_strength]
				if not root_wind_materials.has(cache_key):
					# Per root: set_wind() changes these uniforms for one vegetation build.
					var root_material := wind_template.duplicate() as ShaderMaterial
					root_material.set_shader_parameter("wind_direction", Vector2(0.8, 0.6).normalized())
					root_material.set_shader_parameter("wind_strength", default_strength)
					root_wind_materials[cache_key] = root_material
				output_material = root_wind_materials[cache_key]
		draw_mesh.surface_set_material(surface_index, output_material)
	return draw_mesh


static func _prepare_tree_wind_mesh(source_mesh: Mesh, source_materials: Array, bounds_value: AABB, lean_limit_m: float) -> Mesh:
	var draw_mesh := source_mesh.duplicate() as Mesh
	for surface_index in range(draw_mesh.get_surface_count()):
		var base_material: Material = source_materials[surface_index] if surface_index < source_materials.size() else source_mesh.surface_get_material(surface_index)
		# _tree_asset_wind_supported() has accepted every surface material.
		draw_mesh.surface_set_material(surface_index, _tree_wind_material(base_material as BaseMaterial3D, bounds_value, lean_limit_m))
	return draw_mesh


## Drops generated LODs that keep less than FOLIAGE_LOD_MIN_FRACTION of an alpha-scissor foliage
## surface, in a per-build draw mesh and its shadow mesh. Vertex and index data are unchanged;
## bark surfaces keep their full LOD chain.
static func _without_sparse_foliage_lods(draw_mesh: Mesh, source_materials: Array) -> Mesh:
	if not draw_mesh is ArrayMesh:
		return draw_mesh
	var foliage: Array[int] = []
	for surface_index in range(draw_mesh.get_surface_count()):
		var material: Material = source_materials[surface_index] if surface_index < source_materials.size() else null
		if material is BaseMaterial3D \
				and (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			foliage.append(surface_index)
	if foliage.is_empty():
		return draw_mesh
	_keep_dense_lods(draw_mesh as ArrayMesh, foliage)
	var shadow_mesh := (draw_mesh as ArrayMesh).shadow_mesh
	if shadow_mesh != null and shadow_mesh.get_surface_count() == draw_mesh.get_surface_count():
		var key := shadow_mesh.get_instance_id()
		if not _foliage_shadow_mesh_cache.has(key):
			var stripped_shadow := shadow_mesh.duplicate() as ArrayMesh
			_keep_dense_lods(stripped_shadow, foliage)
			_foliage_shadow_mesh_cache[key] = stripped_shadow
		(draw_mesh as ArrayMesh).shadow_mesh = _foliage_shadow_mesh_cache[key]
	return draw_mesh


static func _keep_dense_lods(mesh: ArrayMesh, surface_indices: Array[int]) -> void:
	# ArrayMesh's stored surface format keeps the encoded buffers byte-for-byte; "lods" alternates
	# edge length and index bytes.
	var surfaces: Array = mesh.get("_surfaces")
	for surface_index in surface_indices:
		var surface: Dictionary = surfaces[surface_index]
		var bytes_per_index := float((surface.index_data as PackedByteArray).size()) / float(surface.index_count)
		var kept := []
		var lods: Array = surface.lods
		for pair in range(0, lods.size(), 2):
			var lod_indices := float((lods[pair + 1] as PackedByteArray).size()) / bytes_per_index
			if lod_indices >= FOLIAGE_LOD_MIN_FRACTION * float(surface.index_count):
				kept.append_array([lods[pair], lods[pair + 1]])
		surface["lods"] = kept
	mesh.set("_surfaces", surfaces)


## Tree-wind materials have no per-build uniforms, so one cached material serves every build.
static func _tree_wind_material(base_material: BaseMaterial3D, bounds_value: AABB, lean_limit_m: float) -> ShaderMaterial:
	var key := "%s:%0.6f:%0.6f:%0.6f" % [base_material.get_instance_id(), bounds_value.size.y, bounds_value.position.y, lean_limit_m]
	if _tree_wind_material_cache.has(key):
		return _tree_wind_material_cache[key]
	var shader_key := _tree_wind_shader_key(base_material)
	if not _tree_wind_shaders.has(shader_key):
		_tree_wind_shaders[shader_key] = ResourceLoader.load(str(TREE_WIND_SHADER_PATHS[shader_key])) as Shader
	var scissor := base_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var normal_map := base_material.normal_enabled and base_material.normal_texture != null
	var ambient_occlusion := base_material.get_feature(BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION)
	var material := ShaderMaterial.new()
	material.shader = _tree_wind_shaders[shader_key]
	material.render_priority = base_material.render_priority
	material.set_shader_parameter("plant_height", maxf(bounds_value.size.y, 0.001))
	material.set_shader_parameter("plant_base_y", bounds_value.position.y)
	material.set_shader_parameter("tree_lean_limit_m", lean_limit_m)
	# Foliage cards flutter; bark and normal-mapped leaves keep their source normal frame.
	material.set_shader_parameter("leaf_flutter_tilt", LEAF_FLUTTER_TILT if scissor and not normal_map else 0.0)
	material.set_shader_parameter("albedo_color", base_material.albedo_color)
	material.set_shader_parameter("albedo_texture", base_material.albedo_texture)
	material.set_shader_parameter("use_albedo_texture", base_material.albedo_texture != null)
	material.set_shader_parameter("uv1_scale", Vector2(base_material.uv1_scale.x, base_material.uv1_scale.y))
	material.set_shader_parameter("uv1_offset", Vector2(base_material.uv1_offset.x, base_material.uv1_offset.y))
	material.set_shader_parameter("use_vertex_color", base_material.vertex_color_use_as_albedo)
	material.set_shader_parameter("vertex_color_is_srgb", base_material.vertex_color_is_srgb)
	material.set_shader_parameter("use_normal_texture", normal_map)
	material.set_shader_parameter("normal_texture", base_material.normal_texture)
	material.set_shader_parameter("normal_scale", base_material.normal_scale)
	material.set_shader_parameter("metallic", base_material.metallic)
	material.set_shader_parameter("metallic_texture", base_material.metallic_texture)
	material.set_shader_parameter("use_metallic_texture", base_material.metallic_texture != null)
	material.set_shader_parameter("metallic_texture_channel", _texture_channel_mask(base_material.metallic_texture_channel))
	material.set_shader_parameter("roughness", base_material.roughness)
	material.set_shader_parameter("roughness_texture", base_material.roughness_texture)
	material.set_shader_parameter("use_roughness_texture", base_material.roughness_texture != null)
	# Godot writes the roughness grayscale mask into generated code with six digits.
	var roughness_mask := Vector4(0.333333, 0.333333, 0.333333, 0.0) \
		if base_material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE \
		else _texture_channel_mask(base_material.roughness_texture_channel)
	material.set_shader_parameter("roughness_texture_channel", roughness_mask)
	material.set_shader_parameter("specular", base_material.metallic_specular)
	material.set_shader_parameter("use_ao", ambient_occlusion)
	material.set_shader_parameter("ao_texture", base_material.ao_texture)
	material.set_shader_parameter("use_ao_texture", ambient_occlusion and base_material.ao_texture != null)
	material.set_shader_parameter("ao_texture_channel", _texture_channel_mask(base_material.ao_texture_channel))
	material.set_shader_parameter("ao_light_affect", base_material.ao_light_affect)
	material.set_shader_parameter("use_alpha_scissor", scissor)
	material.set_shader_parameter("alpha_scissor_threshold", base_material.alpha_scissor_threshold)
	material.set_shader_parameter("alpha_scissor_max_mip", FOLIAGE_ALPHA_MAX_MIP if scissor else 1000.0)
	_tree_wind_material_cache[key] = material
	return material


## Empty when no variant matches the source cull mode and texture repeat.
static func _tree_wind_shader_key(material: BaseMaterial3D) -> String:
	if material.cull_mode == BaseMaterial3D.CULL_DISABLED:
		return "double_repeat" if material.texture_repeat else "double_clamp"
	if material.cull_mode == BaseMaterial3D.CULL_BACK and material.texture_repeat:
		return "back_repeat"
	return ""


## Same masks as BaseMaterial3D's channel uniforms (scene/resources/material.cpp).
static func _texture_channel_mask(channel: BaseMaterial3D.TextureChannel) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1.0, 0.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0.0, 0.0, 0.0, 1.0)
	return Vector4(0.3333333, 0.3333333, 0.3333333, 0.0)


static func _tree_wind_render_bounds(source_bounds: AABB, lean_limit_m: float, transform: Transform3D) -> AABB:
	# The bend is horizontal: grow X/Z by the crown-top limit in local units, never Y.
	var scale := transform.basis.y.length()
	var grow := lean_limit_m / scale if scale > 0.000001 else 0.0
	return AABB(source_bounds.position - Vector3(grow, 0.0, grow), source_bounds.size + Vector3(2.0 * grow, 0.0, 2.0 * grow))


static func _wind_material(base_material: Material, source_height: float, base_y: float) -> ShaderMaterial:
	if _wind_shader == null:
		_wind_shader = ResourceLoader.load(WIND_SHADER_PATH) as Shader
	var key := "%s:%0.4f:%0.4f" % [str(base_material.get_instance_id()) if base_material != null else "none", source_height, base_y]
	if _wind_material_cache.has(key):
		return _wind_material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = _wind_shader
	material.render_priority = base_material.render_priority if base_material != null else 0
	material.set_shader_parameter("plant_height", maxf(source_height, 0.001))
	material.set_shader_parameter("plant_base_y", base_y)
	if base_material is BaseMaterial3D:
		var standard := base_material as BaseMaterial3D
		material.set_shader_parameter("uv1_scale", Vector2(standard.uv1_scale.x, standard.uv1_scale.y))
		material.set_shader_parameter("uv1_offset", Vector2(standard.uv1_offset.x, standard.uv1_offset.y))
		material.set_shader_parameter("albedo_color", standard.albedo_color)
		material.set_shader_parameter("albedo_texture", standard.albedo_texture)
		material.set_shader_parameter("use_albedo_texture", standard.albedo_texture != null)
		material.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
		material.set_shader_parameter("vertex_color_is_srgb", standard.vertex_color_is_srgb)
		material.set_shader_parameter("roughness", standard.roughness)
		material.set_shader_parameter("metallic", standard.metallic)
		material.set_shader_parameter("specular", standard.metallic_specular)
		material.set_shader_parameter("use_normal_texture", standard.normal_enabled and standard.normal_texture != null)
		material.set_shader_parameter("normal_texture", standard.normal_texture)
		material.set_shader_parameter("normal_scale", standard.normal_scale)
		material.set_shader_parameter(
			"use_alpha_scissor",
			standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		)
		material.set_shader_parameter("alpha_scissor_threshold", standard.alpha_scissor_threshold)
	else:
		material.set_shader_parameter("albedo_color", Color.WHITE)
		material.set_shader_parameter("use_albedo_texture", false)
		material.set_shader_parameter("use_vertex_color", true)
		material.set_shader_parameter("use_normal_texture", false)
		material.set_shader_parameter("use_alpha_scissor", false)
	_wind_material_cache[key] = material
	return material


static func _ground_transform(asset: Dictionary, transform: Transform3D) -> Transform3D:
	var source_bounds: Dictionary = asset.get("source_bounds_m", {})
	var ground_offset := float(source_bounds.get("ground_offset", 0.0))
	var grounded := transform
	grounded.origin += grounded.basis * Vector3(0.0, ground_offset, 0.0)
	return grounded


static func _uniformize_transform(transform: Transform3D) -> Transform3D:
	var scale := transform.basis.y.length()
	if scale <= 0.000001:
		scale = maxf(transform.basis.x.length(), transform.basis.z.length())
	if scale <= 0.000001:
		scale = 1.0
	var rotation := transform.basis.orthonormalized()
	return Transform3D(rotation * Basis.from_scale(Vector3.ONE * scale), transform.origin)


static func _wind_strength_for_role(role: String) -> float:
	match role:
		"tree":
			return DEFAULT_WIND_STRENGTH * 0.4
		"shrub":
			return DEFAULT_WIND_STRENGTH * 0.75
		"grass", "herb", "flower", "crop", "reed":
			return DEFAULT_WIND_STRENGTH * 1.5
		_:
			return DEFAULT_WIND_STRENGTH


static func _transform_aabb(bounds_value: AABB, transform: Transform3D) -> AABB:
	var p := bounds_value.position
	var s := bounds_value.size
	var corners: Array[Vector3] = [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]
	var first := transform * corners[0]
	var result := AABB(first, Vector3.ZERO)
	for index in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result
