## L6b: positions-only field data -> eight bounded MultiMeshes; no process, RNG or collisions.
extends RefCounted

const Assets = preload("res://render/tree_assets.gd")
const Frames = preload("res://render/frames.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const TREE_SHADER: Shader = preload("res://render/treeline.gdshader")
const SECTORS: int = 8
const POSITION_PACK_OFFSET: int = 8192
const LEGACY_HASH_OFFSET: int = 2400
const EXTENDED_HASH_OFFSET: int = 8192
const FAR_RING_START_M: float = 600.0
const PATCH_SPACING_M: float = 180.0
const PATCH_HASH_OFFSET: int = 32768
# Must match tree_wind.gdshaderinc; angle <= lean/height, even beyond 10m/s.
const WIND_LEAN_M: float = 0.24


## CPU mirror for bounds/tests. Shader owns appearance; values are design estimates (12–25m).
static func identity(north: float, east: float) -> Dictionary:
	var qn: int = roundi(north * 4.0)
	var qe: int = roundi(east * 4.0)
	# Keep the old hash coordinates for every L6b position. Extend only the
	# negative south/west range that did not fit the original unsigned offset.
	var hash_offset: int = LEGACY_HASH_OFFSET
	if qn < -LEGACY_HASH_OFFSET or qe < -LEGACY_HASH_OFFSET:
		hash_offset = EXTENDED_HASH_OFFSET
	var hash_north: int = qn + hash_offset
	var hash_east: int = qe + hash_offset
	var h: int = (hash_north * 7381 + hash_east * 19391 + 6113) % 65521
	h = (h * 25173 + 13849) % 65521
	var r: int = (h * 25173 + 13849) % 65521
	return {species = h % 3, height = 12.0 + 13.0 * float(h % 1024) / 1023.0, yaw = TAU * float(r) / 65521.0}


## CPU mirror of the shader's smooth world-space foliage patch field, for deterministic checks.
static func foliage_patch_value(north: float, east: float) -> float:
	var grid_north: float = north / PATCH_SPACING_M
	var grid_east: float = east / PATCH_SPACING_M
	var cell_north: int = floori(grid_north)
	var cell_east: int = floori(grid_east)
	var blend_north: float = grid_north - float(cell_north)
	var blend_east: float = grid_east - float(cell_east)
	blend_north = blend_north * blend_north * (3.0 - 2.0 * blend_north)
	blend_east = blend_east * blend_east * (3.0 - 2.0 * blend_east)
	var lower: float = lerpf(_patch_value(cell_north, cell_east), _patch_value(cell_north + 1, cell_east), blend_north)
	var upper: float = lerpf(_patch_value(cell_north, cell_east + 1), _patch_value(cell_north + 1, cell_east + 1), blend_north)
	return lerpf(lower, upper, blend_east)


static func _patch_value(cell_north: int, cell_east: int) -> float:
	var hash_north: int = cell_north + PATCH_HASH_OFFSET
	var hash_east: int = cell_east + PATCH_HASH_OFFSET
	var value: int = posmod(hash_north * 7381 + hash_east * 19391 + 6113, 65521)
	value = posmod(value * 25173 + 13849, 65521)
	return float(value % 997) / 498.0 - 1.0


## Compatibility packs custom data as float16: use four exact integer bytes, not metre floats.
static func packed_position(north: float, east: float) -> Color:
	var qn: int = roundi(north * 4.0) + POSITION_PACK_OFFSET
	var qe: int = roundi(east * 4.0) + POSITION_PACK_OFFSET
	return Color(qn >> 8, qn & 255, qe >> 8, qe & 255)


static func unpacked_position(data: Color) -> Vector2:
	return Vector2(
		(data.r * 256.0 + data.g - POSITION_PACK_OFFSET) / 4.0,
		(data.b * 256.0 + data.a - POSITION_PACK_OFFSET) / 4.0
	)


static func sector(north: float, east: float) -> int:
	return mini(SECTORS - 1, int(fposmod(atan2(east, north), TAU) / (TAU / SECTORS)))


## Validated L6b objects only. Owns meshes/materials per field; shares them within that field.
static func build(object_data: Dictionary, pilot: Dictionary) -> Node3D:
	ShaderClock.register() # standalone fields/exported packs must not depend on main.gd initialization
	var result: Node3D = Node3D.new()
	result.name = object_data.id
	result.position = Frames.ned_to_render([pilot.north, pilot.east, pilot.down])
	var catalog: Dictionary = Assets.catalog()
	var mesh: ArrayMesh = Assets.card_mesh("CommonTree_1")
	var foliage_mask: Texture2D = load(String(catalog.catalog.get("foliage_mask", ""))) as Texture2D
	if not catalog.ok or mesh == null or foliage_mask == null:
		push_error("L6b tree atlas/catalog/material mask missing or invalid")
		return result
	var sizes: Vector3 = Vector3.ZERO
	var ids: Array[String] = ["CommonTree_1", "CommonTree_3", "Pine_1"]
	for entry: Dictionary in catalog.catalog.species:
		sizes[ids.find(entry.id)] = float(entry.frame_size_m)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TREE_SHADER
	material.set_shader_parameter("atlas", load(catalog.catalog.atlas))
	material.set_shader_parameter("foliage_mask", foliage_mask)
	material.set_shader_parameter("frame_sizes", sizes)
	mesh.surface_set_material(0, material)
	var near_groups: Array = []
	var far_groups: Array = []
	for _index: int in SECTORS:
		near_groups.append([])
		far_groups.append([])
	for point: Array in object_data.positions:
		var group_index: int = sector(point[0], point[1])
		var radius: float = sqrt(float(point[0]) * float(point[0]) + float(point[1]) * float(point[1]))
		if radius <= FAR_RING_START_M:
			near_groups[group_index].append(point)
		else:
			far_groups[group_index].append(point)
	for index: int in SECTORS:
		var near_points: Array = near_groups[index]
		var far_points: Array = far_groups[index]
		var points: Array = near_points.duplicate()
		points.append_array(far_points)
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
			# A rotation through theta moves a point by at most length(point)*theta.
			# Include all atlas padding, every wind direction and the saturated peak.
			var max_radius: float = sqrt(radius * radius + pow((0.5 + frame * 0.5) * height, 2.0))
			tree_bounds = tree_bounds.grow(max_radius * WIND_LEAN_M / height)
			bounds = tree_bounds if instance == 0 else bounds.merge(tree_bounds)
		multimesh.custom_aabb = bounds.grow(0.02) # float32 trig/transform rounding allowance, metres
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = "Sector%d" % index
		node.multimesh = multimesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Preserve the eight-draw contract while giving capture tools a stable way
		# to show the near ring only (visible_instance_count includes the near prefix).
		node.set_meta("near_instance_count", near_points.size())
		node.set_meta("far_instance_count", far_points.size())
		result.add_child(node)
	return result
