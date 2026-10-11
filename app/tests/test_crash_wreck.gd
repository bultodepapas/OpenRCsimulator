extends SceneTree

const AircraftCatalog = preload("res://app_state/aircraft_catalog.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")
const WreckController = preload("res://render/crash/wreck.gd")
const PHYSICS_HZ := 240

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for entry: Dictionary in AircraftCatalog.ENTRIES:
		await _check_aircraft(entry)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_aircraft(entry: Dictionary) -> void:
	var airplane_model: Dictionary = AirplaneBuilder.build(String(entry.id))
	var airplane: Node3D = airplane_model.root
	root.add_child(airplane)
	await process_frame
	var original_visibility: bool = airplane.visible
	airplane.visible = false # Match the production crash view, which shows only the duplicate.
	var source_signature := _tree_signature(airplane)
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false) # Drive separation timers at a fixed 60 Hz below.
	var prepared: bool = wreck.prepare(airplane)
	_check(String(entry.id) + " prepares a mesh twin", prepared)
	if not prepared:
		wreck.free()
		airplane.free()
		await process_frame
		return
	var prepared_stats: Dictionary = wreck.get_stats()
	var fragment_groups: Array = prepared_stats.fragment_groups
	_check(String(entry.id) + " pool remains capped at 24 rigid bodies", int(prepared_stats.pool_size) == 24)
	_check(String(entry.id) + " has a shadow per pooled body", int(prepared_stats.contact_shadow_count) == 24)
	_check(String(entry.id) + " exposes actual mesh-backed fragment groups", fragment_groups.size() >= 2)
	if String(entry.id) == "jensen-das-ugly-stik-60":
		for required_group in ["wing_left", "wing_right", "horizontal_tail", "vertical_tail", "engine", "propeller"]:
			_check("Ugly Stik preserves recognizable " + String(required_group), fragment_groups.has(required_group))

	var pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 5.0, 0.0))
	var incoming := Vector3(0.0, -12.0, -3.0)
	var angular := Vector3(1.2, 0.7, -0.5)
	var severity := {
		"class": "C2",
		"mass_kg": 10.0,
		"cg_model": Vector3(0.0, 0.12, -0.25),
		"normal_speed_mps": 12.0,
		"component": "fuselage",
		"seed": 61,
	}
	wreck.start(pose, incoming, angular, severity)
	var low_stats: Dictionary = wreck.stats()
	_check(String(entry.id) + " C2 keeps the airframe together", int(low_stats.detached_group_count) == 0 and int(low_stats.active_body_count) == 1)
	_check(String(entry.id) + " visible core carries real mesh geometry", wreck._twin.visible and _visible_mesh_count(wreck._twin) > 0)
	var expected_core_velocity: Vector3 = incoming + angular.cross(pose.basis * (wreck._groups[0].center - severity.cg_model))
	_check(String(entry.id) + " core inherits angular velocity about model-space CG", wreck._bodies[0].linear_velocity.is_equal_approx(expected_core_velocity))
	_check(String(entry.id) + " low class injects no separation energy", is_zero_approx(float(low_stats.scatter_energy_j)))
	wreck.reset()
	_check(String(entry.id) + " reset hides pooled bodies and twin", not wreck._twin.visible and int(wreck.stats().active_body_count) == 0)
	if String(entry.id) == "jensen-das-ugly-stik-60":
		await _check_c3_contact_release(wreck, airplane, source_signature)

	severity["class"] = "C4"
	severity.erase("component")
	wreck.start(pose, incoming, angular, severity)
	var started: Dictionary = wreck.stats()
	_check(String(entry.id) + " C4 releases progressive real submeshes", int(started.detached_group_count) >= 1 and int(started.active_body_count) > 1 and int(started.active_body_count) <= 24)
	_check(String(entry.id) + " C4 core remains visually present", wreck._twin.visible and _visible_mesh_count(wreck._twin) > 0)
	_check(String(entry.id) + " separation energy is bounded by normal impact energy", float(started.scatter_energy_j) <= float(started.normal_impact_energy_estimate_j) * 0.12 + 0.001)
	_check(String(entry.id) + " secondary impact strength is documented in joules", String(started.secondary_impact_strength_unit) == "J")
	_check(String(entry.id) + " ground and debris use only the isolated wreck layer", wreck._ground is StaticBody3D and wreck._ground.collision_mask == 0 and wreck._ground.collision_layer == wreck._bodies[0].collision_mask)
	_check(String(entry.id) + " every pooled body enables CCD", _all_bodies_use_ccd(wreck))
	var secondary_strengths: Array[float] = []
	wreck.secondary_impact.connect(func(_position: Vector3, strength: float) -> void:
		secondary_strengths.append(strength)
	)
	wreck._process(1.0 / 60.0)
	_check(String(entry.id) + " contact shadows start visible and on the floor", _visible_shadow_count(wreck) > 0 and _shadows_on_ground(wreck))

	# Pause must freeze body transforms; delayed releases resume with their timer.
	var core: RigidBody3D = wreck._bodies[0]
	wreck.set_paused(true)
	var paused_transform: Transform3D = core.global_transform
	for _i in 8:
		await physics_frame
	_check(String(entry.id) + " wreck pause freezes its core", core.global_transform.is_equal_approx(paused_transform))
	wreck.set_paused(false)

	var tunnelled := false
	var invalid_state := false
	for tick in PHYSICS_HZ * 8:
		await physics_frame
		if tick % 4 == 0:
			wreck._process(1.0 / 60.0)
		for body: RigidBody3D in wreck._bodies:
			if not body.visible:
				continue
			if not _body_state_is_finite(body):
				invalid_state = true
			if _box_bottom_y(body) < -0.15:
				tunnelled = true
				break
		if tunnelled or invalid_state:
			break
	var final_stats: Dictionary = wreck.stats()
	_check(String(entry.id) + " debris state stays finite", not invalid_state)
	_check(String(entry.id) + " box colliders do not tunnel below local ground", not tunnelled)
	_check(String(entry.id) + " delayed groups all release within 8 seconds", int(final_stats.active_body_count) == int(final_stats.detached_group_count) + 1)
	_check(String(entry.id) + " delayed scatter stays inside its total energy budget", float(final_stats.scatter_energy_j) <= float(final_stats.normal_impact_energy_estimate_j) * 0.12 + 0.001)
	var secondary_events_valid := int(final_stats.secondary_impacts) == secondary_strengths.size() and not secondary_strengths.is_empty()
	for strength in secondary_strengths:
		secondary_events_valid = secondary_events_valid and is_finite(strength) and strength >= 0.35 and strength <= 250.0
	_check(String(entry.id) + " secondary contacts emit finite joule strengths", secondary_events_valid, "events %d" % secondary_strengths.size())
	_check(String(entry.id) + " at least one impact piece sleeps at rest", int(final_stats.sleeping_body_count) >= 1)
	var resting: Array[Dictionary] = _sleeping_transforms(wreck)
	wreck.set_paused(true)
	var paused_resting: Array[Dictionary] = _sleeping_transforms(wreck)
	for _i in 8:
		await physics_frame
	wreck.set_paused(false)
	for _i in 8:
		await physics_frame
	_check(String(entry.id) + " sleeping wreck stays still through pause and resume", _resting_transforms_stable(paused_resting, wreck))
	for _i in int(PHYSICS_HZ / 2):
		await physics_frame
		if _i % 4 == 0:
			wreck._process(1.0 / 60.0)
	_check(String(entry.id) + " sleeping pieces persist until reset", _resting_transforms_stable(resting, wreck))
	wreck.reset()
	var reset_stats: Dictionary = wreck.stats()
	_check(String(entry.id) + " reset clears visible debris, shadows and counts", int(reset_stats.active_body_count) == 0 and _visible_body_count(wreck) == 0 and _visible_shadow_count(wreck) == 0)
	_check(String(entry.id) + " reset leaves the original model hierarchy and hinges intact", source_signature == _tree_signature(airplane))
	_check(String(entry.id) + " reset preserves the source visibility contract", not airplane.visible)
	airplane.visible = original_visibility
	wreck.free()
	airplane.free()
	await process_frame


