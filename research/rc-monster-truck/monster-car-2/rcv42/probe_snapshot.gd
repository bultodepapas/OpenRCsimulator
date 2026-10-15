## Isolated cost/equivalence probe for physics-owned road-sample snapshots.
## Run manually from app with --output=<absolute-json-path>; never add to app/test.sh.
extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const VEHICLE_ID := "monster-car-2"
const BASE_KEYS := ["height_m", "normal_ned", "mu", "rolling", "surface_id"]
const WET_KEYS := ["wet_zone", "water_height_m", "water_depth_m", "mud_fraction"]
const WARMUP_COPIES := 2000
const COPIES_PER_ROUND := 10000
const ROUNDS := 5

var _output_path := ""
var _failures: Array[String] = []
var _bench_sink := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output_path = argument.trim_prefix("--output=")
	if _output_path.is_empty():
		push_error("--output=<absolute-json-path> is required")
		quit(1)
		return

	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from()
	if not bool(field_result.get("ok", false)) or not bool(lake_result.get("ok", false)):
		_fail("default field or lake did not load")
		_write_report({"format": "openrc-rcv42-road-snapshot-probe-v1", "failures": _failures, "complete": false})
		quit(1)
		return
	var session = Session.new()
	if not session.prepare_airfield(field_result, {}, lake_result.get("lake", {}), VEHICLE_ID):
		_fail("Monster Car 2 did not prepare on the production airfield: " + str(session.load_error))
		_write_report({"format": "openrc-rcv42-road-snapshot-probe-v1", "failures": _failures, "complete": false})
		session.free()
		quit(1)
		return
	var course: Dictionary = session.course_snapshot()
	var source_samples := _course_samples(course)
	if source_samples.size() != 4:
		_fail("production course did not provide track, wall, and wet samples")
	if not _failures.is_empty():
		_write_report({"format": "openrc-rcv42-road-snapshot-probe-v1", "failures": _failures, "complete": false})
		session.free()
		quit(1)
		return

	var all_samples: Array[Dictionary] = source_samples.duplicate()
	all_samples.append_array(_generic_samples())
	var cases: Array[Dictionary] = []
	for entry: Dictionary in all_samples:
		var sample: Dictionary = entry.sample
		for include_center_walls in [false, true]:
			cases.append(_check_projection(str(entry.name), sample, include_center_walls))
	var center_benchmark := _benchmark(source_samples, true)
	var noncenter_benchmark := _benchmark(source_samples, false)
	var backend_identity: Dictionary = VehicleDynamics.backend_identity()
	var complete := _failures.is_empty()
	var report := {
		"format": "openrc-rcv42-road-snapshot-probe-v1",
		"engine": Engine.get_version_info().get("string", ""),
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"vehicle_id": VEHICLE_ID,
		"course_identity": session.identities_snapshot().get("course", {}),
		"backend_identity": backend_identity,
		"native_backend_selected": str(backend_identity.get("backend", "")) == VehicleDynamics.BACKEND_NATIVE,
		"sample_inventory": _sample_inventory(source_samples),
		"projection_case_count": cases.size(),
		"projection_cases": cases,
		"benchmark": {
			"scope": "copy-only; full deep duplicate(true) versus selected-field projection; real AirfieldCourse samples cycled",
			"warmup_copies_each": WARMUP_COPIES,
			"copies_per_round_each": COPIES_PER_ROUND,
			"rounds": ROUNDS,
			"order": ["baseline,candidate", "candidate,baseline", "baseline,candidate", "candidate,baseline", "baseline,candidate"],
			"center_metadata": center_benchmark,
			"noncenter_metadata": noncenter_benchmark,
			"sink": _bench_sink,
		},
		"source_sha256": {
			"field_data": FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
			"lake_loader": FileAccess.get_sha256("res://data/lake_loader.gd"),
			"lake_data": FileAccess.get_sha256(LakeLoader.DEFAULT_PATH),
			"session": FileAccess.get_sha256("res://sim/ground_vehicle/session.gd"),
			"vehicle_dynamics": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_dynamics.gd"),
			"airfield_course": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_course.gd"),
			"airfield_track": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_track.gd"),
			"environment": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_environment.gd"),
			"harness": FileAccess.get_sha256(get_script().resource_path),
		},
		"failures": _failures,
		"complete": complete,
	}
	_write_report(report)
	session.free()
	quit(0 if complete else 1)


