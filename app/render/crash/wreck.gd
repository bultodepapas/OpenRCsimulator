class_name Wreck
extends Node3D

## Visual-only pooled aircraft breakup. No values flow back into the flight simulation.
signal secondary_impact(position: Vector3, strength: float)

const SectionSplitter = preload("res://render/crash/section_splitter.gd")

const MAX_BODIES := 24
const DEBRIS_LAYER := 1 << 19
const MAX_INPUT_SPEED_MPS := 100.0
const MAX_POINT_SPEED_MPS := 120.0
const MAX_SCATTER_SPEED_MPS := 14.0
const MAX_ANGULAR_SPEED_RAD_S := 30.0
const MAX_SCATTER_ENERGY_J := 600.0
const MAX_SCATTER_ENERGY_FRACTION := 0.12
const SHADOW_FADE_HEIGHT_M := 7.0
const MIN_BOX_EDGE_M := 0.035
const MAX_C3_CONTACT_EXPOSURE_INDEX_J := 1000.0
# CR-09b: sections release in order of distance from the contact. Estimated presentation speed of the
# break travelling through the airframe, not a measured stress-wave speed.
const BREAK_PROPAGATION_MPS := 15.0
const MIN_PROPAGATION_DELAY_S := 0.02
const MAX_PROPAGATION_DELAY_S := 0.35
# CR-09b: horizontal momentum leads the scatter direction; the outward share only separates parts.
const SCATTER_OUTWARD_SHARE := 0.35
const SCATTER_LIFT_SHARE := 0.25

# Provisional cosmetic breakup exposure thresholds; these are not material limits.
const C3_CONTACT_RELEASE_ORDER := ["propeller", "gear", "canopy", "engine"]
const C3_CONTACT_RELEASE_THRESHOLDS_J := {
	"propeller": 4.0,
	"gear": 12.0,
	"canopy": 25.0,
	"engine": 50.0,
}

const GROUP_ORDER := [
	"wing_left", "wing_right", "wing_center", "engine", "propeller",
	"horizontal_tail", "vertical_tail", "gear", "canopy"
]
## CR-09c: an imported node may name its crash section explicitly: glTF extras "openrc_section" (set in Blender as a
## custom property) or meta "crash_section" (set by a builder or the section splitter). "core" keeps it with the body.
const SECTION_EXTRAS_KEY := "openrc_section"
const SECTION_META := "crash_section"
const CORE_SECTION := "core"

const GROUP_DELAYS_S := {
	"wing_left": 0.00,
	"wing_right": 0.00,
	"wing_center": 0.00,
	"engine": 0.00,
	"propeller": 0.04,
	"horizontal_tail": 0.12,
	"vertical_tail": 0.12,
	"gear": 0.20,
	"canopy": 0.28
}
const GROUP_MASS_WEIGHTS := {
	"core": 0.42,
	"wing_left": 0.15,
	"wing_right": 0.15,
	"wing_center": 0.25,
	"engine": 0.08,
	"propeller": 0.025,
	"horizontal_tail": 0.07,
	"vertical_tail": 0.045,
	"gear": 0.05,
	"canopy": 0.02
}

var _twin: Node3D
var _ground: StaticBody3D
var _bodies: Array[RigidBody3D] = []
var _shape_nodes: Array[CollisionShape3D] = []
var _shadows: Array[MeshInstance3D] = []
var _shadow_materials: Array[ShaderMaterial] = []
var _shadow_shader: Shader
var _shadow_mesh: PlaneMesh
var _groups: Array[Dictionary] = []
var _prepared_groups: Array[Dictionary] = []
var _member_records: Array[Dictionary] = []
var _selected_roots: Array[Node] = []
var _whole_bounds := AABB()
var _core_bounds := AABB()
var _core_body: RigidBody3D
var _started := false
var _paused := false
var _elapsed_s := 0.0
var _active_body_count := 0
var _secondary_count := 0
var _secondary_lockout_s := 0.0
var _max_speed_seen_mps := 0.0
var _scatter_energy_j := 0.0
var _normal_impact_energy_estimate_j := 0.0
var _scatter_energy_fraction := 0.0
var _energy_estimate_source := "unavailable"
var _last_class_level := -1
var _last_mass_kg := 0.0
var _last_group_weight_total := 0.0
var _last_component_hint := ""
var _last_cg_model := Vector3.ZERO
var _c3_contact_exposure_index_j := 0.0
var _c3_contact_release_pending := false
var _run_generation := 0
var _release_kinds: Array = []
var _contact_model := Vector3.ZERO
var _has_contact := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_ensure_pool()


## Make a hidden, shared-mesh copy and precompute natural separation groups before flight.
func prepare(airplane: Node3D) -> bool:
	if airplane == null or not is_instance_valid(airplane):
		push_error("Wreck.prepare: expected a valid airplane Node3D")
		return false
	reset()
	_clear_prepared_copy()
	_ensure_pool()
	_twin = airplane.duplicate() as Node3D
	if _twin == null:
		push_error("Wreck.prepare: airplane could not be duplicated")
		return false
	_twin.name = "WreckAirframeCopy"
	_twin.transform = Transform3D.IDENTITY
	_twin.visible = false
	add_child(_twin)
	# CR-09c: merged imported meshes with a generated section map become real section meshes in the twin only.
	var split := SectionSplitter.apply(_twin)
	if not bool(split.ok):
		push_warning("Wreck.prepare: crash section map ignored: %s" % "; ".join(split.errors))
	_groups.clear()
	_member_records.clear()
	_selected_roots.clear()
	_collect_fragment_groups(_twin)
	_build_group_records()
	_prepared_groups = _copy_groups(_groups)
	_configure_pool_shapes()
	return true


