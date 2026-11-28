extends SceneTree

const PlannedCamera := preload("planned_camera.gd")


class RigStub extends RefCounted:
	var camera: Camera3D


class FlightStub extends Node:
	var _rig: RefCounted
	var _last_render_pose := {}
	var _airplane := {}
	var simulated_tick := 0
	var simulated_state := PackedFloat64Array([128.0, 55.0, -2.55, 23.0])
	var pilot_commands := {"roll": 0.1, "pitch": -0.2, "yaw": 0.0, "throttle": 0.7}


class FrameCallback extends Node:
	var callback := Callable()

	func _process(_delta: float) -> void:
		if callback.is_valid():
			callback.call()


class DirectorStub extends Node:
	var camera: Camera3D
	var processed := 0

	func _process(_delta: float) -> void:
		processed += 1
		camera.global_position = Vector3(1000.0, 10.0, 0.0)
		camera.fov = 15.0


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_recipe_validation()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--exported-recipe="):
			var path := argument.trim_prefix("--exported-recipe=")
			var exported: Dictionary = PlannedCamera.read_recipe_file(path)
			_check("exported recipe reads and retains its exact file hash", bool(exported.get("ok", false)) \
				and str(exported.get("sha256", "")) == FileAccess.get_sha256(path))
	var flight := FlightStub.new()
	var visual := Node3D.new()
	var camera := Camera3D.new()
	flight.add_child(visual)
	flight.add_child(camera)
	root.add_child(flight)
	visual.global_position = Vector3(400.0, 300.0, -200.0) # Deliberately not the CG.
	flight._airplane = {"root": visual}
	var rig := RigStub.new()
	rig.camera = camera
	flight._rig = rig
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	_test_parallel_tracking(flight, camera, visual)
	_test_fixed_tracking(flight, camera)
	_test_water_plane_tracking(flight, camera, visual)
	_test_frame_evidence(flight, camera)
	await _test_freshness_same_position(flight, camera)
	if OS.get_cmdline_user_args().has("--check-post-draw"):
		await _test_post_draw_freshness(flight, camera)
	await _test_composition(flight, camera)
	_test_failures(flight, rig, camera)
	flight.free()
	print("TRAILER_PLANNED_CAMERA checks=", _checks, " failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _base_recipe() -> Dictionary:
	return {
		"format": "openrc-trailer-camera", "version": 1, "shot_id": "R4-40",
		"vehicle_id": "f4u-corsair-250", "source_plan_sha256": "a".repeat(64),
		"mode": "parallel_east", "target": "presented_cg", "fov_deg": 42.0,
		"north_m": 145.0, "down_m": -1.0, "east_offset_m": -8.0,
	}


func _fixed_recipe() -> Dictionary:
	var recipe := _base_recipe()
	recipe.mode = "fixed_world"
	recipe.erase("north_m")
	recipe.erase("down_m")
	recipe.erase("east_offset_m")
	recipe["eye_ned_m"] = [145.0, 125.0, -1.0]
	return recipe


func _water_recipe() -> Dictionary:
	var recipe := _base_recipe()
	recipe.target = "presented_cg_water_plane"
	recipe["water_down_m"] = 0.45
	return recipe


func _test_recipe_validation() -> void:
	var recipe := _base_recipe()
	_check("parallel recipe is accepted", PlannedCamera.validate_recipe(recipe).is_empty())
	_check("fixed recipe is accepted", PlannedCamera.validate_recipe(_fixed_recipe()).is_empty())
	var water := _water_recipe()
	_check("parallel water-plane recipe is accepted", PlannedCamera.validate_recipe(water).is_empty())
	var fixed_water := _fixed_recipe()
	fixed_water.target = "presented_cg_water_plane"
	fixed_water["water_down_m"] = 0.45
	_check("fixed water-plane recipe is accepted", PlannedCamera.validate_recipe(fixed_water).is_empty())
	var missing_water := water.duplicate(true)
	missing_water.erase("water_down_m")
	_check("water-plane recipe requires water_down_m", not PlannedCamera.validate_recipe(missing_water).is_empty())
	for invalid: Variant in [100000.1, -100000.1, INF, NAN, "0.45", true, null]:
		var changed := water.duplicate(true)
		changed.water_down_m = invalid
		_check("invalid water plane is refused: " + str(invalid), not PlannedCamera.validate_recipe(changed).is_empty())
	for valid: float in [-100000.0, 100000.0]:
		var changed := water.duplicate(true)
		changed.water_down_m = valid
		_check("inclusive water-plane bound is accepted: " + str(valid), PlannedCamera.validate_recipe(changed).is_empty())
	var stray_water := recipe.duplicate(true)
	stray_water["water_down_m"] = 0.45
	_check("CG target refuses an extra water plane", not PlannedCamera.validate_recipe(stray_water).is_empty())
	var source := JSON.stringify(recipe).to_utf8_buffer()
	var parsed: Dictionary = PlannedCamera.parse_recipe_bytes(source)
	var with_space := source.duplicate()
	with_space.append(32)
	var parsed_with_space: Dictionary = PlannedCamera.parse_recipe_bytes(with_space)
	_check("validated recipe bytes yield a SHA-256", bool(parsed.get("ok", false)) \
		and str(parsed.get("sha256", "")).length() == 64 and str(parsed.recipe.shot_id) == "R4-40" \
		and float(parsed.recipe.version) == 1.0 and is_equal_approx(float(parsed.recipe.east_offset_m), -8.0))
	_check("input hash identifies exact bytes, including whitespace", bool(parsed_with_space.get("ok", false)) \
		and parsed.get("sha256") != parsed_with_space.get("sha256"))
	_check("malformed JSON is refused", not PlannedCamera.parse_recipe_bytes("{oops".to_utf8_buffer()).ok)
	_check("JSON arrays are refused", not PlannedCamera.parse_recipe_bytes("[]".to_utf8_buffer()).ok)
	_check("empty recipe is refused", not PlannedCamera.parse_recipe_bytes(PackedByteArray()).ok)
	_check("relative recipe paths are refused", not PlannedCamera.read_recipe_file("relative.json").ok)
	var recipe_path := ProjectSettings.globalize_path("user://camera-recipe-test-%d.json" % Time.get_ticks_usec())
	if not FileAccess.file_exists(recipe_path):
		var recipe_file := FileAccess.open(recipe_path, FileAccess.WRITE)
		if recipe_file != null:
			recipe_file.store_buffer(source)
			recipe_file.close()
			var file_result: Dictionary = PlannedCamera.read_recipe_file(recipe_path)
			_check("absolute recipe file is read and hashed from its actual bytes", bool(file_result.get("ok", false)) \
				and file_result.get("sha256") == FileAccess.get_sha256(recipe_path))
			_check("owned recipe test file is removed", DirAccess.remove_absolute(recipe_path) == OK)
		else:
			_check("recipe test file is writable", false)
	else:
		_check("recipe test path is fresh", false)
	var json_round_trip: Variant = JSON.parse_string(JSON.stringify(recipe))
	_check("JSON round-trip is accepted", typeof(json_round_trip) == TYPE_DICTIONARY \
		and PlannedCamera.validate_recipe(json_round_trip).is_empty())
	var numeric_version := recipe.duplicate(true)
	numeric_version.version = 1.0
	_check("JSON numeric version 1.0 is accepted", PlannedCamera.validate_recipe(numeric_version).is_empty())
	for field: String in ["format", "version", "shot_id", "vehicle_id", "source_plan_sha256", "mode", "target", "fov_deg", "north_m", "down_m", "east_offset_m"]:
		var missing := recipe.duplicate(true)
		missing.erase(field)
		_check("required field is refused when missing: " + field, not PlannedCamera.validate_recipe(missing).is_empty())
	for invalid: Variant in [true, "1", 2, 1.5, INF, NAN]:
		var changed := recipe.duplicate(true)
		changed.version = invalid
		_check("invalid version is refused: " + str(invalid), not PlannedCamera.validate_recipe(changed).is_empty())
	for field: String in ["shot_id", "vehicle_id"]:
		for invalid: Variant in ["", "  ", 0, null]:
			var changed := recipe.duplicate(true)
			changed[field] = invalid
			_check("invalid identity is refused: " + field + "/" + str(invalid), not PlannedCamera.validate_recipe(changed).is_empty())
	for invalid: Variant in ["a".repeat(63), "a".repeat(65), "z".repeat(64), 1, null]:
		var changed := recipe.duplicate(true)
		changed.source_plan_sha256 = invalid
		_check("invalid source hash is refused: " + str(invalid), not PlannedCamera.validate_recipe(changed).is_empty())
	var upper_hash := recipe.duplicate(true)
	upper_hash.source_plan_sha256 = "A".repeat(64)
	_check("uppercase hexadecimal hash is accepted", PlannedCamera.validate_recipe(upper_hash).is_empty())
	for invalid: Variant in [1.999, 120.001, INF, NAN, "42", true, null]:
		var changed := recipe.duplicate(true)
		changed.fov_deg = invalid
		_check("invalid FOV is refused: " + str(invalid), not PlannedCamera.validate_recipe(changed).is_empty())
	for valid: float in [2.0, 120.0]:
		var changed := recipe.duplicate(true)
		changed.fov_deg = valid
		_check("inclusive FOV boundary is accepted: " + str(valid), PlannedCamera.validate_recipe(changed).is_empty())
	for field: String in ["north_m", "down_m", "east_offset_m"]:
		for invalid: Variant in [100000.1, -100000.1, INF, NAN, "1", true, null]:
			var changed := recipe.duplicate(true)
			changed[field] = invalid
			_check("invalid coordinate is refused: " + field + "/" + str(invalid), not PlannedCamera.validate_recipe(changed).is_empty())
	for invalid: Variant in [null, [], [1, 2], [1, 2, 3, 4], [1, NAN, 3], [1, false, 3], [1, 100001, 3]]:
		var changed := _fixed_recipe()
		changed.eye_ned_m = invalid
		_check("invalid fixed eye is refused: " + str(invalid), not PlannedCamera.validate_recipe(changed).is_empty())
	var unexpected := recipe.duplicate(true)
	unexpected["eye_ned_m"] = [145, 125, -1]
	_check("mutually exclusive eye fields are refused", not PlannedCamera.validate_recipe(unexpected).is_empty())
	unexpected = recipe.duplicate(true)
	unexpected["unknown"] = 1
	_check("unknown fields are refused", not PlannedCamera.validate_recipe(unexpected).is_empty())
	for field: String in ["format", "mode", "target"]:
		var changed := recipe.duplicate(true)
		changed[field] = "unsupported"
		_check("unsupported " + field + " is refused", not PlannedCamera.validate_recipe(changed).is_empty())


func _test_parallel_tracking(flight: FlightStub, camera: Camera3D, visual: Node3D) -> void:
	var adapter := PlannedCamera.new()
	var input_recipe := _base_recipe()
	_check("parallel adapter configures", adapter.configure(flight, input_recipe).is_empty())
	_check("priority composes after director and before planar reflection", adapter.process_priority == 20)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	input_recipe.east_offset_m = 999.0 # The adapter must retain the admitted recipe.
	var original_root := visual.global_transform
	var state_before := flight.simulated_state.duplicate()
	var commands_before := flight.pilot_commands.duplicate(true)
	var samples := [
		[55.0, 47.0],
		[124.0, 116.0],
		[193.0, 185.0],
	]
	for sample: Array in samples:
		flight._last_render_pose = {"pos": Vector3(float(sample[0]), 2.55, -128.0)}
		var pose_before := flight._last_render_pose.duplicate(true)
		_check("parallel camera follows displayed position at E" + str(sample[0]), adapter.apply_frame())
		var record: Dictionary = adapter.frame_record()
		var expected_eye := Vector3(float(sample[1]), 1.0, -145.0)
		var expected_target: Vector3 = pose_before.pos
		_check("parallel eye follows CG east, with fixed north and down", camera.global_position.is_equal_approx(expected_eye))
		_check("parallel camera aims at displayed CG, not model root", _aims_at(camera, expected_target))
		_check("parallel record has the actual target and eye", bool(record.get("valid", false)) \
			and record.get("target") == "presented_cg" and record.has("water_down_m") and record.water_down_m == null \
			and _array_vector(record.get("presented_cg_render_m", []), expected_target) \
			and _array_vector(record.get("presented_cg_ned_m", []), Vector3(128.0, float(sample[0]), -2.55)) \
			and _array_vector(record.get("target_render_m", []), expected_target) \
			and _array_vector(record.get("target_ned_m", []), Vector3(128.0, float(sample[0]), -2.55)) \
			and _array_vector(record.get("requested_eye_ned_m", []), Vector3(145.0, float(sample[1]), -1.0)) \
			and _array_vector(record.get("actual_eye_render_m", []), expected_eye))
		_check("parallel lens and mode are recorded", record.get("mode") == "parallel_east" \
			and is_equal_approx(float(record.get("actual_fov_deg", 0.0)), 42.0) \
			and is_equal_approx(float(record.get("requested_fov_deg", 0.0)), 42.0) \
			and int(record.get("keep_aspect", -1)) == Camera3D.KEEP_HEIGHT \
			and camera.keep_aspect == Camera3D.KEEP_HEIGHT)
		_check("presented pose is read without mutation", flight._last_render_pose == pose_before)
	_check("visual model root is not moved", visual.global_transform == original_root)
	_check("simulation state and pilot commands are unchanged", flight.simulated_state == state_before and flight.pilot_commands == commands_before)
	var returned_record: Dictionary = adapter.frame_record()
	returned_record.target_ned_m[0] = 999.0
	_check("frame evidence is a detached copy", not is_equal_approx(float(adapter.frame_record().target_ned_m[0]), 999.0))
	_check("successful adapter has no error", adapter.configuration_error().is_empty())
	adapter.free()


func _test_fixed_tracking(flight: FlightStub, camera: Camera3D) -> void:
	var adapter := PlannedCamera.new()
	_check("fixed adapter configures", adapter.configure(flight, _fixed_recipe()).is_empty())
	for east: float in [55.0, 124.0, 193.0]:
		flight._last_render_pose = {"pos": Vector3(east, 2.55, -128.0)}
		_check("fixed camera follows the displayed CG", adapter.apply_frame())
		_check("fixed NED eye converts to render axes", camera.global_position.is_equal_approx(Vector3(125.0, 1.0, -145.0)))
		_check("fixed eye remains while aim follows aircraft", _aims_at(camera, flight._last_render_pose.pos))
		var record: Dictionary = adapter.frame_record()
		_check("fixed eye and target are recorded", record.get("mode") == "fixed_world" \
			and _array_vector(record.get("requested_eye_ned_m", []), Vector3(145.0, 125.0, -1.0)) \
			and _array_vector(record.get("target_render_m", []), flight._last_render_pose.pos))
	adapter.free()


func _test_water_plane_tracking(flight: FlightStub, camera: Camera3D, visual: Node3D) -> void:
	var adapter := PlannedCamera.new()
	var recipe := _water_recipe()
	_check("water-plane adapter configures", adapter.configure(flight, recipe).is_empty())
	recipe.water_down_m = 123.0 # Configuration retained a detached copy.
	var state_before := flight.simulated_state.duplicate()
	var commands_before := flight.pilot_commands.duplicate(true)
	var root_before := visual.global_transform
	for sample: Array in [[55.0, 2.55], [124.0, 3.1], [193.0, 1.9]]:
		var cg := Vector3(float(sample[0]), float(sample[1]), -128.0)
		var aim := Vector3(float(sample[0]), -0.45, -128.0)
		var eye := Vector3(float(sample[0]) - 8.0, 1.0, -145.0)
		flight._last_render_pose = {"pos": cg}
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		_check("water-plane camera tracks a live CG", adapter.apply_frame())
		var record: Dictionary = adapter.frame_record()
		_check("water-plane eye follows CG east and aims at mean water", camera.global_position.is_equal_approx(eye) \
			and _aims_at(camera, aim) and not _aims_at(camera, cg))
		_check("water-plane evidence separates CG from actual aim", record.get("target") == "presented_cg_water_plane" \
			and is_equal_approx(float(record.get("water_down_m", NAN)), 0.45) \
			and _array_vector(record.get("presented_cg_render_m", []), cg) \
			and _array_vector(record.get("presented_cg_ned_m", []), Vector3(128.0, float(sample[0]), -float(sample[1]))) \
			and _array_vector(record.get("target_render_m", []), aim) \
			and _array_vector(record.get("target_ned_m", []), Vector3(128.0, float(sample[0]), 0.45)) \
			and _array_vector(record.get("actual_eye_render_m", []), eye))
		_check("water-plane lens is explicitly vertical", camera.keep_aspect == Camera3D.KEEP_HEIGHT \
			and int(record.get("keep_aspect", -1)) == Camera3D.KEEP_HEIGHT and is_equal_approx(camera.fov, 42.0))
	var detached: Dictionary = adapter.frame_record()
	detached.presented_cg_render_m[0] = 999.0
	detached.presented_cg_ned_m[0] = 999.0
	detached.target_render_m[0] = 999.0
	detached.target_ned_m[0] = 999.0
	var retained: Dictionary = adapter.frame_record()
	_check("CG and water-plane evidence arrays are detached", float(retained.presented_cg_render_m[0]) != 999.0 \
		and float(retained.presented_cg_ned_m[0]) != 999.0 and float(retained.target_render_m[0]) != 999.0 \
		and float(retained.target_ned_m[0]) != 999.0)
	_check("water-plane aim leaves simulation, inputs and visual root unchanged", flight.simulated_state == state_before \
		and flight.pilot_commands == commands_before and visual.global_transform == root_before)
	adapter.free()

	var fixed := _fixed_recipe()
	fixed.target = "presented_cg_water_plane"
	fixed["water_down_m"] = 0.45
	var fixed_adapter := PlannedCamera.new()
	_check("fixed eye water-plane adapter configures", fixed_adapter.configure(flight, fixed).is_empty())
	_check("fixed eye supports the same water-plane target", fixed_adapter.apply_frame() \
		and camera.global_position.is_equal_approx(Vector3(125.0, 1.0, -145.0)) \
		and _aims_at(camera, Vector3(193.0, -0.45, -128.0)))
	fixed_adapter.free()


func _test_frame_evidence(flight: FlightStub, camera: Camera3D) -> void:
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	var recipe := _water_recipe()
	var adapter := PlannedCamera.new()
	_check("evidence fixture configures", adapter.configure(flight, recipe).is_empty())
	_check("evidence fixture captures a frame", adapter.apply_frame())
	var evidence: Dictionary = adapter.frame_record()
	_check("standalone evidence has the current engine frame and no session tick", \
		evidence.get("process_frame") == Engine.get_process_frames() and evidence.has("sim_tick") \
		and evidence.sim_tick == null)
	_check("live water-plane evidence is accepted", PlannedCamera.frame_evidence_error(
		evidence, recipe, flight._last_render_pose, camera).is_empty())
	_check("capture requiring a session tick refuses standalone evidence", not PlannedCamera.frame_evidence_error(
		evidence, recipe, flight._last_render_pose, camera, 0).is_empty())
	var stale_identity := evidence.duplicate(true)
	stale_identity.process_frame = Engine.get_process_frames() - 1
	_check("evidence from another engine frame is refused at unchanged CG", \
		not PlannedCamera.frame_evidence_error(stale_identity, recipe, flight._last_render_pose, camera).is_empty())
	var moved_cg := {"pos": Vector3(55.0, 3.55, -128.0)}
	_check("changed CG altitude is refused even when water-plane aim stays the same", \
		not PlannedCamera.frame_evidence_error(evidence, recipe, moved_cg, camera).is_empty())
	moved_cg.pos = Vector3(56.0, 2.55, -128.0)
	_check("changed CG east and corresponding aim are refused", \
		not PlannedCamera.frame_evidence_error(evidence, recipe, moved_cg, camera).is_empty())
	_check("missing latest CG is refused", not PlannedCamera.frame_evidence_error(evidence, recipe, {}, camera).is_empty())
	for field: String in ["presented_cg_render_m", "presented_cg_ned_m", "target_render_m", "target_ned_m", \
			"requested_eye_ned_m", "actual_eye_render_m"]:
		var changed := evidence.duplicate(true)
		changed[field][0] = float(changed[field][0]) + 1.0
		_check("changed recorded position is refused: " + field, \
			not PlannedCamera.frame_evidence_error(changed, recipe, flight._last_render_pose, camera).is_empty())
	var bad_plane := evidence.duplicate(true)
	bad_plane.water_down_m = 0.46
	_check("changed recorded water plane is refused", \
		not PlannedCamera.frame_evidence_error(bad_plane, recipe, flight._last_render_pose, camera).is_empty())
	bad_plane.erase("water_down_m")
	_check("missing recorded water plane is refused", \
		not PlannedCamera.frame_evidence_error(bad_plane, recipe, flight._last_render_pose, camera).is_empty())
	var changed_recipe := recipe.duplicate(true)
	changed_recipe.water_down_m = 0.46
	_check("changed admitted water plane is refused", \
		not PlannedCamera.frame_evidence_error(evidence, changed_recipe, flight._last_render_pose, camera).is_empty())
	var bad_target := evidence.duplicate(true)
	bad_target.target = "presented_cg"
	_check("changed target kind is refused", \
		not PlannedCamera.frame_evidence_error(bad_target, recipe, flight._last_render_pose, camera).is_empty())
	var bad_value := evidence.duplicate(true)
	bad_value.presented_cg_render_m[0] = NAN
	_check("nonfinite evidence is refused", \
		not PlannedCamera.frame_evidence_error(bad_value, recipe, flight._last_render_pose, camera).is_empty())
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	_check("changed live FOV axis is refused", \
		not PlannedCamera.frame_evidence_error(evidence, recipe, flight._last_render_pose, camera).is_empty())
	_check("adapter restores vertical FOV", adapter.apply_frame() and camera.keep_aspect == Camera3D.KEEP_HEIGHT)
	camera.fov = 40.0
	_check("changed live FOV is refused", \
		not PlannedCamera.frame_evidence_error(evidence, recipe, flight._last_render_pose, camera).is_empty())
	_check("adapter restores the admitted FOV", adapter.apply_frame())
	camera.global_position += Vector3(1.0, 0.0, 0.0)
	_check("changed live camera eye is refused", \
		not PlannedCamera.frame_evidence_error(evidence, recipe, flight._last_render_pose, camera).is_empty())
	_check("adapter restores the admitted eye", adapter.apply_frame())
	camera.look_at(flight._last_render_pose.pos, Vector3.UP)
	var forged_rotation := evidence.duplicate(true)
	var rotation := camera.get_camera_transform().basis.get_rotation_quaternion().normalized()
	forged_rotation.actual_quaternion_xyzw = [rotation.x, rotation.y, rotation.z, rotation.w]
	_check("live camera cannot look at CG when the admitted aim is the water plane", \
		not PlannedCamera.frame_evidence_error(forged_rotation, recipe, flight._last_render_pose, camera).is_empty())
	adapter.free()

	var cg_adapter := PlannedCamera.new()
	var cg_recipe := _base_recipe()
	_check("legacy CG evidence fixture configures and applies", cg_adapter.configure(flight, cg_recipe).is_empty() \
		and cg_adapter.apply_frame())
	var cg_evidence: Dictionary = cg_adapter.frame_record()
	_check("CG-targeted evidence remains accepted", PlannedCamera.frame_evidence_error(
		cg_evidence, cg_recipe, flight._last_render_pose, camera).is_empty())
	cg_evidence.water_down_m = 0.45
	_check("CG-targeted evidence refuses a plane value", \
		not PlannedCamera.frame_evidence_error(cg_evidence, cg_recipe, flight._last_render_pose, camera).is_empty())
	cg_adapter.free()


## Use real SceneTree processing and the engine frame counter. The stepper models
## a session whose tick advances while its displayed CG remains stationary.
func _test_freshness_same_position(flight: FlightStub, camera: Camera3D) -> void:
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	flight.simulated_tick = 0
	var recipe := _water_recipe()
	var adapter := PlannedCamera.new()
	var tick_provider := func() -> int: return flight.simulated_tick
	_check("freshness fixture configures with a tick provider", adapter.configure(flight, recipe, tick_provider).is_empty())
	var stepper := FrameCallback.new()
	stepper.process_priority = 0
	stepper.callback = func() -> void: flight.simulated_tick += 1
	var director_state := {"processed": 0}
	var director := FrameCallback.new()
	director.process_priority = 10
	director.callback = func() -> void: director_state.processed += 1
	var observations: Array[Dictionary] = []
	var observer := FrameCallback.new()
	observer.process_priority = 30 # After the camera's priority 20, in the same actual process frame.
	observer.callback = func() -> void:
		var evidence: Dictionary = adapter.frame_record()
		observations.append({"engine_frame": Engine.get_process_frames(), "tick": flight.simulated_tick,
			"director_processed": director_state.processed,
			"cg": flight._last_render_pose.pos, "evidence": evidence,
			"error": PlannedCamera.frame_evidence_error(evidence, recipe, flight._last_render_pose, camera, flight.simulated_tick),
			"tick_mismatch_error": PlannedCamera.frame_evidence_error(evidence, recipe, flight._last_render_pose, camera, flight.simulated_tick + 1)})
	root.add_child(stepper)
	root.add_child(director)
	root.add_child(adapter)
	root.add_child(observer)
	# The process_frame signal precedes node processing. Two signals contain at
	# least one complete pass of the stepper, adapter and observer.
	await process_frame
	await process_frame
	if observations.is_empty():
		_check("freshness observer received a process pass", false)
		stepper.free()
		director.free()
		adapter.free()
		observer.free()
		return
	var before: Dictionary = observations.back()
	_check("same-frame camera evidence records the current engine frame and simulation tick", \
		str(before.error).is_empty() and before.evidence.process_frame == before.engine_frame \
		and before.evidence.sim_tick == before.tick)
	_check("different session tick is refused even in the same engine frame", not str(before.tick_mismatch_error).is_empty())
	adapter.set_process(false)
	await process_frame
	await process_frame
	var stale: Dictionary = observations.back()
	_check("skipped camera application is refused while tick and director advance at unchanged CG", \
		int(stale.engine_frame) > int(before.engine_frame) and int(stale.tick) > int(before.tick) \
		and int(stale.director_processed) > int(before.director_processed) \
		and stale.cg == before.cg and stale.evidence.process_frame == before.evidence.process_frame \
		and stale.evidence.sim_tick == before.evidence.sim_tick and not str(stale.error).is_empty())
	adapter.set_process(true)
	await process_frame
	await process_frame
	var resumed: Dictionary = observations.back()
	_check("resumed application supplies current frame and tick at the same CG", str(resumed.error).is_empty() \
		and resumed.evidence.process_frame == resumed.engine_frame and resumed.evidence.sim_tick == resumed.tick \
		and resumed.cg == before.cg and int(resumed.engine_frame) > int(stale.engine_frame))
	stepper.free()
	director.free()
	adapter.free()
	observer.free()


## Both nodes run in the scene tree: the adapter must win after the director
## without replacing it or changing the session and input records.
func _test_post_draw_freshness(flight: FlightStub, camera: Camera3D) -> void:
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	flight.simulated_tick = 0
	var recipe := _water_recipe()
	var adapter := PlannedCamera.new()
	var tick_provider := func() -> int: return flight.simulated_tick
	_check("post-draw fixture configures", adapter.configure(flight, recipe, tick_provider).is_empty())
	var stepper := FrameCallback.new()
	stepper.process_priority = 0
	stepper.callback = func() -> void: flight.simulated_tick += 1
	var observations: Array[Dictionary] = []
	var observer := func() -> void:
		var evidence: Dictionary = adapter.frame_record()
		observations.append({"frame": Engine.get_process_frames(), "tick": flight.simulated_tick,
			"evidence": evidence,
			"error": PlannedCamera.frame_evidence_error(evidence, recipe, flight._last_render_pose, camera, flight.simulated_tick)})
	root.add_child(stepper)
	root.add_child(adapter)
	camera.make_current()
	RenderingServer.frame_post_draw.connect(observer)
	# Bounded even when a runner does not emit draw callbacks. A headless callback
	# result establishes engine ordering only, never rendered pixels or GPU output.
	for i: int in 4:
		await process_frame
	_check("frame_post_draw was observed on this engine route", not observations.is_empty())
	if not observations.is_empty():
		var fresh: Dictionary = observations.back()
		_check("post-draw evidence uses the current engine frame and session tick", str(fresh.error).is_empty() \
			and fresh.evidence.process_frame == fresh.frame and fresh.evidence.sim_tick == fresh.tick)
		adapter.set_process(false)
		var before := observations.size()
		for i: int in 3:
			await process_frame
		_check("post-draw guard rejects a skipped adapter at unchanged CG", observations.size() > before \
			and not str(observations.back().error).is_empty())
		adapter.set_process(true)
		before = observations.size()
		for i: int in 3:
			await process_frame
		_check("post-draw guard accepts resumed fresh evidence", observations.size() > before \
			and str(observations.back().error).is_empty())
	RenderingServer.frame_post_draw.disconnect(observer)
	stepper.free()
	adapter.free()


## Both nodes run in the scene tree: the adapter must win after the director.
func _test_composition(flight: FlightStub, camera: Camera3D) -> void:
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	var state_before := flight.simulated_state.duplicate()
	var commands_before := flight.pilot_commands.duplicate(true)
	var director := DirectorStub.new()
	director.camera = camera
	director.process_priority = 10
	var adapter := PlannedCamera.new()
	_check("composition fixture configures", adapter.configure(flight, _base_recipe()).is_empty())
	root.add_child(director)
	root.add_child(adapter)
	# process_frame is emitted before the nodes process, so one full frame lies
	# between these two signals even when the test starts from a deferred call.
	await process_frame
	await process_frame
	_check("existing director continues processing", director.processed > 0)
	_check("composed camera is the final placement", camera.global_position.is_equal_approx(Vector3(47.0, 1.0, -145.0)) \
		and is_equal_approx(camera.fov, 42.0) and _aims_at(camera, flight._last_render_pose.pos))
	_check("composed camera records the frame", bool(adapter.frame_record().get("valid", false)))
	_check("composition leaves simulated state and controls unchanged", flight.simulated_state == state_before \
		and flight.pilot_commands == commands_before)
	director.free()
	adapter.free()


func _test_failures(flight: FlightStub, rig: RigStub, camera: Camera3D) -> void:
	var bad_recipe := _base_recipe()
	bad_recipe.east_offset_m = INF
	var invalid := PlannedCamera.new()
	_check("invalid configuration returns an error", not invalid.configure(flight, bad_recipe).is_empty())
	_check("invalid configuration cannot later be reused", not invalid.configure(flight, _base_recipe()).is_empty())
	_check("configuration failure remains observable", not invalid.configuration_error().is_empty())
	invalid.free()
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	var invalid_tick := PlannedCamera.new()
	var invalid_tick_provider := func() -> int: return -1
	_check("invalid-tick fixture configures", invalid_tick.configure(flight, _base_recipe(), invalid_tick_provider).is_empty())
	_check("invalid simulation tick fails closed", not invalid_tick.apply_frame() \
		and not invalid_tick.configuration_error().is_empty() and invalid_tick.frame_record().get("valid", true) == false)
	invalid_tick.free()

	flight._last_render_pose = {}
	_assert_frame_failure(flight, "missing displayed CG")
	flight._last_render_pose = {"pos": Vector3(INF, 2.55, -128.0)}
	_assert_frame_failure(flight, "nonfinite displayed CG")
	flight._last_render_pose = {"pos": Vector3(125.0, 1.0, -145.0)}
	_assert_frame_failure(flight, "coincident camera and CG")
	flight._last_render_pose = {"pos": Vector3(125.0, 5.0, -145.0)}
	_assert_frame_failure(flight, "vertical look")
	var water_eye := _fixed_recipe()
	water_eye.target = "presented_cg_water_plane"
	water_eye["water_down_m"] = -1.0
	flight._last_render_pose = {"pos": Vector3(125.0, 2.55, -145.0)}
	var coincident_aim := PlannedCamera.new()
	_check("water aim failure fixture configures", coincident_aim.configure(flight, water_eye).is_empty())
	_check("water-plane aim coincident with eye is refused even when CG differs", not coincident_aim.apply_frame() \
		and not coincident_aim.configuration_error().is_empty() and coincident_aim.frame_record().get("valid", true) == false)
	coincident_aim.free()
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	flight._rig = null
	_assert_frame_failure(flight, "missing rig")
	flight._rig = rig
	rig.camera = null
	_assert_frame_failure(flight, "missing camera")
	rig.camera = camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_assert_frame_failure(flight, "nonperspective camera")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.h_offset = 0.2
	_assert_frame_failure(flight, "nonzero optical offset")
	camera.h_offset = 0.0

	var sticky := PlannedCamera.new()
	_check("sticky-failure fixture configures", sticky.configure(flight, _fixed_recipe()).is_empty())
	_check("sticky-failure fixture first tracks", sticky.apply_frame())
	var camera_before_failure := camera.global_transform
	flight._last_render_pose = {}
	_check("a later missing target fails", not sticky.apply_frame())
	_check("failure leaves camera at its last pose", camera.global_transform == camera_before_failure)
	_check("failure record is not a stale success", sticky.frame_record().get("valid", true) == false)
	var error := sticky.configuration_error()
	flight._last_render_pose = {"pos": Vector3(55.0, 2.55, -128.0)}
	_check("failure remains sticky after target returns", not sticky.apply_frame() and sticky.configuration_error() == error)
	sticky.free()


func _assert_frame_failure(flight: FlightStub, label: String) -> void:
	var adapter := PlannedCamera.new()
	_check(label + ": configuration succeeds", adapter.configure(flight, _fixed_recipe()).is_empty())
	_check(label + ": frame is refused", not adapter.apply_frame())
	_check(label + ": error and invalid evidence are retained", not adapter.configuration_error().is_empty() \
		and adapter.frame_record().get("valid", true) == false)
	adapter.free()


func _aims_at(camera: Camera3D, target: Vector3) -> bool:
	var optical := camera.get_camera_transform()
	var direction := (target - optical.origin).normalized()
	return (-optical.basis.z.normalized()).dot(direction) > 0.99999


func _array_vector(value: Variant, expected: Vector3) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 3 \
		and Vector3(float(value[0]), float(value[1]), float(value[2])).is_equal_approx(expected)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TRAILER_PLANNED_CAMERA FAIL: " + label)
