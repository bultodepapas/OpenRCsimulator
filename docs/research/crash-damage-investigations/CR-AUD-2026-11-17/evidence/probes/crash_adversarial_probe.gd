## Adversarial source audit probe for the production presentation paths.
## Synthetic mesh/point-mass fixture. Uses private methods deliberately to inspect
## immediate handoff state, without interpreting the visual surrogate as the
## authoritative flight dynamics or as physical validation.
##
## Run against the pinned engine with an imported app project, e.g.:
##   python3 tools/godot/run_checked.py --timeout 90 --out-dir <scratch> \
##     --label collision-audit-adversarial -- <pinned-godot> --headless \
##     --path app --audio-driver Dummy --script <absolute-path-to-this-file>
## A failing exit is the intended honest result if an independent expectation
## is violated. Directly emitted contact signals test the connected callback's
## behavior only; they do not prove that the physics solver produced a contact.
extends SceneTree

const WreckController = preload("res://render/crash/wreck.gd")
const EffectsController = preload("res://render/crash/effects.gd")
const SceneryBodies = preload("res://render/landscape_upgrade/scenery_bodies.gd")
const TOTAL_MASS := 4.0
const SECTION_MASS := 1.0
const SECTION_X := 3.25
const CG_X := SECTION_MASS * SECTION_X / TOTAL_MASS
const VELOCITY := Vector3(1.0, 0.0, 0.0)
const OMEGA := Vector3(0.0, 0.0, 2.0)
const ALTITUDE := 10.0
var _checks := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(id: String, passed: bool, observed: String) -> void:
	_checks += 1
	if not passed:
		_failed += 1
	print("PROBE ", id, " ", "PASS" if passed else "FAIL", " ", observed)

func _mass_boxes() -> Array:
	# Point inventories have independently calculable COM: (3*0 + 1*3.25)/4 = 0.8125 m.
	return [
		{mass = 3.0, center = Vector3.ZERO, size = Vector3.ZERO},
		{mass = SECTION_MASS, center = Vector3(SECTION_X, 0.0, 0.0), size = Vector3.ZERO},
	]

func _severity(level: int, component := "fuselage") -> Dictionary:
	return {"class": level, "component": component, "mass_kg": TOTAL_MASS,
		"inventory_boxes": _mass_boxes(), "cg_model": Vector3(CG_X, 0, 0),
		"normal_speed_mps": 0.0, "scatter_energy_fraction": 0.0, "seed": 1}

func _make_model() -> Node3D:
	var model := Node3D.new()
	model.name = "synthetic_airplane"
	var core := MeshInstance3D.new()
	core.name = "fuselage"
	var fuselage := BoxMesh.new()
	fuselage.size = Vector3(2.0, 1.0, 1.0)
	core.mesh = fuselage
	model.add_child(core)
	var prop := MeshInstance3D.new()
	prop.name = "propeller"
	prop.position = Vector3(3.0, 0.0, 0.0)
	var prop_box := BoxMesh.new()
	prop_box.size = Vector3.ONE
	prop.mesh = prop_box
	model.add_child(prop)
	return model

func _make_shape_model() -> Node3D:
	# Widely separated box centers make coverage independent of visual judgement.
	var model := Node3D.new()
	model.name = "synthetic_separate_sections"
	for spec in [
		["fuselage", Vector3.ZERO, Vector3.ONE],
		["wing_left", Vector3(-3, 0, 0), Vector3(1, 0.3, 1)],
		["wing_right", Vector3(3, 0, 0), Vector3(1, 0.3, 1)],
		["propeller", Vector3(0, 0, -3), Vector3.ONE],
	]:
		var node := MeshInstance3D.new()
		node.name = spec[0]
		node.position = spec[1]
		var box := BoxMesh.new()
		box.size = spec[2]
		node.mesh = box
		model.add_child(node)
	return model

func _core_box_contains(wreck: Variant, world_point: Vector3) -> bool:
	# The current production core proxy is one centered BoxShape3D. This is a
	# point-coverage check, not a full geometry or perception qualification.
	var collision: CollisionShape3D = wreck._shape_nodes[0]
	if collision.disabled or not collision.shape is BoxShape3D:
		return false
	var local: Vector3 = collision.global_transform.affine_inverse() * world_point
	var half: Vector3 = (collision.shape as BoxShape3D).size * 0.5
	return absf(local.x) <= half.x + 1.0e-4 and absf(local.y) <= half.y + 1.0e-4 and absf(local.z) <= half.z + 1.0e-4