## Start a presentation-only breakup at the supplied rendered aircraft pose.
func start(pose: Transform3D, velocity: Vector3, angular_velocity: Vector3, severity: Dictionary) -> void:
	if _twin == null:
		push_error("Wreck.start: call prepare(airplane) before start")
		return
	if _started:
		reset()
	_run_generation += 1
	_c3_contact_release_pending = false
	_c3_contact_exposure_index_j = 0.0
	# Use a fresh runtime copy of the prepared section descriptors on every crash.
	_groups = _copy_groups(_prepared_groups)
	_started = false
	_paused = false
	_elapsed_s = 0.0
	_active_body_count = 0
	_secondary_count = 0
	_secondary_lockout_s = 0.0
	_max_speed_seen_mps = 0.0
	_scatter_energy_j = 0.0
	_normal_impact_energy_estimate_j = 0.0
	_scatter_energy_fraction = 0.0
	_energy_estimate_source = "unavailable"
	_rng.seed = int(severity.get("seed", 0x4D595DF4))
	var safe_velocity := _clamp_vector(_finite_vector(velocity), MAX_INPUT_SPEED_MPS)
	var safe_angular := _clamp_vector(_finite_vector(angular_velocity), MAX_ANGULAR_SPEED_RAD_S)
	var cg_model: Vector3 = _finite_vector(severity.get("cg_model", Vector3.ZERO))
	var class_level := _class_level(severity)
	var total_mass := clampf(_finite_number(severity.get("mass_kg", severity.get("aircraft_mass_kg", 2.5)), 2.5), 0.1, 80.0)
	var severity_scale := clampf(_finite_number(severity.get("scale", severity.get("severity", 1.0)), 1.0), 0.0, 4.0)
	var scatter_budget := _scatter_energy_budget(severity, total_mass, safe_velocity)
	if class_level < 3:
		scatter_budget = 0.0
	var component_hint := _component_description(severity).to_lower()
	_release_kinds = _release_kinds_for(class_level, component_hint)
	_has_contact = severity.get("contact_point_world") is Vector3 and _finite_vector(severity.contact_point_world) == severity.contact_point_world
	_contact_model = pose.affine_inverse() * Vector3(severity.contact_point_world) if _has_contact else Vector3.ZERO
	_last_class_level = class_level
	_last_mass_kg = total_mass
	_last_component_hint = component_hint
	_last_cg_model = cg_model
	var total_weight := _group_weight("core")
	_groups[0].undetached_weight = 0.0
	for i in range(1, _groups.size()):
		var group: Dictionary = _groups[i]
		total_weight += _group_weight(String(group.kind))
		group.detached = _should_detach(String(group.kind), class_level, component_hint)
		group.activated = false
		if not bool(group.detached):
			_groups[0].undetached_weight += _group_weight(String(group.kind))
		_groups[i] = group
	_last_group_weight_total = total_weight
	var core_bounds: AABB = _whole_bounds if class_level < 3 else _core_bounds
	_groups[0].bounds = core_bounds
	_groups[0].center = core_bounds.get_center()
	_set_shape_bounds(0, core_bounds)
	var core_center: Vector3 = _groups[0].center
	_core_body = _bodies[0]
	_core_body.mass = maxf(total_mass * (_group_weight("core") + float(_groups[0].undetached_weight)) / maxf(total_weight, 0.0001), 0.015)
	_core_body.global_transform = pose * Transform3D(Basis.IDENTITY, core_center)
	_twin.reparent(_core_body, false)
	_twin.transform = Transform3D(Basis.IDENTITY, -core_center)
	_twin.visible = true
	var detached_weight_total := 0.0
	for i in range(1, _groups.size()):
		if bool(_groups[i].get("detached", false)):
			detached_weight_total += _group_weight(String(_groups[i].kind))
	for i in range(1, _groups.size()):
		var group: Dictionary = _groups[i]
		var body: RigidBody3D = _bodies[i]
		if not bool(group.detached):
			body.freeze = true
			body.visible = false
			body.collision_layer = 0
			body.collision_mask = 0
			continue
		var mass_share: float = _group_weight(String(group.kind)) / maxf(total_weight, 0.0001)
		body.mass = maxf(total_mass * mass_share, 0.015)
		group.mass = body.mass
		group.due_s = float(GROUP_DELAYS_S.get(group.kind, 0.10))
		if _component_matches(String(group.kind), component_hint):
			group.due_s = 0.0
		elif _has_contact:
			# The break travels from the contact: nearer sections let go first.
			var distance: float = (Vector3(group.center) - _contact_model).length()
			group.due_s = clampf(distance / BREAK_PROPAGATION_MPS, MIN_PROPAGATION_DELAY_S, MAX_PROPAGATION_DELAY_S)
		elif class_level == 3:
			group.due_s = 0.14 if String(group.kind).begins_with("wing_") else 0.32
		group.base_velocity = safe_velocity
		group.base_angular_velocity = safe_angular
		var detached_share := _group_weight(String(group.kind)) / maxf(detached_weight_total, 0.0001) if detached_weight_total > 0.0 else 0.0
		group.scatter_energy_j = scatter_budget * detached_share
		group.severity_scale = severity_scale
		_groups[i] = group
		body.freeze = true
		body.visible = false
		body.collision_layer = 0
		body.collision_mask = 0
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	# Low classes keep all sections attached to the core body. These mass weights are presentation estimates.
	_groups[0].mass = _core_body.mass
	_groups[0].base_velocity = safe_velocity
	_groups[0].base_angular_velocity = safe_angular
	# Keep the intact core free of artificial separation impulses. Delayed parts inherit
	# its physical point velocity, then consume only their share of the one scatter budget.
	_groups[0].scatter_energy_j = 0.0
	_groups[0].severity_scale = severity_scale
	_apply_launch(_core_body, _groups[0], pose, safe_velocity, safe_angular, cg_model, true)
	_started = true
	for i in range(1, _groups.size()):
		if bool(_groups[i].get("detached", false)) and float(_groups[i].due_s) <= 0.0:
			_activate_group(i)


