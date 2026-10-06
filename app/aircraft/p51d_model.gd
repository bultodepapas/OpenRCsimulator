# P5-02 visual model of a giant-scale P-51D Mustang (120 cc class, span 2.508 m). Native SurfaceTool lofts, no
# imported assets; every dimension comes from the generated p51d_geometry.gd (scaled full-size data, see its
# DATA.evidence). Interface as the Stik/Extra builders: build() -> {root, propeller, hinges, gear}; hinge nodes carry
# only the commanded deflection, their static parent frames carry dihedral, incidence and hinge sweep:
#   wing (incidence about +X, pivot at the root LE on the chord plane) > wing_frame_<side> (dihedral about +Z)
#   > aileron_frame_<side> (hinge sweep about +Y; local +X along the hinge toward +X, +Y up, +Z aft) > <key>_hinge.
#   tail_frame (stab incidence about +X, on the mean elevator hinge) > elevator_hinge;  fin_frame > rudder_hinge.
# Positive hinge rotation.x moves the trailing edge DOWN (ailerons, elevator); positive rotation.y moves the rudder
# trailing edge RIGHT (+X): the sense input/commands.gd hinge_rotations() produces, same as the Stik and the Extra.
# Finish: original generic natural-metal look (no unit markings or copied artwork).
extends RefCounted

const Geometry := preload("res://aircraft/p51d_geometry.gd")
const D: Dictionary = Geometry.DATA
const Finish := preload("res://aircraft/p51d_finish.gd")
const VISUAL_REVISION := "p51d-mustang-120-v1"
const ALUMINIUM := Color("c9ccd1")
const OLIVE := Color("3f4a2a")
const RED := Color("b8232c")
const YELLOW := Color("e9c227")
const GLASS := Color("1c2733")
const GLASS_ALPHA := 0.35
const COCKPIT := Color("1a1d22")
const DARK := Color("121316")
const METAL := Color("8b9299")
const HUB := Color("a7acb2")
const TIRE := Color("1a1c20")
const PROP := Color("24262b")
const SKIN := Color("d9a67a")
const HELMET := Color("4a3626")
const JACKET := Color("5a3f2b")
const RING_POINTS := 48 # points per fuselage superellipse ring
const LOFT_STEP_M := 0.015 # longitudinal ring spacing between stations
const CHORD_SAMPLES := 22
const SCOOP_TOP_POINTS := 8
const SCOOP_ARC_POINTS := 16
const NOSE_BAND_M := 0.1 # red band: first 0.1 m of the cowl behind the spinner
const SILL_DEPTH_M := 0.045 # canopy sill below the deck line
const TIP_ROUND_M := 0.03 # elliptical thickness fade at the wing tips
const END_GAP_M := 0.002 # spanwise clearance at the ends of moving surfaces
const PROP_TIP_M := 0.03 # yellow blade tips
const HORN_CLEARANCE_M := 0.002 # spanwise gap between the stab's horn cut and the elevator horn (V01)
const STEP_M := 0.0005 # half-length of the near-vertical span step at the horn cut

static var _materials := {}
static var _columns := {}


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


static func _aluminium() -> StandardMaterial3D:
	return material(ALUMINIUM, 0.35, 0.8)


# V08: natural-metal finish with panel lines and rivets (p51d_finish.gd), one shared material per part.
static func _skin(part: int) -> ShaderMaterial:
	return Finish.material(part, D)


# Dark intake throats are seen from inside their lofts: both faces drawn.
static func _throat_material() -> StandardMaterial3D:
	if not _materials.has("throat"):
		var m := StandardMaterial3D.new()
		m.albedo_color = DARK
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["throat"] = m
	return _materials["throat"]


# Tinted canopy, alpha as the Extra's glass.
static func _glass() -> StandardMaterial3D:
	if not _materials.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(GLASS, GLASS_ALPHA)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.3
		m.metallic_specular = 0.8
		_materials["glass"] = m
	return _materials["glass"]


# Godot front faces are clockwise; order the vertices so the face normal agrees with the outward hint.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, outward: Vector3) -> void:
	var face := (c - a).cross(b - a)
	if face.length_squared() < 1e-14:
		return
	var order := [0, 1, 2] if face.dot(outward) >= 0.0 else [0, 2, 1]
	var points := [a, b, c]
	var normals := [na, nb, nc]
	for k in order:
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


# Loft through closed rings that share a point count. Vertex normals come from the grid tangents and are turned
# away from each ring's centroid; flat caps close the first and last rings when requested. `into` appends the loft
# as a new surface of an existing mesh (one MeshInstance3D, several materials).
static func _loft(rings: Array, mat: Material, caps := [true, true], into: ArrayMesh = null) -> ArrayMesh:
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
	return st.commit(into)


# Open strip of quads between rows with the same point count, flat shaded, facing away from the fuselage axis.
static func _strip(rows: Array, mat: Material) -> ArrayMesh:
	var st := _surface(mat)
	var count: int = rows[0].size()
	for i in rows.size() - 1:
		for j in count - 1:
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i][j + 1]
			var c: Vector3 = rows[i + 1][j + 1]
			var d: Vector3 = rows[i + 1][j]
			var out := Vector3(a.x + c.x, a.y + c.y, 0.0)
			var n := (c - a).cross(b - a).normalized()
			if n.dot(out) < 0.0: n = -n
			_tri(st, a, b, c, n, n, n, out)
			_tri(st, a, c, d, n, n, n, out)
	return st.commit()


static func _table(rows: Array, x: float) -> float:
	if x <= rows[0][0]: return rows[0][1]
	for i in rows.size() - 1:
		if x <= rows[i + 1][0]:
			return lerpf(rows[i][1], rows[i + 1][1], (x - rows[i][0]) / (rows[i + 1][0] - rows[i][0]))
	return rows[-1][1]


static func _station_value(z: float, column: int) -> float:
	var rows: Array = D.fuselage_stations
	if z <= rows[0][0]: return rows[0][column]
	for i in rows.size() - 1:
		if z <= rows[i + 1][0]:
			return lerpf(rows[i][column], rows[i + 1][column], (z - rows[i][0]) / (rows[i + 1][0] - rows[i][0]))
	return rows[-1][column]


## Monotone cubic (Fritsch-Carlson) through [x, y] points sorted by x: exact at every station, smooth between them,
## never beyond the neighbouring values. Constant outside the range.
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
		return 0.0 # flat ends: no extrapolated bulge at the spinner back or the tail post
	var a := _secant(points, k - 1)
	var b := _secant(points, k)
	if a * b <= 0.0:
		return 0.0
	var h0: float = points[k][0] - points[k - 1][0]
	var h1: float = points[k + 1][0] - points[k][0]
	return 3.0 * (h0 + h1) / ((2.0 * h1 + h0) / a + (h1 + 2.0 * h0) / b)


## Smooth fuselage profile: column 1 half-width, 2 top, 3 bottom (monotone cubic through the stations).
static func profile(z: float, column: int) -> float:
	if not _columns.has(column):
		var points := []
		for s in D.fuselage_stations: points.append([s[0], s[column]])
		_columns[column] = points
	return monotone(_columns[column], z)


## Skin height at lateral position x: the upper (or lower) superellipse contour of station z.
static func skin_y(z: float, x: float, upper := true) -> float:
	var hw := profile(z, 1)
	var n := _station_value(z, 4 if upper else 5)
	var a := profile(z, 2) if upper else profile(z, 3)
	var u := clampf(absf(x) / hw, 0.0, 1.0)
	return a * pow(maxf(1.0 - pow(u, n), 0.0), 1.0 / n)


## Half-width of the upper skin at height y (inverse of skin_y), for parts seated on a sill.
static func skin_half_width_at(z: float, y: float) -> float:
	var n := _station_value(z, 4)
	var v := clampf(y / profile(z, 2), 0.0, 1.0)
	return profile(z, 1) * pow(maxf(1.0 - pow(v, n), 0.0), 1.0 / n)


# Superellipse ring centred on the thrust line: the upper half uses the top semi-axis/exponent, the lower half the
# bottom ones (exponent 2 = ellipse, higher = boxier). `scale` inflates it about the thrust line.
static func _super_ring(z: float, scale := 1.0) -> Array[Vector3]:
	var hw := profile(z, 1) * scale
	var top := profile(z, 2) * scale
	var bottom := -profile(z, 3) * scale
	var nt := _station_value(z, 4)
	var nb := _station_value(z, 5)
	var ring: Array[Vector3] = []
	for k in RING_POINTS:
		var a := TAU * k / RING_POINTS
		var c := cos(a)
		var s := sin(a)
		var n := nt if s >= 0.0 else nb
		var ay := top if s >= 0.0 else bottom
		ring.append(Vector3(hw * signf(c) * pow(absf(c), 2.0 / n), signf(s) * ay * pow(absf(s), 2.0 / n), z))
	return ring


# Longitudinal sample positions: every station inside [z0, z1] plus LOFT_STEP_M subdivisions, both ends included.
static func _zs(z0: float, z1: float, step := LOFT_STEP_M) -> Array[float]:
	var knots: Array[float] = [z0]
	for s in D.fuselage_stations:
		if s[0] > z0 + 1e-6 and s[0] < z1 - 1e-6: knots.append(s[0])
	knots.append(z1)
	var out: Array[float] = []
	for i in knots.size() - 1:
		var n := maxi(1, ceili((knots[i + 1] - knots[i]) / step))
		for k in n: out.append(lerpf(knots[i], knots[i + 1], float(k) / n))
	out.append(z1)
	return out


