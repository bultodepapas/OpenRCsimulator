# D1 visual model. Coordinates/provenance live in generated ugly_stik_geometry.gd.
# Native Godot geometry: no glTF axis conversion or importer is involved.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Controls := preload("res://aircraft/ugly_stik_controls.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const D: Dictionary = Geometry.DATA
const RED := Finish.RED
const CREAM := Color("f7eedb")
const UNDER := Color("242b35")
const METAL := Color("878e95")
const TIRE := Color("191b20")
static func material(color: Color) -> StandardMaterial3D:
	var profile := "skin"
	if color == METAL: profile = "aluminum"
	elif color == TIRE: profile = "rubber"
	elif color == UNDER: profile = "plastic"
	return Finish.material(color, profile)


# Godot uses clockwise front faces; normals are explicit and face outwards.
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, region := "") -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.dot(outward) < 0.0: normal = -normal
	var vertices := [a, b, c] if (c - a).cross(b - a).dot(normal) >= 0 else [a, c, b]
	for point in vertices:
		st.set_normal(normal)
		if not region.is_empty(): st.set_uv(Finish.uv(point, region))
		st.add_vertex(point)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, region := "") -> void:
	_triangle(st, a, b, c, normal, region)
	_triangle(st, a, c, d, normal, region)


static func _surface(color: Color, textured := false) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(Finish.covering() if textured else material(color))
	return st


