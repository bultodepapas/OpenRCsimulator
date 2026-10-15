# SF-06: the law property harness. A library, not a test program: tests/test_sf_law_properties.gd registers every
# load law and runs these checks. A law is `law(v_body: float64[3], rates_body: float64[3]) -> float64[n]`
# (six body loads, or a state derivative). Every check returns {ok, worst, detail}; `scale` normalizes the law's
# output (a reference force, or an acceleration scale for a derivative). 64-bit floats only.
#
# Properties:
#   continuity  — two Cartesian approaches to the same limit point converge to the same loads (the 2026-10-14
#                 audit's F01 probe): |law(L + εa) − law(L + εb)| / scale ≤ tol at ε/V = 1e-9, finite throughout.
#   finite      — finite output over a sample set that includes rest and vanishing speeds.
#   rest        — zero output at rest (laws that only react to relative motion).
#   galilean    — the law sees only air-relative motion: law(v, wind 0) == law(v + w, wind w) with identity attitude.
#   mirror      — lateral symmetry: v_y, p, r → −v_y, −p, −r gives [Fx, −Fy, Fz, −Mx, My, −Mz].
#   passive     — dissipative axes never do positive work: F_i · v_i ≤ tol · scale · |v_i| on the named axes.
#   passive_translational — the whole load never does positive translational work at zero rates.
extends RefCounted

const EPSILON_RATIOS: Array = [1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9]


static func continuity(law: Callable, limit: PackedFloat64Array, a: PackedFloat64Array, b: PackedFloat64Array,
		rates: PackedFloat64Array, scale: float, tol: float = 1e-6) -> Dictionary:
	var speed: float = maxf(_norm(limit), 1.0)
	var trace: PackedFloat64Array = PackedFloat64Array()
	for ratio: float in EPSILON_RATIOS:
		var eps: float = speed * ratio
		var fa: PackedFloat64Array = law.call(_axpy(limit, eps, a), rates)
		var fb: PackedFloat64Array = law.call(_axpy(limit, eps, b), rates)
		if not _finite(fa) or not _finite(fb) or fa.size() != fb.size() or fa.is_empty():
			return {ok = false, worst = INF, detail = "nonfinite or malformed output at eps/V " + sci(ratio)}
		trace.append(_max_abs_diff(fa, fb) / scale)
	var last: float = trace[trace.size() - 1]
	return {ok = last <= tol, worst = last, detail = "normalized difference per eps/V: " + _fmt(trace)}


static func finite(law: Callable, samples: Array) -> Dictionary:
	for sample: Array in samples:
		var out: PackedFloat64Array = law.call(sample[0], sample[1])
		if out.is_empty() or not _finite(out):
			return {ok = false, worst = INF, detail = "nonfinite at v=%s rates=%s" % [str(sample[0]), str(sample[1])]}
	return {ok = true, worst = 0.0, detail = ""}


