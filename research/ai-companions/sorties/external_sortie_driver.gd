## AFC-09: research-only whole sortie using the production FlightSession external-driver seam.
## The accepted aircraft/physics are untouched; pilot demands remain outside the solver.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const LandingContact := preload("res://tests/landing_test_driver.gd")

const IDLE_HOLD_S := 1.0
const LANDING_DWELL_S := 2.0
const ROLLOUT_MAX_ANGULAR_SPEED_RAD_S := 0.01
const ROLLOUT_MAX_DRIFT_M := 0.002
const RUNWAY_CLEARANCE_M := 2.0 # research-only lateral margin beyond the loaded runway edge
const VACATE_MAX_S := 45.0
const MAX_DURATION_S := 240.0


static func run(eastbound: bool, log_path: String, duration_s: float = MAX_DURATION_S,
		pilot_override_path: String = "", weather_override: Dictionary = {},
		weather_profile_id: String = "calm", record_flight_log: bool = true) -> Dictionary:
	if not is_finite(duration_s) or duration_s <= IDLE_HOLD_S or duration_s > MAX_DURATION_S:
		return {ok = false, error = "duration must be finite and in (1, 240] seconds"}
	var loaded: Dictionary = FieldLoader.load_from()
	if not loaded.ok:
		return {ok = false, error = "field load refused: " + "; ".join(loaded.errors)}
	var field: Dictionary = loaded.field
	var runway: Dictionary = _runway_for(field)
	if runway.is_empty():
		return {ok = false, error = "loaded field has no runway surface"}
	var lake_loaded: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not lake_loaded.ok:
		return {ok = false, error = "lake context load refused: " + "; ".join(lake_loaded.errors)}
	var collision: Dictionary = CollisionSetup.build(field)
	if not collision.ok:
		return {ok = false, error = "production scenery collision build refused: " + "; ".join(collision.errors)}
	var collision_world: Dictionary = collision.get("world", {})
	var collision_proxies: Variant = collision_world.get("proxies", null)
	if str(collision_world.get("format", "")) != "openrc-collision-world v1" \
			or str(collision_world.get("identity", "")).is_empty() \
			or typeof(collision_proxies) != TYPE_ARRAY or (collision_proxies as Array).is_empty():
		return {ok = false, error = "production collision setup did not provide a qualified non-empty static world"}
	var session: Node = FlightSession.new()
	session.setup()
	session.input_enabled = false
	session.crash_auto_restart = false
	# Match the interactive fixed-wing session's hull/contact policy. The kernel's accepted wake path remains enabled.
	session.soft_hull_contacts = true
	if not session.is_flyable():
		var reason := str(session.pause_reason)
		session.free()
		return {ok = false, error = "accepted Stik session setup refused: " + reason}
	if not session.set_field(field):
		var reason := str(session.surface_error)
		session.free()
		return {ok = false, error = "field surface setup refused: " + reason}
	if not session.set_lake_context(lake_loaded.lake):
		session.free()
		return {ok = false, error = "production normalized lake context was refused by FlightSession"}
	if not session.set_collision_world(collision_world):
		session.free()
		return {ok = false, error = "production static collision world refused by FlightSession"}
	var requested_weather: Dictionary = WindConfig.defaults() if weather_override.is_empty() else weather_override.duplicate(true)
	var checked_weather: Dictionary = WindConfig.validate(requested_weather)
	if not checked_weather.get("ok", false):
		var reason := "; ".join(checked_weather.get("errors", PackedStringArray()))
		session.free()
		return {ok = false, error = "weather configuration refused before the sortie: " + reason}
	var selected_weather: Dictionary = checked_weather.config
	if not session.setup_weather(selected_weather):
		var reason := str(session.weather_error)
		session.free()
		return {ok = false, error = "weather configuration refused: " + reason}
	var spot: Dictionary = GroundStart.threshold(field, eastbound)
	if not spot.ok or not session.reset_on_runway(spot.north, spot.east, spot.heading):
		var reason := str(session.start_error)
		session.free()
		return {ok = false, error = "physical runway start refused: " + reason}
	if not session.configure_external_driver():
		session.free()
		return {ok = false, error = "production external-driver configuration refused after ground start"}

	var approach_trim: Dictionary = session.trim_at(12.0)
	var cruise_trim: Dictionary = session.trim_at(15.0)
	if not approach_trim.get("ok", false) or not cruise_trim.get("ok", false):
		session.free()
		return {ok = false, error = "pilot trim reference refused"}
	var pilot_parameters: Dictionary = approach_trim.duplicate(true)
	pilot_parameters.cruise_throttle = float(cruise_trim.throttle)
	var repository_root: String = ProjectSettings.globalize_path("res://..").simplify_path()
	var pilot_path: String = pilot_override_path
	if pilot_path.is_empty():
		pilot_path = repository_root.path_join("research/landing/e3c2a/circuit_pilot.gd")
	var pilot_script: Script = load(pilot_path)
	if pilot_script == null:
		session.free()
		return {ok = false, error = "selected circuit pilot is unavailable: " + pilot_path}
	var pilot: RefCounted = pilot_script.new(runway, eastbound, pilot_parameters)
	var logger: Variant = null
	if record_flight_log:
		if log_path.is_empty():
			session.free()
			return {ok = false, error = "ORFL recording requested without an output path"}
		logger = FlightLog.new(session)
		var log_error: Error = logger.start(log_path)
		if log_error != OK:
			var reason := str(logger.failure)
			session.free()
			return {ok = false, error = "ORFL start failed: " + reason}
	elif not log_path.is_empty():
		session.free()
		return {ok = false, error = "no-log sortie must not receive an ORFL output path"}

	var dt: float = session.sim.dt()
	var landing_ticks: int = ceili(LANDING_DWELL_S / dt)
	var runway_half_width: float = float(runway.width_north_south) * 0.5
	var runway_north_edge: float = float(runway.center_north) + runway_half_width
	var vacate_target_north: float = runway_north_edge + RUNWAY_CLEARANCE_M
	var initial: PackedFloat64Array = session.sim.state.duplicate()
	var initial_yaw: float = M.q_to_euler(initial.slice(6, 10))[0]
	var initial_checkpoint: Dictionary = session.checkpoint()
	var launch_metadata: Dictionary = session._launch_metadata.duplicate(true)
	var launch_choice: String = str(launch_metadata.get("launch_choice", ""))
	var launch_kind: String = str(launch_metadata.get("launch_kind", ""))
	var launch_field_id: String = str(launch_metadata.get("launch_field_id", ""))
	var out: Dictionary = {
		format = "openrc-ai-sortie v1",
		ok = true,
		complete = false,
		error = "",
		phase_history = [],
		contact_event_history = [],
		wheel_contacts = [],
		samples = [],
		eastbound = eastbound,
		aircraft_id = str(session.aircraft.model.get("id", "")),
		aircraft_input_sha256 = str(session.aircraft.get("input_identity", {}).get("sha256", "")),
		solver_sha256 = FlightLog.solver_identity(),
		wind = session.weather_configuration(),
		weather_profile_id = weather_profile_id,
		weather_config_sha256 = FlightLog.sha256(var_to_bytes(session.weather_configuration())).hex_encode(),
		flight_log_requested = record_flight_log,
		field_id = str(field.get("id", "")),
		field_source_path = FieldLoader.DEFAULT_PATH,
		field_source_sha256 = FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
		runway_center_north_m = float(runway.center_north),
		runway_center_east_m = float(runway.center_east),
		runway_length_east_west_m = float(runway.length_east_west),
		runway_width_north_south_m = float(runway.width_north_south),
		field_collision_sha256 = str(collision_world.get("identity", "")),
		collision_proxy_count = (collision_proxies as Array).size(),
		collision_setup_source_sha256 = FileAccess.get_sha256("res://scenery/collision_setup.gd"),
		collision_world_source_sha256 = FileAccess.get_sha256("res://scenery/collision_world.gd"),
		static_scenery_collision = "production CollisionSetup-built default scenery and field lights",
		lake_source_path = LakeLoader.DEFAULT_PATH,
		lake_source_sha256 = FileAccess.get_sha256(LakeLoader.DEFAULT_PATH),
		lake_identity = str(lake_loaded.lake.get("identity", "")),
		flight_session_source_sha256 = FileAccess.get_sha256("res://sim/flight_session.gd"),
		ground_start_source_sha256 = FileAccess.get_sha256("res://physics/ground_start.gd"),
		landing_maneuver_source_sha256 = FileAccess.get_sha256("res://sim/landing_maneuver.gd"),
		pilot_path = pilot_script.resource_path,
		pilot_sha256 = FileAccess.get_sha256(pilot_script.resource_path),
		physics_hz = Engine.physics_ticks_per_second,
		dt_s = dt,
		selected_start_choice = str(session.start_choice),
		launch_choice = launch_choice,
		launch_kind = launch_kind,
		launch_field_id = launch_field_id,
		physical_runway_start_accepted = launch_choice == "runway" and launch_kind == "runway_threshold"
			and launch_field_id == str(field.get("id", "")),
		physical_runway_start_position = {north_m = float(spot.north), east_m = float(spot.east), heading_rad = float(spot.heading)},
		start_error = str(session.start_error),
		external_driver = session.external_driver_enabled,
		initial_checkpoint_sha256 = FlightLog.sha256(var_to_bytes(initial_checkpoint)).hex_encode(),
		initial_state = Array(initial),
		wake_path = "current accepted FlightSession/Simulation wake and turbulence state; no wake-disable override",
		propulsion_slipstream_installation = session.aircraft.model.get("propulsion", {}).get("slipstream", {}).duplicate(true),
		lift_off_time_s = -1.0,
		touchdown_time_s = -1.0,
		touchdown_max_sink_mps = 0.0,
		landing_min_runway_margin_m = INF,
		landing_min_gear_runway_margin_m = INF,
		landing_min_hull_runway_margin_m = INF,
		landing_footprint_model = "all three landing-gear contacts plus every accepted crash_hull point, projected into the loaded runway rectangle",
		hull_footprint_point_count = session.aircraft.model.crash_hull.size() / 3,
		departure_min_runway_margin_m = INF,
		turn_rad = 0.0,
		signed_area_m2 = 0.0,
		max_cross_track_m = 0.0,
		max_altitude_m = 0.0,
		landing_dwell_s = 0.0,
		landing_dwell_complete = false,
		landing_supported_all_wheels = false,
		runway_vacated = false,
		vacate_attempted = false,
		vacate_time_s = -1.0,
		vacate_target_north_m = vacate_target_north,
		vacate_timeout = false,
		max_gear_compression_m = 0.0,
		max_speed_mps = 0.0,
		terminal_damage = false,
		sim_fault = "",
		crash = {},
		prop_strike = {},
		tick_count = 0,
		duration_s = 0.0,
		log_path = log_path,
	}
	var phase_before := ""
	var airborne := false
	var clear_ticks := 0
	var touchdown := false
	var stable_ticks := 0
	var landing_hold_origin := PackedFloat64Array()
	var landing_hold_max_drift_m := 0.0
	var vacate_started := false
	var vacate_start_time := -1.0
	var vacate_clear_ticks := 0
	var last_yaw: float = initial_yaw
	var sample_interval: int = maxi(1, roundi(0.25 / dt))
	var max_ticks: int = roundi(duration_s / dt)
	var wheel_contacts: Array = session.aircraft.model.landing_gear.contacts

	for index in max_ticks:
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty() or session.sim.paused:
			out.error = "session crash/fault/pause: %s %s" % [session.crash, session.sim.fault_reason]
			break
		var before: PackedFloat64Array = session.sim.state.duplicate()
		var time_s: float = session.sim.time()
		var command: Dictionary
		var phase: String
		if vacate_started:
			phase = "vacate_taxi"
			command = _vacate_commands(before, vacate_target_north, time_s - vacate_start_time)
		elif time_s < IDLE_HOLD_S:
			phase = "idle"
			command = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		else:
			var compression: PackedFloat64Array = session.gear_compressions(before)
			var clearance: float = -compression[0]
			for value: float in compression:
				clearance = minf(clearance, -value)
			var air_data: Dictionary = session.air_data(before, time_s)
			var wind_ned: PackedFloat64Array = session.wind_at(time_s)
			# Keep the production E3c2a three-argument driver compatible. Research pilots can
			# opt into accepted read-only air/wind data through this explicit extension seam.
			if pilot.has_method("commands_with_weather"):
				command = pilot.commands_with_weather(before, clearance, time_s - IDLE_HOLD_S, air_data, wind_ned)
			else:
				command = pilot.commands(before, clearance, time_s - IDLE_HOLD_S)
			phase = str(pilot.phase)
		for key: String in ["roll", "pitch", "yaw", "throttle"]:
			var value: float = float(command.get(key, NAN))
			if not is_finite(value) or value < (-1.0 if key != "throttle" else 0.0) or value > 1.0:
				out.error = "pilot emitted invalid %s command at tick %d" % [key, session.sim.tick]
				break
		if not str(out.error).is_empty():
			break
		if phase != phase_before:
			out.phase_history.append(_phase_event(session, before, phase, time_s))
			phase_before = phase
		var staged: Dictionary = session.prepare_external_tick(command)
		if not staged.get("ok", false):
			out.error = "external packet refused at tick %d: %s" % [session.sim.tick, "; ".join(staged.errors)]
			break
		var prior_tick: int = session.sim.tick
		if not session.step_external_tick() or session.sim.tick != prior_tick + 1:
			out.error = "production external tick was not accepted at tick %d" % prior_tick
			break

		var after: PackedFloat64Array = session.sim.state
		# Sample accepted contact outcomes only during unusual angular motion. This keeps the
		# observer bounded and avoids copying contact dictionaries on every normal flight tick.
		if M.norm(after.slice(10, 13)) > 1.0:
			var contacts: Dictionary = session.contact_events()
			var contact_events: Array = contacts.get("events", [])
			if not contact_events.is_empty():
				out.contact_event_history.append({tick = session.sim.tick,
					active_hull_ids = contacts.get("active_hull_ids", []).duplicate(),
					events = contact_events.duplicate(true)})
				if out.contact_event_history.size() > 64:
					out.contact_event_history.pop_front()
		var speed_mps: float = M.norm(after.slice(3, 6))
		var current_yaw: float = M.q_to_euler(after.slice(6, 10))[0]
		# Circuit heading evidence ends at first touchdown; the later taxi vacate is not another circuit turn.
		if not touchdown:
			out.turn_rad = float(out.turn_rad) + wrapf(current_yaw - last_yaw, -PI, PI)
			out.signed_area_m2 = float(out.signed_area_m2) + 0.5 * ((before[1] - initial[1]) * (after[0] - initial[0])
				- (after[1] - initial[1]) * (before[0] - initial[0]))
			out.max_cross_track_m = maxf(float(out.max_cross_track_m), absf(after[0] - float(runway.center_north)))
		last_yaw = current_yaw
		out.max_altitude_m = maxf(float(out.max_altitude_m), -after[2])
		out.max_speed_mps = maxf(float(out.max_speed_mps), speed_mps)
		var any_wheel_down := false
		var all_wheels_down := true
		var all_anchors := true
		var all_wheels_clear_north := true
		var gear_runway_margin_m := INF
		for wheel_index: int in wheel_contacts.size():
			var contact: Dictionary = wheel_contacts[wheel_index]
			var previous_point: PackedFloat64Array = LandingContact.contact_state(before, contact.position)
			var point: PackedFloat64Array = LandingContact.contact_state(after, contact.position)
			var down: bool = point[2] > 0.0
			any_wheel_down = any_wheel_down or down
			all_wheels_down = all_wheels_down and down
			all_wheels_clear_north = all_wheels_clear_north and point[0] > runway_north_edge + 0.5
			var anchor_index: int = FlightSession.AUX_ANCHORS + wheel_index * Ground.ANCHOR_STRIDE + 2
			all_anchors = all_anchors and anchor_index < session.sim.aux.size() and session.sim.aux[anchor_index] == 1.0
			var margin: float = _runway_margin_for_point(point, runway)
			gear_runway_margin_m = minf(gear_runway_margin_m, margin)
			out.max_gear_compression_m = maxf(float(out.max_gear_compression_m), point[2])
			if airborne and previous_point[2] <= 0.0 and point[2] > 0.0:
				var sink_mps: float = maxf(previous_point[5], point[5])
				out.wheel_contacts.append({wheel = wheel_index, tick = session.sim.tick, time_s = session.sim.time(),
					north_m = point[0], east_m = point[1], sink_mps = sink_mps, runway_margin_m = margin})
				out.touchdown_max_sink_mps = maxf(float(out.touchdown_max_sink_mps), sink_mps)
				if not touchdown:
					touchdown = true
					out.touchdown_time_s = session.sim.time()
		var hull_runway_margin_m := INF
		if touchdown:
			var hull: PackedFloat64Array = session.aircraft.model.crash_hull
			for hull_index in range(0, hull.size(), 3):
				var body_point: PackedFloat64Array = hull.slice(hull_index, hull_index + 3)
				var world_point: PackedFloat64Array = LandingContact.contact_state(after, body_point)
				hull_runway_margin_m = minf(hull_runway_margin_m, _runway_margin_for_point(world_point, runway))
		var runway_margin_m: float = minf(gear_runway_margin_m, hull_runway_margin_m)
		if touchdown and not vacate_started:
			out.landing_min_gear_runway_margin_m = minf(float(out.landing_min_gear_runway_margin_m), gear_runway_margin_m)
			out.landing_min_hull_runway_margin_m = minf(float(out.landing_min_hull_runway_margin_m), hull_runway_margin_m)
			out.landing_min_runway_margin_m = minf(float(out.landing_min_runway_margin_m), runway_margin_m)
		if not airborne:
			out.departure_min_runway_margin_m = minf(float(out.departure_min_runway_margin_m), runway_margin_m)
			clear_ticks = 0 if any_wheel_down else clear_ticks + 1
			if float(clear_ticks) * dt >= 0.1:
				airborne = true
				out.lift_off_time_s = session.sim.time() - float(clear_ticks) * dt
		var supported: bool = all_wheels_down and all_anchors
		var angular_speed: float = M.norm(after.slice(10, 13))
		var qualifies_rollout_hold: bool = touchdown and not vacate_started and supported \
			and speed_mps <= 0.5 and angular_speed < ROLLOUT_MAX_ANGULAR_SPEED_RAD_S and runway_margin_m >= 0.0
		if qualifies_rollout_hold:
			if stable_ticks == 0:
				landing_hold_origin = M.v3(after[0], after[1], after[2])
				landing_hold_max_drift_m = 0.0
			var hold_drift_m: float = M.norm(M.sub(M.v3(after[0], after[1], after[2]), landing_hold_origin))
			landing_hold_max_drift_m = maxf(landing_hold_max_drift_m, hold_drift_m)
			if hold_drift_m <= ROLLOUT_MAX_DRIFT_M:
				stable_ticks += 1
			else:
				stable_ticks = 0
				landing_hold_origin = PackedFloat64Array()
				landing_hold_max_drift_m = 0.0
		else:
			stable_ticks = 0
			landing_hold_origin = PackedFloat64Array()
			landing_hold_max_drift_m = 0.0
		if not bool(out.landing_dwell_complete):
			out.landing_dwell_s = float(stable_ticks) * dt
		out.landing_supported_all_wheels = supported
		if not bool(out.landing_dwell_complete) and stable_ticks >= landing_ticks:
			out.landing_dwell_complete = true
			out.landing_stable = {tick = session.sim.tick, time_s = session.sim.time(), speed_mps = speed_mps,
				north_m = after[0], east_m = after[1], all_wheels_down = all_wheels_down,
				all_anchors = all_anchors, runway_margin_m = runway_margin_m,
				angular_speed_rad_s = angular_speed, max_drift_m = landing_hold_max_drift_m}
			vacate_started = true
			vacate_start_time = session.sim.time()
			out.vacate_attempted = true
			out.vacate_start = out.landing_stable.duplicate(true)
		if vacate_started:
			if all_wheels_clear_north:
				vacate_clear_ticks += 1
			else:
				vacate_clear_ticks = 0
			if float(vacate_clear_ticks) * dt >= 0.25:
				out.runway_vacated = true
				out.vacate_time_s = session.sim.time() - vacate_start_time
			if session.sim.time() - vacate_start_time > VACATE_MAX_S and not out.runway_vacated:
				out.vacate_timeout = true
				out.error = "physical north-side runway vacate did not clear the loaded runway in 45 seconds"
			if bool(out.runway_vacated) and session.sim.time() - vacate_start_time >= 2.0:
				out.vacate_end = {tick = session.sim.tick, time_s = session.sim.time(), speed_mps = speed_mps,
					north_m = after[0], east_m = after[1], all_wheels_clear_north = all_wheels_clear_north}
				out.complete = true
				break
		if index % sample_interval == 0:
			var airspeed_mps: float = float(session.air_data(after, session.sim.time()).get("V", speed_mps))
			out.samples.append({tick = session.sim.tick, time_s = session.sim.time(), north_m = after[0], east_m = after[1],
				altitude_m = -after[2], speed_mps = speed_mps, ground_speed_mps = speed_mps,
				airspeed_mps = airspeed_mps, phase = phase, runway_margin_m = runway_margin_m,
				all_wheels_down = all_wheels_down, all_anchors = all_anchors})
		if session.sim.tick > 0 and (session.crash.size() > 0 or not session.prop_strike.is_empty() or session.gear_collapsed(session.sim.state)):
			out.terminal_damage = true
			out.error = "terminal contact/damage during sortie"
			break

	if not bool(out.complete) and str(out.error).is_empty():
		out.error = "sortie did not achieve a supported two-second rollout and physical runway vacate before timeout"
	out.terminal_damage = bool(out.terminal_damage) or not session.crash.is_empty() \
		or not session.prop_strike.is_empty() or session.gear_collapsed(session.sim.state)
	out.sim_fault = str(session.sim.fault_reason)
	if bool(out.terminal_damage) or not str(out.sim_fault).is_empty():
		out.complete = false
		if str(out.error).is_empty():
			out.error = "terminal damage or solver fault occurred during sortie"
	out.crash = session.crash.duplicate(true)
	out.prop_strike = session.prop_strike.duplicate(true)
	out.tick_count = session.sim.tick
	out.duration_s = session.sim.time()
	if pilot.has_method("research_diagnostics"):
		out.pilot_diagnostics = pilot.research_diagnostics()
	out.final_state = Array(session.sim.state)
	out.final_speed_mps = M.norm(session.sim.state.slice(3, 6))
	out.final_rpm = session.sim.aux[FlightSession.AUX_RPM]
	out.idle_rpm = float(session.aircraft.model.propulsion.get("idle_rpm", NAN))
	out.final_throttle = session.sim.inputs[3]
	if not is_finite(float(out.departure_min_runway_margin_m)):
		out.departure_min_runway_margin_m = -1.0
	if not is_finite(float(out.landing_min_runway_margin_m)):
		out.landing_min_runway_margin_m = -1.0
	if not is_finite(float(out.landing_min_gear_runway_margin_m)):
		out.landing_min_gear_runway_margin_m = -1.0
	if not is_finite(float(out.landing_min_hull_runway_margin_m)):
		out.landing_min_hull_runway_margin_m = -1.0
	out.flight_log_rows = 0
	out.flight_log_failure = ""
	out.flight_log_complete = false
	out.flight_log_observer_usec = 0
	out.flight_log_peak_buffer_rows = 0
	if logger != null:
		out.flight_log_rows = logger.rows_written
		out.flight_log_failure = str(logger.failure)
		var stop_error: Error = logger.stop("AFC-09 sortie finished: " + str(out.error if not out.complete else "complete"))
		out.flight_log_complete = stop_error == OK and str(logger.failure).is_empty() and not logger.recording
		out.flight_log_observer_usec = logger.observer_usec
		out.flight_log_peak_buffer_rows = logger.peak_buffer_rows
	session.free()
	return out


