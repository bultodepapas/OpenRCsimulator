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

func check_concave_panels() -> void:
	# A C has area 7 and its vertex centroid lies outside the polygon.
	# A centroid triangle fan overlaps its recess; ear clipping must not.
	for vertical in [false, true]:
		var outline: Array = []
		for p in [Vector2(0, 0), Vector2(3, 0), Vector2(3, 1), Vector2(1, 1), Vector2(1, 2), Vector2(3, 2), Vector2(3, 3), Vector2(0, 3)]:
			outline.append(Vector3(0, p.y, p.x) if vertical else Vector3(p.x, 0, p.y))
		var parent := Node3D.new()
		var mesh := Model.slab(outline, Vector3(.01, 0, 0) if vertical else Vector3(0, .01, 0), parent, "concave_probe", Color.WHITE)
		var vertices := mesh.mesh.get_faces()
		var volume := 0.0
		for i in range(0, vertices.size(), 3):
			volume -= vertices[i].dot(vertices[i + 1].cross(vertices[i + 2])) / 6.0
		check(absf(volume - .14) < .000001, "Concave panel triangulation/winding: %s" % volume)
		parent.free()

func check_lofts(model: Dictionary) -> void:
	for key in ["fuselage_stations", "canopy_stations"]:
		var knots: Array = model.data[key]
		var samples := Model.interpolate_sections(knots, 4)
		var valid := samples.size() == (knots.size() - 1) * 4 + 1
		for i in knots.size() - 1:
			valid = valid and samples[i * 4] == knots[i]
			for j in 4:
				var row: Array = samples[i * 4 + j]
				valid = valid and row[1] > 0 and row[2] > row[3]
				for c in range(1, row.size()):
					valid = valid and row[c] >= minf(knots[i][c], knots[i + 1][c]) - 1e-8 and row[c] <= maxf(knots[i][c], knots[i + 1][c]) + 1e-8
		check(valid and samples[-1] == knots[-1], key + " interpolation changed knots or overshot bounds")
	for node in [model.skin, model.canopy]:
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var valid: bool = normals.size() == arrays[Mesh.ARRAY_VERTEX].size()
		for n in normals: valid = valid and n.is_finite() and absf(n.length() - 1) < .001
		check(valid, "Invalid loft normals: " + str(node.name))
		# Godot may encode a zero input normal as a unit vector. Check its
		# direction against each actual triangle as well as its stored length.
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var outward := true
		for i in range(0, vertices.size(), 3):
			var geometric := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).normalized()
			outward = outward and geometric.dot(normals[i] + normals[i + 1] + normals[i + 2]) > 0
		check(outward, "Loft normals disagree with face orientation: " + str(node.name))
	# Shading must not move vertices or change the physical silhouette.
	var parent := Node3D.new()
	var flat := Model.loft(model.data.canopy_stations, parent, "flat_probe", Color.WHITE, 1, 4, false)
	check(flat.mesh.get_faces() == model.canopy.mesh.get_faces(), "Smooth shading moved canopy vertices")
	parent.free()

func run() -> void:
	check_concave_panels()
	var model := Model.build()
	get_root().add_child(model.root)
	await process_frame
	check_lofts(model)
	var bounds := vertex_bounds(model.root)
	check(absf(bounds.size.x - 2.0) < .0001, "Nominal span must be 2m")
	check(absf(bounds.size.z - 2.22) < .0001, "Overall model length must be 2.22m")
	check(absf(model.skin.mesh.get_aabb().size.z - 2.22) < .0001, "Fuselage must be 2.22m")
	check(absf(bounds.position.x + bounds.end.x) < .0001, "Neutral lateral symmetry")
	check(model.hinges.size() == 7, "Need 2 flaps, 2 ailerons, 2 elevators, rudder")
	# Intermediate tail stations must meet the same straight elevator hinge.
	for side in [-1.0, 1.0]:
		var panel: Dictionary = model.data.tail
		var span: Array = ["probe", panel.stations[0][0], panel.stations[-1][0]]
		var h: Dictionary = model.hinges["elevator_left" if side < 0 else "elevator_right"]
		for row in panel.stations:
			var p := Model.hinge_point(panel, span, row[0], side)
			check((p - h.end_a).cross(h.axis).length() < .000001, "Curved tail bent hinge axis")
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
