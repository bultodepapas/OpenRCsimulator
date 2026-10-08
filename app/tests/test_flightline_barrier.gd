# L10c: merged flightline barrier geometry preserves its opening, dimensions, and shared post layout.
# Run: godot --headless --path app --script res://tests/test_flightline_barrier.gd
extends SceneTree

const Barrier = preload("res://render/flightline_barrier.gd")
const Frames = preload("res://render/frames.gd")
const Loader = preload("res://data/field_loader.gd")
const DEFAULT_PATH: String = "res://data/fields/default.json"
const FOOT_WIDTH_M: float = 0.08
const MAX_BAY_SPAN_M: float = 2.4
const FIRST_SLAT_CENTRE_M: float = 0.225
const TOP_SLAT_MARGIN_M: float = 0.06
const SLAT_HEIGHT_M: float = 0.05

var _count: int = 0
var _failed: int = 0


func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from(DEFAULT_PATH)
	_check("default field validates", bool(loaded["ok"]), str(loaded["errors"]))
	if not bool(loaded["ok"]):
		quit(1)
		return
	var barriers: Array[Dictionary] = _barriers(loaded["field"]["flight_cues"])
	_check("default field has one normalized barrier", barriers.size() == 1)
	if barriers.size() != 1:
		quit(1)
		return
	var cue: Dictionary = barriers[0]
	_check_mesh(cue)
	_test_boundary_variants(cue)
	print("%d checks, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 else 0)


func _check_mesh(cue: Dictionary) -> void:
	var first: Node3D = Barrier.build(cue)
	var second: Node3D = Barrier.build(cue)
	var mesh_instance: MeshInstance3D = first.get_node("Barrier") as MeshInstance3D
	var repeat_instance: MeshInstance3D = second.get_node("Barrier") as MeshInstance3D
	var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	var repeat_mesh: ArrayMesh = repeat_instance.mesh as ArrayMesh
	var bounds: AABB = mesh.get_aabb()
	_check("mesh dimensions contain exactly its full width, height, and 0.08 m face thickness", bounds.position.is_equal_approx(Vector3(-cue.width * 0.5, 0.0, -0.04)) and bounds.size.is_equal_approx(Vector3(cue.width, cue.height, 0.08)), str(bounds))
	_check("barrier root follows NED field position", first.position.is_equal_approx(Frames.ned_to_render([cue.north, cue.east, 0.0])))
	_check("one mesh and one surface, no processing or collision nodes", first.get_child_count() == 1 and mesh_instance.get_child_count() == 0 and mesh.get_surface_count() == 1 and not first.is_processing() and not mesh_instance.is_processing() and not _has_collision(first))
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var finite_unit: bool = vertices.size() == normals.size()
	for index: int in vertices.size():
		finite_unit = finite_unit and vertices[index].is_finite() and normals[index].is_finite() and absf(normals[index].length() - 1.0) < 0.00001
	_check("all geometry and normals are finite and unit length", finite_unit)
	_check("one merged opaque mesh stays below 1,500 triangles", vertices.size() / 3 < 1500 and mesh.surface_get_material(0).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("repeat build owns distinct, byte-identical mesh data", mesh != repeat_mesh and vertices.to_byte_array() == repeat_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array() and normals.to_byte_array() == repeat_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL].to_byte_array())
	_test_posts_and_bays(cue, vertices)
	_test_opening_and_slats(cue, vertices)
	first.free()
	second.free()


func _test_posts_and_bays(cue: Dictionary, vertices: PackedVector3Array) -> void:
	var positions: PackedVector3Array = Barrier.post_positions(cue)
	var posts_per_bank: int = positions.size() / 2
	_check("shared post helper returns paired banks at ground level", positions.size() >= 4 and positions.size() % 2 == 0 and posts_per_bank >= 2)
	if posts_per_bank < 2:
		return
	_check("outside post and fitting edges meet nominal width", absf(positions[0].x - FOOT_WIDTH_M * 0.5 + cue.width * 0.5) < 0.00001 and absf(positions[positions.size() - 1].x + FOOT_WIDTH_M * 0.5 - cue.width * 0.5) < 0.00001)
	_check("inner posts leave the requested clear gap", absf(positions[posts_per_bank].x - positions[posts_per_bank - 1].x - FOOT_WIDTH_M - cue.gap_width) < 0.00001)
	var spacing_ok: bool = true
	for bank: int in 2:
		var offset: int = bank * posts_per_bank
		for index: int in range(posts_per_bank - 1):
			var left: Vector3 = positions[offset + index]
			var right: Vector3 = positions[offset + index + 1]
			spacing_ok = spacing_ok and absf(left.y) < 0.000001 and absf(left.z) < 0.000001 and absf(right.x - left.x) <= MAX_BAY_SPAN_M + 0.00001
	_check("post spacing keeps every open bay at or below 2.4 m", spacing_ok)
	for index: int in positions.size():
		_check("geometry includes helper post %d" % index, _intersects_z(vertices, 0.4, positions[index].x))


func _test_opening_and_slats(cue: Dictionary, vertices: PackedVector3Array) -> void:
	var positions: PackedVector3Array = Barrier.post_positions(cue)
	var posts_per_bank: int = positions.size() / 2
	var bay_x: float = (positions[0].x + positions[1].x) * 0.5
	var centres: Array[float] = []
	for slat: int in 4:
		var fraction: float = float(slat) / 3.0
		var centre_y: float = lerpf(FIRST_SLAT_CENTRE_M, cue.height - TOP_SLAT_MARGIN_M, fraction)
		centres.append(centre_y)
		_check("open bay has slat row %d" % slat, _intersects_z(vertices, centre_y, bay_x))
	for index: int in 3:
		var clear_y: float = (centres[index] + centres[index + 1]) * 0.5
		_check("slat rows remain visually open at gap %d" % index, not _intersects_z(vertices, clear_y, bay_x))
	_check("central opening has no bridge at the default mid-height", not _intersects_z(vertices, cue.height * 0.5, 0.0))
	_check("central gap stays clear up to its inner faces", not _intersects_z(vertices, cue.height * 0.5, cue.gap_width * 0.5 - 0.01)
		and _intersects_z(vertices, cue.height * 0.5, cue.gap_width * 0.5 + 0.01))
	var no_vertices_inside_gap: bool = true
	for vertex: Vector3 in vertices:
		no_vertices_inside_gap = no_vertices_inside_gap and absf(vertex.x) >= cue.gap_width * 0.5 - 0.00001
	_check("actual mesh vertices do not enter the central opening", no_vertices_inside_gap)


func _test_boundary_variants(default_cue: Dictionary) -> void:
	var boundary_values: Array = [[10.0, 0.5, 2.0], [80.0, 0.9, 2.0]]
	for variant_index: int in boundary_values.size():
		var dimensions: Array = boundary_values[variant_index]
		var width: float = float(dimensions[0])
		var height: float = float(dimensions[1])
		var gap_width: float = float(dimensions[2])
		var variant: Dictionary = default_cue.duplicate()
		variant["width"] = width
		variant["height"] = height
		variant["gap_width"] = gap_width
		var root: Node3D = Barrier.build(variant)
		var mesh: MeshInstance3D = root.get_node("Barrier") as MeshInstance3D
		var bounds: AABB = mesh.mesh.get_aabb()
		_check("boundary dimensions remain contained", bounds.size.is_equal_approx(Vector3(width, height, 0.08)) and absf(bounds.position.x + width * 0.5) < 0.00001 and absf(bounds.position.y) < 0.00001)
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		_check("maximum custom geometry remains below 3,000 triangles", vertices.size() / 3 < 3000, str(vertices.size() / 3))
		var positions: PackedVector3Array = Barrier.post_positions(variant)
		var posts_per_bank: int = positions.size() / 2
		_check("boundary post layout keeps the gap", absf(positions[posts_per_bank].x - positions[posts_per_bank - 1].x - FOOT_WIDTH_M - gap_width) < 0.00001)
		root.free()


func _intersects_z(vertices: PackedVector3Array, y: float, x: float) -> bool:
	var start: Vector3 = Vector3(x, y, -0.1)
	var finish: Vector3 = Vector3(x, y, 0.1)
	for index: int in range(0, vertices.size(), 3):
		if Geometry3D.segment_intersects_triangle(start, finish, vertices[index], vertices[index + 1], vertices[index + 2]) != null:
			return true
	return false


func _has_collision(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child: Node in node.get_children():
		if _has_collision(child):
			return true
	return false


func _barriers(cues: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cue_value: Variant in cues:
		var cue: Dictionary = cue_value
		if cue.get("type") == "flightline_barrier":
			result.append(cue)
	return result


func _check(label: String, passed: bool, detail: String = "") -> void:
	_count += 1
	if not passed:
		_failed += 1
		printerr("FAIL: ", label, " ", detail)
