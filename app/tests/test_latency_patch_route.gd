# F6a: the actual main scene owns the optional marker and forwards validated options.
extends SceneTree

class TestFlight extends "res://main.gd":
	var options: Dictionary = {}
	func _user_args() -> Dictionary:
		return options

var _checks: int = 0
var _failures: int = 0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ordinary: TestFlight = TestFlight.new()
	root.add_child(ordinary)
	check("normal flight has no marker", ordinary.get_node_or_null("LatencyPatch") == null)
	ordinary.free()
	var measured: TestFlight = TestFlight.new()
	measured.options = {"latency-patch": true, "latency-axis": "3", "latency-threshold": "0.5"}
	root.add_child(measured)
	var patch: Node = measured.get_node_or_null("LatencyPatch")
	check("live main route attaches marker", patch != null)
	if patch != null:
		check("main forwards chosen axis and threshold", patch.axis == 3 and patch.threshold == 0.5)
		check("marker observes the actual flown session", patch.session == measured.session)
		measured.session.reset()
		check("restart retains marker and session", measured.get_node_or_null("LatencyPatch") == patch and patch.session == measured.session)
	measured.free()
	await process_frame
	print("F6a route: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
