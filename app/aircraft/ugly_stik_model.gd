# D1 visual model. Coordinates/provenance live in generated ugly_stik_geometry.gd.
# Native Godot geometry: no glTF axis conversion or importer is involved.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const D: Dictionary = Geometry.DATA
const RED := Color("c8102e")
const CREAM := Color("f7eedb")
const UNDER := Color("242b35")
const METAL := Color("878e95")
const TIRE := Color("191b20")
static var _materials: Dictionary = {}


static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.52
	if color == METAL:
		mat.metallic = 0.65
		mat.roughness = 0.34
	elif color == TIRE:
		mat.roughness = 0.92
	_materials[key] = mat
	return mat


# Godot uses clockwise front faces; normals are explicit and face outwards.
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	st.set_normal(normal)
	st.add_vertex(a)
	if (c - a).cross(b - a).dot(normal) >= 0:
		st.set_normal(normal)
		st.add_vertex(b)
		st.set_normal(normal)
		st.add_vertex(c)
	else:
		st.set_normal(normal)
		st.add_vertex(c)
		st.set_normal(normal)
		st.add_vertex(b)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_triangle(st, a, b, c, normal)
	_triangle(st, a, c, d, normal)


static func _surface(color: Color) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material(color))
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
	var st := _surface(color)
	for side in [-1.0, 1.0]:
		var normal := Vector3(side, 0, 0) if vertical else Vector3(0, side, 0)
		for i in range(0, triangles.size(), 3):
			var points: Array[Vector3] = []
			for k in 3:
				var p := polygon[triangles[i + k]]
				points.append(Vector3(side * thickness / 2, p.x, p.y) if vertical else Vector3(p.x, side * thickness / 2, p.y))
			_triangle(st, points[0], points[1], points[2], normal)
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
		_quad(st, a, b, c, d, n)
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
	var st := _surface(RED)
	for i in range(rings.size() - 1):
		for j in 8:
			var k := (j + 1) % 8
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][k]
			var c: Vector3 = rings[i + 1][k]
			var d: Vector3 = rings[i + 1][j]
			var n := (d - a).cross(b - a).normalized()
			_quad(st, a, b, c, d, n)
	for end in [0, rings.size() - 1]:
		var center := Vector3.ZERO
		for p in rings[end]: center += p
		center /= 8.0
		for j in 8:
			_triangle(st, center, rings[end][j], rings[end][(j + 1) % 8], Vector3(0, 0, -1 if end == 0 else 1))
	_instance("fuselage", st.commit(), root)
	# Simple cream side stripe follows the tapered stations rather than floating off the tail.
	for side in [-1.0, 1.0]:
		var stripe := _surface(CREAM)
		for i in range(rings.size() - 1):
			var a: Array = D.fuselage_stations[i]
			var b: Array = D.fuselage_stations[i + 1]
			var ya: float = (a[2] + a[3]) * 0.5
			var yb: float = (b[2] + b[3]) * 0.5
			var ha: float = (a[2] - a[3]) * 0.10
			var hb: float = (b[2] - b[3]) * 0.10
			_quad(stripe, Vector3(side * (a[1] + 0.0003), ya - ha, a[0]), Vector3(side * (a[1] + 0.0003), ya + ha, a[0]), Vector3(side * (b[1] + 0.0003), yb + hb, b[0]), Vector3(side * (b[1] + 0.0003), yb - hb, b[0]), Vector3(side, 0, 0))
		_instance("stripe_right" if side > 0 else "stripe_left", stripe.commit(), root)


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
	return Vector3(span_x - span_offset, point[1] * w.chord, point[0] * w.chord + z_offset)


static func _section_normal(section: Array, index: int, face_normal: Vector3) -> Vector3:
	var before: Array = section[(index - 1 + section.size()) % section.size()]
	var point: Array = section[index]
	var after: Array = section[(index + 1) % section.size()]
	var a := Vector3(0, point[0] - before[0], before[1] - point[1]).normalized()
	var b := Vector3(0, after[0] - point[0], point[1] - after[1]).normalized()
	# Preserve the hinge's sharp closing face; smooth only adjacent skin segments.
	return (a + b).normalized() if a.dot(b) > 0.35 else face_normal


