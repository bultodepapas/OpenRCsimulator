extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Agent := preload("res://ai/companions/agent.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Builder := preload("res://render/airplane.gd")
const Frames := preload("res://render/frames.gd")
const Simulation := preload("res://sim/simulation.gd")
const ControlSurfaces := preload("res://physics/control_surfaces.gd")

var _checks := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label, " ", detail)


func _run() -> void:
	# This is a presentation fixture only: the normal real session and render builder
	# are used, but Agent.configure/profile admission is deliberately out of scope.
	var session := Flight.new()
	session.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	_check("real flight session setup", session.aircraft.get("ok", false)
		and session.sim != null and not session.sim.state.is_empty())
	if not session.aircraft.get("ok", false) or session.sim == null:
		session.free()
		_finish()
		return
	var external_ready: bool = session.configure_external_driver()
	_check("session uses the ordinary external-driver control seam",
		external_ready and session.external_driver_enabled and not session.sim.paused)

	var agent := Agent.new()
	agent.session = session
	agent.view = Builder.build(Catalog.DEFAULT_ID)
	_check("real builder view is available", not agent.view.is_empty()
		and agent.view.get("root") is Node3D and agent.view.get("propeller") is Node3D)
	if agent.view.is_empty():
		agent.free()
		session.free()
		_finish()
		return

	var datum: Vector2 = Builder.datum(Catalog.DEFAULT_ID)
	agent._cg_model = Frames.cg_in_model_frame(session.aircraft.model.cg_le, datum.x, datum.y)
	root.add_child(agent)
	agent.add_child(agent.view.root)

	var previous: PackedFloat64Array = session.sim.state.duplicate()
	var current: PackedFloat64Array = session.sim.state.duplicate()
	previous[0] = 120.0
	previous[1] = -35.0
	previous[2] = -100.0
	current[0] = 132.0
	current[1] = -29.0
	current[2] = -104.0
	session.sim.previous = previous
	session.sim.state = current
	_check("fixture previous/current states are valid",
		Simulation.state_is_valid(previous) and Simulation.state_is_valid(current))
	agent._prop_angle = 0.37
	agent.view.propeller.rotation.z = agent._prop_angle * float(agent.view.get("propeller_spin_sign", 1.0))
	Builder.apply_controls(agent.view, ControlSurfaces.hinge_rotations_from_surfaces(session.surface_angles_deg()), float(session.commands.throttle))

	# Sample at a known physics boundary until the engine fraction is well below the
	# current-state endpoint, so the unfixed stopped-state path has a visible error.
	var fraction := Engine.get_physics_interpolation_fraction()
	for _attempt in 32:
		if fraction < 0.95:
			break
		await physics_frame
		fraction = Engine.get_physics_interpolation_fraction()
	_check("normal fixture has a non-current interpolation fraction", is_finite(fraction) and fraction < 0.95,
		"fraction=%0.6f" % fraction)

	_check_stopped(agent, "frozen render uses current state", true, false, false, false)
	_check_stopped(agent, "failure render uses current state", false, true, false, false)
	_check_stopped(agent, "crash render uses current state", false, false, true, false)
	_check_stopped(agent, "individually paused session uses current state", false, false, false, true)

	agent.failure = ""
	session.crash = {}
	session.sim.set_paused(false)
	var frozen_transform: Transform3D = _root_transform(agent, 1.0)
	var frozen_sim_before: PackedByteArray = _simulation_bytes(agent)
	var frozen_components_before: PackedByteArray = _component_bytes(agent)
	var saved_max_fps: int = Engine.max_fps
	Engine.max_fps = 57
	var frozen_pose_preserved := true
	var minimum_fraction := 1.0
	var maximum_fraction := 0.0
	for _frame in 120:
		await process_frame
		var frame_fraction: float = Engine.get_physics_interpolation_fraction()
		minimum_fraction = minf(minimum_fraction, frame_fraction)
		maximum_fraction = maxf(maximum_fraction, frame_fraction)
		agent.render(1.0 / 57.0, true)
		frozen_pose_preserved = frozen_pose_preserved \
			and agent.view.root.transform.is_equal_approx(frozen_transform)
	Engine.max_fps = saved_max_fps
	_check("120 frozen presentations retain the latest committed pose", frozen_pose_preserved,
		"fraction range=%0.6f..%0.6f" % [minimum_fraction, maximum_fraction])
	_check("120 frozen presentations preserve previous/current and simulation bytes",
		frozen_sim_before == _simulation_bytes(agent))
	_check("120 frozen presentations preserve propeller and hinge transforms",
		frozen_components_before == _component_bytes(agent))
	if DisplayServer.get_name() != "headless":
		_check("native frames vary the interpolation fraction during the frozen sample",
			maximum_fraction - minimum_fraction > 0.01,
			"fraction range=%0.6f..%0.6f" % [minimum_fraction, maximum_fraction])
	print("companion frozen frame sample: 120 frames, fraction=%0.6f..%0.6f" % [minimum_fraction, maximum_fraction])

	var alpha: float = Engine.get_physics_interpolation_fraction()
	for _attempt in 32:
		if alpha < 0.95:
			break
		await physics_frame
		alpha = Engine.get_physics_interpolation_fraction()
	var expected: Transform3D = _root_transform(agent, alpha)
	var current_transform: Transform3D = _root_transform(agent, 1.0)
	var sim_before: PackedByteArray = _simulation_bytes(agent)
	var components_before: PackedByteArray = _component_bytes(agent)
	agent.view.root.transform = current_transform
	agent.render(0.0, false)
	_check("normal render uses the physics interpolation fraction",
		agent.view.root.transform.is_equal_approx(expected),
		"fraction=%0.6f root=%s expected=%s" % [alpha, agent.view.root.transform, expected])
	_check("normal fixture differs visibly from the committed endpoint",
		alpha < 0.95 and expected.origin.distance_to(current_transform.origin) > 0.05,
		"fraction=%0.6f" % alpha)
	_check("normal render preserves previous/current state bytes", sim_before == _simulation_bytes(agent))
	_check("normal render preserves propeller and hinge transforms", components_before == _component_bytes(agent))

	agent.free()
	session.free()
	await process_frame
	_finish()


