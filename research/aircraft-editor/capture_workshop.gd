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
	var invalid := false
	var long_name := false
	var aircraft_id := ""
	var smoke_preset := -1
	var smoke_seconds := 0.0
	var paint_color := ""
	var marking := ""
	var library_build := ""
	var favorite := false
	var fixture_id := ""
	var fixture_revision := 0
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
		if argument == "--invalid": invalid = true
		if argument == "--long-name": long_name = true
		if argument == "--opaque": UiTheme.opaque_panels = true
		if argument == "--reduced-motion": UiTheme.reduced_motion = true
		if argument.begins_with("--aircraft="): aircraft_id = argument.trim_prefix("--aircraft=")
		if argument.begins_with("--smoke-preset="): smoke_preset = argument.trim_prefix("--smoke-preset=").to_int()
		if argument.begins_with("--smoke-seconds="): smoke_seconds = clampf(argument.trim_prefix("--smoke-seconds=").to_float(), 0.0, 16.0)
		if argument.begins_with("--paint-color="): paint_color = argument.trim_prefix("--paint-color=")
		if argument.begins_with("--marking="): marking = argument.trim_prefix("--marking=")
		if argument.begins_with("--library-build="): library_build = argument.trim_prefix("--library-build=")
		if argument == "--favorite": favorite = true
		if argument == "--1080p": pixels = Vector2i(1920, 1080)
	root.size = pixels
	if fullscreen: root.mode = Window.MODE_FULLSCREEN
	await process_frame
	var canvas_policy := UiScale.apply(root)
	UiTheme.compact_layout = bool(canvas_policy.compact)
	UiTheme.text_scale = text_scale
	TranslationServer.set_locale(language)
	var workshop: CanvasLayer = load("res://ui/workshop.gd").new()
	if not aircraft_id.is_empty(): workshop.initial_aircraft_id = aircraft_id
	workshop.variants_root = "user://workshop_capture_empty_library"
	if not library_build.is_empty(): workshop.variants_root = "user://workshop_capture_fixture_%d" % Time.get_ticks_usec()
	root.add_child(workshop)
	workshop.set_recipe({scale = requested_scale})
	if not paint_color.is_empty():
		var appearance: Dictionary = workshop.get_presentation()
		var bindings: Dictionary = workshop.get("_presentation_bindings")
		appearance.paint = [{"slot": bindings.paint_slots[0].id, "color": paint_color, "pattern": "solid", "accent": "none"}]
		workshop.set_presentation(appearance)
	if not marking.is_empty():
		var appearance: Dictionary = workshop.get_presentation()
		var slots: Array = workshop.get("_presentation_bindings").get("marking_slots", [])
		if slots.is_empty():
			push_error("The selected aircraft has no registered inscription mount.")
			quit(1)
			return
		appearance.markings = [{"slot": slots[0].id, "text": marking, "color": "#20252BFF"}]
		workshop.set_presentation(appearance)
		workshop.get("_preview").set_standard_view("side")
	if smoke_preset > 0: workshop.get("_page_nodes").smoke.call("apply_preset", smoke_preset)
	if long_name: workshop.set_variant_name("Experimental aircraft with a deliberately long descriptive name")
	if invalid:
		var entry: LineEdit = workshop.get("_factor_inputs").weight_multiplier
		entry.text = "invalid"
		entry.text_changed.emit(entry.text)
	workshop.call("_set_page", page)
	if preview_only and workshop.get("_compact"): workshop.call("_toggle_compact_view")
	for frame in 12: await process_frame
	if smoke_seconds > 0.0:
		var smoke_preview: Node = workshop.get("_preview")
		smoke_preview.set_standard_view("side")
		smoke_preview.toggle_playback()
		smoke_preview.set_process(false)
		for frame in ceili(smoke_seconds * 60.0):
			smoke_preview.call("_process", 1.0 / 60.0)
			await process_frame
		smoke_preview.toggle_playback()
	if not library_build.is_empty():
		var imported: Dictionary = load("res://workshop/bundle.gd").import_file(library_build, workshop.variants_root)
		if not imported.ok:
			push_error(str(imported.errors))
			quit(1)
			return
		fixture_id = str(imported.variant.id)
		fixture_revision = int(imported.variant.revision)
		workshop.call("_refresh_variants")
		var selector: OptionButton = workshop.get("_variant_selector")
		for index in selector.item_count:
			if str(selector.get_item_metadata(index)) == fixture_id:
				selector.select(index)
				workshop.call("_on_variant_selected", index)
		if favorite: workshop.call("_toggle_favorite")
	if dialog == "library": workshop.call("_open_library")
	if dialog == "profile-copy":
		workshop.call("_open_library")
		workshop.call("_review_profile_transfer")
	if dialog == "save": workshop.call("_show_name_dialog", false)
	if dialog == "bundle-import":
		workshop.call("_open_library")
		workshop.call("_choose_bundle_import")
	if dialog == "guard":
		workshop.set_recipe({weight_multiplier = 0.731})
		workshop.request_navigation("Back to Home", func() -> void: pass)
	for frame in 6: await process_frame
	if not fixture_id.is_empty() and dialog == "library":
		var scroll: ScrollContainer = workshop.get("_library_dialog").find_child("LibraryScroll", true, false)
		scroll.ensure_control_visible(workshop.get("_favorite_button"))
	if not fixture_id.is_empty() and dialog == "profile-copy":
		for scroll: ScrollContainer in workshop.get("_transfer_dialog").find_children("*", "ScrollContainer", true, false):
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	for frame in 2: await process_frame
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
	evidence.preview.geometry = _projected_geometry(preview)
	for key: String in ["_library_dialog", "_name_dialog", "_guard_dialog", "_bundle_dialog", "_transfer_dialog"]:
		var popup: Window = workshop.get(key)
		if is_instance_valid(popup) and popup.visible:
			evidence.popup = {size = str(popup.size), position = str(popup.position), minimum = str(popup.get_contents_minimum_size())}
			evidence.popup.buttons = []
			for button: Node in popup.find_children("*", "Button", true, false):
				evidence.popup.buttons.append({text = button.text, size = str(button.size), min = str(button.custom_minimum_size), combined = str(button.get_combined_minimum_size())})
			if not Rect2(Vector2.ZERO, logical).encloses(Rect2(Vector2(popup.position), Vector2(popup.size))):
				evidence.overflow.append(popup.name)
	var metrics := FileAccess.open(output.get_basename() + ".json", FileAccess.WRITE)
	if metrics != null: metrics.store_string(JSON.stringify(evidence, "\t"))
	else: error = ERR_CANT_CREATE
	print("Workshop capture: ", output, " error=", error, " overflow=", evidence.overflow)
	if not fixture_id.is_empty():
		load("res://workshop/library_preferences.gd").set_favorite(fixture_id, false, workshop.variants_root)
		load("res://workshop/store.gd").delete_variant(fixture_id, workshop.variants_root, fixture_revision)
	workshop.free()
	await process_frame
	quit(error if error != OK else (1 if not evidence.overflow.is_empty() else 0))


func _projected_geometry(preview: Control) -> Dictionary:
	var camera: Camera3D = preview.get("_camera")
	var model: Node3D = preview.get("_airplane_root")
	if not is_instance_valid(camera) or not is_instance_valid(model): return {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var count := 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not part.is_visible_in_tree() or part.mesh == null: continue
		for index in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(index)
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not vertices is PackedVector3Array: continue
			for vertex: Vector3 in vertices:
				var point := part.global_transform * vertex
				if camera.is_position_behind(point): continue
				var projected := camera.unproject_position(point)
				minimum = minimum.min(projected)
				maximum = maximum.max(projected)
				count += 1
	if count == 0: return {}
	var canvas := camera.get_viewport().get_visible_rect().size
	return {viewport = [canvas.x, canvas.y], vertex_count = count,
		rect = [minimum.x, minimum.y, maximum.x - minimum.x, maximum.y - minimum.y],
		width_fraction = (maximum.x - minimum.x) / maxf(canvas.x, 1),
		height_fraction = (maximum.y - minimum.y) / maxf(canvas.y, 1)}
