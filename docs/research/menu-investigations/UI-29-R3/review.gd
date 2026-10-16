# UI-29-R1: native final review, isolated preferences, real production screens.
extends SceneTree
const Preferences = preload("res://app_state/preferences.gd")
const Display = preload("res://app_state/display_preferences.gd")
const Driver = preload("res://tests/ui_driver.gd")
var app: Node
var driver: RefCounted
var output := ProjectSettings.globalize_path("res://../tmp/menu-final-review/final-captures")
var records: Array = []
var fluency: Array = []
var prefix := ""
var expected := Vector2i.ZERO
var interactive := "--interactive" in OS.get_cmdline_user_args()
class KeyProbe extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			print("NATIVE_KEY key=",event.keycode," physical=",event.physical_keycode," pressed=",event.pressed)
class FrameSampler extends Node:
	var samples: Array[float] = []
	var active := false
	var previous_usec := 0
	func _process(_delta: float) -> void:
		if not active: return
		var now := Time.get_ticks_usec()
		if previous_usec > 0: samples.append(float(now - previous_usec) / 1000.0)
		previous_usec = now
	func begin() -> void:
		samples.clear()
		previous_usec = 0
		active = true
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for frame in 8: await process_frame
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
func setup(entry: Array) -> void:
	expected = Vector2i(entry[0], entry[1])
	prefix = "%s-%dx%d-%d" % [entry[2],entry[0],entry[1],entry[3]*100]
	var fullscreen := expected == Vector2i(3840,2160)
	root.mode = Window.MODE_WINDOWED
	root.size = expected
	var prefs := Preferences.DEFAULTS.duplicate(true)
	prefs.language = entry[2]
	prefs.first_flight_hint_seen = true
	prefs.latency_marker = false
	prefs.time_of_day = "day"
	var prefs_path := output.path_join("isolated.cfg")
	Preferences.save_to(prefs_path,prefs)
	var display := Display.DEFAULTS.duplicate(true)
	display.ui_scale = entry[3]
	display.window_mode = "borderless" if fullscreen else "windowed"
	Display.save_to(prefs_path + ".display",display)
	app = load("res://app_root.tscn").instantiate()
	app.preferences_path = prefs_path
	app.user_args = PackedStringArray()
	app.random_seed_source = func() -> int: return 20261016
	root.add_child(app)
	await settle()
	root.size = expected
	if fullscreen: root.mode = Window.MODE_FULLSCREEN
	root.title = "OpenRC Simulator — Final menu review"
	await settle()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	driver = Driver.new(self)
	print("HOST display=",DisplayServer.screen_get_size(root.current_screen)," dpi=",DisplayServer.screen_get_dpi(root.current_screen))
	if interactive:
		await setup([1920,1080,"en",1.0])
		root.add_child(KeyProbe.new())
		return
	var cases := [[1280,720,"en",1.0],[1280,720,"es",1.0],[1920,1080,"en",1.0],[1920,1080,"es",1.0],[3840,2160,"en",1.0],[3840,2160,"es",1.0],[960,540,"es",2.0],[3440,1440,"es",1.0]]
	for entry in cases:
		await setup(entry)
		app.menu_audio.set_volume(0.0)
		if entry[2] == "en" and entry[0] in [1920,3840]:
			await measure_navigation()
		await capture("home")
		for page in [1,2,3]:
			await activate(app.home._page_buttons[page])
			await capture(["flight","aircraft","practice","garage"][page])
		await activate(app.home._page_buttons[0])
		await activate(app.home.settings_button)
		await capture("settings-display")
		for tab in [1,2]:
			await activate(app.screens.top()._category_buttons[tab])
			await capture("settings-" + ["display","interface","sound"][tab])
		await driver.tap(KEY_ESCAPE)
		assert(app.screens.is_top("home"))
		if entry[0] != 3440:
			for route in ["help","controls","weather","workshop","failures","natural_random"]:
				app.call("open_failures_settings" if route == "failures" else "open_" + route, app.home.fly_button)
				await capture(route)
				if route == "weather":
					for tab in [1,2,3,4]:
						app.screens.top().tab_bar.current_tab = tab
						await capture(["wind","turbulence","atmosphere","time","sky"][tab])
				await driver.tap(KEY_ESCAPE)
				assert(app.screens.is_top("home"), "Escape must return from " + route)
		await activate(app.home.fly_button)
		await settle()
		assert(app.flight != null)
		# A connected controller may already pause startup for its arming check.
		if app.pause_menu == null:
			await driver.tap(KEY_ESCAPE)
		assert(app.screens.is_top("pause"))
		await capture("pause")
		var paused_tick: int = app.flight.session.sim.tick
		await activate(app.pause_menu.session_options_button)
		await capture("pause-session")
		await driver.tap(KEY_ESCAPE)
		assert(app.screens.is_top("pause") and app.pause_menu._open_group == "")
		await activate(app.pause_menu.settings_button)
		await capture("pause-settings")
		await driver.tap(KEY_ESCAPE)
		assert(app.screens.is_top("pause"))
		assert(paused_tick == app.flight.session.sim.tick)
		await activate(app.pause_menu.exit_options_button)
		await capture("pause-exit")
		await activate(app.pause_menu.end_button)
		await settle()
		assert(app.screens.is_top("home") and app.flight == null)
		print("FLOW ",prefix," navigation, Escape, pause holds, settings return, End flight: PASS")
		app.queue_free()
		await settle()
	FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	FileAccess.open(output.path_join("fluency.json"),FileAccess.WRITE).store_string(JSON.stringify(fluency,"  "))
	quit()
