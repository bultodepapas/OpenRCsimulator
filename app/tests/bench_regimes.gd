# H4/H5: repeated full-tick cost distributions and same-machine trajectory fingerprints for every catalog aircraft.
# This is a measurement tool, not a test. Spin is a documented high-alpha/high-rate load fixture, not handling evidence.
# Run: godot --headless --path . --script res://tests/bench_regimes.gd [-- --aircraft=<catalog id> --output=/tmp/bench.json]
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Commands := preload("res://input/commands.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const Turbine := preload("res://physics/turbine.gd")
const M := preload("res://physics/math3d.gd")

const REGIMES := ["trim", "stall", "spin", "ground"]
const TICK_HZ := 240.0
const DEFAULT_SAMPLES := 16
const DEFAULT_TICKS_PER_SAMPLE := 120
const DEFAULT_FINGERPRINT_TICKS := 960
const COMPONENT_SAMPLES := 7
const COMPONENT_CALLS := 1200

var _aircraft_ids: PackedStringArray = PackedStringArray()
var _output_path: String = ""
var _samples: int = DEFAULT_SAMPLES
var _ticks_per_sample: int = DEFAULT_TICKS_PER_SAMPLE
var _fingerprint_ticks: int = DEFAULT_FINGERPRINT_TICKS


func _initialize() -> void:
	_parse_args()
	var report: Dictionary = {
		"format": "openrc-h4h5-bench v1",
		"machine": {
			"os": OS.get_name(),
			"architecture": Engine.get_architecture_name(),
			"processor": OS.get_processor_name(),
			"logical_cpu_count": OS.get_processor_count(),
			"godot": Engine.get_version_info(),
		},
		"tick_hz": TICK_HZ,
		"samples": _samples,
		"ticks_per_sample": _ticks_per_sample,
		"fingerprint_ticks": _fingerprint_ticks,
		"timing_method": "Repeated batches from a restored fixture; each sample is the whole-session sim.step average over ticks_per_sample ticks.",
		"fingerprint_method": "SHA-256 over the initial and every subsequent PackedFloat64Array state, auxiliary state, and start-of-tick loads in native float64 byte order.",
		"spin_fixture": "Synthetic performance fixture: alpha 22 deg, body p 2.2 rad/s and r 1.2 rad/s, full up/right, engine stopped. Not handling evidence.",
		"aircraft": [],
	}
	for aircraft_id in _aircraft_ids:
		var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
		if entry.is_empty() or not AircraftCatalog.can_fly(aircraft_id):
			push_error("unknown or non-flyable aircraft ID: " + aircraft_id)
			quit(1)
			return
		var session: Node = FlightSession.new()
		session.setup(str(entry.data))
		root.add_child(session)
		if not session.is_flyable():
			push_error("aircraft setup failed for " + aircraft_id + ": " + str(session.pause_reason))
			session.free()
			quit(1)
			return
		var aircraft_result: Dictionary = {"id": aircraft_id, "regimes": {}}
		for regime in REGIMES:
			var fixture: Dictionary = _configure(session, regime)
			var fingerprint: Dictionary = _fingerprint(session, fixture)
			var timing: Dictionary = _benchmark(session, fixture)
			var components: Dictionary = _component_profile(session, fixture)
			aircraft_result.regimes[regime] = {
				"fixture": fixture.summary,
				"fingerprint": fingerprint,
				"timing": timing,
				"component_profile": components,
			}
			print("measured ", aircraft_id, " / ", regime, " / median ", timing.median_us_per_tick, " µs/tick")
		report.aircraft.append(aircraft_result)
		session.free()
	var json: String = JSON.stringify(report, "\t", true, true) + "\n"
	if _output_path.is_empty():
		print(json)
	else:
		var file: FileAccess = FileAccess.open(_output_path, FileAccess.WRITE)
		if file == null:
			push_error("cannot write benchmark output: " + _output_path)
			quit(1)
			return
		file.store_string(json)
		file.close()
		print("wrote ", _output_path)
	quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			_aircraft_ids.append(arg.trim_prefix("--aircraft="))
		elif arg.begins_with("--output="):
			_output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--samples="):
			_samples = maxi(3, int(arg.trim_prefix("--samples=")))
		elif arg.begins_with("--ticks-per-sample="):
			_ticks_per_sample = maxi(1, int(arg.trim_prefix("--ticks-per-sample=")))
		elif arg.begins_with("--fingerprint-ticks="):
			_fingerprint_ticks = maxi(1, int(arg.trim_prefix("--fingerprint-ticks=")))
	if _aircraft_ids.is_empty():
		_aircraft_ids = AircraftCatalog.ids()


## Restore the normal trimmed session, then install one explicit workload fixture.
func _configure(session: Node, regime: String) -> Dictionary:
	session.commands = Commands.neutral_commands()
	session.reset()
	var model: Dictionary = session.aircraft.model
	var state: PackedFloat64Array = session.start.state.duplicate()
	var throttle: float = float(session.start.throttle)
	var engine_running: bool = session.start.get("mode", "level") != "glide"
	var speed: float = sqrt(state[RB.VEL] * state[RB.VEL] + state[RB.VEL + 1] * state[RB.VEL + 1] + state[RB.VEL + 2] * state[RB.VEL + 2])
	var alpha: float = 0.0
	var rate_p: float = 0.0
	var rate_r: float = 0.0
	var ground_contacts: int = 0
	var ground_touched: bool = false
	match regime:
		"trim":
			pass
		"stall":
			alpha = deg_to_rad(15.0)
			state = _set_flight_condition(state, speed, alpha)
			state[RB.POS + 2] = -150.0
		"spin":
			alpha = deg_to_rad(22.0)
			rate_p = 2.2
			rate_r = 1.2
			state = _set_flight_condition(state, speed, alpha)
			state[RB.POS + 2] = -150.0
			state[RB.RATE] = rate_p
			state[RB.RATE + 2] = rate_r
			session.commands = {"roll": 0.0, "pitch": 1.0, "yaw": 1.0, "throttle": 0.0}
			throttle = 0.0
			engine_running = false
		"ground":
			state[RB.VEL] = 2.0
			state[RB.VEL + 1] = 0.0
			state[RB.VEL + 2] = 0.0
			speed = 2.0
			for i in 3:
				state[RB.RATE + i] = 0.0
			var identity: PackedFloat64Array = M.q_identity()
			for i in 4:
				state[RB.ATT + i] = identity[i]
			state[RB.POS + 2] = 0.0
			var compressions: PackedFloat64Array = Ground.compressions(state, model.landing_gear)
			ground_contacts = compressions.size()
			var deepest: float = -1e30
			for compression in compressions:
				deepest = maxf(deepest, compression)
			state[RB.POS + 2] = -deepest + 0.01 if not compressions.is_empty() else 0.0
			ground_touched = Ground.loads(state, model.landing_gear).size() == 6
			throttle = 0.0
			engine_running = false
		_:
			push_error("unknown regime: " + regime)
	var inputs: PackedFloat64Array = session._inputs()
	inputs[3] = throttle
	session.engine_running = engine_running
	session.sim.inputs = inputs
	var aux: PackedFloat64Array = PackedFloat64Array([
		float(session.start.rpm) if engine_running else 0.0,
		inputs[0], inputs[1], inputs[2],
	])
	session.sim.aux = aux
	var reset_ok: bool = session.sim.reset(state)
	if not reset_ok:
		push_error("fixture reset failed for " + regime + ": " + str(session.sim.fault_reason))
	var actual_air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
	return {
		"state": state,
		"inputs": inputs,
		"aux": aux,
		"engine_running": engine_running,
		"summary": {
			"alpha_deg": rad_to_deg(float(actual_air.alpha)),
			"speed_mps": speed,
			"p_radps": rate_p,
			"r_radps": rate_r,
			"ground_contacts": ground_contacts,
			"ground_touched": ground_touched,
		},
	}


func _set_flight_condition(source: PackedFloat64Array, speed: float, alpha: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = source.duplicate()
	out[RB.VEL] = speed * M.cos_(alpha)
	out[RB.VEL + 1] = 0.0
	out[RB.VEL + 2] = speed * M.sin_(alpha)
	return out


func _restore(session: Node, fixture: Dictionary) -> bool:
	session.sim.inputs = fixture.inputs.duplicate()
	session.sim.aux = fixture.aux.duplicate()
	session.sim.fault_reason = ""
	return session.sim.reset(fixture.state)


func _fingerprint(session: Node, fixture: Dictionary) -> Dictionary:
	if not _restore(session, fixture):
		return {"sha256": "", "ticks": 0, "fault": str(session.sim.fault_reason)}
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(session.sim.state.to_byte_array())
	digest.update(session.sim.aux.to_byte_array())
	digest.update(session.sim.last_loads.to_byte_array())
	var completed: int = 0
	for i in _fingerprint_ticks:
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		digest.update(session.sim.state.to_byte_array())
		digest.update(session.sim.aux.to_byte_array())
		digest.update(session.sim.last_loads.to_byte_array())
		completed += 1
	var final_state: PackedFloat64Array = session.sim.state
	var final_velocity: float = M.sqrt_(final_state[RB.VEL] * final_state[RB.VEL]
		+ final_state[RB.VEL + 1] * final_state[RB.VEL + 1] + final_state[RB.VEL + 2] * final_state[RB.VEL + 2])
	var final_ground_contact: bool = not Ground.loads(final_state, session.aircraft.model.landing_gear).is_empty()
	return {
		"sha256": digest.finish().hex_encode(),
		"ticks": completed,
		"fault": str(session.sim.fault_reason),
		"end_speed_mps": final_velocity,
		"end_altitude_m": -final_state[RB.POS + 2],
		"end_ground_contact": final_ground_contact,
	}


func _benchmark(session: Node, fixture: Dictionary) -> Dictionary:
	var values: PackedFloat64Array = PackedFloat64Array()
	for sample in _samples:
		if not _restore(session, fixture):
			return {"samples_us_per_tick": [], "median_us_per_tick": -1.0, "p95_us_per_tick": -1.0, "fault": str(session.sim.fault_reason)}
		var started: int = Time.get_ticks_usec()
		for tick in _ticks_per_sample:
			session.sim.step()
			if not session.sim.fault_reason.is_empty():
				break
		var elapsed: float = float(Time.get_ticks_usec() - started)
		values.append(elapsed / _ticks_per_sample)
	return {
		"samples_us_per_tick": values,
		"median_us_per_tick": _median(values),
		"p95_us_per_tick": _percentile(values, 0.95),
		"min_us_per_tick": _minimum(values),
		"max_us_per_tick": _maximum(values),
		"fault": str(session.sim.fault_reason),
	}


func _component_profile(session: Node, fixture: Dictionary) -> Dictionary:
	_restore(session, fixture)
	var model: Dictionary = session.aircraft.model
	var state: PackedFloat64Array = fixture.state
	var aux: PackedFloat64Array = fixture.aux
	var d: Dictionary = session._deflections(aux)
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
	var profile: Dictionary = {}
	profile["aero"] = _measure(func() -> void: Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL))
	if not model.get("envelope", {}).is_empty():
		profile["aero_local_flow_weight"] = _measure(func() -> void: Aero.local_flow_weight(state, air, d, model))
		profile["aero_global_loads"] = _measure(func() -> void: Aero._global_loads(state, air, d, model, Air.RHO_SEA_LEVEL))
		profile["aero_local_loads"] = _measure(func() -> void: Aero._local_loads(state, air, d, model, Air.RHO_SEA_LEVEL))
		profile["aero_blend"] = Aero.local_flow_weight(state, air, d, model)
	else:
		profile["aero_local_flow_weight"] = 0.0
		profile["aero_global_loads"] = profile["aero"]
		profile["aero_local_loads"] = 0.0
		profile["aero_blend"] = 0.0
	profile["propulsion_thrust_torque"] = 0.0 if Turbine.is_turbine(model.propulsion) else _measure(
		func() -> void: Propulsion.thrust_torque(air.v_air, aux[0], model.propulsion, Air.RHO_SEA_LEVEL))
	profile["propulsion_loads"] = _measure(func() -> void: Propulsion.loads(air.v_air, aux[0], model.propulsion, Air.RHO_SEA_LEVEL))
	profile["dynamics"] = _measure(func() -> void: Dynamics.loads(state, model, d, aux[0], Air.RHO_SEA_LEVEL, PackedFloat64Array([0.0, 0.0, 0.0])))
	profile["ground"] = _measure(func() -> void: Ground.loads(state, model.landing_gear, aux[3]))
	if not model.propulsion.get("slipstream", {}).is_empty():
		profile["slipstream"] = _measure(func() -> void: Slipstream.loads(state, air, d, model, aux[0], Air.RHO_SEA_LEVEL))
		var tq: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, aux[0], model.propulsion, Air.RHO_SEA_LEVEL)
		var wake: Dictionary = Slipstream.wake(air.v_air, tq[0], tq[1], model.propulsion, Air.RHO_SEA_LEVEL)
		profile["slipstream_wake"] = _measure(func() -> void: Slipstream.wake(air.v_air, tq[0], tq[1], model.propulsion, Air.RHO_SEA_LEVEL))
		var pieces: Array = model.propulsion.slipstream.pieces
		if not pieces.is_empty():
			var piece: Dictionary = pieces[0]
			var air_speed: float = M.sqrt_(M.dot(air.v_air, air.v_air))
			var immersion: Dictionary = Slipstream.immersion(piece, wake, model.propulsion.slipstream.hub,
				model.propulsion, air.v_air, air_speed, model)
			profile["slipstream_pieces"] = pieces.size()
			profile["slipstream_first_immersion"] = _measure(func() -> void: Slipstream.immersion(piece, wake,
				model.propulsion.slipstream.hub, model.propulsion, air.v_air, air_speed, model))
			if immersion.area > 0.0:
				var rates: PackedFloat64Array = state.slice(RB.RATE, RB.RATE + 3)
				var extra: PackedFloat64Array = M.sub(M.scale(Propulsion.axis(model.propulsion), wake.dv), immersion.swirl)
				var pair_washed: PackedFloat64Array = Aero.tail_surface_load(air.v_air, rates, d, model,
					piece.surface, immersion.area, immersion.shift, extra, Air.RHO_SEA_LEVEL)
				var pair_free: PackedFloat64Array = Aero.tail_surface_load(air.v_air, rates, d, model,
					piece.surface, immersion.area, immersion.shift, M.v3(0.0, 0.0, 0.0), Air.RHO_SEA_LEVEL)
				var pair_reference: PackedFloat64Array = PackedFloat64Array()
				for i in 6:
					pair_reference.append(pair_washed[i] - pair_free[i])
				var pair_shared: PackedFloat64Array = Aero.tail_surface_increment(air.v_air, rates, d, model,
					piece.surface, immersion.area, immersion.shift, extra, Air.RHO_SEA_LEVEL)
				profile["slipstream_pair_exact"] = pair_reference.to_byte_array() == pair_shared.to_byte_array()
				profile["slipstream_first_tail_pair_reference"] = _measure(func() -> void:
					Aero.tail_surface_load(air.v_air, rates, d, model, piece.surface, immersion.area,
						immersion.shift, extra, Air.RHO_SEA_LEVEL)
					Aero.tail_surface_load(air.v_air, rates, d, model, piece.surface, immersion.area,
						immersion.shift, M.v3(0.0, 0.0, 0.0), Air.RHO_SEA_LEVEL))
				profile["slipstream_first_tail_pair_shared"] = _measure(func() -> void:
					Aero.tail_surface_increment(air.v_air, rates, d, model, piece.surface, immersion.area,
						immersion.shift, extra, Air.RHO_SEA_LEVEL))
			else:
				profile["slipstream_pair_exact"] = true
				profile["slipstream_first_tail_pair_reference"] = 0.0
				profile["slipstream_first_tail_pair_shared"] = 0.0
		var tail_pairs_reference: PackedFloat64Array = _tail_pair_work(state, air, d, model, aux[0], false)
		var tail_pairs_shared: PackedFloat64Array = _tail_pair_work(state, air, d, model, aux[0], true)
		profile["slipstream_all_pairs_exact"] = tail_pairs_reference.to_byte_array() == tail_pairs_shared.to_byte_array()
		profile["slipstream_all_pairs_reference"] = _measure(func() -> void:
			_tail_pair_work(state, air, d, model, aux[0], false))
		profile["slipstream_all_pairs_shared"] = _measure(func() -> void:
			_tail_pair_work(state, air, d, model, aux[0], true))
	else:
		profile["slipstream"] = 0.0
		profile["slipstream_wake"] = 0.0
		profile["slipstream_first_immersion"] = 0.0
		profile["slipstream_pair_exact"] = true
		profile["slipstream_first_tail_pair_reference"] = 0.0
		profile["slipstream_first_tail_pair_shared"] = 0.0
		profile["slipstream_all_pairs_exact"] = true
		profile["slipstream_all_pairs_reference"] = 0.0
		profile["slipstream_all_pairs_shared"] = 0.0
		profile["slipstream_pieces"] = 0
	return profile


