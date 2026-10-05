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
	_check("release -> re-centers", "+0.00" in r and "+0.0°" in r, r)

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
	_check("reset -> throttle 50%", _pct() == 50, _row("throttle"))

	# C6: physics mode is live: the airplane descends, R restarts it, and it restarts by itself below ground.
	_key(KEY_R, true)
	_key(KEY_R, false)
	await process_frame
	await process_frame
	var a0 := _alt()
	await create_timer(1.0).timeout
	var a1 := _alt()
	# With aerodynamics (D3) and no thrust it descends, but lift makes it clearly slower than free fall (4.9 m in 1 s).
	_check("physics: descends without power, slower than free fall", a0 > 29.5 and a1 < a0 - 0.5 and a1 > a0 - 4.0, "%.1f → %.1f m" % [a0, a1])
	_key(KEY_R, true)
	_key(KEY_R, false)
	await process_frame
	await process_frame
	_check("physics: R restarts at 30 m", _alt() > 29.5, "%.1f m" % _alt())
	# A trimmed glide from 30 m takes ~17 s to land, so put it just above the ground and watch it restart.
	var near: PackedFloat64Array = _main._sim.state
	near[2] = -0.3
	_main._sim.state = near
	_main._sim.previous = near
	var lowest := 100.0
	var restarted := false
	for i in 20: # 2 s
		await create_timer(0.1).timeout
		var a := _alt()
		restarted = restarted or (lowest < 5.0 and a > 25.0)
		lowest = minf(lowest, a)
	_check("physics: restarts by itself below ground", restarted, "lowest %.1f m" % lowest)

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
	var note: String = _main._trace_note
	var path := note.get_slice("trace saved: ", 1).get_slice(" (", 0)
	var rows := int(note.get_slice("(", 1).get_slice(" rows", 0))
	_check("T again: trace saved with ~0.5 s of ticks", FileAccess.file_exists(path) and rows > 60, note)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	print("all e2e checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)
