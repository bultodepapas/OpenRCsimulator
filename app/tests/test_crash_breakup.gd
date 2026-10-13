## CR-09b: proportional breakup. C2 loses only the small struck part, C3 the struck section and its load-path
## neighbours, sections release in order of distance from the contact, and debris trails along the momentum
## (docs/plans/crash-realism.md §3.3). Uses the Ugly Stik, whose twin has split wing halves.
extends SceneTree

const AirplaneBuilder = preload("res://render/airplane.gd")
const WreckController = preload("res://render/crash/wreck.gd")
const STIK := "jensen-das-ugly-stik-60"

var _checks := 0
var _failures := 0
var _wreck: Variant
var _pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane: Node3D = AirplaneBuilder.build(STIK).root
	root.add_child(airplane)
	await process_frame
	airplane.visible = false
	_wreck = WreckController.new()
	root.add_child(_wreck)
	await process_frame
	_wreck.set_process(false)
	_check("Stik twin prepares", _wreck.prepare(airplane))
	_class_two()
	_class_three()
	_ordering()
	_momentum_scatter()
	_wreck.reset()
	_check("reset clears the release set and contact", (_wreck.stats().release_kinds as Array).is_empty() and _wreck.stats().contact_point_model == null)
	_wreck.free()
	airplane.free()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _severity(class_label: String, component: String, contact: Variant = null) -> Dictionary:
	var s := {"class": class_label, "mass_kg": 2.89, "cg_model": Vector3.ZERO, "normal_speed_mps": 12.0, "component": component, "seed": 909}
	if contact != null:
		s["contact_point_world"] = contact
	return s


func _start(class_label: String, component: String, velocity := Vector3(0.0, -8.0, -10.0), contact: Variant = null) -> Array:
	_wreck.start(_pose, velocity, Vector3.ZERO, _severity(class_label, component, contact))
	var detached: Array = []
	for group: Dictionary in _wreck._groups.slice(1):
		# CR-09e: tail surfaces carried by a breaking tail boom leave the core too (on the boom's body).
		if bool(group.detached) or bool(group.get("carried", false)):
			detached.append(String(group.kind))
	detached.sort()
	return detached


func _sorted(kinds: Array) -> Array:
	var out := kinds.duplicate()
	out.sort()
	return out


# CR-09f: parts fixed to a released section ride with it (render/crash/wreck.gd CARRIERS), so they leave the core too.
const CHILDREN := {
	"wing_left": ["aileron_left"], "wing_right": ["aileron_right"], "wing_center": ["aileron_left", "aileron_right"],
	"horizontal_tail": ["elevator"], "vertical_tail": ["rudder"],
	"tail_boom": ["horizontal_tail", "vertical_tail", "elevator", "rudder"],
}


## Expected released kinds: the sections plus the parts attached to them, as far as this model has them.
func _expect(kinds: Array) -> Array:
	var out: Array = []
	for kind in kinds:
		for k in [kind] + CHILDREN.get(kind, []):
			if not out.has(k): out.append(k)
	return _sorted(_present(out))


func _present(kinds: Array) -> Array:
	var names: Array = _wreck.stats().fragment_groups
	return kinds.filter(func(kind: String) -> bool: return names.has(kind))


func _class_two() -> void:
	_check("C2 spinner hit releases only the propeller", _start("C2", "spinner") == ["propeller"])
	_check("C2 release adds no scatter energy", is_zero_approx(float(_wreck.stats().scatter_energy_j)))
	_check("C2 nose hit releases only the propeller", _start("C2", "nose") == ["propeller"])
	_check("C2 stab-tip hit releases only the tailplane", _start("C2", "left_stab_tip") == _expect(["horizontal_tail"]))
	_check("C2 fin-top hit releases only the fin", _start("C2", "fin_top") == _expect(["vertical_tail"]))
	_check("C2 wing-tip hit keeps the airframe together", _start("C2", "left_wing_tip").is_empty())
	_check("C2 belly hit keeps the airframe together", _start("C2", "belly").is_empty())
	_check("C2 geometric fuselage estimate keeps the airframe together", _start("C2", "fuselage").is_empty())
	_start("C2", "spinner")
	var total := 0.0
	for body: RigidBody3D in _wreck._bodies:
		if body.visible:
			total += body.mass
	_check("C2 release conserves the aircraft mass", absf(total - 2.89) < 0.001)


