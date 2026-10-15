extends SceneTree

const Airplane := preload("res://render/airplane.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")

func _initialize() -> void:
	var plane: Dictionary = Airplane.build(Airplane.AVANTI_ID)
	if plane.is_empty() or not plane.get("root") is Node3D:
		printerr("UNDERWING_PROBE_ERROR: Avanti builder returned no root")
		quit(2)
		return
	var root: Node3D = plane.root
	var points: PackedVector3Array = AircraftLights.vertices(root)
	var half: float = AircraftLights.span_half(points)
	var triangles: PackedVector3Array = AircraftLights.triangles(root)
	var production: Dictionary = AircraftLights.underwing_lines(triangles, half)
	var stations: Array[Dictionary] = []
	var previous_mid := NAN
	for k in range(AircraftLights.STRIP_STATIONS - 1, -1, -1):
		var x: float = half * lerpf(AircraftLights.STRIP_FROM, AircraftLights.STRIP_TO,
			float(k) / float(AircraftLights.STRIP_STATIONS - 1))
		var segments := _segments_at(root, x)
		segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.z0) < float(b.z0))
		var surface_details := {}
		for segment: Dictionary in segments:
			var detail: Dictionary = surface_details.get(segment.source, {z_min = INF, z_max = -INF,
				y_min = INF, y_min_z = NAN, y_min_normal_y = NAN, triangle_segments = 0})
			detail.z_min = minf(float(detail.z_min), float(segment.z0))
			detail.z_max = maxf(float(detail.z_max), float(segment.z1))
			detail.triangle_segments = int(detail.triangle_segments) + 1
			if float(segment.y_min) < float(detail.y_min):
				detail.y_min = segment.y_min
				detail.y_min_z = segment.y_min_z
				detail.y_min_normal_y = segment.normal_y
			surface_details[segment.source] = detail
		var pieces: Array[Dictionary] = []
		for segment: Dictionary in segments:
			if not pieces.is_empty() and float(segment.z0) <= float(pieces[-1].z1) + 0.01:
				var last: Dictionary = pieces[-1]
				last.z1 = maxf(float(last.z1), float(segment.z1))
				if float(segment.y_min) < float(last.y_min):
					last.y_min = float(segment.y_min)
					last.lowest_sources = [segment.source]
				elif is_equal_approx(float(segment.y_min), float(last.y_min)) and not last.lowest_sources.has(segment.source):
					last.lowest_sources.append(segment.source)
				if not last.sources.has(segment.source):
					last.sources.append(segment.source)
			else:
				pieces.append({z0 = segment.z0, z1 = segment.z1, y_min = segment.y_min,
					lowest_sources = [segment.source], sources = [segment.source]})
		var best_index := -1
		for i in pieces.size():
			var extent: float = float(pieces[i].z1) - float(pieces[i].z0)
			var mid: float = 0.5 * (float(pieces[i].z0) + float(pieces[i].z1))
			if is_nan(previous_mid):
				if best_index < 0 or extent > float(pieces[best_index].z1) - float(pieces[best_index].z0):
					best_index = i
			elif extent > 0.03 and (best_index < 0 or absf(mid - previous_mid) < absf(
					0.5 * (float(pieces[best_index].z0) + float(pieces[best_index].z1)) - previous_mid)):
				best_index = i
		var selected: Dictionary = {}
		if best_index >= 0:
			selected = pieces[best_index]
			previous_mid = 0.5 * (float(selected.z0) + float(selected.z1))
		stations.append({station_index_from_root = k, x_m = x, piece_count = pieces.size(),
			pieces = pieces, selected_piece = selected, selected_lowest_y_m = selected.get("y_min", NAN),
			selected_lowest_sources = selected.get("lowest_sources", []), surface_details = surface_details})
	var output := {aircraft_id = plane.get("aircraft_id", ""),
		visual_revision = root.get_meta("visual_revision", ""), asset_sha256 = root.get_meta("asset_sha256", ""),
		root = root.name, mesh_instance_count = root.find_children("*", "MeshInstance3D", true, false).size(),
		half_span_m = half, triangle_count = triangles.size() / 3,
		production_right_line = production.right, station_diagnostics_tip_to_root = stations}
	var normal_filter_rows: Array[Dictionary] = []
	for id: String in [Airplane.STIK_ID, Airplane.EXTRA_ID, Airplane.AVANTI_ID, Airplane.P51_ID, Airplane.TIMBER_ID]:
		var candidate: Dictionary = plane if id == Airplane.AVANTI_ID else Airplane.build(id)
		if candidate.is_empty() or not candidate.get("root") is Node3D:
			normal_filter_rows.append({aircraft_id = id, build_ok = false})
			continue
		var candidate_root: Node3D = candidate.root
		var candidate_vertices: PackedVector3Array = AircraftLights.vertices(candidate_root)
		var candidate_half: float = AircraftLights.span_half(candidate_vertices)
		var all_triangles: PackedVector3Array = AircraftLights.triangles(candidate_root)
		var baseline_lines: Dictionary = AircraftLights.underwing_lines(all_triangles, candidate_half)
		var baseline_top_lines: Dictionary = AircraftLights.underwing_lines(all_triangles, candidate_half, true)
		var skin_triangles: PackedVector3Array = _triangles_with_vertical_dominant_normal(candidate_root)
		var skin_lines: Dictionary = AircraftLights.underwing_lines(skin_triangles, candidate_half)
		var skin_top_lines: Dictionary = AircraftLights.underwing_lines(skin_triangles, candidate_half, true)
		normal_filter_rows.append({aircraft_id = id, build_ok = true, asset_sha256 = candidate_root.get_meta("asset_sha256", ""),
			triangle_count = all_triangles.size() / 3, filtered_triangle_count = skin_triangles.size() / 3,
			baseline = {left = _line_metrics(baseline_lines.left), right = _line_metrics(baseline_lines.right)},
			baseline_top = {left = _line_metrics(baseline_top_lines.left), right = _line_metrics(baseline_top_lines.right)},
			filtered = {left = _line_metrics(skin_lines.left), right = _line_metrics(skin_lines.right)},
			filtered_top = {left = _line_metrics(skin_top_lines.left), right = _line_metrics(skin_top_lines.right)}})
		if id != Airplane.AVANTI_ID:
			candidate_root.free()
	output.normal_alignment_filter = "abs(normal.y) > sqrt(normal.x^2 + normal.z^2)"
	output.normal_alignment_filter_cross_catalog = normal_filter_rows
	print("UNDERWING_COMPONENT_SLICES " + JSON.stringify(output))
	root.free()
	quit(0)