func _mass_sum(wreck: Variant) -> float:
	var result := 0.0
	for body: RigidBody3D in wreck._bodies:
		if body.visible:
			result += body.mass
	return result

func _linear_momentum(wreck: Variant) -> Vector3:
	var result := Vector3.ZERO
	for body: RigidBody3D in wreck._bodies:
		if body.visible:
			result += body.mass * body.linear_velocity
	return result

func _index(wreck: Variant, kind: String) -> int:
	for i in range(1, wreck._groups.size()):
		if String(wreck._groups[i].kind) == kind:
			return i
	return -1

func _run() -> void:
	var model := _make_model()
	var shape_model := _make_shape_model()
	var wreck := WreckController.new()
	var shape_wreck := WreckController.new()
	var fx_fast := EffectsController.new()
	var fx_slow := EffectsController.new()
	root.add_child(model)
	root.add_child(shape_model)
	root.add_child(wreck)
	root.add_child(shape_wreck)
	root.add_child(fx_fast)
	root.add_child(fx_slow)
	await process_frame
	wreck.set_process(false)
	shape_wreck.set_process(false)
	var shape_prepared: bool = shape_wreck.prepare(shape_model)
	var prepared: bool = wreck.prepare(model)
	_check("FIXTURE_PREPARED", prepared and _index(wreck, "propeller") > 0,
		"prepared=%s groups=%s" % [prepared, str(wreck.stats().fragment_groups)])
	if not prepared or _index(wreck, "propeller") < 0:
		quit(1)
		return
	fx_fast.prepare()
	fx_slow.prepare()
	var point := Vector3(2.0, ALTITUDE, 3.0)
	var effect_report := {"class": 3, "severity": 0.7, "surface": "tree_trunk", "component_group": "fuselage"}
	fx_fast.start(point, Vector3(5, -2, 0), effect_report, 0.0, false, Vector3.ZERO)
	fx_slow.start(point, Vector3(5, -2, 0), effect_report, 0.0, false, Vector3.ZERO)
	_check("ALT_EFFECT_ORIGIN", absf(fx_fast._origin.y - point.y) < 0.75,
		"impact_y=%.3f effect_y=%.3f" % [point.y, fx_fast._origin.y])
	_check("ALT_DUST_EMITTER", absf(fx_fast.dust.global_position.y - point.y) < 0.75,
		"impact_y=%.3f dust_y=%.3f" % [point.y, fx_fast.dust.global_position.y])
	var min_chip_y := INF
	var max_chip_y := -INF
	for i in fx_fast._fragment_count:
		min_chip_y = minf(min_chip_y, fx_fast._positions[i].y)
		max_chip_y = maxf(max_chip_y, fx_fast._positions[i].y)
	_check("ALT_CHIP_SPAWN", fx_fast._fragment_count > 0 and min_chip_y > point.y - 0.75 and max_chip_y < point.y + 1.5,
		"impact_y=%.3f chip_y=[%.3f,%.3f] count=%d" % [point.y, min_chip_y, max_chip_y, fx_fast._fragment_count])
	for i in 60:
		fx_fast.update(1.0 / 60.0, false)
	for i in 10:
		fx_slow.update(0.1, false)
	_check("DT_EFFECT_ELAPSED", absf(fx_fast._age - fx_slow._age) < 1.0e-4 and absf(fx_slow._age - 1.0) < 1.0e-4,
		"same_total_input_s=1.000 age_60hz=%.6f age_10hz=%.6f" % [fx_fast._age, fx_slow._age])

	var plane_shape: CollisionShape3D = wreck._ground.get_node("WreckPlaneShape")
	var plane: Plane = (plane_shape.shape as WorldBoundaryShape3D).plane
	print("PROBE FLAT_PLANE_INFO normal=", plane.normal, " distance=", plane.d, " impact_y=", ALTITUDE)
	var pose := Transform3D(Basis.IDENTITY, Vector3(0.0, ALTITUDE, 0.0))

	# An intact body's COM is the declared CG.  Its COM velocity equals the
	# incoming CG velocity, even when its geometric box center is elsewhere.
	wreck.start(pose, VELOCITY, OMEGA, _severity(1))
	var core: RigidBody3D = wreck._core_body
	var measured_com: Vector3 = Vector3(wreck._groups[0].center) + core.center_of_mass
	_check("FIXTURE_COM", core.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM and measured_com.distance_to(Vector3(CG_X, 0, 0)) < 1.0e-4,
		"model_com=%s expected=(%.4f,0,0) body_box_center=%s" % [str(measured_com), CG_X, str(wreck._groups[0].center)])
	_check("COM_LAUNCH_VELOCITY", core.linear_velocity.distance_to(VELOCITY) < 1.0e-4,
		"incoming_CG_velocity=%s launched_linear_velocity=%s omega=%s" % [str(VELOCITY), str(core.linear_velocity), str(OMEGA)])

	# Signal the same active core against a real layer/shape obstacle and against
	# the ground.  This tests the connected callback, not solver contact timing.
	var obstacle: StaticBody3D = SceneryBodies._body({"shape": "box", "north": 0.0,
		"east": 0.0, "down": -ALTITUDE, "half_x": 0.5, "half_down": 0.5,
		"half_z": 0.5, "id": "synthetic-wall"}, 0)
	root.add_child(obstacle)
	var strengths: Array[float] = []
	wreck.secondary_impact.connect(func(_position: Vector3, strength: float) -> void: strengths.append(strength))
	core.linear_velocity = Vector3(10, 0, 0)
	wreck._secondary_lockout_s = 0.0
	core.body_entered.emit(wreck._ground)
	var after_ground := strengths.size()
	wreck._secondary_lockout_s = 0.0
	core.linear_velocity = Vector3(10, 0, 0)
	core.body_entered.emit(obstacle)
	var after_obstacle := strengths.size()
	_check("CALLBACK_CONTROL_GROUND", after_ground == 1,
		"ground_signals=%d obstacle_layer=%d core_mask=%d" % [after_ground, obstacle.collision_layer, core.collision_mask])
	_check("CALLBACK_SCENERY", obstacle.get_child_count() > 0 and obstacle.collision_layer == core.collision_mask and after_obstacle == after_ground + 1,
		"direct_ground_signals=%d after_valid_static_scenery=%d" % [after_ground, after_obstacle])

	# A scheduled section stays visibly attached until its timer fires. Measure
	# before and after without stepping the solver, avoiding external impulses.
	wreck.reset()
	wreck.start(pose, VELOCITY, OMEGA, _severity(4))
	var delayed_index := _index(wreck, "propeller")
	var initial_mass := _mass_sum(wreck)
	var delay: float = wreck._groups[delayed_index].due_s
	_check("DELAYED_RELEASE_MASS", delay > 0.0 and absf(initial_mass - TOTAL_MASS) < 1.0e-4,
		"aircraft_mass=%.3f visible_active_mass=%.3f scheduled_delay_s=%.3f" % [TOTAL_MASS, initial_mass, delay])
	wreck._process(delay + 0.01)
	_check("DELAYED_RELEASE_MASS_CONTROL", absf(_mass_sum(wreck) - TOTAL_MASS) < 1.0e-4,
		"after_release_visible_mass=%.3f" % _mass_sum(wreck))

	# Later C3 release: conservation of mass, first moment, and linear momentum
	# for an instantaneous separation with no scatter and no physics frame.
	wreck.reset()
	wreck.start(pose, VELOCITY, OMEGA, _severity(3))
	core = wreck._core_body
	var old_com_world: Vector3 = core.global_transform * core.center_of_mass
	var old_v: Vector3 = core.linear_velocity
	var before_momentum := _linear_momentum(wreck)
	var before_first_moment := core.mass * old_com_world
	wreck._record_c3_contact_exposure(100.0)
	wreck._release_pending_c3_contact_group(wreck._run_generation)
	var section_index := _index(wreck, "propeller")
	var section: RigidBody3D = wreck._bodies[section_index]
	# AUTO computes the centered synthetic box COM even if its custom-COM
	# property retains a stale value from a prior pooled C4 run.
	var section_local_com: Vector3 = section.center_of_mass if section.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM else Vector3.ZERO
	var section_com_world: Vector3 = section.global_transform * section_local_com
	var core_com_world: Vector3 = core.global_transform * core.center_of_mass
	var after_first_moment := core.mass * core_com_world + section.mass * section_com_world
	var after_momentum := _linear_momentum(wreck)
	var expected_section_v := old_v + OMEGA.cross((pose * Vector3(SECTION_X, 0, 0)) - old_com_world)
	_check("C3_RELEASE_CONTROL", section.visible and absf(_mass_sum(wreck) - TOTAL_MASS) < 1.0e-4,
		"visible=%s mass_before=%.3f mass_after=%.3f" % [section.visible, TOTAL_MASS, _mass_sum(wreck)])
	_check("C3_RELEASE_FIRST_MOMENT", before_first_moment.distance_to(after_first_moment) < 1.0e-3,
		"before=%s after=%s core_com=%s section_com=%s" % [str(before_first_moment), str(after_first_moment), str(core_com_world), str(section_com_world)])
	_check("C3_RELEASE_POINT_VELOCITY", section.linear_velocity.distance_to(expected_section_v) < 1.0e-3,
		"expected_inventory_COM_v=%s actual_v=%s" % [str(expected_section_v), str(section.linear_velocity)])
	_check("C3_RELEASE_LINEAR_MOMENTUM", before_momentum.distance_to(after_momentum) < 1.0e-3,
		"before=%s after=%s" % [str(before_momentum), str(after_momentum)])

	# C3: only the left wing is selected; the visible right wing remains on core.
	# C2: the propeller is released immediately.  In each case query the center
	# of the relevant fixture part against the current core collision box.
	_check("SHAPE_FIXTURE_PREPARED", shape_prepared and _index(shape_wreck, "wing_left") > 0 and _index(shape_wreck, "wing_right") > 0 and _index(shape_wreck, "propeller") > 0,
		"groups=%s" % str(shape_wreck.stats().fragment_groups))
	if shape_prepared and _index(shape_wreck, "wing_right") > 0 and _index(shape_wreck, "propeller") > 0:
		shape_wreck.start(pose, Vector3.ZERO, Vector3.ZERO,
			{"class": 3, "component": "left_wing_tip", "mass_kg": 4.0, "normal_speed_mps": 0.0})
		var right_index := _index(shape_wreck, "wing_right")
		var right_group: Dictionary = shape_wreck._groups[right_index]
		var right_point: Vector3 = pose * Vector3(right_group.center)
		var right_attached: bool = not bool(right_group.detached) and not bool(right_group.get("carried", false))
		var right_covered := _core_box_contains(shape_wreck, right_point)
		_check("C3_ATTACHED_RIGHT_WING_PROXY", right_attached and right_covered,
			"right_attached=%s right_center=%s core_box_covers=%s" % [right_attached, str(right_point), right_covered])
		shape_wreck.reset()
		shape_wreck.start(pose, Vector3.ZERO, Vector3.ZERO,
			{"class": 2, "component": "propeller", "mass_kg": 4.0, "normal_speed_mps": 0.0})
		var prop_index := _index(shape_wreck, "propeller")
		var prop_group: Dictionary = shape_wreck._groups[prop_index]
		var prop_point: Vector3 = pose * Vector3(prop_group.center)
		var prop_detached: bool = bool(prop_group.detached) and bool(prop_group.activated)
		var ghost_covered := _core_box_contains(shape_wreck, prop_point)
		_check("C2_DETACHED_PROP_PROXY", prop_detached and not ghost_covered,
			"prop_detached=%s original_center=%s core_box_still_covers=%s" % [prop_detached, str(prop_point), ghost_covered])

	print("PROBE RESULT ", _checks, " checks, ", _failed, " failed")
	obstacle.free()
	wreck.free()
	shape_wreck.free()
	model.free()
	shape_model.free()
	fx_fast.free()
	fx_slow.free()
	quit(1 if _failed > 0 else 0)
