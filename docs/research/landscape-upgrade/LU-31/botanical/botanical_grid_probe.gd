extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Grass := preload("res://render/near_grass.gd")

const QUALITIES := ["low", "balanced", "high"]
const TIMED_PAIRS := 15
const TRANSLATION_NE_M := Vector2(128.0, -256.0)


func _initialize() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() < 2:
		printerr("usage: botanical_grid_probe.gd -- <baseline.gd> <report.json>")
		quit(2)
		return
	var baseline_path: String = str(user_args[0])
	var report_path: String = str(user_args[1])
	var baseline_source: String = FileAccess.get_file_as_string(baseline_path)
	if baseline_source.is_empty():
		printerr("cannot read baseline source: %s" % baseline_path)
		quit(2)
		return
	# Keep the archived baseline byte-for-byte intact while avoiding a duplicate global class name.
	var probe_baseline_path := baseline_path.get_base_dir().path_join("botanical_habitats.before_probe.gd")
	var probe_baseline_file := FileAccess.open(probe_baseline_path, FileAccess.WRITE)
	if probe_baseline_file == null:
		printerr("cannot write side-by-side baseline script: %s" % probe_baseline_path)
		quit(2)
		return
	probe_baseline_file.store_string(baseline_source.replace("class_name BotanicalHabitats", "# class_name omitted for side-by-side probe"))
	probe_baseline_file.close()
	var baseline_script := load(probe_baseline_path) as Script
	var candidate_script := load("res://scenery/botanical_habitats.gd") as Script
	if baseline_script == null or candidate_script == null:
		printerr("failed to load baseline or candidate botanical script")
		quit(2)
		return
	var baseline: Object = baseline_script.new()
	var candidate: Object = candidate_script.new()
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(field_result.get("ok", false)):
		printerr("default field failed to load: %s" % field_result.get("errors", []))
		quit(2)
		return
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	if not bool(scenery_result.get("ok", false)):
		printerr("default scenery failed to load: %s" % scenery_result.get("errors", []))
		quit(2)
		return
	var scenery: Dictionary = scenery_result.scenery
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not bool(lake_result.get("ok", false)):
		printerr("default lake failed to load: %s" % lake_result.get("errors", []))
		quit(2)
		return
	var lake: Dictionary = lake_result.lake
	var baseline_default: Array = baseline.call("layout", field, scenery, "high", lake)
	var custom_scenery := _with_targeted_gravel_exclusion(scenery, baseline_default)
	if custom_scenery.is_empty():
		printerr("could not choose an accepted non-shore placement for the custom exclusion case")
		quit(2)
		return
	var cases: Array[Dictionary] = [
		{"name": "default_lake", "field": field, "scenery": scenery, "lake": lake},
		{"name": "empty_lake", "field": field, "scenery": scenery, "lake": {}},
		{"name": "custom_exclusion", "field": field, "scenery": custom_scenery, "lake": lake},
		{
			"name": "translated_field",
			"field": _translate_field(field, TRANSLATION_NE_M),
			"scenery": _translate_scenery(scenery, TRANSLATION_NE_M),
			"lake": {},
		},
	]
	var results: Array[Dictionary] = []
	var failures: Array[String] = []
	var custom_case_effect := false
	for case_index in cases.size():
		var case: Dictionary = cases[case_index]
		var case_field: Dictionary = case.field
		var case_scenery: Dictionary = case.scenery
		var case_lake: Dictionary = case.lake
		var exclusions: Array = baseline.call("exclusions_for", case_scenery, case_lake)
		var grid_cells := Grass._build_exclusion_grid(exclusions).size()
		for quality_index in QUALITIES.size():
			var quality: String = QUALITIES[quality_index]
			var warm_before: Array = baseline.call("layout", case_field, case_scenery, quality, case_lake)
			var warm_after: Array = candidate.call("layout", case_field, case_scenery, quality, case_lake)
			var warm_difference := _first_difference(warm_before, warm_after, "plants")
			if not warm_difference.is_empty():
				failures.append("%s/%s warm parity: %s" % [case.name, quality, warm_difference])
			var before_samples: Array[float] = []
			var after_samples: Array[float] = []
			for pair_index in TIMED_PAIRS:
				var before_plants: Array
				var after_plants: Array
				var before_elapsed_usec: int
				var after_elapsed_usec: int
				var candidate_first := (pair_index + case_index + quality_index) % 2 == 1
				if candidate_first:
					after_elapsed_usec = _timed_layout(candidate, case_field, case_scenery, quality, case_lake, after_plants)
					before_elapsed_usec = _timed_layout(baseline, case_field, case_scenery, quality, case_lake, before_plants)
				else:
					before_elapsed_usec = _timed_layout(baseline, case_field, case_scenery, quality, case_lake, before_plants)
					after_elapsed_usec = _timed_layout(candidate, case_field, case_scenery, quality, case_lake, after_plants)
				var difference := _first_difference(before_plants, after_plants, "plants")
				if not difference.is_empty():
					failures.append("%s/%s pair %d parity: %s" % [case.name, quality, pair_index, difference])
				before_samples.append(float(before_elapsed_usec) / 1000.0)
				after_samples.append(float(after_elapsed_usec) / 1000.0)
			if case.name == "custom_exclusion" and quality == "high":
				custom_case_effect = not _same_value(warm_before, baseline_default)
			results.append({
				"case": case.name,
				"quality": quality,
				"grid_cells": grid_cells,
				"plant_count_before": warm_before.size(),
				"plant_count_after": warm_after.size(),
				"parity": warm_difference.is_empty(),
				"before_median_ms": _median(before_samples),
				"after_median_ms": _median(after_samples),
				"timed_pairs": TIMED_PAIRS,
			})
	if not custom_case_effect:
		failures.append("custom gravel polygon did not alter the default-lake high-tier layout")
	for item: Dictionary in results:
		if int(item.grid_cells) <= 0:
			failures.append("%s has no exclusion-grid cells; indexed path was not exercised" % item.case)
	var report := {
		"format": "botanical-exclusion-grid-probe v1",
		"baseline_path": baseline_path,
		"baseline_source_sha256": baseline_source.sha256_text(),
		"candidate_source_sha256": FileAccess.get_file_as_string(
			ProjectSettings.globalize_path("res://scenery/botanical_habitats.gd")).sha256_text(),
		"alternation": "before-first and after-first pairs alternate by pair, case, and quality",
		"timed_pairs": TIMED_PAIRS,
		"custom_exclusion_effect": custom_case_effect,
		"failures": failures,
		"results": results,
	}
	var output_file := FileAccess.open(report_path, FileAccess.WRITE)
	if output_file == null:
		printerr("cannot write probe report: %s" % report_path)
		quit(2)
		return
	output_file.store_string(JSON.stringify(report, "\t") + "\n")
	output_file.close()
	print(JSON.stringify(report))
	print("BOTANICAL_GRID_PROBE_COMPLETE")
	quit(1 if not failures.is_empty() else 0)