func _tail_pair_work(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		rpm: float, shared: bool) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if rpm < Propulsion.STOPPED_RPM:
		return out
	var prop: Dictionary = model.propulsion
	var tq: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, rpm, prop, Air.RHO_SEA_LEVEL)
	var wake: Dictionary = Slipstream.wake(air.v_air, tq[0], tq[1], prop, Air.RHO_SEA_LEVEL)
	var shaft_axis: PackedFloat64Array = Propulsion.axis(prop)
	var wash_velocity: PackedFloat64Array = M.scale(shaft_axis, wake.dv)
	var speed: float = M.sqrt_(M.dot(air.v_air, air.v_air))
	var rates: PackedFloat64Array = state.slice(RB.RATE, RB.RATE + 3)
	for piece_value in prop.slipstream.pieces:
		var piece: Dictionary = piece_value
		var im: Dictionary = Slipstream.immersion(piece, wake, prop.slipstream.hub, prop, air.v_air, speed, model,
			shaft_axis)
		if im.area <= 0.0:
			continue
		var extra: PackedFloat64Array = M.sub(wash_velocity, im.swirl)
		var increment: PackedFloat64Array
		if shared:
			increment = Aero.tail_surface_increment(air.v_air, rates, d, model, piece.surface,
				im.area, im.shift, extra, Air.RHO_SEA_LEVEL)
		else:
			var washed: PackedFloat64Array = Aero.tail_surface_load(air.v_air, rates, d, model, piece.surface,
				im.area, im.shift, extra, Air.RHO_SEA_LEVEL)
			var free: PackedFloat64Array = Aero.tail_surface_load(air.v_air, rates, d, model, piece.surface,
				im.area, im.shift, M.v3(0.0, 0.0, 0.0), Air.RHO_SEA_LEVEL)
			increment = PackedFloat64Array()
			for i in 6:
				increment.append(washed[i] - free[i])
		for i in 6:
			out[i] += increment[i]
	return out


func _measure(body: Callable) -> float:
	for i in 100:
		body.call()
	var samples: PackedFloat64Array = PackedFloat64Array()
	for sample in COMPONENT_SAMPLES:
		var started: int = Time.get_ticks_usec()
		for call_index in COMPONENT_CALLS:
			body.call()
		samples.append(float(Time.get_ticks_usec() - started) / float(COMPONENT_CALLS))
	return _median(samples)


func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() >> 1
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return 0.5 * (sorted[middle - 1] + sorted[middle])


func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var index: int = clampi(ceili(fraction * sorted.size()) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _minimum(values: PackedFloat64Array) -> float:
	var result: float = INF
	for value in values:
		result = minf(result, value)
	return 0.0 if values.is_empty() else result


func _maximum(values: PackedFloat64Array) -> float:
	var result: float = -INF
	for value in values:
		result = maxf(result, value)
	return 0.0 if values.is_empty() else result
