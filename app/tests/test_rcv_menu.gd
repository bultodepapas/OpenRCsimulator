extends SceneTree
const AppRoot = preload("res://app_root.gd")
const Activity = preload("res://vehicles/ground/ground_scene.gd")
var failures := 0
var checks := 0

class RejectedActivity extends Node3D:
	signal home_requested
	var startup_error := "Fixture: invalid ground-vehicle data"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func _factory() -> Node3D:
	var activity := Activity.new()
	activity.enable_audio = false
	activity.enable_course_visual = false
	return activity

func _run() -> void:
	var app := AppRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = "user://test_rcv_menu_settings.cfg"
	app.update_check_url = "http://127.0.0.1:1/unavailable"
	root.add_child(app)
	await process_frame
	await process_frame # Deferred focus settles before a user can activate an entry.
	check(app.home != null, "Home prepares")
	if app.home == null:
		app.free()
		quit(1)
		return
	var initial_aircraft: String = app.home.aircraft_id
	var original_home: Control = app.home
	var original_background: Node3D = app.home_scene
	check(app.home.ground_vehicle_button.is_visible_in_tree(), "RC vehicle choice is visible")
	app.ground_vehicle_factory = func(): return RejectedActivity.new()
	app.home.ground_vehicle_requested.emit()
	await process_frame
	await process_frame
	check(app.ground_vehicle == null and app.home == original_home and app.home_scene == original_background, "rejected truck restores exact Home and backdrop")
	check(app.home_scene.camera.is_current(), "rejected startup restores Home camera")
	app.ground_vehicle_factory = _factory
	app.home.ground_vehicle_requested.emit()
	await process_frame
	await process_frame
	check(app.ground_vehicle != null and app.flight == null and app.home == null, "Home routes to ground session only")
	if app.ground_vehicle == null:
		app.free()
		quit(1)
		return
	app.ground_vehicle.set_physics_process(false)
	check(app.ground_vehicle.session.paused and app.ground_vehicle.dashboard.menu_visible, "Home transition starts safely in garage")
	app.ground_vehicle.handle_action("home")
	await process_frame
	await process_frame
	check(app.ground_vehicle == null and app.home != null, "truck returns to Home")
	check(app.home.aircraft_id == initial_aircraft, "aircraft selection survives RC visit")
	app.free()
	await process_frame
	var direct := AppRoot.new()
	direct.user_args = PackedStringArray(["--vehicle=mt8-bisonte"])
	direct.preferences_path = "user://rcv_direct_must_not_exist.cfg"
	direct.ground_vehicle_factory = _factory
	root.add_child(direct)
	await process_frame
	await process_frame
	check(direct.ground_vehicle != null and direct.home == null and direct.flight == null, "explicit vehicle CLI selects ground activity")
	check(direct.preferences.is_empty() and not FileAccess.file_exists(direct.preferences_path), "direct route bypasses aircraft preferences")
	direct.free()
	await process_frame
	print("RCV menu: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
