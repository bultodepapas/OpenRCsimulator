extends SceneTree
## Exact CPU-side comparison and paired batches for a frozen and working windsock renderer.
## This does not measure a full flight or GPU work.

const Candidate = preload("res://render/windsock.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Motion = preload("res://render/windsock_motion.gd")
const PHYSICS_HZ: int = 240
const TAPE_TICKS: int = 2400
const RENDER_EVERY_TICKS: int = 4
const TIMING_BATCHES: int = 30
const TICKS_PER_BATCH: int = 240
const BUILD_TIMING_PAIRS: int = 10
const DETAIL_LIMIT: int = 48

var _baseline: Variant
var _baseline_path: String = ""
var _out_path: String = ""
var _mismatch_count: int = 0
var _mismatches: Array[Dictionary] = []
var _render_checks: int = 0
var _motion_checks: int = 0
var _bounds_checks: int = 0
var _static_mesh_cases: int = 0


func _initialize() -> void:
	var options: Dictionary = _parse_args(OS.get_cmdline_user_args())
	_baseline_path = str(options.get("baseline", "")).replace("\\", "/")
	_out_path = str(options.get("out", "")).replace("\\", "/")
	if _baseline_path.is_empty() or _out_path.is_empty():
		printerr("--baseline=<absolute .gd path> and --out=<absolute JSON path> are required")
		quit(2)
		return
	if not _baseline_path.is_absolute_path() or not _out_path.is_absolute_path():
		printerr("--baseline and --out must be absolute paths")
		quit(2)
		return
	if not FileAccess.file_exists(_baseline_path):
		printerr("baseline renderer does not exist: " + _baseline_path)
		quit(2)
		return
	_baseline = load(_baseline_path)
	if _baseline == null or not _baseline is GDScript:
		printerr("could not load baseline GDScript: " + _baseline_path)
		quit(2)
		return
	_run()


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	if not bool(loaded.get("ok", false)):
		printerr("default field failed validation: " + str(loaded.get("errors", [])))
		quit(1)
		return
	var cues: Array = loaded.get("field", {}).get("flight_cues", []).filter(
		func(cue: Dictionary) -> bool: return cue.get("type") == "windsock")
	if cues.size() != 1:
		printerr("expected exactly one validated default windsock cue")
		quit(1)
		return
	var cue: Dictionary = cues[0]
	var baseline_model: Node3D = _baseline.build(cue.duplicate(true))
	var candidate_model: Node3D = Candidate.build(cue.duplicate(true))
	var static_mesh_report: Dictionary = _compare_static_meshes(cue, baseline_model, candidate_model)
	_run_equivalence(baseline_model, candidate_model)
	baseline_model.free()
	candidate_model.free()
	var bounds_report: Dictionary = _compare_bounds(cue)
	var timing_report: Dictionary = _measure_paired(cue)
	var build_timing_report: Dictionary = _measure_build_paired(cue)
	var report := {
		"format": "openrc-windsock-optimization-compare v1",
		"passed": _mismatch_count == 0,
		"godot": Engine.get_version_info().string,
		"platform": OS.get_name(),
		"fixture": "validated default field windsock",
		"tape": {
			"physics_hz": PHYSICS_HZ,
			"ticks": TAPE_TICKS,
			"render_every_ticks": RENDER_EVERY_TICKS,
			"events": [
				{"name": "calm", "seconds": [0.0, 2.0]},
				{"name": "gust", "seconds": [2.0, 4.0]},
				{"name": "turn", "seconds": [4.0, 6.0]},
				{"name": "reversal", "seconds": [6.0, 8.0]},
				{"name": "updraft", "seconds": [8.0, 10.0]},
			],
		},
		"checks": {
			"motion_state_ticks": _motion_checks,
			"rendered_frames": _render_checks,
			"direct_bounds_cases": _bounds_checks,
			"static_mesh_cases": _static_mesh_cases,
			"build_timing_pairs": BUILD_TIMING_PAIRS,
			"mismatches": _mismatch_count,
			"mismatch_details_limit": DETAIL_LIMIT,
		},
		"mismatches": _mismatches,
		"static_mesh": static_mesh_report,
		"direct_bounds": bounds_report,
		"timing": timing_report,
		"build_timing": build_timing_report,
		"sources_sha256": {
			"baseline_renderer": FileAccess.get_sha256(_baseline_path),
			"candidate_renderer": FileAccess.get_sha256("res://render/windsock.gd"),
			"motion": FileAccess.get_sha256("res://render/windsock_motion.gd"),
			"harness": FileAccess.get_sha256(get_script().resource_path),
		},
		"limitations": "Headless CPU component measurements only; no GPU timing, image comparison, or full-flight frame-time claim.",
	}
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot create comparison output: " + _out_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("Windsock comparison: %d checks, %d mismatches; wrote %s" % [
		_motion_checks + _render_checks + _bounds_checks + _static_mesh_cases,
		_mismatch_count, _out_path])
	quit(0 if _mismatch_count == 0 else 1)


