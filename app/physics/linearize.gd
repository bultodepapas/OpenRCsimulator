# Linearization and eigenvalues for flight-mode analysis (D8a). 64-bit floats only (guarded): matrices are Arrays of
# PackedFloat64Array rows; complex numbers are [re, im] pairs (Godot's Vector2 is 32-bit).
# Eigenvalues of small matrices: characteristic polynomial (Faddeev–LeVerrier, exact for n ≤ 6 in practice),
# roots by Durand–Kerner with a Newton polish. Good to ~1e-10 for the well-separated modes of an airplane.
extends RefCounted

const M := preload("res://physics/math3d.gd")


## Central-difference Jacobian of f: R^n → R^n at x0. Returns rows: J[i][k] = ∂f_i/∂x_k.
static func jacobian(f: Callable, x0: PackedFloat64Array, h := 1e-6) -> Array:
	var n := x0.size()
	var cols := []
	for k in n:
		var xp := x0.duplicate()
		var xm := x0.duplicate()
		xp[k] += h
		xm[k] -= h
		var fp: PackedFloat64Array = f.call(xp)
		var fm: PackedFloat64Array = f.call(xm)
		var col := PackedFloat64Array()
		col.resize(n)
		for i in n:
			col[i] = (fp[i] - fm[i]) / (2.0 * h)
		cols.append(col)
	var rows := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		for k in n:
			row[k] = cols[k][i]
		rows.append(row)
	return rows


static func submatrix(a: Array, idx: Array) -> Array:
	var out := []
	for i in idx:
		var row := PackedFloat64Array()
		for k in idx:
			row.append(a[i][k])
		out.append(row)
	return out


static func _matmul(a: Array, b: Array) -> Array:
	var n := a.size()
	var out := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		for k in n:
			var acc := 0.0
			for j in n:
				acc += a[i][j] * b[j][k]
			row[k] = acc
		out.append(row)
	return out


## Characteristic polynomial det(λI − A) = λ^n + c[n−1]·λ^(n−1) + … + c[0]. Returns [c0, …, c(n−1), 1].
static func char_poly(a: Array) -> PackedFloat64Array:
	var n := a.size()
	var c := PackedFloat64Array()
	c.resize(n + 1)
	c[n] = 1.0
	var m := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		m.append(row)
	for k in range(1, n + 1):
		# M_k = A·M_(k−1) + c(n−k+1)·I ; c(n−k) = −tr(A·M_k) / k
		var am := _matmul(a, m)
		for i in n:
			am[i][i] += c[n - k + 1]
		m = am
		var amk := _matmul(a, m)
		var tr := 0.0
		for i in n:
			tr += amk[i][i]
		c[n - k] = -tr / k
	return c


static func _cmul(a: Array, b: Array) -> Array:
	return [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]]


static func _cdiv(a: Array, b: Array) -> Array:
	var d: float = b[0] * b[0] + b[1] * b[1]
	return [(a[0] * b[0] + a[1] * b[1]) / d, (a[1] * b[0] - a[0] * b[1]) / d]


static func _peval(c: PackedFloat64Array, z: Array) -> Array:
	var acc := [c[c.size() - 1], 0.0]
	for i in range(c.size() - 2, -1, -1):
		acc = _cmul(acc, z)
		acc[0] += c[i]
	return acc


static func _pderiv(c: PackedFloat64Array) -> PackedFloat64Array:
	var d := PackedFloat64Array()
	for i in range(1, c.size()):
		d.append(c[i] * i)
	return d


## Roots of a monic polynomial [c0, …, 1] as [re, im] pairs (Durand–Kerner, then Newton polish).
static func roots(c: PackedFloat64Array) -> Array:
	var n := c.size() - 1
	var bound := 1.0
	for i in n:
		bound = maxf(bound, 1.0 + absf(c[i]))
	var z := []
	var seed := [0.4, 0.9]
	var p := [1.0, 0.0]
	for i in n:
		p = _cmul(p, seed)
		z.append([p[0] * bound, p[1] * bound])
	for iteration in 500:
		var moved := 0.0
		for i in n:
			var den := [1.0, 0.0]
			for j in n:
				if j != i:
					den = _cmul(den, [z[i][0] - z[j][0], z[i][1] - z[j][1]])
			var step := _cdiv(_peval(c, z[i]), den)
			z[i] = [z[i][0] - step[0], z[i][1] - step[1]]
			moved = maxf(moved, absf(step[0]) + absf(step[1]))
		if moved < 1e-14 * bound:
			break
	var d := _pderiv(c)
	for i in n:
		for k in 3:
			var dp := _peval(d, z[i])
			if dp[0] == 0.0 and dp[1] == 0.0:
				break
			var step := _cdiv(_peval(c, z[i]), dp)
			z[i] = [z[i][0] - step[0], z[i][1] - step[1]]
	return z


static func eigenvalues(a: Array) -> Array:
	return roots(char_poly(a))


## Splits eigenvalues into oscillatory modes [{ wn (rad/s), zeta }] (one per conjugate pair, fastest first)
## and real roots (most negative first).
static func classify(ev: Array, imag_tol := 1e-7) -> Dictionary:
	var osc := []
	var real := []
	for e in ev:
		if absf(e[1]) > imag_tol:
			if e[1] > 0.0:
				var wn := M.sqrt_(e[0] * e[0] + e[1] * e[1])
				osc.append({ wn = wn, zeta = -e[0] / wn })
		else:
			real.append(e[0])
	osc.sort_custom(func(a, b): return a.wn > b.wn)
	real.sort()
	return { oscillatory = osc, real = real }
