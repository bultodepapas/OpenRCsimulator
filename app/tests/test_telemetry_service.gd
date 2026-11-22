# TELEM-02…06: the telemetry service end to end with injected clocks, a scripted observation context and a fake
# sender: nothing before Enable, cadence windows, activity summaries, sealing, sending, the off switch and its
# generation fence, locale gating, service suspension and session rotation. No network.
# Run: godot --headless --path . --script res://tests/test_telemetry_service.gd
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Store := preload("res://telemetry/telemetry_consent_store.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")
const Queue := preload("res://telemetry/telemetry_queue.gd")
const FlightEvent := preload("res://statistics/flight_event.gd")

const PATH := "user://test_telemetry_service_consent.cfg"
const FRAME_US := 16667


class FakeSender extends Node:
	signal finished(serial: int, status: int, retry_after_s: float)
	var sent: Array[Dictionary] = []
	var cancels := 0
	var _busy := false

	func busy() -> bool:
		return _busy

	func send(endpoint: String, body: PackedByteArray, serial: int) -> bool:
		sent.append({"endpoint": endpoint, "body": body, "serial": serial})
		_busy = true
		return true

	func cancel() -> void:
		cancels += 1
		_busy = false

	func answer(status: int, retry_after := -1.0) -> void:
		var last: Dictionary = sent[-1]
		_busy = false
		finished.emit(int(last.serial), status, retry_after)


var _failures := 0
var _now := 0
var _frames := 0
var _day := 20775 # 2026-11-18, as days since the Unix epoch
var _ctx := {}


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	await process_frame # the root must be in the tree so add_child() runs _ready() at once
	_remove()
	_unavailable()
	_lifecycle()
	_context_boundaries()
	_activities()
	_crash_revisions_across_slices()
	_off_switch_and_suspension()
	_rotation_and_partial_activity()
	_epoch_entry_boundaries()
	_observation_retention()
	_sealing_can_evict_the_active_batch()
	await _notification_can_disable_after_rotation()
	_quit_in_flight_keeps_slices()
	_remove()
	print("all telemetry service checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _service(release := {}) -> Node:
	var s: Node = Service.new()
	s.release = release if not release.is_empty() else {"ok": true, "reason": "qualification",
		"endpoint": "http://127.0.0.1:9/v1/batches", "operator": "Test", "contact": "-", "release_id": "v0.2.9",
		"channel": "stable", "notice": Contract.NOTICE_VERSION, "qualification": true}
	s.interactive = true
	s.consent_path = PATH
	s.locale = "en"
	s.clock_usec = func() -> int: return _now
	s.frames_drawn = func() -> int: return _frames
	s.utc_day = func() -> int: return _day
	s.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen 5 5600X", "threads": 12,
		"memory_bytes": 17179869184, "gpu": "NVIDIA GeForce RTX 3060", "renderer": "forward_plus", "driver": "vulkan"}
	s.context_provider = func() -> Dictionary: return _ctx
	s.sender = FakeSender.new()
	_ctx = {"mode": "home", "activity": false, "vehicle": "", "eligible": true, "window_size": Vector2i(1920, 1080), "vsync": 1,
		"max_fps": 0, "graphics_profile": "unknown", "input_class": "keyboard"}
	root.add_child(s)
	return s


## Advance `seconds` of eligible 60 Hz frames, letting the service process each one.
func _run(s: Node, seconds: float) -> void:
	var steps := int(seconds * 1000000.0 / FRAME_US)
	for i: int in steps:
		_now += FRAME_US
		_frames += 1
		if _ctx.has("simulated_seconds"):
			_ctx.simulated_seconds = float(_ctx.simulated_seconds) + FRAME_US / 1000000.0
		s._process(0.0)


func _batches(s: Node) -> Array:
	var out := []
	for item: Dictionary in s.queue.items:
		out.append(JSON.parse_string(item.body.get_string_from_utf8()))
	return out


func _events(s: Node, name: String) -> Array:
	var out := []
	for batch: Variant in _batches(s):
		for event: Dictionary in batch.events:
			if event.name == name:
				out.append(event)
	for event: Dictionary in s._pending:
		if event.name == name:
			out.append(event)
	return out


func _unavailable() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	var s := _service({"ok": false, "reason": "development"})
	_check("a build without telemetry is unavailable even with a saved grant", s.state == "unavailable"
		and not s.is_processing())
	_check("an unavailable build cannot be enabled", s.enable() == ERR_UNAVAILABLE and s.state == "unavailable")
	s.disable()
	_check("disabling an unavailable build writes nothing", Store.load_choice(PATH).choice == "enabled")
	s.queue_free()
	_remove()


