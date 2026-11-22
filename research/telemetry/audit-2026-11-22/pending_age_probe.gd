# Reproduces pending observation age exceeding the advertised 10 minute limit.
# Use run_godot_probes.py to copy exact dependencies into an isolated project.
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

func _initialize() -> void:
	var s := Service.new()
	s.state = "on"
	s.release = {"notice": Contract.NOTICE_VERSION, "release_id": "v0.3.2", "channel": "stable"}
	s.clock_usec = func() -> int: return 0
	s.utc_day = func() -> String: return "2026-11-22"
	s.context_provider = func() -> Dictionary: return {"window_size": Vector2i(1920, 1080), "vsync": 1}
	s.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen", "threads": 8,
		"memory_bytes": 8589934592, "gpu": "NVIDIA GeForce RTX", "renderer": "forward_plus", "driver": "vulkan"}
	s._session_id = "a".repeat(32)
	s._session_day = "2026-11-22"
	s._session_start_usec = 0
	s._append({"name": "session_started"}, 0) # observation at t=0
	s._seal(60000000) # ordinary 60 s seal: queue's TTL clock starts only here
	var item: Dictionary = s.queue.begin(60.0, s.generation)
	if item.is_empty():
		printerr("INCONCLUSIVE: no sealed item")
		s.free()
		quit(1)
		return
	var first_result: String = s.queue.complete(int(item.serial), 429, 60.0, 599.0)
	# A Retry-After: 599 is valid and fits the queue's t=660 deadline.
	var retried: Dictionary = s.queue.begin(659.0, s.generation)
	var body: Dictionary = JSON.parse_string(retried.body.get_string_from_utf8()) if not retried.is_empty() else {}
	var event_at_retry: bool = not body.is_empty() and body.events.size() == 1 and body.events[0].name == "session_started"
	print("PENDING_AGE_PROBE ", JSON.stringify({"seal_at_seconds": 60, "advertised_limit_seconds": 600,
		"first_result": first_result, "retry_at_seconds": 659, "original_event_still_sent": event_at_retry}))
	var reproduced := first_result == "retry" and event_at_retry
	s.free()
	if reproduced:
		print("REPRODUCED: an observation from t=0 is eligible to send at t=659")
		quit(0)
	else:
		printerr("INCONCLUSIVE: expected source-state signature was not observed")
		quit(1)
