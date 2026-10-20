## TT-20: factory-style lamps and lens locations; all coordinates are render-only.
extends RefCounted

const Imported := preload("res://aircraft/imported_model.gd")

static func apply(root: Node3D) -> void:
	if root.has_meta("timber_factory_lights"):
		return
	root.set_meta("timber_factory_lights", true)
	root.set_meta("light_groups", ["navigation", "strobe", "landing"])
	var anchors := {nav_tail = {enabled = false}, strobe_left = {enabled = false}, strobe_right = {enabled = false}}
	for side: String in ["left", "right"]:
		var wing := root.find_child("wing_" + side + "_fixed", true, false) as MeshInstance3D
		if wing == null:
			continue
		var nav := _material_center(wing, "light_red" if side == "left" else "light_green")
		anchors["nav_" + side] = _anchor(root, wing, nav)
	var cowl := root.find_child("cowl", true, false) as Node3D
	if cowl != null:
		for side: float in [-1.0, 1.0]:
			var landing := Vector3(side * 0.035, -0.035, -0.213)
			anchors["landing" if side < 0 else "landing_right"] = _anchor(root, cowl, landing)
			_landing_lens(cowl, landing)
	var fuselage := root.find_child("fuselage_core", true, false) as Node3D
	if fuselage != null:
		anchors.strobe_dorsal = _anchor(root, fuselage, Vector3(0, 0.056, 0.288))
		anchors.strobe_ventral = _anchor(root, fuselage, Vector3(0, -0.099, 0.400))
	root.set_meta("light_anchors", anchors)

static func _landing_lens(host: Node3D, landing: Vector3) -> void:
	var lens := MeshInstance3D.new()
	lens.name = "TimberLandingLens"
	var mesh := SphereMesh.new()
	mesh.radius = 0.006
	mesh.height = 0.012
	mesh.radial_segments = 16
	mesh.rings = 8
	lens.mesh = mesh
	lens.position = landing
	lens.scale = Vector3(1.0, 1.0, 0.3)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#d7e4e6")
	material.metallic = 0.35
	material.roughness = 0.18
	lens.material_override = material
	lens.set_meta("crash_no_bounds", true)
	host.add_child(lens)

static func _anchor(root: Node3D, host: Node3D, local: Vector3) -> Dictionary:
	return {position = Imported.relative(root, host) * local,
		follow = root.get_path_to(host), follow_offset = local}

static func _material_center(mesh: MeshInstance3D, name: String) -> Vector3:
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		if material == null or material.resource_name != name:
			continue
		var points: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var box := AABB(points[0], Vector3.ZERO)
		for point in points:
			box = box.expand(point)
		return box.get_center()
	return Vector3.ZERO
