## CPU-only parity and AB/BA timing for the imported near-grass placement reducer.
## Run headless against the app tree; timings are layout CPU time, never FPS claims.
extends SceneTree

const ImportedNearGrass := preload("res://scenery/imported_near_grass.gd")
const NearGrass := preload("res://render/near_grass.gd")
const Palette := preload("res://scenery/palette.gd")
const PlantLibrary := preload("res://scenery/imported_vegetation.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const FieldLoader := preload("res://data/field_loader.gd")

const REPORT_FORMAT := "openrc-grass-layout-benchmark v1"
const GRASS_QUALITY_ENV := "OPENRC_GRASS_QUALITY"

var _args: Dictionary = {}
var _checks: Array[Dictionary] = []
var _timings: Array[Dictionary] = []
var _failures := 0
var _check_count := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	for key: String in _args:
		if key not in ["mode", "grass-mode", "report"]:
			_fail("Unknown option: --" + key)
			_finish(1)
			return
	var mode := str(_args.get("mode", "check")).to_lower()
	if mode not in ["check", "benchmark", "all"]:
		_fail("--mode must be check, benchmark or all")
		_finish(1)
		return
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("default field failed validation: " + str(loaded.get("errors", [])))
		_finish(1)
		return
	var previous_quality := OS.get_environment(GRASS_QUALITY_ENV)
	var field: Dictionary = loaded.field
	var cases := _make_cases(field)
	if mode in ["check", "all"]:
		_run_parity(cases)
	if mode in ["benchmark", "all"]:
		var requested_profile := str(_args.get("grass-mode", "default")).to_lower()
		if requested_profile == "all" and mode == "all":
			for profile: String in ["default", "enhanced"]:
				_run_benchmarks(cases, profile)
		elif requested_profile in ["default", "enhanced"]:
			_run_benchmarks(cases, requested_profile)
		else:
			_fail("--grass-mode must be default, enhanced or all (all only with --mode=all)")
	_write_report()
	OS.set_environment(GRASS_QUALITY_ENV, previous_quality)
	print("Imported grass layout: %d checks, %d failed" % [_check_count, _failures])
	_finish(1 if _failures > 0 else 0)


func _make_cases(field: Dictionary) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var empty: Array = []
	cases.append({"id": "default_open", "field": field, "exclusions": empty})

	var translated: Dictionary = field.duplicate(true)
	_translate_field(translated, 137.25, -82.75)
	cases.append({"id": "translated_open", "field": translated, "exclusions": []})

	var boundary_field: Dictionary = field.duplicate(true)
	for surface: Dictionary in boundary_field.get("surfaces", []):
		if str(surface.get("type", "")) == "rough":
			surface["width_north_south"] = 52.0
			surface["length_east_west"] = 56.0
	cases.append({"id": "bounded_rough_field", "field": boundary_field, "exclusions": []})

	var anchor_plant := _first_selected_plant(field)
	var anchor := Vector2(float(anchor_plant.north), float(anchor_plant.east))
	var anchor_row_index := int(anchor_plant.row_index)
	var nearby_mask := _rectangle_mask("nearby", anchor, 1.2)
	var edge_mask := _edge_mask("edge", anchor)
	var far_mask := _rectangle_mask("outside_30m", Vector2(
		float(field.pilot.north) + 1000.0, float(field.pilot.east) - 1000.0), 2.0)
	cases.append({"id": "mask_near_selected_row", "field": field, "exclusions": [nearby_mask], "anchor_row_index": anchor_row_index})
	cases.append({"id": "mask_edge_through_selected_row", "field": field, "exclusions": [edge_mask], "anchor_row_index": anchor_row_index})
	cases.append({"id": "mask_bounds_outside_window", "field": field, "exclusions": [far_mask]})
	_check("mask edge fixture actually excludes its selected boundary point",
		not NearGrass.accepts(anchor.x, anchor.y, field, [edge_mask]))
	_check("far mask fixture lies outside the placement window",
		ImportedNearGrass._nearby_exclusions(float(field.pilot.north), float(field.pilot.east), [far_mask]).is_empty())
	return cases


func _first_selected_plant(field: Dictionary) -> Dictionary:
	var first: Array[Dictionary] = _legacy_layout(field, "high", [])
	if first.is_empty():
		return {"north": float(field.pilot.north), "east": float(field.pilot.east), "row_index": -1}
	return first[0]


func _rectangle_mask(mask_id: String, center: Vector2, half_extent: float) -> Dictionary:
	var points := PackedVector2Array([
		Vector2(center.x - half_extent, center.y - half_extent),
		Vector2(center.x - half_extent, center.y + half_extent),
		Vector2(center.x + half_extent, center.y + half_extent),
		Vector2(center.x + half_extent, center.y - half_extent),
	])
	return GrassMask._record(mask_id, "layout_benchmark", points)


func _edge_mask(mask_id: String, anchor: Vector2) -> Dictionary:
	var points := PackedVector2Array([
		Vector2(anchor.x, anchor.y - 1.0),
		Vector2(anchor.x, anchor.y + 1.0),
		Vector2(anchor.x + 1.0, anchor.y + 1.0),
		Vector2(anchor.x + 1.0, anchor.y - 1.0),
	])
	return GrassMask._record(mask_id, "layout_benchmark_edge", points)


func _translate_field(field: Dictionary, north_delta: float, east_delta: float) -> void:
	var pilot: Dictionary = field.get("pilot", {})
	pilot["north"] = float(pilot.get("north", 0.0)) + north_delta
	pilot["east"] = float(pilot.get("east", 0.0)) + east_delta
	for surface: Dictionary in field.get("surfaces", []):
		surface["center_north"] = float(surface.get("center_north", 0.0)) + north_delta
		surface["center_east"] = float(surface.get("center_east", 0.0)) + east_delta
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.has("north"):
			cue["north"] = float(cue.north) + north_delta
		if cue.has("east"):
			cue["east"] = float(cue.east) + east_delta


func _run_parity(cases: Array[Dictionary]) -> void:
	var rows: Array = ImportedNearGrass._placement_rows()
	_check("only the checksum-validated placement rows are present", rows.size() == NearGrass.COUNT)
	for profile: String in ["default", "enhanced"]:
		OS.set_environment(GRASS_QUALITY_ENV, "" if profile == "default" else profile)
		for case: Dictionary in cases:
			var field: Dictionary = case.field
			var exclusions: Array = case.exclusions
			for quality: String in ["low", "balanced", "high"]:
				var expected := _legacy_layout(field, quality, exclusions)
				var actual := ImportedNearGrass.layout(field, quality, exclusions)
				var same := actual == expected
				_check("%s/%s/%s exact legacy dictionary/order parity" % [profile, case.id, quality], same,
					"new=%d old=%d" % [actual.size(), expected.size()])
				if same:
					_check("%s/%s/%s source triangle total unchanged" % [profile, case.id, quality],
						_triangle_count(actual) == _triangle_count(expected))
				if case.id == "mask_near_selected_row" or case.id == "mask_edge_through_selected_row":
					_check("%s/%s/%s removes the fixture's selected row" % [profile, case.id, quality],
						_not_contains_row(actual, int(case.anchor_row_index)))
				_checks.append({
					"profile": profile,
					"case": str(case.id),
					"quality": quality,
					"placements": actual.size(),
					"source_triangles": _triangle_count(actual),
					"exact_parity": same,
				})
	# A far-away mask must be removed by the active-window bound and leave the layout identical.
	for profile: String in ["default", "enhanced"]:
		OS.set_environment(GRASS_QUALITY_ENV, "" if profile == "default" else profile)
		var open_layout := ImportedNearGrass.layout(cases[0].field, "high")
		var outside_mask_layout := ImportedNearGrass.layout(cases[5].field, "high", cases[5].exclusions)
		_check("%s far mask leaves output exact" % profile, outside_mask_layout == open_layout)
	_check("rank cache was rebuilt for the current 6,000-row validated source",
		ImportedNearGrass._ranked_row_count == rows.size()
		and ImportedNearGrass._ranked_row_keys_by_asset.size() == ImportedNearGrass.ASSET_IDS.size())
	var original_cache: Array = ImportedNearGrass._ranked_row_keys_by_asset.duplicate(true)
	var shortened_rows: Array = rows.duplicate(false)
	shortened_rows.resize(rows.size() - 1)
	var shortened_cache: Array = ImportedNearGrass._ranked_row_keys(shortened_rows)
	var shortened_key_count := 0
	for keys: PackedInt64Array in shortened_cache:
		shortened_key_count += keys.size()
	_check("rank cache rebuilds when row count changes",
		ImportedNearGrass._ranked_row_count == rows.size() - 1 and shortened_key_count == rows.size() - 1)
	var restored_cache: Array = ImportedNearGrass._ranked_row_keys(rows)
	_check("restoring the validated rows restores the original ranking exactly",
		ImportedNearGrass._ranked_row_count == rows.size() and restored_cache == original_cache)


func _legacy_layout(field: Dictionary, quality: String, exclusions: Array) -> Array[Dictionary]:
	var rows: Array = ImportedNearGrass._placement_rows()
	var result: Array[Dictionary] = []
	if rows.is_empty() or not field.has("pilot") or not field.has("surfaces"):
		return result
	var candidates_by_asset: Dictionary = {}
	var triangle_counts: Dictionary = {}
	for asset_id: String in ImportedNearGrass.ASSET_IDS:
		candidates_by_asset[asset_id] = []
		var asset := PlantLibrary.get_asset(asset_id)
		triangle_counts[asset_id] = int(asset.get("source_triangles", 0))
	var pilot: Dictionary = field.get("pilot", {})
	var pilot_north := float(pilot.get("north", 0.0))
	var pilot_east := float(pilot.get("east", 0.0))
	var local_exclusions := ImportedNearGrass._nearby_exclusions(pilot_north, pilot_east, exclusions)
	for row_index: int in range(rows.size()):
		var row: Array = rows[row_index]
		var north := pilot_north + float(row[0]) * 0.001
		var east := pilot_east + float(row[1]) * 0.001
		if not NearGrass.accepts(north, east, field, local_exclusions):
			continue
		var asset_index := int(Palette.hash01(ImportedNearGrass.SEED, row_index, 101) * float(ImportedNearGrass.ASSET_IDS.size()))
		var asset_id: String = ImportedNearGrass.ASSET_IDS[mini(asset_index, ImportedNearGrass.ASSET_IDS.size() - 1)]
		var source_triangles := int(triangle_counts.get(asset_id, 0))
		if source_triangles <= 0:
			continue
		var yaw_u16 := int(row[2])
		var size_u8 := int(row[3])
		(candidates_by_asset[asset_id] as Array).append({
			"asset_id": asset_id,
			"source_triangles": source_triangles,
			"row_index": row_index,
			"rank": int(Palette.hash01(ImportedNearGrass.SEED, row_index, 202) * 65536.0),
			"north": north,
			"east": east,
			"yaw_u16": yaw_u16,
			"yaw_rad": float(yaw_u16) * TAU / 65536.0,
			"size_u8": size_u8,
			"height_m": lerpf(ImportedNearGrass.MIN_HEIGHT_M, ImportedNearGrass.MAX_HEIGHT_M, float(size_u8) / 255.0),
			"seed": ImportedNearGrass.SEED + row_index,
		})
	var limits: Dictionary = ImportedNearGrass.ENHANCED_QUALITY_LIMITS if OS.get_environment(GRASS_QUALITY_ENV).strip_edges().to_lower() == "enhanced" else ImportedNearGrass.QUALITY_LIMITS
	var quality_limits: Dictionary = limits.get(quality, limits.high)
	var triangles := 0
	for asset_id: String in ImportedNearGrass.ASSET_IDS:
		var candidates: Array = candidates_by_asset[asset_id]
		candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_rank := int(left.get("rank", 0))
			var right_rank := int(right.get("rank", 0))
			if left_rank != right_rank:
				return left_rank < right_rank
			return int(left.get("row_index", 0)) < int(right.get("row_index", 0))
		)
		var keep_count := mini(int(quality_limits.get(asset_id, 0)), candidates.size())
		for candidate_index: int in range(keep_count):
			var candidate: Dictionary = candidates[candidate_index]
			triangles += int(candidate.source_triangles)
			result.append(candidate.duplicate(true))
	if triangles > ImportedNearGrass.MAX_SOURCE_TRIANGLES:
		return []
	return result


