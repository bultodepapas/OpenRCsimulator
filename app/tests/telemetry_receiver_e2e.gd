# TELEM-08 qualification: the real Godot client (service, contract, queue, HTTPRequest sender) against the real
# receiver (services/telemetry). Driven by services/telemetry/tests/test_godot_e2e.py, which starts the receiver
# and passes its loopback URL; not part of the unit roster. Simulated frame time advances quickly; the HTTP
# exchange is real. Prints "E2E sent=<n> status=<state>" and exits 0 when every sealed batch was accepted.
# Run: godot --headless --path . --script res://tests/telemetry_receiver_e2e.gd -- --url=http://127.0.0.1:8787/v1/batches
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Release := preload("res://telemetry/telemetry_release.gd")

const CONSENT := "user://telemetry_e2e_consent.cfg"
const FRAME_US := 16667

var _now := 0
var _frames := 0
var _ctx := {"mode": "home", "vehicle": "", "eligible": true, "window_size": Vector2i(1920, 1080), "vsync": 1,
	"max_fps": 0, "graphics_profile": "unknown", "input_class": "keyboard"}


func _initialize() -> void:
	await process_frame
	var url := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--url="):
			url = argument.trim_prefix("--url=")
	var release := Release.qualification(url, "v0.0.0")
	if not release.ok:
		printerr("E2E bad receiver url: ", url)
		quit(2)
		return
	if FileAccess.file_exists(CONSENT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONSENT))
	var service: Node = Service.new()
	service.release = release
	service.interactive = true
	service.consent_path = CONSENT
	service.clock_usec = func() -> int: return _now
	service.frames_drawn = func() -> int: return _frames
	service.context_provider = func() -> Dictionary: return _ctx
	root.add_child(service)
	service.enable()
	# Three simulated minutes: home, a fixed-wing flight (no classifier: unsupported) and home again.
	for second: int in 180:
		if second == 40:
			_ctx.merge({"mode": "flight", "vehicle": "f4u-corsair-250", "simulated_seconds": 0.0}, true)
		if second == 120:
			_ctx.merge({"mode": "home", "vehicle": ""}, true)
			_ctx.erase("simulated_seconds")
		for frame: int in 60:
			_now += FRAME_US
			_frames += 1
			if _ctx.has("simulated_seconds"):
				_ctx.simulated_seconds = float(_ctx.simulated_seconds) + FRAME_US / 1000000.0
			service._process(0.0)
		# Let the real request run between simulated seconds (the sender uses real frames and its own clock).
		var waited := Time.get_ticks_msec()
		while service.sender.busy() and Time.get_ticks_msec() - waited < 6000:
			await process_frame
	var started := Time.get_ticks_msec()
	while (service.queue.items.size() > 0 or service.sender.busy()) and Time.get_ticks_msec() - started < 20000:
		_now += 61000000 # let the normal cadence admit the next queued batch
		service._process(0.0)
		await process_frame
	print("E2E sent=%d queued=%d dropped=%d local_drops=%d status=%s" % [service.queue.sent_ok, service.queue.items.size(),
		service.queue.dropped, service.local_drops, service.state])
	var ok: bool = service.queue.sent_ok >= 3 and service.queue.items.is_empty() and service.queue.dropped == 0 \
		and service.local_drops == 0 and service.state == "on"
	service.disable()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONSENT))
	quit(0 if ok else 1)
