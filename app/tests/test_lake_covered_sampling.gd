## LU-25-R2: covered-only lake query parity against original method oracles.
extends SceneTree

const Loader := preload("res://data/lake_loader.gd")
const BaseLake := preload("res://tests/fixtures/lake_covered_reference.gd")
const BaseTerrain := preload("res://tests/fixtures/ground_terrain_covered_reference.gd")
const BaseHull := preload("res://tests/fixtures/hull_contact_covered_reference.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const CandidateLake := preload("res://physics/lake_surface.gd")
const CandidateTerrain := preload("res://physics/ground_terrain.gd")
const CandidateHull := preload("res://physics/hull_contact.gd")

const EDGE_DELTA_M: float = 0.000001
const TEST_TIME_S: float = 0.73
const SPATIAL_SAMPLES_PER_FIXTURE: int = 50

var _checks: int = 0
var _failures: int = 0
var _fixtures: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_fixtures()
	if not _fixtures.is_empty():
		_test_nonfinite_queries()
		for fixture: Dictionary in _fixtures:
			var lake: Dictionary = fixture.lake
			var name: String = str(fixture.name)
			_test_fixture_samples(name, lake)
			_test_expanded_bank_aabb_edges(name, lake)
			_test_polygon_stencil_edges(name + " bank", lake, lake.bank_ne_m)
			_test_polygon_stencil_edges(name + " shore", lake, lake.shoreline_ne_m)
			_test_caller_parity(name, lake)
		_test_spatial_caller_parity()
		_test_concave_aabb_miss()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _build_fixtures() -> void:
	var raw_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(Loader.DEFAULT_PATH))
	_check("frozen lake fixture parses as an object", typeof(raw_value) == TYPE_DICTIONARY)
	if typeof(raw_value) != TYPE_DICTIONARY:
		return
	var default_raw: Dictionary = raw_value
	_add_fixture("default", default_raw)

	var translated: Dictionary = default_raw.duplicate(true)
	translated["id"] = "pass3_translated_lake"
	translated["origin"]["north_m"] = float(translated.origin.north_m) + 517.25
	translated["origin"]["east_m"] = float(translated.origin.east_m) - 283.5
	_add_fixture("translated", translated)

	var custom: Dictionary = default_raw.duplicate(true)
	custom["id"] = "pass3_custom_octagon"
	custom["origin"] = {"north_m": 0.0, "east_m": 0.0}
	custom["shoreline_offsets_ne_m"] = [
		[-20.0, -15.0], [-20.0, 15.0], [-12.0, 22.0], [12.0, 22.0],
		[20.0, 15.0], [20.0, -15.0], [12.0, -22.0], [-12.0, -22.0],
	]
	custom["bank_offsets_ne_m"] = [
		[-30.0, -25.0], [-30.0, 25.0], [-18.0, 35.0], [18.0, 35.0],
		[30.0, 25.0], [30.0, -25.0], [18.0, -35.0], [-18.0, -35.0],
	]
	_add_fixture("custom", custom)

	# Both polygons are simple and valid; the east-facing notch makes a point inside the
	# bounding box but outside the concave bank polygon, exercising conservative fallback.
	var concave: Dictionary = default_raw.duplicate(true)
	concave["id"] = "pass3_concave_bank"
	concave["origin"] = {"north_m": 0.0, "east_m": 0.0}
	concave["shoreline_offsets_ne_m"] = [
		[-15.0, -20.0], [-15.0, 20.0], [-5.0, 20.0], [-5.0, 5.0],
		[5.0, 5.0], [5.0, 20.0], [15.0, 20.0], [15.0, -20.0],
	]
	concave["bank_offsets_ne_m"] = [
		[-30.0, -30.0], [-30.0, 30.0], [-2.0, 30.0], [-2.0, 10.0],
		[2.0, 10.0], [2.0, 30.0], [30.0, 30.0], [30.0, -30.0],
	]
	_add_fixture("concave", concave)


func _add_fixture(name: String, raw: Dictionary) -> void:
	var normalized: Dictionary = Loader.validate(raw)
	_check(name + " definition passes the existing lake schema", bool(normalized.get("ok", false)),
		str(normalized.get("errors", [])))
	if bool(normalized.get("ok", false)):
		_fixtures.append({"name": name, "lake": normalized.lake})