func _check_stopped(agent: Variant, label: String, frozen: bool, failed: bool,
		crashed: bool, individually_paused: bool) -> void:
	agent.failure = "fixture failure" if failed else ""
	agent.session.crash = {"fixture": true} if crashed else {}
	agent.session.sim.set_paused(individually_paused)
	var expected: Transform3D = _root_transform(agent, 1.0)
	agent.view.root.transform = expected
	var sim_before: PackedByteArray = _simulation_bytes(agent)
	var components_before: PackedByteArray = _component_bytes(agent)
	agent.render(0.0, frozen)
	_check(label, agent.view.root.transform.is_equal_approx(expected),
		"root=%s expected=%s" % [agent.view.root.transform, expected])
	_check(label + " preserves previous/current state bytes", sim_before == _simulation_bytes(agent))
	_check(label + " preserves propeller and hinge transforms", components_before == _component_bytes(agent))


func _root_transform(agent: Variant, fraction: float) -> Transform3D:
	var state: PackedFloat64Array = agent.session.sim.interpolated(fraction)
	var pose: Vector3 = Frames.ned_to_render(Array(state.slice(0, 3)))
	var body: Basis = Frames.quat_to_render(state.slice(6, 10))
	return Frames.root_transform(body, pose, agent._cg_model)


func _simulation_bytes(agent: Variant) -> PackedByteArray:
	return var_to_bytes([agent.session.sim.previous, agent.session.sim.state,
		agent.session.sim.aux, agent.session.sim.inputs, agent.session.sim.tick])


func _component_bytes(agent: Variant) -> PackedByteArray:
	var hinges: Dictionary = agent.view.get("hinges", {})
	var names: Array = hinges.keys()
	names.sort()
	var transforms: Array = []
	for hinge_name in names:
		var hinge: Variant = hinges[hinge_name]
		if hinge is Node3D:
			transforms.append([str(hinge_name), (hinge as Node3D).transform])
	return var_to_bytes([agent.view.propeller.transform, transforms])


func _finish() -> void:
	print("companion render interpolation: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
