## Geometric clearances between closed meshes in the built aircraft.
## A grid point counts as penetration only when it is strictly inside both
## meshes, so shared hinge faces can be distinguished from interior overlap.
extends RefCounted

const GRID_STEP_M := 0.001
const MAX_GRID_CELLS := 150000
const RAY_DIRECTION := Vector3(1.0, 0.37139067, 0.69474659)
const INSIDE_EPSILON := 0.0000001
const MINIMUM_ACCEPTED_MOVING_GAP_M := 0.00025
const CONTAINMENT_FIXTURE_SIZE_M := 0.001
const ELEVATOR_POSES_DEG := [-20.0, 0.0, 20.0]
const RUDDER_POSES_DEG := [-25.0, 0.0, 25.0]
const STRUCTURAL_UNION_PAIRS := [
	["fuselage", "stab"],
	["fuselage", "fin"],
	["stab", "fin"],
]
const OPTIONAL_STRUCTURAL_UNION_PAIRS := [
	["fuselage", "ventral_fin"],
	["fuselage", "tail_skid"],
]
const MOVING_PAIRS := [
	["fuselage", "elevator"],
	["fuselage", "rudder"],
	["stab", "elevator"],
	["stab", "rudder"],
	["elevator", "fin"],
	["elevator", "rudder"],
	["fin", "rudder"],
]
const OPTIONAL_MOVING_PAIRS := [
	["elevator", "ventral_fin"],
	["rudder", "ventral_fin"],
	["elevator", "tail_skid"],
	["rudder", "tail_skid"],
]
const AILERON_POSES_DEG := [-20.0, 0.0, 20.0]

var _airplane: Dictionary
var _root: Node3D