## Freeze visual bodies and delayed release timers while the sim pause menu is open.
func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	for body in _bodies:
		if body == null or not body.visible:
			continue
		if paused:
			body.set_meta("wreck_pause_linear", body.linear_velocity)
			body.set_meta("wreck_pause_angular", body.angular_velocity)
			body.set_meta("wreck_pause_sleeping", body.sleeping)
			body.freeze = true
		else:
			var was_sleeping: bool = bool(body.get_meta("wreck_pause_sleeping", false))
			body.freeze = false
			body.linear_velocity = _finite_vector(body.get_meta("wreck_pause_linear", Vector3.ZERO))
			body.angular_velocity = _finite_vector(body.get_meta("wreck_pause_angular", Vector3.ZERO))
			body.sleeping = was_sleeping
	_queue_c3_contact_release()


## Return the mesh twin and pooled bodies to a clean pre-crash state.
func reset() -> void:
	_run_generation += 1
	_c3_contact_release_pending = false
	_c3_contact_exposure_index_j = 0.0
	if _bodies.is_empty():
		_started = false
		_paused = false
		_last_group_weight_total = 0.0
		return
	for body in _bodies:
		if body == null:
			continue
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.sleeping = true
		body.visible = false
		body.collision_layer = 0
		body.collision_mask = 0
		body.global_transform = Transform3D.IDENTITY
		var body_index := _bodies.find(body)
		if body_index >= 0 and body_index < _shadows.size():
			_shadows[body_index].visible = false
	if _twin != null and is_instance_valid(_twin):
		_member_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.parent.get_instance_id() == b.parent.get_instance_id():
				return int(a.index) < int(b.index)
			return int(a.parent.get_instance_id()) < int(b.parent.get_instance_id())
		)
		for record: Dictionary in _member_records:
			var node: Node3D = record.node
			var original_parent: Node = record.parent
			if not is_instance_valid(node) or not is_instance_valid(original_parent):
				continue
			if node.get_parent() != original_parent:
				node.reparent(original_parent, false)
			node.transform = record.transform
			original_parent.move_child(node, mini(int(record.index), original_parent.get_child_count() - 1))
		if _twin.get_parent() != self:
			_twin.reparent(self, false)
		_twin.transform = Transform3D.IDENTITY
		_twin.visible = false
	_started = false
	_paused = false
	_elapsed_s = 0.0
	_active_body_count = 0
	_secondary_count = 0
	_secondary_lockout_s = 0.0
	_max_speed_seen_mps = 0.0
	_scatter_energy_j = 0.0
	_normal_impact_energy_estimate_j = 0.0
	_scatter_energy_fraction = 0.0
	_energy_estimate_source = "unavailable"
	if not _prepared_groups.is_empty():
		_groups = _copy_groups(_prepared_groups)
	_core_body = null
	_last_class_level = -1
	_last_mass_kg = 0.0
	_last_group_weight_total = 0.0
	_last_component_hint = ""
	_last_cg_model = Vector3.ZERO
	_release_kinds = []
	_has_contact = false
	_contact_model = Vector3.ZERO


func get_stats() -> Dictionary:
	var sleeping := 0
	for body in _bodies:
		if body.visible and body.sleeping:
			sleeping += 1
	return {
		"prepared": _twin != null,
		"started": _started,
		"paused": _paused,
		"pool_size": _bodies.size(),
		"contact_shadow_count": _shadows.size(),
		"active_body_count": _active_body_count,
		"detached_group_count": _detached_group_count(),
		"sleeping_body_count": sleeping,
		"fragment_groups": _group_names(),
		"elapsed_s": _elapsed_s,
		"secondary_impacts": _secondary_count,
		"max_speed_seen_mps": _max_speed_seen_mps,
		"scatter_energy_j": _scatter_energy_j,
		"normal_impact_energy_estimate_j": _normal_impact_energy_estimate_j,
		"scatter_energy_fraction": _scatter_energy_fraction,
		"energy_estimate_source": _energy_estimate_source,
		"secondary_impact_strength_unit": "J",
		"c3_contact_exposure_index_j": _c3_contact_exposure_index_j,
		"c3_contact_exposure_unit": "provisional relative kinetic-energy index J",
		"c3_contact_exposure_kind": "cosmetic post-crash exposure index; not measured dissipated energy",
		"c3_contact_release_thresholds_j": C3_CONTACT_RELEASE_THRESHOLDS_J.duplicate(),
		"c3_contact_release_pending": _c3_contact_release_pending,
		"class_level": _last_class_level,
		"mass_kg": _last_mass_kg,
		"component_hint": _last_component_hint,
		"release_kinds": _release_kinds.duplicate(),
		"contact_point_model": _contact_model if _has_contact else null,
		"cg_model": _last_cg_model
	}


func stats() -> Dictionary:
	return get_stats()


func active_body_count() -> int:
	return _active_body_count


func sleeping_body_count() -> int:
	return int(get_stats().sleeping_body_count)