func _run_benchmarks(cases: Array[Dictionary], profile: String) -> void:
	OS.set_environment(GRASS_QUALITY_ENV, "" if profile == "default" else profile)
	for case_id: String in ["default_open", "bounded_rough_field", "mask_near_selected_row"]:
		var case := _find_case(cases, case_id)
		var field: Dictionary = case.field
		var exclusions: Array = case.exclusions
		var quality := "high"
		var cache_was_ready := ImportedNearGrass._ranked_row_count == NearGrass.COUNT
		var cold_start := Time.get_ticks_usec()
		var cold_result := ImportedNearGrass.layout(field, quality, exclusions)
		var cold_us := Time.get_ticks_usec() - cold_start
		var old_check := _legacy_layout(field, quality, exclusions)
		_check("%s/%s benchmark layout agrees with legacy" % [profile, case_id], cold_result == old_check)
		var old_samples: Array[int] = []
		var new_samples: Array[int] = []
		for warmup in 2:
			if warmup % 2 == 0:
				_legacy_layout(field, quality, exclusions)
				ImportedNearGrass.layout(field, quality, exclusions)
			else:
				ImportedNearGrass.layout(field, quality, exclusions)
				_legacy_layout(field, quality, exclusions)
		for sample_index in 9:
			if sample_index % 2 == 0:
				old_samples.append(_time_legacy(field, quality, exclusions))
				new_samples.append(_time_optimized(field, quality, exclusions))
			else:
				new_samples.append(_time_optimized(field, quality, exclusions))
				old_samples.append(_time_legacy(field, quality, exclusions))
		var old_raw := old_samples.duplicate()
		var new_raw := new_samples.duplicate()
		old_samples.sort()
		new_samples.sort()
		var old_median := old_samples[int(old_samples.size() / 2)]
		var new_median := new_samples[int(new_samples.size() / 2)]
		var timing := {
			"profile": profile,
			"case": case_id,
			"quality": quality,
			"legacy_median_ms": float(old_median) / 1000.0,
			"optimized_median_ms": float(new_median) / 1000.0,
			"optimized_first_call_ms": float(cold_us) / 1000.0,
			"rank_cache_prebuilt": cache_was_ready,
			"warm_median_speedup": float(old_median) / maxf(float(new_median), 1.0),
			"samples_per_algorithm": old_samples.size(),
			"legacy_usec_in_collection_order": old_raw,
			"optimized_usec_in_collection_order": new_raw,
			"order": "legacy/optimized on even zero-based indices; optimized/legacy on odd indices",
			"measurement": "headless layout CPU time; no FPS/render claim",
		}
		_timings.append(timing)
		print("LAYOUT TIMING ", JSON.stringify(timing))


