# DR-17 REPLAY-01…06: multirotor flight log. A complete flight on the default field with the shipped document (arm,
# climb, Acro roll, Angle segment, crash and aftermath) replays exactly from the recorded pilot tape; a recording
# started mid-flight replays exactly from its envelope; truncation, a flipped byte, an unknown format and a changed
# data or rates identity are refused as exact claims; a candidate controller reruns feedback from the same pilot tape
# and reports trajectory deltas; the recorder's bounded lifecycle is safe. Same build and platform only.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const MultirotorLog := preload("res://sim/multirotor/flight_log.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")
const OrflContainer := preload("res://sim/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")

const DIR := "user://test_mr_flight_log"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _hover_throttle(s: Node) -> float:
	var map: Dictionary = s.plant.config.actuator
	var command: float = ActuatorMap.command_for_thrust(map, float(s.data.mass_kg) * 9.80665 / 4.0, s.plant.supply_voltage(s.sim.continuous))
	return (command - float(map.idle)) / (float(map.top) - float(map.idle))


func _fly(s: Node, pilot: PackedFloat64Array, ticks: int) -> bool:
	for _i in ticks:
		if not s.tick_once(pilot):
			return false
	return true


func _arm(s: Node) -> bool:
	return _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 1) and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 1)


func _report(report: Dictionary) -> String:
	return "%s exact=%s complete=%s identity=%s solver_changed=%s rows=%d mismatch=%d %s" % [report.mode, report.exact,
		report.complete, report.identity_match, report.solver_changed, report.rows, report.first_mismatch_tick, str(report.error).left(140)]


