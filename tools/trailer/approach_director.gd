## FW-RGB-13 synthetic-entry approach; existing experimental Stik pilot, unchanged physics.
extends "flight_director.gd"

const ApproachPilot := preload("res://sim/landing_maneuver.gd")
const FlightMath := preload("res://physics/math3d.gd")
const FlightTrim := preload("res://physics/trim.gd")

var _pilot: RefCounted
var _configuration_error := ""
var _fixture := {}
var _runway := {}


func configure(flight_main: Node, shot_name: String, shot_duration_s: float, output_fps: int) -> void:
	if shot_name != "lighting-approach" or str(flight_main.aircraft_id) != "jensen-das-ugly-stik-60" \
			or str(flight_main.session.start_choice) != "airborne":
		_configuration_error = "approach_director requires lighting-approach, the stock Stik family and an airborne start"
		return
	var session: Node = flight_main.session
	if not session.aircraft.model.propulsion.get("slipstream", {}).is_empty():
		_configuration_error = "approach_director is limited to the existing wash-off Stik test condition"
		return
	if not session.weather_is_calm():
		_configuration_error = "approach_director requires calm weather for the existing experimental pilot"
		return
	for surface: Dictionary in flight_main.field.get("surfaces", []):
		if str(surface.get("id", "")) == str(flight_main.field.get("runway", "")):
			_runway = surface.duplicate(true)
	if _runway.is_empty() or session.gear_compressions(session.sim.state).is_empty():
		_configuration_error = "approach_director requires the field runway and observable landing gear"
		return
	# Explicit reference-speed fixture, as in landing_test_driver.gd. Set altitude before
	# trimming so reset does not re-solve the atmosphere and replace the staged attitude.
	session.trim_throttle = NAN
	session.set_start_altitude(ApproachPilot.START_ALTITUDE)
	var trimmed: Dictionary = session.trim_at(ApproachPilot.APPROACH_SPEED)
	if not bool(trimmed.get("ok", false)):
		_configuration_error = "approach trim failed: " + str(trimmed.get("message", ""))
		return
	var initial: PackedFloat64Array = FlightTrim.state_for(ApproachPilot.APPROACH_SPEED,
		float(trimmed.alpha), 0.0, PI / 2.0,
		FlightMath.v3(float(_runway.center_north),
			float(_runway.center_east) - float(_runway.length_east_west) / 2.0 - ApproachPilot.START_BEFORE_END,
			-ApproachPilot.START_ALTITUDE), float(trimmed.beta))
	session.start.state = initial
	session.input_enabled = false
	session.reset()
	if int(session.sim.tick) != 0 or session.sim.state != initial or session.sim.paused or not session.is_flyable() \
			or not str(session.start_error).is_empty() or not str(session.sim.fault_reason).is_empty():
		_configuration_error = "approach fixture reset did not preserve its declared initial state"
		return
	_pilot = ApproachPilot.new(float(_runway.center_north), true, float(trimmed.throttle), float(trimmed.pitch_command))
	_fixture = {
		"kind": "synthetic_approach_entry", "continuous_from_runway": false,
		"initial_tick": 0, "initial_state": Array(initial), "speed_mps": ApproachPilot.APPROACH_SPEED,
		"cg_altitude_m": ApproachPilot.START_ALTITUDE, "eastbound": true,
		"runway_id": str(_runway.id), "trim_throttle": float(trimmed.throttle),
		"trim_commands": session.trims.duplicate(true),
		"pilot_source_sha256": FileAccess.get_sha256("res://sim/landing_maneuver.gd"),
		"session_source_sha256": FileAccess.get_sha256("res://sim/flight_session.gd"),
		"wash_enabled": not session.aircraft.model.propulsion.get("slipstream", {}).is_empty(),
	}
	super.configure(flight_main, shot_name, shot_duration_s, output_fps)


func configuration_error() -> String:
	return _configuration_error


