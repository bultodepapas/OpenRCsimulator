# EX-02 visual preview of the Great Planes Extra 300S .60 (GPMA0236). Not flyable yet: no physics data.
# Coordinates/provenance live in generated extra_300s_geometry.gd. Native Godot geometry, no importer.
# Interface matches the Stik builder: build() -> {root, propeller, hinges, gear}; hinge nodes carry only the
# commanded deflection, their static parent frames carry the swept hinge-line orientation.
extends RefCounted

const Geometry := preload("res://aircraft/extra_300s_geometry.gd")
const Finish := preload("res://aircraft/extra_300s_finish.gd")
const D: Dictionary = Geometry.DATA
const VISUAL_REVISION := "gp-extra-300s-60-ex04-pilot"
const RED := Color("c4182a") # = appearance.json colors.red (verify_extra checks it)
const WHITE := Color("f1efe8")
const GLASS := Color("1c2733")
const COCKPIT := Color("1a1d22")
const METAL := Color("8b9299")
const TIRE := Color("1a1c20")
const PROP := Color("24262b")
const RING_CORNER_SEGMENTS := 10
const LOFT_STEP_M := 0.015 # longitudinal ring spacing between measured stations
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
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, outward: Vector3, uv := [], uv2 := []) -> void:
	var face := (c - a).cross(b - a)
	if face.length_squared() < 1e-14:
		return
	var order := [0, 1, 2] if face.dot(outward) >= 0.0 else [0, 2, 1]
	var points := [a, b, c]
	var normals := [na, nb, nc]
	for k in order:
		st.set_normal(normals[k])
		if not uv.is_empty(): st.set_uv(uv[k])
		if not uv2.is_empty(): st.set_uv2(uv2[k])
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
# uvs/uv2s (optional): one Array[Vector2] per ring, matching its points; consumed by the procedural finish.
static func _loft(rings: Array, mat: Material, caps := [true, true], uvs := [], uv2s := []) -> ArrayMesh:
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
			_tri(st, rings[i][j], rings[i][k], rings[i + 1][k], normals[i][j], normals[i][k], normals[i + 1][k], out,
				_pick(uvs, [[i, j], [i, k], [i + 1, k]]), _pick(uv2s, [[i, j], [i, k], [i + 1, k]]))
			_tri(st, rings[i][j], rings[i + 1][k], rings[i + 1][j], normals[i][j], normals[i + 1][k], normals[i + 1][j], out,
				_pick(uvs, [[i, j], [i + 1, k], [i + 1, j]]), _pick(uv2s, [[i, j], [i + 1, k], [i + 1, j]]))
	for end in [0, rings.size() - 1]:
		if not caps[0 if end == 0 else 1]: continue
		var axis: Vector3 = (centers[end] - centers[1 if end == 0 else end - 1]).normalized()
		for j in count:
			var cap := [[end, -1], [end, j], [end, (j + 1) % count]]
			_tri(st, centers[end], rings[end][j], rings[end][(j + 1) % count], axis, axis, axis, axis, _pick(uvs, cap), _pick(uv2s, cap))
	return st.commit()


# UVs for [ring, point] pairs; point -1 is the ring centre (mean UV), used by the end caps.
static func _pick(table: Array, keys: Array) -> Array:
	if table.is_empty(): return []
	var out := []
	for key in keys:
		var row: Array = table[key[0]]
		if key[1] >= 0:
			out.append(row[key[1]])
		else:
			var mean := Vector2.ZERO
			for v in row: mean += v
			out.append(mean / row.size())
	return out


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


## Monotone cubic (Fritsch-Carlson) through [x, y] points sorted by x: exact at every measured point, smooth
## between them, and never beyond the neighbouring measured values (a Catmull-Rom spline would bulge at the
## canopy frame and the cowl chin). Constant outside the range.
static func monotone(points: Array, x: float) -> float:
	var n := points.size()
	if x <= points[0][0]: return points[0][1]
	if x >= points[n - 1][0]: return points[n - 1][1]
	var i := 0
	while x > points[i + 1][0]: i += 1
	var x0: float = points[i][0]
	var h: float = points[i + 1][0] - x0
	var t := (x - x0) / h
	var m0 := _tangent(points, i)
	var m1 := _tangent(points, i + 1)
	return (2*t*t*t - 3*t*t + 1) * points[i][1] + (t*t*t - 2*t*t + t) * h * m0 + (-2*t*t*t + 3*t*t) * points[i + 1][1] + (t*t*t - t*t) * h * m1


