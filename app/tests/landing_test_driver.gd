# E3c1a flight measurement harness. Test support only; no presentation/input dependencies.
extends RefCounted
const Pilot = preload("res://sim/landing_maneuver.gd")
const M = preload("res://physics/math3d.gd")
const Trim = preload("res://physics/trim.gd")
const Ground = preload("res://physics/ground_contact.gd")
const Session = preload("res://sim/flight_session.gd")

const DURATION: float = 46.0
const EDGE_MARGIN: float = 0.5 # m; every wheel after first contact
const STOP_SPEED: float = 0.02 # m/s, all 3 translational axes
const STOP_DWELL: float = 2.0 # s, all wheels compressed and anchored, |omega| < 0.01 rad/s


# World point position and velocity; velocity includes rotation about the CG.
static func contact_state(s: PackedFloat64Array, r: PackedFloat64Array) -> PackedFloat64Array:
	var attitude: PackedFloat64Array = M.quat(s[6], s[7], s[8], s[9])
	var offset: PackedFloat64Array = M.q_rotate(attitude, r)
	var local_velocity: PackedFloat64Array = M.add(M.v3(s[3], s[4], s[5]), M.cross(M.v3(s[10], s[11], s[12]), r))
	var velocity: PackedFloat64Array = M.q_rotate(attitude, local_velocity)
	return PackedFloat64Array([s[0] + offset[0], s[1] + offset[1], s[2] + offset[2], velocity[0], velocity[1], velocity[2]])


