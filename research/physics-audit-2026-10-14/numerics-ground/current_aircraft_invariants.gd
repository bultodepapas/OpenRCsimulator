extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const RK := preload("res://physics/integrator.gd")
const Dynamics := preload("res://physics/dynamics.gd")

const G := 9.80665
const AIRCRAFT := [
	["Ventage Jet", "res://data/aircraft/sebart_avanti_s_a200.json", 85000.0],
	["Jensen Ugly Stik 60", "res://data/aircraft/jensen_ugly_stik_60.json", 7500.0],
]

var _failures := 0


func _initialize() -> void:
	print("Godot ", Engine.get_version_info().string, "; packed state=PackedFloat64Array")
	for item: Array in AIRCRAFT:
		var loaded: Dictionary = AD.load_file(item[1])
		if not loaded.get("ok", false):
			printerr("FAIL load ", item[0], ": ", loaded.get("errors", []))
			_failures += 1
			continue
		var model: Dictionary = loaded.model
		_audit_model(str(item[0]), model, float(item[2]))
	print("current-aircraft invariant probe: ", _failures, " failed")
	quit(1 if _failures > 0 else 0)


func _audit_model(label: String, model: Dictionary, rpm: float) -> void:
	var inertia: PackedFloat64Array = model.inertia
	var principal := _principal_moments(inertia)
	var triangle_margin: float = principal[0] + principal[1] - principal[2]
	var determinant: float = inertia[0] * (inertia[1] * inertia[2] - inertia[5] * inertia[5]) \
		- inertia[3] * (inertia[3] * inertia[2] - inertia[4] * inertia[5]) \
		+ inertia[4] * (inertia[3] * inertia[5] - inertia[4] * inertia[1])
	var h: PackedFloat64Array = Dynamics.rotor_momentum(model, rpm)
	print("MODEL ", label, " id=", model.id, " mass_kg=", model.mass_kg,
		" J=[", inertia, "] principal_kg_m2=", principal,
		" triangle_margin=", triangle_margin, " determinant=", determinant,
		" rpm=", rpm, " h_body_Nms=", h,
		" state_type=", type_string(typeof(RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0)))))
	_check(label + " tensor positive and realizable",
		principal[0] > 0.0 and triangle_margin > 0.0 and determinant > 0.0,
		"principal=" + str(principal) + " triangle margin=" + str(triangle_margin))
	_ballistic(label, model)
	_free_rotation(label, model, h)


func _ballistic(label: String, model: Dictionary) -> void:
	var q: PackedFloat64Array = M.q_from_euler(deg_to_rad(23.0), deg_to_rad(-11.0), deg_to_rad(37.0))
	var s: PackedFloat64Array = RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), q, M.v3(0, 0, 0))
	var dt := 1.0 / 240.0
	var duration := 1.25
	var zero := M.v3(0, 0, 0)
	var derivative := func(state: PackedFloat64Array) -> PackedFloat64Array:
		return RB.derivative(state, model.mass_kg, model.inertia, RB.inertia_inverse(model.inertia), zero, zero, G)
	for _i in roundi(duration / dt):
		s = RK.rk4_step(s, dt, derivative)
	var expected_down := 0.5 * G * duration * duration
	var position_error := sqrt(s[RB.POS] * s[RB.POS] + s[RB.POS + 1] * s[RB.POS + 1]
		+ (s[RB.POS + 2] - expected_down) * (s[RB.POS + 2] - expected_down))
	var velocity_ned := M.q_rotate(s.slice(RB.ATT, RB.ATT + 4), s.slice(RB.VEL, RB.VEL + 3))
	var velocity_error := sqrt(velocity_ned[0] * velocity_ned[0] + velocity_ned[1] * velocity_ned[1]
		+ (velocity_ned[2] - G * duration) * (velocity_ned[2] - G * duration))
	print("BALLISTIC ", label, " tilted 1.25s NED Δposition_m=", position_error,
		" Δvelocity_m_s=", velocity_error, " down_m=", s[RB.POS + 2], " velocity_ned=", velocity_ned)
	_check(label + " tilted free fall resolves gravity in NED", position_error < 1e-10 and velocity_error < 1e-10,
		"Δp=" + str(position_error) + " m Δv=" + str(velocity_error) + " m/s")


