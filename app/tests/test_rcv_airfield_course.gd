extends SceneTree

const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const Session := preload("res://sim/ground_vehicle/session.gd")
const M := preload("res://physics/math3d.gd")

var failures := 0


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	_check("default airplane airfield validates", bool(field_result.get("ok", false)))
	if not bool(field_result.get("ok", false)):
		quit(1)
		return
	var built: Dictionary = AirfieldCourse.build(field_result)
	_check("airfield bridge builds from normalized field bytes", bool(built.get("ok", false)))
	if not bool(built.get("ok", false)):
		push_error(str(built.get("errors", [])))
		quit(1)
		return
	var course: Dictionary = built.course
	_check("course identity is content-addressed", str(built.identity.get("sha256", "")).length() == 64)
	_test_spawns(course)
	_test_shared_surface_sampler(course)
	_test_surface_cache_invalidation(course)
	_test_shifted_field(field_result, built)
	_test_session(field_result, course)
	_test_lake(field_result)
	print("RCV airfield course: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _test_surface_cache_invalidation(course: Dictionary) -> void:
	var original := AirfieldCourse.sample(course, 15.0, 0.0)
	var modified_course: Dictionary = course.duplicate(true)
	var rects: PackedFloat64Array = modified_course.surface_rects
	var runway_offset := -1
	for row in course.surface_rows.size():
		if str(course.surface_rows[row].id) == "runway":
			runway_offset = row * GroundTerrain.SURFACE_STRIDE
	_check("cache test locates the runway row", runway_offset >= 0)
	if runway_offset < 0:
		return
	rects[runway_offset + 4] *= 0.5
	modified_course.surface_rects = rects
	var changed := AirfieldCourse.sample(modified_course, 15.0, 0.0)
	_check("same-length surface mutation changes friction despite cached validation",
		is_equal_approx(changed.mu, original.mu * 0.5))
	# Packed-array mutation must not modify the already validated cache entry.
	rects[runway_offset + 4] = NAN
	modified_course.surface_rects = rects
	var invalid := AirfieldCourse.sample(modified_course, 15.0, 0.0)
	_check("nonfinite mutation fails closed after a valid cached lookup",
		not is_finite(float(invalid.height_m)) and not is_finite(float(invalid.mu)))
	modified_course.surface_rects = PackedFloat64Array()
	var empty := AirfieldCourse.sample(modified_course, 15.0, 0.0)
	_check("empty surface table fails to resolve a road after cached lookup", not is_finite(float(empty.height_m)))
	_check("original complete sample restores after changed and invalid tables",
		AirfieldCourse.sample(course, 15.0, 0.0) == original)


func _test_spawns(course: Dictionary) -> void:
	var start: Dictionary = course.spawns[0]
	var end: Dictionary = course.spawns[1]
	_check("start is runway centerline at the aircraft field origin", start.id == "start"
		and is_equal_approx(start.north_m, 15.0) and is_equal_approx(start.east_m, 0.0)
		and is_equal_approx(start.heading_rad, PI * 0.5))
	_check("runway-end spawn keeps a two-metre runway margin", end.id == "runway_end"
		and is_equal_approx(end.north_m, 15.0) and is_equal_approx(end.east_m, 48.0)
		and is_equal_approx(end.heading_rad, PI * 1.5))
	_check("both spawn points use the runway surface", AirfieldCourse.sample(course, start.north_m, start.east_m).surface_id == "runway"
		and AirfieldCourse.sample(course, end.north_m, end.east_m).surface_id == "runway")


func _test_shared_surface_sampler(course: Dictionary) -> void:
	var north := 15.0
	var east := 0.0
	var road: Dictionary = AirfieldCourse.sample(course, north, east)
	var expected: PackedFloat64Array = GroundTerrain.sample_validated(north, east, course.surface_rects, course.lake)
	_check("airfield road height is the GroundTerrain result", road.height_m == expected[0])
	var expected_magnitude := M.sqrt_(expected[1] * expected[1] + expected[2] * expected[2] + 1.0)
	_check("airfield road normal uses the GroundTerrain gradient", road.normal_ned[0] == -expected[1] / expected_magnitude
		and road.normal_ned[1] == -expected[2] / expected_magnitude)
	_check("runway material uses dry-pavement truck estimates times field factors",
		is_equal_approx(road.mu, 0.85 * 0.8) and is_equal_approx(road.rolling, 2.5))
	var outside_runway: Dictionary = AirfieldCourse.sample(course, 15.0, 100.0)
	_check("rough surface retains its own field friction factors", outside_runway.surface_id == "rough"
		and is_equal_approx(outside_runway.mu, 0.85 * 0.7)
		and is_equal_approx(outside_runway.rolling, 7.5))


func _test_shifted_field(field_result: Dictionary, original: Dictionary) -> void:
	var shifted: Dictionary = field_result.field.duplicate(true)
	for surface: Dictionary in shifted.surfaces:
		surface.center_north = float(surface.center_north) + 120.0
		surface.center_east = float(surface.center_east) - 90.0
	var result: Dictionary = AirfieldCourse.build({"ok": true, "field": shifted})
	_check("custom field translation builds", bool(result.get("ok", false)))
	if not bool(result.get("ok", false)):
		return
	var start: Dictionary = result.course.spawns[0]
	_check("custom start follows the translated runway", is_equal_approx(start.north_m, 135.0)
		and is_equal_approx(start.east_m, -90.0))
	_check("field content changes the course identity", result.identity.sha256 != original.identity.sha256)


func _test_session(field_result: Dictionary, course: Dictionary) -> void:
	var session = Session.new()
	_check("session prepares directly on the airplane airfield", session.prepare_airfield(field_result))
	if session.prepared:
		var state: PackedFloat64Array = session.state_snapshot()
		_check("airfield initialization keeps float64 state at runway center", state.size() == 31
			and is_equal_approx(state[0], float(course.spawns[0].north_m))
			and is_equal_approx(state[1], float(course.spawns[0].east_m)))
		_check("airfield startup has finite terrain-supported CG altitude", is_finite(state[2]) and state[2] < 0.0)
		_check("airfield session identity matches the bridge", session.identities_snapshot().course.sha256.length() == 64)
		_check("runway-end reset uses the second airfield spawn", session.reset("runway_end")
			and is_equal_approx(session.state_snapshot()[1], float(course.spawns[1].east_m)))
		_test_checkpoint_identity_and_experiment(session, field_result)
	session.free()
	_test_drive_into_rough(field_result)


func _test_checkpoint_identity_and_experiment(session, field_result: Dictionary) -> void:
	var base_checkpoint: Dictionary = session.checkpoint()
	var json_checkpoint: Variant = JSON.parse_string(JSON.stringify(base_checkpoint, "", true, true))
	_check("airfield tick-zero checkpoint survives JSON byte roundtrip",
		typeof(json_checkpoint) == TYPE_DICTIONARY and session.can_restore_checkpoint(json_checkpoint))
	var before_roundtrip: PackedFloat64Array = session.state_snapshot()
	_check("airfield JSON checkpoint restores the exact supported float64 state",
		session.restore_checkpoint(json_checkpoint) and _arrays_equal(session.state_snapshot(), before_roundtrip))
	var shifted_field: Dictionary = field_result.field.duplicate(true)
	for surface: Dictionary in shifted_field.surfaces:
		surface.center_north = float(surface.center_north) + 120.0
		surface.center_east = float(surface.center_east) - 90.0
	var foreign_session = Session.new()
	var shifted_result := {"ok": true, "field": shifted_field}
	_check("second airfield session prepares on a different field identity",
		foreign_session.prepare_airfield(shifted_result))
	if foreign_session.prepared:
		var foreign_state: PackedFloat64Array = foreign_session.state_snapshot()
		_check("checkpoint from a different field is rejected atomically",
			not foreign_session.restore_checkpoint(base_checkpoint)
			and _arrays_equal(foreign_session.state_snapshot(), foreign_state))
	foreign_session.free()
	var baseline_model_identity: Dictionary = session.identities_snapshot().model
	_check("airfield suspension experiment prepares from immutable baseline",
		session.set_experiment({"spring_scale": 1.05, "damper_scale": 1.0,
			"gravity_scale": 1.0, "grip_scale": 1.0, "ballast_kg": 0.0,
			"ballast_height_m": 0.03}))
	_check("airfield experiment changes model identity and resets support",
		session.identities_snapshot().model != baseline_model_identity
		and session.tick == 0 and is_finite(session.state_snapshot()[2]))
	var experiment_checkpoint: Dictionary = session.checkpoint()
	var parsed_experiment_checkpoint: Variant = JSON.parse_string(JSON.stringify(experiment_checkpoint, "", true, true))
	var experiment_state: PackedFloat64Array = session.state_snapshot()
	_check("experiment checkpoint JSON roundtrip restores same airfield support",
		typeof(parsed_experiment_checkpoint) == TYPE_DICTIONARY
		and session.restore_checkpoint(parsed_experiment_checkpoint)
		and _arrays_equal(session.state_snapshot(), experiment_state))
	_check("experiment reset returns to a supported named runway spawn",
		session.reset("start") and is_finite(session.state_snapshot()[2])
		and is_equal_approx(session.state_snapshot()[0], 15.0))


func _test_drive_into_rough(field_result: Dictionary) -> void:
	var driver = Session.new()
	_check("driving session prepares on the airfield", driver.prepare_airfield(field_result))
	if not driver.prepared:
		driver.free()
		return
	_check("drive starts at runway end", driver.reset("runway_end"))
	var neutral := {"throttle": 0.0, "steering": 0.0, "brake": 0.0,
		"reverse": false, "armed": true}
	driver.tick_once(neutral)
	_check("airfield session resumes after neutral arming", driver.resume())
	for _tick in 2400:
		var state: PackedFloat64Array = driver.state_snapshot()
		var q := PackedFloat64Array([state[6], state[7], state[8], state[9]])
		var yaw := M.q_to_euler(q)[0]
		# This checks crossing the runway edge, not maximum-power cornering.
		# Approach north at a bounded speed through ordinary session controls.
		var steering := clampf(-yaw * 1.5, -0.5, 0.5)
		var throttle := clampf((2.0 - absf(state[3])) * 0.3, 0.0, 0.45)
		var controls := {"throttle": throttle, "steering": steering, "brake": 0.0,
			"reverse": false, "armed": true}
		if not driver.tick_once(controls) or driver.state_snapshot()[0] > 22.0:
			break
	var final_state: PackedFloat64Array = driver.state_snapshot()
	var road: Dictionary = AirfieldCourse.sample(driver.course_snapshot(), final_state[0], final_state[1])
	_check("short powered drive leaves runway and samples existing rough field", final_state[0] > 21.0
		and road.surface_id == "rough")
	driver.free()


func _arrays_equal(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _test_lake(field_result: Dictionary) -> void:
	var loaded: Dictionary = LakeLoader.load_from()
	if not bool(loaded.get("ok", false)):
		return
	var bridged: Dictionary = AirfieldCourse.build(field_result, {}, loaded.lake)
	_check("resolved lake joins the airfield terrain source", bool(bridged.get("ok", false)))
	if bool(bridged.get("ok", false)):
		var p: Dictionary = AirfieldCourse.sample(bridged.course, 15.0, 0.0)
		var expected: PackedFloat64Array = GroundTerrain.sample_validated(15.0, 0.0,
			bridged.course.surface_rects, loaded.lake)
		_check("lake-aware road still samples the shared GroundTerrain path", p.height_m == expected[0])
		var same := true
		# Both sides of the bank bounds and their finite-difference stencil must agree.
		for north in range(60, 164, 3):
			for east in range(80, 164, 3):
				var actual := AirfieldCourse.sample(bridged.course, float(north), float(east))
				var shared := GroundTerrain.sample_validated(float(north), float(east), bridged.course.surface_rects, loaded.lake)
				var magnitude := M.sqrt_(shared[1]*shared[1] + shared[2]*shared[2] + 1.0)
				same = same and actual.height_m == shared[0] and actual.normal_ned == PackedFloat64Array([-shared[1]/magnitude,-shared[2]/magnitude,-1.0/magnitude])
		_check("dry broadphase and native lake path preserve shared heights/normals over 980 points", same)
		var moved: Dictionary = loaded.lake.duplicate(true)
		var moved_bank: PackedFloat64Array = moved.bank_ne_m
		for index in range(0, moved_bank.size(), 2): moved_bank[index] += 200.0
		moved.bank_ne_m = moved_bank
		for sample_lake: Dictionary in [loaded.lake, moved, loaded.lake]:
			var polygon: PackedFloat64Array = sample_lake.bank_ne_m
			for offset in [-0.026, -0.025, 0.0, 0.025, 0.026]:
				var north: float = polygon[0] + offset
				var east: float = polygon[1] + offset
				same = same and AirfieldCourse._outside_lake_bank(sample_lake, north, east) == LakeSurface._outside_expanded_polygon_aabb(polygon, north, east, LakeSurface.SAMPLE_EPSILON_M)
		_check("bank bounds invalidate on changed contents and preserve stencil-edge decisions", same)


func _check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
