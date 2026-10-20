# L24: real Home selection, two flight worlds and default preservation.
extends SceneTree

const Landscapes = preload("res://landscapes/catalog.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const Preferences = preload("res://app_state/preferences.gd")
const Conditions = preload("res://render/world/conditions.gd")
const World = preload("res://render/world/world.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const UiDriver = preload("res://tests/ui_driver.gd")
var prefs_path := "user://test_landscapes-%d.cfg" % OS.get_process_id()
const GREEN := "green_paradise"
var failures := 0
var checks := 0
var ui: RefCounted
var captures := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-landscapes="):
			captures = arg.trim_prefix("--capture-landscapes=")
	ui = UiDriver.new(self)
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func _run() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(prefs_path)
	check("Club field remains first and default", Landscapes.DEFAULT_ID == "club_field" and Landscapes.ids() == ["club_field", GREEN])
	check("unknown IDs do not resolve", not Landscapes.has("missing") and Landscapes.entry("missing").is_empty())
	check("missing preferences retain Club field", Preferences.load_from(prefs_path).landscape == Landscapes.DEFAULT_ID)
	for invalid: Variant in ["missing", 7, true]:
		var cfg := ConfigFile.new()
		cfg.set_value("meta", "schema", 1)
		cfg.set_value("flight", "landscape", invalid)
		cfg.save(prefs_path)
		check("invalid preference falls back: " + str(invalid), Preferences.load_from(prefs_path).landscape == Landscapes.DEFAULT_ID)

	var loaded: Dictionary = FieldLoader.load_from(Landscapes.entry(GREEN).field_path)
	check("Green field validates", loaded.ok and loaded.field.id == GREEN)
	var first: Node3D = Landscapes.build(GREEN, loaded.field)
	var second: Node3D = Landscapes.build(GREEN, loaded.field)
	check("Green contains one flat grass plane", first.name == "Field" and first.get_child_count() == 1 and first.get_child(0) is MeshInstance3D and first.get_child(0).mesh is PlaneMesh and first.get_child(0).position.y == 0.0)
	check("Green has independent nodes and materials", first != second and first.get_child(0).material_override != second.get_child(0).material_override)
	check("Green has no lake or obstacle inventory", not first.has_meta("lake_context") and Landscapes.collision_world(GREEN, loaded.field).world.is_empty())
	var config: Dictionary = LightingConfig.defaults()
	config.mode = "astronomical"
	check("Green supports shared lighting updates", FieldBuilder.prepare_lighting(first, Lighting.snapshot(config)).ok and FieldBuilder.update_lighting(first, Lighting.snapshot(config)))
	first.free()
	second.free()
	var night_world := Node3D.new()
	var build_green := func() -> void: night_world.add_child(Landscapes.build(GREEN, loaded.field))
	World.build(night_world, loaded.field, build_green, Conditions.resolve(PackedStringArray(["--time_of_day=night"])))
	check("Green night has no club fixtures", night_world.get_node_or_null("FieldLights") == null and night_world.get_node_or_null("Campfire") == null and night_world.get_node_or_null("AirfieldLighting") == null)
	night_world.free()

	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	prefs.time_of_day = "day"
	prefs.weather_config = load("res://physics/wind_config.gd").defaults()
	Preferences.save_to(prefs_path, prefs)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs_path
	root.add_child(app)
	await ui.settle()
	check("fresh Home preserves Club runway launch", app.landscape_id == Landscapes.DEFAULT_ID and app.home.start_choice == "runway" and app.home_scene.field.id == "default")
	var old_home_world: WeakRef = weakref(app.home_scene)
	app.home.start_button.grab_focus()
	await ui.tap(KEY_RIGHT)
	check("landscape selector is reachable by keyboard", ui.focus_name() == "Landscape")
	await ui.tap(KEY_ENTER)
	check("keyboard switches Home to Green", app.landscape_id == GREEN and app.home_scene.field.id == GREEN and app.home.start_choice == "airborne")
	check("selection is saved", Preferences.load_from(prefs_path).landscape == GREEN)
	check("Green explains the unavailable Natural Random activity", app.home.natural_random_button.disabled and app.home.natural_random_button.tooltip_text == "Natural Random requires Club field.")
	app.open_natural_random()
	check("Green cannot enter a default-field scenario", app.screens.is_top("home"))
	await ui.settle()
	check("previous Home world is released", old_home_world.get_ref() == null)
	await _capture("green-home.png")
	await _fly_and_return(app, GREEN)

	app.home.landscape_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("keyboard switches back to Club", app.landscape_id == Landscapes.DEFAULT_ID and app.home_scene.field.id == "default")
	check("Club restores Natural Random availability", not app.home.natural_random_button.disabled)
	await _capture("club-home.png")
	await _fly_and_return(app, Landscapes.DEFAULT_ID)

	app.set_landscape(GREEN)
	app.set_aircraft("xcell-60-research")
	await ui.settle()
	check("Green helicopter offers hover without a pad", app.home.start_choice == "airborne" and app.home.start_button.disabled)
	await _fly_and_return(app, GREEN, true)
	check("Home retains Green after helicopter flight", app.home.landscape_id == GREEN)
	TranslationServer.set_locale("es")
	await ui.settle()
	check("landscape selector translates its label", app.home.landscape_button.text == "Paisaje: Green paradise")
	TranslationServer.set_locale("en")
	await ui.close_app(app)

	# Reopen the real shell from saved settings, without the previous in-memory world.
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs_path
	root.add_child(app)
	await ui.settle()
	check("relaunch restores Green field and selection", app.landscape_id == GREEN and app.home_scene.field.id == GREEN and app.home.landscape_id == GREEN)
	var before_id: String = app.landscape_id
	app.set_landscape("missing")
	check("unknown selection preserves Home", app.landscape_id == before_id and app.home_scene.field.id == GREEN)
	await ui.close_app(app)
	DirAccess.remove_absolute(prefs_path)
	Conditions.session_preset = ""
	print("%d landscape checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _fly_and_return(app: Node, id: String, helicopter := false) -> void:
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	var flight: Node = app.flight
	check(id + " flight loads", flight != null and flight.startup_error.is_empty() and flight.session.is_flyable())
	if flight == null:
		return
	check(id + " flight shares the selected field", flight.landscape_id == id and flight.field.id == ("default" if id == Landscapes.DEFAULT_ID else GREEN))
	var green: bool = id == GREEN
	var rendered: Node = flight.get_node("Field")
	check(id + " visual and physical worlds agree", (rendered.get_child_count() == 1 and flight.session._collision_world.is_empty()) if green else rendered.get_node_or_null("Scenery") != null and not flight.session._collision_world.is_empty())
	app.set_landscape(Landscapes.DEFAULT_ID if green else GREEN)
	check("active flight cannot change landscape", flight.landscape_id == id and app.landscape_id == id)
	flight.session.resume()
	for index in 4:
		await physics_frame
	check(id + " simulation advances", flight.session.sim.tick > 0)
	if green:
		check("Green has no club lights or campfire", flight.get_node_or_null("FieldLights") == null and flight.get_node_or_null("AirfieldLighting") == null and flight.get_node_or_null("Campfire") == null)
	if not captures.is_empty() and DisplayServer.get_name() != "headless":
		flight.set_overlays_visible(false)
		var report: Variant = flight.get("_accident_report") if not helicopter else null
		if is_instance_valid(report):
			report.visible = false
		var overview := Camera3D.new()
		flight.add_child(overview)
		overview.position = Vector3(0.0, 85.0, 120.0)
		overview.look_at(Vector3(0.0, 0.0, -90.0))
		overview.far = 20000.0
		overview.make_current()
		await _capture(("green-helicopter" if helicopter else id + "-flight") + ".png")
		overview.queue_free()
	app.open_pause()
	app.restart_flight()
	check(id + " restart retains landscape", app.flight.landscape_id == id and app.flight.session.is_flyable())
	app.open_pause()
	app.end_flight()
	await ui.settle()
	check(id + " returns to matching Home", app.flight == null and app.home.landscape_id == id and app.home_scene.field.id == ("default" if id == Landscapes.DEFAULT_ID else GREEN))


func _capture(filename: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame
	await RenderingServer.frame_post_draw
	check("save capture " + filename, root.get_texture().get_image().save_png(captures.path_join(filename)) == OK)
