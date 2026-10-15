extends SceneTree

const BaselineAdapter = preload("res://../research/rc-monster-truck/monster-car-2/rcv37/baseline_model.gd")
const CandidateAdapter = preload("res://vehicles/ground/monster_car_2_model.gd")
const BASELINE_SOURCE := "res://../research/rc-monster-truck/monster-car-2/rcv37/baseline_model.gd"
const CANDIDATE_SOURCE := "res://vehicles/ground/monster_car_2_model.gd"
const HARNESS_SOURCE := "res://../research/rc-monster-truck/monster-car-2/rcv37/bench_visual.gd"
const PINNED_BASELINE_SHA256 := "9eb05dc91d757fc61a4b3fab9757a0e4f05a2e6912c8614677cbe2f1a8296db7"
const MODEL_SOURCE := "res://data/vehicles/ground/monster_car_2.json"
const ENGINE_PHASE_KEY := "engine_phase_rad"
const STATE_TRAVEL_START := 13
const STATE_WHEEL_ANGLE_START := 25
const STEER_STATE_INDEX := 29
const CORNERS := ["FL", "FR", "RL", "RR"]
const TRAVEL_LOW_M := -0.044
const TRAVEL_HIGH_M := 0.036
const WARMUP_PASSES := 6
const TIMED_PASSES := 40
const TIMING_ROUNDS := 3
const SEEDED_PARITY_COUNT := 128
const PARITY_SEED := 0x37C0FFEE

var _output_path := ""
var _report: Dictionary = {}
var _seed_state: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_arguments()
	_report = {
		"schema": "rcv37-monster-car-2-visual-bench-v1",
		"complete": false,
		"baseline_sha256": _source_sha256(BASELINE_SOURCE),
		"candidate_sha256": _source_sha256(CANDIDATE_SOURCE),
		"harness_sha256": _source_sha256(HARNESS_SOURCE),
		"pinned_baseline_sha256": PINNED_BASELINE_SHA256,
		"pinned_baseline_sha256_check": false,
	}
	var baseline_hash := str(_report.baseline_sha256).to_lower()
	_report.baseline_sha256 = baseline_hash
	_report.candidate_sha256 = str(_report.candidate_sha256).to_lower()
	_report.harness_sha256 = str(_report.harness_sha256).to_lower()
	_report.pinned_baseline_sha256_check = baseline_hash == PINNED_BASELINE_SHA256
	if not _report.pinned_baseline_sha256_check:
		_fail("Pinned baseline SHA-256 mismatch (expected %s, got %s)" % [PINNED_BASELINE_SHA256, baseline_hash])
		return
	if str(_report.candidate_sha256).is_empty() or str(_report.harness_sha256).is_empty():
		_fail("Could not calculate source SHA-256 for candidate or harness")
		return
	var visual: Dictionary = CandidateAdapter.build()
	if not visual.get("ok", false):
		_fail("Candidate visual build failed: " + str(visual.get("error", "unknown error")))
		return
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODEL_SOURCE))
	if typeof(source) != TYPE_DICTIONARY:
		_fail("Monster Car 2 model data could not be read")
		return
	var parameters: Dictionary = source.get("parameters", {})
	var cg_height := float(parameters.get("cg_height_above_chassis_datum_m", {}).get("value", NAN))
	var max_steer := float(parameters.get("max_steer_angle_rad", {}).get("value", NAN))
	var powertrain: Dictionary = source.get("powertrain", {})
	var powertrain_parameters: Dictionary = powertrain.get("parameters", {})
	var gear_ratio := float(powertrain_parameters.get("gear_ratio", {}).get("value", 0.0))
	if not is_finite(cg_height) or not is_finite(max_steer):
		_fail("Monster Car 2 CG or steering metadata is invalid")
		return
	if not is_finite(gear_ratio) or gear_ratio <= 0.0:
		_fail("Monster Car 2 gear ratio is missing or not positive; bell-drive parity would be incomplete")
		return
	visual.cg_offset = Vector3(
		float(parameters.get("cg_right_from_datum_m", {}).get("value", 0.0)),
		cg_height,
		-float(parameters.get("cg_forward_from_datum_m", {}).get("value", 0.0)),
	)
	visual["gear_ratio"] = gear_ratio
	root.add_child(visual.root)
	await process_frame
	var timing_poses := _make_poses(max_steer)
	var parity_poses := _make_parity_poses(max_steer, timing_poses)
	_report["gear_ratio"] = gear_ratio
	_report["parity"] = {
		"passed": false,
		"seed": PARITY_SEED,
		"seeded_interior_pose_count": SEEDED_PARITY_COUNT,
		"timing_pose_count": timing_poses.size(),
		"total_pose_count": parity_poses.size(),
		"poses": [],
	}
	if not _check_pose_parity(visual, parity_poses, cg_height):
		return
	_report.parity.passed = true
	if not _benchmark(visual, timing_poses, cg_height):
		return
	visual.root.queue_free()
	_report.complete = true
	if not _write_report():
		_report.complete = false
		quit(1)
		return
	print("Monster Car 2 visual RCV-37 parity/timing harness completed: %d parity poses (%d timed), gear_ratio=%.6f" % [
		parity_poses.size(), timing_poses.size(), gear_ratio,
	])
	quit(0)


