## Research-only binding probe: expose the current reachable-bank predictor's
## sampled center path and feed the same points to StaticTrajectory.
## path_error_m=0 checks only this nominal polyline; it is not a physical bound.
extends SceneTree

const ProductionPilot := preload("res://ai/companions/pilot.gd")
const TraceCandidate := preload("res://../research/ai-companions/avoidance/predictor_trace_candidate.gd")
const Checker := preload("res://ai/companions/static_trajectory.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const RigidBody := preload("res://physics/rigid_body.gd")

const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const BASE_PILOT_RESOURCE := "res://ai/companions/pilot.gd"
const CANDIDATE_RESOURCE := "res://../research/ai-companions/avoidance/predictor_trace_candidate.gd"
const CHECKER_RESOURCE := "res://ai/companions/static_trajectory.gd"
const HARNESS_RESOURCE := "res://../research/ai-companions/avoidance/test_predictor_static_containment.gd"
const STEP_S := 0.25
const HORIZON_S := 8.0
const PATH_ERROR_M := 0.0

var _checks := 0
var _failures := 0
var _output_path := ""
var _fixture_results: Array[Dictionary] = []
var _score_parity: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
		if argument == "--parse-only":
			print("PREDICTOR STATIC CONTAINMENT PROBE PARSE OK")
			quit(0)
			return
	if not _is_absolute(_output_path):
		_fail("Supply an absolute --out path.")
		return

	var field_result: Dictionary = FieldLoader.load_from()
	var aircraft_result: Dictionary = AircraftData.load_file(STIK_PATH)
	var table_result: Dictionary = GroundSurfaces.load_table()
	var lake_result: Dictionary = LakeLoader.load_from()
	_check("real field, Stik, surface table and lake load",
		bool(field_result.get("ok", false)) and bool(aircraft_result.get("ok", false))
		and bool(table_result.get("ok", false)) and bool(lake_result.get("ok", false)))
	if _failures > 0:
		_finish({}, {}, {}, {}, PackedFloat64Array(), PackedFloat64Array(), {})
		return
	var field: Dictionary = field_result.field
	var model: Dictionary = aircraft_result.model
	var surfaces_result: Dictionary = GroundSurfaces.build(table_result.table, field)
	_check("normalized surface table builds", bool(surfaces_result.get("ok", false)))
	if _failures > 0:
		_finish({}, {}, {}, {}, PackedFloat64Array(), PackedFloat64Array(), {})
		return
	var surfaces: PackedFloat64Array = surfaces_result.rects
	var lake: Dictionary = lake_result.lake

	var empty_world: Dictionary = _world([], "predictor-static-empty")
	var context_checker := Checker.new()
	var context: Dictionary = context_checker.configure(field, empty_world, surfaces, lake, model, true)
	_check("checker accepts real terrain and empty synthetic scenery context", bool(context.get("ok", false)))
	if not bool(context.get("ok", false)):
		_finish({}, {}, {}, {}, PackedFloat64Array(), PackedFloat64Array(), {})
		return

	# Use a remote, high path so the fixture isolates static obstacle binding,
	# not the field's protected pilot area or its conservative global terrain cap.
	var north := float(field.pilot.north) + 5000.0
	var east := float(field.pilot.east) + 5000.0
	var ground_upper := float(context.ground_upper_m)
	var aircraft_radius := float(context.aircraft_radius_m)
	var height := ground_upper + aircraft_radius + Checker.TERRAIN_CLEARANCE_M + 100.0
	var clearance := height - ground_upper
	var state := PackedFloat64Array()
	state.resize(RigidBody.SIZE)
	state[RigidBody.POS] = north
	state[RigidBody.POS + 1] = east
	state[RigidBody.POS + 2] = -height
	# Deliberately synthetic 40 m/s makes the 0.25 s endpoint gap long enough to
	# test swept-segment coverage against the helper's full inflated envelope.
	var velocity := PackedFloat64Array([40.0, 0.0, 0.0])
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var empty_threats: Array[Dictionary] = []

	var production := ProductionPilot.new()
	var candidate := TraceCandidate.new()
	production.set("_planning_wind", wind)
	candidate.set("_planning_wind", wind)
	var production_without_trace: Dictionary = production.call("_score_bank", state, velocity, 40.0,
		0.0, 0.0, 0.0, clearance, empty_threats, false)
	var candidate_without_trace: Dictionary = candidate.call("_score_bank", state, velocity, 40.0,
		0.0, 0.0, 0.0, clearance, empty_threats, false)
	_check("trace disabled returns the production result dictionary exactly",
		production_without_trace == candidate_without_trace
		and not candidate_without_trace.has("predicted_own_positions_ned"))
	_score_parity.append({"fixture": "shared_synthetic_state", "trace_enabled": false,
		"exact_result_dictionary_match": production_without_trace == candidate_without_trace,
		"production_score_m": float(production_without_trace.get("score", NAN)),
		"candidate_score_m": float(candidate_without_trace.get("score", NAN))})
	var parity_cases: Array[Dictionary] = [
		{"id": "crosswind_turn", "velocity": PackedFloat64Array([35.0, 1.0, 0.0]),
			"wind": PackedFloat64Array([3.0, 2.0, 0.0]), "speed": 32.01562118716424,
			"current_bank": -0.08, "nominal_bank": 0.12, "candidate_bank": 0.26,
			"clearance": clearance},
		{"id": "descending_candidate", "velocity": PackedFloat64Array([18.0, 4.0, 0.8]),
			"wind": PackedFloat64Array([-1.0, 2.0, 0.0]), "speed": 19.1049731745428,
			"current_bank": 0.05, "nominal_bank": -0.1, "candidate_bank": -0.2,
			"clearance": clearance - 35.0},
	]
	for parity_case: Dictionary in parity_cases:
		var production_case: Dictionary = _score_result(ProductionPilot, state, parity_case.velocity,
			float(parity_case.speed), float(parity_case.current_bank), float(parity_case.nominal_bank),
			float(parity_case.candidate_bank), float(parity_case.clearance), parity_case.wind)
		var candidate_case: Dictionary = _score_result(TraceCandidate, state, parity_case.velocity,
			float(parity_case.speed), float(parity_case.current_bank), float(parity_case.nominal_bank),
			float(parity_case.candidate_bank), float(parity_case.clearance), parity_case.wind)
		var exact_match: bool = production_case == candidate_case
		_check("trace-disabled result matches production: %s" % str(parity_case.id), exact_match)
		_score_parity.append({"fixture": str(parity_case.id), "trace_enabled": false,
			"exact_result_dictionary_match": exact_match,
			"production_score_m": float(production_case.get("score", NAN)),
			"candidate_score_m": float(candidate_case.get("score", NAN))})

	var production_with_trace: Dictionary = production.call("_score_bank", state, velocity, 40.0,
		0.0, 0.0, 0.0, clearance, empty_threats, true)
	var candidate_with_trace: Dictionary = candidate.call("_score_bank", state, velocity, 40.0,
		0.0, 0.0, 0.0, clearance, empty_threats, true)
	var candidate_trace_without_path: Dictionary = candidate_with_trace.duplicate(true)
	candidate_trace_without_path.erase("predicted_own_positions_ned")
	var path: PackedFloat64Array = candidate_with_trace.get("predicted_own_positions_ned", PackedFloat64Array())
	_check("opt-in trace preserves all prior traced result fields exactly",
		production_with_trace == candidate_trace_without_path)
	_check("opt-in predictor trace has 33 sampled NED points",
		path.size() == (int(HORIZON_S / STEP_S) + 1) * 3
		and path[0] == north and path[1] == east and path[2] == -height)
	_score_parity.append({"fixture": "shared_synthetic_state", "trace_enabled": true,
		"prior_fields_exact_match_after_removing_new_path": production_with_trace == candidate_trace_without_path,
		"point_count": path.size() / 3})
	if path.size() < 6:
		_finish(context, production_without_trace, production_with_trace, candidate_with_trace,
			state, velocity, {wind = Array(wind), clearance_m = clearance})
		return

	var middle_north := 0.5 * (path[0] + path[3])
	var middle_east := 0.5 * (path[1] + path[4])
	var middle_down := 0.5 * (path[2] + path[5])
	var on_path_wall := _box("trace-on-path-wall", middle_north, middle_east, middle_down, 0.25)
	var off_path_wall := _box("trace-off-path-wall", middle_north, middle_east + 50.0, middle_down, 0.25)
	var on_path_world := _world([on_path_wall], "predictor-static-on-path-wall")
	var off_path_world := _world([off_path_wall], "predictor-static-off-path-wall")
	var clear_assessment := _assess(field, model, surfaces, lake, empty_world, path)
	var on_path_assessment := _assess(field, model, surfaces, lake, on_path_world, path)
	var off_path_assessment := _assess(field, model, surfaces, lake, off_path_world, path)
	var first_sample := PackedFloat64Array([path[0], path[1], path[2], path[0], path[1], path[2]])
	var second_sample := PackedFloat64Array([path[3], path[4], path[5], path[3], path[4], path[5]])
	var first_endpoint_assessment := _assess(field, model, surfaces, lake, on_path_world, first_sample)
	var second_endpoint_assessment := _assess(field, model, surfaces, lake, on_path_world, second_sample)
	_check("clear control route passes the static checker",
		bool(clear_assessment.get("ok", false)) and bool(clear_assessment.get("clear", false)), str(clear_assessment))
	_check("both sampled endpoints individually clear the same inflated wall",
		bool(first_endpoint_assessment.get("ok", false)) and bool(first_endpoint_assessment.get("clear", false))
		and bool(second_endpoint_assessment.get("ok", false)) and bool(second_endpoint_assessment.get("clear", false)),
		"first=%s second=%s" % [str(first_endpoint_assessment), str(second_endpoint_assessment)])
	_check("wall centered between first two samples blocks the same segment",
		bool(on_path_assessment.get("ok", false)) and not bool(on_path_assessment.get("clear", true))
		and str(on_path_assessment.get("reason", "")) == "static_obstacle"
		and str(on_path_assessment.get("proxy_id", "")) == "trace-on-path-wall", str(on_path_assessment))
	_check("off-path wall leaves the identical path clear",
		bool(off_path_assessment.get("ok", false)) and bool(off_path_assessment.get("clear", false)),
		str(off_path_assessment))
	_check("predictor score remains acceptable with no traffic in all three checker fixtures",
		float(production_without_trace.get("score", -INF)) >= 0.0)
	_fixture_results = [
		_fixture("clear_route", production_without_trace, clear_assessment),
		_fixture("on_path_wall_between_samples", production_without_trace, on_path_assessment),
		_fixture("off_path_wall_control", production_without_trace, off_path_assessment),
	]
	var setup := {
		"field_id": str(field.get("id", "")),
		"checker_context_identity": str(context.get("identity", "")),
		"world_proxy_count": 0,
		"ground_upper_m": ground_upper,
		"aircraft_radius_m": aircraft_radius,
		"state_ned_m": [north, east, -height],
		"own_velocity_ned_m_s": Array(velocity),
		"own_air_speed_m_s": 40.0,
		"wind_ned_m_s": Array(wind),
		"current_ground_clearance_m": clearance,
		"current_bank_rad": 0.0,
		"nominal_bank_rad": 0.0,
		"candidate_bank_rad": 0.0,
		"threat_count": 0,
		"horizon_s": HORIZON_S,
		"step_s": STEP_S,
		"sample_interval_count": path.size() / 3 - 1,
		"point_count": path.size() / 3,
		"path_error_m": PATH_ERROR_M,
		"path_error_interpretation": "Zero checks only the predictor's sampled nominal polyline; no tracking, prediction or interpolation error bound is inferred.",
		"path_sha256": _hash_packed(path),
		"between_sample_wall": {"segment_index": 0, "fraction": 0.5,
			"center_ned_m": [middle_north, middle_east, middle_down],
			"first_endpoint_clear": bool(first_endpoint_assessment.get("clear", false)),
			"second_endpoint_clear": bool(second_endpoint_assessment.get("clear", false)),
			"swept_segment_blocked": not bool(on_path_assessment.get("clear", true))},
	}
	_finish(context, production_without_trace, production_with_trace, candidate_with_trace,
		state, velocity, setup)


func _assess(field: Dictionary, model: Dictionary, surfaces: PackedFloat64Array, lake: Dictionary,
		world: Dictionary, points: PackedFloat64Array) -> Dictionary:
	var checker := Checker.new()
	var configured: Dictionary = checker.configure(field, world, surfaces, lake, model, world.proxies.is_empty())
	if not bool(configured.get("ok", false)):
		return {"ok": false, "clear": false, "reason": "configure_%s" % str(configured.get("reason", "unknown"))}
	return checker.assess(points, PATH_ERROR_M)


func _score_result(script: Script, state: PackedFloat64Array, velocity: PackedFloat64Array,
		own_speed: float, current_bank: float, nominal_bank: float, candidate_bank: float,
		clearance: float, wind: PackedFloat64Array) -> Dictionary:
	var pilot = script.new()
	pilot.set("_planning_wind", wind)
	var empty_threats: Array[Dictionary] = []
	return pilot.call("_score_bank", state, velocity, own_speed, current_bank, nominal_bank,
		candidate_bank, clearance, empty_threats, false)


func _fixture(name: String, prediction: Dictionary, assessment: Dictionary) -> Dictionary:
	return {
		"id": name,
		"predictor_score_m": float(prediction.get("score", NAN)),
		"predictor_terrain_margin_m": float(prediction.get("terrain_margin_m", NAN)),
		"path_error_m": PATH_ERROR_M,
		"assessment_ok": bool(assessment.get("ok", false)),
		"clear": bool(assessment.get("clear", false)),
		"reason": str(assessment.get("reason", "")),
		"proxy_id": str(assessment.get("proxy_id", "")),
		"terrain_margin_m": float(assessment.get("terrain_margin_m", NAN)),
		"candidate_proxies": int(assessment.get("candidate_proxies", 0)),
		"segment_checks": int(assessment.get("segment_checks", 0)),
	}


func _box(id: String, north: float, east: float, down: float, half_extent: float) -> Dictionary:
	return {
		"id": id, "kind": "building", "part": "fixture_wall", "shape": "box",
		"response_class": "rigid", "north": north, "east": east, "down": down,
		"radius": 1.0, "half_length": 0.0, "half_x": half_extent, "half_z": half_extent,
		"half_down": half_extent, "sin_heading": 0.0, "cos_heading": 1.0,
		"bounds_north_min": north - half_extent, "bounds_north_max": north + half_extent,
		"bounds_east_min": east - half_extent, "bounds_east_max": east + half_extent,
		"bounds_down_min": down - half_extent, "bounds_down_max": down + half_extent,
	}


func _world(proxies: Array, identity: String) -> Dictionary:
	return {"format": "openrc-collision-world v1", "identity": identity,
		"proxies": proxies, "bins": {}, "cell_size_m": 32.0}


func _finish(context: Dictionary, production_no_trace: Dictionary, production_trace: Dictionary,
		candidate_trace: Dictionary, state: PackedFloat64Array, velocity: PackedFloat64Array,
		setup: Dictionary) -> void:
	var report := {
		"format": "afc04-predictor-static-path-falsification-v1",
		"purpose": "Research-only binding probe for the current reachable-bank predictor and StaticTrajectory checker.",
		"claim_scope": "Falsification and data-binding evidence for a sampled nominal center polyline only. This is not controller flight equivalence, a physical safety result, or a validated error bound.",
		"all_checks_passed": _failures == 0,
		"check_count": _checks,
		"failure_count": _failures,
		"predictor_score_result_without_trace": _finite_result(production_no_trace),
		"predictor_trace_result_without_new_path_field": _finite_result(production_trace),
		"candidate_trace_result": _finite_result(candidate_trace),
		"score_parity": _score_parity,
		"setup": setup,
		"fixtures": _fixture_results,
		"source_sha256": {
			"production_pilot": _resource_hash(BASE_PILOT_RESOURCE),
			"trace_candidate": _resource_hash(CANDIDATE_RESOURCE),
			"static_checker": _resource_hash(CHECKER_RESOURCE),
			"harness": _resource_hash(HARNESS_RESOURCE),
			"aircraft_data": _resource_hash(STIK_PATH),
		},
		"static_context": _finite_result(context),
	}
	if not _output_path.is_empty():
		var file := FileAccess.open(_output_path, FileAccess.WRITE)
		if file == null:
			_fail("Could not write report to %s" % _output_path)
			quit(2)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("PREDICTOR STATIC CONTAINMENT: %d checks, %d failed; output=%s" % [
		_checks, _failures, _output_path,
	])
	quit(1 if _failures else 0)


func _finite_result(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	for key: Variant in result.keys():
		var item: Variant = result[key]
		if typeof(item) in [TYPE_FLOAT, TYPE_INT] and not is_finite(float(item)):
			result[key] = null
	return result


func _resource_hash(resource_path: String) -> String:
	return _sha256(ProjectSettings.globalize_path(resource_path))


func _sha256(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


func _hash_packed(values: PackedFloat64Array) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(values))
	return hash.finish().hex_encode()


func _is_absolute(path: String) -> bool:
	return path.is_absolute_path() or path.begins_with("\\\\")


func _check(description: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + description + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1
		printerr("FAIL ", description, " ", detail)


func _fail(message: String) -> void:
	printerr("PREDICTOR STATIC CONTAINMENT FAILED: ", message)
	quit(2)
