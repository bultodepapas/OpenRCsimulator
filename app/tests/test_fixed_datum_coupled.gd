## Coupled final-alpha composition. Synthetic mechanics; no aircraft calibration.
extends SceneTree
const Datum := preload("res://physics/fixed_datum_body.gd")
const Inventory := preload("res://physics/mass_inventory.gd")
const RC := preload("res://physics/rotor_coupling.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
var checks := 0
var failed := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_geometry()
	_coupled()
	_integrated_coupled()
	_refusals()
	print("Fixed datum coupled: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _state() -> PackedFloat64Array:
	return RB.make_state(M.v3(2.0, -3.0, 7.0), M.v3(5.0, -2.0, 1.0),
		M.q_from_axis_angle(M.v3(0.3, 0.4, 0.5), 0.6), M.v3(0.4, -0.3, 0.2))

func _properties() -> Dictionary:
	var tensor := PackedFloat64Array([1.2, 1.5, 1.8, 0.02, -0.03, 0.04])
	return {mass_kg = 3.0, inertia = tensor, inverse = RB.inertia_inverse(tensor), cg_body_m = M.v3(0.13, -0.07, 0.09)}

func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance := 2.0e-12) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not is_finite(a[i]) or absf(a[i] - b[i]) > tolerance: return false
	return true

func _gravity(s: PackedFloat64Array, gravity: float) -> PackedFloat64Array:
	var q := s.slice(RB.ATT, RB.ATT + 4)
	return M.q_rotate(PackedFloat64Array([q[0], -q[1], -q[2], -q[3]]), M.v3(0.0, 0.0, gravity))

func _newton(s: PackedFloat64Array, p: Dictionary, force: PackedFloat64Array, gravity: float, alpha: PackedFloat64Array) -> void:
	var before := var_to_bytes([s, p, force, alpha])
	var derivative := Datum.derivative_with_angular_acceleration(s, p, force, gravity, alpha)
	check("well formed final-alpha derivative", derivative.size() == RB.SIZE)
	if derivative.size() != RB.SIZE: return
	var omega := s.slice(RB.RATE, RB.RATE + 3)
	var expected_cm := M.add(M.scale(force, 1.0 / p.mass_kg), _gravity(s, gravity))
	# Independent rigid-point Newton relation in BODY axes at a frozen sample:
	# aO = vO_dot + omega cross vO; aC = aO + alpha cross c + omega cross (omega cross c).
	var datum_acceleration := M.add(derivative.slice(RB.VEL, RB.VEL + 3), M.cross(omega, s.slice(RB.VEL, RB.VEL + 3)))
	var cm_acceleration := M.add(datum_acceleration, M.add(M.cross(alpha, p.cg_body_m), M.cross(omega, M.cross(omega, p.cg_body_m))))
	check("independent Newton CM acceleration closes", _near(cm_acceleration, expected_cm))
	check("independent datum acceleration closes", _near(datum_acceleration,
		M.sub(M.sub(expected_cm, M.cross(alpha, p.cg_body_m)), M.cross(omega, M.cross(omega, p.cg_body_m)))))
	check("supplied final alpha copied exactly", derivative.slice(RB.RATE, RB.RATE + 3) == alpha)
	check("derivative input fields remain untouched", before == var_to_bytes([s, p, force, alpha]))

func _geometry() -> void:
	var s := _state()
	var p := _properties()
	var force := M.v3(4.0, -1.0, 2.0)
	var alpha := M.v3(-0.8, 0.6, 0.9)
	_newton(s, p, force, 4.2, alpha)
	var ordinary := RB.derivative(s, p.mass_kg, p.inertia, p.inverse, force, M.v3(7.0, 8.0, -9.0), 4.2)
	p.cg_body_m = M.v3(0.0, 0.0, 0.0)
	var zero_cg := Datum.derivative_with_angular_acceleration(s, p, force, 4.2, alpha)
	check("unit boundary zero CG agrees with RB within rounding", _near(zero_cg.slice(0, RB.RATE), ordinary.slice(0, RB.RATE), 2.0e-14))
	check("zero CG preserves supplied alpha exactly", zero_cg.slice(RB.RATE) == alpha)
	s[RB.ATT] *= 1.01
	var raw_stage := Datum.derivative_with_angular_acceleration(s, p, force, 4.2, alpha)
	var raw_rb := RB.derivative(s, p.mass_kg, p.inertia, p.inverse, force, M.v3(0.0, 0.0, 0.0), 4.2)
	var normalized_q := M.q_normalized(s.slice(RB.ATT, RB.ATT + 4))
	check("nonunit stage rotates position using orthonormal local q", raw_stage.size() == RB.SIZE \
		and _near(raw_stage.slice(RB.POS, RB.POS + 3), M.q_rotate(normalized_q, s.slice(RB.VEL, RB.VEL + 3)) ))
	check("nonunit stage preserves exact raw quaternion ODE derivative", raw_stage.slice(RB.ATT, RB.ATT + 4).to_byte_array() == raw_rb.slice(RB.ATT, RB.ATT + 4).to_byte_array())
	var rotation_state := s.duplicate()
	for i in 4: rotation_state[RB.ATT + i] = normalized_q[i]
	var rotated_rb := RB.derivative(rotation_state, p.mass_kg, p.inertia, p.inverse, force, M.v3(0.0, 0.0, 0.0), 4.2)
	check("nonunit stage gravity uses same normalized local rotation", _near(raw_stage.slice(RB.VEL, RB.VEL + 3), rotated_rb.slice(RB.VEL, RB.VEL + 3)))
	s = _state()
	p = _properties()
	var moment_o := M.v3(0.3, -0.2, 0.1)
	var moment_cm := M.sub(moment_o, M.cross(p.cg_body_m, force))
	var old := Datum.derivative(s, p, force, moment_cm, 4.2, PackedFloat64Array())
	var same := Datum.derivative_with_angular_acceleration(s, p, force, 4.2, old.slice(RB.RATE))
	check("unit boundary equivalent final alpha matches old derivative within rounding", _near(same, old, 2.0e-14))
	var distinct := Datum.derivative_with_angular_acceleration(s, p, force, 4.2, alpha)
	var double_corrected := old.duplicate()
	var omega := s.slice(RB.RATE)
	var correction := M.add(M.cross(alpha, p.cg_body_m), M.cross(omega, M.cross(omega, p.cg_body_m)))
	for i in 3: double_corrected[RB.VEL + i] -= correction[i]
	check("fixture distinguishes the forbidden double datum correction", not _near(distinct.slice(RB.VEL, RB.VEL + 3), double_corrected.slice(RB.VEL, RB.VEL + 3), 1.0e-5))

func _coupled() -> void:
	var reference_tensor: PackedFloat64Array = _properties().inertia
	var reference := Inventory.prepare_reference(3.0, reference_tensor, [{id = "fuel", reference_mass_kg = 0.5,
		capacity_mass_kg = 0.5, center_body_m = M.v3(0.4, -0.2, 0.3), size_body_m = M.v3(0.2, 0.1, 0.15)}])
	check("live fuel reference prepares", reference.ok)
	var axial := PackedFloat64Array([0.03, 0.04, 0.01, 0.06])
	var transverse := PackedFloat64Array([0.02, 0.025, 0.007, 0.04])
	var axes := PackedFloat64Array([0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.6, -0.8, 0.0, 1.0, 0.0, 0.0])
	var prepared := RC.prepare_system(reference_tensor, axial, transverse, axes,
		{partition_id = "fixed-datum-test", reference_pose_id = "neutral", kind = "estimated", source = "Synthetic rotor/fuel composition fixture"})
	check("three wheels plus dynamic shaft partition prepares", prepared.ok)
	var s := _state()
	var force := M.v3(4.0, -1.0, 2.0)
	var moment_o := M.v3(0.3, -0.2, 0.1)
	var spin := PackedFloat64Array([4.0, -3.0, 2.0, 9.0])
	var internal := PackedFloat64Array([-0.02, 0.03, -0.01, 0.2])
	var zeros := PackedFloat64Array()
	zeros.resize(12)
	for amount: float in [0.5, 0.2, 0.0]:
		var p := Inventory.evaluate_reference(reference, PackedFloat64Array([amount]))
		check("live fuel mass sample evaluates", p.ok)
		var moment_cm := M.sub(moment_o, M.cross(p.cg_body_m, force))
		var response := RC.evaluate_system(prepared, p.inertia, s.slice(RB.RATE), spin, axes, zeros, zeros, moment_cm, zeros, internal)
		check("3+4 response with live fuel reference solves", response.ok)
		if not response.ok: continue
		_newton(s, p, force, 0.0, response.angular_acceleration)
		var derivative := Datum.derivative_with_angular_acceleration(s, p, force, 0.0, response.angular_acceleration)
		var velocity_cm := M.add(s.slice(RB.VEL, RB.VEL + 3), M.cross(s.slice(RB.RATE), p.cg_body_m))
		var velocity_cm_dot := M.add(derivative.slice(RB.VEL, RB.VEL + 3), M.cross(response.angular_acceleration, p.cg_body_m))
		# Frozen sample mechanical power only: resource energy flux stays with fuel owner.
		var translation_rate: float = p.mass_kg * M.dot(velocity_cm, velocity_cm_dot)
		var power_datum: float = M.dot(force, s.slice(RB.VEL, RB.VEL + 3)) + M.dot(moment_o, s.slice(RB.RATE))
		for rotor in spin.size(): power_datum += internal[rotor] * spin[rotor]
		check("analytic coupled kinetic power closes without invented fuel flux", absf(translation_rate + response.kinetic_energy_rate - power_datum) < 3.0e-12)
		check("CM moment shift preserves fixed-datum external power exactly once", absf(M.dot(force, velocity_cm) + M.dot(moment_cm, s.slice(RB.RATE)) \
			- M.dot(force, s.slice(RB.VEL, RB.VEL + 3)) - M.dot(moment_o, s.slice(RB.RATE))) < 1.0e-14)
		var acceleration: PackedFloat64Array = response.angular_acceleration.duplicate()
		acceleration.append_array(response.spin_acceleration)
		var n := acceleration.size()
		var residual := PackedFloat64Array()
		residual.resize(n)
		for row in n:
			for column in n: residual[row] += response.stage.matrix[row * n + column] * acceleration[column]
		check("coupled body and every rotor satisfy full mass matrix", _near(residual, response.stage.generalized_rhs))

## Actual kernel RK stages with three wheels plus a dynamic shaft, no torques.
## The fuel sample is frozen for each run: this gate measures mechanical invariants,
## not a new resource-flux law. Both datum and CM move while body rates precess.
func _integrated_coupled() -> void:
	var saved_hz: int = Engine.physics_ticks_per_second
	var reference_tensor: PackedFloat64Array = _properties().inertia
	var reference := Inventory.prepare_reference(3.0, reference_tensor, [{id = "fuel", reference_mass_kg = 0.5,
		capacity_mass_kg = 0.5, center_body_m = M.v3(0.4, -0.2, 0.3), size_body_m = M.v3(0.2, 0.1, 0.15)}])
	var properties := Inventory.evaluate_reference(reference, PackedFloat64Array([0.2]))
	var axial := PackedFloat64Array([0.03, 0.04, 0.01, 0.06])
	var transverse := PackedFloat64Array([0.02, 0.025, 0.007, 0.04])
	var axes := PackedFloat64Array([0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.6, -0.8, 0.0, 1.0, 0.0, 0.0])
	var prepared := RC.prepare_system(reference_tensor, axial, transverse, axes,
		{partition_id = "integrated-datum-test", reference_pose_id = "neutral", kind = "estimated", source = "Synthetic torque-free RK convergence fixture"})
	var zero3 := M.v3(0.0, 0.0, 0.0)
	var zero12 := PackedFloat64Array()
	zero12.resize(12)
	var zero4 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var errors: Array[PackedFloat64Array] = []
	for hz: int in [120, 240, 480]:
		Engine.physics_ticks_per_second = hz
		var stage_nonunit := [0.0]
		var vehicle := Model.new()
		vehicle.aux_size = 0
		vehicle.continuous_size = 4
		vehicle.stage = func(body: PackedFloat64Array, spin: PackedFloat64Array, _time_s: float) -> Dictionary:
			var q := body.slice(RB.ATT, RB.ATT + 4)
			var norm_sq: float = q[0]*q[0]+q[1]*q[1]+q[2]*q[2]+q[3]*q[3]
			stage_nonunit[0] = maxf(stage_nonunit[0], absf(norm_sq - 1.0))
			var response := RC.evaluate_system(prepared, properties.inertia, body.slice(RB.RATE), spin, axes,
				zero12, zero12, zero3, zero12, zero4)
			if not response.ok: return {}
			return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = response.spin_acceleration,
				rotor_momentum = zero3, body_derivative = Datum.derivative_with_angular_acceleration(body, properties, zero3, 0.0, response.angular_acceleration)}
		var sim := Sim.new()
		sim.mass = properties.mass_kg
		sim.inertia = properties.inertia.duplicate()
		sim.gravity = 0.0
		sim.aux = PackedFloat64Array()
		sim.continuous = PackedFloat64Array([4.0, -3.0, 2.0, 9.0])
		check("integrated joint model installs at %d Hz" % hz, sim.set_model(vehicle))
		var initial := _state()
		initial[RB.RATE] = 2.1
		initial[RB.RATE + 1] = -1.3
		initial[RB.RATE + 2] = 0.9
		check("integrated body reset normalizes valid boundary", sim.reset(initial))
		var before := _invariants(sim.state, sim.continuous, properties, prepared, axes, zero3, zero12, zero4)
		for tick in hz:
			sim.step()
			check("every joint RK tick accepted at %d Hz" % hz, sim.tick == tick + 1 and sim.fault_reason.is_empty())
			if not sim.fault_reason.is_empty(): break
		var after := _invariants(sim.state, sim.continuous, properties, prepared, axes, zero3, zero12, zero4)
		var error := PackedFloat64Array([M.norm(M.sub(after.momentum, before.momentum)),
			M.norm(M.sub(after.angular_momentum, before.angular_momentum)), absf(after.energy - before.energy)])
		errors.append(error)
		check("actual RK fixture exercises nonunit stages beyond old refusal", stage_nonunit[0] > 1.0e-6)
		print("coupled RK Hz=", hz, " max_stage_qnorm_error=", stage_nonunit[0], " invariant_errors=", error)
		sim.free()
	for channel in 3:
		check("inertial momentum/energy refined 120->240", errors[1][channel] < maxf(2.0e-12, errors[0][channel] * 0.2))
		check("inertial momentum/energy refined 240->480", errors[2][channel] < maxf(2.0e-12, errors[1][channel] * 0.2))
		check("finest inertial invariant remains bounded", errors[2][channel] < 2.0e-9)
	Engine.physics_ticks_per_second = saved_hz