func _timed_layout(source: Object, field: Dictionary, scenery: Dictionary, quality: String,
		lake: Dictionary, output: Array) -> int:
	var start_usec := Time.get_ticks_usec()
	output.assign(source.call("layout", field, scenery, quality, lake))
	return Time.get_ticks_usec() - start_usec


func _with_targeted_gravel_exclusion(scenery: Dictionary, plants: Array) -> Dictionary:
	var target: Dictionary = {}
	for plant_value: Variant in plants:
		if plant_value is Dictionary and str(plant_value.get("zone", "")) != "shore":
			target = plant_value
			break
	if target.is_empty():
		return {}
	var north := float(target.north)
	var east := float(target.east)
	var half_size := 0.5
	var custom := scenery.duplicate(true)
	var groups: Array = custom.get("groups", [])
	groups.append({
		"id": "botanical_grid_probe_exclusion",
		"type": "patch",
		"surface": "gravel",
		"points": PackedVector2Array([
			Vector2(north - half_size, east - half_size),
			Vector2(north - half_size, east + half_size),
			Vector2(north + half_size, east + half_size),
			Vector2(north + half_size, east - half_size),
		]),
	})
	custom["groups"] = groups
	return custom


func _translate_field(source: Dictionary, offset: Vector2) -> Dictionary:
	var result := source.duplicate(true)
	var pilot: Dictionary = result.get("pilot", {})
	if pilot.has("north"):
		pilot["north"] = float(pilot.north) + offset.x
	if pilot.has("east"):
		pilot["east"] = float(pilot.east) + offset.y
	result["pilot"] = pilot
	var surfaces: Array = result.get("surfaces", [])
	for surface_value: Variant in surfaces:
		if not surface_value is Dictionary:
			continue
		var surface: Dictionary = surface_value
		if surface.has("center_north"):
			surface["center_north"] = float(surface.center_north) + offset.x
		if surface.has("center_east"):
			surface["center_east"] = float(surface.center_east) + offset.y
	var cues: Array = result.get("flight_cues", [])
	for cue_value: Variant in cues:
		if not cue_value is Dictionary:
			continue
		var cue: Dictionary = cue_value
		if cue.has("north"):
			cue["north"] = float(cue.north) + offset.x
		if cue.has("east"):
			cue["east"] = float(cue.east) + offset.y
	return result


