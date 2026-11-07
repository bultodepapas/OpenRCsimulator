extends SceneTree
const Hint := preload("res://ui/first_flight_hint.gd")

class Clock extends RefCounted:
	var paused := false
	var seconds := 0.0
	func time() -> float:
		return seconds

class Radio extends RefCounted:
	var connected := true

class Session extends Node:
	var sim := Clock.new()
	var radio := Radio.new()
	var _controller_lost := false

var checks := 0
var failures := 0

func _check(label: String, accepted: bool) -> void:
	checks += 1
	if not accepted:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var session := Session.new()
	root.add_child(session)
	var hint := Hint.new(session)
	root.add_child(hint)
	hint.set_process(false)
	hint.duration_s = 3.0
	var completions := [0]
	hint.done.connect(func() -> void: completions[0] += 1)
	for step: int in 10:
		session.sim.seconds += 1.0
		hint._process(1.0)
	_check("controller-owned hidden exposure never finishes the keyboard hint", hint._flown == 0.0 and completions[0] == 0)
	session.radio.connected = false
	hint._process(0.0)
	session.sim.seconds += 1.0
	hint._process(1.0)
	_check("visible advancing keyboard exposure counts", hint.visible and hint._flown == 1.0)
	session._controller_lost = true
	session.sim.seconds += 5.0
	hint._process(5.0)
	_check("controller loss retains remaining exposure", hint._flown == 1.0 and not hint.visible)
	session._controller_lost = false
	session.sim.paused = true
	hint._process(0.0)
	session.sim.seconds += 5.0
	hint._process(5.0)
	_check("paused exposure does not count", hint._flown == 1.0)
	session.sim.paused = false
	hint._process(0.0)
	hint._process(10.0)
	_check("wall time without accepted simulation advance does not count", hint._flown == 1.0)
	session.sim.seconds = 0.0
	hint._process(0.0)
	_check("restart does not subtract credited exposure", hint._flown == 1.0)
	session.sim.seconds += 2.0
	hint._process(2.0)
	hint.finish()
	_check("sufficient visible flight or dismissal emits completion once", completions[0] == 1 and not hint.visible)
	hint.free()
	session.free()
	print("Hint exposure: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