static func _fuselage(root: Node3D) -> void:
	var z0: float = D.spinner.back_z
	var z_end: float = D.fuselage_stations[-1][0]
	var band := z0 + NOSE_BAND_M
	var band_rings := []
	for z in _zs(z0, band): band_rings.append(_super_ring(z))
	_instance("cowl_band", _loft(band_rings, material(RED, 0.35, 0.2), [true, false]), root) # front cap against the spinner back
	var rings := []
	for z in _zs(band, z_end): rings.append(_super_ring(z))
	_instance("fuselage", _loft(rings, _skin(Finish.FUSELAGE), [false, true]), root)
	# Anti-glare panel: olive strip 1.2 mm above the cowl top, out to 62 % of the half-width, band to windscreen.
	var rows := []
	for z in _zs(band, D.canopy.top[0][0]):
		var n := _station_value(z, 4)
		var a0 := acos(pow(0.62, n / 2.0))
		var scale := 1.0 + 0.0012 / profile(z, 1)
		var row: Array[Vector3] = []
		for k in 13:
			var a := lerpf(a0, PI - a0, float(k) / 12.0)
			var c := cos(a)
			var s := sin(a)
			row.append(Vector3(profile(z, 1) * signf(c) * pow(absf(c), 2.0 / n), profile(z, 2) * pow(s, 2.0 / n), z) * scale)
		rows.append(row)
	_instance("anti_glare", _strip(rows, material(OLIVE, 0.8)), root)


# Exhaust stacks (V05): D.exhausts.count short pipes per side on the cowl flank between z0 and z1, at y_fraction of the
# local cowl height, protruding `length` outward and raked aft by rake_deg (photos; the drawing gives only the z range).
static func _exhausts(root: Node3D) -> void:
	var e: Dictionary = D.exhausts
	var n: int = int(e.count)
	for sign in [-1.0, 1.0]:
		for k in n:
			var z := lerpf(float(e.z0), float(e.z1), (float(k) + 0.5) / float(n))
			var y: float = profile(z, 2) * float(e.y_fraction)
			var x := skin_half_width_at(z, y) - 0.004
			var base := Vector3(sign * x, y, z)
			var rake := deg_to_rad(float(e.rake_deg))
			var tip := base + Vector3(sign * cos(rake), -0.15, sin(rake)).normalized() * float(e.length)
			var pipe := _cylinder("exhaust_%s_%d" % ["right" if sign > 0 else "left", k], float(e.radius), (tip - base).length(), DARK, root, 10)
			pipe.position = (base + tip) * 0.5
			pipe.quaternion = Quaternion(Vector3.UP, (tip - base).normalized())


# V03 scoop ring: the top edge follows the fuselage bottom contour at `top_offset` (negative = below the skin, the
# boundary-layer gutter; +4 mm = seated inside the skin), the lower part a superellipse of exponent n (2.6 at the oval
# mouth, ~5 for the duct's nearly straight sides) down to bottom_y.
static func _scoop_ring(z: float, hw: float, bottom: float, n: float, top_offset: float) -> Array[Vector3]:
	var ring: Array[Vector3] = []
	for k in SCOOP_TOP_POINTS + 1:
		var x := lerpf(-hw, hw, float(k) / SCOOP_TOP_POINTS)
		ring.append(Vector3(x, skin_y(z, x, false) + top_offset, z))
	var side_y := skin_y(z, hw, false) + top_offset
	var depth := side_y - bottom
	for k in range(1, SCOOP_ARC_POINTS):
		var a := -PI * float(k) / SCOOP_ARC_POINTS
		var c := cos(a)
		var s := sin(a)
		ring.append(Vector3(hw * signf(c) * pow(absf(c), 2.0 / n), side_y - depth * pow(absf(s), 2.0 / n), z))
	return ring


# Dark throat behind an open intake lip: the lip ring inset, narrowing into the body; drawn from inside.
static func _throat(label: String, lip: Array[Vector3], depth: float, parent: Node3D) -> void:
	var c := Vector3.ZERO
	for p in lip: c += p
	c /= lip.size()
	var near: Array[Vector3] = []
	var far: Array[Vector3] = []
	for p in lip:
		near.append(c + (p - c) * 0.96 + Vector3(0, 0, 0.003))
		far.append(c + (p - c) * 0.45 + Vector3(0, 0, depth))
	_instance(label, _loft([near, far], _throat_material(), [false, true]), parent)


# Belly scoop (V03): straight-sided duct with a boundary-layer gutter over scoop_gutter.length behind the mouth (the duct
# top sits gutter.gap below the fuselage, then blends back onto the skin), a deep dark throat, and an exit door hinged at
# the duct's rear bottom, hanging at scoop_exit.door_angle_deg.
static func _scoop(root: Node3D) -> void:
	var rows: Array = D.scoop_stations
	var gutter: Dictionary = D.scoop_gutter
	var widths := []
	var bottoms := []
	var exps := []
	for r in rows:
		widths.append([r[0], r[1]])
		bottoms.append([r[0], r[2]])
		exps.append([r[0], r[3]])
	var rings := []
	var z0: float = rows[0][0]
	var n := ceili((rows[-1][0] - z0) / 0.02)
	for k in n + 1:
		var z: float = lerpf(z0, rows[-1][0], float(k) / n)
		var blend := smoothstep(float(gutter.length), float(gutter.length) + 0.08, z - z0)
		var top_offset := lerpf(-float(gutter.gap), 0.004, blend)
		rings.append(_scoop_ring(z, monotone(widths, z), monotone(bottoms, z), monotone(exps, z), top_offset))
	_instance("scoop", _loft(rings, _skin(Finish.PLAIN), [false, true]), root) # open intake, closed exit
	_throat("scoop_throat", rings[0], 0.25, root)
	# Gutter roof: the fuselage bottom over the gutter is the skin itself; a dark splitter plate closes the gutter's
	# forward end so the slot reads as a channel, not a hole.
	var plate: Array[Vector3] = []
	var hw0: float = rows[0][1]
	for k in SCOOP_TOP_POINTS + 1:
		var x := lerpf(-hw0 * 0.98, hw0 * 0.98, float(k) / SCOOP_TOP_POINTS)
		plate.append(Vector3(x, skin_y(z0 + 0.03, x, false) - 0.001, z0 + 0.03))
	var plate_low: Array[Vector3] = []
	for pnt in plate: plate_low.append(pnt + Vector3(0, -float(gutter.gap) + 0.002, 0))
	_instance("scoop_gutter_plate", _strip([plate, plate_low], _throat_material()), root)
	# Exit door.
	var ex: Dictionary = D.scoop_exit
	var z_exit: float = rows[-1][0]
	var z_hinge: float = z_exit - float(ex.door_length)
	var hw_door: float = monotone(widths, z_hinge) * 0.8
	var y_hinge: float = monotone(bottoms, z_hinge) - 0.002
	var ang := deg_to_rad(float(ex.door_angle_deg))
	var free := Vector3(0, y_hinge - float(ex.door_length) * sin(ang), z_hinge + float(ex.door_length) * cos(ang))
	var door := []
	for end in [Vector3(0, y_hinge, z_hinge), free]:
		var ring: Array[Vector3] = []
		for corner in [[1.0, -0.0015], [1.0, 0.0015], [-1.0, 0.0015], [-1.0, -0.0015]]:
			ring.append(end + Vector3(corner[0] * hw_door, corner[1], 0))
		door.append(ring)
	_instance("scoop_exit_door", _loft(door, _skin(Finish.PLAIN)), root)


# Height profile of the carburettor intake along its length (0..1): a short rise, a plateau and a long fade into the
# cowl. apply_metrology.py lowers the cowl stations by height x this profile, so intake + cowl = the measured top line.
static func _intake_profile(u: float) -> float:
	if u <= 0.0 or u >= 1.0: return 0.0
	return smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.35, 1.0, u))


# Carburettor intake on the cowl top (V03): half-superellipse loft seated 3 mm into the skin, open at the front with a
# raised lip over the first 8 % of its length, fading into the cowl toward z1.
static func _carb_intake(root: Node3D) -> void:
	var c: Dictionary = D.carb_intake
	var rings := []
	for k in 17:
		var u := float(k) / 16.0
		var z: float = lerpf(c.z0, c.z1, u)
		var h: float = c.height * _intake_profile(u) + float(c.lip) * (1.0 - smoothstep(0.0, 0.08, u))
		var hw: float = c.half_width * (1.0 - 0.3 * u)
		var ring: Array[Vector3] = []
		for j in 13:
			var a := PI * j / 12.0
			var x: float = hw * signf(cos(a)) * pow(absf(cos(a)), 2.0 / 2.4)
			ring.append(Vector3(x, skin_y(z, x) - 0.003 + h * pow(sin(a), 2.0 / 2.4), z))
		for j in range(1, 12):
			var x := lerpf(-hw, hw, j / 12.0)
			ring.append(Vector3(x, skin_y(z, x) - 0.003, z))
		rings.append(ring)
	_instance("carb_intake", _loft(rings, material(OLIVE, 0.8), [false, true]), root)
	_throat("carb_throat", rings[0], 0.06, root)


