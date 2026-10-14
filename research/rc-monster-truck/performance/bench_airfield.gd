## Profile the production airfield course from its authored dirt-circuit spawn.
## Run through run_airfield_profile.py so the native process is bounded and logged.
extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundContact := preload("res://physics/ground_contact.gd")
const M := preload("res://physics/math3d.gd")

const WARMUP_TICKS := 60
const MEASURED_TICKS := 480
const SAMPLE_REPEATS := 3
const SAMPLE_CALLS_PER_REPEAT := 1600
const REFERENCE_DRY_PAVEMENT_MU := 0.85
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const DRIVE := {"throttle": 0.55, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			if not output_path.is_empty():
				_fail("--output may be supplied only once")
				return
			output_path = argument.trim_prefix("--output=")
	if output_path.is_empty():
		_fail("--output=<absolute-json-path> is required")
		return

	var field_result: Dictionary = FieldLoader.load_from()
	if not bool(field_result.get("ok", false)):
		_fail("default airfield did not load: " + "; ".join(field_result.get("errors", [])))
		return
	var snapshot_path := ProjectSettings.globalize_path(
		"res://../research/rc-monster-truck/performance/vehicle_snapshot.json").simplify_path()
	var vehicle_result: Dictionary = VehicleData.load_file(snapshot_path)
	if not bool(vehicle_result.get("ok", false)):
		_fail("frozen vehicle input did not load: " + "; ".join(vehicle_result.get("errors", [])))
		return
	var course_result: Dictionary = AirfieldCourse.build(field_result)
	if not bool(course_result.get("ok", false)):
		_fail("production airfield course did not build: " + "; ".join(course_result.get("errors", [])))
		return
	var session = Session.new()
	if not session.prepare(vehicle_result, course_result, vehicle_result):
		_fail("production airfield session did not prepare: " + str(session.load_error))
		session.free()
		return
	if not session.reset("track_start"):
		_fail("authored track_start spawn was not accepted")
		session.free()
		return
	session.tick_once(NEUTRAL)
	if not session.resume():
		_fail("session did not resume after a neutral armed sample")
		session.free()
		return

	var course: Dictionary = session.course_snapshot()
	var all_durations := PackedFloat64Array()
	var measured_durations := PackedFloat64Array()
	var route_samples: Array[Dictionary] = []
	var surface_hits := {}
	var feature_hits := {}
	var track_samples := 0
	var peak_coverage := 0.0
	var state_hash := HashingContext.new()
	if state_hash.start(HashingContext.HASH_SHA256) != OK:
		_fail("could not start trajectory digest")
		session.free()
		return
	for tick in WARMUP_TICKS + MEASURED_TICKS:
		var before := Time.get_ticks_usec()
		var ok: bool = session.tick_once(DRIVE)
		var elapsed_us := float(Time.get_ticks_usec() - before)
		if not ok:
			_fail("vehicle session faulted during profile tick %d: %s" % [tick, str(session.fault_reason)])
			session.free()
			return
		all_durations.append(elapsed_us)
		if tick >= WARMUP_TICKS:
			measured_durations.append(elapsed_us)
		var state: PackedFloat64Array = session.state_snapshot()
		state_hash.update(state.to_byte_array())
		var road: Dictionary = AirfieldCourse.sample(course, state[0], state[1])
		var surface_id := str(road.get("surface_id", ""))
		var feature_id := str(road.get("feature_id", ""))
		surface_hits[surface_id] = int(surface_hits.get(surface_id, 0)) + 1
		if not feature_id.is_empty():
			feature_hits[feature_id] = int(feature_hits.get(feature_id, 0)) + 1
		var coverage := float(road.get("track_coverage", 0.0))
		peak_coverage = maxf(peak_coverage, coverage)
		if coverage > 0.0:
			track_samples += 1
		route_samples.append({"tick": tick + 1, "north_m": state[0], "east_m": state[1], "road": road})

	var measured_summary := _summary(measured_durations)
	var route_positions: Array[PackedFloat64Array] = []
	for sample: Dictionary in route_samples:
		route_positions.append(PackedFloat64Array([float(sample.north_m), float(sample.east_m)]))
	var sampler_cost := _compare_samplers(course, route_positions)
	var cache_invalidation := _check_cache_invalidation(course)
	if not bool(cache_invalidation.get("ok", false)):
		_fail("airfield course surface-table cache invalidation check failed: " + str(cache_invalidation))
		session.free()
		return
	var identities: Dictionary = session.identities_snapshot()
	var final_state: PackedFloat64Array = session.state_snapshot()
	var report := {
		"format": "openrc-rcv-airfield-course-profile-v1",
		"engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"backend_identity": VehicleDynamics.backend_identity(),
		"scope": "Session.tick_once at the 240 Hz production airfield course from track_start; 60 warmup and 480 measured drive ticks; no rendering or recording.",
		"vehicle_identity": identities.get("model", {}),
		"course_identity": identities.get("course", {}),
		"track_id": str(course.get("track", {}).get("id", "")),
		"spawn_id": "track_start",
		"controls": DRIVE,
		"warmup_ticks": WARMUP_TICKS,
		"measured_ticks": MEASURED_TICKS,
		"tick_cost": measured_summary,
		"warmup_tick_cost": _summary(all_durations.slice(0, WARMUP_TICKS)),
		"trajectory_sha256": state_hash.finish().hex_encode(),
		"initial_position_north_east_m": [route_samples[0].north_m, route_samples[0].east_m],
		"final_position_north_east_m": [final_state[0], final_state[1]],
		"final_speed_m_per_s": sqrt(final_state[3] * final_state[3] + final_state[4] * final_state[4] + final_state[5] * final_state[5]),
		"route_sample_count": route_samples.size(),
		"surface_hits": surface_hits,
		"feature_hits": feature_hits,
		"track_sample_count": track_samples,
		"peak_track_coverage": peak_coverage,
		"sampler_cost": sampler_cost,
		"cache_invalidation": cache_invalidation,
		"route_samples": route_samples,
		"course_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_course.gd"),
		"track_script_sha256": FileAccess.get_sha256("res://physics/ground_vehicle/airfield_track.gd"),
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot open profile output (error %d)" % FileAccess.get_open_error())
		session.free()
		return
	file.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	file.close()
	session.free()
	print(JSON.stringify({"ok": true, "output": output_path, "tick_cost": measured_summary, "sampler_cost": sampler_cost}, "  ", true, true))
	quit(0)


func _compare_samplers(course: Dictionary, route_positions: Array[PackedFloat64Array]) -> Dictionary:
	var positions := _comparison_positions(course, route_positions)
	var reference_durations := PackedFloat64Array()
	var cached_eager_durations := PackedFloat64Array()
	var candidate_durations := PackedFloat64Array()
	var cached_eager_exact := true
	var candidate_exact := true
	var cached_eager_mismatches := 0
	var candidate_mismatches := 0
	var sink := 0.0
	for repeat in SAMPLE_REPEATS:
		for index in SAMPLE_CALLS_PER_REPEAT:
			var position: PackedFloat64Array = positions[index % positions.size()]
			var reference: Dictionary
			var cached_eager: Dictionary
			var candidate: Dictionary
			var order := (index + repeat) % 3
			for slot in 3:
				var method := (order + slot) % 3
				var started := Time.get_ticks_usec()
				if method == 0:
					reference = _reference_sample(course, position[0], position[1])
					reference_durations.append(float(Time.get_ticks_usec() - started))
				elif method == 1:
					cached_eager = _cached_eager_sample(course, position[0], position[1])
					cached_eager_durations.append(float(Time.get_ticks_usec() - started))
				else:
					candidate = AirfieldCourse.sample(course, position[0], position[1])
					candidate_durations.append(float(Time.get_ticks_usec() - started))
			if reference != cached_eager:
				cached_eager_exact = false
				cached_eager_mismatches += 1
			if reference != candidate:
				candidate_exact = false
				candidate_mismatches += 1
			sink += float(candidate.get("height_m", 0.0)) + float(candidate.get("mu", 0.0))
	var reference_summary := _summary(reference_durations)
	var cached_eager_summary := _summary(cached_eager_durations)
	var candidate_summary := _summary(candidate_durations)
	var reference_mean := float(reference_summary.mean_us)
	var cached_eager_mean := float(cached_eager_summary.mean_us)
	var candidate_mean := float(candidate_summary.mean_us)
	return {
		"method": "single-process, interleaved three-way sampler calls; call order rotates for each route/feature query",
		"positions_compared": positions.size(),
		"calls_per_implementation": reference_durations.size(),
		"reference": reference_summary,
		"cached_eager": cached_eager_summary,
		"candidate": candidate_summary,
		"mean_reduction_percent": (reference_mean - candidate_mean) * 100.0 / reference_mean,
		"deferred_allocation_reduction_vs_cached_eager_percent": (cached_eager_mean - candidate_mean) * 100.0 / cached_eager_mean,
		"cached_eager_outputs_exact": cached_eager_exact,
		"cached_eager_output_mismatches": cached_eager_mismatches,
		"candidate_outputs_exact": candidate_exact,
		"candidate_output_mismatches": candidate_mismatches,
		"compared_fields": "complete course sample dictionaries, including normals, friction, coverage, surface/feature IDs, in_bounds and full wall dictionaries",
		"sink": sink,
	}


## Cache-only sampler copy with eager invalid-result allocation, used to isolate that allocation cost.
func _cached_eager_sample(course: Dictionary, north_m: float, east_m: float) -> Dictionary:
	var invalid := AirfieldCourse._invalid_sample()
	var rects_value: Variant = course.get("surface_rects")
	if not is_finite(north_m) or not is_finite(east_m) \
			or typeof(rects_value) != TYPE_PACKED_FLOAT64_ARRAY \
			or not AirfieldCourse._cached_surface_rects_are_valid(rects_value):
		return invalid
	var rects: PackedFloat64Array = rects_value
	var lake_value: Variant = course.get("lake", {})
	if typeof(lake_value) != TYPE_DICTIONARY:
		return invalid
	var lake: Dictionary = lake_value
	var terrain: PackedFloat64Array = GroundTerrain.sample_validated(north_m, east_m, rects, lake)
	if terrain.size() != 3 or not is_finite(terrain[0]) or not is_finite(terrain[1]) or not is_finite(terrain[2]):
		return invalid
	var track: Dictionary = course.get("track", {})
	var overlay := Track.sample(track, north_m, east_m)
	terrain[0] += float(overlay.height_m)
	terrain[1] += float(overlay.dn)
	terrain[2] += float(overlay.de)
	var normal := PackedFloat64Array([-terrain[1], -terrain[2], -1.0])
	var magnitude := M.sqrt_(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
	if not is_finite(magnitude) or magnitude <= 0.0:
		return invalid
	for axis in normal.size():
		normal[axis] /= magnitude
	var offset := GroundContact.surface_at(rects, north_m, east_m)
	if offset < 0 or offset + GroundTerrain.SURFACE_STRIDE > rects.size():
		return invalid
	var row_index := int(offset / GroundTerrain.SURFACE_STRIDE)
	var surface_rows: Variant = course.get("surface_rows", [])
	if typeof(surface_rows) != TYPE_ARRAY or row_index >= surface_rows.size() \
			or typeof(surface_rows[row_index]) != TYPE_DICTIONARY:
		return invalid
	var row: Dictionary = surface_rows[row_index]
	var mu := AirfieldCourse.DRY_PAVEMENT_MU * rects[offset + 4]
	var rolling := rects[offset + 5]
	var coverage := float(overlay.coverage)
	if coverage > 0.0:
		mu = lerpf(mu, float(track.mu), coverage)
		rolling = lerpf(rolling, float(track.rolling), coverage)
	if not is_finite(mu) or mu <= 0.0 or not is_finite(rolling) or rolling < 0.0:
		return invalid
	var bounds_value: Variant = course.get("bounds", {})
	var in_bounds := false
	if typeof(bounds_value) == TYPE_DICTIONARY:
		in_bounds = north_m >= float(bounds_value.get("north_min_m", INF)) \
			and north_m <= float(bounds_value.get("north_max_m", -INF)) \
			and east_m >= float(bounds_value.get("east_min_m", INF)) \
			and east_m <= float(bounds_value.get("east_max_m", -INF))
	return {
		"height_m": terrain[0],
		"normal_ned": normal,
		"mu": mu,
		"rolling": rolling,
		"surface_id": "rc_dirt" if coverage >= 0.5 else str(row.get("id", "outside")),
		"in_bounds": in_bounds,
		"feature_id": str(overlay.feature_id),
		"feature_ids": [] if str(overlay.feature_id).is_empty() else [str(overlay.feature_id)],
		"track_coverage": coverage,
		"walls": Track.nearby_walls(track, north_m, east_m),
	}


func _check_cache_invalidation(course: Dictionary) -> Dictionary:
	var position := PackedFloat64Array([15.0, 0.0])
	var original: PackedFloat64Array = course.get("surface_rects", PackedFloat64Array())
	if original.is_empty():
		return {"ok": false, "reason": "production surface table unexpectedly empty"}
	var original_sample := AirfieldCourse.sample(course, position[0], position[1])
	var offset := GroundContact.surface_at(original, position[0], position[1])
	if offset < 0 or offset + 4 >= original.size():
		return {"ok": false, "reason": "runway query did not resolve to a surface row"}
	var modified_course := course.duplicate()
	var modified := original.duplicate()
	var replacement := 0.95 if modified[offset + 4] < 0.95 else 0.1
	modified[offset + 4] = replacement
	modified_course["surface_rects"] = modified
	var mutated := AirfieldCourse.sample(modified_course, position[0], position[1])
	var mutated_reference := _reference_sample(modified_course, position[0], position[1])
	var same_length_valid_mutation := modified.size() == original.size() \
		and GroundTerrain.is_valid_surface_table(modified) \
		and mutated == mutated_reference and float(mutated.mu) != float(original_sample.mu)

	var nan_table := modified.duplicate()
	nan_table[offset + 4] = NAN
	var nan_course := course.duplicate()
	nan_course["surface_rects"] = nan_table
	var nan_actual := AirfieldCourse.sample(nan_course, position[0], position[1])
	var nan_reference := _reference_sample(nan_course, position[0], position[1])
	var nan_mutation_rejected := not GroundTerrain.is_valid_surface_table(nan_table) \
		and _invalid_results_match(nan_actual, nan_reference)

	var empty_course := course.duplicate()
	empty_course["surface_rects"] = PackedFloat64Array()
	var empty_actual := AirfieldCourse.sample(empty_course, position[0], position[1])
	var empty_reference := _reference_sample(empty_course, position[0], position[1])
	var empty_transition_rejected := _invalid_results_match(empty_actual, empty_reference)

	var restored_course := course.duplicate()
	var restored_actual := AirfieldCourse.sample(restored_course, position[0], position[1])
	var restored_reference := _reference_sample(restored_course, position[0], position[1])
	var restore_after_invalid := restored_actual == restored_reference and restored_actual == original_sample
	return {
		"ok": same_length_valid_mutation and nan_mutation_rejected and empty_transition_rejected and restore_after_invalid,
		"query_north_east_m": [position[0], position[1]],
		"row_offset": offset,
		"table_size": original.size(),
		"same_length_valid_mutation_exact_and_applied": same_length_valid_mutation,
		"nan_mutation_rejected_fail_closed": nan_mutation_rejected,
		"empty_table_transition_matches_reference": empty_transition_rejected,
		"original_table_restores_exactly_after_invalid_inputs": restore_after_invalid,
	}


func _invalid_results_match(actual: Dictionary, reference: Dictionary) -> bool:
	for key in ["height_m", "mu", "rolling"]:
		if not actual.has(key) or not reference.has(key) \
				or is_finite(float(actual[key])) or is_finite(float(reference[key])):
			return false
	var actual_normal: Variant = actual.get("normal_ned")
	var reference_normal: Variant = reference.get("normal_ned")
	if typeof(actual_normal) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(reference_normal) != TYPE_PACKED_FLOAT64_ARRAY \
			or actual_normal.size() != 3 or reference_normal.size() != 3:
		return false
	for axis in 3:
		if is_finite(actual_normal[axis]) or is_finite(reference_normal[axis]):
			return false
	return actual.get("surface_id", null) == "" and reference.get("surface_id", null) == "" \
		and actual.get("in_bounds", null) == false and reference.get("in_bounds", null) == false \
		and actual.get("feature_id", null) == "" and reference.get("feature_id", null) == "" \
		and actual.get("feature_ids", null) == [] and reference.get("feature_ids", null) == []


func _comparison_positions(course: Dictionary, route_positions: Array[PackedFloat64Array]) -> Array[PackedFloat64Array]:
	var positions: Array[PackedFloat64Array] = route_positions.duplicate()
	positions.append_array([
		PackedFloat64Array([15.0, 0.0]), PackedFloat64Array([15.0, 48.0]), PackedFloat64Array([21.0, -10.0]),
		PackedFloat64Array([80.0, 0.0]), PackedFloat64Array([39.0, -4.0]), PackedFloat64Array([51.0, 0.0]),
	])
	var track: Dictionary = course.get("track", {})
	for group in ["ramps", "rollers"]:
		for feature: Dictionary in track.get(group, []):
			var north := float(feature.north_m)
			var east := float(feature.east_m)
			positions.append(PackedFloat64Array([north, east]))
			positions.append(PackedFloat64Array([north, east - float(feature.approach_m)]))
			positions.append(PackedFloat64Array([north, east + float(feature.deck_m) * 0.5]))
	for wall: Dictionary in track.get("walls", []):
		var north := (float(wall.north_min_m) + float(wall.north_max_m)) * 0.5
		var east := (float(wall.east_min_m) + float(wall.east_max_m)) * 0.5
		positions.append(PackedFloat64Array([north, east]))
		positions.append(PackedFloat64Array([north - 0.9, east]))
		positions.append(PackedFloat64Array([north + 0.9, east]))
	return positions


## Baseline airfield_course.gd sample implementation captured before the cache change.
func _reference_sample(course: Dictionary, north_m: float, east_m: float) -> Dictionary:
	var invalid := {"height_m": NAN, "normal_ned": PackedFloat64Array([NAN, NAN, NAN]),
		"mu": NAN, "rolling": NAN, "surface_id": "", "in_bounds": false,
		"feature_id": "", "feature_ids": []}
	var rects_value: Variant = course.get("surface_rects")
	if not is_finite(north_m) or not is_finite(east_m) \
			or typeof(rects_value) != TYPE_PACKED_FLOAT64_ARRAY \
			or not GroundTerrain.is_valid_surface_table(rects_value):
		return invalid
	var rects: PackedFloat64Array = rects_value
	var lake_value: Variant = course.get("lake", {})
	if typeof(lake_value) != TYPE_DICTIONARY:
		return invalid
	var lake: Dictionary = lake_value
	var terrain: PackedFloat64Array = GroundTerrain.sample_validated(north_m, east_m, rects, lake)
	if terrain.size() != 3 or not is_finite(terrain[0]) or not is_finite(terrain[1]) or not is_finite(terrain[2]):
		return invalid
	var track: Dictionary = course.get("track", {})
	var overlay := Track.sample(track, north_m, east_m)
	terrain[0] += float(overlay.height_m)
	terrain[1] += float(overlay.dn)
	terrain[2] += float(overlay.de)
	var normal := PackedFloat64Array([-terrain[1], -terrain[2], -1.0])
	var magnitude := M.sqrt_(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
	if not is_finite(magnitude) or magnitude <= 0.0:
		return invalid
	for axis in normal.size():
		normal[axis] /= magnitude
	var offset := GroundContact.surface_at(rects, north_m, east_m)
	if offset < 0 or offset + GroundTerrain.SURFACE_STRIDE > rects.size():
		return invalid
	var row_index := int(offset / GroundTerrain.SURFACE_STRIDE)
	var surface_rows: Variant = course.get("surface_rows", [])
	if typeof(surface_rows) != TYPE_ARRAY or row_index >= surface_rows.size() \
			or typeof(surface_rows[row_index]) != TYPE_DICTIONARY:
		return invalid
	var row: Dictionary = surface_rows[row_index]
	var mu := REFERENCE_DRY_PAVEMENT_MU * rects[offset + 4]
	var rolling := rects[offset + 5]
	var coverage := float(overlay.coverage)
	if coverage > 0.0:
		mu = lerpf(mu, float(track.mu), coverage)
		rolling = lerpf(rolling, float(track.rolling), coverage)
	if not is_finite(mu) or mu <= 0.0 or not is_finite(rolling) or rolling < 0.0:
		return invalid
	var bounds_value: Variant = course.get("bounds", {})
	var in_bounds := false
	if typeof(bounds_value) == TYPE_DICTIONARY:
		in_bounds = north_m >= float(bounds_value.get("north_min_m", INF)) \
			and north_m <= float(bounds_value.get("north_max_m", -INF)) \
			and east_m >= float(bounds_value.get("east_min_m", INF)) \
			and east_m <= float(bounds_value.get("east_max_m", -INF))
	return {
		"height_m": terrain[0],
		"normal_ned": normal,
		"mu": mu,
		"rolling": rolling,
		"surface_id": "rc_dirt" if coverage >= 0.5 else str(row.get("id", "outside")),
		"in_bounds": in_bounds,
		"feature_id": str(overlay.feature_id),
		"feature_ids": [] if str(overlay.feature_id).is_empty() else [str(overlay.feature_id)],
		"track_coverage": coverage,
		"walls": Track.nearby_walls(track, north_m, east_m),
	}


func _summary(durations: PackedFloat64Array) -> Dictionary:
	var sorted := durations.duplicate()
	sorted.sort()
	var total := 0.0
	for duration in sorted:
		total += duration
	return {"samples": sorted.size(), "mean_us": total / sorted.size(),
		"median_us": sorted[sorted.size() / 2], "p95_us": sorted[int(float(sorted.size() - 1) * 0.95)],
		"maximum_us": sorted[-1]}


func _minimum(values: PackedFloat64Array) -> float:
	var result := INF
	for value in values:
		result = minf(result, value)
	return result


func _fail(message: String) -> void:
	printerr("ERROR: " + message)
	quit(1)
