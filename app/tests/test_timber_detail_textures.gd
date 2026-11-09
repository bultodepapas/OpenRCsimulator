## TT-04-R1: inspect the imported resources, not only their saved importer settings.
extends SceneTree

const Details := preload("res://aircraft/timber_visual_details.gd")
const Paint := preload("res://aircraft/procedural_skin.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	for texture: Texture2D in [Details.FOAM_NORMAL, Details.FOAM_ROUGHNESS, Details.RUBBER_NORMAL, Details.RUBBER_ROUGHNESS]:
		var image := texture.get_image()
		var label := texture.resource_path.get_file()
		_check(label + " is readable", image != null and not image.is_empty())
		if image == null or image.is_empty():
			continue
		_check(label + " has all ten mip levels", image.get_size() == Vector2i(1024, 1024) and image.get_mipmap_count() == 10)
		# Lossless data imports preserve the decoded JPEG at level zero. These maps are not sRGB color.
		var source := Image.new()
		var decoded := source.load_jpg_from_buffer(FileAccess.get_file_as_bytes(texture.resource_path))
		_check(label + " source JPEG decodes", decoded == OK)
		_check(label + " preserves source format", source != null and image.get_format() == source.get_format())
		var base := image.duplicate() as Image
		base.clear_mipmaps()
		_check(label + " preserves every source base-level byte", source != null and base.get_data() == source.get_data())
		print("DETAIL_TEXTURE ", JSON.stringify({path = texture.resource_path, size = [image.get_width(), image.get_height()],
			format = image.get_format(), mipmaps = image.get_mipmap_count(), bytes = image.get_data_size(),
			base_sha256 = _digest(base.get_data()), data_sha256 = _digest(image.get_data())}))
	# The existing paint adapter must receive the same filtered data without losing material strength or scale.
	var material := StandardMaterial3D.new()
	Details._apply_surface_texture(material, {texture = "foam", normal_scale = 0.035, world_tiling_per_m = 3.0})
	material.resource_name = "openrc-paint-white"
	var painted := Paint.paint(material, {base_color = [0.1, 0.5, 0.8, 1.0]}, null) as ShaderMaterial
	_check("custom foam paint builds", painted != null)
	if painted != null:
		_check("custom paint shares the imported normal and roughness resources",
			painted.get_shader_parameter("foam_normal") == Details.FOAM_NORMAL
			and painted.get_shader_parameter("foam_roughness") == Details.FOAM_ROUGHNESS)
		_check("custom paint retains normal strength and local texture scale",
			is_equal_approx(float(painted.get_shader_parameter("normal_strength")), 0.035)
			and painted.get_shader_parameter("foam_scale") == Vector3.ONE * 3.0)
	print("%d Timber detail texture checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed:
		_failures += 1
