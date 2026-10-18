## Headless Windows-preset PCK resource smoke for the opt-in grass preview.
## Run from an otherwise-empty project root and pass the PCK path, source app
## root, and a new absolute evidence JSON path. The script mounts the PCK itself.
extends SceneTree

const FORMAT := "openrc-grass-windows-pack-smoke v1"
const SELECTOR := "OPENRC_GRASS_QUALITY"
const VEGETATION_CATALOG_PATH := "res://assets/landscape/vegetation/catalog.json"
const ASSET_IDS: Array[String] = [
	"grass_common_short",
	"grass_common_tall",
	"grass_wispy_tall",
]
const PHOTO_TEXTURES: Array[Dictionary] = [
	{"name": "Grass001 albedo", "parameter": "rc_grass_albedo", "path": "res://assets/landscape/rc-ground/grass-albedo.jpg"},
	{"name": "Grass001 normal", "parameter": "rc_grass_normal", "path": "res://assets/landscape/rc-ground/grass-normal.jpg"},
	{"name": "Grass001 roughness", "parameter": "rc_grass_roughness", "path": "res://assets/landscape/rc-ground/grass-roughness.jpg"},
]
const RC_TEXTURES: Array[Dictionary] = [
	{"name": "RC dirt albedo", "parameter": "rc_dirt_albedo", "path": "res://assets/landscape/rc-ground/dirt-albedo.jpg"},
	{"name": "RC dirt normal", "parameter": "rc_dirt_normal", "path": "res://assets/landscape/rc-ground/dirt-normal.jpg"},
	{"name": "RC dirt roughness", "parameter": "rc_dirt_roughness", "path": "res://assets/landscape/rc-ground/dirt-roughness.jpg"},
]
const SOURCE_IDENTITY_PATHS: Array[String] = [
	"res://assets/landscape/vegetation/catalog.json",
	"res://assets/landscape/vegetation/LICENSE.txt",
	"res://assets/landscape/rc-ground/manifest.json",
	"res://assets/landscape/rc-ground/LICENSES.txt",
	"res://data/fields/default.json",
	"res://data/fields/grass.json",
]
const CODE_IDENTITY_PATHS: Array[String] = [
	"res://scenery/imported_vegetation.gd",
	"res://scenery/imported_near_grass.gd",
	"res://scenery/imported_grass_material.gd",
	"res://scenery/imported_grass.gdshader",
	"res://render/grass_quality.gd",
	"res://render/ground.gd",
	"res://render/ground.gdshader",
	"res://render/grass_ground_material.gd",
	"res://render/rc_ground_material.gd",
	"res://render/turf_detail.gdshaderinc",
	"res://render/rc_ground_detail.gdshaderinc",
]

