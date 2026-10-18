## L6c: preserve the installed forest collision world in a bounded .orfl fixture.
## Reuses the established detached session probe; this is numerical evidence, not video.
extends "../../research/performance/session_probe.gd"

const FlightLog := preload("res://sim/flight_log.gd")
const LogReader := preload("res://tools/flight_log_cli.gd")


func _run() -> void:
	var log_path := _output + ".orfl"
	if FileAccess.file_exists(log_path):
		printerr("Refusing to overwrite recording: " + log_path)
		quit(2)
		return
	var logger: RefCounted = null
	var completed := 0
	var measurement_boundary_tick := -1
	if _warmup + _samples > FlightLog.MAX_TICKS:
		_fail("requested ticks exceed the bounded flight-log duration")
	elif _prepare():
		logger = FlightLog.new(_session)
		if logger.start(log_path) != OK:
			_fail("cannot start flight log")
		else:
			logger.mark("forest world: " + str(_world.get("identity", "")))
			if _warmup == 0:
				measurement_boundary_tick = _session.sim.tick
				logger.mark("measurement boundary")
			for index in _warmup + _samples:
				if not _advance(false): break
				completed += 1
				if completed == _warmup and measurement_boundary_tick < 0:
					measurement_boundary_tick = _session.sim.tick
					logger.mark("measurement boundary")
			if logger.stop() != OK: _fail("flight log did not close cleanly")
	var checked := LogReader.inspect(log_path)
	if not checked.get("ok", false) or not checked.get("complete", false):
		_fail("recording is incomplete: " + str(checked.get("error", "")))
	elif int(checked.get("rows", 0)) != completed + 1:
		_fail("recorded row count does not match completed ticks")
	elif int(checked.get("footer", {}).get("final_tick", -1)) != int(checked.get("first_tick", 0)) + completed:
		_fail("recorded final tick does not match completed ticks")
	var report := {
		format = "openrc-tree-world-recording v1", complete = _failure.is_empty(),
		failure = _failure, aircraft = _aircraft, case_id = _case,
		requested_ticks = _warmup + _samples, completed_ticks = completed,
		measurement_boundary_tick = measurement_boundary_tick,
		log_rows = int(checked.get("rows", 0)),
		log_first_tick = int(checked.get("first_tick", -1)),
		log_final_tick = int(checked.get("footer", {}).get("final_tick", -1)),
		input_reads = _input_reads, world_identity = _world.get("identity", ""),
		proxy_count = _world.get("proxies", []).size(),
		log_sha256 = FileAccess.get_sha256(log_path) if FileAccess.file_exists(log_path) else "",
		solver_sha256 = FlightLog.solver_identity(),
		scope = "Detached production callbacks with complete installed scenery, field and lake. Exact replay is a separate required CLI check. Cross-world comparisons are not exact equivalence or physical validation.",
	}
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		_fail("cannot write recording report")
	else:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		file.flush()
		if file.get_error() != OK: _fail("recording report write failed")
		file.close()
	if _session != null: _session.free()
	print("tree world recording: %d ticks; %s" % [completed, _failure])
	quit(0 if _failure.is_empty() else 1)
