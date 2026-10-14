extends SceneTree
const AppRoot = preload("res://app_root.gd")
const Activity = preload("res://vehicles/ground/ground_scene.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Frames = preload("res://render/frames.gd")
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
	var home_field: Dictionary = original_background.field.duplicate(true)
	var home_lighting: Dictionary = original_background.lighting_config.duplicate(true)
	var home_sky: Dictionary = original_background.sky_config.duplicate(true)
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
	check(app.ground_vehicle.field == home_field, "truck uses the exact field accepted by Home")
	check(app.ground_vehicle.lighting_config == home_lighting and app.ground_vehicle.sky_config == home_sky, "Home lighting and sky carry into the truck")
	var dashboard: CanvasLayer = app.ground_vehicle.dashboard
	check(dashboard.airfield and dashboard.modes.item_count == 2 and dashboard.modes.get_item_id(1) == 2, "shared airfield exposes free drive and laboratory")
	check(dashboard.locations.item_count == 5 and dashboard.track_available, "garage offers two runway starts and three obstacle circuit entries")
	dashboard.modes.item_selected.emit(1)
	check(app.ground_vehicle.mode == 2 and dashboard.lab.visible, "laboratory selection keeps its mode ID after removing the practice entry")
	dashboard.locations.item_selected.emit(1)
	check(app.ground_vehicle.session.spawn_id == "runway_end" and app.ground_vehicle.session.paused, "runway-end selector resets safely on the same field")
	for location in range(2, 5):
		dashboard.locations.item_selected.emit(location)
		check(app.ground_vehicle.session.spawn_id == dashboard.spawn_ids[location] and app.ground_vehicle.session.paused and dashboard.locations.selected == location, "circuit entry %d resets safely and keeps selection synchronized" % location)
	var before_view: PackedFloat64Array = app.ground_vehicle.session.state_snapshot()
	app.ground_vehicle.handle_action("track_view")
	app.ground_vehicle._process(0.0)
	check(app.ground_vehicle.camera_rig.mode == 3 and before_view == app.ground_vehicle.session.state_snapshot(), "circuit overview is presentation-only")
	app.ground_vehicle.handle_action("reset")
	check(dashboard.locations.selected == dashboard.spawn_ids.find(app.ground_vehicle.session.spawn_id), "reset synchronizes location selector")
	await process_frame
	app.ground_vehicle.handle_action("home")
	await process_frame
	await process_frame
	check(app.ground_vehicle == null and app.home != null, "truck returns to Home")
	check(app.home.aircraft_id == initial_aircraft, "aircraft selection survives RC visit")
	app.free()
	await process_frame
	var direct := AppRoot.new()
	# A shifted field makes hard-coded default terrain/spawn/pilot coordinates observable.
	var custom: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH))
	custom.id = "rcv-menu-shifted-field"
	custom.objects = []
	custom.erase("flight_cues")
	# This fixture isolates a translated runway; the optional rotorcraft site's absolute keepouts do not belong to it.
	custom.erase("rotorcraft_pad")
	custom.surfaces = custom.surfaces.filter(func(surface: Dictionary) -> bool: return surface.type != "rotorpad")
	custom.pilot.north.value = 120.0
	custom.pilot.east.value = -90.0
	for surface: Dictionary in custom.surfaces:
		surface.center_north.value += 120.0
		surface.center_east.value -= 90.0
	var custom_path := "user://test_rcv_menu_field.json"
	var custom_file := FileAccess.open(custom_path, FileAccess.WRITE)
	custom_file.store_string(JSON.stringify(custom))
	custom_file.close()
	direct.field_path = custom_path
	direct.user_args = PackedStringArray(["--vehicle=mt8-bisonte"])
	direct.preferences_path = "user://rcv_direct_must_not_exist.cfg"
	direct.ground_vehicle_factory = _factory
	root.add_child(direct)
	await process_frame
	await process_frame
	check(direct.ground_vehicle != null and direct.home == null and direct.flight == null, "explicit vehicle CLI selects ground activity")
	if direct.ground_vehicle != null:
		var truck: Node3D = direct.ground_vehicle
		check(truck.field.id == custom.id, "direct route honors the selected aircraft field path")
		check(not truck.dashboard.track_available and truck.dashboard.locations.item_count == 2, "custom fields do not receive misplaced default circuit entries")
		var pose: PackedFloat64Array = truck.session.state_snapshot()
		check(absf(pose[0] - 135.0) < 0.01 and absf(pose[1] + 90.0) < 0.01, "truck spawns at the shifted runway center")
		check(truck.camera_rig.pilot_position.is_equal_approx(Frames.ned_to_render([120.0, -90.0, -1.7])), "driver camera uses the shared pilot station")
	check(direct.preferences.is_empty() and not FileAccess.file_exists(direct.preferences_path), "direct route bypasses aircraft preferences")
	direct.free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(custom_path))
	print("RCV menu: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
