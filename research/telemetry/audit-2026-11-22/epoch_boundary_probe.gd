# Source-read-only probe of a UTC day boundary during a running activity.
# Use run_godot_probes.py to copy exact dependencies into an isolated project.
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

var now_usec := 0
var draws := 0
var day := "2026-11-22"
var ctx := {"mode": "home", "activity": false, "vehicle": "", "eligible": true,
	"window_size": Vector2i(1920, 1080), "vsync": 1, "max_fps": 0,
	"graphics_profile": "current_default", "input_class": "keyboard"}

func _initialize() -> void:
	var s := Service.new()
	s.state = "on"
	s.release = {"notice": Contract.NOTICE_VERSION, "release_id": "v0.3.2", "channel": "stable"}
	s.clock_usec = func() -> int: return now_usec
	s.frames_drawn = func() -> int: return draws
	s.utc_day = func() -> String: return day
	s.context_provider = func() -> Dictionary: return ctx
	s.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen",
		"threads": 8, "memory_bytes": 8589934592, "gpu": "NVIDIA GeForce RTX",
		"renderer": "forward_plus", "driver": "vulkan"}
	s._session_id = "a".repeat(32)
	s._session_day = day
	s._session_start_usec = 0
	s._observe(0)
	_step(s) # observe home before the activity
	ctx.merge({"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250",
		"fixed_wing_accepted": true, "simulated_seconds": 0.0}, true)
	for i in 8:
		_step(s)
	s.note_flight_events([{"type": "TAKEOFF"}]) # counted before midnight
	for i in 10:
		_step(s)
	var old_session: String = s._session_id
	day = "2026-11-23" # UTC boundary; do not change any other input
	_step(s)
	var still_old_at_boundary: bool = s._session_id == old_session
	for i in 30:
		_step(s) # next performance event rotates the token
	var rotated_on_later_event: bool = s._session_id != old_session
	ctx.merge({"mode": "home", "activity": false, "vehicle": "", "fixed_wing_accepted": false}, true)
	ctx.erase("simulated_seconds")
	_step(s) # closes activity after rotation
	var summaries := []
	for e: Dictionary in s._pending:
		if e.name == "activity_summary":
			summaries.append(e)
	var summary_in_new_session: bool = s._pending_session == s._session_id and s._pending_session != old_session
	print("EPOCH_BOUNDARY_PROBE ", JSON.stringify({"old_token_remains_on_first_post_boundary_frame": still_old_at_boundary,
		"rotated_at_later_event": rotated_on_later_event,
		"summary_in_new_session": summary_in_new_session, "summaries": summaries}))
	var reproduced: bool = still_old_at_boundary and rotated_on_later_event and summary_in_new_session \
		and summaries.size() == 1 and summaries[0].takeoffs == 1 and summaries[0].complete_observation == true
	s.free()
	if reproduced:
		print("REPRODUCED: pre-boundary takeoff and activity time migrated into a post-boundary session")
		quit(0)
	else:
		printerr("INCONCLUSIVE: expected source-state signature was not observed")
		quit(1)

func _step(s: Node) -> void:
	now_usec += 1000000
	draws += 1
	if ctx.has("simulated_seconds"):
		ctx.simulated_seconds = float(ctx.simulated_seconds) + 1.0
	s._observe(now_usec)