## Analyze the built model. `detailed` scans every overlap-grid cell and returns
## an approximate overlap volume/region for research; normal verification stops
## at the first intersecting sample in a pair. Zero surface gap alone is seam
## contact or a crossing; the inside-both result distinguishes penetration.
func run(airplane: Dictionary, detailed := false, minimum_moving_gap_m := MINIMUM_ACCEPTED_MOVING_GAP_M) -> Dictionary:
	_airplane = airplane
	if not _airplane.has("root") or not (_airplane.root is Node3D):
		return {"ok": false, "failures": ["airplane.root must be Node3D"]}
	_root = _airplane.root as Node3D
	var named_meshes := {}
	_collect_named_meshes(_root, named_meshes)
	for required_name in ["fuselage", "stab", "elevator", "fin", "rudder"]:
		if not named_meshes.has(required_name):
			return {"ok": false, "failures": ["missing required clearance mesh: %s" % required_name]}
	for hinge_name in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		if not _airplane.has("hinges") or not _airplane.hinges.has(hinge_name):
			return {"ok": false, "failures": ["missing required hinge: %s" % hinge_name]}
	var structural_pairs: Array = STRUCTURAL_UNION_PAIRS.duplicate(true)
	for pair in OPTIONAL_STRUCTURAL_UNION_PAIRS:
		if named_meshes.has(pair[1]):
			structural_pairs.append(pair)
	var moving_pairs: Array = MOVING_PAIRS.duplicate(true)
	for pair in OPTIONAL_MOVING_PAIRS:
		if named_meshes.has(pair[1]):
			moving_pairs.append(pair)
	var original_rotations := {}
	for hinge_name in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		original_rotations[hinge_name] = _airplane.hinges[hinge_name].rotation
	var solid_cache := {}
	for mesh_name in named_meshes:
		solid_cache[mesh_name] = _solid_from_mesh(named_meshes[mesh_name])
	if not _validate_inside_probe(solid_cache):
		return {"ok": false, "failures": ["point-in-mesh sanity probes failed"]}
	var containment_fixture: Dictionary = _run_containment_fixture(solid_cache["fuselage"])
	if not containment_fixture["ok"]:
		return {"ok": false, "failures": ["contained-mesh sanity fixture failed"], "containment_fixture": containment_fixture}
	var structural_union_results: Array[Dictionary] = []
	for pair in structural_pairs:
		var a_name: String = pair[0]
		var b_name: String = pair[1]
		var result: Dictionary = _pair_metrics(solid_cache[a_name], solid_cache[b_name], true, 0.0) if detailed else {"metrics_omitted_in_fast_mode": true}
		result["a"] = a_name
		result["b"] = b_name
		result["classification"] = "allowed fixed structural union; measured, not asserted clear"
		structural_union_results.append(result)
	var all_results: Array[Dictionary] = []
	var overlap_total := 0
	var failures: Array[String] = []
	for elevator_deg in ELEVATOR_POSES_DEG:
		for rudder_deg in RUDDER_POSES_DEG:
			_airplane.hinges["elevator"].rotation = Vector3(-deg_to_rad(elevator_deg), 0.0, 0.0)
			_airplane.hinges["rudder"].rotation = Vector3(0.0, deg_to_rad(rudder_deg), 0.0)
			_root.force_update_transform()
			var pose_results: Array[Dictionary] = []
			var pose_solids := {}
			for mesh_name in named_meshes:
				pose_solids[mesh_name] = _solid_from_mesh(named_meshes[mesh_name])
			for pair in moving_pairs:
				var a_name: String = pair[0]
				var b_name: String = pair[1]
				var result := _pair_metrics(pose_solids[a_name], pose_solids[b_name], detailed, minimum_moving_gap_m)
				result["a"] = a_name
				result["b"] = b_name
				result["elevator_deg"] = elevator_deg
				result["rudder_deg"] = rudder_deg
				pose_results.append(result)
				if result["overlap_samples"] > 0 or result["probe_status"] == "unresolved_surface_contact":
					overlap_total += 1
					failures.append("tail %s/%s penetrates or has unresolved surface contact at elevator=%+.0f rudder=%+.0f" % [a_name, b_name, elevator_deg, rudder_deg])
				elif result["minimum_surface_gap_m"] < minimum_moving_gap_m:
					failures.append("tail %s/%s gap %.6f m is below %.6f m at elevator=%+.0f rudder=%+.0f" % [a_name, b_name, result["minimum_surface_gap_m"], minimum_moving_gap_m, elevator_deg, rudder_deg])
			all_results.append({"elevator_deg": elevator_deg, "rudder_deg": rudder_deg, "pairs": pose_results})
	var aileron_results: Array[Dictionary] = []
	var aileron_overlap_total := 0
	for side in ["left", "right"]:
		var side_pairs: Array = []
		for mesh_name in named_meshes:
			var fixed_prefix: String = "wing_" + side + "_"
			var trailing_prefix: String = "fixed_te_" + side + "_"
			if String(mesh_name).begins_with(fixed_prefix) or String(mesh_name).begins_with(trailing_prefix):
				side_pairs.append(["aileron_" + side, String(mesh_name)])
		if side_pairs.is_empty():
			failures.append("no fixed wing panels found for aileron_%s" % side)
		for deflection_deg in AILERON_POSES_DEG:
			_airplane.hinges["aileron_" + side].rotation = Vector3(-deg_to_rad(deflection_deg), 0.0, 0.0)
			_root.force_update_transform()
			var pose_solids := {}
			for pair in side_pairs:
				for mesh_name in pair:
					if not pose_solids.has(mesh_name):
						pose_solids[mesh_name] = _solid_from_mesh(named_meshes[mesh_name])
			var pose_results: Array[Dictionary] = []
			for pair in side_pairs:
				var a_name: String = pair[0]
				var b_name: String = pair[1]
				var result := _pair_metrics(pose_solids[a_name], pose_solids[b_name], detailed, minimum_moving_gap_m)
				result["a"] = a_name
				result["b"] = b_name
				result["side"] = side
				result["aileron_deg"] = deflection_deg
				pose_results.append(result)
				if result["overlap_samples"] > 0 or result["probe_status"] == "unresolved_surface_contact":
					aileron_overlap_total += 1
					failures.append("aileron %s/%s penetrates or has unresolved surface contact at deflection=%+.0f" % [a_name, b_name, deflection_deg])
				elif result["minimum_surface_gap_m"] < minimum_moving_gap_m:
					failures.append("aileron %s/%s gap %.6f m is below %.6f m at deflection=%+.0f" % [a_name, b_name, result["minimum_surface_gap_m"], minimum_moving_gap_m, deflection_deg])
			aileron_results.append({"side": side, "aileron_deg": deflection_deg, "pairs": pose_results})
	for hinge_name in original_rotations:
		_airplane.hinges[hinge_name].rotation = original_rotations[hinge_name]
	_root.force_update_transform()
	return {
		"schema": "openrc-model-clearance-probe-v1",
		"aircraft_id": String(_root.get_meta("aircraft_id", "unknown")),
		"method": "actual transformed mesh triangles; interior overlap from inside-both regular-grid probes, unsigned minimum surface distance from triangle-pair distances",
		"grid_step_m": GRID_STEP_M,
		"approximate_detection_limit_m": 0.0018,
		"detailed": detailed,
		"minimum_accepted_moving_gap_m": minimum_moving_gap_m,
		"containment_fixture": containment_fixture,
		"elevator_poses_deg": ELEVATOR_POSES_DEG,
		"rudder_poses_deg": RUDDER_POSES_DEG,
		"aileron_poses_deg": AILERON_POSES_DEG,
		"structural_union_pairs": structural_pairs,
		"moving_clearance_pairs": moving_pairs,
		"structural_union_results": structural_union_results,
		"overlap_pair_pose_count": overlap_total,
		"results": all_results,
		"aileron_overlap_pair_pose_count": aileron_overlap_total,
		"aileron_results": aileron_results,
		"failures": failures,
		"ok": failures.is_empty(),
		"limits": [
			"Sampled overlap volume is approximate; it is not a penetration-depth estimate.",
			"A zero sample count means no overlap at this grid resolution; triangle distance still reports the nearest surfaces.",
			"The unsigned minimum surface gap is zero for both surface contact and intersecting surfaces; consult the interior probes to distinguish them.",
			"The probe reads the currently built visual triangle meshes and makes no claim about a physical aircraft.",
		]
	}