func _course_samples(course: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var track: Dictionary = course.get("track", {})
	var start: Dictionary = {}
	for spawn_value: Variant in track.get("spawns", []):
		if typeof(spawn_value) == TYPE_DICTIONARY and str(spawn_value.get("id", "")) == "track_start":
			start = spawn_value
			break
	if start.is_empty():
		_fail("course track_start spawn is missing")
		return result
	result.append({"name": "track_start", "sample": AirfieldCourse.sample(course,
		float(start.north_m), float(start.east_m))})

	var walls: Array = track.get("walls", [])
	if walls.is_empty():
		_fail("course track has no wall fixture")
		return result
	var wall: Dictionary = walls[0]
	var wall_north := (float(wall.north_min_m) + float(wall.north_max_m)) * 0.5
	var wall_east := (float(wall.east_min_m) + float(wall.east_max_m)) * 0.5
	var wall_sample: Dictionary = AirfieldCourse.sample(course, wall_north, wall_east)
	if typeof(wall_sample.get("walls")) != TYPE_ARRAY or wall_sample.walls.is_empty():
		_fail("wall-center sample did not retain its nearby wall")
	result.append({"name": "wall_center", "sample": wall_sample})

	var wet_sample: Dictionary = AirfieldCourse.sample(course, 138.0, 125.0)
	if not bool(wet_sample.get("wet_zone", false)) or float(wet_sample.get("water_depth_m", 0.0)) <= 0.0:
		_fail("lake entry sample did not resolve to positive-depth wet metadata")
	result.append({"name": "wet_entry", "sample": wet_sample})
	result.append({"name": "dry_track", "sample": AirfieldCourse.sample(course, 145.5, 125.0)})
	return result


func _generic_samples() -> Array[Dictionary]:
	return [
		{"name": "nested_surface_id", "sample": {
			"height_m": 0.25, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
			"mu": 0.7, "rolling": 2.5, "surface_id": {"label": "fixture", "tags": ["a", {"b": 2,
				"packed": PackedFloat64Array([4.0, 5.0])}]},
			"feature_ids": ["unused"], "walls": [{"id": "fixture_wall", "nested": {"values": [1, 2]}}],
		}},
		{"name": "malformed_normal", "sample": {
			"height_m": 1, "normal_ned": [0.0, {"bad": ["nested"]}], "mu": 0.7,
			"rolling": 2.5, "surface_id": ["raw", {"nested": true}],
			"walls": [{"id": "bad_wall", "bounds": {"north": [1, 2]}}],
		}},
		{"name": "malformed_wet_fields", "sample": {
			"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
			"mu": 0.5, "rolling": 4.5, "surface_id": "mud",
			"wet_zone": true, "water_height_m": {"bad": [3]},
			"water_depth_m": ["invalid"], "mud_fraction": {"nested": true},
			"walls": [{"id": "wet_wall", "nested": [1, {"x": 2}]}],
		}},
	]


func _check_projection(label: String, raw: Dictionary, include_center_walls: bool) -> Dictionary:
	var expected := _expected_projection(raw, include_center_walls)
	var actual := _project_physics_sample(raw, include_center_walls)
	var exact := var_to_bytes(expected) == var_to_bytes(actual)
	if not exact:
		_fail("projection bytes differ from filtered deep copy: %s center=%s" % [label, str(include_center_walls)])
	var mutable_source: Dictionary = raw.duplicate(true)
	var detached_expected := _expected_projection(mutable_source, include_center_walls)
	var detached_actual := _project_physics_sample(mutable_source, include_center_walls)
	_mutate_callback_owned_sample(mutable_source)
	var detached := var_to_bytes(detached_expected) == var_to_bytes(detached_actual)
	if not detached:
		_fail("projection aliased callback-owned mutable values: %s center=%s" % [label, str(include_center_walls)])
	return {
		"name": label,
		"include_center_walls": include_center_walls,
		"raw_keys": raw.keys(),
		"projected_keys": actual.keys(),
		"exact_filtered_copy": exact,
		"detached_after_source_mutation": detached,
		"expected_sha256": _sha256_variant(expected),
		"actual_sha256": _sha256_variant(actual),
	}


func _expected_projection(raw: Dictionary, include_center_walls: bool) -> Dictionary:
	var expected: Dictionary = raw.duplicate(true)
	for key: Variant in expected.keys():
		if not _keep_key(str(key), include_center_walls):
			expected.erase(key)
	return expected


func _project_physics_sample(raw: Dictionary, include_center_walls: bool) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in raw.keys():
		var key_string := str(key)
		if not _keep_key(key_string, include_center_walls):
			continue
		var value: Variant = raw[key]
		if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY]:
			value = value.duplicate(true)
		elif typeof(value) == TYPE_PACKED_FLOAT64_ARRAY:
			value = value.duplicate()
		result[key] = value
	return result


