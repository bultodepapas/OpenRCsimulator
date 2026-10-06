# EX-02 visual preview of the Great Planes Extra 300S .60 (GPMA0236). Not flyable yet: no physics data.
# Coordinates/provenance live in generated extra_300s_geometry.gd. Native Godot geometry, no importer.
# Interface matches the Stik builder: build() -> {root, propeller, hinges, gear}; hinge nodes carry only the
# commanded deflection, their static parent frames carry the swept hinge-line orientation.
extends RefCounted

const Geometry := preload("res://aircraft/extra_300s_geometry.gd")
const D: Dictionary = Geometry.DATA
const VISUAL_REVISION := "gp-extra-300s-60-ex02-preview"
const RED := Color("c41e2a")
const WHITE := Color("f1efe8")
const GLASS := Color("1c2733")
const METAL := Color("8b9299")
const TIRE := Color("1a1c20")
const PROP := Color("24262b")
const RING_CORNER_SEGMENTS := 6
const CHORD_SAMPLES := 22

static var _materials := {}


## Shared, immutable materials: one instance per finish, reused by every build.
static func material(color: Color, roughness := 0.55, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [color.to_html(), roughness, metallic]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		_materials[key] = m
	return _materials[key]


# Godot front faces are clockwise; order the vertices so the face normal agrees with the outward hint.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, outward: Vector3) -> void:
	var face := (c - a).cross(b - a)
	if face.length_squared() < 1e-14:
		return
	var points := [a, b, c]
	var normals := [na, nb, nc]
	if face.dot(outward) < 0.0:
		points = [a, c, b]
		normals = [na, nc, nb]
	for k in 3:
		st.set_normal(normals[k])
		st.add_vertex(points[k])


static func _instance(label: String, mesh: Mesh, parent: Node3D, position := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = position
	parent.add_child(node)
	return node


static func _surface(mat: Material) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	return st


# Loft through closed rings that share a point count. Vertex normals come from the grid tangents and are
# turned away from each ring's centroid; flat caps close the first and last rings when requested.
static func _loft(rings: Array, mat: Material, caps := [true, true]) -> ArrayMesh:
	var st := _surface(mat)
	var count: int = rings[0].size()
	var centers: Array[Vector3] = []
	for ring in rings:
		var c := Vector3.ZERO
		for p in ring: c += p
		centers.append(c / count)
	var normals: Array = []
	for i in rings.size():
		var row: Array[Vector3] = []
		for j in count:
			var around: Vector3 = rings[i][(j + 1) % count] - rings[i][(j - 1 + count) % count]
			var along: Vector3 = rings[mini(i + 1, rings.size() - 1)][j] - rings[maxi(i - 1, 0)][j]
			var n := around.cross(along)
			var out: Vector3 = rings[i][j] - centers[i]
			if n.length_squared() < 1e-14: n = out
			if n.dot(out) < 0.0: n = -n
			row.append(n.normalized() if n.length_squared() > 1e-14 else Vector3.UP)
		normals.append(row)
	for i in rings.size() - 1:
		for j in count:
			var k := (j + 1) % count
			var out: Vector3 = (rings[i][j] + rings[i + 1][k]) * 0.5 - (centers[i] + centers[i + 1]) * 0.5
			_tri(st, rings[i][j], rings[i][k], rings[i + 1][k], normals[i][j], normals[i][k], normals[i + 1][k], out)
			_tri(st, rings[i][j], rings[i + 1][k], rings[i + 1][j], normals[i][j], normals[i + 1][k], normals[i + 1][j], out)
	for end in [0, rings.size() - 1]:
		if not caps[0 if end == 0 else 1]: continue
		var axis: Vector3 = (centers[end] - centers[1 if end == 0 else end - 1]).normalized()
		for j in count:
			_tri(st, centers[end], rings[end][j], rings[end][(j + 1) % count], axis, axis, axis, axis)
	return st.commit()


# Rounded-rectangle fuselage ring; corner radii are fractions of the half-width, limited by the height.
static func _fuselage_ring(z: float, half_width: float, top: float, bottom: float, top_round: float, bottom_round: float) -> Array[Vector3]:
	var height := top - bottom
	var rt := minf(top_round * half_width, height * 0.6)
	var rb := minf(bottom_round * half_width, height - rt)
	var ring: Array[Vector3] = []
	var corners := [
		[Vector2(half_width - rt, top - rt), rt, 90.0, 0.0],
		[Vector2(half_width - rb, bottom + rb), rb, 0.0, -90.0],
		[Vector2(-(half_width - rb), bottom + rb), rb, -90.0, -180.0],
		[Vector2(-(half_width - rt), top - rt), rt, 180.0, 90.0],
	]
	for corner in corners:
		for s in RING_CORNER_SEGMENTS + 1:
			var angle := deg_to_rad(lerpf(corner[2], corner[3], float(s) / RING_CORNER_SEGMENTS))
			var p: Vector2 = corner[0] + Vector2(cos(angle), sin(angle)) * float(corner[1])
			ring.append(Vector3(p.x, p.y, z))
	return ring


static func _station_value(z: float, column: int) -> float:
	var rows: Array = D.fuselage_stations
	if z <= rows[0][0]: return rows[0][column]
	for i in rows.size() - 1:
		if z <= rows[i + 1][0]:
			return lerpf(rows[i][column], rows[i + 1][column], (z - rows[i][0]) / (rows[i + 1][0] - rows[i][0]))
	return rows[-1][column]


static func _fuselage(root: Node3D) -> void:
	var rings: Array = []
	for s in D.fuselage_stations:
		rings.append(_fuselage_ring(s[0], s[1], s[2], s[3], s[4], s[5]))
	_instance("fuselage", _loft(rings, material(RED, 0.45)), root)


static func _canopy(root: Node3D) -> void:
	var c: Dictionary = D.canopy
	var zs: Array[float] = []
	for k in 25: zs.append(lerpf(c.top[0][0], c.top[-1][0], float(k) / 24.0)) # dense enough to round the ends
	for s in D.fuselage_stations:
		if s[0] > c.top[0][0] and s[0] < c.top[-1][0]: zs.append(s[0])
	zs.sort()
	var rings: Array = []
	for z in zs:
		var top := 0.0
		for i in c.top.size() - 1:
			if z >= c.top[i][0] and z <= c.top[i + 1][0]:
				top = lerpf(c.top[i][1], c.top[i + 1][1], (z - c.top[i][0]) / (c.top[i + 1][0] - c.top[i][0]))
		var base := _station_value(z, 2) - 0.002
		# Plan outline: superellipse (n = 4) along the canopy length, straight sides and rounded ends.
		var u := absf((z - (zs[0] + zs[-1]) / 2.0) / ((zs[-1] - zs[0]) / 2.0))
		var half: float = c.halfwidth_fraction * _station_value(z, 1) * pow(maxf(1.0 - pow(u, 4.0), 0.0), 0.25)
		var ring: Array[Vector3] = []
		for k in 13:
			var angle := PI * float(k) / 12.0
			ring.append(Vector3(half * cos(angle), base + maxf(top - base + 0.002, 0.0) * sin(angle), z))
		rings.append(ring)
	_instance("canopy", _loft(rings, material(GLASS, 0.12, 0.2), [false, false]), root)


# Symmetric section: half-thickness/chord at chord fraction x, linearly interpolated from the traced table.
static func _half_thickness(x: float) -> float:
	var table: Array = D.wing.section
	for i in table.size() - 1:
		if x <= table[i + 1][0]:
			return lerpf(table[i][1], table[i + 1][1], (x - table[i][0]) / (table[i + 1][0] - table[i][0]))
	return table[-1][1]


static func _chord(span: float) -> float:
	var w: Dictionary = D.wing
	return lerpf(w.root_chord, w.tip_chord, span / (w.span / 2.0))


static func _le_z(span: float) -> float:
	var w: Dictionary = D.wing
	return lerpf(w.le_z_root, w.le_z_tip, span / (w.span / 2.0))


# Closed section ring at spanwise station x (signed), chord fractions [x0, x1]; a nose at x0 > 0 is a 45 deg
# bevel ending on the hinge axis, so a deflecting aileron turns about its own nose.
static func _wing_ring(x: float, x0: float, x1: float, bevel_nose := false) -> Array[Vector3]:
	var span := absf(x)
	var c := _chord(span)
	var le := _le_z(span)
	var y0: float = D.wing.chord_plane_y
	var upper: Array[Vector3] = []
	var lower: Array[Vector3] = []
	var start := x0
	if bevel_nose: start = x0 + _half_thickness(x0) # 45 deg in chord-normalized units
	for k in CHORD_SAMPLES + 1:
		var u := float(k) / CHORD_SAMPLES
		var xc := lerpf(start, x1, 0.5 - 0.5 * cos(PI * u)) if start <= 0.0 else lerpf(start, x1, u)
		var t := _half_thickness(xc) * c
		upper.append(Vector3(x, y0 + t, le + xc * c))
		lower.append(Vector3(x, y0 - t, le + xc * c))
	var ring: Array[Vector3] = []
	if bevel_nose: ring.append(Vector3(x, y0, le + x0 * c))
	elif x0 > 0.0: lower[0] = Vector3(x, y0 - _half_thickness(x0) * c, le + x0 * c)
	for p in upper: ring.append(p)
	for k in range(lower.size() - 1, -1, -1):
		if k == 0 and x0 <= 0.0: continue # shared leading-edge point
		ring.append(lower[k])
	return ring


# Hinge chord fraction at a spanwise station: constant aileron chord, so the line is parallel to the TE.
static func _hinge_fraction(span: float) -> float:
	return 1.0 - float(D.wing.aileron_chord) / _chord(span)


static func _wing_panel(label: String, a: float, b: float, part: String, parent: Node3D, to_local := Transform3D.IDENTITY) -> void:
	var g: float = D.wing.hinge_gap / 2.0
	var rings: Array = []
	for x in [a, b]:
		var span := absf(x)
		var h := _hinge_fraction(span)
		var ring: Array[Vector3]
		match part:
			"full": ring = _wing_ring(x, 0.0, 1.0)
			"fixed": ring = _wing_ring(x, 0.0, h - g / _chord(span))
			"aileron": ring = _wing_ring(x, h + g / _chord(span), 1.0, true)
		var local: Array[Vector3] = []
		for p in ring: local.append(to_local * p)
		rings.append(local)
	var color := RED if part == "aileron" else WHITE
	_instance(label, _loft(rings, material(color, 0.4)), parent)


static func _hinge(label: String, parent: Node3D, hinges: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label + "_hinge"
	parent.add_child(pivot)
	hinges[label] = pivot
	return pivot


static func _wings(root: Node3D, hinges: Dictionary) -> void:
	var w: Dictionary = D.wing
	var half: float = w.span / 2.0
	var inner: float = w.aileron_inner
	var outer: float = w.aileron_outer
	var end_gap := 0.002
	# TE slope dz/dspan; the hinge line runs parallel to it.
	var te_slope := (_le_z(half) + _chord(half) - _le_z(0.0) - _chord(0.0)) / half
	for sign in [-1.0, 1.0]:
		var suffix := "right" if sign > 0 else "left"
		var wing := Node3D.new()
		wing.name = "wing_" + suffix
		root.add_child(wing)
		_wing_panel("wing_%s_root" % suffix, 0.0, sign * inner, "full", wing)
		_wing_panel("wing_%s_ahead_of_aileron" % suffix, sign * inner, sign * outer, "fixed", wing)
		_wing_panel("wing_%s_tip" % suffix, sign * outer, sign * half, "full", wing)
		# Static frame on the swept hinge line: local +X along the hinge toward +X, +Y up, +Z aft.
		var mid := (inner + outer) / 2.0
		var frame := Node3D.new()
		frame.name = "aileron_frame_" + suffix
		frame.position = Vector3(sign * mid, w.chord_plane_y, _le_z(mid) + _chord(mid) - float(w.aileron_chord))
		frame.rotation.y = atan(-sign * te_slope)
		wing.add_child(frame)
		var pivot := _hinge("aileron_" + suffix, frame, hinges)
		var to_local := frame.transform.affine_inverse()
		var a: float = sign * (inner + end_gap)
		var b: float = sign * (outer - end_gap)
		_wing_panel("aileron_" + suffix, minf(a, b), maxf(a, b), "aileron", pivot, to_local)


# Flat outline extruded symmetrically; outline points are [u, v] mapped by `axes` to the node's local frame.
static func _plate(label: String, outline: Array, thickness: float, color: Color, parent: Node3D, vertical := false) -> MeshInstance3D:
	var polygon := PackedVector2Array()
	for p in outline: polygon.append(Vector2(p[0], p[1]))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():
		# An assert would stop a headless run in the debugger; an engine error fails app/test.sh instead.
		push_error("Extra model: outline %s does not triangulate" % label)
		return _instance(label, ArrayMesh.new(), parent)
	var to3 := func(p: Vector2, side: float) -> Vector3:
		return Vector3(side * thickness / 2.0, p.x, p.y) if vertical else Vector3(p.x, side * thickness / 2.0, p.y)
	var st := _surface(material(color, 0.4))
	for side in [-1.0, 1.0]:
		var n := Vector3(side, 0, 0) if vertical else Vector3(0, side, 0)
		for i in range(0, triangles.size(), 3):
			_tri(st, to3.call(polygon[triangles[i]], side), to3.call(polygon[triangles[i + 1]], side), to3.call(polygon[triangles[i + 2]], side), n, n, n, n)
	var center := Vector2.ZERO
	for p in polygon: center += p
	center /= polygon.size()
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var mid := (p + q) * 0.5
		var edge := q - p
		var n2 := Vector2(edge.y, -edge.x).normalized()
		if n2.dot(mid - center) < 0.0: n2 = -n2
		var n := Vector3(0, n2.x, n2.y) if vertical else Vector3(n2.x, 0, n2.y)
		_tri(st, to3.call(p, -1.0), to3.call(q, -1.0), to3.call(q, 1.0), n, n, n, n)
		_tri(st, to3.call(p, -1.0), to3.call(q, 1.0), to3.call(p, 1.0), n, n, n, n)
	return _instance(label, st.commit(), parent)


static func _tail(root: Node3D, hinges: Dictionary) -> void:
	var t: Dictionary = D.tail
	var g: float = t.hinge_gap / 2.0
	var hz: float = t.elevator_hinge_z
	var hs: float = t.stab_half_span
	# Horizontal tail in a frame on the elevator hinge line, pitched by the plan's stab incidence.
	var frame := Node3D.new()
	frame.name = "tail_frame"
	frame.position = Vector3(0, t.stab_y, hz)
	frame.rotation.x = deg_to_rad(t.stab_incidence_deg)
	root.add_child(frame)
	var stab := [[-hs, t.stab_tip_le_z - hz], [0.0, t.stab_root_le_z - hz], [hs, t.stab_tip_le_z - hz], [hs, -g], [-hs, -g]]
	_plate("stab", stab, t.stab_thickness, WHITE, frame)
	var elevator := _hinge("elevator", frame, hinges)
	var inner: Array = t.elevator_inner_hinge
	var corner: Array = t.elevator_root_corner
	for sign in [-1.0, 1.0]:
		var outline := [[sign * inner[0], g], [sign * hs, g], [sign * hs, t.elevator_tip_te_z - hz], [sign * corner[0], corner[1] - hz], [sign * inner[0], inner[1] - hz]]
		_plate("elevator_" + ("right" if sign > 0 else "left"), outline, t.stab_thickness * 0.8, RED, elevator)
	# Fin and rudder: outlines are [height y, z] in a frame on the rudder hinge line.
	var rz: float = t.rudder_hinge_z
	var rudder_frame := Node3D.new()
	rudder_frame.name = "fin_frame"
	rudder_frame.position = Vector3(0, 0, rz)
	root.add_child(rudder_frame)
	var le: Array = t.fin_root_le
	var bal_y: float = t.balance_bottom_y
	var fin := [[_station_value(le[0], 2) - 0.005, le[0] - rz], [le[1], le[0] - rz], [bal_y - g, t.balance_front_z - rz - 0.001], [bal_y - g, -g], [_station_value(rz, 2) - 0.005, -g]]
	_plate("fin", fin, t.fin_thickness, WHITE, rudder_frame, true)
	var rudder := _hinge("rudder", rudder_frame, hinges)
	var low: Array = t.rudder_te_low
	var bottom_corner: Array = t.rudder_bottom_corner
	var bottom_hinge: Array = t.rudder_bottom_hinge
	var outline := [[bottom_hinge[1], g], [bal_y + g, g], [bal_y + g, t.balance_front_z - rz], [t.fin_top_y, t.fin_le_top_z - rz], [t.fin_top_y, t.rudder_top_te_z - rz], [low[1], low[0] - rz], [bottom_corner[1], bottom_corner[0] - rz]]
	_plate("rudder", outline, t.fin_thickness, RED, rudder, true)


static func _cylinder(label: String, radius: float, length: float, color: Color, parent: Node3D, segments := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material(color, 0.6 if color == TIRE else 0.35, 0.6 if color == METAL else 0.0)
	return _instance(label, mesh, parent)


static func _strut(label: String, a: Vector3, b: Vector3, radius: float, parent: Node3D) -> void:
	var rod := _cylinder(label, radius, (b - a).length(), METAL, parent, 8)
	rod.position = (a + b) * 0.5
	rod.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


static func _wheel(label: String, diameter: float, width: float, center: Vector3, parent: Node3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label
	pivot.position = center
	parent.add_child(pivot)
	var tire := _cylinder(label + "_tire", diameter / 2.0, width, TIRE, pivot, 20)
	tire.rotation.z = PI / 2.0
	return pivot


static func _gear(root: Node3D) -> Dictionary:
	var g: Dictionary = D.gear
	var gear := {}
	for sign in [-1.0, 1.0]:
		var suffix := "right" if sign > 0 else "left"
		var axle := Vector3(sign * g.track / 2.0, g.main_axle[1], g.main_axle[0])
		_strut("main_leg_" + suffix, Vector3(sign * g.leg_root_half_spacing, g.main_leg_root[1], g.main_leg_root[0]), axle - Vector3(sign * 0.02, 0, 0), 0.0045, root)
		gear[suffix] = _wheel("wheel_" + suffix, g.main_wheel_diameter, 0.022, axle, root)
		var pant := MeshInstance3D.new()
		pant.name = "wheel_pant_" + suffix
		var shell := SphereMesh.new()
		shell.radius = 1.0
		shell.height = 2.0
		shell.material = material(RED, 0.45)
		pant.mesh = shell
		pant.position = Vector3(axle.x, (g.pant_y[0] + g.pant_y[1]) / 2.0, (g.pant_z[0] + g.pant_z[1]) / 2.0)
		pant.scale = Vector3(g.pant_half_width, absf(g.pant_y[0] - g.pant_y[1]) / 2.0, (g.pant_z[1] - g.pant_z[0]) / 2.0)
		root.add_child(pant)
	# Tail wheel steers with a pivot on the rudder hinge line.
	var t: Dictionary = D.tail
	var steering := Node3D.new()
	steering.name = "tail_steering"
	steering.position = Vector3(0, t.rudder_bottom_hinge[1], t.rudder_hinge_z)
	root.add_child(steering)
	var axle_local := Vector3(0, g.tail_axle[1], g.tail_axle[0]) - steering.position
	_strut("tail_wire", Vector3(0, 0.004, 0.008), axle_local, 0.0012, steering)
	gear["tail"] = _wheel("wheel_tail", g.tail_wheel_diameter, 0.01, axle_local, steering)
	gear["steering"] = steering
	return gear


static func _propeller(root: Node3D) -> Node3D:
	var p: Dictionary = D.propeller
	var s: Dictionary = D.spinner
	# Thrust frame: plan side/top notes (2 deg right, 0.5 deg down). Visual only; physics thrust is EX-06.
	var thrust := Node3D.new()
	thrust.name = "thrust_frame"
	thrust.position = Vector3(0, 0, s.back_z)
	thrust.rotation = Vector3(-deg_to_rad(p.down_thrust_deg), -deg_to_rad(p.right_thrust_deg), 0)
	root.add_child(thrust)
	# Spinner: lathe from the back plate (z=0 in this frame) to the tip.
	var rings: Array = []
	var length: float = s.back_z - s.tip_z
	for k in 11:
		var u := float(k) / 10.0
		var r: float = s.radius * pow(sin(u * PI / 2.0), 0.75)
		var ring: Array[Vector3] = []
		for j in 20:
			var angle := TAU * j / 20.0
			ring.append(Vector3(r * cos(angle), r * sin(angle), -length * (1.0 - u)))
		rings.append(ring)
	_instance("spinner", _loft(rings, material(WHITE, 0.3), [false, true]), thrust)
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(0, 0, p.z - s.back_z)
	thrust.add_child(propeller)
	for side in [-1.0, 1.0]:
		var blade := MeshInstance3D.new()
		blade.name = "blade_" + ("a" if side > 0 else "b")
		var box := BoxMesh.new()
		box.size = Vector3(p.diameter / 2.0 - 0.02, 0.024, 0.004)
		box.material = material(PROP, 0.5)
		blade.mesh = box
		blade.position = Vector3(side * (p.diameter / 4.0 + 0.01), 0, 0)
		blade.rotation.x = side * deg_to_rad(18.0)
		propeller.add_child(blade)
	return propeller


static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("aircraft_id", D.id)
	root.set_meta("visual_revision", VISUAL_REVISION)
	root.set_meta("status", "preview: visual only, not flyable")
	root.set_meta("evidence", "assets/aircraft/extra-300s-60/geometry.json; research/extra-300/ex01/metrology.json")
	var hinges := {}
	_fuselage(root)
	_canopy(root)
	_wings(root, hinges)
	_tail(root, hinges)
	var gear := _gear(root)
	var propeller := _propeller(root)
	return {root = root, propeller = propeller, hinges = hinges, gear = gear}
