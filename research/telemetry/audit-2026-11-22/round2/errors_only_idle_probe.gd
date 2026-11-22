# Reproduce error-only delivery starvation through the actual service loop.
# No profile, tree admission or network is used. Run through the checked runner
# against an isolated project containing the baseline telemetry modules.
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

class FakeSender:
	extends Node
	signal finished(serial: int, status: int, retry_after_s: float)
	var active := false
	var serial := -1
	var bodies: Array[PackedByteArray] = []
	var cancels := 0
	func busy() -> bool:
		return active
	func send(_endpoint: String, body: PackedByteArray, value: int) -> bool:
		active = true
		serial = value
		bodies.append(body.duplicate())
		return true
	func answer(status: int) -> void:
		active = false
		finished.emit(serial, status, -1.0)
	func cancel() -> void:
		active = false
		cancels += 1

var now_usec := 0
var frames := 0
var ctx := {"mode": "home", "activity": false, "vehicle": "", "eligible": false,
	"window_size": Vector2i(1920, 1080), "vsync": 1, "max_fps": 0,
	"graphics_profile": "current_default", "input_class": "keyboard"}

func _initialize() -> void:
	var s := Service.new()
	var fake := FakeSender.new()
	s.sender = fake
	fake.finished.connect(s._on_sent)
	s.release = {"ok": true, "reason": "qualification", "qualification": true,
		"notice": Contract.NOTICE_VERSION, "release_id": "v0.3.2", "channel": "stable",
		"endpoint": "http://127.0.0.1:9/never-used", "operator": "Synthetic", "contact": "-"}
	s.interactive = true
	s.choice = "enabled"
	s.choice_notice = Contract.NOTICE_VERSION
	s.locale = "en"
	s.state = "on"
	s.clock_usec = func() -> int: return now_usec
	s.frames_drawn = func() -> int: return frames
	s.utc_day = func() -> String: return "2026-11-22"
	s.context_provider = func() -> Dictionary: return ctx
	s.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen", "threads": 8,
		"memory_bytes": 8589934592, "gpu": "NVIDIA GeForce RTX", "renderer": "forward_plus", "driver": "vulkan"}
	# Start and successfully drain the initial batch. This is the normal state
	# after an opted-in process has sent its first batch.
	s._start()
	s._seal(0)
	s._process(0.0)
	if not fake.busy():
		printerr("INCONCLUSIVE: initial batch was not sent")
		s.free()
		fake.free()
		quit(1)
		return
	fake.answer(202)
	var started_clean: bool = s.queue.items.is_empty() and s._pending.is_empty() and s.queue.sent_ok == 1
	# The error occurs after the initial batch, while no window can close.
	now_usec = 1000000
	s.note_error("asset_load_failed")
	for seconds: int in [61, 121, 181, 601]:
		now_usec = seconds * 1000000
		s._process(0.0)
	var idle_error_count: int = int(s._errors.get("asset_load_failed", 0))
	var sends_after_idle: int = fake.bodies.size()
	var pending_after_idle: int = int(s.status().pending)
	var preview_empty: bool = s.preview_text().is_empty()
	var no_counter_batch: bool = s.queue.items.is_empty() and s._pending.is_empty()
	# Control: an eligible warmup window eventually creates another event;
	# sealing it does include the error counter.
	ctx.eligible = true
	for seconds in range(602, 613):
		now_usec = seconds * 1000000
		frames += 1
		s._process(0.0)
	var delivered_after_resume := false
	if fake.bodies.size() == 2:
		var decoded: Variant = JSON.parse_string(fake.bodies.back().get_string_from_utf8())
		if decoded is Dictionary:
			for event: Dictionary in decoded.events:
				if event.name == "error_count" and event.category == "asset_load_failed" and event.count == 1:
					delivered_after_resume = true
		fake.answer(202)
	# Consent control: another recorded error is erased when admission closes,
	# and later callbacks, off-state note_error and re-admission cannot resurrect it.
	s.note_error("asset_load_failed")
	var before_off_sends: int = fake.bodies.size()
	s.set_locale("de")
	var cleared_on_off: bool = s.state == "off" and s._errors.is_empty() and s.queue.items.is_empty()
	fake.finished.emit(fake.serial, 202, -1.0)
	s.note_error("asset_load_failed")
	s._process(0.0)
	var no_send_while_off: bool = fake.bodies.size() == before_off_sends and s._errors.is_empty()
	s.set_locale("en")
	var no_replay_on_reenable: bool = s.state == "on" and s._errors.is_empty()
	print("ERRORS_ONLY_IDLE_PROBE ", JSON.stringify({"initial_batch_drained": started_clean,
		"idle_elapsed_seconds": 600, "idle_error_count": idle_error_count,
		"total_sends_after_idle": sends_after_idle, "status_pending": pending_after_idle,
		"preview_empty": preview_empty, "no_counter_batch": no_counter_batch,
		"eventually_sent_after_resume": delivered_after_resume, "cleared_on_off": cleared_on_off,
		"no_send_while_off": no_send_while_off, "no_replay_on_reenable": no_replay_on_reenable}))
	var reproduced: bool = started_clean and idle_error_count == 1 and sends_after_idle == 1 \
		and pending_after_idle == 0 and preview_empty and no_counter_batch and delivered_after_resume \
		and cleared_on_off and no_send_while_off and no_replay_on_reenable
	s.free()
	fake.free()
	if reproduced:
		print("REPRODUCED: an errors-only observation remains unsent through ten idle minutes")
		quit(0)
	else:
		printerr("INCONCLUSIVE: expected source-state signature was not observed")
		quit(1)