func _test_fixture_samples(name: String, lake: Dictionary) -> void:
	var origin_n: float = float(lake.origin_north_m)
	var origin_e: float = float(lake.origin_east_m)
	_assert_sample_pair(name + " origin/covered", lake, origin_n, origin_e)
	_assert_sample_pair(name + " translated interior", lake, origin_n + 1.25, origin_e - 2.5)
	var bounds: PackedFloat64Array = _polygon_bounds(lake.bank_ne_m)
	var far_north: float = bounds[0] - CandidateLake.SAMPLE_EPSILON_M - 1.0
	var middle_east: float = 0.5 * (bounds[2] + bounds[3])
	_assert_sample_pair(name + " far outside AABB", lake, far_north, middle_east)

	var outside: Dictionary = BaseLake.sample_terrain_validated(lake, far_north, middle_east)
	var candidate_full: Dictionary = CandidateLake.sample_terrain_validated(lake, far_north, middle_east)
	_check(name + " full outside sample retains diagnostic fields",
		_has_outside_diagnostics(outside) and _has_outside_diagnostics(candidate_full)
		and _same_variant(outside, candidate_full), str(candidate_full))


func _test_nonfinite_queries() -> void:
	var lake: Dictionary = _fixtures[0].lake
	var n: float = float(lake.origin_north_m)
	var e: float = float(lake.origin_east_m)
	var invalid_points: Array[PackedFloat64Array] = [
		PackedFloat64Array([NAN, e]), PackedFloat64Array([INF, e]), PackedFloat64Array([-INF, e]),
		PackedFloat64Array([n, NAN]), PackedFloat64Array([n, INF]), PackedFloat64Array([n, -INF]),
	]
	for point: PackedFloat64Array in invalid_points:
		_assert_sample_pair("nonfinite query %s" % str(point), lake, point[0], point[1])
		var base_full: Dictionary = BaseLake.sample_terrain_validated(lake, point[0], point[1])
		var candidate_full: Dictionary = CandidateLake.sample_terrain_validated(lake, point[0], point[1])
		var covered_only: Dictionary = CandidateLake.sample_covered_terrain_validated(lake, point[0], point[1])
		_check("nonfinite query preserves the invalid full sample", _same_variant(base_full, candidate_full)
			and base_full.get("region", "") == "invalid")
		_check("nonfinite query uses the full invalid result", _same_variant(candidate_full, covered_only))


func _assert_sample_pair(label: String, lake: Dictionary, north: float, east: float) -> void:
	var baseline_full: Dictionary = BaseLake.sample_terrain_validated(lake, north, east)
	var candidate_full: Dictionary = CandidateLake.sample_terrain_validated(lake, north, east)
	var covered_only: Dictionary = CandidateLake.sample_covered_terrain_validated(lake, north, east)
	_check(label + ": full sample and outside diagnostics unchanged",
		_same_variant(baseline_full, candidate_full), "base=%s candidate=%s" % [str(baseline_full), str(candidate_full)])
	if not is_finite(north) or not is_finite(east):
		_check(label + ": nonfinite covered-only result is fail-closed invalid sample",
			_same_variant(candidate_full, covered_only) and covered_only.get("region", "") == "invalid")
		return
	var outside_aabb: bool = _outside_expanded_bounds(lake.bank_ne_m, north, east,
		CandidateLake.SAMPLE_EPSILON_M)
	_check(label + ": coverage classification is preserved",
		bool(covered_only.get("covered", false)) == bool(baseline_full.get("covered", false)))
	if outside_aabb:
		_check(label + ": conservative outside result contains only covered=false",
			covered_only.size() == 1 and covered_only.has("covered") and not bool(covered_only.covered))
		_check(label + ": full sampler still returns outside diagnostics",
			_has_outside_diagnostics(baseline_full) and _has_outside_diagnostics(candidate_full))
	else:
		_check(label + ": in-bound result exactly preserves every full field",
			_same_variant(baseline_full, covered_only),
			"full=%s covered-only=%s" % [str(baseline_full), str(covered_only)])
		if not bool(baseline_full.get("covered", false)):
			_check(label + ": concave or near-bank miss keeps full diagnostics",
				_has_outside_diagnostics(covered_only))