func _collect_named_meshes(node: Node, output: Dictionary) -> void:
	if node is MeshInstance3D:
		output[String(node.name)] = node as MeshInstance3D
	for child in node.get_children():
		_collect_named_meshes(child, output)


func _solid_from_mesh(mesh_node: MeshInstance3D) -> Dictionary:
	var triangles: Array[Dictionary] = []
	var points: Array[Vector3] = []
	if mesh_node.mesh == null:
		return {"triangles": triangles, "bounds": AABB()}
	for vertex in mesh_node.mesh.get_faces():
		points.append(_root.to_local(mesh_node.to_global(vertex)))
	for index in range(0, points.size(), 3):
		var triangle := PackedVector3Array([points[index], points[index + 1], points[index + 2]])
		triangles.append(_triangle_record(triangle))
	var bounds := AABB(points[0], Vector3.ZERO)
	for point_index in range(1, points.size()):
		bounds = bounds.expand(points[point_index])
	return {"triangles": triangles, "bounds": bounds}


func _validate_inside_probe(solids: Dictionary) -> bool:
	var fuselage: Dictionary = solids["fuselage"]
	var stab: Dictionary = solids["stab"]
	var body_center: Vector3 = fuselage["bounds"].get_center()
	var body_outside := body_center + Vector3(fuselage["bounds"].size.x + 0.01, 0.0, 0.0)
	var stab_center: Vector3 = stab["bounds"].get_center()
	var inside_body := _point_inside_mesh(body_center, fuselage["triangles"])
	var outside_body := _point_inside_mesh(body_outside, fuselage["triangles"])
	var inside_stab := _point_inside_mesh(stab_center, stab["triangles"])
	return inside_body and not outside_body and inside_stab


## A 1 mm closed cube wholly inside the fuselage must be detected as contained
## even though its surface has positive distance from the fuselage surface.
func _run_containment_fixture(fuselage_solid: Dictionary) -> Dictionary:
	var fuselage_bounds: AABB = fuselage_solid["bounds"]
	var fixture := MeshInstance3D.new()
	fixture.name = "clearance_containment_fixture"
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * CONTAINMENT_FIXTURE_SIZE_M
	fixture.mesh = cube
	fixture.position = fuselage_bounds.get_center()
	_root.add_child(fixture)
	_root.force_update_transform()
	var cube_solid: Dictionary = _solid_from_mesh(fixture)
	var result: Dictionary = _pair_metrics(cube_solid, fuselage_solid, false, MINIMUM_ACCEPTED_MOVING_GAP_M)
	fixture.free()
	_root.force_update_transform()
	var passed: bool = result["probe_status"] == "contained_mesh_vertex" and result["overlap_samples"] > 0
	return {
		"ok": passed,
		"fixture": "1 mm BoxMesh fully inside fuselage bounds center",
		"probe_status": result["probe_status"],
		"contained_vertices_detected": result["overlap_samples"],
		"surface_gap_m": result["minimum_surface_gap_m"],
	}


