# HELI-04: isolated mean inflow law shared with multirotors. Float64 only.
# Johnson NASA/TP-2005-213477, Tables 3/4 (printed pp. 23/24).
# z is climb along the positive thrust axis; x is nonnegative crossflow,
# both divided by ideal hover velocity. No stochastic forcing or cached state.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const ROOT_PASSES: int = 48
const NEWTON_PASSES: int = 12
const MAX_RATIO: float = 1.0e6


static func normalized(z: float, x: float, instability: float = 1.0, loss: float = 1.0) -> Dictionary:
	if not _finite([z, x, instability, loss]) or x < 0.0 or absf(z) > MAX_RATIO or x > MAX_RATIO \
		or instability < 0.0 or instability > 1.0 or loss < 1.0:
		return {"ok": false}
	var base: PackedFloat64Array = _baseline(z, x)
	var delta: float = 0.0
	if instability > 0.0 and z < -0.2 and x < 0.95:
		var u: float = x / 0.95
		var edge: float = maxf(0.0, 1.0 - u * u)
		var n: float = -0.975 + 0.525 * M.pow_(edge, 0.2)
		var peak: float = -0.975 - 0.525 * M.pow_(edge, 1.5)
		var end: float = -2.0 + (peak + 1.5)
		if z > end:
			var fade: float = M.sqrt_(maxf(0.0, 1.0 - M.pow_(u, 6.0)))
			var bn: PackedFloat64Array = _baseline(n, x)
			var bp: PackedFloat64Array = _baseline(peak, x)
			var dn: float = (0.85 - (-0.45 + _momentum(-0.45, x, false)[0])) * fade
			var dp: float = (1.25 - (-1.5 + _momentum(-1.5, x, false)[0])) * fade
			if z >= n:
				delta = _hermite(z, n, -0.2, dn, 0.0, -(1.0 + bn[1]), 0.0)
			elif z >= peak:
				delta = _hermite(z, peak, n, dp, dn, -(1.0 + bp[1]), -(1.0 + bn[1]))
			else:
				# Table 3 prints D here; the X-to-E segment described on p. 15
				# requires E. Its constant coefficient is zero, slope at E free.
				delta = _zero_constant(z, peak, end, dp, -(1.0 + bp[1]), 0.0)[0]
	var value: float = loss * (base[0] + instability * delta)
	if not is_finite(value) or value < 0.0:
		return {"ok": false}
	return {"ok": true, "ratio": value}


# Signed velocity is along the wake direction for positive reference thrust.
# climb is along the positive reference thrust axis; reverse thrust mirrors it.
# height_over_radius=-1 disables ground effect. A nonnegative height means the
# caller established that the downstream wake intersects terrain. Thrust sign
# alone cannot establish that geometry (inverted lift can have negative T).
static func target(thrust: float, density: float, radius: float, climb: float, crossflow: float,
		height_over_radius: float = -1.0, loss: float = 1.0, instability: float = 1.0) -> Dictionary:
	if not _finite([thrust, density, radius, climb, crossflow, height_over_radius, loss, instability]) \
		or density <= 0.0 or radius <= 0.0 or crossflow < 0.0 or loss < 1.0 \
		or instability < 0.0 or instability > 1.0 or (height_over_radius < 0.0 and height_over_radius != -1.0):
		return {"ok": false}
	var factor: float = ground_factor(height_over_radius) if thrust != 0.0 else 1.0
	if thrust == 0.0:
		return {"ok": true, "velocity": 0.0, "hover": 0.0, "ground_factor": factor}
	var hover: float = M.sqrt_(absf(thrust) / (2.0 * density * PI * radius * radius))
	if not is_finite(hover) or hover <= 0.0:
		return {"ok": false}
	var sense: float = 1.0 if thrust > 0.0 else -1.0
	var result: Dictionary = normalized(sense * climb / hover, crossflow / hover, instability, loss)
	if not result.ok:
		return result
	var velocity: float = sense * hover * result.ratio * factor
	if not is_finite(velocity):
		return {"ok": false}
	return {"ok": true, "velocity": velocity, "hover": hover, "ground_factor": factor}


# Applied inflow multiplier: normalize Hayden's empirical intercept so the
# far-field limit is unity, and clamp the near-ground domain to z/R >= 0.5.
static func ground_factor(height_over_radius: float) -> float:
	if not is_finite(height_over_radius) or (height_over_radius < 0.0 and height_over_radius != -1.0):
		return NAN
	if height_over_radius == -1.0:
		return 1.0
	var ratio: float = 2.0 / maxf(0.5, height_over_radius)
	return 0.9926 / (0.9926 + 0.03794 * ratio * ratio)


# Zeroth-harmonic lag, separate from the equilibrium mean-inflow law.
# Caller owns lambda as RK state; floor is a declared positive model parameter.
static func derivative(lambda: float, lambda_target: float, omega: float, lambda_effective: float,
		lambda_floor: float = 0.001) -> Dictionary:
	if not _finite([lambda, lambda_target, omega, lambda_effective, lambda_floor]) \
		or omega < 0.0 or lambda_effective < 0.0 or lambda_floor <= 0.0:
		return {"ok": false}
	if omega == 0.0:
		return {"ok": true, "rate": 0.0, "tau": INF}
	var tau: float = 0.849 / (4.0 * maxf(lambda_effective, lambda_floor) * omega)
	var rate: float = (lambda_target - lambda) / tau
	if not is_finite(tau) or tau <= 0.0 or not is_finite(rate):
		return {"ok": false}
	return {"ok": true, "rate": rate, "tau": tau}


