# Powertrain-only transplant comparison on the recorded Ugly Stik input history.
# The validated standard Stik runtime model supplies the airframe; only its already-derived propulsion branch is
# replaced by a branch from a separately validated 55AX or FS64V installation. This is a bounded research probe.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Weather := preload("res://physics/wind_config.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Aero := preload("res://physics/aero.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const REPLAY_TICKS := 3600 # 15 s at 240 Hz.
const HOLD_TICKS := 7200 # 30 s at the replay's final absolute throttle.
const REPORT_PATH := "res://../docs/research/flight-dynamics/climb-trim/powertrain-interventions.json"

var _raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source_hashes_before: Dictionary = _source_hashes()
	var input_path: String = get_script().resource_path.get_base_dir().path_join("ugly-loop-inputs.json")
	var input_bytes: PackedByteArray = FileAccess.get_file_as_bytes(input_path)
	assert(not input_bytes.is_empty(), "missing recorded Ugly Stik input fixture")
	var fixture: Dictionary = JSON.parse_string(input_bytes.get_string_from_utf8())
	assert(not fixture.is_empty() and fixture.has("samples"), "malformed recorded input fixture")
	var samples: Dictionary = {}
	var input_events: Array = []
	for row: Dictionary in fixture.samples:
		var tick: int = int(row.tick)
		if tick <= REPLAY_TICKS:
			samples[tick] = row
			input_events.append({tick = tick, time_s = float(tick) / 240.0, raw = row.raw.duplicate(true)})

	var base_data: Dictionary = AircraftData.load_file(AIRCRAFT_PATH)
	assert(base_data.get("ok", false), "standard Ugly Stik failed loader validation: %s" % str(base_data.get("errors", [])))
	var baseline: Dictionary = _run_case("legacy_61fx_apc_12x6", base_data, {}, samples, null, AIRCRAFT_PATH)
	assert(baseline.public_report.get("completed_45s", false),
		"baseline did not complete the full 45 s run: %s" % str(baseline.public_report))
	var throttle_history: PackedFloat64Array = baseline.absolute_throttle_history
	assert(throttle_history.size() == REPLAY_TICKS, "baseline throttle history must cover all replay ticks")
	var fixed_trim: Dictionary = baseline.fixed_trim
	var fixed_state: PackedFloat64Array = baseline.initial_state
	var fixed_aux: PackedFloat64Array = baseline.initial_servo_aux
	var fixed_start: Dictionary = baseline.start
	var fixed_elevator: float = float(baseline.public_report.initial_elevator_deg_up)

	var donors := [
		{name = "os_max_55ax_2t_apc_12x7", path = "res://data/aircraft/stik_glow_55ax_2t.json"},
		{name = "os_fs64v_4t_master_airscrew_14x6", path = "res://data/aircraft/stik_glow_fs64v_4t.json"},
	]
	var reports: Array = [baseline.public_report]
	for donor_spec: Dictionary in donors:
		var donor: Dictionary = AircraftData.load_file(donor_spec.path)
		assert(donor.get("ok", false), "%s failed loader validation: %s" % [donor_spec.name, str(donor.get("errors", []))])
		assert(donor.model.get("propulsion", {}).get("glow", {}).has("profile"),
			"%s did not resolve to a validated continuous glow installation" % donor_spec.name)
		var transplanted: Dictionary = base_data.duplicate(true)
		transplanted.model.propulsion = donor.model.propulsion.duplicate(true)
		var candidate: Dictionary = _run_case(donor_spec.name, transplanted, donor,
			samples, {trim = fixed_trim, state = fixed_state, servo_aux = fixed_aux,
				start = fixed_start, elevator = fixed_elevator, throttle = throttle_history}, donor_spec.path)
		reports.append(candidate.public_report)
	var source_hashes_after: Dictionary = _source_hashes()

	var report := {
		format = "openrc-powertrain-intervention-probe-v1",
		generated_utc = Time.get_datetime_string_from_system(true, true),
		fixture = {path = "research/flight-dynamics/climb-trim/ugly-loop-inputs.json",
			sha256 = _sha256(input_bytes), source = fixture.get("source", ""),
			last_fixture_tick = int(fixture.get("last_tick", 0)), replay_event_count = input_events.size(), events = input_events},
		method = {
			run = "15 s recorded raw user-input replay, followed by a 30 s neutral-stick hold at the final baseline absolute throttle command; all runs start at 500 m AGL in calm weather",
			initial_conditions = "candidate body state, airspeed, attitude, and actual elevator servo position are copied exactly from the standard-airframe baseline start; the standard baseline trim is held for all cases",
			throttle = "baseline absolute Session.commands.throttle is captured after each replay tick and copied tick-for-tick to donor runs, independent of each donor's startup trim; applied command arrays and maximum per-tick difference are recorded; hold uses the tick-3600 value",
			controls = "recorded raw pitch input is compared against zero; fixed elevator servo deflection and drift are reported separately",
			transplant = "only model.propulsion is replaced, using the runtime propulsion branch returned by AircraftData.load_file for each existing donor aircraft; standard Stik identity, airframe model, aero, controls, inventory, mass, inertia, geometry, and input_identity are retained",
			validation_scope = "standard and donor source aircraft each pass AircraftData.load_file. Donor runs are common-start diagnostics, not candidate qualification: the standard baseline body state and fixed trim replace donor startup values. The FS64V normal prepare path rejects its native trim with 'nonfinite iterated trim residual'; its separately marked baseline-seeded run is exploratory and does not pass or qualify that native start. The in-memory hybrid is not serialized/re-derived, so full-schema validation is not claimed.",
			mass = "sim.mass/inertia start from the standard airframe; continuous glow stages call GlowFlight.properties with standard-airframe mass/inertia and donor fuel installation. Effective mass/CG/inertia capture fuel depletion but exclude donor engine/propeller dry-mass change. Deltas are 1 s samples, not continuous extrema.",
			wash = "reports use the existing authored local-flow blend and downwash paths. No wake coefficient or geometry is introduced.",
			interpretation = "completed_45s means only that the specified diagnostic integration reached 45 s. Native-start acceptance is reported separately; donor common-start results do not establish native trim suitability. Early crash, pause, numerical fault, or fuel-state failure is recorded and never counted as a completed integration.",
		},
		weather = Weather.defaults(),
		fixed_baseline_trim = fixed_trim,
		absolute_throttle_history_replay = Array(throttle_history),
		hold_throttle_command = throttle_history[REPLAY_TICKS - 1],
		source_hashes_before = source_hashes_before,
		source_hashes_after = source_hashes_after,
		sources_unchanged_during_run = source_hashes_before == source_hashes_after,
		cases = reports,
	}
	var text: String = JSON.stringify(report, "\t", true) + "\n"
	var output := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	assert(output != null, "cannot write powertrain intervention report: %s" % REPORT_PATH)
	output.store_string(text)
	output.close()
	var summary: Array = []
	for item: Dictionary in reports:
		var tail_rows: Array = []
		for row_index: int in range(maxi(0, item.rows.size() - 3), item.rows.size()):
			tail_rows.append(item.rows[row_index])
		summary.append({case = item.case, completed_45s = item.completed_45s, crashed = item.crashed,
			fault = item.fault, first_inverted_s = item.first_inverted_s, max_height_m = item.max_height_m,
			min_height_m = item.min_height_m, final_height_m = item.rows[-1].height_m if not item.rows.is_empty() else NAN,
			initial_elevator_deg_up = item.initial_elevator_deg_up,
			max_abs_pitch_rate_q_rad_s = item.max_abs_pitch_rate_q_rad_s,
			max_sampled_effective_mass_delta_from_static_kg = item.max_sampled_effective_mass_delta_from_static_kg,
			absolute_throttle_history_sha256 = item.absolute_throttle_history_sha256,
			max_absolute_throttle_command_error = item.max_absolute_throttle_command_error,
			max_abs_raw_pitch_input = item.max_abs_raw_pitch_input,
			first_rows = item.rows.slice(0, mini(8, item.rows.size())), last_rows = tail_rows})
	print("POWERTRAIN_INTERVENTION_SUMMARY ", JSON.stringify({summary = summary, output_path = REPORT_PATH}))
	var integrations_completed: bool = reports.size() == 3 and reports.all(func(item: Dictionary) -> bool:
		return bool(item.get("completed_45s", false)) and str(item.get("fault", "")).is_empty() and not bool(item.get("crashed", false)))
	quit(0 if integrations_completed else 1)


