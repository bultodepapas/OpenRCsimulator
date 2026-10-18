## Headless, read-only audit of imported near-grass source materials, the zero-wind
## production/adapter paths, imported geometry, and related ground texture imports.
## Run from the repository root with the pinned console build; this does not render.
extends SceneTree

const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const FORMAT := "openrc-grass-material-audit v1"
const ASSET_IDS: Array[String] = [
	"grass_common_short",
	"grass_common_tall",
	"grass_wispy_tall",
]
const MATERIAL_PROPERTIES: Array[String] = [
	"albedo_color", "albedo_texture", "vertex_color_use_as_albedo", "vertex_color_is_srgb",
	"uv1_scale", "uv1_offset", "uv1_triplanar", "uv2_scale", "uv2_offset",
	"metallic", "metallic_texture", "metallic_texture_channel",
	"roughness", "roughness_texture", "roughness_texture_channel",
	"normal_enabled", "normal_texture", "normal_scale",
	"transparency", "alpha_scissor_threshold", "alpha_antialiasing_mode",
	"cull_mode", "shading_mode", "diffuse_mode", "specular_mode", "depth_draw_mode",
	"texture_filter", "texture_repeat",
	"emission_enabled", "emission", "emission_texture", "ao_enabled", "ao_texture",
	"backlight_enabled", "clearcoat_enabled", "anisotropy_enabled", "heightmap_enabled",
	"detail_enabled",
]
const ADAPTER_PARAMETERS: Array[String] = [
	"albedo_color", "albedo_texture", "use_albedo_texture", "uv1_scale", "uv1_offset",
	"use_vertex_color", "vertex_color_is_srgb", "roughness", "metallic",
	"use_normal_texture", "normal_texture", "normal_scale", "use_alpha_scissor",
	"alpha_scissor_threshold", "plant_height", "plant_base_y",
]
const GROUND_MAPS: Array[Dictionary] = [
	{"role": "turf_detail", "path": "res://assets/landscape/turf/detail.png", "binding": "Ground.TURF_DETAIL / turf_detail"},
	{"role": "rc_dirt_albedo", "path": "res://assets/landscape/rc-ground/dirt-albedo.jpg", "binding": "RCGroundMaterial.DIRT_ALBEDO / rc_dirt_albedo"},
	{"role": "rc_dirt_normal", "path": "res://assets/landscape/rc-ground/dirt-normal.jpg", "binding": "RCGroundMaterial.DIRT_NORMAL / rc_dirt_normal"},
	{"role": "rc_dirt_roughness", "path": "res://assets/landscape/rc-ground/dirt-roughness.jpg", "binding": "RCGroundMaterial.DIRT_ROUGHNESS / rc_dirt_roughness"},
	{"role": "rc_grass_albedo", "path": "res://assets/landscape/rc-ground/grass-albedo.jpg", "binding": "RCGroundMaterial.GRASS_ALBEDO / rc_grass_albedo"},
	{"role": "rc_grass_normal", "path": "res://assets/landscape/rc-ground/grass-normal.jpg", "binding": "RCGroundMaterial.GRASS_NORMAL / rc_grass_normal"},
	{"role": "rc_grass_roughness", "path": "res://assets/landscape/rc-ground/grass-roughness.jpg", "binding": "RCGroundMaterial.GRASS_ROUGHNESS / rc_grass_roughness"},
]
const MATERIAL_CODE_PATHS: Array[String] = [
	"res://scenery/imported_vegetation.gd",
	"res://scenery/imported_vegetation_wind.gdshader",
	"res://render/ground.gd",
	"res://render/ground.gdshader",
	"res://render/turf_detail.gdshaderinc",
	"res://render/rc_ground_material.gd",
	"res://render/rc_ground_detail.gdshaderinc",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog: Dictionary = ImportedVegetation.catalog()
	var report: Dictionary = {
		"format": FORMAT,
		"created_utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info(),
		"project": {
			"renderer_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unavailable"),
			"renderer_driver": ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "unavailable"),
			"msaa_3d": ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", "unavailable"),
		},
		"scope": {
			"rendered": false,
			"gpu_timing": "unavailable: headless resource inspection only",
			"gpu_residency": "unavailable: no GPU capture or residency query",
			"zero_wind_image_parity": "unavailable: no rendered comparison in this audit",
			"material_shader_rid_introspection": _shader_introspection_capabilities(),
		},
		"source_identity": _identity_records(catalog),
		"assets": [],
		"ground_maps": [],
		"diagnostics": [],
	}
	for asset_id: String in ASSET_IDS:
		var asset_report := _inspect_asset(asset_id, catalog)
		(report["assets"] as Array).append(asset_report)
		for diagnostic: Dictionary in asset_report.get("diagnostics", []):
			(report["diagnostics"] as Array).append(diagnostic)
	for map_spec: Dictionary in GROUND_MAPS:
		(report["ground_maps"] as Array).append(_inspect_ground_map(map_spec))
	for map_record: Dictionary in report["ground_maps"]:
		if not bool(map_record.get("available", false)):
			(report["diagnostics"] as Array).append({
				"severity": "error",
				"code": "ground_map_unavailable",
				"path": str(map_record.get("path", "")),
				"message": str(map_record.get("error", "missing map")),
			})
	var output_path := ProjectSettings.globalize_path("res://../tmp/grass-quality/material-audit-baseline.json")
	var output_dir := output_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("Cannot create audit output directory: " + output_dir)
		quit(1)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write audit output: " + output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Grass material audit written: " + output_path)
	print("assets=%d ground_maps=%d diagnostics=%d" % [
		(report["assets"] as Array).size(), (report["ground_maps"] as Array).size(),
		(report["diagnostics"] as Array).size(),
	])
	quit(0)


