## DT-11a: exact procedural propeller grain, including mip levels, generated before runtime.
## godot --headless --path app --script <absolute-path>/bake_grain.gd -- [--check]
extends SceneTree

const Finish := preload("res://aircraft/ugly_stik_finish.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args != PackedStringArray(["--check"]):
		printerr("Expected no arguments or --check")
		quit(1)
		return
	var image := Finish.generate_grain_image()
	if args.has("--check"):
		var baked: Image = load(Finish.GRAIN_PATH) as Image if ResourceLoader.exists(Finish.GRAIN_PATH) else null
		if baked == null or baked.get_size() != image.get_size() or baked.get_format() != image.get_format() \
				or baked.has_mipmaps() != image.has_mipmaps() or baked.get_data() != image.get_data():
			printerr("Missing or stale propeller grain; run assets/aircraft/ugly-stik-60/bake_grain.gd")
			quit(1)
			return
		print("Propeller grain and all mip levels match the procedural recipe")
	else:
		var error := ResourceSaver.save(image, Finish.GRAIN_PATH, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			printerr("Cannot save propeller grain: ", error_string(error))
			quit(1)
			return
		print("Generated ", Finish.GRAIN_PATH, "; regenerate aircraft model manifests next")
	quit()