func _lifecycle() -> void:
	var s := _service()
	_check("first launch asks and collects nothing", s.state == "ask" and s.reason == "unset" and not s.is_processing(),
		"%s processing=%s" % [str(s.status()), s.is_processing()])
	_run(s, 70.0)
	_check("nothing is queued or sent before Enable", s.queue.items.is_empty() and s._pending.is_empty()
		and s.sender.sent.is_empty())
	_check("Enable is saved", s.enable() == OK and Store.load_choice(PATH).choice == "enabled" and s.state == "on")
	_check("admission starts a session", _events(s, "session_started").size() == 1)
	_run(s, 41.0)
	var windows := _events(s, "performance_window")
	_check("ten seconds of warmup, then a complete 30 s steady window", windows.size() == 2
		and windows[0].phase == "warmup" and not windows[0].window_complete and windows[1].phase == "steady"
		and windows[1].window_complete and windows[1].mode == "home" and windows[1].vehicle_id == "none", str(windows))
	_check("drawn frames equal processed intervals at 60 Hz", int(windows[1].rendered_frames) == int(windows[1].interval_count))
	_run(s, 20.0)
	_check("a batch is sealed after 60 s", s.queue.items.size() == 1, str(s.queue.items.size()))
	var batch: Dictionary = _batches(s)[0]
	_check("the sealed batch carries the classified context only", batch.context.gpu_family == "nvidia_rtx"
		and batch.context.cpu_family == "amd_ryzen" and batch.context.resolution_class == "1080p"
		and batch.context.fps_cap_bucket == "unlimited" and batch.context.input_class == "keyboard"
		and not JSON.stringify(batch).contains("3060") and not JSON.stringify(batch).contains("5600"), str(batch.context))
	_check("the sealed batch satisfies the contract", Contract.check_batch(_ints(batch)) == "", Contract.check_batch(_ints(batch)))
	_check("it was sent to the configured endpoint", s.sender.sent.size() == 1
		and s.sender.sent[0].endpoint == "http://127.0.0.1:9/v1/batches" and s.sender.sent[0].body == s.queue.items[0].body)
	_check("the preview shows the exact pending bytes", s.preview_text().contains(s.queue.items[0].body.get_string_from_utf8()))
	s.sender.answer(202)
	_check("202 removes it", s.queue.items.is_empty() and s.queue.sent_ok == 1 and s.status().sent == 1)
	_check("without a graphics provider the context's own value applies", batch.context.graphics_profile == "unknown")
	_ctx.graphics_profile = "custom"
	s.note_error("asset_load_failed")
	s.note_error("asset_load_failed")
	s.note_error("not_a_category")
	_run(s, 61.0)
	var errors := _events(s, "error_count")
	_check("errors are coalesced counters", errors.size() == 1 and int(errors[0].count) == 2
		and errors[0].category == "asset_load_failed", str(errors))
	_check("a new window uses the applied graphics profile", s._pending_context.get("graphics_profile") == "custom",
		str(s._pending_context))
	_ctx.eligible = false
	_run(s, 1.0)
	_check("a pause closes the open window as partial", _events(s, "performance_window").back().window_complete == false)
	_ctx.eligible = true
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(PATH + ".tmp")) # the decline cannot be written
	_check("a failed decline is reported, stays off and leaves no grant on disk", s.disable() != OK and s.state == "off"
		and Store.load_choice(PATH).choice != "enabled" and s.status().save_error != OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ".tmp"))
	s.queue_free()


func _context_boundaries() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	for change: Dictionary in [
		{"window_size": Vector2i(3840, 2160)}, {"window_size": Vector2i(1919, 1080)},
		{"vsync": DisplayServer.VSYNC_DISABLED}, {"max_fps": 60},
		{"input_class": "gamepad"}, {"graphics_revision": 1}, {"activity_revision": 1},
		{"activity_id": 2},
	]:
		var s := _service()
		_ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250", "activity_id": 1,
			"simulated_seconds": 0.0, "max_fps": 50, "graphics_profile": "custom"}, true)
		_run(s, 25.0)
		var old_context: Dictionary = s._window_context
		_ctx.merge(change, true)
		_run(s, 41.0)
		var measured := []
		var batches := _batches(s)
		batches.append({"context": s._pending_context, "events": s._pending})
		for b: Dictionary in batches:
			for event: Dictionary in b.events:
				if event.name == "performance_window":
					measured.append({"context": b.context, "event": event})
		_check("context change splits a partial and restarts warmup: " + str(change),
			measured.size() == 4 and measured[1].context == old_context
			and measured[1].event.phase == "steady" and not measured[1].event.window_complete
			and int(measured[1].event.interval_sum_us) < 15_050_000
			and measured[2].event.phase == "warmup" and not measured[2].event.window_complete
			and measured[3].context == s._window_context and measured[3].event.window_complete
			and int(measured[3].event.interval_sum_us) >= 30_000_000, str(measured))
		if change.has("activity_revision"):
			_check("a presentation/recorder boundary alone does not complete an activity",
				_events(s, "activity_summary").is_empty())
		s.queue_free()


