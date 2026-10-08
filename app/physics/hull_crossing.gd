# CR-01b: a pose-interpolation estimate, NOT continuous collision detection or RK dense output.
# Position is linear and attitude shortest-path nlerp, as in Simulation.interpolated().
extends RefCounted

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const ROUND_OFF: float = 2.842170943040401e-14 # 128 binary64 eps, normalized polynomial units.
const TIE_FRACTION: float = 1e-12 # Numerically simultaneous contacts keep data order.
const UNIT_TOLERANCE: float = 1e-9 # Reject grossly nonunit inputs; session normalizes each step.


class Result:
	extends RefCounted
	var available: bool = false
	var reason: String = "invalid_input"
	var method: String = "position-lerp-shortest-nlerp-v1"
	var fraction: float = 0.0 # Unknown unless available, between previous and detected tick.
	var point_index: int = -1 # Exact model hull order; no stable component identity.
	var position_ned: PackedFloat64Array = PackedFloat64Array()
	var attitude: PackedFloat64Array = PackedFloat64Array()
	var point_ned: PackedFloat64Array = PackedFloat64Array()


static func reconstruct(previous: PackedFloat64Array, current: PackedFloat64Array,
		hull: PackedFloat64Array) -> Result:
	var out: Result = Result.new()
	if not _valid_state(previous) or not _valid_state(current) or hull.is_empty() or hull.size() % 3 != 0:
		return out
	for value in hull:
		if not is_finite(value):
			return out
	var a: PackedFloat64Array = RB._att(previous)
	var end: PackedFloat64Array = RB._att(current)
	var dot: float = 0.0
	for i in 4:
		dot += a[i] * end[i]
	if dot < 0.0:
		for i in 4:
			end[i] = -end[i]
	var b: PackedFloat64Array = PackedFloat64Array()
	for i in 4:
		b.append(end[i]-a[i])
	var n: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	for i in 4:
		n[0] += a[i] * a[i]
		n[1] += 2.0 * a[i] * b[i]
		n[2] += b[i] * b[i]
	var best: float = 2.0
	var selected: int = -1
	for index in range(0, hull.size(), 3):
		var r: PackedFloat64Array = hull.slice(index, index + 3)
		var c: PackedFloat64Array = _polynomial(previous[RB.POS+2], current[RB.POS+2], a, b, n, r)
		for value in c:
			if not is_finite(value):
				out.reason = "nonfinite_reconstruction"
				return out
		if c[0] >= 0.0:
			out.reason = "previous_pose_in_contact"
			return out
		var root: Dictionary = _first_root(c)
		if root.ambiguous:
			out.reason = "near_tangent_or_roundoff"
			return out
		if root.fraction >= 0.0 and root.fraction < best - TIE_FRACTION:
			best = root.fraction
			selected = index / 3
	if selected < 0:
		out.reason = "no_crossing"
		return out
	var position: PackedFloat64Array = PackedFloat64Array()
	var q: PackedFloat64Array = PackedFloat64Array()
	for i in 3:
		position.append(lerpf(previous[RB.POS+i], current[RB.POS+i], best))
	for i in 4:
		q.append(lerpf(a[i], end[i], best))
	q = M.q_normalized(q)
	var point: PackedFloat64Array = M.add(position, M.q_rotate(q, hull.slice(3*selected, 3*selected+3)))
	for value in position + q + point:
		if not is_finite(value):
			out.reason = "nonfinite_reconstruction"
			return out
	var scale: float = maxf(1.0, maxf(absf(position[2]), M.norm(hull.slice(3*selected, 3*selected+3))))
	if not is_finite(scale):
		out.reason = "nonfinite_reconstruction"
		return out
	if absf(point[2]) > 1e-10 * scale:
		out.reason = "pose_residual_too_large"
		return out
	out.available = true
	out.reason = "crossing_estimated"
	out.fraction = best
	out.point_index = selected
	out.position_ned = position
	out.attitude = q
	out.point_ned = point
	return out