func _test_expanded_bank_aabb_edges(name: String, lake: Dictionary) -> void:
	var bounds: PackedFloat64Array = _polygon_bounds(lake.bank_ne_m)
	var margin: float = CandidateLake.SAMPLE_EPSILON_M
	var delta: float = EDGE_DELTA_M
	var middle_n: float = 0.5 * (bounds[0] + bounds[1])
	var middle_e: float = 0.5 * (bounds[2] + bounds[3])
	var cases: Array[Dictionary] = [
		{"label": "north min just outside", "n": bounds[0] - margin - delta, "e": middle_e, "outside": true},
		{"label": "north min at stencil limit", "n": bounds[0] - margin, "e": middle_e, "outside": false},
		{"label": "north min just inside", "n": bounds[0] - margin + delta, "e": middle_e, "outside": false},
		{"label": "north max just inside", "n": bounds[1] + margin - delta, "e": middle_e, "outside": false},
		{"label": "north max at stencil limit", "n": bounds[1] + margin, "e": middle_e, "outside": false},
		{"label": "north max just outside", "n": bounds[1] + margin + delta, "e": middle_e, "outside": true},
		{"label": "east min just outside", "n": middle_n, "e": bounds[2] - margin - delta, "outside": true},
		{"label": "east min at stencil limit", "n": middle_n, "e": bounds[2] - margin, "outside": false},
		{"label": "east min just inside", "n": middle_n, "e": bounds[2] - margin + delta, "outside": false},
		{"label": "east max just inside", "n": middle_n, "e": bounds[3] + margin - delta, "outside": false},
		{"label": "east max at stencil limit", "n": middle_n, "e": bounds[3] + margin, "outside": false},
		{"label": "east max just outside", "n": middle_n, "e": bounds[3] + margin + delta, "outside": true},
	]
	for item: Dictionary in cases:
		var north: float = float(item.n)
		var east: float = float(item.e)
		var expected_outside: bool = bool(item.outside)
		_check(name + " expanded AABB decision: " + str(item.label),
			_outside_expanded_bounds(lake.bank_ne_m, north, east, margin) == expected_outside)
		_assert_sample_pair(name + " " + str(item.label), lake, north, east)


func _test_polygon_stencil_edges(label: String, lake: Dictionary, polygon: PackedFloat64Array) -> void:
	var frame: PackedFloat64Array = _edge_frame(polygon, 0)
	_check(label + " polygon edge frame is finite", frame.size() == 4
		and is_finite(frame[0]) and is_finite(frame[1]) and is_finite(frame[2]) and is_finite(frame[3]))
	if frame.size() != 4:
		return
	var edge_epsilon: float = CandidateLake.EDGE_EPSILON_M
	var edge_probes: Array[Dictionary] = [
		{"label": "exact edge", "offset": 0.0, "inside": true},
		{"label": "inside half edge epsilon", "offset": -0.5 * edge_epsilon, "inside": true},
		{"label": "outside half edge epsilon", "offset": 0.5 * edge_epsilon, "inside": true},
		{"label": "inside twice edge epsilon", "offset": -2.0 * edge_epsilon, "inside": true},
		{"label": "outside twice edge epsilon", "offset": 2.0 * edge_epsilon, "inside": false},
	]
	for item: Dictionary in edge_probes:
		var offset: float = float(item.offset)
		var point := PackedFloat64Array([
			frame[0] + frame[2] * offset,
			frame[1] + frame[3] * offset,
		])
		_assert_sample_pair(label + " " + str(item.label), lake, point[0], point[1])
		var full: Dictionary = BaseLake.sample_terrain_validated(lake, point[0], point[1])
		if label.contains("bank"):
			_check(label + " edge tolerance classification " + str(item.label),
				bool(full.get("covered", false)) == bool(item.inside), str(full))
		else:
			var expected_region: String = "bed" if bool(item.inside) else "bank"
			_check(label + " edge tolerance classification " + str(item.label),
				full.get("region", "") == expected_region, str(full))

	var probes: Array[PackedFloat64Array] = [
		PackedFloat64Array([frame[0] + frame[2] * CandidateLake.SAMPLE_EPSILON_M,
			frame[1] + frame[3] * CandidateLake.SAMPLE_EPSILON_M]),
		PackedFloat64Array([frame[0] - frame[2] * CandidateLake.SAMPLE_EPSILON_M,
			frame[1] - frame[3] * CandidateLake.SAMPLE_EPSILON_M]),
		PackedFloat64Array([frame[0] + frame[2] * (CandidateLake.SAMPLE_EPSILON_M + EDGE_DELTA_M),
			frame[1] + frame[3] * (CandidateLake.SAMPLE_EPSILON_M + EDGE_DELTA_M)]),
		PackedFloat64Array([frame[0] - frame[2] * (CandidateLake.SAMPLE_EPSILON_M + EDGE_DELTA_M),
			frame[1] - frame[3] * (CandidateLake.SAMPLE_EPSILON_M + EDGE_DELTA_M)]),
		PackedFloat64Array([frame[0] + CandidateLake.SAMPLE_EPSILON_M, frame[1]]),
		PackedFloat64Array([frame[0] - CandidateLake.SAMPLE_EPSILON_M, frame[1]]),
		PackedFloat64Array([frame[0], frame[1] + CandidateLake.SAMPLE_EPSILON_M]),
		PackedFloat64Array([frame[0], frame[1] - CandidateLake.SAMPLE_EPSILON_M]),
	]
	for index: int in probes.size():
		var point: PackedFloat64Array = probes[index]
		_assert_sample_pair(label + " epsilon/stencil probe %d" % index, lake, point[0], point[1])
	if label.contains("shore"):
		var shore_margin_ok := true
		for point: PackedFloat64Array in probes:
			shore_margin_ok = shore_margin_ok and not _outside_expanded_bounds(lake.bank_ne_m,
				point[0], point[1], CandidateLake.SAMPLE_EPSILON_M)
		_check(label + " shoreline epsilon probes stay inside bank-stencil fallback", shore_margin_ok)


