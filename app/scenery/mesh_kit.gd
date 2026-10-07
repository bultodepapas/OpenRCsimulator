## SCENERY-PLAN SC-04: a tiny geometry builder for scenery props. Flat-shaded triangles with vertex colours (sRGB:
## measured to render exactly like an albedo colour in Compatibility 4.7.2), emitted directly in cell coordinates through
## a transform, so a whole cell becomes ONE surface with ONE shared material (Compatibility does no 3D batching: SC-01).
## Winding: Godot front faces are clockwise; helpers take polygons counter-clockwise as seen from outside.
extends RefCounted

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
## Current local-to-cell transform; set by callers (push/pop through `with`).
var xf := Transform3D.IDENTITY


func is_empty() -> bool:
	return verts.is_empty()


func triangle_count() -> int:
	return verts.size() / 3


## One triangle, corners counter-clockwise seen from its front, already in local coordinates.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	if xf.basis.determinant() < 0.0: # a mirror flips the apparent winding
		var t := pb
		pb = pc
		pc = t
	var n := (pb - pa).cross(pc - pa)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	verts.append(pa)
	verts.append(pc) # clockwise for Godot
	verts.append(pb)
	norms.append(n)
	norms.append(n)
	norms.append(n)
	cols.append(col)
	cols.append(col)
	cols.append(col)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)


## Convex polygon, counter-clockwise from its front.
func poly(points: PackedVector3Array, col: Color) -> void:
	for i in range(1, points.size() - 1):
		tri(points[0], points[i], points[i + 1], col)


## Axis-aligned box centred at `c` (local). `faces` skips the bottom by default (never seen on the ground).
func box(size: Vector3, c: Vector3, col: Color, bottom := false, top_col: Variant = null) -> void:
	var h := size * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var top: Color = top_col if top_col != null else col
	quad(p[4], p[5], p[6], p[7], col) # +z
	quad(p[1], p[0], p[3], p[2], col) # -z
	quad(p[5], p[1], p[2], p[6], col) # +x
	quad(p[0], p[4], p[7], p[3], col) # -x
	quad(p[7], p[6], p[2], p[3], top) # +y
	if bottom:
		quad(p[0], p[1], p[5], p[4], col)


## Box from a base point (bottom centre) upward: the common case for posts and walls.
func block(size: Vector3, base: Vector3, col: Color, top_col: Variant = null) -> void:
	box(size, base + Vector3(0, size.y * 0.5, 0), col, false, top_col)