func _process(delta: float) -> void:
	if not _started or _paused:
		return
	var dt := maxf(_finite_number(delta, 0.0), 0.0)
	_elapsed_s += dt
	_secondary_lockout_s = maxf(0.0, _secondary_lockout_s - dt)
	for i in range(1, _groups.size()):
		var group: Dictionary = _groups[i]
		if bool(group.get("detached", false)) and not bool(group.activated) and _elapsed_s >= float(group.due_s):
			_activate_group(i)
	for body in _bodies:
		if body.visible:
			var speed_sq := body.linear_velocity.length_squared()
			if is_finite(speed_sq):
				_max_speed_seen_mps = maxf(_max_speed_seen_mps, sqrt(speed_sq))
	for i in range(_bodies.size()):
		_update_contact_shadow(i)


func _ensure_pool() -> void:
	if _ground == null:
		_ground = StaticBody3D.new()
		_ground.name = "WreckGroundOnly"
		_ground.collision_layer = DEBRIS_LAYER
		_ground.collision_mask = 0
		var ground_shape := CollisionShape3D.new()
		ground_shape.name = "WreckPlaneShape"
		var plane := WorldBoundaryShape3D.new()
		plane.plane = Plane(Vector3.UP, 0.0)
		ground_shape.shape = plane
		_ground.add_child(ground_shape)
		add_child(_ground)
		_ground.global_transform = Transform3D.IDENTITY
	if _shadow_mesh == null:
		_shadow_mesh = PlaneMesh.new()
		_shadow_mesh.size = Vector2.ONE
	while _bodies.size() < MAX_BODIES:
		var body := RigidBody3D.new()
		body.name = "WreckPool_%02d" % _bodies.size()
		body.mass = 0.1
		body.gravity_scale = 1.0
		body.linear_damp = 1.5
		body.angular_damp = 2.0
		body.can_sleep = true
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 4
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze = true
		body.visible = false
		var shape_node := CollisionShape3D.new()
		shape_node.name = "WreckBox"
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * MIN_BOX_EDGE_M
		shape_node.shape = box
		body.add_child(shape_node)
		body.body_entered.connect(_on_body_entered.bind(body))
		add_child(body)
		_bodies.append(body)
		_shape_nodes.append(shape_node)
		var shadow := MeshInstance3D.new()
		shadow.name = "WreckContactShadow_%02d" % _shadows.size()
		shadow.mesh = _shadow_mesh
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shadow.visible = false
		var shadow_material := _make_shadow_material()
		shadow.material_override = shadow_material
		add_child(shadow)
		_shadows.append(shadow)
		_shadow_materials.append(shadow_material)


func _clear_prepared_copy() -> void:
	if _twin != null and is_instance_valid(_twin):
		_twin.free()
	_twin = null
	_groups.clear()
	_prepared_groups.clear()
	_member_records.clear()
	_selected_roots.clear()


func _collect_fragment_groups(node: Node) -> void:
	var groups_by_kind: Dictionary = {}
	_collect_candidate_nodes(_twin, groups_by_kind)
	for kind in GROUP_ORDER:
		var members: Array = groups_by_kind.get(kind, [])
		if members.is_empty():
			continue
		var has_mesh := false
		for member: Node3D in members:
			if _subtree_has_mesh(member):
				has_mesh = true
				break
		if has_mesh:
			_groups.append({"kind": kind, "members": members})
			for member: Node3D in members:
				_selected_roots.append(member)
	# Preserve all remaining copied nodes and hinges inside the central airframe body.
	var whole := {"has": false, "bounds": AABB()}
	_collect_mesh_bounds(_twin, _twin, [], whole)
	_whole_bounds = whole.bounds if bool(whole.has) else AABB(Vector3(-0.15, -0.1, -0.4), Vector3(0.3, 0.2, 0.8))
	var core_bounds := {"has": false, "bounds": AABB()}
	_collect_mesh_bounds(_twin, _twin, _selected_roots, core_bounds)
	if not bool(core_bounds.has):
		core_bounds.bounds = AABB(Vector3(-0.15, -0.1, -0.4), Vector3(0.3, 0.2, 0.8))
	_core_bounds = core_bounds.bounds
	var core_center: Vector3 = core_bounds.bounds.get_center()
	var records: Array[Dictionary] = [{
		"kind": "core",
		"members": [],
		"bounds": core_bounds.bounds,
		"center": core_center,
		"due_s": 0.0,
		"activated": false,
	}]
	for group: Dictionary in _groups:
		var aggregate := {"has": false, "bounds": AABB()}
		for member: Node3D in group.members:
			_collect_mesh_bounds(member, _twin, [], aggregate)
		if not bool(aggregate.has):
			continue
		var bounds: AABB = aggregate.bounds
		records.append({
			"kind": group.kind,
			"members": group.members,
			"bounds": bounds,
			"center": bounds.get_center(),
			"due_s": float(GROUP_DELAYS_S.get(group.kind, 0.1)),
			"activated": false,
		})
	_groups = records
	_member_records.clear()
	for group: Dictionary in _groups:
		for member: Node3D in group.members:
			_member_records.append({
				"node": member,
				"parent": member.get_parent(),
				"index": member.get_index(),
				"transform": member.transform,
			})


func _collect_candidate_nodes(node: Node, groups_by_kind: Dictionary) -> void:
	for child in node.get_children():
		if child is Node3D:
			var part_kind := _section_of(child)
			if not part_kind.is_empty() and part_kind != CORE_SECTION:
				if not groups_by_kind.has(part_kind):
					groups_by_kind[part_kind] = []
				groups_by_kind[part_kind].append(child)
				# A selected model subtree already contains its wing, tail, propeller or gear meshes.
				continue
		_collect_candidate_nodes(child, groups_by_kind)