static func rest(law: Callable, scale: float, tol: float = 1e-12) -> Dictionary:
	var out: PackedFloat64Array = law.call(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	if out.is_empty() or not _finite(out):
		return {ok = false, worst = INF, detail = "nonfinite at rest"}
	var worst: float = _max_abs(out) / scale
	return {ok = worst <= tol, worst = worst, detail = "normalized load at rest " + sci(worst)}


## law_wind(v_body, rates, wind_ned) -> loads; identity attitude makes body and NED axes coincide.
static func galilean(law_wind: Callable, samples: Array, winds: Array, scale: float, tol: float = 1e-9) -> Dictionary:
	var worst: float = 0.0
	var calm: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	for sample: Array in samples:
		for wind: PackedFloat64Array in winds:
			var still: PackedFloat64Array = law_wind.call(sample[0], sample[1], calm)
			var moving: PackedFloat64Array = law_wind.call(_axpy(sample[0], 1.0, wind), sample[1], wind)
			if not _finite(still) or not _finite(moving) or still.size() != moving.size():
				return {ok = false, worst = INF, detail = "nonfinite under a uniform wind"}
			worst = maxf(worst, _max_abs_diff(still, moving) / scale)
	return {ok = worst <= tol, worst = worst, detail = "worst normalized Galilean difference " + sci(worst)}


static func mirror(law: Callable, samples: Array, scale: float, tol: float = 1e-9) -> Dictionary:
	var worst: float = 0.0
	for sample: Array in samples:
		var v: PackedFloat64Array = sample[0]
		var w: PackedFloat64Array = sample[1]
		var direct: PackedFloat64Array = law.call(v, w)
		var mirrored: PackedFloat64Array = law.call(PackedFloat64Array([v[0], -v[1], v[2]]), PackedFloat64Array([-w[0], w[1], -w[2]]))
		if direct.size() != 6 or mirrored.size() != 6 or not _finite(direct) or not _finite(mirrored):
			return {ok = false, worst = INF, detail = "mirror needs finite six-value loads"}
		var signs: PackedFloat64Array = PackedFloat64Array([1.0, -1.0, 1.0, -1.0, 1.0, -1.0])
		for i in 6:
			worst = maxf(worst, absf(direct[i] - signs[i] * mirrored[i]) / scale)
	return {ok = worst <= tol, worst = worst, detail = "worst normalized mirror asymmetry " + sci(worst)}


static func passive(law: Callable, samples: Array, axes: PackedInt64Array, scale: float, tol: float = 1e-9) -> Dictionary:
	var worst: float = -INF
	for sample: Array in samples:
		var v: PackedFloat64Array = sample[0]
		var out: PackedFloat64Array = law.call(v, sample[1])
		if out.size() < 3 or not _finite(out):
			return {ok = false, worst = INF, detail = "nonfinite loads"}
		for axis: int in axes:
			var power: float = out[axis] * v[axis]
			worst = maxf(worst, power / (scale * maxf(absf(v[axis]), 1.0)))
	return {ok = worst <= tol, worst = worst, detail = "worst normalized positive work " + sci(worst)}


## Translational power of the whole load: F · v ≤ tol · scale · |v|. Aerodynamic lift does no work and drag
## dissipates, so a passive aerodynamic law never does positive translational work (zero rates, no thrust).
static func passive_translational(law: Callable, samples: Array, scale: float, tol: float = 1e-7) -> Dictionary:
	var worst: float = -INF
	for sample: Array in samples:
		var v: PackedFloat64Array = sample[0]
		var out: PackedFloat64Array = law.call(v, PackedFloat64Array([0.0, 0.0, 0.0]))
		if out.size() < 3 or not _finite(out):
			return {ok = false, worst = INF, detail = "nonfinite loads"}
		var power: float = out[0] * v[0] + out[1] * v[1] + out[2] * v[2]
		worst = maxf(worst, power / (scale * maxf(_norm(v), 1.0)))
	return {ok = worst <= tol, worst = worst, detail = "worst normalized positive translational work " + sci(worst)}


## Deterministic sample set: rest, vanishing speeds, and seeded random velocities/rates.
static func samples(seed_value: int, count: int, speed: float, rate: float) -> Array:
	var out: Array = []
	out.append([PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0])])
	for tiny: float in [1e-12, 1e-6]:
		out.append([PackedFloat64Array([tiny, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0])])
		out.append([PackedFloat64Array([0.0, tiny, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0])])
		out.append([PackedFloat64Array([0.0, 0.0, tiny]), PackedFloat64Array([0.0, 0.0, 0.0])])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _i in count:
		out.append([
			PackedFloat64Array([rng.randf_range(-speed, speed), rng.randf_range(-speed, speed), rng.randf_range(-speed, speed)]),
			PackedFloat64Array([rng.randf_range(-rate, rate), rng.randf_range(-rate, rate), rng.randf_range(-rate, rate)]),
		])
	return out


## Scientific notation for reports; GDScript's % has no e-format.
static func sci(x: float) -> String:
	if not is_finite(x):
		return str(x)
	if x == 0.0:
		return "0"
	var exponent: int = int(floor(log(absf(x)) / log(10.0)))
	var mantissa: float = x / pow(10.0, exponent)
	if absf(mantissa) >= 10.0:
		mantissa /= 10.0
		exponent += 1
	return "%.2fe%d" % [mantissa, exponent]


static func _axpy(base: PackedFloat64Array, k: float, direction: PackedFloat64Array) -> PackedFloat64Array:
	var out := base.duplicate()
	for i in out.size():
		out[i] += k * direction[i]
	return out


static func _norm(v: PackedFloat64Array) -> float:
	var sum := 0.0
	for x in v:
		sum += x * x
	return sqrt(sum)


static func _finite(values: PackedFloat64Array) -> bool:
	for x in values:
		if not is_finite(x):
			return false
	return true


static func _max_abs(values: PackedFloat64Array) -> float:
	var worst := 0.0
	for x in values:
		worst = maxf(worst, absf(x))
	return worst


static func _max_abs_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


static func _fmt(values: PackedFloat64Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for x in values:
		parts.append(sci(x))
	return " ".join(parts)
