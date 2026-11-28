## CAM-FPV-02b: enter and fly the admitted nose view through the stock aircraft routes.
extends SceneTree

const Flight := preload("res://main.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

var _failures := 0
var _flights := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, id: String, description: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", id, ": ", description)


func _run() -> void:
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		_fly(str(entry.id), Catalog.is_player_selectable(str(entry.id)))
		await process_frame
	_fly("skywalker-x8", false)
	await process_frame
	print("Stock FPV airplane routes: %d flights, %d failed" % [_flights, _failures])
	quit(1 if _failures else 0)


func _fly(id: String, home: bool) -> void:
	_flights += 1
	var flight := Flight.new()
	var args := PackedStringArray(["--physics-backend=gdscript_reference", "--soundscape=off", "--smoke=off", "--crash-effects=off"])
	if home:
		flight.interactive_start = true
		flight.aircraft_id = id
		flight.start_choice = "airborne"
		flight.camera_preferences = {"camera_view": "fpv"}
	else:
		args.append_array(PackedStringArray(["--aircraft=" + id, "--start=airborne", "--view=fpv"]))
	flight.set_user_args(args)
	root.add_child(flight)
	var ready := flight.startup_complete and flight.startup_error.is_empty() and is_instance_valid(flight.session)
	_check(ready, id, "stock aircraft starts: " + flight.startup_error)
	if not ready:
		flight.free()
		return
	var sim: Node = flight.session.sim
	var body: Node3D = flight._airplane.root
	var camera: Camera3D = flight._camera
	var local_lens := body.global_transform.affine_inverse() * camera.global_transform
	_check(flight.aircraft_id == Catalog.canonical_id(id) and flight._airplane.aircraft_id == flight.aircraft_id,
		id, "flight and visible model agree on identity")
	_check(sim.tick == 0 and flight._rig.view == "fpv" and flight._rig.can_drag_fpv()
		and local_lens.origin.z < 0.0 and local_lens.basis.is_equal_approx(Basis.IDENTITY), id, "first frame looks forward at the nose")
	flight.session.input_enabled = false
	sim.set_paused(false)
	sim.step()
	flight._render_pose(flight._pose_of(sim.state), flight.session.surfaces(), 0.0)
	_check(sim.tick == 1 and camera.global_transform.is_equal_approx(body.global_transform * local_lens),
		id, "accepted airborne tick carries the same structural lens")
	var checkpoint: Dictionary = sim.checkpoint()
	for key: Key in [KEY_1, KEY_3]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = true
		flight._unhandled_input(event)
		_check(flight._rig.view == ("pilot" if key == KEY_1 else "fpv"), id, "camera shortcut " + str(key))
	_check(not checkpoint.is_empty() and sim.checkpoint() == checkpoint, id, "switching camera preserves the physical checkpoint")
	flight.free()
