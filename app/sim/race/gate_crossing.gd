# DR-25: pure swept rectangular gate geometry (FPV/04 §3), static functions on float64 packed arrays.
# A gate is {c, n, u, v, w, h}: NED centre, unit normal in the allowed travel direction, orthonormal in-plane axes
# and positive half width/height (track.gd prepare()). One straight path piece p0 at t0 -> p1 at t1 is tested:
#   d0 = n·(p0 − c), d1 = n·(p1 − c); a directed crossing needs d0 < 0 and d1 >= 0 (half-open: an endpoint exactly on
#   the plane counts for the piece that ends there, never for the next piece that starts at d0 = 0); a piece starting on
#   the plane, a coplanar piece and wrong-way travel never score; lambda = −d0/(d1 − d0), q = p0 + lambda(p1 − p0),
#   t = t0 + lambda(t1 − t0). With per-axis in-plane uncertainty eps_u, eps_v the crossing is
#   inside     iff |u·(q−c)| + eps_u <  w and |v·(q−c)| + eps_v <  h,
#   outside    iff |u·(q−c)| − eps_u >= w or  |v·(q−c)| − eps_v >= h,
#   unresolved otherwise. With eps = 0 an exact aperture-edge point is outside (strict edge rule).
# This is exact only for the stated straight segment. Curved-path evidence enters as eps (chord_bound_m) under a declared
# acceleration envelope; it does not prove that a path did not cross and return between endpoints.
# A36 R5-F02: eps bounds the same-time distance between the path and its chord, not the distance between their plane
# intersections. A residual r shifts the crossing time by −r_n/v_n, so the aperture coordinate moves by
# r_u − (v_u/v_n)·r_n; with |r| <= eps, |Δu| <= eps·sqrt(1 + (v_u/v_n)²) (Cauchy–Schwarz), likewise for v. The chord's own
# velocity ratios (u·Δp)/(n·Δp) and (v·Δp)/(n·Δp) project eps per axis; a crossing perpendicular to the plane keeps eps.
# Does not claim federation timing compliance. 64-bit floats only.
extends RefCounted

const STATUS_NONE := "none"
const STATUS_INSIDE := "inside"
const STATUS_OUTSIDE := "outside"
const STATUS_UNRESOLVED := "unresolved"


## Linear-chord deviation bound A·dt²/8 (m) of a path whose acceleration normal to the chord is bounded by A (m/s²).
static func chord_bound_m(acceleration_bound: float, dt: float) -> float:
	return acceleration_bound * dt * dt / 8.0


## One gate against one piece. Returns {crossed, direction_ok, status, time_s, point, u_m, v_m, lambda, normal_speed_mps,
## epsilon_u_m, epsilon_v_m}; epsilon_m is the chord deviation bound, projected per aperture axis as described above.
## crossed: the piece crosses the plane under the half-open convention in either direction; direction_ok: it does so in
## the allowed direction (d0 < 0 <= d1). A wrong-way crossing (d0 > 0 >= d1) is reported with direction_ok = false and
## its diagnostic point; only direction_ok crossings may ever score. u_m/v_m are signed in-plane coordinates of q.
## Malformed input (non-finite values, t1 <= t0, negative eps) returns status "none".
static func crossing(gate: Dictionary, p0: PackedFloat64Array, t0: float, p1: PackedFloat64Array, t1: float,
		epsilon_m: float) -> Dictionary:
	var result := {crossed = false, direction_ok = false, status = STATUS_NONE, time_s = 0.0, point = PackedFloat64Array(),
		u_m = 0.0, v_m = 0.0, lambda = 0.0, normal_speed_mps = 0.0, epsilon_u_m = 0.0, epsilon_v_m = 0.0}
	if p0.size() != 3 or p1.size() != 3 or not is_finite(t0) or not is_finite(t1) or not (t1 > t0) \
			or not is_finite(epsilon_m) or epsilon_m < 0.0:
		return result
	var c: PackedFloat64Array = gate.c
	var n: PackedFloat64Array = gate.n
	var d0: float = _dot_offset(n, p0, c)
	var d1: float = _dot_offset(n, p1, c)
	if not is_finite(d0) or not is_finite(d1):
		return result
	var forward: bool = d0 < 0.0 and d1 >= 0.0
	var backward: bool = d0 > 0.0 and d1 <= 0.0
	if not forward and not backward:
		return result
	var lambda: float = -d0 / (d1 - d0)
	var q := PackedFloat64Array([p0[0] + lambda * (p1[0] - p0[0]), p0[1] + lambda * (p1[1] - p0[1]),
		p0[2] + lambda * (p1[2] - p0[2])])
	var u_m: float = _dot_offset(gate.u, q, c)
	var v_m: float = _dot_offset(gate.v, q, c)
	result.crossed = true
	result.direction_ok = forward
	var dn: float = d1 - d0
	var ratio_u: float = (_dot_offset(gate.u, p1, c) - _dot_offset(gate.u, p0, c)) / dn
	var ratio_v: float = (_dot_offset(gate.v, p1, c) - _dot_offset(gate.v, p0, c)) / dn
	var epsilon_u: float = epsilon_m * sqrt(1.0 + ratio_u * ratio_u)
	var epsilon_v: float = epsilon_m * sqrt(1.0 + ratio_v * ratio_v)
	result.status = classify_axes(absf(u_m), absf(v_m), float(gate.w), float(gate.h), epsilon_u, epsilon_v) 		if is_finite(epsilon_u) and is_finite(epsilon_v) else STATUS_UNRESOLVED
	result.epsilon_u_m = epsilon_u
	result.epsilon_v_m = epsilon_v
	result.time_s = t0 + lambda * (t1 - t0)
	result.point = q
	result.u_m = u_m
	result.v_m = v_m
	result.lambda = lambda
	result.normal_speed_mps = (d1 - d0) / (t1 - t0)
	return result


## Aperture classification of an in-plane point |u|, |v| with uncertainty eps on both axes.
static func classify(abs_u: float, abs_v: float, w: float, h: float, epsilon_m: float) -> String:
	return classify_axes(abs_u, abs_v, w, h, epsilon_m, epsilon_m)


## Aperture classification with separate in-plane uncertainty per axis.
static func classify_axes(abs_u: float, abs_v: float, w: float, h: float, epsilon_u: float, epsilon_v: float) -> String:
	if abs_u + epsilon_u < w and abs_v + epsilon_v < h:
		return STATUS_INSIDE
	if abs_u - epsilon_u >= w or abs_v - epsilon_v >= h:
		return STATUS_OUTSIDE
	return STATUS_UNRESOLVED


static func _dot_offset(axis: PackedFloat64Array, p: PackedFloat64Array, c: PackedFloat64Array) -> float:
	return axis[0] * (p[0] - c[0]) + axis[1] * (p[1] - c[1]) + axis[2] * (p[2] - c[2])