## CR-09c: the crash section of a twin node: glTF extras, then builder/splitter meta, then the name rules.
## An unknown explicit name is reported once and ignored (the name rules still apply).
func _section_of(node: Node) -> String:
	var explicit := ""
	var extras: Variant = node.get_meta("extras") if node.has_meta("extras") else null
	if extras is Dictionary and (extras as Dictionary).has(SECTION_EXTRAS_KEY):
		explicit = String(extras[SECTION_EXTRAS_KEY])
	elif node.has_meta(SECTION_META):
		explicit = String(node.get_meta(SECTION_META))
	if not explicit.is_empty():
		if explicit == CORE_SECTION or GROUP_ORDER.has(explicit):
			return explicit
		push_warning("Wreck: unknown crash section '%s' on %s" % [explicit, node.name])
	return _fragment_kind(String(node.name))


func _fragment_kind(raw_name: String) -> String:
	var name := raw_name.to_lower()
	if name == "wing_frame_left" or name == "wing_left" or name.begins_with("wing_left_") or name == "aileron_frame_left":
		return "wing_left"
	if name == "wing_frame_right" or name == "wing_right" or name.begins_with("wing_right_") or name == "aileron_frame_right":
		return "wing_right"
	if name == "wing" or name == "wing_frame":
		return "wing_center"
	if name == "tail_frame" or name == "stab" or name.begins_with("stab_") or name == "elevator_hinge":
		return "horizontal_tail"
	if name == "fin_frame" or name == "fin" or name == "rudder_hinge" or name == "ventral_fin" or name == "rudder":
		return "vertical_tail"
	if name == "engine_assembly" or name == "engine" or name == "motor_assembly":
		return "engine"
	if name == "propeller":
		return "propeller"
	if name == "canopy" or name == "canopy_frame":
		return "canopy"
	if name.begins_with("main_gear") or name.begins_with("nose_gear") or name.begins_with("landing_gear") or name.begins_with("wheel_") or name == "tail_skid":
		return "gear"
	return ""


func _build_group_records() -> void:
	# Group construction currently occurs while preparing the hidden twin; keep a small defensive cap.
	if _groups.size() > MAX_BODIES - 1:
		_groups.resize(MAX_BODIES - 1)


func _configure_pool_shapes() -> void:
	for i in range(_bodies.size()):
		var body := _bodies[i]
		body.freeze = true
		body.visible = false
		body.collision_layer = 0
		body.collision_mask = 0
		_shadows[i].visible = false
		if i < _groups.size():
			var bounds: AABB = _groups[i].bounds
			_set_shape_bounds(i, bounds)
		else:
			_set_shape_bounds(i, AABB(Vector3.ZERO, Vector3.ONE * MIN_BOX_EDGE_M))
		_shape_nodes[i].position = Vector3.ZERO


func _activate_group(index: int) -> void:
	if index <= 0 or index >= _groups.size() or _core_body == null:
		return
	var group: Dictionary = _groups[index]
	if bool(group.activated):
		return
	var body: RigidBody3D = _bodies[index]
	var aircraft_pose: Transform3D = _core_body.global_transform * _twin.transform
	var center: Vector3 = group.center
	body.global_transform = aircraft_pose * Transform3D(Basis.IDENTITY, center)
	for member: Node3D in group.members:
		if is_instance_valid(member):
			member.reparent(body, true)
	var local_offset: Vector3 = aircraft_pose.basis * (center - _groups[0].center)
	var inherited_velocity := _core_body.linear_velocity + _core_body.angular_velocity.cross(local_offset)
	var inherited_angular := _core_body.angular_velocity
	_apply_launch(body, group, aircraft_pose, inherited_velocity, inherited_angular, Vector3.ZERO, false)


func _apply_launch(body: RigidBody3D, group: Dictionary, aircraft_pose: Transform3D, inherited_velocity: Vector3, inherited_angular: Vector3, cg_model: Vector3, is_core: bool) -> void:
	body.visible = true
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = DEBRIS_LAYER
	body.freeze = _paused
	body.sleeping = false
	body.can_sleep = true
	body.linear_damp = 1.5
	body.angular_damp = 2.0
	var center: Vector3 = group.center
	var world_offset: Vector3 = aircraft_pose.basis * (center - cg_model)
	var point_velocity: Vector3 = inherited_velocity + inherited_angular.cross(world_offset) if is_core else inherited_velocity
	body.linear_velocity = _clamp_vector(_finite_vector(point_velocity), MAX_POINT_SPEED_MPS)
	body.angular_velocity = _clamp_vector(_finite_vector(inherited_angular), MAX_ANGULAR_SPEED_RAD_S)
	body.set_meta("wreck_group_kind", group.kind)
	var scatter_energy := maxf(_finite_number(group.get("scatter_energy_j", 0.0), 0.0), 0.0)
	if scatter_energy > 0.0 and body.mass > 0.0:
		var outward: Vector3 = (aircraft_pose.basis * (center - _groups[0].center)).normalized()
		if outward.length_squared() < 0.01:
			outward = Vector3.UP
		var variation := Vector3(_rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.08, 0.20), _rng.randf_range(-0.18, 0.18))
		# CR-09b: debris trails along the horizontal momentum instead of bursting from the core centre.
		var travel := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
		var lead: Vector3 = outward
		if travel.length_squared() > 1.0:
			lead = travel.normalized() + outward * SCATTER_OUTWARD_SHARE + Vector3.UP * SCATTER_LIFT_SHARE
		var direction: Vector3 = (lead + aircraft_pose.basis * variation).normalized()
		if direction.length_squared() > 0.5:
			var before_velocity := body.linear_velocity
			var parallel_speed := before_velocity.dot(direction)
			var delta_speed := sqrt(parallel_speed * parallel_speed + 2.0 * scatter_energy / body.mass) - parallel_speed
			body.linear_velocity = _clamp_vector(before_velocity + direction * minf(delta_speed, MAX_SCATTER_SPEED_MPS), MAX_POINT_SPEED_MPS)
			var actual_delta_energy := 0.5 * body.mass * (body.linear_velocity.length_squared() - before_velocity.length_squared())
			_scatter_energy_j += maxf(actual_delta_energy, 0.0)
	body.linear_velocity = _clamp_vector(body.linear_velocity, MAX_POINT_SPEED_MPS)
	_limit_ground_rebound(body)
	_max_speed_seen_mps = maxf(_max_speed_seen_mps, body.linear_velocity.length())
	if not bool(group.get("activated", false)):
		group.activated = true
		_active_body_count += 1
	_groups[0 if is_core else _group_index_for_body(body)] = group


