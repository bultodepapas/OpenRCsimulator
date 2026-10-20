## Render-only RC circuit furniture. Placement uses the accepted track and road sampler.
extends RefCounted

const BOARD_SCENE := preload("res://assets/landscape/track-signage/billboardLow.glb")
const FLAG_SCENE := preload("res://assets/landscape/track-signage/flagCheckersSmall.glb")
const BOARD_SCALE := 1.35
const FLAG_SCALE := 2.65


static func add(root: Node3D, track: Dictionary, road: Callable) -> void:
	if root == null or track.is_empty() or not road.is_valid():
		return
	var furniture := Node3D.new()
	furniture.name = "TrackFurniture"
	root.add_child(furniture)
	var es := TranslationServer.get_locale().begins_with("es")
	var access: Dictionary = track.get("access", {})
	var access_east := float(access.get("east_m", -10.0))
	var access_half := float(access.get("width_m", 2.6)) * 0.5
	_add_board(furniture, road, "AccessSign", "CIRCUITO RC" if es else "RC CIRCUIT",
		"ACCESO" if es else "ACCESS", access_east - access_half - float(track.get("shoulder_m", 1.2)) - 1.0,
		float(access.get("north_min_m", 22.2)) + 0.6, 0.0, Color("#263b3d"))
	_add_board(furniture, road, "JumpsSign", "SALTOS" if es else "JUMPS",
		"01  /  02", 1.0, 35.25, -PI * 0.5, Color("#333d38"))
	_add_board(furniture, road, "SlalomSign", "ESLALON" if es else "SLALOM",
		"03", 21.9, 45.0, -PI * 0.5, Color("#333d38"))
	_add_board(furniture, road, "RollersSign", "ONDULACIONES" if es else "ROLLERS",
		"01  /  02  /  03", 0.0, 55.1, PI * 0.5, Color("#333d38"))
	_add_start_equipment(furniture, track, road)


static func _add_board(parent: Node3D, road: Callable, board_name: String,
		title: String, detail: String, east: float, north: float, yaw: float,
		panel_color: Color) -> void:
	var sample: Variant = road.call(north, east)
	if typeof(sample) != TYPE_DICTIONARY or not is_finite(float(sample.get("height_m", NAN))):
		return
	var sign_root := Node3D.new()
	sign_root.name = board_name
	sign_root.position = Vector3(east, float(sample.height_m) + 0.006, -north)
	sign_root.rotation.y = yaw
	parent.add_child(sign_root)
	var source := BOARD_SCENE.instantiate() as Node3D
	var model := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var bounds := model.mesh.get_aabb()
	var frame := MeshInstance3D.new()
	frame.name = "ReusedBracedFrame"
	frame.mesh = model.mesh
	frame.scale = Vector3.ONE * BOARD_SCALE
	frame.position = Vector3(-bounds.get_center().x, -bounds.position.y,
		-bounds.get_center().z) * BOARD_SCALE
	# Hide the kit's fictional sponsor face and use its four modeled material groups.
	frame.set_surface_override_material(0, _material(Color("#747b74"), 0.55, 0.57))
	frame.set_surface_override_material(1, _material(Color("#414a49"), 0.72, 0.28))
	frame.set_surface_override_material(2, _material(panel_color, 0.82, 0.1))
	frame.set_surface_override_material(3, _material(Color("#929990"), 0.56, 0.55))
	sign_root.add_child(frame)
	source.free()
	var face_z := bounds.size.z * BOARD_SCALE * 0.5 + 0.009
	var title_label := Label3D.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.font_size = 64
	title_label.pixel_size = 0.004 if title.length() <= 9 else 0.00215
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.modulate = Color("#f2eee2")
	title_label.outline_size = 4
	title_label.outline_modulate = Color("#1a211f")
	title_label.position = Vector3(0.0, 0.65, face_z)
	sign_root.add_child(title_label)
	var sub_label := Label3D.new()
	sub_label.name = "Detail"
	sub_label.text = detail
	sub_label.font_size = 48
	sub_label.pixel_size = 0.00225
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_label.modulate = Color("#e0c887")
	sub_label.position = Vector3(0.0, 0.39, face_z)
	sign_root.add_child(sub_label)
	_box(sign_root, "ReflectiveTopRail", Vector3(1.15, 0.025, 0.006),
		Vector3(0.0, 0.86, face_z + 0.002), _material(Color("#d9c27e"), 0.55, 0.1))
	for x in [-0.55, 0.55]:
		for y in [0.37, 0.84]:
			_sphere(sign_root, "FaceRivet", 0.012, Vector3(x, y, face_z + 0.006),
				_material(Color("#aeb5aa"), 0.4, 0.65))


