extends SceneTree

const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const CourseData := preload("res://physics/ground_vehicle/course.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const ABS_TOLERANCE := 2.0e-8
const REL_TOLERANCE := 2.0e-10
const FLOAT_OUTPUTS := [
	"generalized_acceleration", "suspension_force_n", "wheel_load_n",
	"wheel_longitudinal_force_n", "wheel_lateral_force_n", "wheel_brake_torque_n_m",
	"wheel_slip_ratio", "wheel_slip_angle_rad", "wheel_slip_speed_m_per_s",
]
const BYTE_OUTPUTS := ["wheel_in_contact", "hull_in_contact"]

var _checks := 0
var _failures := 0
var _native: Object


func _initialize() -> void:
	GDExtensionManager.load_extension("res://openrc_ground_vehicle.gdextension")
	if not ClassDB.class_exists("OpenRCGroundVehicleNative"):
		_fail("GDExtension class failed to load")
		quit(1)
		return
	_native = ClassDB.instantiate("OpenRCGroundVehicleNative")
	var identity: Dictionary = _native.backend_identity()
	if identity.get("backend") != "native" or int(identity.get("abi_version", 0)) != 1 \
			or identity.get("backend_version") != "openrc-ground-vehicle-native-evaluate-v3" \
			or identity.get("solver_version") != "openrc-ground-vehicle-dynamics-rk4-v4" \
			or str(identity.get("source_sha256", "")).length() != 64 \
			or str(identity.get("toolchain_sha256", "")).length() != 64 \
			or str(identity.get("binary_sha256", "")).length() != 64:
		_fail("native backend identity/receipt is incomplete: " + str(identity))
		quit(1)
		return
	var vehicle_result: Dictionary = VehicleData.load_default()
	var course_result: Dictionary = CourseData.load_default()
	if not bool(vehicle_result.get("ok", false)) or not bool(course_result.get("ok", false)):
		_fail("fixture data load failed: %s / %s" % [str(vehicle_result.get("errors", [])), str(course_result.get("errors", []))])
		quit(1)
		return
	var model: Dictionary = vehicle_result.model
	var course: Dictionary = course_result.course
	var road: Callable = _make_single_road(course)
	var batch: Callable = _make_batch_road(course)
	var initialized: Dictionary = VehicleDynamics.initialize(model, road, 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		_fail("vehicle initialization failed: " + str(initialized.get("error", "")))
		quit(1)
		return
	var resting: PackedFloat64Array = initialized.state
	var scenarios: Array[Dictionary] = _scenarios(resting)
	for scenario: Dictionary in scenarios:
		_run_case(str(scenario.name), scenario.state, model, scenario.controls, road, batch, true, true)
		_run_case(str(scenario.name) + "_fixed", scenario.state, model, scenario.controls, road, batch, true, false)
	_run_case("rest_no_energy", resting, model, VehicleDynamics.DEFAULT_CONTROLS, road, batch, false, true)
	_run_randomized(resting, model, road, batch)
	_run_brake_distribution(resting, model, road, batch)
	_run_invalids(resting, model, batch)
	_run_external_generalized_loads(resting, scenarios[1], model, road, batch)
	_run_lake_terrain_parity()
	_run_evaluate_profile(scenarios[1], model, road, batch)
	if _failures == 0:
		print("OPENRC_NATIVE_PARITY_OK checks=%d" % _checks)
		quit(0)
	else:
		push_error("OPENRC_NATIVE_PARITY_FAILED checks=%d failures=%d" % [_checks, _failures])
		quit(1)


func _make_single_road(course: Dictionary) -> Callable:
	return func(north_m: float, east_m: float) -> Dictionary:
		return CourseData.sample(course, north_m, east_m)


func _make_batch_road(course: Dictionary) -> Callable:
	return func(coords: PackedFloat64Array) -> Dictionary:
		if coords.size() % 2 != 0:
			return {"ok": false, "error": "coordinate array must contain north/east pairs"}
		var samples := PackedFloat64Array()
		for index in range(0, coords.size(), 2):
			var sample: Dictionary = CourseData.sample(course, coords[index], coords[index + 1])
			var normal: PackedFloat64Array = sample.normal_ned
			samples.append(float(sample.height_m))
			samples.append(normal[0])
			samples.append(normal[1])
			samples.append(normal[2])
			samples.append(float(sample.mu))
			samples.append(float(sample.rolling))
		return {"ok": true, "error": "", "samples": samples}


func _scenarios(resting: PackedFloat64Array) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var base_controls := VehicleDynamics.DEFAULT_CONTROLS.duplicate(true)
	cases.append({"name": "flat_rest", "state": resting.duplicate(), "controls": base_controls})
	var drive := resting.duplicate()
	drive[3] = 0.8
	for corner in 4:
		drive[21 + corner] = 8.0
	cases.append({"name": "forward_drive_steer", "state": drive,
		"controls": {"throttle": 0.72, "steering": 0.63, "brake": 0.0, "reverse": false}})
	var brake := resting.duplicate()
	brake[3] = 1.8
	for corner in 4:
		brake[21 + corner] = 15.0
	cases.append({"name": "braking", "state": brake,
		"controls": {"throttle": 0.0, "steering": -0.31, "brake": 0.88, "reverse": false}})
	var reverse_state := resting.duplicate()
	reverse_state[3] = -0.45
	for corner in 4:
		reverse_state[21 + corner] = -4.5
	cases.append({"name": "reverse_drive", "state": reverse_state,
		"controls": {"throttle": 0.58, "steering": -0.44, "brake": 0.0, "reverse": true}})
	var bump := drive.duplicate()
	bump[0] = 8.5
	bump[3] = 2.3
	for corner in 4:
		bump[21 + corner] = 23.0
	cases.append({"name": "tabletop_bump", "state": bump,
		"controls": {"throttle": 0.52, "steering": 0.18, "brake": 0.0, "reverse": false}})
	var varied_road := drive.duplicate()
	# Use the actual low-grip region and the real analytic tabletop profile.
	var low_grip := resting.duplicate()
	low_grip[0] = 3.3
	low_grip[3] = 1.2
	for corner in 4:
		low_grip[21 + corner] = 11.5
	cases.append({"name": "low_grip_region", "state": low_grip,
		"controls": {"throttle": 0.46, "steering": 0.72, "brake": 0.0, "reverse": false}})
	var airborne := drive.duplicate()
	airborne[2] -= 0.55
	cases.append({"name": "airborne", "state": airborne,
		"controls": {"throttle": 0.15, "steering": 0.0, "brake": 0.75, "reverse": false}})
	var inverted := resting.duplicate()
	inverted[6] = 0.0
	inverted[7] = 1.0
	inverted[8] = 0.0
	inverted[9] = 0.0
	inverted[3] = 0.35
	cases.append({"name": "inverted_hull_contact", "state": inverted,
		"controls": {"throttle": 0.0, "steering": -0.2, "brake": 0.6, "reverse": false}})
	var slope := drive.duplicate()
	slope[0] = 8.5
	slope[1] = 0.3
	slope[4] = 0.25
	slope[11] = -0.18
	cases.append({"name": "bump_nonflat_velocity", "state": slope,
		"controls": {"throttle": 0.35, "steering": 0.52, "brake": 0.12, "reverse": false}})
	return cases


func _run_case(name: String, state: PackedFloat64Array, model: Dictionary,
		controls: Dictionary, road: Callable, batch: Callable, energy: bool, adaptive: bool) -> void:
	var reference: Dictionary = VehicleDynamics._evaluate(state, model, controls, road, energy, adaptive)
	var candidate: Dictionary = _native.evaluate(state, model, controls, batch, energy, adaptive)
	_checks += 1
	if bool(reference.get("ok", false)) != bool(candidate.get("ok", false)):
		_fail("%s success mismatch: gd=%s native=%s (%s)" % [name, str(reference.get("ok")), str(candidate.get("ok")), str(candidate.get("error", ""))])
		return
	if not bool(reference.get("ok", false)):
		return
	for key: String in FLOAT_OUTPUTS:
		if not reference.has(key) or not candidate.has(key):
			_fail("%s omitted output %s" % [name, key])
			continue
		var left: PackedFloat64Array = reference[key]
		var right: PackedFloat64Array = candidate[key]
		if left.size() != right.size():
			_fail("%s %s size mismatch %d vs %d" % [name, key, left.size(), right.size()])
			continue
		for index in left.size():
			if not _close(left[index], right[index]):
				_fail("%s %s[%d] differs: %.17g vs %.17g (delta %.5g)" % [name, key, index, left[index], right[index], left[index] - right[index]])
				break
	for key: String in BYTE_OUTPUTS:
		if reference.get(key) != candidate.get(key):
			_fail("%s %s differs" % [name, key])
	for key: String in ["airborne", "friction_sweeps_used"]:
		if reference.get(key) != candidate.get(key):
			_fail("%s %s differs: %s vs %s" % [name, key, str(reference.get(key)), str(candidate.get(key))])
	if not _close(float(reference.get("steering_acceleration_rad_per_s2", 0.0)), float(candidate.get("steering_acceleration_rad_per_s2", 0.0))):
		_fail("%s steering acceleration differs" % name)
	if not _close(float(reference.get("energy_j", 0.0)), float(candidate.get("energy_j", 0.0))):
		_fail("%s energy differs: %.17g vs %.17g" % [name, float(reference.energy_j), float(candidate.energy_j)])


func _run_randomized(resting: PackedFloat64Array, model: Dictionary, road: Callable, batch: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5243562d50415249
	for sample_index in 12:
		var state := resting.duplicate()
		state[0] = rng.randf_range(-2.0, 14.0)
		state[1] = rng.randf_range(-5.0, 5.0)
		state[2] -= rng.randf_range(0.0, 0.2)
		state[3] = rng.randf_range(-2.0, 3.0)
		state[4] = rng.randf_range(-0.4, 0.4)
		state[5] = rng.randf_range(-0.2, 0.2)
		var roll := rng.randf_range(-0.28, 0.28)
		var pitch := rng.randf_range(-0.28, 0.28)
		var yaw := rng.randf_range(-PI, PI)
		var qx := sin(roll * 0.5)
		var qy := sin(pitch * 0.5)
		var qz := sin(yaw * 0.5)
		var qw := cos(roll * 0.5) * cos(pitch * 0.5) * cos(yaw * 0.5)
		state[6] = qw
		state[7] = qx
		state[8] = qy
		state[9] = qz
		for corner in 4:
			state[13 + corner] = rng.randf_range(-0.04, 0.04)
			state[17 + corner] = rng.randf_range(-0.7, 0.7)
			state[21 + corner] = rng.randf_range(-20.0, 20.0)
			state[25 + corner] = rng.randf_range(-1.0, 1.0)
		state[10] = rng.randf_range(-1.3, 1.3)
		state[11] = rng.randf_range(-1.3, 1.3)
		state[12] = rng.randf_range(-1.3, 1.3)
		state[29] = rng.randf_range(-0.3, 0.3)
		state[30] = rng.randf_range(-1.0, 1.0)
		var controls := {
			"throttle": rng.randf_range(0.0, 1.0),
			"steering": rng.randf_range(-1.0, 1.0),
			"brake": rng.randf_range(0.0, 1.0),
			"reverse": sample_index % 3 == 0,
		}
		_run_case("random_%02d" % sample_index, state, model, controls, road, batch, sample_index % 2 == 0, sample_index % 2 == 1)


func _run_brake_distribution(resting: PackedFloat64Array, model: Dictionary, road: Callable, batch: Callable) -> void:
	var state := resting.duplicate()
	state[3] = 11.87
	state[4] = 0.05
	for corner in 4:
		state[21 + corner] = 118.7
	var controls := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}
	for fraction in [0.0, 0.5, 0.85, 1.0]:
		var biased := model.duplicate(true)
		biased.brake_front_fraction = fraction
		_run_case("brake_fraction_" + str(fraction), state, biased, controls, road, batch, true, true)
	var legacy := model.duplicate(true)
	legacy.erase("brake_front_fraction")
	_run_case("legacy_equal_brake_distribution", state, legacy, controls, road, batch, true, true)
	for fraction in [-0.01, 1.01, NAN, INF, true, "0.85"]:
		var invalid := model.duplicate(true)
		invalid.brake_front_fraction = fraction
		# The public GDScript boundary validates before entering _evaluate.
		var reference: Dictionary = VehicleDynamics.telemetry(state, invalid, road, controls)
		var native: Dictionary = _native.evaluate(state, invalid, controls, batch, true, true)
		_checks += 1
		if reference.get("ok", true) or native.get("ok", true):
			_fail("invalid axle brake fraction accepted: " + str(fraction))


func _run_invalids(resting: PackedFloat64Array, model: Dictionary, batch: Callable) -> void:
	var singular := resting.duplicate()
	singular[13] = float(model.arm_length_m)
	var native_singular: Dictionary = _native.evaluate(singular, model, VehicleDynamics.DEFAULT_CONTROLS, batch, true, true)
	_checks += 1
	if bool(native_singular.get("ok", true)) or not str(native_singular.get("error", "")).contains("singularity"):
		_fail("A-arm singularity did not return a normal native failure")
	var short_state := PackedFloat64Array([0.0, 0.0, 0.0])
	var native_short: Dictionary = _native.evaluate(short_state, model, VehicleDynamics.DEFAULT_CONTROLS, batch, true, true)
	_checks += 1
	if bool(native_short.get("ok", true)) or not str(native_short.get("error", "")).contains("31"):
		_fail("short native state did not return a normal error dictionary")
	var bad_model := model.duplicate(true)
	var wrong_corners: PackedFloat64Array = bad_model.corner_x_m
	wrong_corners.remove_at(3)
	bad_model.corner_x_m = wrong_corners
	var native_model: Dictionary = _native.evaluate(resting, bad_model, VehicleDynamics.DEFAULT_CONTROLS, batch, true, true)
	_checks += 1
	if bool(native_model.get("ok", true)) or str(native_model.get("error", "")).is_empty():
		_fail("malformed native model did not return an error dictionary")
	var rejected_road: Callable = func(_coords: PackedFloat64Array) -> Dictionary:
		return {"ok": false, "error": "synthetic road rejection"}
	var road_failure: Dictionary = _native.evaluate(resting, model, VehicleDynamics.DEFAULT_CONTROLS, rejected_road, true, true)
	_checks += 1
	if bool(road_failure.get("ok", true)) or not str(road_failure.get("error", "")).contains("synthetic road rejection"):
		_fail("road rejection did not return a normal native failure")
	var invalid_normal: Callable = func(coords: PackedFloat64Array) -> Dictionary:
		var samples := PackedFloat64Array()
		for _index in range(0, coords.size(), 2):
			samples.append(0.0)
			samples.append(0.0)
			samples.append(0.0)
			samples.append(0.0)
			samples.append(0.8)
			samples.append(0.02)
		return {"ok": true, "error": "", "samples": samples}
	var normal_failure: Dictionary = _native.evaluate(resting, model, VehicleDynamics.DEFAULT_CONTROLS, invalid_normal, true, true)
	_checks += 1
	if bool(normal_failure.get("ok", true)) or str(normal_failure.get("error", "")).is_empty():
		_fail("invalid road normal did not return a normal native failure")
	var invalid_attitude := resting.duplicate()
	for index in 4:
		invalid_attitude[6 + index] = 0.0
	var attitude_failure: Dictionary = _native.evaluate(invalid_attitude, model, VehicleDynamics.DEFAULT_CONTROLS, batch, true, true)
	_checks += 1
	if bool(attitude_failure.get("ok", true)) or str(attitude_failure.get("error", "")).is_empty():
		_fail("zero quaternion did not return a normal native failure")
	var wrong_type: Dictionary = _native.evaluate(PackedFloat32Array([0.0]), model,
		VehicleDynamics.DEFAULT_CONTROLS, batch, true, true)
	_checks += 1
	if bool(wrong_type.get("ok", true)) or str(wrong_type.get("error", "")).is_empty():
		_fail("wrong-typed state did not return a normal native failure")
	var invalid_flags: Dictionary = _native.evaluate(resting, model,
		VehicleDynamics.DEFAULT_CONTROLS, batch, "true", true)
	_checks += 1
	if bool(invalid_flags.get("ok", true)) or str(invalid_flags.get("error", "")).is_empty():
		_fail("wrong-typed flags did not return a normal native failure")


func _run_external_generalized_loads(resting: PackedFloat64Array, scenario: Dictionary,
		model: Dictionary, road: Callable, batch: Callable) -> void:
	var combined_force := PackedFloat64Array()
	combined_force.resize(14)
	combined_force[0] = 3.0
	combined_force[1] = -1.2
	combined_force[2] = 0.8
	combined_force[3] = 0.4
	combined_force[4] = -0.3
	combined_force[5] = 0.2
	combined_force[6] = 1.5
	combined_force[7] = -0.7
	combined_force[8] = 1.2
	combined_force[9] = -0.8
	combined_force[10] = 0.08
	combined_force[11] = -0.05
	combined_force[12] = 0.06
	combined_force[13] = -0.03
	var combined_controls: Dictionary = scenario.controls.duplicate(true)
	combined_controls["external_generalized_force"] = combined_force
	_run_case("external_body_moment_suspension_and_wheel_loads", scenario.state,
		model, combined_controls, road, batch, true, true)

	# A resting vehicle with freely rolling wheels will accelerate under a
	# horizontal load, but its tire response should oppose that load. Requiring
	# full hold here would incorrectly assume the brakes are engaged.
	var static_force := PackedFloat64Array()
	static_force.resize(14)
	static_force[0] = 0.05
	var static_controls: Dictionary = VehicleDynamics.DEFAULT_CONTROLS.duplicate(true)
	static_controls["external_generalized_force"] = static_force
	_run_case("external_load_static_tire_response", resting, model, static_controls,
		road, batch, true, true)
	var static_reference: Dictionary = VehicleDynamics._evaluate(resting, model,
		static_controls, road, true, true)
	_checks += 1
	if not bool(static_reference.get("ok", false)):
		_fail("GDScript external-load static-grip reference failed")
		return
	var static_acceleration: PackedFloat64Array = static_reference.generalized_acceleration
	var static_longitudinal: PackedFloat64Array = static_reference.wheel_longitudinal_force_n
	var total_longitudinal := 0.0
	for value in static_longitudinal:
		total_longitudinal += value
	if total_longitudinal * static_force[0] >= 0.0:
		_fail("small resting body force did not produce an opposing tire response: acceleration=%s tire_force=%s" % [
			str(static_acceleration[0]), str(total_longitudinal),
		])

	var malformed: Array[Variant] = []
	malformed.append(PackedFloat32Array([0.0]))
	var short_force := PackedFloat64Array()
	short_force.resize(13)
	malformed.append(short_force)
	var long_force := PackedFloat64Array()
	long_force.resize(15)
	malformed.append(long_force)
	var nan_force := PackedFloat64Array()
	nan_force.resize(14)
	nan_force[5] = NAN
	malformed.append(nan_force)
	var infinite_force := PackedFloat64Array()
	infinite_force.resize(14)
	infinite_force[9] = INF
	malformed.append(infinite_force)
	for index in malformed.size():
		var invalid_controls: Dictionary = VehicleDynamics.DEFAULT_CONTROLS.duplicate(true)
		invalid_controls["external_generalized_force"] = malformed[index]
		var reference: Dictionary = VehicleDynamics._evaluate(resting, model,
			invalid_controls, road, true, true)
		var candidate: Dictionary = _native.evaluate(resting, model,
			invalid_controls, batch, true, true)
		_checks += 1
		if bool(reference.get("ok", true)) or bool(candidate.get("ok", true)):
			_fail("malformed external generalized force %d was accepted: gd=%s native=%s" % [
				index, str(reference.get("ok", true)), str(candidate.get("ok", true)),
			])


func _run_lake_terrain_parity() -> void:
	var lake_result: Dictionary = LakeLoader.load_from()
	_checks += 1
	if not bool(lake_result.get("ok", false)):
		_fail("lake terrain parity fixture did not load: " + str(lake_result.get("errors", [])))
		return
	var lake: Dictionary = lake_result.lake
	var surface_rects := PackedFloat64Array([-INF, INF, -INF, INF, 1.0, GroundTerrain.ROLLING_ROUGH])
	var points := PackedFloat64Array()
	var north_min := INF
	var north_max := -INF
	var east_min := INF
	var east_max := -INF
	var bank: PackedFloat64Array = lake.bank_ne_m
	for index in range(0, bank.size(), 2):
		north_min = minf(north_min, bank[index])
		north_max = maxf(north_max, bank[index])
		east_min = minf(east_min, bank[index + 1])
		east_max = maxf(east_max, bank[index + 1])
	for north_index in range(17):
		var north := lerpf(north_min - 1.0, north_max + 1.0, float(north_index) / 16.0)
		for east_index in range(25):
			var east := lerpf(east_min - 1.0, east_max + 1.0, float(east_index) / 24.0)
			_append_lake_terrain_point(points, north, east)
	for polygon: PackedFloat64Array in [lake.shoreline_ne_m, bank]:
		var vertex_count := polygon.size() / 2
		for index in range(vertex_count):
			var next := (index + 1) % vertex_count
			var north_a := polygon[index * 2]
			var east_a := polygon[index * 2 + 1]
			var north_b := polygon[next * 2]
			var east_b := polygon[next * 2 + 1]
			var north_mid := (north_a + north_b) * 0.5
			var east_mid := (east_a + east_b) * 0.5
			for point: PackedFloat64Array in [
				PackedFloat64Array([north_a, east_a]),
				PackedFloat64Array([north_mid, east_mid]),
				PackedFloat64Array([north_mid + 1.0e-6, east_mid]),
				PackedFloat64Array([north_mid - 1.0e-6, east_mid]),
				PackedFloat64Array([north_mid, east_mid + 1.0e-6]),
				PackedFloat64Array([north_mid, east_mid - 1.0e-6]),
			]:
				_append_lake_terrain_point(points, point[0], point[1])
	_append_lake_terrain_point(points, float(lake.origin_north_m), float(lake.origin_east_m))
	_append_lake_terrain_point(points, float(lake.origin_north_m) + 24.0, float(lake.origin_east_m))
	_append_lake_terrain_point(points, float(lake.origin_north_m), float(lake.origin_east_m) + 36.0)
	_append_lake_terrain_point(points, float(lake.origin_north_m) - 45.0, float(lake.origin_east_m) + 70.0)
	var valid_base: PackedFloat64Array = GroundTerrain.sample_validated(110.0, 125.0, surface_rects)
	var max_error := 0.0
	var bit_exact_channels := 0
	var compared_channels := 0
	var invalid_output_count := 0
	var worst_sample_index := -1
	var worst_north := 0.0
	var worst_east := 0.0
	var point_count := points.size() / 2
	for point_index in range(point_count):
		var north := points[point_index * 2]
		var east := points[point_index * 2 + 1]
		var base: PackedFloat64Array = GroundTerrain.sample_validated(north, east, surface_rects)
		var reference: PackedFloat64Array = GroundTerrain.sample_validated(north, east, surface_rects, lake)
		var signed_shore := LakeSurface.shore_distance_validated(lake, north, east)
		var expected := PackedFloat64Array([reference[0], reference[1], reference[2], signed_shore])
		var actual: PackedFloat64Array = _native.sample_lake_terrain(lake, north, east, base)
		_checks += 1
		if actual.size() != 4:
			invalid_output_count += 1
			continue
		var point_error := 0.0
		for channel in 4:
			var difference := absf(actual[channel] - expected[channel])
			point_error = maxf(point_error, difference)
			compared_channels += 1
			if difference == 0.0:
				bit_exact_channels += 1
		if point_error > max_error:
			max_error = point_error
			worst_sample_index = point_index
			worst_north = north
			worst_east = east
	if invalid_output_count > 0:
		_fail("native lake terrain returned the wrong channel count at %d samples" % invalid_output_count)
	if max_error > 1.0e-12:
		_fail("native lake terrain differs at sample %d N=%s E=%s max_error=%s" % [
			worst_sample_index, str(worst_north), str(worst_east), str(max_error),
		])
	var short_base := PackedFloat64Array([0.0, 0.0])
	var nan_base := PackedFloat64Array([0.0, NAN, 0.0])
	var malformed_lake: Dictionary = lake.duplicate(true)
	malformed_lake.bed_profile = [{"inset_m": 0.0, "depth_m": 0.0}]
	_checks += 5
	if not _native.sample_lake_terrain(lake, 110.0, 125.0, short_base).is_empty() \
			or not _native.sample_lake_terrain(lake, 110.0, 125.0, nan_base).is_empty() \
			or not _native.sample_lake_terrain(malformed_lake, 110.0, 125.0, valid_base).is_empty() \
			or not _native.sample_lake_terrain(lake, NAN, 125.0, valid_base).is_empty() \
			or not _native.sample_lake_terrain(lake, 110.0, INF, valid_base).is_empty():
		_fail("native lake terrain accepted malformed base or unnormalized lake input")
	print("OPENRC_NATIVE_LAKE_PARITY points=%d channels=%d bit_exact=%d max_abs_error=%s" % [
		point_count, compared_channels, bit_exact_channels, str(max_error),
	])
	_profile_lake_terrain(lake, surface_rects, points)


func _append_lake_terrain_point(points: PackedFloat64Array, north: float, east: float) -> void:
	points.append(north)
	points.append(east)


func _profile_lake_terrain(lake: Dictionary, surface_rects: PackedFloat64Array,
		points: PackedFloat64Array) -> void:
	const PROFILE_ROUNDS := 3
	var point_count := points.size() / 2
	var sink := 0.0
	for point_index in range(point_count):
		var north_warm := points[point_index * 2]
		var east_warm := points[point_index * 2 + 1]
		var base_warm: PackedFloat64Array = GroundTerrain.sample_validated(north_warm, east_warm, surface_rects)
		var warmed: PackedFloat64Array = _native.sample_lake_terrain(lake, north_warm, east_warm, base_warm)
		sink += warmed[0] + warmed[3]
		var reference_warm: PackedFloat64Array = GroundTerrain.sample_validated(north_warm, east_warm, surface_rects, lake)
		sink += reference_warm[0] + LakeSurface.shore_distance_validated(lake, north_warm, east_warm)
	var before_reference := Time.get_ticks_usec()
	for _round in PROFILE_ROUNDS:
		for point_index in range(point_count):
			var north_reference := points[point_index * 2]
			var east_reference := points[point_index * 2 + 1]
			var reference_sample: PackedFloat64Array = GroundTerrain.sample_validated(north_reference, east_reference, surface_rects, lake)
			var shore_distance := LakeSurface.shore_distance_validated(lake, north_reference, east_reference)
			sink += reference_sample[0] + shore_distance
	var reference_usec := Time.get_ticks_usec() - before_reference
	var before_native := Time.get_ticks_usec()
	for _round in PROFILE_ROUNDS:
		for point_index in range(point_count):
			var north_native := points[point_index * 2]
			var east_native := points[point_index * 2 + 1]
			var base_native: PackedFloat64Array = GroundTerrain.sample_validated(north_native, east_native, surface_rects)
			var native_sample: PackedFloat64Array = _native.sample_lake_terrain(lake, north_native, east_native, base_native)
			sink += native_sample[0] + native_sample[3]
	var native_usec := Time.get_ticks_usec() - before_native
	var reference_ms_per_sample := float(reference_usec) / float(PROFILE_ROUNDS * point_count) / 1000.0
	var native_ms_per_sample := float(native_usec) / float(PROFILE_ROUNDS * point_count) / 1000.0
	print("OPENRC_NATIVE_LAKE_PROFILE points=%d rounds=%d gdscript_ms_per_sample=%s native_ms_per_sample=%s speedup=%s check=%s" % [
		point_count, PROFILE_ROUNDS, str(reference_ms_per_sample), str(native_ms_per_sample),
		str(reference_ms_per_sample / maxf(native_ms_per_sample, 1.0e-9)), str(sink),
	])


func _run_evaluate_profile(scenario: Dictionary, model: Dictionary, road: Callable, batch: Callable) -> void:
	const REPETITIONS := 50
	var state: PackedFloat64Array = scenario.state
	var controls: Dictionary = scenario.controls
	var before_reference := Time.get_ticks_usec()
	for _index in REPETITIONS:
		VehicleDynamics._evaluate(state, model, controls, road, true, true)
	var reference_usec := Time.get_ticks_usec() - before_reference
	var before_native := Time.get_ticks_usec()
	for _index in REPETITIONS:
		_native.evaluate(state, model, controls, batch, true, true)
	var native_usec := Time.get_ticks_usec() - before_native
	print("OPENRC_NATIVE_EVAL_PROFILE engine_debug=%s extension_target=template_release gdscript_ms=%.4f native_ms=%.4f speedup=%.2fx iterations=%d" % [
		str(OS.is_debug_build()),
		float(reference_usec) / REPETITIONS / 1000.0,
		float(native_usec) / REPETITIONS / 1000.0,
		float(reference_usec) / maxf(float(native_usec), 1.0),
		REPETITIONS,
	])


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= ABS_TOLERANCE + REL_TOLERANCE * maxf(absf(a), absf(b))


func _fail(message: String) -> void:
	_failures += 1
	push_error("NATIVE PARITY: " + message)
