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
	var file := FileAccess.open(str(args.out), FileAccess.WRITE)
	if file == null: return _fail("could not write output")
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("FERN PACK VERIFIED: ", image_hash)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