func _pair_metrics(a: Dictionary, b: Dictionary, detailed: bool, minimum_gap_m: float) -> Dictionary:
	var bounds_gap_sq := _aabb_distance_sq(a["bounds"], b["bounds"])
	var bounds_gap := sqrt(bounds_gap_sq)
	if bounds_gap > 0.0 and bounds_gap >= minimum_gap_m:
		return _clearance_result(bounds_gap, true, "aabb_separated")
	var surface_gap := sqrt(_minimum_surface_gap_sq(a["triangles"], b["triangles"]))
	if surface_gap > 1e-8:
		var contained_point: Variant = _contained_vertex(a["triangles"], b["triangles"])
		if contained_point == null:
			contained_point = _contained_vertex(b["triangles"], a["triangles"])
		if contained_point == null:
			return _clearance_result(surface_gap, false, "separated_surfaces")
		if detailed and _grid_cell_count(a["bounds"], b["bounds"]) <= MAX_GRID_CELLS:
			var contained_probe := _probe_pair(a, b, true)
			contained_probe["minimum_surface_gap_m"] = surface_gap
			contained_probe["minimum_surface_gap_is_lower_bound"] = false
			contained_probe["probe_status"] = "contained_vertex_and_volume_sampled"
			return contained_probe
		var contained_result := _clearance_result(surface_gap, false, "contained_mesh_vertex")
		contained_result["overlap_samples"] = 1
		contained_result["region_root_m"] = {"min": _vec3_array(contained_point), "max": _vec3_array(contained_point)}
		return contained_result
	var cells := _grid_cell_count(a["bounds"], b["bounds"])
	if cells == 0:
		return _clearance_result(0.0, false, "zero_volume_aabb_contact")
	if cells > MAX_GRID_CELLS:
		var crossing_point: Variant = _contained_vertex(a["triangles"], b["triangles"])
		if crossing_point == null:
			crossing_point = _contained_vertex(b["triangles"], a["triangles"])
		if crossing_point != null:
			var overlap_result := _clearance_result(0.0, false, "contained_mesh_vertex")
			overlap_result["overlap_samples"] = 1
			overlap_result["region_root_m"] = {"min": _vec3_array(crossing_point), "max": _vec3_array(crossing_point)}
			return overlap_result
		return _clearance_result(0.0, false, "unresolved_surface_contact")
	var probe := _probe_pair(a, b, detailed)
	probe["minimum_surface_gap_m"] = surface_gap
	probe["minimum_surface_gap_is_lower_bound"] = false
	if probe["overlap_samples"] > 0:
		probe["probe_status"] = "inside_both_grid"
	else:
		probe["probe_status"] = "unresolved_surface_contact"
	return probe


func _clearance_result(surface_gap_m: float, is_lower_bound: bool, status: String) -> Dictionary:
	return {
		"overlap_samples": 0,
		"sampled_volume_cm3": null,
		"region_root_m": null,
		"overlap_aabb_root_m": null,
		"minimum_surface_gap_m": surface_gap_m,
		"minimum_surface_gap_is_lower_bound": is_lower_bound,
		"probe_status": status,
	}


func _grid_cell_count(a_bounds: AABB, b_bounds: AABB) -> int:
	var lo := Vector3(
		maxf(a_bounds.position.x, b_bounds.position.x),
		maxf(a_bounds.position.y, b_bounds.position.y),
		maxf(a_bounds.position.z, b_bounds.position.z)
	)
	var hi := Vector3(
		minf(a_bounds.end.x, b_bounds.end.x),
		minf(a_bounds.end.y, b_bounds.end.y),
		minf(a_bounds.end.z, b_bounds.end.z)
	)
	if hi.x <= lo.x or hi.y <= lo.y or hi.z <= lo.z:
		return 0
	return maxi(1, int(ceil((hi.x - lo.x) / GRID_STEP_M))) * maxi(1, int(ceil((hi.y - lo.y) / GRID_STEP_M))) * maxi(1, int(ceil((hi.z - lo.z) / GRID_STEP_M)))


## If separated closed surfaces have positive distance, overlap can only be
## containment. A mesh vertex inside the other solid proves that case.
func _contained_vertex(source_triangles: Array, target_triangles: Array) -> Variant:
	for record in source_triangles:
		var vertices: PackedVector3Array = record["vertices"]
		for vertex in vertices:
			if _point_inside_mesh(vertex, target_triangles):
				return vertex
	return null