func _compare_static_meshes(
		cue: Dictionary, baseline_default: Node3D, candidate_default: Node3D) -> Dictionary:
	var cases: Array[Dictionary] = []
	cases.append(_compare_static_mesh_case("default", baseline_default, candidate_default))
	var fixtures: Array[Dictionary] = [
		{"name": "minimum_valid_dimensions", "length": 0.5, "pole_height": 2.0,
			"throat_diameter": 0.1, "tail_diameter": 0.05},
		{"name": "maximum_valid_dimensions", "length": 5.0, "pole_height": 10.0,
			"throat_diameter": 1.0, "tail_diameter": 0.99},
		{"name": "non_round_valid_dimensions", "length": 1.234567, "pole_height": 3.6,
			"throat_diameter": 0.314159, "tail_diameter": 0.12345},
	]
	for fixture: Dictionary in fixtures:
		var fixture_cue: Dictionary = cue.duplicate(true)
		fixture_cue.length = fixture.length
		fixture_cue.pole_height = fixture.pole_height
		fixture_cue.throat_diameter = fixture.throat_diameter
		fixture_cue.tail_diameter = fixture.tail_diameter
		var baseline_root: Node3D = _baseline.build(fixture_cue.duplicate(true))
		var candidate_root: Node3D = Candidate.build(fixture_cue.duplicate(true))
		cases.append(_compare_static_mesh_case(str(fixture.name), baseline_root, candidate_root))
		baseline_root.free()
		candidate_root.free()
	return {"cases": cases, "case_count": cases.size()}