static func _secant(points: Array, k: int) -> float:
	return (points[k + 1][1] - points[k][1]) / (points[k + 1][0] - points[k][0])


static func _tangent(points: Array, k: int) -> float:
	var n := points.size()
	if k == 0 or k == n - 1:
		return 0.0 # flat ends: no extrapolated bulge at the cowl face or the tail post
	var a := _secant(points, k - 1)
	var b := _secant(points, k)
	if a * b <= 0.0:
		return 0.0 # local extremum or flat: keep it a measured extremum
	var h0: float = points[k][0] - points[k - 1][0]
	var h1: float = points[k + 1][0] - points[k][0]
	return 3.0 * (h0 + h1) / ((2.0 * h1 + h0) / a + (h1 + 2.0 * h0) / b) # Fritsch-Butland weighted harmonic mean


static var _columns := {}


## Smooth fuselage profile: column 1 half-width, 2 top, 3 bottom (monotone cubic through the stations).
static func profile(z: float, column: int) -> float:
	if not _columns.has(column):
		var points := []
		for s in D.fuselage_stations: points.append([s[0], s[column]])
		_columns[column] = points
	return monotone(_columns[column], z)


static func _fuselage(root: Node3D) -> void:
	var rings: Array = []
	var uvs: Array = []
	var rows: Array = D.fuselage_stations
	for i in rows.size():
		var steps := 1 if i == rows.size() - 1 else maxi(1, ceili((rows[i + 1][0] - rows[i][0]) / LOFT_STEP_M))
		for k in steps:
			if i == rows.size() - 1 and k > 0: break
			var z: float = rows[i][0] if i == rows.size() - 1 else lerpf(rows[i][0], rows[i + 1][0], float(k) / steps)
			var top := profile(z, 2)
			var bottom := profile(z, 3)
			var ring := _fuselage_ring(z, profile(z, 1), top, bottom, _station_value(z, 4), _station_value(z, 5))
			var uv: Array[Vector2] = []
			for point in ring: uv.append(Vector2(point.y, z))
			rings.append(ring)
			uvs.append(uv)
	_instance("fuselage", _loft(rings, Finish.material(Finish.FUSELAGE, D.cowl_rear_z), [true, true], uvs), root)


## Half-width of the fuselage skin at height y (same corner rounding as _fuselage_ring), for parts seated on it.
static func skin_half_width(z: float, y: float) -> float:
	var half_width := profile(z, 1)
	var top := profile(z, 2)
	var rt := minf(_station_value(z, 4) * half_width, (top - profile(z, 3)) * 0.6)
	if y <= top - rt: return half_width
	var dy := y - (top - rt)
	return half_width - rt + sqrt(maxf(rt * rt - dy * dy, 0.0))


static func _canopy(root: Node3D) -> void:
	var c: Dictionary = D.canopy
	var zs: Array[float] = []
	for k in 41: zs.append(lerpf(c.top[0][0], c.top[-1][0], float(k) / 40.0)) # dense enough to round the ends
	for s in D.fuselage_stations:
		if s[0] > c.top[0][0] and s[0] < c.top[-1][0]: zs.append(s[0])
	zs.sort()
	var rings: Array = []
	for z in zs:
		var top := monotone(c.top, z)
		var base := profile(z, 2) - 0.002 # seated just under the skin; the crown stays on the measured line
		# Plan outline: superellipse (n = 4) along the canopy length, straight sides and rounded ends.
		var u := absf((z - (zs[0] + zs[-1]) / 2.0) / ((zs[-1] - zs[0]) / 2.0))
		# Never wider than the skin it sits on: over the rounded turtle deck the seat narrows.
		var half: float = minf(c.halfwidth_fraction * profile(z, 1) * pow(maxf(1.0 - pow(u, 4.0), 0.0), 0.25), skin_half_width(z, base))
		var ring: Array[Vector3] = []
		for k in 25:
			var angle := PI * float(k) / 24.0
			ring.append(Vector3(half * cos(angle), base + maxf(top - base, 0.0) * sin(angle), z))
		rings.append(ring)
	_instance("canopy", _loft(rings, _glass(), [false, false]), root)
	# Dark cockpit floor just above the skin under the canopy, so the transparent canopy shows a cockpit.
	var floor_rings: Array = []
	for ring in rings:
		var left: Vector3 = ring[ring.size() - 1]
		var right: Vector3 = ring[0]
		floor_rings.append([left + Vector3(0.002, 0.003, 0), right + Vector3(-0.002, 0.003, 0)])
	var st := _surface(material(COCKPIT, 0.9))
	for i in floor_rings.size() - 1:
		var fa: Vector3 = floor_rings[i][0]
		var fb: Vector3 = floor_rings[i][1]
		var fc: Vector3 = floor_rings[i + 1][1]
		var fd: Vector3 = floor_rings[i + 1][0]
		_tri(st, fa, fb, fc, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP)
		_tri(st, fa, fc, fd, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP)
	_instance("cockpit_floor", st.commit(), root)


