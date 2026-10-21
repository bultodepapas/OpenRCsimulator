## Exploratory single-runtime CPU profile of the Turbo Lumber visual observer.
## The fixture writes synthetic presentation inputs to a private session, then restores it;
## it never changes app physics or measures rendered FPS. Do not compare separate runs as
## performance acceptance evidence; use motion_paired_profile.gd for alternating comparisons.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const Motion := preload("res://aircraft/timber_visual_motion.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const PROFILE_BATCHES := 60
const CALLS_PER_BATCH := 20
const VARIABLE_PAIRS_PER_BATCH := 10

var _out_dir := ""
var _session: Node
var _airplane: Dictionary = {}
var _motion: Node
var _contacts: Array = []
var _loaded_state := PackedFloat64Array()
var _taxi_state_a := PackedFloat64Array()
var _taxi_state_b := PackedFloat64Array()
var _airborne_state := PackedFloat64Array()
var _loaded_compression := PackedFloat64Array()
var _taxi_compression_a := PackedFloat64Array()
var _taxi_compression_b := PackedFloat64Array()
var _airborne_compression := PackedFloat64Array()
var _original_continuous := PackedFloat64Array()
var _original_surfaces := PackedFloat64Array()
var _failures: Array[String] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if _out_dir.is_empty():
		_out_dir = ProjectSettings.globalize_path("res://../tmp/timber-overhaul/motion-profile-baseline")
	_run.call_deferred()


