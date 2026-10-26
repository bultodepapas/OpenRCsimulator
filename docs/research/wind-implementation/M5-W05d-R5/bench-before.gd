# Observational accepted-tick provider benchmark; this is not an automatic test.
# Run observationally through tools/godot/run_checked.py with the pinned Godot binary.
extends SceneTree

const Config := preload("res://physics/wind_spatial_config.gd")
const SpatialField := preload("res://physics/wind_spatial_field.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const Commands := preload("res://input/commands.gd")
const Simulation := preload("res://sim/simulation.gd")
const WindFlow := preload("res://physics/wind_aircraft_flow.gd")
const WashTransport := preload("res://physics/wash_transport.gd")
const TICK_HZ := 240.0
const MODE_COUNTS := [8, 24, 64]
const STATION_COUNTS := [1, 8, 32]
const AIRCRAFT_IDS := ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "turbo-lumber-evolution"]
const SESSION_WEATHER_CASES := ["legacy-v4-steady", "spatial-v5-modes-8", "spatial-v5-modes-24", "spatial-v5-modes-64"]


## Instrumented clone used only for one untimed query-count tick after each scenario is timed.
## The timed path keeps the production WindField object and call overhead unchanged.
class CountingWindField:
	extends "res://physics/wind_field.gd"
	var sample_world_calls := 0

	func sample_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		sample_world_calls += 1
		return super.sample_world(position_ned, time_s)

var _samples := 3
var _ticks_per_sample := 480
var _warmup_ticks := 240
var _output_path := ""
var _full_session := false
var _compile_only := false
var _source_revision := "workspace-uncommitted"
var _source_manifest_sha256 := ""
var _requested_aircraft_ids: Array[String] = []
var _requested_case_ids: Array[String] = []
var _progress_directory := ""


func _initialize() -> void:
	if not _parse_args():
		quit(1)
		return
	if _compile_only:
		print("benchmark script parsed")
		quit()
		return
	if _full_session:
		_run_full_session_benchmark()
		return
	_run_provider_benchmark()


func _run_provider_benchmark() -> void:
	var report := {
		"format": "openrc-spatial-wind-stage-bench v1",
		"source_revision": _source_revision,
		"machine": {
			"os": OS.get_name(),
			"architecture": Engine.get_architecture_name(),
			"processor": OS.get_processor_name(),
			"logical_cpu_count": OS.get_processor_count(),
			"godot": Engine.get_version_info(),
		},
		"tick_hz": TICK_HZ,
		"provider_format": "openrc-spatial-wind v2 + balanced thermal field v1",
		"timing_method": "Warm each immutable provider with untimed 240 Hz accepted-tick queries, then time batches of accepted ticks. Every accepted tick samples all authored wind stations exactly once. Setup, config resolution, receipts, aircraft work and rendering are excluded; this isolates provider sample cost.",
		"composition": "3 m/s neutral mean, seeded vector-potential turbulence and one active balanced thermal agenda cell; no aircraft, RNG-at-query or session callbacks.",
		"samples": _samples,
		"ticks_per_sample": _ticks_per_sample,
		"warmup_ticks": _warmup_ticks,
		"stations_per_accepted_tick": STATION_COUNTS.duplicate(),
		"mode_counts": MODE_COUNTS.duplicate(),
		"cases": [],
	}
	for mode_count: int in MODE_COUNTS:
		for station_count: int in STATION_COUNTS:
			var case := _run_case(mode_count, station_count)
			if not case.ok:
				push_error("spatial stage benchmark failed: " + str(case.error))
				quit(1)
				return
			report.cases.append(case.result)
			print("measured %d modes / %d stations / median %.3f µs per accepted tick (%.4f µs per query)" % [
				mode_count, station_count, case.result.median_us_per_tick, case.result.median_us_per_query,
			])
	_write_report(report)


