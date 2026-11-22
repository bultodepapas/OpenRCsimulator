## TELEM-02…06: the one owner of product telemetry in a session. AppRoot adds it on the interactive route and
## gives it a context provider; nothing else collects or sends. While the effective state is not "on" it does no
## work at all (no processing, hardware reads or allocations beyond this node).
##
## On: it measures process cadence in fixed windows, summarizes accepted activities, seals closed batches into a
## memory-only queue and sends them one at a time. Turning it off first closes the gate and advances the consent
## generation (late answers of the old generation are ignored), then cancels the request, drops every pending byte,
## window and the session token, and saves the choice. It never touches simulation, inputs or replay; the context
## provider only reads state AppRoot already owns.
extends Node

const Contract := preload("res://telemetry/telemetry_contract.gd")
const Policy := preload("res://telemetry/telemetry_policy.gd")
const ConsentStore := preload("res://telemetry/telemetry_consent_store.gd")
const Hardware := preload("res://telemetry/telemetry_hardware.gd")
const FrameWindow := preload("res://telemetry/telemetry_frame_window.gd")
const Queue := preload("res://telemetry/telemetry_queue.gd")
const Sender := preload("res://telemetry/telemetry_sender.gd")

## Effective state or status changed (Settings and Home listen).
signal state_changed

const WARMUP_US := 10000000
const SEAL_INTERVAL_US := 60000000
const SESSION_MAX_US := 14400000000 # four hours
## TELEM-19: a running activity is summarized every 5 minutes, so quitting from a flight (nothing is flushed at exit)
## loses only its last slice and unsealed events (about 6 minutes at most) instead of the whole flight.
const ACTIVITY_SLICE_US := 300000000

## TelemetryRelease.current() result; {ok = false} keeps everything unavailable.
var release: Dictionary = {"ok": false, "reason": "unset"}
var interactive := false
var consent_path := ConsentStore.DEFAULT_PATH
var locale := "en"
## Returns the observation context each frame: {mode, activity (a simulated vehicle session), vehicle, custom,
## eligible, simulated_seconds, fixed_wing_accepted, window_size, vsync, max_fps, input_class}.
## See AppRoot._telemetry_context().
var context_provider := Callable()
## Returns "current_default", "custom" or "unknown"; asked when an event is recorded, never every frame. Unset, the
## context's own graphics_profile (tests) or "unknown" applies.
var graphics_profile_provider := Callable()
## Injected clocks for tests.
var clock_usec: Callable = func() -> int: return Time.get_ticks_usec()
var frames_drawn: Callable = func() -> int: return Engine.get_frames_drawn()
var utc_day: Callable = func() -> String: return Time.get_date_string_from_system(true)
## Hardware facts override for tests ({} reads the engine).
var hardware_facts: Dictionary = {}

var state := Policy.UNAVAILABLE
var reason := "unset"
var choice := "unset"
var choice_notice := ""
var save_error := OK
var suspended := false
var generation := 0
var queue := Queue.new()
var sender: Node
var local_drops := 0

var _session_id := ""
var _session_start_usec := 0
var _session_day := ""
var _seq := 0
var _pending: Array[Dictionary] = []
var _pending_context: Dictionary = {}
var _pending_session := ""
var _last_seal_usec := 0
var _hardware: Dictionary = {}
var _window: RefCounted
var _window_key := ""
var _window_mode := ""
var _window_vehicle := ""
var _warmup_left_us := 0
var _last_usec := -1
var _last_drawn := 0
var _activity: Dictionary = {}
var _last_crash_generation := ""
var _last_crash_sequence := -1
## True once this admission has observed the moment an activity begins (a non-activity frame or a reset); an
## activity already running when telemetry was admitted, or a later 5-minute slice, is not a complete observation.
var _activity_from_start := false
var _errors: Dictionary = {}


func _init() -> void:
	name = "Telemetry"
	set_process(false)


func _ready() -> void:
	if sender == null: # tests may supply a stand-in with the same busy/send/cancel/finished contract
		sender = Sender.new()
	if sender.get_parent() == null:
		add_child(sender)
	sender.finished.connect(_on_sent)
	refresh()


