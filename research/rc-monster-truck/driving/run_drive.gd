extends SceneTree

## Research-only, closed-loop driving trials through the real ground-vehicle session.
## The driver supplies controls; Session and VehicleDynamics retain ownership of all state.

const FieldLoader := preload("res://data/field_loader.gd")
const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Session := preload("res://sim/ground_vehicle/session.gd")
const M := preload("res://physics/math3d.gd")

const FIXED_HZ := 240
const DT := 1.0 / float(FIXED_HZ)
const PATH_STEP_M := 0.5
const LOOP_STRAIGHT_M := 24.0
const LOOP_ARC_M := PI * 6.0
const LOOP_LENGTH_M := 2.0 * LOOP_STRAIGHT_M + 2.0 * LOOP_ARC_M
const ACCELERATION_SECONDS := 3.0
const ROUTE_BRAKE_LIMIT := 0.35
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

var _scenario := ""
var _pace := "steady"
var _vehicle_path := ""
var _output_path := ""
var _max_seconds := 0.0
var _session
var _route: Array[PackedFloat64Array] = []
var _route_closed := false
var _route_length_m := 0.0
var _path_progress_m := 0.0
var _last_path_index := -1


func _initialize() -> void:
	var parsed := _parse_args(OS.get_cmdline_user_args())
	if not bool(parsed.get("ok", false)):
		_fail(str(parsed.get("error", "invalid arguments")))
		return
	_scenario = str(parsed.scenario)
	_pace = str(parsed.pace)
	_vehicle_path = str(parsed.vehicle)
	_output_path = str(parsed.output)
	_max_seconds = float(parsed.max_seconds)
	if FileAccess.file_exists(_output_path):
		_fail("refusing to replace existing CSV: " + _output_path)
		return
	var json_path := _json_path()
	if FileAccess.file_exists(json_path):
		_fail("refusing to replace existing JSON: " + json_path)
		return

	var field_result: Dictionary = FieldLoader.load_from()
	if not bool(field_result.get("ok", false)):
		_fail("default airfield could not be loaded: " + str(field_result.get("errors", [])))
		return
	var course_result: Dictionary = AirfieldCourse.build(field_result)
	if not bool(course_result.get("ok", false)):
		_fail("airfield vehicle course could not be built: " + str(course_result.get("errors", [])))
		return
	var vehicle_result: Dictionary = VehicleData.load_default() if _vehicle_path.is_empty() else VehicleData.load_file(_vehicle_path)
	if not bool(vehicle_result.get("ok", false)):
		_fail("vehicle data could not be loaded: " + str(vehicle_result.get("errors", [])))
		return

	_session = Session.new()
	if not _session.prepare(vehicle_result, course_result, vehicle_result, 0.0):
		_fail("ground-vehicle session preparation failed: " + _session.load_error)
		_session.free()
		return
	var spawn_id := "start" if _scenario == "runway" else "track_rollers"
	if _scenario == "slalom":
		spawn_id = "track_technical"
	if not _session.reset(spawn_id):
		_fail("session could not reset at " + spawn_id + ": " + _session.load_error)
		_session.free()
		return
	if not _session.tick_once(NEUTRAL) or not _session.resume():
		_fail("session could not complete the neutral-armed resume sequence")
		_session.free()
		return

	if _scenario == "circuit":
		_route = _make_loop_route()
		_route_closed = true
		_route_length_m = LOOP_LENGTH_M
	elif _scenario == "slalom":
		_route = _make_slalom_route()
		_route_closed = false
		_route_length_m = _polyline_length(_route)

	var run_result := _run(course_result.course)
	var save_result := _write_results(run_result, vehicle_result, course_result)
	_session.free()
	if not bool(save_result.get("ok", false)):
		_fail(str(save_result.get("error", "could not write drive results")))
		return
	print("RCV drive run: scenario=%s complete=%s ticks=%d max_speed_mps=%.6f samples=%d csv=%s" % [
		_scenario, str(run_result.complete), int(run_result.ticks), float(run_result.max_speed_mps),
		int(run_result.sample_count), _output_path])
	quit(0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var values := {}
	for arg in args:
		var split_at := arg.find("=")
		if not arg.begins_with("--") or split_at <= 2:
			return {"ok": false, "error": "expected --name=value arguments"}
		var key := arg.substr(2, split_at - 2)
		if values.has(key):
			return {"ok": false, "error": "duplicate option --" + key}
		values[key] = arg.substr(split_at + 1)
	for key in values.keys():
		if not key in ["scenario", "pace", "vehicle", "output", "max-seconds"]:
			return {"ok": false, "error": "unknown option --" + str(key)}
	var scenario := str(values.get("scenario", ""))
	if not scenario in ["runway", "circuit", "slalom"]:
		return {"ok": false, "error": "--scenario must be runway, circuit, or slalom"}
	var pace := str(values.get("pace", "steady"))
	if not pace in ["steady", "fast"]:
		return {"ok": false, "error": "--pace must be steady or fast"}
	var output := str(values.get("output", ""))
	if output.is_empty() or not output.get_extension().to_lower() == "csv":
		return {"ok": false, "error": "--output must name a fresh .csv path"}
	var max_seconds := 12.0 if scenario == "runway" else 90.0
	if values.has("max-seconds"):
		if not _finite_number(str(values["max-seconds"])):
			return {"ok": false, "error": "--max-seconds must be a finite number"}
		max_seconds = float(values["max-seconds"])
	if max_seconds < 1.0 or max_seconds > 180.0:
		return {"ok": false, "error": "--max-seconds must be in [1, 180]"}
	return {"ok": true, "scenario": scenario, "pace": pace, "vehicle": str(values.get("vehicle", "")),
		"output": output, "max_seconds": max_seconds}


func _run(course: Dictionary) -> Dictionary:
	var max_ticks := int(roundi(_max_seconds * FIXED_HZ))
	var rows := PackedStringArray()
	rows.append(_csv_header())
	var tick_costs := PackedFloat64Array()
	var feature_counts := {}
	var speed_max := 0.0
	var speed_accel_max := -INF
	var speed_accel_min := INF
	var max_path_error := 0.0
	var min_track_coverage := 1.0
	var max_tilt_deg := 0.0
	var rollover_ticks := 0
	var airborne_ticks := 0
	var grounded_ticks := 0
	var max_wheel_contacts := 0
	var max_hull_contacts := 0
	var max_wall_contacts := 0
	var previous_speed := 0.0
	var have_previous_speed := false
	var completed := false
	var failure_reason := ""
	var braking := false
	var brake_start_speed := 0.0
	var brake_start_north := 0.0
	var brake_start_east := 0.0
	var brake_start_tick := -1
	var stop_tick := -1
	var route_initial_index := -1
	var returned_to_start := false
	var last_route_error := 0.0
	var acceleration_phase_ticks := int(roundi(ACCELERATION_SECONDS * FIXED_HZ))
	if not _route.is_empty():
		var initial_state: PackedFloat64Array = _session.state_snapshot()
		route_initial_index = int(_nearest_path_point(initial_state[Vehicle.POS], initial_state[Vehicle.POS + 1]).index)
		_last_path_index = route_initial_index

	for _iteration in max_ticks:
		var before_state: PackedFloat64Array = _session.state_snapshot()
		var before_report: Dictionary = _session.telemetry_snapshot()
		var before_speed := float(before_report.get("speed_m_per_s", 0.0))
		var before_time: float = _session.time_s()
		var control_result := _controls(before_state, before_speed, before_time, course)
		var controls: Dictionary = control_result.controls
		if _scenario == "runway" and str(control_result.phase) == "brake" and not braking:
			braking = true
			brake_start_speed = before_speed
			brake_start_north = before_state[Vehicle.POS]
			brake_start_east = before_state[Vehicle.POS + 1]
			brake_start_tick = int(_session.tick)

		var start_usec := Time.get_ticks_usec()
		var tick_ok: bool = _session.tick_once(controls)
		var tick_cost_us := float(Time.get_ticks_usec() - start_usec)
		if not tick_ok:
			failure_reason = "Session.tick_once rejected tick %d: %s" % [int(_session.tick), _session.fault_reason]
			break
		tick_costs.append(tick_cost_us)
		var state: PackedFloat64Array = _session.state_snapshot()
		var report: Dictionary = _session.telemetry_snapshot()
		var speed := float(report.speed_m_per_s)
		var acceleration := 0.0 if not have_previous_speed else (speed - previous_speed) / DT
		previous_speed = speed
		have_previous_speed = true
		speed_max = maxf(speed_max, speed)
		speed_accel_max = maxf(speed_accel_max, acceleration)
		speed_accel_min = minf(speed_accel_min, acceleration)

		var path_index := -1
		var path_error := 0.0
		if not _route.is_empty():
			var path_match := _nearest_path_point(state[Vehicle.POS], state[Vehicle.POS + 1])
			path_index = int(path_match.index)
			path_error = float(path_match.distance_m)
			if route_initial_index < 0:
				route_initial_index = path_index
				_last_path_index = path_index
			else:
				_update_progress(path_index, speed)
			max_path_error = maxf(max_path_error, path_error)
			last_route_error = path_error

		var road: Dictionary = AirfieldCourse.sample(course, state[Vehicle.POS], state[Vehicle.POS + 1])
		var coverage := float(road.get("track_coverage", 0.0))
		min_track_coverage = minf(min_track_coverage, coverage)
		var feature_id := str(road.get("feature_id", ""))
		if not feature_id.is_empty():
			feature_counts[feature_id] = int(feature_counts.get(feature_id, 0)) + 1

		var wheel_contacts := _count_set(report.get("wheel_in_contact", PackedByteArray()))
		var hull_contacts := _count_set(report.get("hull_in_contact", PackedByteArray()))
		var airborne := bool(report.get("airborne", false))
		if airborne:
			airborne_ticks += 1
		else:
			grounded_ticks += 1
		max_wheel_contacts = maxi(max_wheel_contacts, wheel_contacts)
		max_hull_contacts = maxi(max_hull_contacts, hull_contacts)
		var wall_contacts := int(report.get("wall_contact_count", 0))
		max_wall_contacts = maxi(max_wall_contacts, wall_contacts)
		var orientation := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1],
			state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
		var body_up: PackedFloat64Array = M.q_rotate(orientation, PackedFloat64Array([0.0, 0.0, -1.0]))
		var upright_cos := clampf(-body_up[2], -1.0, 1.0)
		var tilt_deg := rad_to_deg(acos(upright_cos))
		max_tilt_deg = maxf(max_tilt_deg, tilt_deg)
		var rolled_over := upright_cos <= 0.0
		if rolled_over:
			rollover_ticks += 1

		var phase := str(control_result.phase)
		var lap_value := _path_progress_m if not _route.is_empty() else 0.0
		rows.append(_csv_row(int(_session.tick), float(_session.time_s()), state, report, controls,
			phase, float(control_result.target_speed_mps), acceleration, path_error, lap_value,
			coverage, feature_id, wheel_contacts, hull_contacts, airborne, tilt_deg, rolled_over,
			wall_contacts, tick_cost_us))

		if _scenario == "runway" and braking and stop_tick < 0 \
				and int(_session.tick) - brake_start_tick >= int(0.5 * FIXED_HZ) and speed <= 0.10:
			stop_tick = int(_session.tick)
			completed = true
			break
		if _scenario == "circuit" and _path_progress_m >= _route_length_m \
				and _returned_to_start(path_index, route_initial_index, state):
			returned_to_start = true
			completed = true
			break
		if _scenario == "slalom" and _path_progress_m >= _route_length_m - PATH_STEP_M \
				and path_index >= _route.size() - 3 and path_error <= 1.0:
			completed = true
			break

	if not completed and failure_reason.is_empty():
		failure_reason = "run_limit_reached"
	if speed_accel_max == -INF:
		speed_accel_max = 0.0
	if speed_accel_min == INF:
		speed_accel_min = 0.0
	var braking_distance := 0.0
	if braking:
		var final_state: PackedFloat64Array = _session.state_snapshot()
		var dn := final_state[Vehicle.POS] - brake_start_north
		var de := final_state[Vehicle.POS + 1] - brake_start_east
		braking_distance = M.sqrt_(dn * dn + de * de)
	return {
		"complete": completed,
		"failure_reason": failure_reason,
		"ticks": int(_session.tick),
		"sample_count": rows.size() - 1,
		"elapsed_sim_s": float(_session.time_s()),
		"max_ticks": max_ticks,
		"rows": rows,
		"tick_costs_us": tick_costs,
		"max_speed_mps": speed_max,
		"max_acceleration_mps2": speed_accel_max,
		"min_acceleration_mps2": speed_accel_min,
		"max_path_error_m": max_path_error,
		"final_path_error_m": last_route_error,
		"path_progress_m": _path_progress_m,
		"path_length_m": _route_length_m,
		"lap_fraction": _path_progress_m / _route_length_m if _route_length_m > 0.0 else 0.0,
		"returned_to_start": returned_to_start,
		"min_track_coverage": min_track_coverage,
		"feature_ticks": feature_counts,
		"airborne_ticks": airborne_ticks,
		"grounded_ticks": grounded_ticks,
		"rollover_ticks": rollover_ticks,
		"max_tilt_deg": max_tilt_deg,
		"max_wheel_contacts": max_wheel_contacts,
		"max_hull_contacts": max_hull_contacts,
		"max_wall_contacts": max_wall_contacts,
		"brake_start_tick": brake_start_tick,
		"brake_start_speed_mps": brake_start_speed,
		"braking_distance_m": braking_distance,
		"stop_tick": stop_tick,
	}


