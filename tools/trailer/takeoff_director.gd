## FW-RGB-13 continuous runway departure using the existing scenery test pilot.
## Supplies ordinary controls only. Estimated Stik scenario, not a validated pilot model.
extends "flight_director.gd"

const TakeoffPilot := preload("res://scenery/takeoff_pilot.gd")
const FlightMath := preload("res://physics/math3d.gd")

var _heading_target := 0.0
var _configured_tick := 0
var _departure_phase := "idle"
var _pilot_source_sha256 := ""
var _configuration_error := ""


func configure(flight_main: Node, shot_name: String, shot_duration_s: float, output_fps: int) -> void:
	if shot_name != "lighting-takeoff" or str(flight_main.aircraft_id) != "jensen-das-ugly-stik-60" \
			or str(flight_main.session.start_choice) != "runway":
		_configuration_error = "takeoff_director requires lighting-takeoff, the stock Stik family and a runway start"
		return
	_configuration_error = ""
	super.configure(flight_main, shot_name, shot_duration_s, output_fps)
	_heading_target = FlightMath.q_to_euler(main.session.sim.state.slice(RB.ATT, RB.ATT + 4))[0]
	_configured_tick = int(main.session.sim.tick)
	_pilot_source_sha256 = FileAccess.get_sha256("res://scenery/takeoff_pilot.gd")


func configuration_error() -> String:
	return _configuration_error


func _commands_at(_time_s: float) -> Dictionary:
	var elapsed := float(int(main.session.sim.tick) - _configured_tick) * float(main.session.sim.dt())
	var result: Dictionary = TakeoffPilot.step(elapsed, main.session.sim.state, _heading_target)
	_departure_phase = str(result.phase)
	return result.commands


func _place_camera(_time_s: float) -> void:
	var aircraft: Node3D = main._airplane.root
	var body := aircraft.global_basis.orthonormalized()
	var forward := Vector3(-body.z.x, 0.0, -body.z.z).normalized()
	if forward.length_squared() < 0.9:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var center := aircraft.global_position
	# A level chase rail keeps the runway and complete airframe visible through rotation.
	main._camera.global_position = center - forward * 7.0 + right * 2.0 + Vector3.UP * 1.8
	main._camera.look_at(center + forward * 0.25 + Vector3.UP * 0.1, Vector3.UP)
	main._camera.fov = 40.0


func record_presented_frame(frame_index: int, preroll_frames: int) -> void:
	var count_before := frame_records.size()
	super.record_presented_frame(frame_index, preroll_frames)
	if frame_records.size() != count_before + 1:
		return
	frame_records[-1]["runway_departure"] = _departure_evidence(main.session.sim.state)


func _on_sim_stepped(tick: int, time_s: float, state: PackedFloat64Array, loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	var count_before := tick_records.size()
	super._on_sim_stepped(tick, time_s, state, loads, inputs, aux)
	if tick_records.size() == count_before + 1:
		tick_records[-1]["runway_departure"] = _departure_evidence(state)


func _departure_evidence(state: PackedFloat64Array) -> Dictionary:
	var speed := FlightMath.norm(state.slice(RB.VEL, RB.VEL + 3))
	var heading: float = FlightMath.q_to_euler(state.slice(RB.ATT, RB.ATT + 4))[0]
	var compressions: PackedFloat64Array = main.session.gear_compressions(state)
	var wheels_supported := 0
	var minimum_clearance := INF
	for compression: float in compressions:
		wheels_supported += 1 if compression > 0.0 else 0
		minimum_clearance = minf(minimum_clearance, -compression)
	return {
		"state_sample": "accepted_tick_endpoint",
		"state_tick": int(main.session.sim.tick),
		"phase": _departure_phase,
		"pilot_elapsed_s": float(int(main.session.sim.tick) - _configured_tick) * float(main.session.sim.dt()),
		"configured_tick": _configured_tick,
		"speed_mps": speed,
		"cg_altitude_m": -float(state[RB.POS + 2]),
		"hull_ground_contact": main.session.touches_ground(state),
		"gear_compressions_m": Array(compressions),
		"wheels_supported": wheels_supported,
		"minimum_gear_clearance_m": minimum_clearance if not compressions.is_empty() else null,
		"heading_error_deg": rad_to_deg(wrapf(heading - _heading_target, -PI, PI)),
		"pilot_source_sha256": _pilot_source_sha256,
	}