## Re-reads the saved choice and decides the effective state; starts or stops collection accordingly.
func refresh() -> void:
	var saved := ConsentStore.load_choice(consent_path) if Contract.is_true(release.get("ok")) and interactive else \
		{"choice": "unset", "notice": ""}
	choice = str(saved.choice)
	choice_notice = str(saved.notice)
	_apply()


func set_locale(code: String) -> void:
	if code == locale:
		return
	locale = code
	_apply()


## Facts for TelemetryPolicy.evaluate().
func facts() -> Dictionary:
	return {"release": release, "interactive": interactive, "locale": locale, "choice": choice,
		"notice": choice_notice, "suspended": suspended}


## The deliberate, telemetry-specific Enable action (first-launch choice or Settings). Returns the save result;
## a failed save still enables this session (the player asked) and Settings says it was not saved.
func enable() -> Error:
	if not Contract.is_true(release.get("ok")) or not interactive or suspended:
		return ERR_UNAVAILABLE
	var decision := Policy.evaluate(_facts_with("enabled", str(release.notice)))
	if decision.state != Policy.ON:
		return ERR_UNAVAILABLE
	save_error = ConsentStore.save_choice("enabled", str(release.notice), consent_path)
	choice = "enabled"
	choice_notice = str(release.notice)
	_apply()
	return save_error


## Turning telemetry off (or "Continue without telemetry"). The gate closes before anything else; a failed save
## keeps it closed for this session, and an earlier grant on disk is removed so the next launch asks again rather
## than resuming. Settings reports the failure.
func disable() -> Error:
	choice = "disabled"
	choice_notice = str(release.get("notice", ""))
	_stop()
	save_error = ConsentStore.save_choice("disabled", choice_notice, consent_path) \
		if Contract.is_true(release.get("ok")) and interactive else OK
	if save_error != OK and ConsentStore.load_choice(consent_path).choice == "enabled":
		DirAccess.remove_absolute(consent_path) # never leave a grant behind a failed decline
	_apply()
	return save_error


## Coalesced, bounded software-outcome counters (Contract.ERROR_CATEGORIES); never text.
func note_error(category: String) -> void:
	if state != Policy.ON or not category in Contract.ERROR_CATEGORIES:
		return
	_errors[category] = mini(int(_errors.get(category, 0)) + 1, Contract.ERROR_MAX_COUNT)


## Accepted fixed-wing classifier output (statistics service flight_events_accepted).
func note_flight_events(events: Array) -> void:
	if state != Policy.ON or _activity.is_empty() or _activity.classification != "accepted_fixed_wing":
		return
	for event: Variant in events:
		if not event is Dictionary:
			continue
		var kind := str(event.get("type", ""))
		if kind == "CRASH":
			# Revision zero announces the accident. Later revisions update the same one.
			# Keep a local high-water mark for the detector generation across telemetry slices.
			var detector_generation := str(event.get("generation_id", ""))
			var sequence := int(event.get("sequence", -1))
			if int(event.get("revision", -1)) != 0 or detector_generation == "" or sequence < 0:
				continue
			if detector_generation == _last_crash_generation and sequence <= _last_crash_sequence:
				continue
			_last_crash_generation = detector_generation
			_last_crash_sequence = sequence
		var key := "takeoffs" if kind == "TAKEOFF" else "landings" if kind == "LANDING_SUCCESS" else \
			"aircraft_crashes" if kind == "CRASH" else ""
		if key != "":
			_activity[key] = mini(int(_activity[key]) + 1, Contract.ACTIVITY_MAX_COUNT)


## What Settings shows.
func status() -> Dictionary:
	return {"state": state, "reason": reason, "choice": choice, "save_error": save_error,
		"sent": queue.sent_ok, "pending": queue.items.size() + (1 if not _pending.is_empty() else 0),
		"operator": str(release.get("operator", "")), "contact": str(release.get("contact", "")),
		"endpoint": str(release.get("endpoint", "")), "qualification": Contract.is_true(release.get("qualification"))}