var _checks := 0
var _failures := 0
var _source_root := ""
var _report_path := ""
var _report: Dictionary = {}
var _vegetation: Script
var _near_grass: Script
var _grass_quality: Script
var _ground: Script
var _grass_detail: Script
var _rc_detail: Script
var _field_loader: Script
var _near_grass_constants: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("Expected: <pck> <source-app-root> <new-evidence-json>")
		quit(2)
		return
	var pack_path := _absolute_path(args[0])
	_source_root = _absolute_path(args[1])
	_report_path = _absolute_path(args[2])
	if pack_path.is_empty() or _source_root.is_empty() or _report_path.is_empty():
		printerr("PCK, source root, and evidence path must resolve to absolute paths")
		quit(2)
		return
	if not FileAccess.file_exists(pack_path):
		printerr("Windows-preset PCK does not exist: " + pack_path)
		quit(2)
		return
	if FileAccess.file_exists(_report_path) or DirAccess.dir_exists_absolute(_report_path):
		printerr("Refusing to overwrite existing evidence: " + _report_path)
		quit(2)
		return
	var initial_selector := OS.get_environment(SELECTOR)
	OS.set_environment(SELECTOR, "")

	var pack_hash := _sha256_file(pack_path)
	_report = {
		"format": FORMAT,
		"created_utc": Time.get_datetime_string_from_system(false, true),
		"engine": Engine.get_version_info(),
		"execution": {
			"kind": "host-side headless resource smoke; no Windows executable launch",
			"pack_mode": "Windows Desktop export preset PCK, mounted from the empty root with ProjectSettings.load_resource_pack",
			"project_root": ProjectSettings.globalize_path("res://"),
			"source_app_root": _source_root,
			"pck": pack_path,
			"pck_sha256": pack_hash,
			"rendered": false,
			"gpu_timing": "not measured",
		},
		"checks": [],
		"source_identities": [],
		"code_identities": [],
		"textures": [],
		"meshes": [],
		"profiles": [],
		"grass_material_routes": {},
		"grass_mesh_routes": {},
		"summary": {},
	}
	_check("PCK has a readable SHA-256 identity", pack_hash.length() == 64, pack_hash)
	var pack_loaded := ProjectSettings.load_resource_pack(pack_path, true)
	_check("Windows-preset PCK mounts from the empty project directory", pack_loaded)
	if not pack_loaded:
		_finish()
		return
	_vegetation = load("res://scenery/imported_vegetation.gd") as Script
	_near_grass = load("res://scenery/imported_near_grass.gd") as Script
	_grass_quality = load("res://render/grass_quality.gd") as Script
	_ground = load("res://render/ground.gd") as Script
	_grass_detail = load("res://render/grass_ground_material.gd") as Script
	_rc_detail = load("res://render/rc_ground_material.gd") as Script
	_field_loader = load("res://data/field_loader.gd") as Script
	var scripts_available := _vegetation != null and _near_grass != null and _grass_quality != null \
		and _ground != null and _grass_detail != null and _rc_detail != null and _field_loader != null
	_check("all grass, ground and field loader scripts load from the mounted PCK", scripts_available)
	if not scripts_available:
		_finish()
		return
	_near_grass_constants = _near_grass.get_script_constant_map()
	_check("packed grass adapter exposes both quality tables and triangle budget",
		_near_grass_constants.has("QUALITY_LIMITS") and _near_grass_constants.has("ENHANCED_QUALITY_LIMITS")
		and int(_near_grass_constants.get("MAX_SOURCE_TRIANGLES", 0)) == 50000)
	_check("mounted PCK exposes the vegetation catalog", FileAccess.file_exists(VEGETATION_CATALOG_PATH), VEGETATION_CATALOG_PATH)

	var catalog: Dictionary = _vegetation.call("catalog")
	_check("packed catalog retains all source asset rows", (catalog.get("assets", []) as Array).size() >= 3)
	_check("packed grass quality selector defaults to static", not bool(_grass_quality.call("enhanced")))
	_verify_source_identities(catalog)
	_verify_grass_source_assets()
	_verify_textures()
	_verify_grass_shader()

	var loaded_field: Dictionary = _field_loader.call("load_from")
	_check("packed default field data validates", bool(loaded_field.get("ok", false)), str(loaded_field.get("errors", [])))
	if bool(loaded_field.get("ok", false)):
		var field: Dictionary = loaded_field.field
		var default_profiles := _profile_matrix(field, false)
		var default_root := _near_grass.call("build", field, "high") as Node3D
		_report["profiles"].append({"selector": "default", "tiers": default_profiles})
		_report["grass_mesh_routes"]["default_high"] = _verify_near_grass_root(default_root, false)
		OS.set_environment(SELECTOR, "enhanced")
		_check("enhanced selector activates from the packaged helper", bool(_grass_quality.call("enhanced")))
		var enhanced_profiles := _profile_matrix(field, true)
		var enhanced_root_a := _near_grass.call("build", field, "high") as Node3D
		var enhanced_root_b := _near_grass.call("build", field, "high") as Node3D
		_report["profiles"].append({"selector": "enhanced", "tiers": enhanced_profiles})
		_report["grass_mesh_routes"]["enhanced_high"] = _verify_near_grass_root(enhanced_root_a, true)
		_report["grass_mesh_routes"]["enhanced_second_build"] = _verify_near_grass_root(enhanced_root_b, true)
		_verify_material_isolation(enhanced_root_a, enhanced_root_b)
		if is_instance_valid(default_root):
			default_root.free()
		if is_instance_valid(enhanced_root_a):
			enhanced_root_a.free()
		if is_instance_valid(enhanced_root_b):
			enhanced_root_b.free()
	_verify_ground_bindings()
	OS.set_environment(SELECTOR, initial_selector)
	_finish()


func _finish() -> void:
	_report["summary"] = {
		"checks": _checks,
		"failures": _failures,
		"resource_only": true,
		"windows_preset_pck": true,
		"platform_binary_executed": false,
		"gpu_capture_or_timing": false,
	}
	if not _write_report():
		quit(1)
		return
	print("Grass Windows-preset PCK smoke: %d checks, %d failures" % [_checks, _failures])
	print("GRASS_PACK_REPORT=" + _report_path)
	quit(1 if _failures > 0 else 0)


