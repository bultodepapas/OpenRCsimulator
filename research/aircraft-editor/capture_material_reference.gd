## Matched production WorkshopPreview captures. No flight session or saved build is created.
extends SceneTree

var _out := ""
var _script_path := "res://ui/workshop_preview.gd"
var _reference := ""
var _aircraft := "jensen-das-ugly-stik-60"
var _records: Array = []
var _preview: Control
var _failures: Array[String] = []
var _reference_manifest: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--preview-script="): _script_path = arg.trim_prefix("--preview-script=")
		elif arg.begins_with("--aircraft="): _aircraft = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--reference="): _reference = arg.trim_prefix("--reference=")
		else:
			push_error("Unknown option: " + arg)
			quit(1)
			return
	_run.call_deferred()

func _run() -> void:
	if _out.is_empty() or DirAccess.dir_exists_absolute(_out) or DisplayServer.get_name() == "headless":
		push_error("A rendered session and a new --out directory are required")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("Cannot create " + _out)
		quit(1)
		return
	if not _reference.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_reference.path_join("manifest.json")))
		if not parsed is Dictionary or parsed.get("aircraft", "") != _aircraft \
				or parsed.get("renderer", "") != RenderingServer.get_current_rendering_method() \
				or parsed.get("engine", "") != Engine.get_version_info().string:
			push_error("Reference identity differs from the requested fixture")
			quit(1)
			return
		_reference_manifest = parsed
	load("res://render/shader_clock.gd").register()
	root.size = Vector2i(1920, 1080)
	await process_frame
	_preview = load(_script_path).new()
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_preview)
	_preview.set_aircraft(_aircraft)
	await RenderingServer.frame_post_draw
	await _capture("cold-day")
	for frame in 6: await process_frame
	_preview._request_redraw()
	await RenderingServer.frame_post_draw
	await _capture("settled-day")
	_preview.set_standard_view("side")
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	await _capture("side-day")
	_preview.set_preview_night(true)
	await RenderingServer.frame_post_draw
	await _capture("first-night")
	for frame in 6: await process_frame
	_preview._request_redraw()
	await RenderingServer.frame_post_draw
	await _capture("settled-night")
	_preview.set_preview_night(false)
	await RenderingServer.frame_post_draw
	await _capture("first-return-day")
	for frame in 6: await process_frame
	_preview._request_redraw()
	await RenderingServer.frame_post_draw
	await _capture("settled-return-day")
	_preview.orbit_by(60, 10)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	await _capture("orbit-day")
	for pair: Array in [[0, 1], [3, 4], [5, 6], [2, 6]]:
		if _records[pair[0]].raw_sha256 != _records[pair[1]].raw_sha256:
			_failures.append("Unsettled view: " + str(_records[pair[0]].label))
	var file := FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({engine = Engine.get_version_info().string,
		renderer = RenderingServer.get_current_rendering_method(), adapter = RenderingServer.get_video_adapter_name(),
		source = _script_path, source_sha256 = FileAccess.get_sha256(_script_path), aircraft = _aircraft,
		root_pixels = [root.size.x, root.size.y], captures = _records,
		reference = _reference, failures = _failures,
		limits = "Fixed-light Workshop reference, no flight or frame-time qualification"}, "\t"))
	file.close()
	_preview.queue_free()
	await process_frame
	await process_frame
	print("WORKSHOP_REFERENCE_CAPTURE: %d captures, %d failed" % [_records.size(), _failures.size()])
	for failure in _failures: printerr("FAIL ", failure)
	quit(1 if not _failures.is_empty() else 0)

func _capture(label: String) -> void:
	var viewport: SubViewport = _preview._viewport
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var path := _out.path_join(label + ".png")
	if image.save_png(path) != OK:
		push_error("Cannot save " + path)
		quit(1)
	var camera: Camera3D = _preview._camera
	var record := {label = label, file = label + ".png", sha256 = FileAccess.get_sha256(path), raw_sha256 = _hash(image.get_data()),
		pixels = [image.get_width(), image.get_height()], camera = str(camera.transform),
		view = _preview.get_view_state(), night = _preview._preview_night,
		update_mode = viewport.render_target_update_mode, processing = _preview.is_processing()}
	if record.processing or record.update_mode == SubViewport.UPDATE_ALWAYS:
		_failures.append("Still preview did not stop processing: " + label)
	if not _reference_manifest.is_empty():
		var matched := false
		for reference: Dictionary in _reference_manifest.captures:
			if reference.label != label: continue
			matched = true
			var reference_path := _reference.path_join(reference.file)
			if FileAccess.get_sha256(reference_path) != reference.sha256 or reference.camera != record.camera \
					or Vector2i(int(reference.pixels[0]), int(reference.pixels[1])) != image.get_size() \
					or reference.view != record.view:
				_failures.append("Reference camera/image identity differs: " + label)
			var reference_image := Image.load_from_file(reference_path)
			reference_image.convert(Image.FORMAT_RGBA8)
			record.reference_raw_sha256 = _hash(reference_image.get_data())
			record.reference_pixels_equal = record.raw_sha256 == record.reference_raw_sha256
			if record.night and not record.reference_pixels_equal:
				_failures.append("Night reference changed: " + label)
		if not matched: _failures.append("Reference view missing: " + label)
	_records.append(record)
	print("Captured ", path)


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
