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
const GROUPS := ["navigation", "strobe", "landing", "orientation"]
## Existing imported RC lens material names; models can publish light_material_groups to extend/replace this map.
const MATERIAL_GROUPS := {light_red = "navigation", light_green = "navigation"}
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
const AUTHORED_ANCHORS := ["nav_left", "nav_right", "nav_tail", "strobe_left", "strobe_right", "strobe_dorsal", "strobe_ventral", "landing", "landing_right"]
const AUTHORED_STRIPS := ["strip_left", "strip_right", "strip_top_left", "strip_top_right", "strip_belly"]


## FW-RGB-04: creator-only, node-local metres. Player lighting profiles never contain these paths.
static func empty_authored_layout() -> Dictionary:
	return {"version": 1, "anchors": [], "strips": []}


static func validate_authored_layout(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not _layout_keys(raw, ["version", "anchors", "strips"]):
		return {"ok": false, "errors": PackedStringArray(["lighting layout fields are missing or unsupported"])}
	if typeof(raw.version) not in [TYPE_INT, TYPE_FLOAT] or float(raw.version) != 1.0:
		errors.append("lighting layout version is unsupported")
	if not raw.anchors is Array or raw.anchors.size() > AUTHORED_ANCHORS.size() or not raw.strips is Array or raw.strips.size() > AUTHORED_STRIPS.size():
		return {"ok": false, "errors": PackedStringArray(["lighting layout exceeds its anchor or strip limit"])}
	for group: String in ["anchors", "strips"]:
		var seen := {}
		for row: Variant in raw[group]:
			var fields := ["id", "node_path", "position_m", "gear_gated"] if group == "anchors" else ["id", "node_path", "points_m", "face", "width_m"]
			if not _layout_keys(row, fields):
				errors.append("lighting %s row fields are missing or unsupported" % group)
				continue
			var allowed: Array = AUTHORED_ANCHORS if group == "anchors" else AUTHORED_STRIPS
			if not row.id is String or row.id not in allowed or seen.has(row.id):
				errors.append("lighting %s id is unsupported or duplicated" % group)
				continue
			seen[row.id] = true
			if not _layout_path(row.node_path): errors.append("lighting host path is invalid")
			if group == "anchors":
				if not _layout_vector(row.position_m): errors.append("lighting anchor position is invalid")
				if typeof(row.gear_gated) != TYPE_BOOL or (row.gear_gated and row.id not in ["landing", "landing_right"]):
					errors.append("only landing anchors support gear gating")
			else:
				if not _layout_number(row.width_m, 0.001, 0.05): errors.append("lighting strip width must be in [0.001, 0.05] metres")
				if not _layout_vector(row.face) or not _layout_vector_unit(row.face):
					errors.append("lighting strip face must be a unit vector")
					continue
				if not row.points_m is Array or row.points_m.size() < 2 or row.points_m.size() > 32:
					errors.append("lighting strips require 2 to 32 points")
					continue
				var previous := Vector3.ZERO
				var previous_valid := false
				for point: Variant in row.points_m:
					if not _layout_vector(point):
						errors.append("lighting strip point is invalid")
						previous_valid = false
						continue
					var current := _layout_v3(point)
					if previous_valid:
						var segment := current - previous
						if segment.length() < 0.00001 or segment.normalized().cross(_layout_v3(row.face)).length() < 0.01:
							errors.append("lighting strip segment is collapsed or parallel to its face")
					previous = current
					previous_valid = true
	return {"ok": errors.is_empty(), "errors": errors}


static func _layout_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key: String in keys:
		if not value.has(key): return false
	return true


static func _layout_number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _layout_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for part: Variant in value:
		if not _layout_number(part, -5.0, 5.0): return false
	return true


static func _layout_vector_unit(value: Array) -> bool:
	var length := _layout_v3(value).length()
	return length >= 0.999 and length <= 1.001


static func _layout_v3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _layout_path(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 160: return false
	if value == ".": return true
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_]+(/[A-Za-z0-9_]+)*$")
	return pattern.search(value) != null


## Resolve per instance, after cached geometry fitting, so paths and moving poses are never cached across roots.
static func resolve_authored_layout(root: Node3D) -> Dictionary:
	var result := {"anchors": {}, "strips": {}, "warnings": PackedStringArray()}
	var raw: Variant = root.get_meta("lighting_layout", empty_authored_layout())
	var checked := validate_authored_layout(raw)
	if not checked.ok:
		result.warnings.append_array(checked.errors)
		return result
	var existing: Dictionary = root.get_meta("light_anchors", {})
	for group: String in ["anchors", "strips"]:
		for row: Dictionary in raw[group]:
			if group == "anchors" and existing.has(row.id):
				result.warnings.append("%s already belongs to the aircraft builder; keeping that anchor" % row.id)
				continue
			var host := root if row.node_path == "." else root.get_node_or_null(NodePath(row.node_path)) as Node3D
			if host == null or (host != root and not root.is_ancestor_of(host)) or host.name == "NightKit":
				result.warnings.append("%s host is missing; keeping automatic fitting" % row.id)
				continue
			var transform := _root_local(host, root)
			if not transform.is_finite() or not is_finite(transform.basis.determinant()) or absf(transform.basis.determinant()) < 0.000001:
				result.warnings.append("%s host transform is invalid; keeping automatic fitting" % row.id)
				continue
			if group == "anchors":
				var offset := _layout_v3(row.position_m)
				result.anchors[row.id] = {"position": transform * offset, "follow": NodePath(row.node_path), "follow_offset": offset, "gear_gated": row.gear_gated}
			else:
				result.strips[row.id] = row.duplicate(true)
	return result


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
	return _geometry_arrays(root, true, false).points


## The model's triangles in its root frame, three vertices each (triangle surfaces only).
static func triangles(root: Node3D) -> PackedVector3Array:
	return _geometry_arrays(root, false, true).triangles


## Collect both views from each transformed surface once. Single-view callers keep
## their original mesh/surface filters; arrays belong to this call, not the mesh.
static func _geometry_arrays(root: Node3D, collect_points := true, collect_faces := true) -> Dictionary:
	var points := PackedVector3Array()
	var faces := PackedVector3Array()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var include_points := collect_points and (mi.mesh is ArrayMesh or mi.mesh is PrimitiveMesh)
		if not include_points and not collect_faces:
			continue
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		for i in mi.mesh.get_surface_count():
			var include_faces := collect_faces and not (mi.mesh is ArrayMesh and
				(mi.mesh as ArrayMesh).surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES)
			if not include_points and not include_faces:
				continue
			var arrays: Array = mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = t * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			if include_points:
				points.append_array(verts)
			if include_faces:
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
					for k: int in idx:
						faces.append(verts[k])
				else:
					faces.append_array(verts)
	return {points = points, triangles = faces}


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


## Ribbon vertices lie on the centerline; NORMAL is across and UV.x is side.
## Authored ribbons store normalized host-local path distance in UV.y for RGB patterns.
static func strip(name: String, line: PackedVector3Array, color := STRIP_COLOR, face := Vector3.DOWN, authored_across := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distances := PackedFloat64Array()
	distances.resize(line.size())
	if authored_across:
		for i in range(1, line.size()):
			distances[i] = distances[i - 1] + line[i - 1].distance_to(line[i])
	var length := maxf(distances[-1], 0.00001) if not distances.is_empty() else 1.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var across := (b - a).cross(face if authored_across else Vector3.UP).normalized()
		var u0 := distances[i] / length
		var u1 := distances[i + 1] / length
		for corner: Array in [[a, -1.0, u0], [b, -1.0, u1], [b, 1.0, u1], [a, -1.0, u0], [b, 1.0, u1], [a, 1.0, u0]]:
			st.set_normal(across)
			st.set_uv(Vector2(corner[1], corner[2]))
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
	if authored_across:
		mi.set_meta("lighting_path_uv", true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0 # the ribbon widens with distance
	return mi


static func _fitted_or_authored_strip(root: Node3D, id: String, fallback: PackedVector3Array, face: Vector3, authored: Dictionary) -> MeshInstance3D:
	var color := TOP_STRIP_COLOR if id.begins_with("strip_top_") else STRIP_COLOR
	if not authored.has(id):
		return strip(id, fallback, color, face) if fallback.size() >= 2 else null
	var row: Dictionary = authored[id]
	var line := PackedVector3Array()
	for point: Array in row.points_m: line.append(_layout_v3(point))
	var mesh := strip(id, line, color, _layout_v3(row.face), true)
	var material := mesh.mesh.surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("width_m", float(row.width_m))
	mesh.set_meta("follow", NodePath(row.node_path))
	mesh.set_meta("follow_transform", true)
	var host := root.get_node_or_null(NodePath(row.node_path)) as Node3D
	mesh.transform = _root_local(host, root)
	return mesh


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
	if kit == null or mode not in MODES:
		return
	kit.visible = mode != "off"
	var groups: Dictionary = kit.get_meta("light_bindings", {})
	var supported: Array = kit.get_meta("supported_light_groups", GROUPS)
	for group: String in groups:
		var enabled := mode != "off" and group in supported and (mode == "all" or group in ["navigation", "strobe"])
		for light: Node3D in groups[group]:
			if is_instance_valid(light):
				light.visible = enabled and bool(light.get_meta("gate_open", true))
	kit.set_meta("mode", mode)


## Bind luminous presentation nodes (including emissive effects) once, relative to the kit or by reference.
## Unsupported groups stay dark. Reject invalid/duplicate references before changing accepted bindings.
static func bind_groups(kit: Node3D, bindings: Dictionary, supported: Array = GROUPS) -> bool:
	if kit == null or supported.any(func(group: Variant) -> bool: return group not in GROUPS):
		return false
	var resolved := {}
	var seen: Array[Node3D] = []
	for group: String in bindings:
		if group not in GROUPS or not bindings[group] is Array:
			return false
		var lights: Array[Node3D] = []
		for reference: Variant in bindings[group]:
			var light: Node3D = reference as Node3D if reference is Node3D else kit.get_node_or_null(NodePath(str(reference))) as Node3D
			if light == null or light == kit or light in seen:
				return false
			lights.append(light)
			seen.append(light)
		resolved[group] = lights
	set_mode(kit, "off")
	kit.set_meta("light_bindings", resolved)
	kit.set_meta("supported_light_groups", supported.duplicate())
	set_mode(kit, "off")
	return true


## Own only emission overrides, never the imported mesh or its shared material. Prepare before the first frame,
## even when no kit is fitted yet: an imported emissive lens must also be dark in automatic daylight/OFF.
static func prepare_emission(root: Node3D) -> Dictionary:
	if root.has_meta("aircraft_light_emission"):
		return root.get_meta("aircraft_light_emission")
	var names: Dictionary = root.get_meta("light_material_groups", MATERIAL_GROUPS)
	var private_materials := {}
	var bindings := {materials = [], mode = "", gain = -1.0, supported = root.get_meta("light_groups", GROUPS)}
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		for surface: int in (1 if node.material_override != null else node.mesh.get_surface_count()):
			var source := node.get_active_material(surface) as BaseMaterial3D
			if source == null or not source.emission_enabled or not names.has(source.resource_name):
				continue
			var group := str(names[source.resource_name])
			if group not in GROUPS:
				continue
			var id := source.get_instance_id()
			if not private_materials.has(id):
				var material := source.duplicate() as BaseMaterial3D
				private_materials[id] = material
				bindings.materials.append({material = material, group = group, energy = source.emission_energy_multiplier})
			if node.material_override != null:
				node.material_override = private_materials[id]
			else:
				node.set_surface_override_material(surface, private_materials[id])
	root.set_meta("aircraft_light_emission", bindings)
	return bindings


static func set_emission_mode(bindings: Dictionary, mode: String, gain: float = 1.0) -> void:
	if mode not in MODES or (bindings.mode == mode and bindings.gain == gain):
		return
	for binding: Dictionary in bindings.materials:
		var enabled: bool = mode != "off" and binding.group in bindings.supported and (mode == "all" or binding.group in ["navigation", "strobe"])
		var material: BaseMaterial3D = binding.material
		material.emission_enabled = enabled
		material.emission_energy_multiplier = float(binding.energy) * gain if enabled else 0.0
	bindings.mode = mode
	bindings.gain = gain


## P51-V13: the anchored position of one kit light, or the bounds-derived fallback.
static func _anchor_position(anchors: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var anchor: Variant = anchors.get(key)
	return (anchor as Dictionary).position if anchor is Dictionary and (anchor as Dictionary).get("position") is Vector3 else fallback


## P51-V13: copy an anchor's follow node (path from the model root) and gear gate onto a kit light. The offset is in the
## followed node's frame so the light rides a moving part (a rudder, a lowering lamp).
static func _anchored(light: Node3D, anchors: Dictionary, key: String) -> Node3D:
	var anchor: Variant = anchors.get(key)
	if not anchor is Dictionary:
		return light
	if (anchor as Dictionary).has("follow"):
		light.set_meta("follow", NodePath(str(anchor.follow)))
		light.set_meta("follow_offset", Vector3(anchor.get("follow_offset", Vector3.ZERO)))
	if bool((anchor as Dictionary).get("gear_gated", false)):
		light.set_meta("gear_gated", true)
	return light


## P51-V13: per presented frame, move following lights onto their parts and open gear-gated lamps only with the gear
## down and locked (extension 1). Rendering only; kits without anchored lights are untouched.
static func update_dynamic(kit: Node3D, root: Node3D, gear_extension: float) -> void:
	if kit == null or not is_instance_valid(kit) or root == null or not bool(kit.get_meta("dynamic", false)):
		return
	var regate := false
	for child in kit.get_children():
		var light := child as Node3D
		if light == null:
			continue
		if light.has_meta("follow"):
			var target := root.get_node_or_null(light.get_meta("follow")) as Node3D
			if target != null:
				if bool(light.get_meta("follow_transform", false)):
					light.transform = _root_local(target, root)
				else:
					light.position = _root_local(target, root) * Vector3(light.get_meta("follow_offset", Vector3.ZERO))
		if light.has_meta("gear_gated"):
			var open := is_finite(gear_extension) and gear_extension >= 1.0
			if bool(light.get_meta("gate_open", true)) != open:
				light.set_meta("gate_open", open)
				regate = true
	if regate:
		set_mode(kit, str(kit.get_meta("mode", "all")))


static func _root_local(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


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


## Compact model-local measurements, made before attaching any kit. No scene nodes,
## meshes, materials or full triangle buffers survive in this result.
static func prepare_layout(root: Node3D) -> Dictionary:
	var all: AABB = bounds(root).all
	var geometry := _geometry_arrays(root)
	var points: PackedVector3Array = geometry.points
	var half := span_half(points)
	if points.is_empty() or not all.is_finite() or not is_finite(half) or half <= 0.00001:
		return {"valid": false, "bounds": all}
	var tris: PackedVector3Array = geometry.triangles
	var skins := wing_skin_lines(tris, half)
	var left := tip(points, half, -1.0)
	var right := tip(points, half, 1.0)
	var landing := Vector3.ZERO
	if not (root.get_meta("light_anchors", {}) as Dictionary).has("landing"):
		var piece := wing_piece(tris, -LANDING_SPAN * half)
		landing = Vector3(0.0, (left.centre.y + right.centre.y) / 2.0, minf(left.leading_z, right.leading_z)) if piece.is_empty() else Vector3(-LANDING_SPAN * half, float(piece[2]) - 0.003, float(piece[0]) + 0.01)
	return {bounds = all, skins = skins, left = left, right = right, belly = belly_line(tris, all), landing = landing}


## Adds an independent kit. A caller may reuse measurements only for the same
## validated geometry and local pose; authored anchors and crash hosts stay local.
static func attach(root: Node3D, prepared_layout: Dictionary = {}) -> Node3D:
	var existing := root.get_node_or_null("NightKit") as Node3D
	if existing != null:
		return existing
	var kit := Node3D.new()
	kit.name = "NightKit"
	var layout := prepare_layout(root) if prepared_layout.is_empty() else prepared_layout
	kit.set_meta("geometry_layout", layout)
	if not bool(layout.get("valid", true)):
		kit.set_meta("layout_warnings", PackedStringArray(["Aircraft geometry has no usable span; lighting fitting was skipped"]))
		root.add_child(kit)
		bind_groups(kit, {}, [])
		return kit
	var all: AABB = layout.bounds
	var lines: Dictionary = layout.skins.lower
	var left: Dictionary = layout.left
	var right: Dictionary = layout.right
	# P51-V13 (optional): a model may publish "light_anchors" (model-local positions of its own lenses, an optional node to
	# follow, a gear gate for a lamp that only works with the gear down and locked); absent keeps the bounds-derived kit.
	var authored := resolve_authored_layout(root)
	kit.set_meta("layout_warnings", authored.warnings)
	var anchors: Dictionary = (root.get_meta("light_anchors", {}) as Dictionary).duplicate(true)
	anchors.merge(authored.anchors)
	kit.add_child(_anchored(sprite("nav_left", Color(1.0, 0.06, 0.04), _anchor_position(anchors, "nav_left", left.centre), NAV_SIZE_M), anchors, "nav_left"))
	kit.add_child(_anchored(sprite("nav_right", Color(0.08, 1.0, 0.25), _anchor_position(anchors, "nav_right", right.centre), NAV_SIZE_M), anchors, "nav_right"))
	kit.add_child(_anchored(sprite("nav_tail", Color(1.0, 1.0, 1.0), _anchor_position(anchors, "nav_tail", Vector3(0.0, all.position.y + all.size.y * 0.6, all.end.z + 0.01)), NAV_SIZE_M), anchors, "nav_tail"))
	kit.add_child(_anchored(sprite("strobe_left", Color(1.0, 1.0, 1.0), _anchor_position(anchors, "strobe_left", left.trailing), NAV_SIZE_M * 1.4, LED_RADIANCE, STROBE), anchors, "strobe_left"))
	kit.add_child(_anchored(sprite("strobe_right", Color(1.0, 1.0, 1.0), _anchor_position(anchors, "strobe_right", right.trailing), NAV_SIZE_M * 1.4, LED_RADIANCE, STROBE), anchors, "strobe_right"))
	# Optional authored beacon seats use the same light state and simulation clock.
	for key: String in ["strobe_dorsal", "strobe_ventral"]:
		if anchors.has(key):
			kit.add_child(_anchored(sprite(key, Color(1.0, 0.045, 0.015), _anchor_position(anchors, key, Vector3.ZERO), 0.012, LED_RADIANCE, STROBE), anchors, key))
	Exposure.register()
	var top_lines: Dictionary = layout.skins.upper
	for key: String in ["left", "right"]:
		var line: PackedVector3Array = lines[key]
		var lower_strip := _fitted_or_authored_strip(root, "strip_" + key, line, Vector3.DOWN, authored.strips)
		if lower_strip != null: kit.add_child(lower_strip)
		var top_line: PackedVector3Array = top_lines[key]
		var upper_strip := _fitted_or_authored_strip(root, "strip_top_" + key, top_line, Vector3.UP, authored.strips)
		if upper_strip != null: kit.add_child(upper_strip)
	var belly: PackedVector3Array = layout.belly
	var belly_strip := _fitted_or_authored_strip(root, "strip_belly", belly, Vector3.DOWN, authored.strips)
	if belly_strip != null: kit.add_child(belly_strip)
	var landing := SpotLight3D.new()
	landing.name = "landing_light"
	# In the left wing's leading edge, below the skin: the beam clears the propeller disc it used to light up.
	if anchors.has("landing"):
		landing.position = anchors.landing.position
	else:
		landing.position = layout.landing
	var lamp_ahead := Vector3.ZERO if anchors.has("landing") else Vector3(0, 0, -0.012) # an anchor is the lens face itself
	kit.add_child(_anchored(sprite("landing_lamp", Color("#fff4e0"), landing.position + lamp_ahead, NAV_SIZE_M), anchors, "landing"))
	_anchored(landing, anchors, "landing")
	landing.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0) # aimed a little down from the nose (−z)
	landing.light_energy = LANDING_ENERGY
	landing.spot_range = LANDING_RANGE_M
	landing.spot_angle = LANDING_ANGLE_DEG
	landing.light_color = Color("#fff4e0")
	landing.shadow_enabled = false
	kit.add_child(landing)
	if anchors.has("landing_right"):
		var companion := landing.duplicate() as SpotLight3D
		companion.name = "landing_light_right"
		companion.position = _anchor_position(anchors, "landing_right", landing.position)
		_anchored(companion, anchors, "landing_right")
		# A paired installation shares the original beam's total energy.
		landing.light_energy *= 0.5
		companion.light_energy = landing.light_energy
		kit.add_child(companion)
		kit.add_child(_anchored(sprite("landing_lamp_right", Color("#fff4e0"), companion.position, NAV_SIZE_M), anchors, "landing_right"))
	_mark_hosts(root, kit)
	if not anchors.is_empty() or not authored.strips.is_empty():
		kit.set_meta("dynamic", true) # update_dynamic() has following or gated lights to serve
	root.add_child(kit)
	var bindings := {navigation = [], strobe = [], landing = [], orientation = []}
	for child: Node3D in kit.get_children():
		var label := str(child.name)
		if anchors.has(label) and anchors[label].get("enabled", true) == false:
			child.visible = false
			continue
		var group := "navigation" if label.begins_with("nav_") else "strobe" if label.begins_with("strobe_") else "landing" if label.begins_with("landing_") else "orientation"
		bindings[group].append(child)
	bind_groups(kit, bindings, root.get_meta("light_groups", GROUPS))
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
			anchor = (item as Node3D).transform * (item as MeshInstance3D).get_aabb().get_center() # a strip: the middle of its line
		var best: Dictionary = {}
		for host: Dictionary in hosts:
			if (host.box as AABB).has_point(anchor) and (best.is_empty() or (host.box as AABB).get_volume() < (best.box as AABB).get_volume()):
				best = host
		item.set_meta("crash_no_bounds", true)
		if not best.is_empty():
			item.set_meta("crash_follow", root.get_path_to(best.node))
