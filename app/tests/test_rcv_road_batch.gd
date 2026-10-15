## RCV-42 contract checks for VehicleDynamics' native road-sampling adapter.
## Run with Godot 4.7 using --path app --script res://tests/test_rcv_road_batch.gd.
extends SceneTree

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

var _checks := 0
var _failures := 0
var _calls := 0
var _response: Variant = null
var _responses: Array = []
var _seen: Array[PackedFloat64Array] = []
var _reused_surface: Dictionary = {}
var _reused_normal := PackedFloat64Array([0.0, 0.0, -1.0])
var _coordinates_to_mutate := PackedFloat64Array()


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not condition:
		_failures += 1



func _surface(height: float = 0.0, mu: float = 0.7, rolling: float = 0.04, normal: Variant = null) -> Dictionary:
	if normal == null:
		normal = PackedFloat64Array([0.0, 0.0, -1.0])
	return {"height_m": height, "normal_ned": normal, "mu": mu, "rolling": rolling}


func _constant_road(_north_m: float, _east_m: float) -> Variant:
	_calls += 1
	return _response


func _ordered_road(north_m: float, east_m: float) -> Dictionary:
	_calls += 1
	_seen.append(PackedFloat64Array([north_m, east_m]))
	if _calls == 1:
		var zero := 0.0
		return _surface(-zero, -zero, 0.125, PackedFloat64Array([0.0, -zero, -1.0]))
	return _surface(1.25, 0.25, 0.05, PackedFloat64Array([0.6, 0.0, -0.8]))


func _sequence_road(north_m: float, east_m: float) -> Variant:
	_calls += 1
	_seen.append(PackedFloat64Array([north_m, east_m]))
	if _calls <= _responses.size():
		return _responses[_calls - 1]
	return _surface(north_m + east_m)


func _reused_road(_north_m: float, _east_m: float) -> Dictionary:
	_calls += 1
	var x := float(_calls) * 0.1
	_reused_normal[0] = x
	_reused_normal[1] = 0.0
	_reused_normal[2] = -sqrt(1.0 - x * x)
	_reused_surface["height_m"] = float(_calls) * 3.0
	_reused_surface["normal_ned"] = _reused_normal
	_reused_surface["mu"] = float(_calls) * 0.2
	_reused_surface["rolling"] = float(_calls) * 0.03
	return _reused_surface


func _mutating_road(north_m: float, east_m: float) -> Dictionary:
	_calls += 1
	if _calls == 1:
		_coordinates_to_mutate[2] = NAN
	return _surface(north_m + east_m)


func _failed_result(label: String, result: Dictionary, expected_error: String) -> void:
	var samples: Variant = result.get("samples")
	var packed_samples := PackedFloat64Array()
	if typeof(samples) == TYPE_PACKED_FLOAT64_ARRAY:
		packed_samples = samples
	var empty_buffer := typeof(samples) == TYPE_PACKED_FLOAT64_ARRAY and packed_samples.is_empty()
	var ok: bool = result.get("ok", true) == false
	var error := str(result.get("error", ""))
	_check(label, ok and error == expected_error and empty_buffer,
		"ok=%s error=%s samples_type=%s samples_size=%s" % [str(ok), error, type_string(typeof(samples)), str(samples.size() if typeof(samples) == TYPE_PACKED_FLOAT64_ARRAY else -1)])


func _expect_surface_error(label: String, response: Variant, expected_error: String) -> void:
	_response = response
	_calls = 0
	var result: Dictionary = Vehicle._sample_road_batch(Callable(self, "_constant_road"), PackedFloat64Array([4.0, -2.0]))
	_failed_result(label, result, expected_error)
	_check(label + " invokes one callback", _calls == 1, "calls %d" % _calls)


