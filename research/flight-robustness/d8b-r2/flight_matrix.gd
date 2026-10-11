## D8b-R2b reusable research flight matrix.
## Run through run_matrix.py so each run gets immutable model/source fingerprints and a fresh output directory.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Commands := preload("res://input/commands.gd")
const Aero := preload("res://physics/aero.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const TRACE_HEADER := [
	"case_id", "source_hash_sha256", "sample_phase", "tick", "state_time_s", "load_time_s", "scenario_phase",
	"airspeed_mps", "qbar_pa", "alpha_rad", "alpha_deg", "beta_rad", "beta_deg",
	"p_radps", "q_radps", "r_radps", "normal_load_factor_aero", "normal_load_factor_total",
	"raw_roll", "raw_pitch", "raw_yaw", "raw_throttle",
	"shaped_roll", "shaped_pitch", "shaped_yaw", "shaped_throttle",
	"trim_roll", "trim_pitch", "trim_yaw", "trimmed_roll", "trimmed_pitch", "trimmed_yaw",
	"servo_roll_normalized", "servo_pitch_normalized", "servo_yaw_normalized",
	"servo_aileron_right_deg", "servo_aileron_left_deg", "servo_elevator_deg", "servo_rudder_deg",
	"rpm", "engine_running", "wing_local_blend", "cross_track_m",
	"aero_fx_n", "aero_fy_n", "aero_fz_n", "aero_mx_nm", "aero_my_nm", "aero_mz_nm",
	"prop_fx_n", "prop_fy_n", "prop_fz_n", "prop_mx_nm", "prop_my_nm", "prop_mz_nm",
	"total_fx_n", "total_fy_n", "total_fz_n", "total_mx_nm", "total_my_nm", "total_mz_nm",
	"rotor_hx_kgm2ps", "rotor_hy_kgm2ps", "rotor_hz_kgm2ps",
	"gyro_delta_pdot_radps2", "gyro_delta_qdot_radps2", "gyro_delta_rdot_radps2",
	"north_m", "east_m", "down_m", "u_mps", "v_mps", "w_mps", "qw", "qx", "qy", "qz",
	"wing_strip_available", "wing_strip_json", "finite_sample", "error",
]

const CASES := [
	{"id": "v15_progressive_positive_trim", "entry_speed": 15.0, "style": "progressive", "direction": 1.0, "power": "trim"},
	{"id": "v25_progressive_positive_trim", "entry_speed": 25.0, "style": "progressive", "direction": 1.0, "power": "trim"},
	{"id": "v30_progressive_positive_trim", "entry_speed": 30.0, "style": "progressive", "direction": 1.0, "power": "trim"},
	{"id": "v15_abrupt_positive_trim", "entry_speed": 15.0, "style": "abrupt", "direction": 1.0, "power": "trim"},
	{"id": "v25_abrupt_positive_trim", "entry_speed": 25.0, "style": "abrupt", "direction": 1.0, "power": "trim"},
	{"id": "v30_abrupt_positive_trim", "entry_speed": 30.0, "style": "abrupt", "direction": 1.0, "power": "trim"},
	{"id": "v25_progressive_negative_trim", "entry_speed": 25.0, "style": "progressive", "direction": -1.0, "power": "trim"},
	{"id": "v25_abrupt_negative_trim", "entry_speed": 25.0, "style": "abrupt", "direction": -1.0, "power": "trim"},
	{"id": "v25_progressive_positive_idle", "entry_speed": 25.0, "style": "progressive", "direction": 1.0, "power": "idle"},
	{"id": "v25_progressive_positive_full", "entry_speed": 25.0, "style": "progressive", "direction": 1.0, "power": "full"},
	{"id": "v25_abrupt_positive_idle", "entry_speed": 25.0, "style": "abrupt", "direction": 1.0, "power": "idle"},
	{"id": "v25_abrupt_positive_full", "entry_speed": 25.0, "style": "abrupt", "direction": 1.0, "power": "full"},
	{"id": "v25_progressive_seed_plus_0001", "entry_speed": 25.0, "style": "progressive", "direction": 1.0, "power": "trim", "seed_p": 0.0001},
	{"id": "v25_progressive_seed_minus_0001", "entry_speed": 25.0, "style": "progressive", "direction": 1.0, "power": "trim", "seed_p": -0.0001},
	{"id": "v25_abrupt_seed_plus_0001", "entry_speed": 25.0, "style": "abrupt", "direction": 1.0, "power": "trim", "seed_p": 0.0001},
	{"id": "v25_abrupt_seed_minus_0001", "entry_speed": 25.0, "style": "abrupt", "direction": 1.0, "power": "trim", "seed_p": -0.0001},
	{"id": "v15_trim_accelerate_25_preserve_trim", "entry_speed": 15.0, "target_speed": 25.0, "style": "progressive", "direction": 1.0, "power": "full", "accelerate": true},
]