func _activities() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH) # a saved grant admits at start-up
	var s := _service()
	_run(s, 1.0)
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250", "fixed_wing_accepted": true, "simulated_seconds": 0.0}, true)
	_run(s, 5.0)
	var crash := FlightEvent.make({}, "CRASH", 1, 3, "flight", "episode", "accident")
	s.note_flight_events([{"type": "TAKEOFF"}, {"type": "TOUCHDOWN"}, {"type": "LANDING_SUCCESS"}, crash, "x"])
	_run(s, 5.0)
	_ctx.merge({"mode": "home", "activity": false, "vehicle": "", "fixed_wing_accepted": false}, true)
	_ctx.erase("simulated_seconds")
	_run(s, 1.0)
	var summaries := _events(s, "activity_summary")
	_check("a fixed-wing flight is summarized when it returns home", summaries.size() == 1, str(summaries))
	if summaries.size() == 1:
		var a: Dictionary = summaries[0]
		_check("accepted classifier counts, durations and outcome", a.vehicle_id == "f4u-corsair-250"
			and a.classification == "accepted_fixed_wing" and int(a.takeoffs) == 1 and int(a.landings) == 1
			and int(a.aircraft_crashes) == 1 and a.outcome == "returned_home" and a.complete_observation == true
			and int(a.active_seconds) == 9 and int(a.simulated_seconds) == 9, str(a))
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "mt8-bisonte", "simulated_seconds": 0.0}, true)
	_run(s, 3.0)
	_ctx.simulated_seconds = 0.0 # restarted
	_run(s, 2.0)
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "my-own-truck", "custom": true}, true)
	_run(s, 2.0)
	_ctx.merge({"mode": "home", "activity": false, "vehicle": "", "custom": false}, true)
	_ctx.erase("simulated_seconds")
	_run(s, 1.0)
	summaries = _events(s, "activity_summary")
	_check("a restart closes the car's activity as reset, with no classifier counts", summaries.size() == 4
		and summaries[1].outcome == "reset" and summaries[1].classification == "unsupported"
		and summaries[1].takeoffs == null and summaries[1].vehicle_id == "mt8-bisonte", str(summaries))
	_check("custom content is never named", summaries.size() == 4 and summaries[3].vehicle_id == "custom"
		and not JSON.stringify(_batches(s)).contains("my-own-truck"))
	# Workshop editing is measured as its own mode with no vehicle, and is not a vehicle activity.
	_ctx.merge({"mode": "workshop", "activity": false, "vehicle": "my-draft", "custom": true}, true)
	_run(s, 12.0)
	_ctx.merge({"mode": "home", "activity": false, "vehicle": "", "custom": false}, true)
	_run(s, 1.0)
	var workshop_windows := _events(s, "performance_window").filter(func(w: Dictionary) -> bool: return w.mode == "workshop")
	_check("Workshop editing: windows with no vehicle and no activity summary", not workshop_windows.is_empty()
		and workshop_windows.all(func(w: Dictionary) -> bool: return w.vehicle_id == "none")
		and _events(s, "activity_summary").size() == 4 and not JSON.stringify(_batches(s)).contains("my-draft"), str(workshop_windows))
	s.queue_free()


