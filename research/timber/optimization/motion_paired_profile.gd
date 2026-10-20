## Same-process, order-alternating CPU comparison of frozen baseline and live observer.
## Two equivalent private Turbo Lumber fixtures are used; this is not an FPS measurement.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const BASELINE_PATH := "res://../research/timber/optimization/motion_baseline.gd"
const CANDIDATE_PATH := "res://aircraft/timber_visual_motion.gd"
const BATCHES := 60
const PAIRS_PER_BATCH := 20
const WARMUP_PAIRS := 60

var _out_dir := ""
var _fixtures: Dictionary = {}
var _failures: Array[String] = []
var _loaded_state := PackedFloat64Array()
var _loaded_compression := PackedFloat64Array()
var _taxi_a := PackedFloat64Array()
var _taxi_b := PackedFloat64Array()
var _compression_a := PackedFloat64Array()
var _compression_b := PackedFloat64Array()
var _airborne := PackedFloat64Array()
var _airborne_compression := PackedFloat64Array()
var _contacts: Array = []
var _surfaces := PackedFloat64Array()
var _continuous := PackedFloat64Array()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if _out_dir.is_empty():
		_out_dir = ProjectSettings.globalize_path("res://../tmp/timber-overhaul/motion-paired-profile")
	_run.call_deferred()


