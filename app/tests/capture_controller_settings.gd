extends SceneTree
## Captures the real ControllerSetup screen with explicit fixture observations.
## No fixture is sent to the host input backend and the app uses a private preferences path.
## Use --lang=en|es, --mode=fixture|empty, --size=WIDTHxHEIGHT, and optional --section=devices|profile|axes|aux|buttons and --scroll=top|bottom.
## Run with isolated APPDATA and LOCALAPPDATA; screenshots are written with Viewport.get_texture().get_image().save_png().

const CAPTURE_PROFILE_PATH := "user://capture_controller_profiles.cfg"
const CAPTURE_LEGACY_PATH := "user://capture_controller_legacy.cfg"
const FIXTURE_DEVICES: Array[Dictionary] = [
	{
		"id": 201,
		"name": "Fixture · Xbox 360 Controller",
		"raw_name": "Fixture · Xbox 360 Controller",
		"guid": "fixture-xbox-360",
		"vendor_id": 0x045e,
		"product_id": 0x028e,
		"known": true,
		"kind": "gamepad",
		"platform": "fixture",
		"backend": "capture-fixture",
	},
	{
		"id": 202,
		"name": "Fixture · DualSense Wireless Controller",
		"raw_name": "Fixture · DualSense Wireless Controller",
		"guid": "fixture-dualsense-wireless",
		"vendor_id": 0x054c,
		"product_id": 0x0ce6,
		"known": true,
		"kind": "gamepad",
		"platform": "fixture",
		"backend": "capture-fixture",
	},
	{
		"id": 203,
		"name": "Fixture · Spektrum NX8 Radio",
		"raw_name": "Fixture · Spektrum NX8 Radio",
		"guid": "fixture-spektrum-nx8",
		"vendor_id": 0x0000,
		"product_id": 0x0000,
		"known": false,
		"kind": "radio",
		"platform": "fixture",
		"backend": "capture-fixture",
	},
]

