# P51-24: steady straight sideslips on the runtime equations, for comparison with NACA RM L6J25 Table I
# (P-51D rudder-fixed d(rudder)/d(sideslip) at +-1 deg). Unknowns: alpha, elevator, throttle (level) or
# flight-path angle (glide), bank, aileron, rudder; the sideslip is imposed; all six accelerations vanish.
# Research only. Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/sideslip_probe.gd
#                       [-- --data=res://... --speeds=25.7,45 --beta=1,2]
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
	var path := "res://data/aircraft/p51d_mustang_120.json"
	var speeds := [25.7, 35.0, 45.0]
	var betas := [1.0, 2.0]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			path = arg.trim_prefix("--data=")
		elif arg.begins_with("--speeds="):
			speeds = Array(arg.trim_prefix("--speeds=").split(",")).map(func(t): return float(t))
	var loaded: Dictionary = AircraftData.load_file(path)
	if not loaded.ok:
		printerr(loaded.errors)
		quit(1)
		return
	var model: Dictionary = loaded.model
	for mode in ["level", "glide"]:
		for V: float in speeds:
			var x0 := PackedFloat64Array([0.05, -0.05, 0.3 if mode == "level" else -0.1, 0.0, 0.0, 0.0])
			var base := _solve(V, 0.0, mode, model, x0)
			if not base.ok:
				print("%s V %.1f: no zero-sideslip solution" % [mode, V])
				continue
			for b: float in betas:
				var plus := _solve(V, deg_to_rad(b), mode, model, base.x)
				var minus := _solve(V, -deg_to_rad(b), mode, model, base.x)
				if not plus.ok or not minus.ok:
					print("%s V %.1f beta %.0f: unsolved" % [mode, V, b])
					continue
				var dr: float = (plus.x[5] - minus.x[5]) / (2.0 * deg_to_rad(b))
				var da: float = (plus.x[4] - minus.x[4]) / (2.0 * deg_to_rad(b))
				var bank: float = rad_to_deg(plus.x[3] - minus.x[3]) / (2.0 * b)
				print("%s V %.1f beta +-%.0f deg: d(rudder)/d(beta) %.3f  d(aileron)/d(beta) %.3f  d(bank)/d(beta) %.3f  throttle %.3f  rudder0 %.2f deg" % [
					mode, V, b, absf(dr), da, bank, base.x[2] if mode == "level" else NAN, rad_to_deg(base.x[5])])
	quit(0)
