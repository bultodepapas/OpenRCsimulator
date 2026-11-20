## Audit fixture: stock HX geometry and X-Cell context, prescribed rigid transport.
## Does not claim a flown trajectory or a material/energy calibration.
extends SceneTree

const Model := preload("res://aircraft/hx700_model.gd")
const Data := preload("res://physics/rotorcraft_data.gd")
const Wreck := preload("res://render/rotor/heli_wreck.gd")

var checks := 0
var failures := 0
var observations: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model: Dictionary = Model.build()
	var data: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
	_check("stock model and context load", not model.is_empty() and bool(data.get("ok", false)))
	if model.is_empty() or not bool(data.get("ok", false)):
		_finish()
		return
	root.add_child(model.root)
	var wreck: Variant = Wreck.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	_check("stock wreck prepares", wreck.configure(model, data.context))
	if not bool(wreck.get_stats().prepared):
		wreck.free()
		model.root.free()
		_finish()
		return
	var cases: Array[Dictionary] = [
		{name = "delayed_unchanged_control", translation = Vector3.ZERO, rotation = Basis.IDENTITY, spin = true},
		{name = "delayed_translation", translation = Vector3(1.0, 0.3, 0.8), rotation = Basis.IDENTITY, spin = true},
		{name = "delayed_rotation", translation = Vector3.ZERO, rotation = Basis(Vector3(1.0, 0.0, 1.0).normalized(), 0.7), spin = true},
		{name = "zero_spin_transport_control", translation = Vector3(1.0, 0.3, 0.8), rotation = Basis(Vector3(1.0, 0.0, 1.0).normalized(), 0.7), spin = false},
	]
	for item: Dictionary in cases:
		_case(wreck, model, item)
	wreck.free()
	model.root.free()
	_finish()

func _case(wreck: Variant, model: Dictionary, item: Dictionary) -> void:
	wreck.reset()
	var pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 10.0, 0.0))
	var spin: bool = item.spin
	var report := {
		component = "fuselage", surface = "grass", normal_speed_mps = 0.0,
		tangent_speed_mps = 0.0, normal_energy_j = 0.0, effective_mass_kg = 1.0,
		point_world = pose.origin, ground_point_world = Vector3(0.0, -100.0, 0.0),
		normal_world = Vector3.UP, ground_normal_world = Vector3.UP,
		velocity_world = Vector3.ZERO, point_velocity_world = Vector3.ZERO,
		body_angular_velocity = Vector3.ZERO,
		main_omega_rad_s = 10.0 if spin else 0.0,
		tail_omega_rad_s = 40.0 if spin else 0.0,
		severity = {valid = true, class = 4, severity = 0.5, component = "fuselage", component_group = "fuselage", surface = "grass", normal_energy_j = 0.0},
	}
	var started: Dictionary = wreck.start_impact(report, pose, model.cg_model_m)
	_check(str(item.name) + " starts C4", bool(started.get("ok", false)) and int(wreck.severity.get("class", -1)) == 4)
	if not bool(started.get("ok", false)):
		return
	var rotations: Basis = item.rotation
	var shift: Vector3 = item.translation
	var transport := Transform3D(rotations, pose.origin + shift - rotations * pose.origin)
	var samples: Array[Dictionary] = []
	var max_due := 0.0
	for i: int in range(1, wreck._groups.size()):
		var group: Dictionary = wreck._groups[i]
		var family: String = wreck._rotor_group_family(group)
		if family.is_empty():
			continue
		_check(str(item.name) + " rotor is delayed", bool(group.detached) and not bool(group.activated) and float(group.due_s) > 0.0)
		var hub: Vector3 = wreck._main_rotor_hub if family == "main" else wreck._tail_rotor_hub
		var axis: Vector3 = wreck._main_rotor_axis if family == "main" else wreck._tail_rotor_axis
		var omega: float = wreck._main_rotor_omega if family == "main" else wreck._tail_rotor_omega
		var center: Vector3 = wreck._current_pose_for_center(group.center)
		var reference_spin: Vector3 = omega * axis.cross(center - hub)
		var before_raw: Vector3 = wreck._rotor_release_velocity(group)
		_check(str(item.name) + " initial reference agrees", before_raw.distance_to(reference_spin) < 0.001)
		# The independent oracle is rigid-transport covariance: translation leaves
		# relative spin unchanged, rotation applies the same rotation to that vector.
		var expected_raw: Vector3 = rotations * reference_spin
		var count: int = wreck._rotor_blade_count(family)
		var released_count: int = wreck._released_blade_count(group, family)
		var budget: float = wreck._shaft_spin_energy_budget(family) * float(released_count) / float(count)
		var expected_capped: Vector3 = expected_raw.limit_length(120.0)
		expected_capped = expected_capped.limit_length(sqrt(maxf(2.0 * budget / float(group.mass), 0.0)))
		samples.append({index = i, family = family, due_s = group.due_s, initial_raw = reference_spin,
			expected_raw = expected_raw, expected_capped = expected_capped, mass = group.mass, budget = budget})
		max_due = maxf(max_due, float(group.due_s))
	_check(str(item.name) + " has four authored rotor blades", samples.size() == 4)
	# Move the still-attached core before the existing delayed scheduler fires.
	# No engine physics frame, scatter impulse or ground rebound occurs here.
	wreck._core_body.global_transform = transport * wreck._core_body.global_transform
	wreck._core_body.linear_velocity = Vector3.ZERO
	wreck._core_body.angular_velocity = Vector3.ZERO
	for sample: Dictionary in samples:
		var group: Dictionary = wreck._groups[int(sample.index)]
		var actual_raw: Vector3 = wreck._rotor_release_velocity(group)
		sample.actual_raw = actual_raw
		_check(str(item.name) + " spin transports with " + str(sample.family), actual_raw.distance_to(sample.expected_raw) < 0.001)
	wreck._process(max_due + 0.001)
	var body_samples: Array[Dictionary] = []
	for sample: Dictionary in samples:
		var body: RigidBody3D = wreck._bodies[int(sample.index)]
		var expected: Vector3 = sample.expected_capped
		_check(str(item.name) + " scheduler activates " + str(sample.family), body.visible and bool(wreck._groups[int(sample.index)].activated))
		_check(str(item.name) + " released velocity follows frame " + str(sample.family), body.linear_velocity.distance_to(expected) < 0.001)
		body_samples.append({family = sample.family, index = sample.index, due_s = sample.due_s,
			initial_raw_mps = _v(sample.initial_raw), expected_raw_mps = _v(sample.expected_raw), actual_raw_mps = _v(sample.actual_raw),
			expected_release_mps = _v(expected), actual_release_mps = _v(body.linear_velocity),
			release_error_mps = body.linear_velocity.distance_to(expected), group_mass_kg = sample.mass, spin_budget_j = sample.budget})
	observations.append({case = item.name, translation_m = _v(shift), rotation_radians = 0.7 if rotations != Basis.IDENTITY else 0.0,
		elapsed_supplied_s = max_due + 0.001, shaft_speed_main_rad_s = report.main_omega_rad_s,
		shaft_speed_tail_rad_s = report.tail_omega_rad_s, scatter_j = wreck.get_stats().scatter_energy_j,
		bodies = body_samples})

func _v(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label)

func _finish() -> void:
	print("ROUND2_HELI_DELAYED_FRAMES_OBSERVATIONS " + JSON.stringify(observations))
	print("ROUND2_HELI_DELAYED_FRAMES_COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
