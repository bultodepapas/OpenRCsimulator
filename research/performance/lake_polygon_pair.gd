## LU-25-R3: bitwise parity and paired timing of the lake polygon queries, an explicit prior
## lake_surface.gd (reference, extracted outside app/) versus the working tree (candidate).
## Research-only. See research/performance/README.md#lake-polygon-edge-walk-lu-25-r3.
extends SceneTree

const LakeLoader := preload("res://data/lake_loader.gd")
const Candidate := preload("res://physics/lake_surface.gd")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ref_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): ref_path = arg.trim_prefix("--reference=")
	var reference := GDScript.new()
	reference.source_code = FileAccess.get_file_as_string(ref_path)
	if reference.source_code.is_empty() or reference.reload() != OK:
		push_error("reference script failed to load: " + ref_path)
		quit(2)
		return
	var loaded: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not loaded.ok:
		push_error("lake load failed")
		quit(2)
		return
	var lake: Dictionary = loaded.lake
	var points := _points(lake)
	print("points=", points.size() / 2, " shoreline_vertices=", lake.shoreline_ne_m.size() / 2, " bank_vertices=", lake.bank_ne_m.size() / 2)
	var mismatches := 0
	for i: int in range(0, points.size(), 2):
		var n: float = points[i]
		var e: float = points[i + 1]
		for polygon: PackedFloat64Array in [lake.shoreline_ne_m, lake.bank_ne_m]:
			var a := var_to_bytes([reference._polygon_state(polygon, n, e), reference._polygon_boundary_distance(polygon, n, e),
				reference._contains(polygon, n, e), reference._outside_expanded_polygon_aabb(polygon, n, e, 0.025)])
			var b := var_to_bytes([Candidate._polygon_state(polygon, n, e), Candidate._polygon_boundary_distance(polygon, n, e),
				Candidate._contains(polygon, n, e), Candidate._outside_expanded_polygon_aabb(polygon, n, e, 0.025)])
			if a != b: mismatches += 1
		var ta := var_to_bytes([reference.sample_terrain_validated(lake, n, e), reference.sample_covered_terrain_validated(lake, n, e),
			reference.shore_distance_validated(lake, n, e)])
		var tb := var_to_bytes([Candidate.sample_terrain_validated(lake, n, e), Candidate.sample_covered_terrain_validated(lake, n, e),
			Candidate.shore_distance_validated(lake, n, e)])
		if ta != tb: mismatches += 1
	print("PARITY mismatches=", mismatches)
	if mismatches != 0: _failures += 1
	# Paired timing of the full terrain query over points inside the expanded bank AABB.
	var inside := PackedFloat64Array()
	for i: int in range(0, points.size(), 2):
		if not Candidate._outside_expanded_polygon_aabb(lake.bank_ne_m, points[i], points[i + 1], 0.025):
			inside.append(points[i]); inside.append(points[i + 1])
	var ref_us := PackedFloat64Array()
	var cand_us := PackedFloat64Array()
	for round: int in 12:
		for order: int in 2:
			var use_ref: bool = (round + order) % 2 == 0
			var started := Time.get_ticks_usec()
			for i: int in range(0, inside.size(), 2):
				if use_ref: reference.sample_terrain_validated(lake, inside[i], inside[i + 1])
				else: Candidate.sample_terrain_validated(lake, inside[i], inside[i + 1])
			var per_query: float = float(Time.get_ticks_usec() - started) / float(inside.size() / 2)
			if use_ref: ref_us.append(per_query)
			else: cand_us.append(per_query)
	ref_us.sort(); cand_us.sort()
	print("TIMING sample_terrain_validated queries=%d reference_median_us=%.2f candidate_median_us=%.2f ratio=%.3f" % [
		inside.size() / 2, ref_us[6], cand_us[6], cand_us[6] / ref_us[6]])
	quit(1 if _failures > 0 else 0)


func _points(lake: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var bank: PackedFloat64Array = lake.bank_ne_m
	var lo_n := INF; var hi_n := -INF; var lo_e := INF; var hi_e := -INF
	for i: int in range(0, bank.size(), 2):
		lo_n = minf(lo_n, bank[i]); hi_n = maxf(hi_n, bank[i]); lo_e = minf(lo_e, bank[i + 1]); hi_e = maxf(hi_e, bank[i + 1])
	# Regular grid over the bank box expanded by 20 m.
	for gi: int in 61:
		for gj: int in 61:
			out.append(lerpf(lo_n - 20.0, hi_n + 20.0, gi / 60.0)); out.append(lerpf(lo_e - 20.0, hi_e + 20.0, gj / 60.0))
	# Vertices, edge midpoints and points a few epsilons off each edge (boundary branches).
	for polygon: PackedFloat64Array in [lake.shoreline_ne_m, bank]:
		var count: int = polygon.size() / 2
		for k: int in count:
			var n1: float = polygon[k * 2]; var e1: float = polygon[k * 2 + 1]
			var n2: float = polygon[((k + 1) % count) * 2]; var e2: float = polygon[((k + 1) % count) * 2 + 1]
			out.append(n1); out.append(e1)
			out.append(0.5 * (n1 + n2)); out.append(0.5 * (e1 + e2))
			for offset: float in [1e-9, 5e-9, 2e-8, 0.02, 0.03]:
				out.append(0.5 * (n1 + n2) + offset); out.append(0.5 * (e1 + e2) - offset)
	# Seeded random points.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	for k: int in 3000:
		out.append(rng.randf_range(lo_n - 40.0, hi_n + 40.0)); out.append(rng.randf_range(lo_e - 40.0, hi_e + 40.0))
	return out
