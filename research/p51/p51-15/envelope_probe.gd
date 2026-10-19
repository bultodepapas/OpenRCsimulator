# P51-17: full-session P-51 descriptive envelope. Shared EX-06 reducers and
# inverted Newton solver are reused; its aircraft identity and scenarios are not.
extends "../../extra-300/ex06/envelope_probe.gd"

const P51_ID := "p51d-mustang-120"
const WindConfig := preload("res://physics/wind_config.gd")


func _initialize() -> void:
	var output := ""
	var hz := 240
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		elif arg.begins_with("--hz="):
			hz = int(arg.trim_prefix("--hz="))
	if output.is_empty() or hz not in [240, 480]:
		printerr("P51 probe needs --output=path and --hz=240 or 480")
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	var session := _new_session()
	var report := {schema = "openrc-p51-envelope-probe-v1", aircraft_id = P51_ID,
		physics_hz = hz, errors = [], cases = [],
		scope = "Model predictions and numerical checks, not measured physical acceptance. Calm reference unless named otherwise."}
	if not session.is_flyable():
		report.errors.append(session.pause_reason)
		_write_json(output, report)
		quit(1)
		return
	var cases: Array = report.cases
	var model: Dictionary = session.aircraft.model
	report.setup = {mass_kg = model.mass_kg, cg_le_m = Array(model.cg_le),
		inertia_kgm2 = Array(model.inertia), trim = _trim_snapshot(session.start),
		throws_deg = model.controls.throw_deg, shaft_integrator = session.shaft_integrator()}
	var neutral := func(_t: float, _s: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off()
	for speed: float in [20.0, 25.0, 35.0, 45.0]:
		_store_case(cases, session, "level_trim_%d" % speed, "level", speed, 10.0, 500.0, neutral)
	_store_case(cases, session, "engine_stopped_glide", "glide", 25.0, 10.0, 500.0, neutral)

	# These low rates are the printed H9 1.50 degrees (borrowed RC comparison),
	# not transmitter expo and not measured throws on this custom quarter-scale build.
	var lows := {roll = 14.0 / 18.0, pitch = 12.0 / 15.0, yaw = 20.0 / 30.0}
	for axis: String in ["roll", "pitch", "yaw"]:
		for direction: int in [-1, 1]:
			for rate: String in ["low", "high"]:
				var axis_name := axis
				var amplitude: float = float(direction) * (float(lows[axis]) if rate == "low" else 1.0)
				var pilot := func(t: float, _s: PackedFloat64Array) -> Dictionary:
					return Maneuvers._pulse(t, 0.25, 1.25, {axis_name: amplitude})
				_store_case(cases, session, "%s_%s_%d" % [axis, rate, direction], "level", 25.0, 3.5, 500.0, pilot)

	var throttle := func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.25, 2.0, {throttle_delta = 1.0})
	_store_case(cases, session, "throttle_split", "level", 25.0, 5.0, 500.0, throttle)
	var coupled := _new_session({}, true)
	_store_case(cases, coupled, "throttle_coupled", "level", 25.0, 5.0, 500.0, throttle)
	coupled.free()
	var idle := func(_t: float, _s: PackedFloat64Array) -> Dictionary:
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle_delta = -1.0}
	_store_case(cases, session, "running_engine_idle_descent", "level", 25.0, 10.0, 500.0, idle)

	for direction: int in [-1, 1]:
		var sign_ := direction
		var turn := func(t: float, s: PackedFloat64Array) -> Dictionary:
			var q := M.quat(s[6], s[7], s[8], s[9])
			var bank: float = M.q_to_euler(q)[2]
			var down: float = M.q_rotate(q, M.v3(s[3], s[4], s[5]))[2]
			var target := deg_to_rad(30.0) * sign_ if t >= 0.5 and t < 7.0 else 0.0
			return Maneuvers._coordinated({roll = clampf(1.5 * (target - bank) - 0.4 * s[10], -1.0, 1.0),
				pitch = clampf(0.02 * (500.0 + s[2]) + 0.05 * down - 0.2 * s[11], -1.0, 1.0),
				yaw = 0.0, throttle_delta = 0.0}, s)
		_store_case(cases, session, "guided_turn_%d" % direction, "level", 30.0, 10.0, 500.0, turn)
		var slip := func(t: float, _s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._pulse(t, 0.25, 2.0, {yaw = 0.4 * sign_, roll = -0.15 * sign_})
		_store_case(cases, session, "cross_control_slip_%d" % direction, "level", 25.0, 4.0, 500.0, slip)
		var spin := func(t: float, _s: PackedFloat64Array) -> Dictionary:
			var c := Maneuvers._pulse(t, 0.25, 4.0, {pitch = 1.0, yaw = float(sign_)})
			if t >= 4.0 and t < 5.0:
				c = {roll = 0.0, pitch = -0.5, yaw = -float(sign_), throttle_delta = 0.0}
			c.throttle_delta = -1.0
			return c
		var spin_case := _run_flight_case(session, "spin_%d" % direction, "level", 18.0, 8.0, 500.0, spin)
		if spin_case.has("trace"):
			spin_case.summary.spin_windows = _spin_window_metrics(spin_case.trace)
		cases.append(spin_case.summary)

	for power: float in [0.0, 0.3]:
		var throttle_setting := power
		var stall := func(t: float, _s: PackedFloat64Array) -> Dictionary:
			var c := Maneuvers._pulse(t, 0.25, 4.0, {pitch = 1.0})
			c.throttle_delta = throttle_setting - float(session.start.throttle)
			return c
		_store_case(cases, session, "stall_throttle_%.1f" % power, "level", 18.0, 4.0, 500.0, stall)

	for direction: int in [-1, 1]:
		var pitch_sign := direction
		var loop := func(t: float, _s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._pulse(t, 0.2, 8.0, {pitch = 0.7 * pitch_sign, throttle_delta = 1.0})
		var flown := _run_flight_case(session, "pitch_loop_input_%d" % direction, "level", 30.0, 8.0, 500.0, loop)
		if flown.has("trace"):
			flown.summary.trajectory = _trajectory(flown.trace)
		cases.append(flown.summary)

	var inverted := _solve_inverted_trim(model, 30.0, session.sim.gravity, session.air_density(), session.engine_charge_ratio())
	if inverted.get("ok", false):
		cases.append(_run_inverted_hands_off(session, inverted, 7.0, 500.0).summary)
	else:
		cases.append({id = "inverted_hands_off_7s", available = false, reason = inverted.get("message", "trim unavailable")})

	for preset: String in ["gentle-practice", "gusty", "hot-high"]:
		var windy := _new_session(WindConfig.preset(preset))
		_store_case(cases, windy, "environment_" + preset, "level", 25.0, 10.0, 500.0, neutral)
		cases[-1].environment = {density_kgm3 = windy.air_density(), charge_ratio = windy.engine_charge_ratio(), preset = preset}
		windy.free()
	for c: Dictionary in cases:
		if not c.get("available", false):
			report.errors.append("unavailable case: " + str(c.id))
		elif not str(c.simulation_fault).is_empty() or c.flight.nonfinite_scalar_count != 0 or not c.flight.trace_continuous or c.flight.rows != c.flight.expected_rows:
			report.errors.append("invalid flight: " + str(c.id))
	_write_json(output, report)
	print("P51 airborne: %d cases; %d errors" % [cases.size(), report.errors.size()])
	session.free()
	quit(0 if report.errors.is_empty() else 1)


func _new_session(weather := {}, coupled := false) -> Node:
	var s := Session.new()
	s.input_enabled = false
	if not weather.is_empty():
		s.setup_weather(weather)
	if coupled:
		s.setup_shaft_integrator("coupled-rk4")
	s.setup(Catalog.entry(P51_ID).data, P51_ID)
	root.add_child(s)
	return s


func _run_flight_case(session: Node, case_id: String, mode: String, speed: float, duration: float,
		altitude: float, sticks: Callable) -> Dictionary:
	var trim: Dictionary = session.trim_at(speed, mode)
	if not trim.get("ok", false):
		return {summary = {id = case_id, available = false, reason = trim.get("message", "trim failed")}}
	session.set_start_altitude(altitude)
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return {summary = {id = case_id, available = false, reason = session.pause_reason + session.sim.fault_reason}}
	var rec := Recorder.new(session.sim, session.electrical_state, Callable(session, "mass_properties"))
	rec.start(session.trace_meta())
	for _i in roundi(duration / session.sim.dt()):
		var c: Dictionary = sticks.call(session.sim.time(), session.sim.state)
		session.commands = {roll = c.roll, pitch = c.pitch, yaw = c.yaw,
			throttle = clampf(float(session.start.throttle) + c.throttle_delta, 0.0, 1.0)}
		session.sim.inputs = session._inputs()
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		session.sim.step()
	rec.detach()
	return {summary = {id = case_id, available = true, mode = mode, trim = _trim_snapshot(trim),
		flight = _trace_metrics(rec.trace, session.sim.dt(), duration), simulation_fault = str(session.sim.fault_reason),
		crash = session.crash.duplicate(true), shaft_integrator = session.shaft_integrator()}, trace = rec.trace}


func _trajectory(tr: RefCounted) -> Dictionary:
	var roll := 0.0
	var heading := 0.0
	var integrated_q := 0.0
	for k in tr.row_count():
		roll = maxf(roll, absf(tr.value(k, "roll_deg")))
		heading = maxf(heading, absf(rad_to_deg(wrapf(deg_to_rad(tr.value(k, "yaw_deg") - tr.value(0, "yaw_deg")), -PI, PI))))
		integrated_q += tr.value(k, "q_radps") / float(Engine.physics_ticks_per_second)
	return {body_q_integral_deg = rad_to_deg(integrated_q), maximum_euler_roll_deg = roll,
		maximum_heading_deviation_deg = heading,
		interpretation = "Open-loop pitch input. Body-rate integral and Euler extrema do not establish a planar completed loop."}
