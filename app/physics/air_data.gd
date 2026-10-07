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
	var q := M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var wind_body := M.q_rotate(M.q_conj(q), wind_ned)
	var u := s[RB.VEL] - wind_body[0]
	var v := s[RB.VEL + 1] - wind_body[1]
	var w := s[RB.VEL + 2] - wind_body[2]
	var speed := M.sqrt_(u * u + v * v + w * w)
	return {
		v_air = M.v3(u, v, w),
		V = speed,
		alpha = M.atan2_(w, u),
		# atan2 form of asin(v / V): identical for V > 0, and well defined at V = 0.
		beta = M.atan2_(v, M.sqrt_(u * u + w * w)),
		qbar = 0.5 * rho * speed * speed,
	}
