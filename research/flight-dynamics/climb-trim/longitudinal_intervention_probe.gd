# Compare the recorded throttle history in full 6-DOF and a stage-projected longitudinal plane.
# The projected run retains production aerodynamic/propulsion loads, but constrains lateral motion
# with reaction loads: Fy, Mx and Mz do not drive the projected body equations.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Aero := preload("res://physics/aero.gd")
const Integrator := preload("res://physics/integrator.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const INPUTS_PATH := "res://../research/flight-dynamics/climb-trim/ugly-loop-inputs.json"
const OUTPUT_PATH := "res://../docs/research/flight-dynamics/climb-trim/longitudinal-interventions.json"
const FLIGHT_SESSION_SOURCE_PATH := "res://sim/flight_session.gd"
const ALTITUDE_M := 500.0
const ELEVATOR_UP_DEG := 5.25673
const HISTORY_SECONDS := 15.0
const DURATION_SECONDS := 30.0

var _raw_input: Dictionary = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
var _run_stats: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture_text := FileAccess.get_file_as_string(INPUTS_PATH)
	var fixture: Dictionary = JSON.parse_string(fixture_text)
	if fixture.is_empty() or not fixture.has("samples"):
		printerr("Could not read the recorded throttle fixture: ", INPUTS_PATH)
		quit(1)
		return
	var session_source_path := ProjectSettings.globalize_path(FLIGHT_SESSION_SOURCE_PATH)
	var session_source_hash_before := _sha256(session_source_path)
	var sample_by_tick: Dictionary = {}
	for sample: Dictionary in fixture.samples:
		if int(sample.tick) <= int(round(HISTORY_SECONDS * 240.0)):
			sample_by_tick[int(sample.tick)] = sample.raw.duplicate(true)

	var original_rate := Engine.physics_ticks_per_second
	var runs: Array[Dictionary] = []
	Engine.physics_ticks_per_second = 240
	runs.append(_run_case("history_then_full_240_full_6dof", "full_6dof", 240, DURATION_SECONDS, sample_by_tick, true))
	runs.append(_run_case("history_then_full_240_projected_longitudinal", "projected_longitudinal", 240, DURATION_SECONDS, sample_by_tick, true))
	runs.append(_run_case("trim_hold_240_projected_longitudinal", "projected_longitudinal", 240, DURATION_SECONDS, sample_by_tick, false))
	Engine.physics_ticks_per_second = 480
	runs.append(_run_case("history_then_full_480_projected_longitudinal", "projected_longitudinal", 480, DURATION_SECONDS, sample_by_tick, true))
	Engine.physics_ticks_per_second = original_rate
	var session_source_hash_after := _sha256(session_source_path)
	var source_unchanged := session_source_hash_before != "unavailable" and session_source_hash_before == session_source_hash_after
	var validation_failures: Array[String] = []
	for run_index in range(runs.size()):
		var run: Dictionary = runs[run_index]
		var case_failures: Array[String] = _validate_case(run)
		run["case_validation"] = {"ok": case_failures.is_empty(), "failures": case_failures}
		runs[run_index] = run
		validation_failures.append_array(case_failures)
	if not source_unchanged:
		validation_failures.append("flight_session.gd source hash was unavailable or changed during the experiment")

	var payload := {
		"format": "openrc-longitudinal-intervention-probe-v1",
		"created_utc": Time.get_datetime_string_from_system(true, true),
		"scope": "Research-only counterfactual. No aircraft data, coefficients, runtime files, or golden flights are changed.",
		"aircraft_id": AIRCRAFT_ID,
		"aircraft_source": "app/data/aircraft/jensen_ugly_stik_60.json",
		"aircraft_source_sha256": _sha256(ProjectSettings.globalize_path(AIRCRAFT_PATH)),
		"input_fixture": "research/flight-dynamics/climb-trim/ugly-loop-inputs.json",
		"input_fixture_sha256": _sha256(ProjectSettings.globalize_path(INPUTS_PATH)),
		"source_history_last_tick_240_hz": int(round(HISTORY_SECONDS * 240.0)),
		"input_protocol": "The intervention cases replay fixture raw roll/pitch/yaw/throttle values through 15 s, then set commands.throttle to 1.0 and refresh sim.inputs after each flight-session input update. The trim-hold case keeps all raw controls neutral and retains solved trim.",
		"elevator_protocol": {"target_up_deg": ELEVATOR_UP_DEG, "source": "standard trimmed start; neutral raw pitch held throughout"},
		"initial_altitude_m": ALTITUDE_M,
		"weather": "default calm session weather; sea-level density model retained",
		"aerodynamic_branch": "Production Aero.loads branch is unchanged. It uses the global attached coefficients while local_flow_weight is zero; stage branch occupancy is measured below.",
		"projection_definition": "The projected initial state is rotated to zero heading and set to body v=p=r=0 while preserving trimmed u, w, q and pitch. At each RK4 stage and accepted endpoint, the diagnostic constraint keeps v=p=r and quaternion roll/yaw components at zero. Production loads and continuous derivatives remain active; projected angular derivatives are rebuilt with p_dot=r_dot=0 and q_dot=My/Jyy. Lateral force and roll/yaw moments are balanced by idealized constraint reactions; longitudinal force, pitch moment, u, w, q, pitch, propulsion/RPM and continuous states are retained.",
		"rk4_stage_hook": "Simulation.continuous_step receives the production derivative callable. The projected step recomputes k1-k4 at constrained stage states, retains production translational/continuous derivatives, replaces angular derivatives with the constrained p/q/r equations, then applies the RK4 weights and quaternion normalization.",
		"source_hash_guard": {"path": "app/sim/flight_session.gd", "before_sha256": session_source_hash_before, "after_sha256": session_source_hash_after, "unchanged": source_unchanged},
		"validation": {"ok": validation_failures.is_empty(), "failures": validation_failures},
		"runs": runs,
		"limitations": [
			"This isolates longitudinal dynamics from lateral motion; constraint reactions are a diagnostic model, not a free airplane.",
			"The aircraft's production attached-to-local aerodynamic blend remains enabled. A complete turn after local_flow_weight becomes nonzero is not evidence for attached-flow behavior.",
			"This is simulation evidence, not physical validation of the aircraft coefficients or engine model."
		]
	}
	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		printerr("Could not write evidence: ", OUTPUT_PATH)
		quit(1)
		return
	output.store_string(JSON.stringify(payload, "\t", true, true) + "\n")
	output.close()
	print("LONGITUDINAL_INTERVENTIONS ", JSON.stringify(payload))
	quit(0 if validation_failures.is_empty() else 1)


func _validate_case(run: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	var case_name := str(run.get("case", "unknown"))
	if not bool(run.get("setup_ok", false)):
		failures.append("%s did not set up" % case_name)
		return failures
	if not bool(run.get("completed", false)) or str(run.get("fault", "")) != "" or bool(run.get("paused", false)):
		failures.append("%s did not complete cleanly" % case_name)
	if absf(float(run.initial_state.get("down_m", 0.0)) + ALTITUDE_M) > 1e-9:
		failures.append("%s did not start at the requested altitude" % case_name)
	if absf(float(run.initial_state.get("elevator_up_deg", 0.0)) - ELEVATOR_UP_DEG) > 0.02:
		failures.append("%s did not retain the trimmed elevator" % case_name)
	if case_name.begins_with("history_then_full"):
		var full_throttle_seen := false
		for row: Dictionary in run.telemetry_1hz:
			if absf(float(row.time_s) - 16.0) < 1e-9 and absf(float(row.throttle) - 1.0) < 1e-12:
				full_throttle_seen = true
		if not full_throttle_seen:
			failures.append("%s did not apply full throttle after the 15 s fixture history" % case_name)
	if run.get("mode", "") == "projected_longitudinal":
		if int(run.stage_audit.get("projected_stage_calls", 0)) <= 0:
			failures.append("%s did not invoke the projected RK hook" % case_name)
		if float(run.stage_audit.get("max_projected_stage_constraint_residual", INF)) > 1e-12:
			failures.append("%s exceeded projected constraint residual tolerance" % case_name)
		if bool(run.stage_audit.get("body_derivative_override_seen", false)):
			failures.append("%s used a production body-derivative override that bypasses projected load reactions" % case_name)
		if not bool(run.stage_audit.get("projected_derivative_rebuild", false)):
			failures.append("%s did not rebuild the constrained body derivative" % case_name)
		if case_name.begins_with("trim_hold"):
			if float(run.events.get("first_unwrapped_pitch_360_s", -1.0)) >= 0.0 or float(run.events.get("max_abs_unwrapped_pitch_turns", INF)) > 1e-4:
				failures.append("trim-hold projection moved outside the no-loop tolerance")
		else:
			if float(run.events.get("first_unwrapped_pitch_360_s", -1.0)) < 0.0:
				failures.append("%s did not complete an unwrapped pitch turn" % case_name)
			if float(run.events.get("first_unwrapped_flight_path_360_s", -1.0)) < 0.0:
				failures.append("%s did not complete an unwrapped flight-path turn" % case_name)
	elif case_name.begins_with("history_then_full") and float(run.events.get("first_body_inverted_s", -1.0)) < 0.0:
		failures.append("full 6-DOF comparison did not reach the body-inverted condition")
	return failures


func _run_case(case_name: String, mode: String, tick_rate: int, duration_s: float, sample_by_tick: Dictionary, replay_history: bool) -> Dictionary:
	var session = Session.new()
	_raw_input = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	session.setup(AIRCRAFT_PATH, AIRCRAFT_ID)
	root.add_child(session)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.radio.connected = false
	session.read_raw = func() -> Dictionary: return _raw_input.duplicate()
	session.rate_profile = "normal"
	if not session.aircraft.get("ok", false) or session.start.get("state", PackedFloat64Array()).size() != RB.SIZE:
		var failed := {case = case_name, mode = mode, tick_rate_hz = tick_rate, setup_ok = false, message = "standard aircraft trim setup failed"}
		session.free()
		return failed

	# Move the solved trim to the requested altitude using the session's supported helper.
	session.set_start_altitude(ALTITUDE_M)
	var initial: PackedFloat64Array = session.start.state.duplicate()
	if mode == "projected_longitudinal":
		# Align the planar aircraft to zero heading and remove tiny trim-solver lateral residuals.
		# Retain trimmed u, w, q, pitch, controls, RPM and continuous states.
		var euler: PackedFloat64Array = M.q_to_euler(RB._att(initial))
		var planar_attitude: PackedFloat64Array = M.q_from_euler(0.0, euler[1], 0.0)
		initial[RB.VEL + 1] = 0.0
		initial[RB.ATT] = planar_attitude[0]
		initial[RB.ATT + 1] = planar_attitude[1]
		initial[RB.ATT + 2] = planar_attitude[2]
		initial[RB.ATT + 3] = planar_attitude[3]
		initial[RB.RATE] = 0.0
		initial[RB.RATE + 2] = 0.0
	session.start.state = initial
	session.reset()
	var deflections: Dictionary = session._deflections(session.sim.aux)
	var elevator_up_deg := -rad_to_deg(float(deflections.elevator))
	var initial_state: PackedFloat64Array = session.sim.state.duplicate()
	var initial_wind: PackedFloat64Array = session.wind_at(0.0)
	var initial_down_m: float = session.sim.state[RB.POS + 2]
	var initial_rpm: float = session.sim.aux[0] if not session.sim.aux.is_empty() else NAN

	_run_stats = {
		"stage_load_evaluations": 0,
		"global_attached_stages": 0,
		"first_local_flow_time_s": -1.0,
		"max_local_flow_weight": 0.0,
		"max_abs_stage_fy_n": 0.0,
		"max_abs_stage_mx_nm": 0.0,
		"max_abs_stage_mz_nm": 0.0,
		"max_projected_stage_constraint_residual": 0.0,
		"max_preprojection_lateral_state_drift": 0.0,
		"projected_stage_calls": 0,
		"projected_lateral_load_calls": 0,
		"last_stage_my_nm": 0.0,
		"projected_jyy_kg_m2": float(session.aircraft.model.inertia[1]),
		"max_elevator_target_error_deg": 0.0,
		"min_elevator_up_deg": INF,
		"max_elevator_up_deg": -INF,
		"max_abs_roll_deg": 0.0,
		"max_abs_yaw_deg": 0.0,
		"max_abs_beta_deg": 0.0,
		"max_alpha_deg": -INF,
		"first_inverted_s": -1.0,
		"first_pitch_360_s": -1.0,
		"first_path_360_s": -1.0,
		"max_pitch_turns": 0.0,
		"max_path_turns": 0.0,
		"min_height_m": INF,
		"max_height_m": -INF,
		"max_pitch_rate_rad_s": 0.0,
		"max_abs_lateral_velocity_mps": 0.0,
		"max_abs_roll_rate_rad_s": 0.0,
		"max_abs_yaw_rate_rad_s": 0.0,
		"body_derivative_override_seen": false
	}
	_install_stage_observer(session, mode == "projected_longitudinal")
	if mode == "projected_longitudinal":
		session.sim.model.step_policy = func(s: PackedFloat64Array, t: float, dt: float, f: Callable, _k1: PackedFloat64Array) -> PackedFloat64Array:
			return _projected_rk4_step(s, t, dt, f)

	var history_end_tick := int(round(HISTORY_SECONDS * float(tick_rate)))
	var total_ticks := int(round(duration_s * float(tick_rate)))
	var rows: Array[Dictionary] = []
	var previous_pitch_raw := 2.0 * atan2(initial_state[RB.ATT + 2], initial_state[RB.ATT])
	var unwrapped_pitch := previous_pitch_raw
	var previous_path_raw := _path_angle(initial_state)
	var unwrapped_path := previous_path_raw
	var initial_path := previous_path_raw
	var initial_pitch := previous_pitch_raw
	var max_abs_pitch_turn := 0.0
	var max_abs_path_turn := 0.0
	var first_tick_nonzero_pitch := true
	for tick in range(1, total_ticks + 1):
		var fixture_tick: int = int(floor(float(tick - 1) * 240.0 / float(tick_rate))) + 1
		if replay_history and tick <= history_end_tick and sample_by_tick.has(fixture_tick):
			_raw_input = sample_by_tick[fixture_tick].duplicate(true)
		if not replay_history or tick > history_end_tick:
			_raw_input = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		session._physics_process(session.sim.dt())
		if replay_history and tick > history_end_tick:
			# Full throttle is a commanded state, not a held raw throttle-increase key.
			session.commands.throttle = 1.0
			session.sim.inputs = session._inputs()
		if session.sim.paused:
			break
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		var state: PackedFloat64Array = session.sim.state
		var time_s: float = session.sim.time()
		var attitude: PackedFloat64Array = RB._att(state)
		var euler: PackedFloat64Array = M.q_to_euler(attitude)
		var air: Dictionary = session.air_data(state, time_s)
		var current_deflections: Dictionary = session._deflections(session.sim.aux)
		var actual_elevator_up_deg := -rad_to_deg(float(current_deflections.elevator))
		var turn_pitch := 0.0
		if mode == "projected_longitudinal":
			var pitch_raw := 2.0 * atan2(state[RB.ATT + 2], state[RB.ATT])
			if not first_tick_nonzero_pitch:
				unwrapped_pitch += wrapf(pitch_raw - previous_pitch_raw, -PI, PI)
			previous_pitch_raw = pitch_raw
			first_tick_nonzero_pitch = false
			turn_pitch = (unwrapped_pitch - initial_pitch) / TAU
			max_abs_pitch_turn = maxf(max_abs_pitch_turn, absf(turn_pitch))
			if _run_stats.first_pitch_360_s < 0.0 and absf(turn_pitch) >= 1.0:
				_run_stats.first_pitch_360_s = time_s
		var world_velocity: PackedFloat64Array = M.q_rotate(attitude, RB._slice3(state, RB.VEL))
		var path_raw := _path_angle_from_world_velocity(world_velocity)
		var path_turn := 0.0
		if not first_tick_nonzero_pitch and M.sqrt_(world_velocity[0] * world_velocity[0] + world_velocity[2] * world_velocity[2]) > 0.25:
			unwrapped_path += wrapf(path_raw - previous_path_raw, -PI, PI)
			previous_path_raw = path_raw
			path_turn = (unwrapped_path - initial_path) / TAU
			max_abs_path_turn = maxf(max_abs_path_turn, absf(path_turn))
			if _run_stats.first_path_360_s < 0.0 and absf(path_turn) >= 1.0:
				_run_stats.first_path_360_s = time_s
		if _run_stats.first_inverted_s < 0.0 and M.q_rotate(attitude, M.v3(0.0, 0.0, 1.0))[2] < 0.0:
			_run_stats.first_inverted_s = time_s
		_run_stats.max_pitch_turns = max_abs_pitch_turn
		_run_stats.max_path_turns = max_abs_path_turn
		_run_stats.max_alpha_deg = maxf(float(_run_stats.max_alpha_deg), rad_to_deg(float(air.alpha)))
		_run_stats.max_abs_beta_deg = maxf(float(_run_stats.max_abs_beta_deg), absf(rad_to_deg(float(air.beta))))
		_run_stats.min_height_m = minf(float(_run_stats.min_height_m), -state[RB.POS + 2])
		_run_stats.max_height_m = maxf(float(_run_stats.max_height_m), -state[RB.POS + 2])
		_run_stats.max_pitch_rate_rad_s = maxf(float(_run_stats.max_pitch_rate_rad_s), absf(state[RB.RATE + 1]))
		_run_stats.max_abs_lateral_velocity_mps = maxf(float(_run_stats.max_abs_lateral_velocity_mps), absf(state[RB.VEL + 1]))
		_run_stats.max_abs_roll_rate_rad_s = maxf(float(_run_stats.max_abs_roll_rate_rad_s), absf(state[RB.RATE]))
		_run_stats.max_abs_yaw_rate_rad_s = maxf(float(_run_stats.max_abs_yaw_rate_rad_s), absf(state[RB.RATE + 2]))
		_run_stats.max_abs_roll_deg = maxf(float(_run_stats.max_abs_roll_deg), absf(rad_to_deg(float(euler[2]))))
		_run_stats.max_abs_yaw_deg = maxf(float(_run_stats.max_abs_yaw_deg), absf(rad_to_deg(float(euler[0]))))
		_run_stats.min_elevator_up_deg = minf(float(_run_stats.min_elevator_up_deg), actual_elevator_up_deg)
		_run_stats.max_elevator_up_deg = maxf(float(_run_stats.max_elevator_up_deg), actual_elevator_up_deg)
		_run_stats.max_elevator_target_error_deg = maxf(float(_run_stats.max_elevator_target_error_deg), absf(actual_elevator_up_deg - ELEVATOR_UP_DEG))
		if tick % tick_rate == 0 or tick == total_ticks:
			var lag_index: int = session.downwash_index()
			var downwash_cl: float = session.sim.aux[lag_index] if lag_index >= 0 and lag_index < session.sim.aux.size() else NAN
			var local_weight := Aero.local_flow_weight(state, air, current_deflections, session.aircraft.model, downwash_cl)
			rows.append({
				"time_s": time_s,
				"height_m": -state[RB.POS + 2],
				"u_mps": state[RB.VEL],
				"w_mps": state[RB.VEL + 2],
				"speed_mps": air.V,
				"alpha_deg": rad_to_deg(float(air.alpha)),
				"beta_deg": rad_to_deg(float(air.beta)),
				"euler_pitch_deg_wrapped": rad_to_deg(float(euler[1])),
				"pitch_unwrapped_deg": rad_to_deg(unwrapped_pitch - initial_pitch) if mode == "projected_longitudinal" else null,
				"pitch_turns": turn_pitch if mode == "projected_longitudinal" else null,
				"flight_path_angle_deg_wrapped": rad_to_deg(path_raw),
				"flight_path_angle_unwrapped_deg": rad_to_deg(unwrapped_path - initial_path),
				"flight_path_turns": path_turn,
				"q_rad_s": state[RB.RATE + 1],
				"p_rad_s": state[RB.RATE],
				"r_rad_s": state[RB.RATE + 2],
				"v_mps": state[RB.VEL + 1],
				"roll_deg": rad_to_deg(float(euler[2])),
				"yaw_deg": rad_to_deg(float(euler[0])),
				"throttle": session.sim.inputs[3],
				"raw_throttle": _raw_input.throttle,
				"elevator_up_deg": actual_elevator_up_deg,
				"local_flow_weight": local_weight,
				"inverted": M.q_rotate(attitude, M.v3(0.0, 0.0, 1.0))[2] < 0.0
			})

	var completed_ticks: int = session.sim.tick
	var result := {
		"case": case_name,
		"mode": mode,
		"tick_rate_hz": tick_rate,
		"duration_requested_s": duration_s,
		"duration_completed_s": session.sim.time(),
		"tick_count": completed_ticks,
		"completed": completed_ticks == total_ticks,
		"setup_ok": true,
		"fault": session.sim.fault_reason,
		"paused": session.sim.paused,
		"initial_state": {
			"north_m": initial_state[RB.POS], "east_m": initial_state[RB.POS + 1], "down_m": initial_down_m,
			"u_mps": initial_state[RB.VEL], "v_mps": initial_state[RB.VEL + 1], "w_mps": initial_state[RB.VEL + 2],
			"pitch_deg": rad_to_deg(2.0 * atan2(initial_state[RB.ATT + 2], initial_state[RB.ATT])),
			"yaw_deg": rad_to_deg(float(M.q_to_euler(RB._att(initial_state))[0])),
			"throttle_start": session.start.get("throttle", NAN),
			"rpm_start": initial_rpm,
			"elevator_up_deg": elevator_up_deg,
			"wind_ned_mps": Array(initial_wind)
		},
		"events": {
			"first_body_inverted_s": _run_stats.first_inverted_s,
			"first_unwrapped_pitch_360_s": _run_stats.first_pitch_360_s,
			"first_unwrapped_flight_path_360_s": _run_stats.first_path_360_s,
			"max_abs_unwrapped_pitch_turns": _run_stats.max_pitch_turns,
			"max_abs_unwrapped_flight_path_turns": _run_stats.max_path_turns
		},
		"limits": {
			"max_elevator_target_error_deg": _run_stats.max_elevator_target_error_deg,
			"elevator_up_range_deg": [_run_stats.min_elevator_up_deg, _run_stats.max_elevator_up_deg],
			"min_height_m": _run_stats.min_height_m,
			"max_height_m": _run_stats.max_height_m,
			"max_alpha_deg": _run_stats.max_alpha_deg,
			"max_abs_beta_deg": _run_stats.max_abs_beta_deg,
			"max_pitch_rate_rad_s": _run_stats.max_pitch_rate_rad_s,
			"max_abs_roll_deg": _run_stats.max_abs_roll_deg,
			"max_abs_yaw_deg": _run_stats.max_abs_yaw_deg,
			"max_abs_lateral_velocity_mps": _run_stats.max_abs_lateral_velocity_mps,
			"max_abs_roll_rate_rad_s": _run_stats.max_abs_roll_rate_rad_s,
			"max_abs_yaw_rate_rad_s": _run_stats.max_abs_yaw_rate_rad_s
		},
		"stage_audit": {
			"load_evaluations": _run_stats.stage_load_evaluations,
			"global_attached_stage_fraction": float(_run_stats.global_attached_stages) / maxf(1.0, float(_run_stats.stage_load_evaluations)),
			"first_local_flow_time_s": _run_stats.first_local_flow_time_s,
			"max_local_flow_weight": _run_stats.max_local_flow_weight,
			"max_abs_production_stage_fy_n": _run_stats.max_abs_stage_fy_n,
			"max_abs_production_stage_mx_nm": _run_stats.max_abs_stage_mx_nm,
			"max_abs_production_stage_mz_nm": _run_stats.max_abs_stage_mz_nm,
			"projected_stage_calls": _run_stats.projected_stage_calls,
			"max_projected_stage_constraint_residual": _run_stats.max_projected_stage_constraint_residual,
			"max_preprojection_lateral_state_drift": _run_stats.max_preprojection_lateral_state_drift,
			"projected_lateral_load_calls": _run_stats.projected_lateral_load_calls,
			"body_derivative_override_seen": _run_stats.body_derivative_override_seen,
			"projected_derivative_rebuild": mode == "projected_longitudinal",
			"projected_jyy_kg_m2": _run_stats.projected_jyy_kg_m2
		},
		"telemetry_1hz": rows
	}
	session.free()
	return result


func _install_stage_observer(session: Node, project_lateral: bool) -> void:
	var sim = session.sim
	if sim.model.stage.is_valid():
		var original_joint: Callable = sim.model.stage
		sim.model.stage = func(s: PackedFloat64Array, continuous: PackedFloat64Array, stage_t: float) -> Dictionary:
			var candidate: Dictionary = original_joint.call(s, continuous, stage_t)
			if not candidate.has("loads") or not candidate.loads is PackedFloat64Array or candidate.loads.size() != 6:
				return candidate
			_record_stage(session, s, stage_t, candidate.loads)
			if candidate.has("body_derivative"):
				_run_stats.body_derivative_override_seen = true
			if not project_lateral:
				return candidate
			var projected: Dictionary = candidate.duplicate()
			var stage_loads: PackedFloat64Array = candidate.loads.duplicate()
			_project_lateral_loads(stage_loads)
			projected.loads = stage_loads
			return projected
		return
	if sim.model.block_loads.is_valid():
		var original_continuous_loads: Callable = sim.model.block_loads
		sim.model.block_loads = func(s: PackedFloat64Array, continuous: PackedFloat64Array, stage_t: float) -> PackedFloat64Array:
			var stage_loads: PackedFloat64Array = original_continuous_loads.call(s, continuous, stage_t)
			_record_stage(session, s, stage_t, stage_loads)
			if project_lateral and stage_loads.size() == 6:
				_project_lateral_loads(stage_loads)
			return stage_loads
		return
	var original_loads: Callable = sim.model.loads
	sim.model.loads = func(s: PackedFloat64Array, stage_t: float) -> PackedFloat64Array:
		var stage_loads: PackedFloat64Array = original_loads.call(s, stage_t)
		_record_stage(session, s, stage_t, stage_loads)
		if project_lateral and stage_loads.size() == 6:
			_project_lateral_loads(stage_loads)
		return stage_loads


func _record_stage(session: Node, s: PackedFloat64Array, stage_t: float, production_loads: PackedFloat64Array) -> void:
	if production_loads.size() != 6:
		return
	_run_stats.stage_load_evaluations += 1
	_run_stats.last_stage_my_nm = production_loads[4]
	_run_stats.max_abs_stage_fy_n = maxf(float(_run_stats.max_abs_stage_fy_n), absf(production_loads[1]))
	_run_stats.max_abs_stage_mx_nm = maxf(float(_run_stats.max_abs_stage_mx_nm), absf(production_loads[3]))
	_run_stats.max_abs_stage_mz_nm = maxf(float(_run_stats.max_abs_stage_mz_nm), absf(production_loads[5]))
	var air: Dictionary = session.air_data(s, stage_t)
	var deflections: Dictionary = session._deflections(session.sim.aux)
	var lag_index: int = session.downwash_index()
	var downwash_cl: float = session.sim.aux[lag_index] if lag_index >= 0 and lag_index < session.sim.aux.size() else NAN
	var weight: float = Aero.local_flow_weight(s, air, deflections, session.aircraft.model, downwash_cl)
	if weight <= 1e-12:
		_run_stats.global_attached_stages += 1
	elif _run_stats.first_local_flow_time_s < 0.0:
		_run_stats.first_local_flow_time_s = stage_t
	_run_stats.max_local_flow_weight = maxf(float(_run_stats.max_local_flow_weight), weight)


func _project_lateral_loads(loads: PackedFloat64Array) -> void:
	# Constraint reactions cancel lateral force and roll/yaw moments while preserving every production load in the audit.
	if absf(loads[1]) > 0.0 or absf(loads[3]) > 0.0 or absf(loads[5]) > 0.0:
		_run_stats.projected_lateral_load_calls += 1
	loads[1] = 0.0
	loads[3] = 0.0
	loads[5] = 0.0


func _projected_rk4_step(s: PackedFloat64Array, t: float, dt: float, f: Callable) -> PackedFloat64Array:
	var start := _project_stage_state(s)
	var projected_f := func(stage_state: PackedFloat64Array, stage_time: float) -> PackedFloat64Array:
		var constrained_state := _project_stage_state(stage_state)
		var derivative: PackedFloat64Array = f.call(constrained_state, stage_time)
		if derivative.size() >= RB.SIZE:
			# The no-p/r constraint supplies the missing lateral reaction moments. For p=r=0,
			# the y-axis Euler equation is My = Jyy*qdot; Ixz does not enter this row.
			derivative[RB.RATE] = 0.0
			derivative[RB.RATE + 1] = _run_stats.last_stage_my_nm / _run_stats.projected_jyy_kg_m2
			derivative[RB.RATE + 2] = 0.0
		return derivative
	var k1_projected: PackedFloat64Array = projected_f.call(start, t)
	var k2_state := _project_stage_state(Integrator.axpy(start, dt / 2.0, k1_projected))
	var k2: PackedFloat64Array = projected_f.call(k2_state, t + dt / 2.0)
	var k3_state := _project_stage_state(Integrator.axpy(start, dt / 2.0, k2))
	var k3: PackedFloat64Array = projected_f.call(k3_state, t + dt / 2.0)
	var k4_state := _project_stage_state(Integrator.axpy(start, dt, k3))
	var k4: PackedFloat64Array = projected_f.call(k4_state, t + dt)
	var out: PackedFloat64Array = Integrator._finish_step(start, dt, k1_projected, k2, k3, k4)
	return _project_stage_state(out)


func _project_stage_state(source: PackedFloat64Array) -> PackedFloat64Array:
	var projected := source.duplicate()
	if projected.size() < RB.SIZE:
		return PackedFloat64Array()
	var preprojection_residual := maxf(absf(projected[RB.VEL + 1]), maxf(absf(projected[RB.RATE]), absf(projected[RB.RATE + 2])))
	preprojection_residual = maxf(preprojection_residual, maxf(absf(projected[RB.ATT + 1]), absf(projected[RB.ATT + 3])))
	_run_stats.max_preprojection_lateral_state_drift = maxf(float(_run_stats.max_preprojection_lateral_state_drift), preprojection_residual)
	_run_stats.projected_stage_calls += 1
	projected[RB.VEL + 1] = 0.0
	projected[RB.ATT + 1] = 0.0
	projected[RB.ATT + 3] = 0.0
	projected[RB.RATE] = 0.0
	projected[RB.RATE + 2] = 0.0
	var qnorm := M.sqrt_(projected[RB.ATT] * projected[RB.ATT] + projected[RB.ATT + 2] * projected[RB.ATT + 2])
	if qnorm <= 1e-15:
		return PackedFloat64Array()
	projected[RB.ATT] /= qnorm
	projected[RB.ATT + 2] /= qnorm
	var residual := maxf(absf(projected[RB.VEL + 1]), maxf(absf(projected[RB.RATE]), absf(projected[RB.RATE + 2])))
	residual = maxf(residual, maxf(absf(projected[RB.ATT + 1]), absf(projected[RB.ATT + 3])))
	_run_stats.max_projected_stage_constraint_residual = maxf(float(_run_stats.max_projected_stage_constraint_residual), residual)
	return projected


func _path_angle(state: PackedFloat64Array) -> float:
	var world_velocity: PackedFloat64Array = M.q_rotate(RB._att(state), RB._slice3(state, RB.VEL))
	return _path_angle_from_world_velocity(world_velocity)


func _path_angle_from_world_velocity(world_velocity: PackedFloat64Array) -> float:
	return atan2(-world_velocity[2], world_velocity[0])


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unavailable"
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return "unavailable"
	hash.update(file.get_buffer(file.get_length()))
	return hash.finish().hex_encode()
