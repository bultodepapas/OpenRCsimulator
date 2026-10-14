extends SceneTree
const Activity = preload("res://vehicles/ground/ground_scene.gd")
const M = preload("res://physics/math3d.gd")
const VehicleDynamics = preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const TICK_DT := 1.0 / 240.0
const JUMP_APPROACH_SPEED_MPS := 4.55
var failures := 0
var checks := 0
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
var activity: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	TranslationServer.set_locale("en")
	activity = Activity.new()
	activity.use_practice_fixture = true # Historical jump regression; production opens the shared airfield.
	activity.enable_audio = false
	activity.enable_course_visual = false
	root.add_child(activity)
	activity.set_physics_process(false)
	activity.set_process(false)
	check(activity.startup_error.is_empty(), "activity prepares: " + activity.startup_error)
	if not activity.startup_error.is_empty():
		activity.free()
		quit(1)
		return
	check(activity.session.paused and activity.dashboard.menu_visible, "starts paused in garage")
	activity.session.tick_once({"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true})
	# The activity rechecks current input at the click boundary, not a cached tick.
	var held_key := InputEventKey.new()
	held_key.physical_keycode = KEY_W
	held_key.keycode = KEY_W
	held_key.pressed = true
	Input.parse_input_event(held_key)
	await process_frame
	await process_frame
	activity.handle_action("resume")
	check(activity.session.paused, "held throttle cannot resume")
	held_key = held_key.duplicate()
	held_key.pressed = false
	Input.parse_input_event(held_key)
	await process_frame
	await process_frame
	activity.session.tick_once(NEUTRAL)
	activity.handle_action("resume")
	check(not activity.session.paused and not activity.dashboard.menu_visible, "explicit neutral resume starts driving")
	for i in 24:
		activity.session.tick_once(NEUTRAL)
	check(activity.session.tick == 24, "fixed-tick session advances")
	var state_before: PackedFloat64Array = activity.session.state_snapshot()
	for i in 4:
		activity._process(1.0 / 30.0)
		activity.handle_action("camera")
		activity.handle_action("body")
		activity.handle_action("contacts")
	check(activity.session.state_snapshot() == state_before and activity.session.tick == 24, "camera and HUD are read-only observers")
	activity.open_garage()
	activity.session.tick_once(NEUTRAL)
	check(activity.session.tick == 24, "garage freezes simulation time")
	activity._select_mode(2)
	check(activity.dashboard.lab.visible, "physics lab exposes parameters")
	activity._experiment({"gravity_scale": 1.0, "grip_scale": 0.8, "spring_scale": 1.2, "damper_scale": 1.1, "ballast_kg": 0.2, "ballast_height_m": 0.2})
	check(activity.session.tick == 0 and activity.session.paused, "experiment resets transactionally and remains paused")
	check(activity.session.model_snapshot().sprung_mass_kg > 3.0, "ballast reaches physical model")
	activity.handle_action("recover")
	check(not activity.session.run_valid and activity.session.paused, "manual recovery is assisted and paused")
	activity.handle_action("reset")
	check(activity.session.run_valid and activity.session.paused, "reset starts a new valid run")
	activity._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(activity.session.paused and activity.dashboard.menu_visible, "focus loss opens garage")
	activity._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(activity.session.paused, "focus return never auto-resumes")
	check(activity.session.reset("jump_start"), "jump scenario selects the supported jump_start spawn")
	activity._after_reset()
	activity.scripted_controls = Callable(self, "_jump_controls")
	activity.session.tick_once(NEUTRAL)
	activity.handle_action("resume")
	check(not activity.session.paused, "jump scenario resumes after neutral input")
	var jump_event: Dictionary = {}
	var landing_event: Dictionary = {}
	var airborne_feedback := false
	var landed_feedback := false
	var landing_contact_count := 0
	var landing_upright_dot := -1.0
	var peak_jump_speed_mps := 0.0
	for _tick in 1200:
		activity._physics_process(TICK_DT)
		var current_telemetry: Dictionary = activity.session.telemetry_snapshot()
		peak_jump_speed_mps = maxf(peak_jump_speed_mps,
			float(current_telemetry.get("speed_m_per_s", 0.0)))
		var events: Array[Dictionary] = activity.session.event_tape_snapshot()
		for event in events:
			if str(event.get("type", "")) == "jump" and jump_event.is_empty():
				jump_event = event.duplicate(true)
				activity._process(0.0)
				airborne_feedback = activity.dashboard.telemetry.text.contains("AIR")
			if str(event.get("type", "")) == "landing" and not jump_event.is_empty() \
					and int(event.get("tick", -1)) > int(jump_event.get("tick", -1)) and landing_event.is_empty():
				landing_event = event.duplicate(true)
				activity._process(0.0)
				landed_feedback = not activity.dashboard.telemetry.text.contains("AIR")
				var landing_telemetry: Dictionary = activity.session.telemetry_snapshot()
				var landing_contacts: PackedByteArray = landing_telemetry.wheel_in_contact
				for contact in landing_contacts:
					landing_contact_count += int(contact != 0)
				landing_upright_dot = _upright_dot(activity.session.state_snapshot())
		if not jump_event.is_empty() and not landing_event.is_empty():
			break
	var airtime := float(landing_event.get("time_s", -1.0)) - float(jump_event.get("time_s", 0.0))
	var accepted_control_tape: PackedFloat64Array = activity.session.control_tape_snapshot()
	var ordinary_controls_accepted: bool = accepted_control_tape.size() == activity.session.tick * 4
	var takeoff_tick := int(jump_event.get("tick", -1))
	for accepted_tick in range(1, int(accepted_control_tape.size() / 4) + 1):
		var offset := (accepted_tick - 1) * 4
		var throttle := accepted_control_tape[offset]
		ordinary_controls_accepted = ordinary_controls_accepted \
			and throttle >= 0.0 and throttle <= 1.0 \
			and accepted_control_tape[offset + 1] == 0.0 \
			and accepted_control_tape[offset + 2] == 0.0 \
			and accepted_control_tape[offset + 3] == 0.0
		if takeoff_tick >= 0 and accepted_tick > takeoff_tick and throttle != 0.0:
			ordinary_controls_accepted = false
	print("RCV activity jump: takeoff=", jump_event, " landing=", landing_event,
		" peak_speed=", peak_jump_speed_mps, " airtime=", airtime,
		" contact_count=", landing_contact_count, " upright=", landing_upright_dot,
		" air_feedback=", airborne_feedback, " landed_feedback=", landed_feedback,
		" hud=", activity.dashboard.telemetry.text)
	check(ordinary_controls_accepted,
		"Session tape records bounded throttle only, released from the first airborne tick")
	check(not jump_event.is_empty() and not landing_event.is_empty(), "real course drive records jump and landing events")
	check(peak_jump_speed_mps >= 4.4 and peak_jump_speed_mps < 6.0,
		"speed-limited jump reaches the controlled 4.55 m/s approach band (peak %.2f m/s)" % peak_jump_speed_mps)
	check(airborne_feedback and landed_feedback,
		"HUD reports AIR during flight and leaves AIR at wheel contact (air=%s landed=%s)" % [airborne_feedback, landed_feedback])
	check(airtime > 0.08 and float(activity._airtime) > 0.08,
		"activity derives airtime from observed physics events (event %.3f s, scene %.3f s)" % [airtime, activity._airtime])
	check(landing_contact_count > 0 and landing_upright_dot > 0.65,
		"landing has wheel support and upright attitude (contacts %d, upright %.4f)" % [landing_contact_count, landing_upright_dot])
	for _tick in 24:
		activity._physics_process(TICK_DT)
	check(activity.session.run_valid and not activity.session.paused, "unassisted jump landing preserves a valid driving run")
	check(activity.session.event_tape_snapshot().all(func(event: Dictionary) -> bool: return str(event.get("type", "")) != "manual_recovery"), "jump test does not use manual recovery")
	activity.free()
	await process_frame
	print("RCV activity: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _jump_controls(_tick: int) -> Dictionary:
	var controls: Dictionary = NEUTRAL.duplicate(true)
	# The practice spawn can emit a startup landing before a real jump. Keep the
	# ordinary speed-limited throttle until the jump event, then coast through flight.
	var takeoff_recorded := false
	for event in activity.session.event_tape_snapshot():
		if str(event.get("type", "")) == "jump":
			takeoff_recorded = true
			break
	if not takeoff_recorded:
		var state: PackedFloat64Array = activity.session.state_snapshot()
		controls.throttle = clampf((JUMP_APPROACH_SPEED_MPS - absf(state[VehicleDynamics.VEL])) * 0.8, 0.0, 1.0)
	return controls


func _upright_dot(state: PackedFloat64Array) -> float:
	var x := state[VehicleDynamics.ATT + 1]
	var y := state[VehicleDynamics.ATT + 2]
	return 1.0 - 2.0 * (x * x + y * y)
