# DR-05/18: bounded power maneuver recording. Uses the real session and pilot tape.
# Run record on the pinned baseline before changing solver source; each output path must be fresh.
# Output directory is explicit and disposable. Native input, rendering and real hardware are not involved.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const FlightLog := preload("res://sim/multirotor/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var folder := OS.get_environment("OPENRC_FPV_POWER_DIR")
	if folder.is_empty() or DirAccess.make_dir_recursive_absolute(folder) != OK:
		print("FAIL: OPENRC_FPV_POWER_DIR must name a disposable output directory")
		quit(1)
		return
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.ok:
		print("FAIL: field load")
		quit(1)
		return
	var baseline_folder := OS.get_environment("OPENRC_FPV_BASELINE_DIR")
	var reports := []
	for soc: float in [1.0, 0.5, 0.2]:
		reports.append(_record(loaded.field, folder, soc, baseline_folder))
	var file := FileAccess.open(folder.path_join("summary.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify({format = "openrc-fpv-power-maneuvers-v1", cases = reports}, "  ") + "\n")
		file.close()
	print("power maneuvers: 3 cases, %d failed" % failures)
	quit(1 if failures else 0)

func _record(field: Dictionary, folder: String, soc: float, baseline_folder: String) -> Dictionary:
	var tag := "soc-%03d" % roundi(100.0 * soc)
	var path := folder.path_join(tag + ".orfl")
	var csv_path := folder.path_join(tag + ".csv")
	if FileAccess.file_exists(path) or FileAccess.file_exists(csv_path):
		failures += 1
		return {case = tag, ok = false, error = "output already exists"}
	var session := Session.new()
	root.add_child(session)
	if not session.prepare(field, {initial_soc = soc}):
		failures += 1
		var refused := {case = tag, ok = false, error = session.load_error}
		session.free()
		return refused
	var baseline := {}
	var candidate := not baseline_folder.is_empty()
	if candidate:
		baseline = FlightLog.inspect(baseline_folder.path_join(tag + ".orfl"))
		if not _rested_baseline(baseline, session):
			failures += 1
			session.free()
			return {case = tag, ok = false, error = "baseline must be a complete legacy recording from this identical rested initial state"}
		# Exact mode must still refuse the old solver/model; candidate initialization is confined to this probe.
		var legacy_exact := FlightLog.verify(baseline_folder.path_join(tag + ".orfl"))
		if legacy_exact.ok or legacy_exact.exact or not legacy_exact.solver_changed:
			failures += 1
			session.free()
			return {case = tag, ok = false, error = "legacy recording was incorrectly called exact"}
	var recorder := FlightLog.new(session)
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	var ok := csv != null and recorder.start({field_path = FieldLoader.DEFAULT_PATH}, path) == OK and session.resume()
	if csv != null:
		csv.store_line("tick,phase,throttle,roll_input,charge_c,voltage_v,current_a,soc,altitude_m,roll_rate_radps,polarization_v,power_w")
	var phases := [["off", 1, 0.0, 0.0, 0], ["arm", 1, 0.0, 0.0, 1],
		["climb", 240, 0.35, 0.0, 1], ["settle", 240, 0.18, 0.0, 1],
		["punch", 96, 0.8, 0.0, 1], ["chop_roll", 24, 0.0, 0.15, 1],
		["recover", 240, 0.18, 0.0, 1], ["second_punch", 96, 0.65, 0.0, 1],
		["recovery", 480, 0.18, 0.0, 1]]
	var input_row := 0
	var max_position_delta := 0.0
	var max_rate_delta := 0.0
	var final_position_delta := 0.0
	var max_polarization := 0.0
	var minimum_v := INF
	var maximum_current := -INF
	var minimum_current := INF
	var maximum_charge: float = session.sim.continuous[4]
	for phase: Array in phases:
		recorder.mark(str(phase[0]))
		for _i: int in int(phase[1]):
			var pilot := Fixtures.pilot(float(phase[3]), 0.0, 0.0, float(phase[2]), int(phase[4]), FC.FLIGHT_ANGLE)
			if candidate:
				# The preserved tape is the input authority; phase labels only annotate the unchanged maneuver.
				pilot = baseline.pilot.slice(9 * input_row, 9 * (input_row + 1))
			if not ok or not session.tick_once(pilot):
				ok = false
				break
			var frame: Dictionary = session.frame()
			var telemetry: Dictionary = session.plant.telemetry(frame)
			max_polarization = maxf(max_polarization, float(telemetry.get("polarization_voltage_v", 0.0)))
			if candidate:
				var position2 := 0.0
				var rate2 := 0.0
				for axis in 3:
					var dp: float = frame.body[axis] - baseline.states[13 * input_row + axis]
					var dr: float = frame.body[10 + axis] - baseline.states[13 * input_row + 10 + axis]
					position2 += dp * dp
					rate2 += dr * dr
				final_position_delta = sqrt(position2)
				max_position_delta = maxf(max_position_delta, final_position_delta)
				max_rate_delta = maxf(max_rate_delta, sqrt(rate2))
			input_row += 1
			minimum_v = minf(minimum_v, float(telemetry.bus_voltage_v))
			maximum_current = maxf(maximum_current, float(telemetry.pack_current_a))
			minimum_current = minf(minimum_current, float(telemetry.pack_current_a))
			maximum_charge = maxf(maximum_charge, float(frame.continuous[4]))
			csv.store_line("%d,%s,%.9f,%.9f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f" %
				[session.sim.tick, phase[0], phase[2], phase[3], frame.continuous[4], telemetry.bus_voltage_v,
				telemetry.pack_current_a, telemetry.soc, -frame.body[2], frame.body[10],
				telemetry.get("polarization_voltage_v", 0.0), float(telemetry.bus_voltage_v) * float(telemetry.pack_current_a)])
		if not ok:
			break
	var stopped: int = recorder.stop("power maneuver complete")
	if csv != null:
		csv.close()
	var read: Dictionary = FlightLog.inspect(path)
	var replay: Dictionary = FlightLog.verify(path)
	ok = ok and stopped == OK and session.sim.tick == 1418 and session.crash.is_empty() and session.fault_reason.is_empty() \
		and read.ok and read.complete and str(read.get("footer", {}).get("reason", "")) == "power maneuver complete" \
		and replay.ok and replay.complete and replay.exact and not replay.solver_changed and replay.rows == 1418
	var report := {case = tag, ok = ok, ticks = session.sim.tick, data_sha256 = session.source_sha256,
		solver_sha256 = recorder.header.get("solver_sha256", ""), layout = recorder.header.get("layout", {}),
		initial_soc = soc, minimum_voltage_v = minimum_v, minimum_current_a = minimum_current,
		maximum_current_a = maximum_current, maximum_charge_c = maximum_charge, maximum_polarization_v = max_polarization,
		final_charge_c = session.sim.continuous[4], final_altitude_m = -session.sim.state[2],
		fault = session.fault_reason, crash = session.crash, complete = replay.complete, exact = replay.exact,
		solver_changed = replay.solver_changed, replay_error = replay.error,
		footer_reason = str(read.get("footer", {}).get("reason", ""))}
	if candidate:
		var same_tape: bool = read.pilot.to_byte_array() == baseline.pilot.to_byte_array()
		var changed: bool = str(recorder.header.solver_sha256) != str(baseline.header.solver_sha256)
		ok = ok and same_tape and changed and baseline.ticks == read.ticks
		report.ok = ok
		report.candidate_comparison = {mode = "candidate", exact = false, complete = ok, solver_changed = changed,
			initialization = "identical tick-0 rested state; new polarization = 0 V", pilot_tape_identical = same_tape,
			baseline_solver_sha256 = str(baseline.header.solver_sha256),
			max_position_delta_m = max_position_delta, final_position_delta_m = final_position_delta,
			max_rate_delta_radps = max_rate_delta}
	print("CASE ", JSON.stringify(report))
	if not ok:
		failures += 1
	session.free()
	return report

# Candidate-only initialization: legacy mid-flight polarization is unknown and must never be invented.
# No production restore rule is weakened. A fresh current session must match every recorded old state byte.
func _rested_baseline(read: Dictionary, session: Node) -> bool:
	if not read.get("ok", false) or not read.get("complete", false) or read.ticks.size() != 1418 \
			or read.header.layout != {pilot = 9, state = 13, continuous = 8, aux = 31, modes = 8} \
			or str(read.footer.get("reason", "")) != "power maneuver complete":
		return false
	var envelope: Dictionary = read.header.checkpoint
	var old: Dictionary = envelope.kernel
	var fresh: Dictionary = session.checkpoint().kernel
	if old.tick != 0 or envelope.tape_ticks != 0 or old.state_layout_identity != "openrc-multirotor-controlled-el-v1" \
			or fresh.state_layout_identity != "openrc-multirotor-controlled-el-v2" \
			or old.modes[FC.MODE_MOTOR] != FC.MOTOR_DISARMED or not envelope.crash.is_empty() \
			or fresh.continuous.size() != 9 or fresh.continuous[8] != 0.0:
		return false
	for i in [0, 1, 2, 3, 5, 6, 7]:
		if old.continuous[i] != 0.0:
			return false
	if old.continuous[4] <= 0.0 or old.continuous.to_byte_array() != fresh.continuous.slice(0, 8).to_byte_array():
		return false
	for key: String in ["state", "previous", "aux", "modes", "inputs", "inertia"]:
		if var_to_bytes(old[key]) != var_to_bytes(fresh[key]):
			return false
	return old.dt == fresh.dt and old.mass == fresh.mass and old.gravity == fresh.gravity
