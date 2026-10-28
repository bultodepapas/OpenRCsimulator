## UI-34c: staged Home → Fly startup, duplicate actions, cancellation and recovery.
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const PREFS := "user://test_flight_loading.cfg"
const ALTERNATE_AIRCRAFT := "sebart-avanti-s-a200-p100rx"


class SceneLoadGate extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()

	func load_scene(path: String, type_hint: String) -> Resource:
		entered.post()
		release.wait()
		return ResourceLoader.load(path, type_hint)


## Holds observation of an existing worker's completion without starting another worker.
class HeldTrimPoll extends RefCounted:
	var original: RefCounted
	var released := false
	var owner: String:
		get:
			return str(original.owner)
		set(value):
			original.owner = value
	var complete: bool:
		get:
			return bool(original.complete)

	func poll() -> bool:
		return original.poll() if released else false

	func result_copy() -> Dictionary:
		return original.result_copy()


class UnavailableSceneLoad extends "res://ui/flight_scene_load.gd":
	func start(_path: String) -> Error:
		complete = true
		return ERR_CANT_CREATE


class RejectedFlight extends Node:
	var startup_error := "Intentional startup rejection"
	var recorder: Node
	var session: Node

	func _set(_property: StringName, _value: Variant) -> bool:
		return true


## Hold the real Main before building the world, after the numeric transaction begins.
class WorldGateFlight extends "res://main.gd":
	const SessionScript := preload("res://sim/flight_session.gd")
	var entered_world_gate := false
	var release_world_gate := false
	var reject_world := false
	var private_state_valid := false
	var prepared_session_id := 0
	var prepared_session_ref: WeakRef
	var prepared_sim_ref: WeakRef
	var gate_stats: Dictionary = {}

	func _build_world() -> bool:
		entered_world_gate = true
		gate_stats = SessionScript.launch_trim_cache_stats().duplicate(true)
		if is_instance_valid(_preparing_session):
			prepared_session_id = _preparing_session.get_instance_id()
			prepared_session_ref = weakref(_preparing_session)
			if is_instance_valid(_preparing_session.sim):
				prepared_sim_ref = weakref(_preparing_session.sim)
				private_state_valid = session == null and _preparing_session.get_parent() == null \
					and _preparing_session.sim.get_parent() == null and _preparing_session.sim.tick == 0
		while not release_world_gate and not _startup_cancel_requested():
			await get_tree().process_frame
		if _startup_cancel_requested():
			return false
		if reject_world:
			startup_error = "Intentional world build rejection"
			return false
		return await super._build_world()


class TrackedApp extends "res://app_root.gd":
	const SessionScript := preload("res://sim/flight_session.gd")
	var flight_creations := 0
	var scene_job_creations := 0
	var scene_load_gate: SceneLoadGate
	var scene_thread_unavailable := false
	var reject_next_flight := false
	var use_world_gate := false
	var reject_world := false
	var rejected_candidate_ref: WeakRef
	var rejected_candidate_session_was_null := false
	var quit_candidate_instance_id := 0
	var quit_prepared_session_ref: WeakRef
	var quit_prepared_sim_ref: WeakRef
	var quit_commit_calls := 0
	var quit_commit_state: Dictionary = {}

	func _new_flight_scene_load() -> Node:
		scene_job_creations += 1
		if scene_thread_unavailable:
			return UnavailableSceneLoad.new()
		var job: Node = super._new_flight_scene_load()
		if scene_load_gate != null:
			job.load_resource = scene_load_gate.load_scene
		return job

	func _create_flight(aircraft_id: String = "") -> Node:
		flight_creations += 1
		if reject_next_flight:
			reject_next_flight = false
			var rejected := RejectedFlight.new()
			rejected_candidate_ref = weakref(rejected)
			rejected_candidate_session_was_null = rejected.session == null
			return rejected
		if use_world_gate:
			var gated := WorldGateFlight.new()
			gated.reject_world = reject_world
			return gated
		return super._create_flight(aircraft_id)

	func _commit_app_quit() -> void:
		quit_commit_calls += 1
		var candidate: Object = instance_from_id(quit_candidate_instance_id) if quit_candidate_instance_id > 0 else null
		quit_commit_state = {
			"loading_active": _loading_active,
			"flight_cleared": flight == null,
			"loading_screen_absent": screens.get_screen("loading") == null,
			"home_top": screens.is_top("home"),
			"home_attached": home != null and home.is_inside_tree(),
			"home_scene_attached": is_instance_valid(home_scene) and home_scene.is_inside_tree(),
			"candidate_disposal_scheduled": not is_instance_valid(candidate)
				or (candidate is Node and candidate.is_queued_for_deletion()),
			"prepared_session_gone": quit_prepared_session_ref != null and quit_prepared_session_ref.get_ref() == null,
			"prepared_sim_gone": quit_prepared_sim_ref != null and quit_prepared_sim_ref.get_ref() == null,
			"trim_busy": SessionScript.menu_trim_busy(),
			"trim_stats": SessionScript.launch_trim_cache_stats().duplicate(true),
			"status": str(last_flight_loading.get("status", "")),
		}


