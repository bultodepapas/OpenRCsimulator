# Wind integration measurement harness. This is observational, not a test.
# Run: godot --headless --path app --script res://tests/bench_wind.gd -- --weather=calm --output=/tmp/wind.json
# A run records exact session checkpoints and whole FlightSession/Simulation tick costs for the full flyable catalog.
# Weather is configured through dynamic calls so this script also loads on the frozen pre-wind baseline.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const Commands := preload("res://input/commands.gd")
const Air := preload("res://physics/air_data.gd")
const Ground := preload("res://physics/ground_contact.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const TICK_HZ := 240.0
const REGIMES := ["trim", "stall", "ground"]
const CHECKPOINT_TICKS := [0, 240, 480]

var _aircraft_ids := PackedStringArray()
var _weather_name := "calm"
var _output_path := ""
var _source_revision := "unspecified"
var _samples := 5
var _ticks_per_sample := 240
var _warmup_ticks := 240
var _gust_delay_override_s := -1.0


func _gust_delay_metadata() -> Variant:
	if _gust_delay_override_s >= 0.0:
		return _gust_delay_override_s
	return null


func _initialize() -> void:
	_parse_args()
	var report := {
		"format": "openrc-wind-bench v1",
		"source_revision": _source_revision,
		"machine": {
			"os": OS.get_name(),
			"architecture": Engine.get_architecture_name(),
			"processor": OS.get_processor_name(),
			"logical_cpu_count": OS.get_processor_count(),
			"godot": Engine.get_version_info(),
		},
		"tick_hz": TICK_HZ,
		"weather_requested": _weather_name,
		"weather_options": {
			"gust_delay_override_s": _gust_delay_metadata(),
		},
		"samples": _samples,
		"ticks_per_sample": _ticks_per_sample,
		"warmup_ticks_per_sample": _warmup_ticks,
		"timing_method": "Each timing sample restores a fixture, performs warmup_ticks_per_sample untimed whole-session steps, restores again, then times ticks_per_sample whole-session sim.step calls. Reported percentiles are over batch means, not individual ticks.",
		"fingerprint_method": "SHA-256 over complete packed session snapshots: rigid-body state, auxiliary state, continuous state, modes, inputs, and start-of-tick loads. Snapshot and cumulative trajectory hashes plus numeric values are captured at tick 0, 240, and 480.",
		"fixtures": "trim uses the catalog start; stall sets air-relative alpha to 15 degrees at the same initial airspeed; ground sets a 2 m/s forward body speed and settles landing-gear compression by 1 cm. All command inputs are neutral except the engine/throttle state retained by trim.",
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
		var weather_result: Dictionary = _configure_weather(session)
		if not weather_result.ok:
			session.free()
			quit(1)
			return
		var aircraft_report := {
			"id": aircraft_id,
			"weather_setup": weather_result,
			"weather_samples_ned_mps": _weather_samples(session),
			"regimes": {},
		}
		for regime in REGIMES:
			var fixture: Dictionary = _configure_fixture(session, regime)
			if not fixture.ok:
				push_error("fixture setup failed for " + aircraft_id + " / " + regime + ": " + str(fixture.fault))
				session.free()
				quit(1)
				return
			var regime_report := {
				"fixture": fixture.summary,
				"timing": _benchmark(session, fixture),
			}
			if regime == "trim":
				regime_report["checkpoints"] = _fingerprint(session, fixture)
			aircraft_report.regimes[regime] = regime_report
			print("measured ", aircraft_id, " / ", regime, " / ", _weather_name,
				" / median ", regime_report.timing.median_us_per_tick, " µs/tick")
		report.aircraft.append(aircraft_report)
		session.free()
	var json := JSON.stringify(report, "\t", true, true) + "\n"
	if _output_path.is_empty():
		print(json)
	else:
		var file := FileAccess.open(_output_path, FileAccess.WRITE)
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
		elif arg.begins_with("--weather="):
			_weather_name = arg.trim_prefix("--weather=")
		elif arg.begins_with("--output="):
			_output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--revision="):
			_source_revision = arg.trim_prefix("--revision=")
		elif arg.begins_with("--samples="):
			_samples = maxi(3, int(arg.trim_prefix("--samples=")))
		elif arg.begins_with("--ticks-per-sample="):
			_ticks_per_sample = maxi(1, int(arg.trim_prefix("--ticks-per-sample=")))
		elif arg.begins_with("--warmup-ticks="):
			_warmup_ticks = maxi(0, int(arg.trim_prefix("--warmup-ticks=")))
		elif arg.begins_with("--gust-delay="):
			_gust_delay_override_s = float(arg.trim_prefix("--gust-delay="))
	if _aircraft_ids.is_empty():
		_aircraft_ids = AircraftCatalog.ids()


func _configure_weather(session: Node) -> Dictionary:
	if _weather_name == "calm" and not session.has_method("setup_weather"):
		return {"ok": true, "api_available": false, "configuration": "legacy calm default"}
	if not session.has_method("setup_weather"):
		push_error("weather API is unavailable for requested weather " + _weather_name)
		return {"ok": false, "api_available": false}
	var configuration: Dictionary = _weather_configuration(_weather_name)
	if configuration.is_empty():
		push_error("unknown weather preset: " + _weather_name)
		return {"ok": false, "api_available": true}
	var accepted: bool = bool(session.call("setup_weather", configuration))
	if not accepted:
		push_error("session rejected weather configuration " + _weather_name)
		return {"ok": false, "api_available": true, "requested_configuration": configuration}
	session.reset() # configure requires a reset boundary before querying wind or stepping
	var actual: Dictionary = session.call("weather_configuration") if session.has_method("weather_configuration") else {}
	return {"ok": true, "api_available": true, "requested_configuration": configuration, "configuration": actual}


func _weather_configuration(name: String) -> Dictionary:
	var config := {
		"format": "openrc-weather v1",
		"speed_mps": 0.0,
		"from_deg": 0.0,
		"gust_mps": 0.0,
		"gust_up_mps": 0.0,
		"gust_duration_s": 4.0,
		"gust_period_s": 12.0,
		"gust_delay_s": 2.0,
	}
	match name:
		"calm":
			pass
		"steady":
			config.speed_mps = 3.0
			config.from_deg = 270.0
		"gusty", "gust":
			config.speed_mps = 3.0
			config.from_deg = 270.0
			config.gust_mps = 3.0
			config.gust_up_mps = 1.5
		"crosswind":
			config.speed_mps = 5.0
			config.from_deg = 0.0
		"turbulent":
			config.format = "openrc-weather v2"
			config.speed_mps = 3.0
			config.from_deg = 270.0
			config.turbulence_rms_mps = [0.6, 0.6, 0.4]
			config.turbulence_tau_s = 2.0
			config.turbulence_seed = 20261009
		"updraft":
			config.gust_up_mps = 2.0
			config.gust_period_s = 10.0
		_:
			return {}
	if _gust_delay_override_s >= 0.0:
		config.gust_delay_s = _gust_delay_override_s
	return config


func _weather_samples(session: Node) -> Array:
	var samples: Array = []
	if not session.has_method("wind_at"):
		return samples
	var times: Array = [0.0, 0.5, 1.0, 2.0, 2.5, 3.0, 4.0, 6.0, 10.0, 14.0]
	var config: Dictionary = session.call("weather_configuration")
	if config.get("format") == "openrc-weather v2" and config.get("turbulence_rms_mps") != [0.0, 0.0, 0.0]:
		times = [0.0] # only the current tick interval exists; random future wind is never queried
	for t in times:
		var value: Variant = session.call("wind_at", t)
		samples.append({"time_s": t, "wind_ned_mps": Array(value)})
	return samples


func _configure_fixture(session: Node, regime: String) -> Dictionary:
	session.commands = Commands.neutral_commands()
	session.reset()
	var model: Dictionary = session.aircraft.model
	# Read the state after reset: a weather-aware session may offset its trimmed air-relative state by wind.
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var throttle: float = float(session.start.throttle)
	var engine_running: bool = session.start.get("mode", "level") != "glide"
	var wind: PackedFloat64Array = _wind_at(session, 0.0)
	var initial_air: Dictionary = Air.compute(state, wind, Air.RHO_SEA_LEVEL)
	var speed: float = float(initial_air.V)
	var alpha: float = 0.0
	var ground_contacts := 0
	var ground_touched := false
	match regime:
		"trim":
			pass
		"stall":
			alpha = deg_to_rad(15.0)
			state = _set_air_condition(state, wind, speed, alpha)
			state[RB.POS + 2] = -150.0
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
			var deepest := -1e30
			for compression in compressions:
				deepest = maxf(deepest, compression)
			state[RB.POS + 2] = -deepest + 0.01 if not compressions.is_empty() else 0.0
			ground_touched = Ground.loads(state, model.landing_gear).size() == 6
			throttle = 0.0
			engine_running = false
		_:
			return {"ok": false, "fault": "unknown regime: " + regime}
	var inputs: PackedFloat64Array = session._inputs()
	inputs[3] = throttle
	session.engine_running = engine_running
	session.sim.inputs = inputs
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	aux[0] = float(session.start.rpm) if engine_running else 0.0
	for axis: int in 3:
		aux[axis+1] = inputs[axis]
	session.sim.aux = aux
	var lag: int = session.downwash_index()
	if lag >= 0:
		aux[lag] = session._wing_cl(state, aux, 0.0)
		session.sim.aux = aux
	session.sim.continuous = session._settled_wash(state, aux)
	var reset_ok: bool = session.sim.reset(state)
	if not reset_ok:
		return {"ok": false, "fault": str(session.sim.fault_reason)}
	var actual_air := Air.compute(state, wind, Air.RHO_SEA_LEVEL)
	return {
		"ok": true,
		"state": state,
		"inputs": inputs,
		"aux": aux,
		"modes": session.sim.modes.duplicate(),
		"continuous": session.sim.continuous.duplicate(),
		"summary": {
			"alpha_deg": rad_to_deg(float(actual_air.alpha)),
			"air_speed_mps": float(actual_air.V),
			"p_radps": 0.0,
			"r_radps": 0.0,
			"ground_contacts": ground_contacts,
			"ground_touched": ground_touched,
		},
	}


func _set_air_condition(source: PackedFloat64Array, wind_ned: PackedFloat64Array,
		speed: float, alpha: float) -> PackedFloat64Array:
	var out := source.duplicate()
	var current_air: PackedFloat64Array = Air.compute(source, wind_ned, Air.RHO_SEA_LEVEL).v_air
	var wind_body := PackedFloat64Array([
		source[RB.VEL] - current_air[0],
		source[RB.VEL + 1] - current_air[1],
		source[RB.VEL + 2] - current_air[2],
	])
	out[RB.VEL] = speed * M.cos_(alpha) + wind_body[0]
	out[RB.VEL + 1] = wind_body[1]
	out[RB.VEL + 2] = speed * M.sin_(alpha) + wind_body[2]
	return out


func _wind_at(session: Node, time_s: float) -> PackedFloat64Array:
	if session.has_method("wind_at"):
		var result: Variant = session.call("wind_at", time_s)
		if result is PackedFloat64Array and result.size() == 3:
			return result
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _restore(session: Node, fixture: Dictionary) -> bool:
	session.sim.inputs = fixture.inputs.duplicate()
	session.sim.aux = fixture.aux.duplicate()
	session.sim.modes = fixture.modes.duplicate()
	session.sim.continuous = fixture.continuous.duplicate()
	session.sim.fault_reason = ""
	return session.sim.reset(fixture.state)


func _fingerprint(session: Node, fixture: Dictionary) -> Dictionary:
	if not _restore(session, fixture):
		return {"ok": false, "fault": str(session.sim.fault_reason), "checkpoints": []}
	var checkpoints: Array = []
	var trajectory_bytes := PackedByteArray()
	_append_snapshot(trajectory_bytes, session.sim)
	checkpoints.append(_checkpoint(0, session.sim, trajectory_bytes))
	for tick in range(1, CHECKPOINT_TICKS[-1] + 1):
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			return {"ok": false, "fault": str(session.sim.fault_reason), "completed_ticks": tick - 1, "checkpoints": checkpoints}
		_append_snapshot(trajectory_bytes, session.sim)
		if tick in CHECKPOINT_TICKS:
			checkpoints.append(_checkpoint(tick, session.sim, trajectory_bytes))
	return {"ok": true, "fault": str(session.sim.fault_reason), "ticks": CHECKPOINT_TICKS[-1], "checkpoints": checkpoints}


func _append_snapshot(output: PackedByteArray, sim: Node) -> void:
	output.append_array(sim.state.to_byte_array())
	output.append_array(sim.aux.to_byte_array())
	output.append_array(sim.continuous.to_byte_array())
	output.append_array(sim.modes.to_byte_array())
	output.append_array(sim.inputs.to_byte_array())
	output.append_array(sim.last_loads.to_byte_array())


func _checkpoint(tick: int, sim: Node, trajectory_bytes: PackedByteArray) -> Dictionary:
	var snapshot := PackedByteArray()
	_append_snapshot(snapshot, sim)
	return {
		"tick": tick,
		"snapshot_sha256": _sha256(snapshot),
		"trajectory_sha256": _sha256(trajectory_bytes),
		"state": Array(sim.state),
		"aux": Array(sim.aux),
		"continuous": Array(sim.continuous),
		"modes": Array(sim.modes),
		"inputs": Array(sim.inputs),
		"loads": Array(sim.last_loads),
	}


func _sha256(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


func _benchmark(session: Node, fixture: Dictionary) -> Dictionary:
	var values := PackedFloat64Array()
	var faults := PackedStringArray()
	for sample in _samples:
		if not _restore(session, fixture):
			return {"samples_us_per_tick": [], "median_us_per_tick": -1.0, "p95_batch_mean_us_per_tick": -1.0,
				"fault": str(session.sim.fault_reason)}
		for _tick in _warmup_ticks:
			session.sim.step()
			if not session.sim.fault_reason.is_empty():
				return {"samples_us_per_tick": [], "median_us_per_tick": -1.0, "p95_batch_mean_us_per_tick": -1.0,
					"fault": str(session.sim.fault_reason), "failed_during": "warmup"}
		if not _restore(session, fixture):
			return {"samples_us_per_tick": [], "median_us_per_tick": -1.0, "p95_batch_mean_us_per_tick": -1.0,
				"fault": str(session.sim.fault_reason)}
		var started := Time.get_ticks_usec()
		for _tick in _ticks_per_sample:
			session.sim.step()
			if not session.sim.fault_reason.is_empty():
				faults.append(str(session.sim.fault_reason))
				break
		var elapsed := float(Time.get_ticks_usec() - started)
		if not faults.is_empty():
			return {"samples_us_per_tick": Array(values), "median_us_per_tick": -1.0,
				"p95_batch_mean_us_per_tick": -1.0, "fault": faults[0], "failed_during": "timed batch"}
		values.append(elapsed / float(_ticks_per_sample))
	return {
		"samples_us_per_tick": Array(values),
		"median_us_per_tick": _median(values),
		"p95_batch_mean_us_per_tick": _percentile(values, 0.95),
		"min_batch_mean_us_per_tick": _minimum(values),
		"max_batch_mean_us_per_tick": _maximum(values),
		"fault": "",
	}


func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() >> 1
	return sorted[middle] if sorted.size() % 2 == 1 else 0.5 * (sorted[middle - 1] + sorted[middle])


func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(fraction * sorted.size()) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _minimum(values: PackedFloat64Array) -> float:
	var result := INF
	for value in values:
		result = minf(result, value)
	return result if not values.is_empty() else 0.0


func _maximum(values: PackedFloat64Array) -> float:
	var result := -INF
	for value in values:
		result = maxf(result, value)
	return result if not values.is_empty() else 0.0
