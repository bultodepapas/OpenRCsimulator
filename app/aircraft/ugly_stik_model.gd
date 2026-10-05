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
	mat.roughness = 0.72
	_materials[key] = mat
	return mat


# Godot uses clockwise front faces; normals are explicit and face outwards.
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := outward.normalized()
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


# Constant section between span stations. Section points are [chord fraction, height/chord].
static func _wing_panel(label: String, x0: float, x1: float, section: Array, color: Color, parent: Node3D, z_offset := 0.0) -> void:
	var mesh := ArrayMesh.new()
	for underside in [false, true]:
		var st := _surface(UNDER if underside else color)
		for i in section.size():
			var j := (i + 1) % section.size()
			var p := Vector3(0, section[i][1] * D.wing.chord, section[i][0] * D.wing.chord + z_offset)
			var q := Vector3(0, section[j][1] * D.wing.chord, section[j][0] * D.wing.chord + z_offset)
			var n := Vector3(0, q.z - p.z, p.y - q.y).normalized()
			if (n.y < -0.1) != underside: continue
			_quad(st, p + Vector3(x0, 0, 0), p + Vector3(x1, 0, 0), q + Vector3(x1, 0, 0), q + Vector3(x0, 0, 0), n)
		st.commit(mesh)
	var caps := _surface(color)
	var polygon := PackedVector2Array()
	for p in section: polygon.append(Vector2(p[0] * D.wing.chord + z_offset, p[1] * D.wing.chord))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for x in [x0, x1]:
		for i in range(0, triangles.size(), 3):
			var a := polygon[triangles[i]]
			var b := polygon[triangles[i + 1]]
			var c := polygon[triangles[i + 2]]
			_triangle(caps, Vector3(x, a.y, a.x), Vector3(x, b.y, b.x), Vector3(x, c.y, c.x), Vector3(-1 if x == x0 else 1, 0, 0))
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
	for p in w.section:
		if p[0] <= w.hinge_fraction: fixed.append(p)
	var moving := [[0, 0.021], [1.0 - w.hinge_fraction, 0], [0, -0.008]]
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
			var a: float = sign * interval[0]
			var b: float = sign * interval[1]
			_wing_panel("fixed_te_%s_%s" % [suffix, str(interval[0])], minf(a,b), maxf(a,b), moving, RED, frame, w.hinge_fraction * w.chord)
		var pivot := _hinge("aileron_" + suffix, frame, Vector3(sign * (w.aileron_inner + w.aileron_outer) / 2, 0, w.hinge_fraction * w.chord), hinges)
		var half: float = (w.aileron_outer - w.aileron_inner) / 2
		_wing_panel("aileron_" + suffix, -half, half, moving, RED, pivot)


static func _tail(root: Node3D, hinges: Dictionary) -> void:
	var t: Dictionary = D.tail
	var fixed := _prism("stab", t.stab_outline, t.thickness, RED, root)
	fixed.position = Vector3(0, t.y, t.hinge_z)
	var elevator := _hinge("elevator", root, fixed.position, hinges)
	_prism("elevator", t.elevator_outline, t.thickness, CREAM, elevator)
	var fin := _prism("fin", t.fin_outline, t.thickness, RED, root, true)
	fin.position = fixed.position
	var rudder := _hinge("rudder", root, fixed.position, hinges)
	_prism("rudder", t.rudder_outline, t.thickness, CREAM, rudder, true)


static func _equipment(root: Node3D) -> Node3D:
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
		var wheel := _cylinder("gear_" + suffix, e.main_wheel_diameter / 2, 0.024, pos, TIRE, root)
		wheel.rotation.z = PI / 2
		var cap := _cylinder("hub_" + suffix, 0.014, 0.026, pos, CREAM, root)
		cap.rotation.z = PI / 2
		_strut("main_strut_" + suffix, Vector3(side * 0.025, -0.055, e.main_axle_z - 0.05), pos, 0.004, root)
	var nose_pos := Vector3(0, e.wheel_y, e.nose_axle_z)
	var nose := _cylinder("nosewheel", e.nose_wheel_diameter / 2, 0.022, nose_pos, TIRE, root)
	nose.rotation.z = PI / 2
	var nose_hub := _cylinder("hub_nose", 0.013, 0.024, nose_pos, CREAM, root)
	nose_hub.rotation.z = PI / 2
	_strut("nose_strut", Vector3(0, -0.047, e.firewall_z), nose_pos, 0.0035, root)
	return propeller


static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("aircraft_id", D.id)
	root.set_meta("evidence", "visual v1; calibrated/estimated fields recorded in geometry.json")
	var hinges := {}
	_fuselage(root)
	_wings(root, hinges)
	_tail(root, hinges)
	var propeller := _equipment(root)
	return {root = root, propeller = propeller, hinges = hinges}