func _compare_static_mesh_case(
		case_name: String, baseline_root: Node3D, candidate_root: Node3D) -> Dictionary:
	var mismatch_start: int = _mismatch_count
	for node_name: String in ["Fabric", "Support", "Basket"]:
		var context := {"case": case_name, "mesh": node_name}
		var baseline_instance: MeshInstance3D = baseline_root.get_node_or_null(node_name) as MeshInstance3D
		var candidate_instance: MeshInstance3D = candidate_root.get_node_or_null(node_name) as MeshInstance3D
		_compare_value("static_mesh.instance_present", baseline_instance != null,
			candidate_instance != null, context)
		if baseline_instance == null or candidate_instance == null:
			continue
		_compare_value("static_mesh.instance_transform",
			_transform_value(baseline_instance.transform), _transform_value(candidate_instance.transform), context)
		_compare_value("static_mesh.instance_custom_aabb",
			_aabb_value(baseline_instance.custom_aabb), _aabb_value(candidate_instance.custom_aabb), context)
		var baseline_mesh: Mesh = baseline_instance.mesh
		var candidate_mesh: Mesh = candidate_instance.mesh
		_compare_value("static_mesh.mesh_present", baseline_mesh != null,
			candidate_mesh != null, context)
		if baseline_mesh == null or candidate_mesh == null:
			continue
		_compare_value("static_mesh.mesh_aabb",
			_aabb_value(baseline_mesh.get_aabb()), _aabb_value(candidate_mesh.get_aabb()), context)
		var baseline_surface_count: int = baseline_mesh.get_surface_count()
		var candidate_surface_count: int = candidate_mesh.get_surface_count()
		_compare_value("static_mesh.surface_count", baseline_surface_count,
			candidate_surface_count, context)
		for surface_index: int in range(maxi(baseline_surface_count, candidate_surface_count)):
			var surface_context: Dictionary = context.duplicate(true)
			surface_context.surface = surface_index
			var baseline_has_surface: bool = surface_index < baseline_surface_count
			var candidate_has_surface: bool = surface_index < candidate_surface_count
			_compare_value("static_mesh.surface_present", baseline_has_surface,
				candidate_has_surface, surface_context)
			if not baseline_has_surface or not candidate_has_surface:
				continue
			_compare_value("static_mesh.primitive_type",
				baseline_mesh.surface_get_primitive_type(surface_index),
				candidate_mesh.surface_get_primitive_type(surface_index), surface_context)
			var baseline_arrays: Array = baseline_mesh.surface_get_arrays(surface_index)
			var candidate_arrays: Array = candidate_mesh.surface_get_arrays(surface_index)
			_compare_value("static_mesh.surface_array_slots", baseline_arrays.size(),
				candidate_arrays.size(), surface_context)
			var baseline_vertices: Variant = _surface_array(baseline_arrays, Mesh.ARRAY_VERTEX)
			var candidate_vertices: Variant = _surface_array(candidate_arrays, Mesh.ARRAY_VERTEX)
			var baseline_indices: Variant = _surface_array(baseline_arrays, Mesh.ARRAY_INDEX)
			var candidate_indices: Variant = _surface_array(candidate_arrays, Mesh.ARRAY_INDEX)
			_compare_value("static_mesh.vertex_count", _packed_array_count(baseline_vertices),
				_packed_array_count(candidate_vertices), surface_context)
			_compare_value("static_mesh.index_count", _packed_array_count(baseline_indices),
				_packed_array_count(candidate_indices), surface_context)
			for array_index: int in range(maxi(baseline_arrays.size(), candidate_arrays.size())):
				var array_context: Dictionary = surface_context.duplicate(true)
				array_context.array = array_index
				var baseline_value: Variant = baseline_arrays[array_index] \
					if array_index < baseline_arrays.size() else null
				var candidate_value: Variant = candidate_arrays[array_index] \
					if array_index < candidate_arrays.size() else null
				_compare_value("static_mesh.array_type", typeof(baseline_value),
					typeof(candidate_value), array_context)
				_compare_value("static_mesh.array_element_count", _packed_array_count(baseline_value),
					_packed_array_count(candidate_value), array_context)
				var baseline_bytes: PackedByteArray = _surface_array_bytes(baseline_value)
				var candidate_bytes: PackedByteArray = _surface_array_bytes(candidate_value)
				if baseline_bytes != candidate_bytes:
					_compare_value("static_mesh.array_bytes",
						_byte_summary(baseline_bytes), _byte_summary(candidate_bytes), array_context, true)
	_static_mesh_cases += 1
	return {"case": case_name, "exact": _mismatch_count == mismatch_start}


func _surface_array(arrays: Array, index: int) -> Variant:
	return arrays[index] if index < arrays.size() else null


func _packed_array_count(value: Variant) -> int:
	if value is PackedByteArray or value is PackedInt32Array or value is PackedInt64Array \
			or value is PackedFloat32Array or value is PackedFloat64Array \
			or value is PackedStringArray or value is PackedVector2Array \
			or value is PackedVector3Array or value is PackedVector4Array \
			or value is PackedColorArray:
		return value.size()
	return -1


