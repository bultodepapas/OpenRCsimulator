## One cache-owned numeric worker, exact-key adoption, invalidation and final-validation publication.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Cache := preload("res://sim/launch_trim_cache.gd")
const TrimJob := preload("res://sim/launch_trim_job.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Cruise := preload("res://physics/cruise_trim.gd")
const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const ID := "jensen-das-ugly-stik-60"

class RejectFlight:
	extends "res://sim/flight_session.gd"

	func _candidate_loads_are_valid(_model: Dictionary, _candidate_start: Dictionary, _candidate_trims: Dictionary) -> bool:
		return false


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = AircraftData.load_file(PATH)
	_check("real aircraft data loads", loaded.get("ok", false))
	if not loaded.get("ok", false):
		_finish()
		return
	var model: Dictionary = loaded.model
	var speed: float = model.start_speed
	var args: Array = [speed, -1.0, minf(Cruise.MAX_SEARCH_SPEED_MPS, 2.5 * speed), model,
		9.80665, model.controls.throw_rad, 1.225, 1.0, Cruise.DEFAULT_MAX_ALPHA_RAD]
	await _check_managed_ownership(args)
	await _check_generation_and_abandon(args)
	await _check_foreground_bypass(args)
	await _check_split_transactions()
	await _check_split_busy_cancel()
	await _check_session_adoption()
	await _check_final_validation_rejection()
	await _check_destroyed_consumer()
	print("Menu trim preparation: %d checks, %d failed" % [_checks, _failures])
	_finish()


func _check_managed_ownership(args: Array) -> void:
	var cache := Cache.new()
	var first: Dictionary = cache.acquire_managed(args, true)
	_check("menu starts one managed job", first.kind == "pending" and cache.stats().menu_starts == 1)
	if first.kind != "pending":
		return
	var job: RefCounted = first.job
	var thread: Thread = job.thread
	var changed: Array = args.duplicate(true)
	changed[1] = -0.9
	var skip: Dictionary = cache.acquire_managed(changed, true)
	_check("B speculation skips while useful A remains owned by menu", skip.kind == "skipped"
		and cache.stats().managed_owner == "menu" and cache.stats().staged_workers_started == 1)
	var adopted: Dictionary = cache.acquire_managed(args)
	_check("A to B to A adopts the identical job and thread", adopted.kind == "pending"
		and is_same(adopted.job, job) and is_same(adopted.job.thread, thread)
		and adopted.ticket.token == first.ticket.token and cache.stats().menu_adoptions == 1)
	var joined_before: bool = job.joined
	var menu_status: Dictionary = cache.poll_menu()
	_check("menu poll cannot join or clear an adopted job", menu_status.active and menu_status.adopted
		and job.joined == joined_before and cache.stats().managed_owner == "flight")
	cache.abandon_menu()
	_check("menu abandon cannot cancel adopted flight", cache.stats().managed_owner == "flight")
	var progress: Dictionary = await _drain_flight(cache, adopted)
	_check("managed worker preserves raw solver result exactly", var_to_bytes(progress.result) == var_to_bytes(TrimJob.solve(args)))
	cache.finish_managed(adopted, false)
	_check("rejected worker result leaves no shared entry or worker", not cache.menu_busy() and cache.stats().entries == 0)


func _check_generation_and_abandon(args: Array) -> void:
	var cache := Cache.new()
	var old: Dictionary = cache.acquire_managed(args, true)
	cache.clear()
	var next: Dictionary = cache.acquire_managed(args)
	_check("clear prevents adoption of a matching stale-generation job", next.kind == "wait"
		or (next.kind == "pending" and not is_same(next.job, old.job)))
	while next.kind == "wait":
		await process_frame
		next = cache.acquire_managed(args)
	_check("replacement uses a fresh reservation after draining", next.kind == "pending"
		and next.ticket.token != old.ticket.token and cache.stats().menu_adoptions == 0)
	if next.kind == "pending":
		await _drain_flight(cache, next)
		cache.finish_managed(next, false)
	_check("generation invalidation never publishes stale success", cache.stats().entries == 0 and not cache.menu_busy())
	var abandoned: Dictionary = cache.acquire_managed(args, true)
	cache.abandon_menu()
	while cache.menu_busy():
		cache.poll_menu()
		await process_frame
	_check("abandoned unadopted worker drains without publication", not cache.menu_busy()
		and cache.stats().entries == 0 and cache.stats().menu_discarded >= 2 and abandoned.kind == "pending")


func _check_foreground_bypass(args: Array) -> void:
	var cache := Cache.new()
	var oversized: Array = args.duplicate(true)
	oversized[1] = 0.5
	oversized[3]["unused_large_metadata"] = "x".repeat(Cache.MAX_RETAINED_KEY_BYTES + 1)
	var menu: Dictionary = cache.acquire_managed(oversized, true)
	_check("oversized numeric key skips menu worker", menu.kind == "skipped" and not cache.menu_busy())
	var foreground: Dictionary = cache.acquire_managed(oversized)
	_check("oversized key retains synchronous foreground semantics", foreground.kind == "result"
		and var_to_bytes(foreground.result) == var_to_bytes(TrimJob.solve(oversized)) and not cache.menu_busy())
	var reserved: Dictionary = cache.acquire_managed(args, true)
	foreground = cache.acquire_managed(oversized)
	while foreground.kind == "wait":
		_check("foreground bypass never duplicates a busy numeric worker", cache.stats().staged_workers_started == 1)
		await process_frame
		foreground = cache.acquire_managed(oversized)
	_check("foreground fallback follows the abandoned worker drain", foreground.kind == "result"
		and not cache.menu_busy() and reserved.kind == "pending")


func _check_split_transactions() -> void:
	Flight._launch_trim_cache.clear()
	var wrapper := Flight.new()
	wrapper.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	wrapper.soft_hull_contacts = true
	var never_cancel: Callable = func() -> bool: return false
	var completed: bool = await wrapper.setup_staged(PATH, ID, {}, process_frame, never_cancel)
	var baseline_start: PackedByteArray = var_to_bytes(wrapper.start)
	var baseline_checkpoint: Dictionary = wrapper.checkpoint()
	_check("wrapper creates a valid reference checkpoint", completed and wrapper.is_flyable()
		and not baseline_checkpoint.is_empty(), wrapper.start_error)
	wrapper.free()
	Flight._launch_trim_cache.clear()
	var split := Flight.new()
	split.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	split.soft_hull_contacts = true
	var begun: bool = split.begin_staged_setup(PATH, ID, {}, never_cancel)
	var detached: Node = split.sim
	var before_duplicate: Dictionary = Flight.launch_trim_cache_stats()
	_check("begin leaves aircraft and start private with a detached Simulation", begun and detached != null
		and detached.get_parent() == null and split.aircraft.is_empty() and split.start.is_empty()
		and not split.is_flyable())
	_check("begin owns one private worker without publishing", before_duplicate.entries == 0
		and before_duplicate.managed_owner == "flight" and before_duplicate.staged_workers_started == 1
		and not split._staged_trim_job.is_empty())
	_check("duplicate begin preserves the original preparation", not split.begin_staged_setup(PATH, ID, {}, never_cancel)
		and is_same(split.sim, detached) and Flight.launch_trim_cache_stats().managed_token == before_duplicate.managed_token
		and Flight.launch_trim_cache_stats().staged_workers_started == 1)
	completed = await split.finish_staged_setup(process_frame, never_cancel)
	_check("finish commits exactly the wrapper start and checkpoint", completed and split.is_flyable()
		and split.sim.get_parent() == split and var_to_bytes(split.start) == baseline_start
		and not split.checkpoint().is_empty() and var_to_bytes(split.checkpoint()) == var_to_bytes(baseline_checkpoint), split.start_error)
	_check("finish publishes only after validation", Flight.launch_trim_cache_stats().entries == 1
		and not Flight.menu_trim_busy())
	var duplicate_finish: bool = await split.finish_staged_setup(process_frame, never_cancel)
	_check("duplicate finish and begin refuse a completed setup", not duplicate_finish
		and not split.begin_staged_setup(PATH, ID, {}, never_cancel) and split.sim.get_parent() == split)
	split.free()
	Flight._launch_trim_cache.clear()

	var cancelled_early := Flight.new()
	cancelled_early.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	_check("cancellation before preflight starts no worker", not cancelled_early.begin_staged_setup(PATH, ID, {},
		func() -> bool: return true) and cancelled_early.sim == null
		and Flight.launch_trim_cache_stats().staged_workers_started == 0 and not Flight.menu_trim_busy())
	cancelled_early.free()
	var cancelled_before_worker := Flight.new()
	cancelled_before_worker.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	var preflight_cancel := {calls = 0}
	var cancel_before_acquire: Callable = func() -> bool:
		preflight_cancel.calls += 1
		return preflight_cancel.calls >= 5
	_check("cancellation after preflight starts no worker", not cancelled_before_worker.begin_staged_setup(PATH, ID, {}, cancel_before_acquire)
		and cancelled_before_worker.sim == null and cancelled_before_worker._staged_preflight.is_empty()
		and Flight.launch_trim_cache_stats().staged_workers_started == 0 and not Flight.menu_trim_busy())
	cancelled_before_worker.free()
	var cancelled := Flight.new()
	cancelled.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	cancelled.soft_hull_contacts = true
	_check("cancellation fixture begins before world construction", cancelled.begin_staged_setup(PATH, ID, {}, never_cancel)
		and not cancelled._staged_trim_job.is_empty())
	await cancelled.cancel_staged_setup(process_frame)
	_check("cancel drains the owned job without publishing or committing", cancelled.sim == null
		and cancelled.aircraft.is_empty() and cancelled.start.is_empty() and not Flight.menu_trim_busy()
		and Flight.launch_trim_cache_stats().entries == 0)
	var cancelled_finish: bool = await cancelled.finish_staged_setup(process_frame, never_cancel)
	_check("finish after cancellation cannot commit", not cancelled_finish)
	cancelled.free()
	Flight._launch_trim_cache.clear()

	var invalid := Flight.new()
	invalid.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	begun = invalid.begin_staged_setup(PATH, "wrong-aircraft-id", {}, never_cancel)
	_check("invalid preflight stays private until finish", begun and invalid.sim != null
		and invalid.sim.get_parent() == null and invalid.aircraft.is_empty() and invalid.start.is_empty()
		and not Flight.menu_trim_busy() and Flight.launch_trim_cache_stats().entries == 0)
	completed = await invalid.finish_staged_setup(process_frame, never_cancel)
	_check("invalid preflight completes with the normal invalid session", completed and not invalid.is_flyable()
		and invalid.sim.get_parent() == invalid and not invalid.start_error.is_empty()
		and Flight.launch_trim_cache_stats().entries == 0)
	invalid.free()
	Flight._launch_trim_cache.clear()


func _check_split_busy_cancel() -> void:
	Flight._launch_trim_cache.clear()
	var first: Dictionary = Flight.prepare_menu_trim(PATH, ID)
	var other := Flight.new()
	other.trim_throttle = 0.6 # a distinct key cannot adopt the menu's half-throttle result
	other.soft_hull_contacts = true
	var begun: bool = other.begin_staged_setup(PATH, ID, {}, func() -> bool: return false)
	var kind: String = str(other._staged_resolution.get("kind", ""))
	var starts_before: int = Flight.launch_trim_cache_stats().staged_workers_started
	_check("different-key begin never adopts the menu job", first.kind == "pending" and begun
		and Flight.launch_trim_cache_stats().menu_adoptions == 0 and kind in ["wait", "pending", "result"])
	await other.cancel_staged_setup(process_frame)
	_check("cancelling busy preparation starts no additional solve", other.sim == null
		and Flight.launch_trim_cache_stats().staged_workers_started == starts_before
		and Flight.launch_trim_cache_stats().entries == 0)
	other.free()
	while Flight.menu_trim_busy():
		Flight.poll_menu_trim()
		await process_frame
	_check("busy foreign job eventually drains without publication", Flight.launch_trim_cache_stats().entries == 0)
	Flight._launch_trim_cache.clear()


func _check_session_adoption() -> void:
	Flight._launch_trim_cache.clear()
	var baseline := Flight.new()
	baseline.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	baseline.soft_hull_contacts = true
	baseline.setup(PATH, ID)
	_check("synchronous product launch prepares", baseline.is_flyable(), baseline.start_error)
	var baseline_start: PackedByteArray = var_to_bytes(baseline.start)
	var baseline_state: PackedByteArray = var_to_bytes(baseline.sim.state)
	baseline.free()
	Flight._launch_trim_cache.clear()
	var nodes_before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var first: Dictionary = Flight.prepare_menu_trim(PATH, ID)
	_check("menu request starts detached numeric preparation", first.kind == "pending")
	_check("temporary Session and Simulation are freed before returning to Home",
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes_before)
	var token: int = Flight._launch_trim_cache.stats().managed_token
	while not Flight.poll_menu_trim().complete:
		await process_frame
	_check("completed speculation is still private", Flight._launch_trim_cache.stats().entries == 0
		and Flight.menu_trim_busy() and Flight._launch_trim_cache.stats().managed_token == token)
	var selected := Flight.new()
	selected.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	selected.soft_hull_contacts = true
	var begun: bool = selected.begin_staged_setup(PATH, ID, {}, func() -> bool: return false)
	_check("split begin adopts the completed same-key menu job privately", begun and selected.aircraft.is_empty()
		and selected.start.is_empty() and selected.sim.get_parent() == null
		and Flight._launch_trim_cache.stats().managed_token == token
		and Flight._launch_trim_cache.stats().entries == 0)
	var completed: bool = await selected.finish_staged_setup(process_frame, func() -> bool: return false)
	_check("foreground adopts completed same-key result and passes full validation", completed and selected.is_flyable()
		and Flight._launch_trim_cache.stats().menu_adoptions == 1
		and Flight._launch_trim_cache.stats().staged_workers_started == 1, selected.start_error)
	_check("adopted launch state and trim are byte-exact to synchronous launch", var_to_bytes(selected.start) == baseline_start
		and var_to_bytes(selected.sim.state) == baseline_state)
	_check("only validated adopted result is published", Flight._launch_trim_cache.stats().entries == 1 and not Flight.menu_trim_busy())
	selected.free()
	Flight._launch_trim_cache.clear()
	var invalid: Dictionary = Flight.prepare_menu_trim(PATH, "wrong-aircraft-id")
	_check("identity mismatch rejects speculation before worker", invalid.kind == "invalid" and not Flight.menu_trim_busy())
	# A cancelled flight drains its adopted worker before returning, even without a menu coordinator.
	Flight.prepare_menu_trim(PATH, ID)
	var cancel_session := Flight.new()
	cancel_session.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	cancel_session.soft_hull_contacts = true
	var cancel_at := {calls = 0}
	var should_cancel: Callable = func() -> bool:
		cancel_at.calls += 1
		return cancel_at.calls >= 6
	completed = await cancel_session.setup_staged(PATH, ID, {}, process_frame, should_cancel)
	_check("cancelled adopted launch drains worker and frees its Simulation", not completed and cancel_session.sim == null
		and not Flight.menu_trim_busy())
	cancel_session.free()
	while Flight.menu_trim_busy():
		Flight.poll_menu_trim()
		await process_frame
	_check("cancelled adopted worker drains without cache insertion", Flight._launch_trim_cache.stats().entries == 0)
	Flight._launch_trim_cache.clear()


func _check_final_validation_rejection() -> void:
	Flight._launch_trim_cache.clear()
	Flight.prepare_menu_trim(PATH, ID)
	var session := RejectFlight.new()
	session.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	session.soft_hull_contacts = true
	var begun: bool = session.begin_staged_setup(PATH, ID, {}, func() -> bool: return false)
	_check("final-validation fixture stays private after begin", begun and session.aircraft.is_empty()
		and session.start.is_empty() and Flight.launch_trim_cache_stats().entries == 0)
	var completed: bool = await session.finish_staged_setup(process_frame, func() -> bool: return false)
	_check("full candidate validation rejects an otherwise successful adopted numeric result", completed and not session.is_flyable()
		and "initial loads" in session.start_error, session.start_error)
	_check("failed final validation never publishes speculative success", Flight.launch_trim_cache_stats().entries == 0
		and not Flight.menu_trim_busy() and Flight.launch_trim_cache_stats().staged_workers_started == 1)
	session.free()
	Flight._launch_trim_cache.clear()


func _check_destroyed_consumer() -> void:
	Flight._launch_trim_cache.clear()
	var session := Flight.new()
	session.trim_throttle = Flight.CRUISE_TRIM_THROTTLE
	session.soft_hull_contacts = true
	# Begin owns the worker while Simulation remains detached; raw destruction must release both.
	session.begin_staged_setup(PATH, ID, {}, func() -> bool: return false)
	_check("fresh foreground worker is flight-owned before destruction", Flight.launch_trim_cache_stats().managed_owner == "flight"
		and not session._staged_trim_job.is_empty())
	var detached: WeakRef = weakref(session.sim)
	session.free()
	_check("raw free destroys the detached Simulation", detached.get_ref() == null)
	# No menu coordinator and no manual poll: only the cache's bounded abandoned-job callback runs.
	var frames := 0
	while Flight.menu_trim_busy() and frames < 18000:
		frames += 1
		await process_frame
	_check("destroyed foreground consumer drains independently of AppRoot", not Flight.menu_trim_busy()
		and Flight.launch_trim_cache_stats().entries == 0)
	Flight._launch_trim_cache.clear()


func _drain_flight(cache: RefCounted, resolution: Dictionary) -> Dictionary:
	var progress: Dictionary = cache.poll_managed(resolution)
	while not progress.complete:
		await process_frame
		progress = cache.poll_managed(resolution)
	return progress


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: " + label + (" -- " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	quit(1 if _failures > 0 else 0)