func _group_index_for_body(body: RigidBody3D) -> int:
	return _bodies.find(body)


func _group_weight(kind: String) -> float:
	return float(GROUP_MASS_WEIGHTS.get(kind, 0.03))


func _scatter_energy_budget(severity: Dictionary, total_mass: float, impact_velocity: Vector3) -> float:
	var explicit_energy := -1.0
	var explicit_source := ""
	for key in ["dissipated_normal_energy_j", "normal_impact_energy_j", "normal_energy_j"]:
		if severity.has(key):
			explicit_energy = _finite_number(severity[key], -1.0)
			if explicit_energy >= 0.0:
				explicit_source = key
				break
	var normal_energy := explicit_energy
	if normal_energy < 0.0:
		var normal: Vector3 = _finite_vector(severity.get("contact_normal", Vector3.UP))
		if normal.length_squared() < 1e-6:
			normal = Vector3.UP
		else:
			normal = normal.normalized()
		var supplied_speed := _finite_number(severity.get("normal_speed_mps", -1.0), -1.0)
		var normal_speed := supplied_speed if supplied_speed >= 0.0 else absf(impact_velocity.dot(normal))
		normal_energy = 0.5 * total_mass * normal_speed * normal_speed
		_energy_estimate_source = "normal_speed_mps" if supplied_speed >= 0.0 else "cg_velocity_projection"
	else:
		_energy_estimate_source = explicit_source
	_normal_impact_energy_estimate_j = clampf(normal_energy, 0.0, 1_000_000.0)
	var requested_fraction := _finite_number(severity.get("scatter_energy_fraction", MAX_SCATTER_ENERGY_FRACTION), MAX_SCATTER_ENERGY_FRACTION)
	_scatter_energy_fraction = clampf(requested_fraction, 0.0, MAX_SCATTER_ENERGY_FRACTION)
	return minf(_normal_impact_energy_estimate_j * _scatter_energy_fraction, MAX_SCATTER_ENERGY_J)


func _make_shadow_material() -> ShaderMaterial:
	if _shadow_shader == null:
		_shadow_shader = Shader.new()
		_shadow_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float opacity : hint_range(0.0, 0.35) = 0.0;
void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float soft_edge = 1.0 - smoothstep(0.16, 1.0, radius);
	ALBEDO = vec3(0.025, 0.031, 0.04);
	ALPHA = soft_edge * opacity;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _shadow_shader
	material.set_shader_parameter("opacity", 0.0)
	return material


func _update_contact_shadow(index: int) -> void:
	if index < 0 or index >= _bodies.size() or index >= _shadows.size():
		return
	var body := _bodies[index]
	var shadow := _shadows[index]
	if not body.visible:
		shadow.visible = false
		return
	var shape := _shape_nodes[index].shape as BoxShape3D
	var half := shape.size * 0.5
	var basis := body.global_transform.basis
	var horizontal_x := absf(basis.x.x) * half.x + absf(basis.y.x) * half.y + absf(basis.z.x) * half.z
	var horizontal_z := absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z
	var vertical_extent := absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
	var height := maxf(body.global_position.y - vertical_extent, 0.0)
	var fade := clampf(1.0 - height / SHADOW_FADE_HEIGHT_M, 0.0, 1.0)
	var shrink := lerpf(1.0, 0.35, clampf(height / SHADOW_FADE_HEIGHT_M, 0.0, 1.0))
	var alpha := 0.22 * fade
	shadow.visible = alpha > 0.002
	shadow.global_transform = Transform3D(
		Basis.IDENTITY.scaled(Vector3(maxf(horizontal_x * 2.0 + 0.35, 0.65) * shrink, 1.0, maxf(horizontal_z * 2.0 + 0.35, 0.65) * shrink)),
		Vector3(body.global_position.x, 0.012, body.global_position.z)
	)
	_shadow_materials[index].set_shader_parameter("opacity", alpha)


func _group_names() -> Array[String]:
	var names: Array[String] = []
	for group: Dictionary in _groups:
		names.append(String(group.kind))
	return names


func _detached_group_count() -> int:
	var count := 0
	for i in range(1, _groups.size()):
		if bool(_groups[i].get("detached", false)):
			count += 1
	return count


func _class_level(severity: Dictionary) -> int:
	var raw: Variant = severity.get("class", severity.get("severity_class", "C3"))
	if raw is int or raw is float:
		return clampi(int(raw), 0, 4)
	var label := String(raw).to_upper().strip_edges()
	if label.begins_with("C"):
		label = label.substr(1)
	return clampi(int(label) if label.is_valid_int() else 3, 0, 4)


func _component_description(severity: Dictionary) -> String:
	var description := String(severity.get("component", ""))
	var estimated: Variant = severity.get("estimated_components", [])
	if estimated is Array:
		for item in estimated:
			description += " " + String(item)
	elif estimated is Dictionary:
		for key in estimated:
			description += " " + String(key) + " " + String(estimated[key])
	return description


