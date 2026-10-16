extends SceneTree
const Preferences = preload("res://app_state/preferences.gd")
const DisplayPreferences = preload("res://app_state/display_preferences.gd")
const Driver = preload("res://tests/ui_driver.gd")
var app: Node
var output := ProjectSettings.globalize_path("res://../tmp/menu-optimization/captures")
var prefix := ""
var expected := Vector2i.ZERO
var records: Array = []
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for frame in 8: await process_frame
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var driver := Driver.new(self)
	print("HOST display=",DisplayServer.screen_get_size(root.current_screen)," dpi=",DisplayServer.screen_get_dpi(root.current_screen))
	for entry in [[1280,720,"en",1.0],[960,540,"es",2.0],[3840,2160,"es",1.0]]:
		expected = Vector2i(entry[0],entry[1])
		prefix = "%s-%dx%d-%d" % [entry[2],entry[0],entry[1],entry[3]*100]
		var fullscreen := expected == Vector2i(3840,2160) and DisplayServer.screen_get_size(root.current_screen) == expected
		root.mode = Window.MODE_WINDOWED
		root.size = expected
		var prefs := Preferences.DEFAULTS.duplicate(true)
		prefs.language = entry[2]
		prefs.first_flight_hint_seen = true
		prefs.time_of_day = "day"
		prefs.latency_marker = false
		var prefs_path := output.path_join("isolated.cfg")
		Preferences.save_to(prefs_path,prefs)
		var display := DisplayPreferences.DEFAULTS.duplicate(true)
		display.ui_scale = entry[3]
		display.window_mode = "borderless" if fullscreen else "windowed"
		DisplayPreferences.save_to(prefs_path + ".display",display)
		app = load("res://app_root.tscn").instantiate()
		app.preferences_path = prefs_path
		app.user_args = PackedStringArray()
		root.add_child(app)
		await settle()
		root.size = expected
		if fullscreen: root.mode = Window.MODE_FULLSCREEN
		app.menu_audio.set_volume(0.0)
		await capture("home")
		app.open_settings(app.home.settings_button)
		await settle()
		var settings: Node = app.screens.top()
		settings._show_category(2)
		await settle()
		var home_theme_id: int = app.home.theme.get_instance_id()
		var settings_theme_id: int = settings._surface.theme.get_instance_id()
		for step in 11:
			settings._volume_slider.value = float(step)/10.0
			await process_frame
		assert(app.home.theme.get_instance_id() == home_theme_id)
		assert(settings._surface.theme.get_instance_id() == settings_theme_id)
		assert(is_equal_approx(app.menu_audio.get_volume(),1.0))
		await capture("sound")
		settings._revert()
		await driver.tap(KEY_ESCAPE)
		app.menu_audio.set_volume(0.0)
		app.open_weather(app.home.weather_button)
		await capture("weather")
		app.screens.top().tab_bar.current_tab = 3
		await capture("time")
		app.screens.top().tab_bar.current_tab = 4
		await capture("sky")
		await driver.tap(KEY_ESCAPE)
		print("FLOW ",prefix," volume themes stable, live gain updated, return=",app.screens.is_top("home"))
		app.queue_free()
		await settle()
	FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	quit()
func capture(screen: String) -> void:
	await settle()
	var snapshot := root.get_texture().get_image()
	assert(snapshot.get_size() == expected)
	var file := prefix + "-" + screen + ".webp"
	snapshot.save_webp(output.path_join(file),true)
	records.append({"image":file,"pixels":[snapshot.get_width(),snapshot.get_height()],"logical":str(root.get_visible_rect().size),"window_mode":root.mode})
	print("CAPTURE ",file," mode=",root.mode)