func _controls(state: PackedFloat64Array, speed: float, time_s: float, course: Dictionary) -> Dictionary:
	if _scenario == "runway":
		var phase := "accelerate" if time_s < ACCELERATION_SECONDS else "brake"
		if state[Vehicle.POS + 1] >= 35.0:
			phase = "brake"
		var throttle := 1.0 if phase == "accelerate" else 0.0
		var brake := 0.0 if phase == "accelerate" else 1.0
		return {"phase": phase, "controls": {"throttle": throttle, "steering": 0.0,
			"brake": brake, "reverse": false, "armed": true}, "target_speed_mps": 0.0}

	var match := _nearest_path_point(state[Vehicle.POS], state[Vehicle.POS + 1])
	var nearest_index := int(match.index)
	var lookahead_m := clampf(2.5 + speed * 0.50, 3.0, 5.5)
	var lookahead_steps := maxi(1, int(roundi(lookahead_m / PATH_STEP_M)))
	var target_index := _path_index(nearest_index + lookahead_steps)
	var target: PackedFloat64Array = _route[target_index]
	var north_delta := target[0] - state[Vehicle.POS]
	var east_delta := target[1] - state[Vehicle.POS + 1]
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	var yaw := float(M.q_to_euler(q)[0])
	var target_yaw := M.atan2_(east_delta, north_delta)
	var heading_error := wrapf(target_yaw - yaw, -PI, PI)
	var steering := clampf(heading_error * 1.8, -1.0, 1.0)
	var curvature := _path_curvature(nearest_index)
	var target_speed := 3.4
	if curvature > 1.0e-5:
		target_speed = minf(target_speed, M.sqrt_(1.55 / curvature))
	if _feature_ahead(nearest_index, lookahead_steps, course):
		target_speed = minf(target_speed, 2.15)
	if _pace == "fast":
		target_speed = _fast_speed_envelope(nearest_index, course)
	var speed_error := target_speed - speed
	var throttle := clampf(speed_error * 0.70, 0.0, 0.70)
	var brake := clampf(-speed_error * 0.75, 0.0, ROUTE_BRAKE_LIMIT) if speed_error < -0.12 else 0.0
	if brake > 0.0:
		throttle = 0.0
	var mode := "cruise"
	if brake > 0.0:
		mode = "brake"
	elif throttle > 0.0:
		mode = "accelerate"
	return {"phase": mode, "controls": {"throttle": throttle, "steering": steering,
		"brake": brake, "reverse": false, "armed": true}, "target_speed_mps": target_speed}


