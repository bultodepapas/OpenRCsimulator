# GP-09c: simultaneous wheel/shaft system, static holds and impulse work.
extends SceneTree

const RC := preload("res://physics/rotor_coupling.gd")
const WC := preload("res://physics/wheel_coupling.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const BODY := [1.2, 1.5, 1.8, 0.02, -0.03, 0.04]
const J := [0.03, 0.04, 0.01, 0.06] # three wheels and a dynamic shaft
const K := [0.02, 0.025, 0.007, 0.04]
const AXES := [0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.6, -0.8, 0.0, 1.0, 0.0, 0.0]
const NU := [0.1, 0.0, 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.0, 0.0, 0.0]
const NUDOT := [0.0, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.1, 0.0, 0.0, 0.0]

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_network_holds()
	_instantaneous_work()
	_projections()
	_reference_and_adapter()
	_validation_identity()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _partition() -> Dictionary:
	return {partition_id = "synthetic-wheel-shaft-budget", reference_pose_id = "fixed-centers-neutral",
		kind = "estimated", source = "GP-09c analytical fixture; no physical owner split or measured inventory claim"}


func _locked() -> PackedFloat64Array:
	var out := PackedFloat64Array(BODY)
	for i in J.size():
		var a := PackedFloat64Array(AXES).slice(3 * i, 3 * i + 3)
		var d: float = J[i] - K[i]
		out[0] += K[i] + d * a[0] * a[0]
		out[1] += K[i] + d * a[1] * a[1]
		out[2] += K[i] + d * a[2] * a[2]
		out[3] += d * a[0] * a[1]
		out[4] += d * a[0] * a[2]
		out[5] += d * a[1] * a[2]
	return out


func _prepared() -> Dictionary:
	return RC.prepare_system(_locked(), PackedFloat64Array(J), PackedFloat64Array(K), PackedFloat64Array(AXES), _partition())


func _evaluate(spin: PackedFloat64Array, holds: Array = [], internal_override := PackedFloat64Array()) -> Dictionary:
	return RC.evaluate_system(_prepared(), _locked(), M.v3(0.4, -0.3, 0.2), spin, PackedFloat64Array(AXES),
		PackedFloat64Array(NU), PackedFloat64Array(NUDOT), M.v3(0.3, -0.2, 0.1),
		PackedFloat64Array([0.02, -0.01, 0.03, -0.03, 0.04, 0.01, 0.01, 0.0, -0.02, -0.1, 0.02, 0.0]),
		PackedFloat64Array([-0.02, 0.03, -0.01, 0.2]) if internal_override.is_empty() else internal_override, holds)


# Independent Gram assembly: each component contributes Jacobian^T*C*Jacobian.
# Rotational base columns are unit vectors; its own spin column is its axle.
func _independent_matrix() -> PackedFloat64Array:
	var n := 7
	var out := PackedFloat64Array()
	out.resize(n * n)
	var body := PackedFloat64Array([BODY[0], BODY[3], BODY[4], BODY[3], BODY[1], BODY[5], BODY[4], BODY[5], BODY[2]])
	for row in 3:
		for col in 3:
			out[row * n + col] = body[3 * row + col]
	for rotor in 4:
		var a := PackedFloat64Array(AXES).slice(3 * rotor, 3 * rotor + 3)
		for row in n:
			var left := M.v3(0.0, 0.0, 0.0)
			if row < 3:
				left[row] = 1.0
			elif row == 3 + rotor:
				left = a
			for col in n:
				var right := M.v3(0.0, 0.0, 0.0)
				if col < 3:
					right[col] = 1.0
				elif col == 3 + rotor:
					right = a
				out[row * n + col] += K[rotor] * M.dot(left, right) + (J[rotor] - K[rotor]) * M.dot(left, a) * M.dot(right, a)
	return out


# Dense indefinite KKT inverse is independent of the production structured SPD
# solve and held-coordinate elimination. Signs: M*a - A^T*lambda = rhs; A*a=0.
func _dense_kkt(matrix: PackedFloat64Array, rhs: PackedFloat64Array, indices: Array, target: PackedFloat64Array) -> PackedFloat64Array:
	var n := rhs.size()
	var total := n + indices.size()
	var kkt := PackedFloat64Array()
	kkt.resize(total * total)
	for row in n:
		for col in n:
			kkt[row * total + col] = matrix[row * n + col]
	for i in indices.size():
		kkt[(3 + indices[i]) * total + n + i] = -1.0
		kkt[(n + i) * total + 3 + indices[i]] = 1.0
	var full_rhs := rhs.duplicate()
	full_rhs.append_array(target)
	var inverse := GC.invert(kkt, total)
	if not inverse.ok:
		return PackedFloat64Array()
	return GC.matrix_vector(inverse.inverse, full_rhs, total)


func _network_holds() -> void:
	var spin := PackedFloat64Array([4.0, -3.0, 2.0, 0.0])
	var high := _evaluate(spin, [{rotor_index = 3, capacity_nm = 1000.0}])
	_check("three wheels plus dynamic shaft solve simultaneously", high.ok)
	var matrix := _independent_matrix()
	_check("stage mass matches independent component Gram matrix", _near(high.stage.matrix, matrix, 1e-14))
	var dense := _dense_kkt(matrix, high.stage.generalized_rhs, [3], PackedFloat64Array([0.0]))
	var acceleration: PackedFloat64Array = high.angular_acceleration.duplicate()
	acceleration.append_array(high.spin_acceleration)
	_check("held shaft coupled solve agrees with dense KKT", _near(acceleration, dense.slice(0, 7), 1e-12))
	_check("required static shaft torque agrees with dense multiplier", absf(high.hold_torques[3] - dense[7]) < 1e-12)
	_check("held derivative is exactly zero for every RK stage", high.spin_acceleration[3] == 0.0)
	_check("hold torque does no relative work at zero spin", absf(high.power_residual) < 1e-12)
	var demand: float = absf(high.hold_torques[3])
	_check("fixture has nonzero static hold demand", demand > 1e-3)
	var at_capacity := _evaluate(spin, [{rotor_index = 3, capacity_nm = demand}])
	_check("capacity boundary is admitted", at_capacity.ok)
	var low := _evaluate(spin, [{rotor_index = 3, capacity_nm = demand * 0.5}])
	_check("infeasible static capacity is explicit, not clipped", not low.ok and low.status == "hold_capacity_exceeded" \
		and low.failed_rotor_indices == PackedInt64Array([3]) and absf(low.required_hold_torques[3] - high.hold_torques[3]) < 1e-14)
	var released := _evaluate(spin)
	_check("released shaft participates instead of a post-solve clamp", released.ok and absf(released.spin_acceleration[3]) > 1e-3 \
		and not _near(released.angular_acceleration, high.angular_acceleration, 1e-6))
	var changed := _evaluate(spin, [{rotor_index = 3, capacity_nm = 1000.0}], PackedFloat64Array([0.4, 0.03, -0.01, 0.2]))
	_check("other wheel torque changes shaft hold demand", changed.ok and absf(changed.hold_torques[3] - high.hold_torques[3]) > 1e-5)
	spin[0] = 0.0
	var two := _evaluate(spin, [{rotor_index = 3, capacity_nm = 1000.0}, {rotor_index = 0, capacity_nm = 1000.0}])
	var two_dense := _dense_kkt(matrix, two.stage.generalized_rhs, [3, 0], PackedFloat64Array([0.0, 0.0]))
	var two_acceleration: PackedFloat64Array = two.angular_acceleration.duplicate()
	two_acceleration.append_array(two.spin_acceleration)
	_check("two holds agree with independent dense KKT", two.ok and _near(two_acceleration, two_dense.slice(0, 7), 1e-12))
	_check("two hold multipliers match in requested order", absf(two.hold_torques[3] - two_dense[7]) < 1e-12 and absf(two.hold_torques[0] - two_dense[8]) < 1e-12)
	var reordered := _evaluate(spin, [{rotor_index = 0, capacity_nm = 1000.0}, {rotor_index = 3, capacity_nm = 1000.0}])
	_check("hold order cannot change physical derivatives", var_to_bytes(reordered.angular_acceleration) == var_to_bytes(two.angular_acceleration) \
		and var_to_bytes(reordered.spin_acceleration) == var_to_bytes(two.spin_acceleration))
	print("GP-09c required_shaft_hold_Nm=", high.hold_torques[3], " with_changed_wheel_torque_Nm=", changed.hold_torques[3])


func _energy(velocity: PackedFloat64Array, rates: PackedFloat64Array, axes := PackedFloat64Array(AXES)) -> float:
	var w := velocity.slice(0, 3)
	var result := 0.5 * M.dot(w, RB.inertia_mul(PackedFloat64Array(BODY), w))
	for i in 4:
		var a := axes.slice(3 * i, 3 * i + 3)
		var absolute := M.add(M.add(w, rates.slice(3 * i, 3 * i + 3)), M.scale(a, velocity[3 + i]))
		result += 0.5 * (K[i] * M.dot(absolute, absolute) + (J[i] - K[i]) * pow(M.dot(a, absolute), 2))
	return result


func _momentum(velocity: PackedFloat64Array, rates: PackedFloat64Array, axes: PackedFloat64Array) -> PackedFloat64Array:
	var result := RB.inertia_mul(PackedFloat64Array(BODY), velocity.slice(0, 3))
	for i in 4:
		var a := axes.slice(3 * i, 3 * i + 3)
		var absolute := M.add(M.add(velocity.slice(0, 3), rates.slice(3 * i, 3 * i + 3)), M.scale(a, velocity[3 + i]))
		result = M.add(result, M.add(M.scale(absolute, K[i]), M.scale(a, (J[i] - K[i]) * M.dot(a, absolute))))
	return result


func _rotate(value: PackedFloat64Array, rotation: PackedFloat64Array) -> PackedFloat64Array:
	var angle := M.norm(rotation)
	if angle == 0.0:
		return value.duplicate()
	return M.q_rotate(M.q_from_axis_angle(rotation, angle), value)


func _instantaneous_work() -> void:
	var out := _evaluate(PackedFloat64Array([4.0, -3.0, 2.0, 0.0]), [{rotor_index = 3, capacity_nm = 1000.0}])
	var velocity: PackedFloat64Array = out.stage.velocity
	var acceleration: PackedFloat64Array = out.angular_acceleration.duplicate()
	acceleration.append_array(out.spin_acceleration)
	var eps := 1e-5
	var plus := velocity.duplicate()
	var minus := velocity.duplicate()
	for i in 7:
		plus[i] += eps * acceleration[i]
		minus[i] -= eps * acceleration[i]
	var axes_plus := PackedFloat64Array()
	var axes_minus := PackedFloat64Array()
	var rates_plus := PackedFloat64Array(NU)
	var rates_minus := PackedFloat64Array(NU)
	for i in 4:
		var nu := PackedFloat64Array(NU).slice(3 * i, 3 * i + 3)
		var nu_dot := PackedFloat64Array(NUDOT).slice(3 * i, 3 * i + 3)
		var a := PackedFloat64Array(AXES).slice(3 * i, 3 * i + 3)
		axes_plus.append_array(_rotate(a, M.add(M.scale(nu, eps), M.scale(nu_dot, 0.5 * eps * eps))))
		axes_minus.append_array(_rotate(a, M.add(M.scale(nu, -eps), M.scale(nu_dot, 0.5 * eps * eps))))
	for i in 12:
		rates_plus[i] += eps * NUDOT[i]
		rates_minus[i] -= eps * NUDOT[i]
	var fd_energy := (_energy(plus, rates_plus, axes_plus) - _energy(minus, rates_minus, axes_minus)) / (2.0 * eps)
	var physical_power: float = out.external_power + out.internal_spin_power + out.actuator_power
	var rotation_plus := M.add(M.scale(velocity.slice(0, 3), eps), M.scale(acceleration.slice(0, 3), 0.5 * eps * eps))
	var rotation_minus := M.add(M.scale(velocity.slice(0, 3), -eps), M.scale(acceleration.slice(0, 3), 0.5 * eps * eps))
	var h_plus := _rotate(_momentum(plus, rates_plus, axes_plus), rotation_plus)
	var h_minus := _rotate(_momentum(minus, rates_minus, axes_minus), rotation_minus)
	var fd_momentum := M.scale(M.sub(h_plus, h_minus), 0.5 / eps)
	var energy_error := absf(fd_energy - physical_power)
	var momentum_error := M.norm(M.sub(fd_momentum, M.v3(0.3, -0.2, 0.1)))
	_check("four-rotor held-system independent component energy derivative", energy_error < 1e-8, str(energy_error))
	_check("four-rotor held-system independent inertial momentum derivative", momentum_error < 1e-8, str(momentum_error))
	print("GP-09c independent FD energy_error_W=", energy_error, " inertial_momentum_error_Nm=", momentum_error)


func _projections() -> void:
	var out := _evaluate(PackedFloat64Array([4.0, -3.0, 2.0, 5.0]))
	var stage: Dictionary = out.stage
	var before := var_to_bytes(stage)
	var projection := RC.project_relative_speeds(stage, [3, 0])
	_check("simultaneous relative stop projection succeeds", projection.ok)
	var target := PackedFloat64Array([-stage.velocity[6], -stage.velocity[3]])
	var dense := _dense_kkt(_independent_matrix(), PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), [3, 0], target)
	var delta: PackedFloat64Array = projection.angular_delta.duplicate()
	delta.append_array(projection.spin_delta)
	_check("projection increments agree with dense KKT", _near(delta, dense.slice(0, 7), 1e-12))
	_check("projection impulses agree with dense KKT", _near(projection.constraint_impulses, dense.slice(7), 1e-12))
	_check("requested spins stop exactly", projection.velocity[6] == 0.0 and projection.velocity[3] == 0.0)
	_check("free wheel spin also changes in the same projection", absf(projection.spin_delta[1]) > 1e-4)
	var impulse := GC.matrix_vector(_independent_matrix(), delta, 7)
	_check("total body angular momentum is preserved", M.norm(impulse.slice(0, 3)) < 1e-12)
	_check("unconstrained cyclic spin momenta are preserved", absf(impulse[4]) < 1e-12 and absf(impulse[5]) < 1e-12)
	var physical_work := 0.0
	for i in 4:
		var a := PackedFloat64Array(AXES).slice(3 * i, 3 * i + 3)
		var delta_absolute := M.add(delta.slice(0, 3), M.scale(a, delta[3 + i]))
		var delta_h := M.add(M.scale(delta_absolute, K[i]), M.scale(a, (J[i] - K[i]) * M.dot(a, delta_absolute)))
		physical_work += M.dot(PackedFloat64Array(NU).slice(3 * i, 3 * i + 3), delta_h)
	var energy_change := _energy(projection.velocity, PackedFloat64Array(NU)) - _energy(stage.velocity, PackedFloat64Array(NU))
	_check("projection actuator impulse work matches component momentum change", absf(physical_work - projection.actuator_impulse_work) < 1e-12)
	_check("independent physical energy/work/dissipation receipt closes", absf(energy_change - physical_work + projection.dissipated_energy) < 1e-12 \
		and projection.dissipated_energy >= 0.0 and absf(projection.energy_balance_residual) < 1e-12)
	_check("projection never mutates its input stage", before == var_to_bytes(stage))
	var none := RC.project_relative_speeds(stage, [])
	_check("empty projection is exactly an identity", none.ok and var_to_bytes(none.velocity) == var_to_bytes(stage.velocity) and none.dissipated_energy == 0.0)
	for carrier_twist in [-2.0, 2.0]:
		var locked := PackedFloat64Array([1.06, 1.06, 1.1, 0.0, 0.0, 0.0])
		var prepared := RC.prepare_system(locked, PackedFloat64Array([0.1]), PackedFloat64Array([0.06]), M.v3(0.0, 0.0, 1.0), _partition())
		var zero := M.v3(0.0, 0.0, 0.0)
		var coaxial := RC.evaluate_system(prepared, locked, zero, PackedFloat64Array([3.0]), M.v3(0.0, 0.0, 1.0),
			M.v3(0.0, 0.0, carrier_twist), zero, zero, zero, PackedFloat64Array([0.0]))
		var stopped := RC.project_relative_speeds(coaxial.stage, [0])
		_check("signed coaxial actuator impulse work %s" % carrier_twist, stopped.ok and stopped.actuator_impulse_work * carrier_twist < 0.0 \
			and absf(stopped.kinetic_energy_after - stopped.kinetic_energy_before - stopped.actuator_impulse_work + stopped.dissipated_energy) < 1e-13)
		if carrier_twist < 0.0:
			_check("prescribed actuator can supply net energy during dissipative stop", stopped.kinetic_energy_after > stopped.kinetic_energy_before)
		print("GP-09c coaxial nu=", carrier_twist, " actuator_impulse_J=", stopped.actuator_impulse_work,
			" dissipated_J=", stopped.dissipated_energy, " delta_T_J=", stopped.kinetic_energy_after - stopped.kinetic_energy_before)


