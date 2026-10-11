# G3b/AUD coexistence smoke: actual shared app, each route, pause/restart/teardown.
extends SceneTree
const VoiceAdapter := preload("res://render/engine_audio.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _settle() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	# main.gd reads the real process user arguments, independent of AppRoot's menu override.
	var selected := "on"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--soundscape="):
			selected = arg.trim_prefix("--soundscape=")
	for route in [selected]:
		var app: Node = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray() # interactive shell; main reads the real soundscape CLI flag
		app.preferences_path = "user://g3b-route-smoke-" + route + ".cfg"
		root.add_child(app)
		await _settle()
		app.start_flight()
		await _settle()
		var main: Node = app.flight
		_check(route + " live flight", main != null and main.session.is_flyable())
		if main == null:
			app.free()
			continue
		main.session.input_enabled = false
		await create_timer(0.6).timeout
		_check(route + " advances physics", main.session.sim.tick > 0 and main.session.sim.fault_reason.is_empty())
		if route == "legacy":
			_check("legacy selects G3b generator only", main._engine_audio is VoiceAdapter and main._soundscape_audio == null)
			if main._engine_audio is VoiceAdapter:
				_check("legacy observes accepted state", main._engine_audio.snapshot_tick == main.session.sim.tick)
		elif route == "on":
			_check("default retains AUD ownership", main._soundscape_audio != null and not main._engine_audio is VoiceAdapter)
		else:
			_check("off retains silence route", main._engine_audio == null and main._soundscape_audio == null)
		app.open_pause()
		await create_timer(0.2).timeout
		var tick: int = main.session.sim.tick
		await create_timer(0.2).timeout
		_check(route + " pause freezes physics", main.session.sim.tick == tick)
		app.continue_flight()
		await create_timer(0.2).timeout
		_check(route + " resumes physics", main.session.sim.tick > tick)
		main.session.reset()
		await _settle()
		_check(route + " restart remains flyable", main.session.is_flyable() and main.session.sim.fault_reason.is_empty())
		app.open_pause()
		await _settle()
		app.end_flight()
		await _settle()
		_check(route + " ends to Home", app.flight == null and app.home != null)
		app.free()
		await create_timer(0.25).timeout
	print("G3b/AUD routes: %d failed" % failures)
	quit(1 if failures > 0 else 0)
