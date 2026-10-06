# Offline alpha-edge repair and inspection of the actual Godot mip generator.
extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	var picture: Image = Image.load_from_file(args[0].path_join("atlas.png"))
	if picture == null or picture.get_size() != Vector2i(1024, 1024):
		quit(1)
		return
	picture.fix_alpha_edges()
	if picture.save_png(args[0].path_join("atlas.png")) != OK or picture.generate_mipmaps() != OK:
		quit(1)
		return
	for level: int in range(picture.get_mipmap_count() + 1):
		var size_px: int = 1024 >> level
		var offset: int = 0 if level == 0 else picture.get_mipmap_offset(level)
		var bytes: PackedByteArray = picture.get_data().slice(offset, offset + size_px * size_px * 4)
		var mip: Image = Image.create_from_data(size_px, size_px, false, Image.FORMAT_RGBA8, bytes)
		if mip.save_png(args[0].path_join("mip-%02d.png" % level)) != OK:
			quit(1)
			return
	quit(0)