func _should_detach(kind: String, class_level: int, component_hint: String) -> bool:
	if class_level < 2:
		return false
	if class_level >= 4:
		return true
	if class_level == 2:
		return _release_kinds.has(kind)
	if not _release_kinds.is_empty():
		return _release_kinds.has(kind)
	if _component_matches(kind, component_hint):
		return true
	return kind in ["wing_left", "wing_right", "wing_center", "horizontal_tail", "vertical_tail"]


## CR-09b: sections a named struck component releases. C2 loses only the small struck part; C3 the struck
## section and its usual load-path neighbours. An empty C3 list keeps the legacy wings-and-tails set (fuselage,
## belly or unnamed hits). Presentation estimates of typical RC outcomes, not material limits.
func _release_kinds_for(class_level: int, hint: String) -> Array:
	var h := hint.replace("-", "_").replace(" ", "_")
	var kinds: Array = []
	if class_level == 2:
		if h.contains("spinner") or h.contains("propeller") or h.contains("nose"):
			kinds = ["propeller"]
		elif h.contains("stab") or h.contains("elevator"):
			kinds = ["horizontal_tail"]
		elif h.contains("fin") or h.contains("rudder"):
			kinds = ["vertical_tail"]
		elif h.contains("canopy") or h.contains("hatch"):
			kinds = ["canopy"]
		elif h.contains("gear") or h.contains("wheel"):
			kinds = ["gear"]
	elif class_level == 3:
		if h.contains("left_wing") or h.contains("wing_left") or h.contains("left_tip"):
			kinds = ["wing_left"]
		elif h.contains("right_wing") or h.contains("wing_right") or h.contains("right_tip"):
			kinds = ["wing_right"]
		elif h.contains("spinner") or h.contains("propeller") or h.contains("nose") or h.contains("engine"):
			kinds = ["propeller", "engine", "canopy"]
		elif h.contains("stab") or h.contains("fin") or h.contains("tail") or h.contains("rudder") or h.contains("elevator"):
			kinds = ["horizontal_tail", "vertical_tail"]
		elif h.contains("canopy"):
			kinds = ["canopy", "vertical_tail"]
		elif h.contains("gear") or h.contains("wheel"):
			kinds = ["gear", "propeller"]
	# CR-09c1: release only sections this model has. Without split wing halves the single wing section stands in;
	# a C3 set left empty falls back to the legacy wings-and-tails set so a hit never releases nothing.
	var present: Array = []
	for group: Dictionary in _prepared_groups:
		present.append(String(group.get("kind", "")))
	var available: Array = []
	for kind in kinds:
		var resolved := String(kind)
		if resolved.begins_with("wing_") and not present.has(resolved) and present.has("wing_center"):
			resolved = "wing_center"
		if present.has(resolved) and not available.has(resolved):
			available.append(resolved)
	return available


func _component_matches(kind: String, component_hint: String) -> bool:
	if component_hint.is_empty():
		return false
	var normalized := component_hint.replace("-", "_").replace(" ", "_")
	if kind == "wing_left":
		return normalized.contains("left_wing") or normalized.contains("wing_left") or normalized.contains("left_tip")
	if kind == "wing_right":
		return normalized.contains("right_wing") or normalized.contains("wing_right") or normalized.contains("right_tip")
	if kind == "wing_center":
		return normalized.contains("wing")
	if kind == "horizontal_tail":
		return normalized.contains("tail") or normalized.contains("elevator") or normalized.contains("stab")
	if kind == "vertical_tail":
		return normalized.contains("fin") or normalized.contains("rudder") or normalized.contains("tail")
	if kind == "gear":
		return normalized.contains("gear") or normalized.contains("wheel")
	if kind == "propeller":
		return normalized.contains("propeller") or normalized.contains("spinner")
	return normalized.contains(kind)


func _copy_groups(source: Array[Dictionary]) -> Array[Dictionary]:
	var copies: Array[Dictionary] = []
	for group: Dictionary in source:
		var copy := group.duplicate(false)
		if copy.has("members"):
			copy["members"] = copy["members"].duplicate()
		copies.append(copy)
	return copies


func _set_shape_bounds(index: int, bounds: AABB) -> void:
	if index < 0 or index >= _shape_nodes.size():
		return
	var shape := _shape_nodes[index].shape as BoxShape3D
	shape.size = Vector3(maxf(bounds.size.x, MIN_BOX_EDGE_M), maxf(bounds.size.y, MIN_BOX_EDGE_M), maxf(bounds.size.z, MIN_BOX_EDGE_M))


func _limit_ground_rebound(body: RigidBody3D) -> void:
	var body_index := _bodies.find(body)
	if body_index < 0:
		return
	var shape := _shape_nodes[body_index].shape as BoxShape3D
	var basis := body.global_transform.basis
	var half := shape.size * 0.5
	var vertical_extent := absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
	var clear_y := vertical_extent + 0.015
	if body.global_position.y < clear_y:
		body.global_position += Vector3.UP * minf(clear_y - body.global_position.y, 0.35)
	if body.global_position.y <= vertical_extent + 0.15 and body.linear_velocity.y < 0.0:
		body.linear_velocity.y = minf(-body.linear_velocity.y * 0.12, 5.0)