var _options := {}
var _run_manifest := {}


func _initialize() -> void:
	_options = _parse_options(OS.get_cmdline_user_args())
	call_deferred("run")


func run() -> void:
	var output_dir := str(_options.get("output_dir", ""))
	if output_dir.is_empty():
		printerr("flight_matrix: --output-dir is required; invoke through run_matrix.py")
		quit(2)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_error != OK:
		printerr("flight_matrix: cannot create output directory (%d): %s" % [mkdir_error, output_dir])
		quit(2)
	var model_path := str(_options.get("aircraft_json", ""))
	if model_path.is_empty():
		printerr("flight_matrix: --aircraft-json is required")
		quit(2)
	var selected := _selected_cases(str(_options.get("case_filter", "")))
	var label := str(_options.get("label", "run"))
	var hz := int(_options.get("hz", 240))
	if hz < 30 or hz > 1920:
		printerr("flight_matrix: --hz must be in [30, 1920]")
		quit(2)
	Engine.physics_ticks_per_second = hz
	_run_manifest = {
		"format": "openrc-d8b-r2b-matrix-v1",
		"label": label,
		"source_hash_sha256": str(_options.get("source_hash", "")),
		"model_path": model_path,
		"model_source_sha256": str(_options.get("model_hash", "")),
		"physics_hz": hz,
		"sample_contract": "One row at the initial boundary, then one row after each FlightSession input-shaping call and Simulation.step(). State and loads are both timestamped at that boundary; loads are recomputed from the boundary state/current servo and RPM values, not retained RK4 intermediate stages.",
		"input_contract": "FlightSession._physics_process samples the case raw target and calls the real Commands.step_commands slew limiter; FlightSession._inputs adds trims and clamps; Simulation.step applies actual servo/rpm state updates.",
		"model_identity": {},
		"wing_strip_api": "Aero.wing_strip_loads; local wing strips before global/local blend and excluding tail, propulsion, and gyro.",
		"cases": [],
	}
	for index in selected.size():
		var spec: Dictionary = selected[index].duplicate(true)
		var result := _run_case(spec, index, model_path, output_dir, hz, label)
		_run_manifest.cases.append(result)
		if _run_manifest.model_identity.is_empty() and not result.get("aircraft_identity", {}).is_empty():
			_run_manifest.model_identity = result.aircraft_identity
		print("matrix case %s: %s (%d/%d samples, complete=%s, finite=%s)" % [
			str(spec.get("id", "case")), str(result.get("status", "error")),
			int(result.get("samples", 0)), int(result.get("expected_samples", 0)),
			str(result.get("complete", false)), str(result.get("finite", false)),
		])
	var manifest_path := output_dir.path_join("run_manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		printerr("flight_matrix: cannot write run manifest: " + manifest_path)
		quit(2)
	manifest_file.store_string(JSON.stringify(_run_manifest, "\t", true, true) + "\n")
	manifest_file.close()
	var run_complete := true
	for case_result: Dictionary in _run_manifest.cases:
		if not bool(case_result.get("complete", false)) or not bool(case_result.get("finite", false)):
			run_complete = false
	_run_manifest["complete"] = run_complete
	# Rewrite once with run-level completeness included.
	manifest_file = FileAccess.open(manifest_path, FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(_run_manifest, "\t", true, true) + "\n")
	manifest_file.close()
	quit(0 if run_complete else 1)


func _selected_cases(filter_text: String) -> Array:
	if filter_text.is_empty():
		return CASES.duplicate(true)
	var requested := filter_text.split(",", false)
	var chosen: Array = []
	for spec: Dictionary in CASES:
		if requested.has(str(spec.id)):
			chosen.append(spec.duplicate(true))
	return chosen


func _run_case(spec: Dictionary, index: int, model_path: String, output_dir: String, hz: int, label: String) -> Dictionary:
	var result := {
		"case_id": str(spec.get("id", "case_%d" % index)),
		"label": label,
		"scenario": spec.duplicate(true),
		"status": "error",
		"complete": false,
		"finite": false,
		"expected_samples": 0,
		"samples": 0,
		"error": "",
		"trace_file": "",
		"wing_strip_telemetry_available": false,
		"peak": {},
		"aircraft_identity": {},
	}
	var session = Session.new()
	session.input_enabled = true
	session.physics_enabled = true
	session.radio.connected = false
	session.setup(model_path)
	root.add_child(session)
	if not session.aircraft.get("ok", false) or not session.start.get("ok", false):
		result.error = str(session.start_error if not session.start_error.is_empty() else session.pause_reason)
		if result.error.is_empty():
			result.error = "aircraft setup or trim failed"
		session.free()
		return result
	var trim: Dictionary = session.trim_at(float(spec.get("entry_speed", 15.0)), "level")
	if not trim.get("ok", false):
		result.error = "entry trim failed: " + str(trim.get("message", "unknown trim error"))
		session.free()
		return result
	session.set_start_altitude(300.0)
	result.aircraft_identity = session.aircraft.get("input_identity", {}).duplicate(true)
	result["trim_speed_mps"] = float(spec.get("entry_speed", 15.0))
	result["trim"] = session.trims.duplicate(true)
	result["trim_throttle"] = float(session.start.get("throttle", NAN))
	result["trim_rpm"] = float(session.start.get("rpm", NAN))
	result["model_id"] = str(session.aircraft.model.get("id", ""))
	result["duration_s"] = float(spec.get("duration_s", 5.0))
	if bool(spec.get("accelerate", false)):
		result.duration_s = 18.0
	if _options.has("duration_s"):
		result.duration_s = float(_options.duration_s)
	session.reset()
	if not session._flight_ready() or session.sim.paused:
		result.error = "FlightSession reset did not produce an active flight: " + str(session.pause_reason)
		session.free()
		return result
	var seed_p := float(spec.get("seed_p", 0.0))
	if seed_p != 0.0:
		var seeded: PackedFloat64Array = session.sim.state.duplicate()
		seeded[RB.RATE] = seed_p
		if not session.sim.reset(seeded):
			result.error = "paired p-rate seed reset failed: " + str(session.sim.fault_reason)
			session.free()
			return result
	result["seed_p_radps"] = seed_p
	var scenario: Dictionary = spec.duplicate(true)
	scenario["trigger_time_s"] = -1.0
	scenario["pull_at_s"] = float(spec.get("pull_at_s", 0.25))
	scenario["release_at_s"] = float(spec.get("release_at_s", 2.25))
	scenario["progressive_ramp_s"] = float(spec.get("progressive_ramp_s", 0.8))
	session.read_raw = func() -> Dictionary:
		return _raw_target(scenario, session, session.sim.time())
	var initial_state: PackedFloat64Array = session.sim.state.duplicate()
	var initial_attitude := RB._att(initial_state)
	var heading := M.q_rotate(initial_attitude, M.v3(1.0, 0.0, 0.0))
	var lateral := M.v3(-heading[1], heading[0], 0.0)
	var lateral_norm := M.sqrt_(M.dot(lateral, lateral))
	if lateral_norm > 1e-12:
		lateral = M.scale(lateral, 1.0 / lateral_norm)
	else:
		lateral = M.v3(0.0, 1.0, 0.0)
	var csv_path := output_dir.path_join(str(result.case_id) + ".csv")
	var trace := FileAccess.open(csv_path, FileAccess.WRITE)
	if trace == null:
		result.error = "cannot open trace file: " + csv_path
		session.free()
		return result
	trace.store_line(",".join(TRACE_HEADER))
	var expected_ticks := roundi(float(result.duration_s) * float(hz))
	result.expected_samples = expected_ticks + 1
	result.trace_file = csv_path.get_file()
	var peak := {
		"max_airspeed_mps": 0.0,
		"max_alpha_rad": -INF,
		"max_abs_beta_rad": 0.0,
		"max_abs_p_radps": 0.0,
		"max_abs_q_radps": 0.0,
		"max_abs_r_radps": 0.0,
		"max_abs_cross_track_m": 0.0,
		"max_normal_load_factor_aero": -INF,
		"max_normal_load_factor_total": -INF,
		"min_altitude_m": INF,
	}
	var finite_run := true
	var error_text := ""
	for step_index in range(expected_ticks + 1):
		if step_index > 0:
			session._physics_process(session.sim.dt())
			session.sim.step()
		var tick_state: PackedFloat64Array = session.sim.state
		var tick_time: float = session.sim.time()
		var row := _make_row(session, scenario, tick_state, tick_time, lateral, str(_options.get("source_hash", "")))
		var sample_finite := bool(row.finite_sample)
		finite_run = finite_run and sample_finite
		if not sample_finite:
			error_text = "nonfinite telemetry at tick %d" % int(session.sim.tick)
		row["error"] = str(session.sim.fault_reason)
		if not str(session.sim.fault_reason).is_empty():
			error_text = str(session.sim.fault_reason)
		var values: Array[String] = []
		for field: String in TRACE_HEADER:
			values.append(_csv(row.get(field, "")))
		trace.store_line(",".join(values))
		result.samples = int(result.samples) + 1
		_peak_sample(peak, row)
		if not finite_run or not str(session.sim.fault_reason).is_empty():
			break
	trace.close()
	result.peak = peak
	result["final_state"] = Array(session.sim.state)
	result["final_time_s"] = session.sim.time()
	result["final_airspeed_mps"] = float(session.air_data(session.sim.state, session.sim.time()).V)
	result["final_pull_trigger_time_s"] = float(scenario.get("trigger_time_s", -1.0))
	result["wing_strip_telemetry_available"] = Aero.wing_strip_loads(session.sim.state, session.air_data(session.sim.state),
		session._deflections(session.sim.aux), session.aircraft.model, session.air_density()).size() > 0
	result["finite"] = finite_run
	result["error"] = error_text
	result["complete"] = finite_run and error_text.is_empty() and int(result.samples) == int(result.expected_samples) \
		and bool(result.wing_strip_telemetry_available)
	if bool(spec.get("accelerate", false)) and float(result.final_pull_trigger_time_s) < 0.0:
		result.complete = false
		result.error = "target airspeed %.3f m/s was not reached from the original %.3f m/s trim" % [
			float(spec.get("target_speed", 25.0)), float(spec.get("entry_speed", 15.0)),
		]
	result.status = "complete" if result.complete else ("finite_incomplete" if result.finite else "nonfinite")
	session.free()
	return result


func _raw_target(spec: Dictionary, session: Node, time_s: float) -> Dictionary:
	var accelerate := bool(spec.get("accelerate", false))
	if accelerate and float(spec.get("trigger_time_s", -1.0)) < 0.0:
		var current_air: Dictionary = session.air_data(session.sim.state, time_s)
		if float(current_air.V) >= float(spec.get("target_speed", 25.0)):
			spec["trigger_time_s"] = time_s
			spec["pull_at_s"] = time_s
			spec["release_at_s"] = time_s + 2.0
	var trigger_time := float(spec.get("trigger_time_s", -1.0))
	var pull_at := float(spec.get("pull_at_s", 0.25))
	var release_at := float(spec.get("release_at_s", 2.25))
	var ramp_s := float(spec.get("progressive_ramp_s", 0.8))
	var pitch := 0.0
	if accelerate and trigger_time < 0.0:
		pitch = 0.0
	elif time_s >= pull_at and time_s < release_at:
		var ramp_progress := 1.0
		if str(spec.get("style", "abrupt")) == "progressive":
			ramp_progress = clampf((time_s - pull_at) / maxf(ramp_s, 1e-9), 0.0, 1.0)
		pitch = float(spec.get("direction", 1.0)) * ramp_progress
	var throttle_target := 0.0
	match str(spec.get("power", "trim")):
		"idle": throttle_target = -1.0
		"full": throttle_target = 1.0
		_: throttle_target = 1.0 if accelerate else 0.0
	return {"roll": 0.0, "pitch": pitch, "yaw": 0.0, "throttle": throttle_target}


func _make_row(session: Node, scenario: Dictionary, state: PackedFloat64Array, time_s: float, lateral: PackedFloat64Array,
		source_hash: String) -> Dictionary:
	var aux: PackedFloat64Array = session.sim.aux
	var air: Dictionary = session.air_data(state, time_s)
	var deflections: Dictionary = session._deflections(aux)
	var model: Dictionary = session.aircraft.model
	var rho: float = session.air_density()
	var lag_index: int = session.downwash_index()
	var downwash_cl: float = aux[lag_index] if lag_index >= 0 and lag_index < aux.size() else NAN
	var rotor: PackedFloat64Array = session.rotor_momentum(aux)
	var evaluated: Dictionary = Dynamics.evaluate(state, model, deflections, aux[session.AUX_RPM], rho,
		session.wind_at(time_s), session.sim.gravity, rotor, downwash_cl)
	var actual_loads: PackedFloat64Array = session._loads(state, time_s)
	var aero: PackedFloat64Array = evaluated.aero_loads
	var prop: PackedFloat64Array = evaluated.propulsion_loads
	var rates: PackedFloat64Array = evaluated.derivative
	var no_gyro: PackedFloat64Array = RB.derivative(state, session.sim.mass, session.sim.inertia,
		RB.inertia_inverse(session.sim.inertia), M.v3(evaluated.loads[0], evaluated.loads[1], evaluated.loads[2]),
		M.v3(evaluated.loads[3], evaluated.loads[4], evaluated.loads[5]), session.sim.gravity, M.v3(0.0, 0.0, 0.0))
	var surfaces := Commands.surface_deflections_deg({
		"roll": aux[session.AUX_SERVO], "pitch": aux[session.AUX_SERVO + 1], "yaw": aux[session.AUX_SERVO + 2],
	}, session.throws_deg())
	var strips: Array = Aero.wing_strip_loads(state, air, deflections, model, rho, downwash_cl)
	var strip_available := not strips.is_empty()
	var cross_track := M.dot(M.sub(RB._slice3(state, RB.POS), RB._slice3(session.start.state, RB.POS)), lateral)
	var flow_blend: float = Aero.local_flow_weight(state, air, deflections, model)
	var commands: Dictionary = session.commands
	var raw: Dictionary = session.raw
	var trims: Dictionary = session.trims
	var flown: Dictionary = session.flown_commands()
	var normal_aero := -float(aero[2]) / maxf(float(session.sim.mass) * float(session.sim.gravity), 1e-12)
	var normal_total := -float(actual_loads[2]) / maxf(float(session.sim.mass) * float(session.sim.gravity), 1e-12)
	var phase := _phase(scenario, time_s)
	var numbers: Array[float] = [
		time_s, float(air.V), float(air.qbar), float(air.alpha), float(air.beta),
		state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2], normal_aero, normal_total, cross_track,
		aero[0], aero[1], aero[2], aero[3], aero[4], aero[5], prop[0], prop[1], prop[2], prop[3], prop[4], prop[5],
		actual_loads[0], actual_loads[1], actual_loads[2], actual_loads[3], actual_loads[4], actual_loads[5],
		rotor[0], rotor[1], rotor[2],
		rates[RB.RATE] - no_gyro[RB.RATE], rates[RB.RATE + 1] - no_gyro[RB.RATE + 1], rates[RB.RATE + 2] - no_gyro[RB.RATE + 2],
	]
	for value: float in state:
		numbers.append(value)
	for value: float in [raw.roll, raw.pitch, raw.yaw, raw.throttle,
		commands.roll, commands.pitch, commands.yaw, commands.throttle,
		trims.roll, trims.pitch, trims.yaw,
		flown.roll, flown.pitch, flown.yaw, flown.throttle,
		aux[session.AUX_SERVO], aux[session.AUX_SERVO + 1], aux[session.AUX_SERVO + 2],
		surfaces.aileron_right, surfaces.aileron_left, surfaces.elevator, surfaces.rudder,
		aux[session.AUX_RPM]]:
		numbers.append(value)
	var row := {
		"case_id": str(scenario.get("id", "case")),
		"source_hash_sha256": source_hash,
		"sample_phase": "tick_boundary_after_step" if session.sim.tick > 0 else "initial_tick_boundary",
		"tick": int(session.sim.tick),
		"state_time_s": time_s,
		"load_time_s": time_s,
		"scenario_phase": phase,
		"airspeed_mps": air.V,
		"qbar_pa": air.qbar,
		"alpha_rad": air.alpha,
		"alpha_deg": rad_to_deg(air.alpha),
		"beta_rad": air.beta,
		"beta_deg": rad_to_deg(air.beta),
		"p_radps": state[RB.RATE], "q_radps": state[RB.RATE + 1], "r_radps": state[RB.RATE + 2],
		"normal_load_factor_aero": normal_aero,
		"normal_load_factor_total": normal_total,
		"raw_roll": raw.roll, "raw_pitch": raw.pitch, "raw_yaw": raw.yaw, "raw_throttle": raw.throttle,
		"shaped_roll": commands.roll, "shaped_pitch": commands.pitch, "shaped_yaw": commands.yaw, "shaped_throttle": commands.throttle,
		"trim_roll": trims.roll, "trim_pitch": trims.pitch, "trim_yaw": trims.yaw,
		"trimmed_roll": flown.roll, "trimmed_pitch": flown.pitch, "trimmed_yaw": flown.yaw,
		"servo_roll_normalized": aux[session.AUX_SERVO], "servo_pitch_normalized": aux[session.AUX_SERVO + 1],
		"servo_yaw_normalized": aux[session.AUX_SERVO + 2],
		"servo_aileron_right_deg": surfaces.aileron_right, "servo_aileron_left_deg": surfaces.aileron_left,
		"servo_elevator_deg": surfaces.elevator, "servo_rudder_deg": surfaces.rudder,
		"rpm": aux[session.AUX_RPM], "engine_running": bool(session.engine_running),
		"wing_local_blend": flow_blend, "cross_track_m": cross_track,
		"aero_fx_n": aero[0], "aero_fy_n": aero[1], "aero_fz_n": aero[2],
		"aero_mx_nm": aero[3], "aero_my_nm": aero[4], "aero_mz_nm": aero[5],
		"prop_fx_n": prop[0], "prop_fy_n": prop[1], "prop_fz_n": prop[2],
		"prop_mx_nm": prop[3], "prop_my_nm": prop[4], "prop_mz_nm": prop[5],
		"total_fx_n": actual_loads[0], "total_fy_n": actual_loads[1], "total_fz_n": actual_loads[2],
		"total_mx_nm": actual_loads[3], "total_my_nm": actual_loads[4], "total_mz_nm": actual_loads[5],
		"rotor_hx_kgm2ps": rotor[0], "rotor_hy_kgm2ps": rotor[1], "rotor_hz_kgm2ps": rotor[2],
		"gyro_delta_pdot_radps2": rates[RB.RATE] - no_gyro[RB.RATE],
		"gyro_delta_qdot_radps2": rates[RB.RATE + 1] - no_gyro[RB.RATE + 1],
		"gyro_delta_rdot_radps2": rates[RB.RATE + 2] - no_gyro[RB.RATE + 2],
		"north_m": state[0], "east_m": state[1], "down_m": state[2],
		"u_mps": state[3], "v_mps": state[4], "w_mps": state[5],
		"qw": state[6], "qx": state[7], "qy": state[8], "qz": state[9],
		"wing_strip_available": strip_available,
		"wing_strip_json": JSON.stringify(strips, "", true, true),
		"finite_sample": _all_finite(numbers) and _all_finite(aero) and _all_finite(prop) and _all_finite(actual_loads)
			and _all_finite(rotor) and _all_finite(no_gyro) and _all_finite(rates) and _variant_finite(strips),
		"error": "",
	}
	return row


