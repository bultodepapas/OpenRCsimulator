# P51-26: the legacy (centroid) slipstream tail law evaluated over N spanwise strips per tail piece instead of one point.
# N = 1 reproduces Slipstream.loads exactly (checked); N -> large is the same law integrated over the immersed span.
# Prints the slipstream's roll/yaw derivatives per beta and per rudder at the level beta = 0 trim, in qSb units.
# Research only; no runtime change. Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/strip_swirl_probe.gd
#   [-- --data=<path> --speeds=28.6,45]
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


const Slipstream := preload("res://physics/slipstream.gd")
const GL := {
	3: [[-0.774596669241483, 0.0, 0.774596669241483], [0.555555555555556, 0.888888888888889, 0.555555555555556]],
	5: [[-0.906179845938664, -0.538469310105683, 0.0, 0.538469310105683, 0.906179845938664],
		[0.236926885056189, 0.478628670499366, 0.568888888888889, 0.478628670499366, 0.236926885056189]],
	8: [[-0.960289856497536, -0.796666477413627, -0.525532409916329, -0.183434642495650, 0.183434642495650, 0.525532409916329, 0.796666477413627, 0.960289856497536],
		[0.101228536290376, 0.222381034453374, 0.313706645877887, 0.362683783378362, 0.362683783378362, 0.313706645877887, 0.222381034453374, 0.101228536290376]],
}


