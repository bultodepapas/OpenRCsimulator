extends SceneTree

const Model := preload("res://aircraft/hx700_model.gd")
const Data := preload("res://physics/rotorcraft_data.gd")
const Presentation := preload("res://render/rotor/heli_crash_presentation.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	physics_interpolation = true
	var model: Dictionary = Model.build()
	var loaded: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
	if model.is_empty() or not bool(loaded.get("ok", false)):
		_check("HX model and X-Cell data load", false)
		_finish(model)
		return
	root.add_child(model.root)
	var presentation: Variant = Presentation.new()
	root.add_child(presentation)
	_check("production presentation configures", presentation.configure(model, loaded.context))
	if presentation.wreck == null:
		_finish(model, presentation)
		return
	_check("pooled bodies run with physics interpolation enabled",
		presentation.wreck._bodies[0].is_physics_interpolated_and_enabled())
	var core_id: int = presentation.wreck._bodies[0].get_instance_id()
	var cycle_count := 8
	for cycle in range(cycle_count):
		var main_pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.36, -6.0))
		var nose_pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.50, -6.38465))
		var fence_pose := Transform3D(Basis.IDENTITY, Vector3(-23.96026, 0.325, -3.71))
		model.root.global_transform = main_pose
		presentation.start(_report("main_rotor", 2, main_pose.origin), main_pose, model.cg_model_m, Vector3.ZERO)
		_check("cycle %d main starts at supplied pose" % cycle, _near_wreck(presentation, main_pose, 0.05))
		await physics_frame
		presentation.update(0.0041666667, true)
		_check("cycle %d paused main remains locally placed" % cycle, _near_wreck(presentation, main_pose, 1.0))
		await process_frame
		presentation.reset()
		model.root.global_transform = nose_pose
		presentation.start(_report("nose", 2, nose_pose.origin), nose_pose, model.cg_model_m, Vector3.ZERO)
		_check("cycle %d nose server state starts at new pose after reset" % cycle,
			_near_wreck(presentation, nose_pose, 0.05, false))
		await physics_frame
		presentation.update(0.0041666667, false)
		_check("cycle %d nose remains near pose after physics step" % cycle, _near_wreck(presentation, nose_pose, 1.0))
		await process_frame
		presentation.reset()
		# Deliberately reset and relaunch the pooled body from a frame callback at a
		# position about 24 m away, matching the native fence-capture displacement.
		model.root.global_transform = fence_pose
		presentation.start(_report("fuselage", 4, fence_pose.origin), fence_pose, model.cg_model_m, Vector3.ZERO)
		_check("cycle %d fence server state starts at new pose after reset" % cycle,
			_near_wreck(presentation, fence_pose, 0.05, false))
		await physics_frame
		presentation.update(0.0041666667, false)
		_check("cycle %d fence remains near pose after first physics step" % cycle, _near_wreck(presentation, fence_pose, 1.0))
		for frame in range(2):
			await physics_frame
			presentation.update(0.0041666667, false)
		_check("cycle %d fence has no pooled-body teleport" % cycle, _near_wreck(presentation, fence_pose, 1.5))
		_check("cycle %d reuses the bounded core body" % cycle, presentation.wreck._bodies[0].get_instance_id() == core_id)
		presentation.reset()
	presentation.free()
	_finish(model)


func _report(component: String, class_level: int, body_position: Vector3) -> Dictionary:
	var body_ned := PackedFloat64Array([-body_position.z, body_position.x, -body_position.y])
	var ground_ned := PackedFloat64Array([-body_position.z, body_position.x, 0.0])
	var group := "propeller" if component == "main_rotor" else "fuselage"
	return {
		"component": component,
		"surface": "grass",
		"surface_id": "grass",
		"point_world_ned": body_ned,
		"ground_point_world_ned": ground_ned,
		"normal_world_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"ground_normal_world_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"velocity_world_ned": PackedFloat64Array([0.0, 0.0, 0.0]),
		"point_velocity_world_ned": PackedFloat64Array([0.0, 0.0, 0.0]),
		"body_angular_velocity": PackedFloat64Array([0.0, 0.0, 0.0]),
		"main_omega_rad_s": 167.0,
		"tail_omega_rad_s": 778.0,
		"normal_speed_mps": 0.0,
		"tangent_speed_mps": 0.0,
		"normal_energy_j": 0.0,
		"effective_mass_kg": 1.0,
		"severity": {
			"valid": true,
			"class": class_level,
			"severity": 0.25 if class_level >= 2 else 0.05,
			"component": component,
			"component_group": group,
			"surface": "grass",
		},
	}


func _near_wreck(presentation: Variant, pose: Transform3D, tolerance: float,
		check_interpolation: bool = true) -> bool:
	var wreck: Variant = presentation.wreck
	if wreck == null or wreck._core_body == null or wreck._twin == null:
		return false
	var model_root: Vector3 = wreck._twin.global_transform.origin
	var interpolated_model_root: Vector3 = wreck._twin.get_global_transform_interpolated().origin
	var core_center: Vector3 = wreck._groups[0].center
	var expected_core: Vector3 = pose * core_center
	var interpolated_core: Vector3 = wreck._core_body.get_global_transform_interpolated().origin
	var server_transform: Transform3D = PhysicsServer3D.body_get_state(wreck._core_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var ok: bool = (
		model_root.distance_to(pose.origin) <= tolerance
		and (not check_interpolation or interpolated_model_root.distance_to(pose.origin) <= tolerance)
		and wreck.focus_position().distance_to(expected_core) <= tolerance
		and (not check_interpolation or interpolated_core.distance_to(expected_core) <= tolerance)
		and server_transform.origin.distance_to(expected_core) <= tolerance
	)
	if not ok:
		print("POSE drift model=", model_root, " interp_model=", interpolated_model_root, " expected_model=", pose.origin,
			" focus=", wreck.focus_position(), " interp_core=", interpolated_core, " server_core=", server_transform.origin, " expected_core=", expected_core)
	return ok


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _finish(model: Dictionary, presentation: Node = null) -> void:
	if presentation != null and is_instance_valid(presentation):
		presentation.free()
	if model.get("root") is Node and is_instance_valid(model.root):
		model.root.free()
	print("HELI-33 crash relaunch: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)
