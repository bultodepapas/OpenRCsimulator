# P51-11a: flap checks on the runtime equations (research only).
# 1. Trimmed maximum lift coefficient, power off (glide): at each alpha the elevator is solved for zero pitch moment
#    (no rates); CL = lift/(qS) of the whole airplane. Compared as a ratio with NACA MR L-566 (XP-51 flight CLmax:
#    gliding clean 1.5, landing flaps 50 deg 1.6).
# 2. Elevator trim change with flaps at equal CL to XP-51 Table III (120 mph, take-off: flaps 20 deg needs 1.0 deg more up).
# Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/flap_probe.gd
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


var flap_rad := 0.0


func _residual(x: PackedFloat64Array, V: float, beta: float, mode: String, model: Dictionary) -> PackedFloat64Array:
	var gamma := 0.0 if mode == "level" else x[2]
	var s := _state(V, x[0], beta, x[3], gamma)
	var rpm := 0.0
	if mode == "level":
		var u := M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(model.propulsion))
		rpm = Propulsion.steady_rpm(x[2], u, model.propulsion, RHO, 1.0)
	var d := { elevator = x[1], aileron_right = x[4], aileron_left = -x[4], rudder = x[5], flap = flap_rad }
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


func _trimmed_cl(model: Dictionary, V: float, alpha: float) -> Dictionary:
	var de := -0.05
	for it in 40:
		var f := func(e: float) -> float:
			var s := _state(V, alpha, 0.0, 0.0, 0.0)
			s[RB.POS + 2] = -300.0
			var d := { elevator = e, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0, flap = flap_rad }
			return Dynamics.evaluate(s, model, d, 0.0, RHO, M.v3(0, 0, 0), G).derivative[RB.RATE + 1]
		var r: float = f.call(de)
		var h := 1e-6
		var dr: float = (f.call(de + h) - r) / h
		if absf(dr) < 1e-12:
			break
		de -= r / dr
		de = clampf(de, -0.6, 0.6)
		if absf(r) < 1e-9:
			break
	var s2 := _state(V, alpha, 0.0, 0.0, 0.0)
	var d2 := { elevator = de, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0, flap = flap_rad }
	var c: Dictionary = Dynamics.evaluate(s2, model, d2, 0.0, RHO, M.v3(0, 0, 0), G)
	var l: PackedFloat64Array = c.aero_loads
	var lift: float = -l[2] * cos(alpha) + l[0] * sin(alpha)
	var qS: float = 0.5 * RHO * V * V * float(model.reference.S)
	return { cl = lift / qS, de = de }


func _initialize() -> void:
	var path := "res://data/aircraft/p51d_mustang_120.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			path = arg.trim_prefix("--data=")
	var model: Dictionary = AircraftData.load_file(path).model
	var clean_max := 0.0
	print("Trimmed CLmax, power off, V = 20 m/s (alpha sweep 0-24 deg, elevator for zero pitch moment):")
	for flap_deg: float in [0.0, 15.0, 20.0, 45.0, 50.0]:
		flap_rad = deg_to_rad(flap_deg)
		var best := -INF
		var best_a := 0.0
		var best_de := 0.0
		for k in 241:
			var a := deg_to_rad(0.1 * k)
			var t := _trimmed_cl(model, 20.0, a)
			if float(t.cl) > best:
				best = t.cl
				best_a = a
				best_de = t.de
		if flap_deg == 0.0:
			clean_max = best
		print("  flaps %4.1f deg: CLmax_trim %.3f at alpha %.1f deg (elevator %.1f deg); ratio to clean %.3f; 1-g stall %.2f m/s" % [
			flap_deg, best, rad_to_deg(best_a), rad_to_deg(best_de), best / clean_max, sqrt(2.0 * model.mass_kg * G / (RHO * float(model.reference.S) * best))])
	print("  XP-51 flight (MR L-566): gliding clean 1.5, landing flaps 50 deg 1.6 -> ratio 1.067")
	# Trim change at the XP-51 120 mph take-off lift coefficient (7,400 lb, 235.75 sq ft): CL 0.853.
	var cl_ref := 7400.0 * 4.4482216 / (0.5 * 1.225 * pow(120.0 * 0.44704, 2) * 235.75 * 0.09290304)
	var V := sqrt(2.0 * model.mass_kg * G / (RHO * float(model.reference.S) * cl_ref))
	print("Level trim at CL %.3f (V %.2f m/s), power on:" % [cl_ref, V])
	var e0 := 0.0
	for flap_deg: float in [0.0, 15.0, 20.0, 45.0]:
		flap_rad = deg_to_rad(flap_deg)
		var sol := _solve(V, 0.0, "level", model, PackedFloat64Array([0.08, -0.05, 0.3, 0.0, 0.0, 0.0]))
		if flap_deg == 0.0:
			e0 = sol.x[1]
		print("  flaps %4.1f: ok %s alpha %.2f deg elevator %.2f deg (change %+.2f deg, negative = more up) throttle %.3f" % [flap_deg, sol.ok,
			rad_to_deg(sol.x[0]), rad_to_deg(sol.x[1]), rad_to_deg(sol.x[1] - e0), sol.x[2]])
	print("  XP-51 Table III, 120 mph take-off: flaps 20 deg needs 1.0 deg more up elevator")
	# The same comparison at an equal fraction of the clean CLmax (XP-51: 0.853 of gliding 1.5 = 0.57).
	var cl_frac := cl_ref / 1.5 * clean_max
	var Vf := sqrt(2.0 * model.mass_kg * G / (RHO * float(model.reference.S) * cl_frac))
	print("Level trim at equal CL/CLmax %.2f: CL %.3f (V %.2f m/s), power on:" % [cl_ref / 1.5, cl_frac, Vf])
	for flap_deg: float in [0.0, 15.0, 20.0, 45.0]:
		flap_rad = deg_to_rad(flap_deg)
		var sol := _solve(Vf, 0.0, "level", model, PackedFloat64Array([0.05, -0.05, 0.3, 0.0, 0.0, 0.0]))
		if flap_deg == 0.0:
			e0 = sol.x[1]
		print("  flaps %4.1f: ok %s alpha %.2f deg elevator %.2f deg (change %+.2f deg, negative = more up) throttle %.3f" % [flap_deg, sol.ok,
			rad_to_deg(sol.x[0]), rad_to_deg(sol.x[1]), rad_to_deg(sol.x[1] - e0), sol.x[2]])

	print("Glide trim (engine stopped) at the same CL %.3f (V %.2f m/s):" % [cl_frac, Vf])
	for flap_deg: float in [0.0, 15.0, 20.0, 45.0]:
		flap_rad = deg_to_rad(flap_deg)
		var gsol := _solve(Vf, 0.0, "glide", model, PackedFloat64Array([0.05, -0.05, -0.1, 0.0, 0.0, 0.0]))
		if flap_deg == 0.0:
			e0 = gsol.x[1]
		print("  flaps %4.1f: ok %s alpha %.2f deg elevator %.2f deg (change %+.2f deg, negative = more up) glide angle %.2f deg" % [flap_deg, gsol.ok,
			rad_to_deg(gsol.x[0]), rad_to_deg(gsol.x[1]), rad_to_deg(gsol.x[1] - e0), rad_to_deg(gsol.x[2])])
	quit(0)
