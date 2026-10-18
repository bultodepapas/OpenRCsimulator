# Run with --main-pack from an empty project root, followed by catalog/license hashes.
# Every oak PCK check requires the oak base-image hash printed by the source-app inventory.
extends SceneTree

const OAK_ASSET_ID := "oak_tree"
const OAK_SOURCE_ID := "opengameart_oak_tree_lod_2026"
const OAK_TEXTURE_FILE := "Quercus_A_1024.png"
const OAK_LICENSE_SHA256 := "1be8dab83f4107623eeba4d77e3d66091068e839e1a8b688ea1bf867c2b43e40"

var _textures: Dictionary = {}
var _mip_policy := "observe"
var _expected_oak_base_image_sha256 := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 4:
		_fail("expected catalog and license SHA-256 arguments, optionally a mip policy and oak image SHA-256")
		return
	for option_index in range(2, args.size()):
		var option := str(args[option_index])
		if option in ["--require-mipmaps", "--mip-policy=bark"] and _mip_policy == "observe":
			_mip_policy = "bark" if option == "--mip-policy=bark" else "all"
		elif option.begins_with("--oak-base-image-sha256=") and _expected_oak_base_image_sha256.is_empty():
			_expected_oak_base_image_sha256 = option.trim_prefix("--oak-base-image-sha256=").to_lower()
			if _expected_oak_base_image_sha256.length() != 64 or not _expected_oak_base_image_sha256.is_valid_hex_number():
				_fail("oak base-image SHA-256 argument must contain 64 hexadecimal digits")
				return
		else:
			_fail("unknown or duplicate imported-pack option: " + option)
			return
	var paths := ["res://assets/landscape/vegetation/catalog.json", "res://assets/landscape/vegetation/LICENSE.txt"]
	for index in range(paths.size()):
		if not FileAccess.file_exists(paths[index]) or FileAccess.get_sha256(paths[index]) != args[index]:
			_fail("pack resource missing or changed: " + paths[index])
			return
	var adapter: Script = load("res://scenery/imported_vegetation.gd")
	if adapter == null:
		_fail("pack has no imported vegetation adapter")
		return
	var catalog_json := JSON.new()
	if catalog_json.parse(FileAccess.get_file_as_string(paths[0])) != OK or typeof(catalog_json.data) != TYPE_DICTIONARY:
		_fail("pack vegetation catalog is not a valid object")
		return
	var catalog: Dictionary = catalog_json.data
	var ids := ["common_tree_1", "common_tree_2", "common_tree_3", "common_tree_4", "pine_1", "pine_2", "pine_3"]
	var surfaces := 0
	var normal_maps := 0
	for id: String in ids:
		var parts: Array = adapter.get_parts(id)
		if parts.is_empty():
			_fail("pack has no imported tree parts: " + id)
			return
		for part: Dictionary in parts:
			for value: Variant in part.get("materials", []):
				var material := value as BaseMaterial3D
				if material == null or not _texture_valid(material.albedo_texture):
					_fail("pack lost source material/albedo: " + id)
					return
				surfaces += 1
				if material.normal_enabled:
					if not _texture_valid(material.normal_texture):
						_fail("pack lost bark normal map: " + id)
						return
					normal_maps += 1
	if surfaces != 14 or normal_maps != 7:
		_fail("pack tree surface/normal-map inventory changed")
		return
	print("Tree pack: seven sources, 14 material surfaces, seven bark normal maps, catalog and CC0 license verified")
	if not _verify_optional_oak(catalog, adapter):
		return
	print("TREE_TEXTURE_INVENTORY=" + JSON.stringify(_textures))
	quit(0)