func _translate_scenery(source: Dictionary, offset: Vector2) -> Dictionary:
	var result := source.duplicate(true)
	var groups: Array = result.get("groups", [])
	for group_value: Variant in groups:
		if not group_value is Dictionary:
			continue
		var group: Dictionary = group_value
		var group_type := str(group.get("type", ""))
		if group_type == "instances":
			var placements: Array = group.get("placements", [])
			for placement_value: Variant in placements:
				if not placement_value is Dictionary:
					continue
				var placement: Dictionary = placement_value
				if placement.has("north"):
					placement["north"] = float(placement.north) + offset.x
				if placement.has("east"):
					placement["east"] = float(placement.east) + offset.y
		elif group_type == "track" or group_type == "patch":
			group["points"] = _translate_points(group.get("points", []), offset)
	result["groups"] = groups
	return result


func _translate_points(value: Variant, offset: Vector2) -> Variant:
	if value is PackedVector2Array:
		var result: PackedVector2Array = value.duplicate()
		for index in result.size():
			result[index] += offset
		return result
	if typeof(value) != TYPE_ARRAY:
		return value
	var result: Array = value.duplicate(true)
	for index in result.size():
		var point: Variant = result[index]
		if point is Vector2:
			result[index] = point + offset
		elif typeof(point) == TYPE_ARRAY and (point as Array).size() == 2:
			var pair: Array = point
			pair[0] = float(pair[0]) + offset.x
			pair[1] = float(pair[1]) + offset.y
			result[index] = pair
	return result


func _same_value(left: Variant, right: Variant) -> bool:
	return _first_difference(left, right, "value").is_empty()


func _first_difference(left: Variant, right: Variant, path: String) -> String:
	if typeof(left) != typeof(right):
		return "%s type %d != %d" % [path, typeof(left), typeof(right)]
	if left is Dictionary:
		var left_dictionary: Dictionary = left
		var right_dictionary: Dictionary = right
		if left_dictionary.size() != right_dictionary.size():
			return "%s size %d != %d" % [path, left_dictionary.size(), right_dictionary.size()]
		for key: Variant in left_dictionary.keys():
			if not right_dictionary.has(key):
				return "%s missing key %s" % [path, str(key)]
			var difference := _first_difference(left_dictionary[key], right_dictionary[key], "%s.%s" % [path, str(key)])
			if not difference.is_empty():
				return difference
		return ""
	if left is Array:
		var left_array: Array = left
		var right_array: Array = right
		if left_array.size() != right_array.size():
			return "%s size %d != %d" % [path, left_array.size(), right_array.size()]
		for index in left_array.size():
			var difference := _first_difference(left_array[index], right_array[index], "%s[%d]" % [path, index])
			if not difference.is_empty():
				return difference
		return ""
	if typeof(left) == TYPE_FLOAT:
		var left_float := float(left)
		var right_float := float(right)
		if is_nan(left_float) or is_nan(right_float):
			return "" if is_nan(left_float) and is_nan(right_float) else "%s NaN mismatch" % path
		if is_inf(left_float) or is_inf(right_float):
			return "" if left_float == right_float else "%s infinity mismatch" % path
		return "" if left_float == right_float else "%s %s != %s" % [path, str(left_float), str(right_float)]
	return "" if left == right else "%s %s != %s" % [path, str(left), str(right)]


func _median(samples: Array[float]) -> float:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return 0.0
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) * 0.5
