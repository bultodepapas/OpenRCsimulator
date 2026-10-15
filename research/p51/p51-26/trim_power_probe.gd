# P51-26: level (powered) and glide (engine stopped) trim on the runtime equations at 22-45 m/s; prints the power-on minus
# glide elevator. Solver copied from research/p51/p51-24/sideslip_probe.gd. Research only.
# Run: <godot> --headless --path <app or disposable copy> --audio-driver Dummy --script <abs>/trim_power_probe.gd
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Trim := preload("res://physics/trim.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const G := 9.80665
const RHO := 1.225


func _state(V: float, alpha: float, beta: float, bank: float, gamma: float) -> PackedFloat64Array:
	var u := V * cos(alpha) * cos(beta)
	var v := V * sin(beta)
	var w := V * sin(alpha) * cos(beta)
	# Pitch so that the NED velocity's climb angle is gamma: -u sin(th) + cos(th)(v sin(phi) + w cos(phi)) = -V sin(gamma)
	var c := v * sin(bank) + w * cos(bank)
	var r := sqrt(u * u + c * c)
	var th := atan2(c, u) + asin(clampf(V * sin(gamma) / r, -1.0, 1.0))
	return RB.make_state(M.v3(0, 0, -300), M.v3(u, v, w), M.q_from_euler(0.0, th, bank), M.v3(0, 0, 0))


func _residual(x: PackedFloat64Array, V: float, beta: float, mode: String, model: Dictionary) -> PackedFloat64Array:
	var gamma := 0.0 if mode == "level" else x[2]
	var s := _state(V, x[0], beta, x[3], gamma)
	var rpm := 0.0
	if mode == "level":
		var u := M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(model.propulsion))
		rpm = Propulsion.steady_rpm(x[2], u, model.propulsion, RHO, 1.0)
	var d := { elevator = x[1], aileron_right = x[4], aileron_left = -x[4], rudder = x[5] }
	var dot: PackedFloat64Array = Dynamics.evaluate(s, model, d, rpm, RHO, M.v3(0, 0, 0), G).derivative
	return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 2], dot[RB.RATE + 1], dot[RB.VEL + 1], dot[RB.RATE], dot[RB.RATE + 2]])


func _solve(V: float, beta: float, mode: String, model: Dictionary, x0: PackedFloat64Array) -> Dictionary:
	var x := x0.duplicate()
	for it in 60:
		var r := _residual(x, V, beta, mode, model)
		var n := 0.0
		for v in r:
			n += v * v
		if sqrt(n) < 1e-10:
			return { ok = true, x = x }
		var jac := []
		for i in 6:
			jac.append(PackedFloat64Array([0, 0, 0, 0, 0, 0]))
		for k in 6:
			var h := 1e-7 * maxf(1.0, absf(x[k]))
			var xp := x.duplicate()
			xp[k] += h
			var rp := _residual(xp, V, beta, mode, model)
			for i in 6:
				jac[i][k] = (rp[i] - r[i]) / h
		var neg := PackedFloat64Array()
		for i in 6:
			neg.append(-r[i])
		var dx := Trim.solve_linear(jac, neg)
		if dx.is_empty():
			return { ok = false, x = x }
		for k in 6:
			x[k] += dx[k]
	return { ok = false, x = x }


func _initialize() -> void:
	var model: Dictionary = AircraftData.load_file("res://data/aircraft/p51d_mustang_120.json").model
	for V: float in [22.0, 25.0, 28.6, 35.0, 45.0]:
		var lv := _solve(V, 0.0, "level", model, PackedFloat64Array([0.05, -0.05, 0.3, 0.0, 0.0, 0.0]))
		var gl := _solve(V, 0.0, "glide", model, PackedFloat64Array([0.05, -0.05, -0.1, 0.0, 0.0, 0.0]))
		print("V %.1f  level: alpha %.2f elev %.3f deg thr %.3f | glide: alpha %.2f elev %.3f deg | power-on minus glide elev %.3f deg (%s %s)" % [V,
			rad_to_deg(lv.x[0]), rad_to_deg(lv.x[1]), lv.x[2], rad_to_deg(gl.x[0]), rad_to_deg(gl.x[1]), rad_to_deg(lv.x[1] - gl.x[1]), lv.ok, gl.ok])
	quit(0)