func _make_loop_route() -> Array[PackedFloat64Array]:
	var route: Array[PackedFloat64Array] = []
	var count := int(ceil(LOOP_LENGTH_M / PATH_STEP_M))
	for index in count:
		route.append(_loop_point(float(index) * PATH_STEP_M))
	return route


func _loop_point(distance_m: float) -> PackedFloat64Array:
	var distance := fposmod(distance_m, LOOP_LENGTH_M)
	if distance < LOOP_STRAIGHT_M:
		return PackedFloat64Array([39.0, -12.0 + distance])
	distance -= LOOP_STRAIGHT_M
	if distance < LOOP_ARC_M:
		var angle := -PI * 0.5 + distance / 6.0
		return PackedFloat64Array([45.0 + 6.0 * M.sin_(angle), 12.0 + 6.0 * M.cos_(angle)])
	distance -= LOOP_ARC_M
	if distance < LOOP_STRAIGHT_M:
		return PackedFloat64Array([51.0, 12.0 - distance])
	distance -= LOOP_STRAIGHT_M
	var angle := PI * 0.5 + distance / 6.0
	return PackedFloat64Array([45.0 + 6.0 * M.sin_(angle), -12.0 + 6.0 * M.cos_(angle)])


func _make_slalom_route() -> Array[PackedFloat64Array]:
	var gates: Array[PackedFloat64Array] = [
		PackedFloat64Array([45.0, -10.0]), PackedFloat64Array([46.0, -7.0]),
		PackedFloat64Array([46.0, -5.0]), PackedFloat64Array([44.0, -2.0]),
		PackedFloat64Array([44.0, 2.0]), PackedFloat64Array([46.0, 5.0]),
		PackedFloat64Array([46.0, 7.0]), PackedFloat64Array([45.0, 10.0]),
	]
	var route: Array[PackedFloat64Array] = [gates[0]]
	for segment in range(gates.size() - 1):
		var a: PackedFloat64Array = gates[segment]
		var b: PackedFloat64Array = gates[segment + 1]
		var dn := b[0] - a[0]
		var de := b[1] - a[1]
		var length := M.sqrt_(dn * dn + de * de)
		var pieces := maxi(1, int(ceil(length / PATH_STEP_M)))
		for part in range(1, pieces + 1):
			var fraction := float(part) / float(pieces)
			route.append(PackedFloat64Array([a[0] + fraction * dn, a[1] + fraction * de]))
	return route