## The exact data waiting in memory: sealed batches byte for byte, then the events not yet sealed.
func preview_text() -> String:
	var parts := PackedStringArray()
	for item: Dictionary in queue.items:
		parts.append(item.body.get_string_from_utf8())
	if not _pending.is_empty():
		parts.append(JSON.stringify(_batch(_pending, _pending_context, _pending_session, "0".repeat(32)), "  ", false))
	return "\n\n".join(parts)


func _process(_delta: float) -> void:
	if state != Policy.ON:
		set_process(false)
		return
	var now := int(clock_usec.call())
	_observe(now)
	if not _pending.is_empty() and now - _last_seal_usec >= SEAL_INTERVAL_US:
		_seal(now)
	if not sender.busy():
		var item := queue.begin(now / 1000000.0, generation)
		if not item.is_empty() and not sender.send(str(release.endpoint), item.body, int(item.serial)):
			queue.complete(int(item.serial), 0, now / 1000000.0) # never leave the queue waiting on a request that did not start


func _exit_tree() -> void:
	_stop() # quitting drops pending data; nothing is flushed or retried


func _apply() -> void:
	var decision := Policy.evaluate(facts())
	var was_on := state == Policy.ON
	state = decision.state
	reason = decision.reason
	if state == Policy.ON and not was_on:
		_start()
	elif state != Policy.ON and was_on:
		_stop()
	set_process(state == Policy.ON and is_inside_tree())
	state_changed.emit()


func _facts_with(next_choice: String, notice: String) -> Dictionary:
	var out := facts()
	out.choice = next_choice
	out.notice = notice
	return out


func _start() -> void:
	generation += 1
	_hardware = {}
	_new_session(int(clock_usec.call()))
	_last_seal_usec = int(clock_usec.call())
	_activity_from_start = false
	_append({"name": "session_started"})


## Close the gate's consequences: no request, no queued byte, no window, activity or token survives.
func _stop() -> void:
	generation += 1
	if sender != null:
		sender.cancel()
	queue.purge()
	_pending.clear()
	_pending_context = {}
	_pending_session = ""
	_session_id = ""
	_hardware = {}
	_window = null
	_window_key = ""
	_last_usec = -1
	_activity = {}
	_last_crash_generation = ""
	_errors = {}


func _new_session(now: int) -> void:
	_session_id = Contract.random_id()
	_session_start_usec = now
	_session_day = str(utc_day.call())
	_seq = 0


func _observe(now: int) -> void:
	var ctx: Dictionary = context_provider.call() if context_provider.is_valid() else {}
	var eligible := Contract.is_true(ctx.get("eligible"))
	var mode := str(ctx.get("mode", "other"))
	if not mode in Contract.MODES:
		mode = "other"
	# Only a simulated vehicle session is an activity; Home and Workshop editing are measured with no vehicle.
	var in_activity := Contract.is_true(ctx.get("activity"))
	var vehicle := Contract.vehicle_id(str(ctx.get("vehicle", "")), Contract.is_true(ctx.get("custom"))) \
		if in_activity else "none"
	var key := mode + "|" + vehicle
	_track_activity(ctx, mode, vehicle, now, in_activity)
	if not eligible or key != _window_key:
		_close_window(now, false)
		_last_usec = -1
		if key != _window_key:
			_window_key = key
			_window_mode = mode
			_window_vehicle = vehicle
			_warmup_left_us = WARMUP_US
	if not eligible:
		return
	var drawn := int(frames_drawn.call())
	if _last_usec < 0:
		_last_usec = now
		_last_drawn = drawn
		return
	var interval := now - _last_usec
	if interval <= 0:
		return # no time passed on the monotonic clock: nothing to observe yet
	var draws := drawn - _last_drawn
	_last_usec = now
	_last_drawn = drawn
	if interval > 0 and interval <= Contract.GAP_EXCLUDE_US and not _activity.is_empty():
		_activity.active_us = int(_activity.active_us) + interval
	if _window == null:
		_window = FrameWindow.new()
	var result: String = _window.record(interval, draws if draws >= 0 else -1)
	if result == FrameWindow.FULL:
		_close_window(now, false)
		_window = FrameWindow.new()
		result = _window.record(interval, draws if draws >= 0 else -1)
	if result == FrameWindow.INVALID or result == FrameWindow.FULL:
		local_drops += 1 # an unrepresentable observation: drop it and restart from the next frame
		_close_window(now, false)
		_last_usec = -1
		return
	if result == FrameWindow.RECORDED and _warmup_left_us > 0:
		_warmup_left_us -= interval
		if _warmup_left_us <= 0:
			_close_window(now, false, "warmup")
			return
	if _warmup_left_us <= 0 and _window != null and _window.is_complete():
		_close_window(now, true)


