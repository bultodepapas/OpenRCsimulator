# FIELD-WORLD-PLAN FW-35: a night-flying kit for any catalog aircraft, placed from the model's own bounds, so no
# model team file, node name or hinge changes. Model frame: +x right wing, +y up, −z nose (render/frames.gd).
# - navigation lights: red left tip, green right tip, white tail (the full-size convention RC night kits copy);
#   seeing red on the right means the airplane is coming toward you or inverted, as for full-size traffic;
# - white anti-collision strobes on both tips, double flash every second (on sim_clock);
# - a forward landing light (one SpotLight3D, no shadows) that lights the runway on approach.
# - FW-62: cyan LED strips under both wings, traced on slices of the model's own triangles along the span (35–95 % of
#   the semispan, clear of the gear and tail; the longest-chord group is the wing), so colour seen means the belly is
#   seen: upright vs inverted at a glance (RC night practice).
# - FW-35b: warm-white strips on the wing tops (seen only from above) and a cyan belly strip along the fuselage
#   (traced on the model's own triangles in its symmetry plane), so white means the top is seen and cyan the belly;
#   the landing light sits in the left wing's leading edge, clear of the propeller disc it used to light up;
#   modes ALL / NAV (navigation and strobes only) / OFF via set_mode().
# Brightness is physical in scene units (sun irradiance = 1), so the time-of-day exposure decides what shows.
extends RefCounted

const SPRITE_SHADER := preload("res://render/world/light_sprite.gdshader")
const STRIP_SHADER := preload("res://render/world/led_strip.gdshader")
const Exposure := preload("res://render/world/exposure.gd")

## LED luminance as scene-linear radiance (estimate: ~3× a sunlit white surface, ~10⁴–10⁵ cd/m²).
const LED_RADIANCE := 2.5
const NAV_SIZE_M := 0.025
## Smallest on-screen size and brightest on-screen value of a kit light (estimates, from night captures): 4 px and
## 2.5 keep red and green readable as colours at 100–200 m instead of white specks.
const NAV_MIN_PX := 4.0
const NAV_DISPLAY_CAP := 2.5
const STROBE := Vector4(1.0, 0.06, 0.16, 1.0) # 1 s period, 60 ms pulses, second pulse at 160 ms
const STRIP_COLOR := Color("#20b8ff")
const TOP_STRIP_COLOR := Color("#fff1d6")
## Belly strip stations along the fuselage, between these fractions of the model's length (clear of the propeller,
## engine and tail wheel), and the largest step from one station's belly to the next (a gear leg is a bigger jump).
const BELLY_FROM := 0.14
const BELLY_TO := 0.80
const BELLY_STATIONS := 14
const BELLY_STEP_M := 0.03
## Landing light: in the left wing's leading edge at this share of the semispan (the RC kit position).
const LANDING_SPAN := 0.36 # its 16° beam then clears a propeller disc of up to ~40 % of the span
const MODES := ["all", "nav", "off"]
## A diffuse LED strip's radiance in scene units (estimate: ~1,000–3,000 cd/m², a tenth of a bare LED).
const STRIP_RADIANCE := 0.25
const STRIP_WIDTH_M := 0.015
## Strip stations along each semispan (fractions) and the gap below the sampled underside.
const STRIP_FROM := 0.35
const STRIP_TO := 0.95
const STRIP_STATIONS := 9
const STRIP_GAP_M := 0.004
## Landing light: SpotLight3D energy ≈ irradiance × d² in scene units. ~2,000 cd (a bright LED landing light,
## estimate) gives ~5 lux at 20 m, i.e. 5·10⁻⁵ of a ~10⁵ lux sun.
const LANDING_ENERGY := 0.02
const LANDING_RANGE_M := 80.0
const LANDING_ANGLE_DEG := 16.0


## The model's bounds in its root frame, and the widest mesh's (the wing's) bounds.
static func bounds(root: Node3D) -> Dictionary:
	var all := AABB()
	var wing := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var b := t * mi.get_aabb()
		all = b if first else all.merge(b)
		if first or b.size.x > wing.size.x:
			wing = b
		first = false
	return {all = all, wing = wing}


