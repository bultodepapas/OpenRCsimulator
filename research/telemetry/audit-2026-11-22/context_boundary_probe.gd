# Source-read-only probe for telemetry context-boundary handling.
# Use run_godot_probes.py to copy exact dependencies into an isolated project.
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

var now_usec := 0
var draws := 0
var ctx := {"mode": "home", "activity": false, "vehicle": "", "eligible": true,
	"window_size": Vector2i(1920, 1080), "vsync": 1, "max_fps": 0,
	"graphics_profile": "current_default", "input_class": "keyboard"}

func _initialize() -> void:
	var s := Service.new()
	# No tree admission, consent store, sender or network is needed to exercise
	# the exact observation, event-building and batch-context code.
	s.state = "on"
	s.release = {"notice": Contract.NOTICE_VERSION, "release_id": "v0.3.2", "channel": "stable"}
	s.clock_usec = func() -> int: return now_usec
	s.frames_drawn = func() -> int: return draws
	s.utc_day = func() -> String: return "2026-11-22"
	s.context_provider = func() -> Dictionary: return ctx
	s.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen",
		"threads": 8, "memory_bytes": 8589934592, "gpu": "NVIDIA GeForce RTX",
		"renderer": "forward_plus", "driver": "vulkan"}
	s._session_id = "a".repeat(32)
	s._session_day = "2026-11-22"
	s._session_start_usec = 0
	s._observe(0) # prime
	for i in 25: # 10 s warmup then 15 s steady at 1080p
		_step(s)
	var before_count: int = s._window.interval_count
	var before_us: int = s._window.interval_sum_us
	ctx.window_size = Vector2i(3840, 2160)
	_step(s) # a context boundary should close the old window as partial
	var after_count: int = s._window.interval_count if s._window != null else -1
	var after_us: int = s._window.interval_sum_us if s._window != null else -1
	for i in 14:
		_step(s)
	var steady := []
	for e: Dictionary in s._pending:
		if e.name == "performance_window" and e.phase == "steady":
			steady.append(e)
	var context: Dictionary = s._pending_context
	var result := {"old_context_interval_count": before_count, "old_context_us": before_us,
		"window_interval_count_after_first_new_context_sample": after_count,
		"window_us_after_first_new_context_sample": after_us,
		"steady_events": steady, "event_batch_resolution_class": context.get("resolution_class", "missing")}
	print("CONTEXT_BOUNDARY_PROBE ", JSON.stringify(result))
	var reproduced: bool = before_count == 15 and before_us == 15000000 and after_count == 16 \
		and after_us == 16000000 and steady.size() == 1 and steady[0].window_complete == true \
		and steady[0].interval_sum_us == 30000000 and context.get("resolution_class") == "2160p"
	s.free()
	if reproduced:
		print("REPRODUCED: a complete 30 s window mixed 15 s at 1080p with 15 s at 2160p and was labeled 2160p")
		quit(0)
	else:
		printerr("INCONCLUSIVE: expected source-state signature was not observed")
		quit(1)

func _step(s: Node) -> void:
	now_usec += 1000000
	draws += 1
	s._observe(now_usec)
