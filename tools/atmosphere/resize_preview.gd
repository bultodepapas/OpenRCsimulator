extends SceneTree

const PREVIEW_WIDTH := 384
const PREVIEW_HEIGHT := 216


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths := _parse_paths(OS.get_cmdline_user_args())
	if not paths.get("ok", false):
		printerr(paths.get("error", "Expected --source=<absolute PNG> and --out=<absolute PNG>"))
		quit(1)
		return

	var source_path: String = paths.source
	var output_path: String = paths.out
	if not source_path.is_absolute_path() or not output_path.is_absolute_path():
		_fail("Source and output paths must be absolute")
		return
	if source_path.get_extension().to_lower() != "png" or output_path.get_extension().to_lower() != "png":
		_fail("Source and output paths must use the .png extension")
		return
	if source_path.simplify_path().to_lower() == output_path.simplify_path().to_lower():
		_fail("Source and output paths must be different")
		return
	if not FileAccess.file_exists(source_path):
		_fail("Source PNG does not exist: " + source_path)
		return
	if not DirAccess.dir_exists_absolute(output_path.get_base_dir()):
		_fail("Output directory does not exist: " + output_path.get_base_dir())
		return

	var image := Image.new()
	var error := image.load(source_path)
	if error != OK or image.is_empty():
		_fail("Could not load a valid source PNG: %s (error %d)" % [source_path, error])
		return
	image.resize(PREVIEW_WIDTH, PREVIEW_HEIGHT, Image.INTERPOLATE_LANCZOS)
	error = image.save_png(output_path)
	if error != OK:
		_fail("Could not save preview PNG: %s (error %d)" % [output_path, error])
		return

	var verify := Image.new()
	error = verify.load(output_path)
	if error != OK or verify.get_width() != PREVIEW_WIDTH or verify.get_height() != PREVIEW_HEIGHT:
		_fail("Saved preview failed the %d x %d PNG check" % [PREVIEW_WIDTH, PREVIEW_HEIGHT])
		return

	print("preview_source_sha256=" + FileAccess.get_sha256(source_path))
	print("preview_output_sha256=" + FileAccess.get_sha256(output_path))
	print("preview_dimensions=%dx%d" % [PREVIEW_WIDTH, PREVIEW_HEIGHT])
	quit(0)


func _parse_paths(arguments: PackedStringArray) -> Dictionary:
	var paths := {"source": "", "out": ""}
	for argument in arguments:
		if argument.begins_with("--source="):
			if not paths.source.is_empty():
				return {"ok": false, "error": "Duplicate --source argument"}
			paths.source = argument.trim_prefix("--source=")
		elif argument.begins_with("--out="):
			if not paths.out.is_empty():
				return {"ok": false, "error": "Duplicate --out argument"}
			paths.out = argument.trim_prefix("--out=")
		else:
			return {"ok": false, "error": "Unknown argument: " + argument}
	if paths.source.is_empty() or paths.out.is_empty():
		return {"ok": false, "error": "Expected --source=<absolute PNG> and --out=<absolute PNG>"}
	paths["ok"] = true
	return paths


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