func _test_caller_parity(name: String, lake: Dictionary) -> void:
	var surfaces: PackedFloat64Array = _surface_table()
	var bounds: PackedFloat64Array = _polygon_bounds(lake.bank_ne_m)
	var outside_n: float = bounds[0] - CandidateLake.SAMPLE_EPSILON_M - 0.5
	var outside_e: float = 0.5 * (bounds[2] + bounds[3])
	var bank_point: PackedFloat64Array = _find_bank_point(lake)
	_check(name + " fixture has a covered bank sample", bank_point.size() == 2,
		str(bank_point))
	var points: Array[PackedFloat64Array] = [
		PackedFloat64Array([float(lake.origin_north_m), float(lake.origin_east_m)]),
		PackedFloat64Array([outside_n, outside_e]),
	]
	if bank_point.size() == 2:
		points.append(bank_point)
	if name == "concave":
		points.append(PackedFloat64Array([float(lake.origin_north_m), float(lake.origin_east_m) + 20.0]))
	for index: int in points.size():
		var point: PackedFloat64Array = points[index]
		var old_sample: PackedFloat64Array = BaseTerrain.sample(point[0], point[1], surfaces, lake)
		var new_sample: PackedFloat64Array = CandidateTerrain.sample(point[0], point[1], surfaces, lake)
		var old_validated: PackedFloat64Array = BaseTerrain.sample_validated(point[0], point[1], surfaces, lake)
		var new_validated: PackedFloat64Array = CandidateTerrain.sample_validated(point[0], point[1], surfaces, lake)
		_check(name + " GroundTerrain.sample byte parity at point %d" % index,
			_same_packed64_bits(old_sample, new_sample), "base=%s candidate=%s" % [str(old_sample), str(new_sample)])
		_check(name + " GroundTerrain.sample_validated byte parity at point %d" % index,
			_same_packed64_bits(old_validated, new_validated),
			"base=%s candidate=%s" % [str(old_validated), str(new_validated)])
		_check(name + " sample and validated paths agree at point %d" % index,
			_same_packed64_bits(new_sample, new_validated))
		_assert_hull_parity(name + " HullContact.prop_disc_depth point %d" % index,
			lake, point[0], point[1], M.q_from_euler(0.0, 0.0, 0.0))

	var bad_sample: PackedFloat64Array = CandidateTerrain.sample(NAN, 0.0, surfaces, lake)
	var old_bad_sample: PackedFloat64Array = BaseTerrain.sample(NAN, 0.0, surfaces, lake)
	_check(name + " GroundTerrain invalid coordinate behavior unchanged",
		_same_packed64_values(old_bad_sample, bad_sample) and bad_sample.size() == 3 and is_nan(bad_sample[0]))


