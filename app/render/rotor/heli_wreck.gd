## Presentation-only HX-700 wreck adapter. The flight reference is the glow-fuel X-Cell;
## the HX-700's electric-looking mesh is only a visual surrogate and never creates fire.
class_name HeliWreck
extends "res://render/crash/wreck.gd"

const ImpactSeverity := preload("res://render/crash/severity.gd")
const Frames := preload("res://render/frames.gd")
const ShadowRouteSettings := preload("res://render/shadow_settings.gd")

const MAX_ROTOR_RELEASE_SPEED_MPS := 120.0
const ROTOR_CONTACT_MIN_TIP_SPEED_MPS := 20.0
const DEFAULT_MASS_KG := 3.5

var severity: Dictionary = {}
var _model: Dictionary = {}
var _context: Dictionary = {}
var _source_root: Node3D
var _mass_kg: float = 0.0
var _focus := Vector3.ZERO
var _ground_point := Vector3.ZERO
var _ground_normal := Vector3.UP
var _main_rotor_hub := Vector3.ZERO
var _main_rotor_axis := Vector3.UP
var _tail_rotor_hub := Vector3.ZERO
var _tail_rotor_axis := Vector3.RIGHT
var _main_rotor_omega := 0.0
var _tail_rotor_omega := 0.0
var _rotor_spin_energy_budget_j := 0.0
var _rotor_spin_energy_used_j := 0.0


## Duplicate and classify only the HX visual. `context` is read for physical mass and
## optional inventory boxes; this adapter never mutates the source model or flight state.
func configure(model: Dictionary, context: Dictionary) -> bool:
	var source := model.get("root") as Node3D
	if source == null or not is_instance_valid(source):
		push_error("HeliWreck.configure: model.root must be a valid Node3D")
		return false
	_model = model
	_context = context.duplicate(true)
	_source_root = source
	_mass_kg = _finite_number(context.get("mass_kg", context.get("aircraft_mass_kg", DEFAULT_MASS_KG)), 0.0)
	if _mass_kg <= 0.0:
		push_error("HeliWreck.configure: context.mass_kg must be positive")
		return false
	return prepare(source)


## Start the breakup from a terminal-contact report. Kinematics may be rendered Vector3
## values or the packed NED/FRD arrays produced by ImpactDetector.
func start_impact(report: Dictionary, pose: Transform3D, cg_model: Vector3) -> Dictionary:
	if _source_root == null or _twin == null:
		return {"ok": false, "error": "configure(model, context) must succeed before start_impact"}
	if bool(get_stats().started):
		reset()
	_sync_live_transforms(_source_root, _twin)
	_force_rotor_meshes_visible(_twin)
	_refresh_prepared_groups_from_live_pose()
	_cache_rotor_kinematics(report, pose)
	_ground_point = _report_vector(report, ["ground_point_world", "ground_point_world_ned"], pose.origin)
	_ground_normal = _report_normal(report, ["ground_normal_world", "ground_normal_world_ned"], Vector3.UP)
	_set_local_ground_plane(_ground_point, _ground_normal)
	_rotor_spin_energy_budget_j = _shaft_spin_energy_budget("main") + _shaft_spin_energy_budget("tail")
	_rotor_spin_energy_used_j = 0.0
	severity = _make_severity(report, pose, cg_model)
	if not bool(severity.get("valid", false)):
		return {"ok": false, "error": str(severity.get("error", "impact severity is invalid"))}
	var component := str(severity.get("component", report.get("component", "unknown"))).to_lower()
	_apply_rotor_contact_floor(component)
	var incoming := _report_vector(report, ["velocity_world", "velocity_world_ned"], Vector3.ZERO)
	var angular := _report_angular_velocity(report, pose)
	var contact_point := _report_vector(report, ["contact_point_world", "point_world", "point_world_ned"], pose.origin)
	var contact_normal := _report_normal(report, ["contact_normal", "normal_world", "normal_world_ned"], _ground_normal)
	var surface := _surface_id(report)
	var wreck_severity := severity.duplicate(true)
	wreck_severity.merge({
		"class": int(severity.get("class", 1)),
		"mass_kg": _mass_kg,
		"cg_model": cg_model,
		"component": component,
		"surface": surface,
		"contact_point_world": contact_point,
		"contact_normal": contact_normal,
		"normal_impact_energy_j": _finite_number(report.get("normal_energy_j", severity.get("normal_energy_j", 0.0)), 0.0),
		"normal_speed_mps": _finite_number(report.get("normal_speed_mps", severity.get("normal_speed_mps", 0.0)), 0.0),
		"scatter_energy_fraction": 0.12,
		"inventory_boxes": _context.get("inventory_boxes", []),
		"seed": int(report.get("tick", report.get("seed", 0x48454C49))),
	}, true)
	var outcome_class := _severity_class_number(wreck_severity["class"])
	wreck_severity["class"] = outcome_class
	# C2 keeps a hit on one rotor local; C3 stays local to a named rotor or tail strike.
	# C4 remains the only all-sections release. Wreck's scatter impulse is capped at 12% of
	# normal impact energy (600 J total, 14 m/s per impulse); rotor point speed is separately
	# bounded to 120 m/s and all inherited point speeds remain under Wreck's 120 m/s cap.
	wreck_severity["rotor_release_class"] = outcome_class
	set_meta("heli_crash_severity", wreck_severity.duplicate(true))
	super.start(pose, incoming, angular, wreck_severity)
	_rebuild_attached_core_bounds(pose, incoming, angular, cg_model)
	_reset_pool_physics_interpolation()
	_focus = contact_point
	return {"ok": true, "severity": severity.duplicate(true), "stats": stats()}