class QuitPreparationApp extends "res://app_root.gd":
	var gate: SceneLoadGate
	var quit_requested_count := 0
	var quit_preparation: Dictionary = {}

	func _new_flight_scene_load() -> Node:
		var job: Node = super._new_flight_scene_load()
		job.load_resource = gate.load_scene
		return job

	func _request_app_quit() -> void:
		quit_requested_count += 1
		quit_preparation = home_flight_preparation.duplicate(true)


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)


func _frames(count: int = 4) -> void:
	for _index in count:
		await process_frame


func _wait_phase(app: TrackedApp, phase: String, max_frames: int = 1800) -> bool:
	for _index in max_frames:
		if app._loading_phase == phase:
			return true
		if not app._loading_active:
			return false
		await process_frame
	return app._loading_phase == phase


func _wait_idle(app: TrackedApp, max_frames: int = 1800) -> bool:
	for _index in max_frames:
		if not app._loading_active:
			return true
		await process_frame
	return not app._loading_active


func _wait_quit_commit(app: TrackedApp, max_frames: int = 2400) -> bool:
	for _index in max_frames:
		if app.quit_commit_calls > 0:
			return true
		await process_frame
	return app.quit_commit_calls > 0


func _wait_scene_worker(app: TrackedApp, gate: SceneLoadGate) -> bool:
	for _index in 2400:
		if gate.entered.try_wait():
			return is_instance_valid(app._loading_scene_job) and not app._loading_scene_job.complete
		if not app._loading_active:
			return false
		await process_frame
	return false


func _contains_phase(phases: Array, expected: String) -> bool:
	for phase: Variant in phases:
		if phase is Dictionary and str(phase.get("stage", "")) == expected:
			return true
	return false


func _clear_test_files() -> void:
	for path: String in [PREFS, PREFS + ".display", PREFS + ".controllers", PREFS + ".legacy_rc"]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _wait_trim_drained() -> bool:
	for _index in 18000:
		if not FlightSession.menu_trim_busy():
			return true
		await process_frame
	return not FlightSession.menu_trim_busy()


func _new_world_gate_app() -> TrackedApp:
	var app := TrackedApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.flight_loading_enabled = true
	app.home_flight_prefetch_mode = "off"
	app.window_focus_probe = func() -> bool: return true
	app.use_world_gate = true
	root.add_child(app)
	await _frames(8)
	if app.controllers != null:
		app.controllers.select_devices(-1, -1)
	return app


func _launch_world_gate(app: TrackedApp, label: String) -> WorldGateFlight:
	var drained := await _wait_trim_drained()
	_check(label + " starts with no outstanding trim worker", drained)
	if not drained:
		return null
	FlightSession._launch_trim_cache.clear()
	app.start_flight()
	for _index in 2400:
		var candidate := app.flight as WorldGateFlight
		if is_instance_valid(candidate) and candidate.entered_world_gate:
			var stats: Dictionary = candidate.gate_stats
			_check(label + " keeps one prepared session and trim job private during world build",
				candidate.private_state_valid and candidate.prepared_session_id != 0
				and candidate.prepared_session_ref != null and candidate.prepared_sim_ref != null
				and int(stats.get("staged_workers_started", 0)) == 1
				and bool(stats.get("staged_worker_active", false))
				and str(stats.get("managed_owner", "")) == "flight"
				and int(stats.get("entries", -1)) == 0)
			return candidate
		if not app._loading_active:
			break
		await process_frame
	_check(label + " reaches the world gate", false)
	return null