func _commands_at(_time_s: float) -> Dictionary:
	var compressions: PackedFloat64Array = main.session.gear_compressions(main.session.sim.state)
	var clearance := -compressions[0]
	for compression: float in compressions:
		clearance = minf(clearance, -compression)
	return _pilot.commands(main.session.sim.state, clearance)


func _place_camera(_time_s: float) -> void:
	var aircraft: Node3D = main._airplane.root
	var forward := Vector3(-aircraft.global_basis.z.x, 0.0, -aircraft.global_basis.z.z).normalized()
	if forward.length_squared() < 0.9:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	main._camera.global_position = aircraft.global_position - forward * 7.0 + right * 2.0 + Vector3.UP * 1.8
	main._camera.look_at(aircraft.global_position + forward * 0.25 + Vector3.UP * 0.1, Vector3.UP)
	main._camera.fov = 40.0


func record_presented_frame(frame_index: int, preroll_frames: int) -> void:
	var count_before := frame_records.size()
	super.record_presented_frame(frame_index, preroll_frames)
	if frame_records.size() == count_before + 1:
		frame_records[-1]["approach"] = _approach_evidence(main.session.sim.state, int(main.session.sim.tick))
		if count_before == 0:
			frame_records[-1]["approach_fixture"] = _fixture.duplicate(true)


func _on_sim_stepped(tick: int, time_s: float, state: PackedFloat64Array, loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	var count_before := tick_records.size()
	super._on_sim_stepped(tick, time_s, state, loads, inputs, aux)
	if tick_records.size() == count_before + 1:
		tick_records[-1]["approach"] = _approach_evidence(state, tick)


func _approach_evidence(state: PackedFloat64Array, tick: int) -> Dictionary:
	var compressions: PackedFloat64Array = main.session.gear_compressions(state)
	var clearance := -compressions[0]
	var supported := 0
	for compression: float in compressions:
		clearance = minf(clearance, -compression)
		supported += 1 if compression > 0.0 else 0
	var velocity := FlightMath.q_rotate(state.slice(RB.ATT, RB.ATT + 4), state.slice(RB.VEL, RB.VEL + 3))
	var runway_margin := INF
	var max_wheel_sink := -INF
	for contact: Dictionary in main.session.aircraft.model.landing_gear.contacts:
		var attitude := state.slice(RB.ATT, RB.ATT + 4)
		var offset := FlightMath.q_rotate(attitude, contact.position)
		var point := FlightMath.add(state.slice(RB.POS, RB.POS + 3), offset)
		runway_margin = minf(runway_margin, minf(
			float(_runway.length_east_west) / 2.0 - absf(point[1] - float(_runway.center_east)),
			float(_runway.width_north_south) / 2.0 - absf(point[0] - float(_runway.center_north))))
		# Undeformed wheel-reference velocity, including body rotation; not tyre compression rate.
		var local_velocity := FlightMath.add(state.slice(RB.VEL, RB.VEL + 3),
			FlightMath.cross(state.slice(RB.RATE, RB.RATE + 3), contact.position))
		max_wheel_sink = maxf(max_wheel_sink, FlightMath.q_rotate(attitude, local_velocity)[2])
	return {
		"state_sample": "accepted_tick_endpoint", "state_tick": tick,
		"phase": str(_pilot.phase), "speed_mps": FlightMath.norm(state.slice(RB.VEL, RB.VEL + 3)),
		"cg_altitude_m": -float(state[RB.POS + 2]), "sink_mps": velocity[2],
		"cross_track_m": float(state[RB.POS]) - float(_runway.center_north),
		"gear_compressions_m": Array(compressions), "wheels_supported": supported,
		"minimum_gear_clearance_m": clearance, "hull_ground_contact": main.session.touches_ground(state),
		"minimum_wheel_runway_margin_m": runway_margin,
		"maximum_wheel_reference_sink_mps": max_wheel_sink,
	}