func reset() -> void:
	super.reset()
	_reset_pool_physics_interpolation()
	severity = {}
	_focus = Vector3.ZERO
	_ground_point = Vector3.ZERO
	_ground_normal = Vector3.UP
	_main_rotor_omega = 0.0
	_tail_rotor_omega = 0.0
	_rotor_spin_energy_budget_j = 0.0
	_rotor_spin_energy_used_j = 0.0


func _reset_pool_physics_interpolation() -> void:
	# Wreck bodies are pooled and can move between distant crash locations without a
	# physics tick between reset and relaunch. Reset interpolation after each teleport.
	for body: RigidBody3D in _bodies:
		if body != null and is_instance_valid(body):
			body.force_update_transform()
			var body_rid := body.get_rid()
			if body_rid.is_valid():
				# A pooled RigidBody3D can still have its prior transform in PhysicsServer3D
				# when a render callback relaunches it before another physics tick.
				PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
				PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, body.linear_velocity)
				PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, body.angular_velocity)
			body.reset_physics_interpolation()


func focus_position() -> Vector3:
	if _core_body != null and is_instance_valid(_core_body) and _core_body.visible:
		return _core_body.global_position
	return _focus


func get_stats() -> Dictionary:
	var result: Dictionary = super.get_stats()
	result["outcome_class"] = int(severity.get("class", -1))
	result["outcome_component"] = str(severity.get("component", ""))
	result["ground_point"] = _ground_point
	result["ground_normal"] = _ground_normal
	result["rotor_spin_energy_budget_j"] = _rotor_spin_energy_budget_j
	result["rotor_spin_energy_used_j"] = _rotor_spin_energy_used_j
	var shafts: Variant = _context.get("shaft_elements", [])
	var momentum: Variant = _context.get("b_body_frd_kg_m2", PackedFloat64Array())
	var has_prepared_momentum: bool = (momentum is PackedFloat64Array or momentum is Array) and momentum.size() == 3
	result["rotor_spin_energy_basis"] = "0.5*shaft inertia*omega^2, divided per authored blade; exact shaft inventory or validated geared momentum" if (shafts is Array and shafts.size() >= 2) or has_prepared_momentum else "estimated from flapping and reflected inertia; no structural calibration"
	return result


func stats() -> Dictionary:
	var result := get_stats()
	result["focus_position"] = focus_position()
	return result


## Keep authored crash-section metadata local to the prepared twin. The GLB's named
## subassemblies map to the shared Wreck release taxonomy without changing the builder.
func _section_of(node: Node) -> String:
	var raw_name := String(node.name)
	var lower_name := raw_name.to_lower()
	var blade_family := _rotor_blade_family(lower_name)
	var kind := ""
	if not blade_family.is_empty():
		if _is_articulated_blade(node, blade_family):
			kind = "propeller" if blade_family == "main" else "rudder"
		else:
			# The GLB retains an unarticulated pair below its source pivots. Hide that
			# duplicate only in the wreck twin; the articulated builder mounts are live.
			_hide_geometry_subtree(node)
			kind = CORE_SECTION
	if kind.is_empty():
		kind = _heli_section(raw_name)
	if kind.is_empty():
		# These are the rotating assemblies, not release parts. Keep traversing through
		# their children so only the four authored blade nodes can become debris bodies.
		if lower_name == "propeller" or lower_name == "tail_rotor":
			kind = CORE_SECTION
		else:
			kind = super._section_of(node)
	if not kind.is_empty():
		node.set_meta("crash_section", kind)
	return kind


