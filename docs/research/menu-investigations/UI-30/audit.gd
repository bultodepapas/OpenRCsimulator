# UI-30: menu audit captures. One case per process, fullscreen at the Xvfb screen size, isolated preferences.
# Args after --: --size=WxH --lang=en|es --text=1.0 --set=core|full|homerest|flightfull|switching|firstrun
#   --scale3d=0.5 (backdrop only; use 1.0 on a GPU host) --out=<abs dir>
extends SceneTree
const Preferences = preload("res://app_state/preferences.gd")
const Display = preload("res://app_state/display_preferences.gd")
const Driver = preload("res://tests/ui_driver.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
var app: Node
var driver: RefCounted
var output := ""
var records: Array = []
var timings: Array = []
var prefix := ""
var expected := Vector2i(1920, 1080)
var lang := "en"
var text_scale := 1.0
var set_name := "full"
var full := false # extended screen list: full, homerest, flightfull, switching


func _initialize() -> void:
	run.call_deferred()


func arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.split("=", true, 1)[1]
	return fallback


func settle(frames := 4) -> void:
	for frame in frames: await process_frame
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw


func setup() -> void:
	var prefs := Preferences.DEFAULTS.duplicate(true)
	prefs.language = lang
	prefs.first_flight_hint_seen = set_name != "firstrun"
	prefs.latency_marker = false
	prefs.time_of_day = "day"
	var prefs_path := output.path_join("isolated.cfg")
	Preferences.save_to(prefs_path, prefs)
	var display := Display.DEFAULTS.duplicate(true)
	display.ui_scale = text_scale
	display.window_mode = "borderless"
	Display.save_to(prefs_path + ".display", display)
	app = load("res://app_root.tscn").instantiate()
	app.preferences_path = prefs_path
	app.user_args = PackedStringArray()
	app.random_seed_source = func() -> int: return 20261020
	root.add_child(app)
	await settle()
	root.mode = Window.MODE_FULLSCREEN
	await settle()
	if root.size != expected:
		# Xvfb has no window manager: fall back to an undecorated window covering the whole screen.
		root.mode = Window.MODE_WINDOWED
		root.borderless = true
		root.position = Vector2i.ZERO
		root.size = expected
		await settle()


func run() -> void:
	var size := arg("size", "1920x1080").split("x")
	expected = Vector2i(int(size[0]), int(size[1]))
	lang = arg("lang", "en")
	text_scale = float(arg("text", "1.0"))
	set_name = arg("set", "full")
	full = set_name in ["full", "homerest", "flightfull", "switching"]
	output = arg("out", ProjectSettings.globalize_path("res://../tmp/ui30"))
	DirAccess.make_dir_recursive_absolute(output)
	prefix = "%s-%dx%d-%d" % [lang, expected.x, expected.y, int(text_scale * 100)]
	driver = Driver.new(self)
	print("HOST display=", DisplayServer.screen_get_size(root.current_screen), " dpi=", DisplayServer.screen_get_dpi(root.current_screen))
	# Software rendering budget (llvmpipe): the 3D backdrop renders at half scale by default; UI stays native.
	root.scaling_3d_scale = float(arg("scale3d", "0.5"))
	await setup()
	print("WINDOW size=", root.size, " mode=", root.mode, " visible_rect=", root.get_visible_rect().size, " content_scale=", root.content_scale_factor, " scaling_3d=", root.scaling_3d_scale)
	app.menu_audio.set_volume(0.0)
	if set_name == "firstrun":
		await first_run()
	elif set_name == "homerest":
		await home_routes(["weather", "workshop", "failures", "natural_random", "time_of_day"])
	elif set_name == "flightfull":
		await flight_screens()
	elif set_name == "switching":
		await aircraft_switching()
		await helicopter_flight()
		await garage_activity()
	else:
		await home_screens()
		await flight_screens()
		if full:
			await aircraft_switching()
			await helicopter_flight()
			await garage_activity()
	FileAccess.open(output.path_join(prefix + "-" + set_name + "-geometry.json"), FileAccess.WRITE).store_string(JSON.stringify(records, "  "))
	FileAccess.open(output.path_join(prefix + "-" + set_name + "-timings.json"), FileAccess.WRITE).store_string(JSON.stringify(timings, "  "))
	print("DONE ", prefix)
	quit()


func first_run() -> void:
	await capture("firstrun-home")
	await activate(app.home.fly_button)
	await settle(30)
	await capture("firstrun-after-fly")
	await create_timer(3.0).timeout
	await capture("firstrun-after-3s")


func home_screens() -> void:
	await capture("home")
	await activate(app.home._details_button)
	await capture("home-details")
	await activate(app.home._details_button)
	for page in [1, 2, 3]:
		await activate(app.home._page_buttons[page])
		await capture(["flight", "aircraft", "practice", "garage"][page])
	await activate(app.home._page_buttons[0])
	await activate(app.home.settings_button)
	await capture("settings-display")
	if full:
		for tab in [1, 2]:
			await activate(app.screens.top()._category_buttons[tab])
			await capture("settings-" + ["display", "interface", "sound"][tab])
	await driver.tap(KEY_ESCAPE)
	var routes := ["help", "controls", "weather", "workshop"]
	if full:
		routes += ["failures", "natural_random", "time_of_day"]
	await home_routes(routes)


func home_routes(routes: Array) -> void:
	for route in routes:
		var method: String = "open_failures_settings" if route == "failures" else "open_" + route
		if not app.has_method(method): continue
		app.call(method, app.home.fly_button)
		await settle()
		await capture(route)
		if route == "weather" and full:
			for tab in [1, 2, 3, 4]:
				app.screens.top().tab_bar.current_tab = tab
				await capture("weather-tab%d" % tab)
		await driver.tap(KEY_ESCAPE)
		await settle()
		if not app.screens.is_top("home"):
			print("NOTE Escape did not return to Home from ", route, " top=", app.screens.top().name)
			await driver.tap(KEY_ESCAPE)
			await settle()


func start_flight_from_home() -> void:
	var started := Time.get_ticks_msec()
	await activate(app.home.fly_button)
	await settle()
	timings.append({"event": "fly_to_flight_node_ms", "ms": Time.get_ticks_msec() - started})


func flight_screens() -> void:
	await start_flight_from_home()
	if app.flight == null:
		print("NOTE no flight after Fly")
		return
	if app.pause_menu != null:
		await capture("startup-pause")
		await activate(app.pause_menu.continue_button)
	await create_timer(2.0).timeout
	await capture("flight-hud")
	await driver.tap(KEY_ESCAPE)
	await capture("pause")
	print("PAUSE focus=", driver.focus_name())
	var paused_tick: int = app.flight.session.sim.tick
	await create_timer(1.0).timeout
	print("PAUSE ticks advanced while paused: ", app.flight.session.sim.tick - paused_tick)
	await activate(app.pause_menu.session_options_button)
	await capture("pause-session")
	if full:
		var index := 0
		for child in app.pause_menu.session_options_container.get_children():
			if child is Button and child.is_visible_in_tree() and not child.disabled:
				var name: String = child.name
				await activate(child)
				await capture("pause-session-" + name.to_lower())
				await driver.tap(KEY_ESCAPE)
				await settle()
				if not app.screens.is_top("pause"):
					print("NOTE after Escape from pause child ", name, " top=", app.screens.top().name)
					await driver.tap(KEY_ESCAPE)
					await settle()
				if app.pause_menu._open_group != "session" and app.pause_menu.session_options_button.is_visible_in_tree():
					await activate(app.pause_menu.session_options_button)
				index += 1
	await driver.tap(KEY_ESCAPE)
	await settle()
	print("PAUSE after Escape with group open: top=", app.screens.top().name if app.screens.top() else "none", " group=", app.pause_menu._open_group if app.pause_menu else "closed")
	if app.pause_menu == null:
		await driver.tap(KEY_ESCAPE)
	await activate(app.pause_menu.settings_button)
	await capture("pause-settings")
	await driver.tap(KEY_ESCAPE)
	if app.pause_menu.controls_button.is_visible_in_tree():
		await activate(app.pause_menu.controls_button)
		await capture("pause-controls")
		await driver.tap(KEY_ESCAPE)
	if app.pause_menu.help_button.is_visible_in_tree():
		await activate(app.pause_menu.help_button)
		await capture("pause-help")
		await driver.tap(KEY_ESCAPE)
	print("PAUSE tick unchanged over nested screens: ", paused_tick == app.flight.session.sim.tick)
	await activate(app.pause_menu.exit_options_button)
	await capture("pause-exit")
	if full:
		await driver.tap(KEY_ESCAPE)
		await activate(app.pause_menu.restart_button)
		await settle(20)
		await capture("after-restart")
		if app.pause_menu == null:
			await driver.tap(KEY_ESCAPE)
		await activate(app.pause_menu.exit_options_button)
	await activate(app.pause_menu.end_button)
	await settle(20)
	await capture("home-after-flight")
	print("HOME after flight focus=", driver.focus_name(), " page_visible=", app.home._pages.map(func(p): return p.visible))


func aircraft_switching() -> void:
	await activate(app.home._page_buttons[1])
	for index in app.home._catalog_ids.size():
		var id: String = app.home._catalog_ids[index]
		if id == app.home.aircraft_id: continue
		var started := Time.get_ticks_msec()
		await activate(app.home._catalog_buttons[index])
		var waited := 0
		while app.home.aircraft_preview_label.visible and waited < 600:
			await process_frame
			waited += 1
		timings.append({"event": "select_" + id, "ms_until_preview_ready": Time.get_ticks_msec() - started, "frames": waited, "preview_label_visible": app.home.aircraft_preview_label.visible})
		await capture("aircraft-" + id)
	await activate(app.home._page_buttons[0])
	await capture("home-last-aircraft")


func helicopter_flight() -> void:
	await activate(app.home._page_buttons[1])
	var index: int = app.home._catalog_ids.find("xcell-60-research")
	await activate(app.home._catalog_buttons[index])
	await settle(30)
	await activate(app.home._page_buttons[0])
	await capture("home-heli")
	await start_flight_from_home()
	if app.flight == null: return
	if app.pause_menu != null:
		await capture("heli-startup-pause")
		await activate(app.pause_menu.continue_button)
	await create_timer(2.0).timeout
	await capture("heli-flight")
	await driver.tap(KEY_ESCAPE)
	await capture("heli-pause")
	await activate(app.pause_menu.session_options_button)
	await capture("heli-pause-session")
	await driver.tap(KEY_ESCAPE)
	await activate(app.pause_menu.exit_options_button)
	await activate(app.pause_menu.end_button)
	await settle(20)


func garage_activity() -> void:
	await activate(app.home._page_buttons[3])
	await activate(app.home.ground_vehicle_button)
	await settle(30)
	await create_timer(2.0).timeout
	await capture("garage-drive")
	await driver.tap(KEY_ESCAPE)
	await settle(10)
	await capture("garage-pause")
	print("GARAGE focus=", driver.focus_name())


func activate(button: BaseButton) -> void:
	if not button.is_visible_in_tree() or button.disabled:
		print("NOTE cannot activate ", button.name, " visible=", button.is_visible_in_tree(), " disabled=", button.disabled)
		return
	button.grab_focus()
	await driver.tap(KEY_ENTER)
	await settle()


func capture(screen: String) -> void:
	await settle()
	var snapshot := root.get_texture().get_image()
	if snapshot.get_size() != expected:
		print("NOTE size mismatch ", snapshot.get_size(), " expected ", expected)
	var file := prefix + "-" + screen + ".png"
	snapshot.save_png(output.path_join(file))
	var controls: Array = []
	var top: Node = app.screens.top() if app.screens != null else null
	walk(top if top != null else app, controls)
	var viewport := root.get_visible_rect()
	var outside := controls.filter(func(r): return not r.in_scroll and (r.rect[0] < -1 or r.rect[1] < -1 or r.rect[0] + r.rect[2] > viewport.size.x + 1 or r.rect[1] + r.rect[3] > viewport.size.y + 1))
	records.append({"image": file, "pixels": [expected.x, expected.y], "logical": [viewport.size.x, viewport.size.y], "top": top.name if top != null else "", "focus": driver.focus_name(), "controls": controls, "outside_viewport": outside.size()})
	print("CAPTURE ", file, " top=", top.name if top != null else "", " focus=", driver.focus_name(), " outside=", outside.size())


func walk(node: Node, rows: Array, in_scroll := false) -> void:
	if node == null: return
	if node is Control and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		if node is Label or node is BaseButton or node is PanelContainer or node is ScrollContainer:
			var row := {"path": str(node.get_path()), "type": node.get_class(), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "in_scroll": in_scroll}
			if node is Label or node is Button:
				row.text = node.tr(node.text)
				var font_size: int = node.get_theme_font_size("font_size")
				row.font = font_size
			if node is ScrollContainer: row.scroll_visible = node.get_v_scroll_bar().visible
			rows.append(row)
	for child in node.get_children(): walk(child, rows, in_scroll or node is ScrollContainer)
