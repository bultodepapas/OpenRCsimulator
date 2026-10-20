# AV-16: full-session Avanti S descriptive envelope and lifecycle-safe flight matrix.
# This records model predictions. It does not establish measured aircraft acceptance.
extends "../../extra-300/ex06/envelope_probe.gd"

const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const AVANTI_DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const WindConfig := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const Sim := preload("res://sim/simulation.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")

const LEVEL_SPEEDS := [22.0, 29.0, 45.0, 65.0]
const NORMAL_RATE := { "roll": 0.5, "pitch": 0.5, "yaw": 0.8 }
const HIGH_RATE := { "roll": 1.0, "pitch": 1.0, "yaw": 1.0 }


func _initialize() -> void:
	var output_path := ""
	var hz := 240
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--hz=") and arg.trim_prefix("--hz=").is_valid_int():
			hz = int(arg.trim_prefix("--hz="))
	if output_path.is_empty() or hz not in [240, 480]:
		printerr("AV-16 probe requires --output=<json-path> and --hz=240 or 480")
		quit(2)
		return
	Engine.physics_ticks_per_second = hz

	var session := _new_session()
	var report := {
		"schema": "openrc-avanti-envelope-probe-v1",
		"probe": "AV-16 bounded descriptive flight-behavior matrix",
		"aircraft_id": AVANTI_ID,
		"physics_hz": hz,
		"dt_s": 1.0 / float(hz),
		"scope": "Deterministic model predictions through FlightSession ticks; not physical validation or an operating envelope. No landing acceptance, ECU restart, or fuel-burn claim.",
		"errors": [],
		"cases": [],
		"linearized_modes": [],
	}
	var setup_error := str(session.get_meta("av14_setup_error", ""))
	if not setup_error.is_empty() or not session.is_flyable() or not session.sim.fault_reason.is_empty():
		report.errors.append(setup_error if not setup_error.is_empty() else
			str(session.pause_reason if not session.pause_reason.is_empty() else session.sim.fault_reason))
		report["completed"] = false
		_write_json(output_path, report)
		session.free()
		quit(1)
		return

	var model: Dictionary = session.aircraft.model
	report["setup"] = {
		"available": true,
		"start_trim": _trim_snapshot(session.start),
		"start_speed_mps": float(model.start_speed),
		"mass_kg": float(model.mass_kg),
		"cg_le_m": Array(model.cg_le),
		"inertia_kgm2": Array(model.inertia),
		"high_throw_deg": model.controls.throw_deg.duplicate(true),
		"normal_command_fraction": NORMAL_RATE.duplicate(true),
		"normal_rate_note": "manual normal-rate fractions of normalized full throw; transmitter expo is not modeled or applied twice",
		"field_id": session.ground_field_id,
		"weather": session.weather_configuration(),
	}

	var cases: Array = report["cases"]
	var neutral: Callable = func(_t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._hands_off()
	for speed: float in LEVEL_SPEEDS:
		_append_case(cases, session, "level_trim_%d" % int(speed), "level", speed, 10.0, 300.0, neutral,
			{ "probe": "hands-off trim persistence" })
	report["linearized_modes"] = _linearized_mode_snapshots(model, session.sim.gravity)

	_append_case(cases, session, "engine_off_glide_21", "glide", 21.0, 18.0, 300.0, neutral,
		{ "probe": "sustained engine-off glide; reports energy and ground margin, no touchdown claim" })

	for axis: String in ["roll", "pitch", "yaw"]:
		for direction: int in [-1, 1]:
			for rate_name: String in ["normal", "high"]:
				var axis_name := axis
				var command_fraction: float = float(NORMAL_RATE[axis]) if rate_name == "normal" else float(HIGH_RATE[axis])
				var amplitude: float = float(direction) * command_fraction
				var pilot: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
					return Maneuvers._pulse(t, 0.25, 1.25, { axis_name: amplitude })
				_append_case(cases, session, "%s_%s_%s" % [axis, rate_name, "positive" if direction > 0 else "negative"],
					"level", 29.0, 4.0, 250.0, pilot,
					{ "probe": "single-axis command pulse", "axis": axis, "sign": direction,
						"rate": rate_name, "command_fraction": amplitude, "pulse_s": [0.25, 1.25] })

	var throttle_up: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.25, 3.25, { "throttle_delta": 1.0 })
	_append_case(cases, session, "throttle_up_step_22", "level", 22.0, 8.0, 300.0, throttle_up,
		{ "probe": "running-engine throttle step to full then return to trimmed demand" })

	var idle_approach: Callable = func(_t: float, _s: PackedFloat64Array) -> Dictionary:
		return { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle_delta": -float(session.start.throttle) }
	_append_case(cases, session, "idle_descent_approach_22", "level", 22.0, 18.0, 300.0, idle_approach,
		{ "probe": "sustained idle descent from an in-air start; no flare or landing claim" })

	var go_around: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		var throttle_delta := -float(session.start.throttle) if t < 3.0 else 1.0
		return { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle_delta": throttle_delta }
	_append_case(cases, session, "idle_to_full_go_around_input_22", "level", 22.0, 12.0, 250.0, go_around,
		{ "probe": "idle for 3 s then full throttle input; no ECU shutdown/restart claim" })

	for direction: int in [-1, 1]:
		var turn_sign := direction
		var guided_turn: Callable = func(t: float, s: PackedFloat64Array) -> Dictionary:
			var attitude := M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
			var euler: PackedFloat64Array = M.q_to_euler(attitude)
			var bank: float = euler[2]
			var climb_rate: float = -M.q_rotate(attitude, M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))[2]
			var altitude: float = -s[RB.POS + 2]
			var target_bank: float = deg_to_rad(30.0) * float(turn_sign) if t >= 0.5 and t < 8.0 else 0.0
			var target_altitude := 300.0
			var command := {
				"roll": clampf(1.5 * (target_bank - bank) - 0.4 * s[RB.RATE], -0.5, 0.5),
				"pitch": clampf(0.003 * (target_altitude - altitude) - 0.1 * climb_rate - 0.2 * s[RB.RATE + 1], -0.5, 0.5),
				"yaw": 0.0,
				"throttle_delta": 0.0,
			}
			command = Maneuvers._coordinated(command, s)
			command["yaw"] = clampf(float(command.yaw), -0.8, 0.8)
			return command
		_append_case(cases, session, "guided_30deg_turn_%s" % ("right" if direction > 0 else "left"),
			"level", 29.0, 12.0, 300.0, guided_turn,
			{ "probe": "bounded altitude and bank guidance; pilot gains are diagnostic inputs, not aircraft coefficients",
				"target_bank_deg": 30.0 * direction })

		var slip_sign := direction
		var cross_control_slip: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._pulse(t, 0.25, 2.25,
				{ "yaw": 0.35 * float(slip_sign), "roll": -0.15 * float(slip_sign) })
		_append_case(cases, session, "cross_control_slip_%s" % ("right" if direction > 0 else "left"),
			"level", 29.0, 5.0, 250.0, cross_control_slip,
			{ "probe": "opposed roll/yaw pulse; inspect air-relative sideslip and rates", "sign": direction })

	for power_name: String in ["idle", "full_power"]:
		var power := power_name
		var stall_entry: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			var command := Maneuvers._pulse(t, 0.25, 4.25, { "pitch": 1.0 })
			command["throttle_delta"] = -float(session.start.throttle) if power == "idle" else 1.0
			return command
		_append_case(cases, session, "high_pitch_stall_entry_%s_24" % power_name, "level", 24.0, 6.0, 400.0,
			stall_entry, { "probe": "high-pitch entry at idle/full power; stall break and recovery are not inferred",
				"power_setting": power_name })

	for direction: int in [-1, 1]:
		var spin_sign := direction
		var spin_entry: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			var command := Maneuvers._pulse(t, 0.25, 4.0,
				{ "pitch": 1.0, "yaw": float(spin_sign) })
			if t >= 4.0 and t < 5.0:
				command = { "roll": 0.0, "pitch": -0.5, "yaw": -float(spin_sign), "throttle_delta": 0.0 }
			command["throttle_delta"] = -float(session.start.throttle)
			return command
		var spin_case := _run_flight_case(session, "stall_rotation_response_%s_rudder" % ("right" if direction > 0 else "left"),
			"level", 24.0, 8.0, 500.0, spin_entry)
		if spin_case.has("trace"):
			spin_case.summary["spin_windows"] = _spin_window_metrics(spin_case.trace)
			spin_case.summary["spin_windows"]["yaw_sign"] = direction
			spin_case.summary["spin_windows"]["entry_r_sign_aligned_max_rad_s"] = _signed_window_max(
				spin_case.trace, "r_radps", 2.5, 4.0, direction)
			spin_case.summary["spin_windows"]["recovery_r_sign_aligned_max_abs_rad_s"] = _signed_window_max_abs(
				spin_case.trace, "r_radps", 4.0, 5.0)
		spin_case.summary["probe"] = "stall-rotation response with opposite-rudder recovery input; sustained spin is not asserted"
		cases.append(spin_case.summary)

	for direction: int in [-1, 1]:
		var pitch_sign := direction
		var pitch_loop: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._pulse(t, 0.2, 8.0,
				{ "pitch": 0.25 * float(pitch_sign), "throttle_delta": 1.0 })
		var loop_case := _run_flight_case(session, "pitch_loop_input_%s_50" % ("positive" if direction > 0 else "negative"),
			"level", 50.0, 8.0, 500.0, pitch_loop)
		if loop_case.has("trace"):
			loop_case.summary["trajectory"] = _trajectory(loop_case.trace)
		loop_case.summary["probe"] = "open-loop pitch pulse; q integral is descriptive and does not prove a completed loop"
		loop_case.summary["pitch_command_fraction"] = 0.25 * direction
		cases.append(loop_case.summary)

	var inverted := _solve_inverted_trim(model, 35.0, session.sim.gravity, session.air_density(), session.engine_charge_ratio())
	report["inverted_trim_solver"] = {
		"available": bool(inverted.get("ok", false)),
		"message": str(inverted.get("message", "no solution")),
		"speed_mps": 35.0,
		"residual_l2": _finite_or_null(inverted.get("residual_l2", null)),
		"iterations": int(inverted.get("iterations", 0)),
		"trim": _trim_snapshot(inverted) if inverted.get("ok", false) else {},
	}
	if inverted.get("ok", false):
		var inverted_case := _run_inverted_hands_off(session, inverted, 8.0, 250.0)
		cases.append(inverted_case.summary)
	else:
		cases.append({ "id": "inverted_hands_off_35", "available": false,
			"reason": str(inverted.get("message", "inverted trim unavailable")), "complete": false })

	for preset: String in ["gentle-practice", "gusty", "hot-high"]:
		var weather_session := _new_session(WindConfig.preset(preset))
		var environment_case := _run_flight_case(weather_session, "environment_" + preset, "level", 29.0, 10.0, 300.0, neutral)
		var environment_trace: RefCounted = environment_case.get("trace")
		var environment_meta: Dictionary = environment_trace.meta if environment_case.has("trace") else {}
		environment_case.summary["environment"] = {
			"preset": preset,
			"air_density_kg_m3": weather_session.air_density(),
			"engine_charge_ratio": weather_session.engine_charge_ratio(),
			"configuration": weather_session.weather_configuration(),
			"recording_start_rng_state": environment_meta.get("recording_start_rng_state", ""),
			"recording_start_turbulence": environment_meta.get("recording_start_turbulence", ""),
			"comparison_note": "Compare 240/480 Hz turbulence as distinct sampled realizations using the recorded start state; do not treat equal preset names as identical stochastic forcing.",
		}
		cases.append(environment_case.summary)
		weather_session.free()

	for case: Dictionary in cases:
		if not case.get("available", false):
			report.errors.append("unavailable flight case: " + str(case.get("id", "?")) + ": " + str(case.get("reason", "")))
		elif not case.get("complete", false):
			report.errors.append("incomplete or invalid flight case: " + str(case.get("id", "?")))
	report["completed"] = cases.size() == 34 and report.errors.is_empty()
	if cases.size() != 34:
		report.errors.append("expected 34 flight cases, got %d" % cases.size())
		report["completed"] = false
	_write_json(output_path, report)
	print("AV-16 Avanti: %d cases, %d errors at %d Hz" % [cases.size(), report.errors.size(), hz])
	session.free()
	quit(0 if report.completed else 1)


func _new_session(weather := {}) -> Node:
	var session := Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	if not weather.is_empty() and not session.setup_weather(weather):
		session.set_meta("av14_setup_error", "Avanti weather configuration was refused")
	session.setup(AVANTI_DATA, AVANTI_ID)
	root.add_child(session)
	session.start_choice = Session.START_AIRBORNE
	var loaded_field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded_field.get("ok", false):
		session.set_meta("av14_setup_error", "default field failed to load")
	elif not session.set_field(loaded_field.get("field", {})):
		session.set_meta("av14_setup_error", "default field surfaces failed: " + str(session.surface_error))
	session.reset()
	return session


func _append_case(cases: Array, session: Node, case_id: String, mode: String, speed: float,
		duration: float, altitude: float, sticks: Callable, notes := {}) -> void:
	var result := _run_flight_case(session, case_id, mode, speed, duration, altitude, sticks)
	result.summary.merge(notes, true)
	cases.append(result.summary)


func _run_flight_case(session: Node, case_id: String, mode: String, speed: float, duration: float,
		altitude: float, sticks: Callable) -> Dictionary:
	var trim: Dictionary = session.trim_at(speed, mode)
	if not trim.get("ok", false):
		return { "summary": { "id": case_id, "available": false, "complete": false,
			"reason": str(trim.get("message", "trim failed")), "mode": mode, "speed_mps": speed } }
	session.set_start_altitude(altitude)
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return { "summary": { "id": case_id, "available": false, "complete": false,
			"reason": str(session.pause_reason if not session.pause_reason.is_empty() else session.sim.fault_reason),
			"mode": mode, "speed_mps": speed, "trim": _trim_snapshot(trim) } }
	session.crash_auto_restart = false
	session.sim.set_paused(false)
	var recorder := Recorder.new(session.sim, session.electrical_state, Callable(session, "mass_properties"))
	recorder.start(session.trace_meta())
	var requested_ticks := roundi(duration / session.sim.dt())
	var steps := 0
	var tick_error := ""
	for _i in requested_ticks:
		var pilot: Dictionary = sticks.call(session.sim.time(), session.sim.state.duplicate())
		session.commands = {
			"roll": clampf(float(pilot.get("roll", 0.0)), -1.0, 1.0),
			"pitch": clampf(float(pilot.get("pitch", 0.0)), -1.0, 1.0),
			"yaw": clampf(float(pilot.get("yaw", 0.0)), -1.0, 1.0),
			"throttle": clampf(float(session.start.throttle) + float(pilot.get("throttle_delta", 0.0)), 0.0, 1.0),
		}
		session.sim.inputs = session._inputs()
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		if session.sim.paused:
			tick_error = "session paused before requested end"
			break
		var previous_tick: int = session.sim.tick
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		if session.sim.tick != previous_tick + 1:
			tick_error = "simulation did not commit exactly one session tick"
			break
		steps += 1
		if not Sim.state_is_valid(session.sim.state):
			tick_error = "session committed an invalid rigid-body state"
			break
	if session.crash.is_empty() and session.sim.fault_reason.is_empty() and not session.sim.paused:
		# A zero-delta session callback inspects the final committed state for contact without
		# advancing the crash hold timer or adding another simulation tick.
		session._physics_process(0.0)
	recorder.detach()
	var trace: RefCounted = recorder.trace
	var flight := _trace_metrics(trace, session.sim.dt(), duration)
	var no_crash: bool = session.crash.is_empty()
	var no_fault: bool = session.sim.fault_reason.is_empty() and tick_error.is_empty()
	var expected_rows: int = requested_ticks + 1
	var trace_ok: bool = trace.row_count() == expected_rows and bool(flight.trace_continuous) \
		and int(flight.nonfinite_scalar_count) == 0 and bool(flight.state_rows_valid)
	flight["requested_ticks"] = requested_ticks
	flight["committed_ticks"] = steps
	flight["complete"] = steps == requested_ticks and trace_ok and no_crash and no_fault
	flight["tick_error"] = tick_error
	flight["no_crash"] = no_crash
	flight["no_fault"] = no_fault
	return {
		"summary": {
			"id": case_id,
			"available": true,
			"complete": bool(flight.complete),
			"mode": mode,
			"speed_mps": speed,
			"duration_s": duration,
			"altitude_start_m": altitude,
			"trim": _trim_snapshot(trim),
			"flight": flight,
			"simulation_fault": str(session.sim.fault_reason) if tick_error.is_empty() else tick_error,
			"crash": session.crash.duplicate(true),
			"session_paused": session.sim.paused,
			"shaft_integrator": session.shaft_integrator(),
		},
		"trace": trace,
	}


func _run_inverted_hands_off(session: Node, trim: Dictionary, duration: float, altitude: float) -> Dictionary:
	var start: Dictionary = trim.duplicate(true)
	var state: PackedFloat64Array = start.state.duplicate()
	state[RB.POS + 2] = -altitude
	start.state = state
	start["ok"] = true
	session.start = start
	session.trims = { "roll": trim.roll_command, "pitch": trim.pitch_command, "yaw": trim.yaw_command }
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return { "summary": { "id": "inverted_hands_off_35", "available": false, "complete": false,
			"reason": str(session.pause_reason if not session.pause_reason.is_empty() else session.sim.fault_reason) } }
	session.crash_auto_restart = false
	session.sim.set_paused(false)
	var recorder := Recorder.new(session.sim, session.electrical_state, Callable(session, "mass_properties"))
	recorder.start(session.trace_meta())
	var requested_ticks := roundi(duration / session.sim.dt())
	var steps := 0
	var tick_error := ""
	for _i in requested_ticks:
		session.commands = { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": float(trim.throttle) }
		session.sim.inputs = session._inputs()
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		if session.sim.paused:
			tick_error = "session paused before requested inverted-flight end"
			break
		var previous_tick: int = session.sim.tick
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		if session.sim.tick != previous_tick + 1:
			tick_error = "inverted simulation did not commit exactly one session tick"
			break
		steps += 1
		if not Sim.state_is_valid(session.sim.state):
			tick_error = "inverted session committed an invalid rigid-body state"
			break
	if session.crash.is_empty() and session.sim.fault_reason.is_empty() and not session.sim.paused:
		session._physics_process(0.0)
	recorder.detach()
	var trace: RefCounted = recorder.trace
	var flight := _trace_metrics(trace, session.sim.dt(), duration)
	var no_crash: bool = session.crash.is_empty()
	var no_fault: bool = session.sim.fault_reason.is_empty() and tick_error.is_empty()
	var expected_rows: int = requested_ticks + 1
	var trace_ok: bool = trace.row_count() == expected_rows and bool(flight.trace_continuous) \
		and int(flight.nonfinite_scalar_count) == 0 and bool(flight.state_rows_valid)
	flight["requested_ticks"] = requested_ticks
	flight["committed_ticks"] = steps
	flight["complete"] = steps == requested_ticks and trace_ok and no_crash and no_fault
	flight["tick_error"] = tick_error
	flight["no_crash"] = no_crash
	flight["no_fault"] = no_fault
	return { "summary": {
		"id": "inverted_hands_off_35", "available": true, "complete": bool(flight.complete),
		"mode": "inverted_level", "speed_mps": 35.0, "duration_s": duration,
		"altitude_start_m": altitude, "trim": _trim_snapshot(trim), "flight": flight,
		"simulation_fault": str(session.sim.fault_reason) if tick_error.is_empty() else tick_error,
		"crash": session.crash.duplicate(true), "session_paused": session.sim.paused,
		"shaft_integrator": session.shaft_integrator(),
		"interpretation": "research-only model prediction; no measured inverted-flight acceptance target",
	}, "trace": trace }


func _trace_metrics(trace: RefCounted, dt: float, requested_duration: float) -> Dictionary:
	var metrics: Dictionary = super._trace_metrics(trace, dt, requested_duration)
	var base: Dictionary = metrics.get("metrics", {})
	var alpha := _new_metric()
	var beta := _new_metric()
	var tas := _new_metric()
	var state_rows_valid: bool = trace.row_count() > 0
	var columns: Array = trace.columns()
	var has_wind: bool = columns.has("wind_north_mps") and columns.has("wind_east_mps") and columns.has("wind_down_mps")
	for row in trace.row_count():
		var state := RB.make_state(
			M.v3(trace.value(row, "north_m"), trace.value(row, "east_m"), trace.value(row, "down_m")),
			M.v3(trace.value(row, "u_mps"), trace.value(row, "v_mps"), trace.value(row, "w_mps")),
			M.quat(trace.value(row, "qw"), trace.value(row, "qx"), trace.value(row, "qy"), trace.value(row, "qz")),
			M.v3(trace.value(row, "p_radps"), trace.value(row, "q_radps"), trace.value(row, "r_radps")))
		state_rows_valid = state_rows_valid and Sim.state_is_valid(state)
		var q := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
		var wind := M.v3(0.0, 0.0, 0.0)
		if has_wind:
			wind = M.v3(trace.value(row, "wind_north_mps"), trace.value(row, "wind_east_mps"), trace.value(row, "wind_down_mps"))
		var wind_body: PackedFloat64Array = M.q_rotate(M.q_conj(q), wind)
		var air_body: PackedFloat64Array = M.v3(
			state[RB.VEL] - wind_body[0], state[RB.VEL + 1] - wind_body[1], state[RB.VEL + 2] - wind_body[2])
		var air_speed := sqrt(air_body[0] ** 2 + air_body[1] ** 2 + air_body[2] ** 2)
		_append_value(alpha, rad_to_deg(atan2(air_body[2], air_body[0])))
		_append_value(beta, rad_to_deg(atan2(air_body[1], sqrt(air_body[0] ** 2 + air_body[2] ** 2))))
		_append_value(tas, air_speed)
	base["alpha_deg"] = _metric_snapshot(alpha)
	base["beta_deg"] = _metric_snapshot(beta)
	base["tas_mps"] = _metric_snapshot(tas)
	metrics["metrics"] = base
	metrics["state_rows_valid"] = state_rows_valid
	metrics["air_angle_basis"] = "body velocity minus recorded total NED wind (background wind plus sampled turbulence), rotated into body axes"
	metrics["speed_basis"] = "speed_mps is the norm of the body state velocity (world ground trajectory); tas_mps and alpha/beta use air-relative velocity"
	metrics["complete"] = trace.row_count() == int(metrics.get("expected_rows", -1)) \
		and bool(metrics.get("trace_continuous", false)) and int(metrics.get("nonfinite_scalar_count", 1)) == 0 and state_rows_valid
	return metrics


func _linearized_mode_snapshots(model: Dictionary, gravity: float) -> Array:
	var out: Array = []
	for speed: float in LEVEL_SPEEDS:
		var result: Dictionary = FlightModes.analyze(model, speed, gravity)
		var row := {
			"speed_mps": speed,
			"success": bool(result.get("ok", false)),
			"message": str(result.get("message", "")),
			"short_period": _mode_pair(result.get("short_period", {})),
			"phugoid": _mode_pair(result.get("phugoid", {})),
			"dutch_roll": _mode_pair(result.get("dutch_roll", {})),
			"roll_tau_s": _finite_or_null(result.get("roll_tau", null)),
			"spiral_tau_s": _finite_or_null(result.get("spiral_tau", null)),
			"downwash_lag_root_per_s": _finite_or_null(result.get("downwash_lag_root", null)),
			"projection_note": "Trimmed level Jacobian with throttle, shaft RPM, and control deflections frozen; reported longitudinal/lateral diagonal-block projections omit cross-axis coupling and are not full coupled/gyro eigenvalues.",
		}
		out.append(row)
	return out


func _mode_pair(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var f: Variant = _finite_or_null(value.get("f_hz", null))
	var z: Variant = _finite_or_null(value.get("zeta", null))
	if f == null or z == null:
		return null
	return { "f_hz": f, "zeta": z }


func _trajectory(trace: RefCounted) -> Dictionary:
	var rows: int = trace.row_count()
	if rows < 2:
		return { "available": false, "reason": "trajectory needs at least two trace rows" }
	var first_q := M.quat(trace.value(0, "qw"), trace.value(0, "qx"), trace.value(0, "qy"), trace.value(0, "qz"))
	var first_body_velocity := M.v3(trace.value(0, "u_mps"), trace.value(0, "v_mps"), trace.value(0, "w_mps"))
	var first_world_velocity: PackedFloat64Array = M.q_rotate(first_q, first_body_velocity)
	var horizontal_norm := sqrt(first_world_velocity[0] ** 2 + first_world_velocity[1] ** 2)
	if horizontal_norm < 1e-9:
		return { "available": false, "reason": "initial horizontal world velocity is too small to define the vertical plane" }
	var along_north := first_world_velocity[0] / horizontal_norm
	var along_east := first_world_velocity[1] / horizontal_norm
	var cross_north := -along_east
	var cross_east := along_north
	var previous_angle := atan2(-first_world_velocity[2], first_world_velocity[0] * along_north + first_world_velocity[1] * along_east)
	var unwrapped_angle := 0.0
	var min_unwrapped := 0.0
	var max_unwrapped := 0.0
	var max_cross_track := 0.0
	var max_cross_velocity := 0.0
	var min_altitude: float = trace.value(0, "alt_m")
	var max_altitude: float = min_altitude
	var min_ground_speed: float = trace.value(0, "speed_mps")
	var max_abs_body_q_integral := 0.0
	var body_q_integral := 0.0
	var start_north: float = trace.value(0, "north_m")
	var start_east: float = trace.value(0, "east_m")
	for row in rows:
		var q := M.quat(trace.value(row, "qw"), trace.value(row, "qx"), trace.value(row, "qy"), trace.value(row, "qz"))
		var velocity := M.q_rotate(q, M.v3(trace.value(row, "u_mps"), trace.value(row, "v_mps"), trace.value(row, "w_mps")))
		var along_velocity: float = velocity[0] * along_north + velocity[1] * along_east
		var angle := atan2(-velocity[2], along_velocity)
		if row > 0:
			unwrapped_angle += wrapf(angle - previous_angle, -PI, PI)
			body_q_integral += trace.value(row, "q_radps") * 1.0 / float(Engine.physics_ticks_per_second)
		previous_angle = angle
		min_unwrapped = minf(min_unwrapped, unwrapped_angle)
		max_unwrapped = maxf(max_unwrapped, unwrapped_angle)
		var cross_track: float = (trace.value(row, "north_m") - start_north) * cross_north \
			+ (trace.value(row, "east_m") - start_east) * cross_east
		var cross_velocity: float = velocity[0] * cross_north + velocity[1] * cross_east
		max_cross_track = maxf(max_cross_track, absf(cross_track))
		max_cross_velocity = maxf(max_cross_velocity, absf(cross_velocity))
		min_altitude = minf(min_altitude, trace.value(row, "alt_m"))
		max_altitude = maxf(max_altitude, trace.value(row, "alt_m"))
		min_ground_speed = minf(min_ground_speed, trace.value(row, "speed_mps"))
		max_abs_body_q_integral = maxf(max_abs_body_q_integral, absf(body_q_integral))
	var end_north: float = trace.value(rows - 1, "north_m")
	var end_east: float = trace.value(rows - 1, "east_m")
	var end_distance := sqrt((end_north - start_north) ** 2 + (end_east - start_east) ** 2
		+ (trace.value(rows - 1, "alt_m") - trace.value(0, "alt_m")) ** 2)
	return {
		"available": true,
		"body_q_integral_deg": rad_to_deg(body_q_integral),
		"body_q_integral_abs_peak_deg": rad_to_deg(max_abs_body_q_integral),
		"world_velocity_flight_path_turn_deg": rad_to_deg(unwrapped_angle),
		"world_velocity_flight_path_turn_min_deg": rad_to_deg(min_unwrapped),
		"world_velocity_flight_path_turn_max_deg": rad_to_deg(max_unwrapped),
		"max_abs_cross_track_m": max_cross_track,
		"max_abs_cross_velocity_mps": max_cross_velocity,
		"min_ground_speed_mps": min_ground_speed,
		"min_altitude_m": min_altitude,
		"max_altitude_m": max_altitude,
		"endpoint_distance_from_start_m": end_distance,
		"vertical_plane_heading_ned": [along_north, along_east],
		"interpretation": "Body q integral is descriptive. The independent path metric unwraps atan2(-world-down velocity, velocity along the initial vertical plane); cross-track distance and velocity describe plane departure. None alone proves a completed loop.",
	}


func _signed_window_max(trace: RefCounted, column: String, t0: float, t1: float, sign: float) -> float:
	var peak := -INF
	for row in trace.row_count():
		var t: float = trace.value(row, "t_s")
		if t >= t0 and t <= t1:
			peak = maxf(peak, sign * trace.value(row, column))
	return peak if is_finite(peak) else 0.0


func _signed_window_max_abs(trace: RefCounted, column: String, t0: float, t1: float) -> float:
	var peak := 0.0
	for row in trace.row_count():
		var t: float = trace.value(row, "t_s")
		if t >= t0 and t <= t1:
			peak = maxf(peak, absf(trace.value(row, column)))
	return peak


func _new_metric() -> Dictionary:
	return { "count": 0, "start": 0.0, "end": 0.0, "min": INF, "max": -INF, "max_abs": 0.0 }


func _append_value(metric: Dictionary, value: float) -> void:
	if not is_finite(value):
		return
	if int(metric.count) == 0:
		metric.start = value
	metric.end = value
	metric.min = minf(float(metric.min), value)
	metric.max = maxf(float(metric.max), value)
	metric.max_abs = maxf(float(metric.max_abs), absf(value))
	metric.count = int(metric.count) + 1


func _metric_snapshot(metric: Dictionary) -> Dictionary:
	var has_values: bool = int(metric.count) > 0
	return {
		"start": _finite_or_null(metric.start) if has_values else null,
		"end": _finite_or_null(metric.end) if has_values else null,
		"min": _finite_or_null(metric.min) if has_values else null,
		"max": _finite_or_null(metric.max) if has_values else null,
		"max_abs": _finite_or_null(metric.max_abs) if has_values else null,
		"delta": _finite_or_null(float(metric.end) - float(metric.start)) if has_values else null,
		"finite_samples": int(metric.count),
	}
