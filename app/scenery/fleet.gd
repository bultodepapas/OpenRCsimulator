## Offline source builder for parked-aircraft snapshots.
## Legacy one-argument callers retain material-instance grouping and level poses; modern_pbr adds equivalent-material
## batching and a measured wheel-contact pitch. Runtime scenery loads only generated static ArrayMesh resources.
extends RefCounted

const AirplaneBuilder = preload("res://render/airplane.gd")
const Retraction = preload("res://aircraft/retractable_model.gd")

const STIK_ID := "jensen-das-ugly-stik-60"
const PART_NAMES: Array[String] = ["body", "left_wing", "right_wing", "tail", "gear", "propeller"]


## {mesh, bottom, size, collision_parts, source_triangles, surfaces} for a catalog aircraft/configuration.
static func snapshot(id: String, configuration: String = "assembled", modern_pbr: bool = false) -> Dictionary:
	if configuration not in ["assembled", "service"]:
		push_error("parked aircraft: unknown configuration '%s'" % configuration)
		return {}
	if configuration == "service" and id != STIK_ID:
		push_error("parked aircraft: service configuration is available only for the Ugly Stik")
		return {}
	var airplane: Dictionary = AirplaneBuilder.build(id)
	var root: Node3D = airplane.get("root")
	if root == null:
		push_error("parked aircraft: %s did not build" % id)
		return {}
	# Modern snapshots explicitly deploy sampled/procedural retractable gear, then pose the wheels. Legacy single-argument
	# bakes keep their original untouched builder pose so historical color-baked models remain reproducible.
	if modern_pbr:
		_deploy_gear(airplane)
		AirplaneBuilder.apply_gear(airplane, {}, 0.0)
	var ground_pitch_deg := 0.0
	var ground_wheel_level_error_m := 0.0
	var ground_support_wheels := 0
	var ground_pose: Dictionary = {}
	if configuration == "assembled" and modern_pbr:
		ground_pose = _apply_ground_pitch(root, airplane)
		ground_pitch_deg = float(ground_pose.get("pitch_deg", 0.0))
		ground_wheel_level_error_m = float(ground_pose.get("wheel_level_error_m", 0.0))
		ground_support_wheels = int(ground_pose.get("support_wheels", 0))
	if configuration == "service":
		_configure_service(airplane)

	var collected := _collect_mesh(root, modern_pbr)
	var mesh: ArrayMesh = collected.mesh
	var mesh_surface_roles: Array[String] = collected.surface_roles
	var collision_bounds: Dictionary = {}
	_collect_bounds(root, Transform3D.IDENTITY, "body", collision_bounds)
	if configuration == "assembled" and modern_pbr:
		var predicted_contacts: Array[Vector3] = []
		for contact: Vector3 in ground_pose.get("contact_points", []):
			var rendered_contact: Variant = _nearest_gear_vertex(mesh, mesh_surface_roles, contact)
			if rendered_contact != null:
				predicted_contacts.append(rendered_contact)
		if predicted_contacts.size() == 3:
			var main_y := (predicted_contacts[0].y + predicted_contacts[1].y) * 0.5
			var main_z := (predicted_contacts[0].z + predicted_contacts[1].z) * 0.5
			var delta_z := main_z - predicted_contacts[2].z
			var delta_pitch := atan((main_y - predicted_contacts[2].y) / delta_z) if absf(delta_z) >= 0.1 else 0.0
			if absf(delta_pitch) > deg_to_rad(0.05) and absf(delta_pitch) <= deg_to_rad(5.0):
				root.rotation.x += delta_pitch
				ground_pitch_deg = rad_to_deg(root.rotation.x)
				var correction_rotation := Basis(Vector3.RIGHT, delta_pitch)
				var expected_contacts: Array[Vector3] = []
				for contact: Vector3 in predicted_contacts:
					expected_contacts.append(correction_rotation * contact)
				collected = _collect_mesh(root, modern_pbr)
				mesh = collected.mesh
				mesh_surface_roles = collected.surface_roles
				predicted_contacts.clear()
				for contact: Vector3 in expected_contacts:
					var rendered_contact: Variant = _nearest_gear_vertex(mesh, mesh_surface_roles, contact)
					if rendered_contact != null:
						predicted_contacts.append(rendered_contact)
				collision_bounds.clear()
				_collect_bounds(root, Transform3D.IDENTITY, "body", collision_bounds)
		if predicted_contacts.size() == 3:
			ground_pose["contact_points"] = predicted_contacts
			var contact_min := INF
			var contact_max := -INF
			for contact: Vector3 in predicted_contacts:
				contact_min = minf(contact_min, contact.y)
				contact_max = maxf(contact_max, contact.y)
			ground_wheel_level_error_m = contact_max - contact_min
	root.free()
	if mesh.get_surface_count() == 0:
		push_error("parked aircraft: %s produced no triangle surfaces" % id)
		return {}
	var box := mesh.get_aabb()
	var bottom := box.position.y
	var shift := Vector3(-box.get_center().x, -bottom, -box.get_center().z)
	var ground_wheel_contacts: Array[Array] = []
	for contact: Vector3 in ground_pose.get("contact_points", []):
		var normalized_contact := contact + shift
		ground_wheel_contacts.append([normalized_contact.x, normalized_contact.y, normalized_contact.z])
	var collision_parts: Array[Dictionary] = []
	for part_name: String in PART_NAMES:
		if not collision_bounds.has(part_name):
			continue
		var part: AABB = collision_bounds[part_name]
		var center := part.get_center() + shift
		collision_parts.append({
			"part": part_name,
			"center": [center.x, center.y, center.z],
			"size": [part.size.x, part.size.y, part.size.z],
		})
	var triangle_count := 0
	for surface in mesh.get_surface_count():
		var index_count := mesh.surface_get_array_index_len(surface)
		triangle_count += (index_count if index_count > 0 else mesh.surface_get_array_len(surface)) / 3
	return {
		"mesh": mesh,
		"surface_roles": mesh_surface_roles,
		"bottom": bottom,
		"size": box.size,
		"collision_parts": collision_parts,
		"source_triangles": triangle_count,
		"surfaces": mesh.get_surface_count(),
		"ground_pitch_deg": ground_pitch_deg,
		"ground_wheel_level_error_m": ground_wheel_level_error_m,
		"ground_support_wheels": ground_support_wheels,
		"ground_wheel_contacts": ground_wheel_contacts,
	}