func _is_articulated_blade(node: Node, family: String) -> bool:
	var expected_pivot := "main_rotor_pivot" if family == "main" else "tail_rotor_pivot"
	var expected_mount := "propeller" if family == "main" else "tail_rotor"
	var saw_pivot := false
	var saw_mount := false
	var cursor: Node = node.get_parent()
	while cursor != null and cursor != _twin:
		var name := String(cursor.name).to_lower()
		if name == expected_pivot:
			saw_pivot = true
		if name == expected_mount:
			saw_mount = true
		cursor = cursor.get_parent()
	return saw_pivot and saw_mount


func _hide_geometry_subtree(node: Node) -> void:
	# Exclude the whole legacy branch from Wreck's bounds walker as well as rendering;
	# hidden collision-irrelevant GLB duplicates should not inflate core or detached boxes.
	node.set_meta("crash_no_bounds", true)
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visible = false
	for child: Node in node.get_children():
		_hide_geometry_subtree(child)


func _release_kinds_for(class_level: int, hint: String) -> Array:
	var h := _normalize_hint(hint)
	var rotor_family := _rotor_family(h)
	if class_level == 2:
		if rotor_family == "main":
			return ["propeller"] if _has_prepared_kind("propeller") else []
		if rotor_family == "tail":
			# `rudder` is the shared small-part release slot; here it holds one tail blade.
			return ["rudder"] if _has_prepared_kind("rudder") else []
		if h.contains("skid") or h.contains("gear"):
			return ["gear"] if _has_prepared_kind("gear") else []
		if h.contains("tail_boom") or h.contains("tail_fin"):
			return ["tail_boom"] if _has_prepared_kind("tail_boom") else []
		if h.contains("carenado") or h.contains("canopy"):
			return ["canopy"] if _has_prepared_kind("canopy") else []
		if h.contains("fuselage") or h.contains("nose"):
			# HX nose contacts are authored against the carenado; release that local panel.
			return ["canopy"] if _has_prepared_kind("canopy") else []
		return []
	if class_level == 3:
		if rotor_family == "main":
			return ["propeller"] if _has_prepared_kind("propeller") else []
		if rotor_family == "tail":
			return ["rudder"] if _has_prepared_kind("rudder") else []
		if h.contains("skid") or h.contains("gear"):
			return ["gear"] if _has_prepared_kind("gear") else []
		if h.contains("carenado") or h.contains("canopy"):
			return ["canopy"] if _has_prepared_kind("canopy") else []
		if h.contains("tail_boom") or h.contains("tail_fin"):
			var tail_kinds: Array = []
			for kind in ["tail_boom", "vertical_tail"]:
				if _has_prepared_kind(kind): tail_kinds.append(kind)
			return tail_kinds
	return super._release_kinds_for(class_level, hint)


func _component_matches(kind: String, component_hint: String) -> bool:
	var h := _normalize_hint(component_hint)
	var rotor_family := _rotor_family(h)
	if kind == "propeller" and rotor_family == "main":
		return true
	if kind == "rudder" and rotor_family == "tail":
		return true
	if kind == "canopy" and (h.contains("fuselage") or h.contains("nose") or h.contains("carenado") or h.contains("canopy")):
		return true
	return super._component_matches(kind, component_hint)


func _connected_members(members: Array) -> Array:
	# Independent authored blades stay independent even when their hub bounds touch.
	for member: Variant in members:
		if not member is Node or _rotor_blade_family(String((member as Node).name)).is_empty():
			return super._connected_members(members)
	var singles: Array = []
	for member: Variant in members:
		singles.append([member])
	return singles