func _parse_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output_path = argument.substr("--output=".length())


func _source_sha256(path: String) -> String:
	return FileAccess.get_sha256(path).to_lower()


func _make_poses(max_steer: float) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	var neutral_travel := [0.0, 0.0, 0.0, 0.0]
	var neutral_wheels := [0.0, 0.0, 0.0, 0.0]
	_add_pose(poses, "neutral", neutral_travel, 0.0, neutral_wheels, 0.0)
	for corner_index in CORNERS.size():
		var low := neutral_travel.duplicate()
		low[corner_index] = TRAVEL_LOW_M
		_add_pose(poses, "droop_" + CORNERS[corner_index], low, 0.0, neutral_wheels, 0.41 * (corner_index + 1))
		var high := neutral_travel.duplicate()
		high[corner_index] = TRAVEL_HIGH_M
		_add_pose(poses, "bump_" + CORNERS[corner_index], high, 0.0, neutral_wheels, -0.37 * (corner_index + 1))
	_add_pose(poses, "all_droop", [TRAVEL_LOW_M, TRAVEL_LOW_M, TRAVEL_LOW_M, TRAVEL_LOW_M], 0.0, neutral_wheels, 1.1)
	_add_pose(poses, "all_bump", [TRAVEL_HIGH_M, TRAVEL_HIGH_M, TRAVEL_HIGH_M, TRAVEL_HIGH_M], 0.0, neutral_wheels, -1.3)
	_add_pose(poses, "opposed_corners", [TRAVEL_LOW_M, TRAVEL_HIGH_M, TRAVEL_HIGH_M, TRAVEL_LOW_M], 0.0, neutral_wheels, 0.0)
	_add_pose(poses, "mixed_interior_right", [-0.013, 0.021, -0.032, 0.009], max_steer * 0.52,
		[0.31, -0.74, 1.29, -2.10], 0.73, 0.47)
	_add_pose(poses, "mixed_interior_left", [0.024, -0.018, 0.007, -0.039], -max_steer * 0.61,
		[-1.08, 0.29, -2.41, 0.85], 3.17, -0.33)
	_add_pose(poses, "steer_right_limit", neutral_travel, max_steer,
		[1.1, 1.1, -0.5, -0.5], 2.2, 0.21)
	_add_pose(poses, "steer_left_limit", neutral_travel, -max_steer,
		[-0.7, -0.7, 0.9, 0.9], 4.9, -0.18)
	_add_pose(poses, "spin_opposite_phase", [0.011, 0.018, -0.006, -0.012], 0.0,
		[-5.2, 2.6, 8.4, -3.7], 5.7, 1.03)
	_add_pose(poses, "spin_same_phase", [0.011, 0.018, -0.006, -0.012], 0.0,
		[5.2, -2.6, -8.4, 3.7], 0.19, -0.87)
	return poses


