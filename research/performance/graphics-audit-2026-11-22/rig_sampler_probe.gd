extends SceneTree

const Sampler = preload("res://sampler.gd")
const VARIANTS := ["baseline", "packed_helper", "shared_coordinates", "combined"]
const ROUNDS := 12
const BATCHES := 18
var _sets: Array = []
var _ids: Array[PackedInt32Array] = []
var _groups: Array = []
var _low := PackedInt32Array()
var _high := PackedInt32Array()
var _fraction := PackedFloat64Array()
var _bytes := PackedByteArray()
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://inputs.json"))
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://rig.json"))
	_bytes = FileAccess.get_file_as_bytes("res://rig.bin")
	_groups = spec.groups
	_low.resize(_groups.size())
	_high.resize(_groups.size())
	_fraction.resize(_groups.size())
	for name: String in spec.names:
		_ids.append(PackedInt32Array(spec.ids[name]))
	for _variant in VARIANTS:
		var samplers: Array = []
		for name: String in spec.names:
			samplers.append(Sampler._compile_track(rig.tracks[name]))
		_sets.append(samplers)
	var argument_probe := PackedFloat32Array([1.25, -0.0])
	var observed_argument_type := _array_argument_type(argument_probe)
	if observed_argument_type != TYPE_ARRAY:
		_failures += 1
	var baseline_hash := HashingContext.new()
	baseline_hash.start(HashingContext.HASH_SHA256)
	for sample_case: Dictionary in spec.cases:
		var inputs: Dictionary = sample_case.inputs
		_prepare(inputs)
		for index in _sets[0].size():
			var original: Variant = _one(0, index, inputs)
			var original_bytes := var_to_bytes(original)
			var values: PackedByteArray = _sets[0][index].values.to_byte_array()
			baseline_hash.update(original_bytes)
			baseline_hash.update(values)
			if typeof(original) != TYPE_TRANSFORM3D:
				_failures += 1
			for variant in range(1, VARIANTS.size()):
				var candidate: Variant = _one(variant, index, inputs)
				if var_to_bytes(candidate) != original_bytes or _sets[variant][index].values.to_byte_array() != values:
					_failures += 1
			_checks += 1
	var rows: Array[Dictionary] = []
	if _failures == 0:
		for workload: Dictionary in spec.workloads:
			for _warmup in 3:
				for variant in VARIANTS.size():
					_batch(variant, spec.cases, workload.cases, BATCHES)
			for round_index in ROUNDS:
				for order_index in VARIANTS.size():
					var variant := (round_index + order_index) % VARIANTS.size()
					var start := Time.get_ticks_usec()
					var checksum := _batch(variant, spec.cases, workload.cases, BATCHES)
					var elapsed := Time.get_ticks_usec() - start
					rows.append({"workload": workload.name, "round": round_index, "order": order_index,
						"variant": VARIANTS[variant], "batches": BATCHES, "duration_usec": elapsed, "checksum": checksum})
	var version := Engine.get_version_info()
	var report := {"schema": "openrc-audit-rig-sampler-v1", "complete": _failures == 0,
		"engine_version": "%d.%d.%s.%s.%s" % [version.major, version.minor, version.status, version.build, str(version.hash).left(9)],
		"engine_info": version, "failures": _failures,
		"packed_argument_type": typeof(argument_probe), "array_parameter_observed_type": observed_argument_type,
		"track_cases": _checks, "variant_comparisons": _checks * 3, "tracks": spec.names.size(),
		"cases": spec.cases.size(), "baseline_output_sha256": baseline_hash.finish().hex_encode(),
		"warmup_batches_per_variant_workload": 3 * BATCHES, "rows": rows}
	var output := FileAccess.open("res://rig-sampler-results.json", FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	if _failures == 0:
		print("RIG_SAMPLER_AUDIT_COMPLETE tracks=%d cases=%d comparisons=%d" % [spec.names.size(), spec.cases.size(), _checks * 3])
	quit(0 if _failures == 0 else 1)


func _array_argument_type(values: Array) -> int:
	return typeof(values)


func _prepare(inputs: Dictionary) -> void:
	for index in _groups.size():
		var group: Dictionary = _groups[index]
		var count := int(group.count)
		var grid := clampf((float(inputs.get(str(group.name), 0.0)) - float(group.low)) / float(group.step), 0.0, float(count - 1))
		var lower := int(floor(grid))
		_low[index] = lower
		_high[index] = mini(lower + 1, count - 1)
		_fraction[index] = grid - float(lower)


func _one(variant: int, index: int, inputs: Dictionary) -> Variant:
	var sampler: Sampler.TrackSampler = _sets[variant][index]
	match variant:
		0:
			return Sampler._sample_compiled_track(sampler, _bytes, inputs)
		1:
			return Sampler._sample_packed(sampler, _bytes, inputs)
		2:
			return Sampler._sample_shared(sampler, _bytes, _ids[index], _low, _high, _fraction)
		_:
			return Sampler._sample_combined(sampler, _bytes, _ids[index], _low, _high, _fraction)


func _batch(variant: int, cases: Array, case_indices: Array, count: int) -> float:
	var checksum := 0.0
	for batch_index in count:
		var inputs: Dictionary = cases[int(case_indices[batch_index % case_indices.size()])].inputs
		if variant >= 2:
			_prepare(inputs)
		for index in _sets[variant].size():
			var value: Transform3D = _one(variant, index, inputs)
			checksum += value.origin.x
	return checksum