func _test_spatial_caller_parity() -> void:
	var surfaces: PackedFloat64Array = _surface_table()
	var position_count: int = 0
	var sample_matches: int = 0
	var validated_matches: int = 0
	var hull_matches: int = 0
	var tilted_hull_cases: int = 0
	var first_sample_mismatch: String = ""
	var first_validated_mismatch: String = ""
	var first_hull_mismatch: String = ""
	var covered_count: int = 0
	var outside_aabb_count: int = 0
	for fixture: Dictionary in _fixtures:
		var lake: Dictionary = fixture.lake
		var name: String = str(fixture.name)
		var bounds: PackedFloat64Array = _polygon_bounds(lake.bank_ne_m)
		var span_n: float = bounds[1] - bounds[0] + 0.4
		var span_e: float = bounds[3] - bounds[2] + 0.4
		for index: int in SPATIAL_SAMPLES_PER_FIXTURE:
			# Coprime modular strides give a stable, bounded spread through each expanded bank box.
			var u: float = (float((index * 17) % 53) + 0.5) / 53.0
			var v: float = (float((index * 29) % 47) + 0.5) / 47.0
			var north: float = bounds[0] - 0.2 + u * span_n
			var east: float = bounds[2] - 0.2 + v * span_e
			# Guarantee coverage of the fast path as well as the interior fallback.
			if index % 5 == 0:
				north = bounds[0] - CandidateLake.SAMPLE_EPSILON_M - 1.0
			var base_full: Dictionary = BaseLake.sample_terrain_validated(lake, north, east)
			if bool(base_full.get("covered", false)):
				covered_count += 1
			if _outside_expanded_bounds(lake.bank_ne_m, north, east, CandidateLake.SAMPLE_EPSILON_M):
				outside_aabb_count += 1

			var base_sample: PackedFloat64Array = BaseTerrain.sample(north, east, surfaces, lake)
			var candidate_sample: PackedFloat64Array = CandidateTerrain.sample(north, east, surfaces, lake)
			var sample_ok: bool = _same_packed64_bits(base_sample, candidate_sample)
			if sample_ok:
				sample_matches += 1
			elif first_sample_mismatch.is_empty():
				first_sample_mismatch = "%s[%d] at (%s,%s): base=%s candidate=%s" % [
					name, index, north, east, str(base_sample), str(candidate_sample)]

			var base_validated: PackedFloat64Array = BaseTerrain.sample_validated(north, east, surfaces, lake)
			var candidate_validated: PackedFloat64Array = CandidateTerrain.sample_validated(north, east, surfaces, lake)
			var validated_ok: bool = _same_packed64_bits(base_validated, candidate_validated)
			if validated_ok:
				validated_matches += 1
			elif first_validated_mismatch.is_empty():
				first_validated_mismatch = "%s[%d] at (%s,%s): base=%s candidate=%s" % [
					name, index, north, east, str(base_validated), str(candidate_validated)]

			var attitude: PackedFloat64Array = M.q_from_euler(0.0, 0.0, 0.0)
			if index % 2 == 1:
				attitude = M.q_from_euler(
					0.08 * sin(float(index) * 0.41),
					0.12 * cos(float(index) * 0.23),
					0.04 * sin(float(index) * 0.17))
				tilted_hull_cases += 1
			var hull_ok: bool = _hull_outputs_match(lake, north, east, attitude)
			if hull_ok:
				hull_matches += 1
			elif first_hull_mismatch.is_empty():
				first_hull_mismatch = "%s[%d] at (%s,%s), attitude=%s" % [
					name, index, north, east, str(attitude)]
			position_count += 1

	_check("spatial caller loop covers exactly 200 bounded positions",
		position_count == 4 * SPATIAL_SAMPLES_PER_FIXTURE and covered_count > 0 and outside_aabb_count == 40,
		"positions=%d covered=%d outside-expanded-AABB=%d" % [position_count, covered_count, outside_aabb_count])
	var sample_detail: String = "matches=%d/%d" % [sample_matches, position_count]
	if not first_sample_mismatch.is_empty():
		sample_detail += " first=" + first_sample_mismatch
	_check("spatial GroundTerrain.sample outputs match byte for byte",
		sample_matches == position_count, sample_detail)
	var validated_detail: String = "matches=%d/%d" % [validated_matches, position_count]
	if not first_validated_mismatch.is_empty():
		validated_detail += " first=" + first_validated_mismatch
	_check("spatial GroundTerrain.sample_validated outputs match byte for byte",
		validated_matches == position_count, validated_detail)
	var hull_detail: String = "matches=%d/%d tilted=%d" % [hull_matches, position_count, tilted_hull_cases]
	if not first_hull_mismatch.is_empty():
		hull_detail += " first=" + first_hull_mismatch
	_check("spatial HullContact.prop_disc_depth full outputs match byte for byte",
		hull_matches == position_count, hull_detail)