func _make_parity_poses(max_steer: float, timing_poses: Array[Dictionary]) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	poses.append_array(timing_poses)
	for boundary_mask in 16:
		var travel := []
		for corner_index in CORNERS.size():
			travel.append(TRAVEL_HIGH_M if (boundary_mask & (1 << corner_index)) != 0 else TRAVEL_LOW_M)
		var steer_values := [-max_steer, 0.0, max_steer]
		var steer: float = steer_values[boundary_mask % 3]
		_add_pose(poses, "boundary_%02d" % boundary_mask, travel, steer,
			[0.13 * boundary_mask, -0.17 * boundary_mask, 0.23 * boundary_mask, -0.29 * boundary_mask],
			0.31 * boundary_mask, -0.07 * boundary_mask)
	for corner_index in CORNERS.size():
		var below_low := [0.0, 0.0, 0.0, 0.0]
		below_low[corner_index] = TRAVEL_LOW_M - 0.008
		_add_pose(poses, "out_of_art_%s_below" % CORNERS[corner_index], below_low, 0.0,
			[0.7, -0.4, 1.1, -1.3], 0.3 * corner_index)
		var above_high := [0.0, 0.0, 0.0, 0.0]
		above_high[corner_index] = TRAVEL_HIGH_M + 0.008
		_add_pose(poses, "out_of_art_%s_above" % CORNERS[corner_index], above_high, 0.0,
			[-0.8, 0.6, -1.2, 1.4], -0.4 * corner_index)
	_add_pose(poses, "out_of_art_steer_right", [0.0, 0.0, 0.0, 0.0], max_steer + 0.2,
		[2.1, -1.8, 0.9, -0.7], 1.7)
	_add_pose(poses, "out_of_art_steer_left", [0.0, 0.0, 0.0, 0.0], -max_steer - 0.2,
		[-2.1, 1.8, -0.9, 0.7], -1.7)
	_add_pose(poses, "out_of_art_combined", [TRAVEL_LOW_M - 0.01, TRAVEL_HIGH_M + 0.01,
		TRAVEL_LOW_M - 0.01, TRAVEL_HIGH_M + 0.01], max_steer + 0.2,
		[9.4, -8.6, 7.8, -6.2], 2.6, 0.52)
	poses.append_array(_make_seeded_interior_poses(max_steer))
	return poses


func _make_seeded_interior_poses(max_steer: float) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	_seed_state = PARITY_SEED
	for pose_index in SEEDED_PARITY_COUNT:
		var travel := []
		var wheel_angles := []
		for _corner_index in CORNERS.size():
			travel.append(lerpf(TRAVEL_LOW_M + 0.0001, TRAVEL_HIGH_M - 0.0001, _random_unit()))
			wheel_angles.append(lerpf(-24.0, 24.0, _random_unit()))
		var steer := lerpf(-max_steer * 0.97, max_steer * 0.97, _random_unit())
		var phase := lerpf(-PI, PI, _random_unit())
		var yaw := lerpf(-PI, PI, _random_unit())
		_add_pose(poses, "seeded_interior_%03d" % pose_index, travel, steer, wheel_angles, phase, yaw)
	return poses


func _random_unit() -> float:
	_seed_state = (_seed_state * 1664525 + 1013904223) & 0xffffffff
	return float(_seed_state) / 4294967296.0


