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
## the tail start); efficiency is J Ct / Cp at that point when Cp > 0, else NAN. One pass over the sorted breakpoints
## with monotone segment cursors: O(n log n) for n rows (a 524,289-row table is admitted in seconds).
static func check(ct: PackedFloat64Array, cp: PackedFloat64Array, cp_floor: float) -> Dictionary:
	var breaks := PackedFloat64Array([0.0])
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
	var ct_i := 1
	var cp_i := 1
	var previous := NAN
	var ct_prev := NAN
	var cp_prev := NAN
	for j: float in breaks:
		if j == previous:
			continue
		var ct_at := _value(ct, j, Propulsion.CT_FLOOR, ct_i)
		var cp_at := _value(cp, j, cp_floor, cp_i)
		ct_i = int(ct_at[1])
		cp_i = int(cp_at[1])
		var margin: float = cp_at[0] - j * ct_at[0]
		if margin < worst:
			worst = margin
			worst_j = j
		if is_finite(previous):
			# No row lies strictly inside (previous, j): both coefficients are linear there.
			var a: float = (ct_at[0] - ct_prev) / (j - previous)
			if a < 0.0:
				var b: float = ct_prev - a * previous
				var c: float = (cp_at[0] - cp_prev) / (j - previous)
				var stationary := (c - b) / (2.0 * a)
				if stationary > previous and stationary < j:
					var inside: float = _value(cp, stationary, cp_floor, cp_i)[0] \
						- stationary * _value(ct, stationary, Propulsion.CT_FLOOR, ct_i)[0]
					if inside < worst:
						worst = inside
						worst_j = stationary
		previous = j
		ct_prev = ct_at[0]
		cp_prev = cp_at[0]
	# The last breakpoint starts an unbounded piece where both coefficients are linear (or clamped constant).
	var tail := previous
	var a_tail: float = _value(ct, tail + 1.0, Propulsion.CT_FLOOR, ct_i)[0] - ct_prev
	var b_tail: float = ct_prev - a_tail * tail
	var c_tail: float = _value(cp, tail + 1.0, cp_floor, cp_i)[0] - cp_prev
	if a_tail > 0.0 or (a_tail == 0.0 and c_tail - b_tail < 0.0):
		worst = -INF
		worst_j = tail
	elif a_tail < 0.0:
		var stationary := (c_tail - b_tail) / (2.0 * a_tail)
		if stationary > tail:
			var margin_stationary: float = _value(cp, stationary, cp_floor, cp_i)[0] \
				- stationary * _value(ct, stationary, Propulsion.CT_FLOOR, ct_i)[0]
			if margin_stationary < worst:
				worst = margin_stationary
				worst_j = stationary
	var cp_worst := Propulsion.coefficient(cp, worst_j, cp_floor)
	return {ok = is_finite(worst) and worst >= -TOLERANCE, j = worst_j, margin = worst,
		efficiency = worst_j * Propulsion.coefficient(ct, worst_j, Propulsion.CT_FLOOR) / cp_worst if cp_worst > 0.0 else NAN}


## Propulsion.coefficient's exact arithmetic, searching rows forward from segment `start` (valid for any J at or beyond
## the J that returned `start`). Returns [value, segment] so a caller walking increasing J keeps the search linear.
static func _value(table: PackedFloat64Array, j: float, floor_value: float, start: int) -> Array:
	var n := table.size() / 2
	if j <= table[0]:
		return [table[1], 1]
	var i := maxi(start, 1)
	while i < n and j > table[2 * i]:
		i += 1
	if i < n:
		var j0 := table[2 * i - 2]
		var j1 := table[2 * i]
		return [lerpf(table[2 * i - 1], table[2 * i + 1], (j - j0) / (j1 - j0)), i]
	var ja := table[2 * n - 4]
	var jb := table[2 * n - 2]
	var slope := (table[2 * n - 1] - table[2 * n - 3]) / (jb - ja)
	return [maxf(minf(floor_value, table[2 * n - 1]), table[2 * n - 1] + slope * (j - jb)), i]


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
