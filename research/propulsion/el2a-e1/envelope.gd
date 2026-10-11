extends SceneTree

const Session = preload("res://sim/flight_session.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const GroundStart = preload("res://physics/ground_start.gd")
const Ground = preload("res://physics/ground_contact.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Trim = preload("res://physics/trim.gd")
const LandingPilot = preload("res://sim/landing_maneuver.gd")
const LandingEvidence = preload("res://tests/landing_test_driver.gd")
const Recorder = preload("res://sim/recorder.gd")
const Sim = preload("res://sim/simulation.gd")

const AIRCRAFT := {
	"4s": "res://data/aircraft/synthetic_stik_electric_4s_battery.json",
	"6s": "res://data/aircraft/synthetic_stik_electric_6s_battery.json",
}
const DURATIONS := {"takeoff": 8.0, "stall": 20.0, "landing": 46.0}
const TRACE_FORMAT := "openrc-el2a-e1-case v1"
const G := 9.80665
const STALL_START_ALTITUDE_M := 150.0
const STALL_RECOVERY_FLOOR_M := 35.0
const LANDING_START_SHIFT_M := 2.0 # explicit start-position adjustment from baseline threshold-short trace

var _pack := ""
var _maneuver := ""
var _hz := 240
var _out_dir := ""


func _initialize() -> void:
	_parse_args()
	if not AIRCRAFT.has(_pack) or not DURATIONS.has(_maneuver) or _hz not in [240, 480] or _out_dir.is_empty():
		printerr("usage: -- --pack=4s|6s --hz=240|480 --maneuver=takeoff|stall|landing --out=<fresh-directory>")
		quit(2)
		return
	Engine.physics_ticks_per_second = _hz
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var duration_s: float = DURATIONS[_maneuver]
	var expected_ticks := roundi(duration_s * float(_hz))
	var result := {
		"format": TRACE_FORMAT, "pack": _pack, "maneuver": _maneuver,
		"hz": _hz, "simulation_hz": _hz, "planned_duration_s": duration_s,
		"duration_s": duration_s, "expected_ticks": expected_ticks, "ticks": 0,
		"actual_duration_s": 0.0, "completed": false, "passed": false,
		"metrics": {}, "criteria": {}, "fault": "", "crash": "", "pause_reason": "",
		"error": "", "trace": {"path": "", "save_ok": false, "format_v8": false,
			"row_count": 0, "expected_rows": 1, "continuous": false, "gaps": []},
	}
	var session: Node = Session.new()
	session.setup(AIRCRAFT[_pack])
	root.add_child(session)
	session.process_mode = Node.PROCESS_MODE_DISABLED
	session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	session.input_enabled = false
	if not session.aircraft.get("ok", false):
		result.error = "aircraft setup: %s" % str(session.aircraft.get("message", "invalid aircraft"))
		_finish_without_trace(session, result)
		return
	var loaded: Dictionary = FieldLoader.load_from()
	if not loaded.get("ok", false) or not session.set_field(loaded.get("field", {})):
		result.error = "field setup: %s" % str(loaded.get("message", session.surface_error))
		_finish_without_trace(session, result)
		return
	var run: Dictionary
	match _maneuver:
		"takeoff": run = _takeoff(session, loaded.field, duration_s, expected_ticks)
		"stall": run = _stall(session, duration_s, expected_ticks)
		"landing": run = _landing(session, loaded.field, duration_s, expected_ticks)
	result.error = str(run.get("error", ""))
	result.metrics = run.get("metrics", {})
	result.criteria = run.get("criteria", {})
	var initial_tick: int = int(run.get("initial_tick", session.sim.tick))
	var recorder: Variant = run.get("recorder", null)
	var ticks: int = maxi(0, int(session.sim.tick) - initial_tick)
	result.ticks = ticks
	result.actual_duration_s = float(ticks) * session.sim.dt()
	result.fault = str(session.sim.fault_reason)
	result.crash = _crash_text(session.crash)
	result.pause_reason = str(session.pause_reason)
	if recorder != null:
		var base := "%s_%s_%d" % [_pack, _maneuver, _hz]
		var csv_path := _out_dir.path_join(base + ".csv")
		var save_error: int = recorder.stop(csv_path)
		var trace: Variant = recorder.trace
		var trace_text: String = trace.to_csv()
		result.trace = {
			"path": csv_path, "save_ok": save_error == OK,
			"format_v8": trace_text.begins_with("# format: openrc-trace v8\n"),
			"row_count": trace.row_count(), "expected_rows": ticks + 1,
			"continuous": trace.is_continuous(), "gaps": Array(trace.gaps()),
		}
		recorder.detach()
	else:
		result.error = _append_error(result.error, "maneuver did not create a recorder")
	var criteria: Dictionary = result.criteria
	criteria["exact_planned_tick_count"] = ticks == expected_ticks
	criteria["no_simulation_fault"] = result.fault.is_empty()
	criteria["no_crash"] = result.crash.is_empty()
	criteria["not_paused"] = not session.sim.paused
	criteria["complete_v8_trace"] = bool(result.trace.save_ok) and bool(result.trace.format_v8) \
		and bool(result.trace.continuous) and int(result.trace.row_count) == ticks + 1
	result.completed = ticks == expected_ticks and result.fault.is_empty() and result.crash.is_empty() \
		and not session.sim.paused and result.error.is_empty()
	result.passed = result.completed and _all_true(criteria)
	if not result.completed:
		result.error = _append_error(result.error, "maneuver stopped before its planned terminal tick")
	var json_saved: bool = _write_result(result)
	print(JSON.stringify(result, "\t", true, true))
	session.free()
	quit(0 if result.passed and json_saved else 1)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			_pack = arg.trim_prefix("--pack=")
		elif arg.begins_with("--maneuver="):
			_maneuver = arg.trim_prefix("--maneuver=")
		elif arg.begins_with("--hz="):
			_hz = int(arg.trim_prefix("--hz="))
		elif arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=").trim_suffix("/").trim_suffix("\\")


func _finish_without_trace(session: Node, result: Dictionary) -> void:
	result.fault = str(session.sim.fault_reason)
	result.crash = _crash_text(session.crash)
	result.pause_reason = str(session.pause_reason)
	result.error = _append_error(result.error, "case setup did not produce a trace")
	result.criteria = {"setup_succeeded": false, "no_simulation_fault": result.fault.is_empty(),
		"no_crash": result.crash.is_empty(), "not_paused": not session.sim.paused,
		"exact_planned_tick_count": false, "complete_v8_trace": false}
	var json_saved: bool = _write_result(result)
	print(JSON.stringify(result, "\t", true, true))
	session.free()
	quit(1 if json_saved else 2)


func _takeoff(session: Node, field: Dictionary, duration_s: float, expected_ticks: int) -> Dictionary:
	var runway: Dictionary = _runway(field)
	var spot: Dictionary = GroundStart.threshold(field)
	if runway.is_empty() or not spot.get("ok", false):
		return {error = "runway threshold unavailable", metrics = {}, criteria = {}}
	if not session.reset_on_runway(float(spot.north), float(spot.east), float(spot.heading)):
		return {error = "runway reset refused: %s" % str(session.start_error), metrics = {}, criteria = {}}
	session._physics_process(session.sim.dt())
	if not _ready(session):
		return {error = "runway reset returned an invalid, paused or faulted start", metrics = {}, criteria = {}}
	var initial_tick: int = session.sim.tick
	var model: Dictionary = session.aircraft.model
	var vs := _vs1g(model, session.air_density())
	var start_east: float = session.sim.state[RB.POS + 1]
	var center_east: float = float(runway.center_east)
	var center_north: float = float(runway.center_north)
	var half_length: float = float(runway.length_east_west) * 0.5
	var half_width: float = float(runway.width_north_south) * 0.5
	var direction := 1.0
	var heading := float(spot.heading)
	var initial_electrical: Dictionary = session.electrical_state()
	var metrics := {"vs1g_mps": vs, "initial_speed_mps": _speed(session.sim.state),
		"initial_battery_soc": float(initial_electrical.get("soc", 0.0)),
		"liftoff_detected": false, "liftoff_time_s": -1.0, "liftoff_distance_m": -1.0,
		"liftoff_speed_mps": -1.0, "liftoff_heading_error_deg": -1.0,
		"max_heading_error_before_liftoff_deg": 0.0, "wheel_clear_s": 0.0,
		"minimum_lateral_margin_before_liftoff_m": _runway_margins(session.sim.state,
			model.landing_gear, center_north, center_east, half_length, half_width)[1],
		"max_speed_mps": 0.0, "final_speed_mps": 0.0,
		"battery_soc": 0.0, "battery_exhausted": false}
	var recorder: RefCounted = _start_recorder(session, "takeoff", duration_s,
		"runway full-throttle baseline; neutral surfaces; no aircraft-data changes")
	var dt: float = session.sim.dt()
	var wheel_clear_s := 0.0
	var candidate: Dictionary = {}
	var max_heading := 0.0
	for tick: int in expected_ticks:
		if not _advance(session, {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 1.0}):
			break
		var state: PackedFloat64Array = session.sim.state
		if not metrics.liftoff_detected:
			var margins := _runway_margins(state, model.landing_gear, center_north, center_east, half_length, half_width)
			metrics.minimum_lateral_margin_before_liftoff_m = minf(float(metrics.minimum_lateral_margin_before_liftoff_m), margins[1])
		var compressions: PackedFloat64Array = session.gear_compressions(state)
		var all_clear := not compressions.is_empty()
		for compression: float in compressions:
			all_clear = all_clear and compression <= 0.0
		var euler := _euler(state)
		var heading_error := absf(wrapf(euler[0] - heading, -PI, PI))
		if not bool(metrics.liftoff_detected):
			max_heading = maxf(max_heading, heading_error)
		var speed := _speed(state)
		metrics.max_speed_mps = maxf(float(metrics.max_speed_mps), speed)
		if all_clear and speed > 0.5 * vs:
			if candidate.is_empty():
				candidate = {time = session.sim.time(), distance = direction * (state[RB.POS + 1] - start_east),
					speed = speed, heading_error = rad_to_deg(heading_error)}
			wheel_clear_s += dt
			if wheel_clear_s >= 0.5 and not metrics.liftoff_detected:
				metrics.liftoff_detected = true
				metrics.liftoff_time_s = float(candidate.time)
				metrics.liftoff_distance_m = float(candidate.distance)
				metrics.liftoff_speed_mps = float(candidate.speed)
				metrics.liftoff_heading_error_deg = float(candidate.heading_error)
		else:
			wheel_clear_s = 0.0
			candidate = {}
		metrics.wheel_clear_s = wheel_clear_s
		metrics.max_heading_error_before_liftoff_deg = rad_to_deg(max_heading)
		metrics.final_speed_mps = speed
		var electrical: Dictionary = session.electrical_state()
		metrics.battery_soc = float(electrical.get("soc", 0.0))
		metrics.battery_exhausted = bool(electrical.get("exhausted", false))
	var runway_limit: float = float(runway.length_east_west) - 6.0
	var criteria := {
		"runway_start_solved": true,
		"sustained_wheel_clearance_at_least_0_5_s": bool(metrics.liftoff_detected)
			and float(metrics.wheel_clear_s) >= 0.5,
		"liftoff_before_runway_end": bool(metrics.liftoff_detected) and float(metrics.liftoff_distance_m) > 0.0
			and float(metrics.liftoff_distance_m) < runway_limit,
		"liftoff_heading_error_under_15_deg": bool(metrics.liftoff_detected)
			and float(metrics.liftoff_heading_error_deg) < 15.0,
		"battery_not_exhausted": not bool(metrics.battery_exhausted),
		"heading_before_liftoff_under_15_deg": float(metrics.max_heading_error_before_liftoff_deg) < 15.0,
		"wheel_path_before_liftoff_inside_lateral_margin": float(metrics.minimum_lateral_margin_before_liftoff_m) >= 0.5,
	}
	return {recorder = recorder, initial_tick = initial_tick, metrics = metrics, criteria = criteria}


func _stall(session: Node, duration_s: float, expected_ticks: int) -> Dictionary:
	var model: Dictionary = session.aircraft.model
	var vs := _vs1g(model, session.air_density())
	var entry_speed := 1.4 * vs
	var trim: Dictionary = session.trim_at(entry_speed, "level")
	if not trim.get("ok", false):
		return {error = "stall-entry trim refused: %s" % str(trim.get("message", "unknown")), metrics = {}, criteria = {}}
	session.set_start_altitude(STALL_START_ALTITUDE_M)
	session.reset()
	session._physics_process(session.sim.dt())
	if not _ready(session):
		return {error = "stall reset returned an invalid, paused or faulted start", metrics = {}, criteria = {}}
	var initial_tick: int = session.sim.tick
	var dt: float = session.sim.dt()
	var heading := _euler(session.sim.state)[0]
	var alpha_a2: float = float(model.envelope.a2)
	var initial_electrical: Dictionary = session.electrical_state()
	var metrics := {"profile": "1.4Vs power-off accelerated pull-up to alpha a2, unload and power-on recovery",
		"vs1g_mps": vs, "entry_speed_mps": _speed(session.sim.state),
		"entry_speed_vs": _speed(session.sim.state) / vs,
		"start_altitude_m": -session.sim.state[RB.POS + 2],
		"initial_battery_soc": float(initial_electrical.get("soc", 0.0)),
		"stall_alpha_a2_deg": rad_to_deg(alpha_a2), "stall_detected": false,
		"stall_time_s": -1.0, "stall_altitude_m": -1.0,
		"max_alpha_deg": rad_to_deg(_alpha(session.sim.state)),
		"minimum_speed_mps": _speed(session.sim.state),
		"minimum_altitude_after_stall_m": STALL_START_ALTITUDE_M,
		"altitude_lost_m": 0.0, "recovery_detected": false,
		"recovery_time_s": -1.0, "recovery_latency_s": -1.0,
		"stable_final_s": 0.0, "final_alpha_deg": 0.0,
		"final_bank_deg": 0.0, "final_climb_rate_mps": 0.0,
		"final_speed_mps": 0.0, "final_altitude_m": 0.0,
		"battery_exhausted": false}
	var recorder: RefCounted = _start_recorder(session, "stall", duration_s,
		"alpha-a2-triggered power-off accelerated pull-up and powered recovery")
	var stall_time := -1.0
	var recovery_time := -1.0
	var stable_s := 0.0
	var min_altitude := STALL_START_ALTITUDE_M
	var target_speed := 1.3 * vs
	for tick: int in expected_ticks:
		if not _ready(session):
			break
		var before: PackedFloat64Array = session.sim.state
		var t: float = float(session.sim.tick - initial_tick) * dt
		var alpha := _alpha(before)
		var euler := _euler(before)
		var speed := _speed(before)
		var climb := _climb(before)
		metrics.max_alpha_deg = maxf(float(metrics.max_alpha_deg), rad_to_deg(alpha))
		metrics.minimum_speed_mps = minf(float(metrics.minimum_speed_mps), speed)
		var pitch := 1.0
		var throttle := 0.0
		if stall_time >= 0.0:
			pitch = -0.6 if t - stall_time < 0.75 else 0.0
			throttle = clampf(float(trim.throttle) + 0.10 * (target_speed - speed), 0.0, 1.0)
		var cmd := {roll = clampf(-2.0 * euler[2] - 0.3 * before[RB.RATE], -1.0, 1.0),
			pitch = pitch, yaw = clampf(2.0 * wrapf(heading - euler[0], -PI, PI) - before[RB.RATE + 2], -1.0, 1.0),
			throttle = throttle}
		if not _advance(session, cmd):
			break
		var after: PackedFloat64Array = session.sim.state
		var after_alpha := _alpha(after)
		var after_speed := _speed(after)
		var after_euler := _euler(after)
		var after_climb := _climb(after)
		var altitude := -after[RB.POS + 2]
		metrics.max_alpha_deg = maxf(float(metrics.max_alpha_deg), rad_to_deg(after_alpha))
		metrics.minimum_speed_mps = minf(float(metrics.minimum_speed_mps), after_speed)
		metrics.final_speed_mps = after_speed
		metrics.final_altitude_m = altitude
		metrics.final_alpha_deg = rad_to_deg(after_alpha)
		metrics.final_bank_deg = rad_to_deg(after_euler[2])
		metrics.final_climb_rate_mps = after_climb
		var electrical: Dictionary = session.electrical_state()
		metrics.battery_exhausted = bool(electrical.get("exhausted", false))
		if stall_time < 0.0 and after_alpha >= alpha_a2:
			stall_time = session.sim.time()
			metrics.stall_detected = true
			metrics.stall_time_s = stall_time
			metrics.stall_altitude_m = altitude
		if stall_time >= 0.0:
			min_altitude = minf(min_altitude, altitude)
			metrics.minimum_altitude_after_stall_m = min_altitude
			metrics.altitude_lost_m = float(metrics.stall_altitude_m) - min_altitude
			var stable := after_speed >= 1.2 * vs and absf(rad_to_deg(after_alpha)) < 8.0 \
				and absf(rad_to_deg(after_euler[2])) < 20.0 and after_climb > -5.0 and after_climb < 8.0
			stable_s = stable_s + dt if stable else 0.0
			if recovery_time < 0.0 and stable_s >= 1.0:
				recovery_time = session.sim.time()
				metrics.recovery_detected = true
				metrics.recovery_time_s = recovery_time
				metrics.recovery_latency_s = recovery_time - stall_time
		metrics.stable_final_s = stable_s
	var criteria := {
		"positive_alpha_reached_model_a2": bool(metrics.stall_detected)
			and float(metrics.max_alpha_deg) >= rad_to_deg(alpha_a2),
		"recovered_within_10_s": bool(metrics.recovery_detected)
			and float(metrics.recovery_latency_s) <= 10.0,
		"altitude_loss_below_80_m": bool(metrics.stall_detected) and float(metrics.altitude_lost_m) < 80.0,
		"above_35_m_recovery_floor": float(metrics.minimum_altitude_after_stall_m) > STALL_RECOVERY_FLOOR_M,
		"stable_for_final_1_s": float(metrics.stable_final_s) >= 1.0,
		"battery_not_exhausted": not bool(metrics.battery_exhausted),
	}
	return {recorder = recorder, initial_tick = initial_tick, metrics = metrics, criteria = criteria}


func _landing(session: Node, field: Dictionary, duration_s: float, expected_ticks: int) -> Dictionary:
	var runway: Dictionary = _runway(field)
	if runway.is_empty():
		return {error = "runway surface unavailable", metrics = {}, criteria = {}}
	var trim: Dictionary = session.trim_at(LandingPilot.APPROACH_SPEED)
	if not trim.get("ok", false):
		return {error = "approach trim refused: %s" % str(trim.get("message", "unknown")), metrics = {}, criteria = {}}
	var direction := 1.0
	var heading := direction * PI / 2.0
	var half_length: float = float(runway.length_east_west) * 0.5
	var half_width: float = float(runway.width_north_south) * 0.5
	var center_north: float = float(runway.center_north)
	var center_east: float = float(runway.center_east)
	var start_east := center_east - direction * (half_length + LandingPilot.START_BEFORE_END - LANDING_START_SHIFT_M)
	var start := Trim.state_for(LandingPilot.APPROACH_SPEED, trim.alpha, 0.0, heading,
		M.v3(center_north, start_east, -LandingPilot.START_ALTITUDE), trim.beta)
	var attitude := M.q_from_euler(heading, trim.alpha, 0.0)
	for i: int in 4:
		start[RB.ATT + i] = attitude[i]
	session.start.state = start
	session.reset()
	session._physics_process(session.sim.dt())
	if not _ready(session):
		return {error = "landing reset returned an invalid, paused or faulted start", metrics = {}, criteria = {}}
	var initial_tick: int = session.sim.tick
	var dt: float = session.sim.dt()
	var pilot: RefCounted = LandingPilot.new(center_north, true, float(trim.throttle), float(trim.pitch_command))
	var gear: Dictionary = session.aircraft.model.landing_gear
	var initial_electrical: Dictionary = session.electrical_state()
	var metrics := {"approach_speed_mps": LandingPilot.APPROACH_SPEED,
		"approach_speed_vs": LandingPilot.APPROACH_SPEED / _vs1g(session.aircraft.model, session.air_density()),
		"start_shift_along_runway_m": LANDING_START_SHIFT_M,
		"initial_battery_soc": float(initial_electrical.get("soc", 0.0)),
		"touchdown_detected": false, "touchdown_time_s": -1.0,
		"touchdown_from_threshold_m": -1.0, "touchdown_speed_mps": -1.0,
		"touchdown_sink_mps": -1.0, "max_contact_sink_mps": 0.0,
		"minimum_longitudinal_margin_m": INF, "minimum_lateral_margin_m": INF,
		"minimum_runway_margin_m": INF, "airborne_after_touch_s": 0.0,
		"stop_time_s": -1.0, "stop_runway_margin_m": -1.0,
		"stop_dwell_s": 0.0, "stopped_then_moved": false,
		"final_speed_mps": 0.0, "battery_exhausted": false}
	var recorder: RefCounted = _start_recorder(session, "landing", duration_s,
		"existing LandingManeuver, +2 m along-runway start-position adjustment")
	var threshold_east := center_east - direction * half_length
	var touched := false
	var dwell := 0.0
	var stopped_position := PackedFloat64Array()
	var stop_recorded := false
	var airborne_after := 0.0
	for tick: int in expected_ticks:
		if not _ready(session):
			break
		var before: PackedFloat64Array = session.sim.state
		var compressions: PackedFloat64Array = session.gear_compressions(before)
		var clearance := -compressions[0] if not compressions.is_empty() else -1e30
		for compression: float in compressions:
			clearance = minf(clearance, -compression)
		var command: Dictionary = pilot.commands(before, clearance)
		if not _advance(session, command):
			break
		var after: PackedFloat64Array = session.sim.state
		var post_compressions: PackedFloat64Array = session.gear_compressions(after)
		var all_down := not post_compressions.is_empty()
		var any_down := false
		for i: int in gear.contacts.size():
			var previous: PackedFloat64Array = LandingEvidence.contact_state(before, gear.contacts[i].position)
			var point: PackedFloat64Array = LandingEvidence.contact_state(after, gear.contacts[i].position)
			var compression: float = post_compressions[i]
			all_down = all_down and compression > 0.0
			any_down = any_down or compression > 0.0
			if previous[2] <= 0.0 and point[2] > 0.0:
				var sink := maxf(previous[5], point[5])
				metrics.max_contact_sink_mps = maxf(float(metrics.max_contact_sink_mps), sink)
				if not touched:
					touched = true
					metrics.touchdown_detected = true
					metrics.touchdown_time_s = session.sim.time()
					metrics.touchdown_from_threshold_m = direction * (point[1] - threshold_east)
					metrics.touchdown_speed_mps = _speed(before)
					metrics.touchdown_sink_mps = sink
		if touched:
			for contact: Dictionary in gear.contacts:
				var point: PackedFloat64Array = LandingEvidence.contact_state(after, contact.position)
				var longitudinal := half_length - absf(point[1] - center_east)
				var lateral := half_width - absf(point[0] - center_north)
				metrics.minimum_longitudinal_margin_m = minf(float(metrics.minimum_longitudinal_margin_m), longitudinal)
				metrics.minimum_lateral_margin_m = minf(float(metrics.minimum_lateral_margin_m), lateral)
				metrics.minimum_runway_margin_m = minf(float(metrics.minimum_runway_margin_m), minf(longitudinal, lateral))
			if not any_down:
				airborne_after += dt
		var anchored := true
		for i: int in gear.contacts.size():
			anchored = anchored and session.sim.aux[Session.AUX_ANCHORS + i * Ground.ANCHOR_STRIDE + 2] == 1.0
		var speed := _speed(after)
		var angular := M.norm(M.v3(after[RB.RATE], after[RB.RATE + 1], after[RB.RATE + 2]))
		if touched and all_down and anchored and speed < 0.02 and angular < 0.01:
			dwell += dt
		else:
			dwell = 0.0
			if stop_recorded:
				metrics.stopped_then_moved = true
		if dwell >= 2.0 and not stop_recorded:
			stop_recorded = true
			metrics.stop_time_s = session.sim.time()
			stopped_position = M.v3(after[RB.POS], after[RB.POS + 1], after[RB.POS + 2])
			var margins: PackedFloat64Array = _runway_margins(after, gear, center_north, center_east, half_length, half_width)
			metrics.stop_runway_margin_m = minf(margins[0], margins[1])
		if stop_recorded:
			var drift := M.norm(M.sub(M.v3(after[RB.POS], after[RB.POS + 1], after[RB.POS + 2]), stopped_position))
			metrics["max_stop_drift_m"] = maxf(float(metrics.get("max_stop_drift_m", 0.0)), drift)
		metrics.airborne_after_touch_s = airborne_after
		metrics.stop_dwell_s = dwell
		metrics.final_speed_mps = speed
		var electrical: Dictionary = session.electrical_state()
		metrics.battery_exhausted = bool(electrical.get("exhausted", false))
	if not touched:
		metrics.minimum_longitudinal_margin_m = -1.0
		metrics.minimum_lateral_margin_m = -1.0
		metrics.minimum_runway_margin_m = -1.0
	# The touchdown coordinate is recovered from distance-to-threshold so the criteria stay independent of a center shift.
	var threshold_to_stop := direction * ((stopped_position[1] if not stopped_position.is_empty() else 0.0) - threshold_east)
	metrics["rollout_distance_m"] = threshold_to_stop - float(metrics.touchdown_from_threshold_m) if touched and stop_recorded else -1.0
	var criteria := {
		"approach_speed_above_1_15_vs": float(metrics.approach_speed_vs) >= 1.15,
		"touchdown_inside_first_half": touched and float(metrics.touchdown_from_threshold_m) >= 0.0
			and float(metrics.touchdown_from_threshold_m) <= half_length,
		"touchdown_sink_below_1_2_mps": touched and float(metrics.touchdown_sink_mps) < 1.2,
		"wheel_path_inside_runway_with_0_5_m_margin": touched and float(metrics.minimum_runway_margin_m) >= 0.5,
		"stop_inside_runway_with_0_5_m_margin": stop_recorded and float(metrics.stop_runway_margin_m) >= 0.5,
		"no_bounce_over_0_5_s": airborne_after < 0.5,
		"stopped_and_held_for_2_s": stop_recorded and dwell >= 2.0 and not bool(metrics.stopped_then_moved)
			and float(metrics.get("max_stop_drift_m", 0.0)) < 0.002,
		"rollout_under_200_m": stop_recorded and float(metrics.rollout_distance_m) >= 0.0
			and float(metrics.rollout_distance_m) < 200.0,
		"final_speed_below_3_mps": float(metrics.final_speed_mps) < 3.0,
		"final_speed_below_0_02_mps": float(metrics.final_speed_mps) < 0.02,
		"battery_not_exhausted": not bool(metrics.battery_exhausted),
	}
	return {recorder = recorder, initial_tick = initial_tick, metrics = metrics, criteria = criteria}


func _start_recorder(session: Node, maneuver: String, duration_s: float, pilot: String) -> RefCounted:
	var recorder: RefCounted = Recorder.new(session.sim, Callable(session, "electrical_state"))
	var meta: Dictionary = session.trace_meta()
	meta["el2a_e1_pack"] = _pack
	meta["el2a_e1_maneuver"] = maneuver
	meta["el2a_e1_simulation_hz"] = _hz
	meta["el2a_e1_planned_duration_s"] = duration_s
	meta["el2a_e1_pilot"] = pilot
	meta["el2a_e1_start_policy"] = "fresh FlightSession and fixture initial charge for every case"
	if maneuver == "landing":
		meta["el2a_e1_landing_start_shift_m"] = LANDING_START_SHIFT_M
	recorder.start(meta)
	return recorder


func _advance(session: Node, command: Dictionary) -> bool:
	if not _ready(session):
		return false
	var before_tick: int = session.sim.tick
	session.commands = command
	session.sim.inputs = session._inputs()
	session.sim.step()
	if int(session.sim.tick) != before_tick + 1:
		return false
	session._physics_process(session.sim.dt())
	return _ready(session)


func _ready(session: Node) -> bool:
	return session.crash.is_empty() and session.sim.fault_reason.is_empty() and not session.sim.paused \
		and Sim.state_is_valid(session.sim.state)


func _runway_margins(state: PackedFloat64Array, gear: Dictionary, center_north: float,
		center_east: float, half_length: float, half_width: float) -> PackedFloat64Array:
	var longitudinal := INF
	var lateral := INF
	for contact: Dictionary in gear.contacts:
		var point: PackedFloat64Array = LandingEvidence.contact_state(state, contact.position)
		longitudinal = minf(longitudinal, half_length - absf(point[1] - center_east))
		lateral = minf(lateral, half_width - absf(point[0] - center_north))
	return PackedFloat64Array([longitudinal, lateral])


func _runway(field: Dictionary) -> Dictionary:
	for surface: Dictionary in field.get("surfaces", []):
		if surface.get("id", "") == field.get("runway", ""):
			return surface
	return {}


func _vs1g(model: Dictionary, rho: float) -> float:
	return sqrt(2.0 * float(model.mass_kg) * G / (rho * float(model.reference.S) * float(model.envelope.CL_max)))


func _alpha(state: PackedFloat64Array) -> float:
	return atan2(state[RB.VEL + 2], state[RB.VEL])


func _speed(state: PackedFloat64Array) -> float:
	return sqrt(state[RB.VEL] * state[RB.VEL] + state[RB.VEL + 1] * state[RB.VEL + 1] + state[RB.VEL + 2] * state[RB.VEL + 2])


func _euler(state: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_to_euler(M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]))


func _climb(state: PackedFloat64Array) -> float:
	var q := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	return -M.q_rotate(q, M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))[2]


func _crash_text(crash: Dictionary) -> String:
	return str(crash.get("why", "crash")) if not crash.is_empty() else ""


func _all_true(criteria: Dictionary) -> bool:
	if criteria.is_empty():
		return false
	for value: Variant in criteria.values():
		if typeof(value) != TYPE_BOOL or not value:
			return false
	return true


func _append_error(first: String, second: String) -> String:
	return second if first.is_empty() else first + "; " + second


func _write_result(result: Dictionary) -> bool:
	var base := "%s_%s_%d" % [_pack, _maneuver, _hz]
	var json_path := _out_dir.path_join(base + ".json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write case JSON %s, error %d" % [json_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(result, "\t", true, true) + "\n")
	file.close()
	return true
