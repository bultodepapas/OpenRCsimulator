# L10c: merged flightline barrier geometry preserves its opening, dimensions, and shared post layout.
# Run: godot --headless --path app --script res://tests/test_flightline_barrier.gd
extends SceneTree

const Barrier = preload("res://render/flightline_barrier.gd")
const Planting = preload("res://render/flightline_barrier_planting.gd")
const Plants = preload("res://scenery/imported_vegetation.gd")
const Frames = preload("res://render/frames.gd")
const Loader = preload("res://data/field_loader.gd")
const DEFAULT_PATH: String = "res://data/fields/default.json"
const FOOT_WIDTH_M: float = 0.08
const MAX_BAY_SPAN_M: float = 2.4
const FIRST_SLAT_CENTRE_M: float = 0.24
const TOP_SLAT_MARGIN_M: float = 0.06

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
	_check("one barrier surface plus grounded planting, no processing or collision nodes", first.get_child_count() == 2 and mesh_instance.get_child_count() == 0 and mesh.get_surface_count() == 1 and not first.is_processing() and not mesh_instance.is_processing() and not _has_collision(first))
	_check_planting(first, second, cue)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var finite_unit: bool = vertices.size() == normals.size()
	for index: int in vertices.size():
		finite_unit = finite_unit and vertices[index].is_finite() and normals[index].is_finite() and absf(normals[index].length() - 1.0) < 0.00001
	_check("all geometry and normals are finite and unit length", finite_unit)
	var material := mesh.surface_get_material(0) as ShaderMaterial
	_check("one merged opaque fitted mesh stays below 40,000 triangles", vertices.size() / 3 < 40000 and material != null and not material.shader.code.contains("ALPHA =") and mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, str(vertices.size() / 3))
	_check_detail(mesh_instance, vertices, normals)
	_check("repeat build owns distinct, byte-identical mesh data", mesh != repeat_mesh and vertices.to_byte_array() == repeat_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array() and normals.to_byte_array() == repeat_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL].to_byte_array())
	_test_posts_and_bays(cue, vertices)
	_test_opening_and_slats(cue, vertices)
	_check_rail_sections(cue)
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
	var boundary_values: Array = [[10.0, 0.5, 2.0], [10.0, 0.5, 6.0], [80.0, 0.9, 2.0], [80.0, 0.9, 12.0]]
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
		_check("maximum custom fitted geometry remains below 75,000 triangles", vertices.size() / 3 < 75000, str(vertices.size() / 3))
		var positions: PackedVector3Array = Barrier.post_positions(variant)
		var posts_per_bank: int = positions.size() / 2
		_check("boundary post layout keeps the gap", absf(positions[posts_per_bank].x - positions[posts_per_bank - 1].x - FOOT_WIDTH_M - gap_width) < 0.00001)
		_check_rail_sections(variant)
		_check_planting(root, null, variant)
		root.free()


func _check_rail_sections(cue: Dictionary) -> void:
	var rail_parts: Array[Dictionary] = []
	for part: Dictionary in Barrier.parts(cue):
		if part.profile == "wood":
			rail_parts.append(part)
	var proportions_ok: bool = not rail_parts.is_empty()
	var openings_ok: bool = true
	for index: int in range(0, rail_parts.size(), 4):
		var previous_top: float = 0.0
		for row: int in 4:
			var rail: Dictionary = rail_parts[index + row]
			var size: Vector3 = rail.size
			var bottom: float = rail.base.y
			var expected_height: float = 0.08 if row == 3 else 0.065
			proportions_ok = proportions_ok and absf(size.z - 0.045) < 0.00001 and size.y <= expected_height + 0.00001
			openings_ok = openings_ok and bottom >= previous_top + (0.025 if row > 0 else 0.2) - 0.00001
			previous_top = bottom + size.y
	_check("all timber sections keep their designed height and 45 mm depth", proportions_ok)
	_check("all bays retain ground clearance and at least 25 mm open rail slots", openings_ok)


