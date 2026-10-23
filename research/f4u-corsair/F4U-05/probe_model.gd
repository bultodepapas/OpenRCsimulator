extends SceneTree
## F4U-05: build the Corsair visual model through the production registry and shared importer, then check what the
## session relies on: control senses, flap panels, propeller wrapper, sampled gear poses and oleo compression.
## godot --headless --path app --script <repo>/research/f4u-corsair/F4U-05/probe_model.gd
const Registry := preload("res://aircraft/model_registry.gd")
const Importer := preload("res://aircraft/imported_model.gd")
const Rig := preload("res://aircraft/retractable_model.gd")
const FAMILY := "f4u-corsair-250"
var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


## Model-frame position of the mesh vertex furthest along `direction`.
func _extreme(root: Node3D, mesh: MeshInstance3D, direction: Vector3) -> Vector3:
	var xf := Importer.relative(root, mesh)
	var best := Vector3.ZERO
	var score := -INF
	for surface in mesh.mesh.get_surface_count():
		for v: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var p := xf * v
			if p.dot(direction) > score:
				score = p.dot(direction)
				best = p
	return best


func _initialize() -> void:
	var described := Registry.describe(FAMILY)
	_check("registry accepts the checked-in manifest", described.ok, str(described.get("errors", [])))
	if not described.ok:
		_finish()
		return
	var manifest: Dictionary = described.manifest
	var built := Importer.build_checked(manifest)
	_check("shared importer builds the g1.3 scene", built.ok, str(built.errors))
	if not built.ok:
		_finish()
		return
	var model: Dictionary = built.model
	var root: Node3D = model.root
	var derived := Registry.validate_derived(manifest, model)
	_check("registry accepts the built model (hinges, rotor, gear, asset, crash sections)", derived.ok, str(derived.get("errors", [])))
	_check("identity metadata", root.name == "airplane" and root.get_meta("visual_revision") == "g1.3-c69151b3c96c" and model.aircraft_id == FAMILY)
	_check("ten control hinges bound", model.hinges.size() == 10, str(model.hinges.keys()))

	# Control senses in app degrees: aileron and elevator positive raise the trailing edge, rudder positive moves it right.
	var aft := Vector3(0, 0, 1)
	for role: String in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		var hinge: Dictionary = model.hinges[role]
		var surface: MeshInstance3D = hinge.node.get_child(0)
		var before := _extreme(root, surface, aft)
		Importer.apply_surfaces(model, {role: 10.0})
		var after := _extreme(root, surface, aft)
		Importer.apply_surfaces(model, {})
		var moved := after - before
		var sense := moved.x if role == "rudder" else moved.y
		_check("%s +10 app degrees moves the trailing edge %s" % [role, "right" if role == "rudder" else "up"], sense > 0.005, "%.4f m" % sense)
		_check("%s returns to rest" % role, _extreme(root, surface, aft).is_equal_approx(before))
	var panels := ["flap_left_1", "flap_left_2", "flap_left_3", "flap_right_1", "flap_right_2", "flap_right_3"]
	var rest_te := {}
	for key: String in panels:
		rest_te[key] = _extreme(root, model.hinges[key].node.get_child(0), aft)
	Importer.set_flaps(model, 30.0)
	var drops := []
	for key: String in panels:
		drops.append(rest_te[key].y - _extreme(root, model.hinges[key].node.get_child(0), aft).y)
	Importer.set_flaps(model, 0.0)
	_check("set_flaps(30) lowers all six slotted panels", drops.all(func(d: float) -> bool: return d > 0.01), str(drops))
	# Angle about the hinge: the local Y axis turns, the hinge's own X axis does not.
	var flap_angle := func() -> float: return rad_to_deg(model.hinges.flap_left_1.rest.y.angle_to(model.hinges.flap_left_1.node.basis.y))
	Importer.set_flaps(model, 30.0)
	var at_30: float = flap_angle.call()
	Importer.set_flaps(model, 80.0)
	var at_80: float = flap_angle.call()
	Importer.set_flaps(model, 0.0)
	_check("flap hinge turns 30 deg for a 30 deg command", absf(at_30 - 30.0) < 0.01, "%.3f deg" % at_30)
	_check("flap command clamps at the author's 50 deg envelope", absf(at_80 - 50.0) < 0.01, "%.3f deg for 80" % at_80)

	# Propeller: public wrapper above the spin node; the rotor mesh spins about the thrust axis.
	var propeller: Node3D = model.propeller
	var spin: Node3D = root.find_child("propeller_spin", true, false)
	_check("propeller wrapper carries the spin node", model.has_propeller and propeller.is_ancestor_of(spin))

	# Gear: stowed at bind, sampled poses reproduce the compiled wheel paths, oleo compression offsets the sample.
	var rig: Dictionary = model.gear_retraction
	var data: Dictionary = model.data.gear
	_check("retraction rig bound with left/right/tail and tail steering", not rig.is_empty() and model.gear.has_all(["left", "right", "tail", "steering"]))
	for extension: float in [0.0, 0.5, 1.0]:
		Rig.apply(rig, extension)
		var worst := 0.0
		for role: String in ["left", "right", "tail"]:
			var path: Array = data.wheels[role].center_model
			var expected: Array = path[int(round(extension * (path.size() - 1)))]
			worst = maxf(worst, Importer.relative(root, model.gear[role]).origin.distance_to(Vector3(expected[0], expected[1], expected[2])))
		_check("extension %.1f: wheel centres on their compiled paths" % extension, worst < 1e-4, "%.6f m" % worst)
	Rig.apply(rig, 1.0)
	var down_y := Importer.relative(root, model.gear.left).origin.y
	var slider: Node3D = rig.compression.left
	_check("sampled oleo slider: compression rest is the down sample", rig.rest.left.origin.is_equal_approx(slider.position))
	# The ground_gear.gd write: rest origin plus world-up compression in the slider's parent frame (the model root
	# is at identity here, so its model-frame basis is the global basis ground_gear.gd reads in flight).
	slider.position = rig.rest.left.origin + Importer.relative(root, slider.get_parent()).basis.inverse() * Vector3.UP * 0.01
	var compressed_y := Importer.relative(root, model.gear.left).origin.y
	_check("0.01 m of compression raises the main wheel 0.01 m", absf(compressed_y - down_y - 0.01) < 1e-5, "%.6f m" % (compressed_y - down_y))
	Rig.apply(rig, 1.0)
	_check("the next sample restores the down pose", absf(Importer.relative(root, model.gear.left).origin.y - down_y) < 1e-6)
	Rig.apply(rig, 0.0)
	_check("stowed again after a full cycle", Importer.relative(root, model.gear.left).origin.distance_to(Vector3(data.wheels.left.center_model[0][0], data.wheels.left.center_model[0][1], data.wheels.left.center_model[0][2])) < 1e-4)

	# Presentation and physics contacts (F4U-07 staged data, le frame [x_aft, y_right, z_up] = [z, x, y]).
	var physics: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../research/f4u-corsair/F4U-07/f4u_corsair_250.json").simplify_path()))
	for contact: Dictionary in physics.landing_gear.contacts:
		var role: String = contact.name.trim_prefix("main_")
		var p: Array = data.wheels[role].contact_model[-1]
		var le := Vector3(p[2], p[0], p[1])
		var phys: Array = contact.position.value
		var gap := le.distance_to(Vector3(phys[0], phys[1], phys[2]))
		_check("%s: presentation and physics contacts within 0.03 m (reconciled in F4U-08)" % role, gap < 0.03, "%.4f m" % gap)
	root.free()
	_finish()


func _finish() -> void:
	print("F4U-05 model probe: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
