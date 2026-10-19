extends SceneTree
## Native Workshop capture and geometry evidence. Never writes player variants.
const UiScale := preload("res://ui/ui_scale.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var pixels := Vector2i(1280, 720)
	var language := "en"
	var output := "user://workshop-review.png"
	var requested_scale := 2.0
	var text_scale := 1.0
	var page := "setup"
	var dialog := ""
	var preview_only := false
	var fullscreen := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--language="): language = argument.trim_prefix("--language=")
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
		if argument.begins_with("--scale="): requested_scale = argument.trim_prefix("--scale=").to_float()
		if argument.begins_with("--text-scale="): text_scale = argument.trim_prefix("--text-scale=").to_float()
		if argument.begins_with("--width="): pixels.x = argument.trim_prefix("--width=").to_int()
		if argument.begins_with("--height="): pixels.y = argument.trim_prefix("--height=").to_int()
		if argument.begins_with("--page="): page = argument.trim_prefix("--page=")
		if argument.begins_with("--dialog="): dialog = argument.trim_prefix("--dialog=")
		if argument == "--preview": preview_only = true
		if argument == "--fullscreen": fullscreen = true
		if argument == "--1080p": pixels = Vector2i(1920, 1080)
	root.size = pixels
	if fullscreen: root.mode = Window.MODE_FULLSCREEN
	await process_frame
	UiScale.apply(root)
	UiTheme.text_scale = text_scale
	TranslationServer.set_locale(language)
	var workshop: CanvasLayer = load("res://ui/workshop.gd").new()
	workshop.variants_root = "user://workshop_capture_empty_library"
	root.add_child(workshop)
	workshop.set_recipe({scale = requested_scale})
	workshop.call("_set_page", page)
	if preview_only and workshop.get("_compact"): workshop.call("_toggle_compact_view")
	for frame in 12: await process_frame
	if dialog == "library": workshop.call("_open_library")
	if dialog == "save": workshop.call("_show_name_dialog", false)
	if dialog == "guard":
		workshop.set_recipe({weight_multiplier = 0.731})
		workshop.request_navigation("Back to Home", func() -> void: pass)
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(output)
	var logical: Vector2 = root.get_visible_rect().size
	var evidence := {requested_pixels = [pixels.x, pixels.y], actual_pixels = [root.size.x, root.size.y],
		logical_canvas = [logical.x, logical.y], screen_pixels = str(DisplayServer.screen_get_size()),
		dpi = DisplayServer.screen_get_dpi(), window_mode = root.mode, language = language,
		text_scale = text_scale, scale = requested_scale, page = page, dialog = dialog,
		compact = workshop.get("_compact"), controls = {}, overflow = [], renderer = RenderingServer.get_video_adapter_name()}
	for control_name: String in ["WorkshopPanel", "CloseWorkshop", "OpenLibrary", "TestFly", "SaveVariant", "WorkshopColumns", "AircraftPreview", "WorkshopScroll"]:
		var control := workshop.find_child(control_name, true, false) as Control
		if control == null: continue
		var rect := control.get_global_rect()
		evidence.controls[control_name] = {visible = control.is_visible_in_tree(),
			rect = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
		if control_name in ["CloseWorkshop", "OpenLibrary", "TestFly", "SaveVariant"] and control.is_visible_in_tree():
			if not Rect2(Vector2.ZERO, logical).encloses(rect): evidence.overflow.append(control_name)
	var preview: Control = workshop.get("_preview")
	evidence.preview = preview.call("get_view_state")
	for key: String in ["_library_dialog", "_name_dialog", "_guard_dialog"]:
		var popup: Window = workshop.get(key)
		if is_instance_valid(popup) and popup.visible:
			evidence.popup = {size = str(popup.size), position = str(popup.position), minimum = str(popup.get_contents_minimum_size())}
	var metrics := FileAccess.open(output.get_basename() + ".json", FileAccess.WRITE)
	if metrics != null: metrics.store_string(JSON.stringify(evidence, "\t"))
	else: error = ERR_CANT_CREATE
	print("Workshop capture: ", output, " error=", error, " overflow=", evidence.overflow)
	workshop.free()
	await process_frame
	quit(error if error != OK else (1 if not evidence.overflow.is_empty() else 0))