# Tinted canopy: transparency from appearance.json (alpha 1.0 = opaque fallback).
static func _glass() -> StandardMaterial3D:
	var alpha: float = Finish.A.canopy.alpha
	if alpha >= 1.0: return material(GLASS, 0.12, 0.2)
	if not _materials.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(GLASS, alpha)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.3
		m.metallic_specular = 0.8
		_materials["glass"] = m
	return _materials["glass"]


# Closed ellipsoid (or its part above y_cut) as a latitude-longitude loft. The node sits at the centre, so a
# rotation set on it turns the shape about its own centre.
static func _ellipsoid(label: String, center: Vector3, radii: Vector3, color: Color, parent: Node3D, y_cut := -INF) -> MeshInstance3D:
	var rings: Array = []
	var lowest := -PI / 2.0 if y_cut == -INF else asin(clampf((y_cut - center.y) / radii.y, -1.0, 1.0))
	for i in 13:
		var lat := lerpf(lowest, PI / 2.0, float(i) / 12.0)
		var ring: Array[Vector3] = []
		for k in 20:
			var lon := TAU * k / 20.0
			ring.append(Vector3(radii.x * cos(lat) * cos(lon), radii.y * sin(lat), radii.z * cos(lat) * sin(lon)))
		rings.append(ring)
	return _instance(label, _loft(rings, material(color, 0.6), [y_cut != -INF, false]), parent, center)