func _surface_array_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if value is PackedInt32Array or value is PackedInt64Array \
			or value is PackedFloat32Array or value is PackedFloat64Array \
			or value is PackedVector2Array or value is PackedVector3Array \
			or value is PackedVector4Array or value is PackedColorArray:
		return value.to_byte_array()
	return var_to_bytes(value)


func _byte_summary(bytes: PackedByteArray) -> Dictionary:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return {"byte_count": bytes.size(), "sha256": hash.finish().hex_encode()}


func _run_equivalence(baseline_model: Node3D, candidate_model: Node3D) -> void:
	for tick: int in range(1, TAPE_TICKS + 1):
		var time_s: float = float(tick) / float(PHYSICS_HZ)
		var wind: Array = _wind_for(time_s)
		_baseline.advance(baseline_model, time_s, wind)
		Candidate.advance(candidate_model, time_s, wind)
		_motion_checks += 1
		_compare_snapshots("motion", _motion_snapshot(baseline_model),
			_motion_snapshot(candidate_model), {"tick": tick, "time_s": time_s})
		if tick % RENDER_EVERY_TICKS == 0:
			_baseline.update(baseline_model, time_s, wind)
			Candidate.update(candidate_model, time_s, wind)
			_render_checks += 1
			_compare_snapshots("render", _render_snapshot(baseline_model),
				_render_snapshot(candidate_model), {"tick": tick, "time_s": time_s})


func _compare_bounds(cue: Dictionary) -> Dictionary:
	var default_dimensions: Dictionary = _dimensions(cue)
	var extreme_dimensions := {
		"length_m": 5.0,
		"height_m": 10.0,
		"throat_diameter_m": 1.0,
		"tail_diameter_m": 0.99,
		"arm_m": 0.60,
	}
	var cases: Array[Dictionary] = []
	var default_motion: Variant = Motion.new(
		float(cue.length), float(cue.throat_diameter), float(cue.tail_diameter))
	default_motion.reset(0.0, [0.0, 0.0, 0.0])
	default_motion.update_to(0.5, [0.0, 7.0, -1.0])
	cases.append({"name": "default", "dimensions": default_dimensions,
		"chain": default_motion.centerline_local.duplicate()})
	var extreme_motion: Variant = Motion.new(5.0, 1.0, 0.99)
	extreme_motion.reset(0.0, [0.0, 0.0, 0.0])
	extreme_motion.update_to(0.5, [0.0, 12.0, -4.0])
	cases.append({"name": "maximum_valid_dimensions", "dimensions": extreme_dimensions,
		"chain": extreme_motion.centerline_local.duplicate()})
	var poses: Array[Dictionary] = [
		{"name": "calm", "yaw": 0.0, "inflation": 0.0},
		{"name": "quarter_turn_partial", "yaw": PI * 0.5, "inflation": 0.5},
		{"name": "reversed_full", "yaw": -PI * 0.75, "inflation": 1.0},
	]
	var results: Array[Dictionary] = []
	for test_case: Dictionary in cases:
		for pose: Dictionary in poses:
			var baseline_bounds: AABB = _baseline._fabric_bounds(
				test_case.chain, float(pose.yaw), float(pose.inflation), test_case.dimensions)
			var candidate_bounds: AABB = Candidate._fabric_bounds(
				test_case.chain, float(pose.yaw), float(pose.inflation), test_case.dimensions)
			var context := {"case": test_case.name, "pose": pose.name,
				"yaw": pose.yaw, "inflation": pose.inflation}
			_bounds_checks += 1
			_compare_value("direct_bounds", _aabb_value(baseline_bounds),
				_aabb_value(candidate_bounds), context)
			results.append({"case": test_case.name, "pose": pose.name,
				"baseline": _aabb_value(baseline_bounds),
				"candidate": _aabb_value(candidate_bounds),
				"exact": baseline_bounds == candidate_bounds})
	return {"checks": _bounds_checks, "cases": results}


