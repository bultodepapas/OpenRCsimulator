# E3c2a offline whole-flight measurements. No force/data changes or airborne reset.
extends RefCounted
const M = preload("res://physics/math3d.gd")
const GroundStart = preload("res://physics/ground_start.gd")
const Ground = preload("res://physics/ground_contact.gd")
const Session = preload("res://sim/flight_session.gd")
const Recorder = preload("res://sim/recorder.gd")
const Contact = preload("res://tests/landing_test_driver.gd")

const IDLE_HOLD: float = 1.0
const MAX_DURATION: float = 240.0
const STOP_DWELL: float = 2.0
const POST_STOP_HOLD: float = 3.0


static func fly(session: Node, field: Dictionary, pilot_script: Script, eastbound: bool,
		trace_path: String = "", duration: float = MAX_DURATION) -> Dictionary:
	var runway: Dictionary = {}
	for surface: Dictionary in field.surfaces:
		if surface.id == field.runway:
			runway = surface
	if runway.is_empty() or not session.set_field(field):
		return {error = "runway unavailable", completed = false}
	var cruise_trim: Dictionary = session.trim_at(15.0)
	var trimmed: Dictionary = session.trim_at(12.0)
	if not trimmed.ok or not cruise_trim.ok:
		return {error = "approach trim failed", completed = false}
	session.input_enabled = false
	var spot: Dictionary = GroundStart.threshold(field, eastbound)
	if not spot.ok or not session.reset_on_runway(spot.north, spot.east, spot.heading):
		return {error = "runway equilibrium failed", completed = false}
	var pilot_parameters: Dictionary = trimmed.duplicate(true)
	pilot_parameters.cruise_throttle = cruise_trim.throttle
	var pilot: RefCounted = pilot_script.new(runway, eastbound, pilot_parameters)
	var dt: float = session.sim.dt()
	var gear: Dictionary = session.aircraft.model.landing_gear
	var out: Dictionary = {error = "", completed = false, hz = Engine.physics_ticks_per_second,
		eastbound = eastbound, runway_center_north = runway.center_north, runway_center_east = runway.center_east, phases = [], contacts = [], samples = [], tick_count = 0,
		liftoff_time_s = -1.0, liftoff_east_m = 0.0, touchdown_time_s = -1.0,
		touchdown_east_m = 0.0, max_contact_sink_mps = 0.0, max_compression_m = 0.0,
		departure_margin_m = 1e30, landing_margin_m = 1e30, idle_drift_m = 0.0,
		stop_time_s = -1.0, stop_east_m = 0.0, stop_dwell_s = 0.0, max_stop_drift_m = 0.0,
		stopped_then_moved = false, turn_rad = 0.0, signed_area_m2 = 0.0,
		max_cross_track_m = 0.0, max_altitude_m = 0.0,
		max_speed_mps = 0.0, commands_finite_bounded = true, continuity_ok = true,
		wash_enabled = not session.aircraft.model.propulsion.get("slipstream", {}).is_empty()}
	var recorder: RefCounted = null
	if not trace_path.is_empty():
		recorder = Recorder.new(session.sim)
		var meta: Dictionary = session.trace_meta()
		meta.scenario = "E3c2a continuous experimental circuit; parked start; calm air; wash off; estimated test pilot"
		recorder.start(meta)
	var initial: PackedFloat64Array = session.sim.state.duplicate()
	var last_yaw: float = M.q_to_euler(initial.slice(6, 10))[0]
	var airborne: bool = false
	var touchdown: bool = false
	var clear_dwell: float = 0.0
	var stop_ticks: int = 0
	var stop_tick: int = -1
	var required_stop_ticks: int = ceili(STOP_DWELL / dt)
	var required_hold_ticks: int = ceili(POST_STOP_HOLD / dt)
	var stop_position: PackedFloat64Array = PackedFloat64Array()
	var phase_before: String = ""
	var sample_interval: int = maxi(1, roundi(0.25 / dt))
	session._physics_process(dt)
	for index: int in roundi(duration / dt):
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty() or session.sim.paused:
			out.error = "crash/fault/pause: %s %s" % [session.crash, session.sim.fault_reason]
			break
		var before: PackedFloat64Array = session.sim.state.duplicate()
		var comp: PackedFloat64Array = session.gear_compressions(before)
		var clearance: float = -comp[0]
		for compression: float in comp:
			clearance = minf(clearance, -compression)
		var time: float = session.sim.time()
		var phase: String = "idle" if time < IDLE_HOLD else str(pilot.phase)
		var command: Dictionary = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		if time >= IDLE_HOLD:
			command = pilot.commands(before, clearance, time - IDLE_HOLD)
			phase = str(pilot.phase)
		for key: String in ["roll", "pitch", "yaw", "throttle"]:
			var value: float = float(command.get(key, NAN))
			out.commands_finite_bounded = out.commands_finite_bounded and is_finite(value) and value <= 1.0 and value >= (0.0 if key == "throttle" else -1.0)
		if not out.commands_finite_bounded:
			out.error = "invalid pilot command"
			break
		if phase != phase_before:
			var euler: PackedFloat64Array = M.q_to_euler(before.slice(6, 10))
			var velocity: PackedFloat64Array = M.q_rotate(before.slice(6, 10), before.slice(3, 6))
			out.phases.append({phase = phase, time_s = time, north_m = before[0], east_m = before[1], altitude_m = -before[2], speed_mps = M.norm(before.slice(3, 6)), yaw_rad = euler[0], bank_rad = euler[2], sink_mps = velocity[2]})
			phase_before = phase
		session.commands = command
		session.sim.inputs = session._inputs()
		out.continuity_ok = out.continuity_ok and session.sim.tick == index and before == session.sim.state
		session.sim.step()
		session._physics_process(dt)
		out.continuity_ok = out.continuity_ok and session.sim.tick == index + 1 and session.sim.previous == before
		var after: PackedFloat64Array = session.sim.state
		var speed: float = M.norm(after.slice(3, 6))
		var all_down: bool = true
		var any_down: bool = false
		var margin: float = 1e30
		var anchored: bool = true
		for wheel: int in gear.contacts.size():
			var previous_point: PackedFloat64Array = Contact.contact_state(before, gear.contacts[wheel].position)
			var point: PackedFloat64Array = Contact.contact_state(after, gear.contacts[wheel].position)
			all_down = all_down and point[2] > 0.0
			any_down = any_down or point[2] > 0.0
			anchored = anchored and session.sim.aux[Session.AUX_ANCHORS + wheel * Ground.ANCHOR_STRIDE + 2] == 1.0
			margin = minf(margin, minf(runway.length_east_west / 2.0 - absf(point[1] - runway.center_east), runway.width_north_south / 2.0 - absf(point[0] - runway.center_north)))
			out.max_compression_m = maxf(out.max_compression_m, point[2])
			# Rigid undeformed wheel-reference velocity; compression-rate tyre velocity is unavailable.
			if airborne and previous_point[2] <= 0.0 and point[2] > 0.0:
				var sink: float = maxf(previous_point[5], point[5])
				out.contacts.append({wheel = wheel, time_s = session.sim.time(), north_m = point[0], east_m = point[1], sink_mps = sink})
				out.max_contact_sink_mps = maxf(out.max_contact_sink_mps, sink)
				if not touchdown:
					touchdown = true
					out.touchdown_time_s = session.sim.time()
					out.touchdown_east_m = point[1]
		if not airborne:
			out.departure_margin_m = minf(out.departure_margin_m, margin)
			clear_dwell = clear_dwell + dt if not any_down else 0.0
			if clear_dwell >= 0.1:
				airborne = true
				out.liftoff_time_s = session.sim.time() - clear_dwell
				out.liftoff_east_m = after[1]
		if touchdown:
			out.landing_margin_m = minf(out.landing_margin_m, margin)
		var yaw: float = M.q_to_euler(after.slice(6, 10))[0]
		out.turn_rad += wrapf(yaw - last_yaw, -PI, PI)
		last_yaw = yaw
		out.signed_area_m2 += 0.5 * ((before[1] - initial[1]) * (after[0] - initial[0]) - (after[1] - initial[1]) * (before[0] - initial[0]))
		out.max_cross_track_m = maxf(out.max_cross_track_m, absf(after[0] - runway.center_north))
		out.max_altitude_m = maxf(out.max_altitude_m, -after[2])
		out.max_speed_mps = maxf(out.max_speed_mps, speed)
		if time < IDLE_HOLD:
			out.idle_drift_m = maxf(out.idle_drift_m, M.norm(M.sub(initial.slice(0, 3), after.slice(0, 3))))
		if touchdown and all_down and anchored and speed < 0.02 and M.norm(after.slice(10, 13)) < 0.01:
			stop_ticks += 1
		else:
			stop_ticks = 0
			if out.stop_time_s >= 0.0:
				out.stopped_then_moved = true
		if stop_ticks >= required_stop_ticks and stop_tick < 0:
			stop_tick = session.sim.tick
			out.stop_time_s = session.sim.time()
			out.stop_east_m = after[1]
			stop_position = after.slice(0, 3)
		if not stop_position.is_empty():
			out.max_stop_drift_m = maxf(out.max_stop_drift_m, M.norm(M.sub(after.slice(0, 3), stop_position)))
		if index % sample_interval == 0:
			out.samples.append([session.sim.time(), after[0], after[1], -after[2], speed, phase])
		if stop_tick >= 0 and session.sim.tick - stop_tick >= required_hold_ticks:
			out.completed = true
			break
	out.stop_dwell_s = stop_ticks * dt
	out.tick_count = session.sim.tick
	out.final_state = Array(session.sim.state)
	out.final_rpm = session.sim.aux[Session.AUX_RPM]
	out.idle_rpm = session.aircraft.model.propulsion.idle_rpm
	out.engine_running = session.engine_running
	out.final_throttle = session.sim.inputs[3]
	out.duration_s = session.sim.time()
	out.crash = not session.crash.is_empty()
	out.fault = session.sim.fault_reason
	if out.crash or not out.fault.is_empty():
		out.completed = false
		out.error = "crash/fault: %s %s" % [session.crash, out.fault]
	if recorder != null:
		out.trace_rows = recorder.trace.row_count()
		out.trace_continuous = recorder.trace.is_continuous()
		out.trace_saved = recorder.stop(trace_path) == OK
		recorder.detach()
	return out
