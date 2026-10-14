extends SceneTree

const Model := preload("res://aircraft/hx700_model.gd")
const Data := preload("res://physics/rotorcraft_data.gd")
const RotorVisual := preload("res://render/rotor/heli_rotor_visual.gd")
const HeliWreck := preload("res://render/rotor/heli_wreck.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var model: Dictionary = Model.build()
	var loaded: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
	if model.is_empty() or not bool(loaded.get("ok", false)):
		_check("HX source model and X-Cell context load", false, str(loaded.get("errors", [])))
		_finish()
		return
	root.add_child(model.root)
	var wreck: Variant = HeliWreck.new()
	wreck.name = "HeliWreckTest"
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	_check("clean source clone prepares", wreck.configure(model, loaded.context))
	if not bool(wreck.get_stats().prepared):
		_finish()
		return
	_check_rotor_taxonomy(wreck)
	_check_legacy_rotor_filter(wreck)
	var visual: Variant = RotorVisual.attach(model, root)
	_check("live rotor visual attaches after clone preparation", visual != null)
	if visual == null:
		_finish()
		return
	visual.update({"omega_rad_s": 167.0, "tail_omega_rad_s": 778.0, "a1": 0.0, "b1": 0.0}, PI * 0.5, PI * 0.5)
	await process_frame
	var source_main_a := _named_node(model.root, "Pala_Principal_A") as Node3D
	var source_tail_a := _named_node(model.root, "Pala_Cola_A") as Node3D
	_check("fixture has the actual named main and tail blades", source_main_a != null and source_tail_a != null)
	if source_main_a == null or source_tail_a == null:
		_finish()
		return
	var impact_pose := Transform3D(Basis(Vector3.UP, 0.37), Vector3(1.2, 0.8, -2.4))
	var post_step_pose := Transform3D(Basis(Vector3.UP, -0.6), Vector3(-5.0, 2.0, 4.0))
	model.root.global_transform = post_step_pose
	await process_frame
	var main_local: Transform3D = wreck._relative_transform_to_root(model.main_rotor_pivot, model.root)
	var tail_local: Transform3D = wreck._relative_transform_to_root(model.tail_rotor_pivot, model.root)
	var blade_locals := {}
	for blade_name in ["Pala_Principal_A", "Pala_Principal_B", "Pala_Cola_A", "Pala_Cola_B"]:
		var blade := _named_node(model.root, blade_name) as Node3D
		if blade != null:
			blade_locals[blade_name] = wreck._relative_transform_to_root(blade, model.root)
	var pose_report := _report("main_rotor", 1, 167.0, 778.0)
	pose_report["severity"]["severity"] = 0.05
	var started: Dictionary = wreck.start_impact(pose_report, impact_pose, model.cg_model_m)
	_check("impact starts from the supplied body pose", bool(started.get("ok", false)))
	_check("rotating main-disc contact receives local C2 presentation grade",
		int(wreck.severity.get("class", 0)) == 2 and float(wreck.severity.get("rotor_tip_speed_mps", 0.0)) > 20.0)
	_check("rotor floor retains the shared propeller audio/effect alias",
		str(wreck.severity.get("component_group", "")) == "propeller")
	_check("main pivot hub uses impact pose with live local transform",
		wreck._main_rotor_hub.distance_to(impact_pose * main_local.origin) < 1.0e-5)
	_check("tail pivot hub also uses impact pose, not post-step globals",
		wreck._tail_rotor_hub.distance_to(impact_pose * tail_local.origin) < 1.0e-5)
	var detached_main := _detached_groups(wreck, "propeller")
	_check("C2 main-rotor hit releases one authored blade only", detached_main.size() == 1 and _group_has_family(detached_main[0], "main"), str(detached_main.size()))
	var released_main: Dictionary = detached_main[0] if not detached_main.is_empty() else {}
	if not released_main.is_empty():
		var radial: Vector3 = wreck._current_pose_for_center(released_main.center) - wreck._main_rotor_hub
		var expected_spin: Vector3 = wreck._main_rotor_omega * wreck._main_rotor_axis.cross(radial)
		var actual_spin: Vector3 = _visible_bodies_for(wreck, "propeller")[0].linear_velocity - released_main.base_velocity if not _visible_bodies_for(wreck, "propeller").is_empty() else Vector3.ZERO
		var direction_match := actual_spin.normalized().dot(expected_spin.normalized()) if actual_spin.length_squared() > 1.0e-8 and expected_spin.length_squared() > 1.0e-8 else -1.0
		_check("main blade inherits signed tangential motion at impact", actual_spin.length() > 20.0 and direction_match > 0.98 and absf(actual_spin.dot(radial.normalized())) < 1.0, "speed=%.2f direction_dot=%.4f" % [actual_spin.length(), direction_match])
	var released_node: Node3D = released_main.members[0] as Node3D if not released_main.is_empty() else null
	if released_node != null:
		var expected: Transform3D = impact_pose * blade_locals[String(released_node.name)]
		_check("released blade preserves its live animated transform at impact",
			released_node.global_transform.is_equal_approx(expected), String(released_node.name))
	var energy_stats: Dictionary = wreck.get_stats()
	var main_budget := _shaft_budget(loaded.context, 0, 167.0)
	_check("main rotor inherited spin energy stays within declared shaft budget",
		float(energy_stats.rotor_spin_energy_used_j) <= main_budget / 2.0 + 1.0e-4
		and float(energy_stats.rotor_spin_energy_used_j) > 0.0,
		"main blade share=%.3f used=%.3f" % [main_budget / 2.0, float(energy_stats.rotor_spin_energy_used_j)])
	_check("detached main blade point speed stays capped", float(energy_stats.max_speed_seen_mps) <= 120.0)
	var main_group_bodies: Array = _visible_bodies_for(wreck, "propeller")
	_check("rotor bodies stay inside the bounded wreck pool", int(energy_stats.pool_size) <= 24 and main_group_bodies.size() == 1)
	var gear_group := _first_group(wreck, "gear")
	var canopy_group := _first_group(wreck, "canopy")
	_check("gear receives no main or tail rotor point velocity", gear_group.is_empty() or wreck._rotor_release_velocity(gear_group) == Vector3.ZERO)
	_check("canopy receives no main or tail rotor point velocity", canopy_group.is_empty() or wreck._rotor_release_velocity(canopy_group) == Vector3.ZERO)
	if released_node != null and not gear_group.is_empty() and not gear_group.members.is_empty():
		_check("mixed airframe and blade debris receives no rotor-only velocity",
			wreck._rotor_release_velocity({"members": [released_node, gear_group.members[0]]}) == Vector3.ZERO)
	wreck.reset()
	_check("reset returns the animated blade to its configure-time source hierarchy",
		_named_node(wreck._twin, "propeller") != null and not wreck.get_stats().started)

	# Tail contact only selects tail blades; main blades remain on the core.
	var tail_report := _report("tail_rotor", 1, 167.0, 778.0)
	var tail_started: Dictionary = wreck.start_impact(tail_report, impact_pose, model.cg_model_m)
	var detached_tail := _detached_groups(wreck, "rudder")
	_check("tail-disc contact starts and releases one named tail blade",
		bool(tail_started.get("ok", false)) and detached_tail.size() == 1 and _group_has_family(detached_tail[0], "tail"))
	_check("tail-disc contact does not release main blades", _detached_groups(wreck, "propeller").is_empty())
	var tail_energy_stats: Dictionary = wreck.get_stats()
	var tail_budget := _shaft_budget(loaded.context, 1, 778.0)
	_check("tail blade kinetic share stays within the declared tail-shaft budget",
		float(tail_energy_stats.rotor_spin_energy_used_j) <= tail_budget / 2.0 + 1.0e-4 and tail_energy_stats.rotor_spin_energy_used_j > 0.0,
		"tail blade share=%.3f used=%.3f" % [tail_budget / 2.0, float(tail_energy_stats.rotor_spin_energy_used_j)])
	wreck.reset()

	# C3 skid/canopy contacts release only those sections and must not receive rotor spin.
	var gear_report := _report("landing_gear", 3, 167.0, 778.0)
	gear_report["velocity_world"] = Vector3(1.0, 0.0, 0.0)
	gear_report["normal_energy_j"] = 0.0
	gear_report["severity"]["normal_energy_j"] = 0.0
	var gear_started: Dictionary = wreck.start_impact(gear_report, impact_pose, model.cg_model_m)
	var released_gears := _visible_bodies_for(wreck, "gear")
	_check("C3 skid hit stays local and starts without rotor releases",
		bool(gear_started.get("ok", false)) and not released_gears.is_empty()
		and _detached_groups(wreck, "propeller").is_empty() and _detached_groups(wreck, "rudder").is_empty())
	var gear_velocity_clean := true
	for body: RigidBody3D in released_gears:
		if body.linear_velocity.distance_to(wreck._core_body.linear_velocity) > 1.0e-4:
			gear_velocity_clean = false
	_check("skid bodies inherit aircraft velocity without rotor spin", gear_velocity_clean)
	wreck.reset()
	var canopy_report := _report("canopy", 3, 167.0, 778.0)
	canopy_report["normal_energy_j"] = 0.0
	canopy_report["severity"]["normal_energy_j"] = 0.0
	var canopy_started: Dictionary = wreck.start_impact(canopy_report, impact_pose, model.cg_model_m)
	_check("C3 canopy hit does not release or inherit velocity from either rotor",
		bool(canopy_started.get("ok", false)) and not _visible_bodies_for(wreck, "canopy").is_empty()
		and _detached_groups(wreck, "propeller").is_empty() and _detached_groups(wreck, "rudder").is_empty())
	for body: RigidBody3D in _visible_bodies_for(wreck, "canopy"):
		_check("canopy linear velocity equals aircraft point velocity", body.linear_velocity.distance_to(wreck._core_body.linear_velocity) < 1.0e-4)
	wreck.reset()
	var nose_report := _report("fuselage", 2, 167.0, 778.0)
	var nose_started: Dictionary = wreck.start_impact(nose_report, impact_pose, model.cg_model_m)
	var nose_canopy := _detached_groups(wreck, "canopy")
	_check("C2 nose contact maps to one local carenado panel", bool(nose_started.get("ok", false)) and nose_canopy.size() == 1)
	_check("nose C2 damage leaves rotor blades and gear attached", _detached_groups(wreck, "propeller").is_empty() and _detached_groups(wreck, "rudder").is_empty() and _detached_groups(wreck, "gear").is_empty())
	wreck.reset()

	var low_report := _report("fuselage", 1, 167.0, 778.0)
	_check("low non-rotor impact leaves all authored sections attached",
		bool(wreck.start_impact(low_report, impact_pose, model.cg_model_m).ok) and _detached_groups(wreck).is_empty())
	wreck.reset()
	var severe_report := _report("fuselage", 4, 167.0, 778.0)
	var severe_started: Dictionary = wreck.start_impact(severe_report, impact_pose, model.cg_model_m)
	_check("severe C4 impact can release all bounded named debris groups",
		bool(severe_started.get("ok", false)) and _detached_groups(wreck).size() > detached_main.size()
		and int(wreck.get_stats().pool_size) <= 24)
	wreck.reset()
	_check("reset leaves no active debris bodies", int(wreck.get_stats().active_body_count) == 0)
	wreck.free()
	visual.free()
	model.root.free()
	_finish()


func _check_rotor_taxonomy(wreck: Variant) -> void:
	var main_names: Array[String] = []
	var tail_names: Array[String] = []
	for group: Dictionary in wreck._prepared_groups:
		for member: Node3D in group.get("members", []):
			var name := String(member.name)
			if name in ["Pala_Principal_A", "Pala_Principal_B"]:
				main_names.append(name)
			if name in ["Pala_Cola_A", "Pala_Cola_B"]:
				tail_names.append(name)
	_check("main rotor assembly splits into two named blade groups", main_names.size() == 2 and main_names.has("Pala_Principal_A") and main_names.has("Pala_Principal_B"), str(main_names))
	_check("tail rotor assembly splits into two named blade groups", tail_names.size() == 2 and tail_names.has("Pala_Cola_A") and tail_names.has("Pala_Cola_B"), str(tail_names))


func _check_legacy_rotor_filter(wreck: Variant) -> void:
	var legacy_count := 0
	var hidden_and_excluded := true
	for node: Node in wreck._twin.find_children("*", "Node3D", true, false):
		var family: String = wreck._rotor_blade_family(String(node.name))
		if family.is_empty() or wreck._is_articulated_blade(node, family):
			continue
		legacy_count += 1
		hidden_and_excluded = hidden_and_excluded and node.has_meta("crash_no_bounds") and _subtree_meshes_hidden(node)
	_check("legacy rotor duplicates are hidden and excluded from bounds", legacy_count == 4 and hidden_and_excluded, "legacy=%d" % legacy_count)


func _subtree_meshes_hidden(node: Node) -> bool:
	if node is GeometryInstance3D and (node as GeometryInstance3D).visible:
		return false
	for child: Node in node.get_children():
		if not _subtree_meshes_hidden(child):
			return false
	return true


func _report(component: String, class_level: int, main_omega: float, tail_omega: float) -> Dictionary:
	var group := "gear" if component.contains("gear") else "canopy" if component == "canopy" else "propeller" if component.contains("rotor") else "fuselage"
	return {
		"component": component,
		"surface": "grass",
		"normal_speed_mps": 1.0,
		"tangent_speed_mps": 2.0,
		"normal_energy_j": 1.0,
		"effective_mass_kg": 1.0,
		"point_world": Vector3(1.2, 0.8, -2.4),
		"ground_point_world": Vector3(0.0, -50.0, 0.0),
		"normal_world": Vector3.UP,
		"ground_normal_world": Vector3.UP,
		"velocity_world": Vector3.ZERO,
		"point_velocity_world": Vector3.ZERO,
		"body_angular_velocity": Vector3.ZERO,
		"main_omega_rad_s": main_omega,
		"tail_omega_rad_s": tail_omega,
		"severity": {
			"valid": true,
			"class": class_level,
			"severity": 0.05 if class_level < 2 else 0.5,
			"component": component,
			"component_group": group,
			"surface": "grass",
			"normal_energy_j": 1.0,
		},
	}


func _named_node(root_node: Node, node_name: String) -> Node:
	var matches := root_node.find_children(node_name, "Node3D", true, false)
	return matches[0] if not matches.is_empty() else null


func _detached_groups(wreck: Variant, kind := "") -> Array:
	var out: Array = []
	for i in range(1, wreck._groups.size()):
		var group: Dictionary = wreck._groups[i]
		if bool(group.get("detached", false)) and (kind.is_empty() or String(group.get("kind", "")) == kind):
			out.append(group)
	return out


func _visible_bodies_for(wreck: Variant, kind: String) -> Array:
	var out: Array = []
	for i in range(1, wreck._groups.size()):
		if String(wreck._groups[i].get("kind", "")) == kind and i < wreck._bodies.size() and wreck._bodies[i].visible:
			out.append(wreck._bodies[i])
	return out


func _first_group(wreck: Variant, kind: String) -> Dictionary:
	for group: Dictionary in wreck._groups:
		if String(group.get("kind", "")) == kind:
			return group
	return {}


func _group_has_family(group: Dictionary, family: String) -> bool:
	for member: Node3D in group.get("members", []):
		if family == "main" and String(member.name) in ["Pala_Principal_A", "Pala_Principal_B"]:
			return true
		if family == "tail" and String(member.name) in ["Pala_Cola_A", "Pala_Cola_B"]:
			return true
	return false


func _shaft_budget(context: Dictionary, index: int, omega: float) -> float:
	var momentum: PackedFloat64Array = context.get("b_body_frd_kg_m2", PackedFloat64Array())
	var inertia: float = absf(momentum[2]) if index == 0 else absf(momentum[1]) / float(context.tail_model.tail_to_main_speed_ratio)
	return 0.5 * inertia * omega * omega


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	print("HELI-33 visual: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