static func _baseline(z: float, x: float) -> PackedFloat64Array:
	if z >= 0.0 or x >= 0.75:
		return _momentum(z, x, z < -2.0)
	var u: float = x / 0.75
	var a: float = -1.5 + 0.2 * u * u
	var b: float = -2.1 + 0.2 * u * u
	if u > 0.5:
		b += 0.7 * (a - b) * M.pow_(2.0 * u - 1.0, 3.0)
	if z >= a:
		return _momentum(z, x, false)
	if z <= b:
		return _momentum(z, x, true)
	var va: PackedFloat64Array = _momentum(a, x, false)
	var vb: PackedFloat64Array = _momentum(b, x, true)
	return _zero_constant(z, a, b, va[0], va[1], vb[0])


# Bracket the physical root of v*sqrt(x^2+(z+v)^2)=1. The derivative's
# stationary points delimit the normal (largest) and windmill (smallest) roots.
# Axial branches have cancellation-safe closed forms. Crossflow uses bounded,
# bracketed Newton iterations, retaining fixed-pass bisection as the fallback.
static func _momentum(z: float, x: float, windmill: bool) -> PackedFloat64Array:
	if x == 0.0:
		var root: float
		var slope: float
		if windmill and z < -2.0:
			var d: float = M.sqrt_(z * z - 4.0)
			root = 2.0 / (-z + d)
			slope = -0.5 - 0.5 * z / d
		else:
			var d: float = M.sqrt_(z * z + 4.0)
			root = 2.0 / (z + d) if z >= 0.0 else 0.5 * (-z + d)
			slope = -0.5 + 0.5 * z / d
		return PackedFloat64Array([root, slope])
	var lo: float = 0.0
	var hi: float = absf(z) + 2.0
	# Scale the bracket to the small root in deep windmill flight. A bracket
	# of order |z| loses relative accuracy when v is of order 1/|z|.
	if windmill and z < -2.0:
		hi = 2.0 / M.sqrt_(x * x + z * z)
	var disc: float = z * z - 8.0 * x * x
	if z < 0.0 and disc > 0.0:
		var d: float = M.sqrt_(disc)
		var turn_a: float = (-3.0 * z - d) / 4.0
		var turn_b: float = (-3.0 * z + d) / 4.0
		if windmill and _residual(turn_a, z, x) >= 0.0:
			hi = minf(hi, turn_a)
		elif not windmill and _residual(turn_b, z, x) <= 0.0:
			lo = turn_b
	var v: float = 0.5 * (lo + hi) if lo > 0.0 else minf(hi, 1.0 / M.sqrt_(1.0 + x * x + z * z))
	var converged: bool = false
	for _pass: int in range(NEWTON_PASSES):
		var flow: float = M.sqrt_(x * x + (z + v) * (z + v))
		var residual: float = v * flow - 1.0
		if absf(residual) <= 1e-13:
			converged = true
			break
		if residual > 0.0:
			hi = v
		else:
			lo = v
		var gradient: float = flow + v * (z + v) / flow
		var next: float = v - residual / gradient if gradient > 0.0 else NAN
		v = next if is_finite(next) and next > lo and next < hi else 0.5 * (lo + hi)
	if not converged:
		for _pass: int in range(ROOT_PASSES):
			var mid: float = 0.5 * (lo + hi)
			if _residual(mid, z, x) > 0.0:
				hi = mid
			else:
				lo = mid
		v = 0.5 * (lo + hi)
	var den: float = x * x + (z + v) * (z + 2.0 * v)
	var slope: float = -v * (z + v) / den
	return PackedFloat64Array([v, slope])


static func _residual(v: float, z: float, x: float) -> float:
	return v * M.sqrt_(x * x + (z + v) * (z + v)) - 1.0


# A cubic with no constant term, value/slope at a and value at b.
static func _zero_constant(z: float, a: float, b: float, va: float, da: float, vb: float) -> PackedFloat64Array:
	var qa: float = va / a
	var dqa: float = (da - qa) / a
	var h: float = b - a
	var d: float = (vb / b - qa - dqa * h) / (h * h)
	var c: float = dqa - 2.0 * d * a
	var linear: float = qa - c * a - d * a * a
	return PackedFloat64Array([z * (linear + z * (c + z * d)), linear + z * (2.0 * c + 3.0 * z * d)])


static func _hermite(z: float, a: float, b: float, va: float, vb: float, da: float, db: float) -> float:
	var h: float = b - a
	var t: float = (z - a) / h
	var t2: float = t * t
	var t3: float = t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * va + (t3 - 2.0 * t2 + t) * h * da \
		+ (-2.0 * t3 + 3.0 * t2) * vb + (t3 - t2) * h * db


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