func _invariants(body: PackedFloat64Array, spin: PackedFloat64Array, properties: Dictionary,
		prepared: Dictionary, axes: PackedFloat64Array, zero3: PackedFloat64Array, zero12: PackedFloat64Array,
		zero4: PackedFloat64Array) -> Dictionary:
	var response := RC.evaluate_system(prepared, properties.inertia, body.slice(RB.RATE), spin, axes, zero12, zero12, zero3, zero12, zero4)
	var velocity_cm := M.add(body.slice(RB.VEL, RB.VEL + 3), M.cross(body.slice(RB.RATE), properties.cg_body_m))
	var q := M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
	return {momentum = M.q_rotate(q, M.scale(velocity_cm, properties.mass_kg)),
		angular_momentum = M.q_rotate(q, response.angular_momentum), energy = 0.5 * properties.mass_kg * M.dot(velocity_cm, velocity_cm) + response.kinetic_energy}

func _refusals() -> void:
	for kind: String in ["state_size", "state_nan", "quaternion", "quaternion_overflow", "force_size", "force_nan", "alpha_size", "alpha_nan", "gravity", "missing_mass", "mass_zero", "mass_type", "inertia_size", "inertia_nan", "inertia_nonphysical", "inertia_singular", "inverse_size", "inverse_nan", "inverse_wrong", "cg_size", "cg_nan", "sample_not_ok", "result_overflow"]:
		var s := _state()
		var p := _properties()
		var force := M.v3(4.0, -1.0, 2.0)
		var alpha := M.v3(0.7, -0.8, 0.9)
		var gravity := 9.80665
		match kind:
			"state_size": s.resize(12)
			"state_nan": s[0] = NAN
			"quaternion":
				for i in 4: s[RB.ATT + i] = 0.0
			"quaternion_overflow": s[RB.ATT] = 1.0e308
			"force_size": force.resize(2)
			"force_nan": force[0] = NAN
			"alpha_size": alpha.resize(2)
			"alpha_nan": alpha[0] = NAN
			"gravity": gravity = INF
			"missing_mass": p.erase("mass_kg")
			"mass_zero": p.mass_kg = 0.0
			"mass_type": p.mass_kg = "three"
			"inertia_size": p.inertia.resize(5)
			"inertia_nan": p.inertia[0] = NAN
			"inertia_nonphysical": p.inertia = PackedFloat64Array([1.0, 1.0, 8.0, 0.0, 0.0, 0.0])
			"inertia_singular": p.inertia = PackedFloat64Array([0.0, 1.0, 1.0, 0.0, 0.0, 0.0])
			"inverse_size": p.inverse.resize(5)
			"inverse_nan": p.inverse[0] = NAN
			"inverse_wrong": p.inverse[0] *= 2.0
			"cg_size": p.cg_body_m.resize(2)
			"cg_nan": p.cg_body_m[0] = NAN
			"sample_not_ok": p.ok = false
			"result_overflow": p.cg_body_m = M.v3(1.0e308, 1.0e308, 1.0e308); alpha = M.v3(1.0e308, 1.0e308, 1.0e308)
		var before := var_to_bytes([s, p, force, gravity, alpha])
		var rejected := Datum.derivative_with_angular_acceleration(s, p, force, gravity, alpha)
		check("malformed derivative rejected without mutation: " + kind, rejected.is_empty() and before == var_to_bytes([s, p, force, gravity, alpha]))
