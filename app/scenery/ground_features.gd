## SCENERY-PLAN SC-05/SC-06/SC-11: things that lie on or along the ground. Flat layers are stacked 2 cm apart — the
## separation SC-01 measured clean up to 100 m camera height — over a subdivided ground (G-1): worn ring 0.02 m, gravel
## and tracks 0.04 m, contact shadows 0.06 m. Contact shadows are alpha-blended dark polygons cast along the fixed sun
## (alpha blending fogs correctly; blend_mul was 57–59 % too dark in SC-01).
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")

const LIFT_WORN := 0.02
const LIFT_SURFACE := 0.04
const LIFT_SHADOW := 0.06
const SHADOW_ALPHA := 0.34 # core darkness, estimated against the planar airplane shadow (shadow.gd uses 0.6 for a silhouette)
const SHADOW_SOFT_M := 0.35 # soft edge width


# ---------------- tracks and patches ----------------

## A dirt track along a polyline (render XZ points): two wheel ruts, a grassy crown, mitred joints (no overlaps).
static func track(k: MeshKit, pts: PackedVector2Array, width: float, surface: String, theme: String) -> void:
	var dirt := Palette.col("dirt") if surface == "dirt" else Palette.col("gravel")
	var crown := Palette.vegetation(Palette.col("worn_grass"), theme)
	# lanes across the width (fractions of the half-width): edge, rut, crown, rut, edge
	var lanes := [[-1.0, -0.62, dirt.lightened(0.06)], [-0.62, -0.22, dirt], [-0.22, 0.22, crown], [0.22, 0.62, dirt], [0.62, 1.0, dirt.lightened(0.06)]]
	var offs := _miter_normals(pts)
	for i in pts.size() - 1:
		for lane: Array in lanes:
			var a0: float = lane[0]
			var a1: float = lane[1]
			var c: Color = lane[2]
			var tone := 0.94 + 0.1 * Palette.hash01(i, int(a0 * 10.0))
			var p00 := pts[i] + offs[i] * a0 * width * 0.5
			var p01 := pts[i] + offs[i] * a1 * width * 0.5
			var p10 := pts[i + 1] + offs[i + 1] * a0 * width * 0.5
			var p11 := pts[i + 1] + offs[i + 1] * a1 * width * 0.5
			_flat_quad(k, p00, p10, p11, p01, LIFT_SURFACE, c * Color(tone, tone, tone))


