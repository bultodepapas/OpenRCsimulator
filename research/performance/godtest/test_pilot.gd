extends SceneTree
## Continue must preserve the benchmark reader through the ordinary HeldKeys contract.
const Pilot := preload("pilot.gd")
const HeldKeys := preload("res://ui/held_keys.gd")
var failures := 0

class KeyboardSession extends Node:
	var read_raw: Callable


func _initialize() -> void:
	var pilot := Pilot.new()
	var session := KeyboardSession.new()
	var physical_reads := pilot.last_tick
	pilot.release_for_menu()
	HeldKeys.mask(session, pilot.read_raw)
	_check(session.read_raw == pilot.read_raw, "Continue installs the declared benchmark reader, without a permanently masked feedback axis")
	_check(not pilot.menu_release_pending, "the menu boundary consumes its one released virtual sample")
	_check(pilot.last_tick == physical_reads, "menu polling consumes no physical tick")
	_check(not pilot.begin_phase("invalid").ok, "unsupported phase rejected")
	_check(not pilot.begin_phase("landing").ok, "unconfigured session cannot begin a maneuver")
	session.free()
	print("GOD_PILOT_TESTS: ", failures, " failed")
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
