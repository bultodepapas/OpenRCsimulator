# E0b6p: paired probe for within-stage propulsion/wake sharing. Run only in a disposable app copy.
extends SceneTree

const BaseDynamics: Script = preload("res://physics/dynamics.gd")
const CandidateDynamics: Script = preload("res://tests/stage_sharing/dynamics.gd")
const BaseFlight: Script = preload("res://sim/flight_session.gd")
const CandidateFlight: Script = preload("res://tests/stage_sharing/flight_session.gd")
const Catalog: Script = preload("res://app_state/aircraft_catalog.gd")
const AircraftData: Script = preload("res://physics/aircraft_data.gd")
const Commands: Script = preload("res://input/commands.gd")
const Aero: Script = preload("res://physics/aero.gd")
const Air: Script = preload("res://physics/air_data.gd")
const Ground: Script = preload("res://physics/ground_contact.gd")
const Propulsion: Script = preload("res://physics/propulsion.gd")
const RB: Script = preload("res://physics/rigid_body.gd")
const Scenarios: Script = preload("res://sim/scenarios.gd")
const WashTransport: Script = preload("res://physics/wash_transport.gd")
const WashFixture: Script = preload("res://tests/test_wash_transport.gd")

const DIRECT_CALLS: int = 64
const DIRECT_PAIRS: int = 15
const DIRECT_WARMUP: int = 2
const FLIGHT_TICKS: int = 24
const FLIGHT_PAIRS: int = 9
const FLIGHT_WARMUP: int = 1
const TRAJECTORY_TICKS: int = 240
const FLEET_REGIMES: Array[String] = ["trim", "stall", "spin", "ground"]
const WAKE_REGIMES: Array[String] = ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]

var _output_path: String = ""
var _quick: bool = false
var _failures: int = 0
var _shape_checks: int = 0
var _finite_checks: int = 0
var _direct_calls_compared: int = 0
var _flight_boundaries_compared: int = 0
var _direct_rows: Array[Dictionary] = []
var _flight_rows: Array[Dictionary] = []


func _initialize() -> void:
	_parse_args()
	if _output_path.is_empty():
		_fail("usage: godot --headless --path APP --script PROBE.gd -- --output.json [--quick]")
		quit(1)
		return
	_run_direct_suite()
	_run_flight_suite()
	_write_report()
	quit(0 if _failures == 0 else 1)


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--output="):
			_output_path = arg.trim_prefix("--output=")
		elif arg == "--quick":
			_quick = true
		elif _output_path.is_empty() and not arg.begins_with("--"):
			_output_path = arg


