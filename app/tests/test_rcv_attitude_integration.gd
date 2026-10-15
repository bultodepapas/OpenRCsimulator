## RCV attitude-rate contract: normalized world mappings and high-spin RK step refinement.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Integrator := preload("res://physics/integrator.gd")

const POSITION := Vehicle.POS
const FORWARD := Vehicle.VEL
const EAST_VELOCITY := Vehicle.VEL + 1
const DOWN := Vehicle.POS + 2
const ATTITUDE := Vehicle.ATT
const RATE := Vehicle.RATE

var _failures := 0
var _checks := 0
var _road_calls := 0
var _road_coordinate_calls: Dictionary = {}
var _shared_road_surface: Dictionary = {}
var _shared_road_calls := 0
var _mutate_shared_walls := false


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not condition:
		_failures += 1


func _flat_road(_north_m: float, _east_m: float) -> Dictionary:
	return {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "attitude-test",
	}


func _controls() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}


func _counting_wet_road(north_m: float, east_m: float) -> Dictionary:
	_road_calls += 1
	var east_counts: Dictionary = _road_coordinate_calls.get(north_m, {})
	east_counts[east_m] = int(east_counts.get(east_m, 0)) + 1
	_road_coordinate_calls[north_m] = east_counts
	return {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"wet_zone": true,
		"water_height_m": 0.0,
		"water_depth_m": 0.0,
		"mud_fraction": 0.0,
		"surface_id": "cache-test",
	}


func _shared_mutable_wet_road(_north_m: float, _east_m: float) -> Dictionary:
	_shared_road_calls += 1
	# Deliberately return the same mutable object at every coordinate. The
	# evaluation cache must own a snapshot so later callback activity cannot
	# rewrite an earlier coordinate's sample.
	if _mutate_shared_walls and _shared_road_calls > 1:
		_shared_road_surface["walls"] = [{
			"id": "later-query-wall",
			"north_min_m": 0.30,
			"north_max_m": 0.40,
			"east_min_m": 0.18,
			"east_max_m": 0.28,
			"bottom_up_m": 19.9,
			"top_up_m": 20.1,
			"mu": 0.0,
		}]
	return _shared_road_surface


func _road_coordinate_stats() -> PackedInt32Array:
	var unique := 0
	var maximum_requests := 0
	for north_m in _road_coordinate_calls:
		var east_counts: Dictionary = _road_coordinate_calls[north_m]
		unique += east_counts.size()
		for count in east_counts.values():
			maximum_requests = maxi(maximum_requests, int(count))
	return PackedInt32Array([unique, maximum_requests])