func _polyline_length(route: Array[PackedFloat64Array]) -> float:
	var total := 0.0
	for index in range(1, route.size()):
		var dn := route[index][0] - route[index - 1][0]
		var de := route[index][1] - route[index - 1][1]
		total += M.sqrt_(dn * dn + de * de)
	return total


func _nearest_path_point(north: float, east: float) -> Dictionary:
	var best_index := 0
	var best_squared := INF
	for index in _route.size():
		var dn := _route[index][0] - north
		var de := _route[index][1] - east
		var distance_squared := dn * dn + de * de
		if distance_squared < best_squared:
			best_squared = distance_squared
			best_index = index
	return {"index": best_index, "distance_m": M.sqrt_(best_squared)}


func _path_index(value: int) -> int:
	if _route_closed:
		return posmod(value, _route.size())
	return clampi(value, 0, _route.size() - 1)


func _path_curvature(index: int) -> float:
	if _route.size() < 3:
		return 0.0
	var back := _path_index(index - 2)
	var front := _path_index(index + 2)
	if not _route_closed and (index < 2 or index + 2 >= _route.size()):
		return 0.0
	var centre: PackedFloat64Array = _route[index]
	var previous: PackedFloat64Array = _route[back]
	var following: PackedFloat64Array = _route[front]
	var heading_a := M.atan2_(centre[1] - previous[1], centre[0] - previous[0])
	var heading_b := M.atan2_(following[1] - centre[1], following[0] - centre[0])
	var distance_a := M.sqrt_((centre[0] - previous[0]) * (centre[0] - previous[0])
		+ (centre[1] - previous[1]) * (centre[1] - previous[1]))
	var distance_b := M.sqrt_((following[0] - centre[0]) * (following[0] - centre[0])
		+ (following[1] - centre[1]) * (following[1] - centre[1]))
	var span := 0.5 * (distance_a + distance_b)
	return absf(wrapf(heading_b - heading_a, -PI, PI)) / span if span > 1.0e-12 else 0.0