func _measure_paired(cue: Dictionary) -> Dictionary:
	var active_baseline: Node3D = _baseline.build(cue.duplicate(true))
	var active_candidate: Node3D = Candidate.build(cue.duplicate(true))
	var paused_baseline: Node3D = _baseline.build(cue.duplicate(true))
	var paused_candidate: Node3D = Candidate.build(cue.duplicate(true))
	var warm_ticks: int = 600
	for tick: int in range(1, warm_ticks + 1):
		var time_s: float = float(tick) / float(PHYSICS_HZ)
		var wind: Array = _wind_for(time_s)
		_baseline.advance(active_baseline, time_s, wind)
		Candidate.advance(active_candidate, time_s, wind)
		_baseline.advance(paused_baseline, time_s, wind)
		Candidate.advance(paused_candidate, time_s, wind)
		if tick % RENDER_EVERY_TICKS == 0:
			_baseline.update(active_baseline, time_s, wind)
			Candidate.update(active_candidate, time_s, wind)
			_baseline.update(paused_baseline, time_s, wind)
			Candidate.update(paused_candidate, time_s, wind)
	var active_samples: Array[Dictionary] = []
	for batch: int in TIMING_BATCHES:
		var first: String = "baseline" if batch % 2 == 0 else "candidate"
		var start_tick: int = warm_ticks + 1 + batch * TICKS_PER_BATCH
		var baseline_usec: int
		var candidate_usec: int
		if first == "baseline":
			baseline_usec = _measure_active(_baseline, active_baseline, start_tick)
			candidate_usec = _measure_active(Candidate, active_candidate, start_tick)
		else:
			candidate_usec = _measure_active(Candidate, active_candidate, start_tick)
			baseline_usec = _measure_active(_baseline, active_baseline, start_tick)
		active_samples.append({"batch": batch, "first": first,
			"baseline_batch_usec": baseline_usec, "candidate_batch_usec": candidate_usec,
			"candidate_minus_baseline_usec": candidate_usec - baseline_usec})
		_compare_snapshots("active_timing_state", _motion_snapshot(active_baseline),
			_motion_snapshot(active_candidate), {"batch": batch})
	var paused_time: float = float(warm_ticks) / float(PHYSICS_HZ)
	var paused_wind: Array = _wind_for(paused_time)
	var paused_samples: Array[Dictionary] = []
	for batch: int in TIMING_BATCHES:
		var first: String = "baseline" if batch % 2 == 0 else "candidate"
		var baseline_usec: int
		var candidate_usec: int
		if first == "baseline":
			baseline_usec = _measure_paused(_baseline, paused_baseline, paused_time, paused_wind)
			candidate_usec = _measure_paused(Candidate, paused_candidate, paused_time, paused_wind)
		else:
			candidate_usec = _measure_paused(Candidate, paused_candidate, paused_time, paused_wind)
			baseline_usec = _measure_paused(_baseline, paused_baseline, paused_time, paused_wind)
		paused_samples.append({"batch": batch, "first": first,
			"baseline_batch_usec": baseline_usec, "candidate_batch_usec": candidate_usec,
			"candidate_minus_baseline_usec": candidate_usec - baseline_usec})
		_compare_snapshots("paused_timing_state", _motion_snapshot(paused_baseline),
			_motion_snapshot(paused_candidate), {"batch": batch})
	active_baseline.free()
	active_candidate.free()
	paused_baseline.free()
	paused_candidate.free()
	return {
		"method": "paired alternating order; elapsed microseconds per 240-tick active batch and 60-update paused batch",
		"batches_per_case": TIMING_BATCHES,
		"active_advancing": _summarize_timing(active_samples),
		"paused_same_time": _summarize_timing(paused_samples),
	}