func _activate_group(index: int) -> void:
	if index <= 0 or index >= _groups.size():
		super._activate_group(index)
		return
	var group: Dictionary = _groups[index]
	var spin_velocity := _rotor_release_velocity(group)
	var family := _rotor_group_family(group)
	var spin_energy := 0.0
	if not family.is_empty() and spin_velocity.length_squared() > 0.0:
		var mass := maxf(_finite_number(group.get("mass", _bodies[index].mass), _bodies[index].mass), 0.015)
		var blade_share := _shaft_spin_energy_budget(family) / float(_rotor_blade_count(family))
		var blade_count := _released_blade_count(group, family)
		var group_budget := blade_share * float(blade_count)
		spin_velocity = _clamp_vector(spin_velocity, sqrt(maxf(2.0 * group_budget / mass, 0.0)))
		spin_energy = 0.5 * mass * spin_velocity.length_squared()
	super._activate_group(index)
	if index < _bodies.size() and _bodies[index].visible and spin_velocity.length_squared() > 0.0:
		var body := _bodies[index]
		body.linear_velocity = _clamp_vector(body.linear_velocity + spin_velocity, MAX_POINT_SPEED_MPS)
		_rotor_spin_energy_used_j += spin_energy


func _limit_ground_rebound(body: RigidBody3D) -> void:
	var body_index := _bodies.find(body)
	if body_index < 0 or body_index >= _shape_nodes.size():
		return
	var shape := _shape_nodes[body_index].shape as BoxShape3D
	if shape == null:
		return
	var normal := _ground_normal.normalized()
	var half := shape.size * 0.5
	var basis := body.global_transform.basis
	var support := absf(basis.x.dot(normal)) * half.x + absf(basis.y.dot(normal)) * half.y + absf(basis.z.dot(normal)) * half.z
	var signed_distance := (body.global_position - _ground_point).dot(normal)
	var clear_distance := support + 0.015
	if signed_distance < clear_distance:
		body.global_position += normal * minf(clear_distance - signed_distance, 0.35)
	signed_distance = (body.global_position - _ground_point).dot(normal)
	var normal_speed := body.linear_velocity.dot(normal)
	if signed_distance <= support + 0.15 and normal_speed < 0.0:
		body.linear_velocity -= normal * normal_speed * (1.0 + float(_ground_contact.bounce))


func _update_contact_shadow(index: int) -> void:
	if index < 0 or index >= _bodies.size() or index >= _shadows.size():
		return
	var body := _bodies[index]
	var shadow := _shadows[index]
	if not ShadowRouteSettings.projected_enabled() or not body.visible:
		shadow.visible = false
		return
	var normal := _ground_normal.normalized()
	var shape := _shape_nodes[index].shape as BoxShape3D
	var half := shape.size * 0.5
	var body_basis := body.global_transform.basis
	var support := absf(body_basis.x.dot(normal)) * half.x + absf(body_basis.y.dot(normal)) * half.y + absf(body_basis.z.dot(normal)) * half.z
	var height := maxf((body.global_position - _ground_point).dot(normal) - support, 0.0)
	var fade := clampf(1.0 - height / SHADOW_FADE_HEIGHT_M, 0.0, 1.0)
	var shrink := lerpf(1.0, 0.35, clampf(height / SHADOW_FADE_HEIGHT_M, 0.0, 1.0))
	var local_x := Vector3.RIGHT.slide(normal).normalized()
	if local_x.length_squared() < 0.5:
		local_x = Vector3.FORWARD.slide(normal).normalized()
	var local_z := local_x.cross(normal).normalized()
	if local_z.length_squared() < 0.5:
		local_z = Vector3.BACK
	var width := 0.0
	var depth := 0.0
	width = absf(body_basis.x.dot(local_x)) * half.x + absf(body_basis.y.dot(local_x)) * half.y + absf(body_basis.z.dot(local_x)) * half.z
	depth = absf(body_basis.x.dot(local_z)) * half.x + absf(body_basis.y.dot(local_z)) * half.y + absf(body_basis.z.dot(local_z)) * half.z
	var alpha := 0.22 * fade
	shadow.visible = alpha > 0.002
	var projected := body.global_position - normal * (body.global_position - _ground_point).dot(normal)
	var shadow_basis := Basis(local_x, normal, local_z).scaled(Vector3(
		maxf(width * 2.0 + 0.35, 0.65) * shrink, 1.0,
		maxf(depth * 2.0 + 0.35, 0.65) * shrink))
	shadow.global_transform = Transform3D(shadow_basis, projected + normal * 0.012)
	_shadow_materials[index].set_shader_parameter("opacity", alpha)


