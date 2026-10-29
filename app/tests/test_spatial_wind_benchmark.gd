## Benchmark admission tests, not performance or physical qualification.
extends "res://tests/bench_spatial_wind.gd"

# Captured from the unmodified benchmark with full-precision canonical JSON, M5-W05d-R5.
const CONTROL_CONFIG_SHA256 := {
	"legacy-v4-steady": "fce37479a8a1d7c4648f68451e27c7ea02f13266cba96986e2626840daa30eab",
	"spatial-v5-modes-8": "5287526f458f5ccd5094c3542cb4401f25fd7186d1ad3a8759702fe09e901b82",
	"spatial-v5-modes-24": "0f628e8537776582c59a3f48da24a986fc6a57b9b305bc58842c9dc2e7c00712",
	"spatial-v5-modes-64": "6089a24cc997388cf4e711f1d07717e1c8109d2cca94c58c98ab7a79b3eb0572",
}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL " + label)


func _run() -> void:
	for case_id: String in SESSION_WEATHER_CASES:
		var result: Dictionary = _session_weather_config(case_id)
		check(case_id + " original control config", result.ok and
			JSON.stringify(result.config, "", true, true).sha256_text() == CONTROL_CONFIG_SHA256[case_id])
	check("unknown weather case refused", not _session_weather_config("missing").ok)
	for case_id: String in ACTIVE_WEATHER_CASES:
		_check_active_case(case_id)
	var statistic: Dictionary = _timing_summary(PackedFloat64Array([5.0, 1.0, 3.0]))
	check("batch median", statistic.median_us_per_tick == 3.0)
	check("three-batch p95 is maximum batch mean", statistic.p95_batch_mean_us_per_tick == 5.0)
	check("raw batch order retained", statistic.samples_us_per_tick == [5.0, 1.0, 3.0])
	_check_diagnostic_restore()
	_check_x8_slots()
	_check_verification_report()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _write_progress_snapshot(_aircraft_id: String, _case_id: String, _stage: String, _payload: Dictionary) -> bool:
	# Unit checks exercise workload/result semantics. Full CLI evidence verifies actual JSON writes.
	return true


func _check_verification_report() -> void:
	_verify_only = true
	_samples = 3
	_ticks_per_sample = 2
	_warmup_ticks = 1
	var entry: Dictionary = AircraftCatalog.entry(AIRCRAFT_IDS[0])
	var measured := _run_session_case(entry, AIRCRAFT_IDS[0], ACTIVE_WEATHER_CASES[2])
	check("verification workload report accepted", measured.ok)
	if not measured.ok:
		return
	var result: Dictionary = measured.result
	check("verification report mode", result.measurement_mode == "verification-only")
	check("verification reports real workload counts", result.accepted_workload_ticks == 6 and result.accepted_warmup_ticks == 3)
	check("verification reports all fixture resets", result.reset_checks_passed == 9 and result.reset_checks_expected == 9)
	for key: String in result:
		check("verification contains no timing claim: " + key, not "us_per_" in key
			and not key.begins_with("ratio_") and not "budget_fraction" in key and not "timed_ticks" in key)