func _check_planting(first: Node3D, second: Node3D, cue: Dictionary) -> void:
	var plants := first.get_node("PostVegetation") as Node3D
	var records: Array = plants.get_meta("layout")
	var positions: PackedVector3Array = Barrier.post_positions(cue)
	var counts := PackedInt32Array()
	var tallest := PackedFloat32Array()
	counts.resize(positions.size())
	tallest.resize(positions.size())
	var source_triangles := 0
	var baseline_instances := 0
	var baseline_triangles := 0
	var wispy_triangles: int = Plants.get_asset("grass_wispy_tall").source_triangles
	var short_triangles: int = Plants.get_asset("grass_common_short").source_triangles
	var clover_triangles: int = Plants.get_asset("clover_1").source_triangles
	for i in positions.size():
		baseline_instances += 4 + i % 3
		baseline_triangles += 2 * wispy_triangles + short_triangles + (1 + i % 3) * clover_triangles
	var by_seed := {}
	var indices_ok := true
	for record: Dictionary in records:
		var index := int(record.post)
		if index < 0 or index >= positions.size():
			indices_ok = false
			continue
		counts[index] += 1
		tallest[index] = maxf(tallest[index], float(record.height))
		source_triangles += int(Plants.get_asset(record.asset).source_triangles)
		by_seed[record.seed] = [record.asset, record.transform, record.height]
	var bank_size := positions.size() / 2
	var gate_left := bank_size - 1
	var gate_right := bank_size
	_check("plant records identify their post", indices_ok and by_seed.size() == records.size())
	_check("gate groups stay sparse and lower than the outer groups", counts[gate_left] == 1 and counts[gate_right] == 1 and counts[0] >= 4 and counts[-1] >= 4 and tallest[gate_left] <= 0.0751 and tallest[gate_right] <= 0.0751 and tallest[0] >= 0.12 and tallest[-1] >= 0.12)
	_check("downloaded plants use three batches and one soil mesh", plants.get_child_count() == 4)
	_check("plant instances and source geometry do not exceed the prior layout", records.size() <= baseline_instances and source_triangles <= baseline_triangles and int(plants.get_meta("source_triangles")) == source_triangles)
	var reversed := positions.duplicate()
	reversed.reverse()
	var reversed_by_seed := {}
	for record: Dictionary in Planting.layout(cue, reversed):
		reversed_by_seed[record.seed] = [record.asset, record.transform, record.height]
	_check("post position determines plant placement independent of iteration order", by_seed == reversed_by_seed)
	if second != null:
		_check("plant placement is repeatable", records == second.get_node("PostVegetation").get_meta("layout"))
		var distinct_counts := {}
		for count in counts:
			distinct_counts[count] = true
		_check("default fence has clear, sparse and richer posts", distinct_counts.has(0) and distinct_counts.has(1) and distinct_counts.has(5) and distinct_counts.size() >= 4)
	var state: Dictionary = plants.get_meta("_imported_vegetation_state")
	var grounded := true
	var bounded := true
	for record: Dictionary in state.bounds:
		var box: AABB = record.bounds
		var xf: Transform3D = record.transform
		var bottom := INF
		for i in 8:
			var p := xf * box.get_endpoint(i)
			bottom = minf(bottom, p.y)
			bounded = bounded and p.is_finite() and absf(p.x) >= cue.gap_width * 0.5 - 0.0001 and absf(p.x) <= cue.width * 0.5 + 0.0001 and absf(p.z) < 0.42 and p.y <= 0.231
		grounded = grounded and absf(bottom) < 0.0001
	_check("actual plant bounds preserve walking gap, width and low sightline", bounded)
	_check("all source plant bottoms sit on the ground", grounded)
	var soil: MeshInstance3D = plants.get_node("SoilCollars")
	var soil_clear := true
	var soil_vertices: PackedVector3Array = soil.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var soil_radius := PackedFloat32Array()
	soil_radius.resize(positions.size())
	for p: Vector3 in soil_vertices:
		soil_clear = soil_clear and absf(p.x) >= cue.gap_width * 0.5 - 0.0001 and absf(p.x) <= cue.width * 0.5 + 0.0001 and absf(p.z) < 0.42 and p.y > 0.0 and p.y < 0.04
		for i in positions.size():
			if absf(p.x - positions[i].x) < 0.3:
				soil_radius[i] = maxf(soil_radius[i], Vector2(p.x - positions[i].x, p.z - positions[i].z).length())
	_check("soil collars leave the walking opening and shadow mask clear", soil_clear)
	_check("soil geometry stays within the previous fan budget", soil_vertices.size() / 3 <= positions.size() * 36)
	_check("gate soil remains small", soil_radius[gate_left] > 0.0 and soil_radius[gate_left] < 0.16 and soil_radius[gate_right] > 0.0 and soil_radius[gate_right] < 0.16)
	if second != null:
		var repeat_soil: MeshInstance3D = second.get_node("PostVegetation/SoilCollars")
		_check("soil shape repeats exactly", soil_vertices.to_byte_array() == repeat_soil.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array())
		var soil_posts := 0
		var smallest := INF
		var largest := 0.0
		for radius in soil_radius:
			if radius > 0.0:
				soil_posts += 1
				smallest = minf(smallest, radius)
				largest = maxf(largest, radius)
		_check("default soil contacts are selective and varied", soil_posts > 2 and soil_posts < positions.size() and largest - smallest > 0.03)
		print("Default planting: %d posts, %d plants, %d source triangles, %d soil triangles" % [positions.size(), records.size(), source_triangles, soil_vertices.size() / 3])


func _check_detail(instance: MeshInstance3D, vertices: PackedVector3Array, normals: PackedVector3Array) -> void:
	var colors: PackedColorArray = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var opaque := true
	for color in colors:
		opaque = opaque and color.a == 1.0
	_check("detached debris retains opaque vertex colours", opaque)
	var outward := true
	for i in range(0, vertices.size(), 3):
		var geometric := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).normalized()
		outward = outward and geometric.dot(normals[i]) > 0.999
	_check("bevel and fitting faces match Godot winding", outward)
	var ranges: Array = instance.get_meta("damage_ranges")
	var cursor := 0
	for item: Dictionary in ranges:
		_check("joinery belongs to a contiguous damage piece", item.first == cursor and item.end > item.first)
		cursor = item.end
	_check("no floating fittings survive outside the damage ranges", cursor == vertices.size())
	var material := instance.mesh.surface_get_material(0) as ShaderMaterial
	for channel: String in ["wood_color", "wood_normal", "wood_roughness", "metal_color", "metal_normal", "metal_roughness", "metalness", "zinc_color", "zinc_normal", "zinc_roughness", "zinc_metalness"]:
		var texture := material.get_shader_parameter(channel) as Texture2D
		_check("downloaded %s has distance mipmaps" % channel, texture != null and texture.get_image().has_mipmaps())


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
