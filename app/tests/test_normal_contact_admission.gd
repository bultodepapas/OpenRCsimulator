## Reuse the existing normal-stage authoring/mass fixture for one integration gate.
## Synthetic local admission tests do not qualify an entire moving contact piece.
extends "res://tests/test_aircraft_ground_dynamics.gd"
const Admission := preload("res://physics/normal_contact_admission.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const Ring := preload("res://physics/wheel_geometry.gd")
const Liquid := preload("res://physics/liquid_fuel.gd")

func _initialize() -> void:
	_analytic()
	_coupled_and_units()
	_invalid()
	_plane_orientations()
	_plane_hessians()
	_practical_plane()
	_plane_invalid_and_sweep()
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

func _plane_row(hub: PackedFloat64Array, radius := 0.05, k := 100.0, c := 2.0, load_bound := 20.0, kappa := 0.1) -> Dictionary:
	return {hub_body = hub, radius_m = radius, kbar = k, cbar = c, normal_load_bound_n = load_bound, kappa_min = kappa}

func _add_intrinsic(tensor: PackedFloat64Array, a: PackedFloat64Array, j: float, k: float) -> void:
	var d := j - k
	for axis in 3: tensor[axis] += k + d * a[axis] * a[axis]
	tensor[3] += d * a[0] * a[1]
	tensor[4] += d * a[0] * a[2]
	tensor[5] += d * a[1] * a[2]

func _plane_orientations() -> void:
	var axial := PackedFloat64Array([0.03, 0.04, 0.05])
	var transverse := PackedFloat64Array([0.02, 0.03, 0.04])
	var reference := PackedFloat64Array()
	reference.append_array(M.v3(0.6, 0.8, 0.0))
	reference.append_array(M.scale(M.v3(1.0, 2.0, 3.0), 1.0 / sqrt(14.0)))
	reference.append_array(M.v3(-2.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0))
	var locked := PackedFloat64Array([1.0, 1.5, 2.0, 0.0, 0.0, 0.0])
	for i in 3: _add_intrinsic(locked, reference.slice(3 * i, 3 * i + 3), axial[i], transverse[i])
	var system := Rotor.prepare_system(locked, axial, transverse, reference,
		{partition_id = "plane-envelope", reference_pose_id = "nonaxisaligned", kind = "estimated", source = "Synthetic independent envelope oracle"})
	var zero9 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var n := M.scale(M.v3(0.2, -0.3, -1.0), 1.0 / sqrt(1.13))
	for trial in 9:
		var angle: float = 0.12 * trial
		var q := M.q_from_euler(0.2 + angle, -0.3 + 0.2 * angle, 0.15 - angle)
		var cg := M.v3(0.01 * trial, -0.005 * trial, 0.002 * trial)
		var axes := PackedFloat64Array()
		for i in 3:
			var rotation := M.q_from_axis_angle(M.v3(0.3, 0.2, 0.4), angle * (i + 1))
			axes.append_array(M.q_rotate(rotation, reference.slice(3 * i, 3 * i + 3)))
		var rotor := Rotor.evaluate_system(system, locked, M.v3(0.3, -0.2, 0.1), PackedFloat64Array([2.0, -3.0, 4.0]), axes,
			zero9, zero9, M.v3(0.0, 0.0, 0.0), zero9, PackedFloat64Array([0.0, 0.0, 0.0]))
		_check("nonaxisaligned live common matrix prepares", rotor.ok)
		if not rotor.ok: continue
		var rows: Array = []
		var contacts: Array = []
		for i in 3:
			var hub := M.v3(0.2 - 0.15 * i, 0.1 * i, 0.05)
			var axle := M.q_rotate(q, axes.slice(3 * i, 3 * i + 3))
			var geometry := Ring.plane(M.q_rotate(q, hub), axle, 0.05, M.v3(0.0, 0.0, 0.0), n)
			_check("independent exact plane normal branch exists", geometry.ok)
			if not geometry.ok: continue
			var normal_body := M.q_rotate(M.q_conj(q), n)
			var arm := M.add(hub, M.q_rotate(M.q_conj(q), geometry.hub_arm_ned))
			rows.append(_row(normal_body, arm, PackedFloat64Array([0.0, 0.0, 0.0])))
			var projection: float = sqrt(maxf(0.0, 1.0 - pow(M.dot(axle, n), 2)))
			contacts.append(_plane_row(hub, 0.05, 100.0 + i * 20.0, 2.0, 20.0, minf(0.5, 0.9 * projection)))
		if rows.size() != 3: continue
		var local := Admission.mobility(2.0, cg, rotor.stage, rows)
		var bound := Admission.plane_envelope(2.0, cg, rotor.stage, contacts, 0.001)
		_check("orientation-independent envelope admits qualified sample", local.ok and bound.ok, str(bound))
		if not local.ok or not bound.ok: continue
		var independent := _dense_w(2.0, local.jacobian, rotor.stage.matrix, 3, 9)
		_check("exact oriented normal W matches dense full mass inverse", _near(local.matrix, independent))
		var trace := 0.0
		for i in 3:
			_check("global bound dominates oriented free normal diagonal", bound.mobility_diagonal_bounds[i] >= independent[3 * i + i])
			trace += contacts[i].kbar * independent[3 * i + i]
		_check("material trace bound dominates exact coupled weighted trace", bound.material_eigenvalue_bound_per_s2 >= trace)
		_check("carrier lower bound does not exceed independently known eigenvalue", bound.carrier_lower_bound_kgm2 > 0.0 and bound.carrier_lower_bound_kgm2 <= 1.0)
		_check("plane result cannot claim a complete RHS or geometry certificate", not bound.full_rhs_certificate and not bound.whole_piece_certificate and bound.conditional_envelope)

func _ring_gap(q: PackedFloat64Array, hub: PackedFloat64Array, radius: float) -> float:
	var n := M.v3(0.0, 0.0, -1.0)
	var axle := M.q_rotate(q, M.v3(0.0, 0.0, 1.0))
	var z := M.dot(axle, n)
	return M.dot(n, M.q_rotate(q, hub)) - radius * sqrt(maxf(0.0, 1.0 - z * z))

func _plane_hessians() -> void:
	var rotor := _system()
	var hub := M.v3(0.2, -0.1, 0.3)
	for angle: float in [0.0002, 0.005, 0.05, 0.5, 1.2]:
		var kappa_min := 0.9 * sin(angle)
		var result := Admission.plane_envelope(2.0, M.v3(0.0, 0.0, 0.0), rotor.stage, [_plane_row(hub, 0.05, 0.0, 0.0, 1.0, kappa_min)], 1.0e-6)
		_check("protected near-boundary kappa is numerically supported", result.ok)
		if not result.ok: continue
		var q := M.q_from_axis_angle(M.v3(0.0, 1.0, 0.0), angle)
		var epsilon := minf(1.0e-4, sin(angle) * 0.005)
		for axis: PackedFloat64Array in [M.v3(1.0, 0.0, 0.0), M.v3(0.0, 1.0, 0.0), M.scale(M.v3(0.6, -0.7, 0.3), 1.0 / sqrt(0.94))]:
			var plus := M.q_mul(q, M.q_from_axis_angle(axis, epsilon))
			var minus := M.q_mul(q, M.q_from_axis_angle(axis, -epsilon))
			var second: float = (_ring_gap(plus, hub, 0.05) - 2.0 * _ring_gap(q, hub, 0.05) + _ring_gap(minus, hub, 0.05)) / (epsilon * epsilon)
			_check("analytic curvature bound dominates independent ring-gap second difference", absf(second) <= result.gap_hessian_bounds_m[0] * 1.001)

func _practical_plane() -> void:
	var loaded := Data.load_file("res://data/aircraft/p51d_mustang_120.json")
	_check("practical envelope uses installed closed-shaft resource", loaded.ok)
	if not loaded.ok: return
	var applied := Hardware.apply_to_model(loaded.model)
	var p: Dictionary = applied.model
	var fuel: Dictionary = p.propulsion.liquid_fuel
	var live := Liquid.properties(fuel, {str(fuel.tank_id): 0.5 * (fuel.capacity_kg + fuel.unusable_kg)})
	var axial := PackedFloat64Array([p.propulsion.rotor_inertia])
	var transverse := PackedFloat64Array([0.5 * p.propulsion.rotor_inertia])
	var axes: PackedFloat64Array = p.propulsion.axis.duplicate()
	for contact: Dictionary in p.landing_gear.contacts:
		axial.append(contact.wheel_inertia)
		transverse.append(0.5 * contact.wheel_inertia)
		axes.append_array(M.v3(0.0, -1.0, 0.0))
	var system := Rotor.prepare_system(p.inertia, axial, transverse, axes,
		{partition_id = "practical-plane", reference_pose_id = "test_hubs", kind = "estimated", source = "Explicit synthetic transverse reservation on installed P51"})
	var zero12 := PackedFloat64Array()
	zero12.resize(12)
	var rotor := Rotor.evaluate_system(system, live.inertia, M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), axes,
		zero12, zero12, M.v3(0.0, 0.0, 0.0), zero12, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	_check("live P51 body remainder prepares at partial fuel", live.ok and rotor.ok)
	if not rotor.ok: return
	for speed: float in [0.5, 1.0, 2.0]:
		var contacts: Array = []
		var locations := [M.v3(-0.2, -0.35, 0.0), M.v3(-0.2, 0.35, 0.0), M.v3(0.6, 0.0, 0.0)]
		for i in 3:
			var radius: float = p.landing_gear.contacts[i].wheel_radius
			locations[i][2] = 0.2 - radius
			# Same explicit fixture as the retained design probe: k1500,c20,
			# onset.002m, Xmax.02m; derivative envelope uses dc/dx<=20000.
			contacts.append(_plane_row(locations[i], radius, 1500.0 + 20000.0 * speed, 20.0, 30.0 + 20.0 * speed, 0.5))
		var result := Admission.plane_envelope(live.mass_kg, live.cg_body_m, rotor.stage, contacts, 1.0 / 240.0)
		var expected: int = 3 if speed == 0.5 else 4 if speed == 1.0 else 6
		_check("practical retained plane fixture preserves3/4/6 request", result.ok and result.substeps == expected, str(result))

func _plane_invalid_and_sweep() -> void:
	var stage: Dictionary = _system().stage
	var contact := _plane_row(M.v3(0.2, 0.1, 0.3))
	for kind: String in ["mass", "cg", "missing", "extra", "hub", "radius", "kappa", "kappa_high", "k", "c", "load", "nan", "stage", "overflow"]:
		var mass: Variant = 2.0
		var cg := M.v3(0.0, 0.0, 0.0)
		var rows := [contact.duplicate(true)]
		var s := stage.duplicate(true)
		match kind:
			"mass": mass = true
			"cg": cg[0] = 1.0e7
			"missing": rows[0].erase("kbar")
			"extra": rows[0].extra = 1
			"hub": rows[0].hub_body[0] = INF
			"radius": rows[0].radius_m = 0.0
			"kappa": rows[0].kappa_min = 0.00001
			"kappa_high": rows[0].kappa_min = 1.1
			"k": rows[0].kbar = -1.0
			"c": rows[0].cbar = -1.0
			"load": rows[0].normal_load_bound_n = -1.0
			"nan": rows[0].kbar = NAN
			"stage": s.carrier[0] *= 2.0
			"overflow": rows[0].kbar = 1.0e308
		var before := var_to_bytes([mass, cg, s, rows])
		var bad := Admission.plane_envelope(mass, cg, s, rows, 1.0 / 240.0)
		_check("unsupported/malformed plane envelope refuses: " + kind, not bad.ok and not bad.has("substeps") and before == var_to_bytes([mass, cg, s, rows]))
	var huge := contact.duplicate(true)
	huge.kbar = 1.0e12
	var budget := Admission.plane_envelope(2.0, M.v3(0.0, 0.0, 0.0), stage, [huge], 1.0 / 240.0)
	_check("plane budget rejection preserves declared coefficients", not budget.ok and budget.status == "budget_exceeded" and not budget.has("substeps") and huge.kbar == 1.0e12)
	var yes := Admission.swept_clearance(0.1, 1.0, 0.01)
	var no := Admission.swept_clearance(0.01, 1.0, 0.01)
	var maybe := Admission.swept_clearance(-0.01, 0.0, 0.01)
	_check("analytic swept separation includes strict positive roundoff margin", yes.ok and yes.proved_separated and yes.swept_gap_lower_bound_m <= 0.09)
	_check("swept boundary or initial penetration cannot manufacture separation", no.ok and not no.proved_separated and maybe.ok and not maybe.proved_separated)
	_check("swept proof exposes whole-interval speed assumption", yes.whole_interval_speed_bound_assumed and not yes.full_rhs_certificate)
	_check("negative/nonfinite swept bounds refuse", not Admission.swept_clearance(0.1, -1.0, 0.01).ok and not Admission.swept_clearance(0.1, 1.0, INF).ok)

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