# Canopy section: a semi-ellipse whose base follows the skin down to the sill on each side.
static func _canopy_ring(z: float, top: float, half: float, grow := 0.0) -> Array[Vector3]:
	var ring: Array[Vector3] = []
	for k in 25:
		var a := PI * k / 24.0
		var x := (half + grow) * cos(a)
		var base := skin_y(z, minf(absf(x), half)) - 0.002
		ring.append(Vector3(x, base + maxf(top + grow - base, 0.0) * sin(a), z))
	return ring


static func _canopy_half(z: float, z0: float, z1: float) -> float:
	var c: Dictionary = D.canopy
	var u := absf((z - (z0 + z1) / 2.0) / ((z1 - z0) / 2.0))
	var plan: float = c.halfwidth_fraction * profile(z, 1) * pow(maxf(1.0 - pow(u, 4.0), 0.0), 0.25)
	return minf(plan, skin_half_width_at(z, profile(z, 2) - SILL_DEPTH_M))


# Windscreen cross-section (V04): three flat panels, a centre panel of centre_fraction of the width and two raked side
# panels down to the sill, so the glass reads as framed flat glass, not a bubble. Same point count as _canopy_ring.
static func _windscreen_ring(z: float, top: float, half: float, grow := 0.0) -> Array[Vector3]:
	var ws: Dictionary = D.canopy.windscreen
	var base: float = skin_y(z, half, true) - SILL_DEPTH_M
	var cf: float = float(ws.centre_fraction)
	var corners := [Vector3(-half - grow, base, z), Vector3(-half * cf - grow, top + grow, z), Vector3(half * cf + grow, top + grow, z), Vector3(half + grow, base, z)]
	var ring: Array[Vector3] = []
	var count := 25
	for k in count:
		var u := float(k) / float(count - 1) * 3.0 # 0..3 across the three panels
		var i := mini(int(floor(u)), 2)
		ring.append(corners[i].lerp(corners[i + 1], u - i))
	return ring


static func _canopy(root: Node3D) -> void:
	var c: Dictionary = D.canopy
	var z0: float = c.top[0][0]
	var z1: float = c.top[-1][0]
	var zf: float = c.frame_z
	# Windscreen: faceted prism from the sill to the frame (V04); its top follows the measured canopy line.
	var ws_rings := []
	for k in 9:
		var z := lerpf(z0, zf, float(k) / 8.0)
		ws_rings.append(_windscreen_ring(z, monotone(c.top, z), _canopy_half(z, z0, z1)))
	_instance("windscreen", _loft(ws_rings, _glass(), [false, false]), root)
	# Windscreen frames: dark strips 1.5 mm proud along the two panel joints and the front edge.
	var fw: float = c.windscreen.frame_width
	for joint in [1, 2]:
		var strip := []
		for k in 9:
			var z := lerpf(z0, zf, float(k) / 8.0)
			var ring := _windscreen_ring(z, monotone(c.top, z), _canopy_half(z, z0, z1), 0.0015)
			var idx: int = 8 * int(joint) # ring point on the joint (25 points over 3 panels)
			strip.append([ring[maxi(idx - 2, 0)], ring[idx], ring[mini(idx + 2, 24)]])
		_instance("windscreen_frame_%d" % joint, _strip(strip, material(DARK, 0.6)), root)
	var front := []
	for dz in [0.0, fw]:
		front.append(_windscreen_ring(z0 + dz, monotone(c.top, z0 + dz), _canopy_half(z0 + dz, z0, z1), 0.0015))
	_instance("windscreen_frame_front", _loft(front, material(DARK, 0.6), [false, false]), root)
	# Sliding hood: smooth bubble from the frame to the turtle deck.
	var zs: Array[float] = []
	for k in 33: zs.append(lerpf(zf, z1, float(k) / 32.0))
	var rings := []
	for z in zs: rings.append(_canopy_ring(z, monotone(c.top, z), _canopy_half(z, z0, z1)))
	_instance("canopy", _loft(rings, _glass(), [false, false]), root)
	# Hood frame at the windscreen joint: a dark band 1.5 mm proud of the glass.
	var frame := []
	for dz in [-fw / 2.0, fw / 2.0]:
		var z: float = zf + dz
		frame.append(_canopy_ring(z, monotone(c.top, z), _canopy_half(z, z0, z1), 0.0015))
	_instance("canopy_frame", _loft(frame, material(DARK, 0.6), [false, false]), root)
	# Hood rails on both sills (V04): small boxes along the deck from the frame to the hood's end.
	var rail: Dictionary = c.rail
	for sgn in [-1.0, 1.0]:
		var rows := []
		for z in [zf, z1 - 0.06]:
			var x: float = sgn * (_canopy_half(z, z0, z1) + 0.002)
			var y: float = skin_y(z, x, true)
			var ring: Array[Vector3] = []
			for corner in [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]:
				ring.append(Vector3(x + sgn * corner[0] * float(rail.width), y + corner[1] * float(rail.height), z))
			rows.append(ring)
		_instance("hood_rail_" + ("right" if sgn > 0 else "left"), _loft(rows, material(METAL, 0.4, 0.6)), root)
	# Cockpit tub: dark skin over the deck inside the canopy, so the glass shows a cockpit and not bare metal.
	var tub := []
	var tub_z0 := z0 + 0.012
	var tub_z1 := z1 - 0.05
	for k in 17:
		var z := lerpf(tub_z0, tub_z1, float(k) / 16.0)
		var xs := _canopy_half(z, z0, z1) * 0.92
		var row: Array[Vector3] = []
		for j in 13:
			var x := lerpf(-xs, xs, float(j) / 12.0)
			row.append(Vector3(x, skin_y(z, x) + 0.0015, z))
		tub.append(row)
	_instance("cockpit_tub", _strip(tub, material(COCKPIT, 0.9)), root)
	# Gunsight (V04): a small dark box on the coaming just behind the windscreen frame.
	var gs: Dictionary = c.gunsight
	var sight := BoxMesh.new()
	sight.size = Vector3(float(gs.width), float(gs.height), float(gs.length))
	sight.material = material(DARK, 0.5)
	_instance("gunsight", sight, root, Vector3(0, skin_y(zf + 0.02, 0.0) + float(gs.height) / 2.0, zf + 0.02 + float(gs.length) / 2.0))
	# Armour plate behind the pilot's head, from the deck to just under the hood.
	var plate_z: float = D.pilot.head_back[0] + 0.03
	var deck := profile(plate_z, 2)
	var plate_top: float = monotone(c.top, plate_z) - 0.012
	var plate := BoxMesh.new()
	plate.size = Vector3(0.075, plate_top - deck + 0.02, 0.008)
	plate.material = material(OLIVE, 0.8)
	_instance("armour_plate", plate, root, Vector3(0, (plate_top + deck - 0.02) / 2.0, plate_z))


# Closed ellipsoid (or its part above y_cut) as a latitude-longitude loft, node at the centre.
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


# Stylised pilot from the side-view points: head, leather helmet over the ears, goggles, neck and torso.
static func _pilot(root: Node3D) -> void:
	var p: Dictionary = D.pilot
	var node := Node3D.new()
	node.name = "pilot"
	root.add_child(node)
	var head_z: float = (p.nose_front[0] + p.head_back[0]) / 2.0
	var head_y: float = (p.chin[1] + p.cap_brim_front[1]) / 2.0 + 0.004
	var head_radii := Vector3(p.head_half_width, (p.cap_brim_front[1] - p.chin[1]) / 2.0 + 0.006, (p.head_back[0] - p.nose_front[0]) / 2.0)
	_ellipsoid("pilot_head", Vector3(0, head_y, head_z), head_radii, SKIN, node)
	var helmet_center := Vector3(0, head_y - 0.001, head_z)
	_ellipsoid("pilot_helmet", helmet_center, Vector3(head_radii.x + 0.0025, p.cap_top[1] - helmet_center.y, head_radii.z + 0.0025), HELMET, node, head_y - 0.012)
	_ellipsoid("pilot_goggles", Vector3(0, head_y + 0.006, p.nose_front[0] + 0.012), Vector3(head_radii.x + 0.001, 0.007, 0.012), DARK, node)
	var shoulder_y: float = (p.shoulder_front[1] + p.shoulder_back[1]) / 2.0
	var torso_z: float = (p.shoulder_front[0] + p.shoulder_back[0]) / 2.0
	_ellipsoid("pilot_neck", Vector3(0, (p.chin[1] + shoulder_y) / 2.0, head_z + 0.006), Vector3(0.011, 0.014, 0.012), SKIN, node)
	_ellipsoid("pilot_torso", Vector3(0, shoulder_y - 0.02, torso_z), Vector3(p.shoulder_half_width, 0.03, (p.shoulder_back[0] - p.shoulder_front[0]) / 2.0), JACKET, node)


# Half-thickness/chord of the section table normalised to t/c = 1 (peak 0.5), linear between samples.
static func _half_thickness(x: float) -> float:
	return _table(D.wing.section, x)