func _check_active_case(case_id: String) -> void:
	var result: Dictionary = _session_weather_config(case_id)
	check(case_id + " validates", result.ok)
	if not result.ok:
		return
	var config: Dictionary = result.config
	var identity_before := JSON.stringify(config, "", true, true)
	var counted := CountingWindField.new()
	check(case_id + " counting provider config", counted._apply_config(config))
	check(case_id + " isolated probes build", _prepare_coverage_probes(counted, config).ok)
	check(case_id + " no samples is not coverage", not _coverage_is_valid(counted, case_id))
	var production: Dictionary = WeatherField.build(config)
	check(case_id + " production provider config", production.ok)
	if not production.ok:
		return
	for time_s: float in [0.0, 0.5, 1.0, 1.5, 2.0]:
		var position := PackedFloat64Array([8.0 * time_s, 0.0, -20.0])
		var actual: PackedFloat64Array = counted.sample_world(position, time_s)
		var expected: PackedFloat64Array = production.field.sample_world(position, time_s)
		check(case_id + " instrumentation preserves wind " + str(time_s), actual.to_byte_array() == expected.to_byte_array())
	check(case_id + " actual active coverage", _coverage_is_valid(counted, case_id))
	check(case_id + " query range", counted.first_query_time_s == 0.0 and counted.last_query_time_s == 2.0)
	check(case_id + " gust agenda size", config.spatial_wind.gusts.events.size() == (24 if "gusts" in case_id else 0))
	check(case_id + " gust probe ownership", (counted.gust_probe != null) == ("gusts" in case_id))
	check(case_id + " thermal probe ownership", (counted.thermal_probe != null) == ("thermals" in case_id))
	check(case_id + " input unchanged", JSON.stringify(config, "", true, true) == identity_before)
	counted.reset_observations()
	counted.sample_world(PackedFloat64Array([0.0, 0.0, -20.0]), 4000.0)
	check(case_id + " expired agendas do not establish coverage", not _coverage_is_valid(counted, case_id))
	counted.reset_observations()
	counted.sample_world(PackedFloat64Array([0.0, 0.0, -20.0]), 1.0)
	counted.coverage_error = "manufactured probe failure"
	check(case_id + " failed probe refuses coverage", not _coverage_is_valid(counted, case_id))
	counted.reset_observations()
	check(case_id + " observations reset", counted.sample_world_calls == 0 and counted.gust_peak_mps == 0.0
		and counted.thermal_peak_mps == 0.0 and counted.coverage_error.is_empty())
	check(case_id + " fresh config not shared", _session_weather_config(case_id).config == config)


func _check_diagnostic_restore() -> void:
	var session: Node = FlightSession.new()
	session.setup(AircraftCatalog.data_for(AIRCRAFT_IDS[0], "ideal"))
	root.add_child(session)
	session.commands = Commands.neutral_commands()
	var case_id: String = ACTIVE_WEATHER_CASES[2]
	check("diagnostic weather setup", session.setup_weather(_session_weather_config(case_id).config))
	session.reset()
	var fixture := _capture_fixture(session)
	check("diagnostic initial fixture", fixture.ok)
	if not fixture.ok:
		session.free()
		return
	var original: Variant = session.environment.weather
	_ticks_per_sample = 2 # small functional failure-path test, not a benchmark CLI workload
	check("production diagnostic trajectory", _run_accepted_ticks(session, _ticks_per_sample).ok)
	var expected_hash := _snapshot_hash(session.sim)
	var successful := _measure_world_query_count(session, fixture, expected_hash, case_id)
	check("instrumented diagnostic accepted", successful.ok)
	check("instrumented provider restored", session.environment.weather == original and session.sim.tick == 0)
	if successful.ok:
		check("diagnostic final state agrees", successful.coverage.matches_production)
		check("diagnostic excludes reset queries", successful.coverage.accepted_ticks == 2
			and successful.coverage.first_query_time_s == 0.0
			and successful.coverage.last_query_time_s == 2.0 / TICK_HZ)
	var rejected := _measure_world_query_count(session, fixture, "manufactured mismatch", case_id)
	check("diagnostic state mismatch rejected", not rejected.ok)
	check("failure restores original field and fixture", session.environment.weather == original
		and session.sim.tick == 0 and _snapshot_hash(session.sim) == _fixture_hash(fixture))
	session.free()


func _fixture_hash(fixture: Dictionary) -> String:
	var bytes := PackedByteArray()
	for key: String in ["state", "aux", "continuous", "modes", "inputs", "last_loads"]:
		bytes.append_array(fixture.state[key].to_byte_array())
	return FlightLog.sha256(bytes).hex_encode()


func _check_x8_slots() -> void:
	for mode: String in ["ideal", "pack"]:
		var session: Node = FlightSession.new()
		var path := AircraftCatalog.data_for("moonrunner-x99", mode)
		check("X8 " + mode + " accepted catalog path", not path.is_empty())
		session.setup(path)
		root.add_child(session)
		check("X8 " + mode + " weather setup", session.setup_weather(_session_weather_config(ACTIVE_WEATHER_CASES[2]).config))
		session.reset()
		check("X8 " + mode + " start", _session_start_is_valid(session))
		var contract := _stage_wash_contract(session)
		check("X8 " + mode + " stage contract", contract.ok)
		if contract.ok:
			check("X8 " + mode + " reserved slot is not a query", contract.result.wind_flow_station_count == 9
				and contract.result.provider_queries_per_wind_flow_sample == 9)
		session.free()
