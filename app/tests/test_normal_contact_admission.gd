## Reuse the existing normal-stage authoring/mass fixture for one integration gate.
## Synthetic local admission tests do not qualify an entire moving contact piece.
extends "res://tests/test_aircraft_ground_dynamics.gd"
const Admission := preload("res://physics/normal_contact_admission.gd")
const GC := preload("res://physics/generalized_coordinates.gd")

func _initialize() -> void:
	_analytic()
	_coupled_and_units()
	_invalid()
	_fixture()
	if _failures == 0: _integration()
	print("Normal contact admission: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _system(hold := false) -> Dictionary:
	var locked := PackedFloat64Array([1.25, 1.25, 1.5, 0.0, 0.0, 0.0])
	var system := Rotor.prepare_system(locked, PackedFloat64Array([0.5]), PackedFloat64Array([0.25]),
		M.v3(0.0, 0.0, 1.0), {partition_id = "local-admission", reference_pose_id = "fixed", kind = "estimated", source = "Synthetic analytic mass fixture"})
	return Rotor.evaluate_system(system, locked, M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0]), M.v3(0.0, 0.0, 1.0),
		M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0]),
		[{rotor_index = 0, capacity_nm = 100.0}] if hold else [])

func _row(normal: PackedFloat64Array, arm: PackedFloat64Array, spin := PackedFloat64Array([0.0])) -> Dictionary:
	return {normal_body = normal, arm_datum_body = arm, spin_jacobian = spin}

func _analytic() -> void:
	var rotor := _system()
	_check("analytic rotor stage prepares", rotor.ok)
	var cg := M.v3(0.1, -0.2, 0.3)
	var rows := [_row(M.v3(0.0, 0.0, -1.0), cg)]
	var before := var_to_bytes([rotor.stage, cg, rows])
	var mobility := Admission.mobility(2.0, cg, rotor.stage, rows)
	_check("one normal through CG has exact translational inverse mass", mobility.ok and mobility.matrix == PackedFloat64Array([0.5]))
	_check("CM shift produces zero angular/local Jacobian", mobility.ok and _near(mobility.jacobian, PackedFloat64Array([0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0])))
	var admitted := Admission.admit(mobility.matrix, PackedFloat64Array([400.0]), PackedFloat64Array([12.0]), 0.01)
	_check("analytic one-DOF stiffness/damping eigenvalue bounds", admitted.ok and absf(admitted.stiffness_eigenvalue_bound_per_s2 - 200.0) < 1.0e-10 \
		and absf(admitted.damping_rate_bound_per_s - 6.0) < 1.0e-11)
	_check("analytic frequency target chooses two unsoftened steps", admitted.ok and admitted.substeps == 2 and admitted.h_frequency <= 0.1 and admitted.h_damping_rate <= 0.25)
	_check("scope explicitly refuses whole-piece certificate claim", admitted.ok and not admitted.whole_piece_certificate and admitted.scope == Admission.SCOPE)
	_check("mobility never mutates mass-stage/CG/rows", before == var_to_bytes([rotor.stage, cg, rows]))
	var free := Admission.mobility(2.0, M.v3(0.0, 0.0, 0.0), rotor.stage, [_row(M.v3(0.0, 1.0, 0.0), M.v3(1.0, 0.0, 0.0))])
	var held := Admission.mobility(2.0, M.v3(0.0, 0.0, 0.0), _system(true).stage, [_row(M.v3(0.0, 1.0, 0.0), M.v3(1.0, 0.0, 0.0))])
	_check("free rotor mobility uses Schur response, not locked inertia", free.ok and absf(free.matrix[0] - 1.5) < 1.0e-14 \
		and free.matrix[0] > 0.5 + 1.0 / 1.5)
	_check("existing static hold does not hide free-spin upper mobility", held.ok and held.matrix == free.matrix and held.all_relative_spins_free)
	var zero := Admission.admit(mobility.matrix, PackedFloat64Array([0.0]), PackedFloat64Array([0.0]), 0.01)
	_check("zero derivative bounds require exactly one step", zero.ok and zero.substeps == 1 and zero.angular_frequency_bound_radps == 0.0 and zero.damping_rate_bound_per_s == 0.0)

func _dense_w(mass: float, jacobian: PackedFloat64Array, angular: PackedFloat64Array, count: int, width: int) -> PackedFloat64Array:
	var inverse := GC.invert(angular, width - 3)
	var result := PackedFloat64Array()
	result.resize(count * count)
	for i in count:
		for j in count:
			for k in 3: result[i * count + j] += jacobian[i * width + k] * jacobian[j * width + k] / mass
			for k in range(3, width):
				for l in range(3, width): result[i * count + j] += jacobian[i * width + k] * inverse.inverse[(k - 3) * (width - 3) + l - 3] * jacobian[j * width + l]
	return result

func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance := 1.0e-12) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not is_finite(a[i]) or absf(a[i] - b[i]) > tolerance: return false
	return true

