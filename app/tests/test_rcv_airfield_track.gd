extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const GroundContact := preload("res://physics/ground_contact.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Session := preload("res://sim/ground_vehicle/session.gd")
const M := preload("res://physics/math3d.gd")
const FIXED_DT := 1.0 / 240.0
const LOOP_STRAIGHT_M := 24.0
const LOOP_ARC_M := PI * 6.0
const LOOP_LENGTH_M := 2.0 * LOOP_STRAIGHT_M + 2.0 * LOOP_ARC_M
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

var checks := 0
var failures := 0


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	_check("default airplane field loads for the track", bool(field_result.get("ok", false)), str(field_result.get("errors", [])))
	var track_result: Dictionary = Track.load_default()
	_check("default airfield track loads with a source digest", bool(track_result.get("ok", false))
		and str(track_result.get("sha256", "")).length() == 64)
	if not bool(field_result.get("ok", false)) or not bool(track_result.get("ok", false)):
		quit(1)
		return
	var built: Dictionary = AirfieldCourse.build(field_result)
	_check("validated airfield course includes the default track", bool(built.get("ok", false))
		and built.get("course", {}).has("track"), str(built.get("errors", [])))
	if not bool(built.get("ok", false)):
		quit(1)
		return
	var course: Dictionary = built.course
	var track: Dictionary = track_result.track
	print("RCV airfield track backend: ", Vehicle.backend_identity().get("backend", "unknown"))
	_test_loader_rejects_invalid_track(track)
	_test_track_geometry(course, track)
	_test_road_gradient(course)
	_test_runway_grid_unchanged(course)
	_test_custom_field_unchanged(field_result, built)
	_test_spawn_initialization(field_result, course)
	_test_wall_broadphase(course)
	_test_airfield_wall_impact(field_result)
	_test_tabletop_jump_and_landing(field_result)
	_test_closed_loop_bank_driving(field_result)
	_test_native_one_second_timing(field_result)
	print("RCV airfield track: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	print(("PASS: " if passed else "FAIL: ") + label + ("" if detail.is_empty() else "  " + detail))
	if not passed:
		failures += 1


func _test_loader_rejects_invalid_track(track: Dictionary) -> void:
	var wrong_format: Dictionary = track.duplicate(true)
	wrong_format["format"] = "openrc-airfield-track v999"
	var inverted_wall: Dictionary = track.duplicate(true)
	var walls: Array = inverted_wall["walls"]
	var first_wall: Dictionary = walls[0]
	first_wall["north_max_m"] = first_wall["north_min_m"]
	walls[0] = first_wall
	inverted_wall["walls"] = walls
	var duplicate_id: Dictionary = track.duplicate(true)
	walls = duplicate_id["walls"]
	first_wall = walls[0]
	var second_wall: Dictionary = walls[1]
	second_wall["id"] = first_wall["id"]
	walls[1] = second_wall
	duplicate_id["walls"] = walls
	var nine_walls: Dictionary = track.duplicate(true)
	walls = nine_walls["walls"]
	while walls.size() < 9:
		var extra: Dictionary = walls[0].duplicate(true)
		extra["id"] = "excess-%d" % walls.size()
		walls.append(extra)
	nine_walls["walls"] = walls
	_check("track loader validation rejects malformed format, inverted boxes, duplicate IDs, and >8 walls",
		not Track.valid({}) and not Track.valid(wrong_format) and not Track.valid(inverted_wall)
		and not Track.valid(duplicate_id) and not Track.valid(nine_walls))


func _test_track_geometry(course: Dictionary, track: Dictionary) -> void:
	_check("hairpin geometry is centered at N45/E0 with 6 m radius and 12 m half-straights",
		is_equal_approx(float(track.center_north_m), 45.0)
		and is_equal_approx(float(track.center_east_m), 0.0)
		and is_equal_approx(float(track.radius_m), 6.0)
		and is_equal_approx(float(track.half_straight_m), 12.0))
	var tabletop: Dictionary = AirfieldCourse.sample(course, 39.0, -4.0)
	var no_ramps: Dictionary = track.duplicate(true)
	no_ramps["ramps"] = []
	var tabletop_base: Dictionary = Track.sample(no_ramps, 39.0, -4.0)
	var tabletop_overlay: Dictionary = Track.sample(track, 39.0, -4.0)
	var ramp_height := float(tabletop_overlay.height_m) - float(tabletop_base.height_m)
	_check("south tabletop is a sampled raised feature at E=-4 m",
		str(tabletop.feature_id) == "tabletop" and float(tabletop.track_coverage) > 0.99
		and absf(ramp_height - float(track.ramps[0].height_m)) < 1.0e-10,
		"height %.3f m" % ramp_height)
	var no_rollers: Dictionary = track.duplicate(true)
	no_rollers["rollers"] = []
	var rollers_ok := true
	for east_m in [-4.0, 0.0, 4.0]:
		var sample: Dictionary = Track.sample(track, 51.0, east_m)
		var baseline: Dictionary = Track.sample(no_rollers, 51.0, east_m)
		var expected_id := "roller_1" if east_m == -4.0 else ("roller_2" if east_m == 0.0 else "roller_3")
		rollers_ok = rollers_ok and str(sample.feature_id) == expected_id \
			and absf(float(sample.height_m) - float(baseline.height_m) - 0.12) < 1.0e-10
	_check("three N51 rollers add 0.12 m at E=-4/0/+4 m", rollers_ok)
	var banked: Dictionary = Track.sample(track, 40.527864045, 16.0)
	var no_bank: Dictionary = track.duplicate(true)
	no_bank["bank_height_m"] = 0.0
	var flat_turn: Dictionary = Track.sample(no_bank, 40.527864045, 16.0)
	_check("outer eastern hairpin has a banked-turn rise", str(banked.feature_id) == "banked_turn"
		and float(banked.coverage) > 0.95 and float(banked.height_m) > float(flat_turn.height_m) + 0.05,
		"bank contribution %.3f m" % (float(banked.height_m) - float(flat_turn.height_m)))


func _test_road_gradient(course: Dictionary) -> void:
	var points: Array = [
		[39.31, -4.1], [39.2, -3.8], [50.91, -3.7], [51.11, 0.25],
		[50.8, 4.1], [42.0, 15.2], [47.4, -15.3],
	]
	var step := 0.001
	var max_north_error := 0.0
	var max_east_error := 0.0
	for point: Array in points:
		var north_m := float(point[0])
		var east_m := float(point[1])
		var sample: Dictionary = AirfieldCourse.sample(course, north_m, east_m)
		var north_plus: Dictionary = AirfieldCourse.sample(course, north_m + step, east_m)
		var north_minus: Dictionary = AirfieldCourse.sample(course, north_m - step, east_m)
		var east_plus: Dictionary = AirfieldCourse.sample(course, north_m, east_m + step)
		var east_minus: Dictionary = AirfieldCourse.sample(course, north_m, east_m - step)
		var normal: PackedFloat64Array = sample.normal_ned
		var exact_north := normal[0] / normal[2]
		var exact_east := normal[1] / normal[2]
		var finite_north := (float(north_plus.height_m) - float(north_minus.height_m)) / (2.0 * step)
		var finite_east := (float(east_plus.height_m) - float(east_minus.height_m)) / (2.0 * step)
		max_north_error = maxf(max_north_error, absf(exact_north - finite_north))
		max_east_error = maxf(max_east_error, absf(exact_east - finite_east))
	_check("road normal matches finite-difference terrain gradient away from seams",
		max_north_error < 1.0e-5 and max_east_error < 1.0e-5,
		"max slope errors N %.9f, E %.9f" % [max_north_error, max_east_error])


func _test_runway_grid_unchanged(course: Dictionary) -> void:
	var max_height_error := 0.0
	var max_normal_error := 0.0
	var max_mu_error := 0.0
	var max_rolling_error := 0.0
	var changed_samples := 0
	var unexpected_walls := 0
	for north_int in range(9, 22):
		for east_int in range(-50, 51):
			var north_m := float(north_int)
			var east_m := float(east_int)
			var terrain: PackedFloat64Array = GroundTerrain.sample_validated(north_m, east_m,
				course.surface_rects, course.lake)
			var sample: Dictionary = AirfieldCourse.sample(course, north_m, east_m)
			var offset := GroundContact.surface_at(course.surface_rects, north_m, east_m)
			if terrain.size() != 3 or offset < 0:
				changed_samples += 1
				continue
			var magnitude := M.sqrt_(terrain[1] * terrain[1] + terrain[2] * terrain[2] + 1.0)
			var expected_normal := PackedFloat64Array([-terrain[1] / magnitude,
				-terrain[2] / magnitude, -1.0 / magnitude])
			var row_index := int(offset / GroundTerrain.SURFACE_STRIDE)
			var expected_surface: Dictionary = course.surface_rows[row_index]
			var expected_mu: float = AirfieldCourse.DRY_PAVEMENT_MU * course.surface_rects[offset + 4]
			var expected_rolling: float = course.surface_rects[offset + 5]
			max_height_error = maxf(max_height_error, absf(float(sample.height_m) - terrain[0]))
			max_normal_error = maxf(max_normal_error, M.norm(M.sub(sample.normal_ned, expected_normal)))
			max_mu_error = maxf(max_mu_error, absf(float(sample.mu) - expected_mu))
			max_rolling_error = maxf(max_rolling_error, absf(float(sample.rolling) - expected_rolling))
			if float(sample.track_coverage) != 0.0 or not str(sample.feature_id).is_empty() \
					or str(sample.surface_id) != str(expected_surface.id):
				changed_samples += 1
			if not sample.walls.is_empty():
				unexpected_walls += 1
	var boundary: Dictionary = AirfieldCourse.sample(course, 21.0, -10.0)
	_check("track leaves every 1 m runway-grid sample N9–21/E−50–50 unchanged",
		changed_samples == 0 and unexpected_walls == 0 and max_height_error == 0.0
		and max_normal_error < 1.0e-14 and max_mu_error < 1.0e-14
		and max_rolling_error < 1.0e-14 and float(boundary.track_coverage) == 0.0
		and str(boundary.feature_id).is_empty(),
		"grid edits %d, walls %d, height error %.9f" % [changed_samples, unexpected_walls, max_height_error])


func _test_custom_field_unchanged(field_result: Dictionary, original: Dictionary) -> void:
	var shifted: Dictionary = field_result.field.duplicate(true)
	for surface: Dictionary in shifted.surfaces:
		surface.center_north = float(surface.center_north) + 120.0
		surface.center_east = float(surface.center_east) - 90.0
	var built: Dictionary = AirfieldCourse.build({"ok": true, "field": shifted})
	if not bool(built.get("ok", false)):
		_check("translated custom field course builds without a default-track match", false, str(built.get("errors", [])))
		return
	var sample: Dictionary = AirfieldCourse.sample(built.course, 45.0, 0.0)
	var expected: PackedFloat64Array = GroundTerrain.sample_validated(45.0, 0.0,
		built.course.surface_rects, built.course.lake)
	_check("translated/custom fields retain terrain only and receive no track or walls",
		not built.course.has("track") and float(sample.track_coverage) == 0.0
		and str(sample.feature_id).is_empty() and sample.walls.is_empty()
		and sample.height_m == expected[0]
		and str(built.identity.sha256) != str(original.identity.sha256))


func _test_spawn_initialization(field_result: Dictionary, course: Dictionary) -> void:
	var session = Session.new()
	var prepared := session.prepare_airfield(field_result)
	_check("airfield truck session prepares with track metadata", prepared, session.load_error)
	if not prepared:
		session.free()
		return
	var expected_ids := ["start", "runway_end", "track_start", "track_technical", "track_rollers"]
	var spawn_ids: Array[String] = []
	var every_spawn_initializes := true
	for spawn: Dictionary in course.spawns:
		spawn_ids.append(str(spawn.id))
		var reset_ok: bool = session.reset(str(spawn.id))
		var state: PackedFloat64Array = session.state_snapshot()
		var report: Dictionary = session.telemetry_snapshot()
		every_spawn_initializes = every_spawn_initializes and reset_ok and state.size() == Vehicle.STATE_SIZE \
			and is_finite(state[Vehicle.POS + 2]) and bool(report.get("ok", false)) \
			and is_finite(float(report.get("speed_m_per_s", NAN)))
		if reset_ok and state.size() == Vehicle.STATE_SIZE:
			every_spawn_initializes = every_spawn_initializes \
				and absf(state[Vehicle.POS] - float(spawn.north_m)) < 1.0e-10 \
				and absf(state[Vehicle.POS + 1] - float(spawn.east_m)) < 1.0e-10
	_check("all five named runway and dirt-track spawns initialize with finite supported states",
		spawn_ids == expected_ids and every_spawn_initializes,
		"spawns %s" % str(spawn_ids))
	session.free()


func _test_wall_broadphase(course: Dictionary) -> void:
	var slalom_1: Dictionary = AirfieldCourse.sample(course, 44.0, -6.0)
	var slalom_2: Dictionary = AirfieldCourse.sample(course, 45.0, 0.0)
	var outside: Dictionary = AirfieldCourse.sample(course, 100.0, 100.0)
	var id1 := ""
	var id2 := ""
	if not slalom_1.walls.is_empty():
		id1 = str(slalom_1.walls[0].id)
	if not slalom_2.walls.is_empty():
		id2 = str(slalom_2.walls[0].id)
	_check("road wall broadphase returns local slalom boxes and no outside boxes",
		id1 == "slalom_1" and id2 == "slalom_2" and outside.walls.is_empty()
		and slalom_1.walls.size() <= 8 and slalom_2.walls.size() <= 8)


func _test_airfield_wall_impact(field_result: Dictionary) -> void:
	var session = Session.new()
	if not session.prepare_airfield(field_result) or not session.reset("track_technical"):
		_check("actual airfield wall impact prepares at the technical spawn", false, session.load_error)
		session.free()
		return
	session.tick_once(NEUTRAL)
	session.resume()
	var found_contact := false
	var contact_detail := "no wall response within 1.67 s"
	for tick in 400:
		if not session.tick_once({"throttle": 0.8, "steering": 0.0, "brake": 0.0,
			"reverse": false, "armed": true}):
			break
		var state: PackedFloat64Array = session.state_snapshot()
		var report: Dictionary = session.telemetry_snapshot()
		if int(report.get("wall_contact_count", 0)) > 0:
			var sample: Dictionary = AirfieldCourse.sample(session.course_snapshot(), state[Vehicle.POS], state[Vehicle.POS + 1])
			var wheel_wall: PackedFloat64Array = report.get("wheel_wall_load_n", PackedFloat64Array())
			var total_wheel_wall := 0.0
			for value in wheel_wall:
				total_wheel_wall += value
			found_contact = float(report.get("wall_normal_load_n", 0.0)) > 0.0 \
				and total_wheel_wall > 0.0 and not sample.walls.is_empty()
			contact_detail = "N %.2f E %.2f, normal %.1f N" % [state[Vehicle.POS], state[Vehicle.POS + 1],
				float(report.get("wall_normal_load_n", 0.0))]
			break
	_check("native vehicle step collides with the authored slalom wall", found_contact, contact_detail)
	session.free()


func _test_tabletop_jump_and_landing(field_result: Dictionary) -> void:
	var session = Session.new()
	if not session.prepare_airfield(field_result) or not session.reset("track_start"):
		_check("tabletop jump session initializes at the south track spawn", false, session.load_error)
		session.free()
		return
	session.tick_once(NEUTRAL)
	var resumed: bool = session.resume()
	var saw_airborne := false
	var touchdown_tick := -1
	var airborne_ticks := 0
	var first_air_east := NAN
	var touchdown_east := NAN
	var max_gap_m := -INF
	var max_speed_mps := 0.0
	var landing_upright_cos := -1.0
	var landing_supported := false
	var landing_surface := ""
	var landing_coverage := 0.0
	var all_tires_off_during_flight := true
	var simulated_ticks := 0
	for tick in 1200:
		if touchdown_tick >= 0 and tick - touchdown_tick >= 120:
			break
		var throttle := 1.0 if tick < int(1.7 / FIXED_DT) and not saw_airborne else 0.0
		if not session.tick_once({"throttle": throttle, "steering": 0.0, "brake": 0.0,
			"reverse": false, "armed": true}):
			break
		simulated_ticks = tick + 1
		var state: PackedFloat64Array = session.state_snapshot()
		var report: Dictionary = session.telemetry_snapshot()
		var quaternion := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1],
			state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
		var sample: Dictionary = AirfieldCourse.sample(session.course_snapshot(), state[Vehicle.POS], state[Vehicle.POS + 1])
		var center_up_m := -state[Vehicle.POS + 2]
		max_gap_m = maxf(max_gap_m, center_up_m - float(sample.height_m))
		max_speed_mps = maxf(max_speed_mps, float(report.get("speed_m_per_s", 0.0)))
		if bool(report.get("airborne", false)):
			if not saw_airborne:
				first_air_east = state[Vehicle.POS + 1]
			saw_airborne = true
			airborne_ticks += 1
			all_tires_off_during_flight = all_tires_off_during_flight \
				and report.get("wheel_in_contact", PackedByteArray()).count(1) == 0 \
				and report.get("hull_in_contact", PackedByteArray()).count(1) == 0
		elif saw_airborne and touchdown_tick < 0:
			touchdown_tick = tick
			touchdown_east = state[Vehicle.POS + 1]
			var body_up: PackedFloat64Array = M.q_rotate(quaternion, PackedFloat64Array([0.0, 0.0, -1.0]))
			landing_upright_cos = -body_up[2]
			landing_supported = report.get("wheel_in_contact", PackedByteArray()).count(1) > 0 \
				or report.get("hull_in_contact", PackedByteArray()).count(1) > 0
			landing_surface = str(sample.surface_id)
			landing_coverage = float(sample.track_coverage)
	# One landing tick plus up to 0.5 s of coast for attitude/support to settle.
	var flight_s := float(airborne_ticks) * FIXED_DT
	var horizontal_flight_m := absf(float(touchdown_east) - float(first_air_east)) if is_finite(touchdown_east) else NAN
	_check("full-throttle south tabletop pass creates a measurable airborne hop",
		resumed and saw_airborne and airborne_ticks >= 20 and flight_s >= 0.08
		and all_tires_off_during_flight
		and max_gap_m > 0.215 and max_speed_mps < 8.0,
		"air %d ticks (%.3f s), E %.2f→%.2f, max gap %.3f m, peak speed %.2f m/s" % [airborne_ticks,
			flight_s, first_air_east, touchdown_east, max_gap_m, max_speed_mps])
	_check("tabletop hop lands on track with tire/hull support while upright",
		touchdown_tick >= 0 and landing_supported and landing_upright_cos > 0.90
		and is_finite(touchdown_east) and landing_coverage > 0.5
		and landing_surface in ["rc_dirt", "rough", "outside"],
		"land E %.2f, upright cos %.4f, support %s, feature %s, coverage %.2f, ticks %d" % [touchdown_east,
			landing_upright_cos, str(landing_supported), landing_surface, landing_coverage, simulated_ticks])
	session.free()


func _test_closed_loop_bank_driving(field_result: Dictionary) -> void:
	var session = Session.new()
	if not session.prepare_airfield(field_result) or not session.reset("track_rollers"):
		_check("closed-loop bank driving prepares at the north straight", false, session.load_error)
		session.free()
		return
	session.tick_once(NEUTRAL)
	session.resume()
	var waypoint_step_m := 0.5
	var waypoint_count := int(ceil(LOOP_LENGTH_M / waypoint_step_m))
	var waypoints := PackedFloat64Array()
	for index in waypoint_count:
		var point := _loop_point(float(index) * waypoint_step_m)
		waypoints.append(point[0])
		waypoints.append(point[1])
	var max_cross_track_m := 0.0
	var min_track_coverage := 1.0
	var max_speed_mps := 0.0
	var banked_ticks := 0
	var max_wall_contacts := 0
	var valid_ticks := true
	for _tick in 2300:
		var state: PackedFloat64Array = session.state_snapshot()
		var quaternion := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1],
			state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
		var yaw := float(M.q_to_euler(quaternion)[0])
		var nearest_index := 0
		var nearest_distance_squared := INF
		for offset in range(0, waypoints.size(), 2):
			var north_delta := waypoints[offset] - state[Vehicle.POS]
			var east_delta := waypoints[offset + 1] - state[Vehicle.POS + 1]
			var distance_squared := north_delta * north_delta + east_delta * east_delta
			if distance_squared < nearest_distance_squared:
				nearest_distance_squared = distance_squared
				nearest_index = int(offset / 2)
		max_cross_track_m = maxf(max_cross_track_m, M.sqrt_(nearest_distance_squared))
		var target_index := (nearest_index + 8) % waypoint_count
		var target_north_delta := waypoints[target_index * 2] - state[Vehicle.POS]
		var target_east_delta := waypoints[target_index * 2 + 1] - state[Vehicle.POS + 1]
		var target_yaw := M.atan2_(target_east_delta, target_north_delta)
		var heading_error := wrapf(target_yaw - yaw, -PI, PI)
		var report_before: Dictionary = session.telemetry_snapshot()
		var speed_before := float(report_before.get("speed_m_per_s", 0.0))
		var controls := {
			"throttle": 0.35 if speed_before < 2.3 else 0.0,
			"steering": clampf(heading_error * 1.8, -1.0, 1.0),
			"brake": 0.05 if speed_before > 3.0 else 0.0,
			"reverse": false,
			"armed": true,
		}
		if not session.tick_once(controls):
			valid_ticks = false
			break
		state = session.state_snapshot()
		var report: Dictionary = session.telemetry_snapshot()
		var road: Dictionary = AirfieldCourse.sample(session.course_snapshot(),
			state[Vehicle.POS], state[Vehicle.POS + 1])
		min_track_coverage = minf(min_track_coverage, float(road.track_coverage))
		max_speed_mps = maxf(max_speed_mps, float(report.speed_m_per_s))
		max_wall_contacts = maxi(max_wall_contacts, int(report.get("wall_contact_count", 0)))
		if str(road.feature_id) == "banked_turn":
			banked_ticks += 1
	var final_state: PackedFloat64Array = session.state_snapshot()
	var final_quaternion := PackedFloat64Array([final_state[Vehicle.ATT], final_state[Vehicle.ATT + 1],
		final_state[Vehicle.ATT + 2], final_state[Vehicle.ATT + 3]])
	var final_body_up: PackedFloat64Array = M.q_rotate(final_quaternion, PackedFloat64Array([0.0, 0.0, -1.0]))
	var upright_cos := -final_body_up[2]
	_check("closed-loop waypoints carry the truck through the banked western hairpin",
		valid_ticks and session.tick >= 2200 and banked_ticks >= 50 and min_track_coverage > 0.9
		and max_cross_track_m < 1.25 and max_speed_mps < 4.5 and max_wall_contacts == 0
		and upright_cos > 0.90 and is_finite(final_state[Vehicle.POS]),
		"banked %d ticks, path error %.2f m, coverage %.2f, speed %.2f m/s, upright %.3f" % [
			banked_ticks, max_cross_track_m, min_track_coverage, max_speed_mps, upright_cos])
	session.free()


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


func _test_native_one_second_timing(field_result: Dictionary) -> void:
	var session = Session.new()
	if not session.prepare_airfield(field_result):
		_check("one-second native timing run prepares", false, session.load_error)
		session.free()
		return
	session.reset("start")
	session.tick_once(NEUTRAL)
	session.resume()
	var start_usec := Time.get_ticks_usec()
	var valid := true
	for _tick in 240:
		valid = session.tick_once({"throttle": 0.2, "steering": 0.0, "brake": 0.0,
			"reverse": false, "armed": true}) and valid
	var elapsed_s := float(Time.get_ticks_usec() - start_usec) / 1_000_000.0
	_check("one simulated second completes with finite session state", valid
		and session.state_snapshot().size() == Vehicle.STATE_SIZE
		and is_finite(elapsed_s) and elapsed_s >= 0.0,
		"backend %s, 1 simulated s in %.3f wall s" % [Vehicle.backend_identity().get("backend", "unknown"), elapsed_s])
	session.free()