func _crash_revisions_across_slices() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	var s := _service()
	_run(s, 1.0)
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250", "fixed_wing_accepted": true,
		"simulated_seconds": 0.0}, true)
	_run(s, 1.0)
	var first := FlightEvent.make({}, "CRASH", 2, 7, "flight", "episode", "first")
	var update := FlightEvent.make({}, "CRASH", 3, 8, "flight", "episode", "first", {}, true, 1)
	var next := FlightEvent.make({}, "CRASH", 4, 12, "flight", "episode-2", "second", {}, true)
	_check("crash fixtures follow the semantic event contract", FlightEvent.valid(first) and FlightEvent.valid(update)
		and FlightEvent.valid(next))
	s.note_flight_events([first, first])
	_run(s, 300.0)
	s.note_flight_events([update, first, next, next])
	# The detector may reset even when the sampled simulated clock changes by less than 0.5 seconds.
	_ctx.simulated_seconds = float(_ctx.simulated_seconds) - 0.25
	_run(s, 0.1)
	var short_restart := FlightEvent.make({"generation_id": "short-reset"}, "CRASH", 1, 1, "new-flight", "episode", "third")
	s.note_flight_events([short_restart, short_restart])
	# Statistics can emit the next generation before the telemetry frame sampler sees the reset.
	var restarted := FlightEvent.make({"generation_id": "reset"}, "CRASH", 2, 1, "new-flight", "episode", "fourth")
	s.note_flight_events([restarted])
	_ctx.simulated_seconds = 0.0
	_run(s, 1.0)
	s.note_flight_events([restarted])
	var next_after_reset := FlightEvent.make({"generation_id": "reset"}, "CRASH", 4, 2, "new-flight", "episode", "fifth")
	s.note_flight_events([next_after_reset])
	_ctx.merge({"mode": "home", "activity": false}, true)
	_run(s, 1.0)
	var summaries := _events(s, "activity_summary")
	_check("crash counts track initial events across slices and detector generations",
		summaries.size() == 3 and summaries[0].outcome == "slice" and summaries[1].outcome == "reset"
		and summaries[2].outcome == "returned_home"
		and summaries.map(func(a: Dictionary) -> int: return int(a.aircraft_crashes)) == [1, 3, 1], str(summaries))
	_check("classifier identifiers stay out of the telemetry preview", not s.preview_text().contains("short-reset")
		and not s.preview_text().contains("generation_id") and not s.preview_text().contains("sequence"))
	s.queue_free()


func _off_switch_and_suspension() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	var s := _service()
	_run(s, 65.0)
	_check("a request is in flight", s.sender.sent.size() == 1 and s.sender.busy())
	var generation: int = s.generation
	_check("turning off saves the choice", s.disable() == OK and Store.load_choice(PATH).choice == "disabled")
	_check("off drops every pending byte, window and token", s.state == "off" and s.reason == "declined"
		and s.queue.items.is_empty() and s._pending.is_empty() and s._session_id == "" and s._window == null
		and s.generation > generation and s.sender.cancels >= 1 and not s.is_processing())
	s.sender.finished.emit(int(s.sender.sent[0].serial), 202, -1.0)
	_check("a late answer from before the switch changes nothing", s.queue.sent_ok == 0)
	_run(s, 70.0)
	_check("nothing is collected while off", s.queue.items.is_empty() and s._pending.is_empty())
	s.enable()
	var session_after: String = s._session_id
	_check("re-enabling starts a fresh session", session_after != "" and s.state == "on")
	s.set_locale("de")
	_check("an unreviewed language turns collection off without changing the saved choice", s.state == "off"
		and s.reason == "locale" and s._session_id == "" and Store.load_choice(PATH).choice == "enabled")
	s.set_locale("es")
	_check("a reviewed language resumes with another fresh session", s.state == "on" and s._session_id != session_after)
	_run(s, 65.0)
	s.sender.answer(410)
	_check("410 suspends this process but keeps the player's choice", s.state == "off" and s.reason == "suspended"
		and s.queue.items.is_empty() and Store.load_choice(PATH).choice == "enabled")
	_check("a suspended service cannot be re-enabled in-process", s.enable() == ERR_UNAVAILABLE and s.state == "off")
	s.queue_free()


func _rotation_and_partial_activity() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	_ctx = {}
	var s := _service()
	# The saved grant admits at start-up, while a flight is already running: that activity is not complete.
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "p51d-mustang-120", "fixed_wing_accepted": true, "simulated_seconds": 0.0}, true)
	_check("a saved grant admits at start-up", s.state == "on")
	_run(s, 3.0)
	_ctx.merge({"mode": "home", "activity": false, "vehicle": "", "fixed_wing_accepted": false}, true)
	_ctx.erase("simulated_seconds")
	_run(s, 1.0)
	var summaries := _events(s, "activity_summary")
	_check("an activity already running at admission is not a complete observation", summaries.size() == 1
		and summaries[0].complete_observation == false, str(summaries))
	s._seal(_now)
	var first: String = s._session_id
	_day = 20776
	_run(s, 31.0)
	_check("the UTC day boundary rotates the session token", s._session_id != first and s._session_id != "")
	var sessions := {}
	for batch: Variant in _batches(s):
		sessions[batch.session_id] = true
	_check("old batches keep their own token", sessions.has(first), str(sessions.keys()))
	_now += 4 * 3600 * 1000000
	var second: String = s._session_id
	_now += FRAME_US
	s._process(0.0) # the first frame after the bound retires the previous token
	_check("four hours rotate the session token before observing a new frame", s._session_id != second
		and s._pending.is_empty() and s._seq == 0)
	s.queue_free()