# Closed section ring in an abstract (s, y, z) frame: s spanwise, y thickness, z chordwise (LE at le, TE at le + c).
# x0, x1 chord fractions; bevel_nose puts the nose on the camber line at x0 and starts the skin 45 deg behind it so a
# deflecting surface turns about its own nose. shrink scales the thickness (tip rounding). `map` relabels axes.
static func _foil_ring(s: float, le: float, c: float, t_max: float, camber: float, x0: float, x1: float, bevel_nose := false, shrink := 1.0, map := Basis.IDENTITY) -> Array[Vector3]:
	var tr := shrink * t_max / c
	var start := x0
	if bevel_nose: start = x0 + _half_thickness(x0) * tr
	var upper: Array[Vector3] = []
	var lower: Array[Vector3] = []
	for k in CHORD_SAMPLES + 1:
		var u := float(k) / CHORD_SAMPLES
		var xc := lerpf(start, x1, 0.5 - 0.5 * cos(PI * u)) if start <= 0.0 else lerpf(start, x1, u)
		var yc := 4.0 * camber * xc * (1.0 - xc) * c
		var h := _half_thickness(xc) * tr * c
		upper.append(map * Vector3(s, yc + h, le + xc * c))
		lower.append(map * Vector3(s, yc - h, le + xc * c))
	var ring: Array[Vector3] = []
	if bevel_nose: ring.append(map * Vector3(s, 4.0 * camber * x0 * (1.0 - x0) * c, le + x0 * c))
	for p in upper: ring.append(p)
	for k in range(lower.size() - 1, -1, -1):
		if k == 0 and x0 <= 0.0: continue # shared leading-edge point
		ring.append(lower[k])
	return ring


# Elliptical fade of the thickness over the last `radius` of span.
static func _round_factor(distance_to_end: float, radius: float) -> float:
	if distance_to_end >= radius: return 1.0
	var u := 1.0 - distance_to_end / radius
	return sqrt(maxf(1.0 - u * u, 0.0025))


static func _chord(span: float) -> float:
	var w: Dictionary = D.wing
	return lerpf(w.root_chord, w.tip_chord, span / (w.span / 2.0))


# Straight (trapezoid) leading edge; the measured root extension is added separately (V02).
static func _le_z(span: float) -> float:
	var w: Dictionary = D.wing
	return lerpf(w.le_z_root, w.le_z_tip, span / (w.span / 2.0))


# V02: forward extension of the leading edge at the root (the D's "kink"), measured in the plan view; zero outboard.
static func _root_ext(span: float) -> float:
	return monotone(D.wing.root_extension, span)


# V02: planform rounding of the tip over the last tip_round_plan of span, about mid chord: returns [le_shift, chord_factor].
static func _tip_plan(span: float) -> Array:
	var r: float = D.wing.tip_round_plan
	var d: float = D.wing.span / 2.0 - span
	if d >= r: return [0.0, 1.0]
	var u := 1.0 - d / r
	var f := sqrt(maxf(1.0 - u * u, 0.0016))
	return [0.5 * (1.0 - f), f]


static func _thickness_ratio(span: float) -> float:
	var w: Dictionary = D.wing
	return lerpf(w.root_thickness_ratio, w.tip_thickness_ratio, span / (w.span / 2.0))


# Wing stations are projected (plan-view) spans; the dihedral frame's X runs along the tilted panel, so the panel
# coordinate is span / cos(dihedral) and the projected span of the model stays exactly D.wing.span.
static func _panel_x(x_projected: float) -> float:
	return x_projected / cos(deg_to_rad(D.wing.dihedral_deg))


# Section ring at the signed projected station x, in the dihedral frame (chord plane at y = 0, LE on the frame's z).
# x0, x1 are fractions of the BASE chord (straight LE to TE), so hinge lines never move. with_ext: the ring's leading
# edge moves forward by the root extension (fixed panels only; its thickness stays that of the base chord). The tip
# rounding shrinks the planform about mid chord.
static func _wing_ring(x: float, x0: float, x1: float, bevel_nose := false, with_ext := false) -> Array[Vector3]:
	var span := absf(x)
	var c_b := _chord(span)
	var le_b: float = _le_z(span) - D.wing.le_z_root
	var tip := _tip_plan(span)
	var e: float = _root_ext(span) if with_ext else 0.0
	var le: float = le_b + float(tip[0]) * c_b - e
	var c: float = c_b * float(tip[1]) + e
	# convert base-chord fractions to fractions of the drawn chord
	var f0: float = (le_b + x0 * c_b - le) / c if x0 > 0.0 else 0.0
	var f1: float = (le_b + x1 * c_b - le) / c if x1 < 1.0 else 1.0
	return _foil_ring(_panel_x(x), le, c, c_b * float(tip[1]) * _thickness_ratio(span), D.wing.camber_ratio, f0, f1, bevel_nose,
		_round_factor(D.wing.span / 2.0 - span, TIP_ROUND_M))


# Wing panel between spanwise stations, as lofts per material group ([[material, [stations...]], ...], consecutive
# groups share their end station) in one mesh. part: full | fixed (LE to hinge - gap) | moving (bevel nose at hinge + gap).
static func _wing_panel(label: String, groups: Array, part: String, parent: Node3D, sign: float, to_local := Transform3D.IDENTITY) -> MeshInstance3D:
	var g: float = D.wing.hinge_gap / 2.0
	var h: float = 1.0 - float(D.wing.aileron_chord_fraction) # flap_chord_fraction is the same 0.21
	var mesh: ArrayMesh = null
	for gi in groups.size():
		var rings := []
		for station in groups[gi][1]:
			var c := _chord(station)
			var ring: Array[Vector3]
			match part:
				"full": ring = _wing_ring(sign * station, 0.0, 1.0, false, true)
				"fixed": ring = _wing_ring(sign * station, 0.0, h - g / c, false, true)
				"moving": ring = _wing_ring(sign * station, h + g / c, 1.0, true)
			var local: Array[Vector3] = []
			for p in ring: local.append(to_local * p)
			rings.append(local)
		mesh = _loft(rings, groups[gi][0], [gi == 0, gi == groups.size() - 1], mesh)
	return _instance(label, mesh, parent)


# Point on the wing skin at projected station x and chord fraction xc, in the dihedral frame.
static func _wing_skin_point(x: float, xc: float, upper: bool, with_ext := false) -> Vector3:
	var span := absf(x)
	var c_b := _chord(span)
	var e: float = _root_ext(span) if with_ext else 0.0
	var le: float = _le_z(span) - D.wing.le_z_root - e
	var c := c_b + e
	var f: float = (e + xc * c_b) / c # base-chord fraction -> drawn-chord fraction
	var h := _half_thickness(f) * _thickness_ratio(span) * c_b
	var yc: float = 4.0 * D.wing.camber_ratio * f * (1.0 - f) * c
	return Vector3(_panel_x(x), yc + (h if upper else -h), le + f * c)


# Aileron hinge point at a projected station: constant chord fraction, on the camber line, in the dihedral frame.
static func _hinge_point(x: float) -> Vector3:
	var span := absf(x)
	var c := _chord(span)
	var h: float = 1.0 - float(D.wing.aileron_chord_fraction)
	return Vector3(_panel_x(x), 4.0 * D.wing.camber_ratio * h * (1.0 - h) * c, _le_z(span) - D.wing.le_z_root + h * c)