func _feature_ahead(index: int, lookahead_steps: int, course: Dictionary) -> bool:
	var end_index := index + lookahead_steps + 6
	for route_index in range(index, end_index + 1):
		var point: PackedFloat64Array = _route[_path_index(route_index)]
		var road: Dictionary = AirfieldCourse.sample(course, point[0], point[1])
		var feature_id := str(road.get("feature_id", ""))
		if feature_id == "tabletop" or feature_id == "step_up" or feature_id.begins_with("roller_"):
			return true
		if not _route_closed and route_index >= _route.size() - 1:
			break
	return false


func _fast_speed_envelope(index: int, course: Dictionary) -> float:
	const STRAIGHT_SPEED_MPS := 6.0
	const MAX_LATERAL_ACCEL_MPS2 := 1.55
	const OBSTACLE_SPEED_MPS := 3.0
	const BRAKING_DECEL_MPS2 := 2.5
	const LOOKAHEAD_STEPS := 24
	var target_speed := STRAIGHT_SPEED_MPS
	for offset in range(0, LOOKAHEAD_STEPS + 1):
		var future_index := index + offset
		if not _route_closed and future_index >= _route.size():
			break
		var bounded_index := _path_index(future_index)
		var future_speed := STRAIGHT_SPEED_MPS
		var curvature := _path_curvature(bounded_index)
		if curvature > 1.0e-5:
			future_speed = minf(future_speed, M.sqrt_(MAX_LATERAL_ACCEL_MPS2 / curvature))
		var point: PackedFloat64Array = _route[bounded_index]
		var road: Dictionary = AirfieldCourse.sample(course, point[0], point[1])
		var feature_id := str(road.get("feature_id", ""))
		if feature_id == "tabletop" or feature_id == "step_up" or feature_id.begins_with("roller_"):
			future_speed = minf(future_speed, OBSTACLE_SPEED_MPS)
		var distance_m := float(offset) * PATH_STEP_M
		var reachable_speed := M.sqrt_(future_speed * future_speed + 2.0 * BRAKING_DECEL_MPS2 * distance_m)
		target_speed = minf(target_speed, reachable_speed)
	return target_speed


