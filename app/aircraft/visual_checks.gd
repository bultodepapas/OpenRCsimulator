# Checks atlas/winding, engine bores and crown slots on built triangles, and engine clearance.
extends RefCounted
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
var checks := 0
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures.append(label)

func _first_mesh_ray_hit(engine: MeshInstance3D, root_node: Node3D, ray_from: Vector3, ray_to: Vector3, gold_only: bool = false) -> Variant:
	var root_from_mesh: Transform3D = root_node.global_transform.affine_inverse() * engine.global_transform
	var ray_direction: Vector3 = (ray_to - ray_from).normalized()
	var ray_length: float = ray_from.distance_to(ray_to)
	var closest_hit: Variant = null
	var closest_distance := INF
	for surface in range(engine.mesh.get_surface_count()):
		if gold_only:
			var surface_material := engine.mesh.surface_get_material(surface)
			if surface_material == null or not surface_material.resource_name.begins_with("anodized_gold"):
				continue
		var arrays := engine.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var count: int = vertices.size() if indices == null or indices.is_empty() else indices.size()
		for i in range(0, count - 2, 3):
			var a_index: int = i if indices == null or indices.is_empty() else indices[i]
			var b_index: int = i + 1 if indices == null or indices.is_empty() else indices[i + 1]
			var c_index: int = i + 2 if indices == null or indices.is_empty() else indices[i + 2]
			var a: Vector3 = root_from_mesh * vertices[a_index]
			var b: Vector3 = root_from_mesh * vertices[b_index]
			var c: Vector3 = root_from_mesh * vertices[c_index]
			var hit_mm: Variant = Geometry3D.ray_intersects_triangle(ray_from * 1000.0, ray_direction, a * 1000.0, b * 1000.0, c * 1000.0)
			if hit_mm == null:
				continue
			var hit: Vector3 = hit_mm / 1000.0
			var distance: float = ray_from.distance_to(hit)
			if (hit - ray_from).dot(ray_direction) < -0.000001 or distance > ray_length + 0.000001:
				continue
			if distance < closest_distance:
				closest_distance = distance
				closest_hit = hit
	return closest_hit


func _check_engine_mesh(airplane: Dictionary) -> Dictionary:
	var root_node := airplane.root as Node3D
	var engine := root_node.find_child("engine_assembly", true, false) as MeshInstance3D
	check("engine assembly mesh present", engine != null and engine.mesh != null)
	if engine == null or engine.mesh == null:
		return {}
	var equipment: Dictionary = Geometry.DATA.equipment
	var shaft_y: float = float(equipment.shaft_y)
	var engine_z: float = (float(equipment.firewall_z) + float(equipment.prop_z)) * 0.5
	check("engine assembly clears propeller plane by 5 mm", engine.get_aabb().position.z > float(equipment.prop_z) + 0.005)

	# Compute inspection rays independently from the installation datum, not node metadata.
	var carb_lower := Vector3(0, shaft_y + 0.012, engine_z - 0.010)
	var carb_upper := Vector3(0, shaft_y + 0.027, engine_z - 0.026)
	var intake_axis: Vector3 = (carb_upper - carb_lower).normalized()
	var intake_mouth: Vector3 = carb_upper + intake_axis * 0.005
	var inward_intake: Vector3 = -intake_axis
	var side_axis: Vector3 = intake_axis.cross(Vector3.RIGHT).normalized()
	var up_axis: Vector3 = intake_axis.cross(side_axis).normalized()
	var intake_offsets: Array[Vector3] = [Vector3.ZERO, side_axis * 0.002, -side_axis * 0.002, up_axis * 0.002, -up_axis * 0.002]
	var intake_depths: Array[float] = []
	for i in range(intake_offsets.size()):
		var ray_start: Vector3 = intake_mouth + intake_offsets[i]
		var hit: Variant = _first_mesh_ray_hit(engine, root_node, ray_start, ray_start + inward_intake * 0.035)
		var depth := ray_start.distance_to(hit) if hit is Vector3 else -1.0
		check("carburetor bore ray %d reaches a deep mesh obstruction" % i, hit is Vector3 and depth >= 0.008 and depth < 0.035)
		intake_depths.append(depth)

	# Slot centers and tooth centers sample the gold triangles at matching radius.
	var crown_center := Vector3(0, shaft_y, engine_z + 0.010)
	var slot_floors: Array[float] = []
	var tooth_tops: Array[float] = []
	var crown_gaps: Array[float] = []
	for i in range(12):
		var base_angle: float = TAU * float(i) / 12.0
		var slot_angle: float = base_angle
		var tooth_angle: float = base_angle + PI / 12.0
		var slot_point := crown_center + Vector3(cos(slot_angle), 0, sin(slot_angle)) * 0.0185
		var tooth_point := crown_center + Vector3(cos(tooth_angle), 0, sin(tooth_angle)) * 0.0185
		var slot_hit: Variant = _first_mesh_ray_hit(engine, root_node, Vector3(slot_point.x, shaft_y + 0.10, slot_point.z), Vector3(slot_point.x, shaft_y + 0.05, slot_point.z), true)
		var tooth_hit: Variant = _first_mesh_ray_hit(engine, root_node, Vector3(tooth_point.x, shaft_y + 0.10, tooth_point.z), Vector3(tooth_point.x, shaft_y + 0.05, tooth_point.z), true)
		var slot_y: float = slot_hit.y if slot_hit is Vector3 else -1.0
		var tooth_y: float = tooth_hit.y if tooth_hit is Vector3 else -1.0
		var height_gap: float = tooth_y - slot_y if slot_hit is Vector3 and tooth_hit is Vector3 else -1.0
		check("gold crown slot ray %02d hits slot floor" % i, slot_hit is Vector3)
		check("gold crown tooth ray %02d hits tooth top" % i, tooth_hit is Vector3)
		check("gold crown slot %02d is at least 2 mm below tooth" % i, height_gap >= 0.002)
		slot_floors.append(slot_y)
		tooth_tops.append(tooth_y)
		crown_gaps.append(height_gap)

	var outlet_start := Vector3(0.056, shaft_y - 0.009, engine_z + 0.030)
	var outlet_end := Vector3(0.064, shaft_y - 0.018, engine_z + 0.041)
	var inward_outlet: Vector3 = (outlet_start - outlet_end).normalized()
	var outlet_radial: Vector3 = inward_outlet.cross(Vector3.UP).normalized()
	var outlet_probe_start: Vector3 = outlet_end + outlet_radial * 0.0004
	var outlet_hit: Variant = _first_mesh_ray_hit(engine, root_node, outlet_probe_start, outlet_probe_start + inward_outlet * 0.020)
	var outlet_depth := outlet_probe_start.distance_to(outlet_hit) if outlet_hit is Vector3 else -1.0
	check("muffler outlet bore has a 5-15 mm deep mesh bottom", outlet_hit is Vector3 and outlet_depth >= 0.005 and outlet_depth < 0.015)
	print("Engine mesh probes: intake depths m=%s; crown floor y=%s; tooth y=%s; gaps m=%s; outlet depth m=%.6f" % [str(intake_depths), str(slot_floors), str(tooth_tops), str(crown_gaps), outlet_depth])
	return {"intake_depths_m": intake_depths, "crown_floor_y": slot_floors, "crown_tooth_y": tooth_tops, "crown_gaps_m": crown_gaps, "outlet_depth_m": outlet_depth}


