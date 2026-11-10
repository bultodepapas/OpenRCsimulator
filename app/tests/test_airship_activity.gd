# BL-10/BL-12: Home -> Garage "RC blimp" choice -> Fly RC blimp -> airship activity -> Home. Checks the
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
	app.home._page_buttons[3].pressed.emit()
	await process_frame
	var choice: OptionButton = app.home.ground_vehicle_choice
	check(choice.item_count == GroundCatalog.IDS.size() + Catalog.SKIN_IDS.size(), "Garage lists the RC cars and every blimp skin")
	var historic := GroundCatalog.IDS.size() + Catalog.SKIN_IDS.find("historico")
	choice.select(historic)
	choice.item_selected.emit(historic)
	check(app.home.ground_vehicle_button.text == "Fly RC blimp" and app.home.airship_skin_id == "historico", "a blimp skin turns the Garage action into Fly RC blimp")
	var car_requests := [0]
	app.home.ground_vehicle_requested.connect(func() -> void: car_requests[0] += 1)
	app.home.ground_vehicle_button.pressed.emit()
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
	activity.handle_action("home")
	for i in 8:
		await process_frame
	check(app.ground_vehicle == null and app.home != null, "Home returns after the blimp activity")
	if app.home != null:
		check(app.home.airship_selected and app.home.airship_skin_id == "historico" and app.home.ground_vehicle_button.text == "Fly RC blimp",
			"Garage remembers the blimp and its skin (%s %s %s)" % [app.home.airship_selected, app.home.airship_skin_id, app.home.ground_vehicle_button.text])
	await ui.close_app(app)
	print("Airship activity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
