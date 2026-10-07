# Air data: what the airplane "feels" from the airflow. 64-bit floats only (guarded).
# Wind is a world-frame (NED) air velocity; air-relative velocity = body velocity − wind (in body axes).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

## ISA sea-level density. Altitude changes below ~500 m alter it by < 5 %; revisit with weather/altitude settings.
const RHO_SEA_LEVEL := 1.225


## Returns { v_air: [u, v, w] body (m/s), V (m/s), alpha (rad), beta (rad), qbar (Pa) }.
## Finite for every state, including zero airspeed (alpha = beta = 0 there).
static func compute(s: PackedFloat64Array, wind_ned: PackedFloat64Array, rho := RHO_SEA_LEVEL) -> Dictionary:
	# H15: M.q_rotate(M.q_conj(q), wind_ned) in scalars, same operation order (tests/attached_flow_reference.gd):
	# with u = conj vector part, t = 2·(u × wind) and wind_body = (wind + t·w) + u × t.
	var qw: float = s[RB.ATT]
	var ux: float = -s[RB.ATT + 1]
	var uy: float = -s[RB.ATT + 2]
	var uz: float = -s[RB.ATT + 3]
	var wx: float = wind_ned[0]
	var wy: float = wind_ned[1]
	var wz: float = wind_ned[2]
	var tx: float = (uy * wz - uz * wy) * 2.0
	var ty: float = (uz * wx - ux * wz) * 2.0
	var tz: float = (ux * wy - uy * wx) * 2.0
	var u := s[RB.VEL] - ((wx + tx * qw) + (uy * tz - uz * ty))
	var v := s[RB.VEL + 1] - ((wy + ty * qw) + (uz * tx - ux * tz))
	var w := s[RB.VEL + 2] - ((wz + tz * qw) + (ux * ty - uy * tx))
	var speed := M.sqrt_(u * u + v * v + w * w)
	return {
		v_air = M.v3(u, v, w),
		V = speed,
		alpha = M.atan2_(w, u),
		# atan2 form of asin(v / V): identical for V > 0, and well defined at V = 0.
		beta = M.atan2_(v, M.sqrt_(u * u + w * w)),
		qbar = 0.5 * rho * speed * speed,
	}