func _probe_pair(a: Dictionary, b: Dictionary, detailed: bool) -> Dictionary:
	var a_bounds: AABB = a["bounds"]
	var b_bounds: AABB = b["bounds"]
	var lo := Vector3(
		maxf(a_bounds.position.x, b_bounds.position.x),
		maxf(a_bounds.position.y, b_bounds.position.y),
		maxf(a_bounds.position.z, b_bounds.position.z)
	)
	var hi := Vector3(
		minf(a_bounds.end.x, b_bounds.end.x),
		minf(a_bounds.end.y, b_bounds.end.y),
		minf(a_bounds.end.z, b_bounds.end.z)
	)
	if hi.x <= lo.x or hi.y <= lo.y or hi.z <= lo.z:
		return {"overlap_samples": 0, "sampled_volume_cm3": 0.0 if detailed else null, "region_root_m": null, "overlap_aabb_root_m": null, "probe_status": "zero_volume_aabb_contact"}
	var nx := maxi(1, int(ceil((hi.x - lo.x) / GRID_STEP_M)))
	var ny := maxi(1, int(ceil((hi.y - lo.y) / GRID_STEP_M)))
	var nz := maxi(1, int(ceil((hi.z - lo.z) / GRID_STEP_M)))
	var step := Vector3((hi.x - lo.x) / nx, (hi.y - lo.y) / ny, (hi.z - lo.z) / nz)
	var samples := 0
	var occupied_bounds := AABB()
	var first := true
	for ix in nx:
		for iy in ny:
			for iz in nz:
				var point := lo + Vector3((ix + 0.5) * step.x, (iy + 0.5) * step.y, (iz + 0.5) * step.z)
				if not _point_inside_mesh(point, a["triangles"]):
					continue
				if not _point_inside_mesh(point, b["triangles"]):
					continue
				samples += 1
				if first:
					occupied_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					occupied_bounds = occupied_bounds.expand(point)
				if not detailed:
					return {
						"overlap_samples": 1,
						"sampled_volume_cm3": null,
						"sample_spacing_m": [step.x, step.y, step.z],
						"region_root_m": {"min": _vec3_array(point), "max": _vec3_array(point)},
						"overlap_aabb_root_m": {"min": _vec3_array(lo), "max": _vec3_array(hi)},
					}
	var volume_m3 := float(samples) * step.x * step.y * step.z
	return {
		"overlap_samples": samples,
		"sampled_volume_cm3": volume_m3 * 1000000.0 if detailed else null,
		"sample_spacing_m": [step.x, step.y, step.z],
		"region_root_m": null if first else {"min": _vec3_array(occupied_bounds.position), "max": _vec3_array(occupied_bounds.end)},
		"overlap_aabb_root_m": {"min": _vec3_array(lo), "max": _vec3_array(hi)},
		"probe_status": "inside_both_grid" if samples > 0 else "no_inside_both_grid_sample",
	}


func _point_inside_mesh(point: Vector3, triangles: Array) -> bool:
	var crossings := 0
	for triangle_record in triangles:
		var triangle: PackedVector3Array = triangle_record["vertices"]
		var a: Vector3 = triangle[0]
		var edge_1 := triangle[1] - a
		var edge_2 := triangle[2] - a
		var pvec := RAY_DIRECTION.cross(edge_2)
		var determinant := edge_1.dot(pvec)
		if absf(determinant) <= 1e-12:
			continue
		var inverse_determinant := 1.0 / determinant
		var tvec := point - a
		var u := tvec.dot(pvec) * inverse_determinant
		if u <= INSIDE_EPSILON or u >= 1.0 - INSIDE_EPSILON:
			continue
		var qvec := tvec.cross(edge_1)
		var v := RAY_DIRECTION.dot(qvec) * inverse_determinant
		if v <= INSIDE_EPSILON or u + v >= 1.0 - INSIDE_EPSILON:
			continue
		var distance := edge_2.dot(qvec) * inverse_determinant
		if distance > 1e-7:
			crossings += 1
	return (crossings % 2) == 1