func _run_world_gate_cases() -> void:
	# Reuse one Home for cancellation, world rejection and successful publication.
	var app := await _new_world_gate_app()
	var original_home: Control = app.home
	var gate := await _launch_world_gate(app, "Cancel")
	if gate == null:
		app.free()
		await _wait_trim_drained()
		return
	var pending_session: WeakRef = gate.prepared_session_ref
	var pending_sim: WeakRef = gate.prepared_sim_ref
	app.cancel_flight_loading()
	var cancelled := await _wait_idle(app, 18000)
	await _frames(4)
	var stats: Dictionary = FlightSession.launch_trim_cache_stats()
	_check("cancel at the world gate drains without publishing and restores Home",
		cancelled and app.flight == null and app.home == original_home and app.home.is_inside_tree()
		and app.home_scene != null and app.home_scene.is_inside_tree() and app.screens.is_top("home")
		and app.last_flight_loading.get("status", "") == "cancelled"
		and pending_session != null and pending_session.get_ref() == null
		and pending_sim != null and pending_sim.get_ref() == null
		and int(stats.get("staged_workers_started", 0)) == 1 and not FlightSession.menu_trim_busy()
		and int(stats.get("entries", -1)) == 0)
	if not cancelled:
		app.free()
		await _wait_trim_drained()
		return

	app.reject_world = true
	gate = await _launch_world_gate(app, "Rejected world")
	if gate == null:
		app.free()
		await _wait_trim_drained()
		return
	pending_session = gate.prepared_session_ref
	pending_sim = gate.prepared_sim_ref
	gate.release_world_gate = true
	var rejected := await _wait_idle(app, 18000)
	await _frames(4)
	stats = FlightSession.launch_trim_cache_stats()
	_check("rejected world discards the private session and restores Home",
		rejected and app.flight == null and app.home == original_home and app.home.is_inside_tree()
		and app.screens.is_top("home") and app.last_flight_loading.get("status", "") == "failed"
		and app.home.note_label.text.contains("Intentional world build rejection")
		and pending_session != null and pending_session.get_ref() == null
		and pending_sim != null and pending_sim.get_ref() == null
		and int(stats.get("staged_workers_started", 0)) == 1 and not FlightSession.menu_trim_busy()
		and int(stats.get("entries", -1)) == 0)
	if not rejected:
		app.free()
		await _wait_trim_drained()
		return

	app.reject_world = false
	gate = await _launch_world_gate(app, "Successful world")
	if gate == null:
		app.free()
		await _wait_trim_drained()
		return
	var prepared_id := gate.prepared_session_id
	gate.release_world_gate = true
	var completed := await _wait_idle(app, 18000)
	var ready_flight: Node = app.flight if is_instance_valid(app.flight) else null
	var ready_session: Node = ready_flight.session if ready_flight != null else null
	stats = FlightSession.launch_trim_cache_stats()
	_check("successful world publishes the same prepared session without a duplicate worker",
		completed and app.last_flight_loading.get("status", "") == "ready"
		and ready_flight == gate and is_instance_valid(ready_session)
		and ready_session.get_instance_id() == prepared_id and ready_session.is_flyable()
		and gate._preparing_session == null and int(stats.get("staged_workers_started", 0)) == 1
		and not FlightSession.menu_trim_busy())
	var duplicate_refused := false
	if is_instance_valid(ready_session):
		var repeated: bool = await ready_session.finish_staged_setup(process_frame, func() -> bool: return false)
		duplicate_refused = not repeated and ready_flight.session == ready_session \
			and int(FlightSession.launch_trim_cache_stats().get("staged_workers_started", 0)) == 1
	_check("a completed session cannot be finalized twice", duplicate_refused)
	app.free()
	await _frames(4)
	await _wait_trim_drained()

	# Controlled Quit must wait for the private numeric transaction before restoring Home and committing.
	var quit_app := await _new_world_gate_app()
	var quit_home: Control = quit_app.home # the loading route temporarily removes Home from the screen stack
	gate = await _launch_world_gate(quit_app, "Quit")
	if gate == null:
		quit_app.free()
		await _wait_trim_drained()
		return
	pending_session = gate.prepared_session_ref
	pending_sim = gate.prepared_sim_ref
	quit_app.quit_prepared_session_ref = pending_session
	quit_app.quit_prepared_sim_ref = pending_sim
	quit_app.quit_candidate_instance_id = gate.get_instance_id()
	quit_app.quit_app()
	var quit_finished := await _wait_quit_commit(quit_app, 18000)
	await _frames(4)
	stats = FlightSession.launch_trim_cache_stats()
	var quit_detail := {finished = quit_finished, calls = quit_app.quit_commit_calls,
		flight_cleared = quit_app.flight == null, home_same = quit_app.home == quit_home,
		home_inside = is_instance_valid(quit_app.home) and quit_app.home.is_inside_tree(),
		home_top = quit_app.screens.is_top("home"), commit = quit_app.quit_commit_state,
		session_gone = pending_session != null and pending_session.get_ref() == null,
		sim_gone = pending_sim != null and pending_sim.get_ref() == null, stats = stats}
	_check("Quit at the world gate drains before commit and restores Home",
		quit_finished and quit_app.quit_commit_calls == 1 and quit_app.flight == null
		and quit_app.home == quit_home and quit_app.home.is_inside_tree() and quit_app.screens.is_top("home")
		and quit_app.quit_commit_state.get("candidate_disposal_scheduled", false)
		and quit_app.quit_commit_state.get("prepared_session_gone", false)
		and quit_app.quit_commit_state.get("prepared_sim_gone", false)
		and not quit_app.quit_commit_state.get("trim_busy", true)
		and int(quit_app.quit_commit_state.get("trim_stats", {}).get("entries", -1)) == 0
		and quit_app.quit_commit_state.get("status", "") == "cancelled"
		and pending_session != null and pending_session.get_ref() == null
		and pending_sim != null and pending_sim.get_ref() == null
		and int(stats.get("staged_workers_started", 0)) == 1 and not FlightSession.menu_trim_busy()
		and int(stats.get("entries", -1)) == 0, str(quit_detail))
	quit_app.free()
	await _frames(4)
	await _wait_trim_drained()

	# A raw owner free cannot await; the cache-owned frame callback must finish the abandoned job.
	var raw_app := await _new_world_gate_app()
	gate = await _launch_world_gate(raw_app, "Raw free")
	if gate == null:
		raw_app.free()
		await _wait_trim_drained()
		return
	pending_session = gate.prepared_session_ref
	pending_sim = gate.prepared_sim_ref
	var raw_app_ref: WeakRef = weakref(raw_app)
	var raw_flight_ref: WeakRef = weakref(gate)
	raw_app.free()
	var raw_drained := await _wait_trim_drained()
	await _frames(4)
	stats = FlightSession.launch_trim_cache_stats()
	_check("raw AppRoot.free releases private nodes and independently drains the worker",
		raw_drained and raw_app_ref.get_ref() == null and raw_flight_ref.get_ref() == null
		and pending_session != null and pending_session.get_ref() == null
		and pending_sim != null and pending_sim.get_ref() == null
		and int(stats.get("staged_workers_started", 0)) == 1
		and not FlightSession.menu_trim_busy() and int(stats.get("entries", -1)) == 0)


