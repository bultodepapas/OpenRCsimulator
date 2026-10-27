# AV-FLAP-UI: flap input, capability messaging, live rendered travel and reset use the session's accepted angle.
# Run: godot --headless --path . --script res://tests/test_flaps_ui.gd
extends SceneTree

const MainScene := preload("res://main.tscn")
const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const AVANTI := "sebart-avanti-s-a200-p100rx"

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Variant = MainScene.instantiate()
	main.set("aircraft_id", AVANTI)
	main.set("user_args", PackedStringArray(["soundscape=off"]))
	root.add_child(main)
	for _frame in 30:
		if main.get("session") != null:
			break
		await process_frame
	var session: Variant = main.get("session")
	_check("production Vantage Jet scene starts with a flap-capable session", session != null and session.flaps_available())
	if session == null or not session.flaps_available():
		await _finish(main)
		return
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	main.set_process(false)
	_check("controller capability follows the available Vantage Jet", bool(main.controller_capabilities().flaps))
	_check("new flight starts with flaps retracted", _requested(session) == 0.0 and _actual(session) == 0.0)

	await _tap_key(KEY_F)
	_check("F requests the 40% takeoff detent", is_equal_approx(_requested(session), 0.4))
	await _tap_key(KEY_F)
	_check("F advances to the 100% landing detent", is_equal_approx(_requested(session), 1.0))
	await _tap_key(KEY_F)
	_check("F cycles from landing back to retracted", is_equal_approx(_requested(session), 0.0))
	await _tap_key(KEY_F, true)
	_check("Shift+F steps backward from retracted to landing", is_equal_approx(_requested(session), 1.0))
	session.reset()
	_check("flight reset clears the flap request", _requested(session) == 0.0 and _actual(session) == 0.0)

	_check("controller cycle requests 40% takeoff flaps", main.controller_action("flaps_cycle") and is_equal_approx(_requested(session), 0.4))
	main._update_hud()
	_check("English HUD shows actual and requested target flap angles", main.get("_hud").text.contains("Flaps: 0.0° actual → 20.0° target"))
	TranslationServer.set_locale("es")
	main._update_hud()
	_check("Spanish HUD localizes actual and target flap angles", main.get("_hud").text.contains("Flaps: 0.0° reales → 20.0° objetivo"))
	TranslationServer.set_locale("en")
	_check("controller down/up actions request landing and retracted positions",
		main.controller_action("flaps_down") and is_equal_approx(_requested(session), 1.0)
		and main.controller_action("flaps_up") and is_equal_approx(_requested(session), 0.0))

	main.controller_action("flaps_down")
	for _tick in 20:
		session._physics_process(session.sim.dt())
		session.sim.step()
	var moving: Dictionary = session.flap_state()
	_check("session reports a flap actuator between endpoints while moving",
		bool(moving.get("moving", false)) and _actual(session) > 0.0 and _actual(session) < 1.0, str(moving))
	main._render_pose(main._current_pose(), session.surfaces(), 0.0)
	_check("production render applies the actual in-transit angle to both flap hinges",
		_hinge_matches(main.get("_airplane"), "flap_left", float(moving.angle_deg))
		and _hinge_matches(main.get("_airplane"), "flap_right", float(moving.angle_deg)), str(moving))

	var speed_before: PackedFloat64Array = session.sim.state.duplicate()
	session.sim.state[RB.VEL] = 100.0
	session.sim.state[RB.VEL + 1] = 0.0
	session.sim.state[RB.VEL + 2] = 0.0
	var overspeed: Dictionary = session.flap_state()
	main._update_hud()
	_check("overspeed advisory names the estimated equivalent airspeed limit", bool(overspeed.get("overspeed", false))
		and main.get("_hud").text.contains("above estimated speed limit") and main.get("_hud").text.contains("m/s EAS"))
	_check("overspeed advisory leaves the landing flap request intact", _requested(session) == 1.0)
	session.sim.state = speed_before

	session.reset()
	main._render_pose(main._current_pose(), session.surfaces(), 0.0)
	_check("reset restores the actual flap state and rendered hinges to neutral",
		_requested(session) == 0.0 and _actual(session) == 0.0
		and _hinge_matches(main.get("_airplane"), "flap_left", 0.0)
		and _hinge_matches(main.get("_airplane"), "flap_right", 0.0))

	var fixed: Node = Session.new()
	fixed.setup()
	main.set("session", fixed)
	_check("fixed-gear Stik does not advertise flaps", not bool(main.controller_capabilities().flaps)
		and not bool(fixed.flap_state().get("available", false)))
	main.controller_action("flaps_down")
	_check("unavailable aircraft show the flap capability message", str(main.get("_note")).contains("unavailable"))
	main.set("session", session)
	var capture_out := _argument_value("--capture-flaps-out=")
	if not capture_out.is_empty():
		await _capture_full_flaps(main, session, capture_out)
	await _finish(main)
	fixed.free()


func _tap_key(code: Key, shift := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame


func _requested(session: Node) -> float:
	return float(session.flap_state().get("requested", -1.0))


func _actual(session: Node) -> float:
	return float(session.flap_state().get("actual", -1.0))


func _hinge_matches(airplane: Dictionary, key: String, degrees: float) -> bool:
	var hinge: Dictionary = airplane.get("hinges", {}).get(key, {})
	if hinge.is_empty() or not (hinge.get("node") is Node3D):
		return false
	var expected: Basis = hinge.rest if degrees == 0.0 else Basis(hinge.axis, deg_to_rad(degrees * float(hinge.app_sign))) * hinge.rest
	return hinge.node.basis.is_equal_approx(expected)


func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	await process_frame
	print("flaps UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _capture_full_flaps(main: Node, session: Node, path: String) -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	_check("capture session accepts full landing flap request", session.set_flaps(1.0))
	var tick_count := 0
	while float(session.flap_state().get("actual", 0.0)) < 1.0 - 1e-9 and tick_count < 2400:
		var dt: float = session.sim.dt()
		session._physics_process(dt)
		session.sim.step()
		tick_count += 1
	var state: Dictionary = session.flap_state()
	_check("capture reaches full actual flap deployment", is_equal_approx(float(state.get("actual", 0.0)), 1.0), str(state))
	main.set("_note", "")
	var rig: Variant = main.get("_rig")
	if rig != null:
		rig.set_view("orbit")
		rig.orbit.azimuth_deg = 40.0
		rig.orbit.elevation_deg = 24.0
		rig.orbit.distance = 3.5
		rig.set("_orbit_primed", true)
	main.set_process(true)
	main.call("_process", 0.0)
	main.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	_check("capture viewport is 1280x720", image.get_size() == Vector2i(1280, 720), str(image.get_size()))
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(directory)
	var error: Error = image.save_png(path)
	_check("native rendered full-flap capture saves", error == OK, error_string(error))
	var manifest_path := path.get_basename() + ".json"
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file != null:
		manifest_file.store_string(JSON.stringify({
			"format": "openrc-ui-capture v2",
			"capture_scene": "flaps",
			"image": path.get_file(),
			"sha256": FileAccess.get_sha256(path),
			"ui_evidence": {
				"renderer": RenderingServer.get_current_rendering_method(),
				"flap_state": state,
				"hud": str(main.get("_hud").text),
				"camera_view": str(rig.get("view")) if rig != null else "unknown",
			},
		}, "\t") + "\n")
		manifest_file.close()
	_check("capture runtime sidecar saves", manifest_file != null)
	print("flaps capture saved: %s; renderer=%s" % [path, RenderingServer.get_current_rendering_method()])


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with(prefix):
			return str(argument).trim_prefix(prefix)
	return ""
