## SCENERY-PLAN SC-05/SC-06/SC-11: things that lie on or along the ground. Flat layers are stacked 2 cm apart — the
## separation SC-01 measured clean up to 100 m camera height — over a subdivided ground (G-1): worn ring 0.02 m, gravel
## and tracks 0.04 m, contact shadows 0.06 m. Contact shadows are alpha-blended dark polygons cast along the fixed sun
## (alpha blending fogs correctly; blend_mul was 57–59 % too dark in SC-01).
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const FenceParts = preload("res://scenery/fence_parts.gd")

const LIFT_WORN := 0.02
const LIFT_SURFACE := 0.04
const LIFT_SHADOW := 0.06
const SHADOW_ALPHA := 0.34 # core darkness, estimated against the planar airplane shadow (shadow.gd uses 0.6 for a silhouette)
const SHADOW_SOFT_M := 0.35 # soft edge width
const PATCH_TILE_SIZE_M := 1.1
const PATCH_TILE_JITTER_M := 0.12
const PATCH_AGGREGATE_TILE_M := 0.36
const PATCH_AGGREGATE_RATE := 0.05
const PATCH_EDGE_WOBBLE_M := 0.28
const GRAVEL_SHOULDER_M := 0.55
const PATCH_SHOULDER_M := 0.9
const PATCH_FIELD_GRASS_COLOR := Color("#657545") # matches Spec.GRASS for a feathered shoulder edge


# DT-11a: reuse exact patch buffers across Home/Fly builds, never scene resources.
# FIFO bounds include serialized keys and geometry; container overhead is count-bounded.
# Called by synchronous scene builders on the main thread.
const PATCH_CACHE_MAX_ENTRIES := 8
const PATCH_CACHE_MAX_BYTES := 4 * 1024 * 1024
static var _patch_cache: Array[Dictionary] = []
static var _patch_cache_bytes: int = 0


# ---------------- tracks and patches ----------------

## A dirt track along a polyline (render XZ points): two wheel ruts, a grassy crown, mitred joints (no overlaps).
static func track(k: MeshKit, pts: PackedVector2Array, width: float, surface: String, theme: String) -> void:
	var dirt := Palette.col("dirt") if surface == "dirt" else Palette.col("gravel")
	var crown := Palette.vegetation(Palette.col("worn_grass"), theme)
	var route := _round_track_corners(pts, width, 0.994 if surface == "worn" else 0.94)
	if surface == "worn":
		route = _worn_route(route)
	var lanes: Array
	if surface == "worn":
		# A quiet, single pedestrian tread. Its lower lift lets an existing slab or gravel apron cover the join.
		var edge := Color("#647a4b")
		var tread := Color("#627747")
		# Opaque shader markers, not transparency: the downloaded sparse grass
		# scan breaks up the centre more strongly than the feathered shoulders.
		edge.a = 0.32
		tread.a = 0.18
		lanes = [[-1.0, -0.62, edge], [-0.62, 0.62, tread], [0.62, 1.0, edge]]
	else:
		# lanes across the width (fractions of the half-width): edge, rut, crown, rut, edge
		lanes = [[-1.0, -0.62, dirt.lightened(0.06)], [-0.62, -0.22, dirt], [-0.22, 0.22, crown], [0.22, 0.62, dirt], [0.62, 1.0, dirt.lightened(0.06)]]
	var offs := _miter_normals(route)
	var lift := LIFT_WORN if surface == "worn" else LIFT_SURFACE
	for i in route.size() - 1:
		for lane: Array in lanes:
			var a0: float = lane[0]
			var a1: float = lane[1]
			var c: Color = lane[2]
			var tone := 0.94 + 0.1 * Palette.hash01(i, int(a0 * 10.0))
			var w0 := width * 0.5 * (lerpf(0.78, 1.12, Palette.hash01(i, 37)) if surface == "worn" else 1.0)
			var w1 := width * 0.5 * (lerpf(0.78, 1.12, Palette.hash01(i + 1, 37)) if surface == "worn" else 1.0)
			var p00 := route[i] + offs[i] * a0 * w0
			var p01 := route[i] + offs[i] * a1 * w0
			var p10 := route[i + 1] + offs[i + 1] * a0 * w1
			var p11 := route[i + 1] + offs[i + 1] * a1 * w1
			_flat_quad(k, p00, p10, p11, p01, lift, c * Color(tone, tone, tone))


