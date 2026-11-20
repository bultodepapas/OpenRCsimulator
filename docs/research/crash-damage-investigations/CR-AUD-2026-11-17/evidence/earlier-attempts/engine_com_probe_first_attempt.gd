## Independent pinned-engine COM velocity semantics, without ground or separation impulses.
extends SceneTree
class ObservedBody:
	extends RigidBody3D
	var observation: Dictionary = {}
	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if not observation.is_empty(): return
		observation = {"linear": state.linear_velocity, "angular": state.angular_velocity,
			"com": state.center_of_mass, "com_local": state.center_of_mass_local,
			"at_com": state.get_velocity_at_local_position(Vector3(1.0, 0.0, 0.0)),
			"at_origin": state.get_velocity_at_local_position(Vector3.ZERO)}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var body := ObservedBody.new()
	body.custom_integrator = true
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(1.0, 0.0, 0.0)
	body.mass = 4.0
	body.can_sleep = false
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.collision_layer = 0
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	body.position = Vector3(0.0, 10.0, 0.0)
	root.add_child(body)
	body.linear_velocity = Vector3(2.0, 3.0, 4.0)
	body.angular_velocity = Vector3(0.0, 0.0, 2.0)
	for i in 10:
		await physics_frame
		if not body.observation.is_empty(): break
	print("ENGINE_COM_IDENTITY ", Engine.get_version_info(), " setting=", ProjectSettings.get_setting("physics/3d/physics_engine", "unrecorded"))
	print("ENGINE_COM_OBSERVATION ", body.observation)
	var passed: bool = not body.observation.is_empty() \
		and Vector3(body.observation.at_com).distance_to(Vector3(2.0, 3.0, 4.0)) < 1.0e-5 \
		and Vector3(body.observation.at_origin).distance_to(Vector3(2.0, 1.0, 4.0)) < 1.0e-5
	print("ENGINE_COM_PROBE: 1 checks, %d failed" % [0 if passed else 1])
	body.free()
	quit(0 if passed else 1)