## The model's vertices in its root frame (every MeshInstance3D surface, hinged parts included).
static func vertices(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh or mi.mesh is PrimitiveMesh):
			continue
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		for i in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(i)
			# Keep authored order while transforming the surface in native code.
			out.append_array(t * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	return out


## The model's triangles in its root frame, three vertices each (triangle surfaces only).
static func triangles(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		for i in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = t * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
				for k: int in idx:
					out.append(verts[k])
			else:
				out.append_array(verts)
	return out


## Under-wing lines {left, right}: the model's triangles are sliced by vertical planes at STRIP_STATIONS span stations
## per side. Each sliced triangle gives a chord segment; overlapping segments (within 1 cm) form one piece, so low- and
## high-poly wings behave alike. At the tip the piece with the longest chord is the wing (only the wing reaches it);
## walking inward, the substantial piece (> 3 cm) nearest the previous station's mid chord continues it, so split
## flaps, struts, gear and tail surfaces never take the strip. It runs STRIP_GAP_M below the piece's lowest point.
static func underwing_lines(tris: PackedVector3Array, half: float, top := false) -> Dictionary:
	var sections := _wing_sections(tris, half)
	return _wing_lines_from_sections(sections, top)


## Trace both skins from one set of cuts; each result owns its output lines.
static func wing_skin_lines(tris: PackedVector3Array, half: float) -> Dictionary:
	var sections := _wing_sections(tris, half)
	return {lower = _wing_lines_from_sections(sections, false), upper = _wing_lines_from_sections(sections, true)}


static func _wing_sections(tris: PackedVector3Array, half: float) -> Dictionary:
	var xs := PackedFloat64Array() # tip to root on each side
	for side: float in [-1.0, 1.0]:
		for k in range(STRIP_STATIONS - 1, -1, -1):
			xs.append(side * half * lerpf(STRIP_FROM, STRIP_TO, float(k) / float(STRIP_STATIONS - 1)))
	# Search a sorted copy, but keep output stations in their original tip-to-root
	# order. Every station retains the original triangle order, including ties.
	var station_order: Array[int] = []
	for j in xs.size():
		station_order.append(j)
	var sorted_xs := xs.duplicate()
	var searchable := is_finite(half)
	if searchable:
		station_order.sort_custom(func(u: int, v: int) -> bool: return xs[u] < xs[v])
		for j in xs.size():
			sorted_xs[j] = xs[station_order[j]]
	var segments := [] # per station: Array of [z_min, z_max, y_min, y_max]
	for x in xs:
		segments.append([])
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var face_normal := (b - a).cross(c - a)
		if not _is_vertical_dominant_face_normal(face_normal):
			continue
		var lo := minf(a.x, minf(b.x, c.x))
		var hi := maxf(a.x, maxf(b.x, c.x))
		if hi - lo < 1e-6:
			continue
		var first := 0
		var stop := xs.size()
		if searchable and is_finite(lo) and is_finite(hi):
			first = sorted_xs.bsearch(lo)
			stop = sorted_xs.bsearch(hi, false)
		for ordered_index in range(first, stop):
			var j: int = station_order[ordered_index]
			var x := xs[j]
			if x < lo or x > hi:
				continue
			var z0 := INF
			var z1 := -INF
			var y0 := INF
			var y1 := -INF
			# Preserve AB, BC, CA order without temporary edge arrays.
			for edge in 3:
				var p: Vector3 = a if edge == 0 else (b if edge == 1 else c)
				var q: Vector3 = b if edge == 0 else (c if edge == 1 else a)
				if (p.x - x) * (q.x - x) <= 0.0 and absf(q.x - p.x) > 1e-9:
					var hit := p.lerp(q, (x - p.x) / (q.x - p.x))
					z0 = minf(z0, hit.z)
					z1 = maxf(z1, hit.z)
					y0 = minf(y0, hit.y)
					y1 = maxf(y1, hit.y)
			if z0 < INF:
				segments[j].append([z0, z1, y0, y1])
	# Sort once from the original triangle order, including equal-start segments.
	for segs: Array in segments:
		segs.sort_custom(func(u: Array, v: Array) -> bool: return u[0] < v[0])
	return {xs = xs, segments = segments}


static func _wing_lines_from_sections(sections: Dictionary, top: bool) -> Dictionary:
	var xs: PackedFloat64Array = sections.xs
	var segments: Array = sections.segments
	var height_index := 3 if top else 2
	var lines := {left = PackedVector3Array(), right = PackedVector3Array()}
	var previous_mid := {left = NAN, right = NAN}
	for j in xs.size():
		var key := "left" if xs[j] < 0.0 else "right"
		var segs: Array = segments[j]
		if segs.is_empty():
			continue
		var pieces := [] # [z_min, z_max, y_min]
		for seg: Array in segs:
			if not pieces.is_empty() and seg[0] <= pieces[-1][1] + 0.01:
				pieces[-1][1] = maxf(pieces[-1][1], seg[1])
				pieces[-1][2] = maxf(pieces[-1][2], seg[height_index]) if top else minf(pieces[-1][2], seg[height_index])
			else:
				pieces.append([seg[0], seg[1], seg[height_index]])
		var best: Array = []
		for piece: Array in pieces:
			var extent: float = piece[1] - piece[0]
			var mid: float = (piece[0] + piece[1]) / 2.0
			if is_nan(previous_mid[key]):
				if best.is_empty() or extent > best[1] - best[0]:
					best = piece
			elif extent > 0.03 and (best.is_empty() or absf(mid - previous_mid[key]) < absf((best[0] + best[1]) / 2.0 - previous_mid[key])):
				best = piece
		if best.is_empty():
			continue
		previous_mid[key] = (best[0] + best[1]) / 2.0
		var line: PackedVector3Array = lines[key] # packed arrays are values: append, then store back
		line.append(Vector3(xs[j], best[2] + (STRIP_GAP_M if top else -STRIP_GAP_M), previous_mid[key]))
		lines[key] = line
	for key: String in ["left", "right"]: # back to root-to-tip order
		var reordered := PackedVector3Array()
		var line: PackedVector3Array = lines[key]
		for n in range(line.size() - 1, -1, -1):
			reordered.append(line[n])
		lines[key] = reordered
	return lines


## Keep broad upper/lower wing faces (|normal.y| > horizontal normal magnitude, i.e. under 45° from vertical).
## Side-facing fences and zero-area/non-finite triangles do not define a wing skin station.
static func _is_vertical_dominant_face_normal(normal: Vector3) -> bool:
	if not is_finite(normal.x) or not is_finite(normal.y) or not is_finite(normal.z):
		return false
	var scale := maxf(absf(normal.x), maxf(absf(normal.y), absf(normal.z)))
	if scale <= 0.0:
		return false
	var vertical := absf(normal.y) / scale
	var horizontal_x := normal.x / scale
	var horizontal_z := normal.z / scale
	return vertical * vertical > horizontal_x * horizontal_x + horizontal_z * horizontal_z


## A ribbon mesh through `line` for render/world/led_strip.gdshader (vertices on the line, NORMAL across, UV.x side).
static func strip(name: String, line: PackedVector3Array, color := STRIP_COLOR, face := Vector3.DOWN) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var across := (b - a).cross(Vector3.UP).normalized()
		for corner: Array in [[a, -1.0], [b, -1.0], [b, 1.0], [a, -1.0], [b, 1.0], [a, 1.0]]:
			st.set_normal(across)
			st.set_uv(Vector2(corner[1], 0.0))
			st.add_vertex(corner[0])
	var material := ShaderMaterial.new()
	material.shader = STRIP_SHADER
	material.set_shader_parameter("light_color", color)
	material.set_shader_parameter("face_dir", face)
	material.set_shader_parameter("radiance", STRIP_RADIANCE)
	material.set_shader_parameter("width_m", STRIP_WIDTH_M)
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0 # the ribbon widens with distance
	return mi


## FW-35b: the belly line in the symmetry plane (x = 0). Each station's plane z = const cuts the triangles into
## segments; where a segment crosses x = 0 the skin is there. Starting at the station nearest the wing (the model
## origin), the lowest crossing is the belly; walking fore and aft, the crossing nearest the previous belly height
## (within BELLY_STEP_M) continues it, so a gear leg or tail skid below the fuselage never takes the strip.
static func belly_line(tris: PackedVector3Array, all: AABB) -> PackedVector3Array:
	var zs := PackedFloat64Array()
	for k in BELLY_STATIONS:
		zs.append(all.position.z + all.size.z * lerpf(BELLY_FROM, BELLY_TO, float(k) / float(BELLY_STATIONS - 1)))
	# Binary bounds include both triangle endpoints and repeated stations. Retain
	# the scan for descending/non-finite caller bounds, where bsearch is invalid.
	var ordered := true
	for j in zs.size():
		ordered = ordered and is_finite(zs[j]) and (j == 0 or zs[j] >= zs[j - 1])
	var crossings: Array = []
	for z in zs:
		crossings.append(PackedFloat64Array())
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var lo := minf(a.z, minf(b.z, c.z))
		var hi := maxf(a.z, maxf(b.z, c.z))
		if hi - lo < 1e-9:
			continue
		var first := 0
		var stop := zs.size()
		if ordered and is_finite(lo) and is_finite(hi):
			first = zs.bsearch(lo)
			stop = zs.bsearch(hi, false)
		for j in range(first, stop):
			var z := zs[j]
			if z < lo or z > hi:
				continue
			var hits: Array[Vector3] = []
			# Preserve AB, BC, CA order without temporary edge arrays.
			for edge in 3:
				var p: Vector3 = a if edge == 0 else (b if edge == 1 else c)
				var q: Vector3 = b if edge == 0 else (c if edge == 1 else a)
				if (p.z - z) * (q.z - z) <= 0.0 and absf(q.z - p.z) > 1e-9:
					hits.append(p.lerp(q, (z - p.z) / (q.z - p.z)))
			if hits.size() >= 2 and hits[0].x * hits[1].x <= 0.0 and absf(hits[1].x - hits[0].x) > 1e-9:
				var y := lerpf(hits[0].y, hits[1].y, -hits[0].x / (hits[1].x - hits[0].x))
				var list: PackedFloat64Array = crossings[j]
				list.append(y)
				crossings[j] = list
	var start := 0
	for j in zs.size():
		if absf(zs[j]) < absf(zs[start]):
			start = j
	var ys := PackedFloat64Array()
	ys.resize(zs.size())
	ys.fill(NAN)
	var seed_list: PackedFloat64Array = crossings[start]
	if seed_list.is_empty():
		return PackedVector3Array()
	ys[start] = Array(seed_list).min()
	for direction in [-1, 1]:
		var j: int = start + direction
		var previous: float = ys[start]
		while j >= 0 and j < zs.size():
			var best := NAN
			for y: float in crossings[j]:
				if absf(y - previous) <= BELLY_STEP_M and (is_nan(best) or absf(y - previous) < absf(best - previous)):
					best = y
			if is_nan(best):
				break
			ys[j] = best
			previous = best
			j += direction
	var line := PackedVector3Array()
	for j in zs.size():
		if not is_nan(ys[j]):
			line.append(Vector3(0.0, ys[j] - STRIP_GAP_M, zs[j]))
	return line


## The wing's chord piece at span station x: [leading z, trailing z, lowest y] (longest chord through x), or [].
static func wing_piece(tris: PackedVector3Array, x: float) -> Array:
	var segs: Array = []
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		if x < minf(a.x, minf(b.x, c.x)) or x > maxf(a.x, maxf(b.x, c.x)):
			continue
		var z0 := INF
		var z1 := -INF
		var y0 := INF
		# Preserve AB, BC, CA order without temporary edge arrays.
		for edge in 3:
			var p: Vector3 = a if edge == 0 else (b if edge == 1 else c)
			var q: Vector3 = b if edge == 0 else (c if edge == 1 else a)
			if (p.x - x) * (q.x - x) <= 0.0 and absf(q.x - p.x) > 1e-9:
				var hit := p.lerp(q, (x - p.x) / (q.x - p.x))
				z0 = minf(z0, hit.z)
				z1 = maxf(z1, hit.z)
				y0 = minf(y0, hit.y)
		if z0 < INF:
			segs.append([z0, z1, y0])
	segs.sort_custom(func(u: Array, v: Array) -> bool: return u[0] < v[0])
	var pieces: Array = []
	for seg: Array in segs:
		if not pieces.is_empty() and seg[0] <= pieces[-1][1] + 0.01:
			pieces[-1][1] = maxf(pieces[-1][1], seg[1])
			pieces[-1][2] = minf(pieces[-1][2], seg[2])
		else:
			pieces.append(seg.duplicate())
	var best: Array = []
	for piece: Array in pieces:
		if best.is_empty() or piece[1] - piece[0] > best[1] - best[0]:
			best = piece
	return best


## FW-35b: ALL shows every light, NAV only the navigation lights and strobes, OFF none.
static func set_mode(kit: Node3D, mode: String) -> void:
	if kit == null:
		return
	kit.visible = mode != "off"
	for child in kit.get_children():
		var name := String(child.name)
		var nav := name.begins_with("nav_") or name.begins_with("strobe_")
		(child as Node3D).visible = mode == "all" or nav
	kit.set_meta("mode", mode)


## Half the wingspan from the model's vertices (the widest single mesh is not the wing on every model: the Extra's
## is its stabilizer, the P-51's wing is split by side).
static func span_half(points: PackedVector3Array) -> float:
	var half := 0.0
	for v: Vector3 in points:
		half = maxf(half, absf(v.x))
	return half


## The wing tip on one side (+1 right, −1 left): the outermost 4 % of the span; returns {centre, trailing} where
## centre is the middle of those vertices' height and chord and trailing sits at 75 % of the chord toward the tail.
static func tip(points: PackedVector3Array, half: float, side: float) -> Dictionary:
	var y_min := INF
	var y_max := -INF
	var z_min := INF
	var z_max := -INF
	for v: Vector3 in points:
		if side * v.x >= half * 0.96:
			y_min = minf(y_min, v.y)
			y_max = maxf(y_max, v.y)
			z_min = minf(z_min, v.z)
			z_max = maxf(z_max, v.z)
	var y := (y_min + y_max) / 2.0
	var x := side * (half + 0.01)
	return {centre = Vector3(x, y, (z_min + z_max) / 2.0), trailing = Vector3(x, y, lerpf(z_min, z_max, 0.75)),
		leading_z = z_min}


## A self-luminous point (render/world/light_sprite.gdshader) with the current exposure.
static func sprite(name: String, color: Color, position: Vector3, size_m: float, radiance := LED_RADIANCE,
		flash := Vector4(1.0, 0.0, 0.0, 0.0), min_px := NAV_MIN_PX, display_cap := NAV_DISPLAY_CAP) -> MeshInstance3D:
	Exposure.register() # before the shader compiles
	var material := ShaderMaterial.new()
	material.shader = SPRITE_SHADER
	material.set_shader_parameter("light_color", color)
	material.set_shader_parameter("radiance", radiance)
	material.set_shader_parameter("size_m", size_m)
	material.set_shader_parameter("flash", flash)
	material.set_shader_parameter("min_px", min_px)
	material.set_shader_parameter("display_cap", display_cap)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = quad
	mi.position = position
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0 # the billboard grows with distance
	return mi


## Adds the kit under the airplane's root (a child named "NightKit") and returns it.
static func attach(root: Node3D) -> Node3D:
	var kit := Node3D.new()
	kit.name = "NightKit"
	var all: AABB = bounds(root).all
	# Tips, strips and span from the model's own vertices (traced before any kit node exists).
	var points := vertices(root)
	var half := span_half(points)
	# Both skins use the same posed geometry, before the kit is attached.
	var tris := triangles(root)
	var skins := wing_skin_lines(tris, half)
	var lines: Dictionary = skins.lower
	var left := tip(points, half, -1.0)
	var right := tip(points, half, 1.0)
	kit.add_child(sprite("nav_left", Color(1.0, 0.06, 0.04), left.centre, NAV_SIZE_M))
	kit.add_child(sprite("nav_right", Color(0.08, 1.0, 0.25), right.centre, NAV_SIZE_M))
	kit.add_child(sprite("nav_tail", Color(1.0, 1.0, 1.0), Vector3(0.0, all.position.y + all.size.y * 0.6, all.end.z + 0.01), NAV_SIZE_M))
	kit.add_child(sprite("strobe_left", Color(1.0, 1.0, 1.0), left.trailing, NAV_SIZE_M * 1.4, LED_RADIANCE, STROBE))
	kit.add_child(sprite("strobe_right", Color(1.0, 1.0, 1.0), right.trailing, NAV_SIZE_M * 1.4, LED_RADIANCE, STROBE))
	Exposure.register()
	var top_lines: Dictionary = skins.upper
	for key: String in ["left", "right"]:
		var line: PackedVector3Array = lines[key]
		if line.size() >= 2:
			kit.add_child(strip("strip_" + key, line))
		var top_line: PackedVector3Array = top_lines[key]
		if top_line.size() >= 2:
			kit.add_child(strip("strip_top_" + key, top_line, TOP_STRIP_COLOR, Vector3.UP))
	var belly := belly_line(tris, all)
	if belly.size() >= 2:
		kit.add_child(strip("strip_belly", belly))
	var landing := SpotLight3D.new()
	landing.name = "landing_light"
	# In the left wing's leading edge, below the skin: the beam clears the propeller disc it used to light up.
	var piece := wing_piece(tris, -LANDING_SPAN * half)
	if piece.is_empty():
		landing.position = Vector3(0.0, (left.centre.y + right.centre.y) / 2.0, minf(left.leading_z, right.leading_z))
	else:
		landing.position = Vector3(-LANDING_SPAN * half, float(piece[2]) - 0.003, float(piece[0]) + 0.01)
	kit.add_child(sprite("landing_lamp", Color("#fff4e0"), landing.position + Vector3(0, 0, -0.012), NAV_SIZE_M))
	landing.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0) # aimed a little down from the nose (−z)
	landing.light_energy = LANDING_ENERGY
	landing.spot_range = LANDING_RANGE_M
	landing.spot_angle = LANDING_ANGLE_DEG
	landing.light_color = Color("#fff4e0")
	landing.shadow_enabled = false
	kit.add_child(landing)
	_mark_hosts(root, kit)
	root.add_child(kit)
	set_mode(kit, "all")
	return kit


## FW-35b: each light names the model part it is mounted on (the smallest mesh whose box, grown 2 cm, holds it), so a
## crash wreck can carry it on that part (render/crash/wreck.gd follows meta "crash_follow"); light quads never count
## in the wreck's collision boxes ("crash_no_bounds"). The flying kit keeps its own structure.
static func _mark_hosts(root: Node3D, kit: Node3D) -> void:
	var hosts: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		hosts.append({node = mi, box = (t * mi.get_aabb()).grow(0.02)})
	for item in kit.get_children():
		var anchor: Vector3 = (item as Node3D).position
		if item is MeshInstance3D and not ((item as MeshInstance3D).mesh is QuadMesh):
			anchor = (item as MeshInstance3D).get_aabb().get_center() # a strip: the middle of its line
		var best: Dictionary = {}
		for host: Dictionary in hosts:
			if (host.box as AABB).has_point(anchor) and (best.is_empty() or (host.box as AABB).get_volume() < (best.box as AABB).get_volume()):
				best = host
		item.set_meta("crash_no_bounds", true)
		if not best.is_empty():
			item.set_meta("crash_follow", root.get_path_to(best.node))