func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--full-session":
			_full_session = true
		elif arg == "--compile-only":
			_compile_only = true
		elif arg.begins_with("--revision="):
			_source_revision = arg.trim_prefix("--revision=")
		elif arg.begins_with("--manifest-sha256="):
			_source_manifest_sha256 = arg.trim_prefix("--manifest-sha256=")
		elif arg.begins_with("--aircraft="):
			var aircraft_id := arg.trim_prefix("--aircraft=")
			if aircraft_id not in _requested_aircraft_ids:
				_requested_aircraft_ids.append(aircraft_id)
		elif arg.begins_with("--case="):
			var case_id := arg.trim_prefix("--case=")
			if case_id not in _requested_case_ids:
				_requested_case_ids.append(case_id)
		elif arg.begins_with("--samples="):
			_samples = clampi(int(arg.trim_prefix("--samples=")), 3, 20)
		elif arg.begins_with("--ticks-per-sample="):
			_ticks_per_sample = clampi(int(arg.trim_prefix("--ticks-per-sample=")), 1, 10000)
		elif arg.begins_with("--warmup-ticks="):
			_warmup_ticks = clampi(int(arg.trim_prefix("--warmup-ticks=")), 0, 2000)
		elif arg.begins_with("--output="):
			_output_path = arg.trim_prefix("--output=")
	if _warmup_ticks + _samples * _ticks_per_sample > int(86400.0 * TICK_HZ):
		push_error("benchmark tick range exceeds the declared weather horizon")
		return false
	if _full_session:
		_samples = maxi(_samples, 3)
		_ticks_per_sample = maxi(_ticks_per_sample, 480)
		_warmup_ticks = maxi(_warmup_ticks, 240)
		if not _compile_only and _output_path.is_empty():
			push_error("--full-session requires --output so progress JSON is retained")
			return false
	return true