func _epoch_entry_boundaries() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	for entry: String in ["frame", "error", "flight_event"]:
		_day = 20777
		var s := _service()
		_ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250",
			"simulated_seconds": 0.0, "fixed_wing_accepted": true}, true)
		_run(s, 15.0)
		s._seal(_now)
		s._process(0.0)
		var old_session: String = s._session_id
		var old_generation: int = s.generation
		var sealed: Dictionary = s.queue.items[0].duplicate(true)
		_check("the old epoch has an in-flight batch, an open window and an activity",
			s.sender.busy() and s._window != null and not s._window.is_empty() and not s._activity.is_empty())

		s.note_error("asset_load_failed")
		s.note_error("renderer_unavailable")
		s.note_flight_events([{"type": "TAKEOFF"}])
		for _index: int in Contract.MAX_EVENTS - 1:
			s._append(Contract.error_count(0, "aircraft_validation_failed", 1), _now)
		var notified := [false]
		s.state_changed.connect(func() -> void: notified[0] = true)

		_ctx.eligible = false
		if entry == "flight_event":
			_now = s._session_start_usec + Service.SESSION_MAX_US
			_ctx.simulated_seconds = 100.0
			s.note_flight_events([{"type": "LANDING_SUCCESS"}])
		elif entry == "error":
			_day = 20776 # a UTC clock correction also retires the epoch
			s.note_error("simulation_fault")
		else:
			_day = 20778
			_now += FRAME_US
			s._process(0.0)

		_check("the first post-boundary " + entry + " opens a fresh epoch before collection",
			s._session_id != old_session and s.generation == old_generation and s._window == null
			and s._last_usec == -1 and s._pending_session.is_empty() and s._pending.is_empty()
			and s._seq == 0 and not notified[0])
		var expected_errors: Dictionary = {"simulation_fault": 1} if entry == "error" else {}
		_check("the old epoch's unsealed observations do not cross the boundary",
			s._errors == expected_errors and not s._activity.is_empty() and not s._activity.complete
			and int(s._activity.active_us) == 0 and int(s._activity.takeoffs) == 0
			and int(s._activity.landings) == (1 if entry == "flight_event" else 0))
		if entry == "flight_event":
			_check("an expired old request is canceled on the exact four-hour rotation",
				s.queue.items.is_empty() and not s.sender.busy() and s.sender.cancels == 1)
		else:
			_check("a sealed batch retains its bytes, serial, retry state and original deadline",
				s.queue.items.size() == 1 and s.queue.items[0] == sealed and s.sender.busy())
			_now = roundi((float(sealed.observed) + Queue.TTL_S) * 1000000.0)
			s._process(0.0)
			_check("the old request expires at its original deadline after rotation",
				not s.queue.is_active(int(sealed.serial)) and s.sender.cancels == 1)
		s.sender.finished.emit(int(sealed.serial), 410, -1.0)
		_check("a late refusal from an expired request cannot suspend a later epoch", s.state == "on")
		s.queue_free()
	_day = 20775