func _rebuild_attached_core_bounds(pose: Transform3D, velocity: Vector3, angular: Vector3, cg_model: Vector3) -> void:
	if _twin == null or _core_body == null or not is_instance_valid(_core_body):
		return
	var excluded: Array = []
	for i in range(1, _groups.size()):
		var group: Dictionary = _groups[i]
		if bool(group.get("detached", false)):
			excluded.append_array(group.get("members", []))
	var aggregate := {"has": false, "bounds": AABB()}
	_collect_mesh_bounds(_twin, _twin, excluded, aggregate)
	if not bool(aggregate.has):
		return
	var bounds: AABB = aggregate.bounds
	var center := bounds.get_center()
	_groups[0].bounds = bounds
	_groups[0].center = center
	_set_shape_bounds(0, bounds)
	_core_body.global_transform = pose * Transform3D(Basis.IDENTITY, center)
	_twin.transform = Transform3D(Basis.IDENTITY, -center)
	_set_center_of_mass(_core_body, _core_moment(), _core_body.mass, center)
	_core_body.linear_velocity = _clamp_vector(velocity + angular.cross(pose.basis * (center - cg_model)), MAX_POINT_SPEED_MPS)
	_groups[0].base_velocity = velocity
	_groups[0].base_angular_velocity = angular


func _set_local_ground_plane(point: Vector3, normal: Vector3) -> void:
	if _ground == null:
		return
	var safe_normal := normal.normalized()
	if safe_normal.length_squared() < 0.5:
		safe_normal = Vector3.UP
	_ground_point = point
	_ground_normal = safe_normal
	_ground.global_transform = Transform3D.IDENTITY
	var collision := _ground.get_node_or_null("WreckPlaneShape") as CollisionShape3D
	if collision != null and collision.shape is WorldBoundaryShape3D:
		(collision.shape as WorldBoundaryShape3D).plane = Plane(safe_normal, safe_normal.dot(point))


func _sync_live_transforms(source: Node3D, clone: Node3D, is_root: bool = true) -> void:
	if source == null or clone == null or not is_instance_valid(source) or not is_instance_valid(clone):
		return
	# Wreck.start places the outer model root from the impact pose; copying its scene-local
	# transform here would apply the world pose twice.
	if not is_root:
		clone.transform = source.transform
	var cloned_children: Dictionary = {}
	for child: Node in clone.get_children():
		if child is Node3D:
			var key := String(child.name)
			if not cloned_children.has(key): cloned_children[key] = []
			cloned_children[key].append(child)
	var used: Dictionary = {}
	for child: Node in source.get_children():
		if not child is Node3D:
			continue
		var key := String(child.name)
		if not cloned_children.has(key):
			continue # Rotor blur/night-light adapters are outside the authored twin.
		var ordinal := int(used.get(key, 0))
		var matches: Array = cloned_children[key]
		if ordinal < matches.size():
			_sync_live_transforms(child as Node3D, matches[ordinal] as Node3D, false)
			used[key] = ordinal + 1


func _force_rotor_meshes_visible(node: Node) -> void:
	for child: Node in node.get_children():
		var in_rotor := _is_in_rotor_assembly(child)
		if in_rotor and child is GeometryInstance3D:
			(child as GeometryInstance3D).visible = true
		_force_rotor_meshes_visible(child)


func _is_in_rotor_assembly(node: Node) -> bool:
	var current: Node = node
	while current != null and current != _twin:
		if current.name == "propeller" or current.name == "tail_rotor":
			return true
		current = current.get_parent()
	return false


func _cache_rotor_kinematics(report: Dictionary, pose: Transform3D) -> void:
	_main_rotor_omega = _finite_number(report.get("main_omega_rad_s", 0.0), 0.0) * float(_model.get("main_visual_spin_sign", -1.0))
	_tail_rotor_omega = _finite_number(report.get("tail_omega_rad_s", 0.0), 0.0) * float(_model.get("tail_visual_spin_sign", -1.0))
	var main_pivot := _model.get("main_rotor_pivot") as Node3D
	var tail_pivot := _model.get("tail_rotor_pivot") as Node3D
	var main_tilt := _model.get("main_rotor_tilt") as Node3D
	if main_pivot != null and is_instance_valid(main_pivot):
		var main_local := _relative_transform_to_root(main_pivot, _source_root)
		_main_rotor_hub = pose * main_local.origin
	else:
		_main_rotor_hub = pose * Vector3(0.0, 0.0, 0.35)
	var main_axis_model: Vector3 = _model.get("main_rotor_axis_visual", Vector3.UP)
	var main_tilt_local := _relative_transform_to_root(main_tilt, _source_root) if main_tilt != null and is_instance_valid(main_tilt) else Transform3D.IDENTITY
	_main_rotor_axis = (pose.basis * main_tilt_local.basis * main_axis_model).normalized()
	if tail_pivot != null and is_instance_valid(tail_pivot):
		var tail_local := _relative_transform_to_root(tail_pivot, _source_root)
		_tail_rotor_hub = pose * tail_local.origin
	else:
		_tail_rotor_hub = pose * Vector3(-0.95, 0.2, 0.0)
	var tail_axis_model: Vector3 = _model.get("tail_rotor_axis_visual", Vector3.LEFT)
	_tail_rotor_axis = (pose.basis * tail_axis_model).normalized()
	if _main_rotor_axis.length_squared() < 0.5: _main_rotor_axis = pose.basis * Vector3.UP
	if _tail_rotor_axis.length_squared() < 0.5: _tail_rotor_axis = pose.basis * Vector3.RIGHT


