## Exact cache reuse and responsive worker boundary for a real electric launch trim.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const CruiseTrim := preload("res://physics/cruise_trim.gd")
const Cache := preload("res://sim/launch_trim_cache.gd")
const TrimJob: Script = preload("res://sim/launch_trim_job.gd")
const TURBO_PATH := "res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"
const G := 9.80665

var _checks := 0
var _failures := 0
var _frames := 0


func _initialize() -> void:
	process_frame.connect(_on_process_frame)
	call_deferred("_run")


func _on_process_frame() -> void:
	_frames += 1


func _run() -> void:
	var loaded: Dictionary = AircraftData.load_file(TURBO_PATH)
	_check("Turbo Lumber pack data loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var model: Dictionary = loaded.model
	var speed: float = float(model.get("start_speed", 15.0))
	var arguments: Array = [speed, 0.5, minf(CruiseTrim.MAX_SEARCH_SPEED_MPS, 2.5 * speed),
		model, G, model.controls.throw_rad, 1.225, 1.0, CruiseTrim.DEFAULT_MAX_ALPHA_RAD]
	var expected: Dictionary = _solve(arguments)
	_check("synchronous reference trim succeeds", expected.get("ok", false), str(expected.get("message", "")))
	if not expected.get("ok", false):
		_finish()
		return
	var expected_bytes: PackedByteArray = var_to_bytes(expected)

	var ownership_cache := Cache.new()
	var ownership_job: Dictionary = ownership_cache.begin_staged_solve(arguments)
	var detached_arguments: Array = ownership_job.get("arguments", [])
	var decoded_bytes_match: bool = detached_arguments.size() == 9 \
		and var_to_bytes(detached_arguments) == var_to_bytes(arguments)
	var detached_model: Dictionary = detached_arguments[3] if detached_arguments.size() == 9 else {}
	var original_mass: float = float(model.get("mass_kg", 0.0))
	if not detached_model.is_empty():
		detached_model["mass_kg"] = original_mass + 1.0
	_check("worker payload is an exact but deeply detached safe round trip",
		ownership_job.get("kind", "") == "worker"
		and detached_arguments.size() == 9
		and decoded_bytes_match
		and float(model.get("mass_kg", 0.0)) == original_mass
		and not is_same(detached_model, model))
	ownership_cache.finish_staged_solve(ownership_job, {}, false)

	var busy_cache := Cache.new()
	var active_reservation: Dictionary = busy_cache.begin_staged_solve(arguments)
	var busy_invalid: Array = arguments.duplicate(true)
	busy_invalid[1] = -1.0
	var busy_resolution: Dictionary = busy_cache.begin_staged_solve(busy_invalid)
	_check("a second request while one worker is reserved uses sync fallback",
		active_reservation.get("kind", "") == "worker"
		and busy_resolution.get("kind", "") == "result"
		and busy_cache.stats().staged_worker_active
		and busy_cache.stats().staged_workers_started == 0
		and not busy_resolution.result.get("ok", true))
	busy_cache.finish_staged_solve(active_reservation, {}, false)

	var generation_cache := Cache.new()
	var stale_job: Dictionary = generation_cache.begin_staged_solve(arguments)
	generation_cache.clear()
	var stale_finished: bool = generation_cache.finish_staged_solve(stale_job, expected, true)
	_check("cache clear blocks a stale in-flight success from repopulating entries",
		stale_finished and not generation_cache.stats().staged_worker_active
		and generation_cache.stats().entries == 0)

	var cache := Cache.new()
	var cold_job: Dictionary = cache.begin_staged_solve(arguments)
	_check("cold staged lookup reserves one detached worker", cold_job.get("kind", "") == "worker"
		and cache.stats().staged_worker_active and cache.stats().misses == 1)
	if cold_job.get("kind", "") != "worker":
		_finish()
		return
	var work: Dictionary = await _run_worker(cache, cold_job)
	var staged_result: Dictionary = work.result
	_check("worker result is exact to the synchronous solver", var_to_bytes(staged_result) == expected_bytes)
	_check("main process frames advanced while the cold solve was alive", int(work.frames) > 0,
		"frames=" + str(work.frames))
	_check("successful validated trim releases reservation and retains one raw result",
		cache.finish_staged_solve(cold_job, staged_result, staged_result.get("ok", false))
		and not cache.stats().staged_worker_active and cache.stats().entries == 1)

	var misses_before_sync_hit: int = int(cache.stats().misses)
	var hits_before_sync_hit: int = int(cache.stats().hits)
	var sync_after_stage: Dictionary = _solve_cache(cache, arguments)
	_check("staged-first result is the exact raw sync cache hit", var_to_bytes(sync_after_stage) == expected_bytes
		and cache.stats().hits == hits_before_sync_hit + 1
		and cache.stats().misses == misses_before_sync_hit)
	var workers_before_hit: int = int(cache.stats().staged_workers_started)
	var hit: Dictionary = cache.begin_staged_solve(arguments)
	_check("normal staged cache hit needs no worker", hit.get("kind", "") == "result"
		and var_to_bytes(hit.result) == expected_bytes
		and cache.stats().staged_workers_started == workers_before_hit)

	var exposed_state: PackedFloat64Array = sync_after_stage.get("state", PackedFloat64Array())
	if not exposed_state.is_empty():
		exposed_state[0] += 123.0
		sync_after_stage.state = exposed_state
	sync_after_stage.cache_probe_mutation = true
	var isolated_hit: Dictionary = _solve_cache(cache, arguments)
	_check("mutating a returned cache result cannot poison the retained raw result",
		var_to_bytes(isolated_hit) == expected_bytes and not isolated_hit.has("cache_probe_mutation"))

	var changed_density: Array = arguments.duplicate(true)
	changed_density[6] = float(changed_density[6]) + 0.001
	var misses_before_invalidation: int = int(cache.stats().misses)
	var changed_job: Dictionary = cache.begin_staged_solve(changed_density)
	_check("one exact solver input change creates a distinct cold key",
		changed_job.get("kind", "") == "worker" and cache.stats().misses == misses_before_invalidation + 1)
	if changed_job.get("kind", "") == "worker":
		cache.finish_staged_solve(changed_job, {}, false)

	var invalid: Array = arguments.duplicate(true)
	invalid[1] = -1.0
	var invalid_job: Dictionary = cache.begin_staged_solve(invalid)
	_check("a safe invalid trim request still takes the worker route", invalid_job.get("kind", "") == "worker")
	if invalid_job.get("kind", "") == "worker":
		var invalid_work: Dictionary = await _run_worker(cache, invalid_job)
		var invalid_result: Dictionary = invalid_work.result
		_check("worker preserves solver failures", not invalid_result.get("ok", true))
		cache.finish_staged_solve(invalid_job, invalid_result, false)
	var misses_before_failed_retry: int = int(cache.stats().misses)
	var invalid_retry: Dictionary = cache.begin_staged_solve(invalid)
	_check("failed worker result is not cached and original entry survives",
		invalid_retry.get("kind", "") == "worker"
		and cache.stats().misses == misses_before_failed_retry + 1
		and cache.stats().entries == 1)
	if invalid_retry.get("kind", "") == "worker":
		cache.finish_staged_solve(invalid_retry, {}, false)
	var original_again: Dictionary = _solve_cache(cache, arguments)
	_check("valid raw result remains reusable after worker failures", var_to_bytes(original_again) == expected_bytes)

	var unsafe: Array = arguments.duplicate(true)
	var unsafe_model: Dictionary = arguments[3].duplicate(true)
	unsafe_model["async_probe_object"] = self
	unsafe[3] = unsafe_model
	unsafe[1] = -1.0 # Bounded failure while verifying the object-bearing input never reaches a worker.
	var bypasses_before: int = int(cache.stats().bypasses)
	var unsafe_resolution: Dictionary = cache.begin_staged_solve(unsafe)
	_check("unsafe input keeps synchronous behavior without reserving a worker",
		unsafe_resolution.get("kind", "") == "sync"
		and not cache.stats().staged_worker_active
		and cache.stats().bypasses == bypasses_before + 1
		and not unsafe_resolution.result.get("ok", true))

	print("Launch trim async fixture: %d checks, %d failed; stats=%s" % [
		_checks, _failures, str(cache.stats())])
	_finish()


func _run_worker(cache: Variant, job: Dictionary) -> Dictionary:
	var worker := Thread.new()
	var arguments: Array = job.arguments.duplicate(true)
	var start_error: Error = worker.start(Callable(TrimJob, "solve").bind(arguments))
	_check("Godot starts the detached static trim job", start_error == OK, str(start_error))
	if start_error != OK:
		var fallback: Dictionary = cache.solve_staged_synchronously(job)
		cache.finish_staged_solve(job, fallback, false)
		return {result = fallback, frames = 0}
	_check("cache records a successfully started worker", cache.staged_worker_started(job))
	var frames_before: int = _frames
	while worker.is_alive():
		await process_frame
	var result: Variant = worker.wait_to_finish()
	_check("worker returns a plain Dictionary", typeof(result) == TYPE_DICTIONARY)
	return {result = result if typeof(result) == TYPE_DICTIONARY else {}, frames = _frames - frames_before}


func _solve(arguments: Array) -> Dictionary:
	return CruiseTrim.solve_level_at_throttle(float(arguments[0]), float(arguments[1]),
		float(arguments[2]), arguments[3], float(arguments[4]), arguments[5],
		float(arguments[6]), float(arguments[7]), float(arguments[8]))


func _solve_cache(cache: Variant, arguments: Array) -> Dictionary:
	return cache.solve_level_at_throttle(float(arguments[0]), float(arguments[1]),
		float(arguments[2]), arguments[3], float(arguments[4]), arguments[5],
		float(arguments[6]), float(arguments[7]), float(arguments[8]))


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	push_error("FAIL: " + label + (" — " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	quit(1 if _failures > 0 else 0)