func _strip_loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float, n: int) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	var out := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	if rpm < Propulsion.STOPPED_RPM:
		return out
	var v: PackedFloat64Array = air.v_air
	var tq := Propulsion.thrust_torque(v, rpm, prop, RHO)
	var w: Dictionary = Slipstream.wake(v, tq[0], tq[1], prop, RHO)
	var ss: Dictionary = prop.slipstream
	var ax := Propulsion.axis(prop)
	var wash := M.v3(ax[0] * w.dv, ax[1] * w.dv, ax[2] * w.dv)
	var speed := sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	var hub: PackedFloat64Array = ss.hub
	var lean_ratio: float = minf(speed / (w.u + w.w), 1.0)
	var cg: PackedFloat64Array = model.cg_le
	var surfaces: Dictionary = model.surfaces
	var wing_cl: float = Aero.wing_wake_velocity(state, air, d, model) if surfaces.horizontal.has("free_slope") else 0.0
	var p := state[RB.RATE]
	var q := state[RB.RATE + 1]
	var r := state[RB.RATE + 2]
	for piece: Dictionary in ss.pieces:
		var root: PackedFloat64Array = piece.root
		var dist: float = root[0] - hub[0]
		var shaft_scale: float = dist / -ax[0]
		var c0_ := hub[0] - ax[0] * shaft_scale
		var c1_ := hub[1] + ax[1] * shaft_scale
		var c2_ := hub[2] - ax[2] * shaft_scale
		var lean: float = lean_ratio * dist / speed
		c1_ -= v[1] * lean
		c2_ += v[2] * lean * float(ss.vertical_drift)
		var e: PackedFloat64Array = piece.span_dir
		var along: float = (root[0] - c0_) * e[0] + (root[1] - c1_) * e[1] + (root[2] - c2_) * e[2]
		var p0: float = root[0] - c0_ - e[0] * along
		var p1: float = root[1] - c1_ - e[1] * along
		var p2: float = root[2] - c2_ - e[2] * along
		var d2: float = p0 * p0 + p1 * p1 + p2 * p2
		if d2 >= w.rs * w.rs:
			continue
		var half := sqrt(w.rs * w.rs - d2)
		var span: float = piece.span
		var a := clampf(-along - half, 0.0, span)
		var b := clampf(-along + half, 0.0, span)
		if b <= a:
			continue
		var c0: float = piece.chords[0]
		var slope: float = (piece.chords[1] - c0) / span
		var full: float = c0 * span + 0.5 * slope * span * span
		var tail: Dictionary = surfaces[piece.surface]
		var tail_pos: PackedFloat64Array = tail.position
		var vertical: bool = piece.surface == "vertical"
		# Nodes: n > 0 uniform strips (area, centroid); n < 0 Gauss-Legendre with -n nodes on each sub-interval split
		# where the span line crosses the vortex core radius (the only interior kink of the swirl profile).
		var nodes: Array = []
		if n > 0:
			for k in n:
				var sa := a + (b - a) * k / n
				var sb := a + (b - a) * (k + 1) / n
				var area_k: float = (c0 * sb + 0.5 * slope * sb * sb) - (c0 * sa + 0.5 * slope * sa * sa)
				if area_k > 0.0:
					nodes.append([area_k, ((0.5 * c0 * sb * sb + slope * sb * sb * sb / 3.0) - (0.5 * c0 * sa * sa + slope * sa * sa * sa / 3.0)) / area_k])
		else:
			var cuts := [a, b]
			if w.core * w.core > d2:
				var hc := sqrt(w.core * w.core - d2)
				for c_: float in [-along - hc, -along + hc]:
					if c_ > a and c_ < b:
						cuts.append(c_)
			cuts.sort()
			var gx: Array = GL[5 if n == -100 else -n][0]
			var gw: Array = GL[5 if n == -100 else -n][1]
			for j in cuts.size() - 1:
				var lo: float = cuts[j]
				var hi: float = cuts[j + 1]
				for i in gx.size():
					var sx: float = 0.5 * (lo + hi) + 0.5 * (hi - lo) * float(gx[i])
					nodes.append([(c0 + slope * sx) * 0.5 * (hi - lo) * float(gw[i]), sx])
		var mean_sw := PackedFloat64Array()
		if n == -100:
			# Area-weighted mean swirl velocity over the immersed span (GL5 split at the core), applied once at the
			# legacy area centroid: exact for a tail law linear in the local crossflow.
			var sw_sum := M.v3(0, 0, 0)
			var a_sum := 0.0
			for node: Array in nodes:
				var ptn := M.v3(root[0] + e[0] * float(node[1]), root[1] + e[1] * float(node[1]), root[2] + e[2] * float(node[1]))
				var rbn := M.v3(-(ptn[0] - c0_), ptn[1] - c1_, -(ptn[2] - c2_))
				var pj: float = M.dot(rbn, ax)
				rbn = M.v3(rbn[0] - ax[0] * pj, rbn[1] - ax[1] * pj, rbn[2] - ax[2] * pj)
				var rr: float = maxf(sqrt(M.dot(rbn, rbn)), w.core)
				var scn: float = w.swirl / (rr * rr) * float(node[0])
				sw_sum = M.v3(sw_sum[0] + (ax[1] * rbn[2] - ax[2] * rbn[1]) * scn, sw_sum[1] + (ax[2] * rbn[0] - ax[0] * rbn[2]) * scn,
					sw_sum[2] + (ax[0] * rbn[1] - ax[1] * rbn[0]) * scn)
				a_sum += float(node[0])
			mean_sw = M.v3(sw_sum[0] / a_sum, sw_sum[1] / a_sum, sw_sum[2] / a_sum)
			var a_tot: float = (c0 * b + 0.5 * slope * b * b) - (c0 * a + 0.5 * slope * a * a)
			nodes = [[a_tot, ((0.5 * c0 * b * b + slope * b * b * b / 3.0) - (0.5 * c0 * a * a + slope * a * a * a / 3.0)) / a_tot]]
		for node: Array in nodes:
			var area_s: float = node[0]
			var eta: float = node[1]
			var pt := M.v3(root[0] + e[0] * eta, root[1] + e[1] * eta, root[2] + e[2] * eta)
			var rb := M.v3(-(pt[0] - c0_), pt[1] - c1_, -(pt[2] - c2_))
			var proj: float = M.dot(rb, ax)
			rb = M.v3(rb[0] - ax[0] * proj, rb[1] - ax[1] * proj, rb[2] - ax[2] * proj)
			var radius: float = maxf(sqrt(M.dot(rb, rb)), w.core)
			var sc: float = w.swirl / (radius * radius)
			var sw := M.v3((ax[1] * rb[2] - ax[2] * rb[1]) * sc, (ax[2] * rb[0] - ax[0] * rb[2]) * sc, (ax[0] * rb[1] - ax[1] * rb[0]) * sc)
			if not mean_sw.is_empty():
				sw = mean_sw
			var area: float = float(piece.area) * area_s / full
			var arm := M.v3(-(tail_pos[0] - cg[0]), tail_pos[1] - cg[1] + (pt[1] - tail_pos[1]), -(tail_pos[2] - cg[2]) - (pt[2] - tail_pos[2]))
			var ra := M.v3(q * arm[2] - r * arm[1], r * arm[0] - p * arm[2], p * arm[1] - q * arm[0])
			var free := Aero._tail_surface_from_flow(M.v3(v[0] + ra[0], v[1] + ra[1], v[2] + ra[2]), arm, d, tail, surfaces, area, vertical, RHO, wing_cl)
			var washed := Aero._tail_surface_from_flow(M.v3(v[0] + (wash[0] - sw[0]) + ra[0], v[1] + (wash[1] - sw[1]) + ra[1],
				v[2] + (wash[2] - sw[2]) + ra[2]), arm, d, tail, surfaces, area, vertical, RHO, wing_cl)
			for i in 6:
				out[i] += washed[i] - free[i]
	return out