func _observation_retention() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	_now = 0
	var s := _service()
	_ctx.eligible = false
	s._process(0.0) # Session start at monotonic time zero.
	_now = 60_000_000
	s._seal(_now)
	var sealed: Dictionary = s.queue.items[0]
	_check("sealing keeps the oldest observation timestamp", sealed.created == 60.0 and sealed.observed == 0.0)
	_now = Queue.TTL_USEC - 1
	s._process(0.0)
	_check("the batch can start one microsecond before its observation deadline", s.sender.busy())
	_now = Queue.TTL_USEC
	s._process(0.0)
	_check("an unanswered request is canceled at the original deadline",
		s.queue.items.is_empty() and not s.sender.busy() and s.sender.cancels == 1)
	_now += 1_000_000
	s.sender.finished.emit(int(sealed.serial), 202, -1.0)
	s.sender.finished.emit(int(sealed.serial), 410, -1.0)
	_check("late acceptance and refusal have no effect", s.queue.sent_ok == 0 and s.state == "on")
	s.queue_free()

	_now = 0
	s = _service()
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250",
		"simulated_seconds": 0.0, "fixed_wing_accepted": true}, true)
	_run(s, 0.1)
	s.note_flight_events([{"type": "TAKEOFF"}])
	s.note_error("asset_load_failed")
	var last_old := _now
	_now += Queue.TTL_USEC - 1
	s.note_error("simulation_fault")
	s._append(Contract.error_count(0, "renderer_unavailable", 1), _now)
	_now = last_old + Queue.TTL_USEC
	s.note_flight_events([{"type": "LANDING_SUCCESS"}])
	s._seal(_now)
	var counts := _events(s, "error_count")
	_check("pre-seal expiry removes old data while keeping fresh events and counters",
		_events(s, "session_started").is_empty() and counts.size() == 2
		and counts[0].category == "renderer_unavailable" and counts[1].category == "simulation_fault", str(counts))
	_check("a long stall discards the old window and starts an incomplete activity",
		s._window == null and s._last_usec == -1 and not s._activity.complete
		and s._activity.active_us == 0 and s._activity.takeoffs == 0 and s._activity.landings == 1)
	s.queue_free()


func _sealing_can_evict_the_active_batch() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	_now = 0
	var s := _service()
	_ctx.eligible = false
	s._process(0.0)
	s._seal(_now)
	s._process(0.0)
	var active: int = s.queue.active_serial
	for _index: int in Queue.MAX_BATCHES:
		s.note_error("asset_load_failed")
		s._seal(_now)
	_check("capacity eviction during sealing cancels the active request immediately",
		s.queue.items.size() == Queue.MAX_BATCHES and not s.queue.is_active(active)
		and not s.sender.busy() and s.sender.cancels == 1)
	s.sender.finished.emit(active, 410, -1.0)
	_check("an evicted request cannot suspend collection", s.state == "on")
	s.queue_free()


func _notification_can_disable_after_rotation() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	var s := _service()
	s.set_process(false)
	var old: String = s._session_id
	var observed := [false, false]
	s.state_changed.connect(func() -> void:
		if observed[0]:
			return
		observed[0] = true
		observed[1] = s.state == "on" and s._session_id != old and s._errors.get("simulation_fault") == 1
		s.disable())
	_day += 1
	s.note_error("simulation_fault")
	await process_frame
	_check("a state listener can revoke consent after observing the completed rotation",
		observed == [true, true] and s.state == "off" and s._session_id.is_empty()
		and s.queue.items.is_empty() and s._errors.is_empty())
	s.queue_free()
	_day = 20775


## TELEM-19: a 12-minute flight that ends by quitting (no return to Home) still reports 10 minutes of usage in
## 5-minute slices; before, nothing was reported for flights shorter than the 30-minute slice.
func _quit_in_flight_keeps_slices() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH)
	_day = 20775
	var s := _service()
	_run(s, 1.0)
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250", "fixed_wing_accepted": true,
		"simulated_seconds": 0.0}, true)
	# Answer during flight so this test measures the final unsealed slice, independently of offline expiry.
	for _second: int in 751:
		_run(s, 1.0)
		if s.sender.busy():
			s.sender.answer(202)
	var slices := {}
	var bodies: Array = []
	for item: Dictionary in s.sender.sent:
		bodies.append(JSON.parse_string(item.body.get_string_from_utf8()))
	bodies.append_array(_batches(s))
	for batch: Variant in bodies:
		for event: Dictionary in batch.events:
			if event.name == "activity_summary":
				slices[int(event.seq)] = event
	var total := 0
	var all_slices := true
	for event: Dictionary in slices.values():
		total += int(event.active_seconds)
		all_slices = all_slices and event.outcome == "slice" and event.complete_observation == false
	_check("quitting a 12-minute flight keeps two 5-minute slices", slices.size() == 2 and total >= 590
		and all_slices, str(slices.values()))
	s.queue_free() # quitting: the open third slice is dropped, as before


func _ints(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _ints(value[key])
		return out
	if value is Array:
		return value.map(_ints)
	if typeof(value) == TYPE_FLOAT and value == floorf(value):
		return int(value)
	return value


func _remove() -> void:
	for name: String in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(name):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(name))