func _run_case(case_name: String, data: Dictionary, donor: Dictionary, samples: Dictionary,
		shared: Variant, source_path: String) -> Dictionary:
	var session := Session.new()
	assert(session.setup_weather(Weather.defaults()), "could not configure calm weather")
	session.setup(AIRCRAFT_PATH, AIRCRAFT_ID, data)
	root.add_child(session)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.radio.connected = false
	session.rate_profile = "normal"
	_raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	session.read_raw = func() -> Dictionary: return _raw.duplicate()
	session.set_start_altitude(500.0)
	session.reset()
	var native_trim_result: Dictionary = session.start.duplicate(true)
	var startup_state: PackedFloat64Array = session.sim.state.duplicate()
	var forced_fixed_start := false
	if not session.start.get("ok", false) and shared != null:
		# Use a qualified baseline start only after this hybrid passed model/contact checks.
		# This isolates the requested fixed-trim response when the donor's native trim will not solve.
		session._commit_aircraft({data = data, start = shared.start.duplicate(true), trims = shared.trim.duplicate(true)})
		session.pause_reason = ""
		session.set_start_altitude(500.0)
		session.reset()
		forced_fixed_start = true
	assert(session.start.get("ok", false), "%s baseline-seeded start failed after native trim result %s" % [case_name, str(native_trim_result)])

	var native_start := {
		trim_pitch_command = float(session.trims.pitch),
		trim_roll_command = float(session.trims.roll),
		trim_yaw_command = float(session.trims.yaw),
		throttle_command = float(session.start.get("throttle", NAN)),
		start_rpm = float(session.start.get("rpm", NAN)),
		start_speed_mps = float(session.start.get("V", NAN)),
		native_trim_ok = native_trim_result.get("ok", false),
		native_trim_message = native_trim_result.get("message", ""),
		forced_fixed_start = forced_fixed_start,
		elevator_deg_up = _elevator_deg_up(session),
		model_mass_kg = float(session.aircraft.model.mass_kg),
		model_inertia_kg_m2 = Array(session.aircraft.model.inertia),
	}
	var startup_aux: PackedFloat64Array = session.sim.aux.duplicate()
	var startup_effective_mass: Dictionary = _mass_properties(session)
	var fixed_initial_state: PackedFloat64Array
	var fixed_initial_aux: PackedFloat64Array
	var fixed_baseline_trim: Dictionary
	var throttle_history := PackedFloat64Array()
	if shared == null:
		fixed_initial_state = startup_state.duplicate()
		fixed_initial_aux = PackedFloat64Array([startup_aux[1], startup_aux[2], startup_aux[3]])
		fixed_baseline_trim = session.trims.duplicate(true)
	else:
		fixed_initial_state = shared.state.duplicate()
		fixed_initial_aux = shared.servo_aux.duplicate()
		fixed_baseline_trim = shared.trim.duplicate(true)
		throttle_history = shared.throttle.duplicate()
		session.trims = fixed_baseline_trim.duplicate(true)
		var seeded_state: PackedFloat64Array = fixed_initial_state.duplicate()
		seeded_state[RB.POS + 2] = -500.0
		session.sim.state = seeded_state
		for axis: int in 3:
			session.sim.aux[Session.AUX_SERVO + axis] = fixed_initial_aux[axis]
		session._deflection_key = PackedFloat64Array()
		session.commands.roll = 0.0
		session.commands.pitch = 0.0
		session.commands.yaw = 0.0
		session.commands.throttle = throttle_history[0]
		session.sim.inputs = session._inputs()
		fixed_initial_state = seeded_state.duplicate()

	var initial_air: Dictionary = session.air_data(session.sim.state, session.sim.time())
	var initial_propulsion: Dictionary = _propulsion_diagnostics(session, initial_air)
	var initial_elevator: float = _elevator_deg_up(session)
	var initial_mass: Dictionary = _mass_properties(session)
	var rows: Array = []
	var max_pitch_rate := 0.0
	var max_dynamic_pressure := 0.0
	var max_height: float = -session.sim.state[RB.POS + 2]
	var min_height: float = max_height
	var min_speed: float = initial_air.V
	var max_speed: float = initial_air.V
	var max_elevator_drift := 0.0
	var max_abs_raw_pitch_input := 0.0
	var max_abs_throttle_error := 0.0
	var applied_throttle_history := PackedFloat64Array()
	var initial_elevator_delta := absf(initial_elevator - float(shared.elevator)) if shared != null else 0.0
	var first_inverted_s := -1.0
	var first_crash_s := -1.0
	var first_pause_s := -1.0
	var max_abs_stage_mass_delta := 0.0
	var max_abs_stage_cg_shift := 0.0
	var max_abs_stage_inertia_delta := 0.0
	var max_baseline_state_error := 0.0
	var inverted_ticks := 0
	var completed_ticks := 0
	var crash_snapshot := {}
	var fault := ""
	var sample_map: Dictionary = samples
	for tick: int in range(1, REPLAY_TICKS + HOLD_TICKS + 1):
		if tick <= REPLAY_TICKS and sample_map.has(tick):
			for key: String in _raw.keys():
				_raw[key] = sample_map[tick].raw[key]
		elif tick == REPLAY_TICKS + 1:
			# `read_raw` closes over this dictionary; mutate it in place for the neutral hold.
			for key: String in _raw.keys():
				_raw[key] = 0.0
		max_abs_raw_pitch_input = maxf(max_abs_raw_pitch_input, absf(float(_raw.pitch)))
		# In the candidate runs, use the captured absolute baseline throttle after normal stick processing.
		session._physics_process(session.sim.dt())
		if session.sim.paused:
			if first_pause_s < 0.0:
				first_pause_s = session.sim.time()
			fault = str(session.sim.fault_reason)
			break
		if shared == null and tick <= REPLAY_TICKS:
			throttle_history.append(float(session.commands.throttle))
			max_abs_throttle_error = maxf(max_abs_throttle_error, absf(float(session.commands.throttle) - throttle_history[tick - 1]))
		elif shared == null:
			var hold_command: float = throttle_history[REPLAY_TICKS - 1]
			session.commands.throttle = hold_command
			session.sim.inputs = session._inputs()
			max_abs_throttle_error = maxf(max_abs_throttle_error, absf(float(session.commands.throttle) - hold_command))
		elif shared != null:
			var absolute_command: float = throttle_history[tick - 1] if tick <= REPLAY_TICKS else throttle_history[REPLAY_TICKS - 1]
			session.commands.throttle = absolute_command
			session.sim.inputs = session._inputs()
			max_abs_throttle_error = maxf(max_abs_throttle_error, absf(float(session.commands.throttle) - absolute_command))
		applied_throttle_history.append(float(session.commands.throttle))
		session.sim.step()
		completed_ticks = tick
		fault = str(session.sim.fault_reason)
		var state: PackedFloat64Array = session.sim.state
		var attitude: PackedFloat64Array = RB._att(state)
		var inverted: bool = M.q_rotate(attitude, M.v3(0.0, 0.0, 1.0))[2] < 0.0
		if inverted:
			inverted_ticks += 1
			if first_inverted_s < 0.0:
				first_inverted_s = session.sim.time()
		if not session.crash.is_empty():
			if first_crash_s < 0.0:
				first_crash_s = session.sim.time()
			crash_snapshot = session.crash.duplicate(true)
		var air: Dictionary = session.air_data(state, session.sim.time())
		var deflections: Dictionary = session._deflections(session.sim.aux)
		var current_elevator: float = -rad_to_deg(deflections.elevator)
		max_elevator_drift = maxf(max_elevator_drift, absf(current_elevator - initial_elevator))
		max_pitch_rate = maxf(max_pitch_rate, absf(state[RB.RATE + 1]))
		max_dynamic_pressure = maxf(max_dynamic_pressure, float(air.qbar))
		max_height = maxf(max_height, -state[RB.POS + 2])
		min_height = minf(min_height, -state[RB.POS + 2])
		min_speed = minf(min_speed, float(air.V))
		max_speed = maxf(max_speed, float(air.V))
		var mass: Dictionary = _mass_properties(session)
		if mass.get("ok", false):
			# These maxima are accepted outer-step samples (240 Hz), not integrator-stage extrema.
			max_abs_stage_mass_delta = maxf(max_abs_stage_mass_delta, absf(float(mass.mass_kg) - float(session.sim.mass)))
			max_abs_stage_cg_shift = maxf(max_abs_stage_cg_shift, M.norm(mass.cg_body_m))
			max_abs_stage_inertia_delta = maxf(max_abs_stage_inertia_delta, _max_abs_diff(mass.inertia, session.sim.inertia))
		if tick % 240 == 0 or tick == REPLAY_TICKS or tick == REPLAY_TICKS + HOLD_TICKS:
			var wash: Dictionary = _wash_diagnostics(session, state, air, deflections)
			var propulsion: Dictionary = _propulsion_diagnostics(session, air)
			var weight_n: float = float(mass.mass_kg) * session.sim.gravity if mass.get("ok", false) else NAN
			var thrust_n: Variant = _safe_number(propulsion.get("thrust_n", NAN))
			var safe_weight_n: Variant = _safe_number(weight_n)
			rows.append({
				time_s = session.sim.time(), phase = "recorded_input" if tick <= REPLAY_TICKS else "calm_fixed_trim_hold",
				height_m = -state[RB.POS + 2], airspeed_mps = air.V, alpha_deg = rad_to_deg(air.alpha),
				pitch_deg = rad_to_deg(M.q_to_euler(attitude)[1]), pitch_rate_q_rad_s = state[RB.RATE + 1],
				dynamic_pressure_qbar_pa = air.qbar, raw_input = _raw.duplicate(true),
				absolute_throttle_command = session.commands.throttle, elevator_deg_up = current_elevator,
				rotor_rpm = session.sim.aux[Session.AUX_RPM], thrust_n = thrust_n,
				propulsion_telemetry_ok = propulsion.get("ok", false),
				powerplant_running = propulsion.get("powerplant_running", false),
				engine_stop_reason = propulsion.get("stop_reason", ""),
				effective_mass_kg = _safe_number(mass.get("mass_kg", NAN)), weight_n = safe_weight_n,
				thrust_to_weight = float(thrust_n) / float(safe_weight_n) if thrust_n != null and safe_weight_n != null and float(safe_weight_n) > 0.0 else null,
				fuel_kg = mass.get("fuel_kg", null), local_flow_blend = wash.local_flow_blend,
				downwash_delta_pitch_moment_nm = wash.downwash_delta_pitch_moment_nm,
				inverted = inverted, crashed = not session.crash.is_empty(), fault = fault,
			})
		if not session.crash.is_empty():
			# A crash freezes the run; it cannot satisfy the 45 s acceptance condition.
			break
		if not fault.is_empty():
			break

	var initial_state_error := 0.0
	if shared != null:
		for index: int in fixed_initial_state.size():
			initial_state_error = maxf(initial_state_error, absf(fixed_initial_state[index] - shared.state[index]))
	var base_model: Dictionary = data.model
	var donor_model: Dictionary = donor.get("model", {}) if not donor.is_empty() else {}
	var source_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var source_propulsion: Dictionary = source_record.get("propulsion", {})
	var public_report := {
		case = case_name,
		powerplant = str(source_propulsion.get("engine", {}).get("name", "")),
		propeller = str(source_propulsion.get("propeller", {}).get("name", "")),
		transplant_scope = "baseline file powertrain" if donor.is_empty() else "donor runtime model.propulsion only",
		run_start_basis = "native standard baseline start" if shared == null else "common standard baseline body state and fixed trim",
		native_trim_solver_succeeded = native_trim_result.get("ok", false),
		native_start_used_for_run = shared == null,
		candidate_native_start_accepted = shared == null and native_trim_result.get("ok", false),
		baseline_seeded_after_native_trim_failure = forced_fixed_start,
		completed_ticks = completed_ticks,
		seconds = session.sim.time(), completed_15s = completed_ticks >= REPLAY_TICKS,
		completed_45s = completed_ticks == REPLAY_TICKS + HOLD_TICKS,
		crashed = not crash_snapshot.is_empty(), crash_time_s = first_crash_s,
		crash = crash_snapshot, fault = fault, paused_at_s = first_pause_s,
		first_inverted_s = first_inverted_s, inverted_seconds = float(inverted_ticks) / 240.0,
		initial_state_max_abs_error_vs_baseline = initial_state_error,
		initial_airspeed_mps = initial_air.V,
		initial_elevator_deg_up = initial_elevator,
		initial_powerplant_running = initial_propulsion.get("powerplant_running", false),
		initial_engine_stop_reason = initial_propulsion.get("stop_reason", ""),
		initial_elevator_delta_deg_vs_baseline = initial_elevator_delta,
		max_abs_raw_pitch_input = max_abs_raw_pitch_input,
		max_absolute_throttle_command_error = max_abs_throttle_error,
		fixed_baseline_pitch_trim_command = fixed_baseline_trim.pitch,
		native_solver_start = native_start,
		startup_trim_was_overridden = shared != null,
		baseline_model_mass_kg = base_model.get("mass_kg", NAN),
		runtime_model_mass_kg = session.aircraft.model.get("mass_kg", NAN),
		runtime_model_inertia_kg_m2 = Array(session.aircraft.model.get("inertia", PackedFloat64Array())),
		complete_donor_aircraft_mass_kg = donor_model.get("mass_kg", null),
		complete_donor_mass_delta_kg_vs_standard = float(donor_model.get("mass_kg", base_model.mass_kg)) - float(base_model.mass_kg) if not donor_model.is_empty() else 0.0,
		initial_effective_mass_kg = initial_mass.get("mass_kg", NAN),
		final_effective_mass_kg = _mass_properties(session).get("mass_kg", NAN),
		max_sampled_effective_mass_delta_from_static_kg = max_abs_stage_mass_delta,
		max_sampled_fuel_cg_shift_m = max_abs_stage_cg_shift,
		max_sampled_fuel_inertia_delta_kg_m2 = max_abs_stage_inertia_delta,
		mass_property_sample_rate_hz = 240,
		max_height_m = max_height, min_height_m = min_height,
		min_airspeed_mps = min_speed, max_airspeed_mps = max_speed,
		max_abs_pitch_rate_q_rad_s = max_pitch_rate, max_dynamic_pressure_qbar_pa = max_dynamic_pressure,
		max_elevator_drift_deg = max_elevator_drift,
		absolute_throttle_history_sha256 = _sha256(JSON.stringify(Array(throttle_history)).to_utf8_buffer()) if not throttle_history.is_empty() else "",
		absolute_throttle_history_count = throttle_history.size(),
		applied_absolute_throttle_history_sha256 = _sha256(JSON.stringify(Array(applied_throttle_history)).to_utf8_buffer()),
		applied_absolute_throttle_history_count = applied_throttle_history.size(),
		applied_replay_throttle_matches_reference = _max_abs_diff(applied_throttle_history.slice(0, REPLAY_TICKS), throttle_history) == 0.0,
		applied_hold_throttle_matches_reference = _hold_throttle_matches(applied_throttle_history, throttle_history[REPLAY_TICKS - 1]),
		applied_absolute_throttle_history = Array(applied_throttle_history),
		initial_propeller_rpm = startup_aux[Session.AUX_RPM],
		fixed_trim = fixed_baseline_trim,
		initial_state = Array(fixed_initial_state),
		initial_servo_aux = Array(fixed_initial_aux),
		initial_startup_state_before_override = Array(startup_state),
		initial_startup_effective_mass = startup_effective_mass,
		rows = rows,
	}
	var result := {public_report = public_report, absolute_throttle_history = throttle_history,
		fixed_trim = fixed_baseline_trim, initial_state = fixed_initial_state, initial_servo_aux = fixed_initial_aux,
		start = session.start.duplicate(true)}
	session.free()
	return result