func _rotor_release_velocity(group: Dictionary) -> Vector3:
	var members: Array = group.get("members", [])
	var family := ""
	for member_value: Variant in members:
		if not member_value is Node:
			return Vector3.ZERO
		var member_family := _rotor_blade_family(String((member_value as Node).name))
		if member_family.is_empty() or (not family.is_empty() and member_family != family):
			return Vector3.ZERO
		family = member_family
	# Only groups made entirely from one named rotor's authored blades receive point speed.
	if family.is_empty():
		return Vector3.ZERO
	var tail := family == "tail"
	var omega := _tail_rotor_omega if tail else _main_rotor_omega
	var axis := _tail_rotor_axis if tail else _main_rotor_axis
	var hub := _tail_rotor_hub if tail else _main_rotor_hub
	if absf(omega) < 1.0e-6 or axis.length_squared() < 0.5:
		return Vector3.ZERO
	var model_center: Vector3 = group.get("center", Vector3.ZERO)
	var world_center := _current_pose_for_center(model_center)
	var velocity := omega * axis.normalized().cross(world_center - hub)
	return _clamp_vector(velocity, MAX_ROTOR_RELEASE_SPEED_MPS)


func _rotor_group_family(group: Dictionary) -> String:
	var family := ""
	for member_value: Variant in group.get("members", []):
		if not member_value is Node:
			return ""
		var member_family := _rotor_blade_family(String((member_value as Node).name))
		if member_family.is_empty() or (not family.is_empty() and member_family != family):
			return ""
		family = member_family
	return family


func _released_blade_count(group: Dictionary, family: String) -> int:
	var count := 0
	for member_value: Variant in group.get("members", []):
		if member_value is Node and _rotor_blade_family(String((member_value as Node).name)) == family:
			count += 1
	return maxi(count, 1)


func _rotor_blade_count(family: String) -> int:
	var key := "main_model" if family == "main" else "tail_model"
	var model: Variant = _context.get(key, {})
	var count := int(_finite_number(model.get("rotor_blade_count", 2), 2.0)) if model is Dictionary else 2
	return maxi(count, 1)


func _shaft_spin_energy_budget(family: String) -> float:
	var inertia := _shaft_rotor_inertia(family)
	var omega := _main_rotor_omega if family == "main" else _tail_rotor_omega
	if inertia <= 0.0 or not is_finite(omega):
		return 0.0
	return 0.5 * inertia * omega * omega


func _shaft_rotor_inertia(family: String) -> float:
	# Prefer raw shaft inventory if supplied. Prepared contexts retain geared momentum;
	# the loader validates orthogonal main/tail axes, so this recovers each shaft inertia exactly.
	var shafts: Variant = _context.get("shaft_elements", [])
	var index := 0 if family == "main" else 1
	if shafts is Array and shafts.size() > index and shafts[index] is Dictionary:
		return maxf(_finite_number(shafts[index].get("inertia_kg_m2", 0.0), 0.0), 0.0)
	var momentum: Variant = _context.get("b_body_frd_kg_m2", PackedFloat64Array())
	if (momentum is PackedFloat64Array or momentum is Array) and momentum.size() == 3:
		if family == "main":
			return absf(float(momentum[2]))
		var tail_model_for_axis: Variant = _context.get("tail_model", {})
		var ratio_for_axis := _finite_number(tail_model_for_axis.get("tail_to_main_speed_ratio", 0.0), 0.0) if tail_model_for_axis is Dictionary else 0.0
		return absf(float(momentum[1])) / ratio_for_axis if ratio_for_axis > 0.0 else 0.0
	var main_model: Variant = _context.get("main_model", {})
	var tail_model: Variant = _context.get("tail_model", {})
	if not main_model is Dictionary or not tail_model is Dictionary:
		return 0.0
	var main_inertia := _finite_number(main_model.get("blade_flapping_inertia_kg_m2", 0.0), 0.0)
	main_inertia *= float(_rotor_blade_count("main"))
	if family == "main":
		return maxf(main_inertia, 0.0)
	var reflected := _finite_number(_context.get("spin_inertia_kg_m2", 0.0), 0.0)
	var ratio := _finite_number(tail_model.get("tail_to_main_speed_ratio", 0.0), 0.0)
	if reflected <= main_inertia or ratio <= 0.0:
		return 0.0
	return (reflected - main_inertia) / (ratio * ratio)


