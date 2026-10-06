# Flight modes of the simulated airplane (D8a): the real equations (aero + propulsion + rigid body) linearized at a
# level trim, controls and engine frozen, over x = [u, v, w, p, q, r, φ, θ]. 64-bit floats only (guarded).
# Used by tests/test_modes.gd (regression bands) and by validation/sensitivity work (D8b, D10).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Trim := preload("res://physics/trim.gd")
const L := preload("res://physics/linearize.gd")

const LONGITUDINAL := [0, 2, 4, 7] # u, w, q, θ
const LATERAL := [1, 3, 5, 6] # v, p, r, φ


## Returns { ok, message, trim, short_period {f_hz, zeta}, phugoid {f_hz, zeta}, roll_tau, dutch_roll {f_hz, zeta},
## spiral_tau (s; negative = unstable time to e-fold) }.
static func analyze(model: Dictionary, V: float, g := 9.80665) -> Dictionary:
	var t := Trim.solve("level", V, model, g, model.controls.throw_rad)
	if not t.ok:
		return { ok = false, message = "no trim at %.1f m/s: %s" % [V, t.message] }
	var d := { elevator = t.elevator, aileron_right = t.aileron, aileron_left = -t.aileron, rudder = t.rudder }
	var f := func(x: PackedFloat64Array) -> PackedFloat64Array:
		var s := RB.make_state(M.v3(0, 0, -100), M.v3(x[0], x[1], x[2]), M.q_from_euler(0.0, x[7], x[6]), M.v3(x[3], x[4], x[5]))
		var evaluation := Dynamics.evaluate(s, model, d, t.rpm, Air.RHO_SEA_LEVEL, M.v3(0, 0, 0), g)
		var dot: PackedFloat64Array = evaluation.derivative
		var phi := x[6]
		var th := x[7]
		return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 1], dot[RB.VEL + 2], dot[RB.RATE], dot[RB.RATE + 1], dot[RB.RATE + 2],
			x[3] + (x[4] * sin(phi) + x[5] * cos(phi)) * tan(th), x[4] * cos(phi) - x[5] * sin(phi)])
	var s0: PackedFloat64Array = t.state
	var e := M.q_to_euler(s0.slice(RB.ATT, RB.ATT + 4)) # [yaw, pitch, roll]
	var a := L.jacobian(f, PackedFloat64Array([s0[RB.VEL], s0[RB.VEL + 1], s0[RB.VEL + 2], 0.0, 0.0, 0.0, e[2], e[1]]))
	# Keep the historical 4×4 modal estimates as diagonal-block projections of the complete matrix. They
	# discard longitudinal↔lateral couplings; use the full matrix for cross-axis handling work. The custom
	# eigenvalue solver remains limited to these tested 4×4 projections, not the 8×8 matrix.
	var projected := {
		longitudinal = L.submatrix(a, LONGITUDINAL),
		lateral = L.submatrix(a, LATERAL),
	}
	var lon := L.classify(L.eigenvalues(projected.longitudinal))
	var lat := L.classify(L.eigenvalues(projected.lateral))
	if lon.oscillatory.size() != 2 or lat.oscillatory.size() != 1 or lat.real.size() != 2:
		return { ok = false, message = "unexpected mode structure: longitudinal %s, lateral %s" % [lon, lat], trim = t,
			full_jacobian = a, projected_jacobians = projected }
	var hz := func(m: Dictionary) -> Dictionary: return { f_hz = m.wn / TAU, zeta = m.zeta }
	return {
		ok = true, message = "ok", trim = t,
		full_jacobian = a,
		projected_jacobians = projected,
		projection_note = "4×4 modal estimates are diagonal-block projections; cross-axis couplings are omitted",
		short_period = hz.call(lon.oscillatory[0]), phugoid = hz.call(lon.oscillatory[1]),
		roll_tau = -1.0 / lat.real[0], dutch_roll = hz.call(lat.oscillatory[0]), spiral_tau = -1.0 / lat.real[1],
	}