static func _wing_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, normal_a: Vector3, normal_b: Vector3) -> void:
	var vertices := [a, b, c, d]
	var normals := [normal_a, normal_a, normal_b, normal_b]
	for indices in [[0, 1, 2], [0, 2, 3]]:
		if (vertices[indices[2]] - vertices[indices[0]]).cross(vertices[indices[1]] - vertices[indices[0]]).dot(outward) < 0:
			indices = [indices[0], indices[2], indices[1]]
		for index in indices:
			st.set_normal(normals[index])
			st.add_vertex(vertices[index])


# Section points are [chord fraction, height/chord].
static func _wing_panel(label: String, x0: float, x1: float, section: Array, color: Color, parent: Node3D, z_offset := 0.0, span_offset := 0.0, chord_origin := 0.0) -> void:
	var mesh := ArrayMesh.new()
	for underside in [false, true]:
		var st := _surface(UNDER if underside else color)
		for i in section.size():
			var j := (i + 1) % section.size()
			var p := Vector3(0, section[i][1] * D.wing.chord, section[i][0] * D.wing.chord + z_offset)
			var q := Vector3(0, section[j][1] * D.wing.chord, section[j][0] * D.wing.chord + z_offset)
			var n := Vector3(0, q.z - p.z, p.y - q.y).normalized()
			if (n.y < -0.1) != underside: continue
			_wing_quad(st, _wing_vertex(x0, section[i], z_offset, span_offset, chord_origin), _wing_vertex(x1, section[i], z_offset, span_offset, chord_origin), _wing_vertex(x1, section[j], z_offset, span_offset, chord_origin), _wing_vertex(x0, section[j], z_offset, span_offset, chord_origin), n, _section_normal(section, i, n), _section_normal(section, j, n))
		st.commit(mesh)
	var caps := _surface(color)
	var polygon := PackedVector2Array()
	for p in section: polygon.append(Vector2(p[0] * D.wing.chord + z_offset, p[1] * D.wing.chord))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for x in [x0, x1]:
		for i in range(0, triangles.size(), 3):
			_triangle(caps, _wing_vertex(x, section[triangles[i]], z_offset, span_offset, chord_origin), _wing_vertex(x, section[triangles[i + 1]], z_offset, span_offset, chord_origin), _wing_vertex(x, section[triangles[i + 2]], z_offset, span_offset, chord_origin), Vector3(-1 if x == x0 else 1, 0, 0))
	caps.commit(mesh)
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
			var color := CREAM if i == 1 or i == 3 else RED
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
	var combined := _surface(CREAM)
	var width: float = t.elevator_cutout_half_width
	var start: float = t.elevator_cutout_start
	var notch := PackedVector2Array([Vector2(-width, start), Vector2(width, start), Vector2(width, 1), Vector2(-width, 1)])
	for contour in Geometry2D.clip_polygons(polygon, notch):
		var points: Array = []
		for point in contour: points.append([point.x, point.y])
		var part := _prism("elevator_part", points, t.thickness, CREAM, parent)
		combined.append_from(part.mesh, 0, Transform3D.IDENTITY)
		part.free()
	_instance("elevator", combined.commit(), parent)


static func _tail(root: Node3D, hinges: Dictionary) -> void:
	var t: Dictionary = D.tail
	var fixed := _prism("stab", _relieved_outline(t.stab_outline, -t.hinge_gap / 2), t.thickness, RED, root)
	fixed.position = Vector3(0, t.y, t.hinge_z)
	var elevator := _hinge("elevator", root, fixed.position, hinges)
	_elevator_mesh(_relieved_outline(t.elevator_outline, t.hinge_gap / 2), t, elevator)
	var fin := _prism("fin", _relieved_outline(t.fin_outline, -t.hinge_gap / 2), t.fin_thickness, RED, root, true)
	fin.position = Vector3(0, t.fin_y, t.rudder_hinge_z)
	var ventral := _prism("ventral_fin", t.ventral_outline, t.ventral_thickness, RED, root, true)
	ventral.position = fin.position
	var skid_base: Vector3 = fin.position + Vector3(0, t.ventral_outline[2][0], t.ventral_outline[2][1])
	_strut("tail_skid", skid_base + Vector3(0, 0.018, -0.012), skid_base + Vector3(0, -0.003, 0.012), 0.0008, root)
	var rudder := _hinge("rudder", root, fin.position, hinges)
	_prism("rudder", _relieved_outline(t.rudder_outline, t.hinge_gap / 2), t.fin_thickness, CREAM, rudder, true)