func _coupled_and_units() -> void:
	var rotor := _system()
	var rows := [_row(M.v3(0.0, 0.0, -1.0), M.v3(1.0, 0.0, 0.0), PackedFloat64Array([0.1])),
		_row(M.v3(0.0, 0.0, -1.0), M.v3(-0.5, 0.2, 0.0), PackedFloat64Array([-0.05]))]
	var mobility := Admission.mobility(2.0, M.v3(0.1, -0.05, 0.03), rotor.stage, rows)
	_check("asymmetric coupled normal mobility evaluates", mobility.ok)
	if not mobility.ok: return
	var independent := _dense_w(2.0, mobility.jacobian, rotor.stage.matrix, 2, 7)
	_check("full free 3+N W agrees with independent dense inverse", _near(mobility.matrix, independent))
	_check("distinct contact arms retain off-diagonal coupling", absf(mobility.matrix[1]) > 0.01 and mobility.matrix[1] == mobility.matrix[2])
	var repeated := Admission.mobility(2.0, M.v3(0.0, 0.0, 0.0), rotor.stage, [rows[0], rows[0]])
	_check("redundant identical contact rows remain valid singular PSD", repeated.ok and repeated.psd_rank == 1 and repeated.matrix[0] == repeated.matrix[1])
	var k := PackedFloat64Array([100.0, 900.0])
	var c := PackedFloat64Array([2.0, 6.0])
	var admitted := Admission.admit(repeated.matrix, k, c, 0.002)
	var exact_k: float = repeated.matrix[0] * (k[0] + k[1])
	var exact_c: float = repeated.matrix[0] * (c[0] + c[1])
	_check("singular contact spectrum is conservatively bounded without regularization", admitted.ok and admitted.stiffness_eigenvalue_bound_per_s2 >= exact_k and admitted.damping_rate_bound_per_s >= exact_c)
	var matrix_before := var_to_bytes([mobility.matrix, k, c])
	var baseline := Admission.admit(mobility.matrix, k, c, 0.002)
	for units: PackedFloat64Array in [PackedFloat64Array([1.0e4, 1.0e-4]), PackedFloat64Array([1.0e100, 1.0e-100])]:
		var unit_w: PackedFloat64Array = mobility.matrix.duplicate()
		var unit_k := k.duplicate()
		var unit_c := c.duplicate()
		for i in 2:
			unit_k[i] /= units[i] * units[i]
			unit_c[i] /= units[i] * units[i]
			for j in 2: unit_w[2 * i + j] *= units[i] * units[j]
		var changed := Admission.admit(unit_w, unit_k, unit_c, 0.002)
		_check("gap-coordinate units preserve rate bounds and count", changed.ok and baseline.ok and changed.substeps == baseline.substeps \
			and absf(changed.angular_frequency_bound_radps - baseline.angular_frequency_bound_radps) < 1.0e-10 \
			and absf(changed.damping_rate_bound_per_s - baseline.damping_rate_bound_per_s) < 1.0e-10, str(changed))
	_check("admission leaves all physical coefficients unmodified", matrix_before == var_to_bytes([mobility.matrix, k, c]))
	var rejected := Admission.admit(PackedFloat64Array([0.5]), PackedFloat64Array([1.0e8]), PackedFloat64Array([0.0]), 1.0 / 240.0)
	_check("budget overflow rejects instead of reducing stiffness", not rejected.ok and rejected.status == "budget_exceeded" and rejected.context.required_steps_lower_bound > 16.0 and not rejected.has("substeps"))

func _invalid() -> void:
	var stage: Dictionary = _system().stage
	var row := _row(M.v3(0.0, 0.0, -1.0), M.v3(0.0, 0.0, 0.0))
	_check("boolean mass is not silently converted to a physical quantity", not Admission.mobility(true, M.v3(0.0, 0.0, 0.0), stage, [row]).ok)
	for kind: String in ["mass", "cg", "empty", "normal", "arm", "spin", "extra", "stage_matrix"]:
		var mass := 2.0
		var cg := M.v3(0.0, 0.0, 0.0)
		var rows := [row.duplicate(true)]
		var copied := stage.duplicate(true)
		match kind:
			"mass": mass = 0.0
			"cg": cg[0] = NAN
			"empty": rows.clear()
			"normal": rows[0].normal_body[2] = -2.0
			"arm": rows[0].arm_datum_body.resize(2)
			"spin": rows[0].spin_jacobian.resize(2)
			"extra": rows[0].extra = 1
			"stage_matrix": copied.matrix[0] *= 2.0
		_check("invalid mass/row/stage rejects: " + kind, not Admission.mobility(mass, cg, copied, rows).ok)
	for kind: String in ["negative_k", "negative_c", "size", "nan", "asymmetry", "indefinite", "dt", "budget", "overflow", "underflow"]:
		var matrix := PackedFloat64Array([1.0, 0.0, 0.0, 1.0])
		var k := PackedFloat64Array([100.0, 100.0])
		var c := PackedFloat64Array([1.0, 1.0])
		var dt := 0.01
		var budget := 16
		match kind:
			"negative_k": k[0] = -1.0
			"negative_c": c[0] = -1.0
			"size": matrix.resize(3)
			"nan": matrix[0] = NAN
			"asymmetry": matrix[1] = 0.1
			"indefinite": matrix = PackedFloat64Array([1.0, 2.0, 2.0, 1.0])
			"dt": dt = 0.0
			"budget": budget = 17
			"overflow": matrix[0] = 1.0e308; k[0] = 1.0e308
			"underflow": matrix[0] = 1.0e-300; k[0] = 1.0e-300
		var before := var_to_bytes([matrix, k, c])
		var result := Admission.admit(matrix, k, c, dt, budget)
		_check("invalid/numerically unrepresentable admission rejects: " + kind, not result.ok and not result.has("substeps") and before == var_to_bytes([matrix, k, c]))

