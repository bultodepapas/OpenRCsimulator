## CAM-FPV-02c: both installed rigs, optically clear at steer/travel limits and on the drawn chassis.
extends SceneTree

const GroundCamera := preload("res://vehicles/ground/ground_camera.gd")
const Mt8 := preload("res://vehicles/ground/mt8_model.gd")
const Nitro := preload("res://vehicles/ground/monster_car_2_model.gd")
const Reconstruction := preload("res://render/reconstruction.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAIL ", label)
		failures += 1


func _run() -> void:
	# Independent positions from the two delivered bumper mesh envelopes in chassis axes.
	_vehicle("mt8-bisonte", Mt8, Vector3(0.0, 0.121, -0.3635))
	_vehicle("monster-car-2", Nitro, Vector3(0.0, 0.099970, -0.356645))
	var unbound := GroundCamera.new()
	_check(not unbound.bind_front("missing", {}), "unknown vehicle refuses a mount")
	_check(not unbound.bind_front("mt8-bisonte", {ok = true}), "unresolved bumper refuses a mount")
	for expected: int in [1, 2, 0]:
		unbound.cycle(false)
		_check(unbound.mode == expected, "missing mount preserves the practice camera cycle")
	for expected: int in [1, 2, 3, 0]:
		unbound.cycle(true)
		_check(unbound.mode == expected, "missing mount preserves the circuit camera cycle")
	print("Ground FPV: %d failed" % failures)
	quit(1 if failures else 0)


func _notifications() -> int:
	return int(root.get_meta(Reconstruction.HISTORY_RESET_META, {}).get("notifications", 0))


func _vehicle(id: String, model: Script, expected_mount: Vector3) -> void:
	var visual: Dictionary = model.build()
	_check(visual.get("ok", false), "built " + id)
	if not visual.get("ok", false):
		return
	var chassis: Node3D = visual.root
	root.add_child(chassis)
	var rig := GroundCamera.new()
	_check(rig.bind_front(id, visual), id + " admits stock front bracket")
	for expected: int in [1, 2, 3, GroundCamera.FPV, 0]:
		rig.cycle(true)
		_check(rig.mode == expected, id + " preserves overview and appends FPV")
	for expected: int in [1, 2, GroundCamera.FPV]:
		rig.cycle(false)
		_check(rig.mode == expected, id + " practice skips overview")
	var camera := Camera3D.new()
	root.add_child(camera)
	var terrain := func(_x: float, _z: float) -> float: return 0.0
	var state := PackedFloat64Array()
	state.resize(31)
	state[6] = 1.0
	for sign_value: float in [-1.0, 1.0]:
		state[29] = sign_value * 0.52
		for i in 4:
			state[13 + i] = sign_value * 0.07
			state[25 + i] = sign_value * 1.6
		_check(model.draw(visual, state, 0.065), id + " steers, spins and articulates")
		rig.update(camera, Vector3.ZERO, Basis.IDENTITY, 0.0, false, terrain, chassis)
		_check(chassis.to_local(camera.global_position).distance_to(expected_mount) < 0.0002, id + " matches installed geometry")
		_check(_clear_front(camera, chassis), id + " full forward view clears assembled meshes")

	# The ground scene slerps the drawn chassis independently of its current-tick quaternion slots.
	var next_rotation := Basis(Vector3.UP, PI / 2.0)
	var halfway := Basis(Vector3.UP, PI / 4.0) * Basis(Vector3.RIGHT, 0.32)
	chassis.global_transform = Transform3D(halfway, Vector3(3.0, 1.2, -8.0))
	var before := _notifications()
	rig.update(camera, Vector3.ONE, next_rotation, 1.0 / 60.0, false, terrain, chassis)
	_check(camera.global_basis.is_equal_approx(halfway)
		and camera.global_position.distance_to(chassis.to_global(expected_mount)) < 0.0002, id + " follows drawn slope and half-turn")
	_check(_notifications() == before, id + " continuous FPV motion retains history")
	var fpv_pose := camera.global_transform
	rig.update(camera, chassis.global_position, next_rotation, 0.0, true, terrain, chassis)
	_check(rig.mode == GroundCamera.FPV and not camera.global_transform.is_equal_approx(fpv_pose)
		and is_equal_approx(camera.fov, 46.0), id + " garage inspects the car while retaining Drive choice")
	_check(_notifications() == before + 1, id + " one garage cut")
	rig.update(camera, chassis.global_position, next_rotation, 0.0, false, terrain, chassis)
	_check(camera.global_transform.is_equal_approx(fpv_pose) and _notifications() == before + 2, id + " one cut back to final FPV pose")
	camera.free()
	chassis.free()


## Test the full forward half-space independently of clipping. A rotated wheel's bounding box may
## conservatively cross the eye; visit actual vertices only for meshes that fail the broad check.
func _clear_front(camera: Camera3D, chassis: Node3D) -> bool:
	var eye_from_world := camera.global_transform.affine_inverse()
	for node: Node in chassis.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null or not part.is_visible_in_tree():
			continue
		var eye_from_part := eye_from_world * part.global_transform
		if (eye_from_part * part.mesh.get_aabb()).position.z > 0.005:
			continue
		for surface in part.mesh.get_surface_count():
			var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				if (eye_from_part * vertex).z <= 0.005:
					printerr("Insufficient FPV clearance at ", part.name)
					return false
	return true
