## Small, visual-only CC0 source meshes beside the club pavilion. No physics bodies or handmade geometry.
extends RefCounted

const Frames := preload("res://render/frames.gd")
const ROCK_SCENES := [
	preload("res://assets/landscape/airfield_detail/quaternius_rocks/Rock_Medium_1.gltf"),
	preload("res://assets/landscape/airfield_detail/quaternius_rocks/Rock_Medium_2.gltf"),
	preload("res://assets/landscape/airfield_detail/quaternius_rocks/Rock_Medium_3.gltf"),
]
const FLOWER_SCENE: PackedScene = preload("res://assets/landscape/airfield_detail/flower_empodium/flower_empodium_1k.gltf")
const FLOWER_SHADER: Shader = preload("res://scenery/airfield_flower.gdshader")

const STONES := [
	[-15.4, -5.4, 0, 0.10], [-15.5, 5.3, 1, 0.10],
	[-15.1, -4.5, 2, 0.08], [-15.0, 4.5, 0, 0.08],
]


static func build(field: Dictionary, scenery: Dictionary, quality: String) -> Node3D:
	var root := Node3D.new()
	root.name = "AirfieldDetail"
	if str(field.get("id", "")) != "default" or str(scenery.get("theme", "")) != "temperate":
		return root
	var rock_meshes: Array[Mesh] = []
	for rock_scene: PackedScene in ROCK_SCENES:
		rock_meshes.append_array(_meshes(rock_scene))
	var flower_meshes := _meshes(FLOWER_SCENE)
	if rock_meshes.size() < 3 or flower_meshes.size() < 5:
		push_error("Airfield detail source glTF meshes are incomplete")
		return root
	var rock_limit := 4 if quality == "high" else 3 if quality == "balanced" else 2
	var flower_stride := 1 if quality == "high" else 2
	var groups: Dictionary = {}
	var flower_material := ShaderMaterial.new()
	flower_material.shader = FLOWER_SHADER
	flower_material.set_shader_parameter("diffuse_map", load(
		"res://assets/landscape/airfield_detail/flower_empodium/textures/flower_empodium_diff_1k.jpg"))
	flower_material.set_shader_parameter("alpha_map", load(
		"res://assets/landscape/airfield_detail/flower_empodium/textures/flower_empodium_alpha_1k.jpg"))
	for i in rock_limit:
		var record: Array = STONES[i]
		var variant := int(record[2])
		_append(groups, "rock_%d" % variant, rock_meshes[variant],
			float(record[0]), float(record[1]), float(record[3]), float(i) * 2.15)
	# Two narrow, irregular flower beds already edged by the pavilion's planted verge.
	# The 0.14–0.27 m source plants vary to 0.22–0.48 m, clear of the flight surface.
	for side in [-1, 1]:
		for index in range(2):
			if index % flower_stride != 0:
				continue
			var jitter := _hash(index + 37 * side)
			var north := -15.15 + (jitter - 0.5) * 0.18
			var east := float(side) * (2.55 + float(index) * 1.55 + (jitter - 0.5) * 0.15)
			var variant := index
			var scale := 1.48 + 0.30 * _hash(index + side * 53)
			_append(groups, "flower_%d" % variant, flower_meshes[variant], north, east, scale,
				float(index * 13 + side * 7) * 0.39)
	var triangles := 0
	var instances := 0
	for key: String in groups:
		var group: Dictionary = groups[key]
		var transforms: Array = group.transforms
		var mesh: Mesh = group.mesh
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = key
		instance.multimesh = multimesh
		if key.begins_with("flower"):
			instance.material_override = flower_material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.visibility_range_end = 85.0 if key.begins_with("flower") else 110.0
		root.add_child(instance)
		instances += transforms.size()
		for surface in mesh.get_surface_count():
			triangles += mesh.surface_get_array_index_len(surface) / 3 * transforms.size()
	root.set_meta("instances", instances)
	root.set_meta("triangles", triangles)
	root.set_meta("batches", root.get_child_count())
	return root


static func _meshes(scene: PackedScene) -> Array[Mesh]:
	var temporary := scene.instantiate()
	var result: Array[Mesh] = []
	_collect(temporary, result)
	temporary.free()
	return result


static func _collect(node: Node, result: Array[Mesh]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result.append((node as MeshInstance3D).mesh)
	for child in node.get_children():
		_collect(child, result)


static func _append(groups: Dictionary, key: String, mesh: Mesh, north: float, east: float,
		scale: float, yaw: float) -> void:
	if not groups.has(key):
		groups[key] = {"mesh": mesh, "transforms": []}
	var origin := Frames.ned_to_render([north, east, 0.0])
	origin.y = -mesh.get_aabb().position.y * scale - 0.018
	var transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), origin)
	(groups[key].transforms as Array).append(transform)


static func _hash(value: int) -> float:
	return float(posmod(value * 1103515245 + 12345, 65536)) / 65535.0
