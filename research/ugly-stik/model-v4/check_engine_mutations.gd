extends SceneTree
const Builder := preload("res://render/airplane.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const VisualChecks := preload("res://aircraft/visual_checks.gd")

func _initialize() -> void:
	call_deferred("_run_mutations")

func _run_mutations() -> void:
	var intake_detected: bool = await _run_mutation("capped_intake", "carburetor bore ray")
	var crown_detected: bool = await _run_mutation("closed_crown_slots", "is at least 2 mm below tooth")
	print("MUTATION SUMMARY: capped intake detected=", intake_detected, "; closed crown detected=", crown_detected)
	quit(0 if intake_detected and crown_detected else 1)

func _run_mutation(kind: String, expected_failure_fragment: String) -> bool:
	var airplane := Builder.build()
	var root_node := airplane.root as Node3D
	root.add_child(root_node)
	await process_frame
	var engine := root_node.find_child("engine_assembly", true, false) as MeshInstance3D
	if engine == null or not (engine.mesh is ArrayMesh):
		printerr("MUTATION ", kind, " could not find mutable engine mesh")
		root_node.queue_free()
		await process_frame
		return false
	if kind == "capped_intake":
		_add_intake_cap(engine)
	else:
		_close_crown_slots(engine)
	var report: Dictionary = VisualChecks.new().run(airplane)
	var matching_failures: Array[String] = []
	for failure in report.failures:
		if String(failure).contains(expected_failure_fragment):
			matching_failures.append(String(failure))
	var detected := not matching_failures.is_empty()
	print("MUTATION ", kind, ": expected defect detected=", detected, "; matching failures=", matching_failures.size(), "; total visual failures=", report.failures.size())
	root_node.queue_free()
	await process_frame
	return detected

func _add_intake_cap(engine: MeshInstance3D) -> void:
	var equipment: Dictionary = Geometry.DATA.equipment
	var shaft_y: float = float(equipment.shaft_y)
	var engine_z: float = (float(equipment.firewall_z) + float(equipment.prop_z)) * 0.5
	var lower := Vector3(0, shaft_y + 0.012, engine_z - 0.010)
	var upper := Vector3(0, shaft_y + 0.027, engine_z - 0.026)
	var axis: Vector3 = (upper - lower).normalized()
	var mouth: Vector3 = upper + axis * 0.005
	var cap_surface := SurfaceTool.new()
	cap_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap_material := StandardMaterial3D.new()
	cap_material.resource_name = "mutation_intake_cap"
	cap_surface.set_material(cap_material)
	# A closed, 1 mm long cylinder crosses the throat 0.5 mm behind its mouth.
	Equipment._engine_cylinder(cap_surface, mouth - axis * 0.0015, mouth - axis * 0.0005, 0.0049, 0.0049, 32)
	cap_surface.commit(engine.mesh as ArrayMesh)

func _close_crown_slots(engine: MeshInstance3D) -> void:
	var equipment: Dictionary = Geometry.DATA.equipment
	var shaft_y: float = float(equipment.shaft_y)
	var engine_z: float = (float(equipment.firewall_z) + float(equipment.prop_z)) * 0.5
	var center := Vector3(0, shaft_y + 0.058, engine_z + 0.010)
	var top_y: float = shaft_y + 0.0655
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gold := StandardMaterial3D.new()
	gold.resource_name = "anodized_gold:mutation"
	fill.set_material(gold)
	for slot in range(12):
		var middle: float = TAU * float(slot) / 12.0
		var start: float = middle - deg_to_rad(2.5)
		for step in range(4):
			var a0: float = start + deg_to_rad(5.0) * float(step) / 4.0
			var a1: float = start + deg_to_rad(5.0) * float(step + 1) / 4.0
			var inner0 := Vector3(center.x + cos(a0) * 0.016, top_y, center.z + sin(a0) * 0.016)
			var outer0 := Vector3(center.x + cos(a0) * 0.020, top_y, center.z + sin(a0) * 0.020)
			var outer1 := Vector3(center.x + cos(a1) * 0.020, top_y, center.z + sin(a1) * 0.020)
			var inner1 := Vector3(center.x + cos(a1) * 0.016, top_y, center.z + sin(a1) * 0.016)
			_add_triangle(fill, inner0, outer0, outer1, Vector3.UP)
			_add_triangle(fill, inner0, outer1, inner1, Vector3.UP)
	fill.commit(engine.mesh as ArrayMesh)

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var p1 := b
	var p2 := c
	if (p1 - a).cross(p2 - a).dot(normal) > 0.0:
		p1 = c
		p2 = b
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.add_vertex(p1)
	surface.set_normal(normal)
	surface.add_vertex(p2)
