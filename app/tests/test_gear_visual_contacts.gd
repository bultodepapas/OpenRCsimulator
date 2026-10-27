# GP-06: every flyable airplane's physics wheel contacts sit where its rendered wheels touch the ground.
# For each catalog aircraft with landing gear, build the same manifest-bound visual model as flight, pose retractable
# gear down, and compare each rendered wheel bottom (axle node origin minus the wheel-profile radius along model up),
# converted to the LE datum through the manifest datum, with the physics contact. GP-06b found the Stik contacts 5 mm
# below the drawn wheels (the thrust-line datum was left out), so the wheels floated on the ground; nothing checked it.
# Wheels are compared at rest (zero compression, level body): the renderer then moves each axle by the contact's own
# compression, so agreement here means agreement on the ground. The Stik's mains are bent wire legs whose rest pose
# is the built geometry (US-V10 flex is driven by the same compression).
# Run: godot --headless --path . --script res://tests/test_gear_visual_contacts.gd
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Airplane := preload("res://render/airplane.gd")
const Retraction := preload("res://aircraft/retractable_model.gd")

## Largest accepted visual/physics wheel-bottom difference (m) per axis. Mesh-measured radii (Lumber, Vantage Jet) agree
## with their profiles to about 0.02 mm; the bound leaves room for that, far below a visible float or sink.
const TOLERANCE_M := 0.0005

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var covered := 0
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		var id := str(entry.id)
		var loaded: Dictionary = AircraftData.load_file(str(entry.data))
		_check(id + " data loads", loaded.ok, str(loaded.get("errors", [])))
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		var gear: Dictionary = model.get("landing_gear", {})
		if gear.is_empty():
			continue
		var visual: Dictionary = Airplane.build(id)
		_check(id + " visual model builds", not visual.is_empty() and visual.get("root") is Node3D)
		if visual.is_empty():
			continue
		_pose_down(visual)
		var datum: Vector2 = Airplane.datum(id) # (model_z_le, model_y_thrust)
		var cg: PackedFloat64Array = model.cg_le
		var worst := 0.0
		for contact: Dictionary in gear.contacts:
			var key := str(contact.name).trim_prefix("main_")
			var wheel: Node3D = visual.get("gear", {}).get(key)
			_check("%s %s has a rendered wheel" % [id, contact.name], wheel != null)
			if wheel == null:
				continue
			var axle: Vector3 = _in_model_frame(wheel, visual.root).origin
			var radius: float = float(contact.get("wheel_radius", NAN))
			_check("%s %s has a profiled wheel radius" % [id, contact.name], is_finite(radius) and radius > 0.0)
			# LE frame [x_aft, y_right, z_up] of the rendered wheel bottom, and of the physics contact (body FRD about the CG).
			var bottom := PackedFloat64Array([axle.z - datum.x, axle.x, axle.y - radius - datum.y])
			var r: PackedFloat64Array = contact.position
			var physics := PackedFloat64Array([cg[0] - r[0], cg[1] + r[1], cg[2] - r[2]])
			var error := 0.0
			for axis in 3:
				error = maxf(error, absf(bottom[axis] - physics[axis]))
			worst = maxf(worst, error)
			_check("%s %s rendered wheel bottom matches the physics contact" % [id, contact.name], error <= TOLERANCE_M,
				"rendered %s, physics %s, max axis error %.3f mm" % [str(bottom), str(physics), 1000.0 * error])
		print("info %s: worst wheel-bottom difference %.4f mm" % [id, 1000.0 * worst])
		covered += 1
		visual.root.free()
	_check("every geared catalog airplane was compared", covered >= 5, str(covered))
	print("GP-06 gear visual contacts: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


## The node's transform relative to the model root (the model frame), composed from local transforms so the check
## needs no scene tree.
func _in_model_frame(node: Node3D, top: Node3D) -> Transform3D:
	var t: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != top:
		if parent is Node3D:
			t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t


## Retractable gear rests stowed in a fresh build only by convention; compare the downlocked pose flight lands on.
func _pose_down(visual: Dictionary) -> void:
	var rig: Dictionary = visual.get("gear_retraction", {})
	if not rig.is_empty():
		Retraction.apply(rig, 1.0)
		return
	var builder: Script = visual.get("_model_builder")
	if builder != null and builder.has_method("set_gear") and not visual.get("gear_rig", {}).is_empty():
		builder.call("set_gear", visual, 1.0)
