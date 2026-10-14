# HELI-08: signed multi-member gear and simultaneous six-axis momentum balance.
extends SceneTree

const Coupling = preload("res://physics/rotorcraft/geared_coupling.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1.0e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	var elements: Array = [
		{"inertia_kg_m2": 0.076, "speed_ratio": 1.0, "spin_axis_body_frd": M.v3(0.0, 0.0, 1.0)},
		{"inertia_kg_m2": 0.00017498940853579914, "speed_ratio": 4.66,
			"spin_axis_body_frd": M.v3(0.0, 1.0, 0.0)},
	]
	var prepared: Dictionary = Coupling.prepare(elements)
	check("source signed-shaft inventory prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var spin_inertia: float = 0.076 + 4.66 * 4.66 * 0.00017498940853579914
	close("reflected inertia is sum of squared ratios", prepared.spin_inertia_kg_m2, spin_inertia)
	close("main-axis momentum contributes signed b z", prepared.b_body_frd_kg_m2[2], 0.076)
	close("tail-axis momentum contributes signed b y", prepared.b_body_frd_kg_m2[1],
		4.66 * 0.00017498940853579914)
	var inertia: PackedFloat64Array = PackedFloat64Array([0.18, 0.34, 0.28, 0.0, 0.0, 0.0])
	var inverse: PackedFloat64Array = RB.inertia_inverse(inertia)
	var b: PackedFloat64Array = prepared.b_body_frd_kg_m2
	var w: PackedFloat64Array = M.v3(0.17, -0.23, 0.31)
	var moment: PackedFloat64Array = M.v3(0.4, -0.5, 0.6)
	var speed: float = 167.0
	var torque: float = 0.73
	var solved: Dictionary = Coupling.response(w, moment, inertia, inverse, b, spin_inertia, speed, torque)
	check("simultaneous body and shaft accelerations solve", solved.ok)
	if solved.ok:
		var body_momentum_rate: PackedFloat64Array = RB.inertia_mul(inertia, solved.body_acceleration_rad_s2)
		var shaft_exchange: PackedFloat64Array = M.scale(b, solved.spin_acceleration_rad_s2)
		var predicted_body_rate: PackedFloat64Array = M.sub(M.sub(moment,
			M.cross(w, solved.total_angular_momentum_body_frd_nms)), shaft_exchange)
		for axis: int in range(3):
			close("body angular momentum row closes axis " + str(axis),
				body_momentum_rate[axis], predicted_body_rate[axis])
		close("shaft momentum row closes simultaneously", spin_inertia * solved.spin_acceleration_rad_s2
			+ M.dot(b, solved.body_acceleration_rad_s2), torque)
		var stored_momentum: PackedFloat64Array = M.add(RB.inertia_mul(inertia, w), M.scale(b, speed))
		check("returned angular momentum is locked body plus every rotor", stored_momentum
			== solved.total_angular_momentum_body_frd_nms)
		var momentum_rate_body: PackedFloat64Array = M.add(body_momentum_rate, shaft_exchange)
		var world_from_body: PackedFloat64Array = M.q_from_euler(0.4, -0.2, 0.3)
		var inertial_momentum_rate: PackedFloat64Array = M.q_rotate(world_from_body,
			M.add(momentum_rate_body, M.cross(w, solved.total_angular_momentum_body_frd_nms)))
		var applied_world_moment: PackedFloat64Array = M.q_rotate(world_from_body, moment)
		for axis: int in range(3):
			close("world angular momentum rate equals external torque axis " + str(axis),
				inertial_momentum_rate[axis], applied_world_moment[axis])
		var kinetic_energy_rate: float = M.dot(w, body_momentum_rate) \
			+ solved.spin_acceleration_rad_s2 * M.dot(b, w) \
			+ speed * M.dot(b, solved.body_acceleration_rad_s2) \
			+ spin_inertia * speed * solved.spin_acceleration_rad_s2
		close("cross-coupled kinetic energy rate equals external mechanical power", kinetic_energy_rate,
			M.dot(moment, w) + torque * speed, 1.0e-10)
	var fixed: Dictionary = Coupling.response(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0),
		inertia, inverse, b, spin_inertia, 10.0, 0.5)
	check("fixed-body shaft test has finite coupled reaction", fixed.ok)
	if fixed.ok:
		var expected_denominator: float = 1.0 - M.dot(b, M.v3(b[0] * inverse[0], b[1] * inverse[1], b[2] * inverse[2])) / spin_inertia
		close("effective carrier inertia uses J inverse", fixed.effective_inertia_factor, expected_denominator)
		var expected_alpha: float = 0.5 / (spin_inertia * expected_denominator)
		close("fixed-body shaft acceleration solves the reduced inertia", fixed.spin_acceleration_rad_s2, expected_alpha)
	var clamp_torque: float = 0.5
	var clamp_moment: PackedFloat64Array = M.scale(b, clamp_torque / spin_inertia)
	var clamped: Dictionary = Coupling.response(M.v3(0.0, 0.0, 0.0), clamp_moment,
		inertia, inverse, b, spin_inertia, 10.0, clamp_torque)
	check("fixed-body stand clamp reacts the cross-axis coupling", clamped.ok)
	if clamped.ok:
		close("fixture clamp holds body angular acceleration at zero",
			M.dot(clamped.body_acceleration_rad_s2, clamped.body_acceleration_rad_s2), 0.0)
		var dt: float = 0.01
		var final_speed: float = 10.0 + clamp_torque / spin_inertia * dt
		var rotor_energy_change: float = 0.5 * spin_inertia * (final_speed * final_speed - 100.0)
		var drive_work: float = clamp_torque * (10.0 * dt + 0.5 * clamp_torque / spin_inertia * dt * dt)
		close("fixed-body shaft stand energy matches integrated delivered work",
			rotor_energy_change, drive_work, 1.0e-12)
	var reversed_elements: Array = [
		{"inertia_kg_m2": 0.1, "speed_ratio": 2.0, "spin_axis_body_frd": M.v3(0.0, 0.0, -1.0)},
		{"inertia_kg_m2": 0.05, "speed_ratio": 1.0, "spin_axis_body_frd": M.v3(0.0, 1.0, 0.0)},
	]
	var reversed: Dictionary = Coupling.prepare(reversed_elements)
	check("opposing member keeps its signed shaft axis", reversed.ok
		and reversed.b_body_frd_kg_m2[2] == -0.2 and reversed.b_body_frd_kg_m2[1] == 0.05)
	var bad_axis: Array = elements.duplicate(true)
	bad_axis[0].spin_axis_body_frd = M.v3(0.0, 0.0, -2.0)
	check("non-unit or unsigned axis inventory is refused", not Coupling.prepare(bad_axis).ok)
	var singular: Dictionary = Coupling.response(M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0),
		PackedFloat64Array([0.001, 0.001, 0.001, 0.0, 0.0, 0.0]),
		PackedFloat64Array([1000.0, 1000.0, 1000.0, 0.0, 0.0, 0.0]),
		M.v3(0.0, 0.0, 0.1), 1.0, 10.0, 1.0)
	check("nonpositive effective carrier inertia fails closed", not singular.ok)
	print("HELI-08 geared coupling: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