func _reference_and_adapter() -> void:
	var locked := PackedFloat64Array([1.2, 1.5, 1.8, 0.02, -0.03, 0.04])
	var a := M.v3(0.6, -0.8, 0.0)
	var prepared := RC.prepare_system(locked, PackedFloat64Array([0.1]), PackedFloat64Array([0.06]), a, _partition())
	var w := M.v3(0.4, -0.3, 0.2)
	var moment := M.v3(0.2, -0.4, 0.1)
	var zero := M.v3(0.0, 0.0, 0.0)
	var out := RC.evaluate_system(prepared, locked, w, PackedFloat64Array([4.0]), a, zero, zero, moment, zero, PackedFloat64Array([0.2]))
	var old := RC.response(w, moment, locked, RB.inertia_inverse(locked), a, 0.1, 4.0, 0.2)
	var old_alpha := RB.inertia_mul(RB.inertia_inverse(locked), M.sub(M.add(moment, old.reaction),
		M.cross(w, M.add(RB.inertia_mul(locked, w), old.momentum))))
	_check("one free shaft recovers established simultaneous response", old.ok and out.ok and absf(out.spin_acceleration[0] - old.spin_acceleration) < 1e-13 \
		and _near(out.angular_acceleration, old_alpha, 1e-13))
	var wheel := WC.prepare_transport(PackedFloat64Array(BODY), PackedFloat64Array([0.2, 0.15, 0.1, 1.0]), PackedFloat64Array(J), PackedFloat64Array(K))
	var angular := PackedFloat64Array([4.0, -3.0, 2.0, 5.0])
	var rims := PackedFloat64Array([0.8, -0.45, 0.2, 5.0])
	var wheel_out := WC.evaluate_transport(wheel, w, rims, PackedFloat64Array(AXES), PackedFloat64Array(NU), PackedFloat64Array(NUDOT),
		moment, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	var common := RC.evaluate_system(_prepared(), _locked(), w, angular, PackedFloat64Array(AXES), PackedFloat64Array(NU), PackedFloat64Array(NUDOT),
		moment, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	_check("rim adapter uses common angular system", _near(wheel_out.angular_acceleration, common.angular_acceleration, 1e-13) \
		and absf(wheel_out.derivative[0] - 0.2 * common.spin_acceleration[0]) < 1e-13 \
		and absf(wheel_out.derivative[1] - 0.15 * common.spin_acceleration[1]) < 1e-13)
	_check("original fixed/rim law identities remain available", WC.LAW == "fixed-axis-relative-rim-coupling-v1" and WC.TRANSPORT_LAW == "fixed-center-prescribed-carrier-axisymmetric-rim-v1")


func _validation_identity() -> void:
	var locked := _locked()
	var axial := PackedFloat64Array(J)
	var transverse := PackedFloat64Array(K)
	var axes := PackedFloat64Array(AXES)
	var partition := _partition()
	var original := var_to_bytes([locked, axial, transverse, axes, partition])
	var prepared := RC.prepare_system(locked, axial, transverse, axes, partition)
	_check("preparation does not mutate source arrays/provenance", original == var_to_bytes([locked, axial, transverse, axes, partition]))
	var repeated := RC.prepare_system(locked, axial, transverse, axes, partition)
	_check("same authoritative inputs have deterministic identity", repeated.identity == prepared.identity)
	partition.source = "different explicitly estimated provenance"
	_check("changed provenance changes identity", RC.prepare_system(locked, axial, transverse, axes, partition).identity != prepared.identity)
	axial[0] *= 1.1
	_check("changed rotor reservation changes identity", RC.prepare_system(locked, axial, transverse, axes, _partition()).identity != prepared.identity)
	_check("prepared arrays and provenance are detached", prepared.axial[0] == J[0] and prepared.partition.source == _partition().source)
	_check("SPD but nonphysical aggregate remainder rejects", not RC.prepare_system(PackedFloat64Array([1.6, 1.3, 2.5, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.6]), PackedFloat64Array([0.3]), M.v3(1.0, 0.0, 0.0), _partition()).ok)
	var measured := _partition()
	measured.kind = "measured"
	_check("aggregate estimate cannot masquerade as measured inventory", not RC.prepare_system(_locked(), PackedFloat64Array(J), PackedFloat64Array(K), PackedFloat64Array(AXES), measured).ok)
	var spin := PackedFloat64Array([4.0, -3.0, 2.0, 0.0])
	for holds: Array in [[{rotor_index = 3, capacity_nm = -1.0}], [{rotor_index = 3, capacity_nm = NAN}],
			[{rotor_index = 3, capacity_nm = 1.0}, {rotor_index = 3, capacity_nm = 1.0}],
			[{rotor_index = 4, capacity_nm = 1.0}], [{rotor_index = 3.0, capacity_nm = 1.0}],
			[{rotor_index = 0, capacity_nm = 1.0}], [{rotor_index = 3}], [7]]:
		_check("malformed/nonzero-speed hold rejects %s" % str(holds), not _evaluate(spin, holds).ok)
	var stage: Dictionary = _evaluate(spin).stage
	for indices: Array in [[3, 3], [-1], [4], [1.0], [true]]:
		_check("malformed projection constraint rejects %s" % str(indices), not RC.project_relative_speeds(stage, indices).ok)
	var broken := stage.duplicate(true)
	broken.matrix[0] += 1.0
	_check("projection rejects a matrix changed outside its inventory", not RC.project_relative_speeds(broken, [3]).ok)
	broken = stage.duplicate(true)
	broken.affine_momentum[0] += 1.0
	_check("projection rejects inconsistent prescribed affine momentum", not RC.project_relative_speeds(broken, [3]).ok)
	_check("projection rejects missing stage identity", not RC.project_relative_speeds({}, [3]).ok)
	var live := _locked()
	for i in 3:
		live[i] -= 0.1
	var zero12 := PackedFloat64Array()
	zero12.resize(12)
	var snapshot := var_to_bytes([prepared, live, spin, axes, zero12])
	var sample := RC.evaluate_system(prepared, live, M.v3(0.0, 0.0, 0.0), spin, axes, zero12, zero12,
		M.v3(0.0, 0.0, 0.0), zero12, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	_check("live reference tensor is sampled without changing configuration identity", sample.ok and sample.system_identity == prepared.identity \
		and absf(sample.stage.carrier[0] - (BODY[0] - 0.1)) < 1e-13)
	_check("evaluation does not mutate prepared/live/motion input", snapshot == var_to_bytes([prepared, live, spin, axes, zero12]))
	var no_rotors := RC.prepare_system(PackedFloat64Array(BODY), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), _partition())
	var body_only := RC.evaluate_system(no_rotors, PackedFloat64Array(BODY), M.v3(0.2, -0.1, 0.4), PackedFloat64Array(), PackedFloat64Array(),
		PackedFloat64Array(), PackedFloat64Array(), M.v3(0.1, -0.2, 0.3), PackedFloat64Array(), PackedFloat64Array())
	_check("empty rotor layout remains a valid body solve", body_only.ok and body_only.spin_acceleration.is_empty())
	_check("empty-layout projection preserves its state", RC.project_relative_speeds(body_only.stage, []).ok)


func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]) or absf(a[i] - b[i]) > tolerance:
			return false
	return true