static func _add_start_equipment(parent: Node3D, track: Dictionary, road: Callable) -> void:
	var start: Dictionary = {}
	for value in track.get("spawns", []):
		if typeof(value) == TYPE_DICTIONARY and str(value.get("id", "")) == "track_start":
			start = value
			break
	if start.is_empty():
		return
	var center_north := float(track.get("center_north_m", start.get("north_m", 39.0))) - float(track.get("radius_m", 6.0))
	# The painted staging line sits in the access merge. Place freestanding gear
	# downstream of that merge, before the first tabletop, clear of access traffic.
	var gate_east := float(track.get("center_east_m", 0.0)) - float(track.get("half_straight_m", 12.0)) + 5.9
	var post_offset := float(track.get("lane_width_m", 3.2)) * 0.5 + 0.72
	var gate := Node3D.new()
	gate.name = "StartTimingGate"
	parent.add_child(gate)
	for side in [-1.0, 1.0]:
		var post_north: float = center_north + float(side) * post_offset
		var sample: Variant = road.call(post_north, gate_east)
		if typeof(sample) != TYPE_DICTIONARY or not is_finite(float(sample.get("height_m", NAN))):
			continue
		var post := Node3D.new()
		post.name = "SouthTimingPost" if side < 0.0 else "NorthTimingPost"
		post.position = Vector3(gate_east, float(sample.height_m) + 0.004, -post_north)
		post.rotation.y = PI if side < 0.0 else 0.0
		gate.add_child(post)
		_box(post, "AnchorPlate", Vector3(0.20, 0.022, 0.20), Vector3(0.0, 0.011, 0.0),
			_material(Color("#555d5a"), 0.63, 0.55))
		_cylinder(post, "GalvanizedMast", 0.019, 0.51, Vector3(0.0, 0.27, 0.0),
			_material(Color("#9ca9a2"), 0.46, 0.62))
		_box(post, "OpticalHead", Vector3(0.16, 0.11, 0.12), Vector3(0.0, 0.55, 0.012),
			_material(Color("#272d2d"), 0.67, 0.12))
		_box(post, "OpticalWindow", Vector3(0.09, 0.045, 0.004), Vector3(0.0, 0.55, 0.075),
			_material(Color("#181d20"), 0.22, 0.1))
		_sphere(post, "StatusLens", 0.015, Vector3(-0.052, 0.59, 0.075),
			_material(Color("#a75c3f"), 0.18, 0.05))
		_add_flag(gate, road, gate_east - 0.8, post_north, side)


static func _add_flag(parent: Node3D, road: Callable, east: float, north: float, side: float) -> void:
	var sample: Variant = road.call(north, east)
	if typeof(sample) != TYPE_DICTIONARY or not is_finite(float(sample.get("height_m", NAN))):
		return
	var flag_root := Node3D.new()
	flag_root.name = "SouthCheckeredFlag" if side < 0.0 else "NorthCheckeredFlag"
	flag_root.position = Vector3(east, float(sample.height_m) + 0.003, -north)
	parent.add_child(flag_root)
	var source := FLAG_SCENE.instantiate() as Node3D
	var model := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var flag := MeshInstance3D.new()
	flag.name = "ReusedCheckeredClothAndPole"
	flag.mesh = model.mesh
	flag.scale = Vector3.ONE * FLAG_SCALE
	flag.rotation.z = 0.055 if side < 0.0 else -0.055
	var cloth := model.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	cloth.albedo_color = Color("#d7d4c8")
	cloth.roughness = 0.92
	flag.set_surface_override_material(0, cloth)
	flag.set_surface_override_material(2, _material(Color("#8d9893"), 0.5, 0.55))
	flag_root.add_child(flag)
	source.free()
	_box(flag_root, "GroundSocket", Vector3(0.16, 0.025, 0.16), Vector3(0.035, 0.012, -0.035),
		_material(Color("#59615d"), 0.62, 0.58))


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


static func _box(parent: Node3D, name_value: String, size: Vector3,
		position_value: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)


static func _cylinder(parent: Node3D, name_value: String, radius: float, height: float,
		position_value: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)


static func _sphere(parent: Node3D, name_value: String, radius: float,
		position_value: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