const FIXTURE_SECTIONS: Array[String] = ["devices", "profile", "axes", "aux", "buttons"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var language := "en"
	var mode := "fixture"
	var only_section := ""
	var scroll_position := "top"
	var output_directory := "user://controller-menu-captures"
	var requested_size := Vector2i(1280, 720)
	var parse_only := false
	for arg in args:
		if arg.begins_with("--lang="):
			language = arg.trim_prefix("--lang=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--section="):
			only_section = arg.trim_prefix("--section=")
		elif arg.begins_with("--scroll="):
			scroll_position = arg.trim_prefix("--scroll=")
		elif arg.begins_with("--out-dir="):
			output_directory = arg.trim_prefix("--out-dir=")
		elif arg.begins_with("--size="):
			var dimensions := arg.trim_prefix("--size=").split("x")
			if dimensions.size() != 2 or not dimensions[0].is_valid_int() or not dimensions[1].is_valid_int():
				push_error("Capture size must be WIDTHxHEIGHT.")
				quit(ERR_INVALID_PARAMETER)
				return
			requested_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif arg == "--parse-only":
			parse_only = true
	if language not in ["en", "es"]:
		push_error("Capture language must be en or es.")
		quit(ERR_INVALID_PARAMETER)
		return
	if mode not in ["fixture", "empty"]:
		push_error("Capture mode must be fixture or empty.")
		quit(ERR_INVALID_PARAMETER)
		return
	if not only_section.is_empty() and only_section not in FIXTURE_SECTIONS:
		push_error("Capture section must be devices, profile, axes, aux, or buttons.")
		quit(ERR_INVALID_PARAMETER)
		return
	if scroll_position not in ["top", "bottom"]:
		push_error("Capture scroll position must be top or bottom.")
		quit(ERR_INVALID_PARAMETER)
		return
	if scroll_position == "bottom" and only_section.is_empty():
		push_error("Bottom scroll captures require a single --section.")
		quit(ERR_INVALID_PARAMETER)
		return
	if parse_only:
		print("Controller settings capture harness parsed.")
		quit(0)
		return

	TranslationServer.set_locale(language)
	DisplayServer.window_set_size(requested_size)
	await process_frame
	var registry: Object = (load("res://input/controller_registry.gd") as Script).new()
	var store: Object = (load("res://input/controller_profile_store.gd") as Script).new(CAPTURE_PROFILE_PATH, CAPTURE_LEGACY_PATH)
	var observations: Array[Dictionary] = []
	if mode == "fixture":
		observations = FIXTURE_DEVICES.duplicate(true)
	registry.call("update_devices", observations)
	if mode == "fixture":
		registry.call("select_device", "flight", 203)
		registry.call("select_device", "ui", 201)
	var setup: Node = (load("res://ui/controller_setup.gd") as Script).new()
	setup.call("configure", registry, store, 203 if mode == "fixture" else -1, 201 if mode == "fixture" else -1)
	root.add_child(setup)
	await process_frame
	await process_frame
	var sections: Array[String] = []
	if mode == "fixture":
		sections.append_array(FIXTURE_SECTIONS)
	else:
		sections.append("devices")
	if not only_section.is_empty():
		sections.clear()
		sections.append(only_section)
	var viewport: Viewport = root.get_viewport()
	if viewport.get_visible_rect().size != Vector2(requested_size):
		push_error("Capture viewport is %s, expected %s." % [str(viewport.get_visible_rect().size), str(requested_size)])
		quit(1)
		return
	var captured: Array[Dictionary] = []
	var size_suffix := "" if requested_size == Vector2i(1280, 720) else "-%dx%d" % [requested_size.x, requested_size.y]
	var scroll_suffix := "-bottom" if scroll_position == "bottom" else ""
	for section in sections:
		var file_stem := "%s-%s%s%s" % [mode, "buttons-footer" if section == "buttons" else section, size_suffix, scroll_suffix]
		var result: Dictionary = await _capture_frame(setup, viewport, output_directory, language, file_stem, section, -1, scroll_position == "bottom")
		if result.is_empty():
			quit(1)
			return
		captured.append(result)

	if mode == "fixture" and only_section.is_empty():
		setup.call("_commit_aux_binding", "smoke", {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false}, false)
		setup.call("_commit_aux_binding", "flaps", {"type": "button", "button": 5, "mode": "toggle_edge"}, false)
		setup.call("_commit_aux_binding", "gear", {"type": "button", "button": 6, "mode": "level"}, false)
		captured.append(await _capture_frame(setup, viewport, output_directory, language, "fixture-aux-mapped", "aux"))

		if not await _select_flight_device(setup, 201):
			push_error("Fixture Xbox controller is missing from the flight device picker.")
			quit(1)
			return
		captured.append(await _capture_frame(setup, viewport, output_directory, language, "fixture-xbox-buttons", "buttons", 0))
		captured.append(await _capture_frame(setup, viewport, output_directory, language, "fixture-xbox-camera", "buttons", 2))
		captured.append(await _capture_frame(setup, viewport, output_directory, language, "fixture-xbox-aux-actions", "buttons", 3))

		var action_filter := setup.get("action_filter") as OptionButton
		if action_filter == null or action_filter.item_count <= 2:
			push_error("Could not select the Camera action filter for the active-capture state.")
			quit(1)
			return
		action_filter.select(2)
		setup.call("_on_action_filter_selected", 2)
		await process_frame
		var camera_remap := setup.find_child("Remap_camera_cycle", true, false) as Button
		if camera_remap == null:
			push_error("Could not find the Camera Cycle remap button for the active-capture state.")
			quit(1)
			return
		setup.call("_start_capture", "camera_cycle", camera_remap)
		captured.append(await _capture_frame(setup, viewport, output_directory, language, "fixture-xbox-capture-active", ""))
		setup.call("_capture_done")

		var invalid_profile: Dictionary = setup.call("current_profile")
		invalid_profile["kind"] = "invalid-fixture-kind"
		setup.set("_draft_profile", invalid_profile)
		registry.call("select_device", "flight", 201)
		setup.call("_save_profile")
		captured.append(await _capture_frame(setup, viewport, output_directory, language, "fixture-xbox-validation-error", "buttons", 0))

		if not await _select_flight_device(setup, 202):
			push_error("Fixture DualSense controller is missing from the flight device picker.")
			quit(1)
			return
		captured.append(await _capture_frame(setup, viewport, output_directory, language, "fixture-dualsense-buttons", "buttons", 0))
	for capture in captured:
		if capture.is_empty() or not capture.has("image"):
			push_error("A requested ControllerSetup screenshot did not complete.")
			quit(1)
			return
	var manifest := {
		"route": "standalone production ControllerSetup with a real ControllerRegistry and ControllerProfileStore",
		"language": language,
		"mode": mode,
		"only_section": only_section,
		"scroll_position": scroll_position,
		"fixture_note": "Fixture devices are synthetic registry observations for interface review only; no host input device is emulated.",
		"devices": observations,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"viewport": [requested_size.x, requested_size.y],
		"captures": captured,
	}
	var manifest_stem := mode + size_suffix
	if not only_section.is_empty():
		manifest_stem += "-" + only_section
	if scroll_position == "bottom":
		manifest_stem += "-bottom"
	var manifest_path := "%s/%s/%s-manifest.json" % [output_directory.trim_suffix("/"), language, manifest_stem]
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		push_error("Cannot write capture manifest: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	manifest_file.flush()
	var manifest_error := manifest_file.get_error()
	manifest_file.close()
	if manifest_error != OK:
		push_error("Capture manifest failed to flush: %s" % error_string(manifest_error))
		quit(1)
		return

	setup.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAPTURE_PROFILE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAPTURE_LEGACY_PATH))
	quit(0)


