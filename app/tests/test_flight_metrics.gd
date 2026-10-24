# HUD-13: bounded flight aggregates and guarded instantaneous ground-glide ratio.
extends SceneTree

const FlightMetrics := preload("res://render/overlays/flight_metrics.gd")

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
	_test_distance_extrema_and_pause()
	_test_partial_resets()
	_test_unknown_extrema_and_reset()
	_test_ground_glide()
	print("flight metrics: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _sample(time_s: float, ground_speed := 10.0, load_factor := 1.0, height_agl := 10.0,
		vertical_speed := -2.0, throttle := 0.0, bank_deg := 0.0) -> Dictionary:
	return {
		time_s = time_s,
		ground_speed = ground_speed,
		load_factor = load_factor,
		height_agl = height_agl,
		vertical_speed = vertical_speed,
		throttle = throttle,
		bank_deg = bank_deg,
	}


func _test_distance_extrema_and_pause() -> void:
	var metrics := FlightMetrics.new()
	var result := {}
	for second in range(0, 11):
		var load := -1.5 if second == 4 else (2.5 if second == 7 else 1.0)
		var height := 30.0 if second == 8 else float(second)
		result = metrics.update(_sample(float(second), 10.0, load, height))
	_check("10 m/s for 10 seconds integrates to 100 m", _near(result.distance_m, 100.0) and not result.distance_partial,
		"distance %.6f partial=%s" % [result.distance_m, str(result.distance_partial)])
	_check("finite negative and positive load extrema are sampled", _near(result.min_load_factor, -1.5) and _near(result.max_load_factor, 2.5),
		"min %.3f max %.3f" % [result.min_load_factor, result.max_load_factor])
	_check("maximum finite AGL is retained", _near(result.max_height_agl, 30.0), str(result.max_height_agl))

	# A changed but duplicate timestamp is a paused snapshot, even when its values are now invalid/extreme.
	var paused: Dictionary = metrics.update(_sample(10.0, NAN, -9.0, 9000.0))
	_check("paused duplicate with invalid speed does not add distance or mark partial", _near(paused.distance_m, 100.0)
		and not paused.distance_partial)
	_check("paused duplicate does not alter sampled extrema", _near(paused.min_load_factor, -1.5)
		and _near(paused.max_load_factor, 2.5) and _near(paused.max_height_agl, 30.0))
	result = metrics.update(_sample(10.1, 10.0, 0.5, 31.0))
	_check("next timestamp integrates from the last accepted paused sample", _near(result.distance_m, 101.0))


func _test_partial_resets() -> void:
	var delayed := FlightMetrics.new()
	var result: Dictionary = delayed.update({})
	_check("empty preflight snapshot before the first timestamp does not poison distance", not result.distance_partial)
	result = delayed.update(_sample(0.0, 10.0))
	_check("normal sampling from time zero starts complete", not result.distance_partial)

	var late_start := FlightMetrics.new()
	result = late_start.update(_sample(1.01, 10.0))
	_check("first sample after one second marks unobserved initial distance partial", result.distance_partial and result.distance_m == 0.0)
	result = late_start.update(_sample(1.11, 10.0))
	_check("late-start sampling still accumulates observed intervals", result.distance_partial and _near(result.distance_m, 1.0))

	var metrics := FlightMetrics.new()
	metrics.update(_sample(0.0, 10.0))
	result = metrics.update(_sample(0.2, NAN, -2.0, 25.0))
	_check("invalid speed keeps the valid previous-speed interval and marks later distance partial", result.distance_partial
		and _near(result.distance_m, 2.0))
	result = metrics.update(_sample(0.3, 10.0))
	_check("first valid sample after invalid speed starts a new baseline", result.distance_partial and _near(result.distance_m, 2.0))
	result = metrics.update(_sample(0.4, 10.0))
	_check("later valid intervals integrate while partial remains permanent", result.distance_partial and _near(result.distance_m, 3.0))

	var gap := FlightMetrics.new()
	gap.update(_sample(0.0, 10.0))
	result = gap.update(_sample(1.01, 10.0))
	_check("gap over one second is skipped and marks distance partial", result.distance_partial and _near(result.distance_m, 0.0))
	result = gap.update(_sample(1.11, 10.0))
	_check("distance resumes from the post-gap baseline without hiding partial status", result.distance_partial
		and _near(result.distance_m, 1.0))

	var rewind := FlightMetrics.new()
	for step in range(0, 21):
		result = rewind.update(_sample(float(step) * 0.1, 10.0, 3.0, 80.0))
	_check("pre-rewind aggregate has distance and extrema", result.distance_m > 19.9 and result.max_height_agl == 80.0)
	result = rewind.update(_sample(0.0, 5.0, -2.0, 12.0))
	_check("time rewind resets the whole aggregate then accepts a new baseline", _near(result.distance_m, 0.0)
		and not result.distance_partial and _near(result.min_load_factor, -2.0) and _near(result.max_load_factor, -2.0)
		and _near(result.max_height_agl, 12.0), str(result))