func _elevator_deg_up(session: Node) -> float:
	var deflections: Dictionary = session._deflections(session.sim.aux)
	return -rad_to_deg(deflections.elevator)


func _mass_properties(session: Node) -> Dictionary:
	if session.glow_is_active() and session.sim.continuous.size() > 1:
		var properties: Dictionary = GlowFlight.properties(session, session.sim.continuous[1])
		properties.fuel_kg = session.sim.continuous[1]
		return properties
	return {ok = true, mass_kg = session.sim.mass, inertia = session.sim.inertia.duplicate(),
		cg_body_m = PackedFloat64Array([0.0, 0.0, 0.0]), fuel_kg = null}


func _propulsion_diagnostics(session: Node, air: Dictionary) -> Dictionary:
	if session.glow_is_active():
		var telemetry: Dictionary = session.glow_state()
		var propeller: Dictionary = telemetry.get("propeller", {})
		return {ok = telemetry.get("ok", false) and propeller.has("thrust_n"),
			thrust_n = propeller.get("thrust_n", NAN), powerplant_running = telemetry.get("running", false),
			stop_reason = telemetry.get("stop_reason", ""), fuel_kg = telemetry.get("fuel_kg", NAN)}
	var evaluation: Dictionary = Dynamics.evaluate(session.sim.state, session.aircraft.model,
		session._deflections(session.sim.aux), session.sim.aux[Session.AUX_RPM], session.air_density(),
		session.wind_at(session.sim.time()), session.sim.gravity, PackedFloat64Array(), NAN)
	return {ok = evaluation.get("ok", false), thrust_n = evaluation.get("propulsion_loads", PackedFloat64Array([NAN]))[0],
		powerplant_running = true, stop_reason = "", fuel_kg = null}


