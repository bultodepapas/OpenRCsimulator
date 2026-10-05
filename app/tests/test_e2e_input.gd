# End-to-end input check: key event -> Input -> raw -> limiter -> panel, on the real main scene.
# Run: godot --headless --path . --script res://tests/test_e2e_input.gd
extends SceneTree

var _failures := 0
var _main: Node


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _row(prefix: String) -> String:
	for line in (_main._panel as Label).text.split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


func _alt() -> float:
	var r := _row("sim")
	return float(r.get_slice("alt", 1).strip_edges().get_slice(" ", 0))


func _pct() -> int:
	return int(_row("throttle").get_slice("%", 0).split(" ", false)[-1])


func _initialize() -> void:
	_run()


func _run() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	await process_frame

	_key(KEY_RIGHT, true)
	await create_timer(0.5).timeout # limiter needs 0.25 s
	var r := _row("roll")
	_check("hold -> roll +1, aileron +20°", "+1.00" in r and "+20.0°" in r, r)
	_key(KEY_RIGHT, false)
	await create_timer(0.5).timeout
	r = _row("roll")
	# The stick re-centers; the aileron returns to its TRIM position (like a trimmed real airplane), not to 0°.
	var trim_deg: float = _main.session.trims.roll * _main.session.throws_deg().aileron
	_check("release -> stick re-centers, aileron back to trim", "+0.00" in r and ("%+.1f°" % trim_deg) in r, "%s (trim %+.1f°)" % [r, trim_deg])

	_key(KEY_W, true)
	await create_timer(0.6).timeout
	_key(KEY_W, false)
	await create_timer(0.1).timeout
	var before := _pct()
	await create_timer(0.3).timeout
	_check("throttle rose and holds after release", before > 50 and _pct() == before, "%d%%" % before)

	_key(KEY_R, true)
	_key(KEY_R, false)
	await create_timer(0.1).timeout
	var trim_pct := roundi(float(_main.session.start.throttle) * 100.0)
	_check("reset -> throttle back to its trimmed setting", _pct() == trim_pct, "%s (trim %d%%)" % [_row("throttle"), trim_pct])

	# D5: the live airplane starts trimmed in level flight with the engine running: hands-off it holds altitude;
	# pulling the throttle back makes it descend.
	_key(KEY_R, true)
	_key(KEY_R, false)
	await process_frame
	await process_frame
	var a0 := _alt()
	await create_timer(1.0).timeout
	var a1 := _alt()
	_check("physics: trimmed level flight holds altitude hands-off", a0 > 29.5 and absf(a1 - a0) < 0.2, "%.2f → %.2f m" % [a0, a1])
	_key(KEY_S, true)
	await create_timer(2.0).timeout
	_key(KEY_S, false)
	var a2 := _alt()
	_check("physics: throttle back → descends", a2 < a1 - 0.5, "%.2f → %.2f m" % [a1, a2])
	_key(KEY_R, true)
	_key(KEY_R, false)
	await process_frame
	await process_frame
	_check("physics: R restarts at 30 m", _alt() > 29.5, "%.1f m" % _alt())
	# D9d: put the airplane on the ground: it crashes (impact shown), then restarts by itself after 1.5 s.
	var near: PackedFloat64Array = _main.session.sim.state
	near[2] = 0.1
	_main.session.sim.state = near
	_main.session.sim.previous = near
	await create_timer(0.2).timeout
	_check("physics: ground contact → CRASH shown", "CRASH" in (_main._panel as Label).text, _row("PAUSED"))
	await create_timer(1.6).timeout
	_check("physics: restarts by itself after the crash", _alt() > 29.5 and not ("CRASH" in (_main._panel as Label).text), "%.1f m" % _alt())

	# L0d: every frame, shaders get the session's simulation time wrapped to [0, 1024) s (checked at three ticks).
	var ShaderClock := load("res://render/shader_clock.gd")
	var clock_ok := true
	for i in 3:
		await process_frame # resumes before main._process of this frame, after its physics ticks
		var t: float = _main.session.sim.time()
		await process_frame # by now main._process of the previous frame has sent t to the shaders
		clock_ok = clock_ok and ShaderClock.last_clock == fposmod(t, 1024.0) and t > 0.0
		await create_timer(0.1).timeout
	_check("L0d: sim_clock = simulation time mod 1024 at three ticks", clock_ok)

	# C7: T records a trace in the live scene and saves it on the second press.
	_key(KEY_R, true)
	_key(KEY_R, false)
	await process_frame
	_key(KEY_T, true)
	_key(KEY_T, false)
	await create_timer(0.5).timeout
	_check("T: recording shows in the panel", "REC" in _row("REC"), _row("REC"))
	_key(KEY_T, true)
	_key(KEY_T, false)
	await process_frame
	var note: String = _main.recorder.note
	var path := note.get_slice("trace saved: ", 1).get_slice(" (", 0)
	var rows := int(note.get_slice("(", 1).get_slice(" rows", 0))
	_check("T again: trace saved with ~0.5 s of ticks", FileAccess.file_exists(path) and rows > 60, note)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	print("all e2e checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)