func _check_c3_contact_release(wreck: Variant, source_airplane: Node3D, source_signature: Array[String]) -> void:
	var pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 20.0, 0.0))
	var incoming := Vector3(0.0, -10.0, -1.0)
	var angular := Vector3(0.3, 0.5, -0.2)
	var severity := {
		"class": "C3",
		"mass_kg": 10.0,
		"cg_model": Vector3(0.0, 0.12, -0.25),
		"normal_speed_mps": 12.0,
		"component": "fuselage",
		"seed": 611,
	}
	wreck.start(pose, incoming, angular, severity)
	wreck._process(0.4) # Release the scheduled wings and tails before testing later core contacts.
	var start_stats: Dictionary = wreck.stats()
	var propeller_index := _group_index(wreck, "propeller")
	_check("Ugly Stik C3 initially keeps the propeller with the core", propeller_index > 0 and not bool(wreck._groups[propeller_index].detached))
	_check("C3 contact exposure starts at zero and is separate from impact joules", is_zero_approx(float(start_stats.c3_contact_exposure_index_j)) and String(start_stats.c3_contact_exposure_unit).contains("provisional"))
	if propeller_index < 1:
		wreck.reset()
		return
	var threshold := float(start_stats.c3_contact_release_thresholds_j.propeller)
	var per_contact_energy := threshold * 0.35
	var core: RigidBody3D = wreck._core_body
	core.freeze = true # Keep the core point state fixed while testing deferred release.
	core.angular_velocity = angular
	var emitted_strengths: Array[float] = []
	wreck.secondary_impact.connect(func(_position: Vector3, strength: float) -> void:
		emitted_strengths.append(strength)
	)
	var scatter_before := float(wreck.stats().scatter_energy_j)
	var active_before := int(wreck.stats().active_body_count)
	for contact_index in 3:
		_submit_c3_core_contact(wreck, per_contact_energy)
		var exposure := float(wreck.stats().c3_contact_exposure_index_j)
		_check("C3 accepted core contact adds a separate cumulative exposure index", exposure > float(contact_index + 1) * per_contact_energy - 0.001)
		if contact_index < 2:
			_check("C3 sub-threshold contact does not detach the next group", not bool(wreck._groups[propeller_index].detached))
		else:
			_check("C3 threshold-crossing callback defers hierarchy mutation", not bool(wreck._groups[propeller_index].activated))
		await process_frame
		await process_frame
	if not bool(wreck._groups[propeller_index].activated):
		_check("C3 propeller releases after accumulated threshold", false)
		wreck.reset()
		return
	var first_body: RigidBody3D = wreck._bodies[propeller_index]
	_check("C3 contact exposure releases one group at a time", int(wreck.stats().active_body_count) == active_before + 1)
	_check("C3 contact release adds no scatter energy", is_equal_approx(float(wreck.stats().scatter_energy_j), scatter_before))
	_check("C3 contact signal reports per-impact joules, not cumulative exposure", emitted_strengths.size() == 3 and absf(emitted_strengths[0] - per_contact_energy) < 0.01 and float(wreck.stats().c3_contact_exposure_index_j) > emitted_strengths[0])
	var aircraft_pose: Transform3D = core.global_transform * wreck._twin.transform
	var point_offset: Vector3 = aircraft_pose.basis * (wreck._groups[propeller_index].center - wreck._groups[0].center)
	var inherited_point_velocity: Vector3 = core.linear_velocity + core.angular_velocity.cross(point_offset)
	_check("C3 released section inherits the current core point velocity", first_body.linear_velocity.distance_to(inherited_point_velocity) < 0.2)
	_check("C3 mass remains conserved after contact release", absf(_visible_mass_sum(wreck) - float(severity.mass_kg)) < 0.001)
	var before_followup := int(wreck.stats().detached_group_count)
	_submit_c3_core_contact(wreck, 100.0)
	await process_frame
	await process_frame
	_check("large C3 contact still releases at most one next section", int(wreck.stats().detached_group_count) == before_followup + 1)
	_check("C3 mass stays conserved across a second progressive release", absf(_visible_mass_sum(wreck) - float(severity.mass_kg)) < 0.001)
	var expected_core_box := Vector3(
		maxf(wreck._core_bounds.size.x, 0.035),
		maxf(wreck._core_bounds.size.y, 0.035),
		maxf(wreck._core_bounds.size.z, 0.035)
	)
	var core_box := (wreck._shape_nodes[0].shape as BoxShape3D).size
	_check("C3 detached sections do not enlarge the core collision proxy", core_box.is_equal_approx(expected_core_box))
	wreck.reset()
	_check("C3 reset clears exposure and restores the source hierarchy", is_zero_approx(float(wreck.stats().c3_contact_exposure_index_j)) and source_signature == _tree_signature(source_airplane))