func _wash_diagnostics(session: Node, state: PackedFloat64Array, air: Dictionary, deflections: Dictionary) -> Dictionary:
	var lag_index: int = session.downwash_index()
	var downwash_cl: float = session.sim.aux[lag_index] if lag_index >= 0 else NAN
	var with_wash: PackedFloat64Array = Aero._global_loads(state, air, deflections, session.aircraft.model,
		session.air_density(), downwash_cl)
	var without_lag: PackedFloat64Array = Aero._global_loads(state, air, deflections, session.aircraft.model,
		session.air_density())
	return {
		local_flow_blend = Aero.local_flow_weight(state, air, deflections, session.aircraft.model, downwash_cl),
		downwash_delta_pitch_moment_nm = with_wash[4] - without_lag[4],
	}


func _max_abs_diff(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	var output := 0.0
	for index: int in mini(left.size(), right.size()):
		output = maxf(output, absf(left[index] - right[index]))
	return output


func _hold_throttle_matches(history: PackedFloat64Array, expected: float) -> bool:
	if history.size() != REPLAY_TICKS + HOLD_TICKS:
		return false
	for index: int in range(REPLAY_TICKS, history.size()):
		if history[index] != expected:
			return false
	return true


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _safe_number(value: Variant) -> Variant:
	var numeric: float = float(value)
	return numeric if is_finite(numeric) else null


func _source_hashes() -> Dictionary:
	var paths := [
		"res://sim/flight_session.gd", "res://physics/aero.gd", "res://physics/dynamics.gd",
		"res://physics/propulsion.gd", "res://physics/propulsion_runtime.gd", "res://physics/aircraft_data.gd",
		"res://physics/glow/flight.gd", "res://physics/glow/installation.gd",
		"res://physics/glow/fuel_mass.gd", "res://physics/glow/propeller.gd",
		"res://physics/glow/lifecycle.gd", "res://physics/glow/two_stroke.gd",
		"res://physics/glow/four_stroke.gd", "res://physics/glow/operating_point.gd",
		"res://physics/glow/profile.gd", "res://physics/glow/source.gd",
		"res://physics/glow/thermal.gd", "res://physics/glow/vibration.gd",
		"res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/stik_glow_55ax_2t.json",
		"res://data/aircraft/stik_glow_fs64v_4t.json",
	]
	var result := {}
	for path: String in paths:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		result[path] = _sha256(bytes) if not bytes.is_empty() else "missing"
	return result