func _run_direct_suite() -> void:
	for aircraft_id: String in Catalog.ids():
		var entry: Dictionary = Catalog.entry(aircraft_id)
		var loaded: Dictionary = AircraftData.load_file(str(entry.data))
		if not loaded.get("ok", false):
			_fail("direct fleet model failed to load: %s %s" % [aircraft_id, str(loaded.get("errors", []))])
			continue
		var model: Dictionary = loaded.model
		var trim: Dictionary = Scenarios.trimmed_level_across_view(model, 9.80665,
			model.controls.throw_rad, float(model.get("start_speed", 15.0)))
		if not trim.get("ok", false):
			_fail("direct fleet trim failed: %s %s" % [aircraft_id, str(trim.get("message", "unknown"))])
			continue
		var commands: Dictionary = Commands.neutral_commands()
		commands.roll = float(trim.roll_command)
		commands.pitch = float(trim.pitch_command)
		commands.yaw = float(trim.get("yaw_command", 0.0))
		commands.throttle = float(trim.throttle)
		var surfaces: Dictionary = Commands.surface_deflections_deg(commands, model.controls.throw_deg)
		var deflections: Dictionary = Aero.deflections_from_surfaces(surfaces)
		var base: Dictionary = _make_fixture("fleet:" + aircraft_id, model, trim.state,
			deflections, float(trim.rpm), Air.RHO_SEA_LEVEL, PackedFloat64Array())
		_append_direct_case(base)

	var derived: Dictionary = AircraftData.validate_and_derive(WashFixture.raw_fixture())
	if not derived.get("ok", false):
		_fail("smooth-wake fixture failed validation: " + str(derived.get("errors", [])))
		return
	var smooth_model: Dictionary = derived.model
	var neutral: Dictionary = _neutral_deflections()
	for regime: String in WAKE_REGIMES:
		for swirl: float in [0.0, 0.4]:
			var model: Dictionary = smooth_model.duplicate(true)
			model.propulsion.slipstream.erase("transport_speed_floor")
			model.propulsion.slipstream.swirl_factor = swirl
			var state: PackedFloat64Array = _wake_state(regime, model)
			_append_direct_case(_make_fixture("smooth:%s:swirl=%.1f" % [regime, swirl], model, state,
				neutral, float(model.propulsion.max_rpm), Air.RHO_SEA_LEVEL, PackedFloat64Array()))

	var transport_model: Dictionary = smooth_model.duplicate(true)
	# E0b5 transport is validated for axial wash only; swirl has its own six-regime sweep above.
	transport_model.propulsion.slipstream.swirl_factor = 0.0
	var forward: PackedFloat64Array = _wake_state("forward", transport_model)
	var settled: PackedFloat64Array = _settled_transport(forward, transport_model, Air.RHO_SEA_LEVEL)
	_append_direct_case(_make_fixture("smooth:transport_on", transport_model, forward, neutral,
		float(transport_model.propulsion.max_rpm), Air.RHO_SEA_LEVEL, settled))
	_append_direct_case(_make_fixture("smooth:stopped", transport_model, forward, neutral, 0.0,
		Air.RHO_SEA_LEVEL, PackedFloat64Array()))
	_append_direct_case(_make_fixture("smooth:stopped_residual", transport_model, forward, neutral, 0.0,
		Air.RHO_SEA_LEVEL, settled))


func _append_direct_case(fixture: Dictionary) -> void:
	var requests: Array[Dictionary] = _direct_requests(fixture)
	var exact: bool = true
	for request: Dictionary in requests:
		var baseline: PackedFloat64Array = BaseDynamics.loads(request.state, request.model, request.deflections,
			request.rpm, request.rho, request.wind, request.downwash, request.wash)
		var candidate: PackedFloat64Array = CandidateDynamics.loads(request.state, request.model, request.deflections,
			request.rpm, request.rho, request.wind, request.downwash, request.wash)
		_direct_calls_compared += 1
		var ok: bool = _same_array(fixture.label + " direct loads", baseline, candidate, 6)
		exact = exact and ok
	var pairs: int = 3 if _quick else DIRECT_PAIRS
	var calls: int = 12 if _quick else DIRECT_CALLS
	if _quick:
		requests.resize(calls)
	for warm: int in (1 if _quick else DIRECT_WARMUP):
		var a: Dictionary = _time_base(requests)
		var b: Dictionary = _time_candidate(requests)
		_validate_load(fixture.label + " baseline warmup", a.last)
		_validate_load(fixture.label + " candidate warmup", b.last)
	var base_samples: Array[float] = []
	var candidate_samples: Array[float] = []
	for pair: int in pairs:
		var first_base: Dictionary
		var first_candidate: Dictionary
		if pair % 2 == 0:
			first_base = _time_base(requests)
			first_candidate = _time_candidate(requests)
		else:
			first_candidate = _time_candidate(requests)
			first_base = _time_base(requests)
		base_samples.append(float(first_base.us_per_call))
		candidate_samples.append(float(first_candidate.us_per_call))
		_validate_load(fixture.label + " baseline timed", first_base.last)
		_validate_load(fixture.label + " candidate timed", first_candidate.last)
	_direct_rows.append({
		"case": fixture.label, "calls_per_sample": calls, "timing_unit": "mean microseconds per Dynamics.loads call",
		"exact": exact, "exact_calls": requests.size(), "baseline_samples_us": base_samples,
		"candidate_samples_us": candidate_samples,
		"median_baseline_us": _median(base_samples), "median_candidate_us": _median(candidate_samples),
	})


func _time_base(requests: Array[Dictionary]) -> Dictionary:
	var result: PackedFloat64Array = PackedFloat64Array()
	var started: int = Time.get_ticks_usec()
	for request: Dictionary in requests:
		result = BaseDynamics.loads(request.state, request.model, request.deflections, request.rpm,
			request.rho, request.wind, request.downwash, request.wash)
	var elapsed: float = float(Time.get_ticks_usec() - started)
	return {"us_per_call": elapsed / float(requests.size()), "last": result}


