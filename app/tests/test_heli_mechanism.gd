extends SceneTree

const Model := preload("res://aircraft/hx700_articulated_model.gd")
const Mechanism := preload("res://render/rotor/hx700_mechanism.gd")
const ORACLE_SHA256 := "da7888a45377d4f1628d9cbe2495804c1d6e4da2a863dbd82edc819a14b3d6d7"
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
	root.add_child(preview.root)
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
	var oracle_admitted := FileAccess.file_exists(oracle_path) and FileAccess.get_sha256(oracle_path) == ORACLE_SHA256
	_check("independent oracle bytes match the reviewed snapshot", oracle_admitted)
	if not oracle_admitted:
		print("Missing or changed independent motion oracle: ", oracle_path)
		preview.root.free()
		print("%d checks, %d failed; oracle admission rejected" % [checks, failures])
		quit(1)
		return
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
		for id: String in sample.frames:
			var expected: Transform3D = Model._parse_transform(sample.frames[id]).transform
			var observed: Transform3D = (rig.bindings[id] as Node3D).global_transform
			var position_error := observed.origin.distance_to(expected.origin)
			max_position = maxf(max_position, position_error)
			# Include every terminal orientation: endpoint closure alone does not
			# detect sockets that incorrectly cancel their carrier's rotation.
			for column in 3:
				max_basis = maxf(max_basis, (observed.basis[column] - expected.basis[column]).length())
	_check("all 44 independent source poses match positions within 2 micrometres", max_position < 2e-6)
	_check("all driven frames and 18 ball-link terminals match source orientation within 0.00002", max_basis < 2e-5)
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
	var extreme_ok := true
	for collective: float in [-13, 0, 13]:
		for roll: float in [-10, 0, 10]:
			for pitch: float in [-10, 0, 10]:
				for tail: float in [-20, 0, 20]:
					for step in 12:
						extreme_ok = rig.apply(PackedFloat64Array([collective, roll, pitch, tail, step * TAU / 12])).ok and extreme_ok
	_check("full travel and combined cyclic ring limits close over 972 poses", extreme_ok)
	var random := RandomNumberGenerator.new()
	random.seed = 260116
	var long_phase_ok := true
	for i in 1000:
		var phase := random.randf_range(-1e6, 1e6)
		if i < 2:
			phase = -1e6 if i == 0 else 1e6
		var request := PackedFloat64Array([random.randf_range(-13, 13), random.randf_range(-10, 10), random.randf_range(-10, 10), random.randf_range(-20, 20), phase])
		long_phase_ok = rig.apply(request).ok and long_phase_ok
	_check("1000 mixed poses close throughout the full accumulated phase range", long_phase_ok)
	_check_configuration(rig, preview)
	for tail: float in [-15, 15]:
		rig.apply(PackedFloat64Array([0, 0, 0, tail, 0]))
		_check("tail collective retains its signed source pitch %.0f" % tail, absf(rig.pose.blade_pitch[2] - deg_to_rad(tail)) < 1e-4)
	var rods_match := true
	for link: Dictionary in rig._linkages:
		var a: Node3D = rig.bindings[link.endpoint_a]
		var b: Node3D = rig.bindings[link.endpoint_b]
		var direction: Vector3 = (b.global_position - a.global_position).normalized()
		rods_match = rods_match and absf(a.global_position.distance_to(b.global_position) - link.length_m) < 2e-6
		# Rod meshes retain their neutral scale, inherit the moving terminal,
		# and extend along its authored local +Y. Neither shaft nor tube stretches.
		var bar: Node3D = rig.bindings["visual." + String(link.id).trim_prefix("linkage.") + "_varilla"]
		rods_match = rods_match and (bar.transform as Transform3D).is_equal_approx(rig._rest["visual." + String(link.id).trim_prefix("linkage.") + "_varilla"])
		rods_match = rods_match and absf(a.global_basis.y.normalized().dot(direction)) > 0.9999
	_check("rendered rods follow both terminal positions without stretching meshes", rods_match)
	_check_rotating_terminals(rig)
	for id: String in rig.bindings:
		accepted[id] = rig.bindings[id].transform
	for bad in [PackedFloat64Array([14, 0, 0, 0, 0]), PackedFloat64Array([0, 0, 0, INF, 0]), PackedFloat64Array([0, 0, 0]), PackedFloat64Array([NAN, 0, 0, 0, 0])]:
		_check("bad inputs reject atomically", not rig.apply(bad).ok and _same(rig, accepted))
	rig._linkages[0].length_m += 0.1
	_check("unreachable +100 mm rod cannot be hidden by source trigonometric clamps", not rig.apply(PackedFloat64Array([0, 0, 0, 0, 0])).ok and _same(rig, accepted))
	rig._linkages[0].length_m -= 0.1
	var second := Model.load_preview()
	root.add_child(second.root)
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


func _check_configuration(rig: RefCounted, preview: Dictionary) -> void:
	rig.apply(PackedFloat64Array([0, 0, 0, 0, 0]))
	var neutral: Dictionary = {}
	for id: String in rig.bindings:
		neutral[id] = rig.bindings[id].transform
	rig.apply(PackedFloat64Array([9, -6, 4, 15, 7.3]))
	var articulated: Dictionary = {}
	for id: String in rig.bindings:
		articulated[id] = rig.bindings[id].transform
	var accepted_pose: Dictionary = rig.pose.duplicate(true)
	_check("failed admission preserves the previous configuration", not rig.configure({"ok": false}) and _same(rig, articulated) and rig.pose == accepted_pose)
	var broken := preview.duplicate()
	broken.bindings = preview.bindings.duplicate()
	broken.bindings.erase("main.shaft")
	broken.bindings["unknown"] = preview.root
	_check("missing driven binding rejects without disabling the accepted rig", not rig.configure(broken) and _same(rig, articulated) and rig.pose == accepted_pose)
	broken.bindings = preview.bindings.duplicate()
	broken.bindings["visual.carenado"] = 7
	_check("invalid static binding rejects before dereferencing it", not rig.configure(broken) and _same(rig, articulated) and rig.pose == accepted_pose)
	_check("reconfiguring an articulated rig restores authored neutral frames", rig.configure(preview) and _same(rig, neutral))
	var exported_bindings: Dictionary = preview.bindings
	var exported_node: Node3D = exported_bindings["main.shaft"]
	exported_bindings.erase("main.shaft")
	_check("configured binding map is independent of its caller", rig.bindings.has("main.shaft") and rig.apply(PackedFloat64Array([3, 2, -1, 5, 0.2])).ok)
	exported_bindings["main.shaft"] = exported_node