func _run_retained_main_removal() -> void:
	var initially_drained := await _wait_trim_drained()
	_check("retained Main test starts without an outstanding trim", initially_drained)
	if not initially_drained:
		return
	FlightSession._launch_trim_cache.clear()
	var cancel_state := {requested = false}
	var gate := WorldGateFlight.new()
	gate.interactive_start = true
	gate.start_choice = FlightSession.START_RUNWAY
	gate.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE
	gate.startup_checkpoint = func(_label: String) -> bool: return true
	gate.startup_cancel_requested = func() -> bool: return bool(cancel_state.requested)
	root.add_child(gate)
	for _index in 2400:
		if gate.entered_world_gate or gate.startup_complete:
			break
		await process_frame
	var pending: Node = gate._preparing_session
	var resolution: Dictionary = pending._staged_trim_job if is_instance_valid(pending) else {}
	var original_job: RefCounted = resolution.get("job") as RefCounted
	var valid_job := gate.entered_world_gate and gate.private_state_valid and is_instance_valid(pending) \
		and original_job != null and is_same(original_job, FlightSession._launch_trim_cache._managed_job)
	_check("retained Main test reaches world build with the real reserved job", valid_job)
	if not valid_job:
		gate.free()
		await _wait_trim_drained()
		return
	var pending_ref: WeakRef = weakref(pending)
	var sim_ref: WeakRef = weakref(pending.sim)
	# The real worker may finish before the next frame. Hold its poll result so that
	# cancellation is provably suspended when the still-retained Main leaves the tree.
	var held := HeldTrimPoll.new()
	held.original = original_job
	FlightSession._launch_trim_cache._managed_job = held
	pending._staged_trim_job["job"] = held
	pending._staged_resolution["job"] = held
	cancel_state.requested = true
	var waiting := false
	for _index in 2400:
		if not is_instance_valid(pending):
			break
		if pending._staged_phase == FlightSession._STAGED_CANCELLING:
			waiting = true
			break
		await process_frame
	_check("controlled cancellation is suspended while observing the held job", waiting)
	if not waiting:
		held.released = true
		gate.free()
		await _wait_trim_drained()
		return
	root.remove_child(gate) # retain Main itself; its detached Session must still be released
	var after_remove: Dictionary = FlightSession.launch_trim_cache_stats()
	_check("removing a retained Main frees the private session and abandons the job",
		is_instance_valid(gate) and not gate.is_inside_tree() and gate._preparing_session == null
		and pending_ref.get_ref() == null and sim_ref.get_ref() == null
		and str(after_remove.get("managed_owner", "")) == "abandoned"
		and bool(after_remove.get("staged_worker_active", false))
		and int(after_remove.get("entries", -1)) == 0)
	held.released = true
	var drained := await _wait_trim_drained()
	await _frames(4)
	var final_stats: Dictionary = FlightSession.launch_trim_cache_stats()
	_check("retained Main resumes cleanup while the abandoned job drains without publication",
		drained and gate.startup_complete and gate.session == null and gate._preparing_session == null
		and int(final_stats.get("staged_workers_started", 0)) == 1
		and int(final_stats.get("entries", -1)) == 0 and not FlightSession.menu_trim_busy())
	gate.free()