func _test_valid_and_empty_batches() -> void:
	_calls = 0
	_seen.clear()
	var coords := PackedFloat64Array([1.0, -2.0, 3.0, 4.0])
	var result: Dictionary = Vehicle._sample_road_batch(Callable(self, "_ordered_road"), coords)
	var zero := 0.0
	var expected := PackedFloat64Array([
		-zero, 0.0, -zero, -1.0, -zero, 0.125,
		1.25, 0.6, 0.0, -0.8, 0.25, 0.05,
	])
	var actual: Variant = result.get("samples")
	var actual_samples := PackedFloat64Array()
	if typeof(actual) == TYPE_PACKED_FLOAT64_ARRAY:
		actual_samples = actual
	var exact_bytes := typeof(actual) == TYPE_PACKED_FLOAT64_ARRAY and actual_samples.to_byte_array() == expected.to_byte_array()
	_check("signed-zero fixture carries the negative float64 sign bit", expected.to_byte_array()[7] == 128)
	_check("two valid coordinates pack six exact float64 values each, including signed zero",
		bool(result.get("ok", false)) and str(result.get("error", "!")) == "" and exact_bytes,
		"calls %d values %d" % [_calls, actual.size() if typeof(actual) == TYPE_PACKED_FLOAT64_ARRAY else -1])
	_check("valid batch preserves callback coordinate order",
		_seen.size() == 2 and _seen[0] == PackedFloat64Array([1.0, -2.0]) and _seen[1] == PackedFloat64Array([3.0, 4.0]))

	_calls = 0
	var empty: Dictionary = Vehicle._sample_road_batch(Callable(self, "_constant_road"), PackedFloat64Array())
	var empty_samples: Variant = empty.get("samples")
	var empty_packed := PackedFloat64Array()
	if typeof(empty_samples) == TYPE_PACKED_FLOAT64_ARRAY:
		empty_packed = empty_samples
	_check("zero-length batch succeeds empty without invoking the road", bool(empty.get("ok", false))
		and typeof(empty_samples) == TYPE_PACKED_FLOAT64_ARRAY and empty_packed.is_empty() and _calls == 0)
	_failed_result("invalid Callable is rejected even for an empty batch",
		Vehicle._sample_road_batch(Callable(), PackedFloat64Array()), "Native road batch request is malformed")
	_check("invalid Callable makes no road calls", _calls == 0)


func _test_malformed_requests() -> void:
	_calls = 0
	_failed_result("odd coordinate count is rejected before callback",
		Vehicle._sample_road_batch(Callable(self, "_constant_road"), PackedFloat64Array([1.0, 2.0, 3.0])),
		"Native road batch request is malformed")
	_failed_result("non-finite coordinate is rejected before callback",
		Vehicle._sample_road_batch(Callable(self, "_constant_road"), PackedFloat64Array([1.0, INF])),
		"Native road batch request is malformed")
	_check("malformed coordinate buffers do not call the road", _calls == 0)


func _test_surface_validation() -> void:
	_expect_surface_error("non-Dictionary raw callback result", [1, 2], "Road callback must return a Dictionary")
	for field in ["height_m", "normal_ned", "mu", "rolling"]:
		var missing := _surface()
		missing.erase(field)
		_expect_surface_error("missing " + field + " is rejected", missing,
			"Road callback omitted height, normal, friction, or rolling resistance")
	_expect_surface_error("Array normal has the wrong type", _surface(0.0, 0.7, 0.04, [0.0, 0.0, -1.0]),
		"Road normal must be a PackedFloat64Array")
	_expect_surface_error("PackedFloat32Array normal has the wrong type",
		_surface(0.0, 0.7, 0.04, PackedFloat32Array([0.0, 0.0, -1.0])),
		"Road normal must be a PackedFloat64Array")
	_expect_surface_error("short normal is rejected", _surface(0.0, 0.7, 0.04, PackedFloat64Array([0.0, -1.0])),
		"Road normal must contain three finite NED values")
	_expect_surface_error("long normal is rejected", _surface(0.0, 0.7, 0.04, PackedFloat64Array([0.0, 0.0, -1.0, 0.0])),
		"Road normal must contain three finite NED values")
	_expect_surface_error("NaN normal component is rejected", _surface(0.0, 0.7, 0.04, PackedFloat64Array([NAN, 0.0, -1.0])),
		"Road normal must contain three finite NED values")
	_expect_surface_error("infinite normal component is rejected", _surface(0.0, 0.7, 0.04, PackedFloat64Array([0.0, INF, -1.0])),
		"Road normal must contain three finite NED values")
	_expect_surface_error("normal outside unit tolerance is rejected",
		_surface(0.0, 0.7, 0.04, PackedFloat64Array([0.0, 0.0, -0.999989])),
		"Road normal must be unit length")

	_response = _surface(0.0, 0.7, 0.04, PackedFloat64Array([0.0, 0.0, -0.999991]))
	var near_unit: Dictionary = Vehicle._sample_road_batch(Callable(self, "_constant_road"), PackedFloat64Array([0.0, 0.0]))
	_check("normal within unit-length tolerance is accepted", bool(near_unit.get("ok", false)))
	for field in ["height_m", "mu", "rolling"]:
		var nonfinite := _surface()
		nonfinite[field] = NAN
		_expect_surface_error("NaN " + field + " is rejected", nonfinite,
			"Road height/friction/rolling values must be finite and nonnegative where applicable")
		var infinite := _surface()
		infinite[field] = INF
		_expect_surface_error("infinite " + field + " is rejected", infinite,
			"Road height/friction/rolling values must be finite and nonnegative where applicable")
	for field in ["mu", "rolling"]:
		var negative := _surface()
		negative[field] = -0.001
		_expect_surface_error("negative " + field + " is rejected", negative,
			"Road height/friction/rolling values must be finite and nonnegative where applicable")