func _assert_hull_parity(label: String, lake: Dictionary, north: float, east: float,
		attitude: PackedFloat64Array) -> void:
	var old_and_new: Dictionary = _paired_hull_results(lake, north, east, attitude)
	_check(label + " caller outputs match byte for byte", bool(old_and_new.same),
		"base=%s candidate=%s" % [str(old_and_new.base), str(old_and_new.candidate)])


func _hull_outputs_match(lake: Dictionary, north: float, east: float,
		attitude: PackedFloat64Array) -> bool:
	var old_and_new: Dictionary = _paired_hull_results(lake, north, east, attitude)
	return bool(old_and_new.same)


func _paired_hull_results(lake: Dictionary, north: float, east: float,
		attitude: PackedFloat64Array) -> Dictionary:
	var state: PackedFloat64Array = RB.make_state(
		PackedFloat64Array([north, east, 0.7]), M.v3(0.0, 0.0, 0.0), attitude, M.v3(0.0, 0.0, 0.0))
	var disc: Dictionary = {
		"hub": PackedFloat64Array([0.0, 0.0, 0.0]),
		"axis": PackedFloat64Array([1.0, 0.0, 0.0]),
		"radius": 0.2,
	}
	var old_result: Dictionary = BaseHull.prop_disc_depth(state, disc, lake, TEST_TIME_S)
	var new_result: Dictionary = CandidateHull.prop_disc_depth(state, disc, lake, TEST_TIME_S)
	return {"same": _same_variant(old_result, new_result), "base": old_result, "candidate": new_result}


func _test_concave_aabb_miss() -> void:
	for fixture: Dictionary in _fixtures:
		if str(fixture.name) != "concave":
			continue
		var lake: Dictionary = fixture.lake
		var north: float = float(lake.origin_north_m)
		var east: float = float(lake.origin_east_m) + 20.0
		var full: Dictionary = BaseLake.sample_terrain_validated(lake, north, east)
		var covered_only: Dictionary = CandidateLake.sample_covered_terrain_validated(lake, north, east)
		_check("concave notch point lies inside bank AABB", not _outside_expanded_bounds(lake.bank_ne_m,
			north, east, CandidateLake.SAMPLE_EPSILON_M))
		_check("concave notch point remains an uncovered full diagnostic sample",
			not bool(full.get("covered", true)) and full.get("region", "") == "outside"
			and _has_outside_diagnostics(full) and _same_variant(full, covered_only),
			"full=%s covered-only=%s" % [str(full), str(covered_only)])
		return
	_check("concave fixture is present", false)


func _has_outside_diagnostics(sample: Dictionary) -> bool:
	var required: Array[String] = [
		"covered", "region", "ground_down_m", "slope_north", "slope_east",
		"blend_fraction", "blend_slope_north", "blend_slope_east", "bed_depth_m",
		"bed_depth_slope_north", "bed_depth_slope_east", "signed_shore_distance_m",
		"signed_bank_distance_m", "water_down_m", "depth_m",
	]
	if bool(sample.get("covered", true)) or sample.get("region", "") != "outside":
		return false
	for key: String in required:
		if not sample.has(key):
			return false
	return is_finite(float(sample.signed_bank_distance_m)) and float(sample.signed_bank_distance_m) < 0.0


func _outside_expanded_bounds(polygon: PackedFloat64Array, north: float, east: float, margin: float) -> bool:
	if not is_finite(north) or not is_finite(east):
		return false
	var bounds: PackedFloat64Array = _polygon_bounds(polygon)
	return north < bounds[0] - margin or north > bounds[1] + margin \
		or east < bounds[2] - margin or east > bounds[3] + margin


