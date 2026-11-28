extends SceneTree
## F3 (2026-11-26): render/pipeline_cache_gate.gd defers RenderingDevice pipeline-cache writes while a flight or the RC
## truck runs, and leaves the project value everywhere else (Home, pause, loading, tools without an AppRoot).
## Run: godot --headless --path app --script res://tests/test_pipeline_cache_gate.gd

const Gate := preload("res://render/pipeline_cache_gate.gd")


class FakeApp extends Node:
	var flight: Node
	var ground_vehicle: Node3D
	var _loading_active := false


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, str(detail)])


func _chunk() -> float:
	return float(ProjectSettings.get_setting(Gate.SETTING))


func _run() -> void:
	var original := _chunk()
	_check("no AppRoot: nothing is running", not Gate.flight_running(self))
	var app := FakeApp.new()
	app.name = "AppRoot"
	root.add_child(app)
	var gate: Node = Gate.new()
	root.add_child(gate)
	gate._process(0.0)
	_check("Home keeps the project value", _chunk() == original and not gate._deferring, _chunk())
	var flight := Node.new()
	app.add_child(flight)
	app.flight = flight
	gate._process(0.0)
	_check("a running flight defers the writes", _chunk() == Gate.FLIGHT_CHUNK_MB and gate._deferring, _chunk())
	paused = true
	gate._process(0.0)
	_check("the pause menu writes the deferred growth", _chunk() == original, _chunk())
	paused = false
	gate._process(0.0)
	app._loading_active = true
	gate._process(0.0)
	_check("a loading screen writes as configured", _chunk() == original, _chunk())
	app._loading_active = false
	gate._process(0.0)
	_check("the flight defers again after loading", _chunk() == Gate.FLIGHT_CHUNK_MB, _chunk())
	flight.free()
	gate._process(0.0)
	_check("a freed flight (back Home) restores the project value", _chunk() == original, _chunk())
	var truck := Node3D.new()
	app.add_child(truck)
	app.ground_vehicle = truck
	gate._process(0.0)
	_check("the RC truck defers the writes too", _chunk() == Gate.FLIGHT_CHUNK_MB, _chunk())
	gate.free()
	_check("leaving the tree restores the project value", _chunk() == original, _chunk())
	truck.free()
	app.free()
	ProjectSettings.set_setting(Gate.SETTING, original)
	print("pipeline cache gate: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