func _class_three() -> void:
	_check("C3 left wing-tip hit releases only the left wing", _start("C3", "left_wing_tip") == _expect(["wing_left"]))
	_check("C3 right wing-tip hit releases only the right wing", _start("C3", "right_wing_tip") == _expect(["wing_right"]))
	_check("C3 nose hit releases propeller, engine and canopy", _start("C3", "nose") == _sorted(_present(["propeller", "engine", "canopy"])))
	_check("C3 fin hit releases both tail sections and the boom they are glued to", _start("C3", "fin_top") == _expect(["horizontal_tail", "vertical_tail", "tail_boom"]))
	if _present(["tail_boom"]).size() == 1:
		var boom: Dictionary = _group("tail_boom")
		var carried: Array = _wreck._groups.slice(1).filter(func(g: Dictionary) -> bool: return bool(g.get("carried", false)))
		var tail_parts := _present(["horizontal_tail", "vertical_tail", "elevator", "rudder"]).size()
		_check("C3 tail hit: stab, fin and their hinged surfaces ride on the boom as one body", carried.size() == tail_parts and boom.detached
			and boom.members.size() > 1 and carried.all(func(g: Dictionary) -> bool: return not bool(g.detached)))
		_check("C3 tail hit: the boom carries its surfaces' mass", float(boom.mass) > 0.0 and boom.get("carried_keys", []).size() == tail_parts)
		_start("C4", "fin_top")
		_check("C4 breaks the surfaces off the boom", _wreck._groups.slice(1).all(func(g: Dictionary) -> bool: return not bool(g.get("carried", false))))
	_check("C3 inverted canopy hit releases canopy and fin", _start("C3", "canopy") == _expect(["canopy", "vertical_tail"]))
	var legacy := _expect(["wing_left", "wing_right", "wing_center", "horizontal_tail", "vertical_tail"])
	_check("C3 belly hit keeps the legacy wings-and-tails set", _start("C3", "belly") == legacy)
	var before: Array = _wreck.stats().release_kinds
	var got := _start("C3", "fin_top")
	_check("C3 records its release set (plus the parts riding with it)", _sorted(before) == [] and got == _expect(_wreck.stats().release_kinds))
	_check("C4 still releases every section", _start("C4", "left_wing_tip").size() == _wreck._groups.size() - 1)


func _ordering() -> void:
	var left_center: Vector3 = _group("wing_left").center
	var contact: Vector3 = _pose * (left_center + Vector3(-0.4, -0.05, 0.0))
	_start("C4", "", Vector3(0.0, -8.0, -10.0), contact)
	var model_contact: Vector3 = _wreck.stats().contact_point_model
	_check("the contact point is kept in model space", model_contact.is_equal_approx(_pose.affine_inverse() * contact))
	var ordered := true
	var previous_distance := -1.0
	var previous_due := -1.0
	var rows: Array = []
	for group: Dictionary in _wreck._groups.slice(1):
		rows.append([(Vector3(group.center) - model_contact).length(), float(group.due_s), String(group.kind)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for row: Array in rows:
		if row[1] + 1e-9 < previous_due:
			ordered = false
		previous_due = row[1]
	print("     release order: %s" % str(rows.map(func(r: Array) -> String: return "%s %.3f m %.3f s" % [r[2], r[0], r[1]])))
	_check("nearer sections never release later than farther ones", ordered)
	_check("the left wing releases before the right wing", float(_group("wing_left").due_s) < float(_group("wing_right").due_s))
	_check("release delays stay inside the propagation bounds", rows.all(func(r: Array) -> bool: return r[1] >= WreckController.MIN_PROPAGATION_DELAY_S and r[1] <= WreckController.MAX_PROPAGATION_DELAY_S))
	_start("C4", "")
	_check("without a contact point the legacy fixed delays remain", not _group("gear").is_empty() and is_equal_approx(float(_group("gear").due_s), float(WreckController.GROUP_DELAYS_S.gear)))


func _momentum_scatter() -> void:
	var incoming := Vector3(14.0, -9.0, 0.0) # sliding along +X
	_start("C4", "", incoming)
	_wreck._process(0.5)
	var along := 0.0
	var across := 0.0
	for i in range(1, _wreck._groups.size()):
		var body: RigidBody3D = _wreck._bodies[i]
		if not body.visible:
			continue
		var delta: Vector3 = body.linear_velocity - incoming
		along += delta.x
		across += Vector3(0.0, 0.0, delta.z).length()
	print("     scatter along %.2f, across %.2f m/s (summed)" % [along, across])
	_check("C4 scatter has energy to distribute", float(_wreck.stats().scatter_energy_j) > 0.0)
	_check("debris trails along the horizontal momentum", along > 0.0 and along > across)
	_check("scatter stays inside its bounded budget", float(_wreck.stats().scatter_energy_j) <= float(_wreck.stats().normal_impact_energy_estimate_j) * 0.12 + 0.001)


func _group(kind: String) -> Dictionary:
	for group: Dictionary in _wreck._groups:
		if String(group.kind) == kind:
			return group
	return {}
