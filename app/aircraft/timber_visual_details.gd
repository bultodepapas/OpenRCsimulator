## Render-only finishes and construction cues for the Turbo Lumber Evolution.
## The helper changes instance materials and adds meshes/labels with crash_no_bounds; it never edits source meshes.
extends RefCounted

const ImportedModel := preload("res://aircraft/imported_model.gd")
const VisualData := preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd")
const FOAM_NORMAL: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/polystyrene_nor_gl_1k.jpg")
const FOAM_ROUGHNESS: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/polystyrene_rough_1k.jpg")
const RUBBER_NORMAL: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/Rubber002_1K-JPG_NormalGL.jpg")
const RUBBER_ROUGHNESS: Texture2D = preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/Rubber002_1K-JPG_Roughness.jpg")

const APPLIED_META := "timber_visual_details_applied"


## Safe to call from the catalog builder or an inspector. Returns true when the detail layer exists.
static func apply(root: Node3D) -> bool:
	if root == null:
		return false
	if root.has_meta(APPLIED_META):
		return true
	_apply_material_finishes(root)
	_add_fuselage_markings(root)
	_add_gear_springs(root)
	_add_hub_fasteners(root)
	_add_fracture_reveals(root)
	root.set_meta(APPLIED_META, true)
	return true


static func _apply_material_finishes(root: Node3D) -> void:
	var meshes := _mesh_instances(root)
	var profiles: Dictionary = VisualData.DATA.material_profiles
	for profile_name: String in profiles:
		var profile: Dictionary = profiles[profile_name]
		var allowed_meshes: Array = profile.get("meshes", [])
		var target_materials: Array = profile.get("materials", [])
		for mesh_instance: MeshInstance3D in meshes:
			if not allowed_meshes.is_empty() and not allowed_meshes.has(String(mesh_instance.name)):
				continue
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
				if source == null or not target_materials.has(source.resource_name):
					continue
				var material := source.duplicate() as StandardMaterial3D
				material.resource_name = source.resource_name
				if profile.has("roughness"):
					material.roughness = float(profile.roughness)
				if profile.has("specular"):
					material.metallic_specular = float(profile.specular)
				if profile.has("metallic"):
					material.metallic = float(profile.metallic)
				if profile.has("opacity"):
					var color := material.albedo_color
					material.albedo_color = Color(color.r, color.g, color.b, float(profile.opacity))
					material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				if profile.has("texture"):
					_apply_surface_texture(material, profile)
				if profile.has("grow_meshes") and profile.grow_meshes.has(String(mesh_instance.name)):
					material.grow = true
					material.grow_amount = float(profile.grow_amount_m)
				mesh_instance.set_surface_override_material(surface_index, material)


static func _apply_surface_texture(material: StandardMaterial3D, profile: Dictionary) -> void:
	var pair: Array[Texture2D]
	match String(profile.texture):
		"foam":
			pair = [FOAM_NORMAL, FOAM_ROUGHNESS]
		"rubber":
			pair = [RUBBER_NORMAL, RUBBER_ROUGHNESS]
		_:
			return
	material.normal_enabled = true
	material.normal_texture = pair[0]
	material.normal_scale = float(profile.get("normal_scale", 0.04))
	material.roughness_texture = pair[1]
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 3.0
	material.uv1_scale = Vector3.ONE * float(profile.get("world_tiling_per_m", 3.0))