func _triangle_record(vertices: PackedVector3Array) -> Dictionary:
	var lo := Vector3(
		minf(vertices[0].x, minf(vertices[1].x, vertices[2].x)),
		minf(vertices[0].y, minf(vertices[1].y, vertices[2].y)),
		minf(vertices[0].z, minf(vertices[1].z, vertices[2].z))
	)
	var hi := Vector3(
		maxf(vertices[0].x, maxf(vertices[1].x, vertices[2].x)),
		maxf(vertices[0].y, maxf(vertices[1].y, vertices[2].y)),
		maxf(vertices[0].z, maxf(vertices[1].z, vertices[2].z))
	)
	return {"vertices": vertices, "lo": lo, "hi": hi}


func _minimum_surface_gap_sq(triangles_a: Array, triangles_b: Array) -> float:
	var best := INF
	for record_a in triangles_a:
		for record_b in triangles_b:
			var lower_bound_sq := _bounds_distance_sq(record_a, record_b)
			if lower_bound_sq >= best:
				continue
			var candidate_sq := _triangle_distance_sq(record_a["vertices"], record_b["vertices"])
			best = minf(best, candidate_sq)
			if best <= 1e-18:
				return 0.0
	return best


func _bounds_distance_sq(a: Dictionary, b: Dictionary) -> float:
	var gap := Vector3(
		maxf(maxf(a["lo"].x - b["hi"].x, b["lo"].x - a["hi"].x), 0.0),
		maxf(maxf(a["lo"].y - b["hi"].y, b["lo"].y - a["hi"].y), 0.0),
		maxf(maxf(a["lo"].z - b["hi"].z, b["lo"].z - a["hi"].z), 0.0)
	)
	return gap.length_squared()


func _aabb_distance_sq(a: AABB, b: AABB) -> float:
	var gap := Vector3(
		maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0),
		maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0),
		maxf(maxf(a.position.z - b.end.z, b.position.z - a.end.z), 0.0)
	)
	return gap.length_squared()


func _triangle_distance_sq(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var best := INF
	for i in 3:
		var next_i := (i + 1) % 3
		if _segment_intersects_triangle(a[i], a[next_i], b):
			return 0.0
		if _segment_intersects_triangle(b[i], b[next_i], a):
			return 0.0
		best = minf(best, _point_triangle_distance_sq(a[i], b[0], b[1], b[2]))
		best = minf(best, _point_triangle_distance_sq(b[i], a[0], a[1], a[2]))
	for i in 3:
		for j in 3:
			best = minf(best, _segment_distance_sq(a[i], a[(i + 1) % 3], b[j], b[(j + 1) % 3]))
	return best


func _segment_intersects_triangle(start: Vector3, finish: Vector3, triangle: PackedVector3Array) -> bool:
	var direction := finish - start
	var edge_1 := triangle[1] - triangle[0]
	var edge_2 := triangle[2] - triangle[0]
	var pvec := direction.cross(edge_2)
	var determinant := edge_1.dot(pvec)
	if absf(determinant) <= 1e-12:
		return false
	var inverse_determinant := 1.0 / determinant
	var tvec := start - triangle[0]
	var u := tvec.dot(pvec) * inverse_determinant
	if u < -1e-7 or u > 1.0 + 1e-7:
		return false
	var qvec := tvec.cross(edge_1)
	var v := direction.dot(qvec) * inverse_determinant
	if v < -1e-7 or u + v > 1.0 + 1e-7:
		return false
	var t := edge_2.dot(qvec) * inverse_determinant
	return t >= -1e-7 and t <= 1.0 + 1e-7


func _point_triangle_distance_sq(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return ap.length_squared()
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return bp.length_squared()
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3)
		return (point - (a + v * ab)).length_squared()
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return cp.length_squared()
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6)
		return (point - (a + w * ac)).length_squared()
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		var w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return (point - (b + w * (c - b))).length_squared()
	var denominator := 1.0 / (va + vb + vc)
	var v := vb * denominator
	var w := vc * denominator
	return (point - (a + ab * v + ac * w)).length_squared()


func _segment_distance_sq(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-18 and e <= 1e-18:
		return r.length_squared()
	if a <= 1e-18:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-18:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denominator := a * e - b * b
			if absf(denominator) > 1e-18:
				s = clampf((b * f - c * e) / denominator, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var closest_1 := p1 + d1 * s
	var closest_2 := p2 + d2 * t
	return closest_1.distance_squared_to(closest_2)


func _vec3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _pose_overlap_count(results: Array[Dictionary]) -> int:
	var result := 0
	for pair_result in results:
		if pair_result["overlap_samples"] > 0:
			result += 1
	return result