func _close_window(now: int, complete: bool, phase := "") -> void:
	if _window == null or _window.is_empty():
		_window = null
		return
	if phase == "":
		phase = "warmup" if _warmup_left_us > 0 else "steady"
	var event: Dictionary = _window.event(0, _window_mode, _window_vehicle, phase, complete)
	_window = null
	if not event.is_empty():
		_append(event, now)


func _track_activity(ctx: Dictionary, mode: String, vehicle: String, now: int, active: bool) -> void:
	var key := (mode + "|" + vehicle) if active else ""
	var simulated := float(ctx.get("simulated_seconds", -1.0))
	if not _activity.is_empty():
		if key != _activity["key"]:
			_end_activity(now, "returned_home" if mode == "home" else "unknown", true)
			_activity_from_start = true
		elif simulated >= 0.0 and simulated + 0.5 < float(_activity["sim_last"]):
			_end_activity(now, "reset", true) # the same vehicle restarted: its time went back
			_activity_from_start = true
		elif int(_activity["active_us"]) >= ACTIVITY_SLICE_US:
			_end_activity(now, "slice", false) # the activity continues in a new, incomplete part
			_activity_from_start = false
		else:
			if simulated >= 0.0:
				_activity["sim_last"] = simulated
			return
	if key == "":
		_activity_from_start = true
		_last_crash_generation = ""
		return
	var fixed_wing := Contract.is_true(ctx.get("fixed_wing_accepted")) and vehicle in Contract.FIXED_WING_VEHICLES
	# Without a simulated clock the summary reports 0 simulated seconds and says the observation is incomplete.
	_activity = {"key": key, "vehicle": vehicle, "active_us": 0,
		"sim_start": maxf(simulated, 0.0), "sim_last": maxf(simulated, 0.0),
		"complete": _activity_from_start and simulated >= 0.0,
		"classification": "accepted_fixed_wing" if fixed_wing else "unsupported",
		"takeoffs": 0, "landings": 0, "aircraft_crashes": 0,
		# Captured at the activity start: a backend change needs a new flight or reset, which ends this activity.
		"physics_backend": Contract.physics_backend(ctx.get("physics_backend"))}


func _end_activity(now: int, outcome: String, finished: bool) -> void:
	var a := _activity
	_activity = {}
	var fixed := str(a["classification"]) == "accepted_fixed_wing"
	_append({"name": "activity_summary", "vehicle_id": str(a.vehicle),
		"active_seconds": clampi(int(a.active_us) / 1000000, 0, Contract.ACTIVITY_MAX_ACTIVE_S),
		"simulated_seconds": clampi(int(float(a.sim_last) - float(a.sim_start)), 0, Contract.ACTIVITY_MAX_SIMULATED_S),
		"outcome": outcome, "complete_observation": finished and Contract.is_true(a.get("complete")),
		"classification": str(a.classification),
		"takeoffs": int(a.takeoffs) if fixed else null,
		"landings": int(a.landings) if fixed else null,
		"aircraft_crashes": int(a.aircraft_crashes) if fixed else null,
		"physics_backend": str(a.get("physics_backend", "unknown"))}, now)


