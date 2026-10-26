# EL2a-P2: proposals only; the owning event solver retains state and acceptance guards.
extends RefCounted


## Positive lower / nonpositive upper residual. Normalization avoids residual subtraction
## overflow. The endpoint gap can bracket a near-exact secant root on the next trial.
## After an interpolation retains more than half the interval, the caller MUST bisect.
## NAN means no valid representable interior proposal; it is never an accepted root.
static func propose(lo: float, hi: float, value_lo: float, value_hi: float,
		time_tolerance: float, bisect: bool) -> float:
	if not is_finite(lo) or not is_finite(hi) or lo < 0.0 or hi <= lo \
			or not is_finite(value_lo) or value_lo <= 0.0 \
			or not is_finite(value_hi) or value_hi > 0.0 \
			or not is_finite(time_tolerance) or time_tolerance <= 0.0:
		return NAN
	var width: float = hi - lo
	var midpoint: float = lo + 0.5 * width
	if midpoint <= lo or midpoint >= hi:
		return NAN
	if bisect:
		return midpoint
	var scale: float = maxf(value_lo, -value_hi)
	var positive: float = value_lo / scale
	var negative: float = -value_hi / scale
	var fraction: float = positive / (positive + negative)
	var gap: float = minf(0.5 * time_tolerance, 0.25 * width)
	var proposed: float = clampf(lo + fraction * width, lo + gap, hi - gap)
	return proposed if is_finite(proposed) and proposed > lo and proposed < hi else midpoint
