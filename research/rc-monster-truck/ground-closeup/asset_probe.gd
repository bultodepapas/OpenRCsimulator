## Imported storage inspection, not a driver residency measurement.
extends SceneTree
const Detail = preload("res://render/rc_ground_material.gd")
func _initialize() -> void:
	var result := {"scope": "Imported compressed image payload including mips; not total driver residency", "maps": [], "total_bytes": 0}
	for texture: Texture2D in [Detail.DIRT_ALBEDO, Detail.DIRT_NORMAL, Detail.DIRT_ROUGHNESS, Detail.GRASS_ALBEDO, Detail.GRASS_NORMAL, Detail.GRASS_ROUGHNESS]:
		var image := texture.get_image()
		var bytes := image.get_data().size()
		result.maps.append({"path": texture.resource_path, "width": image.get_width(), "height": image.get_height(), "compressed": image.is_compressed(), "format": image.get_format(), "mip_count": image.get_mipmap_count(), "bytes": bytes})
		result.total_bytes += bytes
	result["engine"] = Engine.get_version_info().string
	result["anisotropic_level_setting"] = ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level")
	result["within_64_mib"] = int(result.total_bytes) <= 64 * 1024 * 1024
	result["manifest_exists"] = FileAccess.file_exists("res://assets/landscape/rc-ground/manifest.json")
	result["license_exists"] = FileAccess.file_exists("res://assets/landscape/rc-ground/LICENSES.txt")
	if result.manifest_exists:
		result["manifest_sha256"] = FileAccess.get_sha256("res://assets/landscape/rc-ground/manifest.json")
	if result.license_exists:
		result["license_sha256"] = FileAccess.get_sha256("res://assets/landscape/rc-ground/LICENSES.txt")
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]):
		quit(2)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result))
	quit(0 if result.within_64_mib and result.manifest_exists and result.license_exists else 1)
