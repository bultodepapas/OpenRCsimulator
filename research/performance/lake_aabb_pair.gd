## LU-25-R7: bitwise parity of the memoized lake bank bounds, an explicit prior lake_surface.gd (reference,
## extracted outside app/) versus the working tree (candidate), over a seeded interleaving of polygons that
## exercises the memo: equal and ±0-different copies, NaN, empty, in-place edits of one array, and points exactly
## on bound ± margin. Research-only. See research/performance/README.md#lake-bank-bounds-memo-lu-25-r7.
extends SceneTree

const LakeLoader := preload("res://data/lake_loader.gd")
const Candidate := preload("res://physics/lake_surface.gd")


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
	var bank: PackedFloat64Array = lake.bank_ne_m
	var zero_plus := bank.duplicate()
	zero_plus[0] = 0.0
	zero_plus[3] = 0.0
	var zero_minus := zero_plus.duplicate()
	zero_minus[0] = -0.0
	zero_minus[3] = -0.0
	var with_nan := bank.duplicate()
	with_nan[5] = NAN
	var shifted := bank.duplicate()
	for i: int in shifted.size(): shifted[i] += 37.5
	var polygons: Array[PackedFloat64Array] = [bank, lake.shoreline_ne_m, zero_plus, zero_minus, with_nan,
		PackedFloat64Array(), PackedFloat64Array([3.0, -4.0]), shifted, bank.duplicate()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	var mismatches := 0
	var calls := 0
	var edited := bank.duplicate() # one array object edited in place between calls
	for step: int in 60000:
		var polygon: PackedFloat64Array
		if step % 97 == 0:
			edited[rng.randi_range(0, edited.size() - 1)] += rng.randf_range(-30.0, 30.0)
		polygon = edited if step % 5 == 0 else polygons[rng.randi_range(0, polygons.size() - 1)]
		var points := _points(rng, polygon)
		for i: int in range(0, points.size(), 2):
			var a: bool = reference._outside_expanded_polygon_aabb(polygon, points[i], points[i + 1], 0.025)
			var b: bool = Candidate._outside_expanded_polygon_aabb(polygon, points[i], points[i + 1], 0.025)
			calls += 1
			if a != b:
				mismatches += 1
				if mismatches <= 5: printerr("MISMATCH step=%d n=%s e=%s ref=%s cand=%s" % [step, points[i], points[i + 1], a, b])
	# The two production callers, through the validated lake, interleaved with the other polygons above.
	for step: int in 4000:
		Candidate._outside_expanded_polygon_aabb(polygons[step % polygons.size()], 0.0, 0.0, 0.025)
		var n: float = rng.randf_range(-250.0, 250.0)
		var e: float = rng.randf_range(-250.0, 250.0)
		var ta := var_to_bytes([reference.sample_covered_terrain_validated(lake, n, e), reference.shore_distance_validated(lake, n, e)])
		var tb := var_to_bytes([Candidate.sample_covered_terrain_validated(lake, n, e), Candidate.shore_distance_validated(lake, n, e)])
		calls += 1
		if ta != tb: mismatches += 1
	print("LAKE_AABB_PARITY calls=%d mismatches=%d" % [calls, mismatches])
	quit(1 if mismatches else 0)


## Random points around the polygon's bounds, plus every bound ± margin exactly and its neighbouring doubles.
func _points(rng: RandomNumberGenerator, polygon: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k: int in 4:
		out.append_array([rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0)])
	out.append_array([NAN, 0.0, 0.0, INF, -INF, 1.0, 0.0, -0.0])
	if polygon.size() >= 2:
		var bounds: PackedFloat64Array = Candidate._polygon_aabb(polygon)
		for edge: float in [bounds[0] - 0.025, bounds[1] + 0.025]:
			for x: float in [edge, _next(edge, -INF), _next(edge, INF)]:
				out.append_array([x, (bounds[2] + bounds[3]) * 0.5])
		for edge: float in [bounds[2] - 0.025, bounds[3] + 0.025]:
			for x: float in [edge, _next(edge, -INF), _next(edge, INF)]:
				out.append_array([(bounds[0] + bounds[1]) * 0.5, x])
	return out


func _next(value: float, toward: float) -> float:
	if not is_finite(value) or value == toward:
		return value
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var bits: int = bytes.decode_s64(0)
	if value == 0.0:
		bits = 1 if toward > 0.0 else -0x7FFFFFFFFFFFFFFF
	elif (value > 0.0) == (toward > value):
		bits += 1
	else:
		bits -= 1
	bytes.encode_s64(0, bits)
	return bytes.decode_double(0)