func _submit_c3_core_contact(wreck: Variant, energy_j: float) -> void:
	var core: RigidBody3D = wreck._core_body
	var speed := sqrt(2.0 * energy_j / maxf(core.mass, 0.0001))
	core.linear_velocity = Vector3.DOWN * speed
	wreck._secondary_lockout_s = 0.0
	# Exercise the same connected body_entered callback used by real debris contacts.
	core.body_entered.emit(wreck._ground)


func _group_index(wreck: Variant, kind: String) -> int:
	for i in range(1, wreck._groups.size()):
		if String(wreck._groups[i].kind) == kind:
			return i
	return -1


func _visible_mass_sum(wreck: Variant) -> float:
	var total := 0.0
	for body: RigidBody3D in wreck._bodies:
		if body.visible:
			total += body.mass
	return total


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("FAIL: " + label + (" — " + detail if not detail.is_empty() else ""))


func _tree_signature(root_node: Node) -> Array[String]:
	var output: Array[String] = []
	_append_tree_signature(root_node, output)
	return output


func _append_tree_signature(node: Node, output: Array[String]) -> void:
	var record := "%s|%s|%d" % [node.name, node.get_class(), node.get_index()]
	if node is Node3D:
		record += "|" + str((node as Node3D).transform) + "|" + str((node as Node3D).visible)
	if node is MeshInstance3D:
		record += "|" + str((node as MeshInstance3D).mesh)
	output.append(record)
	for child in node.get_children():
		_append_tree_signature(child, output)


