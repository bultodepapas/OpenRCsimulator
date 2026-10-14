extends SceneTree

const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const CourseData := preload("res://physics/ground_vehicle/course.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const DATA_PATH := "res://data/vehicles/ground/mt8_bisonte.json"

var failures := 0


func _initialize() -> void:
	var loaded: Dictionary = VehicleData.load_default()
	_check("default vehicle data loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded.model
	_check("vehicle format is separately versioned", loaded.identity.format == "openrc-ground-vehicle" and loaded.identity.version == "1")
	_check("identity binds the file bytes", str(loaded.identity.sha256).length() == 64)
	_check("geometry conversion yields FRD corner order", model.corner_x_m is PackedFloat64Array and model.corner_y_m is PackedFloat64Array)
	_check("corner station signs match FRD", model.corner_x_m[0] > 0.0 and model.corner_x_m[2] < 0.0 and model.corner_y_m[0] < 0.0 and model.corner_y_m[1] > 0.0)
	_check("kernel model has full explicit inertia", model.sprung_inertia_kg_m2 is PackedFloat64Array and model.sprung_inertia_kg_m2.size() == 6)
	_check("kernel model includes slip and torque fade", model.has("tire_slip_relaxation_s") and model.has("drive_torque_fade_rad_s"))
	_test_kernel_initialization(model)
	_test_experiment(loaded)
	_test_strict_rejection()
	_test_brake_distribution()
	quit(1 if failures > 0 else 0)


func _test_kernel_initialization(model: Dictionary) -> void:
	var course_result: Dictionary = CourseData.load_default()
	_check("practice course loads for the vehicle kernel", bool(course_result.get("ok", false)), str(course_result.get("errors", [])))
	if not bool(course_result.get("ok", false)):
		return
	var course: Dictionary = course_result.course
	var road: Callable = func(north_m: float, east_m: float) -> Dictionary:
		return CourseData.sample(course, north_m, east_m)
	var start: Dictionary = VehicleDynamics.initialize(model, road, 0.0, 0.0)
	_check("estimated MT8 model constructs a supported flat-start state", bool(start.get("ok", false)), str(start.get("error", "")))
	if bool(start.get("ok", false)):
		var telemetry: Dictionary = VehicleDynamics.telemetry(start.state, model, road)
		_check("initial kernel state is finite and supported", start.state.size() == VehicleDynamics.STATE_SIZE and bool(telemetry.get("ok", false)) and not bool(telemetry.get("airborne", true)), str(telemetry.get("error", "")))


func _test_experiment(base: Dictionary) -> void:
	var knobs := {
		"gravity_scale": 1.0,
		"grip_scale": 1.0,
		"spring_scale": 1.0,
		"damper_scale": 1.0,
		"ballast_kg": 0.0,
		"ballast_height_m": 0.20,
	}
	var unchanged: Dictionary = VehicleData.with_experiment(base, knobs)
	_check("identity settings experiment succeeds", bool(unchanged.get("ok", false)), str(unchanged.get("errors", [])))
	if not bool(unchanged.get("ok", false)):
		return
	_check("zero ballast preserves mass and CG", is_equal_approx(unchanged.model.sprung_mass_kg, base.model.sprung_mass_kg) and is_equal_approx(unchanged.model.cg_height_above_chassis_datum_m, base.model.cg_height_above_chassis_datum_m))
	_check("experiment identity includes base and settings", unchanged.identity.base_sha256 == base.identity.sha256 and unchanged.identity.settings_json.contains("ballast_kg"))
	var ballast_knobs: Dictionary = knobs.duplicate(true)
	ballast_knobs.ballast_kg = 1.0
	ballast_knobs.ballast_height_m = 0.30
	var ballasted: Dictionary = VehicleData.with_experiment(base, ballast_knobs)
	_check("ballast experiment succeeds", bool(ballasted.get("ok", false)), str(ballasted.get("errors", [])))
	if bool(ballasted.get("ok", false)):
		var expected_cg: float = (base.model.sprung_mass_kg * base.model.cg_height_above_chassis_datum_m + 0.30) / (base.model.sprung_mass_kg + 1.0)
		_check("ballast updates sprung mass and weighted CG", is_equal_approx(ballasted.model.sprung_mass_kg, base.model.sprung_mass_kg + 1.0) and is_equal_approx(ballasted.model.cg_height_above_chassis_datum_m, expected_cg))
		_check("ballast shifts hull probes relative to the new CG", ballasted.model.hull_probe_centers_frd_m[2] > base.model.hull_probe_centers_frd_m[2])
		_check("ballast updates inertia with parallel-axis terms", ballasted.model.sprung_inertia_kg_m2[0] > base.model.sprung_inertia_kg_m2[0] and ballasted.model.sprung_inertia_kg_m2[1] > base.model.sprung_inertia_kg_m2[1])
		_check("experiment does not mutate base", is_equal_approx(base.model.sprung_mass_kg, 4.8) and is_equal_approx(base.model.cg_height_above_chassis_datum_m, 0.065))
	var zero_gravity: Dictionary = knobs.duplicate(true)
	zero_gravity.gravity_scale = 0.0
	var zero_result: Dictionary = VehicleData.with_experiment(base, zero_gravity)
	_check("zero gravity is an intentional experiment setting", bool(zero_result.get("ok", false)) and float(zero_result.model.gravity_m_per_s2) == 0.0, str(zero_result.get("errors", [])))
	var invalid: Dictionary = knobs.duplicate(true)
	invalid.grip_scale = 2.1
	var rejected: Dictionary = VehicleData.with_experiment(base, invalid)
	_check("out-of-range experiment rejected atomically", not bool(rejected.get("ok", true)) and rejected.get("model", {}).is_empty())


func _test_strict_rejection() -> void:
	var parser := JSON.new()
	var source: String = FileAccess.get_file_as_string(DATA_PATH)
	_check("vehicle fixture parses as JSON", parser.parse(source) == OK, parser.get_error_message())
	if parser.parse(source) != OK or not parser.data is Dictionary:
		return
	var mutated: Dictionary = parser.data.duplicate(true)
	mutated.unlisted = true
	var rejected: Dictionary = VehicleData.validate(mutated)
	_check("unknown vehicle fields reject the whole model", not bool(rejected.get("ok", true)) and rejected.get("model", {}).is_empty())
	var bad_quantity: Dictionary = parser.data.duplicate(true)
	bad_quantity.parameters.sprung_mass_kg.unit = "lb"
	rejected = VehicleData.validate(bad_quantity)
	_check("wrong physical units reject the whole model", not bool(rejected.get("ok", true)) and rejected.get("model", {}).is_empty())


func _test_brake_distribution() -> void:
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var legacy := authored.duplicate(true)
	legacy.parameters.erase("brake_front_fraction")
	var loaded: Dictionary = VehicleData.validate(legacy)
	_check("legacy descriptor defaults to equal axle braking", loaded.get("ok", false) and loaded.model.brake_front_fraction == 0.5)
	_check("legacy normalization does not mutate authored quantities", not legacy.parameters.has("brake_front_fraction"))
	for fraction in [0.0, 0.5, 0.85, 1.0]:
		var valid := authored.duplicate(true)
		valid.parameters.brake_front_fraction.value = fraction
		loaded = VehicleData.validate(valid)
		_check("valid axle brake fraction accepted: " + str(fraction), loaded.get("ok", false) and loaded.model.brake_front_fraction == fraction)
	for fraction in [-0.01, 1.01, NAN, INF, true, "0.85"]:
		var invalid := authored.duplicate(true)
		invalid.parameters.brake_front_fraction.value = fraction
		loaded = VehicleData.validate(invalid)
		_check("invalid axle brake fraction rejected: " + str(fraction), not loaded.get("ok", true) and loaded.get("model", {}).is_empty())


func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		failures += 1
		push_error("FAIL: %s %s" % [label, detail])
	else:
		print("PASS: ", label)