func _run() -> void:
	if DirAccess.dir_exists_absolute(_out_dir):
		push_error("Pass a new --out directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var baseline_hash_start := _sha(BASELINE_PATH)
	var candidate_hash_start := _sha(CANDIDATE_PATH)
	var base_script := ResourceLoader.load(BASELINE_PATH, "GDScript", ResourceLoader.CACHE_MODE_REUSE) as Script
	var candidate_script := ResourceLoader.load(CANDIDATE_PATH, "GDScript", ResourceLoader.CACHE_MODE_REUSE) as Script
	if base_script == null or candidate_script == null:
		_failures.append("could not load baseline and live scripts")
		_write_report({"schema": "tt21-timber-motion-paired-profile-v1"})
		quit(1)
		return
	var base_result := _make_fixture("baseline", base_script)
	var candidate_result := _make_fixture("candidate", candidate_script)
	if not bool(base_result.get("ok", false)) or not bool(candidate_result.get("ok", false)):
		_failures.append("fixture setup failed: %s / %s" % [
			base_result.get("error", ""), candidate_result.get("error", "")])
		_write_report({"schema": "tt21-timber-motion-paired-profile-v1"})
		quit(1)
		return
	_fixtures = {"baseline": base_result.fixture, "candidate": candidate_result.fixture}
	_match_initial_inputs()
	_select_states()
	var before_snapshots := _capture_snapshots()
	_resume_fixtures()
	var profiles: Array[Dictionary] = [
		_measure_process("settled_rest", "rest"),
		_measure_process("variable_compression_taxi", "taxi"),
		_measure_process("airborne", "airborne"),
		_measure_process("paused_focus_style", "paused"),
		_measure_cables(),
		_measure_dust("contact_dust_paved_no_slip", "paved"),
		_measure_dust("contact_dust_synthetic_rough_slip", "rough"),
		_measure_dust("contact_dust_no_compression", "none"),
	]
	var after_snapshots := _capture_snapshots()
	var snapshots := _compare_snapshots(before_snapshots, after_snapshots)
	var inputs := _check_inputs()
	var base_hash_end := _sha(BASELINE_PATH)
	var candidate_hash_end := _sha(CANDIDATE_PATH)
	var report := {
		"schema": "tt21-timber-motion-paired-profile-v1",
		"profiling_mode": "same-process order-alternating headless CPU microbenchmark; not an FPS measurement",
		"runtime_sources": {
			"baseline_path": "research/timber/optimization/motion_baseline.gd",
			"baseline_sha256": baseline_hash_start,
			"candidate_path": "app/aircraft/timber_visual_motion.gd",
			"candidate_sha256": candidate_hash_start,
			"baseline_sha256_after": base_hash_end,
			"candidate_sha256_after": candidate_hash_end,
			"stable_after_measurement": baseline_hash_start == base_hash_end and candidate_hash_start == candidate_hash_end,
		},
		"engine_version": Engine.get_version_info(),
		"fixture": "independently built private Turbo Lumber sessions with exact matched state, continuous telemetry, aux, surfaces, and contacts",
		"execution_scope": "shared development host with concurrent root/research work; order pairing reduces but does not eliminate host scheduling/frequency effects",
		"sample_design": {
			"warmup_pairs_per_case": WARMUP_PAIRS,
			"batches": BATCHES,
			"pairs_per_batch": PAIRS_PER_BATCH,
			"calls_per_source_per_case": BATCHES * PAIRS_PER_BATCH,
			"order": "baseline-first/candidate-first alternate on each matched input pair",
			"timer": "Time.get_ticks_usec around one observer method call; input setup outside timing",
		},
		"input_states": _state_report(),
		"paired_profiles": profiles,
		"snapshot_parity": snapshots,
		"snapshots_before_measurement": before_snapshots,
		"snapshots_after_measurement": after_snapshots,
		"input_immutability": inputs,
		"failures": _failures,
	}
	if not bool(report.runtime_sources.stable_after_measurement):
		_failures.append("runtime source changed during the profile")
	_write_report(report)
	_teardown()
	quit(0 if _failures.is_empty() else 1)


func _make_fixture(label: String, motion_script: Script) -> Dictionary:
	var entry: Dictionary = Catalog.entry("turbo-lumber-evolution")
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(str(entry.data))
	if session.sim == null or not session.is_flyable():
		session.free()
		return {"ok": false, "error": label + " session did not initialize"}
	root.add_child(session)
	var field_result: Dictionary = FieldLoader.load_from()
	if not bool(field_result.get("ok", false)) or not session.set_field(field_result.get("field")):
		session.queue_free()
		return {"ok": false, "error": label + " field did not load"}
	session.start_choice = Session.START_RUNWAY
	session.reset()
	var airplane: Dictionary = Airplane.build("turbo-lumber-evolution")
	if airplane.is_empty() or airplane.get("root") == null:
		session.queue_free()
		return {"ok": false, "error": label + " model did not build"}
	root.add_child(airplane.root)
	GroundGear.attach(airplane, session)
	var motion := motion_script.new() as Node
	if motion == null:
		airplane.root.queue_free()
		session.queue_free()
		return {"ok": false, "error": label + " observer did not instantiate"}
	motion.name = "TimberMotionPair_" + label
	motion.process_priority = 20
	motion.set("_airplane", airplane)
	motion.set("_session", session)
	if not bool(motion.call("_configure")):
		motion.free()
		airplane.root.queue_free()
		session.queue_free()
		return {"ok": false, "error": label + " observer configuration failed"}
	airplane.root.add_child(motion)
	if bool(motion.call("_is_source_airframe")) and session.has_signal("resetting"):
		session.resetting.connect(Callable(motion, "_on_session_resetting"))
	var contacts: Array = session.current_landing_gear().get("contacts", [])
	if contacts.is_empty():
		return {"ok": false, "error": label + " contacts are empty"}
	return {"ok": true, "fixture": {
		"label": label, "session": session, "airplane": airplane, "motion": motion,
		"contacts": contacts, "initial_state": session.sim.state.duplicate(),
		"initial_previous": session.sim.previous.duplicate(),
		"initial_continuous": session.sim.continuous.duplicate(),
		"initial_aux": session.sim.aux.duplicate(),
		"initial_surfaces": session.ground_surfaces.duplicate(),
	}}


func _match_initial_inputs() -> void:
	var base: Dictionary = _fixtures.baseline
	var candidate: Dictionary = _fixtures.candidate
	var source: Node = base.session
	var target: Node = candidate.session
	target.sim.state = source.sim.state.duplicate()
	target.sim.previous = source.sim.previous.duplicate()
	target.sim.continuous = source.sim.continuous.duplicate()
	target.sim.aux = source.sim.aux.duplicate()
	target.ground_surfaces = source.ground_surfaces.duplicate()
	_loaded_state = source.sim.state.duplicate()
	_loaded_compression = source.gear_compressions(_loaded_state)
	_surfaces = source.ground_surfaces.duplicate()
	_continuous = source.sim.continuous.duplicate()
	_contacts = source.current_landing_gear().get("contacts", []).duplicate(true)
	if target.current_landing_gear().get("contacts", []) != _contacts:
		_failures.append("baseline/candidate contact definitions differ")
	if target.sim.state != source.sim.state or target.sim.continuous != source.sim.continuous \
		or target.sim.aux != source.sim.aux or target.ground_surfaces != source.ground_surfaces:
		_failures.append("could not match initial fixture inputs exactly")


func _select_states() -> void:
	var motion: Node = _fixtures.baseline.motion
	var root_node: Node3D = _fixtures.baseline.airplane.root
	var candidates: Array[Dictionary] = []
	for down: float in [-0.18, -0.10, -0.06, -0.03, -0.028, -0.025, -0.022,
		-0.020, -0.018, -0.015, -0.012, -0.009, -0.006, -0.003, 0.0,
		0.003, 0.006, 0.009, 0.015, 0.03, 0.06, 0.10, 0.18]:
		var state := _loaded_state.duplicate()
		state[2] += down
		var compression: PackedFloat64Array = _fixtures.baseline.session.gear_compressions(state)
		candidates.append({"state": state, "compression": compression,
			"angles": _angles(motion, root_node, compression)})
	var best_a: Dictionary = {}
	var best_b: Dictionary = {}
	var best_delta := 0.0
	var airborne_score := INF
	_airborne = _loaded_state.duplicate()
	for row: Dictionary in candidates:
		var score := 0.0
		for value: float in row.compression:
			score += maxf(0.0, value)
		if score < airborne_score:
			airborne_score = score
			_airborne = (row.state as PackedFloat64Array).duplicate()
	for i in candidates.size():
		var a: Dictionary = candidates[i]
		if not _is_unsaturated(a, motion):
			continue
		for j in range(i + 1, candidates.size()):
			var b: Dictionary = candidates[j]
			if not _is_unsaturated(b, motion):
				continue
			var delta := absf(a.angles[0] - b.angles[0]) + absf(a.angles[1] - b.angles[1])
			if delta > best_delta:
				best_delta = delta
				best_a = a
				best_b = b
	if best_a.is_empty() or best_b.is_empty():
		_failures.append("could not find variable unsaturated taxi poses")
		_taxi_a = _loaded_state.duplicate()
		_taxi_b = _loaded_state.duplicate()
		_taxi_b[2] -= 0.012
	else:
		_taxi_a = (best_a.state as PackedFloat64Array).duplicate()
		_taxi_b = (best_b.state as PackedFloat64Array).duplicate()
	_taxi_a[3] = 2.0
	_taxi_b[3] = 2.0
	_airborne[3] = 12.0
	_compression_a = _fixtures.baseline.session.gear_compressions(_taxi_a)
	_compression_b = _fixtures.baseline.session.gear_compressions(_taxi_b)
	_airborne_compression = _fixtures.baseline.session.gear_compressions(_airborne)


func _angles(motion: Node, root_node: Node3D, compression: PackedFloat64Array) -> Array[float]:
	var result: Array[float] = []
	var up_root: Vector3 = root_node.global_basis.transposed() * Vector3.UP
	for leg: Dictionary in motion.get("_legs"):
		var index: int = leg.contact_index
		if index < 0 or index >= compression.size():
			result.append(0.0)
			continue
		var amount := clampf(float(compression[index]), 0.0, float(leg.contact.get("max_compression", 0.10)))
		var axis: Vector3 = leg.axis_root
		var arm: Vector3 = leg.tip_root - leg.pivot_root
		var max_height: float = maxf(0.0, motion.call("_height_for_angle", axis, arm,
			motion.get("_max_travel_rad"), up_root))
		result.append(float(motion.call("_suspension_angle", leg, minf(amount, max_height), up_root)))
	return result


func _is_unsaturated(row: Dictionary, motion: Node) -> bool:
	if row.compression.size() < 2 or row.angles.size() < 2:
		return false
	for i in 2:
		var leg: Dictionary = motion.get("_legs")[i]
		if row.compression[leg.contact_index] <= 0.0 or row.angles[i] <= 1.0e-4:
			return false
		if row.angles[i] >= float(motion.get("_max_travel_rad")) - 1.0e-3:
			return false
	return true


func _state_report() -> Dictionary:
	return {
		"settled_rest_compression_m": Array(_loaded_compression),
		"taxi_a_compression_m": Array(_compression_a),
		"taxi_b_compression_m": Array(_compression_b),
		"taxi_compression_l1_delta_m": _delta(_compression_a, _compression_b),
		"airborne_compression_m": Array(_airborne_compression),
		"taxi_a_state_sha256": _hash(_taxi_a),
		"taxi_b_state_sha256": _hash(_taxi_b),
		"airborne_state_sha256": _hash(_airborne),
	}


func _measure_process(label: String, mode: String) -> Dictionary:
	return _measure_pairs(label, func(pair_index: int) -> Dictionary:
		var state: PackedFloat64Array = _loaded_state
		if mode == "taxi":
			state = _taxi_a if pair_index % 2 == 0 else _taxi_b
		elif mode == "airborne":
			state = _airborne
		var paused := mode == "paused"
		for fixture: Dictionary in _fixtures.values():
			fixture.session.sim.set_paused(paused)
			fixture.session.sim.state = state.duplicate()
			fixture.session.sim.previous = state.duplicate()
		return {"operation": "process", "payload": {"delta": 1.0 / 60.0}})


func _measure_cables() -> Dictionary:
	var angles_a := {"left": deg_to_rad(2.0), "right": deg_to_rad(3.5)}
	var angles_b := {"left": deg_to_rad(5.5), "right": deg_to_rad(1.0)}
	return _measure_pairs("cable_and_coil_vertices_variable_pose",
		func(pair_index: int) -> Dictionary:
			return {"operation": "cable", "payload": {"angles": angles_a if pair_index % 2 == 0 else angles_b}})


func _measure_dust(label: String, mode: String) -> Dictionary:
	var state: PackedFloat64Array = _taxi_a
	var compression: PackedFloat64Array = _compression_a
	if mode == "none":
		compression = PackedFloat64Array()
		compression.resize(_contacts.size())
		compression.fill(0.0)
	if mode == "rough":
		_prepare_rough_slip(state)
	else:
		_restore_surface_inputs()
	return _measure_pairs(label, func(_pair_index: int) -> Dictionary:
		for fixture: Dictionary in _fixtures.values():
			fixture.session.sim.set_paused(false)
			fixture.session.sim.state = state.duplicate()
			fixture.session.sim.previous = state.duplicate()
		return {"operation": "dust", "payload": {"state": state, "compression": compression}})


func _measure_pairs(label: String, prepare: Callable) -> Dictionary:
	var all_samples: Array[Dictionary] = []
	for warm in WARMUP_PAIRS:
		var warm_payload: Dictionary = prepare.call(warm)
		_call_pair(warm_payload.operation, warm_payload.payload, warm % 2 == 0)
	for batch in BATCHES:
		var base_total := 0
		var candidate_total := 0
		var pair_ratios: Array[float] = []
		for pair_index in PAIRS_PER_BATCH:
			var global_index := batch * PAIRS_PER_BATCH + pair_index
			var prepared: Dictionary = prepare.call(global_index)
			var pair := _call_pair(prepared.operation, prepared.payload, global_index % 2 == 0)
			base_total += int(pair.baseline_us)
			candidate_total += int(pair.candidate_us)
			pair_ratios.append(_ratio(float(pair.candidate_us), float(pair.baseline_us)))
		all_samples.append({
			"baseline_batch_mean_us": float(base_total) / PAIRS_PER_BATCH,
			"candidate_batch_mean_us": float(candidate_total) / PAIRS_PER_BATCH,
			"candidate_over_baseline_batch_ratio": _ratio(float(candidate_total), float(base_total)),
			"median_pair_ratio": _median(pair_ratios),
		})
	var base_means: Array[float] = []
	var candidate_means: Array[float] = []
	var batch_ratios: Array[float] = []
	var pair_medians: Array[float] = []
	for sample: Dictionary in all_samples:
		base_means.append(float(sample.baseline_batch_mean_us))
		candidate_means.append(float(sample.candidate_batch_mean_us))
		batch_ratios.append(float(sample.candidate_over_baseline_batch_ratio))
		pair_medians.append(float(sample.median_pair_ratio))
	var median_ratio := _median(batch_ratios)
	return {
		"case": label,
		"calls_per_source": BATCHES * PAIRS_PER_BATCH,
		"batches": BATCHES,
		"pairs_per_batch": PAIRS_PER_BATCH,
		"baseline_median_batch_mean_us_per_call": _median(base_means),
		"candidate_median_batch_mean_us_per_call": _median(candidate_means),
		"paired_median_batch_ratio_candidate_over_baseline": median_ratio,
		"paired_median_pair_ratio_candidate_over_baseline": _median(pair_medians),
		"paired_median_change_percent": (median_ratio - 1.0) * 100.0,
		"batch_samples": all_samples,
	}


func _call_pair(operation: String, payload: Dictionary, baseline_first: bool) -> Dictionary:
	var base_us := 0
	var candidate_us := 0
	if baseline_first:
		base_us = _time_fixture(_fixtures.baseline, operation, payload)
		candidate_us = _time_fixture(_fixtures.candidate, operation, payload)
	else:
		candidate_us = _time_fixture(_fixtures.candidate, operation, payload)
		base_us = _time_fixture(_fixtures.baseline, operation, payload)
	return {"baseline_us": base_us, "candidate_us": candidate_us}


func _time_fixture(fixture: Dictionary, operation: String, payload: Dictionary) -> int:
	var motion: Node = fixture.motion
	var started := Time.get_ticks_usec()
	match operation:
		"process":
			motion.call("_process", float(payload.delta))
		"cable":
			motion.call("_update_cable_followers", payload.angles, fixture.airplane.root)
		"dust":
			motion.call("_update_contact_dust", payload.state, fixture.contacts, payload.compression)
	return int(Time.get_ticks_usec() - started)


func _prepare_rough_slip(state: PackedFloat64Array) -> void:
	_restore_surface_inputs()
	var frame: Dictionary = GroundWheels.frame(state, _contacts[0], 0.0, _surfaces,
		PackedFloat64Array(), false, {})
	var position: PackedFloat64Array = frame.get("position", PackedFloat64Array())
	if position.size() < 2:
		_failures.append("rough-slip fixture could not find wheel ground position")
		return
	var index := GroundWheels.surface_at(_surfaces, float(position[0]), float(position[1]))
	if index < 0 or index + 5 >= _surfaces.size():
		_failures.append("rough-slip fixture could not locate a runway surface cell")
		return
	var rough := _surfaces.duplicate()
	rough[index + 5] = maxf(5.0, float(rough[index + 5]))
	var continuous := _continuous.duplicate()
	var wheel_start: int = _fixtures.baseline.session.wheel_index()
	if wheel_start >= 0 and wheel_start < continuous.size():
		continuous[wheel_start] = float(frame.get("long_speed", 0.0)) + 1.5
	for fixture: Dictionary in _fixtures.values():
		fixture.session.ground_surfaces = rough.duplicate()
		fixture.session.sim.continuous = continuous.duplicate()


func _restore_surface_inputs() -> void:
	for fixture: Dictionary in _fixtures.values():
		fixture.session.ground_surfaces = _surfaces.duplicate()
		fixture.session.sim.continuous = _continuous.duplicate()


func _capture_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append(_snapshot_pair("settled_rest", _loaded_state, false, true))
	result.append(_snapshot_pair("variable_compression_taxi", _taxi_b, false, true))
	result.append(_snapshot_pair("airborne", _airborne, false, true))
	result.append(_snapshot_pair("paused_focus_style", _loaded_state, true, true))
	for fixture: Dictionary in _fixtures.values():
		fixture.session.sim.set_paused(false)
		fixture.session.sim.state = _loaded_state.duplicate()
		fixture.session.sim.previous = _loaded_state.duplicate()
		fixture.motion.call("_on_session_resetting")
	result.append(_snapshot_pair("reset_rest", _loaded_state, false, false))
	for fixture: Dictionary in _fixtures.values():
		fixture.motion.call("_stop_after_crash")
	result.append(_snapshot_pair("wreck_stopped", _loaded_state, false, true))
	return result


func _resume_fixtures() -> void:
	for fixture: Dictionary in _fixtures.values():
		fixture.session.sim.set_paused(false)
		fixture.session.sim.state = _loaded_state.duplicate()
		fixture.session.sim.previous = _loaded_state.duplicate()
		fixture.motion.call("_on_session_resetting")


func _snapshot_pair(label: String, state: PackedFloat64Array, paused: bool, process: bool) -> Dictionary:
	var pair := {"pose": label, "baseline": {}, "candidate": {}}
	for side: String in ["baseline", "candidate"]:
		var fixture: Dictionary = _fixtures[side]
		fixture.session.sim.set_paused(paused)
		fixture.session.sim.state = state.duplicate()
		fixture.session.sim.previous = state.duplicate()
		if process:
			fixture.motion.call("_process", 1.0 / 60.0)
		pair[side] = _render_snapshot(fixture, label)
	return pair


func _render_snapshot(fixture: Dictionary, label: String) -> Dictionary:
	var session: Node = fixture.session
	var motion: Node = fixture.motion
	var followers: Array = motion.get("_spring_followers")
	return {
		"pose": label,
		"state_sha256": _hash(session.sim.state),
		"continuous_sha256": _hash(session.sim.continuous),
		"aux_sha256": _hash(session.sim.aux),
		"compression_m": Array(session.gear_compressions(session.sim.state)),
		"cables": _mesh_snapshot(motion.get("_cables")),
		"coils": followers.map(func(item: Dictionary) -> Dictionary: return _mesh_snapshot(item.node)),
		"legs": _leg_snapshot(motion),
		"dust": _dust_snapshot(motion),
	}


func _leg_snapshot(motion: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for leg: Dictionary in motion.get("_legs"):
		var hinge := leg.hinge as Node3D
		var wheel := leg.wheel as Node3D
		var axle := leg.axle as Node3D
		rows.append({
			"role": leg.role,
			"hinge_transform": var_to_str(hinge.transform),
			"wheel_position": [wheel.position.x, wheel.position.y, wheel.position.z],
			"axle_transform": var_to_str(axle.transform),
		})
	return rows


func _dust_snapshot(motion: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var emitters: Dictionary = motion.get("_dust_emitters")
	for key: Variant in emitters:
		var emitter := emitters[key] as CPUParticles3D
		rows.append({"index": int(key), "emitting": emitter.emitting, "speed_scale": emitter.speed_scale})
	return rows


func _mesh_snapshot(node: MeshInstance3D) -> Dictionary:
	if node == null or node.mesh == null:
		return {"valid": false}
	var mesh := node.mesh
	var bounds: AABB = mesh.get_aabb()
	var surfaces: Array[Dictionary] = []
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var material := mesh.surface_get_material(i)
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(var_to_bytes(arrays))
		surfaces.append({
			"index": i,
			"primitive": mesh.surface_get_primitive_type(i),
			"arrays_sha256": hasher.finish().hex_encode(),
			"material_class": material.get_class() if material != null else "null",
			"material_name": str(material.resource_name) if material != null else "",
		})
	return {
		"name": str(node.name),
		"surface_count": mesh.get_surface_count(),
		"aabb_position": [bounds.position.x, bounds.position.y, bounds.position.z],
		"aabb_size": [bounds.size.x, bounds.size.y, bounds.size.z],
		"surfaces": surfaces,
	}


func _compare_snapshots(before: Array[Dictionary], after: Array[Dictionary]) -> Array[Dictionary]:
	var checks: Array[Dictionary] = []
	if before.size() != after.size():
		_failures.append("snapshot pose count changed during profile")
		return checks
	for i in before.size():
		var pre: Dictionary = before[i]
		var post: Dictionary = after[i]
		var before_equal: bool = pre.baseline == pre.candidate
		var after_equal: bool = post.baseline == post.candidate
		var stable: bool = pre.baseline == post.baseline and pre.candidate == post.candidate
		if not before_equal or not after_equal:
			_failures.append("render parity failed at " + str(pre.pose))
		if not stable:
			_failures.append("profile mutated snapshot at " + str(pre.pose))
		checks.append({"pose": pre.pose, "before_exact_parity": before_equal,
			"after_exact_parity": after_equal, "measurement_preserved_snapshot": stable})
	return checks


func _check_inputs() -> Array[Dictionary]:
	var checks: Array[Dictionary] = []
	for side: String in ["baseline", "candidate"]:
		var session: Node = _fixtures[side].session
		var expected: bool = session.sim.state == _loaded_state \
			and session.sim.previous == _loaded_state \
			and session.sim.continuous == _continuous \
			and session.ground_surfaces == _surfaces
		checks.append({"fixture": side, "matched_final_state_and_previous": session.sim.state == _loaded_state \
			and session.sim.previous == _loaded_state, "continuous_unchanged": session.sim.continuous == _continuous,
			"ground_surfaces_unchanged": session.ground_surfaces == _surfaces, "passed": expected})
		if not expected:
			_failures.append(side + " visual observer altered its matched telemetry or field input")
	return checks


func _delta(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var total := 0.0
	for i in mini(a.size(), b.size()):
		total += absf(float(a[i] - b[i]))
	return total


func _hash(value: Variant) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(var_to_bytes(value))
	return hasher.finish().hex_encode()


func _sha(path: String) -> String:
	return FileAccess.get_sha256(path)


func _ratio(a: float, b: float) -> float:
	return a / b if b > 0.0 else 0.0


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var middle := int(ordered.size() / 2)
	return ordered[middle] if ordered.size() % 2 == 1 else (ordered[middle - 1] + ordered[middle]) * 0.5


func _write_report(report: Dictionary) -> void:
	report["failures"] = _failures
	var file := FileAccess.open(_out_dir.path_join("paired-profile.json"), FileAccess.WRITE)
	if file == null:
		printerr("could not write paired profile at ", _out_dir)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("TT-21 paired motion profile: %d cases, %d failures; %s" % [
		(report.get("paired_profiles", []) as Array).size(), _failures.size(),
		_out_dir.path_join("paired-profile.json")])


func _teardown() -> void:
	for fixture: Dictionary in _fixtures.values():
		var airplane: Dictionary = fixture.airplane
		if airplane.get("root") != null and is_instance_valid(airplane.root):
			airplane.root.queue_free()
		if is_instance_valid(fixture.session):
			fixture.session.queue_free()
	await process_frame
