# UI-23-R4: native screenshots through production routes; preferences are isolated.
extends SceneTree
const Preferences = preload("res://app_state/preferences.gd")
const Display = preload("res://app_state/display_preferences.gd")
const Driver = preload("res://tests/ui_driver.gd")
var app: Node
var driver: RefCounted
var output := ProjectSettings.globalize_path("res://../tmp/menu-resolution/captures")
var records: Array = []
var prefix := ""
var expected_pixels := Vector2i.ZERO
var controllers_only := "--controllers-only" in OS.get_cmdline_user_args()
var fullscreen_only := "--fullscreen-only" in OS.get_cmdline_user_args()
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for frame in 10: await process_frame
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	print("HOST display_count=",DisplayServer.get_screen_count()," current_display=",DisplayServer.screen_get_size(root.current_screen)," dpi=",DisplayServer.screen_get_dpi(root.current_screen))
	driver = Driver.new(self)
	var cases := [
		[1024,768,"en",1.0,false], [1920,1080,"en",1.0,false],
		[1280,800,"es",1.0,false], [2560,1080,"es",1.0,false], [3440,1440,"es",1.0,false],
		[960,540,"es",1.0,false], [3840,2160,"es",1.0,true],
		[960,540,"es",2.0,true], [3840,2160,"es",2.0,true]]
	if fullscreen_only:
		assert(DisplayServer.screen_get_size(root.current_screen) == Vector2i(3840,2160), "Fullscreen 4K requires a physical 4K display")
		cases = [[3840,2160,"en",1.0,false],[3840,2160,"es",1.0,false],[3840,2160,"es",2.0,false]]
	for entry in cases:
		if controllers_only and not entry[4]: continue
		var dimensions := Vector2i(entry[0],entry[1])
		expected_pixels = dimensions
		var language: String = entry[2]
		var enlarged: bool = entry[3] > 1.0
		var full: bool = entry[4]
		prefix = "%s-%dx%d-%d" % [language,dimensions.x,dimensions.y,entry[3]*100]
		if fullscreen_only: prefix += "-fullscreen"
		# Window renders and physical fullscreen captures are recorded separately.
		root.mode = Window.MODE_WINDOWED
		root.size = dimensions
		await settle()
		var prefs := Preferences.DEFAULTS.duplicate(true)
		prefs.language = language
		prefs.first_flight_hint_seen = true
		prefs.latency_marker = false
		prefs.time_of_day = "day"
		prefs.aircraft = "sebart-avanti-s-a200-p100rx"
		var prefs_path := output.path_join("isolated.cfg")
		Preferences.save_to(prefs_path,prefs)
		var display := Display.DEFAULTS.duplicate(true)
		display.ui_scale = entry[3]
		display.window_mode = "borderless" if fullscreen_only else "windowed"
		Display.save_to(prefs_path + ".display",display)
		app = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray()
		app.preferences_path = prefs_path
		app.random_seed_source = func() -> int: return 20261016
		root.add_child(app)
		app.menu_audio.set_volume(0.0)
		await settle()
		root.size = dimensions
		if fullscreen_only: root.mode = Window.MODE_FULLSCREEN
		await settle()
		if controllers_only:
			app.open_controls(app.home.fly_button)
			await capture("controls")
			for section in ["profile","axes","aux","buttons"]:
				app.screens.top().select_section(section)
				await capture("controls-" + section)
			await driver.tap(KEY_ESCAPE)
			root.remove_child(app)
			app.queue_free()
			await settle()
			continue
		await capture("home")
		app.open_settings(app.home.fly_button)
		await capture("settings")
		if full:
			app.screens.top()._show_category(1)
			await capture("settings-interface")
			app.screens.top()._show_category(2)
			await capture("settings-sound")
		await driver.tap(KEY_ESCAPE)
		if full:
			for route in ["help","controls","weather","workshop","failures","natural_random"]:
				app.call("open_failures_settings" if route == "failures" else "open_" + route,app.home.fly_button)
				await capture(route)
				if route == "weather":
					app.screens.top().tab_bar.current_tab = 2
					await capture("weather-atmosphere")
				if route == "controls":
					for section in ["profile","axes","aux","buttons"]:
						app.screens.top().select_section(section)
						await capture("controls-" + section)
				await driver.tap(KEY_ESCAPE)
		app.start_flight()
		await settle()
		app.open_pause()
		await capture("pause")
		if full:
			app.open_time_of_day()
			assert(app.screens.is_top("time_of_day"), "Lighting edits must open from Pause")
			await capture("time_of_day")
			app.screens.top().visual_tabs.current_tab = 1
			await capture("sky")
			await driver.tap(KEY_ESCAPE)
			app.open_overlays()
			await capture("overlays")
			await driver.tap(KEY_ESCAPE)
		var paused_tick: int = app.flight.session.sim.tick
		app.open_settings()
		await settle()
		await driver.tap(KEY_ESCAPE)
		print("FLOW ",prefix," pause-held=",paused_tick == app.flight.session.sim.tick," return=",app.screens.is_top("pause"))
		root.remove_child(app)
		app.queue_free()
		await settle()
	var geometry_file := "geometry-fullscreen.json" if fullscreen_only else ("geometry-controls.json" if controllers_only else "geometry.json")
	var file := FileAccess.open(output.path_join(geometry_file),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"  "))
	quit()
func capture(screen: String) -> void:
	await settle()
	var snapshot := root.get_texture().get_image()
	assert(snapshot.get_size() == root.size, "Native capture must match the actual window pixel size")
	assert(snapshot.get_size() == expected_pixels, "Capture must render the requested resolution")
	if fullscreen_only:
		assert(root.mode == Window.MODE_FULLSCREEN and DisplayServer.screen_get_size(root.current_screen) == snapshot.get_size())
	var filename := prefix + "-" + screen + ".webp"
	snapshot.save_webp(output.path_join(filename),true)
	var controls: Array = []
	walk(app.screens.top(),controls)
	records.append({"image":filename,"pixels":[snapshot.get_width(),snapshot.get_height()],"logical":str(root.get_visible_rect().size),"window_mode":root.mode,"display":str(DisplayServer.screen_get_size(root.current_screen)),"dpi":DisplayServer.screen_get_dpi(root.current_screen),"gpu":RenderingServer.get_video_adapter_name(),"controls":controls})
	print("CAPTURE ",filename," ",snapshot.get_size()," logical=",root.get_visible_rect().size)
func walk(node: Node, rows: Array) -> void:
	if node == null: return
	if node is Control and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		if node is Label or node is BaseButton or node is PanelContainer or node is ScrollContainer:
			var row := {"path":str(node.get_path()),"type":node.get_class(),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]}
			if node is Label or node is Button: row.text = node.tr(node.text)
			if node is ScrollContainer: row.scroll_visible = node.get_v_scroll_bar().visible
			rows.append(row)
	for child in node.get_children(): walk(child,rows)