func _update_progress(index: int, speed: float) -> void:
	if _last_path_index < 0 or _route.is_empty():
		_last_path_index = index
		return
	var delta := index - _last_path_index
	if _route_closed and delta < 0:
		delta += _route.size()
	if _route_closed:
		if delta > _route.size() / 2:
			delta -= _route.size()
		elif delta < -_route.size() / 2:
			delta += _route.size()
	var max_step := maxi(2, int(ceil(maxf(speed, 0.0) * DT / PATH_STEP_M)) + 2)
	if abs(delta) <= max_step:
		_path_progress_m += float(delta) * PATH_STEP_M
	_last_path_index = index


func _returned_to_start(index: int, start_index: int, state: PackedFloat64Array) -> bool:
	if _route.is_empty() or start_index < 0:
		return false
	var separation := absi(index - start_index)
	if _route_closed:
		separation = mini(separation, _route.size() - separation)
	if separation > 3:
		return false
	var start_point: PackedFloat64Array = _route[start_index]
	var dn := state[Vehicle.POS] - start_point[0]
	var de := state[Vehicle.POS + 1] - start_point[1]
	if M.sqrt_(dn * dn + de * de) > 1.0:
		return false
	var next_point: PackedFloat64Array = _route[_path_index(start_index + 1)]
	var route_yaw := M.atan2_(next_point[1] - start_point[1], next_point[0] - start_point[0])
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	var yaw := float(M.q_to_euler(q)[0])
	return absf(wrapf(yaw - route_yaw, -PI, PI)) <= 0.55


