extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")
const WindConfig := preload("res://physics/wind_config.gd")

const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const STIK_ID := "jensen-das-ugly-stik-60"
const TICKS_PER_SECOND := 240
const COMMAND_DIVISOR := 4
const FLIGHT_TICKS := 120 * TICKS_PER_SECOND
const SPOT_CHECK_TICKS := 3 * TICKS_PER_SECOND
const SEED := 20261020
const MIN_CLEARANCE_M := 20.0
const MAX_TAS_MPS := 25.0
const MIN_TAS_MPS := 10.0
const MAX_RADIUS_ERROR_M := 40.0
const PLAYER_SEPARATION_M := 30.0
const PAIR_SEPARATION_M := 15.0

var _checks: int = 0
var _failures: int = 0
var _sample_rows := PackedStringArray()
var _flight_ticks: int = FLIGHT_TICKS
var _spot_check: bool = false
var _output_dir := ""
var _pilot_path := "res://ai/companions/pilot.gd"
var _pilot_script: Script


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _initialize() -> void:
	_spot_check = OS.get_cmdline_user_args().has("--spot-check")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_dir = argument.trim_prefix("--out=")
		elif argument.begins_with("--pilot="):
			_pilot_path = argument.trim_prefix("--pilot=")
	if _spot_check:
		_flight_ticks = SPOT_CHECK_TICKS
	call_deferred("_run")


