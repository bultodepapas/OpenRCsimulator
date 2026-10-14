extends SceneTree

const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const Math3D := preload("res://physics/math3d.gd")
const EDGE_EPSILON := 1.0e-9
const BENCH_TRIALS := 7
const BENCH_CALLS_PER_TRIAL := 16000

var comparisons := 0
var failures := 0
var reported_failures := 0
var category_counts := {"route": 0, "loop_edges": 0, "technical_access_edges": 0,
	"feature_transitions": 0, "changed_data": 0, "invalid_inputs": 0}


func _initialize() -> void:
	var loaded: Dictionary = Track.load_default()
	if not bool(loaded.get("ok", false)):
		push_error("Cannot load default airfield track: %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	var track: Dictionary = loaded.track
	_test_route(track)
	_test_loop_edges(track)
	_test_technical_and_access_edges(track)
	_test_feature_transitions(track)
	_test_changed_data(track)
	_test_invalid_inputs(track)
	print(JSON.stringify({"format": "openrc-rcv-track-sampler-parity-v1", "ok": failures == 0,
		"comparisons": comparisons, "failures": failures, "categories": category_counts}, "  ", true, true))
	if failures == 0 and OS.get_cmdline_user_args().has("--bench"):
		_benchmark(track)
	quit(1 if failures > 0 else 0)


func _benchmark(track: Dictionary) -> void:
	var positions := _benchmark_positions(track)
	var sink := 0.0
	# Warm both paths before alternating their order across measured trials.
	sink += _reference_batch(track, positions, 4000)
	sink += _candidate_batch(track, positions, 4000)
	var reference_durations := PackedFloat64Array()
	var candidate_durations := PackedFloat64Array()
	for trial in BENCH_TRIALS:
		var reference_elapsed := 0
		var candidate_elapsed := 0
		if trial % 2 == 0:
			var started := Time.get_ticks_usec()
			sink += _reference_batch(track, positions, BENCH_CALLS_PER_TRIAL)
			reference_elapsed = Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			sink += _candidate_batch(track, positions, BENCH_CALLS_PER_TRIAL)
			candidate_elapsed = Time.get_ticks_usec() - started
		else:
			var started := Time.get_ticks_usec()
			sink += _candidate_batch(track, positions, BENCH_CALLS_PER_TRIAL)
			candidate_elapsed = Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			sink += _reference_batch(track, positions, BENCH_CALLS_PER_TRIAL)
			reference_elapsed = Time.get_ticks_usec() - started
		reference_durations.append(float(reference_elapsed) / BENCH_CALLS_PER_TRIAL)
		candidate_durations.append(float(candidate_elapsed) / BENCH_CALLS_PER_TRIAL)
	var reference_summary := _duration_summary(reference_durations)
	var candidate_summary := _duration_summary(candidate_durations)
	print(JSON.stringify({
		"format": "openrc-rcv-track-sampler-bench-v1",
		"engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"scope": "Paired same-process direct Track.sample calls against the preserved pre-change GDScript implementation; no vehicle/session ticks.",
		"position_count": positions.size(),
		"calls_per_method_per_trial": BENCH_CALLS_PER_TRIAL,
		"trials": BENCH_TRIALS,
		"reference_mean_us_per_sample": reference_summary.mean_us,
		"reference_median_us_per_sample": reference_summary.median_us,
		"candidate_mean_us_per_sample": candidate_summary.mean_us,
		"candidate_median_us_per_sample": candidate_summary.median_us,
		"median_speedup_percent": 100.0 * (1.0 - candidate_summary.median_us / reference_summary.median_us),
		"reference_trial_us_per_sample": reference_durations,
		"candidate_trial_us_per_sample": candidate_durations,
		"sink": sink,
	}, "  ", true, true))


func _benchmark_positions(track: Dictionary) -> Array[PackedFloat64Array]:
	var positions: Array[PackedFloat64Array] = []
	var half := float(track.lane_width_m) * 0.5
	var shoulder := float(track.shoulder_m)
	var straight := 2.0 * float(track.half_straight_m)
	var arc := PI * float(track.radius_m)
	var loop_length := 2.0 * straight + 2.0 * arc
	var samples := int(ceil(loop_length / 0.5))
	for index in samples:
		for offset in [-half - shoulder - EDGE_EPSILON, -half, 0.0, half, half + shoulder + EDGE_EPSILON]:
			positions.append(_loop_point(track, float(index) * 0.5, float(offset)))
	for group in ["ramps", "rollers"]:
		for feature: Dictionary in track[group]:
			var approach := float(feature.approach_m)
			var deck_half := float(feature.deck_m) * 0.5
			var descent := float(feature.descent_m)
			for east_offset in [-approach, -deck_half, 0.0, deck_half, deck_half + descent]:
				for north_offset in [-half - shoulder, 0.0, half + shoulder]:
					positions.append(PackedFloat64Array([
						float(feature.north_m) + north_offset,
						float(feature.east_m) + east_offset,
					]))
	return positions


func _reference_batch(track: Dictionary, positions: Array[PackedFloat64Array], calls: int) -> float:
	var sink := 0.0
	for index in calls:
		var position: PackedFloat64Array = positions[index % positions.size()]
		var sample := _reference_sample(track, position[0], position[1])
		sink += float(sample.height_m) + float(sample.dn) + float(sample.de) + float(sample.coverage)
	return sink


func _candidate_batch(track: Dictionary, positions: Array[PackedFloat64Array], calls: int) -> float:
	var sink := 0.0
	for index in calls:
		var position: PackedFloat64Array = positions[index % positions.size()]
		var sample := Track.sample(track, position[0], position[1])
		sink += float(sample.height_m) + float(sample.dn) + float(sample.de) + float(sample.coverage)
	return sink


func _duration_summary(values: PackedFloat64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {"mean_us": total / sorted.size(), "median_us": sorted[sorted.size() / 2]}


func _test_route(track: Dictionary) -> void:
	var straight := 2.0 * float(track.half_straight_m)
	var arc := PI * float(track.radius_m)
	var loop_length := 2.0 * straight + 2.0 * arc
	var samples := int(ceil(loop_length / 0.5))
	for index in samples:
		var point := _loop_point(track, float(index) * 0.5, 0.0)
		_compare("route-%03d" % index, track, point[0], point[1], "route")


func _test_loop_edges(track: Dictionary) -> void:
	var half := float(track.lane_width_m) * 0.5
	var shoulder := float(track.shoulder_m)
	var offsets := [
		-half - shoulder - EDGE_EPSILON, -half - shoulder, -half - shoulder + EDGE_EPSILON,
		-half - EDGE_EPSILON, -half, -half + EDGE_EPSILON,
		0.0,
		half - EDGE_EPSILON, half, half + EDGE_EPSILON,
		half + shoulder - EDGE_EPSILON, half + shoulder,
		half + shoulder + EDGE_EPSILON,
	]
	var straight := 2.0 * float(track.half_straight_m)
	var arc := PI * float(track.radius_m)
	var loop_length := 2.0 * straight + 2.0 * arc
	var samples := int(ceil(loop_length / 0.5))
	for index in samples:
		for offset in offsets:
			var point := _loop_point(track, float(index) * 0.5, float(offset))
			_compare("loop-edge-%03d-%+.9f" % [index, float(offset)], track,
				point[0], point[1], "loop_edges")


func _test_technical_and_access_edges(track: Dictionary) -> void:
	var half_technical := float(track.technical_width_m) * 0.5
	var shoulder := float(track.shoulder_m)
	var north_offsets := [
		-half_technical - shoulder - EDGE_EPSILON, -half_technical - shoulder,
		-half_technical - shoulder + EDGE_EPSILON, -half_technical - EDGE_EPSILON,
		-half_technical, -half_technical + EDGE_EPSILON, 0.0,
		half_technical - EDGE_EPSILON, half_technical, half_technical + EDGE_EPSILON,
		half_technical + shoulder - EDGE_EPSILON, half_technical + shoulder,
		half_technical + shoulder + EDGE_EPSILON,
	]
	var east_min := float(track.center_east_m) - float(track.half_straight_m) - float(track.radius_m) - shoulder - 1.0
	var east_max := float(track.center_east_m) + float(track.half_straight_m) + float(track.radius_m) + shoulder + 1.0
	var east_samples := int(ceil((east_max - east_min) / 2.0))
	for east_index in east_samples + 1:
		var east := east_min + float(east_index) * 2.0
		for offset in north_offsets:
			_compare("technical-%03d-%+.9f" % [east_index, float(offset)], track,
				float(track.center_north_m) + float(offset), east, "technical_access_edges")

	var access: Dictionary = track.access
	var access_north_center := (float(access.north_min_m) + float(access.north_max_m)) * 0.5
	var access_north_half := (float(access.north_max_m) - float(access.north_min_m)) * 0.5
	var access_east_center := float(access.east_m)
	var access_east_half := float(access.width_m) * 0.5
	var access_offsets := [-access_north_half - shoulder - EDGE_EPSILON,
		-access_north_half - shoulder, -access_north_half - EDGE_EPSILON,
		-access_north_half, -access_north_half + EDGE_EPSILON, 0.0,
		access_north_half - EDGE_EPSILON, access_north_half,
		access_north_half + EDGE_EPSILON, access_north_half + shoulder - EDGE_EPSILON,
		access_north_half + shoulder, access_north_half + shoulder + EDGE_EPSILON]
	var access_east_offsets := [-access_east_half - shoulder - EDGE_EPSILON,
		-access_east_half - shoulder, -access_east_half - EDGE_EPSILON,
		-access_east_half, -access_east_half + EDGE_EPSILON, 0.0,
		access_east_half - EDGE_EPSILON, access_east_half,
		access_east_half + EDGE_EPSILON, access_east_half + shoulder - EDGE_EPSILON,
		access_east_half + shoulder, access_east_half + shoulder + EDGE_EPSILON]
	for north_offset in access_offsets:
		for east_offset in access_east_offsets:
			_compare("access-%+.9f-%+.9f" % [float(north_offset), float(east_offset)], track,
				access_north_center + float(north_offset), access_east_center + float(east_offset),
				"technical_access_edges")


func _test_feature_transitions(track: Dictionary) -> void:
	var shoulder := float(track.shoulder_m)
	for group in ["ramps", "rollers"]:
		for feature: Dictionary in track[group]:
			var approach := float(feature.approach_m)
			var deck_half := float(feature.deck_m) * 0.5
			var descent := float(feature.descent_m)
			var north_half := float(feature.width_m) * 0.5
			var east_offsets := [
				-approach - EDGE_EPSILON, -approach, -approach + EDGE_EPSILON,
				-deck_half - EDGE_EPSILON, -deck_half, -deck_half + EDGE_EPSILON,
				deck_half - EDGE_EPSILON, deck_half, deck_half + EDGE_EPSILON,
				deck_half + descent - EDGE_EPSILON, deck_half + descent,
				deck_half + descent + EDGE_EPSILON,
			]
			var north_offsets := [
				-north_half - shoulder - EDGE_EPSILON, -north_half - shoulder,
				-north_half - shoulder + EDGE_EPSILON, -north_half - EDGE_EPSILON,
				-north_half, -north_half + EDGE_EPSILON, 0.0,
				north_half - EDGE_EPSILON, north_half, north_half + EDGE_EPSILON,
				north_half + shoulder - EDGE_EPSILON, north_half + shoulder,
				north_half + shoulder + EDGE_EPSILON,
			]
			for east_offset in east_offsets:
				for north_offset in north_offsets:
					_compare("%s-%s-%+.9f-%+.9f" % [group, str(feature.id),
						float(east_offset), float(north_offset)], track,
						float(feature.north_m) + float(north_offset),
						float(feature.east_m) + float(east_offset), "feature_transitions")


func _test_invalid_inputs(track: Dictionary) -> void:
	_compare("empty-track", {}, 45.0, 0.0, "invalid_inputs")
	for point: Array in [
		[NAN, 0.0], [45.0, NAN], [NAN, NAN],
		[INF, 0.0], [-INF, 0.0], [45.0, INF], [45.0, -INF],
		[1.0e9, -1.0e9], [-1.0e9, 1.0e9],
	]:
		_compare("invalid-%s-%s" % [str(point[0]), str(point[1])], track,
			float(point[0]), float(point[1]), "invalid_inputs")


func _test_changed_data(track: Dictionary) -> void:
	var changed: Dictionary = track.duplicate(true)
	changed.pad_height_m = float(changed.pad_height_m) + 0.017
	changed.bank_height_m = minf(float(changed.bank_height_m) + 0.11, 2.0)
	changed.lane_width_m = float(changed.lane_width_m) * 1.04
	changed.shoulder_m = float(changed.shoulder_m) * 0.93
	changed.technical_width_m = float(changed.technical_width_m) + 0.4
	var ramps: Array = changed.ramps
	var ramp: Dictionary = ramps[0]
	ramp.approach_m = float(ramp.approach_m) + 0.25
	ramp.east_m = float(ramp.east_m) + 0.3
	ramp.height_m = minf(float(ramp.height_m) + 0.03, 2.0)
	ramp.width_m = float(ramp.width_m) + 0.2
	ramps[0] = ramp
	changed.ramps = ramps
	var rollers: Array = changed.rollers
	var roller: Dictionary = rollers[0]
	roller.east_m = float(roller.east_m) - 0.2
	roller.width_m = float(roller.width_m) + 0.15
	rollers[0] = roller
	changed.rollers = rollers
	if not Track.valid(changed):
		failures += 1
		push_error("Changed track-data parity case must remain a valid authored track")
		return
	var straight := 2.0 * float(changed.half_straight_m)
	var arc := PI * float(changed.radius_m)
	var loop_length := 2.0 * straight + 2.0 * arc
	var route_samples := int(ceil(loop_length / 0.5))
	for index in route_samples:
		var point := _loop_point(changed, float(index) * 0.5, 0.0)
		_compare("changed-route-%03d" % index, changed, point[0], point[1], "changed_data")
	var half := float(changed.lane_width_m) * 0.5
	var shoulder := float(changed.shoulder_m)
	var offsets := [-half - shoulder - EDGE_EPSILON, -half - shoulder,
		-half - EDGE_EPSILON, -half, 0.0, half - EDGE_EPSILON, half,
		half + EDGE_EPSILON, half + shoulder, half + shoulder + EDGE_EPSILON]
	for index in range(0, route_samples, 4):
		for offset in offsets:
			var point := _loop_point(changed, float(index) * 0.5, float(offset))
			_compare("changed-loop-edge-%03d-%+.9f" % [index, float(offset)], changed,
				point[0], point[1], "changed_data")
	for group in ["ramps", "rollers"]:
		for feature: Dictionary in changed[group]:
			var approach := float(feature.approach_m)
			var deck_half := float(feature.deck_m) * 0.5
			var descent := float(feature.descent_m)
			var north_half := float(feature.width_m) * 0.5
			var east_offsets := [-approach - EDGE_EPSILON, -approach, -approach + EDGE_EPSILON,
				-deck_half, -deck_half + EDGE_EPSILON, deck_half - EDGE_EPSILON,
				deck_half, deck_half + EDGE_EPSILON, deck_half + descent - EDGE_EPSILON,
				deck_half + descent, deck_half + descent + EDGE_EPSILON]
			var north_offsets := [-north_half - shoulder - EDGE_EPSILON, -north_half,
				-north_half + EDGE_EPSILON, 0.0, north_half - EDGE_EPSILON,
				north_half, north_half + shoulder + EDGE_EPSILON]
			for east_offset in east_offsets:
				for north_offset in north_offsets:
					_compare("changed-%s-%s-%+.9f-%+.9f" % [group, str(feature.id),
						float(east_offset), float(north_offset)], changed,
						float(feature.north_m) + float(north_offset),
						float(feature.east_m) + float(east_offset), "changed_data")


func _compare(label: String, track: Dictionary, north: float, east: float, category: String) -> void:
	var expected := _reference_sample(track, north, east)
	var actual: Dictionary = Track.sample(track, north, east)
	comparisons += 1
	category_counts[category] = int(category_counts[category]) + 1
	if _same_value(expected, actual):
		return
	failures += 1
	if reported_failures < 10:
		push_error("Track sampler parity failed at %s N=%.12g E=%.12g: expected %s, got %s" % [
			label, north, east, str(expected), str(actual)])
		reported_failures += 1


func _loop_point(track: Dictionary, distance: float, lateral_offset: float) -> PackedFloat64Array:
	var center_north := float(track.center_north_m)
	var center_east := float(track.center_east_m)
	var half_straight := float(track.half_straight_m)
	var radius := float(track.radius_m)
	var straight := 2.0 * half_straight
	var arc := PI * radius
	var loop_length := 2.0 * straight + 2.0 * arc
	var remaining := fposmod(distance, loop_length)
	var north := 0.0
	var east := 0.0
	var normal_north := 0.0
	var normal_east := 0.0
	if remaining < straight:
		north = center_north - radius
		east = center_east - half_straight + remaining
		normal_north = -1.0
	elif remaining < straight + arc:
		var angle := -PI * 0.5 + (remaining - straight) / radius
		normal_north = Math3D.sin_(angle)
		normal_east = Math3D.cos_(angle)
		north = center_north + radius * normal_north
		east = center_east + half_straight + radius * normal_east
	elif remaining < 2.0 * straight + arc:
		var top_distance := remaining - straight - arc
		north = center_north + radius
		east = center_east + half_straight - top_distance
		normal_north = 1.0
	else:
		var angle := PI * 0.5 + (remaining - straight - arc) / radius
		normal_north = Math3D.sin_(angle)
		normal_east = Math3D.cos_(angle)
		north = center_north + radius * normal_north
		east = center_east - half_straight + radius * normal_east
	return PackedFloat64Array([north + lateral_offset * normal_north,
		east + lateral_offset * normal_east])


func _reference_sample(track: Dictionary, north_m: float, east_m: float) -> Dictionary:
	var empty := {"height_m": 0.0, "dn": 0.0, "de": 0.0, "coverage": 0.0, "feature_id": ""}
	if track.is_empty(): return empty
	var n := north_m - float(track.center_north_m)
	var e := east_m - float(track.center_east_m)
	var length := float(track.half_straight_m)
	var radius := float(track.radius_m)
	var half := float(track.lane_width_m) * 0.5
	var shoulder := float(track.shoulder_m)
	if absf(e) > length + radius + half + shoulder or north_m < float(track.access.north_min_m) - shoulder or absf(n) > radius + half + shoulder and north_m > float(track.center_north_m): return empty
	var excess_e := e - clampf(e, -length, length)
	var distance := Math3D.sqrt_(n * n + excess_e * excess_e)
	var radial_n := n / distance if distance > 1e-12 else 0.0
	var radial_e := excess_e / distance if distance > 1e-12 else 0.0
	var lateral := distance - radius
	var strip := _reference_band(lateral, half, shoulder)
	var coverage := strip[0]
	var cn := strip[1] * radial_n
	var ce := strip[1] * radial_e
	var feature := "dirt_loop" if coverage > 0.0 else ""
	var technical_n := _reference_band(n, float(track.technical_width_m) * 0.5, shoulder)
	var technical_e := _reference_band(e, length + radius, shoulder)
	var technical := technical_n[0] * technical_e[0]
	if technical > coverage:
		coverage = technical
		cn = technical_n[1] * technical_e[0]
		ce = technical_n[0] * technical_e[1]
		feature = "wall_slalom"
	var access: Dictionary = track.access
	var access_n := _reference_band(north_m - (float(access.north_min_m) + float(access.north_max_m)) * 0.5, (float(access.north_max_m) - float(access.north_min_m)) * 0.5, shoulder)
	var access_e := _reference_band(east_m - float(access.east_m), float(access.width_m) * 0.5, shoulder)
	var access_mask := access_n[0] * access_e[0]
	if access_mask > coverage:
		coverage = access_mask
		cn = access_n[1] * access_e[0]
		ce = access_n[0] * access_e[1]
		feature = "access"
	var height := float(track.pad_height_m) * coverage
	var dn := float(track.pad_height_m) * cn
	var de := float(track.pad_height_m) * ce
	var turn := _reference_smooth((absf(e) - (length - 2.0)) / 3.5)
	var turn_e := turn[1] * signf(e) / 3.5
	var across := clampf((lateral + half) / (2.0 * half), 0.0, 1.0)
	var across_d := 1.0 / (2.0 * half) if lateral > -half and lateral < half else 0.0
	var bank_shape := _reference_smooth(across)
	var bank := float(track.bank_height_m) * bank_shape[0]
	var bank_d := float(track.bank_height_m) * bank_shape[1] * across_d
	height += bank * turn[0] * strip[0]
	dn += turn[0] * (bank_d * strip[0] + bank * strip[1]) * radial_n
	de += turn[0] * (bank_d * strip[0] + bank * strip[1]) * radial_e + bank * turn_e * strip[0]
	if turn[0] * strip[0] > 0.05: feature = "banked_turn"
	for group in ["ramps", "rollers"]:
		for ramp: Dictionary in track[group]:
			var along := _reference_ramp(east_m - float(ramp.east_m), float(ramp.approach_m), float(ramp.deck_m), float(ramp.descent_m))
			if along[0] == 0.0: continue
			var cross := _reference_band(north_m - float(ramp.north_m), float(ramp.width_m) * 0.5, shoulder)
			var feature_height := float(ramp.height_m)
			height += feature_height * along[0] * cross[0]
			dn += feature_height * along[0] * cross[1]
			de += feature_height * along[1] * cross[0]
			if cross[0] > 0.0: feature = str(ramp.id)
	return {"height_m": height, "dn": dn, "de": de, "coverage": coverage, "feature_id": feature}


func _reference_smooth(t: float) -> PackedFloat64Array:
	if t <= 0.0: return PackedFloat64Array([0.0, 0.0])
	if t >= 1.0: return PackedFloat64Array([1.0, 0.0])
	return PackedFloat64Array([t * t * (3.0 - 2.0 * t), 6.0 * t * (1.0 - t)])


func _reference_band(offset: float, half: float, shoulder: float) -> PackedFloat64Array:
	var edge := _reference_smooth((absf(offset) - half) / shoulder)
	return PackedFloat64Array([1.0 - edge[0], -edge[1] * signf(offset) / shoulder])


func _reference_ramp(offset: float, approach: float, deck: float, descent: float) -> PackedFloat64Array:
	if offset < -deck * 0.5:
		var up := _reference_smooth((offset + deck * 0.5 + approach) / approach)
		return PackedFloat64Array([up[0], up[1] / approach])
	var down := _reference_smooth((offset - deck * 0.5) / descent)
	return PackedFloat64Array([1.0 - down[0], -down[1] / descent])


func _same_value(expected: Variant, actual: Variant) -> bool:
	if typeof(expected) == TYPE_DICTIONARY and typeof(actual) == TYPE_DICTIONARY:
		var expected_dictionary: Dictionary = expected
		var actual_dictionary: Dictionary = actual
		if expected_dictionary.size() != actual_dictionary.size(): return false
		for key in expected_dictionary:
			if not actual_dictionary.has(key) or not _same_value(expected_dictionary[key], actual_dictionary[key]):
				return false
		return true
	if typeof(expected) == TYPE_ARRAY and typeof(actual) == TYPE_ARRAY:
		var expected_array: Array = expected
		var actual_array: Array = actual
		if expected_array.size() != actual_array.size(): return false
		for index in expected_array.size():
			if not _same_value(expected_array[index], actual_array[index]): return false
		return true
	if typeof(expected) in [TYPE_INT, TYPE_FLOAT] and typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
		var expected_number := float(expected)
		var actual_number := float(actual)
		return expected_number == actual_number or expected_number != expected_number and actual_number != actual_number
	return expected == actual
