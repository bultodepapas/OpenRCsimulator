## A36 R6-G01: admission bound for a tabulated Ct/Cp propeller. With T = rho n^2 D^4 Ct, shaft power
## P = rho n^3 D^5 Cp and J = V/(nD), the steady axial energy balance P - T V >= 0 is Cp(J) - J Ct(J) >= 0: the shaft
## supplies at least the thrust work (propeller branch, efficiency J Ct/Cp <= 1), and a windmilling branch (Ct, Cp < 0)
## extracts at most the work the air does on the disk. This is a necessary condition, not a calibration.
##
## The bound is certified exactly on the runtime law, Propulsion.coefficient (piecewise-linear rows, linear tail clamped
## at its floor), over every J >= 0 including the extrapolated tail. Between merged breakpoints (rows of both tables and
## each tail's floor kink) Ct = aJ + b and Cp = cJ + d are linear, so g(J) = Cp - J Ct = -aJ^2 + (c - b)J + d is checked
## at both ends and at its stationary point (an interior minimum only when a < 0, since g'' = -2a). The final unbounded piece must not decrease
## without limit. Endpoint-only checks are insufficient: two passing rows can bracket a failing interior.
extends RefCounted

const Propulsion := preload("res://physics/propulsion.gd")

## Absolute coefficient tolerance for authored rounding; far below any stock margin (smallest stock min g ~ 4e-3).
const TOLERANCE := 1.0e-9


## {ok, j, margin, efficiency}: margin is the minimum of Cp - J Ct over J >= 0 (-INF for an unbounded decrease, with j
## the tail start); efficiency is J Ct / Cp at that point when Cp > 0, else NAN.
static func check(ct: PackedFloat64Array, cp: PackedFloat64Array, cp_floor: float) -> Dictionary:
	var breaks: Array[float] = [0.0]
	for table: PackedFloat64Array in [ct, cp]:
		for i in range(2, table.size(), 2):
			breaks.append(table[i])
	var ct_kink := _tail_kink(ct, Propulsion.CT_FLOOR)
	var cp_kink := _tail_kink(cp, cp_floor)
	if is_finite(ct_kink):
		breaks.append(ct_kink)
	if is_finite(cp_kink):
		breaks.append(cp_kink)
	breaks.sort()
	var worst := INF
	var worst_j := 0.0
	var previous := NAN
	for j: float in breaks:
		if j == previous:
			continue
		if is_finite(previous):
			for candidate: float in _interval_candidates(ct, cp, cp_floor, previous, j):
				var margin := _margin(ct, cp, cp_floor, candidate)
				if margin < worst:
					worst = margin
					worst_j = candidate
		previous = j
	# The last breakpoint starts an unbounded piece where both coefficients are linear (or clamped constant).
	var tail := previous
	var margin_tail := _margin(ct, cp, cp_floor, tail)
	if margin_tail < worst:
		worst = margin_tail
		worst_j = tail
	var a := Propulsion.coefficient(ct, tail + 1.0, Propulsion.CT_FLOOR) - Propulsion.coefficient(ct, tail, Propulsion.CT_FLOOR)
	var b := Propulsion.coefficient(ct, tail, Propulsion.CT_FLOOR) - a * tail
	var c := Propulsion.coefficient(cp, tail + 1.0, cp_floor) - Propulsion.coefficient(cp, tail, cp_floor)
	if a > 0.0 or (a == 0.0 and c - b < 0.0):
		worst = -INF
		worst_j = tail
	elif a < 0.0:
		var stationary := (c - b) / (2.0 * a)
		if stationary > tail:
			var margin_stationary := _margin(ct, cp, cp_floor, stationary)
			if margin_stationary < worst:
				worst = margin_stationary
				worst_j = stationary
	var cp_at := Propulsion.coefficient(cp, worst_j, cp_floor)
	return {ok = is_finite(worst) and worst >= -TOLERANCE, j = worst_j, margin = worst,
		efficiency = worst_j * Propulsion.coefficient(ct, worst_j, Propulsion.CT_FLOOR) / cp_at if cp_at > 0.0 else NAN}


## Admission message for a failed check, or "" when the tables satisfy the bound.
static func error(path: String, ct: PackedFloat64Array, cp: PackedFloat64Array, cp_floor: float) -> String:
	var result := check(ct, cp, cp_floor)
	if result.ok:
		return ""
	if not is_finite(float(result.margin)):
		return "%s: Ct/Cp extrapolation beyond J = %.4f makes thrust work exceed shaft power without bound (Cp - J·Ct must stay >= 0)" \
			% [path, float(result.j)]
	return "%s: thrust work exceeds shaft power at J = %.4f (Cp - J·Ct = %.6f, efficiency %.4f); the steady axial energy balance needs Cp >= J·Ct" \
		% [path, float(result.j), float(result.margin), float(result.efficiency)]


static func _margin(ct: PackedFloat64Array, cp: PackedFloat64Array, cp_floor: float, j: float) -> float:
	return Propulsion.coefficient(cp, j, cp_floor) - j * Propulsion.coefficient(ct, j, Propulsion.CT_FLOOR)


## Ends of [lo, hi] plus the interior stationary point of g when it is a minimum (Ct slope a < 0).
static func _interval_candidates(ct: PackedFloat64Array, cp: PackedFloat64Array, cp_floor: float, lo: float,
		hi: float) -> Array[float]:
	var out: Array[float] = [lo, hi]
	var ct_lo := Propulsion.coefficient(ct, lo, Propulsion.CT_FLOOR)
	var a := (Propulsion.coefficient(ct, hi, Propulsion.CT_FLOOR) - ct_lo) / (hi - lo)
	if a < 0.0:
		var b := ct_lo - a * lo
		var c := (Propulsion.coefficient(cp, hi, cp_floor) - Propulsion.coefficient(cp, lo, cp_floor)) / (hi - lo)
		var stationary := (c - b) / (2.0 * a)
		if stationary > lo and stationary < hi:
			out.append(stationary)
	return out


## J where the linear tail beyond the last row reaches its floor min(floor, last value), or INF if it never does.
static func _tail_kink(table: PackedFloat64Array, floor_value: float) -> float:
	var n := table.size() / 2
	var ja := table[2 * n - 4]
	var jb := table[2 * n - 2]
	var last := table[2 * n - 1]
	var slope := (last - table[2 * n - 3]) / (jb - ja)
	var clamp_value := minf(floor_value, last)
	if slope < 0.0 and last > clamp_value:
		return jb + (clamp_value - last) / slope
	return INF
