extends SceneTree

const Model := preload("res://model.gd")
var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func vertex_bounds(node: Node3D) -> AABB:
	var initialized := false
	var box := AABB()
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh_node.visible: continue
		for vertex in mesh_node.mesh.get_faces():
			var p: Vector3 = mesh_node.global_transform * vertex
			check(p.is_finite(), "Non-finite mesh vertex")
			if not initialized:
				box = AABB(p, Vector3.ZERO); initialized = true
			else: box = box.expand(p)
	return box

func witness(h: Dictionary) -> Vector3:
	return h.node.to_global(h.witness)

func run() -> void:
	var model := Model.build()
	get_root().add_child(model.root)
	await process_frame
	var bounds := vertex_bounds(model.root)
	check(absf(bounds.size.x - 2.0) < .0001, "Nominal span must be 2m")
	check(absf(bounds.size.z - 2.22) < .0001, "Overall model length must be 2.22m")
	check(absf(model.skin.mesh.get_aabb().size.z - 2.22) < .0001, "Fuselage must be 2.22m")
	check(absf(bounds.position.x + bounds.end.x) < .0001, "Neutral lateral symmetry")
	check(model.hinges.size() == 7, "Need 2 flaps, 2 ailerons, 2 elevators, rudder")
	check(model.propeller.get_child_count() == 0 and not model.has_propeller, "Jet must have no propeller geometry")
	check(absf(model.motor.mesh.height - .241) < .00001, "P100 length")
	check(absf(model.motor.mesh.top_radius * 2 - .097) < .00001, "P100 diameter")
	var neutral := {}
	for key in model.hinges: neutral[key] = witness(model.hinges[key])
	Model.apply_controls(model, 1, 1, 1, 50)
	for key in ["flap_left", "flap_right", "aileron_left"]:
		check(witness(model.hinges[key]).y < neutral[key].y - .01, key + " must go DOWN")
	for key in ["elevator_left", "elevator_right", "aileron_right"]:
		check(witness(model.hinges[key]).y > neutral[key].y + .01, key + " must go UP")
	check(witness(model.hinges.rudder).x > neutral.rudder.x + .01, "Positive rudder witness goes right")
	for key in model.hinges:
		var h: Dictionary = model.hinges[key]
		check(h.node.position.distance_to(h.end_a) < .000001, key + " pivot moved")
		check((h.node.basis * h.axis).distance_to(h.axis) < .000001, key + " axis not invariant")
	Model.apply_controls(model, -1, 0, 0, 0)
	check(witness(model.hinges.aileron_left).y > neutral.aileron_left.y, "Reverse roll raises left")
	check(witness(model.hinges.aileron_right).y < neutral.aileron_right.y, "Reverse roll lowers right")
	Model.apply_controls(model, 0, 0, 0, 0)
	for key in model.hinges:
		check(witness(model.hinges[key]).distance_to(neutral[key]) < .000001, key + " failed reset")
	var other := Model.build()
	get_root().add_child(other.root)
	Model.apply_controls(model, 0, 0, 0, 50)
	check(witness(other.hinges.flap_left).distance_to(neutral.flap_left) < .000001, "Instance state leaked")
	check(model.skin.material_override != other.skin.material_override, "Study instances share mutable material")
	var result := {checks = checks, failures = failures, span_m = bounds.size.x,
		fuselage_length_m = model.skin.mesh.get_aabb().size.z, hinges = model.hinges.size(),
		geometry_sha256 = FileAccess.get_sha256("res://geometry.json"), godot = Engine.get_version_info().string,
		limits = ["Not aerodynamic validation", "No full swept-volume intersection test", "Approximate contours"]}
	print(JSON.stringify(result))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(result, "\t") + "\n")
	quit(0 if failures.is_empty() else 1)
