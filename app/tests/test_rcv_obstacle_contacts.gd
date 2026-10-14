extends SceneTree

const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const M := preload("res://physics/math3d.gd")

const POSITION_NORTH := Vehicle.POS
const VELOCITY_NORTH := Vehicle.VEL
const VELOCITY_EAST := Vehicle.VEL + 1
const WHEEL_SPIN := Vehicle.WHEEL_SPIN
const MAX_TICK := 1.0 / 30.0

var _failures := 0
var _checks := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not condition:
		_failures += 1


func _sum(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total


func _road(walls_value: Variant = [], include_walls := true) -> Callable:
	return func(_north_m: float, _east_m: float) -> Dictionary:
		var sample := {
			"height_m": 0.0,
			"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
			"mu": 0.0,
			"rolling": 0.0,
			"surface_id": "wall-test-ground",
		}
		if include_walls:
			sample["walls"] = walls_value
		return sample


func _wall(north_min: float, north_max: float, east_min: float, east_max: float,
		bottom_up: float, top_up: float, mu: float) -> Dictionary:
	return {
		"id": "test-wall",
		"north_min_m": north_min,
		"north_max_m": north_max,
		"east_min_m": east_min,
		"east_max_m": east_max,
		"bottom_up_m": bottom_up,
		"top_up_m": top_up,
		"mu": mu,
	}


func _initialize() -> void:
	var loaded := Data.load_default()
	_check("Bisonte contact test model loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded["model"]
	var clear_road := _road()
	var initialized := Vehicle.initialize(model, clear_road, 0.0, 0.0)
	_check("flat test state initializes", bool(initialized.get("ok", false)), str(initialized.get("error", "")))
	if not bool(initialized.get("ok", false)):
		quit(1)
		return
	var state: PackedFloat64Array = initialized["state"]
	var clear_report := Vehicle.telemetry(state, model, clear_road)
	var touching_wall := _road([_wall(0.28, 0.58, -1.0, 1.0, 0.0, 0.7, 0.8)])
	var rest_report := Vehicle.telemetry(state, model, touching_wall)
	_check("sphere contacts report tire and hull wall support",
		bool(rest_report.get("ok", false)) and int(rest_report.get("wall_contact_count", 0)) > 0
		and _sum(rest_report.get("wheel_wall_load_n", PackedFloat64Array())) > 0.0
		and _sum(rest_report.get("hull_wall_load_n", PackedFloat64Array())) > 0.0
		and rest_report.get("hull_in_contact", PackedByteArray()).count(1) > 0
		and not bool(rest_report.get("airborne", true)))
	_check("wall loads stay separate from terrain tire loads",
		clear_report.get("wheel_load_n", PackedFloat64Array()) == rest_report.get("wheel_load_n", PackedFloat64Array()))
	_check("wall spring energy is included without creating friction power at rest",
		float(rest_report.get("total_energy_j", 0.0)) > float(clear_report.get("total_energy_j", 0.0))
		and float(rest_report.get("wall_friction_power_w", 1.0)) == 0.0)
	_check("empty wall samples stay inactive", int(clear_report.get("wall_contact_count", -1)) == 0
		and float(clear_report.get("wall_normal_load_n", 1.0)) == 0.0)

	var sliding_state := state.duplicate()
	sliding_state[VELOCITY_EAST] = 1.0
	var sliding_report := Vehicle.telemetry(sliding_state, model, touching_wall)
	_check("regularized wall friction dissipates while sliding",
		bool(sliding_report.get("ok", false))
		and int(sliding_report.get("wall_contact_count", 0)) > 0
		and float(sliding_report.get("wall_friction_power_w", 1.0)) < 0.0,
		"friction power %.6f W" % float(sliding_report.get("wall_friction_power_w", NAN)))

	var malformed := Vehicle.telemetry(state, model, _road("not-an-array"))
	var invalid_box := _wall(1.0, 0.0, -1.0, 1.0, 0.0, 1.0, 0.8)
	var invalid_bounds := Vehicle.telemetry(state, model, _road([invalid_box]))
	var too_many: Array = []
	for index in Vehicle.MAX_WALL_CONTACT_BOXES + 1:
		var extra := _wall(4.0 + float(index), 4.5 + float(index), -1.0, 1.0, 0.0, 1.0, 0.8)
		extra["id"] = "wall-%d" % index
		too_many.append(extra)
	var oversized := Vehicle.telemetry(state, model, _road(too_many))
	_check("malformed, inverted, and excessive wall samples fail closed",
		not bool(malformed.get("ok", true)) and not bool(invalid_bounds.get("ok", true))
		and not bool(oversized.get("ok", true)))

	# The entry face is 0.9 m ahead and the wall is 0.25 m thick. At the maximum
	# public tick and 4 m/s, the truck advances 0.133 m per tick.
	var barrier := _wall(0.9, 1.15, -1.0, 1.0, 0.0, 0.7, 0.5)
	var barrier_road := _road([barrier])
	var moving := state.duplicate()
	moving[Vehicle.VEL] = 4.0
	var tire_radius := float(model["tire_radius_m"])
	for corner in Vehicle.CORNER_COUNT:
		moving[WHEEL_SPIN + corner] = 4.0 / tire_radius
	var first_contact: PackedFloat64Array = PackedFloat64Array()
	var passed_barrier := false
	var maximum_speed := absf(moving[Vehicle.VEL])
	for tick in 45:
		moving = Vehicle.step(moving, model, Vehicle.DEFAULT_CONTROLS, MAX_TICK, barrier_road)
		if moving.is_empty():
			break
		maximum_speed = maxf(maximum_speed, absf(moving[Vehicle.VEL]))
		if first_contact.is_empty() and int(Vehicle.telemetry(moving, model, barrier_road).get("wall_contact_count", 0)) > 0:
			first_contact = moving.duplicate()
		if moving[POSITION_NORTH] > float(barrier.north_max_m):
			passed_barrier = true
			break
	var final_report := Vehicle.telemetry(moving, model, barrier_road) if moving.size() == Vehicle.STATE_SIZE else {}
	_check("4 m/s approach reaches a wall contact before crossing it",
		first_contact.size() == Vehicle.STATE_SIZE and not passed_barrier,
		"north %.3f m, speed %.3f m/s" % [moving[POSITION_NORTH] if moving.size() > 0 else NAN,
			M.norm(moving.slice(Vehicle.VEL, Vehicle.VEL + 3)) if moving.size() > 0 else NAN])
	_check("wall impact remains finite and loses forward speed",
		moving.size() == Vehicle.STATE_SIZE and bool(final_report.get("ok", false))
		and is_finite(moving[POSITION_NORTH]) and moving[Vehicle.VEL] < 4.0 and maximum_speed < 8.0,
		"speed %.3f m/s, peak %.3f m/s" % [moving[Vehicle.VEL] if moving.size() > 0 else NAN, maximum_speed])

	var reverse_barrier := _wall(-1.15, -0.9, -1.0, 1.0, 0.0, 0.7, 0.5)
	var reverse_road := _road([reverse_barrier])
	var reversing := state.duplicate()
	reversing[Vehicle.VEL] = -4.0
	for corner in Vehicle.CORNER_COUNT:
		reversing[WHEEL_SPIN + corner] = -4.0 / tire_radius
	var reverse_crossed := false
	var reverse_contact := false
	for tick in 30:
		reversing = Vehicle.step(reversing, model, Vehicle.DEFAULT_CONTROLS, MAX_TICK, reverse_road)
		if reversing.is_empty():
			break
		if int(Vehicle.telemetry(reversing, model, reverse_road).get("wall_contact_count", 0)) > 0:
			reverse_contact = true
		if reversing[POSITION_NORTH] < float(reverse_barrier.north_min_m):
			reverse_crossed = true
			break
	_check("reverse-speed impact stays finite and does not tunnel through the wall",
		reversing.size() == Vehicle.STATE_SIZE and reverse_contact and not reverse_crossed
		and is_finite(reversing[POSITION_NORTH]) and absf(reversing[Vehicle.VEL]) < 8.0)

	var native_or_default := Vehicle._evaluate_active(state, model, Vehicle.DEFAULT_CONTROLS, touching_wall, false)
	var switched := Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE)
	var reference := Vehicle._evaluate_active(state, model, Vehicle.DEFAULT_CONTROLS, touching_wall, false) if switched else {}
	Vehicle.set_backend_override_for_tests("")
	var parity_error := INF
	if bool(native_or_default.get("ok", false)) and bool(reference.get("ok", false)):
		var active_acceleration: PackedFloat64Array = native_or_default["generalized_acceleration"]
		var reference_acceleration: PackedFloat64Array = reference["generalized_acceleration"]
		parity_error = 0.0
		for index in Vehicle.GENERALIZED_SIZE:
			parity_error = maxf(parity_error, absf(active_acceleration[index] - reference_acceleration[index]))
	_check("shared wall response matches the reference backend", switched
		and bool(native_or_default.get("ok", false)) and bool(reference.get("ok", false))
		and int(native_or_default.get("wall_contact_count", 0)) == int(reference.get("wall_contact_count", 0))
		and parity_error < 1.0e-8,
		"max acceleration delta %.9f" % parity_error)
	_test_high_speed_impact(state, model, barrier_road)

	print("RCV obstacle contacts: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_high_speed_impact(initial: PackedFloat64Array, model: Dictionary, road: Callable) -> void:
	# The revised motor permits ~10 m/s. A neutral rolling impact isolates wall
	# collision response from motor work; no drive impulse or state reset follows.
	for dt in [1.0 / 240.0, 1.0 / 480.0]:
		var moving := initial.duplicate()
		moving[Vehicle.VEL] = 10.0
		for corner in Vehicle.CORNER_COUNT:
			moving[WHEEL_SPIN + corner] = 10.0 / float(model.tire_radius_m)
		var initial_energy := float(Vehicle.telemetry(moving, model, road).total_energy_j)
		var max_energy := initial_energy
		var contact_seen := false
		var crossed_before_contact := false
		var valid := true
		var peak_load := 0.0
		for _tick in int(round(0.5 / dt)):
			moving = Vehicle.step(moving, model, Vehicle.DEFAULT_CONTROLS, dt, road)
			if moving.size() != Vehicle.STATE_SIZE:
				valid = false
				break
			var report := Vehicle.telemetry(moving, model, road)
			valid = valid and bool(report.get("ok", false))
			contact_seen = contact_seen or int(report.get("wall_contact_count", 0)) > 0
			crossed_before_contact = crossed_before_contact or (not contact_seen and moving[POSITION_NORTH] > 1.15)
			peak_load = maxf(peak_load, float(report.get("wall_normal_load_n", 0.0)))
			max_energy = maxf(max_energy, float(report.get("total_energy_j", INF)))
		_check("10 m/s rolling wall impact is detected and stays dissipative at %d Hz" % int(round(1.0 / dt)),
			valid and contact_seen and not crossed_before_contact and peak_load > 100.0
			and max_energy <= initial_energy * 1.01 + 0.1,
			"peak load %.1f N, energy %.3f→max %.3f J" % [peak_load, initial_energy, max_energy])