static func _instance(label: String, mesh: Mesh, parent: Node3D, position := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = position
	parent.add_child(node)
	return node


static func _box(label: String, size: Vector3, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(color)
	return _instance(label, mesh, parent, pos)


static func _cylinder(label: String, radius: float, length: float, pos: Vector3, color: Color, parent: Node3D, segments := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material(color)
	return _instance(label, mesh, parent, pos)


static func _strut(label: String, a: Vector3, b: Vector3, radius: float, parent: Node3D) -> void:
	var rod := _cylinder(label, radius, (b - a).length(), (a + b) * 0.5, METAL, parent, 8)
	rod.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


# Extrude an arbitrary x/z outline; vertical maps outline x to height and thickness to x.
# Edges lying on the relieved hinge line (both ends at gap_offset) get the hinge-gap finish (US-V09a).
static func _prism(label: String, outline: Array, thickness: float, color: Color, parent: Node3D, vertical := false, gap_offset := NAN) -> MeshInstance3D:
	var polygon := PackedVector2Array()
	for point in outline:
		polygon.append(Vector2(point[0], point[1]))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	assert(not triangles.is_empty(), "Invalid model outline: " + label)
	var textured := label == "fin" or label == "rudder"
	var st := _surface(color, textured)
	var gap := SurfaceTool.new()
	gap.begin(Mesh.PRIMITIVE_TRIANGLES)
	gap.set_material(Finish.hinge_gap())
	var has_gap := false
	for side in [-1.0, 1.0]:
		var normal := Vector3(side, 0, 0) if vertical else Vector3(0, side, 0)
		for i in range(0, triangles.size(), 3):
			var points: Array[Vector3] = []
			for k in 3:
				var p := polygon[triangles[i + k]]
				points.append(Vector3(side * thickness / 2, p.x, p.y) if vertical else Vector3(p.x, side * thickness / 2, p.y))
			_triangle(st, points[0], points[1], points[2], normal, "fin" if textured else "")
	var clockwise := Geometry2D.is_polygon_clockwise(polygon)
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var edge := q - p
		var n2 := Vector2(edge.y, -edge.x) * (-1.0 if clockwise else 1.0)
		var n := Vector3(0, n2.x, n2.y) if vertical else Vector3(n2.x, 0, n2.y)
		var a := Vector3(-thickness / 2, p.x, p.y) if vertical else Vector3(p.x, -thickness / 2, p.y)
		var b := Vector3(thickness / 2, p.x, p.y) if vertical else Vector3(p.x, thickness / 2, p.y)
		var c := Vector3(thickness / 2, q.x, q.y) if vertical else Vector3(q.x, thickness / 2, q.y)
		var d := Vector3(-thickness / 2, q.x, q.y) if vertical else Vector3(q.x, -thickness / 2, q.y)
		var on_hinge := absf(p.y - gap_offset) < 1e-7 and absf(q.y - gap_offset) < 1e-7
		has_gap = has_gap or on_hinge
		_quad(gap if on_hinge else st, a, b, c, d, n, "white" if textured else "red" if on_hinge else "")
	if textured: st.generate_tangents()
	var mesh := st.commit()
	if has_gap: gap.commit(mesh)
	return _instance(label, mesh, parent)


static func _smooth_quad(st: SurfaceTool, points: Array, normals: Array, outward: Vector3, region: String) -> void:
	for indices in [[0, 1, 2], [0, 2, 3]]:
		if (points[indices[2]] - points[indices[0]]).cross(points[indices[1]] - points[indices[0]]).dot(outward) < 0:
			indices = [indices[0], indices[2], indices[1]]
		for index in indices:
			st.set_normal(normals[index])
			st.set_uv(Finish.uv(points[index], region))
			st.add_vertex(points[index])


# US-V09a: sanded balsa-box corners. Each bevel becomes a quarter arc tangent to both flat sides at the old chamfer
# ends, so the measured half-width, top and bottom stay the envelope. Normals are smooth around the section and
# per bay along the fuselage, keeping the straight-sheet creases at every measured station.
const FUSELAGE_CORNER_SEGMENTS := 4

static func _fuselage(root: Node3D) -> void:
	var rings: Array = []
	var directions: Array = [] # cross-section outward normals, shared by every station
	for station in D.fuselage_stations:
		var z: float = station[0]
		var w: float = station[1]
		var top: float = station[2]
		var bottom: float = station[3]
		var bevel := minf(w * 0.16, (top - bottom) * 0.12)
		var ring: Array = []
		directions.clear()
		for corner in [[w - bevel, top - bevel, 90.0], [w - bevel, bottom + bevel, 0.0], [-w + bevel, bottom + bevel, -90.0], [-w + bevel, top - bevel, -180.0]]:
			for k in FUSELAGE_CORNER_SEGMENTS + 1:
				var angle := deg_to_rad(float(corner[2]) - 90.0 * k / FUSELAGE_CORNER_SEGMENTS)
				var n := Vector3(cos(angle), sin(angle), 0)
				ring.append(Vector3(corner[0], corner[1], z) + n * bevel)
				directions.append(n)
		rings.append(ring)
	var count: int = directions.size()
	var st := _surface(RED, true)
	for i in range(rings.size() - 1):
		for j in count:
			var k := (j + 1) % count
			var points := [rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]]
			var normals: Array = []
			for corner in [[i, j], [i, k], [i + 1, k], [i + 1, j]]:
				var n2: Vector3 = directions[corner[1]]
				var along: Vector3 = rings[i + 1][corner[1]] - rings[i][corner[1]]
				var n: Vector3 = Vector3(-n2.y, n2.x, 0).cross(along).normalized()
				normals.append(n if n.dot(n2) > 0.0 else -n)
			var outward: Vector3 = (directions[j] + directions[k]).normalized()
			var top_flat: bool = directions[j].y > 0.999 and directions[k].y > 0.999
			_smooth_quad(st, points, normals, outward, "dorsal" if top_flat else "red")
	for end in [0, rings.size() - 1]:
		var center := Vector3.ZERO
		for p in rings[end]: center += p
		center /= float(count)
		for j in count:
			_triangle(st, center, rings[end][j], rings[end][(j + 1) % count], Vector3(0, 0, -1 if end == 0 else 1), "red")
	st.generate_tangents()
	_instance("fuselage", st.commit(), root)


# A traced tip tapers spanwise toward the leading edge, preserving nominal maximum span.
# span_offset maps a moving panel's local coordinates back to its fixed wing frame.
static func _wing_vertex(x: float, point: Array, z_offset: float, span_offset: float, chord_origin: float) -> Vector3:
	var w: Dictionary = D.wing
	var span_x := x + span_offset
	var u: float = point[0] + chord_origin
	if absf(span_x) > w.tip_start:
		var t: float = (absf(span_x) - w.tip_start) / (w.span / 2.0 - w.tip_start)
		var edge_x: float = lerpf(w.tip_le_span, w.span / 2.0, clampf(u, 0.0, 1.0))
		span_x = signf(span_x) * lerpf(w.tip_start, edge_x, t)
	var scallop := float(Finish.Appearance.DATA.scallops.depth_m) * pow(sin(PI * absf(x + span_offset) / float(Finish.Appearance.DATA.scallops.pitch_m)), 2.0) if u > 0.999 else 0.0
	return Vector3(span_x - span_offset, point[1] * w.chord, point[0] * w.chord + z_offset - scallop)


static func _section_normal(section: Array, index: int, face_normal: Vector3) -> Vector3:
	var before: Array = section[(index - 1 + section.size()) % section.size()]
	var point: Array = section[index]
	var after: Array = section[(index + 1) % section.size()]
	var a := Vector3(0, point[0] - before[0], before[1] - point[1]).normalized()
	var b := Vector3(0, after[0] - point[0], point[1] - after[1]).normalized()
	# Preserve the hinge's sharp closing face; smooth only adjacent skin segments.
	return (a + b).normalized() if a.dot(b) > 0.35 else face_normal


# US-V09a follow-up: a skin segment narrower than BEVEL_SHADE_MAX_CHORD that ends on a hinge-gap face (the traced
# 4 mm, 25° bevel ahead of the aileron) is sub-pixel at flight distance; with glossy film its sun glint aliased into a
# dashed white line. It keeps its geometry but shades with the adjacent skin segment's face normal. ZERO = not a bevel.
const BEVEL_SHADE_MAX_CHORD := 0.03

static func _narrow_bevel_normal(section: Array, i: int, j: int) -> Vector3:
	var n := section.size()
	var a: Array = section[i]
	var b: Array = section[j]
	if is_equal_approx(float(a[0]), float(b[0])) or Vector2(b[0] - a[0], b[1] - a[1]).length() > BEVEL_SHADE_MAX_CHORD: return Vector3.ZERO
	var neighbour: Array
	if is_equal_approx(float(b[0]), float(section[(j + 1) % n][0])): neighbour = [section[(i - 1 + n) % n], a]
	elif is_equal_approx(float(a[0]), float(section[(i - 1 + n) % n][0])): neighbour = [b, section[(j + 1) % n]]
	else: return Vector3.ZERO
	var p: Array = neighbour[0]
	var q: Array = neighbour[1]
	return Vector3(0, q[0] - p[0], p[1] - q[1]).normalized()


static func _wing_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, normal_a: Vector3, normal_b: Vector3, uv_offset: Vector3) -> void:
	var vertices := [a, b, c, d]
	var normals := [normal_a, normal_a, normal_b, normal_b]
	for indices in [[0, 1, 2], [0, 2, 3]]:
		if (vertices[indices[2]] - vertices[indices[0]]).cross(vertices[indices[1]] - vertices[indices[0]]).dot(outward) < 0:
			indices = [indices[0], indices[2], indices[1]]
		for index in indices:
			st.set_normal(normals[index])
			st.set_uv(Finish.uv(vertices[index] + uv_offset, "wing"))
			st.add_vertex(vertices[index])


# Section points are [chord fraction, height/chord].
static func _wing_panel(label: String, x0: float, x1: float, section: Array, color: Color, parent: Node3D, z_offset := 0.0, span_offset := 0.0, chord_origin := 0.0) -> void:
	var st := _surface(color, true)
	# US-V09a: the hinge-gap closing faces sit in a shadowed slot; with glossy film they otherwise mirror the sky as a
	# bright aliased line. They keep the atlas colour but get the occluded gap finish.
	var gap := SurfaceTool.new()
	gap.begin(Mesh.PRIMITIVE_TRIANGLES)
	gap.set_material(Finish.hinge_gap())
	var count := maxi(1, int(ceil((x1 - x0) / 0.01016))) if chord_origin > 0 else 1
	var uv_offset := Vector3(span_offset, 0, chord_origin * float(D.wing.chord) - z_offset)
	for span_i in count:
		var lo := lerpf(x0, x1, float(span_i) / count)
		var hi := lerpf(x0, x1, float(span_i + 1) / count)
		for i in section.size():
			var j := (i + 1) % section.size()
			var p := Vector3(0, section[i][1] * D.wing.chord, section[i][0] * D.wing.chord + z_offset)
			var q := Vector3(0, section[j][1] * D.wing.chord, section[j][0] * D.wing.chord + z_offset)
			var n := Vector3(0, q.z - p.z, p.y - q.y).normalized()
			var closing := is_equal_approx(float(section[i][0]), float(section[j][0]))
			var na := _section_normal(section, i, n)
			var nb := _section_normal(section, j, n)
			var bevel := _narrow_bevel_normal(section, i, j)
			if bevel != Vector3.ZERO:
				na = bevel
				nb = bevel
			_wing_quad(gap if closing else st, _wing_vertex(lo, section[i], z_offset, span_offset, chord_origin), _wing_vertex(hi, section[i], z_offset, span_offset, chord_origin), _wing_vertex(hi, section[j], z_offset, span_offset, chord_origin), _wing_vertex(lo, section[j], z_offset, span_offset, chord_origin), n, na, nb, uv_offset)
	var polygon := PackedVector2Array()
	for p in section: polygon.append(Vector2(p[0] * D.wing.chord + z_offset, p[1] * D.wing.chord))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for x in [x0, x1]:
		for i in range(0, triangles.size(), 3):
			# Closed caps use the same planar atlas and winding as the adjacent skin.
			var vertices := [_wing_vertex(x, section[triangles[i]], z_offset, span_offset, chord_origin), _wing_vertex(x, section[triangles[i + 1]], z_offset, span_offset, chord_origin), _wing_vertex(x, section[triangles[i + 2]], z_offset, span_offset, chord_origin)]
			var n := Vector3(-1 if x == x0 else 1, 0, 0)
			if (vertices[2] - vertices[0]).cross(vertices[1] - vertices[0]).dot(n) < 0: vertices.reverse()
			for point in vertices:
				st.set_normal(n)
				st.set_uv(Finish.uv(point + uv_offset, "wing"))
				st.add_vertex(point)
	st.generate_tangents() # US-V09b: the covering's film-structure normal map needs a tangent frame
	var mesh := st.commit()
	var gap_vertices: Variant = gap.commit_to_arrays()[Mesh.ARRAY_VERTEX]
	if gap_vertices != null and not gap_vertices.is_empty(): gap.commit(mesh)
	_instance(label, mesh, parent)


static func _hinge(label: String, parent: Node3D, pos: Vector3, hinges: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label + "_hinge"
	pivot.position = pos
	parent.add_child(pivot)
	hinges[label] = pivot
	return pivot


static func _wings(root: Node3D, hinges: Dictionary) -> void:
	var w: Dictionary = D.wing
	# Split at hinge, retaining the semisymmetric section and separate moving trailing edge.
	var fixed: Array = []
	var hinge_heights: Array[float] = []
	var trailing_height := 0.0
	for p in w.section:
		if p[0] <= w.hinge_fraction:
			var q: Array = p.duplicate()
			if is_equal_approx(p[0], w.hinge_fraction): q[0] -= w.hinge_gap / (2.0 * w.chord)
			fixed.append(q)
		if is_equal_approx(p[0], w.hinge_fraction): hinge_heights.append(p[1])
		if is_equal_approx(p[0], 1.0): trailing_height = p[1]
	assert(hinge_heights.size() == 2, "Section needs upper/lower hinge samples")
	var gap_fraction: float = w.hinge_gap / (2.0 * w.chord)
	var moving := [[gap_fraction, hinge_heights[0]], [1.0 - w.hinge_fraction, trailing_height], [gap_fraction, hinge_heights[1]]]
	var fixed_trailing := [[-gap_fraction, hinge_heights[0]], [1.0 - w.hinge_fraction, trailing_height], [-gap_fraction, hinge_heights[1]]]
	for sign in [-1.0, 1.0]:
		var suffix := "right" if sign > 0 else "left"
		var frame := Node3D.new()
		frame.name = "wing_frame_" + suffix
		frame.position = Vector3(0, w.root_y, w.leading_z)
		frame.rotation.z = sign * deg_to_rad(w.dihedral_deg)
		root.add_child(frame)
		var stops := [0.0, 0.47, 0.54, w.tip_start, w.span / 2.0]
		for i in range(stops.size() - 1):
			var color := RED
			var a: float = sign * stops[i]
			var b: float = sign * stops[i + 1]
			_wing_panel("wing_%s_%d" % [suffix, i], minf(a,b), maxf(a,b), fixed, color, frame)
		# Full trailing edge around the movable span closes root and tip gaps.
		for interval in [[0.0, w.aileron_inner], [w.aileron_outer, w.span / 2.0]]:
			if interval[1] - interval[0] <= 0.000001: continue
			var a: float = sign * interval[0]
			var b: float = sign * interval[1]
			_wing_panel("fixed_te_%s_%s" % [suffix, str(interval[0])], minf(a,b), maxf(a,b), fixed_trailing, RED, frame, w.hinge_fraction * w.chord, 0.0, w.hinge_fraction)
		var pivot := _hinge("aileron_" + suffix, frame, Vector3(sign * (w.aileron_inner + w.aileron_outer) / 2, 0, w.hinge_fraction * w.chord), hinges)
		var half: float = (w.aileron_outer - w.aileron_inner) / 2
		_wing_panel("aileron_" + suffix, -half + (w.inboard_gap if sign > 0 else 0.0), half - (w.inboard_gap if sign < 0 else 0.0), moving, RED, pivot, 0.0, sign * (w.aileron_inner + w.aileron_outer) / 2, w.hinge_fraction)


static func _relieved_outline(outline: Array, offset: float) -> Array:
	var result: Array = []
	for point in outline:
		var p: Array = point.duplicate()
		if is_zero_approx(p[1]): p[1] = offset
		result.append(p)
	return result


# US-V09a: the fin and rudder are sanded curves traced as polylines. A centripetal Catmull-Rom spline passes through
# every traced point; the closing root line and the hinge line stay straight, and no point crosses the hinge.
const OUTLINE_SUBDIVISIONS := 4

static func _curved_outline(outline: Array) -> Array:
	var n := outline.size()
	var curved := func(i: int) -> bool:
		var a: Array = outline[posmod(i, n)]
		var b: Array = outline[posmod(i + 1, n)]
		return posmod(i, n) != n - 1 and not (absf(a[1]) < 1e-9 and absf(b[1]) < 1e-9)
	var result: Array = []
	for i in n:
		var p1 := Vector2(outline[i][0], outline[i][1])
		result.append([p1.x, p1.y])
		if not curved.call(i): continue
		var p2 := Vector2(outline[(i + 1) % n][0], outline[(i + 1) % n][1])
		var p0 := Vector2(outline[posmod(i - 1, n)][0], outline[posmod(i - 1, n)][1]) if curved.call(i - 1) else 2.0 * p1 - p2
		var p3 := Vector2(outline[(i + 2) % n][0], outline[(i + 2) % n][1]) if curved.call(i + 1) else 2.0 * p2 - p1
		var t1 := sqrt(p0.distance_to(p1))
		var t2 := t1 + sqrt(p1.distance_to(p2))
		var t3 := t2 + sqrt(p2.distance_to(p3))
		for k in range(1, OUTLINE_SUBDIVISIONS):
			var t := lerpf(t1, t2, float(k) / OUTLINE_SUBDIVISIONS)
			var a1 := p0.lerp(p1, (t - 0.0) / t1)
			var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
			var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
			var b1 := a1.lerp(a2, (t - 0.0) / t2)
			var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
			var c := b1.lerp(b2, (t - t1) / (t2 - t1))
			if p1.y <= 0.0 and p2.y <= 0.0: c.y = minf(c.y, 0.0)
			elif p1.y >= 0.0 and p2.y >= 0.0: c.y = maxf(c.y, 0.0)
			result.append([c.x, c.y])
	return result


# Keep one named mesh/hinge interface while relieving the elevator around the rudder sweep.
static func _elevator_mesh(outline: Array, t: Dictionary, parent: Node3D) -> void:
	var polygon := PackedVector2Array()
	for p in outline: polygon.append(Vector2(p[0], p[1]))
	var combined := _surface(RED)
	var combined_gap := SurfaceTool.new()
	combined_gap.begin(Mesh.PRIMITIVE_TRIANGLES)
	combined_gap.set_material(Finish.hinge_gap())
	var width: float = t.elevator_cutout_half_width
	var start: float = t.elevator_cutout_start
	var notch := PackedVector2Array([Vector2(-width, start), Vector2(width, start), Vector2(width, 1), Vector2(-width, 1)])
	for contour in Geometry2D.clip_polygons(polygon, notch):
		var points: Array = []
		for point in contour: points.append([point.x, point.y])
		var part := _prism("elevator_part", points, t.thickness, RED, parent, false, t.hinge_gap / 2)
		combined.append_from(part.mesh, 0, Transform3D.IDENTITY)
		if part.mesh.get_surface_count() > 1: combined_gap.append_from(part.mesh, 1, Transform3D.IDENTITY)
		part.free()
	var mesh := combined.commit()
	combined_gap.commit(mesh)
	_instance("elevator", mesh, parent)


static func _tail(root: Node3D, hinges: Dictionary) -> void:
	var t: Dictionary = D.tail
	var fixed := _prism("stab", _relieved_outline(t.stab_outline, -t.hinge_gap / 2), t.thickness, RED, root, false, -t.hinge_gap / 2)
	fixed.position = Vector3(0, t.y, t.hinge_z)
	var elevator := _hinge("elevator", root, fixed.position, hinges)
	_elevator_mesh(_relieved_outline(t.elevator_outline, t.hinge_gap / 2), t, elevator)
	var fin := _prism("fin", _relieved_outline(_curved_outline(t.fin_outline), -t.hinge_gap / 2), t.fin_thickness, Finish.WHITE, root, true, -t.hinge_gap / 2)
	fin.position = Vector3(0, t.fin_y, t.rudder_hinge_z)
	var ventral := _prism("ventral_fin", t.ventral_outline, t.ventral_thickness, RED, root, true)
	ventral.position = fin.position
	var skid_base: Vector3 = fin.position + Vector3(0, t.ventral_outline[2][0], t.ventral_outline[2][1])
	_strut("tail_skid", skid_base + Vector3(0, 0.018, -0.012), skid_base + Vector3(0, -0.003, 0.012), 0.0008, root)
	var rudder := _hinge("rudder", root, fin.position, hinges)
	_prism("rudder", _relieved_outline(_curved_outline(t.rudder_outline), t.hinge_gap / 2), t.fin_thickness, Finish.WHITE, rudder, true, t.hinge_gap / 2)


static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("aircraft_id", D.id)
	root.set_meta("visual_revision", "jensen-61-classic-red-v4")
	root.set_meta("evidence", "visual geometry; measured/estimated fields recorded in geometry.json")
	var hinges := {}
	_fuselage(root)
	_wings(root, hinges)
	_tail(root, hinges)
	Equipment.retainers(root)
	var gear := {}
	var propeller := Equipment.build(root, gear)
	var controls := Controls.build(root, hinges)
	return {root = root, propeller = propeller, hinges = hinges, gear = gear, controls = controls}
