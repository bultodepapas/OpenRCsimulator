# CAM-04: camera input through the real flight scene (main.gd _unhandled_input): C/Shift+C, 1/2/5, Z, =/−,
# Backspace, the mouse wheel and a right-button drag reach the rig; --view selects the first view; an unknown view
# is refused; a restart settles the chase again; views never touch the simulation.
# Run: godot --headless --path . --script res://tests/test_camera_route.gd
extends SceneTree

class TestFlight extends "res://main.gd":
	var options: Dictionary = {}
	func _user_args() -> Dictionary:
		return options

var _checks := 0
var _failures := 0


func check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _key(flight: Node, key: Key, shift := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	event.shift_pressed = shift
	flight._unhandled_input(event)


func _frames(flight: Node, count: int) -> void:
	for i in count:
		flight._process(1.0 / 60.0)


func _run() -> void:
	var flight: TestFlight = TestFlight.new()
	flight.options = {"soundscape": "off", "crash-effects": "off", "smoke": "off"}
	root.add_child(flight)
	var rig: RefCounted = flight._rig
	check("a direct flight starts in the pilot view", rig.view == "pilot" and flight._view_name() == "pilot")
	var state_before: PackedFloat64Array = flight.session.sim.state.duplicate()
	var tick_before: int = flight.session.sim.tick
	_key(flight, KEY_C)
	_frames(flight, 3)
	check("C: chase", rig.view == "chase" and flight._view_name() == "chase")
	var behind: Vector3 = flight._camera.global_position - flight._airplane.root.global_position
	check("chase camera is a few metres from the airplane", behind.length() > 2.0 and behind.length() < 15.0, str(behind))
	_key(flight, KEY_C, true)
	check("Shift+C: back to pilot", rig.view == "pilot")
	_key(flight, KEY_5)
	_frames(flight, 1)
	check("5: orbit", rig.view == "orbit")
	var azimuth: float = rig.orbit.azimuth_deg
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(40, 0)
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	flight._unhandled_input(drag)
	check("right-button drag turns the orbit", absf(rig.orbit.azimuth_deg - azimuth) > 5.0)
	var hover := InputEventMouseMotion.new()
	hover.relative = Vector2(40, 0)
	var turned: float = rig.orbit.azimuth_deg
	flight._unhandled_input(hover)
	check("a plain mouse move does not turn it", rig.orbit.azimuth_deg == turned)
	var distance: float = rig.orbit.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	flight._unhandled_input(wheel)
	check("wheel up moves the orbit in", rig.orbit.distance < distance)
	_key(flight, KEY_BACKSPACE)
	check("Backspace resets the orbit", is_equal_approx(rig.orbit.distance, rig.orbit.DEFAULT_SPANS * rig._span))
	_key(flight, KEY_2)
	check("2: chase", rig.view == "chase")
	_key(flight, KEY_EQUAL)
	check("= brings the chase closer", rig.chase.zoom < 1.0)
	_key(flight, KEY_MINUS)
	check("− moves it back", is_equal_approx(rig.chase.zoom, 1.0))
	_key(flight, KEY_1)
	_key(flight, KEY_Z)
	check("1 then Z: pilot view, auto-zoom off", rig.view == "pilot" and not rig.auto_zoom and "auto-zoom off" in flight._status())
	_key(flight, KEY_Z)
	check("Z again: on", rig.auto_zoom)
	flight._inspect = true
	check("the historical close-up switch still works", rig.view == "closeup" and flight._view_name() == "close-up")
	flight._inspect = false
	check("simulation untouched by camera input", flight.session.sim.tick == tick_before and flight.session.sim.state == state_before)
	# Restart while chasing: the chase settles behind the restarted airplane at once.
	_key(flight, KEY_2)
	_frames(flight, 2)
	flight.session.reset()
	_frames(flight, 1)
	var after: float = (flight._camera.global_position - flight._airplane.root.global_position).length()
	check("restart: chase settled next to the airplane", after < 15.0, "%.2f m" % after)
	flight.free()
	await process_frame
	# --view selects the first view; an unknown view is refused before the flight builds.
	var chase_first: TestFlight = TestFlight.new()
	chase_first.options = {"view": "chase", "soundscape": "off", "crash-effects": "off", "smoke": "off"}
	root.add_child(chase_first)
	check("--view=chase starts in chase", chase_first._rig != null and chase_first._rig.view == "chase")
	chase_first.free()
	await process_frame
	var inspect: TestFlight = TestFlight.new()
	inspect.options = {"inspect": true, "soundscape": "off", "crash-effects": "off", "smoke": "off"}
	root.add_child(inspect)
	check("--inspect still starts in the close-up", inspect._rig.view == "closeup")
	inspect.free()
	await process_frame
	print("camera route: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