func _eval(x: PackedFloat64Array, V: float, beta: float, model: Dictionary, dr: float, n: int) -> PackedFloat64Array:
	var s := _state(V, x[0], beta, x[3], 0.0)
	var u := M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(model.propulsion))
	var rpm := Propulsion.steady_rpm(x[2], u, model.propulsion, RHO, 1.0)
	var d := { elevator = x[1], aileron_right = x[4], aileron_left = -x[4], rudder = x[5] + dr }
	var air := Air.compute(s, M.v3(0, 0, 0), RHO)
	var qsb: float = air.qbar * float(model.reference.S) * float(model.reference.b)
	if n == 0:
		var l := Slipstream.loads(s, air, d, model, rpm, RHO)
		return PackedFloat64Array([l[3] / qsb, l[5] / qsb])
	var l2 := _strip_loads(s, air, d, model, rpm, n)
	return PackedFloat64Array([l2[3] / qsb, l2[5] / qsb])


func _initialize() -> void:
	var path := "res://data/aircraft/p51d_mustang_120.json"
	var speeds := [28.6, 45.0]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			path = arg.trim_prefix("--data=")
		elif arg.begins_with("--speeds="):
			speeds = Array(arg.trim_prefix("--speeds=").split(",")).map(func(t): return float(t))
	var model: Dictionary = AircraftData.load_file(path).model
	var h := 1e-4
	for V: float in speeds:
		var base := _solve(V, 0.0, "level", model, PackedFloat64Array([0.05, -0.05, 0.3, 0.0, 0.0, 0.0]))
		var x: PackedFloat64Array = base.x
		var e0 := _eval(x, V, 0.0, model, 0.0, 0)
		var e1 := _eval(x, V, 0.0, model, 0.0, 1)
		print("level V %.1f (solved %s): runtime vs 1-strip difference Cl %s Cn %s" % [V, base.ok,
			String.num_scientific(e0[0] - e1[0]), String.num_scientific(e0[1] - e1[1])])
		for n: int in [0, 1024, -5, -100]:
			var bp := _eval(x, V, h, model, 0.0, n)
			var bm := _eval(x, V, -h, model, 0.0, n)
			var rp := _eval(x, V, 0.0, model, h, n)
			var rm := _eval(x, V, 0.0, model, -h, n)
			var z := _eval(x, V, 0.0, model, 0.0, n)
			print("  %-8s slipstream dCl/dbeta %+.5f dCn/dbeta %+.5f  dCl/drudder %+.5f dCn/drudder %+.5f  trim Cl %+.5f Cn %+.5f" % [
				"runtime" if n == 0 else ("%d strip" % n if n > 0 else ("mean-swirl" if n == -100 else "GL%d/cut" % -n)), (bp[0] - bm[0]) / (2 * h), (bp[1] - bm[1]) / (2 * h),
				(rp[0] - rm[0]) / (2 * h), (rp[1] - rm[1]) / (2 * h), z[0], z[1]])
	quit(0)