static func _hinge(label: String, parent: Node3D, hinges: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label + "_hinge"
	parent.add_child(pivot)
	hinges[label] = pivot
	return pivot


# Returns the root-relative transforms of the two dihedral frames (for parts attached to the wing).
static func _wings(root: Node3D, hinges: Dictionary) -> Dictionary:
	var w: Dictionary = D.wing
	var half: float = w.span / 2.0
	var wing := Node3D.new()
	wing.name = "wing"
	wing.position = Vector3(0, w.chord_plane_y, w.le_z_root)
	wing.rotation.x = deg_to_rad(w.incidence_deg) # positive: trailing edge down = nose up
	root.add_child(wing)
	var alu := _skin(Finish.WING) # fixed skins: ribs and spars
	var plain := _skin(Finish.PLAIN) # moving surfaces: same metal, no lines
	var yellow := material(YELLOW, 0.4)
	var band := half - 0.1 # yellow tips: last 0.1 m of span
	var frames := {}
	for sign in [-1.0, 1.0]:
		var suffix := "right" if sign > 0 else "left"
		var frame := Node3D.new()
		frame.name = "wing_frame_" + suffix
		frame.rotation.z = sign * deg_to_rad(w.dihedral_deg)
		wing.add_child(frame)
		frames[suffix] = wing.transform * frame.transform
		_wing_panel("wing_%s_root" % suffix, [[alu, [0.0, w.flap_inner]]], "full", frame, sign)
		# The fixed panel ahead of the flap carries the root leading-edge extension: its stations follow the measured
		# extension table so the loft reproduces the measured curve instead of a straight wedge to the flap's outer end.
		var ahead_stations: Array = [w.flap_inner]
		for row in w.root_extension:
			if row[0] > w.flap_inner + 0.005 and row[0] < w.flap_outer - 0.02: ahead_stations.append(row[0])
		ahead_stations.append(w.flap_outer)
		_wing_panel("wing_%s_ahead_of_flap" % suffix, [[alu, ahead_stations]], "fixed", frame, sign)
		# Flap: fixed in the retracted position (no flap channel yet), drawn as its own surface with the hinge gap.
		_wing_panel("flap_" + suffix, [[plain, [w.flap_inner + END_GAP_M, w.flap_outer - END_GAP_M]]], "moving", frame, sign)
		_wing_panel("wing_%s_between" % suffix, [[alu, [w.flap_outer, w.aileron_inner]]], "full", frame, sign)
		_wing_panel("wing_%s_ahead_of_aileron" % suffix, [[alu, [w.aileron_inner, band]], [yellow, [band, w.aileron_outer]]], "fixed", frame, sign)
		var tip_stations: Array = [w.aileron_outer]
		var r_plan: float = w.tip_round_plan
		for k in range(0, 9): tip_stations.append(half - r_plan * (1.0 - float(k) / 9.0) ** 1.6 - 0.001 * (8 - k))
		for s in [half - 0.012, half - 0.006, half - 0.002, half]: tip_stations.append(s)
		tip_stations.sort()
		_wing_panel("wing_%s_tip" % suffix, [[yellow, tip_stations]], "full", frame, sign)
		_root_fillet(root, suffix, sign, wing.transform * frame.transform)
		# Static frame on the swept hinge line (constant chord fraction): local +X along the hinge toward +X.
		var inner := _hinge_point(sign * w.aileron_inner)
		var outer := _hinge_point(sign * w.aileron_outer)
		var along: Vector3 = (outer - inner) * sign
		var aileron_frame := Node3D.new()
		aileron_frame.name = "aileron_frame_" + suffix
		aileron_frame.position = (inner + outer) / 2.0
		aileron_frame.rotation.y = atan2(-along.z, along.x)
		frame.add_child(aileron_frame)
		var pivot := _hinge("aileron_" + suffix, aileron_frame, hinges)
		_wing_panel("aileron_" + suffix, [[plain, [w.aileron_inner + END_GAP_M, band]], [yellow, [band, w.aileron_outer - END_GAP_M]]], "moving", pivot, sign,
			aileron_frame.transform.affine_inverse())
	return frames


# V02: wing-root fillet (estimated from photos): a concave quarter-round strip between the wing's upper surface just
# outboard of the fuselage side and the fuselage skin, its radius growing from the leading edge to the trailing edge;
# behind the TE it keeps fairing up the fuselage side while the radius shrinks to zero (root_fillet.length_aft, te_rise).
static func _root_fillet(root: Node3D, suffix: String, sign: float, to_root: Transform3D) -> void:
	var w: Dictionary = D.wing
	var fl: Dictionary = w.root_fillet
	var rows := []
	var x_side: float = profile(0.3 * w.root_chord, 1) # fuselage half-width near the wing: the fillet's foot station
	var le_root: float = _le_z(x_side) - w.le_z_root - _root_ext(x_side)
	var chord_ext: float = _chord(x_side) + _root_ext(x_side)
	for k in 19:
		var u := float(k) / 18.0
		var r: float = lerpf(float(fl.radius_le), float(fl.radius_te), u)
		var xc_drawn := lerpf(0.02, 0.985, u)
		var xc_base: float = (xc_drawn * chord_ext - _root_ext(x_side)) / _chord(x_side)
		var p_w: Vector3 = to_root * _wing_skin_point(sign * (x_side + 0.004), clampf(xc_base, 0.0, 1.0), true, true)
		rows.append(_fillet_row(p_w, r, sign))
	var te_point: Vector3 = to_root * _wing_skin_point(sign * (x_side + 0.004), 1.0, true, false)
	for k in range(1, 9):
		var u := float(k) / 8.0
		var r: float = float(fl.radius_te) * (1.0 - u)
		var p := te_point + Vector3(0, float(fl.te_rise) * u * u, float(fl.length_aft) * u)
		rows.append(_fillet_row(p, maxf(r, 0.003), sign))
	_instance("root_fillet_" + suffix, _strip(rows, _skin(Finish.PLAIN)), root)


# One fillet row: a quarter arc of 7 points from the wing surface point (tangent horizontal) to the fuselage skin
# (tangent vertical), concave toward the corner; the foot sits on the skin at height y + r.
static func _fillet_row(p_w: Vector3, r: float, sign: float) -> Array[Vector3]:
	var x_f: float = skin_half_width_at(p_w.z, p_w.y + r) * sign
	var center := Vector3(x_f + sign * r, p_w.y + r, p_w.z)
	var row: Array[Vector3] = []
	for k in 7:
		var a := lerpf(-PI / 2.0, -PI, float(k) / 6.0) # -90 deg: on the wing surface; -180 deg: on the fuselage wall
		row.append(center + Vector3(sign * r * cos(a), r * sin(a), 0))
	return row


# Horizontal tail section at signed span s, in the tail frame (origin on the elevator hinge). Symmetric section
# with the wing's thickness distribution; thickness scales with the local chord.
# V01: the tail is built from outlines measured on the AN 01-60-3 side and plan views (geometry.json → tail.upper_outline,
# lower_outline, stab_planform). The fin leading edge, cap and rudder trailing edge are the inverse of the upper contour.

# z of the measured upper tail contour at height y: `rising` = dorsal fillet and fin LE (before the contour's maximum),
# otherwise the cap and the raked rudder TE (after it). Bisection on z over a monotone interpolation of the contour.
static func _upper_z_at(y: float, rising: bool) -> float:
	var pts: Array = D.tail.upper_outline
	var i_max := 0
	for i in pts.size():
		if pts[i][1] > pts[i_max][1]: i_max = i
	var lo: float = pts[0][0] if rising else pts[i_max][0]
	var hi: float = pts[i_max][0] if rising else pts[-1][0]
	for k in 40:
		var mid := 0.5 * (lo + hi)
		var ym := monotone(pts, mid)
		if (ym < y) == rising: lo = mid
		else: hi = mid
	return 0.5 * (lo + hi)


static func _fin_top_y() -> float:
	return float(D.tail.fin_top_y)


# Rudder trailing edge z at height y: the measured raked TE and cap above the contour's last point, a straight line down
# to rudder_te_bottom below it.
static func _rudder_te(y: float) -> float:
	var t: Dictionary = D.tail
	var pts: Array = t.upper_outline
	var y_low: float = pts[-1][1]
	if y >= y_low: return _upper_z_at(y, false)
	var z_low: float = pts[-1][0]
	var b: Array = t.rudder_te_bottom
	if y >= float(b[1]): return lerpf(float(b[0]), z_low, clampf((y - float(b[1])) / (y_low - float(b[1])), 0.0, 1.0))
	# Below the trailing-edge bottom corner the rudder's base is bevelled back to the hinge along the measured tail-cone
	# bottom (the tail light sits in this corner on the real airplane).
	var y_base: float = _tail_lower_y(t.rudder_hinge_z)
	return lerpf(t.rudder_hinge_z + 0.03, float(b[0]), clampf((y - y_base) / (float(b[1]) - y_base), 0.0, 1.0))


# Rudder bottom edge (model y) at z: the measured lower tail contour (tail cone and rudder base).
static func _tail_lower_y(z: float) -> float:
	return monotone(D.tail.lower_outline, z)


# Vertical tail section at height y in the fin frame (origin on the rudder hinge line). The fin's section continues into
# the rudder; near the deck the fin widens quadratically into the dorsal fairing (up to 0.7 of the local half-width).
# Axes relabelled so thickness is X and height is Y.
static func _fin_ring(y: float, part: String) -> Array[Vector3]:
	var t: Dictionary = D.tail
	var g: float = t.hinge_gap / 2.0
	var rz: float = t.rudder_hinge_z
	var swap := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
	var z_le: float = _upper_z_at(y, true)
	var le: float = z_le - rz
	var y_deck: float = profile(z_le, 2) - 0.004
	var top := _fin_top_y()
	var blend := clampf(1.0 - (y - y_deck) / (0.12 * (top - y_deck)), 0.0, 1.0)
	var widen: float = 1.0 + (minf(0.7 * profile(z_le, 1), 4.0 * t.fin_thickness) / t.fin_thickness - 1.0) * blend * blend
	var shrink := _round_factor(top - y, 0.02)
	var c_fixed := -g - le
	var c_ref: float = rz - g - _upper_z_at(y_deck + 0.3 * (top - y_deck), true) # thickness reference chord: fin at 30 % height
	var thickness: float = t.fin_thickness * widen * minf(1.0, c_fixed / c_ref)
	if part == "fixed":
		return _foil_ring(y, le, c_fixed, thickness, 0.0, 0.0, 1.0, false, shrink, swap)
	var c := _rudder_te(y) - rz - le
	return _foil_ring(y, le, c, t.fin_thickness * minf(1.0, c_fixed / c_ref), 0.0, (g - le) / c, 1.0, true, shrink, swap)


# Stab planform from the measured plan view (clamped outside the samples), rounded in plan over the last
# stab_tip_round of span about mid chord. Returns [le_z, te_z] (model z).
static func _stab_plan(span: float) -> Array:
	var t: Dictionary = D.tail
	var pf: Dictionary = t.stab_planform
	var le: float = monotone(pf.le, span)
	var te: float = monotone(pf.te, span)
	var d: float = t.stab_half_span - span
	if d < float(t.stab_tip_round):
		var u := 1.0 - d / float(t.stab_tip_round)
		var f := sqrt(maxf(1.0 - u * u, 0.0016))
		var mid := 0.5 * (le + te)
		le = mid - 0.5 * (te - le) * f
		te = mid + 0.5 * (te - le) * f
	return [le, te]


# Elevator hinge fraction along the span: the manual's fraction, except the tip horn balance where the elevator's
# leading edge moves forward to horn.chord_fraction (the fixed stab is cut back accordingly).
static func _elevator_hinge_fraction(span: float, moving := false) -> float:
	var t: Dictionary = D.tail
	var horn: Dictionary = t.elevator_horn
	# The horn's inboard face sits HORN_CLEARANCE_M outboard of the stab's cut, so the part of the elevator ahead of the
	# hinge never shares a span station with fixed stab ahead of the hinge (a straight step, as on the real airplane).
	var step: float = float(horn.span_from_fraction) * t.stab_half_span + (HORN_CLEARANCE_M if moving else 0.0)
	return float(horn.chord_fraction) if span > step else float(t.elevator_hinge_fraction)


# Horizontal tail section at spanwise s (signed) in the tail frame (origin on the elevator hinge line at hz).
static func _stab_ring(s: float, hz: float, part: String) -> Array[Vector3]:
	var t: Dictionary = D.tail
	var g: float = t.hinge_gap / 2.0
	var plan := _stab_plan(absf(s))
	var le: float = plan[0] - hz
	var c: float = plan[1] - plan[0]
	var thickness: float = t.stab_thickness * c / t.stab_root_chord
	var shrink := _round_factor(t.stab_half_span - absf(s), 0.02)
	var hinge_z: float = plan[0] + _elevator_hinge_fraction(absf(s), part != "fixed") * c - hz
	if part == "fixed":
		return _foil_ring(s, le, c, thickness, 0.0, 0.0, (hinge_z - g - le) / c, false, shrink)
	return _foil_ring(s, le, c, thickness, 0.0, (hinge_z + g - le) / c, 1.0, true, shrink)


static func _tail(root: Node3D, hinges: Dictionary) -> void:
	var t: Dictionary = D.tail
	var hs: float = t.stab_half_span
	var alu := _skin(Finish.PLAIN) # elevators
	# Elevator hinge: straight, parallel to X, at the mean of the measured planform's hinge z over the plain (non-horn)
	# span (the measured hinge line sweeps < 0.3 deg); the horn balance rotates about the same axis.
	var f: float = t.elevator_hinge_fraction
	var p0 := _stab_plan(0.0)
	var p1 := _stab_plan(hs * float(t.elevator_horn.span_from_fraction))
	var hz: float = ((p0[0] + f * (p0[1] - p0[0])) + (p1[0] + f * (p1[1] - p1[0]))) / 2.0
	var frame := Node3D.new()
	frame.name = "tail_frame"
	frame.position = Vector3(0, t.stab_y, hz)
	frame.rotation.x = deg_to_rad(t.stab_incidence_deg)
	root.add_child(frame)
	var horn_s: float = hs * float(t.elevator_horn.span_from_fraction)
	var stations: Array[float] = []
	# The elevator's end station (hs - END_GAP_M) is also a stab station, so both follow the same straight segments of the
	# rounded planform there and the hinge gap stays exact (the rounding is curved between stations).
	for s in [0.0, 0.3 * hs, 0.6 * hs, horn_s - STEP_M, horn_s + STEP_M, hs - 0.09, hs - 0.06, hs - 0.035, hs - 0.018, hs - 0.008, hs - 0.004, hs - END_GAP_M, hs]:
		stations.append(s)
	stations.sort() # the horn cut (86 % of the semi-span) lies among the tip stations: a loft must never fold back
	var rings := []
	for i in range(stations.size() - 1, 0, -1): rings.append(_stab_ring(-stations[i], hz, "fixed"))
	for s in stations: rings.append(_stab_ring(s, hz, "fixed"))
	_instance("stab", _loft(rings, _skin(Finish.TAIL_H)), frame)
	var elevator := _hinge("elevator", frame, hinges)
	for sign in [-1.0, 1.0]:
		var el := []
		var inner: float = t.fin_thickness / 2.0 + 0.006 # clears the rudder that passes down between the elevators
		var horn_e: float = horn_s + HORN_CLEARANCE_M
		var el_stations: Array[float] = []
		for s in [inner, 0.3 * hs, 0.6 * hs, horn_e - STEP_M, horn_e + STEP_M, hs - 0.09, hs - 0.06, hs - 0.035, hs - 0.018, hs - 0.008, hs - END_GAP_M]:
			el_stations.append(s)
		el_stations.sort()
		for s in el_stations:
			el.append(_stab_ring(sign * s, hz, "moving"))
		_instance("elevator_" + ("right" if sign > 0 else "left"), _loft(el, alu), elevator)
	# Fin with the dorsal fairing, and the rudder, in a frame on the rudder hinge line. Ring heights: dense near the deck
	# (fairing) and near the cap.
	var fin_frame := Node3D.new()
	fin_frame.name = "fin_frame"
	fin_frame.position = Vector3(0, 0, t.rudder_hinge_z)
	root.add_child(fin_frame)
	var top := _fin_top_y()
	var y_deck: float = profile(float(t.upper_outline[0][0]), 2) - 0.006
	var heights: Array[float] = [y_deck]
	for k in range(1, 7): heights.append(lerpf(y_deck, y_deck + 0.12 * (top - y_deck), float(k) / 6.0))
	for k in range(1, 9): heights.append(lerpf(y_deck + 0.12 * (top - y_deck), top - 0.03, float(k) / 8.0))
	for y in [top - 0.018, top - 0.01, top - 0.005, top - 0.002]: heights.append(y)
	var fin := []
	for y in heights: fin.append(_fin_ring(y, "fixed"))
	_instance("fin", _loft(fin, _skin(Finish.TAIL_V)), fin_frame)
	var rudder := _hinge("rudder", fin_frame, hinges)
	var rud := []
	var y_base: float = _tail_lower_y(t.rudder_hinge_z) + 0.003
	rud.append(_fin_ring(y_base, "moving"))
	rud.append(_fin_ring(float(t.rudder_te_bottom[1]), "moving"))
	for y in heights:
		if y > float(t.rudder_te_bottom[1]) + 0.01: rud.append(_fin_ring(y, "moving"))
	_instance("rudder", _loft(rud, material(YELLOW, 0.4)), rudder)


static func _cylinder(label: String, radius: float, length: float, color: Color, parent: Node3D, segments := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material(color, 0.6 if color == TIRE else 0.35, 0.6 if color in [METAL, HUB] else 0.0)
	return _instance(label, mesh, parent)


static func _strut(label: String, a: Vector3, b: Vector3, radius: float, parent: Node3D) -> void:
	var rod := _cylinder(label, radius, (b - a).length(), METAL, parent, 10)
	rod.position = (a + b) * 0.5
	rod.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


# Wheel pivot (rotation.x spins it): dark tyre, a dished rim, hub_spokes spokes and a cap (V06).
static func _wheel(label: String, diameter: float, width: float, center: Vector3, parent: Node3D, spokes := 0) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label
	pivot.position = center
	parent.add_child(pivot)
	var rim_r := diameter * 0.27
	if spokes == 0:
		var tire := _cylinder(label + "_tire", diameter / 2.0, width, TIRE, pivot, 24)
		tire.rotation.z = PI / 2.0
		var hub := _cylinder(label + "_hub", rim_r, width + 0.004, HUB, pivot, 16)
		hub.rotation.z = PI / 2.0
		return pivot
	# Spoked wheel: the tyre is a tube (open centre) so the dished hub, spokes and caps show in the recess.
	var profile_pts := [[rim_r, -0.5], [diameter / 2.0 - 0.012, -0.5], [diameter / 2.0, -0.3], [diameter / 2.0, 0.3], [diameter / 2.0 - 0.012, 0.5], [rim_r, 0.5]]
	var tyre_rings := []
	for k in 25:
		var a := TAU * float(k) / 24.0
		var radial := Vector3(0, cos(a), sin(a))
		var ring: Array[Vector3] = []
		for pt in profile_pts:
			ring.append(radial * float(pt[0]) + Vector3(float(pt[1]) * width, 0, 0))
		tyre_rings.append(ring)
	_instance(label + "_tire", _loft(tyre_rings, material(TIRE, 0.6), [false, false]), pivot)
	var hub := _cylinder(label + "_hub", rim_r + 0.001, width * 0.55, HUB, pivot, 16)
	hub.rotation.z = PI / 2.0
	if spokes > 0:
		for side in [-1.0, 1.0]:
			var face_x: float = float(side) * (width * 0.55 / 2.0)
			var cap := _cylinder(label + "_cap_" + ("r" if side > 0 else "l"), rim_r * 0.3, 0.006, METAL, pivot, 12)
			cap.rotation.z = PI / 2.0
			cap.position.x = face_x + side * 0.004
			for k in spokes:
				var a := TAU * float(k) / float(spokes)
				var spoke := BoxMesh.new()
				spoke.size = Vector3(0.004, rim_r * 0.72, rim_r * 0.14)
				spoke.material = material(METAL, 0.4, 0.6)
				var inst := _instance(label + "_spoke_%s%d" % ["r" if side > 0 else "l", k], spoke, pivot)
				inst.position = Vector3(face_x + side * 0.002, 0, 0) + Vector3(0, cos(a), sin(a)) * rim_r * 0.5
				inst.rotation.x = a
	return pivot


# Thin plate from an outline of [point, half_width] rows: a loft of flat rectangles along the rows (V06 doors).
static func _plate(rows: Array, normal: Vector3, along: Vector3, thickness: float, mat: Material) -> ArrayMesh:
	var rings := []
	for row in rows:
		var centre: Vector3 = row[0]
		var hw: float = row[1]
		var ring: Array[Vector3] = []
		for corner in [[1.0, -1.0], [1.0, 1.0], [-1.0, 1.0], [-1.0, -1.0]]:
			ring.append(centre + normal * corner[0] * thickness / 2.0 + along * corner[1] * hw)
		rings.append(ring)
	return _loft(rings, mat)


static func _gear(root: Node3D, frames: Dictionary) -> Dictionary:
	var g: Dictionary = D.gear
	var gear := {}
	var rake := deg_to_rad(float(g.rake_deg))
	for sgn in [-1.0, 1.0]:
		var suffix := "right" if sgn > 0 else "left"
		var x_strut: float = sgn * (g.track / 2.0 - 0.03)
		var to_root: Transform3D = frames[suffix]
		var axle := Vector3(sgn * g.track / 2.0, g.main_axle[1], g.main_axle[0])
		# Leg top inside the wing: the lower skin at the chord station that gives the data rake (axle forward of the top).
		var le: Vector3 = to_root * _wing_skin_point(x_strut, 0.0, false)
		var te: Vector3 = to_root * _wing_skin_point(x_strut, 1.0, false)
		var top: Vector3 = to_root * _wing_skin_point(x_strut, 0.12, false) + Vector3(0, 0.01, 0)
		for _pass in 3: # the skin height depends on the station; converges in two passes
			var top_z: float = axle.z + (top.y - axle.y) * tan(rake)
			var xc: float = clampf((top_z - le.z) / (te.z - le.z), 0.03, 0.5)
			top = to_root * _wing_skin_point(x_strut, xc, false) + Vector3(0, 0.01, 0)
		var bottom := Vector3(x_strut, axle.y, axle.z)
		var leg := bottom - top
		_strut("main_strut_" + suffix, top, bottom, g.strut_radius * 0.8, root) # polished piston
		_strut("main_oleo_" + suffix, top, top + leg * 0.55, g.strut_radius * 1.5, root) # outer cylinder
		_strut("axle_" + suffix, bottom, axle, g.strut_radius * 0.6, root)
		# Torque scissor behind the leg: two short links meeting at a knee offset aft.
		var aft := Vector3(0, 0, 1)
		var sc: Dictionary = g.scissor
		var upper_pin: Vector3 = top + leg * 0.55 + aft * g.strut_radius * 1.5
		var lower_pin: Vector3 = top + leg.normalized() * (leg.length() * 0.55 + float(sc.length)) + aft * g.strut_radius * 0.8
		var knee: Vector3 = (upper_pin + lower_pin) / 2.0 + aft * float(sc.offset)
		_strut("scissor_upper_" + suffix, upper_pin, knee, g.strut_radius * 0.35, root)
		_strut("scissor_lower_" + suffix, knee, lower_pin, g.strut_radius * 0.35, root)
		gear[suffix] = _wheel("wheel_" + suffix, g.main_wheel_diameter, g.main_wheel_width, axle, root, int(g.hub_spokes))
		# Strut door: shaped plate inboard of the leg, following its rake; outline [u along the leg, half width].
		var door_x: float = x_strut - sgn * (g.strut_radius * 1.5 + 0.004)
		var rows := []
		for row in g.strut_door:
			var at: Vector3 = top + leg * float(row[0])
			rows.append([Vector3(door_x, at.y - 0.012 * (1.0 - float(row[0])), at.z), float(row[1])])
		_instance("gear_door_" + suffix, _plate(rows, Vector3.RIGHT, Vector3.BACK, 0.003, _skin(Finish.PLAIN)), root)
		# Inner well doors (closed): a panel 1.5 mm proud of the lower wing skin from the fuselage side to the leg.
		var wd: Dictionary = g.well_doors
		var grid := []
		for i in 5:
			var z: float = float(wd.z0) + float(wd.length) * float(i) / 4.0
			var line: Array[Vector3] = []
			for j in 4:
				var x: float = sgn * lerpf(float(wd.inner_x), absf(door_x) - 0.012, float(j) / 3.0)
				var le_x: Vector3 = to_root * _wing_skin_point(x, 0.0, false)
				var te_x: Vector3 = to_root * _wing_skin_point(x, 1.0, false)
				var fx: float = clampf((z - le_x.z) / (te_x.z - le_x.z), 0.0, 1.0)
				line.append(to_root * _wing_skin_point(x, fx, false) + Vector3(0, -0.0015, 0))
			grid.append(line)
		_instance("well_door_" + suffix, _strip(grid, _skin(Finish.PLAIN)), root)
	# Tail wheel: steering pivot (about +Y) on the tail cone bottom above the axle, short strut down to it.
	var steering := Node3D.new()
	steering.name = "tail_steering"
	steering.position = Vector3(0, skin_y(g.tail_axle[0], 0.0, false) + 0.006, g.tail_axle[0])
	root.add_child(steering)
	var axle_local := Vector3(0, g.tail_axle[1], g.tail_axle[0]) - steering.position
	_strut("tail_strut", Vector3(0, 0.004, 0), axle_local + Vector3(0, 0.004, 0), 0.006, steering)
	gear["tail"] = _wheel("wheel_tail", g.tail_wheel_diameter, 0.02, axle_local, steering)
	gear["steering"] = steering
	# Tail-wheel doors (V06): two plates hinged on the belly either side of the well, hanging open.
	var td: Dictionary = g.tailwheel_doors
	for sgn in [-1.0, 1.0]:
		var hinge_x: float = sgn * 0.02
		var open := deg_to_rad(float(td.open_deg))
		var hang := Vector3(sgn * cos(open), -sin(open), 0) * float(td.width)
		var rows := []
		for z in [g.tail_axle[0] - float(td.length) * (1.0 - float(td.aft_fraction)), g.tail_axle[0] + float(td.length) * float(td.aft_fraction)]:
			var hinge := Vector3(hinge_x, skin_y(float(z), hinge_x, false) - 0.002, float(z))
			rows.append([hinge + hang / 2.0, float(td.width) / 2.0])
		_instance("tail_door_" + ("right" if sgn > 0 else "left"), _plate(rows, Vector3(sin(open), sgn * cos(open), 0), hang.normalized(), 0.003, _skin(Finish.PLAIN)), root)
	return gear


# One blade along +X in the propeller frame (shaft along Z, flight toward -Z); sections twist to atan(P / 2 pi r).
static func _blade_ring(r: float) -> Array[Vector3]:
	var p: Dictionary = D.propeller
	var tip: float = p.diameter / 2.0
	var x := r / tip
	var chord := _table(p.blade.chord_fraction_of_radius, x) * tip
	var thickness := _table(p.blade.thickness_fraction_of_chord, x) * chord
	var beta := atan(float(p.pitch) / (TAU * r))
	var along := Vector3(0, cos(beta), -sin(beta)) # trailing edge -> leading edge
	var face := Vector3(0, -sin(beta), -cos(beta)) # forward (cambered) face normal
	var ring: Array[Vector3] = []
	for k in 21:
		var s := float(k) / 20.0
		var bump := sqrt(s) * (1.0 - s) / 0.385
		ring.append(Vector3(r, 0, 0) + along * (0.35 - s) * chord + face * thickness * bump)
	for k in range(19, 0, -1):
		var s := float(k) / 20.0
		ring.append(Vector3(r, 0, 0) + along * (0.35 - s) * chord - face * thickness * 0.08 * sqrt(s) * (1.0 - s) / 0.385)
	return ring


# Paddle blade in two surfaces of one mesh: dark body and a yellow tip over the last PROP_TIP_M.
static func _blade_mesh() -> ArrayMesh:
	var p: Dictionary = D.propeller
	var tip: float = p.diameter / 2.0
	var split := tip - PROP_TIP_M
	var radii: Array[float] = []
	for i in 19: radii.append(lerpf(p.hub_radius, tip, sin(PI / 2.0 * float(i) / 18.0)))
	radii.append(split)
	radii.sort()
	var body := []
	var end := []
	for r in radii:
		var ring := _blade_ring(r)
		if r <= split + 1e-9: body.append(ring)
		if r >= split - 1e-9: end.append(ring)
	var mesh := _loft(body, material(PROP, 0.45), [true, false])
	return _loft(end, material(YELLOW, 0.45), [false, true], mesh)


static func _propeller(root: Node3D) -> Node3D:
	var p: Dictionary = D.propeller
	var s: Dictionary = D.spinner
	var thrust := Node3D.new()
	thrust.name = "thrust_frame"
	thrust.position = Vector3(0, 0, s.back_z)
	# V07: the drawing's down thrust tilts the spinner/propeller axis nose-down (forward -Z dips: negative rotation
	# about +X). Visual only: the physics thrust stays axial until P51-06 records the same angle in the data file.
	thrust.rotation.x = -deg_to_rad(float(p.down_thrust_deg))
	root.add_child(thrust)
	# Spinner: pointed P-51 lathe from the back plate (z = 0 here) to the tip.
	var rings := []
	var length: float = s.back_z - s.tip_z
	for k in 15:
		var u := float(k) / 14.0
		var r: float = s.radius * pow(sin(u * PI / 2.0), 0.6)
		var ring: Array[Vector3] = []
		for j in 24:
			var angle := TAU * j / 24.0
			ring.append(Vector3(r * cos(angle), r * sin(angle), -length * (1.0 - u)))
		rings.append(ring)
	_instance("spinner", _loft(rings, material(RED, 0.3, 0.2), [false, true]), thrust)
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(0, 0, p.z - s.back_z)
	thrust.add_child(propeller)
	var blade := _blade_mesh()
	for k in int(p.blades):
		var node := _instance("blade_%d" % k, blade, propeller)
		node.rotation.z = TAU * k / float(p.blades)
	return propeller


## Kit placeholder throws (degrees), used by the inspector until the P-51 data file sets flight throws.
static func manual_throws_deg() -> Dictionary:
	return {aileron = 16.1, elevator = 14.7, rudder = 33.5} # app/data/aircraft/p51d_mustang_120.json controls.max_throw (V01)


# Trim-tab sleeve (V10): for each station the surface's own section is sampled at the tab's front (half thickness
# there) and at the trailing edge, and a 4-point wedge 1.5 mm proud of it is lofted along the stations. `ring_at`
# returns the section at a station as [[thickness, chord], ...] pairs (thickness axis first), `te` the chord at the TE.
static func _tab_sleeve(stations: Array, sections: Array, tes: Array, chord: float, thick_axis: Vector3, span_axis: Vector3, chord_axis: Vector3) -> ArrayMesh:
	var rings := []
	for i in stations.size():
		var te: float = tes[i]
		var z_f: float = te - chord
		var h_f := 0.0
		for pt in sections[i]:
			if absf(float(pt[1]) - z_f) < chord * 0.35: h_f = maxf(h_f, absf(float(pt[0])))
		h_f = maxf(h_f, 0.002)
		var ring: Array[Vector3] = []
		for corner in [[h_f + 0.0015, z_f], [0.0015, te + 0.001], [-0.0015, te + 0.001], [-(h_f + 0.0015), z_f]]:
			ring.append(span_axis * float(stations[i]) + thick_axis * float(corner[0]) + chord_axis * float(corner[1]))
		rings.append(ring)
	return _loft(rings, material(METAL, 0.45, 0.5))


# V10 details: gun ports, pitot, antenna mast and wire, navigation and tail lights, fuel caps, trim tabs. Each is a few
# primitives placed from the data; the trim tabs hang from the hinge nodes so they move with the surfaces.
static func _details(root: Node3D, frames: Dictionary, hinges: Dictionary) -> void:
	var de: Dictionary = D.details
	var w: Dictionary = D.wing
	var half: float = w.span / 2.0
	var t: Dictionary = D.tail
	for sgn in [-1.0, 1.0]:
		var side := "right" if sgn > 0 else "left"
		var to_root: Transform3D = frames[side]
		# Gun ports: short dark tubes on the leading edge, the inboard barrel protruding.
		var gp: Dictionary = de.gun_ports
		for i in 3:
			var x: float = sgn * float(gp.x[i])
			var le: Vector3 = to_root * _wing_skin_point(x, 0.0, true, true)
			var length: float = float(gp.protrusion[i]) + 0.02
			var tube := _cylinder("gun_port_%s_%d" % [side, i], float(gp.bore_radius), length, DARK, root, 10)
			tube.rotation.x = PI / 2.0
			tube.position = le + Vector3(0, 0, 0.01 - length / 2.0) # 1 cm inside the LE, the rest ahead of it
		# Navigation light on the tip leading edge: red left, green right.
		var nav := SphereMesh.new()
		nav.radius = float(de.nav_lights.radius)
		nav.height = nav.radius * 2.0
		nav.radial_segments = 10
		nav.rings = 6
		nav.material = material(Color("d02020") if sgn < 0 else Color("20b040"), 0.3)
		var tip_pt: Vector3 = to_root * _wing_skin_point(sgn * (half - 0.012), 0.03, true)
		_instance("nav_light_" + side, nav, root, tip_pt)
		# Fuel cap on the upper wing near the root: a flush dark disc.
		var fc: Dictionary = de.fuel_caps
		var cap_pt: Vector3 = to_root * _wing_skin_point(sgn * float(fc.x), float(fc.chord_fraction), true)
		var cap := _cylinder("fuel_cap_" + side, float(fc.radius), 0.002, DARK, root, 12)
		cap.position = cap_pt + Vector3(0, 0.001, 0)
		# Elevator trim tab: a thin box on the inboard trailing edge, following the TE sweep, child of the hinge.
		var et: Dictionary = de.elevator_tab
		var inner: float = t.fin_thickness / 2.0 + 0.006 + float(et.s0)
		var s0: float = inner
		var s1: float = inner + float(et.span)
		var tail_frame: Node3D = hinges.elevator.get_parent()
		var hz: float = tail_frame.position.z
		var e_stations := []
		var e_sections := []
		var e_tes := []
		for k in 4:
			var sp: float = lerpf(s0, s1, float(k) / 3.0)
			var sec := []
			for v in _stab_ring(sgn * sp, hz, "moving"): sec.append([v.y, v.z])
			e_stations.append(sgn * sp)
			e_sections.append(sec)
			e_tes.append(_stab_plan(sp)[1] - hz)
		_instance("elevator_tab_" + side, _tab_sleeve(e_stations, e_sections, e_tes, float(et.chord), Vector3.UP, Vector3.RIGHT, Vector3.BACK), hinges.elevator)
	# Pitot under the right wing: a drop and a forward-pointing tube.
	var pi: Dictionary = de.pitot
	var under: Vector3 = frames["right"] * _wing_skin_point(float(pi.x), float(pi.chord_fraction), false)
	var foot := under + Vector3(0, -float(pi.drop), 0)
	_strut("pitot_mast", under + Vector3(0, 0.005, 0), foot, float(pi.radius), root)
	_strut("pitot_tube", foot, foot + Vector3(0, 0, -float(pi.length)), float(pi.radius) * 0.7, root)
	# Antenna mast on the spine aft of the hood, raked forward, with the wire to the fin's leading edge near the top.
	var am: Dictionary = de.antenna_mast
	var zm: float = float(D.canopy.top[-1][0]) + float(am.z_after_canopy)
	var base := Vector3(0, profile(zm, 2) - 0.005, zm)
	var rake := deg_to_rad(float(am.rake_deg))
	var mast_top := base + Vector3(0, cos(rake), -sin(rake)) * float(am.height)
	_strut("antenna_mast", base, mast_top, float(am.radius), root)
	var fin_y: float = _fin_top_y() - 0.03
	var wire_end := Vector3(0, fin_y, _upper_z_at(fin_y, true) + 0.003)
	var wire := _cylinder("antenna_wire", float(am.wire_radius), (wire_end - mast_top).length(), DARK, root, 6)
	wire.position = (mast_top + wire_end) / 2.0
	wire.quaternion = Quaternion(Vector3.UP, (wire_end - mast_top).normalized())
	# Rudder trim tab on the trailing edge, following the rake, child of the rudder hinge; tail light at the rudder base.
	var rt: Dictionary = de.rudder_tab
	var y_base: float = _tail_lower_y(t.rudder_hinge_z) + 0.003
	var y0: float = maxf(y_base + float(rt.y0), float(t.rudder_te_bottom[1]) + 0.005) # above the base bevel: the tab follows one straight TE
	var y1: float = y0 + float(rt.span)
	var r_stations := []
	var r_sections := []
	var r_tes := []
	for k in 5:
		var yk: float = lerpf(y0, y1, float(k) / 4.0)
		var sec := []
		for v in _fin_ring(yk, "moving"): sec.append([v.x, v.z])
		r_stations.append(yk)
		r_sections.append(sec)
		r_tes.append(_rudder_te(yk) - t.rudder_hinge_z)
	_instance("rudder_tab", _tab_sleeve(r_stations, r_sections, r_tes, float(rt.chord), Vector3.RIGHT, Vector3.UP, Vector3.BACK), hinges.rudder)
	var tail_light := SphereMesh.new()
	tail_light.radius = 0.008
	tail_light.height = 0.016
	tail_light.radial_segments = 8
	tail_light.rings = 5
	tail_light.material = material(Color("f4f4f0"), 0.2)
	_instance("tail_light", tail_light, hinges.rudder, Vector3(0, float(t.rudder_te_bottom[1]) + 0.012, _rudder_te(float(t.rudder_te_bottom[1]) + 0.012) - t.rudder_hinge_z - 0.008))


static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("aircraft_id", D.id)
	root.set_meta("visual_revision", VISUAL_REVISION)
	root.set_meta("status", "experimental: first visual model from scaled full-size dimensions")
	root.set_meta("evidence", "assets/aircraft/p51d-mustang-120/geometry.json (DATA.evidence)")
	var hinges := {}
	_fuselage(root)
	_exhausts(root)
	_scoop(root)
	_carb_intake(root)
	_canopy(root)
	_pilot(root)
	var frames := _wings(root, hinges)
	_tail(root, hinges)
	var gear := _gear(root, frames)
	_details(root, frames, hinges)
	var propeller := _propeller(root)
	return {root = root, propeller = propeller, hinges = hinges, gear = gear, frames = frames}
