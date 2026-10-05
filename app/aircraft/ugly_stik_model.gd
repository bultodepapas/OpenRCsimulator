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
static func _prism(label: String, outline: Array, thickness: float, color: Color, parent: Node3D, vertical := false) -> MeshInstance3D:
	var polygon := PackedVector2Array()
	for point in outline:
		polygon.append(Vector2(point[0], point[1]))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	assert(not triangles.is_empty(), "Invalid model outline: " + label)
	var textured := label == "fin" or label == "rudder"
	var st := _surface(color, textured)
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
		_quad(st, a, b, c, d, n, "white" if textured else "")
	return _instance(label, st.commit(), parent)


static func _fuselage(root: Node3D) -> void:
	var rings: Array = []
	for station in D.fuselage_stations:
		var z: float = station[0]
		var w: float = station[1]
		var top: float = station[2]
		var bottom: float = station[3]
		var bevel := minf(w * 0.16, (top - bottom) * 0.12)
		rings.append([Vector3(-w + bevel, top, z), Vector3(w - bevel, top, z), Vector3(w, top - bevel, z), Vector3(w, bottom + bevel, z), Vector3(w - bevel, bottom, z), Vector3(-w + bevel, bottom, z), Vector3(-w, bottom + bevel, z), Vector3(-w, top - bevel, z)])
	var st := _surface(RED, true)
	for i in range(rings.size() - 1):
		for j in 8:
			var k := (j + 1) % 8
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][k]
			var c: Vector3 = rings[i + 1][k]
			var d: Vector3 = rings[i + 1][j]
			var n := (d - a).cross(b - a).normalized()
			_quad(st, a, b, c, d, n, "dorsal" if j == 0 else "red")
	for end in [0, rings.size() - 1]:
		var center := Vector3.ZERO
		for p in rings[end]: center += p
		center /= 8.0
		for j in 8:
			_triangle(st, center, rings[end][j], rings[end][(j + 1) % 8], Vector3(0, 0, -1 if end == 0 else 1), "red")
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
			_wing_quad(st, _wing_vertex(lo, section[i], z_offset, span_offset, chord_origin), _wing_vertex(hi, section[i], z_offset, span_offset, chord_origin), _wing_vertex(hi, section[j], z_offset, span_offset, chord_origin), _wing_vertex(lo, section[j], z_offset, span_offset, chord_origin), n, _section_normal(section, i, n), _section_normal(section, j, n), uv_offset)
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
	_instance(label, st.commit(), parent)


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


# Keep one named mesh/hinge interface while relieving the elevator around the rudder sweep.
static func _elevator_mesh(outline: Array, t: Dictionary, parent: Node3D) -> void:
	var polygon := PackedVector2Array()
	for p in outline: polygon.append(Vector2(p[0], p[1]))
	var combined := _surface(RED)
	var width: float = t.elevator_cutout_half_width
	var start: float = t.elevator_cutout_start
	var notch := PackedVector2Array([Vector2(-width, start), Vector2(width, start), Vector2(width, 1), Vector2(-width, 1)])
	for contour in Geometry2D.clip_polygons(polygon, notch):
		var points: Array = []
		for point in contour: points.append([point.x, point.y])
		var part := _prism("elevator_part", points, t.thickness, RED, parent)
		combined.append_from(part.mesh, 0, Transform3D.IDENTITY)
		part.free()
	_instance("elevator", combined.commit(), parent)


static func _tail(root: Node3D, hinges: Dictionary) -> void:
	var t: Dictionary = D.tail
	var fixed := _prism("stab", _relieved_outline(t.stab_outline, -t.hinge_gap / 2), t.thickness, RED, root)
	fixed.position = Vector3(0, t.y, t.hinge_z)
	var elevator := _hinge("elevator", root, fixed.position, hinges)
	_elevator_mesh(_relieved_outline(t.elevator_outline, t.hinge_gap / 2), t, elevator)
	var fin := _prism("fin", _relieved_outline(t.fin_outline, -t.hinge_gap / 2), t.fin_thickness, Finish.WHITE, root, true)
	fin.position = Vector3(0, t.fin_y, t.rudder_hinge_z)
	var ventral := _prism("ventral_fin", t.ventral_outline, t.ventral_thickness, RED, root, true)
	ventral.position = fin.position
	var skid_base: Vector3 = fin.position + Vector3(0, t.ventral_outline[2][0], t.ventral_outline[2][1])
	_strut("tail_skid", skid_base + Vector3(0, 0.018, -0.012), skid_base + Vector3(0, -0.003, 0.012), 0.0008, root)
	var rudder := _hinge("rudder", root, fin.position, hinges)
	_prism("rudder", _relieved_outline(t.rudder_outline, t.hinge_gap / 2), t.fin_thickness, Finish.WHITE, rudder, true)


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