func _test_abort_and_reused_mutable_results() -> void:
	_calls = 0
	_seen.clear()
	_responses = [_surface(1.0), {"height_m": 2.0}]
	var aborted: Dictionary = Vehicle._sample_road_batch(Callable(self, "_sequence_road"),
		PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]))
	_failed_result("invalid second result aborts without returning a partial buffer", aborted,
		"Road callback omitted height, normal, friction, or rolling resistance")
	_check("batch aborts in order and never calls the third coordinate", _calls == 2 and _seen.size() == 2
		and _seen[0] == PackedFloat64Array([1.0, 2.0]) and _seen[1] == PackedFloat64Array([3.0, 4.0]),
		"calls %d" % _calls)

	_calls = 0
	_reused_surface = _surface()
	_reused_normal = PackedFloat64Array([0.0, 0.0, -1.0])
	var reused: Dictionary = Vehicle._sample_road_batch(Callable(self, "_reused_road"),
		PackedFloat64Array([10.0, 11.0, 20.0, 21.0, 30.0, 31.0]))
	var expected := PackedFloat64Array()
	for index in 3:
		var x := float(index + 1) * 0.1
		expected.append(float(index + 1) * 3.0)
		expected.append(x)
		expected.append(0.0)
		expected.append(-sqrt(1.0 - x * x))
		expected.append(float(index + 1) * 0.2)
		expected.append(float(index + 1) * 0.03)
	var actual: Variant = reused.get("samples")
	var actual_samples := PackedFloat64Array()
	if typeof(actual) == TYPE_PACKED_FLOAT64_ARRAY:
		actual_samples = actual
	_check("reused Dictionary and Packed normal produce independent per-query values",
		bool(reused.get("ok", false)) and typeof(actual) == TYPE_PACKED_FLOAT64_ARRAY
		and actual_samples.to_byte_array() == expected.to_byte_array() and _calls == 3,
		"calls %d values %d" % [_calls, actual.size() if typeof(actual) == TYPE_PACKED_FLOAT64_ARRAY else -1])

	_coordinates_to_mutate = PackedFloat64Array([1.0, 2.0, 3.0, 4.0])
	_calls = 0
	var mutated: Dictionary = Vehicle._sample_road_batch(Callable(self, "_mutating_road"), _coordinates_to_mutate)
	_failed_result("coordinates invalidated by callback are rechecked before the next query", mutated,
		"Invalid road sample request")
	_check("callback mutation stops before a second road call", _calls == 1, "calls %d" % _calls)


func _initialize() -> void:
	_test_valid_and_empty_batches()
	_test_malformed_requests()
	_test_surface_validation()
	_test_abort_and_reused_mutable_results()
	print("RCV-42 road batch contract: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
