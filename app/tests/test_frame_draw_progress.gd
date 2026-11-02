extends SceneTree

const Main := preload("res://main.gd")
const FrameSamples := preload("res://render/frame_samples.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	for streamed in [false, true]:
		_check_case("continuous", streamed, [10, 11, 12], [1, 1, 1], [0, 0, 0], [0, 0, 0], "observed")
		_check_case("no draw", streamed, [10, 10, 10], [1, 1, 1], [0, 0, 0], [0, 0, 0], "no_draw", 0)
		_check_case("partial draw", streamed, [10, 10, 11], [1, 1, 1], [0, 0, 0], [0, 0, 0], "partial_draw")
		_check_case("extra draws do not mask a skipped interval", streamed, [10, 10, 12], [1, 1, 1], [0, 0, 0], [0, 0, 0], "partial_draw")
		_check_case("hidden first frame", streamed, [10, 11, 12], [0, 1, 1], [0, 0, 0], [1, 1, 1], "window_not_drawable")
		_check_case("hidden intermediate frame", streamed, [10, 11, 12], [1, 0, 1], [0, 0, 0], [0, 1, 1], "window_not_drawable")
		_check_case("counter reset", streamed, [10, 1, 12], [1, 1, 1], [0, 1, 1], [0, 0, 0], "counter_reset")
		_check_case("counter went backwards", streamed, [10, 9, 8], [1, 1, 1], [0, 0, 0], [0, 0, 0], "counter_reset")
		_check_case("single sample", streamed, [10], [1], [0], [0], "observed")
		_check_case("first retained interval has no draw after warmup", streamed, [10, 11, 12], [1, 1, 1], [0, 0, 0], [0, 0, 0], "partial_draw", 0)
		_check_case("first retained interval reset after warmup", streamed, [10, 11, 12], [1, 1, 1], [1, 1, 1], [0, 0, 0], "counter_reset", 0, 1)
	var headless: Dictionary = Main._render_progress({"frames": 3}, "headless")
	_check("headless is explicitly separate from a failed native draw", headless.status == "headless")
	var missing: Dictionary = Main._render_progress({"frames": 3, "raw_metrics": {}}, "macOS")
	_check("missing observations do not invent render progress", missing.status == "insufficient_samples")
	print("frame draw progress: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_case(label: String, streamed: bool, drawn: Array, drawable: Array,
		resets: Array, undrawable: Array, expected: String, first_draws: int = 1, first_reset: int = 0) -> void:
	var no_draw: Array[int] = [1 if first_draws == 0 and first_reset == 0 else 0]
	var interval_draws: Array[int] = [first_draws]
	var interval_resets: Array[int] = [first_reset]
	for index in range(1, drawn.size()):
		interval_resets.append(1 if drawn[index] < drawn[index - 1] else 0)
		interval_draws.append(maxi(0, drawn[index] - drawn[index - 1]))
		no_draw.append(no_draw[-1] + (1 if drawn[index] == drawn[index - 1] else 0))
	var metrics := {
		"render_frames_drawn": PackedFloat64Array(drawn),
		"render_interval_draws": PackedFloat64Array(interval_draws),
		"render_interval_counter_reset": PackedFloat64Array(interval_resets),
		"render_window_drawable": PackedFloat64Array(drawable),
		"render_counter_resets": PackedFloat64Array(resets),
		"render_no_draw_intervals": PackedFloat64Array(no_draw),
		"render_undrawable_samples": PackedFloat64Array(undrawable),
	}
	var report := {"frames": drawn.size(), "raw_metrics": metrics}
	if streamed:
		var first := {}
		var last := {}
		for key in metrics:
			first[key] = metrics[key][0]
			last[key] = metrics[key][-1]
		report.format = FrameSamples.STREAM_FORMAT
		report.sample_endpoints = {"first": first, "last": last}
	var progress: Dictionary = Main._render_progress(report, "macOS")
	_check("%s %s" % ["stream" if streamed else "legacy", label], progress.status == expected)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)
