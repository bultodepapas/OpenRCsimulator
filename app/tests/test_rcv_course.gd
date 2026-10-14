extends SceneTree

const Course := preload("res://physics/ground_vehicle/course.gd")
const DATA_PATH := "res://data/ground_vehicle/practice.json"

var failures := 0


func _initialize() -> void:
	var loaded: Dictionary = Course.load_default()
	_check("default practice course loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var course: Dictionary = loaded.course
	_check("course identity binds exact file bytes", loaded.identity.format == "openrc-ground-course" and str(loaded.identity.sha256).length() == 64)
	_check("course is renderer-ready", course.surfaces.size() == 4 and course.features.size() == 4 and course.spawns.size() == 6)
	_test_surface_regions(course)
	_test_profiles(course)
	_test_spawn(course)
	_test_strict_rejection()
	quit(1 if failures > 0 else 0)


func _test_surface_regions(course: Dictionary) -> void:
	var start: Dictionary = Course.sample(course, 0.0, 0.0)
	_check("safe start is flat asphalt", start.in_bounds and start.surface_id == "asphalt" and is_zero_approx(start.height_m))
	_check("flat ground normal points Up in NED", _unit_up_ned(start.normal_ned))
	_check("gravel pad has a stable material ID", Course.sample(course, 0.0, -4.0).surface_id == "gravel")
	_check("grass pad has a stable material ID", Course.sample(course, 0.0, 4.0).surface_id == "grass")
	_check("slippery pad overrides asphalt by priority", Course.sample(course, 3.0, 0.0).surface_id == "slippery")
	var outside: Dictionary = Course.sample(course, 40.0, 0.0)
	_check("out-of-bounds road is flat deterministic fallback", not outside.in_bounds and is_zero_approx(outside.height_m) and outside.surface_id == "asphalt" and _unit_up_ned(outside.normal_ned))
	var repeated: Dictionary = Course.sample(course, 8.75, 0.3)
	var repeated_again: Dictionary = Course.sample(course, 8.75, 0.3)
	_check("road sampling is deterministic", repeated.height_m == repeated_again.height_m and repeated.normal_ned == repeated_again.normal_ned and repeated.feature_id == repeated_again.feature_id)


func _test_profiles(course: Dictionary) -> void:
	var tabletop: Dictionary = Course.sample(course, 8.5, 0.0)
	_check("tabletop renderer and physics share its peak height", is_equal_approx(tabletop.height_m, 0.12) and tabletop.feature_id == "tabletop-01")
	_check("tabletop top normal is level and unit length", _unit_up_ned(tabletop.normal_ned) and absf(tabletop.normal_ned[0]) < 1e-10 and absf(tabletop.normal_ned[1]) < 1e-10)
	var ramp: Dictionary = Course.sample(course, 7.4, 0.0)
	_check("tabletop approach is a smooth positive slope", ramp.height_m > 0.0 and ramp.normal_ned[0] < 0.0)
	var bump: Dictionary = Course.sample(course, 17.0, 0.0)
	_check("bump lane exposes a continuous analytic bump", is_equal_approx(bump.height_m, 0.04) and bump.feature_id == "bump-lane-01")
	var wedge: Dictionary = Course.sample(course, 13.0, -4.5)
	_check("wedge is sampled at its analytic center", is_equal_approx(wedge.height_m, 0.065) and wedge.feature_id == "wedge-01")
	var slope: Dictionary = Course.sample(course, 23.0, 0.0)
	_check("long slope shares its feature record with renderer", is_equal_approx(slope.height_m, 0.08) and slope.feature_id == "slope-01")
	var shoulder: Dictionary = Course.sample(course, 8.5, 2.1)
	_check("feature shoulder falls smoothly to the flat plane", shoulder.height_m > 0.0 and shoulder.height_m < 0.12)
	var just_outside: Dictionary = Course.sample(course, 8.5, 2.21)
	_check("feature has finite lateral boundary", is_zero_approx(just_outside.height_m))
	for point: Dictionary in [ramp, shoulder, bump, wedge, slope]:
		_check("sloped feature normal is finite unit upward", _unit_up_ned(point.normal_ned))


func _test_spawn(course: Dictionary) -> void:
	var spawn: Dictionary = course.spawns[0]
	_check("default spawn matches kernel pose packet", spawn.keys().size() == 5 and spawn.id == "start" and spawn.north_m == 0.0 and spawn.east_m == 0.0 and spawn.heading_rad == 0.0 and spawn.vehicle_up_m > 0.0)
	var spawn_ids: Array[String] = []
	for item: Dictionary in course.spawns:
		spawn_ids.append(str(item.id))
	var all_spawns_present := true
	for required_id in ["start", "gravel", "grass", "slippery", "bump_lane", "jump_start"]:
		all_spawns_present = all_spawns_present and spawn_ids.has(required_id)
	_check("practice and material test spawns are available", all_spawns_present)
	_check("checkpoints remain within the shared north-forward field", course.checkpoints.size() == 2 and course.checkpoints[0].north_m < course.checkpoints[1].north_m)


func _test_strict_rejection() -> void:
	var parser := JSON.new()
	var source: String = FileAccess.get_file_as_string(DATA_PATH)
	var parse_result: Error = parser.parse(source)
	_check("practice-course fixture parses as JSON", parse_result == OK, parser.get_error_message())
	if parse_result != OK or not parser.data is Dictionary:
		return
	var mutated: Dictionary = parser.data.duplicate(true)
	mutated.surfaces[0].mu.unit = "mph"
	var rejected: Dictionary = Course.validate(mutated)
	_check("invalid physical units reject course atomically", not bool(rejected.get("ok", true)) and rejected.get("course", {}).is_empty())
	var unknown: Dictionary = parser.data.duplicate(true)
	unknown.unmodeled_terrain = []
	rejected = Course.validate(unknown)
	_check("unknown course fields reject course atomically", not bool(rejected.get("ok", true)) and rejected.get("course", {}).is_empty())


func _unit_up_ned(normal: PackedFloat64Array) -> bool:
	if normal.size() != 3:
		return false
	var magnitude_squared: float = normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]
	return is_finite(magnitude_squared) and is_equal_approx(magnitude_squared, 1.0) and normal[2] < 0.0


func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		failures += 1
		push_error("FAIL: %s %s" % [label, detail])
	else:
		print("PASS: ", label)
