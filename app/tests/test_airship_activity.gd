# BL-10/BL-12: Home -> Vehicles catalog "RC blimp" (UI-39) -> FLY -> airship activity -> Home. Checks the
# exclusive activity slot, skin selection, paused safe start, resume/arming, accepted ticks and the return route.
extends SceneTree

const AppRoot = preload("res://app_root.gd")
const Catalog = preload("res://vehicles/airship/airship_catalog.gd")
const GroundCatalog = preload("res://vehicles/ground/vehicle_catalog.gd")
const UiDriver = preload("res://tests/ui_driver.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)
	else:
		print("ok   " + description)


func _run() -> void:
	var ui: RefCounted = UiDriver.new(self)
	var app := AppRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = "user://test_airship_activity_settings.cfg"
	app.update_check_url = "http://127.0.0.1:1/unavailable"
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.home != null, "Home prepares")
	if app.home == null:
		await ui.close_app(app)
		quit(1)
		return
	# UI-39: the RC blimp is one Vehicles catalog entry; its skins are its paints.
	app.home._page_buttons[1].pressed.emit()
	await process_frame
	var blimp: int = app.home._catalog_ids.find(Catalog.STOCK_ID)
	check(blimp >= 0 and app.home._catalog_ids.count(Catalog.STOCK_ID) == 1, "the Vehicles catalog lists the RC blimp once")
	app.home._catalog_buttons[blimp].pressed.emit()
	await process_frame
	var paints: Array = app.home.livery_choices().map(func(choice: Dictionary) -> String: return choice.id)
	check(app.home.activity_id == Catalog.STOCK_ID and paints == Catalog.SKIN_IDS and app.home.livery_button.is_visible_in_tree(),
		"selecting the blimp offers every skin as a paint (%s)" % [paints])
	app.set_livery("historico")
	check(app.home.airship_skin_id == "historico" and app.home.livery_id == "historico" and app.preferences.airship_skin == "historico"
		and app.preferences.get("liveries", {}).is_empty(), "a blimp paint is its skin and never an aircraft livery")
	check(app.home_scene.requested_aircraft == Catalog.STOCK_ID and app.home_scene.requested_livery == "historico", "the backdrop shows the chosen skin")
	var car_requests := [0]
	app.home.ground_vehicle_requested.connect(func() -> void: car_requests[0] += 1)
	app.home.fly_button.pressed.emit()
	for i in 4:
		await process_frame
	var activity: Node = app.ground_vehicle
	check(car_requests[0] == 0 and activity != null and activity.name == "AirshipActivity" and app.home == null and app.flight == null,
		"Fly RC blimp routes to the airship activity only")
	if activity == null:
		await ui.close_app(app)
		quit(1)
		return
	check(str(activity.startup_error).is_empty(), "airship activity starts: " + str(activity.startup_error))
	check(activity.skin_id == "historico" and activity.visual != null, "selected skin is loaded")
	check(activity.session.paused and activity.hud.menu_visible, "the blimp starts paused with its menu open")
	activity.scripted_sticks = func(_tick: int) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0, 0.4])
	activity.handle_action("resume")
	var started: int = activity.session.sim.tick
	for i in 30:
		await physics_frame
	check(activity.session.sim.tick > started and not activity.session.paused, "resumed flight advances accepted ticks")
	check(activity.session.crash.is_empty() and activity.session.fault_reason.is_empty(), "no fault or crash in a short powered run")
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var paused_tick: int = activity.session.sim.tick
	for i in 10:
		await physics_frame
	check(activity.session.paused and activity.hud.menu_visible and activity.session.sim.tick == paused_tick,
		"losing window focus pauses the blimp behind its menu")
	activity.handle_action("resume")
	for i in 10:
		await physics_frame
	check(not activity.session.paused and activity.session.sim.tick > paused_tick, "explicit resume continues the flight")
	activity.handle_action("home")
	for i in 8:
		await process_frame
	check(app.ground_vehicle == null and app.home != null, "Home returns after the blimp activity")
	if app.home != null:
		check(app.home.activity_id == Catalog.STOCK_ID and app.home.airship_skin_id == "historico" and app.home.livery_id == "historico",
			"Home remembers the blimp and its skin (%s %s %s)" % [app.home.activity_id, app.home.airship_skin_id, app.home.livery_id])
	await ui.close_app(app)
	print("Airship activity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