func _inspect_asset(asset_id: String, catalog: Dictionary) -> Dictionary:
	var asset := ImportedVegetation.get_asset(asset_id)
	var result: Dictionary = {
		"id": asset_id,
		"available": not asset.is_empty(),
		"catalog": {},
		"source_gltf": {},
		"import_settings": {},
		"parts": [],
		"triangle_totals": {},
		"feature_fidelity": [],
		"diagnostics": [],
		"unsupported_or_unavailable": [],
	}
	if asset.is_empty():
		result["available"] = false
		result["unsupported_or_unavailable"].append("catalog asset missing")
		return result
	result["catalog"] = {
		"source_id": asset.get("source_id", "unavailable"),
		"source_name": asset.get("source_name", "unavailable"),
		"scene": asset.get("scene", "unavailable"),
		"source_sha256_manifest": asset.get("source_sha256", "unavailable"),
		"source_triangles_manifest": asset.get("source_triangles", "unavailable"),
		"source_surfaces_manifest": asset.get("source_surfaces", "unavailable"),
		"source_materials_manifest": asset.get("source_materials", "unavailable"),
		"source_bounds_m": asset.get("source_bounds_m", "unavailable"),
		"grounded_bounds_m": asset.get("grounded_bounds_m", "unavailable"),
		"lod": asset.get("lod", "unavailable"),
	}
	var scene_path := str(asset.get("scene", ""))
	var source_file := FileAccess.open(scene_path, FileAccess.READ)
	if source_file == null:
		result["available"] = false
		result["unsupported_or_unavailable"].append("source glTF could not be opened")
		return result
	var source_text := source_file.get_as_text()
	source_file.close()
	var gltf_variant: Variant = JSON.parse_string(source_text)
	if not gltf_variant is Dictionary:
		result["available"] = false
		result["unsupported_or_unavailable"].append("source glTF JSON parse failed")
		return result
	var gltf: Dictionary = gltf_variant
	var source_hash := _sha256_res(scene_path)
	result["source_gltf"] = {
		"path": scene_path,
		"sha256_actual": source_hash,
		"sha256_matches_catalog": source_hash == str(asset.get("source_sha256", "")),
		"version": gltf.get("asset", {}).get("version", "unavailable"),
		"materials": gltf.get("materials", []),
		"images": gltf.get("images", []),
		"textures": gltf.get("textures", []),
		"meshes": _source_mesh_summary(gltf),
	}
	if source_hash != str(asset.get("source_sha256", "")):
		(result["diagnostics"] as Array).append(_diagnostic("error", "source_hash_mismatch",
			"The current source glTF hash differs from the catalog identity."))
	var import_path := scene_path + ".import"
	result["import_settings"] = _config_summary(import_path, [
		"nodes/apply_root_scale", "nodes/root_scale", "meshes/generate_lods", "meshes/create_shadow_meshes",
		"meshes/ensure_tangents", "materials/extract", "materials/extract_format", "gltf/embedded_image_handling",
		"gltf/texture_map_mode",
	])
	var texture_paths: Array[String] = []
	for image_variant: Variant in gltf.get("images", []):
		if image_variant is Dictionary and image_variant.has("uri"):
			var texture_path := scene_path.get_base_dir().path_join(str(image_variant["uri"]))
			if not texture_paths.has(texture_path):
				texture_paths.append(texture_path)
	var raw_materials: Array = gltf.get("materials", [])
	var source_material_records: Array[Dictionary] = []
	for material_index in range(raw_materials.size()):
		source_material_records.append(_gltf_material_summary(gltf, material_index, texture_paths))
	result["source_gltf"]["material_summary"] = source_material_records
	result["source_textures"] = []
	for texture_path: String in texture_paths:
		(result["source_textures"] as Array).append(_inspect_texture(texture_path, "source_gltf_dependency"))
	var parts: Array[Dictionary] = ImportedVegetation.get_parts(asset_id)
	var parts_report: Array[Dictionary] = []
	var actual_triangles := 0
	var actual_surfaces := 0
	var part_material_count := 0
	for part_index in range(parts.size()):
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part.get("mesh") as Mesh
		if mesh == null:
			continue
		var part_triangles := _mesh_triangle_count(mesh)
		actual_triangles += part_triangles
		actual_surfaces += mesh.get_surface_count()
		var local_bounds: AABB = part.get("bounds", mesh.get_aabb())
		var part_transform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		var materials: Array = part.get("materials", [])
		var surface_reports: Array[Dictionary] = []
		for surface_index in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_index)
			var effective_material: Material = materials[surface_index] if surface_index < materials.size() else mesh.surface_get_material(surface_index)
			if effective_material != null:
				part_material_count += 1
			var primitive: Dictionary = _source_primitive(gltf, part_index, surface_index)
			var gltf_material_index := int(primitive.get("material", -1))
			var source_material: Dictionary = _gltf_material_summary(gltf, gltf_material_index, texture_paths)
			var static_material := _static_output_material(asset_id, part_index, surface_index)
			var adapter := _adapter_output(asset_id, part_index, surface_index)
			var material_values := _material_summary(effective_material)
			var feature_values := _feature_fidelity(gltf, primitive, source_material, effective_material, static_material, adapter)
			var triangle_count := _surface_triangle_count(arrays)
			surface_reports.append({
				"surface_index": surface_index,
				"source_primitive": primitive,
				"triangle_count": triangle_count,
				"mesh_array_counts": _mesh_array_counts(arrays),
				"source_gltf_material": source_material,
				"effective_import_material": material_values,
				"production_zero_wind_material": _material_summary(static_material),
				"wind_adapter_at_zero_strength": adapter,
				"feature_fidelity": feature_values,
			})
		for feature: Dictionary in feature_values:
			if str(feature.get("status", "")) in ["unsupported_when_used", "mismatch"]:
				(result["diagnostics"] as Array).append(_diagnostic(
					"warning", "adapter_feature_" + str(feature.get("status")),
					"%s: %s" % [str(feature.get("feature", "")), str(feature.get("finding", ""))]
				))
		parts_report.append({
			"part_index": part_index,
			"mesh_class": mesh.get_class(),
			"mesh_name": mesh.resource_name,
			"mesh_resource_path": mesh.resource_path,
			"surface_count": mesh.get_surface_count(),
			"triangle_count": part_triangles,
			"local_bounds": _aabb_value(local_bounds),
			"scene_bounds": _aabb_value(_transform_aabb(local_bounds, part_transform)),
			"part_transform": _transform_value(part_transform),
			"surfaces": surface_reports,
		})
	result["parts"] = parts_report
	result["triangle_totals"] = {
		"catalog_source_triangles": int(asset.get("source_triangles", -1)),
		"loaded_source_triangles": actual_triangles,
		"surface_count": actual_surfaces,
		"material_slots": part_material_count,
		"catalog_match": actual_triangles == int(asset.get("source_triangles", -1)),
	}
	if not bool(result["triangle_totals"]["catalog_match"]):
		(result["diagnostics"] as Array).append(_diagnostic("error", "triangle_count_mismatch",
			"Loaded surface triangle count differs from the catalog source count."))
	result["unsupported_or_unavailable"] = [
		"renderer-generated StandardMaterial3D shader source is reported only when this Godot build exposes the required RenderingServer APIs",
		"shader compile success and zero-wind pixel parity require a rendered run and are not tested here",
		"GPU resident texture bytes and draw/frame cost require a GPU capture and are not measured here",
	]
	return result