static func _runway_for(field: Dictionary) -> Dictionary:
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			return surface
	return {}


static func _runway_margin_for_point(point_ned: PackedFloat64Array, runway: Dictionary) -> float:
	return minf(float(runway.length_east_west) * 0.5 - absf(point_ned[1] - float(runway.center_east)),
		float(runway.width_north_south) * 0.5 - absf(point_ned[0] - float(runway.center_north)))


static func _phase_event(session: Node, state: PackedFloat64Array, phase: String, time_s: float) -> Dictionary:
	var attitude: PackedFloat64Array = state.slice(6, 10)
	var world_velocity: PackedFloat64Array = M.q_rotate(attitude, state.slice(3, 6))
	var ground_speed_mps: float = M.norm(state.slice(3, 6))
	var airspeed_mps: float = float(session.air_data(state, time_s).get("V", ground_speed_mps))
	return {tick = session.sim.tick, time_s = time_s, phase = phase,
		north_m = state[0], east_m = state[1], altitude_m = -state[2],
		speed_mps = ground_speed_mps, ground_speed_mps = ground_speed_mps,
		airspeed_mps = airspeed_mps, sink_mps = world_velocity[2],
		yaw_rad = M.q_to_euler(attitude)[0], bank_rad = M.q_to_euler(attitude)[2]}


static func _vacate_commands(state: PackedFloat64Array, target_north: float, elapsed_s: float) -> Dictionary:
	var attitude: PackedFloat64Array = state.slice(6, 10)
	var yaw: float = M.q_to_euler(attitude)[0]
	var speed: float = M.norm(state.slice(3, 6))
	var heading_error: float = wrapf(-yaw, -PI, PI)
	var north_error: float = target_north - state[0]
	# A small physical steering demand turns to the field's north side. It never assigns pose or velocity.
	var yaw_command: float = clampf(1.5 * heading_error, -0.55, 0.55)
	var throttle: float = clampf(0.14 + 0.10 * (1.0 - speed), 0.0, 0.24)
	if elapsed_s > VACATE_MAX_S or north_error <= 0.0:
		throttle = 0.0
	if absf(heading_error) < deg_to_rad(7.0):
		yaw_command = clampf(1.5 * heading_error, -0.25, 0.25)
	return {roll = 0.0, pitch = 0.0, yaw = yaw_command, throttle = throttle}