func _free_rotation(label: String, model: Dictionary, h: PackedFloat64Array) -> void:
	var q := M.q_from_euler(0.31, -0.22, 0.47)
	var w := M.v3(1.1, 0.8, -0.6)
	var s := RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), q, w)
	var j_inverse := RB.inertia_inverse(model.inertia)
	var zero := M.v3(0, 0, 0)
	var initial_energy := 0.5 * M.dot(w, RB.inertia_mul(model.inertia, w))
	var initial_momentum := _inertial_momentum(s, model.inertia, h)
	var derivative := func(state: PackedFloat64Array) -> PackedFloat64Array:
		return RB.derivative(state, model.mass_kg, model.inertia, j_inverse, zero, zero, 0.0, h)
	for _i in 240 * 5:
		s = RK.rk4_step(s, 1.0 / 240.0, derivative)
	var final_w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE + 3)
	var final_energy := 0.5 * M.dot(final_w, RB.inertia_mul(model.inertia, final_w))
	var final_momentum := _inertial_momentum(s, model.inertia, h)
	var momentum_error := M.norm(M.sub(final_momentum, initial_momentum))
	var relative_energy_error := absf(final_energy - initial_energy) / maxf(initial_energy, 1e-30)
	var q_final: PackedFloat64Array = s.slice(RB.ATT, RB.ATT + 4)
	var q_norm := sqrt(q_final[0] * q_final[0] + q_final[1] * q_final[1]
		+ q_final[2] * q_final[2] + q_final[3] * q_final[3])
	print("FREE_ROTATION ", label, " 5s 240Hz h_Nms=", h,
		" ΔH_inertial_Nms=", momentum_error, " relative_ΔE=", relative_energy_error,
		" final_q_norm=", q_norm, " final_rates=", final_w)
	_check(label + " torque-free angular momentum and energy are conserved",
		momentum_error < 1e-9 and relative_energy_error < 1e-8 and absf(q_norm - 1.0) < 1e-14,
		"ΔH=" + str(momentum_error) + " N·m·s relative ΔE=" + str(relative_energy_error))


func _inertial_momentum(s: PackedFloat64Array, inertia: PackedFloat64Array, h: PackedFloat64Array) -> PackedFloat64Array:
	var body_h: PackedFloat64Array = M.add(RB.inertia_mul(inertia, s.slice(RB.RATE, RB.RATE + 3)), h)
	return M.q_rotate(s.slice(RB.ATT, RB.ATT + 4), body_h)


func _principal_moments(inertia: PackedFloat64Array) -> PackedFloat64Array:
	var a: Array = [
		[inertia[0], inertia[3], inertia[4]],
		[inertia[3], inertia[1], inertia[5]],
		[inertia[4], inertia[5], inertia[2]],
	]
	for _iteration in 40:
		var p := 0
		var q := 1
		if absf(a[0][2]) > absf(a[p][q]):
			p = 0
			q = 2
		if absf(a[1][2]) > absf(a[p][q]):
			p = 1
			q = 2
		if absf(a[p][q]) < 1e-18:
			break
		var app: float = a[p][p]
		var aqq: float = a[q][q]
		var apq: float = a[p][q]
		var angle := 0.5 * atan2(2.0 * apq, aqq - app)
		var c := cos(angle)
		var sn := sin(angle)
		for r in 3:
			if r == p or r == q:
				continue
			var arp: float = a[r][p]
			var arq: float = a[r][q]
			a[r][p] = c * arp - sn * arq
			a[p][r] = a[r][p]
			a[r][q] = sn * arp + c * arq
			a[q][r] = a[r][q]
		a[p][p] = c * c * app - 2.0 * sn * c * apq + sn * sn * aqq
		a[q][q] = sn * sn * app + 2.0 * sn * c * apq + c * c * aqq
		a[p][q] = 0.0
		a[q][p] = 0.0
	var values := [float(a[0][0]), float(a[1][1]), float(a[2][2])]
	values.sort()
	return PackedFloat64Array(values)


func _check(label: String, ok: bool, detail: String) -> void:
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1