func _time_candidate(requests: Array[Dictionary]) -> Dictionary:
	var result: PackedFloat64Array = PackedFloat64Array()
	var started: int = Time.get_ticks_usec()
	for request: Dictionary in requests:
		result = CandidateDynamics.loads(request.state, request.model, request.deflections, request.rpm,
			request.rho, request.wind, request.downwash, request.wash)
	var elapsed: float = float(Time.get_ticks_usec() - started)
	return {"us_per_call": elapsed / float(requests.size()), "last": result}


func _direct_requests(fixture: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count: int = 12 if _quick else DIRECT_CALLS
	for index: int in count:
		var state: PackedFloat64Array = fixture.state.duplicate()
		var offset: float = float(index - count / 2)
		state[RB.VEL] += offset * 0.0005
		state[RB.VEL + 1] += offset * 0.0002
		state[RB.VEL + 2] += offset * 0.0003
		state[RB.RATE] += offset * 0.0001
		state[RB.RATE + 2] -= offset * 0.00008
		var rho: float = 1.10 + float(index % 17) * 0.009
		var rpm: float = fixture.rpm
		if fixture.vary_rpm:
			rpm = maxf(0.0, rpm * (0.86 + float(index % 23) * 0.005))
		var wind: PackedFloat64Array = PackedFloat64Array([0.15 * sin(float(index)), 0.1 * cos(float(index)), 0.04 * sin(float(index) * 0.3)])
		var air: Dictionary = Air.compute(state, wind, rho)
		var downwash: float = _downwash_cl(state, air, fixture.deflections, fixture.model)
		var wash: PackedFloat64Array = fixture.wash.duplicate()
		for piece: int in wash.size():
			wash[piece] *= 0.94 + float(index % 13) * 0.01
		out.append({"state": state, "model": fixture.model, "deflections": fixture.deflections,
			"rpm": rpm, "rho": rho, "wind": wind, "downwash": downwash, "wash": wash})
	return out


func _make_fixture(label: String, model: Dictionary, state: PackedFloat64Array, deflections: Dictionary,
		rpm: float, rho: float, wash: PackedFloat64Array) -> Dictionary:
	var clean_state: PackedFloat64Array = state.duplicate()
	var air: Dictionary = Air.compute(clean_state, PackedFloat64Array([0.0, 0.0, 0.0]), rho)
	return {"label": label, "model": model, "state": clean_state, "deflections": deflections,
		"rpm": rpm, "rho": rho, "wind": PackedFloat64Array([0.0, 0.0, 0.0]),
		"downwash": _downwash_cl(clean_state, air, deflections, model),
		"wash": wash, "vary_rpm": rpm >= Propulsion.STOPPED_RPM}


func _downwash_cl(state: PackedFloat64Array, air: Dictionary, deflections: Dictionary, model: Dictionary) -> float:
	var horizontal: Dictionary = model.get("surfaces", {}).get("horizontal", {})
	return Aero.wing_lift_coefficient(state, air, deflections, model) if horizontal.has("free_slope") else NAN


func _wake_state(regime: String, model: Dictionary, initial: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	var state: PackedFloat64Array = initial.duplicate() if not initial.is_empty() else PackedFloat64Array([
		0.0, 0.0, -100.0, 15.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	state[RB.POS + 2] = -100.0
	var speed: float = 0.0 if regime == "static" else 15.0
	if regime.begins_with("reverse"):
		var prop: Dictionary = model.propulsion
		var induced: float = float(prop.max_rpm) / 60.0 * float(prop.diameter) * sqrt(2.0 * float(prop.ct[1]) / PI)
		speed = (-0.15 if regime == "reverse_fade" else -0.3) * induced
	var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else (0.0 if regime.begins_with("reverse") else 3.0))
	state[RB.VEL] = speed * cos(alpha)
	state[RB.VEL + 2] = speed * sin(alpha)
	if regime == "spin":
		state[RB.RATE] = 0.5
		state[RB.RATE + 1] = -0.3
		state[RB.RATE + 2] = 1.5
	return state


func _settled_transport(state: PackedFloat64Array, model: Dictionary, rho: float) -> PackedFloat64Array:
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), rho)
	return WashTransport.settled(air.v_air, float(model.propulsion.max_rpm), model.propulsion, rho)


func _neutral_deflections() -> Dictionary:
	return {"elevator": 0.0, "rudder": 0.0, "aileron_left": 0.0, "aileron_right": 0.0}


func _run_flight_suite() -> void:
	for aircraft_id: String in Catalog.ids():
		for regime: String in FLEET_REGIMES:
			_run_flight_case("fleet:%s:%s" % [aircraft_id, regime], aircraft_id, regime, "")
	for regime: String in WAKE_REGIMES:
		for swirl: float in [0.0, 0.4]:
			_run_flight_case("smooth:%s:swirl=%.1f" % [regime, swirl], "", regime, "swirl=%.1f" % swirl)
	_run_flight_case("smooth:transport_on", "", "forward", "transport_on")
	_run_flight_case("smooth:stopped_residual", "", "stopped_residual", "transport_on")


func _run_flight_case(label: String, aircraft_id: String, regime: String, smooth_mode: String) -> void:
	var baseline: Node = BaseFlight.new()
	var candidate: Node = CandidateFlight.new()
	var baseline_ok: bool = _configure_flight(baseline, aircraft_id, regime, smooth_mode)
	var candidate_ok: bool = _configure_flight(candidate, aircraft_id, regime, smooth_mode)
	if not baseline_ok or not candidate_ok:
		_fail(label + " flight configuration failed")
		baseline.free()
		candidate.free()
		return
	var expected_aux: int = int(baseline.sim.aux.size())
	var expected_continuous: int = 0
	var model: Dictionary = baseline.aircraft.model
	if WashTransport.enabled(model.propulsion):
		expected_continuous = model.propulsion.slipstream.pieces.size()
	if expected_aux < BaseFlight.AUX_ANCHORS:
		_fail(label + " configured auxiliary state is shorter than the session's declared base layout")
	var fixture_equal: bool = _compare_boundary(label + " initial", baseline.sim, candidate.sim,
		expected_aux, expected_continuous)
	_flight_boundaries_compared += 1
	var baseline_hash: HashingContext = HashingContext.new()
	var candidate_hash: HashingContext = HashingContext.new()
	baseline_hash.start(HashingContext.HASH_SHA256)
	candidate_hash.start(HashingContext.HASH_SHA256)
	_hash_boundary(baseline_hash, baseline.sim)
	_hash_boundary(candidate_hash, candidate.sim)
	var baseline_checkpoint: Dictionary = baseline.sim.checkpoint()
	var candidate_checkpoint: Dictionary = candidate.sim.checkpoint()
	var trajectory_exact: bool = fixture_equal
	var boundaries: int = 1
	for tick: int in TRAJECTORY_TICKS:
		baseline.sim.step()
		candidate.sim.step()
		var step_ok: bool = _check_faults(label, baseline.sim, candidate.sim)
		var same: bool = _compare_boundary(label + " tick %d" % (tick + 1), baseline.sim, candidate.sim,
			expected_aux, expected_continuous)
		_hash_boundary(baseline_hash, baseline.sim)
		_hash_boundary(candidate_hash, candidate.sim)
		trajectory_exact = trajectory_exact and step_ok and same
		boundaries += 1
		_flight_boundaries_compared += 1
	var pairs: int = 3 if _quick else FLIGHT_PAIRS
	var ticks_per_sample: int = 6 if _quick else FLIGHT_TICKS
	var base_samples: Array[float] = []
	var candidate_samples: Array[float] = []
	for warm: int in (0 if _quick else FLIGHT_WARMUP):
		_measure_flight(baseline.sim, baseline_checkpoint, ticks_per_sample)
		_measure_flight(candidate.sim, candidate_checkpoint, ticks_per_sample)
		if not _timed_batch_ok(label + " warmup", baseline.sim, candidate.sim, ticks_per_sample):
			trajectory_exact = false
	for pair: int in pairs:
		var base_measure: float
		var candidate_measure: float
		if pair % 2 == 0:
			base_measure = _measure_flight(baseline.sim, baseline_checkpoint, ticks_per_sample)
			candidate_measure = _measure_flight(candidate.sim, candidate_checkpoint, ticks_per_sample)
		else:
			candidate_measure = _measure_flight(candidate.sim, candidate_checkpoint, ticks_per_sample)
			base_measure = _measure_flight(baseline.sim, baseline_checkpoint, ticks_per_sample)
		base_samples.append(base_measure)
		candidate_samples.append(candidate_measure)
		if not _timed_batch_ok(label + " timed batch", baseline.sim, candidate.sim, ticks_per_sample):
			trajectory_exact = false
	var expected_tick: int = ticks_per_sample
	var batch_ticks_ok: bool = int(baseline.sim.tick) == expected_tick and int(candidate.sim.tick) == expected_tick
	if not batch_ticks_ok:
		_fail(label + " timed batches did not complete %d ticks" % ticks_per_sample)
		trajectory_exact = false
	_flight_rows.append({"case": label, "trajectory_exact": trajectory_exact,
		"boundaries_compared": boundaries, "timing_ticks_per_sample": ticks_per_sample,
		"timing_unit": "mean microseconds per sim.step tick",
		"baseline_trajectory_sha256": baseline_hash.finish().hex_encode(),
		"candidate_trajectory_sha256": candidate_hash.finish().hex_encode(),
		"baseline_samples_us": base_samples, "candidate_samples_us": candidate_samples,
		"median_baseline_us_per_tick": _median(base_samples),
		"median_candidate_us_per_tick": _median(candidate_samples)})
	baseline.free()
	candidate.free()


func _configure_flight(flight: Node, aircraft_id: String, regime: String, smooth_mode: String) -> bool:
	if smooth_mode.is_empty():
		var entry: Dictionary = Catalog.entry(aircraft_id)
		if entry.is_empty() or not Catalog.can_fly(aircraft_id):
			return false
		flight.setup(str(entry.data))
		flight.input_enabled = false
	else:
		if not WashFixture.configure(flight):
			return false
		flight.input_enabled = false
		var slipstream: Dictionary = flight.aircraft.model.propulsion.slipstream
		if smooth_mode.begins_with("swirl="):
			slipstream.erase("transport_speed_floor")
			slipstream.swirl_factor = float(smooth_mode.trim_prefix("swirl="))
		else:
			# The validated transported-wash fixture deliberately excludes swirl.
			slipstream.swirl_factor = 0.0
		flight.reset()
	if not flight.is_flyable():
		return false
	if not flight.is_inside_tree():
		root.add_child(flight)
	if smooth_mode.is_empty():
		return _set_fleet_regime(flight, regime)
	return _set_smooth_regime(flight, regime)


func _set_smooth_regime(flight: Node, regime: String) -> bool:
	var model: Dictionary = flight.aircraft.model
	var wake_regime: String = "forward" if regime == "stopped_residual" else regime
	var state: PackedFloat64Array = _wake_state(wake_regime, model, flight.sim.state)
	var maximum_rpm: float = float(model.propulsion.max_rpm)
	var stopped: bool = regime == "stopped_residual"
	flight.engine_running = not stopped
	var aux: PackedFloat64Array = flight.sim.aux.duplicate()
	aux[flight.AUX_RPM] = 0.0 if stopped else maximum_rpm
	var lag_index: int = flight.downwash_index()
	if lag_index >= 0 and lag_index < aux.size():
		aux[lag_index] = flight._wing_cl(state, aux)
	flight.sim.aux = aux
	flight.sim.continuous = PackedFloat64Array()
	if WashTransport.enabled(model.propulsion):
		var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
		# The stopped-source case begins at powered equilibrium and then decays from a zero-RPM source.
		flight.sim.continuous = WashTransport.settled(air.v_air, maximum_rpm, model.propulsion, Air.RHO_SEA_LEVEL)
	if not flight.sim.reset(state):
		return false
	return flight.sim.fault_reason.is_empty()


func _set_fleet_regime(flight: Node, regime: String) -> bool:
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	var model: Dictionary = flight.aircraft.model
	var speed: float = sqrt(state[RB.VEL] * state[RB.VEL] + state[RB.VEL + 1] * state[RB.VEL + 1]
		+ state[RB.VEL + 2] * state[RB.VEL + 2])
	var alpha: float = 0.0
	var rpm: float = float(flight.sim.aux[flight.AUX_RPM])
	var stop_engine: bool = regime in ["spin", "ground"]
	match regime:
		"trim":
			pass
		"stall":
			alpha = deg_to_rad(15.0)
			state[RB.POS + 2] = -150.0
		"spin":
			alpha = deg_to_rad(22.0)
			state[RB.POS + 2] = -150.0
			state[RB.RATE] = 2.2
			state[RB.RATE + 2] = 1.2
		"ground":
			state[RB.VEL] = 2.0
			state[RB.VEL + 1] = 0.0
			state[RB.VEL + 2] = 0.0
			for i: int in 3:
				state[RB.RATE + i] = 0.0
			state[RB.ATT] = 1.0
			state[RB.ATT + 1] = 0.0
			state[RB.ATT + 2] = 0.0
			state[RB.ATT + 3] = 0.0
			state[RB.POS + 2] = 0.0
			var compressions: PackedFloat64Array = Ground.compressions(state, model.landing_gear)
			var deepest: float = -1e30
			for compression: float in compressions:
				deepest = maxf(deepest, compression)
			state[RB.POS + 2] = -deepest + 0.01 if not compressions.is_empty() else 0.0
		_:
			return false
	if regime in ["stall", "spin"]:
		state[RB.VEL] = speed * cos(alpha)
		state[RB.VEL + 2] = speed * sin(alpha)
	var aux: PackedFloat64Array = flight.sim.aux.duplicate()
	if stop_engine:
		flight.engine_running = false
		rpm = 0.0
	else:
		flight.engine_running = true
	aux[flight.AUX_RPM] = rpm
	if regime == "spin":
		flight.sim.inputs[0] = 0.0
		flight.sim.inputs[1] = 1.0
		flight.sim.inputs[2] = 1.0
		flight.sim.inputs[3] = 0.0
	elif regime == "ground":
		flight.sim.inputs[3] = 0.0
	if regime == "ground":
		var count: int = flight.anchor_count()
		var start: int = flight.AUX_ANCHORS
		var end: int = start + count * Ground.ANCHOR_STRIDE
		if end > start:
			var old_anchors: PackedFloat64Array = aux.slice(start, end)
			var anchors: PackedFloat64Array = Ground.anchor_step(state, model.landing_gear,
				aux[flight.AUX_SERVO + 2], flight.ground_surfaces, old_anchors)
			for j: int in anchors.size():
				aux[start + j] = anchors[j]
	var lag_index: int = flight.downwash_index()
	if lag_index >= 0 and lag_index < aux.size():
		aux[lag_index] = flight._wing_cl(state, aux)
	flight.sim.aux = aux
	flight.sim.continuous = PackedFloat64Array()
	if not flight.sim.reset(state):
		return false
	return flight.sim.fault_reason.is_empty()


func _measure_flight(sim: Node, checkpoint: Dictionary, ticks: int) -> float:
	if not sim.restore_checkpoint(checkpoint):
		_fail("flight benchmark checkpoint restore failed")
		return -1.0
	var started: int = Time.get_ticks_usec()
	for tick: int in ticks:
		sim.step()
	return float(Time.get_ticks_usec() - started) / float(ticks)


func _timed_batch_ok(label: String, baseline: Node, candidate: Node, ticks: int) -> bool:
	var faults_ok: bool = _check_faults(label, baseline, candidate)
	var ticks_ok: bool = int(baseline.tick) == ticks and int(candidate.tick) == ticks
	if not ticks_ok:
		_fail(label + " did not complete %d ticks (baseline=%d candidate=%d)" % [ticks, baseline.tick, candidate.tick])
	return faults_ok and ticks_ok


func _hash_boundary(digest: HashingContext, sim: Node) -> void:
	for field: String in ["state", "aux", "continuous", "last_loads"]:
		var values: PackedFloat64Array = sim.get(field)
		digest.update((field + ":" + str(values.size()) + ":").to_utf8_buffer())
		if not values.is_empty():
			digest.update(values.to_byte_array())


func _compare_boundary(label: String, baseline: Node, candidate: Node, expected_aux: int,
		expected_continuous: int) -> bool:
	var same: bool = true
	for field: String in ["state", "aux", "continuous", "last_loads"]:
		var a: PackedFloat64Array = baseline.get(field)
		var b: PackedFloat64Array = candidate.get(field)
		var expected: int = RB.SIZE if field == "state" else (6 if field == "last_loads" else (
			expected_aux if field == "aux" else expected_continuous))
		same = _same_array(label + " " + field, a, b, expected) and same
	return same


func _check_faults(label: String, baseline: Node, candidate: Node) -> bool:
	var a: String = str(baseline.fault_reason)
	var b: String = str(candidate.fault_reason)
	if not a.is_empty() or not b.is_empty():
		_fail(label + " simulation fault baseline='%s' candidate='%s'" % [a, b])
		return false
	return true


func _same_array(label: String, a: PackedFloat64Array, b: PackedFloat64Array, expected: int) -> bool:
	var valid_a: bool = _check_array(label + " baseline", a, expected)
	var valid_b: bool = _check_array(label + " candidate", b, expected)
	if a.size() != b.size():
		_fail(label + " shape mismatch: %d != %d" % [a.size(), b.size()])
		return false
	if not valid_a or not valid_b:
		return false
	if a.to_byte_array() != b.to_byte_array():
		_fail(label + " float64 bytes differ")
		return false
	return true


func _check_array(label: String, values: PackedFloat64Array, expected: int) -> bool:
	_shape_checks += 1
	_finite_checks += 1
	var shape_ok: bool = expected < 0 or values.size() == expected
	var finite_ok: bool = true
	for value: float in values:
		finite_ok = finite_ok and is_finite(value)
	if not shape_ok:
		_fail(label + " has invalid shape %d (expected %d)" % [values.size(), expected])
	if not finite_ok:
		_fail(label + " contains a nonfinite value")
	return shape_ok and finite_ok


func _validate_load(label: String, values: PackedFloat64Array) -> void:
	_check_array(label, values, 6)


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() >> 1
	return sorted[middle] if sorted.size() % 2 == 1 else 0.5 * (sorted[middle - 1] + sorted[middle])


func _fail(message: String) -> void:
	_failures += 1
	printerr("FAIL ", message)


func _write_report() -> void:
	var routes: Dictionary = {}
	if FileAccess.file_exists("res://tests/stage_sharing/adapter.gd"):
		for entry: Array in [["baseline", "res://tests/e0b6p_native/adapter.gd"],
				["candidate", "res://tests/stage_sharing/adapter.gd"]]:
			var adapter: Script = load(entry[1])
			var counts: Dictionary = adapter.route_counts
			routes[entry[0]] = counts.duplicate()
			if int(counts.kernel_calls) <= 0 or int(counts.refused) != 0:
				_fail("native adapter did not complete its expected route")
	var report: Dictionary = {
		"format": "openrc-e0b6p-stage-sharing v1",
		"status": "pass" if _failures == 0 else "fail",
		"pass": _failures == 0,
		"failures": _failures,
		"machine": {"os": OS.get_name(), "architecture": Engine.get_architecture_name(),
			"processor": OS.get_processor_name(), "godot": Engine.get_version_info()},
		"timing": {"direct_pairs": 3 if _quick else DIRECT_PAIRS,
			"direct_calls_per_pair": 12 if _quick else DIRECT_CALLS,
			"direct_warmup_pairs": 1 if _quick else DIRECT_WARMUP,
			"flight_pairs": 3 if _quick else FLIGHT_PAIRS,
			"flight_ticks_per_pair": 6 if _quick else FLIGHT_TICKS,
			"flight_warmup_pairs": 0 if _quick else FLIGHT_WARMUP,
			"trajectory_ticks": TRAJECTORY_TICKS},
		"counts": {"shape_checks": _shape_checks, "finite_checks": _finite_checks,
			"direct_calls_compared": _direct_calls_compared,
			"flight_boundaries_compared": _flight_boundaries_compared},
		"direct_rows": _direct_rows,
		"flight_rows": _flight_rows,
		"backend_routes": routes,
	}
	var file: FileAccess = FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot open output file: " + _output_path)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("stage-sharing probe wrote ", _output_path, " (", _failures, " failures)")