func _visible_mesh_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).is_visible_in_tree():
		count += 1
	for child in node.get_children():
		count += _visible_mesh_count(child)
	return count


func _visible_body_count(wreck: Node) -> int:
	var count := 0
	for body: RigidBody3D in wreck._bodies:
		if body.visible:
			count += 1
	return count


func _all_bodies_use_ccd(wreck: Node) -> bool:
	for body: RigidBody3D in wreck._bodies:
		if not body.continuous_cd:
			return false
	return true


func _visible_shadow_count(wreck: Node) -> int:
	var count := 0
	for shadow: MeshInstance3D in wreck._shadows:
		if shadow.visible:
			count += 1
	return count


func _shadows_on_ground(wreck: Node) -> bool:
	for shadow: MeshInstance3D in wreck._shadows:
		if shadow.visible and absf(shadow.global_position.y - 0.012) > 0.001:
			return false
	return true


func _body_state_is_finite(body: RigidBody3D) -> bool:
	var values := [body.global_position.x, body.global_position.y, body.global_position.z,
		body.linear_velocity.x, body.linear_velocity.y, body.linear_velocity.z,
		body.angular_velocity.x, body.angular_velocity.y, body.angular_velocity.z]
	for value in values:
		if not is_finite(float(value)):
			return false
	return true


func _box_bottom_y(body: RigidBody3D) -> float:
	var collision := body.get_node("WreckBox") as CollisionShape3D
	var shape := collision.shape as BoxShape3D
	var half := shape.size * 0.5
	var basis := body.global_transform.basis
	var extent := absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
	return body.global_position.y - extent


func _sleeping_transforms(wreck: Node) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for body: RigidBody3D in wreck._bodies:
		if body.visible and body.sleeping:
			output.append({"body": body, "transform": body.global_transform})
	return output


func _resting_transforms_stable(resting: Array[Dictionary], wreck: Node) -> bool:
	if resting.is_empty():
		return false
	for record: Dictionary in resting:
		var body: RigidBody3D = record.body
		if not is_instance_valid(body) or not body.visible or not body.sleeping:
			return false
		if not body.global_transform.is_equal_approx(record.transform):
			return false
	return true
