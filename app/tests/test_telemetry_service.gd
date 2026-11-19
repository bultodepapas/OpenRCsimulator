# TELEM-02…06: the telemetry service end to end with injected clocks, a scripted observation context and a fake
# sender: nothing before Enable, cadence windows, activity summaries, sealing, sending, the off switch and its
# generation fence, locale gating, service suspension and session rotation. No network.
# Run: godot --headless --path . --script res://tests/test_telemetry_service.gd
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Store := preload("res://telemetry/telemetry_consent_store.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")
const Queue := preload("res://telemetry/telemetry_queue.gd")

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
var _day := "2026-11-18"
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
	_activities()
	_off_switch_and_suspension()
	_rotation_and_partial_activity()
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
	s.utc_day = func() -> String: return _day
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
	var profile_asks := [0]
	s.graphics_profile_provider = func() -> String:
		profile_asks[0] += 1
		return "custom"
	s.note_error("asset_load_failed")
	s.note_error("asset_load_failed")
	s.note_error("not_a_category")
	_run(s, 61.0)
	var errors := _events(s, "error_count")
	_check("errors are coalesced counters", errors.size() == 1 and int(errors[0].count) == 2
		and errors[0].category == "asset_load_failed", str(errors))
	var later: Dictionary = _batches(s).back()
	_check("the graphics profile comes from its provider, asked per recorded event, not per frame",
		later.context.graphics_profile == "custom" and int(profile_asks[0]) >= 1 and int(profile_asks[0]) <= 10,
		"%s asks=%d" % [later.context, profile_asks[0]])
	_ctx.eligible = false
	_run(s, 1.0)
	_check("a pause closes the open window as partial", _events(s, "performance_window").back().window_complete == false)
	_ctx.eligible = true
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(PATH + ".tmp")) # the decline cannot be written
	_check("a failed decline is reported, stays off and leaves no grant on disk", s.disable() != OK and s.state == "off"
		and Store.load_choice(PATH).choice != "enabled" and s.status().save_error != OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ".tmp"))
	s.queue_free()


func _activities() -> void:
	Store.save_choice("enabled", Contract.NOTICE_VERSION, PATH) # a saved grant admits at start-up
	var s := _service()
	_run(s, 1.0)
	_ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250", "fixed_wing_accepted": true, "simulated_seconds": 0.0}, true)
	_run(s, 5.0)
	s.note_flight_events([{"type": "TAKEOFF"}, {"type": "TOUCHDOWN"}, {"type": "LANDING_SUCCESS"}, {"type": "CRASH"}, "x"])
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
	var first: String = s._session_id
	_day = "2026-11-19"
	_run(s, 31.0)
	_check("the UTC day boundary rotates the session token", s._session_id != first and s._session_id != "")
	var sessions := {}
	for batch: Variant in _batches(s):
		sessions[batch.session_id] = true
	_check("old batches keep their own token", sessions.has(first), str(sessions.keys()))
	_now += 4 * 3600 * 1000000
	var second: String = s._session_id
	_run(s, 31.0) # the next event after the bound (a closed window) carries a new token
	_check("four hours rotate the session token for the next event", s._session_id != second
		and s._pending.size() > 0 and s._pending_session == s._session_id)
	s.queue_free()


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
