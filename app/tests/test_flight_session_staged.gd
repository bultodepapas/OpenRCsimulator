## Synchronous/staged FlightSession contract, exact launch parity and cancellation cleanup.
extends SceneTree

const Session: Script = preload("res://sim/flight_session.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const TURBO_PATH := "res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"
const TURBO_ID := "turbo-lumber-evolution"

var _checks := 0
var _failures := 0
var _frames := 0
var _cancel_after_frame := 0
var _cancel_observed := false
var _cancel_frame := -1


func _initialize() -> void:
	process_frame.connect(_on_process_frame)
	call_deferred("_run")


func _on_process_frame() -> void:
	_frames += 1


func _cancel_after_worker_yields() -> bool:
	if _frames > _cancel_after_frame and Session._launch_trim_cache.stats().staged_worker_active:
		if not _cancel_observed:
			_cancel_frame = _frames
		_cancel_observed = true
		return true
	return false


func _run() -> void:
	var loaded: Dictionary = AircraftData.load_file(TURBO_PATH)
	_check("Turbo Lumber pack data loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return

	Session._launch_trim_cache.clear()
	var staged: Variant = Session.new()
	staged.trim_throttle = Session.CRUISE_TRIM_THROTTLE
	var staged_ok: bool = await staged.setup_staged(TURBO_PATH, TURBO_ID, loaded, process_frame, Callable())
	_check("cold staged setup completes", staged_ok and staged.is_flyable(), staged.start_error)
	_check("cold staged setup used one worker and retained the raw trim",
		Session._launch_trim_cache.stats().staged_workers_started == 1
		and Session._launch_trim_cache.stats().entries == 1)
	if not staged_ok or not staged.is_flyable():
		staged.free()
		_finish()
		return
	var staged_bytes: PackedByteArray = var_to_bytes(_session_output(staged))
	var staged_cache_entries: Array = Session._launch_trim_cache._entries
	var staged_raw_bytes: PackedByteArray = var_to_bytes(staged_cache_entries[0].result) \
		if not staged_cache_entries.is_empty() else PackedByteArray()
	_check("staged setup retained the raw solver dictionary before adding session state",
		not staged_raw_bytes.is_empty())

	Session._launch_trim_cache.clear()
	var synchronous: Variant = Session.new()
	synchronous.trim_throttle = Session.CRUISE_TRIM_THROTTLE
	synchronous.setup(TURBO_PATH, TURBO_ID, loaded)
	_check("sync setup remains flyable", synchronous.is_flyable(), synchronous.start_error)
	_check("sync/staged sessions preserve exact output bytes", staged_bytes == var_to_bytes(_session_output(synchronous)))
	var sync_cache_entries: Array = Session._launch_trim_cache._entries
	var sync_raw_bytes: PackedByteArray = var_to_bytes(sync_cache_entries[0].result) \
		if not sync_cache_entries.is_empty() else PackedByteArray()
	_check("staged-first raw cache bytes equal the independent sync solver result",
		staged_raw_bytes == sync_raw_bytes and not sync_raw_bytes.is_empty())
	staged.free()
	synchronous.free()

	var bad_data := {ok = false, errors = ["staged validation parity fixture"]}
	var sync_invalid: Variant = Session.new()
	sync_invalid.setup(TURBO_PATH, TURBO_ID, bad_data)
	var staged_invalid: Variant = Session.new()
	var invalid_ok: bool = await staged_invalid.setup_staged(
		TURBO_PATH, TURBO_ID, bad_data, process_frame, Callable())
	_check("validation failure completes staged setup as invalid", invalid_ok and not staged_invalid.is_flyable())
	_check("validation failure matches synchronous state and message bytes",
		var_to_bytes(_session_output(sync_invalid)) == var_to_bytes(_session_output(staged_invalid)))
	sync_invalid.free()
	staged_invalid.free()

	Session._launch_trim_cache.clear()
	_cancel_after_frame = _frames
	_cancel_observed = false
	_cancel_frame = -1
	var cancelled_session: Variant = Session.new()
	cancelled_session.trim_throttle = Session.CRUISE_TRIM_THROTTLE
	var cancelled: bool = await cancelled_session.setup_staged(
		TURBO_PATH, TURBO_ID, loaded, process_frame, Callable(self, "_cancel_after_worker_yields"))
	var after_cancel := Session._launch_trim_cache.stats()
	_check("worker cancellation returns false after observing a yielded frame", not cancelled and _cancel_observed
		and _cancel_frame > _cancel_after_frame)
	_check("cancellation drains worker across additional responsive frames",
		_frames > _cancel_frame + 1 and not after_cancel.staged_worker_active,
		"cancel frame=%d final frame=%d" % [_cancel_frame, _frames])
	_check("cancellation does not cache or attach a partial session",
		after_cancel.entries == 0 and cancelled_session.sim == null and cancelled_session.get_child_count() == 0)
	cancelled_session.free()
	_finish()


func _session_output(session: Variant) -> Dictionary:
	var simulation: Node = session.sim
	return {
		aircraft = session.aircraft,
		start = session.start,
		trims = session.trims,
		start_error = session.start_error,
		pause_reason = session.pause_reason,
		is_flyable = session.is_flyable(),
		tick = simulation.tick,
		state = simulation.state,
		previous = simulation.previous,
		continuous = simulation.continuous,
		inputs = simulation.inputs,
		aux = simulation.aux,
		mass = simulation.mass,
		inertia = simulation.inertia,
		paused = simulation.paused,
		fault_reason = simulation.fault_reason,
	}


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	push_error("FAIL: " + label + (" — " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	print("FlightSession staged fixture: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