# Stylised pilot from the plan side view: head, cap with brim, neck and torso down into the cockpit.
static func _pilot(root: Node3D) -> void:
	var p: Dictionary = D.pilot
	var colors: Dictionary = Finish.A.pilot_colors
	var node := Node3D.new()
	node.name = "pilot"
	root.add_child(node)
	var head_z: float = (p.nose_front[0] + p.head_back[0]) / 2.0
	var head_y: float = (p.chin[1] + p.cap_brim_front[1]) / 2.0 + 0.004
	var head := Vector3(0, head_y, head_z)
	var head_radii := Vector3(p.head_half_width, (p.cap_brim_front[1] - p.chin[1]) / 2.0 + 0.006, (p.head_back[0] - p.nose_front[0]) / 2.0)
	_ellipsoid("pilot_head", head, head_radii, Color(colors.skin), node)
	var brim_y: float = p.cap_brim_front[1]
	var cap_radii := Vector3(p.head_half_width + 0.002, p.cap_top[1] - brim_y, head_radii.z + 0.002)
	_ellipsoid("pilot_cap", Vector3(0, brim_y, head_z), cap_radii, Color(colors.cap), node, brim_y)
	var brim := _ellipsoid("pilot_cap_brim", Vector3(0, brim_y - 0.001, (p.cap_brim_front[0] + head_z) / 2.0 - 0.004),
		Vector3(p.head_half_width * 0.9, 0.0025, (head_z - p.cap_brim_front[0]) / 2.0 + 0.006), Color(colors.cap), node)
	brim.rotation.x = deg_to_rad(-8.0)
	var shoulder_y: float = (p.shoulder_front[1] + p.shoulder_back[1]) / 2.0
	var torso_z: float = (p.shoulder_front[0] + p.shoulder_back[0]) / 2.0
	_ellipsoid("pilot_neck", Vector3(0, (p.chin[1] + shoulder_y) / 2.0, head_z + 0.006), Vector3(0.009, 0.012, 0.01), Color(colors.skin), node)
	_ellipsoid("pilot_torso", Vector3(0, shoulder_y - 0.03, torso_z), Vector3(p.shoulder_half_width, 0.034, (p.shoulder_back[0] - p.shoulder_front[0]) / 2.0),
		Color(colors.shirt), node)


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
	var uvs: Array = []
	var uv2s: Array = []
	for x in [a, b]:
		var span := absf(x)
		var h := _hinge_fraction(span)
		var ring: Array[Vector3]
		match part:
			"full": ring = _wing_ring(x, 0.0, 1.0)
			"fixed": ring = _wing_ring(x, 0.0, h - g / _chord(span))
			"aileron": ring = _wing_ring(x, h + g / _chord(span), 1.0, true)
		var local: Array[Vector3] = []
		var uv: Array[Vector2] = []
		var uv2: Array[Vector2] = []
		for p in ring:
			local.append(to_local * p)
			uv.append(Vector2(span, (p.z - _le_z(span)) / _chord(span)))
			uv2.append(Vector2(_chord(span), 0.0))
		rings.append(local)
		uvs.append(uv)
		uv2s.append(uv2)
	var finish := Finish.material(Finish.AILERON if part == "aileron" else Finish.WING)
	_instance(label, _loft(rings, finish, [true, true], uvs, uv2s), parent)


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
# Flat surface from an outline of [u, v] points (horizontal: x, z; vertical: y, z), extruded symmetrically.
# part >= 0 selects the procedural finish, with the outline coordinates as UV.
# bevel = {edge_v, below_u}: the strip v in [edge_v, edge_v + thickness/2] where u < below_u gets a 45 deg V-bevel
# (half-thickness = v - edge_v), so a moving surface can turn about its hinge line past its own half-thickness.
static func _plate(label: String, outline: Array, thickness: float, color: Color, parent: Node3D, vertical := false, part := -1, bevel := {}) -> MeshInstance3D:
	var polygon := PackedVector2Array()
	for p in outline: polygon.append(Vector2(p[0], p[1]))
	var pieces := [[polygon, false]]
	if not bevel.is_empty():
		var v0: float = bevel.edge_v
		var v1: float = v0 + thickness / 2.0
		var u1: float = bevel.below_u
		var strip := PackedVector2Array([Vector2(-10.0, v0 - 0.01), Vector2(u1, v0 - 0.01), Vector2(u1, v1), Vector2(-10.0, v1)])
		pieces = []
		for piece in Geometry2D.intersect_polygons(polygon, strip): pieces.append([piece, true])
		for piece in Geometry2D.clip_polygons(polygon, strip): pieces.append([piece, false])
	var st := _surface(material(color, 0.4) if part < 0 else Finish.material(part))
	var built := false
	for entry in pieces:
		built = _plate_piece(st, entry[0], thickness, vertical, bevel, entry[1]) or built
	if not built:
		# An assert would stop a headless run in the debugger; an engine error fails app/test.sh instead.
		push_error("Extra model: outline %s does not triangulate" % label)
		return _instance(label, ArrayMesh.new(), parent)
	return _instance(label, st.commit(), parent)