func _segments_at(root: Node3D, x: float) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var transform := Transform3D.IDENTITY
		var ancestor: Node = mi
		while ancestor != null and ancestor != root:
			if ancestor is Node3D:
				transform = (ancestor as Node3D).transform * transform
			ancestor = ancestor.get_parent()
		var path := _relative_name(root, mi)
		for surface in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var label: String = "%s#%d:%s:%s" % [path, surface, mi.mesh.surface_get_name(surface),
				str(mi.get_active_material(surface).resource_name) if mi.get_active_material(surface) != null else ""]
			if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
				var idx: PackedInt32Array = indices
				for i in range(0, idx.size() - 2, 3):
					_append_segment(segments, transform * verts[idx[i]], transform * verts[idx[i + 1]],
						transform * verts[idx[i + 2]], x, label)
			else:
				for i in range(0, verts.size() - 2, 3):
					_append_segment(segments, transform * verts[i], transform * verts[i + 1],
						transform * verts[i + 2], x, label)
	return segments


func _append_segment(out: Array[Dictionary], a: Vector3, b: Vector3, c: Vector3, x: float, source: String) -> void:
	var lo: float = minf(a.x, minf(b.x, c.x))
	var hi: float = maxf(a.x, maxf(b.x, c.x))
	if hi - lo < 1e-6 or x < lo or x > hi:
		return
	var z0 := INF
	var z1 := -INF
	var y0 := INF
	var y0_z := NAN
	var y0_normal_y := NAN
	var normal_y: float = (b - a).cross(c - a).normalized().y
	for edge: Array in [[a, b], [b, c], [c, a]]:
		var p: Vector3 = edge[0]
		var q: Vector3 = edge[1]
		if (p.x - x) * (q.x - x) <= 0.0 and absf(q.x - p.x) > 1e-9:
			var hit: Vector3 = p.lerp(q, (x - p.x) / (q.x - p.x))
			z0 = minf(z0, hit.z)
			z1 = maxf(z1, hit.z)
			if hit.y < y0:
				y0 = hit.y
				y0_z = hit.z
				y0_normal_y = normal_y
	if z0 < INF:
		out.append({z0 = z0, z1 = z1, y_min = y0, y_min_z = y0_z, normal_y = y0_normal_y,
			source = source})


func _relative_name(root: Node, node: Node) -> String:
	var parts: Array[String] = []
	var current: Node = node
	while current != null and current != root:
		parts.push_front(str(current.name))
		current = current.get_parent()
	return "/".join(parts)


func _triangles_with_vertical_dominant_normal(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var transform := Transform3D.IDENTITY
		var ancestor: Node = mi
		while ancestor != null and ancestor != root:
			if ancestor is Node3D:
				transform = (ancestor as Node3D).transform * transform
			ancestor = ancestor.get_parent()
		for surface in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
				var idx: PackedInt32Array = indices
				for i in range(0, idx.size() - 2, 3):
					_add_vertical_dominant_triangle(out, transform * verts[idx[i]], transform * verts[idx[i + 1]],
						transform * verts[idx[i + 2]])
			else:
				for i in range(0, verts.size() - 2, 3):
					_add_vertical_dominant_triangle(out, transform * verts[i], transform * verts[i + 1],
						transform * verts[i + 2])
	return out


func _add_vertical_dominant_triangle(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	var vertical := absf(normal.y)
	var horizontal := sqrt(normal.x * normal.x + normal.z * normal.z)
	if normal.length_squared() > 1e-18 and vertical > horizontal:
		out.append_array(PackedVector3Array([a, b, c]))


func _line_metrics(line: PackedVector3Array) -> Dictionary:
	var max_y := 0.0
	var max_z := 0.0
	for i in range(1, line.size()):
		max_y = maxf(max_y, absf(line[i].y - line[i - 1].y))
		max_z = maxf(max_z, absf(line[i].z - line[i - 1].z))
	return {count = line.size(), max_adjacent_y_m = max_y, max_adjacent_z_m = max_z, points = line}