func _keep_key(key: String, include_center_walls: bool) -> bool:
	return key in BASE_KEYS or key in WET_KEYS or (include_center_walls and key == "walls")


func _mutate_callback_owned_sample(raw: Dictionary) -> void:
	for key in ["height_m", "mu", "rolling", "surface_id", "wet_zone", "water_height_m", "water_depth_m", "mud_fraction"]:
		if raw.has(key):
			raw[key] = _mutate_nested(raw[key])
	if raw.has("normal_ned"):
		raw.normal_ned = _mutate_nested(raw.normal_ned)
	if raw.has("walls"):
		raw.walls = _mutate_nested(raw.walls)


func _mutate_nested(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL:
			return not bool(value)
		TYPE_INT, TYPE_FLOAT:
			return float(value) + 1.0
		TYPE_STRING:
			return str(value) + "_changed"
		TYPE_ARRAY:
			for index in value.size():
				value[index] = _mutate_nested(value[index])
			value.append("changed")
			return value
		TYPE_DICTIONARY:
			for key: Variant in value.keys():
				value[key] = _mutate_nested(value[key])
			value["probe_mutation"] = ["changed"]
			return value
		TYPE_PACKED_FLOAT64_ARRAY:
			if value.size() > 0:
				value[0] = float(value[0]) + 1.0
			return value
	return value


func _benchmark(samples: Array[Dictionary], include_center_walls: bool) -> Dictionary:
	for _index in 2:
		_time_copies(samples, include_center_walls, false, WARMUP_COPIES)
		_time_copies(samples, include_center_walls, true, WARMUP_COPIES)
	var baseline_times := PackedInt64Array()
	var candidate_times := PackedInt64Array()
	for round_index in ROUNDS:
		if round_index % 2 == 0:
			baseline_times.append(_time_copies(samples, include_center_walls, false, COPIES_PER_ROUND))
			candidate_times.append(_time_copies(samples, include_center_walls, true, COPIES_PER_ROUND))
		else:
			candidate_times.append(_time_copies(samples, include_center_walls, true, COPIES_PER_ROUND))
			baseline_times.append(_time_copies(samples, include_center_walls, false, COPIES_PER_ROUND))
	return {
		"include_center_walls": include_center_walls,
		"baseline_full_deep_copy_us": baseline_times,
		"candidate_projection_us": candidate_times,
	}


func _time_copies(samples: Array[Dictionary], include_center_walls: bool,
		candidate: bool, count: int) -> int:
	var started := Time.get_ticks_usec()
	for index in count:
		var raw: Dictionary = samples[index % samples.size()].sample
		var copied: Dictionary = _project_physics_sample(raw, include_center_walls) \
			if candidate else raw.duplicate(true)
		_bench_sink += int(float(copied.get("height_m", 0.0)) * 1000.0) + copied.size()
	return Time.get_ticks_usec() - started


func _sample_inventory(samples: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in samples:
		var sample: Dictionary = entry.sample
		var walls_value: Variant = sample.get("walls", [])
		result.append({"name": str(entry.name), "keys": sample.keys(),
			"wall_count": walls_value.size() if typeof(walls_value) == TYPE_ARRAY else -1,
			"wet_zone": sample.get("wet_zone", false),
			"water_depth_m": sample.get("water_depth_m", null)})
	return result


func _sha256_variant(value: Variant) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(var_to_bytes(value)) != OK:
		return ""
	return context.finish().hex_encode()


func _write_report(report: Dictionary) -> void:
	if _output_path.is_empty():
		return
	var output := FileAccess.open(_output_path, FileAccess.WRITE)
	if output == null:
		_fail("cannot open output path (error %d)" % FileAccess.get_open_error())
		return
	output.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	output.close()
	print(JSON.stringify({"ok": report.get("complete", false), "output": _output_path,
		"projection_cases": report.get("projection_case_count", 0), "failures": _failures}, "  ", true, true))


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)