func measure_navigation() -> void:
	# Warm presentation resources before measuring; no capture/encoding occurs in this interval.
	app.open_settings(app.home.settings_button)
	await settle()
	await driver.tap(KEY_ESCAPE)
	await settle()
	var sampler := FrameSampler.new()
	root.add_child(sampler)
	var open_costs: Array = []
	sampler.begin()
	for cycle in 6:
		var started := Time.get_ticks_usec()
		app.open_settings(app.home.settings_button)
		open_costs.append(float(Time.get_ticks_usec()-started)/1000.0)
		for frame in 20: await process_frame
		await activate(app.screens.top()._category_buttons[1])
		await activate(app.screens.top()._category_buttons[2])
		await driver.tap(KEY_ESCAPE)
		for frame in 20: await process_frame
	sampler.active = false
	var values := sampler.samples.duplicate()
	values.sort()
	fluency.append({"case":prefix,"scope":"native process-frame cadence across six warm Settings open/tab/close cycles; no screenshot encoding", "frame_ms":sampler.samples,"median_ms":values[values.size()/2],"p95_ms":values[mini(values.size()-1,ceili(values.size()*0.95)-1)],"max_ms":values.back(),"settings_open_cpu_ms":open_costs})
	print("FLUENCY ",prefix," frames=",values.size()," median=",values[values.size()/2]," p95=",values[mini(values.size()-1,ceili(values.size()*0.95)-1)]," max=",values.back())
	sampler.queue_free()
func activate(button: BaseButton) -> void:
	assert(button.is_visible_in_tree() and not button.disabled)
	button.grab_focus()
	await driver.tap(KEY_ENTER)
	await settle()
func capture(screen: String) -> void:
	await settle()
	var snapshot := root.get_texture().get_image()
	assert(snapshot.get_size() == expected)
	var file := prefix + "-" + screen + ".webp"
	snapshot.save_webp(output.path_join(file),true)
	var controls: Array = []
	walk(app.screens.top(),controls)
	records.append({"image":file,"pixels":[expected.x,expected.y],"logical":str(root.get_visible_rect().size),"window_mode":root.mode,"controls":controls})
	print("CAPTURE ",file)
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