func _run_full_session_benchmark() -> void:
	if Engine.physics_ticks_per_second != int(TICK_HZ):
		push_error("full-session benchmark requires exactly 240 physics ticks per second")
		quit(1)
		return
	_progress_directory = _output_path + ".progress-" + str(Time.get_ticks_usec())
	var directory_error := DirAccess.make_dir_recursive_absolute(_progress_directory)
	if directory_error != OK:
		push_error("could not create per-case progress directory: " + _progress_directory)
		quit(1)
		return
	var selected_aircraft_ids: Array[String] = []
	if _requested_aircraft_ids.is_empty():
		for aircraft_id: String in AIRCRAFT_IDS:
			selected_aircraft_ids.append(aircraft_id)
	else:
		for aircraft_id: String in _requested_aircraft_ids:
			if aircraft_id not in AIRCRAFT_IDS:
				push_error("unknown --aircraft ID: " + aircraft_id)
				quit(1)
				return
			selected_aircraft_ids.append(aircraft_id)
	var selected_case_ids: Array[String] = []
	if _requested_case_ids.is_empty():
		for case_id: String in SESSION_WEATHER_CASES:
			selected_case_ids.append(case_id)
	else:
		for case_id: String in _requested_case_ids:
			if case_id not in SESSION_WEATHER_CASES:
				push_error("unknown --case ID: " + case_id)
				quit(1)
				return
			selected_case_ids.append(case_id)
	var report := {
		"format": "openrc-spatial-wind-full-session-bench v1",
		"source_revision": _source_revision,
		"source_manifest_sha256": _source_manifest_sha256,
		"progress_directory": _progress_directory,
		"filters": {"aircraft_ids": selected_aircraft_ids, "case_ids": selected_case_ids},
		"machine": {
			"os": OS.get_name(),
			"architecture": Engine.get_architecture_name(),
			"processor": OS.get_processor_name(),
			"logical_cpu_count": OS.get_processor_count(),
			"godot": Engine.get_version_info(),
		},
		"tick_hz": TICK_HZ,
		"samples": _samples,
		"warmup_ticks_per_sample": _warmup_ticks,
		"timed_ticks_per_sample": _ticks_per_sample,
		"comparison": "openrc-weather v4 steady 3 m/s from 270 deg versus v5 spatial neutral mean matched at 10 m AGL with 0.3 m/s nominal turbulence RMS and 8, 24, or 64 modes; no thermal cells or session OU turbulence",
		"timing_method": "For each aircraft/weather scenario, FlightSession setup, v5 install, trim/reset and fixture capture happen before timing. Each sequential batch restores the exact fixture, advances 240 warmup ticks, restores again, then times 480 direct Simulation.step calls. State validation, reset checks, final hashing and the separate query-count diagnostic tick are outside the timed interval. Rendering and UI are absent.",
		"accepted_state_validation": "Every warmup and timed batch must advance exactly the requested Simulation.tick count with no fault, no crash, and finite accepted body, input, auxiliary, continuous and load arrays. Reset checks compare packed state/input/aux/mode/continuous/load bytes against the captured scenario fixture.",
		"session_order": "Sequential only; explicit --aircraft and --case filter order is retained. Defaults are Jensen Ugly Stick, Extra 300S, Turbo Lumber, each with legacy steady then spatial 8, 24, and 64 modes.",
		"wind_query_counter": "A one-tick untimed diagnostic replaces the installed WindField with an equivalent counting subclass after measurement; the reported count is all position-aware WindField.sample_world calls through the full stage and wash path.",
		"aircraft": [],
	}
	for aircraft_id: String in selected_aircraft_ids:
		var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
		if entry.is_empty() or not AircraftCatalog.can_fly(aircraft_id) or AircraftCatalog.is_rotorcraft(aircraft_id):
			push_error("unknown or non-fixed-wing aircraft catalog ID: " + aircraft_id)
			quit(1)
			return
		var cases: Array[Dictionary] = []
		for case_id: String in selected_case_ids:
			print("starting full-session case ", aircraft_id, " / ", case_id)
			if not _write_progress_snapshot(aircraft_id, case_id, "started", {"status": "started"}):
				push_error("could not write start progress for %s / %s" % [aircraft_id, case_id])
				quit(1)
				return
			var measured: Dictionary = _run_session_case(entry, aircraft_id, case_id)
			if not bool(measured.get("ok", false)):
				var failure_message := str(measured.get("error", "case failed without an error detail"))
				_write_progress_snapshot(aircraft_id, case_id, "failed", {"status": "failed", "error": failure_message})
				push_error("full-session benchmark failed for %s / %s: %s" % [aircraft_id, case_id, failure_message])
				quit(1)
				return
			cases.append(measured.result)
			if not _write_progress_snapshot(aircraft_id, case_id, "complete", {"status": "complete", "result": measured.result}):
				push_error("could not write completion progress for %s / %s" % [aircraft_id, case_id])
				quit(1)
				return
			print("measured ", aircraft_id, " / ", case_id, " / median ", measured.result.median_us_per_tick,
				" µs/tick / wind queries ", measured.result.queries_per_accepted_tick_untimed)
		var legacy_baseline_us := -1.0
		for item: Dictionary in cases:
			if item.case_id == "legacy-v4-steady":
				legacy_baseline_us = float(item.median_us_per_tick)
				break
		for index: int in cases.size():
			var item: Dictionary = cases[index]
			if item.case_id == "legacy-v4-steady":
				item["ratio_to_legacy_v4"] = 1.0
				item["increase_pct_vs_legacy_v4"] = 0.0
			elif legacy_baseline_us > 0.0:
				item["ratio_to_legacy_v4"] = float(item.median_us_per_tick) / legacy_baseline_us
				item["increase_pct_vs_legacy_v4"] = (float(item.ratio_to_legacy_v4) - 1.0) * 100.0
			else:
				item["baseline_available"] = false
			item["tick_budget_fraction"] = float(item.median_us_per_tick) / (1000000.0 / TICK_HZ)
			cases[index] = item
		report.aircraft.append({
			"id": aircraft_id,
			"name": str(entry.get("name", aircraft_id)),
			"data": str(entry.get("data", "")),
			"stage_wash_consumers": cases[0].stage_wash_consumers,
			"cases": cases,
		})
	_write_report(report)


func _session_weather_config(case_id: String) -> Dictionary:
	var raw: Dictionary
	if case_id == "legacy-v4-steady":
		raw = WindConfig.upgrade_column(WindConfig.defaults())
		raw.speed_mps = 3.0
		raw.from_deg = 270.0
	else:
		var mode_count := 0
		match case_id:
			"spatial-v5-modes-8": mode_count = 8
			"spatial-v5-modes-24": mode_count = 24
			"spatial-v5-modes-64": mode_count = 64
			_: return {"ok": false, "config": {}, "errors": PackedStringArray(["unknown session weather case"])}
		raw = WindConfig.spatial_defaults()
		raw.spatial_wind.identity.seed_u32 = 20261025
		raw.spatial_wind.identity.world_epoch_id_u32 = 451
		raw.spatial_wind.profile.reference_speed_mps = 3.0
		raw.spatial_wind.profile.reference_from_deg = 270.0
		raw.spatial_wind.turbulence.rms_mps = 0.3
		raw.spatial_wind.turbulence.mode_count = mode_count
	return WindConfig.validate(raw)


