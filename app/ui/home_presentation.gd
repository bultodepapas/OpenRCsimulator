# UI-25-R2: render-only support/framing for the existing aircraft. Never advances a session.
extends RefCounted

const Retraction = preload("res://aircraft/retractable_model.gd")

static func relative(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != root and current != null:
		if current is Node3D: result = current.transform * result
		current = current.get_parent()
	return result


static func mesh_bounds(root: Node3D, subtree: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var meshes := subtree.find_children("*", "MeshInstance3D", true, false)
	if subtree is MeshInstance3D: meshes.push_front(subtree)
	for item in meshes:
		var mesh := item as MeshInstance3D
		if mesh.mesh == null: continue
		var current: Node = mesh
		var visible := true
		while current != root and current != null:
			if current is Node3D: visible = visible and current.visible
			current = current.get_parent()
		if not visible: continue
		var box: AABB = relative(root, mesh) * mesh.get_aabb()
		result = result.merge(box) if found else box
		found = true
	return result


static func prepare(aircraft: Dictionary) -> Dictionary:
	var root: Node3D = aircraft.root
	var rig: Dictionary = aircraft.get("gear_retraction", {})
	if not rig.is_empty(): Retraction.apply(rig, 1.0)
	else:
		var builder: Script = aircraft.get("_model_builder")
		if builder != null and builder.has_method("set_gear"): builder.call("set_gear", aircraft, 1.0)
	var contacts := PackedVector3Array()
	var skids: Dictionary = aircraft.get("skids", {})
	if not skids.is_empty():
		for point: Vector3 in skids.values(): contacts.append(point + aircraft.get("cg_model_m", Vector3.ZERO))
	else:
		var keys: Dictionary = aircraft.get("model_manifest", {}).get("bindings", {}).get("gear", {}).get("keys", {})
		var gear: Dictionary = aircraft.get("gear", {})
		for role in ["left", "right", "nose", "tail"]:
			var wheel: Node3D = gear.get(str(keys.get(role, role)))
			if wheel == null: continue
			var box := mesh_bounds(root, wheel)
			if box.size.length_squared() > 0.000001:
				contacts.append(Vector3(box.get_center().x, box.position.y, box.get_center().z))
	var alignment := Basis.IDENTITY
	var rest := {}
	if contacts.is_empty():
		# A gearless airplane (the X8) rests on its own hull.
		rest = hull_rest(root, aircraft.get("propeller") as Node3D)
		if not rest.is_empty():
			contacts = rest.contacts
			alignment = rest.alignment
	elif contacts.size() >= 3:
		var normal := (contacts[1] - contacts[0]).cross(contacts[2] - contacts[0]).normalized()
		if normal.dot(Vector3.UP) < 0.0: normal = -normal
		if normal.length_squared() > 0.5: alignment = Basis(Quaternion(normal, Vector3.UP))
	var lift := 1.0
	if contacts.size() >= 3:
		lift = -INF
		for point in contacts: lift = maxf(lift, -(alignment * point).y)
	var result := {"bounds": mesh_bounds(root, root), "alignment": alignment, "lift": lift + 0.005,
		"contacts": contacts, "grounded": contacts.size() >= 3}
	if rest.has("propeller_angle"): result.propeller_angle = rest.propeller_angle
	return result


## Render-only hull rest for an airplane without wheels or skids: wings level, on the side-view lower convex hull
## edge of its visible vertices that lies under their mid-length; the propeller is excluded and its blades are
## turned level (`propeller_angle`) so they clear the field. Contacts are the vertices within 2 mm of that edge;
## empty when none lies at least 1 cm off the centre line (no supported roll).
static func hull_rest(root: Node3D, propeller: Node3D) -> Dictionary:
	var points := PackedVector3Array()
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		if mesh.mesh == null or not _visible(root, mesh): continue
		if propeller != null and (mesh == propeller or propeller.is_ancestor_of(mesh)): continue
		var to_root := relative(root, mesh)
		for surface in mesh.mesh.get_surface_count():
			for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: points.append(to_root * vertex)
	if points.size() < 3: return {}
	var side: Array[Vector2] = []
	var front := INF
	var back := -INF
	for point in points:
		side.append(Vector2(point.z, point.y))
		front = minf(front, point.z)
		back = maxf(back, point.z)
	side.sort()
	var hull: Array[Vector2] = []
	for q in side:
		while hull.size() >= 2 and (hull[-1] - hull[-2]).cross(q - hull[-2]) <= 0.0: hull.pop_back()
		hull.append(q)
	var middle := (front + back) * 0.5
	var run := Vector2.ZERO
	var start := Vector2.ZERO
	for i in range(1, hull.size()):
		if hull[i - 1].x <= middle and middle <= hull[i].x:
			start = hull[i - 1]
			run = hull[i] - hull[i - 1]
			break
	if run.x <= 0.0: return {}
	var up := Vector2(-run.y, run.x).normalized()
	var contacts := PackedVector3Array()
	var spread := 0.0
	for point in points:
		if (Vector2(point.z, point.y) - start).dot(up) <= 0.002:
			contacts.append(point)
			spread = maxf(spread, absf(point.x))
	if contacts.size() < 3 or spread < 0.01: return {}
	var result := {"contacts": contacts, "alignment": Basis(Quaternion(Vector3(0.0, up.y, up.x), Vector3.UP))}
	if propeller != null:
		# Blade vertices in the propeller frame; the parked angle (2° steps) keeps the lowest blade point highest.
		var blades := PackedVector3Array()
		var meshes := propeller.find_children("*", "MeshInstance3D", true, false)
		if propeller is MeshInstance3D: meshes.push_front(propeller)
		for item in meshes:
			var mesh := item as MeshInstance3D
			if mesh.mesh == null: continue
			var to_hub := relative(propeller, mesh)
			for surface in mesh.mesh.get_surface_count():
				for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: blades.append(to_hub * vertex)
		var original := propeller.rotation.z
		var best := -INF
		for step in 90:
			propeller.rotation.z = original + deg_to_rad(2.0 * step)
			var to_root := Transform3D(result.alignment, Vector3.ZERO) * relative(root, propeller)
			var lowest := INF
			for vertex in blades: lowest = minf(lowest, (to_root * vertex).y)
			if lowest > best:
				best = lowest
				result.propeller_angle = propeller.rotation.z
		propeller.rotation.z = original
	return result


static func _visible(root: Node3D, node: Node) -> bool:
	var current: Node = node
	while current != root and current != null:
		if current is Node3D and not current.visible: return false
		current = current.get_parent()
	return true


static func fit(camera: Camera3D, aircraft_root: Node3D, bounds: AABB, viewport_size: Vector2,
		azimuth_degrees := 32.0, fov_degrees := 40.0) -> Rect2:
	var aspect := maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.1)
	camera.fov = fov_degrees
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var azimuth := deg_to_rad(azimuth_degrees)
	var forward := Vector3(-sin(azimuth), -0.16, cos(azimuth)).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var center := aircraft_root.transform * bounds.get_center()
	var tangent := tan(deg_to_rad(fov_degrees) * 0.5)
	var distance := 1.5
	for i in 8:
		var offset := aircraft_root.transform * bounds.get_endpoint(i) - center
		var depth := offset.dot(forward)
		var horizontal := offset.dot(right) / (tangent * aspect)
		var vertical := offset.dot(up) / tangent
		# Solve the off-axis perspective inequalities for every bounding corner.
		# Reserve the left 36% for navigation and keep the model inside 96%/88%.
		distance = maxf(distance, (horizontal - 0.92 * depth) / (0.92 - 0.30))
		distance = maxf(distance, (-horizontal - 0.28 * depth) / (0.28 + 0.30))
		distance = maxf(distance, (vertical - 0.70 * depth) / (0.70 + 0.14))
		distance = maxf(distance, (-vertical - 0.76 * depth) / (0.76 - 0.14))
	distance *= 1.03
	var half_height := distance * tangent
	# Put the subject right of navigation, above the session summary.
	camera.position = center - forward * distance - right * (half_height * aspect * 0.30) + up * (half_height * 0.14)
	camera.look_at_from_position(camera.position, camera.position + forward, Vector3.UP)
	var rectangle := Rect2(camera.unproject_position(aircraft_root.transform * bounds.get_endpoint(0)), Vector2.ZERO)
	for i in range(1, 8): rectangle = rectangle.expand(camera.unproject_position(aircraft_root.transform * bounds.get_endpoint(i)))
	return rectangle