func _add_pose(poses: Array[Dictionary], pose_name: String, travel: Array, steer: float,
		wheel_angles: Array, engine_phase: float, yaw_rad: float = 0.0) -> void:
	var state := PackedFloat64Array()
	state.resize(33)
	state[6] = cos(yaw_rad * 0.5)
	state[9] = sin(yaw_rad * 0.5)
	for corner_index in CORNERS.size():
		state[STATE_TRAVEL_START + corner_index] = float(travel[corner_index])
		state[STATE_WHEEL_ANGLE_START + corner_index] = float(wheel_angles[corner_index])
	state[STEER_STATE_INDEX] = steer
	poses.append({"name": pose_name, "state": state, "engine_phase": engine_phase})


func _check_pose_parity(visual: Dictionary, poses: Array[Dictionary], cg_height: float) -> bool:
	for pose: Dictionary in poses:
		var state: PackedFloat64Array = pose.state
		var state_signature := var_to_bytes(state)
		visual[ENGINE_PHASE_KEY] = float(pose.engine_phase)
		if not BaselineAdapter.draw(visual, state, cg_height):
			_fail("Baseline draw failed at pose " + str(pose.name))
			return false
		var baseline_snapshot := _mesh_snapshot(visual)
		var baseline_outside := bool(visual.get("travel_outside_art", false))
		visual[ENGINE_PHASE_KEY] = float(pose.engine_phase)
		if not CandidateAdapter.draw(visual, state, cg_height):
			_fail("Candidate draw failed at pose " + str(pose.name))
			return false
		var candidate_snapshot := _mesh_snapshot(visual)
		if not _bytes_equal(state_signature, var_to_bytes(state)):
			_fail("Adapter mutated physics state at pose " + str(pose.name))
			return false
		var candidate_outside := bool(visual.get("travel_outside_art", false))
		if baseline_outside != candidate_outside:
			_fail("travel_outside_art differs at pose " + str(pose.name))
			return false
		if not _snapshots_equal(baseline_snapshot, candidate_snapshot):
			_fail("Mesh transform/visibility mismatch at pose %s (baseline %s; candidate %s)" % [
				str(pose.name), baseline_snapshot.sha256, candidate_snapshot.sha256,
			])
			return false
		var pose_report := {
			"name": str(pose.name),
			"mesh_sha256": str(candidate_snapshot.sha256).to_lower(),
			"travel_outside_art": candidate_outside,
		}
		_report.parity.poses.append(pose_report)
		print("PARITY %s mesh_sha256=%s outside_art=%s" % [
			str(pose.name), candidate_snapshot.sha256, str(candidate_outside),
		])
	return true


func _mesh_snapshot(visual: Dictionary) -> Dictionary:
	var mesh_nodes: Dictionary = visual.get("_mesh_nodes", {})
	var unique_meshes := {}
	for alias: String in mesh_nodes:
		var mesh := mesh_nodes[alias] as MeshInstance3D
		if mesh != null:
			unique_meshes[str(mesh.name)] = mesh
	var names: Array[String] = []
	for mesh_name: String in unique_meshes:
		names.append(mesh_name)
	names.sort()
	var signatures := {}
	var byte_stream := PackedByteArray()
	var root_signature := var_to_bytes(visual.root.transform)
	byte_stream.append_array(root_signature)
	for mesh_name in names:
		var mesh := unique_meshes[mesh_name] as MeshInstance3D
		var signature := var_to_bytes(mesh.transform)
		signature.append(1 if mesh.visible else 0)
		signature.append(1 if mesh.is_visible_in_tree() else 0)
		signatures[mesh_name] = signature
		byte_stream.append_array(mesh_name.to_utf8_buffer())
		byte_stream.append(0)
		byte_stream.append_array(signature)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(byte_stream)
	return {
		"names": names,
		"root_signature": root_signature,
		"signatures": signatures,
		"sha256": hashing.finish().hex_encode().to_lower(),
	}


func _snapshots_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.names != right.names or not _bytes_equal(left.root_signature, right.root_signature):
		return false
	for mesh_name: String in left.names:
		if not _bytes_equal(left.signatures[mesh_name], right.signatures[mesh_name]):
			return false
	return true


