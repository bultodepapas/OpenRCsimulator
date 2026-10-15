extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
const AppRoot = preload("res://app_root.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
var checks := 0
var failures := 0

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
	activity.checkpoint_path = "user://rcv/test-monster-car-2-%d.json" % OS.get_process_id()
	return activity

func _run() -> void:
	TranslationServer.set_locale("en")
	var app := AppRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = "user://test_rcv_nitro_activity.cfg"
	app.update_check_url = "http://127.0.0.1:1/unavailable"
	app.ground_vehicle_factory = _factory
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.home != null, "Home opens")
	if app.home == null:
		app.free()
		quit(1)
		return
	var aircraft_id: String = app.home.aircraft_id
	check(app.home.ground_vehicle_choice.item_count == 2, "Home exposes both cars")
	app.home.ground_vehicle_choice.select(1)
	app.home.ground_vehicle_choice.item_selected.emit(1)
	check(app.home.ground_vehicle_id == "monster-car-2", "second choice resolves nitro identity")
	app.home.ground_vehicle_button.pressed.emit()
	await process_frame
	await process_frame
	var activity: Node3D = app.ground_vehicle
	check(activity != null, "Home launches MONSTER CAR 2")
	if activity == null:
		app.free()
		quit(1)
		return
	activity.set_physics_process(false)
	activity.set_process(false)
	check(activity.startup_error.is_empty(), "all model, damage and effects bindings prepare")
	check(activity.vehicle_id == "monster-car-2" and activity.dashboard.nitro, "correct car and dashboard")
	check(activity.session.state_snapshot().size() == 33, "engine and fuel are session state")
	check(activity.session.paused and activity.dashboard.menu_visible, "garage starts paused")
	check(activity.checkpoint_path.contains("monster-car-2"), "save path cannot overwrite Bisonte save")
	check(activity.dashboard.control_hint.text.contains("No reverse"), "controls describe forward-only nitro transmission")
	check(activity._effects != null and activity._wet_effects != null and activity._nitro_exhaust != null, "shared effects and nitro exhaust exist")
	check(activity._effects._headlight_lights.size() >= 2, "authored headlights have runtime beams")
	activity.handle_action("sound")
	check(activity._nitro_sound != null and activity._sound == null, "nitro uses its dedicated spatial voice")
	activity.handle_action("sound")
	var service_body: PackedFloat64Array = activity.session.state_snapshot().slice(0, 31)
	activity.handle_action("engine_stop")
	activity._process(0.0)
	check(activity.session.state_snapshot()[31] == 0.0 and activity.dashboard.telemetry.text.contains("Engine off"), "garage stops engine and reports off state")
	check(not activity.dashboard.refuel_button.disabled and not activity.dashboard.engine_start_button.disabled, "stopped engine permits refuel and restart")
	activity.handle_action("refuel")
	activity.handle_action("engine_start")
	activity._process(0.0)
	check(activity.session.telemetry_snapshot().nitro.engine_running and activity.dashboard.refuel_button.disabled, "restart uses fuel and prevents running refuel")
	check(service_body.to_byte_array() == activity.session.state_snapshot().slice(0, 31).to_byte_array(), "garage engine service preserves chassis pose")
	var bell: MeshInstance3D = activity.visual._mesh_nodes.Campana_Embrague
	var flywheel: MeshInstance3D = activity.visual._mesh_nodes.Volante_Motor
	var bell_rest := bell.transform
	var flywheel_rest := flywheel.transform
	activity.visual.engine_phase_rad = 0.7
	activity._process(0.0)
	check(bell.transform.is_equal_approx(bell_rest) and not flywheel.transform.is_equal_approx(flywheel_rest), "idle flywheel rotates independently of clutch bell")
	var rolling: PackedFloat64Array = activity.session.state_snapshot()
	for wheel in 4: rolling[25 + wheel] = 0.1
	activity._visual_adapter.draw(activity.visual, rolling, activity._model.cg_height_above_chassis_datum_m)
	check(not bell.transform.is_equal_approx(bell_rest), "clutch bell follows wheel transmission phase")
	activity._process(0.0)
	activity.handle_action("clean")
	check(service_body.to_byte_array() == activity.session.state_snapshot().slice(0, 31).to_byte_array(), "cleaning never changes physical state")
	activity.session.tick_once(NEUTRAL)
	activity.handle_action("resume")
	check(not activity.session.paused, "explicit neutral resume")
	var controls := NEUTRAL.duplicate()
	controls.throttle = 0.65
	var fuel_before: float = activity.session.state_snapshot()[32]
	var accepted := true
	for tick in 240:
		accepted = activity.session.tick_once(controls) and accepted
	check(accepted and activity.session.tick == 240, "one second of accepted nitro driving")
	check(activity.session.state_snapshot()[32] < fuel_before, "driving consumes recorded fuel")
	activity._process(1.0 / 60.0)
	check(activity.dashboard.telemetry.text.contains("RPM") and activity.dashboard.telemetry.text.contains("Fuel"), "HUD shows live RPM and fuel")
	check(activity._nitro_exhaust.emitting, "running fueled engine emits exhaust")
	var snapshot: PackedFloat64Array = activity.session.state_snapshot()
	activity.handle_action("body")
	for body: Node3D in activity.visual.get("body_nodes", []):
		check(not body.visible, "body toggle hides supplied shell assembly")
	activity.handle_action("body")
	activity.handle_action("contacts")
	activity.handle_action("camera")
	activity._process(0.0)
	check(snapshot == activity.session.state_snapshot(), "model, HUD, lights and effects cannot mutate simulation")
	activity.open_garage()
	activity._process(0.0)
	check(not activity._nitro_exhaust.emitting and activity._nitro_exhaust.speed_scale == 0.0, "pause freezes exhaust")
	activity.handle_action("save")
	check(FileAccess.file_exists(activity.checkpoint_path), "nitro save writes own checkpoint")
	activity.handle_action("reset")
	check(is_equal_approx(activity.session.state_snapshot()[32], fuel_before), "reset refuels")
	activity.handle_action("restore")
	check(activity.session.state_snapshot() == snapshot and activity.session.paused, "restore recovers all nitro state and remains paused")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activity.checkpoint_path))
	await process_frame
	activity.handle_action("home")
	await process_frame
	await process_frame
	check(app.home != null and app.home.aircraft_id == aircraft_id, "return preserves aircraft selection")
	check(app.home != null and app.home.ground_vehicle_id == "monster-car-2", "return remembers chosen car")
	app.free()
	await process_frame
	var direct := AppRoot.new()
	direct.user_args = PackedStringArray(["--vehicle=monster-car-2"])
	direct.ground_vehicle_factory = _factory
	root.add_child(direct)
	await process_frame
	await process_frame
	check(direct.ground_vehicle != null and direct.ground_vehicle.vehicle_id == "monster-car-2", "CLI selects nitro car")
	direct.free()
	await process_frame
	print("RCV nitro activity: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