func _run_retained_main_finish_removal() -> void:
	var initially_drained := await _wait_trim_drained()
	_check("retained Main finish test starts without an outstanding trim", initially_drained)
	if not initially_drained:
		return
	FlightSession._launch_trim_cache.clear()
	var gate := WorldGateFlight.new()
	gate.interactive_start = true
	gate.start_choice = FlightSession.START_RUNWAY
	gate.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE
	gate.startup_checkpoint = func(_label: String) -> bool: return true
	gate.startup_cancel_requested = func() -> bool: return false
	var finished := {count = 0}
	gate.startup_finished.connect(func() -> void: finished.count += 1)
	root.add_child(gate)
	for _index in 2400:
		if gate.entered_world_gate or gate.startup_complete:
			break
		await process_frame
	var pending: Node = gate._preparing_session
	var resolution: Dictionary = pending._staged_trim_job if is_instance_valid(pending) else {}
	var original_job: RefCounted = resolution.get("job") as RefCounted
	var valid_job := gate.entered_world_gate and gate.private_state_valid and is_instance_valid(pending) \
		and original_job != null and is_same(original_job, FlightSession._launch_trim_cache._managed_job)
	_check("retained Main finish test reaches the real reserved trim job", valid_job)
	if not valid_job:
		gate.free()
		await _wait_trim_drained()
		return
	var pending_ref: WeakRef = weakref(pending)
	var sim_ref: WeakRef = weakref(pending.sim)
	# Hold the real job's poll result across world construction, so finish must suspend.
	var held := HeldTrimPoll.new()
	held.original = original_job
	FlightSession._launch_trim_cache._managed_job = held
	pending._staged_trim_job["job"] = held
	pending._staged_resolution["job"] = held
	gate.release_world_gate = true
	var waiting := false
	for _index in 18000:
		if not is_instance_valid(pending) or gate.startup_complete:
			break
		if pending._staged_phase == FlightSession._STAGED_FINISHING:
			waiting = true
			break
		await process_frame
	_check("flight finalization is suspended on the held trim job", waiting)
	if not waiting:
		held.released = true
		gate.free()
		await _wait_trim_drained()
		return
	root.remove_child(gate) # Main is retained while the Session it awaited is freed
	var after_remove: Dictionary = FlightSession.launch_trim_cache_stats()
	_check("removing Main during finish frees its detached session and abandons the job",
		is_instance_valid(gate) and not gate.is_inside_tree() and gate._preparing_session == null
		and pending_ref.get_ref() == null and sim_ref.get_ref() == null
		and str(after_remove.get("managed_owner", "")) == "abandoned"
		and bool(after_remove.get("staged_worker_active", false))
		and int(after_remove.get("entries", -1)) == 0)
	held.released = true
	var drained := await _wait_trim_drained()
	for _index in 2400:
		if gate.startup_complete:
			break
		await process_frame
	var final_stats: Dictionary = FlightSession.launch_trim_cache_stats()
	_check("retained Main leaves finish wait and signals once after its session is removed",
		drained and gate.startup_complete and finished.count == 1 and gate.session == null
		and gate._preparing_session == null and int(final_stats.get("staged_workers_started", 0)) == 1
		and int(final_stats.get("entries", -1)) == 0 and not FlightSession.menu_trim_busy())
	gate.free()