static func _plate_piece(st: SurfaceTool, polygon: PackedVector2Array, thickness: float, vertical: bool, bevel: Dictionary, beveled: bool) -> bool:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty(): return false
	var half := func(p: Vector2) -> float:
		return clampf(p.y - float(bevel.edge_v), 0.0003, thickness / 2.0) if beveled else thickness / 2.0
	var to3 := func(p: Vector2, side: float) -> Vector3:
		var h: float = half.call(p) * side
		return Vector3(h, p.x, p.y) if vertical else Vector3(p.x, h, p.y)
	for side in [-1.0, 1.0]:
		var axis := Vector3(side, 0, 0) if vertical else Vector3(0, side, 0)
		for i in range(0, triangles.size(), 3):
			var face_uv := [polygon[triangles[i]], polygon[triangles[i + 1]], polygon[triangles[i + 2]]]
			var a: Vector3 = to3.call(face_uv[0], side)
			var b: Vector3 = to3.call(face_uv[1], side)
			var c: Vector3 = to3.call(face_uv[2], side)
			var n := (c - a).cross(b - a).normalized()
			if n.dot(axis) < 0.0: n = -n
			_tri(st, a, b, c, n, n, n, n, face_uv)
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var edge := q - p
		if edge.length_squared() < 1e-12: continue
		var n2 := Vector2(edge.y, -edge.x).normalized()
		if Geometry2D.is_point_in_polygon((p + q) * 0.5 + n2 * 1e-5, polygon): n2 = -n2
		var n := Vector3(0, n2.x, n2.y) if vertical else Vector3(n2.x, 0, n2.y)
		_tri(st, to3.call(p, -1.0), to3.call(q, -1.0), to3.call(q, 1.0), n, n, n, n, [p, q, q])
		_tri(st, to3.call(p, -1.0), to3.call(q, 1.0), to3.call(p, 1.0), n, n, n, n, [p, q, p])
	return true


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
	_plate("stab", stab, t.stab_thickness, WHITE, frame, false, Finish.HORIZONTAL_TAIL)
	var elevator := _hinge("elevator", frame, hinges)
	var inner: Array = t.elevator_inner_hinge
	var corner: Array = t.elevator_root_corner
	for sign in [-1.0, 1.0]:
		var outline := [[sign * inner[0], g], [sign * hs, g], [sign * hs, t.elevator_tip_te_z - hz], [sign * corner[0], corner[1] - hz], [sign * inner[0], inner[1] - hz]]
		_plate("elevator_" + ("right" if sign > 0 else "left"), outline, t.stab_thickness * 0.8, RED, elevator, false, Finish.HORIZONTAL_TAIL, {edge_v = g, below_u = 10.0})
	# Fin and rudder: outlines are [height y, z] in a frame on the rudder hinge line.
	var rz: float = t.rudder_hinge_z
	var rudder_frame := Node3D.new()
	rudder_frame.name = "fin_frame"
	rudder_frame.position = Vector3(0, 0, rz)
	root.add_child(rudder_frame)
	var le: Array = t.fin_root_le
	var bal_y: float = t.balance_bottom_y
	var fin := [[profile(le[0], 2) - 0.005, le[0] - rz], [le[1], le[0] - rz], [bal_y - g, t.balance_front_z - rz - 0.001], [bal_y - g, -g], [profile(rz, 2) - 0.005, -g]]
	_plate("fin", fin, t.fin_thickness, WHITE, rudder_frame, true, Finish.VERTICAL_TAIL)
	var rudder := _hinge("rudder", rudder_frame, hinges)
	var low: Array = t.rudder_te_low
	var bottom_corner: Array = t.rudder_bottom_corner
	var bottom_hinge: Array = t.rudder_bottom_hinge
	var outline := [[bottom_hinge[1], g], [bal_y + g, g], [bal_y + g, t.balance_front_z - rz], [t.fin_top_y, t.fin_le_top_z - rz], [t.fin_top_y, t.rudder_top_te_z - rz], [low[1], low[0] - rz], [bottom_corner[1], bottom_corner[0] - rz]]
	_plate("rudder", outline, t.fin_thickness, RED, rudder, true, Finish.VERTICAL_TAIL, {edge_v = g, below_u = bal_y + g})


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
		_strap("main_leg_" + suffix, sign, root)
		gear[suffix] = _wheel("wheel_" + suffix, g.main_wheel_diameter, 0.022, axle, root)
		_pant("wheel_pant_" + suffix, axle.x, root)
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


# Aluminium strap: edge-on chord from the side view (front/rear edges at root and tip), splayed outward in front
# view from the fuselage bottom to just inboard of the wheel, inside the pant.
static func _strap(label: String, sign: float, parent: Node3D) -> void:
	var g: Dictionary = D.gear
	var leg: Dictionary = g.leg
	var root_x: float = sign * g.leg_root_half_spacing
	var tip_x: float = sign * (g.track / 2.0 - 0.016)
	var root_y: float = leg.root[2] + 0.008 # reaches into the fuselage: no visible seam
	var tip_y: float = leg.tip[2] - 0.01 # ends inside the pant
	var along := Vector2(tip_x - root_x, tip_y - root_y).normalized()
	var across: Vector2 = Vector2(-along.y, along.x) * float(leg.thickness) / 2.0
	var rings: Array = []
	for end in [[root_x, root_y, leg.root], [tip_x, tip_y, leg.tip]]:
		var ring: Array[Vector3] = []
		for corner in [[1.0, 0], [1.0, 1], [-1.0, 1], [-1.0, 0]]:
			var c: Vector2 = Vector2(end[0], end[1]) + across * float(corner[0])
			ring.append(Vector3(c.x, c.y, end[2][corner[1]]))
		rings.append(ring)
	_instance(label, _loft(rings, material(METAL, 0.35, 0.6)), parent)