# A fixed gear datum, distinct from wheel spin and steering. Physics supplies angles.
static func _gear_pivot(label: String, position: Vector3, parent: Node3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label
	pivot.position = position
	parent.add_child(pivot)
	return pivot


static func _fuselage_height(z: float, top: bool) -> float:
	var stations: Array = D.fuselage_stations
	var column := 2 if top else 3
	for i in range(stations.size() - 1):
		if z <= stations[i + 1][0]:
			var fraction: float = clampf((z - stations[i][0]) / (stations[i + 1][0] - stations[i][0]), 0.0, 1.0)
			return lerpf(stations[i][column], stations[i + 1][column], fraction)
	return stations.back()[column]


# Visible attachment: two crossed retainers over the wing, hooked onto dowels.
# Construction placement is a visual estimate; no structural strength is implied.
static func _wing_retainers(root: Node3D) -> void:
	var w: Dictionary = D.wing
	var front_z: float = w.leading_z - 0.018
	var rear_z: float = w.leading_z + w.chord + 0.015
	var front_y: float = _fuselage_height(front_z, true) - 0.008
	var rear_y: float = _fuselage_height(rear_z, true) - 0.008
	for item in [["front", front_z, front_y], ["rear", rear_z, rear_y]]:
		var dowel := _cylinder("wing_dowel_" + item[0], 0.003, 0.132, Vector3(0, item[2], item[1]), CREAM, root, 10)
		dowel.rotation.z = PI / 2
	var retainers := _surface(CREAM)
	for sign in [-1.0, 1.0]:
		var path: Array[Vector3] = [Vector3(sign * 0.06, front_y, front_z)]
		for p in w.section:
			if p[0] > w.hinge_fraction: break
			var z: float = w.leading_z + p[0] * w.chord
			var fraction: float = (z - front_z) / (rear_z - front_z)
			var x: float = lerpf(sign * 0.06, -sign * 0.06, fraction)
			var y: float = w.root_y + p[1] * w.chord + absf(x) * tan(deg_to_rad(w.dihedral_deg)) + 0.002
			path.append(Vector3(x, y, z))
		path.append(Vector3(-sign * 0.06, rear_y, rear_z))
		for i in range(path.size() - 1):
			var rod := _cylinder("retainer_%s_%d" % ["r" if sign > 0 else "l", i], 0.0011, path[i].distance_to(path[i + 1]), (path[i] + path[i + 1]) * 0.5, CREAM, root, 6)
			rod.quaternion = Quaternion(Vector3.UP, (path[i + 1] - path[i]).normalized())
			retainers.append_from(rod.mesh, 0, rod.transform)
			rod.free()
	_instance("wing_retainers", retainers.commit(), root)


static func _equipment(root: Node3D, gear: Dictionary) -> Node3D:
	var e: Dictionary = D.equipment
	var engine_z: float = (e.firewall_z + e.prop_z) / 2
	_box("engine_mount", Vector3(0.062, 0.016, 0.09), Vector3(0, e.shaft_y - 0.025, engine_z + 0.006), UNDER, root)
	var crank := _cylinder("engine_crankcase", 0.022, 0.074, Vector3(0, e.shaft_y, engine_z), METAL, root)
	crank.rotation.x = PI / 2
	var shaft := _cylinder("engine_shaft", 0.006, 0.035, Vector3(0, e.shaft_y, e.prop_z + 0.015), METAL, root)
	shaft.rotation.x = PI / 2
	_cylinder("engine_cylinder", 0.02, 0.045, Vector3(0, e.shaft_y + 0.03, engine_z + 0.018), UNDER, root)
	for i in 6:
		_cylinder("cooling_fin_%d" % i, 0.024, 0.0022, Vector3(0, e.shaft_y + 0.018 + i * 0.006, engine_z + 0.018), METAL, root)
	_cylinder("glow_plug", 0.004, 0.01, Vector3(0, e.shaft_y + 0.06, engine_z + 0.018), METAL, root, 8)
	var muffler := _cylinder("muffler", 0.017, 0.14, Vector3(0.064, e.shaft_y - 0.016, engine_z + 0.04), METAL, root)
	muffler.rotation.x = PI / 2
	_strut("muffler_outlet", Vector3(0.064, e.shaft_y - 0.016, engine_z + 0.1), Vector3(0.077, e.shaft_y - 0.027, engine_z + 0.122), 0.006, root)
	_cylinder("carburetor", 0.008, 0.018, Vector3(0, e.shaft_y + 0.022, engine_z - 0.022), METAL, root, 12)
	_cylinder("carburetor_intake", 0.006, 0.001, Vector3(0, e.shaft_y + 0.0315, engine_z - 0.022), UNDER, root, 12)
	_strut("exhaust_header", Vector3(0.018, e.shaft_y + 0.005, engine_z + 0.03), Vector3(0.064, e.shaft_y - 0.016, engine_z + 0.03), 0.009, root)
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(0, e.shaft_y, e.prop_z)
	root.add_child(propeller)
	var hub := _cylinder("prop_hub", 0.017, 0.019, Vector3.ZERO, METAL, propeller)
	hub.rotation.x = PI / 2
	# Blade outline in x/y plane; root centered on the shaft for main.gd's spin.
	var radius: float = e.prop_diameter / 2
	for sign in [-1.0, 1.0]:
		var blade := _prism("prop_blade_right" if sign > 0 else "prop_blade_left", [[0.01,-0.01],[radius*0.72,-0.012],[radius,-0.002],[radius*0.94,0.008],[radius*0.50,0.018],[0.01,0.01]], 0.004, UNDER, propeller)
		blade.rotation.x = PI / 2
		blade.rotation.z = 0 if sign > 0 else PI
	for side in [-1.0, 1.0]:
		var pos := Vector3(side * e.main_track / 2, e.wheel_y, e.main_axle_z)
		var suffix := "right" if side > 0 else "left"
		var axle := _gear_pivot("wheel_" + suffix + "_pivot", pos, root)
		gear[suffix] = axle
		var wheel := _cylinder("gear_" + suffix, e.main_wheel_diameter / 2, 0.024, Vector3.ZERO, TIRE, axle)
		wheel.rotation.z = PI / 2
		var cap := _cylinder("hub_" + suffix, 0.014, 0.026, Vector3.ZERO, METAL, axle)
		cap.rotation.z = PI / 2
		_strut("main_strut_" + suffix, Vector3(side * 0.025, _fuselage_height(e.main_axle_z - 0.05, false) + 0.004, e.main_axle_z - 0.05), pos, 0.004, root)
	var nose_pos := Vector3(0, e.wheel_y, e.nose_axle_z)
	var steering := _gear_pivot("nose_steering_pivot", nose_pos, root)
	gear.steering = steering
	var nose_axle := _gear_pivot("wheel_nose_pivot", Vector3.ZERO, steering)
	gear.nose = nose_axle
	var nose := _cylinder("nosewheel", e.nose_wheel_diameter / 2, 0.022, Vector3.ZERO, TIRE, nose_axle)
	nose.rotation.z = PI / 2
	var nose_hub := _cylinder("hub_nose", 0.013, 0.024, Vector3.ZERO, METAL, nose_axle)
	nose_hub.rotation.z = PI / 2
	_strut("nose_strut", Vector3(0, _fuselage_height(e.firewall_z, false) + 0.014, e.firewall_z), nose_pos + Vector3(0, 0.045, 0), 0.0035, root)
	for sign in [-1.0, 1.0]:
		_strut("nose_fork_" + ("right" if sign > 0 else "left"), Vector3(0, 0.045, 0), Vector3(sign * 0.014, 0, 0), 0.0025, steering)
	return propeller


static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("aircraft_id", D.id)
	root.set_meta("evidence", "visual geometry; measured/estimated fields recorded in geometry.json")
	var hinges := {}
	_fuselage(root)
	_wings(root, hinges)
	_tail(root, hinges)
	_wing_retainers(root)
	var gear := {}
	var propeller := _equipment(root, gear)
	return {root = root, propeller = propeller, hinges = hinges, gear = gear}
