extends SceneTree

const Model := preload("res://aircraft/hx700_articulated_model.gd")
const Mechanism := preload("res://render/rotor/hx700_mechanism.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var preview := Model.load_preview()
	_check("advanced HX-700 admitted", preview.ok)
	if not preview.ok:
		print(preview.errors)
		quit(1)
		return
	var rig := Mechanism.new()
	_check("mechanical adapter configures neutral", rig.configure(preview))
	if rig.pose.is_empty():
		print(rig.apply(PackedFloat64Array([0, 0, 0, 0, 0])))
		preview.root.free()
		quit(1)
		return
	var oracle_path := ProjectSettings.globalize_path("res://../research/helicopter/reference/hx700_motion_oracle.json")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--oracle="):
			oracle_path = arg.trim_prefix("--oracle=")
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(oracle_path))
	_check("oracle pins the same immutable Blender source", oracle.source_sha256 == Model.SOURCE_SHA256)
	var max_position := 0.0
	var max_basis := 0.0
	var max_residual := 0.0
	for sample: Dictionary in oracle.samples:
		var result := rig.apply(PackedFloat64Array(sample.inputs))
		_check("source pose %s closes" % str(sample.inputs), result.ok)
		if not result.ok:
			print(result)
			continue
		max_residual = maxf(max_residual, result.residual_m)
		var local: Dictionary = {}
		for id: String in rig.bindings:
			local[id] = rig.bindings[id].transform
		var world := rig._world_frames(local)
		for id: String in sample.frames:
			var expected: Transform3D = Model._parse_transform(sample.frames[id]).transform
			var observed: Transform3D = world[id]
			var position_error := observed.origin.distance_to(expected.origin)
			max_position = maxf(max_position, position_error)
			# Ball-link roll is deterministic parallel transport; only its endpoints
			# are constrained. Blender's Damped Track uses a different free twist.
			if not id.begins_with("linkage."):
				for column in 3:
					max_basis = maxf(max_basis, (observed.basis[column] - expected.basis[column]).length())
	_check("all 44 independent source poses match positions within 2 micrometres", max_position < 2e-6)
	_check("all driven frames match source orientation within 0.00002", max_basis < 2e-5)
	print("ORACLE max_position_m=", max_position, " max_basis=", max_basis, " max_rod_residual_m=", max_residual)

	var accepted: Dictionary = {}
	var sweep_ok := true
	var continuous := true
	var previous: Dictionary = {}
	for i in range(721):
		var phase := float(i) * TAU / 360.0
		var result := rig.apply(PackedFloat64Array([8 * sin(phase * 0.5), 8 * sin(phase), 8 * cos(phase), 15 * sin(phase), phase]))
		if not result.ok:
			print("SWEEP ", i, " ", result)
			sweep_ok = false
			break
		max_residual = maxf(max_residual, result.residual_m)
		if not previous.is_empty():
			for j in 4:
				continuous = continuous and absf(result.servos[j] - previous.servos[j]) < deg_to_rad(3)
		previous = result
	_check("dense combined sweep keeps all nine rods rigid and servos continuous", sweep_ok and continuous)
	for id: String in rig.bindings:
		accepted[id] = rig.bindings[id].transform
	for bad in [PackedFloat64Array([14, 0, 0, 0, 0]), PackedFloat64Array([0, 0, 0, INF, 0]), PackedFloat64Array([0, 0, 0]), PackedFloat64Array([NAN, 0, 0, 0, 0])]:
		_check("bad inputs reject atomically", not rig.apply(bad).ok and _same(rig, accepted))
	rig._linkages[0].length_m += 0.1
	_check("unreachable +100 mm rod cannot be hidden by source trigonometric clamps", not rig.apply(PackedFloat64Array([0, 0, 0, 0, 0])).ok and _same(rig, accepted))
	rig._linkages[0].length_m -= 0.1
	var second := Model.load_preview()
	var second_rig := Mechanism.new()
	_check("second independent instance initializes", second_rig.configure(second))
	var first_before: Transform3D = rig.bindings["swash.fixed"].transform
	second_rig.apply(PackedFloat64Array([-10, 0, 0, -15, 1]))
	_check("instances share no movable nodes", rig.bindings["swash.fixed"].transform == first_before)
	rig.apply(PackedFloat64Array([10, 0, 0, 15, 0]))
	var outer: Transform3D = rig.bindings["swash.fixed"].transform
	var slider: Transform3D = rig.bindings["tail.slider"].transform
	var swash_height: float = outer.origin.y
	rig.apply(PackedFloat64Array([10, 0, 0, 15, 1]))
	_check("outer swash and tail slider do not spin with shafts", rig.bindings["swash.fixed"].transform == outer and rig.bindings["tail.slider"].transform == slider)
	_check("fixed cases stay fixed; collective raises swash and pitches both blades", rig.bindings["visual.caja_cola"].transform.is_equal_approx(rig._rest["visual.caja_cola"]) and swash_height > rig._rest["swash.fixed"].origin.y and absf(rig.pose.blade_pitch[0] - deg_to_rad(10)) < 1e-4 and absf(rig.pose.blade_pitch[1] - deg_to_rad(10)) < 1e-4)
	var final_inputs: PackedFloat64Array = rig.pose.inputs
	var baseline: Transform3D = rig.bindings["main.blade.a"].transform
	for fps in [30, 60, 144]:
		for frame in fps:
			rig.apply(final_inputs)
		_check("repeated %d Hz reads do not accumulate servo or blade motion" % fps, baseline == rig.bindings["main.blade.a"].transform)
	preview.root.free()
	second.root.free()
	print("%d checks, %d failed; dense sweep max residual %.9f m" % [checks, failures, max_residual])
	quit(0 if failures == 0 else 1)


func _same(rig: RefCounted, before: Dictionary) -> bool:
	for id: String in before:
		if rig.bindings[id].transform != before[id]:
			return false
	return true


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok " if ok else "FAIL ") + label)