func _csv_header() -> String:
	var names := PackedStringArray([
		"tick", "time_s", "phase", "throttle", "steering", "brake", "target_speed_mps",
		"speed_mps", "acceleration_mps2", "north_m", "east_m", "down_m", "path_error_m",
		"path_progress_m", "track_coverage", "feature_id", "wheel_contact_count", "hull_contact_count",
		"grounded", "airborne", "tilt_deg", "rollover", "wall_contact_count", "session_tick_us",
	])
	for state_name in Vehicle.STATE_LAYOUT:
		names.append("state_" + str(state_name))
	for channel in Session.DAMAGE_CHANNELS:
		names.append("damage_" + str(channel))
	return ",".join(names)


func _csv_row(tick: int, time_s: float, state: PackedFloat64Array, report: Dictionary,
		controls: Dictionary, phase: String, target_speed: float, acceleration: float,
		path_error: float, path_progress: float, coverage: float, feature_id: String,
		wheel_contacts: int, hull_contacts: int, airborne: bool, tilt_deg: float,
		rolled_over: bool, wall_contacts: int, tick_cost_us: float) -> String:
	var columns := PackedStringArray([
		str(tick), _f(time_s), _csv(phase), _f(float(controls.throttle)), _f(float(controls.steering)),
		_f(float(controls.brake)), _f(target_speed), _f(float(report.speed_m_per_s)), _f(acceleration),
		_f(state[Vehicle.POS]), _f(state[Vehicle.POS + 1]), _f(state[Vehicle.POS + 2]),
		_f(path_error), _f(path_progress), _f(coverage), _csv(feature_id), str(wheel_contacts),
		str(hull_contacts), str(not airborne), str(airborne), _f(tilt_deg), str(rolled_over),
		str(wall_contacts), _f(tick_cost_us),
	])
	for value in state:
		columns.append(_f(float(value)))
	for channel in Session.DAMAGE_CHANNELS:
		columns.append(_f(float(report.damage[channel])))
	return ",".join(columns)


