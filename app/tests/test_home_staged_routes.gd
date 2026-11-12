extends SceneTree
## UI-28-R5b: the rendered Home rebuild routes, driven headless with flight_loading_enabled (the draw
## helper then waits for process frames). A landscape change and a return from an activity show the
## Home loading surface, finish with Home on top and focus restored, apply a request made during the
## build afterwards, and a close request during the build takes the quit route.

const App := preload("res://app_root.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://test_home_staged_routes.cfg"


class TestApp extends App:
	var quits := 0
	func quit_app() -> void:
		if home_build_pending:
			super()
			return
		quits += 1 # the normal quit route would end this test run


var checks := 0
var failures := 0
var ui: RefCounted


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run.call_deferred()


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func wait_built(app: Node) -> bool:
	for _i in 3000:
		if not app.home_build_pending:
			for _j in 4:
				await process_frame
			return true
		await process_frame
	return false


func home_scene_count(app: Node) -> int:
	return app.get_children().filter(func(child: Node) -> bool: return child.get_script() == App.HomeScene).size()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	check("isolated preferences saved", Preferences.save_to(PREFS, prefs) == OK)
	var app := TestApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.home_flight_prefetch_mode = "off"
	app.flight_loading_enabled = true
	app.window_focus_probe = func() -> bool: return true
	root.add_child(app)
	await ui.settle()
	check("Home starts on the club field", app.screens.is_top("home") and app.landscape_id == "club_field")

	# Landscape change, with a time-of-day request landing during the build.
	var previous: Node = app.home_scene
	var time_before: String = app.preferences.get("time_of_day", "day")
	var other_time := "day" if time_before != "day" else "evening"
	check("a landscape change is accepted at once", app.set_landscape("green_paradise")
		and app.landscape_id == "green_paradise" and app.home_build_pending and app.screens.is_top("loading"))
	var surface: CanvasLayer = app.screens.top()
	check("the landscape surface is the see-through Home surface", surface.title_label.text
		== TranslationServer.translate("Preparing home…") and not surface.cancel_button.visible
		and is_equal_approx(float(surface.backdrop.material.get_shader_parameter("opacity")), surface.SEE_THROUGH_OPACITY)
		and previous.is_inside_tree())
	check("nothing else starts while Home is built", not app.set_landscape("club_field"))
	app.set_time_of_day(other_time)
	var built := await wait_built(app)
	check("the staged landscape completes with Home on top", built and app.screens.is_top("home")
		and not app.screens.get_screen("loading") and app.home_scene != previous
		and app.home_scene.is_inside_tree() and app.home_scene.get("_source_landscape") == "green_paradise"
		and home_scene_count(app) == 1, "screens=%s count=%d" % [app.screens.top(), home_scene_count(app)])
	check("focus returns to Home after the surface closes", root.gui_get_focus_owner() != null
		and app.home.is_ancestor_of(root.gui_get_focus_owner()))
	check("a request made during the build is applied afterwards", app.preferences.get("time_of_day") == other_time
		and not app._home_rebuild_after_build and not app.home_build_pending)

	# Return from an activity: Home is rebuilt from nothing under the opaque surface.
	app.screens.clear()
	app.remove_child(app.home_scene)
	app.home_scene.free()
	app.home_scene = null
	var debriefs := [0]
	app._return_home(func() -> void:
		if app.home != null: debriefs[0] += 1)
	check("the return shows the opaque Home surface first", app.home_build_pending and app.screens.is_top("loading")
		and app.screens.top().backdrop.material.get_shader_parameter("opacity") in [null, 1.0])
	built = await wait_built(app)
	check("the return installs Home once and runs the debrief after it exists", built and app.screens.is_top("home")
		and app.home != null and debriefs[0] == 1 and home_scene_count(app) == 1
		and app.home_scene.get("_source_landscape") == "green_paradise")

	# A close request during a landscape build stops it and takes the normal quit route.
	check("a second landscape change starts", app.set_landscape("club_field") and app.home_build_pending)
	var kept: Node = app.home_scene
	app.quit_app()
	built = await wait_built(app)
	check("quit during the build keeps the previous world and quits normally", built and app.quits == 1
		and app.home_scene == kept and kept.is_inside_tree() and not app.screens.get_screen("loading")
		and not app._home_build_cancelled)

	await ui.close_app(app)
	for suffix: String in ["", ".display", ".controllers", ".legacy_rc"]:
		var path := ProjectSettings.globalize_path(PREFS + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Home staged routes: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