## A thin beam between two points (square section `t`), any direction.
func beam(a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-6:
		return
	var y := d / length
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var saved := xf
	xf = xf * Transform3D(Basis(x, y, z), a + d * 0.5)
	box(Vector3(t, length, t), Vector3.ZERO, col, true)
	xf = saved


## Cylinder or frustum along +Y from `base`. smooth=false keeps the low-poly facets.
func cylinder(r_bottom: float, r_top: float, height: float, segments: int, base: Vector3, col: Color,
		cap_top := true, cap_col: Variant = null, cap_bottom := false) -> void:
	var cap: Color = cap_col if cap_col != null else col
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var b0 := base + Vector3(cos(a0) * r_bottom, 0, sin(a0) * r_bottom)
		var b1 := base + Vector3(cos(a1) * r_bottom, 0, sin(a1) * r_bottom)
		var t0 := base + Vector3(cos(a0) * r_top, height, sin(a0) * r_top)
		var t1 := base + Vector3(cos(a1) * r_top, height, sin(a1) * r_top)
		if r_top > 1e-6:
			quad(b0, t0, t1, b1, col)
		else:
			tri(b0, t0, b1, col)
		if cap_top and r_top > 1e-6:
			tri(base + Vector3(0, height, 0), t1, t0, cap)
		if cap_bottom:
			tri(base, b0, b1, cap)


## A horizontal cylinder (round bale, log, wheel) along local X, resting on y = 0, centred at `c` on the ground.
func roll(radius: float, width: float, segments: int, c: Vector3, side_col: Color, end_col: Color, ring_col: Variant = null) -> void:
	var saved := xf
	xf = xf * Transform3D(Basis(Vector3(0, 0, 1), -PI / 2.0), c + Vector3(-width * 0.5, radius, 0))
	cylinder(radius, radius, width, segments, Vector3.ZERO, side_col, true, end_col, true)
	if ring_col != null: # the spiral of a round bale: a darker inner disc slightly proud of each end
		for side: float in [width + 0.003, -0.003]:
			for i in segments:
				var a0 := TAU * i / segments
				var a1 := TAU * (i + 1) / segments
				var r := radius * 0.55
				var p0 := Vector3(cos(a0) * r, side, sin(a0) * r)
				var p1 := Vector3(cos(a1) * r, side, sin(a1) * r)
				if side > 0.0:
					tri(Vector3(0, side, 0), p1, p0, ring_col)
				else:
					tri(Vector3(0, side, 0), p0, p1, ring_col)
	xf = saved


## Gable roof over a w (x) × l (z) footprint at height `eave`, ridge along Z, with overhang `o`.
func gable_roof(w: float, l: float, eave: float, rise: float, o: float, col: Color, gable_col: Color) -> void:
	var hw := w * 0.5 + o
	var hl := l * 0.5 + o
	var ridge := eave + rise
	var e := eave - o * rise / (w * 0.5)
	quad(Vector3(-hw, e, -hl), Vector3(-hw, e, hl), Vector3(0, ridge, hl), Vector3(0, ridge, -hl), col)
	quad(Vector3(hw, e, hl), Vector3(hw, e, -hl), Vector3(0, ridge, -hl), Vector3(0, ridge, hl), col)
	# soffits (undersides) so the overhang has thickness from below
	quad(Vector3(-hw, e - 0.04, hl), Vector3(-hw, e - 0.04, -hl), Vector3(0, ridge - 0.04, -hl), Vector3(0, ridge - 0.04, hl), col.darkened(0.35))
	quad(Vector3(hw, e - 0.04, -hl), Vector3(hw, e - 0.04, hl), Vector3(0, ridge - 0.04, hl), Vector3(0, ridge - 0.04, -hl), col.darkened(0.35))
	# gable triangles on the walls
	var gw := w * 0.5
	tri(Vector3(-gw, eave, l * 0.5), Vector3(gw, eave, l * 0.5), Vector3(0, eave + rise * (gw / (w * 0.5)), l * 0.5), gable_col)
	tri(Vector3(gw, eave, -l * 0.5), Vector3(-gw, eave, -l * 0.5), Vector3(0, eave + rise, -l * 0.5), gable_col)


## Hip roof over w × l at `eave`, rising `rise`, overhang `o`.
func hip_roof(w: float, l: float, eave: float, rise: float, o: float, col: Color) -> void:
	var hw := w * 0.5 + o
	var hl := l * 0.5 + o
	var r := minf(hw, hl) * 0.98
	var ridge_half := maxf(0.0, maxf(hw, hl) - r)
	var top := eave + rise
	var a := Vector3(-hw, eave, -hl)
	var b := Vector3(hw, eave, -hl)
	var c := Vector3(hw, eave, hl)
	var d := Vector3(-hw, eave, hl)
	var r0: Vector3
	var r1: Vector3
	if hw >= hl:
		r0 = Vector3(-ridge_half, top, 0)
		r1 = Vector3(ridge_half, top, 0)
		quad(d, c, r1, r0, col)
		quad(b, a, r0, r1, col)
		tri(c, b, r1, col)
		tri(a, d, r0, col)
	else:
		r0 = Vector3(0, top, -ridge_half)
		r1 = Vector3(0, top, ridge_half)
		quad(c, b, r0, r1, col)
		quad(a, d, r1, r0, col)
		tri(d, c, r1, col)
		tri(b, a, r0, col)
	var under := col.darkened(0.4)
	quad(a, b, c, d, under) # soffit, faces down


## Low-poly blob (bush, crown, hedge lump): an octahedron-derived 18-face shape, scaled per axis, jittered by `seed`.
func blob(c: Vector3, size: Vector3, col: Color, seed: int, shade := 0.12) -> void:
	var ring: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0 + float(seed % 7) * 0.31
		var j := 0.85 + 0.3 * float((seed * (i + 3) * 2654435761) % 1000) / 1000.0
		ring.append(Vector3(cos(a) * j, 0.0, sin(a) * j))
	var top := c + Vector3(0, size.y * 0.5, 0)
	var bot := c + Vector3(0, -size.y * 0.42, 0)
	var mids: Array[Vector3] = []
	for p: Vector3 in ring:
		mids.append(c + Vector3(p.x * size.x * 0.5, 0.06 * size.y, p.z * size.z * 0.5))
	var light := col.lightened(shade)
	var dark := col.darkened(shade)
	for i in 6:
		var m0: Vector3 = mids[i]
		var m1: Vector3 = mids[(i + 1) % 6]
		tri(top, m1, m0, light)
		tri(bot, m0, m1, dark)


## A rounded, organic ellipsoid (tree crowns, hedges, bushes): `seg` around, `bands` from bottom to top, radius
## jittered per vertex by `seed` so no two lumps match. Upper bands are lightened and lower ones darkened a little,
## a cheap stand-in for sky occlusion that keeps crowns reading as volumes at distance.
func ellipsoid(c: Vector3, size: Vector3, col: Color, seed: int, seg := 8, bands := 4, flat_bottom := 0.0) -> void:
	var rings: Array = []
	for b in bands + 1:
		var phi := -PI * 0.5 + PI * b / bands
		var y := sin(phi) * 0.5
		if flat_bottom > 0.0:
			y = maxf(y, -0.5 + flat_bottom)
		var r := cos(phi)
		var ring: Array[Vector3] = []
		for i in seg:
			var a := TAU * (i + 0.5 * (b % 2)) / seg
			var j := 1.0
			if b > 0 and b < bands:
				j = 0.86 + 0.28 * float(((seed + 31) * (b * 97 + i * 13 + 7) * 2654435761) % 1000) / 1000.0
			ring.append(c + Vector3(cos(a) * r * j * size.x * 0.5, y * size.y, sin(a) * r * j * size.z * 0.5))
		rings.append(ring)
	for b in bands:
		var shade := lerpf(-0.16, 0.12, float(b) / maxf(1.0, bands - 1))
		var band_col := col.lightened(shade) if shade > 0.0 else col.darkened(-shade)
		var lo: Array[Vector3] = rings[b]
		var hi: Array[Vector3] = rings[b + 1]
		for i in seg:
			var i1 := (i + 1) % seg
			if b == 0:
				tri(lo[i], hi[i], hi[i1], band_col)
			elif b == bands - 1:
				tri(lo[i], hi[i], lo[i1], band_col)
			else:
				quad(lo[i], hi[i], hi[i1], lo[i1], band_col)


## Appends an already-built mesh's arrays (positions/normals/colours) under transform `t`; `tint` replaces colours whose
## alpha marks a paintable region (alpha < 0.5) — used for car paint. C++ array transforms keep this fast.
func append_arrays(pos: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, t: Transform3D,
		tint: Variant = null) -> void:
	var full := xf * t
	var transformed := full * pos
	var rot := Transform3D(full.basis.orthonormalized(), Vector3.ZERO)
	var n2 := rot * nrm
	var c2 := col
	if tint != null:
		c2 = col.duplicate()
		var paint: Color = tint
		for i in c2.size():
			if c2[i].a < 0.5:
				c2[i] = Color(paint.r, paint.g, paint.b, 1.0)
	if full.basis.determinant() < 0.0: # a mirror reverses the winding: swap two corners of every triangle
		if tint == null:
			c2 = col.duplicate()
		for i in range(0, transformed.size(), 3):
			var tp := transformed[i + 1]
			transformed[i + 1] = transformed[i + 2]
			transformed[i + 2] = tp
			var tn := n2[i + 1]
			n2[i + 1] = n2[i + 2]
			n2[i + 2] = tn
			var tc := c2[i + 1]
			c2[i + 1] = c2[i + 2]
			c2[i + 2] = tc
	verts.append_array(transformed)
	norms.append_array(n2)
	cols.append_array(c2)


func to_mesh(material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## Stable digest of the geometry (determinism tests).
func digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verts.to_byte_array())
	ctx.update(norms.to_byte_array())
	ctx.update(cols.to_byte_array())
	return ctx.finish().hex_encode()