func _texture_valid(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var picture := texture.get_image()
	if picture == null or picture.is_empty():
		return false
	if _mip_policy != "observe":
		var expected_mips := _mip_policy == "all" or texture.resource_path.get_file().begins_with("Bark_")
		if picture.has_mipmaps() != expected_mips:
			printerr("unexpected imported mip chain: " + texture.resource_path)
			return false
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(picture.get_data())
	var base_image := picture.duplicate() as Image
	base_image.clear_mipmaps()
	var base_context := HashingContext.new()
	base_context.start(HashingContext.HASH_SHA256)
	base_context.update(base_image.get_data())
	# Mip availability is an observed source property, not an export assumption.
	_textures[texture.resource_path] = {
		"width": picture.get_width(), "height": picture.get_height(),
		"format": picture.get_format(), "mipmaps": picture.has_mipmaps(),
		"mipmap_count": picture.get_mipmap_count(), "decoded_bytes": picture.get_data().size(),
		"base_image_sha256": base_context.finish().hex_encode(),
		"image_sha256": context.finish().hex_encode(),
	}
	return true


func _verify_optional_oak(catalog: Dictionary, adapter: Script) -> bool:
	var assets_value: Variant = catalog.get("assets", [])
	var sources_value: Variant = catalog.get("sources", [])
	if typeof(assets_value) != TYPE_ARRAY or typeof(sources_value) != TYPE_ARRAY:
		return _oak_fail("vegetation catalog is missing its assets/sources arrays")
	var oak_assets: Array[Dictionary] = []
	for asset_value in assets_value:
		if typeof(asset_value) != TYPE_DICTIONARY:
			return _oak_fail("vegetation catalog contains a non-object asset entry")
		var asset: Dictionary = asset_value
		if str(asset.get("id", "")) == OAK_ASSET_ID:
			oak_assets.append(asset)
	var oak_sources: Array[Dictionary] = []
	for source_value in sources_value:
		if typeof(source_value) != TYPE_DICTIONARY:
			return _oak_fail("vegetation catalog contains a non-object source entry")
		var source: Dictionary = source_value
		if str(source.get("id", "")) == OAK_SOURCE_ID:
			oak_sources.append(source)
	if oak_assets.is_empty() and oak_sources.is_empty():
		var legacy_counts_value: Variant = catalog.get("counts", {})
		if assets_value.size() != 19 or typeof(legacy_counts_value) != TYPE_DICTIONARY or int(legacy_counts_value.get("total_assets", -1)) != 19:
			return _oak_fail("catalog without oak must be the frozen 19-asset pack")
		print("Oak pack check: frozen catalog has no oak entry; legacy 19-asset pack accepted")
		return true
	if oak_assets.size() != 1 or oak_sources.size() != 1:
		return _oak_fail("oak asset/source must each occur exactly once in the catalog")
	var counts_value: Variant = catalog.get("counts", {})
	if typeof(counts_value) != TYPE_DICTIONARY:
		return _oak_fail("catalog with oak is missing its counts object")
	var counts: Dictionary = counts_value
	if assets_value.size() != 20 or int(counts.get("total_assets", -1)) != 20:
		return _oak_fail("catalog with oak must contain exactly 20 assets")
	var asset: Dictionary = oak_assets[0]
	var oak_source: Dictionary = oak_sources[0]
	if str(asset.get("source_id", "")) != OAK_SOURCE_ID or str(asset.get("role", "")) != "tree":
		return _oak_fail("oak catalog entry has an unexpected source id or role")
	if str(asset.get("scene", "")) != "res://assets/landscape/vegetation/models/oak_tree/oak_lod0.gltf":
		return _oak_fail("oak catalog entry does not point to the reviewed LOD0 glTF")
	if int(asset.get("source_triangles", -1)) != 5303:
		return _oak_fail("oak catalog source triangle count changed from 5,303")
	if int(asset.get("source_surfaces", -1)) != 1 or int(asset.get("source_materials", -1)) != 1:
		return _oak_fail("oak catalog must describe one source surface and material")
	var lod: Variant = asset.get("lod", {})
	if typeof(lod) != TYPE_DICTIONARY or str(lod.get("source_lod", "")) != "LOD0":
		return _oak_fail("oak catalog does not identify supplier LOD0 as the sole imported source level")
	if lod.get("imported_supplied_levels", []) != ["LOD0"] or lod.get("alternate_source_lods_included", []) != []:
		return _oak_fail("oak catalog includes an unexpected supplier LOD")
	var source_license_hash := str(oak_source.get("license_sha256", ""))
	if source_license_hash != OAK_LICENSE_SHA256:
		return _oak_fail("oak catalog license SHA-256 differs from the reviewed pin")
	var oak_license_record := _catalog_file_record(catalog, "LICENSE_OAK.txt")
	if oak_license_record.is_empty() or str(oak_license_record.get("sha256", "")) != source_license_hash:
		return _oak_fail("oak runtime license file record does not match the catalog source notice")
	var oak_license_path := "res://assets/landscape/vegetation/LICENSE_OAK.txt"
	if not FileAccess.file_exists(oak_license_path) or FileAccess.get_sha256(oak_license_path) != source_license_hash:
		return _oak_fail("pack oak license is missing or does not match its catalog SHA-256")
	if str(oak_source.get("license", "")) != "CC BY-SA 3.0":
		return _oak_fail("oak catalog license identifier changed")

	var parts: Array[Dictionary] = adapter.get_parts(OAK_ASSET_ID)
	if parts.size() != 1:
		return _oak_fail("oak imported scene must expose exactly one mesh part")
	var part: Dictionary = parts[0]
	var mesh: Mesh = part.get("mesh")
	if mesh == null or int(part.get("source_triangles", -1)) != 5303 or mesh.get_surface_count() != 1:
		return _oak_fail("oak imported mesh must retain one surface and 5,303 triangles")
	var materials_value: Variant = part.get("materials", [])
	if typeof(materials_value) != TYPE_ARRAY or materials_value.size() != 1:
		return _oak_fail("oak imported mesh must retain exactly one material reference")
	var material := materials_value[0] as StandardMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		return _oak_fail("oak imported material must remain standard BLEND with depth pre-pass")
	if not is_equal_approx(material.roughness, 1.0) or not is_equal_approx(material.metallic_specular, 0.5):
		return _oak_fail("oak imported material roughness/specular must remain 1.0/0.5")
	if material.albedo_texture == null:
		return _oak_fail("oak imported BLEND material has no source atlas")

	var textures_value: Variant = asset.get("textures", [])
	if typeof(textures_value) != TYPE_ARRAY or textures_value.size() != 1:
		return _oak_fail("oak catalog must identify exactly one source atlas PNG")
	var texture_record: Variant = textures_value[0]
	if typeof(texture_record) != TYPE_DICTIONARY:
		return _oak_fail("oak source atlas record is malformed")
	var texture_info: Dictionary = texture_record
	var texture_uri := str(texture_info.get("uri", ""))
	if texture_uri != OAK_TEXTURE_FILE or texture_uri.get_file() != texture_uri:
		return _oak_fail("oak source atlas must use the reviewed Quercus_A_1024.png dependency")
	var scene_path := str(asset.get("scene", ""))
	var texture_path := scene_path.get_base_dir().path_join(texture_uri)
	if material.albedo_texture.resource_path != texture_path:
		return _oak_fail("oak imported material does not use its catalog atlas PNG")
	if not _texture_valid(material.albedo_texture):
		return _oak_fail("oak atlas import failed texture or no-mipmap validation")
	var image := material.albedo_texture.get_image()
	if image.get_width() != 1024 or image.get_height() != 1024 or image.has_mipmaps() or image.get_format() != Image.FORMAT_RGBA8:
		return _oak_fail("oak atlas must be lossless RGBA8 at 1024x1024 with no mipmaps")
	var source_hashes: Variant = asset.get("source_dependency_sha256", {})
	if typeof(source_hashes) != TYPE_DICTIONARY:
		return _oak_fail("oak catalog has no source dependency hash map")
	var source_entry := str(texture_info.get("source_entry", ""))
	var expected_source_hash := str(source_hashes.get(source_entry, ""))
	var runtime_rel := "models/oak_tree/" + texture_uri
	var file_record: Dictionary = _catalog_file_record(catalog, runtime_rel)
	if file_record.is_empty() or expected_source_hash.is_empty() or str(file_record.get("sha256", "")) != expected_source_hash:
		return _oak_fail("oak atlas source and runtime file hashes are not pinned consistently in the catalog")
	var inventory_record: Dictionary = _textures.get(material.albedo_texture.resource_path, {})
	var actual_base_image_hash := str(inventory_record.get("base_image_sha256", ""))
	if actual_base_image_hash.is_empty():
		return _oak_fail("oak source-app image inventory is missing its base-image hash")
	if not _expected_oak_base_image_sha256.is_empty() and actual_base_image_hash != _expected_oak_base_image_sha256:
		return _oak_fail("oak imported base image differs from the source-app inventory SHA-256")
	if _is_main_pack_run() and _expected_oak_base_image_sha256.is_empty():
		return _oak_fail("PCK check requires --oak-base-image-sha256 from the source-app inventory")
	if FileAccess.file_exists(texture_path):
		if FileAccess.get_sha256(texture_path) != expected_source_hash:
			return _oak_fail("oak original PNG bytes differ from the source hash pinned in the catalog")
	elif _expected_oak_base_image_sha256.is_empty():
		return _oak_fail("PCK omits source PNG; provide the base-image SHA-256 from the source-app inventory")
	print("OAK_BASE_IMAGE_SHA256=" + actual_base_image_hash)
	if not _verify_static_oak_build(adapter, material):
		return false
	print("Oak pack: one LOD0 mesh, 5,303 triangles, one static BLEND/depth-pre-pass material, original 1024x1024 PNG lossless and unmipped, catalog-pinned CC BY-SA 3.0 notice verified")
	return true


func _catalog_file_record(catalog: Dictionary, runtime_path: String) -> Dictionary:
	var files_value: Variant = catalog.get("files", [])
	if typeof(files_value) != TYPE_ARRAY:
		return {}
	var matches: Array[Dictionary] = []
	for value in files_value:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var record: Dictionary = value
		if str(record.get("path", "")) == runtime_path:
			matches.append(record)
	return matches[0] if matches.size() == 1 else {}


func _verify_static_oak_build(adapter: Script, source_material: StandardMaterial3D) -> bool:
	var batches: Dictionary = {}
	if adapter.queue(batches, OAK_ASSET_ID, Transform3D.IDENTITY, 0) != OAK_ASSET_ID:
		return _oak_fail("oak cannot be queued for the default static build")
	var built: Node3D = adapter.build(batches)
	if built == null or built.get_child_count() != 1:
		if is_instance_valid(built):
			built.free()
		return _oak_fail("default oak build must contain one mesh instance")
	var instance := built.get_child(0) as MultiMeshInstance3D
	if instance == null or bool(instance.get_meta("_imported_vegetation_tree_wind_enabled", false)) or bool(instance.get_meta("_imported_vegetation_wind_enabled", false)):
		built.free()
		return _oak_fail("default oak build unexpectedly enables tree wind")
	var draw_mesh := instance.multimesh.mesh if instance.multimesh != null else null
	if draw_mesh == null or draw_mesh.get_surface_count() != 1:
		built.free()
		return _oak_fail("default oak build changed the one-surface mesh")
	var draw_material := draw_mesh.surface_get_material(0)
	var valid := draw_material == source_material and not (draw_material is ShaderMaterial)
	built.free()
	if not valid:
		return _oak_fail("default oak build must preserve the original static BLEND material reference")
	return true


func _oak_fail(message: String) -> bool:
	_fail(message)
	return false


func _is_main_pack_run() -> bool:
	for argument in OS.get_cmdline_args():
		if str(argument) == "--main-pack" or str(argument).begins_with("--main-pack="):
			return true
	return false


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