func _test_unknown_extrema_and_reset() -> void:
	var metrics := FlightMetrics.new()
	var result: Dictionary = metrics.update(_sample(0.0, 10.0, NAN, NAN))
	_check("unsampled finite extrema remain NAN", is_nan(result.min_load_factor) and is_nan(result.max_load_factor)
		and is_nan(result.max_height_agl))
	result = metrics.update(_sample(0.1, 10.0, -2.0, 22.0))
	result = metrics.update(_sample(0.2, 10.0, 3.0, 18.0))
	_check("negative-g minimum and maximum AGL update independently", _near(result.min_load_factor, -2.0)
		and _near(result.max_load_factor, 3.0) and _near(result.max_height_agl, 22.0))
	metrics.reset()
	result = metrics.update(_sample(0.0, 10.0, NAN, NAN))
	_check("explicit reset clears distance, partial status and extrema", result.distance_m == 0.0
		and not result.distance_partial and is_nan(result.min_load_factor) and is_nan(result.max_load_factor)
		and is_nan(result.max_height_agl))


func _test_ground_glide() -> void:
	var steady := _sample(1.0, 20.0, 1.0, 100.0, -2.0, 0.0, 0.0)
	var before := steady.duplicate(true)
	var result: Dictionary = FlightMetrics.glide(steady)
	_check("20 m/s at 2 m/s sink is ground glide ratio 10", result.glide_status == "gliding"
		and _near(result.ground_glide_ratio, 10.0), str(result))
	_check("glide calculation does not mutate telemetry", steady == before)

	var powered := FlightMetrics.glide(_sample(0.0, 2.0, 1.0, 10.0, 0.0, 0.051, 45.0))
	var turning := FlightMetrics.glide(_sample(0.0, 2.0, 1.0, 10.0, 0.0, 0.05, 20.01))
	var slow := FlightMetrics.glide(_sample(0.0, 2.99, 1.0, 10.0, 0.0, 0.05, 20.0))
	var not_descending := FlightMetrics.glide(_sample(0.0, 3.0, 1.0, 10.0, -0.2, 0.05, 20.0))
	_check("status priority reports powered before turn or speed", powered.glide_status == "powered" and is_nan(powered.ground_glide_ratio))
	_check("turning takes priority over slow and sink guards", turning.glide_status == "turning")
	_check("slow precedes not-descending", slow.glide_status == "slow")
	_check("sink threshold is strict at -0.2 m/s", not_descending.glide_status == "not_descending")

	var boundary := FlightMetrics.glide(_sample(0.0, 3.0, 1.0, 10.0, -0.21, 0.05, -20.0))
	_check("exact speed, throttle and bank limits permit an unpowered glide", boundary.glide_status == "gliding"
		and _near(boundary.ground_glide_ratio, 3.0 / 0.21))
	var unavailable := FlightMetrics.glide(_sample(0.0, NAN, 1.0, 10.0, -2.0, 0.1, 0.0))
	_check("missing required glide input is unavailable before other statuses", unavailable.glide_status == "unavailable"
		and is_nan(unavailable.ground_glide_ratio))
	var negative_speed := FlightMetrics.glide(_sample(0.0, -1.0, 1.0, 10.0, -2.0, 0.0, 0.0))
	var invalid_throttle := FlightMetrics.glide(_sample(0.0, 20.0, 1.0, 10.0, -2.0, 1.01, 0.0))
	_check("negative speed and out-of-range throttle are unavailable", negative_speed.glide_status == "unavailable"
		and invalid_throttle.glide_status == "unavailable")
