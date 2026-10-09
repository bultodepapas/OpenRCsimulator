# UI-01a: the entry route, the Home screen and its Theme, with real key events (tests/ui_driver.gd).
# Run: godot --headless --path . --script res://tests/test_ui_home.gd
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const Home := preload("res://ui/home.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_home_settings.cfg"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _run() -> void:
	# Route: any user argument keeps the direct flight (traces, captures, --quick-flight); none shows Home.
	_check("route: no user arguments -> Home", not AppRoot.wants_direct_flight(PackedStringArray()))
	_check("route: --trace -> direct flight", AppRoot.wants_direct_flight(PackedStringArray(["--trace=/tmp/t.csv", "--t=3"])))
	_check("route: --quick-flight -> direct flight", AppRoot.wants_direct_flight(PackedStringArray(["--quick-flight"])))

	TranslationServer.set_locale("en")
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS # never the player's own settings
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	root.add_child(app)
	await ui.settle() # Theme lookups and deferred focus need a frame inside the tree
	var home: Control = app.home
	_check("Home shown, no flight scene, no simulation", home != null and app.flight == null and _sessions(root) == 0)
	var scene: Node3D = app.home_scene
	_check("Home backdrop: our airplane, its camera current", scene != null and scene.airplane.root.is_inside_tree()
		and root.get_viewport().get_camera_3d() == scene.camera)

	# Theme, read back from real controls (MENU-PLAN §7: 4.5:1 text, 3:1 focus). Translucent surfaces are judged
	# over the worst sky or ground behind them (white and black).
	var fly: Button = home.fly_button
	var quit_b: Button = home.quit_button
	var panel_bg: Color = (home.get_node("Sidebar") as Control).get_theme_stylebox("panel").bg_color
	for b in [fly, quit_b]:
		for state in ["normal", "hover", "pressed"]:
			var bg: Color = b.get_theme_stylebox(state).bg_color
			var fg: Color = b.get_theme_color("font_color" if state == "normal" else "font_%s_color" % state)
			var r := UiTheme.contrast(fg, bg)
			_check("contrast: %s %s text %.2f:1 >= 4.5" % [b.name, state, r], r >= 4.5)
	var focus := fly.get_theme_stylebox("focus") as StyleBoxFlat
	_check("Fly inherits Button's focus outline, without fill", focus == quit_b.get_theme_stylebox("focus") and not focus.draw_center)
	var r_focus := UiTheme.contrast(focus.border_color, panel_bg)
	_check("contrast: focus outline on panel %.2f:1 >= 3" % r_focus, r_focus >= 3.0)
	# Every label against the surface it sits on (sidebar, card or key cap), and the smallest text height.
	var worst := INF
	var worst_name := ""
	var smallest := INF
	for l in home.find_children("*", "Label", true, false):
		var bg := _surface(l, panel_bg)
		var r := UiTheme.contrast(l.get_theme_color("font_color"), bg)
		if r < worst:
			worst = r
			worst_name = l.text
		smallest = minf(smallest, l.get_theme_font("font").get_height(l.get_theme_font_size("font_size")))
	_check("contrast: every Home label >= 4.5:1 on its surface (worst %.2f, \"%s\")" % [worst, worst_name], worst >= 4.5)
	# AGI "Clear Text": >= 17 px from ascender to descender at 720p.
	_check("smallest text is %.1f px tall (>= 17 at 1280x720)" % smallest, smallest >= 17.0)

	# Keyboard: focus starts on Fly and is visible; arrows move it; nothing flies while navigating.
	_check("initial focus on Fly", ui.focus_name() == "Fly", ui.focus_name())
	_check("focus outline visible (keyboard focus)", fly.has_focus(true))
	await ui.tap(KEY_DOWN)
	_check("Down -> Language", ui.focus_name() == "Language", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("Right -> Help", ui.focus_name() == "Help", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("Right -> Quit", ui.focus_name() == "Quit", ui.focus_name())
	await ui.tap(KEY_UP)
	_check("Up -> Fly", ui.focus_name() == "Fly", ui.focus_name())
	_check("navigating did not start a flight", app.flight == null and _sessions(root) == 0)

	# Quit asks to close (the signal only: the test must not quit through it).
	var quits := [0]
	var lone: Control = Home.new()
	root.add_child(lone)
	lone.quit_requested.connect(func() -> void: quits[0] += 1)
	lone.quit_button.pressed.emit()
	_check("Quit requests closing the app", quits[0] == 1)
	lone.free()

	# Fly: two Enter presses in the same frame still create exactly one flight (research 20: double activation).
	for i in 2:
		for pressed in [true, false]:
			var e := InputEventKey.new()
			e.keycode = KEY_ENTER
			e.physical_keycode = KEY_ENTER
			e.pressed = pressed
			Input.parse_input_event(e)
	await ui.settle()
	await ui.settle()
	_check("Enter on Fly starts the flight", app.flight != null and app.home == null)
	_check("double Enter -> exactly one flight session", _sessions(root) == 1, "%d sessions" % _sessions(root))
	_check("Home and its backdrop freed after Fly", root.find_children("Home", "", true, false).is_empty()
		and root.find_children("HomeScene", "", true, false).is_empty())
	_check("the flight's camera is the one in use", root.get_viewport().get_camera_3d() == app.flight._camera)

	var saved: Dictionary = Preferences.load_from(PREFS)
	_check("Fly saves the selected default start choice", FileAccess.file_exists(PREFS) and saved.start_choice == "airborne")
	app.queue_free()
	await process_frame
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("all UI home checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


## The background colour behind a label: the nearest PanelContainer ancestor's panel style, else `fallback`.
static func _surface(n: Node, fallback: Color) -> Color:
	var p := n.get_parent()
	while p != null:
		if p is PanelContainer:
			var box := (p as Control).get_theme_stylebox("panel") as StyleBoxFlat
			if box != null and box.draw_center:
				return box.bg_color
		p = p.get_parent()
	return fallback


static func _sessions(n: Node) -> int:
	var count := 0
	for c in n.find_children("*", "Node", true, false):
		if c.get_script() == preload("res://sim/flight_session.gd"):
			count += 1
	return count