func _write_results(run_result: Dictionary, vehicle_result: Dictionary, course_result: Dictionary) -> Dictionary:
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot open output CSV (error %d): %s" % [FileAccess.get_open_error(), _output_path]}
	for row in run_result.rows:
		file.store_line(str(row))
	file.close()
	var costs: PackedFloat64Array = run_result.tick_costs_us
	var sorted_costs := costs.duplicate()
	sorted_costs.sort()
	var backend: Dictionary = Vehicle.backend_identity()
	var vehicle_identity: Dictionary = vehicle_result.identity.duplicate(true)
	var report := {
		"format": "openrc-rcv-drive-run",
		"version": 1,
		"scenario": _scenario,
		"pace": _pace,
		"controller": "openrc-speed-aware-route-driver-v1-" + _pace,
		"route_brake_control_limit": ROUTE_BRAKE_LIMIT,
		"vehicle_path": _vehicle_path if not _vehicle_path.is_empty() else VehicleData.DEFAULT_PATH,
		"vehicle_identity": vehicle_identity,
		"vehicle_source_sha256": vehicle_identity.get("sha256", ""),
		"course_identity": course_result.identity.duplicate(true),
		"backend_identity": backend.duplicate(true),
		"solver_version": Vehicle.SOLVER_VERSION,
		"damage": _session.damage_visual_state(),
		"damage_state": Array(_session.damage_snapshot()),
		"fixed_hz": FIXED_HZ,
		"max_seconds": _max_seconds,
		"complete": bool(run_result.complete),
		"lap_complete": _scenario == "circuit" and bool(run_result.complete),
		"failure_reason": str(run_result.failure_reason),
		"ticks": int(run_result.ticks),
		"sample_count": int(run_result.sample_count),
		"elapsed_sim_s": float(run_result.elapsed_sim_s),
		"max_speed_mps": float(run_result.max_speed_mps),
		"max_acceleration_mps2": float(run_result.max_acceleration_mps2),
		"min_acceleration_mps2": float(run_result.min_acceleration_mps2),
		"session_tick_cost_us": {
			"sample_count": sorted_costs.size(),
			"p50": _percentile(sorted_costs, 0.50),
			"p95": _percentile(sorted_costs, 0.95),
			"max": float(sorted_costs[sorted_costs.size() - 1]) if not sorted_costs.is_empty() else 0.0,
		},
		"path": {
			"progress_m": float(run_result.path_progress_m),
			"length_m": float(run_result.path_length_m),
			"fraction": float(run_result.lap_fraction),
			"returned_to_start": bool(run_result.returned_to_start),
			"max_error_m": float(run_result.max_path_error_m),
			"final_error_m": float(run_result.final_path_error_m),
			"min_track_coverage": float(run_result.min_track_coverage),
			"feature_ticks": run_result.feature_ticks,
		},
		"contact": {
			"grounded_ticks": int(run_result.grounded_ticks),
			"airborne_ticks": int(run_result.airborne_ticks),
			"rollover_ticks": int(run_result.rollover_ticks),
			"max_tilt_deg": float(run_result.max_tilt_deg),
			"max_wheel_contacts": int(run_result.max_wheel_contacts),
			"max_hull_contacts": int(run_result.max_hull_contacts),
			"max_wall_contacts": int(run_result.max_wall_contacts),
			"events": _session.event_tape_snapshot(),
		},
		"runway": {
			"acceleration_seconds": ACCELERATION_SECONDS,
			"brake_start_tick": int(run_result.brake_start_tick),
			"brake_start_speed_mps": float(run_result.brake_start_speed_mps),
			"braking_distance_m": float(run_result.braking_distance_m),
			"stop_tick": int(run_result.stop_tick),
		},
		"csv": {
			"path": _output_path,
			"sha256": FileAccess.get_sha256(_output_path),
			"rows": int(run_result.sample_count),
		},
	}
	var json_file := FileAccess.open(_json_path(), FileAccess.WRITE)
	if json_file == null:
		return {"ok": false, "error": "cannot open output JSON (error %d): %s" % [FileAccess.get_open_error(), _json_path()]}
	json_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	json_file.close()
	return {"ok": true}


func _percentile(sorted_values: PackedFloat64Array, fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := int(ceil(float(sorted_values.size() - 1) * fraction))
	return float(sorted_values[clampi(index, 0, sorted_values.size() - 1)])


func _count_set(value: Variant) -> int:
	var count := 0
	if typeof(value) == TYPE_PACKED_BYTE_ARRAY:
		for item in value:
			if int(item) != 0:
				count += 1
	return count


func _json_path() -> String:
	return _output_path.get_basename() + ".json"


func _csv(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\""


func _f(value: float) -> String:
	return "%.9f" % value


func _finite_number(value: String) -> bool:
	var parsed := value.to_float()
	return is_finite(parsed) and not value.strip_edges().is_empty()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
