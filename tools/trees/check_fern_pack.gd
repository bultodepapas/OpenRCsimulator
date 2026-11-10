## Source/PCK comparison for the optional woodland fern's imported texture and raw manifest.
## Run from an empty project with --main-pack to prevent source-file fallback.
extends SceneTree

const ATLAS := "res://assets/landscape/vegetation/impostors/polyhaven_fern_02_a_4view.png"
const MANIFEST := "res://assets/landscape/vegetation/impostors/polyhaven_fern_02_a_4view.json"


func _initialize() -> void:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() == 2 else "on"
	if not args.has("out") or DisplayServer.get_name() == "headless":
		_fail("native renderer and --out=<new JSON> are required")
		return
	if FileAccess.file_exists(str(args.out)):
		_fail("output already exists")
		return
	var builder: Script = load("res://scenery/woodland_edge_habitat.gd")
	if builder == null: return _fail("woodland builder is unavailable")
	var had_override := OS.has_environment("OPENRC_WOODLAND_CARDS")
	var previous := OS.get_environment("OPENRC_WOODLAND_CARDS")
	OS.unset_environment("OPENRC_WOODLAND_CARDS")
	var selected: bool = builder._use_source_ferns()
	OS.set_environment("OPENRC_WOODLAND_CARDS", "legacy")
	var legacy_selected: bool = builder._use_source_ferns()
	if had_override: OS.set_environment("OPENRC_WOODLAND_CARDS", previous)
	else: OS.unset_environment("OPENRC_WOODLAND_CARDS")
	if not selected or legacy_selected: return _fail("source selection or explicit legacy fallback failed")
	if args.has("require-packed") and FileAccess.file_exists(ATLAS):
		return _fail("packed check can still see the original PNG")
	var texture := load(ATLAS) as Texture2D
	if texture == null: return _fail("remapped fern texture is unavailable")
	var picture := texture.get_image()
	if picture == null or picture.get_size() != Vector2i(1024, 256) or picture.has_mipmaps() \
			or picture.get_format() != Image.FORMAT_RGBA8:
		return _fail("fern texture is not the reviewed lossless 1024x256 RGBA8 atlas")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(picture.get_data())
	var image_hash := hash.finish().hex_encode()
	if args.has("expect-image-sha256") and image_hash != str(args["expect-image-sha256"]):
		return _fail("packed decoded pixels differ from the source run")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or manifest.get("source_id") != "polyhaven_fern_02" \
			or manifest.get("license") != "CC0-1.0":
		return _fail("fern manifest is missing or identifies another supplier")
	var report := {complete = true, godot = Engine.get_version_info().string,
		renderer = RenderingServer.get_current_rendering_method(), adapter = RenderingServer.get_video_adapter_name(),
		image_sha256 = image_hash, decoded_bytes = picture.get_data().size(),
		manifest_sha256 = FileAccess.get_sha256(MANIFEST), source_selected = selected,
		legacy_selected = legacy_selected, original_png_present = FileAccess.file_exists(ATLAS)}
	if args.has("require-shrubs"):
		var shrubs := _check_shrubs(builder, args)
		if shrubs.is_empty(): return
		report["shrubs"] = shrubs
	var file := FileAccess.open(str(args.out), FileAccess.WRITE)
	if file == null: return _fail("could not write output")
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("FERN PACK VERIFIED: ", image_hash)
	quit(0)


func _check_shrubs(builder: Script, args: Dictionary) -> Dictionary:
	var had_override := OS.has_environment("OPENRC_WOODLAND_SHRUBS")
	var previous := OS.get_environment("OPENRC_WOODLAND_SHRUBS")
	OS.unset_environment("OPENRC_WOODLAND_SHRUBS")
	var selected: bool = builder._use_source_shrubs()
	var material: ShaderMaterial = builder._material() if selected else null
	OS.set_environment("OPENRC_WOODLAND_SHRUBS", "legacy")
	var legacy_selected: bool = builder._use_source_shrubs()
	if had_override: OS.set_environment("OPENRC_WOODLAND_SHRUBS", previous)
	else: OS.unset_environment("OPENRC_WOODLAND_SHRUBS")
	if not selected or legacy_selected or material == null:
		_fail("packed shrub selection or legacy fallback failed")
		return {}
	var names: Array[String] = []
	for uniform: Dictionary in material.shader.get_shader_uniform_list(): names.append(str(uniform.name))
	if "shrub_atlas_a" not in names or "shrub_atlas_b" not in names:
		_fail("packed source-shrub shader lost its sampler declarations")
		return {}
	var textures := {}
	for index in 2:
		var asset_id: String = builder.SHRUB_CARD_IDS[index]
		var path := "res://assets/landscape/vegetation/impostors/%s_4view.png" % asset_id
		if args.has("require-packed") and FileAccess.file_exists(path):
			_fail("packed shrub check can still read an original PNG")
			return {}
		var texture := material.get_shader_parameter("shrub_atlas_a" if index == 0 else "shrub_atlas_b") as Texture2D
		var image := texture.get_image() if texture != null else null
		if image == null or image.get_size() != Vector2i(1024, 256) or image.has_mipmaps() \
				or image.get_format() != Image.FORMAT_RGBA8:
			_fail("packed shrub atlas is missing or has changed format")
			return {}
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(image.get_data())
		var digest := hash.finish().hex_encode()
		var expected := str(args.get("expect-shrub-images", "")).split(",")
		if args.has("expect-shrub-images") and (expected.size() != 2 or digest != expected[index]):
			_fail("packed shrub pixels differ from their source run")
			return {}
		textures[asset_id] = {image_sha256 = digest, decoded_bytes = image.get_data().size(),
			original_png_present = FileAccess.file_exists(path),
			manifest_sha256 = FileAccess.get_sha256(path.get_basename() + ".json")}
	return {source_selected = selected, legacy_selected = legacy_selected,
		shader_path = material.shader.resource_path, atlases = textures}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