func _run() -> void:
	TranslationServer.set_locale("en")
	_clear_test_files()
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences.first_flight_hint_seen = true
	preferences.start_choice = FlightSession.START_RUNWAY
	_check("isolated test preferences save", Preferences.save_to(PREFS, preferences) == OK)

	var app := TrackedApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.flight_loading_enabled = true # exercise staged rendering checkpoints under headless Godot
	app.window_focus_probe = func() -> bool: return true
	root.add_child(app)
	await _frames(8)
	_check("disabled preparation creates no owner or speculative worker", app._home_flight_preparation == null
		and app.scene_job_creations == 0 and app.home_flight_preparation.get("drained", false))
	if app.controllers != null:
		app.controllers.select_devices(-1, -1)
	app.set_start_choice(FlightSession.START_RUNWAY)
	var original_home: Control = app.home
	var original_aircraft: String = app.home.aircraft_id
	_check("Home starts on the intended runway choice", original_home != null
		and original_home.start_choice == FlightSession.START_RUNWAY)

	# Cancel while the first presentation checkpoint is drawing, before resources or a candidate exist.
	app.start_flight()
	var initial_checkpoint := app._loading_active and app.screens.is_top("loading") \
		and app._loading_phase == "Preparing resources"
	_check("first checkpoint opens the loading screen synchronously", initial_checkpoint)
	app.start_flight() # duplicate Fly must not start a second request
	app.set_aircraft(ALTERNATE_AIRCRAFT)
	app.set_start_choice("airborne")
	_check("Home selections are locked during loading", app.home == original_home
		and app.home.aircraft_id == original_aircraft
		and app.home.start_choice == FlightSession.START_RUNWAY)
	app.cancel_flight_loading()
	var early_cancel_finished := await _wait_idle(app, 60)
	await _frames(3)
	_check("early cancel returns to the same usable Home without a candidate",
		early_cancel_finished and app.flight == null and app.flight_creations == 0
		and app.home == original_home and app.home.is_inside_tree() and app.screens.is_top("home")
		and app.home_scene != null and app.home_scene.is_inside_tree()
		and app.screens.get_screen("loading") == null
		and app.last_flight_loading.get("status", "") == "cancelled")

	# Hold an actual scene-load worker before ResourceLoader runs, so cancellation cannot race a warm cache.
	var cancel_gate := SceneLoadGate.new()
	app.scene_load_gate = cancel_gate
	app.start_flight()
	var worker_started := await _wait_scene_worker(app, cancel_gate)
	var cancelled_job: Node = app._loading_scene_job
	var cancelled_job_ref: WeakRef = weakref(cancelled_job) if is_instance_valid(cancelled_job) else weakref(app)
	_check("scene worker starts after feedback without instantiating flight", worker_started
		and app.last_flight_loading.has("feedback_usec") and app.flight_creations == 0 and app.flight == null)
	app.cancel_flight_loading()
	await _frames(4)
	_check("busy cancellation keeps its loading surface until the worker drains", worker_started
		and app._loading_active and app.screens.is_top("loading") and app.flight_creations == 0
		and is_instance_valid(cancelled_job) and not cancelled_job.complete)
	cancel_gate.release.post()
	var busy_cancel_finished := await _wait_idle(app, 2400)
	await _frames(4)
	_check("cancelled scene job joins and cannot populate the retained cache", busy_cancel_finished
		and cancelled_job_ref.get_ref() == null and app._loading_scene_job == null
		and app._loading_scene_resource == null and app.flight_creations == 0 and app.flight == null
		and not app._home_preview_resources._resources.has(app.FLIGHT_SCENE)
		and app.home == original_home and app.screens.is_top("home")
		and app.last_flight_loading.get("status", "") == "cancelled")
	app.scene_load_gate = null

	# An injected constructor rejection tests the AppRoot rollback path without changing production data.
	app.reject_next_flight = true
	app.start_flight()
	var rejection_finished := await _wait_idle(app, 1800)
	await _frames(3)
	_check("rejected candidate reports failure and restores Home",
		rejection_finished and app.flight == null and app.home == original_home
		and app.home_scene != null and app.home_scene.is_inside_tree()
		and app.screens.is_top("home") and app.screens.get_screen("loading") == null
		and app.last_flight_loading.get("status", "") == "failed"
		and app.home.note_label.text.contains("Intentional startup rejection")
		and app.rejected_candidate_session_was_null and app.rejected_candidate_ref.get_ref() == null)

	# Cancel after the real candidate has a session. The parent is disabled and the session is held while loading.
	app.start_flight()
	var effects_reached := await _wait_phase(app, "Preparing effects", 2400)
	var candidate: Node = app.flight
	var candidate_session: Node = candidate.session if is_instance_valid(candidate) else null
	var candidate_ref: WeakRef = weakref(candidate) if is_instance_valid(candidate) else weakref(app)
	var session_ref: WeakRef = weakref(candidate_session) if is_instance_valid(candidate_session) else weakref(app)
	var tick_before: int = candidate_session.sim.tick if is_instance_valid(candidate_session) else -1
	_check("effects checkpoint has a held real session", effects_reached
		and is_instance_valid(candidate) and is_instance_valid(candidate_session)
		and candidate_session.holds.has("loading") and tick_before == 0)
	if effects_reached:
		var cancel: Button = app._loading_screen.cancel_button
		var focus: Control = root.gui_get_focus_owner()
		_check("Cancel retains focus during effects checkpoint", focus == cancel, "focus=%s" % str(focus))
		for pressed: bool in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER
			key.physical_keycode = KEY_ENTER
			key.pressed = pressed
			root.push_input(key, true)
		_check("Enter requests cancellation during effects checkpoint", app._loading_cancelled,
			"cancelled=%s" % app._loading_cancelled)
		if not app._loading_cancelled:
			app.cancel_flight_loading() # clean up after observing failure; preserve later coverage
	var tick_changed := false
	for _index in 8:
		await process_frame
		var remaining_session: Variant = session_ref.get_ref()
		if is_instance_valid(remaining_session) and remaining_session.sim.tick != tick_before:
			tick_changed = true
	var candidate_cancel_finished := await _wait_idle(app, 60)
	await _frames(3)
	_check("candidate cancellation freezes ticks and frees candidate/session",
		effects_reached and candidate_cancel_finished and not tick_changed
		and app.flight == null and candidate_ref.get_ref() == null and session_ref.get_ref() == null
		and app.home == original_home and app.home_scene != null and app.home_scene.is_inside_tree()
		and app.screens.is_top("home") and app.screens.get_screen("loading") == null
		and app.last_flight_loading.get("status", "") == "cancelled")

	# OS quit during staged startup cancels the held candidate, restores Home, then reaches the quit seam.
	app.start_flight()
	var quit_effects_reached := await _wait_phase(app, "Preparing effects", 2400)
	var quit_candidate: Node = app.flight
	var quit_session: Node = quit_candidate.session if is_instance_valid(quit_candidate) else null
	app.quit_candidate_instance_id = quit_candidate.get_instance_id() if is_instance_valid(quit_candidate) else 0
	var quit_session_instance_id := quit_session.get_instance_id() if is_instance_valid(quit_session) else 0
	_check("quit test reaches loading with a held candidate", quit_effects_reached
		and is_instance_valid(quit_candidate) and is_instance_valid(quit_session)
		and quit_session.holds.has("loading") and quit_session.sim.tick == 0)
	quit_candidate = null
	quit_session = null
	var quit_commit_finished := false
	if quit_effects_reached:
		app.quit_app()
		quit_commit_finished = await _wait_quit_commit(app, 2400)
	await _frames(4)
	_check("quit commits after cancellation restores Home and clears loading",
		quit_effects_reached and quit_commit_finished and app.quit_commit_calls == 1
		and not bool(app.quit_commit_state.get("loading_active", true))
		and bool(app.quit_commit_state.get("flight_cleared", false))
		and bool(app.quit_commit_state.get("candidate_disposal_scheduled", false))
		and bool(app.quit_commit_state.get("loading_screen_absent", false))
		and bool(app.quit_commit_state.get("home_top", false))
		and bool(app.quit_commit_state.get("home_attached", false))
		and bool(app.quit_commit_state.get("home_scene_attached", false))
		and str(app.quit_commit_state.get("status", "")) == "cancelled"
		and not is_instance_valid(instance_from_id(app.quit_candidate_instance_id))
		and not is_instance_valid(instance_from_id(quit_session_instance_id))
		and app.home == original_home and app.screens.is_top("home"))

	# Retry after both cancellation and startup rejection; duplicate Fly calls still construct one candidate.
	var creations_before_success := app.flight_creations
	app.scene_thread_unavailable = true # deterministic OS Thread.start failure seam
	app._home_preview_resources.cancel_for(app) # evict the retained scene, so fallback must run
	app.start_flight()
	app.start_flight()
	var success_finished := await _wait_idle(app, 2400)
	await _frames(3)
	var launched: Node = app.flight
	var session: Node = launched.session if is_instance_valid(launched) else null
	_check("duplicate Fly creates one candidate and completes startup",
		success_finished and app.flight_creations == creations_before_success + 1
		and is_instance_valid(launched) and launched.startup_complete and is_instance_valid(session))
	_check("unavailable worker records the existing synchronous fallback",
		app.last_flight_loading.get("scene_load_fallback", "") == "thread_start_failed")
	_check("successful flight is valid and uses Home's selected start",
		is_instance_valid(session) and session.is_flyable()
		and launched.start_choice == FlightSession.START_RUNWAY)
	_check("ready state removes the loading screen and hold",
		app.last_flight_loading.get("status", "") == "ready"
		and app.screens.get_screen("loading") == null
		and not app.screens.is_top("loading")
		and not session.holds.has("loading"))
	var phases: Array = app.last_flight_loading.get("phases", [])
	var feedback_usec: int = int(app.last_flight_loading.get("feedback_usec", -1))
	var total_usec: int = int(app.last_flight_loading.get("total_usec", -1))
	_check("successful loading retains phase and timing evidence",
		_contains_phase(phases, "Preparing resources") and _contains_phase(phases, "Checking landscape")
		and _contains_phase(phases, "Checking flight") and _contains_phase(phases, "Preparing effects")
		and feedback_usec >= 0 and total_usec >= feedback_usec)

	_check("successful scene preparation shares the broker's two-resource bound",
		app._loading_scene_job == null and app._loading_scene_resource == null
		and app._home_preview_resources._resources.size() <= 2
		and app._home_preview_resources._resources.has(app.FLIGHT_SCENE))
	app.queue_free()
	await _frames(4)

	# AppRoot may be freed by callers without the controlled Quit path. Its root-owned job must survive and drain.
	var departed_app := TrackedApp.new()
	departed_app.user_args = PackedStringArray()
	departed_app.preferences_path = PREFS
	departed_app.flight_loading_enabled = true
	var departed_gate := SceneLoadGate.new()
	departed_app.scene_load_gate = departed_gate
	root.add_child(departed_app)
	await _frames(8)
	departed_app.start_flight()
	var departed_worker_started := await _wait_scene_worker(departed_app, departed_gate)
	var orphan_job: Node = departed_app._loading_scene_job
	var orphan_ref: WeakRef = weakref(orphan_job) if is_instance_valid(orphan_job) else weakref(departed_app)
	var departed_ref: WeakRef = weakref(departed_app)
	departed_app.free()
	await _frames(4)
	_check("AppRoot.free leaves the active scene job owned by the tree", departed_worker_started
		and departed_ref.get_ref() == null and is_instance_valid(orphan_job)
		and orphan_job.get_parent() == root and not orphan_job.complete)
	departed_gate.release.post()
	for _index in 2400:
		if orphan_ref.get_ref() == null:
			break
		await process_frame
	_check("abandoned scene job joins, drops its result and frees itself", orphan_ref.get_ref() == null)

	var prepared_app := TrackedApp.new()
	prepared_app.user_args = PackedStringArray()
	prepared_app.preferences_path = PREFS
	prepared_app.flight_loading_enabled = true
	prepared_app.home_flight_prefetch_mode = "scene"
	prepared_app.home_flight_prefetch_delay_msec = 0
	var prepare_gate := SceneLoadGate.new()
	prepared_app.scene_load_gate = prepare_gate
	root.add_child(prepared_app)
	await _frames(8)
	prepared_app._home_flight_preparation.mark_home_drawn() # explicit headless seam
	var prepared_worker_started := false
	for _index in 2400:
		if prepare_gate.entered.try_wait():
			prepared_worker_started = true
			break
		await process_frame
	prepared_app.start_flight()
	await _frames(6)
	_check("Fly adopts pending Home scene before selected-resource admission", prepared_worker_started
		and prepared_app.last_flight_loading.get("scene_prefetch_adopted", false)
		and prepared_app.scene_job_creations == 1 and prepared_app.flight_creations == 0
		and prepared_app._home_preview_resources._admissions_paused)
	prepare_gate.release.post()
	var prepared_finished := await _wait_idle(prepared_app)
	_check("adopted scene and selected GLB complete without a second scene worker", prepared_finished
		and prepared_app.last_flight_loading.get("status", "") == "ready"
		and prepared_app.scene_job_creations == 1 and prepared_app.flight_creations == 1
		and not prepared_app._home_preview_resources._admissions_paused)
	await prepared_app.shutdown_home_flight_preparation()
	prepared_app.queue_free()
	await _frames()

	var random_app := TrackedApp.new()
	random_app.user_args = PackedStringArray()
	random_app.preferences_path = PREFS
	random_app.flight_loading_enabled = true
	random_app.home_flight_prefetch_mode = "scene"
	random_app.home_flight_prefetch_delay_msec = 0
	var random_gate := SceneLoadGate.new()
	random_app.scene_load_gate = random_gate
	root.add_child(random_app)
	await _frames(8)
	random_app._home_flight_preparation.mark_home_drawn()
	var random_worker_started := false
	for _index in 2400:
		if random_gate.entered.try_wait():
			random_worker_started = true
			break
		await process_frame
	random_app.open_natural_random()
	random_app.start_flight() # a competing launch must not bypass the route's drain barrier
	await _frames(6)
	_check("Natural Random waits for preparation before synchronous briefing setup", random_worker_started
		and random_app._home_preparation_route_pending and random_app.natural_random_screen == null
		and not random_app._loading_active and random_app.flight_creations == 0)
	random_gate.release.post()
	for _index in 2400:
		if not random_app._home_preparation_route_pending:
			break
		await process_frame
	_check("Natural Random opens after the scene drains without a competing Fly", random_app.screens.is_top("natural_random")
		and random_app.natural_random_screen != null and random_app.flight_creations == 0
		and random_app.home_flight_preparation.get("drained", false))
	await random_app.shutdown_home_flight_preparation()
	random_app.queue_free()
	await _frames()

	var quit_app := QuitPreparationApp.new()
	quit_app.user_args = PackedStringArray()
	quit_app.preferences_path = PREFS
	quit_app.home_flight_prefetch_mode = "scene"
	quit_app.home_flight_prefetch_delay_msec = 0
	var quit_gate := SceneLoadGate.new()
	quit_app.gate = quit_gate
	root.add_child(quit_app)
	await _frames(8)
	quit_app.menu_audio.set_volume(0.0)
	quit_app._home_flight_preparation.mark_home_drawn()
	var quit_worker_started := false
	for _index in 2400:
		if quit_gate.entered.try_wait():
			quit_worker_started = true
			break
		await process_frame
	paused = true
	quit_app.quit_app()
	quit_app.quit_app()
	await _frames(6)
	_check("muted idle Quit waits for pending preparation even with SceneTree paused", quit_worker_started
		and quit_app.quit_requested_count == 0 and not quit_app._loading_active)
	quit_gate.release.post()
	for _index in 2400:
		if quit_app.quit_requested_count > 0:
			break
		await process_frame
	_check("paused idle Quit commits only after preparation drains", quit_app.quit_requested_count == 1
		and quit_app.quit_preparation.get("drained", false))
	paused = false
	quit_app.queue_free()
	await _frames()
	await _run_world_gate_cases()
	await _run_retained_main_removal()
	await _run_retained_main_finish_removal()
	TranslationServer.set_locale("en")
	_clear_test_files()
	print("Flight loading: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
