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

	print("all e2e checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)