static func _mesh_instances(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			out.append(mesh_instance)
	return out


static func _find_mesh(root: Node3D, name: String) -> MeshInstance3D:
	return root.find_child(name, true, false) as MeshInstance3D


static func _add_fuselage_markings(root: Node3D) -> void:
	var config: Dictionary = VisualData.DATA.surface_details.fuselage_label
	var host := _find_mesh(root, str(config.host))
	if host == null:
		return
	var group := Node3D.new()
	group.name = "TimberFuselageMarkings"
	group.set_meta("crash_no_bounds", true)
	host.add_child(group)
	var local_position: Array = config.local_position
	for side: String in config.sides:
		var sign_x := -1.0 if side == "left" else 1.0
		var label := Label3D.new()
		label.name = "TurboLumberName_" + side
		label.text = str(config.text)
		label.font_size = int(config.font_size)
		label.pixel_size = float(config.pixel_size_m)
		label.modulate = Color(str(config.color))
		label.shaded = true
		label.no_depth_test = false
		label.double_sided = false
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector3(sign_x * (absf(float(local_position[0])) + 0.001), float(local_position[1]), float(local_position[2]))
		var text_axis := Vector3(0, 0, -1) if side == "right" else Vector3(0, 0, 1)
		var outward := Vector3.RIGHT if side == "right" else Vector3.LEFT
		label.basis = Basis(text_axis, Vector3.UP, outward)
		label.set_meta("crash_no_bounds", true)
		group.add_child(label)


static func _add_gear_springs(root: Node3D) -> void:
	var config: Dictionary = VisualData.DATA.surface_details.main_gear_springs
	var host := _find_mesh(root, str(config.host))
	if host == null:
		return
	var group := Node3D.new()
	group.name = "TimberMainGearCoilSprings"
	group.set_meta("crash_no_bounds", true)
	host.add_child(group)
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberBrushedSpringSteel"
	material.albedo_color = Color("#aeb5ba")
	material.metallic = 0.82
	material.roughness = 0.29
	var limits: Array = config.travel_fraction
	var host_to_root := ImportedModel.relative(root, host)
	var root_to_host := host_to_root.affine_inverse()
	for cable: Dictionary in VisualData.DATA.main_gear_cables:
		var start_root := _vector3(cable.start).lerp(_vector3(cable.end), float(limits[0]))
		var end_root := _vector3(cable.start).lerp(_vector3(cable.end), float(limits[1]))
		var start_local := root_to_host * start_root
		var end_local := root_to_host * end_root
		var spring := MeshInstance3D.new()
		spring.name = "TimberExtensionSpring_" + str(cable.id)
		spring.mesh = _coil_mesh(start_local, end_local, float(config.coil_radius_m), float(config.wire_radius_m), int(config.turns), int(config.segments_per_turn))
		spring.material_override = material
		spring.set_meta("crash_no_bounds", true)
		group.add_child(spring)


static func _coil_mesh(start: Vector3, finish: Vector3, coil_radius: float, wire_radius: float, turns: int, segments_per_turn: int) -> ArrayMesh:
	var axis := (finish - start).normalized()
	var length := start.distance_to(finish)
	var reference := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var first := axis.cross(reference).normalized()
	var second := axis.cross(first).normalized()
	var longitudinal_steps := maxi(turns * segments_per_turn, 12)
	var radial_steps := 8
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in longitudinal_steps + 1:
		var t := float(ring) / float(longitudinal_steps)
		var phase := TAU * float(turns) * t
		var radial := first * cos(phase) + second * sin(phase)
		var tangent := (axis + (-first * sin(phase) + second * cos(phase)) * (TAU * float(turns) * coil_radius / maxf(length, 1.0e-6))).normalized()
		var cross_axis := tangent.cross(radial).normalized()
		var center := start.lerp(finish, t) + radial * coil_radius
		for slice in radial_steps:
			var around := TAU * float(slice) / float(radial_steps)
			var outward := radial * cos(around) + cross_axis * sin(around)
			vertices.append(center + outward * wire_radius)
			normals.append(outward)
	for ring in longitudinal_steps:
		for slice in radial_steps:
			var next_slice := (slice + 1) % radial_steps
			var a := ring * radial_steps + slice
			var b := (ring + 1) * radial_steps + slice
			var c := (ring + 1) * radial_steps + next_slice
			var d := ring * radial_steps + next_slice
			indices.append_array(PackedInt32Array([a, c, b, a, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_hub_fasteners(root: Node3D) -> void:
	var config: Dictionary = VisualData.DATA.surface_details.main_wheel_hub_fasteners
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberHubFastenerSteel"
	material.albedo_color = Color("#b7bdc1")
	material.metallic = 0.7
	material.roughness = 0.31
	var cap := CylinderMesh.new()
	cap.top_radius = float(config.head_radius_m)
	cap.bottom_radius = float(config.head_radius_m)
	cap.height = float(config.head_depth_m)
	cap.radial_segments = 6
	cap.rings = 1
	cap.material = material
	for host_name: String in config.hosts:
		var host := _find_mesh(root, host_name)
		if host == null:
			continue
		var group := Node3D.new()
		group.name = "TimberHubFasteners"
		group.set_meta("crash_no_bounds", true)
		host.add_child(group)
		for side_sign in [-1.0, 1.0]:
			for fastener_index in int(config.count):
				var angle := TAU * float(fastener_index) / float(config.count)
				var fastener := MeshInstance3D.new()
				fastener.name = "HubBolt_%d_%s" % [fastener_index, "outer" if side_sign > 0 else "inner"]
				fastener.mesh = cap
				fastener.position = Vector3(side_sign * (float(config.axial_center_m) + float(config.head_depth_m) * 0.5), float(config.circle_radius_m) * cos(angle), float(config.circle_radius_m) * sin(angle))
				fastener.rotation.z = -side_sign * PI * 0.5
				fastener.set_meta("crash_no_bounds", true)
				group.add_child(fastener)


static func _add_fracture_reveals(root: Node3D) -> void:
	for section: String in VisualData.DATA.fracture_details:
		var config: Dictionary = VisualData.DATA.fracture_details[section]
		var host := _find_mesh(root, str(config.host))
		if host == null or host.mesh == null:
			continue
		var outline := _cross_section_outline(root, host, float(config.cut_x_m))
		if outline.size() < 3:
			continue
		var normal_sign := 1.0 if section == "wing_left" else -1.0
		var reveal := Node3D.new()
		reveal.name = "TimberEPOFracture_" + section
		reveal.visible = false
		reveal.set_meta("crash_reveal", section)
		reveal.set_meta("crash_no_bounds", true)
		var host_to_root := ImportedModel.relative(root, host)
		reveal.transform = host_to_root.affine_inverse()
		host.add_child(reveal)
		var foam := MeshInstance3D.new()
		foam.name = "TornEPOCrossSection"
		foam.mesh = _face_mesh(_roughen_outline(outline, 0.00065), float(config.cut_x_m), normal_sign, 0.00012)
		foam.material_override = _foam_cut_material()
		foam.set_meta("crash_no_bounds", true)
		reveal.add_child(foam)
		var spar := MeshInstance3D.new()
		spar.name = "DarkCarbonSparEnd"
		var spar_mesh := CylinderMesh.new()
		spar_mesh.top_radius = float(config.spar_radius_m)
		spar_mesh.bottom_radius = float(config.spar_radius_m)
		spar_mesh.height = float(config.spar_depth_m)
		spar_mesh.radial_segments = 20
		spar_mesh.rings = 2
		spar.mesh = spar_mesh
		spar.position = Vector3(float(config.cut_x_m) - normal_sign * float(config.spar_depth_m) * 0.5, float(config.spar_y_m), float(config.spar_z_m))
		spar.rotation.z = -normal_sign * PI * 0.5
		spar.material_override = _carbon_material()
		spar.set_meta("crash_no_bounds", true)
		reveal.add_child(spar)


static func _cross_section_outline(root: Node3D, host: MeshInstance3D, cut_x: float) -> PackedVector3Array:
	var root_points: Array[Vector3] = []
	var unique := {}
	var mesh_to_root := ImportedModel.relative(root, host)
	for surface_index in host.mesh.get_surface_count():
		var arrays := host.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for index in vertices.size():
				indices[index] = index
		for triangle in range(0, indices.size() - 2, 3):
			var points: Array[Vector3] = [
				mesh_to_root * vertices[indices[triangle]],
				mesh_to_root * vertices[indices[triangle + 1]],
				mesh_to_root * vertices[indices[triangle + 2]],
			]
			var hits: Array[Vector3] = []
			for edge in 3:
				var a: Vector3 = points[edge]
				var b: Vector3 = points[(edge + 1) % 3]
				var da := a.x - cut_x
				var db := b.x - cut_x
				if absf(da) <= 0.000001:
					_append_hit(hits, a)
				if da * db < 0.0:
					_append_hit(hits, a.lerp(b, -da / (db - da)))
			if hits.size() >= 2:
				for hit in hits:
					var key := "%d:%d" % [roundi(hit.y * 100000.0), roundi(hit.z * 100000.0)]
					if not unique.has(key):
						unique[key] = true
						root_points.append(Vector3(cut_x, hit.y, hit.z))
	return _convex_hull_yz(root_points)


static func _append_hit(hits: Array[Vector3], point: Vector3) -> void:
	for other: Vector3 in hits:
		if other.distance_squared_to(point) <= 1.0e-10:
			return
	hits.append(point)


static func _convex_hull_yz(points: Array[Vector3]) -> PackedVector3Array:
	if points.size() < 3:
		return PackedVector3Array(points)
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.y < b.y if not is_equal_approx(a.y, b.y) else a.z < b.z
	)
	var lower: Array[Vector3] = []
	for point: Vector3 in points:
		while lower.size() >= 2 and _cross_yz(lower[-2], lower[-1], point) <= 0.0:
			lower.pop_back()
		lower.append(point)
	var upper: Array[Vector3] = []
	for index in range(points.size() - 1, -1, -1):
		var point: Vector3 = points[index]
		while upper.size() >= 2 and _cross_yz(upper[-2], upper[-1], point) <= 0.0:
			upper.pop_back()
		upper.append(point)
	lower.pop_back()
	upper.pop_back()
	lower.append_array(upper)
	return PackedVector3Array(lower)


static func _cross_yz(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b.y - a.y) * (c.z - a.z) - (b.z - a.z) * (c.y - a.y)


static func _roughen_outline(outline: PackedVector3Array, amplitude: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	var center := Vector3.ZERO
	for point in outline:
		center += point
	center /= float(outline.size())
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		result.append(a)
		var outward := Vector2((a.y + b.y) * 0.5 - center.y, (a.z + b.z) * 0.5 - center.z).normalized()
		for split in 2:
			var t := float(split + 1) / 3.0
			var sign := 1.0 if (index + split) % 2 == 0 else -1.0
			var middle := a.lerp(b, t)
			middle.y += outward.x * amplitude * sign
			middle.z += outward.y * amplitude * sign
			result.append(middle)
	return result


static func _face_mesh(outline: PackedVector3Array, cut_x: float, normal_sign: float, offset: float) -> ArrayMesh:
	var center := Vector3.ZERO
	for point in outline:
		center += point
	center /= float(outline.size())
	var normal := Vector3.RIGHT * normal_sign
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		var p_center := Vector3(cut_x + normal_sign * offset, center.y, center.z)
		var p_a := Vector3(cut_x + normal_sign * offset, a.y, a.z)
		var p_b := Vector3(cut_x + normal_sign * offset, b.y, b.z)
		st.set_normal(normal)
		st.add_vertex(p_center)
		st.set_normal(normal)
		st.add_vertex(p_a if normal_sign > 0.0 else p_b)
		st.set_normal(normal)
		st.add_vertex(p_b if normal_sign > 0.0 else p_a)
	return st.commit()


static func _foam_cut_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberTornEPOFoam"
	material.albedo_color = Color("#eeeae0")
	material.roughness = 0.94
	material.metallic_specular = 0.08
	return material


static func _carbon_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "TimberCarbonSparCut"
	material.albedo_color = Color("#222729")
	material.metallic = 0.2
	material.roughness = 0.58
	material.metallic_specular = 0.3
	return material


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
