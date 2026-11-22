extends SceneTree

const Policy := preload("res://render/flight_resolution_policy.gd")
const DynamicResolution := preload("res://render/flight_dynamic_resolution.gd")
const FULL := Vector2i(1920, 1080)
const LOWER := Vector2i(1632, 918)
var failures := 0


func _initialize() -> void:
	var policy := Policy.new([LOWER, FULL], 60, 0)
	var request := _feed(policy, 1, 363, 1, FULL, 18_000.0)
	_check(request == 0 and policy.level == 1, "sustained pressure proposes one rung without confirming it")
	_check(policy.observe(_sample(364, 1, FULL, 18_000.0), 364 * 16_667) == -1 and policy.pending_level == 0,
		"an old-generation frame cannot confirm a scale change")
	policy.observe(_sample(365, 2, LOWER, 9_000.0), 365 * 16_667)
	_check(policy.level == 0 and policy.pending_level == -1, "completed work with actual extent confirms the downstep")
	request = _feed(policy, 366, 969, 2, LOWER, 9_000.0)
	_check(request == 1 and policy.level == 0, "sustained headroom proposes recovery after dwell")
	policy.observe(_sample(970, 3, FULL, 9_000.0), 970 * 16_667)
	_check(policy.level == 1 and not policy.retired, "the observed full-size frame confirms recovery to the ceiling")

	var idle := Policy.new([LOWER, FULL], 60, 0)
	_check(_feed(idle, 1, 500, 1, FULL, 6_000.0) == -1 and idle.level == 1, "headroom leaves an existing ceiling intact")
	var cpu_limited := Policy.new([LOWER, FULL], 60, 0)
	for frame: int in range(1, 500):
		var sample := _sample(frame, 1, FULL, 18_000.0)
		sample.recorded_usec = frame * 40_000
		cpu_limited.observe(sample, sample.recorded_usec)
	_check(cpu_limited.pending_level == -1 and cpu_limited.level == 1, "long CPU or pacing intervals suppress reduction")
	var timed_out := Policy.new([LOWER, FULL], 60, 0)
	_feed(timed_out, 1, 363, 1, FULL, 18_000.0)
	timed_out.observe({}, 363 * 16_667 + Policy.APPLY_TIMEOUT_USEC)
	_check(timed_out.retired and timed_out.reason == "apply_timeout", "the deadline retires a missing callback")
	timed_out.observe(_sample(430, 2, LOWER, 9_000.0), 430 * 16_667)
	_check(timed_out.level == 1, "a late receipt cannot revive a retired request")
	var duplicate := Policy.new([LOWER, FULL], 60, 0)
	duplicate.observe(_sample(1, 1, FULL, 18_000.0), 16_667)
	var rewritten := _sample(1, 1, FULL, 18_000.0)
	rewritten.recorded_usec = 150_000
	duplicate.observe(rewritten, 150_000)
	_check(duplicate.retired and duplicate.reason == "gpu_feedback_expired", "duplicate polls cannot refresh completed work")
	var wrong_size := Policy.new([LOWER, FULL], 60, 0)
	_feed(wrong_size, 1, 363, 1, FULL, 18_000.0)
	wrong_size.observe(_sample(364, 2, FULL, 18_000.0), 364 * 16_667)
	_check(wrong_size.retired and wrong_size.reason == "apply_unverified", "a new generation with the wrong dimensions retires")
	if DisplayServer.get_name() == "headless":
		_check(not DynamicResolution.supports(root), "the headless renderer stays fixed")
	print("Flight resolution policy: %d failed" % failures)
	quit(failures)


func _sample(frame: int, generation: int, extent: Vector2i, usec: float) -> Dictionary:
	return {frame_id = frame, generation = generation, recorded_usec = frame * 16_667,
		input_size = extent, gpu_usec = usec}


func _feed(policy: RefCounted, first: int, last: int, generation: int, extent: Vector2i, usec: float) -> int:
	for frame: int in range(first, last + 1):
		var next: int = policy.observe(_sample(frame, generation, extent, usec), frame * 16_667)
		if next >= 0:
			return next
	return -1


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