func _verify_source_identities(catalog: Dictionary) -> void:
	var records: Array[Dictionary] = []
	for path: String in SOURCE_IDENTITY_PATHS:
		var record := _source_pack_hash_record(path, true)
		records.append(record)
		_check("required source identity is byte-identical in PCK: " + path,
			bool(record.get("byte_identical", false)), str(record))
	var code_records: Array[Dictionary] = []
	for path: String in CODE_IDENTITY_PATHS:
		var source_path := _source_absolute(path)
		var source_hash := _sha256_file(source_path)
		var pack_has_raw := FileAccess.file_exists(path)
		var pack_hash := _sha256_virtual(path) if pack_has_raw else "unavailable: exporter may store compiled/remapped resource"
		code_records.append({
			"path": path,
			"source_sha256": source_hash,
			"packed_raw_available": pack_has_raw,
			"packed_raw_sha256": pack_hash,
			"raw_byte_identical": pack_hash == source_hash if pack_has_raw else "unavailable",
			"resource_loadable": ResourceLoader.exists(path),
		})
		_check("runtime code resource loads from PCK: " + path, ResourceLoader.exists(path))
	_report["source_identities"] = records
	_report["code_identities"] = code_records

	var vegetation_license_hash := _sha256_virtual("res://assets/landscape/vegetation/LICENSE.txt")
	var manifest_license_hash := str(catalog.get("source", {}).get("license_sha256", ""))
	_check("Quaternius CC0 license matches the packed vegetation manifest",
		vegetation_license_hash == manifest_license_hash,
		"packed=%s manifest=%s" % [vegetation_license_hash, manifest_license_hash])
	var rc_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/landscape/rc-ground/manifest.json"))
	var rc_license_hash := _sha256_virtual("res://assets/landscape/rc-ground/LICENSES.txt")
	var grass001: Dictionary = rc_manifest.get("assets", {}).get("grass001", {}) if rc_manifest is Dictionary else {}
	var license_text := FileAccess.get_file_as_string("res://assets/landscape/rc-ground/LICENSES.txt")
	_check("ambientCG Grass 001 CC0 evidence remains in the packed license/manifest",
		str(grass001.get("license", "")) == "CC0 1.0 Universal"
		and str(grass001.get("asset_url", "")).contains("ambientcg.com/view?id=Grass001")
		and license_text.contains("Grass 001") and license_text.contains("CC0 1.0 Universal"),
		"license file sha256=%s" % rc_license_hash)


func _verify_grass_source_assets() -> void:
	var mesh_records: Array[Dictionary] = []
	for asset_id: String in ASSET_IDS:
		var asset: Dictionary = _vegetation.call("get_asset", asset_id)
		var scene_path := str(asset.get("scene", ""))
		var source_path := _source_absolute(scene_path)
		var actual_source_hash := _sha256_file(source_path)
		var catalog_hash := str(asset.get("source_sha256", ""))
		_check("%s source glTF identity matches its retained catalog hash" % asset_id,
			actual_source_hash == catalog_hash,
			"source=%s catalog=%s" % [actual_source_hash, catalog_hash])
		var parts: Array[Dictionary] = _vegetation.call("get_parts", asset_id)
		var expected_triangles := int(asset.get("source_triangles", -1))
		var part_triangle_total := 0
		var surface_count := 0
		var materials_valid := not parts.is_empty()
		var meshes: Array[Dictionary] = []
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var mesh := part.get("mesh") as Mesh
			if mesh == null:
				materials_valid = false
				continue
			var mesh_triangles := _mesh_triangle_count(mesh)
			part_triangle_total += mesh_triangles
			surface_count += mesh.get_surface_count()
			var materials: Array = part.get("materials", [])
			var surface_ok := materials.size() == mesh.get_surface_count()
			for surface_index in range(mesh.get_surface_count()):
				var material := materials[surface_index] as StandardMaterial3D if surface_index < materials.size() else null
				surface_ok = surface_ok and material != null and material.albedo_texture != null
				if material != null:
					surface_ok = surface_ok and material.albedo_texture.resource_path == "res://assets/landscape/vegetation/models/Grass.png"
					surface_ok = surface_ok and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
					surface_ok = surface_ok and material.cull_mode == BaseMaterial3D.CULL_DISABLED
			meshes.append({
				"part_index": part_index,
				"mesh_class": mesh.get_class(),
				"surface_count": mesh.get_surface_count(),
				"triangle_count": mesh_triangles,
				"bounds": _aabb_summary(mesh.get_aabb()),
				"materials_valid": surface_ok,
			})
			materials_valid = materials_valid and surface_ok
		_check("%s packaged imported mesh and source material load" % asset_id,
			materials_valid and part_triangle_total == expected_triangles,
			"parts=%d triangles=%d expected=%d surfaces=%d" % [parts.size(), part_triangle_total, expected_triangles, surface_count])
		mesh_records.append({
			"id": asset_id,
			"scene": scene_path,
			"source_sha256_actual": actual_source_hash,
			"source_sha256_catalog": catalog_hash,
			"source_triangles_catalog": expected_triangles,
			"loaded_triangles": part_triangle_total,
			"surface_count": surface_count,
			"parts": meshes,
		})
	_report["meshes"] = mesh_records
	_check("exactly three requested imported grass meshes are present", mesh_records.size() == 3)


func _verify_textures() -> void:
	var texture_records: Array[Dictionary] = []
	for spec: Dictionary in PHOTO_TEXTURES:
		var record := _verify_texture(str(spec.name), str(spec.path), true, Vector2i(2048, 2048))
		texture_records.append(record)
	for spec: Dictionary in RC_TEXTURES:
		var record := _verify_texture(str(spec.name), str(spec.path), true, Vector2i(2048, 2048))
		texture_records.append(record)
	var palette_path := "res://assets/landscape/vegetation/models/Grass.png"
	var palette_record := _verify_texture("Quaternius grass atlas", palette_path, false, Vector2i.ZERO)
	texture_records.append(palette_record)
	var turf_detail_path := "res://assets/landscape/turf/detail.png"
	var turf_record := _verify_texture("existing turf detail", turf_detail_path, true, Vector2i.ZERO)
	texture_records.append(turf_record)
	_report["textures"] = texture_records