func _capture_frame(setup: Node, viewport: Viewport, output_directory: String, language: String,
		file_stem: String, section: String, filter_index := -1, scroll_to_bottom := false) -> Dictionary:
	if not section.is_empty():
		setup.call("select_section", section, false)
	if filter_index >= 0:
		var action_filter := setup.get("action_filter") as OptionButton
		if action_filter == null or filter_index >= action_filter.item_count:
			push_error("Action filter %d is unavailable in this ControllerSetup." % filter_index)
			return {}
		action_filter.select(filter_index)
		setup.call("_on_action_filter_selected", filter_index)
	await process_frame
	if scroll_to_bottom:
		var section_scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
		if section_scroll == null:
			push_error("ControllerSetup has no content scroll container for the bottom capture.")
			return {}
		section_scroll.scroll_vertical = int(section_scroll.get_v_scroll_bar().max_value)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image_path := "%s/%s/%s.png" % [output_directory.trim_suffix("/"), language, file_stem]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(image_path).get_base_dir())
	var image: Image = viewport.get_texture().get_image()
	var expected_size := Vector2i(viewport.get_visible_rect().size)
	if image.get_size() != expected_size:
		push_error("Viewport image is %dx%d, expected %dx%d." % [image.get_width(), image.get_height(), expected_size.x, expected_size.y])
		return {}
	var save_error := image.save_png(image_path)
	if save_error != OK:
		push_error("Could not save %s: %s" % [image_path, error_string(save_error)])
		return {}
	print("saved %s" % image_path)
	var captured_section := section
	if captured_section.is_empty():
		var section_pages: Variant = setup.get("_section_pages")
		if section_pages is Dictionary:
			for section_id in section_pages:
				var section_page := section_pages[section_id] as Control
				if section_page != null and section_page.visible:
					captured_section = str(section_id)
					break
	return {"image": image_path, "size": [image.get_width(), image.get_height()], "section": captured_section,
		"action_filter_index": filter_index}


func _select_flight_device(setup: Node, device_id: int) -> bool:
	var picker := setup.get("flight_device_picker") as OptionButton
	if picker == null:
		return false
	for index in picker.item_count:
		if picker.get_item_id(index) == device_id:
			picker.select(index)
			setup.call("_on_flight_device_selected", index)
			await process_frame
			return true
	return false


