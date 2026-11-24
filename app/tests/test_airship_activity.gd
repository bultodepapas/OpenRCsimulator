# BL-10/BL-12: Home -> Vehicles catalog "RC blimp" (UI-39) -> FLY -> airship activity -> Home. Checks the
# exclusive activity slot, safe launch, skin selection, accepted ticks and the return route.
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(app.preferences_path))
	app.window_focus_probe = func() -> bool: return true
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
	app.flight_loading_enabled = true
	app.home.fly_button.pressed.emit()
	check(app.screens.is_top("loading"), "Fly immediately covers Home with the loading screen")
	app.home.fly_button.pressed.emit()
	var loading_deadline := Time.get_ticks_msec() + 30000
	while app._loading_active and app._loading_phase != "Building landscape" and Time.get_ticks_msec() < loading_deadline:
		await process_frame
	check(app._loading_phase == "Building landscape", "the loading screen remains cancellable while the world is built")
	app.cancel_flight_loading()
	for i in 8:
		await process_frame
	check(app.screens.is_top("home") and app.home_scene.camera.is_current() and app.ground_vehicle == null and not app._loading_active,
		"cancelling a repeated Fly request restores the same Home")
	app.home.fly_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 100000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if app.ground_vehicle != null:
			break
	var activity: Node = app.ground_vehicle
	check(car_requests[0] == 0 and activity != null and activity.name == "AirshipActivity" and app.home == null and app.flight == null,
		"Fly RC blimp routes to the airship activity only")
	if activity == null:
		await ui.close_app(app)
		quit(1)
		return
	check(str(activity.startup_error).is_empty(), "airship activity starts: " + str(activity.startup_error))
	check(activity.skin_id == "historico" and activity.visual != null, "selected skin is loaded")
	check(not activity.session.paused and not activity.hud.menu_visible and app.screens.top() == null
		and activity.session.options.start == "ground", "a focused keyboard launch starts on the wheels with both menus closed")
	activity.scripted_sticks = func(_tick: int) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0, 0.4])
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
	var selector: OptionButton = activity.hud.choices.skin
	selector.select(2)
	selector.item_selected.emit(2)
	check(activity.skin_id == "cromo-carbono-azul" and app.preferences.airship_skin == activity.skin_id
		and paused_tick == activity.session.sim.tick, "changing paint in Pause updates the saved selection at the same tick")
	activity.hud.resume_button.pressed.emit()
	for i in 10:
		await physics_frame
	check(not activity.session.paused and activity.session.sim.tick > paused_tick, "explicit resume continues the flight")
	app.flight_loading_enabled = false
	activity.handle_action("home")
	for i in 8:
		await process_frame
	check(app.ground_vehicle == null and app.home != null, "Home returns after the blimp activity")
	if app.home != null:
		check(app.home.activity_id == Catalog.STOCK_ID and app.home.airship_skin_id == "cromo-carbono-azul" and app.home.livery_id == "cromo-carbono-azul",
			"Home remembers the blimp and its skin (%s %s %s)" % [app.home.activity_id, app.home.airship_skin_id, app.home.livery_id])
		app.set_start_choice("airborne")
		app.window_focus_probe = func() -> bool: return false
		app.home.fly_button.pressed.emit()
		activity = app.ground_vehicle
		check(activity != null and activity.session.options.start == "air" and activity.hud.menu_visible
			and activity.session.paused and activity.hud.resume_button.has_focus(),
			"an unfocused air release remains paused with Resume ready for keyboard navigation")
	await ui.close_app(app)
	print("Airship activity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