func _verify_texture(label: String, resource_path: String, require_mips: bool, expected_size: Vector2i) -> Dictionary:
	var texture := ResourceLoader.load(resource_path) as Texture2D
	var source_path := _source_absolute(resource_path)
	var source_file_image := Image.new()
	var source_error := source_file_image.load(source_path) if FileAccess.file_exists(source_path) else ERR_FILE_NOT_FOUND
	var source_file_valid := source_error == OK and not source_file_image.is_empty()
	var source_project_imported := _load_source_imported_texture(resource_path, source_path)
	var source_project_image: Image = source_project_imported.get("texture").get_image() \
		if source_project_imported.get("texture") is Texture2D else null
	var packed_imported_image: Image = source_project_imported.get("packed_texture").get_image() \
		if source_project_imported.get("packed_texture") is Texture2D else null
	var pack_image: Image = texture.get_image() if texture != null else null
	var imported_image_ok := source_project_image != null and packed_imported_image != null and pack_image != null
	var source_size := source_project_image.get_size() if source_project_image != null else Vector2i.ZERO
	var pack_size := packed_imported_image.get_size() if packed_imported_image != null else Vector2i.ZERO
	var source_hash := _decoded_image_hash(source_project_image) if source_project_image != null else "unavailable"
	var pack_hash := _decoded_image_hash(packed_imported_image) if packed_imported_image != null else "unavailable"
	var runtime_hash := _decoded_image_hash(pack_image) if pack_image != null else "unavailable"
	var equal_pixels := imported_image_ok and source_size == pack_size and source_hash == pack_hash and pack_hash == runtime_hash
	var source_import_has_mips := source_project_image.has_mipmaps() if source_project_image != null else false
	var pack_has_mips := packed_imported_image.has_mipmaps() if packed_imported_image != null else false
	var runtime_has_mips := pack_image.has_mipmaps() if pack_image != null else false
	var size_matches := expected_size == Vector2i.ZERO or (source_size == expected_size and pack_size == expected_size)
	var record := {
		"name": label,
		"path": resource_path,
		"source_file": source_path,
		"source_file_sha256": _sha256_file(source_path) if FileAccess.file_exists(source_path) else "unavailable",
		"resource_loaded_from_pack": texture != null,
		"texture_class": texture.get_class() if texture != null else "unavailable",
		"source_file_decoded_size": source_file_image.get_size() if source_file_valid else Vector2i.ZERO,
		"source_file_decoded_rgba8_sha256": _decoded_image_hash(source_file_image) if source_file_valid else "unavailable",
		"source_project_import_artifact": source_project_imported.get("source_artifact_path", "unavailable"),
		"pck_import_artifact": source_project_imported.get("packed_artifact_path", "unavailable"),
		"import_artifact_sha256_source": source_project_imported.get("source_artifact_sha256", "unavailable"),
		"import_artifact_sha256_pck": source_project_imported.get("packed_artifact_sha256", "unavailable"),
		"import_artifact_byte_identical": source_project_imported.get("artifacts_identical", false),
		"source_project_imported_size": source_size,
		"pck_imported_size": pack_size,
		"source_project_imported_has_mipmaps": source_import_has_mips,
		"pack_has_mipmaps": pack_has_mips,
		"runtime_texture_has_mipmaps": runtime_has_mips,
		"pack_mipmaps_required": require_mips,
		"source_project_imported_decoded_rgba8_sha256": source_hash,
		"pck_imported_decoded_rgba8_sha256": pack_hash,
		"runtime_texture_decoded_rgba8_sha256": runtime_hash,
		"decoded_base_pixels_equal_source_project_to_pack": equal_pixels,
	}
	_check("%s texture loads and source-project imported pixels match the PCK" % label,
		texture != null and source_file_valid and imported_image_ok and equal_pixels and size_matches
		and bool(source_project_imported.get("artifacts_identical", false)),
		"source_project_import=%s PCK_import=%s source_project_mips=%s PCK_mips=%s" % [source_size, pack_size,
			str(source_import_has_mips), str(pack_has_mips)])
	_check("%s imported mipmap state is retained" % label,
		imported_image_ok and source_import_has_mips == pack_has_mips
		and (pack_has_mips if require_mips else not pack_has_mips),
		"required=%s source_project=%s PCK=%s runtime=%s" % [str(require_mips), str(source_import_has_mips), str(pack_has_mips), str(runtime_has_mips)])
	return record


