extends SceneTree

const Runway := preload("res://runway_coordinator.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	for direction: int in [-1, 1]:
		var coordinator := Runway.new(direction)
		coordinator.update_wind(0, -2.0 * direction, 0.0, 0.0)
		_check("default request queues", coordinator.submit_request(0, "zero-tailwind", 1, 0, "p1", "takeoff").ok)
		_check("hysteresis cannot grant with disallowed tailwind", not coordinator.resolve(0).granted)
		_check("direction stays locked until dwell", coordinator.snapshot_state().direction == direction)
		coordinator.update_wind(2400, -2.0 * direction, 0.0, 0.0)
		var grant: Dictionary = coordinator.resolve(2400)
		_check("same queued request grants into wind after reversal", grant.granted and grant.grant.direction == -direction)
		coordinator.update_wind(2401, 0.1 * direction, 0.0, 0.0)
		_check("new tailwind revokes before another direction dwell", coordinator.snapshot_state().mode == "free"
			and not coordinator.enter_runway(2401, grant.grant.ticket, 1, 0).ok)
		var restored := Runway.new()
		_check("tailwind limit and queue roundtrip", restored.restore_state(coordinator.snapshot_state()).ok
			and restored.snapshot_state() == coordinator.snapshot_state())
	var limited := Runway.new()
	limited.update_wind(0, -0.5, 0.0, 0.0)
	_check("explicit finite envelope queues", limited.submit_request(0, "limited", 2, 0, "p2", "landing", 0,
		false, false, false, "", -1, -1, 0.0, 0.0, [], 0.5).ok)
	_check("exact tailwind boundary grants", limited.resolve(0).granted)
	var before: Dictionary = limited.snapshot_state()
	var bad := before.duplicate(true)
	bad.grant.max_tailwind_mps = -1.0
	_check("negative restored limit refuses atomically", not limited.restore_state(bad).ok and limited.snapshot_state() == before)
	bad = before.duplicate(true)
	bad.grant.erase("max_tailwind_mps")
	_check("old grant without tailwind bound refuses", not limited.restore_state(bad).ok and limited.snapshot_state() == before)
	for limit: float in [-1.0, NAN, INF]:
		_check("invalid tailwind limit refuses without mutation", not limited.submit_request(1, "invalid", 3, 0, "p3", "takeoff", 0,
			false, false, false, "", -1, -1, 0.0, 0.0, [], limit).ok and limited.snapshot_state() == before)
	print("runway tailwind: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)
