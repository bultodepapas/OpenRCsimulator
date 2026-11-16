extends SceneTree

const Probe := preload("res://tools/package_default_probe.gd")

class ControlledProbe extends Probe:
	func _ready() -> void: pass

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


func _run() -> void:
	var probe := ControlledProbe.new()
	root.add_child(probe)
	_finish_later.call_deferred(probe)
	var saw_completion: bool = await probe._wait_for(func() -> bool: return probe.finished)
	_check(saw_completion, "a terminal result delivered between frames is observed")
	var unrelated: bool = await probe._wait_for(func() -> bool: return false)
	_check(not unrelated, "a terminal result cannot satisfy a different condition")
	probe.free()
	print("PACKAGE_DEFAULT_PROBE_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