func _load_source_imported_texture(resource_path: String, source_image_path: String) -> Dictionary:
	var config := ConfigFile.new()
	var config_error := config.load(source_image_path + ".import")
	if config_error != OK:
		return {"reason": "source import config unavailable (%d)" % config_error}
	var destinations: Array = config.get_value("deps", "dest_files", [])
	for destination_value: Variant in destinations:
		var destination := str(destination_value)
		if not FileAccess.file_exists(destination):
			continue
		var source_artifact_path := _source_absolute(destination)
		var source_texture := ResourceLoader.load(source_artifact_path) as Texture2D
		var packed_texture := ResourceLoader.load(destination) as Texture2D
		if source_texture == null or packed_texture == null:
			continue
		var source_hash := _sha256_file(source_artifact_path)
		var packed_hash := _sha256_virtual(destination)
		return {
			"source_artifact_path": source_artifact_path,
			"packed_artifact_path": destination,
			"source_artifact_sha256": source_hash,
			"packed_artifact_sha256": packed_hash,
			"artifacts_identical": not source_hash.is_empty() and source_hash == packed_hash,
			"texture": source_texture,
			"packed_texture": packed_texture,
		}
	return {"reason": "no source import artifact was also present in the PCK"}


func _verify_grass_shader() -> void:
	var shader := ResourceLoader.load("res://scenery/imported_grass.gdshader") as Shader
	var adapter: Script = ResourceLoader.load("res://scenery/imported_grass_material.gd") as Script
	var source_shader := _read_source_text("res://scenery/imported_grass.gdshader")
	var shader_code := shader.code if shader != null else ""
	var contract_ok := shader != null and shader_code.contains("render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;") \
		and shader_code.contains("clamp(wind_strength, 0.0, 0.12)")
	_check("grass-only wind shader loads from PCK with the qualified opaque contract", contract_ok)
	_check("grass-only material adapter loads from PCK", adapter != null)
	_report["shader"] = {
		"path": "res://scenery/imported_grass.gdshader",
		"resource_loaded": shader != null,
		"source_sha256": _sha256_text(source_shader),
		"packed_code_sha256": _sha256_text(shader_code),
		"render_mode_contract": contract_ok,
		"adapter_path": "res://scenery/imported_grass_material.gd",
		"adapter_resource_loaded": adapter != null,
		"adapter_exercised_by_enhanced_root_build": adapter != null,
	}


