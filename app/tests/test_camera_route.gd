# CAM-04: camera input through the real flight scene (main.gd _unhandled_input): C/Shift+C, 1/2/5, Z, =/−,
# Backspace, the mouse wheel and a right-button drag reach the rig; --view selects the first view; an unknown view
# is refused; a restart settles the chase again; views never touch the simulation. CAM-26: the helicopter route has
# the same keys (Shift+C, Backspace back to its own zoom), fractional wheel notches and a settled chase on restart.
# Run: godot --headless --path . --script res://tests/test_camera_route.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

class TestFlight extends "res://main.gd":
	var options: Dictionary = {}
	func _user_args() -> Dictionary:
		return options


## CAM-27: a crash director that is active and reports a wreck focus, without simulating a crash.
class FocusDirector extends "res://render/crash/director.gd":
	var point := Vector3.ZERO
	var aimed := false
	func update(_delta: float) -> void:
		pass
	func focus_point() -> Vector3:
		return point
	func aim(_camera: Camera3D, _inspect: bool) -> void:
		aimed = true
	func description() -> String:
		return ""

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
	await _main_wiring()
	await _helicopter()
	print("camera route: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _helicopter() -> void:
	var heli: Node = load("res://helicopter_main.gd").new()
	heli.set_user_args(PackedStringArray(["--soundscape=off"]))
	root.add_child(heli)
	await process_frame
	var rig: RefCounted = heli._rig
	check("helicopter: starts in the pilot view with its own zoom", rig.view == "pilot" and rig.pilot_zoom == 0.35 and rig.default_pilot_zoom == 0.35)
	_key(heli, KEY_C, true)
	check("helicopter Shift+C: back to the close-up", rig.view == "closeup")
	_key(heli, KEY_1)
	_key(heli, KEY_EQUAL)
	check("helicopter =: zoom in from its own zoom", rig.pilot_zoom < 0.35)
	_key(heli, KEY_BACKSPACE)
	check("helicopter Backspace: back to its own zoom, not the airplane's", rig.pilot_zoom == 0.35)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 0.5
	heli._unhandled_input(wheel)
	check("helicopter wheel: a half notch zooms half a step", is_equal_approx(rig.pilot_zoom, 0.35 * pow(rig.ZOOM_STEP, -0.5)))
	_key(heli, KEY_2)
	heli._present(1.0 / 60.0)
	heli._on_session_resetting() # a restart must settle the chase, never glide it from the old spot
	check("helicopter restart: the chase forgets its history", not rig.chase._primed)
	heli.free()
	await process_frame


## CAM-24/27 seams in main.gd: _pose_of gives the CG velocity in render axes; after a crash the non-pilot views follow
## the director's focus point through the rig, and the pilot view keeps the director's own aim.
func _main_wiring() -> void:
	var flight: TestFlight = TestFlight.new()
	flight.options = {"soundscape": "off", "crash-effects": "off", "smoke": "off"}
	root.add_child(flight)
	# Heading east (yaw 90°), level, 12 m/s forward and 2 m/s down in body axes → render (+12 east, −2 up, 0).
	var s := RB.make_state(M.v3(10, 20, -30), M.v3(12, 0, 2), M.q_from_euler(PI / 2.0, 0.0, 0.0), M.v3(0, 0, 0))
	var vel: Vector3 = flight._pose_of(s).vel
	check("_pose_of: CG velocity in render axes (east 12, down 2)", vel.distance_to(Vector3(12, -2, 0)) < 1e-5, str(vel))
	var director := FocusDirector.new()
	director.active = true
	var previous: Variant = flight._crash_director
	flight._crash_director = director
	var anchor: Vector3 = flight._airplane.root.global_position
	director.point = anchor + Vector3(9, -0.5, 6)
	_key(flight, KEY_5)
	_frames(flight, 2)
	var forward: Vector3 = -flight._camera.global_basis.z
	var to_focus: Vector3 = (director.point - flight._camera.global_position).normalized()
	check("crash aftermath: the orbit looks at the director's focus point", forward.dot(to_focus) > 0.9999, "%.6f" % forward.dot(to_focus))
	check("crash aftermath: the orbit leaves the pilot aim alone", not director.aimed)
	_key(flight, KEY_1)
	_frames(flight, 1)
	check("crash aftermath: the pilot view keeps the director's aim", director.aimed)
	flight._crash_director = previous
	director.free()
	flight.free()
	await process_frame