static func fly(session: Node, field: Dictionary, eastbound: bool, cross_offset: float = 0.0,
		bank: float = 0.0, start_shift: float = 0.0, duration: float = DURATION, start_altitude: float = Pilot.START_ALTITUDE) -> Dictionary:
	var runway: Dictionary = {}
	for surface: Dictionary in field.surfaces:
		if surface.id == field.runway:
			runway = surface
	if runway.is_empty() or not session.set_field(field):
		return {error = "runway/field unavailable"}
	var trimmed: Dictionary = session.trim_at(Pilot.APPROACH_SPEED)
	if not trimmed.ok:
		return {error = "approach trim failed"}
	var direction: float = 1.0 if eastbound else -1.0
	var half_length: float = runway.length_east_west / 2.0
	var half_width: float = runway.width_north_south / 2.0
	session.start.state = Trim.state_for(Pilot.APPROACH_SPEED, trimmed.alpha, 0.0, direction * PI / 2.0,
		M.v3(runway.center_north + cross_offset, runway.center_east - direction * (half_length + Pilot.START_BEFORE_END - start_shift), -start_altitude), trimmed.beta)
	var attitude: PackedFloat64Array = M.q_from_euler(direction * PI / 2.0, trimmed.alpha, bank)
	for i: int in 4:
		session.start.state[6 + i] = attitude[i]
	session.input_enabled = false
	session.reset()
	var pilot: RefCounted = Pilot.new(runway.center_north, eastbound, trimmed.throttle, trimmed.pitch_command)
	var gear: Dictionary = session.aircraft.model.landing_gear
	var dt: float = session.sim.dt()
	var count: int = roundi(duration / dt)
	var out: Dictionary = {error = "", completed = false, tick_hz = Engine.physics_ticks_per_second,
		eastbound = eastbound, cross_offset_m = cross_offset, bank_rad = bank, contacts = [],
		max_contact_sink_mps = 0.0, max_compression_m = 0.0, min_runway_margin_m = INF,
		max_cross_track_m = 0.0, stop_time_s = -1.0, stop_east_m = 0.0,
		touchdown_time_s = -1.0, touchdown_east_m = 0.0, touchdown_speed_mps = 0.0,
		max_stop_drift_m = 0.0, stopped_then_moved = false, airborne_after_touch_s = 0.0, dwell_s = 0.0, samples = []}
	var touched: bool = false
	var stopped_position: PackedFloat64Array = PackedFloat64Array()
	var dwell: float = 0.0
	# Initial boundary, then each newly integrated boundary, runs the actual crash detector.
	session._physics_process(dt)
	for tick: int in count:
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty() or session.sim.paused:
			out.error = "crash/fault/pause: %s %s" % [session.crash, session.sim.fault_reason]
			break
		var before: PackedFloat64Array = session.sim.state
		var comp: PackedFloat64Array = session.gear_compressions(before)
		var clearance: float = -comp[0]
		for c: float in comp:
			clearance = minf(clearance, -c)
		session.commands = pilot.commands(before, clearance)
		session.sim.inputs = session._inputs()
		session.sim.step()
		session._physics_process(dt)
		var after: PackedFloat64Array = session.sim.state
		var all_down: bool = true
		var any_down: bool = false
		for i: int in gear.contacts.size():
			var previous_point: PackedFloat64Array = contact_state(before, gear.contacts[i].position)
			var point: PackedFloat64Array = contact_state(after, gear.contacts[i].position)
			all_down = all_down and point[2] > 0.0
			any_down = any_down or point[2] > 0.0
			out.max_compression_m = maxf(out.max_compression_m, point[2])
			if previous_point[2] <= 0.0 and point[2] > 0.0:
				# Maximum endpoint sink over the crossing tick (not an interior extremum bound).
				var sink: float = maxf(previous_point[5], point[5])
				out.contacts.append({wheel = i, time_s = session.sim.time(), east_m = point[1], north_m = point[0],
					sink_mps = sink, sink_before_mps = previous_point[5], sink_after_mps = point[5]})
				out.max_contact_sink_mps = maxf(out.max_contact_sink_mps, sink)
				if not touched:
					out.touchdown_time_s = session.sim.time()
					out.touchdown_east_m = point[1]
					out.touchdown_speed_mps = M.norm(M.v3(before[3], before[4], before[5]))
					touched = true
		# Check every wheel, including unloaded wheels, for the entire post-touch interval.
		if touched:
			for contact: Dictionary in gear.contacts:
				var point: PackedFloat64Array = contact_state(after, contact.position)
				var margin: float = minf(half_length - absf(point[1] - runway.center_east), half_width - absf(point[0] - runway.center_north))
				out.min_runway_margin_m = minf(out.min_runway_margin_m, margin)
				out.max_cross_track_m = maxf(out.max_cross_track_m, absf(point[0] - runway.center_north))
			if not any_down:
				out.airborne_after_touch_s += dt
		var anchored: bool = true
		for i: int in gear.contacts.size():
			anchored = anchored and session.sim.aux[Session.AUX_ANCHORS + i * Ground.ANCHOR_STRIDE + 2] == 1.0
		var speed: float = M.norm(M.v3(after[3], after[4], after[5]))
		var angular_speed: float = M.norm(M.v3(after[10], after[11], after[12]))
		if touched and all_down and anchored and speed < STOP_SPEED and angular_speed < 0.01:
			dwell += dt
		else:
			dwell = 0.0
			if out.stop_time_s >= 0.0:
				out.stopped_then_moved = true
		if dwell >= STOP_DWELL and out.stop_time_s < 0.0:
			out.stop_time_s = session.sim.time()
			out.stop_east_m = after[1]
			stopped_position = M.v3(after[0], after[1], after[2])
		if not stopped_position.is_empty():
			out.max_stop_drift_m = maxf(out.max_stop_drift_m, M.norm(M.sub(M.v3(after[0], after[1], after[2]), stopped_position)))
		if tick % maxi(1, roundi(0.1 / dt)) == 0:
			out.samples.append([session.sim.time(), after[0], after[1], -after[2], speed, pilot.phase])
	out.completed = session.sim.tick == count and session.sim.fault_reason.is_empty() and session.crash.is_empty()
	if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
		out.error = "crash/fault: %s %s" % [session.crash, session.sim.fault_reason]
	out.dwell_s = dwell
	out.final_state = Array(session.sim.state)
	out.engine_running = session.engine_running
	out.final_throttle = session.sim.inputs[3]
	out.final_rpm = session.sim.aux[Session.AUX_RPM]
	out.idle_rpm = session.aircraft.model.propulsion.idle_rpm
	out.wash_enabled = not session.aircraft.model.propulsion.get("slipstream", {}).is_empty()
	# No-contact failure must serialize as finite data, never JSON null from Infinity.
	if not touched:
		out.min_runway_margin_m = -1e30
	return out