func _source_mesh_summary(gltf: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mesh_variant: Variant in gltf.get("meshes", []):
		if not mesh_variant is Dictionary:
			continue
		var primitives: Array[Dictionary] = []
		for primitive_variant: Variant in mesh_variant.get("primitives", []):
			if primitive_variant is Dictionary:
				primitives.append({
					"material": primitive_variant.get("material", "unavailable"),
					"attributes": primitive_variant.get("attributes", {}),
					"mode": primitive_variant.get("mode", 4),
				})
		result.append({"name": mesh_variant.get("name", ""), "primitives": primitives})
	return result


func _source_primitive(gltf: Dictionary, part_index: int, surface_index: int) -> Dictionary:
	var meshes: Array = gltf.get("meshes", [])
	if part_index >= meshes.size() or not meshes[part_index] is Dictionary:
		return {"status": "unavailable: source mesh/surface mapping not resolved"}
	var primitives: Array = meshes[part_index].get("primitives", [])
	if surface_index >= primitives.size() or not primitives[surface_index] is Dictionary:
		return {"status": "unavailable: glTF primitive index not aligned with imported surface"}
	return (primitives[surface_index] as Dictionary).duplicate(true)


func _gltf_material_summary(gltf: Dictionary, index: int, texture_paths: Array[String]) -> Dictionary:
	var materials: Array = gltf.get("materials", [])
	if index < 0 or index >= materials.size() or not materials[index] is Dictionary:
		return {"status": "unavailable: primitive has no source material index", "index": index}
	var source: Dictionary = materials[index]
	var pbr: Dictionary = source.get("pbrMetallicRoughness", {})
	return {
		"status": "present",
		"index": index,
		"name": source.get("name", ""),
		"double_sided": source.get("doubleSided", false),
		"alpha_mode_raw": source.get("alphaMode", "omitted"),
		"alpha_mode_effective_gltf_default": source.get("alphaMode", "OPAQUE"),
		"alpha_cutoff_raw": source.get("alphaCutoff", "omitted"),
		"alpha_cutoff_effective_gltf_default": source.get("alphaCutoff", 0.5),
		"base_color_factor_raw": pbr.get("baseColorFactor", "omitted"),
		"metallic_factor_raw": pbr.get("metallicFactor", "omitted"),
		"roughness_factor_raw": pbr.get("roughnessFactor", "omitted"),
		"base_color_texture": _gltf_texture_reference(gltf, pbr.get("baseColorTexture", {}), texture_paths),
		"metallic_roughness_texture": _gltf_texture_reference(gltf, pbr.get("metallicRoughnessTexture", {}), texture_paths),
		"normal_texture": _gltf_texture_reference(gltf, source.get("normalTexture", {}), texture_paths),
		"occlusion_texture": _gltf_texture_reference(gltf, source.get("occlusionTexture", {}), texture_paths),
		"emissive_texture": _gltf_texture_reference(gltf, source.get("emissiveTexture", {}), texture_paths),
		"emissive_factor_raw": source.get("emissiveFactor", "omitted"),
		"extensions": source.get("extensions", {}),
	}


func _gltf_texture_reference(gltf: Dictionary, texture_slot: Variant, texture_paths: Array[String]) -> Dictionary:
	if not texture_slot is Dictionary or not texture_slot.has("index"):
		return {"status": "absent_in_source"}
	var texture_index := int(texture_slot.get("index", -1))
	var textures: Array = gltf.get("textures", [])
	if texture_index < 0 or texture_index >= textures.size() or not textures[texture_index] is Dictionary:
		return {"status": "unavailable: invalid source texture index", "index": texture_index}
	var texture: Dictionary = textures[texture_index]
	var image_index := int(texture.get("source", -1))
	var images: Array = gltf.get("images", [])
	var image_uri := "unavailable"
	if image_index >= 0 and image_index < images.size() and images[image_index] is Dictionary:
		image_uri = str(images[image_index].get("uri", "unavailable"))
	return {
		"status": "present",
		"index": texture_index,
		"image_index": image_index,
		"image_uri": image_uri,
		"tex_coord": texture_slot.get("texCoord", 0),
		"texture_transform": texture_slot.get("extensions", {}).get("KHR_texture_transform", "absent"),
	}


func _feature_fidelity(
	gltf: Dictionary,
	primitive: Dictionary,
	source_material: Dictionary,
	effective_material: Material,
	static_material: Material,
	adapter: Dictionary
) -> Array[Dictionary]:
	var raw_materials: Array = gltf.get("materials", [])
	var material_index := int(primitive.get("material", -1))
	var raw: Dictionary = raw_materials[material_index] if material_index >= 0 and material_index < raw_materials.size() and raw_materials[material_index] is Dictionary else {}
	var pbr: Dictionary = raw.get("pbrMetallicRoughness", {})
	var attributes: Dictionary = primitive.get("attributes", {})
	var effective: Dictionary = _material_values(effective_material)
	var static_values: Dictionary = _material_values(static_material)
	var adapter_values: Dictionary = adapter.get("shader_parameters", {})
	var adapter_shader: Dictionary = adapter.get("shader", {})
	var records: Array[Dictionary] = []
	_append_feature(records, "base_color_factor", pbr.get("baseColorFactor", "glTF default [1,1,1,1]"), effective.get("albedo_color", "unavailable"), static_values.get("albedo_color", "unavailable"), adapter_values.get("albedo_color", "unavailable"), "copied by adapter when BaseMaterial3D")
	_append_feature(records, "base_color_texture", source_material.get("base_color_texture", {}), effective.get("albedo_texture", "unavailable"), static_values.get("albedo_texture", "unavailable"), adapter_values.get("albedo_texture", "unavailable"), "copied with use flag and UV1 transform")
	_append_feature(records, "vertex_color", {"source_attribute": attributes.get("COLOR_0", "absent")}, effective.get("vertex_color_use_as_albedo", "unavailable"), static_values.get("vertex_color_use_as_albedo", "unavailable"), {"enabled": adapter_values.get("use_vertex_color", "unavailable"), "srgb": adapter_values.get("vertex_color_is_srgb", "unavailable")}, "copied by adapter when BaseMaterial3D")
	_append_feature(records, "uv0_transform", {"source_attribute": attributes.get("TEXCOORD_0", "absent"), "source_texture_ref": source_material.get("base_color_texture", {})}, {"uv1_scale": effective.get("uv1_scale", "unavailable"), "uv1_offset": effective.get("uv1_offset", "unavailable")}, {"uv1_scale": static_values.get("uv1_scale", "unavailable"), "uv1_offset": static_values.get("uv1_offset", "unavailable")}, {"uv1_scale": adapter_values.get("uv1_scale", "unavailable"), "uv1_offset": adapter_values.get("uv1_offset", "unavailable")}, "UV1 scale/offset copied; UV2 and advanced transforms not exposed")
	_append_feature(records, "metallic_factor", pbr.get("metallicFactor", "glTF default 1.0"), effective.get("metallic", "unavailable"), static_values.get("metallic", "unavailable"), adapter_values.get("metallic", "unavailable"), "scalar copied by adapter when BaseMaterial3D")
	_append_feature(records, "roughness_factor", pbr.get("roughnessFactor", "glTF default 1.0"), effective.get("roughness", "unavailable"), static_values.get("roughness", "unavailable"), adapter_values.get("roughness", "unavailable"), "scalar copied by adapter when BaseMaterial3D")
	_append_feature(records, "metallic_roughness_texture", source_material.get("metallic_roughness_texture", {}), effective.get("metallic_texture", "unavailable"), static_values.get("metallic_texture", "unavailable"), "no adapter uniform", "unsupported if source/import uses a metallic-roughness texture")
	_append_feature(records, "normal_texture", source_material.get("normal_texture", {}), {"enabled": effective.get("normal_enabled", "unavailable"), "texture": effective.get("normal_texture", "unavailable"), "scale": effective.get("normal_scale", "unavailable")}, {"enabled": static_values.get("normal_enabled", "unavailable"), "texture": static_values.get("normal_texture", "unavailable"), "scale": static_values.get("normal_scale", "unavailable")}, {"enabled": adapter_values.get("use_normal_texture", "unavailable"), "texture": adapter_values.get("normal_texture", "unavailable"), "scale": adapter_values.get("normal_scale", "unavailable")}, "normal texture and scale copied when enabled")
	_append_feature(records, "alpha_mode", {"raw": source_material.get("alpha_mode_raw", "unavailable"), "gltf_default": source_material.get("alpha_mode_effective_gltf_default", "unavailable"), "cutoff_raw": source_material.get("alpha_cutoff_raw", "unavailable")}, {"transparency": effective.get("transparency", "unavailable"), "threshold": effective.get("alpha_scissor_threshold", "unavailable")}, {"transparency": static_values.get("transparency", "unavailable"), "threshold": static_values.get("alpha_scissor_threshold", "unavailable")}, {"scissor_enabled": adapter_values.get("use_alpha_scissor", "unavailable"), "threshold": adapter_values.get("alpha_scissor_threshold", "unavailable")}, "only ALPHA_SCISSOR is mapped; blend/hash/coverage modes are unsupported")
	_append_feature(records, "double_sided_culling", {"source_double_sided": source_material.get("double_sided", "unavailable")}, {"cull_mode": effective.get("cull_mode", "unavailable")}, {"cull_mode": static_values.get("cull_mode", "unavailable")}, {"render_mode": adapter_shader.get("render_modes", []).filter(func(mode: String) -> bool: return mode.begins_with("cull_"))}, "adapter hard-codes cull_disabled")
	_append_feature(records, "shading_modes", {"source_model": "glTF metallic-roughness PBR"}, {"shading_mode": effective.get("shading_mode", "unavailable"), "diffuse_mode": effective.get("diffuse_mode", "unavailable"), "specular_mode": effective.get("specular_mode", "unavailable")}, {"shading_mode": static_values.get("shading_mode", "unavailable"), "diffuse_mode": static_values.get("diffuse_mode", "unavailable"), "specular_mode": static_values.get("specular_mode", "unavailable")}, {"render_modes": adapter_shader.get("render_modes", [])}, "adapter render modes are fixed in the shader; source diffuse/specular enum names are also recorded")
	_append_feature(records, "texture_filter", "source glTF has no sampler filter requirement", effective.get("texture_filter", "unavailable"), static_values.get("texture_filter", "unavailable"), adapter_shader.get("sampler_filter", "unavailable"), "adapter sampler qualifier is fixed; generated/import filter parity not proven by this field alone")
	_append_feature(records, "secondary_or_extra_material_features", {"uv2": "not specified by glTF material", "emission": raw.get("emissiveFactor", "absent"), "occlusion": source_material.get("occlusion_texture", {})}, {"uv2_scale": effective.get("uv2_scale", "unavailable"), "uv2_offset": effective.get("uv2_offset", "unavailable"), "emission_enabled": effective.get("emission_enabled", "unavailable"), "ao_enabled": effective.get("ao_enabled", "unavailable")}, {"uv2_scale": static_values.get("uv2_scale", "unavailable"), "uv2_offset": static_values.get("uv2_offset", "unavailable"), "emission_enabled": static_values.get("emission_enabled", "unavailable"), "ao_enabled": static_values.get("ao_enabled", "unavailable")}, "no adapter uniforms", "unsupported if enabled by an imported material; verify actual effective values before adding code")
	return records


func _append_feature(
	output: Array[Dictionary], feature: String, source_value: Variant, imported_value: Variant,
	static_value: Variant, adapter_value: Variant, mapping: String
) -> void:
	var status := "preserved_or_not_used"
	var finding := ""
	if mapping.begins_with("unsupported") or mapping.begins_with("no adapter"):
		status = "unsupported_when_used"
		finding = "The source/effective material must be checked; adapter has no corresponding feature mapping."
	output.append({
		"feature": feature,
		"source": source_value,
		"effective_import": imported_value,
		"production_zero_wind": static_value,
		"wind_adapter_zero_strength": adapter_value,
		"mapping": mapping,
		"status": status,
		"finding": finding,
	})


func _static_output_material(asset_id: String, part_index: int, surface_index: int) -> Material:
	var batches: Dictionary = {}
	ImportedVegetation.queue(batches, asset_id, Transform3D.IDENTITY, 0)
	var root := ImportedVegetation.build(batches, false)
	var result: Material = _batch_surface_material(root, asset_id, part_index, surface_index)
	root.free()
	return result


func _adapter_output(asset_id: String, part_index: int, surface_index: int) -> Dictionary:
	var batches: Dictionary = {}
	ImportedVegetation.queue(batches, asset_id, Transform3D.IDENTITY, 0)
	var root := ImportedVegetation.build(batches, true)
	var found_material: Material = _batch_surface_material(root, asset_id, part_index, surface_index)
	var found_instance: MultiMeshInstance3D
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with(asset_id + "_Part_"):
			if int(child.name.get_slice("_Part_", 1)) == part_index:
				found_instance = child as MultiMeshInstance3D
				break
	var result: Dictionary = {
		"available": found_material is ShaderMaterial,
		"material": _material_summary(found_material),
		"shader_parameters": {},
		"instance_parameters": {},
		"shader": {},
		"unsupported_or_unavailable": [],
	}
	if found_material is ShaderMaterial:
		var shader_material := found_material as ShaderMaterial
		for parameter: String in ADAPTER_PARAMETERS:
			result["shader_parameters"][parameter] = _json_value(shader_material.get_shader_parameter(parameter))
		var shader: Shader = shader_material.shader
		result["shader"] = _shader_summary(shader)
	else:
		result["unsupported_or_unavailable"].append("wind adapter material could not be resolved")
	if found_instance != null:
		var initial_strength: Variant = found_instance.get_instance_shader_parameter("wind_strength")
		var initial_direction: Variant = found_instance.get_instance_shader_parameter("wind_direction")
		found_instance.set_instance_shader_parameter("wind_strength", 0.0)
		result["instance_parameters"] = {
			"wind_strength_before_zeroing": _json_value(initial_strength),
			"wind_direction": _json_value(initial_direction),
			"wind_strength_zeroed_for_audit": _json_value(found_instance.get_instance_shader_parameter("wind_strength")),
			"sim_clock_and_wind_vec": "unavailable: global uniform values require a running scene/render state",
		}
	else:
		result["unsupported_or_unavailable"].append("adapter MultiMesh instance node could not be resolved")
	root.free()
	return result


func _batch_surface_material(root: Node3D, asset_id: String, part_index: int, surface_index: int) -> Material:
	for child: Node in root.get_children():
		if not child is MultiMeshInstance3D or not str(child.name).begins_with(asset_id + "_Part_"):
			continue
		if int(child.name.get_slice("_Part_", 1)) != part_index:
			continue
		var multi_mesh: MultiMesh = (child as MultiMeshInstance3D).multimesh
		if multi_mesh == null or multi_mesh.mesh == null or surface_index >= multi_mesh.mesh.get_surface_count():
			return null
		return multi_mesh.mesh.surface_get_material(surface_index)
	return null


func _material_summary(material: Material) -> Dictionary:
	if material == null:
		return {"available": false, "class": "null"}
	var result: Dictionary = {
		"available": true,
		"class": material.get_class(),
		"resource_name": material.resource_name,
		"resource_path": material.resource_path,
		"instance_id_runtime_only": str(material.get_instance_id()),
		"properties": {},
	}
	if material is BaseMaterial3D:
		result["properties"] = _material_values(material)
		result["generated_shader_inspection"] = _generated_material_shader(material as BaseMaterial3D)
	elif material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		result["shader"] = _shader_summary(shader_material.shader)
	return result


func _material_values(material: Material) -> Dictionary:
	var result: Dictionary = {}
	if material == null:
		return result
	var available: Dictionary = {}
	for property_record: Dictionary in material.get_property_list():
		available[str(property_record.get("name", ""))] = property_record
	for property_name: String in MATERIAL_PROPERTIES:
		if not available.has(property_name):
			result[property_name] = {"state": "unavailable_on_runtime_class"}
			continue
		var property_record: Dictionary = available[property_name]
		var value: Variant = material.get(property_name)
		var serialized := _json_value(value)
		if property_name in ["cull_mode", "shading_mode", "diffuse_mode", "specular_mode", "depth_draw_mode", "transparency", "texture_filter", "texture_repeat", "metallic_texture_channel", "roughness_texture_channel", "alpha_antialiasing_mode"]:
			if value is int:
				serialized = {"value": value, "enum_hint": str(property_record.get("hint_string", "unavailable"))}
		result[property_name] = serialized
	return result


func _json_value(value: Variant) -> Variant:
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is AABB:
		return _aabb_value(value)
	if value is Transform3D:
		return _transform_value(value)
	if value is Texture2D:
		return _texture_resource_summary(value)
	if value is Resource:
		return {"class": value.get_class(), "resource_name": value.resource_name, "resource_path": value.resource_path}
	if value is RID:
		return {"rid_valid": value.is_valid()}
	if value is PackedStringArray:
		return Array(value)
	if value is PackedInt32Array:
		return Array(value)
	if value is PackedFloat32Array:
		return Array(value)
	return value


func _texture_resource_summary(texture: Texture2D) -> Dictionary:
	var result: Dictionary = {
		"class": texture.get_class(),
		"resource_path": texture.resource_path,
		"size": _json_value(texture.get_size()),
	}
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		result["image"] = {"state": "unavailable_from_imported_texture"}
	else:
		result["image"] = {
			"width": image.get_width(),
			"height": image.get_height(),
			"format": image.get_format(),
			"has_mipmaps": image.has_mipmaps(),
			"alpha_mode": image.detect_alpha(),
		}
	return result


func _shader_summary(shader: Shader) -> Dictionary:
	if shader == null:
		return {"available": false}
	var code := shader.code
	var modes: Array[String] = []
	var render_match := RegEx.new()
	var render_error := render_match.compile("render_mode\\s+([^;]+);")
	if render_error == OK:
		var found := render_match.search(code)
		if found != null:
			for mode: String in found.get_string(1).split(","):
				modes.append(mode.strip_edges())
	var sampler_filter := "unavailable"
	var filter_match := RegEx.new()
	if filter_match.compile("uniform\\s+sampler2D\\s+albedo_texture\\s*:[^;]*;") == OK:
		var sampler_result := filter_match.search(code)
		if sampler_result != null:
			sampler_filter = sampler_result.get_string(0).get_slice(":", 1).strip_edges()
	return {
		"available": true,
		"resource_path": shader.resource_path,
		"sha256": _sha256_res(shader.resource_path),
		"render_modes": modes,
		"sampler_filter": sampler_filter,
		"source_code": code,
	}


func _generated_material_shader(material: BaseMaterial3D) -> Dictionary:
	var result: Dictionary = {
		"material_has_get_shader_rid": material.has_method("get_shader_rid"),
		"material_has_get_rid": material.has_method("get_rid"),
		"rendering_server_has_material_get_shader": ClassDB.class_has_method("RenderingServer", "material_get_shader"),
		"rendering_server_has_shader_get_code": ClassDB.class_has_method("RenderingServer", "shader_get_code"),
		"shader_code": "unavailable: generated StandardMaterial3D shader code was not queried",
	}
	if not ClassDB.class_has_method("RenderingServer", "material_get_shader") or not ClassDB.class_has_method("RenderingServer", "shader_get_code"):
		result["status"] = "unavailable: required RenderingServer method absent in this build"
		return result
	if not material.has_method("get_rid"):
		result["status"] = "unavailable: Material RID accessor absent"
		return result
	var material_rid_variant: Variant = material.call("get_rid")
	if not material_rid_variant is RID or not (material_rid_variant as RID).is_valid():
		result["status"] = "unavailable: material RID invalid in headless run"
		return result
	var shader_rid_variant: Variant = RenderingServer.call("material_get_shader", material_rid_variant)
	if not shader_rid_variant is RID or not (shader_rid_variant as RID).is_valid():
		result["status"] = "unavailable: generated shader RID invalid in headless run"
		return result
	var code_variant: Variant = RenderingServer.call("shader_get_code", shader_rid_variant)
	if not code_variant is String or str(code_variant).is_empty():
		result["status"] = "unavailable: generated shader code unavailable in headless run"
		return result
	result["status"] = "available"
	result["shader_code"] = code_variant
	result["shader_sha256"] = _sha256_text(str(code_variant))
	return result


func _inspect_ground_map(map_spec: Dictionary) -> Dictionary:
	var path := str(map_spec.get("path", ""))
	var record: Dictionary = {
		"role": map_spec.get("role", "unknown"),
		"path": path,
		"binding": map_spec.get("binding", "unavailable"),
		"available": FileAccess.file_exists(path),
		"source_sha256": _sha256_res(path),
		"source_image": {},
		"import_settings": {},
		"imported_texture": {},
		"unsupported_or_unavailable": [],
	}
	if not bool(record["available"]):
		record["error"] = "source ground map missing"
		return record
	var source_image := Image.new()
	var image_error := source_image.load(ProjectSettings.globalize_path(path))
	if image_error == OK:
		record["source_image"] = {
			"width": source_image.get_width(),
			"height": source_image.get_height(),
			"format": source_image.get_format(),
			"has_mipmaps": source_image.has_mipmaps(),
			"alpha_mode": source_image.detect_alpha(),
		}
	else:
		record["source_image"] = {"state": "unavailable: Image.load error %d" % image_error}
	var import_config := _config_summary(path + ".import", [
		"compress/mode", "compress/high_quality", "compress/lossy_quality", "compress/normal_map",
		"mipmaps/generate", "mipmaps/limit", "roughness/mode", "process/fix_alpha_border",
		"process/premult_alpha", "detect_3d/compress_to", "process/normal_map_invert_y",
	])
	record["import_settings"] = import_config
	var imported: Resource = ResourceLoader.load(path)
	if imported is Texture2D:
		record["imported_texture"] = _texture_resource_summary(imported as Texture2D)
	else:
		record["imported_texture"] = {"state": "unavailable: ResourceLoader did not return Texture2D", "class": imported.get_class() if imported != null else "null"}
		record["unsupported_or_unavailable"].append("imported texture resource inspection unavailable")
	record["runtime_gpu_residency"] = "unavailable: not queried by headless audit"
	return record


func _config_summary(path: String, keys: Array[String]) -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return {"path": path, "available": false, "error_code": error, "values": {}}
	var values: Dictionary = {}
	for key: String in keys:
		var separator := key.find("/")
		if separator <= 0:
			continue
		var section := key.substr(0, separator)
		var property := key.substr(separator + 1)
		values[key] = _json_value(config.get_value(section, property, "unavailable"))
	return {"path": path, "available": true, "values": values}


func _identity_records(catalog: Dictionary) -> Dictionary:
	var paths: Array[String] = ["res://assets/landscape/vegetation/catalog.json"]
	for asset_id: String in ASSET_IDS:
		var asset := ImportedVegetation.get_asset(asset_id)
		var scene_path := str(asset.get("scene", ""))
		if not scene_path.is_empty() and not paths.has(scene_path):
			paths.append(scene_path)
		var bin_path := scene_path.trim_suffix(".gltf") + ".bin"
		if FileAccess.file_exists(bin_path) and not paths.has(bin_path):
			paths.append(bin_path)
		for texture_path_variant: Variant in asset.get("textures", []):
			if not texture_path_variant is Dictionary:
				continue
			var texture_path := scene_path.get_base_dir().path_join(str(texture_path_variant.get("uri", "")))
			if FileAccess.file_exists(texture_path) and not paths.has(texture_path):
				paths.append(texture_path)
	for path: String in MATERIAL_CODE_PATHS:
		if not paths.has(path):
			paths.append(path)
	var records: Array[Dictionary] = []
	for path: String in paths:
		records.append({"path": path, "available": FileAccess.file_exists(path), "sha256": _sha256_res(path)})
	return {"records": records, "catalog_asset_count": catalog.get("assets", []).size()}


func _mesh_triangle_count(mesh: Mesh) -> int:
	var result := 0
	for surface_index in range(mesh.get_surface_count()):
		result += _surface_triangle_count(mesh.surface_get_arrays(surface_index))
	return result


func _surface_triangle_count(arrays: Array) -> int:
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return 0
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return int((indices.size() if not indices.is_empty() else vertices.size()) / 3)


func _mesh_array_counts(arrays: Array) -> Dictionary:
	var counts: Dictionary = {}
	var names: Array[String] = ["vertex", "normal", "tangent", "color", "uv0", "uv1", "bones", "weights", "index"]
	var slots: Array[int] = [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR,
		Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]
	for index in range(names.size()):
		var value: Variant = arrays[slots[index]] if slots[index] < arrays.size() else null
		counts[names[index]] = value.size() if value is PackedByteArray or value is PackedInt32Array or value is PackedFloat32Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedColorArray else 0
	return counts


func _aabb_value(bounds: AABB) -> Dictionary:
	return {"position": _json_value(bounds.position), "size": _json_value(bounds.size), "end": _json_value(bounds.end)}


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				var point := transform * Vector3(float(x), float(y), float(z))
				if first:
					result = AABB(point, Vector3.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result


func _transform_value(transform: Transform3D) -> Dictionary:
	return {
		"basis_x": _json_value(transform.basis.x),
		"basis_y": _json_value(transform.basis.y),
		"basis_z": _json_value(transform.basis.z),
		"origin": _json_value(transform.origin),
	}


func _sha256_res(resource_path: String) -> String:
	if resource_path.is_empty() or not FileAccess.file_exists(resource_path):
		return "unavailable"
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return "unavailable: open error %d" % FileAccess.get_open_error()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return "unavailable: SHA-256 init failed"
	while not file.eof_reached():
		var block := file.get_buffer(1024 * 1024)
		if block.is_empty():
			break
		context.update(block)
	file.close()
	return context.finish().hex_encode()


func _sha256_text(text_value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "unavailable"
	context.update(text_value.to_utf8_buffer())
	return context.finish().hex_encode()


func _shader_introspection_capabilities() -> Dictionary:
	return {
		"BaseMaterial3D.get_shader_rid": ClassDB.class_has_method("BaseMaterial3D", "get_shader_rid"),
		"BaseMaterial3D.get_rid": ClassDB.class_has_method("BaseMaterial3D", "get_rid"),
		"RenderingServer.material_get_shader": ClassDB.class_has_method("RenderingServer", "material_get_shader"),
		"RenderingServer.shader_get_code": ClassDB.class_has_method("RenderingServer", "shader_get_code"),
		"RenderingServer.shader_get_spirv": ClassDB.class_has_method("RenderingServer", "shader_get_spirv"),
	}


func _inspect_texture(path: String, role: String) -> Dictionary:
	var result: Dictionary = {
		"role": role,
		"path": path,
		"available": FileAccess.file_exists(path),
		"source_sha256": _sha256_res(path),
	}
	if not bool(result["available"]):
		return result
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error == OK:
		result["source_image"] = {
			"width": image.get_width(),
			"height": image.get_height(),
			"format": image.get_format(),
			"has_mipmaps": image.has_mipmaps(),
			"alpha_mode": image.detect_alpha(),
		}
	else:
		result["source_image"] = {"state": "unavailable: Image.load error %d" % error}
	result["import_settings"] = _config_summary(path + ".import", [
		"compress/mode", "compress/high_quality", "compress/lossy_quality", "compress/normal_map",
		"mipmaps/generate", "roughness/mode", "process/fix_alpha_border", "process/premult_alpha",
		"detect_3d/compress_to",
	])
	var texture: Resource = ResourceLoader.load(path)
	result["imported_texture"] = _texture_resource_summary(texture as Texture2D) if texture is Texture2D else {"state": "unavailable: texture did not load"}
	return result


func _diagnostic(severity: String, code: String, message: String) -> Dictionary:
	return {"severity": severity, "code": code, "message": message}