# Teardrop pant: elliptical sections along the side-view outline; the width follows the local height, so the
# blunt nose stays round and the tail narrows. The wheel's lower arc shows below it, as on the plan.
static func _pant(label: String, center_x: float, parent: Node3D) -> void:
	var g: Dictionary = D.gear
	var profile_rows: Array = g.pant_profile
	var max_height := 0.0
	for row in profile_rows: max_height = maxf(max_height, row[1] - row[2])
	var rings: Array = []
	for row in profile_rows:
		var half_height: float = (row[1] - row[2]) / 2.0
		var half_width: float = g.pant_half_width * pow(2.0 * half_height / max_height, 0.6)
		var ring: Array[Vector3] = []
		for k in 20:
			var angle := TAU * k / 20.0
			ring.append(Vector3(center_x + half_width * cos(angle), (row[1] + row[2]) / 2.0 + half_height * sin(angle), row[0]))
		rings.append(ring)
	_instance(label, _loft(rings, material(RED, 0.45), [false, false]), parent)


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
	_instance("spinner", _loft(rings, material(RED, 0.3), [false, true]), thrust) # red, as in the owner's photo
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(0, 0, p.z - s.back_z)
	thrust.add_child(propeller)
	var blade := _blade_mesh()
	for k in int(p.blades):
		var node := _instance("blade_" + "ab"[k], blade, propeller)
		node.rotation.z = PI * k # second blade: same mesh turned half a revolution about the shaft
	return propeller


static func _table(rows: Array, x: float) -> float:
	if x <= rows[0][0]: return rows[0][1]
	for i in rows.size() - 1:
		if x <= rows[i + 1][0]:
			return lerpf(rows[i][1], rows[i + 1][1], (x - rows[i][0]) / (rows[i + 1][0] - rows[i][0]))
	return rows[-1][1]


# One blade along +X in the propeller frame (shaft along Z, flight toward -Z). Sections twist to atan(P / 2 pi r);
# the flat face looks aft and the cambered face forward, the leading edge leads toward +Y. Sections bunch toward
# the tip so the planform closes round.
static func _blade_mesh() -> ArrayMesh:
	var p: Dictionary = D.propeller
	var tip: float = p.diameter / 2.0
	var root: float = p.hub_radius
	var rings: Array = []
	var stations := 18
	for i in stations + 1:
		var r := lerpf(root, tip, sin(PI / 2.0 * float(i) / stations))
		var x := r / tip
		var chord := _table(p.blade.chord_fraction_of_radius, x) * tip
		var thickness := _table(p.blade.thickness_fraction_of_chord, x) * chord
		var beta := atan(float(p.pitch) / (TAU * r))
		var along := Vector3(0, cos(beta), -sin(beta)) # trailing edge -> leading edge
		var face := Vector3(0, -sin(beta), -cos(beta)) # forward (cambered) face normal
		var ring: Array[Vector3] = []
		for k in 21:
			var s := float(k) / 20.0 # 0 leading edge ... 1 trailing edge, then back along the flat face
			var bump := sqrt(s) * (1.0 - s) / 0.385
			ring.append(Vector3(r, 0, 0) + along * (0.35 - s) * chord + face * thickness * bump)
		for k in range(19, 0, -1):
			var s := float(k) / 20.0
			ring.append(Vector3(r, 0, 0) + along * (0.35 - s) * chord - face * thickness * 0.08 * sqrt(s) * (1.0 - s) / 0.385)
		rings.append(ring)
	return _loft(rings, material(PROP, 0.45))


## Manual p43 high rates (inches at the widest part of each surface) as hinge angles: delta = asin(d / r), with r the
## widest chord of that surface in this geometry. Visual and clearance use only; flight throws come with EX-05.
static func manual_throws_deg() -> Dictionary:
	var t: Dictionary = D.tail
	var widest := {aileron = float(D.wing.aileron_chord), elevator = float(t.elevator_root_corner[1]) - float(t.elevator_hinge_z),
		rudder = float(t.rudder_te_low[0]) - float(t.rudder_hinge_z)}
	var inches := {aileron = 0.625, elevator = 1.25, rudder = 2.5}
	var out := {}
	for k in widest: out[k] = rad_to_deg(asin(minf(inches[k] * 0.0254 / widest[k], 1.0)))
	return out


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
	_pilot(root)
	_wings(root, hinges)
	_tail(root, hinges)
	var gear := _gear(root)
	var propeller := _propeller(root)
	return {root = root, propeller = propeller, hinges = hinges, gear = gear}