func _profile_matrix(field: Dictionary, expect_enhanced: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var limits: Dictionary = _near_grass_constants.get("ENHANCED_QUALITY_LIMITS", {}) if expect_enhanced else _near_grass_constants.get("QUALITY_LIMITS", {})
	var triangle_budget := int(_near_grass_constants.get("MAX_SOURCE_TRIANGLES", 0))
	var prior_rows: Dictionary = {}
	for quality: String in ["low", "balanced", "high"]:
		var placements: Array[Dictionary] = _near_grass.call("layout", field, quality)
		var counts := _placement_counts(placements)
		var table: Dictionary = limits.get(quality, {})
		var expected_total := 0
		var counts_match := true
		for asset_id: String in ASSET_IDS:
			var expected_count := int(table.get(asset_id, 0))
			expected_total += expected_count
			counts_match = counts_match and int(counts.get(asset_id, 0)) == expected_count
		var rows := _placement_rows(placements)
		var triangles := _placement_triangles(placements)
		var nested := true
		if not prior_rows.is_empty():
			for row_index: int in prior_rows:
				if not rows.has(row_index):
					nested = false
		_check("%s %s profile keeps its exact source-family counts" % ["enhanced" if expect_enhanced else "default", quality],
			placements.size() == expected_total and counts_match,
			"expected=%d actual=%d by_asset=%s" % [expected_total, placements.size(), str(counts)])
		_check("%s %s profile remains within the 50,000 source-triangle cap" % ["enhanced" if expect_enhanced else "default", quality],
			triangle_budget > 0 and triangles <= triangle_budget, str(triangles))
		_check("%s %s placements are nested in the preceding quality tier" % ["enhanced" if expect_enhanced else "default", quality],
			nested)
		result.append({
			"quality": quality,
			"clump_count": placements.size(),
			"counts_by_asset": counts,
			"source_triangles": triangles,
			"triangle_budget": triangle_budget,
			"matches_quality_limits": counts_match,
			"nested_in_prior_tier": nested,
		})
		prior_rows = rows
	return result


func _verify_near_grass_root(root: Node3D, expect_enhanced: bool) -> Dictionary:
	if root == null:
		_check("near-grass runtime root builds from pack", false)
		return {"available": false}
	var children := root.get_children()
	var placements: Array = root.get_meta("cpu_placements", [])
	var actual_counts: Dictionary = {}
	var qualified_shader := ResourceLoader.load("res://scenery/imported_grass.gdshader") as Shader
	var material_route_ok := bool(root.has_meta("grass_wind")) == expect_enhanced
	var geometry_ok := children.size() == ASSET_IDS.size()
	var triangles := 0
	for placement_value: Variant in placements:
		if placement_value is Dictionary:
			var asset_id := str(placement_value.get("asset_id", ""))
			actual_counts[asset_id] = int(actual_counts.get(asset_id, 0)) + 1
			triangles += int(placement_value.get("source_triangles", 0))
	for child: Node in children:
		if not child is MultiMeshInstance3D:
			geometry_ok = false
			material_route_ok = false
			continue
		var batch := child as MultiMeshInstance3D
		var asset_id := str(batch.name).get_slice("_Part_", 0)
		var parts: Array[Dictionary] = _vegetation.call("get_parts", asset_id)
		var mesh: Mesh = batch.multimesh.mesh if batch.multimesh != null else null
		if parts.is_empty() or mesh == null or parts.size() != 1:
			geometry_ok = false
			material_route_ok = false
			continue
		var source_mesh := parts[0].get("mesh") as Mesh
		var effective_materials: Array = parts[0].get("materials", [])
		geometry_ok = geometry_ok and source_mesh != null and _same_mesh_arrays(source_mesh, mesh)
		geometry_ok = geometry_ok and _mesh_triangle_count(mesh) == _mesh_triangle_count(source_mesh)
		geometry_ok = geometry_ok and batch.multimesh.instance_count == int(actual_counts.get(asset_id, -1))
		for surface_index in range(mesh.get_surface_count()):
			var output_material := mesh.surface_get_material(surface_index)
			var source_material := effective_materials[surface_index] as StandardMaterial3D if surface_index < effective_materials.size() else null
			if expect_enhanced:
				var shader_material := output_material as ShaderMaterial
				material_route_ok = material_route_ok and shader_material != null and source_material != null
				if shader_material != null and source_material != null:
					material_route_ok = material_route_ok and shader_material.shader == qualified_shader
					material_route_ok = material_route_ok and shader_material.get_shader_parameter("albedo_texture") == source_material.albedo_texture
					material_route_ok = material_route_ok and bool(shader_material.get_shader_parameter("use_vertex_color")) == source_material.vertex_color_use_as_albedo
					material_route_ok = material_route_ok and _color_equal(shader_material.get_shader_parameter("albedo_color"), source_material.albedo_color)
					material_route_ok = material_route_ok and _vector2_equal(shader_material.get_shader_parameter("uv1_scale"),
						Vector2(source_material.uv1_scale.x, source_material.uv1_scale.y))
					material_route_ok = material_route_ok and _vector2_equal(shader_material.get_shader_parameter("uv1_offset"),
						Vector2(source_material.uv1_offset.x, source_material.uv1_offset.y))
					material_route_ok = material_route_ok and is_equal_approx(float(shader_material.get_shader_parameter("roughness")), source_material.roughness)
					material_route_ok = material_route_ok and is_equal_approx(float(shader_material.get_shader_parameter("metallic")), source_material.metallic)
					material_route_ok = material_route_ok and is_equal_approx(float(shader_material.get_shader_parameter("specular")), source_material.metallic_specular)
			else:
				material_route_ok = material_route_ok and output_material == source_material
	_check("%s high-tier root preserves all three source meshes, arrays and counts" % ("enhanced" if expect_enhanced else "default"),
		geometry_ok and placements.size() == int(root.get_meta("clumps", -1)) and triangles == int(root.get_meta("source_triangles", -1)),
		"batches=%d placements=%d triangles=%d" % [children.size(), placements.size(), triangles])
	_check("%s high-tier root uses only its intended grass material route" % ("enhanced" if expect_enhanced else "default"),
		material_route_ok,
		"grass_wind=%s" % str(root.has_meta("grass_wind")))
	return {
		"available": true,
		"enhanced": expect_enhanced,
		"clumps": placements.size(),
		"source_triangles": triangles,
		"asset_batches": children.size(),
		"counts_by_asset": actual_counts,
		"geometry_contract": geometry_ok,
		"material_route_contract": material_route_ok,
	}


func _verify_material_isolation(root_a: Node3D, root_b: Node3D) -> void:
	var first := _batch_materials(root_a)
	var second := _batch_materials(root_b)
	var isolated := first.size() == ASSET_IDS.size() and second.size() == ASSET_IDS.size()
	for asset_id: String in ASSET_IDS:
		var first_pair: Dictionary = first.get(asset_id, {})
		var second_pair: Dictionary = second.get(asset_id, {})
		var first_mesh: Mesh = first_pair.get("mesh")
		var second_mesh: Mesh = second_pair.get("mesh")
		var first_material := first_pair.get("material") as ShaderMaterial
		var second_material := second_pair.get("material") as ShaderMaterial
		isolated = isolated and first_mesh != null and second_mesh != null and first_mesh != second_mesh
		isolated = isolated and first_material != null and second_material != null and first_material != second_material
		if first_material != null and second_material != null:
			var second_roughness: Variant = second_material.get_shader_parameter("roughness")
			first_material.set_shader_parameter("roughness", 0.37)
			isolated = isolated and is_equal_approx(float(second_material.get_shader_parameter("roughness")), float(second_roughness))
	_check("independent enhanced builds own distinct ArrayMesh and ShaderMaterial resources", isolated)
	_report["material_isolation"] = {
		"independent_root_meshes_and_materials": isolated,
		"shared_mutable_materials": false if isolated else "failed or unavailable",
		"shared_source_textures_expected": true,
	}


func _verify_ground_bindings() -> void:
	var previous_quality := OS.get_environment(SELECTOR)
	OS.set_environment(SELECTOR, "")
	var ordinary := _ground.call("grass_material") as ShaderMaterial
	var ordinary_peer := _ground.call("grass_material") as ShaderMaterial
	var rc_material := _ground.call("grass_material") as ShaderMaterial
	_rc_detail.call("configure", rc_material)
	var default_clean: bool = ordinary.get_shader_parameter("grass_photo_enabled") != true \
		and ordinary.get_shader_parameter("rc_surface_enabled") != true \
		and ordinary.get_shader_parameter("rc_track_surface") != true \
		and ordinary.get_shader_parameter("rc_dirt_albedo") == null
	_check("default ground keeps optional photo and RC surface bindings disabled", default_clean)
	var rc_separate: bool = rc_material.get_shader_parameter("rc_surface_enabled") == true \
		and rc_material.get_shader_parameter("grass_photo_enabled") != true \
		and ordinary.get_shader_parameter("rc_surface_enabled") != true \
		and ordinary.get_shader_parameter("rc_dirt_albedo") == null
	_check("RC binder enables its own dirt/track route without mutating ordinary grass", rc_separate)
	_check("ordinary and RC ground materials are independent", ordinary != rc_material and ordinary != ordinary_peer)
	var rc_map_status := _check_bound_maps(rc_material, true)
	OS.set_environment(SELECTOR, "enhanced")
	var enhanced := _ground.call("grass_material") as ShaderMaterial
	var enhanced_peer := _ground.call("grass_material") as ShaderMaterial
	var photo_branch: bool = enhanced.get_shader_parameter("grass_photo_enabled") == true \
		and enhanced.get_shader_parameter("rc_surface_enabled") != true \
		and enhanced.get_shader_parameter("rc_track_surface") != true \
		and enhanced.get_shader_parameter("rc_dirt_albedo") == null
	_check("enhanced grass binder selects photo grass without enabling RC coverage", photo_branch)
	var photo_map_status := _check_bound_maps(enhanced, false)
	var peer_isolated: bool = enhanced != enhanced_peer \
		and enhanced_peer.get_shader_parameter("grass_photo_enabled") == true \
		and enhanced_peer.get_shader_parameter("rc_surface_enabled") != true \
		and enhanced_peer.get_shader_parameter("rc_dirt_albedo") == null
	_check("enhanced grass binder owns a private material and does not leak into RC", peer_isolated)
	_report["grass_material_routes"] = {
		"default": {"photo_enabled": ordinary.get_shader_parameter("grass_photo_enabled") == true,
			"rc_surface_enabled": ordinary.get_shader_parameter("rc_surface_enabled") == true,
			"rc_dirt_bound": ordinary.get_shader_parameter("rc_dirt_albedo") != null,
			"turf_detail_path": _resource_path(ordinary.get_shader_parameter("turf_detail"))},
		"rc": {"rc_surface_enabled": rc_material.get_shader_parameter("rc_surface_enabled") == true,
			"photo_enabled": rc_material.get_shader_parameter("grass_photo_enabled") == true,
			"six_rc_maps_bound": rc_map_status},
		"enhanced_grass": {"photo_enabled": enhanced.get_shader_parameter("grass_photo_enabled") == true,
			"rc_surface_enabled": enhanced.get_shader_parameter("rc_surface_enabled") == true,
			"rc_dirt_bound": enhanced.get_shader_parameter("rc_dirt_albedo") != null,
			"three_grass_maps_bound": photo_map_status,
			"turf_detail_path": _resource_path(enhanced.get_shader_parameter("turf_detail"))},
		"private_materials": ordinary != ordinary_peer and enhanced != enhanced_peer,
		"rc_separate_from_grass": rc_separate and photo_branch and peer_isolated,
	}
	OS.set_environment(SELECTOR, previous_quality)


func _check_bound_maps(material: ShaderMaterial, expect_rc: bool) -> bool:
	var expected: Array[Dictionary] = []
	if expect_rc:
		expected.append_array(RC_TEXTURES)
	expected.append_array(PHOTO_TEXTURES)
	var ok := true
	for spec: Dictionary in expected:
		var parameter := str(spec.get("parameter", ""))
		var texture := material.get_shader_parameter(parameter) as Texture2D
		var expected_texture := ResourceLoader.load(str(spec.path)) as Texture2D
		ok = ok and texture != null and texture == expected_texture
	return ok


func _batch_materials(root: Node3D) -> Dictionary:
	var result := {}
	if root == null:
		return result
	for child: Node in root.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var batch := child as MultiMeshInstance3D
		var asset_id := str(batch.name).get_slice("_Part_", 0)
		var mesh := batch.multimesh.mesh if batch.multimesh != null else null
		var material := mesh.surface_get_material(0) as Material if mesh != null and mesh.get_surface_count() > 0 else null
		result[asset_id] = {"mesh": mesh, "material": material}
	return result


func _source_pack_hash_record(resource_path: String, required: bool) -> Dictionary:
	var source_path := _source_absolute(resource_path)
	var source_hash := _sha256_file(source_path)
	var pack_available := FileAccess.file_exists(resource_path)
	var pack_hash := _sha256_virtual(resource_path) if pack_available else "unavailable"
	var identical := not source_hash.is_empty() and source_hash == pack_hash
	return {
		"path": resource_path,
		"required_in_pack": required,
		"source_available": not source_hash.is_empty(),
		"source_sha256": source_hash,
		"packed_raw_available": pack_available,
		"packed_raw_sha256": pack_hash,
		"byte_identical": identical,
	}


func _source_absolute(resource_path: String) -> String:
	var relative := resource_path.trim_prefix("res://").replace("/", "\\")
	return _source_root.path_join(relative).replace("\\", "/")


func _absolute_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return ProjectSettings.globalize_path(normalized).replace("\\", "/")
	return normalized if normalized.is_absolute_path() else ""


func _sha256_virtual(resource_path: String) -> String:
	return _sha256_file(resource_path)


func _sha256_file(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while not file.eof_reached():
		var block := file.get_buffer(1024 * 1024)
		if block.is_empty():
			break
		context.update(block)
	file.close()
	return context.finish().hex_encode()


func _sha256_text(value: String) -> String:
	if value.is_empty():
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _read_source_text(resource_path: String) -> String:
	var source_path := _source_absolute(resource_path)
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return ""
	var value := file.get_as_text()
	file.close()
	return value


func _decoded_image_hash(image: Image) -> String:
	if image == null or image.is_empty():
		return ""
	var normalized := image.duplicate() as Image
	if normalized.is_compressed() and normalized.decompress() != OK:
		return ""
	normalized.clear_mipmaps()
	normalized.convert(Image.FORMAT_RGBA8)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(normalized.get_data())
	return context.finish().hex_encode()


func _placement_counts(placements: Array[Dictionary]) -> Dictionary:
	var result := {}
	for asset_id: String in ASSET_IDS:
		result[asset_id] = 0
	for placement: Dictionary in placements:
		var asset_id := str(placement.get("asset_id", ""))
		result[asset_id] = int(result.get(asset_id, 0)) + 1
	return result


func _placement_triangles(placements: Array[Dictionary]) -> int:
	var result := 0
	for placement: Dictionary in placements:
		result += int(placement.get("source_triangles", 0))
	return result


func _placement_rows(placements: Array[Dictionary]) -> Dictionary:
	var result := {}
	for placement: Dictionary in placements:
		result[int(placement.get("row_index", -1))] = true
	return result


func _mesh_triangle_count(mesh: Mesh) -> int:
	var total := 0
	if mesh == null:
		return 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
	return total


func _same_mesh_arrays(left: Mesh, right: Mesh) -> bool:
	if left == null or right == null or left.get_surface_count() != right.get_surface_count():
		return false
	for surface_index in range(left.get_surface_count()):
		var left_arrays := left.surface_get_arrays(surface_index)
		var right_arrays := right.surface_get_arrays(surface_index)
		if left_arrays != right_arrays:
			return false
	return true


func _color_equal(left: Variant, right: Color) -> bool:
	if not left is Color:
		return false
	var color := left as Color
	return is_equal_approx(color.r, right.r) and is_equal_approx(color.g, right.g) \
		and is_equal_approx(color.b, right.b) and is_equal_approx(color.a, right.a)


func _vector2_equal(left: Variant, right: Vector2) -> bool:
	return left is Vector2 and (left as Vector2).distance_to(right) < 0.0001


func _aabb_summary(bounds: AABB) -> Dictionary:
	return {"position": [bounds.position.x, bounds.position.y, bounds.position.z],
		"size": [bounds.size.x, bounds.size.y, bounds.size.z]}


func _resource_path(value: Variant) -> String:
	return value.resource_path if value is Resource else "unavailable"


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	(_report["checks"] as Array).append({"label": label, "passed": passed, "detail": detail})
	if passed:
		print("PASS: " + label)
	else:
		_failures += 1
		printerr("FAIL: %s %s" % [label, detail])


func _write_report() -> bool:
	var parent := _report_path.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(parent)
	if mkdir_error != OK and not DirAccess.dir_exists_absolute(parent):
		printerr("Could not create grass pack evidence directory: " + parent)
		return false
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write grass pack evidence: " + _report_path)
		return false
	file.store_string(JSON.stringify(_report, "\t") + "\n")
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		printerr("Could not finish grass pack evidence: " + _report_path)
		return false
	return true
