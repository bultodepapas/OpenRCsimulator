## Post-hoc geometry check for a real encounter-probe trajectory CSV.
## The 0.5 m allowance is only the polyline interpolation allowance; this does
## not claim to bound tracking error between 10 Hz samples or certify flight.
extends SceneTree

const Checker := preload("res://ai/companions/static_trajectory.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const SURVEY_ROOT := "D:/OpenRCsimulator-AFC-work/evidence/avoidance/"
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const INTERPOLATION_ALLOWANCE_M := 0.5

var _trajectory_path := ""
var _survey_report_path := ""
var _output_path := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--parse-only":
			print("STATIC PATH CHECK HARNESS PARSE OK")
			quit(0)
			return
		if argument.begins_with("--trajectory="):
			_trajectory_path = argument.trim_prefix("--trajectory=")
		elif argument.begins_with("--survey-report="):
			_survey_report_path = argument.trim_prefix("--survey-report=")
		elif argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
	if not _is_absolute(_trajectory_path) or not _is_absolute(_survey_report_path) or not _is_absolute(_output_path):
		_fail("Supply absolute --trajectory, --survey-report and --out paths.")
		return
	if not FileAccess.file_exists(_trajectory_path) or not FileAccess.file_exists(_survey_report_path):
		_fail("Trajectory CSV or survey report does not exist.")
		return
	var survey: Variant = JSON.parse_string(FileAccess.get_file_as_string(_survey_report_path))
	if typeof(survey) != TYPE_DICTIONARY or survey.get("format") != "openrc-companion-encounter-survey v1":
		_fail("Unrecognized encounter survey report.")
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from()
	var aircraft_result: Dictionary = AircraftData.load_file(STIK_PATH)
	var table_result: Dictionary = GroundSurfaces.load_table()
	if not field_result.get("ok", false) or not lake_result.get("ok", false) \
			or not aircraft_result.get("ok", false) or not table_result.get("ok", false):
		_fail("Field, lake, aircraft or surface data failed to load.")
		return
	var field: Dictionary = field_result.field
	var surfaces_result: Dictionary = GroundSurfaces.build(table_result.table, field)
	var world_result: Dictionary = CollisionSetup.build(field)
	if not surfaces_result.get("ok", false) or not world_result.get("ok", false):
		_fail("Survey geometry context failed to build.")
		return
	var world: Dictionary = world_result.world
	var lake: Dictionary = lake_result.lake
	if str(survey.get("field_id", "")) != str(field.get("id", "")) \
			or str(survey.get("collision_identity", "")) != str(world.get("identity", "")) \
			or str(survey.get("lake_identity", "")) != str(lake.get("identity", "")):
		_fail("Rebuilt field, collision or lake identity does not match the surveyed flight.")
		return
	var checker := Checker.new()
	var configured: Dictionary = checker.configure(field, world, surfaces_result.rects, lake, aircraft_result.model)
	if not configured.get("ok", false):
		_fail("Static checker context refused: %s" % str(configured.get("reason", "unknown")))
		return
	var rows_by_case: Dictionary = _read_ai_rows(_trajectory_path)
	if rows_by_case.is_empty():
		_fail("No AI trajectory rows found in CSV.")
		return
	var case_results: Array[Dictionary] = []
	var all_clear := true
	for case_id: String in rows_by_case.keys():
		var rows: Array = rows_by_case[case_id]
		var chunks: Array[Dictionary] = []
		var min_terrain_margin := INF
		var case_clear := true
		var start_index := 0
		while start_index < rows.size() - 1:
			var end_index: int = mini(start_index + Checker.MAX_POINTS - 1, rows.size() - 1)
			var path := PackedFloat64Array()
			for row_index: int in range(start_index, end_index + 1):
				var row: Dictionary = rows[row_index]
				path.append_array(PackedFloat64Array([
					float(row.north_m), float(row.east_m), -float(row.altitude_m),
				]))
			var result: Dictionary = checker.assess(path, INTERPOLATION_ALLOWANCE_M)
			var terrain_margin := float(result.get("terrain_margin_m", -INF))
			min_terrain_margin = minf(min_terrain_margin, terrain_margin)
			var clear := bool(result.get("ok", false)) and bool(result.get("clear", false))
			case_clear = case_clear and clear
			chunks.append({
				"first_time_s": rows[start_index].time_s,
				"last_time_s": rows[end_index].time_s,
				"point_count": end_index - start_index + 1,
				"clear": clear,
				"reason": result.get("reason", ""),
				"proxy_id": result.get("proxy_id", ""),
				"terrain_margin_m": terrain_margin,
				"candidate_proxies": result.get("candidate_proxies", 0),
				"segment_checks": result.get("segment_checks", 0),
			})
			start_index = end_index
		all_clear = all_clear and case_clear
		case_results.append({
			"case_id": case_id,
			"sample_count": rows.size(),
			"first_time_s": rows[0].time_s,
			"last_time_s": rows[-1].time_s,
			"minimum_polyline_terrain_margin_m": min_terrain_margin,
			"clear": case_clear,
			"chunks": chunks,
		})
	var report := {
		"format": "afc-reachable-observed-static-path-check-v1",
		"purpose": "Post-hoc static-geometry check of the AI's observed, sampled encounter path.",
		"interpretation": "Checks the supplied 10 Hz piecewise-linear center path with the static trajectory helper's conservative aircraft envelope and a caller-supplied 0.5 m interpolation allowance. The allowance covers only geometric approximation between polyline points; no controller tracking/prediction error bound is inferred. This does not assess dynamic aircraft conflicts or physical safety.",
		"all_paths_clear": all_clear,
		"interpolation_allowance_m": INTERPOLATION_ALLOWANCE_M,
		"checker_context": {
			"identity": configured.identity,
			"world_identity": world.identity,
			"proxy_count": configured.proxies,
			"protected_count": configured.protected,
			"aircraft_radius_m": configured.aircraft_radius_m,
			"ground_upper_m": configured.ground_upper_m,
		},
		"source_files": {
			"survey_report": {"path": _survey_report_path, "sha256": _sha256(_survey_report_path)},
			"trajectory_csv": {"path": _trajectory_path, "sha256": _sha256(_trajectory_path)},
			"checker": _resource_source("res://ai/companions/static_trajectory.gd"),
			"candidate_pilot": _resource_source(str(survey.get("pilot_resource", ""))),
			"parent_pilot": _resource_source("res://ai/companions/pilot.gd"),
			"survey_probe": _resource_source(str(survey.get("probe_resource", ""))),
			"field": _resource_source(FieldLoader.DEFAULT_PATH),
			"lake": _resource_source(LakeLoader.DEFAULT_PATH),
			"aircraft": _resource_source(STIK_PATH),
			"surface_table": _resource_source(GroundSurfaces.DEFAULT_PATH),
			"collision_setup": _resource_source("res://scenery/collision_setup.gd"),
			"encounter_probe": _resource_source(str(survey.get("probe_resource", ""))),
			"assessment_harness": _resource_source("res://../research/ai-companions/avoidance/assess_static_paths.gd"),
		},
		"cases": case_results,
	}
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		_fail("Could not write assessment output.")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("STATIC PATH CHECK identity=%s cases=%d all_clear=%s output=%s" % [
		str(configured.identity), case_results.size(), str(all_clear), _output_path,
	])
	quit(0 if all_clear else 1)

func _read_ai_rows(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var header := file.get_csv_line()
	var columns: Dictionary = {}
	for index: int in header.size():
		columns[str(header[index])] = index
	for name: String in ["case", "time_s", "role", "north_m", "east_m", "altitude_m"]:
		if not columns.has(name):
			return {}
	var output: Dictionary = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() != header.size() or row[columns.role] != "ai":
			continue
		var case_id := str(row[columns.case])
		var case_rows: Array = output.get(case_id, [])
		case_rows.append({
			"time_s": row[columns.time_s].to_float(),
			"north_m": row[columns.north_m].to_float(),
			"east_m": row[columns.east_m].to_float(),
			"altitude_m": row[columns.altitude_m].to_float(),
		})
		output[case_id] = case_rows
	file.close()
	for case_id: String in output:
		var case_rows: Array = output[case_id]
		case_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time_s < b.time_s)
	return output

func _resource_source(resource_path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(resource_path)
	return {"path": absolute, "sha256": _sha256(absolute)}

func _sha256(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _is_absolute(path: String) -> bool:
	return path.is_absolute_path() or path.begins_with("\\\\")

func _fail(message: String) -> void:
	printerr("STATIC PATH CHECK FAILED: ", message)
	quit(2)