func _measure_build_paired(cue: Dictionary) -> Dictionary:
	var warm_baseline: Node3D = _baseline.build(cue.duplicate(true))
	var warm_candidate: Node3D = Candidate.build(cue.duplicate(true))
	warm_baseline.free()
	warm_candidate.free()
	var samples: Array[Dictionary] = []
	for pair: int in BUILD_TIMING_PAIRS:
		var first: String = "baseline" if pair % 2 == 0 else "candidate"
		var baseline_usec: int
		var candidate_usec: int
		if first == "baseline":
			baseline_usec = _measure_build(_baseline, cue)
			candidate_usec = _measure_build(Candidate, cue)
		else:
			candidate_usec = _measure_build(Candidate, cue)
			baseline_usec = _measure_build(_baseline, cue)
		samples.append({"pair": pair, "first": first,
			"baseline_build_usec": baseline_usec, "candidate_build_usec": candidate_usec,
			"candidate_minus_baseline_usec": candidate_usec - baseline_usec})
	return {
		"method": "10 alternating-order within-process pairs; one default-cue build per sample; cue copies and root disposal outside timers",
		"fixture": "validated default field windsock",
		"pairs": BUILD_TIMING_PAIRS,
		"construction": _summarize_build_timing(samples),
	}


func _measure_build(script: Variant, cue: Dictionary) -> int:
	var build_cue: Dictionary = cue.duplicate(true)
	var began: int = Time.get_ticks_usec()
	var root: Node3D = script.build(build_cue)
	var elapsed: int = Time.get_ticks_usec() - began
	if root != null:
		root.free()
	return elapsed


func _measure_active(script: Variant, model: Node3D, start_tick: int) -> int:
	var began: int = Time.get_ticks_usec()
	for offset: int in TICKS_PER_BATCH:
		var tick: int = start_tick + offset
		var time_s: float = float(tick) / float(PHYSICS_HZ)
		var wind: Array = _wind_for(time_s)
		script.advance(model, time_s, wind)
		if tick % RENDER_EVERY_TICKS == 0:
			script.update(model, time_s, wind)
	return Time.get_ticks_usec() - began


func _measure_paused(script: Variant, model: Node3D, time_s: float, wind: Array) -> int:
	var began: int = Time.get_ticks_usec()
	for _update: int in 60:
		script.update(model, time_s, wind)
	return Time.get_ticks_usec() - began


func _summarize_timing(samples: Array[Dictionary]) -> Dictionary:
	var baseline_values: Array[float] = []
	var candidate_values: Array[float] = []
	for sample: Dictionary in samples:
		baseline_values.append(float(sample.baseline_batch_usec))
		candidate_values.append(float(sample.candidate_batch_usec))
	return {
		"baseline": _summary(baseline_values),
		"candidate": _summary(candidate_values),
		"raw_paired_batches": samples,
	}


func _summarize_build_timing(samples: Array[Dictionary]) -> Dictionary:
	var baseline_values: Array[float] = []
	var candidate_values: Array[float] = []
	for sample: Dictionary in samples:
		baseline_values.append(float(sample.baseline_build_usec))
		candidate_values.append(float(sample.candidate_build_usec))
	return {
		"baseline": _build_summary(baseline_values),
		"candidate": _build_summary(candidate_values),
		"raw_paired_builds": samples,
	}


func _build_summary(values: Array[float]) -> Dictionary:
	var summary: Dictionary = _summary(values)
	return {
		"mean_build_usec": summary.mean_batch_usec,
		"median_build_usec": summary.median_batch_usec,
		"raw_build_usec": summary.raw_batch_usec,
	}