func _find_case(cases: Array[Dictionary], case_id: String) -> Dictionary:
	for case: Dictionary in cases:
		if str(case.id) == case_id:
			return case
	return {}


func _time_legacy(field: Dictionary, quality: String, exclusions: Array) -> int:
	var start := Time.get_ticks_usec()
	_legacy_layout(field, quality, exclusions)
	return Time.get_ticks_usec() - start


func _time_optimized(field: Dictionary, quality: String, exclusions: Array) -> int:
	var start := Time.get_ticks_usec()
	ImportedNearGrass.layout(field, quality, exclusions)
	return Time.get_ticks_usec() - start


func _triangle_count(placements: Array[Dictionary]) -> int:
	var result := 0
	for plant: Dictionary in placements:
		result += int(plant.get("source_triangles", 0))
	return result


func _not_contains_row(placements: Array[Dictionary], row_index: int) -> bool:
	for plant: Dictionary in placements:
		if int(plant.get("row_index", -1)) == row_index:
			return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	_check_count += 1
	_checks.append({"label": label, "ok": condition, "detail": detail})
	if not condition:
		_failures += 1
		push_error("FAIL: %s %s" % [label, detail])


func _fail(message: String) -> void:
	_failures += 1
	push_error(message)


func _write_report() -> void:
	var report_path := str(_args.get("report", "")).strip_edges()
	if report_path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(report_path)
	if FileAccess.file_exists(absolute):
		_fail("report path already exists; refusing to overwrite evidence: " + absolute)
		return
	var report := {
		"format": REPORT_FORMAT,
		"godot": Engine.get_version_info(),
		"selector": OS.get_environment(GRASS_QUALITY_ENV),
		"source_file": "res://scenery/imported_near_grass.gd",
		"source_sha256": FileAccess.get_sha256("res://scenery/imported_near_grass.gd"),
		"tool_sha256": FileAccess.get_sha256(str(get_script().resource_path)),
		"validated_rows": NearGrass.COUNT,
		"check_count": _check_count,
		"failures": _failures,
		"checks": _checks,
		"timings": _timings,
	}
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		_fail("could not create report: " + absolute)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("LAYOUT REPORT ", absolute)


func _finish(exit_code: int) -> void:
	quit(exit_code)
