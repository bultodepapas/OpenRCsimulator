extends SceneTree

const Session = preload("res://sim/helicopter_flight_session.gd")
const FlightMain = preload("res://helicopter_main.gd")
const Field = preload("res://data/field_loader.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	var session: Node = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	root.add_child(session)
	var flight = FlightMain.new()
	flight.session = session
	session.resetting.connect(flight._on_session_resetting)
	session.sim.stepped.connect(flight._on_sim_stepped)
	check("pre-reset presentation is unavailable", flight._collective_hud_line().contains("Collective unavailable"))
	var loaded: Dictionary = Field.load_from()
	check("ground trainer session resets", loaded.ok and session.setup()
		and session.set_field(loaded.field) and session.set_start_choice("ground") and session.reset())
	if not session.is_flyable():
		flight.free()
		session.queue_free()
		await process_frame
		_finish()
		return
	_check_current("reset", session, flight)
	for mode: String in ["normal", "idle_up"]:
		for trainer_enabled: bool in [false, true]:
			session.flight_mode = mode
			session.trainer_enabled = trainer_enabled
			for values: Array in [[1.0, 0.0, 0.0], [1.0, 1.0, -1.0],
					[0.0, 0.0, 0.0], [0.0, -1.0, 1.0]]:
				var throttle: float = values[0]
				var roll: float = values[1]
				var pitch: float = values[2]
				session.commands = {"roll": roll, "pitch": pitch, "yaw": 0.0, "throttle": throttle}
				session.sim.inputs = PackedFloat64Array([roll, pitch, 0.0, throttle])
				var old_tick: int = session.sim.tick
				session.sim.step()
				var label: String = "%s trainer=%s controls=%s" % [mode, trainer_enabled, str(values)]
				check(label + " is an accepted tick", session.sim.tick == old_tick + 1 and session.is_flyable())
				_check_current(label, session, flight)
				if not trainer_enabled and absf(roll) > 0.0:
					var expected: Dictionary = _electronics(session)
					check(label + " uses saturation instead of premix", expected.servo_travel_limited
						and absf(expected.collective_75_rad - session.collective_pitch()) > 1.0e-4)
	# A changed input has not yet been accepted; the line retains its own
	# sampled collective, stick and mode until the next accepted tick.
	var before: String = flight._collective_hud_line()
	session.commands = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 1.0}
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	check("unaccepted stick change does not rewrite endpoint HUD", flight._collective_hud_line() == before)
	var prior_tick: int = session.sim.tick
	session.sim.step()
	check("next tick accepts the new input", session.sim.tick == prior_tick + 1)
	_check_current("changed stick accepted", session, flight)
	var saved: Dictionary = session.checkpoint()
	check("matching endpoint checkpoint is available", not saved.is_empty())
	# Deliberately populate a different same-tick render cache, then restore.
	# Restore must invalidate it even when the integer tick is unchanged.
	session.commands = {"roll": 1.0, "pitch": -1.0, "yaw": 0.0, "throttle": 0.0}
	session.sim.inputs = PackedFloat64Array([1.0, -1.0, 0.0, 0.0])
	flight._cache_presentation_telemetry(session.sim.state, session.sim.continuous, session.sim.inputs, session.sim.time())
	check("checkpoint restore accepts same tick", session.restore_checkpoint(saved).ok)
	check("restore invalidates stale display", flight._collective_hud_line().contains("Collective unavailable"))
	flight._ensure_rotor_phase_current()
	_check_current("restored endpoint", session, flight)
	check("ordinary reset returns to initial accepted telemetry", session.reset())
	_check_current("second reset", session, flight)
	var before_mode: String = flight._collective_hud_line()
	session.commands = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.5}
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	var changed_mode: bool = session.request_flight_mode()
	if not changed_mode:
		changed_mode = session.request_flight_mode()
	check("mode transition accepted", changed_mode and session.flight_mode == "idle_up")
	check("pre-tick mode action leaves endpoint HUD unchanged", flight._collective_hud_line() == before_mode)
	prior_tick = session.sim.tick
	session.sim.step()
	check("mode's first tick is accepted", session.sim.tick == prior_tick + 1)
	_check_current("accepted new mode", session, flight)
	var invalid: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, NAN, 0.0])
	flight._cache_presentation_telemetry(session.sim.state, session.sim.continuous, invalid, session.sim.time())
	check("failed electronics evaluation never reports fallback zero as accepted",
		not flight._collective_telemetry_valid and flight._collective_hud_line().contains("Collective unavailable"))
	flight.free()
	session.queue_free()
	await process_frame
	_finish()


func _electronics(session: Node) -> Dictionary:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	state.append_array(session.sim.continuous.slice(0, 6))
	var inputs: PackedFloat64Array = session.sim.inputs
	var sticks: PackedFloat64Array = PackedFloat64Array([-inputs[1], inputs[0], inputs[2], 2.0 * inputs[3] - 1.0])
	return Electronics.fast_evaluate(session.aircraft.context.electronics_model, state, sticks,
		session.flight_mode, session.trainer_enabled, session._trim)


func _check_current(label: String, session: Node, flight: Variant) -> void:
	var result: Dictionary = _electronics(session)
	check(label + " electronics valid", result.ok)
	if not result.ok:
		return
	var expected: String = tr("Collective %.1f deg (stick %.0f%%) · %s · %s") % [
		rad_to_deg(result.collective_75_rad), session.sim.inputs[3] * 100.0,
		session.flight_mode, tr(session.power_phase())]
	check(label + " HUD uses same endpoint postmix and stick", flight._collective_telemetry_valid
		and flight._collective_hud_line() == expected
		and absf(float(flight._rotor_state.collective) - result.collective_75_rad) < 1.0e-12)


func _finish() -> void:
	print("HELI H06 collective HUD: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
