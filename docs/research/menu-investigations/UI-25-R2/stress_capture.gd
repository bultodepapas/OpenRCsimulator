extends "capture.gd"
func run() -> void:
	output = ProjectSettings.globalize_path("res://../tmp/menu-direction/stress")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	driver = Driver.new(self)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160)]:
		root.mode = Window.MODE_FULLSCREEN if dimensions.y == 2160 else Window.MODE_WINDOWED
		if dimensions.y != 2160: root.size = dimensions
		await settle()
		prefix = "es-%d-200" % dimensions.y
		var prefs := Preferences.DEFAULTS.duplicate(true)
		prefs.language = "es"
		prefs.first_flight_hint_seen = true
		prefs.time_of_day = "day"
		var prefs_path := output.path_join("isolated.cfg")
		Preferences.save_to(prefs_path,prefs)
		var display := preload("res://app_state/display_preferences.gd").DEFAULTS.duplicate(true)
		display.window_mode = "borderless" if dimensions.y == 2160 else "windowed"
		display.ui_scale = 2.0
		display.opaque_panels = true
		display.reduced_motion = true
		preload("res://app_state/display_preferences.gd").save_to(prefs_path + ".display",display)
		app = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray()
		app.preferences_path = prefs_path
		root.add_child(app)
		await capture("home")
		app.home.settings_button.pressed.emit()
		await capture("settings")
		await driver.tap(KEY_ESCAPE)
		app.start_flight()
		await settle()
		app.open_pause()
		await capture("pause")
		root.remove_child(app)
		app.queue_free()
		await settle()
	var file := FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"  "))
	quit()
