# AV-02 visual study only. No flight model, imports or app dependencies.
# Estimated contours are explicitly identified in geometry.json.
extends RefCounted

const WHITE := Color("e9e8e1")
const BLUE := Color("176fba")
const RED := Color("d83538")
const DARK := Color("172735")

static func point(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .48
	return m

static func instance(label: String, mesh: Mesh, parent: Node3D, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	return node

# Panels retain face normals; loft sides supply continuous vertex normals.
static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, normals: Dictionary = {}) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-16: return
	var vertices := [a, b, c]
	if normal.dot(outward) < 0:
		vertices = [a, c, b]
		normal = -normal
	for v in vertices:
		st.set_normal(normals.get(v, normal.normalized()))
		st.add_vertex(v)

static func section_slope(rows: Array, i: int, column: int) -> float:
	if i == 0: return (float(rows[1][column]) - float(rows[0][column])) / (float(rows[1][0]) - float(rows[0][0]))
	if i == rows.size() - 1: return section_slope([rows[-2], rows[-1]], 0, column)
	var left_h: float = rows[i][0] - rows[i - 1][0]
	var right_h: float = rows[i + 1][0] - rows[i][0]
	var left_d: float = (rows[i][column] - rows[i - 1][column]) / left_h
	var right_d: float = (rows[i + 1][column] - rows[i][column]) / right_h
	if left_d * right_d <= 0: return 0.0
	var w1 := 2 * right_h + left_h
	var w2 := right_h + 2 * left_h
	return (w1 + w2) / (w1 / left_d + w2 / right_d)

# Monotone Hermite sections preserve knots and do not overshoot local extrema.
static func interpolate_sections(rows: Array, subdivisions: int) -> Array:
	var result: Array = []
	for i in rows.size() - 1:
		var h: float = rows[i + 1][0] - rows[i][0]
		for j in subdivisions:
			var t := float(j) / subdivisions
			var row: Array = [lerpf(rows[i][0], rows[i + 1][0], t)]
			for column in range(1, rows[i].size()):
				var a: float = rows[i][column]
				var b: float = rows[i + 1][column]
				var value := (2*t*t*t-3*t*t+1)*a + (t*t*t-2*t*t+t)*h*section_slope(rows,i,column) + (-2*t*t*t+3*t*t)*b + (t*t*t-t*t)*h*section_slope(rows,i+1,column)
				row.append(clampf(value, minf(a, b), maxf(a, b)))
			result.append(row)
	result.append(rows[-1].duplicate())
	return result

static func loft(rows: Array, parent: Node3D, label: String, color: Color, side: float = 1.0, subdivisions: int = 1, smooth: bool = false, cap_rear: bool = true) -> MeshInstance3D:
	rows = interpolate_sections(rows, subdivisions)
	var rings: Array = []
	for row in rows:
		var ring: Array[Vector3] = []
		for j in 32:
			var a := TAU * j / 32.0
			var center_x: float = float(row[4]) * side if row.size() > 4 else 0.0
			ring.append(Vector3(center_x + row[1] * cos(a), (row[2] + row[3]) * .5 + (row[2] - row[3]) * .5 * sin(a), row[0]))
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normals := {}
	if smooth:
		for i in rings.size():
			for j in 32:
				var around: Vector3 = rings[i][(j + 1) % 32] - rings[i][(j + 31) % 32]
				var along: Vector3 = rings[mini(i + 1, rings.size() - 1)][j] - rings[maxi(i - 1, 0)][j]
				normals[rings[i][j]] = around.cross(along).normalized()
	for i in rings.size() - 1:
		for j in 32:
			var k := (j + 1) % 32
			var hint := Vector3(cos(TAU * (j + .5) / 32), sin(TAU * (j + .5) / 32), 0)
			triangle(st, rings[i][j], rings[i][k], rings[i + 1][k], hint, normals)
			triangle(st, rings[i][j], rings[i + 1][k], rings[i + 1][j], hint, normals)
	for end in [0, rings.size() - 1]:
		if end != 0 and not cap_rear: continue
		var center_x: float = float(rows[end][4]) * side if rows[end].size() > 4 else 0.0
		var center := Vector3(center_x, (rows[end][2] + rows[end][3]) * .5, rows[end][0])
		for j in 32:
			triangle(st, center, rings[end][j], rings[end][(j + 1) % 32], Vector3.FORWARD if end == 0 else Vector3.BACK)
	return instance(label, st.commit(), parent, color)

# A closed thin polygonal solid; its extrusion is a visual placeholder, not an airfoil.
static func slab(vertices: Array, half_thickness: Vector3, parent: Node3D, label: String, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Ear clipping also supports the concave fin-to-fuselage fairing.
	var polygon := PackedVector2Array()
	for p in vertices:
		polygon.append(Vector2(p.z, p.y) if half_thickness.x != 0 else Vector2(p.x, p.z))
	var indices := Geometry2D.triangulate_polygon(polygon)
	assert(not indices.is_empty(), "Invalid panel polygon: " + label)
	for i in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[i]]
		var b: Vector3 = vertices[indices[i + 1]]
		var c: Vector3 = vertices[indices[i + 2]]
		triangle(st, a + half_thickness, b + half_thickness, c + half_thickness, half_thickness)
		triangle(st, a - half_thickness, b - half_thickness, c - half_thickness, -half_thickness)
	for j in vertices.size():
		var a: Vector3 = vertices[j]
		var b: Vector3 = vertices[(j + 1) % vertices.size()]
		# Edge orientation, not radial direction, is reliable on concave outlines.
		var edge := b - a
		var hint := edge.cross(half_thickness).normalized()
		if not Geometry2D.is_polygon_clockwise(polygon): hint = -hint
		triangle(st, a + half_thickness, a - half_thickness, b - half_thickness, hint)
		triangle(st, a + half_thickness, b - half_thickness, b + half_thickness, hint)
	return instance(label, st.commit(), parent, color)

static func station(rows: Array, x: float) -> Array:
	for i in rows.size() - 1:
		if x <= float(rows[i + 1][0]) + 1e-8:
			var t := (x - float(rows[i][0])) / (float(rows[i + 1][0]) - float(rows[i][0]))
			return [x, lerpf(rows[i][1], rows[i + 1][1], t), lerpf(rows[i][2], rows[i + 1][2], t), lerpf(rows[i][3], rows[i + 1][3], t)]
	return rows[-1]

static func plan_point(panel: Dictionary, x: float, chord_fraction: float, side: float) -> Vector3:
	var s := station(panel.stations, x)
	return Vector3(side * x, s[3], lerpf(s[1], s[2], chord_fraction))

static func hinge(root: Node3D, hinges: Dictionary, label: String, a: Vector3, b: Vector3, outline: Array, thickness: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.name = label + "_hinge"
	pivot.position = a
	root.add_child(pivot)
	var local: Array = []
	for p in outline: local.append(p - a)
	slab(local, thickness, pivot, label, RED)
	var axis := (b - a).normalized()
	# Store the axis and rest basis, so deflection never replaces a future static orientation.
	hinges[label] = {node = pivot, axis = axis, rest = pivot.basis, end_a = a, end_b = b, witness = local[2]}

# A curved planform must still rotate around one straight physical hinge.
static func hinge_point(panel: Dictionary, span: Array, x: float, side: float) -> Vector3:
	var a := plan_point(panel, span[1], panel.hinge_fraction, side)
	var b := plan_point(panel, span[2], panel.hinge_fraction, side)
	return a.lerp(b, (x - float(span[1])) / (float(span[2]) - float(span[1])))

static func lifting_surface(root: Node3D, hinges: Dictionary, panel: Dictionary, side: float, tail: bool) -> void:
	var suffix := "left" if side < 0 else "right"
	var spans: Array = [["elevator_" + suffix, panel.stations[0][0], panel.stations[-1][0]]] if tail else [
		["flap_" + suffix, panel.flap_span[0], panel.flap_span[1]],
		["aileron_" + suffix, panel.aileron_span[0], panel.aileron_span[1]]]
	var cuts: Array[float] = []
	for s in panel.stations: cuts.append(float(s[0]))
	for s in spans:
		if not cuts.has(float(s[1])): cuts.append(float(s[1]))
		if not cuts.has(float(s[2])): cuts.append(float(s[2]))
	cuts.sort()
	for i in cuts.size() - 1:
		var start: float = cuts[i]
		var end: float = cuts[i + 1]
		var moving_span: Array = []
		for s in spans:
			if (start + end) * .5 >= float(s[1]) and (start + end) * .5 <= float(s[2]): moving_span = s
		var aa := plan_point(panel, start, 0, side)
		var bb := plan_point(panel, end, 0, side)
		var cc := plan_point(panel, end, 1, side)
		var dd := plan_point(panel, start, 1, side)
		if not moving_span.is_empty():
			cc = hinge_point(panel, moving_span, end, side)
			dd = hinge_point(panel, moving_span, start, side)
			cc.z -= float(panel.gap_m) * .5
			dd.z -= float(panel.gap_m) * .5
		slab([aa, bb, cc, dd], Vector3(0, float(panel.slab_thickness_m) * .5, 0), root,
			("stab" if tail else "wing") + "_" + suffix + "_%s" % i, WHITE)
	for s in spans:
		var a := plan_point(panel, s[1], panel.hinge_fraction, side)
		var b := plan_point(panel, s[2], panel.hinge_fraction, side)
		# Gap behind the hinge is geometric clearance; the physical hinge remains at a/b.
		var gap := Vector3(0, 0, float(panel.gap_m) * .5)
		var outline: Array = [a + gap, b + gap, plan_point(panel, s[2], 1, side)]
		for j in range(panel.stations.size() - 1, -1, -1):
			var x: float = panel.stations[j][0]
			if x > float(s[1]) and x < float(s[2]): outline.append(plan_point(panel, x, 1, side))
		outline.append(plan_point(panel, s[1], 1, side))
		hinge(root, hinges, s[0], a, a + (b - a) * side, outline, Vector3(0, float(panel.control_thickness_m) * .5, 0))

static func cylinder(root: Node3D, label: String, radius: float, length: float, center: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 32
	var node := instance(label, mesh, root, color)
	node.rotation.x = PI / 2
	node.position = center
	return node

static func canopy_frames(parent: Node3D, data: Dictionary) -> void:
	var rows := interpolate_sections(data.canopy_stations, data.loft.longitudinal_subdivisions)
	for index in data.details.canopy_frame_z_m.size():
		var center: float = data.details.canopy_frame_z_m[index]
		var frames: Array = []
		for z in [center - data.details.canopy_frame_width_m * .5, center + data.details.canopy_frame_width_m * .5]:
			for i in rows.size() - 1:
				if z >= rows[i][0] and z <= rows[i + 1][0]:
					var t: float = (z - rows[i][0]) / (rows[i + 1][0] - rows[i][0])
					var offset: float = data.details.canopy_frame_offset_m
					frames.append([z, lerpf(rows[i][1], rows[i + 1][1], t) + offset,
						lerpf(rows[i][2], rows[i + 1][2], t) + offset, lerpf(rows[i][3], rows[i + 1][3], t) - offset])
					break
		# Parent to canopy so the inspector's interior toggle also hides the frames.
		loft(frames, parent, "canopy_frame_%s" % index, WHITE, 1, 1, true)

static func wing_fences(root: Node3D, data: Dictionary) -> void:
	var detail: Dictionary = data.details
	var x: float = detail.fence_span_m
	var s := station(data.wing.stations, x)
	var span: Array = ["aileron", data.wing.aileron_span[0], data.wing.aileron_span[1]]
	for side in [-1.0, 1.0]:
		var hinge_z := hinge_point(data.wing, span, x, side).z
		var aft: float = hinge_z - detail.fence_hinge_clearance_m
		var y: float = s[3]
		var le: float = s[1]
		var outline: Array = [Vector3(side*x,y + detail.fence_bottom_m,le + .025),
			Vector3(side*x,y - .055,le - .025), Vector3(side*x,y + .015,le - .035),
			Vector3(side*x,y + detail.fence_top_m,le + .015), Vector3(side*x,y + .027,aft),
			Vector3(side*x,y - .05,aft)]
		slab(outline, Vector3(detail.fence_thickness_m * .5,0,0), root,
			"wing_fence_left" if side < 0 else "wing_fence_right", WHITE)

static func exhaust(root: Node3D, data: Dictionary) -> void:
	var tail: Array = data.fuselage_stations[-1]
	var z: float = tail[0]
	var radius: float = data.details.exhaust_inner_radius_m
	var depth: float = data.details.exhaust_depth_m
	var rim := SurfaceTool.new()
	var throat := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	throat.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 32:
		var a := TAU * j / 32.0
		var b := TAU * (j + 1) / 32.0
		var oa := Vector3(tail[1]*cos(a),tail[2]*sin(a),z)
		var ob := Vector3(tail[1]*cos(b),tail[2]*sin(b),z)
		var ia := Vector3(radius*cos(a),radius*sin(a),z)
		var ib := Vector3(radius*cos(b),radius*sin(b),z)
		triangle(rim,oa,ob,ib,Vector3.BACK)
		triangle(rim,oa,ib,ia,Vector3.BACK)
		var da := ia - Vector3(0,0,depth)
		var db := ib - Vector3(0,0,depth)
		var inward := -Vector3(cos((a+b)*.5),sin((a+b)*.5),0)
		triangle(throat,ia,ib,db,inward)
		triangle(throat,ia,db,da,inward)
		triangle(throat,Vector3(0,0,z-depth),da,db,Vector3.BACK)
	instance("exhaust_fixed",rim.commit(),root,Color("879198"))
	instance("exhaust_throat",throat.commit(),root,Color("0c141d"))

static func build() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://geometry.json"))
	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("status", data.status)
	var hinges := {}
	var skin := loft(data.fuselage_stations, root, "fuselage", BLUE, 1, data.loft.longitudinal_subdivisions, data.loft.smooth_normals, false)
	var canopy := loft(data.canopy_stations, root, "canopy", DARK, 1, data.loft.longitudinal_subdivisions, data.loft.smooth_normals)
	canopy_frames(canopy, data)
	for side in [-1.0, 1.0]:
		lifting_surface(root, hinges, data.wing, side, false)
		lifting_surface(root, hinges, data.tail, side, true)
	wing_fences(root, data)
	var fin: Dictionary = data.fin
	var a := Vector3(0, fin.hinge_bottom_yz[0], fin.hinge_bottom_yz[1])
	var b := Vector3(0, fin.hinge_top_yz[0], fin.hinge_top_yz[1])
	var outline: Array = []
	for i in int(fin.leading_outline_count): outline.append(Vector3(0, fin.outline_yz[i][0], fin.outline_yz[i][1]))
	outline.append(b)
	outline.append(a)
	slab(outline, Vector3(fin.thickness_m * .5, 0, 0), root, "fin", WHITE)
	hinge(root, hinges, "rudder", a, b, [a + Vector3(0, 0, .003), b + Vector3(0, 0, .003),
		Vector3(0, fin.outline_yz[-2][0], fin.outline_yz[-2][1]), Vector3(0, fin.outline_yz[-1][0], fin.outline_yz[-1][1])], Vector3(.005, 0, 0))
	var motor := cylinder(root, "p100rx_nominal_envelope", data.nominal.engine_diameter_m * .5,
		data.nominal.engine_length_m, point(data.installation.engine_center), Color("a8b2b7"))
	motor.visible = false
	for side in [-1.0, 1.0]:
		var suffix := "left" if side < 0 else "right"
		loft(data.installation.intake_stations, root, "intake_fairing_" + suffix, WHITE, side)
		loft(data.installation.intake_shadow_stations, root, "intake_shadow_" + suffix, DARK, side)
	exhaust(root, data)
	var propeller := Node3D.new()
	propeller.name = "propeller"
	root.add_child(propeller) # compatibility placeholder: no geometry and no rotation
	return {root = root, hinges = hinges, data = data, propeller = propeller, skin = skin, canopy = canopy, motor = motor, has_propeller = false}

static func apply_controls(model: Dictionary, roll: float, pitch: float, yaw: float, flap_deg: float) -> void:
	var c: Dictionary = model.data.controls_deg
	roll = clampf(roll, -1, 1)
	pitch = clampf(pitch, -1, 1)
	yaw = clampf(yaw, -1, 1)
	var left := roll * (float(c.aileron_down) if roll >= 0 else float(c.aileron_up))
	var right := -roll * (float(c.aileron_up) if roll >= 0 else float(c.aileron_down))
	var angles := {aileron_left = left, aileron_right = right,
		elevator_left = -pitch * float(c.elevator_up), elevator_right = -pitch * float(c.elevator_up),
		rudder = yaw * float(c.rudder_each_side), flap_left = clampf(flap_deg, 0, c.flap_landing), flap_right = clampf(flap_deg, 0, c.flap_landing)}
	for key in angles:
		var h: Dictionary = model.hinges[key]
		h.node.basis = Basis(h.axis, deg_to_rad(angles[key])) * h.rest
