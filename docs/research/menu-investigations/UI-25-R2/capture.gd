# Native UI-25-R2 evidence through production routes, with isolated preferences.
extends SceneTree
const Preferences = preload("res://app_state/preferences.gd")
const Driver = preload("res://tests/ui_driver.gd")
var app: Node
var driver: RefCounted
var output := ProjectSettings.globalize_path("res://../tmp/menu-direction/captures")
var records: Array = []
var prefix := ""
var quick := false
var core := false
var home_only := false
var only_height := 0
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for frame in 8: await process_frame
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--quick": quick = true
		if arg == "--core": core = true
		if arg == "--home-only": home_only = true
		if arg.begins_with("--height="): only_height = int(arg.trim_prefix("--height="))
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	driver = Driver.new(self)
	var sizes := [Vector2i(1920,1080)] if quick else [Vector2i(1920,1080),Vector2i(3840,2160),Vector2i(1280,720),Vector2i(2560,1440)]
	for dimensions in sizes:
		if only_height > 0 and dimensions.y != only_height: continue
		root.mode = Window.MODE_FULLSCREEN if dimensions.y == 2160 else Window.MODE_WINDOWED
		if dimensions.y != 2160: root.size = dimensions
		await settle()
		for language in (["en"] if quick else ["en", "es"]):
			prefix = "%s-%d" % [language, dimensions.y]
			var prefs := Preferences.DEFAULTS.duplicate(true)
			prefs.language = language
			prefs.first_flight_hint_seen = true
			prefs.latency_marker = false
			prefs.time_of_day = "day"
			prefs.aircraft = "sebart-avanti-s-a200-p100rx"
			var prefs_path := output.path_join("isolated.cfg")
			Preferences.save_to(prefs_path,prefs)
			var display := preload("res://app_state/display_preferences.gd").DEFAULTS.duplicate(true)
			display.window_mode = "borderless" if dimensions.y == 2160 else "windowed"
			preload("res://app_state/display_preferences.gd").save_to(prefs_path + ".display", display)
			app = load("res://app_root.tscn").instantiate()
			app.user_args = PackedStringArray()
			app.preferences_path = prefs_path
			app.random_seed_source = func() -> int: return 20261015
			root.add_child(app)
			await capture("home")
			if home_only:
				root.remove_child(app)
				app.queue_free()
				await settle()
				continue
			if not quick:
				app.home._page_buttons[1].pressed.emit()
				await capture("aircraft")
				app.home._page_buttons[2].pressed.emit()
				await capture("practice")
				app.home._page_buttons[3].pressed.emit()
				await capture("garage")
				app.home._page_buttons[0].pressed.emit()
			app.home.settings_button.pressed.emit()
			await capture("settings")
			await driver.tap(KEY_ESCAPE)
			if not quick:
				for route in (["weather"] if core else ["help", "controls", "weather", "workshop", "natural_random", "failures"]):
					var method: String = "open_failures_settings" if route == "failures" else "open_" + route
					app.call(method, app.home.fly_button)
					await capture(route)
					await driver.tap(KEY_ESCAPE)
			app.start_flight()
			await settle()
			app.open_pause()
			await capture("pause")
			var tick: int = app.flight.session.sim.tick
			app.pause_menu.settings_button.pressed.emit()
			await capture("pause-settings")
			await driver.tap(KEY_ESCAPE)
			print("FLOW ",prefix," pause-held=",tick == app.flight.session.sim.tick," return=",app.screens.is_top("pause"))
			root.remove_child(app)
			app.queue_free()
			await settle()
	var file := FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"  "))
	quit()
func capture(screen: String) -> void:
	await settle()
	var snapshot := root.get_texture().get_image()
	var filename := prefix + "-" + screen + ".webp"
	snapshot.save_webp(output.path_join(filename),true)
	var controls: Array = []
	walk(app.screens.top(), controls)
	records.append({"image":filename,"pixels":[snapshot.get_width(),snapshot.get_height()],"logical":str(root.get_visible_rect().size),"window_mode":root.mode,"gpu":RenderingServer.get_video_adapter_name(),"controls":controls})
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