# Multiplying point-down by |a+f*b|² yields a cubic. Coefficients ordered f^0..f^3.
static func _polynomial(z0: float, z1: float, a: PackedFloat64Array, b: PackedFloat64Array,
		n: PackedFloat64Array, r: PackedFloat64Array) -> PackedFloat64Array:
	var dz: float = z1-z0
	var h0: float = _rotated_down_numerator(a, r)
	var h2: float = _rotated_down_numerator(b, r)
	var h1: float = 2.0 * ((a[1]*b[3]+b[1]*a[3]-a[0]*b[2]-b[0]*a[2])*r[0]
		+ (a[2]*b[3]+b[2]*a[3]+a[0]*b[1]+b[0]*a[1])*r[1]
		+ (a[0]*b[0]-a[1]*b[1]-a[2]*b[2]+a[3]*b[3])*r[2])
	return PackedFloat64Array([z0*n[0]+h0, z0*n[1]+dz*n[0]+h1, z0*n[2]+dz*n[1]+h2, dz*n[2]])


static func _rotated_down_numerator(q: PackedFloat64Array, r: PackedFloat64Array) -> float:
	return 2.0*(q[1]*q[3]-q[0]*q[2])*r[0] + 2.0*(q[2]*q[3]+q[0]*q[1])*r[1] \
		+ (q[0]*q[0]-q[1]*q[1]-q[2]*q[2]+q[3]*q[3])*r[2]


static func _value(c: PackedFloat64Array, x: float) -> float:
	return ((c[3]*x+c[2])*x+c[1])*x+c[0]


# Partition into monotone cubic intervals using its derivative roots. Fixed subdivision
# alone can miss a narrow enter-and-exit pair whose two endpoint depths are both negative.
static func _first_root(input: PackedFloat64Array) -> Dictionary:
	var c: PackedFloat64Array = input.duplicate()
	var magnitude: float = 0.0
	for value in c:
		magnitude = maxf(magnitude, absf(value))
	if magnitude == 0.0:
		return {fraction = -1.0, ambiguous = true}
	for i in 4:
		c[i] /= magnitude
	var boundaries: PackedFloat64Array = PackedFloat64Array([0.0, 1.0])
	var a: float = 3.0*c[3]
	var b: float = 2.0*c[2]
	var d: float = c[1]
	if a == 0.0:
		if b != 0.0:
			_append_inside(boundaries, -d/b)
	else:
		var discriminant: float = b*b-4.0*a*d
		if discriminant >= 0.0:
			var q: float = -0.5*(b + (1.0 if b >= 0.0 else -1.0)*M.sqrt_(discriminant))
			if q == 0.0:
				_append_inside(boundaries, -b/(2.0*a))
			else:
				_append_inside(boundaries, q/a)
				_append_inside(boundaries, d/q)
		elif absf(discriminant) <= ROUND_OFF*(b*b+absf(4.0*a*d)):
			_append_inside(boundaries, -b/(2.0*a)) # Probe a numerically merged stationary point.
	boundaries.sort()
	var lo: float = 0.0
	var v_lo: float = c[0]
	if absf(v_lo) <= ROUND_OFF:
		return {fraction = -1.0, ambiguous = true}
	for i in range(1, boundaries.size()):
		var hi: float = boundaries[i]
		var v_hi: float = _value(c, hi)
		if hi < 1.0 and absf(v_hi) <= ROUND_OFF:
			return {fraction = -1.0, ambiguous = true}
		if v_lo < 0.0 and v_hi >= 0.0:
			for iteration in 60:
				var mid: float = lo + (hi-lo)*0.5
				if mid == lo or mid == hi:
					break
				if _value(c, mid) >= 0.0:
					hi = mid
				else:
					lo = mid
			return {fraction = hi, ambiguous = false}
		lo = hi
		v_lo = v_hi
	return {fraction = -1.0, ambiguous = false}


static func _append_inside(values: PackedFloat64Array, x: float) -> void:
	if is_finite(x) and x > 0.0 and x < 1.0 and not values.has(x):
		values.append(x)


static func _valid_state(s: PackedFloat64Array) -> bool:
	if s.size() != RB.SIZE:
		return false
	for value in s:
		if not is_finite(value):
			return false
	var q: PackedFloat64Array = RB._att(s)
	var norm_sq: float = 0.0
	for value in q:
		norm_sq += value*value
	return is_finite(norm_sq) and absf(norm_sq-1.0) <= UNIT_TOLERANCE