## Per-point offset directions with miter scaling, so consecutive segments share their joint edge exactly.
static func _miter_normals(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var d0 := (pts[i] - pts[maxi(i - 1, 0)]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
		var d1 := (pts[mini(i + 1, pts.size() - 1)] - pts[i]).normalized() if i < pts.size() - 1 else d0
		var t := (d0 + d1).normalized()
		var n := Vector2(-t.y, t.x)
		var scale := 1.0 / maxf(0.35, n.dot(Vector2(-d1.y, d1.x)))
		out.append(n * scale)
	return out


## A flat quad on the ground at `lift`, corners counter-clockwise seen from above (any order is fixed here).
static func _flat_quad(k: MeshKit, a: Vector2, b: Vector2, c: Vector2, d: Vector2, lift: float, col: Color) -> void:
	var pa := Vector3(a.x, lift, a.y)
	var pb := Vector3(b.x, lift, b.y)
	var pc := Vector3(c.x, lift, c.y)
	var pd := Vector3(d.x, lift, d.y)
	if (pb - pa).cross(pc - pa).y < 0.0: # make it face up
		k.quad(pa, pd, pc, pb, col)
	else:
		k.quad(pa, pb, pc, pd, col)


## A gravel / dirt / worn patch (render XZ polygon) with a worn-grass ring, so it does not end in a hard line.
static func patch(k: MeshKit, poly: PackedVector2Array, surface: String, theme: String, seed: int) -> void:
	var ring := Geometry2D.offset_polygon(poly, 0.9, Geometry2D.JOIN_ROUND)
	var worn := Palette.vegetation(Palette.col("worn_grass"), theme)
	if not ring.is_empty():
		_fill(k, ring[0], LIFT_WORN, worn, worn.darkened(0.08), seed)
	var base: Color = {"gravel": Palette.col("gravel"), "dirt": Palette.col("dirt"), "worn": worn}[surface]
	var alt: Color = {"gravel": Palette.col("gravel_dark"), "dirt": Palette.col("dirt").darkened(0.12), "worn": worn.darkened(0.1)}[surface]
	_fill(k, poly, LIFT_SURFACE, base, alt, seed + 1)


## Triangulated fill with a per-vertex tone from a position hash (a soft mottling instead of a flat colour).
static func _fill(k: MeshKit, poly: PackedVector2Array, lift: float, a: Color, b: Color, seed: int) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var pts: Array[Vector3] = []
		var cs: Array[Color] = []
		for j in 3:
			var p := poly[idx[t + j]]
			pts.append(Vector3(p.x, lift, p.y))
			cs.append(a.lerp(b, Palette.hash01(int(p.x * 4.0), int(p.y * 4.0), seed)))
		var up := (pts[1] - pts[0]).cross(pts[2] - pts[0]).y > 0.0
		var o := PackedInt32Array([0, 1, 2]) if up else PackedInt32Array([0, 2, 1])
		_tri_colored(k, pts[o[0]], pts[o[1]], pts[o[2]], cs[o[0]], cs[o[1]], cs[o[2]])


## A triangle with per-corner colours, counter-clockwise from above (bypasses MeshKit.tri's single colour).
static func _tri_colored(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var pa := k.xf * a
	var pb := k.xf * b
	var pc := k.xf * c
	var n := (pb - pa).cross(pc - pa).normalized()
	k.verts.append_array([pa, pc, pb])
	k.norms.append_array([n, n, n])
	k.cols.append_array([ca, cc, cb])


# ---------------- contact shadows ----------------

## Adds a soft contact shadow for a prop placed with `t` (render), footprint `size` (w × h × l, local), mode:
## "solid" (the footprint swept along the sun to its height), "roof" (only the roof outline, cast from `size.y`),
## "crown" (a disc of the crown, cast from 70 % of the height, plus the trunk's line).
static func contact_shadow(k: MeshKit, t: Transform3D, size: Vector3, mode: String, sun: Vector3) -> void:
	var cast := Vector2(-sun.x, -sun.z) / maxf(sun.y, 0.2) # ground offset per metre of height, away from the sun
	var hw := size.x * 0.5
	var hl := size.z * 0.5
	var base: Array[Vector2] = []
	for c: Vector2 in [Vector2(-hw, -hl), Vector2(hw, -hl), Vector2(hw, hl), Vector2(-hw, hl)]:
		var p := t * Vector3(c.x, 0, c.y)
		base.append(Vector2(p.x, p.z))
	var pts := PackedVector2Array()
	match mode:
		"roof":
			for p: Vector2 in base:
				pts.append(p + cast * size.y)
		"crown":
			var centre := t * Vector3.ZERO
			var r := maxf(hw, hl) * 0.85
			var c2 := Vector2(centre.x, centre.z) + cast * size.y * 0.7
			for i in 12:
				var a := TAU * i / 12.0
				pts.append(c2 + Vector2(cos(a), sin(a)) * r)
			pts.append(Vector2(centre.x, centre.z))
		_:
			for p: Vector2 in base:
				pts.append(p)
				pts.append(p + cast * size.y)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() < 4:
		return
	hull.remove_at(hull.size() - 1) # convex_hull repeats the first point
	var centroid := Vector2.ZERO
	for p: Vector2 in hull:
		centroid += p
	centroid /= hull.size()
	var core := Color(0, 0, 0, SHADOW_ALPHA)
	var edge := Color(0, 0, 0, 0)
	for i in hull.size():
		var a := hull[i]
		var b := hull[(i + 1) % hull.size()]
		var ao := a + (a - centroid).normalized() * SHADOW_SOFT_M
		var bo := b + (b - centroid).normalized() * SHADOW_SOFT_M
		_shadow_tri(k, centroid, a, b, core, core, core)
		_shadow_tri(k, a, ao, bo, core, edge, edge)
		_shadow_tri(k, a, bo, b, core, edge, core)


static func _shadow_tri(k: MeshKit, a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color) -> void:
	var pa := Vector3(a.x, LIFT_SHADOW, a.y)
	var pb := Vector3(b.x, LIFT_SHADOW, b.y)
	var pc := Vector3(c.x, LIFT_SHADOW, c.y)
	if (pb - pa).cross(pc - pa).y > 0.0:
		_tri_colored(k, pa, pb, pc, ca, cb, cc)
	else:
		_tri_colored(k, pa, pc, pb, ca, cc, cb)


# ---------------- hedges and fences ----------------

## A continuous hedgerow along render-XZ points: overlapping lumps every ~1.5 m with seeded size and tone, and a
## hedgerow tree every ~45 m (common in field boundaries). Themed.
static func hedge(k: MeshKit, pts: PackedVector2Array, height: float, width: float, theme: String, seed: int, trees := true) -> void:
	var dark := Palette.veg("hedge", theme)
	var light := Palette.veg("hedge_light", theme)
	var walked := 0.0
	var next_tree := 20.0 + 25.0 * Palette.hash01(seed, 1)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var steps := maxi(1, int(seg / 1.5))
		var dir := (b - a) / seg
		for s in steps:
			var p := a.lerp(b, (s + 0.5) / steps)
			var h := Palette.hash01(seed, i * 997 + s, 3)
			var hh := height * (0.82 + 0.3 * h)
			var ww := width * (0.85 + 0.3 * Palette.hash01(seed, i * 997 + s, 4))
			var col := dark.lerp(light, Palette.hash01(seed, i * 997 + s, 5) * 0.7)
			var saved := k.xf
			k.xf = k.xf * Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(p.x, 0, p.y))
			k.ellipsoid(Vector3(0, hh * 0.48, 0), Vector3(2.6, hh * 1.05, ww), col, seed + i * 131 + s, 7, 3, 0.12)
			k.xf = saved
			walked += seg / steps
			if trees and walked > next_tree:
				next_tree = walked + 35.0 + 30.0 * Palette.hash01(seed, i, s)
				_hedge_tree(k, p, seed + i * 7 + s, theme)


static func _hedge_tree(k: MeshKit, p: Vector2, seed: int, theme: String) -> void:
	var h := 7.0 + 4.0 * Palette.hash01(seed, 2)
	k.cylinder(0.28, 0.18, h * 0.5, 6, Vector3(p.x, 0, p.y), Palette.col("trunk"))
	var leaf := Palette.veg("leaf", theme)
	k.ellipsoid(Vector3(p.x, h * 0.66, p.y), Vector3(5.0, 4.2, 5.0), leaf.lerp(Palette.veg("leaf_dark", theme), 0.3), seed, 8, 4)
	for i in 4:
		var a := TAU * i / 4.0 + Palette.hash01(seed, i) * 0.8
		var r := 1.4 + 0.6 * Palette.hash01(seed, i, 1)
		var s := 2.4 + 0.8 * Palette.hash01(seed, i, 2)
		k.ellipsoid(Vector3(p.x + cos(a) * r, h * 0.62 + 1.4 * Palette.hash01(seed, i, 3), p.y + sin(a) * r), Vector3(s, s * 0.85, s),
			leaf.lerp(Palette.veg("leaf_light", theme), 0.5 * Palette.hash01(seed, i, 4)), seed + i, 7, 3)


## Post-and-wire ("wire") or post-and-rail ("rail") fence along render-XZ points.
static func fence(k: MeshKit, pts: PackedVector2Array, style: String, seed: int) -> void:
	var spacing := 3.0 if style == "wire" else 2.5
	var post := Palette.col("wood_grey") if style == "wire" else Palette.col("wood")
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var n := maxi(1, int(round(seg / spacing)))
		for s in n + (1 if i == pts.size() - 2 else 0):
			var p := a.lerp(b, float(s) / n)
			var lean := (Palette.hash01(seed, i * 1000 + s) - 0.5) * 0.06
			var top := Vector3(p.x + lean, 1.25 if style == "wire" else 1.15, p.y)
			k.beam(Vector3(p.x, 0, p.y), top, 0.1 if style == "wire" else 0.13, post.darkened(0.15 * Palette.hash01(seed, s, i)))
		if style == "wire":
			for y: float in [0.55, 0.85, 1.12]:
				k.beam(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), 0.012, Palette.col("steel"))
		else:
			for y: float in [0.45, 0.95]:
				k.beam(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), 0.08, post.lightened(0.05))