## Number the event, keep batches context-stable and seal when full. `event` arrives without its seq.
func _append(event: Dictionary, now: int = -1) -> void:
	if state != Policy.ON or _session_id == "":
		return
	if now < 0:
		now = int(clock_usec.call())
	if now - _session_start_usec >= SESSION_MAX_US or str(utc_day.call()) != _session_day:
		_seal(now)
		_new_session(now)
	var context := _context()
	if not _pending.is_empty() and (context != _pending_context or _pending_session != _session_id):
		_seal(now)
	if _pending.is_empty():
		_pending_context = context
		_pending_session = _session_id
	_seq += 1
	var numbered := {"name": event.name, "seq": _seq}
	for key: String in event:
		if key != "name" and key != "seq": # builders may carry a placeholder seq; the session numbers events
			numbered[key] = event[key]
	_pending.append(numbered)
	if _pending.size() >= Contract.MAX_EVENTS:
		_seal(now)


func _seal(now: int) -> void:
	_last_seal_usec = now
	_flush_errors_into_pending()
	if _pending.is_empty():
		return
	var batch := _batch(_pending, _pending_context, _pending_session, Contract.random_id())
	_pending = []
	_pending_context = {}
	_pending_session = ""
	var error := Contract.check_batch(batch)
	if error != "":
		local_drops += 1
		push_warning("telemetry: dropped a batch that failed the local contract check (%s)" % error)
		return
	queue.push(Contract.encode(batch), generation, now / 1000000.0)
	state_changed.emit()


func _flush_errors_into_pending() -> void:
	if _errors.is_empty() or _pending.size() >= Contract.MAX_EVENTS:
		return
	if _pending.is_empty():
		_pending_context = _context()
		_pending_session = _session_id
	for category: String in Contract.ERROR_CATEGORIES:
		if _errors.has(category) and _pending.size() < Contract.MAX_EVENTS:
			_seq += 1
			_pending.append(Contract.error_count(_seq, category, int(_errors[category])))
			_errors.erase(category)


func _batch(events: Array[Dictionary], context: Dictionary, session_id: String, batch_id: String) -> Dictionary:
	return {"schema_version": Contract.SCHEMA_VERSION, "notice_version": str(release.get("notice", "")),
		"session_id": session_id, "batch_id": batch_id,
		"build": {"release_id": str(release.get("release_id", "")), "channel": str(release.get("channel", "")),
			"engine_minor": Contract.ENGINE_MINOR},
		"context": context, "events": events.duplicate(true)}


## Hardware is classified once per admission (after the grant); display facts follow the live window.
func _context() -> Dictionary:
	var ctx: Dictionary = context_provider.call() if context_provider.is_valid() else {}
	if _hardware.is_empty():
		var facts := hardware_facts.duplicate()
		facts.window_size = Vector2i.ZERO
		_hardware = Hardware.context(facts)
	var out := _hardware.duplicate()
	var live := hardware_facts.duplicate()
	live.window_size = ctx.get("window_size", Vector2i.ZERO)
	live.vsync = int(ctx.get("vsync", -1))
	if ctx.has("max_fps"):
		live.max_fps = int(ctx.max_fps)
	out.resolution_class = Hardware.resolution_class(live.window_size)
	out.resolution_basis = "viewport_coordinates" if live.window_size != Vector2i.ZERO else "unknown"
	out.vsync = Hardware.vsync(live.vsync)
	out.fps_cap_bucket = Hardware.fps_cap(int(live.get("max_fps", Engine.max_fps)))
	var source: Variant = graphics_profile_provider.call() if graphics_profile_provider.is_valid() \
		else ctx.get("graphics_profile", "unknown")
	var profile := str(source)
	out.graphics_profile = profile if profile in Contract.CONTEXT_VALUES.graphics_profile else "unknown"
	var input := str(ctx.get("input_class", "unknown"))
	out.input_class = input if input in Contract.CONTEXT_VALUES.input_class else "unknown"
	return out


func _on_sent(serial: int, status: int, retry_after_s: float) -> void:
	if state != Policy.ON or not queue.is_active(serial):
		return # a request from an earlier generation, or the gate closed meanwhile
	var outcome: String = queue.complete(serial, status, int(clock_usec.call()) / 1000000.0, retry_after_s)
	if outcome == Queue.SUSPEND:
		# The service refused this build: off for this process; the saved choice is unchanged.
		suspended = true
		_stop()
		_apply()
		return
	state_changed.emit()
