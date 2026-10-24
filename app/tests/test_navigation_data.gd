# HUD-13 data layer: pilot-relative NED values, track/wind geometry, and sampled electric cruise efficiency.
# Draft parsed with Godot 4.7.2 before integration; the lead owns runtime test execution.
extends SceneTree

const Telemetry := preload("res://render/overlays/telemetry.gd")
const NavigationData := preload("res://render/overlays/navigation_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Air := preload("res://physics/air_data.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(a: float, b: float, tol := 1e-8) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	_test_telemetry_geometry()
	_test_efficiency_units_and_paused_time()
	_test_resets_and_validity()
	_test_rolling_window_and_bound()
	print("navigation data: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _state(position_ned: Array, velocity_body: Array, yaw_deg: float) -> PackedFloat64Array:
	var state := PackedFloat64Array()
	state.resize(RB.SIZE)
	for i in 3:
		state[RB.POS + i] = float(position_ned[i])
		state[RB.VEL + i] = float(velocity_body[i])
	var q := M.q_from_euler(deg_to_rad(yaw_deg), 0.0, 0.0)
	for i in 4:
		state[RB.ATT + i] = q[i]
	return state


func _telemetry_at(position_ned: Array, velocity_body: Array, yaw_deg: float,
		wind_ned: PackedFloat64Array, pilot_ned: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var state := _state(position_ned, velocity_body, yaw_deg)
	var air: Dictionary = Air.compute(state, wind_ned)
	var ctx := {
		pilot_ned = pilot_ned,
		terrain_up = 0.0,
		last_loads = PackedFloat64Array([0.0, 0.0, -9.80665, 0.0, 0.0, 0.0]),
		mass = 1.0,
		gravity = 9.80665,
		time_s = 4.0,
	}
	return Telemetry.compute(state, wind_ned, air, ctx)


func _test_telemetry_geometry() -> void:
	var calm := M.v3(0.0, 0.0, 0.0)
	var relative := _telemetry_at([12.0, 34.0, -50.0], [10.0, 0.0, 0.0], 0.0, calm, [10.0, 30.0, -1.7])
	_check("pilot offsets are aircraft-minus-pilot north/east", _near(relative.pilot_north_m, 2.0) and _near(relative.pilot_east_m, 4.0),
		"N %.3f E %.3f" % [relative.pilot_north_m, relative.pilot_east_m])
	_check("existing pilot range remains slant distance", _near(relative.distance_pilot, sqrt(2.0 * 2.0 + 4.0 * 4.0 + 48.3 * 48.3)))

	# NED wind velocity points where air travels. South wind is a headwind to a northbound aircraft;
	# east wind is toward the northbound aircraft's right.
	var north := _telemetry_at([0.0, 0.0, -20.0], [15.0, 0.0, 0.0], 0.0, M.v3(-4.0, 3.0, 0.0))
	_check("northbound headwind and right crosswind signs", _near(north.headwind_mps, 4.0) and _near(north.crosswind_mps, 3.0),
		"head %.3f cross %.3f" % [north.headwind_mps, north.crosswind_mps])

	# Facing east, west wind is headwind and southward wind pushes right.
	var east := _telemetry_at([0.0, 0.0, -20.0], [15.0, 0.0, 0.0], 90.0, M.v3(-3.0, -4.0, 0.0))
	_check("eastbound headwind and right crosswind signs", _near(east.headwind_mps, 4.0) and _near(east.crosswind_mps, 3.0),
		"head %.3f cross %.3f" % [east.headwind_mps, east.crosswind_mps])

	var east_track := _telemetry_at([0.0, 0.0, -20.0], [0.0, 5.0, 0.0], 0.0, calm)
	_check("eastward ground velocity reports a 090 course and positive drift", _near(east_track.ground_course_deg, 90.0)
		and _near(east_track.drift_deg, 90.0), "course %.3f drift %.3f" % [east_track.ground_course_deg, east_track.drift_deg])

	var right_speed := 20.0 * tan(deg_to_rad(2.0))
	var positive_wrap := _telemetry_at([0.0, 0.0, -20.0], [20.0, right_speed, 0.0], 359.0, calm)
	var negative_wrap := _telemetry_at([0.0, 0.0, -20.0], [20.0, -right_speed, 0.0], 1.0, calm)
	_check("drift wraps +179 to -179 through +2 degrees", _near(positive_wrap.drift_deg, 2.0, 1e-6), str(positive_wrap.drift_deg))
	_check("drift wraps -179 to +179 through -2 degrees", _near(negative_wrap.drift_deg, -2.0, 1e-6), str(negative_wrap.drift_deg))

	var still := _telemetry_at([0.0, 0.0, -20.0], [0.99, 0.0, 0.0], 25.0, calm)
	var threshold := _telemetry_at([0.0, 0.0, -20.0], [1.0, 0.0, 0.0], 25.0, calm)
	_check("course and drift are unknown below one metre per second", is_nan(still.ground_course_deg) and is_nan(still.drift_deg))
	_check("one metre per second is the defined course threshold", is_finite(threshold.ground_course_deg) and is_finite(threshold.drift_deg))


func _battery(power_w := 360.0, current_a := 36.0, kind := "pack_ecm", valid := true, soc := 0.5) -> Dictionary:
	return { valid = valid, kind = kind, power_w = power_w, current_a = current_a, soc = soc }


func _feed(data: RefCounted, from_index: int, to_index: int, period_s := 0.1,
		power_w := 360.0, current_a := 36.0, speed := 10.0, soc := 0.5) -> Dictionary:
	var result := {}
	for i in range(from_index, to_index + 1):
		result = data.update({ time_s = float(i) * period_s, ground_speed = speed }, _battery(power_w, current_a, "pack_ecm", true, soc))
	return result


func _test_efficiency_units_and_paused_time() -> void:
	var data := NavigationData.new()
	var first_t := { time_s = 0.0, ground_speed = 10.0 }
	var first_battery := _battery()
	var original_t := first_t.duplicate(true)
	var original_battery := first_battery.duplicate(true)
	var partial: Dictionary = data.update(first_t, first_battery)
	_check("less than two seconds is explicitly unavailable", not partial.valid and is_nan(partial.efficiency_wh_km)
		and is_nan(partial.efficiency_mah_km) and partial.sample_seconds == 0.0)
	for i in range(1, 21):
		partial = data.update({ time_s = float(i) * 0.1, ground_speed = 10.0 }, _battery())
	_check("360 W at 10 m/s integrates to 10 Wh/km", partial.valid and _near(partial.efficiency_wh_km, 10.0)
		and _near(partial.sample_seconds, 2.0), "valid=%s wh/km=%.6f seconds=%.6f" % [str(partial.valid), partial.efficiency_wh_km, partial.sample_seconds])
	_check("36 A at 10 m/s integrates to 1000 mAh/km", _near(partial.efficiency_mah_km, 1000.0), str(partial.efficiency_mah_km))
	_check("rolling totals use sampled ZOH power, current, distance", _near(partial.energy_wh, 0.2)
		and _near(partial.charge_mah, 20.0) and _near(partial.distance_m, 20.0))
	_check("telemetry and battery dictionaries stay untouched", first_t == original_t and first_battery == original_battery)
	var held: Dictionary = data.update({ time_s = 2.0, ground_speed = 10.0 }, _battery(900.0, 90.0))
	_check("a repeated timestamp while paused returns the same estimate", held == partial, str(held))

	var high_soc := NavigationData.new()
	var low_soc := NavigationData.new()
	var high_result := {}
	var low_result := {}
	for i in range(0, 21):
		var telemetry := { time_s = float(i) * 0.1, ground_speed = 10.0 }
		high_result = high_soc.update(telemetry, _battery(360.0, 36.0, "pack_ecm", true, 0.95))
		low_result = low_soc.update(telemetry, _battery(360.0, 36.0, "pack_ecm", true, 0.05))
	_check("efficiency depends on radio power/current, not true SOC", high_result == low_result)


func _test_resets_and_validity() -> void:
	var data := NavigationData.new()
	var result: Dictionary = _feed(data, 0, 20)
	_check("valid contiguous cruise establishes an estimate", result.valid)
	result = data.update({ time_s = 2.0, ground_speed = 10.0 }, _battery(360.0, 36.0, "pack_ecm", false))
	_check("invalid battery at a paused timestamp breaks and clears the window", not result.valid and result.sample_seconds == 0.0
		and is_nan(result.efficiency_wh_km))
	result = _feed(data, 0, 20)
	result = data.update({ time_s = 2.1, ground_speed = 10.0 }, _battery(360.0, 36.0, "glow", true))
	_check("non-electric battery readings are refused", not result.valid and result.sample_seconds == 0.0)

	result = _feed(data, 0, 20)
	result = data.update({ time_s = 2.1, ground_speed = 2.99 }, _battery())
	_check("speed below three metres per second breaks the cruise window", not result.valid and result.sample_seconds == 0.0)
	result = data.update({ time_s = 2.2, ground_speed = 10.0 }, _battery())
	_check("cruise restarts from a fresh first sample after taxi", not result.valid and result.sample_seconds == 0.0)

	result = _feed(data, 0, 20)
	result = data.update({ time_s = 3.2, ground_speed = 10.0 }, _battery())
	_check("a sample gap greater than one second resets the window", not result.valid and result.sample_seconds == 0.0)
	result = data.update({ time_s = 0.0, ground_speed = 10.0 }, _battery())
	_check("time rewind resets and starts a new sample", not result.valid and result.sample_seconds == 0.0)

	var no_current := NavigationData.new()
	result = no_current.update({ time_s = 0.0, ground_speed = 10.0 }, _battery(360.0, NAN))
	_check("nonfinite current is an invalid electric reading", not result.valid and result.sample_seconds == 0.0)


func _test_rolling_window_and_bound() -> void:
	var rolling := NavigationData.new()
	var result := _feed(rolling, 0, 200)
	_check("rolling efficiency uses approximately the latest ten seconds", result.valid and _near(result.sample_seconds, 10.0, 1e-7)
		and _near(result.efficiency_wh_km, 10.0), "seconds %.9f efficiency %.6f" % [result.sample_seconds, result.efficiency_wh_km])

	var bounded := NavigationData.new()
	for i in range(0, 181):
		result = bounded.update({ time_s = float(i) * 0.01, ground_speed = 10.0 }, _battery())
	_check("high-frequency calls still cap stored intervals at 120", bounded._segments.size() <= NavigationData.MAX_SEGMENTS,
		"stored %d" % bounded._segments.size())
	_check("bounded history does not claim two seconds after its oldest intervals are discarded",
		not result.valid and result.sample_seconds < 1.3, "%.6f s" % result.sample_seconds)
