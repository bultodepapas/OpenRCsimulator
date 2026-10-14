extends SceneTree

const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
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
	_test_shifted_field(field_result, built)
	_test_session(field_result, course)
	_test_lake(field_result)
	print("RCV airfield course: %d failed" % failures)
	quit(1 if failures > 0 else 0)


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
	session.free()


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


func _check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