func _run_session_case(entry: Dictionary, aircraft_id: String, case_id: String) -> Dictionary:
	var weather_result: Dictionary = _session_weather_config(case_id)
	if not weather_result.ok:
		return {"ok": false, "error": "weather config invalid: " + str(weather_result.errors)}
	var session: Node = FlightSession.new()
	session.setup(str(entry.data))
	root.add_child(session)
	if not session.is_flyable():
		var setup_error := str(session.pause_reason)
		session.free()
		return {"ok": false, "error": "aircraft setup refused: " + setup_error}
	session.commands = Commands.neutral_commands()
	if not session.setup_weather(weather_result.config):
		var weather_error := str(session.weather_error)
		session.free()
		return {"ok": false, "error": "session rejected weather: " + weather_error}
	session.reset()
	if not _session_start_is_valid(session):
		var reset_error := str(session.start_error) + "; " + str(session.sim.fault_reason)
		session.free()
		return {"ok": false, "error": "session weather reset refused or returned invalid state: " + reset_error}
	var installed_config: Dictionary = session.weather_configuration()
	if installed_config != weather_result.config:
		session.free()
		return {"ok": false, "error": "installed weather config differs from the validated request"}
	var consumers: Dictionary = _stage_wash_contract(session, case_id)
	if not consumers.ok:
		var consumer_error := str(consumers.error)
		session.free()
		return {"ok": false, "error": consumer_error}
	var fixture: Dictionary = _capture_fixture(session)
	if not fixture.ok:
		var fixture_error := str(fixture.error)
		session.free()
		return {"ok": false, "error": "could not capture valid reset fixture: " + fixture_error}
	var timings := PackedFloat64Array()
	var final_hashes := PackedStringArray()
	var reset_checks := 0
	var total_warmup_accepted := 0
	var total_timed_accepted := 0
	for sample_index: int in _samples:
		var restored: Dictionary = _restore_fixture(session, fixture)
		if not restored.ok:
			var restore_error := str(restored.error)
			session.free()
			return {"ok": false, "error": "before warmup reset: " + restore_error}
		reset_checks += 1
		var warmup: Dictionary = _run_accepted_ticks(session, _warmup_ticks)
		if not warmup.ok:
			var warmup_error := str(warmup.error)
			session.free()
			return {"ok": false, "error": "warmup batch %d: %s" % [sample_index, warmup_error]}
		total_warmup_accepted += int(warmup.accepted_ticks)
		if not _write_progress_snapshot(aircraft_id, case_id, "warmup-%02d" % sample_index, {
			"status": "warmup_complete", "batch_index": sample_index,
			"accepted_warmup_ticks_total": total_warmup_accepted,
			"accepted_timed_ticks_total": total_timed_accepted,
		}):
			session.free()
			return {"ok": false, "error": "could not write warmup progress snapshot for batch %d" % sample_index}
		restored = _restore_fixture(session, fixture)
		if not restored.ok:
			var restore_error := str(restored.error)
			session.free()
			return {"ok": false, "error": "before timed batch reset: " + restore_error}
		reset_checks += 1
		var first_tick := int(session.sim.tick)
		var started := Time.get_ticks_usec()
		var timed_fault := ""
		for _tick: int in _ticks_per_sample:
			session.sim.step()
			if not session.sim.fault_reason.is_empty():
				timed_fault = str(session.sim.fault_reason)
				break
		var elapsed_us := float(Time.get_ticks_usec() - started)
		var accepted_ticks := int(session.sim.tick) - first_tick
		if not timed_fault.is_empty() or accepted_ticks != _ticks_per_sample:
			var acceptance_error := timed_fault if not timed_fault.is_empty() else "accepted %d / %d ticks" % [accepted_ticks, _ticks_per_sample]
			session.free()
			return {"ok": false, "error": "timed batch %d: %s" % [sample_index, acceptance_error]}
		if not _session_state_is_finite(session) or not session.crash.is_empty():
			session.free()
			return {"ok": false, "error": "timed batch %d ended with a crash or nonfinite accepted state" % sample_index}
		timings.append(elapsed_us / float(_ticks_per_sample))
		total_timed_accepted += accepted_ticks
		final_hashes.append(_snapshot_hash(session.sim))
		if not _write_progress_snapshot(aircraft_id, case_id, "batch-%02d" % sample_index, {
			"status": "timed_batch_complete", "batch_index": sample_index,
			"accepted_warmup_ticks_total": total_warmup_accepted,
			"accepted_timed_ticks_total": total_timed_accepted,
			"samples_us_per_tick": _float64_array(timings),
			"median_us_per_tick": _median(timings),
			"final_state_sha256_per_batch": _string_array(final_hashes),
		}):
			session.free()
			return {"ok": false, "error": "could not write timed-batch progress snapshot for batch %d" % sample_index}
	if not _all_strings_equal(final_hashes):
		session.free()
		return {"ok": false, "error": "same-fixture timed batches did not reproduce the same final state hash"}
	var final_restore: Dictionary = _restore_fixture(session, fixture)
	if not final_restore.ok:
		var final_error := str(final_restore.error)
		session.free()
		return {"ok": false, "error": "final reset validation failed: " + final_error}
	reset_checks += 1
	var query_diagnostic: Dictionary = _measure_world_query_count(session, fixture)
	if not query_diagnostic.ok:
		var query_error := str(query_diagnostic.error)
		session.free()
		return {"ok": false, "error": "untimed query-count diagnostic failed: " + query_error}
	reset_checks += 1
	var result := {
		"case_id": case_id,
		"weather_format": str(installed_config.format),
		"mode_count": 0 if case_id == "legacy-v4-steady" else int(installed_config.spatial_wind.turbulence.mode_count),
		"weather_configuration": installed_config,
		"weather_receipt": session.call("_spatial_weather_receipt", session.environment.weather) if session.environment.weather.is_spatial() else {},
		"samples_us_per_tick": _float64_array(timings),
		"median_us_per_tick": _median(timings),
		"p95_batch_mean_us_per_tick": _percentile(timings, 0.95),
		"min_batch_mean_us_per_tick": _minimum(timings),
		"max_batch_mean_us_per_tick": _maximum(timings),
		"queries_per_accepted_tick_untimed": query_diagnostic.sample_world_calls,
		"timed_ticks_per_batch": _ticks_per_sample,
		"warmup_ticks_per_batch": _warmup_ticks,
		"accepted_timed_ticks": total_timed_accepted,
		"accepted_warmup_ticks": total_warmup_accepted,
		"reset_checks_passed": reset_checks,
		"reset_checks_expected": 2 * _samples + 2,
		"final_state_sha256_per_batch": _string_array(final_hashes),
		"final_states_repeatable": _all_strings_equal(final_hashes),
		"stage_wash_consumers": consumers.result,
		"setup_start_state": _float64_array(fixture.state.state),
		"aircraft_status": str(entry.get("status", "")),
	}
	session.free()
	return {"ok": true, "result": result}