func run(airplane: Dictionary) -> Dictionary:
	var skin := Finish.covering()
	check("atlas loaded", skin.albedo_texture != null)
	if skin.albedo_texture == null: return {"checks": checks, "failures": failures, "ok": false}
	var image := skin.albedo_texture.get_image()
	check("atlas has mip chain", image.has_mipmaps())
	check("atlas is square and intended resolution", image.get_size() == Vector2i(1024, 1024))
	check("atlas does not multiply colored tint", skin.albedo_color.is_equal_approx(Color.WHITE))
	var total_uvs := 0
	var winding_triangles := 0
	for node in airplane.root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var mesh_arrays := instance.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = mesh_arrays[Mesh.ARRAY_NORMAL]
			var indices: Variant = mesh_arrays[Mesh.ARRAY_INDEX]
			var count: int = positions.size() if indices == null or indices.is_empty() else indices.size()
			var valid_winding := true
			for i in range(0, count, 3):
				var a: int = i if indices == null or indices.is_empty() else indices[i]
				var b: int = i+1 if indices == null or indices.is_empty() else indices[i+1]
				var c: int = i+2 if indices == null or indices.is_empty() else indices[i+2]
				var face := (positions[c] - positions[a]).cross(positions[b] - positions[a])
				if face.length_squared() < 1e-20: continue
				var expected := normals[a] + normals[b] + normals[c]
				valid_winding = valid_winding and face.dot(expected) > 0.000001 * face.length() * expected.length()
				winding_triangles += 1
			check("clockwise faces agree with normals " + String(instance.name) + ":" + str(surface), valid_winding)
			if instance.mesh.surface_get_material(surface) != skin: continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			check("UV vertex cardinality " + String(instance.name), vertices.size() == uv.size())
			if vertices.size() != uv.size(): continue
			var valid := true
			var aligned := true
			var frame: Node3D = null
			if String(instance.name).begins_with("wing_") or String(instance.name).begins_with("fixed_te_"):
				frame = instance.get_parent() as Node3D
			elif String(instance.name).begins_with("aileron_"):
				frame = instance.get_parent().get_parent() as Node3D
			for i in uv.size():
				valid = valid and is_finite(uv[i].x) and is_finite(uv[i].y) and uv[i].x >= 0 and uv[i].x <= 1 and uv[i].y >= 0 and uv[i].y <= 1
				if frame != null:
					var point := frame.to_local(instance.to_global(vertices[i]))
					aligned = aligned and uv[i].distance_to(Finish.uv(point, "wing")) < 0.00001
			check("finite atlas UV " + String(instance.name), valid)
			if frame != null: check("neutral fixed/moving atlas registration " + String(instance.name), aligned)
			total_uvs += uv.size()
	check("skin vertices audited", total_uvs > 100)
	var a := MeshInstance3D.new()
	var b := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.material = skin
	a.mesh = mesh
	b.mesh = mesh
	a.material_override = skin.duplicate() as StandardMaterial3D
	a.material_override.roughness = 0.99
	check("inspection override stays local", b.get_active_material(0) == skin and a.get_active_material(0) != skin and skin.roughness != 0.99)
	check("same color different finishes stay distinct", Finish.material(Color.GRAY, "rubber") != Finish.material(Color.GRAY, "steel"))
	var engine_probe_report := _check_engine_mesh(airplane)
	a.free()
	b.free()
	return {"checks": checks, "failures": failures, "ok": failures.is_empty(), "textured_vertices": total_uvs, "winding_triangles": winding_triangles, "engine_probes": engine_probe_report}
