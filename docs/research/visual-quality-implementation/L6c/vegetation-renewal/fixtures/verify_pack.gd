extends SceneTree

## Run this script from an empty host project so resources can only resolve from the PCK.
## Example: godot --headless --path <empty-host> --script <this-file> -- <export.pck>

const TREE_CATALOG_PATH := "res://assets/landscape/trees/catalog.json"
const VEGETATION_CATALOG_PATH := "res://assets/landscape/vegetation/catalog.json"
const TREE_LICENSE_PATH := "res://assets/landscape/trees/LICENSE.txt"
const UNDERSTORY_LICENSE_PATH := "res://assets/landscape/vegetation/LICENSE_UNDERSTORY.txt"

const EXPECTED_TREE_SPECIES := {
	"CommonTree_1": {
		"source_asset_id": "landscapelab:quercus",
		"source_name": "Quercus",
		"license": "CC BY-SA 4.0",
		"notice_tokens": ["landscapelab", "quercus", "cc by-sa 4.0"],
	},
	"CommonTree_3": {
		"source_asset_id": "lolipop:acer_large_3_lod1",
		"source_name": "Maple",
		"license": "CC BY 4.0",
		"notice_tokens": ["lolipop", "maple", "cc by 4.0"],
	},
	"Pine_1": {
		"source_asset_id": "landscapelab:pine",
		"source_name": "Pine",
		"license": "CC BY-SA 4.0",
		"notice_tokens": ["landscapelab", "pine", "cc by-sa 4.0"],
	},
}

const EXPECTED_VEGETATION_ASSETS := {
	"landscapelab_quercus": {
		"source_id": "landscapelab_tree_2026",
		"source_name": "Quercus",
		"role": "tree",
		"scene": "res://assets/landscape/vegetation/models/landscapelab_tree_2026/quercus/quercus.glb",
		"triangles": 7016,
		"surfaces": 2,
	},
	"landscapelab_pine": {
		"source_id": "landscapelab_tree_2026",
		"source_name": "Pine",
		"role": "tree",
		"scene": "res://assets/landscape/vegetation/models/landscapelab_tree_2026/pine/pine_joined.glb",
		"triangles": 4246,
		"surfaces": 2,
	},
	"polyhaven_fern_02_a": {
		"source_id": "polyhaven_fern_02",
		"source_name": "fern_02_a",
		"role": "herb",
		"scene": "res://assets/landscape/vegetation/models/realistic_understory_2026/fern_02_a.gltf",
		"triangles": 784,
		"surfaces": 1,
	},
	"polyhaven_flower_empodium_a": {
		"source_id": "polyhaven_flower_empodium",
		"source_name": "flower_empodium_a_LOD0",
		"role": "flower",
		"scene": "res://assets/landscape/vegetation/models/realistic_understory_2026/flower_empodium_a.gltf",
		"triangles": 758,
		"surfaces": 1,
	},
}

