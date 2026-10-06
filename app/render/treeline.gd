## L6b: positions-only field data -> eight bounded MultiMeshes; no process, RNG or collisions.
extends RefCounted

const Assets = preload("res://render/tree_assets.gd")
const Frames = preload("res://render/frames.gd")
const TREE_SHADER: Shader = preload("res://render/treeline.gdshader")
const SECTORS: int = 8


## CPU mirror for bounds/tests. Shader owns appearance; values are design estimates (12–25m).
static func identity(north: float, east: float) -> Dictionary:
	var qn: int = int(round(north * 4.0)) + 2400
	var qe: int = int(round(east * 4.0)) + 2400
	var h: int = (qn * 7381 + qe * 19391 + 6113) % 65521
	h = (h * 25173 + 13849) % 65521
	var r: int = (h * 25173 + 13849) % 65521
	return {species = h % 3, height = 12.0 + 13.0 * float(h % 1024) / 1023.0, yaw = TAU * float(r) / 65521.0}


## Compatibility packs custom data as float16: use four exact integer bytes, not metre floats.
static func packed_position(north: float, east: float) -> Color:
	var qn: int = int(round(north * 4.0)) + 2400
	var qe: int = int(round(east * 4.0)) + 2400
	return Color(qn >> 8, qn & 255, qe >> 8, qe & 255)


static func unpacked_position(data: Color) -> Vector2:
	return Vector2((data.r * 256.0 + data.g - 2400.0) / 4.0, (data.b * 256.0 + data.a - 2400.0) / 4.0)


static func sector(north: float, east: float) -> int:
	return mini(SECTORS - 1, int(fposmod(atan2(east, north), TAU) / (TAU / SECTORS)))


## Validated L6b objects only. Owns meshes/materials per field; shares them within that field.
static func build(object_data: Dictionary, pilot: Dictionary) -> Node3D:
	var result: Node3D = Node3D.new()
	result.name = object_data.id
	result.position = Frames.ned_to_render([pilot.north, pilot.east, pilot.down])
	var catalog: Dictionary = Assets.catalog()
	var mesh: ArrayMesh = Assets.card_mesh("CommonTree_1")
	if not catalog.ok or mesh == null:
		push_error("L6b tree atlas/catalog missing or invalid")
		return result
	var sizes: Vector3 = Vector3.ZERO
	var ids: Array[String] = ["CommonTree_1", "CommonTree_3", "Pine_1"]
	for entry: Dictionary in catalog.catalog.species:
		sizes[ids.find(entry.id)] = float(entry.frame_size_m)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TREE_SHADER
	material.set_shader_parameter("atlas", load(catalog.catalog.atlas))
	material.set_shader_parameter("frame_sizes", sizes)
	mesh.surface_set_material(0, material)
	var groups: Array = []
	for _index: int in SECTORS:
		groups.append([])
	for point: Array in object_data.positions:
		groups[sector(point[0], point[1])].append(point)
	for index: int in SECTORS:
		var points: Array = groups[index]
		if points.is_empty():
			continue
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		multimesh.instance_count = points.size()
		var bounds: AABB = AABB()
		for instance: int in points.size():
			var p: Array = points[instance]
			var origin: Vector3 = Frames.ned_to_render(p)
			multimesh.set_instance_transform(instance, Transform3D(Basis.IDENTITY, origin))
			multimesh.set_instance_custom_data(instance, packed_position(p[0], p[1]))
			var shape: Dictionary = identity(p[0], p[1])
			var frame: float = sizes[int(shape.species)]
			var height: float = shape.height
			# Enclose every rotated card vertex, including transparent below-ground padding.
			var radius: float = frame * height * 0.5
			var tree_bounds: AABB = AABB(origin + Vector3(-radius, (0.5 - frame * 0.5) * height, -radius), Vector3(2.0 * radius, frame * height, 2.0 * radius))
			bounds = tree_bounds if instance == 0 else bounds.merge(tree_bounds)
		multimesh.custom_aabb = bounds.grow(0.02) # float32 trig/transform rounding allowance, metres
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = "Sector%d" % index
		node.multimesh = multimesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		result.add_child(node)
	return result