func _run() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var s: Node = Session.new()
	root.add_child(s)
	_check("the shipped document prepares on the default field", s.prepare(field, {}), s.load_error)
	var context := {field_path = FieldLoader.DEFAULT_PATH}
	# REPLAY-01: a complete baseline flight recorded from the prepared start.
	var flight_path := DIR + "/flight.orfl"
	var recorder := MultirotorLog.new(s)
	_check("recording starts on the prepared, paused flight", recorder.start(context, flight_path) == OK and recorder.recording
		and recorder.header.layout == {pilot = 9, state = 13, continuous = 8, aux = 31, modes = 8})
	_check("a second start while recording is refused", recorder.start(context, DIR + "/other.orfl") == ERR_ALREADY_IN_USE)
	s.resume()
	var ok: bool = _arm(s) and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
	ok = ok and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.35, 1), 120)
	var hover := _hover_throttle(s)
	ok = ok and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, hover, 1), 120)
	recorder.mark("roll")
	ok = ok and _fly(s, Fixtures.pilot(1.0, 0.0, 0.0, hover + 0.1, 1), 130)
	ok = ok and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, hover, 1), 120)
	s.pause("pilot pause")
	s.resume()
	ok = ok and _fly(s, Fixtures.pilot(0.2, -0.3, 0.1, hover + 0.05, 1, 1), 120)
	ok = ok and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, hover, 1, 1), 60)
	var crashed := false
	for _i in 2400:
		ok = ok and s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0))
		if not s.crash.is_empty():
			crashed = true
			break
	_check("the scripted flight (arm, climb, Acro roll, Angle segment, disarmed fall) ends in a crash", ok and crashed, str(s.crash))
	# Aftermath while the kernel accepts it. A hard impact of the shipped document can fault within a few ticks
	# (the plant's state validator refuses the impact-driven shaft speeds); the recorder then closes on the fault.
	var aftermath := 0
	while aftermath < 60 and s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0)):
		aftermath += 1
	print("aftermath: %d accepted ticks after the crash; fault: %s" % [aftermath, s.fault_reason])
	var final_frame := var_to_bytes(s.frame())
	var final_tick: int = s.sim.tick
	_check("seconds() reports the recorded span", absf(recorder.seconds() - float(final_tick) / 240.0) < 1e-9)
	_check("stop closes a complete file", recorder.stop("test end") == OK and not recorder.recording and recorder.rows_written == final_tick,
		"%d rows" % recorder.rows_written)
	_check("a second stop is a safe no-op", recorder.stop("again") == OK and not recorder.recording)
	var read := MultirotorLog.inspect(flight_path)
	_check("inspect: complete file, chained blocks, every accepted tick", read.ok and read.complete and read.ticks.size() == final_tick
		and read.pilot.size() == 9 * final_tick and read.aux.size() == 31 * final_tick and read.modes.size() == 8 * final_tick,
		str(read.get("error", "")))
	var kinds: Array = []
	var kernel_crash := false
	for event: Dictionary in read.get("events", []):
		kinds.append(event.kind)
		if event.kind == "kernel" and event.event.type == "crash":
			kernel_crash = true
	_check("pause, resume, marker, crash, kernel crash event and stop are kept", kinds.has("pause") and kinds.has("resume")
		and kinds.has("marker") and kinds.has("crash") and kinds.has("stop") and kernel_crash)
	var last: int = read.ticks.size() - 1
	_check("the last row is the live final frame", var_to_bytes({body = read.states.slice(13 * last), continuous = read.continuous.slice(8 * last),
		aux = read.aux.slice(31 * last), modes = read.modes.slice(8 * last)}) == final_frame)
	var report := MultirotorLog.verify(flight_path)
	_check("REPLAY-01 the complete flight replays exactly from its pilot tape", report.ok and report.exact and report.complete
		and report.identity_match and not report.solver_changed and report.mode == "exact" and report.rows == final_tick
		and report.recorded_crash == str(s.crash.get("reason", "")) and report.replayed_crash == report.recorded_crash, _report(report))
	_check("fixed-wing-family tools refuse the multirotor format", not AirshipLog.inspect(flight_path).ok)
	_check("refuses to start on a crashed flight", MultirotorLog.new(s).start(context, DIR + "/crashed.orfl") == ERR_UNAVAILABLE)

	# REPLAY-02: a recording started mid-flight; a pad reset closes it complete.
	s.reset_to_pad()
	_check("refuses to overwrite an existing log", MultirotorLog.new(s).start(context, flight_path) == ERR_ALREADY_EXISTS)
	s.resume()
	_arm(s)
	_fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.35, 1), 120)
	hover = _hover_throttle(s)
	_fly(s, Fixtures.pilot(0.0, 0.0, 0.0, hover, 1), 240)
	_fly(s, Fixtures.pilot(0.5, 0.0, 0.0, hover, 1), 40)
	var mid_path := DIR + "/mid.orfl"
	var mid := MultirotorLog.new(s)
	var start_tick: int = s.sim.tick
	_check("a recording starts mid-flight, during a roll", mid.start(context, mid_path) == OK and start_tick == 402
		and absf(s.sim.state[10]) > 1.0, "tick %d roll rate %.3f" % [start_tick, s.sim.state[10]])
	for i in 480:
		var t := float(i) / 240.0
		s.tick_once(Fixtures.pilot(0.5 * sin(3.0 * t), 0.3 * sin(2.0 * t), 0.2 * cos(t), clampf(hover + 0.1 * sin(t), 0.0, 1.0), 1, 1 if i > 240 else 0))
	s.reset_to_pad()
	var mid_read := MultirotorLog.inspect(mid_path)
	_check("a pad reset closes the mid-flight log complete", not mid.recording and mid_read.ok and mid_read.complete
		and mid_read.ticks.size() == 480 and int(mid_read.ticks[0]) == start_tick + 1, str(mid_read.get("error", "")))
	var mid_report := MultirotorLog.verify(mid_path)
	_check("REPLAY-02 the mid-flight recording replays exactly from its envelope (controller, pack and clock included)",
		mid_report.ok and mid_report.exact and mid_report.rows == 480 and mid_report.recorded_crash.is_empty(), _report(mid_report))

	# REPLAY-03: truncation, a flipped byte and an unknown format.
	var bytes := FileAccess.get_file_as_bytes(flight_path)
	_write(DIR + "/truncated.orfl", bytes.slice(0, bytes.size() - 100))
	var truncated := MultirotorLog.verify(DIR + "/truncated.orfl")
	var prefix := MultirotorLog.inspect(DIR + "/truncated.orfl")
	_check("REPLAY-03 a truncated file is incomplete, never exact, and its prefix is recoverable", not truncated.complete
		and not truncated.exact and not truncated.ok and prefix.ok and not prefix.complete and prefix.ticks.size() > 0
		and not str(prefix.get("error", "")).is_empty(), "%d prefix rows; %s" % [prefix.ticks.size(), truncated.error])
	var corrupt := bytes.duplicate()
	corrupt[bytes.size() / 2] = corrupt[bytes.size() / 2] ^ 0xFF
	_write(DIR + "/corrupt.orfl", corrupt)
	var flipped := MultirotorLog.verify(DIR + "/corrupt.orfl")
	_check("REPLAY-03 a flipped byte in a block is a refusal with a specific error", not flipped.ok and not flipped.exact
		and not str(flipped.error).is_empty(), str(flipped.error))
	var head: Dictionary = read.header.duplicate(true)
	head.format = "openrc-multirotor-flight-log v0"
	_rewrite(read, head, DIR + "/format.orfl")
	var unknown := MultirotorLog.verify(DIR + "/format.orfl")
	_check("an unknown format is refused", not unknown.ok and not unknown.exact and str(unknown.error).contains("format"), str(unknown.error))

	# REPLAY-04: a valid file whose header identity differs from the current configuration.
	head = read.header.duplicate(true)
	_rewrite(read, head, DIR + "/rewritten.orfl")
	var control := MultirotorLog.verify(DIR + "/rewritten.orfl")
	_check("control: a faithfully rewritten container still replays exactly", control.exact, _report(control))
	head = read.header.duplicate(true)
	head.session.data_sha256 = "0".repeat(64)
	_rewrite(read, head, DIR + "/data.orfl")
	var data_mismatch := MultirotorLog.verify(DIR + "/data.orfl")
	_check("REPLAY-04 a header whose data identity differs is not exact", data_mismatch.complete and not data_mismatch.identity_match
		and not data_mismatch.exact and not data_mismatch.ok, _report(data_mismatch))
	head = read.header.duplicate(true)
	var other_rates: Dictionary = Rates.default_profile()
	other_rates.axes.roll.rc_rate = 25
	head.options.rates = other_rates
	_rewrite(read, head, DIR + "/rates.orfl")
	var rates_mismatch := MultirotorLog.verify(DIR + "/rates.orfl")
	_check("REPLAY-04 a header whose rates differ is not exact", rates_mismatch.complete and not rates_mismatch.identity_match
		and not rates_mismatch.exact and not rates_mismatch.ok, _report(rates_mismatch))

	# REPLAY-05: candidate controller from the same pilot tape.
	var stiffer: Dictionary = s.data.duplicate(true)
	var kp: PackedFloat64Array = stiffer.controller.kp.duplicate()
	for i in kp.size():
		kp[i] *= 1.5
	stiffer.controller.kp = kp
	var candidate := MultirotorLog.verify(flight_path, {prepared_data = stiffer})
	_check("REPLAY-05 a candidate controller reruns feedback from the pilot tape and reports nonzero deltas", candidate.ok
		and candidate.mode == "candidate" and not candidate.identity_match and not candidate.exact and candidate.rows == final_tick
		and float(candidate.max_position_delta_m) > 0.0 and float(candidate.max_rate_delta_radps) > 0.0
		and is_finite(float(candidate.final_position_delta_m)),
		"max position %.4f m max rate %.4f rad/s final %.4f m %s" % [candidate.get("max_position_delta_m", NAN),
			candidate.get("max_rate_delta_radps", NAN), candidate.get("final_position_delta_m", NAN), candidate.error])
	var rates_candidate := MultirotorLog.verify(mid_path, {rates = other_rates})
	_check("REPLAY-05 a candidate rates profile is a candidate run, never exact", rates_candidate.ok and not rates_candidate.exact
		and rates_candidate.mode == "candidate" and float(rates_candidate.max_rate_delta_radps) > 0.0, _report(rates_candidate))

	# REPLAY-06: bounded recorder lifecycle.
	var faulted_path := DIR + "/faulted.orfl"
	var guard := MultirotorLog.new(s)
	s.resume()
	_check("a recorder starts on a fresh pad flight", guard.start(context, faulted_path) == OK)
	_arm(s)
	_fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.3, 1), 30)
	s.sim.mass = NAN
	s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.3, 1))
	var faulted_read := MultirotorLog.inspect(faulted_path)
	_check("REPLAY-06 a kernel fault closes the recording complete with only accepted ticks", not guard.recording
		and faulted_read.complete and faulted_read.ticks.size() == 32 and str(faulted_read.footer.reason).begins_with("simulation fault"),
		str(faulted_read.get("footer", {})))
	_check("REPLAY-06 the closed fault log still replays exactly", MultirotorLog.verify(faulted_path).exact)
	_check("starting on a faulted flight is refused", MultirotorLog.new(s).start(context, DIR + "/x.orfl") == ERR_UNAVAILABLE)
	_check("stop on a recorder that never started is a no-op", MultirotorLog.new(s).stop() == OK)
	s.queue_free()
	_clean()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Re-encode an inspected log with a chosen header: valid packets, digests, chain and footer.
func _rewrite(read: Dictionary, head: Dictionary, file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_buffer(OrflContainer.MAGIC.to_ascii_buffer())
	var chain := _packet(file, head, PackedByteArray())
	chain = _packet(file, {kind = "block", ticks = read.ticks, pilot = read.pilot, states = read.states, continuous = read.continuous,
		aux = read.aux, modes = read.modes, events = read.events}, chain)
	_packet(file, {kind = "footer", rows = read.ticks.size(), first_tick = int(read.footer.first_tick), final_tick = int(read.footer.final_tick),
		reason = "rewritten", chain_sha256 = chain.hex_encode()}, chain)
	file.close()


func _packet(file: FileAccess, value: Dictionary, chain: PackedByteArray) -> PackedByteArray:
	var payload := var_to_bytes(value)
	var digest := OrflContainer.sha256(payload)
	file.store_32(payload.size())
	file.store_buffer(digest)
	file.store_buffer(payload)
	return OrflContainer.sha256(chain + digest)


func _write(file_path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _clean() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(dir):
		for name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(name))
		DirAccess.remove_absolute(dir)