func _current_pose_for_center(model_center: Vector3) -> Vector3:
	if _core_body != null and is_instance_valid(_core_body) and _twin != null:
		return _core_body.global_transform * (_twin.transform * model_center)
	return model_center


func _make_severity(report: Dictionary, pose: Transform3D, cg_model: Vector3) -> Dictionary:
	var supplied: Variant = report.get("severity", report.get("outcome", null))
	if supplied is Dictionary and (supplied as Dictionary).has("class"):
		var supplied_result: Dictionary = (supplied as Dictionary).duplicate(true)
		supplied_result["valid"] = bool(supplied_result.get("valid", true))
		supplied_result["component"] = str(supplied_result.get("component", report.get("component", "unknown"))).to_lower()
		supplied_result["surface"] = str(supplied_result.get("surface", _surface_id(report))).to_lower()
		var fallback_group := _severity_component(str(supplied_result["component"]))
		supplied_result["component_group"] = str(supplied_result.get("component_group", fallback_group))
		supplied_result["cg_model"] = cg_model
		return supplied_result
	var component := str(report.get("component", "unknown")).to_lower()
	var normal := _report_normal(report, ["contact_normal", "normal_world", "normal_world_ned"], _ground_normal)
	var incoming := _report_vector(report, ["velocity_world", "velocity_world_ned"], Vector3.ZERO)
	var normal_speed := _finite_number(report.get("normal_speed_mps", 0.0), 0.0)
	var tangent_speed := _finite_number(report.get("tangent_speed_mps", 0.0), 0.0)
	if normal_speed <= 0.0:
		var point_velocity := _report_vector(report, ["point_velocity_world", "point_velocity_world_ned"], incoming)
		normal_speed = maxf(0.0, -point_velocity.dot(normal))
		var tangent := point_velocity - normal * point_velocity.dot(normal)
		tangent_speed = tangent.length()
	var angle := rad_to_deg(atan2(normal_speed, tangent_speed)) if normal_speed > 0.0 or tangent_speed > 0.0 else 0.0
	var effective_mass := _finite_number(report.get("effective_mass_kg", -1.0), -1.0)
	var cg_normal_speed := maxf(0.0, -incoming.dot(normal))
	var surface := _surface_id(report)
	var result := ImpactSeverity.estimate(_mass_kg, normal_speed, tangent_speed, angle, surface,
		_severity_component(component), effective_mass, 1.0, cg_normal_speed)
	if report.has("normal_energy_j"):
		result["normal_energy_j"] = _finite_number(report.normal_energy_j, result.get("normal_energy_j", 0.0))
	if report.has("normal_speed_mps"):
		result["normal_speed_mps"] = normal_speed
	result["component"] = component
	result["surface"] = surface
	result["cg_model"] = cg_model
	result["valid"] = bool(result.get("valid", false))
	return result


func _apply_rotor_contact_floor(component: String) -> void:
	var family := _rotor_family(_normalize_hint(component))
	if family.is_empty():
		return
	var omega := absf(_main_rotor_omega if family == "main" else _tail_rotor_omega)
	var radius := _rotor_radius(family)
	var tip_speed := omega * radius
	severity["rotor_tip_speed_mps"] = tip_speed
	severity["rotor_damage_proxy"] = "estimated rotating-disc contact; no structural calibration"
	if tip_speed < ROTOR_CONTACT_MIN_TIP_SPEED_MPS:
		return
	var class_level := _severity_class_number(severity.get("class", 0))
	if class_level < 2:
		severity["class"] = 2
		severity["severity"] = maxf(_finite_number(severity.get("severity", 0.0), 0.0), 0.25)
	severity["class_basis"] = "rotor tip-speed presentation floor; not an airframe-strength threshold"
	severity["component_group"] = str(severity.get("component_group", "propeller"))