func _on_body_entered(other: Node, fragment: RigidBody3D) -> void:
	if not _started or _paused or _secondary_lockout_s > 0.0 or not is_instance_valid(fragment):
		return
	if other == null or (other != _ground and not _is_pool_body(other)):
		return
	var relative_speed := fragment.linear_velocity.length()
	if other is RigidBody3D:
		relative_speed = (fragment.linear_velocity - other.linear_velocity).length()
	var energy := clampf(0.5 * fragment.mass * relative_speed * relative_speed, 0.0, 250.0)
	if energy < 0.35:
		return
	_secondary_lockout_s = 0.08
	_secondary_count += 1
	if fragment == _core_body:
		_record_c3_contact_exposure(energy)
	secondary_impact.emit(fragment.global_position, energy)


func _record_c3_contact_exposure(contact_energy_j: float) -> void:
	if not _started or _paused or _last_class_level != 3:
		return
	var safe_energy := clampf(_finite_number(contact_energy_j, 0.0), 0.0, 250.0)
	_c3_contact_exposure_index_j = minf(
		_c3_contact_exposure_index_j + safe_energy,
		MAX_C3_CONTACT_EXPOSURE_INDEX_J
	)
	_queue_c3_contact_release()


func _queue_c3_contact_release() -> void:
	if _c3_contact_release_pending or not _started or _paused or _last_class_level != 3:
		return
	var index := _next_c3_contact_release_index()
	if index < 1:
		return
	var kind := String(_groups[index].kind)
	var threshold := float(C3_CONTACT_RELEASE_THRESHOLDS_J.get(kind, INF))
	if _c3_contact_exposure_index_j + 0.0001 < threshold:
		return
	_c3_contact_release_pending = true
	# body_entered is raised while the physics server may be flushing; defer tree changes.
	call_deferred("_release_pending_c3_contact_group", _run_generation)


func _release_pending_c3_contact_group(generation: int) -> void:
	if generation != _run_generation:
		return
	_c3_contact_release_pending = false
	if not _started or _paused or _last_class_level != 3 or _core_body == null:
		return
	var index := _next_c3_contact_release_index()
	if index < 1:
		return
	var group: Dictionary = _groups[index]
	var kind := String(group.kind)
	var threshold := float(C3_CONTACT_RELEASE_THRESHOLDS_J.get(kind, INF))
	if _c3_contact_exposure_index_j + 0.0001 < threshold:
		return
	var group_weight := _group_weight(kind)
	var release_mass := _last_mass_kg * group_weight / maxf(_last_group_weight_total, 0.0001)
	if not is_finite(release_mass) or release_mass <= 0.0 or release_mass >= _core_body.mass:
		return
	# Transfer the group's estimated mass out of the core; no new scatter impulse is added.
	_core_body.mass -= release_mass
	var core_group: Dictionary = _groups[0]
	core_group.mass = _core_body.mass
	core_group.undetached_weight = maxf(float(core_group.get("undetached_weight", 0.0)) - group_weight, 0.0)
	_groups[0] = core_group
	group.detached = true
	group.activated = false
	group.due_s = 0.0
	group.mass = release_mass
	group.scatter_energy_j = 0.0
	group.severity_scale = 0.0
	_groups[index] = group
	_bodies[index].mass = release_mass
	_activate_group(index)


func _next_c3_contact_release_index() -> int:
	for kind in C3_CONTACT_RELEASE_ORDER:
		for i in range(1, _groups.size()):
			var group: Dictionary = _groups[i]
			if String(group.kind) != String(kind):
				continue
			if bool(group.get("detached", false)) or bool(group.get("activated", false)):
				break
			return i
	return -1


func _is_pool_body(candidate: Node) -> bool:
	for body in _bodies:
		if body == candidate:
			return true
	return false


func _subtree_has_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	for child in node.get_children():
		if _subtree_has_mesh(child):
			return true
	return false


func _collect_mesh_bounds(node: Node, root: Node3D, excluded: Array, aggregate: Dictionary) -> void:
	if excluded.has(node):
		return
	if node is MeshInstance3D and node.mesh != null and node.visible:
		var local_bounds: AABB = node.get_aabb()
		var relative: Transform3D = _relative_transform_to_root(node, root)
		for corner_index in range(8):
			var corner := Vector3(
				local_bounds.position.x + (local_bounds.size.x if (corner_index & 1) != 0 else 0.0),
				local_bounds.position.y + (local_bounds.size.y if (corner_index & 2) != 0 else 0.0),
				local_bounds.position.z + (local_bounds.size.z if (corner_index & 4) != 0 else 0.0)
			)
			var point := relative * corner
			if not bool(aggregate.has):
				aggregate.bounds = AABB(point, Vector3.ZERO)
				aggregate.has = true
			else:
				aggregate.bounds = aggregate.bounds.expand(point)
	for child in node.get_children():
		_collect_mesh_bounds(child, root, excluded, aggregate)


func _relative_transform_to_root(node: Node, root: Node3D) -> Transform3D:
	var path: Array[Transform3D] = []
	var cursor: Node = node
	while cursor != null and cursor != root:
		if cursor is Node3D:
			path.append((cursor as Node3D).transform)
		cursor = cursor.get_parent()
	if cursor != root:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	for i in range(path.size() - 1, -1, -1):
		result = result * path[i]
	return result


func _finite_number(value: Variant, fallback: float) -> float:
	if not (value is int or value is float):
		return fallback
	var number := float(value)
	return number if is_finite(number) else fallback


func _finite_vector(value: Vector3) -> Vector3:
	return value if is_finite(value.x) and is_finite(value.y) and is_finite(value.z) else Vector3.ZERO


func _clamp_vector(value: Vector3, maximum: float) -> Vector3:
	var safe := _finite_vector(value)
	var length_sq := safe.length_squared()
	if not is_finite(length_sq) or length_sq <= maximum * maximum:
		return safe
	return safe * (maximum / sqrt(length_sq))