func _session_start_is_valid(session: Node) -> bool:
	return session != null and session.sim != null and session.sim.tick == 0 \
		and session.sim.fault_reason.is_empty() and session.start_error.is_empty() \
		and _session_state_is_finite(session) and session.crash.is_empty()


func _session_state_is_finite(session: Node) -> bool:
	if session == null or session.sim == null:
		return false
	var sim: Node = session.sim
	if not Simulation.state_is_valid(sim.state) or not _finite_float64(sim.inputs) or not _finite_float64(sim.aux) \
			or not _finite_float64(sim.continuous) or not _finite_float64(sim.last_loads) or sim.last_loads.size() != 6:
		return false
	for mode: int in sim.modes:
		if mode < 0:
			return false
	return is_finite(sim.time())


func _stage_wash_contract(session: Node, case_id: String) -> Dictionary:
	var model: Dictionary = session.aircraft.model
	var propulsion: Dictionary = model.get("propulsion", {})
	var slipstream: Dictionary = propulsion.get("slipstream", {})
	var pieces: Array = slipstream.get("pieces", [])
	var wash_transport_enabled: bool = WashTransport.enabled(propulsion)
	var geometry: Dictionary = WindFlow.geometry(model)
	var simulation_model: Variant = session.sim.model
	var stage_active: bool = simulation_model.stage.is_valid()
	var split_load_route_active: bool = simulation_model.block_loads.is_valid() and simulation_model.block_derivative.is_valid()
	var stage_air_probe: Dictionary = session.air_data(session.sim.state, 0.0)
	var spatial_contract_valid := true
	var sampler_valid := false
	if case_id.begins_with("spatial-"):
		var sampler: Variant = stage_air_probe.get("ambient_delta_body_at", Callable())
		sampler_valid = sampler is Callable and sampler.is_valid()
		spatial_contract_valid = stage_air_probe.get("spatial_air_law", "") == WindFlow.STAGE_AIR_LAW and sampler_valid
	else:
		sampler_valid = stage_air_probe.has("v_air") and stage_air_probe.v_air.size() == 3
		spatial_contract_valid = sampler_valid
	if not geometry.get("ok", false) or geometry.offsets_body.is_empty():
		return {"ok": false, "error": "fixed-wing spatial station geometry is invalid: %s" % str(geometry.get("errors", PackedStringArray()))}
	if not spatial_contract_valid or not (stage_active or split_load_route_active):
		return {"ok": false, "error": "full fixed-wing stage/load consumers are not active for this scenario"}
	return {
		"ok": true,
		"result": {
			"fixed_wing_load_path": "FlightSession._loads -> _wash_loads -> Dynamics.loads_from_air",
			"quasi_static_slipstream_piece_count": pieces.size(),
			"lagged_wash_transport_enabled": wash_transport_enabled,
			"lagged_wash_transport_piece_count": pieces.size() if wash_transport_enabled else 0,
			"continuous_state_size": session.sim.continuous.size(),
			"wind_flow_station_count": int(geometry.offsets_body.size() / 3),
			"provider_queries_per_wind_flow_sample": 1 + int(geometry.offsets_body.size() / 3),
			"simulation_stage_callback": stage_active,
			"simulation_split_load_route": split_load_route_active,
			"stage_air_probe_contract_valid": spatial_contract_valid,
			"stage_point_sampler_valid": sampler_valid if case_id.begins_with("spatial-") else false,
			"actual_full_simulation_step_used": true,
		},
	}