func _severity_class_number(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, 4)
	var label := str(value).to_upper().strip_edges()
	if label.begins_with("C"):
		label = label.substr(1)
	return clampi(int(label) if label.is_valid_int() else 0, 0, 4)


func _rotor_radius(family: String) -> float:
	var context_key := "main_model" if family == "main" else "tail_model"
	var context_model: Variant = _context.get(context_key, {})
	var key := "rotor_radius_m" if family == "main" else "tail_rotor_radius_m"
	var radius := _finite_number(context_model.get(key, 0.0), 0.0) if context_model is Dictionary else 0.0
	if radius > 0.0:
		return radius
	key = "main_rotor_radius_runtime_m" if family == "main" else "tail_rotor_radius_runtime_m"
	return maxf(_finite_number(_model.get(key, 0.0), 0.0), 0.0)


func _rotor_family(hint: String) -> String:
	if hint.contains("tail_rotor") or (hint.contains("rotor") and hint.contains("tail")):
		return "tail"
	if hint.contains("main_rotor") or hint == "rotor" or hint.contains("rotor"):
		return "main"
	return ""


func _normalize_hint(hint: String) -> String:
	return hint.to_lower().replace("-", "_").replace(" ", "_")


func _rotor_blade_family(raw_name: String) -> String:
	match raw_name.to_lower():
		"pala_principal_a", "pala_principal_b": return "main"
		"pala_cola_a", "pala_cola_b": return "tail"
		_: return ""


func _severity_component(component: String) -> String:
	if component.contains("rotor"):
		return "propeller"
	if component.contains("tail_boom"):
		return "tail"
	if component.contains("tail_fin"):
		return "fin"
	if component.contains("skid") or component.contains("gear"):
		return "gear"
	if component.contains("carenado") or component.contains("canopy"):
		return "canopy"
	if component.contains("fuselage") or component.contains("nose"):
		return "fuselage"
	return component


func _surface_id(report: Dictionary) -> String:
	var value: Variant = report.get("surface_id", report.get("surface", "grass"))
	if value is Dictionary:
		var surface: Dictionary = value
		return str(surface.get("id", surface.get("surface_id", "grass"))).to_lower()
	var result := str(value).to_lower()
	return "grass" if result.is_empty() or result in ["terrain", "rotorpad"] else result


func _report_vector(report: Dictionary, keys: Array, fallback: Vector3) -> Vector3:
	for key: String in keys:
		if not report.has(key):
			continue
		var value: Variant = report[key]
		if value is Vector3:
			return value
		if (value is PackedFloat64Array or value is Array) and value.size() == 3:
			return Vector3(float(value[1]), -float(value[2]), -float(value[0]))
	return fallback


func _report_normal(report: Dictionary, keys: Array, fallback: Vector3) -> Vector3:
	var value := _report_vector(report, keys, fallback)
	return value.normalized() if value.length_squared() > 1.0e-8 else fallback.normalized()


func _report_angular_velocity(report: Dictionary, pose: Transform3D) -> Vector3:
	if report.get("angular_velocity_world") is Vector3:
		return report.angular_velocity_world
	if report.get("body_angular_velocity") is PackedFloat64Array or report.get("body_angular_velocity") is Array:
		var value: Variant = report.body_angular_velocity
		if value.size() == 3:
			var body_model := Vector3(value[1], -value[2], -value[0])
			return pose.basis * body_model
	return Vector3.ZERO


func _refresh_prepared_groups_from_live_pose() -> void:
	if _twin == null:
		return
	# Wreck's normal prepare cache reflects the model at configuration time. Refresh its
	# bounds and member transforms once per terminal event after copying the live rotor
	# phase, while retaining the original records for reset().
	var reset_records: Array[Dictionary] = _member_records.duplicate(true)
	_groups.clear()
	_member_records.clear()
	_selected_roots.clear()
	_collect_fragment_groups(_twin)
	_build_group_records()
	_prepared_groups = _copy_groups(_groups)
	_configure_pool_shapes()
	_member_records = reset_records


func _has_prepared_kind(kind: String) -> bool:
	for group: Dictionary in _prepared_groups:
		if String(group.get("kind", "")) == kind:
			return true
	return false


func _heli_section(raw_name: String) -> String:
	match raw_name.to_lower():
		"botalon_carbono", "caja_cola", "soportes_botalon": return "tail_boom"
		"aleta_vertical": return "vertical_tail"
		"tren_de_aterrizaje": return "gear"
		"carenado": return "canopy"
		_: return ""


func _finite_number(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return float(value)
