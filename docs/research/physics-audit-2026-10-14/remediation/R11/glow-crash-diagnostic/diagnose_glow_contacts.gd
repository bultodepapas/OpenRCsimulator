extends SceneTree

const MainScene = preload("res://main.tscn")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Ground = preload("res://physics/ground_contact.gd")
const HullContact = preload("res://physics/hull_contact.gd")

const AIRCRAFT := [
	"jensen-das-ugly-stik-60",
	"stik-glow-61fx-2t",
	"stik-glow-55ax-2t",
	"stik-glow-fs64v-4t",
	"gp-extra-300s-60",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for aircraft_id: String in AIRCRAFT:
		await _integration_fixture(aircraft_id)
		if aircraft_id.begins_with("stik-glow-"):
			await _accepted_tick_fixture(aircraft_id)
		await _pose_fixture(aircraft_id)
	quit(0)


func _make_main(aircraft_id: String, effects_enabled: bool) -> Node:
	var flight: Node = MainScene.instantiate()
	flight.set("aircraft_id", aircraft_id)
	flight.set("crash_effects_enabled", effects_enabled)
	root.add_child(flight)
	return flight


func _integration_fixture(aircraft_id: String) -> void:
	var flight: Node = _make_main(aircraft_id, true)
	var session: Node = flight.get("session")
	if session == null:
		print(JSON.stringify({fixture = "integration", aircraft = aircraft_id, setup = "no_session"}))
		flight.queue_free()
		await process_frame
		return
	session.input_enabled = false
	var first_tick: int = session.sim.tick
	var frames := 0
	while session.sim.tick < first_tick + 100 and frames < 500:
		await physics_frame
		frames += 1
	session.set_physics_process(false)
	var state: PackedFloat64Array = _place_hull_contact(session)
	var previous: PackedFloat64Array = _tick_before(state)
	_emit_pre_state("integration", aircraft_id, session, previous, state)
	session.sim.state = state.duplicate()
	session.sim.previous = previous
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	_emit_post_state("integration", aircraft_id, session, previous, state)
	flight.queue_free()
	await process_frame
	await process_frame


func _pose_fixture(aircraft_id: String) -> void:
	var flight: Node = _make_main(aircraft_id, false)
	var session: Node = flight.get("session")
	if session == null:
		print(JSON.stringify({fixture = "pose", aircraft = aircraft_id, setup = "no_session"}))
		flight.queue_free()
		await process_frame
		return
	flight.set_process(false)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.input_enabled = false
	var previous: PackedFloat64Array = _pose_state(-5.0)
	var state: PackedFloat64Array = _pose_state(0.4)
	session.sim.previous = previous.duplicate()
	session.sim.state = state.duplicate()
	session.sim.tick = 7
	session.sim.set_paused(false)
	_emit_pre_state("pose", aircraft_id, session, previous, state)
	session._physics_process(session.sim.dt())
	_emit_post_state("pose", aircraft_id, session, previous, state)
	flight.free()


func _accepted_tick_fixture(aircraft_id: String) -> void:
	var flight: Node = _make_main(aircraft_id, false)
	var session: Node = flight.get("session")
	if session == null:
		print(JSON.stringify({fixture = "accepted_tick", aircraft = aircraft_id, setup = "no_session"}))
		flight.queue_free()
		await process_frame
		return
	session.input_enabled = false
	var first_tick: int = session.sim.tick
	var frames := 0
	while session.sim.tick < first_tick + 100 and frames < 500:
		await physics_frame
		frames += 1
	session.set_physics_process(false)
	var state: PackedFloat64Array = _place_hull_contact(session)
	var previous: PackedFloat64Array = _tick_before(state)
	# A real Simulation.step invokes the Glow stage-coupled contact callback. Start at the clear
	# previous endpoint and let the pinned RK4/contact path produce its accepted endpoint.
	session.sim.state = previous.duplicate()
	session.sim.previous = previous.duplicate()
	session.sim.set_paused(false)
	session.sim.step()
	var result: Dictionary = {
		fixture = "accepted_tick",
		aircraft = aircraft_id,
		sim_tick = session.sim.tick,
		sim_fault = session.sim.fault_reason,
		crash_present = not session.crash.is_empty(),
		crash_why = str(session.crash.get("why", "")),
		impact_trigger = str(session.crash.impact.trigger) if not session.crash.is_empty() else "",
		impact_point_index = int(session.crash.impact.point_index) if not session.crash.is_empty() else -1,
		impact_soft_rule = str(session.crash.impact.soft_rule) if not session.crash.is_empty() else "",
		impact_crossing_available = session.crash.impact.crossing.available if not session.crash.is_empty() and session.crash.impact.crossing != null else false,
		endpoint_position_ned_m = _slice3(session.sim.state, RB.POS),
		endpoint_velocity_body_mps = _slice3(session.sim.state, RB.VEL),
		endpoint_hull_terminal = _terminal_report(session, previous, session.sim.state),
		endpoint_gear_compressions_m = session.gear_compressions(session.sim.state),
	}
	print(JSON.stringify(result))
	flight.queue_free()
	await process_frame
	await process_frame


func _emit_pre_state(fixture: String, aircraft_id: String, session: Node,
		previous: PackedFloat64Array, state: PackedFloat64Array) -> void:
	var gear: Dictionary = session.current_landing_gear()
	var surfaces: PackedFloat64Array = session.ground_surfaces if session.wheel_count() > 0 else PackedFloat64Array()
	var compressions: PackedFloat64Array = Ground.compressions(state, gear, surfaces, session._lake)
	var contacts: Array = []
	for index in compressions.size():
		var contact: Dictionary = gear.contacts[index]
		contacts.append({name = contact.name, compression_m = compressions[index],
			travel_limit_m = contact.max_compression, position_body_m = contact.position})
	var terminal: Dictionary = _terminal_report(session, previous, state)
	print(JSON.stringify({
		fixture = fixture,
		aircraft = aircraft_id,
		soft_hull_contacts = session.soft_hull_contacts,
		flight_ready = session._flight_ready(),
		state_tick = session.sim.tick,
		dt_s = session.sim.dt(),
		previous_pos_ned_m = _slice3(previous, RB.POS),
		state_pos_ned_m = _slice3(state, RB.POS),
		previous_attitude_wxyz = previous.slice(RB.ATT, RB.ATT + 4),
		state_attitude_wxyz = state.slice(RB.ATT, RB.ATT + 4),
		state_velocity_body_mps = _slice3(state, RB.VEL),
		state_rate_body_rad_s = _slice3(state, RB.RATE),
		hull_point_count = int(session.aircraft.model.crash_hull.size() / 3),
		hull_prepared = not session._hull_contact.is_empty(),
		terminal_result = terminal,
		touches_ground = session.touches_ground(state),
		gear_collapsed = session.gear_collapsed(state),
		gear_contact_rows = contacts,
	}))


func _emit_post_state(fixture: String, aircraft_id: String, session: Node,
		previous: PackedFloat64Array, injected_state: PackedFloat64Array) -> void:
	var crash: Dictionary = session.crash
	var impact: Variant = crash.get("impact") if not crash.is_empty() else null
	var post_state: PackedFloat64Array = session.sim.state
	var post_compressions: PackedFloat64Array = session.gear_compressions(post_state)
	var contact_rows: Array = []
	var gear: Dictionary = session.current_landing_gear()
	for index in post_compressions.size():
		var contact: Dictionary = gear.contacts[index]
		contact_rows.append({name = contact.name, compression_m = post_compressions[index],
			travel_limit_m = contact.max_compression})
	var hull_after: Dictionary = _terminal_report(session, previous, injected_state)
	var impact_trigger := ""
	var impact_component := ""
	var impact_point_index := -1
	var impact_has_compression := false
	var impact_compression_m := 0.0
	var impact_travel_limit_m := 0.0
	var impact_soft_rule := ""
	var impact_crossing_available := false
	var impact_crossing_reason := ""
	if impact != null:
		impact_trigger = impact.trigger
		impact_component = impact.component_name
		impact_point_index = impact.point_index
		impact_has_compression = impact.has_compression
		impact_compression_m = impact.compression_m
		impact_travel_limit_m = impact.travel_limit_m
		impact_soft_rule = impact.soft_rule
		if impact.crossing != null:
			impact_crossing_available = impact.crossing.available
			impact_crossing_reason = impact.crossing.reason
	var result: Dictionary = {
		fixture = fixture,
		aircraft = aircraft_id,
		crash_present = not crash.is_empty(),
		crash_why = str(crash.get("why", "")),
		impact_trigger = impact_trigger,
		impact_component = impact_component,
		impact_point_index = impact_point_index,
		impact_has_compression = impact_has_compression,
		impact_compression_m = impact_compression_m,
		impact_travel_limit_m = impact_travel_limit_m,
		impact_soft_rule = impact_soft_rule,
		impact_crossing_available = impact_crossing_available,
		impact_crossing_reason = impact_crossing_reason,
		post_tick = session.sim.tick,
		post_paused = session.sim.paused,
		post_state_equals_injected_state = post_state == injected_state,
		post_position_ned_m = _slice3(post_state, RB.POS),
		post_velocity_body_mps = _slice3(post_state, RB.VEL),
		post_gear_contacts = contact_rows,
		injected_hull_terminal = hull_after,
	}
	print(JSON.stringify(result))


func _place_hull_contact(session: Node) -> PackedFloat64Array:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var attitude: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest_down := -INF
	for index in range(0, hull.size(), 3):
		var point: PackedFloat64Array = PackedFloat64Array([hull[index], hull[index + 1], hull[index + 2]])
		var world_point: PackedFloat64Array = M.q_rotate(attitude, point)
		deepest_down = maxf(deepest_down, world_point[2])
	state[RB.POS + 2] = -deepest_down + 0.001
	var velocity_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), PackedFloat64Array([0.0, 0.0, 20.0]))
	for axis in 3:
		state[RB.VEL + axis] = velocity_body[axis]
		state[RB.RATE + axis] = 0.0
	return state


func _tick_before(state: PackedFloat64Array) -> PackedFloat64Array:
	var before: PackedFloat64Array = state.duplicate()
	before[RB.POS + 2] -= 0.01
	return before


func _pose_state(down: float) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, -15.0, down), M.v3(8.0, 0.0, 3.0), M.q_from_euler(0.4, 0.3, 0.6), M.v3(0.2, 0.3, 0.4))


func _terminal_report(session: Node, previous: PackedFloat64Array, state: PackedFloat64Array) -> Dictionary:
	if session.glow_is_active():
		var sample: Callable = session._contact_mass_sampler(session.sim.continuous, session.sim.continuous)
		if not sample.is_valid():
			return {ok = false, reason = "invalid_contact_mass_sampler"}
		var properties: Dictionary = sample.call(0.0)
		return HullContact.terminal_at_properties(previous, state, session._hull_contact, properties)
	return HullContact.terminal(previous, state, session._hull_contact)


func _slice3(state: PackedFloat64Array, at: int) -> PackedFloat64Array:
	return state.slice(at, at + 3)