func _bytes_equal(left: PackedByteArray, right: PackedByteArray) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _benchmark(visual: Dictionary, poses: Array[Dictionary], cg_height: float) -> bool:
	for _pass_index in WARMUP_PASSES:
		for pose: Dictionary in poses:
			visual[ENGINE_PHASE_KEY] = float(pose.engine_phase)
			BaselineAdapter.draw(visual, pose.state, cg_height)
			visual[ENGINE_PHASE_KEY] = float(pose.engine_phase)
			CandidateAdapter.draw(visual, pose.state, cg_height)
	print("TIMING warmup_passes=%d measured_passes=%d rounds=%d poses=%d" % [
		WARMUP_PASSES, TIMED_PASSES, TIMING_ROUNDS, poses.size(),
	])
	var rounds: Array[Dictionary] = []
	for round_index in TIMING_ROUNDS:
		var baseline_timing: Dictionary
		var candidate_timing: Dictionary
		var order: Array[String] = []
		if round_index % 2 == 0:
			order = ["baseline", "candidate"]
			baseline_timing = _time_adapter(false, visual, poses, cg_height)
			if baseline_timing.is_empty():
				return false
			candidate_timing = _time_adapter(true, visual, poses, cg_height)
		else:
			order = ["candidate", "baseline"]
			candidate_timing = _time_adapter(true, visual, poses, cg_height)
			if candidate_timing.is_empty():
				return false
			baseline_timing = _time_adapter(false, visual, poses, cg_height)
		if baseline_timing.is_empty() or candidate_timing.is_empty():
			return false
		var round_report := {
			"round": round_index + 1,
			"order": order,
			"baseline": baseline_timing,
			"candidate": candidate_timing,
		}
		rounds.append(round_report)
		_print_timing(round_index + 1, "baseline", baseline_timing)
		_print_timing(round_index + 1, "candidate", candidate_timing)
		_report["timing"] = {
			"warmup_passes": WARMUP_PASSES,
			"measured_passes_per_round": TIMED_PASSES,
			"round_count": TIMING_ROUNDS,
			"pose_count": poses.size(),
			"rounds": rounds.duplicate(true),
		}
	return true


func _time_adapter(candidate: bool, visual: Dictionary, poses: Array[Dictionary], cg_height: float) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var call_count := 0
	for _pass_index in TIMED_PASSES:
		for pose: Dictionary in poses:
			visual[ENGINE_PHASE_KEY] = float(pose.engine_phase)
			var success: bool = CandidateAdapter.draw(visual, pose.state, cg_height) if candidate else BaselineAdapter.draw(visual, pose.state, cg_height)
			if not success:
				_fail("Timed draw failed for %s adapter at pose %s" % ["candidate" if candidate else "baseline", str(pose.name)])
				return {}
			call_count += 1
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	return {
		"elapsed_usec": elapsed_usec,
		"draw_calls": call_count,
		"usec_per_draw": float(elapsed_usec) / float(maxi(call_count, 1)),
	}


func _print_timing(round_index: int, label: String, timing: Dictionary) -> void:
	print("TIMING round=%d adapter=%s elapsed_usec=%d draw_calls=%d usec_per_draw=%.3f" % [
		round_index, label, int(timing.get("elapsed_usec", 0)), int(timing.get("draw_calls", 0)), float(timing.get("usec_per_draw", 0.0)),
	])


func _fail(message: String) -> void:
	_report["complete"] = false
	_report["error"] = message
	_write_report()
	push_error(message)
	quit(1)


func _write_report() -> bool:
	if _report.is_empty():
		return true
	var serialized := JSON.stringify(_report, "\t", true, true)
	if _output_path.is_empty():
		return true
	var path := _output_path
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://" + path.trim_prefix("./"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write RCV-37 JSON report to %s (error %s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(serialized + "\n")
	file.close()
	return true
