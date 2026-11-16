extends SceneTree

const Probe := preload("res://tools/package_default_probe.gd")

class ControlledProbe extends Probe:
	func _ready() -> void: pass

class FakeSimulation extends Node:
	var tick := 0

class FakeSession extends Node:
	var sim: FakeSimulation
	func is_flyable() -> bool: return true

class FakeFlight extends Node:
	var startup_complete := false
	var session: FakeSession

class FakeApp extends Node:
	var flight: FakeFlight

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("PACKAGE_DEFAULT_PROBE_TEST failed: " + label)


func _finish_later(probe: ControlledProbe) -> void:
	probe.finished = true


func _complete_startup_later(flight: FakeFlight) -> void:
	await process_frame
	flight.startup_complete = true


func _advance_tick_later(sim: FakeSimulation) -> void:
	await process_frame
	sim.tick = 1


func _run() -> void:
	var probe := ControlledProbe.new()
	root.add_child(probe)
	_finish_later.call_deferred(probe)
	var saw_completion: bool = await probe._wait_for(func() -> bool: return probe.finished)
	_check(saw_completion, "a terminal result delivered between frames is observed")
	var unrelated: bool = await probe._wait_for(func() -> bool: return false)
	_check(not unrelated, "a terminal result cannot satisfy a different condition")
	probe.finished = false
	var app := FakeApp.new()
	var flight := FakeFlight.new()
	var session := FakeSession.new()
	var sim := FakeSimulation.new()
	root.add_child(app)
	app.add_child(flight)
	flight.add_child(session)
	session.add_child(sim)
	app.flight = flight
	flight.session = session
	session.sim = sim
	sim.tick = 1
	_complete_startup_later.call_deferred(flight)
	var startup_ready: bool = await probe._flight_ready(app)
	_check(startup_ready and flight.startup_complete, "flight readiness waits for startup completion")
	sim.tick = 0
	_advance_tick_later.call_deferred(sim)
	var tick_ready: bool = await probe._flight_ready(app)
	_check(tick_ready and sim.tick > 0, "flight readiness waits for a post-restart simulation tick")
	await process_frame
	await process_frame
	app.free()
	probe.free()
	print("PACKAGE_DEFAULT_PROBE_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