func _normal_rows(body: PackedFloat64Array, contact: Dictionary, stage: Dictionary) -> Dictionary:
	var q := M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
	var inverse := M.q_conj(q)
	var rows: Array = []
	var k := PackedFloat64Array()
	var c := PackedFloat64Array()
	for record: Dictionary in contact.contacts:
		if not record.geometry_evaluated: continue
		var n := M.q_rotate(inverse, record.normal_ned)
		var spin := PackedFloat64Array()
		spin.resize(stage.axial.size())
		var index: int = record.contact_index
		spin[index] = M.dot(stage.axes.slice(3 * index, 3 * index + 3), M.cross(record.rho_body_m, n))
		rows.append(_row(n, record.arm_datum_body_m, spin))
		var bounds := Normal.bounds(_prepared.supports[index].normal, 0.05, 2.0)
		k.append(bounds.position_derivative_bound_npm)
		c.append(bounds.rate_derivative_bound_nsm)
	return {rows = rows, k = k, c = c}

func _integration() -> void:
	var inv := _inventory()
	if not inv.system.ok: return
	var properties := {mass_kg = MASS, cg_body_m = M.v3(0.0, 0.0, 0.0), inertia = inv.locked, inverse = RB.inertia_inverse(inv.locked)}
	var original_hz := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	var vehicle := VM.new()
	vehicle.continuous_size = 5
	var observed_steps := [0]
	vehicle.stage = func(body, values, at):
		var contact := Dynamics.evaluate(_prepared, body, _flat, at, values.slice(0, 3), _motion)
		if not contact.ok: return {}
		var response := _mechanics(inv, body, values, contact)
		if not response.ok: return {}
		var rows := _normal_rows(body, contact, response.stage)
		var mobility := Admission.mobility(MASS, properties.cg_body_m, response.stage, rows.rows)
		if not mobility.ok: return {}
		var admitted := Admission.admit(mobility.matrix, rows.k, rows.c, 1.0 / 240.0)
		if not admitted.ok: return {}
		var derivative: PackedFloat64Array = response.spin_acceleration.duplicate()
		derivative.append(contact.dissipation_w)
		return {loads = contact.loads, derivative = derivative, rotor_momentum = M.v3(0.0, 0.0, 0.0),
			body_derivative = FixedDatum.derivative_with_angular_acceleration(body, properties, contact.loads.slice(0, 3), GRAVITY, response.angular_acceleration),
			stage_context = {local_admission = admitted}}
	vehicle.substeps_joint = func(_body, _values, _at, stage):
		var admitted: Dictionary = stage.stage_context.local_admission
		observed_steps[0] = maxi(observed_steps[0], admitted.substeps)
		return admitted.substeps
	var sim := Sim.new()
	sim.mass = MASS
	sim.inertia = inv.locked
	sim.gravity = GRAVITY
	sim.continuous = PackedFloat64Array([1.0, -2.0, 0.5, 20.0, 0.0])
	_check("actual normal stage admission model installs", sim.set_model(vehicle) and sim.reset(_body(-0.19)))
	var initial := _energy(inv, sim.state, sim.continuous)
	for tick in 24:
		sim.step()
		_check("actual normal stage admitted tick accepts", sim.tick == tick + 1 and sim.fault_reason.is_empty(), sim.fault_reason)
		if not sim.fault_reason.is_empty(): break
	var final := _energy(inv, sim.state, sim.continuous)
	_check("actual admission requests multiple substeps within fixed budget", observed_steps[0] > 1 and observed_steps[0] <= 16)
	_check("actual normal integration mechanical energy plus heat remains bounded", initial.ok and final.ok and absf(final.energy - initial.energy) < 1.0e-5)
	print("local normal admission integration: substeps=", observed_steps[0], " energy_heat_error_J=", absf(final.energy - initial.energy))
	sim.free()
	Engine.physics_ticks_per_second = original_hz