func _check_rotating_terminals(rig: RefCounted) -> void:
	rig.apply(PackedFloat64Array([0, 0, 0, 0, 0]))
	var neutral: Dictionary = {}
	var rod_references: Dictionary = {}
	for link: Dictionary in rig._linkages:
		for endpoint: String in [link.endpoint_a, link.endpoint_b]:
			neutral[endpoint] = (rig.bindings[endpoint] as Node3D).global_basis
		var a: Node3D = rig.bindings[link.endpoint_a]
		var b: Node3D = rig.bindings[link.endpoint_b]
		var bar: MeshInstance3D = rig.bindings["visual." + String(link.id).trim_prefix("linkage.") + "_varilla"]
		var bounds := bar.mesh.get_aabb()
		var longest := bounds.size.max_axis_index()
		var direction := (b.global_position - a.global_position).normalized()
		var tips := PackedVector3Array()
		var offsets := PackedFloat64Array()
		for end in [bounds.position[longest], bounds.end[longest]]:
			var point := bounds.get_center()
			point[longest] = end
			tips.append(point)
			offsets.append((bar.global_transform * point - a.global_position).dot(direction))
		rod_references[link.id] = {"node": bar, "tips": tips, "offsets": offsets}
	rig.apply(PackedFloat64Array([0, 0, 0, 0, PI]))
	var head_follows := true
	var fixed_stays := true
	for id: String in neutral:
		var observed: Basis = rig.bindings[id].global_basis
		if id.begins_with("linkage.bieleta_cabeza"):
			var expected: Basis = Basis(Vector3.UP, PI) * neutral[id]
			head_follows = head_follows and _basis_error(observed, expected) < 2e-5
		elif id.begins_with("linkage.varilla_servo"):
			fixed_stays = fixed_stays and _basis_error(observed, neutral[id]) < 2e-5
	_check("all four head sockets follow a half-turn of the rotor", head_follows)
	_check("the six fixed servo-link sockets do not inherit rotor spin", fixed_stays)
	var previous_frames: Dictionary = {}
	var reference_pose: Dictionary = {}
	var maximum_step := 0.0
	var maximum_mesh_error := 0.0
	var full_turn_ok := true
	for i in 1441:
		var phase := float(i) * TAU / 720.0
		var result: Dictionary = rig.apply(PackedFloat64Array([6, 7, -4, 15, phase]))
		full_turn_ok = full_turn_ok and result.ok
		for link: Dictionary in rig._linkages:
			var a: Node3D = rig.bindings[link.endpoint_a]
			var b: Node3D = rig.bindings[link.endpoint_b]
			var direction := (b.global_position - a.global_position).normalized()
			# Check the actual rendered mesh's long axis and both centreline ends.
			# Imported rod mesh axes differ from the terminal's authored +Y axis.
			var rod: Dictionary = rod_references[link.id]
			for tip_index in 2:
				var offset: Vector3 = (rod.node as Node3D).global_transform * rod.tips[tip_index] - a.global_position
				maximum_mesh_error = maxf(maximum_mesh_error, offset.cross(direction).length())
				maximum_mesh_error = maxf(maximum_mesh_error, absf(offset.dot(direction) - rod.offsets[tip_index]))
			for endpoint: String in [link.endpoint_a, link.endpoint_b]:
				var node: Node3D = rig.bindings[endpoint]
				var rotation := node.global_basis.orthonormalized().get_rotation_quaternion()
				full_turn_ok = full_turn_ok and absf(node.global_basis.y.normalized().dot(direction)) > 0.9999
				if previous_frames.has(endpoint):
					maximum_step = maxf(maximum_step, rotation.angle_to(previous_frames[endpoint]))
				previous_frames[endpoint] = rotation
				if i == 360:
					reference_pose[endpoint] = node.global_transform
	_check("all 18 sockets stay aligned without flips through two full rotor turns", full_turn_ok and maximum_step < deg_to_rad(4))
	_check("rendered rod centreline ends preserve their authored ball clearances throughout rotation", maximum_mesh_error < 2e-6)
	print("TERMINALS maximum_step_deg=", rad_to_deg(maximum_step), " main_step_deg=0.5 poses=1441")
	print("RENDERED_RODS maximum_axis_or_end_offset_error_m=", maximum_mesh_error)
	rig.apply(PackedFloat64Array([6, 7, -4, 15, PI]))
	var path_independent := true
	for endpoint: String in reference_pose:
		path_independent = path_independent and (rig.bindings[endpoint] as Node3D).global_transform.is_equal_approx(reference_pose[endpoint])
	_check("revisiting an azimuth restores identical socket frames without accumulated twist", path_independent)


func _basis_error(a: Basis, b: Basis) -> float:
	var error := 0.0
	for axis in 3:
		error = maxf(error, a[axis].distance_to(b[axis]))
	return error


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok " if ok else "FAIL ") + label)