func _capture_fixture(session: Node) -> Dictionary:
	if not _session_state_is_finite(session) or session.sim.tick != 0:
		return {"ok": false, "error": "initial scenario is not a finite tick-zero session"}
	return {"ok": true, "state": _snapshot(session.sim)}


func _restore_fixture(session: Node, fixture: Dictionary) -> Dictionary:
	var sim: Node = session.sim
	var state: Dictionary = fixture.state
	sim.inputs = state.inputs.duplicate()
	sim.aux = state.aux.duplicate()
	sim.modes = state.modes.duplicate()
	sim.continuous = state.continuous.duplicate()
	sim.fault_reason = ""
	if not sim.reset(state.state.duplicate()):
		return {"ok": false, "error": str(sim.fault_reason)}
	if sim.tick != 0 or not sim.fault_reason.is_empty() or not _session_state_is_finite(session):
		return {"ok": false, "error": "Simulation.reset did not produce a finite accepted tick-zero state"}
	var restored: Dictionary = _snapshot(sim)
	for key: String in ["state", "inputs", "aux", "modes", "continuous", "last_loads"]:
		if not _packed_values_equal(restored[key], state[key]):
			return {"ok": false, "error": "Simulation.reset changed fixture array '%s'" % key}
	return {"ok": true}


func _run_accepted_ticks(session: Node, count: int) -> Dictionary:
	var sim: Node = session.sim
	var first_tick := int(sim.tick)
	for _tick: int in count:
		sim.step()
		if not sim.fault_reason.is_empty():
			return {"ok": false, "error": str(sim.fault_reason), "accepted_ticks": int(sim.tick) - first_tick}
	var accepted := int(sim.tick) - first_tick
	if accepted != count or not _session_state_is_finite(session) or not session.crash.is_empty():
		return {"ok": false, "error": "accepted tick count or finite-state/crash validation failed", "accepted_ticks": accepted}
	return {"ok": true, "accepted_ticks": accepted}