func _phase(spec: Dictionary, time_s: float) -> String:
	var trigger_time := float(spec.get("trigger_time_s", -1.0))
	if bool(spec.get("accelerate", false)) and trigger_time < 0.0:
		return "accelerating_to_target"
	var pull_at := float(spec.get("pull_at_s", 0.25))
	var release_at := float(spec.get("release_at_s", 2.25))
	if time_s < pull_at:
		return "trimmed_entry"
	if time_s < release_at:
		if str(spec.get("style", "abrupt")) == "progressive" and time_s < pull_at + float(spec.get("progressive_ramp_s", 0.8)):
			return "progressive_pull"
		return "full_pull"
	return "release_recovery"


func _peak_sample(peak: Dictionary, row: Dictionary) -> void:
	peak.max_airspeed_mps = maxf(float(peak.max_airspeed_mps), float(row.airspeed_mps))
	peak.max_alpha_rad = maxf(float(peak.max_alpha_rad), float(row.alpha_rad))
	peak.max_abs_beta_rad = maxf(float(peak.max_abs_beta_rad), absf(float(row.beta_rad)))
	peak.max_abs_p_radps = maxf(float(peak.max_abs_p_radps), absf(float(row.p_radps)))
	peak.max_abs_q_radps = maxf(float(peak.max_abs_q_radps), absf(float(row.q_radps)))
	peak.max_abs_r_radps = maxf(float(peak.max_abs_r_radps), absf(float(row.r_radps)))
	peak.max_abs_cross_track_m = maxf(float(peak.max_abs_cross_track_m), absf(float(row.cross_track_m)))
	peak.max_normal_load_factor_aero = maxf(float(peak.max_normal_load_factor_aero), float(row.normal_load_factor_aero))
	peak.max_normal_load_factor_total = maxf(float(peak.max_normal_load_factor_total), float(row.normal_load_factor_total))
	peak.min_altitude_m = minf(float(peak.min_altitude_m), -float(row.down_m))


func _all_finite(values: Variant) -> bool:
	for value: Variant in values:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return true


func _variant_finite(value: Variant) -> bool:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return is_finite(float(value))
	if typeof(value) == TYPE_DICTIONARY:
		for key: Variant in value:
			if not _variant_finite(value[key]):
				return false
		return true
	if typeof(value) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY]:
		for item: Variant in value:
			if not _variant_finite(item):
				return false
	return true


func _csv(value: Variant) -> String:
	var text := str(value)
	if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		text = JSON.stringify(float(value), "", true, true)
	if text.contains(",") or text.contains("\"") or text.contains("\n") or text.contains("\r"):
		return "\"" + text.replace("\"", "\"\"") + "\""
	return text


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result := {}
	for argument: String in arguments:
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var pair := argument.substr(2).split("=", true, 1)
		if pair.size() == 2:
			result[pair[0].replace("-", "_")] = pair[1]
	return result