func _polygon_bounds(polygon: PackedFloat64Array) -> PackedFloat64Array:
	var north_min: float = INF
	var north_max: float = -INF
	var east_min: float = INF
	var east_max: float = -INF
	for index: int in range(0, polygon.size(), 2):
		north_min = minf(north_min, polygon[index])
		north_max = maxf(north_max, polygon[index])
		east_min = minf(east_min, polygon[index + 1])
		east_max = maxf(east_max, polygon[index + 1])
	return PackedFloat64Array([north_min, north_max, east_min, east_max])


func _edge_frame(polygon: PackedFloat64Array, edge_index: int) -> PackedFloat64Array:
	var count: int = polygon.size() / 2
	if count < 3 or edge_index < 0 or edge_index >= count:
		return PackedFloat64Array()
	var twice_area: float = 0.0
	for index: int in range(count):
		var next: int = (index + 1) % count
		twice_area += polygon[index * 2] * polygon[next * 2 + 1] \
			- polygon[index * 2 + 1] * polygon[next * 2]
	var next_edge: int = (edge_index + 1) % count
	var n1: float = polygon[edge_index * 2]
	var e1: float = polygon[edge_index * 2 + 1]
	var n2: float = polygon[next_edge * 2]
	var e2: float = polygon[next_edge * 2 + 1]
	var dn: float = n2 - n1
	var de: float = e2 - e1
	var length: float = sqrt(dn * dn + de * de)
	if length <= 0.0 or twice_area == 0.0:
		return PackedFloat64Array()
	var orientation: float = 1.0 if twice_area > 0.0 else -1.0
	# For positive N/E shoelace winding, the polygon interior is left of the edge.
	var outward_n: float = orientation * de / length
	var outward_e: float = -orientation * dn / length
	return PackedFloat64Array([0.5 * (n1 + n2), 0.5 * (e1 + e2), outward_n, outward_e])


func _find_bank_point(lake: Dictionary) -> PackedFloat64Array:
	var shoreline: PackedFloat64Array = lake.shoreline_ne_m
	for edge_index: int in shoreline.size() / 2:
		var frame: PackedFloat64Array = _edge_frame(shoreline, edge_index)
		if frame.size() != 4:
			continue
		for distance: float in [0.5, 1.0, 2.0, 4.0, 8.0]:
			var north: float = frame[0] + frame[2] * distance
			var east: float = frame[1] + frame[3] * distance
			var sample: Dictionary = BaseLake.sample_terrain_validated(lake, north, east)
			if bool(sample.get("covered", false)) and sample.get("region", "") == "bank":
				return PackedFloat64Array([north, east])
	return PackedFloat64Array()


func _surface_table() -> PackedFloat64Array:
	# Same precedence and sentinel row as test_ground_terrain.gd.
	return PackedFloat64Array([
		-10.0, 10.0, -20.0, 20.0, 0.8, 2.5,
		-30.0, 30.0, -40.0, 40.0, 0.7, 5.0,
		-100.0, 100.0, -100.0, 100.0, 0.7, 7.5,
		-INF, INF, -INF, INF, 0.7, 7.5,
	])


func _same_variant(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return _same_float_bits(float(a), float(b))
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key: Variant in a.keys():
				if not b.has(key) or not _same_variant(a[key], b[key]):
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for index: int in a.size():
				if not _same_variant(a[index], b[index]):
					return false
			return true
		TYPE_PACKED_FLOAT64_ARRAY:
			return _same_packed64_bits(a, b)
		_:
			return a == b


func _same_float_bits(a: float, b: float) -> bool:
	if is_nan(a) or is_nan(b):
		return is_nan(a) and is_nan(b)
	var left := PackedByteArray()
	var right := PackedByteArray()
	left.resize(8)
	right.resize(8)
	left.encode_double(0, a)
	right.encode_double(0, b)
	return left == right


func _same_packed64_bits(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for index: int in a.size():
		if not _same_float_bits(a[index], b[index]):
			return false
	return true


func _same_packed64_values(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for index: int in a.size():
		var left: float = a[index]
		var right: float = b[index]
		if is_nan(left) or is_nan(right):
			if not (is_nan(left) and is_nan(right)):
				return false
		elif left != right:
			return false
	return true