func _run() -> void:
	if not _pilot_path.begins_with("res://") or not FileAccess.file_exists(_pilot_path):
		printerr("Supply an existing --pilot=res://... script.")
		quit(2)
		return
	_pilot_script = load(_pilot_path) as Script
	if _pilot_script == null or not _pilot_script.can_instantiate():
		printerr("Selected pilot script cannot be instantiated.")
		quit(2)
		return
	print("PILOT SOURCE %s SHA256 %s" % [_pilot_path, FileAccess.get_sha256(_pilot_path)])
	if not _spot_check:
		if _output_dir.is_empty():
			printerr("Supply --out=<new directory>; qualification never overwrites accepted evidence.")
			quit(2)
			return
		_output_dir = ProjectSettings.globalize_path(_output_dir)
		if DirAccess.dir_exists_absolute(_output_dir) or FileAccess.file_exists(_output_dir):
			printerr("Qualification output must be a new directory.")
			quit(2)
			return
	var loaded: Dictionary = FieldLoader.load_from()
	_check("Club field loads from accepted data", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		quit(1)
		return
	var field: Dictionary = loaded.field
	if _spot_check:
		var spot_result: Dictionary = _run_fleet(field, 1, "calm", false, false)
		print("companion pilot heading spot-check: %d checks, %d failed; ticks=%d" % [
			_checks, _failures, int(spot_result.get("ticks", 0))])
		quit(1 if _failures > 0 else 0)
		return
	var calm_results: Array = []
	var gentle_results: Array = []
	for count in range(1, 4):
		calm_results.append(_run_fleet(field, count, "calm", false, true))
	for count in range(1, 4):
		gentle_results.append(_run_fleet(field, count, "gentle-practice", false, true))
	var deterministic_first: Dictionary = _run_fleet(field, 3, "calm", true, false)
	var deterministic_second: Dictionary = _run_fleet(field, 3, "calm", true, false)
	var first_trace: PackedFloat64Array = deterministic_first.get("trace", PackedFloat64Array())
	var second_trace: PackedFloat64Array = deterministic_second.get("trace", PackedFloat64Array())
	var replay_identical: bool = first_trace.to_byte_array() == second_trace.to_byte_array()
	var replay_complete: bool = int(deterministic_first.get("ticks", -1)) == _flight_ticks \
		and int(deterministic_second.get("ticks", -1)) == _flight_ticks
	_check("seeded three-aircraft calm replay has bit-identical sampled state and command trace",
		replay_identical)
	_check("both seeded replay flights complete 120 simulated seconds",
		replay_complete)
	var output_result: Dictionary = _write_qualification_outputs(calm_results + gentle_results, replay_identical, replay_complete)
	_check("qualification CSV outputs are written", output_result.get("ok", false), str(output_result.get("reason", "")))
	print("companion pilot qualification: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_fleet(field: Dictionary, count: int, weather_id: String, record_trace: bool, record_rows: bool) -> Dictionary:
	var weather: Dictionary = WindConfig.preset(weather_id)
	var sessions: Array = []
	var pilots: Array = []
	var packets: Array = []
	var trace := PackedFloat64Array()
	var min_clearance: float = INF
	var max_clearance: float = -INF
	var min_tas: float = INF
	var max_tas: float = -INF
	var max_radius_error: float = 0.0
	var min_player_separation: float = INF
	var max_control: float = 0.0
	var max_bank: float = 0.0
	var min_pair_separation: float = INF
	var refusals: int = 0
	var stop_reason: String = ""
	for slot in count:
		var session: Node = FlightSession.new()
		session.start_choice = FlightSession.START_AIRBORNE
		session.input_enabled = false
		session.rate_profile = "full"
		var weather_ok: bool = session.setup_weather(weather)
		_check("%s %d-slot weather preset loads" % [weather_id, slot], weather_ok, str(session.weather_error))
		session.setup(STIK_PATH, STIK_ID)
		var field_ok: bool = session.set_field(field)
		_check("%s %d-slot Club field installs" % [weather_id, slot], field_ok, str(session.surface_error))
		session.reset()
		var trim: Dictionary = session.start.duplicate(true)
		var pilot: Variant = _pilot_script.new()
		var configured: bool = pilot.configure(slot, count, SEED, trim, field)
		_check("%s %d-slot pilot accepts current Stik trim" % [weather_id, slot], configured, str(pilot.configure_error))
		if not configured:
			session.free()
			for old: Node in sessions:
				old.free()
			return {"weather": weather_id, "count": count, "ticks": 0, "stop_reason": "pilot configure failed"}
		var pose: Dictionary = pilot.initial_pose()
		var external_ready: bool = session.configure_external_driver()
		var spawn_ok: bool = external_ready and session.external_spawn_airborne(
			float(pose.get("north", NAN)), float(pose.get("east", NAN)),
			float(pose.get("height_agl_m", NAN)), float(pose.get("heading_rad", NAN)))
		_check("%s %d-slot spawn uses reset-boundary AGL pose" % [weather_id, slot],
			spawn_ok and float(pose.get("height_agl_m", 0.0)) >= 35.0)
		if not spawn_ok:
			session.free()
			for old: Node in sessions:
				old.free()
			return {"weather": weather_id, "count": count, "ticks": 0, "stop_reason": "external setup/spawn failed"}
		var spawn_state: PackedFloat64Array = session.sim.state
		var actual_heading: float = Math3D.q_to_euler(Math3D.quat(
			spawn_state[RigidBody.ATT], spawn_state[RigidBody.ATT + 1],
			spawn_state[RigidBody.ATT + 2], spawn_state[RigidBody.ATT + 3]))[0]
		var heading_error: float = absf(wrapf(actual_heading - float(pose.heading_rad), -PI, PI))
		_check("%s %d-slot spawn matches the pilot's absolute heading" % [weather_id, slot],
			heading_error <= 1e-9, "requested=%.9f actual=%.9f error=%.9f rad" % [
			float(pose.heading_rad), actual_heading, heading_error])
		root.add_child(session)
		sessions.append(session)
		pilots.append(pilot)
		packets.append({})
	var player_state: PackedFloat64Array = _player_state(field)
	var player_traffic: Array = [{"id": "player", "is_player": true, "wingspan_m": 1.7, "state": player_state}]
	if record_rows and _sample_rows.is_empty():
		_sample_rows.append("weather,count,seed,slot,time_s,north_m,east_m,height_agl_m,tas_m_s,clearance_m,radius_error_m,roll,pitch,yaw,throttle")
	for tick in _flight_ticks:
		for slot in count:
			var session: Node = sessions[slot]
			var pilot: Variant = pilots[slot]
			if tick % COMMAND_DIVISOR == 0:
				var snapshot: Dictionary = _snapshot(session, weather)
				var traffic: Array = player_traffic.duplicate()
				for other_slot in count:
					if other_slot == slot:
						continue
					var other_session: Node = sessions[other_slot]
					traffic.append({"id": "companion-%d" % other_slot, "slot": other_slot, "is_player": false,
						"wingspan_m": 1.7, "state": other_session.sim.state.duplicate()})
				var packet: Dictionary = pilot.command(snapshot, tick, traffic)
				if not packet.get("ok", false):
					refusals += 1
					stop_reason = "pilot refusal at tick %d: %s" % [tick, str(packet.get("reason", "unknown"))]
					break
				var controls := {"roll": float(packet.roll), "pitch": float(packet.pitch),
					"yaw": float(packet.yaw), "throttle": float(packet.throttle)}
				packets[slot] = packet
				var control_peak: float = maxf(maxf(absf(float(packet.roll)), absf(float(packet.pitch))),
					maxf(absf(float(packet.yaw)), absf(float(packet.throttle))))
				max_control = maxf(max_control, control_peak)
				if record_trace:
					for control_name: String in ["roll", "pitch", "yaw", "throttle"]:
						trace.append(float(packet.get(control_name, NAN)))
					trace.append(float(session.sim.state[RigidBody.POS]))
					trace.append(float(session.sim.state[RigidBody.POS + 1]))
					trace.append(float(session.sim.state[RigidBody.POS + 2]))
			if not stop_reason.is_empty():
				break
			var held_packet: Dictionary = packets[slot]
			var controls := {"roll": float(held_packet.get("roll", NAN)), "pitch": float(held_packet.get("pitch", NAN)),
				"yaw": float(held_packet.get("yaw", NAN)), "throttle": float(held_packet.get("throttle", NAN))}
			var staged: Dictionary = session.prepare_external_tick(controls)
			if not staged.get("ok", false):
				stop_reason = "external input rejected at tick %d: %s" % [tick, str(staged.get("errors", []))]
				break
		if not stop_reason.is_empty():
			break
		for slot in count:
			var session: Node = sessions[slot]
			if not session.step_external_tick():
				stop_reason = "session rejected tick %d for slot %d" % [tick, slot]
				break
		if not stop_reason.is_empty():
			break
		for slot in count:
			var session: Node = sessions[slot]
			var state: PackedFloat64Array = session.sim.state
			var altitude: float = -state[RigidBody.POS + 2]
			var terrain: PackedFloat64Array = session.environment.terrain(state[RigidBody.POS], state[RigidBody.POS + 1])
			var clearance: float = altitude - terrain[0]
			var current_tas: float = float(session.air_data(state, session.sim.time()).get("V", NAN))
			min_clearance = minf(min_clearance, clearance)
			max_clearance = maxf(max_clearance, clearance)
			min_tas = minf(min_tas, current_tas)
			max_tas = maxf(max_tas, current_tas)
			var pilot: Variant = pilots[slot]
			max_radius_error = maxf(max_radius_error, absf(_radius_error_for_state(state, pilot)))
			max_bank = maxf(max_bank, absf(Math3D.q_to_euler(Math3D.quat(state[6], state[7], state[8], state[9]))[2]))
			min_player_separation = minf(min_player_separation, _distance3(state, player_state))
			if not session.crash.is_empty():
				stop_reason = "crash at tick %d: %s" % [tick + 1, str(session.crash.get("why", "contact"))]
			elif not session.sim.fault_reason.is_empty():
				stop_reason = "simulation fault at tick %d: %s" % [tick + 1, session.sim.fault_reason]
			elif not SimStateFinite(state) or not is_finite(current_tas) or not is_finite(clearance):
				stop_reason = "nonfinite flight metric at tick %d" % [tick + 1]
		if count > 1:
			for first_slot in count:
				for second_slot in range(first_slot + 1, count):
					min_pair_separation = minf(min_pair_separation,
						_distance3(sessions[first_slot].sim.state, sessions[second_slot].sim.state))
		if record_trace and (tick + 1) % TICKS_PER_SECOND == 0:
			for slot in count:
				var session: Node = sessions[slot]
				var state: PackedFloat64Array = session.sim.state
				var controls: Dictionary = packets[slot]
				for value: float in state:
					trace.append(value)
				for control_name: String in ["roll", "pitch", "yaw", "throttle"]:
					trace.append(float(controls.get(control_name, NAN)))
		if record_rows and (tick + 1) % TICKS_PER_SECOND == 0:
			for slot in count:
				var session: Node = sessions[slot]
				var state: PackedFloat64Array = session.sim.state
				var terrain: PackedFloat64Array = session.environment.terrain(state[RigidBody.POS], state[RigidBody.POS + 1])
				var controls: Dictionary = packets[slot]
				var clearance: float = -state[RigidBody.POS + 2] - terrain[0]
				var tas: float = float(session.air_data(state, session.sim.time()).get("V", NAN))
				var radius_error: float = _radius_error_for_state(state, pilots[slot])
				_sample_rows.append("%s,%d,%d,%d,%.3f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.8f,%.8f,%.8f,%.8f" % [
					weather_id, count, SEED, slot, float(tick + 1) / TICKS_PER_SECOND,
					state[RigidBody.POS], state[RigidBody.POS + 1], -state[RigidBody.POS + 2], tas, clearance,
					radius_error, float(controls.get("roll", NAN)), float(controls.get("pitch", NAN)),
					float(controls.get("yaw", NAN)), float(controls.get("throttle", NAN))])
		if not stop_reason.is_empty():
			break
	var completed_ticks: int = int(sessions[0].sim.tick) if not sessions.is_empty() else 0
	var completed: bool = stop_reason.is_empty() and completed_ticks >= _flight_ticks
	var highest_target: float = 35.0 + float(count - 1) * 20.0
	var max_clearance_limit: float = highest_target + 20.0
	var detail: String = "ticks=%d/%d AGL=%.2f..%.2fm TAS=%.2f..%.2fm/s max_radius_error=%.2fm min_player=%.2fm min_pair=%.2fm max_bank=%.1fdeg max_input=%.4f refusals=%d%s" % [
		completed_ticks, _flight_ticks, min_clearance, max_clearance, min_tas, max_tas, max_radius_error,
		min_player_separation, min_pair_separation, rad_to_deg(max_bank), max_control, refusals,
		" stop=" + stop_reason if not stop_reason.is_empty() else ""]
	var label: String = "%s %d-Stik flight for %d simulated seconds" % [
		weather_id, count, _flight_ticks / TICKS_PER_SECOND]
	_check(label + " completes without refusal, crash or simulation fault", completed and refusals == 0, detail)
	_check(label + " stays within the clearance envelope", min_clearance >= MIN_CLEARANCE_M and max_clearance <= max_clearance_limit, detail)
	_check(label + " stays within the 10..25 m/s TAS envelope", min_tas >= MIN_TAS_MPS and max_tas <= MAX_TAS_MPS, detail)
	_check(label + " stays within the assigned circuit band", max_radius_error <= MAX_RADIUS_ERROR_M, detail)
	_check(label + " keeps the player at least 30 m clear", min_player_separation >= PLAYER_SEPARATION_M, detail)
	_check(label + " keeps normalized inputs within travel", max_control <= 1.0, detail)
	if count > 1:
		_check(label + " keeps all aircraft centers at least 15 m apart", min_pair_separation >= PAIR_SEPARATION_M, detail)
	for session_value: Variant in sessions:
		var session: Node = session_value
		session.queue_free()
	return {
		"weather": weather_id, "count": count, "seed": SEED, "ticks": completed_ticks, "complete": completed,
		"min_clearance": min_clearance, "max_clearance": max_clearance, "min_tas": min_tas,
		"max_tas": max_tas, "max_radius_error": max_radius_error,
		"min_player_separation": min_player_separation, "min_pair_separation": min_pair_separation,
		"max_bank_deg": rad_to_deg(max_bank), "max_control": max_control, "refusals": refusals,
		"stop_reason": stop_reason, "trace": trace,
	}


func _snapshot(session: Node, weather: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var now: float = session.sim.time()
	var turbulence: Variant = weather.get("turbulence_rms_mps", PackedFloat64Array([0.0, 0.0, 0.0]))
	if turbulence is Array:
		turbulence = PackedFloat64Array(turbulence)
	var terrain: PackedFloat64Array = session.environment.terrain(state[RigidBody.POS], state[RigidBody.POS + 1])
	return {
		"state": state,
		"airspeed_m_s": float(session.air_data(state, now).get("V", NAN)),
		"wind_ned": session.wind_at(now),
		"ground_clearance_m": -state[RigidBody.POS + 2] - terrain[0],
		"trim": session.start.duplicate(true),
		"turbulence_rms_m_s": turbulence,
	}


func _player_state(field: Dictionary) -> PackedFloat64Array:
	var pilot: Dictionary = field.pilot
	return RigidBody.make_state(
		PackedFloat64Array([float(pilot.north), float(pilot.east), float(pilot.down)]),
		PackedFloat64Array([0.0, 0.0, 0.0]), Math3D.q_identity(), PackedFloat64Array([0.0, 0.0, 0.0]))


func _radius_error_for_state(state: PackedFloat64Array, pilot: Variant) -> float:
	var center_north: float = float(pilot.get("_center_north_m"))
	var center_east: float = float(pilot.get("_center_east_m"))
	var radius: float = float(pilot.get("_radius_m"))
	var dn: float = state[RigidBody.POS] - center_north
	var de: float = state[RigidBody.POS + 1] - center_east
	return sqrt(dn * dn + de * de) - radius


func _distance3(first: PackedFloat64Array, second: PackedFloat64Array) -> float:
	var north: float = first[RigidBody.POS] - second[RigidBody.POS]
	var east: float = first[RigidBody.POS + 1] - second[RigidBody.POS + 1]
	var down: float = first[RigidBody.POS + 2] - second[RigidBody.POS + 2]
	return sqrt(north * north + east * east + down * down)


func _write_qualification_outputs(results: Array, replay_identical: bool, replay_complete: bool) -> Dictionary:
	var output_dir: String = _output_dir
	if DirAccess.dir_exists_absolute(output_dir) or FileAccess.file_exists(output_dir):
		return {"ok": false, "reason": "output appeared during the run; existing evidence is preserved"}
	var dir_error: int = DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK and not DirAccess.dir_exists_absolute(output_dir):
		return {"ok": false, "reason": "could not create output directory (error %d)" % dir_error}
	var metrics_path: String = output_dir.path_join("scenario_metrics.csv")
	var metrics_file: FileAccess = FileAccess.open(metrics_path, FileAccess.WRITE)
	if metrics_file == null:
		return {"ok": false, "reason": "could not open scenario_metrics.csv (error %d)" % FileAccess.get_open_error()}
	metrics_file.store_line("weather,count,seed,ticks,complete,min_agl_m,max_agl_m,min_tas_m_s,max_tas_m_s,max_radius_error_m,min_player_separation_m,min_pair_separation_m,max_bank_deg,max_abs_input,refusals,stop_reason")
	for item_value: Variant in results:
		var item: Dictionary = item_value
		metrics_file.store_line("%s,%d,%d,%d,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.8f,%d,\"%s\"" % [
			item.weather, item.count, item.seed, item.ticks, str(item.complete), item.min_clearance, item.max_clearance,
			item.min_tas, item.max_tas, item.max_radius_error, item.min_player_separation, item.min_pair_separation,
			item.max_bank_deg, item.max_control, item.refusals, str(item.stop_reason).replace("\"", "\"\"")])
	metrics_file.close()
	var samples_path: String = output_dir.path_join("flight_samples_1hz.csv")
	var samples_file: FileAccess = FileAccess.open(samples_path, FileAccess.WRITE)
	if samples_file == null:
		return {"ok": false, "reason": "could not open flight_samples_1hz.csv (error %d)" % FileAccess.get_open_error()}
	for row: String in _sample_rows:
		samples_file.store_line(row)
	samples_file.close()
	var summary_path: String = output_dir.path_join("README.md")
	var summary_file: FileAccess = FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file == null:
		return {"ok": false, "reason": "could not open README.md (error %d)" % FileAccess.get_open_error()}
	var failed_results: int = 0
	var radial_failures: int = 0
	for item_value: Variant in results:
		var item: Dictionary = item_value
		if float(item.max_radius_error) > MAX_RADIUS_ERROR_M:
			radial_failures += 1
		if not _item_passes(item):
			failed_results += 1
	summary_file.store_line("# Ugly Stik Companion Pilot Qualification")
	summary_file.store_line("")
	var matrix_qualified: bool = failed_results == 0 and replay_identical and replay_complete
	summary_file.store_line("**%s** Maximum absolute radial error: %.2f m against the %.2f m gate; %d of %d matrix scenarios failed at least one gate (%d exceeded the radius gate)." % [
		"Qualified for the tested matrix gates." if matrix_qualified else "Not qualified for the tested matrix gates.",
		_max_result(results, "max_radius_error"), MAX_RADIUS_ERROR_M, failed_results, results.size(), radial_failures])
	summary_file.store_line("")
	summary_file.store_line("Seeded FlightSession matrix, generated by `research/ai-companions/pilot_probe.gd` with the checked Godot 4.7.2 runner. Each aircraft completed 120 simulated seconds unless its row says otherwise. The controller was sampled at 60 Hz and each accepted command held for four 240 Hz physics ticks.")
	summary_file.store_line("")
	summary_file.store_line("| Weather | Slots | Ticks | AGL min–max (m) | TAS min–max (m/s) | Max route error (m) | Min player distance (m) | Min fleet distance (m) | Bank max (°) | Outcome |")
	summary_file.store_line("|---|---:|---:|---:|---:|---:|---:|---:|---:|---|")
	for item_value: Variant in results:
		var item: Dictionary = item_value
		var outcome: String = "pass" if _item_passes(item) else "fail: one or more gates"
		summary_file.store_line("| %s | %d | %d | %.2f–%.2f | %.2f–%.2f | %.2f | %.2f | %s | %.1f | %s |" % [
			item.weather, item.count, item.ticks, item.min_clearance, item.max_clearance, item.min_tas, item.max_tas,
			item.max_radius_error, item.min_player_separation,
			("n/a" if item.count == 1 else "%.2f" % item.min_pair_separation), item.max_bank_deg, outcome])
	summary_file.store_line("")
	summary_file.store_line("Seeded repeatability (three aircraft, calm, same seed): **%s**; both repeats completed: **%s**." % [
		"bit-identical for all sampled state and command values" if replay_identical else "failed",
		"yes" if replay_complete else "no"])
	summary_file.store_line("")
	summary_file.store_line("| Gate | Limit |")
	summary_file.store_line("|---|---:|")
	summary_file.store_line("| Local terrain clearance | 20 m minimum; 20 m above highest assigned target maximum |")
	summary_file.store_line("| True airspeed | 10–25 m/s |")
	summary_file.store_line("| Assigned circuit radial error | 40 m maximum |")
	summary_file.store_line("| Player / other-aircraft center separation | 30 m / 15 m minimum |")
	summary_file.store_line("| Normalized command travel | absolute value at most 1 |")
	summary_file.store_line("")
	summary_file.store_line("The gentle-practice condition is the project's estimated practice preset (1.5 m/s east wind, 0.6 m/s horizontal gust, 0.15 m/s vertical gust, turbulence RMS 0.15/0.15/0.08 m/s with seed 20261011); it is not measured site weather. The matrix does not establish 60 fps performance or physical realism. Encounter behavior is covered separately by `app/tests/test_companions_pilot.gd`; long-flight matrix scenarios contain no scripted encounter traffic beyond the stationary player and companion fleet.")
	summary_file.store_line("")
	summary_file.store_line("Run-specific checked-runner log identity and source hashes are recorded after the run.")
	summary_file.close()
	return {"ok": true, "directory": output_dir}


func _max_result(results: Array, key: String) -> float:
	var highest: float = -INF
	for item_value: Variant in results:
		var item: Dictionary = item_value
		highest = maxf(highest, float(item.get(key, -INF)))
	return highest


func _item_passes(item: Dictionary) -> bool:
	return item.get("complete", false) and str(item.get("stop_reason", "" )).is_empty() \
		and float(item.get("min_clearance", -INF)) >= MIN_CLEARANCE_M \
		and float(item.get("max_clearance", INF)) <= 35.0 + float(item.get("count", 1) - 1) * 20.0 + 20.0 \
		and float(item.get("min_tas", -INF)) >= MIN_TAS_MPS and float(item.get("max_tas", INF)) <= MAX_TAS_MPS \
		and float(item.get("max_radius_error", INF)) <= MAX_RADIUS_ERROR_M \
		and float(item.get("min_player_separation", -INF)) >= PLAYER_SEPARATION_M \
		and float(item.get("max_control", INF)) <= 1.0 \
		and (int(item.get("count", 1)) == 1 or float(item.get("min_pair_separation", -INF)) >= PAIR_SEPARATION_M)


func SimStateFinite(state: PackedFloat64Array) -> bool:
	if state.size() != RigidBody.SIZE:
		return false
	for value: float in state:
		if not is_finite(value):
			return false
	return true