## Break long walking treads into small, uneven mowing/wear intervals. Endpoints and centre route are retained.
static func _worn_route(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([points[0]])
	for segment in points.size() - 1:
		var a := points[segment]
		var b := points[segment + 1]
		var delta := b - a
		var steps := maxi(1, ceili(delta.length() / 0.7))
		var normal := Vector2(-delta.y, delta.x).normalized()
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var point := a.lerp(b, t)
			if step < steps:
				point += normal * (Palette.hash01(segment * 103 + step, 79) - 0.5) * 0.10
			out.append(point)
	return out


## Clip sharp polyline corners with a bounded quadratic arc; endpoints and route intent stay fixed.
## `straight_dot` selects the minimum heading change that merits rounding without trig or frame state.
static func _round_track_corners(pts: PackedVector2Array, width: float, straight_dot: float) -> PackedVector2Array:
	if pts.size() < 3 or width <= 0.0:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var corner := pts[i]
		var incoming_delta := corner - pts[i - 1]
		var outgoing_delta := pts[i + 1] - corner
		var incoming_length := incoming_delta.length()
		var outgoing_length := outgoing_delta.length()
		if incoming_length <= 1e-5 or outgoing_length <= 1e-5:
			continue
		var incoming := incoming_delta / incoming_length
		var outgoing := outgoing_delta / outgoing_length
		var turn_dot := incoming.dot(outgoing)
		if turn_dot >= straight_dot or turn_dot <= -0.96:
			out.append(corner)
			continue
		var cut := minf(width * 2.5, minf(incoming_length, outgoing_length) * 0.25)
		if cut <= 0.01:
			out.append(corner)
			continue
		var entry := corner - incoming * cut
		var exit := corner + outgoing * cut
		if out[out.size() - 1].distance_squared_to(entry) > 1e-10:
			out.append(entry)
		for step in range(1, 4):
			var t := float(step) / 4.0
			var one_minus_t := 1.0 - t
			out.append(entry * (one_minus_t * one_minus_t) + corner * (2.0 * one_minus_t * t) + exit * (t * t))
		out.append(exit)
	out.append(pts[pts.size() - 1])
	return out


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
	# Preserve transformed normals and gravel-mask coordinates, including mirrored kits.
	var key := var_to_bytes([poly, surface, theme, seed, k.xf])
	for entry: Dictionary in _patch_cache:
		if entry.key == key:
			var arrays: Array = bytes_to_var(entry.payload)
			k.verts.append_array(arrays[0])
			k.norms.append_array(arrays[1])
			k.cols.append_array(arrays[2])
			return
	var first_vertex := k.verts.size()
	_patch_uncached(k, poly, surface, theme, seed)
	var payload := var_to_bytes([k.verts.slice(first_vertex), k.norms.slice(first_vertex), k.cols.slice(first_vertex)])
	var entry_bytes := key.size() + payload.size()
	if entry_bytes > PATCH_CACHE_MAX_BYTES:
		return
	while _patch_cache.size() >= PATCH_CACHE_MAX_ENTRIES or _patch_cache_bytes + entry_bytes > PATCH_CACHE_MAX_BYTES:
		var oldest: Dictionary = _patch_cache.pop_front()
		_patch_cache_bytes -= oldest.key.size() + oldest.payload.size()
	_patch_cache.append({key = key, payload = payload})
	_patch_cache_bytes += entry_bytes


static func _patch_uncached(k: MeshKit, poly: PackedVector2Array, surface: String, theme: String, seed: int) -> void:
	var first_vertex := k.verts.size()
	var worn := Palette.vegetation(Palette.col("worn_grass"), theme)
	var base: Color = {"gravel": Palette.col("gravel"), "dirt": Palette.col("dirt"), "worn": worn}[surface]
	var alt: Color = {"gravel": Palette.col("gravel_dark"), "dirt": Palette.col("dirt").darkened(0.12), "worn": worn.darkened(0.1)}[surface]
	var shoulder := GRAVEL_SHOULDER_M if surface == "gravel" else PATCH_SHOULDER_M
	var wobble := PATCH_EDGE_WOBBLE_M if surface == "gravel" else 0.16
	var hash_scale := 0.65 if surface == "gravel" else 1.5
	var ring := Geometry2D.offset_polygon(poly, shoulder, Geometry2D.JOIN_ROUND)
	if not ring.is_empty():
		var outline := _roughen_outline(ring[0], seed, wobble, hash_scale)
		# Start at the apron material, then feather toward the field grass across the worn shoulder.
		_grid_fill(k, outline, LIFT_WORN, base, base.lerp(worn, 0.28), seed, poly, shoulder, PATCH_FIELD_GRASS_COLOR, 1.0, true, false, true)
	var inner_edge_width := 0.62 if surface == "gravel" else 1.15
	var inner_edge_strength := 0.28 if surface == "gravel" else 0.48
	_grid_fill(k, poly, LIFT_SURFACE, base, alt, seed + 1, poly, inner_edge_width, worn, inner_edge_strength, false, surface == "gravel")
	if surface == "gravel":
		# LU-12: mask only this patch; shared flat batches may also contain tracks.
		# Fade the grain through the worn shoulder. No alpha blending or extra draw.
		for i in range(first_vertex, k.verts.size()):
			var p := Vector2(k.verts[i].x, k.verts[i].z)
			var mask := 1.0 if Geometry2D.is_point_in_polygon(p, poly) else 1.0 - smoothstep(0.0, shoulder, _edge_distance(p, poly))
			k.cols[i].a = 1.0 - 0.5 * mask



## Break the outer edge gently, at a bounded fraction of the worn shoulder width.
static func _roughen_outline(poly: PackedVector2Array, seed: int, wobble_m: float, hash_scale: float) -> PackedVector2Array:
	var centre := Vector2.ZERO
	for p: Vector2 in poly:
		centre += p
	centre /= maxi(1, poly.size())
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var steps := maxi(1, int(ceil(a.distance_to(b) / PATCH_TILE_SIZE_M)))
		for step in steps:
			var p := a.lerp(b, float(step) / steps)
			var tone := Palette.hash01(int(floor(p.x * hash_scale)), int(floor(p.y * hash_scale)), seed + 401)
			out.append(p + (p - centre).normalized() * ((tone - 0.5) * wobble_m * 2.0))
	return out


## Clip slightly jittered 1.1 m grid cells to the patch. Triangles stay tile-sized instead of spanning the apron.
## Edge blends create interleaved worn-grass and gravel tongues without overlays or new ground heights.
static func _grid_fill(k: MeshKit, poly: PackedVector2Array, lift: float, a: Color, b: Color, seed: int,
		edge_poly: PackedVector2Array, edge_width: float, edge_accent: Color, edge_strength: float,
		accent_outside_only: bool, aggregates: bool, feather_to_field := false) -> void:
	if poly.size() < 3:
		return
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p: Vector2 in poly:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var start_x := int(floor(min_x / PATCH_TILE_SIZE_M)) - 1
	var end_x := int(ceil(max_x / PATCH_TILE_SIZE_M)) + 1
	var start_z := int(floor(min_z / PATCH_TILE_SIZE_M)) - 1
	var end_z := int(ceil(max_z / PATCH_TILE_SIZE_M)) + 1
	for gx in range(start_x, end_x):
		for gz in range(start_z, end_z):
			var tile := PackedVector2Array([
				_grid_point(gx, gz, seed), _grid_point(gx + 1, gz, seed),
				_grid_point(gx + 1, gz + 1, seed), _grid_point(gx, gz + 1, seed),
			])
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(tile, poly):
				if aggregates and Palette.hash01(gx, gz, seed + 2081) < PATCH_AGGREGATE_RATE:
					_fill_aggregate_tile(k, clipped, lift, a, b, seed + gx * 67 + gz * 131, edge_poly, edge_width, edge_accent, edge_strength)
				else:
					_emit_clipped_polygon(k, clipped, lift, a, b, seed, edge_poly, edge_width, edge_accent, edge_strength, accent_outside_only, feather_to_field)


static func _fill_color(p: Vector2, a: Color, b: Color, seed: int, edge_poly: PackedVector2Array,
		edge_width: float, edge_accent: Color, edge_strength: float, accent_outside_only: bool, feather_to_field := false) -> Color:
	var x_cell := int(floor(p.x * 1.8))
	var z_cell := int(floor(p.y * 1.8))
	var tone := Palette.hash01(x_cell, z_cell, seed)
	var result := a.lerp(b, 0.22 + tone * 0.52)
	if edge_width <= 0.0 or edge_poly.size() < 3:
		return result
	var d := _edge_distance(p, edge_poly)
	if accent_outside_only and Geometry2D.is_point_in_polygon(p, edge_poly):
		return result
	if feather_to_field:
		# An irregular ramp avoids a continuous green outline while matching the field at the outer edge.
		var ramp_noise := Palette.hash01(x_cell, z_cell, seed + 619)
		var ramp := clampf(d / edge_width + (ramp_noise - 0.5) * 0.3, 0.0, 1.0)
		ramp = ramp * ramp * (3.0 - 2.0 * ramp)
		var field_shade := 0.86 + Palette.hash01(x_cell, z_cell, seed + 631) * 0.28
		return result.lerp(PATCH_FIELD_GRASS_COLOR * field_shade, ramp)
	if d >= edge_width:
		return result
	var speckle := clampf((Palette.hash01(x_cell, z_cell, seed + 173) - 0.48) / 0.52, 0.0, 1.0)
	var blend := (1.0 - d / edge_width) * edge_strength * speckle
	return result.lerp(edge_accent, blend)


static func _grid_point(x: int, z: int, seed: int) -> Vector2:
	var jx := (Palette.hash01(x, z, seed + 401) - 0.5) * PATCH_TILE_JITTER_M * 2.0
	var jz := (Palette.hash01(x, z, seed + 977) - 0.5) * PATCH_TILE_JITTER_M * 2.0
	return Vector2(x * PATCH_TILE_SIZE_M + jx, z * PATCH_TILE_SIZE_M + jz)


## Replace a sparse subset of large gravel cells with 36 cm clipped color tiles for fine, non-floating aggregate.
static func _fill_aggregate_tile(k: MeshKit, poly: PackedVector2Array, lift: float, a: Color, b: Color, seed: int,
		edge_poly: PackedVector2Array, edge_width: float, edge_accent: Color, edge_strength: float) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var centre := Vector2.ZERO
	for p: Vector2 in poly:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
		centre += p
	centre /= maxi(1, poly.size())
	var start_x := int(floor(min_x / PATCH_AGGREGATE_TILE_M)) - 1
	var end_x := int(ceil(max_x / PATCH_AGGREGATE_TILE_M)) + 1
	var start_z := int(floor(min_z / PATCH_AGGREGATE_TILE_M)) - 1
	var end_z := int(ceil(max_z / PATCH_AGGREGATE_TILE_M)) + 1
	for gx in range(start_x, end_x):
		for gz in range(start_z, end_z):
			var tile := PackedVector2Array([
				_aggregate_grid_point(gx, gz, seed), _aggregate_grid_point(gx + 1, gz, seed),
				_aggregate_grid_point(gx + 1, gz + 1, seed), _aggregate_grid_point(gx, gz + 1, seed),
			])
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(tile, poly):
				var tone := Palette.hash01(gx, gz, seed + 503)
				var col := _fill_color(centre, a, b, seed, edge_poly, edge_width, edge_accent, edge_strength, false)
				if tone < 0.18:
					col = col.lerp(a.lerp(b, 0.88), 0.68)
				elif tone > 0.91:
					col = col.lerp(a.lightened(0.08), 0.42)
				_emit_solid_polygon(k, clipped, lift, col)


static func _aggregate_grid_point(x: int, z: int, seed: int) -> Vector2:
	var jitter := 0.055
	var jx := (Palette.hash01(x, z, seed + 401) - 0.5) * jitter * 2.0
	var jz := (Palette.hash01(x, z, seed + 977) - 0.5) * jitter * 2.0
	return Vector2(x * PATCH_AGGREGATE_TILE_M + jx, z * PATCH_AGGREGATE_TILE_M + jz)


static func _emit_solid_polygon(k: MeshKit, poly: PackedVector2Array, lift: float, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var p0 := poly[idx[t]]
		var p1 := poly[idx[t + 1]]
		var p2 := poly[idx[t + 2]]
		_emit_fill_triangle(k, p0, p1, p2, col, col, col, lift)


static func _emit_clipped_polygon(k: MeshKit, poly: PackedVector2Array, lift: float, a: Color, b: Color, seed: int,
		edge_poly: PackedVector2Array, edge_width: float, edge_accent: Color, edge_strength: float, accent_outside_only: bool,
		feather_to_field := false) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var p0 := poly[idx[t]]
		var p1 := poly[idx[t + 1]]
		var p2 := poly[idx[t + 2]]
		var c0 := _fill_color(p0, a, b, seed, edge_poly, edge_width, edge_accent, edge_strength, accent_outside_only, feather_to_field)
		var c1 := _fill_color(p1, a, b, seed, edge_poly, edge_width, edge_accent, edge_strength, accent_outside_only, feather_to_field)
		var c2 := _fill_color(p2, a, b, seed, edge_poly, edge_width, edge_accent, edge_strength, accent_outside_only, feather_to_field)
		_emit_fill_triangle(k, p0, p1, p2, c0, c1, c2, lift)


static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var edge := poly[(i + 1) % poly.size()] - a
		var t := clampf((p - a).dot(edge) / maxf(edge.length_squared(), 1e-8), 0.0, 1.0)
		best = minf(best, p.distance_to(a + edge * t))
	return best


static func _emit_fill_triangle(k: MeshKit, a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color, lift: float) -> void:
	var pa := Vector3(a.x, lift, a.y)
	var pb := Vector3(b.x, lift, b.y)
	var pc := Vector3(c.x, lift, c.y)
	if (pb - pa).cross(pc - pa).y > 0.0:
		_tri_colored(k, pa, pb, pc, ca, cb, cc)
	else:
		_tri_colored(k, pa, pc, pb, ca, cc, cb)


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
	if mode.begins_with("aircraft_"):
		_aircraft_shadow(k, t, size, mode, sun)
		return
	if mode == "person":
		# A bounded contact patch on the real support plane, including veranda slabs.
		var center := Vector2(t.origin.x, t.origin.z)
		var lift := t.origin.y + 0.004 if t.origin.y > 0.0 else LIFT_SHADOW
		for step in 12:
			var a := TAU * float(step) / 12.0
			var b := TAU * float(step + 1) / 12.0
			var da := t.basis * Vector3(cos(a) * size.x * 0.62, 0.0, sin(a) * size.z * 0.66)
			var db := t.basis * Vector3(cos(b) * size.x * 0.62, 0.0, sin(b) * size.z * 0.66)
			_emit_fill_triangle(k, center, center + Vector2(da.x, da.z), center + Vector2(db.x, db.z),
				Color(0, 0, 0, 0.65), Color(0, 0, 0, 0), Color(0, 0, 0, 0), lift)
		return
	if mode == "vehicle":
		# Estimated tire patches stay in the existing scene-local shadow batch.
		for side: float in [-1.0, 1.0]:
			for axle: float in [-1.0, 1.0]:
				var center3 := t * Vector3(side * size.x * 0.37, 0.0, axle * size.z * 0.31)
				var center2 := Vector2(center3.x, center3.z)
				for step in 8:
					var a := TAU * float(step) / 8.0
					var b := TAU * float(step + 1) / 8.0
					var da: Vector3 = t.basis * Vector3(cos(a) * 0.20, 0.0, sin(a) * 0.29)
					var db: Vector3 = t.basis * Vector3(cos(b) * 0.20, 0.0, sin(b) * 0.29)
					_shadow_tri(k, center2, center2 + Vector2(da.x, da.z), center2 + Vector2(db.x, db.z),
						Color(0, 0, 0, 0.68), Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	var cast := shadow_cast(sun)
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


## Compact, feathered planform shadow on the actual grass/slab receiver.
## Retained by Scenery's existing lighting transaction; no per-frame process or shadow viewport.
static func _aircraft_shadow(k: MeshKit, t: Transform3D, size: Vector3, mode: String, sun: Vector3) -> void:
	var bench := mode.ends_with("_bench")
	mode = mode.trim_suffix("_bench")
	var half_span := size.x * 0.5
	var half_length := size.z * 0.5
	var wing_front := -0.18 if mode == "aircraft_jet" else -0.28
	var wing_tip := 0.10 if mode == "aircraft_jet" else -0.22
	var wing_back := 0.27 if mode == "aircraft_jet" else 0.03
	var outline := PackedVector2Array([
		Vector2(0, -1), Vector2(0.10, -0.72), Vector2(0.12, wing_front),
		Vector2(1, wing_tip), Vector2(1, wing_back), Vector2(0.10, 0.30),
		Vector2(0.07, 0.65), Vector2(0.38, 0.77), Vector2(0.38, 0.90),
		Vector2(0.035, 0.89), Vector2(0, 1), Vector2(-0.035, 0.89),
		Vector2(-0.38, 0.90), Vector2(-0.38, 0.77), Vector2(-0.07, 0.65),
		Vector2(-0.10, 0.30), Vector2(-1, wing_back), Vector2(-1, wing_tip),
		Vector2(-0.12, wing_front), Vector2(-0.10, -0.72)])
	if mode == "aircraft_service":
		outline = PackedVector2Array([Vector2(0, -1), Vector2(0.22, -0.7), Vector2(0.15, 0.6),
			Vector2(1, 0.8), Vector2(1, 0.95), Vector2(-1, 0.95), Vector2(-1, 0.8),
			Vector2(-0.15, 0.6), Vector2(-0.22, -0.7)])
	var cast := shadow_cast(sun) * size.y * 0.35
	var points := PackedVector2Array()
	var center := Vector2.ZERO
	for p: Vector2 in outline:
		var world := t * Vector3(p.x * half_span, 0, p.y * half_length)
		var point := Vector2(world.x, world.z) + cast
		points.append(point)
		center += point
	if bench:
		# Worktables are aligned east/west; clip their receiver so wing shadows never float beyond the edge.
		var receiver := PackedVector2Array([
			Vector2(t.origin.x - 1.2, t.origin.z - 0.4), Vector2(t.origin.x + 1.2, t.origin.z - 0.4),
			Vector2(t.origin.x + 1.2, t.origin.z + 0.4), Vector2(t.origin.x - 1.2, t.origin.z + 0.4)])
		var clipped := Geometry2D.intersect_polygons(points, receiver)
		if clipped.is_empty():
			return
		points = clipped[0]
		center = Vector2.ZERO
		for point: Vector2 in points:
			center += point
	center /= float(points.size())
	var lift := t.origin.y + 0.004
	var core := Color(0, 0, 0, 0.32)
	var edge := Color(0, 0, 0, 0)
	var indices := Geometry2D.triangulate_polygon(points)
	for i in range(0, indices.size(), 3):
		_emit_fill_triangle(k, points[indices[i]], points[indices[i + 1]], points[indices[i + 2]],
			core, core, core, lift)
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var ao := a + (a - center).normalized() * 0.055
		var bo := b + (b - center).normalized() * 0.055
		if bench:
			var receiver_min := Vector2(t.origin.x - 1.2, t.origin.z - 0.4)
			var receiver_max := Vector2(t.origin.x + 1.2, t.origin.z + 0.4)
			ao = ao.clamp(receiver_min, receiver_max)
			bo = bo.clamp(receiver_min, receiver_max)
		_emit_fill_triangle(k, a, ao, bo, core, edge, edge, lift)
		_emit_fill_triangle(k, a, bo, b, core, edge, core, lift)


## Ground-plane offset per metre of height, away from the sun. The 0.2 floor bounds low-angle shadows.
static func shadow_cast(sun: Vector3) -> Vector2:
	return Vector2(-sun.x, -sun.z) / maxf(sun.y, 0.2)


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
	for piece: Dictionary in FenceParts.build(pts, style, seed):
		k.beam(piece.a, piece.b, piece.width, piece.color)
