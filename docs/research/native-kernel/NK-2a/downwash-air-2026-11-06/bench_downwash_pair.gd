# NK-2a / A6 O4: paired original-source/candidate timing using the existing weather bench fixtures.
# Run outside automatic tests. --baseline=<original flight_session.gd> --output=<new JSON> [--ticks=240]
extends "res://tests/bench_spatial_wind.gd"

const PAIRS := 8
const CALLBACKS := 256
var _pair_ticks := 240
var _baseline_path := ""
var _pair_output := ""
var _pair_error := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="): _baseline_path = arg.trim_prefix("--baseline=")
		elif arg.begins_with("--output="): _pair_output = arg.trim_prefix("--output=")
		elif arg.begins_with("--ticks="):
			var value := arg.trim_prefix("--ticks=")
			if not value.is_valid_int() or int(value) < 1 or int(value) > 10000: _pair_error = "ticks must be within 1..10000"
			else: _pair_ticks = int(value)
		else: _pair_error = "unknown argument: " + arg
	if not FileAccess.file_exists(_baseline_path) or _pair_output.is_empty() or FileAccess.file_exists(_pair_output):
		_pair_error = "baseline must exist and output must name a new file"
	_pair_run.call_deferred()

func _pair_run() -> void:
	if not _pair_error.is_empty():
		printerr(_pair_error)
		quit(1)
		return
	var baseline: Script = load(_baseline_path)
	if baseline == null:
		printerr("baseline script could not load")
		quit(1)
		return
	var report := {
		format = "openrc-downwash-pair v1", complete = false,
		baseline_sha256 = FileAccess.get_sha256(_baseline_path),
		candidate_sha256 = FileAccess.get_sha256("res://sim/flight_session.gd"),
		benchmark_sha256 = FileAccess.get_sha256(get_script().resource_path),
		fixture_helpers_sha256 = FileAccess.get_sha256("res://tests/bench_spatial_wind.gd"),
		machine = {os = OS.get_name(), cpu = OS.get_processor_name(), godot = Engine.get_version_info().string},
		pairs = PAIRS, callbacks_per_batch = CALLBACKS, ticks_per_batch = _pair_ticks,
		scope = "Detached GDScript Stik, no scenery/companions/render/input observer; production kernel pre-step and full Simulation.step including session accepted-step handlers. Alternating AB/BA; batch means, not tick percentiles. Warmup, resets, query instrumentation and final-state hashes excluded from timing.",
		cases = [],
	}
	for case_id: String in ["legacy-v4-steady", "spatial-v5-modes-8"]:
		var sessions: Array[Node] = []
		var fixtures: Array[Dictionary] = []
		var weather: Dictionary = _session_weather_config(case_id)
		for script: Script in [baseline, FlightSession]:
			var flight: Node = script.new()
			flight.input_enabled = false
			flight.physics_enabled = false
			flight.crash_auto_restart = false
			flight.setup()
			if not weather.ok or not flight.setup_weather(weather.config): _pair_error = "weather setup failed"
			flight.reset()
			if not _session_start_is_valid(flight): _pair_error = "invalid initial state"
			sessions.append(flight)
			fixtures.append(_capture_fixture(flight))
		var row := {case_id = case_id, weather = weather.config, backend = sessions[1].stage_backend_status(), callback = [], tick = []}
		if _snapshot_hash(sessions[0].sim) != _snapshot_hash(sessions[1].sim): _pair_error = "initial state differs"
		for mode: String in ["callback", "tick"]:
			for pair: int in PAIRS:
				if not _pair_error.is_empty(): break
				var batch := {order = "AB" if pair % 2 == 0 else "BA", baseline_us = 0.0, candidate_us = 0.0, fingerprints = []}
				var fingerprints := ["", ""]
				for index: int in ([0, 1] if pair % 2 == 0 else [1, 0]):
					var flight: Node = sessions[index]
					if not _restore_fixture(flight, fixtures[index]).ok: _pair_error = "warmup reset failed"
					for warm: int in 32:
						if mode == "callback": flight._kernel_pre_step(flight.sim.aux, flight.sim.inputs, flight.sim.dt())
						else: flight.sim.step()
					if not _restore_fixture(flight, fixtures[index]).ok: _pair_error = "timed reset failed"
					var count: int = CALLBACKS if mode == "callback" else _pair_ticks
					var output := PackedFloat64Array()
					var started := Time.get_ticks_usec()
					for sample: int in count:
						if mode == "callback": output = flight._kernel_pre_step(flight.sim.aux, flight.sim.inputs, flight.sim.dt())
						else: flight.sim.step()
					var elapsed: int = Time.get_ticks_usec() - started
					batch["baseline_us" if index == 0 else "candidate_us"] = float(elapsed) / count
					if not flight.sim.fault_reason.is_empty() or not _session_state_is_finite(flight): _pair_error = "nonfinite or refused timed workload"
					if mode == "tick" and flight.sim.tick != _pair_ticks: _pair_error = "accepted tick count differs"
					fingerprints[index] = _snapshot_hash(flight.sim) if mode == "tick" else _hash_output(output)
				batch.fingerprints = fingerprints
				if fingerprints[0] != fingerprints[1]: _pair_error = "paired output differs"
				row[mode].append(batch)
			if not _pair_error.is_empty(): break
		for flight: Node in sessions: flight.free()
		report.cases.append(row)
		print("paired ", case_id, " error=", _pair_error)
		if not _pair_error.is_empty(): break
	if FileAccess.get_sha256(_baseline_path) != report.baseline_sha256 or FileAccess.get_sha256("res://sim/flight_session.gd") != report.candidate_sha256:
		_pair_error = "sources changed during measurement"
	report.complete = _pair_error.is_empty()
	report.error = _pair_error
	var file := FileAccess.open(_pair_output, FileAccess.WRITE)
	if file == null:
		printerr("cannot write report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("DOWNWASH_PAIRS_COMPLETE=", report.complete)
	quit(0 if report.complete else 1)

func _hash_output(output: PackedFloat64Array) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(output.to_byte_array())
	return digest.finish().hex_encode()
