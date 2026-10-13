# Native Home launch diagnostic; never writes the player's preferences.
extends SceneTree
const Prefs = preload("res://app_state/preferences.gd")
const Weather = preload("res://physics/wind_config.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
var app: Node
var records := []
func _initialize() -> void:
	call_deferred("run")
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	for case in [
		["turbo-lumber-evolution", "airborne", -1.0],
		["turbo-lumber-evolution", "airborne", 0.25],
		["turbo-lumber-evolution", "runway", 0.25],
		["jensen-das-ugly-stik-60", "airborne", 0.25],
	]:
		var prefs: Dictionary = Prefs.load_from("user://settings.cfg")
		prefs.aircraft = case[0]
		prefs.start_choice = case[1]
		prefs.check_updates = false
		prefs.first_flight_hint_seen = true
		assert(Prefs.save_to("user://climb_native_probe.cfg",prefs) == OK)
		app = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray()
		app.preferences_path = "user://climb_native_probe.cfg"
		root.add_child(app)
		await process_frame
		await process_frame
		app.home.fly_button.grab_focus()
		key(KEY_ENTER, true)
		key(KEY_ENTER, false)
		await process_frame
		await process_frame
		assert(app.flight != null)
		var flight: Node = app.flight
		var session: Node = flight.session
		if app.pause_menu != null: app.continue_flight()
		if case[2] >= 0.0: session.commands.throttle = case[2]
		flight.recorder.start(session.trace_meta())
		var initial: PackedFloat64Array = session.sim.state.duplicate()
		var timeout_ms: int = Time.get_ticks_msec() + 90000
		var shot := false
		while session.sim.tick < 2400 and Time.get_ticks_msec() < timeout_ms:
			await process_frame
			if session.sim.tick >= 480 and not shot:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../.tools/climb-native-%s-%s-%s.png") % [case[0],case[1],case[2]])
				shot = true
			if session.sim.paused: break
		flight.recorder.stop()
		var state: PackedFloat64Array = session.sim.state
		var velocity: PackedFloat64Array = M.q_rotate(RB._att(state),RB._slice3(state,RB.VEL))
		var result := {id=case[0],launch=case[1],power=case[2],height_m=-state[2],gain_m=initial[2]-state[2],
			seconds=session.sim.time(),pitch_deg=rad_to_deg(M.q_to_euler(RB._att(state))[1]),climb_mps=-velocity[2],
			raw=session.raw.duplicate(),inputs=Array(session.sim.inputs),paused=session.sim.paused,pause_reason=session.pause_reason,trace=flight.recorder.note}
		records.append(result)
		print("NATIVE_RESULT ",JSON.stringify(result))
		app.free()
		await process_frame
	var output := FileAccess.open(ProjectSettings.globalize_path("res://../.tools/climb-native-results.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(records,"\t"))
	quit()

