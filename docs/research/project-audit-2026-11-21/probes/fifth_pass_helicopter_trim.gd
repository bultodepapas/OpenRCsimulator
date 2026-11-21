extends SceneTree

const Session = preload("res://sim/helicopter_flight_session.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const Swash = preload("res://physics/rotorcraft/swash.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var session := Session.new()
	session.input_enabled = false
	session.physics_enabled = false
	root.add_child(session)
	if not session.setup() or not session.reset() or not session.is_flyable():
		print("SESSION PROBE ERROR: ", session.start_error)
		quit(1)
		return
	var state: PackedFloat64Array = session.sim.state.duplicate()
	state.append_array(session.sim.continuous.slice(0,6))
	var sticks := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var out: Dictionary = Electronics.fast_evaluate(session.aircraft.context.electronics_model, state, sticks, session.flight_mode, session.trainer_enabled, session._trim)
	var physical: Dictionary = Swash.linkage_output(out.swash_servo_targets, session.aircraft.context.electronics_model.linkage)
	var untrimmed_bias: Dictionary = session._trim.duplicate(true)
	untrimmed_bias.cyclic_forward_bias_rad = 0.0
	untrimmed_bias.cyclic_right_bias_rad = 0.0
	var wind: PackedFloat64Array = session.wind_at(0.0, state.slice(0, 13))
	var result: Dictionary = Flight.evaluate(state, session.aircraft.context, sticks, "normal", true, false, wind, true, PackedFloat64Array(), session._trim, session._height_over_radius(state))
	var control: Dictionary = Flight.evaluate(state, session.aircraft.context, sticks, "normal", true, false, wind, true, PackedFloat64Array(), untrimmed_bias, session._height_over_radius(state))
	if not result.ok or not control.ok:
		print("SESSION PROBE ERROR: stage comparison failed")
		quit(1)
		return
	var ground: float = session.environment.ground(state[0], state[1])[0]
	var before: int = session.sim.tick
	session.sim.step()
	var accepted: bool = session.sim.tick == before + 1 and session.is_flyable() and session.sim.fault_reason.is_empty()
	print("SESSION ", JSON.stringify({"aircraft_sha":session.aircraft.input_identity.sha256,"start": Array(state.slice(0,3)),"ground_height":ground,"trim":session._trim,"mode":session.flight_mode,"trainer":session.trainer_enabled,"rotorcraft_speed_rad_s":state[13],"angles":[out.collective_75_rad,out.cyclic_forward_rad,out.cyclic_right_rad],"servo":Array(out.swash_servo_targets),"servo_limited":out.servo_travel_limited,"servo_linkage_angles":[physical.theta0_rad,physical.longitudinal_rad,physical.lateral_rad],"flap_rate_actual":Array(result.aero.main_rotor.flap_rate),"flap_rate_zero_bias":Array(control.aero.main_rotor.flap_rate),"tick_before":before,"tick_after":session.sim.tick,"accepted":accepted,"fault":session.sim.fault_reason}))
	if not accepted:
		quit(1)
		return
	print("SESSION_PROBE_COMPLETE")
	quit(0)