func _snapshot(sim: Node) -> Dictionary:
	return {
		"state": sim.state.duplicate(),
		"inputs": sim.inputs.duplicate(),
		"aux": sim.aux.duplicate(),
		"modes": sim.modes.duplicate(),
		"continuous": sim.continuous.duplicate(),
		"last_loads": sim.last_loads.duplicate(),
	}


func _packed_values_equal(left: Variant, right: Variant) -> bool:
	return typeof(left) == typeof(right) and left.to_byte_array() == right.to_byte_array()


func _finite_float64(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _snapshot_hash(sim: Node) -> String:
	var bytes := PackedByteArray()
	var state: Dictionary = _snapshot(sim)
	for key: String in ["state", "aux", "continuous", "modes", "inputs", "last_loads"]:
		bytes.append_array(state[key].to_byte_array())
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


func _measure_world_query_count(session: Node, fixture: Dictionary) -> Dictionary:
	var original: Variant = session.environment.weather
	var original_configuration: Dictionary = original.configuration()
	var counted: CountingWindField = CountingWindField.new()
	if not counted._apply_config(original_configuration):
		return {"ok": false, "error": "equivalent counting field rejected the installed weather config"}
	if counted.configuration() != original_configuration or counted.spatial_content_hash() != original.spatial_content_hash():
		return {"ok": false, "error": "counting field changed the installed weather identity"}
	session.environment.weather = counted
	var restored: Dictionary = _restore_fixture(session, fixture)
	if not restored.ok:
		return {"ok": false, "error": "counting field fixture reset failed: " + str(restored.error)}
	counted.sample_world_calls = 0
	session.sim.step()
	if not session.sim.fault_reason.is_empty() or session.sim.tick != 1 or not _session_state_is_finite(session):
		return {"ok": false, "error": "counting diagnostic tick was not accepted"}
	var calls := counted.sample_world_calls
	if calls <= 0:
		return {"ok": false, "error": "full session did not invoke position-aware wind sampling"}
	return {"ok": true, "sample_world_calls": calls}


func _write_report(report: Dictionary) -> void:
	var json := JSON.stringify(report, "\t", true, true) + "\n"
	if _output_path.is_empty():
		print(json)
		quit()
		return
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write benchmark output: " + _output_path)
		quit(1)
		return
	file.store_string(json)
	file.close()
	print("wrote ", _output_path)
	quit()


func _write_progress_snapshot(aircraft_id: String, case_id: String, stage: String, payload: Dictionary) -> bool:
	if _progress_directory.is_empty():
		return false
	var record := {
		"format": "openrc-spatial-wind-session-progress v1",
		"source_revision": _source_revision,
		"source_manifest_sha256": _source_manifest_sha256,
		"aircraft_id": aircraft_id,
		"case_id": case_id,
		"stage": stage,
	}
	record.merge(payload, true)
	var filename := "%s--%s--%s.json" % [aircraft_id, case_id, stage]
	return _write_atomic_json(_progress_directory.path_join(filename), record)


func _write_atomic_json(path: String, payload: Dictionary) -> bool:
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t", true, true) + "\n")
	file.flush()
	file.close()
	return DirAccess.rename_absolute(temporary_path, path) == OK


func _run_case(mode_count: int, station_count: int) -> Dictionary:
	var raw := Config.defaults()
	raw.identity.seed_u32 = 20261025 + mode_count
	raw.identity.world_epoch_id_u32 = 451
	raw.profile.reference_speed_mps = 3.0
	raw.profile.reference_from_deg = 270.0
	raw.turbulence.rms_mps = 0.3
	raw.turbulence.mode_count = mode_count
	var v2: Dictionary = Config.thermal_defaults(raw)
	if not v2.ok:
		return {"ok": false, "error": str(v2.errors)}
	v2.config.thermal_field.cells = [{
		"id": "bench-active-cell",
		"birth_s": 0.0,
		"duration_s": 720.0,
		"center_ne_m": [0.0, 0.0],
		"drift_ne_mps": [0.2, -0.1],
		"radius_m": 60.0,
		"top_agl_m": 200.0,
		"peak_updraft_mps": 1.0,
	}]
	var built: Dictionary = SpatialField.build(v2.config)
	if not built.ok:
		return {"ok": false, "error": str(built.errors)}
	var stations: Array[PackedFloat64Array] = []
	for index: int in station_count:
		var north := float((index * 37) % 101 - 50)
		var east := float((index * 19) % 101 - 50)
		var height := 5.0 + float(index % 20) * 5.0
		stations.append(PackedFloat64Array([north, east, -height]))
	var result: Dictionary = _benchmark(built.field, stations)
	if not result.ok:
		return result
	var ticks_per_batch := float(_ticks_per_sample)
	return {
		"ok": true,
		"result": {
			"mode_count": mode_count,
			"station_count": station_count,
			"queries_per_accepted_tick": station_count,
			"field_content_hash": built.field.content_hash(),
			"nested_thermal_content_hash": built.field.thermal_content_hash(),
			"samples_us_per_tick": _float64_array(result.samples_us_per_tick),
			"median_us_per_tick": _median(result.samples_us_per_tick),
			"p95_batch_mean_us_per_tick": _percentile(result.samples_us_per_tick, 0.95),
			"min_batch_mean_us_per_tick": _minimum(result.samples_us_per_tick),
			"max_batch_mean_us_per_tick": _maximum(result.samples_us_per_tick),
			"median_us_per_query": _median(result.samples_us_per_tick) / float(station_count),
			"timed_query_count_per_case": int(ticks_per_batch) * station_count * _samples,
			"sample_checksum": result.sample_checksum,
		},
	}


func _benchmark(field: Variant, stations: Array[PackedFloat64Array]) -> Dictionary:
	var samples := PackedFloat64Array()
	var checksum := 0.0
	var warmup: Dictionary = _sample_ticks(field, stations, 0, _warmup_ticks)
	if not warmup.ok:
		return {"ok": false, "error": "warmup: " + str(warmup.error)}
	for sample: int in _samples:
		var start_tick := _warmup_ticks + sample * _ticks_per_sample
		var started := Time.get_ticks_usec()
		var batch: Dictionary = _sample_ticks(field, stations, start_tick, _ticks_per_sample)
		var elapsed_us := float(Time.get_ticks_usec() - started)
		if not batch.ok:
			return {"ok": false, "error": "timed batch: " + str(batch.error)}
		samples.append(elapsed_us / float(_ticks_per_sample))
		checksum += float(batch.checksum)
	return {"ok": true, "samples_us_per_tick": samples, "sample_checksum": checksum}


func _sample_ticks(field: Variant, stations: Array[PackedFloat64Array], start_tick: int, tick_count: int) -> Dictionary:
	var checksum := 0.0
	for offset: int in tick_count:
		var simulation_time_s := float(start_tick + offset) / TICK_HZ
		for position_ned: PackedFloat64Array in stations:
			var sample: Dictionary = field.sample_world(position_ned, simulation_time_s)
			if not sample.ok:
				return {"ok": false, "error": str(sample.error)}
			var wind: PackedFloat64Array = sample.wind_ned_mps
			checksum += wind[0] + 0.25 * wind[1] - 0.125 * wind[2]
			if not is_finite(checksum):
				return {"ok": false, "error": "sample checksum overflowed"}
	return {"ok": true, "checksum": checksum}


func _median(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() >> 1
	return sorted[middle] if sorted.size() % 2 == 1 else 0.5 * (sorted[middle - 1] + sorted[middle])


func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(fraction * sorted.size()) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _minimum(values: PackedFloat64Array) -> float:
	var result := INF
	for value: float in values:
		result = minf(result, value)
	return result


func _maximum(values: PackedFloat64Array) -> float:
	var result := -INF
	for value: float in values:
		result = maxf(result, value)
	return result


func _all_strings_equal(values: PackedStringArray) -> bool:
	if values.is_empty():
		return false
	for value: String in values:
		if value != values[0]:
			return false
	return true


func _float64_array(values: PackedFloat64Array) -> Array:
	var result: Array = []
	for value: float in values:
		result.append(value)
	return result


func _string_array(values: PackedStringArray) -> Array:
	var result: Array = []
	for value: String in values:
		result.append(value)
	return result