func _max_abs_difference(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size():
		return INF
	var maximum := 0.0
	for index in a.size():
		maximum = maxf(maximum, absf(a[index] - b[index]))
	return maximum


func _spin_endpoint(state: PackedFloat64Array, model: Dictionary, road: Callable, dt: float, ticks: int) -> PackedFloat64Array:
	var result := state.duplicate()
	for _tick in ticks:
		result = Vehicle.step(result, model, _controls(), dt, road)
		if result.size() != Vehicle.STATE_SIZE:
			return PackedFloat64Array()
	return result


func _test_spatial_mappings(model: Dictionary, road: Callable) -> void:
	var initialized: Dictionary = Vehicle.initialize(model, road)
	if not bool(initialized.get("ok", false)) or initialized.get("state", PackedFloat64Array()).size() != Vehicle.STATE_SIZE:
		_check("spatial-mapping fixture initializes", false, str(initialized.get("error", "")))
		return
	var state: PackedFloat64Array = initialized["state"].duplicate()
	state[DOWN] = -20.0
	state[FORWARD] = 8.0
	state[EAST_VELOCITY] = 1.0
	var yaw_quaternion := M.q_from_euler(PI / 2.0, 0.0, 0.0)
	for component in 4:
		state[ATTITUDE + component] = yaw_quaternion[component] * 1.0005
	var normalized_q := M.q_normalized(yaw_quaternion)
	var expected_velocity := M.q_rotate(normalized_q, PackedFloat64Array([8.0, 1.0, 0.0]))
	var derivative := Vehicle.derivative(state, model, _controls(), road)
	var observed_rate := PackedFloat64Array()
	if derivative.size() == Vehicle.STATE_SIZE:
		observed_rate = PackedFloat64Array([derivative[POSITION], derivative[POSITION + 1], derivative[POSITION + 2]])
	_check("near-unit accepted attitude maps body velocity with normalized quaternion", derivative.size() == Vehicle.STATE_SIZE
		and _max_abs_difference(observed_rate, expected_velocity) < 1.0e-12,
		"position-rate error %.12f m/s" % _max_abs_difference(observed_rate, expected_velocity))
	var telemetry := Vehicle.telemetry(state, model, road)
	var expected_speed := sqrt(65.0)
	_check("telemetry speed is independent of tolerated quaternion norm drift", bool(telemetry.get("ok", false))
		and absf(float(telemetry.get("speed_m_per_s", NAN)) - expected_speed) < 1.0e-12,
		"speed %.12f, expected %.12f m/s" % [float(telemetry.get("speed_m_per_s", NAN)), expected_speed])


func _test_unit_input_spin_refinement(model: Dictionary, road: Callable) -> void:
	var initialized: Dictionary = Vehicle.initialize(model, road)
	if not bool(initialized.get("ok", false)) or initialized.get("state", PackedFloat64Array()).size() != Vehicle.STATE_SIZE:
		_check("spin-refinement fixture initializes", false, str(initialized.get("error", "")))
		return
	var state: PackedFloat64Array = initialized["state"].duplicate()
	state[DOWN] = -20.0
	state[FORWARD] = 12.0
	state[EAST_VELOCITY] = 0.5
	state[RATE + 2] = 12.0
	var initial_q_norm := sqrt(state[ATTITUDE] * state[ATTITUDE] + state[ATTITUDE + 1] * state[ATTITUDE + 1]
		+ state[ATTITUDE + 2] * state[ATTITUDE + 2] + state[ATTITUDE + 3] * state[ATTITUDE + 3])
	var derivative := Vehicle.derivative(state, model, _controls(), road)
	var initial_rate := PackedFloat64Array()
	if derivative.size() == Vehicle.STATE_SIZE:
		initial_rate = PackedFloat64Array([derivative[POSITION], derivative[POSITION + 1], derivative[POSITION + 2]])
	var exact_rate := PackedFloat64Array([12.0, 0.5, 0.0])
	_check("high-spin reference starts from a unit quaternion and exact world velocity", absf(initial_q_norm - 1.0) < 1.0e-14
		and derivative.size() == Vehicle.STATE_SIZE and _max_abs_difference(initial_rate, exact_rate) < 1.0e-12,
		"q norm %.15f, position-rate error %.12f m/s" % [initial_q_norm, _max_abs_difference(initial_rate, exact_rate)])
	if derivative.size() != Vehicle.STATE_SIZE:
		_check("unit-input RK stage derivative computes", false)
		return
	var stage_2 := Integrator.axpy(state, 0.5 / 30.0, derivative)
	var stage_q := PackedFloat64Array([stage_2[ATTITUDE], stage_2[ATTITUDE + 1], stage_2[ATTITUDE + 2], stage_2[ATTITUDE + 3]])
	var stage_q_norm := sqrt(stage_q[0] * stage_q[0] + stage_q[1] * stage_q[1] + stage_q[2] * stage_q[2] + stage_q[3] * stage_q[3])
	var stage_velocity := PackedFloat64Array([stage_2[FORWARD], stage_2[EAST_VELOCITY], stage_2[Vehicle.VEL + 2]])
	var expected_stage_rate := M.q_rotate(M.q_normalized(stage_q), stage_velocity)
	var stage_derivative := Vehicle._derivative_core(stage_2, model, _controls(), road)
	var observed_stage_rate := PackedFloat64Array()
	var observed_qdot := PackedFloat64Array()
	if stage_derivative.size() == Vehicle.STATE_SIZE:
		observed_stage_rate = PackedFloat64Array([stage_derivative[POSITION], stage_derivative[POSITION + 1], stage_derivative[POSITION + 2]])
		observed_qdot = PackedFloat64Array([
			stage_derivative[ATTITUDE], stage_derivative[ATTITUDE + 1], stage_derivative[ATTITUDE + 2], stage_derivative[ATTITUDE + 3],
		])
	var stage_rate := PackedFloat64Array([stage_2[RATE], stage_2[RATE + 1], stage_2[RATE + 2]])
	var expected_qdot := M.q_mul(stage_q, M.quat(0.0, stage_rate[0], stage_rate[1], stage_rate[2]))
	for component in 4:
		expected_qdot[component] *= 0.5
	_check("unit-input RK spin stage normalizes spatial mapping but preserves raw quaternion rate", not stage_derivative.is_empty()
		and absf(stage_q_norm - 1.0) > 1.0e-3
		and _max_abs_difference(observed_stage_rate, expected_stage_rate) < 1.0e-12
		and _max_abs_difference(observed_qdot, expected_qdot) < 1.0e-12,
		"stage q norm %.9f, map error %.12f m/s, qdot error %.12f" % [stage_q_norm,
		_max_abs_difference(observed_stage_rate, expected_stage_rate), _max_abs_difference(observed_qdot, expected_qdot)])
	var duration := 2.0
	var coarse := _spin_endpoint(state, model, road, 1.0 / 30.0, 60)
	var medium := _spin_endpoint(state, model, road, 1.0 / 60.0, 120)
	var fine := _spin_endpoint(state, model, road, 1.0 / 120.0, 240)
	var expected_position := PackedFloat64Array([
		state[POSITION] + 12.0 * duration,
		state[POSITION + 1] + 0.5 * duration,
		state[DOWN],
	])
	var coarse_position := coarse.slice(POSITION, POSITION + 3) if not coarse.is_empty() else PackedFloat64Array()
	var medium_position := medium.slice(POSITION, POSITION + 3) if not medium.is_empty() else PackedFloat64Array()
	var fine_position := fine.slice(POSITION, POSITION + 3) if not fine.is_empty() else PackedFloat64Array()
	var coarse_error := _max_abs_difference(coarse_position, expected_position)
	var medium_error := _max_abs_difference(medium_position, expected_position)
	var fine_error := _max_abs_difference(fine_position, expected_position)
	_check("12 rad/s free-flight translation stays accurate across RK step refinement", not coarse.is_empty()
		and not medium.is_empty() and not fine.is_empty() and coarse_error < 0.1
		and medium_error < coarse_error and fine_error < medium_error,
		"2 s position errors at dt=1/30, 1/60, 1/120: %.9f, %.9f, %.9f m" % [coarse_error, medium_error, fine_error])


func _test_exact_evaluation_road_cache(model: Dictionary, dry_road: Callable) -> void:
	var initialized: Dictionary = Vehicle.initialize(model, dry_road)
	if not bool(initialized.get("ok", false)) or initialized.get("state", PackedFloat64Array()).size() != Vehicle.STATE_SIZE:
		_check("road-cache fixture initializes", false, str(initialized.get("error", "")))
		return
	var state: PackedFloat64Array = initialized["state"].duplicate()
	state[DOWN] = -20.0
	_road_calls = 0
	_road_coordinate_calls.clear()
	var result: Dictionary = Vehicle._evaluate_active(state, model, _controls(), Callable(self, "_counting_wet_road"), false)
	var stats := _road_coordinate_stats()
	var hull_radii: PackedFloat64Array = model["hull_probe_radii_m"]
	var expected_uncached_requests: int = 1 + 8 + Vehicle.CORNER_COUNT + hull_radii.size()
	_check("wet evaluation reuses exact duplicate coordinates only within its callback scope", bool(result.get("ok", false))
		and _road_calls <= expected_uncached_requests - Vehicle.CORNER_COUNT
		and stats[0] == _road_calls and stats[1] == 1,
		"callback requests %d of %d possible, unique %d, max per exact coordinate %d" % [
			_road_calls, expected_uncached_requests, stats[0], stats[1],
		])

	_shared_road_surface = {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"wet_zone": true,
		"water_height_m": 0.0,
		"water_depth_m": 0.1,
		"mud_fraction": 0.0,
		"walls": [],
		"surface_id": "shared-mutable-cache-test",
	}
	_shared_road_calls = 0
	_mutate_shared_walls = true
	var mutable_road := Callable(self, "_shared_mutable_wet_road")
	var first_result: Dictionary = Vehicle._evaluate_active(state, model, _controls(), mutable_road, false)
	var first_environment: Dictionary = first_result.get("environment", {})
	var first_depth := float(first_environment.get("water_depth_m", NAN))
	var first_wall_contacts := int(first_result.get("wall_contact_count", -1))
	var calls_after_first := _shared_road_calls
	_shared_road_surface["water_depth_m"] = 0.6
	_shared_road_surface["walls"] = []
	_mutate_shared_walls = false
	var second_result: Dictionary = Vehicle._evaluate_active(state, model, _controls(), mutable_road, false)
	var second_environment: Dictionary = second_result.get("environment", {})
	var second_depth := float(second_environment.get("water_depth_m", NAN))
	_check("cached center sample is insulated from later callback mutation", bool(first_result.get("ok", false))
		and is_equal_approx(first_depth, 0.1) and first_wall_contacts == 0,
		"first depth %.3f m, first wall contacts %d" % [first_depth, first_wall_contacts])
	_check("same-pose next evaluation re-queries mutable road payload", bool(second_result.get("ok", false))
		and _shared_road_calls > calls_after_first and is_equal_approx(second_depth, 0.6),
		"calls %d→%d, water depth %.3f m" % [calls_after_first, _shared_road_calls, second_depth])


func _initialize() -> void:
	Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE)
	var loaded := Data.load_default()
	if not bool(loaded.get("ok", false)):
		push_error("vehicle model failed to load: " + str(loaded.get("errors", [])))
		quit(1)
		return
	var model: Dictionary = loaded["model"].duplicate(true)
	model["gravity_m_per_s2"] = 0.0
	var road := Callable(self, "_flat_road")
	_test_spatial_mappings(model, road)
	_test_unit_input_spin_refinement(model, road)
	_test_exact_evaluation_road_cache(model, road)
	print("RCV attitude integration: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
