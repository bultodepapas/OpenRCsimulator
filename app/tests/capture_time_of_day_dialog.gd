# Render a real interactive pause editor for TOD-08b layout evidence.
# Run under Xvfb with --out=<png> --lang=en|es --size=WIDTHxHEIGHT.
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")

const PREFS_PATH: String = "user://tod08b_ui_capture_settings.cfg"


func _initialize() -> void:
	await _run()


func _run() -> void:
	var output_path: String = "user://time-of-day.png"
	var language: String = "en"
	var requested_size: Vector2i = Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--lang="):
			language = argument.trim_prefix("--lang=")
		elif argument.begins_with("--size="):
			var dimensions: PackedStringArray = argument.trim_prefix("--size=").split("x")
			if dimensions.size() != 2 or not dimensions[0].is_valid_int() or not dimensions[1].is_valid_int():
				push_error("Capture size must be WIDTHxHEIGHT")
				quit(ERR_INVALID_PARAMETER)
				return
			requested_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	if language not in ["en", "es"] or requested_size.x < 640 or requested_size.y < 480:
		push_error("Capture requires en/es and a viewport of at least 640x480")
		quit(ERR_INVALID_PARAMETER)
		return
	DisplayServer.window_set_size(requested_size)
	await process_frame
	TranslationServer.set_locale(language)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences.language = language
	preferences.first_flight_hint_seen = true
	var saved: Error = Preferences.save_to(PREFS_PATH, preferences)
	if saved != OK:
		push_error("Could not write isolated UI capture preferences: %s" % error_string(saved))
		quit(saved)
		return
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS_PATH
	root.add_child(app)
	await process_frame
	await process_frame
	app.start_flight()
	var flight: Node = app.flight
	if flight == null or flight.startup_error != "":
		push_error("Could not start the interactive flight for the UI capture")
		quit(1)
		return
	await create_timer(0.5).timeout
	app.open_pause()
	await process_frame
	app.open_time_of_day(app.pause_menu.time_of_day_button)
	await process_frame
	var dialog: CanvasLayer = app.time_of_day_dialog
	if dialog == null:
		push_error("Pause menu did not open the time-of-day editor")
		quit(1)
		return
	var controls: VBoxContainer = dialog.get("controls") as VBoxContainer
	var mode_picker: OptionButton = controls.find_child("LightingMode", true, false) as OptionButton
	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	var advanced_toggle: CheckButton = controls.find_child("AdvancedLocation", true, false) as CheckButton
	advanced_toggle.button_pressed = true
	TranslationServer.set_locale(language)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var viewport: Viewport = root.get_viewport()
	var panel: Control = dialog.find_child("TimeOfDayPanel", true, false) as Control
	var panel_rect: Rect2 = panel.get_global_rect()
	var actual_size: Vector2 = viewport.get_visible_rect().size
	var fits_viewport: bool = panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0 \
		and panel_rect.end.x <= actual_size.x and panel_rect.end.y <= actual_size.y
	var image: Image = viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	var image_error: Error = image.save_png(output_path)
	if image_error != OK or not fits_viewport:
		push_error("Time-of-day dialog capture failed: image=%d panel=%s viewport=%s" % [image_error, panel_rect, actual_size])
		quit(1)
		return
	var evidence: Dictionary = {
		"format": "openrc-tod08b-ui-capture v1",
		"image": output_path.get_file(),
		"language": language,
		"requested_size": [requested_size.x, requested_size.y],
		"image_size": [image.get_width(), image.get_height()],
		"panel_rect": [panel_rect.position.x, panel_rect.position.y, panel_rect.size.x, panel_rect.size.y],
		"fits_viewport": fits_viewport,
		"mode": "astronomical",
		"advanced_location_visible": advanced_toggle.button_pressed,
		"apply_text": (dialog.get("apply_button") as Button).text,
		"cancel_text": (dialog.get("cancel_button") as Button).text,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"performance_claim": false,
	}
	var manifest_path: String = output_path.get_basename() + ".json"
	var manifest: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest == null:
		push_error("Could not save UI capture evidence")
		quit(1)
		return
	manifest.store_string(JSON.stringify(evidence, "  ", true) + "\n")
	manifest.close()
	print("saved %s (%dx%d, %s, fits=%s)" % [output_path, image.get_width(), image.get_height(), language, str(fits_viewport)])
	for child: Node in root.get_children():
		child.queue_free()
	for frame_index: int in 3:
		await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	quit(0)
