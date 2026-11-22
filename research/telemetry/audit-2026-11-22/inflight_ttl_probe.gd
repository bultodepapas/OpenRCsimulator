# Actual service _process and queue with a controllable no-network sender.
# Use run_godot_probes.py to copy exact dependencies into an isolated project.
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

class FakeSender:
	extends Node
	signal finished(serial: int, status: int, retry_after_s: float)
	var active := false
	var last_serial := -1
	var send_count := 0
	var cancel_count := 0
	func busy() -> bool:
		return active
	func send(_endpoint: String, _body: PackedByteArray, serial: int) -> bool:
		active = true
		last_serial = serial
		send_count += 1
		return true
	func answer(status: int, retry_after: float = -1.0) -> void:
		active = false
		finished.emit(last_serial, status, retry_after)
	func cancel() -> void:
		active = false
		cancel_count += 1

var now_usec := 0

func _initialize() -> void:
	var s := Service.new()
	var fake := FakeSender.new()
	s.sender = fake
	fake.finished.connect(s._on_sent)
	s.state = "on"
	s.release = {"notice": Contract.NOTICE_VERSION, "release_id": "v0.3.2", "channel": "stable",
		"endpoint": "http://127.0.0.1:9/never-used"}
	s.clock_usec = func() -> int: return now_usec
	s.utc_day = func() -> String: return "2026-11-22"
	s.context_provider = func() -> Dictionary: return {"eligible": false, "activity": false, "mode": "home"}
	s.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen", "threads": 8,
		"memory_bytes": 8589934592, "gpu": "NVIDIA GeForce RTX", "renderer": "forward_plus", "driver": "vulkan"}
	s._session_id = "a".repeat(32)
	s._session_day = "2026-11-22"
	s._session_start_usec = 0
	s._append({"name": "session_started"}, 0)
	s._seal(0)
	s._process(0.0)
	if not fake.busy():
		printerr("INCONCLUSIVE: first request was not started")
		s.free()
		fake.free()
		quit(1)
		return
	fake.answer(429, 599.0)
	now_usec = 599000000
	s._process(0.0) # retry starts one second before the original 600 s TTL
	var retry_started: bool = fake.busy() and fake.send_count == 2
	now_usec = 600000000
	s._process(0.0) # queue deadline reached during a live request
	var busy_at_deadline: bool = fake.busy()
	var retained_at_deadline: bool = not s.queue.items.is_empty()
	var cancels_at_deadline: int = fake.cancel_count
	now_usec = 601000000
	s._process(0.0)
	fake.answer(202)
	var accepted_after_deadline: bool = s.queue.sent_ok == 1
	print("INFLIGHT_TTL_PROBE ", JSON.stringify({"retry_started_at_599": retry_started,
		"sender_busy_at_600": busy_at_deadline, "queue_retained_at_600": retained_at_deadline,
		"cancel_count_at_600": cancels_at_deadline, "accepted_202_at_601": accepted_after_deadline}))
	var reproduced := retry_started and busy_at_deadline and retained_at_deadline \
		and cancels_at_deadline == 0 and accepted_after_deadline
	s.free()
	fake.free()
	if reproduced:
		print("REPRODUCED: an in-flight request survives the original queue deadline and a late 202 is accepted")
		quit(0)
	else:
		printerr("INCONCLUSIVE: expected source-state signature was not observed")
		quit(1)