func _run() -> void:
	if DirAccess.dir_exists_absolute(_out_dir):
		push_error("Pass a new --out directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var setup := _setup_fixture()
	if not bool(setup.get("ok", false)):
		_failures.append(str(setup.get("error", "profile fixture setup failed")))
		_write_report({"schema": "tt21-timber-motion-profile-v1", "failures": _failures})
		quit(1)
		return
	var pose_scan := _select_profile_states()
	var initial_snapshot := _render_snapshot("settled_rest")
	var process_profiles: Array[Dictionary] = []
	process_profiles.append(_measure_process("settled_rest", _set_and_process.bind(_loaded_state)))
	process_profiles.append(_measure_variable_process())
	process_profiles.append(_measure_process("airborne", _set_and_process.bind(_airborne_state)))
	_session.sim.set_paused(true)
	process_profiles.append(_measure_process("paused_focus_style", _set_and_process.bind(_loaded_state)))
	_session.sim.set_paused(false)
	var pause_snapshot := _render_snapshot("paused_focus_style")

	var contact_dust_profiles := _measure_contact_dust()
	var cable_profile := _measure_cable_updates()
	var loaded_snapshot := _pose_and_snapshot("variable_compression_taxi_b", _taxi_state_b)
	var reset_profile := _measure_reset_response()
	var reset_snapshot := _render_snapshot("reset_rest")
	var wreck_profile := _measure_wreck_response()
	var wreck_snapshot := _render_snapshot("wreck_stopped")
	var input_state_restore := _restore_session_inputs()
	var report := {
		"schema": "tt21-timber-motion-profile-v1",
		"profiling_mode": "single-runtime headless exploratory CPU microbenchmark; not an FPS measurement",
		"timing_status": "exploratory only; separate report runs are host-drift-confounded and do not establish optimization acceptance",
		"runtime_source": "app/aircraft/timber_visual_motion.gd",
		"runtime_sha256": FileAccess.get_sha256("res://aircraft/timber_visual_motion.gd"),
		"frozen_baseline_source": "research/timber/optimization/motion_baseline.gd",
		"frozen_baseline_sha256": FileAccess.get_sha256("res://../research/timber/optimization/motion_baseline.gd"),
		"engine_version": Engine.get_version_info(),
		"fixture": "private Turbo Lumber runway session; no engine/renderer frame-rate sampling",
		"input_states": pose_scan,
		"sample_design": {
			"warmup_calls": 40,
			"batches": PROFILE_BATCHES,
			"calls_per_batch": CALLS_PER_BATCH,
			"variable_compression_pairs_per_batch": VARIABLE_PAIRS_PER_BATCH,
			"timing_source": "Time.get_ticks_usec around CPU method batches",
		},
		"process_profiles": process_profiles,
		"contact_dust_profiles": contact_dust_profiles,
		"cable_and_coil_update_profile": cable_profile,
		"reset_response_profile": reset_profile,
		"wreck_response_profile": wreck_profile,
		"mesh_snapshots": [initial_snapshot, pause_snapshot, loaded_snapshot, reset_snapshot, wreck_snapshot],
		"fixture_session_inputs_restored": input_state_restore,
		"failures": _failures,
	}
	_write_report(report)
	print("TT-21 motion profile: %d process states, %d failures; report: %s" % [
		process_profiles.size(), _failures.size(), _out_dir.path_join("profile.json")])
	_teardown()
	quit(0 if _failures.is_empty() else 1)


func _setup_fixture() -> Dictionary:
	var entry: Dictionary = Catalog.entry("turbo-lumber-evolution")
	_session = Session.new()
	_session.input_enabled = false
	_session.setup(str(entry.data))
	if _session.sim == null or not _session.is_flyable():
		return {"ok": false, "error": "Turbo Lumber session did not initialize"}
	root.add_child(_session)
	var field_result: Dictionary = FieldLoader.load_from()
	if not bool(field_result.get("ok", false)) or not _session.set_field(field_result.get("field")):
		return {"ok": false, "error": "default field did not load"}
	_session.start_choice = Session.START_RUNWAY
	_session.reset()
	_airplane = Airplane.build("turbo-lumber-evolution")
	if _airplane.is_empty() or _airplane.get("root") == null:
		return {"ok": false, "error": "Turbo Lumber model did not build"}
	root.add_child(_airplane.root)
	GroundGear.attach(_airplane, _session)
	_motion = Motion.attach(_airplane, _session)
	if _motion == null:
		return {"ok": false, "error": "visual observer did not attach"}
	_contacts = _session.current_landing_gear().get("contacts", [])
	_loaded_state = _session.sim.state.duplicate()
	_original_continuous = _session.sim.continuous.duplicate()
	_original_surfaces = _session.ground_surfaces.duplicate()
	return {"ok": not _contacts.is_empty()}


func _select_profile_states() -> Dictionary:
	_loaded_compression = _session.gear_compressions(_loaded_state)
	var candidates: Array[Dictionary] = []
	var offsets := [-0.18, -0.10, -0.06, -0.03, -0.028, -0.025, -0.022,
		-0.020, -0.018, -0.015, -0.012, -0.009, -0.006, -0.003, 0.0,
		0.003, 0.006, 0.009, 0.015, 0.03, 0.06, 0.10, 0.18]
	for delta_down: float in offsets:
		var state := _loaded_state.duplicate()
		state[2] += delta_down
		var compression: PackedFloat64Array = _session.gear_compressions(state)
		var angles := _angles_for_compression(compression)
		candidates.append({"delta_down_m": delta_down, "compression_m": compression.duplicate(),
			"angles_rad": angles, "state": state.duplicate()})
	var best_a := PackedFloat64Array()
	var best_b := PackedFloat64Array()
	var best_a_comp := PackedFloat64Array()
	var best_b_comp := PackedFloat64Array()
	var best_a_angles: Array[float] = []
	var best_b_angles: Array[float] = []
	var max_pair_angle_delta := 0.0
	var airborne_score := INF
	_airborne_state = _loaded_state.duplicate()
	_airborne_compression = _loaded_compression.duplicate()
	for candidate: Dictionary in candidates:
		var compression: PackedFloat64Array = candidate.compression_m
		var sum_compression := 0.0
		for value: float in compression:
			sum_compression += maxf(0.0, value)
		if sum_compression < airborne_score:
			airborne_score = sum_compression
			_airborne_state = (candidate.state as PackedFloat64Array).duplicate()
			_airborne_compression = compression.duplicate()
	for first_index in candidates.size():
		var first: Dictionary = candidates[first_index]
		if not _candidate_is_loaded_unsaturated(first):
			continue
		for second_index in range(first_index + 1, candidates.size()):
			var second: Dictionary = candidates[second_index]
			if not _candidate_is_loaded_unsaturated(second):
				continue
			var angle_delta := _angle_delta(first.angles_rad, second.angles_rad)
			if angle_delta > max_pair_angle_delta:
				max_pair_angle_delta = angle_delta
				best_a = (first.state as PackedFloat64Array).duplicate()
				best_b = (second.state as PackedFloat64Array).duplicate()
				best_a_comp = (first.compression_m as PackedFloat64Array).duplicate()
				best_b_comp = (second.compression_m as PackedFloat64Array).duplicate()
				best_a_angles = first.angles_rad
				best_b_angles = second.angles_rad
	if best_a_comp.size() < 2 or best_b_comp.size() < 2 or max_pair_angle_delta <= 1.0e-4:
		_failures.append("could not find distinct unsaturated loaded compression states")
		best_a = _loaded_state.duplicate()
		best_b = _loaded_state.duplicate()
		best_b[2] -= 0.012
		best_a_comp = _session.gear_compressions(best_a)
		best_b_comp = _session.gear_compressions(best_b)
		best_a_angles = _angles_for_compression(best_a_comp)
		best_b_angles = _angles_for_compression(best_b_comp)
	_taxi_state_a = best_a.duplicate()
	_taxi_state_b = best_b.duplicate()
	_taxi_state_a[3] = 2.0
	_taxi_state_b[3] = 2.0
	_taxi_compression_a = _session.gear_compressions(_taxi_state_a)
	_taxi_compression_b = _session.gear_compressions(_taxi_state_b)
	_airborne_state[3] = 12.0
	_airborne_compression = _session.gear_compressions(_airborne_state)
	return {
		"settled_rest_compression_m": Array(_loaded_compression),
		"variable_taxi_a_compression_m": Array(_taxi_compression_a),
		"variable_taxi_b_compression_m": Array(_taxi_compression_b),
		"variable_taxi_compression_l1_delta_m": _compression_delta(_taxi_compression_a, _taxi_compression_b),
		"variable_taxi_a_hinge_degrees": best_a_angles.map(func(value: float) -> float: return rad_to_deg(value)),
		"variable_taxi_b_hinge_degrees": best_b_angles.map(func(value: float) -> float: return rad_to_deg(value)),
		"variable_taxi_hinge_angle_l1_delta_degrees": rad_to_deg(max_pair_angle_delta),
		"airborne_compression_m": Array(_airborne_compression),
		"candidate_down_offsets": candidates.map(func(row: Dictionary) -> Dictionary:
			return {"delta_down_m": row.delta_down_m, "compression_m": Array(row.compression_m),
				"hinge_degrees": row.angles_rad.map(func(value: float) -> float: return rad_to_deg(value))}),
	}


func _angles_for_compression(compression: PackedFloat64Array) -> Array[float]:
	var angles: Array[float] = []
	var up_root: Vector3 = _airplane.root.global_basis.transposed() * Vector3.UP
	for leg: Dictionary in _motion._legs:
		var index: int = leg.contact_index
		if index < 0 or index >= compression.size():
			angles.append(0.0)
			continue
		var amount := clampf(float(compression[index]), 0.0,
			float(leg.contact.get("max_compression", 0.10)))
		var axis: Vector3 = leg.axis_root
		var arm: Vector3 = leg.tip_root - leg.pivot_root
		var max_height := maxf(0.0, _motion._height_for_angle(axis, arm, _motion._max_travel_rad, up_root))
		angles.append(_motion._suspension_angle(leg, minf(amount, max_height), up_root))
	return angles


func _candidate_is_loaded_unsaturated(candidate: Dictionary) -> bool:
	var compression: PackedFloat64Array = candidate.compression_m
	var angles: Array[float] = candidate.angles_rad
	if compression.size() < 2 or angles.size() < 2:
		return false
	for leg_index in 2:
		var leg: Dictionary = _motion._legs[leg_index]
		if compression[leg.contact_index] <= 0.0:
			return false
		if angles[leg_index] <= 1.0e-4 or angles[leg_index] >= _motion._max_travel_rad - 1.0e-3:
			return false
	return true


func _angle_delta(left: Array[float], right: Array[float]) -> float:
	if left.size() < 2 or right.size() < 2:
		return 0.0
	return absf(left[0] - right[0]) + absf(left[1] - right[1])


func _compression_delta(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	var total := 0.0
	for index in mini(left.size(), right.size()):
		total += absf(float(left[index] - right[index]))
	return total


func _set_state(state: PackedFloat64Array) -> void:
	_session.sim.state = state.duplicate()
	_session.sim.previous = state.duplicate()


func _set_and_process(state: PackedFloat64Array) -> void:
	_set_state(state)
	_motion._process(1.0 / 60.0)


func _measure_process(label: String, operation: Callable) -> Dictionary:
	for _warm in 40:
		operation.call()
	var samples: Array[float] = []
	for _batch in PROFILE_BATCHES:
		var start_usec := Time.get_ticks_usec()
		for _call in CALLS_PER_BATCH:
			operation.call()
		var elapsed_usec := Time.get_ticks_usec() - start_usec
		samples.append(float(elapsed_usec) / float(CALLS_PER_BATCH))
	return _summary(label, samples, CALLS_PER_BATCH * PROFILE_BATCHES)


func _measure_variable_process() -> Dictionary:
	for _warm in 20:
		_set_and_process(_taxi_state_a)
		_set_and_process(_taxi_state_b)
	var samples: Array[float] = []
	for _batch in PROFILE_BATCHES:
		var total_usec := 0
		for _pair in VARIABLE_PAIRS_PER_BATCH:
			_set_state(_taxi_state_a)
			var start_a := Time.get_ticks_usec()
			_motion._process(1.0 / 60.0)
			total_usec += Time.get_ticks_usec() - start_a
			_set_state(_taxi_state_b)
			var start_b := Time.get_ticks_usec()
			_motion._process(1.0 / 60.0)
			total_usec += Time.get_ticks_usec() - start_b
		samples.append(float(total_usec) / float(VARIABLE_PAIRS_PER_BATCH * 2))
	return _summary("variable_compression_taxi", samples, VARIABLE_PAIRS_PER_BATCH * 2 * PROFILE_BATCHES)


func _measure_contact_dust() -> Array[Dictionary]:
	_set_state(_taxi_state_a)
	var contact: Dictionary = _contacts[0]
	var state: PackedFloat64Array = _taxi_state_a
	var frame: Dictionary = GroundWheels.frame(state, contact, 0.0, _original_surfaces,
		PackedFloat64Array(), false, {})
	var surface_position: PackedFloat64Array = frame.get("position", PackedFloat64Array())
	var surface_index := GroundWheels.surface_at(_original_surfaces,
		float(surface_position[0]), float(surface_position[1]))
	var paved := _measure_process("contact_dust_paved_no_slip",
		Callable(self, "_profile_dust_current").bind(state, _taxi_compression_a))
	var profiles: Array[Dictionary] = [paved]
	if surface_index < 0 or surface_index + 5 >= _original_surfaces.size():
		_failures.append("dust profile could not locate the runway surface cell")
		return profiles
	var rough_surfaces := _original_surfaces.duplicate()
	rough_surfaces[surface_index + 5] = maxf(5.0, float(rough_surfaces[surface_index + 5]))
	_session.ground_surfaces = rough_surfaces
	var first_wheel: int = _session.wheel_index()
	var continuous: PackedFloat64Array = _session.sim.continuous.duplicate()
	if first_wheel >= 0 and first_wheel < continuous.size():
		continuous[first_wheel] = float(frame.get("long_speed", 0.0)) + 1.5
		_session.sim.continuous = continuous
	var rough := _measure_process("contact_dust_synthetic_rough_slip",
		Callable(self, "_profile_dust_current").bind(state, _taxi_compression_a))
	profiles.append(rough)
	_session.ground_surfaces = _original_surfaces.duplicate()
	_session.sim.continuous = _original_continuous.duplicate()
	return profiles


func _profile_dust_current(state: PackedFloat64Array, compression: PackedFloat64Array) -> void:
	_motion._update_contact_dust(state, _contacts, compression)


func _measure_cable_updates() -> Dictionary:
	var angle_a := {"left": deg_to_rad(2.0), "right": deg_to_rad(3.5)}
	var angle_b := {"left": deg_to_rad(5.5), "right": deg_to_rad(1.0)}
	var use_a := false
	var samples: Array[float] = []
	for _warm in 40:
		use_a = not use_a
		_motion._update_cable_followers(angle_a if use_a else angle_b, _airplane.root)
	for _batch in PROFILE_BATCHES:
		var start_usec := Time.get_ticks_usec()
		for _call in CALLS_PER_BATCH:
			use_a = not use_a
			_motion._update_cable_followers(angle_a if use_a else angle_b, _airplane.root)
		var elapsed_usec := Time.get_ticks_usec() - start_usec
		samples.append(float(elapsed_usec) / float(CALLS_PER_BATCH))
	_motion._on_session_resetting()
	return {
		"profile": _summary("cable_and_coil_vertices_variable_pose", samples, CALLS_PER_BATCH * PROFILE_BATCHES),
		"main_cable_surfaces": _surface_summary(_motion._cables.mesh),
		"coil_surfaces": _motion._spring_followers.map(func(follower: Dictionary) -> Dictionary:
			return {"name": follower.node.name, "surfaces": _surface_summary(follower.mesh)}),
		"operation_cost": "per-vertex position update followed by clear_surfaces/add_surface_from_arrays for each dynamic surface",
	}


func _measure_reset_response() -> Dictionary:
	var samples: Array[float] = []
	for _warm in 20:
		_set_and_process(_taxi_state_a)
		_set_and_process(_taxi_state_b)
		_motion._on_session_resetting()
	for _batch in PROFILE_BATCHES:
		var total_usec := 0
		for _call in CALLS_PER_BATCH:
			_set_and_process(_taxi_state_b)
			var start_usec := Time.get_ticks_usec()
			_motion._on_session_resetting()
			total_usec += Time.get_ticks_usec() - start_usec
		samples.append(float(total_usec) / float(CALLS_PER_BATCH))
	return _summary("reset_signal_visual_response", samples, CALLS_PER_BATCH * PROFILE_BATCHES)


func _measure_wreck_response() -> Dictionary:
	_motion._stop_after_crash()
	return _measure_process("wreck_stopped_early_return", Callable(self, "_call_stopped_process"))


func _call_stopped_process() -> void:
	_motion._process(1.0 / 60.0)


func _summary(label: String, samples: Array[float], operation_count: int) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var min_value := INF
	var max_value := -INF
	for value: float in samples:
		total += value
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)
	var mean := total / maxf(float(samples.size()), 1.0)
	return {
		"case": label,
		"operation_count": operation_count,
		"batches": samples.size(),
		"mean_us_per_call": mean,
		"median_us_per_call": _percentile(sorted, 0.50),
		"p95_us_per_call": _percentile(sorted, 0.95),
		"max_batch_mean_us_per_call": max_value,
		"min_batch_mean_us_per_call": min_value,
		"calls_in_each_timed_batch": CALLS_PER_BATCH,
	}


func _percentile(sorted: Array[float], percentile: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(ceili(float(sorted.size() - 1) * percentile), 0, sorted.size() - 1)]


func _pose_and_snapshot(label: String, state: PackedFloat64Array) -> Dictionary:
	_set_and_process(state)
	return _render_snapshot(label)


func _render_snapshot(label: String) -> Dictionary:
	return {
		"pose": label,
		"state_sha256": _hash_value(_session.sim.state),
		"continuous_sha256": _hash_value(_session.sim.continuous),
		"compression_m": Array(_session.gear_compressions(_session.sim.state)),
		"cables": _mesh_snapshot(_motion._cables),
		"coils": _motion._spring_followers.map(func(follower: Dictionary) -> Dictionary:
			return _mesh_snapshot(follower.node)),
		"leg_transforms": _leg_transform_snapshot(),
	}


func _leg_transform_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for leg: Dictionary in _motion._legs:
		var hinge := leg.hinge as Node3D
		var wheel := leg.wheel as Node3D
		var axle := leg.axle as Node3D
		out.append({
			"role": leg.role,
			"hinge_transform": var_to_str(hinge.transform),
			"wheel_position": [wheel.position.x, wheel.position.y, wheel.position.z],
			"axle_transform": var_to_str(axle.transform),
		})
	return out


func _mesh_snapshot(node: MeshInstance3D) -> Dictionary:
	if node == null or node.mesh == null:
		return {"valid": false}
	var mesh := node.mesh
	var bounds: AABB = mesh.get_aabb()
	return {
		"name": str(node.name),
		"resource_id": mesh.get_instance_id(),
		"resource_path": mesh.resource_path,
		"surface_count": mesh.get_surface_count(),
		"aabb_position": [bounds.position.x, bounds.position.y, bounds.position.z],
		"aabb_size": [bounds.size.x, bounds.size.y, bounds.size.z],
		"surfaces": _surface_summary(mesh),
	}


func _surface_summary(mesh: ArrayMesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var surface_hasher := HashingContext.new()
	surface_hasher.start(HashingContext.HASH_SHA256)
	for surface_index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertex_data: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index_data: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := mesh.surface_get_material(surface_index)
		var material_name := str(material.resource_name) if material != null else ""
		surface_hasher.update(var_to_bytes(arrays))
		surface_hasher.update(var_to_bytes(material_name))
		out.append({
			"surface_index": surface_index,
			"primitive": mesh.surface_get_primitive_type(surface_index),
			"vertex_count": vertex_data.size(),
			"index_count": index_data.size(),
			"material_class": material.get_class() if material != null else "null",
			"material_name": material_name,
		})
	var digest := surface_hasher.finish().hex_encode()
	if not out.is_empty():
		out[0]["geometry_sha256"] = digest
	return out


func _hash_value(value: Variant) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(var_to_bytes(value))
	return hasher.finish().hex_encode()


func _restore_session_inputs() -> bool:
	_session.sim.set_paused(false)
	_session.sim.continuous = _original_continuous.duplicate()
	_session.ground_surfaces = _original_surfaces.duplicate()
	_session.sim.state = _loaded_state.duplicate()
	_session.sim.previous = _loaded_state.duplicate()
	return _session.sim.continuous == _original_continuous \
		and _session.ground_surfaces == _original_surfaces


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(_out_dir.path_join("profile.json"), FileAccess.WRITE)
	if file == null:
		printerr("could not write motion profile: ", _out_dir)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")


func _teardown() -> void:
	if is_instance_valid(_motion):
		_motion.queue_free()
	if _airplane.get("root") != null and is_instance_valid(_airplane.root):
		_airplane.root.queue_free()
	if is_instance_valid(_session):
		_session.queue_free()
	await process_frame