static func _collect_mesh(root: Node3D, modern_pbr: bool) -> Dictionary:
	var tools: Dictionary = {}
	var materials: Dictionary = {}
	var surface_roles: Dictionary = {}
	var order: Array = []
	_collect(root, Transform3D.IDENTITY, "body", tools, materials, surface_roles, order, modern_pbr)
	var mesh := ArrayMesh.new()
	var mesh_surface_roles: Array[String] = []
	for key: Variant in order:
		var st: SurfaceTool = tools[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		mesh_surface_roles.append(str(surface_roles.get(key, "body")))
	return {mesh = mesh, surface_roles = mesh_surface_roles}


static func _deploy_gear(airplane: Dictionary) -> void:
	var rig: Dictionary = airplane.get("gear_retraction", {})
	if not rig.is_empty():
		Retraction.apply(rig, 1.0)
		return
	var builder: Variant = airplane.get("_model_builder")
	if builder != null and builder.has_method("set_gear"):
		builder.call("set_gear", airplane, 1.0)


static func _configure_service(airplane: Dictionary) -> void:
	AirplaneBuilder.set_maintenance(airplane, true)
	var root: Node3D = airplane.root
	# Keep stock node names and hinge bindings stable while showing the airframe opened for service.
	for side: String in ["left", "right"]:
		var wing := root.get_node_or_null("wing_frame_%s" % side) as Node3D
		if wing:
			wing.visible = false
	# A service airframe rests on the work foam. Hide only the gear assembly nodes; the assembled snapshot keeps them.
	for node_name: String in ["main_gear_structure", "wheel_left_pivot", "wheel_right_pivot", "nose_steering_pivot", "propeller"]:
		var gear_node := root.find_child(node_name, true, false) as Node3D
		if gear_node:
			gear_node.visible = false


static func _collect(node: Node, parent: Transform3D, part: String, tools: Dictionary,
		materials: Dictionary, surface_roles: Dictionary, order: Array, modern_pbr: bool) -> void:
	if node is Node3D and not (node as Node3D).visible:
		return
	var transform := parent
	if node is Node3D:
		transform = parent * (node as Node3D).transform
	var source: Mesh
	if node is MeshInstance3D:
		source = (node as MeshInstance3D).mesh
	elif modern_pbr and node is ImporterMeshInstance3D:
		var imported: ImporterMesh = (node as ImporterMeshInstance3D).get_mesh()
		source = imported.get_mesh() if imported else null
	if source:
		for surface in source.get_surface_count():
			if source is ArrayMesh and (source as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material: Material
			if node is MeshInstance3D:
				material = (node as MeshInstance3D).get_active_material(surface)
			else:
				material = source.surface_get_material(surface)
			var key: Variant = _material_key(material) if modern_pbr else material
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
				materials[key] = material
				surface_roles[key] = part
				order.append(key)
			elif modern_pbr and part == "gear":
				# Preserve which material batches include contact gear without increasing draw surfaces.
				surface_roles[key] = "gear"
			(tools[key] as SurfaceTool).append_from(source, surface, transform)
	for child in node.get_children():
		var child_part := _child_part(child, part)
		_collect(child, transform, child_part, tools, materials, surface_roles, order, modern_pbr)


static func _collect_bounds(node: Node, parent: Transform3D, part: String, out: Dictionary) -> void:
	if node is Node3D and not (node as Node3D).visible:
		return
	var transform := parent
	if node is Node3D:
		transform = parent * (node as Node3D).transform
	var source: Mesh
	if node is MeshInstance3D:
		source = (node as MeshInstance3D).mesh
	elif node is ImporterMeshInstance3D:
		var imported: ImporterMesh = (node as ImporterMeshInstance3D).get_mesh()
		source = imported.get_mesh() if imported else null
	if source:
		var box := _transformed_aabb(source.get_aabb(), transform)
		if out.has(part):
			out[part] = (out[part] as AABB).merge(box)
		else:
			out[part] = box
	for child in node.get_children():
		var child_part := _child_part(child, part)
		_collect_bounds(child, transform, child_part, out)


static func _child_part(node: Node, current: String) -> String:
	if not (node is Node3D):
		return current
	var name := str(node.name).to_lower()
	# Some P-51 wing details are attached directly to the airplane root instead of a wing frame.
	# Keep side-specific lights, fuel caps, and gun ports with their wing rather than stretching the fuselage proxy.
	var wing_surface := name.contains("wing") or name.contains("aileron") or name.contains("flap") \
			or name.contains("nav_light") or name.contains("fuel_cap") or name.contains("gun_port")
	if wing_surface and (name.contains("left") or name.ends_with("_l")):
		return "left_wing"
	if wing_surface and (name.contains("right") or name.ends_with("_r")):
		return "right_wing"
	# The P-51 builder names its right-wing pitot mast and tube without a side suffix.
	if name.contains("pitot"):
		return "right_wing"
	if name.contains("gear") or name.contains("wheel") or name.contains("axle") or name.contains("strut") \
			or name.contains("inner_door") or name.contains("well_door"):
		return "gear"
	if name.contains("propeller"):
		return "propeller"
	if name.contains("tail") or name.contains("rudder") or name.contains("elevator") \
			or name.contains("fin") or name.contains("stabilizer") or name.contains("empennage"):
		return "tail"
	return current


static func _transformed_aabb(box: AABB, transform: Transform3D) -> AABB:
	var corners: Array[Vector3] = []
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				corners.append(transform * (box.position + Vector3(box.size.x * x, box.size.y * y, box.size.z * z)))
	var result := AABB(corners[0], Vector3.ZERO)
	for i in range(1, corners.size()):
		result = result.expand(corners[i])
	return result


static func _apply_ground_pitch(root: Node3D, airplane: Dictionary) -> Dictionary:
	var gear: Dictionary = airplane.get("gear", {})
	var manifest: Dictionary = airplane.get("model_manifest", {})
	var gear_keys: Dictionary = manifest.get("bindings", {}).get("gear", {}).get("keys", {})
	var left_wheel := _gear_node(gear, gear_keys, "left")
	var right_wheel := _gear_node(gear, gear_keys, "right")
	var trailing_role := "nose" if _gear_node(gear, gear_keys, "nose") != null else "tail"
	var trailing_wheel := _gear_node(gear, gear_keys, trailing_role)
	if left_wheel == null or right_wheel == null or trailing_wheel == null:
		return {"pitch_deg": 0.0, "wheel_level_error_m": 0.0, "support_wheels": 0}
	var left := _gear_wheel_bounds(root, left_wheel)
	var right := _gear_wheel_bounds(root, right_wheel)
	var trailing := _gear_wheel_bounds(root, trailing_wheel)
	if left.is_empty() or right.is_empty() or trailing.is_empty():
		return {"pitch_deg": 0.0, "wheel_level_error_m": 0.0, "support_wheels": 0}
	var left_box: AABB = left.bounds
	var right_box: AABB = right.bounds
	var trailing_box: AABB = trailing.bounds
	var raw_contacts: Array[Vector3] = []
	for wheel: Node3D in [left_wheel, right_wheel, trailing_wheel]:
		var point: Variant = _gear_support_point(root, wheel)
		if point == null:
			return {"pitch_deg": 0.0, "wheel_level_error_m": 0.0, "support_wheels": 0}
		raw_contacts.append(point)
	var main_y := (left_box.position.y + right_box.position.y) * 0.5
	var main_z := (left_box.get_center().z + right_box.get_center().z) * 0.5
	var trailing_y := trailing_box.position.y
	var delta_z := main_z - trailing_box.get_center().z
	if absf(delta_z) < 0.1:
		return {"pitch_deg": 0.0, "wheel_level_error_m": 0.0, "support_wheels": 3,
			"contact_points": raw_contacts}
	var pitch := atan((main_y - trailing_y) / delta_z)
	# A conventional taildragger can need a little over twelve degrees to put the tailwheel
	# on the same plane as its mains. Reject only larger builder-specific offsets.
	if absf(pitch) > deg_to_rad(16.0):
		return {"pitch_deg": 0.0, "wheel_level_error_m": 0.0, "support_wheels": 3,
			"contact_points": raw_contacts}
	root.rotation.x = pitch
	var rotation := Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
	var contact_points: Array[Vector3] = []
	for point: Vector3 in raw_contacts:
		contact_points.append(rotation * point)
	var bottom_min := INF
	var bottom_max := -INF
	for point: Vector3 in contact_points:
		bottom_min = minf(bottom_min, point.y)
		bottom_max = maxf(bottom_max, point.y)
	return {
		"pitch_deg": rad_to_deg(pitch),
		"wheel_level_error_m": bottom_max - bottom_min,
		"support_wheels": contact_points.size(),
		"contact_points": contact_points,
	}


static func _gear_node(gear: Dictionary, keys: Dictionary, role: String) -> Node3D:
	var candidates: Array[String] = []
	var bound_key := str(keys.get(role, ""))
	if not bound_key.is_empty():
		candidates.append(bound_key)
	candidates.append(role)
	candidates.append("main_%s" % role)
	candidates.append("%s_main" % role)
	candidates.append("%s_gear" % role)
	for key: String in candidates:
		var node: Variant = gear.get(key)
		if node is Node3D:
			return node as Node3D
	return null


static func _gear_wheel_bounds(root: Node3D, wheel: Node3D) -> Dictionary:
	if wheel == null:
		return {}
	var ancestors: Array[Node3D] = []
	var current: Node = wheel.get_parent()
	while current != null and current != root:
		if current is Node3D:
			ancestors.push_front(current as Node3D)
		current = current.get_parent()
	var transform := Transform3D.IDENTITY
	for node: Node3D in ancestors:
		transform *= node.transform
	var bounds := _subtree_aabb(wheel, transform)
	return {"bounds": bounds.bounds} if bounds.has("found") else {}


static func _gear_support_point(root: Node3D, wheel: Node3D) -> Variant:
	var ancestors: Array[Node3D] = []
	var current: Node = wheel.get_parent()
	while current != null and current != root:
		if current is Node3D:
			ancestors.push_front(current as Node3D)
		current = current.get_parent()
	var transform := Transform3D.IDENTITY
	for node: Node3D in ancestors:
		transform *= node.transform
	var state: Array = [INF, Vector3.ZERO]
	_subtree_lowest_vertex(wheel, transform, state)
	return state[1] if is_finite(float(state[0])) else null


static func _nearest_gear_vertex(mesh: ArrayMesh, surface_roles: Array, point: Vector3) -> Variant:
	var nearest: Vector3
	var best := INF
	for surface in mesh.get_surface_count():
		if surface >= surface_roles.size() or str(surface_roles[surface]) != "gear":
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
		for index: int in indices:
			if index < 0 or index >= vertices.size():
				continue
			var distance := vertices[index].distance_squared_to(point)
			if distance < best:
				best = distance
				nearest = vertices[index]
	return nearest if is_finite(best) else null


static func _subtree_lowest_vertex(node: Node, parent: Transform3D, state: Array) -> void:
	if node is Node3D and not (node as Node3D).visible:
		return
	var transform := parent
	if node is Node3D:
		transform = parent * (node as Node3D).transform
	var source: Mesh
	if node is MeshInstance3D:
		source = (node as MeshInstance3D).mesh
	elif node is ImporterMeshInstance3D:
		var imported: ImporterMesh = (node as ImporterMeshInstance3D).get_mesh()
		source = imported.get_mesh() if imported else null
	if source:
		for surface in source.get_surface_count():
			if source is ArrayMesh and (source as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
			for index: int in indices:
				if index < 0 or index >= vertices.size():
					continue
				var vertex: Vector3 = vertices[index]
				var candidate := transform * vertex
				if candidate.y < float(state[0]):
					state[0] = candidate.y
					state[1] = candidate
	for child in node.get_children():
		_subtree_lowest_vertex(child, transform, state)


static func _subtree_aabb(node: Node, parent: Transform3D) -> Dictionary:
	if node is Node3D and not (node as Node3D).visible:
		return {}
	var transform := parent
	if node is Node3D:
		transform = parent * (node as Node3D).transform
	var merged: AABB
	var found := false
	var source: Mesh
	if node is MeshInstance3D:
		source = (node as MeshInstance3D).mesh
	elif node is ImporterMeshInstance3D:
		var imported: ImporterMesh = (node as ImporterMeshInstance3D).get_mesh()
		source = imported.get_mesh() if imported else null
	if source:
		for surface in source.get_surface_count():
			if source is ArrayMesh and (source as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
			for index: int in indices:
				if index < 0 or index >= vertices.size():
					continue
				var point := transform * vertices[index]
				if not found:
					merged = AABB(point, Vector3.ZERO)
					found = true
				else:
					merged = merged.expand(point)
	for child in node.get_children():
		var child_bounds := _subtree_aabb(child, transform)
		if not child_bounds.is_empty():
			var child_box: AABB = child_bounds.bounds
			merged = merged.merge(child_box) if found else child_box
			found = true
	return {"found": true, "bounds": merged} if found else {}


static func _material_key(material: Material) -> String:
	if material == null:
		return "<null>"
	var names: Array[String] = []
	for property: Dictionary in material.get_property_list():
		var name := str(property.name)
		if name in ["resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id", "script"]:
			continue
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			names.append(name)
	names.sort()
	var parts: Array[String] = [material.get_class()]
	for name: String in names:
		parts.append("%s=%s" % [name, _value_key(material.get(name))])
	return "\n".join(parts)


static func _value_key(value: Variant) -> String:
	if value is Resource:
		var resource := value as Resource
		if resource is Shader and resource.resource_path.is_empty():
			return "Shader#%d" % (resource as Shader).code.hash()
		if not resource.resource_path.is_empty():
			return "%s:%s" % [resource.get_class(), resource.resource_path]
		return "%s#%d" % [resource.get_class(), resource.get_instance_id()]
	return var_to_str(value)