const EXPECTED_POLYHAVEN_SOURCES := {
	"polyhaven_fern_02": {
		"title": "Fern 02",
		"url": "https://polyhaven.com/a/fern_02",
	},
	"polyhaven_flower_empodium": {
		"title": "Flower Empodium",
		"url": "https://polyhaven.com/a/flower_empodium",
	},
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		_fail("Usage: godot --headless --path <empty-host> --script verify_pack.gd -- <export.pck>")
		return
	if not ProjectSettings.load_resource_pack(args[0], true):
		_fail("Could not mount export pack: " + args[0])
		return

	var tree_error := _check_tree_catalog_and_notices()
	if not tree_error.is_empty():
		_fail(tree_error)
		return
	var catalog: Dictionary = _read_json(VEGETATION_CATALOG_PATH)
	if catalog.is_empty():
		_fail("Missing or invalid vegetation catalog")
		return
	var vegetation_error := _check_vegetation_sources(catalog)
	if not vegetation_error.is_empty():
		_fail(vegetation_error)
		return
	var scene_error := _check_scenes(catalog)
	if not scene_error.is_empty():
		_fail(scene_error)
		return

	print("PASS: tree atlas/mask, three tree notices, Poly Haven notices, and four packed vegetation scenes")
	quit(0)


func _check_tree_catalog_and_notices() -> String:
	var catalog: Dictionary = _read_json(TREE_CATALOG_PATH)
	if catalog.is_empty() or catalog.get("format", "") != "openrc-tree-assets v1":
		return "Missing or invalid tree atlas/mask catalog"
	if catalog.get("atlas", "") != "res://assets/landscape/trees/atlas.png" \
			or catalog.get("foliage_mask", "") != "res://assets/landscape/trees/foliage_mask.png" \
			or int(catalog.get("atlas_size_px", 0)) != 1024 \
			or int(catalog.get("tile_size_px", 0)) != 512 \
			or not is_equal_approx(float(catalog.get("alpha_cutoff", -1.0)), 0.5):
		return "Tree atlas/mask catalog paths or dimensions changed"

	var atlas := ResourceLoader.load(str(catalog.atlas)) as Texture2D
	var mask := ResourceLoader.load(str(catalog.foliage_mask)) as Texture2D
	if not _texture_is_readable(atlas) or not _texture_is_readable(mask) \
			or atlas.get_width() != 1024 or atlas.get_height() != 1024 \
			or mask.get_width() != 1024 or mask.get_height() != 1024 \
			or not _image_alpha_equal(atlas.get_image(), mask.get_image()):
		return "Tree atlas or alpha-aligned foliage mask is missing or invalid"

	var species: Variant = catalog.get("species", null)
	if not (species is Array) or species.size() != EXPECTED_TREE_SPECIES.size():
		return "Tree catalog must contain exactly the three credited source slots"
	var seen: Dictionary = {}
	for entry: Variant in species:
		if not (entry is Dictionary):
			return "Malformed tree species entry"
		var id := str(entry.get("id", ""))
		if not EXPECTED_TREE_SPECIES.has(id) or seen.has(id):
			return "Unexpected or duplicate tree species: " + id
		seen[id] = true
		var expected: Dictionary = EXPECTED_TREE_SPECIES[id]
		var provenance: Variant = entry.get("source_provenance", null)
		if not (provenance is Dictionary) \
				or provenance.get("license_file", "") != "licenses/%s.txt" % id \
				or provenance.get("license", "") != expected.license \
				or entry.get("source_asset_id", "") != expected.source_asset_id:
			return "Tree source attribution mismatch for " + id
		var notice_path := "res://assets/landscape/trees/" + str(provenance.license_file)
		var notice_text := _read_text(notice_path)
		if notice_text.is_empty():
			return "Missing tree source notice: " + notice_path
		for token: String in expected.notice_tokens:
			if not notice_text.to_lower().contains(token):
				return "Tree source notice for %s is missing %s" % [id, token]
	if seen.size() != EXPECTED_TREE_SPECIES.size():
		return "Tree catalog is missing a credited species"
	var combined_notice := _read_text(TREE_LICENSE_PATH)
	if combined_notice.is_empty() or not combined_notice.contains("CC BY-SA 4.0") \
			or not combined_notice.contains("atlas-aligned foliage material mask"):
		return "Missing combined tree atlas/mask license and attribution"
	print("Tree atlas/mask catalog and three source notices validated")
	return ""


func _check_vegetation_sources(catalog: Dictionary) -> String:
	var assets: Variant = catalog.get("assets", null)
	var sources: Variant = catalog.get("sources", null)
	if not (assets is Array) or not (sources is Array):
		return "Vegetation catalog has no assets or source records"
	var found_sources: Dictionary = {}
	for source: Variant in sources:
		if source is Dictionary:
			var source_id := str(source.get("id", ""))
			if EXPECTED_POLYHAVEN_SOURCES.has(source_id):
				if found_sources.has(source_id):
					return "Duplicate Poly Haven source record: " + source_id
				found_sources[source_id] = source
	for source_id: String in EXPECTED_POLYHAVEN_SOURCES:
		if not found_sources.has(source_id):
			return "Vegetation catalog is missing source record: " + source_id
		var source_record: Dictionary = found_sources[source_id]
		var expected_source: Dictionary = EXPECTED_POLYHAVEN_SOURCES[source_id]
		if source_record.get("title", "") != expected_source.title \
				or source_record.get("url", "") != expected_source.url \
				or source_record.get("license", "") != "CC0-1.0" \
				or source_record.get("license_url", "") != "https://creativecommons.org/publicdomain/zero/1.0/" \
				or source_record.get("license_statement_url", "") != "https://polyhaven.com/license":
			return "Incorrect Poly Haven source or license metadata for " + source_id
	var catalog_files: Variant = catalog.get("files", null)
	if not (catalog_files is Array):
		return "Vegetation catalog has no runtime file inventory"
	var license_record: Dictionary = {}
	for file_record: Variant in catalog_files:
		if file_record is Dictionary and file_record.get("path", "") == "LICENSE_UNDERSTORY.txt":
			license_record = file_record
			break
	if license_record.is_empty():
		return "Vegetation catalog does not ship LICENSE_UNDERSTORY.txt"
	var notice_path := "res://assets/landscape/vegetation/" + str(license_record.get("path", ""))
	var shared_notice_raw := _read_text(notice_path)
	var shared_notice := shared_notice_raw.to_lower()
	if notice_path != UNDERSTORY_LICENSE_PATH or shared_notice.is_empty() \
			or shared_notice_raw.to_utf8_buffer().size() != int(license_record.get("bytes", -1)) \
			or FileAccess.get_sha256(notice_path) != str(license_record.get("sha256", "")):
		return "Missing or altered packaged Poly Haven license: " + notice_path
	for source_id: String in EXPECTED_POLYHAVEN_SOURCES:
		var expected_source: Dictionary = EXPECTED_POLYHAVEN_SOURCES[source_id]
		if not shared_notice.contains(str(expected_source.title).to_lower()) \
				or not shared_notice.contains(str(expected_source.url).to_lower()):
			return "Packaged Poly Haven license is missing source attribution for " + source_id
	if not shared_notice.contains("cc0 1.0") \
			or not shared_notice.contains("https://polyhaven.com/license") \
			or not shared_notice.contains("https://creativecommons.org/publicdomain/zero/1.0/legalcode.en"):
		return "Packaged Poly Haven license is missing CC0 license references"

	var found_assets: Dictionary = {}
	for asset: Variant in assets:
		if not (asset is Dictionary):
			continue
		var asset_id := str(asset.get("id", ""))
		if EXPECTED_VEGETATION_ASSETS.has(asset_id):
			if found_assets.has(asset_id):
				return "Duplicate vegetation asset record: " + asset_id
			found_assets[asset_id] = asset
	for asset_id: String in EXPECTED_VEGETATION_ASSETS:
		if not found_assets.has(asset_id):
			return "Vegetation catalog is missing asset: " + asset_id
		var asset_record: Dictionary = found_assets[asset_id]
		var expected: Dictionary = EXPECTED_VEGETATION_ASSETS[asset_id]
		if asset_record.get("source_id", "") != expected.source_id \
				or asset_record.get("source_name", "") != expected.source_name \
				or asset_record.get("role", "") != expected.role \
				or asset_record.get("scene", "") != expected.scene \
				or int(asset_record.get("source_triangles", 0)) != expected.triangles \
				or int(asset_record.get("source_surfaces", 0)) != expected.surfaces:
			return "Vegetation source contract changed for " + asset_id
	print("Vegetation catalog and Poly Haven CC0 notices validated")
	return ""


func _check_scenes(catalog: Dictionary) -> String:
	var assets: Array = catalog.assets
	for asset_id: String in EXPECTED_VEGETATION_ASSETS:
		var expected: Dictionary = EXPECTED_VEGETATION_ASSETS[asset_id]
		var scene_path: String = expected.scene
		var packed := ResourceLoader.load(scene_path) as PackedScene
		if packed == null:
			return "Could not load packed scene from catalog path: " + scene_path
		var instance := packed.instantiate()
		if instance == null:
			return "Could not instantiate packed scene: " + asset_id
		var stats := {"triangles": 0, "surfaces": 0, "materials": {}, "textures": {}}
		var inspect_error := _inspect_node(instance, stats, asset_id)
		instance.free()
		if not inspect_error.is_empty():
			return inspect_error
		if int(stats.triangles) != int(expected.triangles) \
				or int(stats.surfaces) != int(expected.surfaces) \
				or stats.materials.is_empty() or stats.textures.is_empty():
			return "Packed scene geometry/material/texture mismatch for %s (triangles=%d surfaces=%d materials=%d textures=%d)" % [
			asset_id, stats.triangles, stats.surfaces, stats.materials.size(), stats.textures.size()]
		print("Scene %s: %d source triangles, %d surfaces, %d materials, %d textures" % [
			asset_id, stats.triangles, stats.surfaces, stats.materials.size(), stats.textures.size()])
	return ""


func _inspect_node(node: Node, stats: Dictionary, asset_id: String) -> String:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			return "Packed scene has an empty mesh: " + asset_id
		for surface_index in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				return "Packed scene has a non-triangle surface: " + asset_id
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			var element_count: int = indices.size() if indices is PackedInt32Array and not indices.is_empty() else vertices.size()
			if element_count <= 0 or element_count % 3 != 0:
				return "Packed scene has invalid triangle arrays: " + asset_id
			stats.triangles += int(element_count / 3)
			stats.surfaces += 1
			var material := mesh_instance.get_active_material(surface_index)
			if material == null:
				return "Packed scene surface has no material: %s surface %d" % [asset_id, surface_index]
			stats.materials[material.get_instance_id()] = true
			var texture_error := _inspect_material_textures(material, stats, asset_id)
			if not texture_error.is_empty():
				return texture_error
	for child: Node in node.get_children():
		var child_error := _inspect_node(child, stats, asset_id)
		if not child_error.is_empty():
			return child_error
	return ""


func _inspect_material_textures(material: Material, stats: Dictionary, asset_id: String) -> String:
	var texture_values: Array[Texture2D] = []
	if material is BaseMaterial3D:
		for property: Dictionary in material.get_property_list():
			var property_value: Variant = material.get(str(property.name))
			if property_value is Texture2D:
				texture_values.append(property_value)
	elif material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		if shader_material.shader != null:
			for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
				var uniform_value: Variant = shader_material.get_shader_parameter(str(uniform.get("name", "")))
				if uniform_value is Texture2D:
					texture_values.append(uniform_value)
	for texture: Texture2D in texture_values:
		if not _texture_is_readable(texture):
			return "Packed scene material references an unreadable texture: " + asset_id
		stats.textures[texture.get_instance_id()] = true
	return ""


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _texture_is_readable(texture: Texture2D) -> bool:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return false
	var image := texture.get_image()
	return image != null and not image.is_empty()


func _image_alpha_equal(left: Image, right: Image) -> bool:
	if left == null or right == null or left.is_empty() or right.is_empty() \
			or left.get_size() != right.get_size() \
			or left.get_format() != Image.FORMAT_RGBA8 or right.get_format() != Image.FORMAT_RGBA8:
		return false
	var left_data := left.get_data()
	var right_data := right.get_data()
	if left_data.size() != right_data.size():
		return false
	for alpha_index in range(3, left_data.size(), 4):
		if left_data[alpha_index] != right_data[alpha_index]:
			return false
	return true


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
