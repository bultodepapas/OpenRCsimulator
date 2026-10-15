# P51-25: decomposes the runtime roll and yaw derivatives (per beta, per one-side aileron, per rudder; about the CG)
# at the beta = 0 steady sideslip solution into total, blended aero, attached oracle, local model, propulsion and
# slipstream parts, in qSb units. Shows that the oracle's ARP-referenced coefficients move by r x F at the CG.
# Solver copied from research/p51/p51-24/sideslip_probe.gd. Research only.
# Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/deriv_probe.gd [-- --data=res://...]
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Trim := preload("res://physics/trim.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
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


func _parts(x: PackedFloat64Array, V: float, beta: float, mode: String, model: Dictionary, da: float, dr: float) -> Dictionary:
	var gamma := 0.0 if mode == "level" else x[2]
	var s := _state(V, x[0], beta, x[3], gamma)
	var rpm := 0.0
	if mode == "level":
		var u := M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(model.propulsion))
		rpm = Propulsion.steady_rpm(x[2], u, model.propulsion, RHO, 1.0)
	var d := { elevator = x[1], aileron_right = x[4] + da, aileron_left = -(x[4] + da), rudder = x[5] + dr }
	var c: Dictionary = Dynamics.evaluate(s, model, d, rpm, RHO, M.v3(0, 0, 0), G)
	var air := Air.compute(s, M.v3(0, 0, 0), RHO)
	var glob := Aero._global_loads(s, air, d, model, RHO)
	var loc := Aero._local_loads(s, air, d, model, RHO)
	var total: PackedFloat64Array = c.loads
	var aero: PackedFloat64Array = c.aero_loads
	var prop: PackedFloat64Array = c.propulsion_loads
	var q: float = air.qbar * float(model.reference.S) * float(model.reference.b)
	return { total = [total[3] / q, total[5] / q], aero = [aero[3] / q, aero[5] / q], oracle = [glob[3] / q, glob[5] / q],
		local = [loc[3] / q, loc[5] / q], prop = [prop[3] / q, prop[5] / q], other = [(total[3] - aero[3] - prop[3]) / q, (total[5] - aero[5] - prop[5]) / q],
		blend = Aero.local_flow_weight(s, air, d, model) }


func _initialize() -> void:
	var path := "res://data/aircraft/p51d_mustang_120.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			path = arg.trim_prefix("--data=")
	var model: Dictionary = AircraftData.load_file(path).model
	var h := 1e-4
	for mode in ["glide", "level"]:
		for V: float in [28.6]:
			var x0 := PackedFloat64Array([0.05, -0.05, 0.3 if mode == "level" else -0.1, 0.0, 0.0, 0.0])
			var base := _solve(V, 0.0, mode, model, x0)
			var x: PackedFloat64Array = base.x
			print("%s V %.1f  alpha %.2f deg  blend %.3f" % [mode, V, rad_to_deg(x[0]), _parts(x, V, 0.0, mode, model, 0, 0).blend])
			for what in ["beta", "aileron(one side)", "rudder"]:
				var p: Dictionary
				var m: Dictionary
				if what == "beta":
					p = _parts(x, V, h, mode, model, 0, 0); m = _parts(x, V, -h, mode, model, 0, 0)
				elif what == "rudder":
					p = _parts(x, V, 0, mode, model, 0, h); m = _parts(x, V, 0, mode, model, 0, -h)
				else:
					p = _parts(x, V, 0, mode, model, h, 0); m = _parts(x, V, 0, mode, model, -h, 0)
				var line := "  d/d %-18s" % what
				for k in ["total", "aero", "oracle", "local", "prop", "other"]:
					line += "  %s Cl %+.5f Cn %+.5f" % [k, (p[k][0] - m[k][0]) / (2 * h), (p[k][1] - m[k][1]) / (2 * h)]
				print(line)
	quit(0)
