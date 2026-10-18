# Run with --main-pack from an empty project root, followed by catalog/license hashes.
extends SceneTree

var _textures: Dictionary = {}
var _require_mipmaps := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3 or (args.size() == 3 and args[2] != "--require-mipmaps"):
		_fail("expected catalog and license SHA-256 arguments, optionally --require-mipmaps")
		return
	_require_mipmaps = args.size() == 3
	var paths := ["res://assets/landscape/vegetation/catalog.json", "res://assets/landscape/vegetation/LICENSE.txt"]
	for index in range(paths.size()):
		if not FileAccess.file_exists(paths[index]) or FileAccess.get_sha256(paths[index]) != args[index]:
			_fail("pack resource missing or changed: " + paths[index])
			return
	var adapter: Script = load("res://scenery/imported_vegetation.gd")
	if adapter == null:
		_fail("pack has no imported vegetation adapter")
		return
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
	print("TREE_TEXTURE_INVENTORY=" + JSON.stringify(_textures))
	quit(0)


func _texture_valid(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var picture := texture.get_image()
	if picture == null or picture.is_empty():
		return false
	if _require_mipmaps and not picture.has_mipmaps():
		printerr("missing imported mip chain: " + texture.resource_path)
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


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