func _summary(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in values:
		total += value
	var median: float = 0.0
	if not sorted.is_empty():
		var middle: int = sorted.size() / 2
		median = sorted[middle] if sorted.size() % 2 == 1 \
			else (sorted[middle - 1] + sorted[middle]) * 0.5
	return {
		"mean_batch_usec": total / maxf(float(values.size()), 1.0),
		"median_batch_usec": median,
		"raw_batch_usec": values,
	}


func _motion_snapshot(root: Node3D) -> Dictionary:
	var motion: Variant = root.get_meta("windsock_motion")
	return {
		"basket_yaw_rad": float(motion.basket_yaw_rad),
		"inflation": float(motion.inflation),
		"centerline_local": _points_value(motion.centerline_local),
		"simulated_time_s": float(motion.simulated_time_s),
	}


func _render_snapshot(root: Node3D) -> Dictionary:
	var fabric: MeshInstance3D = root.get_node("Fabric") as MeshInstance3D
	var basket: MeshInstance3D = root.get_node("Basket") as MeshInstance3D
	var material: ShaderMaterial = fabric.mesh.surface_get_material(0) as ShaderMaterial
	var root_bounds: AABB = root.get_meta("visual_bounds")
	var fabric_centres: PackedVector3Array = fabric.get_meta("centreline")
	var material_centres: PackedVector3Array = material.get_shader_parameter("centerline_points")
	return {
		"fabric_custom_aabb": _aabb_value(fabric.custom_aabb),
		"root_visual_bounds": _aabb_value(root_bounds),
		"fabric_centreline_meta": _points_value(fabric_centres),
		"basket_transform": _transform_value(basket.transform),
		"material_centerline_points": _points_value(material_centres),
		"material_basket_yaw_rad": float(material.get_shader_parameter("basket_yaw_rad")),
		"material_inflation": float(material.get_shader_parameter("inflation")),
	}


func _compare_snapshots(label: String, baseline: Dictionary, candidate: Dictionary, context: Dictionary) -> void:
	for field: Variant in baseline.keys():
		_compare_value(label + "." + str(field), baseline[field], candidate.get(field), context)


func _compare_value(
		label: String, baseline: Variant, candidate: Variant, context: Dictionary,
		force_mismatch: bool = false) -> void:
	if not force_mismatch and baseline == candidate:
		return
	_mismatch_count += 1
	if _mismatches.size() < DETAIL_LIMIT:
		var mismatch_context: Dictionary = context.duplicate(true)
		_mismatches.append({"context": mismatch_context, "field": label,
			"baseline": baseline, "candidate": candidate})


func _aabb_value(bounds: AABB) -> Array:
	return [_vector_value(bounds.position), _vector_value(bounds.size)]


func _transform_value(value: Transform3D) -> Dictionary:
	return {
		"basis_x": _vector_value(value.basis.x),
		"basis_y": _vector_value(value.basis.y),
		"basis_z": _vector_value(value.basis.z),
		"origin": _vector_value(value.origin),
	}


func _points_value(points: PackedVector3Array) -> Array:
	var result: Array = []
	for point: Vector3 in points:
		result.append(_vector_value(point))
	return result


func _vector_value(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _dimensions(cue: Dictionary) -> Dictionary:
	var throat: float = float(cue.throat_diameter)
	return {
		"length_m": float(cue.length),
		"height_m": float(cue.pole_height),
		"throat_diameter_m": throat,
		"tail_diameter_m": float(cue.tail_diameter),
		"arm_m": maxf(0.35, throat * 0.5 + 0.10),
	}


func _wind_for(time_s: float) -> Array:
	if time_s < 2.0:
		return [0.1 * sin(time_s), 0.15 * sin(time_s * 2.0), 0.05 * cos(time_s)]
	if time_s < 4.0:
		return [2.0 + 0.4 * sin(time_s * 2.0), 7.0 + sin(time_s * 3.0), -0.2]
	if time_s < 6.0:
		return [1.0, -7.0 + 0.5 * sin(time_s * 2.0), 1.5]
	if time_s < 8.0:
		return [-1.0, -8.0 - 0.5 * sin(time_s * 3.0), -0.5]
	return [1.0 + 0.2 * sin(time_s), 4.0 + 0.7 * sin(time_s * 2.0), -5.5]


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for argument: String in args:
		if argument.begins_with("--baseline="):
			result["baseline"] = argument.trim_prefix("--baseline=")
		elif argument.begins_with("--out="):
			result["out"] = argument.trim_prefix("--out=")
	return result
